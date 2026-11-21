# ip_lutram_cpu_tournament

| 项 | 内容 |
|---|---|
| IP 类型 | IP Compiler → Memory → 分布式 RAM（Distributed RAM）→ 简单双口 RAM（Simple Dual Port），带初始化文件 |
| 模块名 | `ip_lutram_cpu_tournament` |
| 包装模块 | `edrv32_ram_cpu_local_direction / edrv32_ram_cpu_chooser`（`rtl/tech/`） |
| 使用者 | CPU tournament：局部方向 ×3；选择器 ×8（查询/更新各四 bank） |
| 依据 | cpu-spec v0.18 4.4；CLAUDE.md 8 |
| 器件 | PG2L200H，速度等级以工程为准 |
| 状态 | 待生成（CPU v0.18） |

## 选项

| 选项 | 取值 |
|---|---|
| 实现资源 | 分布式 RAM，不选 DRM |
| 端口模式 | 简单双口：独立写地址、读地址，同宽读写 |
| 数据位宽 | 写端口和读端口都为 2 |
| 深度 | 1024（地址 10 位） |
| 写入方式 | 同步写；单一时钟 clk_sys，上升沿，写使能有效时写整字 |
| 字节写使能 | 不勾选 |
| 读出方式 | 组合读；不注册读地址，不选读时钟使能 |
| 输出寄存器 | 不勾选；读延迟 0 拍 |
| 复位 | 不复位内容或输出；生成的 `rst` 端口由包装接 1'b0 |
| 初始化文件 | 使能，HEX 格式，选择 `ip_lutram_cpu_tournament.dat`：1024 行，每行 `1` |

初始化文件生成（Windows 或 Linux 均可）：

```sh
python -c "open('ip_lutram_cpu_tournament.dat','w').write('1\n' * 1024)"
```

如果 PDS 的分布式 RAM 不提供初始化文件选项，停止生成并回报，不要改用复位清零或其他初值。

## 期望端口

| 端口 | 方向 | 位宽 |
|---|---|---|
| `wr_clk`、`rd_clk` | in | 1（包装都接 clk_sys） |
| `rst` | in | 1（包装接 1'b0） |
| `wr_en` | in | 1 |
| `wr_addr`、`rd_addr` | in | 10 |
| `wr_data` | in | 2 |
| `rd_data` | out | 2（组合输出） |

## 时序

同址写读：写沿之前读出旧值，写沿之后读出新值。所有读副本共享写端口，内容始终一致。
选择器逻辑深度为 4096，地址 [11:10] 选择四个 1024 深 bank；每个读副本的四 bank 都复用此 IP 和初始化文件。局部方向为单 bank。

## 生成后需要回传的信息

实际模块名、端口、资源（所有副本合计 LUTRAM 数）、初始化选项截图。端口名不一致时只改包装模块 FPGA 分支的连接，并回报。
