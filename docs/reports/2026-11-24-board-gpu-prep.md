# GPU SoC 板级准备（T-1b，2026-11-24）
- 代码版本：本报告所属提交；`git log -1 --format=%H -- fpga/rtl/edrv32_fpga_board_gpu_top.v`。
- 器件：PG2L200H-6 FBB676；本机 Verilator 5.020、Python 3.12、Tcl 8.6；未运行 PDS。
- 新顶层例化 `edrv32_gpu_soc_top`；复用原 DDR 适配器、TMDS、RGMII，视觉文件未改；115 个端口/位均绑定唯一管脚；I2C0 端口 1 输入接高、输出不引出，GPIO12–15 不引出。

## PLL 与时序预算

- 系统 125 MHz；DDR core 125 MHz；视频 74.25/371.25 MHz；ETH RX/TX 同用 125 MHz。
- 新建 `ip_pll_gpu`：27 MHz → 180 MHz；新建 `ip_pll_aud`：27 MHz → 12.288 MHz 目标；GPU 替换 NPU PLL，AUD 独立：相对 full 工程净增 1 个 PLL；不改变现有 PLL 端口契约。
- 协调者 2026-11-24 答复：缺 PLL 手册，取消穷举/最优误差证明；PDS“计算分频”决定配置，Windows 回传 VCO、分频和实际频率。
- 音频验收 `ppm=(实际MHz/12.288-1)*1000000`，`|ppm|≤1000`；超出交协调者处理。
- 对应采样率 47952–48048 Hz、约 ±1.73 音分；MCLK/BCLK/LRCK 同源，ES8156 作从机；误差按比例改变音高/播放时长，不产生时钟失配丢样；软件仍需按 FIFO 水位及时补充。
- FDC 音频比率 512/1125 仅表示目标频率；实际值回传后同步修改，才进行 G-T1 测量。
- 核心频率不放宽，setup uncertainty 0.4 ns 留布线余量；GPU 最终频率由 G-T1 定稿。DDR PHY 原有厂商多周期、0.4 ns uncertainty、位置/区域约束保留；未新增宽松多周期。

## gpu-soc-spec 5.2 对照

| 条目 | 已覆盖的跨域与例外 |
|---|---|
| X1 | sys→mem 媒体 APB；sys/mem 异步组 |
| X2 | sys↔mem DDR AXI64；同上 |
| X3 | mem、gpu→sys 中断电平同步；sys/mem、sys/gpu 异步组 |
| X4 | 删除摄像头端口、时钟、引脚与例外 |
| X5 | mem→pix L0/L1 FIFO、扫描使能、停止/配置握手；mem/video 异步组 |
| X6 | pix→mem 帧握手、scan_live、欠载脉冲、Gray 计数；同上 |
| X7 | eth↔mem 帧 FIFO、eth→mem 发送完成脉冲；mem/eth 异步组 |
| X8 | 外部复位 false path；mem_ready 从 mem 到各域由异步组覆盖，SoC 同步释放 |
| X9 | gpu↔mem AXI256（P3）；mem/gpu 异步组 |
| X10 | mem→gpu APB（槽 6）；同上 |
| X11 样本/使能 | mem→aud 样本 FIFO、使能电平同步；mem/aud 异步组 |
| X11 欠载 | aud→mem cdc_pulse；同上 |
| X11 读计数 | aud→mem cdc_gray_cnt；同上 |

六组 SoC 时钟两两异步，pix/serial、aud/MCLK、eth/转发 TX 各保留组内时序关系。
协调者允许例外：保留 full 已上板的厂商 `i_dqs_bank[0/1]` PHY 固定层次；禁止我方 `g_*` 引用。

## J25 / PMOD-D 引脚（全部 LVCMOS33 / 3.3 V）

| PMOD 脚 | 端口（aud_dac_ 前缀） | FPGA | 方向 |
|---|---|---|---|
| 3 | i2c_sda_o | V17 | 开漏双向 |
| 4 | i2c_scl_o | V16 | 开漏双向 |
| 5 | mclk_o | V21 | 输出 |
| 6 | bclk_o | U21 | 输出 |
| 7 | sdata_o | W24 | 输出 |
| 8 | lrck_o | V24 | 输出 |

AA22/AA23、U16/U15 不分配；其余 DDR/HDMI/RGMII/UART/按键/LED 管脚逐位继承 full。

## Windows IP 与本机检查

- PLL：`ip_pll_sys`、`ip_pll_video`、`ip_pll_eth`、新建 `ip_pll_gpu`/`ip_pll_aud`；DDR：`ip_ddr3`，均按 `fpga/ip/` 同名说明生成。
- CPU：`ip_ram_icache_tag/data`、`ip_ram_dcache_tag/data`、`ip_ram_sram`、`ip_rom_boot`、`ip_mul_s33x33`、`ip_lutram_cpu_btb/direction/local_history/tournament`（斜线表示各独立 IP）。
- MEM/DISP/ETH/AUD：`ip_ram_mem_xbar_r`、`ip_lutram_mem_xbar_w`、`ip_ram_disp_scan`、`ip_ram_eth_buf/fifo`、`ip_ram_aud_fifo`。
- GPU：`ip_lutram_gpu_palette_current/read_pool/write_pool`、`ip_ram_gpu_palette_segment/resolve_line/target_segment/target_tail/texture_segment`、`ip_rom_gpu_recip_p18/q30`；器件原语不需生成。
- Lint：`. ~/.local/opt/edrv32/env.sh; verilator --lint-only -Wall -DFPGA_MODE --top-module edrv32_fpga_board_gpu_top -f build/board_gpu/sources.f build/board_gpu/ip_stubs.v`，141 RTL 文件、0 告警；空壳仅 build，不入库。
- 风格：`python3 tools/check/verilog_style.py $(sed '1d' build/board_gpu/sources.f)`，141 文件、0 告警；日志 `build/board_gpu/{lint,style}.log`。
- Tcl：`tclsh build/board_gpu/check_tcl.tcl`，导入顺序与 gpu_soc.f 展开后 141 源一致、FDC Tcl 语法 PASS；PDS 命令以空过程验证语法，未验证布局布线。
- 层次：`rg -n 'g_[A-Za-z0-9_]+(\[[^]]+\])?[./]' fpga/constraints/edrv32_fpga_board_gpu_top.fdc fpga/scripts/import_board_gpu_top.tcl`，0 匹配（退出码 1）。
- 剩余：Windows 生成 IP、回传分频与实际音频 ppm；G-T1 检查全部域时序、PLL 总量和布线余量。
