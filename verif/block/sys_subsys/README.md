# 系统子系统 SB 验证环境（S-V1）

依据 sys-subsys-spec v0.1 及协调者确认并写入 v0.2 的顶层端口、复位和覆盖契约；
依据 sys-subsys-testplan 3.1–3.5、5、6。编写时没有读取被测的
`rtl/bus/`、`rtl/periph/`、`rtl/soc/` 实现。

`edrv32_sys_env.sv` 通过规格 3.4 的扁平端口连接 DUT；`edrv32_sys_cases.svh`
包含全部 50 项测试。两个 `edrv32_axi64_master` 实例模拟 I$/D$；M0 只连接 AR/R，
M1 连接五通道。驱动支持 SIZE、WSTRB、LEN、事务间隔和响应反压；每方向一次一笔。
系统复位会将驱动置为空闲并终止在途调用，包括允许被 SOC 软复位取消的触发写。

复用 `edrv32_axi64_memory` 作为 S6 DDR 模型，复用其独立 `reference_memory`
字节阵列作为 ROM/SRAM/DDR oracle；DDR 别名共享物理存储。地址均来自生成的
`edrv32_soc_map.vh`。`edrv32_sys_reference.sv` 单独实现区域、矩阵、响应和字节写参考。
`+ROM_HEX`、`+SRAM_HEX` 同时提供给 DUT 和参考模型；MEM-01/05 缺少对应镜像会明确失败。
镜像为 64 位 `$readmemh` 格式；固定镜像测试应传完整镜像，以便比较区域首尾。

APB 模型提供 16 槽寄存器阵列、`delay_cycles`、`inject_error`、`never_ready`；
`used_slots` 默认媒体 0–9，CACHE_CTRL 实例只启用槽 5。预留槽返回 ready/error，
已用槽才记录传输。`last_data` / `last_strb` 保存最后一次传输的 AXI 半部转换结果。
`edrv32_apb_checker` 检查单热选择、SETUP/ACCESS、等待期间负载保持，并允许在第
256 个 ACCESS 周期后结束超时传输。

AXI 检查器增加经授权的 `CACHE_CONTRACT` 参数，默认 1 保持原 cache 检查；SB 使用
0 保留通道保持、事务并发、LEN/LAST 和写数据完成前不能产生 BVALID 等协议检查，
允许测试规定的非法请求和任意 WSTRB 交给 DUT 返回错误。两个主口和外部 S6 都挂检查器；
`binds.f` 将同一检查器绑定到 sys_xbar 的全部七个从口，并在 APB decoder 和四个
内部 APB 外设边界绑定 APB 检查器。绑定只使用规格端口；端口 fixture 的六个顶层
在 `stub/` 中单独编译，避免读取正在并行开发的 RTL。

UART 模型 `verif/models/uart_model.sv` 提供 `baud`、`deviation`（比例偏差）、
`send(byte, frame_error)`、`expect_byte(byte)` 和接收队列；8N1，位时间以 ns 计。
SCCB 模型 `verif/models/sccb_model.sv` 响应写地址 0x78 / 读地址 0x79，16 位寄存器
指针、8 位数据；`nack_byte` 按 START 后的字节序号配置，地址字节为 0，-1 为不注入。
它支持 STOP+START 和重复起始的读取，记录 `bytes_seen`、`writes`、`reads`、`nacks`；
`quarter_ns` 配置四相时序检查（0 关闭速率检查），覆盖 SCL 周期/高低时间、
SDA 建立/保持和 START/STOP 建立/保持。

默认系统时钟半周期 5 ns（从 `EDRV32_CLK_SYS_HZ` 计算），媒体半周期 4 ns，相位偏移 1.137 ns；系统频率为
100 MHz（1 ps 时间精度），寄存器分频计算使用生成的时钟常量。`sys_half` / `mem_half`
可配置；AB-07 遍历 0.5、0.83、1、2 的比率并随机化访问相位和从设备延迟。
GPIO 激励由 `gpio` 提供，两个 SCCB peer 分别连接两对开漏引脚。

## 真实 RTL 的接入

S-I1 的 `environment.f` 使用 `rtl.f` 中的真实系统子系统、共享模型以及内部绑定。
`rtl.f` 路径相对本目录，与协调者维护的 `rtl/filelists/sys_subsys.f` 使用同一套 RTL，
公共原语只列一次。`selftest/files.f` 也使用真实环境；UART 自测通过 APB 寄存器
触发发送、接收及帧错误检查。`stub/` 仅保留绑定端口 fixture；旧顶层桩和其文件列表已删除，
不进入任何已激活的 SB 功能测试文件列表。

