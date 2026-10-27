# 旧工程图像通路盘点

| 项 | 内容 |
|---|---|
| 日期 | 2026-10-27 |
| 状态 | 参考资料 |
| 范围 | `legacy/rtl/vision/{camera,display,pixel,geometry,control}` 及这些文件引用的公共模块；旧工程板级/约束文件查找结果 |
| 关联 | `docs/design/2026-10-27-image-path.md`；SoC 规格 v0.7；旧视觉架构与像素处理设计 |

本文记录仓库中可查到的 RTL、仿真说明和设计记录。文中“板上验证”只在旧文档明确声称上板时使用；仿真通过不等于板上验证。端口宽度均按 RTL 声明；单比特信号未标宽度。表中端口时钟以模块时钟输入为准，跨时钟端口单独注明。行数包含注释和空行。

## 1. 旧文件、端口、状态和原语

接口缩写：`AXI256-W/R` 表示 AXI 写/读通道（地址 32、ID 4、LEN 8、SIZE 3、BURST 2、DATA 256、WSTRB 32，均按该旧模块端口声明）；`S258` 表示旧流 `{sof,eof,16×RGB565}` 258 位；`P2` 表示内部每拍两个 RGB565、每像素 16 位并带 SOF/EOF/SOL/EOL；`APB` 为地址/数据 32 位、WSTRB 4 位的 APB4 从口。常规控制、状态端口均为 1 位，文中单列的计数/地址/数据端口注明位宽。

### 1.1 camera

| 文件（行） | 功能；接口分组、位宽、时钟 | 状态/缓冲；IP/原语 |
|---|---|---|
| `edrv32_ov5640_capture.v` (168) | DVP `data[7:0],href,vsync` 输入和使能/初始化；S258 valid/ready 输出；frame-active、32 位帧计数、overflow。单 `clk_i`，旧顶层接相机 PCLK。 | 字节相位、像素/16 像素 lane 计数和 256 位打包寄存器；先丢弃 2 帧；满时丢当前帧。代码内将 init_done、enable 直接两级寄存器同步（新工程应改公共 CDC 原语）。无 RAM/IP。 |
| `edrv32_camera_fifo.v` (82) | 写端 `wr_clk/wr_rst_n/data[257:0]/valid/ready/almost_full`；读端 `rd_clk/rd_rst_n/data[257:0]/valid/ready`。 | 后端选择器；FPGA 分支例化 Pango `cam_fifo`，注释规格 1024×258；SIM 分支例化旧公共 `edrv32_async_fifo`。 |
| `edrv32_camera_axi_writer.v` (192) | S258 输入；完成 buffer/base、帧计数、active/error 状态输出；AXI256-W 主口。单 DDR `clk_i` 域。 | `STATE_SYNC/AW/W/B`；两块交替缓冲，聚集完整 DDR beat/burst，收到末尾 B 后发布完成帧。 |
| `edrv32_camera_stream_mux.v` (101) | 两路 S258 valid/ready 输入；一条 S258 输出；选择、active-camera、error。单 `clk_i`。 | 选源在帧边界提交；排空未选输入并等待新 SOF，避免拼帧；无 RAM/IP。 |
| `edrv32_camera_select.v` (53) | 单时钟按键 `button_n_i` 输入、1 位选择输出。 | 按键去抖/边沿检测和选路状态。无板级 IO 原语。 |
| `edrv32_ov5640_sccb.v` (259) | 单时钟命令（start/read、寄存器地址 16、写数据 8）；SDA 输入及 SCL/SDA-drive-low 输出；busy/done/error/read-data。 | `STATE_IDLE/START/SEND/DONT_CARE/RESTART/READ/MASTER_NA/STOP` 与字节 phase 状态；开漏 SDA 由顶层三态。默认参数 27 MHz、250 kHz。 |
| `edrv32_ov5640_reg_rom.v` (50) | 单时钟 ROM 地址 8 位、数据 24 位。 | 同步 ROM；FPGA 例化 `cam_rom`，配置注释为 512×24；SIM `initial/$readmemh` 从同一 hex 读入。 |
| `edrv32_ov5640_stereo_init.v` (240) | 配置请求 toggle、摄像头选择、读写、寄存器地址 16/数据 8；双路 SCL、SDA-in/drive-low、复位和 init-done；响应 toggle/error/data。27 MHz 默认控制域。 | `RESET/SETTLE/ROM/START/WAIT/DONE/RUNTIME_WAIT/ERROR`；单 ROM/SCCB 引擎串行配置 cam0 后 cam1。默认 reset 65,536 周期、settle 1,048,576 周期；请求 toggle 有本地两级同步。 |
| `edrv32_stereo_hdmi.v` (997) | 旧视觉子系统组合顶层：控制、DDR、像素、串行四个时钟/复位组；双路 DVP；S258 控制配置、几何模式配置；AXI256-W/R；双路相机 SCCB 和 HDMI TMDS 差分输出；多项计数/错误/telemetry。 | 组合相机 init/capture/FIFO/mux/PIX/GEO/DDR writer/HDMI pageflip/FIFO/scanout/TMDS。跨域依赖旧 `edrv32_async_fifo`、`edrv32_counter_cdc`、自写 toggle 同步/复位逻辑；不应直接复制为新 SoC 顶层。顶层没有 PLL 实例。 |

### 1.2 display

