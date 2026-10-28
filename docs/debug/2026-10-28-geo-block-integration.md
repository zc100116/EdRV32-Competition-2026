# GEO 模块联调（V-I3）

## 1. 现象

输入提交 `92b340b`（包含 RTL `7ac1a35`），依据 geo-spec v0.1（含全部澄清）
和 geo-testplan v0.1，串行联调独立模块测试与 RTL。
验证修复提交 `4cd98c905b2b8f851d74567486dfe9f9ee2886a2`；RTL 保持 `7ac1a35` 的实现。
本记录随后独立提交，未改 RTL，因此没有 RTL 修复提交。

| 失败 | 定性 | 规格依据与处理 |
|---|---|---|
| 完整 harness 编译报 SYNCASYNCNET | 测试集成错误 | 真实 DUT 的控制复位异步，公共 BFM/检查器在时钟边沿采样复位；仅在 TB 文件豁免此项诊断，不屏蔽 DUT 告警 |
| GE-07，第二条描述符读源时 AW=65、B=64 | 测试错误 | 2.5 要求前后描述符顺序，5.2 允许当前块计算与下一块读取重叠；原检查误把当前描述符自身未返回的写响应当作前条未完成 |
| 原 block/geo smoke 达到 60 秒超时 | 测试档位错误 | CLAUDE.md 9.1 与本 Task 要求超时目录移入 full；根目录 53 向量全部迁移，内容不删减，selftest 保留 smoke |

GE-07 修复后，在每个新描述符第一次 AR 握手时检查先前所有 B 已返回。
三条依赖链逐像素比对、DONE_COUNT/CUR_DESC 逐条检查继续保留。
修复前观察到第二条描述符本身首个块的 AW 已发出，下一块源读取与它重叠；
此前第一条描述符的全部写响应已经返回，故不是 RTL 违例。

原 `$fatal` 的字符串拼接在 Verilator 5.020 中打印成大整数，遮蔽诊断。
对拼接格式显式使用 `string'(...)`，恢复可读的测试号、坐标和期望/实际值。

## 2. 复现

工具：Linux，Python 3 标准库，Verilator 5.020（Debian 5.020-1）。
每个 shell 先执行 `. ~/.local/opt/edrv32/env.sh`。
所有回归 `-j 1`，一次最多一个仿真，无 `--parallel`。

初次失败：

```sh
make smoke REGRESS_ARGS='-j 1 --path verif/block/geo'
```

初次为 lint 失败；豁免后运行到 GE-07-chain-seed1 失败，59 秒。
修正 GE-07 后，原 smoke 在 GE-09-descriptor-seed1 通过后达到 60 秒上限。
原始日志：`build/geo/initial-smoke-failures.log`（GE-07）、
`build/regress/smoke/block/geo/verilator/run.log`（60 秒超时）。
生成的 config、输入、期望值与单向量日志在 `build/geo/<档位>/GE-*/`。

## 3. 观察与性能

GE-12 使用 1280×720 输出、45° 旋转、s=1/2、125 MHz、首拍读延迟至少 40 周期、
共享 R/W 额度限制 1.2 GB/s；PERF0×8 ns 得到帧时间。
同时读取 PERF4（源缓冲等待）和 PERF5（写出等待），PDS 前结果如下：

| GE-12 | PERF0（周期） | 帧时间 | 门限 | PERF4（周期） | PERF5（周期） | 结果 |
|---|---:|---:|---:|---:|---:|---|
| s=1 | 1,203,173 | 9.625384 ms | 16.7 ms | 7 | 240,120 | PASS |
| s=2 | 2,452,913 | 19.623304 ms | 33 ms | 929 | 1,488,938 | PASS |

两档均完成全图逐位比对及协议、PERF 与排空检查。
PERF5/PERF0 分别约 19.96% 和 60.70%；PERF4/PERF0 分别约 0.0006% 和 0.0379%。
观察表明当前条件下记录到的停顿以写出侧为主，源缓冲等待很少；
此结论仅针对这两个固定条件仿真，不是 PDS 时序或真实 DDR 测量。
没有放宽门限或更改结构。

原始日志：`build/regress/perf/block/geo/perf/verilator/run.log`、
`build/geo/perf/GE-12-1-seed1/run.log`、`build/geo/perf/GE-12-2-seed1/run.log`。

