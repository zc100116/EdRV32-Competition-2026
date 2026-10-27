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

## C-R6：D$ 命中到前端的组合路径

日期：2026-10-26。对照基线 `700dbf7`，RTL 结果 `5c853aa`，路径工具 `20cb727`。
本节覆盖 P1–P3 和协调者追加、用户确认的 P4（D 级在后级停顿时提前重定向一次）。

| 项 | 提交 | 实际改动 |
|---|---|---|
| P1 | `1ba2874` | D$ err 只由响应寄存状态限定；core 直接用 err 判断访存错误 |
| P2 | `7c26536` | 前端 halt 使用寄存一拍的 M 等待状态 |
| P3 | `e4f96a0` | E 级重定向和训练不等待 M，保存本条已判定状态；停顿中的本条保留在 E，槽 0 重定向立即清掉同组槽 1 |
| 路径工具 | `20cb727` | 按起点/终点集合筛选；支持内部接口 net，区分 FF 的 Q 别名和 D/enable 终点 |
| P4 | `5c853aa` | D 级 JAL 重定向不等待后级，保存本条已重定向状态；未发射的 JAL 留在 IB 首条，较年轻项清除 |

P1 的有效错误 `valid && err` 与旧实现逐周期相同；新增 D$ 单元检查覆盖该等式以及
`err -> valid`。I$ 同类检查结果：`ic_resp_err_o` 仍直接选择 `fill_err_r/pma_err_r`，
不依赖 tag 比较，但没有按 valid 限定，可能在无响应周期保留旧错误；本次未修改 I$。

P2 的 `div_wait_w` 保留原样：仅依赖 E 级 valid/class、`div_done_r` 和除法器的
寄存输出 `div_valid_w`，没有 D$ hit 或除法器余数减法的组合反馈。`sleep_r` 及 WFI
提交/唤醒条件未改。M 等待寄存的起始与结束两端各错开一拍：起始可能多发一次请求，
结束时前端新请求可能晚一拍恢复；后端仍由当拍 `m_wait_w` 控制。

P3 同时消除了 `e_advance_w` 中访存接收 ready 对预测纠正的限制：非控制访存指令
被 BTB 错预测为跳转时，也不等待请求接收便纠正前端，但仍等待接收后才进入 M。
M 级重定向同拍禁止年轻 E/D 重定向及 E 训练；随后发生的 M 级陷阱仍覆盖已发出的
年轻重定向并恢复提交 RAS 检查点。

### 结构路径测量

工具与 C-R5 相同：Yosys 0.70+219（5053d0e26），Verilator 5.020，GCC 15.2.0。
`edrv32_cpu_subsys`，`RVC_EN=1`，`SIM_MODE`，`rtl/filelists/cpu_subsys.f`，
包含完整 CPU、I$/D$ 与 RAM 行为模型；flatten 后使用通用 LUT6 映射：
`synth -top edrv32_cpu_subsys -flatten -noabc; abc -lut 6 -dress; opt_clean`。
FF 的 D/enable 为终点，Q 为起点；每个组合 LUT 为一级，跨 FF 不传播。
这是结构参考，未做路径可激活性约束或 PDS 物理布局布线，不据此推算 MHz。
本轮没有新的 PG2L200H-6 / 150 MHz 约束下的 PDS 测量。

筛选起点为 `u_dcache.addr_r[31:0]`、`valid0_r[127:0]`、
`valid1_r[127:0]`、同步 tag RAM 读出 `tag0_w[19:0]` / `tag1_w[19:0]`，
共 328 bit。起点内部 net 在自身驱动器之后截断；筛选在最长路径传播之前完成，
不会仅从全局最深 50 条结果中过滤而漏掉较浅的指定路径。

| 所选起点到的终点 | `700dbf7` 最长级数 | `5c853aa` 最长级数 |
|---|---:|---:|
| 前端任意寄存器 D/enable | 59 | 38 |
| IB 任意寄存器 D/enable | 55 | 34 |
| core I$ 请求 valid/addr 的实际接口 net | 54 | 33 |
| `d_issue_w` / `decode_pop_count_i` 实际 net | 39 | 26 |
| M 级重定向实际 net | 17 | 无路径 |
| E 级重定向实际 net | 31 | 无路径 |
| E 级预测器训练 valid 实际 net | 27 | 无路径 |
| D 级重定向实际 net（P4 后） | 37 | 无路径 |
| D 级访存旁路数据 `d_operand_w` 实际 net（后端内部） | 17 | 16 |

“无路径”各项的起点仍为 328 bit，所选终点各 1 bit；并非未匹配到终点。
结果版 `u_frontend.halt_i` 同样匹配到 1 bit，所选起点无路径可达；基线该内部别名被
映射优化消除，因此不提供基线 halt 单独级数。
I$ 请求 addr 直接来自 F1 PC 寄存器，所选 D$ 起点不跨该寄存器；表中的请求路径
终点为 valid（同一 net 的别名为 `u_core.u_frontend.f1_valid_o`）。

**残留路径仍存在，不能表述为“D$ 到前端已全部切断”。** 按协调者追加要求分列：

- IB：结果版 `u_dcache.addr_r[6]` → 命中/响应 → M 等待 → D 发射数量 →
  `decode_pop_count_i` → `u_core.u_frontend.u_ib.entries_r[0][50]` 的 D，34 级
  （另一并列终点为同一记录 bit 57）。基线对应终点为 55 级。
- IB `free_count_o = 4 - count_r + pop_count_i` 仍把同拍 pop 数组合反馈给前端。
  它影响 `push_count_w/consume_w`，进而影响 `remaining_w` 和请求 valid；还参与 F2
  第二条恢复判定。结果版最深前端路径经请求接收进入预测器 RAS enable，38 级，
  终点 `u_core.u_frontend.u_predictor.ras_count_r[0].E`，同组另外两位并列。
- 结果版该 38 级映射路径的可见节点依次包括：`hit1_w`（第 7 级）、`hit_w`（8）、
  `dc_resp_valid_i`（11）、`dc_commit_o`（12）、D$ `buffer_push_w`（13）、
  `dc_fence_done_i`（14）、`m_ready_w`（15）、`m_wait_w`（16）、`e_advance_w`（19）、
  `decode_pop_count_i`（25）、`remaining_w`（31）、`ic_req_valid_o`（33）、
  `request_accept_w`（35）、预测器 RAS enable（38）。级数为结构图中的最长链，
  包括提交/写缓冲/FENCE 握手的组合耦合，不代表所有条件可以在同一条指令上激活。
- P4 后 D 级重定向本身无该类路径；D 级访存旁路数据路径仍在后端内部，最长 16 级。

