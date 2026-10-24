// ============================================================================
// File        : edrv32_isa.vh
// Description : Fixed RV32IMC instruction encodings used by the scalar core.
// Notes       : This rewrite intentionally has no F/D feature macros or
//               floating-point opcode definitions.
// ============================================================================
`ifndef EDRV32_ISA_VH
`define EDRV32_ISA_VH

`define EDRV32_XLEN              32
`define EDRV32_REG_ADDR_W         5

// Base opcode field, instr[6:0].
`define EDRV32_OPCODE_LOAD       7'b0000011
`define EDRV32_OPCODE_MISC_MEM   7'b0001111
`define EDRV32_OPCODE_OP_IMM     7'b0010011
`define EDRV32_OPCODE_AUIPC      7'b0010111
`define EDRV32_OPCODE_STORE      7'b0100011
`define EDRV32_OPCODE_OP         7'b0110011
`define EDRV32_OPCODE_LUI        7'b0110111
`define EDRV32_OPCODE_BRANCH     7'b1100011
`define EDRV32_OPCODE_JALR       7'b1100111
`define EDRV32_OPCODE_JAL        7'b1101111
`define EDRV32_OPCODE_SYSTEM     7'b1110011

// Exact SYSTEM instructions.
`define EDRV32_INSN_ECALL        32'h0000_0073
`define EDRV32_INSN_EBREAK       32'h0010_0073
`define EDRV32_INSN_MRET         32'h3020_0073
`define EDRV32_INSN_WFI          32'h1050_0073

`endif // EDRV32_ISA_VH
