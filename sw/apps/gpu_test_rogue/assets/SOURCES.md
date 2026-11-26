# 棱炉地宫素材来源

- `actors.png`：本任务使用 Codex 内置 imagegen 生成的原创 4×2 角色/物件源图，2026-11-26；未使用第三方游戏角色或另一个肉鸽项目素材。生成内容不宣称 CC0，作为项目自制素材使用。
- `hud.bdf`：TakWolf / Fusion Pixel contributors 的 2026.11.10 12px monospaced zh_hans 字体，仅保留 G-4 实际使用字形，SIL OFL 1.1。上游：https://github.com/TakWolf/fusion-pixel-font/releases/tag/2026.11.10 ；许可与组件声明复用 `../../gpu_test_common/assets/fusion-pixel/OFL.txt`、`LICENSES/`。
- 地砖、门、光晕、金币由本目录工具原创生成；ASCII 是共享 public-domain console 字体。
- 处理规范：`../../gpu_test_common/assets/STYLE.md` 与 `../../gpu_test_common/tools/art.py`；面积缩小、72 色调色板量化、1px 深蓝描边，I8 块交织。原始源图入库，处理头文件仅在 build。

## actors.png 完整提示词

Use case: stylized-concept. Asset type: production pixel sprite source atlas for an original mechanical dungeon game 棱炉地宫. Make exactly 4 columns by 2 rows evenly spaced cells on transparent background, no labels, no grid lines, each object centered fully inside its own cell with generous empty margin. Each sprite should look 32x32 chunky pixel art enlarged, sharp dark navy outline, 2-3 shades, high saturation, overhead three-quarter view. Row 1 left to right: white and cyan box shell maintenance robot with little antenna and feet, coral red horned charging cube enemy, violet floating prism eye turret enemy, golden round cracked split-gel core enemy. Row 2 left to right: large gray-purple round floating furnace boss with bright orange core and detached angular claw arms, bright cyan wide angular energy cleaver pointing right with dark grip on left, closed brass treasure chest with cyan clasp, copper mechanical altar pedestal with cyan crystal. Original design only, no existing game characters, no text, no shadow background, true alpha transparency.
