// File: tb.sv
// Spec: geo-spec 2, 4, 5.
// Description: Independent formula-based unit checks.
// Clock domain: clk_mem.
module tb;
    reg clk = 0;
    always #4 clk = !clk;
    reg a_clk_i;
    reg a_rst_n_i;
    reg a_start_i;
    reg a_clear_i;
    reg [31:0] a_base_i;
    reg [31:0] a_stride_i;
    reg [12:0] a_row_i;
    reg [12:0] a_column_i;
    wire a_done_o;
    wire [31:0] a_addr_o;
    edrv32_geo_address u_a_ (
        .clk_i(a_clk_i),
        .rst_n_i(a_rst_n_i),
        .start_i(a_start_i),
        .clear_i(a_clear_i),
        .base_i(a_base_i),
        .stride_i(a_stride_i),
        .row_i(a_row_i),
        .column_i(a_column_i),
        .done_o(a_done_o),
        .addr_o(a_addr_o)
    );
    integer trial;
    integer cycles;
    reg [31:0] expected;
    initial begin

        a_rst_n_i = 0;
        a_start_i = 0;
        a_clear_i = 0;
        a_base_i = 0;
        a_stride_i = 0;
        a_row_i = 0;
        a_column_i = 0;
        repeat(2) @(negedge clk);a_rst_n_i=1;
        for(trial=0;trial<200;trial++) begin
            a_base_i=$urandom;a_stride_i=$urandom;
            a_row_i=13'($urandom);a_column_i=13'($urandom);
            expected=a_base_i+a_stride_i*32'(a_row_i)+2*32'(a_column_i);
            a_start_i=1;
            @(negedge clk);a_start_i=0;cycles=0;
            while(!a_done_o) begin
                cycles++;
                if(cycles>14) $fatal(1,"FAIL address timeout");
                @(negedge clk);
            end
            @(negedge clk);
            if(a_addr_o!==expected)
                $fatal(1,"FAIL surface address expected=%h got=%h",expected,a_addr_o);
        end
        a_start_i=1;
        @(negedge clk);a_start_i=0;a_clear_i=1;
        @(negedge clk);a_clear_i=0;
        repeat(15) begin
            @(negedge clk);
            if(a_done_o) $fatal(1,"FAIL cancelled address completed");
        end
        $display("PASS geo_address independent surface formula and cancellation");
        $finish;
    end
    always @(*) a_clk_i=clk;
endmodule
