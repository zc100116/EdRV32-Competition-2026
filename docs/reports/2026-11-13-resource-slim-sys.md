# CPU、存储总线、网络和系统外设瘦身评估（2026-11-13）

- 静态评估源码：`e1052afaffdbbbe188d9e8afefccc9a6cc841fd2`；仅报告，无 RTL/规格/软件/约束改动。CPU/cache 按冻结 v0.21 处理。
- 资源基线：`origin/win/20261108-70-soc-npu-post`=`7153d605cc6c66fa7f415b22bbe8d5b40da7ff08`，实际综合源码 `ce2b4fd42edc526fa702fd08071e14b4c2a0353a`；`tasks/win/20261108-70-soc-npu-post/artifacts/resource_hier.txt`（下称 H），同目录 `high_fanout.txt`（HF）。PDS 2022.2-SP6.1 build138931，PG2L200H-6 FBB676，sys/npu/mem=125/180/125 MHz，pix=74.25 MHz。
- H 是 ADS 层次统计，不能与 device-map/PnR 混加；卡70无最终 PnR 数字。卡68 R2 对照见 `2026-11-08-timing-soc-audit.md`：CLMA/CLMS=87%/86%，mem WNS −0.025 ns，sys −0.088 ns，故没有可直接删除流水的时序余量。
- 以下节省均为**结构估算，非新综合结果**。L/F/D 表示 LUT/FF/分布式 RAM；D 已包含于 LUT，不能再加。站点等效量按每 CLM 4 LUT/8 FF，`max(ceil(L/4),ceil(F/8))`；分布 RAM 的 CLMS 压力另看 `ceil(D/4)`。这是理想打包量，真实释放站点可能为零，须整片 PDS 验证；FF 与 LUT 共用站点不能重复记账。

## 实测资源（LUT / FF / 分布 RAM / APM / DRM）

| H 层次（子项包含于父项，不累加） | LUT | FF | 分布 RAM | APM | DRM |
|---|---:|---:|---:|---:|---:|
| u_cpu | 19212 | 12109 | 680 | 4 | 27 |
| u_cpu/u_core/u_csr | 1529 | 868 | 0 | 0 | 0 |
| u_cpu/u_core/u_frontend（含 IB/预测器） | 4127 | 2912 | 680 | 0 | 0 |
| …/u_ib；…/u_predictor | 1510；1531 | 1011；490 | 0；680 | 0 | 0 |
| …/u_predictor/u_btb；u_direction；u_chooser | 119；261；241 | 0 | 116；192；192 | 0 | 0 |
| …/u_predictor/u_local_history；u_local_direction | 138；77 | 0 | 116；64 | 0 | 0 |
| u_cpu/u_icache；u_dcache；u_cache_ctrl | 3311；3492；53 | 2542；1867；161 | 0 | 0 | 9；18；0 |
| u_mem；u_mem/u_gw（含 AXI64 CDC） | 9348；767 | 9095；1116 | 849；0 | 0 | 4；0 |
| u_mem/u_xbar | 8581 | 7947 | 849 | 0 | 4 |
| …/g_port[1,2,4,5,6].g_w_ram.u_ram（每个） | 144 | 288 | 144 | 0 | 0 |
| …/g_port[3].g_w_ram.u_ram | 129 | 257 | 129 | 0 | 0 |
| …/u_rbuf；u_regs；u_sched | 1705；3396；436 | 1204；3621；151 | 0 | 0 | 4；0；0 |
| u_eth；u_eth/u_regs；u_tx；u_rx | 4437；1210；1212；764 | 4665；1271；1027；983 | 76；0；0；0 | 0 | 3；0；1；0 |
| u_eth/u_rx_packets；u_rx_write；u_write_dma | 81；532；290 | 7；488；388 | 76；0；0 | 0 | 0 |
| u_sys；u_sys/u_sys_xbar | 1931；364 | 1640；138 | 8；0 | 0 | 20；0 |
| u_sys/u_clint；u_plic；u_gpio；u_i2c；u_uart；u_sysctrl | 282；196；235；57；192；25 | 242；184；204；79；143；68 | 0；0；0；0；8；0 | 0 | 0 |
| u_sys/u_sys_apb_bridge；u_media_apb_bridge；u_sys_apb_decoder；u_media_apb_decoder | 96；84；53；124 | 127；123；0；8 | 0 | 0 | 0 |
| u_sys/u_reset_ctrl | 11 | 29 | 0 | 0 | 0 |
| u_sys/u_rom；u_sram | 61；141 | 30；37 | 0 | 0 | 4；16 |
| u_ddr3（生成 IP，排除）；u_rgmii；u_tmds | 4689；1；0 | 5210；19；0 | 45；0；0 | 0 | 0 |

