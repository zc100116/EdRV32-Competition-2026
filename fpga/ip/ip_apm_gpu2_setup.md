# GPU v2 setup APM 原语

本探针不需要在 IP Compiler 创建乘法 IP，`rtl/tech/edrv32_apm_gpu2_setup_*` 直接
例化 PDS 器件库 `GTP_APM_E2`，FPGA 工程器件必须为 PG2L200H；导入脚本定义 FPGA_MODE。
不得用通用 `*` 替代 FPGA 分支，PDS 项目保留默认 PG2L 原语库。

一条 signed49×signed33 乘法池使用6 APM，三条两 APM 短链并行；总延迟6拍、II1。
X 拆24/24/最高符号位，Y 拆无符号低16/有符号高17；链头 X/Y/MULT/P/CPO 注册，
MODEZ=0；链尾 MODEZ=5（CPI 算术右移16后相加）。其余参数/端口以包装原文为准。
高项操作数延迟1拍，低16余数延迟1拍，两 APM 的合成有效延迟4拍；
随后两级82bit外部加法树合并 X 的三个分块，低位完整保留。

PDS setup 顶层只含一条乘法池（6 APM），用于实测可复用原语；正式四池应为24 APM。
Windows 在 ModelSim 用 PDS 原语库运行 G-P03 同一向量，核对完整82bit积和6拍延迟；
PDS 回传6颗 APM 映射、CPI/CPO级联路径和每级时序。200/150MHz裕量分别为
`5.000ns - 最差路径需求`、`6.667ns - 最差路径需求`，220MHz约束为4.545ns。
