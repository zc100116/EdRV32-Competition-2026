# PG2L200H 720p 视觉系统总体框架

初稿：2026-09-14；重整：2026-09-22  
定位：规定系统边界、数据流、DDR 调度和集成验收。像素处理的内部设计见 [像素处理设计计划](2026-09-22-pixel-pipeline-design.md)。

## 1. 目标与边界

- 两路 OV5640 输入，1280×720 HDMI 输出；单个 bitstream 内切换预览、图像处理、检测和界面模式。
- EdRV32 负责配置、Surface/任务管理和少量结果处理；视频帧、图层及模型数据由硬件 DMA 访问 DDR。
- Pixel Pipeline、Geometry、YOLO、2D Renderer 和 HDMI 作为独立功能模块，以流接口、DDR Surface、命令及 Fence 连接。开发期可分别使用测试顶层验证，最终仍需在同一系统中集成。
- YOLO 的内部实现方案不在本文中规定；Renderer 的硬件设计与当前 RTL 进度见 [2D 图形加速器设计计划](2026-09-24-render-architecture.md)。

## 2. 数据流

```text
Camera L/R → RX / CDC FIFO → 帧级分发 ─┬→ Pixel Pipeline → Pixel Surface ─┐
                                       │                                  ▼
                                       │                        Geometry（按模式启用）
                                       │                                  │
                                       │                             Geometry Surface
                                       ├→ YOLO 输入适配 → YOLO → Detection META
                                       └→ 可选 Capture DMA → Raw Surface

Raw / Pixel / Geometry Surface + Detection META + 绘图命令
                         → 2D Renderer（按模式启用）
                         → Final Display Surface Pool → HDMI DMA → HDMI
```

摄像头源在各消费支路分别选择。Pixel 与 YOLO 可以同时消费同一摄像头帧；不要求视频帧先经过 Pixel 才能进入 YOLO。YOLO 输入适配器独立完成源格式转换、缩放/Letterbox、颜色顺序和模型要求的量化与排布。显示效果不隐式改变模型输入。

Pixel 输出先形成 DDR Surface；Geometry 从完整的输入 Surface 取数并写新的 Surface。没有几何任务时，Pixel Surface 直接交给下游，不做恒等变换的整帧复制。原始摄像头数据只有在 Capture DMA 开启后才可作为 Raw Surface 被 Geometry 或 Renderer 读取。

Renderer 接收绘图命令与图像 Surface，合成最终显示帧。Detection META 包含 `frame_id`、类别、置信度和检测框；它由软件或约定的命令转换层变为框、文字等绘图命令，不能当作像素图层直接混合。没有绘图任务且源格式符合 HDMI 读取要求时，可以直接将已有完整 Surface 交给显示池；该 Surface 在 HDMI 扫描完成前保持只读所有权。

## 3. 模块交接契约

| 模块 | 输入 | 输出 | 交接条件 |
|---|---|---|---|
| Camera 分发 | 两路采集流 | 分支视频流 | 选源在 SOF 生效；分支分别缓冲与计数 |
| Pixel | 选中的视频流、帧边界配置 | Pixel Surface | 全帧写入及写响应完成后发布 READY |
| Geometry | READY Raw/Pixel Surface、变换参数 | Geometry Surface | 读写 Fence 完成后释放输入、发布输出 |
| YOLO | 独立摄像头分支或指定 Surface | Detection META | 输入和结果保留源 `frame_id`；推理慢时丢过期待处理帧 |
| Renderer | READY 图像 Surface、图层和绘图命令 | Final Display Surface | 全部写回完成后发布 READY |
| HDMI | READY 显示 Surface | 720p60 像素流 | 只在 VBlank 切换；扫描完后归还旧 Surface |

每个 Surface 至少记录地址、分配长度、宽高、stride、像素格式、`frame_id`、生产者/消费者 Fence 和所有权。基本所有权顺序为 `FREE → FILLING → READY → IN_USE → FREE`；读者不得访问 `FILLING`，写者不得覆盖 `IN_USE`。显示池采用三缓冲：写入、候选、扫描中的 Surface 分离。跨模块队列只保留有限帧数，非实时处理落后时优先保留最新完整帧，避免积压导致画面越来越旧。HDMI 无新帧时重复当前完整帧。

