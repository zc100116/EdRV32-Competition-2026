# 演示程序

四个 SRAM 程序共用网口的模型、RGB565 图像和检测回传协议，调试工具无须选择板型。
实现依据：PIX 2.2–2.6、GEO 2.1/2.4/5.2、VIN 2.8、SoC 7.3–7.5。

| 程序 | 功能 |
|---|---|
| `demo` | 摄像头图像处理、检测、HDMI 和网口；RND 绘制检测叠加 |
| `demo_vision` | 摄像头图像处理、HDMI、网口视频与监控 |
| `demo_vnpu` | 摄像头图像处理、检测、HDMI 和网口；CPU 绘制检测叠加 |
| `demo_npu` | 网口图像检测与监控；CPU 生成与 VIN 相同的 NPU 输入 |

## 构建与烧录

```sh
. ~/.local/opt/edrv32/env.sh
for program in demo demo_vision demo_vnpu demo_npu; do
  make -C sw PROGRAM="$program" MEMORY=sram -j1
done
make -C sw/apps/demo test
```

输出 `build/sw/<程序>/<程序>.elf` 和 `.bin`。串口连接 115200、8N1，KEY1 + 复位进入
BIOS，在调试工具“设备与输出”中选择镜像。`.bin` 的烧录和运行地址均为 `0x10000000`；
也可选择 ELF 按段加载。烧录后自动运行，程序打印实际引擎 ID，默认图像处理、HDMI、
网口视频目标 30 fps、监控 100 Hz；`demo_npu` 默认等待网口图像。
摄像头程序使用 `-Os`，为参数解析、软件 Gamma 和仿射计算留出 SRAM；无浮点硬件要求。

## 串口命令

命令用 CR 或 LF 结束，整数以十进制表示。下列菜单适用于 `demo`、`demo_vision`、
`demo_vnpu`；`demo_vision` 不支持摄像头检测，`s1` 明确报错并保留当前流水线。
`demo_npu` 仅使用网口图像、模型与监控，不处理这些串口菜单。

| 命令 | 行为 |
|---|---|
| `s1` / `s2` | 摄像头检测 / 摄像头图像处理 |
| `pix set BC CONTRAST BRIGHT GAMMA_EN GAMMA S1 S2 GRAY BIN THRESH INV` | 一次设置完整 PIX 参数 |
| `geo set EN ANGLE SX SY TX TY MX MY` | 一次设置完整 GEO 参数 |
| `pix bypass` | 旁路 |
| `pix brightness` | 对比度 320，亮度 +24 |
| `pix gamma` | 原提亮预设 `2*x-x*x/255` |
| `pix gaussian` / `pix sobel` | 第一级高斯 / 第一级 Sobel 并输出灰度 |
| `geo off` / `geo rotate` / `geo scale` | 关闭 / 180° / 居中放大两倍 |
| `output hdmi` / `output eth` / `output both` | HDMI / 网口 / 两者同时 |
| `fps N` | 网口视频目标 1–60 fps |
| `sample N` | 监控 10–1000 Hz |
| `status` / `help` | 状态 / 菜单 |

PIX 参数：BC、GAMMA_EN、GRAY、BIN、INV 均为 0/1；CONTRAST 为 0–511 的 Q8，
256 表示 1 倍；BRIGHT 为 −256–255；GAMMA 为正整数千分值，1000 表示 1.000，
2200 表示 2.200。固件以整数 Q24 log2 / Q30 exp2 生成 256 项表，相对
`round(255*(x/255)^(1000/GAMMA))` 最大误差不超过 1，
写入当前未使用的 bank，全部写完后切换。S1、S2 独立选择 0–6：旁路、均值、高斯、
锐化、Sobel、腐蚀、膨胀；THRESH 为 0–255。各处理阶段可同时启用。

GEO 参数：EN、MX、MY 为 0/1；ANGLE 单位 0.1°，正值顺时针，接受任意整数角度；
SX、SY 为正整数千分比，1000 为原尺寸、500 为缩小一半、2000 为放大两倍；
TX、TY 为像素，正值向右/向下。先围绕 `(639.5,359.5)` 缩放和镜像，再旋转、平移。
`sw/lib/affine.c` 使用带保护位的整数 Q30 CORDIC 计算逆映射 Q16.16 矩阵，按实际量化后的系数检查 GEO 2.4：
`31*abs(A)+15*abs(B) <= 78*65536`，第二行同理。保证缩小至一半时的任意角度；
放大不设倍率上限。超出覆盖范围或 Q16.16 可表示范围，明确打印 Input error，
不暂停流水线、不下发矩阵。语法和寄存器字段越界也明确报错。

