# 卡56结果（默认参数及R1补跑）

PDS2022.2-SP6.1 build138931，PG2L200H-6/FBB676，ADS。
R1为CPU v0.15，提交b35f8349（方向表两个1024×4 bank）；R2为正式版e54e471e。
共同约束周期6.667ns，FDC设置setup uncertainty 0.15ns；本机补充clk_i的LVCMOS33电气标准。

## 默认参数与补跑结果

| 轮次 | 布局布线参数 | 慢角WNS/TNS(ns) | 违例端点数 | WHS慢角/快角(ns) | 估算Fmax(MHz) | LUT/FF/DRM/APM/分布式RAM |
|---|---|---|---|---|---|---|
| R1 v0.15 | 默认，原始命令pnr | -1.342/-2188.698 | 5111 | +0.147/+0.099 | 124.8595 | 16090/9778/18/4/308 |
| R2正式版 | 默认，原始命令pnr | -0.927/-640.126 | 3315 | +0.145/+0.101 | 131.6829 | 15710/10316/18/4/143 |
| R1-d2 v0.15 | decongestion=2，pin cost=600，LUT6D=0 | -1.398/-3378.189 | 5960 | +0.148/+0.102 | 123.9926 | 16237/9770/18/4/308 |

Fmax按任务卡公式1000/(6.667-WNS)计算。资源使用布线后层次汇总表的顶层一行，含探针移位链。u_cpu本身R1为15829 LUT、9035 FF；R2为15453 LUT、9573 FF。资源表原文见artifacts各轮resource_summary.txt及resource_hier.txt。

两轮布局布线均完成。慢角Setup不满足150MHz；Hold、Recovery、Removal均无违例。新版方向表的地址宽度不匹配警告已经消失。

## 最差路径

- R1：执行级操作数寄存器到预测器RAS寄存器使能，13级逻辑；逻辑2.307ns、布线5.251ns。
- R2：乘法器APM输出经写回/操作数选择路径，5级逻辑；逻辑3.787ns、布线3.152ns。
- 最差200条Setup、最差20条逐级Setup、最差20条Hold见artifacts/R1和R2，慢角/快角均保留。
- R1慢角Setup共有5111个违例端点，5000条导出保留最差5000个端点，其余111个端点超出任务卡指定的导出上限。R2的3315个违例端点均已导出。

## IO和流程提示

两轮约束检查均为0错误、0严重警告、3普通警告，分别为rst_n_i、scan_i、scan_o没有板级物理IO约束。FDC对这些探针端口设置false path；内部clk_sys路径继续按150MHz检查。Timing Analyzer同时报告这些端口没有外部延迟约束。

日志显示本轮还执行了Generate Bitstream，出现SCBV未设置提示。卡56不做上板，生成的比特流不作为本卡交付。R1补跑配置已关闭Generate Bitstream的Auto Run。

## LUTRAM读出延迟（R1默认轮）

已按RAM输出DO引脚分别定向导出BTB和方向表的慢角最差10条路径，逐级明细及输出弧Incr值见artifacts/R1/timing_lutram_detail.txt。最差BTB读出路径slack为-0.656ns，其中RAM输出弧为0.188ns；最差方向表读出路径slack为-1.195ns，其中RAM输出弧为0.240ns。输出弧延迟不包含后续bank选择、比较或布线延迟。

## R1补跑状态

R1默认WNS低于-1.0ns，按卡56需要补跑。已配置：

```tcl
pnr -plc_decongestion 2 -pin_cost_increasing_speed 600 -logic_optimize_lut6d_combing_strategy 0
```

R1-d2已完成，原始报告确认三个参数实际生效，沿用既有综合和Device Map。R2没有触发补跑条件，保持默认配置。

补跑相对R1默认：WNS变差0.056ns，TNS从-2188.698ns变为-3378.189ns，违例端点增加849个；PnR耗时从9分33秒缩短为8分18秒。默认参数的R1时序优于本次补跑，保留全部结果供协调者分析，未继续扫参。

补跑最差路径仍为执行级操作数到RAS寄存器使能，12级逻辑，逻辑延迟2.260ns、布线延迟5.226ns（69.810%）。u_cpu本身资源为15880 LUT、9027 FF；顶层含探针的资源见上表。

R1-d2慢角5960个违例端点保留最差5000条，按任务卡注明剩余960个端点超出导出上限。最差200条Setup、最差20条Setup逐级明细和最差20条Hold均已保存。

R1-d2的BTB和方向表均已按RAM输出DO引脚分别定向导出慢角最差10条路径，见artifacts/R1-d2/timing_lutram_detail.txt。

补跑最差BTB读出路径slack为-0.446ns，其RAM输出弧为0.078ns；方向表分别为-1.223ns、0.113ns。

## 原始报告在Windows本地的路径

- R1默认完整日志、报告、原PDS、FDC及布线数据库：G:/codex_project/EdRV32-FPGA/EdRV32-PROBE-V015/report-captures/card56-default/
- R1-d2完整日志、报告及布线数据库：G:/codex_project/EdRV32-FPGA/EdRV32-PROBE-V015/report-captures/card56-d2/
- R2默认完整日志、报告、原PDS、FDC及布线数据库：G:/codex_project/EdRV32-FPGA/EdRV32-PROBE-REL/report-captures/card56-default/
- 5000条导出的原始报告：G:/codex_project/EdRV32-Competition-2026/build/card56/下timing5000-R1/report_timing/、timing5000-R2/report_timing/、timing5000-R1-d2/report_timing/。
- 压缩原始报告及整理文件：artifacts/R1/、artifacts/R2/和artifacts/R1-d2/。每轮5000条原始报告包含Setup/Hold、Recovery/Removal、慢快角，未压缩约200–230MB，压缩后仍为数MB；为满足任务卡详细路径回传要求保留。

## 状态

卡56要求的两轮默认实现及R1补跑数据已取得，整理在artifacts/R1、R2、R1-d2，作为本轮结果回传。
