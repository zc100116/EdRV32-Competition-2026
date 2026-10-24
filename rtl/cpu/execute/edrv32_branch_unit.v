// ============================================================================
// File        : edrv32_branch_unit.v
// Description : EX-local RV32 branch decision using the shared structural
//               comparator datapath.
// ============================================================================
`include "edrv32_uop.vh"

module edrv32_branch_unit (
    input  wire [`EDRV32_BRANCH_OP_W-1:0] branch_op_i,
    input  wire [31:0]                    lhs_i,
    input  wire [31:0]                    rhs_i,
    output reg                            taken_o
);

    wire equal_w;
    wire signed_less_w;
    wire unsigned_less_w;

    edrv32_compare32 u_compare (
        .lhs_i           (lhs_i),
        .rhs_i           (rhs_i),
        .equal_o         (equal_w),
        .signed_less_o   (signed_less_w),
        .unsigned_less_o (unsigned_less_w)
    );

    always @* begin
        case (branch_op_i)
            `EDRV32_BRANCH_EQ:  taken_o = equal_w;
            `EDRV32_BRANCH_NE:  taken_o = ~equal_w;
            `EDRV32_BRANCH_LT:  taken_o = signed_less_w;
            `EDRV32_BRANCH_GE:  taken_o = ~signed_less_w;
            `EDRV32_BRANCH_LTU: taken_o = unsigned_less_w;
            `EDRV32_BRANCH_GEU: taken_o = ~unsigned_less_w;
            default:            taken_o = 1'b0;
        endcase
    end

endmodule
