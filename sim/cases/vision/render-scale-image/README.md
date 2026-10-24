# Render bitmap scale image

运行 `make case-sim CASE=vision/render-scale-image`。命令执行器在 1280×720 RGB565 画布上从同一个 96×96 RGB565 素材绘制四个独立位图元素：原始 1:1、最近邻 2 倍放大、最近邻 1/2 缩小、双轴翻转并 2 倍放大。素材紫色背景用颜色键透明处理。画布和前景都由 RTL 命令填充，最终经过 RTL 合成 DMA 写回 DDR，并输出 `sim/build/cases/vision/render-scale-image/scale.ppm`。测试另检查四个元素的已知像素及 AXI 错误状态。用 `python3 sim/cases/vision/render-scale-image/render_image.py sim/build/cases/vision/render-scale-image/scale.ppm sim/build/cases/vision/render-scale-image/scale.png` 无插值地转为 PNG，不修改仿真像素。验证图片保存于 `docs/validation/figures/2026-09-24-render-scale-1280x720.png`。

运行 `make case-sim CASE=vision/render-scale-image PARAMS=-Ptb_render_scale_image.GRADIENT_PANELS=1` 将四块底板改为水平/垂直渐变，输出 `gradient.ppm`；验证 PNG 位于 `docs/validation/figures/2026-09-24-render-gradient-1280x720.png`。
