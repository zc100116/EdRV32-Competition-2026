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


## B3 渲染验证板级顶层

`edrv32_fpga_board_render_top.v` 直接例化 CPU、系统、存储子系统、RND 和 DISP v0.3
（L0/L1 两层），用于在板上运行 LVGL、游戏和验证 RND。RND 接 mem_xbar P4、媒体
APB 槽 4、PLIC 源 11；DISP 接 P0、槽 5、源 12；CPU DDR 网关接 P2。存储子系统保留
MEM_XBAR（槽 8、源 15）和 PERF_MON（槽 9）。VIN、PIX、GEO、NPU、ETH 不例化。

板级 DDR 适配器、DDR IP、TMDS 串化与 B2 相同。`ip_pll_sys` 输出 100 MHz 系统时钟；
DDR `core_clk` 输出 125 MHz `clk_mem`；`ip_pll_video` 同相输出 74.25 MHz 像素时钟和
371.25 MHz 串化时钟。只例化 sys/video PLL，未使用的 NPU、摄像头和 ETH 域时钟输入
在系统子系统处同 B1 接 `clk_sys`。板级复位为 `rst_n_i & sys_lock & video_lock`，DDR
控制器直接使用该复位；系统子系统中的 reset_ctrl 同步 `mem_ready` 并按 SoC 5.3 释放
各域，CPU 不会阻塞 DDR 初始化。CDC 沿用 SoC 5.2 X1/X2/X3/X5/X6/X8。

### 裁剪端口接法

这是板级裁剪，空槽依据 SoC 6.1 / sys-subsys 2.3 的约定；协调者于 2026-10-29 确认
已移除引擎的已分配槽也适用同一约定。

| 端口 | 接值 | 依据 |
|---|---|---|
| mem_subsys P1/P3/P5/ETH 的 AWVALID/WVALID/ARVALID、负载、BREADY/RREADY；P1 urgent | 全 0，响应输出不接 | SoC 6.4.1、4.2；B3-6 裁剪及协调者确认 |
| 媒体 APB 槽 0/1/2/3/6/7/10–15 | PRDATA=0、PREADY=1、PSLVERR=1 | SoC 6.1、sys-subsys 2.3 空槽约定 |
| PLIC 源 8/9/10/13/14 | 0 | SoC 6.1 中断源表、B3-6 裁剪 |
| GPIO 输入 [15:4] / [3:0]，LED 输出 | 0 / KEY[3:0]，GPIO[8:4] | SoC 3.5，与 B1/B2 相同 |
| I2C SCL/SDA 输入，输出及 OE | 2'b11，输出不接 | 同 B1，无板级 I2C 引脚 |
| DDR APB、诊断控制 | APB 输入全 0；dbg_ddrphy_rst_n=1，其余控制为 0 | fpga/ip/ip_ddr3.md，与 B2 相同 |

### 渲染顶层端口表

引脚和 IO 标准逐位沿用上面的 B2 表，约束文件为
`fpga/constraints/edrv32_fpga_board_render_top.fdc`。只保留 sys/mem/video 三组的异步关系，
pix/serial 相关时钟及 DDR PHY 内部时序约束保留。

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
| `tmds_data_p_o[0]` | R25 | TMDS | ov5640.fdc: tmds_data_p[0] |
| `tmds_data_p_o[1]` | P23 | TMDS | ov5640.fdc: tmds_data_p[1] |
| `tmds_data_p_o[2]` | N23 | TMDS | ov5640.fdc: tmds_data_p[2] |
| `tmds_data_n_o[0]` | P25 | TMDS | ov5640.fdc: tmds_data_n[0] |
| `tmds_data_n_o[1]` | P24 | TMDS | ov5640.fdc: tmds_data_n[1] |
| `tmds_data_n_o[2]` | N24 | TMDS | ov5640.fdc: tmds_data_n[2] |
| `tmds_clk_p_o` | N21 | TMDS | ov5640.fdc: tmds_clk_p |
| `tmds_clk_n_o` | N22 | TMDS | ov5640.fdc: tmds_clk_n |
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

### 导入和验证

