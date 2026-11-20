#!/usr/bin/env python3
"""validate.py — R5-11/13: unchanged INT8 models on APK media and JVM farm renders.

Run under flock /tmp/edrv32-sw-build.lock. Dataset candidates failing acceptance
are excluded; all four user videos remain packaged regardless of their scores.
Clock: offline host; intermediate frames and measurements stay in build/demo-app/.
"""
from collections import Counter
import importlib.util
import io
import json
from pathlib import Path
import sys

import cv2
import numpy as np
from PIL import Image, ImageOps
import torch

from models_eval import integer
from quantize import prepare_image

ROOT = Path(__file__).resolve().parent
BUILD = Path('build/demo-app')
ASSETS = BUILD / 'assets'
OUT = Path('outputs/demo-app')
spec = importlib.util.spec_from_file_location('kit_validation', ROOT.parent / 'kit/validate.py')
kit = importlib.util.module_from_spec(spec)
spec.loader.exec_module(kit)
kit.OUT = OUT
NAMES = ['张开', '握拳', '剪刀手', '指点', '爪形', '抓紧', '八', 'OK', '点赞', '倒赞', '三', '四', '六']


class Model:
    def __init__(self, name):
        self.plan, self.rows, self.memory, self.registers, self.heads, self.names = kit.setup(name)
        if name == 'detect':
            self.names = self.names | {0: 'person', 14: 'bird', 16: 'dog', 17: 'horse',
                                       18: 'sheep', 19: 'cow', 15: 'cat', 13: 'bench',
                                       58: 'potted plant',
                                       25: 'umbrella', 24: 'backpack', 11: 'stop sign'}

    def run(self, frame, name):
        photograph = kit.photograph(frame)
        path = BUILD / 'frames' / (name + '.png')
        cv2.imwrite(str(path), photograph)
        result = integer(self.memory, self.registers, self.plan, self.rows,
                         self.heads, prepare_image(path))
        boxes, scores, ids, points = result
        boxes = (boxes - [0, 12, 0, 12]) * 2
        points = points.copy()
        points[:, :, :2] = (points[:, :, :2] - [0, 12]) * 2
        for box, score, cls, person in zip(boxes, scores, ids, points):
            x1, y1, x2, y2 = np.int32(box)
            cv2.rectangle(photograph, (x1, y1), (x2, y2), (80, 255, 180), 2)
            cv2.putText(photograph, f'{self.names.get(int(cls), str(cls))} {score:.2f}',
                        (x1, max(18, y1-5)), cv2.FONT_HERSHEY_SIMPLEX, .5,
                        (80, 255, 180), 1, cv2.LINE_AA)
            for p in person:
                if p[2] > .5:
                    cv2.circle(photograph, tuple(np.int32(p[:2])), 3, (60, 180, 255), -1)
        return boxes, scores, ids, points, photograph


def fitted(path):
    image = ImageOps.pad(Image.open(path).convert('RGB'), (1280, 720), color='black')
    encoded = io.BytesIO()
    image.save(encoded, format='JPEG', quality=92)
    return cv2.imdecode(np.frombuffer(encoded.getvalue(), np.uint8), cv2.IMREAD_COLOR)


def overlap(a, b):
    area = np.maximum(0, np.minimum(a[2:], b[2:]) - np.maximum(a[:2], b[:2])).prod()
    return area / (np.prod(a[2:]-a[:2]) + np.prod(b[2:]-b[:2]) - area)


