#!/usr/bin/env python3
"""check_feather.py: card 86 step 4, verify approximately 3 px mask transition.
Clock domain: not applicable (offline image geometry check).
"""
import cv2
import numpy as np
from freihand_composite import feather_alpha

mask = np.zeros((80, 80), dtype='float32')
mask[:, 40:] = 1
old = cv2.GaussianBlur(mask, (0, 0), 3)[40]
new = feather_alpha(mask)[40]
old_width = int(np.count_nonzero((old > 0.1) & (old < 0.9)))
new_width = int(np.count_nonzero((new > 0.1) & (new < 0.9)))
assert new_width <= 3, new_width
finger = np.zeros((40, 40), dtype='float32')
finger[:, 18:22] = 1
center = float(feather_alpha(finger)[20, 20])
assert center > 0.9, center
print('FEATHER_PASS', 'old_transition_px', old_width, 'new_transition_px', new_width,
      'four_pixel_finger_opacity', center)
