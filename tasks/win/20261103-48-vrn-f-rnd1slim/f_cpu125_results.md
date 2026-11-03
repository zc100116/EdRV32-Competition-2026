# 卡48追加实验：完整F CPU125MHz实现与F100进度

## 结论和归档

F125已完成Compile、综合、Map、PnR、Report Timing与bitstream，第117轮0未布通/0过用。仍有CPU、NPU、mem的setup违例及已知RGMII输入hold违例，不作为全时序通过版本。未取得本版本上板结果。

归档fpga/bitstreams/EdRV32-F-cpu125m.sbit（9188552字节）。来源G:/codex_project/EdRV32-FPGA/EdRV32-B3F-RND1S-CPU125/generate_bitstream/edrv32_fpga_board_full_top.sbit。其他VRN归档保留，不覆盖。

工具PDS2022.2-SP6.1、PG2L200H-6 FBB676、ADS，无ILA；RTL为卡48基线11046fb0627afc3d182a072c8b150edab44191f3，完整F含VIN/PIX/GEO/RND/NPU/DISP/ETH。CPU125为用户追加局部配置：生成PLL125MHz、私有SYS常量125000000、私有约束clk_sys 8ns，最终RTR也确认为8.0000ns；NPU150MHz和DDR core125MHz不变。配置过程见cpu125_experiment.md。

## 各阶段

| 阶段 | 墙钟 | CPU | 进程CPU | 峰值MB |
|---|---|---|---|---:|
| Compile |2m56s|19s|19s|820|
| Synthesize |9m26s|28s|32s|3833|
| Device Map |1m45s|4s|5s|2340|
| Place & Route |1h20m35s|11m20s|19m29s|7779|
| Report Timing |2m34s|20s|25s|7376|
| Generate Bitstream |2m36s|17s|17s|4340|

PDS汇总从Compile至bitstream墙钟1h39m52s，CPU12m48s、进程CPU21m07s。实现参数Decongestion2、Slack40、Pin Cost600、LUT6D0、逻辑优化开启、线程5、拥塞图开启。原始阶段时间和诊断见artifacts/F-cpu125m/flow_summary.txt及logs/。

## 资源

Map：LUT87151、FF96124、DRM277、APM372、分布式RAM2206、IO137；专用资源完整表在resource_summary.txt。

综合层次值（父层包含子模块，不相加、不与Map直接相减）：

| 模块 | LUT | FF | 分布式RAM | APM | DRM |
|---|---:|---:|---:|---:|---:|
| u_cpu |15585|9564|143|4|18|
| u_mem |9298|9096|849|0|4|
| u_npu |16469|30874|1048|266|122|
| u_rnd |16802|11296|0|68|58|
| u_vin |5615|7097|37|0|17|
| u_pix |5975|9763|0|18|11|
| u_geo |3296|3376|0|9|16|
| u_disp |2990|4023|0|7|8|
| u_eth |4448|4665|76|0|3|

## 时序

| 慢角setup组 | WNS ns | TNS ns | 失败端点 |
|---|---:|---:|---:|
| clk_sys | -0.033 | -0.096 |5|
| clk_npu | -0.120 | -0.168 |4|
| clk_mem | -0.010 | -0.010 |1|
| clk_eth | +2.020 |0|0|

RGMII输入慢角hold WHS -0.242ns、THS -1.103ns、5端点，按项目已知例外单列。其他域的setup/hold及recovery/removal，包含fast角，见timing_summary.txt。

- CPU最差：e_operand_a_r[0][20]→frontend/predictor/ras_data_r[33]/CE，11级，-0.033ns。
- NPU最差：MAC channel6/lane7 APM→accum channel6/pixel1/r4_data_r[16]/CIN，3级，-0.120ns。
- mem最差：DDR复位时钟相位调整rst_clk_adj_en→rst_clk_gpll/DPS_EN，0级，-0.010ns。未添加例外隐藏此路径。
- 正裕度临界项同样保留，例如clk_mem→phy_dq_sysclk_1 setup +0.156ns、RGMII输入setup +0.130ns；不只保存负裕度。

从已完成pnr.adf只读补导min_max/max_path200/nworst1/input_pins，多路径列表、最差20条setup/hold逐级明细、违例和0～+0.200ns路径分别保存。扩展原生RTR用gzip回传以复核覆盖，数量见timing_coverage.txt。未为收集报告重跑实现流程。

## F CPU100MHz进行中快照

本地G:/codex_project/EdRV32-FPGA/EdRV32-B3F-RND1S，收集时最后完成第25轮：22877未布通、65077过用，该轮MT317.019s。第18～25轮从39596下降至22877。保存已完成阶段报告、Map层次/高扇出、现有PnR报告、逐轮原文、日志尾部和首尾拥塞快照到artifacts/F-cpu100m-progress/。

本次没有停止F100，没有收到其最终失败结果；其最终PnR耗时、时序和bitstream未取得。尚未到卡48第40轮止损节点，不将“比F125慢”写为失败。F125先布通也不能证明提频一定加速：不同布局与资源竞争均会影响启发式布线收敛，未分离各因素贡献。

## 产物和限制

F125的CMR/SNR/DMR/PRR/RTR/BGR原文gzip、阶段告警及出现次数、综合层次、高扇出、逐轮布线、首尾拥塞、时序路径见artifacts/F-cpu125m/。完整工程、IP、数据库、完整构建日志留在本地，不入库；比特流按用户明确要求统一归档上传。复制来源的旧结果不代替本次完成的F125结果。
