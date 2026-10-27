# 图像通路实施方案（P3 实时视频通路、P4 图像处理、ETH）

| 项 | 内容 |
|---|---|
| 版本 | v0.1 |
| 日期 | 2026-10-27 |
| 方案 | `docs/design/2026-10-27-image-path.md`（已决定） |
| 规格 | `docs/spec/dma2d-spec.md` v0.1（已确认）；`vin-spec.md`、`disp-spec.md`、`pix-spec.md`、`geo-spec.md`、`eth-spec.md` 待写；SoC 规格 v0.8 |

## 1. 目标和完成标准

摄像头（或网口图像经 VIN 内存源）→ PIX → DDR →（可选）GEO → DDR → DISP → HDMI 闭环：模块级测试逐像素与参考模型一致，SoC 级仿真无 underflow/overflow，上板 720p30 连续运行。各规格的验证方案 smoke、full 档全部通过。

## 2. 前置条件

存储子系统（mem_xbar、DDR 网关）、系统子系统（I2C0、GPIO0、PLIC）已合入 main。mem_xbar P1 读通道：存储子系统规格 v0.3 已确认，RTL 见 V-M1。

## 3. 待办清单

| 编号 | 内容 | 执行者 | 依赖 | 验收 | 分支 | 状态 |
|---|---|---|---|---|---|---|
| V-L1 | 旧工程图像通路盘点 | Codex · GPT-6 Luna | — | `docs/design/2026-10-27-image-path-legacy-inventory.md` | task-vision-inventory | [x] 0af888b |
| V-S1 | dma2d 规格和验证方案 | 协调者 + 用户确认 | — | 规格已确认 | — | [x] 2026-10-27 |
| V-D1 | dma2d_rd / dma2d_wr RTL 和单元测试 | Codex · GPT-6.1 Sol | V-S1 | `verif/unit/dma2d_{rd,wr}` smoke/full 通过，lint 0 告警 | task-dma2d | [~] 2026-10-27 派发 |
| V-S2 | VIN、DISP 规格（含内存源、NPU 适配接口）；SoC 与存储子系统规格修订（P1 读通道） | 协调者 + 用户确认 | V-L1 | 规格已确认 | — | [~] 草案 vin-spec、disp-spec v0.1，待用户确认 |
| V-M1 | mem_xbar P1 增加读通道（存储子系统规格 v0.3 2.2、3.1；testplan MX-13）：`edrv32_mem_xbar`、`edrv32_mem_subsys` 的 P1 读端口和 OUTST_RD[1] 复位值 | Codex · GPT-6.1 Sol | V-S2 | `verif/unit/mem_xbar`、`verif/block/mem_subsys` full 通过（含新增 MX-13），lint 0 告警 | task-mem-p1-read | [ ] |
| V-S3 | PIX、GEO 规格 | 协调者 + 用户确认 | V-L1 | 规格已确认 | — | [ ] |
| V-S4 | ETH 规格（网口图像协议、ARP） | 协调者 + 用户确认 | — | 规格已确认 | — | [ ] |

后续待办（VIN、DISP、PIX、GEO、ETH 的 RTL、验证、联调、板级和 Windows 任务卡）在对应规格确认后补入。

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
