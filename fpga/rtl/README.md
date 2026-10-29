板级顶层和板级适配 RTL（PLL/DDR IP 的例化、DDR 适配器、TMDS 串化、RGMII IO）
`edrv32_fpga_media_top.v`：VIN/DISP/PIX/GEO/ETH 合并 PDS 测量顶层，分域串行激励和寄存 XOR 观察，不上板。

`edrv32_fpga_board_b1_top.v`：B1 上板顶层，27 MHz PLL → 100 MHz CPU/cache/系统子系统，UART、启动按键与 LED。


## B2 完整 SoC 板级顶层

`edrv32_fpga_board_b2_top.v` 直接例化 `edrv32_soc_top`、`ip_ddr3` 和板级 PLL，
经 `edrv32_fpga_ddr_adapter` 接 DDR 用户接口。`core_clk` 唯一驱动 clk_mem，
`ddr_init_done` 接 mem_ready；按键及 sys/npu/video PLL lock 合成异步 SoC 复位。
DDR resetn 使用相同板级复位，不能使用等 mem_ready 后才释放的 SoC 复位。
PHY 复位仅由 SoC PHY_CTRL 驱动，不能用 Ethernet PLL lock 阻塞全局复位。

HDMI 由 FPGA 直出 TMDS：`edrv32_fpga_tmds.v` 的每对输出使用两个级联
`GTP_OSERDES_E2`（DDR10TO1）和一个 `GTP_OUTBUFDS`，时钟对也串化固定符号；
无 HDMI 发送芯片初始化。依据 `2_10_hdmi_loop/source/outputserdes.v` 和
`4_12_HDMI_IN_DDR3_HDMI_OUT/source/rtl/HDMI_IN_DDR3_OUT_top.v`。
`edrv32_fpga_rgmii.v` 按 Ethernet demo 使用 PLL 125 MHz/30°、RX 247 步和 TXC
100 步 IODELAY（每步 10 ps）；两路 MAC 时钟共享该时钟，无新增数据跨域。
所有协议 CDC 仍在 SoC（5.2 X1–X10），串化相关时钟保持同步约束。

I2C 和 MDIO 是双向引脚，因仓库风格检查要求 inout 使用 `_o` 后缀而这样命名；
方向以 Verilog `inout` 和约束 INOUT 为准。LED 使用 GPIO[8:4]；KEY 使用 GPIO[3:0]。
摄像头 GPIO[13]/[15] 分别接 T22/AC26；GPIO[12]/[14] 的 PWDN **不引出**，
SoC 输出连显式 unused 信号。协调者确认（2026-10-29）：PWDN 由摄像头模块固定，
厂商 `5_1` 的 `camera_pwnd()` 留空，已上板的
`legacy/rtl/vision/camera/edrv32_ov5640_stereo_init.v` 也只引出两路 reset。
用户将核对实物，有变更再改引脚。没有板级仿真；Linux 仅 lint，功能由 Windows 上板验收。

### 引脚核对表

所有向量逐位列出，覆盖全部物理顶层端口。来源文件相对于厂商 `2_Demo/`：
`ov5640.fdc` = `5_1 双目摄像头例程/ov5640_200k/ov5640.fdc`；
`ethernet_test.fdc` = `2_11_ethernet_test/2_11_ethernet_test/ethernet_test.fdc`；
UART/时钟来源 `2_8_uart_test/2_8_uart_test/uart_test.fdc`；
复位来源 `2_7_key_led_test/2_7_key_led_test/source/key_led_test.fdc`。
XLSX 为 `3_Hardware/FPGA管脚分配/mini-base管脚映射.xlsx`，行号从 1 开始。
DDR IO 标准按双目例程的 HSTL15_I/HSTL15D_I 保留；B2 FDC 同时包含厂商 DDR PHY 时钟和内部布局约束。
摄像头 pclk 按厂商最严 100 MHz 约束（10 ns），实际由 OV5640 配置决定。

