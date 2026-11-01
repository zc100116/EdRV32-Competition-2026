# ila_cpu：CPU 性能计数器与流水线观察用的 ILA 调试核

| 项 | 内容 |
|---|---|
| 用途 | 1. 用硬件计数器核对 CoreMark 的实际周期数、指令数和 HPM 事件，与串口打印对照；2. 竞赛要求"利用 ILA 抓取的波形图，分析 CPU 在执行 CoreMark 关键算法时的流水线效率"（`docs/reference/2026-ziguang-guide.md` 技术实现与文档 (2)） |
| 观察对象 | A 组：cpu-spec 7.1 的现有计数器（CSR 内部寄存器）；B 组：cpu-spec 7.2 的 `debug_o[63:0]`，在 B3F 顶层寄存一拍，寄存器为 `ila_cpu_r[63:0]`。计数器方案和 CPU RTL 都不改 |
| 插入方式 | PDS 的调试核插入工具（Inserter），在综合之后、Device Map 之前从综合网表中选信号；不使用 IP Compiler |
| 器件 | PG2L200H-6 FBB676，PDS 2022.2-SP6.1 |
| 首次使用 | 卡 31。GUI 的具体菜单路径由 Windows Codex 按本机 PDS 自带的调试工具用户指南确认，写进 result.md 后回填到本说明 |

## 调试核参数

| 参数 | 值 |
|---|---|
| 采样时钟 | `clk_sys`（PLL `u_pll_sys` CLKOUT0 经全局缓冲后的网络，100 MHz） |
| 数据探针 | A 组 400 位 + B 组 64 位，共 464 位，按下表分组命名 |
| 触发探针 | B 组 `retire_pc`、`retire`（触发只用这两组） |
| 采样深度 | 1024 |
| 触发位置 | 前 10% |
| 存储限定 | 不使用 |

资源估算：464 位 × 1024 ≈ 475 Kbit，约 13–14 个 DRM36K，另加少量 LUT/FF（估算，以卡 31 的 Device Map 为准）。

## A 组：性能计数器（cpu-spec 7.1，`u_cpu/u_core/u_csr` 内）

每个计数器取低 40 位（2⁴⁰ 个周期在 100 MHz 下约 3 小时，足够覆盖一轮 CoreMark）。综合后的实例名以网表为准，在卡 31 中确认后回填。

| 组名 | RTL 寄存器 | 位 | 含义 |
|---|---|---|---|
| `mcycle` | `cycle_r` | [39:0] | 周期数 |
| `minstret` | `instret_r` | [39:0] | 退休指令数 |
| `hpm3` … `hpm10` | `counter_r[0]` … `counter_r[7]` | [39:0] | mhpmcounter3–10，统计哪种事件由 mhpmevent3–10 决定 |

monitor 的 CoreMark 测量（`sw/apps/monitor/benchmark.c`、`hpm.c`）已经分两轮配置事件：第 1 轮事件 1–8，第 2 轮事件 9–16。每轮开始前把 mcycle、minstret 和 HPM 清零，用 `mcountinhibit` 只在 `iterate()` 期间计数，结束后把每个计数器从串口打印出来。软件不需要修改。

## B 组：流水线（cpu-spec 7.2，`ila_cpu_r`）

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

函数地址从 `build/sw/monitor/monitor.dis` 中查。

1. **核对跑分**：触发条件设为 `retire_pc` 等于 `monitor_hpm_read` 的入口。此时计数已被 `mcountinhibit` 冻结，A 组的值就是这一轮的最终计数，可以和串口的 `HPM round cycles`、`HPM round instructions` 以及各事件计数逐项对比。每轮触发一次，第 1 轮抓完后重新布防再抓第 2 轮。
2. **流水线效率**：触发条件设为 `retire_pc` 等于 CoreMark 关键函数（`core_list_find`、`crcu8`、`matrix_mul_matrix`、`core_state_transition` 等）的入口，看 B 组 1024 个周期的波形，统计每周期退休条数分布、双发射比例、各类停顿和重定向所占周期。每个函数抓一次。
