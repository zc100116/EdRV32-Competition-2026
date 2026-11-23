# ip_rom_gpu_recip_p18

| 项 | 内容 |
|---|---|
| IP 类型 | IP Compiler → Memory → DRM ROM |
| 模块名 | `ip_rom_gpu_recip_p18` |
| 包装模块 | `rtl/tech/edrv32_rom_gpu_recip_p18.v` |
| 使用者 | `edrv32_gpu_perspective`，每 lane 独立例化，共 4 份 |
| 规格 | gpu-spec v0.3 2.13 第 10–11 条 |
| 器件 | PG2L200H |

## 选项

| 选项 | 取值 |
|---|---|
| 数据位宽 | 18 |
| 深度 | 1024（地址 10 位） |
| 时钟使能 | 勾选；使能为 0 时保持输出 |
| 输出寄存器 | 不勾选；总读延迟 1 拍 |
| 初始化 | `INIT_EN=true`，`INIT_FORMAT=HEX` |
| 初始化文件 | `fpga/ip/gpu_recip_p18.dat`，1024 行，每行 5 个 HEX 字符 |
| 复位 | 高有效，仅作用于读出通路；包装接常数 `1'b0` |

生成文件：

```sh
python3 tools/gpu/rom/gen_recip_p18.py fpga/ip/gpu_recip_p18.dat
```

地址 i 的内容为 `R(2^28 / (2049 + 2*i))`，R 为最近舍入、半值远离零。
P18 种子全部存放在此 ROM，没有低位补充表。
行为模型直接读取同一份入库文件 `fpga/ip/gpu_recip_p18.dat`，从仓库根目录启动仿真。
行为模型在读使能上升沿后给出对应数据，未使能时保持输出，不复位存储或输出数据。

## 端口

| 端口 | 方向 | 位宽 | 包装连接 |
|---|---|---|---|
| `clk` | in | 1 | `clk_i` |
| `clk_en` | in | 1 | `en_i` |
| `rst` | in | 1 | `1'b0` |
| `addr` | in | 10 | `addr_i` |
| `rd_data` | out | 18 | `rd_data_o` |

按 `ip_rom_boot` 同类 ROM 配置创建，生成后的实际端口和读延迟须在 Windows 任务回传确认。
