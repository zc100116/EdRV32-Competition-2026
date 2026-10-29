// File: GTP_IODELAY_E2.sv
// Spec: fpga/rtl/edrv32_fpga_rgmii.v; Task B3-7.
// Description: RGMII connectivity model; physical pin delays are outside this test.
// Clock domain: 125 MHz Ethernet.
module GTP_IODELAY_E2 #(
    parameter DELAY_STEP_SEL = "PORT",
    parameter DELAY_STEP_VALUE = 8'd0,
    parameter TDELAY_EN = "FALSE"
) (
    input wire DI,
    input wire DELAY_SEL,
    input wire [7:0] DELAY_STEP,
    input wire EN_N,
    output wire DO
);
    assign DO = DI;
    wire unused_configuration = &{1'b0, DELAY_STEP_SEL, DELAY_STEP_VALUE, TDELAY_EN,
        DELAY_SEL, DELAY_STEP, EN_N};
endmodule
