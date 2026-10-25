# Cache 实施方案（P1）

| 项 | 内容 |
|---|---|
| 版本 | v0.1 |
| 日期 | 2026-10-25 |
| 对应规格 | `docs/spec/cache-spec.md` v0.1 |
| 对应验证方案 | `docs/testplan/cache-testplan.md` v0.1 |

状态标记：`[ ]` 未开始，`[~]` 进行中，`[x]` 完成，`[!]` 阻塞。

---

## 1. 目标和完成标准

- 实现 `edrv32_icache`、`edrv32_dcache`、`edrv32_cache_ctrl`。
- 验证方案的 smoke 和 full 档位全部通过，功能点全部覆盖。
- 与 CPU 集成（cpu-plan C-I3、C-R4），CoreMark CRC 正确。
- 4 个 RAM IP 的创建说明写好，用户在 PDS 中生成成功。

## 2. 前置条件

- P0：回归框架、风格检查、地址生成器（`edrv32_soc_map.vh`）。
- cpu-spec 3.2、3.3 节的 core↔cache 接口（已写定）。

## 3. 待办清单

cache 属于关键模块：RTL 由协调者逐行评审。

| 编号 | 内容 | 执行者 | 依赖 | 验收 | 分支 | 状态 |
|---|---|---|---|---|---|---|
| K-R1 | RAM 包装模块：`rtl/tech/edrv32_ram_icache_tag.v`、`edrv32_ram_icache_data.v`、`edrv32_ram_dcache_tag.v`、`edrv32_ram_dcache_data.v`（行为模型 + IP 例化分支，CLAUDE.md 第 8 节） | Codex · GPT-6.1 Sol | P0 | 行为模型单元测试通过；lint 0 告警 | 与 K-R2 同分支 | [~] dispatch ctx_4b3443f5e629 |
| K-R2 | I$ RTL、PMA 译码、LRU；单元测试 | Codex · GPT-6.1 Sol | K-R1 | 单元测试通过；lint 0 告警 | task-cache-rtl | [~] dispatch ctx_4b3443f5e629 |
| K-R3 | D$ RTL（写缓冲、写回、设备访问、维护操作）和 `edrv32_cache_ctrl`；单元测试 | Codex · GPT-6.1 Sol | K-R2 | 单元测试通过；lint 0 告警 | task-cache-rtl | [~] dispatch ctx_4b3443f5e629 |
| K-V1 | 模块级验证环境：core 侧驱动、AXI64 内存模型、架构内存参考模型、AXI 和 core 接口检查器、APB 驱动 | Codex · GPT-6.1 Sol（独立验证 worker） | P0 回归框架 | 用接口时序桩自测通过 | task-cache-verif | [~] dispatch ctx_2386d74f5e18 |
| K-V2 | 验证方案 3.1–3.4 的全部测试项和覆盖统计 | Codex · GPT-6.1 Sol（独立验证 worker） | K-V1 | 测试代码完成 | task-cache-verif | [~] dispatch ctx_2386d74f5e18 |
| K-I1 | 联调：smoke → full，覆盖收敛 | Codex · GPT-6.1 Sol | K-R3、K-V2 | full 全部通过，功能点全部覆盖 | task-cache-integ | [ ] |
| K-A1 | 协调者逐行评审 K-R2、K-R3 | 协调者 | K-R3 | 评审意见全部处理 | — | [ ] |
| K-P1 | 4 个 RAM IP 的创建说明 `fpga/ip/*.md`，以及乘法器 `ip_mul_s33x33` 的创建说明 | 协调者 | K-R1 | 用户在 PDS 中按说明一次生成成功 | — | [ ] |

可以并行的波次：
- 波次 1：K-R1 → K-R2 → K-R3（同一个 worker 顺序完成）；K-V1 → K-V2（独立验证 worker）
- 波次 2：K-I1、K-A1、K-P1

## 4. 规格定稿项

| cache-spec 待定项 | 定稿依据 | 对应待办 |
|---|---|---|
| 1 容量 | CoreMark 缺失率（HPM 事件 13、14）、DRM 占用 | cpu-plan C-I3、C-W2 |
| 2 tag RAM 实现 | CPU 顶层综合的资源和时序 | cpu-plan C-W2 |
| 3 IP 名称 | 用户在 PDS 中生成后确认 | K-P1 |

## 5. 风险和阻塞

| 风险 | 应对 |
|---|---|
| PDS 的简单双口 DRM 不支持 8 位字节写使能 | K-P1 时确认；不支持就把 D$ 数据 RAM 拆成按字节或按字的多块 |
| 维护期间"可缓存请求不接受、设备请求接受"使 ready 依赖地址，形成较长组合路径 | 综合时关注；必要时改为维护期间 core 侧只发设备访问的软件约定 |

## 6. 变更记录

| 日期 | 版本 | 变更 |
|---|---|---|
| 2026-10-25 | v0.1 | 初稿 |
