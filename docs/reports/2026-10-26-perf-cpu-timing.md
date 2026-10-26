# C-R5 CPU 时序优化测量

日期：2026-10-26。基线：`6e5591a5f8bbfe111f46b0ff8107dd3689d46c5a`；结果：`06a29d77eed1fb2b597e3595d1b5b2d337d51288`。

| 改动 | 提交 |
|---|---|
| HPM 事件向量寄存一拍 | `8e2d246` |
| halfword 环形缓冲与共享块元数据 | `743bdea` |
| MRET/WFI/FENCE.I 提交判断展开 | `06a29d7` |

工具：Verilator 5.020（Debian 5.020-1）、xPack GCC 15.2.0、
Yosys 0.70+219（5053d0e26，Clang 21.1.8）、Icarus Verilog 12.0。CoreMark 子模块：
`cfa9ab377835911f23d9b0831c7be302ed1f58de`，未改版本。

所有仿真串行执行，Verilator `-j 1`。系统测量使用 `RVC_EN=1`、64 KiB SRAM、
8 KiB I$/D$（2 路、32 B 行），CoreMark `ITERATIONS=10`。
O2 与 tuned 的完整编译选项保留在下述 `sw/*/build.log`。
本轮未运行 PDS；Yosys 使用通用 LUT6 映射，无器件/速度等级和物理时钟约束。

## CoreMark

执行：在基线检出和结果检出分别运行：

```sh
. ~/.local/opt/edrv32/env.sh
git submodule update --init third_party/coremark
python3 verif/block/sys_cpu/run.py perf
```

分数计算：`CoreMark/MHz = 10,000,000 / Total ticks`。
四种配置的算法 CRC 均为 `e714 / 1fd7 / 8e3a`（list / matrix / state）。

| 配置 | 基线周期 | 结果周期 | 基线 CoreMark/MHz | 结果 CoreMark/MHz | 分数变化 |
|---|---:|---:|---:|---:|---:|
| coremark_sram_o2 | 2,811,517 | 2,811,517 | 3.556799 | 3.556799 | +0.000000% |
| coremark_sram_tuned | 2,308,674 | 2,308,674 | 4.331491 | 4.331491 | +0.000000% |
| coremark_ddr_o2_l20 | 2,814,448 | 2,814,448 | 3.553095 | 3.553095 | +0.000000% |
| coremark_ddr_o2_l60 | 2,820,608 | 2,820,608 | 3.545335 | 3.545335 | +0.000000% |

原始数字与日志：

- 基线：`build/cpu_timing/before/sys_cpu/coremark.csv`、
  `build/cpu_timing/before/sys_cpu/coremark_*/run.log`、
  `build/cpu_timing/before/sys_cpu/sw/*/build.log`。
- 结果：`build/cpu_timing/after/sys_cpu/coremark.csv`、
  `build/cpu_timing/after/sys_cpu/coremark_*/run.log`、
  `build/cpu_timing/after/sys_cpu/sw/*/build.log`。
- 编译：对应 `sys_cpu/compile.log`，`-Wall -j 1`，零告警。

## Yosys 前端参考数字

顶层 `edrv32_cpu_frontend`，`RVC_EN=1`，包含 predictor、IB 和 RVC 展开。
映射命令为 `synth -flatten -noabc; abc -lut 6 -dress; opt_clean`。
深度由 `tools/synth/netlist_paths.py` 的 `analyze` 统计映射后组合级数。

| 提交 | 通用 LUT（≤6 输入） | FF | 最深组合级数 |
|---|---:|---:|---:|
| `6e5591a` | 28,781 | 5,130 | 37 |
| `06a29d7` | 10,088 | 5,167 | 25 |

LUT 变化 -64.95%；最深级数变化 -32.43%。

在两个检出分别执行以下命令；基线使用 `before`，结果使用 `after`：

