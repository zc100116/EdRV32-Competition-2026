# 存储子系统实施方案（P2）

| 项 | 内容 |
|---|---|
| 版本 | v0.1 |
| 日期 | 2026-10-26 |
| 对应规格 | `docs/spec/mem-subsys-spec.md` v0.1 |
| 对应验证方案 | `docs/testplan/mem-subsys-testplan.md` v0.1 |

状态标记：`[ ]` 未开始，`[~]` 进行中，`[x]` 完成，`[!]` 阻塞。

---

## 1. 目标和完成标准

- 实现规格中的全部模块和存储子系统顶层 `rtl/soc/edrv32_mem_subsys.v`，以及附录 A 的板级 DDR 适配器。
- 验证方案 smoke、full 全部通过，第 5 节覆盖全部命中。
- 存储子系统接入 SoC 顶层后，SC-06（DDR 窗口）和 CoreMark DDR 运行在真实存储路径上通过（随 SoC 顶层任务进行）。
- 上板：PERF_MON 读写校验通过，测得 B_eff（Windows 任务卡）。

## 2. 前置条件

- P0 基础设施、系统子系统（已在 main）。
- 存储子系统规格确认。

## 3. 待办清单

mem_xbar 是 CLAUDE.md 11.1 的关键模块：协调者逐行评审。

| 编号 | 内容 | 执行者 | 依赖 | 验收 | 分支 | 状态 |
|---|---|---|---|---|---|---|
| M-R1 | `edrv32_axi_async_bridge`（rtl/common，AXI64 五通道）+ DDR 网关；单元测试 | Codex · GPT-6.1 Sol | 规格确认 | 单元测试两种仿真器通过；lint、风格 0 告警 | task-mem-gw | [ ] |
| M-R2 | mem_xbar（含 MEM_XBAR 寄存器、W 缓冲、读返回缓冲）；单元测试 | Codex · GPT-6.1 Sol；协调者逐行评审 | 规格确认 | 同上 | task-mem-xbar | [ ] |
| M-R3 | PERF_MON + P6 仲裁；单元测试 | Codex · GPT-6.1 Sol | 规格确认 | 同上 | task-mem-pmon | [ ] |
| M-V1 | MB 环境与模型：AXI256 主设备驱动、AXI256 检查器、DDR 时序模型、参考存储、调度观察器；验证方案 3.1–3.4 全部测试项和覆盖统计 | Codex · GPT-6.1 Sol（独立验证 worker） | 规格确认 | 用桩从设备自测通过 | task-mem-verif | [ ] |
| M-R4 | 板级 DDR 适配器 `fpga/rtl/edrv32_fpga_ddr_adapter.v` + IP 端口行为模型 + AD-01 | Codex · GPT-6.1 Sol | DDR3 IP 端口模板（板卡厂商例程） | AD-01 通过 | task-mem-adapter | [ ] |
| M-T1 | 存储子系统顶层和文件列表 `rtl/filelists/mem_subsys.f`（协调者写文件列表） | Codex · GPT-6.1 Sol | M-R1–M-R3 | lint 0 告警 | task-mem-integ | [ ] |
| M-I1 | 联调：M-T1 + M-V1，smoke → full，覆盖收敛 | Codex · GPT-6.1 Sol | M-T1、M-V1 | full 全过，覆盖全部命中 | task-mem-integ | [ ] |
| M-A1 | 交叉评审 M-R1、M-R3（mem_xbar 由协调者评审） | Codex · GPT-6.1 Sol | M-R1、M-R3 | 意见全部处理 | — | [ ] |
| M-W1 | 上板：PERF_MON 读写校验、带宽与延迟、自动预充电对照（Windows 任务卡） | 用户 + Windows Codex | SoC 板级顶层 | 校验通过，B_eff 实测 | — | [ ] |

可以并行的波次：
- 波次 1：M-R1、M-R2、M-R3、M-V1、M-R4
- 波次 2：M-T1 → M-I1；M-A1
- 波次 3：M-W1（板级顶层完成后）

## 4. 规格定稿项

| 待定项 | 定稿依据 | 对应待办 |
|---|---|---|
| 1 网关延迟指标 | 系统级综合 | C-W2 之后 |
| 2 PERF_MON LUT 上限 | 综合 | M-I1 之后 |
| 3 适配器地址单位、控制器读写顺序 | DDR IP 文档 + 上板 | M-R4、M-W1 |
| 4 DDR 模型时序参数 | 上板实测 | M-W1 |

## 5. 风险和阻塞

| 风险 | 应对 |
|---|---|
| mem_xbar 调度逻辑（5 条规则 + 令牌桶 + 赤字轮询）在 125 MHz 下时序紧张 | 规格允许授权判定打一拍；综合后评估 |
| DDR3 IP 实际调度能力未知，B_eff 可能低于 2.6 GB/s | M-W1 尽早上板实测，必要时调整各场景流量预算 |
| 读返回缓冲 + W 缓冲占用 DRM | 与 NPU、cache、SRAM 的 DRM 预算一起核对 |

## 6. 变更记录

| 日期 | 版本 | 变更 |
|---|---|---|
| 2026-10-26 | v0.1 | 初稿 |
