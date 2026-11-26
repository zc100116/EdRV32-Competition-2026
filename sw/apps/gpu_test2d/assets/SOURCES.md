# Prism Patrol 素材来源

| 文件 | 来源 / 许可 | 实际用途 |
|---|---|---|
| imagegen/ships-effects.png | Codex imagegen 生成，项目自有 | 主角、3 种敌机、Boss、旋转部件、4 帧尾焰、护盾、陨石、掉落物、弹光、激光；导弹由金色敌机缩成 |
| imagegen/explosion.png | Codex imagegen 生成，项目自有 | 8 帧爆炸序列；火花复用弹光 |
| imagegen/environment-ui.png | Codex imagegen 生成，项目自有 | 星云、行星、云层、UI 面板边框及武器/血量/星/环图标 |

生成工具为 Codex 内置 imagegen；提示词和处理参数见 [STYLE.md](STYLE.md) 与
[公共 STYLE](../../gpu_test_common/assets/STYLE.md)。调色板、裁切、面积缩小、量化、
描边和 GPU atlas 打包均由项目 Python 标准库脚本完成。

中文继续使用 Fusion Pixel（SIL OFL 1.1），见
[字体来源](../../gpu_test_common/assets/SOURCES.md)；ASCII 为 BSP 的 public-domain 字体。
Kenney 旧 PNG 已由以上统一画风素材替换。
