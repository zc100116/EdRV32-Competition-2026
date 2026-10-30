# GTP_APM_E2 原语：NPU INT8 SIMD 级联（不经 IP Compiler 生成）

| 项 | 内容 |
|---|---|
| 类型 | APM 原语 `GTP_APM_E2`，两路独立有符号 INT8 乘法及 24 位后加 |
| 包装模块 | `rtl/tech/edrv32_mac_npu_int8_chain.v`，FPGA 分支直接例化原语 |
| 使用者 | `edrv32_npu_mac_array`，32 条八级链，共 256 APM、512 MAC/拍 |
| 依据 | npu-spec v0.5 5.4 C1–C8；设计记录 `docs/design/2026-10-30-npu-apm-cascade.md` 3–6 |

原语由 PDS 器件库提供，无需在 IP Compiler 中生成模块。PDS 工程导入此包装，定义
`FPGA_MODE`，选择 PG2L200H-6/FBB676；不要把厂商仿真模型加入综合文件列表。

## 固定配置

| 参数 / 端口 | 取值 |
|---|---|
| `USE_SIMD` / `USE_PREADD` / `USE_POSTADD` | 1 / 0 / 1 |
| `X_REG` / `Y_REG` / `MULT_REG` / `P_REG` / `CPO_REG` | 1 / 1 / 1 / 1 / 1 |
| `ASYNC_RST` / `GRS_EN` | 0 / `"FALSE"` |
| 其余原语参数 | 保留器件库缺省值（包装未覆盖） |
| `MODEY` / `MODEZ` / `MODEIN` | `3'b001` / `4'b0011`（Z 取 CPI）/ `5'b00010` |
| `X[29:0]` | `{6'b0, {4{a1[7]}}, a1, {4{a0[7]}}, a0}` |
| `Y[17:0]` | `{b1[7], b1, b0[7], b0}` |
| `CPI[47:0]` | 包装输入 `cpi_i`；第 0 级接 0，其余接前一级 `cpo_o` |
| `CPO[47:0]` | 包装输出 `cpo_o`；仅接下一级 CPI，末级不连接 |
| `P[47:0]` | 包装输出 `p_o`；与 CPO 同拍同值，阵列从末级 P 取结果，前七级不连接 |
| `COUT`、`CXO`、`CXBO` | 不连接 |
| `Z` / `CXI` / `CXBI` / `XB` / `CIN` | 全 0 |
| 所有 CE | 1；不暴露全局 CE |
| 所有 RST | 0；数据通路不复位 |

包装端口：`clk_i`，`a0_i[7:0]`、`b0_i[7:0]`、`a1_i[7:0]`、`b1_i[7:0]`，
`cpi_i[47:0]`，`cpo_o[47:0]`，`p_o[47:0]`。无参数、无初始化文件。

## 延迟与位序

第 1 沿采样输入，第 2 沿产生乘积，第 3 沿将乘积与该沿的 CPI 相加。
两路分别在低/高 24 位回绕，低路进位不进入高路。第 k 个链单元的操作数晚 k 沿；
八级链输出在第 10 沿有效。每通道两个像素结果分别取末级 P 的 `[18:0]` 和 `[42:24]`，
保留原 19 位接口；每拍均可开始新的归约。

## EQ-01 等价性测试

Linux Icarus Verilog 12.0 四态仿真，直接比较包装 SIM_MODE 和 FPGA_MODE 分支，
同时检查厂商 P 与 CPO；单级包含随机 CPI 和 24 位回绕，八级链包含逐项错拍、
随机 INT8 和 −128/127 极值，超过 1000 拍。厂商模型不入库：

```sh
. ~/.local/opt/edrv32/env.sh
export EDRV32_PANGO_SIM_DIR="$HOME/.local/share/edrv32/pango"
flock /tmp/edrv32-sim.lock python3 tools/regress.py smoke --path verif/unit/npu_mac_chain -j 1
```

变量必须指向包含 `GTP_APM_E2.v` 的目录，未设置立即报错。测试顶层提供
`GRS_INST.GRSNET = 1'b1` 桩；详细结果见 `docs/reports/2026-10-30-resource-npu-cascade.md`。
