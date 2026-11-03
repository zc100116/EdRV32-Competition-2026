# 卡45：F仍在布线，VRN布通及上板结果

## 本次回传结论

PDS 2022.2-SP6.1，PG2L200H-6 FBB676。F/VRN均沿用卡43 RND原版v1 + Q6/OPT2 NPU综合数据库，本卡重新Map、不插ILA。以下为本次实际运行结果；后文准备阶段记录保留作说明。

| 项目 | F NOILA | VRN NOILA |
|---|---|---|
| 本地目录 | G:/codex_project/EdRV32-FPGA/EdRV32-B3F-RND1-N-NOILA | G:/codex_project/EdRV32-FPGA/EdRV32-B3F-VRN-RND1-N-NOILA |
| 状态 | PnR进程42092仍运行，未停止、未宣称失败 | PnR、时序报告、bitstream完成，已上板 |
| Map耗时/峰值 | 2m02s / 2379MB | 1m48s / 2165MB |
| Map LUT / FF / DRM / APM | 88472 / 99711 / 279 / 386 | 78352 / 86128 / 252 / 359 |
| PnR | 最后完成第12轮，78933未布通、430438过用、MT3004.771s | 1h10m08s；CPU10m36s；进程CPU16m19s；峰值7854MB |
| VRN最终布线 | — | 第114轮0未布通、0过用 |

本轮F与VRN曾同时PnR；VRN完成后F继续。F第7～12轮原文及当前尾部见artifacts/F/pnr_progress.txt、logs/pnr_tail.txt；第14/40/80轮均未取得。不能把“运行很久”写为已收到Route-0039失败。F未取得最终时序与bitstream；没有终止其进程。

VRN bitstream：上述目录/generate_bitstream/edrv32_fpga_board_vrn_top.sbit。Map资源不含ILA；VRN分布式RAM2062、IO137。u_rnd综合层次资源LUT18145、FF14712、APM82、DRM60（综合口径，不与Map直接相加）。原生报告gzip、层次资源、高扇出、首尾拥塞快照、阶段时间/告警分别在artifacts/F与artifacts/VRN。

### VRN时序：存在新增setup违例

| 慢角路径组 | WNS ns | TNS ns | 违例端点 |
|---|---:|---:|---:|
| clk_mem → clk_mem | -0.474 | -7.056 | 42 |
| clk_npu → clk_npu | -0.047 | -0.250 | 8 |
| clk_eth → clk_eth | -0.154 | -0.154 | 1 |

另有已知RGMII输入慢角hold：WHS -0.361ns、THS -1.698ns、5端点。不能将前三项setup违例归入RGMII已知例外。慢角clk_sys setup +0.380ns，clk_mem→phy_dq_sysclk_1 setup +0.175ns；clk_npu hold +0.065ns，正裕度也单独保留。所有时钟slow/fast、recovery/removal见timing_summary.txt；多条路径和危险正裕度见时序产物。

### VRN串口与软件问题（供Claude重建软件）

会话1663条，GUI buffer seq1～1663，已保存artifacts/VRN/uart/tool_session.log；是当前缓冲快照，非保证覆盖用户所有历史会话。程序从卡43实验分支提取至build/board/card45/vrn_runtime，未用卡46精简版替代原版v1。

- NPU：PASS 39/39；C-YOLO PERF0=6106770、MAC=5347440、40.711ms/frame、24.562fps、CRC32=0738f96e；D20全部PASS。串口没有给出NPU自检失败。
- RND原版v1：16/16 CRC逐行匹配rnd_v1_expected.log，ERR_CODE均为0，出现RND display ready。逐项对照见uart/rnd_crc_check.txt。
- s3_v1：benchmark平均22fps，各场景原文已保存。软件是旧S3，不是卡46 showcase；WIDGETS及虚拟输入有卡43已知限制。没有将用户未单独确认的LAYERS画面写为通过。
- demo_npu：PEER确认为192.168.1.2:6000，但连续识别出现实际应用错误，不能只归咎工具超时。串口原文：`frame_id=0 NPU_PERF0=1 post_cpu_cycles=18872481 detections=100`；`RGB565 image bytes: 3686400`；`DEMO ERROR: RGB565 image length`；`DEMO stopped: reset to restart`。同时工具每次发送1843200B；应用报告长度是两倍，根因尚未定位。
- 工具在板端停止后继续队列，快照中104条“回传未结束（超时1s）”，105条UDP发送完成，仅一条YOLO回传完整（FRAME0、100框）。该次回传与错误同时出现，不能记为正确识别或计算有效检测fps。没有取得本次demo模型上传成功的明确日志，不能将100框当作模型正确性证据。
- 需Claude检查/重建与VRN原版v1匹配的软件及PC工具：图片长度/格式协议、图像事务边界、模型就绪及板端停止后队列处理；保留已有硬件与网络配置，不在本轮自行修改RTL、PHY延迟或超时参数。
- 网口测试会话与Load PASS原文已保存，未据此补写未取得的5轮PERF1/PERF3增量表。无ILA，不做Debugger计数器验收；VRN不运行依赖PIX/GEO的demo_vision/demo_vnpu。

