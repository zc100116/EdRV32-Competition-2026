# ila_cpu：CPU 性能计数器与流水线观察用的 ILA 调试核

| 项 | 内容 |
|---|---|
| 用途 | 1. 用硬件计数器核对 CoreMark 的实际周期数、指令数和 HPM 事件，与串口打印对照；2. 竞赛要求"利用 ILA 抓取的波形图，分析 CPU 在执行 CoreMark 关键算法时的流水线效率"（`docs/reference/2026-ziguang-guide.md` 技术实现与文档 (2)） |
| 观察对象 | cpu-spec 7.1 的现有计数器（CSR 内部寄存器）：mcycle、minstret、mhpmcounter3–10。它们有 CSR 读负载，综合后保留（卡 31 的网表中能找到）。卡 31 中没有负载的 `debug_o` 寄存器被综合删掉，初赛版不再观察 `debug_o`。T-FANOUT-CPU 之后，HPM 计数器位于 `u_csr/g_counter[2..9].g_hpm.count_r`，mcycle/minstret 仍为 `cycle_r`/`instret_r`。计数器方案和 CPU RTL 都不改 |
| 插入方式 | PDS 的调试核插入工具（Inserter），在综合之后、Device Map 之前从综合网表中选信号；不使用 IP Compiler |
| 器件 | PG2L200H-6 FBB676，PDS 2022.2-SP6.1 |
| 首次使用 | 卡 33（卡 31 未插入成功）。GUI 的具体菜单路径由 Windows Codex 按本机 PDS 自带的调试工具用户指南确认，写进 result.md 后回填到本说明 |

## 调试核参数

| 参数 | 值 |
|---|---|
| 采样时钟 | `clk_sys`（PLL `u_pll_sys` CLKOUT0 经全局缓冲后的网络，100 MHz） |
| 数据探针 | A 组 400 位，按下表分组命名 |
| 触发探针 | `minstret`、`mcycle`（数值比较） |
| 采样深度 | 1024 |
| 触发位置 | 前 10% |
| 存储限定 | 不使用 |

资源估算：400 位 × 1024 ≈ 410 Kbit，约 12 个 DRM36K，另加少量 LUT/FF（估算，以卡 33 的 Device Map 为准）。

## A 组：性能计数器（cpu-spec 7.1，`u_cpu/u_core/u_csr` 内）

每个计数器取低 40 位（2⁴⁰ 个周期在 100 MHz 下约 3 小时，足够覆盖一轮 CoreMark）。综合后的实例名以网表为准，在卡 33 中确认后回填。

| 组名 | RTL 寄存器 | 位 | 含义 |
|---|---|---|---|
| `mcycle` | `cycle_r` | [39:0] | 周期数 |
| `minstret` | `instret_r` | [39:0] | 退休指令数 |
| `hpm3` … `hpm10` | `g_counter[2].g_hpm.count_r` … `g_counter[9].g_hpm.count_r` | [39:0] | mhpmcounter3–10，统计哪种事件由 mhpmevent3–10 决定 |

monitor 的 CoreMark 测量（`sw/apps/monitor/benchmark.c`、`hpm.c`）已经分两轮配置事件：第 1 轮事件 1–8，第 2 轮事件 9–16。每轮开始前把 mcycle、minstret 和 HPM 清零，用 `mcountinhibit` 只在 `iterate()` 期间计数，结束后把每个计数器从串口打印出来。软件不需要修改。

## 运行时使用（上板时）

1. **核对跑分**：`monitor_hpm_stop()` 在 `iterate()` 结束时把全部计数器同时冻结；随后 `monitor_hpm_release()` 会重新放开 mcycle/minstret（HPM 保持冻结），所以串口打印之后再手动触发，mcycle/minstret 已经不是最终值（卡 34）。正确做法：触发条件设为 `minstret` 等于该轮的指令数（串口 `HPM round instructions`，同一程序和迭代次数下每次相同；O2、5000 次为 1441025033 = 0x55E44C09）。冻结期间 minstret 停在这个值上，触发点上 mcycle 就是该轮的 `HPM round cycles`，hpm3–10 就是该轮 8 个事件的最终计数。第 1 轮触发后重新布防，抓第 2 轮（第 2 轮开始时计数器清零，minstret 会再次到达同一个值）。另有一条自洽检查：第 1 轮的事件 1–3（dual/single/zero retire）之和等于周期数，single + 2×dual 等于指令数。
2. **流水线效率**：在 CoreMark 运行中，触发条件设为 `minstret` 等于某个中间值（例如该轮指令数的一半，从第 1 次串口结果估算），采 1024 个周期。`minstret` 每周期的增量就是这一拍退休的条数（0/1/2），可以统计 IPC 和双发射比例；HPM 各计数器每周期的增量，是对应事件（第 1 轮为事件 1–8，第 2 轮为 9–16：load-use、D$/I$ 缺失、配对失败、重定向等）发生的周期。用这些增量画出关键算法区间的流水线效率波形。
