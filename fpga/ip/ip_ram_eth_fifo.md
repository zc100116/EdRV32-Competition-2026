# ip_ram_eth_fifo

| 项 | 内容 |
|---|---|
| IP 类型 | IP Compiler → Memory → DRM（块 RAM）简单双口 RAM（Simple Dual Port），读写端口独立时钟 |
| 模块名 | `ip_ram_eth_fifo` |
| 包装模块 | `rtl/tech/edrv32_ram_eth_fifo.v` |
| 用途 | ETH 接收、发送异步 FIFO 的存储（SoC 规格 5.2 X7）：每项 8 位字节加 2 位帧标记 |
| 使用者 | ETH 接收异步 FIFO（eth_rx_clk 写、clk_mem 读）1 实例，发送异步 FIFO（clk_mem 写、eth_tx_clk 读）1 实例，共 2 实例 |
| 依据 | ETH 规格 5.2、9 第 1 项 |
| 器件 | PG2L200H，速度等级以工程为准 |

## 选项

| 选项 | 取值 |
|---|---|
| 数据位宽 | 写端口和读端口都为 10 |
| 深度 | 512（地址 9 位） |
| 字节写使能 | 不勾选 |
| 读时钟使能（读使能） | 勾选；读使能为 0 时输出保持 |
| 输出寄存器 | 不勾选；同步读延迟 1 个读时钟周期 |
| 读写同址冲突 | 不依赖：异步 FIFO 控制只读已写入且写指针已同步过来的项 |
| 写端口时钟 / 读端口时钟 | **独立**：两个端口各接一个 125 MHz 时钟，互不相关（接收实例写 eth_rx_clk、读 clk_mem；发送实例写 clk_mem、读 eth_tx_clk） |
| 复位 | 不复位内容或输出；IP 带复位端口时在包装中接无效电平 |
| 初始化 | 无初始化文件 |

## 期望端口

| 端口 | 方向 | 位宽 |
|---|---|---|
| `wr_clk`、`rd_clk` | in | 1（两个不同时钟） |
| `wr_en`、`rd_clk_en`（读使能） | in | 1 |
| `wr_rst`、`rd_rst` | in | 1（包装接 `1'b0`） |
| `wr_addr`、`rd_addr` | in | 9 |
| `wr_data` | in | 10 |
| `rd_data` | out | 10 |

## 生成后需要回传的信息

PDS 生成的端口名由 IP 决定，不能手动改名。请在 Windows 任务卡的 `result.md` 记录模块名、实际端口列表、实际占用的 DRM 块数和选项最终取值截图（放 `artifacts/`）。实际端口与期望端口不一致时，由协调者修改包装模块 FPGA 分支，不修改生成文件。
