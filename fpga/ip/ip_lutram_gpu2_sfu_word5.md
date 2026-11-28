# ip_lutram_gpu2_sfu_word5

PDS IP Compiler → Memory → Distributed Simple Dual Port RAM；Module Name为
`ip_lutram_gpu2_sfu_word5`，固定32×5，地址5位，上升沿整字写，异步读。
无初始化、数据/内容复位、byte enable或读输出寄存器；端口 `wr_clk`/`rd_clk`接clk_gpu，
`rst`接0，`wr_en`为注册使能，`wr_addr[4:0]`、`rd_addr[4:0]`、
`wr_data[4:0]`、`rd_data[4:0]`。
包装 `edrv32_ram_gpu2_sfu_word5`，全SFU 4份，共20 LR分配额（32bit/LR）。
逻辑metadata的21位用16+5，返回队列37位用16+16+5；各region独立同边沿使能副本，
每叶最多16个LUTRAM写使能负载，不增加拍数。metadata/队列各自两个读/消费者副本。
生成物留本地PDS工程；Windows验证异步读、端口及实际LUTRAM/CLMS占用后回传。
