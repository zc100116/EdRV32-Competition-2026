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

游戏数据由 `tools/sw/gen_sim_games.py` 从 `../games/games.txt` 的第一列生成，
两端均展示同一份 30 款游戏；名字字符也进入字体子集。脚本不读取 ROM。
第三列封面路径相对仓库的 `third_party/nes/`，留空时显示首字色块。
封面输入仅支持 8 位 RGB/RGBA、非交错 PNG；JPG/JPEG 明确报错，不使用其他解码库。
图片等比缩放到 120×160 以内，不裁剪，居中留白，透明像素合成到白底后转 RGB565。
改动已使用的 PNG 后构建会重新生成游戏数据；更改封面路径需修改清单。
游戏卡片以四键线性选择，超出一屏时立即滚动到焦点位置。
性能页数值由协调者提供的卡 46 数据固定生成；RND 关闭值为 P2 授权的固定估算，P3 改接板上数据。

现有板上 showcase 不变，本目录不参与其构建。