### 全核最深十条结构路径

以下均从完整 CPU + cache 组合中排名，未限制起点或终点。
`FE` 表示 `u_core.u_frontend`，`.E` 表示目标 FF 的使能输入。
完整映射 cell/pin 和逐级明细保存在 `all_paths.json/md`。

`700dbf7`：

| # | 起点 | 终点 | 级数 |
|---:|---|---|---:|
| 1 | `u_dcache.addr_r[6]` | `FE.u_predictor.ras_count_r[0].E` | 59 |
| 2 | `u_dcache.addr_r[6]` | `FE.u_predictor.ras_count_r[1].E` | 59 |
| 3 | `u_dcache.addr_r[6]` | `FE.u_predictor.ras_count_r[2].E` | 59 |
| 4 | `u_dcache.addr_r[6]` | `FE.f1_pc_r[1].E` | 58 |
| 5 | `u_dcache.addr_r[6]` | `FE.f1_pc_r[2].E` | 58 |
| 6 | `u_dcache.addr_r[6]` | `FE.f1_pc_r[3].E` | 58 |
| 7 | `u_dcache.addr_r[6]` | `FE.f1_pc_r[4].E` | 58 |
| 8 | `u_dcache.addr_r[6]` | `FE.f1_pc_r[5].E` | 58 |
| 9 | `u_dcache.addr_r[6]` | `FE.f1_pc_r[6].E` | 58 |
| 10 | `u_dcache.addr_r[6]` | `FE.f1_pc_r[7].E` | 58 |

`5c853aa`：

| # | 起点 | 终点 | 级数 |
|---:|---|---|---:|
| 1 | `u_core.e_operand_a_r[0][1]` | `FE.u_predictor.ras_count_r[0].E` | 49 |
| 2 | `u_core.e_operand_a_r[0][1]` | `FE.u_predictor.ras_count_r[1].E` | 49 |
| 3 | `u_core.e_operand_a_r[0][1]` | `FE.u_predictor.ras_count_r[2].E` | 49 |
| 4 | `u_core.e_operand_a_r[0][1]` | `FE.f1_pc_r[1].E` | 48 |
| 5 | `u_core.e_operand_a_r[0][1]` | `FE.f1_pc_r[2].E` | 48 |
| 6 | `u_core.e_operand_a_r[0][1]` | `FE.f1_pc_r[3].E` | 48 |
| 7 | `u_core.e_operand_a_r[0][1]` | `FE.f1_pc_r[4].E` | 48 |
| 8 | `u_core.e_operand_a_r[0][1]` | `FE.f1_pc_r[5].E` | 48 |
| 9 | `u_core.e_operand_a_r[0][1]` | `FE.f1_pc_r[6].E` | 48 |
| 10 | `u_core.e_operand_a_r[0][1]` | `FE.f1_pc_r[7].E` | 48 |

### 复现命令与原始数据

综合前将基线源文件导出到生成物目录，结果版从 `5c853aa` 检出执行。文件列表未改。

```sh
. ~/.local/opt/edrv32/env.sh
mkdir -p build/cpu_timing/cr6/before/src
git archive 700dbf7 rtl | tar -x -C build/cpu_timing/cr6/before/src
python3 - <<'PY_SYNTH'
from pathlib import Path
import subprocess
from tools.synth.yosys_synth import read_filelist
root = Path.cwd()
files, includes = [], set()
read_filelist(root / 'rtl/filelists/cpu_subsys.f', files, includes)
for label in ('before', 'after'):
    out = root / 'build/cpu_timing/cr6' / label
    out.mkdir(parents=True, exist_ok=True)
    read = 'read_verilog -D SIM_MODE ' + ' '.join('-I' + p for p in sorted(includes))
    commands = [read + ' ' + ' '.join(files), 'hierarchy -top edrv32_cpu_subsys',
                'synth -top edrv32_cpu_subsys -flatten -noabc',
                'abc -lut 6 -dress', 'opt_clean', f'write_json {out}/subsys.json', 'stat']
    script = out / 'subsys.ys'
    script.write_text('\n'.join(commands) + '\n')
    with (out / 'console.log').open('w') as log:
        subprocess.run(['yosys', '-Q', '-T', '-l', str(out / 'subsys.log'), '-s', str(script)],
                       cwd=out / 'src' if label == 'before' else root,
                       stdout=log, stderr=subprocess.STDOUT, check=True)
PY_SYNTH
```

路径统计使用同一个 `tools/synth/netlist_paths.py`，没有另写图遍历工具。
下面一次生成全部比较所用结果：

```sh
python3 - <<'PY_PATHS'
from pathlib import Path
import json
from tools.synth.netlist_paths import analyze, markdown
starts = [r'^u_dcache\.(?:addr_r|valid[01]_r|tag[01]_w)(?:\[|$)']
for label in ('before', 'after'):
    out = Path('build/cpu_timing/cr6') / label
    design = json.loads((out / 'subsys.json').read_text())
    queries = {
        'all': {},
        'frontend': {'ends': [r'^u_core\.u_frontend\..*_r(?:\[|$)']},
        'ib': {'ends': [r'^u_core\.u_frontend\.u_ib\..*_r(?:\[|$)']},
        'ic_request': {'end_nets': [r'^u_core\.ic_req_(?:valid|addr)_o(?:\[|$)']},
        'decode_pop': {'end_nets': [r'^u_core\.d_issue_w']},
        'd_redirect': {'end_nets': [r'^u_core\.d_redirect_w$']},
        'e_redirect': {'end_nets': [r'^u_core\.e_redirect_w$']},
        'm_redirect': {'end_nets': [r'^u_core\.m_redirect_w$']},
        'halt': {'end_nets': [r'^u_core\.u_frontend\.halt_i$']},
        'predict_update': {'end_nets': [r'^u_core\.u_frontend\.update_valid_i$']},
        'd_bypass_data': {'end_nets': [r'^u_core\.d_operand_w']},
    }
    for name, selection in queries.items():
        result = analyze(design, starts=None if name == 'all' else starts, **selection)
        (out / (name + '_paths.json')).write_text(json.dumps(result, indent=2) + '\n')
        (out / (name + '_paths.md')).write_text(markdown(result))
        print(label, name, result['max_levels'], result['selected_start_bits'],
              result['selected_endpoint_count'], result['endpoint_count'])
PY_PATHS
```

原始综合：`build/cpu_timing/cr6/{before,after}/subsys.{ys,log,json}`、`console.log`。
路径明细：同目录 `all_paths.{json,md}`、`frontend_paths.{json,md}`、
`ib_paths.{json,md}`、`ic_request_paths.{json,md}`、`decode_pop_paths.{json,md}`、
`{d,e,m}_redirect_paths.{json,md}`、`predict_update_paths.{json,md}`、
`halt_paths.{json,md}`、`d_bypass_data_paths.{json,md}`。