40 项 S 测试已激活为 `smoke`，10 项 F 测试为 `full`；`full` 同时运行全部 S、F 项。
各清单的 `runner` 调用 `run.py`，自动生成完整 ROM/SRAM 镜像并同时传给 DUT 和参考模型。
它按组复用 Verilator 模型，构建最多 `-j 2`，逐项串行运行；`CASE_ID` 参数选择测试组，
同名 plusarg 选择组内场景。直接调用 `run.py smoke` 或 `run.py full` 可运行目标 SB 档位，
不触发全仓回归。数值参数（如 `run.py 104`）只运行相应测试项。

## 已确认的测试契约

- M0 写不适用；真实仲裁竞争只要求 S0/S1/S6。S2–S5 检查 M0 DECERR 与 M1 合法访问
  同时发生时的隔离。PLIC 认领覆盖只统计已分配的 12 个源，3/4/7 保持为零。
- 预留 APB 槽可以有自身的 SETUP/ACCESS，但不能选中已用槽；非法突发、SIZE、对齐
  请求必须在 AXI 侧拒绝，不能发出任何 APB SETUP。绑定观察器为内部系统槽提供计数。
- MEDIA 软复位写正常返回 B；SOC 软复位写允许被复位取消，驱动随 `rst_sys_n` 复位。
- CL-01 以 AR 接受到 R 返回之间的 `mtime_o` 范围核对读值，不假设额外的采样周期。

## 命令

从仓库根目录执行，生成物都在 `build/sys/`：

```sh
. ~/.local/opt/edrv32/env.sh
python3 verif/block/sys_subsys/run.py smoke
python3 verif/block/sys_subsys/run.py full
python3 verif/block/sys_subsys/coverage.py build/sys/full/*.log
python3 verif/block/sys_subsys/verify.py selftest
python3 verif/block/sys_subsys/verify.py probes
python3 verif/block/sys_subsys/verify.py style
```

`run.py` 把各项日志写到 `build/sys/{smoke,full}/<测试项>.log`，模型构建日志在
`build/sys/group<组号>/compile.log`；单项重现日志在 `build/sys/<CASE_ID>/`。

`selftest` 构建环境、生成完整 ROM/SRAM 镜像并传 plusarg；检查双主、存储回读、
DECERR、ROM 写错误、APB 延迟/错误/256 周期超时和恢复、UART 正常字节及帧错误、
SCCB 写/读/NACK。P0 的 smoke 自测不传镜像时仍检查上述事务，只跳过初始镜像比较。
`probes` 正例还验证公共 AXI 内存模型的 DDR 别名；负例进程必须非零退出，且日志
必须出现对应诊断：AR 保持、BVALID 提前、APB 保持、非单热选择、SCCB START 保持时间。
`lint` 对 50 项参数配置、自测及六种绑定 fixture 分别进行 `--lint-only --timing -Wall`；
`compile` 对九组代表配置构建 binary。每次构建使用 `-j 1`。

`style` 复用仓库风格检查的机械规则；对 CLAUDE.md 9.1 允许的 timed SystemVerilog
语法不应用可综合 RTL 的禁令，并避开 RTL scanner 将 task/function 误认成实例的情形。
模块实例的命名连接仍单独检查；每行一端口、100 列、四空格缩进和文件头规则仍检查。
局部 lint 豁免只针对生成地址头的无关 UNUSEDPARAM，以及时钟生成、串行事件模型、
覆盖计数和复位引脚更新中必须原子执行的 BLKSEQ，以及 testbench 同步采样异步复位
输出的 SYNCASYNCNET。桩的复位同步使用公共 `cdc_sync_bit` / `reset_sync` 原语。

覆盖脚本逐项打印 covered/uncovered 和计数，不把缺失分箱伪装为通过。功能日志输出
`COVER name=count`，统计主从读写、三类响应、仲裁/隔离、APB、PLIC、UART、I2C 和复位；
full 回归将所有通过日志传入 `coverage.py` 做覆盖收敛。XB-07 每次执行种子 1–50，
每种子每个主设备 100 笔，记录 SEED；M0/M1 使用分离的数据区避免参考模型读写竞争。

## 测试项—文件对照

全部场景实现在 `edrv32_sys_cases.svh`；目录内均有 `test.yaml` / `files.f`，
`edrv32_sys_case_tb.sv` 按 CASE_ID 运行。S/F 是验证方案档位，对应已激活的
`smoke` / `full`。

