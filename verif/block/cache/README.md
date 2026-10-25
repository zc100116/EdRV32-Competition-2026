# Cache 模块级验证

依据 cache-spec v0.1、cache-testplan v0.1；初版由独立验证 worker 编写，未读取 `rtl/cache/`；本分支随后完成真实 RTL 联调。

环境入口 `edrv32_cache_env.sv` 连接 `edrv32_icache`、`edrv32_dcache` 和
`edrv32_cache_ctrl` 的规格端口。core 驱动包含定向事务、连续命中流和可配置随机流；
APB 驱动直接访问维护控制器。`edrv32_cache_core_checker.sv` 检查命中时序、kill、
设备提交顺序、地址、大小和写数据。维护测试中 STATUS 地址作为设备事务地址，
AXI 模型提供设备数据；真实控制器寄存器由 APB 驱动检查，环境不包含 sys_xbar/APB 桥。

`verif/common/` 下新增：

- `edrv32_axi64_if.sv`：完整 AXI64 五通道接口。
- `edrv32_axi64_memory_pkg.sv`：共享平坦物理内存和独立架构内存，按字节寻址，
  DDR 两个地址窗口映射到同一物理字节。未写字节由地址确定初始值。
- `edrv32_axi64_memory.sv`：每方向一笔事务，随机 READY、响应延迟和响应间隔，
  R/B 停顿时保持负载；按行地址注入读/写 SLVERR。
- `edrv32_axi64_checker.sv`：五通道 VALID/负载保持、ID、突发类型、行大小/对齐、
  单拍大小、WSTRB、LAST、事务并发和响应顺序。

参考模型在提交 store 时立即更新；load 比较有效访问字节。整体 clean 后比较两个
内存已写字节的并集，能够检查未提交 store 导致的额外写入。所有失败打印期望、实际和时刻并退出非零。

## 运行（真实 RTL 联调）

`environment.f` 现在包含真实 Cache/RAM RTL 和验证环境；所有路径相对所在
file list。P0 清单使用 top、files、defines、parameters、software、timeout、pass、tier、
simulator 字段。运行：

```sh
. ~/.local/opt/edrv32/env.sh
make smoke
make full
make lint
python3 tools/check/verilog_style.py rtl/
```

单项示例：

```sh
mkdir -p build/cache/ic_01
verilator --binary --timing -Wall -DSIM_MODE \
    --top-module edrv32_cache_ic_01_tb \
    -F verif/block/cache/ic_01/files.f --Mdir build/cache/ic_01 -o sim
build/cache/ic_01/sim
```

`ic_08_smoke` / `dc_15_smoke` 各运行种子 1–2；`ic_08` / `dc_15` 的 full
清单各运行种子 1–50。每个种子重新复位 DUT、清空物理和架构内存，并输出
`RANDOM` 与 `PASS seed`。顶层参数 `SEEDS` 选择种子数；单种子调试仍可用
`+SEED=17 +COUNT=300 +BASE=10000000 +CONFLICT_LINES=6`，以及
`+STORE_PERCENT=50 +KILL_PERCENT=15`。PF-01/02 保持 perf 档位。

`stub/` 保留初版验证环境的桩自测产物；正式 smoke/full 不使用桩。

## 测试映射

