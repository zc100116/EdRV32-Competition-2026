# NPU 后处理 RTL（2026-11-08）

基线 fa3f9312（核心 RTL 同派发基线 65ea90ac）；实现提交为本报告所在提交，`git log -1 -- docs/reports/2026-11-08-npu-post-rtl.md` 可取得。
工具：Yosys 0.70+219 / 5053d0e26、Verilator 5.020；目标 PG2L200H-6 FBB676，新增逻辑按 200 MHz/5 ns 预算，Linux 代理不替代 PDS。
结构：字13译码 POST_KIND/HEAD_ID，字14表地址；寄存器0x114–0x130实现IDLE配置、DOORBELL清零和完整SOFT_RST；conv_write在结果RAM出口携带标签分流，按EN/RAW_CLS_WRITE抑制cls DMA。
分类12级：P1输入；P2–P5两棵signed max树；P6–P8 best读/三写历史前递；P9合并写回并查概率；P10–P12两阈值/入队；plane0直接初始化。
RAM：best双bank各2048×16；候选双bank各固定2520×32；exp/probability各1024×32真双口，三个head保留到尾部；box启动先装表。
尾部：每候选四侧各单拍AXI256 gather；串行峰值/差值/查表/乘积/25-bit den/28-bit num/36-bit舍入；12个商位各三拍分段减法与寄存选择；坐标加减、stride移位分拍。
24 B连续打包并尾拍补零；最后B对应write_idle后才统一发布POST_COUNT/POST_DONE/DONE_COUNT/IRQ；ABORT排空已接受W/R/B，错误复用1/2，无新增检查。

## 写回后处理支路接口

`edrv32_npu_post`：clk_i/rst_n_i，clear_i帧开始；cls_valid_i每拍接收cls_data_i[255:0]，无ready；低/高128 bit分别为左/右像素，通道0在低字节。
标签：cls_head_i[1:0]、cls_row_i[11:0]、cls_pair_i[10:0]、cls_block_i[2:0]、cls_plane_i；pair为行内像素对，C16 plane=`{block[1:0],plane}`（0..4）。
head0/1/2固定80×48/40×24/20×12，anchor起点0/3840/4800；int8_th_i[26:0]=`{TH2[8:0],TH1[8:0],TH0[8:0]}`，prob_th_i[31:0]。
load_i开始装表，load_head_i[1:0]/load_addr_i[31:0]/box_offset_i[31:0]/box_stride_i[31:0]保持到load_done_o；post_base_i/output_base_i保持整帧。
read_req_valid_o/read_req_ready_i/read_req_addr_o请求一拍；read_data_valid_i/read_data_i返回256 bit，无返回背压；write_req_valid_o/ready_i/addr_o及write_data_valid_o/ready_i/data_o也是单拍。
tail_i开始尾部，count_o[12:0]观察内部队列条数；write_stream_idle_i表示W流排空，write_idle_i包含B栅栏，tail_done_o仅在最终write_idle后产生；stop_i/cancel_i沿用执行停止/排空后取消。
可独立例化`edrv32_npu_post_classify`：clk_i/rst_n_i/clear_i，valid_i/data_i及head_i/row_i/pair_i/block_i/plane_i为上述去cls_前缀端口；int8_th_i/prob_th_i同上。
prob_en_o/prob_addr0_o[9:0]/prob_addr1_o[9:0]发两拍查表请求，prob_data0_i[31:0]/prob_data1_i[31:0]返回；地址=`{head[1:0],raw_best[7:0]}`。
candidate_valid_o[1:0]的bit0/1对应左/右；candidate0_o/1_o[31:0]=`{zero[3:0],best[7:0],class[6:0],anchor[12:0]}`；idle_o表示12级排空，只有plane4可产生候选。

