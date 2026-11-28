# CPU v2 FP32 FMA 探针验证

`model.py` 用标准库 `fractions.Fraction` 构造精确积与和，只在最终目标精度舍入一次。
模型逐位解码 IEEE 编码，不用宿主 float；五种 rm、canonical NaN、sNaN、0×∞、
相反无穷及 NV/OF/UF/NX 均按 RISC-V 语义处理，tininess 在舍入后判断。

```sh
. ~/.local/opt/edrv32/env.sh
python3 tools/check/verilog_style.py rtl/cpu2/fpu rtl/tech/edrv32_apm_cpu2_*.v \
    fpga/rtl/edrv32_fpga_probe_cpu2_fma_top.v
verilator --lint-only -Wall -DSIM_MODE -Irtl/include rtl/cpu2/fpu/*.v \
    rtl/tech/edrv32_apm_cpu2_*.v fpga/rtl/edrv32_fpga_probe_cpu2_fma_top.v \
    --top-module edrv32_fpga_probe_cpu2_fma_top
python3 tools/regress.py smoke --path verif/unit/cpu2_fpu_fma32 -j 1
python3 tools/regress.py full --path verif/unit/cpu2_fpu_fma32 -j 1
python3 verif/unit/cpu2_fpu_fma32/levels.py
```

也可直接运行 `run.py smoke` / `run.py full`。smoke 为 131,120 个向量，
full 为 1,121,120 个向量（含固定种子的 1,000,000 个随机向量）。定向集包含
18 类编码三源笛卡尔积×四个 op×五种 rm，FV06 单次舍入反例、积先溢出再抵消、
精确消去、正常/非规格化边界、奇偶 tie、tie 邻点、正负下溢及特殊值。
随机同时覆盖原始位、接近指数、渐进下溢。所有向量每拍注入，满流水排空，
逐位检查结果和 5 位 flags；失败打印三源原始位、op、rm、期望与实际值。

`op_i` 是 RISC-V 四条 opcode 的 [3:2]：00 FMADD、01 FMSUB、10 FNMSUB、11 FNMADD。
`rm_i` 已解析且合法（000..100），此数据通路不负责指令非法编码检查。
E0 为调用者已捕获的输入；E1 是分类/LZ 的第一个采样沿，E8 输出本地结果，
相对 E0 共 8 拍；testbench 在采样 E1 后第七个后续沿检查 E8。

`levels.py` 使用 Yosys XC7 代理和仓库 `tools/synth/cpu_levels.py` 的图分析，
每个 LUT/MUXF 计 1 级，连续原生 carry 链计 2 级。APM 为寄存黑盒，
不测内部寄存路径；所有生成物在 `build/cpu2_fpu_fma32/`，不作物理时序结论。
