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
| 正在进行 | CPU：探针 PDS 完成（C-W6）：去 C 扩展 129.1 MHz、净性能最好，B 类（切流水）净收益 ≤ 1.5% 不采用，全部切断也只到 138.9 MHz，150 MHz 达不到，频率目标待用户决定（设计记录 `2026-10-28-cpu-timing-closure.md` 5.1）；NPU：完整 NPU PDS 通过 150 MHz（+0.214 ns），规格 v0.4 已确认，N-V2 完成；图像通路与 ETH：VIN/DISP/PIX/GEO/ETH 模块级全部通过；合并 PDS（V-W2）：GEO 3238、ETH 3863 LUT 在预算内，VIN+PIX+DISP 10523 超 10K 5.2%，clk_mem 只有 63.8 MHz，违例全在 PIX 组合 3×3 核，V-R6 流水化已完成（待 PDS 复测）；PDS 布局优化能力调研进行中（`guides/pds-floorplan.md`）；上板计划 `plan/board-plan.md`：B1 准备完成，Windows 卡 20261028-06-board-b1；媒体复测卡 20261028-05-media-r2 已下发 |
| 等待用户 | 无 |
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
| 公共单元（CDC、FIFO、dma2d） | `spec/dma2d-spec.md` v0.1（草案） | — | — | [~] dma2d 规格起草中 |
| VIN / PIX / DISP | `spec/vin-spec.md` v0.1、`spec/pix-spec.md` v0.1、`spec/disp-spec.md` v0.2 | `testplan/vin-testplan.md`、`pix-testplan.md`、`disp-testplan.md` | `plan/vision-plan.md` | [~] VIN/DISP/PIX 模块级验证通过，待 PDS 资源测量和 SoC 级集成 |
| RND | — | — | — | [ ] |
| GEO | `spec/geo-spec.md` v0.1 | `testplan/geo-testplan.md` v0.1 | `plan/vision-plan.md` | [~] 模块级验证通过，待 PDS 资源测量 |
| NPU | `spec/npu-spec.md` v0.4 | `testplan/npu-testplan.md` v0.4 | `plan/npu-plan.md` | [~] 完整 NPU PDS 通过 150 MHz；待整网性能（N-P1） |
| ETH | `spec/eth-spec.md` v0.1 | `testplan/eth-testplan.md` v0.1 | `plan/vision-plan.md`（V-R5、V-P5、V-T5、V-I4） | [~] 模块级验证通过，待 PDS 资源测量 |
| 板级（fpga/rtl、约束、导入脚本）与上板实测 | — | — | `plan/board-plan.md`（B1 CPU 最小系统 100 MHz、B2 + 图像通路与 DDR、B3 + NPU 与 ETH 跑 YOLO） | [~] v0.1 草案待确认 |

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
| 20261027-02-cpu-npu-synth | A：CPU 第二轮综合（同 20261027-01）；B：NPU 9 个 IP 生成、10 个包装 ModelSim 检查、数据通路单独综合与布局布线 | cpu-plan C-W3、npu-plan N-W1 | [x] CPU 94.46 MHz；NPU 158.08 MHz |

---

## 5. 里程碑

| tag | 内容 | 状态 |
|---|---|---|
| m1-cpu-isa-pass | CPU 通过全部 ISA/ACT 测试 | [ ] |
| m2-coremark-board | CoreMark 上板运行 | [ ] |
