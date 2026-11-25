# GPU 项目实施方案

| 项 | 内容 |
|---|---|
| 版本 | v0.1 |
| 日期 | 2026-11-23 |
| 分支 | `zc100116/gpu`（协调者工作树 `EdRV32-Competition-2026/gpu`）；worker 分支由 Orca 从它拉出 |
| 规格 | `gpu-spec.md` v0.1、`gpu-soc-spec.md` v0.1、`aud-spec.md` v0.1 |
| 验证方案 | `gpu-testplan.md`、`aud-testplan.md`、`gpu-soc-testplan.md`（均为 v0.1） |

## 1. 目标和完成标准

- **仿真**：GPU、AUD 的模块级 smoke 和 full 全部通过；GPU SoC 的 smoke 和 full 全部通过；GPU perf 档记录到测量报告。
- **上板**：Windows 端完成综合和布局布线，时序收敛；三部分演示在板上运行，放音正常。
- **规格定稿**：`gpu-spec.md` 第 9 节、`gpu-soc-spec.md` 第 10 节、`aud-spec.md` 第 9 节的待定项全部按数据定稿。

## 2. 前置条件

- 视觉项目的 RTL、验证环境和工具链（`zc100116/b3` 3f111eb83 的内容）都已在本分支中。
- 本项目的文件列表、地址表、顶层都新建，不修改视觉项目的对应文件（`gpu-soc-spec.md` 开头说明）。

## 3. 待办清单

执行者：Codex 暂用 `gpt-6.1-sol`、effort medium（用户 2026-11-23：本机 Codex CLI 不支持 gpt-6.2-sol，用户更新后通知再换），不派 Claude worker。

工作树：G2 起不冲突的任务共用 `gpu-dev`（分支 `zc100116/gpu-dev`，用户 2026-11-23 同意），各自只提交自己的文件；协调者按批合入 `zc100116/gpu`。仿真全部在仿真主机上跑（只限 Codex）。

