# System peripheral drivers

The C11 drivers use only bases and PLIC source numbers from generated
`sw/bsp/include/soc_map.h`. `include/{uart,gpio,i2c,clint,plic,sysctrl}.h` define
register offsets and fields from sys-subsys-spec section 4. MMIO accesses are
aligned 32-bit volatile accesses, including UART byte data and GPIO fields.
Compile with the BSP include directory and `sw/drivers/include`, using
`-std=c11 -Wall -Wextra -Werror`; the system program make fragments do this.

- UART: enable reset 115200 8N1, set a rounded fractional baud divisor, blocking
  transmit/receive, string output, and drain through the end of the stop bit.
  FIFO and error/IRQ fields are exposed in `uart.h`; the caller owns servicing
  receive errors and FIFO clear operations through the documented registers.
- GPIO: whole-word OUT/OE, debounced input, edge enables, RW1C IRQ acknowledge,
  and debounce period. The boot button is configured in `sw/boot/boot.h`.
- I2C: select port 0/1 only after BUSY clears, set the quarter-period divider,
  execute byte commands and wait for DONE. Write commands return `-1` on the
  specified NACK error and `0` on ACK; no retry is performed. After a NACK the
  caller handles the failure; SCCB helpers return immediately and do not issue
  further commands. `i2c_sccb_write/read(device, reg, ...)` use a 7-bit slave
  address, register high byte then low byte, and 8-bit data. Reads use a repeated
  START, then send NACK and STOP after the received byte. `i2c_command` also
  permits explicit STOP + START sequences. No clock stretching or arbitration.
- CLINT: high/low/high stable RV32 time reads, compare update in low=max/high/low
  order, and MSIP access. Time units are clk_sys cycles; get frequency through
  SYSCTRL `CLK_SYS_HZ`.
- PLIC: source priorities, full enable mask, threshold, pending, claim/complete.
  Source 0 means no interrupt; sources 1–15 and priority/threshold 0–7 follow
  the hardware contract. Clear the peripheral condition before completion.
- SYSCTRL: register definitions and read/write helpers for boot and SC software.

`sw/bsp/include/cache.h` and `sw/bsp/cache.c` provide range clean, invalidate,
clean+invalidate and whole-cache clean through CACHE_CTRL, waiting for BUSY to
clear. This is the BSP interface required by SoC 7.4; SC-06 uses it for DDR aliases.

Driver operations require the specified hardware state and valid API arguments;
there are no added timeouts, recovery paths or input gates. See
`sw/tests/sys/README.md` for SC tests and the software-only Spike checks.

`uart_input.h` / `uart_input.c` share Enter-terminated input between the ROM BIOS
and SRAM monitor. The caller owns `struct uart_input` (initialized to zero), so
BIOS has no mutable static SRAM state. `uart_read_selection()` consumes a whole
line, accepts a single character, and treats CR LF as one Enter.
`uart_input_binary_begin()` is called after draining the BIOS ready line; the
host must wait for that line before sending binary bytes.

# B2 媒体引擎驱动

依据：`docs/design/2026-10-29-b2-software.md` 3.2–3.5a、SoC 6.1/7.1–7.4，
各头文件逐函数标注模块规格条款。所有引擎 MMIO 地址、字段和描述符偏移来自
`sw/bsp/include/regs/` 与 `soc_map.h`；没有手写新寄存器地址。
驱动不做参数检查、重试、超时或错误恢复。调用者提供合法配置、空闲引擎和有效生命周期；
硬件错误由 `engine_poll()` 或中断回调中的原始 `irq/status/error` 上报。

