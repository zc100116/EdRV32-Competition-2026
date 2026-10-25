// File: edrv32_cache_pma.v
// Spec: cache-spec 2.3; soc-spec 6.1.
// Description: High-address-bit decode of executable, cached and device regions.
// Clock: clk_sys.
// Address-high-bit PMA classification shared by the two cache controllers.
// Generated power-of-two region sizes select the compared high bits.
module edrv32_cache_pma (
    // Requested physical byte address and operation.
    input wire [31:0] addr_i,
    input wire execute_i,
    input wire store_i,
    output wire cacheable_o,
    output wire device_o,
    output wire err_o
);
    // The shared map also declares attributes, APB slots and IRQs unused here.
    /* verilator lint_off UNUSEDPARAM */
    `include "edrv32_soc_map.vh"
    /* verilator lint_on UNUSEDPARAM */
    localparam ROM_BITS = $clog2(EDRV32_ROM_SIZE);
    localparam SRAM_BITS = $clog2(EDRV32_SRAM_SIZE);
    localparam CLINT_BITS = $clog2(EDRV32_CLINT_SIZE);
    localparam PLIC_BITS = $clog2(EDRV32_PLIC_SIZE);
    localparam SYS_APB_BITS = $clog2(EDRV32_SYS_APB_SIZE);
    localparam MEDIA_APB_BITS = $clog2(EDRV32_MEDIA_APB_SIZE);
    localparam DDR_BITS = $clog2(EDRV32_DDR_SIZE);
    localparam DDR_UNCACHED_BITS = $clog2(EDRV32_DDR_UNCACHED_SIZE);
    wire unused_addr_w;
    wire rom_w;
    wire device_region_w;
    assign unused_addr_w = &{1'b0, addr_i[ROM_BITS-1:0]};
    assign rom_w = addr_i[31:ROM_BITS] == EDRV32_ROM_BASE[31:ROM_BITS];
    assign cacheable_o = addr_i[31:SRAM_BITS] == EDRV32_SRAM_BASE[31:SRAM_BITS] ||
                        addr_i[31:DDR_BITS] == EDRV32_DDR_BASE[31:DDR_BITS];
    assign device_region_w = addr_i[31:CLINT_BITS] == EDRV32_CLINT_BASE[31:CLINT_BITS] ||
                            addr_i[31:PLIC_BITS] == EDRV32_PLIC_BASE[31:PLIC_BITS] ||
                            addr_i[31:SYS_APB_BITS] == EDRV32_SYS_APB_BASE[31:SYS_APB_BITS] ||
                            addr_i[31:MEDIA_APB_BITS] ==
                                EDRV32_MEDIA_APB_BASE[31:MEDIA_APB_BITS] ||
                            addr_i[31:DDR_UNCACHED_BITS] ==
                                EDRV32_DDR_UNCACHED_BASE[31:DDR_UNCACHED_BITS];
    assign device_o = !execute_i && (device_region_w || (rom_w && !store_i));
    assign err_o = !(cacheable_o || (rom_w && !store_i) ||
                    (!execute_i && device_region_w));
endmodule
