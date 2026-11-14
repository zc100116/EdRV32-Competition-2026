# 卡 73：扇出修正后的整片 SoC（含 NPU 硬件后处理）：两组 Slack Weight 并行布局布线，并上板

## 1. 目标

卡 72 布线不收敛。分析见 `origin/win/20261113-72-soc-slim1-post` 的结果和下文。本卡做两件事：
1. 用扇出修正后的 RTL，跑两个工程，网表相同，只有 Slack Weight 不同：A 为 40，B 为 20。确认哪个能布通，以及两项修正各自有没有作用；
2. 选一个布通的比特流上板，确认硬件后处理生效、性能不变。

**本卡取代卡 72**。卡 71 改用本卡的比特流。

**卡 72 的问题**：卡 72 的 LUT 比卡 68 少 3.2K，但到通用布线第 34 轮，未布通数是 24,329，卡 68 R2 是 11,159。对比 Device Map 的高扇出网，瘦身和后处理把原来按通道或分段复制的控制寄存器合并成了单个寄存器：

| 网 | 卡 68 | 卡 72 | 本卡 RTL |
|---|---:|---:|---|
| `u_npu/u_conv/u_datapath/quant_tag_w[28]` | —（64 份 `wb1_res_en_r`） | 640 | 恢复 64 份 `wb1_res_en_r` |
| `u_npu/post_active_r` / `u_npu/is_conv_r` | — / 246 | 357 / 373 | 写数据选择各加 8 份副本 `g_write_slice[*].post_active_slice_r / is_conv_slice_r` |
| `u_rnd/u_copy/align_offset_r[0..4]` | —（8 份分段偏移） | 256–496 | 8 个位列各一份 `g_alignment[*].align_offset_r` |
| `u_rnd/u_copy/read_index_w[9]` | — | 504 | 8 份 `g_alignment[*].read_overflow_r` |

报告：`docs/reports/2026-11-14-fanout-npu.md`、`docs/reports/2026-11-14-fanout-rnd.md`。

**为什么同时试 Slack Weight 20**：卡 69 的 A、B 两个工程网表和布局都相同（第 1 轮未布通数都是 148,634），只有 Slack Weight 不同：40 和 90。到通用布线第 34 轮，90 的那个未布通 25,856，40 的那个是 16,854。时序权重越高越难布通，所以试一个更低的值。

**对照**（通用布线第 N 轮：日志中第一条 `Unrouted general nets` 记为第 1 轮）：

| 通用第 N 轮 | 卡 68 R2（布通） | 卡 69 A（40） | 卡 69 B（90） | 卡 72（40） |
|---:|---:|---:|---:|---:|
| 1 | 147,564 | 148,634 | 148,634 | 146,548 |
| 20 | 24,186 | 28,923 | 37,724 | 35,933 |
| 34 | 11,159 | 16,854 | 25,856 | 24,329 |

卡 68 R2 的其他结果：
- 资源：LUT 91,208、FF 107,042、DRM 286、APM 372；
- 慢角 WNS：clk_sys −0.088、clk_npu −0.205、clk_mem −0.025 ns；
- board_npu PERF0 为 6,190,102；
- LVGL 平均 23 fps。

## 2. 输入

| 项 | 内容 |
|---|---|
| 代码 | `origin/zc100116/b3` 上包含本卡的提交，从这里拉出 `win/20261114-73-soc-fanout-post`，记录 HEAD |
| 工程 | A：沿用 `G:/codex_project/EdRV32-FPGA/EdRV32-B3F-POST`。B：把它复制为 `EdRV32-B3F-POST-B`，包含全部 IP |
| 导入脚本 / 约束 | 与卡 68、72 相同 |
| 程序 | 沿用卡 70 的 `tasks/win/20261108-70-soc-npu-post/src/showcase-post.elf` 和 `src/board_npu.elf`，软件没有改动 |
| 调试工具 | 本 checkout 的 `tools/debug_tool` |

## 3. 环境

PDS 2022.2-SP6.1，PG2L200H-6 FBB676。A、B 两个工程同时运行。

## 4. 需要的 IP

无新增。

## 5. 操作步骤

