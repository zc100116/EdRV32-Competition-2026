# CoreMark ISA 轨迹测量（C-E1）

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

## 测量结果

`.text` 是最终链接 ELF 的整段大小，包含启动、BSP、移植与已链接 libgcc；动态编码字节和取指字节只覆盖计时区。取指字节=8×动态组访问数，包含未执行的组内填充字节；不含错误路径取指或 cache 行填充。

| ISA | 动态指令 | .text / B | 动态编码 / B | 8B 组访问 | 取指 / B |
| --- | --- | --- | --- | --- | --- |
| rv32im | 2882005 | 12072 | 11528020 | 1627011 | 13016088 |
| rv32imc | 2882005 | 8738 | 8451820 | 1315808 | 10526464 |
| rv32im_zba_zbb | 2842425 | 11764 | 11369700 | 1637186 | 13097488 |
| rv32imc_zba_zbb | 2842425 | 8630 | 8485516 | 1350645 | 10805160 |
| rv32im_zba | 2862865 | 11876 | 11451460 | 1609922 | 12879376 |
| rv32imc_zba | 2862865 | 8674 | 8538060 | 1345582 | 10764656 |

相对本次 RV32IM 基线的变化（负数表示减少）：

| ISA | 动态指令变化 | .text 变化 | 取指字节变化 |
| --- | --- | --- | --- |
| rv32im | +0.0000% | +0.0000% | +0.0000% |
| rv32imc | +0.0000% | -27.6176% | -19.1273% |
| rv32im_zba_zbb | -1.3733% | -2.5514% | +0.6254% |
| rv32imc_zba_zbb | -1.3733% | -28.5123% | -16.9861% |
| rv32im_zba | -0.6641% | -1.6236% | -1.0503% |
| rv32imc_zba | -0.6641% | -28.1478% | -17.2973% |

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
