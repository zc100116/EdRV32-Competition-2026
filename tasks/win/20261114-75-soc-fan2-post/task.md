# 卡 75：第二轮扇出复制后的整片 SoC（含 NPU 硬件后处理）：单工程布局布线，并上板

## 1. 目标

卡 73 的扇出修正有效，但不够：通用第 9 轮未布通数与卡 68 R2 的差距，从卡 72 的 +12.6% 缩小到 +4.7%，单轮耗时仍很长。本卡针对卡 73 A 第 9 轮拥塞最重的网，再做一轮扇出复制。只跑一个工程，参数与卡 73 A 相同（Slack Weight 40，clk_npu 180 MHz）。布通后上板。

**本卡取代卡 73**。卡 71 改用本卡的比特流。

**复制对象**：下表的扇出和拥塞值都取自卡 73 A，分别来自 Device Map 和第 9 轮的拥塞网列表。

| 卡 73 A 的网 | 扇出 | 第 9 轮拥塞值 | 本卡 RTL 的副本 |
|---|---:|---:|---|
| `u_rnd/cancel_region_w[6]`，即 P4 写 DMA 的 `abort_i` | 677 | 498 | `u_rnd/u_write`（`edrv32_dma2d_wr`）内的组合副本：`stop_w[0..7]` 和 `abort_latch_w`，属性为 syn_keep |
| `u_rnd/state_r_reg[5]` | 582 | 331 | 共 26 份 4 位状态副本：<br>- `g_command[0..9].capture_state_r`；<br>- `g_capture[0..7].capture_state_r`；<br>- `g_result_state[0..7].result_state_r`。 |
| `u_rnd/blend_tag_w[31]` / `u_rnd/blend_valid_w` | 519 / 518 | 312 / 447 | `u_alpha/g_result_control[0..7].bank_r` / `slice_valid_r`，各 8 份 |
| `u_rnd/u_blit/render_bank_r` | — | 264 | `u_blit/g_render_select[0..7].bank_r` |
| `u_rnd/command_control_w[2][8]` | 289 | — | `g_command[6..9].control_r[8]`，FILL 格式位 4 份 |
| `u_mem/u_xbar/w_port_r[0..2]` | 471–615 | 291–368 | `g_w_select[0..8].w_port_copy_r`，9 份 |
| `u_mem/u_xbar/u_rbuf/skid_valid_r[0..6]` | 223–230 | 309–348 | 每口 4 份：`g_output[p].g_data[0..3].skid_valid_copy_r` |
| `u_npu/u_conv/u_datapath/u_weight_store/g_bank[0..2].rd_segment_output_r` | — | 256 | 每个 bank 4 份：`g_bank[*].g_read_slice[0..3].rd_segment_output_r` |
| `u_npu/u_conv/dp_result_rd_index_w[0..4]` | — | 256 | `u_npu/u_conv/u_conv_write/result_rd_index_r[9:0]`，两份 5 位地址，各驱动一个 256 位结果 RAM IP |
| `u_npu/cls_plane_w` | — | 257 | 拆为两路：<br>- `u_conv_write/cls_plane_r`，只送后处理；<br>- `u_datapath/u_writeback/rd_plane_output_r[0..3]`，各选 64 位。 |

所有副本都是寄存器复制或组合复制，带 keep 属性；逐拍行为不变，没有加流水级。资源方面，Yosys 参考估计 RND 增加约 260 个 FF 和 290 个 LUT，MEM 和 NPU 增加的量更小。

报告：`docs/reports/2026-11-14-fan2-{rnd,mem,npu}.md`。

**对照**（通用第 N 轮：日志中第一条 `Unrouted general nets` 记为第 1 轮）：

| 通用第 N 轮 | 卡 68 R2（布通） | 卡 72 | 卡 73 A | 卡 73 A 单轮耗时（秒） | 卡 68 R2 单轮耗时（秒） |
|---:|---:|---:|---:|---:|---:|
| 1 | 147,564 | 146,548 | 147,815 | | |
| 7 | 71,679 | 77,183 | 74,336 | 605 | 111 |
| 9 | 55,897 | 62,953 | 58,510 | 1,120 | 174 |
| 20 | 24,186 | 35,933 | 未取得 | | |
| 34 | 11,159 | 24,329 | 未取得 | | |

卡 68 R2 的其他结果：
- 资源：LUT 91,208、FF 107,042、DRM 286、APM 372；
- 慢角 WNS：clk_sys −0.088、clk_npu −0.205、clk_mem −0.025 ns；
- board_npu PERF0 为 6,190,102；
- LVGL 平均 23 fps。

## 2. 输入

