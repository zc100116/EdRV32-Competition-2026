# CoreMark 顺序配对机会测量（C-E3）

## 条件

| 项目 | 实测配置 |
|---|---|
| 软件输入 commit | `144949aa1cd5f30bd09fae442573d7a71dac4050`（C-V1） |
| 评估工具 commit | `281cb2888ab1f30a830385ac3e5277edb7200900` |
| 规格输入 commit | `581d84ff8a9f39f7c5260cbdd0c7d6ae9d654c6f`，协调者分支 `zc100116/SOC系统设计` 的 cpu-spec v0.5；cpu-testplan v0.1 |
| CoreMark | v1.01，子模块 commit `cfa9ab377835911f23d9b0831c7be302ed1f58de` |
| 编译工具 | xPack riscv-none-elf-gcc 15.2.0；GNU binutils 2.45 |
| 运行/分析工具 | Spike 1.1.1-dev；Python 3.12.3；仅 Python 标准库 |
| 器件和速度等级 | 不适用；Spike 正确路径提交轨迹，无 FPGA 映射 |
| 程序配置 | 未改动的 `sw/apps/coremark/` P0 移植；单上下文；静态 2K 工作区（各算法 666 字节）；seeds 0/0/0x66；10 次迭代；SRAM 起始 PC `0x10000000` |
| 编译配置 | 六种指定 ISA 均加 `_zicsr` 供计时 CSR 使用；`-mabi=ilp32 -O2 -std=c11 -ffreestanding -fno-builtin -ffunction-sections -fdata-sections`；链接 `--gc-sections`；完整参数见各组 `commands.txt` |
| Spike 配置 | 相应 ISA 加 `_zicsr_zifencei_zicntr_zihpm`；`--priv=m --pmpregions=0 --no-dm --disable-dtb -l --log-commits`；ROM 0/16KiB、SRAM 0x10000000/256KiB |

协调者确认的本次评估约定（原文）：

> 推荐六种 ISA 均运行 10 次迭代，动态统计窗口为 start_time 返回后至 stop_time 进入前（同时报告整程序 .text）；取指只统计正确路径连续访问的 8B 组（跨组 32 位指令计两组、控制转移重新计组）。C-E2 用顺序提交轨迹在每次组入口查询、分支解析后立即训练；BTB 每组只保留一条分支且每个已提交控制转移均分配/替换，其他容量自然扩展索引位数；RAS 在预测时更新并在该分支解析时恢复/按实际修正，不能测错误路径污染；C-E3 跨实际 taken 控制转移不配对，支持分支方案只新增条件分支，失败按 RAW > 结构冲突(槽0 CSR/系统) > 槽1类型 > 只有1条优先。

上述区间含调用 `stop_time` 的指令，不含 `stop_time` 函数体。取指重新计组针对实际 taken 控制转移；未跳转的条件分支继续复用顺序组。

六组均在 Spike 正常退出，输出 seedcrc=e9f5、list=e714、matrix=1fd7、state=8e3a、final=fcaf；list/matrix/state 与 CoreMark 的已知结果一致。控制台同时输出执行不足 10 秒和 `Errors detected`，因此本报告不提供官方 CoreMark 分数、CoreMark/MHz 或 RTL 周期数。P0 控制台的 Compiler flags 为固定字符串，实际六组编译参数以 `commands.txt` / `build.log` 为准。上游 CoreMark 的既有 GCC maybe-uninitialized 告警在 `build.log` 中保留，依 P0 已批准的规则对上游代码不启用 `-Werror`；本地 BSP/移植代码保留 `-Werror`。

## 模型与统计口径

顺序贪心取最老两条候选；成功则消费两条，否则消费最老一条。槽 1 基础只支持 ALU（含 LUI/AUIPC 和启用的 Zba/Zbb ALU 指令）；对比方案另支持条件分支，JAL/JALR、访存、乘除法及 CSR/系统仍不进入槽 1。组内 RAW 禁止，x0 不产生 RAW；同目的寄存器的 WAW 允许。压缩指令按实际显式与隐含源寄存器统计，例如 C.ADDI 读写同一寄存器。

跨实际 taken 转移以及轨迹末尾视为仅有一条候选。存在两条顺序候选时，互斥失败原因按 RAW > 结构冲突（槽 0 为 CSR/系统/FENCE）> 槽 1 类型统计；没有第二条候选时计“只有 1 条”。不存在真实 IB 占用或时序信息，因而“只有 1 条”只表示上述序列边界，不能当作前端断流计数。统计不限制取指组边界，IB 可拼接相邻组。

配对指令比例=2×成功对数/动态指令数；双发射组比例=成功对数/发射组数；序列 IPC=动态指令数/发射组数。成功对数加四类互斥失败数等于发射组数，2×成功对数加四类失败数等于动态指令数。不建模 load-use、乘除法、分支误预测、cache 等时序，序列 IPC 不是实测 CPU IPC。

