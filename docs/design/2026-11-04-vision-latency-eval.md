# 实时识别端到端延迟与后处理硬件评估

## 背景和问题

- 输入代码 commit `e54e471ea3a5292f16d430c610c58f963a08ebae`；本记录和剖析原型随本提交保存。按协调者追加要求，以最终框硬件输出为主，不评估 NPU 算子提速。
- **实测 R3**：结果分支 `8a2b0c03614bc32f435271738d03a6b797f83c6b` 的 `tasks/win/20261103-54-showcase-p5-board/r3_result.md` 及同卡 `artifacts/uart/{r3_vision_excerpt.txt,r3_latency.log}`；稳定示例 npu≈41.7、copy≈1、wait≈19、decode≈23.6、post_span≈58、gui≈41、period≈61、e2e≈175 ms，app≈46%、gui≈23%、comm≈2%。
- R3 照片/结果记录：通信/应用/GUI 最长单步分别 2097/1512/117233 µs；130 条日志的**窗口均值范围实测** e2e 132.2–278.4、period 49.5–101.7、post_span 43.3–98.5 ms，不能当逐帧 WCET。R4 已禁后处理向 GUI 让步并缩小框失效区，仅有用户帧率改善反馈，尚无数字。

## 约束

- 依据 `docs/spec/{npu,vin,pix,geo,disp,edrv32-soc,cache}-spec.md`；只产出评估原型、记录及视觉时间戳，不改 RTL、规格、编译模型或调度行为；未访问暂停的 VM。
- 本文硬件面积、时延和移植工作量均为**估算**，公式及假设随段列出；CPU 按 125 MHz 举例，板上实际频率由 SYSCTRL 读取。Spike 只提供退休指令数，不模拟 EdRV32 双发射、cache、DDR 或中断周期。
- 当前数值契约：5040 anchor、每格 80 类、先阈值 0.25、Q8 DFL、确定性分数/anchor 排序、按类 IoU >0.45、最多 100 框；UI 默认 0.50/白名单仅过滤展示。候选 ≤64 **尚不是规格**。

## 可选方案

### 一帧链路与 e2e 口径

| 段 | 时间及依据 | 串行/重叠 |
|---|---|---|
| 曝光、滚动读出 | **估算** nominal 30 fps，Tcam=1000/30=33.3 ms；一帧读出约一周期，曝光另加 Te（自动曝光，未取得）；事件等下一帧还可能加 0–Tcam | 不在现有 e2e；与上一帧计算重叠 |
| VIN CH0/CH2→DDR | **估算** 数据量 CH0=1280×720×2=1.843 MB、CH2=640×384×4=0.983 MB；理想总服务时间 2.826 MB/4 GB/s=0.707 ms，不等于读出后再花此时间 | 流式随读出写入；最后 B 返回才完成，尾延迟/竞争待测 |
| PIX/GEO 预处理 | 识别输入走 VIN CH2 2×2 平均/letterbox/量化，已包括上一行；GEO=0；完整板 PIX 为 bypass，VRN 不触及 PIX/GEO；PIX 规格冲刷上限 (1280+32)/125M=10.5 µs（**估算上限**） | CH2 不经 PIX，不串接一次 GEO 帧任务 |
| 配对→NPU 启动 | **估算残差** 175−41.7−19−58−41≈15.3 ms；含 CH0/CH2 同 frame_id 配对、等 NPU 空闲和 app 被调度 | 与上一帧 NPU/post/GUI 重叠；非固定 FIFO 深度 |
| NPU | **实测** 41.7 ms，软件启动时间戳→NPU DONE ISR | 可与上一帧 CPU 后处理重叠 |
| 完成派发、OUTPUT 复制 | **实测** wait≈19 ms 是 DONE ISR→post_start，**已含** copy≈1 ms；复制用同步 RND 搬 725760 B 到 cached POST，含 cache 维护/硬件等待 | 前一 post 未完成也会挡新结果复制；复制完成后启动下一帧 |
| decode、排序、NMS | **实测** 23.6、0.0、0.0 ms（后两者是 0.1 ms 精度）；post_span≈58 ms，差≈34.4 ms 为片间等待及服务开销 | CPU 各阶段串行，下一帧 NPU 并行 |
| 发布、界面取结果、LVGL | **实测** gui≈41 ms 是 publish→L1 SWITCH1 ISR，包含 GUI 排队、更新/绘制、cache clean、等待 VBlank；不是纯绘制时间 | L0 相机图像与框独立提交，未保证同一来源帧 |
| DISP 合成和扫描 | **估算** 1650×750/74.25M=16.667 ms；提交→帧锁存 0–16.7 ms 已含 gui；锁存后到指定像素另约 0.667+y×22.22 µs+x/74.25M | 硬件双层合成随扫描；面板内部延迟未测，未包含在 e2e |

