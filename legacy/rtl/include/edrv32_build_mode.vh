// ============================================================================
// File        : edrv32_build_mode.vh
// Description : Global compile-time build-mode selection.
//
// Public compiler directives:
//   FPGA_MODE - instantiate generated FPGA memory IP backends.
//   SIM_MODE  - instantiate portable synchronous RTL memory backends.
//
// Official build flows define exactly one public directive.  The RTL-memory
// fallback keeps standalone lint/elaboration commands portable when neither
// directive is supplied.  Defining both is an error at every memory boundary.
// ============================================================================
`ifndef EDRV32_BUILD_MODE_VH
`define EDRV32_BUILD_MODE_VH

`ifdef FPGA_MODE
    `ifdef SIM_MODE
        `define EDRV32_BUILD_MODE_CONFLICT
    `else
        `define EDRV32_FPGA_MEMORY_MODE
    `endif
`elsif SIM_MODE
    `define EDRV32_SIM_MEMORY_MODE
`else
    `define EDRV32_SIM_MEMORY_MODE
    `define EDRV32_BUILD_MODE_DEFAULTED
`endif

`endif