| 顶层端口（逐位） | FPGA 引脚 | IO 标准 | 来源 |
|---|---|---|---|
| `clk_i` | D18 | LVCMOS33 | 2_8_uart_test/uart_test.fdc: clk |
| `rst_n_i` | C22 | LVCMOS33 | 2_7_key_led_test/source/key_led_test.fdc: rstn |
| `ddr_ref_clk_p_i` | N3 | HSTL15D_I | ov5640.fdc: clk_p |
| `ddr_ref_clk_n_i` | N2 | HSTL15D_I | ov5640.fdc: clk_n |
| `uart_rx_i` | B24 | LVCMOS33 | 2_8_uart_test/uart_test.fdc: uart_rx |
| `uart_tx_o` | C24 | LVCMOS33 | 2_8_uart_test/uart_test.fdc: uart_tx |
| `key_n_i[0]` | C23 | LVCMOS33 | mini-base管脚映射.xlsx sheet1 行101 USER_BUTTON1 |
| `key_n_i[1]` | B22 | LVCMOS33 | mini-base管脚映射.xlsx sheet1 行102 USER_BUTTON2 |
| `key_n_i[2]` | A22 | LVCMOS33 | mini-base管脚映射.xlsx sheet1 行103 USER_BUTTON3 |
| `key_n_i[3]` | B20 | LVCMOS33 | mini-base管脚映射.xlsx sheet1 行104 USER_BUTTON4 |
| `led_o[0]` | A20 | LVCMOS33 | mini-base管脚映射.xlsx sheet1 行105 USER_LED0 |
| `led_o[1]` | C18 | LVCMOS33 | mini-base管脚映射.xlsx sheet1 行109 USER_LED1 |
| `led_o[2]` | C19 | LVCMOS33 | mini-base管脚映射.xlsx sheet1 行107 USER_LED2 |
| `led_o[3]` | E18 | LVCMOS33 | mini-base管脚映射.xlsx sheet1 行109 USER_LED3 |
| `led_o[4]` | A17 | LVCMOS33 | mini-base管脚映射.xlsx sheet1 行110 USER_LED4 |
| `cam0_pclk_i` | L22 | LVCMOS33 | ov5640.fdc: camera_clk_0 |
| `cam1_pclk_i` | M21 | LVCMOS33 | ov5640.fdc: camera_clk_1 |
| `cam0_vsync_i` | L23 | LVCMOS33 | ov5640.fdc: camera_vsync_0 |
| `cam0_href_i` | T25 | LVCMOS33 | ov5640.fdc: camera_href_0 |
| `cam0_data_i[0]` | M24 | LVCMOS33 | ov5640.fdc: camera_data_0[0] |
| `cam0_data_i[1]` | R22 | LVCMOS33 | ov5640.fdc: camera_data_0[1] |
| `cam0_data_i[2]` | K26 | LVCMOS33 | ov5640.fdc: camera_data_0[2] |
| `cam0_data_i[3]` | K25 | LVCMOS33 | ov5640.fdc: camera_data_0[3] |
| `cam0_data_i[4]` | M25 | LVCMOS33 | ov5640.fdc: camera_data_0[4] |
| `cam0_data_i[5]` | N19 | LVCMOS33 | ov5640.fdc: camera_data_0[5] |
| `cam0_data_i[6]` | T24 | LVCMOS33 | ov5640.fdc: camera_data_0[6] |
| `cam0_data_i[7]` | R21 | LVCMOS33 | ov5640.fdc: camera_data_0[7] |
| `cam1_vsync_i` | U25 | LVCMOS33 | ov5640.fdc: camera_vsync_1 |
| `cam1_href_i` | U26 | LVCMOS33 | ov5640.fdc: camera_href_1 |
| `cam1_data_i[0]` | M22 | LVCMOS33 | ov5640.fdc: camera_data_1[0] |
| `cam1_data_i[1]` | R23 | LVCMOS33 | ov5640.fdc: camera_data_1[1] |
| `cam1_data_i[2]` | T23 | LVCMOS33 | ov5640.fdc: camera_data_1[2] |
| `cam1_data_i[3]` | AB24 | LVCMOS33 | ov5640.fdc: camera_data_1[3] |
| `cam1_data_i[4]` | P26 | LVCMOS33 | ov5640.fdc: camera_data_1[4] |
| `cam1_data_i[5]` | M26 | LVCMOS33 | ov5640.fdc: camera_data_1[5] |
| `cam1_data_i[6]` | AA24 | LVCMOS33 | ov5640.fdc: camera_data_1[6] |
| `cam1_data_i[7]` | AB25 | LVCMOS33 | ov5640.fdc: camera_data_1[7] |
| `cam0_rst_n_o` | T22 | LVCMOS33 | ov5640.fdc: cam_rst_0 |
| `cam1_rst_n_o` | AC26 | LVCMOS33 | ov5640.fdc: cam_rst_1 |
| `i2c0_scl_o[0]` | P19 | LVCMOS33 | ov5640.fdc: SCL_0 |
| `i2c0_scl_o[1]` | AC24 | LVCMOS33 | ov5640.fdc: SCL_1 |
| `i2c0_sda_o[0]` | R20 | LVCMOS33 | ov5640.fdc: SDA_0 |
| `i2c0_sda_o[1]` | Y25 | LVCMOS33 | ov5640.fdc: SDA_1 |
| `tmds_data_p_o[0]` | R25 | TMDS | ov5640.fdc: tmds_data_p[0] |
| `tmds_data_p_o[1]` | P23 | TMDS | ov5640.fdc: tmds_data_p[1] |
| `tmds_data_p_o[2]` | N23 | TMDS | ov5640.fdc: tmds_data_p[2] |
| `tmds_data_n_o[0]` | P25 | TMDS | ov5640.fdc: tmds_data_n[0] |
| `tmds_data_n_o[1]` | P24 | TMDS | ov5640.fdc: tmds_data_n[1] |
| `tmds_data_n_o[2]` | N24 | TMDS | ov5640.fdc: tmds_data_n[2] |
| `tmds_clk_p_o` | N21 | TMDS | ov5640.fdc: tmds_clk_p |
| `tmds_clk_n_o` | N22 | TMDS | ov5640.fdc: tmds_clk_n |
| `rgmii_rxc_i` | D19 | LVCMOS33 | ethernet_test.fdc: rgmii_rxc |
| `rgmii_rxd_i[0]` | D16 | LVCMOS33 | ethernet_test.fdc: rgmii_rxd[0] |
| `rgmii_rxd_i[1]` | E16 | LVCMOS33 | ethernet_test.fdc: rgmii_rxd[1] |
| `rgmii_rxd_i[2]` | A19 | LVCMOS33 | ethernet_test.fdc: rgmii_rxd[2] |
| `rgmii_rxd_i[3]` | B19 | LVCMOS33 | ethernet_test.fdc: rgmii_rxd[3] |
| `rgmii_rx_ctl_i` | H16 | LVCMOS33 | ethernet_test.fdc: rgmii_rx_ctl |
| `rgmii_txc_o` | G16 | LVCMOS33 | ethernet_test.fdc: rgmii_txc |
| `rgmii_txd_o[0]` | E20 | LVCMOS33 | ethernet_test.fdc: rgmii_txd[0] |
| `rgmii_txd_o[1]` | B21 | LVCMOS33 | ethernet_test.fdc: rgmii_txd[1] |
| `rgmii_txd_o[2]` | C21 | LVCMOS33 | ethernet_test.fdc: rgmii_txd[2] |
| `rgmii_txd_o[3]` | D21 | LVCMOS33 | ethernet_test.fdc: rgmii_txd[3] |
| `rgmii_tx_ctl_o` | D20 | LVCMOS33 | ethernet_test.fdc: rgmii_tx_ctl |
| `eth_mdc_o` | A25 | LVCMOS33 | mini-base管脚映射.xlsx sheet1 行101 PHY0_MDC: eth_mdc_o |
| `eth_mdio_o` | E21 | LVCMOS33 | mini-base管脚映射.xlsx sheet1 行102 PHY0_MDIO: eth_mdio_o |
| `eth_phy_rst_n_o` | G25 | LVCMOS33 | ethernet_test.fdc: phy_rstn |
| `mem_cs_n_o` | N4 | HSTL15_I | ov5640.fdc: mem_cs_n |
| `mem_rst_n_o` | H1 | HSTL15_I | ov5640.fdc: mem_rst_n |
| `mem_ck_o` | U6 | HSTL15D_I | ov5640.fdc: mem_ck |
| `mem_ck_n_o` | U5 | HSTL15D_I | ov5640.fdc: mem_ck_n |
| `mem_cke_o` | R1 | HSTL15_I | ov5640.fdc: mem_cke |
| `mem_ras_n_o` | P6 | HSTL15_I | ov5640.fdc: mem_ras_n |
| `mem_cas_n_o` | T7 | HSTL15_I | ov5640.fdc: mem_cas_n |
| `mem_we_n_o` | T8 | HSTL15_I | ov5640.fdc: mem_we_n |
| `mem_odt_o` | H2 | HSTL15_I | ov5640.fdc: mem_odt |
| `mem_a_o[0]` | J1 | HSTL15_I | ov5640.fdc: mem_a[0] |
| `mem_a_o[1]` | L3 | HSTL15_I | ov5640.fdc: mem_a[1] |
| `mem_a_o[2]` | L2 | HSTL15_I | ov5640.fdc: mem_a[2] |
| `mem_a_o[3]` | P3 | HSTL15_I | ov5640.fdc: mem_a[3] |
| `mem_a_o[4]` | T2 | HSTL15_I | ov5640.fdc: mem_a[4] |
| `mem_a_o[5]` | M1 | HSTL15_I | ov5640.fdc: mem_a[5] |
| `mem_a_o[6]` | U1 | HSTL15_I | ov5640.fdc: mem_a[6] |
| `mem_a_o[7]` | K1 | HSTL15_I | ov5640.fdc: mem_a[7] |
| `mem_a_o[8]` | U2 | HSTL15_I | ov5640.fdc: mem_a[8] |
| `mem_a_o[9]` | K2 | HSTL15_I | ov5640.fdc: mem_a[9] |
| `mem_a_o[10]` | T3 | HSTL15_I | ov5640.fdc: mem_a[10] |
| `mem_a_o[11]` | P1 | HSTL15_I | ov5640.fdc: mem_a[11] |
| `mem_a_o[12]` | T4 | HSTL15_I | ov5640.fdc: mem_a[12] |
| `mem_a_o[13]` | M2 | HSTL15_I | ov5640.fdc: mem_a[13] |
| `mem_a_o[14]` | N1 | HSTL15_I | ov5640.fdc: mem_a[14] |
| `mem_ba_o[0]` | P4 | HSTL15_I | ov5640.fdc: mem_ba[0] |
| `mem_ba_o[1]` | R2 | HSTL15_I | ov5640.fdc: mem_ba[1] |
| `mem_ba_o[2]` | T5 | HSTL15_I | ov5640.fdc: mem_ba[2] |
| `mem_dqs_o[0]` | J4 | HSTL15D_I | ov5640.fdc: mem_dqs[0] |
| `mem_dqs_o[1]` | H7 | HSTL15D_I | ov5640.fdc: mem_dqs[1] |
| `mem_dqs_o[2]` | B5 | HSTL15D_I | ov5640.fdc: mem_dqs[2] |
| `mem_dqs_o[3]` | C1 | HSTL15D_I | ov5640.fdc: mem_dqs[3] |
| `mem_dqs_n_o[0]` | H4 | HSTL15D_I | ov5640.fdc: mem_dqs_n[0] |
| `mem_dqs_n_o[1]` | G7 | HSTL15D_I | ov5640.fdc: mem_dqs_n[1] |
| `mem_dqs_n_o[2]` | A5 | HSTL15D_I | ov5640.fdc: mem_dqs_n[2] |
| `mem_dqs_n_o[3]` | B1 | HSTL15D_I | ov5640.fdc: mem_dqs_n[3] |
| `mem_dq_o[0]` | G5 | HSTL15_I | ov5640.fdc: mem_dq[0] |
| `mem_dq_o[1]` | J6 | HSTL15_I | ov5640.fdc: mem_dq[1] |
| `mem_dq_o[2]` | F5 | HSTL15_I | ov5640.fdc: mem_dq[2] |
| `mem_dq_o[3]` | L8 | HSTL15_I | ov5640.fdc: mem_dq[3] |
| `mem_dq_o[4]` | G4 | HSTL15_I | ov5640.fdc: mem_dq[4] |
| `mem_dq_o[5]` | K7 | HSTL15_I | ov5640.fdc: mem_dq[5] |
| `mem_dq_o[6]` | F4 | HSTL15_I | ov5640.fdc: mem_dq[6] |
| `mem_dq_o[7]` | J5 | HSTL15_I | ov5640.fdc: mem_dq[7] |
| `mem_dq_o[8]` | H6 | HSTL15_I | ov5640.fdc: mem_dq[8] |
| `mem_dq_o[9]` | F8 | HSTL15_I | ov5640.fdc: mem_dq[9] |
| `mem_dq_o[10]` | H8 | HSTL15_I | ov5640.fdc: mem_dq[10] |
| `mem_dq_o[11]` | D6 | HSTL15_I | ov5640.fdc: mem_dq[11] |
| `mem_dq_o[12]` | G8 | HSTL15_I | ov5640.fdc: mem_dq[12] |
| `mem_dq_o[13]` | E6 | HSTL15_I | ov5640.fdc: mem_dq[13] |
| `mem_dq_o[14]` | H9 | HSTL15_I | ov5640.fdc: mem_dq[14] |
| `mem_dq_o[15]` | G6 | HSTL15_I | ov5640.fdc: mem_dq[15] |
| `mem_dq_o[16]` | C4 | HSTL15_I | ov5640.fdc: mem_dq[16] |
| `mem_dq_o[17]` | D4 | HSTL15_I | ov5640.fdc: mem_dq[17] |
| `mem_dq_o[18]` | A4 | HSTL15_I | ov5640.fdc: mem_dq[18] |
| `mem_dq_o[19]` | E3 | HSTL15_I | ov5640.fdc: mem_dq[19] |
| `mem_dq_o[20]` | C3 | HSTL15_I | ov5640.fdc: mem_dq[20] |
| `mem_dq_o[21]` | F3 | HSTL15_I | ov5640.fdc: mem_dq[21] |
| `mem_dq_o[22]` | B4 | HSTL15_I | ov5640.fdc: mem_dq[22] |
| `mem_dq_o[23]` | D3 | HSTL15_I | ov5640.fdc: mem_dq[23] |
| `mem_dq_o[24]` | F2 | HSTL15_I | ov5640.fdc: mem_dq[24] |
| `mem_dq_o[25]` | D1 | HSTL15_I | ov5640.fdc: mem_dq[25] |
| `mem_dq_o[26]` | G1 | HSTL15_I | ov5640.fdc: mem_dq[26] |
| `mem_dq_o[27]` | A2 | HSTL15_I | ov5640.fdc: mem_dq[27] |
| `mem_dq_o[28]` | E1 | HSTL15_I | ov5640.fdc: mem_dq[28] |
| `mem_dq_o[29]` | A3 | HSTL15_I | ov5640.fdc: mem_dq[29] |
| `mem_dq_o[30]` | G2 | HSTL15_I | ov5640.fdc: mem_dq[30] |
| `mem_dq_o[31]` | C2 | HSTL15_I | ov5640.fdc: mem_dq[31] |
| `mem_dm_o[0]` | K6 | HSTL15_I | ov5640.fdc: mem_dm[0] |
| `mem_dm_o[1]` | F7 | HSTL15_I | ov5640.fdc: mem_dm[1] |
| `mem_dm_o[2]` | D5 | HSTL15_I | ov5640.fdc: mem_dm[2] |
| `mem_dm_o[3]` | E2 | HSTL15_I | ov5640.fdc: mem_dm[3] |

