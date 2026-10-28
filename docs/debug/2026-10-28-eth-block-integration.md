# ETH 模块级联调（V-I4）

## 范围和复现基线

- 基线：`647650b`（包含 RTL `ec3d2af` 和独立模块验证环境）。
- 最终测试修复提交：`511bda8`，RTL 保持 `ec3d2af` 的实现。
- 规格：`docs/spec/eth-spec.md` v0.1（含全部澄清）；方案：`docs/testplan/eth-testplan.md` v0.1。
- 环境：Linux，Verilator 5.020；先执行 `. ~/.local/opt/edrv32/env.sh`。
- 所有回归使用 `-j 1`，无并行仿真。
- 协调者更正：Makefile 没有 perf 目标，使用
  `python3 tools/regress.py perf -j 1 --path verif/block/eth`，不修改 Makefile。

## 失败定性和修复

| 失败 | 定性及条款 | 根因和修复 | 保留检查 |
|---|---|---|---|
| 模块 TB 编译：VARHIDDEN | 测试环境问题，CLAUDE.md 7 要求 lint 无告警 | memory_file 的 foreach 隐式索引与外层 address 同名；索引改名 written_address | `-Wall` 编译 |
| 模块 TB 编译：SYNCASYNCNET | 测试环境集成告警；DUT 异步复位，存储/peer 模型同步采样复位 | 在 lint.vlt 对 TB 文件的该项告警作定点豁免，说明两端复位语义；不改变 DUT 和模型行为 | 其余 `-Wall` 告警仍为错误 |
| ET-10-overflow：PERF9 期望非零，实际 0 | 测试错误，eth 4.3：PERF9 只从 DOORBELL 起计；本场景仅接收 | 共用 E 操作误把 TX 非零周期要求施加在 RX；E 参数标明是否发起过发送，RX-only 检查为 0，TX 保留非零和停止检查 | ET-10-overflow E，所有发送场景 E |

## 验收结果

模块级回归（最终测试提交 `511bda8`，退出码均为 0）：

| 命令 | PASS / FAIL | 场景 |
|---|---|---|
| `make smoke REGRESS_ARGS='-j 1 --path verif/block/eth'` | 2 / 0 | selftest，ET-01–13 共 22 个子场景 |
| `make full REGRESS_ARGS='-j 1 --path verif/block/eth'` | 3 / 0 | ET-15 种子 0–9 各 200 帧，selftest，全部定向场景 |
| `python3 tools/regress.py perf -j 1 --path verif/block/eth` | 1 / 0 | ET-14 三个子场景 |

ET-14 的存储模型 R/B 延迟固定 40 个 clk_mem 周期、无反压；三个时钟异步相位，
RX +100 ppm、TX −100 ppm。均逐字节比对数据，RX 检查全部包数、字节数和丢弃计数。

| 测量 | 字节数 | 时间 | 实测 | 规格 |
|---|---|---|---|---|
| 连续接收 | 2,097,152 | 17,992,624 ns | 116.556207 MB/s | ≥ 100 MB/s、无丢包 |
| 接收空闲时发送 | 1,048,576 | 9,006,920 ns | 116.418931 MB/s | ≥ 100 MB/s |
| 发送期间 ARP 应答 | — | 104.010400 ns | 0.1040104 µs | ≤ 10 µs |

吞吐 = 数据字节数 × 1000 / 仿真 ns（十进制 MB/s）。ARP 从请求帧结束与当时
正在发送的 UDP 帧结束两者中较晚时刻，量到应答帧开始；TB 现输出原有判定使用的实测值。

单元逐目录回归（每条命令退出码均为 0）：

| 目录 | smoke PASS / FAIL（耗时） | full PASS / FAIL（耗时） |
|---|---|---|
| `verif/unit/eth_crc` | 1 / 0（10 s） | 1 / 0（12 s） |
| `verif/unit/eth_mdio` | 1 / 0（9 s） | 1 / 0（10 s） |
| `verif/unit/eth_regs` | 1 / 0（12 s） | 1 / 0（11 s） |
| `verif/unit/eth_rx` | 1 / 0（29 s） | 1 / 0（28 s） |
| `verif/unit/eth_rx_write` | 1 / 0（13 s） | 1 / 0（12 s） |
| `verif/unit/eth_tx` | 1 / 0（12 s） | 2 / 0（fast 和常规各 12 s） |

逐条命令的可复现批次（实际输出逐条记录在 units 汇总日志）：

```sh
for name in crc mdio regs rx rx_write tx; do
    make smoke REGRESS_ARGS="-j 1 --path verif/unit/eth_${name}"
    make full REGRESS_ARGS="-j 1 --path verif/unit/eth_${name}"
done
```

smoke 时限：模块目录含重编译的通过轮次为 36 s，selftest 含构建轮次最大 20 s；
最终提交复跑模块目录为 33 s、selftest 为 0 s（缓存）；
单元目录最大 29 s，均未超过约 60 s，没有需要移到 full 的目录。

## 日志和检查命令

- 汇总：`build/eth-integration-{smoke,full,perf,units}.log`。
- 模块子场景及性能原始数据：
  `build/regress/{smoke,full}/block/eth/verilator/run.log`、
  `build/regress/full/block/eth/full/verilator/run.log`、
  `build/regress/perf/block/eth/perf/verilator/run.log`。
- 单元原始编译/运行日志：`build/regress/{smoke,full}/unit/eth_*/verilator/`。
- `python3 tools/check/verilog_style.py rtl/eth/`：10 文件，0 告警。
- `python3 verif/block/eth/check_style.py`：8 SV/SVH 文件，0 告警。
- RTL 和模块 TB 的 Verilator lint 均 0 告警，准确命令如下：

```sh
. ~/.local/opt/edrv32/env.sh
python3 - <<'PYLINT'
from pathlib import Path
import subprocess
import sys
sys.path.insert(0, 'tools')
from regress import expand_files
for top, filelist, timing in [
    ('edrv32_eth', 'rtl/filelists/eth.f', []),
    ('edrv32_eth_tb', 'verif/block/eth/files.f', ['--timing']),
]:
    subprocess.run(['verilator', '--lint-only', '-Wall', '+define+SIM_MODE',
                    '--top-module', top, *timing,
                    *expand_files(Path(filelist))], check=True)
PYLINT
```

没有发现 RTL 规格违例或需要协调者决定的规格歧义，未修改 RTL、规格和验证方案。
所有问题定位均少于半小时，未触发另写单问题长调试记录的条件。

