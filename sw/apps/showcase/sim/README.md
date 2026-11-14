# Showcase 桌面界面

先执行 `. ~/.local/opt/edrv32/env.sh`，再运行：

```
make -C sw/apps/showcase/sim shots win
```

生成 `build/sim/showcase_sim.exe` 和 `build/sim/shots/*.png`（1280×720）。
Windows 使用系统 DLL，无额外运行库。← / → 移动焦点，Enter 激活，Esc 返回；
鼠标点击使用标准控件行为，悬停与键盘焦点分开显示。
滑条和下拉框按 Enter 进入编辑，← / → 调整，Enter 或 Esc 退出编辑；
再次 Esc 才退出子视图或页面。F1 切换全部模块与无 PIX/GEO 两种硬件能力。
游戏画面中按 Esc 回到列表，焦点保留在刚才的游戏。

`ui/` 使用共享静态样式和 `ui_data.h`，`sim_data.c` 按 LVGL 时钟提供固定脚本数据。
图表每秒更新；统计每秒两次，仅修改变化的对象。默认主题关闭，无切换动画。
示例照片由内置 imagegen 生成，提示词见 `assets/README.md`，构建脚本只用 Python 标准库。

游戏数据由 `tools/sw/gen_sim_games.py` 从 `../games/games.txt` 的第一列生成，
两端均展示同一份 30 款游戏；名字字符也进入字体子集。脚本不读取 ROM。
第三列封面路径相对仓库的 `third_party/nes/`，留空时显示首字色块。
封面输入仅支持 8 位 RGB/RGBA、非交错 PNG；JPG/JPEG 明确报错，不使用其他解码库。
图片等比缩放到 120×160 以内，不裁剪，居中留白，透明像素合成到白底后转 RGB565。
改动已使用的 PNG 后构建会重新生成游戏数据；更改封面路径需修改清单。
游戏卡片以四键线性选择，超出一屏时立即滚动到焦点位置。
性能页数值由协调者提供的卡 46 数据固定生成；RND 关闭值为 P2 授权的固定估算，P3 改接板上数据。

本目录与板上 showcase 共用 ui/，模拟器后端独立于硬件驱动。

P4 显示模拟：GUI 使用 ARGB8888 L1；示例图片模拟全屏 L0。Linux 截图在 flush
时按 DISP alpha 公式合成两层，再输出 PNG。Windows 用 bottom layer 模拟底图。
`process.c` 在参数改变时按 PIX/GEO 公式计算处理预览，与界面渲染分离。
`vision.png`、`image.png`、`process.png`、`process-collapsed.png` 分别为视频类
三页和图像处理参数面板收起状态。

P5 截图程序使用真实 LVGL keypad 的 NEXT / PREV / ENTER / ESC，遍历全部页面和
子视图的可用控件，并断言焦点自动滚动、滑条/下拉框编辑、开关/类别、图片五种状态、
翻页忙时禁用、会话重试，以及设置→页面→首页、游戏→列表→首页的逐级返回。
会话和图片状态可由 sim_data_session / sim_data_image_status 固定，默认按时钟脚本变化。
处理预览遵循 enabled 位，逐项默认保留启用状态，全部默认清除全部启用位。
截图还包含 process-stage-off、process-editing、image-*、keyboard-focus、mouse-hover
及 session-failed / session-starting / session-stopping。
