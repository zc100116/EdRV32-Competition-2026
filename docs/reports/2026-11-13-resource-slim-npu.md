# NPU 瘦身评估（2026-11-13）

- 评估源码 `e1052afaffdbbbe188d9e8afefccc9a6cc841fd2`；范围为 `rtl/npu/` 全部、全部 NPU tech 包装、AXI256 异步桥及其 FIFO；仅报告，未改 RTL/规格/约束/软件。
- 实测基线为卡70结果 `7153d605cc6c66fa7f415b22bbe8d5b40da7ff08`，构建源码 `ce2b4fd42edc526fa702fd08071e14b4c2a0353a`；PDS 2022.2-SP6.1 build138931、PG2L200H-6 FBB676、sys/npu/mem=125/180/125 MHz。
- 原始路径：`origin/win/20261108-70-soc-npu-post:tasks/win/20261108-70-soc-npu-post/artifacts/{resource_hier,resource_summary,high_fanout,routing_congestion}.txt`；资源表全部取 ADS `resource_hier`，不混用 Device Map/PnR。
- 对照卡68 R2 `a5d08903812061a894dd8cdfff970fc77eefbb0d` 的 `tasks/win/20261108-68-soc-v021-full/artifacts/R2/`；时序/位置依据 `2026-11-08-timing-soc-audit.md`、`2026-11-10-route-soc-card69.md`；卡70尚无最终布线时序。
- 以下收益全部为**结构估算，非 PDS 复测**。CLM 换算用每站点4 LUT/8 FF，`C=max(ceil(ΔLUT/4),ceil(ΔFF/8))`；分布式 RAM 已包含于 LUT，单列 `ceil(ΔRAM/4)` 为 CLMS 压力，不重复相加。C 是容量当量，实际腾出站点取决于原打包/放置，不能保证等量释放。

## ADS 资源（LUT / FF / 分布式 RAM / APM / DRM）

| 层次（均在 u_npu 下；父子不累加） | LUT | FF | RAM | APM | DRM |
|---|---:|---:|---:|---:|---:|
| u_npu 总计 | 19004 | 42630 | 1086 | 267 | 134 |
| u_conv；u_datapath | 13931；11382 | 35720；33022 | 749；619 | 264；264 | 114；114 |
| datapath/u_accum | 3043 | 5619 | 0 | 0 | 0 |
| datapath/u_mac_array | 270 | 8560 | 0 | 256 | 0 |
| datapath/u_window | 735 | 6188 | 0 | 0 | 0 |
| datapath/u_result_quant | 2188 | 5271 | 0 | 8 | 0 |
| datapath/u_weight_store | 2058 | 2176 | 0 | 0 | 96 |
| datapath/u_quant_param_store（8×u_ram） | 224（216） | 1360（880） | 216 | 0 | 0 |
| datapath/u_residual_buffer（u_residual_ram） | 192（128） | 553（512） | 128 | 0 | 0 |
| datapath/u_residual_add | 1921 | 1569 | 0 | 0 | 0 |
| datapath/u_writeback（u_result_ram） | 587（256） | 1106（1040） | 275（256） | 0 | 0 |
| datapath/u_input_unpack；u_activation_lut；u_line_cache | 155；1；1 | 542；20；0 | 0 | 0 | 0；2；16 |
| u_conv/u_conv_write | 449 | 284 | 128 | 0 | 0 |
| u_post（u_classify；u_dfl） | 1602（466；217） | 2787（1047；389） | 32（0；0） | 1（0；1） | 12（2；0） |
| post/exp；probability；queue_even；queue_odd | 0 | 0 | 0 | 0 | 1；1；4；4 |
| u_axi_bridge（R；W；AR；AW；B FIFO） | 362（144；142；32；31；13） | 160（各32） | 296（130；129；18；18；1） | 0 | 0 |
| u_nonconv（plane/row scratch 各4 DRM） | 1398 | 1387 | 0 | 0 | 8 |
| u_descriptor；u_read_dma；u_write_dma | 274；28；22 | 643；328；305 | 0；9；0 | 2；0；0 | 0 |
| u_regs；u_apb_bridge | 810；9 | 808；205 | 0 | 0 | 0 |

## 候选（按节省/代价优先；“省”为正，“增”为负）

