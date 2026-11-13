# 卡 72：瘦身第一步后的整片 SoC（含 NPU 硬件后处理）：布局布线与上板

## 1. 目标

卡 70 加入 NPU 硬件后处理后布线不收敛：第 7–9 轮未布通数相对卡 68 为 ×1.037→×1.066，比失败的卡 69 偏离更快。本卡用瘦身第一步后的 RTL，在卡 70 的工程上重新综合、布局布线、上板，确认三件事：
1. 布线能收敛，时序和卡 68 相当；
2. 硬件后处理在板上工作：`decode` 从约 21 ms 降到约 1 ms；
3. 瘦身后性能不变：NPU 每帧周期、LVGL 跑分、图像处理画面。

**本卡取代卡 70**。卡 71（三种调度方式对比）改用本卡的比特流。

**瘦身第一步**（设计记录 `docs/design/2026-11-13-soc-slim.md` 第 4 节），参考综合估算省约 4.5K LUT、2K FF：
- NPU：残差加法去掉 512 位旁路副本；删除 PERF2–7（报告 `docs/reports/2026-11-13-slim1-npu.md`）；
- RND：拷贝两侧对齐合并为一次；
- PIX：min/max 归约合用；
- 删除 PIX PERF1–3、GEO PERF1–5、DISP PERF2–6（报告 `docs/reports/2026-11-13-slim1-media.md`）。

**对照**

| 项 | 卡 68 R2 | 卡 70 |
|---|---|---|
| 资源（Device Map） | LUT 91,208 / FF 107,042 / DRM 286 / APM 372 | LUT 93,252 / FF 110,423 / DRM 298 / APM 373 |
| 布线 | 第 176 轮收敛，2h25m | 第 9 轮已比卡 68 多 6.6% 未布通，判断不收敛 |
| 慢角 WNS（clk_sys / clk_npu / clk_mem，ns） | −0.088 / −0.205 / −0.025 | 未取得 |
| board_npu C-YOLO | PERF0 6,190,102，34.389 ms | 未取得 |
| LVGL benchmark | 平均 23 fps，ALL 平均渲染 42.637 ms | 未取得 |
| 实时识别 | 15–26 fps；decode 20.8 ms；e2e 100–144 ms | 未取得 |

卡 68 第 7–40 轮未布通数（用于止损对照）：7 → 147,564；9 → 117,783；20 → 37,409；40 → 11,159。

## 2. 输入

| 项 | 内容 |
|---|---|
| 代码 | `origin/zc100116/b3` 上包含本卡的提交，从这里拉出 `win/20261113-72-soc-slim1-post`，记录 HEAD |
| 工程 | 卡 70 的 `G:/codex_project/EdRV32-FPGA/EdRV32-B3F-POST`，直接沿用（已含 3 个后处理 IP，查表 RAM 的端口名已按 `a_*/b_*` 修正） |
| 导入脚本 / 约束 | 与卡 68、70 相同 |
| 程序 | 沿用卡 70 的 `tasks/win/20261108-70-soc-npu-post/src/showcase-post.elf` 和 `src/board_npu.elf`（本次只改 RTL，软件不变） |
| 调试工具 | 本 checkout 的 `tools/debug_tool` |

## 3. 环境

- PDS 2022.2-SP6.1，PG2L200H-6 FBB676。
- **PnR 期间仿真虚拟机必须关机**，也不运行其他占内存的程序。

## 4. 需要的 IP

无新增。沿用卡 70 工程中的全部 IP。

## 5. 操作步骤

