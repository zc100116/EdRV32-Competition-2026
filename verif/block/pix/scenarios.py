#!/usr/bin/env python3
# File: scenarios.py
# Spec: PIX testplan PX-01 through PX-14, sections 3 and 6.
# Description: Enumerate the specified directed and seeded frame configurations.
# Clock domain: host; actual input pixels are emitted by the SV stream source.
import random


BC = 1
GAMMA = 2
GRAY = 1 << 16
BIN = 1 << 17
INV = 1 << 18
FLUSH = 1
NO_WAIT = 2
SOFT_MID = 4
SOFT_IDLE = 8
RESET_RESTART = 16


def bc_value(contrast=256, brightness=0):
    return contrast | ((brightness & 511) << 16)


def frame(w=64, h=8, enable=1, cfg=0, bc=256, threshold=128, pattern=0, seed=1,
          sent=None, flow=0, flags=0, mid=-1, update=None):
    # Patterns: random, pure colour, RGB gradient, checkerboard, gradient + noise.
    if sent is None:
        sent = w * h // 2
    if update is None:
        update = (enable, cfg, bc, threshold)
    return [w, h, enable, cfg, bc, threshold, pattern, seed, sent, flow, flags, mid, *update]


def cases(tier):
    result = []
    def add(number, frames, suffix=''):
        result.append((f'PX-{number:02d}' + suffix, number, frames))

    add(1, [frame(enable=0, cfg=0x77777), frame(enable=1)])
    add(2, [frame(cfg=BC, bc=bc_value(c, b), pattern=2)
            for b in (-256, -1, 0, 255) for c in (0, 128, 256, 511)])
    add(3, [frame(cfg=GAMMA, mid=32, update=(1, GAMMA | 4, 256, 128)),
            frame(cfg=GAMMA | 4),
            frame(cfg=BC | GAMMA | 4, bc=bc_value(511, -1), pattern=2)])
    add(4, [frame(cfg=op << shift, pattern=pattern)
            for shift in (4, 8) for op in range(1, 8) for pattern in (0, 3)])
    add(6, [frame(cfg=combo << 16, threshold=t, pattern=pattern, seed=5 if combo == 2 else combo)
            for combo in range(8) for t in (0, 128, 255) for pattern in (1, 2)])
    if tier == 'smoke':
        sizes = [(w, h) for w in (2, 4, 6) for h in (1, 2, 3)]
    else:
        sizes = [(w, h) for w in (2, 4, 6, 1278, 1280) for h in (1, 2, 3, 720)]
    add(8, [frame(w=w, h=h, cfg=(2 << 4) | (4 << 8), pattern=2) for w, h in sizes])
    c0 = BC | GAMMA | GRAY
    c1 = BC | GAMMA | 4 | BIN | INV
    add(9, [frame(cfg=c0, bc=bc_value(128, -1), mid=32,
                  update=(0, c1, bc_value(511, 255), 255)),
            frame(enable=0, cfg=c1, bc=bc_value(511, 255), threshold=255, mid=32,
                  update=(1, c1, bc_value(0, 0), 0)),
            frame(cfg=c1, bc=bc_value(0, 0), threshold=0)])
    add(10, [frame(cfg=BC | (2 << 4) | (4 << 8) | BIN, flow=1),
             frame(cfg=(1 << 4) | (3 << 8), flow=2)])
    for stop, label in ((35, 'midline'), (64, 'eol'), (230, 'lastline')):
        cfg = (2 << 4) | (4 << 8)
        add(12, [frame(cfg=cfg, sent=stop), frame(cfg=cfg, seed=19)], '-' + label)
    add(13, [frame(cfg=GAMMA | 4 | (2 << 4) | (1 << 8), mid=32, flags=SOFT_MID),
             frame(cfg=GAMMA | 4, flags=SOFT_IDLE), frame(cfg=GAMMA | 4),
             frame(cfg=GAMMA | 4 | (2 << 4) | (1 << 8), sent=130,
                   mid=32, flags=SOFT_MID),
             frame(enable=0, flags=RESET_RESTART), frame(cfg=GAMMA | 4)])
    if tier == 'full':
        add(5, [frame(w=32, h=6, cfg=(a << 4) | (b << 8))
                for a in range(7) for b in range(7)])
        add(7, [frame(w=1280, h=720, cfg=BC | GAMMA | 4 | (a << 4) | (b << 8) | tail,
                      bc=bc_value(320, -17), pattern=4)
                for a, b, tail in ((2, 4, BIN), (5, 6, GRAY | INV), (1, 3, GRAY))])
        add(11, [frame(w=1280, h=6, cfg=(2 << 4) | (4 << 8), flags=FLUSH | NO_WAIT),
                 frame(w=1280, h=6, cfg=(2 << 4) | (4 << 8), flags=FLUSH, seed=2)])
        for seed in range(1, 11):
            rng = random.Random(seed)
            frames = []
            for i in range(6):
                w = rng.randrange(1, 641) * 2
                h = rng.randrange(2 if i in (1, 3) else 1, 65)
                cfg = rng.randrange(8) | (rng.randrange(8) << 4) | (rng.randrange(8) << 8)
                cfg |= rng.randrange(8) << 16
                sent = w * h // 2
                if i in (1, 3):
                    sent = rng.randrange(1, sent)
                frames.append(frame(w=w, h=h, enable=rng.randrange(2), cfg=cfg,
                                    bc=bc_value(rng.randrange(512), rng.randrange(-256, 256)),
                                    threshold=rng.randrange(256), pattern=rng.randrange(5),
                                    seed=seed * 17 + i, sent=sent, flow=1))
            add(14, frames, f'-seed{seed}')
    return result