## 候选（按收益与代价综合排序；I 实现、S 规格决策、F 须先解冻）

| 编号、模块、改法 | 类 | 估算节省 L/F/D；CLM 等效 | 新增 DRM/APM | 代价、验证与拥塞位置 |
|---|---|---|---|---|
| 01 mem 六口 W RAM 改同步读 DRM，输出寄存搬入硬核 | S | 849/1697/849；约213，含约213 CLMS | 24/0 | 功能不变但 mem-spec §7 明定分布 RAM，须改该条；6×ceil(288/72)=24 DRM，剩余117→93；新生成 SDP IP，维持一拍读、CE保持、old-data；验证 AW 后首拍连续 W、背压与末拍；mem/DDR 跨区，非 NPU 核心但共用中部通道 |
| 02 xbar 去 WAIT_SUM/MAX、URG_CNT 统计及对应快照，保留流量/窗口统计 | S | 700–1100/800–1120/0；约175–280 | 0/0 | 上界7×2×(32+16+32)=1120 FF，常量裁剪后取较低区间；须改寄存器、驱动、监控 UI；仲裁本身不变；统计/快照/CLEAR 回归及带宽显示；mem 区，减快照/清零广播 |
| 03 CSR 去8个 HPM，保留 cycle/instret/time | F | 600–900/512–560/0；约150–225 | 0/0 | 8×64=512位外加事件选择；仅面积估算，需解冻并修规格、HPM UI/CSR测试；CoreMark主算法周期预计不变，观测功能消失，Fmax待测；CPU热点 |
| 04 ETH 保留 PERF0/1/2/10，去其余7项 | S | 200–350/224/0；约50–90 | 0/0 | 7×32 FF及加法/读选择；吞吐和协议不变，诊断能力缩小；改 eth-spec §4.3、eth_diag和通用监控，验证计数/清零/收发；ETH↔APB已知近临界区 |
| 05 合并 mem/ETH APB 低5位地址副本：18/9组各收为3组 | I | 0/45–65/0；约6–9 | 0/0 | 原27×5→6×5，理论最多105 FF，实际未用位被裁剪故降额；不动 setup/access 拍与PREADY；syn_preserve副本本为降扇出，可能恶化125MHz；APB全地址/连续访问及STA，非NPU核心 |
| 06 W输出由动态切片改为局部一热选择/平衡树，保留级数 | I | 0–200/0/0；0–50 | 0/0 | 288位六选一的映射优化目标，非确定收益；不得新增宽寄存；验证逐口交错事务与等价性，STA/PnR；直接针对 w_port 高扇出与DDR跨区 |
| 07 去 tournament，保留BTB+gshare | F | 456/0–100/372；约114（CLMS约93） | 0/0 | 三表实测和241+138+77 LUT；还需裁控制/令牌，未计额外收益；CoreMark预测准确率/周期下降，v0.18模型曾显示引入该级收益+3.7%，不能当作反向实测；Fmax可能改善，须解冻、性能模型/三负载/CPU全回归；CPU热点 |
| 08 NPU AXI256 W/R FIFO 改双时钟DRM，深度保留至少8 | I | D约259；L净−300至+100，F净增加约520–560；净CLM无保证，释放约65 CLMS | 8/0 | 4+4个72位宽DRM；用async_fifo_ram会加head_data和宽输出mux，不能只报原284 LUT全省；新IP、首字+1读周期，深度可能需16维持吞吐；双时钟/随机背压/单拍流与整片性能验证；**NPU枢纽**，与NPU报告不可重复求和 |
| 09 IB 去预译码存储，读出后再译码 | F | 100–300/最多280/0；约35–75 | 0/0 | 4×70位predecode；读侧重建抵消部分LUT，I$→IB已−0.088ns，可能形成新关键路径；CoreMark理想周期不变但Fmax下降风险高，不能直接删级；CPU全回归/STA |
| 10 PLIC 优先级3→1位；GPIO消抖24→22位 | S | 20–60/约40/0；约5–15 | 0/0 | PLIC少(15+1)×2=32位，GPIO实际4输入各少2位；GPIO最大消抖134→33.6ms@125MHz，仍容20ms演示；sys_spike写priority7/threshold3须改；非NPU区，低优先 |
| 11 W深16→4、B深8→更浅、rbuf128→更小 | S | 未计正收益 | 0/0 | W须存满LEN+1后才发AW，合法16拍不能放4拍；缩rbuf在相同72位映射下仍4 DRM，主要少指针FF且降低并发；须降最大burst/在途或重写DDR连续W契约；不推荐 |

