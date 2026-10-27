# GTP_APM_E2 原语：NPU INT8 双乘法（不经 IP Compiler 生成）

| 项 | 内容 |
|---|---|
| 类型 | APM 原语 `GTP_APM_E2`，原生 SIMD 模式，每个 APM 两个独立的有符号 INT8 × INT8 |
| 包装模块 | `rtl/tech/edrv32_mul_npu_int8_pair.v`（FPGA 分支直接例化原语） |
| 使用者 | `edrv32_npu_mac_array`，256 实例（32 输出通道 × 8 输入），共 512 个乘法/拍 |
| 依据 | NPU 规格 1、5.4；设计记录 `docs/design/2026-10-27-npu-datapath.md` 4.6.1；旧工程 `legacy/rtl/vision/yolo/edrv32_yolo_apm_mul2.v`（已上板验证同一配置） |

## 为什么不用 IP Compiler

IP Compiler 的乘法器界面只生成单路宽乘法，没有两路独立 INT8 的 SIMD 选项；改成普通宽乘法再拆位会得到错误的符号处理。旧工程直接例化 `GTP_APM_E2` 并在板上跑通整网，本包装沿用同一组参数。原语来自 PDS 器件库，工程中不需要生成任何文件，**用户无需操作**；只需在 Windows ModelSim 上做一次行为模型与原语的等价性测试（随 NPU 数据通路的 Windows 任务卡进行）。

## 原语配置

| 参数 / 端口 | 取值 |
|---|---|
| `USE_SIMD` | 1 |
| `USE_PREADD` / `USE_POSTADD` | 0 / 0 |
| `X_REG` / `Y_REG` / `MULT_REG` / `P_REG` | 1 / 1 / 1 / 0（两级：输入寄存 + 乘法寄存） |
| `ASYNC_RST` / `GRS_EN` | 0 / "FALSE" |
| `MODEY` / `MODEZ` / `MODEIN` | `3'b001` / `4'b0000` / `5'b00010` |
| X（30 位） | `{6'b0, {4{a1[7]}}, a1, {4{a0[7]}}, a0}`（两个 12 位子字，各自符号扩展） |
| Y（18 位） | `{b1[7], b1, b0[7], b0}`（两个 9 位子字） |
| 输出 | `p0 = P[15:0]`、`p1 = P[39:24]` |
| Z、CPI、CXI、CXBI、XB、CIN | 0 |
| 全部 CE | 1 |
| 全部 RST | 0（数据通路不复位） |

延迟：操作数在第 1 个时钟沿进入输入寄存器，第 2 个沿后乘积有效，与行为模型相同。

## 等价性测试要求（Windows ModelSim）

覆盖 a、b 的全部边界组合（−128、−1、0、1、127）和随机值，两路互相独立，逐拍比较 `p0_o`、`p1_o` 与行为模型。结果写进对应任务卡的 `result.md`。