| 编号 | 目录 | 内容 |
|---|---|---|
| IC-01 | `ic_01/` | 冷启动顺序取指：每行先缺失后命中；命中时每周期返回一个 |
| IC-02 | `ic_02/` | 三个映射到同一组的行轮流访问，检查 LRU 替换顺序 |
| IC-03 | `ic_03/` | ROM 取指不装入 cache（再次取同一地址仍然发出 AXI 读） |
| IC-04 | `ic_04/` | 取指访问非可执行区域：返回错误，不发出 AXI 事务 |
| IC-05 | `ic_05/` | 缺失期间 `ic_kill_o`：响应被丢弃，该行仍然装入 |
| IC-06 | `ic_06/` | `ic_inv_o` 后全部重新缺失 |
| IC-07 | `ic_07/` | 填充返回 SLVERR：请求返回错误，该行不装入，下一次访问重新缺失 |
| IC-08 | `ic_08/` | 随机取指流（含 kill），AXI 随机延迟和反压，每次返回的数据与内存一致 |
| DC-01 | `dc_01/` | load 命中下一周期返回；连续 load 每周期一个 |
| DC-02 | `dc_02/` | store 命中后提交，数据写入；字节、半字、字三种宽度和所有对齐位置 |
| DC-03 | `dc_03/` | 写缓冲旁路：store 提交后紧跟同一字的 load（全覆盖和部分覆盖） |
| DC-04 | `dc_04/` | 连续 store 不停顿 |
| DC-05 | `dc_05/` | 缺失替换干净行：只有填充突发 |
| DC-06 | `dc_06/` | 缺失替换脏行：先写回（4 拍，数据正确），再填充 |
| DC-07 | `dc_07/` | store 缺失：写分配，填充后合并 store 数据 |
| DC-08 | `dc_08/` | `dc_kill_o`：被取消的 load 不返回，被取消的 store 不改变内存；正在进行的填充继续完成 |
| DC-09 | `dc_09/` | 设备 load/store：只在提交后发出；store 收到 B 后才返回；WSTRB 和数据落在正确字节 |
| DC-10 | `dc_10/` | 设备访问被 kill：不发出总线事务 |
| DC-11 | `dc_11/` | 对 ROM 的 store 返回访问错误；对未映射地址的 load/store 返回访问错误，且都不发出总线事务 |
| DC-12 | `dc_12/` | DDR 非缓存别名：不装入 cache，每次都发出单拍事务 |
| DC-13 | `dc_13/` | 填充返回错误：请求返回错误，该行不装入 |
| DC-14 | `dc_14/` | 设备访问返回错误：请求返回错误 |
| DC-15 | `dc_15/` | 随机 load/store 流（组冲突密集、kill 随机、AXI 随机延迟和反压），全程与参考模型一致，结束时整体 clean 后内存一致 |
| MT-01 | `mt_01/` | 范围 clean：范围内的脏行被写回、清脏位；范围外的脏行不变；行首、行尾不对齐的范围 |
| MT-02 | `mt_02/` | 范围 invalidate：范围内的行失效，脏数据不写回 |
| MT-03 | `mt_03/` | 范围 clean+invalidate |
| MT-04 | `mt_04/` | 整个 D$ clean |
| MT-05 | `mt_05/` | FENCE.I 序列：`dc_clean_all_o` 完成后 `ic_inv_o`；之后取指能看到 store 写入的新代码（I$ 与 D$ 共用同一个 AXI 内存模型） |
| MT-06 | `mt_06/` | FENCE：写缓冲非空时等到排空 |
| MT-07 | `mt_07/` | 维护期间可缓存请求不被接受；设备请求（轮询 STATUS）照常完成 |
| MT-08 | `mt_08/` | OP_SIZE = 0 立即完成；BUSY 期间写 OP_CMD 无效果 |
| MT-09 | `mt_09/` | 写回返回错误：IRQ_STAT.bit1 置位、ERR_ADDR 正确、`irq_o` 按 IRQ_EN 输出；写 1 清除 |
| PF-01 | `pf_01/` | 命中流的吞吐 |
| PF-02 | `pf_02/` | 缺失代价（SRAM 时序的内存模型，无反压，干净替换） |

## 覆盖

每次运行输出 `COVER name=count`，统计命中 load/store、缺失 clean/dirty × load/store、
全/部分写缓冲旁路、三种 kill 时刻、九个 PMA 区域（含未映射）、四个维护命令、
FENCE.I、FENCE，以及填充/设备/写回错误。`instruction_hits` 是附加的 I$ 命中统计。

```sh
python3 verif/block/cache/coverage.py build/cache/selftest/run.log \
    > build/cache/selftest/coverage.txt
```

真实 full 回归将所有日志作为参数传入相同命令；报告逐箱输出 `covered/uncovered`。
桩不具备完整 cache 行为，因此自测报告中命中、替换、旁路和错误等分箱为零是预期结果；
真实 RTL 的覆盖收敛属于 K-I1，不在桩阶段声称覆盖完成。

## 已确认的规格问题

协调者通过 ask 确认：I$ ROM 取指允许单拍 SIZE=3（SoC 单拍 SIZE≤2 针对数据侧）；
覆盖分箱采用命中 × load/store 两箱、缺失 × clean/dirty × load/store 四箱，空路填充计 clean。
无需更改本 worker 归属之外的规格文件。

