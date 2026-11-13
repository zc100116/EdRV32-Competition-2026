# 媒体子系统瘦身评估（2026-11-13）

范围：`rtl/media/{rnd,pix,vin,geo,disp}/` 全部 RTL，以及其 dma2d、FIFO、CDC 和 tech 包装；只评估，不改设计。
源码：`e1052afaffdbbbe188d9e8afefccc9a6cc841fd2`；与卡70源码 `ce2b4fd42edc526fa702fd08071e14b4c2a0353a` 的上述媒体及公共依赖一致。
实测基线：`origin/win/20261108-70-soc-npu-post`=`7153d605cc6c66fa7f415b22bbe8d5b40da7ff08`；原始目录 `tasks/win/20261108-70-soc-npu-post/artifacts/`（下称 A），资源取 `A/resource_hier.txt`，不是 Device Map/PnR 资源。
工具/器件：PDS 2022.2-SP6.1 build138931、PG2L200H-6 FBB676；sys/npu/mem=125/180/125 MHz，DISP像素74.25 MHz；卡70未取得布线后时序和资源。
规格：`docs/spec/{rnd,pix,vin,geo,disp,dma2d}-spec.md`；时序依据另取卡68R2审计 `2026-11-08-timing-soc-audit.md` 和 `2026-11-08-rnd-fmax-eval.md`，不混作卡70测量。

## 实测资源（子项包含在父项内，不重复求和）

|层次（SoC实例前缀省略）|LUT|FF|分布式RAM|APM|DRM|
|---|---:|---:|---:|---:|---:|
|u_rnd|16790|11312|0|68|58|
|u_rnd/u_draw|7803|5725|0|45|37|
|u_rnd/u_copy|5356|1426|0|2|4|
|u_rnd/u_alpha；u_blit|341；1033|1542；535|0；0|16；4|1；16|
|u_rnd/u_fill；u_regs|328；452|399；305|0；0|1；0|0；0|
|u_rnd/u_read；u_write|150；339|133；404|0；0|0；0|0；0|
|u_pix|5977|9763|0|18|11|
|u_pix/u_stage1；u_stage2|2595；2594|4247；4247|0；0|6；6|4；4|
|各stage/u_kernel0、u_kernel1范围|781–795|1326（每个）|0|3（每个）|0|
|u_pix/u_point1；u_point2；u_regs|195；269；266|323；470；207|0；0；0|6；0；0|3；0；0|
|u_vin|5550|7097|37|0|17|
|u_vin/g_channel[0].u_channel；[1].u_channel|967；855|1494；1493|0；0|0；0|4；4|
|u_vin/u_ch2；u_msrc；u_regs|885；541；1094|1927；593；994|0；0；0|0；0；0|5；4；0|
|u_vin/u_cam0；u_cam1；u_fmt0；u_fmt1；u_p1|72；73；158；182；415|107；107；157；157；27|18；18；0；0；1|0；0；0；0；0|0；0；0；0；0|
|u_geo|3290|3376|0|9|16|
|u_geo/u_bounds；u_range；u_coords；u_tiles|567；287；287；233|487；275；140；144|0；0；0；0|0；0；0；0|0；0；0；0|
|u_geo/u_source；u_bilinear；u_regs|252；129；429|7；78；332|0；0；0|0；9；0|16；0；0|
|u_geo/u_rd；u_wr；u_read_address；u_write_address|199；296；68；57|130；379；70；71|0；0；0；0|0；0；0；0|0；0；0；0|
|u_disp|3009|4023|0|7|8|
|u_disp/u_scan；u_regs；u_reader；u_dma|949；865；336；196|1106；785；396；139|0；0；0；0|7；0；0；0|0；0；0；0|
|u_disp/u_scan_fifo；u_scan1_fifo|184；56|351；351|0；0|0；0|0；0|
|u_disp/u_perf0、1、2、5、6（合计）|178|480|0|0|0|

## 软件核对与时序边界

