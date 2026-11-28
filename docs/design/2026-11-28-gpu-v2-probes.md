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

## GP-C：卡112校准后的220MHz切拍候选（待定稿）

基线35ec01496；PDS原始路径见origin/win/20261128-112-gpu2-probes的artifacts/{fp32,sfu,setup}，PG2L200H-6/Slow/4.545ns；本节随GP-C实现提交，规格不改。Yosys0.70+219、ABC LUT4/LUT6；新值为Linux估计，非PDS达标证明。
先复用原拍：DP把对齐移位移入+2.701ns加法段；FMA把高位积对齐移入+1.772ns加法段，末两级规格化移入RNE段；SFU EXP索引移位量/余数条件与规格化并行计算，缩放仍两拍。
| 操作 | 旧→新采样延迟（拍） | II与新增拍归因 |
|---|---|---|
| vec4 MUL / FMA | 12→12 / 12→12 | II1；算术仍10拍，复用原返回对齐拍 |
| DP3 / DP4 | 13→16 / 13→16 | II1；积tap 7→8、两层独立加法器各3→4，均对应下表超预算段 |
| RCP / RSQ / LOG2 / EXP2 | 47/68/88/78→56/79/102/91 | 混合II4；前端+2、bank捕获+1；valid tap 5/18/29/40/52/63/75/86避开引擎/写口相位碰撞 |
| setup N48 / 49×33 / signed60重定位 | 2/6/4→4/6/4 | 均II1；N48原27级拆绝对值、LZ、移位、舍入；另两项保留原拍 |

| 卡112同一逻辑起终点（实例前缀省略） | 旧Yosys LUT4/LUT6 | PDS级/裕量ns |
|---|---:|---:|
| APM s5_product[31]→tap_s6_increment | 32/28 | 15/−4.078 |
| DP a[18]→s1_small[0] | 26/18 | 15/−3.703 |
| DP s1_small[2]→s2_sum[24] | 22/14 | 6/+2.701 |
| DP s2_sum[27]→result[3] | 24/15 | 14/−3.285 |
| SFU req_data[12]→ROM a_addr[8] | 38/24 | 14/−2.712 |
| SFU field1 DRM读总线→s1_a_exp[8] | 11/11 | 10/−2.342 |
| SFU s6_c[3]→s7_forward[55] | 38/23 | 13/+1.772 |
| N48 mantissa[1]→truncated[3] | 33/28 | 27/−4.188 |
估计按同类锥校准而非单一比例：普通LUT段L约0.5ns/级；进位段C按协调者确认0.05ns/级，原≥+1ns进位段保留；新增段用T=0.5L+0.05C，DRM另加约2.8ns。PDS优化别名不同，DRM行比较同一读端口的完整32bit锥。
| 新流水段 | 新Yosys LUT4/LUT6参考 | 校准后每段上界估计（L普通级/C进位级） |
|---|---|---|
| DP 比较/移位加法/LZ粗移/低移RNE | 15/11；26/17；18/14；21/13 | 6L+10C / 7L+7C / 7L+3C / 7L+10C，均<4.545ns |
| 积tap APM捕获/高移GRS/pack；FMA APM低移/高移加法 | 4/2；6/6；pack含carry；3/3；41/27 | tap 2L/4L/3L+10C；FMA 2L/7L+14C（4.2ns，最紧） |
| FMA LZ/高位规格化/低移RNE | 20/19；10/7；21/13 | 7L+3C / 7L / 7L+10C；其余原拍普通段≤6L |
| SFU 前端/DRM捕获/捕获后选择/两拍缩放 | ROM11/9；field1/1、result2/2；core首拍19/17；scale16/12、15/11 | 前端各≤7L；DRM1/2L；选择+LZ≤7L加carry；缩放各≤7L加carry |
| N48 四段；49×33合并/重定位 | 24/15、17/13、8/5、25/16；宽carry单独计 | 1L+21C / 5L+3C / 5L / 3L+24C；合并/重定位≤2L+21C |

