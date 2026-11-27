# GPU P-A 平面与 raster 存储精简

## 背景和问题

卡 107 的 CLM 占满，平面路径存在大量宽寄存器。gpu-spec v0.6
（`fd13f647d`）2.13.6a 已确认 P-A：先按 d 舍入，再按 SC∩TGT 的条带原点
重定位，最后按每个属性的 κ 舍入。此记录描述 R-6b 的实现决策。

## 约束

- 逐位实现 gpu-spec 2.13.6a、7、10–12、15；三角形 II=8、每周期两像素。
- P18 尾数流水保持原算术；宽度不超过 36 位的加法一段进位链完成。
- 器件目标仍为 PG2L200H-6/FBB676；clk_gpu 按 200 MHz 设计，180 MHz 目标、150 MHz 保底。
- 只在需要停顿的流水和需要保存状态的寄存器保留使能。
- PDS 不支持 generate 层次引用和 generate 内 wire 数组元素的切片。

## 可选方案

1. 只缩位宽：修改量小，但保留所有重复梯度和种子副本。
2. 缩位宽并把梯度保存在三角形槽 RAM：两个 lane 共用梯度，删除可由既有
   种子寄存器替代的副本；代价是每属性一片 64×72 分布式 RAM。
3. 全面重写扫描调度：可能进一步减寄存器，但会扩大 II、反馈与反压验证范围。

## 决策

采用方案 2。各属性顺序为 Z、q、uq、vq、R、G、B；W 从
[62,66,66,66,58,58,58] 改为 [32,42,42,42,32,32,32]，总和 434→254。
γ 的宽度 G 从 W−14 改为 W−10，总和 336→184。

raster 输入队列仍最多两项，梯度地址使用四个循环槽，分别容纳一个正在扫描和
最多两个等待的三角形；队列其他字段仍使用两个槽。弹出三角形时保存其梯度地址，
扫描与 lane 共用该地址的 γ；后续入队不覆盖正在使用的梯度。

下表为每个属性的显式数据寄存点，W/G 分别采用各版本定义；不计输出 RAM 和控制位。
加法器内部存储单独列出，避免重复计算。

| 寄存点 | 旧宽×份数 | 新宽×份数 | 处理 |
|---|---:|---:|---|
| 输入 σ/s 队列 | W×2 | W×2 | 缩宽 |
| 输入 gx/gy 队列 | G×4 | 0 | 一片梯度 RAM |
| 活跃 gx/gy | W×2 | 0 | 同一梯度 RAM 读取 |
| 起点 base | W×1 | W×1 | 缩宽 |
| 准备阶段有符号/移位梯度 | W×2 | W×2 | 缩宽 |
| seed_accumulator | W×1 | 0 | 初始化只有一个种子加法，直接用 base |
| row_accumulator | W×1 | 0 | 与 next_seed[0] 相同，直接复用 |
| row_seed | W×1 | W×1 | 保存当前行，供下一行准备使用 |
| 两行 next_seed | W×2 | W×2 | 缩宽 |
| prepare 的 CSA sum/carry | W×2 | W×2 | 缩宽 |
| plane 两相反馈值 | W×2 | W×2 | 缩宽 |
| plane 两拍原始值 | W×2 | W×2 | 缩宽 |
| lane 梯度延迟 | W×2 | G×2 | 只寄存有效 γ 位 |
| lane 0 基值对齐 | W×2 | W×2 | 缩宽 |
| 两 lane 输出对齐 | W×4 | W×4 | 缩宽 |
| 两拍加法器 | 6×(3W−34) | 4×(32 位各 2W；42 位各 3W−34) | 删除两路取负；32 位不切段 |

以上 RTL 位数公式的估算：旧 26ΣW+4ΣG+6Σ(3W−34)=19012 FF；
新 20ΣW+2ΣG+4(4×64+3×92)=7576 FF，毛省 11436 FF。
其中超出单纯缩宽的节省为 2956 FF（未计控制位缩短）。该值不含控制、覆盖、元数据和工具优化，
不是综合实测。

