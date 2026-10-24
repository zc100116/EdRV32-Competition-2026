// ============================================================================
// File        : edrv32_bus.vh
// Author      : Edward ZC
// Description : Harvard memory request/response channel encodings (cache-ready).
// Notes       : Shared contract header. Matches design doc section 7.
// ============================================================================
`ifndef EDRV32_BUS_VH
`define EDRV32_BUS_VH

// --- Core data width (guarded: also defined in edrv32_pipeline.vh) ---
`ifndef XLEN
`define XLEN 32
`endif

// --- Data access size (dmem_req_size_o) ---
`define BUS_SZ_W   2          // size field width
`define BUS_SZ_BYTE 2'b00
`define BUS_SZ_HALF 2'b01
`define BUS_SZ_WORD 2'b10

// --- Response error (imem_resp_error_i / dmem_resp_error_i) ---
`define BUS_OK   1'b0
`define BUS_ERR  1'b1

`endif // EDRV32_BUS_VH
