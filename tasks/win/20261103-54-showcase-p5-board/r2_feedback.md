# 卡54第二轮：实时识别与文件夹切换异常

## 用户实测反馈

- HDMI目前已恢复显示；不能将此前无画面认定为本次仍存在的状态，恢复原因未确认。
- 实时识别帧率仍低，不到10fps，端到端延迟大。
- 图片识别成功发送几张后，更换文件夹，用户观察到卡住；虚拟按键失效，但板载按键仍有效。退出图片识别后虚拟输入没有恢复。该表现不能直接判定为整机CPU死机。
- 图片被强行拉伸到全屏，用户不认可变形。后续应讨论保持宽高比的适配显示和补边，以及检测框映射、图像预处理的一致性；本次未修改实现。

## 照片证据

`artifacts/photos/r2_vision_9fps_e2e112ms.jpg`：识别9fps，NPU41.3ms，后处理23.2ms，端到端112.9ms；顶部CPU43%、GUI11FPS。页面阈值≥0.50、80类，行人1。GUI FPS与识别FPS不是同一指标。

## 日志证据

- 当前P5b工具版本字段64aec2b6。
- `artifacts/uart/r2_A_C_folder_switch.log` 保存当前缓冲1197条（seq1–1197），含1038条RX。串口原文含实时 `vision fps=...` 和图片 `image request=...`。
- 多条实时行显示fps=9、npu约41ms、decode约23ms、gui约37–43ms、e2e约113–122ms。只作为已观察行示例，不声称是全程均值或完整范围。后处理较上轮177ms已下降，但总体帧率仍未达到用户预期；需要继续分析GUI和应用调度/流水间隙，不能仅看后处理达标就判通过。
- 已有图片完成行request=2/4/6/8；其upload_to_done依次为100/88/88/89（按原文保留）。receive分别119.6/142.9/90.9/122.0ms。部分receive比upload_to_done大，必须核对计时起点和单位，不能未经确认当作完整上传到完成的总耗时。
- 采集工具状态phase=disconnected、PEER未完成，缓存应用state仍为app2/state2，request10/frame3/image_status1。缓存字段不能证明板端当前状态。
- 图片传输状态失败，sent=0/1843200，错误原文“同类命令正在等待设备完成”，路径为coco-val-160/images/000000003156.jpg。这与请求/取消/换目录时存在未结束命令的方向相符，但具体根因尚未定位。
- 工具本轮UDP接收实例计数0；不把重建接收器后的0推定为整个测试从未收包。

已保存工具status、ethernet、program及原始buffer到artifacts/tool/r2_image_folder_*；关键行摘录见artifacts/uart/r2_vision_image_excerpt.txt。未清空日志、未复位设备、未修改程序。本次按用户要求先本地记录，未在记录过程中自动操作输入或重启应用。
