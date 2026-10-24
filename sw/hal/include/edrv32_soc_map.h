// ============================================================================
// File        : edrv32_soc_map.h
// Author      : Edward ZC
// Description : Competition SoC address/interrupt contract for software.
//               GENERATED FILE - do not edit by hand.  Source of truth: rtl/include/soc_address_map.json (2026-09-19 Vision). CPU PMA/access permission bits remain inherited from the frozen CPU-REWRITE-SPEC-V1.0 contract.  Regenerate with:  python scripts/check/soc_addr_map.py generate
// Notes       : Values mirror rtl/include/edrv32_soc_map.vh.  Reserved
//               APB slots are address-only.  Device register offsets
//               belong to the HAL driver headers, not this file.
// ============================================================================
#ifndef EDRV32_SOC_MAP_H
#define EDRV32_SOC_MAP_H

// Region base addresses and exact sizes (design section 6.5.1).
#define SOC_ROM_BASE    0x00000000u  // Boot ROM (read-only, executable)
#define SOC_ROM_SIZE    0x00004000u
#define SOC_ITCM_BASE    0x01000000u  // ITCM (instruction fetch only, CPU-private). Access requires TCM enable; disabled window faults without a fabric request.
#define SOC_ITCM_SIZE    0x00010000u
#define SOC_DTCM_BASE    0x02000000u  // DTCM (data read/write only, CPU-private). Access requires TCM enable; disabled window faults without a fabric request.
#define SOC_DTCM_SIZE    0x00010000u
#define SOC_SRAM_BASE    0x10000000u  // On-chip SRAM - Phase-1 main memory (capacity converges with BRAM budget)
#define SOC_SRAM_SIZE    0x00040000u
#define SOC_CLINT_BASE    0x20000000u  // CLINT (non-cache MMIO, 64 KiB)
#define SOC_CLINT_SIZE    0x00010000u
#define SOC_PLIC_BASE    0x30000000u  // PLIC (non-cache MMIO, 4 MiB sparse SiFive layout)
#define SOC_PLIC_SIZE    0x00400000u
#define SOC_PERIPH_BASE    0x40000000u  // APB peripheral region (64 slots x 4 KiB, addr[17:12] sub-decode)
#define SOC_PERIPH_SIZE    0x00040000u
#define SOC_DDR_BASE    0x80000000u  // DDR canonical cacheable/executable view; implemented capacity is a board-profile parameter up to 1 GiB
#define SOC_DDR_SIZE    0x40000000u
#define SOC_DDR_UNCACHED_BASE    0xC0000000u  // Uncached/non-executable alias of DDR; aliases physical offset zero and consumes no additional memory
#define SOC_DDR_UNCACHED_SIZE    0x40000000u

// APB peripheral slot bases within the 0x4 region (4 KiB per slot).
#define SOC_UART0_BASE      0x40000000u  // slot 0x00
#define SOC_GPIO0_BASE      0x40001000u  // slot 0x01
#define SOC_SPI0_BASE      0x40002000u  // slot 0x02
#define SOC_CACHE_MAINT_BASE      0x40003000u  // slot 0x03
#define SOC_DDR_MONITOR_BASE      0x40004000u  // slot 0x04
#define SOC_STEREO_BASE      0x40005000u  // slot 0x05 (reserved)
#define SOC_CAM_BASE      0x40006000u  // slot 0x06
#define SOC_DISP_BASE      0x40007000u  // slot 0x07
#define SOC_PS2_BASE      0x40008000u  // slot 0x08 (reserved)
#define SOC_I2C0_BASE      0x40009000u  // slot 0x09 (reserved)
#define SOC_MEM_HUB_BASE      0x4000B000u  // slot 0x0B (reserved)
#define SOC_PIXEL_BASE      0x4000C000u  // slot 0x0C
#define SOC_GEOM_BASE      0x4000D000u  // slot 0x0D (reserved)
#define SOC_RENDER_BASE      0x4000E000u  // slot 0x0E (reserved)
#define SOC_VISION_MGR_BASE      0x4000F000u  // slot 0x0F (reserved)

// Generic aliases resolve to instance 0.
#define SOC_GPIO_BASE   SOC_GPIO0_BASE
#define SOC_SPI_BASE   SOC_SPI0_BASE
#define SOC_UART_BASE   SOC_UART0_BASE

// PLIC interrupt source numbering (source 0 reserved).
#define PLIC_SRC_UART0    1u
#define PLIC_SRC_GPIO0    2u
#define PLIC_SRC_SPI0     3u
#define PLIC_SRC_YOLO     4u
#define PLIC_SRC_STEREO   5u
#define PLIC_SRC_CAM      6u
#define PLIC_SRC_DISP     7u
#define PLIC_SRC_PS2      8u
#define PLIC_SRC_I2C0     9u
#define PLIC_SRC_DDR_MEM  10u
#define PLIC_SRC_PIXEL    11u
#define PLIC_SRC_GEOM     12u
#define PLIC_SRC_RENDER   13u
#define PLIC_SRC_VISION_MGR 14u
#define PLIC_NUM_SOURCES  32u

#define PLIC_SRC_GPIO     PLIC_SRC_GPIO0
#define PLIC_SRC_SPI      PLIC_SRC_SPI0
#define PLIC_SRC_UART     PLIC_SRC_UART0

#endif // EDRV32_SOC_MAP_H
