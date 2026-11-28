# GPU v2 原型探针

依据：gpu-v2-spec v0.1、gpu-v2-plan G-P03/G-P04、M-9准则与M-8/M-6算术。

## setup/存储探针

背景与约束：验证完整积/source48/整数重定位，以及C12和72个独立bank的真实存储成本。
实现提交由 `git log -1 --format=%H -- rtl/gpu2/edrv32_gpu2_setup_probe.v` 定位；本节随实现提交。
只做独立运算/地址端口；不定义G-R04字段、DAG银行仲裁，不把探针吞吐当整套setup吞吐。
方案与决策：49×33采用三条两APM短级联，保留低16残数，两级82bit树合并，裸6拍/II1；
加1拍同步取数为M-8的7拍。FPGA为gpu2专用GTP_APM_E2包装，未用LUT乘法替代APM。
N48裸2拍：幅值/前导零移位、舍入/进位再规格化；加同步取数1拍严格对应M-8的3拍。
首级不另打幅值寄存，避免多拍；控制有效2bit，数据118bit，不重计已有RAM读寄存。
重定位按获批1280×720初值：x五位/y四位非负tile偏移，九条件移位项加S；
九个60bit加法器、四级寄存、II1；比M-8的640×360估算多两个加法器/一拍，不加APM。
每级寄存只切对应加法路径；无整属性记录延迟链、数据复位、等待状态或降级路径。
C12行宽核实：64+12×8=160有效位；五片1024×36拼180，20位空置，旧96位不适用。
RF三副本512×128共6 DRM，常量两副本共4 DRM，program共5 DRM；SDP72几何复用。
M-7 `tools/gpu/study/m7_model.py:110` 明确scratch每bank深度16，M-8保留此形状并扩为72bank。
因此对照72×16×92 LUTRAM与72×两颗512×72 DRM；均1拍RAM读+1拍外捕获，禁读保持。
同址行为模型返回旧字；实际PDS IP/原语同址与延迟必须由Windows ModelSim同向量核实。

| Yosys LUT4参考；APM/RAM黑盒 | LUT4 | 外部FF | DRM/APM/LUTRAM实例 | ltp级数 |
|---|---:|---:|---|---:|
| 裸N48 | 799 | 120 | 0/0/0 | 45 |
| 裸重定位 | 1371 | 612 | 0/0/0 | 35 |
| 裸49×33 | 201 | 312 | 0/6/0 | 33 |
| setup探针含激励/观察 | 2262 | 1291 | 0/6/0 | 46 |
| banks DRM探针含激励/观察 | 2703 | 15352 | 159/0/0 | 5 |
| banks LUTRAM探针含激励/观察 | 2703 | 21976 | 15/0/72 | 5 |

按寄存器D端计LUT级数：N48两拍45/44；乘积合并31/32；重定位四拍35/35/35/35。
通用LUT4未映射Pango进位链，不能当作PDS级数；N48首级很深，220MHz时序存在风险。
LUTRAM版省144 DRM、增6624读捕获FF及105984存储bit；黑盒不含LUTRAM内部LUT/CLMS。
scratch的144 DRM占规格性能档219 DRM估算约65.8%；需PDS比较CLMS与时序后选型。
单池6 APM，正式四池24 APM；单运算探针未实现完整四池/三宽三窄/九在途，不能冒称整套预算达标。
验证：39三角形/780整数边界恒等式、3458逐位向量；3072拍bank trace、60872同址碰撞，
每映射236339次比较；覆盖连续最坏读写、不同地址并发、禁读保持，smoke/full各通过。
复现：`python3 tools/regress.py smoke --path verif/unit/gpu2_setup -j 1`，banks同命令改目录；
full替换smoke；`python3 tools/gpu2/measure_probes.py`生成各寄存器级数及LUT4/FF/IP参考。
Verilator 5.051 --lint-only -Wall三顶层零告警；风格14文件零告警，PDS限制静态扫描零违例。
Yosys 0.67+94；日志在`build/gpu2/yosys/`，回归日志回收到`build/gpu2/regress/`，均不入库。
状态：RTL逐位通过且N48不多拍；PDS 220MHz约束已提供，220/200/150MHz裕量、
真实DRM/LUTRAM/CLMS占用均未取得，IP创建说明含Windows核对步骤，不写作实测达标。

## 算术探针

