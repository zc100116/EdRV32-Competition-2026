# Render box shadow image

运行 `make case-sim CASE=vision/render-shadow-image`。在 1280×720 RGB565 画布上用三条 `BOX_SHADOW` 命令绘制不同模糊半径的圆角阴影，再用 `ROUND_RECT` 绘制不透明卡片本体，最后经 RTL 合成 DMA 输出 `sim/build/cases/vision/render-shadow-image/shadow.ppm`。同一 DDR 临时掩码区域按命令顺序复用。测试检查命令完成、卡片、阴影边缘、背景和未知像素。PNG 转换不插值、不改变仿真像素。

执行 `python3 sim/cases/vision/render-scale-image/render_image.py sim/build/cases/vision/render-shadow-image/shadow.ppm sim/build/cases/vision/render-shadow-image/shadow.png` 可生成 PNG；已验证的图片位于 `docs/validation/figures/2026-09-24-render-shadow-1280x720.png`。
