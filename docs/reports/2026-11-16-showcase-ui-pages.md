# Showcase UI pages — 2026-11-16

- 代码：改造前 `fdca476e2`；改造后代码 `742fd3533`，开始和完成均 rebase 到 `origin/zc100116/b3`。
- 范围：只改页面、增量组件、32 px 粗体字形和主机截图；首页积木塔入口由 T-TOWER-GAME 负责。

| 页面 | LVGL 部件和布局 |
|---|---|
| 目标检测计数 | 16.240 | 14.229 | -12.4% |
| 检测设置 | spinbox 数值行、80 类 switch 行、全选 / 全不选 dropdown、flex wrap |
| 图片识别 | 共用检测画布，table 结果、led 状态、spinner 加载、flex 侧栏 |
| 图像处理 | 分组面板、switch 行、slider 参数、滤波 dropdown、flex 滚动栏 |
| 图形引擎 | buttonmatrix 分段、两张 benchmark table、flex 功能测试列表和结果面板 |
| 经典游戏 | flex wrap 封面卡片，沿用游戏封面、名称位图和原入口动作 |
| 系统监控 | flex 浮窗、chart 60 秒带宽曲线、CPU / NPU / RND bar、网口 led |
| 芯片信息 | 参数 / 互连 / 模块状态 table、64 px CoreMark、spinner、性能计数器 table |
| 调试助手 | tabview 串口 / 网口、switch、dropdown、flex 数据和通信状态面板 |
| 人体姿态 / 手势 | flex 标题和侧栏，纯色名称 / 置信度徽章，保留原骨架和框绘制 |
| 人脸贴纸 | 15.334 | 13.952 | -9.0% |
| 简笔画 / 安全帽 | 32 px 粗体识别名；64 px 未戴 / 已戴计数、红绿纯色徽章 |
| 设置 | 显示组增加运行期保留的共享调试叠加；抓取判定组末尾增加抓取测试入口 |

- 经协调者授权，`shell.c` 只在会话框创建后设 `ignore_layout`，避免 flex 接管原坐标；新增失败态截图和定位断言。
- 新组件：`ui_page_layout`、`ui_panel`、`ui_data_table`、`ui_select`、`ui_live_badge`、`ui_flex_switch`、`ui_flex_number`；现有接口未变。
- 页面沿用 shell 公共顶栏、返回和底栏；摄像头标题条和侧栏为不透明静态面板，动态区域无阴影、模糊、半透明层或渐变。
- 粗体字形：保留现有 32 px 字形（含积木塔），加页面标题、`gesture.c` 的 20 个简笔画类别、等待识别 / 行人；Noto Sans SC Bold 2.004，命令和完整字符集在生成 C 文件头。
- 字形生成：`python3 tools/sw/gen_fonts.py --output-dir build/fonts --bold-font build/fonts/NotoSansSC-Bold.otf --bold-sizes 32 -- build/fonts/pages-glyphs.txt`；文本文件将上述字符集包在 `ui_emphasis(p,"…",false)` 中。
- 主机条件：Linux x86_64、GCC 13.3、锁定 LVGL、1280×720 ARGB8888 软件渲染；相同模拟画面和识别框 / 关键点，30 次整帧重绘平均 CPU 时间，含 RGB565 合成，不含文件写出。
- 姿态一人；贴纸预热 8 帧；手势前后均开启框 / 关键点，贴纸前后均关闭调试叠加；这是整帧重绘测量，不是 FPGA 上板时延。

| 摄像头页 | 改造前 ms | 改造后 ms | 变化 |
|---|---:|---:|---:|
| 目标检测计数 | 16.240 | 14.229 | -12.4% |
| 人体姿态 | 16.149 | 14.389 | -10.9% |
| 手势（调试叠加开） | 15.533 | 14.512 | -6.6% |
| 人脸贴纸 | 15.334 | 13.952 | -9.0% |
| 简笔画 | 15.367 | 14.064 | -8.5% |
| 安全帽 | 15.642 | 13.639 | -12.8% |

- 全部摄像头页满足不慢于旧版 10% 的要求；手势默认关闭叠加为 15.300 ms，贴纸开启叠加为 14.571 ms。
- 基线复现：`mkdir -p build/ui-before` 后，`for f in sw/apps/showcase/ui/*.c; do git show fdca476e2:$f > build/ui-before/${f##*/}; done`；普通字体生成命令：`python3 tools/sw/gen_fonts.py --output-dir build/sim/fonts --sizes 14 16 20 28 40 --digit-sizes 40 -- build/ui-before/*.c sw/apps/showcase/ui/*.[ch] sw/apps/showcase/sim/sim_data.c sw/apps/showcase/games/games.txt`。
- 删除已有截图可执行文件后构建基线：`flock /tmp/edrv32-sw-build.lock make -C sw/apps/showcase/sim -j2 "$PWD/build/sim/showcase_pages_shots" UI="$(printf '%s ' "$PWD"/build/ui-before/*.c)" PAGES_FLAGS=-DPAGES_BASELINE`；运行 `build/sim/showcase_pages_shots build/sim/ui-pages`，再删除该可执行文件，按下条命令构建新版。
- 新版截图 / 断言：`flock /tmp/edrv32-sw-build.lock make -C sw/apps/showcase/sim -j2 pages-shots PAGES_OUTPUT=/home/workspace/orca/workspaces/EdRV32-Competition-2026/SOC系统设计/outputs/ui-pages`：PASS，24 张 PNG；覆盖共享开关跨页保留、贴纸选择、抓取入口、阈值 / 类别、五类别面板、处理开关及页签、会话失败弹框原坐标。
- `flock /tmp/edrv32-sw-build.lock make -C sw/tests/showcase sticker grab`：PASS；原 `filter.c` 按测试 Makefile 的 C11 / Werror 命令编译执行：PASS。
- 两种目标构建：PASS，GCC 15.2、C11、`-Wall -Wextra -Werror`，0 告警；命令为 `flock /tmp/edrv32-sw-build.lock make -C sw -j2 PROGRAM=showcase`，以及追加 `SHOWCASE_POST=cpu`。
- 原始日志：`build/showcase/pages-before.log`、`pages-after.log`、`pages-tests.log`、`pages-build-hw.log`、`pages-build-cpu.log`；截图在上述 `PAGES_OUTPUT` 目录。