- 除01/08外无新增IP；I类无软件接口改动。03/07/09均须先解冻，07/09保持指令集但须重测CoreMark、视觉、LVGL周期与Fmax；不承诺当前频率不降。mem基线9348 LUT已超过规格8K目标，不能据目标值下调实测基线。

## 关键结构与软件证据

- 01 的总数必须用 `5×144+129=849 LUT/D`、`5×288+257=1697 FF`，不能按六份144/288计算；P3常量WSTRB被综合裁剪。包装 `rtl/tech/edrv32_ram_mem_xbar_w.v` 已是一拍读，两个144位半部地址/CE虽复制但语义相同；DRM同步读可以保持延迟，不能再串接一拍输出寄存。old-data和停读保持需在新IP上确认。原逆向迁移依据见 `docs/design/2026-10-31-drm-lutram.md`（当时瓶颈为DRM）。
- FIFO需求：mem-spec §2.2 明定W16/B8/rbuf128和8在途；P0只读，其余6口256位数据+32位字节掩码，P2窄CPU访问仍须保留byte strobe；P3全掩码已自动常量化。缩深浅LUTRAM未必少D，不能以存储位数比例估计收益。sched只有436 LUT/151 FF，无宽数据总线，保留DRR/令牌/urgent/饿死规则；rbuf已用4 DRM，259位含RESP/LAST，七口skid隔离反压，取消会改变无RREADY下游契约。
- HF须区分版本：卡68审计 w_port[1]=621、N633=153、P6 read_hi=144、ram_data位约68–73；卡70HF的w_port[1/2]=616、[0]=472，另见rbuf skid_valid[6]=350、snapshot_cmd每口208。N633为综合网名，不能臆断对应RTL；06从编码选择扇出入手，01从RAM CE/外部FF负载入手；rbuf输出宽mux已贴近NPU关键跨区，改共享skid或删隔离可能传播反压，未计收益。
- CPU副本不是重复无用数据：chooser copy0/query与copy1/update为不同读地址；local_history三份服务两个查询和一个训练地址，local_direction亦三读；DRM同步读替换异步读会改F1/F2/训练流水，不能列为无代价I类。实际HPM为8个64位计数器、16种事件（非16个物理计数器）；`sw/apps/showcase/board/hpm.c`和`platform.c`分两轮使用全部8槽。
- frontend另有4×160位流缓冲、4×179位IB及重放/预测元数据；容量与规格8条合计credit相配，缩深须F类性能重评。I$/D$各32KiB、tag/data已DRM，缩容量主要省硬核而非当前稀缺CLMS；双路load选择/early路径与CoreMark相关，未承诺缩cache或去旁路有净收益。
- 软件全树检索（排除生成头文件作为使用证据）：`sw/drivers/mem_xbar.c`读取全部统计；`sw/lib/eth_monitor.c`、demo、showcase/LVGL及board/network调用快照，故02不是“无人使用”。`sw/apps/showcase/board/network.c`使用窗口0/1/2/3、UDP发送、PERF2/10，board/debug用PERF1/2；`sw/tests/eth_diag/main.c`读全部PERF并通过MDIO配置PHY、`sw/drivers/eth.c`配置TX_GAP；协议检验、ARP、MDIO、四窗口不能按当前一条演示路径裁掉，裁剪均属S。
- PLIC源1/2/5/6/8–15实际连UART/GPIO/I2C/cache及8个媒体源，共12源，3/4/7接0；H只保留12组同步器，删除空源不会再省6个同步FF，且最高源15仍须4位claim。3位优先级被sys_spike使用，不能据board程序常用priority1擅改。
- GPIO板级只输入4个key（其余接0），H已裁掉其余输入同步/消抖，不能按16×24位全省；demo设置20ms消抖。I2C为两摄像头SCCB所需，57 LUT/79 FF；UART双16字节FIFO和可编程分频用于console/下载；CLINT64位mtime/mtimecmp与CPU time、计时及中断相连，缩宽均属S且收益小。
- 复位抽查：W RAM、rbuf skid/table负载、CDC payload、DDR网关数据、RGMII数据均未复位；统计快照带复位是可见读寄存器的复位语义，不可直接删除。CPU预测历史、GPIO消抖、FIFO指针属于控制。未发现可直接按5.2删除的大批数据复位；保留区域reset_copy，不为省少量FF合并高扇出复位网。

## 全片公共异步单元（按 full_top 可达实例计，排除其他板级测试顶层和IP内部）