### 定向验证与期望变动说明

所有仿真串行运行，Verilator 编译 `-j 1`。执行：

```sh
. ~/.local/opt/edrv32/env.sh
python3 tools/check/verilog_style.py rtl/cpu rtl/cache/edrv32_dcache.v
make smoke REGRESS_ARGS='-j 1 --path verif/block/cpu'
make smoke REGRESS_ARGS='-j 1 --path verif/block/cpu_b2'
make smoke REGRESS_ARGS='-j 1 --path verif/block/cache'
make smoke REGRESS_ARGS='-j 1 --path verif/unit/cpu_frontend'
make smoke REGRESS_ARGS='-j 1 --path verif/unit/cpu_csr'
make full REGRESS_ARGS='-j 1 --path verif/block/sys_cpu'
make smoke REGRESS_ARGS='-j 1 --path verif/unit/cpu_ib'
make smoke REGRESS_ARGS='-j 1 --path verif/unit/cpu_redirect_wait'
python3 -m unittest discover -s tools/synth -v
python3 verif/block/sys_cpu/run.py perf
```

lint 按上节 C-R5 的 `expand_files` 命令，对 `edrv32_cpu_core` / `cpu.f` 和
`edrv32_cpu_subsys` / `cpu_subsys.f` 分别运行 `--lint-only -Wall +define+SIM_MODE`
及 `-GRVC_EN=0/1`；另对 `edrv32_dcache` / `cache.f` 运行相同 lint。

期望调整逐条如下，未修改任何模块级用例的期望周期：

- `verif/unit/cache_dcache/tb.sv`：增加 P1 的逐周期有效错误等价和 err 必带 valid 检查。
  原始测试通过记录为 `unit-dcache-p1.log`。额外组合 SAT 证明
  `new_err == old_valid && old_err` 对任意状态/错误/命中输入成立，记录于
  `p1_effective_err_equiv.v`、`p1-effective-err-equiv.log`（SUCCESS）；执行
  `yosys -Q -T -p 'read_verilog build/cpu_timing/cr6/p1_effective_err_equiv.v; prep -top p1_effective_err_equiv; sat -verify -prove mismatch 0 -show-inputs'`。
- `verif/unit/cpu_frontend/tb.sv`：P4 的 D 重定向且未 pop 时保留旧首条，模型先检查并消费
  该条，再把下一 PC 改为重定向目标；年轻条目按原要求清空。D 重定向激励仅在 IB
  非空时发出，对应真实 D 级必须有指令的前提。
- `verif/unit/cpu_ib/tb.sv`：增加 `keep_head_i` 的独立队列模型期望，flush 时只保留首条；
  其余双入/双出、回绕和完全 flush 期望未改，4,000 周期 PASS。
- 新增 `verif/unit/cpu_redirect_wait/`：RVC=0/1 各五个定向场景，检查 E/D 在后级等待时
  各只重定向一次、保存待发射指令、E 槽 0 重定向清掉槽 1、训练次数、JAL 的 RAS
  仅压栈一次，以及 M 同拍或随后故障覆盖年轻重定向；两种配置均 PASS。

工具 13 个单元测试 PASS；包含指定起点在较短支路上时仍被找到、别名/内部起点截断、
不可达终点，以及内部接口 Q 别名不误算成 FF.D 的回归。

汇总日志统一在 `build/cpu_timing/cr6/`：`style.log`、`lint-rvc{0,1}.log`、
`lint-subsys-rvc{0,1}.log`、`lint-dcache.log`、`smoke-{cpu,cpu_b2,cache,cpu_frontend,cpu_csr}.log`、
`full-sys_cpu.log`、`ib-p4.log`、`redirect-wait.log`、`tool-unit.log`、`perf.log`。
逐用例日志保留在 `build/regress/{smoke,full}/`。

| 检查 | 结果 |
|---|---|
| CPU + D$ RTL 风格 | 13 文件，0 告警 |
| core / CPU+cache 子系统 lint，RVC=0/1；D$ lint | 全部 0 告警 |
| CPU smoke | 74 PASS，0 FAIL |
| CPU B2 smoke | 3 PASS，0 FAIL |
| Cache smoke | 23 PASS，0 FAIL |
| 前端单元 | 1 PASS，0 FAIL |
| CSR 单元（Verilator / Icarus） | 2 PASS，0 FAIL |
| sys_cpu full | 8 PASS，0 FAIL，CoreMark CRC 通过 |
| IB 单元 | 1 PASS，0 FAIL |
| 停顿重定向定向单元，RVC=0/1 | 2 PASS，各五个场景 |
| 路径工具单元 | 13 PASS |
| P1 有效错误组合 SAT 等价 | SUCCESS |

### C-R6 CoreMark 周期对比

配置和编译选项沿用 C-R5，`RVC_EN=1`、64 KiB SRAM、8 KiB I$/D$、10 次迭代；
四种配置的 list/matrix/state CRC 均为 `e714 / 1fd7 / 8e3a`。

| 配置 | C-R5 周期 | C-R6 周期 | 周期差 | 周期变化 |
|---|---:|---:|---:|---:|
| coremark_sram_o2 | 2,811,517 | 2,811,516 | -1 | -0.000036% |
| coremark_sram_tuned | 2,308,674 | 2,308,675 | +1 | +0.000043% |
| coremark_ddr_o2_l20 | 2,814,448 | 2,814,447 | -1 | -0.000036% |
| coremark_ddr_o2_l60 | 2,820,608 | 2,820,607 | -1 | -0.000035% |

四配置周期绝对变化均为 1；没有配置超过 +1% 阈值。
原始数字：`build/cpu_timing/cr6/coremark.csv`（从 `build/sys_cpu/coremark.csv` 复制）。
逐配置日志：`build/sys_cpu/coremark_*/run.log`；编译选项：
`build/sys_cpu/sw/coremark_*/build.log`；仿真编译：`build/sys_cpu/compile.log`。
完整测量 stdout：`build/cpu_timing/cr6/perf.log`。

## C-R7：按 20261027-02 PDS 路径做周期等价重排

日期：2026-10-27。软件/RTL 基线为 `c664061`；结果提交见本节末尾。
PDS 依据为 `335bb0f` 的 PG2L200H-6、150 MHz、RVC_EN=1 实测：slow WNS
−3.920 ns，估计 94.46 MHz，12645/43021 个端点违例。
原始数据位于 `origin/win/20261027-02-cpu-npu-synth`（`1c3eda6`）的
`tasks/win/20261027-02-cpu-npu-synth/artifacts/cpu/`，汇总见
`docs/reports/2026-10-27-timing-cpu-sys-r2.md`。
本轮没有运行 PDS；下文 Yosys 只计结构级数，不据此换算 PG2L200H 频率。

