# Original mole sprites

Built-in imagegen, 2026-11-16. All designs are original, transparent backgrounds.

## hole.png (150×70)

Use case: stylized-concept. Asset type: original tiny AR game sprite. Bright flat cartoon, bold uniform dark navy outline, simple clean silhouette, limited cheerful colors, centered with small padding. Transparent background with real alpha. No text, no watermark, no existing game characters or franchises. A single oval garden burrow hole, dark interior with thick smooth ochre earth rim, seen slightly from above.

## monster.png (100×100)

Use case: stylized-concept. Asset type: original tiny AR game sprite. Bright flat cartoon, bold uniform dark navy outline, simple clean silhouette, limited cheerful colors, centered with small padding. Transparent background with real alpha. No text, no watermark, no existing game characters or franchises. A single cute original mint green pebble monster emerging, squat rounded body, two stubby antennae, happy eyes, no limbs below body.

## monster-hit.png (100×100)

Use case: stylized-concept. Asset type: original tiny AR game sprite. Bright flat cartoon, bold uniform dark navy outline, simple clean silhouette, limited cheerful colors, centered with small padding. Transparent background with real alpha. No text, no watermark, no existing game characters or franchises. A single cute original mint green pebble monster squashed flat with surprised star eyes, two stubby antennae, hit animation frame.

## gold.png (100×100)

Use case: stylized-concept. Asset type: original tiny AR game sprite. Bright flat cartoon, bold uniform dark navy outline, simple clean silhouette, limited cheerful colors, centered with small padding. Transparent background with real alpha. No text, no watermark, no existing game characters or franchises. A single cute original shiny golden pebble monster, squat rounded body, two stubby antennae, cheerful eyes, little diamond mark.

## bomb.png (88×88)

Use case: stylized-concept. Asset type: original tiny AR game sprite. Bright flat cartoon, bold uniform dark navy outline, simple clean silhouette, limited cheerful colors, centered with small padding. Transparent background with real alpha. No text, no watermark, no existing game characters or franchises. A single round purple cartoon hazard bomb with orange fuse and zigzag yellow warning emblem.

## impact.png (90×90)

Use case: stylized-concept. Asset type: original tiny AR game sprite. Bright flat cartoon, bold uniform dark navy outline, simple clean silhouette, limited cheerful colors, centered with small padding. Transparent background with real alpha. No text, no watermark, no existing game characters or franchises. A single compact yellow and coral starburst hit impact, four small spark rays, no text.

## Postprocessing

Pillow is already listed in `tools/requirements.txt`. Imagegen source files were moved into `build/games-art-source/`, then deleted after processing.

```python
from PIL import Image
im = Image.open(source).convert("RGBA")
im = im.crop(im.getchannel("A").getbbox())
im = im.resize((width, height), Image.Resampling.LANCZOS)
im.save(destination, interlace=False)
```

Generated alpha is preserved; final PNGs are RGBA8 and non-interlaced.

Embed: `python3 tools/sw/embed_showcase_images.py sw/apps/showcase/assets/mole build/showcase/mole_images.c --prefix mole`.
