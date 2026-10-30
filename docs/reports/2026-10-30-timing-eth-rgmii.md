# ETH RGMII 收发 IO 流水测量（Task E-F1）

- 基线 commit：`8977d1f43484942b32319d4e7046dbf9f673f219`。
- 实现 commit：`856db6354ac92d34cf4f09c1632729141007cc39`。
- 工具：Yosys 0.70+219（5053d0e26），Verilator 5.020，Linux。
- 目标器件：PG2L200H；本次是通用 LUT6 参考综合，没有器件速度等级和物理延迟模型。
  clk_eth 目标周期 8 ns；Yosys 不做时钟约束或 PDS 时序签核。
- PDS 比较来源：`origin/win/20261029-07-b3-rerun` 的
  `tasks/win/20261029-07-b3-rerun/artifacts/B3V/setup_top200_clk_eth.txt`。

## 修改与可见延迟

`fpga/rtl/edrv32_fpga_rgmii.v` 在 IDDR 输出后、ODDR 输入前各增加一拍普通寄存器；
RX 的数据/DV/ER 与 TX 的数据/EN/ER 分别对齐，数据和控制分开写，无新增复位或顶层端口。
B2、vision、vnpu 都例化同一个适配器，自动获得修改。

`rtl/eth/edrv32_eth_tx_front.v` 的 `done_o` 同步延后一拍，使其与 ODDR 输入处最后一个
FCS 字节保持原有关系；clk_mem 的发送完成时刻相应晚一拍 clk_eth 加 CDC 采样相位。
这项配套修改及适配器内无复位采样均已由协调者通过 E-F1 的 ask 明确批准。
ODDR、TXC 产生和固定 IO 延迟均未修改。

## Yosys 级数

重现命令（仓库根目录）：

```sh
. ~/.local/opt/edrv32/env.sh
python3 verif/unit/eth_rgmii/timing.py 8977d1f43484942b32319d4e7046dbf9f673f219
```

测量夹具连接实际 RGMII、RX/TX 前端和两个 ETH FIFO，RAM 与厂商 IO 原语作为黑盒。
综合使用 `synth -flatten -noabc`、`abc -lut 6 -dress`，通过已有
`tools/synth/netlist_paths.py` 按起终点筛选组合路径；寄存器/黑盒构成边界，不跨流水级累计。
适配器 IO 黑盒类型仅在分析内存中加 `ip_` 前缀供已有分析器识别，综合 JSON 保持原样。

| 路径类别 | 改前最长 LUT6 级数 | 改后原起终点直连 | 改后对应分段最长级数 |
|---|---:|---|---|
| RX IDDR → FIFO RAM 写数据 | 1 | 无可达组合路径 | IDDR → RX 寄存器 0（数据/DV）或 1（ER）；RX 寄存器 → RAM 1 |
| TX FIFO RAM 读数据 → ODDR 输入 | 3 | 无可达组合路径 | RAM → TX 寄存器 2；TX 寄存器 → ODDR 0 |
| RX IDDR → `frame_r` | 2 | 无可达组合路径 | IDDR → RX 寄存器最多 1；RX 寄存器 → `frame_r` 3 |
| RX IDDR → `crc_r` | 2 | 无可达组合路径 | IDDR → RX 寄存器最多 1；RX 寄存器 → `crc_r` 3 |

原来的 IO↔FIFO 长连线已被寄存器切断；最靠近 IO 的组合段从 RX 最多 2 级降至最多 1 级，
TX 从 3 级降至 0 级。全部新分段均满足 DRM 起点不超过 6 级、其他起点不超过 8 级。
RX 前端内部余段由 2 级变成 3 级是此次通用 LUT6 重新映射的实测结果，
没有把断开的组合路径记作“0 级”，也没有声称整体最大组合深度全面降低。

原 PDS slow 角的三类关键路径分别为 +0.798 ns/1 级、+1.262 ns/1 级、
+1.569 ns/2 级；本次未运行 PDS，不能据 Yosys 级数推算修改后的裕量。
布局位置、IO 到新增 FF 及 FF 到 DRM 的实际布线延迟仍由后续 PDS 确认。

原始生成物在 `build/eth_timing/{before,after}/`：`synth.ys`、`synth.log`、
`netlist.json`、`summary.json` 和各路径类别的 JSON。
`build/eth_timing/timing.log` 为合并摘要；这些生成物不入库，可用上述命令重建。

## 验证命令与结果

所有回归使用 `-j 1`，未使用 `--parallel`，同一时刻仅运行一个仿真。
下表耗时包含编译及仿真，是本次共享主机环境下的墙钟时间。