| 测试项 | 目录（相对本目录） | CASE_ID | 场景任务 | 档位 |
|---|---|---:|---|---|
| XB-01 | `xb_01/` | 101 | `xbar_case` | S |
| XB-02 | `xb_02/` | 102 | `xbar_case` | S |
| XB-03 | `xb_03/` | 103 | `xbar_case` | S |
| XB-04 | `xb_04/` | 104 | `xbar_case` | S |
| XB-05 | `xb_05/` | 105 | `xbar_case` | F |
| XB-06 | `xb_06/` | 106 | `xbar_case` | S |
| XB-07 | `xb_07/` | 107 | `xbar_case` | F |
| MEM-01 | `mem_01/` | 201 | `memory_case` | S |
| MEM-02 | `mem_02/` | 202 | `memory_case` | S |
| MEM-03 | `mem_03/` | 203 | `memory_case` | S |
| MEM-04 | `mem_04/` | 204 | `memory_case` | S |
| MEM-05 | `mem_05/` | 205 | `memory_case` | S |
| AB-01 | `ab_01/` | 301 | `apb_case` | S |
| AB-02 | `ab_02/` | 302 | `apb_case` | S |
| AB-03 | `ab_03/` | 303 | `apb_case` | S |
| AB-04 | `ab_04/` | 304 | `apb_case` | F |
| AB-05 | `ab_05/` | 305 | `apb_case` | S |
| AB-06 | `ab_06/` | 306 | `apb_case` | S |
| AB-07 | `ab_07/` | 307 | `apb_case` | F |
| CL-01 | `cl_01/` | 401 | `clint_case` | S |
| CL-02 | `cl_02/` | 402 | `clint_case` | S |
| CL-03 | `cl_03/` | 403 | `clint_case` | S |
| CL-04 | `cl_04/` | 404 | `clint_case` | S |
| CL-05 | `cl_05/` | 405 | `clint_case` | F |
| PL-01 | `pl_01/` | 501 | `plic_case` | S |
| PL-02 | `pl_02/` | 502 | `plic_case` | S |
| PL-03 | `pl_03/` | 503 | `plic_case` | S |
| PL-04 | `pl_04/` | 504 | `plic_case` | F |
| PL-05 | `pl_05/` | 505 | `plic_case` | S |
| UA-01 | `ua_01/` | 601 | `uart_case` | S |
| UA-02 | `ua_02/` | 602 | `uart_case` | S |
| UA-03 | `ua_03/` | 603 | `uart_case` | S |
| UA-04 | `ua_04/` | 604 | `uart_case` | F |
| UA-05 | `ua_05/` | 605 | `uart_case` | S |
| UA-06 | `ua_06/` | 606 | `uart_case` | F |
| GP-01 | `gp_01/` | 701 | `gpio_case` | S |
| GP-02 | `gp_02/` | 702 | `gpio_case` | S |
| GP-03 | `gp_03/` | 703 | `gpio_case` | S |
| IC-01 | `ic_01/` | 801 | `i2c_case` | S |
| IC-02 | `ic_02/` | 802 | `i2c_case` | S |
| IC-03 | `ic_03/` | 803 | `i2c_case` | S |
| IC-04 | `ic_04/` | 804 | `i2c_case` | S |
| IC-05 | `ic_05/` | 805 | `i2c_case` | F |
| IC-06 | `ic_06/` | 806 | `i2c_case` | F |
| SY-01 | `sy_01/` | 901 | `sysctrl_case` | S |
| SY-02 | `sy_02/` | 902 | `sysctrl_case` | S |
| SY-03 | `sy_03/` | 903 | `sysctrl_case` | S |
| SY-04 | `sy_04/` | 904 | `sysctrl_case` | S |
| SY-05 | `sy_05/` | 905 | `sysctrl_case` | S |
| SY-06 | `sy_06/` | 906 | `sysctrl_case` | S |

环境自测：`selftest/edrv32_sys_selftest_tb.sv`；协议正负例：
`protocol/edrv32_sys_protocol_tb.sv`。外部串行模型在 `verif/models/`；新增总线 BFM、
协议检查器和被动适配器在 `verif/common/`。

## S-V1 验收记录

最终命令、结果和源码提交见本节末尾；真实 RTL 的功能回归与覆盖收敛由 S-I1 完成。

代码提交：`795400b`（基点 `7822d70`），分支 `zc100116/task-sys-verif`；
2026-10-25，Verilator 5.020。后续报告提交只更新本记录。

