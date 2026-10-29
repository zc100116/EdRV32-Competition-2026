// File: ip_pll_eth.sv
// Spec: fpga/rtl/edrv32_fpga_rgmii.v; Task B3-7.
// Description: Model the fixed 30 degree RX PLL phase shift.
// Clock domain: 125 MHz Ethernet.
module ip_pll_eth (
    input wire clkin1,
    output reg clkout0 = 0,
    output reg lock = 0
);
    timeunit 1ns;
    timeprecision 1ps;
    // Explicit input event avoids Verilator 5.020 continuous-delay rescheduling.
    always @(clkin1) clkout0 <= #0.666667 clkin1;
    initial begin
        repeat (8) @(posedge clkin1);
        lock = 1;
    end
endmodule
