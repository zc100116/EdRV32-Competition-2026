# FPGA IP 清单

所有 IP 由用户在 Windows 端用 PDS IP Compiler 按各自的创建说明手动生成，生成文件留在本地 FPGA 工程中，不入库（CLAUDE.md 第 8 节）。

| IP 模块名 | 类型 | 规格 | 包装模块 | 使用者 | 创建说明 | 状态 |
|---|---|---|---|---|---|---|
| `ip_ram_icache_tag` | DRM 简单双口 RAM | 512 × 18 | `edrv32_ram_icache_tag` | I$ ×2 | [ip_ram_icache_tag.md](ip_ram_icache_tag.md) | 32 KiB（用户 2026-10-31 采用），卡 21 重新生成（模块名不变） |
| `ip_ram_icache_data` | DRM 简单双口 RAM | 2048 × 64 | `edrv32_ram_icache_data` | I$ ×2 | [ip_ram_icache_data.md](ip_ram_icache_data.md) | 32 KiB（用户 2026-10-31 采用），卡 21 重新生成（模块名不变） |
| `ip_ram_dcache_tag` | DRM 简单双口 RAM | 512 × 18 | `edrv32_ram_dcache_tag` | D$ ×2 | [ip_ram_dcache_tag.md](ip_ram_dcache_tag.md) | 需重新生成（D$ 32 KiB） |
| `ip_ram_dcache_data` | DRM 简单双口 RAM，字节写使能 | 2048 × 64 | `edrv32_ram_dcache_data` | D$ ×2 | [ip_ram_dcache_data.md](ip_ram_dcache_data.md) | 需重新生成（D$ 32 KiB） |
| `ip_mul_s33x33` | APM 乘法器 | 33 × 33 有符号，2 级 | `edrv32_mul_s33x33` | CPU | [ip_mul_s33x33.md](ip_mul_s33x33.md) | 已生成（20261025-01） |
| `ip_rom_boot` | DRM ROM，带初始化 | 2048 × 64 | `edrv32_rom_boot` | Boot ROM | [ip_rom_boot.md](ip_rom_boot.md) | 已生成（20261025-01） |
| `ip_ram_sram` | DRM 单口 RAM，字节写使能，可初始化 | 8192 × 64 | `edrv32_ram_sram` | SRAM | [ip_ram_sram.md](ip_ram_sram.md) | 已生成（8192 深，20261027-02） |
| `ip_ram_npu_line` | DRM 简单双口 RAM，输出寄存 | 1024 × 256 | `edrv32_ram_npu_line` | NPU 行缓存 ×2 | [ip_ram_npu_line.md](ip_ram_npu_line.md) | 已生成（20261027-02） |
| `ip_ram_npu_weight` | DRM 简单双口 RAM，输出寄存 | 512 × 256 | `edrv32_ram_npu_weight` | NPU 常驻权重 ×24 | [ip_ram_npu_weight.md](ip_ram_npu_weight.md) | 已生成（20261027-02） |
| `ip_lutram_npu_quant` | 分布式 RAM，组合读 | 32 × 64 | `edrv32_ram_npu_quant` | NPU 量化参数 ×8 | [ip_lutram_npu_quant.md](ip_lutram_npu_quant.md) | 已采用（用户 2026-10-31），待卡 21 生成 |
| `ip_ram_npu_lut` | DRM 简单双口 RAM，输出寄存 | 2048 × 8 | `edrv32_ram_npu_lut` | NPU 激活表 ×16 | [ip_ram_npu_lut.md](ip_ram_npu_lut.md) | 已采用（用户 2026-10-31），待卡 21 生成 |
| `ip_lutram_npu_residual` | 分布式 RAM，组合读 | 32 × 256 | `edrv32_ram_npu_residual` | NPU 残差缓冲 ×1 | [ip_lutram_npu_residual.md](ip_lutram_npu_residual.md) | 已采用（用户 2026-10-31），待卡 21 生成 |
| `ip_lutram_npu_result` | 分布式 RAM，组合读 | 32 × 512 | `edrv32_ram_npu_result` | NPU 结果环 ×1 | [ip_lutram_npu_result.md](ip_lutram_npu_result.md) | 已采用（用户 2026-10-31），待卡 21 生成 |
| `ip_ram_npu_scratch` | DRM 简单双口 RAM | 512 × 256 | `edrv32_ram_npu_scratch` | NPU 非卷积暂存 ×2 | [ip_ram_npu_scratch.md](ip_ram_npu_scratch.md) | 已生成（20261027-02） |
| （原语 `GTP_APM_E2`） | APM SIMD 两路 INT8 级联乘加，不经 IP Compiler | 2 × INT8 乘法 + 独立 24 位后加，单元 3 沿、八级链 10 沿 | `edrv32_mac_npu_int8_head` / `edrv32_mac_npu_int8_chain` | NPU MAC 阵列 head ×32 / chain ×224 | [ip_mac_npu_int8_chain.md](ip_mac_npu_int8_chain.md) | 无需生成；EQ-01 厂商模型对比 PASS |
| `ip_mul_npu_quant_low` | APM 乘法器 | 18 × 16 有符号，2 级 | `edrv32_mul_npu_quant_low` | NPU 量化 ×16 | [ip_mul_npu_quant_low.md](ip_mul_npu_quant_low.md) | 已生成（20261027-02） |
| `ip_mul_npu_quant_high` | APM 乘法器 | 16 × 16 有符号，2 级 | `edrv32_mul_npu_quant_high` | NPU 量化 ×16 | [ip_mul_npu_quant_high.md](ip_mul_npu_quant_high.md) | 已生成（20261027-02） |
| `ip_ram_mem_xbar_r` | DRM 简单双口 RAM | 512 × 259（用 128 项） | `edrv32_ram_mem_xbar_r` | mem_xbar 共享读缓冲 | [ip_ram_mem_xbar_r.md](ip_ram_mem_xbar_r.md) | B2 待生成 |
| `ip_lutram_mem_xbar_w` | 分布式 RAM，组合读 | 16 × 288 | `edrv32_ram_mem_xbar_w` | mem_xbar 写缓冲 ×6 | [ip_lutram_mem_xbar_w.md](ip_lutram_mem_xbar_w.md) | 已采用（用户 2026-10-31），待卡 21 生成 |
| `ip_ram_vin_wfifo` | DRM 简单双口 RAM | 512 × 288 | `edrv32_ram_vin_wfifo` | VIN 写 FIFO ×2、内存源输入缓冲 ×1 | [ip_ram_vin_wfifo.md](ip_ram_vin_wfifo.md) | 已生成（20261028-04） |
| `ip_ram_disp_scan` | DRM 简单双口 RAM，读写独立时钟 | 512 × 256 | `edrv32_ram_disp_scan` | DISP 扫描 FIFO ×1（B3 起 ×2：L0、L1，disp-spec v0.3） | [ip_ram_disp_scan.md](ip_ram_disp_scan.md) | 已生成（20261028-04） |
| `ip_ram_pix_line` | DRM 简单双口 RAM | 1024 × 48 | `edrv32_ram_pix_line` | PIX 3×3 行缓存 ×4 | [ip_ram_pix_line.md](ip_ram_pix_line.md) | 已生成（20261028-04） |
| `ip_ram_geo_src` | DRM 简单双口 RAM，读写位宽不同 | 写 256 × 128 / 读 2048 × 16 | `edrv32_ram_geo_src` | GEO 源缓冲 ×8 | [ip_ram_geo_src.md](ip_ram_geo_src.md) | 已生成（20261028-04） |
| `ip_ram_eth_buf` | DRM 简单双口 RAM | 1024 × 32 | `edrv32_ram_eth_buf` | ETH 接收、发送缓冲 ×2 | [ip_ram_eth_buf.md](ip_ram_eth_buf.md) | 已生成（20261028-04） |
| `ip_ram_eth_fifo` | DRM 简单双口 RAM，独立时钟 | 512 × 10 | `edrv32_ram_eth_fifo` | ETH 接收、发送异步 FIFO ×2 | [ip_ram_eth_fifo.md](ip_ram_eth_fifo.md) | 已生成（20261028-04） |
| `ip_ram_rnd_line` | DRM 简单双口 RAM，字节写使能 | 512 × 256 | `edrv32_ram_rnd_line` | RND 行缓冲 ×5 | [ip_ram_rnd_line.md](ip_ram_rnd_line.md) | 待生成（B3） |
| `ip_ram_rnd_palette` | DRM 简单双口 RAM | 512 × 32（用 256 项） | `edrv32_ram_rnd_palette` | RND 调色板 ×2 | [ip_ram_rnd_palette.md](ip_ram_rnd_palette.md) | 待生成（B3） |
| `ip_pll_sys` | PLL（板级） | 27 MHz → clk_sys 100 MHz | 无（板级顶层直接例化，仿真用 `verif/models/ip_pll_sys.sv`） | B1/B2 板级顶层 | [ip_pll_sys.md](ip_pll_sys.md) | B1 已生成 |
| `ip_ddr3` | DDR3 Controller + PHY | x32、1000 Mbps，core_clk 125 MHz、用户口 256 位 | 无（板级直接例化） | B2 DDR 及 clk_mem | [ip_ddr3.md](ip_ddr3.md) | B2 待生成 |
| `ip_pll_npu` | PLL | 27 → 150 MHz | 无（板级直接例化） | B2 NPU | [ip_pll_npu.md](ip_pll_npu.md) | B2 待生成 |
| `ip_pll_video` | PLL | 27 → 74.25 / 371.25 MHz，同相 | 无（板级直接例化） | B2 DISP / TMDS | [ip_pll_video.md](ip_pll_video.md) | B2 待生成 |
| `ip_pll_eth` | PLL | 125 → 125 MHz，30° | 无（板级直接例化） | B2 RGMII RX/TX | [ip_pll_eth.md](ip_pll_eth.md) | B2 待生成 |

