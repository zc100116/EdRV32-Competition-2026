# YOLOv8n 共享执行器与上板节点

## 当前结构

最终执行路径使用 `edrv32_yolo_v8n_exec`：一套 512 逻辑 MAC/周期的卷积组，以及 C16 残差 DMA、5×5 maxpool DMA、2× 最近邻上采样 DMA。四类操作按命令独占同一个 256-bit AXI master，卷积组只例化一次。`edrv32_yolo_c2f` 与 `edrv32_yolo_sppf` 是独立的层序验证封装，不在最终共享执行器内例化；否则会复制 MAC 阵列。

卷积特征图保持 `[C16 平面][行][相邻像素对]` DDR 布局。上采样读入一条 C16 源行，水平复制每个像素并将输出行写两次；输入宽度支持到 40 像素。SPPF 池化依次处理 C16 平面，片上缓存最多 20×12×16 byte 的一个平面，对 5×5 窗口按有符号 INT8 求最大值，边界以 -128 填充。池化每个邻域采样使用两个时钟，避免多读端口平面缓存；在 150 MHz 下，实际 P5 20×12、C128、三次池化的纯采样约 288,000 周期（1.92 ms），DDR 读写与调度另计。两类 DMA 的 AXI burst 均不超过 16 beat，并在 4 KiB 边界拆分。