| 验收 | 命令或入口 | 结果与日志 |
|---|---|---|
| 桩自测 | `verify.py selftest`；P0 `run_test` 单独选择 `selftest/test.yaml` | PASS；`build/sys/selftest/run-final.log`、`build/regress/smoke/block/sys_subsys/selftest/verilator/run.log` |
| 初始镜像 | 上述 P0 binary 加 `+ROM_HEX=build/sys/rom.hex +SRAM_HEX=build/sys/sram.hex` | PASS，首尾内容与独立参考模型一致 |
| 协议正负例 | `verify.py probes` | 正例及 5 种负例全部符合预期；`build/sys/probe-summary.log`、`build/sys/protocol/*.log` |
| 全部 HDL 配置 | `verify.py lint` | 50 功能项 + 自测 + 6 种绑定 fixture，0 告警；`build/sys/compile-summary-final.log`、`build/sys/*-lint.log` |
| 代表 binary | `verify.py compile` | XB/MEM/AB/CL/PL/UA/GP/IC/SY 九组代表配置构建通过；`build/sys/binary-summary.log`、各组 `compile.log` |
| 风格与公共 RTL lint | `verify.py style`、`make lint` | SB 25 文件 0 告警，RTL 17 文件 0 告警；`build/sys/sb-style.log`、`build/sys/make-lint.log` |
| 共享检查器兼容 | P0 分别选择 cache `ic_01/test.yaml`、`dc_03/test.yaml` | 2 PASS / 0 FAIL；对应 `build/regress/smoke/block/cache/` 日志 |
| 桩覆盖 | `coverage.py build/sys/selftest/run-final.log` | 13/99 分箱；`build/sys/coverage-final.txt`，其余保留 uncovered，真实 DUT 在 S-I1 收敛 |

P0 单项回归的可复现调用（避免启动全仓并发编译）：

```sh
. ~/.local/opt/edrv32/env.sh
python3 - <<'PY'
from pathlib import Path
from tools.regress import read_test, run_test
for item in ('sys_subsys/selftest', 'cache/ic_01', 'cache/dc_03'):
    path = (Path('verif/block') / item / 'test.yaml').resolve()
    assert run_test(path, read_test(path), 'verilator', 'smoke')
PY
build/regress/smoke/block/sys_subsys/selftest/verilator/obj/sim \
    +ROM_HEX=build/sys/rom.hex +SRAM_HEX=build/sys/sram.hex
```

全量 `make smoke/full` 按协调者 2026-10-25 的资源安排未执行，改为上述本任务自测、
两个 cache 代表测试、`make lint` 和风格检查；全量回归由协调者在集成时串行运行。
九组 binary 构建后，桩复位进一步切换为公共同步原语；该最终桩已重新构建自测
binary、通过 P0 回归和镜像自测，并重新对全部配置执行 HDL lint。

自测曾在 SCCB 首个 ACK 处失败。独立最小复现中，Verilator 5.020 对定时 task 内
动态位选写 `test_scl_oe[port_index]` 没有传播预期的引脚变化；改为整向量赋值后，
SCL/SDA 事件和字节接收均正确。当前 selftest 固定覆盖两端口、ACK/NACK、写入和读取；
负例另检查 START 保持时间。复现观察日志在 `build/sys/sccb-probe-*.log`。

S-V1 交付时留给 S-I1 的工作为：接入真实 DUT 和内部绑定、提供实际镜像、激活 50 项清单、
运行 smoke/full（XB-07 为 50 种子）并使 99 个可达功能分箱全部覆盖；本次不声称
真实外设功能、性能或全仓回归已经通过。


## S-I1 联调记录

代码提交：`590e02a`，分支 `zc100116/task-sys-integ`；2026-10-25 Linux，
Verilator 5.020（Debian 5.020-1）、Icarus Verilog 12.0。

本轮没有修改 RTL。独立 SB 环境发现并修正了以下测试问题，每项独立提交：

| 提交 | 场景、根因与修正 |
|---|---|
| `3eb495a` | XB-01/02：共享 PENABLE 在未选中外设处仍可以为 1，删除误报条件；保留选中事务的 SETUP、等待保持检查，并补协议正例 |
| `2b1f302` | XB-04：每轮两次完成都会推进仲裁历史，不能要求下一轮的首个获胜者翻转；先用单主完成事务设定历史，再检查下一次平局让给另一主设备 |
| `7b9d1cc` | XB-05：DDR 模型有随机等待，不同目标的 R 窗口不必重叠；该确定性场景关闭模型随机等待，逐主比较并行访问与无竞争访问的首拍延迟 |
| `59c0221` | XB-07：每种子重复创建 timed fork 子协程在当前模拟器的第二种子异常退出；使用持久驱动流和时钟采样的种子屏障，保留 50 种子、每主每种子 100 笔 |
| `9a88a17` | 原桩自测依赖 UART 引脚直接回环；改接真实顶层，由 APB 寄存器驱动 UART 收发并检查真实 RX 帧错误状态 |
| `590e02a` | runner 成功汇总中的“0 FAIL”被 P0 判为失败；改为 PASS 比例，通过 XB-01 的 `regress.run_test` 确认公共入口接入 |

