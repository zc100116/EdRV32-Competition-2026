# B2 演示程序（B3 两层显示升级）

依据：`docs/design/2026-10-29-b2-software.md` 全文、SoC 7.3–7.5，
驱动调用契约见 `sw/drivers/README.md`。默认 S2、PIX 旁路、GEO 关闭、HDMI、
视频目标 30 fps、DDR 监控 100 Hz；`demo` 使用完整 SoC，另有下述裁剪版本，不运行 SoC 仿真。

## 按板级工程选择版本（B3-11）

四份 `program.mk` 位于本目录、`demo_vision/`、`demo_vnpu/`、`demo_npu/`，通过源文件列表
选择功能；没有运行时引擎探测或版本条件编译。UART、S2、视频和 DDR 监控共用源文件，
S1 由 `scene_npu.c` 提供，EDNM 由 `network_npu.c` 共用，摄像头检查/CH2 回传由
`network_video_npu.c` 提供，L1 的交接由 `overlay_surface.c` 共用。

| 程序 | FPGA 工程/顶层 | 场景 | HDMI 检测框与标签 | 网口功能 | 不访问的引擎 |
|---|---|---|---|---|---|
| `demo` | B3F 全部，`edrv32_fpga_board_b2_top`（完整 SoC） | S1、S2 | `overlay.c`，RND 写 L1 | S2 视频、DDR 监控、EDNM、图像检查、EDDT | 无 |
| `demo_vision` | B3V 图像，`edrv32_fpga_board_vision_top` | 仅 S2 | 关闭 L1 | S2 视频、DDR 监控、WIN3 建立对端 | NPU、RND |
| `demo_vnpu` | B3VN 图像 + NPU，`edrv32_fpga_board_vnpu_top` | S1、S2 | `overlay_cpu.c`，CPU 写 L1 | 与 `demo` 相同 | RND |
| `demo_npu` | B3N，`edrv32_fpga_board_npu_top` | PC 送张量识别 | 上位机原图叠框 | EDNM、CH2 输入、OUTPUT/EDDT、EDTM 100 Hz | VIN、PIX、GEO、DISP、RND |

```sh
. ~/.local/opt/edrv32/env.sh
make -C sw PROGRAM=demo MEMORY=sram -j1
make -C sw PROGRAM=demo_vision MEMORY=sram -j1
make -C sw PROGRAM=demo_vnpu MEMORY=sram -j1
make -C sw PROGRAM=demo_npu MEMORY=sram -j1
```

各版本生成 `build/sw/<程序>/<程序>.elf`、`.dis`、`.bin` 和存储 hex，均可用下面的
BIOS SRAM 烧录步骤。B3R 渲染器工程继续使用自己的程序，不使用这四种演示镜像。

`demo_vision` 的 `s1` 和 KEY2 均打印 `Input error: this board requires s2`，保留 S2，
不停止或重配流水线；`help` 只列出 S2。WIN0/1/2 不配置、不注册通知，不编入
模型加载、图像推理检查、检测回传和 YOLO 后处理；PC 应发 WIN3 短包建立对端。
EDTM 布局保持兼容，其中四个 NPU 统计字段为零，偏移 288 的协议频率常数保持 150 MHz。

三个版本启动均打印 VIN、PIX、GEO、DISP、ETH、MEM_XBAR、PERF_MON 的实际 ID；
`demo`、`demo_vnpu` 另打印 NPU，`demo` 另打印 RND。ID 只打印、不比较；
裁剪版本不会尝试读取不存在的 APB 槽。

B3VN 的 CPU 绘制沿用 RND 参数：绿色 `0xff00ff00`、向框内一像素的四边边框，
矩形为 `[x0,x1-1]×[y0,y1-1]`；标签底条同色、OPA=255，高 16 像素，宽为
标签长度×8，位置在框上方 16 像素（y0<16 时从 y0 开始）；同一 `font8x16.h`
字库按 MSB 在左画白色字形，未置位的字形像素保留底条。两种实现共用 COCO 名称和
千分比标签格式。裁剪范围均为 1280×720，空矩形按 RND 2.5 不访问目标。
每份 L1 缓冲分别保留框/标签脏矩形，复用时清成全透明再画下一帧；零检测也清旧框。
CPU 写缓存别名 `EDRV32_DDR_BASE + 0x07400000/0x07800000`，通过 BSP `cache_clean`
写回清除和新画的矩形范围，完成后才发布给 `disp_submit(DISP_L1,...)`。
L1 仍等 SWITCH1/REL_BASE 释放，绝不修改当前扫描或 shadow-next 缓冲。