| SoC 输出（无物理端口） | FPGA 引脚 | IO 标准 | 来源 |
|---|---|---|---|
| `cam0_pwdn_o` / GPIO12 | 不引出，模块固定 | — | `5_1` Top.v `camera_pwnd()` 留空；legacy stereo init |
| `cam1_pwdn_o` / GPIO14 | 不引出，模块固定 | — | 同上 |


### Linux 检查

`python3 tools/check/verilog_style.py fpga/rtl`：9 个文件，0 告警。
完整 SoC 使用 `tools/regress.py expand_files` 去重，Verilator 5.020 命令：

```sh
verilator --lint-only -Wall +define+FPGA_MODE \
  --top-module edrv32_fpga_board_b2_top build/board_b2/lint.vlt \
  -f build/board_b2/soc.f build/board_b2/ip_stubs.v \
  fpga/rtl/edrv32_fpga_board_b2_top.v fpga/rtl/edrv32_fpga_ddr_adapter.v \
  fpga/rtl/edrv32_fpga_tmds.v fpga/rtl/edrv32_fpga_rgmii.v
```

IP 和器件原语空壳只放 `build/board_b2/ip_stubs.v`，不入库；本次板级 RTL 0 告警。
`lint.vlt` 只豁免既有 `rtl/tech/edrv32_mul_npu_int8_pair.v` 的四个未连接级联输出
和乘积未用位；没有全局告警豁免。该文件及板级 RTL 之外的业务 RTL未由本任务修改。
Tcl mock 检查：141 个 SoC 源文件顺序与 Python 展开完全一致，去重后加 4 个板级文件；
FDC Tcl 语法通过（17 个时钟定义）。137 个物理引脚逐位覆盖，无重复占用，README
引脚/标准与 FDC 一致。Tcl mock 不验证 PDS 命令或实际网表层级，Windows 仍需实现。