| 头文件 | API（完整公开入口） | 作用 |
|---|---|---|
| `engine.h` | `engine_control`, `engine_poll`, `engine_irq_clear`, `engine_perf` | 公共 CTRL、状态/错误/完成数、RW1C、PERF |
| `engine.h` | `engine_irq_register`, `engine_irq_handle`, `engine_irq_dispatch` | PLIC 注册、处理已 claim 的源、单次 claim/handle/complete |
| `engine.h` | `surface_ring_slot`, `engine_dma_clean`, `engine_dma_invalidate` | 等间距 Surface 地址转槽号；调用 BSP cache 接口 |
| `vin.h` | `vin_camera_size`, `vin_channel_configure`, `vin_channel_enable` | 摄像头尺寸、CH0–2 源/环/跨距/使能 |
| `vin.h` | `vin_slots_busy`, `vin_frame_done`, `vin_frame_slot`, `vin_write_status` | 软件占用位图、原始完成信息与 frame_id、槽提取、当前写状态 |
| `vin.h` | `vin_memory_start`, `vin_memory_status` | 单帧内存源启动和状态 |
| `pix.h` | `pix_config_word`, `pix_configure`, `pix_gamma_load` | 点运算、两级 3×3、256 项 Gamma 表 |
| `geo.h` | `geo_q16`, `geo_descriptor_pack`, `geo_submit` | 有理数转 Q16.16、64 B 描述符打包和提交 |
| `disp.h` | `disp_submit`, `disp_current`, `disp_switched`, `disp_released` | v0.3 两层 Surface 提交、当前/释放地址和切换标志 |
| `disp.h` | `disp_layer_enable`, `disp_l0_scroll`, `disp_l1_geometry` | 两层使能、L0 卷轴、L1 位置/大小/OPA |
| `npu.h` | `npu_configure`, `npu_start`, `npu_current_descriptor` | 六项基址/数量配置、更新输入输出并启动、错误描述符定位 |
| `eth.h` | `eth_ipv4_pack`, `eth_local_configure`, `eth_peer_configure` | MAC/IP/端口（字节数组按网络顺序） |
| `eth.h` | `eth_window_configure`, `eth_window_bytes` | 四个接收窗口及已提交字节数 |
| `eth.h` | `eth_tx_descriptor_pack`, `eth_header_pack`, `eth_send` | 32 B TX 描述符、8 B 网络序应用头、提交 |
| `eth.h` | `eth_phy_reset`, `eth_mdio_write`, `eth_mdio_read` | PHY 复位电平、阻塞 Clause 22 访问 |
| `mem_xbar.h` | `mem_xbar_snapshot`, `mem_xbar_rate`, `mem_xbar_error` | SNAPSHOT\|CLEAR 后读七端口统计、RATE、错误详情 |
| `ov5640.h` | `ov5640_table`, `ov5640_init`, `ov5640_chip_id` | 双端口初始化、252 项 720p30 表及长度、读取芯片 ID |

`geo_q16(n,d)` 用有符号 64 位中间数计算 `n*65536/d`，向零截断；分母非零、结果
适合 int32 是调用者契约。矩阵顺序是 **A, B, TX, C, D, TY**，描述符由
`geo-spec` 2.6 的生成宏打包，保留字置零。`struct geo_descriptor` /
`struct eth_tx_descriptor` 是 64 / 32 B 的字数组，小端 RV32 上可直接放 DDR；
表首地址另由调用者保证 32 B 对齐。NPU 描述符由离线工具产生，驱动不重建模型。
`surface_ring_slot(base, first, spacing)` 返回 `(base-first)/spacing`，这里 spacing 是
分配间距（CH0 为 2 MiB，CH2 为 1 MiB），不是有效图像字节数；只对本环的槽首地址调用。

所有传给引擎的地址都是 **DDR 物理地址**，例如 `0x06000000`；CPU 的缓存地址为
`EDRV32_DDR_BASE + physical`，非缓存地址为 `EDRV32_DDR_UNCACHED_BASE + physical`。
上述 B2 接口不隐式 clean/invalidate（RND 批次接口见下节）：调用者按 SoC 7.4
在 CPU 写完/引擎读取前调用 `engine_dma_clean(cached_address, bytes)`，在引擎写完/CPU
读取前调用 `engine_dma_invalidate(cached_address, bytes)`，或始终使用非缓存别名。
GEO 的源/目标、ETH 的载荷/描述符、NPU 的模型/描述符等分别维护；只 clean 描述符不足以
覆盖 CPU 修改过的载荷。DMA 写入目标先前若有 CPU 脏行，交接前通过 BSP
`cache_clean_invalidate()` 放弃 CPU 所有权；完成后再 invalidate。