`vision.c:vision_irq` 的 `vin_done_tick[0]` 是 CH0 最后写响应后 FRAME IRQ 的 **ISR 软件时间**，经 `image_tick→npu_vin→timing.vin` 传递；不是曝光、SOF 或 CH2 完成。终点是 `platform.c:disp_event→vision_gui_presented` 的 L1 SWITCH1 ISR，即 VBlank 内锁存/释放 Surface，**不是最后一个像素显示完成**。
对同一有效帧：e2e = (start−VIN0) + npu + wait + post_span + (handoff−nms_end) + gui；copy、decode 均为子项，不能重复相加。
因此 175 ms 与 npu+decode+copy=66.3 ms 的约 109 ms 缺口主要是上述四级等待，不是缺失的硬件运算；窗口计数分母不同、未展示结果会覆盖，所以不能把各窗口均值强行凑为同一帧。
`period` 是 NPU 两次启动间隔；理想流水周期=max(Tcam,NPU+copy,CPU每帧总工作)，串行帧龄则各依赖段相加。无 GUI 阻塞时 NPU 极限≈1000/(41.7+1)=23.4 fps。

### 软件对照（约 20 行）

真实输入使用 COCO128 `000000000009.jpg`，将已入库的卡 09 模型/描述符执行一次 NPU 参考模型，非随机伪造 OUTPUT、非上板捕获；使用生产 `post.c` 的分片流程与 `sw/lib/yolo_tables.c`。
工具：xPack GCC 15.2.0，`-O3 -march=rv32im_zicsr -mabi=ilp32 -fno-strict-aliasing`；Spike 1.1.1-dev；原始输出在 `build/vision-latency/{baseline,packed}.txt`，前 12 行依次为 decode/调用数、sort/调用数、NMS/调用数、class、DFL、候选数、框数、sort 比较数、IoU 比较数，其后为 EDDT 六字段。

| 步骤 | 基线实测指令 | packed 实测指令 | 估算周期（基线，CPI=1–3） |
|---|---:|---:|---:|
| decode 总计，636 次分片 | 1,235,564 | 953,351 | 1.236–3.707 M |
| 其中类别扫描 | 1,036,778（83.9%） | 713,154 | 1.037–3.110 M |
| 其中 DFL | 30,439（2.5%） | 31,105 | 0.030–0.091 M |
| decode 其余/分片开销 | 168,347 | 209,092 | 0.168–0.505 M |
| 排序 / NMS | 11,766 / 7,853 | 相同 | 0.012–0.035 / 0.008–0.024 M |

这些是插入 `minstret` 读数、抽出扫描函数后的指令实测，包含打点开销；各子项不含调用者累计开销，不能当原封不动固件周期。37 候选→5 框，270 次排序比较、54 次 IoU；两版及独立 `yolo_post_ref.py` 的全部检测字段一致。
原型每次从 4 个 signed INT8 字节构造并行阈值命中掩码；未命中不取 argmax，命中再跑原 argmax，保留首次同分 anchor/class 规则。仅用于本模型正阈值 103/105、C16 对齐；不加入通用参数/兜底。
**估算**按 R3 decode 校准 k=23.6ms/1,235,564≈19.1ns/指令（等效 CPI≈2.39），原型剩 18.2 ms、省 5.4 ms；O2 板端、O3 原型和场景不同，此为投影，软件对照目标 18–24 ms，未证明更低极限。
原软件已先 INT8 阈值、后 DFL，exp/sigmoid 已查表，新增收益均为 0；白名单提前处理会改变目前“完整原始结果+UI过滤”契约，不能计入保真加速。
32 KiB、2 路、32B 行的 D$ 放不下 403200 B 类别；至少 12600 个类数据行/帧，稀疏框另读。5 平面并不天然每次冲突失效；packed 少 load，不会减少必需类字节/冷缺失。按每 miss 10–50 周期估算 1–5 ms，可观测 cache HPM 后再判断布局收益，不能与 5.4 ms 直接相加。

