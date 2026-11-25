# Ember Isles asset credits

Music: Eric Skiff — **A Night Of Dizzy Spells**, **Arpanauts**, **Chibi Ninja** —
*Resistor Anthems* — [Available at EricSkiff.com/music](https://ericskiff.com/music/).
License: [Creative Commons Attribution 4.0 International](https://creativecommons.org/licenses/by/4.0/).
The author's original page was verified on 2026-11-24 and explicitly grants CC BY 4.0.
Original direct MP3 downloads are stored in `music/` with filename spaces removed.
`music/stages.csv` maps coast / forest / crater to those three recordings respectively.
This is a **provisional mapping**: user listening and scene-fit approval remain pending.

Modifications: decoded/resampled to 48 kHz stereo; each music loop overlaps the final
one second with the first one second using an equal-gain crossfade, omits the initial
one second, normalizes peak to 10000 PCM units, and quantizes to G.711 mu-law.
These are edited full recordings, not original compositions or claimed native seamless loops.
The generated binary is linked into the same mixer on PC and board.
Loop musical timing, full-track quality and the quantized sound remain subject to listening.

Sound effects: **Kenney**, [Starter Kit FPS](https://github.com/KenneyNL/Starter-Kit-FPS/tree/185fd2326d74a5cf858cffc616f87cf9696f9cc0),
commit `185fd2326d74a5cf858cffc616f87cf9696f9cc0`.
The original README explicitly licenses included sound effects as
[CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/); the separate MIT
software license does not describe these sound assets.
Exact original `sounds/` files copied unchanged into `audio/`:
`blaster.ogg`, `blaster_repeater.ogg`, `enemy_attack.ogg`, `enemy_destroy.ogg`,
`enemy_hurt.ogg`, `weapon_change.ogg`.

Sound effects: **Kenney**, [Starter Kit 3D Platformer](https://github.com/KenneyNL/Starter-Kit-3D-Platformer/tree/3fa8a04b1c01ab23db43123d4ce814a34c3fc7f0),
commit `3fa8a04b1c01ab23db43123d4ce814a34c3fc7f0`.
The original README explicitly licenses sound effects as **CC0 1.0**.
Exact original `sounds/` files: `break.ogg`, `coin.ogg`, `jump.ogg`.
Both pinned original READMEs were verified on 2026-11-24.

Sound modifications: resample to 48 kHz stereo, normalize each cue to peak 4000,
encode mu-law; level-up/victory layer three/four upward-transposed coin sounds,
and block slows the coin bell to half pitch. Shot, iron hit, elemental hit, kill,
dash, seed, explosion, choose/weapon-change, hurt and pickup use the named source
cues in `tools/music_convert.py`. All effects remain pending user listening approval.
No commercial game recordings, third-party mirrors or website download bypasses were used.

Font: **Fusion Pixel Font**, 12px monospaced zh_Hans, release **2026.11.10**,
copyright (c) 2022 TakWolf and the contributors listed in the upstream licenses.
Source: [TakWolf/fusion-pixel-font](https://github.com/TakWolf/fusion-pixel-font),
[original release](https://github.com/TakWolf/fusion-pixel-font/releases/tag/2026.11.10).
License: **SIL Open Font License 1.1**; the unmodified BDF, OFL text and original
component notices are preserved in `fonts/` (`OFL.txt`, `LICENSES/`, `SOURCE.txt`).
The converter extracts native glyph bitmaps used by game text into build outputs;
it does not rescale the glyphs. Distribute the OFL and component notices with the
game containing this font.

The additional 12px U+2212 mathematical minus is an original Ember Isles glyph,
dedicated by this project to **CC0**; it is separate from the upstream font.

## ART-3 coast, 06a-2 source checkpoint

The new `art_coast/sources/smith-common-down-06a2-input.png` and
`reef-crab-down-06a2-input.png` are original outputs of the built-in imagegen tool,
using this project's previously generated keeper/smith/crab images as references.
Prompts, source images and processing notes are saved under `art_coast/`.
The smith image is a rejected production trial; the crab image is a partial
front-facing I8 capacity checkpoint, not a completed or quality-approved coast pack.
No external commercial game assets or third-party source packs were used here.

## ART-3 coast, 06a-2c compact-frame checkpoint

The six new PNG source images under `art_coast/sources/*06a2c*-input.png` are
original built-in imagegen outputs: tide biter, salt charger (two trials),
drowned watcher (two trials), and mist jellyfish. Prompts are saved beside each
image; existing project enemy/crab art supplies only style and pixel-grid references.
Native grid samples, palettes and foot-anchor placement are produced by the
standard-library art converter. Rejected fine-density trials and the oversized
tide-biter draft are retained and identified in `art_coast/PROCESS.txt`.
These are incomplete front-facing source studies, not an approved full coast pack.
No external source pack or commercial game artwork is included.

## ART-3 coast, 06a-2d continued production

The PNG sources named `*06a2d*` in `art_coast/sources/` are original built-in
imagegen outputs, using this project's accepted native sprite references.
Prompts are stored beside the raw images. Native sheets preserve the authored
square-pixel grid; explicit head copies are1:1 translations, and small clothing
seam repairs have literal coordinates in sheet metadata. Original and repaired
sheets are retained; the inspection page displays their actual pixel difference.
Rejected size, facing or transparency trials remain identified by the production
manifest and PROCESS notes. They are not included in the delivered frame table.
No commercial game art, external source pack or third-party generated asset is used.

The nine2–16px particle types in `art_coast/coast-particle-pixels-06a2d.json`
are original literal pixel drawings by Codex, authorized by msg_aac2628fcd8c.
Their38 frames are copied1:1 from the saved ASCII artwork, with five elemental
palette groups; no procedural shape formula, bitmap scaling or rotation is used.
The rejected built-in imagegen particle studies are retained under `sources/`.

The two64×64 functional light textures in `art_coast/coast-light-masks-06a2d-native.png`
are original mathematical radial gradients with a4×4 Bayer pattern, authorized
by msg_164d7644a991. They reuse unreferenced indices of the existing star palette;
they are functional blend masks rather than imagegen artwork or external textures.
The remaining06a-2d guardian/Boss death parts, hostile tide effects and30item icons
are original built-in imagegen material; prompts and raw inputs remain in `art_coast/sources/`.

## ART-3 coast, 06a-2e elite auras and pickups

The eight `coast-elite-aura-*-06a2e` six-frame sheets and five
`coast-pickup-*-06a2e` icons are original built-in imagegen outputs for this project.
Full prompts and raw images are preserved in `art_coast/sources/`, including the
rejected ward checkerboard study and its transparency correction prompt.
Native sheets restore the declared square-pixel grids; the eight I4 auras use
the first16 entries of existing RGB565+A4 groups. A common index permutation
preserves every previous palette color and elemental variant, including the
star group's reserved light indices. Fanatic and health reuse the keeper's
crimson scarf ramp. No commercial game artwork or external asset pack is used.
