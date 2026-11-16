# Original rps sprites

Built-in imagegen, 2026-11-16. All designs are original, transparent backgrounds.

## player-rock.png (120×120)

Use case: stylized-concept. Asset type: original tiny AR game sprite. Bright flat cartoon, bold uniform dark navy outline, simple clean silhouette, limited cheerful colors, centered with small padding. Transparent background with real alpha. No text, no watermark, no existing game characters or franchises. A single teal cartoon human hand in a closed fist, the rock hand sign, front view.

## player-scissors.png (120×120)

Use case: stylized-concept. Asset type: original tiny AR game sprite. Bright flat cartoon, bold uniform dark navy outline, simple clean silhouette, limited cheerful colors, centered with small padding. Transparent background with real alpha. No text, no watermark, no existing game characters or franchises. A single teal cartoon human hand making a V with index and middle finger, scissors hand sign.

## player-paper.png (120×120)

Use case: stylized-concept. Asset type: original tiny AR game sprite. Bright flat cartoon, bold uniform dark navy outline, simple clean silhouette, limited cheerful colors, centered with small padding. Transparent background with real alpha. No text, no watermark, no existing game characters or franchises. A single teal cartoon human open palm with five fingers, paper hand sign.

## board-rock.png (120×120)

Use case: stylized-concept. Asset type: original tiny AR game sprite. Bright flat cartoon, bold uniform dark navy outline, simple clean silhouette, limited cheerful colors, centered with small padding. Transparent background with real alpha. No text, no watermark, no existing game characters or franchises. A single warm orange cartoon robot glove in a closed fist, rock hand sign, front view.

## board-scissors.png (120×120)

Use case: stylized-concept. Asset type: original tiny AR game sprite. Bright flat cartoon, bold uniform dark navy outline, simple clean silhouette, limited cheerful colors, centered with small padding. Transparent background with real alpha. No text, no watermark, no existing game characters or franchises. A single warm orange cartoon robot glove making a V with index and middle finger, scissors hand sign.

## board-paper.png (120×120)

Use case: stylized-concept. Asset type: original tiny AR game sprite. Bright flat cartoon, bold uniform dark navy outline, simple clean silhouette, limited cheerful colors, centered with small padding. Transparent background with real alpha. No text, no watermark, no existing game characters or franchises. A single warm orange cartoon robot glove open with five fingers, paper hand sign.

## win.png (64×64)

Use case: stylized-concept. Asset type: original tiny AR game sprite. Bright flat cartoon, bold uniform dark navy outline, simple clean silhouette, limited cheerful colors, centered with small padding. Transparent background with real alpha. No text, no watermark, no existing game characters or franchises. A single golden medal with a green checkmark, compact circular victory badge.

## lose.png (64×64)

Use case: stylized-concept. Asset type: original tiny AR game sprite. Bright flat cartoon, bold uniform dark navy outline, simple clean silhouette, limited cheerful colors, centered with small padding. Transparent background with real alpha. No text, no watermark, no existing game characters or franchises. A single purple circular badge containing a simple orange cross, friendly defeat marker.

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

Embed: `python3 tools/sw/embed_showcase_images.py sw/apps/showcase/assets/rps build/showcase/rps_images.c --prefix rps`.