```text
pix set 1 320 24 1 2200 2 4 1 1 128 0
geo set 1 123 1500 750 20 -10 1 0
```

参数命令先完成计算，然后停止 VIN 并排空旧帧消费者，提交完整配置后恢复摄像头；
成功打印 `Demo command: OK`。PIX 设置持续生效，GEO 在摄像头图像处理路径生效。
原有预设命令、KEY2 场景切换、KEY3 五档 PIX 和 KEY4 三档 GEO 循环保持原行为；
PIX/GEO 预设仅在图像处理模式接受。预设切换会替换相应自定义参数。
预设、场景和输出切换在新模式首帧完成交接后打印 `Switch: frames=N mtime_ticks=T`；
HDMI 以 DISP FRAME 确认新帧，纯网口以完整输出 Surface 就绪计时。

视频从名义 30 fps 摄像头按 `max(1,ceil(30/N))` 分频，不重复帧；例如目标 7 fps
实际名义 6 fps，目标 60 fps 仍取所有源帧。`fps 60` 将 P6 RATE 设为 32/256，
其他档恢复 13/256。实际速率由源帧率、推理和带宽决定，工具显示实收 fps。

## 网口协议

MAC `02:45:44:52:56:32`，板端 IP `192.168.1.10`，UDP `5000`；PC 使用同网段地址，
监听 `6000`。应用包头保持网络序 8 B：用途编号 u8、FLAGS u8、保留 u16、OFFSET u32。
FLAGS bit0 为 NOTIFY；不新增 magic、协议代号或重试。下表数字仅供协议实现者使用，
GUI 按功能命名，图像缓冲由工具自动交替。

| 方向与用途编号 | 内容与结束条件 |
|---|---|
| PC→板，0/1 | 1280×720、小端 RGB565，1,843,200 B，stride=2560；末包 NOTIFY |
| PC→板，2 | EDNM 32 B 头在偏移 0，描述符在 0x1000、模型在 0x100000；仅最后一包 NOTIFY |
| PC→板，3 | 偏移 0、末包 NOTIFY；空负载或单字节 `00` 建立对端；`camera`（ASCII 6 B，无换行）恢复摄像头检测 |
| 板→PC，0 | 图像检查的 CH2，983,040 B，不置 NOTIFY |
| 板→PC，1 | 图像检查的 OUTPUT，725,760 B，不置 NOTIFY |
| 板→PC，2 | EDDT 检测结果，末包 NOTIFY；结束本张图像检查 |
| 板→PC，3 | EDTM 监控批次 |

所有支持检测的程序都接收同一种 RGB565 图像，回传顺序都是 **CH2 → OUTPUT → EDDT**。
`demo_npu` 的 CPU 严格执行 VIN 2.8：RGB565 位复制展开到 8 位，2×2 求和后
`(sum+2)>>2`，量化 `(254*c+255)/510`，上下各补 12 行 `[57,57,57,0]`，
最终 640×384 INT8_C4，每像素内存顺序 R/G/B/0。输入使用非缓存 DDR 别名，
NPU 和回传共同使用该张量。原始图像缓冲及 CH2/OUTPUT 在最终发送 DONE 前保持占用，
完成后清图像接收计数，主机才发送下一张；`demo_npu` 的 frame_id 从 0 自增。

摄像头检测程序收到图像后切换 VIN 内存源，同时生成 CH0 和 CH2；图像检查期间
不发 EDVF，结束保持内存源；`demo` / `demo_vnpu` 接受 WIN3 的 `camera` 命令，
停止内存流水线、排空已有消费者后设置 S1 和 `VIN_CAM0`，模型保持不变，
打印 `YOLO source: camera` 并清 WIN3 接收计数。其他非空 WIN3 内容打印
`Input error: unknown WIN3 command`，单字节 `00` 对端探测保持原行为；
`demo_npu` 没有摄像头，WIN3 仍只建立对端。串口 `s1` / `s2` 也会恢复摄像头，
`status`、场景及 PIX/GEO/输出命令仍走串口，不经过 WIN3。模型接收停止流水线，
加载后恢复原摄像头场景。EDNM 头维持现有格式和检查：magic/version、数量、长度、
模型容量、WORK/INPUT/OUTPUT 基址及实际接收字节数；成功打印 `EDNM: loaded`。
模型必须与 `sw/lib/yolo_tables.c` 来自同次量化，生成步骤见 `sw/lib/README.md`。
主机参考模型使用实际 RGB565 的 VIN 适配结果，避免原图低位与硬件输入不同。

