// File: edrv32_vin.sv
// Spec: vin 3; V-T1 compile-only harness stub.
// Description: Interface-only substitute; implements no VIN behavior and cannot pass VIN tests.
// Clock domain: clk_mem, cam0_pclk, cam1_pclk.
`timescale 1ns/1ps
module edrv32_vin (
    input wire clk_mem_i,
    input wire rst_mem_n_i,
    input wire cam0_pclk_i,
    input wire cam1_pclk_i,
    input wire rst_cam0_n_i,
    input wire rst_cam1_n_i,
    input wire cam0_vsync_i,
    input wire cam0_href_i,
    input wire [7:0] cam0_data_i,
    input wire cam1_vsync_i,
    input wire cam1_href_i,
    input wire [7:0] cam1_data_i,
    input wire [11:0] apb_paddr_i,
    input wire apb_psel_i,
    input wire apb_penable_i,
    input wire apb_pwrite_i,
    input wire [31:0] apb_pwdata_i,
    input wire [3:0] apb_pstrb_i,
    output wire apb_pready_o,
    output wire [31:0] apb_prdata_o,
    output wire apb_pslverr_o,
    output wire p1_awid_o,
    output wire [31:0] p1_awaddr_o,
    output wire [3:0] p1_awlen_o,
    output wire p1_awvalid_o,
    input wire p1_awready_i,
    output wire [255:0] p1_wdata_o,
    output wire [31:0] p1_wstrb_o,
    output wire p1_wlast_o,
    output wire p1_wvalid_o,
    input wire p1_wready_i,
    input wire p1_bid_i,
    input wire [1:0] p1_bresp_i,
    input wire p1_bvalid_i,
    output wire p1_bready_o,
    output wire p1_arid_o,
    output wire [31:0] p1_araddr_o,
    output wire [3:0] p1_arlen_o,
    output wire p1_arvalid_o,
    input wire p1_arready_i,
    input wire p1_rid_i,
    input wire [255:0] p1_rdata_i,
    input wire [1:0] p1_rresp_i,
    input wire p1_rlast_i,
    input wire p1_rvalid_i,
    output wire p1_rready_o,
    output wire p1_urgent_o,
    output wire pix_in_valid_o,
    input wire pix_in_ready_i,
    output wire [31:0] pix_in_data_o,
    output wire pix_in_sof_o,
    output wire pix_in_eol_o,
    output wire pix_in_eof_o,
    input wire pix_out_valid_i,
    output wire pix_out_ready_o,
    input wire [31:0] pix_out_data_i,
    input wire pix_out_sof_i,
    input wire pix_out_eol_i,
    input wire pix_out_eof_i,
    output wire irq_o
);
    assign apb_pready_o = '0;
    assign apb_prdata_o = '0;
    assign apb_pslverr_o = '0;
    assign p1_awid_o = '0;
    assign p1_awaddr_o = '0;
    assign p1_awlen_o = '0;
    assign p1_awvalid_o = '0;
    assign p1_wdata_o = '0;
    assign p1_wstrb_o = '0;
    assign p1_wlast_o = '0;
    assign p1_wvalid_o = '0;
    assign p1_bready_o = '0;
    assign p1_arid_o = '0;
    assign p1_araddr_o = '0;
    assign p1_arlen_o = '0;
    assign p1_arvalid_o = '0;
    assign p1_rready_o = '0;
    assign p1_urgent_o = '0;
    assign pix_in_valid_o = '0;
    assign pix_in_data_o = '0;
    assign pix_in_sof_o = '0;
    assign pix_in_eol_o = '0;
    assign pix_in_eof_o = '0;
    assign pix_out_ready_o = '0;
    assign irq_o = '0;
endmodule