最终四配置 CoreMark 周期差均为 **0**，全部定向验收通过。
通用 LUT6 全子系统最长路径由 **47 → 36 级**，LUT +0.53%、FF +0.97%。
D$ 地址到 CSR 计数器的组合通路消失，三个 E 操作数路径分别减少 13 级；
F2 PC 已局部化，但分出的 I$ 地址副本支路仍需 PDS 复测，详见下表。


### PDS 证据范围与六类 RTL 路径

已读取 `setup_top20_detail.txt`、`all_paths.tsv`、`hold_top200.txt`、
`high_fanout.txt`、`setup_near_positive_top20_detail.txt` 和原生 `.rtr`。
`setup_top20_detail.txt` 实际有 40 条明细，全部是 D$/乘法结果 → CSR 计数器；
其余五类的**所列最差路径**只有起终点、裕量和级数。near-positive 明细另有
F2 PC → IB 的同族正裕量路径，可补充信号链证据，不能替代 −2.892 ns 最差路径的明细。
经本任务的 `ask`，协调者确认：这五类写成“代码推导/Yosys 参考”，
逐级物理延迟和扇出写“未取得”，下一轮 Windows 按起终点分组补导出。
不能把下面的 RTL 信号链当成已经取得的 PDS 逐级明细。

本小节的行号统一引用 **基线 `c664061`**；`core`、`FE`、`PRED`、`IB`、
`CSR` 分别为 `rtl/cpu/edrv32_cpu_{core,frontend,predictor,ib,csr}.v`，
`DC`、`IC` 为 `rtl/cache/edrv32_{dcache,icache}.v`。
箭头中标出的算术、比较、选择、门控均为组合逻辑；模块端口连线和
同一结果到多个负载的广播是布线/扇出，不增加 RTL 运算层次。

| PDS 起点 → 终点 | WNS / 级数 | 基线 RTL 信号链、逻辑与布线 |
|---|---|---|
| `u_dcache/addr_r` → `u_csr/counter_r` | −3.920 ns / 24 | **有 PDS 逐级明细**。`DC:190–212`：索引 valid、tag 比较得到 `hit0_w`，选择路/字得到 `raw_load_w`；`DC:213–226`：写缓冲逐字节合并及装载移位；经 `dc_resp_data_i` 连线到 `core:617–628` 的 load 符号/零扩展，再经 `m_result_w`、`w_result_w` 和 `core:419–453` 的 D 操作数前递选择，到 `core:597–598` 的 `csr_operand_w`；端口连线到 `CSR:123–130` 的 CSRRW/CSRRS/CSRRC 写数据选择，最后到 `CSR:155–190` 的计数器写入/自动累加。PDS 中带 `e_operand_a_r/.../L6` 的点是寄存器旁的组合 LUT，并未跨过 E 寄存器。 |
| `e_operand_a_r` → `PRED.ras_data_r` | −3.233 ns / 17 | **代码推导/Yosys 参考**。`core:494–518`：`e_address_w` 32 位加法 → JALR 目标低位清零及目标选择 → 与预测目标比较 → `e_redirect0_w`；`core:522–525,587–590`：槽间/后端重定向优先级及 RAS 检查点选择；经端口到 `FE:150–160,197–201` 的 restore 选择，再到 `PRED:93–96,143–149` 的 RAS 槽地址和写使能。PDS 最差终点是 RAS FF 的 **CE**，因此控制链也属于测量对象，不仅是返回地址数据链。逐级物理延迟/扇出未取得。 |
| `FE.f2_pc_r` → `PRED.ras_data_r` | −3.102 ns / 9 | **代码推导/Yosys 参考**。本地支路为 `FE:162–163,238–248` 的响应数量/半字位置和数据选择 → `FE:265–315` 的指令长度、边界恢复判断及检查点选择 → `FE:151–155,197–201` 的 RAS restore → `PRED:143–149`。另有 Yosys 实测支路：F2 PC 与 I$ 接收地址 FF 被合并，共享网络经 `IC:81–88` 的命中/响应有效 → `FE:161–167,227,298–308` 的 append/容量与边界恢复 → RAS restore；容量支路也可经新请求接受影响 `PRED:147–149` 的推测调用写栈。两者不能仅凭 PDS 打包后的起点名称区分；明细未取得。 |
| `e_operand_a_r` → `FE.f1_pc_r` | −3.085 ns / 17 | **代码推导/Yosys 参考**。同上 `core:494–525` 的目标计算和误预测判断，`core:587–590` 选择后端重定向，`FE:147–149` 选择后端/D 重定向，`FE:375–414` 的重定向/恢复/顺序取指优先级更新 F1 PC。目标数据和晚到的重定向使能是并行的两类输入；PDS 最差终点为 F1 FF 的 CE。逐级物理延迟/扇出未取得。 |
| `e_operand_a_r` → I$ tag RAM `CEB` | −2.947 ns / 16 | **代码推导/Yosys 参考**。同上误预测控制链 → `FE.redirect_w` → `FE:166–169` 的 `ic_req_valid_o/request_accept_w` → `IC:84–86` 的 `accept_w` → `IC:103–127` 两路 tag 的 `rd_en_i`；经 `rtl/tech/edrv32_ram_icache_tag.v:31–35` 端口连线到 IP `rd_clk_en`/物理 CEB。最后这段是使能广播/布线，不是额外运算。逐级物理延迟/扇出未取得。 |
| `FE.f2_pc_r` → `IB.entries_r` | −2.892 ns / 10 | **代码推导/Yosys 参考**。`FE:162–163,238–248` 的响应数量/位置和数据选择 → `FE:265–290` 的两条指令拼接及 RVC 展开 → `FE:326–364` 的 `push_count_w/push_data_w` → `IB:30–35,59–65` 的写槽选择/写使能；PC、GHR 和预测元数据还有直接数据广播支路。共享 I$ 接收地址 FF 引出的命中/响应数据及响应有效/容量支路也可到达 IB。最差路径的逐级物理延迟/扇出未取得；同族正裕量明细见下段。 |

