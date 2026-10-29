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
| `ip_ram_sram` | DRM 单口 RAM，字节写使能，可初始化 | 8192 × 64 | `edrv32_ram_sram` | SRAM | [ip_ram_sram.md](ip_ram_sram.md) | 已生成（8192 深，20261027-02） |
| `ip_ram_npu_line` | DRM 简单双口 RAM，输出寄存 | 1024 × 256 | `edrv32_ram_npu_line` | NPU 行缓存 ×2 | [ip_ram_npu_line.md](ip_ram_npu_line.md) | 已生成（20261027-02） |
| `ip_ram_npu_weight` | DRM 简单双口 RAM，输出寄存 | 512 × 256 | `edrv32_ram_npu_weight` | NPU 常驻权重 ×24 | [ip_ram_npu_weight.md](ip_ram_npu_weight.md) | 已生成（20261027-02） |
| `ip_ram_npu_quant` | DRM 简单双口 RAM，输出寄存 | 512 × 64（用 32 项） | `edrv32_ram_npu_quant` | NPU 量化参数 ×8 | [ip_ram_npu_quant.md](ip_ram_npu_quant.md) | 已生成（20261027-02） |
| `ip_ram_npu_lut` | DRM 简单双口 RAM，输出寄存 | 4096 × 8（用 2048 项） | `edrv32_ram_npu_lut` | NPU 激活表 ×16 | [ip_ram_npu_lut.md](ip_ram_npu_lut.md) | 已生成（20261027-02） |
| `ip_ram_npu_residual` | DRM 简单双口 RAM，输出寄存 | 512 × 256（用 32 项） | `edrv32_ram_npu_residual` | NPU 残差缓冲 ×1 | [ip_ram_npu_residual.md](ip_ram_npu_residual.md) | 已生成（20261027-02） |
| `ip_ram_npu_result` | DRM 简单双口 RAM，输出寄存 | 512 × 512（用 32 项） | `edrv32_ram_npu_result` | NPU 结果环 ×1 | [ip_ram_npu_result.md](ip_ram_npu_result.md) | 已生成（20261027-02） |
| `ip_ram_npu_scratch` | DRM 简单双口 RAM | 512 × 256 | `edrv32_ram_npu_scratch` | NPU 非卷积暂存 ×2 | [ip_ram_npu_scratch.md](ip_ram_npu_scratch.md) | 已生成（20261027-02） |
| （原语 `GTP_APM_E2`） | APM SIMD 两路 INT8 乘法，不经 IP Compiler | 2 × (8 × 8) 有符号，2 级 | `edrv32_mul_npu_int8_pair` | NPU MAC 阵列 ×256 | [ip_mul_npu_int8_pair.md](ip_mul_npu_int8_pair.md) | 无需生成；ModelSim 检查通过（20261027-02） |
| `ip_mul_npu_quant_low` | APM 乘法器 | 18 × 16 有符号，2 级 | `edrv32_mul_npu_quant_low` | NPU 量化 ×16 | [ip_mul_npu_quant_low.md](ip_mul_npu_quant_low.md) | 已生成（20261027-02） |
| `ip_mul_npu_quant_high` | APM 乘法器 | 16 × 16 有符号，2 级 | `edrv32_mul_npu_quant_high` | NPU 量化 ×16 | [ip_mul_npu_quant_high.md](ip_mul_npu_quant_high.md) | 已生成（20261027-02） |
| `ip_ram_vin_wfifo` | DRM 简单双口 RAM | 512 × 288 | `edrv32_ram_vin_wfifo` | VIN 写 FIFO ×2、内存源输入缓冲 ×1 | [ip_ram_vin_wfifo.md](ip_ram_vin_wfifo.md) | 已生成（20261028-04） |
| `ip_ram_disp_scan` | DRM 简单双口 RAM，读写独立时钟 | 512 × 256 | `edrv32_ram_disp_scan` | DISP 扫描 FIFO ×1（B3 起 ×2：L0、L1，disp-spec v0.3） | [ip_ram_disp_scan.md](ip_ram_disp_scan.md) | 已生成（20261028-04） |
| `ip_ram_pix_line` | DRM 简单双口 RAM | 1024 × 48 | `edrv32_ram_pix_line` | PIX 3×3 行缓存 ×4 | [ip_ram_pix_line.md](ip_ram_pix_line.md) | 已生成（20261028-04） |
| `ip_ram_geo_src` | DRM 简单双口 RAM，读写位宽不同 | 写 256 × 128 / 读 2048 × 16 | `edrv32_ram_geo_src` | GEO 源缓冲 ×8 | [ip_ram_geo_src.md](ip_ram_geo_src.md) | 已生成（20261028-04） |
| `ip_ram_eth_buf` | DRM 简单双口 RAM | 1024 × 32 | `edrv32_ram_eth_buf` | ETH 接收、发送缓冲 ×2 | [ip_ram_eth_buf.md](ip_ram_eth_buf.md) | 已生成（20261028-04） |
| `ip_ram_eth_fifo` | DRM 简单双口 RAM，独立时钟 | 512 × 10 | `edrv32_ram_eth_fifo` | ETH 接收、发送异步 FIFO ×2 | [ip_ram_eth_fifo.md](ip_ram_eth_fifo.md) | 已生成（20261028-04） |
| `ip_ram_rnd_line` | DRM 简单双口 RAM，字节写使能 | 512 × 256 | `edrv32_ram_rnd_line` | RND 行缓冲 ×5 | [ip_ram_rnd_line.md](ip_ram_rnd_line.md) | 待生成（B3） |
| `ip_ram_rnd_palette` | DRM 简单双口 RAM | 512 × 32（用 256 项） | `edrv32_ram_rnd_palette` | RND 调色板 ×2 | [ip_ram_rnd_palette.md](ip_ram_rnd_palette.md) | 待生成（B3） |

