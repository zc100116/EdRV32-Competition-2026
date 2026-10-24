// ============================================================================
// File        : edrv32_pair.vh
// Description : Optional younger ALU payload carried with its older scalar
//               packet. Packed valid is meaningful only with the parent valid.
// ============================================================================
`ifndef EDRV32_PAIR_VH
`define EDRV32_PAIR_VH
`include "edrv32_uop.vh"

// DECODE: {valid, pc, instr, compressed, epoch, rd, write, alu_op, lhs, rhs,
//          lhs_source, rhs_source}. Sources: 0=DECODE value, 1=resident A,
//          2=resident B. Both resident sources use the parent's registered PC.
`define EDRV32_PAIR_DECODE_W (144 + `EDRV32_EPOCH_W)
// EX onward: {valid, pc, instr, compressed, epoch, rd, write, result}.
`define EDRV32_PAIR_RESULT_W (104 + `EDRV32_EPOCH_W)
`endif
