# Showcase 桌面界面

先执行 `. ~/.local/opt/edrv32/env.sh`，再运行：

```
make -C sw/apps/showcase/sim shots
```

生成 `build/sim/showcase_shots` 和 `build/sim/shots/*.png`（1280×720）。
`make -C sw/apps/showcase/sim win` 可生成 Windows 原生模拟器；本次流水线验收使用
Linux 无窗口截图程序，不运行 SoC 仿真或板端构建。

视觉流水线以全屏 RGB565 L0 为主画面，ARGB8888 L1 绘制预设行、积木链、参数、
硬件路径与菜单。← / → 移动焦点，Enter 打开积木菜单，Esc 逐级返回；滑条和
下拉框按 Enter 编辑，再用 ← / → 调整，Enter 或 Esc 退出编辑。
长积木链按焦点自动横向滚动，每块保留 160×90 缩略图。参数面板可纵向滚动。
来源卡可以切换摄像头、PC 图片、测试图，在链首插入积木，或看来源原图（view=0xFE）；
HDMI 卡返回最终输出。

`pipeline.c` 实现冻结的链接口、8 种预设及合法性规则，拒绝时保持原链。
硬件跳表按设计 7.4 粗略合并、拆分，耗时、帧率和带宽为模拟数字。
同次 PIX 的积木以底色分组并共用输出缩略图；看此级也显示该次 PIX 的完整输出。
链首融合标注“与摄像头融合”，摄像头入口耗时显示“随摄像头帧”。
`process.c` 用现有照片计算各级 PIX / GEO 预览，检测使用固定框，缩略图由各级输出缩放。
“叠加界面”使用示意条，未模拟实时 LVGL 整层快照；板上合成由硬件执行器负责。
看此级通过 chain.view 选择模拟 L0。静态照片只在链内容变化时重算，UI 每 200 ms
刷新缩略图；Windows 使用 bottom layer 模拟 L0，Linux 在 flush 时按 DISP alpha 合成。

截图和真实 LVGL keypad 用例由 `main_shots.c` 统一运行：

- `pipeline-standard.png`：标准识别；
- `pipeline-rotation.png`：整屏旋转，选中几何积木；
- `pipeline-filter.png`：多级滤波与硬件融合 / 拆分；
- `pipeline-menu.png`：积木菜单。

用例断言移动、插入、删除、换功能、改参数、看此级、8 种预设、中文拒绝提示、
检测门槛设置、PC 图片翻页以及空链 / 满链编辑；截图递归检查缺字和静态标签越界。
同时保留游戏、图形引擎、CoreMark、调试助手、鼠标恢复界面和会话重试的主机用例。
原有视觉识别、图片识别、图像处理三页及旧 PROCESS 接口已删除。

游戏仍从 `../games/games.txt` 生成名字和封面；不读取 ROM。封面由仓库标准库
PNG 工具解码，照片提示词见 `assets/README.md`。字体从 UI 源码提取中文子集。
