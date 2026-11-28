# GPU v2 FP32 probe

依据 gpu-v2-spec v0.1 §2.4、VT04 与 G-P01。四个原生 lane 共用八颗 APM；每 lane
独立完整48bit积。MUL/FMA 返回12拍，DP3/DP4 返回13拍，均按第一采样边沿计第1拍。
无背压时连续每拍接收；两个返回端口分别对应 vec4 和独立 DP 树，后续 RF 写口预约
由顶点调度器负责。两个队列共享16个在途信用，不改变计算延迟。

独立参考 `tools/gpu2/fp32.py` 使用整数尾数和二进制指数、显式最近偶数舍入；不读
RTL 内部状态，不依赖 Python 双精度替代 FP32。覆盖非正规数、抵消、正负零、NaN/Inf
的 IEEE 开发初值；这些特殊值核对列为 G2-07 待定，不能记为规格验收 PASS。
DP 抵消样本 `(1+2^-23,1,0)·(1-2^-23,-1,0)` 必须为0；相同 FMA 为 `a8800000`。
原始全位随机、边界值、四 opcode 交错、DP3 未用第四项 NaN、两个返回端口合法
背压/保持、最初256拍 II1 和无背压返回12/13拍均由公开端口检查。

```sh
python3 tools/regress.py smoke --path verif/unit/gpu2_fp32 -j 1
python3 tools/regress.py full --path verif/unit/gpu2_fp32 -j 1
python3 tools/gpu2/synth.py edrv32_gpu2_fp32
python3 tools/gpu2/synth_summary.py build/gpu2_synth/edrv32_gpu2_fp32.json
```

smoke 是10001条 scalar/MUL/add 检查加2048条 vec4/DP 请求；full 子目录追加
200001条 scalar/MUL/add 和100000条 vec4/DP。参考构建不综合 APM/LUTRAM内部，
外部 APM 对齐/残数寄存器每 lane48 FF另计。LUTRAM五份16×32共80 LR。
`ltp -noff` 会穿越 APM 黑盒；以 `synth_summary.py` 切开宏边界的级数为准。
LUT4 映射没有 Pango 进位链，不能作为 PDS 时序或220/200/150MHz达标证明。

在 `74fe746d2` 的数据通路上，Yosys0.67+94、abc -lut4 参考为14421 LUT4 /
4594外部FF /8 APM /0 DRM（另80 LR分配额）；含LFSR/折叠的FPGA顶层为14664 LUT4 /
5042外部FF，APM/DRM/LR不变。最长宏边界间路径38 LUT4：s6_c_r→s7_reverse_r，
这是未映射Pango进位链的通用逻辑参考。相对77bit版本省1563 LUT4/40 FF，保持12/13拍。
