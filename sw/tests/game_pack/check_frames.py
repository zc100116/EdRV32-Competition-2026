#!/usr/bin/env python3
"""check_frames.py: showcase design 4.4; compare all pixels of 600 frames.
Host execution only; generated files and logs remain under build/sw/game-pack.
"""
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[3]
OUT = ROOT / 'build/sw/game-pack/frames'
OUT.mkdir(parents=True, exist_ok=True)
for name, app in [('baseline', 'sw/apps/nes'), ('step', 'sw/apps/showcase/nes')]:
    destination = OUT / name
    destination.mkdir(exist_ok=True)
    makefile = destination / 'Makefile'
    makefile.write_text(f'''.DEFAULT_GOAL := all
ROOT := {ROOT}
OUT := {destination}
CC := gcc
include {ROOT / app}/sources.mk
SOURCES := $(NES_CORE) $(NES_COMMON) sw/tests/game_pack/frame_host.c
OBJECTS := $(addprefix $(OUT)/obj/,$(SOURCES:.c=.o))
CFLAGS := -std=c11 -Wall -Wextra -Werror -ffunction-sections \
    -fdata-sections $(NES_FLAGS) -I{ROOT / app}
.PHONY: all FORCE
all: $(OUT)/frame-host
FORCE:
$(OUT)/frame-host: $(OBJECTS)
\t$(CC) $(OBJECTS) -Wl,--gc-sections $(NES_WRAPS) -lm -o $@
$(OUT)/obj/%.o: $(ROOT)/%.c FORCE
\tmkdir -p $(@D)
\t$(CC) $(CFLAGS) -c $< -o $@
''')
    with (destination / 'build.log').open('w') as log:
        subprocess.run(['make', '-j1', '-f', str(makefile)], cwd=ROOT, check=True,
                       stdout=log, stderr=subprocess.STDOUT)
    with (destination / 'run.log').open('w') as log:
        subprocess.run([str(destination / 'frame-host'),
                        str(ROOT / 'sw/apps/nes/roms/nrom-template.nes'),
                        str(destination / 'frames.rgb'), *(['restart'] if name == 'step' else [])],
                       check=True,
                       stdout=log, stderr=subprocess.STDOUT)
frame_bytes = 256 * 240 * 3
with ((OUT / 'baseline/frames.rgb').open('rb') as baseline,
      (OUT / 'step/frames.rgb').open('rb') as step):
    for frame in range(1, 601):
        expected, actual = baseline.read(frame_bytes), step.read(frame_bytes)
        assert len(expected) == len(actual) == frame_bytes, f'frame {frame} missing'
        if expected != actual:
            offset = next(i for i, (a, b) in enumerate(zip(expected, actual)) if a != b)
            raise AssertionError(f'frame {frame}, pixel {offset // 3}: differs')
    assert baseline.read() == b'', 'unexpected extra baseline frame'
    baseline.seek(0)
    for frame in range(1, 601):
        expected, actual = baseline.read(frame_bytes), step.read(frame_bytes)
        assert len(actual) == frame_bytes and expected == actual, f'restart frame {frame} differs'
    assert step.read() == b'', 'unexpected extra step frame'
print('PASS continuous loop vs cooperative step: 600 frames, 36864000 pixels identical')
print('PASS stop/restart in the same process: all 600 frames remain identical')
