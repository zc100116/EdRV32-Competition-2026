// File: ip_pll_sys.sv
// Spec: board-plan B1-2/B1-4; fpga/ip/ip_pll_sys.md.
// Description: Fixed 100/150 MHz behavioral PLL; lock asserts after eight reference edges.
// Clock domain: clkin1 (27 MHz), clkout0 (100 MHz) and clkout1 (150 MHz).
module ip_pll_sys (
    input wire clkin1,
    output reg clkout0 = 0,
    output reg clkout1 = 0,
    output reg lock = 0
);
    timeunit 1ns;
    timeprecision 1ps;
    always #5 clkout0 <= ~clkout0;
    always #3.333 clkout1 <= ~clkout1;
    initial begin
        repeat (8) @(posedge clkin1);
        lock = 1;
    end
endmodule
