// ============================================================================
// File        : edrv32_immgen.v
// Description : Immediate extraction for canonical 32-bit RV32 instructions.
// ============================================================================
`include "edrv32_isa.vh"
`include "edrv32_uop.vh"

module edrv32_immgen (
    input  wire [`EDRV32_XLEN-1:0]       instr_i,
    input  wire [`EDRV32_IMM_SEL_W-1:0]  imm_sel_i,
    output reg  [`EDRV32_XLEN-1:0]       imm_o
);

    always @* begin
        case (imm_sel_i)
            `EDRV32_IMM_I:    imm_o = {{20{instr_i[31]}}, instr_i[31:20]};
            `EDRV32_IMM_S:    imm_o = {{20{instr_i[31]}}, instr_i[31:25], instr_i[11:7]};
            `EDRV32_IMM_B:    imm_o = {{19{instr_i[31]}}, instr_i[31], instr_i[7],
                                       instr_i[30:25], instr_i[11:8], 1'b0};
            `EDRV32_IMM_U:    imm_o = {instr_i[31:12], 12'd0};
            `EDRV32_IMM_J:    imm_o = {{11{instr_i[31]}}, instr_i[31], instr_i[19:12],
                                       instr_i[20], instr_i[30:21], 1'b0};
            `EDRV32_IMM_Z:    imm_o = {27'd0, instr_i[19:15]};
            default:          imm_o = 32'd0;
        endcase
    end

endmodule
