# 任务23：R/N/V实现与上板测试记录

- 分支 win/20261031-23-b3-converged；本轮RTL输入2a3ee2e0，软件与工具同步至9b54c704（摄像头720p30）。
- PDS 2022.2-SP6.1，PG2L200H-6 FBB676；工程 G:/codex_project/EdRV32-FPGA/EdRV32-B3V。
- 用户确认本次已下载卡23新V比特流并运行新版demo_vision；不把先前卡22异常归到本卡。
- V最终源码111；ROM/SRAM采用卡23DAT、Dcache tag为20位。R/N配置准备文件保留；本版已补充R/N最终流程与上板结果。

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

## N 综合、布局布线与最终时序

工程 `G:/codex_project/EdRV32-FPGA/EdRV32-B3N`，顶层 edrv32_fpga_board_npu_top；PDS 2022.2-SP6.1，PG2L200H-6 FBB676。综合、映射、布局布线、时序报告及比特流生成均结束，各阶段错误行数为0；最终时序有违例，不能记为时序通过。

| 阶段 | 实际耗时 | CPU时间 | Process CPU时间 | 峰值内存池 | W:行 | E:行 |
|---|---|---|---|---|---|---|
| compile | 1m48s | 14s | 14s | 590 MB | 3764 | 0 |
| synthesize | 6m14s | 1m9s | 1m14s | 2675 MB | 13711 | 0 |
| device_map | 1m8s | 8s | 9s | 1663 MB | 268 | 0 |
| place_route | 33m50s | 5m42s | 9m54s | 5059 MB | 694 | 0 |
| report_timing | 1m21s | 17s | 22s | 5010 MB | 130 | 0 |
| generate_bitstream | 1m35s | 23s | 23s | 3557 MB | 0 | 0 |

最终PnR资源：LUT 57937（CLMA 44036 + CLMS 13901）、FF 62278（47293 + 14985）、分布式RAM 1737、APM 294、DRM 173、IO 101、GPLL 5、PPLL 2。原厂CMR/SNR/DMR/PRR、资源层次与汇总保存于 artifacts/b3n/native_reports、resource_hier.txt、resource_summary.txt。当前本地未取得卡22的N结果产物，因此本轮不填造卡22资源与耗时差值。

原厂最终报告：clk_npu 请求150.0002 MHz，估算148.2653 MHz；slow setup WNS=-0.078 ns、TNS=-0.078 ns、1个失败端点。slow clk_sys setup=0.698 ns、clk_mem=0.349 ns、clk_eth=0.738 ns，也保留为低裕量重点。不能因为上板自检通过就忽略该违例；目前没有证据证明图片回传失败是时序违例造成的。

警告按原文保留：编译 ConstantProbeLoop 735行；综合 Public-4008 10490行；时序有85行Timing-4087和45行Timing-4086未约束输入/输出警告，结论受约束覆盖限制。PnR区域警告694行（4048:344、4032:192、4049:158），包括重复/站点优先、区域硬资源类型不匹配、IO区域约束被忽略；详细原文与高扇出/时钟/复位/CE表一并保存。警告数是日志行数，不等于独立缺陷数。

N自检39/39通过；图片端到端识别未通过（回传不完整，无叠框，批量停止）；网口ELF加载未确认成功（进度满但等不到板端完成），均按实际记录，不归并为整体PASS。未修改RTL、工具或重新跑实现流程；时序补导出只读取现有routed DB。完整PDS原始run.log、IP、工程数据库和比特流留在本机，不上传。

### N 时序补导出与复位证据

从现有routed DB执行 `report_timing -delay_type min_max -max_path 200 -input_pins TRUE -nworst 1`，原厂输出 Report timing is finished successfully，耗时3m4s。解析得到9552条各角/各类型路径，其中1条负裕量；setup/hold分别保存每组上限200条索引、每角最差20条逐级明细，以及<1ns低裕量路径（setup 505条、hold 3170条）。这不是全芯片所有路径穷举，数量与分组见 timing_path_counts.txt。