| 文件（行） | 功能；接口分组、位宽、时钟 | 状态/缓冲；IP/原语 |
|---|---|---|
| `edrv32_colorbar_axi_writer.v` (211) | start/busy/done/error；AXI256-W。单 DDR 时钟。 | 单次色条帧写；`IDLE/AW/W/B/DONE`。 |
| `edrv32_colorbar_hdmi.v` (246) | bring-up 组合顶层：DDR/pixel/serial 三时钟；start；AXI256-W/R；TMDS 差分输出、reader/error/underflow 状态。 | 色条 writer + HDMI reader + async FIFO + scanout + TMDS TX；注释称是 P2 bring-up 路径。 |
| `edrv32_display_axi_writer.v` (290) | S258 输入；release buffer、completed buffer/base、帧/drop 计数和 active/error；AXI256-W。单 DDR 时钟。 | `SYNC/FILL/AW/W/B`；三缓冲槽、最多 16 拍暂存后再申请 AW；释放信号控制重用，完整写响应后发布。 |
| `edrv32_frame_composer.v` (272) | 双路 frame-ready/base/帧号和选择输入；显示 frame token/base 输出；AXI256-W/R。单 DDR 时钟。 | `IDLE/AR/R/AW/W/B`；旧版 1:1 RGB565 整帧拷贝，未包含合成器。 |
| `edrv32_hdmi_axi_reader.v` (168) | start/active/prefill/frame/error；AXI256-R；256 位 FIFO valid/ready。单 DDR 时钟。 | `IDLE/AR/R`，单个 outstanding burst；读 FIFO 背压 AXI 返回。 |
| `edrv32_hdmi_axi_reader_pageflip.v` (250) | display valid/ready、buffer 索引、base；release token；active buffer/prefill/frame/error；AXI256-R 和 256 位 FIFO 流。DDR 时钟。 | `IDLE/AR/R` 与 burst-last 跟踪；帧边界换前台 buffer，最后一拍读完后归还旧 buffer。 |
| `edrv32_hdmi_fifo.v` (165) | DDR 写侧和 pixel 读侧各自时钟/复位；两侧 256 位 valid/ready；almost-empty 和 2 位 local-count。 | Pango `hdmi_fifo` 注释配置 512×256、almost-empty 阈值 64；本地两词队列遮蔽同步读延迟；SIM 用旧 async FIFO 模型。 |
| `edrv32_hdmi_scanout.v` (159) | 单 pixel 时钟；enable/output-enable；256 位 FIFO输入 valid/ready；RGB 24、HS/VS/DE、坐标 16×2、帧和 underflow 计数。 | 两个 RGB565 像素/beat 拆成输出像素；例化 timing；无帧 RAM。 |
| `edrv32_hdmi_timing.v` (71) | 单 pixel 时钟；enable；HS/VS/DE、坐标 X/Y 各 16、frame-start。 | 水平/垂直计数器；默认 1280/110/40/220 与 720/5/5/20，正极性。 |
| `edrv32_tmds_encoder.v` (126) | pixel clock/reset；8 位 channel data、control0/1、DE；10 位符号。 | TMDS transition minimization 与 running disparity 状态；控制期输出控制符。 |
| `edrv32_tmds_serdes.v` (142) | pixel-clock/serial-clock、serial reset、10 位 TMDS 符号；差分单 lane 输出。 | 两级串行域复位释放寄存器；FPGA 例化 `GTP_OSERDES_E2` 主/从级联，`DDR10TO1`，另有 `GTP_OUTBUFDS(IOSTANDARD="TMDS")`；非 FPGA 分支只输出 symbol bit0。含 `ifdef`，按旧项目适配层看待。 |
| `edrv32_tmds_tx.v` (93) | RGB[23:0]、HS/VS/DE，pixel/serial 时钟与复位；TMDS clock 一对和数据三对差分输出。 | 三个 8b→10b encoder，四个 serializer（RGB + clock）；clock symbol 固定 `10'b1111100000`。 |

### 1.3 pixel

| 文件（行） | 功能；接口分组、位宽、时钟 | 状态/缓冲；IP/原语 |
|---|---|---|
| `edrv32_pixel_pipeline.v` (181) | S258 输入/输出 valid-ready；点处理配置：enable/灰度/阈值/反色、亮度 signed 9、对比度 9、阈值 8；空间模式 3 和阈值 8；配置 pending/帧计数。单 clk_mem 设计。 | 解包→点运算→共享 3×3 窗口→重包；各内部阶段 P2。 |
| `edrv32_pixel_unpack_2p.v` (107) | S258 valid-ready 输入；两个 RGB565(16) 输出及 SOF/EOF/SOL/EOL、P2 valid-ready。 | 16 像素包每拍拆出 2 像素；低 16 位为 lane0；控制边界计数寄存器。 |
| `edrv32_pixel_point_pipe.v` (445) | P2 valid-ready 输入/输出；配置控制和 9/8 位参数、pending。单 clk。 | 深度 8 输入队列 + s0–s4 五个流水 valid；逐帧 shadow/active 配置和像素携带的配置 sideband。 |
| `edrv32_pixel_window_3x3_2p.v` (593) | P2 输入/输出 valid-ready；空间使能、mode[2:0]、threshold[7:0] 与 pending。单 clk。 | 三个旋转 line RAM，各存 1024×32（每地址一对 RGB565）；上下行窗口对齐、水平三列寄存器、首尾行补零/帧尾 flush；RAM 实际被例化三次。 |
| `edrv32_pixel_filter_3x3.v` (113) | 九个灰度像素输入（各 8）、中心 RGB565 16、使能、模式 3、阈值 8；RGB565 16 输出。组合逻辑，无时钟。 | Sobel、mean、Gaussian、sharpen、erode、dilate 和 bypass 的组合运算。 |
| `edrv32_pixel_pack_2p.v` (72) | 两像素 P2 与 SOF/EOF valid-ready；S258 valid-ready 输出。单 clk。 | 8 个双像素 beat 组装 16 像素，输出 `{sof,eof,pixels[255:0]}`。 |
| `edrv32_pixel_line_ram.v` (65) | clk/reset；读/写使能、地址（默认 10 位）、读/写数据 32 位。 | FPGA `pixel_line_ram` 注释配置为 1024×32 SDP，同步读延迟 1；SIM 为对应单周期 RAM。 |

