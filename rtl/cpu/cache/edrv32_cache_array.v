// ============================================================================
// File        : edrv32_cache_array.v
// Description : One synchronous-read cache tag/data array contract.
//               FPGA_MODE selects generated Pango DRM IP banks; SIM_MODE
//               selects portable synchronous RTL storage.
// Notes       : Storage is never reset.  The cache valid vector owns
//               visibility.  Read data is available after the accepting edge
//               and holds while rd_en_i is low.
// ============================================================================
`include "edrv32_build_mode.vh"

module edrv32_cache_array #(
    parameter integer SET_COUNT = 128,
    parameter integer INDEX_W = $clog2(SET_COUNT),
    parameter integer TAG_W = 21
) (
    input  wire                 clk_i,
    input  wire                 rst_n_i,

    input  wire                 rd_en_i,
    input  wire [INDEX_W-1:0]   rd_index_i,
    output wire [TAG_W-1:0]     rd_tag_o,
    output wire [127:0]         rd_line_o,

    input  wire                 tag_wr_en_i,
    input  wire [INDEX_W-1:0]   tag_wr_index_i,
    input  wire [TAG_W-1:0]     tag_wr_data_i,

    input  wire                 data_wr_en_i,
    input  wire [INDEX_W-1:0]   data_wr_index_i,
    input  wire [127:0]         data_wr_line_i,
    input  wire [15:0]          data_wr_byte_en_i
);

`ifdef EDRV32_BUILD_MODE_CONFLICT
    edrv32_build_mode_error__define_only_one_of_FPGA_MODE_or_SIM_MODE
        u_build_mode_error ();
`elsif EDRV32_FPGA_MEMORY_MODE
    generate
        if (1) begin : gen_pango_drm
            // One generated 128-entry tag RAM and one 128-bit data RAM form
            // exactly one cache way.  The cache instantiates this module once
            // per way; no address banking is hidden inside the storage layer.
            reg [6:0] held_read_index_r;
            wire [6:0] ip_read_index_w = rd_en_i
                ? rd_index_i[6:0] : held_read_index_r;

            always @(posedge clk_i or negedge rst_n_i) begin
                if (!rst_n_i)
                    held_read_index_r <= 7'd0;
                else if (rd_en_i)
                    held_read_index_r <= rd_index_i[6:0];
            end

            cache_tag u_tag_ram (
                // Write port.
                .wr_data(tag_wr_data_i[20:0]),
                .wr_addr(tag_wr_index_i[6:0]),
                .wr_en(tag_wr_en_i),
                .wr_clk(clk_i),
                .wr_rst(~rst_n_i),

                // Synchronous read port.
                .rd_data(rd_tag_o[20:0]),
                .rd_addr(ip_read_index_w),
                .rd_clk(clk_i),
                .rd_rst(~rst_n_i)
            );

            cache_data u_data_ram (
                // Byte-enabled write port.
                .wr_data(data_wr_line_i),
                .wr_addr(data_wr_index_i[6:0]),
                .wr_en(data_wr_en_i),
                .wr_clk(clk_i),
                .wr_rst(~rst_n_i),
                .wr_byte_en(data_wr_byte_en_i),

                // Synchronous read port.
                .rd_data(rd_line_o),
                .rd_addr(ip_read_index_w),
                .rd_clk(clk_i),
                .rd_rst(~rst_n_i)
            );

            if ((SET_COUNT != 128) ||
                (INDEX_W != 7) ||
                (TAG_W != 21)) begin : gen_bad_pango_geometry
                edrv32_pango_cache_geometry_must_be_128x21 u_static_assert ();
            end
        end
    endgenerate
`else
    generate
        if (1) begin : gen_portable_rtl
            reg [TAG_W-1:0] tag_mem [0:SET_COUNT-1];
            reg [127:0] data_mem [0:SET_COUNT-1];
            reg [TAG_W-1:0] rd_tag_r;
            reg [127:0] rd_line_r;
            wire [127:0] data_wr_mask_w = {
                {8{data_wr_byte_en_i[15]}}, {8{data_wr_byte_en_i[14]}},
                {8{data_wr_byte_en_i[13]}}, {8{data_wr_byte_en_i[12]}},
                {8{data_wr_byte_en_i[11]}}, {8{data_wr_byte_en_i[10]}},
                {8{data_wr_byte_en_i[9]}},  {8{data_wr_byte_en_i[8]}},
                {8{data_wr_byte_en_i[7]}},  {8{data_wr_byte_en_i[6]}},
                {8{data_wr_byte_en_i[5]}},  {8{data_wr_byte_en_i[4]}},
                {8{data_wr_byte_en_i[3]}},  {8{data_wr_byte_en_i[2]}},
                {8{data_wr_byte_en_i[1]}},  {8{data_wr_byte_en_i[0]}}
            };

            always @(posedge clk_i) begin
                if (rd_en_i) begin
                    rd_tag_r  <= tag_mem[rd_index_i];
                    rd_line_r <= data_mem[rd_index_i];
                end
            end

            always @(posedge clk_i) begin
                if (tag_wr_en_i)
                    tag_mem[tag_wr_index_i] <= tag_wr_data_i;
            end

            always @(posedge clk_i) begin
                if (data_wr_en_i) begin
                    // Single nonblocking byte-masked merge: the combinational
                    // read sees the pre-edge value, preserving the read-first
                    // same-address collision contract of the FPGA DRM model.
                    data_mem[data_wr_index_i] <=
                        (data_mem[data_wr_index_i] & ~data_wr_mask_w) |
                        (data_wr_line_i & data_wr_mask_w);
                end
            end

            assign rd_tag_o = rd_tag_r;
            assign rd_line_o = rd_line_r;
            wire unused_rst_n_w = rst_n_i;
        end
    endgenerate
`endif

endmodule
