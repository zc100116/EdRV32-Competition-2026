# Ember Isles E1/E2 original art and graphics

Required source resources: `ember-isles-source.png` and `ember-isles-weapons.png`.
Both are genuine built-in imagegen outputs, committed unchanged; no third-party art is used.
The second image edits only the three weapon cells of the first image.

Source generation prompt:
> Use case: stylized-concept. Asset type: original pixel-art game sprite atlas for Ember Isles. Create a square 1024x1024 sheet organized EXACTLY as 4 columns x 4 rows of equal 256x256 cells, no margins, no text. Each cell is a crisp low-resolution 32x32 pixel sprite enlarged nearest neighbor to fill its cell; flat solid pure black background, no grids or borders. Restrained 16-color aesthetic: midnight navy, cold teal blue, slate rocks, pale cyan, warm orange and gold fire. TOP-DOWN oblique retro game sprites, strong silhouettes. Row 1 cells left to right: seamless dark navy ocean ripples tile filling cell; seamless blue-black pebbled shore ground tile filling cell; rocky coast with cyan surf tile filling cell; dark stone path tile filling cell. Row 2: lone lantern keeper adventurer with orange scarf facing down; blue crab-like tide beast; dark teal rushing wolf-like tide beast; hooded blue tide caster. Row 3: orange ember projectile/fireball; cyan crescent tidal slash; iron throwing spike silver-orange; golden lantern orbit spark. Row 4: blazing orange campfire on small rocks; weathered blue lighthouse with orange light; cyan experience crystal; orange ember particle star. Original production pixel art, hard pixel edges, dark outlines, no antialiasing, no gradients, no labels, no shadows extending outside sprites. All non-ground sprites centered in cell with generous pure black empty space.

Weapon edit prompt:
> Use case: precise-object-edit. Keep this exact 4x4 original pixel-art sprite sheet, grid alignment, all tiles in first/second/fourth rows and first cell in third row unchanged. Replace ONLY three cells in the THIRD ROW: second cell becomes a circular ring of orange flame (hollow black center), third cell becomes a low spreading orange glowing ember bed (small coals and short flames), fourth cell becomes a brown ceramic fire pot with a flaming orange fuse. These are four ember/fire weapon effects with first fireball unchanged. Preserve pure black background for sprites, crisp pixel-art edges, cold blue coast / warm orange fire palette, no text, no borders. Do not modify any other cell.

Run from the repository root:
```sh
python3 sw/apps/ember_isles/tools/atlas_convert.py
make -f sw/apps/ember_isles/src/gfx2d/tests/Makefile check -j1
make -f sw/apps/ember_isles/src/gfx2d/tests/Makefile asan -j1
```
The standard-library-only converter reads the weapon PNG, reduces each cell to 32x32,
maps it to 31 opaque colors plus transparency, and emits GPU-spec 2.6 swizzled I8.
It also packs an original 5x7 ASCII font, its 2x version, an art-derived reef mask,
an 8x8 ember and a solid-color texture into `build/ember_isles/generated/atlas.h`.
The generated header exports `ember_atlas[]`, `ember_palette[]`, and byte/group constants.
Measured sizes: textures **65,600 B**, palettes **11,264 B**, combined **76,864 B**.
The combined size is below the 192 KiB texture budget even when counting palette storage.

Atlas coordinates: source cells occupy x=0..127/y=0..127 in row-major 32x32 cells.
Cell 0..3 terrain; 4 keeper; 5..7 enemies; 8..11 four ember weapons; 12 campfire;
13 lighthouse; 14 XP crystal; 15 ember star. Reef: (0,160), 32x32; ember: (0,192), 8x8.
Small font: (0,128), 16 columns of 8x8, ASCII 32..95; large font: (128,0), 8 columns of 16x16.
Palette groups: 0 art/font, 1 flash white, 2..9 UI colors, 10 dim terrain.
Solid texture: byte offset 65536, 8x8 I8; main atlas: offset 0, 256x256 I8.

The coordinator approved the UI argument change: `ember_gfx_prepare(sim, fps, ui)`.
`ui` is a pointer to game-owned `struct ember_ui_state` from `src/ui/ui.h`.
The game toggles `show_perf` on SELECT. No graphics code reads controller input.
`init` allocates DMA memory and copies resources; `prepare` only builds CPU data and
uses pure GPU encoders/address translation; `submit` owns MMIO, GPU/DISP and PERF reads.
No separate synthetic `ember_gfx_work` exists: Spike must measure actual `prepare`.
Camera clamps to sim world bounds; terrain reflects safe bounds and sim reefs.
The renderer reads sim positions, kinds, flashes, pickups, choices and events without writes.
Visual events emit hardware-stepped embers and damage glyphs into an 8000-object ring;
new effects replace the oldest ring entries. Only the first 640x180 stripe advances objects.
Pause/upgrade freeze object motion; both stripes resolve to one 640x360 RGB565 surface.
DISP L0_X2 presents 1280x720; the overlay displays previous-submit GPU PERF counters.

Validation: GCC, Zig x86_64-windows-gnu and RV32IM module compilation use
`-std=c11 -O2 -Wall -Wextra -Werror`; host and ASan preview tests pass.
The test prepares full enemy/shot/pickup/reef pools and wraps the particle ring,
checks sim immutability, checks real GPU particle emission/pause and emits seven PNGs
in `build/ember_isles/gfx-{menu,play,upgrade,won,lost,paused,coast}.png`.
An exploratory UBSan run additionally reported the existing external
`tools/gpu/emu/pc/png.c:20` zero-length NULL fwrite; that file is outside this task.
Full game replay, Spike instruction budgets and final four-target linking belong to integration.
Commit identity is recorded in this task's worker_done result.
