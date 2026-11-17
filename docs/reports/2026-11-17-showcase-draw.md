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

## T-DRAW-FIX：指尖平滑与落笔稳定
- 实现为本节所在提交；验收基线 76290bc71，最终 rebase 7cd0bd525（协调者确认无需重跑）；板上旧版 f9ad95530，结果分支 origin/win/20261117-96-r5-board。
- 原始数据：该分支 tasks/win/20261117-96-r5-board/artifacts/{uart/session.log,video/QQ20261117-151053.mp4}，用 git show 提取至 build/draw-fix/{session.log,board.mp4}。
- 复现量化：python3 sw/apps/showcase/sim/draw_measure.py build/draw-fix；Python 3、ffmpeg 7.0.2，结果 build/draw-fix/measurement.log。
- 15:10:53..15:11:49 绘画时段抽样 56 条，指点 35/56=62.5%；非指点连续采样长度分布 1:3、2:4、3:2、4:1（长度:次数），笔画计数 26→68。
- 日志仅 1 Hz，包含主动抬笔，无法还原逐帧比例或 ≤200 ms 中断分布；上述为时段抽样，不能当作分类器故障率。
- 录像归一化 1280×720：t=10 s、ROI x490..620/y240..310 白线中心去 31 px 滑动均值后 RMS 6.05 px、峰峰 28.08 px；含主动曲率，属空间抖动估计。
- 前 8 s 以 25 Hz 提取新增白色笔迹端点，129 次观测/60 组三连帧，二阶差分/√6 径向 RMS 7.91 px；受旧滤波、光栅化及主动移动影响，并非原始指尖误差。
- 分类或几何任一成立：食指尖掌根距离 > 中/无名指的 1.3 倍、>自身 PIP 的 1.2 倍，其余三指尖较 PIP 靠掌根，拇指距掌根 < 食指的 0.75 倍；2 帧落笔/4 帧非指点抬笔，丢手 ≤200 ms 直线接续。
- One Euro：min_cutoff=0.35 Hz、β=0.012（速度 px/s）、导数 cutoff=1 Hz，使用实际毫秒间隔；画笔 Catmull-Rom 延迟一帧，3 px 等距采样，累计长度 <10 px 暂存后丢弃；橡皮共享跟踪但直接直线擦除且不删短笔。
- 合成测试种子 42653887，900 帧/25 Hz、各轴 Gaussian σ=6 px、90 帧分类中断、7 帧丢手（恢复间隔 80/120/200 ms），得到预期 3 笔，无 <10 px 笔迹写出。
- 抖动指标 RMS(Δ(输出−真值))：输入 12.272 px→输出 2.485 px，降低 79.75%；位置 RMSE 6.662 px（含滤波滞后，不以抖动指标代替定位误差）。
- flock /tmp/edrv32-sw-build.lock 串行执行 make -C sw -j2 PROGRAM=showcase、make -C sw/tests/showcase draw、make -C sw/apps/showcase/sim -j2 draw-shots：全部通过、0 编译告警；日志 build/draw-fix/{build,host,shots}.log，截图 outputs/draw/smooth.png（宿主模拟，未重做上板）。