| 编号/模块/改法 | 类 | 估算省 LUT / FF / RAM；CLM 当量 | 新增 DRM/APM | 代价、验证范围与拥塞位置 |
|---|---|---|---|---|
| N1 result RAM 改同步 DRM，内部阵列/输出寄存替代软寄存 | S¹ | 256 / 1024–1040 / 256；128–130，含CLMS64 | 8 / 0 | 保持2拍读、512写/512读后选256、旧值碰撞语义；新IP；验证环credit/双plane/取消；枢纽，DRM列位置风险 |
| N2 quant 参数8 bank改 DRM | S¹ | 216 / 864–880 / 216；108–110，含CLMS54 | 8 / 0 | 8×32×54有效位，64位接口保留零；每bank独立写/并行读，2拍不变；新IP；量化逐位/装载/CE保持；枢纽，需避免再跨列 |
| N3 residual RAM 改 DRM | S¹ | 128 / 512 / 128；64，含CLMS32 | 4 / 0 | 32×256、2拍不变；新IP；验证双bank最后读与重用、半尾/取消；枢纽 |
| N4 accum 去R5数据寄存，R4选择直接送ACC | I | 0 / 1216–1280 / 0；152–160 | 0 / 0 | 64×19–20位；延迟−1，II=1；mux+32位反馈加法可能成为关键路径；准备参数、tag/valid/credit重对齐，D2/气泡/连续块逐位验证；MAC左端/枢纽 |
| N5 residual_add 去512位旁路副本 | I | 0 / 512 / 0；64 | 0 / 0 | RES_EN=0时令加法器的残差输入等于zp，算y+zp−zp，复用wb1_sum；延迟/II不变；输入选择增加算术前路径，需重测时序；残差/旁路/饱和/半尾全验证；枢纽 |
| N6 result_quant 合并两段49位桶移位Q6/Q7 | I | 0 / 196（另有少量tag） / 0；25 | 0 / 0 | 4×49；延迟−1，II不变；六级选择可能超过主通路约8级预算，需全位宽舍入/负数/shift0..63及LUT/残差对齐验证；枢纽 |
| N7 post 仅按180MHz合并max层、末端阈值与DFL小级 | S | 0–80 / 250–500 / 0；32–63 | 0 / 0 | 200→180仅多0.556ns；分类约−2..3拍、II=1，DFL少量减拍；两层比较/25位减法成为新关键路径，重验前递/阈值/全部候选/DFL整数舍入；枢纽外缘 |
| N8 regs 删PERF2..7有效计数，保留读零地址 | S | 约150–220 / 约280–320 / 0；38–55 | 0 / 0 | 六个32位计数器+事件/本地复位副本；丢读写/等待/非卷积性能观测；修改spec及板级检查期望，应用不依赖有效值；控制区 |
| N9 post/写DMA 消除额外优先级，互斥源直接在既有W寄存入口选择 | I | 0–128 / 0 / 0；0–32 | 0 / 0 | 现综合可能已摊平，零收益也是合法结果；不新增宽缓存；检查S_LOAD/S_POST与CONV/NONCONV切换、背压、最后B/ABORT；枢纽 |
| N10 window/MAC 合并相邻输入级或撤一组激活副本 | I | 0 / 毛省512–2560 / 0；64–320 | 0 / 0 | 4份256中有256位未用，按768有效→256共享省512，去2048位权重边界再省2048，控制/tag另算；A5/MAC输入重对齐；整片W/A/P已负裕量，暂不推荐、净收益不计总数 |
| N11 AXI R/W FIFO 改DRM+已有async_fifo_ram预取 | I | 净省−80..40 / −520..−570 / 259；CLMS65，新增约65–72 FF站点当量 | 约10 / 0 | 深度8保留，新增头暂存约260+257位及控制，LUT含输出选择；CDC/复位/全速/背压重验、新双钟1拍IP；枢纽，不保证净省CLM，低优先 |
| N12 post 两棵16路max改一棵，分两拍服务左右像素 | S | 毛省约100–200 / 200–310 / 0；毛25–50；缓存后可能倒增 | 视缓存映射 / 0 | 核心II=2违反§5.6，且两树为明确初值；16个连续beat需额外吸收约8beat=2048数据位及标签，不能拿全网平均吞吐代替突发；不推荐 |

¹ N1–N3 功能/容量/外部吞吐不变，但 §5.2 明确“只用32项的量化参数、残差读缓冲、结果缓冲使用分布式RAM”，故仍归S，须用户决定改介质条款；不是自行放宽功能。DRM数量按既有512×256权重/暂存IP实测4 DRM、每bank 64位一个估算，不能按总bit数除36K忽略宽口数量。