### 后处理硬件主方案（约 50 行）

**资源基线实测**：`42c34430d368ecd1bfb4c51009680e9ca9417567`，卡 48 `artifacts/F-cpu125m-r2/resource_summary.txt` 的 Device Utilization Summary：LUT 87151/159800、FF 96124/319600、DRM 277/415、APM 372/740；余量分别 72649、223476、138、368。
同目录 `resource_hier.txt` 的综合层次：CPU 15585 LUT/18 DRM，NPU 16469 LUT/122 DRM/266 APM，RND 16802 LUT/58 DRM/68 APM；汇总阶段口径略异，不混加层次与总量。以下面积为新增预算，非综合结果，也不证明时序可收敛。
共同入口选在 `edrv32_npu_writeback` 的量化/残差后结果 RAM→`conv_write/write_dma` 出口，按描述符 OUTPUT 区间辨认六个检测输出，并保留 frame/head/cell/plane 标签；不在卷积累加器内改算子。
类别 C16 平面不是一拍完整 80 类：每个 beat 是两个 anchor×16 类；用 16 类 max 树×2，再更新每格 best/class，5 平面完成后阈值/压缩，跨 head 比较分数必须用各 head 的 probability_q24，不能直接比较 raw INT8。
最大 head 3840 格，best+class 约 2 B/格=7680 B；DRM 为36 Kibit（见 `fpga/ip/ip_ram_vin_wfifo.md` 及资源报告），双anchor分bank和读写口预算 2–4 DRM，另加结果 FIFO/标签。流式每拍接受一个 256bit beat，类别共 403200/32=12600 拍=0.101 ms@125M，树流水约 6 拍；若带宽满足可隐入原头输出，不额外串行扫全网。

| 方案 | 完成时输出/CPU 剩余 | 新增资源估算 LUT / FF / DRM / APM | RTL及验证规模估算 |
|---|---|---|---|
| (a) max+阈值+候选压缩 | 候选 anchor/class/probability（8 B），CPU 稀疏读框、DFL、排序、NMS | 800–1800 / 600–1600 / 6–10 / 0 | RTL 500–900 行；1 个单元+NPU 写回集成，约 1–2 人周 |
| (b) 再加 DFL | 24 B Q8 框候选，CPU 排序/NMS/显示坐标转换 | 2000–4000 / 1500–3000 / 10–18 / 2–4 | 在(a)上加 600–1000 行；定点边界+DDR gather+集成，额外约 1–2 人周 |
| (c) 再加确定性排序/NMS | 最终 ≤100×12 B EDDT，CPU 读结果、发布 UI | 4500–8500 / 3000–6500 / 44–54 / 4–8 | 在(b)上加 1000–1800 行；排序/IoU及端到端逐字段对比，额外约 2–3 人周 |

