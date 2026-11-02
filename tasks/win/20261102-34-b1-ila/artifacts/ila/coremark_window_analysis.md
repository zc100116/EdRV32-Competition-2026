# 卡34 CoreMark运行窗口采样分析

1024个连续采样点包含1023个可计算的相邻周期差分；不用1024作差分IPC分母。将PRN中DataPort[0..399]按已核对FIC顺序每40位小端拼接为mcycle、minstret、hpm3..10。原始PRN有重复的DataPort列，两组逐行一致，取第一组。保留原始PRN/TXT和转换的CSV，不修改原始数据。

导出文本的mcycle按十进制显示，其他总线多为十六进制，TXT统一前缀0x不能作为全部列进制依据。因此数值计算以PRN原始单bit重建为准。

## 触发与退休增量

触发值minstret=720512516（40bit Hex002AF22604），在sample102命中；前置采样102点，约10%。每个mcycle相邻增量均为1，无跳采样证据。

| 退休增量 | 相邻周期数 | 比例 |
|---|---:|---:|
| 0 | 215 | 21.017% |
| 1 | 427 | 41.740% |
| 2 | 381 | 37.243% |

窗口mcycle增量1023，minstret增量1189，IPC=1.162268。0/1/2的计数总和1023；1×427+2×381=1189，与minstret差值一致。该局部窗口IPC约1.162，本轮串口整体IPC1.038，同量级，不能把局部窗口替代完整跑分。

## HPM增量（第1轮事件1–8）

| 探针 | 本轮事件 | 窗口增量 |
|---|---|---:|
| hpm3 | dual retire | 381 |
| hpm4 | single retire | 427 |
| hpm5 | zero retire | 215 |
| hpm6 | branches | 192 |
| hpm7 | pair RAW | 182 |
| hpm8 | pair structural | 3 |
| hpm9 | pair slot1 type | 204 |
| hpm10 | pair missing slot1 | 22 |

本次串口CoreMark5000第1轮cycles1387628279、第2轮1387628217，两轮instructions均1441025033，CoreMark/MHz3.603，CoreMark PASS。完整本轮日志见../uart/coremark_window_run.log。

## 尚未完成的冻结值核对

本窗口验证运行中数值触发与IPC计算，不替代卡34第6步两轮最终计数逐项相等。代码sw/apps/monitor/benchmark.c在monitor_hpm_read之后、打印HPM round之前调用monitor_hpm_release；hpm.c的release重新放开mcycle/minstret，因此打印后手动抓取不保证这两个值冻结。尚未取得可据以宣称十组冻结值逐项相等的证据，需Claude确认采集时机/软件方案；Windows端没有修改monitor或ROM。
