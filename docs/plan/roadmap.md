# EdRV32 开发路线图

| 项 | 内容 |
|---|---|
| 更新日期 | 2026-10-25 |
| 维护者 | 协调者（每次派发、完成、合并、Windows 结果回传后更新） |

状态标记：`[ ]` 未开始，`[~]` 进行中，`[x]` 完成，`[!]` 阻塞。

---

## 1. 当前状态

| 项 | 内容 |
|---|---|
| 当前阶段 | P1 CPU 和 cache（orca Run `run_6e42f8ce0f9c`）；P0、cache、CPU（d411035）已合入 main |
| 正在进行 | C-E4 CPU 微结构优化评估（`ctx_3d19c7fb2fbb`）；S-I1 系统子系统联调（`ctx_0bf2700f11d5`） |
| 等待用户 | 无 |
| 阻塞 | 无 |

---

## 2. 规格与方案

| 模块 | 规格 | 验证方案 | 实施方案 | 状态 |
|---|---|---|---|---|
| SoC 总体 | `spec/edrv32-soc-spec.md` v0.4 | — | 本文件 | [x] 草案完成 |
| 基础设施 | — | — | `plan/infra-plan.md` | [x] 草案完成 |
| CPU | `spec/cpu-spec.md` v0.9 | `testplan/cpu-testplan.md` v0.1 | `plan/cpu-plan.md` | [x] 草案完成 |
| Cache | `spec/cache-spec.md` v0.4 | `testplan/cache-testplan.md` v0.1 | `plan/cache-plan.md` | [x] 已确认 |
| 系统子系统（sys_xbar、ROM/SRAM、APB 桥、CLINT、PLIC、UART、GPIO、I2C、SYSCTRL、复位） | `spec/sys-subsys-spec.md` v0.2 | `testplan/sys-subsys-testplan.md` v0.1 | `plan/sys-subsys-plan.md` | [x] 已确认 |
| 存储子系统（DDR 网关、mem_xbar、PERF_MON） | — | — | — | [ ] |
| 公共单元（CDC、FIFO、dma2d） | — | — | — | [ ] |
| VIN / PIX / DISP | — | — | — | [ ] |
| RND | — | — | — | [ ] |
| GEO | — | — | — | [ ] |
| NPU | — | — | — | [ ] |
| ETH | — | — | — | [ ] |
| 板级（fpga/rtl、约束、导入脚本） | — | — | — | [ ] |

---

## 3. 开发阶段

| 阶段 | 内容 | 实施方案 | 退出条件 | 状态 |
|---|---|---|---|---|
| P0 | 基础设施：legacy 迁移、目录骨架、工具链、回归框架、生成器、公共原语、软件 BSP | `plan/infra-plan.md` | 见 infra-plan 第 1 节 | [x] |
| P1 | CPU（含 cache） | `plan/cpu-plan.md`、cache-plan | ISA/ACT 全部通过，CoreMark CRC 正确，上板测得 Fmax、LUT、CoreMark/MHz | [~] |
| P2 | SoC 骨架：系统总线、外设、中断、存储子系统、板级顶层 | `plan/sys-subsys-plan.md`、存储子系统待写 | SoC 级 CoreMark 和 DDR 测试通过，上板运行 | [ ] |
| P3 | 实时视频通路：dma2d、VIN、DISP | 待写 | 摄像头到 HDMI 闭环，无 underflow/overflow | [ ] |
| P4 | 图像处理：PIX、GEO | 待写 | 像素级比对通过 | [ ] |
| P5 | 渲染：RND、LVGL 移植 | 待写 | UI 画面比对通过 | [ ] |
| P6 | NPU | 待写 | 逐层与参考模型逐位一致，帧率达标 | [ ] |
| P7 | ETH、三场景演示、系统集成与性能报告 | 待写 | SoC 规格第 9 节的指标全部达标 | [ ] |

---

## 4. Windows 任务

| 任务号 | 内容 | 所属 | 状态 |
|---|---|---|---|
| — | CPU 顶层综合（cpu-plan C-W2），CPU 和 cache 完成后下发 | cpu-plan C-W2 | [ ] |

---

## 5. 里程碑

| tag | 内容 | 状态 |
|---|---|---|
| m1-cpu-isa-pass | CPU 通过全部 ISA/ACT 测试 | [ ] |
| m2-coremark-board | CoreMark 上板运行 | [ ] |
