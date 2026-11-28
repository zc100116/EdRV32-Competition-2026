# CPU v2 单精度算术、转换与短操作（F02）

依据 `fpu-spec.md` v0.2 2.1–2.4、3.1、5.2–5.4 和 FV02/FV04–FV07/FV09/FV11/FV16。
`fma32` 实现 FADD/FSUB/FMUL 和四条融合指令；`convert` 实现四条 S/整数转换与
FMV.X.W/FMV.W.X；`short` 实现符号、最值、比较和分类。不涉及 D 算术或 S/D 精度转换。

单元只用 `FPU_FORMAT="F"/"FD"` 派生 3/4 位 tag，源和结果固定 32 位；无
`ISSUE_WIDTH` 相关电路。仅暴露实际使用的源端口。非法编码/舍入由上游译码处理；
boxing 检查和窄结果高 32 位填 1 由 fpu_top 处理。

## 结构与拍数

| 操作 | 无阻塞本体拍数 | 无冲突 II |
|---|---:|---:|
| ADD/SUB | 5 | 1 |
| MUL | 7 | 1 |
| 四条 FMA | 8 | 1 |
| 四条整数/S 转换 | 3 | 1 |
| 符号、两条搬移 | 1 | 1 |
| 比较、最值、分类 | 2 | 1 |

计数从三源已捕获的 E0 到本地结果：第一接受沿是 E1。testbench 在下一接受沿观察
本地响应时，用 `response_cycle-request_cycle` 检查上表数字，首先孤立执行各 opcode。
这些数字不包含分类级预约等待、skid 背压或完成竞争。

ADD 经过分类/次正规指数排序、带 GRS 的对齐、共享 add/LZA、粗规格化、细规格化/舍入。
MUL 经过分类、四拍 APM 链，绕过 add/LZA 后直接进入共享两拍尾端；FMA 在 APM 链的
同时完成加数对齐，再进入 add/LZA 和尾端。APM X/Y 直接捕获规格化输出，不增加同值 FF。
分类级按未来尾端入口拍预约，冲突时保留分类项；另有一项输入保持容量。

每个单元的两项完成 skid 保持结果/tag/flags/domain。skid 容量生成寄存的全链使能，
`resp_ready` 不组合连接到请求 ready 或流水使能。两条搬移和符号操作在尾端空闲时
直接进入 skid；若与已有结果相撞，则沿本单元流水保持，直到能够交付。
取消按 `(tag-age_head) mod N >= (cancel_tag-age_head) mod N` 包含边界清 valid，
覆盖输入保持、执行、尾端及 skid；在途 APM 数据可继续保留，但被取消的 valid 不会返回。

APM 技术包装的 `enable_i[5:0]` 是同一拍容量使能的六个物理副本：两颗 APM 各 13 个 CE
引脚，外部 24 位 X 延迟拆成 16+8 位，另有 8 位 Y 和 16 位 residue。六位必须同沿同值。

## 复现

先加载仓库工具环境。在仿真主机的独立工作目录运行，单次构建 `-j 1`：

```sh
python3 verif/unit/cpu2_fpu_fma32/run.py smoke --unit fma32
python3 verif/unit/cpu2_fpu_fma32/run.py full --unit fma32
python3 verif/unit/cpu2_fpu_fma32/run.py smoke --unit convert
python3 verif/unit/cpu2_fpu_fma32/run.py full --unit convert
python3 verif/unit/cpu2_fpu_fma32/run.py smoke --unit short
python3 verif/unit/cpu2_fpu_fma32/run.py full --unit short
```

也可通过 `tools/regress.py smoke/full --path verif/unit/cpu2_fpu_<单元> -j 1`。
每个 runner 都编译 F/FD 两个 tag 配置；每个配置先逐位检查全部输入，再重放带随机
背压、长 skid 停顿、包含边界取消、同沿接收/取消及 tag 环回的序列。

`model.py` 的精确 `Fraction` 参考只在 FMA 完整积加数之后舍入一次；
`unit_vectors.py` 为 ADD/MUL、转换、短操作增加精确有理数/原始编码参考，不用宿主浮点。
full 每单元至少 100 万随机向量，FMA 另含 20 万混合 opcode 序列。
`apm_tb.sv` 在 full 单独验证完整 48 位积、四个使能沿和随机暂停。

