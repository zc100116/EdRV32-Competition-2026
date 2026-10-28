# 20261028-06-board-b1 结果

| 项 | 内容 |
|---|---|
| 任务卡执行commit | 346c171c4b003b53f4df2b241ea145cefe91c8c3；软件构建75dff18 |
| PDS / 器件 | 2022.2-SP6.1 build138931；PG2L200H-6 FBB676；ADS |
| 工程 | G:/codex_project/EdRV32-FPGA/EdRV32-B1/EdRV32-B1.pds |
| 完成情况 | 综合/PnR/STA/bitstream完成并已有上板输出；O2短诊断、系统信息和外设日志已取得，5000次O2和tuned未取得，未满足完整B1验收 |

用户选择新建B1工程，再用PDS Tcl复制和导入原7个IP，另生成PLL；原EdRV32工程未改。

## IP

| IP | 模块/端口 | 配置 |
|---|---|---|
| ip_pll_sys | clkin1、clkout0、lock，与顶层一致 | 输入27 MHz；I=1、M=2、F=18.75、O0=10.125，CLKOUTF反馈；推算VCO1012.5 MHz、输出100.000 MHz；无输出buffer，后端已插全局缓冲 |
| ip_rom_boot | 与包装一致 | 2048×64，INIT_EN=true，HEX，本卡src/ip_rom_boot.dat |
| ip_ram_sram | 与包装一致 | 单口8192×64，8字节写使能，INIT_EN=true，HEX，本卡src/ip_ram_sram.dat |

实际IP端口和初始化配置见ip/ip_check.txt。初始化已展开为生成RTL的INIT向量，未修改生成文件。PLL选项截图未取得，频率来自生成参数及PDS时序，不是仪器实测。

## 约束

clk_board=37.037 ns，clk_sys=10.000 ns。原create_generated_clock命令正常执行，get_pins u_pll_sys/clkout0未报找不到对象，最终解析为u_pll_sys/u_gpll/gpll_inst/CLKOUT0。
clk_sys报告6949个clock loads、303个non-clock loads；详细路径涵盖CPU及系统子系统。没有本地修改FDC，无需提交fdc_used.fdc。
实际Compile已通过。首次GUI导入在include设置应用前启动层次解析，曾报缺头文件及Flow-0245；后续Compile正确读取两个include目录，无Error。历史错误摘录单独保留，未为此修改RTL或脚本。

## 时序

| 时钟/角 | WNS(ns) | TNS(ns) | WHS(ns) | THS(ns) | setup/hold违例端点 | Fmax(MHz，推算) |
|---|---:|---:|---:|---:|---|---:|
| clk_sys/slow | 0.674 | 0.000 | 0.143 | 0.000 | 0/0 | 107.2271 |
| clk_sys/fast | 4.046 | 0.000 | 0.101 | 0.000 | 0/0 | 167.9543 |

clk_board没有寄存器到寄存器的setup/hold汇总行，相关WNS/TNS/WHS/THS为未取得/不适用，不填0。
PDS最终判定All Constraints Met；clk_sys setup最小裕量+0.674 ns，fast hold最小+0.101 ns。推算Fmax取舍入后的WNS，和原报告107.2280 MHz有微小舍入差。
另导出0<slack<1 ns的危险setup路径200条，连同最差200条setup、20条setup逐级明细和fast hold最差20条保存。

最差路径前10条：