| 检查 | Slow最差/ns | Fast最差/ns |
|---|---|---|
| Setup | -0.078 | 2.408 |
| Hold | 0.129 | 0.099 |
| Recovery | 1.401 | 3.474 |
| Removal | 0.359 | 0.247 |
| Minimum pulse width | 0.035 | 0.035 |

最差setup起点为 `u_npu/u_conv/u_datapath/u_window/g_weight_channel[25].weight_r[43]/opit_0_L6QQ_perm/CLK`，终点为 `u_npu/u_conv/u_datapath/u_mac_array/g_channel[25].g_lane[5].g_cascade.u_mac/u_apm/gopapm/Y[3]`。详细路径与时钟偏斜原文见 timing_setup_top20_detail.txt、timing_violations.txt。DDR PHY最小脉宽只有0.035ns，也作为危险裕量保留。

SNR中识别出32个u_reset_*层次项（FF及资源见reset_copies.txt）；同文件保存最终PnR网表中仍存在的匹配标识符。DMR中的复位网络有重命名，未建立每个副本到最终fanout的完整映射，不能宣称已验证所有副本负载≤1000；高扇出、时钟、复位、CE原表与实际PCF均已保存。

完整扩展RTR约78MB留在 `build/win/20261031-23-b3-converged/exports/b3n_top200/`；上传原工程RTR、路径索引和逐级明细，避免提交重复的超大扩展文件。较大产物（DMR约2.1MB、综合警告节选约1.8MB、EDTM约1.7MB）用于保留映射/警告/遥测证据。

## R 综合、布局布线与上板问题

工程 `G:/codex_project/EdRV32-FPGA/EdRV32-B3R`，顶层edrv32_fpga_board_render_top，PDS 2022.2-SP6.1、PG2L200H-6 FBB676。各阶段结束且错误行数为0；比特流已生成。原厂CMR/SNR/DMR/PRR/RTR、警告节选、资源层次、高扇出/复位/CE、实际PCF和扩展时序路径保存于artifacts/b3r/。

| 阶段 | 实际耗时 | CPU时间 | Process CPU时间 | 峰值内存池 | W:行 | E:行 |
|---|---|---|---|---|---|---|
| compile | 1m51s | 16s | 16s | 562 MB | 3162 | 0 |
| synthesize | 6m5s | 1m8s | 1m13s | 2291 MB | 10365 | 0 |
| device_map | 1m3s | 9s | 10s | 1654 MB | 21 | 0 |
| place_route | 4h21m16s | 1h0m51s | 1h14m32s | 5827 MB | 693 | 0 |
| report_timing | 1m16s | 20s | 24s | 5466 MB | 138 | 0 |
| generate_bitstream | 1m21s | 24s | 24s | 3776 MB | 0 | 0 |

布局布线时间主要在Detailed routing 14695.27s（约4h4m55s），Total routing 14975.46s；Hold Violation Fix in router 175.06s。97462条route net均成功。原文见logs/pnr_execution_excerpt.txt。不仅凭耗时归因为拥塞或某个模块，当前日志不能证明上板软件异常由布线导致。

最终PnR资源：LUT 70542（53748+16794）、FF 55795（42128+13667）、分布式RAM 750、APM 131、DRM 117.5（原厂报告单位）、GPLL 5。详细资源及层次见resource_summary.txt和resource_hier.txt。卡22本地未取得同工程结果产物，不填造资源/耗时差值。

原厂报告All Constraints Met，但slow clk_mem setup仅0.003ns（目标125MHz，估算125.0469MHz），属于极低裕量；clk_sys为0.416ns、clk_eth为0.898ns。保留未约束输入/输出警告（Timing-4087 93行、Timing-4086 45行），结论受约束覆盖范围限制。PnR区域警告693行：4048为343、4032为192、4049为158。所有W:/E:原文和耗时均已保存，不将警告行数当作独立缺陷数。

### R 上板结果与用户反馈

