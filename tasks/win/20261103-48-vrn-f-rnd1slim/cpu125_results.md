# 卡48追加实验：VRN CPU125MHz实现结果

| 项 | 内容 |
|---|---|
| 代码基线 | 11046fb0627afc3d182a072c8b150edab44191f3，CPU125局部配置见cpu125_experiment.md |
| 工程 | G:/codex_project/EdRV32-FPGA/EdRV32-B3F-VRN-RND1S-CPU125 |
| 工具/器件 | PDS2022.2-SP6.1，PG2L200H-6 FBB676，ADS，无ILA |
| 时钟 | CPU125MHz，NPU150MHz，DDR core125MHz |
| 归档 | fpga/bitstreams/EdRV32-VRN-cpu125m.sbit，9188552字节 |
| 结论 | 第174轮0未布通/0过用，时序报告和bitstream完成；CPU、mem setup及已知RGMII慢角hold仍有违例，不是时序全通过版本 |
| 上板 | 本版未取得，不以此前100MHz或原版v1的功能测试代替 |

## 流程

| 阶段 | 墙钟 | CPU | 进程CPU | 峰值MB |
|---|---|---|---|---:|
| Compile | 2m50s |15s|15s|793|
| Synthesize |8m19s|24s|28s|3429|
| Device Map |1m37s|5s|6s|2126|
| Place & Route |1h10m24s|8m41s|14m30s|7348|
| Report Timing |2m09s|15s|18s|6631|
| Generate Bitstream |2m39s|34s|34s|4126|

PDS从Compile到bitstream汇总墙钟1h27m58s，CPU10m14s、进程CPU16m11s。PnR逐轮及首尾拥塞快照均保存。实际同机并行流程由用户从PDS启动，并非此前等待队列；该等待队列已停止，未终止PDS任务。不能把不同运行条件下的布线耗时差当作频率提升的确定因果。

PnR设置：Decongestion2、LUT6D0、Slack Weight40、Pin Cost600、逻辑优化开启、线程5、拥塞图开启。125MHz不是仅改名称：生成PLL及综合网表为I1/M2/F15.625/O0=6.75；最终RTR的clk_sys Period=8.0000ns。Map加载私有125MHz FDC，Compile使用私有125000000Hz常量，相关记录及IP生成日志在artifacts/VRN-cpu125m/。

## 资源

Map整机LUT77175、FF82542、DRM250、APM345、分布式RAM2062、IO137；其余专用资源见resource_summary.txt。

以下为综合层次资源，父层包含子模块，不能累加，也不能直接与Map相减推算优化量：

| 模块 | LUT | FF | 分布式RAM | APM | DRM |
|---|---:|---:|---:|---:|---:|
| u_cpu |15558|9564|143|4|18|
| u_mem |8763|8619|705|0|4|
| u_npu |16454|30874|1048|266|122|
| u_rnd |16813|11312|0|68|58|
| u_vin |5562|7096|37|0|17|
| u_disp |2990|4023|0|7|8|
| u_eth |4442|4665|76|0|3|

## 时序与100MHz归档对照

100MHz列引用已归档的第一次结果，未引用目前重跑工程的覆盖日志。

| 慢角setup组 | 125MHz WNS ns | TNS ns | 失败端点 | 100MHz基线WNS ns |
|---|---:|---:|---:|---:|
| clk_sys | -0.436 | -1.135 |16|+0.439|
| clk_mem | -0.167 | -0.303 |5|-0.124|
| clk_npu | +0.051 |0|0|-0.022|
| clk_eth | +0.433 |0|0|+2.427|

两版RGMII输入慢角hold都是WHS -0.361ns、THS -1.698ns、5端点。其他fast setup/hold及slow/fast recovery/removal的完整表在timing_summary.txt。

已有原生最差路径：
- CPU：frontend f1_pc_r[8]→f1_pc_r[29]/CIN，15级逻辑，-0.436ns；不是CPU频率未生效，而是125MHz实际违例。
- mem：DDR复位时钟相位调整rst_clk_adj_en→rst_clk_gpll/DPS_EN，-0.167ns；另有xbar读缓存→RND COPY行缓存，-0.058ns。未添加例外去隐藏这些路径。
- NPU：MAC APM→accum r4_data_r[16]，+0.051ns；weight_store写使能路径+0.053ns，虽然无违例，裕度很小。
- clk_mem→phy_dq_sysclk_1 setup +0.169ns，也作为临界正裕度记录。

本轮PnR比100MHz基线1h21m22s短，但仍未时序收敛。CPU125与NPU150、mem125属于独立域，某个域变好不能替代其他域验收。

## 日志、报告与限制

artifacts/VRN-cpu125m保存各阶段耗时、Warning/Error原文和出现次数、高扇出、综合层次、逐轮布线与首尾拥塞图；CMR/SNR/DMR/PRR/RTR/BGR用gzip保存。实现阶段未发现E类错误，存在PAP_KEEP属性无效、constant probe Loop、未约束IO等W类输出，保留原文，不将重复警告数量当作缺陷数量或直接认定实际组合环路。

从已完成pnr.adf只读补导min_max/max_path200/nworst1/input_pins的扩展时序，提供路径列表、最差20条setup/hold明细、负裕度和0～+0.200ns危险正裕度，覆盖数量见timing_coverage.txt。扩展原生RTR较大，用gzip保留以便Claude复核多路径；未重新运行Compile、综合、Map或PnR。

完整工程、IP、数据库、完整构建日志留在本地上述工程目录；按用户明确要求，仅比特流额外归档上传，不上传PDS工程或数据库。F125的进行中结果不混入本版报告。