Camera 和 HDMI 是硬实时边界。YOLO 或 Renderer 的背压不得沿流式支路长期反向传到 Camera；各分支通过本地 FIFO、独立帧池与丢帧策略解耦。配置、源选择和显示所有权都在帧边界提交。结果叠加必须明确使用同一 `frame_id`，或明确标记沿用上一份检测结果。

## 4. 总线与 DDR

控制面为 `EdRV32 → 64-bit System AXI → APB/CSR`；数据面为各引擎 AXI DMA Master 经独立 DDR AXI Interconnect、Pango UI Adapter 访问 DDR。CPU 经 DDR Gateway 访问同一物理 DDR 的 cached/uncached 视图，不搬运整帧像素。中断由各模块锁存后进入 PLIC。

DDR 数据面以重新生成的 IP 原生宽度为准，当前架构按 256 bit 设计。一个 DDR AXI 事务为 1～16 个 32-byte beat、INCR、32-byte 对齐且不跨 4 KiB；较长二维行由 DMA 在入口前拆为多个事务。DDR Fabric 负责仲裁、Outstanding、ID/返回路由和错误隔离；像素格式、stride、Tile 地址和任务完成 Fence 由各引擎负责。

### 4.1 带宽估算

当前生成的 DDR IP 配置为 x32、1000 MT/s，理论数据率为 **4.0 GB/s**，256-bit UI 对应 125 MHz。该值只是峰值上界；有效混合读写带宽会受到 DDR 刷新、行命中率、读写换向、小 Burst、DDR UI 空拍及仲裁影响。旧计划的 4.26 GB/s 与当前 IP 配置不一致。以下均以十进制 MB/GB 计，只统计数据载荷。

规划一个较重的并发场景：一条 720p30 RGB565 Pixel/Geometry 视频链；Renderer 每秒合成 30 张 ARGB8888 显示帧，每张读取一层 RGB565 基底和两层全屏 ARGB8888；HDMI 扫描 720p60 ARGB8888；两路原始 RGB565 Camera 均可选写入 DDR；YOLO 适配器每秒最多写入 30 张 640×384、补齐到 C16 的 INT8 输入帧。这个场景用于容量检查，并不表示所有模式都必须同时开启这些功能。

| DDR 请求者 | 规划流量 |
|---|---:|
| Pixel 写 RGB565，30 FPS | 55 MB/s |
| Geometry 读和写 RGB565，各 30 FPS | 111 MB/s |
| Renderer 读 RGB565 基底、读两层 ARGB8888、写 ARGB8888，30 FPS | 387 MB/s |
| HDMI 读 ARGB8888，60 Hz | 221 MB/s |
| 可选两路原始 RGB565 Capture，各 30 FPS | 111 MB/s |
| YOLO 输入环形池写入 640×384×16 INT8，30 FPS | 118 MB/s |
| **不含 YOLO 权重/特征图时合计** | **约 1.00 GB/s** |

若 Renderer 每秒重新合成 60 张同规格的显示帧，总量升至约 **1.37 GB/s**。去掉 Capture、图层或 Geometry，相应流量应直接从预算中扣除；不能将所有模式的峰值误认为常态。相反，若某阶段改为 32-bit Surface、图层多次重读或额外整帧复制，也必须把新增读写计入预算。

YOLO 的主要未知量是每次推理的 DDR 权重、特征图、工作区读写量，记为 `B_infer`；其流量为 `B_infer × 推理 FPS`，不包含上表单独列出的输入帧写入。例如 **假设**每次推理产生 0.5 GB DDR 流量，则 3 FPS 需要 1.5 GB/s，5 FPS 需要 2.5 GB/s；与上述重视频场景叠加分别为约 2.5～2.9 和 3.5～3.9 GB/s。后一种即使低于 4.0 GB/s 理论峰值，也不能认为可持续。`B_infer` 必须由模型映射、Tile 复用和 DMA 计数得出，不能由输入图片大小推断。

因此当前结论是：**视频、几何和多图层本身很可能放得下；YOLO 与重图层同时运行是否够用尚不能确认。**在板上测得持续混合读写带宽 `B_eff` 后，先按 `0.75 × B_eff` 作为任务准入的保守总流量上限，再从中扣除视频与图形负载，剩余才是 YOLO 可用预算。这个 75% 是初始调度余量，应依据最坏等待时间实测调整；不是 DDR 的既定效率。

### 4.2 调度与延迟