PLIC 源号按生成头：VIN=8、PIX=9、GEO=10、DISP=12、NPU=13、ETH=14、MEM_XBAR=15。
`engine_irq_register(engine, irq_mask, priority, callback, context)` 只用于上述七个有源引擎，
在 CPU MEIE/MIE 开启前调用；它保留其他 PLIC enable 位，不修改 threshold。
应用设置 `plic_set_threshold(0)` 并启用 CPU 中断。
回调拿到 IRQ、STATUS、ERR_CODE、DONE_COUNT 的值拷贝，在回调内读取 VIN 完成信息、
DISP REL_BASE 或 MEM_XBAR 错误详情；回调返回后驱动清除本次捕获的 IRQ，再 complete。
回调内不重复 RW1C。ERR_CODE 清零前的值保存在 event 中，必须由应用显式处理/上报。
`engine_irq_dispatch()` 适用于只开启这些已注册媒体源的应用；若同时开启 UART/GPIO，
由应用自己 `plic_claim()` 分流，媒体源调用 `engine_irq_handle(source)` 后由应用
`plic_complete(source)`。驱动不接管 trap vector，也不设置 CLINT 中断。

**S2 典型顺序。** `ov5640_init(0, clk_sys_hz)`（双目再初始化 camera 1），
`vin_camera_size()`；配置 CH0 的四个 2 MiB 槽、stride=2560、SRC=VIN_CAM0。
`pix_gamma_load()` 写未使用 bank，`pix_configure()` 设置点运算和两级滤波，
`engine_control(ENGINE_PIX, EDRV32_PIX_CTRL_ENABLE_MASK)`；注册 VIN FRAME/ERROR、
DISP FRAME/SWITCH/ERROR，最后使能 VIN。VIN FRAME 回调读取 `vin_frame_done(0)`，
保留 info 中 INCOMPLETE/BUS_ERR；应用选用该帧后置 SLOT_BUSY，再 `disp_submit(base,2560)`
并使能 DISP。新帧可选经 `geo_descriptor_pack()` → coherent 描述符 → `geo_submit()`，
GEO DONE 后提交其输出 Surface。DISP SWITCH 时读取 `disp_released()`，旧 Surface 的
其他消费者也已完成后清占用。PIX 参数在 SOF 锁存，Gamma 用非活动 bank 双缓冲；
DISP 参数在 FRAME 中断后集中提交，下一 VBlank 生效。停止 DISP 后须等 IDLE 才释放最后
一张 Surface；ENABLE=0 不再产生后续 SWITCH，不能无限等释放中断。

**S1 典型顺序。** PIX 旁路；CH0 四槽、CH2 三槽同时选择一个源（CH2 stride=2560）。
`npu_configure()` 一次配置 MODEL/WORK/DESC/count，CH2_FRAME 回调读两路完成状态，
按相同 frame_id 配对。只有 NPU 空闲才占用该 CH2 槽和匹配的 CH0 槽，然后
`npu_start(input_slot, output_buffer)`；NPU 忙时应用跳过新帧。
NPU DONE 后对 OUTPUT invalidate（缓存 CPU 访问时），将输出交给后处理，并在 NPU
最后读事务完成后释放 CH2 输入；应用可切换 OUTPUT 双缓冲启动下一帧。
CPU 在保留的 CH0 Surface 画框，clean 修改范围后 `disp_submit()`。
DISP SWITCH 和 ETH DONE_COUNT 都满足释放条件后才解除该 CH0 SLOT_BUSY。
全部 bitmap 更新由应用串行化；DISP/ETH 共用的占用由应用合并，驱动不隐式改环状态。
NPU 的 DONE_COUNT 是完成描述符数；应用在整次 DONE 时增加推理次数。

