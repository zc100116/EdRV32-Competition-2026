#!/usr/bin/env python3
"""prepare_assets.py — R5-12/13: package local licensed media, no network access.

Run ffmpeg work under /tmp/edrv32-sw-build.lock. Generated assets stay in build/.
Clock: offline host. Positional stages allow preparing art before media selection.
"""
import json
from pathlib import Path
import shutil
import subprocess
import sys

from PIL import Image, ImageOps

ROOT = Path(__file__).resolve().parent
KIT = ROOT.parent / 'kit'
BUILD = Path('build/demo-app')
ASSETS = BUILD / 'assets'
USER = Path('/home/workspace/orca/workspaces/EdRV32-Competition-2026/b3-int/build/card98')
FFMPEG = Path.home() / '.local/opt/video/bin/ffmpeg'


def art():
    output = ASSETS / 'farm'
    output.mkdir(parents=True, exist_ok=True)
    shutil.copy2(ROOT / 'art/background.jpg', output / 'background.jpg')
    background = Image.open(ROOT / 'art/background.jpg')
    background.crop((1700, 0, 2000, 160)).save(output / 'tree.webp', lossless=True)
    for source in (ROOT / 'art').glob('*-sheet.webp'):
        image = Image.open(source)
        width, height = image.size[0] // 2, image.size[1] // 2
        frames = [image.crop((x*width, y*height, (x+1)*width, (y+1)*height))
                  for y in range(2) for x in range(2)]
        # Crop to the visible body, excluding faint transparent generation fringes.
        bounds = [f.getchannel('A').point(lambda a: 255 if a >= 64 else 0).getbbox()
                  for f in frames]
        canvas_width = max(b[2]-b[0] for b in bounds)
        canvas_height = max(b[3]-b[1] for b in bounds)
        print(source.stem, 'aspect', canvas_width / canvas_height)
        for i, (frame, own) in enumerate(zip(frames, bounds)):
            sprite = Image.new('RGBA', (canvas_width, canvas_height))
            cutout = frame.crop(own)
            sprite.paste(cutout, ((sprite.width-cutout.width)//2,
                                  sprite.height-cutout.height))
            sprite.thumbnail((620, 620))
            sprite.save(output / f'{source.stem[:-6]}-{i}.webp', lossless=True)

    for name in ('cow2', 'chicken'):
        image = Image.open(ROOT / 'art' / (name+'.webp'))
        bounds = image.getchannel('A').point(lambda a: 255 if a >= 64 else 0).getbbox()
        image = image.crop(bounds)
        print(name, 'aspect', image.width / image.height)
        image.thumbnail((620, 620))
        image.save(output / (name+'-3.webp'), lossless=True)