### 1.4 geometry

| 文件（行） | 功能；接口分组、位宽、时钟 | 状态/缓冲；IP/原语 |
|---|---|---|
| `edrv32_geometry_engine.v` (315) | 帧配置（surface base/stride 32、尺寸/crop 16、angle 9、flip/fill）；AXI256-R；单像素 RGB565 输出、x/y/标志、busy/done/error。单 clk_mem。 | 配置 + 坐标 walker + 四项 tile cache + bilinear。现有 tile 版 reader path。 |
| `edrv32_geometry_config.v` (481) | 尺寸/crop/angle[8:0]/flip 输入；walker 起始和 Q16.16 原点、像素/行步长（各 32 signed）输出；busy/done/error。 | FSM 求旋转 bbox、X/Y 比例和逆映射原点；同步 512×36 trig ROM + 迭代 48÷16 divider；参数缓存。 |
| `edrv32_geometry_trig_rom.v` (50) | addr 9、data 36、clk/reset。 | Pango `trig_rom`，同步 512×36；字 `{signed Q2.16 cos[17:0], signed Q2.16 sin[17:0]}`，SIM 文件 `trig_q2_16.hex`（512 行，每行 9 个 hex 字符，即 36 位；文件末尾有 0 填充）。 |
| `edrv32_geometry_coord_walker.v` (164) | cfg dimensions 16、origin/pixel-step/row-step 各 signed 32 Q16.16；coord valid-ready；dst x/y 16、src integer signed 16、fraction 16、边界和 SOF/EOL/EOF、busy/done/error。 | 活动计数器逐像素加 pixel step、逐行加 row step；背压时坐标保持。 |
| `edrv32_geometry_tile_cache.v` (406) | 坐标及分数、坐标 valid-ready；四像素/分数/输出坐标；tile fill 请求/每行 256 位返回；busy/error。 | 四项 16×16 tile 缓存；围绕双线性采样获取 2×2 邻域，缺块时请求 fill；例化 tile RAM。 |
| `edrv32_geometry_axi_tile_reader.v` (167) | Surface base/stride、源尺寸、tile x/y 请求；16 行索引和 256 位数据 valid-ready；AXI256-R；done/error。 | 每 tile 行一个 256 位 AXI beat；RID 选行，可乱序返回，底部不完整行以零补。 |
| `edrv32_geometry_tile_ram.v` (79) | clk/reset；写地址 6、数据 256；双读地址 6、两个 256 位输出。 | 两份 Pango SDP RAM `geometry_tile_ram`，每份 64×256，用复制提供双读口；SIM 双读 RAM。 |
| `edrv32_geometry_bilinear.v` (274) | 四个 RGB565 样点、x/y fraction 各 16、边界/fill、dst 坐标及标记；ready/valid 输出 RGB565 和坐标。单 clk。 | 展开 RGB565 到 8-bit channel；三级算术 pipeline + depth 8 输出 FIFO/credit。 |
| `edrv32_geometry_axi_writer.v` (270) | 配置 dst base/stride/尺寸；RGB565 单像素坐标 valid-ready；AXI256-W；done/error。 | 收集 16 像素一拍/beat，最多 16 beat、按行拆 burst，partial tail WSTRB；FSM `IDLE/COLLECT/AW/W/B`。 |
| `edrv32_geometry_surface_pipeline.v` (218) | source/destination surface 描述符、变换参数；AXI256 读写双主口；busy/done/error。 | Block engine 接 AXI writer；DDR→DDR 完整数据通路。 |
| `edrv32_geometry_block_engine.v` (871) | 配置含源 surface、crop/dst、angle/flip/fill；AXI256-R；单 RGB565 像素坐标流。 | 32×16 destination block；bounded source patch、双线性输出入 16 行 target band，按 raster 次序排空；patch reader、patch RAM、band RAM。多状态 block/proc/drain/bbox。 |
| `edrv32_geometry_axi_patch_reader.v` (207) | surface base/stride、patch x/y、宽 beat(1–4)、高(最多 64)；patch RAM 写口；AXI256-R；done/error。 | 每源行 burst，最多 4 个 outstanding ID，按 RID 写 patch RAM。 |
| `edrv32_geometry_patch_ram.v` (66) | 写列 2/行 6/数据 256；两行读地址 6；四列×两行的 256 位输出。 | 以四份 `geometry_tile_ram` 组成 64×64 RGB565 patch，每个列存储 16 像素宽；副本提供双行读。 |
| `edrv32_geometry_band_ram.v` (57) | 写/读使能，地址 11，数据 256，clk/reset。 | Pango `geometry_band_ram` 注释规格 2048×256 SDP；1280×16 RGB565 行带占 1280 word。 |
| `edrv32_geometry_udiv48_16.v` (81) | start、dividend 48、divisor 16；busy/done/div-zero/quotient 48。 | 迭代无符号除法器，每周期生成一位商，只用于配置计算。 |
| `edrv32_geometry_frame_scheduler.v` (187) | source/target frame token、mode；geometry start/src/target base/模式；完成/error；display token 和 source release。 | 当前 active source + 至多一个 pending frame；新到帧替换陈旧 pending。无 RAM/IP。 |

