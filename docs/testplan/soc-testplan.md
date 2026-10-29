# SoC 级验证方案（B2：完整 SoC，RND 除外）

| 项 | 内容 |
|---|---|
| 版本 | v0.1（用户确认 2026-10-29） |
| 日期 | 2026-10-29 |
| 对应规格 | SoC 规格 v0.16（1.2、5、6、7.3–7.5、8、9.1–9.2）；`sys-subsys-spec.md` v0.4；`mem-subsys-spec.md` v0.4；`vin-spec.md` v0.2；`pix-spec.md` v0.1；`geo-spec.md` v0.1；`disp-spec.md` v0.2（B2 用的 RTL）；`npu-spec.md` v0.4；`eth-spec.md` v0.1 |
| 关联 | 设计记录 `2026-10-29-b2-software.md`（3.3 DDR 布局、3.4 数据流、3.4a 输出选择、3.5 监控记录、3.5a 线协议）；`board-plan.md` B2-1d |

## 1. 验证对象和范围

`edrv32_soc_top`（B2：CPU、系统子系统、存储子系统、VIN + PIX、GEO、DISP、NPU、ETH；RND 未接入）加全部外部器件模型。

- 本层验证：
  - 子系统之间的数据流和中断；
  - 共享 DDR 下的实时性（DISP 不读空、VIN 不溢出，SoC 9.2）；
  - 启动流程（SoC 7.5）；
  - 媒体软复位；
  - 网口收发和监控记录的端到端格式。
- 不在本层：各模块内部功能（已在单元级和模块级验证）、带宽和帧率的板级实测（B2-6 上板）、YOLO 整网精度（`tools/npu/` 和 B2-5b 调试工具比对）。
- 已有的连接冒烟 `verif/soc/soc_connect`（B2-1a）作为 SC-02 纳入本方案，不重复实现。

## 2. 验证环境

- 层级：SoC 级，`verif/soc/<测试>/`，Verilator `--timing`，自检。
- 顶层：`edrv32_soc_top`，文件列表 `rtl/filelists/soc.f`（按 `tools/regress.py` 的 `expand_files` 去重展开）。
- 时钟：
  - clk_sys 100 MHz、clk_mem 125 MHz、clk_npu 150 MHz、clk_pix 74.25 MHz、eth 125 MHz；
  - 摄像头 pclk 按 `dvp_camera_model` 的配置；
  - 各时钟初相位可由种子设定。
- 外部器件模型（`verif/models/`）：
  - `ddr3_axi256_model.sv`：DDR，`mem_ready_i` 由 testbench 在复位后拉高；
  - `dvp_camera_model.sv` × 2：摄像头；
  - `sccb_model.sv`：摄像头配置；
  - `tmds_rx_model.sv`：HDMI 接收，恢复像素和时序；
  - `eth_peer_model.sv`：网口对端，收发 UDP、应答 ARP；
  - `uart_model.sv`：串口。
- 软件：`sw/tests/soc/<测试>/`，由 `sw/Makefile` 构建。
  - 默认后门预加载 ROM/SRAM/DDR 镜像（CLAUDE.md 9.2）；
  - 结束时写 SYSCTRL `SIM_EXIT`，0 表示通过；
  - UART 输出存入测试日志。
- 参考模型：
  - `verif/block/pix/pix_ref.py`、`verif/block/geo/geo_ref.py`；
  - VIN CH2 参考（`verif/block/vin/` 中的参考实现）；
  - `tools/npu/ref/npu_ref.py`；
  - DISP 像素展开按 disp-spec 2.3。
- 比对：testbench 或软件把结果和参考逐字节比对，失败时打印位置、期望值和实际值。

## 3. 测试项清单