def site():
    output = ASSETS / 'site'
    output.mkdir(parents=True, exist_ok=True)
    source = ROOT / 'art/site'
    shutil.copy2(source / 'background.jpg', output / 'background.jpg')
    sheets = [Image.open(source / (name + '-sheet.webp')) for name in ('head', 'helmet')]
    visitor = Image.open(source / 'visitor.webp')
    visitor = visitor.crop(visitor.getchannel('A').point(lambda a: 255 if a >= 64 else 0).getbbox())
    visitor.thumbnail((318, 490))
    canvas = Image.new('RGBA', (318, 490))
    canvas.paste(visitor, ((318-visitor.width)//2, 490-visitor.height))
    canvas.save(output / 'visitor.webp', lossless=True)
    wipe = Image.open(source / 'wipe.webp')
    wipe = wipe.crop(wipe.getchannel('A').point(lambda a: 255 if a >= 64 else 0).getbbox())
    wipe.thumbnail((318, 490))
    canvas = Image.new('RGBA', (318, 490))
    canvas.paste(wipe, ((318-wipe.width)//2, 490-wipe.height))
    canvas.save(output / 'wipe.webp', lossless=True)
    for i in range(6):
        x, y = i % 3, i // 3
        frames = [im.crop((x*512, y*512, (x+1)*512, (y+1)*512)) for im in sheets]
        bounds = [f.getchannel('A').point(lambda a: 255 if a >= 64 else 0).getbbox()
                  for f in frames]
        left = min(b[0] for b in bounds)
        top = min(b[1] for b in bounds)
        right = max(b[2] for b in bounds)
        bottom = max(b[3] for b in bounds)
        # Both states share one foot baseline, body scale and head position.
        height = bottom - top
        width = round(height * .65)
        for name, frame in zip(('head', 'helmet'), frames):
            sprite = Image.new('RGBA', (width, height))
            cutout = frame.crop((left, top, right, bottom))
            sprite.paste(cutout, ((width-cutout.width)//2, 0))
            sprite.save(output / f'{i}-{name}.webp', lossless=True)
        cap = frames[1].crop((180, 0, 300, 58))
        cap.save(output / f'{i}-cap.webp', lossless=True)
    sheets = [Image.open(source / name) for name in
              ('walk-sheet.webp', 'walk-helmet-sheet.webp')]
    cw, ch = sheets[0].width // 6, sheets[0].height // 2
    for i in range(6):
        for pose in range(2):
            frames = [im.crop((i*cw, pose*ch, (i+1)*cw, (pose+1)*ch)) for im in sheets]
            bounds = [f.getchannel('A').point(lambda a: 255 if a >= 64 else 0).getbbox()
                      for f in frames]
            left, top = min(b[0] for b in bounds), min(b[1] for b in bounds)
            right, bottom = max(b[2] for b in bounds), max(b[3] for b in bounds)
            for state, frame in zip(('head', 'helmet'), frames):
                body = frame.crop((left, top, right, bottom))
                body.thumbnail((318, 490))
                canvas = Image.new('RGBA', (318, 490))
                canvas.paste(body, ((318-body.width)//2, 490-body.height))
                canvas.save(output / f'{i}-{state}-walk-{pose}.webp', lossless=True)
                if i == 0 and state == 'head':
                    wipe = Image.open(output / 'wipe.webp')
                    wipe.paste(canvas.crop((0, 270, 318, 490)), (0, 270))
                    wipe.save(output / f'wipe-walk-{pose}.webp', lossless=True)
    poster = Image.open(output / 'background.jpg').convert('RGBA')
    positions = [(360, 385), (940, 360), (1530, 365), (520, 865), (1100, 865), (1680, 865)]
    for i, (x, y) in enumerate(positions):
        sprite = Image.open(output / f'{i}-{"helmet" if i < 4 else "head"}.webp')
        sprite = sprite.resize((318, 490), Image.Resampling.LANCZOS)
        poster.alpha_composite(sprite, (x-159, y-245))
    poster.convert('RGB').save(output / 'poster.jpg', quality=90)


def site_catalog(scenes):
    scene = next(s for s in scenes if s['id'] == 'helmet')
    scene['items'] = [dict(id='site', name='CAM-05 施工区', path='site/background.jpg',
        type='site', poster='site/poster.jpg', author='本项目 · imagegen 原创',
        source='原创工地背景及工人角色；提示词见 README.md',
        license='本项目原创素材，可随演示使用与修改', license_url='无第三方素材许可')
    ] + [item for item in scene['items'] if item['id'] != 'site']


def street_sprites(output, kind, frames):
    bounds = [f.getchannel('A').point(lambda a: 255 if a >= 64 else 0).getbbox()
              for f in frames]
    width = max(b[2]-b[0] for b in bounds)
    height = max(b[3]-b[1] for b in bounds)
    for i, (frame, bound) in enumerate(zip(frames, bounds)):
        canvas = Image.new('RGBA', (width, height))
        cutout = frame.crop(bound)
        canvas.paste(cutout, ((width-cutout.width)//2, height-cutout.height))
        canvas.thumbnail((700, 700))
        canvas.save(output / f'{kind}-{i}.webp', lossless=True)


def street():
    output = ASSETS / 'street'
    output.mkdir(parents=True, exist_ok=True)
    sources = [('car', [(0, 'car')], 1),
               ('living', [(2, 'person'), (3, 'dog')], 4),
               ('traffic', [(0, 'bus'), (1, 'truck')], 3),
               ('bicycle', [(0, 'bicycle')], 1),
               ('motorcycle', [(0, 'motorcycle')], 1)]
    for sheet, kinds, rows in sources:
        image = Image.open(ROOT / 'art/street' / (sheet + '-sheet.webp'))
        cell_w, cell_h = image.width // 2, image.height // rows
        edges = [0, 400, 770, 1165, 1448] if sheet == 'living' else [
            row*cell_h for row in range(rows+1)]
        for row, kind in kinds:
            frames = [image.crop((col*cell_w, edges[row], (col+1)*cell_w,
                                  edges[row+1])) for col in range(2)]
            street_sprites(output, kind, frames)
    extras = Image.open(ROOT / 'art/street/extras-sheet.webp')
    cw, ch = extras.width // 4, extras.height // 3
    for kind, row, columns in [('plant', 1, [1]), ('light', 1, [2]), ('stop', 1, [3])]:
        frames = [extras.crop((col*cw, row*ch, (col+1)*cw, (row+1)*ch)) for col in columns]
        street_sprites(output, kind, frames)
    poster = Image.new('RGB', (480, 270), '#55585a')
    car = Image.open(output / 'car-0.webp')
    car.thumbnail((360, 200))
    poster.paste(car, ((480-car.width)//2, (270-car.height)//2), car)
    poster.save(output / 'poster.jpg', quality=90)


def street_catalog(scenes):
    item = dict(id='street', name='动态街景', path='street/poster.jpg', type='street',
        poster='street/poster.jpg', author='本项目 · imagegen 原创',
        source='原创透明街景动作图集；提示词见 README.md',
        license='本项目原创素材，可随演示使用与修改', license_url='无第三方素材许可')
    scenes[:] = [s for s in scenes if s['id'] != 'street']
    scenes.insert(1, dict(id='street', name='动态街景', app='目标检测计数',
        thumbnail='street/poster.jpg', items=[item]))


def motion_catalog():
    """Update the restored APK catalog with newly prepared motion scenes."""
    path = ASSETS / 'catalog.json'
    data = json.loads(path.read_text())
    site_catalog(data['scenes'])
    street_catalog(data['scenes'])
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2))


def video():
    output = ASSETS / 'videos'
    downloads = BUILD / 'user-sources'
    output.mkdir(parents=True, exist_ok=True)
    downloads.mkdir(parents=True, exist_ok=True)
    for clip in json.loads((ROOT / 'user_clips.json').read_text()):
        copied = downloads / clip['source']
        shutil.copy2(USER / clip['source'], copied)
        subprocess.run([str(FFMPEG), '-y', '-ss', str(clip['start']), '-i', str(copied),
                        '-t', str(clip['duration']), '-an', '-vf',
                        'scale=1280:720:force_original_aspect_ratio=decrease,'
                        'pad=1280:720:(ow-iw)/2:(oh-ih)/2,setsar=1',
                        '-c:v', 'libx264', '-profile:v', 'main', '-pix_fmt', 'yuv420p',
                        '-b:v', '1400k', '-maxrate', '1800k', '-bufsize', '2800k',
                        '-threads', '1', '-movflags', '+faststart',
                        str(output / (clip['id']+'.mp4'))], check=True)
    for clip in json.loads((KIT / 'clips.json').read_text()):
        shutil.copy2(Path('build/demo-kit/clips') / (clip['id']+'.mp4'),
                     output / (clip['id']+'.mp4'))


def catalog():
    import cv2
    from collections import Counter
    images = ASSETS / 'images'
    posters = ASSETS / 'posters'
    thumbnails = ASSETS / 'thumbnails'
    for directory in (images, posters, thumbnails):
        directory.mkdir(parents=True, exist_ok=True)
    scenes = json.loads((KIT / 'media.json').read_text())
    clips = {c['id']: c for c in json.loads((KIT / 'clips.json').read_text())}
    for scene in scenes:
        if scene['id'] == 'zoo':
            scene['id'] = 'detect'
            scene['name'] = '检测图集'
        scene['thumbnail'] = 'thumbnails/' + scene['id'] + '.jpg'
        for item in scene['items']:
            if item['id'] in clips:
                item.update(clips[item['id']])
                item['path'] = 'videos/' + item['id'] + '.mp4'
            else:
                shutil.copy2(KIT / 'media' / (item['id']+'.jpg'), images / (item['id']+'.jpg'))
                item['path'] = 'images/' + item['id'] + '.jpg'
            item['poster'] = 'posters/' + item['id'] + '.jpg'
    for clip in json.loads((ROOT / 'user_clips.json').read_text()):
        scene = next(s for s in scenes if s['id'] == clip['scene'])
        scene['items'].insert(0, clip | dict(path='videos/'+clip['id']+'.mp4',
            type='video/mp4', poster='posters/'+clip['id']+'.jpg', author='用户提供',
            source=clip['source']+f"；截取 {clip['start']}–{clip['start']+clip['duration']} s",
            license='用户提供，用于本次现场演示', license_url='用户原始视频'))
    selected = json.loads((BUILD / 'selected-data.json').read_text())
    for item in selected:
        ImageOps.pad(Image.open(item['original']).convert('RGB'), (1280, 720),
                     color='black').save(ASSETS / item['path'], quality=92)
        scene = next(s for s in scenes if s['id'] == item['scene'])
        item['license'] += '；仅等比缩放、留边及 JPEG 转码，改动部分沿用原许可'
        scene['items'].append(item)
    order = ['farm', 'traffic', 'dance', 'detect', 'gesture', 'helmet', 'face']
    scenes.sort(key=lambda s: order.index(s['id']))
    farm = scenes[0]
    farm['items'] = [dict(id='farm', name='CAM-02 东牧场', path='farm/background.jpg',
        type='farm', poster='farm/background.jpg', author='本项目 · imagegen 原创',
        source='原创监控背景及逐帧角色；提示词见 README.md',
        license='本项目原创素材，可随演示使用与修改', license_url='无第三方素材许可')]
    site_catalog(scenes)
    street_catalog(scenes)
    for scene in scenes:
        for item in scene['items']:
            if item['type'] == 'video/mp4':
                capture = cv2.VideoCapture(str(ASSETS / item['path']))
                ok, frame = capture.read()
                capture.release()
                if not ok:
                    raise RuntimeError('Cannot decode '+item['path'])
                cv2.imwrite(str(ASSETS / item['poster']), frame)
            elif item['type'] not in ('farm', 'site', 'street'):
                shutil.copy2(ASSETS / item['path'], ASSETS / item['poster'])
        poster = ASSETS / scene['items'][0]['poster']
        ImageOps.fit(Image.open(poster).convert('RGB'), (480, 270)).save(
            ASSETS / scene['thumbnail'], quality=85)
    shutil.copytree(ROOT / 'licenses', ASSETS / 'licenses', dirs_exist_ok=True)
    fields = ('id', 'name', 'path', 'type', 'poster', 'author', 'source',
              'license', 'license_url')
    packaged = [dict(id=s['id'], name=s['name'], app=s['app'], thumbnail=s['thumbnail'],
                     items=[{key: item[key] for key in fields} for item in s['items']])
                for s in scenes]
    (ASSETS / 'catalog.json').write_text(json.dumps(dict(scenes=packaged), ensure_ascii=False,
                                                   indent=2))
    print('packaged media:', dict(Counter(i['type'] for s in scenes for i in s['items'])))


if __name__ == '__main__':
    for stage in (sys.argv[1:] or ['art', 'site', 'street', 'video', 'catalog']):
        {'art': art, 'site': site, 'street': street, 'video': video, 'catalog': catalog,
         'motion-catalog': motion_catalog}[stage]()
