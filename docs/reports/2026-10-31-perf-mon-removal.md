# PERF_MON / P6 仲裁删除验收

- 改前：`b86d99b6919098bdf9ea653420899bb60d11cb46`；改后：本报告所在提交（`git rev-parse HEAD`）。
- 依据：SoC v0.19、mem-subsys v0.6、mem-subsys-testplan v0.5、设计方案 A。
- 删除：`rtl/mem/edrv32_mem_{perf_mon,p6_arb}.v`、寄存器 JSON/两种生成头、驱动 C/H、两个单元测试目录。
- 删除：MB 的 `pm_01`–`pm_07`、`p6_01`、三个观察 include、相关覆盖项；新增 `bw_01`。
- 连线：ETH 直接接 xbar P6，保留 ETH 本地 ID；SoC/板级媒体 APB 槽 9 预留，CPU 访问返回 SLVERR。
- 同步：地址映射/寄存器生成物、文件列表、约束、驱动引擎表、demo、LVGL 配置、遥测端口名称、说明文档。

| mock 导入 | 改前实数 | 改后实数 |
|---|---:|---:|
| render | 104 | 102 |
| npu | 107 | 105 |
| vision | 113 | 111 |
| vnpu | 146 | 144 |

- 命令：`for b in render npu vision vnpu; do tclsh verif/soc/board_$b/check_import.tcl; done`；四项 PASS。
- Yosys 0.70+219 (`5053d0e26`)，generic LUT6 参考；`SIM_MODE`、RAM 展开为 FF、无器件/速度级/时序约束。
- 综合命令：在 `rtl/filelists` 执行 `files=$(sed '/^+/d' mem_subsys.f | tr '\n' ' '); yosys -p "read_verilog -D SIM_MODE -I../include $files; synth -top edrv32_mem_subsys -flatten -noabc; abc -lut 6; opt_clean; stat"`。

| mem_subsys | 改前 | 改后 | 差值 |
|---|---:|---:|---:|
| LUT6（`$lut`） | 72414 | 62121 | -10293 |
| FF（全部 DFF 类单元） | 74223 | 71219 | -3004 |

- 综合日志：`build/pmrm/synth-{before,after}/mem.log`；此为统一条件逻辑参考，不是 PG2L200H 的 DRM/APM 映射结果。
- Verilator 5.020：MEM、完整 SoC、render/npu/vision/vnpu/imgtest 顶层 `--lint-only --timing -Wall` 全部 0 告警；风格检查 191 文件、0 告警。
- 扫描：`grep -rn 'perf_mon\|PERF_MON\|p6_arb' rtl fpga sw tools verif` 无结果。
- 回归：MEM smoke 14、BW-01 1、mem_xbar 2（双仿真器）、eth_* 8、四板级 smoke 4、sc_bios_eth/sc_06_eth_rx 各 1，共 31 PASS、0 FAIL。
- smoke 命令：`for d in verif/block/mem_subsys verif/unit/mem_xbar verif/unit/eth_* verif/soc/board_{render,npu,vision,vnpu}; do python3 tools/regress.py smoke --path "$d" -j 1; done`。
- full 命令：`for d in verif/block/mem_subsys/bw_01 verif/soc/sc_bios_eth verif/soc/sc_06_eth_rx; do python3 tools/regress.py full --path "$d" -j 1; done`。
- BW-01：P0 同行顺序读，65536 拍 / 69650 周期 = 94.093%，超过 90%；含默认刷新停顿与启动/排空。
- 软件：s3；nes（`MEMORY=ddr_app`）；board_npu；demo/demo_vision/demo_vnpu（`MEMORY=sram`）；rnd_board；eth_diag 全部构建 PASS、0 warning。
- 附加软件：regs_check、drivers_build 交叉构建和驱动 host test PASS。
- 工具：debug_tool 86、board 13、NPU 12+12+11+17、CPU eval 52、synth 13，共 216 项 PASS。
- 工具命令：`for d in tools/{debug_tool/tests,board/tests,npu,npu/tests,npu/eval,npu/ref,cpu/eval,synth}; do QT_QPA_PLATFORM=offscreen ~/.local/opt/edrv32-py/bin/python -m unittest discover -s "$d" -p 'test_*.py'; done`。
- 软件/工具/lint/mock 原始日志：`build/pmrm/`；回归汇总为 `build/pmrm/regression-summary.txt`，复现日志由 `tools/regress.py` 写入 `build/regress/`。
