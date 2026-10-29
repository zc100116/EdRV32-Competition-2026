// File: edrv32_rnd.sv
// Spec: rnd 3; Task R-T1 compile acceptance.
// Description: Public-port declaration stub for independent harness elaboration only.
//              No rendering behavior; excluded from the real DUT file list.
// Clock domain: clk_mem.
`timescale 1ns/1ps
module edrv32_rnd (
    input logic clk_mem_i,
    input logic rst_mem_n_i,
    input logic [11:0] apb_paddr_i,
    input logic apb_psel_i,
    input logic apb_penable_i,
    input logic apb_pwrite_i,
    input logic [31:0] apb_pwdata_i,
    input logic [3:0] apb_pstrb_i,
    output logic apb_pready_o,
    output logic [31:0] apb_prdata_o,
    output logic apb_pslverr_o,
    output logic p4_awid_o,
    output logic [31:0] p4_awaddr_o,
    output logic [3:0] p4_awlen_o,
    output logic p4_awvalid_o,
    input logic p4_awready_i,
    output logic [255:0] p4_wdata_o,
    output logic [31:0] p4_wstrb_o,
    output logic p4_wlast_o,
    output logic p4_wvalid_o,
    input logic p4_wready_i,
    input logic p4_bid_i,
    input logic [1:0] p4_bresp_i,
    input logic p4_bvalid_i,
    output logic p4_bready_o,
    output logic p4_arid_o,
    output logic [31:0] p4_araddr_o,
    output logic [3:0] p4_arlen_o,
    output logic p4_arvalid_o,
    input logic p4_arready_i,
    input logic p4_rid_i,
    input logic [255:0] p4_rdata_i,
    input logic [1:0] p4_rresp_i,
    input logic p4_rlast_i,
    input logic p4_rvalid_i,
    output logic p4_rready_o,
    output logic irq_o
);
    assign apb_pready_o = 1;
    assign apb_prdata_o = '0;
    assign apb_pslverr_o = '0;
    assign p4_awid_o = '0;
    assign p4_awaddr_o = '0;
    assign p4_awlen_o = '0;
    assign p4_awvalid_o = '0;
    assign p4_wdata_o = '0;
    assign p4_wstrb_o = '0;
    assign p4_wlast_o = '0;
    assign p4_wvalid_o = '0;
    assign p4_bready_o = '0;
    assign p4_arid_o = '0;
    assign p4_araddr_o = '0;
    assign p4_arlen_o = '0;
    assign p4_arvalid_o = '0;
    assign p4_rready_o = '0;
    assign irq_o = '0;
endmodule