| 起点 → 终点 | 裕量(ns) | 级数 |
|---|---:|---:|
| u_cpu_subsys/u_dcache/u_tag0/u_ip/U_ipm2l_sdpram_ip_ram_dcache_tag/ADDR_LOOP[0].DATA_LOOP[0].U_GTP_DRM18K_E1/gopdrm_18k/CLKB → u_cpu_subsys/u_dcache/dirty1_r[77]/opit_0_inv_L7Q_perm/B2 | 0.674 | 8 |
| u_cpu_subsys/u_core/u_frontend/u_ib/read_ptr_r[0]/opit_0_inv_L5Q_perm/CLK → u_cpu_subsys/u_core/u_csr/counter_r[7][63]/opit_0_inv_AQ_perm/CE | 0.701 | 7 |
| u_cpu_subsys/u_icache/addr_r[11]/opit_0/CLK → u_cpu_subsys/u_core/u_frontend/u_predictor/ras_data_r[61]/opit_0_L6Q_perm/CE | 0.701 | 9 |
| u_cpu_subsys/u_dcache/valid1_r[121]/opit_0_inv_L6Q_perm/CLK → u_cpu_subsys/u_core/u_frontend/u_predictor/ras_data_r[74]/opit_0_L6Q_perm/I1 | 0.706 | 7 |
| u_cpu_subsys/u_dcache/u_tag0/u_ip/U_ipm2l_sdpram_ip_ram_dcache_tag/ADDR_LOOP[0].DATA_LOOP[0].U_GTP_DRM18K_E1/gopdrm_18k/CLKB → u_cpu_subsys/u_dcache/dirty1_r[88]/opit_0_inv_L7Q_perm/M | 0.735 | 8 |
| u_cpu_subsys/u_icache/addr_r[11]/opit_0/CLK → u_cpu_subsys/u_core/u_frontend/u_predictor/ras_data_r[60]/opit_0_L6Q_perm/CE | 0.736 | 9 |
| u_cpu_subsys/u_dcache/u_tag0/u_ip/U_ipm2l_sdpram_ip_ram_dcache_tag/ADDR_LOOP[0].DATA_LOOP[0].U_GTP_DRM18K_E1/gopdrm_18k/CLKB → u_cpu_subsys/u_dcache/dirty0_r[88]/opit_0_inv_L7Q_perm/M | 0.741 | 8 |
| u_cpu_subsys/u_dcache/u_tag0/u_ip/U_ipm2l_sdpram_ip_ram_dcache_tag/ADDR_LOOP[0].DATA_LOOP[0].U_GTP_DRM18K_E1/gopdrm_18k/CLKB → u_cpu_subsys/u_dcache/dirty1_r[93]/opit_0_inv_L7Q_perm/A3 | 0.747 | 8 |
| u_cpu_subsys/u_dcache/valid1_r[121]/opit_0_inv_L6Q_perm/CLK → u_cpu_subsys/u_core/u_frontend/u_predictor/ras_data_r[113]/opit_0_L6Q_perm/I4 | 0.748 | 7 |
| u_cpu_subsys/u_dcache/u_tag0/u_ip/U_ipm2l_sdpram_ip_ram_dcache_tag/ADDR_LOOP[0].DATA_LOOP[0].U_GTP_DRM18K_E1/gopdrm_18k/CLKB → u_cpu_subsys/u_dcache/dirty1_r[93]/opit_0_inv_L7Q_perm/B4 | 0.759 | 8 |

## 资源

| 阶段 | LUT | FF | DRM18K/36K | APM | 分布式RAM | IO | PLL |
|---|---:|---:|---|---:|---:|---:|---:|
| 综合 | 14737 | 8334 | 4 / 24 | 4 | 151 | 9 | 1 |
| PnR逻辑层次 | 14648 | 8334 | 4 / 24（SNR拆分；PRR26当量） | 4 | 151 | 9 | 1 |

PnR逻辑层次口径；DRM为36K当量，完整容量/占用率及综合口径见resource_summary.txt。