| 编号 | 内容 | 执行者 | 依赖 | 验收 | 状态 |
|---|---|---|---|---|---|
| C-1 | 寄存器和命令格式 `rtl/include/regs/gpu.json`、`aud.json`（沿用 `tools/gen/regs.py` 生成头文件）；gpu-spec 2.11 编码表。地址表 `gpu_soc_address_map.json` 放到 T-1 | 协调者 | — | 生成器运行通过；字段与 gpu-spec 2.3–2.11、aud-spec 4 逐项一致 | [x] |
| M-1 | Python 逐位参考模型 `tools/gpu/model/` 和场景生成器 `tools/gpu/scene/`；数值研究：对 G-N1–G-N3 给出定点格式和近似方法的误差数据与建议 | Codex（验证侧，不读 RTL） | C-1 | 模型覆盖规格全部功能；数值报告 `docs/reports/<日期>-model-gpu-numeric.md` | [x] a2f6adecd 合入 zc100116/gpu；数值报告 `2026-11-24-model-gpu-numeric.md` |
| D-1 | GPU 微结构设计记录：单元划分、单元间接口（信号、握手、时序）、流水线、片上 RAM 组织（纹理存储体、渲染目标 4 像素字）、读改写旁路、资源和时序估算 | Codex 起草，协调者逐条评审 | C-1 | 设计记录 `docs/design/<日期>-gpu-microarch.md` 经协调者批准；内部接口冻结 | [~] 修订稿 b2ac0bb8b 已评审通过：GPU DRM 193、APM 172、LUT 约 55K（估算），全芯片 DRM 约 62%；D-1c 完成（gpu-dev 8f9272261）。前端/DMA/像素/目标/对象的接口已冻结；几何、建立、光栅化、透视、纹理的接口 [!] 阻塞：v0.2 算术按每像素精确除法定义，估算 GPU 约 73 万 LUT，需修订规格算术（S-2）后重定 |
| S-1 | 协调者根据 M-1 修订 `gpu-spec.md` 为 v0.2（G-N1–G-N3 定稿），经用户确认 | 协调者 | M-1 | 规格 v0.2 | [x] v0.2 已确认（用户 2026-11-23，8908a5cbe）；M-1b 按 v0.2 更新模型（双线性减半纹素、视口取自 SET_TARGET）并删除研究参数 |
| S-2 | 逐像素算术改为硬件可实现的定义（平面方程插值、LOD 乘法求偏导、透视位宽）：M-1c 数值研究（ctx_0cecc4ee61cb，用户 2026-11-23 同意）→ 规格 v0.3 → D-1 重定几何/光栅/纹理接口 | M-1c Codex；协调者修订规格 | D-1c | 规格 v0.3 经用户确认 | [~] M-1c 完成（b3315ccb0，B32/P18：64 APM、约 1.4 万 LUT，误差达标）；规格 v0.3 已确认（用户 2026-11-23）；D-1d 重定接口中（ctx_39e6e600928e） |
| R-1 | GPU 前端：寄存器块、命令处理、DMA（命令、顶点、四边形、对象表、纹理装入）、RESOLVE 与后处理抗锯齿 | Codex | D-1、S-1 | 单元测试；lint 0 | [x] 48136be87、edd379254：7 个单元 PASS；包装评审通过 |
| R-2 | 几何：顶点变换、光照、裁剪、透视除法、背面剔除、三角形建立 | Codex | D-1、S-1 | 单元测试对照参考模型逐位一致 | [x] 1f4d360ed：顶点 II=2、建立 II=8 实测；geometry 87 + setup 42 APM（全芯片估算 257/740） |
| R-3 | 光栅化（三角形、四边形快速通道）与对象单元 | Codex | D-1、S-1 | 单元测试 | [x] 对象单元 R-3o 完成（8fb39eb19）；光栅化、四边形、透视 R-3r 完成（20f072dcd、ab8e9265a，评审通过） |
| R-4 | 纹理单元（取样、mipmap、调色板）、像素运算（模板、深度、混合）、片上渲染目标 | Codex | D-1、S-1 | 单元测试 | [x] 像素运算和目标 R-4b 完成（1d788b9e4）；纹理 R-4a 完成（01de6cd72，评审通过；1024×20 真双口是否 1 块 DRM 待 Windows 生成确认） |
| V-1 | GPU 模块级测试环境和 GT-01–GT-25（不读 RTL） | Codex（验证侧） | M-1、C-1 | 环境可运行；测试按验证方案实现 | [x] V-1a b851cc734、V-1b 4c0dde3c3、V-1c 6fccf92b4：GT-01–25 模型对模型全部 PASS；V-1b2 补时钟设置 |
| I-1 | GPU 集成：`edrv32_gpu` 顶层，跑 GPU 模块级全部档位，按 11.3 分清 RTL、测试、规格问题 | Codex（集成） | R-1–R-4、V-1 | smoke、full 通过；perf 报告 | [x] fc448d81b 集成；I-2 修复 7257fa437、382469085（RESOLVE 首尾包、object 完成）后 GT-01–25 全部 PASS |
| A-1 | AUD RTL、单元测试，以及 AT-01–AT-09（RTL 和测试由两个 worker 分开写） | Codex × 2 | C-1 | smoke、full 通过 | [x] A-1r 0ea3c68b7（单元 5 项 PASS）；A-1v 04910154a（AT-01–09 在 RTL 上全部 PASS）；aud-spec v0.2 澄清 |
| X-1 | mem_xbar 改为 5 个端口，相应测试改写（ST-01–03） | Codex；**协调者逐行评审** | — | ST-01–03 通过 | [x] gpu-dev b8cda862d，协调者逐行评审通过；47 项 PASS |
| X-2 | DISP 增加 `L0_X2`；测试 ST-04–07 | Codex | — | ST-04–07 通过 | [x] gpu-dev 0a7a9ef1d；77 项 PASS |
| X-3 | 系统子系统：reset_ctrl 改名和新增 `rst_aud_n`；CHIP_ID | Codex | — | 视觉项目系统子系统测试通过 | [x] gpu-dev 48091fd90，协调者评审通过；测试 8 项 PASS |
| T-1 | `edrv32_gpu_soc_top`、本项目文件列表、板级顶层和约束（PLL 增加 clk_gpu、clk_aud 输出；I2S、I2C 引脚按 J25 PMOD-D）、PDS 导入脚本 | Codex（RTL）；协调者（约束、脚本、IP 说明） | I-1、A-1、X-1–X-3 | SoC lint 0；ST-08、ST-09 通过 | [x] 地址表 6d396ffb4；SoC 顶层 T-1a 455383e37；板级顶层、PLL 说明、约束、导入脚本 T-1b 5984930a7（协调者评审通过） |
| W-1 | BSP 驱动（GPU、AUD、ES8156 配置）和 SoC 测试程序 ST-10–ST-14 | Codex | T-1 | SoC smoke、full 通过 | [x] W-1a 0f3cf7347；I-2 修复复位释放顺序 1aad898b8、ST-08 超时 06d94ada3 后 ST-08–14 全部 PASS（ST-08 仿真 2590 s，full 档） |
| S-3 | 资源闭合第二轮：算术流水重写（microarch 4.13）、平面精度 G、2×2 LOD（规格 v0.4，用户 2026-11-25 同意，7335a9fbe）；之后出卡 107 第 7 轮 | Codex（ctx_758a8032e299） | S-2 FF 整改（8807e6580）、M-2/M-2b（273905071） | Yosys GPU FF ≤ 120k、perspective LUT6 −50%；单元测试和 GT-01～25 通过 | [x] 完成（0725ffa10..0018e27f2）：Yosys GPU FF 286k→201k、LUT6 315k→269k，perspective FF 27.4k；GPU FF 未达 120k（Yosys 偏大，以 PDS 为准）；卡 107 第 7 轮已下发（1ff651219） |
| B-1 | Windows 任务卡：PLL IP 修改说明、综合、布局布线、时序和资源报告，上板跑 ST-10、ST-12 的程序 | 协调者写卡，用户和 Windows Codex 执行 | W-1 | 报告回传；定稿 G-T1、G-R1、G-R2、GS-1、GS-3 | [~] 卡 107：13 个新 IP 已生成（用户 2026-11-24）；纹理/调色板 RAM 包装端口改为 PDS 的 a_*/b_* 命名 d0d9c022d；重跑后 PDS rtl-infer 内部崩溃（InferWriteMode.cpp:2983，Flow-0189），write_dma 单独编译通过；卡 109 定位到 unpack 共享数组多进程动态写（PDS 内部崩溃）和 clip output_r 整字/分段双写（多驱动），已改写；S-1A–D 硬件风格整改 16 个提交并入 gpu-dev（3aae2e38f..a5ee47f2f，lint/风格 0 告警），卡 107 第 3 轮已下发 |
| V2-1 | 第二版：可编程顶点着色器（4 路 SIMD），取代几何单元（设计记录 gpu-architecture 第 7 节）；第一版完成后再讨论规格 | — | 第一版上板 | — | [ ] |
| S-0a | GPU 模拟器核心：Python 参考模型的 C 移植（设计记录 2026-11-23-gpu-pc-emulator） | Codex | M-1 | 全部 GT/自测场景与 Python 模型逐位一致；压力场景一帧 ≤ 16 ms | [x] 2367f249f：121 个 GT 子场景 + 12 组自测逐位一致；S-0d 0f80d2861 提速：压力帧单线程 20.5 ms、三线程 11.0 ms |
| S-0b | PC 平台：替换 mmio.h 的虚拟 SoC（GPU、DISP、AUD、PLIC）、游戏平台层、Windows exe 与 Linux 无界面前端、示例程序 gpu_hello | Codex | S-0a、S-0c | 三种构建 0 告警；gpu_hello 出帧且与 Python 模型一致 | [x] e8fa1e59d：三种构建 0 告警；gpu_hello 第 150 帧与 Python 模型逐位一致（协调者用 2367f249f 复跑通过） |
| S-0c | 驱动 mmio 改造：gpu.c、aud.c 改用 mmio.h，新增 ddr_physical() | Codex（W-1a） | W-1 | 全部 sw 构建 0 告警，行为不变 | [x] 166c00a27 |
| G-1 | 游戏《余烬群岛》（2D 肉鸽 + 3D 对战，共用世界观；设计总纲 sw/apps/ember_isles/docs/gdd.md，逐章与用户确认）和测试展示页 | Codex | W-1、S-0、玩法确认 | PC 上运行，上板运行 | [~] GDD v1.0.1 + tech v1.0；E1+E2 完成（16f6fc83d，报告 sw/apps/ember_isles/docs/report-e1e2.md：四目标 0 告警，10800 帧录像通关 5 波，PC/Spike 摘要一致；音频峰值超分项预算 14%）；待用户试玩，E3–E5 待派 |