| 编号 | 规格条款 | 测试内容 | 激励 | 检查 | 档位 |
|---|---|---|---|---|---|
| SC-01 | SoC 7.5 第 1–3a 条 | 启动：<br>(a) 不按 KEY1，bootloader 打印启动信息后跳到 SRAM 程序；<br>(b) 按住 KEY1，进入 BIOS，经 UART 模型下载一个小 SRAM 程序，复位后运行它 | 软件程序 + UART 模型（前门加载） | UART 日志中的固定提示文字（7.5 第 2、3a 条）；下载的程序写 SIM_EXIT = 0 | full |
| SC-02 | SoC 6.1、6.4.1 | 连接冒烟（已有 `verif/soc/soc_connect`）：媒体 APB 槽 ID、预留槽 SLVERR、DDR 网关读写、MEM_XBAR 读写统计、媒体中断到 MEIP | 软件程序 | 已有判定 | smoke |
| SC-03 | SoC 1.2 S2、7.3、8.5、8.6、8.8 | S2 摄像头通路：<br>• 摄像头模型输出 1280×720 测试图；<br>• VIN CH0 + PIX（旁路一帧，一种 3×3 算子一帧）写入底图环；<br>• DISP 扫描显示 | 软件程序（配置 SCCB、VIN、PIX、DISP，按 FRAME/SWITCH 交接） | 接收模型恢复的像素与 `pix_ref.py` 的期望帧逐像素一致；SLOT_BUSY 与 SWITCH/REL_BASE 交接正确；DISP、VIN 错误计数为 0 | full |
| SC-04 | SoC 8.7、7.3 | S2 + GEO：底图经 GEO 旋转（45°，s = 1）写入输出 Surface，DISP 扫描 GEO 输出 | 软件程序 | 接收像素与 `geo_ref.py` 一致；GEO DONE 中断 | full |
| SC-05 | SoC 1.2 S1、7.5 S1 第 1–3 条、8.5、8.9 | S1 数据通路（内存源，不依赖摄像头）：<br>• DDR 中预置一幅 1280×720 图；<br>• VIN 内存源读出，经 CH0 和 CH2；<br>• NPU 执行一份小规模描述符表（`tools/npu/gen_case.py` 生成，以 CH2 输出为输入，**[待定]** 规模见第 7 节） | 软件程序 | CH2 输出与 VIN CH2 参考逐字节一致；NPU 输出与 `npu_ref.py` 逐字节一致；CH0 与 CH2 的 frame_id 相同；VIN、NPU 中断经 PLIC 到达 | full |
| SC-06 | SoC 8.10、7.5 ETH 数据下载 | ETH 接收：<br>• 对端模型发 ARP 请求；<br>• 向窗口 2 发 64 KiB 数据（多包，末包 NOTIFY），中间插入一个目的端口不匹配的包和一个校验和错误的包 | 对端模型 + 软件程序 | ARP 应答正确；窗口数据逐字节一致；WIN2 字节计数、NOTIFY 中断；错误包丢弃并计数 | full |
| SC-07 | SoC 8.10；设计记录 b2-software 3.4a、3.5、3.5a | ETH 发送：<br>• 软件按 3.4a 发一帧视频，EDVF 帧头 + Surface 原地发送，Surface 用 1280×720；<br>• 按 3.5 发一组监控记录（type 1，16 条） | 软件程序 + 对端模型 | 对端重组的帧头字段、像素与 DDR 中的 Surface 逐字节一致；监控记录的 magic、version、seq 连续，port 统计与软件同一快照读到的 MEM_XBAR 寄存器一致 | full |
| SC-08 | SoC 9.1、9.2 | 并发实时性（S1 负载）：<br>• 摄像头 CH0 + CH2 连续采集；<br>• NPU 循环执行带宽较大的描述符表；<br>• ETH 以 720p30 发送视频（"同时"档）；<br>• DISP 扫描；<br>• 运行至少 3 个显示帧 **[待定]** | 软件程序 | DISP PERF1（读空帧）= 0；VIN CH0/CH2 溢出丢帧 = 0；记录 MEM_XBAR 各端口统计和 `urgent` 计数（写入测试日志，供 SoC 9.1 规划值对照） | full |
| SC-09 | mem-subsys-spec 2.3（PERF_MON） | PERF_MON 延迟探针：在 SC-08 的负载下开启顺序读探针 | 软件程序 | 直方图各格之和 = READ_CNT；LAT_MIN ≤ 平均 ≤ LAT_MAX；P6 限速生效（P6 读拍数不超过 RATE[P6] 规定的份额） | full |
| SC-10 | sys-subsys-spec 2.10；SoC 5.3 | 媒体软复位：S2 + GEO + ETH 接收进行中，软件写 SYSCTRL `SOFT_RESET.MEDIA` | 软件程序 | 复位后各引擎 STATUS.IDLE；mem_xbar 没有挂起的事务（随后 CPU 经网关读写 DDR 正常）；重新配置后 SC-03 的一帧再次逐像素正确 | full |
| SC-11 | SoC 6.1 PLIC 源 8–15 | 中断全覆盖：<br>• 源 8–10、12–14 各触发一次可由软件或模型产生的事件（VIN FRAME、PIX FRAME、GEO DONE、DISP FRAME、NPU DONE、ETH 接收 NOTIFY）；<br>• 源 11（RND）始终不挂起；<br>• 源 15（MEM_XBAR 错误）不在本层触发：B2 中没有软件合法产生违规事务的路径（各引擎 DMA 和 PERF_MON 都保证对齐、不跨 4 KiB），其中断由存储子系统模块级测试验证，顶层连接由协调者评审核对 | 软件程序 | 每个源经 PLIC claim/complete 一次，源号正确 | full |

