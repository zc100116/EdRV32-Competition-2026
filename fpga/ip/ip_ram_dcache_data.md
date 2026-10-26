# ip_ram_dcache_data

| 项 | 内容 |
|---|---|
| IP 类型 | IP Compiler → Memory → DRM（块 RAM）简单双口 RAM（Simple Dual Port） |
| 模块名 | `ip_ram_dcache_data` |
| 包装模块 | `rtl/tech/edrv32_ram_dcache_data.v` |
| 使用者 | D$ 每路一块，共 2 块 |
| 器件 | PG2L200H，速度等级以工程为准 |

## 选项

| 选项 | 取值 |
|---|---|
| 数据位宽 | 写端口和读端口都为 64 |
| 深度 | 512（地址 9 位） |
| 字节写使能 | 勾选，8 位（每 8 位数据一位） |
| 读时钟使能（读使能） | 勾选。读使能为 0 的周期，读数据输出保持不变 |
| 输出寄存器 | 不勾选（读延迟 1 个周期：读使能有效的时钟沿之后，下一个周期得到数据） |
| 读写同址冲突 | 读出旧数据（Read First / 读优先）。同一时钟沿对同一地址读和写时，读端口得到写入之前的值；行为模型按此实现 |
| 写端口和读端口时钟 | 同一时钟（clk_sys） |
| 复位 | IP 强制带高有效 `wr_rst`/`rd_rst`，只作用于读出通路；包装模块接 `1'b0` |

PDS 的简单双口 DRM 如果不支持 64 位宽下的 8 位字节写使能，请在 `result.md` 中说明，协调者会改为按字节拆分的多块 RAM（cache-plan 风险项）。

## 实际端口（PDS 2022.2-SP6.1 生成，任务 20261025-01 回传）

| 端口 | 方向 | 位宽 | 包装模块连接 |
|---|---|---|---|
| `wr_clk` | in | 1 | `clk_i` |
| `wr_en` | in | 1 | `wr_en_i` |
| `wr_addr` | in | 9 | `wr_addr_i` |
| `wr_data` | in | 64 | `wr_data_i` |
| `wr_byte_en` | in | 8 | `wr_byte_en_i` |
| `wr_rst` | in | 1 | `1'b0`（高有效，存储不复位） |
| `rd_clk` | in | 1 | `clk_i` |
| `rd_clk_en` | in | 1 | `rd_en_i` |
| `rd_addr` | in | 9 | `rd_addr_i` |
| `rd_data` | out | 64 | `rd_data_o` |
| `rd_rst` | in | 1 | `1'b0` |

## 生成后需要回传的信息

PDS 生成的端口名由 IP 决定，不能手动改名。生成后请在 Windows 任务卡的 `result.md` 中记录：
1. 生成的模块名（必须为上面的模块名，在 IP Compiler 中填写实例名/模块名时设置）；
2. 生成文件中模块的实际端口列表（名称、方向、位宽）；
3. 各选项的最终取值截图（PNG，放 `artifacts/`）。

重新生成后端口与上表不一致时，由协调者统一修改包装模块的 FPGA 分支，不要改生成的文件。