| 步骤 | 执行者 | 内容 |
|---|---|---|
| 0 | Windows Codex（C） | `git fetch origin`，`git switch -c win/20261114-73-soc-fanout-post origin/zc100116/b3`，记录 HEAD。 |
| 1 | 用户（U） | 先停掉卡 72 的 PnR（如果还在跑）。把 `EdRV32-B3F-POST` 复制为 `EdRV32-B3F-POST-B`。 |
| 2 | U 或 C | 两个工程分别执行：<br>- 清空源文件列表；<br>- 在工程目录下 `source ../../EdRV32-Competition-2026/fpga/scripts/import_board_full_top.tcl`；<br>- 然后 Compile、`synthesize -ads`、`dev_map`。<br>记录资源，以及 `u_npu`、`u_rnd` 的 LUT / FF。 |
| 3 | C | **核对复制寄存器是否保留**。在 Device Map 的高扇出列表中：<br>- 确认第 1 节表中 4 组网在卡 72 中的大扇出（640、357/373、256–496、504）已经消失；<br>- 列出 `post_active_slice_r`、`is_conv_slice_r`、`align_offset_r`、`read_overflow_r`、`wb1_res_en_r` 各副本的扇出（列表中没有的写"低于列表门限"）；<br>- 如果副本被合并，回到单个大扇出，就停下回报，不跑 PnR。 |
| 4 | U | PnR：<br>- **A**：参数与卡 68 完全相同，Slack Weight 40；<br>- **B**：只把 Slack Weight 改为 **20**，其余与 A 相同。<br>两个同时运行。导出两个工程实际使用的 compile / synthesize / dev_map / pnr 命令和参数，格式同卡 68 的 `artifacts/R2/settings.txt`。 |
| 5 | C | 每小时记录两个工程的轮次、单轮耗时、未布通数和过用数。轮次按通用布线第 N 轮计。<br>**止损**，每个工程单独判断，出现任意一条就停止该工程并回报：<br>- 工具报 Route-0039 或 Route-0008；<br>- 通用第 20 轮未布通数大于 30,000；<br>- 通用第 34 轮未布通数大于 15,000。 |
| 6 | U + C | 布通的工程按第 6 节导出。两个都布通时，选慢角 WNS 总体较好的那个生成比特流并上板，另一个只导出时序。有时序违例也照常上板，时序和功能分开报告。 |
| 7 | U | 下载比特流，KEY1 复位进入 BIOS，记录 `CLK_SYS_HZ`。 |
| 8 | U + C | **board_npu** 跑 1 次：39/39，D 组 CRC 一致；记录 C-YOLO 的 PERF0 和 fps。 |
| 9 | U + C | **showcase**（`showcase-post.elf`，加载方法同卡 68）：<br>- 实时识别连续运行 5 分钟，保存全部 `vision fps=` 串口行；检测框的位置和类别正常；<br>- 图片识别页跑 1 次，PC 端调试工具能收到并显示候选；<br>- 图像处理页：两级 3×3 分别设为高斯和 Sobel，运行 1 分钟，拍照记录界面显示的帧率，画面无错乱；<br>- 在任意一个有画面的页面执行一次 RND 拷贝（例如切换页面或窗口），画面无错位；<br>- CoreMark 1 次；<br>- LVGL benchmark 完整跑 1 次。<br>记录死机、复位、画面错乱、框位置明显错误等异常。 |
| 10 | C | 整理 result.md，推送 `win/20261114-73-soc-fanout-post`。 |

## 6. 产物

放在 `tasks/win/20261114-73-soc-fanout-post/artifacts/`，A、B 分开放在 `A/`、`B/` 子目录：
- **设置**：`settings.txt`（第 5 节第 4 步）。
- **资源**：资源汇总；ADS 按模块层次的资源分布 `resource_hier.txt`；Device Map 的 `high_fanout.txt`；第 3 步的复制寄存器核对表。
- **布线**：每轮的轮次、耗时、未布通数、过用数；通用第 1、20、34 轮和最后一轮的拥塞网格，以及共用色标的 PNG。
- **时序**（布通的工程）：
  - 三个时钟域、快慢两角的 WNS/TNS/WHS/THS 汇总；
  - 每个域 slack ≤ +0.5 ns 的全部 setup 路径，一行一条：起点、终点、slack、逻辑级数、逻辑延迟、走线延迟；
  - 每个域最差 20 条路径的逐级明细；
  - `u_npu/u_post*`、`u_rnd/u_copy*` 下 slack ≤ +0.5 ns 的路径单独列出。
- **上板**：`uart/*.log`；`photos/`（识别画面、图像处理页、CoreMark）；`benchmark.txt`。

## 7. 通过判据

- 至少一个工程布通，并生成比特流；
- board_npu 39/39；
- 实时识别 5 分钟无异常，`decode` 明显低于卡 68 的 20.8 ms；
- 图片识别时 PC 端能收到并显示候选；
- 所有数字都取自报告或日志原文，找不到的写"未取得"。

## 8. result.md 模板

```markdown
# 卡 73 结果

| 项 | A（SW 40） | B（SW 20） |
|---|---|---|
| 代码 HEAD | | |
| 收敛轮次 / PnR 用时 | | |
| 上板的是 | | |
| CLK_SYS_HZ | | |

## 资源（与卡 68、卡 72 对比）
| 项 | 卡 68 | 卡 72 | 卡 73 |
|---|---|---|---|
| LUT / FF / DRM / APM | | | |
| u_npu / u_rnd 的 LUT/FF | | | |
| CLMA / CLMS（布通的工程） | | | |

## 复制寄存器核对
| 网 | 卡 72 扇出 | 卡 73 副本数 × 扇出 |
|---|---|---|
| quant_tag_w[28] / wb1_res_en_r | 640 | |
| post_active_r / post_active_slice_r | 357 | |
| is_conv_r / is_conv_slice_r | 373 | |
| align_offset_r | 256–496 | |
| read_index_w[9] / read_overflow_r | 504 | |

## 布线（通用第 N 轮未布通数）
| 通用第 N 轮 | 卡 68 R2 | 卡 72 | A | B |
|---|---|---|---|---|
| 1 / 10 / 20 / 34 / 60 / 100 / 收敛 | | | | |

## 时序（慢角 WNS / TNS，快角 WHS / THS）
| 时钟域 | 约束 MHz | A | B |
|---|---|---|---|
| clk_sys | 125 | | |
| clk_npu | 180 | | |
| clk_mem | 125 | | |
| u_npu/u_post*、u_rnd/u_copy* 最差 slack | | | |

## 上板
| 项目 | 结果 | 关键数字 |
|---|---|---|
| board_npu | | PERF0、fps |
| 实时识别 5 min | | fps、npu、wait、decode、post_span、gui、e2e（范围） |
| 图片识别 | | 候选数、PC 端显示 |
| 图像处理页 | | 界面帧率 |
| RND 拷贝画面 | | |
| CoreMark | | Iterations/Sec、CoreMark/MHz |
| LVGL benchmark | | 平均 fps、ALL 平均渲染 ms |

## 问题与偏离
```