B2 保留 `ip_pll_sys` 的 B1 配置，新增上表四个 IP；不要把视频输出合入系统 PLL，
74.25/371.25 MHz 必须同 PLL 同相。摄像头模块自带时钟，板级不产生 XCLK。
TMDS 及 RGMII 使用器件原语，无需另生成 GUI IP：
`GTP_OSERDES_E2`、`GTP_OUTBUFDS`、`GTP_IDDR_E1`、`GTP_ODDR_E1`、
`GTP_IODELAY_E2`、`GTP_INBUF`、`GTP_OUTBUF`、`GTP_CLKBUFG`、`GTP_INBUFDS`。
原语配置固定在 `fpga/rtl/edrv32_fpga_tmds.v` 和 `edrv32_fpga_rgmii.v`；
SERDES 数据寄存器不使用本地复位，持续发送 SoC 的 TMDS 符号（CLAUDE 5.2）。

浅存储改用分布式 RAM（设计记录 `docs/design/2026-10-31-drm-lutram.md` 方案 B，用户 2026-10-31 采用）：
四种浅存储改用分布式 RAM，激活表 DRM 改为 2048 深，由卡 21 生成。原 DRM 版 `ip_ram_npu_result`、
`ip_ram_npu_quant`、`ip_ram_npu_residual`、`ip_ram_mem_xbar_w` 不再使用，工程中应移除。
分布式 RAM 的读使能、保持和 1/2 拍延迟由包装模块寄存器实现，IP 本身为组合读。

