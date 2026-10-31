# T-RST2 区域复位副本（2026-10-31）
基线 `506f07e4`；实现为本报告所在提交。Yosys 0.70+219（5053d0e26），FPGA_MODE、SoC 默认参数，PG2L200H-6 通用参考，无器件时序映射。
沿用 T-RST1 的 `$adff/$adffe` Q 位负载口径，硬 IP 内部及同步复位不计；同一 Q 位只计一次。Yosys 忽略 synthesis 注释，统计时对复位副本驱动单元设置 keep，避免副本合并；此设置仅用于统计，不写入 RTL。
下表名字均带 `u_reset_` 前缀；花括号展开为独立实例。共 41 份，每路同域恰好一级、同拍释放；所有副本负载 ≤1000。
| 子系统 | 副本名字：区域、负载位数 |
|---|---|
| CPU | sys_core_n：流水/前端131；sys_csr_n：CSR900；sys_direction{0,1}_n：方向表各512；sys_icache_n：I$控制43；sys_ivalid{0,1}_n：有效位各512；sys_ilru_n：LRU512；sys_dcache_n：D$628；sys_cache_ctrl_n：维护94 |
| SYS | sys_bus_n：总线/APB/UART/I2C/PLIC430；sys_periph_n：GPIO/CLINT701；mem_core_bus_n：媒体APB16；POR直连保留 |
| MEM | sys_gateway_n：网关sys47；mem_core_ctrl_n：网关mem/调度/队列815；mem_regs_n：全局寄存器433；mem_stat{0,1,2,3,4,5,6}_n：各端口统计/快照各428 |
| VIN | mem_ctrl_n：通道/格式化/内存源883（直接45+soft-clear派生838）；mem_regs_n：寄存器976（soft-clear派生）；cam{0,1}_front_n：摄像头域各32 |
| PIX | mem_ctrl_n：全部mem301 |
| GEO | mem_ctrl_n：全部mem488 |
| RND | mem_ctrl_n：全部mem958 |
| DISP | mem_ctrl_n：读引擎/DMA/CDC665；mem_regs_n：寄存器908；pix_scan_n：扫描/TMDS/CDC780 |
| NPU | npu_conv_n：卷积779；npu_ctrl_n：顶层/非卷积/DMA/寄存器/桥794；mem_bridge_n：跨域桥93 |
| ETH | mem_ctrl_n：收发/DMA/MDIO381；mem_regs_n：配置/状态821；mem_perf_n：统计352；eth_rx_front_n：RX43；eth_tx_front_n：TX72 |
删除数据通路复位：PIX `frame_cfg_r/frame_contrast_r/frame_bias_r/frame_thresh_r`（46位）及两级 filter `width_r`（各10位），共66位；SOF捕获配置，首行EOL捕获宽度，之后valid/flush才消费。
DISP reader `layer_ctrl_r/l1_y_end_r/l1_beats_r/l0_beats_r/l0_limit_r/l1_limit_r` 共46位：IDLE接受frame_start时覆写，LOAD/INIT后使用。
RND affine `initial_mask_r` 16位：start覆写后才进入X/Y移位；合计128位。T-RST1“明确排除”各项均保留。
每路最大复位网络负载（改前→改后，包含各路副本及派生复位）：sys 5534→900；mem_core 4274→815；mem 5141→976；npu 1570→794；pix 780→780；cam0/cam1各32→32；eth_rx 43→43；eth_tx 72→72；sys_por 83→83。
SoC LUT6/FF（改前/改后）：未取得/未取得；全展开映射被 SIGKILL，协调者确认停止映射，资源以上板卡 PDS 报告为准。原始统计在 `build/reset_copies/{before,final}/{start.ys,coarse.json,finish.ys,loads.json}`。
复现负载：从 T-RST1 报告提取原脚本，基线替换为本次基线；改后改用当前RTL，并在opt前保留副本驱动。由loads.json按ARST网络累加Q位，VIN将派生ARST归入其上游副本。
```sh
. ~/.local/opt/edrv32/env.sh
mkdir -p build/reset_copies
python3 - <<'PY'
from pathlib import Path
s = Path('docs/reports/2026-10-31-resource-reset-fanout.md').read_text().split('```sh\n')[1].split('\n```')[0].replace('d06e32d6', '506f07e4')
Path('build/reset_copies/before.sh').write_text(s)
s = s.replace('git archive 506f07e4 rtl tools/synth | tar -x -C build/reset_fanout/baseline', 'cp -a rtl tools build/reset_fanout/baseline/')
s = s.replace('proc\\nflatten\\nopt', 'proc\\nflatten\\nselect -set preserved w:*reset*.rst_n_o %ci\\nsetattr -set keep 1 @preserved\\nselect *\\nopt')
Path('build/reset_copies/after.sh').write_text(s)
PY
bash build/reset_copies/before.sh
bash build/reset_copies/after.sh
```
检查复现：`python3 tools/check/verilog_style.py rtl/`；展开soc.f/四板files.f后执行`verilator --lint-only --timing -Wall -DSIM_MODE --top-module <top>`（仅soc加`-Wno-MODDUP`）；均0告警。
四板导入复现：`for b in render npu vision vnpu; do tclsh verif/soc/board_${b}/check_import.tcl; done`；102/105/111/144源文件全部PASS；日志在 `build/reset_copies/`。
