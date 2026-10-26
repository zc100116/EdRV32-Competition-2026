// File: edrv32_mem_pmon_stub.sv
// Spec: mem-subsys 2.3; M-V1 coordinator-approved observation points.
// Description: Idle AXI ports for the PERF_MON instance in the compilation stub.
// Clock domain: clk_mem.
`timescale 1ns/1ps
module edrv32_mem_pmon_stub (
    output logic axi_arvalid_o,
    input logic axi_arready_i,
    output logic [31:0] axi_araddr_o,
    output logic [3:0] axi_arlen_o,
    output logic axi_arid_o,
    input logic axi_rvalid_i,
    output logic axi_rready_o,
    input logic axi_rlast_i,
    input logic [255:0] axi_rdata_i,
    input logic [1:0] axi_rresp_i,
    input logic axi_rid_i,
    output logic axi_awvalid_o,
    input logic axi_awready_i,
    output logic [31:0] axi_awaddr_o,
    output logic [3:0] axi_awlen_o,
    output logic axi_awid_o,
    output logic axi_wvalid_o,
    input logic axi_wready_i,
    output logic axi_wlast_o,
    output logic [255:0] axi_wdata_o,
    output logic [31:0] axi_wstrb_o,
    input logic axi_bvalid_i,
    output logic axi_bready_o,
    input logic axi_bid_i,
    input logic [1:0] axi_bresp_i
);
    assign axi_arvalid_o = 0;
    assign axi_araddr_o = 0;
    assign axi_arlen_o = 0;
    assign axi_arid_o = 0;
    assign axi_rready_o = 1;
    assign axi_awvalid_o = 0;
    assign axi_awaddr_o = 0;
    assign axi_awlen_o = 0;
    assign axi_awid_o = 0;
    assign axi_wvalid_o = 0;
    assign axi_wlast_o = 0;
    assign axi_wdata_o = 0;
    assign axi_wstrb_o = 0;
    assign axi_bready_o = 1;
endmodule
