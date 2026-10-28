# 20261028-07-media-r3-b1 结果

| 项 | 内容 |
|---|---|
| 任务卡执行commit | b23c03c25060ea392e97b82e86f35432bd9da8d6 |
| PDS / 器件 | 2022.2-SP6.1 build138931；PG2L200H-6 FBB676；ADS |
| 完成情况 | A全部完成且时序通过；B两种编译选项均完成5000次、运行≥10秒且CRC PASS，按键和系统信息结果PASS，要求记录已取得 |

## A 媒体/网络模块

| 时钟/角 | WNS(ns) | TNS(ns) | WHS(ns) | THS(ns) | setup/hold违例端点 | Fmax(MHz，推算) |
|---|---:|---:|---:|---:|---|---:|
| clk_mem/slow | 0.388 | 0.000 | 0.103 | 0.000 | 0/0 | 131.3715 |
| clk_ext/slow | 1.898 | 0.000 | 0.169 | 0.000 | 0/0 | 163.8807 |
| clk_mem/fast | 3.243 | 0.000 | 0.100 | 0.000 | 0/0 | 210.2165 |
| clk_ext/fast | 4.444 | 0.000 | 0.115 | 0.000 | 0/0 | 281.2148 |

上一轮clk_mem slow -1.270 ns/542个违例端点（ETH196、GEO174、VIN172）；本轮+0.388 ns、0个，WNS改善1.658 ns。
PDS violating endpoints=0; exported unique endpoints=0; coverage=complete
全部模块均无clk_mem slow setup违例，寄存器对违例分组为无，未用最差200条代替全量违例统计。
clk_ext slow +1.898 ns。两时钟原引脚K21/D18及异步组检查保存在clock_checks.txt。每域最差200条setup、前20条逐级明细、fast hold前20条均已保存。
另保留0<slack<1 ns的危险setup样本144条及前20条明细；不能以无违例代表裕量充足。

| 模块（PnR） | LUT | FF | 分布式RAM | APM | DRM36K当量 |
|---|---:|---:|---:|---:|---:|
| edrv32_fpga_media_top | 18416 | 23199 | 113 | 141 | 46 |
| u_disp | 1468 | 1729 | 0 | 0 | 4 |
| u_eth | 3858 | 4234 | 76 | 0 | 3 |
| u_geo | 3184 | 3002 | 0 | 9 | 16 |
| u_pix | 4943 | 7107 | 0 | 132 | 11 |
| u_reset_ext | 0 | 2 | 0 | 0 | 0 |
| u_reset_mem | 0 | 2 | 0 | 0 | 0 |
| u_vin | 3562 | 4213 | 37 | 0 | 12 |

上一轮VIN3532、PIX4935/132 APM、DISP1452、GEO3357/9 APM、ETH3841 LUT；本轮完整层次和器件占用率见media/resource_hier.txt、resource_summary.txt。

## B B1 上板补测

| 时钟/角 | WNS(ns) | TNS(ns) | WHS(ns) | THS(ns) | setup/hold违例端点 | Fmax(MHz，推算) |
|---|---:|---:|---:|---:|---|---:|
| clk_sys/slow | 0.674 | 0.000 | 0.143 | 0.000 | 0/0 | 107.2271 |
| clk_sys/fast | 4.046 | 0.000 | 0.101 | 0.000 | 0/0 | 167.9543 |

clk_board37.037 ns、clk_sys10.000 ns，generated clock已生效，见b1/clock_checks.txt。本轮slow WNS与上一轮+0.674 ns相同。
本轮PnR逻辑资源[LUT,FF,分布式RAM,APM,DRM36K当量]=[14648, 8334, 151, 4, 26]；上一轮[14648,8334,151,4,26]。其余IO/PLL及18K/36K拆分见resource_summary.txt。

### 串口

原始日志来自用户串口工具现有会话，COM7/115200/8N1，保留时间戳与RX/TX/SYS方向；未向板卡发送新指令。
完整当前会话见b1/uart/serial_console_session.log；分段及结论见同目录uart_summary.md。Build commit为207b05a，CLK_SYS_HZ100000000，ISA为rv32im_zicsr_zifencei。O2从SRAM app启动；tuned为UART download，原始文件monitor_tuned.wire共31896字节，工具报告发送完成，板卡报告UART download complete。下载记录另存b1_uart_download.log。

| 编译选项 | 迭代次数 | 计时周期 | 运行秒数（cycles/100MHz） | CoreMark | CoreMark/MHz | CRC | IPC |
|---|---:|---:|---:|---:|---:|---|---:|
| O2 | 5000 | 1387629692 | 13.87629692 | 360.326 | 3.603 | PASS | 1.038 |
| tuned | 5000 | 1159978150 | 11.59978150 | 431.042 | 4.310 | PASS | 1.068 |

O2和tuned均明确打印duration >=10 s及CoreMark result PASS，两轮CRC均PASS；HPM分两轮采集，O2串口总墙钟约28秒、tuned约23秒，不能当作单轮CoreMark计时。编译标志中DITERATIONS=10是编译默认值，实际Iterations均为5000。tuned标志末尾含-O3 -funroll-all-loops -finline-limit=600 -falign-functions=4 -falign-jumps=4 -falign-loops=4，后面的-O3覆盖前面的默认-O2。
tuned计时1159978150周期=11.59978150秒，退休1239834691条指令，IPC1.068；两版HPM原文分别保存hpm_o2.txt和hpm_tuned.txt。按Iterations/Sec比较，431.042/360.326−1，tuned较O2提升约19.63%。
上一轮O2为10次短诊断3.600 CoreMark/MHz；任务卡仿真参考O2 3.592456、tuned4.290770，仅作参考。

按键：第一次NOT PRESSED within wait；第二次按下3748 ms、松开4003 ms、保持255 ms，GPIO button result PASS。两次记录都保留。
第二次Timer请求4096、实际4143、晚47周期，mcause0x80000007、interrupts1、PASS；I2C两端口0设备，日志SCAN COMPLETE，未将零设备视为硬件连通性通过。
菜单3系统信息已补充并PASS，见b1_sysinfo.log。LED的本轮独立目视确认未取得，不沿用上一轮观察代替；按键按下/松开的串口判定已为PASS。

## 报告、日志与本地路径

media/和b1/均保留各阶段耗时、CPU时间、峰值内存、warning分类与全部W/E/C提示摘录、原生资源报告及补导时序命令。B1含bitstream生成摘要，SCBV提示保持原文。
原始PDS工程、IP目录、数据库、bitstream及完整PDS日志不入库；串口原始日志按任务卡上传。未改RTL/IP/约束，没有重跑综合或PnR，只补导STA。

- MEDIA：G:/codex_project/EdRV32-FPGA/EdRV32-MEDIA/各阶段子目录。
- B1：G:/codex_project/EdRV32-FPGA/EdRV32-B1/各阶段子目录。
- 补导STA：G:/codex_project/EdRV32-Competition-2026/build/win/20261028-07-media-r3-b1/exports/。
