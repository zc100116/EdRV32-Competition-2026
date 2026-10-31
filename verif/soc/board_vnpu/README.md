# B3-10 board_vnpu 连线验收

基线：`3eb0a95`（含 `9277b37` DDR PHY 异步组修复）。本目录只有一个 smoke 用例，
复用 board_render/board_vision 的 IP 和器件原语模型，新增固定 150 MHz NPU PLL 模型。

直接例化 CPU/SYS/MEM 子系统、VIN、PIX、GEO、DISP、NPU、ETH；reset_ctrl 在 SYS 内。
板级直接例化 sys/video/NPU PLL、DDR IP/适配器、TMDS、RGMII，ETH PLL 在 RGMII 内。
VIN=P1/槽1/PLIC8，PIX=槽2/PLIC9，GEO=P5/槽3/PLIC10，DISP=P0/槽5/PLIC12，
NPU=P3/槽6/PLIC13，ETH=P6/槽7/PLIC14；CPU=P2，MEM_XBAR=槽8/PLIC15，槽9预留。
P3 的 AXI256 和槽6的 APB 均通过 NPU 内部 CDC（SoC 5.2 X9/X10），连线同 SoC 顶层。

## 未接入端口与依据

| 端口 → 接值 | 依据 |
|---|---|
| mem_subsys P4（RND）的 AWVALID/WVALID/ARVALID、AWID/AWADDR/AWLEN、WDATA/WSTRB/WLAST、ARID/ARADDR/ARLEN、BREADY/RREADY → 全 0；响应输出不接 | SoC 4.2、6.4.1，B3-10 裁剪契约；P4 没有 urgent 输入 |
| 媒体 APB 槽 4 → PRDATA=0、PREADY=1、PSLVERR=1 | SoC 6.1、sys-subsys 2.3，B3-10 已确认空槽约定 |
| 媒体 APB 预留槽 0/10–15 → PRDATA=0、PREADY=1、PSLVERR=1 | SoC 6.1 |
| PLIC 源 11 → 0 | SoC 6.1 中断源表，B3-10 裁剪契约 |
| GPIO 输入 [15:4]/[3:0] → 0/KEY[3:0]；LED → GPIO[8:4] | SoC 3.5，与 B2 相同 |
| 摄像头 PWDN 输出、其余 GPIO OE、CPU debug、未用复位/仿真状态输出 → 不引出 | SoC 3.5，与 B2 的板级引脚相同 |
| DDR APB 输入 → 全 0；dbg_ddrphy_rst_n → 1，其余诊断控制 → 0 | fpga/ip/ip_ddr3.md，与 B2 相同 |

## 时钟

| 时钟 | 来源 | 频率 / 用途 |
|---|---|---|
| `clk_i` | 板载晶振 | 27 MHz，sys/video/NPU PLL 输入 |
| `clk_sys_w` | `ip_pll_sys` | 100 MHz，CPU 和系统外设 |
| `ddr_ref_clk_w` | 差分参考输入经 GTP_INBUFDS | 125 MHz，DDR IP 输入 |
| `clk_mem_w` | `ip_ddr3.core_clk` | 125 MHz，DDR fabric、VIN/PIX/GEO、DISP/ETH 控制侧 |
| `clk_pix_w` | `ip_pll_video.clkout0` | 74.25 MHz，DISP 扫描和 TMDS 编码 |
| `clk_serial_w` | 同一 video PLL 的 clkout1 | 371.25 MHz，与像素时钟同相、5:1 |
| `cam0_pclk_i`、`cam1_pclk_i` | 两路摄像头 | 独立 DVP 时钟，FDC 各按 100 MHz 约束 |
| `rgmii_rxc_i` | PHY | 125 MHz，ETH PLL 输入 |
| `clk_eth_w` | `u_rgmii.u_pll_eth`，经 GTP_CLKBUFG | 125 MHz、30° 相移，MAC RX/TX 共用 |
| `rgmii_txc_o` | ODDR 和固定 IO 延迟 | 125 MHz，延迟 1 ns 的发送时钟 |
| `clk_npu_w` | `ip_pll_npu.clkout0` | 150 MHz，NPU 计算、DMA 和寄存器，接系统子系统 `clk_npu_i` |

复位：`rst_n_i & sys_lock & npu_lock & video_lock`，与 B2 相同；各域同步释放由
SYS 内 reset_ctrl 负责（SoC 5.3）。约束沿用 B2，含 rst_clk、phy_dq_clk_0/1 异步组。

FDC 共 17 个时钟定义：clk_board（27 MHz）、clk_ddr_ref（125 MHz）、clk_cam0/1
（各 100 MHz 约束）、clk_rgmii_ref（125 MHz）、clk_sys（100 MHz）、clk_npu（150 MHz）、
clk_pix（74.25 MHz）、clk_serial（371.25 MHz）、rst_clk/clk_mem（各 125 MHz）、
phy_dq_clk_0/1（各 1 GHz）、phy_dq_sysclk_0/1（各 125 MHz）、clk_eth（125 MHz，30°）、
clk_rgmii_tx（125 MHz，输出延迟 1 ns）。