| 单元（同工具旧→新，括号为增量） | LUT4 | LUT6 | 外部FF | LR/DRM/APM增量 |
|---|---:|---:|---:|---|
| FP32含返回队列 | 15661→13959(−1702) | 11541→10345(−1196) | 4402→5090(+688) | +80/0/0 |
| SFU含scratch/返回 | 8899→8891(−8) | 6704→6792(+88) | 3625→4470(+845) | 0/0/0 |
| 裸N48；其余setup单元增量0 | 853→986(+133) | 738→735(−3) | 120→316(+196) | 0/0/0 |
FF为Yosys合并同值副本后的参考；APM内部/对齐FF不计但增量0。移位叶按7/8/16位复制，选择按16位复制；bank捕获448bit切DRM路径，预译码替换后置操作数捕获；DP16耗尽旧16信用已实测触发II1空拍，32信用用原16深宏双bank（协调者已批准，逻辑深度/总信用均16→32，无数据拍增加）。
验证：setup smoke/full各3458向量通过；隔离候选FP32 full=200001标量+100000向量、SFU full=448892请求/3119259发射逐位通过（bank捕获重排后的full亦通过）；原IEEE特殊值仍仅G2-07开发核对。风格14文件/−Wall三顶层/PDS三类扫描0告警（含单always写入、generate层次引用、generate局部数组切片）；日志build/gpc/。
复现：`python3 tools/gpu2/synth.py --lut 4 --out build/gpc/new4 edrv32_gpu2_fp32 edrv32_gpu2_sfu edrv32_gpu2_fp32_add edrv32_gpu2_fp32_scalar`；基线加`--revision 35ec01496`并改`--out build/gpc/base4`，LUT6改`--lut 6`和输出目录；setup用`measure_probes.py --lut 4 --out build/gpc/setup4`；路径用`timing_paths.py netlist --start 信号 --end 信号[bit]`；回归python3 tools/regress.py smoke或full --path verif/unit/gpu2_{fp32,sfu,setup} -j 1（SFU full用/full）。本机仅串行flock /tmp/edrv32-sim.lock，Verilator5.053。
状态：协调者已批准SFU预取5/18/29/40/52/63/75/86及56/79/102/91拍作为G2-01候选，并批准DP双bank/32信用；G2-01/G2-07最终由协调者和用户定稿；风险为FMA E7余量估计仅0.345ns、SFU选择/LZ、queue bank读选择和复制保留，需原约束PDS重测；E7估计200/150MHz余量0.8/2.467ns，未取得新PDS实测。

GP-C2续接已将获批的SFU预约与FP32双bank候选搬入正式路径，并统一README、tb延迟及先声明后使用风格；实现提交用 `git log -1 --format=%H -- rtl/gpu2/edrv32_gpu2_fp32.v` 定位。
正式路径用Yosys0.70+219重新测得上表全部新资源数，日志/netlist在 `build/gpc/c2-new4/`、`c2-new6/`、`c2-setup4/`、`c2-setup6/`；前两项复现沿用上列synth命令并改输出目录，N48加 `--tops edrv32_gpu2_setup_normalize`。
续接仿真用Verilator5.051、独立目录串行 `-j 1`；三组smoke/full按上列入口，SFU另跑 `python3 verif/unit/gpu2_sfu/run_prepare.py`（512输入）及 `run_scale.py`（2048向量）。
正式路径回归日志回收至 `build/gpc/c2-regress/`，汇总 `build/gpc/c2-regress.log`；首次FP32冷编译超过smoke的60秒预算，完整构建结束后full/smoke通过，setup首次因同步目录缺少model依赖报错、补齐源目录后重跑，未修改timeout或屏蔽错误。
本次风格14文件、三个FPGA探针顶层 `--lint-only --timing -Wall +define+SIM_MODE`、PDS单always写入/禁止generate层次引用/禁止generate局部数组切片均0告警，日志 `build/gpc/c2-style.log`、`c2-lint-remote.log`、`c2-pds.log`；未更改共享文件列表/FPGA文件或增加RTL文件。
