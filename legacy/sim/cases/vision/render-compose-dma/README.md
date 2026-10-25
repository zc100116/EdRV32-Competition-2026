# Render Compose DMA

`make case-sim CASE=vision/render-compose-dma`。随机背压下检查 RGB565 底图与预乘 ARGB8888 前景的原地及异址合成，逐像素比较并输出 `sim/build/cases/vision/render-compose-dma/render.ppm`。
