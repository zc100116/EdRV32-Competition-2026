# 任务卡 20261031-20-b3f-baseline：B3F 全部优化后的基线（方案 A，不加区域约束）

## 1. 目标

在包含全部结构和时序优化的 `zc100116/b3` 上，B3F 不加区域约束跑一次完整实现，取得资源、时序、布线收敛和 DRM/APM 布局数据。这是两版 B3F 对比中的方案 A（设计记录 `docs/design/2026-10-31-drm-lutram.md`）；方案 B（浅存储改分布式 RAM）随后由卡 21 下发，在本卡结束后用复制的工程跑。

与卡 10 的 B3F 相比，RTL 包含：

| 修改 | 来源 |
|---|---|
| RND 组合路径与乘法位宽收窄（卡 14 B3R 布通，clk_mem +0.072 ns） | T-RND1/2 |
| PLIC 仲裁改为平衡树（卡 10 B3F clk_sys −1.785 ns 的路径） | T-PLIC1 |
| PIX 卷积核共享（`$mul` 132 → 18） | T-PIX1 |
| NPU 读请求地址提前寄存（卡 10 B3F clk_npu −0.770 ns 的路径） | T-NPU1 |
| NPU MAC 改为 APM SIMD 级联和链头修复（卡 15 B3N 上板 39/39） | T-NPU2/3 |

I$ 仍为 8 KiB（32 KiB 在卡 19 单独评估）。

## 2. 输入

- **代码分支**：`origin/zc100116/b3`（包含本卡的提交）。Windows Codex 从这里拉出 `win/20261031-20-b3f-baseline`，在 `result.md` 记录完整哈希。
- **约束和导入脚本**：`fpga/constraints/edrv32_fpga_board_b2_top.fdc`、`fpga/scripts/import_board_b2_top.tcl`，与卡 10 相同，**不接入** `edrv32_fpga_board_b2_top_regions.fdc`。
- **源文件**：按导入脚本应为 **161** 个（卡 10 为 162）。差异：
  - 删除 `rtl/tech/edrv32_mul_npu_int8_pair.v`、`rtl/media/rnd/edrv32_rnd_address.v`、`rtl/media/rnd/edrv32_rnd_source.v`；
  - 新增 `rtl/tech/edrv32_mac_npu_int8_head.v`、`rtl/tech/edrv32_mac_npu_int8_chain.v`。它们直接例化原语 `GTP_APM_E2`，不需要 IP。

## 3. 环境

- PDS 2022.2-SP6.1，PG2L200H-6 FBB676。
- 复用卡 10 的工程 `G:\codex_project\EdRV32-FPGA\EdRV32-B3F`。
- **单独运行**：卡 19（B3R）结束后再开始，期间不跑其他 PDS 工程。

## 4. 需要的 IP

- 从工程中移除 `ip_mul_npu_int8_pair`（已不再例化）。
- 其余 IP 与卡 10 相同，不用重新生成。

## 5. 操作步骤

| 步骤 | 执行者 | 内容 |
|---|---|---|
| 0 | Windows Codex（C） | `git fetch origin`，`git switch -c win/20261031-20-b3f-baseline origin/zc100116/b3`。把用户步骤整理成清单交给用户。 |
| 1 | 用户（U） | 在 B3F 工程的 Designs 中按第 2 节删除 3 个文件、添加 2 个文件，移除 IP `ip_mul_npu_int8_pair`。确认顶层为 `edrv32_fpga_board_b2_top`，没有游离的顶层模块。 |
| 2 | Windows Codex（C） | 把工程 Designs 中的源文件清单与导入脚本展开的清单逐项比对，确认为 161 个、无多无少；不一致就停下回报差异。 |
| 3 | 用户（U），或 Codex 在 PDS 控制台 | 依次执行 `synthesize -ads`、`dev_map`、`pnr`、`report_timing`、`gen_bit_stream`，记录各步耗时和峰值内存；布线时记下每一轮的未布通网络数和 overused 数。`pnr` 后执行 `generate_constraint -file {drm_placement.pcf} -device {DRM}` 和 `generate_constraint -file {apm_placement.pcf} -device {APM}`。报错就停下，回传原文和已取得的产物。布线超过 3 小时仍未收敛时，告诉用户，由用户决定是否继续。 |
| 4 | 用户（U） | 时序结果不论正负都生成 bitstream 并下载；复位后确认串口有启动信息，按住 KEY1 复位能进入 BIOS 菜单。 |
| 5 | Windows Codex（C） | 收集第 6 节产物，填写 `result.md`，提交信息 `win: 20261031-20-b3f-baseline results`，推送 `win/20261031-20-b3f-baseline`。 |

## 6. 产物

放在 `tasks/win/20261031-20-b3f-baseline/artifacts/`：

| # | 产物 | 内容 |
|---|---|---|
| 1 | `timing_summary.txt`、`setup_top200_<时钟>.txt`、`setup_top20_detail.txt`、`hold_top20.txt` | 每个时钟域的 WNS/TNS/WHS/THS；每个时钟域最差 200 条 setup 路径一行一条（起点、终点、裕量、逻辑级数）；最差 20 条 setup 逐级明细；最差 20 条 hold |
| 2 | `resource_summary.txt`、`resource_hier.txt` | 资源汇总（LUT、FF、DRM、APM、分布式 RAM、IO、PLL）；按层次展开到 `u_soc` 下一级子系统，以及 `u_mem/u_xbar`、`u_npu` 下一级 |
| 3 | `drm_by_instance.tsv` | 每个 DRM 实例一行：层次名、DRM18K/36K 类型、个数。从 device_map 或资源报告中取 |
| 4 | `flow_summary.txt`、`route_progress.tsv` | 各步耗时、峰值内存；布线每一轮的未布通网络数和 overused 数 |
| 5 | `drm_placement.pcf`、`apm_placement.pcf` | 布局导出 |
| 6 | `uart/boot.log` | 启动信息和 BIOS 菜单 |

## 7. 通过判据

- 完成布线和 bitstream，时序如实记录，不作为停止条件。
- 能进入 BIOS 菜单。
- 所有数字来自 PDS 报告和串口原文，找不到的写"未取得"。

## 8. result.md 模板

```markdown
# 20261031-20-b3f-baseline 结果

| 项 | 内容 |
|---|---|
| 代码 commit | |
| 源文件数（与导入脚本比对） | |
| 各步耗时 / 峰值内存 | |
| 布线轮数、最后一轮未布通 / overused | |
| 完成情况 | |

## 资源（对照卡 10 B3F）
| 项 | 卡 10 | 本卡 |
|---|---|---|
| LUT | 99201 (63%) | |
| FF | 94809 (30%) | |
| DRM | 325 (79%) | |
| APM | 569 (77%) | |
| 分布式 RAM | 794 (3%) | |

## 时序（布线后，slow 角）
| 时钟 | WNS | TNS | WHS | THS | setup 违例端点 |
|---|---|---|---|---|---|

每个违例时钟域最差路径前 10 条（起点 → 终点，裕量，级数）：

## 上板（BIOS 菜单）

## 完整报告在 Windows 本地的路径

## 备注
```
