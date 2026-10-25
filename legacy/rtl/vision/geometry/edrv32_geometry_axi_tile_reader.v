// ============================================================================
// File        : edrv32_geometry_axi_tile_reader.v
// Description : AXI reader for one 16x16 RGB565 source tile.
// Notes       : Each tile row is one aligned 256-bit AXI beat.  Rows may return
//               out of order; RID is the tile row index. Partial bottom tiles
//               are completed locally with zero rows.
// ============================================================================

module edrv32_geometry_axi_tile_reader (
    input  wire         clk_i,
    input  wire         rst_n_i,

    input  wire         req_valid_i,
    output wire         req_ready_o,
    input  wire [31:0]  req_surface_base_i,
    input  wire [31:0]  req_stride_i,
    input  wire [15:0]  req_src_width_i,
    input  wire [15:0]  req_src_height_i,
    input  wire [11:0]  req_tile_x_i,
    input  wire [11:0]  req_tile_y_i,

    output wire         row_valid_o,
    input  wire         row_ready_i,
    output wire [3:0]   row_index_o,
    output wire [255:0] row_data_o,
    output wire         done_o,
    output wire         error_o,

    output wire [3:0]   m_arid_o,
    output wire [31:0]  m_araddr_o,
    output wire [7:0]   m_arlen_o,
    output wire [2:0]   m_arsize_o,
    output wire [1:0]   m_arburst_o,
    output wire [3:0]   m_arqos_o,
    output wire         m_arvalid_o,
    input  wire         m_arready_i,
    input  wire [3:0]   m_rid_i,
    input  wire [255:0] m_rdata_i,
    input  wire [1:0]   m_rresp_i,
    input  wire         m_rlast_i,
    input  wire         m_rvalid_i,
    output wire         m_rready_o
);

    localparam [1:0] RESP_OKAY = 2'b00;

    reg active_r;
    reg done_r;
    reg error_r;
    reg [4:0] valid_rows_r;
    reg [4:0] issued_rows_r;
    reg [4:0] returned_rows_r;
    reg [4:0] zero_row_r;
    reg [15:0] returned_bitmap_r;
    reg [31:0] next_addr_r;
    reg [31:0] stride_r;

    wire [27:0] tile_origin_y_w = {req_tile_y_i, 4'b0};
    wire [27:0] tile_origin_x_w = {req_tile_x_i, 4'b0};
    wire [32:0] row_offset_w = tile_origin_y_w * req_stride_i;
    wire [31:0] tile_offset_x_w = {15'b0, tile_origin_x_w[15:0], 1'b0};
    wire [32:0] tile_base_full_w = {1'b0, req_surface_base_i} +
        row_offset_w + {1'b0, tile_offset_x_w};
    wire [16:0] width_bytes_w = {1'b0, req_src_width_i} << 1;
    wire tile_inside_w = (tile_origin_x_w < req_src_width_i) &&
        (tile_origin_y_w < req_src_height_i);
    wire req_legal_w = tile_inside_w &&
        (req_surface_base_i[4:0] == 5'b0) &&
        (req_stride_i[4:0] == 5'b0) &&
        ({1'b0, req_stride_i} >= {{16{1'b0}}, width_bytes_w}) &&
        !tile_base_full_w[32];
    wire [16:0] rows_remaining_w =
        {1'b0, req_src_height_i} - {1'b0, tile_origin_y_w[15:0]};
    wire [4:0] accepted_rows_w = rows_remaining_w >= 17'd16 ?
        5'd16 : rows_remaining_w[4:0];

    wire req_fire_w = req_valid_i && req_ready_o;
    wire ar_fire_w = m_arvalid_o && m_arready_i;
    wire use_r_w = active_r && m_rvalid_i;
    wire use_zero_w = active_r &&
        (returned_rows_r == valid_rows_r) &&
        (zero_row_r < 5'd16) && !m_rvalid_i;
    wire row_fire_w = row_valid_o && row_ready_i;
    wire final_row_w = use_zero_w && (zero_row_r == 5'd15);

    assign req_ready_o = !active_r;
    assign row_valid_o = use_r_w || use_zero_w;
    assign row_index_o = use_r_w ? m_rid_i : zero_row_r[3:0];
    assign row_data_o = use_r_w && (m_rresp_i == RESP_OKAY) ?
        m_rdata_i : 256'b0;
    assign done_o = done_r;
    assign error_o = error_r;

    assign m_arid_o = issued_rows_r[3:0];
    assign m_araddr_o = next_addr_r;
    assign m_arlen_o = 8'b0;
    assign m_arsize_o = 3'd5;
    assign m_arburst_o = 2'b01;
    assign m_arqos_o = 4'h8;
    assign m_arvalid_o = active_r && (issued_rows_r < valid_rows_r);
    assign m_rready_o = active_r && row_ready_i;

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            active_r <= 1'b0;
            done_r <= 1'b0;
            error_r <= 1'b0;
            valid_rows_r <= 5'b0;
            issued_rows_r <= 5'b0;
            returned_rows_r <= 5'b0;
            zero_row_r <= 5'b0;
            returned_bitmap_r <= 16'b0;
            next_addr_r <= 32'b0;
            stride_r <= 32'b0;
        end else begin
            done_r <= 1'b0;

            if (req_fire_w) begin
                error_r <= !req_legal_w;
                issued_rows_r <= 5'b0;
                returned_rows_r <= 5'b0;
                returned_bitmap_r <= 16'b0;
                next_addr_r <= tile_base_full_w[31:0];
                stride_r <= req_stride_i;
                if (req_legal_w) begin
                    active_r <= 1'b1;
                    valid_rows_r <= accepted_rows_w;
                    zero_row_r <= accepted_rows_w;
                end else begin
                    active_r <= 1'b0;
                    valid_rows_r <= 5'b0;
                    zero_row_r <= 5'b0;
                    done_r <= 1'b1;
                end
            end

            if (ar_fire_w) begin
                issued_rows_r <= issued_rows_r + 1'b1;
                next_addr_r <= next_addr_r + stride_r;
            end

            if (row_fire_w && use_r_w) begin
                if ((m_rresp_i != RESP_OKAY) || !m_rlast_i ||
                    (m_rid_i >= valid_rows_r) ||
                    returned_bitmap_r[m_rid_i])
                    error_r <= 1'b1;
                returned_bitmap_r[m_rid_i] <= 1'b1;
                returned_rows_r <= returned_rows_r + 1'b1;
                if ((valid_rows_r == 5'd16) &&
                    (returned_rows_r == 5'd15)) begin
                    active_r <= 1'b0;
                    done_r <= 1'b1;
                end
            end

            if (row_fire_w && use_zero_w) begin
                if (final_row_w) begin
                    active_r <= 1'b0;
                    done_r <= 1'b1;
                end else begin
                    zero_row_r <= zero_row_r + 1'b1;
                end
            end
        end
    end

endmodule
