# Sling original sprites

Generated with the built-in imagegen tool, 2026-11-16. No existing game characters.

Each prompt uses this suffix:

> Bright flat cartoon, consistent thick dark teal outline, clean simple shapes readable over camera video, original object design. Centered isolated object fills canvas with small padding. Genuinely transparent background, no text, no cast shadow, no characters, no birds or pigs, no existing game references.

| File | Size | Subject prompt |
|---|---|---|
| slingshot.png | 110×190 | A single Y-shaped wooden slingshot, front view, fork ends at same height, golden wood and dark teal outlines, no rubber bands, tall 110:190 aspect |
| ball.png | 56×56 | A single round smooth turquoise stone projectile, circular silhouette, small cream glint, 1:1 aspect |
| crate.png | 88×88 | A single square golden wooden target crate with crossed planks, front view, 1:1 aspect |
| balloon-coral.png | 72×100 | A single coral red balloon with tiny knot and short string, 72:100 aspect |
| balloon-blue.png | 72×100 | A single sky blue balloon with tiny knot and short string, 72:100 aspect |
| platform.png | 180×28 | A single long horizontal wooden plank platform, front view, 240:28 aspect |
| wood-chip.png | 18×18 | A single small golden wooden splinter, compact polygon, 1:1 aspect |
| balloon-chip.png | 18×18 | A single curved coral rubber balloon fragment, 1:1 aspect |
| star.png | 48×48 | A single golden five pointed reward star, cream highlights, 1:1 aspect |

Prompt prefix: `Use case: stylized-concept. Asset type: small game sprite.`

Postprocessing (Pillow is already listed in tools/requirements.txt):

```python
from PIL import Image
im = Image.open(source).convert("RGBA")
im = im.crop(im.getchannel("A").getbbox())
im = im.resize((width, height), Image.Resampling.LANCZOS)
im.save(destination, interlace=False)
```

Only transparent padding is cropped; generated alpha is preserved. PNG files are 8-bit RGBA, non-interlaced.
Embed: `python3 tools/sw/embed_showcase_images.py sw/apps/showcase/assets/sling build/showcase/sling_images.c --prefix sling`.