### B2 Windows 用户 IP 生成顺序

1. 新建独立 B2 工程（PG2L200H-6/FBB676），保留 B1 工程供对照。
2. 按 `ip_pll_sys.md` 复用或生成 100 MHz PLL；按新说明生成 NPU、video、ETH PLL。
3. 按 `ip_ddr3.md` 导入 `ip_ddr3.idf` 生成 DDR3（导入失败时用 GUI 步骤），确认 `ref_clk`、`core_clk` 及全部用户口/物理端口。
4. 在 B2 工程加入 soc.f 所用存储/乘法 IP（见下表），ROM/SRAM 用 B2 BIOS/监控
   程序重新生成的初始化文件。尤其 `ip_ram_mem_xbar_r`/`ip_lutram_mem_xbar_w`
   是 B2 DDR fabric 所需，不能只复制 B1 的七种 IP。
5. 执行 `fpga/scripts/import_board_b2_top.tcl`，随后综合、实现和上板；
   在 PDS 确认时钟约束命中真实 IP 层级，回传实际 IP 版本/端口、频率及参数截图。
   本次没有板级仿真或 Windows PDS 运行结果。

B2 soc.f 的 24 种生成 IP（不含上面 5 种板级 IP，APM 原语另计）：

- CPU/SYS：`ip_ram_icache_tag`、`ip_ram_icache_data`、`ip_ram_dcache_tag`、
  `ip_ram_dcache_data`、`ip_mul_s33x33`、`ip_rom_boot`、`ip_ram_sram`。
- MEM：`ip_ram_mem_xbar_r`、`ip_lutram_mem_xbar_w`。
- VIN/PIX/GEO/DISP：`ip_ram_vin_wfifo`、`ip_ram_pix_line`、`ip_ram_geo_src`、
  `ip_ram_disp_scan`。
- NPU：`ip_ram_npu_line`、`ip_ram_npu_weight`、`ip_lutram_npu_quant`、`ip_ram_npu_lut`、
  `ip_lutram_npu_residual`、`ip_lutram_npu_result`、`ip_ram_npu_scratch`、
  `ip_mul_npu_quant_low`、`ip_mul_npu_quant_high`。
- ETH：`ip_ram_eth_buf`、`ip_ram_eth_fifo`。

RND 的两种 RAM 不在 B2 soc.f 依赖内。

## 通用约定

- DRM 读延迟默认 1 个周期（不勾选输出寄存器），读使能为 0 时读数据保持。例外：NPU 数据通路的 RAM（`ip_ram_npu_*`，scratch 除外）勾选输出寄存器，读延迟 2 个周期（NPU 规格 5.4 时序设计）。PDS 生成的读使能端口名为 `clk_en` / `rd_clk_en`。
- 现有 PDS DRM 和乘法 IP 都强制带高有效复位端口，只作用于读出或流水通路，不清存储阵列；包装模块一律接 `1'b0`（CLAUDE.md 5.2：数据通路不复位）。
- 18K DRM 的地址最少 9 位（512 深），更浅的存储按 512 深生成，包装模块高位补 0。
- DRM 简单双口 RAM 的写端口和读端口同一时钟；同一时钟沿对同一地址读写时，读端口得到旧数据（CPU 侧 IP 的定向检查结果）。NPU 的 `ip_ram_npu_*` 没有冲突模式选项，同址读写的读出值不确定，使用方不得依赖（见各创建说明）。
- 分布式 RAM 只有同步写时钟，组合读；包装模块沿前采样读值，同址读写返回旧值。NPU 两级读寄存器第一级受读使能控制、第二级一直使能；mem_xbar 写缓冲一级受读使能控制。
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
