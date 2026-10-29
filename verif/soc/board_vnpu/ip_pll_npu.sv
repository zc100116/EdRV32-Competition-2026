// File: ip_pll_npu.sv
// Spec: Task B3-10; fpga/ip/ip_pll_npu.md.
// Description: Fixed 150 MHz behavioral PLL; lock asserts after eight reference edges.
// Clock domain: clkin1 (27 MHz) and clkout0 (150 MHz).
module ip_pll_npu (
    input wire clkin1,
    output reg clkout0 = 0,
    output reg lock = 0
);
    timeunit 1ns;
    timeprecision 1ps;
    always #3.333333 clkout0 <= ~clkout0;
    initial begin
        repeat (8) @(posedge clkin1);
        lock = 1;
    end
endmodule