(a) **低风险实现**保留 box C64 的 DDR 写回 5040×64=322560 B；类别不再写 DDR，最终 head 完成才将少量候选写 DDR。CPU 不再做整块 RND copy，维护/读取候选及所需 box cache 行即可，原 725760 B 全量 OUTPUT 不再存在。
37 候选时输出仅 296 B；CPU 时间**估算**为 DFL≈23.6×30439/1235564=0.58 ms，加稀疏读取/排序/NMS/驱动后约 1–3 ms，decode 比 R3 省约 21–23 ms，比 packed 软件再省约 15–17 ms。
不能声称(a)完全不写 raw box：box 分支先于 cls 分支，没得到筛选条件时必须保存 box，完全片上保存最大 head 原始 box 要 3840×64=245760 B；按64bit×512的4KiB有效容量/站点与bank取整约60–64 DRM，连(a)约66–74/138余量；虽放得下，但显著多于保留DDR的6–10 DRM。
(b) 采用(a)流式类别筛选，网络结束后 DMA gather 候选的 4×16 bins；每侧串行 16 拍找峰、16 拍 LUT 求和、约 40 拍无符号除法，共 288 拍/候选。要求与软件完全一致的正舍入 `(num×256+den/2)/den`。
37 候选：10656 拍=0.085 ms，加 DDR 读取2368 B、地址/突发开销，**估算尾延迟 0.1–0.3 ms**；5040 全过阈值则 1,451,520 拍=11.61 ms，非固定 0.1 ms。DFL 的 LUT 差值索引无零点，3×256×21 bit≈2 KiB，另有概率 LUT 和 FIFO，因此预算比(a)多 4–8 DRM。
CPU 仅 270 次比较和54次 IoU，按本次退休指令与 k 投影约 0.38 ms，再加搬运/转换**估算 0.2–1 ms**；相对(a)只再省约 0.5–2 ms，但为(c)完整最终结果接口做准备。
(c) 首选保留当前**最多5040候选**语义：片上 5040×24=120960 B；按192bit分6个32bit银行、每bank深度向上取5×1024，约30 DRM，加(b)及排序临时/FIFO共44–54 DRM，仍在138余量内（余84–94 DRM）；不需要装下完整725KB OUTPUT。
使用原 heapsort 规则（probability 降序、anchor 升序），class-aware NMS 保留未裁剪 Q8 框，最后映射/裁剪到1280×720并输出 EDDT。复用整数乘法器计算面积；IoU 不能先量化为8位或用 UI 过滤后的框代替。
**估算拍数**：37 候选排序 ≤2×37×ceil(log2 37)=444 次比较，2拍/次约888拍；95次类比较、54次IoU按共享乘法器12拍/次≈743拍；DFL+排序/NMS合计≈12287拍=0.098 ms，连DDR/写结果预算0.2–0.5 ms。
保守高候选估算：5040 候选 heapsort ≤2×5040×13×2=262080拍；NMS最多100×5040次IoU×12=6.048M拍；加DFL总≈7.762M拍=62.1 ms。这是所提微架构的粗上界，未含DDR停顿；恶劣场景不能承诺24fps。
三者的后处理若在整网后执行并纳入 DONE，就会延长 NPU 可见时间；(a)流式尾巴微小，(b)/(c)典型增加0.1–0.5ms，高密度则明显拖慢下一帧。可与下一网并行需独立 box 区/候选 bank 和独立完成事件，不能只改 DONE 含义而保持原软件不变。
**≤64候选版(c)**可把候选 RAM降到约1 DRM，总约13–23 DRM，排序/NMS各≤1536/4096次比较（≤64结果），按2/12拍估算尾处理≤0.57ms，再加DFL≤0.15ms；是便宜的有界方案，但本帧37不能证明全部摄像场景都≤64。
若只保留top64再NMS，会丢掉“高分重复框被抑制后应保留的第65名”，不等价现有参考；若规格明确64是合法输入上限，则超限应明确报错，不能静默截断。本任务不引入该新限制，须另行确认规格/精度后再选。
**DDR节省**：三种低风险版都不写403200B类别；(a)另写8C、(b)写24C、(c)写12K B（C=候选、K=保留）。37/5例中净少写约0.403 MB/帧，即×24≈9.67 MB/s；raw box 0.323 MB/帧仍在DDR。
共同还取消725760B的RND读+写，即1.452MB/帧×24=34.84MB/s，并取消CPU全量类别读取约9.68MB/s；含这三项合计约54MB/s，不能把节省带宽直接换成等比例NPU加速。典型(c)只读回60B框，最坏100框1200B。
**完全不写OUTPUT的变体**：可将独立的cls末层提前到box末层之前，再流式只接收命中格的box；需要编译器/描述符次序与标签协议调整，并以全图参考验证一致，不是现有流序上免费删除DMA。
或先对所有box做DFL，只缓存每格4×12bit距离：最大head 3840×6=23040 B，48bit分两bank、深度取整约8 DRM，再等class结果；比60–64DRM raw缓存便宜，但全5040格都做DFL。串行设计需1.45M拍=11.6ms，局部输出突发可能拖住NPU，不能用整网41.7ms证明不会反压。
上述无DDR版若要求满速无反压，需多路峰值/LUT、流水除法或更大缓存，面积另做吞吐综合评估；本次不把它纳入低风险资源数字，也不承诺省掉头写回就省下11.6ms。
验证共同以 `tools/npu/yolo_post_ref.py` 为逐字段 oracle：真实帧、全低/全高阈值、跨head同分、DFL极值/舍入、IoU=0.45边界、多类不抑制、100框截断；检查DDR反压、plane/row/half-tail标签、结果完成/IRQ和前后帧隔离。
(c)额外覆盖5040候选、heapsort同分顺序、抑制链；64版另需被批准的超限语义。(a)/(b)比较完整候选和最终框，(c)直接比较EDDT，不以截图“看起来相同”验收。以上是后续验证工作量评估，未修改 testplan。