F05 SoftFloat/TestFloat Release3e smoke 向量通过公共包直接读取/比对：

```sh
python3 tools/fpu/build.py
python3 tools/fpu/generate.py --tier smoke --format F --output build/fpu/smoke-f
python3 tools/fpu/generate.py --tier smoke --format FD --output build/fpu/smoke-fd
python3 verif/unit/cpu2_fpu_fma32/run.py smoke --unit fma32 --softfloat-root build/fpu
python3 verif/unit/cpu2_fpu_fma32/run.py smoke --unit convert --softfloat-root build/fpu
python3 verif/unit/cpu2_fpu_fma32/run.py smoke --unit short --softfloat-root build/fpu
```

此适配器在 testbench 模拟 top 的 boxing 边界，然后只比较单元的低 32 位结果；
不把非法 boxing 的高字直接丢弃，不据此声称验证了尚未实现的 fpu_top RTL。
F05 smoke 生成器消费完整 level1 流后采样；本任务的 full 是上述有理数长随机，
不声称执行了 F05 巨大的未截断 TestFloat level2 全流。

```sh
python3 tools/check/verilog_style.py rtl/cpu2/fpu/edrv32_cpu2_fpu_fma32.v \
  rtl/cpu2/fpu/edrv32_cpu2_fpu_convert.v rtl/cpu2/fpu/edrv32_cpu2_fpu_short.v \
  rtl/tech/edrv32_apm_cpu2_u24xu24.v fpga/rtl/edrv32_fpga_probe_cpu2_fma_top.v
verilator --lint-only -Wall -DSIM_MODE -Irtl/include \
  rtl/cpu2/fpu/edrv32_cpu2_fpu_fma32.v rtl/cpu2/fpu/edrv32_cpu2_fpu_lz24.v \
  rtl/cpu2/fpu/edrv32_cpu2_fpu_lza32.v rtl/tech/edrv32_apm_cpu2_*.v \
  fpga/rtl/edrv32_fpga_probe_cpu2_fma_top.v --top-module edrv32_fpga_probe_cpu2_fma_top
python3 verif/unit/cpu2_fpu_fma32/levels.py
```

`levels.py` 用同一 Yosys XC7 代理比较旧探针提交
`8344727fcb67127837ab6c02679f81e512be006b` 与当前 RTL。APM 是寄存黑盒，
每个 LUT/MUXF 计一级、连续原生 carry 链计两级；不把该结果当作 PG2L200H 物理时序。
日志、网表与级数在 `build/cpu2_fpu_fma32/levels/{before,after}/` 和 `summary.json`。

## F02 验收与测量记录（2026-11-28）

RTL/参考/testbench 提交：`9b99a44cc`。本记录所在提交另将时序探针的寄存刺激扩展为
ADD/SUB/MUL/四 FMA，避免综合常量传播删除新旁路；`resp_ready` 来自寄存 LFSR 位，
请求源在 ready=0 时保持，取消固定 0，新增 `rst_n_i`。探针入口/观察出口均保留寄存器。

仿真使用 Verilator 5.051 devel，所有 F/FD 编译 `-Wall` 零告警。
本地 Verilator 5.020 lint（包括三个自检 TB 和更新后的 FPGA 探针）、风格及
`git diff --check` 均零告警/错误；没有本地 HDL 仿真。

| 单元 | 有理数/编码 smoke（每配置） | 长随机 full（每配置） | F05 smoke F / FD |
|---|---:|---:|---:|
| fma32 | 137,542 | 1,326,542 | 37,435 / 40,225 |
| convert | 17,206 | 1,007,206 | 1,452 / 2,134 |
| short | 13,258 | 1,003,258 | 8,007 / 8,534 |

