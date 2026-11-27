# Candy Canyon 素材来源

| 文件 / 模型 | 来源 / 许可 | 实际用途 |
|---|---|---|
| imagegen/materials.png | Codex imagegen 生成，项目自有 | 沙地、暖橙岩层、紫色矿岩、白青飞船和珊瑚无人机表面；64×64 RGB565 七级 mip |
| ../../gpu_test2d/assets/imagegen/ships-effects.png | Codex imagegen 生成，项目自有 | 共用发光贴图用于尾焰、晶体闪光、弹光和穿环粒子 |
| ../../gpu_test2d/assets/imagegen/environment-ui.png | Codex imagegen 生成，项目自有 | 云层、UI 面板边框及图标 |
| canyon.c 飞船 / 无人机 / 岩石 / 水晶 / 环 | 项目自建模型，项目自有 | 玩家飞船 176 三角形；无人机 48 三角形；岩石不规则多面体、水晶五棱柱、光环实体网格 |

不依赖外部 OBJ。棋盘、天空渐变和速度线为项目生成；字体沿用 Fusion Pixel / OFL 与 BSP ASCII。
内置 imagegen 提示词和处理参数见 [STYLE.md](STYLE.md) 与
[公共 STYLE](../../gpu_test_common/assets/STYLE.md)。Kenney 旧材质已替换。
