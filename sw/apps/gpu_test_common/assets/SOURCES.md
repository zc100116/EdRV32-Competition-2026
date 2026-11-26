# 中文字体来源

| 文件 | 作者 | 来源 | 许可 | 用途 |
|---|---|---|---|---|
| fusion-pixel/hud.bdf | TakWolf / Fusion Pixel contributors | [Fusion Pixel 2026.11.10, 12px monospaced BDF zh_hans](https://github.com/TakWolf/fusion-pixel-font/releases/tag/2026.11.10) | SIL OFL 1.1 | HUD 实际使用的 54 个中文字形子集 |
| fusion-pixel/OFL.txt、LICENSES/* | 上游及组件作者，详见各 OFL | [上游](https://github.com/TakWolf/fusion-pixel-font) | SIL OFL 1.1 | 原始许可及组件版权声明 |

`hud.bdf` 仅删除未使用字形，保留上游 BDF 属性；字形无修改。构建直接解析 BDF，不依赖系统字体或第三方 Python 包。
ASCII 仍用 `sw/lib/font8x16.h` 的 public-domain console 字体。