- **RND CRC：29/29 PASS**。串口出现RND display ready，各组ERR_CODE均为0。对GUI分开的CRC标签/数值做明确拼接后执行 `C:/Python314/python.exe sw/tests/rnd_board/expect.py tasks/win/20261031-23-b3-converged/artifacts/b3r/uart/rnd_crc_joined.log`，退出码0。原始缓冲不变，比较输出和派生输入均保存。没有本轮照片，不代替图案目视验收。
- **S3 LVGL：失败**。用户反馈“测试程序点开就卡死”；日志两次相同异常：`S3 CPU mcause=0x00000007 mepc=0x900663bc`，前面有`lv_obj_get_display: No screen found`及NULL display警告。该PC落在本卡s3.elf的`lv_event_send.part.0+0x40`范围；这是符号定位，不是根因。未取得Benchmark Summary、LVGL split及RN-17完整结果，不记为通过；具体哪个LVGL子菜单未明确。
- **LAYERS：部分证据**。有画面1至5入口说明，画面5多次打印claimed=11 unclaimed=0；缺少五幅画面的照片及逐项目视结论。
- **NES：能运行但虚拟输入验收失败**。最初空ROM槽报错，随后通过临时含ROM ELF加载本地超级马里奥1超级版，Load result: PASS、NES powered on、mapper=0。用户反馈键盘方向键松开后人物仍持续移动。原始串口TX记录有right=8→keys=0的释放帧（例如seq732→744），不能直接归因为GUI从不发松键；未取得板端消费该释放帧的证据。
- **NES显示帧率偏低**：64条采样中shown为17.5–19.2fps，样本算术平均18.102fps；模拟fps为52.6–67.0，样本平均54.703。采样间隔不等，未将算术平均当作按时间加权吞吐率。完整数据在uart/nes_fps.tsv。
- **网口/EDTM：未完成**。当前UART快照connected=true、COM7/115200；未建立PEER，telemetry records=0，未取得S3/NES EDTM带宽或R网口加载成功证据。工具board.phase的disconnected和旧Input error不等同于串口物理断开。

详细软件报告见 [R串口及问题报告](artifacts/b3r/uart/result.md)，包括两次S3故障上下文、ELF符号范围、完整控制台、所有可取得的输入帧及工具状态。只收集报告和日志，未修改RTL、应用或调试工具。ROM、含ROM临时ELF、数据库、bitstream和完整PDS原始run.log不上传。当前R不能记为整体验收通过。

### R 危险时序与复位补充

只读现有routed DB补导出 `report_timing -delay_type min_max -max_path 200 -input_pins TRUE -nworst 1`，退出码0；共9620条各角/各类路径，已导出的负裕量路径0条。setup/hold各组上限200条，保留每角最差20条逐级明细，以及<1ns路径（setup 270条、hold 3205条）。不是全芯片全部路径穷举；分组计数见timing_path_counts.txt。

| 检查 | Slow最差/ns | Fast最差/ns |
|---|---|---|
| Setup | 0.003 | 2.084 |
| Hold | 0.100 | 0.086 |
| Recovery | 1.851 | 4.048 |
| Removal | 0.363 | 0.247 |
| Minimum pulse width | 0.035 | 0.035 |

除3ps setup外，DDR PHY最小脉宽35ps、最差hold86ps也已标为低裕量。各路径起终点、逻辑级数与逐级延迟见timing_setup_top200.txt、timing_setup_top20_detail.txt、timing_hold_top200.txt、timing_hold_top20.txt及timing_near_*。

SNR记录33个u_reset_*副本层次项；最终网表匹配标识符和综合资源逐项保存在reset_copies.txt。DMR有信号重命名，尚未建立全部副本到最终fanout的映射，不能声称全部副本负载≤1000。原厂高扇出/复位表与PCF完整保存。

完整扩展时序RTR约79MB留在build/win/20261031-23-b3-converged/exports/b3r_top200/；上传原工程RTR、路径索引及最差明细。较大DMR和综合警告节选保留用于Claude复核映射/约束/警告，不上传实现数据库。