### B3VN 上板测量画框 CPU 时间

烧录 `demo_vnpu`，先加载模型再发 `s1`，选择 `output hdmi` 或 `output both`。
等待检测帧出现后发已有的 `status`，记录 `Detection count`、`Overlay CPU cycles`
和启动时的 `CLK_SYS_HZ`。`Overlay CPU cycles` 每次实际画 L1 后更新为本帧的
`mcycle` 差值：包含该槽上一帧脏矩形的清除、新框/标签/字形绘制和 BSP cache clean；
不包含后处理、等待 L1 空闲、DISP 提交及扫描，计时区间内的中断时间会计入。
毫秒数 = `Overlay CPU cycles × 1000 / CLK_SYS_HZ`，例如 100 MHz 时周期数除以
100000 即为毫秒。这里只提供测量方法，尚无实板周期数据。

保持场景，移动目标改变框数，重复 `status` 并保存 UART 日志，连同构建 commit、
输出模式、检测框数和时钟频率记录，便于比较；脏矩形来自该槽的前次使用，时间也受
旧框数影响。零检测帧可测清旧框耗时。`output eth` 不画 L1，该计数保留最后一次
实际绘制值；启动后首次绘制前为零。没有新增测量命令，也没有逐帧串口打印干扰绘制。

### B3N 上板检查清单（卡 22）

B3N 烧录 `build/sw/demo_npu/demo_npu.bin`，启动默认等待 PC 网口输入，
无摄像头、HDMI、KEY 场景切换或串口菜单；打印 SYS/MEM_XBAR/PERF_MON/NPU/ETH ID。
仍使用上述 MAC/IP/端口、EDNM 和 EDTM 格式，监控固定 100 Hz。

- 调试工具板型选择 **B3N**，烧录 `demo_npu`；建立网口连接后核对 PEER，查看 EDTM 曲线。
- 选择编译模型目录和对应的量化 JSON，发送模型，串口须打印 `EDNM: loaded`。
- 选择任意尺寸图片并发送；工具先缩放到 1280×720，再调用现有 `input_pack` 生成
  983,040 B CH2（INT8_C4），发 WIN0 或 WIN1，末包 NOTIFY；板端直接以该窗口为 NPU 输入。
- 返回顺序为 WIN1 OUTPUT（725,760 B）、WIN2 EDDT；只有 EDDT 末包 NOTIFY，
  不回传 CH2、不发 EDVF。窗口地址沿用原分配，计数在最终发送完成后清零。
- 工具自动运行 NPU 参考和 Python 后处理，OUTPUT 字节差异和检测项差异应为零。
  CH2 比较的是本地重打包与发送张量；B3N 无输入回读。框从 1280×720 坐标映射到原图显示。
- 串口每张一行 `frame_id=N NPU_PERF0=C post_cpu_cycles=P detections=D`；
  frame_id 从 0 自增，P 是 CPU mcycle 差值（含期间中断），C 是 NPU PERF0。
- 文件夹按钮按文件名顺序逐张发送，WIN0/1 交替；收到最终通知并比对后才发下一张。
  日志记录每张从开始发送到最终 EDDT 通知的往返 ms，及包含打包/参考比对的平均 fps。
- 连续 N 张保存串口/会话日志、每张比对结果、平均 fps 和 EDTM 曲线；
  EDTM 的 VIN/DISP 字段为零，NPU/ETH/CPU/DDR 字段保持原定义。

## 构建和烧录

```sh
. ~/.local/opt/edrv32/env.sh
make -C sw PROGRAM=demo MEMORY=sram -j1
make -C sw/apps/demo test
riscv-none-elf-size build/sw/demo/demo.elf
python3 tools/check/verilog_style.py sw/apps/demo
git diff --check
```

输出在 `build/sw/demo/`：`demo.elf`、`demo.dis`、`demo.bin` 及
`rom.hex` / `sram.hex` / `ddr.hex`。在调试工具烧录页选择 `demo.bin`，填写烧录和运行地址 0x10000000，
选择串口或网口。按住 KEY1 再按复位；烧录成功后 BIOS 自动执行镜像。也可用同一 ELF 生成的 SRAM hex 初始化 bitstream。
程序、量化表、字库初值、100 项检测结果和状态在 SRAM；图像、候选工作区、
RND 命令及绘制时使用的字体副本在 DDR。

启动打印所选版本名、构建 commit/编译器、CHIP_ID/CLK_SYS_HZ、
本版本实际访问的引擎 ID，以及两路摄像头的 chip ID 原始读值。
ID 只打印，不比较期望值，不设“自检通过才运行”的门禁。
SCCB NACK、引擎错误、帧 INCOMPLETE/BUS_ERR、错误 EDNM/图像长度会直接打印
相关原始寄存器并停止，保留场景，按复位重启；无重试或备用数据流。