| 模块 | LUT | FF | 分布式RAM | APM | DRM36K当量 |
|---|---:|---:|---:|---:|---:|
| edrv32_fpga_board_b1_top | 14648 | 8334 | 151 | 4 | 26 |
| edrv32_fpga_board_b1_top/u_cpu_subsys | 13202 | 7172 | 143 | 4 | 6 |
| edrv32_fpga_board_b1_top/u_cpu_subsys/u_cache_ctrl | 46 | 161 | 0 | 0 | 0 |
| edrv32_fpga_board_b1_top/u_cpu_subsys/u_core | 10063 | 5399 | 143 | 4 | 0 |
| edrv32_fpga_board_b1_top/u_cpu_subsys/u_dcache | 2411 | 1121 | 0 | 0 | 3 |
| edrv32_fpga_board_b1_top/u_cpu_subsys/u_icache | 682 | 491 | 0 | 0 | 3 |
| edrv32_fpga_board_b1_top/u_pll_sys | 0 | 0 | 0 | 0 | 0 |
| edrv32_fpga_board_b1_top/u_sys_subsys | 1445 | 1162 | 8 | 0 | 20 |
| edrv32_fpga_board_b1_top/u_sys_subsys/u_clint | 351 | 241 | 0 | 0 | 0 |
| edrv32_fpga_board_b1_top/u_sys_subsys/u_gpio | 98 | 116 | 0 | 0 | 0 |
| edrv32_fpga_board_b1_top/u_sys_subsys/u_i2c | 49 | 67 | 0 | 0 | 0 |
| edrv32_fpga_board_b1_top/u_sys_subsys/u_media_apb_async | 6 | 19 | 0 | 0 | 0 |
| edrv32_fpga_board_b1_top/u_sys_subsys/u_media_apb_bridge | 18 | 11 | 0 | 0 | 0 |
| edrv32_fpga_board_b1_top/u_sys_subsys/u_plic | 151 | 149 | 0 | 0 | 0 |
| edrv32_fpga_board_b1_top/u_sys_subsys/u_reset_ctrl | 11 | 19 | 0 | 0 | 0 |
| edrv32_fpga_board_b1_top/u_sys_subsys/u_rom | 61 | 30 | 0 | 0 | 4 |
| edrv32_fpga_board_b1_top/u_sys_subsys/u_sram | 138 | 37 | 0 | 0 | 16 |
| edrv32_fpga_board_b1_top/u_sys_subsys/u_sys_apb_bridge | 98 | 127 | 0 | 0 | 0 |
| edrv32_fpga_board_b1_top/u_sys_subsys/u_sys_apb_decoder | 69 | 0 | 0 | 0 | 0 |
| edrv32_fpga_board_b1_top/u_sys_subsys/u_sys_xbar | 187 | 137 | 0 | 0 | 0 |
| edrv32_fpga_board_b1_top/u_sys_subsys/u_sysctrl | 24 | 66 | 0 | 0 | 0 |
| edrv32_fpga_board_b1_top/u_sys_subsys/u_uart | 184 | 143 | 8 | 0 | 0 |

完整下级层次见resource_hier.txt。DRM18K/36K拆分、IO、PLL均保留SNR/PRR原文，不把不同阶段物理LUT相加当作逻辑LUT。

## 上板与串口

使用用户提供的EdRV32 Serial Console 2.0，COM7、115200、8N1、UTF-8，DTR/RTS关闭。通过工具REST API读取既有会话，没有另开串口或向板卡发送测试指令。
完整原始RX/TX/SYS时间戳日志见uart/serial_console_session.log；O2及外设段分别保存b1_o2.log和b1_periph.log，原始会话条目含hex字段另存serial_console_buffer.txt。

启动确认：logo、CHIP_ID 0xed320001、CLK_SYS_HZ 100000000、ROM16384/SRAM65536、I$/D$各8192、MEM_READY=1、SRAM app启动、Build commit 75dff18、GCC15.2.0。ISA打印rv32im_zicsr_zifencei，不含C扩展。

### CoreMark

| 编译选项 | 迭代 | 计时周期 | Iterations/Sec | CoreMark/MHz | CRC | IPC |
|---|---:|---:|---:|---:|---|---:|
| O2（短诊断） | 10 | 2777214 | 360.073 | 3.600 | seed/list/matrix/state及总结果PASS | 1.037 |
| tuned | 未取得 | 未取得 | 未取得 | 未取得 | 未取得 | 未取得 |

串口明确打印：Score status: short diagnostic run (<10 s); not a publishable CoreMark score。上表为诊断输出，不能当作正式CoreMark成绩。
本次没有5000次O2计时，也没有tuned下载/运行记录；不将菜单1的一次短运行写成两种构建均已通过。
仿真参考（任务卡）：O2 3.592456、tuned4.290770 CoreMark/MHz，仅供参考，不代替板测。

HPM两轮：第一轮events1..8，2777214 cycles/2882008 instructions；第二轮events9..16，2776175 cycles/2882008 instructions。16项计数和比率原文见uart/hpm_summary.txt。GUI参数面板未捕获规则参数，但串口RX已包含HPM。

### 系统信息和外设

- 菜单3系统信息已取得，System info result: PASS；详见uart/b1_sysinfo.log。
- 用户观察：LED正常；按键测试策略问题，不太好测试。LED顺序记录为通过观察，按键功能未确认。两次外设测试均显示GPIO button pressed: 0。
- Timer两次：均请求4096周期，实际4168/4142，晚72/46周期；mcause=0x80000007，interrupts=1，均PASS。
- I2C：100000 Hz、地址0x08..0x77，两端口均0设备；日志为SCAN COMPLETE，未把零设备写成探测成功。

