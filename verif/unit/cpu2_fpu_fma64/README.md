# F04：FPU 剩余数据通路验收

源码提交：fma64/APM/探针 `5203721ad`，convert `d4c62bb31`，short `06150ff00`，
FP RF `4bbb4d2eb`。依据 fpu-spec v0.2、接口冻结记录及本 Dispatch 的协调者补充授权；
本目录与 ISSUE_WIDTH 无关。FPU top 只在 FD 实例化 fma64，convert/short 按 FPU_FORMAT
导出 B/T，F 保持 32 位，FD 为 64 位，S 的 boxing 检查仍由 top 执行。

## 结构与实际拍数

| 操作 | 无阻塞本体延迟 | 路径 |
|---|---:|---|
| ADD.D / SUB.D | 7 | 分类、对齐、两拍 84 位分片加减、三拍尾端 |
| MUL.D | 18 | 分类、14 拍 APM、三拍尾端，绕过加法级 |
| 四种 FMA.D | 20 | 分类、14 拍 APM、两拍分片加减、三拍尾端 |
| S/D 整数与精度转换 | 3 | 两级准备、舍入/完成；原 S 位搬移无冲突时 1 拍 |
| S/D 比较、最值、分类 | 2 | 计算/寄存、完成 |
| S/D 符号注入 | 1 | 无冲突时直接进入完成 skid |

延迟从全部源已捕获后的请求接受到本地结果可用，不含 FD 的 rs3 额外捕获或完成背压。
F03 需要回填 D ADD=7、D 转换=3；D MUL/FMA 与 18/20 初值一致。
算术流水每个使能沿推进；ADD/MUL/FMA 预约同一个尾端入口沿，尾端长三拍不等于 II3。
分类/输入缓冲与两项完成 skid 保持请求和结果，取消按队头相对年龄包含边界。

乘法器按 `(24+24+5)×(16+16+16+5)` 使用 12 个 APM，保留完整 106 位积。
位权 `0,16,24,32,40,48,48,56,64,72,80,96`，e=48 第二项使用 MODEZ=3 直通 CPI；
其余差为 8/16。首项直接使用 APM X/Y 内部寄存，其余项复用紧凑的分段输入错拍链。
C 在乘积等待期间保持 53 位，最后两级完成宽对齐；舍入下限标记与指数控制提前准备，
LZA 与两拍分片加减并行，只有尾端做最终舍入。取消年龄比较不串入 MUL 数据选择。

743 个同沿流水使能叶按 47 个容量区域分配，每组最多 16 个叶；7 个完成 valid 根
每根服务最多 7 个容量区域，容量计数在各区域独立更新。APM 包装占其中 124 个使能叶。
数据寄存器每个 CE 叶最多 16 位；ADD 选择使用 8 组分类副本和 47 个选择叶，MUL
选择使用 7 个根和 28 个叶。向量/数组均只有一个 always 写入点，不使用 generate 层次引用。

FP RF 使用 32×B、F 三份/FD 两份异步读副本和单个提交写口，FD 每份高低字分别实例化
`edrv32_ram_cpu2_rf`；f0 可写，WB 寄存值显式转发。FD 第三组配置端口按协调者确认驱动 0，
不产生第三份存储。按本任务补充授权不另写 RF 单元测试，架构依赖留给 F07 核级覆盖。

## 数值与协议结果

工具：Verilator 5.020（Debian 5.020-1）、Python 3.12.3；F05 参考为仓库记录的
SoftFloat/TestFloat Release3e，版本与生成条件见 `tools/fpu/README.md`。
仿真主机连接超时/复用连接断开后按任务约定在本地统一锁下串行执行；远端临时目录已清理。

| 单元/向量 | F 数值检查数 | FD 数值检查数 |
|---|---:|---:|
| fma64 有理数 smoke | — | 19,167 |
| fma64 有理数 full | — | 1,009,167 |
| fma64 F05 smoke | — | 33,695 |
| convert 原 F 有理数/编码 smoke | 17,206 | — |
| convert F05 smoke，含全部 D 与 S/D 转换 | 1,452 | 3,923 |
| short 原 F 编码 smoke | 13,258 | — |
| short F05 smoke，含全部 D 短指令 | 8,007 | 12,753 |

