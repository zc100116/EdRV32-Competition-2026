// ============================================================================
// File        : tb_pango_ddr_ip_adapter.sv
// Description : Standard AXI -> project adapter -> generated DDR IP test.
// ============================================================================

`timescale 1ns/1ps

module tb_pango_ddr_ip_adapter;

    reg ref_clk_r;
    reg resetn_r;
    wire core_clk_w;
    wire init_done_w;
    wire init_error_w;

    wire [3:0] awid_w;
    wire [31:0] awaddr_w;
    wire [7:0] awlen_w;
    wire [2:0] awsize_w;
    wire [1:0] awburst_w;
    wire awvalid_w;
    wire awready_w;
    wire [255:0] wdata_w;
    wire [31:0] wstrb_w;
    wire wlast_w;
    wire wvalid_w;
    wire wready_w;
    wire [3:0] bid_w;
    wire [1:0] bresp_w;
    wire bvalid_w;
    wire bready_w;
    wire [3:0] arid_w;
    wire [31:0] araddr_w;
    wire [7:0] arlen_w;
    wire [2:0] arsize_w;
    wire [1:0] arburst_w;
    wire arvalid_w;
    wire arready_w;
    wire [3:0] rid_w;
    wire [255:0] rdata_w;
    wire [1:0] rresp_w;
    wire rlast_w;
    wire rvalid_w;
    wire rready_w;

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
    wire protocol_error_w;

    always #4 ref_clk_r = ~ref_clk_r;

    GTP_GRS GRS_INST (
        .GRS_N(resetn_r)
    );

    axi256_master_bfm #(.ID_W(4), .TAG(0)) u_master (
        .clk_i(core_clk_w), .rst_n_i(resetn_r),
        .awid_o(awid_w), .awaddr_o(awaddr_w), .awlen_o(awlen_w),
        .awsize_o(awsize_w), .awburst_o(awburst_w), .awqos_o(),
        .awvalid_o(awvalid_w), .awready_i(awready_w),
        .wdata_o(wdata_w), .wstrb_o(wstrb_w), .wlast_o(wlast_w),
        .wvalid_o(wvalid_w), .wready_i(wready_w),
        .bid_i(bid_w), .bresp_i(bresp_w), .bvalid_i(bvalid_w),
        .bready_o(bready_w),
        .arid_o(arid_w), .araddr_o(araddr_w), .arlen_o(arlen_w),
        .arsize_o(arsize_w), .arburst_o(arburst_w), .arqos_o(),
        .arvalid_o(arvalid_w), .arready_i(arready_w),
        .rid_i(rid_w), .rdata_i(rdata_w), .rresp_i(rresp_w),
        .rlast_i(rlast_w), .rvalid_i(rvalid_w), .rready_o(rready_w)
    );

    edrv32_pango_ddr_axi_adapter u_adapter (
        .clk_i(core_clk_w), .rst_n_i(resetn_r), .init_done_i(init_done_w),
        .s_awid_i(awid_w), .s_awaddr_i(awaddr_w), .s_awlen_i(awlen_w),
        .s_awsize_i(awsize_w), .s_awburst_i(awburst_w),
        .s_awvalid_i(awvalid_w), .s_awready_o(awready_w),
        .s_wdata_i(wdata_w), .s_wstrb_i(wstrb_w), .s_wlast_i(wlast_w),
        .s_wvalid_i(wvalid_w), .s_wready_o(wready_w),
        .s_bid_o(bid_w), .s_bresp_o(bresp_w), .s_bvalid_o(bvalid_w),
        .s_bready_i(bready_w),
        .s_arid_i(arid_w), .s_araddr_i(araddr_w), .s_arlen_i(arlen_w),
        .s_arsize_i(arsize_w), .s_arburst_i(arburst_w),
        .s_arvalid_i(arvalid_w), .s_arready_o(arready_w),
        .s_rid_o(rid_w), .s_rdata_o(rdata_w), .s_rresp_o(rresp_w),
        .s_rlast_o(rlast_w), .s_rvalid_o(rvalid_w), .s_rready_i(rready_w),
        .ui_awaddr_o(ui_awaddr_w), .ui_awid_o(ui_awid_w),
        .ui_awlen_o(ui_awlen_w), .ui_awvalid_o(ui_awvalid_w),
        .ui_awready_i(ui_awready_w), .ui_wdata_o(ui_wdata_w),
        .ui_wstrb_o(ui_wstrb_w), .ui_wready_i(ui_wready_w),
        .ui_wusero_id_i(ui_wid_w), .ui_wusero_last_i(ui_wlast_w),
        .ui_araddr_o(ui_araddr_w), .ui_arid_o(ui_arid_w),
        .ui_arlen_o(ui_arlen_w), .ui_arvalid_o(ui_arvalid_w),
        .ui_arready_i(ui_arready_w), .ui_rdata_i(ui_rdata_w),
        .ui_rid_i(ui_rid_w), .ui_rlast_i(ui_rlast_w),
        .ui_rvalid_i(ui_rvalid_w), .protocol_error_o(protocol_error_w)
    );

    pango_ddr200h_model u_model (
        .ref_clk_i(ref_clk_r), .resetn_i(resetn_r),
        .core_clk_o(core_clk_w), .init_done_o(init_done_w),
        .init_error_o(init_error_w),
        .ui_awaddr_i(ui_awaddr_w), .ui_awid_i(ui_awid_w),
        .ui_awlen_i(ui_awlen_w), .ui_awvalid_i(ui_awvalid_w),
        .ui_awready_o(ui_awready_w), .ui_wdata_i(ui_wdata_w),
        .ui_wstrb_i(ui_wstrb_w), .ui_wready_o(ui_wready_w),
        .ui_wid_o(ui_wid_w), .ui_wlast_o(ui_wlast_w),
        .ui_araddr_i(ui_araddr_w), .ui_arid_i(ui_arid_w),
        .ui_arlen_i(ui_arlen_w), .ui_arvalid_i(ui_arvalid_w),
        .ui_arready_o(ui_arready_w), .ui_rdata_o(ui_rdata_w),
        .ui_rid_o(ui_rid_w), .ui_rlast_o(ui_rlast_w),
        .ui_rvalid_o(ui_rvalid_w)
    );

    initial begin
        ref_clk_r = 0;
        resetn_r = 0;
        #100 resetn_r = 1;
        wait (init_done_w || init_error_w);
        if (!init_done_w || init_error_w)
            $fatal(1, "DDR training failed");

        u_master.write_burst(32'h0000_2000, 4'h1, 1, 32'h1100_0000);
        u_master.read_check (32'h0000_2000, 4'h1, 1, 32'h1100_0000);
        u_master.write_burst(32'h0000_3000, 4'h2, 8, 32'h2200_0000);
        u_master.read_check (32'h0000_3000, 4'h2, 8, 32'h2200_0000);
        u_master.write_burst(32'h0000_4000, 4'h3, 16, 32'h3300_0000);
        u_master.read_check (32'h0000_4000, 4'h3, 16, 32'h3300_0000);

        if (protocol_error_w)
            $fatal(1, "Adapter protocol_error asserted");
        $display("PANGO_DDR_IP_ADAPTER_PASS");
        $finish;
    end

    initial begin
        #1000000;
        $fatal(1, "Pango DDR adapter/IP timeout");
    end

endmodule