## 4. 参考模型

- 像素和数据：测试程序把输入图像（DDR 预置或摄像头模型的测试图）和配置写进日志或共享文件。testbench 调用对应 Python 参考模型生成期望结果，再与接收模型恢复的像素、DDR 中的输出逐字节比对。
- NPU：`tools/npu/gen_case.py` 生成小规模用例的描述符、权重和期望输出；期望输出由 `npu_ref.py` 产生，与模块级 NPU 测试使用同一工具链。
- 网口：`eth_peer_model` 记录收到的每个 UDP 包，testbench 按 b2-software 3.5a 的协议重组，与 DDR 中的源数据比对。

## 5. 覆盖目标

SoC 7.5 的每一个流程至少有一个测试项：启动、BIOS、S1、S2、ETH 下载。B2 中接入的每个 mem_xbar 端口（P0、P1、P2、P3、P5、P6）都在至少一个测试中有读、写流量（P0 只有读）。媒体中断源 8–10、12–14 都被触发一次（源 15 见 SC-11）。

## 6. 通过判据和回归档位

- 全部测试自检 PASS，并以进程退出码返回。
- smoke：SC-02。
- full：全部。
- 每个测试的超时写进 `test.yaml`；SoC 级测试单项可能超过 60 秒，不放进 smoke（CLAUDE.md 9.1）。
- SC-08、SC-09 记录的端口统计写进测试日志，作为 SoC 9.1 规划值的仿真对照，不作为通过判据。

## 7. 待定事项与变更记录

| # | 事项 | 开发初值 | 定稿依据 |
|---|---|---|---|
| 1 | SC-05 NPU 用例规模 | 3 条描述符：3×3 卷积步长 2；1×1 卷积；1×1 卷积 + RES_EN（残差取第一层输出，npu-spec 2.1 没有独立加法描述符）。各层输出 16 通道，输入为 CH2 的完整 640×384 | 仿真时间：单项不超过约 30 分钟 |
| 2 | SC-08 运行的显示帧数和 NPU 负载 | 3 帧；NPU 循环执行 SC-05 的用例 | 仿真时间；能否覆盖摄像头帧与 NPU 推理重叠 |

| 日期 | 版本 | 变更 |
|---|---|---|
| 2026-10-29 | v0.1 | 初稿 |
| 2026-10-29 | v0.1 | 第 7 节 #1 更正：逐元素加改为 1×1 卷积 + RES_EN（B2-1d 问答，npu-spec 2.1） |
| 2026-10-29 | v0.1 | SC-11：源 15（MEM_XBAR 错误）不在 SoC 级触发（无合法触发路径，B2-1d 问答），由模块级测试和连接评审覆盖 |
