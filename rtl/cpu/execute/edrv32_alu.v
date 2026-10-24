// ============================================================================
// File        : edrv32_alu.v
// Description : Production RV32 integer ALU. Wide arithmetic, comparison and
//               variable shifts are delegated to structural/dataflow units.
// Reuse       : Datapath units are adapted from the pre-rewrite CPU.
// ============================================================================
`include "edrv32_isa.vh"
`include "edrv32_uop.vh"

module edrv32_alu (
    input  wire [`EDRV32_ALU_OP_W-1:0] op_i,
    input  wire [`EDRV32_XLEN-1:0]     lhs_i,
    input  wire [`EDRV32_XLEN-1:0]     rhs_i,
    output wire [`EDRV32_XLEN-1:0]     result_o
);

    wire subtract_w = (op_i == `EDRV32_ALU_SUB);
    wire [31:0] adder_rhs_w = rhs_i ^ {32{subtract_w}};
    wire [31:0] adder_result_w;
    wire unused_adder_carry_w;

    edrv32_adder32 u_add_sub (
        .lhs_i   (lhs_i),
        .rhs_i   (adder_rhs_w),
        .carry_i (subtract_w),
        .sum_o   (adder_result_w),
        .carry_o (unused_adder_carry_w)
    );

    localparam [1:0] SHIFT_LEFT_LOGICAL     = 2'b00;
    localparam [1:0] SHIFT_RIGHT_LOGICAL    = 2'b01;
    localparam [1:0] SHIFT_RIGHT_ARITHMETIC = 2'b10;

    reg [1:0] shift_operation_r;
    always @* begin
        case (op_i)
            `EDRV32_ALU_SLL: shift_operation_r = SHIFT_LEFT_LOGICAL;
            `EDRV32_ALU_SRA: shift_operation_r = SHIFT_RIGHT_ARITHMETIC;
            default:         shift_operation_r = SHIFT_RIGHT_LOGICAL;
        endcase
    end

    wire [31:0] shift_result_w;
    edrv32_shifter32 u_shift (
        .data_i      (lhs_i),
        .shamt_i     (rhs_i[4:0]),
        .operation_i (shift_operation_r),
        .result_o    (shift_result_w)
    );

    wire equal_w;
    wire signed_less_w;
    wire unsigned_less_w;
    edrv32_compare32 u_compare (
        .lhs_i          (lhs_i),
        .rhs_i          (rhs_i),
        .equal_o        (equal_w),
        .signed_less_o  (signed_less_w),
        .unsigned_less_o(unsigned_less_w)
    );

    // Select completed parallel operations. Keep compare/shift results out
    // of arithmetic inputs when the FPGA compiler factors a result mux.
    wire select_adder_w = (op_i == `EDRV32_ALU_ADD) ||
                          (op_i == `EDRV32_ALU_SUB);
    wire select_shift_w = (op_i == `EDRV32_ALU_SLL) ||
                          (op_i == `EDRV32_ALU_SRL) ||
                          (op_i == `EDRV32_ALU_SRA);
    wire select_slt_w = (op_i == `EDRV32_ALU_SLT);
    wire select_sltu_w = (op_i == `EDRV32_ALU_SLTU);
    wire select_xor_w = (op_i == `EDRV32_ALU_XOR);
    wire select_or_w = (op_i == `EDRV32_ALU_OR);
    wire select_and_w = (op_i == `EDRV32_ALU_AND);
    wire select_copy_w = (op_i == `EDRV32_ALU_COPY_B);

    assign result_o = (adder_result_w & {32{select_adder_w}}) |
                      (shift_result_w & {32{select_shift_w}}) |
                      {31'd0, signed_less_w && select_slt_w} |
                      {31'd0, unsigned_less_w && select_sltu_w} |
                      ((lhs_i ^ rhs_i) & {32{select_xor_w}}) |
                      ((lhs_i | rhs_i) & {32{select_or_w}}) |
                      ((lhs_i & rhs_i) & {32{select_and_w}}) |
                      (rhs_i & {32{select_copy_w}});

endmodule