## 日志和bitstream

```text
STAGE compile: Errors=0 Warnings=1052
Verilog-2020	408
Verilog-2008	269
Verilog-2038	108
ConstantProbeLoop	108
Sdm-2003	79
Verilog-2023	46
Verilog-2039	15
Public-4030	13
Verilog-2036	4
Sdm-2010	2
Action compile: Real time elapsed is 0h:0m:26s
Action compile: CPU time elapsed is 0h:0m:1s
Action compile: Process CPU time elapsed is 0h:0m:1s
Current time: Wed Oct 28 23:20:09 2026
Action compile: Peak memory pool usage is 250 MB

STAGE synthesize: Errors=0 Warnings=1725
Public-4008	1006
Uncoded warning	707
Timing-4087	5
Uncoded fanout warning	4
Timing-4086	3
Action synthesize: Real time elapsed is 0h:1m:18s
Action synthesize: CPU time elapsed is 0h:0m:15s
Action synthesize: Process CPU time elapsed is 0h:0m:15s
Current time: Wed Oct 28 23:21:27 2026
Action synthesize: Peak memory pool usage is 994 MB

STAGE device_map: Errors=0 Warnings=0
Action dev_map: Real time elapsed is 0h:0m:15s
Action dev_map: CPU time elapsed is 0h:0m:3s
Action dev_map: Process CPU time elapsed is 0h:0m:3s
Current time: Wed Oct 28 23:21:42 2026
Action dev_map: Peak memory pool usage is 626 MB

STAGE place_route: Errors=0 Warnings=0
Action pnr: Real time elapsed is 0h:3m:32s
Action pnr: CPU time elapsed is 0h:0m:59s
Action pnr: Process CPU time elapsed is 0h:1m:13s
Current time: Wed Oct 28 23:25:14 2026
Action pnr: Peak memory pool usage is 3,281 MB

STAGE report_timing: Errors=0 Warnings=8
Timing-4087	5
Timing-4086	3
Action report_timing: Real time elapsed is 0h:0m:26s
Action report_timing: CPU time elapsed is 0h:0m:5s
Action report_timing: Process CPU time elapsed is 0h:0m:5s
Current time: Wed Oct 28 23:25:41 2026
Action report_timing: Peak memory pool usage is 1,967 MB

STAGE generate_bitstream: Errors=0 Warnings=0
C: Bitstream-2001: SCBV has not been set. Please set SCBV value based on PCB board, where is in configuration tab of bit stream options.
Action gen_bit_stream: Real time elapsed is 0h:0m:38s
Action gen_bit_stream: CPU time elapsed is 0h:0m:7s
Action gen_bit_stream: Process CPU time elapsed is 0h:0m:7s
Current time: Wed Oct 28 23:26:19 2026
Action gen_bit_stream: Peak memory pool usage is 2,590 MB
```

bitstream已成功生成；Bitstream-2001提示SCBV未设置，原文保留在generate_bitstream摘录中。没有为此修改配置。
各阶段warning、C级提示、耗时、峰值内存及高扇出表均已保存。常量传播Loop日志不能单凭该提示判定为RTL组合环。

## 串口工具一并上传

工具目录tools/serial-console-2：GUI入口main.py、同会话CLI、REST API、串口引擎、规则配置、说明、启动bat及已有截图一并提交。运行依赖PySide6和pyserial；本机PySide6 6.11.2、pyserial3.5。工具已实际启动并通过API读取本次会话，未运行压测或进行源码改造。
工具的文件发送是原始字节发送；本次没有验证它是否适配B1 bootloader下载协议。tuned UART下载仍按任务卡tools/board/uart_tool.py执行。

## 完整报告在Windows本地的路径

- PDS完整报告/原始日志：G:/codex_project/EdRV32-FPGA/EdRV32-B1/各阶段子目录。
- 补导STA及命令：G:/codex_project/EdRV32-Competition-2026/build/win/20261028-06-board-b1/exports/。
- 工具：G:/codex_project/EdRV32-Competition-2026/tools/serial-console-2/。

本次上传现有结果；采集期间用户又完成菜单3及第二次外设测试，已纳入。未补做5000次O2、tuned或按键测试，需要这些实测结果才能宣称任务卡全部通过。