- 全 `sw/` 搜索调用和直接MMIO，区分驱动能力、host测试与实际板级程序。LVGL `showcase/lvgl/draw_rnd.c` 使用 FILL/BORDER/GLYPH/BLIT/COPY，目标RGB565/ARGB8888、源A8/RGB565/ARGB8888，正常over、渐变、圆角、缩放、颜色键、recolor；ARGB离屏层不能去掉直通alpha归一化。
- LVGL本身不用A1/A2/A4、I8、翻转，但 `showcase/board/renderer.c:69–99` 的板级图形页覆盖全部；`demo/overlay.c` 用A1，两个NES `display_command.c` 用I8。**未找到整个软件树完全未用的现存RND命令/格式**；MODE1–7已在v0.5删除，不能再记节省。
- PIX `showcase/ui/page_process.c:18–19` 两级均开放1–6，`board/vision/vision.c:489–494` 原样配置；demo参数也传两级。均值/高斯/锐化/Sobel/腐蚀/膨胀不是闲置功能；删除一级必须为S。单级跑两遍需中间帧DDR和调度，不能维持规格§7连续2像素/拍及逐级1行+≤16拍延迟；单纯分时只有约1像素/拍上限，不能以720p平均带宽冒充合规。
- VIN运行调用配置CH0/CH2，未找到启用CH1；CH1是规格§1明确的完整预留写通道。cam1虽有demo尺寸初始化和PERF1读取，未找到运行选路VIN_CAM1；CH2、内存源在视觉/网口图像路径实际使用，不可删。
- 通用 `drivers/engine.c` 能读所有PERF不等于应用都读；demo `main.c`/`monitor_video.c`读VIN 0/1/3/5/6/8和DISP1，SoC SC05也读VIN3/5/8；RND6个PERF全用于LVGL基准。PIX/GEO PERF、DISP2–6未找到运行消费者；DISP0还参与BUSY内部判定，不能连内部完成计数一起删除。
- 卡68 mem域最差−0.025 ns，RND相关最差+0.088、内部+0.153 ns，GEO写控制+0.115 ns；这些是截断的top200，不能证明其他流水可删除。RND基准ALL BUSY中等待代理50.9%，提到200MHz帧率代理收益仅4.4%，先压逻辑/总线规模，不能承诺压流水后提频。
- 卡70 `A/high_fanout.txt`：cancel_region[6]=680、RND state[5]=582、blend_valid/tag[31]=519，PIX filter advance[3]=344，VIN APB地址[2]=362、DISP scan/N98=378；卡68对应cancel=684、write/N61=288、draw网77–283。减少宽选择和载荷FF才能从源头减负；直接合并局部控制副本可能加重扇出。

## 候选（按节省与代价综合排序；全部数字为结构估算，尚未综合比较）

记 `L/F/D` 为节省LUT/FF/分布式RAM，负数表示新增；新增硬核列为DRM/APM。CLM等效 `E=max(L/4,F/8)`，依据 `2026-10-31-b3f-floorplan.md` 的4LUT/8FF容量口径；它是容量代理，不是实际释放站点，打包/CE/复位/局部位置不明，实际净释放可为0；各行E不直接相加。
位置：R=RND控制/读返回区（copy DRM约坐标336,672，卡68审计）；V=VIN寄存器/APB区；G=GEO写控制区；P/D=PIX/DISP，无精确模块拥塞占比；均无证据直接位于NPU枢纽，仍会竞争中部CLM/硬核连线。

|编号/模块/改法|类|估算L/F/D；CLM等效E|新增DRM/APM|代价、依据及位置|
|---|---|---|---|---|
|M1 VIN删预留CH1及专属寄存器/仲裁输入|S|1000–1200/1650–1800/0；250–300|0/0（释放4DRM）|855/1493实测通道+约160bit配置/专属译码；不影响CH0/2吞吐，取消双路拼接能力；改VIN/SoC规格及软件寄存器窗口，验证禁用地址/帧槽/仲裁；V|
|M2 RND COPY原始行入RAM，以src/dst相对偏移做一次跨beat对齐|I|900–1800/0–64/0；225–450|0/0|现两侧256bit×5级字节移位及TAIL选择，按减少一套约1280个2:1选择（约640–1280 LUT）及TAIL/旁路选择估算；保留整行暂存和反向行序，目标维持1beat/拍；需重排首尾/读预取，时序风险中高，验证全部偏移/重叠/4KiB/ABORT，无新IP/软件；R|
|M3 PIX每kernel合并min/max归约树，按OP选比较方向|I|200–400/280–320/0；50–100|0/0|4个kernel各有两套5+3+2个8bit寄存和8次比较，互斥OP5/6共享一套，扣除方向/选择逻辑；级数/2像素吞吐不变，比较方向网有扇出风险；验证两级全部组合、零边界/停顿/丢帧，无IP/软件；P|
|M4 RND draw四项cache_data改四读口DRM副本|I|400–900/768–1024/0；100–225|16/0|4×256=1024bit存储及4路256bit四选一；四副本各1写1读，按64bit/DRM分片共16块，输出替代已有sparse_data捕获级，保守不另计后者1024FF；保持2像素/拍需同拍四地址、同步读对齐；新浅RAM IP、碰撞/替换/跨beat/稀疏缩放验证，软件无改；R|
|M5 RND draw目标载荷与alpha tag延时链转DRM环|I|−40–0/600–700/0；75–88|2/0|pipe_dst[1:9]为576bit，alpha tag[0:8]为288bit，扣指针/输出/控制；各16深、64/32bit，改同步读及弹性使能，保持原延迟/2像素吞吐；新IP，验证停顿/clear/tag逐拍对齐，不能把valid改RAM；R|
|M6 GEO bounds四路24bit移位累加乘积改APM|I|100–200/96–192/0；25–50|0/4（估算）|去4×24bit移位操作数及4路24bit累加器，保留结果/角点裁剪；20bit系数×5bit跨度需核对APM切分/内部寄存，四路并行不增加9拍setup；新乘法IP若推断不映射，验证符号/极限/帧时间，软件无改；G|
|M7 删除未用诊断PERF：PIX停顿/丢帧、GEO1–5、DISP2–6|S|350–600/800–1150/0；100–150|0/0|PIX 3×32+GEO5×32+DISP3跨域×(32+96)及mem PERF3/4、基线/比较/读译码；保留DISP0/1、所有错误上报与内部完成判定；须改规格/通用驱动诊断契约，验证回绕/软复位/CDC，吞吐无变；P/G/D；与M1专属VIN计数不重叠|
|M8 PIX取消第二级，或单级两遍DDR处理|S|2000–2594/3400–4247/0；500–649|0/0（释放4DRM/6APM）|上限为stage2实测；两遍还要DMA/帧缓冲，净额更小且多约4WH字节DDR读写/帧；删除二级组合/连续吞吐或延迟要求，改UI/驱动/规格，整条VIN实时性验证；P，与M3按保留kernel数重算|
|M9 VIN删除cam1采集前端/整形/寄存器|S|250–350/300–400/18；63–88|0/0|73/107+182/157实测及配置/计数估算；双摄功能取消、demo读PERF1和初始化需改，验证源编号/IRQ/不完整帧；V，与M1可独立但共享译码节省不双计|
|M10 DISP扫描混合S4–S6或S8–S10缩一级|I|0–30/48–96/0；6–12|0/0|按一组RGB/alpha延迟FF估算；保持逐位round255及DE/HS/VS对齐，吞吐1像素/拍；74.25MHz不代表实有余量，卡70无该路径STA，可能成为新关键路径；无新IP/软件，验证两层欠账/同步；D|
|M11 VIN DVP16×36异步FIFO改DRM|I|0–20/−50–0/36；0–5（另释放CLMS）|2/0|18×2分布式RAM实测；每36bit宽只16深，须同步读预取及边界项完整保留，面积收益可能为负，新双钟IP/CDC验证；不优先，FIFO延迟会增加；V|
|M12 VIN APB预译码并分组读选择，保持寄存器语义|I|0–100/−40–0/0；0–25|0/0|1094/994不能整体算闲置；只预期减少重复译码，不保证净面积；可用已有APB等待级，无软件/IP，验证读写等待/软复位/非法地址，重点地址扇出362；V|

