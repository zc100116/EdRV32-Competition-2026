# Render HDMI display

运行 `make case-sim CASE=vision/render-hdmi-display`。在独立 DDR、像素和串行时钟下实例化渲染专用的 HDMI 显示链路：三位 pageflip token、AXI 读端、异步 FIFO、RGB565 scanout 和 TMDS 编码器。测试先提交蓝色底图，再提交红色目标，检查完整活动帧内没有混色、旧 token 退役及 FIFO 不下溢。此 case 的像素来自预填 DDR；渲染器与 HDMI 共享 DDR Fabric 的联调另行进行。
