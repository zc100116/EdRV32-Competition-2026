# Showcase UI frame — 2026-11-16

- 代码：`76afc2e56`，基于最新 `origin/zc100116/b3` 的 `cc7abd99f`。
- 范围：R4 §4、§5、§8.1 D6；未修改视觉后端、平台、调度和游戏规则。
- 主题：背景 `#eff3f8`、面板 `#ffffff`、正文 `#152b45`、强调蓝 `#2563eb`、青绿 `#0d9488`。
- 间距：8 / 12 / 16 / 24 px；圆角：8 / 12 / 20 px；正文 14 / 16 / 20，粗体标题 32 / 48，数字 64 / 96 px。
- 部件样式：tabview、button、imagebutton、buttonmatrix、switch、spinbox、slider、dropdown、roller；
  menu、msgbox、bar、arc、spinner、led、chart、scale、table。
- 薄组件：应用卡片、场景卡片、单选分段、开关行、数值行（加减）、粗体标题、渐变胶囊、大号数字、握拳停留 arc。
- 动态样式无阴影、模糊和整层半透明；注释限定渐变胶囊用于静态区域，旧页面辅助函数保留。
- 场景入口：智能视觉 · 检测计数 → 实时识别；体感积木 → 抓取测试（积木塔完成前）。
- AI 视觉（7）：目标检测计数、安全帽检测、人体姿态、手势识别、人脸贴纸、简笔画识别、图片识别。
- 体感互动（6）：积木塔、弹弓打靶、石头剪刀布、打地鼠、切图形、接物篮。
- 图形多媒体（3）：图像处理、图形引擎、经典游戏；系统（4）：系统监控、芯片信息、调试助手、设置。
- 四键遍历两张场景卡与全部 20 张应用卡，跨分类切换；五个体感游戏直达，返回体感互动页签。
- 设置：镜像、性能窗、抓取模式 A–D、各模式阈值、关键点、曝光；运行期保留并沿用串口输出。
- 协调者答复调整范围：调试叠加共享开关留给后续页面改造，贴纸 / 手势现有按钮保留。
- 字体：Noto Sans SC Bold 2.004，OFL-1.1；源字体仅在 build，生成命令在 C 文件头。
- 新字体 C 文件 426,058 字节；4 个 RV32 目标文件常量 67,756 字节，其中字形位图 66,584 字节。
- 原创 imagegen 图标 20×96×96、场景插图 2×528×176；PNG 共 408,498 字节，ARGB8888 像素共 1,480,704 字节，RV32 目标文件常量共 1,481,320 字节。
- 提示词：`sw/apps/showcase/assets/icons/README.md`；转换使用现有 `embed_showcase_images.py`。
- 主机：Linux x86_64、GCC 13.3、LVGL 锁定版本，软件 ARGB8888 渲染，计时包括 RGB565 画面合成，不含文件写出。
- 首页四页单帧分别 12.950 / 10.368 / 9.222 / 9.400 ms；设置 8.760 ms；游戏开始画面 15.554 ms。
- 截图及断言：`flock /tmp/edrv32-sw-build.lock make -C sw/apps/showcase/sim -j2 frame-shots FRAME_OUTPUT=<下列目录>`：PASS。
- 截图目录：`/home/workspace/orca/workspaces/EdRV32-Competition-2026/SOC系统设计/outputs/ui-frame/`（6 张 PNG，不入库）。
- 主机覆盖：四页卡片数量 / 页宽、22 卡焦点与高亮、五游戏入口 / 返回、模式阈值独立、模式 C 禁用阈值、设置跨页保留、缺字检查。
- `flock /tmp/edrv32-sw-build.lock make -C sw/tests/showcase games grab`：PASS。
- `flock /tmp/edrv32-sw-build.lock make -C sw -j2 PROGRAM=showcase`：PASS，GCC 15.2、C11、`-Wall -Wextra -Werror`。
- `flock /tmp/edrv32-sw-build.lock make -C sw -j2 PROGRAM=showcase SHOWCASE_POST=cpu`：PASS，0 告警。
- 原始日志：`build/showcase/frame-shots.log`、`games-grab.log`、`build-hw.log`、`build-cpu.log`。
