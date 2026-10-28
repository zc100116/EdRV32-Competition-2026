# 图像通路实施方案（P3 实时视频通路、P4 图像处理、ETH）

| 项 | 内容 |
|---|---|
| 版本 | v0.5 |
| 日期 | 2026-10-28 |
| 方案 | `docs/design/2026-10-27-image-path.md`（已决定） |
| 规格 | `docs/spec/dma2d-spec.md` v0.1、`vin-spec.md` v0.1、`disp-spec.md` v0.2、`pix-spec.md` v0.1、`geo-spec.md` v0.1、`eth-spec.md` v0.1（已确认）；SoC 规格 v0.13 |

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
| V-S3 | PIX、GEO 规格 | 协调者 + 用户确认 | V-L1 | 规格已确认 | — | [x] 2026-10-28：pix-spec v0.1、geo-spec v0.1 与验证方案已确认；SoC 规格 v0.12 |
| V-P3 | PIX 行缓存 IP 创建说明和包装模块 | 协调者 | V-S3（PIX） | `fpga/ip/ip_ram_pix_line.md`、`rtl/tech/edrv32_ram_pix_line.v` | — | [x] 2026-10-28：1024 × 48 简单双口，4 实例 |
| V-R3 | PIX RTL 和单元测试 | Codex · GPT-6.1 Sol | V-P3 | 单元测试通过，lint 0 告警；Yosys 参考 LUT | task-pix-rtl | [x] 2026-10-28：6 个 RTL 模块，单元 pix_point/pix_filter/pix_control smoke/full 6 PASS；Yosys 参考 33170 LUT6、5234 FF（远超 3K 估算，Gamma 表未映射为 LUTRAM；面积以 PDS 为准，另立任务） |
| V-T3 | PIX 模块级测试（`verif/block/pix`，Python 参考模型 `pix_ref.py`），不读被测 RTL | Codex · GPT-6.1 Sol | V-S3（PIX） | testbench 按 pix-testplan 完成，参考模型自测通过 | task-pix-verif | [x] 2026-10-28：d80c240（PX-01–14 两档，selftest PASS，未读 RTL） |
| V-I2 | PIX 联调：block/pix smoke/full；VIN + PIX 联合测试 VI-18（pix-testplan 待定事项 1） | Codex · GPT-6.1 Sol | V-R3、V-T3 | pix testplan smoke/full 通过，VI-18 通过 | task-pix-int | [x] 2026-10-28：未改 RTL，修 PX-13 测试调度、删无引用桩；PIX smoke 2、full 3 PASS，VIN smoke 3 PASS（含 VI-18），单元 3 目录 smoke/full PASS；PX-10 每拍 2 像素，PX-11 冲刷 1288 ≤ 1312 拍（`docs/debug/2026-10-28-pix-block-integration.md`）。既有 VIN smoke 冷构建 216 秒（编译 139 + 运行 78），超出 9.1 的约 60 秒，里程碑回归时处理 |
| V-R4 | GEO RTL 和单元测试；源缓冲组织确定后 ask 协调者建存储包装 | Codex · GPT-6.1 Sol | V-S3（GEO） | 单元测试通过，lint 0 告警；Yosys 参考 LUT | task-geo-rtl | [x] 2026-10-28：7ac1a35（已并入协调者分支）；单元 6 项 PASS；Yosys 参考 9292 LUT6，≤ 8K 由 PDS 判定 |
| V-P4 | GEO 源缓冲 IP 创建说明和包装模块（按 V-R4 提出的组织） | 协调者 | V-R4 提问 | `fpga/ip/`、`rtl/tech/` | — | [x] 2026-10-28：`ip_ram_geo_src` 写 256 × 128 / 读 2048 × 16，8 实例（每组 96 列 × 80 行，不回绕、无字节使能） |
| V-T4 | GEO 模块级测试（`verif/block/geo`，Python 参考模型 `geo_ref.py`），不读被测 RTL | Codex · GPT-6.1 Sol | V-S3（GEO） | testbench 按 geo-testplan 完成，参考模型自测通过 | task-geo-verif | [x] 2026-10-28：92b340b（GE-01–13 三档，selftest PASS，未读 RTL） |
| V-I3 | GEO 联调：block/geo smoke/full/perf | Codex · GPT-6.1 Sol | V-R4、V-T4 | geo testplan smoke/full 通过，GE-12 满足第 7 节 | task-geo-int | [x] 2026-10-28：未改 RTL，修测试问题；block smoke 2、full 3、perf 1 PASS，单元 6 目录 smoke/full PASS；GE-12 s=1 9.63 ms、s=2 19.62 ms（`docs/debug/2026-10-28-geo-block-integration.md`）；根目录 smoke 57 秒，保持 smoke |
| V-S4 | ETH 规格（网口图像协议、ARP） | 协调者 + 用户确认 | — | 规格已确认 | — | [x] 2026-10-28：eth-spec v0.1、eth-testplan v0.1 已确认；SoC 规格 v0.13；设计记录 `2026-10-28-eth.md` |
| V-R5 | ETH RTL（`rtl/eth/`：收发前端、异步 FIFO、过滤和 ARP、窗口写出、分包发送、MDIO、寄存器）和单元测试；接收/发送缓冲组织确定后 ask 协调者建存储包装 | Codex · GPT-6.1 Sol | V-S4 | 单元测试通过，lint 0 告警；Yosys 参考 LUT | task-eth-rtl | [x] 2026-10-28：ec3d2af（已并入协调者分支）；单元 smoke 6、full 2 PASS；Yosys 参考 8684 LUT6（目标 5K，由 PDS 判定）|
| V-P5 | ETH 接收/发送缓冲 IP 创建说明和包装模块（按 V-R5 提出的组织）；`rtl/filelists/eth.f` | 协调者 | V-R5 提问 | `fpga/ip/`、`rtl/tech/`、`rtl/filelists/` | — | [x] 2026-10-28：`ip_ram_eth_buf` 1024 × 32（接收、发送缓冲各 1 实例），`ip_ram_eth_fifo` 512 × 10 独立时钟（两个异步 FIFO） |
| V-T5 | ETH 模块级测试（`verif/block/eth`，对端模型 `verif/models/eth_peer_model.sv`、参考模型 `eth_ref.py`），不读被测 RTL | Codex · GPT-6.1 Sol | V-S4 | testbench 按 eth-testplan 完成，对端模型和参考模型自测通过 | task-eth-verif | [x] 2026-10-28：647650b（ET-01–15 三档，selftest PASS，未读 RTL） |
| V-I4 | ETH 联调：block/eth smoke/full/perf | Codex · GPT-6.1 Sol | V-R5、V-T5 | eth testplan smoke/full 通过，ET-14 满足第 7 节 | task-eth-int | [x] 2026-10-28：未改 RTL，修 3 处测试问题；block smoke 2、full 3、perf 1 PASS，单元 6 目录 smoke/full PASS；ET-14 接收 116.6 MB/s、发送 116.4 MB/s、ARP 0.10 µs（`docs/debug/2026-10-28-eth-block-integration.md`） |
| V-W1 | 媒体与网络模块 PDS 测量顶层（VIN、DISP、PIX、GEO、ETH 合并为 `edrv32_fpga_media_top`）、约束、导入脚本 | Codex · GPT-6.1 Sol | V-I1–V-I4 | lint 0 告警；Yosys 确认五个模块和 6 种 RAM 包装都保留 | task-media-fpga-top | [x] 2026-10-28：91368b8；58 个源文件；Yosys 参考 LUT6 VIN 8422、DISP 3179、PIX 32535、GEO 9043、ETH 8279 |
| V-W2 | Windows：生成 6 个新 IP，`edrv32_fpga_media_top` PDS 综合 + 布局布线，按层次资源和时序 | 用户 + Windows Codex | V-W1 | 任务卡、测量报告；PIX、GEO、ETH 资源与 SoC 9.3 对比 | `tasks/win/20261028-04-media-cpu-probes/`（A 部分），win/20261028-04-media-cpu-probes | [x] 2026-10-28：6 个 IP 端口一致；LUT VIN 3482、PIX 5593、DISP 1448（合计 10523，超 10K 预算 5.2%）、GEO 3238、ETH 3863；clk_mem −7.667 ns（63.8 MHz），最差 200 条全在 PIX 组合 3×3 核；clk_ext +2.064 ns；报告 `docs/reports/2026-10-28-timing-media-top.md` |
| V-R6 | PIX 时序：3×3 核和点运算切成流水（pix-spec 7：每级 1 行 + ≤ 16 拍，点运算 ≤ 8 拍），÷9 改为精确的常数乘移位；clk_mem 125 MHz 下 PIX 内寄存器间逻辑按 DRM 输出/APM 各占一级划分 | Codex · GPT-6.1 Sol | V-W2 | 单元 pix_* 与 block/pix smoke/full、VI-18 通过；PX-10 2 像素/拍、PX-11 冲刷不超上限；lint 0 告警 | task-pix-pipeline | [x] 2026-10-28：d9d5258；3×3 级一行 + 11 拍、点运算各 5 拍；÷9 改倒数乘并穷举；单元 4 目录、block/pix smoke/full、VI-18 通过；PX-10 2 像素/拍，PX-11 1312 拍（上限 1312）；待 PDS 复测（`docs/debug/2026-10-28-pix-pipeline.md`） |

后续待办（OV5640 软件驱动；PC 端网口工具和板上应用层协议；板级顶层、RGMII IO、约束和 Windows 任务卡；PIX、GEO、ETH 的 PDS 资源测量）在对应前置完成后补入。

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
| 2026-10-28 | v0.4 | GEO 规格确认；增加 V-R4、V-P4、V-T4、V-I3 |
| 2026-10-28 | v0.5 | ETH 规格确认（V-S4）；增加 V-R5、V-P5、V-T5、V-I4 |
| 2026-10-28 | v0.6 | V-W2 完成；增加 V-R6（PIX 流水化） |
