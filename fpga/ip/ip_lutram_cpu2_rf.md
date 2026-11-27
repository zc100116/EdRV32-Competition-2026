# ip_lutram_cpu2_rf

| 项 | 设置 |
|---|---|
| IP Compiler | Memory → Distributed RAM → Simple Dual Port RAM |
| Module Name | `ip_lutram_cpu2_rf` |
| 包装 | `rtl/tech/edrv32_ram_cpu2_rf.v` |
| 器件 | PG2L200H-6 |
| 使用者/实例数 | RF×8、AGU读路径×2 |
| Write/Read Width | 32 / 32 |
| Write/Read Depth | 32 / 32（地址 5 位） |
| 时钟 | 同一个 clk_sys，上升沿，同步整字写 |
| Byte Enable | 关闭 |
| Read Address Register | 关闭；组合读 |
| Read Clock Enable | 关闭 |
| Output Register | 关闭 |
| Read During Write | 沿前旧值，沿后新值 |
| Reset | rst 高有效，包装接0；不复位存储 |
| 初始化 | 无初始化文件；内容与输出不复位。 |

端口名必须与包装中的命名连接相同：`wr_clk`、`wr_en`、`wr_addr[4:0]`、
`wr_data[31:0]`、`rd_clk`、`rd_addr[4:0]`、`rd_data[31:0]`，
另有 `rst`，时钟/使能/复位均1位。
在 PDS 工程内创建 IP，填写上述模块名，按表设置后 Generate；生成文件保留在工程内。
生成后回传端口声明、选项截图与资源报告；端口不同由协调者修订包装连接，不改生成文件。
