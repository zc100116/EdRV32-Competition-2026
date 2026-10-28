# CPU 子系统第三轮时序与资源（C-W4）

| 项 | 内容 |
|---|---|
| commit | `2960c57`（C-R7 之后，RTL 与 `main` 的 `3bfc8f7` 相同） |
| 任务卡 | `tasks/win/20261028-01-cpu-npu-synth/` A 部分 |
| 工具 | PDS 2022.2-SP6.1（build 138931），Timing Models Pre-silicon |
| 器件 | PG2L200H-6 FBB676 |
| 顶层 / 约束 | `edrv32_fpga_cpu_sys_top`，`edrv32_fpga_cpu_sys_top.fdc`：clk_sys 6.667 ns（150 MHz） |
| 原始数据 | `tasks/win/20261028-01-cpu-npu-synth/artifacts/cpu/`；完整报告在 Windows `G:/codex_project/EdRV32-FPGA/EdRV32/` |

## 时序

| 角 | WNS ns | TNS ns | WHS ns | setup 违例端点 | Fmax（`1000 / (6.667 − WNS)`） |
|---|---|---|---|---|---|
| slow | −2.324 | −8602.632 | +0.143 | 9196 / 39621 | 111.2 MHz |
| fast | +1.222 | 0 | +0.100 | 0 / 39621 | — |

与上一轮（20261027-02 A，C-R6 之后）对比：slow WNS −3.920 → −2.324 ns（94.5 → 111.2 MHz），TNS −19583.569 → −8602.632 ns，违例端点 12645/43021 → 9196/39621；fast 角上一轮 −0.069 ns、7 个违例，本轮无违例。

### 最差路径

`u_core/e_operand_a_r[0][2]` → `u_predictor/ras_data_r[116]` 的 CE，19 级，逻辑 2.770 ns、布线 5.821 ns（67.8%），裕量 −2.324 ns。逐级经过：

1. E 级地址加法 `e_operand_a + imm`（进位链）→ `dc_req_addr`
2. D$ PMA 译码 → `dc_req_ready`（`edrv32_dcache.v` 维护期间 ready 取决于 PMA 的设备判定）
3. core E 级推进 → IB 空位数（`edrv32_cpu_ib.v`：`4 − count + pop_count`）
4. 前端推进 → predictor RAS 写使能（扇出 32）

### 分组（slow 角）

| 组 | 起点 → 终点 | 最差裕量 ns | 级数 | 上一轮 |
|---|---|---|---|---|
| G1 | D$ `addr_r` → CSR `counter_r` | 无此类路径 | — | −3.920 / 24 |
| G2 | E 级操作数 → RAS `ras_data_r` | −2.324 | 19 | −3.233 / 17 |
| — | E 级操作数 → 前端 `f1_cross_target_r` | −2.303 | 18 | — |
| G3 | F2 PC → RAS | 无此类路径 | — | −3.102 / 9 |
| G4 | E 级操作数 → 前端 `f1_pc_r` | −2.251 | 18 | −3.085 / 17 |
| — | D$ tag RAM → RAS | −2.191 | 12 | — |
| — | E 级操作数 → I$ `addr_r` | −2.185 | 17 | — |
| — | D$ tag RAM → 前端 `f1_pc_r` / `f1_cross_target_r` / I$ `addr_r` | −2.118 / −2.170 / −2.052 | 10–11 | — |
| — | E 级操作数 → D$ `dirty1_r` | −1.993 | 17 | — |
| — | E 级操作数 → IB `entries_r` | −1.939 | 16 | — |
| G5 | F2 PC → IB `entries_r` | +3.865 | 2 | −2.892 / 10 |
| G6 | 任意 → I$ 数据 RAM 读端口 | −1.567 | 17 | — |

前 10 组中，除 D$ `dirty1_r` 外，终点都在前端（RAS、F1 PC、I$ 地址、IB），起点是 E 级操作数或 D$ tag RAM，都经过 `dc_req_ready` → E 级推进 → IB 空位这一段。正裕量最差的一批路径只有 +0.001 至 +0.021 ns（例如 `e_operand_a_r` → `m_result_r`，12 级）。

## 资源（PnR 后）

| LUT | FF | 分布式 RAM | DRM36K 当量 | APM | IO |
|---|---|---|---|---|---|
| 15426 | 8369 | 231 | 26 | 4 | 9 |

上一轮 14879 LUT、8319 FF、26 DRM。按层次：`u_core` 10683 LUT（其中 frontend 3933、csr 1811、IB 1181、predictor 1294），`u_dcache` 2535，`u_icache` 721，`u_sys_subsys` 1440。

## 其他

- 映射阶段高扇出：`u_cache_ctrl/N44` 3807，`u_predictor/N5893` 1024。
- 综合对寄存器堆 `registers_r` 报 2 行 Sdm-2010（RAM 不支持多口同时写）；实际映射方式未核对，C-S1 定稿第 5 项时核对。
- 未约束 IO 8 个（测量顶层，不做 IO 时序判定）。
