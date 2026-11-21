#!/usr/bin/env python3
"""compose_workshop_art.py — block-workshop design §3 original runtime artwork.

Pillow-only, supersampled flat painted materials and articulated animal animation.
Host tool; no clock domain. All output PNGs use straight RGBA, never premultiplied.
"""
import argparse
import math
from pathlib import Path
import random
import shutil

from PIL import Image, ImageDraw, ImageEnhance, ImageFilter, ImageOps

ROOT = Path(__file__).resolve().parents[2]
ASSETS = ROOT / 'sw/apps/showcase/assets/workshop'
SCALE = 4
INK = '#39434a'
CREAM = '#fff1d4'


class Paint:
    """Draw in display-pixel coordinates on an antialiased canvas."""

    def __init__(self, size):
        self.image = Image.new('RGBA', tuple(v * SCALE for v in size))
        self.draw = ImageDraw.Draw(self.image)

    def box(self, rect, fill, outline=None, width=2, radius=0):
        rect = tuple(v * SCALE for v in rect)
        if radius:
            self.draw.rounded_rectangle(rect, radius * SCALE, fill, outline, round(width * SCALE))
        else:
            self.draw.rectangle(rect, fill, outline, round(width * SCALE))

    def oval(self, rect, fill, outline=None, width=2):
        self.draw.ellipse(tuple(v * SCALE for v in rect), fill, outline, round(width * SCALE))

    def line(self, points, fill, width=1):
        self.draw.line([(x * SCALE, y * SCALE) for x, y in points], fill,
                       round(width * SCALE), joint='curve')

    def poly(self, points, fill):
        self.draw.polygon([(x * SCALE, y * SCALE) for x, y in points], fill)

    def finish(self):
        return self.image.resize(tuple(v // SCALE for v in self.image.size),
                                 Image.Resampling.LANCZOS)


def save(name, image):
    image.save(ASSETS / f'{name}.png')
    return image


def material(kind, size=(48, 48)):
    w, h = size
    colors = {'grass': '#a97653', 'dirt': '#ad7d59', 'stone': '#929caa',
              'gravel': '#999592', 'sand': '#e3ca90', 'plank': '#c99b65',
              'log': '#ad7b50', 'stonebrick': '#9aa6ae', 'brick': '#cb8972',
              'metal': '#a3b9bc', 'ice': '#a3d9e5', 'glass': '#aad5cd',
              'leaves': '#80a878'}
    p = Paint(size)
    p.box((0, 0, w - .25, h - .25), colors[kind])
    rng = random.Random(321 + len(kind))
    if kind in ('dirt', 'grass', 'sand', 'stone'):
        for _ in range(25):
            x, y = rng.randrange(5, w - 4), rng.randrange(7, h - 4)
            color = {'sand': '#c4aa74', 'stone': '#737e91'}.get(kind, '#825d46')
            p.line([(x, y), (x + 2, y - 1)], color, 1)
            p.line([(x, y - 1), (x + 1, y - 1)], '#dec59c', .6)
        if kind == 'grass':
            p.poly([(0, 0), (48, 0), (48, 9), (41, 12), (35, 9), (27, 13),
                    (22, 10), (15, 12), (8, 9), (0, 12)], '#83aa69')
            p.line([(4, 5), (8, 6), (10, 3)], '#bfd68b', 1)
            p.line([(29, 4), (33, 6), (37, 4)], '#bcd28a', 1)
    elif kind == 'gravel':
        for y in range(3, h, 12):
            for x in range(3, w, 12):
                x += rng.randrange(-2, 3)
                p.poly([(x, y + 3), (x + 5, y), (x + 10, y + 3),
                        (x + 9, y + 9), (x + 2, y + 10)], '#666c73')
                p.poly([(x + 1, y + 3), (x + 5, y + 1), (x + 9, y + 3),
                        (x + 7, y + 7), (x + 2, y + 7)], '#b6b4ac')
    elif kind in ('plank', 'log'):
        for y in range(12, h, 14):
            p.line([(1, y), (w - 2, y)], '#8b613f', 1.2)
            p.line([(2, y + 2), (w - 3, y + 2)], '#e3bc7b', .8)
        for y in range(6, h, 15):
            p.line([(5, y), (w * .3, y + 1), (w * .55, y - 1),
                    (w - 6, y)], '#ad7c4b', .8)
        p.oval((w * .57, h * .4, w * .57 + 10, h * .4 + 4), None, '#90613e', 1)
        if kind == 'log':
            p.box((3, 3, 12, h - 4), '#c39969')
            p.line([(8, 5), (7, 20), (9, h - 5)], '#e0b580', 1)
            p.box((w - 10, 3, w - 4, h - 4), '#865e40')
    elif kind in ('brick', 'stonebrick'):
        mortar = '#f0d1b4' if kind == 'brick' else '#d5d9d4'
        shade = '#9d6256' if kind == 'brick' else '#6e7d8c'
        for row, y in enumerate(range(0, h, 16)):
            p.line([(0, y), (w, y)], mortar, 2)
            for x in range(-24 if row % 2 else 0, w, 24):
                p.line([(x, y), (x, y + 16)], mortar, 2)
                p.line([(x + 4, y + 12), (x + 20, y + 12)], shade, .7)
                p.line([(x + 4, y + 4), (x + 19, y + 4)], '#e0b8a0', .7)
    elif kind == 'metal':
        for y in (12, 33):
            p.line([(5, y), (w - 5, y)], '#cbdad9', 1)
        for x in (7, w - 8):
            for y in (7, h - 8):
                p.oval((x - 2, y - 2, x + 2, y + 2), '#657f89')
                p.oval((x - 1, y - 1, x + .5, y + .5), '#e5ece1')
    elif kind in ('glass', 'ice'):
        p.poly([(6, 4), (18, 4), (4, 30), (4, 19)], '#e8f5ed')
        p.poly([(27, 4), (31, 4), (8, 44), (4, 44)], '#ceeae9')
        if kind == 'ice':
            p.line([(30, 7), (28, 22), (35, 30), (32, 41)], '#e9f7ef', 1.3)
            p.line([(28, 22), (19, 26), (17, 35)], '#e9f7ef', .8)
    elif kind == 'leaves':
        for y in range(4, h, 10):
            for x in range(3, w, 11):
                p.oval((x, y, x + 12, y + 8), '#527d60', None)
                p.oval((x, y, x + 10, y + 5), '#a5c381', None)
        for x, y in ((0, 13), (45, 27), (16, 0), (30, 46)):
            p.box((x, y, x + 2, y + 2), (0, 0, 0, 0))
    # All bevels are inset: two bright upper/left pixels and dark lower/right pixels.
    p.poly([(0, 0), (w, 0), (w - 2, 2), (2, 2), (2, h - 2), (0, h)], '#ead6af')
    p.poly([(w, 0), (w, h), (0, h), (2, h - 2), (w - 2, h - 2),
            (w - 2, 2)], '#59616a')
    image = p.finish()
    if kind in ('ice', 'glass'):
        image.putalpha(180)
    return image


def star(p, cx, cy, radius=3):
    points = []
    for i in range(10):
        angle = -math.pi / 2 + i * math.pi / 5
        r = radius if i % 2 == 0 else radius * .44
        points.append((cx + math.cos(angle) * r, cy + math.sin(angle) * r))
    p.poly(points, '#f7cd65')


def animal(kind, action, frame):
    bunny = kind == 'bunny'
    p = Paint((64 if bunny else 56, 56))
    phase = 2 * math.pi * frame / 8
    walk = action == 'walk'
    bob = -1.5 * (1 - math.cos(phase * 2)) if walk else (frame * -.5)
    if action == 'lift':
        bob = -4
    foot_color = '#c5b7a5' if bunny else '#dc9560'
    # Articulated legs: planted feet move back 12/8px over four frames, then swing forward.
    stride = 24 if bunny else 16
    for side in (0, 1):
        t = (frame / 8 + side / 2) % 1
        x = 27 + side * 11
        y = 51
        if walk:
            x += stride * (.25 - t) if t < .5 else stride * (t - .75)
            y -= 4 * math.sin((t - .5) * 2 * math.pi) if t >= .5 else 0
        if action == 'lift':
            x += (frame * 2 - 1) * (3 if side else -3)
            y = 47 + side * 2
        p.line([(27 + side * 9, 39 + bob), (x, y - 2)], foot_color, 4)
        p.oval((x - 5, y - 3, x + 5, y + 1), foot_color, INK, 1.2)
    if bunny:
        p.oval((5, 30 + bob, 17, 42 + bob), '#f7eddb', INK, 1.4)
        p.oval((13, 23 + bob, 46, 47 + bob), '#e7ddc9', INK, 2)
        p.oval((18, 26 + bob, 37, 42 + bob), '#fff4de')
        sway = 2 * math.sin(phase) if walk else frame - .5
        p.poly([(35, 25 + bob), (28 + sway, 8 + bob), (33 + sway, 6 + bob),
                (43, 24 + bob)], INK)
        p.poly([(36, 24 + bob), (30 + sway, 9 + bob), (32 + sway, 8 + bob),
                (41, 24 + bob)], '#f7ead4')
        p.line([(33 + sway, 12 + bob), (38, 22 + bob)], '#dcaeaa', 2)
        p.oval((39, 7 + bob, 48, 28 + bob), '#f8ecd7', INK, 1.5)
        p.line([(43, 11 + bob), (44, 23 + bob)], '#dcaeaa', 2)
        p.oval((31, 19 + bob, 56, 40 + bob), '#faedda', INK, 2)
        p.oval((43, 30 + bob, 58, 39 + bob), '#fff3df')
        p.oval((50, 31 + bob, 54, 34 + bob), '#b77e7b')
        p.oval((37, 30 + bob, 43, 34 + bob), '#eac8b5')
        eye_x, eye_y = 47, 27 + bob
        p.line([(22, 38 + bob), (30, 41 + bob)], '#b6a58f', 1)
    else:
        tilt = math.sin(phase) * 1.5 if walk else 0
        p.poly([(13, 34 + bob), (4, 29 + bob), (7, 40 + bob), (19, 44 + bob)], INK)
        p.oval((9, 24 + bob, 43, 47 + bob), '#e9c363', INK, 2)
        p.oval((13, 26 + bob, 32, 39 + bob), '#f8dc81')
        p.oval((18, 31 + bob + tilt, 34, 41 + bob + tilt), '#d5aa55', INK, 1)
        p.line([(21, 34 + bob + tilt), (29, 35 + bob + tilt)], '#f4d17b', 1)
        p.oval((29, 12 + bob, 49, 32 + bob), '#f5d47c', INK, 2)
        p.poly([(46, 23 + bob), (54, 26 + bob), (47, 30 + bob),
                (43, 28 + bob)], '#d88c5d')
        p.line([(47, 26 + bob), (52, 26 + bob)], '#8e644c', .8)
        p.line([(33, 14 + bob), (34, 10 + bob), (37, 13 + bob)], '#b99953', 1.3)
        p.oval((34, 24 + bob, 40, 28 + bob), '#e7b17a')
        eye_x, eye_y = 42, 20 + bob
    if action == 'stun':
        for dx in (-2, 2):
            p.line([(eye_x + dx - 1, eye_y - 2), (eye_x + dx + 1, eye_y + 2)], INK, 1)
        p.line([(eye_x - 3, eye_y), (eye_x + 3, eye_y)], INK, .8)
        p.line([(18, 9), (25, 6), (36, 7)], '#a1bdc8', 1)
        for x, y in ((19 + frame * 4, 6), (32 - frame * 3, 4), (52, 10)):
            star(p, x, y, 2.7)
    elif action == 'idle' and frame == 1:
        p.line([(eye_x - 2, eye_y), (eye_x + 2, eye_y)], INK, 1.4)
    else:
        p.oval((eye_x - 1.4, eye_y - 2, eye_x + 1.4, eye_y + 2), INK)
        p.oval((eye_x - .7, eye_y - 1.4, eye_x + .2, eye_y - .4), '#fff8e8')
    return p.finish()


def hand(grab, size):
    p = Paint((64, 64))
    if grab:
        p.box((18, 21, 49, 50), '#ede5d2', INK, radius=9)
        for x in (23, 31, 39):
            p.line([(x, 24), (x, 31)], '#918d84', 1)
        p.box((13, 31, 37, 40), '#fff5df', INK, radius=4)
    else:
        for rect in ((18, 16, 25, 38), (27, 9, 34, 37), (36, 12, 43, 38),
                     (45, 21, 52, 41)):
            p.box(rect, '#fff2dc', INK, radius=3)
        p.box((18, 30, 51, 53), '#f2e7d1', INK, radius=10)
        p.line([(22, 45), (12, 32), (9, 34), (16, 47), (23, 52)], '#fff1da', 6)
        p.line([(10, 33), (17, 48), (23, 52)], INK, 2)
        p.line([(29, 37), (39, 40)], '#c9bba1', 1)
    p.box((23, 49, 44, 59), '#a4bec1', INK, radius=3)
    return p.finish().resize((size, size), Image.Resampling.LANCZOS)


def pick(swing, size):
    p = Paint((64, 64))
    p.line([(18, 55), (43, 16)], INK, 8)
    p.line([(18, 54), (43, 16)], '#be8b59', 5)
    p.line([(17, 52), (40, 18)], '#e2b77c', 1)
    p.poly([(21, 17), (30, 10), (43, 10), (55, 16), (61, 28),
            (49, 21), (39, 19), (28, 20)], INK)
    p.poly([(24, 16), (31, 12), (43, 12), (53, 17), (57, 23),
            (48, 18), (39, 16), (29, 18)], '#b9cdd0')
    p.line([(31, 13), (43, 13), (51, 17)], '#f0ebd4', 1)
    image = p.finish()
    if swing:
        image = image.rotate(-65, Image.Resampling.BICUBIC)
    return image.resize((size, size), Image.Resampling.LANCZOS)


def make_blocks():
    kinds = ['grass', 'dirt', 'stone', 'gravel', 'sand', 'plank', 'log',
             'stonebrick', 'brick', 'metal', 'ice', 'glass', 'leaves']
    for kind in kinds:
        save('block-' + kind, material(kind))
    for on in (False, True):
        for kind in ('lamp', 'window'):
            p = Paint((48, 48))
            p.box((0, 0, 47.75, 47.75), '#b5a17c', INK)
            p.line([(2, 45), (2, 2), (45, 2)], '#e9d7ac', 2)
            p.box((6, 6, 41, 41), '#f5cf78' if on else '#a5c5c5', INK, radius=3)
            if kind == 'window':
                p.poly([(10, 9), (20, 9), (10, 29)], '#fff0c1' if on else '#e1ebe0')
                p.line([(24, 6), (24, 41)], '#8b7256', 3)
                p.line([(6, 24), (41, 24)], '#8b7256', 3)
            else:
                p.oval((14, 12, 34, 32), '#ffe8a4' if on else '#ccd5c3', INK, 1.5)
                p.box((20, 30, 28, 35), '#7d8a86')
                p.line([(21, 27), (24, 22), (27, 27)], '#ba915a', 1)
                if on:
                    for x, y in ((11, 11), (36, 11), (10, 33), (37, 33)):
                        p.line([(x, y), (x + 2, y + 2)], '#fff0c0', 1)
            save('block-' + kind + ('-on' if on else ''), p.finish())
    for name, kind in (('beam', 'plank'), ('pillar', 'stonebrick')):
        save(name + '-h', material(kind, (96, 48)))
        save(name + '-v', material(kind, (48, 96)))
    p = Paint((48, 96))
    p.box((0, 0, 47.75, 95.75), '#866348', INK)
    p.box((4, 3, 43, 93), '#ba8c59', '#e7bd80', 2)
    for x in (16, 30):
        p.line([(x, 5), (x, 91)], '#8e6441', 1)
    for y in (12, 53, 82):
        p.box((6, y, 41, y + 3), '#806247')
    p.box((9, 18, 37, 42), '#bad3ce', INK, radius=3)
    p.line([(23, 19), (23, 41)], '#98714e', 2)
    p.oval((34, 59, 40, 65), '#f4cf7d', INK, 1)
    save('door', p.finish())
    corners = {'bl': [(0, 0), (48, 48), (0, 48)],
               'br': [(48, 0), (48, 48), (0, 48)],
               'tl': [(0, 0), (48, 0), (0, 48)],
               'tr': [(0, 0), (48, 0), (48, 48)]}
    for kind, texture in (('wood', 'plank'), ('brick', 'brick')):
        for corner, points in corners.items():
            mask = Paint((48, 48))
            mask.poly(points, 'white')
            image = material(texture).resize((192, 192), Image.Resampling.BICUBIC)
            image.putalpha(mask.image.getchannel('A'))
            # Inset triangle outline is clipped by the silhouette including its hypotenuse.
            outline = ImageDraw.Draw(image)
            vertices = [(x * 4, y * 4) for x, y in points]
            outline.line(vertices + [vertices[0]], fill='#59616a', width=16, joint='curve')
            a, b = points[:2] if corner in ('bl', 'br') else (points[1], points[2])
            outline.line([(a[0] * 4, a[1] * 4), (b[0] * 4, b[1] * 4)],
                         fill='#ecd0a0', width=8)
            image.putalpha(mask.image.getchannel('A'))
            save(f'slope-{kind}-{corner}', image.resize((48, 48), Image.Resampling.LANCZOS))


def make_cracks():
    rng = random.Random(20261117)
    branches = []
    for level in range(8):
        theta = level * 2.399
        points = [(24, 24)]
        for r in (7, 14, 22):
            points.append((24 + math.cos(theta) * r + rng.uniform(-2, 2),
                           24 + math.sin(theta) * r + rng.uniform(-2, 2)))
        branches.append(points)
        p = Paint((48, 48))
        for i, branch in enumerate(branches):
            width = 1 + (level - i) * .14
            p.line([(x + 1, y + .7) for x, y in branch], '#dddbc3', width + .5)
            p.line(branch, '#3c424e', width)
            x, y = branch[2]
            fork = [(x, y), (x + math.sin(i) * 6, y + math.cos(i) * 6)]
            p.line(fork, '#3c424e', width * .7)
        save('crack-' + str(level + 1), p.finish())


def make_icons():
    save('cursor-hand-open', hand(False, 64))
    save('cursor-hand-grab', hand(True, 64))
    save('tool-hand', hand(False, 56))
    save('cursor-pick', pick(False, 64))
    save('cursor-pick-swing', pick(True, 64))
    save('tool-pick', pick(False, 56))
    for period in ('day', 'dusk', 'night'):
        p = Paint((56, 56))
        p.oval((4, 4, 52, 52), {'day': '#aacdd1', 'dusk': '#b69bb0',
                              'night': '#536779'}[period], INK, 2)
        if period == 'night':
            p.oval((15, 12, 40, 38), '#f8e4a6')
            p.oval((23, 8, 43, 30), '#536779')
            for x, y in ((13, 34), (41, 19), (38, 40)):
                star(p, x, y, 2)
        else:
            cy = 23 if period == 'day' else 34
            p.oval((17, cy - 10, 39, cy + 12), '#f9d27c')
            for i in range(8):
                t = i * math.pi / 4
                p.line([(28 + math.cos(t) * 14, cy + math.sin(t) * 14),
                        (28 + math.cos(t) * 17, cy + math.sin(t) * 17)], '#fce3aa', 1.5)
            if period == 'dusk':
                p.line([(10, 37), (46, 37)], '#e1b1a0', 3)
                p.line([(15, 42), (41, 42)], '#e1b1a0', 2)
        save('sky-' + period, p.finish())
    glow = Image.new('RGBA', (144, 144))
    glow.putdata([(255, 208, 118, round(150 * max(0, 1 - math.hypot(x - 71.5,
                  y - 71.5) / 71.5) ** 1.7)) for y in range(144) for x in range(144)])
    save('glow', glow)


def camera_example():
    """Offline camera-style room example, drawn locally without external imagery."""
    p = Paint((960, 450))
    p.box((0, 0, 959, 449), '#b9b5a7')
    p.poly([(0, 0), (170, 60), (170, 360), (0, 449)], '#999f98')
    p.poly([(0, 449), (170, 360), (960, 360), (960, 450)], '#8e8170')
    p.box((660, 70, 870, 245), '#767e79')
    p.box((671, 81, 858, 232), '#c5d4cb')
    p.line([(763, 80), (763, 233)], '#a49f8b', 6)
    p.box((220, 268, 760, 300), '#938571')
    p.poly([(230, 300), (252, 300), (246, 440), (230, 440)], '#776955')
    p.box((715, 300, 738, 440), '#776955')
    p.oval((390, 76, 490, 181), '#a58b76')
    p.oval((384, 70, 491, 119), '#5f655f')
    p.box((359, 177, 522, 334), '#81939b', radius=35)
    p.line([(375, 203), (310, 270), (400, 283)], '#ab9681', 27)
    p.line([(501, 203), (561, 260), (497, 279)], '#ab9681', 27)
    room = p.finish().filter(ImageFilter.GaussianBlur(3))
    return ImageEnhance.Brightness(room.convert('RGB')).enhance(.34).convert('RGBA')


def previews(output):
    output.mkdir(parents=True, exist_ok=True)
    def asset(name):
        return Image.open(ASSETS / f'{name}.png').convert('RGBA')
    canvas = Image.new('RGBA', (1120, 900), '#202e38')
    canvas.alpha_composite(camera_example(), (80, 65))
    d = ImageDraw.Draw(canvas)
    d.text((28, 20), 'BLOCK WORKSHOP / Original painted building kit / display pixels', fill=CREAM)
    def place(name, x, y):
        canvas.alpha_composite(asset(name), (x, y))
    for i in range(17):
        place('block-grass', 152 + i * 48, 449)
    for row in range(3):
        for col in range(7):
            place('block-plank', 392 + col * 48, 305 + row * 48)
    place('door', 536, 353)
    place('block-window', 440, 353)
    place('block-window-on', 632, 353)
    for i in range(9):
        place('block-brick', 344 + i * 48, 257)
    place('slope-brick-br', 344, 209)
    place('slope-brick-bl', 728, 209)
    for i in range(7):
        place('block-brick', 392 + i * 48, 209)
    for i in range(5):
        place('block-brick', 440 + i * 48, 161)
    place('slope-brick-br', 392, 161)
    place('slope-brick-bl', 680, 161)
    # Sample garden, foundation and fittings use every 1x1 material in the house scene.
    for i, kind in enumerate(('dirt', 'stone', 'gravel', 'sand', 'stonebrick',
                              'stone', 'stonebrick', 'gravel', 'sand')):
        place('block-' + kind, 344 + i * 48, 449)
    place('block-metal', 632, 113)
    place('block-lamp-on', 632, 161)
    place('block-lamp', 680, 305)
    place('block-ice', 776, 401)
    place('block-glass', 824, 401)
    place('block-log', 200, 353)
    place('block-leaves', 176, 305)
    place('block-leaves', 224, 305)
    place('bunny-walk-1-r', 267, 397)
    place('duck-walk-1-l', 800, 397)
    names = sorted(p.stem for p in ASSETS.glob('*.png')
                   if p.stem.startswith(('block-', 'slope-', 'beam-', 'pillar-')))
    names += ['door', 'tool-hand', 'tool-pick', 'sky-day', 'sky-dusk', 'sky-night']
    for i, name in enumerate(names):
        x, y = 25 + (i % 10) * 109, 540 + (i // 10) * 87
        image = asset(name)
        image.thumbnail((78, 58), Image.Resampling.LANCZOS)
        canvas.alpha_composite(image, (x + 13, y))
        d.text((x, y + 61), name.replace('block-', ''), fill='#d4ded8')
    canvas.convert('RGB').save(output / 'blocks.png')
    canvas = Image.new('RGBA', (800, 138), '#26353f')
    d = ImageDraw.Draw(canvas)
    d.text((20, 12), 'STONE / Progressive fractures 1 - 8 / seed 20261117', fill=CREAM)
    for i in range(8):
        x = 24 + i * 96
        canvas.alpha_composite(asset('block-stone'), (x, 47))
        canvas.alpha_composite(asset('crack-' + str(i + 1)), (x, 47))
        d.text((x + 20, 110), str(i + 1), fill=CREAM)
    canvas.convert('RGB').save(output / 'cracks.png')
    canvas = Image.new('RGBA', (1040, 940), '#26353f')
    d = ImageDraw.Draw(canvas)
    d.text((20, 14), 'ANIMATION / walk 8 frames / idle, lift, stun 2 frames / R and mirrored L',
           fill=CREAM)
    row = 0
    for kind in ('bunny', 'duck'):
        for action, count in (('walk', 8), ('idle', 2), ('lift', 2), ('stun', 2)):
            for direction in ('r', 'l'):
                y = 54 + row * 54
                d.text((15, y + 20), f'{kind} {action} {direction}', fill=CREAM)
                for i in range(count):
                    canvas.alpha_composite(asset(f'{kind}-{action}-{i + 1}-{direction}'),
                                           (150 + i * 105, y))
                row += 1
        frames = []
        for i in range(8):
            frame = Image.new('RGBA', (320, 180), '#26353f')
            sprite = asset(f'{kind}-walk-{i + 1}-r')
            frame.alpha_composite(sprite.resize((sprite.width * 3, 168)), (60, 6))
            ImageDraw.Draw(frame).line((20, 162, 300, 162), fill='#77857f')
            frames.append(frame.convert('RGB'))
        frames[0].save(output / f'{kind}-walk.gif', save_all=True, append_images=frames[1:],
                       duration=100, loop=0, disposal=2)
    canvas.convert('RGB').save(output / 'animals.png')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--preview-dir', type=Path, required=True)
    args = parser.parse_args()
    ASSETS.mkdir(parents=True, exist_ok=True)
    make_blocks()
    make_cracks()
    make_icons()
    for kind in ('bunny', 'duck'):
        for action, count in (('walk', 8), ('idle', 2), ('lift', 2), ('stun', 2)):
            for frame in range(count):
                image = animal(kind, action, frame)
                save(f'{kind}-{action}-{frame + 1}-r', image)
                save(f'{kind}-{action}-{frame + 1}-l', ImageOps.mirror(image))
    for effect in ('dust', 'shard'):
        for i in range(1, 4):
            name = f'{effect}-{i}.png'
            shutil.copyfile(ROOT / 'sw/apps/showcase/assets/tower' / name, ASSETS / name)
    previews(args.preview_dir)
    total = sum(Image.open(path).width * Image.open(path).height * 4
                for path in ASSETS.glob('*.png'))
    print(f'{len(list(ASSETS.glob("*.png")))} runtime images; ARGB8888: {total} bytes')


if __name__ == '__main__':
    main()
