# Render Fill DMA

`make case-sim CASE=vision/render-fill-dma`。使用 256-bit AXI 内存模型与随机 AW/W/B 背压，逐字节检查 RGB565/ARGB8888 纯色填充、边界 WSTRB 和 4 KiB Burst 拆分；另逐像素验证 RGB565 水平渐变、预乘 ARGB8888 垂直渐变、负步长及 0–255 截断。纯色填充保持多 beat Burst；渐变先生成每个 beat 的像素，再单 beat 写出，性能留待板级测试后优化。