第一类明细给出的数据路径为逻辑 3.938 ns（38.867%）、布线 6.194 ns（61.133%）。
关键网络：`addr_r[10]` 扇出 354，net 1.022 ns；tag 选择两级分别为
0.352、0.305 ns；比较 LUT 0.113 ns 后的 `hit0_w` 扇出 74，net 0.513 ns；
`raw_load_w` 选择 0.380 ns；CSR `write_data_w[11]` 扇出 25，net 0.835 ns；
随后进入 64 位计数器 carry 链。`high_fanout.txt` 是布局前 DMR 数据，
其中 F2 PC 的两个列出网络扇出为 115、111，不能把它们当作布局后的逐级数值。
PDS 打包后 Startpoint 的寄存器名称与实际 Q 引脚信号名可能不同，例如
第一条标 `addr_r[11]/.../CLK`，实际 Q2 输出为 `addr_r[10]`。
`hold_top200.txt` 的最差裕量为 +0.143 ns，没有本轮需修复的 hold 违例。

near-positive 第 5 条是 slow +0.001 ns、7 级的 F2 PC → IB 同族路径：
`f2_pc_r[9]` 的 Q（扇出 65，net 1.008 ns）直接进入 I$ valid 选择与 tag 比较，
`hit0_w`（扇出 86）选择 `ic_resp_data_w[16]`，再经前端半字选择到
`first_length_w[1]`（扇出 221，net 0.600 ns），选择 `second_w[1]`
（扇出 37，net 1.109 ns），到 `entries_r[0][65]` 的输入。
逻辑 1.356 ns（21.004%）、布线 5.100 ns（78.996%）。这直接支持 F2 PC/I$ 地址网络
共用及指令长度选择扇出的判断；这条已满足时序的支路不是表中的 −2.892 ns 最差路径，
也没有提供 F2 PC → RAS 的最差逐级明细。它还说明 I$ 数据选择到长度译码的支路仍需下轮关注。


### 结构修改及周期等价理由

1. **CSR 写数据只取 M 级，提交条件按 CSR 类型展开。**
   `core.csr_operand_w` 直接接 `m_csr_data_r`，删除 D 操作数前递到写数据的组合输入。
   D 级仍读取同一个 CSR 地址并检查未实现/只读权限；这些检查不依赖写数据。
   `commit_i` 使用 `csr_m_access_w && m_system_commit_w`：在 M 类别为 CSR 时，
   `m_ready_w=1`、`m_memory_w=0`，故它与原来的 `csr_m_access_w && m_commit_w[0]`
   完全相同，仍受异常、中断以及除法不可中断窗口约束，但不再绕经 D$ fence/ready。
   CSR 内部 HPM 读数据按互斥地址译码后按位 OR，替代 24 次条件覆盖形成的优先链。
   地址集合不相交，读值、illegal、只读属性不变。计数器的 64 位累加、CSR 写覆盖
   自动加一、同拍未写半部保持原值、trap 优先级和写入边沿全部保持原样。
   没有让 CSR 等待 W 级，也没有提前或延后提交。
2. **E 级目标比较前移不依赖操作数的部分。**
   在原 D→E 接收边沿、使用相同 `d_issue_w != 0` 使能，保存 PC 相对目标及其预测命中比较。
   JAL 在 D 重定向后，比较位与原有预测字段覆盖一致。
   JALR 在 D 级预计算 `even_expected = {prediction[31:1],0} - immediate` 和
   `odd_expected = {prediction[31:1],1} - immediate`；E 级直接比较 rs1 是否等于两者之一，
   并要求预测目标 bit0 为 0。模 2^32 运算下，这正好等价于
   `((rs1 + immediate) & ~1) == prediction`，包含负立即数、溢出、奇数原始和与奇数预测目标。
   因而 E 重定向控制不再串过完整目标加法和目标 mux。JALR 的正确目标数据仍由原加法器产生。
   RVC=0 的目标对齐判断按指令类别直接取对应 bit1；E 级发出时点、不等 M 接收、只发一次、
   槽 1 冲刷和 trace 的重定向原因均未改。
   另把后端 redirect-valid 写成 M 请求与 E 原始原因的直接 OR，避免
   M 重定向先取消 E resolve、再经 E 槽间优先级串回后端 valid。
   令 `B=e_valid[0] && !e_resolved && !div_wait`、`N=槽0重定向原因`、
   `Y=e_valid[1] && predicted_taken[1]`，原式为
   `M || (B && !M && N) || (B && !M && Y && !(B && !M && N))`，
   化简为 `M || (B && (N || Y))`。实际 E resolve/trace/update 仍使用原来受 M 取消的条件，
   PC、RAS 和 push/pop 的 M 优先级 mux 不变。
   Yosys SAT 对上述 JALR 32 位恒等式证明成功，
   日志为 `build/c-r7/prove-jalr.log`。
3. **RAS 写槽局部译码。**
   `PRED.g_ras` 对四个固定槽分别生成 restore-top、restore-link、query-link 条件，
   最后再接晚到的 restore-valid。消除动态 part-select 写造成的整条 128 位写掩码/数据优先链。
   restore 仍压过 query；同槽 push 仍压过恢复栈顶；指针、计数、满栈覆盖和实际写入边沿不变。
4. **F2 起点预译码、响应数量预计算和 PC 局部化。**
   原请求接收边沿保存 `min(request_end,4)-f1_pc[2:1]` 与四位 one-hot 起点；
   F2 的四条流分别旋转 one-hot，选择原来的半字与预测位。计数和位置是相同表达式跨原有寄存器边界
   的移动，没有新增流水级，也不改变响应旁路、容量预留、IB 入队或边界恢复周期。
   F2 PC 改在 `!f2_pending_r || ic_resp_valid_i` 时保存 F1 PC：无未完成请求时该负载没有所有者，
   有未完成请求时一直保持到响应边沿；同拍响应/再请求也保存新请求的旧 F1 PC。
   因此每个有效 F2 响应所见 PC 相同；只允许无效负载变化。
   这个不同的寄存器使能防止综合把 F2 PC 与 I$ 已接收地址 FF 合并，分开两组负载（Yosys 中 [31:3] 的 29 个共享 bit 由 29 个降为 0 个），
   没有添加 keep/dont_touch 属性、额外复位或新参数。
5. **综合工具端口同步。**
   原 `tools/synth/ip_stubs.v` 与当前 PDS 包装器端口不符，基线 FPGA_MODE 综合在
   `ip_ram_icache_tag.rd_rst` 处明确失败。本轮按已有包装器同步 cache IP 的 reset/clock-enable、
   tag 物理地址宽度以及 SRAM/ROM/multiplier 端口；前后比较共用修正后的 stub。
   RTL 包装器、文件列表和 FPGA 文件均未修改。全 CPU+系统测量顶层的
   `hierarchy -check` 也已验证端口可连接，日志为 `build/c-r7/elaborate-top.log`；
   可用既有脚本 `python3 tools/synth/yosys_synth.py edrv32_fpga_cpu_sys_top` 的
   hierarchy 阶段复核同一组端口。