块内整数均为小端，既有头不变：

| 块 | 布局 |
|---|---|
| EDTM | 320 B；type/version 各 u16；seq@8、scene@12、mtime u64@16；采样窗口@24；七端口统计@36；VIN@232；DISP@248；NPU@256；ETH@272；WFI@280；系统频率@284；NPU 150 MHz@288；视频跳帧@292；296–319 为零 |
| EDVF | 32 B；magic、version=1、format=1、width/height=1280/720；stride@12、frame_id@16、mtime u64@20、scene@28；后接 RGB565 |
| EDDT | 16 B；magic、version=1、count u16、frame_id u32、reserved=0；随后 count×12 B：x0/y0/x1/y1 i16、class/score u16，1280×720 坐标、COCO 类别、千分比分数，最多 100 框 |

摄像头检测先发送 EDDT，若本帧被分频选中且 ETH 空闲，再发 EDVF 头和原地底图。
图像处理视频只用头和像素两条描述符；像素 OFFSET=32，末包 NOTIFY。
上一帧仍在发送则跳过视频，累计 vid_skip；检测结果等待前次 TX 完成。

## DDR 布局与所有权

所有地址均为物理地址，与设计记录 3.3 相同；CPU 非缓存别名为 `0xc0000000+physical`。

| 区域 | 基址 | 分配 |
|---|---|---|
| NPU 描述符 | `0x00080000` | 64 KiB |
| NPU 模型 | `0x00100000` | 4 MiB |
| NPU WORK | `0x01000000` | 8 MiB |
| CH2 输入 | `0x04000000` | 3×1 MiB，实际每槽 983040 B |
| NPU OUTPUT | `0x05000000` | 2×1 MiB，实际每份 725760 B |
| CH0 底图 | `0x06000000` | 4×2 MiB，实际每槽 1843200 B |
| GEO 输出 | `0x07000000` | 2×2 MiB |
| 图像接收 | `0x08000000` | 2×2 MiB |
| 模型接收 | `0x09000000` | 16 MiB |
| 控制接收 | `0x0a000000` | 64 KiB |
| 发送缓冲 | `0x0a100000` | 4 MiB |

后处理所需 5040 项候选工作区另分配在原布局的空闲区 `0x01800000`，
有效 120,960 B（到 `0x0181d880`，右开），位于 WORK 分配区之后、CH2 输入之前，
不占发送缓冲；只有 CPU 使用，走缓存别名。100 项最终检测结果在 SRAM，占 1200 B。
发送缓冲内部：TX 描述符 `+0`（最多三条），EDVF `+0x100`，
EDDT `+0x200`（最多 1216 B），GEO 描述符 `+0x700`，
监控发送暂存 `+0x800`（5120 B），监控环 `+0x2000`（1024×320 B）。
主机测试覆盖上述区域边界，包含 EDDT 与 GEO 描述符不重叠。

VIN 中断及时锁住同 frame_id 的 CH0/CH2；NPU 忙则跳过摄像头帧。
NPU DONE 后释放普通推理的 CH2 输入，当前 OUTPUT 交 CPU，另一 OUTPUT 可供下一帧。
真实 `yolo_post_process(output,yolo_default_heads,workspace,detections,&stats)` 接口
接在 `scene_npu.c`。CPU 访问前只对 NPU OUTPUT 作废 cache；不再读写摄像头像素。
L0 显示摄像头帧；`overlay.c` 用 RND 的 BORDER/FILL/GLYPH 在 L1 画框及原有 COCO 标签。
L1 两块 ARGB8888 缓冲分别保留上次的框/标签脏矩形；复用时先 COPY 全透明源的对应
矩形，再重画，其他像素保持透明。OPA=0 的 FILL 不会清像素，因此不用于清除。
完成的 L1 与对应 L0 在同一个提交临界区发布，FRAME 后成组提交两层 shadow 参数。
两块 L1 分别等待 SWITCH1/REL_BASE 后复用，禁止写扫描或 shadow-next 缓冲。