| 项 | 内容 |
|---|---|
| 代码 | `origin/zc100116/b3` 上包含本卡的提交，从这里拉出 `win/20261114-75-soc-fan2-post`，记录 HEAD |
| 工程 | 沿用 `G:/codex_project/EdRV32-FPGA/EdRV32-B3F-POST`。卡 73 的 B 工程 `EdRV32-B3F-POST-B` 不用，可以删除 |
| 导入脚本 / 约束 | 与卡 68、73 相同 |
| 程序 | 沿用卡 70 的 `tasks/win/20261108-70-soc-npu-post/src/showcase-post.elf` 和 `src/board_npu.elf`，本卡不要重新编译 |
| 调试工具 | 卡 70 程序对应的调试工具：`git show cc5df889:tools/debug_tool` 导出到临时目录后使用。b3 HEAD 的调试工具已改为新协议，不能用 |

## 3. 环境

PDS 2022.2-SP6.1，PG2L200H-6 FBB676。只运行一个工程。

## 4. 需要的 IP

无新增。`ip_lutram_npu_result` 不变：包装模块仍例化两个 256 位实例，只是两个实例改用各自的读地址。

## 5. 操作步骤

| 步骤 | 执行者 | 内容 |
|---|---|---|
| 0 | Windows Codex（C） | `git fetch origin`，`git switch -c win/20261114-75-soc-fan2-post origin/zc100116/b3`，记录 HEAD。 |
| 1 | 用户（U） | 如果卡 73 的 PnR 还在跑，先停掉。 |
| 2 | U 或 C | 在 `EdRV32-B3F-POST` 中依次执行：<br>- 清空源文件列表；<br>- 在工程目录下 `source ../../EdRV32-Competition-2026/fpga/scripts/import_board_full_top.tcl`；<br>- Compile、`synthesize -ads`、`dev_map`。<br>记录资源，以及 `u_npu`、`u_rnd`、`u_mem` 的 LUT / FF。 |
| 3 | C | **核对副本是否保留**。在 Device Map 的高扇出列表中：<br>- 第 1 节表中的每根网，列出原网的扇出和各副本的扇出；列表中没有的，写"低于列表门限"；<br>- `u_rnd/u_write/stop_w[*]` 是组合副本：写明 PDS 保留了几根独立的网，还是合并成了一根；<br>- `state_r` 被 PDS 改成独热码后，写明 `state_r_reg[*]` 各位的扇出；<br>- 列出高扇出表前 30 条（`u_cpu` 除外）。<br>如果某组副本被合并回单个大扇出网（扇出 ≥ 400），停下回报，不跑 PnR。 |
| 4 | U | PnR 参数与卡 73 A 完全相同（Slack Weight 40）。导出实际使用的 compile / synthesize / dev_map / pnr 命令和参数，格式同卡 68 的 `artifacts/R2/settings.txt`。 |
| 5 | C | 每完成一个通用轮次就记录：轮次、单轮耗时、未布通数、过用数。轮次按通用布线第 N 轮计。<br>**止损**：出现下列任意一条，就停止并回报：<br>- 工具报 Route-0039 或 Route-0008；<br>- 通用第 9 轮未布通数大于 58,510（不比卡 73 A 好）；<br>- 通用第 20 轮未布通数大于 30,000；<br>- 通用第 34 轮未布通数大于 15,000。<br>停止前导出最后完成一轮的拥塞网列表（前 50 条）。 |
| 6 | U + C | 布通后按第 6 节导出，生成比特流并上板。有时序违例也照常上板，时序和功能分开报告。 |
| 7 | U | 下载比特流，按 KEY1 复位进入 BIOS，记录 `CLK_SYS_HZ`。 |
| 8 | U + C | **board_npu** 跑 1 次：要求 39/39，D 组 CRC 一致；记录 C-YOLO 的 PERF0 和 fps。 |
| 9 | U + C | **showcase**（`showcase-post.elf`，加载方法同卡 68）：<br>- 实时识别连续运行 5 分钟，保存全部 `vision fps=` 串口行；检测框的位置和类别正常；<br>- 图片识别页跑 1 次，PC 端调试工具能收到并显示候选；<br>- 图像处理页：两级 3×3 分别设为高斯和 Sobel，运行 1 分钟，拍照记录界面显示的帧率，画面无错乱；<br>- 在任意一个有画面的页面执行一次 RND 拷贝（例如切换页面或窗口），画面无错位；<br>- 打开一个带半透明控件的页面（例如性能浮窗），叠加区域无错位、无花屏；<br>- CoreMark 1 次；<br>- LVGL benchmark 完整跑 1 次。<br>记录死机、复位、画面错乱、框位置明显错误等异常。 |
| 10 | C | 整理 result.md，推送 `win/20261114-75-soc-fan2-post`。 |

