// ============================================================================
// File        : edrv32_shifter32.v
// Description : 32-bit barrel shifter implemented as five 2:1 mux levels.
// Reuse       : Adapted from the pre-rewrite datapath/shifter.v.
// ============================================================================
module edrv32_shifter32 (
    input  wire [31:0] data_i,
    input  wire [4:0]  shamt_i,
    input  wire [1:0]  operation_i,
    output wire [31:0] result_o
);

    localparam [1:0] SHIFT_LEFT_LOGICAL     = 2'b00;
    localparam [1:0] SHIFT_RIGHT_LOGICAL    = 2'b01;
    localparam [1:0] SHIFT_RIGHT_ARITHMETIC = 2'b10;

    wire shift_left_w = (operation_i == SHIFT_LEFT_LOGICAL);
    wire sign_fill_w  = (operation_i == SHIFT_RIGHT_ARITHMETIC) & data_i[31];

    // Each level conditionally shifts by one power of two.  The right tree
    // shares its fill path between logical and arithmetic operations.
    wire [31:0] right_level_1_w = shamt_i[0]
        ? {sign_fill_w, data_i[31:1]} : data_i;
    wire [31:0] right_level_2_w = shamt_i[1]
        ? {{2{sign_fill_w}}, right_level_1_w[31:2]} : right_level_1_w;
    wire [31:0] right_level_4_w = shamt_i[2]
        ? {{4{sign_fill_w}}, right_level_2_w[31:4]} : right_level_2_w;
    wire [31:0] right_level_8_w = shamt_i[3]
        ? {{8{sign_fill_w}}, right_level_4_w[31:8]} : right_level_4_w;
    wire [31:0] right_level_16_w = shamt_i[4]
        ? {{16{sign_fill_w}}, right_level_8_w[31:16]} : right_level_8_w;

    // The left tree uses zero fill and mirrors the five right-tree levels.
    wire [31:0] left_level_1_w = shamt_i[0] ? {data_i[30:0], 1'b0} : data_i;
    wire [31:0] left_level_2_w = shamt_i[1]
        ? {left_level_1_w[29:0], 2'b0} : left_level_1_w;
    wire [31:0] left_level_4_w = shamt_i[2]
        ? {left_level_2_w[27:0], 4'b0} : left_level_2_w;
    wire [31:0] left_level_8_w = shamt_i[3]
        ? {left_level_4_w[23:0], 8'b0} : left_level_4_w;
    wire [31:0] left_level_16_w = shamt_i[4]
        ? {left_level_8_w[15:0], 16'b0} : left_level_8_w;

    assign result_o = shift_left_w ? left_level_16_w : right_level_16_w;

endmodule
