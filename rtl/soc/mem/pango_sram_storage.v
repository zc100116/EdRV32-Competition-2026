// ============================================================================
// File        : pango_sram_storage.v
// Author      : Edward ZC
// Description : PG2L200H SRAM backend using generated Pango DRM IP.
// Notes       : The current 32-KiB generated IP module is named sram. The
//               legacy 8-KiB target retains its original module name.
// ============================================================================
module pango_sram_storage #(
    parameter integer PAIR_ADDR_W = 10
) (
    input  wire          clk,
    input  wire          rst_n,
    input  wire [PAIR_ADDR_W-1:0] rd_addr_i,
    output wire [63:0]   rd_data_o,
    input  wire [PAIR_ADDR_W-1:0] wr_addr_i,
    input  wire [63:0]   wr_data_i,
    input  wire [7:0]    wr_strb_i,
    input  wire          wr_en_i
);
    generate
        if (PAIR_ADDR_W == 10) begin : gen_sram_8k
            pango_sram_64x1024 u_pango_sram_64x1024 (
                .wr_data    (wr_data_i),
                .wr_addr    (wr_addr_i),
                .wr_en      (wr_en_i),
                .wr_clk     (clk),
                .wr_rst     (~rst_n),
                .wr_byte_en (wr_strb_i),
                .rd_data    (rd_data_o),
                .rd_addr    (rd_addr_i),
                .rd_clk     (clk),
                .rd_rst     (~rst_n)
            );
        end else if (PAIR_ADDR_W == 12) begin : gen_sram_32k
            sram u_sram (
                .wr_data    (wr_data_i),
                .wr_addr    (wr_addr_i),
                .wr_en      (wr_en_i),
                .wr_clk     (clk),
                .wr_rst     (~rst_n),
                .wr_byte_en (wr_strb_i),
                .rd_data    (rd_data_o),
                .rd_addr    (rd_addr_i),
                .rd_clk     (clk),
                .rd_rst     (~rst_n)
            );
        end else begin : gen_bad_geometry
            edrv32_pango_sram_pair_address_width_must_be_10_or_12
                u_static_assert ();
        end
    endgenerate
endmodule
