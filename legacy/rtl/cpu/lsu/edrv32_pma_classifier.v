// ============================================================================
// File        : edrv32_pma_classifier.v
// Description : Single combinational PMA classifier for instruction and data
//               accesses in the frozen competition address map.
// Notes       : Region constants and attributes come only from the generated
//               edrv32_pma.vh contract.  All regions are naturally aligned
//               powers of two, so decode is a shallow parallel prefix match;
//               no base-plus-size carry chain is placed in MEM1.
// ============================================================================
`include "edrv32_pma.vh"

module edrv32_pma_classifier #(
    parameter integer TCM_ENABLE  = 0,
    parameter integer ITCM_ENABLE = TCM_ENABLE,
    parameter integer DTCM_ENABLE = TCM_ENABLE
) (
    input  wire [31:0] address_i,
    input  wire        instruction_i,
    input  wire        load_i,
    input  wire        store_i,

    output wire        mapped_o,
    output wire        permitted_o,
    output wire        access_fault_o,
    output wire        cacheable_o,
    output wire        tcm_o,
    output wire        device_o,
    output wire [`PMA_ATTR_WIDTH-1:0] attributes_o
);

    localparam [31:0] ROM_BASE = `SOC_ROM_BASE;
    localparam [31:0] ITCM_BASE = `SOC_ITCM_BASE;
    localparam [31:0] DTCM_BASE = `SOC_DTCM_BASE;
    localparam [31:0] SRAM_BASE = `SOC_SRAM_BASE;
    localparam [31:0] CLINT_BASE = `SOC_CLINT_BASE;
    localparam [31:0] PLIC_BASE = `SOC_PLIC_BASE;
    localparam [31:0] PERIPH_BASE = `SOC_PERIPH_BASE;
    localparam [31:0] DDR_BASE = `SOC_DDR_BASE;
    localparam [31:0] DDR_UNCACHED_BASE = `SOC_DDR_UNCACHED_BASE;

    wire match_rom_w = address_i[31:14] == ROM_BASE[31:14];
    wire match_itcm_w = address_i[31:16] == ITCM_BASE[31:16];
    wire match_dtcm_w = address_i[31:16] == DTCM_BASE[31:16];
    wire match_sram_w = address_i[31:18] == SRAM_BASE[31:18];
    wire match_clint_w = address_i[31:16] == CLINT_BASE[31:16];
    wire match_plic_w = address_i[31:22] == PLIC_BASE[31:22];
    wire match_periph_w = address_i[31:18] == PERIPH_BASE[31:18];
    wire match_ddr_w = address_i[31:30] == DDR_BASE[31:30];
    wire match_ddr_uncached_w = address_i[31:30] == DDR_UNCACHED_BASE[31:30];

    reg [`PMA_ATTR_WIDTH-1:0] attributes_w;
    reg mapped_w;
    always @* begin
        attributes_w = {`PMA_ATTR_WIDTH{1'b0}};
        mapped_w = 1'b1;
        if (match_rom_w)
            attributes_w = `PMA_ATTR_ROM;
        else if (match_itcm_w)
            attributes_w = `PMA_ATTR_ITCM;
        else if (match_dtcm_w)
            attributes_w = `PMA_ATTR_DTCM;
        else if (match_sram_w)
            attributes_w = `PMA_ATTR_SRAM;
        else if (match_clint_w)
            attributes_w = `PMA_ATTR_CLINT;
        else if (match_plic_w)
            attributes_w = `PMA_ATTR_PLIC;
        else if (match_periph_w)
            attributes_w = `PMA_ATTR_PERIPH;
        else if (match_ddr_w)
            attributes_w = `PMA_ATTR_DDR;
        else if (match_ddr_uncached_w)
            attributes_w = `PMA_ATTR_DDR_UNCACHED;
        else
            mapped_w = 1'b0;
    end

    wire access_requested_w = instruction_i || load_i || store_i;
    wire selected_tcm_enabled_w = match_itcm_w ? (ITCM_ENABLE != 0) :
                                       match_dtcm_w ? (DTCM_ENABLE != 0) :
                                                      (TCM_ENABLE != 0);
    wire tcm_enabled_w =
        ((attributes_w & `PMA_ATTR_TCM_ONLY) == {`PMA_ATTR_WIDTH{1'b0}}) ||
        selected_tcm_enabled_w;
    wire instruction_allowed_w =
        ((attributes_w & `PMA_ATTR_EXECUTABLE) != {`PMA_ATTR_WIDTH{1'b0}});
    wire load_allowed_w =
        ((attributes_w & `PMA_ATTR_READABLE) != {`PMA_ATTR_WIDTH{1'b0}});
    wire store_allowed_w =
        ((attributes_w & `PMA_ATTR_WRITABLE) != {`PMA_ATTR_WIDTH{1'b0}});
    wire access_permission_w =
        (!instruction_i || instruction_allowed_w) &&
        (!load_i || load_allowed_w) &&
        (!store_i || store_allowed_w);
    wire permitted_w = access_requested_w && mapped_w && tcm_enabled_w &&
                       access_permission_w;

    assign mapped_o = mapped_w;
    assign permitted_o = permitted_w;
    assign access_fault_o = access_requested_w && !permitted_w;
    assign cacheable_o = permitted_w &&
        ((attributes_w & `PMA_ATTR_CACHEABLE) != {`PMA_ATTR_WIDTH{1'b0}});
    assign tcm_o = permitted_w &&
        ((attributes_w & `PMA_ATTR_TCM_ONLY) != {`PMA_ATTR_WIDTH{1'b0}});
    assign device_o = permitted_w &&
        ((attributes_w & `PMA_ATTR_DEVICE) != {`PMA_ATTR_WIDTH{1'b0}});
    assign attributes_o = attributes_w;

endmodule
