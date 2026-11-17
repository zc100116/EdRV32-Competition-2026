# 方块工坊原创美术

依据 `docs/design/2026-11-17-block-workshop.md` 第 3 节。
110 张运行时 PNG，straight-alpha RGBA8，ARGB8888 合计 **1,370,112 字节**。
新资源全部由 Pillow 原创绘制，无网络素材、无 imagegen 新原图，因此不创建 `source/`。
嵌入工具只读根目录 `*.png`；未来 `source/` 中的离线原图不会嵌入程序。

## 重生成

仓库根目录执行（Python 环境需安装 `tools/requirements.txt` 中的 Pillow）：

```sh
~/.local/opt/edrv32-py/bin/python tools/sw/compose_workshop_art.py \
  --preview-dir '/home/workspace/orca/workspaces/EdRV32-Competition-2026/SOC系统设计/outputs/workshop-art'
```

脚本用 4 倍画布绘制后 LANCZOS 缩小，避免像素风。材质左上浅色、右下深色，
两像素内斜边；冰和玻璃 alpha=180，树叶有透明缝隙。
斜坡后缀为直角所在角，斜边外透明并抗锯齿。裂纹种子 `20261117`，
每级保留此前全部分支、增加新分支并加粗旧分支，不生成随机独立图案。
光晕 144×144，中心 alpha 150，半径 71.5 px 外 alpha 0。

| 类别 | 数量 | 尺寸 |
|---|---:|---|
| 方块（含灯、窗双状态） | 17 | 48×48 |
| 门、木梁横竖、石柱横竖 | 5 | 门/竖件 48×96，横件 96×48 |
| 木/砖四方向斜坡 | 8 | 48×48 |
| 裂纹 | 8 | 48×48 |
| 小兔：walk 8、idle/lift/stun 各 2，左右各一套 | 28 | 64×56 |
| 小鸭：同上 | 28 | 56×56 |
| 空手/稿子双状态光标 | 4 | 64×64 |
| 工具和昼夜图标 | 5 | 56×56 |
| 暖光晕 | 1 | 144×144 |
| 扬尘、碎片 | 6 | 24×24 / 16×16 |

## 动画契约

| 角色 | walk 每循环步幅 | 支撑脚脚底 y（画布顶部为 0） | 10 fps 移速 |
|---|---:|---:|---:|
| bunny | 24 px | 52 px | 30 px/s |
| duck | 16 px | 52 px | 20 px/s |

位移速度 = 步幅 × 播放帧率 ÷ 8。支撑半周期脚向后匀速移动，
另一半周期抬脚回摆；左右腿相差半周期，身体周期起伏、兔耳和鸭翅摆动。
同一角色使用固定几何部件和配色；左朝向由完成的右朝向帧镜像，首尾周期连续。
idle 第二帧眨眼，lift 双腿交替晃动，stun 双帧星星转位，无伤害表现。
预览 GIF 是 10 fps 的原地步态展示；游戏应按上式同步角色位移。

## 预览

`--preview-dir` 下输出 `blocks.png`、`cracks.png`、`animals.png`、
`bunny-walk.gif`、`duck-walk.gif`。房屋背景是 Pillow 绘制并模糊、调暗的
室内摄像头示例画面（非真实相机采集），方块在场景中按实际显示像素绘制。

## 复用效果与完整 imagegen 提示词

`dust-1..3.png` 和 `shard-1..3.png` 原样复制 `../tower/`，原图、提示词和
原有清除低 alpha 残留、裁切留边流程见该目录 README。以下保留完整提示词：

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
