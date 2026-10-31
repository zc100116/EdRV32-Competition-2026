# 任务23：V实现与上板、N自检与图片回传异常

- 分支 win/20261031-23-b3-converged；本轮RTL输入2a3ee2e0，软件与工具同步至9b54c704（摄像头720p30）。
- PDS 2022.2-SP6.1，PG2L200H-6 FBB676；工程 G:/codex_project/EdRV32-FPGA/EdRV32-B3V。
- 用户确认本次已下载卡23新V比特流并运行新版demo_vision；不把先前卡22异常归到本卡。
- V最终源码111；ROM/SRAM采用卡23DAT、Dcache tag为20位。R/N配置准备文件保留；本版尚未收集R/N最终流程报告，N上板结果补充如下。

## V流程

布局布线成功、bitstream生成成功。各阶段错误行均为0，详细警告代码计数与原文保存在flow_summary.txt和logs/。

| 阶段 | 实际耗时 | CPU时间 | Process CPU时间 | 峰值内存池 | W:行 | E:行 |
|---|---|---|---|---|---|---|
| compile | 0h:1m:42s | 0h:0m:13s | 0h:0m:13s | 495 MB | 3136 | 0 |
| synthesize | 0h:5m:5s | 0h:0m:40s | 0h:0m:44s | 2,189 MB | 9256 | 0 |
| device_map | 0h:0m:55s | 0h:0m:9s | 0h:0m:9s | 1,376 MB | 56 | 0 |
| place_route | 0h:21m:16s | 0h:3m:17s | 0h:5m:41s | 3,715 MB | 694 | 0 |
| report_timing | 0h:1m:21s | 0h:0m:17s | 0h:0m:20s | 4,095 MB | 166 | 0 |
| generate_bitstream | 0h:1m:27s | 0h:0m:21s | 0h:0m:21s | 3,395 MB | 0 | 0 |

卡22V布局布线37m58s、峰值内存池5555MB，本卡21m16s、3715MB；时间和内存均按原厂日志字段记录，不混用CPU与实际耗时。

## 资源对比

同为Device Map口径。DRM为36K等效，primitive拆分和最终PnR资源另见resource_summary.txt；完整最终层次见resource_hier.txt。

| 资源 | 卡22 V | 卡23 V | 差值（23−22） |
|---|---|---|---|
| LUT | 62877 | 51865 | -11012 |
| FF | 56372 | 51875 | -4497 |
| Distributed RAM | 922 | 885 | -37 |
| APM | 47 | 38 | -9 |
| DRM | 97 | 97 | 0 |
| IO | 137 | 137 | 0 |
| GPLL | 5 | 5 | 0 |
| PPLL | 2 | 2 | 0 |

最终PnR逻辑层次总计：LUT 51468、FF 51875、分布式RAM 885、APM 38、DRM 97。卡22同口径为62631、56428、922、47、97。原始CMR/SNR/DMR/PRR已保存，完整run.log保留工程本地。

## 最终时序及危险裕量

两个角的原厂汇总未列出setup/hold/recovery/removal/最小脉宽负裕量。最差setup为slow clk_mem 0.433ns；hold为fast clk_mem→phy_dq_sysclk_1 0.098ns；recovery为slow clk_mem 3.672ns，removal为fast clk_eth 0.250ns。DDR PHY最小脉宽裕量仍只有0.035ns。
工具有未约束输入/输出警告，因此结论受当前约束覆盖范围限制。

| Corner | Launch→Capture | WNS | TNS | WHS | THS |
|---|---|---|---|---|---|
| Slow | clk_cam0 → clk_cam0 | 5.924 | 0.000 | 0.153 | 0.000 |
| Slow | clk_cam1 → clk_cam1 | 5.677 | 0.000 | 0.149 | 0.000 |
| Slow | clk_sys → clk_sys | 0.796 | 0.000 | 0.132 | 0.000 |
| Slow | clk_pix → clk_pix | 7.366 | 0.000 | 0.195 | 0.000 |
| Slow | clk_serial → clk_serial | 1.706 | 0.000 | 0.346 | 0.000 |
| Slow | rst_clk → rst_clk | 4.576 | 0.000 | 0.226 | 0.000 |
| Slow | clk_mem → clk_mem | 0.433 | 0.000 | 0.137 | 0.000 |
| Slow | phy_dq_sysclk_1 → clk_mem | 2.996 | 0.000 | 0.549 | 0.000 |
| Slow | phy_dq_sysclk_0 → clk_mem | 3.942 | 0.000 | 0.812 | 0.000 |
| Slow | clk_mem → phy_dq_sysclk_0 | 2.242 | 0.000 | 0.440 | 0.000 |
| Slow | clk_mem → phy_dq_sysclk_1 | 1.465 | 0.000 | 0.453 | 0.000 |
| Slow | clk_eth → clk_eth | 2.485 | 0.000 | 0.266 | 0.000 |
| Fast | clk_cam0 → clk_cam0 | 7.694 | 0.000 | 0.105 | 0.000 |
| Fast | clk_cam1 → clk_cam1 | 7.584 | 0.000 | 0.103 | 0.000 |
| Fast | clk_sys → clk_sys | 4.001 | 0.000 | 0.102 | 0.000 |
| Fast | clk_pix → clk_pix | 9.957 | 0.000 | 0.131 | 0.000 |
| Fast | clk_serial → clk_serial | 2.084 | 0.000 | 0.225 | 0.000 |
| Fast | rst_clk → rst_clk | 6.078 | 0.000 | 0.155 | 0.000 |
| Fast | clk_mem → clk_mem | 3.269 | 0.000 | 0.100 | 0.000 |
| Fast | phy_dq_sysclk_1 → clk_mem | 4.762 | 0.000 | 0.099 | 0.000 |
| Fast | phy_dq_sysclk_0 → clk_mem | 5.273 | 0.000 | 0.195 | 0.000 |
| Fast | clk_mem → phy_dq_sysclk_0 | 4.207 | 0.000 | 0.100 | 0.000 |
| Fast | clk_mem → phy_dq_sysclk_1 | 3.752 | 0.000 | 0.098 | 0.000 |
| Fast | clk_eth → clk_eth | 4.654 | 0.000 | 0.161 | 0.000 |

