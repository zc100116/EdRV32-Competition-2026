// cpu_mul/tb.sv
// cpu-testplan U-05; cpu-spec 2, 4, 5.
// Check four multiply forms, streaming latency and pipeline enable behavior.
// Stop with a diagnostic on the first mismatch; print PASS on completion.
// Clock domain: clk_sys.
`timescale 1ns/1ps
module tb;
    reg clk_i=0;
    always #5 clk_i=~clk_i;
    reg rst_n_i=0;
    reg [31:0] operand_a_i;
    reg [31:0] operand_b_i;
    reg enable_i=1;
    reg valid_i=0;
    reg [1:0] operation_i;
    wire valid_o;
    wire [31:0] result_o;
    reg [31:0] expected[0:2];
    reg [2:0] expected_valid=0;
    reg signed [32:0] a;
    reg signed [32:0] b;
    reg signed [65:0] product;
    integer i;

    edrv32_cpu_mul dut (
        .clk_i(clk_i),
        .rst_n_i(rst_n_i),
        .enable_i(enable_i),
        .valid_i(valid_i),
        .operand_a_i(operand_a_i),
        .operand_b_i(operand_b_i),
        .operation_i(operation_i),
        .valid_o(valid_o),
        .result_o(result_o)
    );
    initial begin
        repeat(2) @(negedge clk_i);
        rst_n_i=1;
        for(i=0;i<2004;i=i+1) begin
            enable_i=(i%13!=0);
            valid_i=(i<2000 && i%7!=0);
            operation_i=2'(i);
            operand_a_i=$urandom; operand_b_i=$urandom;
            if(i<16) begin
                operand_a_i=(i/4==0)?0:(i/4==1)?32'hffffffff:
                    (i/4==2)?32'h80000000:32'h7fffffff;
                operand_b_i=32'hffffffff;
            end
            a={operand_a_i[31] && operation_i!=3,operand_a_i};
            b={operand_b_i[31] && operation_i==1,operand_b_i};
            product=a*b;
            if(enable_i) begin
                expected[2]=expected[1];
                expected[1]=expected[0];
                expected[0]=operation_i==0?product[31:0]:product[63:32];
                expected_valid={expected_valid[1:0],valid_i};
            end
            @(posedge clk_i); #1;
            if(valid_o!==expected_valid[2] ||
                (valid_o && result_o!==expected[2]))
                $fatal(1,"FAIL MUL i=%d exp=%h actual=%h valid=%b time=%t",
                    i,expected[2],result_o,valid_o,$time);
            @(negedge clk_i);
        end
        $display("PASS U-05"); $finish;
    end
endmodule
