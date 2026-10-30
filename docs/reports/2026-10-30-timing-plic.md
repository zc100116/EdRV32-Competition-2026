# PLIC 判优与认领路径时序修复（T-PLIC1）

| 项目 | 条件 |
|---|---|
| 日期 | 2026-10-30 |
| 改前 RTL | `05088f4b13d5d8399f63deef48dc2760ad0f5bec` |
| 改后 RTL | `a338a6cce23fcec61de74427e0ac9b32cfad1c47` |
| PDS 起点数据 | `origin/win/20261030-10-b3-timing-rerun`（`2f43834d5d5a2759f200c7c4a86e020125748b61`）；`tasks/win/20261030-10-b3-timing-rerun/artifacts/{B3V,B3VN,B3R,B3F}/synthesis_paths.tsv`、`synthesis_path_detail.txt` |
| PDS 条件 | PDS 2022.2-SP6.1，PG2L200H-6/FBB676，clk_sys 10 ns；均为综合估算，本轮未运行改后 PDS |
| Yosys 条件 | 0.70+219，git `5053d0e26`；独立 `edrv32_periph_plic`，FPGA_MODE；`synth -flatten -noabc; abc -lut 6 -dress; opt_clean` |
| 本机仿真 | Verilator 5.020；单元测试另运行 Icarus Verilog 12.0 |
| 补充验证环境 | 用户提供的仿真主机（环境不记录） |
| 原始数据 | 本 worktree 的 `build/plic-timing/`，回归原始日志另见 `build/regress/`、`build/sys/`、`build/sys_cpu/` |

## PDS 改前路径

以下取各工程 clk_sys 中起点、终点均位于 PLIC 的最差 setup 路径；不能与 Yosys LUT6 级数直接等同。

| 工程 | 起点 → 终点（PLIC 内相对路径） | 裕量 ns | 逻辑级数 |
|---|---|---:|---:|
| B3V | `priority_r[2][1]` → `claimed_r[15]` / `pending_r[15]` | −0.074 | 17 |
| B3VN | `pending_r[1]` → `claimed_r[15]` / `pending_r[15]` | −1.020 | 19 |
| B3R | `priority_r[1][2]` → `pending_r[15]` | −1.077 | 18 |
| B3F | `pending_r[1]` → `axi_rdata_o[35]` | −1.785 | 20 |

`B3*_synthesis_paths.tsv`、`B3*_synthesis_path_detail.txt` 是上述原始数据在 `build/plic-timing/` 的副本。没有取得改后 PDS 裕量、Fmax 或器件资源，不以 Yosys 级数推算这些数字。

## RTL 与时序推导

15 源及一个空候选构成 16 叶树，候选携带 3 位优先级与 4 位源号。没有 pending 或未使能的候选优先级为 0；四层两两比较在同级时选左子树，因此同优先级时保留最小源号。树根优先级严格大于 threshold 时才输出非零源号，优先级 0 永不触发。

每拍把树根胜者寄存为 `winner_r`。CLAIM 在 AR 接受边沿以该寄存值同时形成读响应、清除对应 pending、置对应 claimed；RREADY 不参与认领判定，响应反压期间 RDATA 保持。没有增加屏蔽位或重认领检查。

设第一次合法单拍 CLAIM 的 AR 在边沿 N 接受，RREADY 始终为 1、ARVALID 连续保持：

| 边沿 | 接受前的状态 | 该边沿的动作 | 边沿后的状态 |
|---|---|---|---|
| N | RVALID=0，ARREADY=1，`winner_r=A` | 接受第一次 CLAIM；返回 A，清 pending[A]，置 claimed[A]；winner 仍采样清除前状态 | RVALID=1，ARREADY=0 |
| N+1 | RVALID=1，ARREADY=0 | 完成第一次 R 握手；winner 采样已清除 A 的 pending | RVALID=0，ARREADY=1，winner 已更新为 B 或 0 |
| N+2 | RVALID=0，ARREADY=1 | 最早接受第二次 CLAIM，使用 N+1 已更新的 winner | 返回 B 或 0 |

因此连续 CLAIM 的 AR 接受最早相隔 **2 个 clk_sys 周期**。N+1 不可能同时接受 AR，因为 `axi_arready_o = !axi_rvalid_o` 使用边沿前的 RVALID；同一边沿清除 RVALID 不会让该边沿接受第二笔。N+1 的 pending[A] 已为 0，claimed[A] 为 1，持续高电平的源也不会重置 pending。R 反压只会延长此间隔，第二次 CLAIM 不会重复认领 A；软件另行完成并使其重新 pending 属于一次新中断。

