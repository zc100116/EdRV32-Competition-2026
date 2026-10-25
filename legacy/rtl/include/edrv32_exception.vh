// ============================================================================
// File        : edrv32_exception.vh
// Description : Synchronous exception cause values carried to COMMIT.
// ============================================================================
`ifndef EDRV32_EXCEPTION_VH
`define EDRV32_EXCEPTION_VH

`define EDRV32_EXC_CAUSE_W              4
`define EDRV32_EXC_INSTR_MISALIGNED   4'd0
`define EDRV32_EXC_INSTR_ACCESS       4'd1
`define EDRV32_EXC_ILLEGAL_INSTR      4'd2
`define EDRV32_EXC_BREAKPOINT         4'd3
`define EDRV32_EXC_LOAD_MISALIGNED    4'd4
`define EDRV32_EXC_LOAD_ACCESS        4'd5
`define EDRV32_EXC_STORE_MISALIGNED   4'd6
`define EDRV32_EXC_STORE_ACCESS       4'd7
`define EDRV32_EXC_ECALL_M           4'd11

`endif // EDRV32_EXCEPTION_VH
