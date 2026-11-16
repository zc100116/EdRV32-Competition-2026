#!/usr/bin/env python3
"""hand3d_gesture.py: card 86 step 3, orientation independent hand shapes.

Both FreiHAND and DexYCB use wrist, thumb, index, middle, ring, little order.
Clock domain: not applicable (offline geometry).
"""
import numpy as np

NAMES = ['palm', 'fist', 'peace', 'point', 'grabbing', 'grip', 'thumb_index',
         'ok', 'like', 'dislike', 'three', 'four', 'call', 'no_gesture']
TIPS = np.array([4, 8, 12, 16, 20])


def features(points):
    p = np.asarray(points, dtype=float)
    scale = np.linalg.norm(p[9] - p[0])
    fingers = p[1:].reshape(5, 4, 3)
    bones = np.diff(fingers, axis=1)
    unit = bones / np.linalg.norm(bones, axis=2, keepdims=True)
    angles = np.degrees(np.arccos(np.clip((unit[:, :-1] * unit[:, 1:]).sum(2), -1, 1)))
    bases = fingers[:, 0] - p[0]
    base_cosine = (bases * unit[:, 0]).sum(1) / np.linalg.norm(bases, axis=1)
    base_angles = np.degrees(np.arccos(np.clip(base_cosine, -1, 1)))
    base_angles[0] = 0  # Thumb CMC abduction is not finger flexion.
    angles = np.c_[base_angles, angles]
    tips = p[TIPS]
    distances = np.linalg.norm(tips[:, None] - tips[None, :], axis=2) / scale
    palm = p[[0, 5, 9, 13, 17]].mean(0)
    root_distance = np.linalg.norm(tips - fingers[:, 0], axis=1) / scale
    return angles, distances, np.linalg.norm(tips - palm, axis=1) / scale, root_distance


def classify(points, image_points):
    p = np.asarray(points)
    scale = np.linalg.norm(p[9] - p[0])
    angles, distances, palm_distance, root_distance = features(p)
    straight = (np.all(angles < 35, axis=1) &
                (root_distance > np.array([0.65, 0.95, 1.05, 0.95, 0.7])))
    curled = (angles[:, 1:].sum(axis=1) > 110) & (root_distance < 0.45)
    thumb = bool(straight[0] and distances[0, 1] > 0.6)
    thumb_to_palm = np.linalg.norm(p[[5, 9]] - p[4], axis=1) / scale
    tucked = bool(not thumb and np.all(thumb_to_palm < 0.5))
    thumb_to_middle = np.linalg.norm(p[[6, 10]] - p[4], axis=1).min() / scale
    s = straight[1:]
    c = curled[1:]
    matches = []
    spread = distances[np.arange(4), np.arange(1, 5)]
    if thumb and s.all() and np.all(spread > 0.35):
        matches.append('palm')
    if tucked and s.all():
        matches.append('four')
    if c.all() and thumb_to_middle < 0.45:
        matches.append('fist')
    if tucked and s[0] and c[1:].all():
        matches.append('point')
    if tucked and s[:2].all() and c[2:].all():
        matches.append('peace')
    if int(thumb) + s.sum() == 3 and np.all(s | c) and (thumb or tucked):
        matches.append('three')
    if thumb and s[3] and c[:3].all():
        matches.append('call')
    if thumb and s[0] and c[1:].all():
        matches.append('thumb_index')
    if thumb and c.all():
        delta = np.asarray(image_points)[4] - np.asarray(image_points)[1]
        if abs(delta[1]) > abs(delta[0]):
            matches.append('like' if delta[1] < 0 else 'dislike')
    if (distances[0, 1] < 0.25 and s[1:].all() and root_distance[1] < 0.8 and
            angles[0].sum() > 20 and angles[1].sum() > 35):
        matches.append('ok')
    if distances.max() < 0.55 and np.all(root_distance < 1) and np.all(angles.sum(1) > 35):
        matches.append('grip')
    half = np.all((angles.max(axis=1) > 35) & (angles.max(axis=1) < 100))
    half_distance = np.all((root_distance > 0.45) & (root_distance < 0.9))
    if half and half_distance and np.all(spread > 0.35) and np.all(palm_distance > 0.65):
        matches.append('grabbing')
    return NAMES.index(matches[0]) if len(matches) == 1 else None


def orientation(points, side='right'):
    p = np.asarray(points)
    normal = np.cross(p[5] - p[0], p[17] - p[0])
    if side == 'left':
        normal = -normal
    view = -p[[0, 5, 9, 13, 17]].mean(0)
    cosine = np.dot(normal, view) / (np.linalg.norm(normal) * np.linalg.norm(view))
    if cosine > 0.5:
        return 'palm'
    if cosine < -0.5:
        return 'back'
    return 'side'