## 4. 根因

以上失败均属于验证集成或测试错误；本次验收未发现需要修改的 RTL 违例。
没有修改规格、接口、公共 BFM 或技术封装。

## 5. 修复

- `lint.vlt`：限定 TB 文件的混合复位诊断豁免。
- `edrv32_geo_memory.sv`：GE-07 顺序检查移到新描述符开始的位置。
- `edrv32_geo_tb.sv`：修正错误消息格式，并输出 GE-12 PERF4、PERF5。
- `test.yaml`：原 smoke 目录迁移 full，超时调整至与 full 子目录相同的 1800 秒。
- `check.py`：去掉独立测试开发阶段的临时空端口声明，直接 lint 真实 DUT 与完整 TB。
- `README.md`：同步真实 RTL 联调状态、最终档位、真实 DUT lint 和记录位置。

## 6. 防回归与验收

```sh
. ~/.local/opt/edrv32/env.sh
python3 tools/check/verilog_style.py rtl/media/geo
python3 verif/block/geo/check.py
make smoke REGRESS_ARGS='-j 1 --path verif/block/geo'
make full REGRESS_ARGS='-j 1 --path verif/block/geo'
python3 tools/regress.py perf -j 1 --path verif/block/geo
```

- RTL 风格：10 文件，0 告警。
- `check.py`：SV 风格 2 文件，0 告警；完整真实 DUT + TB lint 0 告警。
- 模块 smoke：1 PASS、0 FAIL（参考自测，0 秒）。
- 模块 full：3 PASS、0 FAIL（53 + 33 = 86 个 RTL 向量，另加参考自测）。
  最终复核中 full 子目录 60 秒、根目录 25 秒、自测 0 秒；所有向量均保留。
- 模块 perf：1 PASS、0 FAIL（2 个 GE-12 向量，共 98 秒）。

单独的 `edrv32_geo` lint 也为 0 告警，复现命令：

```sh
python3 - <<'PYTHON'
import subprocess
import sys
from pathlib import Path
sys.path.insert(0, 'tools')
from regress import expand_files
subprocess.run(['verilator', '--lint-only', '-Wall', '--top-module', 'edrv32_geo',
                '+define+SIM_MODE',
                *expand_files(Path('rtl/filelists/geo.f').resolve())], check=True)
PYTHON
```

逐个单元目录执行 smoke 与 full（每项均为 1 PASS、0 FAIL）：

```sh
for name in address bilinear coords math regs source; do
    make smoke REGRESS_ARGS="-j 1 --path verif/unit/geo_$name"
    make full REGRESS_ARGS="-j 1 --path verif/unit/geo_$name"
done
```

| 单元目录 | smoke | full | smoke/full 墙钟时间（含构建） |
|---|---|---|---|
| geo_address | 1 PASS / 0 FAIL | 1 PASS / 0 FAIL | 10 / 9 秒 |
| geo_bilinear | 1 PASS / 0 FAIL | 1 PASS / 0 FAIL | 10 / 10 秒 |
| geo_coords | 1 PASS / 0 FAIL | 1 PASS / 0 FAIL | 16 / 16 秒 |
| geo_math | 1 PASS / 0 FAIL | 1 PASS / 0 FAIL | 12 / 12 秒 |
| geo_regs | 1 PASS / 0 FAIL | 1 PASS / 0 FAIL | 11 / 11 秒 |
| geo_source | 1 PASS / 0 FAIL | 1 PASS / 0 FAIL | 12 / 11 秒 |

所有回归日志在 `build/regress/<档位>/unit/geo_<名>/verilator/`。
迁移到 full 的目录仅 `verif/block/geo/`；迁移依据是完整构建加运行的 60 秒超时，
不是硬件帧时间失败。剩余模块 smoke 的 `selftest/` 为 0 秒。

## 7. 同类排查

检查 GE-07 三条链的 Surface 比较与 DONE_COUNT/CUR_DESC 检查，均保留。
错误恢复和 ABORT 继续使用公共检查器及内存队列排空检查。
所有拼接 `$fatal` 格式使用相同修复；其余非拼接格式不变。
本次没有单个问题定位超过半小时，故无需额外专题调试记录。