def projected_box(box, width, height):
    ratio = min(1280 / width, 720 / height)
    pad = np.array([(1280-round(width*ratio))//2, (720-round(height*ratio))//2])
    x, y, w, h = box
    corners = np.array([[x, y], [x+w, y], [x+w, y+h], [x, y+h]], dtype=np.float32)
    corners = (corners * ratio + pad) * [2000/1280, 1125/720]
    transformed = cv2.perspectiveTransform(np.float32([corners]), kit.MATRIX)[0]
    return np.r_[transformed.min(0), transformed.max(0)]


def select_coco():
    data = json.loads((BUILD / 'coco-candidates.json').read_text())
    mapping = {row['id']: i for i, row in enumerate(data['categories'])}
    names = {i: row['name'] for i, row in enumerate(data['categories'])}
    licenses = {row['id']: row for row in data['licenses']}
    model = Model('detect')
    model.names = names
    chosen, results, samples, covered = [], [], [], set()
    candidates = data['images'][:]
    while candidates and len(chosen) < 24:
        image = max(candidates, key=lambda im: len(
            {a['category_id'] for a in im['annotations']} - covered))
        candidates.remove(image)
        frame = fitted(image['path'])
        boxes, scores, ids, _, annotated = model.run(frame, 'coco-'+str(image['id']))
        truth = image['annotations']
        targets = [projected_box(a['bbox'], image['width'], image['height']) for a in truth]
        large = {i for i, a in enumerate(truth)
                 if a['area'] >= image['width']*image['height']*.02}
        used = set()
        false = 0
        for box, cls in zip(boxes, ids):
            matches = [i for i, a in enumerate(truth) if i not in used and
                       mapping[a['category_id']] == cls and overlap(box, targets[i]) >= .5]
            if matches:
                used.add(max(matches, key=lambda i: overlap(box, targets[i])))
            else:
                false += 1
        recalled = len(large & used)
        passed = recalled / len(large) >= .8 and false <= 2
        result = dict(id=image['id'], recalled=recalled, targets=len(large),
                      false_positives=false, passed=passed)
        results.append(result)
        print('COCO', result, flush=True)
        if passed:
            covered.update(a['category_id'] for a in truth)
            name = 'coco-'+str(image['id'])
            license = licenses[image['license']]
            item = dict(id=name, name='COCO · '+str(image['id']), scene='detect',
                        original=image['path'], path='images/'+name+'.jpg', type='image/jpeg',
                        poster='posters/'+name+'.jpg', author='COCO 官方图像；原作者见来源页',
                        source='https://www.flickr.com/photo.gne?id='+
                        Path(image['flickr_url']).name.split('_')[0],
                        license={4: 'CC BY 2.0', 5: 'CC BY-SA 2.0',
                                 7: 'No known copyright restrictions',
                                 8: 'United States Government Work'}[image['license']],
                        license_url=license['url'], annotations=image['annotations'],
                        original_width=image['width'], original_height=image['height'])
            chosen.append(item)
            samples.append((name, annotated))
    (BUILD / 'coco-results.json').write_text(json.dumps(results, indent=2))
    (BUILD / 'coco-selected.json').write_text(json.dumps(chosen, indent=2))
    kit.contact_sheet('coco', samples)
    if len(chosen) != 24:
        raise SystemExit(f'FAIL: only {len(chosen)} permitted COCO pictures passed')
    print('PASS COCO', len(chosen), 'images;', len(covered), 'classes', flush=True)
    return chosen


def select_hagrid():
    model = Model('gesture')
    candidates = json.loads((BUILD / 'hagrid-candidates.json').read_text())
    counts = Counter()
    chosen, results, samples = [], [], []
    for image in candidates:
        cls = image['cls']
        if counts[cls] >= 2:
            continue
        name = 'hagrid-'+image['id']
        _, scores, ids, _, annotated = model.run(fitted(image['path']), name)
        passed = ids.tolist() == [cls]
        results.append(dict(id=name, expected=cls, classes=ids.tolist(), passed=passed))
        print('HaGRID', name, cls, ids.tolist(), passed, flush=True)
        if passed:
            counts[cls] += 1
            chosen.append(dict(id=name, name=NAMES[cls]+' · HaGRID '+str(counts[cls]),
                scene='gesture', original=image['path'], path='images/'+name+'.jpg',
                type='image/jpeg', poster='posters/'+name+'.jpg', expected=cls,
                author='HaGRID 项目（hukenovs/hagrid）', source='https://github.com/hukenovs/hagrid',
                license='Public license with attribution and conditions reserved',
                license_url='https://github.com/hukenovs/hagrid/blob/master/license/en_us.pdf'))
            samples.append((kit.GESTURES[cls]+' '+str(counts[cls]), annotated))
        if all(counts[i] == 2 for i in range(13)):
            break
    (BUILD / 'hagrid-results.json').write_text(json.dumps(results, indent=2))
    (BUILD / 'hagrid-selected.json').write_text(json.dumps(chosen, indent=2))
    kit.contact_sheet('hagrid', samples)
    if any(counts[i] != 2 for i in range(13)):
        raise SystemExit('FAIL: HaGRID does not have two passing images per gesture')
    print('PASS HaGRID 26/26', flush=True)
    return chosen


def user_videos():
    results, samples = [], []
    clips = json.loads((ROOT / 'user_clips.json').read_text())
    for scene, model_name in [('traffic', 'detect'), ('dance', 'pose')]:
        model = Model(model_name)
        for clip in clips:
            if clip['scene'] != scene:
                continue
            capture = cv2.VideoCapture(str(ASSETS / 'videos' / (clip['id']+'.mp4')))
            frames = []
            for second in range(clip['duration']):
                capture.set(cv2.CAP_PROP_POS_MSEC, second*1000)
                ok, frame = capture.read()
                if not ok:
                    raise RuntimeError('Cannot decode '+clip['id'])
                _, scores, ids, points, annotated = model.run(frame, clip['id']+f'-{second:02d}')
                visible = [int(np.count_nonzero(p[:, 2] > .5)) for p in points]
                if scene == 'traffic':
                    passed = sum(int(cls) in (1, 2, 3, 5, 7) for cls in ids) >= 2
                else:
                    passed = len(ids) == clip['people'] and all(n >= 12 for n in visible)
                frames.append(dict(second=second, classes=ids.tolist(), points=visible,
                                   passed=bool(passed)))
                if second % 4 == 0:
                    samples.append((clip['id']+' '+str(second)+'s', annotated))
                print('user', clip['id'], second, bool(passed), visible, flush=True)
            capture.release()
            results.append(clip | dict(good=sum(f['passed'] for f in frames),
                                       samples=len(frames), frames=frames))
        del model
    (BUILD / 'user-video-results.json').write_text(json.dumps(results, ensure_ascii=False, indent=2))
    kit.contact_sheet('user-videos', samples)


def visible_targets(actors):
    """Alpha contours with frame clipping and nearer full-body occlusion removed."""
    foreground = np.zeros((1125, 2000), dtype=bool)
    targets = []
    for actor in reversed(actors):
        width, height = int(actor['width']), int(actor['height'])
        image = Image.open(ASSETS / actor['sprite']).resize((width, height))
        if actor['facing'] < 0:
            image = ImageOps.mirror(image)
        mask = np.asarray(image.getchannel('A')) >= 64
        x, y = int(actor['x']-actor['width']/2), int(actor['y']-actor['height']/2)
        left, top, right, bottom = max(0, x), max(0, y), min(2000, x+width), min(1125, y+height)
        # Scripted off-screen actors still occlude nothing and have zero exposed area.
        if left >= right or top >= bottom:
            continue
        part = mask.copy()
        if actor['part'] == 'head':
            part[int(height*.24):] = False
            part[:, :int(width*.25)] = False
            part[:, int(width*.75):] = False
        parts = [(actor['category'], part)]
        for category, contour in parts:
            exposed = contour[top-y:bottom-y, left-x:right-x] & ~foreground[top:bottom, left:right]
            ratio = float(np.count_nonzero(exposed) / np.count_nonzero(contour))
            ys, xs = np.nonzero(contour[top-y:bottom-y, left-x:right-x])
            box = None if len(xs) == 0 else projected_box(
                [left+int(xs.min()), top+int(ys.min()), int(xs.max()-xs.min()+1),
                 int(ys.max()-ys.min()+1)], 2000, 1125).tolist()
            targets.append(dict(id=actor['id'], category=category, exposed=ratio, box=box))
        foreground[top:bottom, left:right] |= mask[top-y:bottom-y, left-x:right-x]
    return targets


def counted_detections(boxes, ids, targets):
    kept, ignored = [], []
    for i, (box, category) in enumerate(zip(boxes, ids)):
        matches = [t for t in targets if t['category'] == int(category) and t['box'] is not None]
        match = max(matches, key=lambda t: overlap(box, np.array(t['box']))) if matches else None
        if (match is not None and match['exposed'] < .7 and
                overlap(box, np.array(match['box'])) >= .5):
            ignored.append(i)
        else:
            kept.append(int(category))
    return Counter(kept), ignored


def farm():
    model = Model('detect')
    rows = json.loads((BUILD / 'farm-frames.json').read_text())
    results, samples = [], []
    static = people = absent = clean = 0
    nstatic = npeople = nabsent = 0
    expected = Counter({19: 2, 17: 1, 18: 3, 14: 3})
    for i, row in enumerate(rows):
        frame = cv2.imread(str(BUILD / 'farm-frames' / row['file']))
        boxes, scores, ids, _, annotated = model.run(frame, row['file'][:-4])
        visibility = visible_targets(row['targets'])
        counts, ignored = counted_detections(boxes, ids, visibility)
        person_visible = any(t['category'] == 0 and t['exposed'] >= .7 for t in visibility)
        if row['static']:
            nstatic += 1
            static += all(counts[c] == count for c, count in expected.items())
        if person_visible:
            npeople += 1
            people += counts[0] > 0
        else:
            nabsent += 1
            absent += counts[0] == 0
        clean += not (set(counts) - {0, 14, 17, 18, 19})
        results.append(row | dict(counts=dict(counts), visibility=visibility, ignored=ignored,
                                  boxes=boxes.tolist(),
                                  scores=scores.tolist(), classes=ids.tolist()))
        if i % 4 == 0:
            samples.append((row['file'][:-4], annotated))
        print('farm', row['file'], dict(counts), flush=True)
    summary = dict(static=[static, nstatic], person=[people, npeople],
                   no_person=[absent, nabsent], classes_only=[clean, len(rows)],
                   ignored=sum(len(r['ignored']) for r in results))
    (BUILD / 'farm-results.json').write_text(json.dumps(dict(summary=summary, frames=results),
                                                       indent=2))
    kit.contact_sheet('farm', samples)
    print('farm summary', summary, flush=True)
    if not (static/nstatic >= .9 and people/npeople >= .9 and
            absent/nabsent >= .98 and clean/len(rows) >= .95):
        raise SystemExit('FAIL: farm acceptance')
    print('PASS farm', flush=True)


def site():
    model = Model('helmet')
    rows = json.loads((BUILD / 'site-frames.json').read_text())
    results, samples = [], []
    good = Counter()
    total = Counter()
    for i, row in enumerate(rows):
        frame = cv2.imread(str(BUILD / 'site-frames' / row['file']))
        boxes, scores, ids, _, annotated = model.run(frame, row['file'][:-4])
        visibility = visible_targets(row['targets'])
        measured, ignored = counted_detections(boxes, ids, visibility)
        counts = Counter({model.names[cls]: count for cls, count in measured.items()})
        row['head'] = sum(t['category'] == 1 and t['exposed'] >= .7 for t in visibility)
        group = 'static' if row['static'] else 'warning' if row['head'] else 'clear'
        passed = (counts['helmet'] == 4 and counts['head'] == 2) if row['static'] else (
            counts['head'] >= 1 if row['head'] else counts['head'] == 0)
        good[group] += passed
        total[group] += 1
        results.append(row | dict(counts=dict(counts), ignored=ignored, visibility=visibility,
                                  passed=passed, boxes=boxes.tolist(),
                                  scores=scores.tolist(), classes=ids.tolist()))
        if i < 25 or i % 4 == 0:
            samples.append((row['file'][:-4] + ' ' + str(dict(counts)), annotated))
        print('site', row['file'], dict(counts), passed, flush=True)
    summary = {group: [good[group], total[group]] for group in ('static', 'warning', 'clear')}
    (BUILD / 'site-results.json').write_text(json.dumps(dict(summary=summary, frames=results),
                                                       indent=2))
    kit.contact_sheet('site', samples)
    print('site summary', summary, 'ignored', sum(len(r['ignored']) for r in results), flush=True)
    if any(good[group] / total[group] < .9 for group in summary):
        raise SystemExit('FAIL: site acceptance')
    print('PASS site', flush=True)


def main():
    torch.set_num_threads(1)
    (BUILD / 'frames').mkdir(parents=True, exist_ok=True)
    OUT.mkdir(parents=True, exist_ok=True)
    for stage in (sys.argv[1:] or ['data', 'user', 'farm']):
        if stage == 'data':
            chosen = select_coco() + select_hagrid()
            (BUILD / 'selected-data.json').write_text(json.dumps(chosen, ensure_ascii=False, indent=2))
        elif stage == 'user':
            user_videos()
        elif stage == 'farm':
            farm()
        elif stage == 'site':
            site()
        else:
            raise ValueError(stage)


if __name__ == '__main__':
    main()
