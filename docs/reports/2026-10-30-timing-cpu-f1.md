# CPU 100 MHz 近临界路径修改与测量（C-F1）

| 项目 | 条件 |
|---|---|
| 日期 | 2026-10-30 |
| 改前 RTL | `8977d1f43484942b32319d4e7046dbf9f673f219` |
| CPU 修改提交 | `8bdc4a3afe19c966b4eb3f1c7996c361f9ca9a47` |
| 改后 RTL（含 CPU 与 cache 修改） | `69208036a973324eb42f80ef14064e5b4fb7f3ce` |
| B3V RTL commit | `4ef33208996422721c342d75bb600552514a225a` |
| PDS 起点数据 | `origin/win/20261029-07-b3-rerun`，`d0dd945e1bbcb889e2c16f6e361d2c687430e771` |
| PDS 器件 / 约束 | PG2L200H-6/FBB676；PDS 2022.2-SP6.1 build138931；clk_sys 10 ns（本轮未运行 PDS） |
| Yosys | 0.70+219，git 5053d0e26；`edrv32_cpu_subsys`，`RVC_EN=0`，FPGA_MODE，LUT6，RAM/APM 黑盒 |
| 仿真 | Verilator 5.020；CSR/regfile 另含 Icarus Verilog 12.0；软件 xPack GCC 15.2.0 |
| 原始数据 | 本 worktree 的 `build/cpu-f1/`；完整版本输出 `versions.log` |

本轮切断第 1、2、4（CE）、6 类原路径，第 3 类最大级数 26→12，第 5 类 12→8。CoreMark 为 2,774,333→2,774,333 周期，退休指令数均为 2,882,012，CRC 与 16 项 HPM 读数逐项相同。

**未声称全部 DRM 起点路径达到 6 级。** 第 3 类剩余数据路径 12 级、CE 路径 11 级，第 4 类原 CE 已移除但 load 数据到 W 为 10 级，第 6 类新流水断点前半段为 7 级。协调者在本 Dispatch 的两次 ask 中明确同意保持当前 RTL、不扩大修改，把这些剩余路径交 PDS 最终判定；条件为本报告列出的回归通过和 CoreMark 不增周期。

## 六类路径级数

Yosys 数字均来自相同 `synth -noabc; abc -lut 6 -dress` 流程。分析使用仓库 `tools/synth/netlist_paths.py`：以命名 tag 输出作为组合锥起点，寄存器终点计入 D 和 CE 的最大值；统计全部对应 HPM banks、cache 两路和 CPU 两条管线。`无` 表示该起终点组合锥在网表中已不存在，不记成零级物理路径。PDS 数字是 B3V 实测，不能与 LUT6 级数直接等同。

| # | 起点 → 终点类别 | B3V slow 裕量 ns / 级数 | 改前 Yosys | 改后 Yosys | 说明 |
|---|---|---:|---:|---:|---|
| 1 | IB read_ptr → HPM counter | +0.182 / 26 | 18 | 无 | 分离 D 权限检查与 M CSR 读写地址 |
| 2 | D$ tag → predictor ras_data | +0.248 / 10 | 23 | 无 | 调用/返回的已提交 RAS 更新使用自身提交条件 |
| 3 | D$ tag → E operand_a/b | +0.363 / 11 | 26 | 12 | 剩余最差是 load 数据前递；CE 单独测得 11 |
| 4 | D$ tag → W result（原 CE） | +0.420 / 8 | 16 | CE 无；数据 10 | W payload 每拍采样，w_valid 仍按原提交条件更新 |
| 5 | I$ addr → valid0/1 | +0.509 / 6 | 12 | 8 | 请求接受拍同步读取 metadata、寄存集合掩码 |
| 6 | D$ tag → dirty0/1 | +0.598 / 10 | 13 | 无 | 前半段 tag→scan_invalidate 为 7；下一状态清 dirty/valid |

最终网表：`after4/netlist.json`；每类完整前后路径：`before/group1.json`…`group6.json`、`after4/group1.json`…`group6.json`。CE 单独分析和新增断点在 `after4/operand_ce.json`、`w_result_ce.json`、`scan_invalidate.json`；CE 分析只保留 FF 的 CE 输入终点，FF 的 Q 边界保持不变。

剩余最差数据路径为 `u_dcache.tag0_w` → tag 匹配 → D$ load 数据选择 → M 级 load 格式化 → M→D 旁路 → `e_operand_a_r[0][15]`，12 LUT6 级；到 `w_result_r[0][15]` 为 10 级。Yosys 在共享逻辑时重新合并了部分分路提前移位的组合锥，以上数字按最终映射网表报告。不能由这些逻辑级数推算布线后的裕量或 Fmax。

## 改动与周期关系

