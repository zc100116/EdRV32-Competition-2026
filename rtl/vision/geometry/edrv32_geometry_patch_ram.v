// ============================================================================
// File        : edrv32_geometry_patch_ram.v
// Description : 64x64 RGB565 source patch stored as four 16-pixel columns.
// Notes       : Each column reuses the generated 64x256 geometry_tile_ram IP.
//               Replicated read copies provide two source-row ports, allowing
//               a complete bilinear 2x2 neighbourhood after one RAM cycle.
// ============================================================================

module edrv32_geometry_patch_ram (
    input  wire         clk_i,
    input  wire         rst_n_i,

    input  wire         wr_en_i,
    input  wire [1:0]   wr_column_i,
    input  wire [5:0]   wr_row_i,
    input  wire [255:0] wr_data_i,

    input  wire         rd_en_i,
    input  wire [5:0]   rd_row0_i,
    input  wire [5:0]   rd_row1_i,
    output wire [255:0] rd_col0_row0_o,
    output wire [255:0] rd_col0_row1_o,
    output wire [255:0] rd_col1_row0_o,
    output wire [255:0] rd_col1_row1_o,
    output wire [255:0] rd_col2_row0_o,
    output wire [255:0] rd_col2_row1_o,
    output wire [255:0] rd_col3_row0_o,
    output wire [255:0] rd_col3_row1_o
);

    genvar column_g;
    generate
        for (column_g = 0; column_g < 4; column_g = column_g + 1) begin : gen_column
            wire [255:0] row0_w;
            wire [255:0] row1_w;

            edrv32_geometry_tile_ram u_column_ram (
                .clk_i      (clk_i),
                .rst_n_i    (rst_n_i),
                .wr_en_i    (wr_en_i && (wr_column_i == column_g[1:0])),
                .wr_addr_i  (wr_row_i),
                .wr_data_i  (wr_data_i),
                .rd_en_i    (rd_en_i),
                .rd_addr0_i (rd_row0_i),
                .rd_data0_o (row0_w),
                .rd_addr1_i (rd_row1_i),
                .rd_data1_o (row1_w)
            );

            if (column_g == 0) begin : gen_col0_output
                assign rd_col0_row0_o = row0_w;
                assign rd_col0_row1_o = row1_w;
            end else if (column_g == 1) begin : gen_col1_output
                assign rd_col1_row0_o = row0_w;
                assign rd_col1_row1_o = row1_w;
            end else if (column_g == 2) begin : gen_col2_output
                assign rd_col2_row0_o = row0_w;
                assign rd_col2_row1_o = row1_w;
            end else begin : gen_col3_output
                assign rd_col3_row0_o = row0_w;
                assign rd_col3_row1_o = row1_w;
            end
        end
    endgenerate

endmodule