### 1.5 control

| 文件（行） | 功能；接口分组、位宽、时钟 | 状态/缓冲；IP/原语 |
|---|---|---|
| `edrv32_cam_apb.v` (243) | APB 从口；双 camera init/frame 状态、error；SCCB toggle 响应；camera enables、请求 toggle、camera/read、地址 16/数据 8、IRQ。单 `clk_i`，remote ack 为异步输入。 | 旧 camera 私有寄存器状态及请求/应答同步，payload 保持至 ack；不是新公共引擎寄存器模型。 |
| `edrv32_pixel_apb.v` (253) | APB 从口；ack/frame/error 状态；点/空间配置及请求 toggle、IRQ。单 `clk_i`。 | shadow寄存器与提交握手；9 位亮度/对比度、8 位阈值、3 位空间 mode。 |
| `edrv32_disp_apb.v` (162) | APB 从口；active-buffer 2、错误、帧/underflow/scanout 计数、debug 7、三个 base 32；enable/IRQ。 | 显示控制与状态寄存器，缓冲地址旧版 read-only。 |
| `edrv32_vision_telemetry.v` (536) | 单 clk 输入大量视频计数/AXI 握手/阶段状态；UART TX 1 位输出。 | 一秒窗口帧计数、最近帧 phase 周期；ASCII hex CSV 发射 FSM；引用 `edrv32_uart_tx` 公共 UART 模块。 |
| `edrv32_vision_uart_command.v` (149) | UART byte valid/data 8；command valid/type 3/value 16。 | 字符串/数值解析 FSM，无视频数据路径。此控制工具未列入新 VIN/PIX/GEO/DISP 数据面。 |

范围内 vision RTL 共 49 个 Verilog 文件。另有顶层引用的旧公共模块：`legacy/rtl/com/edrv32_async_fifo.v`（跨域 FIFO）、`edrv32_counter_cdc.v`（计数器 CDC）、`reset_sync.v`；旧 AXI 互连在 `legacy/rtl/soc/fabric/`。新规格要求使用 `rtl/common/` 中的 `async_fifo`、`cdc_*`、`reset_sync` 等公共原语，不能搬运这些旧同步器实现。引用的 RAM/ROM/PLL/TMDS FPGA primitives 以具体表格说明为准。

文件数量为 **49 个 Verilog 文件**（camera 9、display 12、pixel 7、geometry 16、control 5；另有 hex 数据文件 2 个）。直接引用的公共模块如下：

| 文件（行） | 功能、主要端口/时钟 | 状态和原语 |
|---|---|---|
| `legacy/rtl/com/edrv32_async_fifo.v` (109) | 参数化 DATA_W/ADDR_W；写时钟侧 data/valid/ready，读时钟侧 data/valid/ready，双异步 reset。 | 二进制读写指针、Gray 指针及跨域同步指针；不复位 payload memory。新规格对应 `rtl/common/async_fifo`。 |
| `legacy/rtl/com/edrv32_counter_cdc.v` (53) | 源时钟/复位和 WIDTH 位单调计数；目标时钟/复位及 WIDTH 位快照输出。 | Gray-code counter snapshot；代码约束源端每次最多 +1，目的端观察最终一致快照。 |
| `legacy/rtl/com/reset_sync.v` (36) | `clk`、异步低有效 `arst_n_i`，低有效同步释放 `rst_n_o`。 | 参数 STAGES 的异步置位/同步释放级联。新规格应使用 `rtl/common/reset_sync`。 |
| `legacy/rtl/soc/fabric/edrv32_axi_m2s_interconnect.v` (168) | 参数化 NUM_M 主口、单 AXI slave 口；打包 AXI AW/W/B、AR/R，另有 urgent/weight/credit 向量；单 clk。 | 写/读调度分离，参数化 AXI fabric；例化 `edrv32_axi_m2s_arbiter`。 |
| `legacy/rtl/soc/fabric/edrv32_axi_m2s_arbiter.v` (174) | request、QoS/weight/urgent 向量，grant/index，fire。 | burst-granular 优先级和加权仲裁状态，不包含 CDC/宽度转换。 |

`axi_rd_fabric.v`、`axi_wr_fabric.v`、`axi_interconnect.v` 在该 legacy fabric 目录存在但不是本图像链顶层 `edrv32_stereo_hdmi.v` 的例化模块；其配置、参数及端口不能据目录存在就视为旧相机/HDMI 实际板级数据路径。它们不是本次表中 `edrv32_axi_m2s_interconnect` 的直接依赖。

## 2. 有出处的板级事实与缺项