XB-07 异常的观测在 `build/sys-integ-review/xb07-trace.log`：进程收到 SIGILL，
程序计数器位于生成的 timed-fork coroutine actor 内的 `ud2` 指令。
修正后的单项日志在 `build/sys/107/xb_07.log`，包含种子 1–50 和最终 PASS。

| 验收 | 结果与日志 |
|---|---|
| SB smoke | 40 PASS / 0 FAIL；`build/sys-integ-review/sb-smoke-final.log` |
| SB full | 50 PASS / 0 FAIL；`build/sys-integ-review/sb-full-final.log` |
| XB-07 | 50 种子（1–50）、每种子双主各 100 笔，全部通过；`build/sys/full/xb_07.log` |
| 功能覆盖 | 99/99 分箱；`build/sys-integ-review/coverage-final.txt`，M0 写和 PLIC 3/4/7 按已确认契约不统计 |
| manifest 接入 | XB-01 通过 P0 `regress.run_test`；`build/sys-integ-review/manifest-final.log` |
| 真实顶层自测 | PASS；`build/sys-integ-review/selftest-real.log`、`build/sys/selftest/run.log` |
| 系统单元测试 | 14 个目录 × Verilator/Icarus，28 PASS / 0 FAIL；`build/sys-integ-review/system-units.log` |
| 共享检查器兼容 | cache IC-01、DC-03，2 PASS / 0 FAIL；`build/sys-integ-review/cache-checker.log` |
| 协议正负例 | 1 个正例和 5 个负例全部符合预期；`build/sys-integ-review/probes.log` |
| 顶层 lint | `--lint-only -Wall` 0 告警；`build/sys-integ-review/lint-final.log` |
| 风格 | RTL 47 文件、SB 24 文件均为 0 告警；`build/sys-integ-review/{rtl-style,sb-style}.log` |

系统单元测试的复现命令：

```sh
. ~/.local/opt/edrv32/env.sh
python3 -u - <<'PYTEST'
from pathlib import Path
import tools.regress as r
names = ('bus_sys_xbar', 'bus_rom', 'bus_sram', 'bus_apb_bridge', 'bus_apb_decoder',
         'apb_async_bridge', 'periph_clint', 'periph_plic', 'periph_sysctrl',
         'soc_reset_ctrl', 'periph_uart', 'periph_gpio', 'periph_i2c', 'sys_subsys_reset')
results = []
for name in names:
    path = (Path('verif/unit') / name / 'test.yaml').resolve()
    for simulator in ('verilator', 'iverilog'):
        results.append(r.run_test(path, r.read_test(path), simulator, 'smoke'))
print(f'S-I1 units: {sum(results)} PASS, {len(results)-sum(results)} FAIL')
raise SystemExit(not all(results))
PYTEST
python3 - <<'PYTEST'
from pathlib import Path
from tools.regress import read_test, run_test
path = Path('verif/block/sys_subsys/xb_01/test.yaml').resolve()
assert run_test(path, read_test(path), 'verilator', 'smoke')
PYTEST
verilator --lint-only -Wall -Irtl/include --top-module edrv32_sys_subsys \
  rtl/soc/edrv32_sys_subsys.v rtl/soc/edrv32_soc_reset_ctrl.v \
  rtl/bus/*.v rtl/periph/*.v rtl/common/edrv32_apb_async_bridge.v \
  rtl/common/edrv32_cdc_handshake.v rtl/common/edrv32_cdc_sync_bit.v \
  rtl/common/edrv32_reset_sync.v rtl/tech/edrv32_rom_boot.v rtl/tech/edrv32_ram_sram.v
python3 tools/check/verilog_style.py rtl/
```

SB 档位、自测、协议例和覆盖的命令见上方“命令”；cache 兼容检查按 S-V1
验收记录中的 `run_test` 调用分别选择 `cache/ic_01`、`cache/dc_03`。
本轮只运行上述系统相关测试和两项共享检查器兼容检查，未运行全仓 smoke/full。
