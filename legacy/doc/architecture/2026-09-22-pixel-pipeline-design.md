# Pixel Pipeline 设计计划

日期：2026-09-22  
系统位置见 [视觉系统总体框架](2026-09-14-vision-system-design.md)。本文件只规定像素处理支路；DDR Surface 所有权、Geometry、YOLO 和显示调度由总体框架规定。

## 1. 模块职责与接口

Pixel Pipeline 接收 Camera RX/CDC 后选定的视频流，进行逐像素与有限邻域处理，再将输出交给 Surface Writer。它不负责摄像头选源、DDR 地址生成、几何变换或显示页切换，也不作为 YOLO 的必经输入级。

现有 RTL 的外部流格式与 Camera FIFO、Display Writer 一致：`{sof, eof, 16 × RGB565}`，共 258 bit；使用 `valid/ready` 握手。内部解包为每拍两个 RGB565 像素，经过点运算和共享 3×3 窗口后重新打包。目标处理分辨率为 1280×720，输出帧的像素数量、行宽与 SOF/EOF 必须和输入一致。

```text
选定 Camera 流
  → 16 像素包解包 / 行边界
  → 2 像素/拍点运算
  → 共享 3×3 窗口与空间算子
  → 16 像素包重组
  → Surface Writer → DDR Pixel Surface
```

Pixel 的旁路是逐像素等值旁路；关闭某项功能不应让图像再次经过 DDR。Surface Writer 在全帧写响应完成后发布 READY，不能只凭 Pixel 输出 EOF 宣告 DDR 数据可读。

## 2. 当前已经实现的基线

| 层 | 已有能力 |
|---|---|
| 点运算 | RGB565 展开/重新量化、灰度、亮度、Q8 对比度、单阈值二值化、反色、旁路 |
| 空间运算 | 共享双像素 3×3 窗口；Sobel、均值、高斯、五点锐化、腐蚀、膨胀及旁路 |
| 边界 | 零填充，一行垂直延迟，帧尾补零行；输入输出像素数相同 |
| 配置 | APB slot 12；系统域到处理域 toggle/ack；shadow 参数在下一帧 SOF 原子提交 |
| 背压 | 各级 `valid/ready`，可在任意输出停顿下保持像素、SOF/EOF 与配置一致 |

现有 3×3 窗口使用三条旋转行存储；Pango `pixel_line_ram` 为单一 IP 定义并被 RTL 例化三次。详见 `docs/validation/2026-09-20-pixel-spatial-filters.md`，不要把行缓存误写为完整帧 DDR 往返。

## 3. 功能范围与配置规则

Pixel 支路的功能按下列顺序组织，实际使能通过配置控制：

```text
格式展开 → 颜色/增益类点运算 → Gamma/LUT → 灰度/阈值
        → 邻域滤波/形态学 → RGB565 输出
```

现有点运算和 3×3 功能按第 2 节作为实现基线。原计划中的颜色矩阵、白平衡/色温、Gamma/自定义 LUT、颜色空间转换、5×5 或可编程卷积尚不属于已有 RTL 能力；若继续纳入 Pixel，应逐项给出定点系数范围、舍入/饱和规则、资源与时序结果，再加入已通过的主路径。每新增一项必须保持旁路逐像素一致。

配置通过 shadow 寄存器提交，在下一帧 SOF 同时生效。提交与应答期间跨时钟传输的 payload 保持稳定；不能在一行中途切换参数。点运算与空间算子共用同一帧配置版本；`frame_id` 由分发器和 Surface Writer 在模块外关联，不要求改动现有 258-bit Pixel 流格式。

空间算子只依赖有限邻域，在片上行存储运行。任何需要整帧随机寻址的操作交给 Geometry 或 Renderer，不向 Pixel 增加整帧缓存。图像处理效果只作用于 Pixel 分支；YOLO 从 Camera 分发器取得独立输入，并使用自己的模型预处理约定。

## 4. 吞吐与时序

1280×720@30 的有效像素率为 27.65 Mpixel/s。现有内部目标为每拍两个像素；在 125 MHz 下纯算术发射能力为 250 Mpixel/s，但不能把这个数字当作包含解包、行缓存、帧尾冲刷、下游背压和 DDR 写入的实测帧率。

关键时序路径按模块边界检查：解包到点运算、点运算到行窗口、行 RAM 读出到滤波、滤波到重包、配置扇出，以及重包到 Writer 的 `ready` 回传。若布局布线需要加流水寄存器，数据、有效位、SOF/EOF 和配置版本必须一起延迟；相邻阶段用本地容量切断跨级组合 `ready` 路径。不能用降低输出像素数或改变边界像素行为换时序。

Camera 输入不能长期受 Pixel/DDR 反压。Surface Writer 使用独立写 FIFO，并把高水位传给 DDR 仲裁；FIFO 满、行长错误和丢帧必须计数。Pixel 帧未完整写入时，下游继续使用上一张 READY Surface。

## 5. 验证与完成条件

已有证据：`vision/pixel-pipeline` 定向仿真通过 7102 项检查、13 帧；`vision/pixel-control-apb` 通过 40 项；Camera→Pixel→DDR→HDMI 集成仿真通过逐像素 Golden 和随机背压。详见 `docs/validation/2026-09-19-pixel-pipeline.md`。这些结果不等于 PG2L200H 上已完成综合、布局布线或 720p 长时间板测。

后续每次功能或时序调整，应检查：

1. 旁路逐像素一致，全部模式与独立 NumPy/OpenCV Golden 一致；覆盖零/满量程、奇数边界、首尾行、连续帧和随机背压。
2. SOF/EOF、行宽、输出像素总数、frame_id 和帧边界配置提交始终对齐；复位与 FIFO 满/空恢复后不混帧。
3. Pango 行 RAM 原语行为、资源推断、单模块 PNR 和 Camera→Pixel→DDR→HDMI 集成 PNR 通过；记录各时钟域 setup/hold 与最大扇出。
4. 板级 720p 连续运行时无新增 Camera overflow、Pixel 丢帧或显示 underflow，并记录最大 Writer 等待时间及端到端延迟。

只有上述功能、时序和板级结果同时满足，才将 Pixel 支路标记为完成；未实现的扩展功能应按实际 RTL 能力单独报告。
