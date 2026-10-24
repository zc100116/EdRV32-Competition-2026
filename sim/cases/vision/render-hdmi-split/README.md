# render-hdmi-split

运行 `make case-sim CASE=vision/render-hdmi-split`。

此 case 将渲染器和 HDMI 扫描读取接到两个独立 AXI Master 端口，在外层仲裁后访问同一 DDR 行为模型。检查绘制、两次合成、目标像素、完整 HDMI 活动帧、显示 token 退役、读写重叠及无下溢和 AXI 协议错误。使用 `SPLIT_AXI=1`，对应 render 板级顶层的连接方式。
