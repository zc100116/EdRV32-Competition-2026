// ============================================================================
// File        : tb_pango_ddr_ip_interconnect.sv
// Description : Two AXI masters -> generic 256-bit M:1 interconnect -> Pango
//               adapter -> generated DDR controller/PHY and DDR3 model.
// ============================================================================

`timescale 1ns/1ps

module tb_pango_ddr_ip_interconnect;

    localparam integer NUM_M = 2;
    localparam integer ID_W = 4;
    localparam integer S_ID_W = 5;
    localparam integer COUNT_W = S_ID_W + 1;

    reg ref_clk_r;
    reg resetn_r;
    wire core_clk_w;
    wire init_done_w;
    wire init_error_w;

    wire [NUM_M*ID_W-1:0] m_awid_w;
    wire [NUM_M*32-1:0] m_awaddr_w;
    wire [NUM_M*8-1:0] m_awlen_w;
    wire [NUM_M*3-1:0] m_awsize_w;
    wire [NUM_M*2-1:0] m_awburst_w;
    wire [NUM_M*4-1:0] m_awqos_w;
    wire [NUM_M-1:0] m_awvalid_w;
    wire [NUM_M-1:0] m_awready_w;
    wire [NUM_M*256-1:0] m_wdata_w;
    wire [NUM_M*32-1:0] m_wstrb_w;
    wire [NUM_M-1:0] m_wlast_w;
    wire [NUM_M-1:0] m_wvalid_w;
    wire [NUM_M-1:0] m_wready_w;
    wire [NUM_M*ID_W-1:0] m_bid_w;
    wire [NUM_M*2-1:0] m_bresp_w;
    wire [NUM_M-1:0] m_bvalid_w;
    wire [NUM_M-1:0] m_bready_w;
    wire [NUM_M*ID_W-1:0] m_arid_w;
    wire [NUM_M*32-1:0] m_araddr_w;
    wire [NUM_M*8-1:0] m_arlen_w;
    wire [NUM_M*3-1:0] m_arsize_w;
    wire [NUM_M*2-1:0] m_arburst_w;
    wire [NUM_M*4-1:0] m_arqos_w;
    wire [NUM_M-1:0] m_arvalid_w;
    wire [NUM_M-1:0] m_arready_w;
    wire [NUM_M*ID_W-1:0] m_rid_w;
    wire [NUM_M*256-1:0] m_rdata_w;
    wire [NUM_M*2-1:0] m_rresp_w;
    wire [NUM_M-1:0] m_rlast_w;
    wire [NUM_M-1:0] m_rvalid_w;
    wire [NUM_M-1:0] m_rready_w;

    wire [S_ID_W-1:0] s_awid_w;
    wire [31:0] s_awaddr_w;
    wire [7:0] s_awlen_w;
    wire [2:0] s_awsize_w;
    wire [1:0] s_awburst_w;
    wire [3:0] s_awqos_w;
    wire s_awvalid_w;
    wire s_awready_w;
    wire [255:0] s_wdata_w;
    wire [31:0] s_wstrb_w;
    wire s_wlast_w;
    wire s_wvalid_w;
    wire s_wready_w;
    wire [S_ID_W-1:0] s_bid_w;
    wire [1:0] s_bresp_w;
    wire s_bvalid_w;
    wire s_bready_w;
    wire [S_ID_W-1:0] s_arid_w;
    wire [31:0] s_araddr_w;
    wire [7:0] s_arlen_w;
    wire [2:0] s_arsize_w;
    wire [1:0] s_arburst_w;
    wire [3:0] s_arqos_w;
    wire s_arvalid_w;
    wire s_arready_w;
    wire [S_ID_W-1:0] s_rid_w;
    wire [255:0] s_rdata_w;
    wire [1:0] s_rresp_w;
    wire s_rlast_w;
    wire s_rvalid_w;
    wire s_rready_w;

    wire [27:0] ui_awaddr_w;
    wire [3:0] ui_awid_w;
    wire [3:0] ui_awlen_w;
    wire ui_awvalid_w;
    wire ui_awready_w;
    wire [255:0] ui_wdata_w;
    wire [31:0] ui_wstrb_w;
    wire ui_wready_w;
    wire [3:0] ui_wid_w;
    wire ui_wlast_w;
    wire [27:0] ui_araddr_w;
    wire [3:0] ui_arid_w;
    wire [3:0] ui_arlen_w;
    wire ui_arvalid_w;
    wire ui_arready_w;
    wire [255:0] ui_rdata_w;
    wire [3:0] ui_rid_w;
    wire ui_rlast_w;
    wire ui_rvalid_w;
    wire adapter_error_w;
    wire read_error_w;
    wire write_error_w;

    always #4 ref_clk_r = ~ref_clk_r;

    GTP_GRS GRS_INST (
        .GRS_N(resetn_r)
    );

    axi256_master_bfm #(.ID_W(ID_W), .TAG(0)) u_m0 (
        .clk_i(core_clk_w), .rst_n_i(resetn_r),
        .awid_o(m_awid_w[0 +: ID_W]), .awaddr_o(m_awaddr_w[0 +: 32]),
        .awlen_o(m_awlen_w[0 +: 8]), .awsize_o(m_awsize_w[0 +: 3]),
        .awburst_o(m_awburst_w[0 +: 2]), .awqos_o(m_awqos_w[0 +: 4]),
        .awvalid_o(m_awvalid_w[0]), .awready_i(m_awready_w[0]),
        .wdata_o(m_wdata_w[0 +: 256]), .wstrb_o(m_wstrb_w[0 +: 32]),
        .wlast_o(m_wlast_w[0]), .wvalid_o(m_wvalid_w[0]),
        .wready_i(m_wready_w[0]), .bid_i(m_bid_w[0 +: ID_W]),
        .bresp_i(m_bresp_w[0 +: 2]), .bvalid_i(m_bvalid_w[0]),
        .bready_o(m_bready_w[0]),
        .arid_o(m_arid_w[0 +: ID_W]), .araddr_o(m_araddr_w[0 +: 32]),
        .arlen_o(m_arlen_w[0 +: 8]), .arsize_o(m_arsize_w[0 +: 3]),
        .arburst_o(m_arburst_w[0 +: 2]), .arqos_o(m_arqos_w[0 +: 4]),
        .arvalid_o(m_arvalid_w[0]), .arready_i(m_arready_w[0]),
        .rid_i(m_rid_w[0 +: ID_W]), .rdata_i(m_rdata_w[0 +: 256]),
        .rresp_i(m_rresp_w[0 +: 2]), .rlast_i(m_rlast_w[0]),
        .rvalid_i(m_rvalid_w[0]), .rready_o(m_rready_w[0])
    );

    axi256_master_bfm #(.ID_W(ID_W), .TAG(1)) u_m1 (
        .clk_i(core_clk_w), .rst_n_i(resetn_r),
        .awid_o(m_awid_w[ID_W +: ID_W]), .awaddr_o(m_awaddr_w[32 +: 32]),
        .awlen_o(m_awlen_w[8 +: 8]), .awsize_o(m_awsize_w[3 +: 3]),
        .awburst_o(m_awburst_w[2 +: 2]), .awqos_o(m_awqos_w[4 +: 4]),
        .awvalid_o(m_awvalid_w[1]), .awready_i(m_awready_w[1]),
        .wdata_o(m_wdata_w[256 +: 256]), .wstrb_o(m_wstrb_w[32 +: 32]),
        .wlast_o(m_wlast_w[1]), .wvalid_o(m_wvalid_w[1]),
        .wready_i(m_wready_w[1]), .bid_i(m_bid_w[ID_W +: ID_W]),
        .bresp_i(m_bresp_w[2 +: 2]), .bvalid_i(m_bvalid_w[1]),
        .bready_o(m_bready_w[1]),
        .arid_o(m_arid_w[ID_W +: ID_W]), .araddr_o(m_araddr_w[32 +: 32]),
        .arlen_o(m_arlen_w[8 +: 8]), .arsize_o(m_arsize_w[3 +: 3]),
        .arburst_o(m_arburst_w[2 +: 2]), .arqos_o(m_arqos_w[4 +: 4]),
        .arvalid_o(m_arvalid_w[1]), .arready_i(m_arready_w[1]),
        .rid_i(m_rid_w[ID_W +: ID_W]), .rdata_i(m_rdata_w[256 +: 256]),
        .rresp_i(m_rresp_w[2 +: 2]), .rlast_i(m_rlast_w[1]),
        .rvalid_i(m_rvalid_w[1]), .rready_o(m_rready_w[1])
    );

    edrv32_axi_m2s_interconnect #(
        .NUM_M(NUM_M), .ADDR_W(32), .DATA_W(256), .ID_W(ID_W),
        .S_ID_W(S_ID_W), .LEN_W(8), .WR_ORDER_DEPTH(8),
        .STARVE_CYCLES(64), .COUNT_W(COUNT_W)
    ) u_interconnect (
        .clk_i(core_clk_w), .rst_n_i(resetn_r), .accept_i(init_done_w),
        .m_awid_i(m_awid_w), .m_awaddr_i(m_awaddr_w), .m_awlen_i(m_awlen_w),
        .m_awsize_i(m_awsize_w), .m_awburst_i(m_awburst_w),
        .m_awqos_i(m_awqos_w), .m_awvalid_i(m_awvalid_w),
        .m_awready_o(m_awready_w), .m_wdata_i(m_wdata_w),
        .m_wstrb_i(m_wstrb_w), .m_wlast_i(m_wlast_w),
        .m_wvalid_i(m_wvalid_w), .m_wready_o(m_wready_w),
        .m_bid_o(m_bid_w), .m_bresp_o(m_bresp_w), .m_bvalid_o(m_bvalid_w),
        .m_bready_i(m_bready_w), .m_arid_i(m_arid_w),
        .m_araddr_i(m_araddr_w), .m_arlen_i(m_arlen_w),
        .m_arsize_i(m_arsize_w), .m_arburst_i(m_arburst_w),
        .m_arqos_i(m_arqos_w), .m_arvalid_i(m_arvalid_w),
        .m_arready_o(m_arready_w), .m_rid_o(m_rid_w),
        .m_rdata_o(m_rdata_w), .m_rresp_o(m_rresp_w),
        .m_rlast_o(m_rlast_w), .m_rvalid_o(m_rvalid_w),
        .m_rready_i(m_rready_w), .m_read_urgent_i(2'b00),
        .m_write_urgent_i(2'b00), .m_read_weight_i({4'd4, 4'd1}),
        .m_write_weight_i({4'd4, 4'd1}), .m_read_credit_i({5'd4, 5'd4}),
        .m_write_credit_i({5'd4, 5'd4}),
        .s_awid_o(s_awid_w), .s_awaddr_o(s_awaddr_w), .s_awlen_o(s_awlen_w),
        .s_awsize_o(s_awsize_w), .s_awburst_o(s_awburst_w),
        .s_awqos_o(s_awqos_w), .s_awvalid_o(s_awvalid_w),
        .s_awready_i(s_awready_w), .s_wdata_o(s_wdata_w),
        .s_wstrb_o(s_wstrb_w), .s_wlast_o(s_wlast_w),
        .s_wvalid_o(s_wvalid_w), .s_wready_i(s_wready_w),
        .s_bid_i(s_bid_w), .s_bresp_i(s_bresp_w), .s_bvalid_i(s_bvalid_w),
        .s_bready_o(s_bready_w), .s_arid_o(s_arid_w),
        .s_araddr_o(s_araddr_w), .s_arlen_o(s_arlen_w),
        .s_arsize_o(s_arsize_w), .s_arburst_o(s_arburst_w),
        .s_arqos_o(s_arqos_w), .s_arvalid_o(s_arvalid_w),
        .s_arready_i(s_arready_w), .s_rid_i(s_rid_w),
        .s_rdata_i(s_rdata_w), .s_rresp_i(s_rresp_w),
        .s_rlast_i(s_rlast_w), .s_rvalid_i(s_rvalid_w),
        .s_rready_o(s_rready_w), .read_outstanding_o(),
        .write_outstanding_o(), .read_protocol_error_o(read_error_w),
        .write_protocol_error_o(write_error_w)
    );

    edrv32_pango_ddr_axi_adapter #(.ID_W(S_ID_W)) u_adapter (
        .clk_i(core_clk_w), .rst_n_i(resetn_r), .init_done_i(init_done_w),
        .s_awid_i(s_awid_w), .s_awaddr_i(s_awaddr_w), .s_awlen_i(s_awlen_w),
        .s_awsize_i(s_awsize_w), .s_awburst_i(s_awburst_w),
        .s_awvalid_i(s_awvalid_w), .s_awready_o(s_awready_w),
        .s_wdata_i(s_wdata_w), .s_wstrb_i(s_wstrb_w), .s_wlast_i(s_wlast_w),
        .s_wvalid_i(s_wvalid_w), .s_wready_o(s_wready_w),
        .s_bid_o(s_bid_w), .s_bresp_o(s_bresp_w), .s_bvalid_o(s_bvalid_w),
        .s_bready_i(s_bready_w), .s_arid_i(s_arid_w),
        .s_araddr_i(s_araddr_w), .s_arlen_i(s_arlen_w),
        .s_arsize_i(s_arsize_w), .s_arburst_i(s_arburst_w),
        .s_arvalid_i(s_arvalid_w), .s_arready_o(s_arready_w),
        .s_rid_o(s_rid_w), .s_rdata_o(s_rdata_w), .s_rresp_o(s_rresp_w),
        .s_rlast_o(s_rlast_w), .s_rvalid_o(s_rvalid_w), .s_rready_i(s_rready_w),
        .ui_awaddr_o(ui_awaddr_w), .ui_awid_o(ui_awid_w),
        .ui_awlen_o(ui_awlen_w), .ui_awvalid_o(ui_awvalid_w),
        .ui_awready_i(ui_awready_w), .ui_wdata_o(ui_wdata_w),
        .ui_wstrb_o(ui_wstrb_w), .ui_wready_i(ui_wready_w),
        .ui_wusero_id_i(ui_wid_w), .ui_wusero_last_i(ui_wlast_w),
        .ui_araddr_o(ui_araddr_w), .ui_arid_o(ui_arid_w),
        .ui_arlen_o(ui_arlen_w), .ui_arvalid_o(ui_arvalid_w),
        .ui_arready_i(ui_arready_w), .ui_rdata_i(ui_rdata_w),
        .ui_rid_i(ui_rid_w), .ui_rlast_i(ui_rlast_w),
        .ui_rvalid_i(ui_rvalid_w), .protocol_error_o(adapter_error_w)
    );

    pango_ddr200h_model u_model (
        .ref_clk_i(ref_clk_r), .resetn_i(resetn_r),
        .core_clk_o(core_clk_w), .init_done_o(init_done_w),
        .init_error_o(init_error_w), .ui_awaddr_i(ui_awaddr_w),
        .ui_awid_i(ui_awid_w), .ui_awlen_i(ui_awlen_w),
        .ui_awvalid_i(ui_awvalid_w), .ui_awready_o(ui_awready_w),
        .ui_wdata_i(ui_wdata_w), .ui_wstrb_i(ui_wstrb_w),
        .ui_wready_o(ui_wready_w), .ui_wid_o(ui_wid_w),
        .ui_wlast_o(ui_wlast_w), .ui_araddr_i(ui_araddr_w),
        .ui_arid_i(ui_arid_w), .ui_arlen_i(ui_arlen_w),
        .ui_arvalid_i(ui_arvalid_w), .ui_arready_o(ui_arready_w),
        .ui_rdata_o(ui_rdata_w), .ui_rid_o(ui_rid_w),
        .ui_rlast_o(ui_rlast_w), .ui_rvalid_o(ui_rvalid_w)
    );

    initial begin
        ref_clk_r = 0;
        resetn_r = 0;
        #100 resetn_r = 1;
        wait (init_done_w || init_error_w);
        if (!init_done_w || init_error_w)
            $fatal(1, "DDR training failed");

        fork
            u_m0.write_burst(32'h0001_0000, 4'h3, 16, 32'ha100_0000);
            u_m1.write_burst(32'h0002_0000, 4'h7, 16, 32'hb200_0000);
        join
        fork
            u_m0.read_check(32'h0001_0000, 4'h3, 16, 32'ha100_0000);
            u_m1.read_check(32'h0002_0000, 4'h7, 16, 32'hb200_0000);
        join

        if (adapter_error_w || read_error_w || write_error_w)
            $fatal(1, "Protocol error adapter=%0d read=%0d write=%0d",
                   adapter_error_w, read_error_w, write_error_w);
        $display("PANGO_DDR_IP_INTERCONNECT_PASS");
        $finish;
    end

    initial begin
        #1200000;
        $fatal(1, "Pango DDR interconnect/IP timeout");
    end

endmodule
