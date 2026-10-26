// File: edrv32_mem_xbar_stub.sv
// Spec: mem-subsys 2.2; approved module port observations for M-V1.
// Description: Idle observation instance in the empty-response stub.
// Clock domain: clk_mem.
`timescale 1ns/1ps
module edrv32_mem_xbar_stub (
    input logic p0_arid_i,
    input logic [31:0] p0_araddr_i,
    input logic [3:0] p0_arlen_i,
    input logic p0_arvalid_i,
    output logic p0_arready_o,
    output logic p0_rid_o,
    output logic [255:0] p0_rdata_o,
    output logic [1:0] p0_rresp_o,
    output logic p0_rlast_o,
    output logic p0_rvalid_o,
    input logic p0_rready_i,
    input logic p0_urgent_i,
    input logic p1_awid_i,
    input logic [31:0] p1_awaddr_i,
    input logic [3:0] p1_awlen_i,
    input logic p1_awvalid_i,
    output logic p1_awready_o,
    input logic [255:0] p1_wdata_i,
    input logic [31:0] p1_wstrb_i,
    input logic p1_wlast_i,
    input logic p1_wvalid_i,
    output logic p1_wready_o,
    output logic p1_bid_o,
    output logic [1:0] p1_bresp_o,
    output logic p1_bvalid_o,
    input logic p1_bready_i,
    input logic p1_urgent_i,
    input logic p2_arid_i,
    input logic [31:0] p2_araddr_i,
    input logic [3:0] p2_arlen_i,
    input logic p2_arvalid_i,
    output logic p2_arready_o,
    output logic p2_rid_o,
    output logic [255:0] p2_rdata_o,
    output logic [1:0] p2_rresp_o,
    output logic p2_rlast_o,
    output logic p2_rvalid_o,
    input logic p2_rready_i,
    input logic p2_awid_i,
    input logic [31:0] p2_awaddr_i,
    input logic [3:0] p2_awlen_i,
    input logic p2_awvalid_i,
    output logic p2_awready_o,
    input logic [255:0] p2_wdata_i,
    input logic [31:0] p2_wstrb_i,
    input logic p2_wlast_i,
    input logic p2_wvalid_i,
    output logic p2_wready_o,
    output logic p2_bid_o,
    output logic [1:0] p2_bresp_o,
    output logic p2_bvalid_o,
    input logic p2_bready_i,
    input logic p3_arid_i,
    input logic [31:0] p3_araddr_i,
    input logic [3:0] p3_arlen_i,
    input logic p3_arvalid_i,
    output logic p3_arready_o,
    output logic p3_rid_o,
    output logic [255:0] p3_rdata_o,
    output logic [1:0] p3_rresp_o,
    output logic p3_rlast_o,
    output logic p3_rvalid_o,
    input logic p3_rready_i,
    input logic p3_awid_i,
    input logic [31:0] p3_awaddr_i,
    input logic [3:0] p3_awlen_i,
    input logic p3_awvalid_i,
    output logic p3_awready_o,
    input logic [255:0] p3_wdata_i,
    input logic [31:0] p3_wstrb_i,
    input logic p3_wlast_i,
    input logic p3_wvalid_i,
    output logic p3_wready_o,
    output logic p3_bid_o,
    output logic [1:0] p3_bresp_o,
    output logic p3_bvalid_o,
    input logic p3_bready_i,
    input logic p4_arid_i,
    input logic [31:0] p4_araddr_i,
    input logic [3:0] p4_arlen_i,
    input logic p4_arvalid_i,
    output logic p4_arready_o,
    output logic p4_rid_o,
    output logic [255:0] p4_rdata_o,
    output logic [1:0] p4_rresp_o,
    output logic p4_rlast_o,
    output logic p4_rvalid_o,
    input logic p4_rready_i,
    input logic p4_awid_i,
    input logic [31:0] p4_awaddr_i,
    input logic [3:0] p4_awlen_i,
    input logic p4_awvalid_i,
    output logic p4_awready_o,
    input logic [255:0] p4_wdata_i,
    input logic [31:0] p4_wstrb_i,
    input logic p4_wlast_i,
    input logic p4_wvalid_i,
    output logic p4_wready_o,
    output logic p4_bid_o,
    output logic [1:0] p4_bresp_o,
    output logic p4_bvalid_o,
    input logic p4_bready_i,
    input logic p5_arid_i,
    input logic [31:0] p5_araddr_i,
    input logic [3:0] p5_arlen_i,
    input logic p5_arvalid_i,
    output logic p5_arready_o,
    output logic p5_rid_o,
    output logic [255:0] p5_rdata_o,
    output logic [1:0] p5_rresp_o,
    output logic p5_rlast_o,
    output logic p5_rvalid_o,
    input logic p5_rready_i,
    input logic p5_awid_i,
    input logic [31:0] p5_awaddr_i,
    input logic [3:0] p5_awlen_i,
    input logic p5_awvalid_i,
    output logic p5_awready_o,
    input logic [255:0] p5_wdata_i,
    input logic [31:0] p5_wstrb_i,
    input logic p5_wlast_i,
    input logic p5_wvalid_i,
    output logic p5_wready_o,
    output logic p5_bid_o,
    output logic [1:0] p5_bresp_o,
    output logic p5_bvalid_o,
    input logic p5_bready_i,
    input logic p6_arid_i,
    input logic [31:0] p6_araddr_i,
    input logic [3:0] p6_arlen_i,
    input logic p6_arvalid_i,
    output logic p6_arready_o,
    output logic p6_rid_o,
    output logic [255:0] p6_rdata_o,
    output logic [1:0] p6_rresp_o,
    output logic p6_rlast_o,
    output logic p6_rvalid_o,
    input logic p6_rready_i,
    input logic p6_awid_i,
    input logic [31:0] p6_awaddr_i,
    input logic [3:0] p6_awlen_i,
    input logic p6_awvalid_i,
    output logic p6_awready_o,
    input logic [255:0] p6_wdata_i,
    input logic [31:0] p6_wstrb_i,
    input logic p6_wlast_i,
    input logic p6_wvalid_i,
    output logic p6_wready_o,
    output logic p6_bid_o,
    output logic [1:0] p6_bresp_o,
    output logic p6_bvalid_o,
    input logic p6_bready_i,
    input logic clk_i,
    input logic rst_n_i
);
    assign p0_arready_o = '0;
    assign p0_rid_o = '0;
    assign p0_rdata_o = '0;
    assign p0_rresp_o = '0;
    assign p0_rlast_o = '0;
    assign p0_rvalid_o = '0;
    assign p1_awready_o = '0;
    assign p1_wready_o = '0;
    assign p1_bid_o = '0;
    assign p1_bresp_o = '0;
    assign p1_bvalid_o = '0;
    assign p2_arready_o = '0;
    assign p2_rid_o = '0;
    assign p2_rdata_o = '0;
    assign p2_rresp_o = '0;
    assign p2_rlast_o = '0;
    assign p2_rvalid_o = '0;
    assign p2_awready_o = '0;
    assign p2_wready_o = '0;
    assign p2_bid_o = '0;
    assign p2_bresp_o = '0;
    assign p2_bvalid_o = '0;
    assign p3_arready_o = '0;
    assign p3_rid_o = '0;
    assign p3_rdata_o = '0;
    assign p3_rresp_o = '0;
    assign p3_rlast_o = '0;
    assign p3_rvalid_o = '0;
    assign p3_awready_o = '0;
    assign p3_wready_o = '0;
    assign p3_bid_o = '0;
    assign p3_bresp_o = '0;
    assign p3_bvalid_o = '0;
    assign p4_arready_o = '0;
    assign p4_rid_o = '0;
    assign p4_rdata_o = '0;
    assign p4_rresp_o = '0;
    assign p4_rlast_o = '0;
    assign p4_rvalid_o = '0;
    assign p4_awready_o = '0;
    assign p4_wready_o = '0;
    assign p4_bid_o = '0;
    assign p4_bresp_o = '0;
    assign p4_bvalid_o = '0;
    assign p5_arready_o = '0;
    assign p5_rid_o = '0;
    assign p5_rdata_o = '0;
    assign p5_rresp_o = '0;
    assign p5_rlast_o = '0;
    assign p5_rvalid_o = '0;
    assign p5_awready_o = '0;
    assign p5_wready_o = '0;
    assign p5_bid_o = '0;
    assign p5_bresp_o = '0;
    assign p5_bvalid_o = '0;
    assign p6_arready_o = '0;
    assign p6_rid_o = '0;
    assign p6_rdata_o = '0;
    assign p6_rresp_o = '0;
    assign p6_rlast_o = '0;
    assign p6_rvalid_o = '0;
    assign p6_awready_o = '0;
    assign p6_wready_o = '0;
    assign p6_bid_o = '0;
    assign p6_bresp_o = '0;
    assign p6_bvalid_o = '0;
endmodule
