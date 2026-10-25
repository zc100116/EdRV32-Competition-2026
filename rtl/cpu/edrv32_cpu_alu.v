// File: edrv32_cpu_alu.v
// Spec: cpu-spec 2.1, 4.1
// Description: Execute RV32I arithmetic, logical, comparison and shift operations.
// The operation selects the combinational result for either pipeline.
// Clock domain: 组合逻辑.
module edrv32_cpu_alu (
    // Execute operands and operation (funct3; bit 3 selects SUB/SRA).
    input wire [31:0] operand_a_i,
    input wire [31:0] operand_b_i,
    input wire [3:0] operation_i,
    // Execute result.
    output reg [31:0] result_o
);
    always @(*) begin
        result_o = 32'b0;
        case (operation_i)
            4'b0000: result_o = operand_a_i + operand_b_i;
            4'b1000: result_o = operand_a_i - operand_b_i;
            4'b0001: result_o = operand_a_i << operand_b_i[4:0];
            4'b0010: result_o = {31'b0, $signed(operand_a_i) < $signed(operand_b_i)};
            4'b0011: result_o = {31'b0, operand_a_i < operand_b_i};
            4'b0100: result_o = operand_a_i ^ operand_b_i;
            4'b0101: result_o = operand_a_i >> operand_b_i[4:0];
            4'b1101: result_o = $signed(operand_a_i) >>> operand_b_i[4:0];
            4'b0110: result_o = operand_a_i | operand_b_i;
            4'b0111: result_o = operand_a_i & operand_b_i;
            default: result_o = 32'b0;
        endcase
    end
endmodule
