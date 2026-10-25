`timescale 1ns/1ps
module tb;
    reg [31:0] operand_a_i;
    reg [31:0] operand_b_i;
    reg [3:0] operation_i;
    wire [31:0] result_o;
    reg [31:0] expected;
    integer i;
    integer j;

    edrv32_cpu_alu dut (
        .operand_a_i(operand_a_i),
        .operand_b_i(operand_b_i),
        .operation_i(operation_i),
        .result_o(result_o)
    );
    initial begin
        for (i = 0; i < 2000; i = i + 1) begin
            case (i)
                0: begin operand_a_i=0; operand_b_i=0; end
                1: begin operand_a_i=32'hffffffff; operand_b_i=31; end
                2: begin operand_a_i=32'h80000000; operand_b_i=31; end
                3: begin operand_a_i=32'h7fffffff; operand_b_i=0; end
                default: begin operand_a_i=$urandom; operand_b_i=$urandom; end
            endcase
            for (j = 0; j < 16; j = j + 1) begin
                operation_i=4'(j);
                case (j)
                    0: expected=operand_a_i+operand_b_i;
                    8: expected=operand_a_i-operand_b_i;
                    1: expected=operand_a_i<<operand_b_i[4:0];
                    2: expected=32'($signed(operand_a_i)<$signed(operand_b_i));
                    3: expected=32'(operand_a_i<operand_b_i);
                    4: expected=operand_a_i^operand_b_i;
                    5: expected=operand_a_i>>operand_b_i[4:0];
                    13: expected=$signed(operand_a_i)>>>operand_b_i[4:0];
                    6: expected=operand_a_i|operand_b_i;
                    7: expected=operand_a_i&operand_b_i;
                    default: expected=0;
                endcase
                #1;
                if (result_o !== expected)
                    $fatal(1,"FAIL ALU op=%d a=%h b=%h expected=%h actual=%h time=%t",
                        j,operand_a_i,operand_b_i,expected,result_o,$time);
            end
        end
        $display("PASS U-03"); $finish;
    end
endmodule
