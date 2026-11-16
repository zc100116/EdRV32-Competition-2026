# 积木塔原创美术资源

依据：`docs/design/2026-11-16-showcase-r4-plan.md` §6；T-TOWER-ART。

所有纹理和其他元素均由内置 imagegen 原创生成；不使用网络或现有游戏素材。
PNG 使用 straight-alpha RGBA8；ARGB8888 装载成本为宽 × 高 × 4，与 PNG 压缩大小无关。

## 重生成积木

依赖 Pillow（已列于 `tools/requirements.txt`）。在仓库根目录运行：

```sh
PATH="$HOME/.local/opt/edrv32-py/bin:$PATH" python3 tools/sw/compose_tower_blocks.py
# 也可明确输入、输出目录：
PATH="$HOME/.local/opt/edrv32-py/bin:$PATH" python3 tools/sw/compose_tower_blocks.py \
  --textures sw/apps/showcase/assets/tower/textures --output build/tower-art/blocks
```

2026-11-16：橡胶合成时用固定种子 20261116 增加 ±5 级细颗粒和对角柔和高光，
重新生成六张橡胶积木；保留原始纹理和几何。

工具按原始像素尺度平铺纹理，以形状遮罩裁切，添加向内 2 px 深色描边、
上左斜面高光和下右暗部，用 4 倍采样抗锯齿，输出 0° PNG。
冰、玻璃的主体 alpha 为 179/255（约 0.702），其余主体完全不透明；
轮廓以外 alpha=0，斜边有抗锯齿过渡。矩形轮廓填满画布，透明区仅存在于轮廓外。

## 形状与物理几何

唯一代码定义：`tools/sw/compose_tower_blocks.py` 的 `SHAPES`。
下表坐标原点为图片左上角，x 向右、y 向下，单位为 1280×720 画面的显示像素。
坐标描述连续的几何边界（不是末像素索引）；碰撞形状必须使用相同边界，描边向内，不扩大尺寸。

| 形状 | 画布 | 几何边界 |
|---|---|---|
| square | 80×80 | 顶点 (0,0), (80,0), (80,80), (0,80) |
| plank | 240×40 | 顶点 (0,0), (240,0), (240,40), (0,40) |
| brick | 120×60 | 顶点 (0,0), (120,0), (120,60), (0,60) |
| triangle | 120×80 | 等腰屋顶；顶点 (60,0), (120,80), (0,80) |
| arch | 160×80 | 同心上半圆环；圆心 (80,80)，外半径 80，底部半圆缺口半径 40；y≤80 |
| circle | 80×80 | 圆心 (40,40)，半径 40 |

拱的实体为 `40² ≤ (x−80)²+(y−80)² ≤ 80²` 且 `y≤80`；
下方两脚各宽 40 px，缺口直径 80 px。物理侧可按设计要求将此轮廓分解为凸形状。

## imagegen 提示词和后处理

每张源纹理对应以下完整提示词。生成结果缩为 128×128，沿 x/y 镜像拼成 256×256，
因此相对边的像素完全一致，可以连续平铺；冰和玻璃纹理的 alpha 设为 179。
其他元素保留原始透明通道，清除 alpha<24 的低透明度背景残留，按前景边界裁切，
缩放到目标画布内并保留 2 px 透明边距；平台、架、尺按指定长宽比整形。
徽章不含文字，高度尺不含数字；文字和数字均由程序绘制。

### `textures/wood.png`

Use case: stylized-concept. Original 2D cartoon stacking game material texture: pale honey blond wood, flowing horizontal grain and tiny knots. Clean polished painted game art, crisp readable restrained detail, warm highlights, no perspective, no border, no objects, no text, no shadow. A seamless tile filling the entire square edge to edge; opposite edges match. Designed to be resized to 256x256 and masked into small building blocks.

### `textures/stone.png`

Use case: stylized-concept. Original 2D cartoon stacking-game material texture. Seamless medium cool gray stone material tile, fitted large subtle irregular stone slabs, clean readable shapes and gentle speckled texture. Style: clean polished painted cartoon game art, crisp clear edges, restrained shading, readable against a dim camera background. Square image filled edge to edge, opposite edges tile seamlessly, flat material swatch, no border, no text, no perspective, no scene, no cast shadow.

### `textures/ice.png`

Use case: stylized-concept. Original 2D cartoon stacking-game material texture. Seamless pale blue ice material tile, fine branching cracks and icy white highlights, translucent frozen water appearance, no snow. Style: clean polished painted cartoon game art, crisp clear edges, restrained shading, readable against a dim camera background. Square image filled edge to edge, opposite edges tile seamlessly, flat material swatch, no border, no text, no perspective, no scene, no cast shadow.

