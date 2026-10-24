# Render + HDMI shared DDR

运行 `make case-sim CASE=vision/render-hdmi-system`。实例化完整渲染器、帧控制器、双 Master 256-bit AXI Fabric、HDMI AXI 读端、异步 FIFO、scanout 与 TMDS。APB 提交两条前景绘制命令，连续送入两张 RGB565 底图；检查合成后的 DDR 像素、HDMI 活动帧每个像素、源底图释放、目标 token 退役和读写并行。此 case 使用缩小的 32×8 几何，不能代表 720p 帧率或板级时序。
