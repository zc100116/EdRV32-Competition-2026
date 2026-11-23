# ip_lutram_gpu_read_pool

| 项 | 内容 |
|---|---|
| IP 类型 | IP Compiler → Memory → Distributed RAM → Simple Dual Port RAM |
| 模块名 | `ip_lutram_gpu_read_pool` |
| 包装模块 | `rtl/tech/edrv32_ram_gpu_read_pool.v` |
| 使用者 | GPU DMA 读池，4 个 16 beat 区 |
| 器件 | PG2L200H，速度等级以工程为准 |
| 依据 | gpu-microarch 4.8、4.9；CLAUDE.md 8 |

## 固定选项

| 选项 | 取值 |
|---|---|
| 数据宽度 | 写、读均 256 位 |
| 深度 / 地址宽度 | 64 / 6 位 |
| 资源 / 端口 | 分布式 RAM，简单双口 |
| 时钟 | 写读均接 clk_gpu，上升沿 |
| 写入 | 同步写，整字写使能，不启用字节使能 |
| 读出 | 组合读，不注册地址，输出寄存器关闭；包装模块寄存输出 |
| 延迟 | 包装端口读延迟 1 拍，rd_en_i=0 保持输出 |
| 复位 / 初始化 | 不复位内容或数据输出，无初始化文件；上电内容未定义 |
| 同址读写 | 业务控制不同时读写同址，不依赖碰撞结果 |

## 生成端口

| 端口 | 方向 / 宽度 |
|---|---|
| wr_clk、rd_clk | 输入 / 1，均接 clk_i |
| wr_en | 输入 / 1 |
| wr_addr、rd_addr | 输入 / 6 |
| wr_data、rd_data | 输入、输出 / 256 |
| rst | 输入 / 1，接 0 |

PDS 生成文件不入库。Windows 回传实际端口、配置截图和资源；端口有差异时只调整包装的 FPGA 分支。