## 串口命令表

115200、8N1；每条命令独占一行，CR、LF、CR LF 都支持。
命令区分大小写，不带首尾空格。成功后打印 `Demo command: OK`，
非法输入打印 `Input error`，保留当前场景。PC 每次等应答后再发下一条命令。

PIX/GEO、场景和输出命令在新模式首帧完成交接后应答；紧接 `Demo command: OK`
的一行是 `Switch: frames=N mtime_ticks=T HDMI FRAME`。计时从接受命令开始，
到 DISP FRAME 确认新模式 Surface 为 CUR_BASE 为止；N 是期间的 DISP FRAME 次数，
T 是 64 位 `mtime` 差值，秒数为 `T / CLK_SYS_HZ`。包含等待 VIN 帧边界、
GEO/NPU/后处理和 DISP 提交的时间，没有新增命令。
ETH-only 没有上屏事件，按协调者确认的口径改为首张新模式完整输出 Surface 就绪，
同一行标注 `HDMI off (Surface ready)`；此时 N 是期间的 VIN CH0 完成帧数，
不以未知对端或 UDP 发送完成作为终点。

| 命令文本 | 行为 | 调试工具场景键 |
|---|---|---|
| `s1` | 摄像头目标检测，PIX 强制旁路 | `s1` |
| `s2` | 摄像头图像处理，恢复所选 PIX/GEO | `s2` |
| `pix bypass` | PIX 旁路 | `pix_bypass` |
| `pix brightness` | 对比度 Q8=320，亮度 +24 | `pix_brightness` |
| `pix gamma` | 提亮曲线 `2*x-x*x/255`，bank 1 | `pix_gamma` |
| `pix gaussian` | 第一级 Gaussian 3×3 | `pix_gaussian` |
| `pix sobel` | 第一级 Sobel，灰度输出 | `pix_sobel` |
| `geo off` | GEO 关闭 | — |
| `geo rotate` | 180° 旋转，保持 1280×720 | `geo_rotate` |
| `geo scale` | 居中放大 2 倍，1280×720 输出 | `geo_scale` |
| `output hdmi` | DISP 扫描，不发视频 | 输出选择 |
| `output eth` | DISP ENABLE=0 并等 IDLE，仅发视频 | 输出选择 |
| `output both` | HDMI 和网口同时输出 | 输出选择 |
| `fps N` | N=1–60，设置网口视频目标帧率 | 视频帧率 |
| `sample N` | N=10–1000 Hz，设置监控采样率 | `sample_rate` |
| `status` | 场景/设置、VIN/NPU/ETH 计数、时间及监控丢弃数 | — |
| `help` | 重印菜单 | — |

`sample_rate` 的命令模板是 `sample {hz}`；视频帧率模板是 `fps {fps}`。
PIX/GEO 命令仅在 S2 接受，S1 输出须保持原图供检测画框。
KEY2（GPIO bit1，低有效）切换 S1/S2；KEY3（bit2）依次选 5 种 PIX；
KEY4（bit3）依次选 GEO 关闭/旋转/缩放，后两键在 S1 打印操作要求 S2。
GPIO 消抖设 20 ms，KEY1 保留给 BIOS。

视频以摄像头帧号整数分频：`divisor=max(1,ceil(30/N))`，发送 frame_id 可整除
该 divisor 的帧。720p 摄像头表的名义源频率为 30 fps，因此 `fps 15` 每两帧发一帧，
`fps 7` 每五帧发一帧、名义 6 fps，`fps 30` 与 `fps 60` 都选所有源帧；
实际发送率还受源帧率、S1 推理率及 ETH 跳帧影响。该程序不会重复 Surface 来伪造 60 fps。
纯逻辑分频同时测试 30/60 fps 源；实板若采用 60 fps 摄像头配置，应同步把
`demo.h` 中源频率常数改为 60。当前驱动的 720p 表实际帧率须由 VIN PERF 测量。
`fps 60` 把 P6 RATE 调到 32/256 beat/cycle，其余档恢复 13/256，供极限带宽测量。
可选 PERF_MON 延迟探针/type 2 本次未启用，没有 `probe_on`/`probe_off` 对应命令。

## 网口约定