## 后处理、主流水与存储判断依据

- `post_classify` 的max1/2/3/4分别256/192/96/48位；合并两层可去192或48位及标签。best RAM、概率RAM各2拍读的等待级不能直接删除；前递历史也要随流水改。DFL已是单串行链（1 APM、389 FF），没有第二个可删的DFL阵列；bins暂存和25/28/36位中间值是完整精度所需。
- `conv_write` 的 `read_w` 在S_STREAM内只受4个return reservation和burst长度约束，不按MAC归约间隔节拍；可连续读多拍，每burst最多16beat，两个plane分burst。即使当前4槽回收偶有气泡，仍有连续输入，单树每2拍吞一个beat会积压；量化16拍/像素对的平均速率与burst吸收能力不是同一指标。
- 单树若加足缓存、排程并继续保证入口II=1，原则上可摊薄低平均负载，但须证明所有合法交错/全候选/边界下无积压溢出；还要修改“两棵树/双格概率”结构条款。用原结果RAM暂留再慢读也改变当前无后处理ready的接点，不能记作无代价合并。
- `edrv32_npu.v:305–344` 已将装表/gather接u_read_dma，候选输出接u_write_dma；读数据是共享广播，没有独立post AXI读DMA。写侧是post与conv/nonconv的256位选择，N9仅调整该既有入口；`post/load_data_r`256位供逐字装表、`write_data_r`256位供24B跨beat打包，各有存活期，不能仅凭串行阶段就删。读写DMA自身256位弹性寄存也不可无条件删。
- result存储是**32×512**，DMA出口才是256位；结果环32pair、残差双16beat、量化8×32条是规格容量，缩深均为S。结果2拍读的保留/碰撞CE与DRM输出保持必须逐项匹配，不能简单替换IP名；N1–N3保守收益只计软读级移入硬核，未计写入暂存消除。
- 主流水调整允许按§5.4的待定级数另写设计记录，故N4–N6归I；ACC的2048位反馈态、quant的2048位hold_acc和512位组装是串行量化所需，不能作为“多余一级”全删。Q4乘积重构+Q5舍入均为49位加法，不优先合并；Q10/Q11旁路对齐2拍激活表，不能单独去一级。
- MAC激活skew为8×16×(0+…+7)=3584位，服务C1–C8固有时差；权重也按item错拍读出，不能只删skew而保持APM配置。APM内部M1/M2/C1–C8已在硬核，不是可回收CLM FF；N10只能动外围输入/副本，必须连tag/控制一起改。
- 卡65 `953268f0` 独立200MHz WNS+0.053ns（估算202.1MHz），但其46144 FF与整片基线不同；卡68整片180MHz已WNS−0.205ns，W/A/P最差0级路径走线占91–96%。因此180MHz不提供“删任意宽级”的证据；N4/N6先看新算术路径，N10须在存储瘦身后再试，禁止照卡69加大范围副本。
- AXI R/W实际宽260/289、深8；W的32位strb恒全1使映射仅129 RAM，R130，共259。DRM替换会把组合读变1拍预取，已有async_fifo_ram带head_data和选择，收益必须扣这些FF；AR/AW/B共37 RAM很浅，迁移更不划算，深度4还会缩短信贷往返覆盖，不能无证据减半。
- 源级复位审查：所列accum/MAC/window/quant/存储、post bins/record/算术数据均无复位；复位主要用于valid/FSM/计数/所有权，未发现可直接删除的宽数据复位。keep/syn_preserve使相同控制/标签物理复制，删属性可能再合并也可能拉长广播，不能把RTL声明位数直接当收益。

## 同RTL不同FF与高扇出

