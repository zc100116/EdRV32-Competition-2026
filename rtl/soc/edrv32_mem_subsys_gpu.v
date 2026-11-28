// File: edrv32_mem_subsys_gpu.v
// Spec: gpu-soc-spec 6.2, 8.3; mem-subsys-spec 1, 3.1, 5, 6; edrv32-soc-spec 4.2.
// Description: Connect the DDR gateway and five-port crossbar.
//              ETH exclusively owns P4 with its one-bit local ID.
// Clock domains: clk_sys and clk_mem; resets are supplied by reset_ctrl.
module edrv32_mem_subsys_gpu (
    // Clocks.
    input wire clk_sys_i,
    input wire clk_mem_i,

    // Resets.
    input wire rst_sys_n_i,
    input wire rst_mem_core_n_i,

    // AXI64 system crossbar S6.
    input wire [3:0] gw_awid_i,
    input wire [31:0] gw_awaddr_i,
    input wire [7:0] gw_awlen_i,
    input wire gw_awvalid_i,
    output wire gw_awready_o,
    input wire [63:0] gw_wdata_i,
    input wire [7:0] gw_wstrb_i,
    input wire gw_wlast_i,
    input wire gw_wvalid_i,
    output wire gw_wready_o,
    output wire [3:0] gw_bid_o,
    output wire [1:0] gw_bresp_o,
    output wire gw_bvalid_o,
    input wire gw_bready_i,
    input wire [3:0] gw_arid_i,
    input wire [31:0] gw_araddr_i,
    input wire [7:0] gw_arlen_i,
    input wire gw_arvalid_i,
    output wire gw_arready_o,
    output wire [3:0] gw_rid_o,
    output wire [63:0] gw_rdata_o,
    output wire [1:0] gw_rresp_o,
    output wire gw_rlast_o,
    output wire gw_rvalid_o,
    input wire gw_rready_i,
    input wire [2:0] gw_awsize_i,
    input wire [1:0] gw_awburst_i,
    input wire [2:0] gw_arsize_i,
    input wire [1:0] gw_arburst_i,

    // DISP read port P0.
    input wire p0_arid_i,
    input wire [31:0] p0_araddr_i,
    input wire [3:0] p0_arlen_i,
    input wire p0_arvalid_i,
    output wire p0_arready_o,
    output wire p0_rid_o,
    output wire [255:0] p0_rdata_o,
    output wire [1:0] p0_rresp_o,
    output wire p0_rlast_o,
    output wire p0_rvalid_o,
    input wire p0_rready_i,
    input wire p0_urgent_i,

    // AUD read port P1.
    input wire p1_arid_i,
    input wire [31:0] p1_araddr_i,
    input wire [3:0] p1_arlen_i,
    input wire p1_arvalid_i,
    output wire p1_arready_o,
    output wire p1_rid_o,
    output wire [255:0] p1_rdata_o,
    output wire [1:0] p1_rresp_o,
    output wire p1_rlast_o,
    output wire p1_rvalid_o,
    input wire p1_rready_i,
    input wire p1_urgent_i,

    // GPU read/write port P3.
    input wire p3_awid_i,
    input wire [31:0] p3_awaddr_i,
    input wire [3:0] p3_awlen_i,
    input wire p3_awvalid_i,
    output wire p3_awready_o,
    input wire [255:0] p3_wdata_i,
    input wire [31:0] p3_wstrb_i,
    input wire p3_wlast_i,
    input wire p3_wvalid_i,
    output wire p3_wready_o,
    output wire p3_bid_o,
    output wire [1:0] p3_bresp_o,
    output wire p3_bvalid_o,
    input wire p3_bready_i,
    input wire p3_arid_i,
    input wire [31:0] p3_araddr_i,
    input wire [3:0] p3_arlen_i,
    input wire p3_arvalid_i,
    output wire p3_arready_o,
    output wire p3_rid_o,
    output wire [255:0] p3_rdata_o,
    output wire [1:0] p3_rresp_o,
    output wire p3_rlast_o,
    output wire p3_rvalid_o,
    input wire p3_rready_i,

    // ETH exclusively owns crossbar P4.
    input wire eth_awid_i,
    input wire [31:0] eth_awaddr_i,
    input wire [3:0] eth_awlen_i,
    input wire eth_awvalid_i,
    output wire eth_awready_o,
    input wire [255:0] eth_wdata_i,
    input wire [31:0] eth_wstrb_i,
    input wire eth_wlast_i,
    input wire eth_wvalid_i,
    output wire eth_wready_o,
    output wire eth_bid_o,
    output wire [1:0] eth_bresp_o,
    output wire eth_bvalid_o,
    input wire eth_bready_i,
    input wire eth_arid_i,
    input wire [31:0] eth_araddr_i,
    input wire [3:0] eth_arlen_i,
    input wire eth_arvalid_i,
    output wire eth_arready_o,
    output wire eth_rid_o,
    output wire [255:0] eth_rdata_o,
    output wire [1:0] eth_rresp_o,
    output wire eth_rlast_o,
    output wire eth_rvalid_o,
    input wire eth_rready_i,

    // DDR controller AXI256 port without response backpressure.
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

    // MEM_XBAR media APB slot 8.
    input wire [11:0] xbar_apb_paddr_i,
    input wire xbar_apb_psel_i,
    input wire xbar_apb_penable_i,
    input wire xbar_apb_pwrite_i,
    input wire [31:0] xbar_apb_pwdata_i,
    input wire [3:0] xbar_apb_pstrb_i,
    output wire xbar_apb_pready_o,
    output wire [31:0] xbar_apb_prdata_o,
    output wire xbar_apb_pslverr_o,

    // Interrupt.
    output wire irq_mem_xbar_o
);

    // Register the complete no-backpressure DDR return together at the mem entrance.
    reg ddr_rvalid_r;
    reg [3:0] ddr_rid_r;
    reg [255:0] ddr_rdata_r;
    reg [1:0] ddr_rresp_r;
    reg ddr_rlast_r;
    always @(posedge clk_mem_i or negedge rst_mem_core_n_i) begin
        if (!rst_mem_core_n_i) ddr_rvalid_r <= 1'b0;
        else ddr_rvalid_r <= ddr_rvalid_i;
    end
    always @(posedge clk_mem_i) begin
        if (ddr_rvalid_i) begin
            ddr_rid_r <= ddr_rid_i;
            ddr_rdata_r <= ddr_rdata_i;
            ddr_rresp_r <= ddr_rresp_i;
            ddr_rlast_r <= ddr_rlast_i;
        end
    end

    // SoC 5.3: one preserved reset copy per destination region.
    wire [2:0] rst_mem_regs_n_w;
    wire rst_sys_gateway_n_w;
    wire [3:0] rst_mem_core_ctrl_n_w;
    wire [2:0] rst_mem_stat0_n_w;
    wire [2:0] rst_mem_stat1_n_w;
    wire [2:0] rst_mem_stat2_n_w;
    wire [2:0] rst_mem_stat3_n_w;
    wire [2:0] rst_mem_stat4_n_w;
    genvar reset_regs;
    generate
        for (reset_regs = 0; reset_regs < 3; reset_regs = reset_regs + 1) begin : g_reset_regs
            edrv32_reset_copy u_reset_mem_regs_n (
                .clk_i(clk_mem_i),
                .rst_n_i(rst_mem_core_n_i),
                .rst_n_o(rst_mem_regs_n_w[reset_regs])
            );
        end
    endgenerate
    edrv32_reset_copy u_reset_sys_gateway_n (
        .clk_i(clk_sys_i),
        .rst_n_i(rst_sys_n_i),
        .rst_n_o(rst_sys_gateway_n_w)
    );
    genvar rst_mem_core_ctrl_n_w_idx;
    generate
        for (rst_mem_core_ctrl_n_w_idx = 0; rst_mem_core_ctrl_n_w_idx < 4;
            rst_mem_core_ctrl_n_w_idx = rst_mem_core_ctrl_n_w_idx + 1) begin : g_core_ctrl_reset
            edrv32_reset_copy u_reset (
                .clk_i(clk_mem_i),
                .rst_n_i(rst_mem_core_n_i),
                .rst_n_o(rst_mem_core_ctrl_n_w[rst_mem_core_ctrl_n_w_idx])
            );
        end
    endgenerate
    genvar reset_stat0;
    generate
        for (reset_stat0 = 0; reset_stat0 < 3; reset_stat0 = reset_stat0 + 1) begin : g_reset_stat0
            edrv32_reset_copy u_reset_mem_stat0_n (
                .clk_i(clk_mem_i),
                .rst_n_i(rst_mem_core_n_i),
                .rst_n_o(rst_mem_stat0_n_w[reset_stat0])
            );
        end
    endgenerate
    genvar reset_stat1;
    generate
        for (reset_stat1 = 0; reset_stat1 < 3; reset_stat1 = reset_stat1 + 1) begin : g_reset_stat1
            edrv32_reset_copy u_reset_mem_stat1_n (
                .clk_i(clk_mem_i),
                .rst_n_i(rst_mem_core_n_i),
                .rst_n_o(rst_mem_stat1_n_w[reset_stat1])
            );
        end
    endgenerate
    genvar reset_stat2;
    generate
        for (reset_stat2 = 0; reset_stat2 < 3; reset_stat2 = reset_stat2 + 1) begin : g_reset_stat2
            edrv32_reset_copy u_reset_mem_stat2_n (
                .clk_i(clk_mem_i),
                .rst_n_i(rst_mem_core_n_i),
                .rst_n_o(rst_mem_stat2_n_w[reset_stat2])
            );
        end
    endgenerate
    genvar reset_stat3;
    generate
        for (reset_stat3 = 0; reset_stat3 < 3; reset_stat3 = reset_stat3 + 1) begin : g_reset_stat3
            edrv32_reset_copy u_reset_mem_stat3_n (
                .clk_i(clk_mem_i),
                .rst_n_i(rst_mem_core_n_i),
                .rst_n_o(rst_mem_stat3_n_w[reset_stat3])
            );
        end
    endgenerate
    genvar reset_stat4;
    generate
        for (reset_stat4 = 0; reset_stat4 < 3; reset_stat4 = reset_stat4 + 1) begin : g_reset_stat4
            edrv32_reset_copy u_reset_mem_stat4_n (
                .clk_i(clk_mem_i),
                .rst_n_i(rst_mem_core_n_i),
                .rst_n_o(rst_mem_stat4_n_w[reset_stat4])
            );
        end
    endgenerate


    // p2 internal AXI256 connections.
    wire p2_awid_w;
    wire [31:0] p2_awaddr_w;
    wire [3:0] p2_awlen_w;
    wire p2_awvalid_w;
    wire p2_awready_w;
    wire [255:0] p2_wdata_w;
    wire [31:0] p2_wstrb_w;
    wire p2_wlast_w;
    wire p2_wvalid_w;
    wire p2_wready_w;
    wire p2_bid_w;
    wire [1:0] p2_bresp_w;
    wire p2_bvalid_w;
    wire p2_bready_w;
    wire p2_arid_w;
    wire [31:0] p2_araddr_w;
    wire [3:0] p2_arlen_w;
    wire p2_arvalid_w;
    wire p2_arready_w;
    wire p2_rid_w;
    wire [255:0] p2_rdata_w;
    wire [1:0] p2_rresp_w;
    wire p2_rlast_w;
    wire p2_rvalid_w;
    wire p2_rready_w;

    edrv32_mem_ddr_gw u_gw (
        // Clocks and resets.
        .clk_sys_i(clk_sys_i),
        .clk_mem_i(clk_mem_i),
        .rst_sys_n_i(rst_sys_gateway_n_w),
        .rst_mem_n_i(rst_mem_gateway_n_w),

        // System crossbar AXI64.
        .s_axi_awid_i(gw_awid_i),
        .s_axi_awaddr_i(gw_awaddr_i),
        .s_axi_awlen_i(gw_awlen_i),
        .s_axi_awsize_i(gw_awsize_i),
        .s_axi_awburst_i(gw_awburst_i),
        .s_axi_awvalid_i(gw_awvalid_i),
        .s_axi_awready_o(gw_awready_o),
        .s_axi_wdata_i(gw_wdata_i),
        .s_axi_wstrb_i(gw_wstrb_i),
        .s_axi_wlast_i(gw_wlast_i),
        .s_axi_wvalid_i(gw_wvalid_i),
        .s_axi_wready_o(gw_wready_o),
        .s_axi_bid_o(gw_bid_o),
        .s_axi_bresp_o(gw_bresp_o),
        .s_axi_bvalid_o(gw_bvalid_o),
        .s_axi_bready_i(gw_bready_i),
        .s_axi_arid_i(gw_arid_i),
        .s_axi_araddr_i(gw_araddr_i),
        .s_axi_arlen_i(gw_arlen_i),
        .s_axi_arsize_i(gw_arsize_i),
        .s_axi_arburst_i(gw_arburst_i),
        .s_axi_arvalid_i(gw_arvalid_i),
        .s_axi_arready_o(gw_arready_o),
        .s_axi_rid_o(gw_rid_o),
        .s_axi_rdata_o(gw_rdata_o),
        .s_axi_rresp_o(gw_rresp_o),
        .s_axi_rlast_o(gw_rlast_o),
        .s_axi_rvalid_o(gw_rvalid_o),
        .s_axi_rready_i(gw_rready_i),

        // Converted AXI256 crossbar P2.
        .m_axi_awid_o(p2_awid_w),
        .m_axi_awaddr_o(p2_awaddr_w),
        .m_axi_awlen_o(p2_awlen_w),
        .m_axi_awvalid_o(p2_awvalid_w),
        .m_axi_awready_i(p2_awready_w),
        .m_axi_wdata_o(p2_wdata_w),
        .m_axi_wstrb_o(p2_wstrb_w),
        .m_axi_wlast_o(p2_wlast_w),
        .m_axi_wvalid_o(p2_wvalid_w),
        .m_axi_wready_i(p2_wready_w),
        .m_axi_bid_i(p2_bid_w),
        .m_axi_bresp_i(p2_bresp_w),
        .m_axi_bvalid_i(p2_bvalid_w),
        .m_axi_bready_o(p2_bready_w),
        .m_axi_arid_o(p2_arid_w),
        .m_axi_araddr_o(p2_araddr_w),
        .m_axi_arlen_o(p2_arlen_w),
        .m_axi_arvalid_o(p2_arvalid_w),
        .m_axi_arready_i(p2_arready_w),
        .m_axi_rid_i(p2_rid_w),
        .m_axi_rdata_i(p2_rdata_w),
        .m_axi_rresp_i(p2_rresp_w),
        .m_axi_rlast_i(p2_rlast_w),
        .m_axi_rvalid_i(p2_rvalid_w),
        .m_axi_rready_o(p2_rready_w)
    );

    edrv32_mem_xbar_gpu u_xbar (
        // Clock and reset.
        .clk_i(clk_mem_i),
        .rst_n_i(rst_mem_core_ctrl_n_w),
        .rst_mem_regs_n_i(rst_mem_regs_n_w),
        .rst_mem_stat_n_i({rst_mem_stat4_n_w,
            rst_mem_stat3_n_w, rst_mem_stat2_n_w, rst_mem_stat1_n_w, rst_mem_stat0_n_w}),

        // DISP read port P0.
        .p0_arid_i(p0_arid_i),
        .p0_araddr_i(p0_araddr_i),
        .p0_arlen_i(p0_arlen_i),
        .p0_arvalid_i(p0_arvalid_i),
        .p0_arready_o(p0_arready_o),
        .p0_rid_o(p0_rid_o),
        .p0_rdata_o(p0_rdata_o),
        .p0_rresp_o(p0_rresp_o),
        .p0_rlast_o(p0_rlast_o),
        .p0_rvalid_o(p0_rvalid_o),
        .p0_rready_i(p0_rready_i),
        .p0_urgent_i(p0_urgent_i),

        // AUD read port P1.
        .p1_arid_i(p1_arid_i),
        .p1_araddr_i(p1_araddr_i),
        .p1_arlen_i(p1_arlen_i),
        .p1_arvalid_i(p1_arvalid_i),
        .p1_arready_o(p1_arready_o),
        .p1_rid_o(p1_rid_o),
        .p1_rdata_o(p1_rdata_o),
        .p1_rresp_o(p1_rresp_o),
        .p1_rlast_o(p1_rlast_o),
        .p1_rvalid_o(p1_rvalid_o),
        .p1_rready_i(p1_rready_i),
        .p1_urgent_i(p1_urgent_i),

        // p2 interface.
        .p2_awid_i(p2_awid_w),
        .p2_awaddr_i(p2_awaddr_w),
        .p2_awlen_i(p2_awlen_w),
        .p2_awvalid_i(p2_awvalid_w),
        .p2_awready_o(p2_awready_w),
        .p2_wdata_i(p2_wdata_w),
        .p2_wstrb_i(p2_wstrb_w),
        .p2_wlast_i(p2_wlast_w),
        .p2_wvalid_i(p2_wvalid_w),
        .p2_wready_o(p2_wready_w),
        .p2_bid_o(p2_bid_w),
        .p2_bresp_o(p2_bresp_w),
        .p2_bvalid_o(p2_bvalid_w),
        .p2_bready_i(p2_bready_w),
        .p2_arid_i(p2_arid_w),
        .p2_araddr_i(p2_araddr_w),
        .p2_arlen_i(p2_arlen_w),
        .p2_arvalid_i(p2_arvalid_w),
        .p2_arready_o(p2_arready_w),
        .p2_rid_o(p2_rid_w),
        .p2_rdata_o(p2_rdata_w),
        .p2_rresp_o(p2_rresp_w),
        .p2_rlast_o(p2_rlast_w),
        .p2_rvalid_o(p2_rvalid_w),
        .p2_rready_i(p2_rready_w),

        // GPU read/write port P3.
        .p3_awid_i(p3_awid_i),
        .p3_awaddr_i(p3_awaddr_i),
        .p3_awlen_i(p3_awlen_i),
        .p3_awvalid_i(p3_awvalid_i),
        .p3_awready_o(p3_awready_o),
        .p3_wdata_i(p3_wdata_i),
        .p3_wstrb_i(p3_wstrb_i),
        .p3_wlast_i(p3_wlast_i),
        .p3_wvalid_i(p3_wvalid_i),
        .p3_wready_o(p3_wready_o),
        .p3_bid_o(p3_bid_o),
        .p3_bresp_o(p3_bresp_o),
        .p3_bvalid_o(p3_bvalid_o),
        .p3_bready_i(p3_bready_i),
        .p3_arid_i(p3_arid_i),
        .p3_araddr_i(p3_araddr_i),
        .p3_arlen_i(p3_arlen_i),
        .p3_arvalid_i(p3_arvalid_i),
        .p3_arready_o(p3_arready_o),
        .p3_rid_o(p3_rid_o),
        .p3_rdata_o(p3_rdata_o),
        .p3_rresp_o(p3_rresp_o),
        .p3_rlast_o(p3_rlast_o),
        .p3_rvalid_o(p3_rvalid_o),
        .p3_rready_i(p3_rready_i),

        // ETH crossbar P4.
        .p4_awid_i(eth_awid_i),
        .p4_awaddr_i(eth_awaddr_i),
        .p4_awlen_i(eth_awlen_i),
        .p4_awvalid_i(eth_awvalid_i),
        .p4_awready_o(eth_awready_o),
        .p4_wdata_i(eth_wdata_i),
        .p4_wstrb_i(eth_wstrb_i),
        .p4_wlast_i(eth_wlast_i),
        .p4_wvalid_i(eth_wvalid_i),
        .p4_wready_o(eth_wready_o),
        .p4_bid_o(eth_bid_o),
        .p4_bresp_o(eth_bresp_o),
        .p4_bvalid_o(eth_bvalid_o),
        .p4_bready_i(eth_bready_i),
        .p4_arid_i(eth_arid_i),
        .p4_araddr_i(eth_araddr_i),
        .p4_arlen_i(eth_arlen_i),
        .p4_arvalid_i(eth_arvalid_i),
        .p4_arready_o(eth_arready_o),
        .p4_rid_o(eth_rid_o),
        .p4_rdata_o(eth_rdata_o),
        .p4_rresp_o(eth_rresp_o),
        .p4_rlast_o(eth_rlast_o),
        .p4_rvalid_o(eth_rvalid_o),
        .p4_rready_i(eth_rready_i),

        // DDR controller AXI256 port without response backpressure.
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
        .ddr_rid_i(ddr_rid_r),
        .ddr_rdata_i(ddr_rdata_r),
        .ddr_rresp_i(ddr_rresp_r),
        .ddr_rlast_i(ddr_rlast_r),
        .ddr_rvalid_i(ddr_rvalid_r),

        // Media APB control registers.
        .apb_paddr_i(xbar_apb_paddr_i),
        .apb_psel_i(xbar_apb_psel_i),
        .apb_penable_i(xbar_apb_penable_i),
        .apb_pwrite_i(xbar_apb_pwrite_i),
        .apb_pwdata_i(xbar_apb_pwdata_i),
        .apb_pstrb_i(xbar_apb_pstrb_i),
        .apb_pready_o(xbar_apb_pready_o),
        .apb_prdata_o(xbar_apb_prdata_o),
        .apb_pslverr_o(xbar_apb_pslverr_o),

        // irq interface.
        .irq_o(irq_mem_xbar_o)
    );

    // The gateway and fabric formerly shared the same regional reset FF output.
    wire [2:0] rst_mem_gateway_n_w;
    genvar gateway_reset;
    generate
        for (gateway_reset = 0; gateway_reset < 3;
            gateway_reset = gateway_reset + 1) begin : g_gateway_reset
            edrv32_reset_copy u_reset_mem_gateway_n (
                .clk_i(clk_mem_i),
                .rst_n_i(rst_mem_core_n_i),
                .rst_n_o(rst_mem_gateway_n_w[gateway_reset])
            );
        end
    endgenerate
endmodule