没有修改任何测试或内部观察检查。`verif/block/cpu/b1/edrv32_cpu_directed_checks.svh`
对 `e_actual_pc_w` 的优先级观察仍成立；`verif/unit/cpu_redirect_wait/tb.sv`
对 `ras_data_r` 的向量观察仍保持原名和位序。被替换的 `f2_end_r` 在验证目录没有层次引用。
没有修改 cpu-spec、公共头文件、文件列表、FPGA 文件或 cache RTL。

### Yosys 子系统结构对比

工具：Yosys 0.70+219（5053d0e26，Clang 21.1.8），
Verilator 5.020（Debian 5.020-1），xPack GCC 15.2.0。
综合顶层为 `edrv32_cpu_subsys` 的测量 wrapper，RVC_EN=1、FPGA_MODE，
I$/D$ RAM 和两拍乘法器按包装器边界作为黑盒；使用既有
`tools/synth/yosys_synth.py` 的 `synth -flatten -noabc; abc -lut 6 -dress; opt_clean`。
`tools/synth/netlist_paths.py.analyze` 包含 FF 的 D/enable 终点。
与前一节 C-R6 的 SIM_MODE 展开存储器结果不能逐项混用。

| 项目 | 基线 `c664061` | 本轮结果 | 变化 |
|---|---:|---:|---:|
| 通用 LUT6 | 29,817 | 29,974 | +157（+0.53%） |
| FF | 9,985 | 10,082 | +97（+0.97%） |
| IP 黑盒实例 | 9 | 9 | 0 |
| 全子系统最长组合级数 | 47 | 36 | −11（−23.40%） |

下表过滤起点后再求最长路径，不是从全局前若干条中反向筛选。
`—` 表示该起点集合到指定终点没有组合可达路径，不表示 0 级通路。
I$ CEB 用两路 tag wrapper 的 `rd_en_i` 实际内部网络作为终点；两路互为别名，选中 1 bit。
F2 PC 的未使用 bit0 已在 `opt_clean` 后无驱动，查询只选 [31:1]。

| 起点 → 终点集合 | 基线最长级数 | 本轮最长级数 | 处理结论 |
|---|---:|---:|---|
| D$ `addr_r` → CSR `counter_r` | 20 | — | 前递写数据入口与 fence/ready 提交入口均已消除，指定寄存器组无可达组合路径 |
| E 槽 0 `e_operand_a_r[0]` → RAS `ras_data_r` | 47 | 34 | 目标加法后的误预测比较拆开；最深剩余路径经条件分支比较和前端容量/请求接收 |
| F2 `f2_pc_r[31:1]` → RAS `ras_data_r` | 26 | — | F2/I$ 地址共享被解除，二进制起点不再控制半字数据/预测选择 |
| E 槽 0 `e_operand_a_r[0]` → F1 `f1_pc_r` | 45 | 32 | 减少 13 级；仍保留同拍 E 重定向和正确目标数据 |
| E 槽 0 `e_operand_a_r[0]` → I$ tag `rd_en_i` | 44 | 31 | 减少 13 级；没有把重定向推迟一拍 |
| F2 `f2_pc_r[31:1]` → IB `entries_r` | 23 | 5 | 剩余是 PC/元数据等短数据通路，可达终点由 1424 个降为 160 个 |
| F2 PC 及替代控制状态 `{pc,end/count,start}` → RAS | 26 | 19 | 把新寄存器也计入，避免只按旧名字报告“路径消失”；仍减少 7 级 |
| F2 PC 及替代控制状态 `{pc,end/count,start}` → IB | 23 | 16 | 同上，减少 7 级 |
| I$ `addr_r` → RAS（共享 PC 拆分后的另一份） | 26 | 28 | I$ 命中/响应有效及数据选择支路仍在；本轮未缩短，通用映射增加 2 级 |
| I$ `addr_r` → IB（同上） | 23 | 25 | 同上，不能把起点分开后的结果说成整条取指响应链消失 |

全子系统最深 10 条如下。省略公共前缀 `u_target.`，`FE/PRED` 展开为
`u_core.u_frontend.u_predictor`；D/E/R 表示终点 D、enable 或映射 FF 的同步置零控制引脚。
同级路径按既有分析器的 net 编号顺序输出，没有按寄存器组去重。

| # | 基线起点 → 终点 | 级数 | 本轮起点 → 终点 | 级数 |
|---:|---|---:|---|---:|
| 1 | `u_core.e_imm_r[0][1]` → `FE/PRED.ras_data_r[33].D` | 47 | `u_dcache.state_r[3]` → `FE/PRED.ras_count_r[0].E` | 36 |
| 2 | `u_core.e_imm_r[0][1]` → `FE/PRED.ras_data_r[34].D` | 47 | `u_dcache.state_r[3]` → `FE/PRED.ras_count_r[1].E` | 36 |
| 3 | `u_core.e_imm_r[0][1]` → `FE/PRED.ras_data_r[35].D` | 47 | `u_dcache.state_r[3]` → `FE/PRED.ras_count_r[2].E` | 36 |
| 4 | `u_core.e_imm_r[0][1]` → `FE/PRED.ras_data_r[36].D` | 47 | `u_dcache.state_r[3]` → `FE/PRED.ras_data_r[96].E` | 36 |
| 5 | `u_core.e_imm_r[0][1]` → `FE/PRED.ras_data_r[37].D` | 47 | `u_dcache.state_r[3]` → `FE/PRED.ras_data_r[64].E` | 36 |
| 6 | `u_core.e_imm_r[0][1]` → `FE/PRED.ras_data_r[38].D` | 47 | `u_dcache.state_r[3]` → `FE/PRED.ras_data_r[64].R` | 36 |
| 7 | `u_core.e_imm_r[0][1]` → `FE/PRED.ras_data_r[39].D` | 47 | `u_dcache.state_r[3]` → `FE/PRED.ras_data_r[32].E` | 36 |
| 8 | `u_core.e_imm_r[0][1]` → `FE/PRED.ras_data_r[41].D` | 47 | `u_dcache.state_r[3]` → `FE/PRED.ras_data_r[97].E` | 36 |
| 9 | `u_core.e_imm_r[0][1]` → `FE/PRED.ras_data_r[44].D` | 47 | `u_dcache.state_r[3]` → `FE/PRED.ras_data_r[98].E` | 36 |
| 10 | `u_core.e_imm_r[0][1]` → `FE/PRED.ras_data_r[45].D` | 47 | `u_dcache.state_r[3]` → `FE/PRED.ras_data_r[99].E` | 36 |

