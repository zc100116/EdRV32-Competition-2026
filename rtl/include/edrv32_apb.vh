// ============================================================================
// File        : edrv32_apb.vh
// Author      : Edward ZC
// Description : APB shared macros — signal widths. AMBA 3 APB protocol compliant.
// Notes       : Used by current bus-to-APB bridges, apb_mux and APB peripherals.
//               and their testbenches.  PCLK = system clk (no clock divider).
//               AMBA 3 APB does not define PSTRB; this project adds a 4-bit
//               pstrb for byte-write consistency with native wstrb.
// ============================================================================
`ifndef EDRV32_APB_VH
`define EDRV32_APB_VH

// --- Signal widths ---
`define APB_AW            32            // Address width
`define APB_DW            32            // Data width
`define APB_SW             4            // Strobe width (DW/8; project extension)

`endif // EDRV32_APB_VH
