# Render gallery

运行 `make case-sim CASE=vision/render-gallery` 绘制 640×360 测试画布；运行 `make case-sim CASE=vision/render-gallery PARAMS=-Ptb_render_gallery.SCALE=2` 绘制目标显示规格的 **1280×720** 画布。两者使用同一份 DDR 命令列表和 RTL，SCALE=2 时图形坐标、尺寸、半径与边框宽度同步放大。内容为底色、ARGB 前景清除、8 个不同大小的圆角矩形与圆、4 个 A8 字形、RGB565 棋盘纹理、透明 ARGB 圆形素材，以及一次同前景层内的斜向重叠 COPY，最后原地合成。检查命令完成、背景/圆心采样、已知像素、AXI Burst 长度和 4 KiB 边界；输出 `sim/build/cases/vision/render-gallery/gallery.ppm`。两次运行共用这个文件名，先保存需要的输出再运行另一种尺寸。

该 case 用于观察画布实际像素下的边缘效果；精确的圆角、边框和透明度逐像素参考比对仍由 `vision/render-engine` case 负责。将 PPM 无缩放地转成 PNG 即可查看，不要用最近邻放大图来判断实际显示的平滑程度。
