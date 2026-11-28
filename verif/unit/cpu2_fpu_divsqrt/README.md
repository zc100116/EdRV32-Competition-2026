# F03 / FV08：独立 S/D 除法与开方

实现与本报告在同一提交；复现提交由
`git log -1 --format=%H -- rtl/cpu2/fpu/edrv32_cpu2_fpu_divsqrt.v` 确定。规格为 fpu-spec v0.2
2.2、3.1、5.2–5.4，接口按冻结记录及协调者对未用源的确认：无 src3/int_src，
FD 的 S 源 boxing 检查及结果 boxing 在 fpu_top 完成，单元返回低 32 位数值、高位 0。
本模块与 ISSUE_WIDTH 无关，只验证 FPU_FORMAT=F/FD。

`edrv32_cpu2_fpu_divsqrt` 只有一个入口及一个本地完成槽；F 始终只实例化 S，
FD 额外实例化独立 D 数据通路。数值核心采用基 4 restoring digit recurrence，
每轮产生两位商/根：三路并行试减选择 0–3，SQRT 的第三试数随根独立递推，
四个下一试数在本轮试减旁并行计算。S 使用已有 lz24，D 使用固定 lz53 平衡树。
余数、子规格化移出位参与 sticky，舍入只进行一次，tininess 在舍入后判断。
保持使能按至多 16 位分区、预先注册并保留区域副本；数据寄存器不复位。
SQRT 模式采用 P2 两个区域根、P3 每 16 位叶副本，根至多八个叶，
准备余数与结果选择器也分别复制。移位量用三级区域复制，根至多七个叶，
低/高移位按八位区域实现；sticky 用 16 位并行归约及第二拍最终归约。

## 复现

在已装好 Verilator 5、Yosys、Python 3.9+ 的仿真环境，仓库根目录执行：

```sh
python3 tools/check/verilog_style.py rtl/cpu2/fpu/edrv32_cpu2_fpu_divsqrt*.v \
    rtl/cpu2/fpu/edrv32_cpu2_fpu_lz53.v
verilator --lint-only --language 1364-2001 -Wall \
    --top-module edrv32_cpu2_fpu_divsqrt \
    rtl/cpu2/fpu/edrv32_cpu2_fpu_divsqrt*.v rtl/cpu2/fpu/edrv32_cpu2_fpu_lz24.v \
    rtl/cpu2/fpu/edrv32_cpu2_fpu_lz53.v
verilator --lint-only --language 1364-2001 -Wall -GFPU_FORMAT=17988 \
    --top-module edrv32_cpu2_fpu_divsqrt \
    rtl/cpu2/fpu/edrv32_cpu2_fpu_divsqrt*.v rtl/cpu2/fpu/edrv32_cpu2_fpu_lz24.v \
    rtl/cpu2/fpu/edrv32_cpu2_fpu_lz53.v
python3 tools/regress.py smoke --path verif/unit/cpu2_fpu_divsqrt -j 1
python3 tools/regress.py full --path verif/unit/cpu2_fpu_divsqrt -j 1
python3 verif/unit/cpu2_fpu_divsqrt/levels.py
```

`run.py smoke/full` 也可直接运行。参考只用标准库 `fractions.Fraction`、大整数
及 `math.isqrt`；除法直接按精确有理数舍入，开方用平方后的精确中点比较，
不使用宿主浮点或 DUT 内部信号。固定 seed 为 `0xF03+width`（S=3875、D=3907）。
定向包含正负零、sNaN/qNaN、无穷、最小/最大 subnormal、最小 normal、
最大有限数、邻 ULP/余数边界，全部交叉五种舍入。
随机覆盖原始编码及边界操作数，smoke 每精度 2000 条、full 每精度 200000 条。

除逐位结果与 flags 外，testbench 检查接受后源/指令/rm 立即改变、局部忙、
完成背压、tag 环回、相对 head 跨环年龄比较、取消等于/早于/晚于本项的边界、
接受同沿及每个执行/完成/保持阶段取消、执行中与完成后复位，以及持续请求的 II。
三组配置合计 543 个取消场景；每条算术结果均在实际响应端比对。

## 实测延迟

以请求握手采样沿为 P1；下表的本体延迟从调用者输入已捕获的 E0 起计，
即 P1 算第 1 拍。请求握手沿到结果 valid 沿的间隔为下表本体延迟减一。
所有特殊值也走相同固定日程，无背压时结果出现周期不依赖操作数。

| 精度/操作 | 准备 | 基 4 迭代 | 尾端 | 本体延迟 | 连续接受 II |
|---|---:|---:|---:|---:|---:|
| S DIV | 3 | 13 | 6 | 22 | 23 |
| S SQRT | 3 | 14 | 6 | 23 | 24 |
| D DIV | 3 | 27 | 6 | 36 | 37 |
| D SQRT | 3 | 28 | 6 | 37 | 38 |

准备分别为分类/LZ、规格化及指数调整、初始余数/分母/指数选择；
DIV 的固定首位 1 及首次减分母在准备末拍完成，随后只迭代其余基 4 数字。
尾端分别为渐进下溢对齐低三位移位、高位移位、舍入、进位规格化、指数编码、打包。
下溢移位量及其掩码在迭代期间预计算，不延长尾端。
初始 19/35 规划值增加的拍数来自真实准备、S 尾端及下溢移位切拍；II 另含完成握手
释放入口的一个周期，ready 仅依赖登记容量，不组合依赖 resp_ready。
DIV II 由持续请求直接量测；SQRT II 为已核对的结果出现拍加一次完成释放拍。
背压延长占用；取消同沿优先清所有权与本地完成 valid/flags，下一拍可复用 tag。

## 验收结果

Verilator 5.051：smoke 回归含 F/FD 单线程编译耗时 43 秒，长随机回归耗时 53 秒。
smoke F 的 S 7930 条、FD 的 S/D 各 7930 条；
full F 的 S 205930 条、FD 的 S/D 各 205930 条，全部逐位结果与 flags 一致。
smoke 共 23790、长随机 full 共 617790 条（full 档另重跑 smoke）；严格 Verilog-2001 `-Wall` 两配置及风格检查零告警。
日志在 `build/regress/{smoke,full}/unit/cpu2_fpu_divsqrt/`。

Yosys 0.67+94 XC7 代理由 `levels.py` 复现，连续 carry 链计两级，LUT/MUXF 各计一级，
原始网表、阶段统计及综合日志在 `build/cpu2_fpu_divsqrt/levels/`。
该代理不包含 Pango 物理布线，165 MHz、区域复制后的真实扇出和资源仍需 PDS 确认。
协调者需据上述实际延迟/II 更新 F03 及周期模型。

| 代理阶段（连续 carry 链计两级） | S | D |
|---|---:|---:|
| 准备：分类/LZ | 6 | 8 |
| 准备：规格化 | 4 | 6 |
| 准备：初始指数/余数 | 7 | 7 |
| 迭代反馈 | 8 | 8 |
| 尾端：低移位/sticky 分组 | 5 | 4 |
| 尾端：高移位/sticky 合并 | 2 | 3 |
| 尾端：舍入 | 6 | 6 |
| 尾端：规格化/编码/打包 | 3/4/2 | 3/3/2 |

代理的八级迭代反馈包含原生 carry 链；该数字不能直接换成 Pango 逻辑级或 MHz。
共享模式控制已分区复制，组合 digit 选择等路径的真实布线/扇出仍需 PDS 检查。
