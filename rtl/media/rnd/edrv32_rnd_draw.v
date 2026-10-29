// File: edrv32_rnd_draw.v
// Spec: rnd-spec 2.2, 2.3, 2.6 FILL/BORDER/GLYPH/BLIT/TILEMAP, 5.
// Description: Double-buffered chunk loading, two-lane source sampling and tagged writeback.
//              Source reads, shading and result streams overlap; the parent owns shared DMA.
// Clock domain: clk_mem (clk_i).
module edrv32_rnd_draw (
    // Clock and reset.
    input wire clk_i,
    input wire rst_n_i,

    // One drawing command; held constant through done.
    input wire start_i,
    input wire [511:0] command_i,
    input wire [31:0] source_stride_i,
    input wire cancel_i,
    output wire idle_o,
    output wire done_o,
    output wire [4:0] pixel_count_o,
    output wire read_wait_o,
    output wire write_wait_o,

    // Ordered row/segment read descriptors and their data responses.
    output wire rd_valid_o,
    input wire rd_ready_i,
    output wire [31:0] rd_addr_o,
    output wire [15:0] rd_bytes_o,
    input wire rd_done_i,
    input wire rd_data_valid_i,
    input wire [255:0] rd_data_i,

    // Result chunk stream, completed by the final DDR B response.
    output wire wr_valid_o,
    input wire wr_ready_i,
    output wire [31:0] wr_addr_o,
    output wire [15:0] wr_bytes_o,
    output wire wr_data_valid_o,
    input wire wr_data_ready_i,
    output wire [255:0] wr_data_o,
    output wire [31:0] wr_strb_o,
    input wire wr_done_i,

    // Shared two-pixel alpha datapath.
    output wire blend_valid_o,
    input wire blend_ready_i,
    output wire [63:0] blend_src_o,
    output wire [63:0] blend_dst_o,
    output wire [31:0] blend_tag_o,
    input wire [31:0] blend_tag_i,
    input wire blend_valid_i,
    input wire [63:0] blend_pixel_i
);
    // Each chunk owns disjoint target beats; loading, shading and writing overlap.
    localparam [4:0] S_IDLE = 5'd0;
    localparam [4:0] S_RADIUS = 5'd1;
    localparam [4:0] S_INNER = 5'd2;
    localparam [4:0] S_SIZE = 5'd3;
    localparam [4:0] S_ROW = 5'd4;
    localparam [4:0] S_EDGE_REQ = 5'd5;
    localparam [4:0] S_EDGE_WAIT = 5'd6;
    localparam [4:0] S_CHUNK = 5'd7;
    localparam [4:0] S_BOUNDS = 5'd8;
    localparam [4:0] S_TARGET_REQ = 5'd9;
    localparam [4:0] S_TARGET_DATA = 5'd10;
    localparam [4:0] S_SOURCE_REQ = 5'd11;
    localparam [4:0] S_SOURCE_DATA = 5'd12;
    localparam [4:0] S_TILE_MAP = 5'd13;
    localparam [4:0] S_MAP_REQ = 5'd14;
    localparam [4:0] S_MAP_DATA = 5'd15;
    localparam [4:0] S_TILE_ADDR = 5'd16;
    localparam [4:0] S_TILE_NEXT = 5'd17;
    localparam [4:0] S_LOADED = 5'd18;
    localparam [4:0] S_PALETTE_REQ = 5'd19;
    localparam [4:0] S_PALETTE_DATA = 5'd20;
    localparam [4:0] S_PALETTE_WRITE = 5'd21;
    localparam [1:0] S_RENDER_IDLE = 2'd0;
    localparam [1:0] S_RENDER_STREAM = 2'd1;
    localparam [1:0] S_WRITE_IDLE = 2'd0;
    localparam [1:0] S_WRITE_DESC = 2'd1;
    localparam [1:0] S_WRITE_DATA = 2'd2;
    localparam [1:0] S_WRITE_RESPONSE = 2'd3;

    reg active_r;
    reg done_r;
    reg [4:0] load_state_r;
    reg [1:0] render_state_r;
    reg [1:0] write_state_r;
    reg load_bank_r;
    reg render_bank_r;
    reg write_bank_r;
    reg [1:0] busy_r;
    reg [1:0] loaded_r;
    reg [1:0] rendered_r;
    reg loaded_all_r;
    reg [11:0] load_left_r;
    reg [11:0] load_right_r;
    reg [11:0] load_y_r;
    reg [8:0] load_beat_r;
    reg [31:0] load_source_base_r;
    reg [15:0] load_source_bytes_r;
    reg [7:0] tile_index_r;
    reg [11:0] tile_x_r;
    reg [15:0] tile_entry_r;
    reg [31:0] map_addr_r;
    reg [255:0] map_data_r;
    reg map_valid_r;
    reg [7:0] palette_index_r;
    reg [255:0] palette_buffer_r;
    reg read_busy_r;
    reg read_render_r;
    reg [31:0] miss_addr_r;
    reg [3:0] cache_valid_r;
    reg [31:0] cache_addr_r [0:3];
    reg [255:0] cache_data_r [0:3];
    reg [1:0] cache_replace_r;
    reg [11:0] bank_left_r [0:1];
    reg [11:0] bank_right_r [0:1];
    reg [11:0] bank_y_r [0:1];
    reg [31:0] bank_target_r [0:1];
    reg [15:0] bank_bytes_r [0:1];
    reg [31:0] bank_source_r [0:1];
    reg bank_sparse_r [0:1];
    reg [31:0] bank_tile_first_r [0:1];
    reg [15:0] bank_outer_edge_r [0:1];
    reg [15:0] bank_inner_edge_r [0:1];
    reg bank_inner_inside_r [0:1];
    reg [11:0] issue_x_r;
    reg [13:0] issue_byte_r;
    reg [4:0] bank_first_byte_r [0:1];
    reg [4:0] bank_last_byte_r [0:1];
    reg [8:0] write_beat_r;
    reg inner_r;
    reg [15:0] outer_edge_r;
    reg [15:0] inner_edge_r;
    reg inner_inside_r;
    reg [16:0] width_r;
    reg [16:0] height_r;
    reg signed [17:0] rect_left_r;
    reg signed [17:0] rect_top_r;
    reg signed [17:0] rect_right_r;
    reg signed [17:0] rect_bottom_r;
    reg [11:0] radius_r;
    reg [11:0] inner_radius_r;
    reg signed [17:0] inner_left_r;
    reg signed [17:0] inner_top_r;
    reg signed [17:0] inner_right_r;
    reg signed [17:0] inner_bottom_r;
    reg signed [17:0] inner_width_r;
    reg signed [17:0] inner_height_r;

    // Pipeline: coordinate/map+target, address, source RAM, palette, converted alpha input.
    reg [4:0] pipe_valid_r;
    reg [11:0] sample_x_r;
    reg [31:0] pipe_tag_r [0:4];
    reg [63:0] pipe_dst_r [1:4];
    reg [4:0] source_offset_r [1:2][0:1];
    reg [31:0] sample_addr_r [0:1];
    reg [8:0] source_index_r [0:1];
    reg [31:0] fill_pixel_r [0:1];
    reg [2:0] source_shift_r [1:3][0:1];
    reg [7:0] source_mask_r [1:3][0:1];
    reg [31:0] raw_r [0:1];
    reg [63:0] pipe_src_r;
    reg [23:0] fill_color_r [0:2][0:1];
    reg [7:0] fill_coverage_r [0:1][0:1];
    reg [7:0] fill_alpha_r [0:1];
    reg [7:0] fill_inner_r [0:1];
    reg [15:0] fill_product_r [0:1];
    reg [15:0] fill_opacity_r [0:1];
    reg [511:0] sparse_data_r [0:1];
    reg [255:0] lane_cache_low_w [0:1];
    reg [255:0] lane_cache_high_w [0:1];
    reg lane_low_hit_w [0:1];
    reg lane_high_hit_w [0:1];
    reg [1:0] cache_victim_w;
    reg cache_needed_w;
    integer cache_entry;
    integer cache_lane;

    wire [7:0] op_w;
    wire argb_w;
    wire [3:0] format_w;
    wire [15:0] flags_w;
    wire signed [17:0] left_w;
    wire signed [17:0] top_w;
    wire signed [17:0] right_w;
    wire signed [17:0] bottom_w;
    wire [16:0] width_w;
    wire [16:0] height_w;
    wire unused_decode_w;
    wire unused_empty_w;
    wire unused_fast_w;
    wire fill_w;
    wire tile_w;
    wire [2:0] bits_log2_w;
    wire [4:0] tile_log2_w;
    wire [31:0] tile_mask_w;
    wire [16:0] half_min_w;
    wire [11:0] radius_w;
    wire signed [17:0] border_w;
    wire signed [17:0] extension_w;
    wire signed [17:0] inner_left_w;
    wire signed [17:0] inner_top_w;
    wire signed [17:0] inner_right_w;
    wire signed [17:0] inner_bottom_w;
    wire signed [17:0] row_local_w;
    wire [17:0] row_width_w;
    wire [17:0] row_height_w;
    wire row_ready_w;
    wire edge_valid_w;
    wire [15:0] edge_w;
    wire [11:0] unused_radius_w;
    wire [15:0] outer_cov_w;
    wire [15:0] inner_cov_w;
    wire [31:0] load_dst_w;
    wire [31:0] load_src_w;
    wire [31:0] load_map_w;
    wire [31:0] load_sample_x_w;
    wire [31:0] load_sample_y_w;
    wire [31:0] load_adjusted_w;
    wire [31:0] end_dst_w;
    wire [31:0] end_src_w;
    wire [31:0] end_sample_y_w;
    wire [31:0] end_adjusted_w;
    wire [31:0] source_min_w;
    wire [31:0] source_max_w;
    wire [31:0] source_last_w;
    wire [31:0] palette_addr_w;
    wire [31:0] source_span_w;
    wire [31:0] tile_pixel_x_w;
    wire [31:0] tile_row_base_w;
    wire [31:0] tile_row_last_w;
    wire [31:0] tile_row_bytes_w;
    wire [12:0] chunk_right_w;
    wire [12:0] next_tile_x_w;
    wire [255:0] map_shift_w;
    wire map_hit_w;
    wire load_request_w;
    wire load_accept_w;
    wire load_data_w;
    wire load_done_w;
    wire [31:0] load_addr_w;
    wire [15:0] load_bytes_w;
    wire [7:0] palette_last_w;
    wire palette_write_w;
    wire [255:0] palette_shift_w;
    wire sample_bank_w;
    wire source_bank_w;
    wire palette_bank_w;
    wire render_start_w;
    wire render_finish_w;
    wire write_start_w;
    wire write_finish_w;
    wire [9:0] next_write_w;
    wire issue_pair_w;
    wire issue_last_w;
    wire issue_w;
    wire pipeline_step_w;
    wire source_ready_w;
    wire miss_request_w;
    wire [31:0] miss_query_w;
    wire [31:0] target_offset_w;
    wire [31:0] issue_offset_w;
    wire [255:0] target_data_w [0:1];
    wire [255:0] result_data_w [0:1];
    wire [255:0] target_shift_w;
    wire [255:0] result_write_data_w;
    wire [31:0] result_write_strb_w;
    wire [63:0] result_pixels_w;
    wire [31:0] lane_src_w [0:1];
    wire [31:0] lane_adjusted_w [0:1];
    wire [31:0] lane_sample_x_w [0:1];
    wire [31:0] lane_sample_y_w [0:1];
    wire [2:0] lane_shift_w [0:1];
    wire [7:0] lane_mask_w [0:1];
    wire [31:0] lane_tile_pixel_w [0:1];
    wire [31:0] lane_tile_base_w [0:1];
    wire [31:0] lane_source_index_w [0:1];
    wire [31:0] lane_tile_index_w [0:1];
    wire [31:0] issue_map_index_w [0:1];
    wire [31:0] map_entry_w [0:1][0:1];
    wire [255:0] source_data_w [0:1][0:1];
    wire [255:0] source_next_w [0:1][0:1];
    wire [511:0] raw_shift_w [0:1];
    wire [7:0] palette_index_w [0:1];
    wire [31:0] palette_data_w [0:1];
    wire [31:0] converted_w [0:1];
    wire lane_hit_w [0:1];
    wire [511:0] lane_cache_w [0:1];
    wire lane_cross_w [0:1];
    wire [31:0] lane_next_w [0:1];
    wire [31:0] gradient_k_w [0:1];
    wire [23:0] gradient_color_w [0:1];
    wire [7:0] gradient_alpha_w [0:1];
    wire unused_load_w;
    wire [31:0] target_bytes_w;
    wire [31:0] tile_bytes_w;
    wire [31:0] unused_end_w;
    wire [2:0] unused_load_shift_w;
    wire [7:0] unused_load_mask_w;
    wire [2:0] unused_end_shift_w;
    wire [7:0] unused_end_mask_w;
    wire [31:0] unused_end_sample_x_w;
    wire unused_geometry_w;
    integer stage;
    integer lane;
    function automatic [7:0] divide255;
        input [15:0] value_i;
        reg [15:0] biased;
        reg [15:0] rounded;
        reg [7:0] unused_low;
        begin
            biased = value_i + 16'd128;
            rounded = biased + (biased >> 8);
            divide255 = rounded[15:8];
            unused_low = rounded[7:0];
        end
    endfunction
    function automatic [7:0] gradient;
        input [7:0] channel_start_i;
        input [15:0] k_i;
        input signed [31:0] step_i;
        reg signed [48:0] value;
        begin
            value = $signed({1'd0, k_i}) * step_i +
                $signed({25'd0, channel_start_i, 16'd0}) + 49'sd32768;
            if (value < 0)
                gradient = 8'd0;
            else if (value >= 49'sd16777216)
                gradient = 8'd255;
            else
                gradient = value[23:16];
        end
    endfunction

    edrv32_rnd_decode u_decode (
        .command_i(command_i),
        .illegal_o(unused_decode_w),
        .empty_o(unused_empty_w),
        .op_o(op_w),
        .argb_o(argb_w),
        .src_fmt_o(format_w),
        .flags_o(flags_w),
        .left_o(left_w),
        .top_o(top_w),
        .right_o(right_w),
        .bottom_o(bottom_w),
        .width_o(width_w),
        .height_o(height_w),
        .fast_fill_o(unused_fast_w)
    );
    assign fill_w = op_w == 8'h01 || op_w == 8'h02;
    assign tile_w = op_w == 8'h08;
    assign bits_log2_w = format_w == 4'd0 ? 3'd4 : format_w == 4'd1 ? 3'd5 :
        format_w == 4'd2 || format_w == 4'd6 ? 3'd3 :
        format_w == 4'd3 || format_w == 4'd7 ? 3'd2 :
        format_w == 4'd4 || format_w == 4'd8 ? 3'd1 : 3'd0;
    assign tile_log2_w = flags_w[0] ? 5'd4 : 5'd3;
    assign tile_mask_w = flags_w[0] ? 32'd15 : 32'd7;
    assign half_min_w = (width_r < height_r ? width_r : height_r) >> 1;
    assign radius_w = {5'd0, command_i[267:256]} < half_min_w ?
        command_i[267:256] : half_min_w[11:0];
    assign border_w = $signed({6'd0, command_i[299:288]});
    assign extension_w = $signed({6'd0, radius_r}) + 18'sd1;
    assign inner_left_w = rect_left_r + (command_i[306] ? border_w : -extension_w);
    assign inner_top_w = rect_top_r + (command_i[304] ? border_w : -extension_w);
    assign inner_right_w = rect_right_r - (command_i[307] ? border_w : -extension_w);
    assign inner_bottom_w = rect_bottom_r - (command_i[305] ? border_w : -extension_w);
    assign row_local_w = $signed({6'd0, load_y_r}) - (inner_r ? inner_top_r : rect_top_r);
    assign row_width_w = inner_r ? inner_width_r : {1'd0, width_r};
    assign row_height_w = inner_r ? inner_height_r : {1'd0, height_r};
    edrv32_rnd_round_row u_round_row (
        .clk_i(clk_i),
        .rst_n_i(rst_n_i),
        .clear_i(cancel_i),
        .row_valid_i(load_state_r == S_EDGE_REQ),
        .row_ready_o(row_ready_w),
        .width_i(row_width_w[16:0]),
        .height_i(row_height_w[16:0]),
        .row_y_i(row_local_w[16:0]),
        .radius_i(inner_r ? inner_radius_r : radius_r),
        .edge_valid_o(edge_valid_w),
        .edge_ready_i(load_state_r == S_EDGE_WAIT || cancel_i),
        .edge_q4_o(edge_w),
        .radius_o(unused_radius_w)
    );
    edrv32_rnd_coverage u_outer_coverage (
        .x_i($signed({6'd0, issue_x_r}) - rect_left_r),
        .width_i(width_r),
        .edge_q4_i(bank_outer_edge_r[render_bank_r]),
        .row_inside_i(1'b1),
        .coverage_o(outer_cov_w)
    );
    edrv32_rnd_coverage u_inner_coverage (
        .x_i($signed({6'd0, issue_x_r}) - inner_left_r),
        .width_i(inner_width_r[16:0]),
        .edge_q4_i(bank_inner_edge_r[render_bank_r]),
        .row_inside_i(bank_inner_inside_r[render_bank_r]),
        .coverage_o(inner_cov_w)
    );
    edrv32_rnd_address u_load_address (
        .command_i(command_i),
        .x_i(tile_w ? tile_x_r : load_left_r),
        .y_i(load_y_r),
        .map_entry_i(tile_entry_r),
        .dst_addr_o(load_dst_w),
        .src_addr_o(load_src_w),
        .map_addr_o(load_map_w),
        .sub_shift_o(unused_load_shift_w),
        .sub_mask_o(unused_load_mask_w),
        .sample_x_o(load_sample_x_w),
        .sample_y_o(load_sample_y_w)
    );
    edrv32_rnd_address u_end_address (
        .command_i(command_i),
        .x_i(load_right_r),
        .y_i(load_y_r),
        .map_entry_i(16'd0),
        .dst_addr_o(end_dst_w),
        .src_addr_o(end_src_w),
        .map_addr_o(unused_end_w),
        .sub_shift_o(unused_end_shift_w),
        .sub_mask_o(unused_end_mask_w),
        .sample_x_o(unused_end_sample_x_w),
        .sample_y_o(end_sample_y_w)
    );
    assign load_adjusted_w = load_src_w + load_sample_y_w *
        (source_stride_i - {16'd0, command_i[303:288]});
    assign end_adjusted_w = end_src_w + end_sample_y_w *
        (source_stride_i - {16'd0, command_i[303:288]});
    assign target_bytes_w = {end_dst_w[31:5], 5'd0} -
        {load_dst_w[31:5], 5'd0} + 32'd32;
    assign tile_bytes_w = {tile_row_last_w[31:5], 5'd0} -
        {tile_row_base_w[31:5], 5'd0} + 32'd32;
    assign source_min_w = load_adjusted_w < end_adjusted_w ?
        load_adjusted_w : end_adjusted_w;
    assign source_max_w = load_adjusted_w > end_adjusted_w ?
        load_adjusted_w : end_adjusted_w;
    assign source_last_w = source_max_w + (format_w == 4'd1 ? 32'd3 :
        format_w == 4'd0 ? 32'd1 : 32'd0);
    assign source_span_w = {source_last_w[31:5], 5'd0} -
        {source_min_w[31:5], 5'd0} + 32'd32;
    assign tile_pixel_x_w = tile_entry_r[12] ?
        tile_mask_w - (load_sample_x_w & tile_mask_w) : load_sample_x_w & tile_mask_w;
    assign tile_row_base_w = load_src_w - ((tile_pixel_x_w << bits_log2_w) >> 3);
    assign tile_row_bytes_w = ((tile_mask_w + 32'd1) << bits_log2_w) >> 3;
    assign tile_row_last_w = tile_row_base_w + tile_row_bytes_w - 32'd1;
    // End chunks on a target beat so concurrent banks never own the same bytes.
    assign chunk_right_w = {1'b0, load_left_r} + 13'd511 -
        (argb_w ? {10'd0, load_dst_w[4:2]} : {9'd0, load_dst_w[4:1]});
    assign next_tile_x_w = {1'b0, tile_x_r} +
        (flags_w[0] ? 13'd16 : 13'd8) - {9'd0, load_sample_x_w[3:0] & tile_mask_w[3:0]};
    assign map_hit_w = map_valid_r && map_addr_r == {load_map_w[31:5], 5'd0};
    assign map_shift_w = map_data_r >> {load_map_w[4:0], 3'd0};
    assign palette_last_w = format_w == 4'd6 ? 8'd255 : format_w == 4'd7 ? 8'd15 :
        format_w == 4'd8 ? 8'd3 : 8'd1;
    assign palette_addr_w = command_i[447:416] + {22'd0, palette_index_r, 2'd0};
    assign palette_shift_w = palette_buffer_r >> {palette_addr_w[4:0], 3'd0};
    assign palette_write_w = load_state_r == S_PALETTE_WRITE && !cancel_i;
    assign load_request_w = load_state_r == S_TARGET_REQ || load_state_r == S_SOURCE_REQ ||
        load_state_r == S_MAP_REQ || load_state_r == S_PALETTE_REQ;
    assign load_addr_w = load_state_r == S_TARGET_REQ ? bank_target_r[load_bank_r] :
        load_state_r == S_MAP_REQ ? {load_map_w[31:5], 5'd0} :
        load_state_r == S_PALETTE_REQ ? {palette_addr_w[31:5], 5'd0} : load_source_base_r;
    assign load_bytes_w = load_state_r == S_TARGET_REQ ? bank_bytes_r[load_bank_r] :
        load_state_r == S_SOURCE_REQ ? load_source_bytes_r : 16'd32;
    assign rd_valid_o = !cancel_i && !read_busy_r && (miss_request_w || load_request_w);
    assign rd_addr_o = miss_request_w ? miss_query_w : load_addr_w;
    assign rd_bytes_o = miss_request_w ? 16'd32 : load_bytes_w;
    assign load_accept_w = rd_valid_o && rd_ready_i && !miss_request_w;
    assign load_data_w = rd_data_valid_i && read_busy_r && !read_render_r;
    assign load_done_w = rd_done_i && read_busy_r && !read_render_r;

    assign sample_bank_w = pipe_tag_r[0][31];
    assign source_bank_w = pipe_tag_r[1][31];
    assign palette_bank_w = pipe_tag_r[2][31];
    assign render_start_w = active_r && render_state_r == S_RENDER_IDLE &&
        loaded_r[render_bank_r];
    assign render_finish_w = blend_valid_i && blend_tag_i[30];
    assign write_start_w = active_r && write_state_r == S_WRITE_IDLE &&
        rendered_r[write_bank_r];
    assign write_finish_w = write_state_r == S_WRITE_RESPONSE && wr_done_i;
    assign next_write_w = {1'b0, write_beat_r} + 10'd1;
    assign issue_pair_w = issue_x_r < bank_right_r[render_bank_r] &&
        issue_offset_w[4:0] <= (argb_w ? 5'd24 : 5'd28);
    assign issue_last_w = {1'b0, issue_x_r} + (issue_pair_w ? 13'd1 : 13'd0) >=
        {1'b0, bank_right_r[render_bank_r]};
    assign issue_offset_w = {18'd0, issue_byte_r};
    assign target_offset_w = {18'd0, pipe_tag_r[0][13:0]};
    assign target_shift_w = target_data_w[sample_bank_w] >> {target_offset_w[4:0], 3'd0};
    assign source_ready_w = !pipe_valid_r[1] || fill_w || !bank_sparse_r[source_bank_w] ||
        (lane_hit_w[0] && (!pipe_tag_r[1][29] || lane_hit_w[1]));
    assign pipeline_step_w = (!pipe_valid_r[4] || blend_ready_i) && source_ready_w;
    assign issue_w = render_state_r == S_RENDER_STREAM && pipeline_step_w;
    assign miss_request_w = pipe_valid_r[1] && !source_ready_w;
    assign miss_query_w = !lane_low_hit_w[0] ? {sample_addr_r[0][31:5], 5'd0} :
        lane_cross_w[0] && !lane_high_hit_w[0] ? lane_next_w[0] :
        !lane_low_hit_w[1] ? {sample_addr_r[1][31:5], 5'd0} : lane_next_w[1];
    assign blend_valid_o = pipe_valid_r[4] && source_ready_w;
    assign blend_src_o = pipe_src_r;
    assign blend_dst_o = pipe_dst_r[4];
    assign blend_tag_o = pipe_tag_r[4];
    assign result_pixels_w = argb_w ? blend_pixel_i :
        {32'd0, blend_pixel_i[47:32], blend_pixel_i[15:0]};
    assign result_write_data_w = {192'd0, result_pixels_w} << {blend_tag_i[4:0], 3'd0};
    assign result_write_strb_w = (argb_w ? (blend_tag_i[29] ? 32'hff : 32'hf) :
        (blend_tag_i[29] ? 32'hf : 32'h3)) << blend_tag_i[4:0];
    assign wr_valid_o = write_state_r == S_WRITE_DESC && !cancel_i;
    assign wr_addr_o = bank_target_r[write_bank_r];
    assign wr_bytes_o = bank_bytes_r[write_bank_r];
    assign wr_data_valid_o = write_state_r == S_WRITE_DATA && !cancel_i;
    assign wr_data_o = result_data_w[write_bank_r];
    // Original target bytes are preserved in the result RAM outside the drawing region.
    assign wr_strb_o = (write_beat_r == 9'd0 ?
        32'hffff_ffff << bank_first_byte_r[write_bank_r] : 32'hffff_ffff) &
        ({2'd0, next_write_w, 5'd0} == {1'b0, bank_bytes_r[write_bank_r]} ?
            32'hffff_ffff >> (5'd31 - bank_last_byte_r[write_bank_r]) : 32'hffff_ffff);
    assign idle_o = !active_r;
    assign done_o = done_r;
    assign pixel_count_o = blend_valid_i ? (blend_tag_i[29] ? 5'd2 : 5'd1) : 5'd0;
    assign read_wait_o = active_r && ((render_state_r == S_RENDER_IDLE &&
        !loaded_r[render_bank_r]) || miss_request_w);
    assign write_wait_o = active_r && busy_r[load_bank_r] &&
        write_state_r != S_WRITE_IDLE;

    genvar pixel;
    generate for (pixel = 0; pixel < 2; pixel = pixel + 1) begin : g_pixel
        localparam [11:0] PIXEL = pixel;
        wire [31:0] unused_dst_w;
        wire [31:0] unused_map_w;
        wire [7:0] unused_source_index_w;
        wire [11:0] coordinate_w;
        wire [31:0] issue_map_x_w;
        assign coordinate_w = sample_x_r + PIXEL;
        edrv32_rnd_address u_address (
            .command_i(command_i),
            .x_i(coordinate_w),
            .y_i(bank_y_r[sample_bank_w]),
            .map_entry_i(map_entry_w[sample_bank_w][pixel][15:0]),
            .dst_addr_o(unused_dst_w),
            .src_addr_o(lane_src_w[pixel]),
            .map_addr_o(unused_map_w),
            .sub_shift_o(lane_shift_w[pixel]),
            .sub_mask_o(lane_mask_w[pixel]),
            .sample_x_o(lane_sample_x_w[pixel]),
            .sample_y_o(lane_sample_y_w[pixel])
        );
        assign lane_adjusted_w[pixel] = lane_src_w[pixel] + lane_sample_y_w[pixel] *
            (source_stride_i - {16'd0, command_i[303:288]});
        assign lane_tile_pixel_w[pixel] = map_entry_w[sample_bank_w][pixel][12] ?
            tile_mask_w - (lane_sample_x_w[pixel] & tile_mask_w) :
            lane_sample_x_w[pixel] & tile_mask_w;
        assign lane_tile_base_w[pixel] = lane_src_w[pixel] -
            ((lane_tile_pixel_w[pixel] << bits_log2_w) >> 3);
        assign lane_tile_index_w[pixel] = (lane_sample_x_w[pixel] >> tile_log2_w) -
            bank_tile_first_r[sample_bank_w];
        assign lane_source_index_w[pixel] = tile_w ? lane_tile_index_w[pixel] * 32'd3 +
            (({lane_src_w[pixel][31:5], 5'd0} -
                {lane_tile_base_w[pixel][31:5], 5'd0}) >> 5) :
            (lane_adjusted_w[pixel] - bank_source_r[sample_bank_w]) >> 5;
        assign issue_map_x_w = {16'd0, command_i[367:352]} +
            {20'd0, issue_x_r} + pixel - {{16{command_i[175]}}, command_i[175:160]};
        assign issue_map_index_w[pixel] = (issue_map_x_w >> tile_log2_w) -
            bank_tile_first_r[render_bank_r];
        assign lane_cross_w[pixel] = format_w == 4'd1 ? sample_addr_r[pixel][4:0] > 5'd28 :
            format_w == 4'd0 && sample_addr_r[pixel][4:0] == 5'd31;
        assign lane_next_w[pixel] = {sample_addr_r[pixel][31:5], 5'd0} + 32'd32;
        assign lane_hit_w[pixel] = lane_low_hit_w[pixel] &&
            (!lane_cross_w[pixel] || lane_high_hit_w[pixel]);
        assign lane_cache_w[pixel] = {lane_cache_high_w[pixel], lane_cache_low_w[pixel]};
        assign raw_shift_w[pixel] = (bank_sparse_r[palette_bank_w] ? sparse_data_r[pixel] :
            {source_next_w[palette_bank_w][pixel], source_data_w[palette_bank_w][pixel]}) >>
                {source_offset_r[2][pixel], 3'd0};
        assign palette_index_w[pixel] =
            (raw_shift_w[pixel][7:0] >> source_shift_r[2][pixel]) & source_mask_r[2][pixel];
        edrv32_ram_rnd_palette u_palette (
            .clk_i(clk_i),
            .wr_en_i(palette_write_w),
            .wr_addr_i(palette_index_r),
            .wr_data_i(palette_shift_w[31:0]),
            .rd_en_i(pipe_valid_r[2] && pipeline_step_w && !cancel_i),
            .rd_addr_i(palette_index_w[pixel]),
            .rd_data_o(palette_data_w[pixel])
        );
        edrv32_rnd_source u_source (
            .format_i(format_w),
            .glyph_i(op_w == 8'h03),
            .raw_i(raw_r[pixel]),
            .sub_shift_i(source_shift_r[3][pixel]),
            .sub_mask_i(source_mask_r[3][pixel]),
            .palette_i(palette_data_w[pixel]),
            .color_i(command_i[247:224]),
            .opacity_i(command_i[255:248]),
            .colorkey_i(flags_w[2]),
            .key_i(command_i[463:448]),
            .recolor_i(op_w == 8'h04 && flags_w[3]),
            .recolor_value_i(command_i[511:480]),
            .index_o(unused_source_index_w),
            .pixel_o(converted_w[pixel])
        );
        assign gradient_k_w[pixel] = flags_w[1] ? {20'd0, bank_y_r[render_bank_r]} -
            {{16{command_i[191]}}, command_i[191:176]} : {20'd0, issue_x_r} + pixel -
            {{16{command_i[175]}}, command_i[175:160]};
        assign gradient_alpha_w[pixel] = flags_w[0] ?
            gradient(command_i[319:312], gradient_k_w[pixel][15:0], command_i[351:320]) :
            8'd255;
        assign gradient_color_w[pixel] = {
            gradient(command_i[311:304], gradient_k_w[pixel][15:0], command_i[383:352]),
            gradient(command_i[303:296], gradient_k_w[pixel][15:0], command_i[415:384]),
            gradient(command_i[295:288], gradient_k_w[pixel][15:0], command_i[447:416])};
    end endgenerate
    always @(*) begin
        cache_victim_w = 2'd0;
        cache_needed_w = 1'b0;
        for (cache_lane = 0; cache_lane < 2; cache_lane = cache_lane + 1) begin
            lane_cache_low_w[cache_lane] = 256'd0;
            lane_cache_high_w[cache_lane] = 256'd0;
            lane_low_hit_w[cache_lane] = 1'b0;
            lane_high_hit_w[cache_lane] = 1'b0;
        end
        for (cache_entry = 0; cache_entry < 4; cache_entry = cache_entry + 1) begin
            cache_needed_w = 1'b0;
            for (cache_lane = 0; cache_lane < 2; cache_lane = cache_lane + 1) begin
                if (cache_valid_r[cache_entry] && cache_addr_r[cache_entry] ==
                    {sample_addr_r[cache_lane][31:5], 5'd0}) begin
                    lane_low_hit_w[cache_lane] = 1'b1;
                    lane_cache_low_w[cache_lane] = cache_data_r[cache_entry];
                    if (cache_lane == 0 || pipe_tag_r[1][29])
                        cache_needed_w = 1'b1;
                end
                if (cache_valid_r[cache_entry] &&
                    cache_addr_r[cache_entry] == lane_next_w[cache_lane]) begin
                    lane_high_hit_w[cache_lane] = 1'b1;
                    lane_cache_high_w[cache_lane] = cache_data_r[cache_entry];
                    if (lane_cross_w[cache_lane] && (cache_lane == 0 || pipe_tag_r[1][29]))
                        cache_needed_w = 1'b1;
                end
            end
            if (!cache_needed_w)
                cache_victim_w = cache_entry[1:0];
        end
    end

    genvar bank;
    generate for (bank = 0; bank < 2; bank = bank + 1) begin : g_bank
        wire target_load_w;
        wire source_load_w;
        wire render_read_w;
        wire result_write_w;
        wire write_read_w;
        wire [8:0] source_write_addr_w;
        assign target_load_w = load_data_w && load_state_r == S_TARGET_DATA &&
            load_bank_r == bank && !cancel_i;
        assign source_load_w = load_data_w && load_state_r == S_SOURCE_DATA &&
            load_bank_r == bank && !cancel_i;
        assign source_write_addr_w = tile_w ?
            ({1'b0, tile_index_r} + ({1'b0, tile_index_r} << 1)) + load_beat_r : load_beat_r;
        assign render_read_w = render_bank_r == bank && issue_w && !cancel_i;
        assign result_write_w = blend_valid_i && blend_tag_i[31] == bank && !cancel_i;
        assign write_read_w = write_bank_r == bank && !cancel_i &&
            ((write_state_r == S_WRITE_DESC && wr_ready_i) ||
            (write_state_r == S_WRITE_DATA && wr_data_ready_i &&
                {2'd0, next_write_w, 5'd0} < {1'b0, bank_bytes_r[bank]}));
        // Keep the immutable target snapshot separate from byte-enabled result writes.
        // This also avoids undefined read/write collisions when sparse sampling stalls.
        edrv32_ram_rnd_line u_target (
            .clk_i(clk_i),
            .wr_en_i(target_load_w),
            .wr_addr_i(load_beat_r),
            .wr_data_i(rd_data_i),
            .wr_strb_i(32'hffff_ffff),
            .rd_en_i(render_read_w),
            .rd_addr_i(issue_offset_w[13:5]),
            .rd_data_o(target_data_w[bank])
        );
        edrv32_ram_rnd_line u_result (
            .clk_i(clk_i),
            .wr_en_i(target_load_w || result_write_w),
            .wr_addr_i(result_write_w ? blend_tag_i[13:5] : load_beat_r),
            .wr_data_i(result_write_w ? result_write_data_w : rd_data_i),
            .wr_strb_i(result_write_w ? result_write_strb_w : 32'hffff_ffff),
            .rd_en_i(write_read_w),
            .rd_addr_i(write_state_r == S_WRITE_DESC ? 9'd0 : next_write_w[8:0]),
            .rd_data_o(result_data_w[bank])
        );
        for (pixel = 0; pixel < 2; pixel = pixel + 1) begin : g_sample
            edrv32_ram_rnd_line u_source (
                .clk_i(clk_i),
                .wr_en_i(source_load_w),
                .wr_addr_i(source_write_addr_w),
                .wr_data_i(rd_data_i),
                .wr_strb_i(32'hffff_ffff),
                .rd_en_i(source_bank_w == bank && pipe_valid_r[1] &&
                    pipeline_step_w && !cancel_i),
                .rd_addr_i(source_index_r[pixel]),
                .rd_data_o(source_data_w[bank][pixel])
            );
            edrv32_ram_rnd_line u_source_next (
                .clk_i(clk_i),
                .wr_en_i(source_load_w),
                .wr_addr_i(source_write_addr_w),
                .wr_data_i(rd_data_i),
                .wr_strb_i(32'hffff_ffff),
                .rd_en_i(source_bank_w == bank && pipe_valid_r[1] &&
                    pipeline_step_w && !cancel_i),
                .rd_addr_i(source_index_r[pixel] + 9'd1),
                .rd_data_o(source_next_w[bank][pixel])
            );
            edrv32_ram_rnd_palette u_map (
                .clk_i(clk_i),
                .wr_en_i(load_bank_r == bank && load_state_r == S_TILE_ADDR && !cancel_i),
                .wr_addr_i(tile_index_r),
                .wr_data_i({16'd0, tile_entry_r}),
                .rd_en_i(render_read_w),
                .rd_addr_i(issue_map_index_w[pixel][7:0]),
                .rd_data_o(map_entry_w[bank][pixel])
            );
        end
    end endgenerate

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            active_r <= 1'b0;
            done_r <= 1'b0;
            busy_r <= 2'd0;
            loaded_r <= 2'd0;
            rendered_r <= 2'd0;
        end else if (cancel_i || start_i) begin
            active_r <= start_i && !cancel_i;
            done_r <= 1'b0;
            busy_r <= 2'd0;
            loaded_r <= 2'd0;
            rendered_r <= 2'd0;
        end else begin
            done_r <= 1'b0;
            if (load_state_r == S_CHUNK && !busy_r[load_bank_r])
                busy_r[load_bank_r] <= 1'b1;
            if (load_state_r == S_LOADED)
                loaded_r[load_bank_r] <= 1'b1;
            if (render_start_w)
                loaded_r[render_bank_r] <= 1'b0;
            if (render_finish_w)
                rendered_r[blend_tag_i[31]] <= 1'b1;
            if (write_start_w)
                rendered_r[write_bank_r] <= 1'b0;
            if (write_finish_w) begin
                busy_r[write_bank_r] <= 1'b0;
                if (bank_y_r[write_bank_r] == bottom_w[11:0] &&
                    bank_right_r[write_bank_r] == right_w[11:0]) begin
                    active_r <= 1'b0;
                    done_r <= 1'b1;
                end
            end
        end
    end
    // Descriptor ownership follows the DMA completion, independent of rendering.
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            read_busy_r <= 1'b0;
            read_render_r <= 1'b0;
            cache_valid_r <= 4'd0;
            cache_replace_r <= 2'd0;
        end else if (cancel_i || start_i) begin
            read_busy_r <= 1'b0;
            cache_valid_r <= 4'd0;
        end else begin
            if (rd_valid_o && rd_ready_i) begin
                read_busy_r <= 1'b1;
                read_render_r <= miss_request_w;
                if (miss_request_w) begin
                    cache_replace_r <= cache_victim_w;
                end
            end
            if (rd_done_i)
                read_busy_r <= 1'b0;
            if (read_busy_r && read_render_r && rd_data_valid_i)
                cache_valid_r[cache_replace_r] <= 1'b1;
        end
    end
    always @(posedge clk_i) begin
        if (rd_valid_o && rd_ready_i && miss_request_w)
            miss_addr_r <= miss_query_w;
        if (read_busy_r && read_render_r && rd_data_valid_i) begin
            cache_addr_r[cache_replace_r] <= miss_addr_r;
            cache_data_r[cache_replace_r] <= rd_data_i;
        end
    end
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            load_state_r <= S_IDLE;
            load_bank_r <= 1'b0;
            load_left_r <= 12'd0;
            load_right_r <= 12'd0;
            load_y_r <= 12'd0;
            load_beat_r <= 9'd0;
            loaded_all_r <= 1'b0;
            tile_index_r <= 8'd0;
            tile_x_r <= 12'd0;
            map_valid_r <= 1'b0;
            palette_index_r <= 8'd0;
            inner_r <= 1'b0;
            inner_inside_r <= 1'b0;
        end else if (cancel_i || start_i) begin
            load_state_r <= cancel_i ? S_IDLE :
                ((op_w == 8'h04 || tile_w) && format_w >= 4'd6 ? S_PALETTE_REQ : S_RADIUS);
            load_bank_r <= 1'b0;
            load_left_r <= left_w[11:0];
            load_y_r <= top_w[11:0];
            tile_x_r <= left_w[11:0];
            loaded_all_r <= 1'b0;
            map_valid_r <= 1'b0;
            palette_index_r <= 8'd0;
        end else begin
            if (load_data_w)
                load_beat_r <= load_beat_r + 9'd1;
            case (load_state_r)
                S_RADIUS: load_state_r <= S_INNER;
                S_INNER: load_state_r <= S_SIZE;
                S_SIZE: load_state_r <= S_ROW;
                S_ROW: begin
                    inner_r <= 1'b0;
                    inner_inside_r <= 1'b0;
                    load_state_r <= fill_w ? S_EDGE_REQ : S_CHUNK;
                end
                S_EDGE_REQ: if (row_ready_w)
                    load_state_r <= S_EDGE_WAIT;
                S_EDGE_WAIT: if (edge_valid_w) begin
                    if (!inner_r && op_w == 8'h02 && inner_width_r > 0 &&
                        inner_height_r > 0 && $signed({6'd0, load_y_r}) >= inner_top_r &&
                        $signed({6'd0, load_y_r}) <= inner_bottom_r) begin
                        inner_r <= 1'b1;
                        inner_inside_r <= 1'b1;
                        load_state_r <= S_EDGE_REQ;
                    end else
                        load_state_r <= S_CHUNK;
                end
                S_CHUNK: if (!busy_r[load_bank_r] && !loaded_all_r) begin
                    load_right_r <= chunk_right_w < {1'b0, right_w[11:0]} ?
                        chunk_right_w[11:0] : right_w[11:0];
                    tile_x_r <= load_left_r;
                    tile_index_r <= 8'd0;
                    load_state_r <= S_BOUNDS;
                end
                S_BOUNDS: load_state_r <= S_TARGET_REQ;
                S_TARGET_REQ: if (load_accept_w) begin
                    load_beat_r <= 9'd0;
                    load_state_r <= S_TARGET_DATA;
                end
                S_TARGET_DATA: if (load_done_w)
                    load_state_r <= fill_w || bank_sparse_r[load_bank_r] ? S_LOADED :
                        tile_w ? S_TILE_MAP : S_SOURCE_REQ;
                S_SOURCE_REQ: if (load_accept_w) begin
                    load_beat_r <= 9'd0;
                    load_state_r <= S_SOURCE_DATA;
                end
                S_SOURCE_DATA: if (load_done_w)
                    load_state_r <= tile_w ? S_TILE_NEXT : S_LOADED;
                S_TILE_MAP: if (map_hit_w)
                    load_state_r <= S_TILE_ADDR;
                else
                    load_state_r <= S_MAP_REQ;
                S_MAP_REQ: if (load_accept_w)
                    load_state_r <= S_MAP_DATA;
                S_MAP_DATA: if (load_done_w) begin
                    map_valid_r <= 1'b1;
                    load_state_r <= S_TILE_MAP;
                end
                S_TILE_ADDR: load_state_r <= S_SOURCE_REQ;
                S_TILE_NEXT: if (next_tile_x_w > {1'b0, load_right_r})
                    load_state_r <= S_LOADED;
                else begin
                    tile_x_r <= next_tile_x_w[11:0];
                    tile_index_r <= tile_index_r + 8'd1;
                    load_state_r <= S_TILE_MAP;
                end
                S_LOADED: begin
                    load_bank_r <= !load_bank_r;
                    if (load_right_r == right_w[11:0]) begin
                        if (load_y_r == bottom_w[11:0]) begin
                            loaded_all_r <= 1'b1;
                            load_state_r <= S_IDLE;
                        end else begin
                            load_left_r <= left_w[11:0];
                            tile_x_r <= left_w[11:0];
                            load_y_r <= load_y_r + 12'd1;
                            load_state_r <= S_ROW;
                        end
                    end else begin
                        load_left_r <= load_right_r + 12'd1;
                        tile_x_r <= load_right_r + 12'd1;
                        load_state_r <= S_CHUNK;
                    end
                end
                S_PALETTE_REQ: if (load_accept_w)
                    load_state_r <= S_PALETTE_DATA;
                S_PALETTE_DATA: if (load_done_w)
                    load_state_r <= S_PALETTE_WRITE;
                S_PALETTE_WRITE: begin
                    palette_index_r <= palette_index_r + 8'd1;
                    if (palette_index_r == palette_last_w)
                        load_state_r <= S_RADIUS;
                    else if (palette_addr_w[4:0] == 5'd28)
                        load_state_r <= S_PALETTE_REQ;
                end
                default: load_state_r <= load_state_r;
            endcase
        end
    end
    always @(posedge clk_i) begin
        if (start_i) begin
            width_r <= width_w;
            height_r <= height_w;
            rect_left_r <= {{2{command_i[175]}}, command_i[175:160]};
            rect_top_r <= {{2{command_i[191]}}, command_i[191:176]};
            rect_right_r <= {{2{command_i[207]}}, command_i[207:192]};
            rect_bottom_r <= {{2{command_i[223]}}, command_i[223:208]};
        end
        if (load_state_r == S_RADIUS)
            radius_r <= radius_w;
        if (load_state_r == S_INNER) begin
            inner_left_r <= inner_left_w;
            inner_top_r <= inner_top_w;
            inner_right_r <= inner_right_w;
            inner_bottom_r <= inner_bottom_w;
            inner_radius_r <= radius_r > command_i[299:288] ?
                radius_r - command_i[299:288] : 12'd0;
        end
        if (load_state_r == S_SIZE) begin
            inner_width_r <= inner_right_r - inner_left_r + 18'sd1;
            inner_height_r <= inner_bottom_r - inner_top_r + 18'sd1;
        end
        if (load_state_r == S_EDGE_WAIT && edge_valid_w) begin
            if (inner_r)
                inner_edge_r <= edge_w;
            else
                outer_edge_r <= edge_w;
        end
        if (load_state_r == S_BOUNDS) begin
            bank_left_r[load_bank_r] <= load_left_r;
            bank_right_r[load_bank_r] <= load_right_r;
            bank_y_r[load_bank_r] <= load_y_r;
            bank_target_r[load_bank_r] <= {load_dst_w[31:5], 5'd0};
            bank_bytes_r[load_bank_r] <= target_bytes_w[15:0];
            bank_first_byte_r[load_bank_r] <= load_dst_w[4:0];
            bank_last_byte_r[load_bank_r] <= end_dst_w[4:0] + (argb_w ? 5'd3 : 5'd1);
            bank_source_r[load_bank_r] <= {source_min_w[31:5], 5'd0};
            bank_sparse_r[load_bank_r] <= !tile_w && !fill_w && source_span_w > 32'd16384;
            bank_tile_first_r[load_bank_r] <= load_sample_x_w >> tile_log2_w;
            bank_outer_edge_r[load_bank_r] <= outer_edge_r;
            bank_inner_edge_r[load_bank_r] <= inner_edge_r;
            bank_inner_inside_r[load_bank_r] <= inner_inside_r;
            load_source_base_r <= {source_min_w[31:5], 5'd0};
            load_source_bytes_r <= source_span_w[15:0];
        end
        if (load_state_r == S_TILE_MAP && map_hit_w)
            tile_entry_r <= map_shift_w[15:0];
        if (load_state_r == S_TILE_ADDR) begin
            load_source_base_r <= {tile_row_base_w[31:5], 5'd0};
            load_source_bytes_r <= tile_bytes_w[15:0];
        end
        if (load_accept_w && load_state_r == S_MAP_REQ)
            map_addr_r <= {load_map_w[31:5], 5'd0};
        if (load_data_w && load_state_r == S_MAP_DATA)
            map_data_r <= rd_data_i;
        if (load_data_w && load_state_r == S_PALETTE_DATA)
            palette_buffer_r <= rd_data_i;
    end
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            render_state_r <= S_RENDER_IDLE;
            render_bank_r <= 1'b0;
            issue_x_r <= 12'd0;
            issue_byte_r <= 14'd0;
            pipe_valid_r <= 5'd0;
        end else if (cancel_i || start_i) begin
            render_state_r <= S_RENDER_IDLE;
            render_bank_r <= 1'b0;
            pipe_valid_r <= 5'd0;
        end else begin
            if (pipeline_step_w)
                pipe_valid_r <= {pipe_valid_r[3:0], issue_w};
            case (render_state_r)
                S_RENDER_IDLE: if (render_start_w) begin
                    issue_x_r <= bank_left_r[render_bank_r];
                    issue_byte_r <= {9'd0, bank_first_byte_r[render_bank_r]};
                    render_state_r <= S_RENDER_STREAM;
                end
                S_RENDER_STREAM: if (issue_w) begin
                    issue_x_r <= issue_x_r + (issue_pair_w ? 12'd2 : 12'd1);
                    issue_byte_r <= issue_byte_r + (argb_w ?
                        (issue_pair_w ? 14'd8 : 14'd4) : (issue_pair_w ? 14'd4 : 14'd2));
                    if (issue_last_w) begin
                        render_state_r <= S_RENDER_IDLE;
                        render_bank_r <= !render_bank_r;
                    end
                end
                default: render_state_r <= render_state_r;
            endcase
        end
    end
    always @(posedge clk_i) begin
        if (pipeline_step_w) begin
            if (issue_w) begin
                sample_x_r <= issue_x_r;
                pipe_tag_r[0] <= {render_bank_r, issue_last_w, issue_pair_w,
                    15'd0, issue_offset_w[13:0]};
            end
            for (stage = 1; stage < 5; stage = stage + 1)
                if (pipe_valid_r[stage-1])
                    pipe_tag_r[stage] <= pipe_tag_r[stage-1];
            if (pipe_valid_r[0])
                pipe_dst_r[1] <= argb_w ? target_shift_w[63:0] :
                    {16'd0, target_shift_w[31:16], 16'd0, target_shift_w[15:0]};
            if (pipe_valid_r[1])
                pipe_dst_r[2] <= pipe_dst_r[1];
            if (pipe_valid_r[2])
                pipe_dst_r[3] <= pipe_dst_r[2];
            if (pipe_valid_r[3])
                pipe_dst_r[4] <= pipe_dst_r[3];
            for (lane = 0; lane < 2; lane = lane + 1) begin
                if (issue_w) begin
                    fill_color_r[0][lane] <= op_w == 8'h01 && flags_w[0] ?
                        gradient_color_w[lane] : command_i[247:224];
                    fill_alpha_r[lane] <= gradient_alpha_w[lane];
                    fill_coverage_r[0][lane] <= outer_cov_w[lane*8 +: 8];
                    fill_inner_r[lane] <= 8'd255 - inner_cov_w[lane*8 +: 8];
                end
                if (pipe_valid_r[0]) begin
                    sample_addr_r[lane] <= lane_adjusted_w[lane];
                    source_index_r[lane] <= lane_source_index_w[lane][8:0];
                    source_offset_r[1][lane] <= lane_adjusted_w[lane][4:0];
                    source_shift_r[1][lane] <= lane_shift_w[lane];
                    source_mask_r[1][lane] <= lane_mask_w[lane];
                    fill_color_r[1][lane] <= fill_color_r[0][lane];
                    fill_coverage_r[1][lane] <= fill_coverage_r[0][lane];
                    fill_product_r[lane] <= op_w == 8'h01 ?
                        command_i[255:248] * fill_alpha_r[lane] :
                        fill_coverage_r[0][lane] * fill_inner_r[lane];
                end
                if (pipe_valid_r[1]) begin
                    sparse_data_r[lane] <= lane_cache_w[lane];
                    source_offset_r[2][lane] <= source_offset_r[1][lane];
                    source_shift_r[2][lane] <= source_shift_r[1][lane];
                    source_mask_r[2][lane] <= source_mask_r[1][lane];
                    fill_color_r[2][lane] <= fill_color_r[1][lane];
                    fill_opacity_r[lane] <= divide255(fill_product_r[lane]) *
                        (op_w == 8'h01 ? {8'd0, fill_coverage_r[1][lane]} :
                            {8'd0, command_i[255:248]});
                end
                if (pipe_valid_r[2]) begin
                    raw_r[lane] <= raw_shift_w[lane][31:0];
                    source_shift_r[3][lane] <= source_shift_r[2][lane];
                    source_mask_r[3][lane] <= source_mask_r[2][lane];
                    fill_pixel_r[lane] <=
                        {divide255(fill_opacity_r[lane]), fill_color_r[2][lane]};
                end
                if (pipe_valid_r[3])
                    pipe_src_r[lane*32 +: 32] <= fill_w ? fill_pixel_r[lane] : converted_w[lane];
            end
        end
    end
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            write_state_r <= S_WRITE_IDLE;
            write_bank_r <= 1'b0;
            write_beat_r <= 9'd0;
        end else if (cancel_i || start_i) begin
            write_state_r <= S_WRITE_IDLE;
            write_bank_r <= 1'b0;
        end else begin
            case (write_state_r)
                S_WRITE_IDLE: if (write_start_w)
                    write_state_r <= S_WRITE_DESC;
                S_WRITE_DESC: if (wr_ready_i) begin
                    write_state_r <= S_WRITE_DATA;
                    write_beat_r <= 9'd0;
                end
                S_WRITE_DATA: if (wr_data_ready_i) begin
                    write_beat_r <= next_write_w[8:0];
                    if ({2'd0, next_write_w, 5'd0} == {1'b0, bank_bytes_r[write_bank_r]})
                        write_state_r <= S_WRITE_RESPONSE;
                end
                S_WRITE_RESPONSE: if (wr_done_i) begin
                    write_state_r <= S_WRITE_IDLE;
                    write_bank_r <= !write_bank_r;
                end
                default: write_state_r <= write_state_r;
            endcase
        end
    end
    assign unused_load_w = ^{unused_load_shift_w, unused_load_mask_w};
    assign unused_geometry_w = ^{left_w[17:12], right_w[17:12], top_w[17:12], bottom_w[17:12],
        row_local_w[17], row_width_w[17], row_height_w[17], inner_width_r[17],
        inner_height_r[17], source_span_w[4:0], target_shift_w[255:64],
        blend_tag_i[28:14], unused_load_w, flags_w[15:4], source_min_w[4:0],
        source_max_w[4:0], map_shift_w[255:16], palette_shift_w[255:32],
        target_offset_w[31:5], issue_offset_w[31:14], target_bytes_w[31:16],
        tile_bytes_w[31:16], tile_row_last_w[4:0], source_last_w[4:0]};
endmodule
