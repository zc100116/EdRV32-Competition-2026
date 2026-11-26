# ip_lutram_gpu_delay

| 项 | 内容 |
|---|---|
| IP 类型 | IP Compiler → Memory → Distributed RAM → Simple Dual Port RAM |
| 模块名 | `ip_lutram_gpu_delay` |
| 包装模块 | `rtl/tech/edrv32_ram_gpu_delay64.v` |
| 使用者 | GPU 内深度 ≤ 64 的延迟线、结果队列、按标签寻址的小常数表（取代这些位置原来用的 `ip_ram_gpu_delay` DRM） |
| 器件 | PG2L200H，速度等级以工程为准 |
| 依据 | gpu-microarch 4.15；CLAUDE.md 8 |

## 固定选项

| 选项 | 取值 |
|---|---|
| 数据宽度 | 写、读均 72 位 |
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
| wr_data、rd_data | 输入、输出 / 72 |
| rst | 输入 / 1，接 0 |

生成选项与 `ip_lutram_gpu_read_pool` 相同，只有数据宽度不同（256 → 72）。PDS 生成的文件不入库。Windows 端回传实际端口、配置截图和资源用量；端口与本表不一致时，只调整包装模块的 FPGA 分支。
