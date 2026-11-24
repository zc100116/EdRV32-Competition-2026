# Ember Isles E1/E2

From the repository root, one command builds Linux, Windows, board and Spike products:

```sh
. ~/.local/opt/edrv32/env.sh && make -C sw/apps/ember_isles all -j1
```

Products and generated tables/textures/music live in `build/ember_isles/`.
Windows is a standalone executable using the existing Win32 frontend; `--half`
selects a 640×360 window. Arrow keys move, Z/X activate A/B, Z+X activates the
charged ultimate, Enter starts or pauses, and Esc toggles performance details.
An upgrade uses the direction keys and A to choose one of three offers.

Replay the original demonstration and capture selected frames into an existing directory:

```sh
mkdir -p build/ember_isles/frames
build/ember_isles/ember_isles --replay sw/apps/ember_isles/assets/replays/coast.txt \
    --dump 120,3600,7200,10000 --out build/ember_isles/frames > build/ember_isles/pc.log
python3 sw/apps/ember_isles/tools/measure.py
```

The replay starts with `EMBER1 seed count`, then one decimal eight-bit controller
mask per frame. Interactive runs retain up to 60,000 frames in RAM through
`ember_game_recording()`; the 10,800-frame demonstration uses the same format. Its seed and bytes are embedded unchanged in the Spike target.
`STATE` records list simulation fields every 60 frames, while `PERF` records the
functional GPU counters. The GPU emulator does not simulate cycle timing.
Spike reports actual retired instructions for simulation, CPU display preparation
and audio, excluding media MMIO submission. The measurement tool compares the
complete field summaries and reports average and maximum instruction counts,
then converts them to cycles using tech.md's provisional CPI of 1.3.

CSV data, art sources, score and conversion tools are original project assets.
The art converter packs the generated pixel sheet and font into GPU I8 swizzles.
The E2 slice ends after clearing wave five; further stages are outside this build.
