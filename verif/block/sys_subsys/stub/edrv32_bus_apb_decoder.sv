// File: edrv32_bus_apb_decoder.sv
// Spec: sys-subsys 3.1/3.2; sys-subsys-testplan 2.1.
// Description: Port-only fixture for compiling passive binds without reading DUT RTL.
// Clock domain: the observed interface clock.
module edrv32_bus_apb_decoder (
    input logic clk_i,
    input logic rst_n_i,
    output logic [11:0] slot_paddr_o,
    output logic [15:0] slot_psel_o,
    output logic slot_penable_o,
    output logic slot_pwrite_o,
    output logic [31:0] slot_pwdata_o,
    output logic [3:0] slot_pstrb_o,
    input logic [511:0] slot_prdata_i,
    input logic [15:0] slot_pready_i,
    input logic [15:0] slot_pslverr_i
);
    assign slot_paddr_o = 0;
    assign slot_psel_o = 0;
    assign slot_penable_o = 0;
    assign slot_pwrite_o = 0;
    assign slot_pwdata_o = 0;
    assign slot_pstrb_o = 0;
    wire unused_inputs = &{
        clk_i,
        rst_n_i,
        slot_prdata_i,
        slot_pready_i,
        slot_pslverr_i
    };
endmodule
