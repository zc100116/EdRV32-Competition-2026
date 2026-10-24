# Render Command Engine

`make case-sim CASE=vision/render-engine`。DDR 命令列表依次执行 RGB565 底图填充、ARGB 前景清除、两层带透明度的圆角矩形、A8 蒙版着色、RGB565 和 ARGB8888 位图叠加与原地合成；在随机 AXI 背压下逐像素检查 64×32 输出，并生成 `sim/build/cases/vision/render-engine/render.ppm`。主画面圆角读写 174 beat、各 29 个 Burst；另有跨 4 KiB 的 2 beat 用例，被拆成两个 Burst。检查非法操作码、非法圆角描述符及连续批次恢复。

`ROUND_RECT` 描述符操作码为 `0x04`。32-bit word 1/2 为前景首行地址与 stride，word 3 为 `{width[15:0], x[15:0]}`，word 4 的低 16 bit 为高度、高 16 bit 的低 10 bit 为半径；word 5 的低 10 bit 为边框宽度；word 6/7 分别为普通 ARGB8888 填充色和边框色。首行地址已包含 y 偏移，x 是该行的像素坐标。颜色在混合前转成预乘 Alpha。地址及 stride 必须按 32 byte 对齐，矩形不能超出 stride。

`A8_BLIT` 操作码为 `0x05`。word 1/2 为前景首行地址与 stride，word 3 为 `{width, x}`，word 4 低 16 bit 为高度，word 5/6 为 A8 蒙版首行地址与 stride，word 7 为普通 ARGB8888 着色。当前每条命令支持宽 1–32 像素，每行蒙版恰占一个对齐的 256-bit beat；长素材可由软件按水平块拆成多条命令。目标前景按行组成不跨 4 KiB 的 Burst。渐变 A8 与随机 AXI 背压用例逐像素验证透明度和命令顺序；24 个目标 beat 使用各 8 个读/写 Burst，另测 4 KiB 分界拆分和 X=7、宽 32 像素的五 beat 上限。

`BITMAP_BLIT` 操作码为 `0x06`。word 0 bit 8 选择 ARGB8888（0 为 RGB565），bit 9 指示预乘 ARGB，bit 10/11 分别控制水平/垂直翻转，bit 12 启用颜色键，bit 13 启用最近邻缩放，bits 23:16 为全局透明度。word 1/2 为前景首行地址及 stride，word 3 为 `{width, dest_x}`，word 4 为 `{source_x, height}`，word 5/6 为源首行地址及 stride，word 7 为颜色键原始像素值，word 8/9 是水平/垂直 Q16 无符号采样步长。缩放时，`source_x` 与源首行地址指向首个采样像素及所在行；翻转标志使步长反向，软件应将首地址或 `source_x` 设在素材对应边界。不缩放时仍使用原有 1:1 快路径。源和目标行地址及 stride 均须 32-byte 对齐，目标 X 可任意取值；源尺寸/坐标超出 stride 时缩放路径返回错误。颜色键按源像素原值比较，命中时保留目标像素。输出按最多 8 beat、不跨 4 KiB 的 tile 写回。仿真逐像素验证了 RGB565/ARGB8888 放大、缩小、翻转与颜色键。源/目标重叠搬运尚未实现。

`COPY` 操作码为 `0x07`，word 0 bit 8 选择 ARGB8888（0 为 RGB565），bit 9 声明源/目标 Surface 不相交。word 1/2 为源首行地址与 stride，word 3 为 `{width, source_x}`；word 4/5 为目标首行地址与 stride，word 6 为 `{height, target_x}`。同 Surface 重叠复制要求 stride 相同；明确不相交的复制可使用不同 stride。执行器用例检查两种模式的矩形数据与邻接像素。

`GRADIENT` 操作码为 `0x08`。word 0 bit 8 选择 ARGB8888（0 为 RGB565），bit 9 选择垂直方向（0 为水平）；word 1/2 为目标首行地址与 stride，word 3 为 `{width, x}`，word 4 低 16 bit 为高度，word 5 为起点 ARGB8888 颜色，word 6–9 依次是 Alpha、红、绿、蓝通道的有符号 Q16.16 每像素或每行步长。软件用颜色端点及尺寸计算一次步长；前景端点应使用预乘颜色。硬件逐像素累加并将超出 0–255 的结果截断，RGB565 模式忽略 Alpha。当前渐变路径每个 256-bit beat 独立发一次写事务；纯色 `FILL` 保持原多 beat 快路径。

`A8_BLUR` 操作码为 `0x09`。word 1/2 是源 A8 首行地址与 stride，word 3/4 是 DDR 水平模糊临时区地址与 stride，word 5/6 是最终 A8 输出地址与 stride，word 7 为 `{height,width}`，word 8 低 5 bit 为半径（0–15）。源、临时区和输出区行地址及 stride 均需按 32 byte 对齐，临时区不能与另两块区域重叠。算法用固定 `(2r+1)` 窗口和边界零填充，先水平后垂直，两遍分别四舍五入到 8 bit。此命令只生成 A8 蒙版；可随后使用 `A8_BLIT` 着色到前景。

`BOX_SHADOW` 操作码为 `0x0a`。word 1/2 是前景外框首行地址与 stride，word 3 为 `{outer_width,outer_x}`，word 4 为 `{corner_radius[15:0],outer_height}`（半径当前限 8 bit），word 5/6/7 是种子蒙版、水平模糊临时区、最终模糊蒙版的 DDR 地址，word 8 是三个 A8 区域共用的 stride，word 9 是普通 ARGB8888 阴影色，word 10 低 5 bit 是模糊半径（0–15）。软件根据控件位置、阴影偏移和扩展量计算外框；硬件生成内缩的圆角种子蒙版、执行两遍模糊，再按 32 像素宽片段调用 A8 着色 DMA，将阴影画到前景。通常先发阴影命令，再发卡片本体的 `ROUND_RECT` 命令。三块 A8 DDR 区域在整条命令完成前由此命令独占，可在后续阴影命令间复用。
