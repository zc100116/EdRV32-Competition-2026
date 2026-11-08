# 卡 68：整片 SoC（CPU v0.21 + NPU 180 MHz）实现与上板

## 1. 目标

把冻结的 CPU v0.21 和时序优化后的 NPU 合入整片 F 工程，按 clk_sys 125 MHz、clk_npu 180 MHz 完成布局布线和比特流生成，并上板验证。重点测：
- CoreMark：理论约 5.53–5.56 CoreMark/MHz，125 MHz 下约 690 分；
- NPU 识别帧率：clk_npu 从 150 提到 180 MHz；
- 稳定性。

**对照（发布版 m1，卡 48/51/54）**：
- clk_sys 125 MHz、clk_npu 150 MHz；
- CoreMark 4.354/MHz，约 544 分。

**本版的 Linux 端证据**（报告 `docs/reports/2026-11-08-soc-int-v021.md`）：
- 整片 lint 0 告警；
- 启动、渲染、NPU 代表仿真通过；
- SRAM 中 CoreMark 为 5.56 CoreMark/MHz。

**独立探针**：
- CPU+L1 为 138.3 MHz（卡 64）；
- NPU 为 202.1 MHz（卡 65）。

## 2. 输入

| 项 | 内容 |
|---|---|
| 代码 | `origin/zc100116/b3` 上包含本卡的提交。从这里拉出 `win/20261108-68-soc-v021-full`，记录 HEAD |
| 顶层 / 导入脚本 / 约束 | `edrv32_fpga_board_full_top` / `fpga/scripts/import_board_full_top.tcl` / `fpga/constraints/edrv32_fpga_board_full_top.fdc`（clk_npu 已改为 ×20/3 = 180 MHz） |
| 程序 | `src/showcase-v021.elf`：12936432 字节，构建自 b3 `48b84d67`，调试工具显示的板端版本应为 `48b84d67`。`src/board_npu.elf`：5194104 字节，同一提交构建 |
| NPU 模型 | `tasks/win/20261029-09-b3-software/src/npu/`（与以前相同；showcase 已内嵌模型） |
| 调试工具 | 本 checkout 的 `tools/debug_tool`（NPU 时钟换算已改为 180 MHz）。先关掉旧进程再启动 |

## 3. 环境

- PDS 2022.2-SP6.1，PG2L200H-6 FBB676。
- 板级连接与卡 51/54 相同：PC 192.168.1.2/24，板 192.168.1.10:5000，HDMI、两个 OV5640、串口、网口。

## 4. 需要的 IP

新工程复制发布版 F 工程 `G:/codex_project/EdRV32-FPGA/EdRV32-B3F-RND1S-CPU125`（卡 48 F CPU125）。沿用其中全部 IP，另做以下改动：

| 动作 | IP | 说明 |
|---|---|---|
| 重新生成 | `ip_pll_npu` | 按 `fpga/ip/ip_pll_npu.md`，CLKOUT0 改为 **180.000 MHz**（27 × 20 / 3）；工具显示的实际频率不是 180.000 时停下回报 |
| 新增 | `ip_lutram_cpu_btb` | 按 `fpga/ip/ip_lutram_cpu_btb.md`，无初始化文件 |
| 新增 | `ip_lutram_cpu_direction` | 按 `fpga/ip/ip_lutram_cpu_direction.md`，初始化文件 1024 行，每行 `5` |
| 新增 | `ip_lutram_cpu_local_history` | 按 `fpga/ip/ip_lutram_cpu_local_history.md`，初始化文件 256 行，每行 `000` |
| 新增 | `ip_lutram_cpu_tournament` | 按 `fpga/ip/ip_lutram_cpu_tournament.md`，初始化文件 1024 行，每行 **`1`**。卡 60–67 的探针工程里用的是 `INIT_FILE=NONE`（初值 0），这是错的，不能沿用 |
| 不变 | `ip_ram_icache_data` | 保持 **64 位**（发布版工程本来就是 64 位）。不要用卡 66/67 探针工程的 108 位版本 |

三个初始化文件由 Windows Codex 在新工程目录下生成，路径为 `<工程>/ip_init/`，不提交到 git：