平均带宽只解决“总量”问题。HDMI 720p60 一行有效像素持续约 17.2 µs；ARGB8888 每行需 5120 byte，像素有效期间的瞬时消耗率约 297 MB/s。若在低水位时 FIFO 只剩一行，DDR 读请求、返回和跨域传输必须在约 17.2 µs 内补给；应再扣除安全余量。Camera 写 FIFO 同样按**输入有效期间的瞬时字节率**和剩余空间计算溢出截止时间，不能使用 30 FPS 的平均率代替。

1. **两级仲裁**：正常时按加权轮询/Deficit 份额调度；HDMI 接近读空或 Camera 接近写满时，按各自剩余截止时间在下一个 Burst 边界优先服务。读、写可分别排队，但 DDR 物理服务时间共用，必须同时监测读写换向与两个实时端口的等待。紧急请求不得一直保持有效，否则会使后台端口饿死。
2. **限制占用时间**：一个 DDR AXI Burst 最多 16×32=512 byte；低优先级 Master 还要限制连续获准 Burst 数和 Outstanding Credit，不能连续提交整帧而占住 DDR。为 HDMI 保留可用的读命令/返回容量，为 Camera 保留写入容量；只在仲裁器里提高优先级而把 DDR UI 队列预先塞满 YOLO 请求仍然会错过截止时间。
3. **软实时与后台调度**：Geometry/Renderer 按当前目标显示帧的完成期限获得份额；YOLO 使用可用余量，但保留可测的最低服务份额以避免无限期停滞。任务准入根据已测 `B_eff`、当前图层数、Surface 格式和 YOLO 每次推理字节数决定并发级别，而不是只给 AXI Master 固定优先级。CPU/调试 DMA 限速。
4. **超载退化**：先减少 YOLO 取帧和推理并发，再降低可选图层/Renderer 更新率；Geometry 或 Renderer 错过目标帧时丢弃旧待处理帧，HDMI 重复上一张完整帧。Camera 不能在行中间停顿，HDMI 不能扫描未写完的 Surface。已经发出的 AXI 请求必须正常 Drain，Fence 在最终响应后才完成。
5. **限制帧级延迟**：Pixel→DDR→Geometry→DDR→Renderer→DDR 的全帧依赖，即使零仲裁等待，也可能使显示落后多个 30 FPS 帧周期。各阶段处理不同帧以保持 30 FPS 吞吐；预览和简单效果旁路不需要的整帧级。分别统计采集到显示延迟、显示帧重复率和 Detection META 年龄，避免以 HDMI 始终输出 60 Hz 掩盖画面更新变慢。
6. **模式切换**：停止接收旧命令、排空已发 AXI 事务、等待新模式生成完整显示帧，再在 VBlank 切换；不得靠复位丢失在途事务和缓冲所有权。

验收必须同时覆盖：原始 DDR 与多 Master 混合有效带宽、各 Master 最大服务间隔和队列占用、HDMI underflow、Camera overflow、完整帧率、端到端延迟、YOLO 结果年龄和资源/时序。压测应同时注入 HDMI 扫描、Camera 连续输入、Geometry 读写、Renderer 多图层和可控强度的 YOLO 流量；仅凭均值或单 Master 峰值不能验收。单模块综合与布局布线只能证明局部可实现性，不能替代完整系统混合负载验证。

## 5. 当前依据与集成顺序

- Pixel RTL 已有 RGB565 双像素点运算和共享 3×3 空间处理，定向仿真及 Camera→Pixel→DDR→HDMI 集成仿真通过；其详细状态和待完成项见像素处理设计计划与 `docs/validation/2026-09-19-pixel-pipeline.md`。
- Geometry 已有 DDR Surface-to-Surface 的 Block/Strip 路径与逐像素仿真证据。125 MHz 下的算术发射上限为 62.5 Mpixel/s，尚未计 Patch 读取和 Band 排空；720p30 需求为 27.65 Mpixel/s，720p60 则不能据此宣称可持续。详见 `docs/validation/2026-09-21-geometry-surface-pipeline.md`。
- DDR IP、Adapter、Interconnect 与 CPU Gateway 有分层仿真记录；旧事务拆分结果属于被替换的设计，不能作为当前 AXI profile 的板级吞吐证据。详见 `docs/validation/2026-09-18-ddr-layered-simulation.md`。

集成顺序为：DDR 与 HDMI/Camera 闭环 → Pixel → Geometry 与 Surface 交接 → YOLO 分支 → Renderer 合成 → 全系统混合流量、时序和板测。每加入一段，保留已验证路径的旁路与回归，最终在一个 bitstream 中验收。
