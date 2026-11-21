# Original catch sprites

Built-in imagegen, 2026-11-16. All designs are original, transparent backgrounds.

## basket.png (150×76)

Use case: stylized-concept. Asset type: original tiny AR game sprite. Bright flat cartoon, bold uniform dark navy outline, simple clean silhouette, limited cheerful colors, centered with small padding. Transparent background with real alpha. No text, no watermark, no existing game characters or franchises. A single wide shallow woven golden basket with open top, turquoise rim and small handles, front view, 150:76 aspect.

## apple.png (60×60)

Use case: stylized-concept. Asset type: original tiny AR game sprite. Bright flat cartoon, bold uniform dark navy outline, simple clean silhouette, limited cheerful colors, centered with small padding. Transparent background with real alpha. No text, no watermark, no existing game characters or franchises. A single original coral red cartoon apple, tiny golden leaf, teal outline.

## pear.png (60×60)

Use case: stylized-concept. Asset type: original tiny AR game sprite. Bright flat cartoon, bold uniform dark navy outline, simple clean silhouette, limited cheerful colors, centered with small padding. Transparent background with real alpha. No text, no watermark, no existing game characters or franchises. A single original light green cartoon pear, tiny turquoise leaf, teal outline.

## orange.png (60×60)

Use case: stylized-concept. Asset type: original tiny AR game sprite. Bright flat cartoon, bold uniform dark navy outline, simple clean silhouette, limited cheerful colors, centered with small padding. Transparent background with real alpha. No text, no watermark, no existing game characters or franchises. A single original golden orange cartoon citrus fruit with tiny mint leaf, teal outline.

## plum.png (60×60)

Use case: stylized-concept. Asset type: original tiny AR game sprite. Bright flat cartoon, bold uniform dark navy outline, simple clean silhouette, limited cheerful colors, centered with small padding. Transparent background with real alpha. No text, no watermark, no existing game characters or franchises. A single original lavender purple cartoon plum with tiny mint leaf, teal outline.

## bomb.png (60×60)

Use case: stylized-concept. Asset type: original tiny AR game sprite. Bright flat cartoon, bold uniform dark navy outline, simple clean silhouette, limited cheerful colors, centered with small padding. Transparent background with real alpha. No text, no watermark, no existing game characters or franchises. A single round purple cartoon hazard bomb with orange fuse and zigzag yellow warning emblem.

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

Embed: `python3 tools/sw/embed_showcase_images.py sw/apps/showcase/assets/catch build/showcase/catch_images.c --prefix catch`.
