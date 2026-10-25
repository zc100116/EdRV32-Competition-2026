// ============================================================================
// File        : edrv32_build_mode.vh
// Spec        : CLAUDE.md 5.4, 8
// Description : Global build-mode selection. Synthesis defines FPGA_MODE,
//               simulation defines SIM_MODE. Only rtl/tech/ IP wrappers test
//               the derived EDRV32_FPGA_MEMORY_MODE macro. Defining both
//               modes is a compile error, reported here and nowhere else.
// ============================================================================
`ifndef EDRV32_BUILD_MODE_VH
`define EDRV32_BUILD_MODE_VH

`ifdef FPGA_MODE
    `ifdef SIM_MODE
        `error "Define only one of FPGA_MODE or SIM_MODE"
    `endif
    `define EDRV32_FPGA_MEMORY_MODE
`endif

`endif
