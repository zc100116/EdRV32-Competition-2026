# ila_cpu：CPU 流水线观察用的 ILA 调试核

| 项 | 内容 |
|---|---|
| 用途 | 竞赛要求"利用 ILA 抓取的波形图，分析 CPU 在执行 CoreMark 关键算法时的流水线效率"（`docs/reference/2026-ziguang-guide.md` 技术实现与文档 (2)） |
| 观察对象 | cpu-spec 7.2 的 `debug_o[63:0]`，在 B3F 顶层 `edrv32_fpga_board_full_top` 中寄存一拍，寄存器为 `ila_cpu_r[63:0]`（`syn_preserve`，fabric 内没有负载） |
| 插入方式 | PDS 的调试核插入工具（Inserter），在综合之后、Device Map 之前插入；不使用 IP Compiler，也不改 RTL |
| 器件 | PG2L200H-6 FBB676，PDS 2022.2-SP6.1 |
| 首次使用 | 卡 31。GUI 的具体菜单路径由 Windows Codex 按本机 PDS 自带的调试工具用户指南确认，写进 result.md 后回填到本说明 |

## 调试核参数

| 参数 | 值 |
|---|---|
| 采样时钟 | `clk_sys`（PLL `u_pll_sys` CLKOUT0 经全局缓冲后的网络，100 MHz） |
| 数据探针 | `ila_cpu_r[63:0]`，共 64 位，按下表分组命名 |
| 触发探针 | 同一组 64 位（触发和数据共用） |
| 采样深度 | 8192 |
| 触发位置 | 前 10%（819 点触发前，其余触发后） |
| 存储限定 | 不使用 |

估算资源：64 位 × 8192 = 512 Kbit，约 14–16 个 DRM36K，另加少量 LUT/FF（估算，以卡 31 的 Device Map 为准）。

## 探针分组（cpu-spec 7.2）

| 组名 | 位 | 含义 |
|---|---|---|
| `f_valid` | [1:0] | F1、F2 有效 |
| `ib_count` | [4:2] | IB 中的指令数 |
| `d_valid` | [6:5] | D 槽 0/1 有效 |
| `e_valid` | [8:7] | E 管线 0/1 有效 |
| `m_valid` | [10:9] | M 管线 0/1 有效 |
| `w_valid` | [12:11] | W 管线 0/1 有效 |
| `stall` | [15:13] | D 级停顿、M 级停顿、前端停顿 |
| `redirect` | [17:16] | E 级、D 级重定向 |
| `trap` | [18] | 异常或中断进入 |
| `retire` | [20:19] | 本周期退休条数 |
| `pair_fail` | [23:21] | 配对失败原因 |
| `events` | [29:24] | load-use、除法、设备访问等待、I$ 缺失、D$ 缺失、WFI |
| `retire_pc` | [63:32] | 本周期退休的最老指令的 PC |

## 运行时使用（上板时）

- 程序：`PROGRAM=coremark`。触发条件设为 `retire_pc` 等于 CoreMark 关键函数（`core_list_find`、`crcu8`、`matrix_mul_matrix`、`core_state_transition` 等）的入口地址，地址从 `build/sw/coremark/*.dis` 中查。
- 每个函数抓一次。分析时从波形中统计：每周期退休条数分布、双发射比例、各类停顿和重定向所占周期。
