# Showcase 桌面界面

先执行 `. ~/.local/opt/edrv32/env.sh`，再运行：

```
make -C sw/apps/showcase/sim shots win
```

生成 `build/sim/showcase_sim.exe` 和 `build/sim/shots/*.png`（1280×720）。
Windows 使用系统 DLL，无额外运行库。← / → 移动焦点，Enter 激活，Esc 返回；
鼠标点击等价于选择并确认。F1 切换全部模块与无 PIX/GEO 两种硬件能力。
游戏画面中按返回两次回到列表。

`ui/` 使用共享静态样式和 `ui_data.h`，`sim_data.c` 按 LVGL 时钟提供固定脚本数据。
图表每秒更新；统计每秒两次，仅修改变化的对象。默认主题关闭，无切换动画。
示例照片由内置 imagegen 生成，提示词见 `assets/README.md`，构建脚本只用 Python 标准库。

协调者在 P2 实施期间明确调整：两个桌面版本均使用 `sim_data.c` 的八个固定游戏条目，
以首字和色块作图标，不读取 games.txt 或 ROM。游戏来源和字体覆盖留待 P3 确定。
性能页数值由协调者提供的卡 46 数据固定生成；RND 关闭值为 P2 授权的固定估算，P3 改接板上数据。

现有板上 showcase 不变，本目录不参与其构建。
