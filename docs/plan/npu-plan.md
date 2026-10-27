# NPU 实施方案

| 项 | 内容 |
|---|---|
| 版本 | v0.6 |
| 日期 | 2026-10-27 |
| 对应规格 | `docs/spec/npu-spec.md` v0.1（已确认） |

状态标记：`[ ]` 未开始，`[~]` 进行中，`[x]` 完成，`[!]` 阻塞。

---

## 1. 目标和完成标准

评估阶段（N-E1、N-E2，已完成）：量化旧工程 YOLOv8n 加速器（`legacy/rtl/vision/yolo/`）的性能和 512 MAC 下数据通路与调度改进的收益，作为 NPU 规格讨论的依据。

开发阶段：实现 `edrv32_npu`（规格 v0.1），完成标准：
- 验证方案 `docs/testplan/npu-testplan.md` 的 smoke、full 全部通过，perf（NET-02）结果写成测量报告；
- 数据通路单独 PDS 一次、NPU 整体 PDS 一次，时序和资源写成测量报告，据此定稿规格第 9 节的 [待定] 项；
- SoC 集成（`clk_npu_i`、reset_ctrl 的 clk_npu 域、P3 和媒体 APB 槽 6 连线）不在本方案，随 SoC 集成阶段进行。

已确认的方向（2026-10-26，规格起草时写入）：以旧工程卷积数据通路和量化/激活单元为基础移植，重写调度与 DMA，数据通路可按分析结果修改；MAC 先做 512，跑通后再看是否需要 1024；NPU 用独立时钟 clk_npu，开发初值 150 MHz。

## 2. 前置条件

- `rtl/common/` 现有 CDC 原语；AXI256 异步桥需新增（N-C0）。
- 整网用例需要真实量化权重，来源见验证方案待定事项 1（N-Q1）。
- 新 IP（APM 乘法器、行缓存/常驻权重/量化参数/结果缓冲 RAM）的规格由 N-D0 确定，协调者写创建说明和包装模块后，由用户在 Windows 生成。

## 3. 待办清单

| 编号 | 内容 | 执行者 | 依赖 | 验收 | 分支 | 状态 |
|---|---|---|---|---|---|---|
| N-E1 | 旧加速器性能评估：静态逐层分析、旧 RTL 逐命令实测、周期模型校准、W1–W8 改进项评估 | Codex · GPT-6.1 Sol | — | 测量报告 `docs/reports/2026-10-26-perf-npu-legacy.md` | task-npu-legacy-eval | [x] 已合入 f36219c |
| N-E2 | 512 MAC 数据通路与调度改进评估：D2 半块模式、D3a/D3b patch 填充、W 组合、带宽敏感性、DRM 估算 | Codex · GPT-6.1 Sol | N-E1 | 测量报告 `docs/reports/2026-10-26-perf-npu-datapath.md` | task-npu-datapath-eval | [x] 2026-10-27 合入 main |
| N-S1 | NPU 规格 v0.1：设计记录 `docs/design/2026-10-26-npu-architecture.md` | 协调者 + 用户确认 | N-E2 | 用户确认 | — | [x] 2026-10-27 确认 |
| N-S2 | SoC 规格同步修改：clk_npu、跨时钟域清单、INT8_C4 格式、8.5 输入适配 C4、8.9 引用 NPU 规格 | 协调者 + 用户确认 | N-S1 | 用户确认 | — | [x] SoC 规格 v0.7，用户确认 2026-10-27。RTL 影响：SoC 顶层增加 `clk_npu_i`，reset_ctrl 增加 clk_npu 域复位，在 NPU 集成时一并实现 |
| N-T1 | NPU 验证方案 `docs/testplan/npu-testplan.md`、本实施方案的开发任务拆分 | 协调者 | N-S1 | 文档完成 | — | [x] 2026-10-27 草案（testplan v0.1） |
| N-Q1 | Python 环境：Linux 用户目录虚拟环境（numpy、torch CPU），`tools/requirements.txt` 和 `docs/guides/env-setup.md` 补充；初始化 ultralytics 子模块，取得 YOLOv8n 预训练权重和 COCO128 | 协调者 | 用户确认来源 | 旧工程 `yolo_v8n_checkpoint_audit.py` 在 Linux 跑通 | — | [x] 2026-10-27：`~/.local/opt/edrv32-py`（torch 2.14.1 CPU、numpy 2.5.2），`tools/requirements.txt`、env-setup 第 6 节。旧脚本在 Linux 全部跑通：标定导出 1 分 24 秒，32 图评估浮点 mAP50 0.642（与旧工程相同）、INT8 0.611（旧工程记录 0.623，差异在 N-M1 中查明） |
| N-D0 | 数据通路微架构设计记录：流水级表、行缓存/常驻权重/量化参数/结果缓冲的 RAM 组织（深度、位宽、个数、读延迟）、APM 用法、权重镜像格式（规格 4.2 [待定]）、发射信用的计算；评估旧数据通路各模块的可移植部分 | Codex · GPT-6.1 Sol | N-T1 | 设计记录 `docs/design/2026-10-2x-npu-datapath.md`，协调者评审、用户确认权重格式 | task-npu-dp-arch | [ ] |
| N-IP1 | NPU 用 IP 的创建说明和包装模块（`fpga/ip/`、`rtl/tech/`），Windows 任务卡生成 IP | 协调者 + 用户 | N-D0 | 包装模块 lint 0 告警；任务卡结果 | — | [ ] |
| N-M1 | 离线编译工具 `tools/npu/`：移植旧工程量化流程，生成模型镜像（按 N-D0 的权重格式）、描述符表（规格 4.1）、量化记录（4.2）、INT8_C4 输入；随机小用例生成器 `gen_case.py`；TL-03 | Codex · GPT-6.1 Sol | N-D0、N-Q1 | TL-03 通过；整网镜像生成命令写进 README | task-npu-compiler | [ ] |
| N-M2 | 参考模型 `tools/npu/ref/`：按规格解释描述符和存储镜像；TL-01、TL-02、TL-04 | Codex · GPT-6.1 Sol（与 N-M1 不同 worker） | N-D0（权重格式）、N-Q1 | TL-01/02 smoke 通过，TL-04 逐层一致 | task-npu-ref | [ ] |
| N-C0 | `rtl/common/edrv32_axi256_async_bridge.v` 及单元测试 | Codex · GPT-6.1 Sol | — | 单元测试 smoke/full 通过，lint 0 告警 | task-npu-axi256-bridge | [ ] |
| N-D1 | 数据通路 RTL：行缓存、窗口生成、MAC 阵列、累加、量化、激活表、残差加、写回打包、数据通路子顶层；各单元测试和 `verif/unit/npu_datapath/`（向量来自 N-M2 的参考模型） | Codex 项目经理 + 员工（GPT-6.1 Sol） | N-D0、N-IP1（包装模块）、N-M2 | 单元测试全过，lint 0 告警；协调者评审关键部分 | task-npu-datapath | [ ] |
| N-W1 | 数据通路单独 PDS（规格 5.4 第 4 条）：板级测量顶层 `fpga/rtl/edrv32_fpga_npu_dp_top.v`、约束、导入脚本、Windows 任务卡 | 协调者 + 用户 | N-D1、N-IP1 生成 | 时序和资源测量报告；不达标时回到 N-D1 修改 | win 任务卡 | [ ] |
| N-C1 | 控制和 DMA RTL：寄存器块、描述符读取与译码、调度器（W1/W2/W3/W4b、发射信用）、读写 DMA、POOL、UPSAMPLE、错误和 ABORT、`edrv32_npu` 顶层和两个异步桥；单元测试 | Codex · GPT-6.1 Sol | N-D1、N-C0 | 单元测试全过，lint 0 告警；协调者逐行评审调度器 | task-npu-ctrl | [ ] |
| N-V1 | NB 模块级环境和测试：存储模型 `npu_axi256_mem.sv`、APB 驱动、镜像装载与比对、验证方案 3.2–3.7 全部测试项（不读被测 RTL） | Codex · GPT-6.1 Sol（独立验证 worker） | N-M1、N-M2；与 N-D1/N-C1 并行 | 用参考模型自身产生的输出做回环自检；测试代码评审 | task-npu-verif | [ ] |
| N-I1 | 联调：NB smoke → full，覆盖收敛 | Codex · GPT-6.1 Sol | N-C1、N-V1 | smoke、full 全过，第 5 节覆盖全部命中 | task-npu-integ | [ ] |
| N-P1 | 整网性能 NET-02 和测量报告；NPU 整体 PDS（Windows 任务卡）；规格第 9 节 [待定] 项定稿 | Codex · GPT-6.1 Sol + 协调者 + 用户 | N-I1 | 测量报告 `docs/reports/…-perf-npu.md`、`…-timing-npu.md`；规格修订经用户确认 | task-npu-perf | [ ] |

