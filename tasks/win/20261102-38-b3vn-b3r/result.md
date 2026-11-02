# 卡38：B3VN阶段报告（B3R另行整理）

本次按用户要求先上传B3VN已有报告和日志，布局布线仍在运行，没有中断、重启或修改当前流程。B3R已完成Map，但其完整结果不包含在本次提交范围。

| 项 | B3VN |
|---|---|
| 代码输入 | ab09d64f13f878cfe8a6e664629b437d8a7d4653（origin/zc100116/b3，含RND扇出、xbar调度优化） |
| 工程 | G:/codex_project/EdRV32-FPGA/EdRV32-B3VN-r3/EdRV32-B3VN-r3.pds |
| 顶层 | edrv32_fpga_board_vnpu_top |
| 工具 / 器件 | PDS2022.2-SP6.1，PG2L200H-6 FBB676 |
| 源文件数 | 144；卡写145，用户已明确允许按144继续（R同意102） |
| IP | 来自卡33 B3F，29类，未重新生成；初始化沿用卡24 |
| ILA | 用户明确补充要求R/VN均加入，覆盖卡38原“不插ILA”要求 |
| 当前状态 | Compile、Synthesize ADS、Device Map完成；PnR进行中 |

## 阶段耗时与消息

| 阶段 | 墙钟 | CPU / Process CPU | 峰值内存池 | W / C / E消息行 |
|---|---|---|---|---|
|Compile|2m39s|8s / 8s|711MB|4661 / 0 / 0|
|Synthesize ADS|7m55s|11s / 14s|3507MB|16685 / 61 / 0|
|Device Map|1m51s|7s / 8s|2192MB|356 / 0 / 0|
|Placement（PnR内部）|69.70s|未取得|未取得|见PnR节选|
|Routing|尚未结束|未取得|最终峰值未取得|见PnR节选|

完整阶段数字在artifacts/VN/flow_summary.txt。各代码分组计数在warning_counts.txt；logs/保留不同W/C/E原文，去除完全相同重复行，但计数按原始日志，不能视为独立问题数。C级包含共享引脚/驱动强度约束提示，原文保留供检查。

## Map资源（含ILA）

|LUT|FF|DRM|APM|Distributed RAM|IO|GPLL / PPLL|
|---:|---:|---:|---:|---:|---:|---|
|75788（48%）|93303（30%）|237（58%）|328（45%）|2062（6%）|137（35%）|6 / 2|

resource_summary.txt保存Map汇总，resource_hier.txt保存SNR完整模块层次表。SNR为插核前资源，Map含插核及优化，不能把两者差额直接当作ILA独立资源。父模块包含子模块，不能相加。高扇出报告数设置1000，Clock/Reset/CE/Other原文在high_fanout.txt，综合控制集在controlsets.txt。

## ILA

用户要求加入400位CSR计数器ILA，clk_sys_w，深度1024，两个40位触发端口minstret/mcycle。数据按mcycle、minstret、hpm3–10各低40位连接。FIC从B1适配本工程本地ADF，全部480位连接与本次综合网表核对。Map日志确认Core Insertion Complete，调试核已实际插入。配置文件在artifacts/VN/ila/。

## 当前PnR快照

设置与卡33 A相同：Placement Decongestion Mode2，拥塞图开启，路由线程5。当前路由网络总数136126。

- Placement完成，耗时69.70秒。原文Worst slack=766、TNS after placement=0；日志数值保持原样，不冒充最终布线后setup/hold结论。
- 第17轮：未布通48858，overused200375。
- 第26轮：未布通30423，overused93997，日志MT total route time266.568sec为该轮字段，不是整个PnR累计墙钟耗时。
- 每轮Unrouted general nets原文在pnr_progress.txt；logs/pnr_excerpt.txt保留布局尾部及当前路由上下文，另保存clock_utilization和线程日志。
- PRR当前为空，无最终布线成功/失败、最终峰值内存、布线后时序、200条setup/最差hold路径或bitstream结论。原生SNR仍保留综合估算时序全文，不将其称为布线后时序。
- 按卡38：第40轮未布通>18000停止VN并回传；本快照尚未达到该轮次。

## 路径、IP与已修复问题

工程和源码位于同一codex_project父目录，源码/include使用../../EdRV32-Competition-2026相对路径，include沿用tab分隔格式；已导入144源文件。

准备IP时名称提取遗漏rom类，最初仅28类，Compile报Verilog-4072：ip_rom_boot is referenced to undefined module。已补复制完整ROM目录并由用户add_design注册，正确为29类；之后Compile/综合/Map成功。未改RTL、ROM初始化或其他IP参数。原错误截图在logs/vn_rom_missing.png。此前宣称IP全部准备齐全不准确，修正记录保留。

最初创建项目脚本位于build目录，IP相对路径按脚本目录解析导致Flow-0049；已把准备脚本放到工程目录并指定work_dir，最终项目注册路径均正确。官方导入脚本没有改动。

## 数据位置与尚未完成项

artifacts/VN/native_reports/保存CMR、SNR、DMR原文；DMR约2.6MB，保留全部约束/资源/扇出信息供分析。完整原始阶段run.log、正在增长的全工程run.log、IP、数据库、网表、PDS工程和bitstream留在Windows本地目录，不上传。

布局布线尚未完成，上板测试未开展；本次结果不能作为卡38整体通过。用户要求的ILA改变已明确记录，后续时序和上板报告会包含其影响。