setup 和 perspective 的属性寄存点如下；同样按声明位数列出，不把重复符号位
优化当作保证，RAM 存储与 FF 分开计。

| 寄存点 | 旧宽×份数 | 新宽×份数 |
|---|---:|---:|
| setup 起点 assembly / 两输出槽 | ΣW×3 | ΣW×3，434→254 |
| setup 双梯度 assembly / 两输出槽 | ΣG×6 | ΣG×6，336→184 |
| setup h assembly / 两输出槽 | 10×7×3 | 不变，含 κ |
| setup 边 bias 两输出槽 | 40×3×2 | 1×3×2 |
| setup 原前端 delta / offset 副本 | 18×12 | 删除，复用新前端持有的顶点和差分 |
| setup 新前端顶点 / 差分 | 0 | 18×6 + 18×6 |
| setup 原始 / 裁后 bounds | 0 | 18×4 + 18×2 + 16×2 |
| perspective 输入属性两 lane×两槽 | ΣW×4 | ΣW×4，434→254 |
| perspective q/uq/vq 绝对值低/高段合计与结果 | 66×2×6 | 42×2×6 |
| perspective 绝对值符号/指数 | 1/10 位、两级、6 路 | 不变 |
| perspective Z/RGB 固定舍入和钳位 | 每 lane 92 位声明存储 | 删除 |
| perspective 新 Z/RGB 移位一级 | 0 | (49+4+1+1)×4×2 |
| perspective 新舍入输入/溢出/结果 | 0 | 每 lane (17+1+16)+3×(9+1+8) |
| perspective P18 后续算术与延迟 | 原规格宽度和份数 | 不变 |

P-A 新增共享寄存点：metadata 为 14×27；三路两级绝对值各为 2N+3 位
（N=72/52/52）；S′ 求和为 CSA 2×72 加两级进位 181 位；B 求和 181 位；
梯度比较为 52 位两拍加法器（122 位寄存）加 4 个比较标志。κ 路径的字节编码为
9×4、编码对齐 27+4、初值延迟 5×6、阈值 3×72、比较标志 3、κ 延迟 8×6。
三路舍入移位各保存 73×2+(N+1)+5 位（N=42/32/32），再各经过两拍舍入和
两拍符号恢复加法器。两个固定乘法包装各有 166 位错拍/残数寄存及 3 个 APM。
原始 s66、gx/gy52×2、绝对值72+52×2+符号3、B72、上下文460、重定位上下文37
分别放在 1/2/3/1/7/1 片 LUTRAM，跨流水不再各级复制这些字段。

内部指数接口继续使用七个有符号 10 位字段，语义由 h 改为 h+κ，协调者已同意。
perspective 始终按 (h+κ)−f+d 归一化；Z、RGB 同样使用该指数完成舍入和饱和。
Z/RGB 使用三级可变移位与舍入，其共享 shade RAM 延迟相应减少一拍。

模型的默认构造函数直接执行 P-A，renderer 传入 SC∩TGT。历史 v0.5 建立算术
只保存在 study_v03.py 的研究类中，study_precision.py 用它对比新默认实现；
运行时 GPU 不保留旧方案分支。

setup 的 P-A 采用两路共享 `edrv32_apm_gpu_s56xs18`，共新增 6 APM，每路
5 拍。包装没有外部 CPI 输入，无法把两路完整 74 位乘积和 S 直接接入同一个
现有后加器；因此求和复用 raster_prepare（CSA 一拍，两个 36 位进位段两拍）。
梯度符号扩展到 56 位，坐标差使用 18 位；完整 S′ 使用 72 位。

setup 前端在原始三角形包围盒与 SC∩TGT 间取交集，左/上界仍向 4×2 辅助
像素对齐，右/下界限制到交集。新增两拍分别保存原始 bounds/顶点/边差分和
裁剪后的 bounds，随后才计算边起点偏移；边函数在裁剪后的起点直接精确建立。
外部屏幕握手和内部面积发射各有一个 II=8 计数器，pending 从外部握手开始计数，
原始属性和规范平面上下文也在外部握手保存。输入顶点和差分一直保持到三条边
发射结束，因此删除旧 front_delta/front_offset 的 12 份 18 位副本，直接复用。非空扫描始终从条带原点的非负偏移
开始，所有有效步进与辅助像素均在 6a 的定宽保证范围内。