## IP

需要 29 种 IP（不含 RND IP）：

- 板级：`ip_pll_sys`、`ip_pll_video`、`ip_pll_eth`、`ip_pll_npu`、`ip_ddr3`。
- CPU/SYS：`ip_ram_icache_tag`、`ip_ram_icache_data`、`ip_ram_dcache_tag`、
  `ip_ram_dcache_data`、`ip_mul_s33x33`、`ip_rom_boot`、`ip_ram_sram`。
- MEM：`ip_ram_mem_xbar_r`、`ip_ram_mem_xbar_w`。
- 图像通路：`ip_ram_vin_wfifo`、`ip_ram_pix_line`、`ip_ram_geo_src`、
  `ip_ram_disp_scan`（L0/L1 各一个）。
- NPU：`ip_ram_npu_line`、`ip_ram_npu_weight`、`ip_ram_npu_quant`、`ip_ram_npu_lut`、
  `ip_ram_npu_residual`、`ip_ram_npu_result`、`ip_ram_npu_scratch`、
  `ip_mul_npu_quant_low`、`ip_mul_npu_quant_high`；INT8 MAC 使用 APM 原语。
- ETH：`ip_ram_eth_buf`、`ip_ram_eth_fifo`。

TMDS/RGMII/差分参考使用器件原语，具体创建要求以 `fpga/ip/README.md` 为准。

## 验证命令与日志

```sh
. ~/.local/opt/edrv32/env.sh
python3 tools/check/verilog_style.py fpga/rtl/edrv32_fpga_board_vnpu_top.v
tclsh verif/soc/board_vnpu/check_import.tcl
python3 tools/regress.py smoke --path verif/soc/board_vnpu -j 1
```

板级顶层与行为模型 lint（未关闭任何命令行告警）：

```sh
python3 - <<'LINT'
from pathlib import Path
import subprocess
from tools.regress import expand_files
args = ['verilator', '--lint-only', '--timing', '-Wall', '+define+SIM_MODE',
        '--top-module', 'edrv32_fpga_board_vnpu_top']
args += expand_files(Path('verif/soc/board_vnpu/files.f'))
subprocess.run(args, check=True)
LINT
```

runner 另外对 `edrv32_board_vnpu_tb` 和其全部依赖运行同样的 `--lint-only --timing -Wall`。
日志为 `build/board_vnpu/{lint_top,lint,compile,simulation,software,bootloader}.log`；
回归入口日志为 `build/regress/smoke/soc/board_vnpu/verilator/run.log`。

软件后门加载 SRAM，真实 BIOS 后进入应用，检查 VIN/PIX/GEO/DISP/NPU/ETH 六个 ID、
对 RND 槽仅一次读触发 load access fault、GEO 64×4 RGB565 恒等变换，
经 PLIC10 到 CPU 后读取 DDR 非缓存别名并逐字比较 128 个 32 位字。
UART 加速沿用已确认的 Q4 BAUD_DIV=256 与 6.25 Mbaud peer，CLINT 启动窗口同 board_render。

2026-10-29，Verilator lint（顶层和 testbench 两个入口）均为 0 告警，两个 lint 日志均为空。
风格检查输出 `Style: 1 files, 0 warnings`。
导入脚本检查输出：

```text
edrv32: added 144 sources; top edrv32_fpga_board_vnpu_top; FPGA_MODE
PASS: all 144 imported RTL files and constraint exist
PASS: constraint Tcl syntax, 17 clock definitions
```

首次冷构建回归 `Summary: 1 PASS, 0 FAIL`，含编译共 104 s，实际仿真 15.19 s。
最终缓存构建回归输出：

```text
PASS board_vnpu simulation=15.09s: build/board_vnpu/simulation.log
PASS soc/board_vnpu [verilator] (build/regress/smoke/soc/board_vnpu/verilator) 27s
Summary: 1 PASS, 0 FAIL
```

最终回归运行于 `29bd9ff` 加本目录验证文件，实际仿真与缓存构建的总用时均小于 60 s。


实现提交：`e820742`（fpga）、`29bd9ff`（sw）；验证提交见本文件所在提交。


## 修改文件

- `fpga/rtl/edrv32_fpga_board_vnpu_top.v`
- `fpga/rtl/README.md`（B3-10 章节含全部端口表及相对 B2/board_vision 的差异）
- `fpga/constraints/edrv32_fpga_board_vnpu_top.fdc`
- `fpga/scripts/import_board_vnpu_top.tcl`
- `sw/tests/board_vnpu/{main.c,program.mk}`（由现有 Makefile 自动发现）
- `verif/soc/board_vnpu/{files.f,test.yaml,run.py,check_import.tcl,ip_pll_npu.sv,edrv32_board_vnpu_tb.sv,README.md}`

Linux 验收只覆盖连线，PDS 综合、时序和上板由协调者安排。
