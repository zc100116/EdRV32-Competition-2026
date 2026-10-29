# B3V IP 与导入路径检查

工程：G:/codex_project/EdRV32-FPGA/EdRV32-B3V
需要IP种类：19
Tcl展开源文件数：112（未运行真实PDS compile）
include：G:/codex_project/EdRV32-Competition-2026/rtl/include
头文件存在：edrv32_build_mode.vh, edrv32_soc_map.vh

## ip_ddr3
模块名、端口名和连接位宽：一致。
实际版本：1.10
生成日志：Done: 0 error(s), 0 warning(s)
例化位置：fpga/rtl/edrv32_fpga_board_vision_top.v / u_ddr3
output align_error [1]
input apb_addr [8]
input apb_clk [1]
input apb_enable [1]
output apb_rdata [16]
output apb_ready [1]
input apb_rst_n [1]
input apb_sel [1]
input apb_wdata [16]
input apb_write [1]
input axi_araddr [28]
input axi_arlen [4]
output axi_arready [1]
input axi_aruser_ap [1]
input axi_aruser_id [4]
input axi_arvalid [1]
input axi_awaddr [28]
input axi_awlen [4]
output axi_awready [1]
input axi_awuser_ap [1]
input axi_awuser_id [4]
input axi_awvalid [1]
output axi_rdata [256]
output axi_rid [4]
output axi_rlast [1]
output axi_rvalid [1]
input axi_wdata [256]
output axi_wready [1]
input axi_wstrb [32]
output axi_wusero_id [4]
output axi_wusero_last [1]
input ck_dly_en [1]
output ck_dly_set_bin [8]
output core_clk [1]
input dbg_cpd_start [1]
output dbg_ddrphy_init_fail [1]
input dbg_ddrphy_rst_n [1]
output dbg_dll_upd_state [2]
input dbg_gate_start [1]
input dbg_gpll_scan_rst [1]
output dbg_rst_dps_state [3]
output dbg_slice_state [88]
output dbg_slice_status [68]
output dbg_tran_err_rst_cnt [6]
output ddr_init_done [1]
output ddrphy_cpd_lock [1]
output debug_calib_ctrl [34]
input debug_cpd_offset [10]
input debug_cpd_offset_adj [1]
input debug_cpd_offset_dir [1]
output debug_cpd_state [4]
output debug_data [276]
output debug_dps_cnt_dir0 [10]
output debug_dps_cnt_dir1 [10]
output debug_gpll_dps_phase [9]
output debug_rst_state [4]
input force_read_clk_ctrl [1]
output gpll_lock [1]
input init_ck_dly_step [8]
input init_read_clk_ctrl [12]
input init_samp_position_even [32]
input init_samp_position_odd [32]
input init_slip_step [16]
input init_wrcal_position [32]
output mem_a [15]
output mem_ba [3]
output mem_cas_n [1]
output mem_ck [1]
output mem_ck_n [1]
output mem_cke [1]
output mem_cs_n [1]
output mem_dm [4]
inout mem_dq [32]
inout mem_dqs [4]
inout mem_dqs_n [4]
output mem_odt [1]
output mem_ras_n [1]
output mem_rst_n [1]
output mem_we_n [1]
output phy_pll_lock [1]
output pll_lock [1]
input ref_clk [1]
input resetn [1]
output rst_gpll_lock [1]
input samp_position_dyn_adj [1]
input wrcal_position_dyn_adj [1]
OPERATING_MODE=Controller + PHY
DDR_MEM_PART=MT41K256M16XX
MEM_DQ_WIDTH=32
MEM_ROW_WIDTH=15
MEM_COLUMN_WIDTH=10
MEM_BANK_WIDTH=3
ACTUAL_RATE=1000.000
CLKIN_FREQ=125.000
DFI_CLK_PERIOD=8000

## ip_mul_s33x33
模块名、端口名和连接位宽：一致。
实际版本：1.5
生成日志：Done: 0 error(s), 0 warning(s)
例化位置：rtl/tech/edrv32_mul_s33x33.v / u_ip
input a [33]
input b [33]
input ce [1]
input clk [1]
output p [66]
input rst [1]
PREG_BOOL=false
PIPE_STATUS=2
B_SIGNED=1
PIPEREG_EN_1=1
OUTREG_BOOL=false
INREG_BOOL=false
OUTREG_EN=0
INREG_EN=0
MREG_BOOL=true
PIPEREG_EN_2=0
CPO_REG=14'b00000000000010
PIPEREG_EN_3=1
PIPELINE_TXT=6
A_SIGNED=1
XYREG_BOOL=false