```
python -c "open('ip_lutram_cpu_direction.dat','w').write('5\n' * 1024)"
python -c "open('ip_lutram_cpu_local_history.dat','w').write('000\n' * 256)"
python -c "open('ip_lutram_cpu_tournament.dat','w').write('1\n' * 1024)"
```

## 4b. 第 2 轮（2026-11-08）

第 1 轮在第 21 轮时仍有 49,566 条未布通网络，单轮约 1,400 s，用户决定停止。原因有两个：
- 仿真虚拟机与 PnR 同时运行，内存只剩 746 MiB；
- NPU 为提频复制的约 6.1K 个 FF 加重了拥塞。

第 2 轮的改动：
- NPU 的 RTL 退回卡 63 版本 `b5be940c`（独立探针 198.9 MHz），clk_npu 保持 180 MHz。CPU、软件、IP 和约束都不变。
- 本卡所在分支更新后，`rtl/npu/` 中的 5 个文件改为卡 63 版本。文件路径不变，所以不需要重新导入。

| 步骤 | 执行者 | 内容 |
|---|---|---|
| R2-0 | 用户（U） | 停止第 1 轮的 PnR。**确认仿真虚拟机已关机**，关掉其他占内存的程序。 |
| R2-1 | Windows Codex（C） | 在 `win/20261108-68-soc-v021-full` 分支上 `git fetch origin`，然后 `git merge origin/zc100116/b3`，取得本轮代码，记录 HEAD。记录系统空闲物理内存。 |
| R2-2 | U | 在 `EdRV32-B3F-V021` 工程中重新运行 Compile、`synthesize -ads`、`dev_map`、`pnr`，PnR 参数与第 1 轮相同。 |
| R2-3 | C | 每小时记录布线轮次、单轮耗时、未布通数、过用数、系统空闲内存。止损条件与第 1 轮相同；另外，单轮耗时持续超过 600 s 时回报。 |
| R2-4 | U + C | 布通后照第 5 节第 7–11 步执行，即 `report_timing`、比特流和上板。产物放进 `artifacts/R2/`，result.md 增加第 2 轮一节，第 1 轮的记录保留。 |

## 5. 操作步骤

| 步骤 | 执行者 | 内容 |
|---|---|---|
| 0 | Windows Codex（C） | `git fetch origin`，`git switch -c win/20261108-68-soc-v021-full origin/zc100116/b3`，记录 HEAD。记录空闲物理内存。 |
| 1 | 用户（U） | 把 `EdRV32-B3F-RND1S-CPU125` 复制为 `G:/codex_project/EdRV32-FPGA/EdRV32-B3F-V021`。 |
| 2 | C | 在 `<工程>/ip_init/` 下生成第 4 节的三个 `.dat` 文件。 |
| 3 | U | 按第 4 节重新生成 `ip_pll_npu`，新增 4 个 CPU LUTRAM IP。每个 IP 的选项页截图。 |
| 4 | U 或 C | **清空**工程原有的源文件列表。在 PDS 控制台中，于工程目录下执行 `source ../../EdRV32-Competition-2026/fpga/scripts/import_board_full_top.tcl`。然后 `synthesize -ads`，记录综合资源和源文件数。 |
| 5 | U | PnR 设置与卡 48 的 F 工程相同：<br>- Device Map：`Number of Nets To Report` 1000；<br>- PnR：Placement Decongestion Mode 2；勾选 Placement Logic Optimization；LUT6D Packing Strategy 0；Slack Weight 40；Pin Cost Increasing Speed 600；Multi-thread routing 5；勾选 Dump Router Congestion Plot。<br>截图设置页，然后运行 `dev_map`、`pnr`。 |
| 6 | C | 每小时记录布线轮次、未布通数和过用数。**止损**：工具报 Route-0039 / Route-0008 即为失败；第 40 轮时未布通数仍大于 18000，也停止并回报。 |
| 7 | U + C | 布通后执行 `report_timing` 和 `gen_bit_stream`，按第 6 节收集时序和资源。有时序违例也照常生成比特流并上板，时序和功能分开报告。 |
| 8 | U | 下载比特流。KEY1 复位进入 BIOS，记录串口启动信息，其中 `CLK_SYS_HZ` 应为 125000000。 |
| 9 | U + C | **board_npu**：按卡 48 第 5 节 5N 的命令运行 `src/board_npu.elf` **3 次**。每次都要 39/39，D 组 20 帧 CRC 全部一致，并记录 C-YOLO 的 PERF0 和 fps（180 MHz 换算）。 |
| 10 | U + C | **showcase**：按卡 54 的方法加载 `src/showcase-v021.elf`。<br>- 芯片信息页运行 CoreMark **3 次**，每次记录 Iterations/Sec、CoreMark/MHz、编译选项、16 个性能计数器、IPC、每千条指令缺失数。编译选项应包含 `-O3 -funroll-all-loops`。<br>- 视觉识别连续运行 **15 分钟**，记录 NPU 帧率和端到端帧率，每 5 分钟记录一次遥测。<br>- benchmark 完整跑一遍。<br>- NES 运行 5 分钟。<br>记录是否出现死机、复位、画面错乱、CRC 不一致等异常。 |
| 11 | C | 整理 result.md，推送 `win/20261108-68-soc-v021-full`。 |

