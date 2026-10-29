// File: edrv32_soc_top.v
// Spec: edrv32-soc-spec 2-6; sys-subsys-spec 2.10; engine-spec 3.
// Description: B2 full SoC integration with media APB and seven DDR master ports.
//              RND is reserved; all other engines connect without optional configurations.
// Clock domains: sys, mem, pix, npu, camera 0/1 and Ethernet RX/TX.
module edrv32_soc_top (
    // Board clocks and global asynchronous reset.
    input wire clk_sys_i,
    input wire clk_mem_i,
    input wire clk_pix_i,
    input wire clk_npu_i,
    input wire cam0_pclk_i,
    input wire cam1_pclk_i,
    input wire eth_rx_clk_i,
    input wire eth_tx_clk_i,
    input wire rst_n_i,
    input wire mem_ready_i,

    // DDR controller AXI256 master (clk_mem), without B/R backpressure.
    output wire [3:0] ddr_awid_o,
    output wire [31:0] ddr_awaddr_o,
    output wire [3:0] ddr_awlen_o,
    output wire ddr_awvalid_o,
    input wire ddr_awready_i,
    output wire [255:0] ddr_wdata_o,
    output wire [31:0] ddr_wstrb_o,
    output wire ddr_wlast_o,
    output wire ddr_wvalid_o,
    input wire ddr_wready_i,
    input wire [3:0] ddr_bid_i,
    input wire [1:0] ddr_bresp_i,
    input wire ddr_bvalid_i,
    output wire [3:0] ddr_arid_o,
    output wire [31:0] ddr_araddr_o,
    output wire [3:0] ddr_arlen_o,
    output wire ddr_arvalid_o,
    input wire ddr_arready_i,
    input wire [3:0] ddr_rid_i,
    input wire [255:0] ddr_rdata_i,
    input wire [1:0] ddr_rresp_i,
    input wire ddr_rlast_i,
    input wire ddr_rvalid_i,

    // DVP camera inputs and GPIO-controlled camera outputs.
    input wire cam0_vsync_i,
    input wire cam0_href_i,
    input wire [7:0] cam0_data_i,
    input wire cam1_vsync_i,
    input wire cam1_href_i,
    input wire [7:0] cam1_data_i,
    output wire cam0_pwdn_o,
    output wire cam0_rst_n_o,
    output wire cam1_pwdn_o,
    output wire cam1_rst_n_o,

    // Open-drain camera control pins; tristate buffers reside in the board layer.
    input wire [1:0] i2c0_scl_i,
    output wire [1:0] i2c0_scl_o,
    output wire [1:0] i2c0_scl_oe_o,
    input wire [1:0] i2c0_sda_i,
    output wire [1:0] i2c0_sda_o,
    output wire [1:0] i2c0_sda_oe_o,

    // Parallel TMDS symbols for the board serializer.
    output wire [29:0] tmds_sym_o,

    // Ethernet MAC-side data and management pins.
    input wire [7:0] eth_rxd_i,
    input wire eth_rx_dv_i,
    input wire eth_rx_er_i,
    output wire [7:0] eth_txd_o,
    output wire eth_tx_en_o,
    output wire eth_tx_er_o,
    output wire eth_mdc_o,
    output wire eth_mdio_o,
    output wire eth_mdio_oe_o,
    input wire eth_mdio_i,
    output wire eth_phy_rst_n_o,

    // System peripherals and CPU debug observation.
    input wire uart0_rx_i,
    output wire uart0_tx_o,
    input wire [15:0] gpio_i,
    output wire [15:0] gpio_o,
    output wire [15:0] gpio_oe_o,
    output wire [63:0] debug_o
);
    // Subsystem buses, domain resets and the VIN/PIX pixel streams.
    wire rst_sys_n_w;
    wire [3:0] iaxi_arid_w;
    wire [31:0] iaxi_araddr_w;
    wire [7:0] iaxi_arlen_w;
    wire [2:0] iaxi_arsize_w;
    wire [1:0] iaxi_arburst_w;
    wire iaxi_arvalid_w;
    wire iaxi_arready_w;
    wire [3:0] iaxi_rid_w;
    wire [63:0] iaxi_rdata_w;
    wire [1:0] iaxi_rresp_w;
    wire iaxi_rlast_w;
    wire iaxi_rvalid_w;
    wire iaxi_rready_w;
    wire [3:0] daxi_awid_w;
    wire [31:0] daxi_awaddr_w;
    wire [7:0] daxi_awlen_w;
    wire [2:0] daxi_awsize_w;
    wire [1:0] daxi_awburst_w;
    wire daxi_awvalid_w;
    wire daxi_awready_w;
    wire [63:0] daxi_wdata_w;
    wire [7:0] daxi_wstrb_w;
    wire daxi_wlast_w;
    wire daxi_wvalid_w;
    wire daxi_wready_w;
    wire [3:0] daxi_bid_w;
    wire [1:0] daxi_bresp_w;
    wire daxi_bvalid_w;
    wire daxi_bready_w;
    wire [3:0] daxi_arid_w;
    wire [31:0] daxi_araddr_w;
    wire [7:0] daxi_arlen_w;
    wire [2:0] daxi_arsize_w;
    wire [1:0] daxi_arburst_w;
    wire daxi_arvalid_w;
    wire daxi_arready_w;
    wire [3:0] daxi_rid_w;
    wire [63:0] daxi_rdata_w;
    wire [1:0] daxi_rresp_w;
    wire daxi_rlast_w;
    wire daxi_rvalid_w;
    wire daxi_rready_w;
    wire [11:0] cache_apb_paddr_w;
    wire cache_apb_psel_w;
    wire cache_apb_penable_w;
    wire cache_apb_pwrite_w;
    wire [31:0] cache_apb_pwdata_w;
    wire [3:0] cache_apb_pstrb_w;
    wire cache_apb_pready_w;
    wire [31:0] cache_apb_prdata_w;
    wire cache_apb_pslverr_w;
    wire irq_meip_w;
    wire irq_msip_w;
    wire irq_mtip_w;
    wire [63:0] mtime_w;
    wire irq_cache_w;
    wire unused_rst_sys_por_n_w;
    wire rst_mem_core_n_w;
    // SoC 5.2 X8: reset is also sampled by the reset-release status synchronizer.
    /* verilator lint_off SYNCASYNCNET */
    wire rst_mem_n_w;
    /* verilator lint_on SYNCASYNCNET */
    wire rst_pix_n_w;
    wire rst_npu_n_w;
    wire rst_cam0_n_w;
    wire rst_cam1_n_w;
    wire rst_eth_rx_n_w;
    wire rst_eth_tx_n_w;
    wire [3:0] gw_awid_w;
    wire [31:0] gw_awaddr_w;
    wire [7:0] gw_awlen_w;
    wire [2:0] gw_awsize_w;
    wire [1:0] gw_awburst_w;
    wire gw_awvalid_w;
    wire gw_awready_w;
    wire [63:0] gw_wdata_w;
    wire [7:0] gw_wstrb_w;
    wire gw_wlast_w;
    wire gw_wvalid_w;
    wire gw_wready_w;
    wire [3:0] gw_bid_w;
    wire [1:0] gw_bresp_w;
    wire gw_bvalid_w;
    wire gw_bready_w;
    wire [3:0] gw_arid_w;
    wire [31:0] gw_araddr_w;
    wire [7:0] gw_arlen_w;
    wire [2:0] gw_arsize_w;
    wire [1:0] gw_arburst_w;
    wire gw_arvalid_w;
    wire gw_arready_w;
    wire [3:0] gw_rid_w;
    wire [63:0] gw_rdata_w;
    wire [1:0] gw_rresp_w;
    wire gw_rlast_w;
    wire gw_rvalid_w;
    wire gw_rready_w;
    wire [11:0] media_apb_paddr_w;
    wire [15:0] media_apb_psel_w;
    wire media_apb_penable_w;
    wire media_apb_pwrite_w;
    wire [31:0] media_apb_pwdata_w;
    wire [3:0] media_apb_pstrb_w;
    wire [511:0] media_apb_prdata_w;
    wire [15:0] media_apb_pready_w;
    wire [15:0] media_apb_pslverr_w;
    wire [15:8] irq_src_w;
    wire unused_sim_exit_valid_w;
    wire [31:0] unused_sim_exit_code_w;
    wire p0_arid_w;
    wire [31:0] p0_araddr_w;
    wire [3:0] p0_arlen_w;
    wire p0_arvalid_w;
    wire p0_arready_w;
    wire p0_rid_w;
    wire [255:0] p0_rdata_w;
    wire [1:0] p0_rresp_w;
    wire p0_rlast_w;
    wire p0_rvalid_w;
    wire p0_rready_w;
    wire p0_urgent_w;
    wire p1_awid_w;
    wire [31:0] p1_awaddr_w;
    wire [3:0] p1_awlen_w;
    wire p1_awvalid_w;
    wire p1_awready_w;
    wire [255:0] p1_wdata_w;
    wire [31:0] p1_wstrb_w;
    wire p1_wlast_w;
    wire p1_wvalid_w;
    wire p1_wready_w;
    wire p1_bid_w;
    wire [1:0] p1_bresp_w;
    wire p1_bvalid_w;
    wire p1_bready_w;
    wire p1_arid_w;
    wire [31:0] p1_araddr_w;
    wire [3:0] p1_arlen_w;
    wire p1_arvalid_w;
    wire p1_arready_w;
    wire p1_rid_w;
    wire [255:0] p1_rdata_w;
    wire [1:0] p1_rresp_w;
    wire p1_rlast_w;
    wire p1_rvalid_w;
    wire p1_rready_w;
    wire p1_urgent_w;
    wire p3_awid_w;
    wire [31:0] p3_awaddr_w;
    wire [3:0] p3_awlen_w;
    wire p3_awvalid_w;
    wire p3_awready_w;
    wire [255:0] p3_wdata_w;
    wire [31:0] p3_wstrb_w;
    wire p3_wlast_w;
    wire p3_wvalid_w;
    wire p3_wready_w;
    wire p3_bid_w;
    wire [1:0] p3_bresp_w;
    wire p3_bvalid_w;
    wire p3_bready_w;
    wire p3_arid_w;
    wire [31:0] p3_araddr_w;
    wire [3:0] p3_arlen_w;
    wire p3_arvalid_w;
    wire p3_arready_w;
    wire p3_rid_w;
    wire [255:0] p3_rdata_w;
    wire [1:0] p3_rresp_w;
    wire p3_rlast_w;
    wire p3_rvalid_w;
    wire p3_rready_w;
    wire unused_p4_awready_w;
    wire unused_p4_wready_w;
    wire unused_p4_bid_w;
    wire [1:0] unused_p4_bresp_w;
    wire unused_p4_bvalid_w;
    wire unused_p4_arready_w;
    wire unused_p4_rid_w;
    wire [255:0] unused_p4_rdata_w;
    wire [1:0] unused_p4_rresp_w;
    wire unused_p4_rlast_w;
    wire unused_p4_rvalid_w;
    wire p5_awid_w;
    wire [31:0] p5_awaddr_w;
    wire [3:0] p5_awlen_w;
    wire p5_awvalid_w;
    wire p5_awready_w;
    wire [255:0] p5_wdata_w;
    wire [31:0] p5_wstrb_w;
    wire p5_wlast_w;
    wire p5_wvalid_w;
    wire p5_wready_w;
    wire p5_bid_w;
    wire [1:0] p5_bresp_w;
    wire p5_bvalid_w;
    wire p5_bready_w;
    wire p5_arid_w;
    wire [31:0] p5_araddr_w;
    wire [3:0] p5_arlen_w;
    wire p5_arvalid_w;
    wire p5_arready_w;
    wire p5_rid_w;
    wire [255:0] p5_rdata_w;
    wire [1:0] p5_rresp_w;
    wire p5_rlast_w;
    wire p5_rvalid_w;
    wire p5_rready_w;
    wire eth_awid_w;
    wire [31:0] eth_awaddr_w;
    wire [3:0] eth_awlen_w;
    wire eth_awvalid_w;
    wire eth_awready_w;
    wire [255:0] eth_wdata_w;
    wire [31:0] eth_wstrb_w;
    wire eth_wlast_w;
    wire eth_wvalid_w;
    wire eth_wready_w;
    wire eth_bid_w;
    wire [1:0] eth_bresp_w;
    wire eth_bvalid_w;
    wire eth_bready_w;
    wire eth_arid_w;
    wire [31:0] eth_araddr_w;
    wire [3:0] eth_arlen_w;
    wire eth_arvalid_w;
    wire eth_arready_w;
    wire eth_rid_w;
    wire [255:0] eth_rdata_w;
    wire [1:0] eth_rresp_w;
    wire eth_rlast_w;
    wire eth_rvalid_w;
    wire eth_rready_w;
    wire pix_in_valid_w;
    wire pix_in_ready_w;
    wire [31:0] pix_in_data_w;
    wire pix_in_sof_w;
    wire pix_in_eol_w;
    wire pix_in_eof_w;
    wire pix_out_valid_w;
    wire pix_out_ready_w;
    wire [31:0] pix_out_data_w;
    wire pix_out_sof_w;
    wire pix_out_eol_w;
    wire pix_out_eof_w;

    // SoC 6.1: RND is absent and reserved APB slots return SLVERR.
    assign irq_src_w[11] = 1'b0;
    assign media_apb_prdata_w[0 +: 32] = 32'b0;
    assign media_apb_pready_w[0] = 1'b1;
    assign media_apb_pslverr_w[0] = 1'b1;
    assign media_apb_prdata_w[128 +: 32] = 32'b0;
    assign media_apb_pready_w[4] = 1'b1;
    assign media_apb_pslverr_w[4] = 1'b1;
    assign media_apb_prdata_w[320 +: 32] = 32'b0;
    assign media_apb_pready_w[10] = 1'b1;
    assign media_apb_pslverr_w[10] = 1'b1;
    assign media_apb_prdata_w[352 +: 32] = 32'b0;
    assign media_apb_pready_w[11] = 1'b1;
    assign media_apb_pslverr_w[11] = 1'b1;
    assign media_apb_prdata_w[384 +: 32] = 32'b0;
    assign media_apb_pready_w[12] = 1'b1;
    assign media_apb_pslverr_w[12] = 1'b1;
    assign media_apb_prdata_w[416 +: 32] = 32'b0;
    assign media_apb_pready_w[13] = 1'b1;
    assign media_apb_pslverr_w[13] = 1'b1;
    assign media_apb_prdata_w[448 +: 32] = 32'b0;
    assign media_apb_pready_w[14] = 1'b1;
    assign media_apb_pslverr_w[14] = 1'b1;
    assign media_apb_prdata_w[480 +: 32] = 32'b0;
    assign media_apb_pready_w[15] = 1'b1;
    assign media_apb_pslverr_w[15] = 1'b1;

    wire unused_media_psel_w;
    assign unused_media_psel_w = |{media_apb_psel_w[15:10], media_apb_psel_w[4],
        media_apb_psel_w[0]};

    // SoC 3.5: the board camera control pins mirror GPIO0 outputs 12 through 15.
    assign cam0_pwdn_o = gpio_o[12];
    assign cam0_rst_n_o = gpio_o[13];
    assign cam1_pwdn_o = gpio_o[14];
    assign cam1_rst_n_o = gpio_o[15];

    // CPU interfaces retain their owning subsystem and engine signal stems.
    edrv32_cpu_subsys u_cpu (

        // Clock and reset domains.
        .clk_i(clk_sys_i),
        .rst_n_i(rst_sys_n_w),

        // iaxi interface.
        .iaxi_arid_o(iaxi_arid_w),
        .iaxi_araddr_o(iaxi_araddr_w),
        .iaxi_arlen_o(iaxi_arlen_w),
        .iaxi_arsize_o(iaxi_arsize_w),
        .iaxi_arburst_o(iaxi_arburst_w),
        .iaxi_arvalid_o(iaxi_arvalid_w),
        .iaxi_arready_i(iaxi_arready_w),
        .iaxi_rid_i(iaxi_rid_w),
        .iaxi_rdata_i(iaxi_rdata_w),
        .iaxi_rresp_i(iaxi_rresp_w),
        .iaxi_rlast_i(iaxi_rlast_w),
        .iaxi_rvalid_i(iaxi_rvalid_w),
        .iaxi_rready_o(iaxi_rready_w),

        // daxi interface.
        .daxi_awid_o(daxi_awid_w),
        .daxi_awaddr_o(daxi_awaddr_w),
        .daxi_awlen_o(daxi_awlen_w),
        .daxi_awsize_o(daxi_awsize_w),
        .daxi_awburst_o(daxi_awburst_w),
        .daxi_awvalid_o(daxi_awvalid_w),
        .daxi_awready_i(daxi_awready_w),
        .daxi_wdata_o(daxi_wdata_w),
        .daxi_wstrb_o(daxi_wstrb_w),
        .daxi_wlast_o(daxi_wlast_w),
        .daxi_wvalid_o(daxi_wvalid_w),
        .daxi_wready_i(daxi_wready_w),
        .daxi_bid_i(daxi_bid_w),
        .daxi_bresp_i(daxi_bresp_w),
        .daxi_bvalid_i(daxi_bvalid_w),
        .daxi_bready_o(daxi_bready_w),
        .daxi_arid_o(daxi_arid_w),
        .daxi_araddr_o(daxi_araddr_w),
        .daxi_arlen_o(daxi_arlen_w),
        .daxi_arsize_o(daxi_arsize_w),
        .daxi_arburst_o(daxi_arburst_w),
        .daxi_arvalid_o(daxi_arvalid_w),
        .daxi_arready_i(daxi_arready_w),
        .daxi_rid_i(daxi_rid_w),
        .daxi_rdata_i(daxi_rdata_w),
        .daxi_rresp_i(daxi_rresp_w),
        .daxi_rlast_i(daxi_rlast_w),
        .daxi_rvalid_i(daxi_rvalid_w),
        .daxi_rready_o(daxi_rready_w),

        // APB engine control.
        .apb_paddr_i(cache_apb_paddr_w),
        .apb_psel_i(cache_apb_psel_w),
        .apb_penable_i(cache_apb_penable_w),
        .apb_pwrite_i(cache_apb_pwrite_w),
        .apb_pwdata_i(cache_apb_pwdata_w),
        .apb_pstrb_i(cache_apb_pstrb_w),
        .apb_pready_o(cache_apb_pready_w),
        .apb_prdata_o(cache_apb_prdata_w),
        .apb_pslverr_o(cache_apb_pslverr_w),

        // irq interface.
        .irq_meip_i(irq_meip_w),
        .irq_msip_i(irq_msip_w),
        .irq_mtip_i(irq_mtip_w),

        // mtime interface.
        .mtime_i(mtime_w),

        // debug interface.
        .debug_o(debug_o),

        // irq interface.
        .irq_o(irq_cache_w)
    );

    // SYS interfaces retain their owning subsystem and engine signal stems.
    edrv32_sys_subsys u_sys (

        // Clock and reset domains.
        .clk_sys_i(clk_sys_i),
        .clk_mem_i(clk_mem_i),
        .clk_pix_i(clk_pix_i),
        .clk_npu_i(clk_npu_i),
        .cam0_pclk_i(cam0_pclk_i),
        .cam1_pclk_i(cam1_pclk_i),
        .eth_rx_clk_i(eth_rx_clk_i),
        .eth_tx_clk_i(eth_tx_clk_i),
        .rst_n_i(rst_n_i),
        .mem_ready_i(mem_ready_i),
        .rst_sys_por_n_o(unused_rst_sys_por_n_w),
        .rst_sys_n_o(rst_sys_n_w),
        .rst_mem_core_n_o(rst_mem_core_n_w),
        .rst_mem_n_o(rst_mem_n_w),
        .rst_pix_n_o(rst_pix_n_w),
        .rst_npu_n_o(rst_npu_n_w),
        .rst_cam0_n_o(rst_cam0_n_w),
        .rst_cam1_n_o(rst_cam1_n_w),
        .rst_eth_rx_n_o(rst_eth_rx_n_w),
        .rst_eth_tx_n_o(rst_eth_tx_n_w),

        // m0 interface.
        .m0_arid_i(iaxi_arid_w),
        .m0_araddr_i(iaxi_araddr_w),
        .m0_arlen_i(iaxi_arlen_w),
        .m0_arsize_i(iaxi_arsize_w),
        .m0_arburst_i(iaxi_arburst_w),
        .m0_arvalid_i(iaxi_arvalid_w),
        .m0_arready_o(iaxi_arready_w),
        .m0_rid_o(iaxi_rid_w),
        .m0_rdata_o(iaxi_rdata_w),
        .m0_rresp_o(iaxi_rresp_w),
        .m0_rlast_o(iaxi_rlast_w),
        .m0_rvalid_o(iaxi_rvalid_w),
        .m0_rready_i(iaxi_rready_w),

        // m1 interface.
        .m1_awid_i(daxi_awid_w),
        .m1_awaddr_i(daxi_awaddr_w),
        .m1_awlen_i(daxi_awlen_w),
        .m1_awsize_i(daxi_awsize_w),
        .m1_awburst_i(daxi_awburst_w),
        .m1_awvalid_i(daxi_awvalid_w),
        .m1_awready_o(daxi_awready_w),
        .m1_wdata_i(daxi_wdata_w),
        .m1_wstrb_i(daxi_wstrb_w),
        .m1_wlast_i(daxi_wlast_w),
        .m1_wvalid_i(daxi_wvalid_w),
        .m1_wready_o(daxi_wready_w),
        .m1_bid_o(daxi_bid_w),
        .m1_bresp_o(daxi_bresp_w),
        .m1_bvalid_o(daxi_bvalid_w),
        .m1_bready_i(daxi_bready_w),
        .m1_arid_i(daxi_arid_w),
        .m1_araddr_i(daxi_araddr_w),
        .m1_arlen_i(daxi_arlen_w),
        .m1_arsize_i(daxi_arsize_w),
        .m1_arburst_i(daxi_arburst_w),
        .m1_arvalid_i(daxi_arvalid_w),
        .m1_arready_o(daxi_arready_w),
        .m1_rid_o(daxi_rid_w),
        .m1_rdata_o(daxi_rdata_w),
        .m1_rresp_o(daxi_rresp_w),
        .m1_rlast_o(daxi_rlast_w),
        .m1_rvalid_o(daxi_rvalid_w),
        .m1_rready_i(daxi_rready_w),

        // s6 interface.
        .s6_awid_o(gw_awid_w),
        .s6_awaddr_o(gw_awaddr_w),
        .s6_awlen_o(gw_awlen_w),
        .s6_awsize_o(gw_awsize_w),
        .s6_awburst_o(gw_awburst_w),
        .s6_awvalid_o(gw_awvalid_w),
        .s6_awready_i(gw_awready_w),
        .s6_wdata_o(gw_wdata_w),
        .s6_wstrb_o(gw_wstrb_w),
        .s6_wlast_o(gw_wlast_w),
        .s6_wvalid_o(gw_wvalid_w),
        .s6_wready_i(gw_wready_w),
        .s6_bid_i(gw_bid_w),
        .s6_bresp_i(gw_bresp_w),
        .s6_bvalid_i(gw_bvalid_w),
        .s6_bready_o(gw_bready_w),
        .s6_arid_o(gw_arid_w),
        .s6_araddr_o(gw_araddr_w),
        .s6_arlen_o(gw_arlen_w),
        .s6_arsize_o(gw_arsize_w),
        .s6_arburst_o(gw_arburst_w),
        .s6_arvalid_o(gw_arvalid_w),
        .s6_arready_i(gw_arready_w),
        .s6_rid_i(gw_rid_w),
        .s6_rdata_i(gw_rdata_w),
        .s6_rresp_i(gw_rresp_w),
        .s6_rlast_i(gw_rlast_w),
        .s6_rvalid_i(gw_rvalid_w),
        .s6_rready_o(gw_rready_w),

        // APB media slots.
        .media_apb_paddr_o(media_apb_paddr_w),
        .media_apb_psel_o(media_apb_psel_w),
        .media_apb_penable_o(media_apb_penable_w),
        .media_apb_pwrite_o(media_apb_pwrite_w),
        .media_apb_pwdata_o(media_apb_pwdata_w),
        .media_apb_pstrb_o(media_apb_pstrb_w),
        .media_apb_prdata_i(media_apb_prdata_w),
        .media_apb_pready_i(media_apb_pready_w),
        .media_apb_pslverr_i(media_apb_pslverr_w),

        // APB cache control.
        .cache_apb_paddr_o(cache_apb_paddr_w),
        .cache_apb_psel_o(cache_apb_psel_w),
        .cache_apb_penable_o(cache_apb_penable_w),
        .cache_apb_pwrite_o(cache_apb_pwrite_w),
        .cache_apb_pwdata_o(cache_apb_pwdata_w),
        .cache_apb_pstrb_o(cache_apb_pstrb_w),
        .cache_apb_prdata_i(cache_apb_prdata_w),
        .cache_apb_pready_i(cache_apb_pready_w),
        .cache_apb_pslverr_i(cache_apb_pslverr_w),

        // irq interface.
        .irq_cache_i(irq_cache_w),
        .irq_src_i(irq_src_w),

        // mtime interface.
        .mtime_o(mtime_w),

        // irq interface.
        .irq_mtip_o(irq_mtip_w),
        .irq_msip_o(irq_msip_w),
        .irq_meip_o(irq_meip_w),

        // uart0 interface.
        .uart0_rx_i(uart0_rx_i),
        .uart0_tx_o(uart0_tx_o),

        // gpio interface.
        .gpio_i(gpio_i),
        .gpio_o(gpio_o),
        .gpio_oe_o(gpio_oe_o),

        // i2c0 interface.
        .i2c0_scl_i(i2c0_scl_i),
        .i2c0_scl_o(i2c0_scl_o),
        .i2c0_scl_oe_o(i2c0_scl_oe_o),
        .i2c0_sda_i(i2c0_sda_i),
        .i2c0_sda_o(i2c0_sda_o),
        .i2c0_sda_oe_o(i2c0_sda_oe_o),

        // sim interface.
        .sim_exit_valid_o(unused_sim_exit_valid_w),
        .sim_exit_code_o(unused_sim_exit_code_w)
    );

    // MEM interfaces retain their owning subsystem and engine signal stems.
    edrv32_mem_subsys u_mem (

        // Clock and reset domains.
        .clk_sys_i(clk_sys_i),
        .clk_mem_i(clk_mem_i),
        .rst_sys_n_i(rst_sys_n_w),
        .rst_mem_core_n_i(rst_mem_core_n_w),

        // gw interface.
        .gw_awid_i(gw_awid_w),
        .gw_awaddr_i(gw_awaddr_w),
        .gw_awlen_i(gw_awlen_w),
        .gw_awvalid_i(gw_awvalid_w),
        .gw_awready_o(gw_awready_w),
        .gw_wdata_i(gw_wdata_w),
        .gw_wstrb_i(gw_wstrb_w),
        .gw_wlast_i(gw_wlast_w),
        .gw_wvalid_i(gw_wvalid_w),
        .gw_wready_o(gw_wready_w),
        .gw_bid_o(gw_bid_w),
        .gw_bresp_o(gw_bresp_w),
        .gw_bvalid_o(gw_bvalid_w),
        .gw_bready_i(gw_bready_w),
        .gw_arid_i(gw_arid_w),
        .gw_araddr_i(gw_araddr_w),
        .gw_arlen_i(gw_arlen_w),
        .gw_arvalid_i(gw_arvalid_w),
        .gw_arready_o(gw_arready_w),
        .gw_rid_o(gw_rid_w),
        .gw_rdata_o(gw_rdata_w),
        .gw_rresp_o(gw_rresp_w),
        .gw_rlast_o(gw_rlast_w),
        .gw_rvalid_o(gw_rvalid_w),
        .gw_rready_i(gw_rready_w),
        .gw_awsize_i(gw_awsize_w),
        .gw_awburst_i(gw_awburst_w),
        .gw_arsize_i(gw_arsize_w),
        .gw_arburst_i(gw_arburst_w),

        // p0 interface.
        .p0_arid_i(p0_arid_w),
        .p0_araddr_i(p0_araddr_w),
        .p0_arlen_i(p0_arlen_w),
        .p0_arvalid_i(p0_arvalid_w),
        .p0_arready_o(p0_arready_w),
        .p0_rid_o(p0_rid_w),
        .p0_rdata_o(p0_rdata_w),
        .p0_rresp_o(p0_rresp_w),
        .p0_rlast_o(p0_rlast_w),
        .p0_rvalid_o(p0_rvalid_w),
        .p0_rready_i(p0_rready_w),
        .p0_urgent_i(p0_urgent_w),

        // p1 interface.
        .p1_awid_i(p1_awid_w),
        .p1_awaddr_i(p1_awaddr_w),
        .p1_awlen_i(p1_awlen_w),
        .p1_awvalid_i(p1_awvalid_w),
        .p1_awready_o(p1_awready_w),
        .p1_wdata_i(p1_wdata_w),
        .p1_wstrb_i(p1_wstrb_w),
        .p1_wlast_i(p1_wlast_w),
        .p1_wvalid_i(p1_wvalid_w),
        .p1_wready_o(p1_wready_w),
        .p1_bid_o(p1_bid_w),
        .p1_bresp_o(p1_bresp_w),
        .p1_bvalid_o(p1_bvalid_w),
        .p1_bready_i(p1_bready_w),
        .p1_arid_i(p1_arid_w),
        .p1_araddr_i(p1_araddr_w),
        .p1_arlen_i(p1_arlen_w),
        .p1_arvalid_i(p1_arvalid_w),
        .p1_arready_o(p1_arready_w),
        .p1_rid_o(p1_rid_w),
        .p1_rdata_o(p1_rdata_w),
        .p1_rresp_o(p1_rresp_w),
        .p1_rlast_o(p1_rlast_w),
        .p1_rvalid_o(p1_rvalid_w),
        .p1_rready_i(p1_rready_w),
        .p1_urgent_i(p1_urgent_w),

        // p3 interface.
        .p3_awid_i(p3_awid_w),
        .p3_awaddr_i(p3_awaddr_w),
        .p3_awlen_i(p3_awlen_w),
        .p3_awvalid_i(p3_awvalid_w),
        .p3_awready_o(p3_awready_w),
        .p3_wdata_i(p3_wdata_w),
        .p3_wstrb_i(p3_wstrb_w),
        .p3_wlast_i(p3_wlast_w),
        .p3_wvalid_i(p3_wvalid_w),
        .p3_wready_o(p3_wready_w),
        .p3_bid_o(p3_bid_w),
        .p3_bresp_o(p3_bresp_w),
        .p3_bvalid_o(p3_bvalid_w),
        .p3_bready_i(p3_bready_w),
        .p3_arid_i(p3_arid_w),
        .p3_araddr_i(p3_araddr_w),
        .p3_arlen_i(p3_arlen_w),
        .p3_arvalid_i(p3_arvalid_w),
        .p3_arready_o(p3_arready_w),
        .p3_rid_o(p3_rid_w),
        .p3_rdata_o(p3_rdata_w),
        .p3_rresp_o(p3_rresp_w),
        .p3_rlast_o(p3_rlast_w),
        .p3_rvalid_o(p3_rvalid_w),
        .p3_rready_i(p3_rready_w),

        // p4 interface.
        .p4_awid_i(1'b0),
        .p4_awaddr_i(32'b0),
        .p4_awlen_i(4'b0),
        .p4_awvalid_i(1'b0),
        .p4_awready_o(unused_p4_awready_w),
        .p4_wdata_i(256'b0),
        .p4_wstrb_i(32'b0),
        .p4_wlast_i(1'b0),
        .p4_wvalid_i(1'b0),
        .p4_wready_o(unused_p4_wready_w),
        .p4_bid_o(unused_p4_bid_w),
        .p4_bresp_o(unused_p4_bresp_w),
        .p4_bvalid_o(unused_p4_bvalid_w),
        .p4_bready_i(1'b1),
        .p4_arid_i(1'b0),
        .p4_araddr_i(32'b0),
        .p4_arlen_i(4'b0),
        .p4_arvalid_i(1'b0),
        .p4_arready_o(unused_p4_arready_w),
        .p4_rid_o(unused_p4_rid_w),
        .p4_rdata_o(unused_p4_rdata_w),
        .p4_rresp_o(unused_p4_rresp_w),
        .p4_rlast_o(unused_p4_rlast_w),
        .p4_rvalid_o(unused_p4_rvalid_w),
        .p4_rready_i(1'b1),

        // p5 interface.
        .p5_awid_i(p5_awid_w),
        .p5_awaddr_i(p5_awaddr_w),
        .p5_awlen_i(p5_awlen_w),
        .p5_awvalid_i(p5_awvalid_w),
        .p5_awready_o(p5_awready_w),
        .p5_wdata_i(p5_wdata_w),
        .p5_wstrb_i(p5_wstrb_w),
        .p5_wlast_i(p5_wlast_w),
        .p5_wvalid_i(p5_wvalid_w),
        .p5_wready_o(p5_wready_w),
        .p5_bid_o(p5_bid_w),
        .p5_bresp_o(p5_bresp_w),
        .p5_bvalid_o(p5_bvalid_w),
        .p5_bready_i(p5_bready_w),
        .p5_arid_i(p5_arid_w),
        .p5_araddr_i(p5_araddr_w),
        .p5_arlen_i(p5_arlen_w),
        .p5_arvalid_i(p5_arvalid_w),
        .p5_arready_o(p5_arready_w),
        .p5_rid_o(p5_rid_w),
        .p5_rdata_o(p5_rdata_w),
        .p5_rresp_o(p5_rresp_w),
        .p5_rlast_o(p5_rlast_w),
        .p5_rvalid_o(p5_rvalid_w),
        .p5_rready_i(p5_rready_w),

        // eth interface.
        .eth_awid_i(eth_awid_w),
        .eth_awaddr_i(eth_awaddr_w),
        .eth_awlen_i(eth_awlen_w),
        .eth_awvalid_i(eth_awvalid_w),
        .eth_awready_o(eth_awready_w),
        .eth_wdata_i(eth_wdata_w),
        .eth_wstrb_i(eth_wstrb_w),
        .eth_wlast_i(eth_wlast_w),
        .eth_wvalid_i(eth_wvalid_w),
        .eth_wready_o(eth_wready_w),
        .eth_bid_o(eth_bid_w),
        .eth_bresp_o(eth_bresp_w),
        .eth_bvalid_o(eth_bvalid_w),
        .eth_bready_i(eth_bready_w),
        .eth_arid_i(eth_arid_w),
        .eth_araddr_i(eth_araddr_w),
        .eth_arlen_i(eth_arlen_w),
        .eth_arvalid_i(eth_arvalid_w),
        .eth_arready_o(eth_arready_w),
        .eth_rid_o(eth_rid_w),
        .eth_rdata_o(eth_rdata_w),
        .eth_rresp_o(eth_rresp_w),
        .eth_rlast_o(eth_rlast_w),
        .eth_rvalid_o(eth_rvalid_w),
        .eth_rready_i(eth_rready_w),

        // ddr interface.
        .ddr_awid_o(ddr_awid_o),
        .ddr_awaddr_o(ddr_awaddr_o),
        .ddr_awlen_o(ddr_awlen_o),
        .ddr_awvalid_o(ddr_awvalid_o),
        .ddr_awready_i(ddr_awready_i),
        .ddr_wdata_o(ddr_wdata_o),
        .ddr_wstrb_o(ddr_wstrb_o),
        .ddr_wlast_o(ddr_wlast_o),
        .ddr_wvalid_o(ddr_wvalid_o),
        .ddr_wready_i(ddr_wready_i),
        .ddr_bid_i(ddr_bid_i),
        .ddr_bresp_i(ddr_bresp_i),
        .ddr_bvalid_i(ddr_bvalid_i),
        .ddr_arid_o(ddr_arid_o),
        .ddr_araddr_o(ddr_araddr_o),
        .ddr_arlen_o(ddr_arlen_o),
        .ddr_arvalid_o(ddr_arvalid_o),
        .ddr_arready_i(ddr_arready_i),
        .ddr_rid_i(ddr_rid_i),
        .ddr_rdata_i(ddr_rdata_i),
        .ddr_rresp_i(ddr_rresp_i),
        .ddr_rlast_i(ddr_rlast_i),
        .ddr_rvalid_i(ddr_rvalid_i),

        // APB memory fabric control.
        .xbar_apb_paddr_i(media_apb_paddr_w),
        .xbar_apb_psel_i(media_apb_psel_w[8]),
        .xbar_apb_penable_i(media_apb_penable_w),
        .xbar_apb_pwrite_i(media_apb_pwrite_w),
        .xbar_apb_pwdata_i(media_apb_pwdata_w),
        .xbar_apb_pstrb_i(media_apb_pstrb_w),
        .xbar_apb_pready_o(media_apb_pready_w[8]),
        .xbar_apb_prdata_o(media_apb_prdata_w[256 +: 32]),
        .xbar_apb_pslverr_o(media_apb_pslverr_w[8]),

        // APB performance monitor control.
        .pmon_apb_paddr_i(media_apb_paddr_w),
        .pmon_apb_psel_i(media_apb_psel_w[9]),
        .pmon_apb_penable_i(media_apb_penable_w),
        .pmon_apb_pwrite_i(media_apb_pwrite_w),
        .pmon_apb_pwdata_i(media_apb_pwdata_w),
        .pmon_apb_pstrb_i(media_apb_pstrb_w),
        .pmon_apb_pready_o(media_apb_pready_w[9]),
        .pmon_apb_prdata_o(media_apb_prdata_w[288 +: 32]),
        .pmon_apb_pslverr_o(media_apb_pslverr_w[9]),

        // irq interface.
        .irq_mem_xbar_o(irq_src_w[15])
    );

    // VIN interfaces retain their owning subsystem and engine signal stems.
    edrv32_vin u_vin (

        // Clock and reset domains.
        .clk_mem_i(clk_mem_i),
        .rst_mem_n_i(rst_mem_n_w),
        .cam0_pclk_i(cam0_pclk_i),
        .rst_cam0_n_i(rst_cam0_n_w),

        // cam0 interface.
        .cam0_vsync_i(cam0_vsync_i),
        .cam0_href_i(cam0_href_i),
        .cam0_data_i(cam0_data_i),

        // Clock and reset domains.
        .cam1_pclk_i(cam1_pclk_i),
        .rst_cam1_n_i(rst_cam1_n_w),

        // cam1 interface.
        .cam1_vsync_i(cam1_vsync_i),
        .cam1_href_i(cam1_href_i),
        .cam1_data_i(cam1_data_i),

        // APB engine control.
        .apb_paddr_i(media_apb_paddr_w),
        .apb_psel_i(media_apb_psel_w[1]),
        .apb_penable_i(media_apb_penable_w),
        .apb_pwrite_i(media_apb_pwrite_w),
        .apb_pwdata_i(media_apb_pwdata_w),
        .apb_pstrb_i(media_apb_pstrb_w),
        .apb_pready_o(media_apb_pready_w[1]),
        .apb_prdata_o(media_apb_prdata_w[32 +: 32]),
        .apb_pslverr_o(media_apb_pslverr_w[1]),

        // p1 interface.
        .p1_awid_o(p1_awid_w),
        .p1_awaddr_o(p1_awaddr_w),
        .p1_awlen_o(p1_awlen_w),
        .p1_awvalid_o(p1_awvalid_w),
        .p1_awready_i(p1_awready_w),
        .p1_wdata_o(p1_wdata_w),
        .p1_wstrb_o(p1_wstrb_w),
        .p1_wlast_o(p1_wlast_w),
        .p1_wvalid_o(p1_wvalid_w),
        .p1_wready_i(p1_wready_w),
        .p1_bid_i(p1_bid_w),
        .p1_bresp_i(p1_bresp_w),
        .p1_bvalid_i(p1_bvalid_w),
        .p1_bready_o(p1_bready_w),
        .p1_arid_o(p1_arid_w),
        .p1_araddr_o(p1_araddr_w),
        .p1_arlen_o(p1_arlen_w),
        .p1_arvalid_o(p1_arvalid_w),
        .p1_arready_i(p1_arready_w),
        .p1_rid_i(p1_rid_w),
        .p1_rdata_i(p1_rdata_w),
        .p1_rresp_i(p1_rresp_w),
        .p1_rlast_i(p1_rlast_w),
        .p1_rvalid_i(p1_rvalid_w),
        .p1_rready_o(p1_rready_w),
        .p1_urgent_o(p1_urgent_w),

        // Pixel stream.
        .pix_in_valid_o(pix_in_valid_w),
        .pix_in_ready_i(pix_in_ready_w),
        .pix_in_data_o(pix_in_data_w),
        .pix_in_sof_o(pix_in_sof_w),
        .pix_in_eol_o(pix_in_eol_w),
        .pix_in_eof_o(pix_in_eof_w),
        .pix_out_valid_i(pix_out_valid_w),
        .pix_out_ready_o(pix_out_ready_w),
        .pix_out_data_i(pix_out_data_w),
        .pix_out_sof_i(pix_out_sof_w),
        .pix_out_eol_i(pix_out_eol_w),
        .pix_out_eof_i(pix_out_eof_w),

        // irq interface.
        .irq_o(irq_src_w[8])
    );

    // PIX interfaces retain their owning subsystem and engine signal stems.
    edrv32_pix u_pix (

        // Clock and reset domains.
        .clk_mem_i(clk_mem_i),
        .rst_mem_n_i(rst_mem_n_w),

        // Pixel stream.
        .pix_in_valid_i(pix_in_valid_w),
        .pix_in_ready_o(pix_in_ready_w),
        .pix_in_data_i(pix_in_data_w),
        .pix_in_sof_i(pix_in_sof_w),
        .pix_in_eol_i(pix_in_eol_w),
        .pix_in_eof_i(pix_in_eof_w),
        .pix_out_valid_o(pix_out_valid_w),
        .pix_out_ready_i(pix_out_ready_w),
        .pix_out_data_o(pix_out_data_w),
        .pix_out_sof_o(pix_out_sof_w),
        .pix_out_eol_o(pix_out_eol_w),
        .pix_out_eof_o(pix_out_eof_w),

        // APB engine control.
        .apb_paddr_i(media_apb_paddr_w),
        .apb_psel_i(media_apb_psel_w[2]),
        .apb_penable_i(media_apb_penable_w),
        .apb_pwrite_i(media_apb_pwrite_w),
        .apb_pwdata_i(media_apb_pwdata_w),
        .apb_pstrb_i(media_apb_pstrb_w),
        .apb_pready_o(media_apb_pready_w[2]),
        .apb_prdata_o(media_apb_prdata_w[64 +: 32]),
        .apb_pslverr_o(media_apb_pslverr_w[2]),

        // irq interface.
        .irq_o(irq_src_w[9])
    );

    // GEO interfaces retain their owning subsystem and engine signal stems.
    edrv32_geo u_geo (

        // Clock and reset domains.
        .clk_mem_i(clk_mem_i),
        .rst_mem_n_i(rst_mem_n_w),

        // APB engine control.
        .apb_paddr_i(media_apb_paddr_w),
        .apb_psel_i(media_apb_psel_w[3]),
        .apb_penable_i(media_apb_penable_w),
        .apb_pwrite_i(media_apb_pwrite_w),
        .apb_pwdata_i(media_apb_pwdata_w),
        .apb_pstrb_i(media_apb_pstrb_w),
        .apb_pready_o(media_apb_pready_w[3]),
        .apb_prdata_o(media_apb_prdata_w[96 +: 32]),
        .apb_pslverr_o(media_apb_pslverr_w[3]),

        // p5 interface.
        .p5_awid_o(p5_awid_w),
        .p5_awaddr_o(p5_awaddr_w),
        .p5_awlen_o(p5_awlen_w),
        .p5_awvalid_o(p5_awvalid_w),
        .p5_awready_i(p5_awready_w),
        .p5_wdata_o(p5_wdata_w),
        .p5_wstrb_o(p5_wstrb_w),
        .p5_wlast_o(p5_wlast_w),
        .p5_wvalid_o(p5_wvalid_w),
        .p5_wready_i(p5_wready_w),
        .p5_bid_i(p5_bid_w),
        .p5_bresp_i(p5_bresp_w),
        .p5_bvalid_i(p5_bvalid_w),
        .p5_bready_o(p5_bready_w),
        .p5_arid_o(p5_arid_w),
        .p5_araddr_o(p5_araddr_w),
        .p5_arlen_o(p5_arlen_w),
        .p5_arvalid_o(p5_arvalid_w),
        .p5_arready_i(p5_arready_w),
        .p5_rid_i(p5_rid_w),
        .p5_rdata_i(p5_rdata_w),
        .p5_rresp_i(p5_rresp_w),
        .p5_rlast_i(p5_rlast_w),
        .p5_rvalid_i(p5_rvalid_w),
        .p5_rready_o(p5_rready_w),

        // irq interface.
        .irq_o(irq_src_w[10])
    );

    // DISP interfaces retain their owning subsystem and engine signal stems.
    edrv32_disp u_disp (

        // Clock and reset domains.
        .clk_mem_i(clk_mem_i),
        .rst_mem_n_i(rst_mem_n_w),
        .clk_pix_i(clk_pix_i),
        .rst_pix_n_i(rst_pix_n_w),

        // APB engine control.
        .apb_paddr_i(media_apb_paddr_w),
        .apb_psel_i(media_apb_psel_w[5]),
        .apb_penable_i(media_apb_penable_w),
        .apb_pwrite_i(media_apb_pwrite_w),
        .apb_pwdata_i(media_apb_pwdata_w),
        .apb_pstrb_i(media_apb_pstrb_w),
        .apb_pready_o(media_apb_pready_w[5]),
        .apb_prdata_o(media_apb_prdata_w[160 +: 32]),
        .apb_pslverr_o(media_apb_pslverr_w[5]),

        // p0 interface.
        .p0_arid_o(p0_arid_w),
        .p0_araddr_o(p0_araddr_w),
        .p0_arlen_o(p0_arlen_w),
        .p0_arvalid_o(p0_arvalid_w),
        .p0_arready_i(p0_arready_w),
        .p0_rid_i(p0_rid_w),
        .p0_rdata_i(p0_rdata_w),
        .p0_rresp_i(p0_rresp_w),
        .p0_rlast_i(p0_rlast_w),
        .p0_rvalid_i(p0_rvalid_w),
        .p0_rready_o(p0_rready_w),
        .p0_urgent_o(p0_urgent_w),

        // tmds interface.
        .tmds_sym_o(tmds_sym_o),

        // irq interface.
        .irq_o(irq_src_w[12])
    );

    // NPU interfaces retain their owning subsystem and engine signal stems.
    edrv32_npu u_npu (

        // Clock and reset domains.
        .clk_npu_i(clk_npu_i),
        .rst_npu_n_i(rst_npu_n_w),
        .clk_mem_i(clk_mem_i),
        .rst_mem_n_i(rst_mem_n_w),

        // APB engine control.
        .apb_paddr_i(media_apb_paddr_w),
        .apb_psel_i(media_apb_psel_w[6]),
        .apb_penable_i(media_apb_penable_w),
        .apb_pwrite_i(media_apb_pwrite_w),
        .apb_pwdata_i(media_apb_pwdata_w),
        .apb_pstrb_i(media_apb_pstrb_w),
        .apb_pready_o(media_apb_pready_w[6]),
        .apb_prdata_o(media_apb_prdata_w[192 +: 32]),
        .apb_pslverr_o(media_apb_pslverr_w[6]),

        // axi interface.
        .axi_awid_o(p3_awid_w),
        .axi_awaddr_o(p3_awaddr_w),
        .axi_awlen_o(p3_awlen_w),
        .axi_awvalid_o(p3_awvalid_w),
        .axi_awready_i(p3_awready_w),
        .axi_wdata_o(p3_wdata_w),
        .axi_wstrb_o(p3_wstrb_w),
        .axi_wlast_o(p3_wlast_w),
        .axi_wvalid_o(p3_wvalid_w),
        .axi_wready_i(p3_wready_w),
        .axi_bid_i(p3_bid_w),
        .axi_bresp_i(p3_bresp_w),
        .axi_bvalid_i(p3_bvalid_w),
        .axi_bready_o(p3_bready_w),
        .axi_arid_o(p3_arid_w),
        .axi_araddr_o(p3_araddr_w),
        .axi_arlen_o(p3_arlen_w),
        .axi_arvalid_o(p3_arvalid_w),
        .axi_arready_i(p3_arready_w),
        .axi_rid_i(p3_rid_w),
        .axi_rdata_i(p3_rdata_w),
        .axi_rresp_i(p3_rresp_w),
        .axi_rlast_i(p3_rlast_w),
        .axi_rvalid_i(p3_rvalid_w),
        .axi_rready_o(p3_rready_w),

        // irq interface.
        .irq_o(irq_src_w[13])
    );

    // ETH interfaces retain their owning subsystem and engine signal stems.
    edrv32_eth u_eth (

        // Clock and reset domains.
        .clk_mem_i(clk_mem_i),
        .rst_mem_n_i(rst_mem_n_w),
        .clk_eth_rx_i(eth_rx_clk_i),
        .rst_eth_rx_n_i(rst_eth_rx_n_w),
        .clk_eth_tx_i(eth_tx_clk_i),
        .rst_eth_tx_n_i(rst_eth_tx_n_w),

        // eth interface.
        .eth_rxd_i(eth_rxd_i),
        .eth_rx_dv_i(eth_rx_dv_i),
        .eth_rx_er_i(eth_rx_er_i),
        .eth_txd_o(eth_txd_o),
        .eth_tx_en_o(eth_tx_en_o),
        .eth_tx_er_o(eth_tx_er_o),
        .eth_mdc_o(eth_mdc_o),
        .eth_mdio_o(eth_mdio_o),
        .eth_mdio_oe(eth_mdio_oe_o),
        .eth_mdio_i(eth_mdio_i),
        .eth_phy_rst_n_o(eth_phy_rst_n_o),

        // APB engine control.
        .apb_paddr_i(media_apb_paddr_w),
        .apb_psel_i(media_apb_psel_w[7]),
        .apb_penable_i(media_apb_penable_w),
        .apb_pwrite_i(media_apb_pwrite_w),
        .apb_pwdata_i(media_apb_pwdata_w),
        .apb_pstrb_i(media_apb_pstrb_w),
        .apb_pready_o(media_apb_pready_w[7]),
        .apb_prdata_o(media_apb_prdata_w[224 +: 32]),
        .apb_pslverr_o(media_apb_pslverr_w[7]),

        // axi interface.
        .axi_arid_o(eth_arid_w),
        .axi_araddr_o(eth_araddr_w),
        .axi_arlen_o(eth_arlen_w),
        .axi_arvalid_o(eth_arvalid_w),
        .axi_arready_i(eth_arready_w),
        .axi_rid_i(eth_rid_w),
        .axi_rdata_i(eth_rdata_w),
        .axi_rresp_i(eth_rresp_w),
        .axi_rlast_i(eth_rlast_w),
        .axi_rvalid_i(eth_rvalid_w),
        .axi_rready_o(eth_rready_w),
        .axi_awid_o(eth_awid_w),
        .axi_awaddr_o(eth_awaddr_w),
        .axi_awlen_o(eth_awlen_w),
        .axi_awvalid_o(eth_awvalid_w),
        .axi_awready_i(eth_awready_w),
        .axi_wdata_o(eth_wdata_w),
        .axi_wstrb_o(eth_wstrb_w),
        .axi_wlast_o(eth_wlast_w),
        .axi_wvalid_o(eth_wvalid_w),
        .axi_wready_i(eth_wready_w),
        .axi_bid_i(eth_bid_w),
        .axi_bresp_i(eth_bresp_w),
        .axi_bvalid_i(eth_bvalid_w),
        .axi_bready_o(eth_bready_w),

        // irq interface.
        .irq_o(irq_src_w[14])
    );

endmodule
