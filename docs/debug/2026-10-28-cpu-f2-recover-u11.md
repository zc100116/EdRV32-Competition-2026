# cpu_f2_recover U-11：停顿 D 重定向后的参考流过时

## 1. 现象

协调者报告 `verif/unit/cpu_f2_recover` 的 U-11 case 6 失败：

```text
FAIL U-11 case=6 PC=00000100/00000000 raw=00000001/00000001 instruction=00000013/00000013 time=1405000
```

错误信息的斜线前为模型期望，斜线后为实际值。原始指令与展开结果相同，
差异是模型期望从重定向目标 `0x100` 开始，IB 实际仍输出 `0x0` 的旧首条。
协调者已二分确认 `884067b` 通过，首次失败为 `e3c67f4`；本任务基线为
`c0f6e5ab335af85e560138af731e8e73a5b81713`。

## 2. 复现

工具为 Verilator 5.020（Debian 5.020-1）；同类复核另使用 Icarus Verilog 12.0。
U-11 为八个定向场景，不使用随机种子，
`RVC_EN=1`，时钟周期 10 ns。标准复现命令：

```sh
. ~/.local/opt/edrv32/env.sh
python3 tools/regress.py smoke -j 1 --path verif/unit/cpu_f2_recover
```

本任务日志统一保存在 `build/cpu-f2-recover-u11/`；回归逐例日志位于
`build/regress/{smoke,full}/`。`before-obj/sim` 在修改模型前从上述基线编译，
`before-compile.log` 保存其编译输出。

额外尝试的全仓库 smoke 还需要初始化既有依赖：
`git submodule update --init third_party/coremark third_party/ultralytics`。
该尝试中的 NET-03 在进入仿真前因本工作树缺少 ultralytics 子模块，
报 `ModuleNotFoundError: No module named 'ultralytics'`；原始日志保存在
`build/cpu-f2-recover-u11/net03-before-env.log`。
随后按 `docs/guides/env-setup.md` 初始化仓库固定子模块版本；现有虚拟环境可导入
torch 2.14.1+cpu、numpy 2.5.2、ultralytics 8.4.160，没有修改依赖清单或 NPU 源码。

同一全局尝试还发现 `verif/block/vin` 在基线 `c0f6e5a` 编译时因 13 个
`TIMESCALEMOD` 告警退出，未进入仿真；原始日志保存为
`build/cpu-f2-recover-u11/vin-baseline-compile.log`。
协调者明确该基线失败由 **V-I1** 负责，本任务按指定 CPU 范围验收，无需全局 smoke，
并要求停止额外回归。按此指示终止了本 worker 的全局进程组，返回码 143；
没有完成全局汇总，也没有在依赖补齐后重新运行 NET-03。

实际运行 `before-obj/sim` 重现上述 1405000 ps 的同一错误，退出为 SIGABRT
（Python 返回码 -6），完整日志为 `before-run.log`。
定位时在 `build/cpu-f2-recover-u11/tb-probe.sv` 临时增加观察输出，
使用相同 `files.f` 的其余源文件，以 `verilator --binary --timing --top-module tb
-j 1 +define+SIM_MODE` 编译并运行；日志为 `probe-{compile,run}.log`，
未将观察代码入库。

## 3. 观察

case 6 在检测到 F2 边界失配时，同拍注入 D 重定向，目标为 `0x100`，
并令 `decode_pop_count_i=0`，模拟 D 指令尚未发射。旧模型在该拍直接把
`expected_pc` 改为 `0x100`，激励代码也提前把 `expected_ras` 改为目标流的检查点。

`e3c67f4` 给前端 IB 增加的保留条件是
`d_redirect_valid_i && !redirect_valid_i && decode_pop_count_i == 0`。
它保留原首条记录，把 IB 计数设为 1，丢弃较年轻记录；因此下一次消费须先检查
旧首条及其原 RAS 检查点，再检查目标流。

case 7 同时注入较老的后端重定向和 D 重定向，后端目标为 `0x180`；
此时不保留 IB 首条，模型应立即切换 PC 和 RAS。

临时观察输出确认以下时序（时间单位 ns；原日志 `%t` 为 ps）：

| 场景/时刻 | 重定向、消费和队列状态 |
|---|---|
| case 6，1335 | D=1、较老重定向=0、pop=0；IB 有 2 条，首条 PC=0，RAS=`05abcdef00` |
| case 6，1336 | 重定向后 IB 有 1 条，首条 PC 和 RAS 不变 |
| case 6，1405 | pop=2；本拍先消费 PC=0 的保留首条，再消费目标 PC=`0x100`，两条均通过模型比对 |
| case 6，1415 | IB 首条已到 PC=`0x102`，目标流 RAS=`07bbbb0000` |
| case 7，1545/1546 | 较老重定向与 D 同拍有效；IB 由 2 条清为空，无保留首条 |
| case 7，1615 | 首次消费从 PC=`0x180` 开始，RAS=`06cccc0000` |

## 4. 根因

判定为**测试模型过时**。依据 `docs/spec/cpu-spec.md` v0.11 第 4.4 节：

- D 级重定向冲刷 F1、F2 和 IB 中较年轻的指令；后级停顿时不等停顿解除即可发出，
  但该指令仍须在停顿解除后进入 E。因此不能把尚未发射的 D 首条一并丢弃。