P-A 系数新增流水仍为 27 拍：乘法 5、S′ 求和 3、三路绝对值 2、B 求和 2、前导位/κ 初值
3、A·2^κ 阈值移位 3、阈值比较和 κ 修正 2、系数带保护位移位 3、舍入 2、
符号恢复 2。κ 使用与规格等价的阈值选择，不实例化除法器：先取
k₀=max(0,bit_length(B)−(W−1))，若 B>A·2^k₀ 则 κ=k₀+1，否则 κ=k₀。
B=0 时同样得到 κ=0。梯度绝对值的比较与两拍绝对值流水并行：同号时比较
两段原始系数，异号时取 gx+gy 的符号；避免在 B 加法前串联另一条进位链。三个系数各自按幅值最近舍入后恢复符号，保持两次舍入。

TGT 的合法尺寸使 g 只有 10、11 两值。原始梯度最多有符号 52 位，条带原点
与规范原点之差落在有符号 17 位内；两乘积与旧起点之和绝对值小于 2^70，
B<2^71，故采用 72 位中间存储，保守 κ≤42。q 的 h∈[−32,3]，uq/vq 的
h∈[−32,19]；加 κ 后均落在 [−32,61] 内。Z 为 h=−16、RGB 为 h=−8，
加 κ 后同样在有符号 10 位范围 [−512,511] 内，无指数截断。

原 setup 的 16 个三角形上下文在 II=8 时每 128 拍复用，不能等新增 27 拍后
再读。旧 plane 返回时即读取 edge、bounds、条带 origin、nonzero，并放进
7 片现有 64×72 LUTRAM 的同一条延迟；只保留 3×(value40+dx40+dy40+bias符号1)
+ bounds64 + origin32 + nonzero1 = 460 位。边 bias 在输出队列也只寄存符号，
恢复为 40 位 0/−1，额外省 234 FF。仍保留原 4 位 triangle tag，PA 内只延迟
attribute3、h10、g选择1 共 14 位元数据；系数和上下文跨深流水使用 RAM。
P-A 数据流水另外使用三个带 preserve 的 occupancy 使能副本，按存储量分为三组，
避免把整个新增流水挂在同一条高扇出 CE 上；valid/地址计数仍只受原 setup 停顿条件控制。

裁剪后的非空扫描偏移有界：x−ox≤1282，y−oy≤180，且均非负。
因此 raster 删除 negative_x/y 和两路宽取负加法器，x/y 偏移只存 11/8 位，
起点准备只迭代 11 位。SIGN 状态只需一拍读取共享 γ；prepare 的每次加法仍保留
原三拍，像素发布和反馈流水不变。wait/row_wait 缩为 2 位，bit 索引缩为 4 位。
这项收敛依赖 setup 已执行的交集裁剪，不增加负偏移备用路径。

## 影响

setup、raster、perspective 及 GPU 内部连接；模型和单元向量的平面打包格式相应变化。
fragment_plane 由两 lane 的 868 位改为 508 位；setup_start 434→254 位，
setup_gradient 672→368 位。SoC 接口不受此内部格式变化影响。

## 测量与验证

Yosys 0.70+219（5053d0e26），ABC `strash; if -K 6` 通用映射，各模块分别作
顶层、递归计数，RAM/ROM 包装 blackbox，SIM 乘法模型保留。因此 FF/LUT6 包括
原生 APM 包装内部的仿真寄存器和乘法逻辑，不能直接当成 PDS 物理 CLM 数字；
LUTRAM 包装内部资源不计入。原始脚本、JSON、日志在 `build/r6b/`。

