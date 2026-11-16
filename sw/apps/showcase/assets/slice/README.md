# Original slice sprites

Built-in imagegen, 2026-11-16. All designs are original, transparent backgrounds.

## ruby.png (72×72)

Use case: stylized-concept. Asset type: original tiny AR game sprite. Bright flat cartoon, bold uniform dark navy outline, simple clean silhouette, limited cheerful colors, centered with small padding. Transparent background with real alpha. No text, no watermark, no existing game characters or franchises. A single original rounded raspberry red faceted gem shaped like a plump fruit, small turquoise leaf.

## lime.png (72×72)

Use case: stylized-concept. Asset type: original tiny AR game sprite. Bright flat cartoon, bold uniform dark navy outline, simple clean silhouette, limited cheerful colors, centered with small padding. Transparent background with real alpha. No text, no watermark, no existing game characters or franchises. A single original lime green faceted gem shaped like a plump fruit, small golden leaf.

## amber.png (72×72)

Use case: stylized-concept. Asset type: original tiny AR game sprite. Bright flat cartoon, bold uniform dark navy outline, simple clean silhouette, limited cheerful colors, centered with small padding. Transparent background with real alpha. No text, no watermark, no existing game characters or franchises. A single original amber orange faceted gem shaped like a plump pear, small turquoise leaf.

## berry.png (72×72)

Use case: stylized-concept. Asset type: original tiny AR game sprite. Bright flat cartoon, bold uniform dark navy outline, simple clean silhouette, limited cheerful colors, centered with small padding. Transparent background with real alpha. No text, no watermark, no existing game characters or franchises. A single original lavender purple faceted gem shaped like a plump berry, small mint leaf.

## bomb.png (72×72)

Use case: stylized-concept. Asset type: original tiny AR game sprite. Bright flat cartoon, bold uniform dark navy outline, simple clean silhouette, limited cheerful colors, centered with small padding. Transparent background with real alpha. No text, no watermark, no existing game characters or franchises. A single round dark purple cartoon hazard bomb with orange fuse and zigzag yellow warning emblem.

## spark.png (72×72)

Use case: stylized-concept. Asset type: original tiny AR game sprite. Bright flat cartoon, bold uniform dark navy outline, simple clean silhouette, limited cheerful colors, centered with small padding. Transparent background with real alpha. No text, no watermark, no existing game characters or franchises. A single compact white and turquoise four pointed cutting sparkle, clean angular rays.

## trail.png (20×20)

Use case: stylized-concept. Asset type: original tiny AR game sprite. Bright flat cartoon, bold uniform dark navy outline, simple clean silhouette, limited cheerful colors, centered with small padding. Transparent background with real alpha. No text, no watermark, no existing game characters or franchises. A single small turquoise glowing circular light bead, white center, teal outline, for a sword cursor trail.

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

Each 72×72 gem also provides separate, pre-cropped half sprites (36×72):

```python
im.crop((0, 0, 36, 72)).save(left_destination, interlace=False)
im.crop((36, 0, 72, 72)).save(right_destination, interlace=False)
```

These retain the original gem art; runtime rendering never rotates sprites.

Embed: `python3 tools/sw/embed_showcase_images.py sw/apps/showcase/assets/slice build/showcase/slice_images.c --prefix slice`.