在已按 `fpga/ip/README.md` 生成 IP 的 PDS 工程中执行
`source <仓库路径>/fpga/scripts/import_board_render_top.tcl`。脚本从
`cpu_subsys.f`、`sys_subsys.f`、`mem_subsys.f`、`rnd.f`、`disp.f` 展开源文件并去重，
设置 `FPGA_MODE`。需要的 15 种 IP：`ip_pll_sys`、`ip_pll_video`、`ip_ddr3`、
`ip_ram_icache_tag`、`ip_ram_icache_data`、`ip_ram_dcache_tag`、`ip_ram_dcache_data`、
`ip_mul_s33x33`、`ip_rom_boot`、`ip_ram_sram`、`ip_ram_mem_xbar_r`、`ip_ram_mem_xbar_w`、
`ip_ram_rnd_line`（5 实例）、`ip_ram_rnd_palette`（2 实例）、`ip_ram_disp_scan`（2 实例）。
TMDS 和 DDR 参考差分时钟使用器件原语，无需 GUI 生成串化 IP。

```sh
. ~/.local/opt/edrv32/env.sh
python3 tools/check/verilog_style.py fpga/rtl/edrv32_fpga_board_render_top.v
tclsh verif/soc/board_render/check_import.tcl
python3 tools/regress.py smoke --path verif/soc/board_render -j 1
```

`verif/soc/board_render/run.py` 构建真实 bootloader 和 `sw/tests/board_render/` 程序，
打包 ROM/SRAM 后门镜像；对顶层、全部依赖及行为模型运行 `verilator --lint-only
--timing -Wall +define+SIM_MODE --top-module edrv32_board_render_tb`（源文件由
`tools.regress.expand_files` 展开 `verif/soc/board_render/files.f`）。日志在
`build/board_render/{lint,compile,simulation}.log`。同一仿真先按住 KEY1 检查 BIOS 菜单，
再释放 KEY1 复位、从 Boot ROM 跳到预加载的 SRAM 程序；B1 的 CLINT 测试窗口加速器
用于两次启动。软件检查 RND/DISP ID、64×4 ARGB8888 FILL、PLIC 源 11 DONE、非缓存
DDR 别名逐字读回，最后写 SIM_EXIT。DDR 用户口复用已有带停顿的行为模型；PHY/诊断
引脚保持空闲，视频只建模串化连线，不运行显示帧，画面留给板上验收。

协调者批准的 testbench UART 加速：强制 BAUD_DIV=256（Q4，即每位 16 个系统周期），
UART peer=6.25 Mbaud，保留实际 BIOS 和应用的全部字节。这只用于仿真加速，不验收
UART 时序；UART 时序由 B1 测试和上板覆盖。软件仍按 115200 配置，打印文本不改。

## B3 图像通路板级顶层

`edrv32_fpga_board_vision_top.v` 用于单独检查图像通路时序、上板运行 S2，以及通过
调试工具监控 DDR 带宽、通过网口发送测试图和视频。直接例化 `edrv32_cpu_subsys`、
`edrv32_sys_subsys`（含 reset_ctrl）、`edrv32_mem_subsys`、`edrv32_vin`、`edrv32_pix`、
`edrv32_geo`、`edrv32_disp`、`edrv32_eth`；不经过完整 `edrv32_soc_top`。

与 B2 的差异：去掉 NPU 和 RND，以及 NPU PLL、NPU CDC X9/X10 和相关时钟约束；
DISP 使用当前 v0.3 的 L0/L1 两层。保留全部 B2 板级端口、引脚和 IO 标准，保留两路
DVP、I2C、DDR、HDMI、ETH/RGMII。VIN CH2 仍写 DDR，只是没有 NPU 消费它的数据。
CPU DDR 网关接 P2，VIN 接 P1、APB 槽 1、PLIC8，PIX 接槽 2、PLIC9，GEO 接 P5、
槽 3、PLIC10，DISP 接 P0、槽 5、PLIC12，ETH 接 P6 的 ETH 口、槽 7、PLIC14；
MEM_XBAR（槽 8、PLIC15）和 PERF_MON（槽 9，P6 内部仲裁）照常保留。

### 时钟与复位

| 时钟 | 来源 | 频率 / 用途 |
|---|---|---|
| `clk_i` | 板载晶振 | 27 MHz，sys/video PLL 输入 |
| `clk_sys_w` | `ip_pll_sys` | 100 MHz，CPU 和系统外设 |
| `ddr_ref_clk_w` | 差分参考输入经 GTP_INBUFDS | 125 MHz，DDR IP 输入 |
| `clk_mem_w` | `ip_ddr3.core_clk` | 125 MHz，DDR fabric、VIN/PIX/GEO、DISP/ETH 控制侧 |
| `clk_pix_w` | `ip_pll_video.clkout0` | 74.25 MHz，DISP 扫描和 TMDS 编码 |
| `clk_serial_w` | 同一 video PLL 的 clkout1 | 371.25 MHz，与像素时钟同相、5:1 |
| `cam0_pclk_i`、`cam1_pclk_i` | 两路摄像头 | 独立 DVP 时钟，FDC 各按 100 MHz 约束 |
| `rgmii_rxc_i` | PHY | 125 MHz，ETH PLL 输入 |
| `clk_eth_w` | `u_rgmii.u_pll_eth`，经 GTP_CLKBUFG | 125 MHz、30° 相移，MAC RX/TX 共用 |
| `rgmii_txc_o` | ODDR 和固定 IO 延迟 | 125 MHz，延迟 1 ns 的发送时钟 |
| 系统子系统 `clk_npu_i` | `clk_sys_w` | 同 B1，未使用的 NPU 域不生成 PLL |