完整汇总及各检查原文在timing_summary.txt、timing_minima.txt；从已完成的routed DB补导出每组上限200条setup/hold，保存最差20条逐级明细以及<1ns的危险路径（包含所有已导出的负裕量路径，如有）。实际数量见timing_path_counts.txt，不声称默认报告只有几条时覆盖全部路径。

## 复位副本与区域约束

SNR层次表中V有37个子系统u_reset_*副本，各占1个FF；最终PnR网表中仍有37个不同的副本寄存器实例，另有reset_ctrl内部u_mem_copy，实例摘录在reset_copies.txt。
DMR复位表很多信号已重命名为Nxxx，不能仅凭少数保留的u_reset_*名字建立全部负载映射。高扇出、clock/reset/CE表完整保留在high_fanout.txt；本版未取得所有副本对应的逐项fanout，不能宣称已证明每个都≤1000。

PnR区域警告共694条（4048:344、4032:192、4049:158）：重复约束/固定站点优先、区域不含目标硬资源类型、IO区域约束不建议且被忽略。保留实际PCF和警告原文，不将层次region定义等同于所有内部单元都受区域限制。

## 当前上板与摄像头

用户确认卡23新比特流和新版程序已运行。工具快照显示本机192.168.1.2:6000、板端PEER一致，四步连接状态完成、error=null，已接收视频数据与EDTM。快照导出 10864 条EDTM，records=10848、lost=0、errors=0。counts.video为数据接收计数，未把它误写为完整视频帧数或fps。

两次status相隔CLINT时间 11.006368 秒（mtime / 100MHz），camera0/1各增加 330 帧，均为 29.98264 FPS。两次CH0 overflow均为0。原文和计算输入在camera/status_samples.log、camera/fps.json。
本次采样时输出为HDMI；ETH/both两模式下工具显示的完整视频fps、逐项图像处理画面/照片仍未取得。不能把网口收发与相机帧计数正常等同于全部上板清单已通过。

工具完整缓冲、状态、串口和DDR CSV在tool_snapshot/。其中可能包含此前历史会话，摄像头两次专门采样均在用户确认卡23上板后进行。

## 卡22网口异常更正

先前复测失败时用户最初回答卡23，随后明确更正为卡22。以更正为准：当时PEER为0、ARP失败、GUI与独立probe均无接收。其后原比特流已不在FPGA上，用户表示无法复现并暂停；根因未定。
本次将该组日志单独放在artifacts/card22_network_retry/，observations.md已更正，不能作为卡23网口故障证据。更早卡22四组延迟诊断成功、原应用也曾成功收发的事实同样保留在卡22结果分支，不用一次结果覆盖另一次现象。

## 产物范围

artifacts/b3v 包含完整原厂阶段报告、警告/错误/耗时节选、资源层次、时序列表与危险路径、复位副本、实际PCF、串口/状态/EDTM和摄像头采样。
不提交生成IP、实现数据库、bitstream或完整PDS原始run.log。所有完整文件继续留在上述V工程的各阶段目录。

补导出已成功退出（exit 0），总计 12052 条各角/各类型路径，已导出的负裕量路径为0。

较大产物保留原因：原厂DMR包含完整约束与映射信息，EDTM CSV保留本次全部已导出数据，便于复核时序/区域及DDR带宽，不上传实现数据库。
- artifacts\b3v\tool_snapshot\edtm.csv：2911505 字节
- artifacts\b3v\native_reports\device_map\edrv32_fpga_board_vision_top.dmr：2141600 字节

## N 自检与图片批量测试补充

串口自检结果：`NPU board: PASS 39/39`；`NPU C-YOLO PASS PERF0=6249568 MAC=5347440 ms/frame=41.663 fps=24.001 CRC32=0738f96e`。这是自检测量，不等于图片批量测试端到端吞吐率。原始串口与摘要在 artifacts/b3n/uart/selftest_*。

此前网口加载 ELF 时，115200 波特率下 BIOS 已打印 ETH link: up / ETH load ready，主机 sent=total=5212944，但停在 wait_result，没有收到 Load result: PASS 或 Run。满进度条不能当作板端加载成功。另一次切换至 2000000 后出现乱码/零字节。随后取消网口加载并回到 BIOS，用户以串口完成自检；相关状态和日志在 artifacts/b3n/uart/eth_load_*，未确认网口加载失败根因。

图片测试中模型 3247136 B 上传并获 `EDNM: loaded`。文件夹首张 000000000285.jpg 发送后，板端报告 `frame_id=1 NPU_PERF0=6290069 post_cpu_cycles=2641589 detections=1`；PC 随后报 `YOLO return 0: incomplete return (983040 B expected)`，退出共享 UDP 接收线程。GUI 需要完整 capture 才显示检测框、推进下一张，因此用户看到首张停住且无框。不是“板端检出0个目标”；检测框内容和正确性尚未核对。

详细故障链、重启监听后的统计限制、完整工具日志、EDTM及两个原始窗口文件在 [图片测试报告](artifacts/b3n/image_batch/result.md)。窗口文件合计1708800 B，保留用于定位回传问题；逻辑长度不证明覆盖完整。本轮只整理输出和代码行为，未修改 RTL、工具或发起新的测试。
