# 系统子系统实施方案（P2）

| 项 | 内容 |
|---|---|
| 版本 | v0.1 |
| 日期 | 2026-10-25 |
| 对应规格 | `docs/spec/sys-subsys-spec.md` v0.1 |
| 对应验证方案 | `docs/testplan/sys-subsys-testplan.md` v0.1 |

状态标记：`[ ]` 未开始，`[~]` 进行中，`[x]` 完成，`[!]` 阻塞。

---

## 1. 目标和完成标准

- 实现系统子系统规格中的全部模块，以及系统子系统顶层 `rtl/soc/edrv32_sys_subsys.v`（连线顶层，供 SoC 顶层例化）。
- 验证方案 smoke、full 全部通过，第 5 节功能点全部覆盖。
- SC 环境中 CPU 从 ROM 启动、跑通中断和 CoreMark（SC-01–SC-07）。
- ROM、SRAM 的 IP 创建说明写好，用户在 PDS 中生成成功。

## 2. 前置条件

- P0 基础设施（已在 main）。
- 系统子系统规格确认。
- SC 环境依赖 CPU 联调（cpu-plan C-I2）合入 main，以及 `edrv32_cpu_subsys`（cpu-plan C-R4）。

## 3. 待办清单

sys_xbar 和外设不属于 CLAUDE.md 11.1 的关键模块：RTL 由另一个 Codex worker 交叉评审，协调者抽查。

| 编号 | 内容 | 执行者 | 依赖 | 验收 | 分支 | 状态 |
|---|---|---|---|---|---|---|
| S-R1 | 总线：`edrv32_bus_sys_xbar`、`edrv32_bus_rom`、`edrv32_bus_sram`、`edrv32_bus_apb_bridge`、`edrv32_apb_async_bridge`（`rtl/common/`）、存储包装 `edrv32_rom_boot`、`edrv32_ram_sram`；单元测试 | Codex · GPT-6.1 Sol | 规格确认 | 单元测试通过；lint、风格 0 告警 | zc100116/task-sys-bus | [x] 14a487c（分支保留待集成），6 组单元测试两种仿真器通过 |
| S-R2 | 中断与系统控制：`edrv32_periph_clint`、`edrv32_periph_plic`、`edrv32_periph_sysctrl`、`edrv32_soc_reset_ctrl`；生成器增加 `EDRV32_CLK_SYS_HZ` 常量；单元测试 | Codex · GPT-6.1 Sol | 规格确认 | 同上 | zc100116/task-sys-ctrl | [x] ce8aac5 + ec4b8c9（regress Icarus 参数修复）（分支保留待集成），CL/PL/SY 全部单元测试两种仿真器通过 |
| S-R3 | 外设：`edrv32_periph_uart`、`edrv32_periph_gpio`、`edrv32_periph_i2c`；单元测试 | Codex · GPT-6.1 Sol | 规格确认 | 同上 | zc100116/task-sys-periph | [x] 9dd243a（分支保留待集成），15 项单元测试两种仿真器通过；CLK_SYS_HZ 暂用本地常量，联调时改引用生成常量 |
| S-V1 | SB 环境和模型：AXI64 主设备驱动、参考存储模型、APB 检查器和从设备模型、UART 模型、SCCB 从设备模型（`verif/models/`）；验证方案 3.1–3.5 的全部测试项和覆盖统计 | Codex · GPT-6.1 Sol（独立验证 worker） | 规格确认 | 用桩从设备自测通过 | zc100116/task-sys-verif | [~] dispatch ctx_65c83e492e13 |
| S-W1 | 软件：bootloader（logo、跳转 SRAM、UART 下载）、驱动（UART、GPIO、I2C、CLINT、PLIC）、SC-01–SC-06 的测试程序；ROM 链接与 `rom.hex` 生成 | Codex · GPT-6.1 Sol | 规格确认 | 在 Spike 上能编译运行到 tohost（依赖外设的部分只编译） | zc100116/task-sys-sw | [x] bf5046f（分支保留待集成），bootloader 624 B，三个程序在 Spike 上通过；外设相关程序待 SC 环境 |
| S-T1 | 系统子系统顶层 `rtl/soc/edrv32_sys_subsys.v` 和文件列表 | Codex · GPT-6.1 Sol | S-R1–S-R3 | lint 0 告警 | zc100116/task-sys-integ | [x] 95f5278，13 个单元目录两种仿真器 26/0；评审意见修改 S-T1b dispatch ctx_890232ce9f24 |
| S-I1 | 联调：S-T1 + S-V1，smoke → full，覆盖收敛 | Codex · GPT-6.1 Sol | S-T1、S-V1 | full 全部通过，覆盖全部命中 | task-sys-integ | [ ] |
| S-I2 | SC 环境：`edrv32_cpu_subsys` + 系统子系统，跑 SC-01–SC-07 | Codex · GPT-6.1 Sol | S-I1、S-W1、cpu-plan C-I2 | SC 测试通过，CoreMark CRC 正确 | task-sys-cpu | [ ] |
| S-A1 | 交叉评审 S-R1–S-R3 | Codex · GPT-6.1 Sol；协调者抽查 | S-R1–S-R3 | 意见全部处理 | — | [x] 15 个文件评审完：2 个缺陷（CLINT/PLIC 多余的未对齐检查）、1 项异步桥复位边界，已交 S-T1 修改；其余无意见 |
| S-P1 | ROM、SRAM 的 IP 创建说明 `fpga/ip/*.md` | 协调者 | S-R1 | 用户在 PDS 中一次生成成功 | — | [~] 创建说明 04ac257 已写，待用户在 PDS 生成并回传实际端口 |

可以并行的波次：
- 波次 1：S-R1、S-R2、S-R3、S-V1、S-W1
- 波次 2：S-T1 → S-I1；S-A1；S-P1
- 波次 3：S-I2（CPU 联调合入后）

## 4. 规格定稿项

| 待定项 | 定稿依据 | 对应待办 |
|---|---|---|
| 1 CHIP_ID | 用户确认 | — |
| 2 clk_sys 频率 | cpu-plan C-W2 | — |
| 3 ROM、SRAM 的 IP 名称 | 用户在 PDS 中生成后确认 | S-P1 |
| 4 软复位脉宽 | 板级验证 | 板级阶段 |

## 5. 风险和阻塞

| 风险 | 应对 |
|---|---|
| sys_xbar 的组合路径（译码 + 仲裁 + 握手）影响 clk_sys 时序 | 规格允许地址和返回各一级寄存器；C-W2 之后的系统级综合关注 |
| 256 KiB SRAM 占用 DRM 较多 | 与 cache、NPU 的 DRM 预算一起在 SoC 级资源评估中核对 |

## 6. 变更记录

| 日期 | 版本 | 变更 |
|---|---|---|
| 2026-10-25 | v0.1 | 初稿 |