## 测量结果

| ISA | 槽1条件分支 | 成功对数 | 发射组 | 配对指令比例 | 双发射组比例 | 序列 IPC |
| --- | --- | --- | --- | --- | --- | --- |
| rv32im | 0 | 723332 | 2158673 | 50.1964% | 33.5082% | 1.335082 |
| rv32im | 1 | 846639 | 2035366 | 58.7535% | 41.5964% | 1.415964 |
| rv32imc | 0 | 723332 | 2158673 | 50.1964% | 33.5082% | 1.335082 |
| rv32imc | 1 | 846639 | 2035366 | 58.7535% | 41.5964% | 1.415964 |
| rv32im_zba_zbb | 0 | 714072 | 2128353 | 50.2439% | 33.5504% | 1.335504 |
| rv32im_zba_zbb | 1 | 836519 | 2005906 | 58.8595% | 41.7028% | 1.417028 |
| rv32imc_zba_zbb | 0 | 714072 | 2128353 | 50.2439% | 33.5504% | 1.335504 |
| rv32imc_zba_zbb | 1 | 836519 | 2005906 | 58.8595% | 41.7028% | 1.417028 |
| rv32im_zba | 0 | 720652 | 2142213 | 50.3448% | 33.6405% | 1.336405 |
| rv32im_zba | 1 | 843959 | 2018906 | 58.9590% | 41.8028% | 1.418028 |
| rv32imc_zba | 0 | 720652 | 2142213 | 50.3448% | 33.6405% | 1.336405 |
| rv32imc_zba | 1 | 843959 | 2018906 | 58.9590% | 41.8028% | 1.418028 |

失败原因计数（每个单发射组只计一类）：

| ISA | 槽1条件分支 | 组内 RAW | 结构冲突 | 槽1类型 | 只有1条 |
| --- | --- | --- | --- | --- | --- |
| rv32im | 0 | 518987 | 0 | 545039 | 371315 |
| rv32im | 1 | 535917 | 0 | 381031 | 271779 |
| rv32imc | 0 | 518987 | 0 | 545039 | 371315 |
| rv32imc | 1 | 535917 | 0 | 381031 | 271779 |
| rv32im_zba_zbb | 0 | 498507 | 0 | 544459 | 371315 |
| rv32im_zba_zbb | 1 | 515357 | 0 | 381961 | 272069 |
| rv32imc_zba_zbb | 0 | 498507 | 0 | 544459 | 371315 |
| rv32imc_zba_zbb | 1 | 515357 | 0 | 381961 | 272069 |
| rv32im_zba | 0 | 504967 | 0 | 545279 | 371315 |
| rv32im_zba | 1 | 521897 | 0 | 381271 | 271779 |
| rv32imc_zba | 0 | 504967 | 0 | 545279 | 371315 |
| rv32imc_zba | 1 | 521897 | 0 | 381271 | 271779 |

同一 ISA 的两种规则差值（支持条件分支减不支持）：

| ISA | 成功对数差 | 配对指令比例差 / 百分点 | 序列 IPC 差 |
| --- | --- | --- | --- |
| rv32im | 123307 | +8.5570 | +0.080882 |
| rv32imc | 123307 | +8.5570 | +0.080882 |
| rv32im_zba_zbb | 122447 | +8.6157 | +0.081524 |
| rv32imc_zba_zbb | 122447 | +8.6157 | +0.081524 |
| rv32im_zba | 123307 | +8.6142 | +0.081622 |
| rv32imc_zba | 123307 | +8.6142 | +0.081622 |

## 复现与原始数据

在评估工具 commit 上从仓库根目录执行：

```sh
. ~/.local/opt/edrv32/env.sh
git submodule update --init third_party/coremark
python3 tools/cpu/eval/test_models.py
python3 tools/cpu/eval/run_coremark.py
python3 tools/cpu/eval/analyze.py
```

原始数据根目录为 `build/cpu/eval/`（生成物不入库）。`versions.txt` 记录输入 commit 和工具版本；每个 `<isa>/` 下保存 `commands.txt`、`build.log`、`coremark.elf`、`coremark.map`、`numeric.dis`、`sections.txt`、完整 `spike.log`、`console.log`、计时区 `roi.trace` 和 `branches.csv`。汇总表为 `isa.csv`、`pairing.csv`、`predictor.csv`，后者保留全部 162 组配置的原始计数和未舍入百分比。

验证命令 `python3 tools/cpu/eval/test_models.py`：7 项通过；`python3 -m py_compile tools/cpu/eval/*.py` 与 `git diff --check` 通过。此次只新增 Python 工具和 Markdown，未修改 RTL，Verilog 风格检查及 Verilator lint 不适用。无先前同口径报告；本次为首次基线，组间比较均来自同一次测量。