经协调者确认：本机 MAC `02:45:44:52:56:32`，IP `192.168.1.10`，UDP 接收
和发送源端口 `5000`。PC 用同网段地址、本地端口 `6000`，先监听，再通过这个端口
发一个有效应用包；图像、镜像，或 WIN3 的短包均可。WIN3 只用于建立对端，不解释命令。
发送目的 MAC/IP/UDP 端口取硬件 PEER 寄存器，即 PC 最近一个成功写入包的源地址。
没有 PEER 时不发送。场景控制统一走串口，WIN3 不实现网口菜单。

PHY 复位按协调者批准的保守值：拉低 10 ms，释放后等 100 ms；
厂商例程只用 PLL lock 释放 PHY，具体 PHY 型号和时序仍须上板核对。
不额外访问未确认地址的 MDIO 寄存器，不轮询链路作为运行门禁。

PC→板的块均以末包 NOTIFY 结束，每次发送完等当前操作结束再发送下一块：

- WIN2：32 B 小端 EDNM v1 头；描述符在块偏移 `0x1000`，模型在 `0x100000`。
  核对头的 magic/version、描述符数量和字节数、模型区容量、WORK/INPUT/OUTPUT
  基址，以及 `WIN2_BYTES=32+desc_bytes+model_bytes`；偏移间空洞不计入字节数。
  将两段复制到固定 DDR 位置、配置 NPU，然后打印 `EDNM: loaded`。
  这次镜像替换先停止当前流水线，完成后回到原场景的摄像头源。
- WIN0/1：1,843,200 B 连续 RGB565 图像，stride=2560；通知后自动切 S1 内存源，
  CH0 显示、CH2 输入 NPU。按 WIN0（983,040 B CH2）、WIN1（725,760 B OUTPUT）、
  WIN2（EDDT）顺序回传，只有最后 EDDT 块的末包 NOTIFY。检查期间不发 EDVF，
  避免复用 WIN0 的两种格式。检查结束保持内存源，发 `s1` 或 `s2` 恢复摄像头。
  原图接收窗口的字节计数在回传完成后清零，之后可再次发送。
- WIN3：短包会更新 PEER、清计数，无其他应用动作。

NPU 镜像必须与 `sw/lib/yolo_tables.c` 的量化表来自同次量化。
`yolo_default_heads` 已编入 SRAM，不经 EDNM、也不从 MODEL 中猜测量化参数。
换模型按 `sw/lib/README.md` 重新生成表并重新构建 demo；板上不加哈希/比对门禁，
不一致时由调试工具 YOLO 页的 OUTPUT/EDDT 逐字节比较呈现。
上电先加载 NPU 镜像再选择 S1；程序不维护“模型已验证”的运行标记。

板→PC 的应用头由 ETH 驱动/硬件生成，仍为网络序 8 B `WIN/FLAGS/OFFSET`。
块内 EDTM/EDVF/EDDT 都是小端：

| 块 | 布局 |
|---|---|
| EDTM，WIN3 | 固定 320 B；version/type 各 u16=1；seq@8、scene@12、mtime u64@16；WINDOW_CYC@24、DS_BUSY@28、DIR_SWITCH@32；7×7 个端口 u32@36；VIN 4×u32@232；DISP 2×u32@248；NPU 4×u32@256；ETH 2×u32@272；WFI 周期@280；CLK_SYS_HZ@284；150000000@288；vid_skip@292；296–319 为零 |
| EDVF，WIN0 | 32 B：magic；version u16=1；format u16=1；width/height u16=1280/720；stride u32@12；frame_id u32@16；mtime u64@20；scene u32@28 |
| EDDT，WIN2 | 16 B：magic；version u16=1；count u16；frame_id u32；reserved u32=0；随后 count×12 B：x0/y0/x1/y1 i16、class/score u16，显示坐标、COCO 0–79、千分比；最多 100 框 |

普通 S1 每个后处理帧先回传 EDDT；若该帧的视频分频选中且 ETH 可用，
同一列表再发 EDVF 头和原地 Surface。S2 视频只用头和像素两条描述符。
像素 LEN=1,843,200、OFFSET=32、末包 NOTIFY；CPU 不复制像素。
ETH 上一帧仍在发送时跳过本帧视频，累加 `vid_skip`；S1 的 EDDT 等前次 TX 完成后发送。
图像检查三块用同一个描述符列表，CH2/OUTPUT 保持占用直到 DONE_COUNT 前进三条。

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
| 接收 WIN0/1 | `0x08000000` | 2×2 MiB |
| 接收 WIN2 | `0x09000000` | 16 MiB |
| 接收 WIN3 | `0x0a000000` | 64 KiB |
| 发送缓冲 | `0x0a100000` | 4 MiB |

B2-4a 所需 5040 项候选工作区另分配在原布局的空闲区 `0x01800000`，
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