表内每个数值向量在无取消序列中全部逐位比对通过；随后同文件的随机背压/取消重放也
通过。full 的完整 48 位 APM 积与四使能沿测试通过 100,013 次检查（含暂停沿保持）。
无阻塞本体延迟逐 opcode 断言通过：ADD/SUB=5、MUL=7、FMA=8、转换=3、比较/最值/
分类=2、符号/搬移=1。相撞的短结果被流水或 skid 保持，不把完成争用计作本体延迟。

最终日志保留于本地生成目录 `build/f02/`：`fma-current-rtl.log` 包含 FMA 两配置的
smoke/full 数值与协议重放及 APM 测试；`{short,convert}-{smoke,full}-final.log`
记录另两单元；`{fma,short,convert}-softfloat-final.log` 记录最新 F05 smoke。
仿真使用的独立临时目录在收回日志后清理。F05 向量生成/上游版本见 `tools/fpu/README.md`
和其记录的 Release3e 提交；本测试直接使用公共 `edrv32_fpu_vectors_pkg`。

### 资源与级数代理

工具：Yosys `0.70+219`（`5053d0e26`），XC7 技术映射，无物理器件/速度等级。
比较对象仅为 `edrv32_cpu2_fpu_fma32`：旧纯 FMA 探针与新 ADD/MUL/FMA 算术单元；
不包含 convert/short，也不包含探针刺激和观察 FF。配置为 F，APM 为两个寄存黑盒，
无 multicycle；实际器件的 165 MHz / 6.061 ns 约束留待 F06 PDS 重测。

| 指标 | 旧纯 FMA | 新算术单元 | 差值 |
|---|---:|---:|---:|
| XC7 LUT | 3,592 | 4,672 | +1,080 |
| XC7 FF | 1,044 | 1,489 | +445 |
| CARRY4 | 204 | 155 | −49 |
| APM 黑盒 | 2 | 2 | 0 |
| 固定舍入候选 | 48 | 3 | −45 |
| 最大代理级数 | 11 | 11 | 0 |

| 代理边界 | 旧 | 新 |
|---|---:|---:|
| E1 分类 | 9 | 9 |
| E2 准备 | 9 | 9 |
| E3 对齐准备 | 6 | 6 |
| E4 对齐 | 4 | 4 |
| E5 积/对齐 | 4 | 4 |
| 共享 add/LZA | 9 | 11 |
| 规格化 | 9 | 11 |
| 舍入/skid | 11 | 11 |

旧探针的 PG2L200H PDS 基线是卡 110 第三轮的约 179.2 MHz、3,111 LUT。
上述 XC7 数字不能与该 PDS LUT 数相减；本任务不声称 PG2L 净回收或新设计达到 165 MHz。
已回收重复舍入结构，但新增旁路/预约/本地保持后的代理 LUT 净增；按协调者确认的口径，
真实 PG2L LUT、FF、setup/hold、165 MHz 与控制扇出由 F06 在同器件/约束下定稿。

### 同沿控制副本

所有副本使用 `(* keep = "true", syn_preserve = 1 *)`，同沿计算/采样相同容量或分类
状态，没有级联寄存延迟。宽数据按不超过 16 位的固定片分配；同一数组/向量始终只有
一个 always 写入者，没有 generate 层次引用。

| 控制 | 区域根 | 叶 FF 副本 | 每叶负载估计 |
|---|---:|---:|---|
| fma32 全链使能 | 8 个容量根（16 个计数 FF） | 126 | ≤16 个 FF/宏 CE；APM 各 13 CE |
| fma32 ADD 入口选择 | 7 对分类根（14 个 FF） | 22 | ≤16 个数据选择位 |
| convert 使能 | 1 个容量根（2 个 FF） | 14 | ≤16 个 FF；含 FD tag 的末叶约 14 |
| short 使能 | 1 个容量根（2 个 FF） | 3 | ≤16 个 FF；含 FD tag 的末叶约 10 |

fma32 每个容量根分配 15/16 个叶副本；分类原状态加七份副本的分发根最多八路，
每个分类区域驱动 3/4 个入口叶。Yosys 可能合并同值寄存器，上述代理 FF/扇出不等价于
PDS 物理副本数；F06 必须检查 preserve 是否生效及根≤8/叶≤16 的实际负载。
