# ip_ram_gpu_target_tail

| 项 | 内容 |
|---|---|
| IP 类型 | IP Compiler → Memory → DRM（块 RAM）简单双口 RAM（Simple Dual Port），读写同一时钟 |
| 模块名 | `ip_ram_gpu_target_tail` |
| 包装模块 | `rtl/tech/edrv32_ram_gpu_target_tail.v` |
| 用途 | GPU 目标 RAM，微结构 4.8 |
| 使用者 | target，尾部 3 实例，与 RESOLVE 行缓冲分开 |
| 依据 | gpu-spec 2.1、2.3；微结构 4.8 |
| 器件 | PG2L200H，速度等级以工程为准 |

## 选项

| 选项 | 取值 |
|---|---|
| 数据位宽 | 写端口和读端口都为 72 |
| 深度 | 512（地址 9 位） |
| 字节写使能 | 不勾选 |
| 读时钟使能（读使能） | 勾选；读使能为 0 时输出保持 |
| 输出寄存器 | 勾选；阵列加输出寄存器共 2 拍；输出寄存器持续使能 |
| 读写同址冲突 | 不依赖：target 在阵列采样沿捕获提交字旁路 |
| 写端口时钟 / 读端口时钟 | 同一 clk_gpu 时钟 |
| 复位 | 不复位内容或输出；IP 带复位端口时在包装中接无效电平 |
| 初始化 | 无初始化文件 |

## 期望端口

| 端口 | 方向 | 位宽 |
|---|---|---|
| `wr_clk`、`rd_clk` | in | 1（同一时钟） |
| `wr_en`、`rd_clk_en`（读使能） | in | 1 |
| `wr_rst`、`rd_rst` | in | 1（包装接 `1'b0`） |
| `wr_addr`、`rd_addr` | in | 9 |
| `wr_data` | in | 72 |
| `rd_data` | out | 72 |

## 生成后需要回传的信息

PDS 生成的端口名由 IP 决定，不能手动改名。请在 Windows 任务卡的 `result.md` 记录模块名、实际端口列表、实际占用的 DRM 块数和选项最终取值截图（放 `artifacts/`）。实际端口与期望端口不一致时，由协调者修改包装模块 FPGA 分支，不修改生成文件。
