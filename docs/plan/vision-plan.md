# 图像通路实施方案（P3 实时视频通路、P4 图像处理、ETH）

| 项 | 内容 |
|---|---|
| 版本 | v0.3 |
| 日期 | 2026-10-27 |
| 方案 | `docs/design/2026-10-27-image-path.md`（已决定） |
| 规格 | `docs/spec/dma2d-spec.md` v0.1、`vin-spec.md` v0.1、`disp-spec.md` v0.2、`pix-spec.md` v0.1（已确认）；`geo-spec.md`、`eth-spec.md` 待写；SoC 规格 v0.11 |

## 1. 目标和完成标准

摄像头（或网口图像经 VIN 内存源）→ PIX → DDR →（可选）GEO → DDR → DISP → HDMI 闭环：模块级测试逐像素与参考模型一致，SoC 级仿真无 underflow/overflow，上板 720p30 连续运行。各规格的验证方案 smoke、full 档全部通过。

## 2. 前置条件

存储子系统（mem_xbar、DDR 网关）、系统子系统（I2C0、GPIO0、PLIC）已合入 main。mem_xbar P1 读通道：存储子系统规格 v0.3 已确认，RTL 见 V-M1。

## 3. 待办清单

| 编号 | 内容 | 执行者 | 依赖 | 验收 | 分支 | 状态 |
|---|---|---|---|---|---|---|
| V-L1 | 旧工程图像通路盘点 | Codex · GPT-6 Luna | — | `docs/design/2026-10-27-image-path-legacy-inventory.md` | task-vision-inventory | [x] 0af888b |
| V-S1 | dma2d 规格和验证方案 | 协调者 + 用户确认 | — | 规格已确认 | — | [x] 2026-10-27 |
| V-D1 | dma2d_rd / dma2d_wr RTL 和单元测试 | Codex · GPT-6.1 Sol | V-S1 | `verif/unit/dma2d_{rd,wr}` smoke/full 通过，lint 0 告警 | task-dma2d | [x] c3a8c5f、3999e1e（Yosys 参考 rd 393 LUT6/165 FF，wr 664/436） |
| V-S2 | VIN、DISP 规格（含内存源、NPU 适配接口）；SoC 与存储子系统规格修订（P1 读通道） | 协调者 + 用户确认 | V-L1 | 规格已确认 | — | [x] 2026-10-27：vin-spec、disp-spec v0.1，SoC v0.9，mem-subsys v0.3；testplan vin、disp v0.1 |
| V-M1 | mem_xbar P1 增加读通道（存储子系统规格 v0.3 2.2、3.1；testplan MX-13）：`edrv32_mem_xbar`、`edrv32_mem_subsys` 的 P1 读端口和 OUTST_RD[1] 复位值 | Codex · GPT-6.1 Sol | V-S2 | `verif/unit/mem_xbar`、`verif/block/mem_subsys` full 通过（含新增 MX-13），lint 0 告警 | task-mem-p1-read | [x] 2026-10-28：mem_xbar unit full 3、mem_subsys full 49（含 MX-13）PASS |
| V-R1 | VIN RTL（CH0、CH1、内存源、两路前端、P1 仲裁，CH2 不实现）和单元测试 | Codex · GPT-6.1 Sol | V-D1 | 单元测试通过，lint 0 告警 | task-vin-rtl | [x] 2026-10-28：6 组单元 smoke/full PASS；Yosys 不含存储 7097 LUT6（超 4K 目标，待 V-P1 与 PDS） |
| V-T1 | VIN 模块级测试（`verif/block/vin`，DVP 模型 `verif/models/dvp_camera_model.sv`），不读被测 RTL | Codex · GPT-6.1 Sol | V-S2 | testbench 按 vin-testplan 完成，模型自测通过 | task-vin-verif | [x] 2026-10-28：DVP 模型自测 PASS，VI-01–17 在桩下编译通过；通过判定在 V-I1 |
| V-R2 | DISP RTL（时序、TMDS 编码按旧工程移植，读控制、扫描、欠账）和单元测试 | Codex · GPT-6.1 Sol | V-D1 | 单元测试通过，lint 0 告警 | task-disp-rtl | [x] 2026-10-28：6 组单元 smoke/full 12 PASS；停止确认握手（disp-spec v0.2 2.8）；Yosys 3920 LUT4（超 2.5K 目标，待 PDS） |
| V-T2 | DISP 模块级测试（`verif/block/disp`，TMDS 接收模型、Python 参考编码），不读被测 RTL | Codex · GPT-6.1 Sol | V-S2 | testbench 按 disp-testplan 完成，模型自测通过 | task-disp-verif | [x] 2026-10-28：DS-01–13 smoke 12/12、full 29/29 PASS（接真 RTL，未读源码）；V-P2 后在 DRM FIFO 上 smoke 复跑通过 |
| V-I1 | VIN、DISP 联调：跑模块级回归，区分 RTL 错误、测试错误、规格歧义 | Codex · GPT-6.1 Sol | V-R1、V-T1、V-R2、V-T2 | vin、disp testplan smoke/full 通过 | task-vin-disp-int | [x] 2026-10-28：DISP 部分由 V-T2 直接接真 RTL 跑通；VIN smoke 2/2、full 3/3（VI-01–17、完整尺寸、10 种子）与 6 个单元 smoke 通过，只改测试侧（`docs/debug/2026-10-28-vin-block-integration.md`） |
| V-P1 | 写 FIFO、内存源输入缓冲、扫描 FIFO 的存储 IP 创建说明和包装模块 | 协调者 | V-R1、V-R2 的存储需求 | `fpga/ip/` 创建说明、`rtl/tech/` 包装模块 | — | [x] 2026-10-28：`ip_ram_vin_wfifo`（512 × 288）、`ip_ram_disp_scan`（512 × 256 双时钟）创建说明和包装模块（8217c48） |
| V-P2 | 基于 RAM 的 FIFO 控制器（`edrv32_sync_fifo_ram`、`edrv32_async_fifo_ram`），VIN 写 FIFO、内存源缓冲、DISP 扫描 FIFO 改用 V-P1 包装 | Codex · GPT-6.1 Sol | V-P1 | FIFO 单元测试与 VIN/DISP 全部单元测试通过，lint 0 告警 | task-media-fifo-ram | [x] 2026-10-28 ea7f137：14 个单元目录 smoke/full 16/16 PASS；Yosys 参考 VIN 8829 LUT6（含 1160 位小 FIFO）、DISP 3947 LUT4，RAM 黑盒 3 + 1 |
| V-S3 | PIX、GEO 规格 | 协调者 + 用户确认 | V-L1 | 规格已确认 | — | [~] 2026-10-28：PIX 规格 v0.1 与验证方案已确认（2951da8）；GEO 待起草 |
| V-P3 | PIX 行缓存 IP 创建说明和包装模块 | 协调者 | V-S3（PIX） | `fpga/ip/ip_ram_pix_line.md`、`rtl/tech/edrv32_ram_pix_line.v` | — | [x] 2026-10-28：1024 × 48 简单双口，4 实例 |
| V-R3 | PIX RTL 和单元测试 | Codex · GPT-6.1 Sol | V-P3 | 单元测试通过，lint 0 告警；Yosys 参考 LUT | task-pix-rtl | [x] 2026-10-28：6 个 RTL 模块，单元 pix_point/pix_filter/pix_control smoke/full 6 PASS；Yosys 参考 33170 LUT6、5234 FF（远超 3K 估算，Gamma 表未映射为 LUTRAM；面积以 PDS 为准，另立任务） |
| V-T3 | PIX 模块级测试（`verif/block/pix`，Python 参考模型 `pix_ref.py`），不读被测 RTL | Codex · GPT-6.1 Sol | V-S3（PIX） | testbench 按 pix-testplan 完成，参考模型自测通过 | task-pix-verif | [ ] |
| V-I2 | PIX 联调：block/pix smoke/full；VIN + PIX 联合测试 VI-18（pix-testplan 待定事项 1） | Codex · GPT-6.1 Sol | V-R3、V-T3 | pix testplan smoke/full 通过，VI-18 通过 | task-pix-int | [ ] |
| V-S4 | ETH 规格（网口图像协议、ARP） | 协调者 + 用户确认 | — | 规格已确认 | — | [ ] |

后续待办（PIX、GEO、ETH 的 RTL 和验证；OV5640 软件驱动；板级顶层、约束和 Windows 任务卡）在对应规格确认后补入。

## 4. 规格定稿项

dma2d 资源指标在 PDS 实测后定稿；其余模块随各自规格列出。

## 5. 风险和阻塞

| 风险 | 应对 |
|---|---|
| 摄像头 PCLK、消隐、引脚、HDMI PLL 在仓库中没有板级记录（V-L1） | 板级约束从厂商例程取得，通过 Windows 任务卡核对 |
| mem_xbar P1 改为读写需修改已合入的 RTL | 随 V-S2 规格修订单列一个 RTL 任务，回归 mem_xbar 全部测试 |

## 6. 变更记录

| 日期 | 版本 | 变更 |
|---|---|---|
| 2026-10-27 | v0.1 | 初稿：V-L1、V-S1 完成，V-D1 待派 |
| 2026-10-27 | v0.2 | V-S2 完成；增加 V-M1、V-R1、V-T1、V-R2、V-T2、V-I1、V-P1 |
| 2026-10-28 | v0.3 | PIX 规格确认；增加 V-P3、V-R3、V-T3、V-I2 |