B3 DDR 布局（常数统一在 `demo.h`；设计 3.3 已补充）：L1 双缓冲从 0x07400000 起、
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
每 16 条经 WIN3 批发，或场景切换时发不足 16 条的尾批。

经协调者明确批准：没有 PEER 或监控环没有空位时丢弃最新记录，旧记录保持；
seq 每次采样仍递增，`status` 的 `Monitor dropped records` 计本地丢弃总数。
发送前把至多 16 条小记录复制到独立暂存，ETH 完成前不改暂存；不覆盖在途数据。
这不是视频像素搬运。PC 以 seq 间隔观察丢记录，视频独立用 vid_skip/帧号观测。

## 上板检查清单

以下是**待执行的功能验收**，不声称 Linux 构建或主机测试已经验证硬件现象：

| 操作 | 正常现象/判据 |
|---|---|
| BIOS 烧录后自动运行 | UART 出现 Demo 版本、实际引擎 ID、两路 camera chip ID（OV5640 通常 0x5640）；无 ERROR；菜单可接受 Enter 命令 |
| `s2`、`pix bypass`、`geo off` | HDMI 稳定 1280×720 摄像头画面，无错位、撕裂；VIN CH0 帧数持续增长 |
| `status` 两次 | 用 `ΔPERF0×CLK_SYS_HZ/Δmtime` 算 cam0 帧率；CH0 用 PERF3，S1 CH2 用 PERF5；测量时间段至少一秒，确认实际摄像头帧率，不拿 HDMI 60 Hz 当摄像头帧率 |
| 5 种 PIX 逐一切换 | 旁路原图、亮度/对比度增强、Gamma 提亮、高斯模糊、灰度 Sobel 边缘；无黑帧、闪烁、失锁或撕裂，无引擎错误，CH0 计数继续增长；记录每次 Switch 帧数和 mtime_ticks，保存连续切换视频 |
| `geo rotate` / `geo scale` / `geo off` | 图像转 180° / 中心放大 2 倍 / 恢复；旧完整帧保持至新完整帧接管，无黑帧或撕裂，DISP 读空计数为零；记录每次 Switch 耗时并保存视频 |
| KEY2–4 | KEY2 S1/S2 切换；S2 下 KEY3/4 各循环 PIX/GEO；一次按下只有一次操作，无黑帧；记录 Switch 耗时；S1 下后两键打印要求 S2 |
| PC 监听 6000 后发 WIN3 短包 | status 出现 PC peer IP/6000；调试工具 DDR 监控页出现 EDTM；无 peer 前本地 dropped 递增且画面照常 |
| 加载模型到 WIN2 | UART 打印准确 WIN2_BYTES、`EDNM: loaded`；不存在 hash/self-test 成功门禁；不正确 EDNM 显示头字/寄存器后停止 |
| 模型加载后 `s1` | HDMI 的 L0 摄像头加 L1 目标框、COCO 类名和千分比置信度标签；NPU 推理次数增长；调试工具检测帧率、NPU/后处理耗时有值；CH0/CH2 同帧，无错误 |
| S1 移动/移走目标 | L1 框及标签更新，旧位置恢复透明，无前两帧残影；L0 摄像头帧不被写框；分别观察 SWITCH/SWITCH1 和 REL_BASE/L1_REL_BASE，复用只在释放后 |
| S1 连续检测、`s1`/`s2` 切换 | L0 持续扫描，无黑帧、撕裂或错配，S2 无旧框；返回 S1 后新检测出现；零检测时旧框全部清除；记录每次 Switch 耗时，保存 UART 和切换视频 |
| S1 `output both` | HDMI 有框，PC 收到的原始 L0 视频无板端框，EDDT 可在 PC 按 frame_id 叠加；不要求两端视频像素含相同 UI |
| YOLO 页发 WIN0 图像，再发 WIN1 图像 | 自动内存源；依次收齐 CH2 983040 B、OUTPUT 725760 B、EDDT；与工具 input_pack、NPU 参考、Python 后处理逐字节/逐项相同；两窗口可重复使用，收到最终 NOTIFY 后再发下一图 |
| `output hdmi` / `output eth` / `output both` | HDMI 正常/黑色但时序保留/正常；hdmi/both 互切无黑帧；视频无/有/有；ETH-only 时监控 P0 读带宽停止；both 下底图与 S1 frame_id 对应；L1 框仅 HDMI，PC 使用 EDDT；记录 Switch 耗时及 HDMI off 标注 |
| `fps 1` / `fps 15` / `fps 30` / `fps 60` | 30 fps 源分别名义 1/15/30/30 fps；S1 不超过推理率；核对收到帧号分频；带宽压力下 vid_skip 增长，显示 Surface 不被提前覆写；真实 60 fps 源另配置后验证约 111 MB/s 极限档 |
| `sample 10` / `sample 100` / `sample 1000` | EDTM WINDOW_CYC 随采样周期变化，帧率/带宽按实际窗口换算；vid_skip 在偏移 292；保留尾 24 B 全零；场景切换有尾批，seq 间隔显示丢记录 |
| DDR 监控页运行 S1/S2 | 端口读写堆叠图、利用率、等待、VIN 溢出/DISP 读空、NPU/后处理耗时符合页面字段；实时性异常计数正常应为零；保存 UART/CSV/必要视频截图作为实板证据 |
| 复位再次运行 | 同一 SRAM 镜像重新打印启动信息、默认 S2；data/bss 状态重建，没有沿用上次菜单状态；断电后按 BIOS/bitstream 初始化规则重新烧录 |