显示叠加 DDR 布局（常数统一在 `demo.h`；设计 3.3 已补充）：L1 双缓冲从 0x07400000 起、
每块占 4 MiB；0x07c00000 起 4 MiB 资源区放透明源、命令列表、DDR A1 字体。
RND 驱动 clean 命令和声明的源，DONE 后 invalidate 声明的目标；均通过 BSP cache。
仅 HDMI/both 需要生成 L1；ETH-only 不启动叠加绘制。
网口始终直接发送 L0，S1 检测框由同 frame_id 的 EDDT 提供给 PC 自行叠加。
MODEL、NPU 描述符、EDDT/EDVF 和监控记录继续使用非缓存别名。

每个 CH0/GEO Surface 分别保留处理中、显示和 ETH 引用；DISP 的待提交、已写 shadow、
当前扫描状态分别维护。FRAME 中断提交下一张，SWITCH/REL_BASE 释放旧张；
停止 HDMI 后等 IDLE，再释放最后一张。ETH 必须完成整个描述符列表的 DONE_COUNT，
才能解除其引用；只有全部消费者释放后才清 VIN SLOT_BUSY。
PIX/GEO 切换不关闭 VIN 或 DISP：命令先排队，在 VIN CH0 帧完成事件中提交，
下一帧 SOF 开始使用新配置。PIX 的 BC/THRESH/CFG 影子组在同一事件中一次写完。
每张底图和 GEO 输出带配置代号，旧代号的在途 GEO 完成帧不作为新模式输出；
DISP 继续扫描旧完整帧，新代号首帧仍按提交、FRAME/SWITCH、释放的顺序接管。
S1/S2 切换只停止 VIN 并排空 NPU/GEO/ETH，保留 L0 当前扫描和 shadow-next 引用，
重配 VIN 环时保留相应 SLOT_BUSY。VIN 全局重启按规格重新丢弃两帧，计入切换耗时。
L1 在 FRAME 事件后写关闭，下一 FRAME 等待 SWITCH1 释放，S2 不再显示旧检测框；
返回 S1 后才画新结果。HDMI/both 互切也保持 DISP；涉及 ETH-only 的输出切换
沿用关闭 DISP、等 IDLE 后释放的流程。模型/测试图像接收仍沿用完整停机重配流程。

## DDR 监控

CLINT 默认 100 Hz；每次中断 SNAPSHOT|CLEAR，记录精确 WINDOW_CYC；
VIN 使用 PERF3/5/6/8 差值，DISP 读空用 PERF1 差值、提交数为软件计数差值；
NPU 最近周期取 PERF0（150 MHz），后处理周期由 CLINT 测量（100 MHz）。
CPU WFI 周期从睡眠到中断入口测量，不包括中断处理；配置处理/等待不计为空闲。
ETH 收发字节均指应用数据：RX 取 PERF2 差值；TX 由 PERF10 已发 UDP 包数与
本列表各段长度换算，短尾包按实际长度计数，不含以太网/IP/UDP/应用头。
每 16 条经监控通道批发，或场景切换时发不足 16 条的尾批。
切换刷新仅排空调用时记录快照，刷新期间新采样留给后续正常批发，避免持续采样使切换无法返回。

经协调者明确批准：没有 PEER 或监控环没有空位时丢弃最新记录，旧记录保持；
seq 每次采样仍递增，`status` 的 `Monitor dropped records` 计本地丢弃总数。
发送前把至多 16 条小记录复制到独立暂存，ETH 完成前不改暂存；不覆盖在途数据。
这不是视频像素搬运。PC 以 seq 间隔观察丢记录，视频独立用 vid_skip/帧号观测。

## 验证与上板

`make -C sw/apps/demo test` 包含原菜单、缓冲所有权、绘制、网口/监控测试，以及
参数解析、全角度和独立缩放矩阵、覆盖范围与 Q16.16 超限、Gamma 表/双 bank 切换、
不下发错误配置、完整随机 RGB565 帧的 CPU CH2 与独立 Python VIN 参考逐字节比较。
构建大小、主机工具测试和截图验收统一记录在
[调试工具 T-UI1 验收记录](../../../tools/debug_tool/README.md#t-ui1-验收记录)。

实板仍需连接摄像头、HDMI、PHY，核对各项同时启用效果、任意角度与非等比缩放、
两端输出及采样计数，并保存 UART/CSV。主机测试和合成截图不代替实板功能或时序测量。