## 6. 产物

放在 `tasks/win/20261108-68-soc-v021-full/artifacts/`：
- **时序**：
  - 每个时钟域的 WNS/TNS/WHS/THS 汇总；
  - clk_sys、clk_npu、clk_mem 各自最差 200 条 setup 路径（每条一行：起点、终点、slack、级数）；
  - 最差 20 条 setup 路径的逐级明细；
  - 最差 20 条 hold 路径；
  - `native_reports/` 中放压缩的 `report_timing` 原文。
- **资源**：资源汇总（LUT、FF、DRM、APM、分布式 RAM、IO、PLL，每项都写"已用 / 总数"），以及按模块层次的资源分布。
- **布线**：每轮的轮次、未布通数、过用数，格式与卡 65 的 `routing_congestion.txt` 相同；拥塞图（PNG）。
- **IP**：IP 选项截图，以及 `ip_pll_npu` 的实际频率。
- **上板**：
  - `uart/*.log`：各项目的串口原文；
  - `photos/`：HDMI 画面；
  - `benchmark.txt`；
  - `edtm_*.csv`：遥测（如果有）。

不提交工程文件、IP 目录、比特流和完整日志，在 result.md 中写明它们的本地路径。

## 7. 通过判据

- 布通并生成比特流；
- 启动信息中 `CLK_SYS_HZ` 为 125000000；
- 3 次 board_npu 都是 39/39，D 组 CRC 一致；
- 3 次 CoreMark 的 CRC 都正确；
- 15 分钟识别和 5 分钟 NES 无异常；
- 所有数字都取自报告或日志原文，找不到的写"未取得"。

时序有违例时，照常上板，在 result.md 中分开报告时序和功能。

## 8. result.md 模板

```markdown
# 卡 68 结果

| 项 | 内容 |
|---|---|
| 代码 HEAD | |
| 工程 / 比特流路径 | |
| ip_pll_npu 实际频率 | |
| CLK_SYS_HZ | |

## 时序
| 时钟域 | 约束 MHz | WNS / TNS | WHS / THS | 违例端点数 | 估算 Fmax |
|---|---|---|---|---|---|
| clk_sys | 125 | | | | |
| clk_npu | 180 | | | | |
| clk_mem | 125 | | | | |
| 其他 | | | | | |

## 资源（已用 / 总数）
| LUT | FF | DRM | APM | 分布式 RAM | IO | PLL |
|---|---|---|---|---|---|---|

## 布线
| 收敛轮次 | 首轮 未布通 / 过用 | 路由耗时 |
|---|---|---|

## 上板
| 项目 | 次数 / 时长 | 结果 | 关键数字 |
|---|---|---|---|
| board_npu | 3 次 | | C-YOLO PERF0、fps |
| CoreMark | 3 次 | | Iterations/Sec、CoreMark/MHz、IPC |
| 视觉识别 | 15 min | | NPU fps、端到端 fps |
| benchmark | 1 次 | | |
| NES | 5 min | | |

## 问题与偏离
```
