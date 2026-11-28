# ip_lutram_cpu2_fast

| 项 | 设置 |
|---|---|
| IP Compiler | Memory → Distributed RAM → Simple Dual Port RAM |
| Module Name | `ip_lutram_cpu2_fast` |
| 包装 | `rtl/tech/edrv32_ram_cpu2_fast.v` |
| 器件 | PG2L200H-6 |
| 使用者/实例数 | gshare四bank×三读副本，共12 |
| Write/Read Width | 2 / 2 |
| Write/Read Depth | 1024 / 1024（地址 10 位） |
| 时钟 | 同一个 clk_sys，上升沿，同步整字写 |
| Byte Enable | 关闭 |
| Read Address Register | 关闭；组合读 |
| Read Clock Enable | 关闭 |
| Output Register | 关闭 |
| Read During Write | 沿前旧值，沿后新值 |
| Reset | rst 高有效，包装接0；不复位存储 |
| 初始化 | HEX 初始化文件 ip_lutram_cpu2_fast.dat：1024 行，每行 1；内容不复位。 |

端口名必须与包装中的命名连接相同：`wr_clk`、`wr_en`、`wr_addr[9:0]`、
`wr_data[1:0]`、`rd_clk`、`rd_addr[9:0]`、`rd_data[1:0]`，
另有 `rst`，时钟/使能/复位均1位。
在 PDS 工程内创建 IP，填写上述模块名，按表设置后 Generate；生成文件保留在工程内。
生成后回传端口声明、选项截图与资源报告；端口不同由协调者修订包装连接，不改生成文件。

逻辑4096×2：包装按地址[11:10]分成4个1024×2 IP；两查询与训练读各复制一份，共12实例。
初始化文件：`python -c "open('ip_lutram_cpu2_fast.dat','w').write('1\n' * 1024)"`。
