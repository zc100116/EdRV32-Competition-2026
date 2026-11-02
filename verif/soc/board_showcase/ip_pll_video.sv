// File: ip_pll_video.sv
// Design: showcase test; coordinator-approved pixel-only video PLL abstraction.
// Description: Keep the real 74.25 MHz pixel clock; TMDS serial is covered by
// board_render and is not observed in this application/frame ownership test.
// Clock domain: clkin1 and clkout0; serial output intentionally inactive.
module ip_pll_video (
    input wire clkin1,
    output reg clkout0 = 0,
    output wire clkout1,
    output reg lock = 0
);
    timeunit 1ns;
    timeprecision 1ps;
    always #6.734 clkout0 <= ~clkout0;
    assign clkout1 = 1'b0;
    initial begin
        repeat (8) @(posedge clkin1);
        lock = 1;
    end
endmodule