K-I1 已确认：P0 标量清单格式与相对 file-list 路径；RTL 使用规格的平坦端口；
OP_SIZE=0 仅适用于范围命令 1–3，整体 clean 忽略 OP_ADDR/OP_SIZE；新写回错误
优先于同拍 RW1C。core 驱动仅在 E 级请求本周期确定进入 M 时发出 dc_req_valid。

## 原 K-VERIF 桩验证记录（合入前，2026-10-25）

工具：Verilator 5.020；分支 `zc100116/task-cache-verif`，开发基点
`7894b4438c62880b3984830ebb4b79a9dd4a6e66`，源代码随本文件一起提交。

- 34 个功能/性能顶层全部通过 `--binary --timing -Wall` 桩编译。
- 34 个功能/性能顶层加 selftest，共 35 个顶层，最终 `--lint-only --timing -Wall`
  为零告警。共享行为内存的原子字节更新仅局部豁免 BLKSEQ，未关闭其他诊断。
- selftest 种子 1、17、101：全部 PASS，退出码 0；记录首个随机数和种子便于复现。
- `+BAD_AXI_LEN`：时刻 85 报出 `expected=3 actual=2`，退出码非零。
- `+BAD_CORE_HIT`：时刻 85 报出 `expected=1 actual=0`，退出码非零。
- 三种子覆盖汇总：缺失/等待时 kill 24 次，设备等提交时 kill 22 次；PMA ROM/SRAM/CLINT
  分别 126/6/141 次；范围 clean、FENCE.I、FENCE 各 3 次。其余分箱尚未覆盖，需真实 RTL。

原始数据：`build/cache/compile-summary.txt`、各测试目录下 `compile.log` / `lint.log`、
`build/cache/selftest/seed-{1,17,101}.log`、`bad_axi_len.log`、`bad_core_hit.log`、
`coverage.txt`。当时分支尚无 `tools/check/`，已检查全部 44 个 SystemVerilog 文件的
100 列限制、空格缩进、接口分组和命名连接；仓库 RTL 风格工具已由 K-I1 在 P0 集成后补跑，正式结果见下方联调记录。

## K-I1 联调修复分类

- 集成适配：按 P0 标量 schema 重写清单，扁平 file lists 的路径相对自身目录，
  同时适用于 P0 展开与直接 Verilator `-F`；随机顶层通过 SEEDS 执行 smoke 2 个、
  full 50 个独立复位的种子。
- 测试错误（维护启动）：MT-07/08 在 APB OP_CMD 返回后立即要求 maint_busy=1，
  忽略了 cache_ctrl mailbox 的 valid/ready 接受周期；在 890 时刻观察到 expected=1、
  actual=0。改为先等 maint_req_valid 被接受，再检查维护执行。
- 测试错误（总线归属）：维护可与设备请求共存，原 core 驱动却将总 AW 计数变化
  作为设备提前提交；940 时刻出现 device-before-commit AW expected=0、actual=1，
  实际为合法四拍维护写回。现按 LEN=0 的单拍设备事务计数，core checker 也仅用
  已接受的设备 AW 检查其 W 数据/B 完成；四拍写回仍由 AXI checker 和内存比对检查。
- 测试合同修正：MT-07 探测维护对可缓存地址的 READY 时只驱动地址，不给尚未
  进入 M 的 E 级指令发送 request-valid，遵守 K-I1 确认的 core 接口约定。
- 覆盖计数修正：随机调用未声明 expected-hit 并不代表实际 miss，kill 分箱改为
  取消完成后按实际读事务分类；PMA 错误/已取消请求不计作 instruction_hits。

MT-07 原始失败记录为 `build/cache/mt_07_failure_mailbox.log` 和
`build/cache/mt_07_failure_bus_ownership.log`，修复后的窄范围测试 PASS；
`build/cache/mt_07_debug-run.log` 记录该结果。以上均未改变 Cache 的维护或设备行为。
新增 RTL 只有任务要求的生成 PMA 常量接入与 dc_wb_event_o 输出。

## K-I1 验收结果（2026-10-25）

