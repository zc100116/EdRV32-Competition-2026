// File: edrv32_sys_subsys.v
// Spec: sys-subsys-spec 1, 2.3, 2.10, 3.3, 3.4.
// Description: Connect CPU AXI ports to system storage, peripherals and the DDR gateway.
//              Export decoded cache and media APB ports and all sequenced domain resets.
// Clock domain: clk_sys; media APB in clk_mem; reset outputs in their own domains.
module edrv32_sys_subsys (
    // Domain clocks and asynchronous reset/status.
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

    // Sequenced domain resets (spec 2.10).
    output wire rst_sys_por_n_o,
    output wire rst_sys_n_o,
    output wire rst_mem_core_n_o,
    output wire rst_mem_n_o,
    output wire rst_pix_n_o,
    output wire rst_npu_n_o,
    output wire rst_cam0_n_o,
    output wire rst_cam1_n_o,
    output wire rst_eth_rx_n_o,
    output wire rst_eth_tx_n_o,

    // m0 AXI64 interface.
    input wire [3:0] m0_arid_i,
    input wire [31:0] m0_araddr_i,
    input wire [7:0] m0_arlen_i,
    input wire [2:0] m0_arsize_i,
    input wire [1:0] m0_arburst_i,
    input wire m0_arvalid_i,
    output wire m0_arready_o,
    output wire [3:0] m0_rid_o,
    output wire [63:0] m0_rdata_o,
    output wire [1:0] m0_rresp_o,
    output wire m0_rlast_o,
    output wire m0_rvalid_o,
    input wire m0_rready_i,

    // m1 AXI64 interface.
    input wire [3:0] m1_awid_i,
    input wire [31:0] m1_awaddr_i,
    input wire [7:0] m1_awlen_i,
    input wire [2:0] m1_awsize_i,
    input wire [1:0] m1_awburst_i,
    input wire m1_awvalid_i,
    output wire m1_awready_o,
    input wire [63:0] m1_wdata_i,
    input wire [7:0] m1_wstrb_i,
    input wire m1_wlast_i,
    input wire m1_wvalid_i,
    output wire m1_wready_o,
    output wire [3:0] m1_bid_o,
    output wire [1:0] m1_bresp_o,
    output wire m1_bvalid_o,
    input wire m1_bready_i,
    input wire [3:0] m1_arid_i,
    input wire [31:0] m1_araddr_i,
    input wire [7:0] m1_arlen_i,
    input wire [2:0] m1_arsize_i,
    input wire [1:0] m1_arburst_i,
    input wire m1_arvalid_i,
    output wire m1_arready_o,
    output wire [3:0] m1_rid_o,
    output wire [63:0] m1_rdata_o,
    output wire [1:0] m1_rresp_o,
    output wire m1_rlast_o,
    output wire m1_rvalid_o,
    input wire m1_rready_i,

    // s6 AXI64 interface.
    output wire [3:0] s6_awid_o,
    output wire [31:0] s6_awaddr_o,
    output wire [7:0] s6_awlen_o,
    output wire [2:0] s6_awsize_o,
    output wire [1:0] s6_awburst_o,
    output wire s6_awvalid_o,
    input wire s6_awready_i,
    output wire [63:0] s6_wdata_o,
    output wire [7:0] s6_wstrb_o,
    output wire s6_wlast_o,
    output wire s6_wvalid_o,
    input wire s6_wready_i,
    input wire [3:0] s6_bid_i,
    input wire [1:0] s6_bresp_i,
    input wire s6_bvalid_i,
    output wire s6_bready_o,
    output wire [3:0] s6_arid_o,
    output wire [31:0] s6_araddr_o,
    output wire [7:0] s6_arlen_o,
    output wire [2:0] s6_arsize_o,
    output wire [1:0] s6_arburst_o,
    output wire s6_arvalid_o,
    input wire s6_arready_i,
    input wire [3:0] s6_rid_i,
    input wire [63:0] s6_rdata_i,
    input wire [1:0] s6_rresp_i,
    input wire s6_rlast_i,
    input wire s6_rvalid_i,
    output wire s6_rready_o,

    // Media decoded APB interface.
    output wire [11:0] media_apb_paddr_o,
    output wire [15:0] media_apb_psel_o,
    output wire media_apb_penable_o,
    output wire media_apb_pwrite_o,
    output wire [31:0] media_apb_pwdata_o,
    output wire [3:0] media_apb_pstrb_o,
    input wire [511:0] media_apb_prdata_i,
    input wire [15:0] media_apb_pready_i,
    input wire [15:0] media_apb_pslverr_i,

    // Cache decoded APB interface.
    output wire [11:0] cache_apb_paddr_o,
    output wire cache_apb_psel_o,
    output wire cache_apb_penable_o,
    output wire cache_apb_pwrite_o,
    output wire [31:0] cache_apb_pwdata_o,
    output wire [3:0] cache_apb_pstrb_o,
    input wire [31:0] cache_apb_prdata_i,
    input wire cache_apb_pready_i,
    input wire cache_apb_pslverr_i,

    // External interrupt sources.
    input wire irq_cache_i,
    input wire [15:8] irq_src_i,

    // clint pins and status.
    output wire [63:0] mtime_o,
    output wire irq_mtip_o,
    output wire irq_msip_o,

    // plic pins and status.
    output wire irq_meip_o,

    // uart pins and status.
    input wire uart0_rx_i,
    output wire uart0_tx_o,

    // gpio pins and status.
    input wire [15:0] gpio_i,
    output wire [15:0] gpio_o,
    output wire [15:0] gpio_oe_o,

    // i2c pins and status.
    input wire [1:0] i2c0_scl_i,
    output wire [1:0] i2c0_scl_o,
    output wire [1:0] i2c0_scl_oe_o,
    input wire [1:0] i2c0_sda_i,
    output wire [1:0] i2c0_sda_o,
    output wire [1:0] i2c0_sda_oe_o,

    // sysctrl pins and status.
    output wire sim_exit_valid_o,
    output wire [31:0] sim_exit_code_o
);

    // SoC 5.3: one preserved reset copy per destination region.
    wire rst_mem_core_bus_n_w;
    edrv32_reset_copy u_reset_mem_core_bus_n (
        .clk_i(clk_mem_i),
        .rst_n_i(rst_mem_core_n_o),
        .rst_n_o(rst_mem_core_bus_n_w)
    );

    // Internal AXI, APB and interrupt connections.
    wire [3:0] s0_awid_w;
    wire [31:0] s0_awaddr_w;
    wire [7:0] s0_awlen_w;
    wire [2:0] s0_awsize_w;
    wire [1:0] s0_awburst_w;
    wire s0_awvalid_w;
    wire s0_awready_w;
    wire [63:0] s0_wdata_w;
    wire [7:0] s0_wstrb_w;
    wire s0_wlast_w;
    wire s0_wvalid_w;
    wire s0_wready_w;
    wire [3:0] s0_bid_w;
    wire [1:0] s0_bresp_w;
    wire s0_bvalid_w;
    wire s0_bready_w;
    wire [3:0] s0_arid_w;
    wire [31:0] s0_araddr_w;
    wire [7:0] s0_arlen_w;
    wire [2:0] s0_arsize_w;
    wire [1:0] s0_arburst_w;
    wire s0_arvalid_w;
    wire s0_arready_w;
    wire [3:0] s0_rid_w;
    wire [63:0] s0_rdata_w;
    wire [1:0] s0_rresp_w;
    wire s0_rlast_w;
    wire s0_rvalid_w;
    wire s0_rready_w;
    wire [3:0] s1_awid_w;
    wire [31:0] s1_awaddr_w;
    wire [7:0] s1_awlen_w;
    wire [2:0] s1_awsize_w;
    wire [1:0] s1_awburst_w;
    wire s1_awvalid_w;
    wire s1_awready_w;
    wire [63:0] s1_wdata_w;
    wire [7:0] s1_wstrb_w;
    wire s1_wlast_w;
    wire s1_wvalid_w;
    wire s1_wready_w;
    wire [3:0] s1_bid_w;
    wire [1:0] s1_bresp_w;
    wire s1_bvalid_w;
    wire s1_bready_w;
    wire [3:0] s1_arid_w;
    wire [31:0] s1_araddr_w;
    wire [7:0] s1_arlen_w;
    wire [2:0] s1_arsize_w;
    wire [1:0] s1_arburst_w;
    wire s1_arvalid_w;
    wire s1_arready_w;
    wire [3:0] s1_rid_w;
    wire [63:0] s1_rdata_w;
    wire [1:0] s1_rresp_w;
    wire s1_rlast_w;
    wire s1_rvalid_w;
    wire s1_rready_w;
    wire [3:0] s2_awid_w;
    wire [31:0] s2_awaddr_w;
    wire [7:0] s2_awlen_w;
    wire [2:0] s2_awsize_w;
    wire [1:0] s2_awburst_w;
    wire s2_awvalid_w;
    wire s2_awready_w;
    wire [63:0] s2_wdata_w;
    wire [7:0] s2_wstrb_w;
    wire s2_wlast_w;
    wire s2_wvalid_w;
    wire s2_wready_w;
    wire [3:0] s2_bid_w;
    wire [1:0] s2_bresp_w;
    wire s2_bvalid_w;
    wire s2_bready_w;
    wire [3:0] s2_arid_w;
    wire [31:0] s2_araddr_w;
    wire [7:0] s2_arlen_w;
    wire [2:0] s2_arsize_w;
    wire [1:0] s2_arburst_w;
    wire s2_arvalid_w;
    wire s2_arready_w;
    wire [3:0] s2_rid_w;
    wire [63:0] s2_rdata_w;
    wire [1:0] s2_rresp_w;
    wire s2_rlast_w;
    wire s2_rvalid_w;
    wire s2_rready_w;
    wire [3:0] s3_awid_w;
    wire [31:0] s3_awaddr_w;
    wire [7:0] s3_awlen_w;
    wire [2:0] s3_awsize_w;
    wire [1:0] s3_awburst_w;
    wire s3_awvalid_w;
    wire s3_awready_w;
    wire [63:0] s3_wdata_w;
    wire [7:0] s3_wstrb_w;
    wire s3_wlast_w;
    wire s3_wvalid_w;
    wire s3_wready_w;
    wire [3:0] s3_bid_w;
    wire [1:0] s3_bresp_w;
    wire s3_bvalid_w;
    wire s3_bready_w;
    wire [3:0] s3_arid_w;
    wire [31:0] s3_araddr_w;
    wire [7:0] s3_arlen_w;
    wire [2:0] s3_arsize_w;
    wire [1:0] s3_arburst_w;
    wire s3_arvalid_w;
    wire s3_arready_w;
    wire [3:0] s3_rid_w;
    wire [63:0] s3_rdata_w;
    wire [1:0] s3_rresp_w;
    wire s3_rlast_w;
    wire s3_rvalid_w;
    wire s3_rready_w;
    wire [3:0] s4_awid_w;
    wire [31:0] s4_awaddr_w;
    wire [7:0] s4_awlen_w;
    wire [2:0] s4_awsize_w;
    wire [1:0] s4_awburst_w;
    wire s4_awvalid_w;
    wire s4_awready_w;
    wire [63:0] s4_wdata_w;
    wire [7:0] s4_wstrb_w;
    wire s4_wlast_w;
    wire s4_wvalid_w;
    wire s4_wready_w;
    wire [3:0] s4_bid_w;
    wire [1:0] s4_bresp_w;
    wire s4_bvalid_w;
    wire s4_bready_w;
    wire [3:0] s4_arid_w;
    wire [31:0] s4_araddr_w;
    wire [7:0] s4_arlen_w;
    wire [2:0] s4_arsize_w;
    wire [1:0] s4_arburst_w;
    wire s4_arvalid_w;
    wire s4_arready_w;
    wire [3:0] s4_rid_w;
    wire [63:0] s4_rdata_w;
    wire [1:0] s4_rresp_w;
    wire s4_rlast_w;
    wire s4_rvalid_w;
    wire s4_rready_w;
    wire [3:0] s5_awid_w;
    wire [31:0] s5_awaddr_w;
    wire [7:0] s5_awlen_w;
    wire [2:0] s5_awsize_w;
    wire [1:0] s5_awburst_w;
    wire s5_awvalid_w;
    wire s5_awready_w;
    wire [63:0] s5_wdata_w;
    wire [7:0] s5_wstrb_w;
    wire s5_wlast_w;
    wire s5_wvalid_w;
    wire s5_wready_w;
    wire [3:0] s5_bid_w;
    wire [1:0] s5_bresp_w;
    wire s5_bvalid_w;
    wire s5_bready_w;
    wire [3:0] s5_arid_w;
    wire [31:0] s5_araddr_w;
    wire [7:0] s5_arlen_w;
    wire [2:0] s5_arsize_w;
    wire [1:0] s5_arburst_w;
    wire s5_arvalid_w;
    wire s5_arready_w;
    wire [3:0] s5_rid_w;
    wire [63:0] s5_rdata_w;
    wire [1:0] s5_rresp_w;
    wire s5_rlast_w;
    wire s5_rvalid_w;
    wire s5_rready_w;
    wire [15:1] plic_irq_src_w;
    wire [15:0] sys_apb_paddr_w;
    wire sys_apb_psel_w;
    wire sys_apb_penable_w;
    wire sys_apb_pwrite_w;
    wire [31:0] sys_apb_pwdata_w;
    wire [3:0] sys_apb_pstrb_w;
    wire [31:0] sys_apb_prdata_w;
    wire sys_apb_pready_w;
    wire sys_apb_pslverr_w;
    wire [15:0] media_sys_apb_paddr_w;
    wire media_sys_apb_psel_w;
    wire media_sys_apb_penable_w;
    wire media_sys_apb_pwrite_w;
    wire [31:0] media_sys_apb_pwdata_w;
    wire [3:0] media_sys_apb_pstrb_w;
    wire [31:0] media_sys_apb_prdata_w;
    wire media_sys_apb_pready_w;
    wire media_sys_apb_pslverr_w;
    wire [15:0] media_mem_apb_paddr_w;
    wire media_mem_apb_psel_w;
    wire media_mem_apb_penable_w;
    wire media_mem_apb_pwrite_w;
    wire [31:0] media_mem_apb_pwdata_w;
    wire [3:0] media_mem_apb_pstrb_w;
    wire [31:0] media_mem_apb_prdata_w;
    wire media_mem_apb_pready_w;
    wire media_mem_apb_pslverr_w;
    wire [11:0] sys_slot_paddr_w;
    wire [15:0] sys_slot_psel_w;
    wire sys_slot_penable_w;
    wire sys_slot_pwrite_w;
    wire [31:0] sys_slot_pwdata_w;
    wire [3:0] sys_slot_pstrb_w;
    wire [511:0] sys_slot_prdata_w;
    wire [15:0] sys_slot_pready_w;
    wire [15:0] sys_slot_pslverr_w;
    wire irq_uart_w;
    wire irq_gpio_w;
    wire irq_i2c_w;
    wire soft_reset_media_w;
    wire soft_reset_soc_w;
    wire unused_w;

    // spec 2.3: system slots 2, 3 and 7-15 are reserved.
    assign sys_slot_prdata_w[64 +: 32] = 32'd0;
    assign sys_slot_pready_w[2] = 1'b1;
    assign sys_slot_pslverr_w[2] = 1'b1;
    assign sys_slot_prdata_w[96 +: 32] = 32'd0;
    assign sys_slot_pready_w[3] = 1'b1;
    assign sys_slot_pslverr_w[3] = 1'b1;
    assign sys_slot_prdata_w[224 +: 32] = 32'd0;
    assign sys_slot_pready_w[7] = 1'b1;
    assign sys_slot_pslverr_w[7] = 1'b1;
    assign sys_slot_prdata_w[256 +: 32] = 32'd0;
    assign sys_slot_pready_w[8] = 1'b1;
    assign sys_slot_pslverr_w[8] = 1'b1;
    assign sys_slot_prdata_w[288 +: 32] = 32'd0;
    assign sys_slot_pready_w[9] = 1'b1;
    assign sys_slot_pslverr_w[9] = 1'b1;
    assign sys_slot_prdata_w[320 +: 32] = 32'd0;
    assign sys_slot_pready_w[10] = 1'b1;
    assign sys_slot_pslverr_w[10] = 1'b1;
    assign sys_slot_prdata_w[352 +: 32] = 32'd0;
    assign sys_slot_pready_w[11] = 1'b1;
    assign sys_slot_pslverr_w[11] = 1'b1;
    assign sys_slot_prdata_w[384 +: 32] = 32'd0;
    assign sys_slot_pready_w[12] = 1'b1;
    assign sys_slot_pslverr_w[12] = 1'b1;
    assign sys_slot_prdata_w[416 +: 32] = 32'd0;
    assign sys_slot_pready_w[13] = 1'b1;
    assign sys_slot_pslverr_w[13] = 1'b1;
    assign sys_slot_prdata_w[448 +: 32] = 32'd0;
    assign sys_slot_pready_w[14] = 1'b1;
    assign sys_slot_pslverr_w[14] = 1'b1;
    assign sys_slot_prdata_w[480 +: 32] = 32'd0;
    assign sys_slot_pready_w[15] = 1'b1;
    assign sys_slot_pslverr_w[15] = 1'b1;

    // System slot 5 belongs to the CPU cache controller (spec 3.4).
    assign cache_apb_paddr_o = sys_slot_paddr_w;
    assign cache_apb_psel_o = sys_slot_psel_w[5];
    assign cache_apb_penable_o = sys_slot_penable_w;
    assign cache_apb_pwrite_o = sys_slot_pwrite_w;
    assign cache_apb_pwdata_o = sys_slot_pwdata_w;
    assign cache_apb_pstrb_o = sys_slot_pstrb_w;
    assign sys_slot_prdata_w[160 +: 32] = cache_apb_prdata_i;
    assign sys_slot_pready_w[5] = cache_apb_pready_i;
    assign sys_slot_pslverr_w[5] = cache_apb_pslverr_i;

    // spec 3.3: PLIC performs synchronization of all fifteen source levels.
    assign plic_irq_src_w = {irq_src_i, 1'b0, irq_cache_i, irq_i2c_w,
        2'b00, irq_gpio_w, irq_uart_w};
    assign unused_w = &{1'b0, sys_slot_psel_w[15:7], sys_slot_psel_w[3:2]};

    edrv32_bus_sys_xbar u_sys_xbar (
        // Clock and reset.
        .clk_i(clk_sys_i),
        .rst_n_i(rst_sys_xbar_n_w),

        // m0 AR channel.
        .m0_arid_i(m0_arid_i),
        .m0_araddr_i(m0_araddr_i),
        .m0_arlen_i(m0_arlen_i),
        .m0_arsize_i(m0_arsize_i),
        .m0_arburst_i(m0_arburst_i),
        .m0_arvalid_i(m0_arvalid_i),
        .m0_arready_o(m0_arready_o),

        // m0 R channel.
        .m0_rid_o(m0_rid_o),
        .m0_rdata_o(m0_rdata_o),
        .m0_rresp_o(m0_rresp_o),
        .m0_rlast_o(m0_rlast_o),
        .m0_rvalid_o(m0_rvalid_o),
        .m0_rready_i(m0_rready_i),

        // m1 AW channel.
        .m1_awid_i(m1_awid_i),
        .m1_awaddr_i(m1_awaddr_i),
        .m1_awlen_i(m1_awlen_i),
        .m1_awsize_i(m1_awsize_i),
        .m1_awburst_i(m1_awburst_i),
        .m1_awvalid_i(m1_awvalid_i),
        .m1_awready_o(m1_awready_o),

        // m1 W channel.
        .m1_wdata_i(m1_wdata_i),
        .m1_wstrb_i(m1_wstrb_i),
        .m1_wlast_i(m1_wlast_i),
        .m1_wvalid_i(m1_wvalid_i),
        .m1_wready_o(m1_wready_o),

        // m1 B channel.
        .m1_bid_o(m1_bid_o),
        .m1_bresp_o(m1_bresp_o),
        .m1_bvalid_o(m1_bvalid_o),
        .m1_bready_i(m1_bready_i),

        // m1 AR channel.
        .m1_arid_i(m1_arid_i),
        .m1_araddr_i(m1_araddr_i),
        .m1_arlen_i(m1_arlen_i),
        .m1_arsize_i(m1_arsize_i),
        .m1_arburst_i(m1_arburst_i),
        .m1_arvalid_i(m1_arvalid_i),
        .m1_arready_o(m1_arready_o),

        // m1 R channel.
        .m1_rid_o(m1_rid_o),
        .m1_rdata_o(m1_rdata_o),
        .m1_rresp_o(m1_rresp_o),
        .m1_rlast_o(m1_rlast_o),
        .m1_rvalid_o(m1_rvalid_o),
        .m1_rready_i(m1_rready_i),

        // s0 AW channel.
        .s0_awid_o(s0_awid_w),
        .s0_awaddr_o(s0_awaddr_w),
        .s0_awlen_o(s0_awlen_w),
        .s0_awsize_o(s0_awsize_w),
        .s0_awburst_o(s0_awburst_w),
        .s0_awvalid_o(s0_awvalid_w),
        .s0_awready_i(s0_awready_w),

        // s0 W channel.
        .s0_wdata_o(s0_wdata_w),
        .s0_wstrb_o(s0_wstrb_w),
        .s0_wlast_o(s0_wlast_w),
        .s0_wvalid_o(s0_wvalid_w),
        .s0_wready_i(s0_wready_w),

        // s0 B channel.
        .s0_bid_i(s0_bid_w),
        .s0_bresp_i(s0_bresp_w),
        .s0_bvalid_i(s0_bvalid_w),
        .s0_bready_o(s0_bready_w),

        // s0 AR channel.
        .s0_arid_o(s0_arid_w),
        .s0_araddr_o(s0_araddr_w),
        .s0_arlen_o(s0_arlen_w),
        .s0_arsize_o(s0_arsize_w),
        .s0_arburst_o(s0_arburst_w),
        .s0_arvalid_o(s0_arvalid_w),
        .s0_arready_i(s0_arready_w),

        // s0 R channel.
        .s0_rid_i(s0_rid_w),
        .s0_rdata_i(s0_rdata_w),
        .s0_rresp_i(s0_rresp_w),
        .s0_rlast_i(s0_rlast_w),
        .s0_rvalid_i(s0_rvalid_w),
        .s0_rready_o(s0_rready_w),

        // s1 AW channel.
        .s1_awid_o(s1_awid_w),
        .s1_awaddr_o(s1_awaddr_w),
        .s1_awlen_o(s1_awlen_w),
        .s1_awsize_o(s1_awsize_w),
        .s1_awburst_o(s1_awburst_w),
        .s1_awvalid_o(s1_awvalid_w),
        .s1_awready_i(s1_awready_w),

        // s1 W channel.
        .s1_wdata_o(s1_wdata_w),
        .s1_wstrb_o(s1_wstrb_w),
        .s1_wlast_o(s1_wlast_w),
        .s1_wvalid_o(s1_wvalid_w),
        .s1_wready_i(s1_wready_w),

        // s1 B channel.
        .s1_bid_i(s1_bid_w),
        .s1_bresp_i(s1_bresp_w),
        .s1_bvalid_i(s1_bvalid_w),
        .s1_bready_o(s1_bready_w),

        // s1 AR channel.
        .s1_arid_o(s1_arid_w),
        .s1_araddr_o(s1_araddr_w),
        .s1_arlen_o(s1_arlen_w),
        .s1_arsize_o(s1_arsize_w),
        .s1_arburst_o(s1_arburst_w),
        .s1_arvalid_o(s1_arvalid_w),
        .s1_arready_i(s1_arready_w),

        // s1 R channel.
        .s1_rid_i(s1_rid_w),
        .s1_rdata_i(s1_rdata_w),
        .s1_rresp_i(s1_rresp_w),
        .s1_rlast_i(s1_rlast_w),
        .s1_rvalid_i(s1_rvalid_w),
        .s1_rready_o(s1_rready_w),

        // s2 AW channel.
        .s2_awid_o(s2_awid_w),
        .s2_awaddr_o(s2_awaddr_w),
        .s2_awlen_o(s2_awlen_w),
        .s2_awsize_o(s2_awsize_w),
        .s2_awburst_o(s2_awburst_w),
        .s2_awvalid_o(s2_awvalid_w),
        .s2_awready_i(s2_awready_w),

        // s2 W channel.
        .s2_wdata_o(s2_wdata_w),
        .s2_wstrb_o(s2_wstrb_w),
        .s2_wlast_o(s2_wlast_w),
        .s2_wvalid_o(s2_wvalid_w),
        .s2_wready_i(s2_wready_w),

        // s2 B channel.
        .s2_bid_i(s2_bid_w),
        .s2_bresp_i(s2_bresp_w),
        .s2_bvalid_i(s2_bvalid_w),
        .s2_bready_o(s2_bready_w),

        // s2 AR channel.
        .s2_arid_o(s2_arid_w),
        .s2_araddr_o(s2_araddr_w),
        .s2_arlen_o(s2_arlen_w),
        .s2_arsize_o(s2_arsize_w),
        .s2_arburst_o(s2_arburst_w),
        .s2_arvalid_o(s2_arvalid_w),
        .s2_arready_i(s2_arready_w),

        // s2 R channel.
        .s2_rid_i(s2_rid_w),
        .s2_rdata_i(s2_rdata_w),
        .s2_rresp_i(s2_rresp_w),
        .s2_rlast_i(s2_rlast_w),
        .s2_rvalid_i(s2_rvalid_w),
        .s2_rready_o(s2_rready_w),

        // s3 AW channel.
        .s3_awid_o(s3_awid_w),
        .s3_awaddr_o(s3_awaddr_w),
        .s3_awlen_o(s3_awlen_w),
        .s3_awsize_o(s3_awsize_w),
        .s3_awburst_o(s3_awburst_w),
        .s3_awvalid_o(s3_awvalid_w),
        .s3_awready_i(s3_awready_w),

        // s3 W channel.
        .s3_wdata_o(s3_wdata_w),
        .s3_wstrb_o(s3_wstrb_w),
        .s3_wlast_o(s3_wlast_w),
        .s3_wvalid_o(s3_wvalid_w),
        .s3_wready_i(s3_wready_w),

        // s3 B channel.
        .s3_bid_i(s3_bid_w),
        .s3_bresp_i(s3_bresp_w),
        .s3_bvalid_i(s3_bvalid_w),
        .s3_bready_o(s3_bready_w),

        // s3 AR channel.
        .s3_arid_o(s3_arid_w),
        .s3_araddr_o(s3_araddr_w),
        .s3_arlen_o(s3_arlen_w),
        .s3_arsize_o(s3_arsize_w),
        .s3_arburst_o(s3_arburst_w),
        .s3_arvalid_o(s3_arvalid_w),
        .s3_arready_i(s3_arready_w),

        // s3 R channel.
        .s3_rid_i(s3_rid_w),
        .s3_rdata_i(s3_rdata_w),
        .s3_rresp_i(s3_rresp_w),
        .s3_rlast_i(s3_rlast_w),
        .s3_rvalid_i(s3_rvalid_w),
        .s3_rready_o(s3_rready_w),

        // s4 AW channel.
        .s4_awid_o(s4_awid_w),
        .s4_awaddr_o(s4_awaddr_w),
        .s4_awlen_o(s4_awlen_w),
        .s4_awsize_o(s4_awsize_w),
        .s4_awburst_o(s4_awburst_w),
        .s4_awvalid_o(s4_awvalid_w),
        .s4_awready_i(s4_awready_w),

        // s4 W channel.
        .s4_wdata_o(s4_wdata_w),
        .s4_wstrb_o(s4_wstrb_w),
        .s4_wlast_o(s4_wlast_w),
        .s4_wvalid_o(s4_wvalid_w),
        .s4_wready_i(s4_wready_w),

        // s4 B channel.
        .s4_bid_i(s4_bid_w),
        .s4_bresp_i(s4_bresp_w),
        .s4_bvalid_i(s4_bvalid_w),
        .s4_bready_o(s4_bready_w),

        // s4 AR channel.
        .s4_arid_o(s4_arid_w),
        .s4_araddr_o(s4_araddr_w),
        .s4_arlen_o(s4_arlen_w),
        .s4_arsize_o(s4_arsize_w),
        .s4_arburst_o(s4_arburst_w),
        .s4_arvalid_o(s4_arvalid_w),
        .s4_arready_i(s4_arready_w),

        // s4 R channel.
        .s4_rid_i(s4_rid_w),
        .s4_rdata_i(s4_rdata_w),
        .s4_rresp_i(s4_rresp_w),
        .s4_rlast_i(s4_rlast_w),
        .s4_rvalid_i(s4_rvalid_w),
        .s4_rready_o(s4_rready_w),

        // s5 AW channel.
        .s5_awid_o(s5_awid_w),
        .s5_awaddr_o(s5_awaddr_w),
        .s5_awlen_o(s5_awlen_w),
        .s5_awsize_o(s5_awsize_w),
        .s5_awburst_o(s5_awburst_w),
        .s5_awvalid_o(s5_awvalid_w),
        .s5_awready_i(s5_awready_w),

        // s5 W channel.
        .s5_wdata_o(s5_wdata_w),
        .s5_wstrb_o(s5_wstrb_w),
        .s5_wlast_o(s5_wlast_w),
        .s5_wvalid_o(s5_wvalid_w),
        .s5_wready_i(s5_wready_w),

        // s5 B channel.
        .s5_bid_i(s5_bid_w),
        .s5_bresp_i(s5_bresp_w),
        .s5_bvalid_i(s5_bvalid_w),
        .s5_bready_o(s5_bready_w),

        // s5 AR channel.
        .s5_arid_o(s5_arid_w),
        .s5_araddr_o(s5_araddr_w),
        .s5_arlen_o(s5_arlen_w),
        .s5_arsize_o(s5_arsize_w),
        .s5_arburst_o(s5_arburst_w),
        .s5_arvalid_o(s5_arvalid_w),
        .s5_arready_i(s5_arready_w),

        // s5 R channel.
        .s5_rid_i(s5_rid_w),
        .s5_rdata_i(s5_rdata_w),
        .s5_rresp_i(s5_rresp_w),
        .s5_rlast_i(s5_rlast_w),
        .s5_rvalid_i(s5_rvalid_w),
        .s5_rready_o(s5_rready_w),

        // s6 AW channel.
        .s6_awid_o(s6_awid_o),
        .s6_awaddr_o(s6_awaddr_o),
        .s6_awlen_o(s6_awlen_o),
        .s6_awsize_o(s6_awsize_o),
        .s6_awburst_o(s6_awburst_o),
        .s6_awvalid_o(s6_awvalid_o),
        .s6_awready_i(s6_awready_i),

        // s6 W channel.
        .s6_wdata_o(s6_wdata_o),
        .s6_wstrb_o(s6_wstrb_o),
        .s6_wlast_o(s6_wlast_o),
        .s6_wvalid_o(s6_wvalid_o),
        .s6_wready_i(s6_wready_i),

        // s6 B channel.
        .s6_bid_i(s6_bid_i),
        .s6_bresp_i(s6_bresp_i),
        .s6_bvalid_i(s6_bvalid_i),
        .s6_bready_o(s6_bready_o),

        // s6 AR channel.
        .s6_arid_o(s6_arid_o),
        .s6_araddr_o(s6_araddr_o),
        .s6_arlen_o(s6_arlen_o),
        .s6_arsize_o(s6_arsize_o),
        .s6_arburst_o(s6_arburst_o),
        .s6_arvalid_o(s6_arvalid_o),
        .s6_arready_i(s6_arready_i),

        // s6 R channel.
        .s6_rid_i(s6_rid_i),
        .s6_rdata_i(s6_rdata_i),
        .s6_rresp_i(s6_rresp_i),
        .s6_rlast_i(s6_rlast_i),
        .s6_rvalid_i(s6_rvalid_i),
        .s6_rready_o(s6_rready_o)
    );

    edrv32_bus_rom u_rom (
        // Clock and reset.
        .clk_i(clk_sys_i),
        .rst_n_i(rst_sys_rom_n_w),

        // axi AW channel.
        .axi_awid_i(s0_awid_w),
        .axi_awaddr_i(s0_awaddr_w),
        .axi_awlen_i(s0_awlen_w),
        .axi_awsize_i(s0_awsize_w),
        .axi_awburst_i(s0_awburst_w),
        .axi_awvalid_i(s0_awvalid_w),
        .axi_awready_o(s0_awready_w),

        // axi W channel.
        .axi_wdata_i(s0_wdata_w),
        .axi_wstrb_i(s0_wstrb_w),
        .axi_wlast_i(s0_wlast_w),
        .axi_wvalid_i(s0_wvalid_w),
        .axi_wready_o(s0_wready_w),

        // axi B channel.
        .axi_bid_o(s0_bid_w),
        .axi_bresp_o(s0_bresp_w),
        .axi_bvalid_o(s0_bvalid_w),
        .axi_bready_i(s0_bready_w),

        // axi AR channel.
        .axi_arid_i(s0_arid_w),
        .axi_araddr_i(s0_araddr_w),
        .axi_arlen_i(s0_arlen_w),
        .axi_arsize_i(s0_arsize_w),
        .axi_arburst_i(s0_arburst_w),
        .axi_arvalid_i(s0_arvalid_w),
        .axi_arready_o(s0_arready_w),

        // axi R channel.
        .axi_rid_o(s0_rid_w),
        .axi_rdata_o(s0_rdata_w),
        .axi_rresp_o(s0_rresp_w),
        .axi_rlast_o(s0_rlast_w),
        .axi_rvalid_o(s0_rvalid_w),
        .axi_rready_i(s0_rready_w)
    );

    edrv32_bus_sram u_sram (
        // Clock and reset.
        .clk_i(clk_sys_i),
        .rst_n_i(rst_sys_sram_n_w),

        // axi AW channel.
        .axi_awid_i(s1_awid_w),
        .axi_awaddr_i(s1_awaddr_w),
        .axi_awlen_i(s1_awlen_w),
        .axi_awsize_i(s1_awsize_w),
        .axi_awburst_i(s1_awburst_w),
        .axi_awvalid_i(s1_awvalid_w),
        .axi_awready_o(s1_awready_w),

        // axi W channel.
        .axi_wdata_i(s1_wdata_w),
        .axi_wstrb_i(s1_wstrb_w),
        .axi_wlast_i(s1_wlast_w),
        .axi_wvalid_i(s1_wvalid_w),
        .axi_wready_o(s1_wready_w),

        // axi B channel.
        .axi_bid_o(s1_bid_w),
        .axi_bresp_o(s1_bresp_w),
        .axi_bvalid_o(s1_bvalid_w),
        .axi_bready_i(s1_bready_w),

        // axi AR channel.
        .axi_arid_i(s1_arid_w),
        .axi_araddr_i(s1_araddr_w),
        .axi_arlen_i(s1_arlen_w),
        .axi_arsize_i(s1_arsize_w),
        .axi_arburst_i(s1_arburst_w),
        .axi_arvalid_i(s1_arvalid_w),
        .axi_arready_o(s1_arready_w),

        // axi R channel.
        .axi_rid_o(s1_rid_w),
        .axi_rdata_o(s1_rdata_w),
        .axi_rresp_o(s1_rresp_w),
        .axi_rlast_o(s1_rlast_w),
        .axi_rvalid_o(s1_rvalid_w),
        .axi_rready_i(s1_rready_w)
    );

    edrv32_periph_clint u_clint (
        // Clock and reset.
        .clk_i(clk_sys_i),
        .rst_n_i(rst_sys_clint_n_w),

        // AXI64 slave write address.
        .axi_awid_i(s2_awid_w),
        .axi_awaddr_i(s2_awaddr_w),
        .axi_awlen_i(s2_awlen_w),
        .axi_awsize_i(s2_awsize_w),
        .axi_awburst_i(s2_awburst_w),
        .axi_awvalid_i(s2_awvalid_w),
        .axi_awready_o(s2_awready_w),

        // AXI64 slave write data and response.
        .axi_wdata_i(s2_wdata_w),
        .axi_wstrb_i(s2_wstrb_w),
        .axi_wlast_i(s2_wlast_w),
        .axi_wvalid_i(s2_wvalid_w),
        .axi_wready_o(s2_wready_w),
        .axi_bid_o(s2_bid_w),
        .axi_bresp_o(s2_bresp_w),
        .axi_bvalid_o(s2_bvalid_w),
        .axi_bready_i(s2_bready_w),

        // AXI64 slave read address and response.
        .axi_arid_i(s2_arid_w),
        .axi_araddr_i(s2_araddr_w),
        .axi_arlen_i(s2_arlen_w),
        .axi_arsize_i(s2_arsize_w),
        .axi_arburst_i(s2_arburst_w),
        .axi_arvalid_i(s2_arvalid_w),
        .axi_arready_o(s2_arready_w),
        .axi_rid_o(s2_rid_w),
        .axi_rdata_o(s2_rdata_w),
        .axi_rresp_o(s2_rresp_w),
        .axi_rlast_o(s2_rlast_w),
        .axi_rvalid_o(s2_rvalid_w),
        .axi_rready_i(s2_rready_w),

        // CPU timer and interrupt outputs.
        .mtime_o(mtime_o),
        .irq_mtip_o(irq_mtip_o),
        .irq_msip_o(irq_msip_o)
    );

    edrv32_periph_plic u_plic (
        // Clock and reset.
        .clk_i(clk_sys_i),
        .rst_n_i(rst_sys_plic_n_w),

        // AXI64 slave write address.
        .axi_awid_i(s3_awid_w),
        .axi_awaddr_i(s3_awaddr_w),
        .axi_awlen_i(s3_awlen_w),
        .axi_awsize_i(s3_awsize_w),
        .axi_awburst_i(s3_awburst_w),
        .axi_awvalid_i(s3_awvalid_w),
        .axi_awready_o(s3_awready_w),

        // AXI64 slave write data and response.
        .axi_wdata_i(s3_wdata_w),
        .axi_wstrb_i(s3_wstrb_w),
        .axi_wlast_i(s3_wlast_w),
        .axi_wvalid_i(s3_wvalid_w),
        .axi_wready_o(s3_wready_w),
        .axi_bid_o(s3_bid_w),
        .axi_bresp_o(s3_bresp_w),
        .axi_bvalid_o(s3_bvalid_w),
        .axi_bready_i(s3_bready_w),

        // AXI64 slave read address and response.
        .axi_arid_i(s3_arid_w),
        .axi_araddr_i(s3_araddr_w),
        .axi_arlen_i(s3_arlen_w),
        .axi_arsize_i(s3_arsize_w),
        .axi_arburst_i(s3_arburst_w),
        .axi_arvalid_i(s3_arvalid_w),
        .axi_arready_o(s3_arready_w),
        .axi_rid_o(s3_rid_w),
        .axi_rdata_o(s3_rdata_w),
        .axi_rresp_o(s3_rresp_w),
        .axi_rlast_o(s3_rlast_w),
        .axi_rvalid_o(s3_rvalid_w),
        .axi_rready_i(s3_rready_w),

        // Interrupt sources and machine external interrupt.
        .irq_src_i(plic_irq_src_w),
        .irq_meip_o(irq_meip_o)
    );

    edrv32_bus_apb_bridge u_sys_apb_bridge (
        // Clock and reset.
        .clk_i(clk_sys_i),
        .rst_n_i(rst_sys_apb_bridge_n_w),

        // axi AW channel.
        .axi_awid_i(s4_awid_w),
        .axi_awaddr_i(s4_awaddr_w),
        .axi_awlen_i(s4_awlen_w),
        .axi_awsize_i(s4_awsize_w),
        .axi_awburst_i(s4_awburst_w),
        .axi_awvalid_i(s4_awvalid_w),
        .axi_awready_o(s4_awready_w),

        // axi W channel.
        .axi_wdata_i(s4_wdata_w),
        .axi_wstrb_i(s4_wstrb_w),
        .axi_wlast_i(s4_wlast_w),
        .axi_wvalid_i(s4_wvalid_w),
        .axi_wready_o(s4_wready_w),

        // axi B channel.
        .axi_bid_o(s4_bid_w),
        .axi_bresp_o(s4_bresp_w),
        .axi_bvalid_o(s4_bvalid_w),
        .axi_bready_i(s4_bready_w),

        // axi AR channel.
        .axi_arid_i(s4_arid_w),
        .axi_araddr_i(s4_araddr_w),
        .axi_arlen_i(s4_arlen_w),
        .axi_arsize_i(s4_arsize_w),
        .axi_arburst_i(s4_arburst_w),
        .axi_arvalid_i(s4_arvalid_w),
        .axi_arready_o(s4_arready_w),

        // axi R channel.
        .axi_rid_o(s4_rid_w),
        .axi_rdata_o(s4_rdata_w),
        .axi_rresp_o(s4_rresp_w),
        .axi_rlast_o(s4_rlast_w),
        .axi_rvalid_o(s4_rvalid_w),
        .axi_rready_i(s4_rready_w),

        // Undecoded APB master.
        .apb_paddr_o(sys_apb_paddr_w),
        .apb_psel_o(sys_apb_psel_w),
        .apb_penable_o(sys_apb_penable_w),
        .apb_pwrite_o(sys_apb_pwrite_w),
        .apb_pwdata_o(sys_apb_pwdata_w),
        .apb_pstrb_o(sys_apb_pstrb_w),
        .apb_prdata_i(sys_apb_prdata_w),
        .apb_pready_i(sys_apb_pready_w),
        .apb_pslverr_i(sys_apb_pslverr_w)
    );

    edrv32_bus_apb_bridge u_media_apb_bridge (
        // Clock and reset.
        .clk_i(clk_sys_i),
        .rst_n_i(rst_sys_media_apb_bridge_n_w),

        // axi AW channel.
        .axi_awid_i(s5_awid_w),
        .axi_awaddr_i(s5_awaddr_w),
        .axi_awlen_i(s5_awlen_w),
        .axi_awsize_i(s5_awsize_w),
        .axi_awburst_i(s5_awburst_w),
        .axi_awvalid_i(s5_awvalid_w),
        .axi_awready_o(s5_awready_w),

        // axi W channel.
        .axi_wdata_i(s5_wdata_w),
        .axi_wstrb_i(s5_wstrb_w),
        .axi_wlast_i(s5_wlast_w),
        .axi_wvalid_i(s5_wvalid_w),
        .axi_wready_o(s5_wready_w),

        // axi B channel.
        .axi_bid_o(s5_bid_w),
        .axi_bresp_o(s5_bresp_w),
        .axi_bvalid_o(s5_bvalid_w),
        .axi_bready_i(s5_bready_w),

        // axi AR channel.
        .axi_arid_i(s5_arid_w),
        .axi_araddr_i(s5_araddr_w),
        .axi_arlen_i(s5_arlen_w),
        .axi_arsize_i(s5_arsize_w),
        .axi_arburst_i(s5_arburst_w),
        .axi_arvalid_i(s5_arvalid_w),
        .axi_arready_o(s5_arready_w),

        // axi R channel.
        .axi_rid_o(s5_rid_w),
        .axi_rdata_o(s5_rdata_w),
        .axi_rresp_o(s5_rresp_w),
        .axi_rlast_o(s5_rlast_w),
        .axi_rvalid_o(s5_rvalid_w),
        .axi_rready_i(s5_rready_w),

        // Undecoded APB master.
        .apb_paddr_o(media_sys_apb_paddr_w),
        .apb_psel_o(media_sys_apb_psel_w),
        .apb_penable_o(media_sys_apb_penable_w),
        .apb_pwrite_o(media_sys_apb_pwrite_w),
        .apb_pwdata_o(media_sys_apb_pwdata_w),
        .apb_pstrb_o(media_sys_apb_pstrb_w),
        .apb_prdata_i(media_sys_apb_prdata_w),
        .apb_pready_i(media_sys_apb_pready_w),
        .apb_pslverr_i(media_sys_apb_pslverr_w)
    );

    // spec 2.10: keep both CDC toggle histories across MEDIA and SOC software resets.
    edrv32_apb_async_bridge u_media_apb_async (
        // Source and destination clocks and resets.
        .clk_s_i(clk_sys_i),
        .rst_s_n_i(rst_sys_por_n_o),
        .clk_m_i(clk_mem_i),
        .rst_m_n_i(rst_mem_core_bus_n_w),

        // s_apb interface.
        .s_apb_paddr_i(media_sys_apb_paddr_w),
        .s_apb_psel_i(media_sys_apb_psel_w),
        .s_apb_penable_i(media_sys_apb_penable_w),
        .s_apb_pwrite_i(media_sys_apb_pwrite_w),
        .s_apb_pwdata_i(media_sys_apb_pwdata_w),
        .s_apb_pstrb_i(media_sys_apb_pstrb_w),
        .s_apb_prdata_o(media_sys_apb_prdata_w),
        .s_apb_pready_o(media_sys_apb_pready_w),
        .s_apb_pslverr_o(media_sys_apb_pslverr_w),

        // m_apb interface.
        .m_apb_paddr_o(media_mem_apb_paddr_w),
        .m_apb_psel_o(media_mem_apb_psel_w),
        .m_apb_penable_o(media_mem_apb_penable_w),
        .m_apb_pwrite_o(media_mem_apb_pwrite_w),
        .m_apb_pwdata_o(media_mem_apb_pwdata_w),
        .m_apb_pstrb_o(media_mem_apb_pstrb_w),
        .m_apb_prdata_i(media_mem_apb_prdata_w),
        .m_apb_pready_i(media_mem_apb_pready_w),
        .m_apb_pslverr_i(media_mem_apb_pslverr_w)
    );

    edrv32_bus_apb_decoder u_sys_apb_decoder (
        // Local APB clock and reset.
        .clk_i(clk_sys_i),
        .rst_n_i(rst_sys_apb_decoder_n_w),

        // Undecoded upstream APB.
        .apb_paddr_i(sys_apb_paddr_w),
        .apb_psel_i(sys_apb_psel_w),
        .apb_penable_i(sys_apb_penable_w),
        .apb_pwrite_i(sys_apb_pwrite_w),
        .apb_pwdata_i(sys_apb_pwdata_w),
        .apb_pstrb_i(sys_apb_pstrb_w),
        .apb_prdata_o(sys_apb_prdata_w),
        .apb_pready_o(sys_apb_pready_w),
        .apb_pslverr_o(sys_apb_pslverr_w),

        // Slot APB interfaces; reserved slots are tied to ready/error at the caller.
        .slot_paddr_o(sys_slot_paddr_w),
        .slot_psel_o(sys_slot_psel_w),
        .slot_penable_o(sys_slot_penable_w),
        .slot_pwrite_o(sys_slot_pwrite_w),
        .slot_pwdata_o(sys_slot_pwdata_w),
        .slot_pstrb_o(sys_slot_pstrb_w),
        .slot_prdata_i(sys_slot_prdata_w),
        .slot_pready_i(sys_slot_pready_w),
        .slot_pslverr_i(sys_slot_pslverr_w)
    );

    edrv32_bus_apb_decoder u_media_apb_decoder (
        // spec 2.10: the media decoder shares the bridge destination reset boundary.
        .clk_i(clk_mem_i),
        .rst_n_i(rst_mem_core_bus_n_w),

        // Undecoded upstream APB.
        .apb_paddr_i(media_mem_apb_paddr_w),
        .apb_psel_i(media_mem_apb_psel_w),
        .apb_penable_i(media_mem_apb_penable_w),
        .apb_pwrite_i(media_mem_apb_pwrite_w),
        .apb_pwdata_i(media_mem_apb_pwdata_w),
        .apb_pstrb_i(media_mem_apb_pstrb_w),
        .apb_prdata_o(media_mem_apb_prdata_w),
        .apb_pready_o(media_mem_apb_pready_w),
        .apb_pslverr_o(media_mem_apb_pslverr_w),

        // Slot APB interfaces; reserved slots are tied to ready/error at the caller.
        .slot_paddr_o(media_apb_paddr_o),
        .slot_psel_o(media_apb_psel_o),
        .slot_penable_o(media_apb_penable_o),
        .slot_pwrite_o(media_apb_pwrite_o),
        .slot_pwdata_o(media_apb_pwdata_o),
        .slot_pstrb_o(media_apb_pstrb_o),
        .slot_prdata_i(media_apb_prdata_i),
        .slot_pready_i(media_apb_pready_i),
        .slot_pslverr_i(media_apb_pslverr_i)
    );

    edrv32_periph_uart u_uart (
        // Clock and reset.
        .clk_i(clk_sys_i),
        .rst_n_i(rst_sys_uart_n_w),

        // APB slave.
        .apb_paddr_i(sys_slot_paddr_w),
        .apb_psel_i(sys_slot_psel_w[0]),
        .apb_penable_i(sys_slot_penable_w),
        .apb_pwrite_i(sys_slot_pwrite_w),
        .apb_pwdata_i(sys_slot_pwdata_w),
        .apb_pstrb_i(sys_slot_pstrb_w),
        .apb_prdata_o(sys_slot_prdata_w[0 +: 32]),
        .apb_pready_o(sys_slot_pready_w[0]),
        .apb_pslverr_o(sys_slot_pslverr_w[0]),

        // UART pads.
        .uart0_rx_i(uart0_rx_i),
        .uart0_tx_o(uart0_tx_o),

        // Interrupt.
        .irq_o(irq_uart_w)
    );

    edrv32_periph_gpio u_gpio (
        // Clock and reset.
        .clk_i(clk_sys_i),
        .rst_n_i(rst_sys_gpio_n_w),

        // APB slave.
        .apb_paddr_i(sys_slot_paddr_w),
        .apb_psel_i(sys_slot_psel_w[1]),
        .apb_penable_i(sys_slot_penable_w),
        .apb_pwrite_i(sys_slot_pwrite_w),
        .apb_pwdata_i(sys_slot_pwdata_w),
        .apb_pstrb_i(sys_slot_pstrb_w),
        .apb_prdata_o(sys_slot_prdata_w[32 +: 32]),
        .apb_pready_o(sys_slot_pready_w[1]),
        .apb_pslverr_o(sys_slot_pslverr_w[1]),

        // GPIO pads.
        .gpio_i(gpio_i),
        .gpio_o(gpio_o),
        .gpio_oe_o(gpio_oe_o),

        // Interrupt.
        .irq_o(irq_gpio_w)
    );

    edrv32_periph_i2c u_i2c (
        // Clock and reset.
        .clk_i(clk_sys_i),
        .rst_n_i(rst_sys_i2c_n_w),

        // APB slave.
        .apb_paddr_i(sys_slot_paddr_w),
        .apb_psel_i(sys_slot_psel_w[4]),
        .apb_penable_i(sys_slot_penable_w),
        .apb_pwrite_i(sys_slot_pwrite_w),
        .apb_pwdata_i(sys_slot_pwdata_w),
        .apb_pstrb_i(sys_slot_pstrb_w),
        .apb_prdata_o(sys_slot_prdata_w[128 +: 32]),
        .apb_pready_o(sys_slot_pready_w[4]),
        .apb_pslverr_o(sys_slot_pslverr_w[4]),

        // I2C pads: output data is always zero; OE drives low, otherwise releases.
        .i2c0_scl_i(i2c0_scl_i),
        .i2c0_scl_o(i2c0_scl_o),
        .i2c0_scl_oe_o(i2c0_scl_oe_o),
        .i2c0_sda_i(i2c0_sda_i),
        .i2c0_sda_o(i2c0_sda_o),
        .i2c0_sda_oe_o(i2c0_sda_oe_o),

        // Interrupt.
        .irq_o(irq_i2c_w)
    );

    edrv32_periph_sysctrl u_sysctrl (
        // Clock and power-on reset.
        .clk_i(clk_sys_i),
        .rst_n_i(rst_sys_por_n_o),

        // APB slave.
        .apb_paddr_i(sys_slot_paddr_w),
        .apb_psel_i(sys_slot_psel_w[6]),
        .apb_penable_i(sys_slot_penable_w),
        .apb_pwrite_i(sys_slot_pwrite_w),
        .apb_pwdata_i(sys_slot_pwdata_w),
        .apb_pstrb_i(sys_slot_pstrb_w),
        .apb_prdata_o(sys_slot_prdata_w[192 +: 32]),
        .apb_pready_o(sys_slot_pready_w[6]),
        .apb_pslverr_o(sys_slot_pslverr_w[6]),

        // System status and software request pulses.
        .mem_ready_i(mem_ready_i),
        .soft_reset_media_o(soft_reset_media_w),
        .soft_reset_soc_o(soft_reset_soc_w),
        .sim_exit_valid_o(sim_exit_valid_o),
        .sim_exit_code_o(sim_exit_code_o)
    );

    edrv32_soc_reset_ctrl u_reset_ctrl (
        // Clocks and external asynchronous reset.
        .clk_sys_i(clk_sys_i),
        .clk_mem_i(clk_mem_i),
        .clk_pix_i(clk_pix_i),
        .clk_npu_i(clk_npu_i),
        .clk_cam0_i(cam0_pclk_i),
        .clk_cam1_i(cam1_pclk_i),
        .clk_eth_rx_i(eth_rx_clk_i),
        .clk_eth_tx_i(eth_tx_clk_i),
        .rst_n_i(rst_n_i),

        // Ready level and clk_sys software request pulses.
        .mem_ready_i(mem_ready_i),
        .soft_reset_media_i(soft_reset_media_w),
        .soft_reset_soc_i(soft_reset_soc_w),

        // Resets synchronously released in their respective domains.
        .rst_sys_por_n_o(rst_sys_por_n_o),
        .rst_sys_n_o(rst_sys_n_o),
        .rst_mem_core_n_o(rst_mem_core_n_o),
        .rst_mem_n_o(rst_mem_n_o),
        .rst_pix_n_o(rst_pix_n_o),
        .rst_npu_n_o(rst_npu_n_o),
        .rst_cam0_n_o(rst_cam0_n_o),
        .rst_cam1_n_o(rst_cam1_n_o),
        .rst_eth_rx_n_o(rst_eth_rx_n_o),
        .rst_eth_tx_n_o(rst_eth_tx_n_o)
    );

    // Parallel replicas retain the existing sys-region reset release edge.
    wire rst_sys_xbar_n_w;
    edrv32_reset_copy u_reset_sys_xbar_n (
        .clk_i(clk_sys_i),
        .rst_n_i(rst_sys_n_o),
        .rst_n_o(rst_sys_xbar_n_w)
    );
    wire rst_sys_rom_n_w;
    edrv32_reset_copy u_reset_sys_rom_n (
        .clk_i(clk_sys_i),
        .rst_n_i(rst_sys_n_o),
        .rst_n_o(rst_sys_rom_n_w)
    );
    wire rst_sys_sram_n_w;
    edrv32_reset_copy u_reset_sys_sram_n (
        .clk_i(clk_sys_i),
        .rst_n_i(rst_sys_n_o),
        .rst_n_o(rst_sys_sram_n_w)
    );
    wire rst_sys_clint_n_w;
    edrv32_reset_copy u_reset_sys_clint_n (
        .clk_i(clk_sys_i),
        .rst_n_i(rst_sys_n_o),
        .rst_n_o(rst_sys_clint_n_w)
    );
    wire rst_sys_plic_n_w;
    edrv32_reset_copy u_reset_sys_plic_n (
        .clk_i(clk_sys_i),
        .rst_n_i(rst_sys_n_o),
        .rst_n_o(rst_sys_plic_n_w)
    );
    wire rst_sys_apb_bridge_n_w;
    edrv32_reset_copy u_reset_sys_apb_bridge_n (
        .clk_i(clk_sys_i),
        .rst_n_i(rst_sys_n_o),
        .rst_n_o(rst_sys_apb_bridge_n_w)
    );
    wire rst_sys_media_apb_bridge_n_w;
    edrv32_reset_copy u_reset_sys_media_apb_bridge_n (
        .clk_i(clk_sys_i),
        .rst_n_i(rst_sys_n_o),
        .rst_n_o(rst_sys_media_apb_bridge_n_w)
    );
    wire rst_sys_apb_decoder_n_w;
    edrv32_reset_copy u_reset_sys_apb_decoder_n (
        .clk_i(clk_sys_i),
        .rst_n_i(rst_sys_n_o),
        .rst_n_o(rst_sys_apb_decoder_n_w)
    );
    wire rst_sys_uart_n_w;
    edrv32_reset_copy u_reset_sys_uart_n (
        .clk_i(clk_sys_i),
        .rst_n_i(rst_sys_n_o),
        .rst_n_o(rst_sys_uart_n_w)
    );
    wire rst_sys_gpio_n_w;
    edrv32_reset_copy u_reset_sys_gpio_n (
        .clk_i(clk_sys_i),
        .rst_n_i(rst_sys_n_o),
        .rst_n_o(rst_sys_gpio_n_w)
    );
    wire rst_sys_i2c_n_w;
    edrv32_reset_copy u_reset_sys_i2c_n (
        .clk_i(clk_sys_i),
        .rst_n_i(rst_sys_n_o),
        .rst_n_o(rst_sys_i2c_n_w)
    );
endmodule