**网口加载/视频典型顺序。** 按 PHY 手册控制 `eth_phy_reset(1/0)` 和等待间隔，
必要时 `eth_mdio_read/write()`，再 `eth_local_configure()`、`eth_peer_configure()`、
配置四个窗口，注册 RX_NOTIFYn/ERROR/DONE 并使能 ETH。RX_NOTIFYn 后读
`eth_window_bytes(n)`，应用按设计记录核对字节数/EDNM 基址，复制模型/描述符到 NPU 区，
CPU 使用缓存时做 clean；网口测试图用 `vin_memory_start()` 同时送 CH0/CH2。
内存源 DONE 仅表示读完，后续 CH0/CH2 FRAME 才表示目标写完。
TX 用 `eth_tx_descriptor_pack()`，clean 描述符和 CPU 写过的载荷，再 `eth_send()`；
硬件每包切 1024 B 并构造应用头，不需 CPU 复制像素。
一帧视频为两条描述符：32 B EDVF 帧头（OFFSET=0）和原地 RGB565（LEN=1843200、
OFFSET=32、NOTIFY=1）。LEN=0 表示零数据包，仍由硬件发出。
不在 ETH BUSY 时重配 TX 地址/端口或提交新列表；应用以 DONE_COUNT 前进确认源缓冲
可释放。下一块接收前重新 `eth_window_configure()` 清计数。
HDMI/网口/同时由应用控制 DISP ENABLE 和是否提交 ETH；关闭 HDMI 后先等 DISP IDLE。

**监控上报典型顺序。** CLINT 100 Hz 定时回调里 `mem_xbar_snapshot(&stats)`，一次写
SNAPSHOT|CLEAR 后读出冻结值；读取 `engine_perf(ENGINE_VIN,3/5/6/8)` 等求回绕增量，
拼设计记录规定的 320 B 小端 EDTM，应用每 16 条经 WIN3 描述符发送。
`mem_xbar_rate(6, rate)` 的单位为 1/256 beat/cycle。

OV5640 移植依据与差异（T-CAM30 更新默认时序）：

- 来源：本机厂商 `SOC系统设计/doc/fpga/pago_200/2_Demo/5_1 双目摄像头例程/`
  `ov5640_200k/rtl/camera/data_init.v` 的 **0–243，共 244 项**。
  经协调者确认删除 244–247 四项占位（向只读 ID 寄存器 `0x300a` 写 0）。
- B2 初版与 `legacy/rtl/vision/camera/ov5640_720p.hex` 的前 244 项逐项比较，0 处差异；
  T-CAM30 在此基础上按下表修改，当前共 252 项。
  旧 hex 共 512 行，其 244–247 同为上述占位，248–511 为零填充；均未移植。
  `legacy/sw/hal/drivers/cam.c` 没有初始化表；核对其芯片 ID 高/低字节位置为
  0x300a/0x300b、镜像/翻转寄存器为 0x3821/0x3820、测试图寄存器为 0x503d。
- `0x4300=0x61`、`0x501f=0x01` 选择 RGB565/RGB；
  `0x3808..0x380b=05 00 02 d0`，尺寸 1280×720。
  当前默认表为标称 30 fps，时钟/时序计算见下文；实际帧率仍须上板测量。