## 验证记录

Linux 仅验证 C11 构建和纯逻辑，未运行 Verilator、SoC 仿真、FPGA 或真实串口/PHY/HDMI。
构建/主机日志在 `build/sw/demo/{rv32-build.log,host-test.log}`；静态栈帧信息在
`build/sw/demo/obj/**/*.su`，供重复测量。

2026-10-29 在实现提交 `6119551` 上的结果（已 rebase 并接入 B2-4a）：

| 验收 | 结果 |
|---|---|
| `make -C sw PROGRAM=demo MEMORY=sram -j1` | PASS，xPack GCC 15.2.0，C11 / RV32IM+Zicsr / `-O2 -Wall -Wextra -Werror`，0 warning / 0 error |
| `make -C sw/apps/demo test` | PASS，主机 GCC 13.3.0，C11 / `-Wall -Wextra -Werror` / UBSan，7 类纯逻辑覆盖均通过，无 UBSan 错误 |
| `riscv-none-elf-nm -u build/sw/demo/demo.elf` | 无未解析符号 |
| `python3 tools/check/verilog_style.py sw/apps/demo` | 0 Verilog 文件、0 warning；没有 RTL 改动，Verilator lint 不适用 |
| `git diff --check` | PASS |

`riscv-none-elf-size`：text=**41132 B**（指令 28148 B、只读数据 12984 B），
data=**0 B**，bss=**1996 B**（含 BSP `.tohost` 72 B），合计 **43128 B**。
链接对齐另占 20 B，`__bss_end=0x1000a88c`，
距 SRAM 栈顶 `0x10010000` 尚余 **22388 B**；整个程序和栈放得进 64 KiB SRAM。
BIOS 镜像 `demo.bin=41132 B`，也小于 BIOS 的 SRAM−4 KiB 栈下载上限。
静态 `.su` 中最大单函数栈帧为监控采样 336 B，main 320 B、
后处理入口 128 B；这些是函数自身帧，不冒充实板栈高水位测量。
未取得硬件性能数字；真实摄像头帧率、60 fps 源配置、PHY 时序、HDMI/UDP 功能现象
按上述清单在实板验证并记录，Linux 验收未替代这些检查。


## B3 本次验收

```sh
make -C sw PROGRAM=demo
make -C sw/apps/demo test
make -C sw PROGRAM=rnd_board MEMORY=ddr_app
make -C sw/tests/rnd_board test
python3 sw/tests/rnd_board/expect.py
```

前述 `6119551` 的大小为 B2 历史记录。B3 的构建与主机测试日志在同一 build 目录；
RND 独立的 16 组 CRC、屏幕图案及 BIOS DDR 加载流程见
[`rnd_board/README.md`](../../tests/rnd_board/README.md)。
本次仍未执行实板检查或 SoC 仿真，上板按本节之前的清单记录真实结果。

## B3-11 Linux 验收

本节对应 `demo: build full, vision and vnpu board variants` 实现提交。
使用 xPack GCC 15.2.0、RV32IM+Zicsr、`-O2 -Wall -Wextra -Werror`，
以上三个 SRAM 构建全部通过，0 warning / 0 error。

| 程序 | text (B) | data (B) | bss (B) | size 合计 (B) | `__bss_end` | 至 SRAM 栈顶余量 (B) |
|---|---:|---:|---:|---:|---|---:|
| `demo` | 43524 | 0 | 5244 | 48768 | `0x1000bebc` | 16708 |
| `demo_vision` | 24692 | 0 | 796 | 25488 | `0x1000639c` | 40036 |
| `demo_vnpu` | 43312 | 0 | 5224 | 48536 | `0x1000bda8` | 16984 |

