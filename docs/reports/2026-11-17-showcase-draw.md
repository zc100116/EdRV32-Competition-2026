# 空中画板 T-DRAW

- 日期：2026-11-17；实现：本报告所在提交；验收基线 d9d55d942，最终 rebase a0e55ee05。
- 工具：xPack GCC 15.2.0，宿主 cc / LVGL 9.6；配置：showcase、1280×720 ARGB8888。
- 复用 UI_APP_GRAB 手部流水线；页面 20，食指尖 8，指点类别 3。
- 一阶低通 α=0.5，3 px 等距插点；原始帧间跳变 >120 px 断笔。
- 换手势立即抬笔，丢手 >200 ms 抬笔；工具条区域禁止落笔。
- 8 色、6/12/24 px；仅选中橡皮且指点时擦除；清空清除透明层。
- 工具条 x=180..1099、y=72..143；悬停 600 ms 选择，lv_arc 显示进度。
- 页面 40 ms 采样；笔迹增量写像素，仅失效新增笔迹和光标边界。
- `flock /tmp/edrv32-sw-build.lock make -C sw -j2 PROGRAM=showcase`：通过，0 告警。
- `make -C sw/tests/showcase draw`：通过，覆盖抬落笔、丢手、平滑、断笔、工具隔离、工具条。
- `flock /tmp/edrv32-sw-build.lock make -C sw/apps/showcase/sim -j2 draw-shots`：通过。
- 模拟页检查：真实 point-8 输入、悬停橡皮、按键遍历/选择/清空、返回体感标签、可见字体。
- 截图：`outputs/draw/writing.png`、`eraser.png`、`motion-tab.png`。
- 日志：`build/draw-build.log`、`build/draw-shots.log`；截图为宿主模拟，不代表实板帧率测量。
- 原创 imagegen 图标：`assets/icons/draw.png`；完整提示词见同目录 README。
