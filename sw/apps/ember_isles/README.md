# Ember Isles — C first version in progress

E3 systems run on the existing five-wave coast content. E4 content, E5 modes,
Chinese menus/HUD and the replacement art are pending; this is not the complete C release.
PC stability is also pending: the shared Linux host exceeded 16.67 ms on 4.72% of
frames in the platform measurement. See `docs/report-e3-platform.md`.

Build Linux, Windows, board and Spike from the repository root:

```sh
. ~/.local/opt/edrv32/env.sh
make -C sw/apps/ember_isles all test -j1
```

Products and generated tables/textures/music stay in `build/ember_isles/`.
Windows is a standalone executable; `--half` selects a 640×360 window.
Move with WASD, hold J to attack, Space to dash, Q to swap main/sub weapons,
K/L/U for skills and the ultimate, and F to light a nearby pillar.
Enter starts/pauses/returns; Esc toggles performance details in this E3 slice.
Upgrade choices use A/D or W/S, then J to confirm. Menus also accept left clicks.
The old placeholder art and HUD still show some E2 labels; E5/ART production will replace them.
The agreed bow/gun/greatsword charge controls are scheduled for E4.

Capture selected frames into an existing directory:

```sh
mkdir -p build/ember_isles/frames
build/ember_isles/ember_isles --replay sw/apps/ember_isles/assets/replays/coast.txt \
    --dump 206,764,1600 --out build/ember_isles/frames > build/ember_isles/pc.log
python3 sw/apps/ember_isles/tools/measure.py
```

Replays begin with `EMBER2 seed count`, followed by one decimal 16-bit keyboard
bitmap per frame (tech section 3). Menu clicks become the same recorded keyboard
commands; pointer coordinates do not enter simulation. The recording limit is
60,000 frames. PC and Spike print field summaries every 60 frames.
Spike measures simulation, display preparation and audio instructions; media MMIO
submission and hardware GPU cycles are not measured by that program.
The functional GPU emulator does not simulate clock cycles.

Only the PC configuration defines `GPU_EMU_TEXTURE_BYTES=262144`; the default
emulator configuration and board target retain the hardware 192 KiB capacity.
PC and board use the same game, drivers and GPU command rendering path.