## 结论与不重复检查项

推荐先做保持功能的前5项：**M2 → M3 → M6 → M5 → M4**；M4放最后因16个浅DRM副本占列且改动大。五项互不重复，合计**估算节省1560–3300 LUT、1744–2300 FF、0分布式RAM，新增18 DRM/4 APM，容量等效390–825 CLM**；这是方案目标区间，不是保证下限，需逐项ADS再看整片PnR实际站点/扇出/时序。
若用户愿意改规格，优先M1：单独可省约1000–1200 LUT/1650–1800 FF并释放4DRM；M7次之；M8虽最大，但会删除UI已用组合或改变实时性，不应作为“免费合并”。本范围无F项；不触碰CPU/cache。
已核对无直接可删项：RND decode/fill/round_row/coverage与BLIT双缓冲（功能已用、乘法已APM）；PIX point1 Gamma已3DRM、point2及四行RGB888存储维持逐级精度；VIN CH2量化已化简为c/2、line/FIFO均已DRM；GEO双线性9APM/源缓冲16DRM及range/coords/address；DISP双层/卷轴/TMDS/时序均在用。
FIFO深度：VIN写/内存源512项、DISP两层512项均已DRM，缩深主要省DRM而非CLM，且无最长P1/P0阻塞证据；GEO八bank为并行采样，不能按总bit数合成单口；不提出无依据的缩深。dma2d的32bit地址/stride、16bit行字节/12bit行数是规格契约，pending计数按OUTSTANDING裁剪；写hold的288bit用于AXI停顿/ABORT保载荷，不可直接删。
复位审查：媒体大载荷/存储均已分离无复位；规格可见配置/帧计数及GEO tile u/v属于配置或控制，不能冒称数据复位浪费；reset_copy和局部advance/bank副本用于当前近临界网，不按副本位数直接计收益。寄存器字段已有PIX 266/207、RND452/305、GEO429/332，合并不同影子/当前/释放字段会破坏帧边界契约；只在M1/M7/M9明确删功能时计入对应寄存器节省。
复现：`git show 7153d605:tasks/win/20261108-70-soc-npu-post/artifacts/resource_hier.txt` 及同目录 `high_fanout.txt`；`rg -n 'rnd_|RND_|pix_|PIX_|vin_|VIN_|engine_perf' sw --glob '*.[ch]'`，再读调用所在板级程序与上述RTL。没有运行Yosys/PDS/仿真、未访问仿真机；仅报告改动，RTL lint/回归不适用；`git diff --check`通过。
