// ============================================================================
// File        : edrv32_geometry_tile_cache.v
// Description : Four-entry 16x16 RGB565 tile cache and 2x2 neighborhood fetch.
// Notes       : A coordinate remains owned until its four pixels are available
//               or it is classified as fill. Tile rows are 256-bit DDR beats.
// ============================================================================

module edrv32_geometry_tile_cache (
    input  wire                     clk_i,
    input  wire                     rst_n_i,
    input  wire                     flush_i,

    input  wire [15:0]              crop_x_i,
    input  wire [15:0]              crop_y_i,
    input  wire [15:0]              crop_width_i,
    input  wire [15:0]              crop_height_i,
    input  wire [15:0]              fill_pixel_i,

    input  wire                     coord_valid_i,
    output wire                     coord_ready_o,
    input  wire signed [15:0]       coord_src_x_i,
    input  wire signed [15:0]       coord_src_y_i,
    input  wire [15:0]              coord_frac_x_i,
    input  wire [15:0]              coord_frac_y_i,
    input  wire                     coord_in_bounds_i,
    input  wire [15:0]              coord_dst_x_i,
    input  wire [15:0]              coord_dst_y_i,
    input  wire                     coord_sof_i,
    input  wire                     coord_eol_i,
    input  wire                     coord_eof_i,

    output wire                     sample_valid_o,
    input  wire                     sample_ready_i,
    output wire [15:0]              sample_p00_o,
    output wire [15:0]              sample_p10_o,
    output wire [15:0]              sample_p01_o,
    output wire [15:0]              sample_p11_o,
    output wire [15:0]              sample_frac_x_o,
    output wire [15:0]              sample_frac_y_o,
    output wire                     sample_in_bounds_o,
    output wire [15:0]              sample_fill_pixel_o,
    output wire [15:0]              sample_dst_x_o,
    output wire [15:0]              sample_dst_y_o,
    output wire                     sample_sof_o,
    output wire                     sample_eol_o,
    output wire                     sample_eof_o,

    output wire                     fill_req_valid_o,
    input  wire                     fill_req_ready_i,
    output wire [11:0]              fill_req_tile_x_o,
    output wire [11:0]              fill_req_tile_y_o,
    input  wire                     fill_row_valid_i,
    output wire                     fill_row_ready_o,
    input  wire [3:0]               fill_row_index_i,
    input  wire [255:0]             fill_row_data_i,
    input  wire                     fill_done_i,
    input  wire                     fill_error_i,

    output wire                     busy_o,
    output wire                     error_o
);

    localparam [2:0] STATE_IDLE      = 3'd0;
    localparam [2:0] STATE_CHECK     = 3'd1;
    localparam [2:0] STATE_OUTPUT    = 3'd2;
    localparam [2:0] STATE_FILL_REQ  = 3'd3;
    localparam [2:0] STATE_FILL_DATA = 3'd4;

    reg [2:0] state_r;
    reg error_r;
    reg [3:0] tile_valid_r;
    reg [11:0] tile_x_r [0:3];
    reg [11:0] tile_y_r [0:3];
    reg [1:0] replace_r;
    reg [1:0] fill_entry_r;
    reg [11:0] fill_tile_x_r;
    reg [11:0] fill_tile_y_r;

    reg [15:0] src_x0_r;
    reg [15:0] src_y0_r;
    reg [15:0] frac_x_r;
    reg [15:0] frac_y_r;
    reg in_bounds_r;
    reg [15:0] dst_x_r;
    reg [15:0] dst_y_r;
    reg sof_r;
    reg eol_r;
    reg eof_r;

    wire [16:0] crop_right_full_w = {1'b0, crop_x_i} +
        {1'b0, crop_width_i} - 1'b1;
    wire [16:0] crop_bottom_full_w = {1'b0, crop_y_i} +
        {1'b0, crop_height_i} - 1'b1;
    wire [15:0] crop_right_w = crop_right_full_w[15:0];
    wire [15:0] crop_bottom_w = crop_bottom_full_w[15:0];
    wire coord_inside_crop_w = coord_in_bounds_i &&
        !coord_src_x_i[15] && !coord_src_y_i[15] &&
        ($unsigned(coord_src_x_i) >= crop_x_i) &&
        ($unsigned(coord_src_x_i) <= crop_right_w) &&
        ($unsigned(coord_src_y_i) >= crop_y_i) &&
        ($unsigned(coord_src_y_i) <= crop_bottom_w);
    wire coord_fire_w = coord_valid_i && coord_ready_o;

    wire [15:0] src_x1_w = src_x0_r == crop_right_w ?
        src_x0_r : src_x0_r + 1'b1;
    wire [15:0] src_y1_w = src_y0_r == crop_bottom_w ?
        src_y0_r : src_y0_r + 1'b1;
    wire [11:0] req00_x_w = src_x0_r[15:4];
    wire [11:0] req00_y_w = src_y0_r[15:4];
    wire [11:0] req10_x_w = src_x1_w[15:4];
    wire [11:0] req10_y_w = src_y0_r[15:4];
    wire [11:0] req01_x_w = src_x0_r[15:4];
    wire [11:0] req01_y_w = src_y1_w[15:4];
    wire [11:0] req11_x_w = src_x1_w[15:4];
    wire [11:0] req11_y_w = src_y1_w[15:4];

    function [15:0] select_pixel;
        input [255:0] row_i;
        input [3:0] pixel_i;
        begin
            case (pixel_i)
                4'd0: select_pixel = row_i[15:0];
                4'd1: select_pixel = row_i[31:16];
                4'd2: select_pixel = row_i[47:32];
                4'd3: select_pixel = row_i[63:48];
                4'd4: select_pixel = row_i[79:64];
                4'd5: select_pixel = row_i[95:80];
                4'd6: select_pixel = row_i[111:96];
                4'd7: select_pixel = row_i[127:112];
                4'd8: select_pixel = row_i[143:128];
                4'd9: select_pixel = row_i[159:144];
                4'd10: select_pixel = row_i[175:160];
                4'd11: select_pixel = row_i[191:176];
                4'd12: select_pixel = row_i[207:192];
                4'd13: select_pixel = row_i[223:208];
                4'd14: select_pixel = row_i[239:224];
                default: select_pixel = row_i[255:240];
            endcase
        end
    endfunction

    reg [2:0] lookup00_w;
    reg [2:0] lookup10_w;
    reg [2:0] lookup01_w;
    reg [2:0] lookup11_w;
    reg found00_w;
    reg found10_w;
    reg found01_w;
    reg found11_w;
    integer lookup_i;
    always @(*) begin
        lookup00_w = 3'b0;
        lookup10_w = 3'b0;
        lookup01_w = 3'b0;
        lookup11_w = 3'b0;
        found00_w = 1'b0;
        found10_w = 1'b0;
        found01_w = 1'b0;
        found11_w = 1'b0;
        for (lookup_i = 0; lookup_i < 4; lookup_i = lookup_i + 1) begin
            if (!found00_w && tile_valid_r[lookup_i] &&
                (tile_x_r[lookup_i] == req00_x_w) &&
                (tile_y_r[lookup_i] == req00_y_w)) begin
                lookup00_w = {1'b1, lookup_i[1:0]};
                found00_w = 1'b1;
            end
            if (!found10_w && tile_valid_r[lookup_i] &&
                (tile_x_r[lookup_i] == req10_x_w) &&
                (tile_y_r[lookup_i] == req10_y_w)) begin
                lookup10_w = {1'b1, lookup_i[1:0]};
                found10_w = 1'b1;
            end
            if (!found01_w && tile_valid_r[lookup_i] &&
                (tile_x_r[lookup_i] == req01_x_w) &&
                (tile_y_r[lookup_i] == req01_y_w)) begin
                lookup01_w = {1'b1, lookup_i[1:0]};
                found01_w = 1'b1;
            end
            if (!found11_w && tile_valid_r[lookup_i] &&
                (tile_x_r[lookup_i] == req11_x_w) &&
                (tile_y_r[lookup_i] == req11_y_w)) begin
                lookup11_w = {1'b1, lookup_i[1:0]};
                found11_w = 1'b1;
            end
        end
    end

    wire all_hit_w = lookup00_w[2] && lookup10_w[2] &&
        lookup01_w[2] && lookup11_w[2];
    reg [11:0] missing_x_w;
    reg [11:0] missing_y_w;
    always @(*) begin
        missing_x_w = req00_x_w;
        missing_y_w = req00_y_w;
        if (!lookup00_w[2]) begin
            missing_x_w = req00_x_w;
            missing_y_w = req00_y_w;
        end else if (!lookup10_w[2]) begin
            missing_x_w = req10_x_w;
            missing_y_w = req10_y_w;
        end else if (!lookup01_w[2]) begin
            missing_x_w = req01_x_w;
            missing_y_w = req01_y_w;
        end else if (!lookup11_w[2]) begin
            missing_x_w = req11_x_w;
            missing_y_w = req11_y_w;
        end
    end

    reg [1:0] victim_w;
    reg victim_found_w;
    integer victim_i;
    integer victim_index_i;
    always @(*) begin
        victim_w = replace_r;
        victim_found_w = 1'b0;
        for (victim_i = 0; victim_i < 4; victim_i = victim_i + 1) begin
            victim_index_i = (replace_r + victim_i) & 3;
            if (!victim_found_w && !tile_valid_r[victim_index_i]) begin
                victim_w = victim_index_i[1:0];
                victim_found_w = 1'b1;
            end
        end
        if (!victim_found_w) begin
            for (victim_i = 0; victim_i < 4; victim_i = victim_i + 1) begin
                victim_index_i = (replace_r + victim_i) & 3;
                if (!victim_found_w &&
                    !(((tile_x_r[victim_index_i] == req00_x_w) &&
                       (tile_y_r[victim_index_i] == req00_y_w)) ||
                      ((tile_x_r[victim_index_i] == req10_x_w) &&
                       (tile_y_r[victim_index_i] == req10_y_w)) ||
                      ((tile_x_r[victim_index_i] == req01_x_w) &&
                       (tile_y_r[victim_index_i] == req01_y_w)) ||
                      ((tile_x_r[victim_index_i] == req11_x_w) &&
                       (tile_y_r[victim_index_i] == req11_y_w)))) begin
                    victim_w = victim_index_i[1:0];
                    victim_found_w = 1'b1;
                end
            end
        end
    end

    wire [255:0] tile_rd0_w [0:3];
    wire [255:0] tile_rd1_w [0:3];
    wire tile_read_en_w = (state_r == STATE_CHECK) && all_hit_w;
    wire fill_row_fire_w = fill_row_valid_i && fill_row_ready_o;

    genvar tile_g;
    generate
        for (tile_g = 0; tile_g < 4; tile_g = tile_g + 1) begin : gen_tile_ram
            edrv32_geometry_tile_ram u_tile_ram (
                .clk_i(clk_i), .rst_n_i(rst_n_i),
                .wr_en_i(fill_row_fire_w && (fill_entry_r == tile_g[1:0])),
                .wr_addr_i({2'b00, fill_row_index_i}),
                .wr_data_i(fill_row_data_i),
                .rd_en_i(tile_read_en_w),
                .rd_addr0_i({2'b00, src_y0_r[3:0]}),
                .rd_data0_o(tile_rd0_w[tile_g]),
                .rd_addr1_i({2'b00, src_y1_w[3:0]}),
                .rd_data1_o(tile_rd1_w[tile_g])
            );
        end
    endgenerate

    wire [255:0] row00_w = tile_rd0_w[lookup00_w[1:0]];
    wire [255:0] row10_w = tile_rd0_w[lookup10_w[1:0]];
    wire [255:0] row01_w = tile_rd1_w[lookup01_w[1:0]];
    wire [255:0] row11_w = tile_rd1_w[lookup11_w[1:0]];

    assign coord_ready_o = (state_r == STATE_IDLE) ||
        ((state_r == STATE_OUTPUT) && sample_ready_i);
    assign sample_valid_o = state_r == STATE_OUTPUT;
    assign sample_p00_o = in_bounds_r ?
        select_pixel(row00_w, src_x0_r[3:0]) : 16'b0;
    assign sample_p10_o = in_bounds_r ?
        select_pixel(row10_w, src_x1_w[3:0]) : 16'b0;
    assign sample_p01_o = in_bounds_r ?
        select_pixel(row01_w, src_x0_r[3:0]) : 16'b0;
    assign sample_p11_o = in_bounds_r ?
        select_pixel(row11_w, src_x1_w[3:0]) : 16'b0;
    assign sample_frac_x_o = frac_x_r;
    assign sample_frac_y_o = frac_y_r;
    assign sample_in_bounds_o = in_bounds_r;
    assign sample_fill_pixel_o = fill_pixel_i;
    assign sample_dst_x_o = dst_x_r;
    assign sample_dst_y_o = dst_y_r;
    assign sample_sof_o = sof_r;
    assign sample_eol_o = eol_r;
    assign sample_eof_o = eof_r;

    assign fill_req_valid_o = state_r == STATE_FILL_REQ;
    assign fill_req_tile_x_o = fill_tile_x_r;
    assign fill_req_tile_y_o = fill_tile_y_r;
    assign fill_row_ready_o = state_r == STATE_FILL_DATA;
    assign busy_o = state_r != STATE_IDLE;
    assign error_o = error_r;

    wire sample_fire_w = sample_valid_o && sample_ready_i;

    integer reset_i;
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            state_r <= STATE_IDLE;
            error_r <= 1'b0;
            tile_valid_r <= 4'b0;
            replace_r <= 2'b0;
            fill_entry_r <= 2'b0;
            fill_tile_x_r <= 12'b0;
            fill_tile_y_r <= 12'b0;
            src_x0_r <= 16'b0;
            src_y0_r <= 16'b0;
            frac_x_r <= 16'b0;
            frac_y_r <= 16'b0;
            in_bounds_r <= 1'b0;
            dst_x_r <= 16'b0;
            dst_y_r <= 16'b0;
            sof_r <= 1'b0;
            eol_r <= 1'b0;
            eof_r <= 1'b0;
            for (reset_i = 0; reset_i < 4; reset_i = reset_i + 1) begin
                tile_x_r[reset_i] <= 12'b0;
                tile_y_r[reset_i] <= 12'b0;
            end
        end else if (flush_i) begin
            state_r <= STATE_IDLE;
            tile_valid_r <= 4'b0;
            replace_r <= 2'b0;
            error_r <= 1'b0;
        end else begin
            case (state_r)
                STATE_IDLE: begin
                    if (coord_fire_w) begin
                        src_x0_r <= coord_src_x_i;
                        src_y0_r <= coord_src_y_i;
                        frac_x_r <= coord_frac_x_i;
                        frac_y_r <= coord_frac_y_i;
                        in_bounds_r <= coord_inside_crop_w;
                        dst_x_r <= coord_dst_x_i;
                        dst_y_r <= coord_dst_y_i;
                        sof_r <= coord_sof_i;
                        eol_r <= coord_eol_i;
                        eof_r <= coord_eof_i;
                        state_r <= coord_inside_crop_w ?
                            STATE_CHECK : STATE_OUTPUT;
                    end
                end

                STATE_CHECK: begin
                    if (all_hit_w) begin
                        state_r <= STATE_OUTPUT;
                    end else begin
                        fill_entry_r <= victim_w;
                        fill_tile_x_r <= missing_x_w;
                        fill_tile_y_r <= missing_y_w;
                        tile_valid_r[victim_w] <= 1'b0;
                        state_r <= STATE_FILL_REQ;
                    end
                end

                STATE_FILL_REQ: begin
                    if (fill_req_valid_o && fill_req_ready_i)
                        state_r <= STATE_FILL_DATA;
                end

                STATE_FILL_DATA: begin
                    if (fill_done_i) begin
                        tile_x_r[fill_entry_r] <= fill_tile_x_r;
                        tile_y_r[fill_entry_r] <= fill_tile_y_r;
                        tile_valid_r[fill_entry_r] <= 1'b1;
                        replace_r <= fill_entry_r + 1'b1;
                        if (fill_error_i)
                            error_r <= 1'b1;
                        state_r <= STATE_CHECK;
                    end
                end

                STATE_OUTPUT: begin
                    if (sample_fire_w) begin
                        if (coord_fire_w) begin
                            src_x0_r <= coord_src_x_i;
                            src_y0_r <= coord_src_y_i;
                            frac_x_r <= coord_frac_x_i;
                            frac_y_r <= coord_frac_y_i;
                            in_bounds_r <= coord_inside_crop_w;
                            dst_x_r <= coord_dst_x_i;
                            dst_y_r <= coord_dst_y_i;
                            sof_r <= coord_sof_i;
                            eol_r <= coord_eol_i;
                            eof_r <= coord_eof_i;
                            state_r <= coord_inside_crop_w ?
                                STATE_CHECK : STATE_OUTPUT;
                        end else begin
                            state_r <= STATE_IDLE;
                        end
                    end
                end

                default: begin
                    state_r <= STATE_IDLE;
                    error_r <= 1'b1;
                end
            endcase
        end
    end

endmodule