## ip_pll_eth
模块名、端口名和连接位宽：一致。
实际版本：1.4
生成日志：Done: 0 error(s), 0 warning(s)
例化位置：fpga/rtl/edrv32_fpga_rgmii.v / u_pll_eth
input clkin1 [1]
output clkout0 [1]
output lock [1]
CLKIN_FREQ=125.00000000
STATIC_RATIOI=5
STATIC_RATIOM=2
STATIC_RATIO0=8.0
STATIC_RATIO1=20
STATIC_PHASE0=5
STATIC_PHASE1=0
INTERNAL_FB=CLKOUTF

生成Verilog PLL参数：{'CLKIN_FREQ': 125.0, 'STATIC_RATIOI': 5, 'STATIC_RATIOM': 2, 'STATIC_RATIOF': 20.0, 'STATIC_RATIO0': 8.0, 'STATIC_RATIO1': 20, 'STATIC_PHASE0': 5, 'STATIC_PHASE1': 0}
生成参数对应输出MHz：125.0
## ip_pll_sys
模块名、端口名和连接位宽：一致。
实际版本：1.4
生成日志：Done: 0 error(s), 0 warning(s)
例化位置：fpga/rtl/edrv32_fpga_board_vision_top.v / u_pll_sys
input clkin1 [1]
output clkout0 [1]
output lock [1]
CLKIN_FREQ=27.00000000
STATIC_RATIOI=1
STATIC_RATIOM=2
STATIC_RATIO0=10.125
STATIC_RATIO1=20
STATIC_PHASE0=0
STATIC_PHASE1=0
INTERNAL_FB=CLKOUTF

生成Verilog PLL参数：{'CLKIN_FREQ': 27.0, 'STATIC_RATIOI': 1, 'STATIC_RATIOM': 2, 'STATIC_RATIOF': 18.75, 'STATIC_RATIO0': 10.125, 'STATIC_RATIO1': 20, 'STATIC_PHASE0': 0, 'STATIC_PHASE1': 0}
生成参数对应输出MHz：100.0
## ip_pll_video
模块名、端口名和连接位宽：一致。
实际版本：1.4
生成日志：Done: 0 error(s), 0 warning(s)
例化位置：fpga/rtl/edrv32_fpga_board_vision_top.v / u_pll_video
input clkin1 [1]
output clkout0 [1]
output clkout1 [1]
output lock [1]
CLKIN_FREQ=27.00000000
STATIC_RATIOI=1
STATIC_RATIOM=2
STATIC_RATIO0=10.0
STATIC_RATIO1=2
STATIC_PHASE0=0
STATIC_PHASE1=0
INTERNAL_FB=CLKOUTF

生成Verilog PLL参数：{'CLKIN_FREQ': 27.0, 'STATIC_RATIOI': 1, 'STATIC_RATIOM': 2, 'STATIC_RATIOF': 13.75, 'STATIC_RATIO0': 10.0, 'STATIC_RATIO1': 2, 'STATIC_PHASE0': 0, 'STATIC_PHASE1': 0}
生成参数对应输出MHz：74.25
第二路输出MHz：371.25
## ip_ram_dcache_data
模块名、端口名和连接位宽：一致。
实际版本：1.10
生成日志：Done: 0 error(s), 0 warning(s)
例化位置：rtl/tech/edrv32_ram_dcache_data.v / u_ip
wire rd_addr [9]
wire rd_clk [1]
wire rd_clk_en [1]
wire rd_data [64]
wire rd_rst [1]
wire wr_addr [9]
wire wr_byte_en [8]
wire wr_clk [1]
wire wr_data [64]
wire wr_en [1]
wire wr_rst [1]
WR_DATA_WIDTH=64
BYTE_SIZE=8
FAB_REG=false
BE_WIDTH=8
SAMEWIDTH_EN=true
INIT_EN=false
INIT_FORMAT=BIN
RD_ADDR_WIDTH=9
WR_CLK_EN=false
WR_BYTE_EN=true
RD_BE_WIDTH=8
WR_ADDR_WIDTH=9
INIT_FILE=NONE
OUTPUT_REG=false
RD_CLK_EN=true
RD_DATA_WIDTH=64

