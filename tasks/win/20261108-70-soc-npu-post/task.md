# 卡 70：整片 SoC 加入 NPU 硬件后处理 (b)：实现与上板

## 1. 目标

在卡 68 第 2 轮的整片工程上加入 NPU 硬件后处理 (b)：
- 类别最大值、阈值、候选压缩在 NPU 写回时流式完成；
- DFL 在网络结束后按候选完成；
- CPU 只做排序和 NMS。

要确认三件事：
1. 新逻辑不成为新的最差路径或拥塞点；
2. 实时识别的 CPU 后处理（`decode`）从约 21 ms 降到 1 ms 左右；
3. 端到端延迟下降。

卡 69（NPU APM 本地化）布不通，见 `docs/reports/2026-11-10-route-soc-card69.md`；其 RTL 已在 b3 `ea11656c` 撤销。本卡的 NPU 主体与卡 68 相同，只多后处理，PnR 参数与卡 68 相同（Slack Weight 40）。

**Linux 端证据**（`zc100116/b3` `1bfcb123`，撤销 APM 本地化后在 `ea11656c` 重跑了 NPU 单元和后处理模块测试）
- 规格：npu-spec v0.10、SoC 规格 v0.23；
- 联调报告 `docs/reports/2026-11-08-npu-post-integ.md`：
  - 单元、模块、F/P 档、SoC 软件测试 PP-SW-01/02 全部通过；
  - 真实网络 37 个候选与参考逐字段一致；
  - 后处理尾部约 0.2 ms（180 MHz，带 DDR 延迟模型）。
- RTL 报告 `docs/reports/2026-11-08-npu-post-rtl.md`：新逻辑按 200 MHz 预算设计。

**对照**
- 卡 68 第 2 轮上板：
  - 识别 15–26 fps；
  - NPU 35.0 ms；
  - `decode` 20.8 ms，`post_span` 25.6 ms；
  - 端到端 100–144 ms。
- 卡 68 第 2 轮：第 176 轮收敛，PnR 2h25m；慢角 WNS clk_sys −0.088 / clk_npu −0.205 / clk_mem −0.025 ns；LUT 91,208、FF 107,042。

## 2. 输入

| 项 | 内容 |
|---|---|
| 代码 | `origin/zc100116/b3` 上包含本卡的提交。从这里拉出 `win/20261108-70-soc-npu-post`，记录 HEAD |
| 顶层 / 导入脚本 / 约束 | 与卡 68 相同。导入脚本按 `rtl/filelists/*.f` 收集源文件，新增的 `rtl/npu/edrv32_npu_post*.v` 和 `rtl/tech/edrv32_ram_npu_post_*.v` 会自动导入 |
| 程序 | `src/showcase-post.elf`：12936548 字节，构建自 b3 `1bfcb123`（撤销只涉及 RTL，软件不变）。`src/board_npu.elf`：5200248 字节，同一提交构建。board_npu 保持后处理关闭（POST_CTRL.EN=0），用来回归核心推理 |
| 调试工具 | 本 checkout 的 `tools/debug_tool`：网口 channel 1 已改为接收候选，内容为 count 加 count×24 B |

## 3. 环境

- PDS 2022.2-SP6.1，PG2L200H-6 FBB676。
- 仿真虚拟机关机；PnR 期间不运行其他占内存的程序。

## 4. 需要的 IP

把卡 68 的工程 `G:/codex_project/EdRV32-FPGA/EdRV32-B3F-V021` 复制为 `G:/codex_project/EdRV32-FPGA/EdRV32-B3F-POST`，沿用其中全部 IP，另外**新增 3 个**：

| IP | 创建说明 | 要点 |
|---|---|---|
| `ip_ram_npu_post_best` | `fpga/ip/ip_ram_npu_post_best.md` | 深度 2048，RTL 中例化 2 次 |
| `ip_ram_npu_post_queue` | `fpga/ip/ip_ram_npu_post_queue.md` | 深度 2520，例化 2 次 |
| `ip_ram_npu_post_table` | `fpga/ip/ip_ram_npu_post_table.md` | 真双口 1024 × 32，例化 2 次 |

- 每个 IP 都严格按创建说明设置。
- 生成后，核对模块名和端口名与说明一致；不一致时停下回报。
- 每个 IP 的选项页截图。

## 5. 操作步骤

