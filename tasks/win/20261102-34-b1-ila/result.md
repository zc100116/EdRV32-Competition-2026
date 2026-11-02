# 卡34 B1计数器ILA实验：阶段结果与冻结计数问题

代码输入79801bc0；工程G:/codex_project/EdRV32-FPGA/EdRV32-B1-ILA，PG2L200H-6/FBB676，PDS2022.2-SP6.1。43个源码。复用B3F的8类IP，ROM/SRAM初始化为卡24dat；B1导入脚本的include改为已验证的工程相对路径+tab格式。复制脚本位于src/copy_b3f_ips.tcl。本卡未修改RTL、monitor、ROM内容。

## 当前结论

- 10组计数器各低40位可选，400位探针和两个40位触发端口位序全部核对通过。
- Device Map日志Core Insertion Complete，成功插入DebugCore0（Debugger显示MyFLA0）。
- 布局布线和bitstream完成，时序All Constraints Met。
- 条件触发成功，1024点窗口退休增量仅0/1/2，窗口IPC1.162268，串口整体IPC1.038，属于同一量级。
- **未完成卡34第6步的两轮冻结计数逐项相等核对；当前monitor在打印前恢复mcycle/minstret计数，不能凭打印后手动抓取宣称冻结值一致。卡34不能判全部通过。**

## 实现报告

| 阶段 | 实际耗时 | CPU / Process CPU | 峰值内存池 | W/C/E行 |
|---|---|---|---|---|
| Compile |27s|3s / 3s|270MB|1384/0/0|
| Synthesize |1m25s|12s / 12s|1113MB|1937/0/0|
| Device Map |47s|2s / 2s|712MB|35/0/0|
| Place & Route |4m26s|1m27s / 1m47s|3378MB|0/4/0|
| Report Timing |28s|10s / 11s|2191MB|12/0/0|
| Bitstream |39s|8s / 8s|2686MB|0/1/0|

原厂CMR/SNR/DMR/PRR/RTR/BGR保留在native_reports/，各阶段警告按代码分组及原文在logs/；C级原文保留，不将0条E解释成没有警告。没有重新综合或布局布线来生成本次报告。

含ILA的Device Map全芯片资源：LUT18838、FF14816、DRM50、分布式RAM151、APM4、IO13、GPLL1、SCANCHAIN1、USCM2。
插核前SNR全芯片LUT17159、FF10830、DRM38。两阶段净变化为LUT+1679、FF+3986、DRM+12，但包含Map优化差异，**不是单独ILA精确占用**；未取得独立调试核层次资源表。详见resource_summary.txt及resource_hier_before_ila.txt。

时序：clk_sys slow setup+0.498ns、fast setup+3.974ns；slow hold+0.143ns、fast hold+0.100ns。JTAG与capture相关时钟也无负裕量。完整各时钟WNS/TNS/WHS/THS和recovery/removal/pulse width均见timing_summary.txt，危险小正裕量与最差路径另存，不只保留违例路径。

## 探针和配置

实际网名和寄存器实例见probe_names.txt、counter_register_excerpt.txt：
- clk_sys_w，100MHz，上升沿；
- mcycle=cycle_r[39:0]，minstret=instret_r[39:0]；
- hpm3–10数据网为counter_r[0..7][39:0]，驱动寄存器实例为g_counter[2..9].g_hpm.count_r[0..39]；
- DataPort低到高依次mcycle、minstret、hpm3…hpm10，每组40位；
- TriggerPort0=minstret，TriggerPort1=mcycle，深度1024，不启用存储限定。

插核原FIC与Debugger导出的FIC分别保存；initial_capture和coremark_window含Debugger工程及WDF，用于保留原始采样和用户组合的总线。Debugger导出FIC使用DataPort编号，不当成原综合网名。Inserter和Debugger操作出处为本机Fabric_Inserter_User_Guide.pdf第9–17页、Fabric_Debugger_User_Guide.pdf第12–18页及26–36页（PDF页码）。

## CoreMark串口与运行窗口

两次CoreMark均5000次、CRC/CoreMark PASS、CoreMark/MHz3.603。
参考运行两轮instructions均1441025033；cycles为1387629902、1387628281。
触发运行两轮instructions仍均1441025033；cycles为1387628279、1387628217。完整串口见uart/coremark_reference.log、coremark_window_run.log。

参考指令数一半向下取整=720512516，40位Hex002AF22604。条件TU0（minstret）等于此值，窗口sample102命中，约10%前置点。

| 退休增量 | 周期数 | 比例 |
|---|---:|---:|
|0|215|21.017%|
|1|427|41.740%|
|2|381|37.243%|

1024采样点产生1023个相邻周期差分；mcycle每步严格+1，总+1023；minstret总+1189；IPC=1189/1023=1.162268。HPM3–10窗口增量依次381、427、215、192、182、3、204、22，第1轮对应dual retire、single retire、zero retire、branches、pair RAW、pair structural、pair slot1 type、pair missing slot1。前三项和1023、427+2×381=1189，与退休计数交叉对应。

原始PRN/TXT、重建CSV和差分CSV、计算说明在ila/coremark_window*。PRN含原始400位DataPort两份重复列；转换取第一份，每40位按低位优先重建。显示总线进制混用，mcycle打印十进制，其余多为Hex，不能把TXT统一0x前缀当成全部Hex直接解析。CSV保留十进制重建值；不从截图估算IPC。

## 冻结计数问题：需Claude处理

任务卡第6步假定“串口打印该轮HPM结果后，mcycle/minstret/HPM仍全部冻结，手动抓取逐项等于串口”。当前实现不满足这一假定：

```c
// sw/apps/monitor/benchmark.c
monitor_hpm_stop();
stop_time();
cycles[round] = get_time();
monitor_hpm_read(...);
monitor_hpm_release();
info_number("HPM round", ...);
// 随后打印cycles/instructions
```

sw/apps/monitor/hpm.c的monitor_hpm_release写mcountinhibit=HPM_INHIBIT & ~5u，重新放开CY和IR。HPM本身仍冻结，但mcycle/minstret在打印前已经重新增长；下一轮prepare还会重配和清零。因此“打印后任意时刻Immediate”无法保证10组逐项相等，不能把不相等直接认定为ILA错误。

本次已证明计数器探针、数据位序、条件触发、采样时钟和运行窗口可用；尚未提供两轮最终冻结快照的逐项比较。请Claude确定软件停留/握手或其他准确采集时机，重新下发。Windows端没有自行改软件、IP或ROM，也没有为凑验收编造冻结值。

## 缺项与文件范围

没有本次条件触发页面截图，初次立即抓取截图已保存。未完成两轮冻结CSV，因此缺项明确保留。只提交报告、必要日志、FIC和Debugger采样工程/WDF/PRN/TXT/CSV；不提交PDS工程、IP目录、数据库、综合网表、bitstream。
