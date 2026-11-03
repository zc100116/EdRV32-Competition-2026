# 卡48 VRN CPU100MHz：归档与下一轮布线建议

工程G:/codex_project/EdRV32-FPGA/EdRV32-B3F-VRN-RND1S，PDS2022.2-SP6.1，PG2L200H-6 FBB676。已完成PnR、Report Timing和bitstream；PnR墙钟1h21m22s、CPU9m07s/进程CPU15m39s、峰值7789MB。

归档：fpga/bitstreams/EdRV32-VRN-cpu100m.sbit（9188552字节），直接复制当前生成结果。本轮仅归档和提供建议，没有修改原工程参数、没有启动参数重跑。

## 实际违例

| 慢角setup组 | WNS ns | TNS ns | 失败端点 |
|---|---:|---:|---:|
| clk_sys，CPU100MHz | +0.439 | 0 | 0 |
| clk_mem，125MHz | -0.124 | -0.190 | 2 |
| clk_npu，150MHz | -0.022 | -0.022 | 1 |
| clk_eth，125MHz | +2.427 | 0 | 0 |

RGMII输入clk_rgmii_ref→clk_eth慢角hold仍为WHS -0.361ns、THS -1.698ns、5端点，是本项目已有例外；不能与mem/NPU的setup违例混为一项。

- mem最差路径：u_mem/u_xbar/u_rbuf RAM读出→u_rnd/u_copy的两级选择逻辑→u_copy/u_row行缓存RAM。逻辑2级，Logic2.292ns(29.693%)、Route5.427ns(70.307%)；最差-0.124ns，另一条-0.066ns。从路径报告推断走线和放置有优化空间，不能据此保证改参数就通过。
- NPU最差：u_window/a4_tag_r[48]→MAC阵列channel25/lane0 APM X[17]，逻辑1级，-0.022ns。
- 危险路径：DDR prefetch rd_data_ff1[2]→xbar读缓存地址输入，setup仅0.000ns；NPU weight_store写使能路径+0.047ns、input_unpack→line_cache地址路径+0.070ns。
- 这些报告中的其他fast setup/hold、slow recovery/removal见artifacts/VRN-cpu100m/timing_summary.txt。原生报告只使用本次已有路径覆盖，未宣称已补导200条；路径索引及<=+0.200ns明细一并保存。

## 布线参数建议（尚未执行）

当前命令原文：
`pnr -plc_decongestion 2 -dump_router_congestion_plot true -slack_weight 40 -pin_cost_increasing_speed 600 -logic_optimize_lut6d_combing_strategy 0`

1. 已经能布通，下一轮优先只改Router页的Slack Weight：40→90（恢复默认），加强时序权重；Decongestion2、Pin Cost600、LUT6D0、逻辑优化勾选、线程5、拥塞图开启保持不变。该方向基于卡45为拥塞而降低时序权重的原始设计意图，以及本轮仅剩3个setup失败端点，是实验建议，不是确定修复。
2. GUI重新运行Place & Route即可，沿用本版Map数据库；不必重新导入或综合。随后重新Report Timing与Generate Bitstream。先比较mem/NPU WNS、TNS和失败端点，再看DDR→xbar零裕度路径，不能只看最差一条。
3. 若仍差少量，再单独试Multi-Run页Global Random Seed(Placement)=1、Iterations=1；保持第1步其他参数不变，另留结果。不同种子可能更好也可能更差，不启用多轮并行占内存。
4. RGMII外部输入hold不能靠增加Slack Weight认定修复，仍按已有例外单列。CPU提至125MHz也不会自动修复mem/NPU域的违例，它们是独立时钟域。

本轮归档的是修改前的基线，可继续上板测试，但存在以上时序违例，功能结果与时序结果需分别记录。