- `rtl/cpu/edrv32_cpu_csr.v`、`rtl/cpu/edrv32_cpu_core.v`：第 1 类实际终点为 HPM counter，不是 minstret。D 级只走独立的 CSR 权限译码，M 级独占 CSR 数据口，沿用同一权限函数；没有新增计数流水，mcycle/minstret/HPM 的读数、写优先级和 HPM 原有一拍延迟保持原语义。
- `rtl/cpu/edrv32_cpu_core.v`：第 2 类将已提交 RAS 的调用/返回更新条件专用于非访存指令；第 3 类在 E→M 时准备 memory-wait 属性，E 槽空闲时可以提前装入 D 操作数，未冲刷且未推进的有效 E 指令仍保持操作数；第 4 类移除 W payload 的提交 CE，W valid 的更新条件不变。
- `rtl/cache/edrv32_dcache.v`：请求接受拍寄存两位 tag 分组的选择表，与 RAM 读同拍读取 valid，准备 cached-hit eligibility；cache 接收条件仍不依赖当前新请求的 PMA。两路 load 先各自合并旁路和移位，再选择命中路。FENCE 与 M 级访存提交互斥，移除 FENCE 完成判断中本不可能发生的同拍 buffer_push 依赖。
- `rtl/cache/edrv32_icache.v`：接受拍寄存集合掩码、有效位和 LRU；同集合前一拍 hit 对 LRU 的更新在该接受边沿旁路，接受时的 invalidate 清除 metadata 快照。
- `rtl/cache/edrv32_dcache.v`：维护范围的首末 cache line 在接受命令时计算，index 比较在 S_MREAD 与 tag RAM 同拍完成；S_MCHECK 寄存清除条件，已有的 S_MNEXT 状态再更新 valid/dirty。dirty clean+invalidate 的写回和 B 响应处理不变，维护状态数与完成拍数不变，缓存请求仍在维护结束后 replay。
- 数据 payload 和 tag 选择表不复位；控制 valid 与 payload 分开写。新增测试仅覆盖这些已有规格行为：D/M CSR 同拍不同地址、I$ LRU 同集合相邻接受与 invalidate、D$ 跨 tag/index 边界和 exclusive end 的维护范围。

## 回归命令与耗时

全部命令在仓库根目录先执行 `. ~/.local/opt/edrv32/env.sh`；worker 的仿真串行运行，Verilator 编译均 `-j 1`。

### 风格与 lint

```sh
python3 tools/check/verilog_style.py rtl/cpu rtl/cache
```

16 文件，0 warnings，耗时 0.46 s（`style.log`、`style.time`）。Lint 由 `tools.regress.expand_files(Path('rtl/filelists/cpu_subsys.f'))` 展开文件列表，以 `verilator --lint-only -Wall +define+SIM_MODE --top-module edrv32_cpu_subsys -GRVC_EN=0` 和 `-GRVC_EN=1` 分别执行；两次合计 4.06 s，0 warnings，完整命令保存在 `lint.log`。

### 全部 CPU/cache 单元测试

实际逐目录命令：`python3 tools/regress.py full --path verif/unit/<目录名> -j 1`，执行脚本 `build/cpu-f1/regress_units.py`。21 个目录（包含嵌套 no_c 配置及 CSR/regfile 的 Icarus），24 次运行全部 PASS，合计 1154.81 s；原始命令与耗时 `units.json`，总输出 `units.log`，仿真日志 `build/regress/full/unit/`。

| 目录 | 耗时 s | 结果 |
|---|---:|---|
| `cache_ctrl` | 71.25 | PASS |
| `cache_dcache` | 69.86 | PASS |
| `cache_icache` | 44.14 | PASS |
| `cache_pma` | 27.73 | PASS |
| `cache_ram` | 18.43 | PASS |
| `cpu_alu` | 17.73 | PASS |
| `cpu_branch` | 28.73 | PASS |
| `cpu_core_smoke` | 96.67 | PASS |
| `cpu_core_smoke_no_c` | 143.50 | PASS |
| `cpu_csr` | 156.58 | PASS |
| `cpu_decode` | 28.39 | PASS |
| `cpu_div` | 34.35 | PASS |
| `cpu_f2_recover` | 33.65 | PASS |
| `cpu_frontend` | 57.23 | PASS |
| `cpu_frontend_no_c` | 33.36 | PASS |
| `cpu_ib` | 33.65 | PASS |
| `cpu_mul` | 25.09 | PASS |
| `cpu_predictor` | 105.31 | PASS |
| `cpu_redirect_wait` | 99.26 | PASS |
| `cpu_regfile` | 11.93 | PASS |
| `cpu_rvc` | 17.98 | PASS |

首轮期间继续完成的 RTL 与新用例，最终补跑同样的命令如下，均 PASS；串行脚本 `regress_final.py`，记录 `units_final.json`、`final-tests.log`。