结果版的最深支路为：D$ 响应错误状态 → `dc_resp_err_i` → M 级 fault/interrupt/trap
→ 后端重定向/D 重定向有效 → F2 响应接受/可用半字数 → 边界恢复/入队数量/剩余容量
→ 新请求接受 → RAS query 更新使能。
这是 Yosys 组合图，包含互斥状态下仍被计入的结构依赖，不能据 36 级认定为下一轮 PDS 的最差路径。
E 操作数到前端剩余的最长支路经过条件分支操作数比较 → 重定向有效
→ F2 响应/容量 → 新请求接受；本轮没有改请求接收或指令推进周期。
表中 FF 的 R 是 Yosys 从数据选择映射出的同步置零控制，不是新增的 RTL 复位。
64 位计数器自身的自动进位链也保留，未从结构深度推断其器件延迟。
F2 PC 的局部化降低了共享负载，但 I$ 地址副本到 RAS/IB 的组合通路依然存在，
Yosys 还各增加了 2 级；是否由布线/扇出改善抵消，必须看下一轮 PDS，不能宣称这一支已消除。

原始结果：`build/c-r7/{before,after}/synth/netlist.{ys,log,json}`、
同目录 `{all,dcache-csr,e-ras,f2-ras,e-f1,e-ic,f2-ib,f2state-ras,f2state-ib}.{json,md}`，
以及 `build/c-r7/paths-{before,after}-summary.log`、
`paths-ic-copy-summary.log` 和 `{before,after}/synth/icaddr-{ras,ib}.{json,md}`。
中间方案只留在 `build/c-r7/after-v{1,2,3}/`，不作为本节结果。

复现综合（在结果提交检出执行；基线导出目录只提供 `c664061` 的源代码，
两侧使用同一版修正后的 IP 端口声明）：

```sh
. ~/.local/opt/edrv32/env.sh
mkdir -p build/c-r7/reproduce-before/src
git archive c664061 rtl tools/synth | tar -x -C build/c-r7/reproduce-before/src
cp tools/synth/ip_stubs.v build/c-r7/reproduce-before/src/tools/synth/ip_stubs.v
(cd build/c-r7/reproduce-before/src && python3 tools/synth/yosys_synth.py edrv32_cpu_subsys)
python3 tools/synth/yosys_synth.py edrv32_cpu_subsys
```

对两侧生成的 JSON 执行以下查询；若直接复用本轮日志，设置 `files` 为
`build/c-r7/{before,after}/synth/netlist.json` 即可：

```python
from pathlib import Path
import json
from tools.synth.netlist_paths import analyze, markdown
files = {
    'before': Path('build/c-r7/reproduce-before/src/build/synth/'
                   'edrv32_cpu_subsys_rvc1/netlist.json'),
    'after': Path('build/synth/edrv32_cpu_subsys_rvc1/netlist.json'),
}
root = r'^u_target\.'
operand = root + r'u_core\.e_operand_a_r\[0\](?:\[|$)'
pc = root + r'u_core\.u_frontend\.f2_pc_r\[(?:[1-9]|[12][0-9]|3[01])\]$'
state = root + (r'u_core\.u_frontend\.f2_(?:(?:start|count|end)_r(?:\[|$)|'
                r'pc_r\[(?:[1-9]|[12][0-9]|3[01])\]$)')
ras = root + r'u_core\.u_frontend\.u_predictor\.ras_data_r(?:\[|$)'
ib = root + r'u_core\.u_frontend\.u_ib\.entries_r(?:\[|$)'
queries = {
    'all': {},
    'dcache-csr': {'starts': [root + r'u_dcache\.addr_r(?:\[|$)'],
                  'ends': [root + r'u_core\.u_csr\.counter_r(?:\[|$)']},
    'e-ras': {'starts': [operand], 'ends': [ras]},
    'f2-ras': {'starts': [pc], 'ends': [ras]},
    'e-f1': {'starts': [operand],
             'ends': [root + r'u_core\.u_frontend\.f1_pc_r(?:\[|$)']},
    'e-ic': {'starts': [operand],
             'end_nets': [root + r'u_icache\.u_tag[01]\.rd_en_i$']},
    'f2-ib': {'starts': [pc], 'ends': [ib]},
    'f2state-ras': {'starts': [state], 'ends': [ras]},
    'f2state-ib': {'starts': [state], 'ends': [ib]},
    'icaddr-ras': {'starts': [root + r'u_icache\.addr_r(?:\[|$)'], 'ends': [ras]},
    'icaddr-ib': {'starts': [root + r'u_icache\.addr_r(?:\[|$)'], 'ends': [ib]},
}
for label, path in files.items():
    design = json.loads(path.read_text())
    for name, selection in queries.items():
        result = analyze(design, **selection)
        path.with_name(name + '.json').write_text(json.dumps(result, indent=2) + '\n')
        path.with_name(name + '.md').write_text(markdown(result))
        print(label, name, result['max_levels'], result['selected_start_bits'],
              result['selected_endpoint_count'], result['endpoint_count'])
```

JALR 比较恒等式的额外证明可复现为：

```sh
cat > build/c-r7/prove-jalr.v <<'V'
module prove_jalr(input [31:0] operand, immediate, prediction, output equal);
wire [31:0] address = operand + immediate;
wire old_match = {address[31:1], 1'b0} == prediction;
wire [31:0] even_expected = {prediction[31:1],1'b0} - immediate;
wire [31:0] odd_expected = {prediction[31:1],1'b1} - immediate;
wire new_match = !prediction[0] && (operand == even_expected || operand == odd_expected);
assign equal = old_match == new_match;
endmodule
V
yosys -Q -T -p 'read_verilog build/c-r7/prove-jalr.v; prep -top prove_jalr; sat -prove equal 1 -show-inputs'
```

### 定向验证与 CoreMark

所有仿真串行，Verilator `-j 1`。风格检查使用仓库标准 RTL 范围；
RVC=0/1 均对 core 和 CPU+cache 子系统运行 `--lint-only -Wall +define+SIM_MODE`。
额外的综合脚本测试为 `python3 -m unittest discover -s tools/synth -v`，13 项全部通过。

复现定向验收：

