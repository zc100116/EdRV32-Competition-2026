// ============================================================================
// File        : ddr_test_stub.sv
// Author      : Edward ZC
// Description : Verilator structural-lint stub for the generated Pango DDR IP.
// Notes       : This is not a memory model and must never be used as board RTL.
// ============================================================================
module ddr_test (
    input wire pll_refclk_in, input wire top_rst_n,
    output wire pll_aclk_0, output wire pll_aclk_1,
    output wire pll_aclk_2, output wire pll_lock,
    output wire ddrphy_rst_done, output wire ddrc_init_done,
    input wire ddrc_rst, input wire areset_0, input wire aclk_0,
    input wire [7:0] awid_0, input wire [31:0] awaddr_0,
    input wire [7:0] awlen_0, input wire [2:0] awsize_0,
    input wire [1:0] awburst_0, input wire awlock_0,
    input wire awvalid_0, output wire awready_0,
    input wire awurgent_0, input wire awpoison_0,
    input wire [127:0] wdata_0, input wire [15:0] wstrb_0,
    input wire wlast_0, input wire wvalid_0, output wire wready_0,
    output wire [7:0] bid_0, output wire [1:0] bresp_0,
    output wire bvalid_0, input wire bready_0,
    input wire [7:0] arid_0, input wire [31:0] araddr_0,
    input wire [7:0] arlen_0, input wire [2:0] arsize_0,
    input wire [1:0] arburst_0, input wire arlock_0,
    input wire arvalid_0, output wire arready_0,
    input wire arpoison_0, input wire arurgent_0,
    output wire [7:0] rid_0, output wire [127:0] rdata_0,
    output wire [1:0] rresp_0, output wire rlast_0,
    output wire rvalid_0, input wire rready_0,
    input wire csysreq_0, output wire csysack_0,
    output wire cactive_0, input wire csysreq_ddrc,
    output wire csysack_ddrc, output wire cactive_ddrc,
    input wire pad_loop_in, input wire pad_loop_in_h,
    output wire pad_rstn_ch0, output wire pad_ddr_clk_w,
    output wire pad_ddr_clkn_w, output wire pad_csn_ch0,
    output wire [15:0] pad_addr_ch0, inout wire [15:0] pad_dq_ch0,
    inout wire [1:0] pad_dqs_ch0, inout wire [1:0] pad_dqsn_ch0,
    output wire [1:0] pad_dm_rdqs_ch0, output wire pad_cke_ch0,
    output wire pad_odt_ch0, output wire pad_rasn_ch0,
    output wire pad_casn_ch0, output wire pad_wen_ch0,
    output wire [2:0] pad_ba_ch0, output wire pad_loop_out,
    output wire pad_loop_out_h
);
    assign pll_aclk_0 = pll_refclk_in;
    assign pll_aclk_1 = 1'b0;
    assign pll_aclk_2 = 1'b0;
    assign pll_lock = top_rst_n;
    assign ddrphy_rst_done = top_rst_n;
`ifdef EDRV32_DDR_STUB_INIT_FAIL
    assign ddrc_init_done = 1'b0;
`else
    assign ddrc_init_done = top_rst_n;
`endif
    assign awready_0 = 1'b0;
    assign wready_0 = 1'b0;
    assign bid_0 = 8'b0;
    assign bresp_0 = 2'b0;
    assign bvalid_0 = 1'b0;
    assign arready_0 = 1'b0;
    assign rid_0 = 8'b0;
    assign rdata_0 = 128'b0;
    assign rresp_0 = 2'b0;
    assign rlast_0 = 1'b0;
    assign rvalid_0 = 1'b0;
    assign csysack_0 = csysreq_0;
    assign cactive_0 = 1'b0;
    assign csysack_ddrc = csysreq_ddrc;
    assign cactive_ddrc = 1'b0;
    assign pad_rstn_ch0 = top_rst_n;
    assign pad_ddr_clk_w = 1'b0;
    assign pad_ddr_clkn_w = 1'b0;
    assign pad_csn_ch0 = 1'b1;
    assign pad_addr_ch0 = 16'b0;
    assign pad_dq_ch0 = 16'bz;
    assign pad_dqs_ch0 = 2'bz;
    assign pad_dqsn_ch0 = 2'bz;
    assign pad_dm_rdqs_ch0 = 2'b0;
    assign pad_cke_ch0 = 1'b0;
    assign pad_odt_ch0 = 1'b0;
    assign pad_rasn_ch0 = 1'b1;
    assign pad_casn_ch0 = 1'b1;
    assign pad_wen_ch0 = 1'b1;
    assign pad_ba_ch0 = 3'b0;
    assign pad_loop_out = pad_loop_in;
    assign pad_loop_out_h = pad_loop_in_h;

    // Keep AXI/control inputs visible to lint without inventing behavior.
    wire unused_w = &{1'b0, ddrc_rst, areset_0, aclk_0, awid_0,
                      awaddr_0, awlen_0, awsize_0, awburst_0, awlock_0,
                      awvalid_0, awurgent_0, awpoison_0, wdata_0, wstrb_0,
                      wlast_0, wvalid_0, bready_0, arid_0, araddr_0, arlen_0,
                      arsize_0, arburst_0, arlock_0, arvalid_0, arpoison_0,
                      arurgent_0, rready_0};
endmodule
