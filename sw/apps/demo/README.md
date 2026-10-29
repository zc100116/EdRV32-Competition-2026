# B2 演示程序

依据：`docs/design/2026-10-29-b2-software.md` 全文、SoC 7.3–7.5，
驱动调用契约见 `sw/drivers/README.md`。默认 S2、PIX 旁路、GEO 关闭、HDMI、
视频目标 30 fps、DDR 监控 100 Hz；使用完整 SoC，不运行 SoC 仿真。

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
`rom.hex` / `sram.hex` / `ddr.hex`。在调试工具“烧录 SRAM”页选择 `demo.bin`，
按住 KEY1 再按复位；看到 BIOS 的烧录成功提示后，松开 KEY1 再按复位运行。
BIOS 不自动执行刚烧录的镜像。也可用同一 ELF 生成的 SRAM hex 初始化 bitstream。
程序、量化表、字库、100 项检测结果和状态全部在 SRAM；大块图像与候选工作区在 DDR。

启动打印 `Demo: EdRV32 B2 v1`、构建 commit/编译器、CHIP_ID/CLK_SYS_HZ、
全部八个引擎的实际 ID，以及两路摄像头的 chip ID 原始读值。
ID 只打印，不比较期望值，不设“自检通过才运行”的门禁。
SCCB NACK、引擎错误、帧 INCOMPLETE/BUS_ERR、错误 EDNM/图像长度会直接打印
相关原始寄存器并停止，保留场景，按复位重启；无重试或备用数据流。

## 串口命令表

115200、8N1；每条命令独占一行，CR、LF、CR LF 都支持。
命令区分大小写，不带首尾空格。成功后打印 `Demo command: OK`，
非法输入打印 `Input error`，保留当前场景。PC 每次等应答后再发下一条命令。

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
和 `draw_detection()` 已接在 `pipeline.c`，不留占位调用。
OUTPUT/底图在 CPU 访问前通过 BSP `engine_dma_invalidate()`，
画框后通过 `engine_dma_clean()`，然后才能交 DISP/ETH；这些驱动入口调用 BSP cache。
MODEL、描述符、EDDT/EDVF 和监控记录用非缓存别名。

每个 CH0/GEO Surface 分别保留处理中、显示和 ETH 引用；DISP 的待提交、已写 shadow、
当前扫描状态分别维护。FRAME 中断提交下一张，SWITCH/REL_BASE 释放旧张；
停止 HDMI 后等 IDLE，再释放最后一张。ETH 必须完成整个描述符列表的 DONE_COUNT，
才能解除其引用；只有全部消费者释放后才清 VIN SLOT_BUSY。
配置变化先停新帧、排空当前 VIN/NPU/GEO/ETH/DISP，再重设所选场景。

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
| BIOS 烧录后复位 | UART 出现 Demo 版本、实际引擎 ID、两路 camera chip ID（OV5640 通常 0x5640）；无 ERROR；菜单可接受 Enter 命令 |
| `s2`、`pix bypass`、`geo off` | HDMI 稳定 1280×720 摄像头画面，无错位、撕裂；VIN CH0 帧数持续增长 |
| `status` 两次 | 用 `ΔPERF0×CLK_SYS_HZ/Δmtime` 算 cam0 帧率；CH0 用 PERF3，S1 CH2 用 PERF5；测量时间段至少一秒，确认实际摄像头帧率，不拿 HDMI 60 Hz 当摄像头帧率 |
| 5 种 PIX 逐一切换 | 旁路原图、亮度/对比度增强、Gamma 提亮、高斯模糊、灰度 Sobel 边缘；无引擎错误，CH0 计数继续增长 |
| `geo rotate` / `geo scale` / `geo off` | 图像转 180° / 中心放大 2 倍 / 恢复；换帧完整，DISP 读空计数为零 |
| KEY2–4 | KEY2 S1/S2 切换；S2 下 KEY3/4 各循环 PIX/GEO；一次按下只有一次操作；S1 下后两键打印要求 S2 |
| PC 监听 6000 后发 WIN3 短包 | status 出现 PC peer IP/6000；调试工具 DDR 监控页出现 EDTM；无 peer 前本地 dropped 递增且画面照常 |
| 加载模型到 WIN2 | UART 打印准确 WIN2_BYTES、`EDNM: loaded`；不存在 hash/self-test 成功门禁；不正确 EDNM 显示头字/寄存器后停止 |
| 模型加载后 `s1` | HDMI 目标框、COCO 类名和千分比置信度标签；NPU 推理次数增长；调试工具检测帧率、NPU/后处理耗时有值；CH0/CH2 同帧，无错误 |
| YOLO 页发 WIN0 图像，再发 WIN1 图像 | 自动内存源；依次收齐 CH2 983040 B、OUTPUT 725760 B、EDDT；与工具 input_pack、NPU 参考、Python 后处理逐字节/逐项相同；两窗口可重复使用，收到最终 NOTIFY 后再发下一图 |
| `output hdmi` / `output eth` / `output both` | HDMI 正常/黑色但时序保留/正常；视频无/有/有；ETH-only 时监控 P0 读带宽停止；both 下 HDMI 与工具视频画面及 S1 frame_id 对应 |
| `fps 1` / `fps 15` / `fps 30` / `fps 60` | 30 fps 源分别名义 1/15/30/30 fps；S1 不超过推理率；核对收到帧号分频；带宽压力下 vid_skip 增长，显示 Surface 不被提前覆写；真实 60 fps 源另配置后验证约 111 MB/s 极限档 |
| `sample 10` / `sample 100` / `sample 1000` | EDTM WINDOW_CYC 随采样周期变化，帧率/带宽按实际窗口换算；vid_skip 在偏移 292；保留尾 24 B 全零；场景切换有尾批，seq 间隔显示丢记录 |
| DDR 监控页运行 S1/S2 | 端口读写堆叠图、利用率、等待、VIN 溢出/DISP 读空、NPU/后处理耗时符合页面字段；实时性异常计数正常应为零；保存 UART/CSV/必要视频截图作为实板证据 |
| 复位再次运行 | 同一 SRAM 镜像重新打印启动信息、默认 S2；data/bss 状态重建，没有沿用上次菜单状态；断电后按 BIOS/bitstream 初始化规则重新烧录 |

## 验证记录

Linux 仅验证 C11 构建和纯逻辑，未运行 Verilator、SoC 仿真、FPGA 或真实串口/PHY/HDMI。
构建/主机日志在 `build/sw/demo/{rv32-build.log,host-test.log}`；静态栈帧信息在
`build/sw/demo/obj/**/*.su`，供重复测量。最终 commit 与尺寸见本节后续记录。