```sh
. ~/.local/opt/edrv32/env.sh
python3 tools/check/verilog_style.py rtl/
python3 - <<'PY_LINT'
from pathlib import Path
import subprocess
from tools.regress import expand_files
for top, filelist in [('edrv32_cpu_core', 'cpu.f'),
                      ('edrv32_cpu_subsys', 'cpu_subsys.f')]:
    for rvc in (0, 1):
        subprocess.run(['verilator', '--lint-only', '-Wall', '+define+SIM_MODE',
                        '--top-module', top, f'-GRVC_EN={rvc}'] +
                       expand_files(Path('rtl/filelists') / filelist), check=True)
PY_LINT
for scope in cpu cpu_b2 cache; do
    make smoke REGRESS_ARGS="-j 1 --path verif/block/$scope"
done
for scope in cpu_frontend cpu_csr; do
    make smoke REGRESS_ARGS="-j 1 --path verif/unit/$scope"
done
for scope in cpu sys_cpu; do
    make full REGRESS_ARGS="-j 1 --path verif/block/$scope"
done
make smoke REGRESS_ARGS='-j 1 --path verif/unit/cpu_redirect_wait'
python3 -m unittest discover -s tools/synth -v
```

CoreMark 在基线与结果检出各执行以下命令，四种配置和编译选项沿用前两轮：
RVC_EN=1、64 KiB SRAM、8 KiB I$/D$、ITERATIONS=10，SRAM O2、SRAM tuned、
DDR O2 latency=20/60。算法 CRC 必须为 list/matrix/state = `e714 / 1fd7 / 8e3a`。

```sh
. ~/.local/opt/edrv32/env.sh
git submodule update --init third_party/coremark
python3 verif/block/sys_cpu/run.py perf
```

原始基线为 `build/c-r7/before/sys_cpu/coremark.csv` 和 `coremark_*/run.log`。
结果为 `build/c-r7/after/coremark.csv`、`build/sys_cpu/coremark_*/run.log`；
各软件的完整构建命令保存在对应 `sw/*/build.log`，Verilator 编译在 `compile.log`。
最终 RTL 的四配置复测日志为 `build/c-r7/coremark-after-final.log`。
定向验收汇总日志为 `build/c-r7/{style,lint-*,smoke-*,full-*,tools-tests}.log`。

本轮两次 `ask` 均已答复：其一确认其余五类缺失的 PDS 逐级明细按“代码推导/Yosys 参考”
标注；其二确认单仿真进程约束针对本 worker 内部，不同 worker 可各自 `-j 1` 仿真。
第二次提问期间暂停过本 worker 的 SC-08，答复后恢复并通过，未超时、未重跑；
暂停不推进仿真时间或 CPU 周期。
答复原文保存在 `build/c-r7/ask-{pds-details,sim-order}.log`。
未提出改变重定向代价、CSR 排空条件或 load 结果延迟的方案，也没有修改规格。

定向验收结果：

| 命令/对象 | 结果 |
|---|---|
| `python3 tools/check/verilog_style.py rtl/` | 82 文件，0 告警 |
| core 与 cpu_subsys 的 RVC_EN=0/1 Verilator lint | 4 次均 0 告警 |
| `make smoke REGRESS_ARGS='-j 1 --path verif/block/cpu'` | 74 PASS，0 FAIL |
| `make smoke REGRESS_ARGS='-j 1 --path verif/block/cpu_b2'` | 3 PASS，0 FAIL |
| `make smoke REGRESS_ARGS='-j 1 --path verif/block/cache'` | 23 PASS，0 FAIL |
| `make smoke REGRESS_ARGS='-j 1 --path verif/unit/cpu_frontend'` | 1 PASS，0 FAIL |
| `make smoke REGRESS_ARGS='-j 1 --path verif/unit/cpu_csr'` | 2 PASS，0 FAIL（Verilator、Icarus） |
| `make full REGRESS_ARGS='-j 1 --path verif/block/cpu'` | 747 PASS，0 FAIL |
| `make full REGRESS_ARGS='-j 1 --path verif/block/sys_cpu'` | 8 PASS，0 FAIL，含 SC-07 CoreMark CRC 与 SC-08 monitor |
| `make smoke REGRESS_ARGS='-j 1 --path verif/unit/cpu_redirect_wait'` | 2 PASS，0 FAIL（RVC=0/1，各五种 E/D 重定向与 M 等待/异常场景） |
| `python3 -m unittest discover -s tools/synth -v` | 13 项全部通过 |


| 配置 | `c664061` 基线周期 | 本轮最终周期 | 周期差 | 基线 CoreMark/MHz | 本轮 CoreMark/MHz |
|---|---:|---:|---:|---:|---:|
| coremark_sram_o2 | 2,811,516 | 2,811,516 | 0 | 3.556800 | 3.556800 |
| coremark_sram_tuned | 2,308,675 | 2,308,675 | 0 | 4.331489 | 4.331489 |
| coremark_ddr_o2_l20 | 2,814,447 | 2,814,447 | 0 | 3.553096 | 3.553096 |
| coremark_ddr_o2_l60 | 2,820,607 | 2,820,607 | 0 | 3.545336 | 3.545336 |

四种配置算法 CRC 均通过，逐项周期差均为 0；CSV 中的 HPM、填充/缺失等待计数和启动周期
也逐列相同。最终 RTL 修改后的完整四配置复测已完成，未用中间方案的测量代替最终结果。

尚需下一轮 PDS 确认的部分：I$ 地址副本 → 命中/响应及数据选择 → RAS/IB 的支路仍在，
本轮通过分开 F2/缓存负载处理扇出，没有改变 I$ 的同拍响应和前端容量握手；
Yosys 上该副本支路各增加 2 级，不能在物理复测前宣称时序已改善。
条件分支比较、M 级错误/陷阱经前端容量到 RAS 的控制通路以及计数器自身的 64 位进位链也保留。
本轮只移除/重排所列组合依赖，没有证据表明必须增加流水周期，因此没有实现或提出加拍方案。

### 提交与结果对应

| 提交 | 文件 | 内容 |
|---|---|---|
| `0139281` | `tools/synth/ip_stubs.v` | 同步现有 PDS IP 端口，前后综合共用 |
| `e187075` | `rtl/cpu/edrv32_cpu_core.v`、`rtl/cpu/edrv32_cpu_csr.v` | M 级 CSR 写入口/提交分路，HPM 读选择并行化 |
| `f4606f2` | `rtl/cpu/edrv32_cpu_core.v` | D 级预计算目标比较，后端重定向有效请求并行化 |
| `e920f02` | `rtl/cpu/edrv32_cpu_predictor.v` | RAS 固定槽本地写译码 |
| `d8fb52a` | `rtl/cpu/edrv32_cpu_frontend.v` | F2 数量/起点预计算、前端 PC 副本局部化 |

最终 RTL 可检出 `d8fb52a` 复现；本报告作为后续独立提交。
测量在上述提交前的同一份最终 RTL 工作树取得：Yosys/最终回归时 HEAD 为 `0139281`，
因此生成物的 `commit.txt` 记录当时 HEAD；最终 RTL 版本对应 `d8fb52a`，
基线与共用 stub 修正按上表和复现命令取得。
