// File: ip_pll_video.sv
// Spec: fpga/ip/ip_pll_video.md; edrv32-soc-spec 5.2 X5/X6.
// Description: Related 74.25/371.25 MHz clocks, with lock after eight reference edges.
// Clock domain: clkin1, clkout0 (pixel), clkout1 (5x serial).
module ip_pll_video (
    input wire clkin1,
    output wire clkout0,
    output reg clkout1 = 0,
    output reg lock = 0
);
    timeunit 1ns;
    timeprecision 1ps;
    reg [3:0] phase = 0;
    // One time base preserves the exact 5:1 ratio at simulation precision.
    always #1.3468 begin
        clkout1 <= ~clkout1;
        phase <= phase == 9 ? 0 : phase + 1'b1;
    end
    assign clkout0 = phase < 5;
    initial begin
        repeat (8) @(posedge clkin1);
        lock = 1;
    end
endmodule
