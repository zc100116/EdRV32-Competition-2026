# F CPU125MHz重跑r2：仅剩已知RGMII输入hold

## 归档与结论

比特流：fpga/bitstreams/EdRV32-F-cpu125m-r2.sbit，9188552字节。来源G:/codex_project/EdRV32-FPGA/EdRV32-B3F-RND1S-CPU125/generate_bitstream/edrv32_fpga_board_full_top.sbit。本次归档不覆盖第117轮旧版EdRV32-F-cpu125m.sbit。

PDS2022.2-SP6.1、PG2L200H-6 FBB676，完整F，精简RND v1，CPU125MHz、NPU150MHz、DDR core125MHz，无ILA。沿用卡48相同综合/Map结果，用户修改PnR参数后重跑。

**第210轮0未布通、0过用；slow/fast setup、recovery/removal满足，其他内部hold满足。唯一负裕度汇总项为已知RGMII输入慢角hold，WHS -0.242ns、THS -1.103ns、5端点。** 不能把有已知例外写成所有约束都为零违例。

## 参数与耗时

本轮PRR的Flow Command：

```tcl
pnr -plc_decongestion 2 -dump_router_congestion_plot true -pin_cost_increasing_speed 600 -logic_optimize_lut6d_combing_strategy 0
```

前轮显式-slack_weight40；本轮省略，恢复工具默认90。其他主要设置不变，线程5、逻辑优化开启。未修改RTL、PLL、FDC或时序例外来消除本轮违例。

| 本轮阶段 | 墙钟 | CPU | 进程CPU | 峰值MB |
|---|---|---|---|---:|
| Place & Route |1h39m44s|15m46s|26m39s|8317|
| Report Timing |2m11s|17s|23s|7388|
| Generate Bitstream |2m18s|9s|9s|4344|

Compile2m56s/820MB、综合9m26s/3833MB、Map1m45s/2340MB为沿用阶段报告，保留作资源和来源参考，不当作本轮重新执行的证据。根日志显示从Compile至bitstream累计1h58m20s，包含已有阶段时间，不作为纯PnR重跑耗时。

Map资源仍为LUT87151、FF96124、DRM277、APM372、分布式RAM2206、IO137；综合层次和高扇出原文保存在对应产物目录。I/D-cache实际均32KiB，旧BIOS的8192容量打印是软件常量；相关核实见卡52更正说明。

## 前后时序比较

| 慢角setup组 | 第117轮旧版WNS ns | r2 WNS ns | r2 TNS / 失败端点 |
|---|---:|---:|---|
| clk_sys | -0.033 | +0.087 |0 / 0|
| clk_npu | -0.120 | +0.048 |0 / 0|
| clk_mem | -0.010 | +0.179 |0 / 0|
| clk_eth | +2.020 | +1.864 |0 / 0|

RGMII输入hold仍为-0.242ns/5端点，与旧版相同。完整每时钟slow/fast WNS/TNS/WHS/THS和recovery/removal、脉宽汇总见timing_summary.txt。

CPU和NPU虽然已满足，裕度仍较小，因此保存危险正裕度，不仅保存违例：
- CPU f1_pc_r[8]→f1_pc_r[29]/CIN，14级逻辑，setup +0.087ns。
- NPU MAC channel6/lane7→accum r4_data_r[16]/CIN，2级，setup +0.048ns；NPU慢角hold +0.066ns。
- mem xbar读缓存→RND BLIT target RAM，1级，setup +0.179ns；RGMII输入setup +0.130ns。

PnR轮数117→210、墙钟1h20m35s→1h39m44s，时序得到改善但布线更久。只有本轮实际结果，不把一次参数变更推广成所有设计都能通过的规律。

## 产物与上板范围

artifacts/F-cpu125m-r2/包含CMR/SNR/DMR/PRR/RTR/BGR原文gzip、阶段耗时和告警计数、综合层次、高扇出、逐轮布线、首尾拥塞、参数原文。完整数据库、IP、工程及构建日志仍在本地。

从已完成pnr.adf只读补导min_max/max_path200/nworst1/input_pins的多路径时序，列表、最差20条setup/hold细节、负裕度和0～+0.200ns路径一并保存，覆盖见timing_coverage.txt；较大原生扩展RTR用gzip回传供复核。本轮收集没有触发Compile、综合、Map或PnR重跑。

本轮尚未取得r2上板结果。卡51已上板的是第117轮旧版；卡52原卡输入也是旧版，后续如果用户切换到r2，应在上板报告明确区分，不能将旧版数据直接记作r2通过。本次没有自行下载r2到板上。
