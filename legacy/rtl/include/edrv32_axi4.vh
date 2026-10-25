// ============================================================================
// File        : edrv32_axi4.vh
// Author      : Edward ZC
// Description : AXI4 Full shared definitions for the competition SoC fabric.
//               Conservative subset per design §6.1: aligned INCR bursts,
//               WSTRB, restricted ID width, restricted outstanding.
//               Not used / tied off system-wide: WRAP/FIXED bursts, exclusive
//               access, read interleaving, QoS/USER/REGION, atomic ops.
// Notes       : Public fabric data width is fixed to 64 bit. The CPU pipeline
//               remains 32 bit; I$/D$ assemble and disassemble line transfers
//               directly on their AXI master ports. Every AXI module includes
//               this header; widths come from here.
// ============================================================================
`ifndef EDRV32_AXI4_VH
`define EDRV32_AXI4_VH

// --- Widths (design §6.4: 64-bit fixed for Phase 2A; 128 bit is a future
//     data-backed upgrade candidate only) ---
`ifndef AXI_ID_W
    `define AXI_ID_W            4
`endif
`ifndef AXI_DATA_W
    `define AXI_DATA_W          64
`endif
`ifndef AXI_STRB_W
    `define AXI_STRB_W          (`AXI_DATA_W/8)
`endif
`define AXI_ADDR_W              32
`define AXI_LEN_W               8
`define AXI_SIZE_W              3
`define AXI_BURST_W             2
`define AXI_RESP_W              2

// --- Burst type ---
`define AXI_BURST_FIXED         2'b00
`define AXI_BURST_INCR          2'b01
`define AXI_BURST_WRAP          2'b10

// --- Response codes ---
`define AXI_RESP_OKAY           2'b00
`define AXI_RESP_EXOKAY         2'b01
`define AXI_RESP_SLVERR         2'b10
`define AXI_RESP_DECERR         2'b11

// --- Size encoding for a 32-bit beat (AXI_DATA_W/8 bytes) ---
`define AXI_SIZE_1B             3'd0
`define AXI_SIZE_2B             3'd1
`define AXI_SIZE_4B             3'd2
`define AXI_SIZE_8B             3'd3

// --- Convenience: sized field types ---
`define AXI_ID_MS               [`AXI_ID_W-1:0]
`define AXI_ADDR_MS             [`AXI_ADDR_W-1:0]
`define AXI_LEN_MS              [`AXI_LEN_W-1:0]
`define AXI_SIZE_MS             [`AXI_SIZE_W-1:0]
`define AXI_DATA_MS             [`AXI_DATA_W-1:0]
`define AXI_STRB_MS             [`AXI_STRB_W-1:0]

`endif // EDRV32_AXI4_VH