MEIP 在寄存 `winner_r` 的**同一个边沿**采样 `(winner_w != 0)`，是该寄存判优结果的非零标志；两者同时复位为 0，故每个边沿后均有 `irq_meip_o == (winner_r != 4'd0)`。设 pending、enable、priority 或 threshold 在 N 边沿更新，树根在 N 后组合稳定，MEIP 在 N+1 边沿反映该结果，与改前相同，仍为规格 2.5 的“输出打一拍”。若使用 `irq_meip_o <= (winner_r != 0)` 会多出一拍，本实现不这样连接；协调者已确认同级寄存的实现方式，规格保持不变。

地址表规定 PLIC 基址 `0x30000000`、大小 `0x00400000`，基址按 4 MiB 对齐。sys_xbar 仅转发这个窗口，因此合法内部事务的 `ARADDR - BASE` 等于零扩展的 `ARADDR[21:0]`。读译码保留全部 22 位及低两位精确匹配，PRIORITY、PENDING、ENABLE、THRESHOLD、CLAIM 地址及未列出偏移读零保持原样；优先级读改用同一 case 的并列分支。写偏移、AXI 通道控制、SIZE/LEN 错误检测和响应均保持原行为。

## Yosys 测量

前后使用同一工具和选项。改前源由 `git show 05088f4b:rtl/periph/edrv32_periph_plic.v` 保存到 `build/plic-timing/before/edrv32_periph_plic.v`，其余依赖只有未修改的 `rtl/common/edrv32_cdc_sync_bit.v` 和 `rtl/include/`。`before/netlist.ys` 与 `after/netlist.ys` 仅在 PLIC 源文件和输出目录上不同：

在改后 RTL 提交上可用以下命令重建脚本：

```sh
mkdir -p build/plic-timing/before build/plic-timing/after
git show 05088f4b:rtl/periph/edrv32_periph_plic.v > build/plic-timing/before/edrv32_periph_plic.v
cat > build/plic-timing/before/netlist.ys <<'EOF'
read_verilog -D FPGA_MODE -Irtl/include rtl/common/edrv32_cdc_sync_bit.v build/plic-timing/before/edrv32_periph_plic.v
hierarchy -top edrv32_periph_plic
synth -top edrv32_periph_plic -flatten -noabc
abc -lut 6 -dress
opt_clean
write_json build/plic-timing/before/netlist.json
stat
EOF
sed 's@build/plic-timing/before/edrv32_periph_plic.v@rtl/periph/edrv32_periph_plic.v@; s@before/netlist@after/netlist@g' build/plic-timing/before/netlist.ys > build/plic-timing/after/netlist.ys
```

实际命令（两次在仓库根目录执行）：

```sh
flock /tmp/edrv32-sim.lock yosys -Q -T -l build/plic-timing/before/netlist.log -s build/plic-timing/before/netlist.ys
flock /tmp/edrv32-sim.lock yosys -Q -T -l build/plic-timing/after/netlist.log -s build/plic-timing/after/netlist.ys
python3 tools/synth/netlist_paths.py build/plic-timing/before/netlist.json --start '\.Q\[' --end '\.(D|E)\['
python3 tools/synth/netlist_paths.py build/plic-timing/after/netlist.json --start '\.Q\[' --end '\.(D|E)\['
```

`netlist_paths.py` 统计 FF Q→D/E 的最大组合级数，包含数据和时钟使能终点，不把异步 IRQ 输入、复位或时钟作为 clk_sys 寄存器起点。该独立 PLIC 中所有 FF 均在 clk_sys 域。`reg_paths.json` / `.md` 是相同过滤结果的命名副本；`arbitration.json`、`claim.json`、`read.json` 为局部锥，生成命令在 `build/plic-timing/analyze.py`。

