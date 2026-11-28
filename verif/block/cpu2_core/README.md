# CPU v2 NONE 核级 smoke

范围：`ISSUE_WIDTH=1/2`、`FPU_FORMAT="NONE"`。F/FD、V01 比较器接入、V02/V03
完整回归不在本次结果中；这里的 PASS 是程序自检/tohost 与定向断言结果。

## 运行

先初始化仓库锁定的 `third_party/coremark` 子模块，并加载 GCC 15.2.0 工具环境。
仿真在独立仿真目录执行；本地退回运行时按 Task 使用 `flock` 和单进程构建。

```sh
. ~/.local/opt/edrv32/env.sh
python3 tools/regress.py smoke --path verif/block/cpu2_core
python3 tools/regress.py perf --path verif/block/cpu2_core
```

也可分步构建和运行：

```sh
python3 tools/cpu/build_cpu2_tests.py --suite isa
python3 tools/cpu/run_cpu2_core.py --width 1
python3 tools/cpu/run_cpu2_core.py --width 2
python3 tools/cpu/build_cpu2_tests.py --suite coremark
python3 tools/cpu/run_cpu2_core.py --width 1 --program coremark
python3 tools/cpu/run_cpu2_core.py --width 2 --program coremark
```

程序/ELF/内存镜像位于 `build/cpu2_core/programs/`；构建和逐程序日志在
`build/cpu2_core/w{1,2}/`。`--no-build` 复用已构建仿真器，`--program` 选择一个程序。
BFM 使用共享 AXI64 字节内存，关闭随机等待/错误注入，保留固定读返回和通道握手等待。
APB/IRQ/mtime 输入为零。ELF 经 `elf2mem.py` 转成后门加载的绝对地址字节镜像。
终止观察退休 store 的 tohost 地址和值，避免把仍在 D$ 中的可缓存结果漏掉。
`+TRACE=<文件>` 记录退休 PC/编码/整数目的和值；`+CONTROL_LOG` 记录恢复/分配诊断。

top 用三个既有 `edrv32_reset_copy` 区域（frontend/I$、execute、commit/D$），
同一沿延后一拍释放，不增加参数。复位公共源由协调者提交 `a778bc2a1` 加入 cpu2.f。

风格和 top lint 的复现命令：

```sh
python3 tools/check/verilog_style.py rtl/cpu2/*.v
cd rtl/filelists
verilator --lint-only -Wall -DSIM_MODE --top-module edrv32_cpu2_top -GISSUE_WIDTH=1 -f cpu2.f
verilator --lint-only -Wall -DSIM_MODE --top-module edrv32_cpu2_top -GISSUE_WIDTH=2 -f cpu2.f
```

## 本次验证

实现与测试提交：`86f413ddf2c7ccb46b69a37c0527411f906201b5`（复位公共源基线 `a778bc2a1`）。
工具：GCC 15.2.0，ISA `rv32im_zicsr_zifencei_zba`；Verilator 5.051 devel
（v5.050-99-gf8fb1d664）。协调者确认统一补上规格 2.1 已实现的 Zifencei。

| 检查 | ISSUE_WIDTH=1 | ISSUE_WIDTH=2 |
|---|---|---|
| Verilog 风格 / top `--lint-only -Wall` | 0 告警 | 0 告警 |
| 40 个适用 rv32ui | PASS | PASS |
| 8 个 rv32um、SH1ADD/SH2ADD/SH3ADD | PASS | PASS |
| smoke、trap、redirect | PASS | PASS |
| CoreMark 10 次迭代、CRC | PASS | PASS |

协调者确认排除 `rv32ui/ma_data.S`：它要求未对齐数据访问成功/仿真，与规格 2.1
自然对齐/异常行为不符。`trap.S` 另测未对齐 load/store cause 4/6 与 mtval。
本轮共 53 个核级程序/宽度。恢复拍旧 IB 和 CSR FENCE.I 缺陷与复现测试见
`docs/debug/2026-11-28-cpu2-core-integration.md`。

观察端口适配后的原单元测试：31 项 Verilator PASS，涵盖 alu/branch/issue/frontend
六配置、commit/csr 六配置合并测试、I$/D$ 对应配置。新增 ALU/branch 锁取消和分支
管线 tag 别名复现后，相关六配置再次通过。三个算法 CRC 为 e714/1fd7/8e3a，
10 次迭代最终 CRC fcaf；两宽均退休 2,477,565 条指令。

## 授权补充的模块观察输出

所有端口仅供观察，top 的 IP 外部端口不变；不用层次引用，未复制架构状态。

| 模块 | 输出（省略 `_o`） |
|---|---|
| ib/frontend | ib_count（`clog2(IB_DEPTH+5)`）；frontend 另有 frontend_active[1:0]（F2/F1） |
| issue | issue_hpm[7:0]（事件5..12）、issue_pair_cause[2:0]、issue_wait |
| alu/branch | debug_mem_valid[1:0]；branch 另有 trace_branch_pc[31:0]/stage[1:0]/cause[1:0] |
| commit | 既有内部退休/访存/陷阱 trace；commit_mem_wait/div_wait/device_wait |
| csr | trace_csr_valid/addr/data（I/12I/32I）、trace_fflags[4:0]/frm[2:0]/fs[1:0] |
| icache/dcache | debug_miss；D$ 另有 trace_mem_effect_valid/tag/addr/data/mask（1/T/32/32/4） |

顶层保留两槽宽度的 `trace_*_w`，单发射高槽为零；源 tag、重定向及每 beat 副作用齐全。
HPM 事件仅在 CSR 中寄存一拍。NONE 无 FPU 例化，未用的物理 FP 端口按冻结补充接零。

## CoreMark 条件与数字

使用仓库锁定的 EEMBC CoreMark `cfa9ab377835911f23d9b0831c7be302ed1f58de`、既有
`sw/apps/coremark` 端口、SRAM 代码/数据、10 次迭代、静态内存、单上下文。
编译选项：`-O3 -funroll-all-loops -finline-limit=600 -falign-functions=4
-falign-jumps=4 -falign-loops=4 -ffreestanding -fno-builtin -ffunction-sections
-fdata-sections -march=rv32im_zicsr_zifencei_zba -mabi=ilp32`。
计时窗口为 `start_time` 首指令退休至 `stop_time` 首指令退休，计入真实缓存影响。
CoreMark/MHz = `10 * 1000000 / 窗口周期`，仅记录，不作为验收门槛。

| ISSUE_WIDTH | 窗口周期 | CoreMark/MHz | 模型参考 |
|---|---:|---:|---:|
| 1 | 3,771,680 | 2.651338 | 3.74 |
| 2 | 3,315,758 | 3.015902 | 6.25 |

短迭代会打印不足 10 秒的标准 CoreMark 提示；本次是核级 smoke 和周期测量，
不声称符合 CoreMark 正式成绩条件。脚本检查实际 list/matrix/state CRC 错误。

提交时 Git 自动 gc 报告 commit-graph 中三个历史提交对象缺失；实现提交已成功生成，
未改仓库维护元数据，此项交协调者处理。