- 表不写 `0x4740`，沿用复位值 `0x20`。极性沿用默认，与 legacy 板上结果一致，
  上板再确认一次。配套 legacy 采集模块按 HREF 高有效、VSYNC 下降沿帧开始、PCLK
  上升沿采样，与 vin-spec 2.1 一致；厂商采集模块也按 VSYNC 下降沿开始。
  [OV5640 数据手册](https://cdn.sparkfun.com/datasheets/Sensors/LightImaging/OV5640_datasheet.pdf)
  的 0x4740 极性说明与此存在文字差异，
  [Linux OV5640 驱动](https://gbmc.googlesource.com/linux/+/9a5523f72bd2b0d66eef3d58810c6eb7b5ffc143/drivers/media/i2c/ov5640.c)
  也记录了 VSYNC 手册与硬件极性相反；经协调者确认保持原表，不额外写极性寄存器。
- 两路摄像头分别选 I2C0 port 0/1，7 位地址 0x3c（线上写地址 0x78）。
  GPIO bit12/13、14/15 为 PWDN/RST_N，保留其他 GPIO 位；复位等待按厂商 camera.v
  的 5 ms、1.3 ms、21 ms 顺序，用 CLINT 实现，然后 100 kHz SCCB 连续写表。
  这些是器件复位时序，不是超时兜底；首个 NACK 立即返回 -1。
  上电先调用 init，再 chip_id；后者只选端口读 ID，不重复复位，也不判断芯片型号。

### T-CAM30：默认 1280×720 RGB565 DVP，标称 30 fps

依据：

- **D**：[OmniVision OV5640 datasheet v2.03, 2011-05-26](https://cdn.sparkfun.com/datasheets/Sensors/LightImaging/OV5640_datasheet.pdf)，
  §2.5（VCO 上限 800 MHz）、§7.1 `0x3034..0x3037`（PLL 分频/倍频）、
  §7.2 `0x3108`（根分频）、§7.7（窗口/时序）、§7.8（AEC）、
  §7.17 `0x460c[1]`（DVP PCLK 自动/手动分频）、§5.9（缩放开关）。
- **L**：[Linux v6.12 drivers/media/i2c/ov5640.c](https://github.com/torvalds/linux/blob/v6.12/drivers/media/i2c/ov5640.c)，
  `ov5640_mode_data[OV5640_MODE_720P_1280_720].dvp_timings`、
  `ov5640_setting_720P_1280_720`、`ov5640_set_timings` 为裁剪/时序与模式寄存器来源；
  时钟树注释、`ov5640_calc_pclk`、`ov5640_set_dvp_pclk`、`ov5640_get_sysclk`
  补充 bit divider 与 DVP PCLK/SCLK 关系；`ov5640_set_bandingfilter` 给出消闪计算。
  数据手册未完整说明 bit divider 和自动 DVP 分频链，因此这部分按 Linux 驱动推导，
  不是已经取得的硬件测量值。

每个修改/新增寄存器如下（十六进制；“未写”指旧表依赖复位值）：

| 寄存器 | 旧值 → 新值 | 来源与用途 |
|---|---|---|
| `3034` | 未写（复位 `1a`）→ `18` | D §7.1 + L DVP：8-bit bit divider=2，保留 charge pump |
| `3035` | `11` → `20` | D §7.1 + L `set_dvp_pclk`：system divider=2，DVP P_DIV bypass=0 |
| `3036` | `3c` → `54` | D §7.1 + 下列计算：multiplier=84，VCO=672 MHz |
| `3c07`（后一次写） | `08` → `07` | L 720P 表的光频检测设置；前一次写 `08` 保留 |
| `3803` | `00` → `fa` | L DVP analog crop：top=250（`3802=00` 不变） |
| `3806`, `3807` | `07 9f` → `06 a9` | L：bottom=250+1456−1=1705 |
| `380c`, `380d` | `09 c0` → `07 64` | L：HTS=1892 |
| `380e`, `380f` | `04 c8` → `02 e4` | L：VTS=720+20=740 |
| `3a02`, `3a03` | `17 10` → `02 e4` | L 720P 表：60 Hz 最大曝光限制为 VTS |
| `3a14`, `3a15` | `17 10` → `02 e4` | L 720P 表：50 Hz 最大曝光限制为 VTS |
| `3a08`, `3a09` | 未写（复位 `01 27`）→ `00 dd` | D §7.8 + L banding 公式：50 Hz step=221 行 |
| `3a0a`, `3a0b` | 未写（复位 `00 f6`）→ `00 b8` | 同上：60 Hz step=184 行 |
| `3a0d` | 未写（复位 `08`）→ `04` | L：floor((740−4)/184)=4 个 60 Hz band |
| `3a0e` | 未写（复位 `06`）→ `03` | L：floor((740−4)/221)=3 个 50 Hz band |
| `460b` | 未写（手册未给复位值）→ `37` | L 720P VFIFO 模式设置（手册列为 debug） |
| `460c` | `22` → `20` | D §7.17 + L 720P：清 manual bit，使用自动 DVP PCLK 分频 |
| `5001` | `a3` → `83` | D §5.9 + L 720P：关闭 scaler，保留 AWB/色彩矩阵/SDE |

Linux 720P 表也写 `3824=04`，但 `460c[1]=0` 时手动分频值不生效，
本表不新增该无效写入；不移植 Linux 的 MIPI 配置。
`3037=13`、`3108=01` 保留：pre-divider=3、PLL root divider=2、
SCLK root divider=2、PCLK root divider=1。`3034[3:0]=8` 的 bit divider=2；
原来未写的 `3034` 复位为 `1a`（bit divider=2.5）。

以传感器 **XCLK=24 MHz** 为计算输入（上板需确认实际晶振频率）：

```text
VCO      = XCLK / pre-divider × multiplier = 24 / 3 × 84 = 672 MHz
pll_clki = VCO / system divider / PLL root divider / bit divider
         = 672 / 2 / 2 / 2 = 84 MHz
PCLK     = pll_clki / PCLK root divider = 84 / 1 = 84 MHz
SCLK     = pll_clki / SCLK root divider = 84 / 2 = 42 MHz
HTS×VTS  = 1892 × 740 = 1,400,080 SCLK cycles/frame
fps      = 42,000,000 / 1,400,080 = 29.998286 fps
line     = 1892 / 42,000,000 = 45.047619 us
50Hz step = floor(42,000,000 / 1892 / 100) = 221 lines
60Hz step = floor(42,000,000 / 1892 / 120) = 184 lines
```

RGB565 在 8-bit DVP 上每像素传两字节，PCLK 是字节传输时钟，
HTS/VTS 使用 SCLK；不能直接用 84 MHz 除以 HTS×VTS 算帧率。
PCLK=84 MHz，周期约 11.905 ns，低于 `fpga/constraints/*` 中
`clk_cam0/1` 的 10 ns（100 MHz）约束上限；VCO 低于 D 的 800 MHz 上限。
旧配置按相同公式（bit divider=2.5、system divider=1、multiplier=60）得
VCO=480 MHz、PCLK=96 MHz、SCLK=48 MHz，48,000,000/(2496×1224)=15.711413 fps，
与任务背景约 15.7 fps 相符，仍只是时序公式对照。

视场从原 4:3 全阵列缩放变为 **16:9 中央裁剪**：模拟窗口从
`(0,0)..(2623,1951)` 变成 `(0,250)..(2623,1705)`，
按 L 保留 `3814/3815=31` 的行列子采样以及 ISP offset `(16,4)`，
输出 1280×720，关闭缩放；上下视场减少，水平视场基本保留。
`31` 表示奇/偶采样步进 3/1，并非隔行扫描视频。
保持 `4300=61` 的 RGB565 高字节先传、`501f=01` 的 RGB 输出、
`3820/3821` 翻转/镜像、`4740` 复位极性、`503d=00` 测试图关闭及原 DVP 接口；VIN 无需修改。
AEC night mode 仍保持 `3a00` 复位 `78`（bit2=0），不启用降帧曝光。
不增加 60 fps 表、帧率参数、重试或回退路径。

Linux 验收仅包括构建和 host 检查；host 按最终寄存器值解码 PLL、根分频、
HTS/VTS，要求 PCLK≤100 MHz、fps∈[29.5,30.5]，并检查裁剪、格式及消闪设置。
**30 fps 的实际结论只由上板验证**：两路 `VIN camera0/1 frames` 每秒约增加 30，
HDMI/网口画面无撕裂、无错位，VIN 溢出计数为 0；同时确认实际 PCLK/XCLK。

```sh
. ~/.local/opt/edrv32/env.sh
make -C sw PROGRAM=demo_vision MEMORY=sram -j1
make -C sw PROGRAM=demo_npu MEMORY=sram -j1
make -C sw PROGRAM=demo_vnpu MEMORY=sram -j1
make -C sw PROGRAM=demo MEMORY=sram -j1
make -C sw PROGRAM=drivers_build MEMORY=sram -j1
make -C sw/tests/drivers_build test
git diff --check
```

2026-10-31，基于 `2a3ee2e0` 加 T-CAM30 改动，以上五个 SRAM 程序均构建通过，
0 warning、0 error，构建日志为 `build/ov5640-30fps/<PROGRAM>.log`；
GCC host 检查 PASS，报告 VCO=672000000 Hz、PCLK=84000000 Hz、SCLK=42000000 Hz、
HTS=1892、VTS=740、29.998286 fps；`git diff --check` 通过。
未运行 RTL 仿真或上板测试，硬件验收待 Windows 端完成。

B2 初版验收命令（仓库根目录，只验 C 编译和纯逻辑）：

```sh
. ~/.local/opt/edrv32/env.sh
make -C sw PROGRAM=drivers_build MEMORY=sram -j1
make -C sw/tests/drivers_build test
riscv-none-elf-size build/sw/drivers_build/drivers_build.elf
git diff --check
```

`drivers_build/main.c` 对全部驱动入口建立可达地址表，防止链接时 `--gc-sections`
删掉未用驱动，确保所有驱动和 BSP cache 真正链接；不执行 MMIO。
主机测试链接实际驱动 C，BSP cache 仅提供调用即终止的链接符号；测试不碰硬件，
覆盖 GEO 描述符和 Q16.16、ETH 描述符/网络序头/IP、CH0/CH2 Surface 槽映射、
VIN DONE_INFO 槽提取、PIX Gaussian+Sobel CFG、OV5640 表长度/关键寄存器/时钟与帧率。
期望值是规格布局的独立字面值，没有使用被测打包函数构造期望。

2026-10-29 在实现提交 `9fa9bcf` 上的结果：xPack RISC-V GCC 15.2.0 的全部驱动
编译/链接成功，0 warning、0 error，产出 ELF、dis、rom/sram/ddr hex；
GCC 13.3.0 主机纯逻辑测试 PASS，0 warning、0 error；`git diff --check` 通过。
完整命令输出分别在 `build/sw/drivers_build/rv32-build.log`、`host-test.log`。
`riscv-none-elf-size`：text=10460 B、data=0 B、bss=268 B，总计 10728 B
（包含原有系统驱动、全部新驱动、OV5640 表、接受测试和 BSP；不含栈）。
未运行 SoC 仿真/Verilator；功能效果、实际摄像头帧率/极性、PHY/HDMI 待上板验收。

提交关系：`f1dd1f4` 冻结首版 API；协调者 `be1848f` 补全 GEO 描述符生成头，本分支
以 `039850f` 复用；`9fa9bcf` 为完整实现与验收程序。无其他规格/设计布局偏差；
OV5640 占位删除、帧率及默认极性处理均已通过协调者 ask 确认。

## B3：RND 与 DISP v0.3

RND 依据 `rnd-spec.md` v0.2，DISP 依据 `disp-spec.md` v0.3。
参数范围、对齐、源读取范围、COPY 以外的非重叠条件由调用者保证，驱动不检查。
交给 DISP 的 Surface 必须满足 SoC 7.3；正在扫描的 Surface 禁止写入。

| RND 函数 | 用途 |
|---|---|
| `rnd_fill` | 编码纯色/线性渐变、圆角填充；四个有符号 Q15.16 步长 |
| `rnd_border` | 编码指定边、宽度和半径的边框 |
| `rnd_glyph` | 编码 A8/A4/A2/A1 掩码着色 |
| `rnd_blit` | 编码缩放/翻转、颜色键、重着色、四种混合和调色板 |
| `rnd_copy` | 编码同格式逐位搬运，支持规格规定的重叠 |
| `rnd_box_shadow` | 编码圆角阴影，显式提供临时区 |
| `rnd_blur` | 编码原地两遍模糊，显式提供临时区 |
| `rnd_tilemap` | 编码 8/16 像素瓦片地图及调色板 |
| `rnd_physical` | 由生成头的两个 DDR 别名基址换算物理地址 |
| `rnd_submit` | clean 命令及声明的源区，写 DESC_BASE/COUNT，再写 DOORBELL |
| `rnd_wait` | 轮询 DONE/ERROR，等在途事务排空，返回 irq/error/cur_desc |
| `rnd_irq_register` | 注册回调、设置 RND DONE/ERROR 及 PLIC 源 11 的优先级/使能 |
| `rnd_irq_handle` | 服务应用已 claim 的源 11，完成 cache 交接并通知回调 |
| `rnd_abort` | 请求 ABORT，等 IDLE，返回捕获结果并交回目标区 |

编码函数只写调用者 DDR 数组中的一条 64 B 命令；**列表起点**须 64 B 对齐。
描述符中的所有地址均为物理地址。`rnd_batch` 中命令和范围地址则为 CPU 地址；
范围数组需存活到完成，单次只允许一个在途 batch。

`rnd_submit()` 只执行 rnd 5.4 的 cache 维护；源区应包括 CPU 修改过、将被 RND
读取的数据（图片、字体、调色板、地图等），以及读改写需要的 CPU 修改目标像素。
RND 完成或停止后，驱动在 CPU 再次访问前 invalidate 调用者声明的目标区；
临时区若需要 CPU 读取，也应列入目标区。LVGL 软件单元接手前必须等这一交接，
软件单元修改的像素则在下次提交时作为源区 clean。未声明区域不作 cache 操作。

ERROR 先等总线排空，读 `ERR_CODE`/`CUR_DESC`，最后 RW1C；返回值保留清除前的错误。
不重试、不复位、不恢复。ABORT 后部分结果保留。轮询与中断完成路径不可同时消费同一批。
IRQ 方式由应用安装 trap、设置 mie/mstatus，并在 claim/complete 之间调用处理函数：

```c
unsigned int source = plic_claim();
if (source == EDRV32_PLIC_SOURCE_RND) {
    rnd_irq_handle();
} else if (source != EDRV32_PLIC_SOURCE_NONE) {
    engine_irq_handle(source); /* 仅适用于已注册的其他媒体源 */
}
if (source != EDRV32_PLIC_SOURCE_NONE) {
    plic_complete(source);
}
```

回调发生在目标 invalidate 和 IRQ_STAT 确认之后，可以提交下一批；PLIC completion
仍由上层负责。普通 `engine_irq_dispatch()` 不替应用路由 RND 专用回调。
轮询使用 IRQ_EN=0（复位状态）；切换为轮询时由调用者关闭 RND IRQ_EN。

| DISP 函数 | 用途 |
|---|---|
| `disp_submit(layer, base, stride)` | 向 L0/L1 提交下一帧 Surface，替代 v0.2 两参数接口 |
| `disp_layer_enable` | 分别使能 L0 或 L1，保留另一层使能位 |
| `disp_l0_scroll` | 配置 L0 像素卷轴 X/Y |
| `disp_l1_geometry` | 配置 L1 位置、大小和整体 OPA；X/W 按 8 像素粒度 |
| `disp_current` | 分层读取 CUR_BASE |
| `disp_switched` | 读取对应层 SWITCH 标志，不清除 |
| `disp_released` | 分层读取 REL_BASE，结合捕获的 SWITCH 使用 |

同一帧生效的一组配置由调用者在 FRAME 后一次写完。两层分别保留扫描、shadow-next
和待提交 Surface 的所有权；只改位置/大小/卷轴/OPA 不释放 Surface。
v0.3 第一次启用不报告复位基址 0 的释放；关闭图层可在后续 SWITCH 释放，
关闭整个 DISP 则等 IDLE 后释放最后的占用。B2 demo 已迁移到显式 `DISP_L0`。

B3 验收命令及硬件检查见 [`rnd_board/README.md`](../tests/rnd_board/README.md)
和 [`demo/README.md`](../apps/demo/README.md)。不执行 SoC 仿真。
