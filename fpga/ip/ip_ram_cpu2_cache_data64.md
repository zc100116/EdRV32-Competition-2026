# ip_ram_cpu2_cache_data64

| 项 | 设置 |
|---|---|
| IP Compiler | Memory → DRM → Simple Dual Port RAM |
| Module Name | `ip_ram_cpu2_cache_data64` |
| 包装 | `rtl/tech/edrv32_ram_cpu2_cache_data64.v` |
| 器件 | PG2L200H-6 |
| 用途 | D$每路数据、单发射I$每路数据 |
| 使用者/实例数 | D$×2（每路一块）；单发射 I$×2 |
| Write/Read Width | 64 / 64 |
| Write/Read Depth | 2048 / 2048（地址 11 位） |
| 时钟 | 同一个 clk_sys，上升沿，同步写 |
| Byte Enable | 开启，8 位（每 8 位数据一位），端口 `wr_byte_en` |
| Read Address Register | 同步读，一拍延迟 |
| Read Clock Enable | 开启；为0时输出保持 |
| Output Register | 关闭 |
| Read During Write | Read First；同沿同址读旧值 |
| Reset | wr_rst/rd_rst 高有效，包装接0；不复位存储 |
| 初始化 | 无初始化文件；内容与输出不复位。 |

端口名必须与包装中的命名连接相同：`wr_clk`、`wr_en`、`wr_addr[10:0]`、
`wr_data[63:0]`、`wr_byte_en[7:0]`、`rd_clk`、`rd_addr[10:0]`、`rd_data[63:0]`，
另有 `wr_rst`、`rd_rst`、`rd_clk_en`，时钟/使能/复位均1位。
在 PDS 工程内创建 IP，填写上述模块名，按表设置后 Generate；生成文件保留在工程内。
生成后回传端口声明、选项截图与资源报告；端口不同由协调者修订包装连接，不改生成文件。