### `textures/metal.png`

Use case: stylized-concept. Original 2D cartoon stacking-game material texture. Seamless brushed steel material tile, horizontal brushed silver grain, restrained small round rivet heads in repeating layout, metallic highlight. Style: clean polished painted cartoon game art, crisp clear edges, restrained shading, readable against a dim camera background. Square image filled edge to edge, opposite edges tile seamlessly, flat material swatch, no border, no text, no perspective, no scene, no cast shadow.

### `textures/rubber.png`

Use case: stylized-concept. Original 2D cartoon stacking-game material texture. Seamless vivid vermilion orange-red matte rubber material tile, subtle fine dimples, diffuse soft lighting, no glossy reflections. Style: clean polished painted cartoon game art, crisp clear edges, restrained shading, readable against a dim camera background. Square image filled edge to edge, opposite edges tile seamlessly, flat material swatch, no border, no text, no perspective, no scene, no cast shadow.

### `textures/glass.png`

Use case: stylized-concept. Original 2D cartoon stacking-game material texture. Seamless cyan glass material tile, broad diagonal white reflective stripes, transparent tinted glass appearance, no cracks. Style: clean polished painted cartoon game art, crisp clear edges, restrained shading, readable against a dim camera background. Square image filled edge to edge, opposite edges tile seamlessly, flat material swatch, no border, no text, no perspective, no scene, no cast shadow.

### `hand-open.png`

Use case: stylized-concept. Original 2D cartoon stacking-game sprite. One white open hand cursor, five clearly separated fingers, palm facing viewer, thumb on left, dark navy thick outline, simple readable silhouette. Isolated centered icon. Style: clean polished painted cartoon game art, crisp clear edges, restrained shading, readable against a dim camera background. Genuinely transparent background, isolated single asset, full object visible with a small transparent margin, no cast shadow, no scene, no text, no watermark.

### `hand-fist.png`

Use case: stylized-concept. Original 2D cartoon stacking-game sprite. One white clenched fist hand cursor, four folded knuckles and thumb across front, palm facing viewer, dark navy thick outline, simple readable silhouette. Isolated centered icon. Style: clean polished painted cartoon game art, crisp clear edges, restrained shading, readable against a dim camera background. Genuinely transparent background, isolated single asset, full object visible with a small transparent margin, no cast shadow, no scene, no text, no watermark.

### `rotate-hint.png`

Use case: stylized-concept. Original 2D cartoon stacking-game sprite. One compact gesture instruction icon, white V-sign scissors hand with exactly two extended fingers, bold dark navy outline, with one bright cyan clockwise curved arrow above and around it indicating quarter turn. No text, no numbers. Readable at 48 pixels. Style: clean polished painted cartoon game art, crisp clear edges, restrained shading, readable against a dim camera background. Genuinely transparent background, isolated single asset, full object visible with a small transparent margin, no cast shadow, no scene, no text, no watermark.

### `platform.png`

Use case: stylized-concept. Original 2D cartoon stacking-game sprite. One long horizontal stone platform for a side-view stacking game, aspect ratio 11.25:1, flat level straight top, chunky carved slate gray blocks, bright bevel top edge, dark navy clean outline. Front view, no perspective, no feet, no ground, no scenery. Entire platform visible. Style: clean polished painted cartoon game art, crisp clear edges, restrained shading, readable against a dim camera background. Genuinely transparent background, isolated single asset, full object visible with a small transparent margin, no cast shadow, no scene, no text, no watermark.

### `shelf.png`

Use case: stylized-concept. Original 2D cartoon stacking-game sprite. One tall narrow side-view wooden game inventory shelf, aspect ratio 160:420, exactly three vertically stacked open empty compartments, pale warm wood frame with dark navy edging, cyan corner brackets. Front view, perfectly vertical, no objects inside, no backdrop. Style: clean polished painted cartoon game art, crisp clear edges, restrained shading, readable against a dim camera background. Genuinely transparent background, isolated single asset, full object visible with a small transparent margin, no cast shadow, no scene, no text, no watermark.

### `ruler.png`

Use case: stylized-concept. Original 2D cartoon stacking-game sprite. One tall narrow golden height ruler, aspect ratio 56:480, straight vertical measuring stick with crisp alternating short and long dark tick marks on the left edge. No numerals, no letters, no hands. Front view, flat, entirely visible. Style: clean polished painted cartoon game art, crisp clear edges, restrained shading, readable against a dim camera background. Genuinely transparent background, isolated single asset, full object visible with a small transparent margin, no cast shadow, no scene, no text, no watermark.

