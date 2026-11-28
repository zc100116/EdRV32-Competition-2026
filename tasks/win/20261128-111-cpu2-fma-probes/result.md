# 卡 111 结果

**FP32 和 FP64 均完成布局布线，PDS 显示 All Constraints Met。** 165 MHz 名义约束对应 FDC 的 6.061 ns，PDS 显示 164.9893 MHz。

| 项 | 内容 |
|---|---|
| 运行的源码 HEAD | `2b458cb2a7ee2df5b1070270584c3de1aae64651` |
| PDS 版本 / 器件 | 2022.2-SP6.1 build 138931，ADS，PG2L200H-6 FBB676 |
| 布线设置 | 默认策略 `0`，实际 Tcl 为 `pnr`，无参数覆盖 |
| 工程路径 | `G:/codex_project/EdRV32-FPGA/cpu2_probe_fma_card111` 与 `G:/codex_project/EdRV32-FPGA/cpu2_probe_fma64_card111` |

## 工程 B（FP32）和工程 C（FP64）

时序表为布局布线后 Slow Corner，单位 ns。LUT、FF 等取 P&R 层次合计，control set 取 ADS 综合报告。

| 项 | B · FP32 | C · FP64 |
|---|---:|---:|
| WNS / TNS | +0.714 / 0.000 | +0.457 / 0.000 |
| WHS / THS | +0.196 / 0.000 | +0.141 / 0.000 |
| 估算 Fmax（MHz） | 187.0208 | 178.4440 |
| LUT / FF | 2,548 / 1,832 | 5,375 / 6,589 |
| DRM / APM / 分布式 RAM LUT / I/O | 0 / 2 / 0 / 10 | 0 / 12 / 0 / 10 |
| Use of CLMA | 659 / 30,075（3%） | 1,805 / 30,075（7%） |
| Use of CLMS | 185 / 9,875（2%） | 611 / 9,875（7%） |
| Control set 数 | 119 | 455 |
| 布通网数与 P&R 墙钟用时 | 3,806 / 3,806，1 分 55 秒 | 10,721 / 10,721，2 分 56 秒 |

- **FP32 最差 setup** 为 `e5_c_r[60] → e6_reverse_count0_r[4]`，6 逻辑级，逻辑 / 布线延迟 **1.411 / 3.657 ns**。卡 110 第 3 轮旧 FP32 探针同约束估算 179.1794 MHz，资源为 3,111 LUT、1,097 FF。 [FP32 路径明细](artifacts/fma32/setup_top20_detail.txt) · [卡 110 基线](https://github.com/zc100116/EdRV32-Competition-2026/blob/38ea6392/tasks/win/20261127-110-cpu2-probes/result.md)
- **FP64 最差 setup** 为 `u_product/u_term11/u_apm/gopapm/CLK → t1_magnitude_r[0]`，7 逻辑级，逻辑 / 布线延迟 **1.834 / 3.558 ns**。 [FP64 路径明细](artifacts/fma64/setup_top20_detail.txt)

时序导出均使用对应 GUI 布线数据库的副本。每份常规扩展报告与原 GUI 汇总一致，含 200 个不同 setup 终点、最差 20 条 setup 逐级明细和快慢角各 20 条 hold 路径。另用 PDS 按 APM 起终点筛选级联，PDS 明细用 `PO/PI` 标出专用路径。

| APM 最差级联路径 | Slow setup | Slow hold | Fast hold |
|---|---:|---:|---:|
| FP32 `u_head → u_tail/PI[0]` | +4.254 | +0.582 | +0.320 |
| FP64 `u_term5 → u_term6/PI[0]` | +4.222 | +0.549 | +0.299 |

Device Map 的 APM 推断原文为 FP32 `insts:2`、FP64 `insts:12`。Compile 到 Report Timing 的最终阶段日志中，未发现 APM 级联、CPI/CPO 或内部寄存器相关告警或错误。 [FP32 分段与级联](artifacts/fma32/segments.txt) · [FP64 分段与级联](artifacts/fma64/segments.txt) · [FP32 APM 日志](artifacts/fma32/apm-messages.txt) · [FP64 APM 日志](artifacts/fma64/apm-messages.txt)

## 高扇出及控制副本

副本数按布线后网表中的**同名寄存器实例**统计。扇出取 Device Map 的 CE 和 Other 等原表，保留分栏口径。缺少同名寄存器的位，无法从网表名判断其具体被合并、改名还是优化。

| 项 | B · FP32 | C · FP64 |
|---|---:|---:|
| `advance_copy_r` 同名寄存器 / RTL 声明 | 106 / 126 | 570 / 743 |
| `add_select_r` 同名寄存器 / RTL 声明 | 21 / 22 | 39 / 47 |
| `mul_data_select_r` 同名寄存器 / RTL 声明 | — | 22 / 28 |
| 已报告的 `advance_copy_r[*]` 最大扇出 | 16 | 16 |
| CE 表中最大网络 `u_fma/N65` | 104 | 200 |
| CE 表 `unit_req_ready_w` | 103 | 199 |
| Other 表高扇出例 | `advance_w` 21，`add_select_r[5]` 48 | `mul_data_select_r[25]` 289，`add_select_r[15]` 43 |

两组已报告的流水使能叶均未超过 16，CE 表中仍有其他网络超过 16。逐位保留状态和已报告扇出、Top 50、所有 CE >16 的网名随附。 [FP32 高扇出](artifacts/fma32/high_fanout.txt) · [FP64 高扇出](artifacts/fma64/high_fanout.txt)

## 问题与偏离

- 初次 Compile 时 PDS 将 include 范围留空，两组报 `Verilog-4104`，找不到 `edrv32_build_mode.vh`。工程配置恢复了 `rtl/include`，并在两份工程目录放入该提交的同一头文件。最终成功的 `impl.tcl` 和 Compile 日志都记录了实际使用的 G 盘 include 路径。RTL 和 6.061 ns 约束保持原提交版本。初次失败及最终成功日志均附在各自 `raw/` 目录。
- B 使用独立副本 `cpu2_probe_fma_card111`，C 使用 `cpu2_probe_fma64_card111`。PDS 记录 `ConstraintEditor-4019`，涉及探针的 `observe_o`、`seed_i`、`clk_i`、`rst_n_i` 未绑定 I/O 位置。工程用于时序探针，流程结束在 Report Timing。

[FP32 全部报告及日志](artifacts/fma32) · [FP64 全部报告及日志](artifacts/fma64)
