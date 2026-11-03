# 卡54第三轮 P5c：实时识别性能阶段反馈

本次按用户要求仅整理并上传已有日志和照片，交给Claude分析；没有修改源码、增加打印或重编程序。

## 用户反馈

实时识别性能略有提升，但端到端延迟仍然太长。其余R1–R7项目本次未收集到完整测试结论，不标记通过。

## 照片实测

`artifacts/photos/r3_e2e226ms.jpg`：识别12fps，NPU41.7ms，后处理23.7ms，端到端226.6ms；顶部CPU77%、GUI13FPS。性能浮窗显示渲染13fps、显示60fps、NPU55%、RND23%；通信1%最长2097us、应用35%最长1512us、界面38%最长117233us。阈值≥0.50、80类。以上均为照片显示口径，不将刷新率、渲染帧率与识别帧率混用。

## 串口证据

本次保存130条vision性能行。以下为原文示例，不作为全程平均：

```
vision fps=12 npu=41.7 wait=39.2 decode=23.6 sort=0.0 nms=0.0 post_span=79.6 gui=60.2 e2e=236.3 period=80.8 copy=1.0 cpu_comm=1% cpu_app=33% cpu_gui=40%
vision fps=10 npu=41.7 wait=45.1 decode=23.6 sort=0.0 nms=0.0 post_span=90.5 gui=57.8 e2e=257.5 period=91.8 copy=1.0 cpu_comm=1% cpu_app=28% cpu_gui=43%
```

请求Claude结合原始行检查wait、post_span、gui、period及e2e口径和等待来源，不在本报告中预设根因。

## 产物

- `artifacts/uart/r3_latency.log`：采集时完整当前会话RX/TX/SYS，时间为Unix毫秒。
- `artifacts/uart/r3_vision_excerpt.txt`：130条vision原文。
- `artifacts/tool/r3_latency_buffer.json`：原始会话结构。
- `artifacts/tool/r3_latency_status.json`：采集时工具/板端缓存状态。
- `artifacts/photos/r3_e2e226ms.jpg`：用户实拍。

第1、2轮日志保留不动。当前为第3轮阶段结果，不宣称完整验收完成。