全部逐位结果和每条 flags 一致。FMA full 无背压序列 1,492,806 周期；相同 full
向量的背压/取消/tag 环回序列 2,089,386 周期，检查 893,624 个未取消结果。
convert/short 的 F、FD SoftFloat 文件也分别通过背压、取消、tag 环回重放。
最终容量/使能分区后再次用现有 full 文件及 F05 smoke 验证，结果与周期数一致。
无阻塞 FMA 的三种本体延迟在 testbench 的隔离前缀逐 opcode 断言。

APM 独立测试在 20,000 个时钟周期中推进 16,130 个使能沿；每项的部分和均对照
外部输入独立计算的期望值，包含两项 e=48、全 1 最大操作数及暂停沿，完整 106 位积通过。
FMA full 中还逐条验证所有随机乘积参与最终舍入的效果。
本单元 full 是一百万条有理数随机及定向流，不冒称未截断 TestFloat level2 全流。

复现（先按 `tools/fpu/README.md` 准备 `build/fpu/smoke-f` 与 `smoke-fd`）：

```sh
. ~/.local/opt/edrv32/env.sh
flock /tmp/edrv32-sim.lock python3 verif/unit/cpu2_fpu_fma64/run.py smoke --softfloat-root build/fpu
flock /tmp/edrv32-sim.lock python3 verif/unit/cpu2_fpu_fma64/run.py full
flock /tmp/edrv32-sim.lock python3 verif/unit/cpu2_fpu_convert/run.py smoke
flock /tmp/edrv32-sim.lock python3 verif/unit/cpu2_fpu_short/run.py smoke
flock /tmp/edrv32-sim.lock python3 verif/unit/cpu2_fpu_fma64/levels.py
flock /tmp/edrv32-sim.lock verilator --lint-only -Wall -DSIM_MODE \
    --top-module edrv32_fpga_probe_cpu2_fma64_top -F rtl/filelists/cpu2_probe_fma64.f
```

最后八种 lint 配置（convert/short/RF 的 F/FD、fma64、D 探针）零告警，九个所改 RTL
文件风格检查零告警。生成日志位于 `build/f04/`：`smoke-final.log`、`full-final.log`、
`control-final.log`、`convert.log`、`short.log`、`lint-final.log`、`levels-final.log`；
资源网表和完整摘要为 `build/cpu2_fpu_fma64/levels/{xc7.json,summary.json,synth.log}`。

## XC7 资源与级数代理

工具 Yosys 0.70+219（5053d0e26），`synth_xilinx -family xc7 -flatten -noiopad
-noclkbuf -nobram -nosrl`；只有 fma64 本体，不包含探针、S 单元、convert/short 或 RF。
12 个 APM 作为时钟黑盒，内部 X/Y/MULT/P/CPO 不映射成 LUT，不另计为 CLM FF。
无物理器件、速度等级或 PDS 时序结果；探针约束为 165 MHz / 6.061 ns。

| 指标 | 数值 |
|---|---:|
| XC7 LUT2–LUT6 合计 | 12,383 |
| XC7 FF 合计 | 5,784 |
| CARRY4 | 251 |
| 独立 INV 代理 | 113 |
| APM 黑盒 | 12 |
| 最大 FF→FF 代理级数 | 12 |
| 最大 APM→FF 代理级数 | 11 |
| 最大顶层输入→FF 代理级数 | 12 |

| 边界 | 最大代理级数 |
|---|---:|
| 分类 | 12 |
| 乘积指数准备 p0/p1/p2/p3 | 6 / 3 / 3 / 6 |
| 舍入下限准备 p4/p5 | 2 / 5 |
| C 对齐 p11/p12/p13 | 4 / 10 / 1 |
| ADD 对齐 | 12 |
| 加减低半/LZA、加减高半 | 11 / 6 |
| 尾端粗移/细移/舍入-skid | 12 / 6 / 11 |

代理对一整条连续 carry 链按两级计数，与 F02 的统计口径一致。初版代理最长 23 级，
通过指数准备分拍、下限标记提前准备、取消与数据选择分离和同沿控制副本降至 12 级。
Yosys 可能合并同值控制寄存器；路径中仍可出现高扇出网络，不能用代理网表证明 PDS
物理根≤8/叶≤16。F06 必须检查 preserve、副本物理分布、12 颗专用级联、原语等价、
setup/hold 和实际 LUT/FF；本报告不声称 D 探针已达到 165 MHz。
