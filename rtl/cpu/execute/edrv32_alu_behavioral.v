// ============================================================================
// File        : edrv32_alu_behavioral.v
// Description : Behavioral RV32 integer ALU retained only as the A/B reference
//               model for simulation and synthesis experiments. It is excluded
//               from the production CPU file lists.
// ============================================================================
`include "edrv32_isa.vh"
`include "edrv32_uop.vh"

module edrv32_alu_behavioral (
    input  wire [`EDRV32_ALU_OP_W-1:0] op_i,
    input  wire [`EDRV32_XLEN-1:0]     lhs_i,
    input  wire [`EDRV32_XLEN-1:0]     rhs_i,
    output reg  [`EDRV32_XLEN-1:0]     result_o
);

    always @* begin
        case (op_i)
            `EDRV32_ALU_ADD:    result_o = lhs_i + rhs_i;
            `EDRV32_ALU_SUB:    result_o = lhs_i - rhs_i;
            `EDRV32_ALU_SLL:    result_o = lhs_i << rhs_i[4:0];
            `EDRV32_ALU_SLT:    result_o = ($signed(lhs_i) < $signed(rhs_i)) ? 32'd1 : 32'd0;
            `EDRV32_ALU_SLTU:   result_o = (lhs_i < rhs_i) ? 32'd1 : 32'd0;
            `EDRV32_ALU_XOR:    result_o = lhs_i ^ rhs_i;
            `EDRV32_ALU_SRL:    result_o = lhs_i >> rhs_i[4:0];
            `EDRV32_ALU_SRA:    result_o = $signed(lhs_i) >>> rhs_i[4:0];
            `EDRV32_ALU_OR:     result_o = lhs_i | rhs_i;
            `EDRV32_ALU_AND:    result_o = lhs_i & rhs_i;
            `EDRV32_ALU_COPY_B: result_o = rhs_i;
            default:            result_o = 32'd0;
        endcase
    end

endmodule
