# ip_ram_npu_post_table

| 项 | 内容 |
|---|---|
| IP 类型 | IP Compiler → Memory → DRM，True Dual Port RAM（真双口） |
| 模块名 | `ip_ram_npu_post_table` |
| 包装 | `rtl/tech/edrv32_ram_npu_post_table.v` |
| 使用者 | `edrv32_npu_post`，exp/probability 各一实例，分别保留三个 head |
| 依据 | npu-spec 4.4、5.2、5.6；CLAUDE.md 8 |
| 器件 | PG2L200H；速度等级沿用整片工程 |

## 创建选项

| 选项 | 值 |
|---|---|
| Memory type | True Dual Port RAM / DRM |
| Port A / B 数据宽度 | 都为 32 bit |
| Port A / B 深度 | 都为 1024，地址都是 10 bit |
| 时钟 | 两端口均连接 clk_npu，同频同相 |
| Port A / B clock enable | 都使能；读阵列仅在 clk_en 为 1 时更新 |
| Port A / B output register | 都勾选，阵列读加输出寄存器共 2 拍；输出寄存器始终使能（如生成 a_oce/b_oce，包装须接 1） |
| Byte write enable | 关闭；32 bit 整字写 |
| Reset | 不复位内容或输出；复位端口接无效电平 0 |
| 初始化 | 无初始化文件；上电内容不确定 |
| 冲突模式 | 不依赖同址写读返回值；装表先排空分类，尾处理期间不写表 |

## 期望端口与连接

| 端口 | 方向/宽度 | 包装连接 |
|---|---|---|
| a_clk / b_clk | in 1 | clk_i |
| a_rst / b_rst | in 1 | 0 |
| a_clk_en / b_clk_en | in 1 | a_en_i / b_en_i |
| a_wr_en / b_wr_en | in 1 | a_write_i / 0 |
| a_addr / b_addr | in 10 | a_addr_i / b_addr_i |
| a_wr_data / b_wr_data | in 32 | a_data_i / 0 |
| a_rd_data / b_rd_data | out 32 | a_data_o / b_data_o |

地址为 `{head[1:0], index[7:0]}`，使用 0..767，其余未使用。
exp 实例仅使用 A 端口，probability 实例在分类时双端口各服务一个像素，尾处理使用 A。
装表由 A 端口整字写入；行为模型无初始化，读阵列与输出各一拍，冲突返回旧值但业务不依赖。

生成文件留在 Windows FPGA 工程并加入工程，不入库。生成后在 Windows 任务卡 result.md 回传实际端口列表、DRM 数和设置截图；若实际端口名不同，由协调者修改包装 FPGA 分支，不能改生成文件。
