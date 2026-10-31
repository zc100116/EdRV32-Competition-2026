# B3R/B3N ETH 与缓存/浅存储集成回归（T-BE1）

- 输入：`dc8856bf`（I$ 32 KiB、cache-spec v0.7；浅存储方案 B、mem-subsys v0.5、NPU v0.6）。
- 板级 RTL：`72c74ca2`；软件：`5d325211`；板级测试及本次构建：`5b94a47c`。
- 环境：用户提供的仿真主机（环境不记录）；风格/lint、导入模拟、五个上板软件构建在本机。
- 目标：PG2L200H-6/FBB676；本次未执行 PDS、实现时序或上板测试。
- 本机工具：Verilator 5.020、GCC 15.2.0；使用 `. ~/.local/opt/edrv32/env.sh`。

## 接线与软件范围

- B3R/B3N 增加 ETH P6 主口、APB 槽 7、PLIC14、reset_ctrl RX/TX 域复位和板级 RGMII/MDIO/MDC/PHY_RST。
- 时钟与 B3VN 一致：RGMII 内 `ip_pll_eth`，PHY RXC 125 MHz → 125 MHz/30°，MAC RX/TX 共用。
- B3R/B3N 需新增生成 `ip_pll_eth`、`ip_ram_eth_buf`、`ip_ram_eth_fifo`；SYS/VIDEO/NPU PLL 无需重新生成或新增输出。
- PLL 配置见 `fpga/ip/ip_pll_eth.md`；ETH PLL lock 不参与全局复位，PHY 复位仍由 PHY_CTRL 控制。
- FDC 复用 B3VN 的 ETH 引脚、时钟和与各已用域的异步组；SoC RTL 与规格未改。
- TB/软件 ETH 覆盖与 board_vnpu 相同：空闲 RGMII 接口加 CPU 读取 ETH ID，不新增网络流量测试。
- 检索：`rg -n -i 'ETH|网口|B3R|B3N|board_render|board_npu' sw tools/debug_tool`。
- 修改 sw：`tests/board_render/{main.c,program.mk}`、`tests/board_npu_smoke/{main.c,README.md}`，
  `tests/{board_npu,rnd_board}/README.md`、`apps/{s3,nes}/README.md`；前两项补 ETH ID，其余更新板型说明。
- `sw/drivers/engine.c` 与 `sw/drivers/include/engine.h` 已含 ETH，未发现按 B3R/B3N 裁剪的引擎表；BIOS 无引擎探测/板型菜单。
- 检索发现 `tools/debug_tool/{core/session.py,gui/soc_console.py,tests/test_session.py,README.md}` 仍将 B3R 标为无网口。
- 经 ask，协调者限定本任务不改调试工具，不给 s3/nes/rnd_board/board_npu 加网络初始化；软件另派任务。
- 现有 B3R/B3N 软件没有 ETH peer/WIN3/EDTM 路径；demo 依赖被裁剪的媒体引擎，不能作为这两板的连通程序。
- 后续复用约定：`sw/apps/demo/{network.c,monitor.c}` 与 `tools/debug_tool` 的建立网口连接/DDR EDTM；本任务未新写协议。

## 验证结果

- 风格：`python3 tools/check/verilog_style.py rtl fpga/rtl`：188 文件、0 告警。
- Lint：`flock /tmp/edrv32-sim.lock verilator --lint-only --timing -Wall -j 1 +define+SIM_MODE --top-module <top> <sources>`。
- top 为 board_render/board_npu/board_vnpu/board_b2（全名 `edrv32_fpga_<top>_top`）及 `edrv32_soc_top`：均 0 告警。
- sources 按 `tools.regress.expand_files` 展开各板 `files.f`；B2 用 vnpu 模型列表并补齐 `rtl/filelists/soc.f` 和 B2 顶层。
- 本机 Verilator/regress 全部加 `flock /tmp/edrv32-sim.lock`；全部编译 `-j 1`。
- 回归入口：`python3 tools/regress.py smoke --path verif/<下列目录> -j 1`；无 smoke 的项目使用 full。
- SoC：board_render、board_npu、board_vnpu 各 1 PASS；sc_06_eth_rx（full）1 PASS。
- 浅存储：unit/mem_xbar（Verilator/Icarus）2 PASS；block/mem_subsys 17 PASS。
- NPU：unit/npu_activation_lut、npu_quant_param_store、npu_residual_buffer、npu_writeback、npu_datapath、npu_conv、npu_top，共 9 PASS（含两目录双仿真器）；block/npu 22 PASS。
- Cache：unit/cache_icache、unit/cache_ram、block/cache：协调者暂缓，待 cache 容量定稿后由后续任务运行。
- CPU：block/cpu smoke 与逐 arch-* 目录 full：协调者暂缓，待 cache 容量定稿后由后续任务运行（T-IC1 同一范围）。
- 主机不可用于 mem_xbar、npu_activation_lut、npu_quant_param_store 的 Icarus 检查；三目录改在本机跑完整 smoke。
- 调试归因：首次新 TB 拼接误带 TMDS 连接，已修正；曾用 smoke 选 full-only 的 SC-06，改为 full 后执行。
- 导入：在 `build/board-eth/import/` 建 EdRV32-FPGA/P 和指回仓库的 EdRV32-Competition-2026 符号链接，
  进入 P 后执行 render/vnpu 的 `check_import.tcl`；npu 的 checker 自建同样布局；三项全部 PASS。
- B3R/B3N/B3VN：源文件数 98/106/145，IP 种数 18/24/29，时钟定义 14/13/17；Tcl mocks 不替代 PDS。

## 卡 21 软件

- 构建 commit：`5b94a47c`；命令 `make -C sw PROGRAM=<程序> -j 1`，NES 另加 `MEMORY=ddr_app`。
- B3R：`build/sw/s3/s3.elf`、`build/sw/nes/nes.elf`、`build/sw/rnd_board/rnd_board.elf`：全部构建成功、0 warning。
- B3N：`build/sw/board_npu/board_npu.elf`；B3VN：`build/sw/demo_vnpu/demo_vnpu.elf`：全部构建成功、0 warning。
- board_npu 数据复用 `../b3-int/build/sw/board_npu/data/`（复制到本工作区同一相对输出目录），未重新标定 YOLO。
- 本次获准范围合计 54 PASS、0 FAIL；主机运行进程和临时目录已清理。
- 本机证据：`build/board-eth/{style,lint-*,import,build-*}.log`；远端只记录本人汇总结果，不回传原始文件。
- 待办：cache/CPU 回归暂缓；Windows 新增 IP/PDS/上板验收及另派 ETH 连通软件任务。