| 路径类别 | 改前 Yosys LUT6 级数 | 改后 Yosys LUT6 级数 | 改后最差起终点或说明 |
|---|---:|---:|---|
| PLIC 全部 clk_sys FF Q→D/E | 38 | 8 | `pending_r[14]` → `irq_meip_o` |
| 判优输入 → MEIP | 36 | 8 | `pending_r[14]` → `irq_meip_o` |
| 判优输入 → winner_r | 无此寄存级 | 8 | `pending_r[14]` → `winner_r[0]` |
| 判优输入 → claimed_r | 36 | 无组合路径 | 被 winner_r 截断 |
| 判优输入 → pending_r | 37 | 无组合路径 | 被 winner_r 截断 |
| 判优输入 → axi_rdata_o | 38 | 4 | 剩余为 PRIORITY 寄存器普通读：`priority_r[12][1]` → `axi_rdata_o[1]` |
| winner_r → 认领状态 / 读响应 | 无此寄存级 | 3 | `winner_r[2]` → `pending_r[15]` |
| ARADDR → 读响应（输入路径，另列） | 19 | 8 | `axi_araddr_i[0]` → `axi_rdata_o[0]` |

“判优输入”过滤为 `^(priority_r|pending_r|enable_r|threshold_r)(?:\[|$)`；每个终点以同名信号正则过滤，原始结果为 `{winner_r,irq_meip_o,claimed_r,pending_r,axi_rdata_o}_paths.json`。无组合路径表示寄存边界切断原锥，不表示零延迟的物理路径。改前全局最差为 `threshold_r[0]` → `axi_rdata_o[34]`，改后全局最差如上表。

| 通用 LUT6 代理资源 | 改前 | 改后 | 变化 |
|---|---:|---:|---:|
| LUT | 503 | 539 | +36 |
| FF | 222 | 226 | +4 |

增加的四个 FF 为 winner_r；资源是独立 PLIC 的通用映射结果，不是 PG2L200H 的最终 PDS 资源。

## 验证与性能

以下本机命令先执行 `. ~/.local/opt/edrv32/env.sh`；Verilator 仿真编译、Yosys 综合和 regress 用 `flock /tmp/edrv32-sim.lock` 串行执行，Verilator / regress 均 `-j 1`，没有使用 `--parallel`。风格与最终 lint 按协调者的锁规则调整直接运行；以下独立仿真复现命令也按新规则加锁。最终五组指定回归全部 PASS，结果见下表。风格检查为 `python3 tools/check/verilog_style.py rtl/periph`，6 文件、0 warnings；`build/plic-timing/style.log` 保存输出。对应 lint 命令如下，退出码 0、日志为空（0 warnings）：

```sh
verilator --lint-only -Wall -j 1 +incdir+rtl/include --top-module edrv32_periph_plic rtl/periph/edrv32_periph_plic.v rtl/common/edrv32_cdc_sync_bit.v
```

日志为 `build/plic-timing/lint.log`。


### 指定回归

```sh
flock /tmp/edrv32-sim.lock python3 tools/regress.py smoke --path verif/unit/periph_plic -j 1
flock /tmp/edrv32-sim.lock python3 tools/regress.py full --path verif/unit/periph_plic -j 1
flock /tmp/edrv32-sim.lock python3 tools/regress.py smoke --path verif/block/sys_subsys -j 1
flock /tmp/edrv32-sim.lock python3 tools/regress.py full --path verif/block/sys_subsys -j 1
flock /tmp/edrv32-sim.lock python3 tools/regress.py smoke --path verif/block/sys_cpu -j 1
```

回归由 `build/plic-timing/regress.py`、`regress_remaining.py` 和 `regress_sys_final.py` 串行编排；命令、退出码、含共享锁等待的墙钟时间分别在同名 JSON 文件中。输出依次为 `smoke_verif_unit_periph_plic.log`、`full_verif_unit_periph_plic.log`、`smoke_verif_block_sys_subsys.log`、`full_verif_block_sys_subsys.log`、`smoke_verif_block_sys_cpu.log`；各测试编译和仿真日志由原回归入口保存。

首次全目录 sys_subsys smoke 为 33 PASS、5 FAIL（`smoke_verif_block_sys_subsys_initial.log`）：IC-02、UA-02、UA-03 达到 runner 外层 180 s 超时；IC-03/04 的共享 group8 构建报 PCH 缺失/无效，未取得功能断言失败。PLIC 的 PL-02/03/05 均已 PASS。首次失败日志留存于 `build/plic-timing/initial-errors/{ic_02,ic_03,ic_04,ua_02,ua_03}_run.log`、`group8_compile.log`；相关模型完成构建后按原命令复跑，不修改 timeout、测试或 RTL。

