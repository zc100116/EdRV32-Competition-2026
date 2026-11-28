# ip_ram_gpu2_sfu_scratch

| 项 | 固定设置 |
|---|---|
| 入口 / 资源 | PDS IP Compiler → Memory → Simple Dual Port RAM / DRM |
| Module Name | `ip_ram_gpu2_sfu_scratch` |
| 形状 | 1024×32，地址10位，整字写；实际只用0..31，包装高5位接0 |
| 时钟 | wr_clk/rd_clk均接clk_gpu，上升沿；开启rd_clk_en端口并固定接1 |
| 额外地址 / 输入寄存器 | 关闭 |
| 延迟 | 阵列读1拍，关闭额外输出寄存器 |
| Write mode | 不依赖 RAM 碰撞结果：同址时包装用外部同边沿转发返回新字；用 PDS 默认（NORMAL_WRITE） |
| Reset / Initialization / Byte Enable | 不复位数据/内容；wr_rst/rd_rst固定为0；无初始化和byte enable |
| 端口 | wr_clk、wr_rst、wr_en、wr_addr[9:0]、wr_data[31:0]、rd_clk、rd_rst、rd_clk_en、rd_addr[9:0]、rd_data[31:0] |
| 包装 / 数量 | `edrv32_ram_gpu2_sfu_scratch`，四输入字段按消费者分7份（engine0不读LOG基值），中间结果7份，共14DRM |

末槽7无后继读者，engine0也不读LOG基值，因此较16bank规划省2DRM。
同边沿转发切开RAM碰撞语义并与算术核心重叠；相隔10拍的算术依赖另有核心返回旁路，
不在模型之外添加等待。包装的32bit转发数据寄存和两个16bit选择叶是外部FF，不计入DRM内部。
生成文件只留PDS工程；ModelSim核实同步读及同址转发，PDS按层次核实14DRM与寄存器数。
