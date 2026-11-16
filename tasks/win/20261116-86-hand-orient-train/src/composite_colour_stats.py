#!/usr/bin/env python3
"""composite_colour_stats.py: card 86, paired foreground hue and affine statistics.
Compares original pixels with their matching composite pixels in validation hands.
Clock domain: not applicable (offline quality measurement).
"""
import argparse
from collections import defaultdict
import json
from pathlib import Path
import cv2
import numpy as np


def summary(before, after):
    before = np.concatenate(before)
    after = np.concatenate(after)
    original = cv2.cvtColor(before.reshape(-1, 1, 3), cv2.COLOR_BGR2HSV).reshape(-1, 3)
    composed = cv2.cvtColor(after.reshape(-1, 1, 3), cv2.COLOR_BGR2HSV).reshape(-1, 3)
    colored = original[:, 1] >= 30
    delta = ((composed[colored, 0].astype(int) - original[colored, 0] + 90) % 180 - 90) * 2

    def hue_mean(hsv):
        radians = hsv[:, 0].astype(float) * np.pi / 90
        weights = original[:, 1].astype(float)
        return float(np.degrees(np.arctan2(np.sum(np.sin(radians) * weights),
                                          np.sum(np.cos(radians) * weights))) % 360)

    def purple_fraction(hsv):
        return float(np.mean((hsv[:, 0] >= 130) & (hsv[:, 0] <= 175) & (hsv[:, 1] >= 30)))

    before_mean = before.mean(0)
    after_mean = after.mean(0)
    mean_colours = np.array([before_mean, after_mean], dtype='float32') / 255
    mean_hsv = cv2.cvtColor(mean_colours.reshape(1, 2, 3), cv2.COLOR_BGR2HSV)[0]
    mean_shift = abs(float((mean_hsv[1, 0] - mean_hsv[0, 0] + 180) % 360 - 180))
    return dict(pixels=len(before), colored_pixels=int(colored.sum()),
                before_bgr_mean=before_mean.tolist(), after_bgr_mean=after_mean.tolist(),
                before_mean_colour_hsv=mean_hsv[0].tolist(),
                after_mean_colour_hsv=mean_hsv[1].tolist(),
                mean_colour_hue_shift_degrees=mean_shift,
                before_hue_degrees=hue_mean(original), after_hue_degrees=hue_mean(composed),
                signed_hue_shift_median_degrees=float(np.median(delta)),
                absolute_hue_shift_mean_degrees=float(np.mean(np.abs(delta))),
                absolute_hue_shift_median_degrees=float(np.median(np.abs(delta))),
                absolute_hue_shift_p95_degrees=float(np.quantile(np.abs(delta), 0.95)),
                before_purple_fraction=purple_fraction(original),
                after_purple_fraction=purple_fraction(composed))


def measure(source, dataset, output):
    xyz = np.array(json.loads((source / 'training_xyz.json').read_text()))
    cameras = np.array(json.loads((source / 'training_K.json').read_text()))
    groups = defaultdict(list)
    for item in json.loads((dataset / 'records.json').read_text()):
        if item['split'] == 'val':
            groups[item['image']].append(item)
    pairs = {name: ([], []) for name in ['interior_3px', 'opaque_core']}
    scales, ratios, aspects = [], [], []
    for image, items in groups.items():
        canvas = cv2.imread(image)
        for item in items:
            index = item['source_id']
            extent = np.array(item['box'][2:]) - np.array(item['box'][:2])
            aspects.append(float(extent.max() / extent.min()))
            projected = xyz[index] @ cameras[index].T
            points = projected[:, :2] / projected[:, 2:]
            matrix = np.linalg.lstsq(np.c_[points, np.ones(21)], item['points'], rcond=None)[0].T
            singular = np.linalg.svd(matrix[:, :2], compute_uv=False)
            scales.append(float(singular.mean()))
            ratios.append(float(singular.max() / singular.min()))
            corners = np.array([[0, 0, 1], [224, 0, 1], [0, 224, 1], [224, 224, 1]]) @ matrix.T
            low = np.rint(corners.min(0)).astype(int)
            size = np.ceil(corners.max(0) - corners.min(0)).astype(int)
            matrix[:, 2] -= low
            rgb = cv2.imread(str(source / 'training/rgb' / f'{index:08d}.jpg'))
            mask = cv2.imread(str(source / 'training/mask' / f'{index:08d}.jpg'), 0)
            patch = cv2.warpAffine(rgb, matrix, tuple(size))
            alpha = cv2.warpAffine(mask, matrix, tuple(size)).astype(float) / 255
            masks = dict(interior_3px=cv2.erode((alpha > 0.5).astype('uint8'),
                                               np.ones((7, 7), 'uint8')).astype(bool),
                         opaque_core=cv2.GaussianBlur(alpha, (0, 0), 3) >= 0.99)
            x, y = low
            width, height = size
            composed = canvas[y:y+height, x:x+width]
            for name, selected in masks.items():
                pairs[name][0].append(patch[selected])
                pairs[name][1].append(composed[selected])
    result = {name: summary(*values) for name, values in pairs.items()}
    result['geometry'] = dict(hands=len(scales), scale_min=min(scales),
                              scale_median=float(np.median(scales)), scale_max=max(scales),
                              maximum_hand_box_aspect_ratio=max(aspects),
                              maximum_aspect_stretch_ratio=max(ratios))
    output.write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps(result, indent=2), flush=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=Path)
    parser.add_argument('dataset', type=Path)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    measure(args.source, args.dataset, args.output)