```sh
. ~/.local/opt/edrv32/env.sh
python3 - after <<'PY_SYNTH'
from pathlib import Path
import json
import subprocess
import sys
from tools.synth.yosys_synth import read_filelist
from tools.synth.netlist_paths import analyze
out = Path('build/cpu_timing') / sys.argv[1]
out.mkdir(parents=True, exist_ok=True)
files, includes = [], set()
read_filelist(Path('rtl/filelists/cpu.f').resolve(), files, includes)
read = 'read_verilog -D SIM_MODE ' + ' '.join('-I' + p for p in includes)
commands = [read + ' ' + ' '.join(files),
            'hierarchy -top edrv32_cpu_frontend',
            'synth -top edrv32_cpu_frontend -flatten -noabc',
            'abc -lut 6 -dress', 'opt_clean',
            f'write_json {out}/frontend.json', 'stat']
(out / 'frontend.ys').write_text('\n'.join(commands) + '\n')
subprocess.run(['yosys', '-Q', '-T', '-l', str(out / 'frontend.log'),
                '-s', str(out / 'frontend.ys')], check=True)
result = analyze(json.loads((out / 'frontend.json').read_text()))
(out / 'levels.json').write_text(json.dumps(result, indent=2))
print(result['totals'], result['max_levels'])
PY_SYNTH
```

原始数据：`build/cpu_timing/{before,after}/frontend.{ys,log,json}`、
`build/cpu_timing/{before,after}/levels.json`。

## 定向回归

```sh
. ~/.local/opt/edrv32/env.sh
python3 tools/check/verilog_style.py rtl/cpu
make smoke REGRESS_ARGS='-j 1 --path verif/block/cpu'
make smoke REGRESS_ARGS='-j 1 --path verif/block/cpu_b2'
make smoke REGRESS_ARGS='-j 1 --path verif/block/cache'
make full REGRESS_ARGS='-j 1 --path verif/block/sys_cpu'
make smoke REGRESS_ARGS='-j 1 --path verif/unit/cpu_csr'
make smoke REGRESS_ARGS='-j 1 --path verif/unit/cpu_frontend'
python3 tools/cpu/run_b1.py verif/block/cpu/c-03-c/case.json
python3 tools/cpu/run_b1.py verif/block/cpu/c-03-no-c/case.json
```

`sys_cpu full` 包含该路径的全部 smoke 用例。

| 检查 | 结果 |
|---|---|
| CPU RTL 风格 | 12 文件，0 告警 |
| Verilator CPU lint，RVC=0/1 | 各 0 告警 |
| CPU smoke | 74 PASS，0 FAIL |
| CPU B2 smoke | 3 PASS，0 FAIL |
| Cache smoke | 23 PASS，0 FAIL |
| sys_cpu full | 8 PASS，0 FAIL，SC-07 CoreMark CRC 通过 |
| CSR 单元（Verilator / Icarus） | 2 PASS，0 FAIL |
| 前端单元 | 1 PASS，0 FAIL |
| HPM B1 c-03（C / 非 C） | 各 PASS |

CPU lint 命令：

```sh
python3 - <<'PY_LINT'
from pathlib import Path
import subprocess
from tools.regress import expand_files
for rvc in (0, 1):
    subprocess.run(['verilator', '--lint-only', '-Wall', '+define+SIM_MODE',
                    '--top-module', 'edrv32_cpu_core', f'-GRVC_EN={rvc}'] +
                   expand_files(Path('rtl/filelists/cpu.f')), check=True)
PY_LINT
```

回归汇总日志：`build/cpu_timing/style.log`、`lint-rvc{0,1}.log`、
`smoke-cpu.log`、`smoke-cpu_b2.log`、`smoke-cache.log`、`full-sys_cpu.log`、
`hpm-unit.log`、`frontend-unit.log`、`hpm-b1-{c,no-c}.log`。
逐用例日志位于 `build/regress/{smoke,full}/`。

附加开发检查（原始激励与日志留在 `build/cpu_timing/`）：

- 旧/新前端定向逐周期完整 IB / push 记录对照：1,200 周期，PASS，
  `frontend_equiv.sv`、`equiv-run.log`。
- 随机逐周期完整记录对照：各 20,000 周期；RVC=0（Icarus）PASS，
  回绕 1,075 次、预测跳转 4,240 次；RVC=1（Verilator）PASS，
  F2 恢复 1,772 次、回绕 219 次、预测跳转 3,367 次，
  `frontend_random_equiv.sv`、`random-equiv-rvc0.log`、`random-equiv-rvc1-verilator.log`。
- MRET / WFI / FENCE.I 新旧提交判断的组合 SAT 等价：SUCCESS，
  `redirect_equiv.v`、`redirect-equiv.log`；命令：
  `yosys -p 'read_verilog build/cpu_timing/redirect_equiv.v; prep -top redirect_equiv; sat -verify -prove mismatch 0 -show-inputs'`。
