# RND 与 DISP 两层实施方案（board-plan B3-1、B3-2）

| 项 | 内容 |
|---|---|
| 版本 | v0.1 |
| 日期 | 2026-10-29 |
| 方案 | `docs/design/2026-10-29-rnd-disp.md`（已确认） |
| 规格 | `docs/spec/rnd-spec.md` v0.2、`disp-spec.md` v0.3（已确认）；SoC 规格 v0.16 |
| 验证方案 | `docs/testplan/rnd-testplan.md` v0.1、`disp-testplan.md` v0.3 |

## 1. 目标和完成标准

- RND：
  - 按 `rnd-spec` v0.1 实现；
  - `rnd-testplan` smoke、full 档通过（RN-17 除外，它随 B3-3 完成）；
  - perf 档 RN-18 测得的数字回填规格第 7 节。
- DISP：
  - 按 `disp-spec` v0.3 实现两层叠加；
  - `disp-testplan` v0.3 smoke、full 档通过；
  - 复位值下的单层行为与 v0.2 一致（B2 的软件不改）。
- 集成：
  - RND 接入 `edrv32_soc_top`（P4、媒体 APB 槽 4、PLIC 源 11）；
  - PDS 测得 media（VIN + PIX + DISP）和 RND 的时序、资源，回填 SoC 9.3 和两份规格的 [待定] 项。

## 2. 前置条件

- `dma2d_rd/wr`、`edrv32_async_fifo_ram` 和 DISP 扫描 FIFO 的存储包装 `edrv32_ram_disp_scan`（V-P1）已在仓库中。
- RND 接入顶层（R-S2）依赖 B2-1a（`edrv32_soc_top`）合入。
- **DISP 两层的合入时机**：
  - D-R1 可以与 B2 并行开发。
  - 合入协调者分支要等 B2-6 的 PDS 跑完，以免改变 B2 正在收敛的 media 时序（r4：+0.592 ns @ 135 MHz）。
  - 到时由协调者向用户确认。

## 3. 待办清单