依赖关系：N-Q1、N-D0、N-C0 可以立即并行开始；N-M1、N-M2、N-IP1 在 N-D0 之后并行；N-D1 和 N-V1 并行；N-W1 的结果可能让 N-D1 返工，N-C1 在 N-W1 结论之后再接数据通路。

## 4. 规格定稿项

npu-spec 第 9 节的 [待定] 项：权重镜像格式、存储容量在 N-D0 后提出、N-D1 完成时定；流水级和 clk_npu 频率在 N-W1 后定；描述符位域在 N-C1 完成时定；帧率、APM、DRM 指标和 PERF 定义在 N-P1 后定。

## 5. 风险和阻塞

| 风险 | 应对 |
|---|---|
| 整网 RTL 仿真耗时过长（估算约 660 万 clk_npu 周期） | smoke 只跑代表层（NET-03）；整网只在 full/perf；仍不可接受时改为代表层实测 + 模型外推 |
| torch 等第三方依赖在 Linux 用户目录安装失败 | 改由 Windows 端生成模型镜像后回传（N-Q1 的备选） |
| 数据通路单独 PDS 达不到 150 MHz | 按 N-W1 关键路径调整流水级；clk_npu 频率按实测定稿 |
| 288 KiB 常驻权重以 2048 位宽读出，DRM 拼接和布线压力大 | N-D0 给出 RAM 组织和 DRM 数；N-W1 实测 |

## 6. 变更记录

| 日期 | 版本 | 变更 |
|---|---|---|
| 2026-10-26 | v0.1 | 初稿：N-E1 |
| 2026-10-26 | v0.2 | 记录已确认方向；新增 N-E2 |
| 2026-10-27 | v0.3 | N-E2 完成；NPU 规格 v0.1 确认；新增 N-S2、N-T1 |
| 2026-10-27 | v0.4 | N-S2 完成（SoC 规格 v0.7） |
| 2026-10-27 | v0.5 | N-T1：验证方案 v0.1 草案；开发阶段目标和待办 N-Q1、N-D0、N-IP1、N-M1、N-M2、N-C0、N-D1、N-W1、N-C1、N-V1、N-I1、N-P1 |
| 2026-10-27 | v0.6 | N-Q1 完成；N-D0、N-C0 派发 |
