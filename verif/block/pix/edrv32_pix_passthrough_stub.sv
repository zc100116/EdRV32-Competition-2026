// File: edrv32_pix_passthrough_stub.sv
// Spec: V-T3 environment validation; PIX testplan PX-01.
// Description: Explicit combinational stream loopback with an always-ready APB sink.
//              This has no PIX processing/register implementation and is never formal DUT.
// Clock domain: clk_mem.
`timescale 1ns/1ps
module edrv32_pix_passthrough_stub (
    // Clock and reset.
    input wire clk_mem_i,
    input wire rst_mem_n_i,

    // Upstream pixel stream.
    input wire pix_in_valid_i,
    output wire pix_in_ready_o,
    input wire [31:0] pix_in_data_i,
    input wire pix_in_sof_i,
    input wire pix_in_eol_i,
    input wire pix_in_eof_i,

    // Downstream pixel stream.
    output wire pix_out_valid_o,
    input wire pix_out_ready_i,
    output wire [31:0] pix_out_data_o,
    output wire pix_out_sof_o,
    output wire pix_out_eol_o,
    output wire pix_out_eof_o,

    // APB sink.
    input wire [11:0] apb_paddr_i,
    input wire apb_psel_i,
    input wire apb_penable_i,
    input wire apb_pwrite_i,
    input wire [31:0] apb_pwdata_i,
    input wire [3:0] apb_pstrb_i,
    output wire [31:0] apb_prdata_o,
    output wire apb_pready_o,
    output wire apb_pslverr_o,

    // Interrupt.
    output wire irq_o
);
    assign pix_in_ready_o = pix_out_ready_i && rst_mem_n_i;
    assign pix_out_valid_o = pix_in_valid_i && rst_mem_n_i;
    assign pix_out_data_o = pix_in_data_i;
    assign pix_out_sof_o = pix_in_sof_i;
    assign pix_out_eol_o = pix_in_eol_i;
    assign pix_out_eof_o = pix_in_eof_i;
    assign apb_prdata_o = 0;
    assign apb_pready_o = 1;
    assign apb_pslverr_o = 0;
    assign irq_o = 0;
endmodule
