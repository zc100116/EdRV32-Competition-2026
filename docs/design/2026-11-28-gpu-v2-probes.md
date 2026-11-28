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

依据gpu-v2-spec v0.1 §2.4、M-8/M-6；FP32实现74fe746d2、SFU数值阶段1fd8fefa7；集成05b03d325。
FP32原生4lane、八APM，完整48bit积；DP3第四积+0，独立三加法器平衡树，禁止融合DP。
每lane第1拍捕获/LZ，第2–5拍两APM级联；第7拍舍入乘积旁路供DP。
FMA第2拍公共指数，3/4拍对齐C，5拍等积，6拍对齐积，7拍56bit正反加减，
8拍LZ/指数，9拍规格化/GRS，10拍RNE/pack，11拍按已确认返回预约对齐，12拍写队列。
56bit保留完整积及7个低保护位，较77bit省1563 LUT4/40FF；未增加拍数。
DP第7拍乘积舍入，8–10拍两对加法，11–13拍最终加法；末pack直接写队列，13拍按协调者确认保留。
独立adder参考三段均24 LUT4：第一段product_o（第二层为u_pair01.result_o）→s1_small_r[0]，
第二段s1_small_r[0]→s2_sum_r[25]，第三段s2_sum_r[10]→result_o[0]（最终层为队列写端）。
单adder728 LUT4/197FF；两层各3拍，G-P05以真实PDS决定时序，不自行加拍。
FP32双返回支持背压、总信用16、II1；五份16×32返回LUTRAM约80LR，无DRM。
协调者已确认：M-6的64bit打包与M-7 §9.1 TDP36冲突，改一颗1024×36、32bit分项，
A口在原4拍前端先后读LOG/INV，setup独立B口连续读RCP，保持1种子DRM/II4/原返回拍数。
ROM地址RCP0..63、RSQ64..127、LOG128..176、INV177..225、EXP226..289；其余补0。
SFU拍1拆分/首读，拍2读INV/数值转换，拍3字段/双表齐备，拍4写scratch并预取，拍5首次运算。
两核心各10拍/II1；模预约(4,0)/(14,0)/(24,1)/(34,1)/(45,0)/(55,0)/(65,1)/(75,1)。
四op分别用4/6/8/7槽，核心返回后2拍缩放和返回队列；无背压握手延迟47/68/88/78，混合II4。
同步scratch与首次字段写同边沿转发；相隔10拍用核心返回旁路，11拍间隔用RAM同址转发，不加等待。
七输入字段副本+七结果bank共14DRM；engine0不读LOG基值、末槽7无后继，较16bank规划省2DRM。
metadata双副本32×21、双返回队列32×37共116LR分配额；总32信用支持背压，算术不全局停顿。
forward数据寄存切开RAM同址路径，两个16bit选择叶限制扇出；metadata只流水20位，不搬87级宽记录。
EXP小负残差用FMA(x,ln2,ln2/64)保留精度，无新增槽/APM；bb77b4d6保持3f7f5488。

| 独立Yosys LUT4参考，不含IP内部FF/逻辑 | LUT4 | 外部FF | APM/DRM/LR | 最长级数 |
|---|---:|---:|---|---:|
| FP32+DP历史参考74fe746d2 | 14421 | 4594 | 8/0/80 | 38 |
| FP32 FPGA顶层历史参考 | 14664 | 5042 | 8/0/80 | 38 |
| SFU完整单元 | 8061 | 3721 | 4/15/116 | 38 |
| SFU FPGA顶层 | 8170 | 3817 | 4/15/116 | 38 |

SFU关键段g_engine[0].u_arithmetic.u_arithmetic.s6_c_r[0]→s7_forward_r[54]；FP32同级段s6_c_r→s7_reverse_r。
每RAM bank有32bit转发数据及2选择FF；ROM捕获和LUTRAM按16/5位同边沿复制使能，不加拍。
表为Yosys合并等价FF后的统计；PDS须保留使能副本，每对APM另48外部FF，物理FF以PDS为准。
SFU4APM不变，15DRM含1种子/14scratch，较17DRM规划省2；LUT/FF高于M-6的3284/1864估算。
FP32加SFU独立参考已22482 LUT4，超过M-8 geometry17238预算且未计其余几何，需PDS核实进位链/整片预算。
复现python3 tools/gpu2/synth.py及synth_summary.py build/gpu2_synth/*.json；Yosys0.67+94，abc -lut4。
脚本切开注册APM和存储IP边界，原生ltp会错误穿越宏；38/24级未映射Pango进位链，不等同PDS逻辑级数。
full保留原执行398760调用，再补M6跳过的12405对underflow输入（49620调用），加512混合前缀；
448892请求逐位通过、3119259次RTL发射；smoke另有256压力样本，不删超限或underflow。
smoke前512请求连续II4/逐拍延迟检查，另256压力样本；setup并发/禁读保持、返回背压与scratch冲突断言覆盖。
FP32原smoke/full含staged抵消、第四项NaN忽略、双口背压和12/13拍；特殊值仍为G2-07待定开发核对，不计规格PASS。
测试入口python3 tools/regress.py smoke --path verif/unit/gpu2_sfu -j 1；full改档位并用gpu2_sfu/full路径。
ROM镜像python3 -B tools/gpu2/gen_sfu_rom.py；IP说明/220MHz约束/导入/filelist已提供，日志在build/gpu2_sfu/及gpu2_synth/。
状态：Linux逐位/静态检查通过；220/200/150MHz实际裕量、真实DRM/LUTRAM/CLMS仍需Windows PDS/ModelSim。
