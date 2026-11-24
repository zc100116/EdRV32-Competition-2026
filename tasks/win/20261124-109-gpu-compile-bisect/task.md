# 卡 109：定位 GPU RTL 的 PDS Compile 内部错误

## 1. 目标

找出让 PDS rtl-infer 崩溃（`InferWriteMode.cpp:2983`，`E: Flow-0189`）的模块和数组。给出能复现的最小写法，以便 Linux 端改写 RTL。

## 2. 输入

| 项 | 内容 |
|---|---|
| 代码 | 用 `git log -1 --format=%H origin/zc100116/gpu-dev -- tasks/win/20261124-109-gpu-compile-bisect` 找到本卡的提交，从它拉出 `win/20261124-109-gpu-compile-bisect`，记录 HEAD |
| 复现脚本 | 卡 107 结果分支中的 `tasks/win/20261124-107-gpu-board/artifacts/compile/compile-gpu-only.tcl`（顶层 `edrv32_gpu`，环境变量 `EDRV32_REPO`、`BOARD_GPU_IPCORE`） |
| 已知事实 | 整片和 GPU-only 都在打印 `Found Ram strobe_r`（write_dma）后崩溃；write_dma 原模块单独编译通过，所以崩溃发生在之后处理的另一个阵列 |

## 3. 环境

PDS 2022.2-SP6.1，PG2L200H-6 FBB676，卡 107 已建好的 board_gpu 工程的 ipcore 目录。全部步骤由 **Windows Codex（命令行）** 完成，不需要用户操作 GUI。

## 4. 需要的 IP

无新 IP，使用卡 107 已生成的 IP。

## 5. 操作步骤

| 步骤 | 执行者 | 内容 |
|---|---|---|
| 0 | C | 按第 2 节拉分支，记录 HEAD |
| 1 | C | 复制 `compile-gpu-only.tcl` 为 `compile-one.tcl`。文件列表不变，只把 `-top_module edrv32_gpu` 改成读环境变量 `TOP`：`compile -top_module $::env(TOP) ...` |
| 2 | C | 对 `rtl/gpu/` 下除 `edrv32_gpu` 以外的 35 个模块，逐个设置 `TOP=<模块名>`，各用独立的空工作目录运行 `pds_shell.exe -file compile-one.tcl -work_dir <目录> -project_name m_<模块名>`。记录每个模块的结果：通过 / 崩溃 / 其他错误，以及 rtl-infer 阶段最后一条 `Found Ram` 信息 |
| 3 | C | 对每个崩溃的模块：在仓库外复制该文件，逐步删除或简化其中的数组写入（每次只改一处），直到找到删掉就不再崩溃的那一处。记录数组名、源码行号，以及该数组的全部写入和读取语句（原文） |
| 4 | C | 如果第 2 步没有模块崩溃（只有组合起来才崩溃），在 `edrv32_gpu.v` 的副本中逐个把子模块实例替换为只保留端口的空模块，二分到最少的子模块组合，再按第 3 步缩小到具体数组 |
| 5 | C | 填写 result.md，把第 3 步的最小样例（`.v`，几十行以内）放进 `artifacts/`，推送分支 |

## 6. 产物

放在 `tasks/win/20261124-109-gpu-compile-bisect/artifacts/`：
- `module-scan.txt`：35 个模块各一行（模块名、结果、最后一条 Found Ram、耗时）；
- `min_repro_<模块>.v`：最小复现样例；它的编译日志节选 `min_repro_<模块>.log`（rtl-infer 段）；
- 不提交 PDS 工程目录和完整日志。

## 7. 通过判据

找到至少一个能单独复现崩溃的模块，并定位到具体数组和语句；或者确认只有子模块组合才会崩溃，并给出最小组合。

## 8. result.md 模板

```markdown
# 卡 109 结果

| 项 | 内容 |
|---|---|
| 代码 HEAD | |
| PDS 版本 | |

## 模块扫描
| 模块 | 结果 | 最后一条 Found Ram |
|---|---|---|

## 崩溃定位
| 模块 | 数组 | 行号 | 删除或简化了什么后不再崩溃 |
|---|---|---|---|

触发语句原文：

## 问题与偏离
```