| 项 | 查到的事实 | 出处 / 范围说明 |
|---|---|---|
| OV5640 模式 | 名称和配置数据为 1280×720 RGB565。采集 RTL 将连续两个 8 位 DVP 字节组成 `{byte_hi,data_i}`，再依次打包像素；模块本身不测量 PCLK。 | `legacy/rtl/vision/camera/edrv32_ov5640_capture.v`；寄存器序列 `ov5640_720p.hex`。 |
| 相机 PCLK 频率、水平/垂直 blank、实际 RGB565 byte order | 未找到旧板级约束、示波器记录或验证报告可佐证。RTL 注释/命名不足以证明这些物理数值。 | 查找 `legacy/` 的 `.fdc/.pdc/.xdc` 和旧 `legacy/doc/validation/` 未发现相应文件；仿真中的 PCLK 周期不代表传感器板测频率。 |
| 上电/复位序列 | RTL 默认控制时钟 `CLK_HZ=27 MHz`；相机 reset 拉低 65,536 周期，之后 reset 拉高并等待 1,048,576 周期，再开始配置；约 2.43 ms + 38.84 ms（按默认频率换算）。两路按 cam0 后 cam1 配置。 | `edrv32_ov5640_stereo_init.v` 参数、`cam_rst_n_o` 和状态机；属于代码时序，不是独立板测波形记录。 |
| SCCB 地址 | 写字节发 `8'h78`，读字节发 `8'h79`（8 位线格式，对应 7 位地址 `0x3c`）。 | `edrv32_ov5640_sccb.v` `PHASE_DEVICE_WRITE/READ`。 |
| 两相机引脚与外部时钟 | 旧顶层端口有 cam0/cam1 各自 PCLK、8-bit data、HREF、VSYNC、SCL、SDA、RESET；顶层未包含 PWDN 输出。具体 FPGA package pin、IO 电平标准和 PCLK board route 未找到。 | `edrv32_stereo_hdmi.v` 顶层端口；无 legacy 约束文件。 |
| HDMI active raster | 默认 1280×720，H front/sync/back = 110/40/220，V front/sync/back = 5/5/20；总计 1650×750。按 74.25 MHz 像素钟推得 60 Hz。HS/VS 默认正极性。 | `edrv32_hdmi_timing.v` 参数/计数逻辑；74.25 MHz 由新 SoC 规格 `edrv32-soc-spec.md` §5.1 规定，旧板级 PLL 频率未在旧约束或顶层中找到。 |
| TMDS 实现 | 每色通道 8→10-bit encoder；三数据通道加一个 TMDS clock lane。FPGA serializer 用 Pango `GTP_OSERDES_E2` master/slave cascade、`DDR10TO1` 和 `GTP_OUTBUFDS(IOSTANDARD="TMDS")`。按 10:1 DDR serializer，串行时钟需为像素钟 5 倍；如取新 SoC 74.25 MHz，则为 371.25 MHz（推导值，并非旧 PLL 实测/配置）。 | `edrv32_tmds_tx.v`、`edrv32_tmds_encoder.v`、`edrv32_tmds_serdes.v`。实际 PLL 频率、抖动、IO 引脚约束和板上锁定记录未找到；`legacy/sim/cases/vision/render-board-top/board_ip_stubs.v` 只有 IP stub。 |
| IP | `cam_fifo` 注释配置 1024×258；`cam_rom` 512×24；HDMI FIFO 512×256/阈值 64；Pixel line RAM 1024×32；GEO band RAM 2048×256；tile RAM 64×256 两份。 | 各 backend 源码注释，未发现相应 PDS IP 创建报告或完整工程约束。 |
| 60 fps camera 表 | 未找到第二张 60 fps hex 表或寄存器表注释。旧设计记录和 SoC 规格写的是模式选择能力，但本次指定范围中唯一寄存器表为 `ov5640_720p.hex`。 | `legacy/rtl/vision/camera/` 文件列表与 `legacy/doc/architecture/2026-09-14-vision-system-design.md`；当前新设计决定使用软件/I2C0 配置。 |

仓库当前不存在用户任务提及的 `legacy/doc/validation/` 目录；旧设计文档里提到的 `docs/validation/2026-09-19-pixel-pipeline.md`、`docs/validation/2026-09-21-geometry-surface-pipeline.md` 等也未在本工作树找到。因此相关上板记录、旧综合/布局布线资源数字和时序报告均为“未找到依据”。`legacy/sim/cases/vision/` 有多个定向仿真 case，但属于 RTL 仿真证据。

## 3. `ov5640_720p.hex` 格式与表项

该文件每行是 6 个十六进制字符，即一个 24 位字 `{register_address[15:0], register_data[7:0]}`；ROM 数据输出为 24 位，初始化 FSM 用 `[23:8]` 作寄存器地址、`[7:0]` 作数据。全文件有 512 行，其中索引 0–247 共 248 个非零寄存器条目，索引 248–511 为 264 个 `000000` 填充项。启动参数 `REG_COUNT=248`，因此填充项不被遍历。RTL 没有延时 opcode 或延时字段；上电等待通过独立 reset/settle 计数器完成，`000000` 在这里是 ROM 填充，不是表内延时。未找到 60 fps 表或 60 fps 标记。出处：`ov5640_720p.hex`、`edrv32_ov5640_reg_rom.v`、`edrv32_ov5640_stereo_init.v`。

## 4. 对接新规格的差异