依据：gpu-v2-spec v0.1 §2.4、M-8/M-6；G-P01 实现提交 `74fe746d2`（前置 `f674bc3e7`）；SFU数值阶段 `1fd8fefa7`。
FP32 原生4lane、八颗APM；每 lane 保留完整48bit积，DP3第四积固定+0，独立三加法器平衡树。
每 lane 第1拍捕获尾数/前导零，第2–5拍两APM级联；7拍舍入乘积旁路供 DP 使用。
FMA 第2拍选公共指数，3/4拍分级对齐C，5拍等APM，6拍对齐乘积，7拍56bit正反加减；
第8拍前导零/指数，第9拍规格化/GRS，第10拍RNE+pack，第11拍对齐，第12拍写返回队列。
56bit 保留完整48bit积及7个低保护位；抵消时保留全部积位；比77bit实现省1563 LUT4/40 FF。
DP 第7拍乘积舍入，第8–10拍两对独立加法，第11–13拍最终独立加法；最后pack直接写队列。
两个返回端口分别是vec4和DP；都支持合法背压，总信用16；无背压II1，12/13拍检查通过。
第11拍按已确认的vec4 12拍返回预约对齐；数据通路无全局stall/ready组合使能；五个队列写使能来自注册valid，ready为注册信用状态。
新增第6拍乘积/C寄存切开移位与进位链；合并末拍舍入/pack，未增加算术拍数。
队列是背压所需五份16×32 LUTRAM（80 LR分配额），不用DRM；FPGA端需生成 `ip_ram_gpu2_queue`。
APM 用gpu2独立tech包装；head MODEZ=0、tail CPI>>>16，X/Y/MULT/P/CPO全寄存，裸积4拍。

| Yosys LUT4参考，不含APM内部/队列内部 | LUT4 | 外部FF | APM/DRM/LR | 最长级数 |
|---|---:|---:|---|---:|
| vec4+独立DP+返回队列控制 | 14421 | 4594 | 8/0/80 | 38 |
| 含LFSR/输出折叠的FPGA顶层 | 14664 | 5042 | 8/0/80 | 38 |
| lane含DP乘积旁路 | 3137 | 963 | 2/0/0 | 38 |
| SFU十拍纯标量核，裁掉DP旁路 | 2320 | 833 | 2/0/0 | 38 |

FP32关键段 `g_lane[0].u_scalar.s6_c_r[1]` → `s7_reverse_r[54]`；单SFU核同级段为
`u_arithmetic.s6_c_r[1]` → `s7_forward_r[54]`。表含每两APM包装48个外部对齐/残数FF。
使用 `python3 tools/gpu2/synth.py` 与 `synth_summary.py build/gpu2_synth/*.json`；
Yosys 0.67+94，abc -lut4；脚本切开注册APM黑盒，原生ltp会错误穿越宏边界。
LUT4未映射Pango进位链，不作为PDS逻辑级数或220MHz收敛证明；220/200/150MHz裕量均未取得。
M-8 geometry 总预算17238 LUT；FP32加两SFU核参考已19061 LUT，尚未计其余几何，需真实PDS复核预算。
FP32 smoke：10001 scalar/MUL/add +2048 vec/DP；full：200001 scalar/MUL/add +100000 vec/DP，逐位通过。
参考为整数尾数/指数与显式RNE；测试含staged抵消、第四项NaN忽略、双返回背压、II1与12/13拍。
特殊值逐位核对列为待定（IEEE开发初值），不计规格验收PASS；G2-07未定稿，未覆盖域不声称已验证。
SFU已完成3拍数值前端、10拍标量核、2拍最终缩放；M5/M6 398760次原始调用整数参考逐位一致，
前端398760例、缩放100000例通过；512混合请求3131预约的Python证明通过，尚无RTL预约集成。
EXP的小负数残差用 `FMA(x,ln2,ln2/64)`，避免额外FP32残差舍入；原料bb77b4d6保持3f7f5488。
SFU尚缺ROM/两引擎预约/scratch集成、FPGA顶层/filelist/约束/IP说明；G-P02未完成。
待协调：M6要求64bit LOG+INV并与setup双读，但M7按TDP每口36bit规划；建议一颗1024×36，
32bit分表，在原4拍前端先后读LOG/INV，setup独立B口，保持1DRM、II4和原返回拍数；待明确授权。
复现：`python3 tools/regress.py smoke --path verif/unit/gpu2_fp32 -j 1`，full改档位；SFU改目录名。
原始日志回收到 `build/gpu2_fp32/`、`build/gpu2_sfu/`、`build/gpu2_synth/`，不入库。
风格15文件、Verilator --lint-only -Wall、PDS三类静态限制扫描均0告警/违例。
状态：G-P01 Linux逐位通过、PDS未测；G-P02数值片段已验证，存储/预约架构决策待协调。