正式 RTL/测试源快照：`a5ec3be`；基线 `main` 为 `7ada537`，随后仅更新报告及
未被正式回归使用的 stub file list。工具为环境脚本提供的 Verilator 5.020，
P0 单元测试另使用其清单规定的 Icarus。无工具代码、共享头文件或规格文件改动。

从仓库根目录执行：

```sh
. ~/.local/opt/edrv32/env.sh
make smoke
make full OPT_FAST=-O0 OPT_SLOW=-O0
python3 tools/regress.py perf
make lint
python3 tools/check/verilog_style.py rtl/
python3 verif/block/cache/coverage.py build/regress/full/block/cache/*/verilator/run.log
```

OPT_FAST/OPT_SLOW 仅改变已生成 C++ 的编译优化级别，不改变 HDL 测试或仿真周期。
另外按 `rtl/cache/README.md` 中的三个顶层命令执行 Cache 专属 `--lint-only -Wall`，
均为 0 告警；额外核对的 MT-07 / DC-15_smoke 环境也通过 `--lint-only --timing -Wall`。

| 项目 | 结果 |
|---|---|
| smoke | 44 PASS / 0 FAIL（固定源码最后一轮直接 make smoke） |
| full | 56 PASS / 0 FAIL（35 个 Cache block 配置、5 个 Cache unit、16 个 P0 仿真配置） |
| perf | 2 PASS / 0 FAIL |
| make lint / 全 RTL 风格 | 17 文件，0 告警；公共 RTL lint 与 Cache 专属 lint 均通过 |
| IC-08 / DC-15 full | 各 50 个独立种子，唯一序列均为 1–50，每个 300 个请求；全部 PASS |
| dc_wb_event_o | full 总计 5590 个脉冲，对应 5590 次四拍写回 AW；逐周期一致 |
| 新增单元检查 | AW 反压期间不提前脉冲，替换/维护共 4 个事件；设备 AW 不计入 |

full 按框架规定包含 smoke 配置，因此还重跑各两个随机 smoke 种子。
所要求的 29 个功能分箱全部覆盖，另有 instruction_hits 附加统计：

```text
bypass[0]: 1 covered
bypass[1]: 2 covered
command[0]: 9 covered
command[1]: 1 covered
command[2]: 1 covered
command[3]: 2 covered
command[4]: 63 covered
command[5]: 2 covered
error[0]: 2 covered
error[1]: 2 covered
error[2]: 1 covered
hit[0]: 2179 covered
hit[1]: 2248 covered
instruction_hits: 4386 covered
kill[0]: 1566 covered
kill[1]: 3135 covered
kill[2]: 10 covered
miss[store=0][dirty=0]: 2087 covered
miss[store=0][dirty=1]: 2314 covered
miss[store=1][dirty=0]: 2164 covered
miss[store=1][dirty=1]: 2372 covered
pma[0]: 45 covered
pma[1]: 31322 covered
pma[2]: 80 covered
pma[3]: 1 covered
pma[4]: 2 covered
pma[5]: 1 covered
pma[6]: 1 covered
pma[7]: 4 covered
pma[8]: 3 covered

```

kill[1] 汇总缺失/读等待期间的取消；IC-05 和 DC-08 另外在 AR 握手之后定向取消，
明确验证正在进行的填充继续完成、响应被丢弃，并在之后命中该行。
性能结果：I$、D$ load、D$ store 均在 16 周期接收 16 个命中请求；冷缺失
请求至返回为 8 周期，AXI 往返为 2 周期，外部可见上界 11 周期，判定 PASS。

日志：`build/cache-integ-smoke-accepted.log`、`build/cache-integ-full.log`、
`build/cache-integ-perf.log`、`build/cache-integ-lint-final.log`、
`build/cache-integ-coverage.txt`；逐配置编译/运行日志在
`build/regress/{smoke,full,perf}/`。构建产物均未入库。

已发现的功能性失败均为上文两项测试错误，没有为通过测试更改维护、设备、
写缓冲或错误处理 RTL；新增 RTL 为经要求的 PMA 常量接入与写回事件端口。
局部 lint 豁免仅针对共享生成头中无关的 UNUSEDPARAM，以及 testbench 对异步
DUT 复位进行同步观察的 SYNCASYNCNET；原子字节内存的既有 BLKSEQ 豁免保持不变。