余量含未使用 SRAM，栈顶均为 `0x10010000`，不是实板栈高水位。
`make -C sw/apps/demo test` 通过，C11 / `-Wall -Wextra -Werror` / UBSan，
原有纯逻辑测试保留，新增 CPU L1 测试按 RND 参数逐像素检查已知框、标签底条、
字形、相互覆盖、右边裁剪、退化框、双缓冲独立清除及零检测帧；BSP clean 的主机替身
只将已写回范围复制到模拟可见图像，并核对 DISP 可见像素与 CPU 结果一致。
`python3 tools/check/verilog_style.py sw/apps/demo` 为 0 文件/0 warning（无 RTL），
`git diff --check` 通过。

构建日志在各版本的 `build/sw/<程序>/rv32-build.log`；主机测试在
`build/sw/demo/host-test.log`。大小和 SRAM 余量可用以下命令复测：

```sh
riscv-none-elf-size build/sw/demo/demo.elf build/sw/demo_vision/demo_vision.elf \
    build/sw/demo_vnpu/demo_vnpu.elf
riscv-none-elf-nm -n build/sw/demo/demo.elf build/sw/demo_vision/demo_vision.elf \
    build/sw/demo_vnpu/demo_vnpu.elf | rg 'elf:|__bss_end|__stack_top'
```

缺失 APB 访问检查（无匹配是预期结果）：

```sh
riscv-none-elf-objdump -d build/sw/demo_vision/demo_vision.elf \
    > build/sw/demo_vision/apb-check.dis
riscv-none-elf-objdump -d build/sw/demo_vnpu/demo_vnpu.elf \
    > build/sw/demo_vnpu/apb-check.dis
rg -n '4100[46]|<(npu|rnd)_' build/sw/demo_vision/apb-check.dis
rg -n '41004|<rnd_' build/sw/demo_vnpu/apb-check.dis
riscv-none-elf-nm build/sw/demo_vision/demo_vision.elf \
    | rg 'yolo|demo_(model_header|detection_pack)|npu_|rnd_'
rg -B 12 '<engine_(control|poll|perf|irq_register|irq_handle)>' \
    build/sw/demo_vision/apb-check.dis
```

前三个匹配检查均无输出：vision 无 NPU `0x41006000`/RND `0x41004000` 直接访问、
vnpu 无 RND 直接访问，vision 无模型/检测/YOLO 链接符号。另核对 vision 的公共
`engine_*` 调用参数及注册回调：只选择 VIN=0、PIX=1、GEO=2、DISP=3、ETH=5、
MEM_XBAR=6，错误/等待路径来自这些调用者；未注册 NPU 中断，不选择 NPU=4。
公共驱动只读表中仍有 NPU 的地址常量，它不是执行中的 APB 访问；驱动按 Task 约束未改。
未运行 SoC 仿真，HDMI 视觉效果、实板 CPU 周期和功能仍按上板方法验收。

### B3-12 平滑切换验证（2026-10-30）

实现及本记录在同一提交，开发基线为 `4ef3320`；复现时检出包含本节的提交。
使用 xPack GCC 15.2.0，C11、`-Wall -Wextra -Werror`，以下三次构建全部通过、0 告警：

```sh
. ~/.local/opt/edrv32/env.sh
make -C sw PROGRAM=demo MEMORY=sram -j1
make -C sw PROGRAM=demo_vision MEMORY=sram -j1
make -C sw PROGRAM=demo_vnpu MEMORY=sram -j1
make -C sw/apps/demo test
python3 tools/check/verilog_style.py sw/apps/demo
git diff --check
```

| 程序 | text (B) | data (B) | bss (B) | size 合计 (B) | `__bss_end` | 至 SRAM 栈顶余量 (B) |
|---|---:|---:|---:|---:|---|---:|
| `demo` | 45584 | 0 | 5328 | 50912 | `0x1000c710` | 14576 |
| `demo_vision` | 26556 | 0 | 876 | 27432 | `0x10006b2c` | 38100 |
| `demo_vnpu` | 45356 | 0 | 5308 | 50664 | `0x1000c5fc` | 14852 |

三者均放进 64 KiB SRAM；余量不是实板栈高水位。原始构建日志位于各版本的
`build/sw/<程序>/rv32-build.log`，主机日志为 `build/sw/demo/host-test.log`。
上述 size/nm 命令可以重新取得表中数据。