| 步骤 | 执行者 | 内容 |
|---|---|---|
| 0 | Windows Codex（C） | `git fetch origin`，`git switch -c win/20261113-72-soc-slim1-post origin/zc100116/b3`，记录 HEAD 和空闲物理内存。 |
| 1 | 用户（U） | 关闭仿真虚拟机。 |
| 2 | U 或 C | 在 `EdRV32-B3F-POST` 中清空源文件列表，在工程目录下 `source ../../EdRV32-Competition-2026/fpga/scripts/import_board_full_top.tcl`；然后 Compile、`synthesize -ads`、`dev_map`。记录综合资源，并与卡 70 对比 `u_npu`、`u_rnd`、`u_pix`、`u_geo`、`u_disp` 的 LUT / FF。 |
| 3 | U | PnR 参数与卡 68 完全相同（Slack Weight 40），运行 `pnr`。截图设置页。 |
| 4 | C | 每小时记录：布线轮次、单轮耗时、未布通数、过用数、空闲内存。<br>**止损**（出现任意一条就停止并回报）：<br>- 工具报 Route-0039 / Route-0008；<br>- 第 20 轮未布通数大于 45,000（卡 68 为 37,409）；<br>- 第 40 轮未布通数大于 15,000（卡 68 为 11,159，卡 69 为 16,854）；<br>- 单轮耗时持续超过 600 s。 |
| 5 | U + C | 布通后按第 6 节导出，生成比特流。有时序违例也照常上板，时序和功能分开报告。 |
| 6 | U | 下载比特流，KEY1 复位进入 BIOS，记录 `CLK_SYS_HZ`。 |
| 7 | U + C | **board_npu** 跑 1 次：39/39，D 组 CRC 一致；记录 C-YOLO 的 PERF0 和 fps。 |
| 8 | U + C | **showcase**（`showcase-post.elf`，加载方法同卡 68）：<br>- 实时识别连续运行 5 分钟，保存全部 `vision fps=` 串口行；检测框位置和类别正常；<br>- 图片识别页跑 1 次，PC 端调试工具能收到并显示候选；<br>- 图像处理页：两级 3×3 分别设为高斯和 Sobel，运行 1 分钟，拍照记录界面显示的帧率，画面无错乱；<br>- CoreMark 1 次；<br>- LVGL benchmark 完整跑 1 次。<br>记录死机、复位、画面错乱、框位置明显错误等异常。 |
| 9 | C | 整理 result.md，推送 `win/20261113-72-soc-slim1-post`。 |

## 6. 产物

放在 `tasks/win/20261113-72-soc-slim1-post/artifacts/`：
- **时序**：
  - 三个时钟域、快慢两角的 WNS/TNS/WHS/THS 汇总；
  - 每个域 slack ≤ +0.5 ns 的全部 setup 路径，一行一条：起点、终点、slack、逻辑级数、逻辑延迟、走线延迟；
  - 每个域最差 20 条路径的逐级明细；
  - `u_npu/u_post*` 下 slack ≤ +0.5 ns 的路径单独列出。
- **资源**：汇总（已用 / 总数）、按模块层次的分布、CLMA / CLMS 占用。
- **布线**：每轮的轮次、耗时、未布通数、过用数；最终拥塞网格和 PNG。
- **上板**：`uart/*.log`；`photos/`（识别画面、图像处理页、CoreMark）；`benchmark.txt`。

## 7. 通过判据

- 布通并生成比特流；
- board_npu 39/39；
- 实时识别 5 分钟无异常，`decode` 明显低于卡 68 的 20.8 ms；
- 图片识别的 PC 端能收到并显示候选；
- 所有数字都取自报告或日志原文，找不到的写"未取得"。

## 8. result.md 模板

```markdown
# 卡 72 结果

| 项 | 内容 |
|---|---|
| 代码 HEAD | |
| 收敛轮次 / PnR 用时 | |
| CLK_SYS_HZ | |

## 资源（已用 / 总数，与卡 68、卡 70 对比）
| 项 | 卡 68 | 卡 70 | 卡 72 |
|---|---|---|---|
| LUT / FF / DRM / APM | | | |
| CLMA / CLMS | | | |
| u_npu / u_rnd / u_pix / u_geo / u_disp 的 LUT/FF | | | |

## 布线（未布通数）
| 轮次 | 卡 68 | 卡 72 |
|---|---|---|
| 7 / 9 / 20 / 40 / 100 / 收敛 | | |

## 时序
| 时钟域 | 约束 MHz | 慢角 WNS / TNS | 快角 WHS / THS | 违例端点 |
|---|---|---|---|---|
| clk_sys | 125 | | | |
| clk_npu | 180 | | | |
| clk_mem | 125 | | | |
| u_npu/u_post* 最差 slack | | | | |

## 上板
| 项目 | 结果 | 关键数字 |
|---|---|---|
| board_npu | | PERF0、fps |
| 实时识别 5 min | | fps、npu、wait、decode、post_span、gui、e2e（范围） |
| 图片识别 | | 候选数、PC 端显示 |
| 图像处理页 | | 界面帧率 |
| CoreMark | | Iterations/Sec、CoreMark/MHz |
| LVGL benchmark | | 平均 fps、ALL 平均渲染 ms |

## 问题与偏离
```
