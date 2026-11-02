# 卡31 B3F全系统：综合与Device Map阶段结果

| 项 | 结果 |
|---|---|
| 代码输入 | 50a64dd7befcbe1af1b8bfd26377461ed82ce551 |
| 源文件数 | 164，用户明确确认按164继续；未补文件凑任务卡原预计165 |
| 工程 | G:/codex_project/EdRV32-FPGA/EdRV32-B3F/EdRV32-B3F-card31.pds，保留原旧工程文件 |
| 已完成 | Compile、Synthesize ADS、Device Map，原流程日志E=0 |
| ILA | 未取得FIC或配置截图；没有插核成功证据，调试核资源未取得，**卡31未完成** |
| 后续流程 | 本卡不布局布线、不生成bitstream或上板 |

## 耗时和警告

| 阶段 | 实际耗时 | CPU / Process CPU | 峰值内存池 | W / C / E行 |
|---|---|---|---|---|
| Compile | 3m19s | 12s / 12s | 787MB | 5390 / 0 / 0 |
| Synthesize | 9m35s | 1m27s / 1m35s | 4051MB | 19636 / 61 / 0 |
| Device Map | 1m44s | 12s / 13s | 2711MB | 331 / 0 / 0 |

原始CMR/SNR/DMR保存在artifacts/native_reports；警告按代码分组见warning_counts.txt，原文见logs/。C级包含共享引脚ConstraintEditor-2002和驱动强度ConstraintEditor-2009，全部保留。消息行数不当作独立缺陷数量。

## 全系统资源（未含已确认的ILA调试核）

Device Map：LUT **104271（66%）**，FF **113336（36%）**，DRM **289.5（70%）**，APM **448（61%）**，Distributed RAM 2252（6%），IO137（35%），GPLL6/PPLL2。

以下为SNR按模块的包含子模块资源，不能与DMR总数直接混算或将父子层次叠加：

| 模块 | LUT | FF | 分布式RAM | APM | DRM |
|---|---:|---:|---:|---:|---:|
| 全顶层（SNR） |104275|113659|2252|448|289.5|
| u_cpu |15120|8794|143|4|18|
| u_mem |9402|8858|849|0|4|
| u_sys |1949|1631|8|0|20|
| u_vin |5513|7045|37|0|17|
| u_pix |5958|9763|0|18|11|
| u_geo |3252|3355|0|9|16|
| u_rnd |30232|24954|46|120|64.5|
| u_disp |2972|3939|0|7|8|
| u_npu |20801|35522|1048|290|128|
| u_eth |4389|4576|76|0|3|
| u_ddr3 |4675|5203|45|0|0|

完整层次表resource_hier.txt，时钟/复位/CE/Other High Fanout表high_fanout.txt及controlsets.txt均保存。Device Map有Number of Nets To Report，对应-fanout_number；手册PDF250页（正文249页）。本轮仅归档已运行结果，未改成1000重跑，故不宣称取得全量1000条高扇出数据。

## 时序与级数

已保存原SNR时序全部内容、逐时钟路径索引和logic levels≥8样本计数（仅原SNR覆盖，不冒充每时钟200条）。综合估算clk_mem setup WNS=-0.507ns、TNS=-86.999ns、461失败端点；clk_npu setup +0.236ns。慢角DDR相关hold最差-3.778ns，RGMII RX hold -1.106ns。**全部为综合阶段估算，不是布线后时序结论。**

按卡尝试从map ADF导出200路径，PDS报Flow-0013“should be of phase PNR”；随后按卡对syn ADF尝试，同样报错。原文见logs/map_timing_export_error.txt、syn_timing_export_error.txt。没有为导出时序启动PnR，未伪造200条路径。

## ILA阻塞和已做准备

IP来源逐项在artifacts/ip_sources.txt，复制32类IP：V公共/视频、N的NPU、R的RND；未提交生成目录。ILA应在综合后用Inserter创建FIC，说明及手册页码见user_steps.md、artifacts/ila/manual_steps.txt。

实际综合网表文字查找ila_cpu_r出现0次；cycle_r、instret_r、counter_r分别有322、323、2584处名称出现。这些出现次数不是位宽或寄存器个数。尚不能确认B组64个寄存器及A组400位的实际可选探针名，故不宣称符合插核要求，也未改RTL或综合配置强留信号。该结果需交Claude确认保留方式，再继续插核。

## 与卡24 R PnR重叠

卡31首次后台启动17:38:05，后按用户要求停止；随后用户重新运行取得上述综合/Map结果（Map结束17:54:07）。这段活动均发生在R PnR期间（R结束20:33:42）。用于比较R耗时的备注窗口为17:38:05–17:54:07，**中间停止/重启间隔没有精确记录，不当成连续满负载时长**；没有仿真运行情况证据，不补写“完全空闲”。相同备注同时写入卡24结果。

DMR约2.4MB，保留完整约束、扇出及资源原文供分析；不提交数据库、网表、IP目录、PDS工程、bitstream或完整PDS run.log。


## 2026-11-02 补充：用户已启动的布局布线过程快照

本次按用户要求归档正在运行的B3F-card31，未停止、重启或修改PDS流程。上文“本卡不布局布线”是原卡31范围；本节记录用户之后已自行运行的PnR，不代表原卡ILA要求已完成。

- 原始目录：`G:/codex_project/EdRV32-FPGA/EdRV32-B3F`，项目`EdRV32-B3F-card31.pds`。
- Compile、Synthesize、Device Map原生CMR/SNR/DMR已一并保存，既有资源、层次、扇出、警告及综合时序产物一起回传。
- Placement已完成，日志耗时207.12秒；进入timing driven router，线程数5。
- 路由网络176851条，负载804443个；时钟路由在iteration5达到未布通0。
- 通用网络最新完成iteration116，未布通13273，overused29690；第7轮为159132/1223044，第100轮为15780/36305。仍在收敛，尚不能判断最终成功或失败。
- 后段单轮日志MT total route time达到约608–894秒；它是原日志每轮字段，不当成整个PnR累计墙钟耗时。完整已输出的各轮数值见routing_iterations.txt。
- Placement末尾原文Worst slack=-1033、TNS=-157628，原日志未标单位，保留原值，不换算成最终布线后WNS/TNS。负裕量与尚多的未布通/overused表明当前有时序和布线压力，不能据此单独断言长耗时根因。
- `place_route/edrv32_fpga_board_full_top.prr`和`place_route/run.log`目前为空，尚无可交付的最终PRR、布线后setup/hold/recovery路径或bitstream结果。本次不启动额外时序分析。

新增快照在`artifacts/pnr_in_progress/`：布局布线日志节选（含各轮原文）、迭代数据、clock_utilization、路由线程信息以及节选范围的警告/错误原文与计数。完整原始run.log仍留本机，不上传数据库、网表或PDS工程文件。此为进行中快照，最终时序及危险路径待PnR完成后再补。