host_test 在 UBSan 下通过，保留原有协议/菜单/CPU 绘制测试，并实际链接
`pipeline.c`、`switch.c`、`network.c`、`scene_npu.c`、`overlay_surface.c`
及原 VIN/PIX/GEO/DISP 驱动。替换 MMIO、IRQ 锁和硬件完成事件，不运行 RTL。
事件序列检查五档 PIX 的影子组仅在 VIN CH0 完成事件中一次写完、PIX/GEO 不停
VIN/DISP、DISP 提交无空档且旧 Surface 等 SWITCH 后释放、ETH 引用独立保留、
在途旧 GEO 输出不完成新模式切换、S1/S2 保留扫描和 shadow-next 的 SLOT_BUSY、
在途 NPU 排空后的 POST 引用释放、L1 待提交时关闭及返回 S1 重画、hdmi/both
互切不停 DISP、ETH-only 的 Surface 就绪口径，以及帧计数/mtime 回绕和耗时行。
风格检查为 0 文件/0 告警（目录无 RTL），`git diff --check` 通过。

未运行 SoC 仿真或上板；无黑帧、闪烁、失锁、撕裂及实际切换耗时，仍须按上板
检查清单保存连续切换视频和 UART 原始打印，不能由上述软件事件测试代替。

### demo_npu 验收记录（2026-10-31，T-NETN / T-NETN-R）

原实现 `7b3306d5`（基线 `ddd39075`），源文件拆分及本记录位于同一提交；GCC 15.2.0，C11，
`-Wall -Wextra -Werror`。四版本构建均通过，0 warning，均装入 64 KiB SRAM：

| 程序 | 改前 .bin B | 改后 .bin/text B | data B | bss B | 合计 B |
|---|---:|---:|---:|---:|---:|
| demo_npu | 22124 | 22056 | 0 | 1856 | 23912 |
| demo_vnpu | 45328 | 45452 | 0 | 5308 | 50760 |
| demo | 45988 | 46128 | 0 | 5360 | 51488 |
| demo_vision | 26584 | 26628 | 0 | 876 | 27504 |

原三版本 .bin 分别变化 +140/+44/+124 B（demo/vision/vnpu），行为保持原样。
B3N `__bss_end=0x10005d80`，至栈顶余量 41,600 B（非实板高水位）。复现：

```sh
. ~/.local/opt/edrv32/env.sh
for p in demo_npu demo_vnpu demo demo_vision; do make -C sw PROGRAM=$p MEMORY=sram -j 1; done
make -C sw/apps/demo test
QT_QPA_PLATFORM=offscreen OPENBLAS_NUM_THREADS=1 OMP_NUM_THREADS=1 \
  ~/.local/opt/edrv32-py/bin/python -m unittest discover -s tools/debug_tool/tests -v
python3 tools/check/verilog_style.py sw/apps/demo
git diff --check
```

UBSan 主机测试通过：实际链接 B3N 网络/推理/监控和 NPU/ETH 驱动、CPU 后处理，
检查 EDNM、双窗口、OUTPUT→EDDT、最终 DONE 前保留缓冲、EDTM 零 VIN/DISP 字段、
长度/模型/引擎错误报停；MMIO 模型拒绝访问不存在的媒体引擎。
工具 69 项测试通过；`test_b3n` 用 `telemetry_sim.run_b3n` 及合法 NPU 描述符，
真实执行 input_pack、NPU 参考和 Python 后处理，localhost UDP 两张分别发 WIN0/1，
每张 CH2=983040 B、OUTPUT=725760 B、EDDT=1 框，字节/检测项差异均 0。
主机激励使用现有 send_blocks 的包间隔模拟线速；另测试缺失 OUTPUT 报错、文件夹队列、
完成计数/平均 fps 及保留原图尺寸；未把主机时间当实板性能。风格 0 文件/0 warning。
已删除全部版本条件宏：`network.c`/`network_npu.c`/`monitor.c` 保留公共逻辑，
视频 Surface/呈现、CH2/VIN 检查及媒体计数分别选 `network_video.c`、`network_video_npu.c`、
`monitor_video.c`；B3N 选 `demo_npu/network.c`、`demo_npu/monitor.c`，无空回调或运行时探测。
主机测试同步选择实际版本源文件；原三版本的搬移函数及展开后的 EDNM 操作序列与原提交一致。
日志：`build/sw/<程序>/rv32-refactor-build.log`、`build/sw/demo/host-refactor-test.log`、
`build/sw/demo_npu/tool-refactor-test.log`；大小前后记录在 `build/sw/demo_npu/refactor/`。
B3N ELF 无 vin_/pix_/geo_/disp_/rnd_ 链接符号；原获授权的 `sw/Makefile` 本次未改。
未改规格/RTL，未跑 SoC 仿真；实际识别、连续 N 张性能及 EDTM 曲线留卡 22 验收。
