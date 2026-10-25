`timescale 1ns/1ps

module edrv32_clock_reset_driver;
    reg clk;
    reg rst_n;

    always #5 clk = ~clk;

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        repeat (6) @(posedge clk);
        rst_n = 1'b1;
    end

    `EDRV32_TB u_tb (
        .clk   (clk),
        .rst_n (rst_n)
    );
endmodule