| 编号 | 内容 | 执行者 | 依赖 | 验收 | 分支 | 状态 |
|---|---|---|---|---|---|---|
| R-S1 | 设计决策；RND、DISP v0.3、SoC v0.16 规格；两份验证方案；本方案 | 协调者 + 用户确认 | — | 规格已确认 | — | [x] 2026-10-29 |
| D-R1 | DISP v0.3 RTL：L1 读描述符和顺序（2.5）、L1 扫描 FIFO、本帧参数握手（2.4 第 6 条）、L0 卷轴、按层欠账、clk_pix 混合（2.7）、新寄存器和 PERF5–6；单元测试 | Codex · GPT-6.1 Sol | R-S1 | `verif/unit/disp*` smoke/full 通过，lint 0 告警；Yosys 参考 LUT | task-disp-layers | [x] 2026-10-29：分支 zc100116/task-disp-layers 23ed7ad（未合入）；单元 7/7 smoke/full，v0.2 block 兼容 12/12（授权副本）；Yosys LUT4 2947 → 6260；clk_mem 最长 16 → 50 级 → D-R2 |
| D-R2 | DISP v0.3 clk_mem 长组合路径切到不超过 v0.2 的 16 级（BUSY/停稳/SOFT_RST/APB 读、reader、L1 行地址），行为不变 | Codex · GPT-6.1 Sol | D-R1 | 同一 Yosys 脚本下 clk_mem 路径 ≤ 16 级；单元 smoke/full；block 兼容不变 | task-disp-layers（同分支） | [x] 2026-10-29：同分支 5a490f9、cfc7fb2（未合入）；clk_mem 非 DMA 路径 50 → 16 级，dma2d_rd 内部 24 级（批准例外）；Yosys LUT4 6260 → 6767；单元 7/7 smoke/full，v0.2 block 兼容 12/12（授权副本） |
| D-T1 | DISP 模块级测试按 testplan v0.3 增改（DS-03、06、07、09、12–19，`blend_ref.py`），不读被测 RTL | Codex · GPT-6.1 Sol | R-S1 | testbench 完成，参考模型自测通过 | task-disp-layers-verif | [x] 2026-10-29：分支 zc100116/task-disp-layers-verif 4be2d55（未合入，等 D-I1）；d(x) 穷举、Python/SV 553 万像素互比、lint 通过；在 v0.2 RTL 上只有预期的版本差异 |
| D-I1 | DISP 联调：block/disp smoke/full | Codex · GPT-6.1 Sol | D-R2、D-T1 | disp-testplan v0.3 smoke/full 通过 | task-disp-layers（同分支，cherry-pick D-T1） | [~] 2026-10-29 派发（ctx_6ef5826206c9）；用户决定跑完当前档后暂停，B2 上板后续作 |
| R-R1 | RND RTL 和单元测试：<br>• 命令执行、读客户端仲裁、alpha 通路（2 像素/拍，移植旧工程 `edrv32_render_alpha_pipe.v` 并改为 2.2 的非预乘 over）、256 位快速通路；<br>• 覆盖率（移植 `edrv32_render_round_*`，按 2.3 逐位规定改写）、GLYPH、BLIT、COPY、模糊和阴影（移植并改为 2.4）、TILEMAP（新写）。<br>片上存储需求整理后 ask 协调者建 IP 包装 | Codex · GPT-6.1 Sol | R-S1 | 单元测试通过，lint 0 告警；Yosys 参考 LUT；设计记录写明 dma2d 实例、片上缓冲组织（rnd-spec 3、5.2） | task-rnd-rtl | [x] 2026-10-29：分支 zc100116/task-rnd-rtl 70f833d（未合入）；功能 141 案例通过，ARGB BLIT 1.97 px/拍；Yosys 参考 21.2K LUT / 94 DSP（面积交 R-W1）；通用路径 I8 BLIT 仅 0.098 px/拍，不满足 5.2 → R-R2 |
| R-R2 | 通用像素路径流水化（rnd-spec 5.2 每拍 2 像素）：BLIT 全格式/缩放、GLYPH、TILEMAP、FILL 渐变/圆角、BORDER、BOX_SHADOW 着色；像素结果不变 | Codex · GPT-6.1 Sol | R-R1 | 吞吐表（I8 1:1 与 3× ≥ 1.5、A8 GLYPH ≥ 1.5、TILEMAP ≥ 1.0、圆角 FILL ≥ 1.5、ARGB BLIT ≥ 1.9）；unit smoke/full | task-rnd-rtl（同分支） | [x] 2026-10-29：同分支 516c031–5bb8e38（未合入）；I8 1:1 1.95、3× 1.99、A8 GLYPH 1.95、TILEMAP 1.36、圆角 FILL 1.99、ARGB BLIT 1.97 px/拍，A4 字形平均 509 周期/条；unit smoke/full 8/8，原期望值未改；Yosys 参考 26.9K LUT / 7.9K FF / 162 DSP，行 RAM 包装 5 → 17、调色板 2 → 6（约 70 DRM36K，**估算**：每个 512×256 按 SDP 512×64 拼 4 块）；最长 ltp 29 → 28 |
| R-P1 | RND 片上存储（行缓冲、调色板、瓦片缓存、Q 表等）的 IP 创建说明和包装模块，按 R-R1 提出的组织 | 协调者 | R-R1 提问 | `fpga/ip/`、`rtl/tech/` | — | [x] 2026-10-29：`ip_ram_rnd_line` ×5、`ip_ram_rnd_palette` ×2、Q 表为生成函数 `rtl/include/edrv32_rnd_q.vh`（e6ff241） |
| R-T1 | RND 模块级测试（`verif/block/rnd`，`rnd_ref.py`），按 rnd-testplan RN-01–16、18、19，不读被测 RTL | Codex · GPT-6.1 Sol | R-S1 | testbench 完成，参考模型自测通过 | task-rnd-verif | [x] 2026-10-29：ab6527b、b1a1950（随 R-I1 合入）；参考模型自测和 636 个场景通过，桩编译通过 |
| R-I1 | RND 联调：block/rnd smoke/full/perf；perf 数字写测量报告 | Codex · GPT-6.1 Sol | R-R2、R-T1、R-P1 | rnd-testplan smoke/full 通过；`docs/reports/<日期>-perf-rnd.md` | task-rnd-rtl（同分支，cherry-pick R-T1） | [x] 2026-10-29：已合入协调者分支（8e60efa）；block/rnd full 3/3（636 场景，含 10 种子随机）、perf 1/1，RTL 未改，失败全属测试（超时预算，调试记录 `2026-10-29-rnd-regression-timeouts.md`）；RN-18 无等待：ARGB 全屏填充 0.997 ms、RGB565 0.507 ms、BLIT 1.96 px/拍、A4 字形 439 周期/条；40 周期读延迟下字形 1904 周期/条（报告 `2026-10-29-perf-rnd.md`） |
| R-S2 | RND 接入 `edrv32_soc_top`：P4、槽 4（删去预留 SLVERR）、PLIC 源 11；`soc_connect` 增加 RND ID 和一条最小命令的 DONE 中断 | Codex · GPT-6.1 Sol | R-I1、B2-1a | `verif/soc/soc_connect` smoke 通过 | task-soc-rnd | [ ] |
| R-W1 | Windows：media（含 DISP 两层）与 RND 的 PDS 时序、资源 | 用户 + Windows Codex | D-I1、R-I1 | 任务卡结果；测量报告 | `tasks/win/<日期>-rnd-pds/` | [ ] |