级数实测：FF→FF **6**、DRM→FF **3**（调用tools/synth/cpu_levels.py，native carry-chain-two口径）；注册DSP48按APM边界处理；原始单CARRY4逐块计数不等同此口径。
全部非时钟输入引脚扇出最大**32**（包括同步/异步复位引脚）；五份区域复位扇出分别**29/31/13/23/12**；PDS仍须检查整片布线和拥塞。
完整NPU generic LUT6：基线37567 LUT/47612 FF→42196 LUT/51210 FF，增量**4629 LUT/3598 FF**；协调者批准Linux参考上限4.7K/3.6K，PDS资源为准。
post单独generic：3403 LUT/3031 FF；XC7代理：2095 LUT/2786 FF、1 DSP48、12 RAM32M、6个DRM包装实例；Pango DRM/APM待Windows实测，不把DSP48直接当APM数量。
尾部实测：37条**14863拍**（74.315 µs@200M），5040条**2114871拍**（10.574 ms）；直接DMA模型1拍读返回、B延迟40拍，不含DDR竞争，装表不计入尾部。
5040分类连续接收**12600拍**（63 µs@200M），完整候选逐字段一致；尾部读20160 beat/写3780 beat；1–5条另覆盖所有打包余数、仅右入队、半拍选择及三head不同exp表。
新IP：ip_ram_npu_post_best×2、ip_ram_npu_post_queue×2、ip_ram_npu_post_table×2；创建步骤和端口见fpga/ip/README.md索引。

区域复制（原扇出→份数；对照移除keep的同RTL代理及迭代原网；没有额外功能复制）：
`g_payload_region.load_copy_r`256→16；`pack_copy_r[*]`最大244→16/位；`g_side.carry1_copy_r`155→8；`g_side.gather_copy_r/half_copy_r`128→8；`g_metadata.metadata_copy_r`52→4。
`u_dfl.g_bins_region.input_copy_r/initialize_copy_r`合并对照162→4+3；rotate_copy_r128→4；init_copy_r38→3、low_copy_r40→3、round_copy_r36→2；逐位选择原35→subtract_copy_r×2/select_copy_r×3，累加valid原generic56→2。
`cell_copy_r`合并对照56→3；`load_config_copy_r`46→4；`load_word_copy_r`64→2；box_offset_head_copy_r/box_stride_head_copy_r合并对照36→2；best8_r标签迭代原60→两像素各保留。
迭代原phase_stride_w38→stride_copy_r×2、读地址选择36→read_address_copy_r×2、装表地址推进35→table_advance_copy_r×2、队列bank选择33→queue_bank_copy_r；clear_queue_copy_r分count/游标区，tail_copy_r分地址区；rst_n_i合并对照108→5。

原始数据：build/npu_post/measure/{resources,levels,mapped_paths,merged_paths}.json及*.log；单元日志build/regress/smoke/unit/npu_post_*/verilator/。
综合复现：`python3 verif/unit/npu_post_tail/synth.py`（本提交保留区域复制；同时输出解除keep对照，不用于最终资源数）。
仿真/lint先`. ~/.local/opt/edrv32/env.sh`，每条命令前加`flock /tmp/edrv32-sim.lock`，-j 1：
`python3 tools/regress.py smoke --path verif/unit/npu_post_<classify|dfl|tail|empty> -j 1`：各1/1 PASS；`<...>`逐个替换目录后缀。
`python3 tools/regress.py smoke --path verif/unit/npu_<regs|conv_write|top> -j 1`：各1/1 PASS（同样逐个替换）。
`python3 tools/regress.py smoke --path verif/block/npu -j 1`：**22/22 PASS**，EN=0既有行为通过。
NET复现：`PYTHONPATH=verif/block/npu python3 -c "from run import build,simulate; from prepare import prepare_network; p,a=prepare_network('NET-02')[1]; r,t,l=simulate(build(False),p,a,'post_en0_latency94'); print(t); assert r==0 and 'PASS NB' in t and 'FAIL' not in t"`。
NET-02 latency94：725760 B逐字节PASS；**PERF0=6194664，与改前相同**；读/写512472/309000 beat；日志build/npu/yolo/post_en0_latency94.log。
`python3 verif/unit/npu_post_tail/lint.py`：edrv32_soc_top、edrv32_fpga_board_full_top的--lint-only --timing -Wall -j 1均0告警；改动10个RTL文件风格0告警，git diff --check通过。
