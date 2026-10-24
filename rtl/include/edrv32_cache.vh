// ============================================================================
// File        : edrv32_cache.vh
// Description : Frozen V1 cache geometry constants shared at SoC boundaries.
// Notes       : Formal I$/D$ are each 4 KiB, 16-byte line, 2-way, blocking.
//               D$ is write-back + write-allocate.  Geometry alternatives,
//               write-through, store buffer, CWF and CMO are not V1 options.
// ============================================================================
`ifndef EDRV32_CACHE_VH
`define EDRV32_CACHE_VH

`define ICACHE_SIZE_BYTES     4096
`define ICACHE_LINE_BYTES     16
`define DCACHE_SIZE_BYTES     4096
`define DCACHE_LINE_BYTES     16
`define EDRV32_DC_LINE_BITS   128

`endif // EDRV32_CACHE_VH