软件（LVGL 子模块和绘制单元驱动、S3、S1 画框改到 L1、网口发送帧）、游戏和 NES 移植在 `board-plan.md` B3-3、B3-4。

## 4. 规格定稿项

| 项 | 时机 | 依据 |
|---|---|---|
| SoC 9.3：VIN + PIX + DISP 12K、RND 10K | R-W1 之后 | PDS 资源报告 |
| disp-spec 7（DISP ≤ 4K LUT、DRM）、9 #1–2（两个 FIFO 深度） | R-W1、SoC 级 S1 满负载仿真之后 | PDS 报告、P0 最长等待 |
| rnd-spec 7（填充时间、alpha 吞吐）、9 #3（索引格式） | R-I1、R-W1 之后 | RN-18、PDS 报告 |
| rnd-spec 7（LVGL 帧率）、rnd-testplan RN-17 容差 | B3-3 之后 | 上板实测、差异分布 |

## 5. 风险和阻塞

- **RND 资源**：R-R2 后 Yosys 参考 26.9K LUT（预算 10K **[待定]**）、162 DSP、约 70 DRM36K（估算），2 像素/拍通用路径的代价主要在行 RAM 副本和双 lane 地址计算。按已定流程等 R-W1 的 PDS 数据由用户决定。
- **RND 资源（初值依据）**：T2 的命令种类多，10K LUT 的初值没有实测依据（旧工程 render 没有综合数据）。R-R1 的 Yosys 参考数和 R-W1 的 PDS 数据出来后，超出时由用户决定裁减范围（rnd-spec 9 #3）或调整预算。
- **media 时序**：DISP 两层后 clk_mem 侧增加 L1 读控制。r4 的余量只有 +0.592 ns，D-I1 后要重跑 PDS（R-W1）。
- **P0 实时性**：两层全屏 332 MB/s 是硬实时流量，必须在 SoC 级 S1 满负载仿真中证明两层都不读空（disp-spec 7）。

## 6. 变更记录

| 日期 | 版本 | 变更 |
|---|---|---|
| 2026-10-29 | v0.1 | 初稿 |
