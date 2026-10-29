# ip_ram_rnd_line

| 项 | 内容 |
|---|---|
| IP 类型 | IP Compiler → Memory → DRM（块 RAM）简单双口 RAM（Simple Dual Port），字节写使能 |
| 模块名 | `ip_ram_rnd_line` |
| 包装模块 | `rtl/tech/edrv32_ram_rnd_line.v` |
| 用途 | RND 行缓冲的一个 bank（源、目标行，每项一个 256 位 beat） |
| 使用者 | RND，源、目标各 2 个 bank，COPY 行快照 1 个 bank，共 5 实例 |
| 依据 | RND 规格 5.2、7；R-R1 片上存储请求（2026-10-29） |
| 器件 | PG2L200H，速度等级以工程为准 |

## 选项

| 选项 | 取值 |
|---|---|
| 写端口 | 位宽 256，深度 512（地址 9 位） |
| 读端口 | 位宽 256，深度 512（地址 9 位） |
| 字节写使能 | 勾选，32 位（每 8 位数据一位，`wr_byte_en[i]` 对应 `wr_data[8i+7:8i]`） |
| 读时钟使能（读使能） | 勾选；读使能为 0 时输出保持 |
| 输出寄存器 | 不勾选；同步读延迟 1 个周期 |
| 读写同址冲突 | 同拍同址读写的读出值不确定。RND 不在同一拍读写同一地址 |
| 写端口和读端口时钟 | 同一时钟 clk_mem |
| 复位 | 不复位内容或输出；IP 带复位端口时在包装中接无效电平 |
| 初始化 | 无初始化文件 |

PDS 的简单双口 DRM 如果不支持 256 位宽下的 32 位字节写使能，停下并在 `result.md` 中记录 PDS 支持的组合，不要改用其他配置；协调者会改为按字节组拆分的多块 RAM。

## 期望端口

| 端口 | 方向 | 位宽 | 包装模块连接 |
|---|---|---|---|
| `wr_clk`、`rd_clk` | in | 1 | `clk_i` |
| `wr_en` | in | 1 | `wr_en_i` |
| `wr_addr` | in | 9 | `wr_addr_i` |
| `wr_data` | in | 256 | `wr_data_i` |
| `wr_byte_en` | in | 32 | `wr_strb_i` |
| `wr_rst`、`rd_rst` | in | 1 | `1'b0` |
| `rd_clk_en` | in | 1 | `rd_en_i` |
| `rd_addr` | in | 9 | `rd_addr_i` |
| `rd_data` | out | 256 | `rd_data_o` |

## 生成后需要回传的信息

PDS 生成的端口名由 IP 决定，不能手动改名。请在 Windows 任务卡的 `result.md` 记录模块名、实际端口列表、字节使能与数据位的对应、实际占用的 DRM 块数和选项最终取值截图（放 `artifacts/`）。实际端口与期望端口不一致时，由协调者修改包装模块 FPGA 分支，不修改生成文件。