板级复位为 `rst_n_i & sys_lock & video_lock`，DDR IP 直接使用它。reset_ctrl 在系统
子系统中同步 `mem_ready`、生成各域复位，维持 SoC 5.3 的释放顺序；DDR 初始化不依赖
CPU 释放。ETH PLL lock 与 B2 一样不接入全局复位。CDC 沿用 SoC 5.2 X1–X8。
约束文件 `fpga/constraints/edrv32_fpga_board_vision_top.fdc` 从 B2 删除 `clk_npu`
及其异步组，保留 DDR PHY 时钟/布局约束和 pix/serial 的相关时序。

### 未接入端口

空槽接法由协调者在 B3-7 中确认：已移除引擎的已分配槽适用预留槽约定。

| 端口 → 接值 | 依据 |
|---|---|
| mem_subsys P3（NPU）、P4（RND）的 AWVALID/WVALID/ARVALID、AWID/AWADDR/AWLEN、WDATA/WSTRB/WLAST、ARID/ARADDR/ARLEN、BREADY/RREADY → 全 0；响应输出不接 | SoC 4.2、6.4.1，B3-7 裁剪契约；这两个口没有 urgent 输入 |
| 媒体 APB 槽 4/6 → PRDATA=0、PREADY=1、PSLVERR=1 | SoC 6.1、sys-subsys 2.3，B3-7 已确认空槽约定 |
| 媒体 APB 预留槽 0/10–15 → PRDATA=0、PREADY=1、PSLVERR=1 | SoC 6.1 |
| PLIC 源 11/13 → 0 | SoC 6.1 中断源表，B3-7 裁剪契约 |
| GPIO 输入 [15:4]/[3:0] → 0/KEY[3:0]；LED → GPIO[8:4] | SoC 3.5，与 B2 相同 |
| 摄像头 PWDN 输出、其余 GPIO OE、CPU debug、未用复位/仿真状态输出 → 不引出 | SoC 3.5，与 B2 的板级引脚相同 |
| DDR APB 输入 → 全 0；dbg_ddrphy_rst_n → 1，其余诊断控制 → 0 | fpga/ip/ip_ddr3.md，与 B2 相同 |

### 图像通路顶层端口表

本顶层与 B2 **逐个端口、逐位引脚、IO 标准完全相同**。下表列出全部端口分组；
每一位的封装引脚和来源沿用上文 B2 的逐位引脚表，无新增物理引脚。

| 顶层端口 | 方向 | 位宽 | 引脚 / 功能 |
|---|---|---|---|
| `clk_i`、`rst_n_i` | 输入 | 各 1 | D18、C22 |
| `ddr_ref_clk_p_i`、`ddr_ref_clk_n_i` | 输入 | 各 1 | N3、N2，差分参考 |
| `uart_rx_i`、`uart_tx_o` | 输入、输出 | 各 1 | B24、C24 |
| `key_n_i`、`led_o` | 输入、输出 | 4、5 | B2 按键和 LED 逐位引脚 |
| `cam0_pclk_i`、`cam1_pclk_i` | 输入 | 各 1 | L22、M21 |
| `cam0_vsync_i`、`cam0_href_i`、`cam0_data_i` | 输入 | 1、1、8 | L23、T25、B2 camera_data_0[7:0] 引脚 |
| `cam1_vsync_i`、`cam1_href_i`、`cam1_data_i` | 输入 | 1、1、8 | U25、U26、B2 camera_data_1[7:0] 引脚 |
| `cam0_rst_n_o`、`cam1_rst_n_o` | 输出 | 各 1 | T22、AC26，GPIO13/15 |
| `i2c0_scl_o`、`i2c0_sda_o` | 双向 | 各 2 | SCL[0/1]=P19/AC24，SDA[0/1]=R20/Y25，开漏 |
| `tmds_data_p_o`、`tmds_data_n_o` | 输出 | 各 3 | P[0/1/2]=R25/P23/N23，N[0/1/2]=P25/P24/N24 |
| `tmds_clk_p_o`、`tmds_clk_n_o` | 输出 | 各 1 | N21、N22 |
| `rgmii_rxc_i`、`rgmii_rxd_i`、`rgmii_rx_ctl_i` | 输入 | 1、4、1 | D19、RXD[0/1/2/3]=D16/E16/A19/B19、H16 |
| `rgmii_txc_o`、`rgmii_txd_o`、`rgmii_tx_ctl_o` | 输出 | 1、4、1 | G16、TXD[0/1/2/3]=E20/B21/C21/D21、D20 |
| `eth_mdc_o`、`eth_mdio_o`、`eth_phy_rst_n_o` | 输出、双向、输出 | 各 1 | A25、E21、G25 |
| `mem_cs_n_o`、`mem_rst_n_o` | 输出 | 各 1 | N4、H1 |
| `mem_ck_o`、`mem_ck_n_o` | 输出 | 各 1 | U6、U5 |
| `mem_cke_o`、`mem_ras_n_o`、`mem_cas_n_o`、`mem_we_n_o`、`mem_odt_o` | 输出 | 各 1 | R1、P6、T7、T8、H2 |
| `mem_a_o`、`mem_ba_o` | 输出 | 15、3 | B2 DDR 地址 / Bank 逐位引脚 |
| `mem_dqs_o`、`mem_dqs_n_o` | 双向 | 各 4 | B2 DDR DQS 差分逐位引脚 |
| `mem_dq_o`、`mem_dm_o` | 双向、输出 | 32、4 | B2 DDR 数据 / 掩码逐位引脚 |

