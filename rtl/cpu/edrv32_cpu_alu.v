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
    // Equivalent registered amount, isolated from arithmetic operand loads.
    input wire [119:0] shift_amount_i,
    // Execute result.
    output reg [31:0] result_o
);
    // Each 4-bit slice has independent amount FFs for all three shift kinds.
    // The first mux group shifts 0..3, the second shifts multiples of four.
    function [3:0] shift_part;
        input [31:0] value_i;
        input [4:0] amount_i;
        input [1:0] kind_i;
        input [2:0] slice_i;
        reg [31:0] shifted_v;
        begin
            case (kind_i)
                0: shifted_v = value_i << amount_i;
                1: shifted_v = value_i >> amount_i;
                default: shifted_v = $signed(value_i) >>> amount_i;
            endcase
            shift_part = shifted_v[slice_i*4 +: 4];
        end
    endfunction
    wire [31:0] left_low_w;
    wire [31:0] right_low_w;
    wire [31:0] signed_low_w;
    wire [31:0] left_w;
    wire [31:0] right_w;
    wire [31:0] signed_w;
    genvar shift_slice;
    generate
        for (shift_slice = 0; shift_slice < 8;
            shift_slice = shift_slice + 1) begin : g_shift
            localparam SLICE = shift_slice;
            assign left_low_w[shift_slice*4 +: 4] = shift_part(operand_a_i,
                {3'b0, shift_amount_i[shift_slice*15 +: 2]}, 2'd0, SLICE[2:0]);
            assign right_low_w[shift_slice*4 +: 4] = shift_part(operand_a_i,
                {3'b0, shift_amount_i[shift_slice*15+5 +: 2]}, 2'd1, SLICE[2:0]);
            assign signed_low_w[shift_slice*4 +: 4] = shift_part(operand_a_i,
                {3'b0, shift_amount_i[shift_slice*15+10 +: 2]}, 2'd2, SLICE[2:0]);
            assign left_w[shift_slice*4 +: 4] = shift_part(left_low_w,
                {shift_amount_i[shift_slice*15+2 +: 3], 2'b0}, 2'd0, SLICE[2:0]);
            assign right_w[shift_slice*4 +: 4] = shift_part(right_low_w,
                {shift_amount_i[shift_slice*15+7 +: 3], 2'b0}, 2'd1, SLICE[2:0]);
            assign signed_w[shift_slice*4 +: 4] = shift_part(signed_low_w,
                {shift_amount_i[shift_slice*15+12 +: 3], 2'b0}, 2'd2, SLICE[2:0]);
        end
    endgenerate
    always @(*) begin
        result_o = 32'b0;
        case (operation_i)
            4'b0000: result_o = operand_a_i + operand_b_i;
            4'b1000: result_o = operand_a_i - operand_b_i;
            4'b0001: result_o = left_w;
            4'b0010: result_o = {31'b0, $signed(operand_a_i) < $signed(operand_b_i)};
            4'b0011: result_o = {31'b0, operand_a_i < operand_b_i};
            4'b0100: result_o = operand_a_i ^ operand_b_i;
            4'b0101: result_o = right_w;
            4'b1101: result_o = signed_w;
            4'b0110: result_o = operand_a_i | operand_b_i;
            4'b0111: result_o = operand_a_i & operand_b_i;
            default: result_o = 32'b0;
        endcase
    end
endmodule
