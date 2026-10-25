// ============================================================================
// File        : edrv32_soc_map.vh
// Author      : Edward ZC
// Description : Competition SoC address, interrupt and APB slot contract
//               for RTL, verification and software.
//               GENERATED FILE - do not edit by hand.  Source of truth:
//               rtl/include/soc_address_map.json (2026-09-19 Vision).
//               CPU PMA/access permissions inherit the frozen CPU-
//               REWRITE-SPEC-V1.0 contract.
//               Regenerate with:
//               python scripts/check/soc_addr_map.py generate
// Notes       : Peripheral register offsets/bits are device ABI and live
//               in edrv32_periph_abi.vh (hand-maintained), included at
//               the end of this file.  64 APB slots decode addr[17:12];
//               each slot is 4 KiB.  Reserved slots are address-only.
// ============================================================================
`ifndef EDRV32_SOC_MAP_VH
`define EDRV32_SOC_MAP_VH

// ----------------------------------------------------------------------------
// Region base addresses and exact sizes (design section 6.5.1).
// ----------------------------------------------------------------------------
`define SOC_ROM_BASE          32'h0000_0000   // Boot ROM (read-only, executable)
`define SOC_ROM_SIZE          32'd16384
`define SOC_ITCM_BASE         32'h0100_0000   // ITCM (instruction fetch only, CPU-private). Access requires TCM enable; disabled window faults without a fabric request.
`define SOC_ITCM_SIZE         32'd65536
`define SOC_DTCM_BASE         32'h0200_0000   // DTCM (data read/write only, CPU-private). Access requires TCM enable; disabled window faults without a fabric request.
`define SOC_DTCM_SIZE         32'd65536
`define SOC_SRAM_BASE         32'h1000_0000   // On-chip SRAM - Phase-1 main memory (capacity converges with BRAM budget)
`define SOC_SRAM_SIZE         32'd262144
`define SOC_CLINT_BASE        32'h2000_0000   // CLINT (non-cache MMIO, 64 KiB)
`define SOC_CLINT_SIZE        32'd65536
`define SOC_PLIC_BASE         32'h3000_0000   // PLIC (non-cache MMIO, 4 MiB sparse SiFive layout)
`define SOC_PLIC_SIZE         32'd4194304
`define SOC_PERIPH_BASE       32'h4000_0000   // APB peripheral region (64 slots x 4 KiB, addr[17:12] sub-decode)
`define SOC_PERIPH_SIZE       32'd262144
`define SOC_DDR_BASE          32'h8000_0000   // DDR canonical cacheable/executable view; implemented capacity is a board-profile parameter up to 1 GiB
`define SOC_DDR_SIZE          32'd1073741824
`define SOC_DDR_UNCACHED_BASE 32'hC000_0000   // Uncached/non-executable alias of DDR; aliases physical offset zero and consumes no additional memory
`define SOC_DDR_UNCACHED_SIZE 32'd1073741824

// ----------------------------------------------------------------------------
// APB peripheral slot bases within the 0x4 region.  Each slot is 4 KiB,
// sub-decoded by addr[17:12].  Reserved slots are address-only and
// produce no RTL (design section 6.5.1).
// ----------------------------------------------------------------------------
`define SOC_UART0_BASE       32'h4000_0000   // slot 0x00 - UART #0
`define SOC_GPIO0_BASE       32'h4000_1000   // slot 0x01 - GPIO #0 (16 bit)
`define SOC_SPI0_BASE        32'h4000_2000   // slot 0x02 - SPI #0
`define SOC_CACHE_MAINT_BASE 32'h4000_3000   // slot 0x03 - cache maintenance
`define SOC_DDR_MONITOR_BASE 32'h4000_4000   // slot 0x04 - DDR traffic generator and performance monitor
`define SOC_STEREO_BASE      32'h4000_5000   // slot 0x05 - stereo depth control window (reserved)
`define SOC_CAM_BASE         32'h4000_6000   // slot 0x06 - camera capture control
`define SOC_DISP_BASE        32'h4000_7000   // slot 0x07 - display control (HDMI TX)
`define SOC_PS2_BASE         32'h4000_8000   // slot 0x08 - PS/2 (reserved)
`define SOC_I2C0_BASE        32'h4000_9000   // slot 0x09 - I2C master (reserved)
`define SOC_MEM_HUB_BASE     32'h4000_B000   // slot 0x0B - vision memory hub control (reserved)
`define SOC_PIXEL_BASE       32'h4000_C000   // slot 0x0C - pixel point-processing control
`define SOC_GEOM_BASE        32'h4000_D000   // slot 0x0D - geometry and coordinate control (reserved)
`define SOC_RENDER_BASE      32'h4000_E000   // slot 0x0E - render compositor control (reserved)
`define SOC_VISION_MGR_BASE  32'h4000_F000   // slot 0x0F - vision system manager (reserved)

// Generic aliases resolve to instance 0.
`define SOC_GPIO_BASE   `SOC_GPIO0_BASE
`define SOC_SPI_BASE   `SOC_SPI0_BASE
`define SOC_UART_BASE   `SOC_UART0_BASE

// ----------------------------------------------------------------------------
// Address decode fields.
//   - Coarse decode: addr[31:28] (high nibble) -> region.
//   - Peripheral sub-decode: addr[17:12] (6 bits -> 64 slots) within
//     the 0x4 region.
// ----------------------------------------------------------------------------
`define SOC_NIB_MSB     31
`define SOC_NIB_LSB     28

`define SOC_NIB_ROM      4'h0
`define SOC_NIB_SRAM     4'h1
`define SOC_NIB_CLINT    4'h2
`define SOC_NIB_PLIC     4'h3
`define SOC_NIB_PERIPH   4'h4
`define SOC_NIB_EXTMEM   4'h8
`define SOC_NIB_DDR_UNCACHED 4'hC

