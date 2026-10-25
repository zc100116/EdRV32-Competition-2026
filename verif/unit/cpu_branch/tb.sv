`timescale 1ns/1ps
module tb;
    reg [31:0] operand_a_i;
    reg [31:0] operand_b_i;
    reg [2:0] condition_i;
    wire taken_o;
    reg expected;
    integer i;
    integer j;

    edrv32_cpu_branch dut (
        .operand_a_i(operand_a_i),
        .operand_b_i(operand_b_i),
        .condition_i(condition_i),
        .taken_o(taken_o)
    );
    initial begin
        for (i=0;i<2000;i=i+1) begin
            operand_a_i=$urandom; operand_b_i=$urandom;
            case (i)
                0: begin operand_a_i=0; operand_b_i=0; end
                1: begin operand_a_i=32'hffffffff; operand_b_i=0; end
                2: begin operand_a_i=32'h80000000; operand_b_i=32'h7fffffff; end
                3: begin operand_a_i=32'h7fffffff; operand_b_i=32'h80000000; end
                default: begin end
            endcase
            for (j=0;j<8;j=j+1) begin
                condition_i=3'(j);
                case(j)
                    0: expected=operand_a_i==operand_b_i;
                    1: expected=operand_a_i!=operand_b_i;
                    4: expected=$signed(operand_a_i)<$signed(operand_b_i);
                    5: expected=$signed(operand_a_i)>=$signed(operand_b_i);
                    6: expected=operand_a_i<operand_b_i;
                    7: expected=operand_a_i>=operand_b_i;
                    default: expected=0;
                endcase
                #1;
                if(taken_o!==expected)
                    $fatal(1,"FAIL branch condition=%d a=%h b=%h exp=%b actual=%b time=%t",
                        j,operand_a_i,operand_b_i,expected,taken_o,$time);
            end
        end
        $display("PASS U-04"); $finish;
    end
endmodule
