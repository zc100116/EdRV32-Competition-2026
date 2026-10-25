// File: edrv32_cache_pma.v
// Spec: cache-spec 2.3; soc-spec 6.1.
// Description: High-address-bit decode of executable, cached and device regions.
// Clock: clk_sys.
// Address-high-bit PMA classification shared by the two cache controllers.
// Local address constants await the P0 generated SoC map. Combinational logic.
module edrv32_cache_pma (
    // Requested physical byte address and operation.
    input wire [31:0] addr_i,
    input wire execute_i,
    input wire store_i,
    output wire cacheable_o,
    output wire device_o,
    output wire err_o
);
    localparam [31:0] ROM_BASE = 32'h0000_0000;
    localparam [31:0] SRAM_BASE = 32'h1000_0000;
    localparam [31:0] CLINT_BASE = 32'h2000_0000;
    localparam [31:0] PLIC_BASE = 32'h3000_0000;
    localparam [31:0] SYS_APB_BASE = 32'h4000_0000;
    localparam [31:0] MEDIA_APB_BASE = 32'h4100_0000;
    localparam [31:0] DDR_BASE = 32'h8000_0000;
    localparam [31:0] DDR_ALIAS_BASE = 32'hc000_0000;
    wire unused_addr_w;
    assign unused_addr_w = &{1'b0, addr_i[13:0]};
    wire rom_w;
    wire device_region_w;
    assign rom_w = addr_i[31:14] == ROM_BASE[31:14];
    assign cacheable_o = addr_i[31:18] == SRAM_BASE[31:18] ||
                            addr_i[31:30] == DDR_BASE[31:30];
    assign device_region_w = addr_i[31:16] == CLINT_BASE[31:16] ||
                                addr_i[31:22] == PLIC_BASE[31:22] ||
                                addr_i[31:16] == SYS_APB_BASE[31:16] ||
                                addr_i[31:16] == MEDIA_APB_BASE[31:16] ||
                                addr_i[31:30] == DDR_ALIAS_BASE[31:30];
    assign device_o = !execute_i && (device_region_w || (rom_w && !store_i));
    assign err_o = !(cacheable_o || (rom_w && !store_i) ||
                    (!execute_i && device_region_w));
endmodule
