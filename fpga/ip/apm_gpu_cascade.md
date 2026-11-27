# GTP_APM_E2 原语：GPU 宽乘法级联（不经 IP Compiler 生成）

| 项 | 内容 |
|---|---|
| 类型 | APM 原语 `GTP_APM_E2`，25×18 有符号乘法加 48 位后加，带移位的 CPI/CPO 级联 |
| 原生包装 | `rtl/tech/edrv32_apm_gpu_head.v`（链头，MODEZ=0）、`edrv32_apm_gpu_shift8.v` / `shift16.v` / `shift24.v`（CPI>>>8/16/24） |
| 固定宽乘法包装 | `rtl/tech/edrv32_apm_gpu_{s32xs16,u24xu8,u33xu8,s40xs43,s40xu35,u35xu16,s94xu16,u31xu30,u30xu32,s34xs18,s56xu31,s56xs18}.v`，只连接原生包装、输入错拍和低位残数 |
| 使用者 | GPU transform、clip、project、project_recip、setup_plane、setup |
| 依据 | gpu-spec v0.6 2.4、2.12、2.13；设计记录 `docs/design/2026-11-27-gpu-apm-cascade.md`（配置表、级联次序、APM 数和延迟） |

原语由 PDS 器件库提供，**用户不需要在 IP Compiler 中生成任何模块**。PDS 工程照常导入 `rtl/filelists/gpu.f` 中的包装并定义 `FPGA_MODE`。不要把厂商仿真模型加入综合文件列表。

## 原生单元的固定配置

| 参数 / 端口 | 取值 |
|---|---|
| `USE_POSTADD` / `USE_PREADD` / `USE_SIMD` | 1 / 0 / 0 |
| `X_REG` / `Y_REG` / `MULT_REG` / `P_REG` / `CPO_REG` | 全为 1 |
| `ASYNC_RST` / `GRS_EN` | 0 / `"FALSE"` |
| `MODEY` / `MODEIN` | `3'b001` / `5'b00010` |
| `MODEZ` | head `4'd0`，shift8 `4'd7`，shift16 `4'd6`，shift24 `4'd5` |
| `X` / `Y` | `{5'b0, x_i[24:0]}` / `y_i[17:0]` |
| `CPI` / `CPO` | 后级 CPI 接前级 CPO（专用级联走线）；head 不选 CPI |
| `P` | 寄存后的后加结果，接低位残数寄存和链尾结果 |
| `Z`、`CXI`、`CXBI`、`XB`、`CIN` | 全 0；`COUT`、`CXO`、`CXBO` 不连接 |
| CE / RST | CE 接包装的 `enable_i`；RST 全 0，数据不复位 |

延迟：原生单元从输入采样起 3 拍（X/Y、乘积、后加各 1 拍）；n 级链为 n + 2 拍。每个固定宽乘法包装的级联次序、APM 数和延迟见设计记录"固定宽乘法包装的级联次序"表。

## 验证

- 本机 Icarus：包装的 SIM 行为模型与厂商模型 `GTP_APM_E2.v` 逐拍比对，12 种包装各 1000 轮随机和极值，全部 PASS（R-6a，`d632b2c55`）。
- PDS 需要确认：级联链的物理放置（同一 APM 列中连续站点）、`clk_gpu` 时序、APM 实际用量。结果在下一张 PDS 任务卡中回传。