## 4. 规格定稿项

| 待定项 | 时机 | 依据 |
|---|---|---|
| gpu-spec G-N1–G-N3 | M-1 完成后（S-1） | 参考模型误差数据 |
| gpu-spec G-R1 | 已定 192 KiB（用户 2026-11-23，S-1 写入） | 资源闭合设计记录 |
| gpu-spec G-T1、G-R2、G-P1 | B-1 后（G-T1 初值改 180 MHz，S-1 写入） | PDS 报告、perf 测量 |
| gpu-soc-spec GS-1、GS-3 | B-1 后 | PDS 报告 |
| gpu-soc-spec GS-2 | 现在 | 用户确认 CHIP_ID |
| gpu-soc-spec GS-4 | W-1 后 | 联调带宽测量 |
| aud-spec A-1–A-3 | 上板后 | 听感、DDR 延迟 |

## 5. 风险和阻塞

| 风险 | 应对 |
|---|---|
| DRM 预算偏紧 | 已决定目标减半等（da4c70345），全芯片 DRM 估算约 62%；按 ≤ 65% 控制 |
| clk_gpu 时序：透视校正的倒数、三线性、混合乘法链较长 | D-1 按 PDS 级数预算切流水；按全 SoC 拥塞留余量（150 MHz 初值） |
| 主机只有 7 GiB 内存、3 核 | 本机 worker 仿真 `-j 1`；大规模回归放到仿真虚拟机（只能由 Codex 访问） |

