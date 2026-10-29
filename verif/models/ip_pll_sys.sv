// File: ip_pll_sys.sv
// Spec: board-plan B1-2/B1-4; fpga/ip/ip_pll_sys.md.
// Description: Fixed 100 MHz behavioral PLL; lock asserts after eight reference edges.
// Clock domain: clkin1 (27 MHz) and clkout0 (100 MHz).
module ip_pll_sys (
    input wire clkin1,
    output reg clkout0 = 0,
    output reg lock = 0
);
    timeunit 1ns;
    timeprecision 1ps;
    always #5 clkout0 <= ~clkout0;
    initial begin
        repeat (8) @(posedge clkin1);
        lock = 1;
    end
endmodule
