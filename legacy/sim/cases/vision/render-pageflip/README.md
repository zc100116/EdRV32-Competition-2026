# Render HDMI pageflip token

运行 `make case-sim CASE=vision/render-pageflip`。使用真实 AXI HDMI pageflip 读端验证 3 位渲染 token、两条待切换帧队列、队列满时的 valid/ready 背压、按帧读取的数据和旧 token 退役。此 case 只测试 DDR 读端与显示帧边界，不产生 TMDS 信号。
