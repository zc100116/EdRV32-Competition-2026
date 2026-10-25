// ============================================================================
// File        : edrv32_adder64.v
// Description : 64-bit structural adder built from two 32-bit block-CLA units.
// Reuse       : Adapted from the pre-rewrite datapath/adder_64.v.
// ============================================================================
module edrv32_adder64 (
    input  wire [63:0] lhs_i,
    input  wire [63:0] rhs_i,
    input  wire        carry_i,
    output wire [63:0] sum_o,
    output wire        carry_o
);

    wire low_carry_w;

    edrv32_adder32 u_low (
        .lhs_i(lhs_i[31:0]),
        .rhs_i(rhs_i[31:0]),
        .carry_i(carry_i),
        .sum_o(sum_o[31:0]),
        .carry_o(low_carry_w)
    );

    edrv32_adder32 u_high (
        .lhs_i(lhs_i[63:32]),
        .rhs_i(rhs_i[63:32]),
        .carry_i(low_carry_w),
        .sum_o(sum_o[63:32]),
        .carry_o(carry_o)
    );

endmodule
