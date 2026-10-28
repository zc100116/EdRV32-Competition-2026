# CPU 时序探针 P1–P3 的 PDS 测量（C-W6）

| 项 | 内容 |
|---|---|
| commit | 任务卡 `f757c4f`；探针源文件为卡内 `src/p1|p2|p3/`（取自 `15d21f8` / `2ec4170` / `3615a7e`） |
| 任务卡 | `tasks/win/20261028-04-media-cpu-probes/`（B 部分），结果提交 `756ebfc` |
| 工具 | PDS 2022.2-SP6.1（build 138931），ADS 综合 |
| 器件 | PG2L200H-6 FBB676 |
| 顶层 / 约束 | `edrv32_fpga_cpu_sys_top`，clk_sys 6.667 ns（150 MHz）；P2、P3 另加探针约束（实际全文 `artifacts/cpu/<版本>/fdc_used.fdc`） |
| 原始数据 | `tasks/win/20261028-04-media-cpu-probes/artifacts/cpu/{p1,p2,p3,p3_noregion}/`；完整报告在 Windows `G:/codex_project/EdRV32-Competition-2026/build/win/20261028-04-media-cpu-probes/cpu/` |
| 周期数据 | `docs/reports/2026-10-28-perf-cpu-probes.md`（评估分支 `probe/cpu-timing`）：P1 实测，P2/P3 为周期模型 |

## 版本

| 版本 | 内容 |
|---|---|
| P1 | RVC_EN = 0，软件 rv32im；功能正确 |
| P2 | P1 + 前端的全部后端输入寄存一拍（重定向代价 E 3 → 4、D 2 → 3） |
| P3 | P2 + I$/D$ 命中寄存、乘法和 load 只从寄存级旁路（load 2 → 3、mul 3 → 4）、CSR 计数器进位寄存 |
| P3_noregion | P3 去掉 core 区域约束（区域坐标在 PDS 中非法，P3 停在约束检查，见"约束确认"） |

P2、P3 功能不正确，只用于测量。

## 时序（slow 角）

| 版本 | WNS ns | TNS ns | 违例端点 | Fmax MHz（`1000 / (6.667 − WNS)`） | WHS ns |
|---|---:|---:|---:|---:|---:|
| 第四轮 RVC=1（`6a9cd92`） | −1.789 | −4967.383 | 7611 | 118.3 | +0.152 |
| P1 | −1.078 | −2866.648 | 8196 | 129.1 | +0.143 |
| P2 | −0.762 | −319.292 | 1361 | 134.6 | +0.113 |
| P3_noregion | −0.534 | −67.345 | 432 | 138.9 | +0.145 |

fast 角三版均无 setup 违例；三版 hold、recovery、removal 均无违例。

## 性能（Fmax × CoreMark/MHz）

CoreMark/MHz：第四轮和 P1 为实测，P2、P3 为周期模型折算（`2026-10-28-perf-cpu-probes.md`）。

| 版本 | Fmax | O2 CoreMark/MHz | O2 CoreMark | tuned CoreMark/MHz | tuned CoreMark | 相对 P1（O2 / tuned） |
|---|---:|---:|---:|---:|---:|---|
| 第四轮 RVC=1 | 118.3 | 3.5529 | 420.2 | 4.3372 | 512.9 | −9.4% / −7.4% |
| P1 | 129.1 | 3.5925 | 463.8 | 4.2908 | 554.0 | — |
| P2 | 134.6 | 3.4972（模型） | 470.7 | 4.1422（模型） | 557.6 | +1.5% / +0.6% |
| P3_noregion | 138.9 | 2.9475（模型） | 409.3 | 3.5963（模型） | 499.4 | −11.8% / −9.9% |

## 违例分组（全部违例端点，按起点/终点寄存器）

完整列表 `artifacts/cpu/<版本>/endpoints_violating.tsv`、分组 `endpoint_groups.txt`。

**P1**（−1.078 ns）

| 起点 → 终点 | 端点数 | 最差 ns | 级数 |
|---|---:|---:|---:|
| I$ `addr_r` → IB `entries_r` | 485 | −1.078 | 6 |
| D$ tag0 RAM → core 旁路（`N791_17`、`N630_15`） | 30 + 30 | −1.036 | 8 |
| E 级 `e_operand_a_r` → `f1_pc_r` | 19 | −1.032 | 11 |
| `f1_pc_r` → RAS `ras_data_r` | 128 | −0.999 | 9 |
| E 级 `e_operand_a_r` → RAS | 333 | −0.993 | 11 |
| `f1_pc_r` → `f1_pc_r` | 35 | −0.947 | 15 |
| D$ tag0 RAM → `dirty0_r` / `dirty1_r` / `buffer_addr_r` | 502 + 480 + 17 | −0.847 | 7 |

**P2**（−0.762 ns）：D$ tag1 RAM → `dirty0_r`/`dirty1_r`（603 + 309，−0.762，9 级）；乘法 APM → core 旁路（−0.515，5 级）；D$ tag0 RAM → `e_record_r`、`e_imm_r`、旁路（−0.321 至 −0.285，7 级）。

**P3_noregion**（−0.534 ns）：predictor `history_r` → RAS `ras_data_r`/`f1_pc_r`/`ras_count_r`（109 + 20 + 5，−0.534，8 级）；D$ `addr_r` → `w_result_r`（−0.405）；D$ tag1 RAM → dirty（−0.314）；IB `read_ptr_r` → `e_record_r`、CSR `instret_r`（−0.214、−0.143）。

## 资源（PnR 后）

| 版本 | LUT | FF | DRM36K 当量 | APM | 分布式 RAM | u_core LUT / FF |
|---|---:|---:|---:|---:|---:|---|
| 第四轮 RVC=1 | 15204 | 8367 | 26 | 4 | 231 | 10625 / — |
| P1 | 14750 | 8362 | 26 | 4 | 151 | 10140 / 5412 |
| P2 | 15567 | 8657 | 26 | 4 | 151 | 10237 / 5703 |
| P3_noregion | 15232 | 8714 | 26 | 4 | 151 | 10244 / 5771 |

## 约束确认

- `.fdc` 中的 `syn_preserve` / `syn_keep` 在本版 PDS 报 ConstraintEditor-0046（属性无效）。
- 6 个复制的重定向 valid 在 Compile 阶段（读 FDC 之前）就被合并为 2 个（"redundant to ..."），`PAP_DONT_TOUCH` 作用于 Device Map，不能恢复。**P2 的"复制"没有生效**，P2 数据只反映"寄存一拍"。
- 区域约束写法为 `define_global_attribute {PAP_REGION} {name(x0,y0,x1,y1)}` 加 `define_attribute` 关联实例；坐标网格为 x 0..238、y 0..249（`clock_utilization.txt`），卡中候选坐标尺度错误，P3 报 ConstraintEditor-0027 停止。
- 层次分隔符为 `.`，`i:` 表示实例（UCE 手册第 68 页）。