### 导入与验证

PDS 工程中先按 `fpga/ip/README.md` 生成 IP，再执行
`source <仓库路径>/fpga/scripts/import_board_vision_top.tcl`。脚本展开
`cpu_subsys.f`、`sys_subsys.f`、`mem_subsys.f`、`vin.f`、`pix.f`、`geo.f`、`disp.f`、
`eth.f` 并保持首次出现顺序去重，加入四个板级文件、约束和 `FPGA_MODE`。
需要 19 种 IP（不含 NPU/RND IP）：

- 板级：`ip_pll_sys`、`ip_pll_video`、`ip_pll_eth`、`ip_ddr3`。
- CPU/SYS：`ip_ram_icache_tag`、`ip_ram_icache_data`、`ip_ram_dcache_tag`、
  `ip_ram_dcache_data`、`ip_mul_s33x33`、`ip_rom_boot`、`ip_ram_sram`。
- MEM：`ip_ram_mem_xbar_r`、`ip_ram_mem_xbar_w`。
- 图像通路：`ip_ram_vin_wfifo`、`ip_ram_pix_line`、`ip_ram_geo_src`、
  `ip_ram_disp_scan`（L0/L1 各一个）。
- ETH：`ip_ram_eth_buf`、`ip_ram_eth_fifo`。

TMDS、RGMII 和差分参考使用器件原语，无需另生成 IP。Linux 仿真复用 board_render
的 DDR、video PLL、TMDS 原语模型，补充 RGMII PLL/缓冲/延迟/DDR IO 行为模型；本项
只验收连线，不检查摄像头采集、显示帧和网口包协议或 IO 时序。

```sh
. ~/.local/opt/edrv32/env.sh
python3 tools/check/verilog_style.py fpga/rtl/edrv32_fpga_board_vision_top.v
tclsh verif/soc/board_vision/check_import.tcl
python3 tools/regress.py smoke --path verif/soc/board_vision -j 1
```

`verif/soc/board_vision/run.py` 构建真实 BIOS 和 `sw/tests/board_vision/` SRAM 程序，
后门加载 ROM/SRAM，先检查 BIOS 菜单再复位启动应用。复用已确认的 CLINT 启动窗口
和 UART 加速：强制 Q4 BAUD_DIV=256、peer=6.25 Mbaud。软件检查 VIN/PIX/GEO/DISP/ETH
ID，对 NPU/RND 槽各执行一次读并验证 load access fault；再执行 GEO RGB565 64×4
恒等变换，经 PLIC 源 10 接收 DONE，从非缓存别名逐字比较 128 个 32 位字后写 SIM_EXIT。
顶层及全部依赖、行为模型的 lint 命令由 runner 使用 `files.f` 展开执行：
`verilator --lint-only --timing -Wall +define+SIM_MODE --top-module edrv32_board_vision_tb`。
原始日志在 `build/board_vision/{lint,compile,simulation}.log`，回归日志在
`build/regress/smoke/soc/board_vision/verilator/run.log`；Linux 结果不代表 PDS 实现或上板验收。