### 硬件化后剩余调度与 RTOS（约 20 行）

现有 comm>app>gui 是固定优先级协作调度，IRQ可打断任务、**任务不能抢占任务**；`sched_defer_for`只在GUI就绪时把app延迟1ms，并不限制一次GUI步长。R4后post期间不主动让给GUI，但已经开始的GUI仍可挡app。
让出粒度：post 每8 anchor/单heap根/16 NMS比较返回；一次 `application_step` 先 `vision_service()`、后 active->step()，视觉可能服务两次；RND同步等待用 `sched_wait_flag`，只服务IRQ/WFI，不让另一个任务运行。
R3 的单步最长不是WCET；通信还有UART接收while及16KiB输出队列的同步腾挪，GUI `lv_timer_handler` 没有时间预算，故当前**没有可证明的有限最坏帧延迟/抖动，属于尽力式软实时**。实测窗口e2e摆幅146.2ms已远大于一个NPU周期。
输入端保留最新匹配CH0/CH2，没有积压整条FIFO；仍可能因GUI超一个33.3ms帧周期导致VIN DONE寄存器/IRQ位合并，需核对 frame_id 和丢帧，而非解释为队列深度固定。
CPU负载100−(46+23+2)≈29%为空闲/计账余项（实测系统窗口约25%空闲），`sched_wait_flag`内WFI从任务busy扣除，不能由空闲推断服务期限有保证。
硬件(c)消除的是每格/每候选post服务及725KB复制，**没有消除每帧VIN输入选择、NPU doorbell、完成通知和GUI发布**；现有NPU描述符协议并不自动追踪VIN环。
不上RTOS的最小排程改进：DONE ISR只记录结果/唤醒高优先服务，服务读少量框后立即提交最新匹配输入；GUI仅新结果刷新框，统计区降频，LVGL绘制分片或规定单步预算，例如≤5ms（目标，尚未实现）。
不建议把同步 `showcase_rnd_run` 或整个后处理搬进 ISR：会延长IRQ屏蔽且与GUI/RND所有权冲突。要让CPU完全退出逐帧NPU调度，还需VIN→NPU硬件帧序列器、slot_busy所有权/完成握手的新规格，另立任务，不由“后处理硬件化”自动获得。
理想(c)后按输入phase≤33.3、NPU≈42、服务≤2、GUI≤8、VBlank≤16.7ms估算，VIN起点e2e上界目标≈102ms；这依赖每段预算成立，高候选62ms尾巴时不成立，当前117ms GUI也不满足。
FreeRTOS抢占可使NPU服务不被117ms GUI任务阻塞，但不减少单核总CPU工作、NPU41.7ms或VBlank；硬件(c)后主要矛盾仍是长GUI与输入交接，不是调度器运行成本。
LVGL需单GUI任务所有权，其他任务以结果消息交接；若到处用同一把LVGL mutex，长GUI仍会阻塞调用者（[LVGL官方线程说明](https://lvgl.io/docs/open/9.5/integration/overview)）。
RISC-V移植涉及CLINT tick、PLIC外部IRQ、独立ISR栈、上下文与原子临界段、启动/heap、RND/DISP所有权及原三任务唤醒；估算项目适配500–1000行，约1–2人周加回归，不含引入内核源码（[FreeRTOS官方端口说明](https://compatibility.freertos.org/Using-FreeRTOS-on-RISC-V)）。
**估算开销**：内核/port ROM约12–24KiB；4任务栈×2–4KiB+ISR栈2–4KiB+TCB/队列约2KiB=RAM12–22KiB，不含现有LVGL堆和帧缓存。
切换保存/恢复约64个word访存，加100–300条调度/入口指令，以CPI=1–3、125MHz估算1.3–8.7µs，含cache预算约2–12µs；2000次切换/s约0.4–2.4%CPU，tick另算，均需板测。
中断响应受MIE屏蔽最长段+总线/取指等待+陷入入口决定，抢占只改善任务响应；当前无屏蔽段测量，不能宣称上RTOS就有确定的µs中断上界。
NES需保持输入/60Hz渲染期限及独占显示流程；CoreMark需停无关tick/任务或记录抢占成本，才能与原裸机基线比较；RTOS不会提高分数。建议本轮**不上RTOS**，若GUI无法切片且有明确应用期限，再引入抢占。

## 决策

推荐目标为 **(c)保留5040候选、raw box留DDR、最终EDDT输出**，先完成(a)/(b)作为可独立验证的里程碑；不先砍到64、不先追求零OUTPUT写回。44–54 DRM/4–8 APM预算可容纳，换取CPU只读少量框；若只追求近期低风险，(b)已把CPU后处理压到约1ms，(c)价值在自主完成与接口简化而非本帧NMS省时。
组合最小输入交接服务+新结果驱动GUI：**估算典型目标**周期≈max(33.3,41.7+0.5,CPU总工作)=42.2ms≈23.7fps；VIN起点e2e≈15+42.2+1+8+8.3=74.5ms，目标75–105ms；曝光到像素还须加Te/读出约33.3ms和0.7–16.7ms扫描，不能标成同一e2e。
(c)CPU估算=(硬件后服务/杂项3–7ms+GUI5–8ms)×23.7/1000+comm2%≈21–38%；软件packed对照为(18.2+其余约7.1+GUI5–8)×23.4/1000+2%≈73–80%。这些工作预算都需实测，不是R4预测值。
板测必须确认：新增三段等待、CH0/CH2 frame_id与丢帧、曝光/读出、GUI纯绘制与VBlank、cache miss和MIE屏蔽、候选数量分布/拥挤最坏场景；硬件需综合/布局及吞吐反压验证，面积估算不能替代PDS。

## 影响

仅改 `vision.c` 时间戳累计和UART字段，新增原型在 `tools/npu/eval/vision_{frame,profile}.py`、`vision_profile.c`；无RTL/spec/testplan/FPGA改动。未来硬件需单独确认 npu-spec 结果接口/DONE语义、编译器输出元数据、驱动/cache所有权及验证方案。
UART保留原 `vision ...` 行，每秒追加 `vin_wait=<ms> dispatch=<ms> take=<ms>`（0.1ms）：分别为所选帧VIN0 ISR→NPU启动、NPU DONE ISR→copy开始、publish→首次 `ui_data_vision`；`wait−dispatch−copy`为启动/初始化等余项，`gui−take`为取结果后的绘制/提交/等锁存。前两项按post完成帧平均，take按展示帧平均；不新增调度分支/恢复路径。
复现先 `git submodule update --init`，再 `. ~/.local/opt/edrv32/env.sh`；原型命令分别只执行一次有效测量：
```sh
flock -s /tmp/edrv32-sim.lock env OPENBLAS_NUM_THREADS=1 OMP_NUM_THREADS=1 ~/.local/opt/edrv32-py/bin/python tools/npu/eval/vision_frame.py ~/.local/share/edrv32/npu/coco128/images/train2017/000000000009.jpg build/vision-latency/output.bin
flock -s /tmp/edrv32-sim.lock python3 tools/npu/eval/vision_profile.py
make -C sw PROGRAM=showcase -j 3 > build/vision-latency/showcase-build.log 2>&1
```
验收：两版Spike/独立Python EDDT逐字段一致；showcase上述构建一次通过、无warning/error（视觉源码使用-Werror）；`git diff --check`通过。仅C/Python/文档变更，Verilog风格/lint不适用。工具初始化期间缺失子模块与裸ELF链接/HTIF可见性问题均已明确报错并修正，没有形成有效性能样本或使用兜底。

## 状态

讨论中：本记录提出硬件路线与目标，未批准新增硬件接口或64候选限制；新增UART待协调者下发上板确认。