## 6. 产物

放在 `tasks/win/20261114-75-soc-fan2-post/artifacts/`：
- **设置**：`settings.txt`（第 5 节第 4 步）。
- **资源**：
  - 资源汇总；
  - ADS 按模块层次的资源分布 `resource_hier.txt`；
  - Device Map 的 `high_fanout.txt`；
  - 第 3 步的副本核对表 `fanout_copies.txt`。
- **布线**：
  - 每轮的轮次、耗时、未布通数、过用数，存为 `routing_rounds.csv`；
  - 通用第 1、9、20、34 轮和最后一轮的拥塞网格，以及共用色标的 PNG；色标与卡 73 的 `routing_congestion.png` 相同；
  - 通用第 9 轮和最后一轮的拥塞网列表，各取前 50 条。
- **时序**（布通时）：
  - 三个时钟域、快慢两角的 WNS/TNS/WHS/THS 汇总；
  - 每个域 slack ≤ +0.5 ns 的全部 setup 路径，一行一条：起点、终点、slack、逻辑级数、逻辑延迟、走线延迟；
  - 每个域最差 20 条路径的逐级明细；
  - 下列模块下 slack ≤ +0.5 ns 的路径单独列出：`u_rnd/u_alpha*`、`u_rnd/u_blit*`、`u_rnd/u_write*`、`u_mem/u_xbar*`、`u_npu/u_conv/u_datapath/u_weight_store*`、`u_npu/u_post*`。
- **上板**：`uart/*.log`；`photos/`（识别画面、图像处理页、半透明叠加、CoreMark）；`benchmark.txt`。

## 7. 通过判据

- 布通并生成比特流；
- board_npu 39/39；
- 实时识别 5 分钟无异常；
- 图片识别时 PC 端能收到并显示候选；
- RND 拷贝和半透明叠加画面正常；
- 所有数字都取自报告或日志原文，找不到的写"未取得"。

## 8. result.md 模板

```markdown
# 卡 75 结果

| 项 | 内容 |
|---|---|
| 代码 HEAD | |
| 收敛轮次 / PnR 用时 | |
| CLK_SYS_HZ | |

## 资源（与卡 68、卡 73 对比）
| 项 | 卡 68 R2 | 卡 73 | 卡 75 |
|---|---|---|---|
| LUT / FF / DRM / APM | | | |
| u_npu / u_rnd / u_mem 的 LUT/FF | | | |
| CLMA / CLMS（布通时） | | | |

## 副本核对
| 卡 73 的网 | 卡 73 扇出 | 卡 75 原网扇出 | 卡 75 副本数 × 扇出 |
|---|---|---|---|
| cancel_region_w[6] / u_write stop_w | 677 | | 独立网数： |
| state_r_reg[*] / capture_state_r、result_state_r | 582 | | |
| blend_tag_w[31] / bank_r | 519 | | |
| blend_valid_w / slice_valid_r | 518 | | |
| u_blit render_bank_r / g_render_select bank_r | — | | |
| command_control_w[2][8] / control_r[8] | 289 | | |
| w_port_r[0..2] / w_port_copy_r | 471–615 | | |
| skid_valid_r[*] / skid_valid_copy_r | 223–230 | | |
| rd_segment_output_r | — | | |
| dp_result_rd_index_w / result_rd_index_r | — | | |
| cls_plane_w / cls_plane_r、rd_plane_output_r | — | | |

## 布线（通用第 N 轮）
| 通用第 N 轮 | 卡 68 R2 未布通 | 卡 73 A 未布通 | 卡 75 未布通 | 卡 75 单轮耗时（秒） |
|---|---|---|---|---|
| 1 / 7 / 9 / 20 / 34 / 60 / 100 / 收敛 | | | | |

第 9 轮拥塞网前 10 条（网名、拥塞值）：

## 时序（慢角 WNS / TNS，快角 WHS / THS）
| 时钟域 | 约束 MHz | 卡 75 |
|---|---|---|
| clk_sys | 125 | |
| clk_npu | 180 | |
| clk_mem | 125 | |
| 第 6 节列出的模块，最差 slack | | |

## 上板
| 项目 | 结果 | 关键数字 |
|---|---|---|
| board_npu | | PERF0、fps |
| 实时识别 5 min | | fps、npu、wait、decode、post_span、gui、e2e（范围） |
| 图片识别 | | 候选数、PC 端显示 |
| 图像处理页 | | 界面帧率 |
| RND 拷贝 / 半透明叠加 | | |
| CoreMark | | Iterations/Sec、CoreMark/MHz |
| LVGL benchmark | | 平均 fps、ALL 平均渲染 ms |

## 问题与偏离
```
