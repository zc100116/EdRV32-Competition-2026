// edrv32_cpu_branch.v
// cpu-spec 2, 4: branch datapath.
// Clock domain: clk_sys (combinational where no clock port).
module edrv32_cpu_branch (
    // Branch operands and instruction funct3.
    input wire [31:0] operand_a_i,
    input wire [31:0] operand_b_i,
    input wire [2:0] condition_i,
    // Branch direction.
    output reg taken_o
);
    always @(*) begin
        taken_o = 1'b0;
        case (condition_i)
            3'b000: taken_o = operand_a_i == operand_b_i;
            3'b001: taken_o = operand_a_i != operand_b_i;
            3'b100: taken_o = $signed(operand_a_i) < $signed(operand_b_i);
            3'b101: taken_o = $signed(operand_a_i) >= $signed(operand_b_i);
            3'b110: taken_o = operand_a_i < operand_b_i;
            3'b111: taken_o = operand_a_i >= operand_b_i;
            default: taken_o = 1'b0;
        endcase
    end
endmodule