本次还将卡46 RND精简版的画面/字库/monitor/benchmark问题单独回传至win/20261103-46-b3r-rnd1slim，不能与本卡旧S3问题混为一个版本。

## 工程准备阶段记录

卡片输入effcfa47，结果分支win/20261103-45-f-noila-route；实现输入严格保留卡43提交13a17403的综合数据库，不使用当前b3的RNDv2重新编译。用户要求将本卡F配置同样用于一个VRN副本。

|项目|F|VRN（用户扩展）|
|---|---|---|
|新目录|EdRV32-B3F-RND1-N-NOILA|EdRV32-B3F-VRN-RND1-N-NOILA|
|源工程|EdRV32-B3F-RND1-N|EdRV32-B3F-VRN-RND1-N|
|综合数据库|保留原卡43syn.adf|保留原卡43syn.adf|
|ILA|FIC关联及副本FIC文件均移除|同左|
|下一阶段|Device Map重跑|Device Map重跑|

两副本路径位于G:/codex_project/EdRV32-FPGA，项目文件同目录名.pds；保留原器件和ADS设置、IP及初始化内容。没有复制旧Map/PnR/时序/bitstream输出。Map及之后状态置为待运行；不重新导入、不重新综合。所有项目输入路径存在，副本synthesize下无FIC。尚未运行Map验证未插核，不宣称已取得NOILA资源。

PnR两工程统一：Decongestion2；Placement Logic Optimization TRUE；LUT6D Packing Strategy0；Slack Weight40；Pin Cost600；线程5；拥塞图TRUE；Map高扇出1000。设置通过对应PDS _option保存，GUI实际显示待用户打开确认。

## 停止与资源安排

按本次用户要求结合卡45停止旧F（PID67748）及实际已启动的F-D4（PID64036）。未关闭PDS GUI，防止丢失未保存界面设置。停止前旧F最后第242轮5796/10897，F-D4第9轮128658/905752。VRN两个原版已无运行进程，用户此前已暂停；D2最后第55轮24029/65273，D3第60轮22868/58660。F-D1根run.log无轮次，已不在运行。原文见artifacts/stopped_runs.txt。

停止后最新FreePhysicalMemory20075064KB，约19.1GiB；未启动两个新工程。卡45原要求只F及VRN-D2可同时跑，用户本次要求改配新的F/VRN；目前旧VRN保持停止，后续只安排这两个NOILA变体。用户需先完成两个Map，再按空闲内存安排PnR。未启动综合、Map或PnR。

## 清理空间

拟删除未打开、已归档的F-D1、F-D3、VRN-D3、旧F-B四目录，约2.3GiB。已准备限制在FPGA父目录内、排除打开工程的原生PowerShell递归删除，但工具自动审批拒绝，返回blocked by policy，未提供更具体理由；命令没有执行，未删除任何目录，未释放磁盘空间。名单及大小在artifacts/cleanup_pending.txt，待用户手动清理。保留B1-ILA、卡24B3R、卡38B3R-r5、VN及源工程。

## 操作注意

当前checkout为b3任务卡分支，其RND为v2，故不要执行导入或Compile/Synthesize。用户在GUI打开新副本后，用dev_map -input_db_file显式选择各自卡43 syn.adf、-fanout_number1000 -force_to_run，确保从综合数据库重做Map。命令选项已由本机dev_map -help确认；没有使用-file模式对用户项目做所谓加载验证。Map完成后检查无Core Insertion Complete/无u_CORES，再开始PnR。

## 补导时序

VRN从已完成的pnr.adf只读导出 -delay_type min_max -max_path 200 -nworst 1 -input_pins TRUE，导出成功；未启动实现流程。保留各路径组最多200条的列表、最差20条setup/hold逐级明细、0～+0.200ns危险正裕度和违例清单。扩展原生RTR约100.6MB，gzip压缩回传，供复核多路径而保留；数量覆盖见VRN/timing_coverage.txt。
