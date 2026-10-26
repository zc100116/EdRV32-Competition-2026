# FPGA IP 清单

所有 IP 由用户在 Windows 端用 PDS IP Compiler 按各自的创建说明手动生成，生成文件留在本地 FPGA 工程中，不入库（CLAUDE.md 第 8 节）。

| IP 模块名 | 类型 | 规格 | 包装模块 | 使用者 | 创建说明 | 状态 |
|---|---|---|---|---|---|---|
| `ip_ram_icache_tag` | DRM 简单双口 RAM | 512 × 20（用 128 项） | `edrv32_ram_icache_tag` | I$ ×2 | [ip_ram_icache_tag.md](ip_ram_icache_tag.md) | 已生成（20261025-01） |
| `ip_ram_icache_data` | DRM 简单双口 RAM | 512 × 64 | `edrv32_ram_icache_data` | I$ ×2 | [ip_ram_icache_data.md](ip_ram_icache_data.md) | 已生成（20261025-01） |
| `ip_ram_dcache_tag` | DRM 简单双口 RAM | 512 × 20（用 128 项） | `edrv32_ram_dcache_tag` | D$ ×2 | [ip_ram_dcache_tag.md](ip_ram_dcache_tag.md) | 已生成（20261025-01） |
| `ip_ram_dcache_data` | DRM 简单双口 RAM，字节写使能 | 512 × 64 | `edrv32_ram_dcache_data` | D$ ×2 | [ip_ram_dcache_data.md](ip_ram_dcache_data.md) | 已生成（20261025-01） |
| `ip_mul_s33x33` | APM 乘法器 | 33 × 33 有符号，2 级 | `edrv32_mul_s33x33` | CPU | [ip_mul_s33x33.md](ip_mul_s33x33.md) | 已生成（20261025-01） |
| `ip_rom_boot` | DRM ROM，带初始化 | 2048 × 64 | `edrv32_rom_boot` | Boot ROM | [ip_rom_boot.md](ip_rom_boot.md) | 已生成（20261025-01） |
| `ip_ram_sram` | DRM 单口 RAM，字节写使能，可初始化 | 32768 × 64 | `edrv32_ram_sram` | SRAM | [ip_ram_sram.md](ip_ram_sram.md) | 已生成（20261025-01） |

PLL、DDR3 控制器等板级 IP 在板级阶段补充。

## 通用约定

- 读延迟一律为 1 个周期（不勾选输出寄存器），读使能为 0 时读数据保持。PDS 生成的读使能端口名为 `clk_en` / `rd_clk_en`。
- PDS 存储和乘法 IP 都强制带高有效复位端口，只作用于读出或流水通路，不清存储阵列；包装模块一律接 `1'b0`（CLAUDE.md 5.2：数据通路不复位）。
- 18K DRM 的地址最少 9 位（512 深），更浅的存储按 512 深生成，包装模块高位补 0。
- 简单双口 RAM 的写端口和读端口同一时钟；同一时钟沿对同一地址读写时，读端口得到旧数据。
- 端口名以 PDS 实际生成的为准；每个说明末尾列出了包装模块期望的端口名，生成后请回传实际端口列表，不一致由协调者修改包装模块。
- 第一次生成时建议先只生成 `ip_ram_icache_tag` 和 `ip_rom_boot` 两个，确认端口和选项后再生成其余的。

## 初始化文件

`sw/` 构建得到 `build/sw/<程序>/rom.hex`、`sram.hex`（每行一个 64 位字，十六进制，与仿真后门加载使用的文件相同）。PDS 生成器提供的 HEX 示例为每行一个 64 位字（16 个十六进制数字），尚未实测加载外部文件；确认后由 `tools/` 中的转换脚本从同一个 hex 文件生成，保证 FPGA 与仿真内容一致。