## ip_ram_dcache_tag
模块名、端口名和连接位宽：一致。
实际版本：1.10
生成日志：Done: 0 error(s), 0 warning(s)
例化位置：rtl/tech/edrv32_ram_dcache_tag.v / u_ip
wire rd_addr [9]
wire rd_clk [1]
wire rd_clk_en [1]
wire rd_data [20]
wire rd_rst [1]
wire wr_addr [9]
wire wr_clk [1]
wire wr_data [20]
wire wr_en [1]
wire wr_rst [1]
WR_CLK_EN=false
RD_BE_WIDTH=1
SAMEWIDTH_EN=true
RD_DATA_WIDTH=20
RD_ADDR_WIDTH=9
WR_DATA_WIDTH=20
INIT_FILE=NONE
OUTPUT_REG=false
FAB_REG=false
RD_CLK_EN=true
WR_ADDR_WIDTH=9
BYTE_SIZE=8
INIT_EN=false
INIT_FORMAT=BIN
WR_BYTE_EN=false
BE_WIDTH=1

## ip_ram_disp_scan
模块名、端口名和连接位宽：一致。
实际版本：1.10
生成日志：Done: 0 error(s), 0 warning(s)
例化位置：rtl/tech/edrv32_ram_disp_scan.v / u_ip
wire rd_addr [9]
wire rd_clk [1]
wire rd_clk_en [1]
wire rd_data [256]
wire rd_rst [1]
wire wr_addr [9]
wire wr_clk [1]
wire wr_data [256]
wire wr_en [1]
wire wr_rst [1]
BE_WIDTH=1
FAB_REG=false
INIT_FILE=NONE
INIT_FORMAT=BIN
WR_DATA_WIDTH=256
OUTPUT_REG=false
WR_ADDR_WIDTH=9
SAMEWIDTH_EN=true
RD_ADDR_WIDTH=9
BYTE_SIZE=8
WR_CLK_EN=false
INIT_EN=false
RD_BE_WIDTH=1
WR_BYTE_EN=false
RD_DATA_WIDTH=256
RD_CLK_EN=true

## ip_ram_eth_buf
模块名、端口名和连接位宽：一致。
实际版本：1.10
生成日志：Done: 0 error(s), 0 warning(s)
例化位置：rtl/tech/edrv32_ram_eth_buf.v / u_ip
wire rd_addr [10]
wire rd_clk [1]
wire rd_clk_en [1]
wire rd_data [32]
wire rd_rst [1]
wire wr_addr [10]
wire wr_clk [1]
wire wr_data [32]
wire wr_en [1]
wire wr_rst [1]
BE_WIDTH=1
FAB_REG=false
INIT_FILE=NONE
INIT_FORMAT=BIN
WR_DATA_WIDTH=32
OUTPUT_REG=false
WR_ADDR_WIDTH=10
SAMEWIDTH_EN=true
RD_ADDR_WIDTH=10
BYTE_SIZE=8
WR_CLK_EN=false
INIT_EN=false
RD_BE_WIDTH=1
WR_BYTE_EN=false
RD_DATA_WIDTH=32
RD_CLK_EN=true

## ip_ram_eth_fifo
模块名、端口名和连接位宽：一致。
实际版本：1.10
生成日志：Done: 0 error(s), 0 warning(s)
例化位置：rtl/tech/edrv32_ram_eth_fifo.v / u_ip
wire rd_addr [9]
wire rd_clk [1]
wire rd_clk_en [1]
wire rd_data [10]
wire rd_rst [1]
wire wr_addr [9]
wire wr_clk [1]
wire wr_data [10]
wire wr_en [1]
wire wr_rst [1]
BE_WIDTH=1
FAB_REG=false
INIT_FILE=NONE
INIT_FORMAT=BIN
WR_DATA_WIDTH=10
OUTPUT_REG=false
WR_ADDR_WIDTH=9
SAMEWIDTH_EN=true
RD_ADDR_WIDTH=9
BYTE_SIZE=8
WR_CLK_EN=false
INIT_EN=false
RD_BE_WIDTH=1
WR_BYTE_EN=false
RD_DATA_WIDTH=10
RD_CLK_EN=true

## ip_ram_geo_src
模块名、端口名和连接位宽：一致。
实际版本：1.10
生成日志：Done: 0 error(s), 0 warning(s)
例化位置：rtl/tech/edrv32_ram_geo_src.v / u_ip
wire rd_addr [11]
wire rd_clk [1]
wire rd_clk_en [1]
wire rd_data [16]
wire rd_rst [1]
wire wr_addr [8]
wire wr_clk [1]
wire wr_data [128]
wire wr_en [1]
wire wr_rst [1]
INIT_FORMAT=BIN
INIT_EN=false
SAMEWIDTH_EN=false
RD_DATA_WIDTH=16
INIT_FILE=NONE
FAB_REG=false
WR_CLK_EN=false
WR_ADDR_WIDTH=8
RD_ADDR_WIDTH=11
BE_WIDTH=1
RD_BE_WIDTH=1
WR_BYTE_EN=false
WR_DATA_WIDTH=128
BYTE_SIZE=8
RD_CLK_EN=true
OUTPUT_REG=false