| 项 | 旧工程 | 新规格/迁移工作 |
|---|---|---|
| 像素接口 | 多个端口使用 258 位 `{sof,eof,16×RGB565}`；PIX 内解包为两像素/拍。 | SoC v0.7 §4.5 明确两像素 `data[31:0]`，含 valid/ready/sof/eol/eof；重新做通路边界和包/拆分，移除 16 像素旧接口及其行/帧边界编码。 |
| 时钟域/CDC | camera capture 在 cam PCLK 后进旧异步 FIFO；HDMI DDR 读与 pixel scanout 过旧 FIFO；toggle handshakes 和局部两级同步并存。 | §5.1–5.2 固定 camN_pclk→clk_mem async_fifo、clk_mem→clk_pix async_fifo 等清单；所有跨域改用 `rtl/common/` 原语。新 PIX/GEO/DISP 在 clk_mem，扫描/TMDS 在 clk_pix。 |
| DDR | camera/display/GEO 自带 AXI writer/readers，含旧 AXI256 端口字段、burst 聚合、outstanding 和内部格式假设。 | §4.2 与 §8.11 要求符合 AXI256 32B 对齐、1–16 beat、不跨 4 KiB，由公共 `dma2d_rd/wr` 访问；VIN/PIX/GEO/DISP 重新接 DMA 和 mem_xbar 端口。 |
| 控制寄存器 | 私有 APB map，旧 cam/disp/pixel APB 模块；点/空间配置各自握手，旧地址映射/状态格式。 | §7.1 公共 ID/CTRL/STATUS/IRQ/PERF 布局；APB4 用新 SoC §4.3，模块私有寄存器从 0x100 起。旧 APB 只可作功能参考，不原样移植。OV5640 设置改为软件通过 I2C0（`sys-subsys-spec.md` §2.8）。 |
| PIX 行缓存与级联 | 一个共享三 RAM 3×3 窗口，不能同帧串接两种空间核。 | 决策记录要求两个在线固定级联 3×3 stage。可复用算法函数、点运算思路、双像素行地址/窗口推进逻辑；窗口/行 RAM 增为两级独立状态和存储。 |
| GEO | 旧工程存在旧 tile 版 `geometry_engine` 与较新的 block/strip `geometry_surface_pipeline` 两套实现；AXI 直接口、单时钟命令和内部完成状态。 | 新设计为 CPU 每帧启动的 DDR→DDR 命令式引擎；按 §7.1、§7.2 公共寄存器和 §8.11 DMA 重写控制/总线边界。可复用逆仿射、坐标递推和插值算法参考，不能把旧 AXI reader/writer 接口当新契约。 |
| DISP | 旧 reader/pageflip 支持多个 buffer，旧扫描 FIFO 内部 256 位 packed stream；旧顶层读写 DDR/管理 token。 | 本阶段 DISP 单层扫描，Surface 在 VBlank 提交；按 §4.5 与 `dma2d_rd` 对接，fifo CDC 仅用公共原语；板级保留 TMDS/Pango IO 适配职责。 |
| 命名、语法、初始化 | 文件多为 `edrv32_vision_*`；多个模块是旧阶段名。ROM/FIFO 仿真 backend 有 `initial` 与 `ifdef`；`tmds_serdes` 含 `ifdef`，旧代码存在自行 CDC/复位同步。 | 新命名按 CLAUDE §6 的 `edrv32_<subsystem>_<function>` 和 §5 语法/CDC 约束；`ifdef` 只放 `rtl/tech/`，存储初始化须按新 IP wrapper 约定。初始 ROM 文件需在 tech/IP 边界处理，不把 `initial` 带到业务 RTL。 |

## 5. PIX 算法、窗口与可复用部分

| 运算 | 旧定点和像素行为 | 舍入、饱和、边界 |
|---|---|---|
| RGB565 展开/重新量化 | R/B 5 位扩展 `{v[4:0],v[4:2]}`；G 6 位扩展 `{v[5:0],v[5:4]}`。输出截取 R/B `[7:3]`、G `[7:2]`。 | 位复制展开，输出截断，无中间舍入。 |
| 亮度/对比度 | `contrast` 是无符号 9 位 Q8，复位值 256（1.0）；亮度是 signed 9 位。每 channel 将 8-bit 中心化为 `c-128`，计算 `((c-128)*contrast >>> 8)+128+brightness`。 | 算术右移丢低 8 位（向负无穷取整语义）；之后饱和到 0–255。 |
| 灰度 | `Y=(77R+150G+29B+128)>>8`，R/G/B 为扩展后 8 位。系数和为 256。 | `+128` 最近整数舍入；输出复制灰度到 RGB565。 |
| 阈值/反色 | `gray >= threshold` 得白，否则黑；反色对该布尔结果 XOR。复位阈值 128。 | 不含中间饱和；结果为 `ffff` 或 `0000`。 |
| Sobel | `Gx=-p00+p02-2p10+2p12-p20+p22`；`Gy=-p00-2p01-p02+p20+2p21+p22`；输出 `min(|Gx|+|Gy|,255)`。 | 绝对值相加后超过 255 饱和至 255；不做除法/舍入。 |
| Mean | 九点和除 9：`(sum+4)/9`。 | 先加 4 后整数除法，近似最近整数；输出灰度 RGB565。 |
| Gaussian | 3×3 核 `[[1,2,1],[2,4,2],[1,2,1]]`，`(weighted_sum+8)>>4`。 | 除 16 最近整数舍入；结果天然在 0–255。 |
| Sharpen | `5*p11-p01-p10-p12-p21`。 | signed clamp 到 0–255；输出灰度 RGB565。 |
| Erosion/Dilation | 九点比较 `pixel >= threshold`；erosion 是 AND，dilation 是 OR。 | 输出纯黑/白 RGB565。 |
| 空间旁路和边界 | mode 0/其它 default 返回中心 RGB565；零补齐邻域。窗口产生合成零行 flush 最后一行，保持像素计数。 | `edrv32_pixel_filter_3x3.v` 与 `edrv32_pixel_window_3x3_2p.v`。 |

