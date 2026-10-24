// ============================================================================
// File        : edrv32_pma.vh
// Author      : Edward ZC
// Description : Competition physical-memory-attribute (PMA) table.  GENERATED FILE - do not edit by hand.  Source of truth: rtl/include/soc_address_map.json (2026-09-19 Vision). CPU PMA/access permission bits remain inherited from the frozen CPU-REWRITE-SPEC-V1.0 contract.  Regenerate with:  python scripts/check/soc_addr_map.py generate
// Notes       : Every PMA consumer (cache wrapper and future memory
//               targets) must use this table, never inline bounds.
//               Per-region PMA_ATTR_*/PMA_SIZE_* macros are the only
//               encodings.  Region bounds follow edrv32_soc_map.vh.
// ============================================================================
`ifndef EDRV32_PMA_VH
`define EDRV32_PMA_VH

`include "edrv32_soc_map.vh"

// ----------------------------------------------------------------------------
// PMA attribute bits per region.
`define PMA_ATTR_WIDTH       8
//   bit0  CACHEABLE  : cacheable (SRAM/DDR canonical)
//   bit1  EXECUTABLE : instruction fetch allowed
//   bit2  READABLE   : data load allowed
//   bit3  WRITABLE   : data store allowed
//   bit4  IDEMPOTENT : idempotent (re-reads stable, safe to probe)
//   bit5  DEVICE     : ordered device/MMIO access
//   bit6  TCM_ONLY   : access requires the TCM profile to be enabled
//   bit7  RETAINED   : retains contents across non-POR reset
// ----------------------------------------------------------------------------
`define PMA_ATTR_CACHEABLE   8'b00000001
`define PMA_ATTR_EXECUTABLE  8'b00000010
`define PMA_ATTR_READABLE    8'b00000100
`define PMA_ATTR_WRITABLE    8'b00001000
`define PMA_ATTR_IDEMPOTENT  8'b00010000
`define PMA_ATTR_DEVICE      8'b00100000
`define PMA_ATTR_TCM_ONLY    8'b01000000
`define PMA_ATTR_RETAINED    8'b10000000

// Accesses outside every region and accesses to a disabled TCM never
// reach the fabric.  MEM1 converts them into precise access faults.
`define PMA_HOLE_FAULT_NO_REQUEST          1'b1
`define PMA_TCM_DISABLED_FAULT_NO_REQUEST  1'b1
`define PMA_REGION_COUNT                   9

// ----------------------------------------------------------------------------
// Region attributes (frozen competition contract, design section 6.5.1).
// ----------------------------------------------------------------------------
`define PMA_ATTR_ROM         8'b10000110
`define PMA_ATTR_ITCM        8'b11010010
`define PMA_ATTR_DTCM        8'b11011100
`define PMA_ATTR_SRAM        8'b10011111
`define PMA_ATTR_CLINT       8'b00111100
`define PMA_ATTR_PLIC        8'b00111100
`define PMA_ATTR_PERIPH      8'b00101100
`define PMA_ATTR_DDR         8'b00011111
`define PMA_ATTR_DDR_UNCACHED 8'b00011100

// ----------------------------------------------------------------------------
// Region sizes (single source; identical values to SOC_*_SIZE).
// ----------------------------------------------------------------------------
`define PMA_SIZE_ROM         32'd16384
`define PMA_SIZE_ITCM        32'd65536
`define PMA_SIZE_DTCM        32'd65536
`define PMA_SIZE_SRAM        32'd262144
`define PMA_SIZE_CLINT       32'd65536
`define PMA_SIZE_PLIC        32'd4194304
`define PMA_SIZE_PERIPH      32'd262144
`define PMA_SIZE_DDR         32'd1073741824
`define PMA_SIZE_DDR_UNCACHED 32'd1073741824

// ----------------------------------------------------------------------------
// Region table: (name, base, size, attributes) - packed form for table
// consumers and for reference-model parsers.
// ----------------------------------------------------------------------------
`define PMA_REGION_ROM         "ROM",       `SOC_ROM_BASE,       `PMA_SIZE_ROM,       `PMA_ATTR_ROM
`define PMA_REGION_ITCM        "ITCM",      `SOC_ITCM_BASE,      `PMA_SIZE_ITCM,      `PMA_ATTR_ITCM
`define PMA_REGION_DTCM        "DTCM",      `SOC_DTCM_BASE,      `PMA_SIZE_DTCM,      `PMA_ATTR_DTCM
`define PMA_REGION_SRAM        "SRAM",      `SOC_SRAM_BASE,      `PMA_SIZE_SRAM,      `PMA_ATTR_SRAM
`define PMA_REGION_CLINT       "CLINT",     `SOC_CLINT_BASE,     `PMA_SIZE_CLINT,     `PMA_ATTR_CLINT
`define PMA_REGION_PLIC        "PLIC",      `SOC_PLIC_BASE,      `PMA_SIZE_PLIC,      `PMA_ATTR_PLIC
`define PMA_REGION_PERIPH      "PERIPH",    `SOC_PERIPH_BASE,    `PMA_SIZE_PERIPH,    `PMA_ATTR_PERIPH
`define PMA_REGION_DDR         "DDR",       `SOC_DDR_BASE,       `PMA_SIZE_DDR,       `PMA_ATTR_DDR
`define PMA_REGION_DDR_UNCACHED "DDR_UNCACHED", `SOC_DDR_UNCACHED_BASE, `PMA_SIZE_DDR_UNCACHED, `PMA_ATTR_DDR_UNCACHED

`endif // EDRV32_PMA_VH
