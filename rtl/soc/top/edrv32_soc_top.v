// ============================================================================
// File        : edrv32_soc_top.v
// Author      : Edward ZC
// Description : Competition SoC top.  Integrates the clean eight-stage
//               RV32IMC cached core with the reused AXI4 interconnect and the
//               Phase-1 peripheral set (design §6.5.1 frozen map):
//                 Boot ROM  @ 0x0000_0000 (16 KiB, RO)
//                 SRAM      @ 0x1000_0000 (256 KiB, Phase-1 main memory)
//                 CLINT     @ 0x2000_0000 (MTIP/MSIP)
//                 PLIC      @ 0x3000_0000 (single M-context, sources 1..31)
//                 APB       @ 0x4000_0000 (UART0 / GPIO0-16b / SPI0)
//               Interconnect: the caches are AXI masters connected directly to
//               the parameterised NUM_M x NUM_S fabric. M0 (I-cache) reaches
//               ROM/SRAM; M1 (D-cache) reaches every current slave. Connectivity,
//               address windows, arbitration, ownership and DECERR handling are
//               contained in axi_interconnect for future master/slave expansion.
// Notes       : Verilog-2001.  Board adapter (clocking/pins) is a separate
//               layer; this module is board-agnostic.
// ============================================================================
`include "edrv32_axi4.vh"

// ============================================================================
// edrv32_soc_top - competition Phase-2 SoC integration
// ============================================================================
module edrv32_soc_top #(
    parameter [31:0]  RESET_PC   = 32'h0000_0000,  // Boot ROM entry
    parameter         SRAM_WORDS = 65536,          // 256 KiB
    parameter         ROM_WORDS  = 4096,           // 16 KiB
    parameter [31:0]  MVENDORID  = 32'h0,
    parameter [31:0]  MARCHID    = 32'h0,
    parameter [31:0]  MIMPID     = 32'h0,
    parameter [31:0]  MHARTID    = 32'h0,
    parameter integer CPU_MUL_USE_PANGO_APM = 0,
    parameter         CPU_HPM_ENABLE = 1,
    parameter integer CPU_FRONTEND_DUAL_WINDOW = 0,
    parameter integer CPU_DUAL_ISSUE = 0,
    parameter integer CPU_FETCH_WIDE = 0,
    parameter         TCM_ENABLE  = 0,
    parameter         ITCM_ENABLE = TCM_ENABLE,
    parameter         DTCM_ENABLE = TCM_ENABLE,
    parameter [31:0]  ITCM_SIZE_BYTES = 32'd65536,
    parameter [31:0]  DTCM_SIZE_BYTES = 32'd65536,
    parameter         AXI_MON_ENABLE = 1,
    parameter         DDR_ENABLE = 0,
    parameter         DDR_GATEWAY_ENABLE = 1,
    parameter         DDR_MONITOR_ENABLE = 0,
    parameter         VISION_ENABLE = 1,
    parameter         ROM_INIT_FILE  = "",
    parameter         SRAM_INIT_FILE = "",
    parameter         ITCM_INIT_FILE = ""
)(
    // --- Clock and reset ---
    input  wire                     clk,
    input  wire                     rst_n,

    // DDR data-plane clock. Used only when DDR_MONITOR_ENABLE is set.
    input  wire                     ddr_bus_clk_i,
    input  wire                     ddr_bus_rst_n_i,

    // --- UART0 (slot 0x00) ---
    output wire                     uart0_tx_o,
    input  wire                     uart0_rx_i,
    // --- GPIO0 (slot 0x01, 16 bit) ---
    input  wire [15:0]              gpio_in_i,
    output wire [15:0]              gpio_out_o,
    output wire [15:0]              gpio_oe_o,
    // --- SPI0 (slot 0x02) ---
    input  wire [3:0]               spi_io_i,
    output wire [3:0]               spi_io_o,
    output wire [3:0]               spi_io_oe_o,
    output wire                     spi_sclk_o,
    output wire [3:0]               spi_cs_n_o,

    // Platform level interrupt sources 4..31.  Source 0 is reserved and
    // sources 1..3 remain the internal UART/GPIO/SPI gateways.
    input  wire [27:0]              platform_irq_i,

    // --- Vision control/status (status inputs are synchronous to clk) ---
    input  wire                     vision_cam0_init_done_i,
    input  wire                     vision_cam1_init_done_i,
    input  wire                     vision_cam_error_i,
    input  wire [31:0]              vision_cam0_frame_count_i,
    input  wire [31:0]              vision_cam1_frame_count_i,
    input  wire                     vision_cam_cfg_ack_toggle_i,
    input  wire                     vision_cam_cfg_response_error_i,
    input  wire [7:0]               vision_cam_cfg_response_data_i,
    input  wire [1:0]               vision_disp_active_buffer_i,
    input  wire                     vision_disp_error_i,
    input  wire [31:0]              vision_disp_frame_count_i,
    input  wire [31:0]              vision_disp_underflow_count_i,
    input  wire [31:0]              vision_disp_scanout_frame_count_i,
    input  wire [6:0]               vision_disp_debug_status_i,
    input  wire                     vision_pixel_cfg_ack_toggle_i,
    input  wire [31:0]              vision_pixel_frame_count_i,
    input  wire [31:0]              vision_pixel_error_count_i,
    output wire                     vision_cam0_enable_o,
    output wire                     vision_cam1_enable_o,
    output wire                     vision_cam_cfg_req_toggle_o,
    output wire                     vision_cam_cfg_camera_o,
    output wire                     vision_cam_cfg_read_o,
    output wire [15:0]              vision_cam_cfg_reg_addr_o,
    output wire [7:0]               vision_cam_cfg_write_data_o,
    output wire                     vision_disp_enable_o,
    output wire                     vision_pixel_cfg_req_toggle_o,
    output wire                     vision_pixel_cfg_enable_o,
    output wire                     vision_pixel_cfg_grayscale_o,
    output wire                     vision_pixel_cfg_threshold_enable_o,
    output wire                     vision_pixel_cfg_invert_o,
    output wire signed [8:0]        vision_pixel_cfg_brightness_o,
    output wire [8:0]               vision_pixel_cfg_contrast_o,
    output wire [7:0]               vision_pixel_cfg_threshold_o,
    output wire                     vision_pixel_cfg_spatial_enable_o,
    output wire [2:0]               vision_pixel_cfg_spatial_mode_o,
    output wire [7:0]               vision_pixel_cfg_spatial_threshold_o,

    // --- 256-bit DDR data-plane master from the CPU Gateway ---
    output wire [3:0]               ddr_awid_o,
    output wire [31:0]              ddr_awaddr_o,
    output wire [7:0]               ddr_awlen_o,
    output wire [2:0]               ddr_awsize_o,
    output wire [1:0]               ddr_awburst_o,
    output wire [3:0]               ddr_awqos_o,
    output wire                     ddr_awvalid_o,
    input  wire                     ddr_awready_i,
    output wire [255:0]             ddr_wdata_o,
    output wire [31:0]              ddr_wstrb_o,
    output wire                     ddr_wlast_o,
    output wire                     ddr_wvalid_o,
    input  wire                     ddr_wready_i,
    input  wire [3:0]               ddr_bid_i,
    input  wire [1:0]               ddr_bresp_i,
    input  wire                     ddr_bvalid_i,
    output wire                     ddr_bready_o,
    output wire [3:0]               ddr_arid_o,
    output wire [31:0]              ddr_araddr_o,
    output wire [7:0]               ddr_arlen_o,
    output wire [2:0]               ddr_arsize_o,
    output wire [1:0]               ddr_arburst_o,
    output wire [3:0]               ddr_arqos_o,
    output wire                     ddr_arvalid_o,
    input  wire                     ddr_arready_i,
    input  wire [3:0]               ddr_rid_i,
    input  wire [255:0]             ddr_rdata_i,
    input  wire [1:0]               ddr_rresp_i,
    input  wire                     ddr_rlast_i,
    input  wire                     ddr_rvalid_i,
    output wire                     ddr_rready_o,

    // --- 256-bit DDR Monitor master (already in the DDR bus clock domain) ---
    output wire [3:0]               ddr_mon_awid_o,
    output wire [31:0]              ddr_mon_awaddr_o,
    output wire [7:0]               ddr_mon_awlen_o,
    output wire [2:0]               ddr_mon_awsize_o,
    output wire [1:0]               ddr_mon_awburst_o,
    output wire [3:0]               ddr_mon_awqos_o,
    output wire                     ddr_mon_awvalid_o,
    input  wire                     ddr_mon_awready_i,
    output wire [255:0]             ddr_mon_wdata_o,
    output wire [31:0]              ddr_mon_wstrb_o,
    output wire                     ddr_mon_wlast_o,
    output wire                     ddr_mon_wvalid_o,
    input  wire                     ddr_mon_wready_i,
    input  wire [3:0]               ddr_mon_bid_i,
    input  wire [1:0]               ddr_mon_bresp_i,
    input  wire                     ddr_mon_bvalid_i,
    output wire                     ddr_mon_bready_o,
    output wire [3:0]               ddr_mon_arid_o,
    output wire [31:0]              ddr_mon_araddr_o,
    output wire [7:0]               ddr_mon_arlen_o,
    output wire [2:0]               ddr_mon_arsize_o,
    output wire [1:0]               ddr_mon_arburst_o,
    output wire [3:0]               ddr_mon_arqos_o,
    output wire                     ddr_mon_arvalid_o,
    input  wire                     ddr_mon_arready_i,
    input  wire [3:0]               ddr_mon_rid_i,
    input  wire [255:0]             ddr_mon_rdata_i,
    input  wire [1:0]               ddr_mon_rresp_i,
    input  wire                     ddr_mon_rlast_i,
    input  wire                     ddr_mon_rvalid_i,
    output wire                     ddr_mon_rready_o,

    // --- Compact board-debug vector (for optional ILA) ---
    output wire [255:0]             debug_o
);

    // ========================================================================
    // AXI master channels: M0 = instruction cache, M1 = data cache.
    // ========================================================================
    wire m0_arvalid_w;
    wire m0_arready_w;
    wire m0_rvalid_w;
    wire m0_rready_w;
    wire m0_rlast_w;
    wire [`AXI_ID_W-1:0] m0_arid_w;
    wire [`AXI_ID_W-1:0] m0_rid_w;
    wire [31:0] m0_araddr_w;
    wire [`AXI_DATA_W-1:0] m0_rdata_w;
    wire [`AXI_LEN_W-1:0] m0_arlen_w;
    wire [`AXI_SIZE_W-1:0] m0_arsize_w;
    wire [`AXI_BURST_W-1:0] m0_arburst_w;
    wire [`AXI_RESP_W-1:0] m0_rresp_w;
    wire m1_arvalid_w;
    wire m1_arready_w;
    wire m1_rvalid_w;
    wire m1_rready_w;
    wire m1_rlast_w;
    wire [`AXI_ID_W-1:0] m1_arid_w;
    wire [`AXI_ID_W-1:0] m1_rid_w;
    wire [31:0] m1_araddr_w;
    wire [`AXI_DATA_W-1:0] m1_rdata_w;
    wire [`AXI_LEN_W-1:0] m1_arlen_w;
    wire [`AXI_SIZE_W-1:0] m1_arsize_w;
    wire [`AXI_BURST_W-1:0] m1_arburst_w;
    wire [`AXI_RESP_W-1:0] m1_rresp_w;
    wire m1_awvalid_w;
    wire m1_awready_w;
    wire m1_wvalid_w;
    wire m1_wready_w;
    wire m1_wlast_w;
    wire [`AXI_ID_W-1:0] m1_awid_w;
    wire [`AXI_ID_W-1:0] m1_bid_w;
    wire [31:0] m1_awaddr_w;
    wire [`AXI_DATA_W-1:0] m1_wdata_w;
    wire [`AXI_LEN_W-1:0] m1_awlen_w;
    wire [`AXI_SIZE_W-1:0] m1_awsize_w;
    wire [`AXI_BURST_W-1:0] m1_awburst_w;
    wire [`AXI_STRB_W-1:0] m1_wstrb_w;
    wire m1_bvalid_w;
    wire m1_bready_w;
    wire [`AXI_RESP_W-1:0] m1_bresp_w;

    // ========================================================================
    // Address map (design §6.5.1)
    // ========================================================================
    localparam [31:0] ROM_BASE   = 32'h0000_0000;
    localparam [31:0] ROM_END    = ROM_BASE  + ROM_WORDS * 4;
    localparam [31:0] SRAM_BASE  = 32'h1000_0000;
    localparam [31:0] SRAM_END   = SRAM_BASE + SRAM_WORDS * 4;
    localparam [31:0] CLINT_BASE = 32'h2000_0000;
    localparam [31:0] CLINT_END  = CLINT_BASE + 32'h0001_0000;
    localparam [31:0] PLIC_BASE  = 32'h3000_0000;
    localparam [31:0] PLIC_END   = PLIC_BASE + 32'h0040_0000;
    localparam [31:0] APB_BASE   = 32'h4000_0000;
    localparam [31:0] APB_END    = APB_BASE + 32'h0004_0000;
    localparam [31:0] DDR_BASE   = 32'h8000_0000;
    // axi_interconnect treats base > limit as a wrap-through-zero interval;
    // limit zero therefore describes [0x8000_0000, 2^32).
    localparam [31:0] DDR_END    = 32'h0000_0000;

    localparam AXI_NUM_M = 2;
    localparam AXI_NUM_S = 6;
    localparam AXI_S_ROM   = 0;
    localparam AXI_S_SRAM  = 1;
    localparam AXI_S_CLINT = 2;
    localparam AXI_S_PLIC  = 3;
    localparam AXI_S_APB   = 4;
    localparam AXI_S_DDR   = 5;
    // Both cache masters are single-outstanding, and M0 is read-only.
    // Match the fabric queues to that real contract instead of synthesizing
    // the generic 4-deep master / 8-deep slave write machinery.
    localparam AXI_M_MAX_OUTSTANDING = 1;
    localparam AXI_S_MAX_WR = 1;
    // Slave-side global ID width: {master_index, local_id} (design §6.3).
    localparam AXI_S_ID_W = `AXI_ID_W + $clog2(AXI_NUM_M);

    // Packed slave order is high-to-low DDR/APB/PLIC/CLINT/SRAM/ROM.
    wire [AXI_NUM_S*32-1:0] axi_s_base_w =
        {DDR_BASE, APB_BASE, PLIC_BASE, CLINT_BASE, SRAM_BASE, ROM_BASE};
    wire [AXI_NUM_S*32-1:0] axi_s_limit_w =
        {DDR_END, APB_END, PLIC_END, CLINT_END, SRAM_END, ROM_END};
    wire [AXI_NUM_M*AXI_NUM_S-1:0] axi_read_connect_w =
        {(DDR_ENABLE ? 1'b1 : 1'b0), 5'b11111,
         (DDR_ENABLE ? 1'b1 : 1'b0), 3'b000, 2'b11};
    wire [AXI_NUM_M*AXI_NUM_S-1:0] axi_write_connect_w =
        {(DDR_ENABLE ? 1'b1 : 1'b0), 5'b11111, 6'b000000};

    // ========================================================================
    // Clean eight-stage core + blocking I$/D$.
    // ========================================================================
    wire        debug_commit_valid_w;
    wire [31:0] debug_commit_pc_w;
    wire [31:0] debug_commit_instr_w;
    wire        debug_commit_exception_w;
    wire [31:0] debug_commit_cause_w;
    wire        debug_core_sleep_w;
    wire [31:0] debug_decode_pc_w;
    wire [31:0] debug_decode_instr_w;
    wire irq_soft_w;
    wire irq_timer_w;
    wire irq_ext_w;
    wire [63:0] clint_mtime_w;
    wire itcm_req_valid_w;
    wire itcm_req_ready_w;
    wire [31:0] itcm_req_addr_w;
    wire itcm_resp_valid_w;
    wire itcm_resp_ready_w;
    wire [31:0] itcm_resp_rdata_w;
    wire itcm_resp_error_w;
    wire dtcm_req_valid_w;
    wire dtcm_req_ready_w;
    wire [31:0] dtcm_req_addr_w;
    wire dtcm_req_we_w;
    wire [1:0] dtcm_req_size_w;
    wire [3:0] dtcm_req_wstrb_w;
    wire [31:0] dtcm_req_wdata_w;
    wire dtcm_resp_valid_w;
    wire dtcm_resp_ready_w;
    wire [31:0] dtcm_resp_rdata_w;
    wire dtcm_resp_error_w;

    edrv32_cached_core #(
        .RESET_PC(RESET_PC),
        .ICACHE_LINE_COUNT(256),
        .DCACHE_LINE_COUNT(256),
        .MUL_USE_PANGO_APM(CPU_MUL_USE_PANGO_APM),
        .CPU_HPM_ENABLE(CPU_HPM_ENABLE),
        .FRONTEND_DUAL_WINDOW(CPU_FRONTEND_DUAL_WINDOW),
        .DUAL_ISSUE(CPU_DUAL_ISSUE),
        .FETCH_WIDE(CPU_FETCH_WIDE),
        .TCM_ENABLE (TCM_ENABLE),
        .ITCM_ENABLE(ITCM_ENABLE),
        .DTCM_ENABLE(DTCM_ENABLE),
        .MVENDORID(MVENDORID),
        .MARCHID(MARCHID),
        .MIMPID(MIMPID),
        .MHARTID(MHARTID)
    ) u_cached_core (
        .clk_i(clk),
        .rst_n_i(rst_n),
        .icache_axi_arid_o(m0_arid_w),
        .icache_axi_araddr_o(m0_araddr_w),
        .icache_axi_arlen_o(m0_arlen_w),
        .icache_axi_arsize_o(m0_arsize_w),
        .icache_axi_arburst_o(m0_arburst_w),
        .icache_axi_arvalid_o(m0_arvalid_w),
        .icache_axi_arready_i(m0_arready_w),
        .icache_axi_rid_i(m0_rid_w),
        .icache_axi_rdata_i(m0_rdata_w),
        .icache_axi_rresp_i(m0_rresp_w),
        .icache_axi_rlast_i(m0_rlast_w),
        .icache_axi_rvalid_i(m0_rvalid_w),
        .icache_axi_rready_o(m0_rready_w),
        .dcache_axi_awid_o(m1_awid_w),
        .dcache_axi_awaddr_o(m1_awaddr_w),
        .dcache_axi_awlen_o(m1_awlen_w),
        .dcache_axi_awsize_o(m1_awsize_w),
        .dcache_axi_awburst_o(m1_awburst_w),
        .dcache_axi_awvalid_o(m1_awvalid_w),
        .dcache_axi_awready_i(m1_awready_w),
        .dcache_axi_wdata_o(m1_wdata_w),
        .dcache_axi_wstrb_o(m1_wstrb_w),
        .dcache_axi_wlast_o(m1_wlast_w),
        .dcache_axi_wvalid_o(m1_wvalid_w),
        .dcache_axi_wready_i(m1_wready_w),
        .dcache_axi_bid_i(m1_bid_w),
        .dcache_axi_bresp_i(m1_bresp_w),
        .dcache_axi_bvalid_i(m1_bvalid_w),
        .dcache_axi_bready_o(m1_bready_w),
        .dcache_axi_arid_o(m1_arid_w),
        .dcache_axi_araddr_o(m1_araddr_w),
        .dcache_axi_arlen_o(m1_arlen_w),
        .dcache_axi_arsize_o(m1_arsize_w),
        .dcache_axi_arburst_o(m1_arburst_w),
        .dcache_axi_arvalid_o(m1_arvalid_w),
        .dcache_axi_arready_i(m1_arready_w),
        .dcache_axi_rid_i(m1_rid_w),
        .dcache_axi_rdata_i(m1_rdata_w),
        .dcache_axi_rresp_i(m1_rresp_w),
        .dcache_axi_rlast_i(m1_rlast_w),
        .dcache_axi_rvalid_i(m1_rvalid_w),
        .dcache_axi_rready_o(m1_rready_w),
        .itcm_req_valid_o(itcm_req_valid_w),
        .itcm_req_ready_i(itcm_req_ready_w),
        .itcm_req_addr_o(itcm_req_addr_w),
        .itcm_resp_valid_i(itcm_resp_valid_w),
        .itcm_resp_ready_o(itcm_resp_ready_w),
        .itcm_resp_rdata_i(itcm_resp_rdata_w),
        .itcm_resp_error_i(itcm_resp_error_w),
        .dtcm_req_valid_o(dtcm_req_valid_w),
        .dtcm_req_ready_i(dtcm_req_ready_w),
        .dtcm_req_addr_o(dtcm_req_addr_w),
        .dtcm_req_we_o(dtcm_req_we_w),
        .dtcm_req_size_o(dtcm_req_size_w),
        .dtcm_req_wstrb_o(dtcm_req_wstrb_w),
        .dtcm_req_wdata_o(dtcm_req_wdata_w),
        .dtcm_resp_valid_i(dtcm_resp_valid_w),
        .dtcm_resp_ready_o(dtcm_resp_ready_w),
        .dtcm_resp_rdata_i(dtcm_resp_rdata_w),
        .dtcm_resp_error_i(dtcm_resp_error_w),
        .irq_soft_i(irq_soft_w),
        .irq_timer_i(irq_timer_w),
        .irq_ext_i(irq_ext_w),
        .time_value_i(clint_mtime_w),
        .retire_o(debug_commit_valid_w),
        .retire_pc_o(debug_commit_pc_w),
        .retire_instr_o(debug_commit_instr_w),
        .retire_exception_o(debug_commit_exception_w),
        .retire_cause_o(debug_commit_cause_w),
        .core_sleep_o(debug_core_sleep_w),
        .debug_decode_pc_o(debug_decode_pc_w),
        .debug_decode_instr_o(debug_decode_instr_w)
    );

    edrv32_tcm_subsystem #(
        .ENABLE          (TCM_ENABLE),
        .ITCM_ENABLE     (ITCM_ENABLE),
        .DTCM_ENABLE     (DTCM_ENABLE),
        .ITCM_SIZE_BYTES (ITCM_SIZE_BYTES),
        .DTCM_SIZE_BYTES (DTCM_SIZE_BYTES),
        .ITCM_INIT_FILE  (ITCM_INIT_FILE)
    ) u_tcm_subsystem (
        .clk_i             (clk),
        .rst_n_i           (rst_n),
        .itcm_req_valid_i  (itcm_req_valid_w),
        .itcm_req_ready_o  (itcm_req_ready_w),
        .itcm_req_addr_i   (itcm_req_addr_w),
        .itcm_resp_valid_o (itcm_resp_valid_w),
        .itcm_resp_ready_i (itcm_resp_ready_w),
        .itcm_resp_rdata_o (itcm_resp_rdata_w),
        .itcm_resp_error_o (itcm_resp_error_w),
        .dtcm_req_valid_i  (dtcm_req_valid_w),
        .dtcm_req_ready_o  (dtcm_req_ready_w),
        .dtcm_req_addr_i   (dtcm_req_addr_w),
        .dtcm_req_we_i     (dtcm_req_we_w),
        .dtcm_req_wstrb_i  (dtcm_req_wstrb_w),
        .dtcm_req_wdata_i  (dtcm_req_wdata_w),
        .dtcm_resp_valid_o (dtcm_resp_valid_w),
        .dtcm_resp_ready_i (dtcm_resp_ready_w),
        .dtcm_resp_rdata_o (dtcm_resp_rdata_w),
        .dtcm_resp_error_o (dtcm_resp_error_w)
    );

    wire unused_dtcm_size_w = ^dtcm_req_size_w;

    // ========================================================================
    // Parameterised AXI interconnect. Adding another master or slave only
    // extends these packed vectors, the map, and connectivity masks.
    // ========================================================================
    wire [AXI_NUM_M-1:0] axi_m_arready_w;
    wire [AXI_NUM_M-1:0] axi_m_rvalid_w;
    wire [AXI_NUM_M-1:0] axi_m_rlast_w;
    wire [AXI_NUM_M*`AXI_ID_W-1:0] axi_m_rid_w;
    wire [AXI_NUM_M*`AXI_DATA_W-1:0] axi_m_rdata_w;
    wire [AXI_NUM_M*`AXI_RESP_W-1:0] axi_m_rresp_w;
    wire [AXI_NUM_M-1:0] axi_m_awready_w;
    wire [AXI_NUM_M-1:0] axi_m_wready_w;
    wire [AXI_NUM_M-1:0] axi_m_bvalid_w;
    wire [AXI_NUM_M*`AXI_ID_W-1:0] axi_m_bid_w;
    wire [AXI_NUM_M*`AXI_RESP_W-1:0] axi_m_bresp_w;

    // Fully registered return slices.  Each two-entry FIFO cuts AXI
    // VALID/payload and READY paths in both directions, so a slave response
    // cannot propagate through the crossbar and cache state in one cycle.
    // Both cache masters are single-outstanding, therefore two entries are
    // sufficient for B and for continuous burst R beats.
    localparam AXI_R_SLICE_W = `AXI_ID_W + `AXI_DATA_W +
                               `AXI_RESP_W + 1;
    localparam AXI_B_SLICE_W = `AXI_ID_W + `AXI_RESP_W;
    wire [AXI_R_SLICE_W-1:0] m0_r_slice_data_w;
    wire [AXI_R_SLICE_W-1:0] m1_r_slice_data_w;
    wire [AXI_B_SLICE_W-1:0] m1_b_slice_data_w;
    wire m0_r_slice_full_w;
    wire m0_r_slice_empty_w;
    wire m1_r_slice_full_w;
    wire m1_r_slice_empty_w;
    wire m1_b_slice_full_w;
    wire m1_b_slice_empty_w;
    wire [AXI_NUM_M-1:0] axi_m_rready_slice_w =
        {~m1_r_slice_full_w, ~m0_r_slice_full_w};
    wire [AXI_NUM_M-1:0] axi_m_bready_slice_w =
        {~m1_b_slice_full_w, 1'b0};

    wire [AXI_NUM_S*AXI_S_ID_W-1:0] axi_s_arid_w;
    wire [AXI_NUM_S*AXI_S_ID_W-1:0] axi_s_rid_w;
    wire [AXI_NUM_S*32-1:0] axi_s_araddr_w;
    wire [AXI_NUM_S*`AXI_LEN_W-1:0] axi_s_arlen_w;
    wire [AXI_NUM_S*`AXI_SIZE_W-1:0] axi_s_arsize_w;
    wire [AXI_NUM_S*`AXI_BURST_W-1:0] axi_s_arburst_w;
    wire [AXI_NUM_S-1:0] axi_s_arvalid_w;
    wire [AXI_NUM_S-1:0] axi_s_arready_w;
    wire [AXI_NUM_S*`AXI_DATA_W-1:0] axi_s_rdata_w;
    wire [AXI_NUM_S*`AXI_RESP_W-1:0] axi_s_rresp_w;
    wire [AXI_NUM_S-1:0] axi_s_rlast_w;
    wire [AXI_NUM_S-1:0] axi_s_rvalid_w;
    wire [AXI_NUM_S-1:0] axi_s_rready_w;
    wire [AXI_NUM_S*AXI_S_ID_W-1:0] axi_s_awid_w;
    wire [AXI_NUM_S*AXI_S_ID_W-1:0] axi_s_bid_w;
    wire [AXI_NUM_S*32-1:0] axi_s_awaddr_w;
    wire [AXI_NUM_S*`AXI_LEN_W-1:0] axi_s_awlen_w;
    wire [AXI_NUM_S*`AXI_SIZE_W-1:0] axi_s_awsize_w;
    wire [AXI_NUM_S*`AXI_BURST_W-1:0] axi_s_awburst_w;
    wire [AXI_NUM_S-1:0] axi_s_awvalid_w;
    wire [AXI_NUM_S-1:0] axi_s_awready_w;
    wire [AXI_NUM_S*`AXI_DATA_W-1:0] axi_s_wdata_w;
    wire [AXI_NUM_S*`AXI_STRB_W-1:0] axi_s_wstrb_w;
    wire [AXI_NUM_S-1:0] axi_s_wlast_w;
    wire [AXI_NUM_S-1:0] axi_s_wvalid_w;
    wire [AXI_NUM_S-1:0] axi_s_wready_w;
    wire [AXI_NUM_S*`AXI_RESP_W-1:0] axi_s_bresp_w;
    wire [AXI_NUM_S-1:0] axi_s_bvalid_w;
    wire [AXI_NUM_S-1:0] axi_s_bready_w;

    assign {m1_arready_w, m0_arready_w} = axi_m_arready_w;
    assign {m0_rid_w, m0_rdata_w, m0_rresp_w, m0_rlast_w} =
        m0_r_slice_data_w;
    assign {m1_rid_w, m1_rdata_w, m1_rresp_w, m1_rlast_w} =
        m1_r_slice_data_w;
    assign m0_rvalid_w = !m0_r_slice_empty_w;
    assign m1_rvalid_w = !m1_r_slice_empty_w;
    assign m1_awready_w = axi_m_awready_w[1];
    assign m1_wready_w  = axi_m_wready_w[1];
    assign {m1_bid_w, m1_bresp_w} = m1_b_slice_data_w;
    assign m1_bvalid_w = !m1_b_slice_empty_w;

    sync_fifo #(
        .WIDTH (AXI_R_SLICE_W),
        .DEPTH (2)
    ) u_m0_r_slice (
        .clk     (clk),
        .rst_n   (rst_n),
        .flush_i (1'b0),
        .push_i  (axi_m_rvalid_w[0] && axi_m_rready_slice_w[0]),
        .wdata_i ({axi_m_rid_w[0 +: `AXI_ID_W],
                   axi_m_rdata_w[0 +: `AXI_DATA_W],
                   axi_m_rresp_w[0 +: `AXI_RESP_W], axi_m_rlast_w[0]}),
        .pop_i   (m0_rvalid_w && m0_rready_w),
        .rdata_o (m0_r_slice_data_w),
        .full_o  (m0_r_slice_full_w),
        .empty_o (m0_r_slice_empty_w),
        .count_o ()
    );

    sync_fifo #(
        .WIDTH (AXI_R_SLICE_W),
        .DEPTH (2)
    ) u_m1_r_slice (
        .clk     (clk),
        .rst_n   (rst_n),
        .flush_i (1'b0),
        .push_i  (axi_m_rvalid_w[1] && axi_m_rready_slice_w[1]),
        .wdata_i ({axi_m_rid_w[`AXI_ID_W +: `AXI_ID_W],
                   axi_m_rdata_w[`AXI_DATA_W +: `AXI_DATA_W],
                   axi_m_rresp_w[`AXI_RESP_W +: `AXI_RESP_W],
                   axi_m_rlast_w[1]}),
        .pop_i   (m1_rvalid_w && m1_rready_w),
        .rdata_o (m1_r_slice_data_w),
        .full_o  (m1_r_slice_full_w),
        .empty_o (m1_r_slice_empty_w),
        .count_o ()
    );

    sync_fifo #(
        .WIDTH (AXI_B_SLICE_W),
        .DEPTH (2)
    ) u_m1_b_slice (
        .clk     (clk),
        .rst_n   (rst_n),
        .flush_i (1'b0),
        .push_i  (axi_m_bvalid_w[1] && axi_m_bready_slice_w[1]),
        .wdata_i ({axi_m_bid_w[`AXI_ID_W +: `AXI_ID_W],
                   axi_m_bresp_w[`AXI_RESP_W +: `AXI_RESP_W]}),
        .pop_i   (m1_bvalid_w && m1_bready_w),
        .rdata_o (m1_b_slice_data_w),
        .full_o  (m1_b_slice_full_w),
        .empty_o (m1_b_slice_empty_w),
        .count_o ()
    );

    // Fail-stop timeout: generous gate (SRAM responses are single-digit
    // cycles; 8192 cannot misfire on legal latency, and a hung slave stops
    // the world loudly instead of silently).  Monitor enabled per §4.3.
    wire [AXI_NUM_M-1:0] axi_fs_rd_fail_w;
    wire [AXI_NUM_M-1:0] axi_fs_wr_fail_w;
    wire [AXI_NUM_M*32-1:0] axi_fs_rd_addr_w;
    wire [AXI_NUM_M*32-1:0] axi_fs_wr_addr_w;
    wire [AXI_NUM_M*`AXI_ID_W-1:0] axi_fs_rd_id_w;
    wire [AXI_NUM_M*`AXI_ID_W-1:0] axi_fs_wr_id_w;
    wire [AXI_NUM_M*32-1:0] axi_mon_rd_beats_w;
    wire [AXI_NUM_M*32-1:0] axi_mon_rd_bursts_w;
    wire [AXI_NUM_M*32-1:0] axi_mon_rd_err_w;
    wire [AXI_NUM_M*32-1:0] axi_mon_rd_maxwait_w;
    wire [AXI_NUM_M*32-1:0] axi_mon_wr_beats_w;
    wire [AXI_NUM_M*32-1:0] axi_mon_wr_bursts_w;
    wire [AXI_NUM_M*32-1:0] axi_mon_wr_err_w;
    wire [AXI_NUM_M*32-1:0] axi_mon_wr_maxwait_w;
    wire unused_axi_mon_w = ^{axi_fs_rd_addr_w, axi_fs_wr_addr_w,
                              axi_fs_rd_id_w, axi_fs_wr_id_w,
                              axi_mon_rd_beats_w, axi_mon_rd_bursts_w,
                              axi_mon_rd_err_w, axi_mon_rd_maxwait_w,
                              axi_mon_wr_beats_w, axi_mon_wr_bursts_w,
                              axi_mon_wr_err_w, axi_mon_wr_maxwait_w};

    axi_interconnect #(
        .NUM_M (AXI_NUM_M),
        .NUM_S (AXI_NUM_S),
        .M_MAX_OUTSTANDING (AXI_M_MAX_OUTSTANDING),
        .S_MAX_WR          (AXI_S_MAX_WR),
        .RD_TIMEOUT_CYCLES (32'd8192),
        .WR_TIMEOUT_CYCLES (32'd8192),
        .AXI_MON_ENABLE    (AXI_MON_ENABLE)
    ) u_axi_interconnect (
        // --- Clock and reset ---
        .clk               (clk),
        .rst_n             (rst_n),
        // --- Master-side read channels ---
        .m_arid_i          ({m1_arid_w, m0_arid_w}),
        .m_araddr_i        ({m1_araddr_w, m0_araddr_w}),
        .m_arlen_i         ({m1_arlen_w, m0_arlen_w}),
        .m_arsize_i        ({m1_arsize_w, m0_arsize_w}),
        .m_arburst_i       ({m1_arburst_w, m0_arburst_w}),
        .m_arvalid_i       ({m1_arvalid_w, m0_arvalid_w}),
        .m_arready_o       (axi_m_arready_w),
        .m_rid_o           (axi_m_rid_w),
        .m_rdata_o         (axi_m_rdata_w),
        .m_rresp_o         (axi_m_rresp_w),
        .m_rlast_o         (axi_m_rlast_w),
        .m_rvalid_o        (axi_m_rvalid_w),
        .m_rready_i        (axi_m_rready_slice_w),
        // --- Master-side write channels ---
        .m_awid_i          ({m1_awid_w, {`AXI_ID_W{1'b0}}}),
        .m_awaddr_i        ({m1_awaddr_w, 32'h0}),
        .m_awlen_i         ({m1_awlen_w, {`AXI_LEN_W{1'b0}}}),
        .m_awsize_i        ({m1_awsize_w, {`AXI_SIZE_W{1'b0}}}),
        .m_awburst_i       ({m1_awburst_w, {`AXI_BURST_W{1'b0}}}),
        .m_awvalid_i       ({m1_awvalid_w, 1'b0}),
        .m_awready_o       (axi_m_awready_w),
        .m_wdata_i         ({m1_wdata_w, {`AXI_DATA_W{1'b0}}}),
        .m_wstrb_i         ({m1_wstrb_w, {`AXI_STRB_W{1'b0}}}),
        .m_wlast_i         ({m1_wlast_w, 1'b0}),
        .m_wvalid_i        ({m1_wvalid_w, 1'b0}),
        .m_wready_o        (axi_m_wready_w),
        .m_bid_o           (axi_m_bid_w),
        .m_bresp_o         (axi_m_bresp_w),
        .m_bvalid_o        (axi_m_bvalid_w),
        .m_bready_i        (axi_m_bready_slice_w),
        // --- Address map and connectivity ---
        .s_base_i          (axi_s_base_w),
        .s_limit_i         (axi_s_limit_w),
        .m_read_connect_i  (axi_read_connect_w),
        .m_write_connect_i (axi_write_connect_w),
        // --- Slave-side read channels ---
        .s_arid_o          (axi_s_arid_w),
        .s_araddr_o        (axi_s_araddr_w),
        .s_arlen_o         (axi_s_arlen_w),
        .s_arsize_o        (axi_s_arsize_w),
        .s_arburst_o       (axi_s_arburst_w),
        .s_arvalid_o       (axi_s_arvalid_w),
        .s_arready_i       (axi_s_arready_w),
        .s_rid_i           (axi_s_rid_w),
        .s_rdata_i         (axi_s_rdata_w),
        .s_rresp_i         (axi_s_rresp_w),
        .s_rlast_i         (axi_s_rlast_w),
        .s_rvalid_i        (axi_s_rvalid_w),
        .s_rready_o        (axi_s_rready_w),
        // --- Slave-side write channels ---
        .s_awid_o          (axi_s_awid_w),
        .s_awaddr_o        (axi_s_awaddr_w),
        .s_awlen_o         (axi_s_awlen_w),
        .s_awsize_o        (axi_s_awsize_w),
        .s_awburst_o       (axi_s_awburst_w),
        .s_awvalid_o       (axi_s_awvalid_w),
        .s_awready_i       (axi_s_awready_w),
        .s_wdata_o         (axi_s_wdata_w),
        .s_wstrb_o         (axi_s_wstrb_w),
        .s_wlast_o         (axi_s_wlast_w),
        .s_wvalid_o        (axi_s_wvalid_w),
        .s_wready_i        (axi_s_wready_w),
        .s_bid_i           (axi_s_bid_w),
        .s_bresp_i         (axi_s_bresp_w),
        .s_bvalid_i        (axi_s_bvalid_w),
        .s_bready_o        (axi_s_bready_w),
        .fs_rd_fail_o      (axi_fs_rd_fail_w),
        .fs_rd_addr_o      (axi_fs_rd_addr_w),
        .fs_rd_id_o        (axi_fs_rd_id_w),
        .fs_wr_fail_o      (axi_fs_wr_fail_w),
        .fs_wr_addr_o      (axi_fs_wr_addr_w),
        .fs_wr_id_o        (axi_fs_wr_id_w),
        .mon_rd_beats_o    (axi_mon_rd_beats_w),
        .mon_rd_bursts_o   (axi_mon_rd_bursts_w),
        .mon_rd_err_o      (axi_mon_rd_err_w),
        .mon_rd_maxwait_o  (axi_mon_rd_maxwait_w),
        .mon_wr_beats_o    (axi_mon_wr_beats_w),
        .mon_wr_bursts_o   (axi_mon_wr_bursts_w),
        .mon_wr_err_o      (axi_mon_wr_err_w),
        .mon_wr_maxwait_o  (axi_mon_wr_maxwait_w)
    );

    // ========================================================================
    // Slaves: Boot ROM, SRAM, CLINT, PLIC, APB
    // ========================================================================
    wire [AXI_S_ID_W-1:0] rom_bid_w;
    wire [AXI_S_ID_W-1:0] sram_bid_w;
    wire [AXI_S_ID_W-1:0] rom_rid_w;
    wire [AXI_S_ID_W-1:0] sram_rid_w;
    wire [`AXI_RESP_W-1:0] rom_bresp_w;
    wire [`AXI_RESP_W-1:0] sram_bresp_w;
    wire rom_bvalid_w;
    wire sram_bvalid_w;
    wire rom_awready_w;
    wire sram_awready_w;
    wire rom_wready_w;
    wire sram_wready_w;
    wire [`AXI_DATA_W-1:0] rom_rdata_w;
    wire [`AXI_DATA_W-1:0] sram_rdata_w;
    wire [`AXI_RESP_W-1:0] rom_rresp_w;
    wire [`AXI_RESP_W-1:0] sram_rresp_w;
    wire rom_rvalid_w;
    wire rom_rlast_w;
    wire rom_arready_w;
    wire sram_rvalid_w;
    wire sram_rlast_w;
    wire sram_arready_w;

    boot_rom_axi #(
        .NUM_WORDS     (ROM_WORDS),
        .BASE_ADDR     (ROM_BASE),
        .ID_W          (AXI_S_ID_W),
        .ROM_INIT_FILE (ROM_INIT_FILE)
    ) u_boot_rom (
        .clk(clk),
        .rst_n(rst_n),
        .awid_i (axi_s_awid_w[AXI_S_ROM*AXI_S_ID_W +: AXI_S_ID_W]),
        .awaddr_i (axi_s_awaddr_w[AXI_S_ROM*32 +: 32]),
        .awlen_i (axi_s_awlen_w[AXI_S_ROM*`AXI_LEN_W +: `AXI_LEN_W]),
        .awvalid_i (axi_s_awvalid_w[AXI_S_ROM]),
        .awready_o (rom_awready_w),
        .wdata_i (axi_s_wdata_w[AXI_S_ROM*`AXI_DATA_W +: `AXI_DATA_W]),
        .wstrb_i (axi_s_wstrb_w[AXI_S_ROM*`AXI_STRB_W +: `AXI_STRB_W]),
        .wlast_i (axi_s_wlast_w[AXI_S_ROM]),
        .wvalid_i (axi_s_wvalid_w[AXI_S_ROM]),
        .wready_o (rom_wready_w),
        .bid_o (rom_bid_w),
        .bresp_o (rom_bresp_w),
        .bvalid_o (rom_bvalid_w),
        .bready_i (axi_s_bready_w[AXI_S_ROM]),
        .arid_i (axi_s_arid_w[AXI_S_ROM*AXI_S_ID_W +: AXI_S_ID_W]),
        .araddr_i (axi_s_araddr_w[AXI_S_ROM*32 +: 32]),
        .arlen_i (axi_s_arlen_w[AXI_S_ROM*`AXI_LEN_W +: `AXI_LEN_W]),
        .arsize_i (axi_s_arsize_w[AXI_S_ROM*`AXI_SIZE_W +: `AXI_SIZE_W]),
        .arburst_i (axi_s_arburst_w[AXI_S_ROM*`AXI_BURST_W +: `AXI_BURST_W]),
        .arvalid_i (axi_s_arvalid_w[AXI_S_ROM]),
        .arready_o (rom_arready_w),
        .rid_o (rom_rid_w),
        .rdata_o (rom_rdata_w),
        .rresp_o (rom_rresp_w),
        .rlast_o (rom_rlast_w),
        .rvalid_o (rom_rvalid_w),
        .rready_i (axi_s_rready_w[AXI_S_ROM])
    );

    sram_axi #(
        .NUM_WORDS    (SRAM_WORDS),
        .BASE_ADDR    (SRAM_BASE),
        .ID_W         (AXI_S_ID_W),
        .SRAM_INIT_FILE(SRAM_INIT_FILE)
    ) u_sram (
        .clk(clk),
        .rst_n(rst_n),
        .awid_i (axi_s_awid_w[AXI_S_SRAM*AXI_S_ID_W +: AXI_S_ID_W]),
        .awaddr_i (axi_s_awaddr_w[AXI_S_SRAM*32 +: 32]),
        .awlen_i (axi_s_awlen_w[AXI_S_SRAM*`AXI_LEN_W +: `AXI_LEN_W]),
        .awsize_i (axi_s_awsize_w[AXI_S_SRAM*`AXI_SIZE_W +: `AXI_SIZE_W]),
        .awburst_i (axi_s_awburst_w[AXI_S_SRAM*`AXI_BURST_W +: `AXI_BURST_W]),
        .awvalid_i (axi_s_awvalid_w[AXI_S_SRAM]),
        .awready_o (sram_awready_w),
        .wdata_i (axi_s_wdata_w[AXI_S_SRAM*`AXI_DATA_W +: `AXI_DATA_W]),
        .wstrb_i (axi_s_wstrb_w[AXI_S_SRAM*`AXI_STRB_W +: `AXI_STRB_W]),
        .wlast_i (axi_s_wlast_w[AXI_S_SRAM]),
        .wvalid_i (axi_s_wvalid_w[AXI_S_SRAM]),
        .wready_o (sram_wready_w),
        .bid_o (sram_bid_w),
        .bresp_o (sram_bresp_w),
        .bvalid_o (sram_bvalid_w),
        .bready_i (axi_s_bready_w[AXI_S_SRAM]),
        .arid_i (axi_s_arid_w[AXI_S_SRAM*AXI_S_ID_W +: AXI_S_ID_W]),
        .araddr_i (axi_s_araddr_w[AXI_S_SRAM*32 +: 32]),
        .arlen_i (axi_s_arlen_w[AXI_S_SRAM*`AXI_LEN_W +: `AXI_LEN_W]),
        .arsize_i (axi_s_arsize_w[AXI_S_SRAM*`AXI_SIZE_W +: `AXI_SIZE_W]),
        .arburst_i (axi_s_arburst_w[AXI_S_SRAM*`AXI_BURST_W +: `AXI_BURST_W]),
        .arvalid_i (axi_s_arvalid_w[AXI_S_SRAM]),
        .arready_o (sram_arready_w),
        .rid_o (sram_rid_w),
        .rdata_o (sram_rdata_w),
        .rresp_o (sram_rresp_w),
        .rlast_o (sram_rlast_w),
        .rvalid_o (sram_rvalid_w),
        .rready_i (axi_s_rready_w[AXI_S_SRAM])
    );

    // --- CLINT ---
    wire clint_req_valid_w;
    wire clint_req_ready_w;
    wire clint_resp_valid_w;
    wire clint_resp_error_w;
    wire [31:0] clint_req_addr_w;
    wire [31:0] clint_resp_rdata_w;
    wire clint_req_we_w;
    wire clint_resp_ready_w;
    wire [3:0]  clint_req_wstrb_w;
    wire [31:0] clint_req_wdata_w;
    wire clint_awready_w;
    wire clint_wready_w;
    wire clint_arready_w;
    wire clint_bvalid_w;
    wire clint_rvalid_w;
    wire clint_rlast_w;
    wire [AXI_S_ID_W-1:0] clint_bid_w;
    wire [AXI_S_ID_W-1:0] clint_rid_w;
    wire [`AXI_DATA_W-1:0] clint_rdata_w;
    wire [`AXI_RESP_W-1:0] clint_bresp_w;
    wire [`AXI_RESP_W-1:0] clint_rresp_w;

    axi2native #(.ID_W(AXI_S_ID_W)) u_a2n_clint (
        .clk(clk),
        .rst_n(rst_n),
        .awid_i (axi_s_awid_w[AXI_S_CLINT*AXI_S_ID_W +: AXI_S_ID_W]),
        .awaddr_i (axi_s_awaddr_w[AXI_S_CLINT*32 +: 32]),
        .awlen_i (axi_s_awlen_w[AXI_S_CLINT*`AXI_LEN_W +: `AXI_LEN_W]),
        .awsize_i (axi_s_awsize_w[AXI_S_CLINT*`AXI_SIZE_W +: `AXI_SIZE_W]),
        .awvalid_i (axi_s_awvalid_w[AXI_S_CLINT]),
        .awready_o (clint_awready_w),
        .wdata_i (axi_s_wdata_w[AXI_S_CLINT*`AXI_DATA_W +: `AXI_DATA_W]),
        .wstrb_i (axi_s_wstrb_w[AXI_S_CLINT*`AXI_STRB_W +: `AXI_STRB_W]),
        .wlast_i (axi_s_wlast_w[AXI_S_CLINT]),
        .wvalid_i (axi_s_wvalid_w[AXI_S_CLINT]),
        .wready_o (clint_wready_w),
        .bid_o (clint_bid_w),
        .bresp_o (clint_bresp_w),
        .bvalid_o (clint_bvalid_w),
        .bready_i (axi_s_bready_w[AXI_S_CLINT]),
        .arid_i (axi_s_arid_w[AXI_S_CLINT*AXI_S_ID_W +: AXI_S_ID_W]),
        .araddr_i (axi_s_araddr_w[AXI_S_CLINT*32 +: 32]),
        .arlen_i (axi_s_arlen_w[AXI_S_CLINT*`AXI_LEN_W +: `AXI_LEN_W]),
        .arsize_i (axi_s_arsize_w[AXI_S_CLINT*`AXI_SIZE_W +: `AXI_SIZE_W]),
        .arvalid_i (axi_s_arvalid_w[AXI_S_CLINT]),
        .arready_o (clint_arready_w),
        .rid_o (clint_rid_w),
        .rdata_o (clint_rdata_w),
        .rresp_o (clint_rresp_w),
        .rlast_o (clint_rlast_w),
        .rvalid_o (clint_rvalid_w),
        .rready_i (axi_s_rready_w[AXI_S_CLINT]),
        .req_valid_o (clint_req_valid_w),
        .req_ready_i (clint_req_ready_w),
        .req_addr_o (clint_req_addr_w),
        .req_we_o (clint_req_we_w),
        .req_wstrb_o (clint_req_wstrb_w),
        .req_wdata_o (clint_req_wdata_w),
        .resp_valid_i (clint_resp_valid_w),
        .resp_ready_o (clint_resp_ready_w),
        .resp_rdata_i (clint_resp_rdata_w),
        .resp_error_i (clint_resp_error_w)
    );

    clint u_clint (
        .clk(clk),
        .rst_n(rst_n),
        .req_valid_i (clint_req_valid_w),
        .req_ready_o (clint_req_ready_w),
        .req_addr_i (clint_req_addr_w),
        .req_we_i (clint_req_we_w),
        .req_wstrb_i (clint_req_wstrb_w),
        .req_wdata_i (clint_req_wdata_w),
        .resp_ready_i (clint_resp_ready_w),
        .resp_valid_o (clint_resp_valid_w),
        .resp_rdata_o (clint_resp_rdata_w),
        .resp_error_o (clint_resp_error_w),
        .irq_timer_o (irq_timer_w),
        .irq_soft_o (irq_soft_w),
        .mtime_o (clint_mtime_w)
    );

    // --- PLIC ---
    wire plic_req_valid_w;
    wire plic_req_ready_w;
    wire plic_resp_valid_w;
    wire plic_resp_error_w;
    wire [31:0] plic_req_addr_w;
    wire [31:0] plic_resp_rdata_w;
    wire plic_req_we_w;
    wire plic_resp_ready_w;
    wire [3:0]  plic_req_wstrb_w;
    wire [31:0] plic_req_wdata_w;
    wire plic_awready_w;
    wire plic_wready_w;
    wire plic_arready_w;
    wire plic_bvalid_w;
    wire plic_rvalid_w;
    wire plic_rlast_w;
    wire [AXI_S_ID_W-1:0] plic_bid_w;
    wire [AXI_S_ID_W-1:0] plic_rid_w;
    wire [`AXI_DATA_W-1:0] plic_rdata_w;
    wire [`AXI_RESP_W-1:0] plic_bresp_w;
    wire [`AXI_RESP_W-1:0] plic_rresp_w;
    wire uart_irq_w;
    wire gpio_irq_w;
    wire spi_irq_w;
    wire cam_irq_w;
    wire disp_irq_w;
    wire pixel_irq_w;
    wire [3:0]  spi_cs_n;
    // PLIC source 0 is reserved. Platform IRQ IDs start at one:
    // UART0=1, GPIO0=2, SPI0=3, platform_irq_i[0]=4 ... [27]=31.
    // CAM/DISP/PIXEL are internal sources 6/7/11, replacing the matching
    // platform bits while all other platform sources pass through.
    wire [27:0] platform_irq_effective_w = {
        platform_irq_i[27:8], pixel_irq_w, platform_irq_i[6:4],
        disp_irq_w, cam_irq_w,
        platform_irq_i[1:0]
    };
    wire [31:0] plic_src_w = {platform_irq_effective_w,
                              spi_irq_w, gpio_irq_w,
                              uart_irq_w, 1'b0};

    axi2native #(.ID_W(AXI_S_ID_W)) u_a2n_plic (
        .clk(clk),
        .rst_n(rst_n),
        .awid_i (axi_s_awid_w[AXI_S_PLIC*AXI_S_ID_W +: AXI_S_ID_W]),
        .awaddr_i (axi_s_awaddr_w[AXI_S_PLIC*32 +: 32]),
        .awlen_i (axi_s_awlen_w[AXI_S_PLIC*`AXI_LEN_W +: `AXI_LEN_W]),
        .awsize_i (axi_s_awsize_w[AXI_S_PLIC*`AXI_SIZE_W +: `AXI_SIZE_W]),
        .awvalid_i (axi_s_awvalid_w[AXI_S_PLIC]),
        .awready_o (plic_awready_w),
        .wdata_i (axi_s_wdata_w[AXI_S_PLIC*`AXI_DATA_W +: `AXI_DATA_W]),
        .wstrb_i (axi_s_wstrb_w[AXI_S_PLIC*`AXI_STRB_W +: `AXI_STRB_W]),
        .wlast_i (axi_s_wlast_w[AXI_S_PLIC]),
        .wvalid_i (axi_s_wvalid_w[AXI_S_PLIC]),
        .wready_o (plic_wready_w),
        .bid_o (plic_bid_w),
        .bresp_o (plic_bresp_w),
        .bvalid_o (plic_bvalid_w),
        .bready_i (axi_s_bready_w[AXI_S_PLIC]),
        .arid_i (axi_s_arid_w[AXI_S_PLIC*AXI_S_ID_W +: AXI_S_ID_W]),
        .araddr_i (axi_s_araddr_w[AXI_S_PLIC*32 +: 32]),
        .arlen_i (axi_s_arlen_w[AXI_S_PLIC*`AXI_LEN_W +: `AXI_LEN_W]),
        .arsize_i (axi_s_arsize_w[AXI_S_PLIC*`AXI_SIZE_W +: `AXI_SIZE_W]),
        .arvalid_i (axi_s_arvalid_w[AXI_S_PLIC]),
        .arready_o (plic_arready_w),
        .rid_o (plic_rid_w),
        .rdata_o (plic_rdata_w),
        .rresp_o (plic_rresp_w),
        .rlast_o (plic_rlast_w),
        .rvalid_o (plic_rvalid_w),
        .rready_i (axi_s_rready_w[AXI_S_PLIC]),
        .req_valid_o (plic_req_valid_w),
        .req_ready_i (plic_req_ready_w),
        .req_addr_o (plic_req_addr_w),
        .req_we_o (plic_req_we_w),
        .req_wstrb_o (plic_req_wstrb_w),
        .req_wdata_o (plic_req_wdata_w),
        .resp_valid_i (plic_resp_valid_w),
        .resp_ready_o (plic_resp_ready_w),
        .resp_rdata_i (plic_resp_rdata_w),
        .resp_error_i (plic_resp_error_w)
    );

    plic u_plic (
        .clk(clk),
        .rst_n(rst_n),
        .req_valid_i (plic_req_valid_w),
        .req_ready_o (plic_req_ready_w),
        .req_addr_i (plic_req_addr_w),
        .req_we_i (plic_req_we_w),
        .req_wstrb_i (plic_req_wstrb_w),
        .req_wdata_i (plic_req_wdata_w),
        .resp_ready_i (plic_resp_ready_w),
        .resp_valid_o (plic_resp_valid_w),
        .resp_rdata_o (plic_resp_rdata_w),
        .resp_error_o (plic_resp_error_w),
        .src_i (plic_src_w),
        .irq_ext_o (irq_ext_w)
    );

    // --- APB bridge + peripherals ---
    wire [31:0] apb_paddr_w;
    wire [31:0] apb_pwdata_w;
    wire [31:0] apb_prdata_w;
    wire apb_psel_w;
    wire apb_penable_w;
    wire apb_pwrite_w;
    wire apb_pready_w;
    wire apb_pslverr_w;
    wire apb_mux_pready_w;
    wire apb_mux_pslverr_w;
    wire [3:0]  apb_pstrb_w;
    wire apb_awready_w;
    wire apb_wready_w;
    wire apb_arready_w;
    wire apb_bvalid_w;
    wire apb_rvalid_w;
    wire apb_rlast_w;
    wire [AXI_S_ID_W-1:0] apb_bid_w;
    wire [AXI_S_ID_W-1:0] apb_rid_w;
    wire [`AXI_DATA_W-1:0] apb_rdata_w;
    wire [`AXI_RESP_W-1:0] apb_bresp_w;
    wire [`AXI_RESP_W-1:0] apb_rresp_w;

    wire ddr_gateway_awready_w;
    wire ddr_gateway_wready_w;
    wire ddr_gateway_bvalid_w;
    wire [AXI_S_ID_W-1:0] ddr_gateway_bid_w;
    wire [`AXI_RESP_W-1:0] ddr_gateway_bresp_w;
    wire ddr_gateway_arready_w;
    wire ddr_gateway_rvalid_w;
    wire ddr_gateway_rlast_w;
    wire [AXI_S_ID_W-1:0] ddr_gateway_rid_w;
    wire [`AXI_DATA_W-1:0] ddr_gateway_rdata_w;
    wire [`AXI_RESP_W-1:0] ddr_gateway_rresp_w;
    wire ddr_gateway_protocol_error_w;

    generate if (DDR_GATEWAY_ENABLE) begin : gen_ddr_gateway
    edrv32_axi_ddr_gateway #(
        .S_ID_W(AXI_S_ID_W),
        .M_ID_W(4),
        .LEN_W(`AXI_LEN_W)
    ) u_ddr_gateway (
        .clk_i(clk),
        .rst_n_i(rst_n),
        .s_awid_i(axi_s_awid_w[AXI_S_DDR*AXI_S_ID_W +: AXI_S_ID_W]),
        .s_awaddr_i(axi_s_awaddr_w[AXI_S_DDR*32 +: 32]),
        .s_awlen_i(axi_s_awlen_w[AXI_S_DDR*`AXI_LEN_W +: `AXI_LEN_W]),
        .s_awsize_i(axi_s_awsize_w[AXI_S_DDR*`AXI_SIZE_W +: `AXI_SIZE_W]),
        .s_awburst_i(axi_s_awburst_w[AXI_S_DDR*`AXI_BURST_W +: `AXI_BURST_W]),
        .s_awvalid_i(axi_s_awvalid_w[AXI_S_DDR]),
        .s_awready_o(ddr_gateway_awready_w),
        .s_wdata_i(axi_s_wdata_w[AXI_S_DDR*`AXI_DATA_W +: `AXI_DATA_W]),
        .s_wstrb_i(axi_s_wstrb_w[AXI_S_DDR*`AXI_STRB_W +: `AXI_STRB_W]),
        .s_wlast_i(axi_s_wlast_w[AXI_S_DDR]),
        .s_wvalid_i(axi_s_wvalid_w[AXI_S_DDR]),
        .s_wready_o(ddr_gateway_wready_w),
        .s_bid_o(ddr_gateway_bid_w),
        .s_bresp_o(ddr_gateway_bresp_w),
        .s_bvalid_o(ddr_gateway_bvalid_w),
        .s_bready_i(axi_s_bready_w[AXI_S_DDR]),
        .s_arid_i(axi_s_arid_w[AXI_S_DDR*AXI_S_ID_W +: AXI_S_ID_W]),
        .s_araddr_i(axi_s_araddr_w[AXI_S_DDR*32 +: 32]),
        .s_arlen_i(axi_s_arlen_w[AXI_S_DDR*`AXI_LEN_W +: `AXI_LEN_W]),
        .s_arsize_i(axi_s_arsize_w[AXI_S_DDR*`AXI_SIZE_W +: `AXI_SIZE_W]),
        .s_arburst_i(axi_s_arburst_w[AXI_S_DDR*`AXI_BURST_W +: `AXI_BURST_W]),
        .s_arvalid_i(axi_s_arvalid_w[AXI_S_DDR]),
        .s_arready_o(ddr_gateway_arready_w),
        .s_rid_o(ddr_gateway_rid_w),
        .s_rdata_o(ddr_gateway_rdata_w),
        .s_rresp_o(ddr_gateway_rresp_w),
        .s_rlast_o(ddr_gateway_rlast_w),
        .s_rvalid_o(ddr_gateway_rvalid_w),
        .s_rready_i(axi_s_rready_w[AXI_S_DDR]),
        .m_awid_o(ddr_awid_o),
        .m_awaddr_o(ddr_awaddr_o),
        .m_awlen_o(ddr_awlen_o),
        .m_awsize_o(ddr_awsize_o),
        .m_awburst_o(ddr_awburst_o),
        .m_awqos_o(ddr_awqos_o),
        .m_awvalid_o(ddr_awvalid_o),
        .m_awready_i(ddr_awready_i),
        .m_wdata_o(ddr_wdata_o),
        .m_wstrb_o(ddr_wstrb_o),
        .m_wlast_o(ddr_wlast_o),
        .m_wvalid_o(ddr_wvalid_o),
        .m_wready_i(ddr_wready_i),
        .m_bid_i(ddr_bid_i),
        .m_bresp_i(ddr_bresp_i),
        .m_bvalid_i(ddr_bvalid_i),
        .m_bready_o(ddr_bready_o),
        .m_arid_o(ddr_arid_o),
        .m_araddr_o(ddr_araddr_o),
        .m_arlen_o(ddr_arlen_o),
        .m_arsize_o(ddr_arsize_o),
        .m_arburst_o(ddr_arburst_o),
        .m_arqos_o(ddr_arqos_o),
        .m_arvalid_o(ddr_arvalid_o),
        .m_arready_i(ddr_arready_i),
        .m_rid_i(ddr_rid_i),
        .m_rdata_i(ddr_rdata_i),
        .m_rresp_i(ddr_rresp_i),
        .m_rlast_i(ddr_rlast_i),
        .m_rvalid_i(ddr_rvalid_i),
        .m_rready_o(ddr_rready_o),
        .protocol_error_o(ddr_gateway_protocol_error_w)
    );
    end else begin : gen_no_ddr_gateway
        assign ddr_gateway_awready_w        = 1'b0;
        assign ddr_gateway_wready_w         = 1'b0;
        assign ddr_gateway_bid_w            = {AXI_S_ID_W{1'b0}};
        assign ddr_gateway_bresp_w          = 2'b00;
        assign ddr_gateway_bvalid_w         = 1'b0;
        assign ddr_gateway_arready_w        = 1'b0;
        assign ddr_gateway_rid_w            = {AXI_S_ID_W{1'b0}};
        assign ddr_gateway_rdata_w          = {`AXI_DATA_W{1'b0}};
        assign ddr_gateway_rresp_w          = 2'b00;
        assign ddr_gateway_rlast_w          = 1'b0;
        assign ddr_gateway_rvalid_w         = 1'b0;
        assign ddr_gateway_protocol_error_w = 1'b0;
        assign ddr_awid_o                   = 4'b0000;
        assign ddr_awaddr_o                 = 32'b0;
        assign ddr_awlen_o                  = 8'b0;
        assign ddr_awsize_o                 = 3'b000;
        assign ddr_awburst_o                = 2'b00;
        assign ddr_awqos_o                  = 4'b0000;
        assign ddr_awvalid_o                = 1'b0;
        assign ddr_wdata_o                  = 256'b0;
        assign ddr_wstrb_o                  = 32'b0;
        assign ddr_wlast_o                  = 1'b0;
        assign ddr_wvalid_o                 = 1'b0;
        assign ddr_bready_o                 = 1'b0;
        assign ddr_arid_o                   = 4'b0000;
        assign ddr_araddr_o                 = 32'b0;
        assign ddr_arlen_o                  = 8'b0;
        assign ddr_arsize_o                 = 3'b000;
        assign ddr_arburst_o                = 2'b00;
        assign ddr_arqos_o                  = 4'b0000;
        assign ddr_arvalid_o                = 1'b0;
        assign ddr_rready_o                 = 1'b0;
    end endgenerate

    assign axi_s_arready_w = {ddr_gateway_arready_w,
                              apb_arready_w, plic_arready_w, clint_arready_w,
                              sram_arready_w, rom_arready_w};
    assign axi_s_rid_w     = {ddr_gateway_rid_w,
                              apb_rid_w, plic_rid_w, clint_rid_w,
                              sram_rid_w, rom_rid_w};
    assign axi_s_rdata_w   = {ddr_gateway_rdata_w,
                              apb_rdata_w, plic_rdata_w, clint_rdata_w,
                              sram_rdata_w, rom_rdata_w};
    assign axi_s_rresp_w   = {ddr_gateway_rresp_w,
                              apb_rresp_w, plic_rresp_w, clint_rresp_w,
                              sram_rresp_w, rom_rresp_w};
    assign axi_s_rlast_w   = {ddr_gateway_rlast_w,
                              apb_rlast_w, plic_rlast_w, clint_rlast_w,
                              sram_rlast_w, rom_rlast_w};
    assign axi_s_rvalid_w  = {ddr_gateway_rvalid_w,
                              apb_rvalid_w, plic_rvalid_w, clint_rvalid_w,
                              sram_rvalid_w, rom_rvalid_w};
    assign axi_s_awready_w = {ddr_gateway_awready_w,
                              apb_awready_w, plic_awready_w, clint_awready_w,
                              sram_awready_w, rom_awready_w};
    assign axi_s_wready_w  = {ddr_gateway_wready_w,
                              apb_wready_w, plic_wready_w, clint_wready_w,
                              sram_wready_w, rom_wready_w};
    assign axi_s_bid_w     = {ddr_gateway_bid_w,
                              apb_bid_w, plic_bid_w, clint_bid_w,
                              sram_bid_w, rom_bid_w};
    assign axi_s_bresp_w   = {ddr_gateway_bresp_w,
                              apb_bresp_w, plic_bresp_w, clint_bresp_w,
                              sram_bresp_w, rom_bresp_w};
    assign axi_s_bvalid_w  = {ddr_gateway_bvalid_w,
                              apb_bvalid_w, plic_bvalid_w, clint_bvalid_w,
                              sram_bvalid_w, rom_bvalid_w};

    axi2apb #(.ID_W(AXI_S_ID_W)) u_a2p (
        .clk(clk),
        .rst_n(rst_n),
        .awid_i (axi_s_awid_w[AXI_S_APB*AXI_S_ID_W +: AXI_S_ID_W]),
        .awaddr_i (axi_s_awaddr_w[AXI_S_APB*32 +: 32]),
        .awlen_i (axi_s_awlen_w[AXI_S_APB*`AXI_LEN_W +: `AXI_LEN_W]),
        .awsize_i (axi_s_awsize_w[AXI_S_APB*`AXI_SIZE_W +: `AXI_SIZE_W]),
        .awvalid_i (axi_s_awvalid_w[AXI_S_APB]),
        .awready_o (apb_awready_w),
        .wdata_i (axi_s_wdata_w[AXI_S_APB*`AXI_DATA_W +: `AXI_DATA_W]),
        .wstrb_i (axi_s_wstrb_w[AXI_S_APB*`AXI_STRB_W +: `AXI_STRB_W]),
        .wlast_i (axi_s_wlast_w[AXI_S_APB]),
        .wvalid_i (axi_s_wvalid_w[AXI_S_APB]),
        .wready_o (apb_wready_w),
        .bid_o (apb_bid_w),
        .bresp_o (apb_bresp_w),
        .bvalid_o (apb_bvalid_w),
        .bready_i (axi_s_bready_w[AXI_S_APB]),
        .arid_i (axi_s_arid_w[AXI_S_APB*AXI_S_ID_W +: AXI_S_ID_W]),
        .araddr_i (axi_s_araddr_w[AXI_S_APB*32 +: 32]),
        .arlen_i (axi_s_arlen_w[AXI_S_APB*`AXI_LEN_W +: `AXI_LEN_W]),
        .arsize_i (axi_s_arsize_w[AXI_S_APB*`AXI_SIZE_W +: `AXI_SIZE_W]),
        .arvalid_i (axi_s_arvalid_w[AXI_S_APB]),
        .arready_o (apb_arready_w),
        .rid_o (apb_rid_w),
        .rdata_o (apb_rdata_w),
        .rresp_o (apb_rresp_w),
        .rlast_o (apb_rlast_w),
        .rvalid_o (apb_rvalid_w),
        .rready_i (axi_s_rready_w[AXI_S_APB]),
        .paddr_o (apb_paddr_w),
        .psel_o (apb_psel_w),
        .penable_o (apb_penable_w),
        .pwrite_o (apb_pwrite_w),
        .pwdata_o (apb_pwdata_w),
        .pstrb_o (apb_pstrb_w),
        .pready_i (apb_mux_pready_w),
        .prdata_i (apb_prdata_w),
        .pslverr_i (apb_mux_pslverr_w)
    );

    // APB downstream. CAM/DISP occupy slots 6/7 and PIXEL occupies slot 12.
    wire [15:0] apb_slot_psel_w;
    wire apb_d_penable_w;
    wire apb_d_pwrite_w;
    wire [31:0] apb_d_paddr_w;
    wire [31:0] apb_d_pwdata_w;
    wire [3:0]  apb_d_pstrb_w;
    wire uart_pready_w;
    wire gpio_pready_w;
    wire spi_pready_w;
    wire ddr_monitor_pready_w;
    wire cam_pready_w;
    wire disp_pready_w;
    wire pixel_pready_w;
    wire uart_pslverr_w;
    wire gpio_pslverr_w;
    wire spi_pslverr_w;
    wire ddr_monitor_pslverr_w;
    wire cam_pslverr_w;
    wire disp_pslverr_w;
    wire pixel_pslverr_w;
    wire [31:0] uart_prdata_w;
    wire [31:0] gpio_prdata_w;
    wire [31:0] spi_prdata_w;
    wire [31:0] ddr_monitor_prdata_w;
    wire [31:0] cam_prdata_w;
    wire [31:0] disp_prdata_w;
    wire [31:0] pixel_prdata_w;

    wire [15:0] apb_slot_pready_w;
    wire [16*32-1:0] apb_slot_prdata_w;
    wire [15:0] apb_slot_pslverr_w;
    // slot0=UART0, slot1=GPIO0, slot2=SPI0, slot3=cache-maintenance
    // (intercepted in the core), slot4=DDR monitor.
    assign apb_slot_pready_w[0] = uart_pready_w;
    assign apb_slot_pready_w[1] = gpio_pready_w;
    assign apb_slot_pready_w[2] = spi_pready_w;
    assign apb_slot_pready_w[3] = 1'b1;
    assign apb_slot_pready_w[4] = ddr_monitor_pready_w;
    assign apb_slot_pready_w[5] = 1'b1;
    assign apb_slot_pready_w[6] = cam_pready_w;
    assign apb_slot_pready_w[7] = disp_pready_w;
    assign apb_slot_pready_w[8] = 1'b1;
    assign apb_slot_pready_w[9] = 1'b1;
    assign apb_slot_pready_w[10] = 1'b1;
    assign apb_slot_pready_w[11] = 1'b1;
    assign apb_slot_pready_w[12] = pixel_pready_w;
    assign apb_slot_pready_w[13] = 1'b1;
    assign apb_slot_pready_w[14] = 1'b1;
    assign apb_slot_pready_w[15] = 1'b1;
    assign apb_slot_pslverr_w[0] = uart_pslverr_w;
    assign apb_slot_pslverr_w[1] = gpio_pslverr_w;
    assign apb_slot_pslverr_w[2] = spi_pslverr_w;
    assign apb_slot_pslverr_w[3] = 1'b1;
    assign apb_slot_pslverr_w[4] = ddr_monitor_pslverr_w;
    assign apb_slot_pslverr_w[5] = apb_slot_psel_w[5] & apb_d_penable_w;
    assign apb_slot_pslverr_w[6] = cam_pslverr_w;
    assign apb_slot_pslverr_w[7] = disp_pslverr_w;
    assign apb_slot_pslverr_w[8] = apb_slot_psel_w[8] & apb_d_penable_w;
    assign apb_slot_pslverr_w[9] = apb_slot_psel_w[9] & apb_d_penable_w;
    assign apb_slot_pslverr_w[10] = apb_slot_psel_w[10] & apb_d_penable_w;
    assign apb_slot_pslverr_w[11] = apb_slot_psel_w[11] & apb_d_penable_w;
    assign apb_slot_pslverr_w[12] = pixel_pslverr_w;
    assign apb_slot_pslverr_w[13] = apb_slot_psel_w[13] & apb_d_penable_w;
    assign apb_slot_pslverr_w[14] = apb_slot_psel_w[14] & apb_d_penable_w;
    assign apb_slot_pslverr_w[15] = apb_slot_psel_w[15] & apb_d_penable_w;
    assign apb_slot_prdata_w[0*32 +: 32] = uart_prdata_w;
    assign apb_slot_prdata_w[1*32 +: 32] = gpio_prdata_w;
    assign apb_slot_prdata_w[2*32 +: 32] = spi_prdata_w;
    assign apb_slot_prdata_w[3*32 +: 32] = 32'h0;
    assign apb_slot_prdata_w[4*32 +: 32] = ddr_monitor_prdata_w;
    assign apb_slot_prdata_w[5*32 +: 32] = 32'h0;
    assign apb_slot_prdata_w[6*32 +: 32] = cam_prdata_w;
    assign apb_slot_prdata_w[7*32 +: 32] = disp_prdata_w;
    assign apb_slot_prdata_w[8*32 +: 32] = 32'b0;
    assign apb_slot_prdata_w[9*32 +: 32] = 32'b0;
    assign apb_slot_prdata_w[10*32 +: 32] = 32'b0;
    assign apb_slot_prdata_w[11*32 +: 32] = 32'b0;
    assign apb_slot_prdata_w[12*32 +: 32] = pixel_prdata_w;
    assign apb_slot_prdata_w[13*32 +: 32] = 32'b0;
    assign apb_slot_prdata_w[14*32 +: 32] = 32'b0;
    assign apb_slot_prdata_w[15*32 +: 32] = 32'b0;

    apb_mux #(.NUM_SLOTS(16)) u_apb_mux (
        .pclk_i (clk),
        .presetn_i (rst_n),
        .up_paddr_i (apb_paddr_w),
        .up_psel_i (apb_psel_w),
        .up_penable_i (apb_penable_w),
        .up_pwrite_i (apb_pwrite_w),
        .up_pwdata_i (apb_pwdata_w),
        .up_pstrb_i (apb_pstrb_w),
        .up_pready_o (apb_pready_w),
        .up_prdata_o (apb_prdata_w),
        .up_pslverr_o (apb_pslverr_w),
        .pready_i (apb_slot_pready_w),
        .prdata_i (apb_slot_prdata_w),
        .pslverr_i (apb_slot_pslverr_w),
        .psel_o (apb_slot_psel_w),
        .penable_o (apb_d_penable_w),
        .pwrite_o (apb_d_pwrite_w),
        .paddr_o (apb_d_paddr_w),
        .pwdata_o (apb_d_pwdata_w),
        .pstrb_o (apb_d_pstrb_w)
    );

    // Unpopulated slots: complete with PSLVERR so no access hangs (§6.3).
    wire apb_none_w = apb_psel_w && apb_penable_w &&
                      (apb_slot_psel_w == 16'h0);
    assign apb_mux_pready_w  = apb_none_w | apb_pready_w;
    assign apb_mux_pslverr_w = apb_none_w | apb_pslverr_w;

    generate
        if (DDR_MONITOR_ENABLE) begin : gen_ddr_monitor
            edrv32_ddr_monitor u_ddr_monitor (
                .apb_clk_i       (clk),
                .apb_rst_n_i     (rst_n),
                .paddr_i         (apb_d_paddr_w),
                .psel_i          (apb_slot_psel_w[4]),
                .penable_i       (apb_d_penable_w),
                .pwrite_i        (apb_d_pwrite_w),
                .pwdata_i        (apb_d_pwdata_w),
                .pstrb_i         (apb_d_pstrb_w),
                .pready_o        (ddr_monitor_pready_w),
                .prdata_o        (ddr_monitor_prdata_w),
                .pslverr_o       (ddr_monitor_pslverr_w),
                .axi_clk_i       (ddr_bus_clk_i),
                .axi_rst_n_i     (ddr_bus_rst_n_i),
                .m_awid_o        (ddr_mon_awid_o),
                .m_awaddr_o      (ddr_mon_awaddr_o),
                .m_awlen_o       (ddr_mon_awlen_o),
                .m_awsize_o      (ddr_mon_awsize_o),
                .m_awburst_o     (ddr_mon_awburst_o),
                .m_awqos_o       (ddr_mon_awqos_o),
                .m_awvalid_o     (ddr_mon_awvalid_o),
                .m_awready_i     (ddr_mon_awready_i),
                .m_wdata_o       (ddr_mon_wdata_o),
                .m_wstrb_o       (ddr_mon_wstrb_o),
                .m_wlast_o       (ddr_mon_wlast_o),
                .m_wvalid_o      (ddr_mon_wvalid_o),
                .m_wready_i      (ddr_mon_wready_i),
                .m_bid_i         (ddr_mon_bid_i),
                .m_bresp_i       (ddr_mon_bresp_i),
                .m_bvalid_i      (ddr_mon_bvalid_i),
                .m_bready_o      (ddr_mon_bready_o),
                .m_arid_o        (ddr_mon_arid_o),
                .m_araddr_o      (ddr_mon_araddr_o),
                .m_arlen_o       (ddr_mon_arlen_o),
                .m_arsize_o      (ddr_mon_arsize_o),
                .m_arburst_o     (ddr_mon_arburst_o),
                .m_arqos_o       (ddr_mon_arqos_o),
                .m_arvalid_o     (ddr_mon_arvalid_o),
                .m_arready_i     (ddr_mon_arready_i),
                .m_rid_i         (ddr_mon_rid_i),
                .m_rdata_i       (ddr_mon_rdata_i),
                .m_rresp_i       (ddr_mon_rresp_i),
                .m_rlast_i       (ddr_mon_rlast_i),
                .m_rvalid_i      (ddr_mon_rvalid_i),
                .m_rready_o      (ddr_mon_rready_o)
            );
        end else begin : gen_no_ddr_monitor
            assign ddr_monitor_pready_w  = 1'b1;
            assign ddr_monitor_prdata_w  = 32'b0;
            assign ddr_monitor_pslverr_w =
                apb_slot_psel_w[4] & apb_d_penable_w;
            assign ddr_mon_awid_o        = 4'b0;
            assign ddr_mon_awaddr_o      = 32'b0;
            assign ddr_mon_awlen_o       = 8'b0;
            assign ddr_mon_awsize_o      = 3'b0;
            assign ddr_mon_awburst_o     = 2'b0;
            assign ddr_mon_awqos_o       = 4'b0;
            assign ddr_mon_awvalid_o     = 1'b0;
            assign ddr_mon_wdata_o       = 256'b0;
            assign ddr_mon_wstrb_o       = 32'b0;
            assign ddr_mon_wlast_o       = 1'b0;
            assign ddr_mon_wvalid_o      = 1'b0;
            assign ddr_mon_bready_o      = 1'b0;
            assign ddr_mon_arid_o        = 4'b0;
            assign ddr_mon_araddr_o      = 32'b0;
            assign ddr_mon_arlen_o       = 8'b0;
            assign ddr_mon_arsize_o      = 3'b0;
            assign ddr_mon_arburst_o     = 2'b0;
            assign ddr_mon_arqos_o       = 4'b0;
            assign ddr_mon_arvalid_o     = 1'b0;
            assign ddr_mon_rready_o      = 1'b0;
        end
    endgenerate

    generate if (VISION_ENABLE) begin : gen_vision_apb
    edrv32_cam_apb u_cam_apb (
        .clk_i              (clk),
        .rst_n_i            (rst_n),
        .paddr_i            (apb_d_paddr_w),
        .psel_i             (apb_slot_psel_w[6]),
        .penable_i          (apb_d_penable_w),
        .pwrite_i           (apb_d_pwrite_w),
        .pwdata_i           (apb_d_pwdata_w),
        .pstrb_i            (apb_d_pstrb_w),
        .pready_o           (cam_pready_w),
        .prdata_o           (cam_prdata_w),
        .pslverr_o          (cam_pslverr_w),
        .cam0_init_done_i   (vision_cam0_init_done_i),
        .cam1_init_done_i   (vision_cam1_init_done_i),
        .error_i            (vision_cam_error_i),
        .cam0_frame_count_i (vision_cam0_frame_count_i),
        .cam1_frame_count_i (vision_cam1_frame_count_i),
        .cfg_ack_toggle_i   (vision_cam_cfg_ack_toggle_i),
        .cfg_response_error_i(vision_cam_cfg_response_error_i),
        .cfg_response_data_i(vision_cam_cfg_response_data_i),
        .cam0_enable_o      (vision_cam0_enable_o),
        .cam1_enable_o      (vision_cam1_enable_o),
        .cfg_req_toggle_o   (vision_cam_cfg_req_toggle_o),
        .cfg_camera_o       (vision_cam_cfg_camera_o),
        .cfg_read_o         (vision_cam_cfg_read_o),
        .cfg_reg_addr_o     (vision_cam_cfg_reg_addr_o),
        .cfg_write_data_o   (vision_cam_cfg_write_data_o),
        .irq_o              (cam_irq_w)
    );

    edrv32_disp_apb u_disp_apb (
        .clk_i              (clk),
        .rst_n_i            (rst_n),
        .paddr_i            (apb_d_paddr_w),
        .psel_i             (apb_slot_psel_w[7]),
        .penable_i          (apb_d_penable_w),
        .pwrite_i           (apb_d_pwrite_w),
        .pwdata_i           (apb_d_pwdata_w),
        .pstrb_i            (apb_d_pstrb_w),
        .pready_o           (disp_pready_w),
        .prdata_o           (disp_prdata_w),
        .pslverr_o          (disp_pslverr_w),
        .active_buffer_i    (vision_disp_active_buffer_i),
        .error_i            (vision_disp_error_i),
        .frame_count_i      (vision_disp_frame_count_i),
        .underflow_count_i  (vision_disp_underflow_count_i),
        .scanout_frame_count_i(vision_disp_scanout_frame_count_i),
        .debug_status_i     (vision_disp_debug_status_i),
        .buffer0_base_i     (32'h0180_0000),
        .buffer1_base_i     (32'h01a0_0000),
        .buffer2_base_i     (32'h01c0_0000),
        .enable_o           (vision_disp_enable_o),
        .irq_o              (disp_irq_w)
    );

    edrv32_pixel_apb u_pixel_apb (
        .clk_i                    (clk),
        .rst_n_i                  (rst_n),
        .paddr_i                  (apb_d_paddr_w),
        .psel_i                   (apb_slot_psel_w[12]),
        .penable_i                (apb_d_penable_w),
        .pwrite_i                 (apb_d_pwrite_w),
        .pwdata_i                 (apb_d_pwdata_w),
        .pstrb_i                  (apb_d_pstrb_w),
        .pready_o                 (pixel_pready_w),
        .prdata_o                 (pixel_prdata_w),
        .pslverr_o                (pixel_pslverr_w),
        .cfg_ack_toggle_i         (vision_pixel_cfg_ack_toggle_i),
        .frame_count_i            (vision_pixel_frame_count_i),
        .error_count_i            (vision_pixel_error_count_i),
        .cfg_req_toggle_o         (vision_pixel_cfg_req_toggle_o),
        .cfg_enable_o             (vision_pixel_cfg_enable_o),
        .cfg_grayscale_o          (vision_pixel_cfg_grayscale_o),
        .cfg_threshold_enable_o   (vision_pixel_cfg_threshold_enable_o),
        .cfg_invert_o             (vision_pixel_cfg_invert_o),
        .cfg_brightness_o         (vision_pixel_cfg_brightness_o),
        .cfg_contrast_o           (vision_pixel_cfg_contrast_o),
        .cfg_threshold_o          (vision_pixel_cfg_threshold_o),
        .cfg_spatial_enable_o     (vision_pixel_cfg_spatial_enable_o),
        .cfg_spatial_mode_o       (vision_pixel_cfg_spatial_mode_o),
        .cfg_spatial_threshold_o  (vision_pixel_cfg_spatial_threshold_o),
        .irq_o                    (pixel_irq_w)
    );
    end else begin : gen_no_vision_apb
        assign cam_pready_w                    = 1'b1;
        assign cam_prdata_w                    = 32'b0;
        assign cam_pslverr_w                   = apb_slot_psel_w[6] & apb_d_penable_w;
        assign cam_irq_w                       = 1'b0;
        assign disp_pready_w                   = 1'b1;
        assign disp_prdata_w                   = 32'b0;
        assign disp_pslverr_w                  = apb_slot_psel_w[7] & apb_d_penable_w;
        assign disp_irq_w                      = 1'b0;
        assign pixel_pready_w                  = 1'b1;
        assign pixel_prdata_w                  = 32'b0;
        assign pixel_pslverr_w                 = apb_slot_psel_w[12] & apb_d_penable_w;
        assign pixel_irq_w                     = 1'b0;
        assign vision_cam0_enable_o            = 1'b0;
        assign vision_cam1_enable_o            = 1'b0;
        assign vision_cam_cfg_req_toggle_o     = 1'b0;
        assign vision_cam_cfg_camera_o         = 1'b0;
        assign vision_cam_cfg_read_o           = 1'b0;
        assign vision_cam_cfg_reg_addr_o       = 16'b0;
        assign vision_cam_cfg_write_data_o     = 8'b0;
        assign vision_disp_enable_o            = 1'b0;
        assign vision_pixel_cfg_req_toggle_o   = 1'b0;
        assign vision_pixel_cfg_enable_o       = 1'b0;
        assign vision_pixel_cfg_grayscale_o    = 1'b0;
        assign vision_pixel_cfg_threshold_enable_o = 1'b0;
        assign vision_pixel_cfg_invert_o       = 1'b0;
        assign vision_pixel_cfg_brightness_o   = 9'sb0;
        assign vision_pixel_cfg_contrast_o     = 9'b0;
        assign vision_pixel_cfg_threshold_o    = 8'b0;
        assign vision_pixel_cfg_spatial_enable_o = 1'b0;
        assign vision_pixel_cfg_spatial_mode_o = 3'b000;
        assign vision_pixel_cfg_spatial_threshold_o = 8'b0;
    end endgenerate

    wire [31:0] gpio_pin_out_w;
    wire [31:0] gpio_pin_oe_w;
    wire [31:0] gpio_pin_in_w = {16'h0, gpio_in_i};

    uart #(.INSTANCE_ID(0)) u_uart0 (
        .clk(clk),
        .rst_n(rst_n),
        .paddr_i (apb_d_paddr_w),
        .psel_i (apb_slot_psel_w[0]),
        .penable_i (apb_d_penable_w),
        .pwrite_i (apb_d_pwrite_w),
        .pwdata_i (apb_d_pwdata_w),
        .pstrb_i (apb_d_pstrb_w),
        .pready_o (uart_pready_w),
        .prdata_o (uart_prdata_w),
        .pslverr_o (uart_pslverr_w),
        .tx_o (uart0_tx_o),
        .rx_i (uart0_rx_i),
        .rts_o (),
        .cts_i (1'b0),
        .irq_o (uart_irq_w)
    );

    gpio u_gpio0 (
        .clk(clk),
        .rst_n(rst_n),
        .paddr_i (apb_d_paddr_w),
        .psel_i (apb_slot_psel_w[1]),
        .penable_i (apb_d_penable_w),
        .pwrite_i (apb_d_pwrite_w),
        .pwdata_i (apb_d_pwdata_w),
        .pstrb_i (apb_d_pstrb_w),
        .pready_o (gpio_pready_w),
        .prdata_o (gpio_prdata_w),
        .pslverr_o (gpio_pslverr_w),
        .pin_in_i (gpio_pin_in_w),
        .pin_out_o (gpio_pin_out_w),
        .pin_oe_o (gpio_pin_oe_w),
        .irq_o (gpio_irq_w)
    );
    assign gpio_out_o = gpio_pin_out_w[15:0];
    assign gpio_oe_o  = gpio_pin_oe_w[15:0];
    assign spi_cs_n_o = spi_cs_n;

    spi #(.INSTANCE_ID(0)) u_spi0 (
        .clk(clk),
        .rst_n(rst_n),
        .paddr_i (apb_d_paddr_w),
        .psel_i (apb_slot_psel_w[2]),
        .penable_i (apb_d_penable_w),
        .pwrite_i (apb_d_pwrite_w),
        .pwdata_i (apb_d_pwdata_w),
        .pstrb_i (apb_d_pstrb_w),
        .pready_o (spi_pready_w),
        .prdata_o (spi_prdata_w),
        .pslverr_o (spi_pslverr_w),
        .io_i (spi_io_i),
        .io_o (spi_io_o),
        .io_oe_o (spi_io_oe_o),
        .sclk_o (spi_sclk_o),
        .cs_n_o (spi_cs_n),
        .irq_o (spi_irq_w)
    );

    // Board-level ILA probe vector.  Keep the layout stable so captured probes
    // remain comparable when optional performance counters are compiled out.
    assign debug_o[31:0]    = m0_araddr_w;
    assign debug_o[63:32]   = m1_araddr_w;
    assign debug_o[127:64]  = 64'b0;
    assign debug_o[128]     = m0_arvalid_w;
    assign debug_o[129]     = m0_arready_w;
    assign debug_o[130]     = m0_rvalid_w;
    assign debug_o[131]     = m0_rready_w;
    assign debug_o[132]     = m1_arvalid_w;
    assign debug_o[133]     = m1_arready_w;
    assign debug_o[134]     = m1_rvalid_w;
    assign debug_o[135]     = m1_rready_w;
    assign debug_o[136]     = m1_awvalid_w;
    assign debug_o[137]     = m1_awready_w;
    assign debug_o[138]     = m1_wvalid_w;
    assign debug_o[139]     = m1_wready_w;
    assign debug_o[140]     = m1_bvalid_w;
    assign debug_o[141]     = m1_bready_w;
    assign debug_o[143:142] = axi_fs_rd_fail_w;
    assign debug_o[145:144] = axi_fs_wr_fail_w;
    assign debug_o[146]     = ddr_gateway_protocol_error_w;
    assign debug_o[149:147] = 3'b0;
    assign debug_o[150]     = irq_soft_w;
    assign debug_o[151]     = irq_timer_w;
    assign debug_o[152]     = irq_ext_w;
    assign debug_o[153]     = debug_core_sleep_w;
    assign debug_o[154]     = debug_commit_valid_w;
    assign debug_o[159:155] = 5'b0;
    assign debug_o[191:160] = debug_commit_pc_w;
    assign debug_o[223:192] = debug_decode_pc_w;
    assign debug_o[255:224] = debug_decode_instr_w;

    wire unused_commit_debug_w = ^{debug_commit_instr_w,
        debug_commit_exception_w, debug_commit_cause_w};

endmodule
