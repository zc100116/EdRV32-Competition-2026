// File: edrv32_periph_uart.sv
// Spec: sys-subsys 3.1/3.2; sys-subsys-testplan 2.1.
// Description: Port-only fixture for compiling passive binds without reading DUT RTL.
// Clock domain: the observed interface clock.
module edrv32_periph_uart (
    input logic clk_i,
    input logic rst_n_i,
    input logic [11:0] apb_paddr_i,
    input logic apb_psel_i,
    input logic apb_penable_i,
    input logic apb_pwrite_i,
    input logic [31:0] apb_pwdata_i,
    input logic [3:0] apb_pstrb_i,
    output logic [31:0] apb_prdata_o,
    output logic apb_pready_o,
    output logic apb_pslverr_o
);
    assign apb_prdata_o = 0;
    assign apb_pready_o = 0;
    assign apb_pslverr_o = 0;
    wire unused_inputs = &{
        clk_i,
        rst_n_i,
        apb_paddr_i,
        apb_psel_i,
        apb_penable_i,
        apb_pwrite_i,
        apb_pwdata_i,
        apb_pstrb_i
    };
endmodule
