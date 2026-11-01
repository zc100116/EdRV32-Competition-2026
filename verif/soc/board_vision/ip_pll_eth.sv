// File: ip_pll_eth.sv
// Spec: fpga/rtl/edrv32_fpga_rgmii.v; Task B3-7.
// Description: Model the external-feedback RX PLL: CLKOUT0 aligned to clkin1 (0 degrees).
// Clock domain: 125 MHz Ethernet.
module ip_pll_eth (
    input wire clkin1,
    input wire clkfb,
    output reg clkout0 = 0,
    output reg lock = 0
);
    timeunit 1ns;
    timeprecision 1ps;
    always @(clkin1) clkout0 <= clkin1;
    wire unused_feedback = clkfb;
    initial begin
        repeat (8) @(posedge clkin1);
        lock = 1;
    end
endmodule