- RAS 检查点随指令传递；保留的旧首条须保留其原检查点。
- 重定向优先级为 M 异常/中断 > E 重定向 > D 重定向 > F2 误取恢复。

`rtl/cpu/edrv32_cpu_frontend.v:213` 与 `edrv32_cpu_ib.v:43` 的保留行为符合上述要求。
基线 `verif/unit/cpu_f2_recover/tb.sv:143` 仍按完整清空 IB 的旧行为立即切换期望 PC；
其激励中的 RAS 期望赋值也有相同问题。`e3c67f4` 更新了 `cpu_frontend`、`cpu_ib`
及新增的 `cpu_redirect_wait`，但没有更新该 U-11 模型。

## 5. 修复

仅修改 `verif/unit/cpu_f2_recover/tb.sv` 的参考模型：D 重定向时保存目标 PC 和
目标 RAS，先用旧期望检查保留首条，消费该条后再切换到目标流。后端重定向立即
更新 PC/RAS 并清除待处理的 D 重定向。RAS 期望的更新从激励移入记分板。

没有修改 RTL、规格、公共头文件或文件列表；RTL 缺陷分支要求的 CoreMark 周期
对比及 CPU block full 不适用。

## 6. 防回归

保留原八个 U-11 场景及其 PC、原始字节、展开指令、长度、异常、RAS、
BTB 清除、取消请求和重定向优先级检查。case 6 现在按顺序检查保留首条及目标流，
case 7 继续检查较老重定向覆盖 D 和 F2。

本 worker 内仿真串行，Verilator 编译均为 `-j 1`。
协调者明确本任务按下列指定 CPU 范围验收，额外全局尝试中的 VIN 失败交由 V-I1 处理。
下列命令在基线工作树加本记录所属修复上执行：

| 命令 | 结果 | 汇总日志（`build/cpu-f2-recover-u11/` 下） |
|---|---|---|
| `make smoke REGRESS_ARGS='-j 1 --path verif/unit/cpu_f2_recover'` | 1 PASS，0 FAIL；八场景各检查 14 条 | `smoke-f2.log` |
| `make full REGRESS_ARGS='-j 1 --path verif/unit/cpu_f2_recover'` | 1 PASS，0 FAIL；八场景均通过 | `full-cpu_f2_recover.log` |
| `make smoke REGRESS_ARGS='-j 1 --path verif/unit/cpu_frontend'` | 1 PASS，0 FAIL | `smoke-cpu_frontend.log` |
| `make smoke REGRESS_ARGS='-j 1 --path verif/unit/cpu_ib'` | 1 PASS，0 FAIL | `smoke-cpu_ib.log` |
| `make smoke REGRESS_ARGS='-j 1 --path verif/unit/cpu_redirect_wait'` | 2 PASS，0 FAIL，RVC=0/1 | `smoke-cpu_redirect_wait.log` |
| `python3 tools/check/verilog_style.py rtl/` | 110 文件，0 告警 | `style.log` |
| core 的 `--lint-only -Wall`，RVC=0/1 | 两次均 0 告警 | `lint-core-rvc{0,1}.log` |
| U-11 testbench 的 `--lint-only --timing` | 0 告警 | `lint-testbench.log` |

lint 使用 `tools.regress.expand_files()` 展开既有文件列表：core 为
`rtl/filelists/cpu.f`，顶层 `edrv32_cpu_core`，定义 `SIM_MODE`，分别设置
`-GRVC_EN=0/1`；testbench 为 `verif/unit/cpu_f2_recover/files.f`，顶层 `tb`，
定义 `SIM_MODE`。

## 7. 同类排查

检查 `e3c67f4..c0f6e5a` 的 CPU 单元测试变更历史和
`docs/reports/2026-10-26-perf-cpu-timing.md` 的 C-R6/C-R7 验收记录。
该范围内未再修改 CPU 单元测试；报告只记载了 `cpu_frontend`、`cpu_csr`、`cpu_ib`
和 `cpu_redirect_wait` 的定向 smoke。以下 12 个目录没有出现在这些已提交记录中：

`cpu_alu`、`cpu_branch`、`cpu_core_smoke`、`cpu_core_smoke_no_c`、`cpu_decode`、
`cpu_div`、`cpu_f2_recover`、`cpu_frontend_no_c`、`cpu_mul`、`cpu_predictor`、
`cpu_regfile`、`cpu_rvc`。

此结论是“未发现已提交的运行证据”，不等同于断言历史上从未运行。
当前 CPU 单元共有 17 份 `test.yaml`、19 个仿真器条目（CSR 和 regfile 各含
Verilator/Icarus，redirect_wait 含 RVC=0/1）。

本轮全局 smoke 已逐项运行这些 CPU 单元，19 项全部 PASS；除本次修正的 U-11 外，
没有发现另一项同类失败。`cpu_frontend_no_c` 也使用 `e3c67f4` 已更新的共享前端
模型，RVC=0 同样通过。逐项输出可在全局汇总日志中检索 `PASS unit/cpu`，
各仿真器原始输出位于 `build/regress/smoke/unit/cpu*/`。