### `dust-1.png`

Use case: stylized-concept. Original 2D cartoon stacking-game sprite. One tiny cream beige landing dust puff sprite, three rounded cloud lobes, crisp cartoon outline, no ground, no other objects, compact and readable at 24 pixels. Style: clean polished painted cartoon game art, crisp clear edges, restrained shading, readable against a dim camera background. Genuinely transparent background, isolated single asset, full object visible with a small transparent margin, no cast shadow, no scene, no text, no watermark.

### `dust-2.png`

Use case: stylized-concept. Original 2D cartoon stacking-game sprite. One tiny cream beige landing dust puff sprite, asymmetric spreading cloud with four rounded lobes and two small floating dust dots, no ground, compact and readable at 24 pixels. Style: clean polished painted cartoon game art, crisp clear edges, restrained shading, readable against a dim camera background. Genuinely transparent background, isolated single asset, full object visible with a small transparent margin, no cast shadow, no scene, no text, no watermark.

### `dust-3.png`

Use case: stylized-concept. Original 2D cartoon stacking-game sprite. One tiny cream beige dispersing landing dust sprite, three separated rounded small wisps forming one compact icon, no ground, readable at 24 pixels. Style: clean polished painted cartoon game art, crisp clear edges, restrained shading, readable against a dim camera background. Genuinely transparent background, isolated single asset, full object visible with a small transparent margin, no cast shadow, no scene, no text, no watermark.

### `shard-1.png`

Use case: stylized-concept. Original 2D cartoon stacking-game sprite. One tiny cyan glass shard sprite, a triangular thin transparent glass fragment with white glint and clean dark turquoise outline, isolated, readable at 16 pixels. Style: clean polished painted cartoon game art, crisp clear edges, restrained shading, readable against a dim camera background. Genuinely transparent background, isolated single asset, full object visible with a small transparent margin, no cast shadow, no scene, no text, no watermark.

### `shard-2.png`

Use case: stylized-concept. Original 2D cartoon stacking-game sprite. One tiny cyan glass shard sprite, a narrow irregular diamond transparent glass fragment with white glint and clean dark turquoise outline, isolated, readable at 16 pixels. Style: clean polished painted cartoon game art, crisp clear edges, restrained shading, readable against a dim camera background. Genuinely transparent background, isolated single asset, full object visible with a small transparent margin, no cast shadow, no scene, no text, no watermark.

### `shard-3.png`

Use case: stylized-concept. Original 2D cartoon stacking-game sprite. One tiny cyan glass shard sprite, a small angular trapezoid transparent glass fragment with white glint and clean dark turquoise outline, isolated, readable at 16 pixels. Style: clean polished painted cartoon game art, crisp clear edges, restrained shading, readable against a dim camera background. Genuinely transparent background, isolated single asset, full object visible with a small transparent margin, no cast shadow, no scene, no text, no watermark.

### `badge-record.png`

Use case: stylized-concept. Original 2D cartoon stacking-game sprite. One blank golden orange achievement badge banner, wide 200:80 aspect ratio, rounded central rectangular plaque with generous totally empty central space for program-rendered text, small ribbon tabs on the sides, bright bevel highlights and thick dark navy outline. No text, no letters, no symbols, no stars. Style: clean polished painted cartoon game art, crisp clear edges, restrained shading, readable against a dim camera background. Genuinely transparent background, isolated single asset, full object visible with a small transparent margin, no cast shadow, no scene, no text, no watermark.

### 合成的 36 张积木

各 `block-<material>-<shape>.png` 使用对应 `textures/<material>.png` 的上述提示词，
再由工具根据几何表合成；没有为每个形状重新生成纹理。每个文件和对应提示词如下：

