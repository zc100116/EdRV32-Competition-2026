# EdRV32 开发路线图

| 项 | 内容 |
|---|---|
| 更新日期 | 2026-10-27 |
| 维护者 | 协调者（每次派发、完成、合并、Windows 结果回传后更新） |

状态标记：`[ ]` 未开始，`[~]` 进行中，`[x]` 完成，`[!]` 阻塞。

---

## 1. 当前状态

| 项 | 内容 |
|---|---|
| 当前阶段 | P1 CPU 和 cache（orca Run `run_6e42f8ce0f9c`）；P0、cache、CPU（d411035）已合入 main |
| 正在进行 | NPU 规格 v0.2、验证方案 v0.2 已确认；N-Q1/N-D0/N-C0/N-IP1/N-M1/N-M2/N-M3/N-V1/N-D1 已完成并合入 main；Windows 任务 20261027-02 已下发：CPU 第二轮综合（原 20261027-01，含 SRAM IP 重新生成）与 NPU 数据通路单独 PDS（N-W1，含 9 个 NPU IP 生成和 ModelSim 等价性检查）合并执行 |
| 等待用户 | Windows 任务 20261027-02-cpu-npu-synth 执行，结果分支 `win/20261027-02-cpu-npu-synth` |
| 阻塞 | 无 |

---

## 2. 规格与方案

| 模块 | 规格 | 验证方案 | 实施方案 | 状态 |
|---|---|---|---|---|
| SoC 总体 | `spec/edrv32-soc-spec.md` v0.7 | — | 本文件 | [x] 草案完成 |
| 基础设施 | — | — | `plan/infra-plan.md` | [x] 草案完成 |
| CPU | `spec/cpu-spec.md` v0.11 | `testplan/cpu-testplan.md` v0.1 | `plan/cpu-plan.md` | [x] 草案完成 |
| Cache | `spec/cache-spec.md` v0.5 | `testplan/cache-testplan.md` v0.1 | `plan/cache-plan.md` | [x] 已确认 |
| 系统子系统（sys_xbar、ROM/SRAM、APB 桥、CLINT、PLIC、UART、GPIO、I2C、SYSCTRL、复位） | `spec/sys-subsys-spec.md` v0.3 | `testplan/sys-subsys-testplan.md` v0.2 | `plan/sys-subsys-plan.md` | [x] 已确认 |
| 存储子系统（DDR 网关、mem_xbar、PERF_MON、板级 DDR 适配器） | `spec/mem-subsys-spec.md` v0.2 | `testplan/mem-subsys-testplan.md` v0.2 | `plan/mem-subsys-plan.md` | [x] 已确认 |
| 公共单元（CDC、FIFO、dma2d） | — | — | — | [ ] |
| VIN / PIX / DISP | — | — | — | [ ] |
| RND | — | — | — | [ ] |
| GEO | — | — | — | [ ] |
| NPU | `spec/npu-spec.md` v0.2 | `testplan/npu-testplan.md` v0.2 | `plan/npu-plan.md` | [~] 数据通路 RTL 完成，待 PDS 测量（N-W1）和控制器（N-C1） |
| ETH | — | — | — | [ ] |
| 板级（fpga/rtl、约束、导入脚本） | — | — | — | [ ] |

---

## 3. 开发阶段

| 阶段 | 内容 | 实施方案 | 退出条件 | 状态 |
|---|---|---|---|---|
| P0 | 基础设施：legacy 迁移、目录骨架、工具链、回归框架、生成器、公共原语、软件 BSP | `plan/infra-plan.md` | 见 infra-plan 第 1 节 | [x] |
| P1 | CPU（含 cache） | `plan/cpu-plan.md`、cache-plan | ISA/ACT 全部通过，CoreMark CRC 正确，上板测得 Fmax、LUT、CoreMark/MHz | [~] |
| P2 | SoC 骨架：系统总线、外设、中断、存储子系统、板级顶层 | `plan/sys-subsys-plan.md`、`plan/mem-subsys-plan.md` | SoC 级 CoreMark 和 DDR 测试通过，上板运行 | [~] 系统子系统与 SC 联调已合入 main；存储子系统已合入 main（58de802，全局 full 待补跑） |
| P3 | 实时视频通路：dma2d、VIN、DISP | 待写 | 摄像头到 HDMI 闭环，无 underflow/overflow | [ ] |
| P4 | 图像处理：PIX、GEO | 待写 | 像素级比对通过 | [ ] |
| P5 | 渲染：RND、LVGL 移植 | 待写 | UI 画面比对通过 | [ ] |
| P6 | NPU | 待写 | 逐层与参考模型逐位一致，帧率达标 | [ ] |
| P7 | ETH、三场景演示、系统集成与性能报告 | 待写 | SoC 规格第 9 节的指标全部达标 | [ ] |

---

## 4. Windows 任务

| 任务号 | 内容 | 所属 | 状态 |
|---|---|---|---|
| 20261025-01-cpu-sys-synth | 生成 7 个 IP；CPU + 系统子系统测量顶层综合与布局布线（Fmax、资源、RVC_EN 0/1 对照） | cpu-plan C-W2、sys-subsys-plan S-P1 | [x] 69.6 MHz，WNS −7.708 ns；报告 `reports/2026-10-26-timing-cpu-sys.md` |
| 20261027-01-cpu-sys-synth-r2 | 重新生成 SRAM IP（8192×64）；C-R5/C-R6 后第二轮综合与布局布线 | cpu-plan C-W3 | 并入 20261027-02，不单独执行 |
| 20261027-02-cpu-npu-synth | A：CPU 第二轮综合（同 20261027-01）；B：NPU 9 个 IP 生成、10 个包装 ModelSim 检查、数据通路单独综合与布局布线 | cpu-plan C-W3、npu-plan N-W1 | [~] 已下发 |

---

## 5. 里程碑

| tag | 内容 | 状态 |
|---|---|---|
| m1-cpu-isa-pass | CPU 通过全部 ISA/ACT 测试 | [ ] |
| m2-coremark-board | CoreMark 上板运行 | [ ] |
