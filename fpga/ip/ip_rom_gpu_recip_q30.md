# ip_rom_gpu_recip_q30

固定 GPU Q30 倒数种子 ROM，依据 gpu-spec 2.12 和微结构 4.8。
投影和建立各例化一份，合计 2 个 DRM；不共享读端口。

| IP Compiler 选项 | 取值 |
|---|---|
| 器件 | PG2L200H |
| 类型 | Memory → DRM ROM，单读端口 |
| 模块名 | `ip_rom_gpu_recip_q30` |
| 数据位宽 / 深度 | 18 / 1024（地址 10 位） |
| 时钟使能 | 勾选，低时保持读输出 |
| 输出寄存器 | 不勾选，读延迟 1 拍 |
| 初始化 | `INIT_EN=true`，`INIT_FORMAT=HEX` |
| 初始化文件 | `fpga/ip/gpu_recip_q30.dat`，地址递增，1024 行，每行 5 个 HEX 字符 |
| 复位 | IP 的高有效 `rst` 接常数 0，不复位数据 |

在仓库根目录执行 `python3 tools/gpu/rom/gen_recip_q30.py` 生成初始化文件和包装模块。
第 i 项为 `round(2^60 / (2^30 + i*2^20 + 2^19))` 的高 18 位。
包装模块 `rtl/tech/edrv32_rom_gpu_recip_q30.v` 用常数组合逻辑补全低 12 位，
与 DRM 同拍寄存，输出完整 30 位种子，不能把低位补零。
行为模型从上述相对路径读文件，仿真运行目录必须是仓库根目录。

| 生成模块端口 | 位宽 | 包装连接 |
|---|---:|---|
| `clk` | 1 | `clk_i` |
| `clk_en` | 1 | `en_i` |
| `rst` | 1 | `1'b0` |
| `addr` | 10 | `addr_i` |
| `rd_data` | 18 | `high_w` |

创建后回传实际模块名、端口表及选项截图，由协调者确认；不修改生成文件。