按 [Ultralytics YOLOv8 配置](https://github.com/ultralytics/ultralytics/blob/main/ultralytics/cfg/models/v8/yolov8.yaml) 与 [C2f/SPPF 实现](https://github.com/ultralytics/ultralytics/blob/main/ultralytics/nn/modules/block.py)，C2f 封装覆盖隐藏通道 C16/C32/C64/C128、一个或两个 bottleneck，以及 backbone 带 shortcut、neck 不带 shortcut 的形态。SPPF 封装验证 C256→C128、连续三次 5×5 maxpool、四组 C128 免拷贝拼接、C512→C256。固定层序控制器现已连接一套共享执行器；两个早期层序验证封装不会同时例化到整网顶层。

## 仿真结果

| 测试 | 覆盖 | 结果 |
| --- | --- | --- |
| 首个 C2f | C32→C16 隐藏通道、1 个 bottleneck、shortcut、激活表配置 | PASS；736 MAC beat |
| 双 bottleneck C2f | C32 隐藏通道，分别带／不带 shortcut，逐 beat 检查四组 workspace 和最终输出 | 两种均 PASS；各 2944 MAC beat |
| 2× 上采样 | 小尺寸和实际 P4→P3 的 40×24 源尺寸、两平面、4 KiB 拆分 | 两种均 PASS |
| 5×5 maxpool | 有符号数据、边界、20×12 平面、4 KiB 拆分 | 两种均 PASS |
| SPPF | 两次卷积与三次池化，逐 beat 检查 32 个 workspace 平面和 16 个输出平面 | PASS；10240 MAC beat、10624 读 beat、768 写 beat |
| 共享执行器 | 卷积→残差→池化→上采样，单一 AXI master | PASS；24 MAC beat、76 读 beat、96 写 beat |
| 完整板顶行为仿真 | 150 MHz AXI CDC→125 MHz 256-bit interconnect→DDR adapter/UI，背景 master 同时读 | `YEXE PASS`；24 MAC beat、76 读 beat、96 写 beat、背景读 1184 beat，最长服务间隔 18 个 DDR 周期 |

故意翻转最终输出第一个 DDR beat 的一位，板顶行为仿真输出 `YEXE FAIL`、`ERR=00000010`、`LOC=00000000`、`GOT=02020203`、`EXP=02020202`，证明读回比较与串口定位路径生效。串口助手的八条观测规则已通过本地 API 更新为新顶层的 `YEXE/CNV/POL/OTH` 格式。

旧 `edrv32_pango_200h_yolo_ddr_top` 的板顶行为回归仍通过。共享执行器顶层已完成布局布线和板级自检：YOLO 150 MHz WNS +0.151 ns、DDR 125 MHz WNS +0.626 ns、APM 257/740、DRM 60/415；串口报 `YEXE PASS`、`ERR=0`。这仍是小尺寸合成数据自检，不能外推整网帧率。

## 上板验证

在 PDS Tcl 控制台设置：

```tcl
set EDRV32_TOP edrv32_pango_200h_yolo_exec_top
source import_sources.tcl
```

Device Map 前在 GUI 中确认并保存相同的 Top Module。复用现有 `yolo_pll`、`yolo_weight_ram`、`yolo_activation_ram`、`ddr` IP；`clock.fdc` 与 `io.fdc` 沿用原有时钟和引脚约束。新顶层串口输出 `YEXE PASS/FAIL MAC=... RD=... WR=... CYC=...`、`YDBG ...`、`YPRF CNV=... POL=... OTH=... ARW=... WWR=... BGR=... GAP=...`。`CNV/POL/OTH` 分别是卷积、池化、残差加上采样期间的 150 MHz 周期数。期待自检计数 `MAC=0x18`、`RD=0x4C`、`WR=0x60`；背景读取服务量和周期数随真实 DDR 变化。

这次上板主要确认新增平面缓存、四路操作选择与原 DDR 通路共存时的 APM/片上 RAM 占用、150 MHz 时序，以及持续背景访问下是否仍能完成自检。当前自检仍使用合成数据，没有对真实权重、量化标定、Detect 解码与 Detection META 做板级验证，因此自检 PASS 只表示操作数据通路正确。

## 临时串口模型装载

`edrv32_pango_200h_yolo_exec_top` 在原有 `YEXE/YDBG/YPRF` 自检报告发送完毕后开放 UART RX。`scripts/yolo_serial_pack.py` 只生成传输文件，不打开串口；由第二代串口工具的「发送文件」按钮或 `/api/file/send` 发送，接收回执仍显示在同一个工具里。传输文件以 `YCFG` 开始，后接 32-bit little-endian 的 DDR 基址、补齐后的总字节数及镜像 CRC32；后续每包为 `YM`、16-bit 序号、16-bit 长度、最多 1024 字节内容、32-bit CRC32。CRC 覆盖序号、长度及内容，镜像与包长度均补齐到 32 字节。配置和每包后放 32 个零字节，给板端 DDR 写入和回执留出时间。串口工具按原始字节连续发送，不解析或等待回执。

回执是文本行：`YR0000` 表示准备就绪，`YAxxxx` 表示接收一包，`YNxxxx` 表示该包未接收，`YDxxxx` 表示整镜像通过，`YExxxx` 表示致命错误；四位十六进制数是下一期待序号。每行以 CRLF 结束。连续文件发送无法自动重传；出现 `YN` 或 `YE` 时应取消发送，复位后重新传输。发送文件完成还不代表镜像通过，应以 `YD` 为准。

串口装载器按包暂存内容，校验通过才发起 256-bit AXI 写；最多 16 beat 一次突发，在 4 KiB 边界拆分，并等待每次写响应。重复包只回执不重写。全部字节写入且整镜像 CRC32 正确时才给出完成状态。它在自检完成后复用原有 AXI CDC 和 interconnect master，不增加卷积 MAC 或 DDR master。串口打包脚本只接受**已转换为本执行器格式**的二进制镜像；`.pt` 权重不能直接作为可运行镜像。

串口装载器支持一轮完成后继续发送新的 `YCFG`，可以在同一次上电中分别写模型区和输入图像区；仍识别上一包的重传，以便补发丢失的完成回执。两个 32 字节区域连续装载的 UART RX、回执和 AXI 写入已通过独立仿真和完整板顶行为仿真，完整模型及图像的实体板装载见下文。

`tb_yolo_serial_dma.sv` 覆盖坏包、重发、跨 4 KiB 拆分、写响应错误和 DDR 字节比对；`tb_yolo_exec_board.sv` 的 `TEST_SERIAL_LOAD` 分支覆盖实际 UART RX、原自检、AXI CDC、DDR 模型及串口回执。两组行为仿真通过。2026-09-24 在 COM7 上通过串口工具 API 发送 122 字节测试文件，板端返回 `YR0000` 和 `YD0001`，说明一包数据写入后整镜像 CRC32 校验通过；板上尚未独立读回并比较该 DDR 区域。此次串口改动的布局布线时序数值也尚未记录在本文。

## 固定 YOLOv8n 卷积程序

`scripts/yolo_v8n_fixed_plan.py` 对照仓库内的 Ultralytics YOLOv8n YAML，生成 `out/board/yolo_v8n_fixed_plan.json` 和 `edrv32_yolo_v8n_program.v`。输入固定为 640×384；0～22 层展开为 74 条共享执行器命令：63 次卷积、6 次残差加法、3 次 SPPF 池化、2 次上采样。Detect 的三尺度 box/class 分支共占其中 18 次卷积，最后 1×1 卷积输出线性 logits，不经过 SiLU LUT。四处跨层 Concat 的两路输出预留相邻 C16 平面，不发起 DDR 拷贝。C2f、SPPF 与 Detect 中间工作区在命令之间复用，不复制 MAC 阵列。

当前计划的模型基址是 `0x0010_0000`，前 3,257,856 字节为卷积权重，量化记录从偏移 3,260,416 开始，完整卷积镜像预留 3,358,720 字节。输入及中间特征位于 `0x0200_0000` 起的独立 DDR 区域；首层输入 C3 需补零为 C16，地址由清单给出。每个 C32 输出块的量化记录占 512 字节：前 32 个 8 字节项依次存放 little-endian `bias:s32, multiplier:s16, shift:u8 (0..47), zero_point:u8`，后 256 字节为激活 LUT；Detect 最后一级线性卷积不使用 LUT。模型镜像仍需量化标定，并保证残差两路量化尺度一致，才能用于推理。

`edrv32_yolo_v8n_core` 只例化一套 `edrv32_yolo_v8n_exec`。其配置 DMA 在每个输出块进入配置阶段时读取 16 个 256-bit AXI beat，再送 32 个通道参数和必要时的 256 个 LUT 字节；配置读取与算子读取独占同一个 AXI master。DMA 读取错误会终止程序，并要求全局复位后再启动。固定程序握手与错误退出、量化 DMA 的 LUT／线性两种模式和错误响应，以及核心第一层“量化记录→权重”顺序均已仿真通过。

官方 `yolov8n.pt` 已下载并校验 SHA256 `f59b3d833e2ff32e194b5bb8e08d211dc7c5bdf144b90d2c8412c47ccfc83b36`。`scripts/yolo_v8n_checkpoint_audit.py` 将 BN 融入卷积，核对 63 个卷积权重形状和 P3/P4/P5 浮点输出尺寸，并导出 fused FP32 权重。`scripts/yolo_v8n_weight_layout.py` 按 `[输出块][ky][kx][C16][8 通道半块][8 bank][4 输出通道][8 输入通道]` 检查所有 63 层的打包往返。

`scripts/yolo_v8n_quantize.py` 已把 fused 权重转换为真实 INT8 权重、INT32 bias、每通道乘数／移位和 SiLU LUT。残差两路共享尺度，免拷贝拼接的每个 C16 平面可保留不同输入尺度；Detect 最后线性 logits 使用 zero point。`scripts/yolo_v8n_validate_quant.py` 逐条模拟 74 个命令的打包权重、量化记录和输出，再用官方 DFL／框解码及 NMS 对照浮点模型。`scripts/yolo_v8n_input_pack.py` 将 RGB 图像居中缩放补边、量化为 C16 输入；当前清单输入基址实际为 `0x0215_2000`，并可直接输出正确基址的 `.ymod`。模型基址为 `0x0010_0000`。按 115200 baud 连续发送这两个文件，线路发送时间约 11 分钟，另有 DDR 等待时间。

用 [COCO128](https://docs.ultralytics.com/datasets/detect/coco128) 排序后的前 96 张图像做标定，每图层极值取 95 百分位，余下 32 张做独立小样本验证。在相同 640×384 预处理及 NMS 下，浮点 mAP50／mAP50-95 为 `0.642/0.499`，INT8 主机模拟为 `0.623/0.471`；单张图像的主要类别和框也能对应。报告位于 `out/models/yolov8n_int8_coco96_p95_eval.json`。这是候选模型的小样本主机结果，仍需更充分数据集精度评估、RTL 数值对照与整网板测。完整镜像 `out/models/yolov8n_int8_coco96_p95.bin` 与两个 UART 传输文件已生成。

首版板顶 `edrv32_pango_200h_yolo_v8n_top` 按顺序等待模型 `0x0010_0000/3,358,720B`、C16 输入 `0x0215_2000/3,932,160B` 两次 UART 装载完成，再把同一个 AXI CDC 主口交给完整 74 命令核心；背景 DDR 读 master 在核心运行时继续工作。首版串口报告 `YV8 PASS/FAIL STEP=xx CYC=xxxxxxxx`。成功时 STEP 为十六进制 `49`，表示完成索引 73。下述实体板数据来自首版，仅确认命令执行和 AXI 响应，未核对 logits 数值。

上板选用同一 PDS 项目中的 `edrv32_pango_200h_yolo_v8n_top` 并重新运行 `import_sources.tcl`，其 IO 与时钟路径沿用现有 `io.fdc`、`clock.fdc`。烧录后先在第二代串口工具发送 `out/board/yolo_v8n_coco96_p95.ymod`，确认 `YD0CD0`（3280 包）后，再发送 `out/board/yolo_bus_input.ymod`，确认 `YD0F00`（3840 包），最后观察 `YV8` 状态。应以板端 `YD` 为装载完成依据，而不是仅看文件发送完成。

2026-09-24 实体板 COM7、115200 baud 完成这两份文件装载，分别收到 `YD0CD0`、`YD0F00`，随后报告 `YV8 PASS STEP=49 CYC=00DC42CF`。14,435,023 个 150 MHz 周期折合 96.23 ms，是单次整网卷积程序运行时间，未包含 UART、图像预处理、DFL/NMS 与显示；不能直接当作完整系统帧率。按 512 MAC/周期和清单中的物理填充运算量 3.077 GMAC 计算，纯计算下限约 6.009 M 周期，本次总执行周期对应约 41.6% 的理想算力占比，包含 DDR、配置、池化、上采样和调度开销。串口助手已通过 API 增加 `YV8` 的步骤与毫秒用时规则。

本次布局布线资源为 APM `289/740`、DRM `79/415`。DDR 域 WNS `+0.509 ns`；150 MHz YOLO 域仍有两条 setup 违例，WNS `-0.048 ns`、TNS `-0.073 ns`，路径从卷积配置通道寄存器经量化配置读取选择到 bias RAM 数据口，主要是配置通道信号扇出和布线延迟。板上成功执行说明这次样本运行通过，但不能替代时序收敛。下一次 RTL 迭代需处理这条配置路径，并增加 logits 读回校验，之后才能判断整网数值是否与主机一致。

## DFL、NMS 与性能记录（新版 RTL，待重新上板）

新版板顶在卷积核心完成后将同一个 AXI master 切给 `edrv32_yolo_v8n_post`。后处理逐行读取三尺度 Detect 的 4 个 box C16 平面和 5 个 class C16 平面，总读量 22,680 个 256-bit beat。每个位置选最大类别分数；分数至少 0.25 的位置再由 `edrv32_yolo_dfl16` 对四侧各 16 个 INT8 分布值做指数查表、归一化和距离期望。模型相关的指数与 sigmoid 表由 `scripts/yolo_v8n_post_tables.py` 根据镜像 SHA 和输出量化尺度生成。最多保存 512 个候选，`edrv32_yolo_nms` 按分数降序执行同类 IoU≥0.7 抑制，最多输出 100 个目标；候选溢出会置错误位。

新板顶还检查第一份模型文件的镜像 CRC32 `0x77398E67`，保证 DDR 中的权重／量化参数与本次生成的后处理查表一致；其他模型镜像需重新量化、生成查表并更新板顶 CRC 后重新综合。

对 COCO128 的 128 张图像做候选容量检查，0.25 阈值下每图平均 27 个、最多 160 个候选，均低于 512 项容量；这不是对所有场景的保证。

Detection META 写入 DDR `0x02A0_B000`：首个 32-byte beat 为 `YMET`、版本 2、目标数、错误标志、模型宽高和候选数；第二个 beat 保存原图宽高、缩放后宽高和左右／上下补边量。目标记录从 `0x02A0_B040` 开始，每个目标占一个 beat，含四个模型坐标 Q8.8 的 32-bit 边界、8-bit 类别、16-bit Q15 置信度、尺度编号和 anchor 编号。当前板顶的几何参数对应测试 bus 图像 810×1080；接入 1280×720 相机时应传入 640×360、左右补边 0、上下补边 12，渲染器据第二个 beat 逆变换 letterbox。

仿真覆盖 DFL 数值、同类／异类 NMS、空画面、单目标以及真实量化 bus 图像的三尺度 logits。真实样本读取 22,680 beat、筛出 38 个候选、NMS 后得到 4 个目标，与主机 INT8 参考的目标数、类别、置信度顺序相同；首框坐标差约 0.1 像素。该仿真只证明后处理与主机生成的 logits 对齐，实体板的 logits 仍没有独立读回校验。

2026-09-25 行缓存优化前，无 DDR 等待的真实 logits 行为仿真从后处理开始到 META 写回应答约 3.03 ms。优化后的相同测试约 3.78 ms，仍读取 22,680 beat，得到相同的 38 个候选、4 个目标及首框坐标；实际板上仍需计入 CDC、互联和 DDR 争用。上一版卷积核心实测 96.23 ms，纯 512-MAC 计算下限约 40.06 ms；两者间约 56 ms 的差额要依据新版逐命令 MAC／DDR 等待数据定位，不能直接认定全部是 DDR 搬运。

`edrv32_yolo_v8n_profiler` 为 74 条命令分别记录周期 `CY`、MAC 活跃拍 `MC`、AXI 读／写 beat `RB/WB`、读地址等待 `AR`、有待读数据时的空等 `RW`、写地址等待 `AW`、写数据等待 `WW` 和写响应等待 `BW`。新版串口完成后输出 `YV8` 总周期、`YCORE` 卷积程序周期、`YPOST` 后处理周期与候选／目标数、`YPH` 后处理加载／类别扫描／DFL／NMS／META 写入周期、`YPIO` 后处理 AXI 读写／等待计数，再打印每条 `YS` 明细及每个目标的 `YDET` 类别、Q15 分数和 Q8.8 框坐标。所有周期在 150 MHz AXI 源侧计数；`RW` 含 CDC、互联和 DDR 返回时间，且可与 MAC 周期重叠，不能直接将各列相加。串口助手已通过 API 添加总时间、卷积时间、后处理时间和候选／目标数规则；逐命令明细保留原始行，避免参数面板堆出数百项。`scripts/yolo_v8n_parse_report.py` 可将串口工具保存的日志转换为毫秒用时、最慢命令和十进制目标框；传入输入打包器的几何 JSON 时，也输出原图坐标。

量化配置 DMA 的 64-bit 通道记录现先入寄存器，再供量化 bias RAM 写入。首项增加一拍准备时间，之后 32 个通道保持每拍一项的配置吞吐；相关仿真已检查无中途空拍。这针对上次布局布线的通道索引高扇出至 bias RAM 数据路径；新版时序仍须以 PDS 报告确认。当前 UART 测试文件和现有 PLL、权重 RAM、激活 RAM、DDR IP 配置均可复用，重新导入源码、综合布局布线和烧录后才能验证本节 RTL。

### 2026-09-25 物理收敛优化

新增后处理的首轮 Device Map 为 APM 292/740、DRM 79/415、LUT 45,253/159,800、分布式 RAM 7144/39,500。布局后预估最差裕量 -1.545 ns；路由日志停在第 65 次迭代时仍有 6656 条未布通网络，没有完成结果。综合明细显示 9 路同时驻留的 Detect 行缓存使用约 2304 个分布式 RAM 原语，NMS 双索引候选表约 1620 个。此数字来自旧网表，不能当作优化后资源值。

RTL 已改为类别 5 个 plane、box 4 个 plane 顺序复用一份同步行 RAM。每个 plane 的 DDR 行读取仍为连续突发，读量及地址布局不变；每行的类别最大值和四侧 DFL 距离暂存后形成候选。NMS 将 winner 记录锁存，候选表只使用一个同步读口。逐命令 profiler 改用同步读取的打包记录 RAM，串口检测记录也改为同步读取。FPGA_MODE 复用工程已有的 512×256、单周期同步读、独立读写口的 `yolo_weight_ram` IP：后处理行缓存 1 实例、NMS 候选表 1 实例、profiler 2 实例、串口检测记录 1 实例；无需新增 IP 类型。该 IP 深度和宽度大于其中部分数据的实际需求，目的是使用空闲 DRM 换取更少的分布式 RAM 和扇出，优化后的物理资源和时序仍须以新一轮 PDS 综合布局布线为准。

2026-09-26 对 9/25 已布线版本的完整负裕量端点审计后，进一步给 reporter 字节、量化 CE、NMS IoU、LUT 配置、DFL、maxpool 地址与 post 框判定增加明确寄存边界，并将 UART 包缓存从按字节写入的 FF 阵列换为组 beat 后写同步 RAM。真实 logits 的理想 AXI 后处理仿真现约 4.15 ms，输出目标不变；见 [时序修订验证](../validation/2026-09-26-yolo-timing-fixes.md)。当前尚无这批 RTL 的新 PDS 时序结果。