| 步骤 | 执行者 | 内容 |
|---|---|---|
| 0 | Windows Codex（C） | `git fetch origin`，`git switch -c win/20261108-70-soc-npu-post origin/zc100116/b3`，记录 HEAD 和空闲物理内存。 |
| 1 | 用户（U） | 复制工程（第 4 节），生成 3 个新 IP。 |
| 2 | U 或 C | 清空源文件列表，在工程目录下 `source ../../EdRV32-Competition-2026/fpga/scripts/import_board_full_top.tcl`；然后 Compile、`synthesize -ads`、`dev_map`。记录综合资源，特别是 `u_npu` 下 post 相关模块的 LUT / FF / DRM / APM。 |
| 3 | U | PnR 参数与卡 68 **完全相同**（Slack Weight 40），运行 `pnr`。截图设置页。 |
| 4 | C | 每小时记录布线轮次、单轮耗时、未布通数、过用数和空闲内存。止损条件：<br>- Route-0039 / Route-0008；<br>- 第 40 轮时未布通数大于 18000；<br>- 单轮耗时持续超过 600 s。 |
| 5 | U + C | 布通后按第 6 节导出，生成比特流。有时序违例也照常上板，时序和功能分开报告。 |
| 6 | U | 下载比特流，KEY1 复位进入 BIOS，记录 `CLK_SYS_HZ`。 |
| 7 | U + C | **board_npu** 跑 1 次：39/39，D 组 CRC 一致；记录 C-YOLO 的 PERF0 和 fps。 |
| 8 | U + C | **showcase**（`src/showcase-post.elf`，加载方法同卡 68）：<br>- 实时识别连续运行 **5 分钟**：记录 `vision fps=` 串口行，包括 npu、wait、decode、post_span、gui、e2e、period；画面中检测框位置和类别正常，与卡 68 的识别效果一致；<br>- 图片识别页跑 1 次：PC 端调试工具应能收到候选并显示结果；<br>- CoreMark 1 次；<br>- benchmark 完整跑 1 次。<br>记录死机、复位、画面错乱、框位置明显错误等异常。 |
| 9 | C | 整理 result.md，推送 `win/20261108-70-soc-npu-post`。 |

## 6. 产物

放在 `tasks/win/20261108-70-soc-npu-post/artifacts/`：
- **时序**：格式同卡 69 任务卡第 6 节。包括：
  - 三个时钟域 slack ≤ +1.0 ns 的全部 setup 路径；
  - clk_npu 的 recovery；
  - 每个域最差 50 条路径的逐级明细；
  - `native_reports/`。
  - 另外单列 `u_npu/u_post*` 下 slack ≤ +0.5 ns 的路径。
- **资源**：
  - 汇总（已用 / 总数）、按模块层次的分布；
  - post 模块的 LUT / FF / DRM / APM；
  - CLMA / CLMS 占用。
- **布线**：每轮的轮次、耗时、未布通数、过用数；最终拥塞网格和 PNG。
- **IP**：3 个新 IP 的选项截图。
- **上板**：
  - `uart/*.log`；
  - `photos/`：识别画面、CoreMark；
  - `benchmark.txt`；
  - `edtm_*.csv`（如有）。

## 7. 通过判据

- 布通并生成比特流；
- board_npu 39/39；
- 实时识别 5 分钟无异常，检测框正常，`decode` 明显低于卡 68 的 20.8 ms；
- 图片识别的 PC 端能收到并显示候选；
- 所有数字都取自报告或日志原文，找不到的写"未取得"。

## 8. result.md 模板

```markdown
# 卡 70 结果

| 项 | 内容 |
|---|---|
| 代码 HEAD | |
| 工程 / Slack Weight | |
| 收敛轮次 / PnR 用时 | |
| CLK_SYS_HZ | |

## 时序
| 时钟域 | 约束 MHz | WNS / TNS | WHS / THS | 违例端点 | 估算 Fmax |
|---|---|---|---|---|---|
| clk_sys | 125 | | | | |
| clk_npu | 180 | | | | |
| clk_mem | 125 | | | | |
| u_npu/u_post* 最差 slack | | | | | |

## 资源（已用 / 总数）
| LUT | FF | DRM | APM | CLMA / CLMS | post 模块 LUT / FF / DRM / APM |
|---|---|---|---|---|---|

## 上板
| 项目 | 结果 | 关键数字 |
|---|---|---|
| board_npu | | PERF0、fps |
| 实时识别 5 min | | fps、npu、wait、decode、post_span、gui、e2e（范围） |
| 图片识别 | | 候选数、PC 端显示 |
| CoreMark | | Iterations/Sec、CoreMark/MHz |
| benchmark | | 平均 fps |

## 问题与偏离
```
