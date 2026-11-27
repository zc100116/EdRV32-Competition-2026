# CPU v2 FPU APM 原语包装

| 项 | 固定配置 |
|---|---|
| 依据 | fpu-spec v0.1 5.2、5.3；CPU v2 探针 P09 |
| 使用者 | `edrv32_cpu2_fpu_fma32`，clk_sys，II=1 |
| 原语 | PDS 器件库 `GTP_APM_E2`，不需要 IP Compiler 生成 |
| 原生包装 | `rtl/tech/edrv32_apm_cpu2_head.v`、`edrv32_apm_cpu2_shift16.v` |
| 固定宽包装 | `rtl/tech/edrv32_apm_cpu2_u24xu24.v`，完整无符号 48 位积 |
| APM 数 | 2；低 16 位乘项在链头，高 8 位乘项在链尾 |
| 延迟 | 原生单元 3 个采样沿；两级乘法链 4 个采样沿（FMA E2–E5） |

CPU 包装独立于 GPU 包装；工程只需导入 `rtl/filelists/cpu2_probe_fma.f`，
通过 `fpga/scripts/import_probe_cpu2_fma_top.tcl` 定义 `FPGA_MODE`。
`SIM_MODE` 分支逐级使用与原语相同的 X/Y、MULT、P/CPO 寄存边界；数据不复位。

## 原生单元配置与连接

- `GRS_EN="FALSE"`，`USE_POSTADD=1`，`USE_PREADD=0`，`USE_SIMD=0`，`ASYNC_RST=0`。
- `X_REG=Y_REG=MULT_REG=P_REG=CPO_REG=1`，全部 CE 连接 `enable_i`；全部 RST 接 0。
- `MODEY=3'b001`、`MODEIN=5'b00010`；head `MODEZ=0`，shift16 `MODEZ=6`。
- X 接 `{5'b0,x_i[24:0]}`，Y 接 `y_i[17:0]`；CPU significand 通过补零保持正数。
- head：`x={1'b0,a[23:0]}`，`y={2'b0,b[15:0]}`，CPI 接 0。
- tail：`x={1'b0,a_delayed[23:0]}`，`y={10'b0,b_delayed[23:16]}`，CPI 接 head CPO。
- tail 的后加项是 `CPI >>> 16`；两输入错后 1 拍，使 tail MULT 与 head CPO 同事务。
- 输出是 `{tail.P[31:0],head.P_delayed[15:0]}`，完整保留 48 位，不在乘法链内舍入。
- `Z/CXI/CXBI/XB/CIN` 接 0，`COUT/CXO/CXBO` 不连接；每级 P/CPO 均启用寄存。

E2 规格化直接进入 head 内部 X/Y；tail 的输入错拍 FF 是级联对齐所需寄存，
不是 head X/Y 的外部同值副本。E3 head MULT、tail X/Y；E4 head P/CPO、tail MULT；
E5 tail P/CPO、低 16 位残数。PDS 须实测内部寄存路径与专用 CPI/CPO 级联，
确认使用两颗 APM、物理级联放置和 150 MHz 时序；Linux 代理不证明这些物理性质。

## 验证与复现

`python3 verif/unit/cpu2_fpu_fma32/run.py smoke` 和 `full` 逐位比较完整 FMA 结果和 flags，
覆盖非规格化 significand 的输入规格化、完整低积及流水错拍。
`python3 verif/unit/cpu2_fpu_fma32/levels.py` 把原语作为时钟边界，生成 XC7 LUT6/进位链
代理级数；原语内部不映射成 LUT、不重复计入 CLM FF。最终 PDS 结果由协调者任务卡回传。