## ip_ram_icache_data
模块名、端口名和连接位宽：一致。
实际版本：1.10
生成日志：Done: 0 error(s), 0 warning(s)
例化位置：rtl/tech/edrv32_ram_icache_data.v / u_ip
wire rd_addr [9]
wire rd_clk [1]
wire rd_clk_en [1]
wire rd_data [64]
wire rd_rst [1]
wire wr_addr [9]
wire wr_clk [1]
wire wr_data [64]
wire wr_en [1]
wire wr_rst [1]
WR_DATA_WIDTH=64
BYTE_SIZE=8
FAB_REG=false
BE_WIDTH=1
SAMEWIDTH_EN=true
INIT_EN=false
INIT_FORMAT=BIN
RD_ADDR_WIDTH=9
WR_CLK_EN=false
WR_BYTE_EN=false
RD_BE_WIDTH=1
WR_ADDR_WIDTH=9
INIT_FILE=NONE
OUTPUT_REG=false
RD_CLK_EN=true
RD_DATA_WIDTH=64

## ip_ram_icache_tag
模块名、端口名和连接位宽：一致。
实际版本：1.10
生成日志：Done: 0 error(s), 0 warning(s)
例化位置：rtl/tech/edrv32_ram_icache_tag.v / u_ip
wire rd_addr [9]
wire rd_clk [1]
wire rd_clk_en [1]
wire rd_data [20]
wire rd_rst [1]
wire wr_addr [9]
wire wr_clk [1]
wire wr_data [20]
wire wr_en [1]
wire wr_rst [1]
INIT_EN=false
FAB_REG=false
BE_WIDTH=1
WR_CLK_EN=false
SAMEWIDTH_EN=true
INIT_FILE=NONE
WR_DATA_WIDTH=20
RD_BE_WIDTH=1
RD_ADDR_WIDTH=9
RD_DATA_WIDTH=20
BYTE_SIZE=8
WR_BYTE_EN=false
WR_ADDR_WIDTH=9
RD_CLK_EN=true
INIT_FORMAT=BIN
OUTPUT_REG=false

## ip_ram_mem_xbar_r
模块名、端口名和连接位宽：一致。
实际版本：1.10
生成日志：Done: 0 error(s), 0 warning(s)
例化位置：rtl/tech/edrv32_ram_mem_xbar_r.v / u_ip
wire rd_addr [9]
wire rd_clk [1]
wire rd_clk_en [1]
wire rd_data [259]
wire rd_rst [1]
wire wr_addr [9]
wire wr_clk [1]
wire wr_data [259]
wire wr_en [1]
wire wr_rst [1]
RD_CLK_EN=true
WR_BYTE_EN=false
OUTPUT_REG=false
BYTE_SIZE=8
INIT_FORMAT=BIN
INIT_EN=false
RD_BE_WIDTH=1
RD_ADDR_WIDTH=9
WR_CLK_EN=false
INIT_FILE=NONE
FAB_REG=false
SAMEWIDTH_EN=true
RD_DATA_WIDTH=259
WR_DATA_WIDTH=259
WR_ADDR_WIDTH=9
BE_WIDTH=1

## ip_ram_mem_xbar_w
模块名、端口名和连接位宽：一致。
实际版本：1.10
生成日志：Done: 0 error(s), 0 warning(s)
例化位置：rtl/tech/edrv32_ram_mem_xbar_w.v / u_ip
wire rd_addr [9]
wire rd_clk [1]
wire rd_clk_en [1]
wire rd_data [288]
wire rd_rst [1]
wire wr_addr [9]
wire wr_clk [1]
wire wr_data [288]
wire wr_en [1]
wire wr_rst [1]
RD_CLK_EN=true
WR_BYTE_EN=false
OUTPUT_REG=false
BYTE_SIZE=8
INIT_FORMAT=BIN
INIT_EN=false
RD_BE_WIDTH=1
RD_ADDR_WIDTH=9
WR_CLK_EN=false
INIT_FILE=NONE
FAB_REG=false
SAMEWIDTH_EN=true
RD_DATA_WIDTH=288
WR_DATA_WIDTH=288
WR_ADDR_WIDTH=9
BE_WIDTH=1

