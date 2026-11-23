# ip_lutram_gpu_palette_current

| 项 | 内容 |
|---|---|
| IP 类型 | IP Compiler → Memory → Simple Dual Port Distributed RAM |
| 模块名 | `ip_lutram_gpu_palette_current` |
| 包装模块 | `rtl/tech/edrv32_ram_gpu_palette_current.v` |
| 用途 | 当前组 8 副本各 16 个 16×20 页，共 128 个实例 |
| 依据 | gpu-spec 2.6；2026-11-24-gpu-microarch 4.8 |
| 器件 | PG2L200H，速度等级以工程为准 |

## 固定配置

| 选项 | 取值 |
|---|---|
| 深度 / 位宽 | 16 × 20；地址 4 位，两端等宽 |
| 时钟 | 单一 clk_gpu，上升沿 |
| 复位 | 不复位内容或输出；IP 复位接 `1'b0` |
| 初始化 | 无，不选择初始化文件 |
| 资源 | Distributed RAM，不选 DRM |
| 端口模式 | Simple Dual Port；同步写，独立地址组合读 |
| 输出寄存器 / 读地址寄存器 | 均关闭，IP 组合读 0 拍 |
| 字节写使能 / 读时钟使能 | 均关闭 |

## 端口与包装时序

期望端口：`wr_clk`、`rd_clk`、`rst`、`wr_en` 各 1 位；`wr_addr`、
`rd_addr` 各 4 位；`wr_data`、`rd_data` 各 20 位。只有 `rd_data` 是输出。
`rd_clk` 接 clk_gpu，`rst` 接 0；组合读不依赖 rd_clk。
包装的 256×20 由 16 页组成：索引寄存 1 拍、页数据采样 1 拍、4 页选择
1 拍、最终 4 选 1 再 1 拍，读请求到结果共 4 拍，单副本每拍 1 读。
广播预装只写选中页，绘制期间不写。页行为模型同址采样旧值；业务不依赖此冲突。

## 生成回传

Windows 端记录实际模块名、端口、配置截图及资源占用；实际端口和期望不一致时，
由协调者修改包装 FPGA 分支，不修改生成文件。生成文件不入库。
