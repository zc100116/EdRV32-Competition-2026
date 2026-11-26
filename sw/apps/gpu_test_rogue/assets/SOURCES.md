# 棱炉地宫素材来源

- `actors.png`：本任务使用 Codex 内置 imagegen 生成的原创 4×2 角色/物件源图，2026-11-26；未使用第三方游戏角色或另一个肉鸽项目素材。生成内容不宣称 CC0，作为项目自制素材使用。
- `hud.bdf`：TakWolf / Fusion Pixel contributors 的 2026.11.10 12px monospaced zh_hans 字体，仅保留 G-4 实际使用字形，SIL OFL 1.1。上游：https://github.com/TakWolf/fusion-pixel-font/releases/tag/2026.11.10 ；许可与组件声明复用 `../../gpu_test_common/assets/fusion-pixel/OFL.txt`、`LICENSES/`。
- `dungeon.png` 为 G-5 使用 Codex 内置 imagegen 生成的原创机械地宫瓦片与四帧火焰源图；光晕、阴影、刀光透明度和金币由本目录工具构造；ASCII 是共享 public-domain console 字体。
- 处理规范：`../../gpu_test_common/assets/STYLE.md` 与 `../../gpu_test_common/tools/art.py`；面积缩小、72 色调色板量化、1px 深蓝描边，I8 块交织。原始源图入库，处理头文件仅在 build。

## actors.png 完整提示词

Use case: stylized-concept. Asset type: production pixel sprite source atlas for an original mechanical dungeon game 棱炉地宫. Make exactly 4 columns by 2 rows evenly spaced cells on transparent background, no labels, no grid lines, each object centered fully inside its own cell with generous empty margin. Each sprite should look 32x32 chunky pixel art enlarged, sharp dark navy outline, 2-3 shades, high saturation, overhead three-quarter view. Row 1 left to right: white and cyan box shell maintenance robot with little antenna and feet, coral red horned charging cube enemy, violet floating prism eye turret enemy, golden round cracked split-gel core enemy. Row 2 left to right: large gray-purple round floating furnace boss with bright orange core and detached angular claw arms, bright cyan wide angular energy cleaver pointing right with dark grip on left, closed brass treasure chest with cyan clasp, copper mechanical altar pedestal with cyan crystal. Original design only, no existing game characters, no text, no shadow background, true alpha transparency.


## dungeon.png 完整提示词（G-5，2026-11-26）

Use case: stylized-concept. Production pixel art texture sheet for original mechanical dungeon game. A precisely aligned 4 columns by 2 rows grid, equal square cells filling entire image, no margins no labels no text. Each cell is an orthographic flat seamless texture tile, NOT perspective and NOT a scene. Modern cartoon pixel art, dark navy outlines, 2-3 shade clusters, muted indigo/violet mechanical dungeon metal with teal highlights and orange vents. Top row left to right: worn steel floor with etched diamond; floor with inset grate; cracked steel floor; thick purple stone wall front with horizontal luminous orange exhaust grille. Bottom row left to right: thick wall top with bevel and bolts; wall with purple pipe and copper collars; heavy copper sliding door with glowing cyan jambs; four small separate cyan flame tongues arranged horizontally showing 4 distinct animation phases on very dark navy background. Clean readable texture details at 16 to 32 pixel downsample. Bright accents confined to vents, door frame and flames, floor dark blue purple.

四帧火焰先去除源图深蓝底色，再用公共 effect 处理；瓦片面积缩小并量化到同一72色。
原始 imagegen 源图作为项目自制素材使用，不宣称 CC0。