| 归属/数量 | 深×宽（每个通道） | 存储/实测 | 判断 |
|---|---|---|---|
| mem/u_gw/u_bridge：1个AXI64桥，5 FIFO | 2×49 AW/AR；2×73 W；2×6 B；2×71 R | FF；合计96 LUT/484 FF | 已是原语最小深2；ID/SIZE/BURST用于合法性/回传，改DRM浪费至少5块且加延迟 |
| npu/u_axi_bridge：1个AXI256桥，5 FIFO | 8×37 AW/AR；8×289 W；8×3 B；8×260 R | LUTRAM；362 LUT/160 FF/296 D | 深8覆盖指针同步往返，不能用常见16拍burst证明AW/B可缩；W常量掩码已裁，见08 |
| VIN两摄像头：2 FIFO | 16×36 | LUTRAM；合计73 LUT/80 FF/36 D | 带像素及边界标记，缩宽须重编码；改DRM约2块但新增头寄存≥72 FF，CLMS仅9站点，低收益不推荐 |
| ETH收/发：2 FIFO | 512×10 | 外接DRM，合计113 LUT/198 FF/1 DRM | 8数据+2控制，已用硬核；深度吸收收发节拍，缩深不释放当前半块DRM |
| DISP L0/L1：2 FIFO | 512×256 | 外接DRM，控制合计240 LUT/702 FF，RAM合计8 DRM | 已用硬核；256位为8像素组，深度吸收DDR抖动，不裁 |
| SYS媒体APB、NPU APB：2桥 | 各1在途；request53、response33位握手 | FF；合计19 LUT/421 FF；内含4个cdc_handshake | 53=16地址+1写+32数据+4掩码；33=32数据+1错误，握手同步级不能删；NPU只用低12位地址已常量化，非两份FIFO |

- 合计16 FIFO（10桥内+6流接口），其中FF5、LUTRAM7、外接DRM4；另有2个APB桥，不能把包装内FIFO再计一次。依据 `rtl/common/edrv32_{axi,axi256}_async_bridge.v`、`rtl/media/{vin/edrv32_vin_dvp,disp/edrv32_disp}.v`、`rtl/eth/edrv32_eth_fifo.v`及H。
- 其他bit/pulse/Gray/handshake用于中断、复位释放、DISP参数/计数/帧请求，属于控制CDC而非宽数据缓存；保留两级同步，未识别可合并的相同源/相同目的/相同复位契约副本，不以删同步级换面积。08收益归公共单元口径，与NPU工作包汇总去重。

## 建议与排除

- 推荐先做的五项：01（须批准存储映射条文修订）、02（用户决定诊断裁剪）、04（用户决定计数裁剪）、05（小规模试验）、06（宽选择优化）。互不重叠的估算合计 **1749–2499 LUT、2766–3106 FF、849 D，约440–645个理想CLM等效站点，其中约213 CLMS；增加24 DRM、0 APM**。不代表保证释放的PnR站点；其中确定结构主项为01，其余必须逐项综合/时序复核，未经S决策不得实施02/04。
- 若仅允许I类，优先05/06，估算0–200 LUT、45–65 FF、0 D，约6–59站点等效，收益可能为零；冻结CPU的03/07/09与08不计上述合计。08可解决NPU局部CLMS压力，但可能增加CLMA，须独立比较。
- 确认无直接可省项：DDR适配器（`fpga/rtl/edrv32_fpga_ddr_adapter.v`纯组合、无流水/缓冲，H中被展平，收益0）；u_ddr3为生成IP不评估内部；TMDS已OSERDES、fabric LUT/FF=0；RGMII仅1 LUT/19 FF且有IO时序/hold风险，保留一拍收发隔离；ROM/SRAM已20 DRM且软件链接/热点代码使用；reset_ctrl、sys_xbar、APB桥/译码、CLINT、I2C、UART无证据支持无代价裁剪。
- 复现：`git show 7153d605:tasks/win/20261108-70-soc-npu-post/artifacts/resource_hier.txt`，同法读取HF/result；`rg -n 'edrv32_(async_fifo|async_fifo_ram|axi_async_bridge|axi256_async_bridge|apb_async_bridge)' rtl --glob '*.v'`后沿full_top可达层次计数；`rg -n 'mem_xbar_snapshot|engine_perf|ETH_PERF|plic_set_priority|mhpmevent' sw --glob '*.[ch]'`结合上述调用点。未运行Yosys、仿真或访问仿真虚拟机；纯文档不适用RTL lint/回归；`git diff --check`通过。
