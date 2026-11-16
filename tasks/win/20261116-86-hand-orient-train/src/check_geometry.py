#!/usr/bin/env python3
"""check_geometry.py: card 86 step 3, test 3D rotation/scale invariance on real points.
Clock domain: not applicable (offline geometry test).
"""
from collections import Counter
from pathlib import Path
import sys
import numpy as np
from hand3d_gesture import classify, features, NAMES

root = Path(sys.argv[1])
rng = np.random.default_rng(0)
counts = Counter()
for sequence in sorted(root.iterdir())[:10]:
    for path in sorted(sequence.glob('*/labels_*.npz'))[::10]:
        with np.load(path) as data:
            image_points = data['joint_2d'].reshape(21, 2)
            points = data['joint_3d'].reshape(21, 3)
        if np.any(image_points == -1):
            continue
        expected = classify(points, image_points)
        rotation, _ = np.linalg.qr(rng.normal(size=(3, 3)))
        transformed = points @ rotation * rng.uniform(0.1, 10)
        actual = classify(transformed, image_points)
        assert expected == actual, (str(path), expected, actual)
        for original, changed in zip(features(points), features(transformed)):
            np.testing.assert_allclose(original, changed, atol=1e-4)
        counts['uncertain' if expected is None else NAMES[expected]] += 1
print('3D rotation and scale invariance PASS', sum(counts.values()), dict(counts))