旧 3×3 窗口以三个旋转同步 RAM 存相邻两像素/地址，当前行写入一 bank，前两行读出形成三行；行内移位对齐左右列，垂直方向延迟约一行。`pixel_line_ram` 每份 1024×32，一拍同步读，实例化 3 次。RGB565→灰度发生在 3×3 组合核之前，因此旧空间算子均在灰度图工作，输出灰度色；erosion/dilation 也输出二值图。点处理先于共享空间核，后续不能把旧模块组合顺序当新两级级联的约束。

新 PIX 可复用：RGB565 展开/量化，点亮度对比度和灰度核，Sobel/mean/Gaussian/sharpen/morphology 系数与比较逻辑，valid/ready 弹性级和标记延迟概念，pair-indexed line RAM 的地址递进。需要为两级 3×3 各自复制行缓存/窗口/边界状态；新流中每拍已是 2 像素且有 EOL/EOF，不能保留 S258 unpack/pack 外壳。

出处：`legacy/doc/architecture/2026-09-22-pixel-pipeline-design.md`；`legacy/rtl/vision/pixel/edrv32_pixel_point_pipe.v`、`edrv32_pixel_filter_3x3.v`、`edrv32_pixel_window_3x3_2p.v`、`edrv32_pixel_line_ram.v`。

## 6. GEO 参数、遍历、缓存与吞吐

- **矩阵和角度**：配置角度为 9 位，RTL 接受 0–359 度；`trig_q2_16.hex` 是同步 512×36 ROM，每项 18 位 signed Q2.16 cos + 18 位 signed Q2.16 sin。`geometry_config` 计算裁剪框、非等比 X/Y scale、旋转逆映射和 origin，输出 signed Q16.16 原点、每像素步长和每行步长，各 32 位。相同完整 geometry config 会缓存 cos/sin/步长参数，下一帧仍启动 walker。出处：`edrv32_geometry_config.v`、`edrv32_geometry_trig_rom.v`。
- **坐标遍历**：左上目的坐标起始，接受坐标时 x 递增并累加 `pixel_step`；EOL 时 y 递增并从行起点累加 `row_step`。坐标整数部分为 signed 高 16 位，fraction 为低 16 位。SOF/EOL/EOF 与目的坐标同拍；valid/ready 背压时当前坐标保持。出处：`edrv32_geometry_coord_walker.v`。
- **tile engine**：旧 `geometry_engine` 版采用 16×16 tile、四项 cache，每个 tile 16 行、每行一个 256-bit DDR beat。每个 tile 返回可乱序（RID 是行索引），不完整底边行在 reader 本地补零。双线性 cache 需要相邻 2×2 样点，tile cache 解析块命中并发起缺块填充。出处：`edrv32_geometry_engine.v`、`edrv32_geometry_tile_cache.v`、`edrv32_geometry_axi_tile_reader.v`、`geometry-tile-reader/README.md`。
- **block/strip 版本**：`geometry_surface_pipeline` 连接 Block Engine + AXI writer。Block Engine 按 32×16 destination block 取 bounded source patch；reader 每源行 1–4 beat burst、最多 4 个 outstanding ID；patch RAM 64×64 RGB565、四个 16-pixel 列分 bank，复制读口同时读两行；目标 band RAM 2048×256，RTL 注释称 1280×16 目标 band 使用 1280 word。完成 block 后按 raster 顺序 drain band，writer 收集 16 像素/beat，burst 最大 16 beat 且不跨行。出处：`edrv32_geometry_block_engine.v`、`edrv32_geometry_axi_patch_reader.v`、`edrv32_geometry_patch_ram.v`、`edrv32_geometry_band_ram.v`、`edrv32_geometry_axi_writer.v`。
- **双线性精度**：输入 RGB565 展开到 8 位/channel；fraction x/y 是 Q0.16（坐标 Q16.16 的低 16 位）。先水平 lerp：`a*65536 + (b-a)*fx`，保留 Q16 中间值；后垂直 lerp并加 `2^31` 后取 `[39:32]`，即最终到 8-bit channel 前加半 LSB 舍入。再量化回 RGB565。无界样点取 fill pixel。输出 pipeline 3 级并用 depth 8 FIFO credit 防止背压覆盖。出处：`edrv32_geometry_bilinear.v`。
- **吞吐和资源**：旧 2026-09-14 架构文档记载新旧 Geometry 路径算术发射上限 62.5 Mpixel/s @125 MHz，720p30 需求 27.65 Mpixel/s；明示未计 patch 读取和 band drain，因此不是端到端吞吐或板测结果，且 720p60 不能据此确认。`geometry-rot15-stress/README.md` 给出可运行尺寸/角度参数，但本次未运行。legacy 中未找到该组模块的 LUT/FF/DRM/APM 或时序报告。出处：`legacy/doc/architecture/2026-09-14-vision-system-design.md` §5；`legacy/sim/cases/vision/geometry-rot15-stress/README.md`。

