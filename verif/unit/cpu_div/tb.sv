`timescale 1ns/1ps
module tb;
    reg clk_i=0;
    always #5 clk_i=~clk_i;
    reg rst_n_i=0;
    reg [31:0] operand_a_i;
    reg [31:0] operand_b_i;
    reg start_i=0;
    reg [1:0] operation_i;
    wire busy_o;
    wire valid_o;
    wire [31:0] result_o;
    reg [31:0] expected;
    integer i;
    integer cycles;
    integer limit;

    edrv32_cpu_div dut (
        .clk_i(clk_i),
        .rst_n_i(rst_n_i),
        .start_i(start_i),
        .operand_a_i(operand_a_i),
        .operand_b_i(operand_b_i),
        .operation_i(operation_i),
        .busy_o(busy_o),
        .valid_o(valid_o),
        .result_o(result_o)
    );
    initial begin
        repeat(2) @(negedge clk_i);
        rst_n_i=1;
        for(i=0;i<1200;i=i+1) begin
            operation_i=2'(i);
            operand_a_i=$urandom; operand_b_i=$urandom;
            case(i/4)
                0: begin operand_a_i=0;operand_b_i=0;end
                1: begin operand_a_i=32'h80000000;operand_b_i=32'hffffffff;end
                2: begin operand_a_i=32'hffffffff;operand_b_i=0;end
                3: begin operand_a_i=32'h7fffffff;operand_b_i=1;end
                4: begin operand_a_i=32'h80000000;operand_b_i=1;end
                5: begin operand_a_i=32'hffffffff;operand_b_i=32'h80000000;end
                default: begin end
            endcase
            if(operand_b_i==0) expected=operation_i[1]?operand_a_i:32'hffffffff;
            else if(!operation_i[0] && operand_a_i==32'h80000000 &&
                operand_b_i==32'hffffffff) expected=operation_i[1]?0:32'h80000000;
            else case(operation_i)
                0: expected=$signed(operand_a_i)/$signed(operand_b_i);
                1: expected=operand_a_i/operand_b_i;
                2: expected=$signed(operand_a_i)%$signed(operand_b_i);
                3: expected=operand_a_i%operand_b_i;
                default: expected=0;
            endcase
            limit=(operand_b_i==0 || (!operation_i[0] &&
                operand_a_i==32'h80000000 && operand_b_i==32'hffffffff))?1:33;
            start_i=1;
            for(cycles=1;cycles<=limit;cycles=cycles+1) begin
                @(posedge clk_i);#1;
                if(valid_o !== (cycles==limit) || busy_o !== (cycles!=limit))
                    $fatal(1,"FAIL DIV timing cycle=%d limit=%d time=%t",cycles,limit,$time);
                if(cycles==limit && result_o!==expected)
                    $fatal(1,"FAIL DIV op=%d a=%h b=%h exp=%h actual=%h time=%t",
                        operation_i,operand_a_i,operand_b_i,expected,result_o,$time);
                @(negedge clk_i); start_i=0;
            end
        end
        $display("PASS U-06");$finish;
    end
endmodule
