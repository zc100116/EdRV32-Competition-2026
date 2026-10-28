# CPU 子系统第四轮时序与资源（C-W5）

| 项 | 内容 |
|---|---|
| commit | `6a9cd92`（C-R8 之后） |
| 任务卡 | `tasks/win/20261028-03-cpu-sys-synth-r4/` |
| 工具 | PDS 2022.2-SP6.1（build 138931），Timing Models Pre-silicon |
| 器件 | PG2L200H-6 FBB676 |
| 顶层 / 约束 | `edrv32_fpga_cpu_sys_top`，`edrv32_fpga_cpu_sys_top.fdc`：clk_sys 6.667 ns（150 MHz） |
| 原始数据 | `tasks/win/20261028-03-cpu-sys-synth-r4/artifacts/`（结果分支 `win/20261028-03-cpu-sys-synth-r4`）；完整报告在 Windows `G:/codex_project/EdRV32-FPGA/EdRV32/` |

## 时序

| 角 | WNS ns | TNS ns | WHS ns | setup 违例端点 | Fmax（`1000 / (6.667 − WNS)`） |
|---|---|---|---|---|---|
| slow | −1.789 | −4967.383 | +0.152 | 7611 / 41070 | 118.3 MHz |
| fast | +1.197 | 0 | +0.101 | 0 / 41070 | — |

与上一轮（C-W4，C-R7 之后）对比：slow WNS −2.324 → −1.789 ns（111.2 → 118.3 MHz），TNS −8602.632 → −4967.383 ns，违例端点 9196 → 7611。hold、recovery、removal、最小脉宽均无违例。

### 最差路径

`u_core/e_jalr_expected_odd_r[4]` → `u_predictor/ras_data_r[109]` 的 CE，16 级，逻辑 2.885 ns、布线 5.267 ns（64.6%），裕量 −1.789 ns。逐级经过：

1. E 级 JALR 目标比较（32 位相等比较，进位链）→ `e_target_match_w`
2. E 级重定向判定 → `event_count_w[16]`（E 级重定向，网表名 `debug_o[17]`，扇出 86）
3. 前端：重定向参与 F2 响应接收 → `append_count_w` → `available_w` → `second_recover_w`（F2 误取恢复判定，扇出 34）
4. 重定向/恢复选择 → predictor RAS 写使能（扇出 32）

C-R8 切断的"地址加法 → D$ PMA → ready → IB 空位"链已不在前列。

### 分组（slow 角，最差一条）

| 组 | 起点 → 终点 | 裕量 ns | 级数 | 经过 |
|---|---|---|---|---|
| T01 | E 级 JALR 期望目标 → RAS | −1.789 | 16 | 上述最差路径 |
| T02 / G4 | D$ tag RAM → RAS | −1.753 | 11 | `hit0_w` → `m_ready_w` → 前端 → RAS 检查点恢复 `restore_link_w` |
| T03、T04 | E 级 JALR 期望目标 → `f1_cross_target_r`、`f1_pc_r` | −1.701、−1.686 | 16 | 同 T01 |
| G1–G3 | E 级操作数 → RAS、`f1_cross_target_r`、`f1_pc_r` | −1.698 至 −1.595 | 16 | 分支比较 → E 级重定向 → 同 T01 第 3、4 段 |
| T05 | I$ tag RAM → IB `entries_r` | −1.595 | 10 | `hit0_w` → 前端 → RVC 展开 `u_expand_first` → IB 写数据 |
| T06、G5 | E 级 → I$ `addr_r` | −1.568、−1.477 | 15 | E 级重定向 → I$ 请求地址 |
| T07、T08 | D$ tag RAM → E 级操作数 | −1.558、−1.523 | 11 | D$ 命中 → 旁路 |
| T09、T12 | 乘法器 APM 输出 → E 级操作数 | −1.52、−1.354 | 6 | APM 输出 → 旁路选择 |
| T10 | IB `entries_r` → CSR `counter_r` | −1.498 | 21 | 计数器 64 位进位链 |
| G7 | E 级操作数 → D$ 数据 RAM 读端口 | −1.011 | 13 | 地址加法 → RAM 读使能 |
| G8 | D$ tag RAM → `m_result_r` | −0.594 | 7 | — |

前 10 组中 7 组的终点在前端（RAS、F1 PC、I$ 地址、IB），起点是 E 级的分支/JALR 比较或 D$ tag RAM：后端本拍的重定向或停顿判定，组合地进入前端的 F2 恢复判定和状态更新使能。

正裕量最差的一批路径只有 +0.001 至 +0.019 ns（operand_b → operand_b、D$ tag → m_cause、IB read_ptr → CSR counter 等）。

## 资源（PnR 后）

| LUT | FF | 分布式 RAM | DRM36K 当量 | APM | IO |
|---|---|---|---|---|---|
| 15204 | 8367 | 231 | 26 | 4 | 9 |

上一轮 15426 LUT、8369 FF。按层次：`u_core` 10625 LUT（frontend 3869、csr 1816、IB 1146、predictor 1293），`u_dcache` 2404，`u_icache` 683，`u_sys_subsys` 1445。

## 其他

- 映射阶段高扇出：`u_cache_ctrl/N44` 3809，`u_predictor/N5893` 1024，`u_frontend/N21` 733，`push_count_w[1]` 706。
- Compile 对寄存器堆 `registers_r` 仍报 2 行 Sdm-2010（RAM 不支持多口同时写），C-S1 定稿第 5 项时核对实际映射。
- 8 个测量 IO 没有 IO 时序约束，路径另存 `unconstrained_io_paths.txt`，不作为接口时序结论。
