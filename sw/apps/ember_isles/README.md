# Ember Isles — C first version in progress

E3 and the submitted E4 content run on the existing five-wave coast. E4b is
implementing the six decisions recorded in GDD section 2.4; E5 modes, Chinese
menus/HUD and replacement art are pending. This is not the complete C release.
PC stability is also pending: the shared Linux host exceeded 16.67 ms on 4.72% of
frames in the platform measurement. See `docs/report-e3-platform.md`.

Build Linux, Windows, board and Spike from the repository root:

```sh
. ~/.local/opt/edrv32/env.sh
export PATH="$HOME/.local/opt/video/bin:$PATH"
make -C sw/apps/ember_isles all test -j1
```

Products and generated tables/textures/music stay in `build/ember_isles/`.
The music converter requires ffmpeg on PATH; Python uses only its standard library.
Three licensed recordings and sampled effects are linked into the executable.
Track selection and loop quality await user listening; see `docs/report-audio-c1.md`.
Distribute `assets/CREDITS.md` with the executable for the CC BY music attribution.
Windows is a standalone executable; `--half` selects a 640×360 window.
Move with WASD, hold J to attack, Space to dash, Q to swap main/sub weapons,
K/L/U for skills and the ultimate, and F to light a nearby pillar.
Enter starts/pauses/returns; Esc toggles performance details in this E3 slice.
Upgrade choices use A/D or W/S, then J to confirm. Menus also accept left clicks.
The old placeholder art and HUD still show some E2 labels; E5/ART production will replace them.
Bow, gun and greatsword now hold J to charge and release J to fire; early release
fires a normal attack. The focused-core staff evolution also gains charging.

Capture selected frames into an existing directory:

```sh
mkdir -p build/ember_isles/frames
build/ember_isles/ember_isles --replay sw/apps/ember_isles/assets/replays/coast.txt \
    --dump 206,764,1600 --out build/ember_isles/frames > build/ember_isles/pc.log
spike --isa=rv32im_zicsr_zicntr --priv=m --pmpregions=0 --no-dm --disable-dtb \
    -m0x80000000:0x40000000 --pc=0x80000000 \
    build/ember_isles/ember_isles-spike.elf > build/ember_isles/spike.log
python3 sw/apps/ember_isles/tools/compare_replay.py \
    build/ember_isles/pc.log build/ember_isles/spike.log
```

This comparison checks determinism and prints the ending state. Mode acceptance
also requires a victorious ending; matching summaries alone do not prove a clear.

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