- 卡68→70，datapath 11236/32404/600→11382/33022/619，即LUT+146、FF+618、RAM+19；accum FF4330→5619（+1289）、MAC9388→8560（−828），两者合计+461，其余+157。整个u_npu实际+2051 LUT/+3621 FF，不能把整片ADS的+3828 FF全归post。
- 两ref的 `git diff -- rtl/npu/edrv32_npu_{accum,mac_array,window,result_quant,writeback}.v` 为空；window LUT2800→735（−2065）、weight_store 11→2058（+2047）而源码也不变，是跨边界选择逻辑归属改变的旁证，非硬件凭空省/增同等数量。
- **综合推断**：新增post负载改变展平后的公共表达式/寄存合并、复制、SRL选择及层次归属；1289接近64×20位边界，828也不等于一个明确RTL级，不能只凭数量确证retiming。未取得两版逐寄存网表对照，不能指定某一优化为根因，更不能把618全部作为可省目标。
- RTL可用单一所有者、明确共享控制/数据和局部复制边界减少不确定性；需物理副本处保留少量属性，不能全层次keep/dont_touch或全面禁SRL。这样只能降低波动，不能保证层次计数稳定；验收看整片总FF/CLM与布局时序，并用已有PDS网表比较合并/复制结果，不新增门禁。
- 卡70高扇出实测：regs/N7=644、conv/N1307=418、is_conv=373、post_active=357、conv/serial_valid=319、residual_rd_en=260、WB valid/slot地址=258、weight片选=256/257。N1–N3把宽口CE/地址落入硬RAM、N9取消嵌套源选择可减少CLM负载；保留单点owner，按硬核bank局部驱动，避免为所有扇出直接复制256位数据。热点坐标x180–300/y240–600约55%来自卡69报告的模块位置推断，非卡70逐模块拥塞测量。

## 软件核对与结论

- 核对整个 `sw/` 的NPU宏和 `engine_perf/engine_control/engine_poll` 调用（含驱动、sw/lib、showcase、demo、board_*、soc及host tests）：`npu.c`配置全部基址/描述符和post阈值/状态/count；`engine.c`间接读取STATUS/ERR_CODE/DONE_COUNT、配置IRQ；`board_npu`读取ID/CUR_DESC、验证SOFT_RST/ENABLE和全部PERF复位；不能仅搜索npu.c就判未用。
- showcase/platform、demo/scene_npu与demo_npu/inference使用PERF0；board_npu用PERF0做周期、PERF1打印MAC；PERF2–7未找到有效统计值消费，但board_npu复位循环读取它们，故N8不是“从未读取”。PERF8–15已读零、无8个额外计数器可删；sw/lib/yolo_post使用硬件候选并保留raw软件路径，不能删后处理/原始算子模式。
- RAW_CLS_WRITE=1、ABORT未找到现有板级/应用主动使用（仍为规格调试/取消能力，删除归S，资源未证实不记收益）；POST阈值虽应用写固定值，仍是明确可配寄存器，硬编码归S。CTRL.ENABLE仅镜像/readback的1 FF、IRQ_EN[31:2]读回存储30 FF可列S，ID/CTRL.START/FRAME无额外可删数据态；省幅很小，不进前五。
- **推荐前五：N1→N2→N3→N4→N5**；前三项先由用户批准§5.2介质修改，保持全部功能/吞吐。合计估算省**600 LUT、4128–4224 FF、600分布式RAM**，新增**20 DRM、0 APM**；约**516–528 CLM容量当量**（其中CLMS150，不另加），DRM整片298→318、余97。N4/N5时序未过时仅前三项也可省2400–2432 FF、300–304 CLM当量；这些数字未计N7–N12，避免重叠/毛收益叠加。
- 无需先改规格的试验顺序为N4/N5/N6小范围相对综合及180MHz整片PnR；后处理200MHz降预算和单树均留S决策。任何删级最终都须独立算子逐位、混合描述符/残差/全候选、背压/错误/取消回归及整片setup/hold/拥塞证据，本次按任务约束未运行这些验证。
- 已检查、无独立可直接兑现收益：input_unpack的C4串行展开、line_cache/weight_store容量与读端口、4路activation LUT、nonconv的POOL/UPSAMPLE共享行暂存、descriptor容量/OP错误、DMA的在途计数/B栅栏、APB CDC/reset副本、post的best/满5040队列/双口表/串行DFL；已用DRM/APM部分不重复报搬迁收益。本范围无F类CPU/cache改动。
- 复现：`git show <上述ref>:<上述artifacts路径>/resource_hier.txt`（其余三报告同法）；`git diff <卡68ref> <卡70ref> -- rtl/npu rtl/tech`；`rg -n 'EDRV32_NPU_|engine_perf|engine_poll|engine_control' sw --glob '*.[ch]'`，再沿通用driver表追调用。文档验收 `git diff --check`；无RTL lint适用项，未运行仿真/访问仿真VM/运行Yosys，所有未实测收益均保留估算标记。
