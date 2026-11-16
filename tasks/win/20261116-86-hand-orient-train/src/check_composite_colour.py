#!/usr/bin/env python3
"""check_composite_colour.py: card 86, BGR/PNG and edge-only colour checks.
Clock domain: not applicable (CPU image checks).
"""
import io
import cv2
import numpy as np
from PIL import Image
from freihand_composite import mask_and_colour

swatches = np.array([[[0, 0, 255], [0, 255, 0], [255, 0, 0]]], dtype='uint8')
_, encoded = cv2.imencode('.png', swatches)
rgb = np.array(Image.open(io.BytesIO(encoded.tobytes())))
np.testing.assert_array_equal(rgb, swatches[:, :, ::-1])
mask = np.zeros((80, 80), dtype='uint8')
mask[16:64, 16:64] = 255
patch = np.full((80, 80, 3), [80, 120, 180], dtype='uint8')
changed, alpha = mask_and_colour(patch, mask, np.random.default_rng(0))
before = cv2.cvtColor(patch, cv2.COLOR_BGR2HSV)[40, 40, 0]
after = cv2.cvtColor(changed.astype('uint8'), cv2.COLOR_BGR2HSV)[40, 40, 0]
shift = abs((int(after) - int(before) + 90) % 180 - 90) * 2
assert shift <= 5, shift
np.testing.assert_allclose(alpha[40, 40], 1, atol=1e-6)
patch[:] = [40, 200, 60]
changed, _ = mask_and_colour(patch, mask, np.random.default_rng(0))
before = cv2.cvtColor(patch, cv2.COLOR_BGR2HSV)[40, 40, 0]
after = cv2.cvtColor(changed.astype('uint8'), cv2.COLOR_BGR2HSV)[40, 40, 0]
core_shift = abs((int(after) - int(before) + 90) % 180 - 90) * 2
assert core_shift <= 5, core_shift
print('COMPOSITE_COLOUR_PASS BGR/PNG round trip; core hue shift degrees', shift,
      'green core retained, hue shift degrees', core_shift)
