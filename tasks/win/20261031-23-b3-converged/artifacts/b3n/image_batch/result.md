# N 图片文件夹测试：首张推理完成，回传失败后批量停止

## 结论

用户观察：选择图片文件夹后只显示一张图片，不再继续，也没有检测框。
实际日志显示首张图已执行推理，板端报告 `detections=1`；PC 在组装回传数据时抛出 `YOLO return 0: incomplete return (983040 B expected)`，随后退出 UDP 接收。GUI 依赖完整回传触发下一张，因此停在首张。当前结果不能判定为模型没有检出，也不能判定检测框正确。

## 操作与原始输出

模型从 `tasks/win/20261029-09-b3-software/src/npu` 上传。图片文件夹为 `G:/codex_project/EdRV32-test-images/coco-val-160/images`，选择文件夹后首张为 `000000000285.jpg`。同目录 input_record.json 保存该图片的数据集索引；没有上传整个图片集。

```text
[00:51:33.531] UDP 发送完成：3247136 B · .../src/npu
[00:51:33.535] Model bytes: 3247136
[00:51:34.161] EDNM: loaded
[00:51:48.023] UDP 发送完成：1843200 B · .../000000000285.jpg
[00:51:51.506] frame_id=1 NPU_PERF0=6290069 post_cpu_cycles=2641589 detections=1
[00:51:51.514] UDP 接收失败：YOLO return 0: incomplete return (983040 B expected)
[00:53:03.235] UDP 已监听 192.168.1.2:6000 · console
[00:53:03.236] 连接请求已发送：192.168.1.10:5000；本机 ['192.168.1.2', 6000]
[00:53:03.240] ETH peer IP: 0xc0a80102
[00:53:03.240] ETH peer port: 6000
```

发送完成表示主机提交数据完成；模型另有板端 EDNM: loaded 确认。该帧有板端推理完成日志，但没有成功的完整回传记录。不能把 NPU_PERF0 或自检 fps 当作本次批量端到端 fps。

## 工具代码解释

以下为读取当前源码得到的故障传播路径，本轮未修改工具或 RTL：

1. `tools/debug_tool/core/yolo.py:88–107`：收到 window2 的 notify 后，依次检查 CH2（window0，983040 B）、OUTPUT（window1，725760 B）及检测结果的字节覆盖。此错误来自第一个覆盖检查；在生成 capture、递增 generation、清除 capture_pending 之前抛出异常。按代码路径，触发检查的检测结果结束通知已到达；并未取得足以核对检测框的完整 capture。
2. `tools/debug_tool/core/video.py` 的 Block.complete：要求覆盖区间严格为 [(0,size)]。错误表明覆盖未满足，不能只凭文件长度认定接收完整；现有证据没有缺失区间明细。
3. `tools/debug_tool/core/ethernet.py:183–217`：yolo.receive 的 ValueError 被接收线程捕获，记录 UDP 接收失败，finally 关闭共享接收 socket，因此也影响该 socket 的 EDTM 接收。yolo.receive 在落盘之前执行，触发异常的 window2 包不会写入 window2.bin。
4. `tools/debug_tool/gui/soc_console.py:698–719`：只有出现新的完整 capture/generation 才增加 folder_completed 并调用 _next_image；本次异常阻断了这一条件，所以队列不继续，也没有完整检测框可显示。

## 保存的数据与限制

- session.log、entries.json：本次可取得的完整控制台及带时间的日志项。
- status.json、board.json、ethernet.json：采集时工具状态；telemetry.json、edtm.csv：可取得的 EDTM。
- return_data/window0.bin：逻辑大小 983040 B；window1.bin：逻辑大小 725760 B。这是失败后保留在 build/debug_tool/udp-rx 的原始窗口文件副本；文件按 offset seek/write，空洞可能补零，逻辑大小不证明覆盖完整，也不据此推断缺失位置。
- 用户已在错误后重新启动监听。当前 rx 的 packets=110、bytes=112640、error=null、files={} 属于重启后的状态，不能用来还原失败时的收包统计或否认历史错误。此时 PEER 为 192.168.1.2:6000，与本机一致。
- EDTM 快照 records=6528、lost=7232、errors=0；lost 是遥测序号缺口计数，包含接收中断等影响，不能当作图片丢包数量。

尚不能区分真实丢包、乱序时结束通知先到、窗口分流/重置或其他原因。没有抓包及覆盖区间记录，不把任一候选写成已确认根因。已确认的是回传覆盖检查失败，以及工具因此关闭接收并停止批量推进。

本轮文件夹测试未完成；未获得批量吞吐率或与参考模型的检测框对比结果。交给 Claude 的排查重点是结束通知到达时各窗口的实际覆盖、UDP 接收/窗口分流，以及当前异常传播对 GUI 队列的影响。