| `ip_pll_sys` | PLL（板级） | 27 MHz → clk_sys 100 MHz | 无（板级顶层直接例化，仿真用 `verif/models/ip_pll_sys.sv`） | B1 板级顶层 | [ip_pll_sys.md](ip_pll_sys.md) | 待生成 |

DDR3 控制器、HDMI/摄像头相关 PLL 在 B2 补充。

## 通用约定

- 读延迟默认 1 个周期（不勾选输出寄存器），读使能为 0 时读数据保持。例外：NPU 数据通路的 RAM（`ip_ram_npu_*`，scratch 除外）勾选输出寄存器，读延迟 2 个周期（NPU 规格 5.4 时序设计）。PDS 生成的读使能端口名为 `clk_en` / `rd_clk_en`。
- PDS 存储和乘法 IP 都强制带高有效复位端口，只作用于读出或流水通路，不清存储阵列；包装模块一律接 `1'b0`（CLAUDE.md 5.2：数据通路不复位）。
- 18K DRM 的地址最少 9 位（512 深），更浅的存储按 512 深生成，包装模块高位补 0。
- 简单双口 RAM 的写端口和读端口同一时钟；同一时钟沿对同一地址读写时，读端口得到旧数据（CPU 侧 IP 的定向检查结果）。NPU 的 `ip_ram_npu_*` 没有冲突模式选项，同址读写的读出值不确定，使用方不得依赖（见各创建说明）。
- 端口名以 PDS 实际生成的为准；每个说明末尾列出了包装模块期望的端口名，生成后请回传实际端口列表，不一致由协调者修改包装模块。
- 第一次生成时建议先只生成 `ip_ram_icache_tag` 和 `ip_rom_boot` 两个，确认端口和选项后再生成其余的。

## 初始化文件

`make -C sw PROGRAM=bootloader` 与 `PROGRAM=monitor` 输出的
`build/sw/<程序>/rom.hex`、`sram.hex` 实际是**字节镜像**：每个 token 一个字节，
`@` 后为区内字节地址（见 `tools/elf2mem.py`），不能直接选进 64 位 DRM IP。

```sh
make -C sw PROGRAM=bootloader
make -C sw PROGRAM=monitor
python3 tools/fpga/mem_init.py build/sw/bootloader/rom.hex build/sw/monitor/sram.hex
```

转换器按小端把连续 8 字节打包为 64 位字（低地址字节位于最低 8 位），从地址 0
逐行递增写出纯 HEX，无 `@` 地址、注释、前缀或分隔符，每行 16 个十六进制字符。
稀疏镜像中的空洞和末尾均补零，ROM 固定 2048 行，SRAM 固定 8192 行。
同一文件可直接用于存储包装模块的 `$readmemh`，板级仿真共用此打包函数。

在 IP Compiler 中使能初始化（`INIT_EN=true`），选择 HEX（`INIT_FORMAT=HEX`）：

| IP | 初始化文件（相对于仓库） |
|---|---|
| `ip_rom_boot` | `build/fpga/ip_rom_boot.dat` |
| `ip_ram_sram` | `build/fpga/ip_ram_sram.dat` |

格式依据为厂商只读 demo 根目录
`SOC系统设计/doc/fpga/pago_200/2_Demo/2_6_ram_rom_fifo/2_6_ram_rom_fifo/3_6_ram_rom_fifo/`：

- `rom_test/rom_test/ipcore/rom_test/init_param_hex_exmp.dat` 注释明示 64 bit 数据、
  10 bit 地址，“横向表示数据，纵向表示地址”，正文 1024 行、每行 16 个 HEX 字符；
  同目录 `init_param_bin_exmp.dat` 每行 64 个二进制字符，也是 1024 行。
- `rom_test/rom_test/ipcore/rom_test/rom_test.idf` 实际选择 `INIT_EN=true`、
  `INIT_FORMAT=HEX`、`DATA_WIDTH=64`、`ADDR_WIDTH=10`，其 `INIT_FILE` 指向
  `rom_test/rom_test/ipcore/init_param_hex_exmp.dat`。此已选文件去掉注释，前 3 行为
  `ffffffffffffffff`、`ffffffffffffff22`、`ffffffffffffff33`。
- `ram_test/ram_test/ipcore/ram_test/ram_test.idf` 有相同的 `INIT_FILE`、
  `INIT_FORMAT` 和 `INIT_EN` 选项（demo RAM 未使能初始化）。

示例总是填满深度，未证明短文件尾部的处理方式；本工具因此输出完整深度，避免依赖
未定义的尾部内容。HEX 的行顺序按地址 0 起递增使用；Windows B1 任务卡需确认 IP
Compiler 接受这两份文件、ROM 最初几条指令和 SRAM 首字正确，并通过真实启动 logo
与监控菜单验证。Linux 没有执行 PDS 初始化导入。