| 输出文件 | 提示词来源 |
|---|---|
| `block-wood-square.png` | `textures/wood.png` 完整提示词 + `square` 几何遮罩 |
| `block-wood-plank.png` | `textures/wood.png` 完整提示词 + `plank` 几何遮罩 |
| `block-wood-brick.png` | `textures/wood.png` 完整提示词 + `brick` 几何遮罩 |
| `block-wood-triangle.png` | `textures/wood.png` 完整提示词 + `triangle` 几何遮罩 |
| `block-wood-arch.png` | `textures/wood.png` 完整提示词 + `arch` 几何遮罩 |
| `block-wood-circle.png` | `textures/wood.png` 完整提示词 + `circle` 几何遮罩 |
| `block-stone-square.png` | `textures/stone.png` 完整提示词 + `square` 几何遮罩 |
| `block-stone-plank.png` | `textures/stone.png` 完整提示词 + `plank` 几何遮罩 |
| `block-stone-brick.png` | `textures/stone.png` 完整提示词 + `brick` 几何遮罩 |
| `block-stone-triangle.png` | `textures/stone.png` 完整提示词 + `triangle` 几何遮罩 |
| `block-stone-arch.png` | `textures/stone.png` 完整提示词 + `arch` 几何遮罩 |
| `block-stone-circle.png` | `textures/stone.png` 完整提示词 + `circle` 几何遮罩 |
| `block-ice-square.png` | `textures/ice.png` 完整提示词 + `square` 几何遮罩 |
| `block-ice-plank.png` | `textures/ice.png` 完整提示词 + `plank` 几何遮罩 |
| `block-ice-brick.png` | `textures/ice.png` 完整提示词 + `brick` 几何遮罩 |
| `block-ice-triangle.png` | `textures/ice.png` 完整提示词 + `triangle` 几何遮罩 |
| `block-ice-arch.png` | `textures/ice.png` 完整提示词 + `arch` 几何遮罩 |
| `block-ice-circle.png` | `textures/ice.png` 完整提示词 + `circle` 几何遮罩 |
| `block-metal-square.png` | `textures/metal.png` 完整提示词 + `square` 几何遮罩 |
| `block-metal-plank.png` | `textures/metal.png` 完整提示词 + `plank` 几何遮罩 |
| `block-metal-brick.png` | `textures/metal.png` 完整提示词 + `brick` 几何遮罩 |
| `block-metal-triangle.png` | `textures/metal.png` 完整提示词 + `triangle` 几何遮罩 |
| `block-metal-arch.png` | `textures/metal.png` 完整提示词 + `arch` 几何遮罩 |
| `block-metal-circle.png` | `textures/metal.png` 完整提示词 + `circle` 几何遮罩 |
| `block-rubber-square.png` | `textures/rubber.png` 完整提示词 + `square` 几何遮罩 |
| `block-rubber-plank.png` | `textures/rubber.png` 完整提示词 + `plank` 几何遮罩 |
| `block-rubber-brick.png` | `textures/rubber.png` 完整提示词 + `brick` 几何遮罩 |
| `block-rubber-triangle.png` | `textures/rubber.png` 完整提示词 + `triangle` 几何遮罩 |
| `block-rubber-arch.png` | `textures/rubber.png` 完整提示词 + `arch` 几何遮罩 |
| `block-rubber-circle.png` | `textures/rubber.png` 完整提示词 + `circle` 几何遮罩 |
| `block-glass-square.png` | `textures/glass.png` 完整提示词 + `square` 几何遮罩 |
| `block-glass-plank.png` | `textures/glass.png` 完整提示词 + `plank` 几何遮罩 |
| `block-glass-brick.png` | `textures/glass.png` 完整提示词 + `brick` 几何遮罩 |
| `block-glass-triangle.png` | `textures/glass.png` 完整提示词 + `triangle` 几何遮罩 |
| `block-glass-arch.png` | `textures/glass.png` 完整提示词 + `arch` 几何遮罩 |
| `block-glass-circle.png` | `textures/glass.png` 完整提示词 + `circle` 几何遮罩 |

## 内存成本

协调者已确认预算口径：`textures/` 仅用于离线重生成，不嵌入程序；
2.5 MB 限额只计下表运行时的 36 张积木及 13 张其他元素。

