# ip_ram_rnd_window

用途：RND v0.3 AFFINE_BLIT 的32块8×8解码源窗口。四个实例按(x低位,y低位)分银行，每银行256×64有效位，共8KiB；不复制窗口。

在PDS IP Compiler新建Distributed/Block Memory中的 **DRM simple dual-port RAM**，模块名填`ip_ram_rnd_window`：

| 选项 | 值 |
|---|---|
| Memory type | Simple dual-port RAM，独立写口和读口 |
| Implementation | DRM（不使用分布式RAM） |
| Write/read data width | 64 bit / 64 bit |
| Write/read depth | 512 / 512 |
| Address width | 9 bit / 9 bit（包装将高位绑0，只用低256项） |
| Byte write enable | Disabled，整64位写 |
| Write clock / read clock | Separate ports，同接clk_mem，125MHz |
| Write enable | Enabled，wr_en |
| Read clock enable | Enabled，rd_clk_en |
| Read output register | Disabled，RAM同步读本身提供1周期延迟 |
| Read-during-write same address | Don't care / undefined（调用者不消费这种冲突） |
| Reset polarity | Active high；包装将两个reset绑0 |
| Initialization | None，不加载初始化文件，valid/tag管理所有权 |

生成后端口必须如下；写在时钟上升沿完成，读使能上升沿采样地址并在该拍后输出，读使能为0时输出保持。

| 端口 | 方向 | 位宽 |
|---|---|---|
| wr_clk | in | 1 |
| wr_en | in | 1 |
| wr_addr | in | 9 |
| wr_data | in | 64 |
| wr_rst | in | 1 |
| rd_clk | in | 1 |
| rd_clk_en | in | 1 |
| rd_rst | in | 1 |
| rd_addr | in | 9 |
| rd_data | out | 64 |

包装：`rtl/tech/edrv32_ram_rnd_window.v`；使用者`edrv32_rnd_window`，共四个实例，预期每实例占一个36Kbit DRM站点，最终以PDS报告核对。