| 目录 | 最终补跑耗时 s | 结果 |
|---|---:|---|
| `cache_dcache` | 28.49 | PASS |
| `cache_icache` | 16.54 | PASS |
| `cpu_core_smoke` | 32.67 | PASS |
| `cpu_core_smoke_no_c` | 40.53 | PASS |

### ISA：riscv-tests 和 riscv-arch-test

实际命令 `python3 build/cpu-f1/regress_isa.py`：从 `verif/block/cpu/**/case.json` 选出 suite 为 `riscv-tests`、`arch-test` 的全部 282 项，读取对应 `test.yaml` 后调用统一入口的 `run_test(..., tier='full', jobs=1)` 串行运行，不自行改动测试列表或跳过配置。RVC=0/1 均覆盖；退休追踪按原 runner 与 Spike 比较，arch-test 还比较签名。

| 测试来源 | 数量 | 总耗时 s（含首次编译） | 结果 |
|---|---:|---:|---|
| riscv-tests | 127 | 138.86 | PASS |
| arch-test | 155 | 589.56 | PASS |

完整逐项结果 `isa.json` 和 `final-tests.log`，对应回归日志 `build/regress/full/block/cpu/`。可用仓库统一入口逐目录复现：

```sh
for test_dir in verif/block/cpu/isa-* verif/block/cpu/arch-*; do
    python3 tools/regress.py full --path "$test_dir" -j 1 || exit
done
```

### CoreMark

测量配置：RVC_EN=0，GCC 15.2.0，RV32IM_Zicsr，`-O2`，10 iterations，真实 I$/D$ 的 B2 bench，AXI read latency=2。测量调用现有 `tools/cpu/b2_measure.py` 的 build/execute/coremark_row，保留各版本软件输出目录；基线 RTL 由 `git show 8977d1f:<source>` 写入 build 中的仿真源快照。没有给 RTL 增加测试专用条件。

实际命令：

```sh
python3 build/cpu-f1/coremark.py before
python3 build/cpu-f1/coremark.py after compile
python3 build/cpu-f1/coremark.py after
```

`coremark.py` 仅编排现有 B2 bench 与测量工具，完整编译命令在 `before/compile.log`、`after/compile.log`；常规等价复现命令为 `python3 tools/cpu/b2_run.py r05 --rvc 0 --read-latency 2`（各 RTL commit 单独运行）。

| 指标 | 改前 | 改后 |
|---|---:|---:|
| Total ticks / B2 window cycles | 2774333 | 2774333 |
| 退休指令数 | 2882012 | 2882012 |
| CoreMark/MHz | 3.604469975 | 3.604469975 |
| CRC list / matrix / state | e714 / 1fd7 / 8e3a PASS | e714 / 1fd7 / 8e3a PASS |
| 测量命令耗时 s | 320.71（冷编译） | 31.87（已编译增量运行） |

计数没有增加，HPM 1–16 也逐项相同。原始计数 `before/coremark.json`、`after/coremark.json`；UART、窗口与 HPM 日志 `before/rvc0_r05_o2/run_l2.log`、`after/rvc0_r05_o2/run_l2.log`。

## 综合复现与资源

```sh
python3 tools/synth/yosys_synth.py edrv32_cpu_subsys --rvc-en 0
```

分别在改前、改后 RTL 上执行，同一工具、同一选项；本次改前综合耗时 365.95 s，最终改后 193.15 s。最终产物复制到 `build/cpu-f1/after4/`，此前探索结果不作为交付数字；基线保存在 `before/`。

六类过滤条件可通过仓库分析函数复现（CLI 的 `--start`、`--end` 与函数使用相同正则）：

```python
from tools.synth.netlist_paths import analyze
filters = [
    (r'u_ib.read_ptr_r', r'u_csr.counter_r'),
    (r'u_dcache.tag[01]_w(?:\[|$)', r'u_predictor.ras_data_r'),
    (r'u_dcache.tag[01]_w(?:\[|$)', r'u_core.e_operand_[ab]_r'),
    (r'u_dcache.tag[01]_w(?:\[|$)', r'u_core.w_result_r'),
    (r'u_icache.addr_r', r'u_icache.valid[01]_r'),
    (r'u_dcache.tag[01]_w(?:\[|$)', r'u_dcache.dirty[01]_r'),
]
for start, end in filters:
    result = analyze(design_json, [start], [end])
    print(result['max_levels'], result['endpoint_count'])
```

| LUT6 代理资源 | 改前 | 改后 | 变化 |
|---|---:|---:|---:|
| LUT | 28028 | 27613 | −415 |
| FF | 9863 | 10031 | +168 |
| RAM/APM 黑盒实例 | 9 | 9 | 0 |

以上是通用 LUT6 代理综合，不能当作 PG2L200H 的 PDS 实际 LUT/FF/DRM 资源或时序结果。PDS 仍需确认第 3 类数据/CE、第 4 类数据、第 6 类前半段以及 clk_sys 全域的 setup/hold；本轮没有取得改后的物理裕量。