| 模块 | fd13f647d FF / LUT6 | R-6a 后 cffb4041d | R-6b 后 | R-6b FF 变化 |
|---|---:|---:|---:|---:|
| setup | 26009 / 42896 | 26793 / 52976 | 29164 / 62377 | +2371 |
| raster | 23041 / 20684 | 23041 / 20684 | 11713 / 10652 | −11328 |
| perspective | 13058 / 17441 | 13058 / 17441 | 12572 / 17460 | −486 |
| 合计 | 62108 / 81021 | 62892 / 91101 | 53449 / 90489 | −9443 |

R-6b 相对 R-6a 后净减 9443 FF，LUT6 减 612；相对 fd13f647d 总计减 8659 FF。
setup 的显式 APM 从 34 增至 40；剔除 head/shift 原语内部的 CLM 代理为
22383 FF / 16920 LUT6 → 23976 FF / 20001 LUT6。RAM table 数 setup 41→56，
raster 2→9，perspective 20 不变；raster read_pool 4→3。
新增 κ 缩放导致 perspective 的毛省与净省不同，已计入上表。

setup 粗网表递归 FF 使能负载：原 enable 为 35，六个 control_enable 副本为
[1317,363,156,1030,1456,1286]；映射后对应输入引脚负载为 45 和
[1333,368,165,1029,1407,1163]，均小于 2000；新增 screen_accept 的引脚负载为 280。这是 Yosys 参考负载，PDS
实际布线扇出和 clk_gpu 时序仍需后续确认。

复现资源：用 `git archive` 导出上述基线的 `rtl/`，展开各自 gpu.f，定义 SIM_MODE，
加入对应 `rtl/include`。对 setup/raster/perspective 分别执行：

```text
read_verilog -defer -D SIM_MODE -Irtl/include <gpu.f 全部源文件>
blackbox edrv32_ram_gpu_* edrv32_rom_gpu_*
hierarchy -top edrv32_gpu_<模块>
blackbox edrv32_ram_gpu_* edrv32_rom_gpu_*
synth -top edrv32_gpu_<模块> -noabc -noalumacc -run begin:fine
write_json <粗网表>.json
synth -top edrv32_gpu_<模块> -noabc -run fine:check
abc -lut 6 -script <两行 strash / if -K 6 的脚本>
write_json <映射网表>.json
```

递归计数叶单元 type 含 DFF 的个数与 `$lut` 个数；APM CLM 代理跳过
head/shift8/shift16/shift24 原语内部。该方法与 R-6a 记录一致。

模型 `python3 tools/gpu/model/selftest.py` 全部通过（50.905 s），包括新增的
面积一、非零条带原点和 γ/累加器定宽测试。
`python3 tools/gpu/model/study_precision.py --part synthetic` 通过（269.126 s）：
786556 个共同像素与 v0.5 的覆盖、UV、Z、RGB、LOD、过滤结果全部相同。
同命令 part 换成 canyon/world/world-dusk/rogue-slash，四帧新默认模型的完整
DDR 与研究工具内隔离的 v0.5 基线逐位相同。沿用 M-3 已导出的输入，不修改 PC
模拟器；原始结果与日志在 `build/gpu/precision/{<帧>.json,r6b-<帧>.log}`。

风格命令 `python3 tools/check/verilog_style.py` 对所检查的 14 个 RTL 文件为零告警。
GPU 顶层 lint：在 `rtl/filelists/` 执行
`verilator --lint-only -Wall -DSIM_MODE --top-module edrv32_gpu -f gpu.f`，零告警。

最终 18 个 GPU 单元全部通过；setup 在裁剪前端/副本收敛后另行复跑通过，
raster 在删除取负和缩短起点准备后作为最终 18 项回归的首项运行，四个模式全通过。
GT-01～24 全部通过；GT-01～06 也在最后一轮 raster 收敛后补跑通过。
GT-18/19 使用既有的字典 union 语法，默认 EDA Python 3.8 在生成场景时失败；
固定系统 Python 3.9.25 后重跑通过，未修改场景测试代码。PATH 将 `/usr/bin`
放在 EDA Python 前，保证 runner 子进程使用同一解释器，GT-25 也采用此设置。
单元完整日志和最终摘要在 `build/r6b/regression/unit/`、`build/r6b/units.log`；
GT 原始摘要在 `build/r6b/gt-full.log` 和 `gt-final-recheck.log`。