补充验证按同一 commit、同一仓库判据执行，smoke 为 0 PASS / 38 FAIL、full 为 0 PASS / 51 FAIL，未形成可用的仿真验收结果，失败集中在构建阶段。没有修改 RTL 或测试迁就补充验证，回到本机按原命令复核。该批次的残留进程、构建目录和源副本已清理；只保留本助手归纳的测试名、结果、计数和耗时（`build/plic-timing/extra_validation_summary.json`），不回传原始文件。

| 路径 | 档位 | PASS / FAIL | 退出码 | 墙钟 s（含锁等待） |
|---|---|---:|---:|---:|
| `verif/unit/periph_plic` | smoke | 2 / 0 | 0 | 722.59 |
| `verif/unit/periph_plic` | full | 2 / 0 | 0 | 1401.82 |
| `verif/block/sys_cpu` | smoke | 3 / 0 | 0 | 3752.39 |
| `verif/block/sys_subsys` | smoke | 38 / 0 | 0 | 661.51 |
| `verif/block/sys_subsys` | full | 51 / 0 | 0 | 987.27 |

最终本机 sys_subsys smoke 为 38 PASS / 0 FAIL、full 为 51 PASS / 0 FAIL，包含全部 PL-01—PL-05；sys_cpu smoke 的 SC-02、SC-03、SC-06 均通过。首次失败的五项在相同 RTL 上复跑全部通过。以上墙钟包含较长的共享锁等待，不能作为 RTL 周期性能数据；周期对照见下一节。

### 前后性能对照

同一份临时 PL-01/PL-02 激励在改前快照和改后 RTL 上运行，两次均 PASS。基于现有 `verif/unit/periph_plic/tb.sv` 的单进程 AXI BFM，把第一组 CLAIM 改成 ARVALID/RREADY 连续为 1 的四笔读，其余寄存器、网关、非法事务检查沿用原 bench；没有改动入库测试。生成器 `build/plic-timing/make_fast_bench.py`、激励 `fast_tb.sv`，前后分别使用 `before_fast_obj/` 和 `fast_obj/` 编译目录。

| 测量项 | 改前 | 改后 |
|---|---:|---:|
| 合法 CLAIM 的最短 AR 接受间隔 | 2 clk_sys 周期 | 2 clk_sys 周期 |
| 最短间隔连续认领返回序列 | 5、1、2、0 | 5、1、2、0 |
| 上述四笔 AR 接受后采样时刻（bench 时间单位，周期=10） | 616、636、656、676 | 616、636、656、676 |
| 外部 IRQ 拉高到 MEIP 的采样边沿数 | 4 | 4 |
| AXI 接受边沿到已寄存 RVALID/RDATA 可用 | 同一接受边沿后 | 同一接受边沿后 |

IRQ 的四个边沿分别覆盖 CDC 第一级、CDC 第二级、置 pending、输出 MEIP；激励逐拍检查前 3 拍 MEIP=0、第 4 拍为 1。RVALID 占用期间检查 ARREADY=0，下一边沿 R 握手后检查 ARREADY=1，因此最短间隔数据来自实际总线激励，并与前述推导一致。没有把多一级 winner 寄存解释成多一级 AXI 响应延迟。

```sh
python3 build/plic-timing/make_fast_bench.py
flock /tmp/edrv32-sim.lock verilator --binary --timing --top-module tb -j 1 --Mdir "$PWD/build/plic-timing/before_fast_obj" -o sim +incdir+rtl/include build/plic-timing/before/edrv32_periph_plic.v rtl/common/edrv32_cdc_sync_bit.v build/plic-timing/fast_tb.sv
flock /tmp/edrv32-sim.lock build/plic-timing/before_fast_obj/sim
flock /tmp/edrv32-sim.lock verilator --binary --timing --top-module tb -j 1 --Mdir "$PWD/build/plic-timing/fast_obj" -o sim +incdir+rtl/include rtl/periph/edrv32_periph_plic.v rtl/common/edrv32_cdc_sync_bit.v build/plic-timing/fast_tb.sv
flock /tmp/edrv32-sim.lock build/plic-timing/fast_obj/sim
```

输出为 `before_fast_compile.log`、`before_fast_run.log`、`fast_compile.log`、`fast_run.log`；完整原 PL-01—PL-05 检查也均通过。
