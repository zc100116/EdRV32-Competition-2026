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