## 6. 变更记录

| 日期 | 版本 | 内容 |
|---|---|---|
| 2026-11-23 | v0.1 | 初稿 |
| 2026-11-23 | v0.1 | 规格 v0.3 确认；D-1 接口冻结（建立 II ≤ 8 另注）；派 R-2、R-3r、R-4a、T-1a、W-1a；X-2、V-1 完成 |
| 2026-11-23 | v0.1 | M-1b 合入 gpu-dev；D-1c 发现 v0.2 算术不可实现，几何/光栅/纹理阻塞待 S-2；派发 R-1、R-4b、R-3o |
| 2026-11-23 | v0.1 | 规格 v0.2 确认；G2 第一批 8 个任务派发（M-1b、D-1c、A-1r、A-1v、X-1、X-2、X-3、V-1a），共用 gpu-dev |
| 2026-11-23 | v0.1 | M-1 完成并合入；S-1 规格 v0.2 草案 |
| 2026-11-23 | v0.1 | 资源闭合决定（目标减半、纹理 192 KiB、调色板改造、200 MHz 级数预算、STEP=0 只绘制），D-1b 派发，M-1 已通知 |
| 2026-11-23 | v0.1 | M-1、D-1 用 gpt-6.1-sol 派发；D-1 草稿完成，问答中的规格缺口（视口、对象失效与碰撞、PERF4 口径、纹理分体布局、吞吐测量条件）归入 S-1 |