复现单元：逐目录执行 `python3 tools/regress.py full --path verif/unit/gpu_<模块> -j 1`；
GT：固定上述 PATH 后执行 `python3 tools/regress.py full --path verif/block/gpu -j 1`，
再执行 `python3 tools/regress.py perf --path verif/block/gpu/gt25 -j 1`。
仿真使用 Verilator 5.051 devel（v5.050-99-gf8fb1d664）和 Icarus；clk_gpu=180 MHz
及各 GT 所要求的额外时钟档，默认 DDR 延迟，不并行运行共享构建目录的测试。

GT-25 性能回归通过（126 s）。与 `fd13f647d` 对比共 124 条命令：110 条周期
不变，14 条改变；差值范围 −530664～+165。全部变化如下，其余命令的差值均为 0。
此处是最终 R-6a+R-6b 的集成结果，不将每一项差异单独归因于某个子改动。

| 工作负载 / 命令 | 类型 | fd13f647d | 74a1a5674 | 差值 |
|---|---|---:|---:|---:|
| nearest / 12 | DRAW_TRI | 8686 | 8692 | +6 |
| nearest / 13 | RESOLVE | 39907 | 39901 | -6 |
| bilinear / 11 | DRAW_TRI | 58093 | 58099 | +6 |
| bilinear / 12 | RESOLVE | 40063 | 40057 | -6 |
| trilinear / 11 | DRAW_TRI | 75472 | 75481 | +9 |
| trilinear / 12 | RESOLVE | 39946 | 39937 | -9 |
| palette_i4 / 12 | DRAW_TRI | 58354 | 58360 | +6 |
| palette_i4 / 13 | RESOLVE | 40048 | 40213 | +165 |
| palette_i8 / 12 | DRAW_TRI | 58360 | 58366 | +6 |
| palette_i8 / 13 | RESOLVE | 40162 | 40156 | -6 |
| vertex / 11 | DRAW_TRI | 3049 | 3052 | +3 |
| vertex / 12 | RESOLVE | 39988 | 39985 | -3 |
| setup / 11 | DRAW_TRI | 543901 | 13237 | -530664 |
| setup / 12 | RESOLVE | 40135 | 40039 | -96 |

quad 的载荷命令仍为 16618 周期，objects 为 74695；AA RESOLVE 的两次测量合计
仍为 80048 周期（0.444711 ms @180 MHz），满足 90000 周期上限。三角形 setup
工作负载下降对应裁剪屏外扫描与缩短起点准备；普通载荷 DRAW_TRI 增加 3～9 周期。
palette_i4 的后续 RESOLVE 增加 165 周期，已如实保留，不作为画面结果差异。

完整逐命令表为 `build/r6b/gt25-cycles.csv`；两版 timing.txt、commands.bin、
performance.txt、expected.regs.json 与 runs.json 在
`build/r6b/gt25-baseline/`、`build/r6b/gt25-current/`，原始日志为
`build/r6b/gt25.log`，汇总为 `build/r6b/gt25-cycle-summary.log`。
逐行周期为 timing.txt 第 4 列减第 3 列，以工作负载和命令序号对齐。
基线从 `git archive fd13f647d` 导出 rtl/tools/verif/fpga/ip 后运行同一 GT-25 runner；
必须同步该 commit 的倒数 ROM 数据。GT 期望 DDR 均由各自默认模型经现有 runner
重新生成，不修改场景或放宽比较。

实现与全部验证的代码提交为 `74a1a5674`；本文资源表对应这一提交。


## 状态

**已决定。** 实现、最终集成回归、模型逐位比较与资源参考测量均已完成；PDS 物理时序/资源确认属于后续任务。
