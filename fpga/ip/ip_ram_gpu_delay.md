# ip_ram_gpu_delay

| 项 | 内容 |
|---|---|
| IP 类型 | IP Compiler → Memory → DRM → Simple Dual Port RAM |
| 模块名 | `ip_ram_gpu_delay` |
| 包装模块 | `rtl/tech/edrv32_ram_gpu_delay.v` |
| 使用者 | GPU perspective 延迟线 34 实例、结果队列 12 实例，raster 延迟线 5 实例、texture 过滤元数据 2 实例、setup_plane 元数据 2 实例、project 元数据 4 实例、object 索引 1 实例，共 60 个 DRM36K |
| 器件 | PG2L200H，速度等级以工程为准 |
| 依据 | gpu-spec 2.5、2.13；S-2 FF closure；CLAUDE.md 8 |

## 固定选项

| 选项 | 取值 |
|---|---|
| 数据宽度 | 写、读均 72 位 |
| 深度 / 地址宽度 | 512 / 9 位 |
| 资源 / 端口 | DRM，一片 36Kb，简单双口 |
| 时钟 | 写读均接 clk_gpu，上升沿 |
| 写入 | 同步写，整字写使能，不启用字节使能 |
| 读出 | 同步读，启用读时钟使能，输出寄存器关闭 |
| 延迟 | 包装端口读延迟 1 拍，rd_en_i=0 保持输出 |
| 复位 / 初始化 | 不复位内容或数据输出，无初始化文件；上电内容未定义 |
| 同址读写 | 业务控制不同时读写同址，不依赖碰撞结果 |

## 生成端口

| 端口 | 方向 / 宽度 |
|---|---|
| wr_clk、rd_clk | 输入 / 1，均接 clk_i |
| wr_en | 输入 / 1 |
| wr_addr、rd_addr | 输入 / 9 |
| wr_data、rd_data | 输入、输出 / 72 |
| wr_rst、rd_rst | 输入 / 1，接 0 |
| rd_clk_en | 输入 / 1，接 rd_en_i |

PDS 生成文件不入库。Windows 回传实际端口、配置截图和资源；端口有差异时只调整包装的 FPGA 分支。

raster 的 64 项结果 FIFO 复用现有 `ip_lutram_gpu_read_pool` 九实例，
使用相同 64×256 配置，不新增 IP 类型，也不计入上述 DRM 用量。