```sh
. ~/.local/opt/edrv32/env.sh
python3 tools/check/verilog_style.py fpga/rtl/edrv32_fpga_rgmii.v rtl/eth/edrv32_eth_tx_front.v
tools/check/lint.sh --top-module edrv32_eth_tx_front \
    rtl/eth/edrv32_eth_tx_front.v rtl/eth/edrv32_eth_crc.v
python3 tools/regress.py smoke --path verif/unit/eth_rgmii -j 1
```

RGMII 单元及板级 runner 均使用 Verilator `-Wall`；单元沿用现有测试的
`-Wno-TIMESCALEMOD -Wno-BLKSEQ -Wno-SYNCASYNCNET`。适配器单独 lint 的源文件与
`verif/unit/eth_rgmii/files.f` 相同，命令为：

```sh
python3 - <<'PYCODE'
from pathlib import Path
import subprocess
from tools.regress import expand_files
subprocess.run(['verilator', '--lint-only', '--timing', '-Wall', '-Wno-TIMESCALEMOD',
                '-Wno-BLKSEQ', '-Wno-SYNCASYNCNET', '+define+SIM_MODE', '--top-module', 'tb',
                *expand_files(Path('verif/unit/eth_rgmii/files.f'))], check=True)
PYCODE
```

风格检查 0 告警（0.37 s），TX 前端 lint 0 告警（0.35 s），
RGMII 独立 lint 0 告警（0.95 s），参考综合加路径分析耗时 17.96 s。
RGMII 新增测试首次冷构建 smoke PASS（145 s），最终提交上增量运行 PASS（25.92 s）。

`eth_rgmii` 用例遍历 256 种数据及 EN/ER、DV/ER 组合，检查每个周期的单拍延迟、
两边沿数据/控制编码和 TXC 电平；另发送 60 字节帧，用独立的 MSB-first CRC 模型
检查 72 个前导码/数据/FCS 字节，并逐拍检查最后一个 FCS 字节在 ODDR 输入端时
`done_o` 同时有效。

板级测试例化真实共享 RGMII 适配器及 DDR IO 模型；其 RX 引脚激励为空闲，
验证完整板级启动、总线和连线。动态以太网字节/控制/帧尾对齐由上述新单元用例覆盖。

| 命令 | 结果 | 墙钟耗时 |
|---|---|---:|
| `python3 tools/regress.py smoke --path verif/unit/eth_rgmii -j 1` | PASS | 25.92 s |
| `python3 tools/regress.py full --path verif/unit/eth_crc -j 1` | PASS | 85.93 s |
| `python3 tools/regress.py full --path verif/unit/eth_mdio -j 1` | PASS | 61.19 s |
| `python3 tools/regress.py full --path verif/unit/eth_priority -j 1` | PASS | 143.15 s |
| `python3 tools/regress.py full --path verif/unit/eth_regs -j 1` | PASS | 73.97 s |
| `python3 tools/regress.py full --path verif/unit/eth_rx -j 1` | PASS | 112.10 s |
| `python3 tools/regress.py full --path verif/unit/eth_rx_write -j 1` | PASS | 29.35 s |
| `python3 tools/regress.py full --path verif/unit/eth_tx -j 1` | 2 PASS | 73.43 s |
| `python3 verif/soc/board_vision/run.py` | PASS（增量构建） | 40.08 s |
| `python3 verif/soc/board_vnpu/run.py` | PASS（完整构建） | 295.55 s |

共 9 个单元用例（含 TX fast）和 2 个板级用例取得 PASS。

首次 `python3 tools/regress.py full --path verif/soc/board_vision -j 1`
在总墙钟 300 s 时被 `test.yaml` 的外层超时终止，统一入口记录 FAIL；
当时构建已经完成，子仿真随后也输出 PASS。随后明确改用未修改的现有
`python3 verif/soc/board_vision/run.py` 重新完整执行（增量构建），退出码 0，
仿真本身 25.40 s。没有修改回归时限或屏蔽失败。vnpu 直接 runner 的仿真本身耗时 27.51 s；
两套板级独立 lint 的日志均为空（0 告警）。

单元原始日志在 `build/regress/full/unit/eth_*/verilator/`，
新增 RGMII 用例在 `build/regress/smoke/unit/eth_rgmii/verilator/`，
ARP 优先级 runner 的构建/用例日志在 `build/media-r3/eth_priority/`；
板级 lint/构建/仿真日志分别在 `build/board_vision/` 和 `build/board_vnpu/`。
命令汇总与墙钟数据在 `build/eth_timing/*.regress.log`、`regression.json`、
`board_*.direct.log`、`board_*.direct.time`。
