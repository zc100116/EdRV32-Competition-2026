# Render A8 blur

运行 `make case-sim CASE=vision/render-a8-blur`。使用独立整数参考模型逐像素比较 DDR 源 A8 蒙版的水平与垂直两遍盒式模糊，覆盖不满 32 字节的行、跨多个 DDR beat、图像高度小于或大于模糊窗口、半径 0–15、随机 AXI 背压和区域外字节保持。临时区和输出区都存放在 DDR；边界之外按零填充，平均值按最近整数取整。
