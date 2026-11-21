// File: edrv32_cpu_branch.v
// Spec: cpu-spec 2.1, 4.4
// Description: Compare operands for the six RV32I conditional branch forms.
// Signed and unsigned conditions use the instruction funct3 encoding.
// Clock domain: 组合逻辑.
module edrv32_cpu_branch (
    // Branch operands and instruction funct3.
    input wire [31:0] operand_a_i,
    input wire [31:0] operand_b_i,
    input wire [2:0] condition_i,
    // Branch direction.
    output reg taken_o
);
    wire equal_w;
    wire less_unsigned_w;
    wire less_signed_w;
    assign equal_w = operand_a_i == operand_b_i;
    assign less_unsigned_w = operand_a_i < operand_b_i;
    // Signed/unsigned forms share one magnitude comparison; funct3[0] inverts it.
    assign less_signed_w = operand_a_i[31] == operand_b_i[31] ?
        less_unsigned_w : operand_a_i[31];
    always @(*) begin
        taken_o = 1'b0;
        case (condition_i[2:1])
            2'b00: taken_o = equal_w ^ condition_i[0];
            2'b10: taken_o = less_signed_w ^ condition_i[0];
            2'b11: taken_o = less_unsigned_w ^ condition_i[0];
            default: taken_o = 1'b0;
        endcase
    end
endmodule