| 运行时文件 | 尺寸 | ARGB8888 字节 |
|---|---|---:|
| `badge-record.png` | 200×80 | 64,000 |
| `block-glass-arch.png` | 160×80 | 51,200 |
| `block-glass-brick.png` | 120×60 | 28,800 |
| `block-glass-circle.png` | 80×80 | 25,600 |
| `block-glass-plank.png` | 240×40 | 38,400 |
| `block-glass-square.png` | 80×80 | 25,600 |
| `block-glass-triangle.png` | 120×80 | 38,400 |
| `block-ice-arch.png` | 160×80 | 51,200 |
| `block-ice-brick.png` | 120×60 | 28,800 |
| `block-ice-circle.png` | 80×80 | 25,600 |
| `block-ice-plank.png` | 240×40 | 38,400 |
| `block-ice-square.png` | 80×80 | 25,600 |
| `block-ice-triangle.png` | 120×80 | 38,400 |
| `block-metal-arch.png` | 160×80 | 51,200 |
| `block-metal-brick.png` | 120×60 | 28,800 |
| `block-metal-circle.png` | 80×80 | 25,600 |
| `block-metal-plank.png` | 240×40 | 38,400 |
| `block-metal-square.png` | 80×80 | 25,600 |
| `block-metal-triangle.png` | 120×80 | 38,400 |
| `block-rubber-arch.png` | 160×80 | 51,200 |
| `block-rubber-brick.png` | 120×60 | 28,800 |
| `block-rubber-circle.png` | 80×80 | 25,600 |
| `block-rubber-plank.png` | 240×40 | 38,400 |
| `block-rubber-square.png` | 80×80 | 25,600 |
| `block-rubber-triangle.png` | 120×80 | 38,400 |
| `block-stone-arch.png` | 160×80 | 51,200 |
| `block-stone-brick.png` | 120×60 | 28,800 |
| `block-stone-circle.png` | 80×80 | 25,600 |
| `block-stone-plank.png` | 240×40 | 38,400 |
| `block-stone-square.png` | 80×80 | 25,600 |
| `block-stone-triangle.png` | 120×80 | 38,400 |
| `block-wood-arch.png` | 160×80 | 51,200 |
| `block-wood-brick.png` | 120×60 | 28,800 |
| `block-wood-circle.png` | 80×80 | 25,600 |
| `block-wood-plank.png` | 240×40 | 38,400 |
| `block-wood-square.png` | 80×80 | 25,600 |
| `block-wood-triangle.png` | 120×80 | 38,400 |
| `dust-1.png` | 24×24 | 2,304 |
| `dust-2.png` | 24×24 | 2,304 |
| `dust-3.png` | 24×24 | 2,304 |
| `hand-fist.png` | 72×72 | 20,736 |
| `hand-open.png` | 72×72 | 20,736 |
| `platform.png` | 720×64 | 184,320 |
| `rotate-hint.png` | 48×48 | 9,216 |
| `ruler.png` | 56×480 | 107,520 |
| `shard-1.png` | 16×16 | 1,024 |
| `shard-2.png` | 16×16 | 1,024 |
| `shard-3.png` | 16×16 | 1,024 |
| `shelf.png` | 160×420 | 268,800 |

运行时合计：**1,933,312 字节**（49 张，≤2,500,000 字节）。

| 离线源纹理 | 尺寸 | ARGB8888 字节 |
|---|---|---:|
| `textures/glass.png` | 256×256 | 262,144 |
| `textures/ice.png` | 256×256 | 262,144 |
| `textures/metal.png` | 256×256 | 262,144 |
| `textures/rubber.png` | 256×256 | 262,144 |
| `textures/stone.png` | 256×256 | 262,144 |
| `textures/wood.png` | 256×256 | 262,144 |

离线源纹理合计：**1,572,864 字节**；含源纹理总计：**3,506,176 字节**（55 张）。

## 预览与验证

预览：`SOC系统设计/outputs/tower-art.png`（共享输出目录，不入库）。
1280×720 深色摄像头示意背景上按原始显示尺寸排列 36 块积木和全部其他元素，
右侧第二个架是同图镜像缩略示例；所有运行时 PNG 的背景为透明。

验收：执行上述重生成命令；逐项检查 36 张尺寸、RGBA 模式和 alpha、
拱中心缺口透明、源纹理相对边连续，比较重新生成文件的解码像素与入库文件一致。
本任务不涉及 RTL 或程序源代码，Verilator lint 不适用。

已执行：默认输出命令、指定输出命令、Python 编译检查和 `git diff --check`，全部通过。
36 张重生成结果的解码像素完全一致；49 张运行时 PNG 的尺寸、alpha、拱缺口和
6 张纹理的相对边像素检查通过。重生成后可直接复查像素和运行时字节数：

```sh
PATH="$HOME/.local/opt/edrv32-py/bin:$PATH" python3 - <<'PY'
from pathlib import Path
from PIL import Image
assets = Path('sw/apps/showcase/assets/tower')
for path in sorted(assets.glob('block-*.png')):
    generated = Image.open(Path('build/tower-art/blocks') / path.name)
    assert Image.open(path).tobytes() == generated.tobytes(), path.name
total = sum(Image.open(p).width * Image.open(p).height * 4
            for p in assets.glob('*.png'))
print('36 blocks identical; runtime ARGB8888:', total)
PY
```
