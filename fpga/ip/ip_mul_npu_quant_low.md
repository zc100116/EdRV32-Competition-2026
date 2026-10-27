# ip_mul_npu_quant_low

| 项 | 内容 |
|---|---|
| IP 类型 | IP Compiler → Arithmetic → APM 乘法器（Multiplier） |
| 模块名 | `ip_mul_npu_quant_low` |
| 包装模块 | `rtl/tech/edrv32_mul_npu_quant_low.v` |
| 用途 | 量化乘法的一半：acc+bias 低 17 位零扩展为有符号 18 位，乘有符号 16 位 mult；两半的乘积在量化流水中按 `hi × 2^17 + lo` 合成 49 位乘积 |
| 使用者 | `edrv32_npu_result_quant`，16 实例（量化 16 路并行） |
| 依据 | NPU 规格 2.3、5.4；设计记录 `docs/design/2026-10-27-npu-datapath.md` 4.6.2 |
| 器件 | PG2L200H |

## 选项

| 选项 | 取值 |
|---|---|
| A 输入 | 18 位，有符号 |
| B 输入 | 16 位，有符号 |
| 输出 P | 34 位（全精度） |
| 流水级数 | 2 级：Advanced Control 中勾选 XYREG 和 MREG，PREG、INREG、OUTREG 不勾选（20261027-02 生成并经 ModelSim 检查：第 2 个时钟沿后输出有效） |
| 时钟使能 | 若 IP 带 `ce` 端口，包装中接 1 |
| 复位 | IP 强制带高有效 `rst`；包装模块接 `1'b0` |

应只占 1 个 APM；在 `result.md` 中记录实际占用的 APM 数量。

## 期望端口

| 端口 | 方向 | 位宽 |
|---|---|---|
| `clk` | in | 1 |
| `ce` | in | 1 |
| `rst` | in | 1 |
| `a` | in | 18 |
| `b` | in | 16 |
| `p` | out | 34 |

## 生成后需要回传的信息

模块名、实际端口列表、实际 APM 占用和选项截图（放 `artifacts/`）。端口不一致时由协调者修改包装模块 FPGA 分支，不修改生成文件。