旧 GEO 至少包含两条实现支路：单 `geometry_engine` 的 tile/cache 路径，以及 `geometry_surface_pipeline` 的 block/strip 路径。新的命令式 DDR→DDR 用公共 DMA，因此坐标数学、trig ROM 的表格式、双线性插值及 patch/tile/band 局部缓存的数据组织是算法/结构参考；旧 AXI master、APB/调度器和所有权接口需重新定义。

## 7. 旧资源和时序报告

在 `legacy/` 中未找到图像通路相关 PDS 综合、布局布线、器件资源映射或时序报告。旧设计文档中对像素吞吐（2 像素/拍 @125 MHz、理论 250 Mpixel/s）及 Geometry 算术上限（62.5 Mpixel/s）的描述属于架构计算，不是综合/布局布线实测。故 PIX/GEO/VIN/DISP 的 LUT、FF、DRM、APM、WNS/TNS/WHS/THS 均为“未找到依据”。

## 8. 移植清单

| 模块 | 建议 | 理由 |
|---|---|---|
| OV5640 DVP capture 前端和 `ov5640_720p.hex` 配置内容 | 改接口 | 方案决定保留已验证传感器配置序列和相机采集行为；像素包需改到新 2-pixel stream，初始化移交软件 I2C0。PCLK/blanking 字节序板测证据不在仓库。 |
| 相机控制私有 APB 与 ROM/SCCB 初始化 RTL | 改写/弃用旧 init RTL | 新设计由软件经 I2C0 配置传感器，复用 248 项表内容；旧 APB/toggle control 不符合新公共寄存器/I2C模型。 |
| Camera FIFO / camera AXI writer | 改接口 | 新 CDC 需 `rtl/common/async_fifo`；DDR 通路需公共 `dma2d_wr`、三缓冲环和最后 B 响应后的 CPU 交接。 |
| PIX 点运算 | 改写 | 旧算术公式可作实现参考；按新规格端口、寄存器和每帧级联路径重新组织，Gamma 是新决策新增功能，旧代码没有 Gamma LUT。 |
| PIX 3×3 filter kernel | 改写 | 六种算子的系数/比较行为可复用为算法参考；旧核组合接口、固定灰度计算和单共享窗口不满足两级固定级联。 |
| PIX window/line RAM、unpack/pack、pipeline | 改写 | 旧包是 258 位单帧标记、内部 P2；新统一 P2 接口带 SOF/EOL/EOF；双级需两个独立 3 行缓存。RAM IP 应重建为新 tech wrapper。 |
| GEO inverse transform/walker/bilinear | 改接口 | Q2.16 trig、Q16.16 坐标递推和 RGB565 双线性可作算法依据；帧级控制改 CPU 每帧启动的 descriptor/doorbell。 |
| GEO tile/block readers、patch/band RAM、writer | 改写 | 旧实现直接发 AXI256；新必须通过 `dma2d_rd/wr`，遵守公共 AXI 事务拆分约束，定稿新的 tile/patch 和 in-flight 参数。 |
| Geometry frame scheduler | 不移植 | 新方案由 CPU 通过公共寄存器和 buffer ownership 交接帧，无旧硬件自动 scheduler 接口。 |
| HDMI timing / TMDS encoder | 原样移植核心，改命名/边界 | 时序参数可对上新 720p60 `clk_pix` 规格，TMDS encoder 算法与新 top 的 3×10 符号边界一致。 |
| TMDS SERDES / 差分输出 | 板级原样移植 | 这是 Pango OSERDES/差分 IO 设备边界；新 SoC 内部输出符号，不在 SoC RTL 中例化 FPGA IO 原语。需由新板级 PLL/约束工程确认频率和 pin。 |
| HDMI AXI reader/FIFO/scanout/pageflip | 改接口 | 新 DISP 单层扫描与 VBlank 切换可复用扫描计数和像素展开；AXI 改公共 `dma2d_rd`，跨域改公共 async FIFO，frame token 与新 Surface 模型对齐。 |
| colorbar writer/bring-up top/frame composer | 不移植到产品通路 | 属于测试/旧整帧拷贝 bring-up；新产品通路使用正式 Surface 和公共 DMA。可保留作独立验证参考，不作为 SoC 数据路径。 |
| `cam_apb` / `pixel_apb` / `disp_apb` | 改写 | 旧私有 APB 寄存器 map 替换为 §7.1 公共引擎模型和各模块私有偏移。 |
| telemetry / UART command | 不移植到图像模块 | 只供旧 demo 统计/命令控制；不属于 VIN/PIX/GEO/DISP 规格接口。 |

### 主要依据

- 新架构决策：`docs/design/2026-10-27-image-path.md`。
- SoC 新契约：`docs/spec/edrv32-soc-spec.md` §4.2–4.5、§5、§5.2、§7.1–7.3、§8.5–8.8、§8.11、§9.1；`docs/spec/sys-subsys-spec.md` §2.8。
- 旧设计：`legacy/doc/architecture/2026-09-14-vision-system-design.md`、`legacy/doc/architecture/2026-09-22-pixel-pipeline-design.md`。
- 原始证据：本文各表及 `legacy/sim/cases/vision/` 对应仿真源码/README。仿真说明未当作板级测量证据使用。