## ip_ram_pix_line
模块名、端口名和连接位宽：一致。
实际版本：1.10
生成日志：Done: 0 error(s), 0 warning(s)
例化位置：rtl/tech/edrv32_ram_pix_line.v / u_ip
wire rd_addr [10]
wire rd_clk [1]
wire rd_clk_en [1]
wire rd_data [48]
wire rd_rst [1]
wire wr_addr [10]
wire wr_clk [1]
wire wr_data [48]
wire wr_en [1]
wire wr_rst [1]
BE_WIDTH=1
FAB_REG=false
INIT_FILE=NONE
INIT_FORMAT=BIN
WR_DATA_WIDTH=48
OUTPUT_REG=false
WR_ADDR_WIDTH=10
SAMEWIDTH_EN=true
RD_ADDR_WIDTH=10
BYTE_SIZE=8
WR_CLK_EN=false
INIT_EN=false
RD_BE_WIDTH=1
WR_BYTE_EN=false
RD_DATA_WIDTH=48
RD_CLK_EN=true

## ip_ram_sram
模块名、端口名和连接位宽：一致。
实际版本：1.8
生成日志：Done: 0 error(s), 0 warning(s)
例化位置：rtl/tech/edrv32_ram_sram.v / u_ip
wire addr [13]
wire clk [1]
wire clk_en [1]
wire rd_data [64]
wire rst [1]
wire wr_byte_en [8]
wire wr_data [64]
wire wr_en [1]
INIT_EN=true
OUTPUT_REG=false
DATA_WIDTH=64
INIT_FILE=G:\codex_project\EdRV32-Competition-2026\tasks\win\20261029-03-b3-render-full\src\ip_ram_sram.dat
FAB_REG=false
WR_BYTE_EN=true
BE_WIDTH=8
CLK_EN=true
ADDR_WIDTH=13
BYTE_SIZE=8
INIT_FORMAT=HEX

## ip_ram_vin_wfifo
模块名、端口名和连接位宽：一致。
实际版本：1.10
生成日志：Done: 0 error(s), 0 warning(s)
例化位置：rtl/tech/edrv32_ram_vin_wfifo.v / u_ip
wire rd_addr [9]
wire rd_clk [1]
wire rd_clk_en [1]
wire rd_data [288]
wire rd_rst [1]
wire wr_addr [9]
wire wr_clk [1]
wire wr_data [288]
wire wr_en [1]
wire wr_rst [1]
BE_WIDTH=1
FAB_REG=false
INIT_FILE=NONE
INIT_FORMAT=BIN
WR_DATA_WIDTH=288
OUTPUT_REG=false
WR_ADDR_WIDTH=9
SAMEWIDTH_EN=true
RD_ADDR_WIDTH=9
BYTE_SIZE=8
WR_CLK_EN=false
INIT_EN=false
RD_BE_WIDTH=1
WR_BYTE_EN=false
RD_DATA_WIDTH=288
RD_CLK_EN=true

## ip_rom_boot
模块名、端口名和连接位宽：一致。
实际版本：1.8
生成日志：Done: 0 error(s), 0 warning(s)
例化位置：rtl/tech/edrv32_rom_boot.v / u_ip
wire addr [11]
wire clk [1]
wire clk_en [1]
wire rd_data [64]
wire rst [1]
CLK_EN=true
INIT_FILE=G:\codex_project\EdRV32-Competition-2026\tasks\win\20261029-03-b3-render-full\src\ip_rom_boot.dat
ADDR_WIDTH=11
FAB_REG=false
DATA_WIDTH=64
INIT_EN=true
INIT_FORMAT=HEX
OUTPUT_REG=false

## 工程登记
磁盘PDS已登记：0；当前所需但未登记：ip_ddr3, ip_mul_s33x33, ip_pll_eth, ip_pll_sys, ip_pll_video, ip_ram_dcache_data, ip_ram_dcache_tag, ip_ram_disp_scan, ip_ram_eth_buf, ip_ram_eth_fifo, ip_ram_geo_src, ip_ram_icache_data, ip_ram_icache_tag, ip_ram_mem_xbar_r, ip_ram_mem_xbar_w, ip_ram_pix_line, ip_ram_sram, ip_ram_vin_wfifo, ip_rom_boot
GUI可能尚未保存。导入前执行 add_design 将 ipcore 下 IDF 加入当前工程，再保存。