`define SOC_PSEL_MSB    17
`define SOC_PSEL_LSB    12

// Frozen APB slot codes (design section 6.5.1).
`define SOC_PSEL_UART0        6'h00          // 0x00
`define SOC_PSEL_GPIO0        6'h01          // 0x01
`define SOC_PSEL_SPI0         6'h02          // 0x02
`define SOC_PSEL_CACHE_MAINT  6'h03          // 0x03
`define SOC_PSEL_DDR_MONITOR  6'h04          // 0x04
`define SOC_PSEL_STEREO       6'h05          // 0x05 (reserved)
`define SOC_PSEL_CAM          6'h06          // 0x06
`define SOC_PSEL_DISP         6'h07          // 0x07
`define SOC_PSEL_PS2          6'h08          // 0x08 (reserved)
`define SOC_PSEL_I2C0         6'h09          // 0x09 (reserved)
`define SOC_PSEL_MEM_HUB      6'h0B          // 0x0B (reserved)
`define SOC_PSEL_PIXEL        6'h0C          // 0x0C
`define SOC_PSEL_GEOM         6'h0D          // 0x0D (reserved)
`define SOC_PSEL_RENDER       6'h0E          // 0x0E (reserved)
`define SOC_PSEL_VISION_MGR   6'h0F          // 0x0F (reserved)

// Generic aliases resolve to instance 0.
`define SOC_PSEL_GPIO     `SOC_PSEL_GPIO0
`define SOC_PSEL_SPI      `SOC_PSEL_SPI0
`define SOC_PSEL_UART     `SOC_PSEL_UART0

// ----------------------------------------------------------------------------
// PLIC interrupt source numbering (design section 6.5.1).  Source 0
// reserved.  Register offsets live in edrv32_periph_abi.vh.
// ----------------------------------------------------------------------------
`define PLIC_SRC_UART0    32'd1
`define PLIC_SRC_GPIO0    32'd2
`define PLIC_SRC_SPI0     32'd3
`define PLIC_SRC_YOLO     32'd4
`define PLIC_SRC_STEREO   32'd5
`define PLIC_SRC_CAM      32'd6
`define PLIC_SRC_DISP     32'd7
`define PLIC_SRC_PS2      32'd8
`define PLIC_SRC_I2C0     32'd9
`define PLIC_SRC_DDR_MEM  32'd10
`define PLIC_SRC_PIXEL    32'd11
`define PLIC_SRC_GEOM     32'd12
`define PLIC_SRC_RENDER   32'd13
`define PLIC_SRC_VISION_MGR 32'd14
`define PLIC_NUM_SOURCES  32'd32       // total source count (incl. reserved source 0)

// Backward-compatible aliases
`define PLIC_SRC_GPIO     `PLIC_SRC_GPIO0
`define PLIC_SRC_SPI      `PLIC_SRC_SPI0
`define PLIC_SRC_UART     `PLIC_SRC_UART0

// Peripheral register ABI (offsets/bit fields, hand-maintained).
`include "edrv32_periph_abi.vh"

`endif // EDRV32_SOC_MAP_VH
