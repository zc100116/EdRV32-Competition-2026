// File: edrv32_rnd_draw.v
// Spec: rnd-spec 2.2, 2.3, 2.6 FILL/BORDER/GLYPH/BLIT/TILEMAP, 5.
// Description: Double-buffered chunk loading, two-lane source sampling and tagged writeback.
//              Source reads, shading and result streams overlap; the parent owns shared DMA.
// Clock domain: clk_mem (clk_i).
module edrv32_rnd_draw (
    // Clock and reset.
    input wire clk_i,
    input wire rst_n_i,
    input wire rst_geometry_n_i,
    input wire rst_affine_n_i,

    // One drawing command; held constant through done.
    input wire start_i,
    input wire [511:0] command_i,
    input wire [31:0] geometry_control_i,
    input wire [31:0] affine_control_i,
    input wire [31:0] source_stride_i,
    input wire [63:0] round_area_i,
    input wire [1023:0] parameters_i,
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
    input wire [19:0] blend_offset_i,
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
    localparam [4:0] S_TARGET_END = 5'd22;
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
    reg [31:0] bank_source_row_r [0:1];
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
    reg [11:0] clip_left_r;
    reg [11:0] clip_right_r;
    reg [11:0] clip_bottom_r;
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

    // spec rnd 5.2: bounds arithmetic overlaps the target DMA, without stalling shading.
    reg [6:0] bounds_valid_r;
    reg bounds_ready_r;
    // Command SRC_STRIDE is 16 bits; blur.shadow_stride_o only drives its low 18 bits.
    reg [17:0] source_stride_r;
    reg [31:0] source_last_base_r;
    reg [11:0] dst_y_r;
    reg [31:0] dst_row_product_r;
    reg [31:0] dst_row_base_r;
    wire [31:0] bounds_kx_w [0:1];
    wire [31:0] bounds_ky_w;
    reg [15:0] bounds_kx_r [0:1];
    reg [15:0] bounds_ky_r;
    reg [47:0] bounds_scaled_x_r [0:1];
    reg [47:0] bounds_scaled_y_r;
    reg [15:0] bounds_x_r [0:1];
    reg [15:0] bounds_y_r;
    reg [31:0] bounds_u_r [0:1];
    reg [31:0] bounds_v_r;
    reg [31:0] bounds_row_product_r;
    reg [31:0] bounds_byte_r [0:1];
    reg [31:0] bounds_byte_delay_r [0:1];
    reg [31:0] bounds_row_base_r;
    reg [31:0] bounds_row_last_base_r;
    reg [31:0] bounds_addr_r [0:1];
    reg [31:0] bounds_last_addr_r [0:1];
    reg [31:0] bounds_first_r;
    reg [31:0] bounds_last_r;
    wire [26:0] bounds_min_word_w;
    wire [26:0] bounds_word_span_w;
    wire bounds_sparse_result_w;
    wire [15:0] bounds_span_w;
    wire bounds_sparse_w;
    wire bounds_available_w;
    reg [31:0] map_x_offset_r;
    reg [31:0] map_y_offset_r;
    wire [31:0] map_x_w;
    wire [31:0] map_y_w;
    reg [16:0] map_x_r;
    reg [16:0] map_y_r;
    reg [13:0] map_row_r;
    reg [31:0] map_row_product_r;
    reg [31:0] map_column_r;
    reg [31:0] map_row_base_r;
    reg [31:0] load_map_r;
    reg [31:0] tile_row_pixel_r;
    wire [31:0] tile_pixel_y_w;
    wire [34:0] tile_row_bits_w;
    wire [31:0] tile_row_base_w;
    wire [31:0] tile_last_offset_w;
    reg [5:0] tile_last_offset_r;
    wire [6:0] tile_end_offset_w;
    wire [1:0] tile_beats_w;
    reg [12:0] tile_next_x_r;
    wire [11:0] tile_query_x_w;
    wire [11:0] chunk_end_w;
    wire [11:0] bounds_coordinate_w [0:1];
    wire [34:0] bounds_bits_w [0:1];
    integer bounds_lane;

    // Elastic sampling: coordinate, multiply, sample, address, index, RAM, palette,
    // expansion, opacity/recolor products, normalization. Every stage advances together.
    reg [9:0] pipe_valid_r;
    reg [31:0] pipe_tag_r [0:9];
    reg [63:0] pipe_dst_r [1:9];
    reg [4:0] source_offset_r [4:5][0:1];
    reg [26:0] sample_line_r [0:1];
    reg [31:0] sample_next_r [0:1];
    reg [1:0] sample_cross_r;
    reg [8:0] source_index_r [0:1];
    reg [2:0] source_shift_r [3:6][0:1];
    reg [7:0] source_mask_r [3:6][0:1];
    reg [31:0] raw_r [0:1];
    reg [63:0] pipe_src_r;
    reg [31:0] sample_base2_r;
    reg [23:0] gradient_bias_r [0:3];
    reg [7:0] recolor_inverse_r;
    reg [15:0] recolor_product_r [0:2];
    reg [15:0] recolor_bias_r [0:2];
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
    wire [7:0] unused_decode_op_w;
    wire unused_decode_w;
    wire unused_empty_w;
    wire unused_fast_w;
    wire fill_w;
    wire affine_w;
    wire affine_ready_w;
    wire affine_read_wait_w;
    wire affine_valid_w;
    wire affine_input_step_w;
    wire affine_rd_valid_w;
    wire [31:0] affine_rd_addr_w;
    wire [15:0] affine_rd_bytes_w;
    wire affine_palette_valid_w;
    wire [15:0] affine_palette_index_w;
    wire [31:0] affine_pixel_w;
    wire [31:0] affine_destination_w;
    wire [31:0] affine_tag_w;
    wire [7:0] affine_coverage_w;
    wire [7:0] affine_input_cov_w;
    reg [11:0] affine_tile_left_r;
    reg [11:0] affine_tile_right_r;
    reg [11:0] affine_tile_top_r;
    reg [11:0] affine_tile_bottom_r;
    wire signed [17:0] affine_offset_x_w;
    wire signed [17:0] affine_offset_y_w;
    wire [12:0] affine_first_right_w;
    wire [12:0] affine_first_bottom_w;
    wire [12:0] affine_next_right_w;
    wire [12:0] affine_next_bottom_w;
    wire [11:0] affine_next_y_w;
    wire [11:0] affine_next_left_w;
    wire [31:0] affine_row_left_bytes_w;
    wire [31:0] affine_row_right_bytes_w;
    wire [31:0] write_clip_strb_w;
    wire [31:0] affine_write_mask_w [0:1][0:7];
    reg [1:0] affine_has_write_r;
    wire affine_skip_write_w;
    wire [31:0] final_tag_w;
    wire geometry_w;
    wire geometry_ready_w;
    wire geometry_valid_w;
    wire [7:0] geometry_cov_w;
    reg [7:0] geometry_cov_r [8:9];
    wire gradient_w;
    wire gradient_vertical_w;
    wire plain_fill_w;
    wire round_fill_w;
    wire mask_w;
    wire cutout_w;
    wire round_clip_w;
    wire shape_w;
    wire post_w;
    wire solid_w;
    wire [31:0] shape_start_w;
    wire [31:0] shape_end_w;
    wire [11:0] shape_radius_w;
    wire signed [17:0] shape_left_w;
    wire signed [17:0] shape_top_w;
    wire signed [17:0] shape_right_w;
    wire signed [17:0] shape_bottom_w;
    reg [1:0] post_valid_r;
    reg [63:0] post_src0_r;
    reg [63:0] post_dst_r [0:1];
    reg [31:0] post_tag_r [0:1];
    reg [15:0] post_product_r [0:1];
    reg [63:0] post_src1_r;
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
    reg signed [17:0] coverage_outer_x0_r;
    reg signed [17:0] coverage_inner_x0_r;
    wire [15:0] outer_cov_w;
    wire [15:0] inner_cov_w;
    wire [31:0] load_dst_w;
    wire [31:0] palette_addr_w;
    wire [31:0] tile_row_bytes_w;
    reg [12:0] chunk_right_r;
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
    wire [7:0] issue_map_index_w [0:1];
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
    reg [31:0] load_dst_r;
    reg [31:0] row_start_r;
    reg [13:0] clip_left_bytes_r;
    reg [13:0] clip_right_bytes_r;
    reg [10:0] clip_end_r;
    reg load_last_r;
    wire [26:0] next_target_word_w;
    wire [31:0] clip_end_w;
    wire [5:0] target_word_difference_w;
    wire [6:0] target_word_count_w;
    wire [4:0] target_last_start_w;
    wire [15:0] target_bytes_w;
    wire [31:0] tile_bytes_w;
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
    function automatic [7:0] gradient_channel;
        input [24:0] low_sum_i;
        input high_zero_i;
        input high_minus_one_i;
        input negative_i;
        reg [15:0] unused_fraction;
        begin
            unused_fraction = low_sum_i[15:0];
            if (high_zero_i)
                gradient_channel = low_sum_i[24] ? 8'd255 : low_sum_i[23:16];
            else if (high_minus_one_i)
                gradient_channel = low_sum_i[24] ? low_sum_i[23:16] : 8'd0;
            else
                gradient_channel = negative_i ? 8'd0 : 8'd255;
        end
    endfunction
    function automatic [7:0] normalize_biased;
        input [15:0] biased_i;
        reg [15:0] rounded;
        reg [7:0] unused_low;
        begin
            rounded = biased_i + (biased_i >> 8);
            normalize_biased = rounded[15:8];
            unused_low = rounded[7:0];
        end
    endfunction

    // Shadow shading keeps opcode 06 but uses its expanded GLYPH coordinates.
    assign op_w = command_i[7:0];
    edrv32_rnd_decode u_decode (
        .command_i({command_i[511:8], 8'h04}),
        .illegal_o(unused_decode_w),
        .empty_o(unused_empty_w),
        .op_o(unused_decode_op_w),
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
    assign affine_w = op_w == 8'h0d;
    assign geometry_w = op_w >= 8'h09 && op_w <= 8'h0b;
    assign round_fill_w = op_w == 8'h01 || op_w == 8'h02;
    assign plain_fill_w = op_w == 8'h01 || geometry_w;
    assign fill_w = round_fill_w || geometry_w;
    assign gradient_w = op_w == 8'h09 ? flags_w[6] : op_w == 8'h01 && flags_w[0];
    assign gradient_vertical_w = op_w == 8'h09 ? flags_w[7] : flags_w[1];
    assign tile_w = op_w == 8'h08;
    assign mask_w = op_w == 8'h0c;
    assign cutout_w = op_w == 8'h06 && flags_w[0];
    assign round_clip_w = (op_w == 8'h04 || affine_w) && flags_w[7];
    assign shape_w = mask_w || cutout_w || round_clip_w;
    assign post_w = cutout_w || round_clip_w || geometry_w;
    assign solid_w = fill_w || mask_w || affine_w;
    assign shape_start_w = mask_w ? command_i[319:288] :
        cutout_w ? command_i[383:352] : affine_w ? parameters_i[223:192] : round_area_i[31:0];
    assign shape_end_w = mask_w ? command_i[351:320] :
        cutout_w ? command_i[415:384] : affine_w ? parameters_i[255:224] : round_area_i[63:32];
    assign shape_radius_w = mask_w ? command_i[267:256] :
        cutout_w ? command_i[427:416] : affine_w ? command_i[395:384] : command_i[475:464];
    assign shape_left_w = {{2{shape_start_w[15]}}, shape_start_w[15:0]};
    assign shape_top_w = {{2{shape_start_w[31]}}, shape_start_w[31:16]};
    assign shape_right_w = {{2{shape_end_w[15]}}, shape_end_w[15:0]};
    assign shape_bottom_w = {{2{shape_end_w[31]}}, shape_end_w[31:16]};
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
        .x_i(coverage_outer_x0_r),
        .width_i(width_r),
        .edge_q4_i(bank_outer_edge_r[pipe_tag_r[0][31]]),
        .row_inside_i(1'b1),
        .coverage_o(outer_cov_w)
    );
    edrv32_rnd_coverage u_inner_coverage (
        .x_i(coverage_inner_x0_r),
        .width_i(inner_width_r[16:0]),
        .edge_q4_i(bank_inner_edge_r[pipe_tag_r[0][31]]),
        .row_inside_i(bank_inner_inside_r[pipe_tag_r[0][31]]),
        .coverage_o(inner_cov_w)
    );
    assign affine_offset_x_w = left_w -
        $signed({{2{command_i[175]}}, command_i[175:160]});
    assign affine_offset_y_w = top_w -
        $signed({{2{command_i[191]}}, command_i[191:176]});
    assign affine_first_right_w = {1'b0, left_w[11:0]} + 13'd31 -
        {8'd0, affine_offset_x_w[4:0]};
    assign affine_first_bottom_w = {1'b0, top_w[11:0]} + 13'd15 -
        {9'd0, affine_offset_y_w[3:0]};
    assign affine_next_right_w = {1'b0, affine_tile_right_r} + 13'd32;
    assign affine_next_bottom_w = {1'b0, affine_tile_bottom_r} + 13'd16;
    assign affine_next_y_w = load_y_r < affine_tile_bottom_r ? load_y_r + 12'd1 :
        affine_tile_right_r < clip_right_r ? affine_tile_top_r : affine_tile_bottom_r + 12'd1;
    assign affine_next_left_w = load_y_r < affine_tile_bottom_r ? affine_tile_left_r :
        affine_tile_right_r < clip_right_r ? affine_tile_right_r + 12'd1 : clip_left_r;
    assign affine_row_left_bytes_w = argb_w ? {18'd0, load_left_r, 2'd0} :
        {19'd0, load_left_r, 1'b0};
    assign affine_row_right_bytes_w = argb_w ? {18'd0, affine_tile_right_r, 2'd0} :
        {19'd0, affine_tile_right_r, 1'b0};
    assign affine_input_step_w = !pipe_valid_r[0] || affine_ready_w;
    assign affine_input_cov_w = !round_clip_w || shape_radius_w == 0 ?
        8'd255 : inner_cov_w[7:0];
    assign load_dst_w = load_dst_r;
    assign clip_end_w = dst_row_base_r + (affine_w ? affine_row_right_bytes_w :
        {18'd0, clip_right_bytes_r});
    assign next_target_word_w = load_dst_r[31:5] + (argb_w ? 27'd64 : 27'd32);
    // A chunk owns at most 64 target beats, so six bits retain the complete word difference.
    assign target_word_difference_w = clip_end_r[10:5] - load_dst_r[10:5];
    assign target_word_count_w = {1'b0, target_word_difference_w} + 7'd1;
    assign target_bytes_w = load_last_r ? {4'd0, target_word_count_w, 5'd0} :
        (argb_w ? 16'd2048 : 16'd1024);
    assign target_last_start_w = load_last_r ? clip_end_r[4:0] :
        (argb_w ? {3'b111, load_dst_r[1:0]} : {4'b1111, load_dst_r[0]});
    assign tile_row_base_w = command_i[287:256] + tile_row_bits_w[34:3];
    assign tile_last_offset_w = tile_row_bytes_w - 32'd1;
    assign tile_end_offset_w = {2'd0, tile_row_base_w[4:0]} + {1'b0, tile_last_offset_r};
    assign tile_beats_w = tile_end_offset_w[6:5] + 2'd1;
    assign tile_bytes_w = {25'd0, tile_beats_w, 5'd0};
    assign tile_pixel_y_w = map_shift_w[13] ?
        tile_mask_w - ({15'd0, map_y_r} & tile_mask_w) : {15'd0, map_y_r} & tile_mask_w;
    assign tile_row_bits_w = {3'd0, tile_row_pixel_r} << bits_log2_w;
    assign tile_row_bytes_w = ((tile_mask_w + 32'd1) << bits_log2_w) >> 3;
    // End chunks on a target beat so concurrent banks never own the same bytes.
    assign chunk_right_w = affine_w ? {1'b0, affine_tile_right_r} : chunk_right_r;
    // Alignment makes the low five address bits irrelevant to the lower bound.
    assign bounds_min_word_w = bounds_addr_r[0][31:5] < bounds_addr_r[1][31:5] ?
        bounds_addr_r[0][31:5] : bounds_addr_r[1][31:5];
    assign bounds_word_span_w = bounds_last_r[31:5] - bounds_first_r[31:5] + 27'd1;
    assign bounds_span_w = {bounds_word_span_w[10:0], 5'd0};
    assign bounds_sparse_result_w = bounds_word_span_w > 27'd512;
    assign bounds_available_w = bounds_ready_r || bounds_valid_r[6];
    assign bounds_sparse_w = bounds_ready_r ? bank_sparse_r[load_bank_r] :
        bounds_sparse_result_w;
    assign chunk_end_w = chunk_right_w < {1'b0, clip_right_r} ?
        chunk_right_w[11:0] : clip_right_r;
    assign bounds_ky_w = op_w == 8'h04 && flags_w[1] ?
        {{16{command_i[223]}}, command_i[223:208]} - {20'd0, load_y_r} :
        {20'd0, load_y_r} - {{16{command_i[191]}}, command_i[191:176]};
    assign bounds_kx_w[0] = op_w == 8'h04 && flags_w[0] ?
        {{16{command_i[207]}}, command_i[207:192]} - {20'd0, bounds_coordinate_w[0]} :
        {20'd0, bounds_coordinate_w[0]} - {{16{command_i[175]}}, command_i[175:160]};
    assign bounds_kx_w[1] = op_w == 8'h04 && flags_w[0] ?
        {{16{command_i[207]}}, command_i[207:192]} - {20'd0, bounds_coordinate_w[1]} :
        {20'd0, bounds_coordinate_w[1]} - {{16{command_i[175]}}, command_i[175:160]};
    assign bounds_coordinate_w[0] = load_left_r;
    assign bounds_coordinate_w[1] = chunk_end_w;
    assign bounds_bits_w[0] = {3'd0, bounds_u_r[0]} << bits_log2_w;
    assign bounds_bits_w[1] = {3'd0, bounds_u_r[1]} << bits_log2_w;
    assign next_tile_x_w = {1'b0, tile_x_r} +
        (flags_w[0] ? 13'd16 : 13'd8) - {9'd0, map_x_r[3:0] & tile_mask_w[3:0]};
    // The next map lookup runs during this tile's source DMA; no per-tile setup bubbles.
    assign tile_query_x_w = load_state_r == S_SOURCE_REQ || load_state_r == S_SOURCE_DATA ||
        load_state_r == S_TILE_NEXT ? tile_next_x_r[11:0] : tile_x_r;
    assign map_x_w = {20'd0, tile_query_x_w} + map_x_offset_r;
    assign map_y_w = {20'd0, load_y_r} + map_y_offset_r;
    assign map_hit_w = map_valid_r && map_addr_r == {load_map_r[31:5], 5'd0};
    assign map_shift_w = map_data_r >> {load_map_r[4:0], 3'd0};
    assign palette_last_w = format_w == 4'd6 ? 8'd255 : format_w == 4'd7 ? 8'd15 :
        format_w == 4'd8 ? 8'd3 : 8'd1;
    assign palette_addr_w = command_i[447:416] + {22'd0, palette_index_r, 2'd0};
    assign palette_shift_w = palette_buffer_r >> {palette_addr_w[4:0], 3'd0};
    assign palette_write_w = load_state_r == S_PALETTE_WRITE && !cancel_i;
    assign load_request_w = load_state_r == S_TARGET_REQ || load_state_r == S_SOURCE_REQ ||
        load_state_r == S_MAP_REQ || load_state_r == S_PALETTE_REQ;
    assign load_addr_w = load_state_r == S_TARGET_REQ ? bank_target_r[load_bank_r] :
        load_state_r == S_MAP_REQ ? {load_map_r[31:5], 5'd0} :
        load_state_r == S_PALETTE_REQ ? {palette_addr_w[31:5], 5'd0} : load_source_base_r;
    assign load_bytes_w = load_state_r == S_TARGET_REQ ? bank_bytes_r[load_bank_r] :
        load_state_r == S_SOURCE_REQ ? load_source_bytes_r : 16'd32;
    assign rd_valid_o = !cancel_i && !read_busy_r && (miss_request_w || load_request_w);
    assign rd_addr_o = miss_request_w ? miss_query_w : load_addr_w;
    assign rd_bytes_o = miss_request_w ?
        (affine_w ? affine_rd_bytes_w : 16'd32) : load_bytes_w;
    assign load_accept_w = rd_valid_o && rd_ready_i && !miss_request_w;
    assign load_data_w = rd_data_valid_i && read_busy_r && !read_render_r;
    assign load_done_w = rd_done_i && read_busy_r && !read_render_r;

    assign sample_bank_w = pipe_tag_r[0][31];
    assign source_bank_w = pipe_tag_r[4][31];
    assign render_start_w = active_r && render_state_r == S_RENDER_IDLE &&
        loaded_r[render_bank_r];
    assign render_finish_w = blend_valid_i && blend_tag_i[30];
    assign affine_skip_write_w = active_r && affine_w &&
        write_state_r == S_WRITE_IDLE && rendered_r[write_bank_r] &&
        !affine_has_write_r[write_bank_r];
    assign write_start_w = active_r && write_state_r == S_WRITE_IDLE &&
        rendered_r[write_bank_r] && !affine_skip_write_w;
    assign write_finish_w = (write_state_r == S_WRITE_RESPONSE && wr_done_i) ||
        affine_skip_write_w;
    assign next_write_w = {1'b0, write_beat_r} + 10'd1;
    assign issue_pair_w = !affine_w && !geometry_w && issue_x_r < bank_right_r[render_bank_r] &&
        issue_offset_w[4:0] <= (argb_w ? 5'd24 : 5'd28);
    assign issue_last_w = {1'b0, issue_x_r} + (issue_pair_w ? 13'd1 : 13'd0) >=
        {1'b0, bank_right_r[render_bank_r]};
    assign issue_offset_w = {18'd0, issue_byte_r};
    assign target_offset_w = {18'd0, pipe_tag_r[0][13:0]};
    wire [255:0] target_selected_w;
    genvar target_slice;
    generate for (target_slice = 0; target_slice < 4; target_slice = target_slice + 1) begin
        : g_target_select
        reg bank_r /* synthesis syn_preserve=1 */;
        wire [255:0] selected_w;
        wire unused_selected_w;
        always @(posedge clk_i) begin
            if (issue_w)
                bank_r <= render_bank_r;
        end
        assign selected_w = target_data_w[bank_r];
        assign target_selected_w[target_slice*64 +: 64] = selected_w[target_slice*64 +: 64];
        assign unused_selected_w = ^selected_w;
    end endgenerate
    assign target_shift_w = target_selected_w >> {target_offset_w[4:0], 3'd0};
    assign source_ready_w = !pipe_valid_r[4] || solid_w || !bank_sparse_r[source_bank_w] ||
        (lane_hit_w[0] && (!pipe_tag_r[4][29] || lane_hit_w[1]));
    assign pipeline_step_w = (!(post_w ? post_valid_r[1] : pipe_valid_r[9]) ||
        blend_ready_i) && source_ready_w &&
        (!geometry_w || !pipe_valid_r[7] || geometry_valid_w);
    genvar step_region;
    generate for (step_region = 0; step_region < 4; step_region = step_region + 1) begin
        : g_step_ctrl
        reg tail_valid_r /* synthesis syn_preserve=1 */;
        reg geometry_valid_r /* synthesis syn_preserve=1 */;
        reg post_valid_copy_r /* synthesis syn_preserve=1 */;
        wire step_w /* synthesis syn_keep=1 */;
        assign step_w = (!(post_w ? post_valid_copy_r : tail_valid_r) || blend_ready_i) &&
            source_ready_w && (!geometry_w || !geometry_valid_r || geometry_valid_w);
        always @(posedge clk_i or negedge rst_n_i) begin
            if (!rst_n_i) begin
                tail_valid_r <= 1'b0;
                geometry_valid_r <= 1'b0;
                post_valid_copy_r <= 1'b0;
            end else if (cancel_i || start_i) begin
                tail_valid_r <= 1'b0;
                geometry_valid_r <= 1'b0;
                post_valid_copy_r <= 1'b0;
            end else if (pipeline_step_w) begin
                tail_valid_r <= pipe_valid_r[8];
                geometry_valid_r <= affine_w ? affine_valid_w : pipe_valid_r[6];
                post_valid_copy_r <= post_valid_r[0];
            end
        end
    end endgenerate
    assign issue_w = render_state_r == S_RENDER_STREAM &&
        (affine_w ? affine_input_step_w : pipeline_step_w) &&
        (!geometry_w || geometry_ready_w);
    assign miss_request_w = affine_w ? affine_rd_valid_w :
        pipe_valid_r[4] && !source_ready_w;
    assign miss_query_w = affine_w ? affine_rd_addr_w :
        !lane_low_hit_w[0] ? {sample_line_r[0], 5'd0} :
        lane_cross_w[0] && !lane_high_hit_w[0] ? lane_next_w[0] :
        !lane_low_hit_w[1] ? {sample_line_r[1], 5'd0} : lane_next_w[1];
    assign blend_valid_o = (post_w ? post_valid_r[1] : pipe_valid_r[9]) && source_ready_w;
    // MASK bypasses over using the shared pipe's exact raw-destination preservation path.
    assign blend_src_o = mask_w ? 64'd0 : post_w ? post_src1_r : pipe_src_r;
    assign blend_dst_o = mask_w ? pipe_src_r : post_w ? post_dst_r[1] : pipe_dst_r[9];
    assign final_tag_w = post_w ? post_tag_r[1] : pipe_tag_r[9];
    assign blend_tag_o = affine_w ? {final_tag_w[31:29], |blend_src_o[31:24],
        final_tag_w[27:0]} : final_tag_w;
    assign result_pixels_w = argb_w ? blend_pixel_i :
        {32'd0, blend_pixel_i[47:32], blend_pixel_i[15:0]};
    genvar result_quadrant;
    generate for (result_quadrant = 0; result_quadrant < 4;
        result_quadrant = result_quadrant + 1) begin : g_result_shift
        wire [255:0] shifted_w;
        assign shifted_w = {192'd0, result_pixels_w} <<
            {blend_offset_i[result_quadrant*5 +: 5], 3'd0};
        assign result_write_data_w[result_quadrant*64 +: 64] =
            shifted_w[result_quadrant*64 +: 64];
        wire unused_shifted_w;
        assign unused_shifted_w = ^shifted_w;
    end endgenerate
    assign result_write_strb_w = (argb_w ? (blend_tag_i[29] ? 32'hff : 32'hf) :
        (blend_tag_i[29] ? 32'hf : 32'h3)) << blend_tag_i[4:0];
    assign wr_valid_o = write_state_r == S_WRITE_DESC && !cancel_i;
    assign wr_addr_o = bank_target_r[write_bank_r];
    assign wr_bytes_o = bank_bytes_r[write_bank_r];
    assign wr_data_valid_o = write_state_r == S_WRITE_DATA && !cancel_i;
    assign wr_data_o = result_data_w[write_bank_r];
    // Original target bytes are preserved in the result RAM outside the drawing region.
    assign write_clip_strb_w = (write_beat_r == 9'd0 ?
        32'hffff_ffff << bank_first_byte_r[write_bank_r] : 32'hffff_ffff) &
        ({2'd0, next_write_w, 5'd0} == {1'b0, bank_bytes_r[write_bank_r]} ?
            32'hffff_ffff >> (5'd31 - bank_last_byte_r[write_bank_r]) : 32'hffff_ffff);
    assign wr_strb_o = write_clip_strb_w & (affine_w ?
        affine_write_mask_w[write_bank_r][write_beat_r[2:0]] : 32'hffff_ffff);
    assign idle_o = !active_r;
    assign done_o = done_r;
    assign pixel_count_o = blend_valid_i ? (blend_tag_i[29] ? 5'd2 : 5'd1) : 5'd0;
    assign read_wait_o = active_r && ((render_state_r == S_RENDER_IDLE &&
        !loaded_r[render_bank_r]) || (affine_w ? affine_read_wait_w : miss_request_w));
    assign write_wait_o = active_r && busy_r[load_bank_r] &&
        write_state_r != S_WRITE_IDLE;

    genvar pixel;
    generate for (pixel = 0; pixel < 2; pixel = pixel + 1) begin : g_pixel
        localparam [11:0] PIXEL = pixel;
        wire [11:0] coordinate_w;
        wire [31:0] kx_w;
        wire [31:0] gradient_k_w;
        wire [11:0] issue_map_x_w;
        wire [11:0] issue_map_column_w;
        wire [3:0] tile_x_w;
        wire [3:0] tile_y_w;
        wire [34:0] pixel_bits_w;
        wire [8:0] tile_slot_base_w;
        wire [1:0] tile_beat_w;
        wire [31:0] map_entry_read_w;
        wire unused_coordinate_w;
        reg [15:0] kx0_r;
        reg [15:0] kx1_r;
        reg [47:0] scaled_x1_r;
        reg [31:0] sample_u2_r;
        reg [3:0] map_x0_r;
        reg [3:0] map_y0_r;
        reg [19:0] tile_pixel1_r;
        reg [19:0] tile_pixel2_r;
        reg [7:0] tile_slot_r [0:3];
        reg [6:0] tile_base_r [1:3];
        reg [31:0] address3_r;
        reg [31:0] expanded7_r;
        reg [23:0] expanded8_r;
        reg [15:0] alpha_product8_r;
        reg [15:0] recolor_back8_r [0:2];
        reg [31:0] expanded_w;
        wire [7:0] sample_w;
        reg [16:0] gradient_k0_r;
        reg signed [48:0] gradient_product1_r [0:3];
        reg [24:0] gradient_low2_r [0:3];
        reg gradient_zero2_r [0:3];
        reg gradient_minus_one2_r [0:3];
        reg gradient_negative2_r [0:3];
        wire [7:0] gradient_value_w [0:3];
        reg [23:0] fill_color_r [3:6];
        reg [7:0] fill_coverage_r [1:4];
        reg [7:0] shape_coverage_r [1:9];
        wire shape_x_inside_w;
        wire [7:0] shape_factor_w;
        wire [7:0] mask_alpha_w;
        wire [7:0] post_factor_w;
        wire [7:0] source_factor_w;
        assign post_factor_w = geometry_w ? (pixel == 0 ? geometry_cov_r[9] : 8'd0) :
            cutout_w ? command_i[255:248] : shape_coverage_r[9];
        assign source_factor_w = cutout_w ?
            8'd255 - shape_coverage_r[7] : command_i[255:248];
        assign shape_x_inside_w = $signed(coverage_inner_x0_r) >= 0 &&
            $signed(coverage_inner_x0_r) < inner_width_r;
        assign shape_factor_w = round_clip_w && shape_radius_w == 0 ? 8'd255 :
            mask_w && flags_w[0] && (!bank_inner_inside_r[pipe_tag_r[0][31]] ||
            !(pixel == 0 ? shape_x_inside_w :
                ($signed(coverage_inner_x0_r) + 18'sd1 >= 0 &&
                    $signed(coverage_inner_x0_r) + 18'sd1 < inner_width_r))) ? 8'd255 :
            inner_cov_w[pixel*8 +: 8];
        assign mask_alpha_w = divide255(alpha_product8_r);
        reg [7:0] fill_inner_r [1:2];
        reg [7:0] fill_operand_a3_r;
        reg [7:0] fill_operand_b3_r;
        reg [15:0] fill_product4_r;
        reg [7:0] fill_alpha5_r;
        reg [7:0] fill_factor5_r;
        reg [15:0] fill_product6_r;
        reg [31:0] fill_pixel7_r;
        reg [31:0] fill_pixel8_r;
        integer arithmetic_stage;
        integer channel;

        // RECT is signed 16 bits, CLIP is 12 bits; accepted drawing samples have 0<=k<65536.
        assign coordinate_w = issue_x_r + PIXEL;
        assign kx_w = op_w == 8'h04 && flags_w[0] ?
            {{16{command_i[207]}}, command_i[207:192]} - {20'd0, coordinate_w} :
            {20'd0, coordinate_w} - {{16{command_i[175]}}, command_i[175:160]};
        assign gradient_k_w = gradient_vertical_w ? {20'd0, bank_y_r[render_bank_r]} -
            {{16{command_i[191]}}, command_i[191:176]} : {20'd0, coordinate_w} -
            {{16{command_i[175]}}, command_i[175:160]};
        assign issue_map_x_w = coordinate_w + map_x_offset_r[11:0];
        assign issue_map_column_w = issue_map_x_w >> tile_log2_w;
        assign issue_map_index_w[pixel] = issue_map_column_w[7:0] -
            bank_tile_first_r[render_bank_r][7:0];
        assign map_entry_read_w = map_entry_w[sample_bank_w][pixel];
        assign tile_x_w = map_entry_read_w[12] ?
            tile_mask_w[3:0] - (map_x0_r & tile_mask_w[3:0]) :
            map_x0_r & tile_mask_w[3:0];
        assign tile_y_w = map_entry_read_w[13] ?
            tile_mask_w[3:0] - (map_y0_r & tile_mask_w[3:0]) :
            map_y0_r & tile_mask_w[3:0];
        assign pixel_bits_w = (tile_w ? {15'd0, tile_pixel2_r} :
            {3'd0, sample_u2_r}) << bits_log2_w;
        assign tile_slot_base_w = {1'b0, tile_slot_r[3]} + {tile_slot_r[3], 1'b0};
        assign tile_beat_w = address3_r[6:5] - tile_base_r[3][6:5];
        assign unused_coordinate_w = ^{kx_w[31:16], gradient_k_w[31:16],
            scaled_x1_r[15:0], issue_map_column_w[11:8], map_entry_read_w[31:23],
            map_entry_read_w[15:14], tile_base_r[3][4:0], sample_w[7:4]};
        assign lane_cross_w[pixel] = sample_cross_r[pixel];
        assign lane_next_w[pixel] = sample_next_r[pixel];
        assign lane_hit_w[pixel] = lane_low_hit_w[pixel] &&
            (!lane_cross_w[pixel] || lane_high_hit_w[pixel]);
        assign lane_cache_w[pixel] = {lane_cache_high_w[pixel], lane_cache_low_w[pixel]};
        wire [511:0] palette_source_w;
        wire [511:0] raw_source_w;
        genvar palette_slice;
        for (palette_slice = 0; palette_slice < 8; palette_slice = palette_slice + 1) begin
            : g_palette_select
            reg bank_r /* synthesis syn_preserve=1 */;
            wire [511:0] bank_data_w;
            reg sparse_r [0:1] /* synthesis syn_preserve=1 */;
            always @(posedge clk_i) begin
                if (load_state_r == S_BOUNDS && (solid_w || tile_w))
                    sparse_r[load_bank_r] <= 1'b0;
                if ((load_state_r == S_BOUNDS && bounds_ready_r) ||
                    (bounds_valid_r[6] && load_state_r != S_CHUNK))
                    sparse_r[load_bank_r] <= bounds_sparse_result_w;
            end
            assign raw_source_w[palette_slice*64 +: 64] = sparse_r[pipe_tag_r[5][31]] ?
                sparse_data_r[pixel][palette_slice*64 +: 64] :
                palette_source_w[palette_slice*64 +: 64];
            always @(posedge clk_i) begin
                if (g_step_ctrl[pixel].step_w && pipe_valid_r[4])
                    bank_r <= pipe_tag_r[4][31];
            end
            assign bank_data_w = {source_next_w[bank_r][pixel], source_data_w[bank_r][pixel]};
            assign palette_source_w[palette_slice*64 +: 64] =
                bank_data_w[palette_slice*64 +: 64];
            wire unused_bank_data_w;
            assign unused_bank_data_w = ^bank_data_w;
        end
        assign raw_shift_w[pixel] = raw_source_w >>
                {source_offset_r[5][pixel], 3'd0};
        assign palette_index_w[pixel] =
            (raw_shift_w[pixel][7:0] >> source_shift_r[5][pixel]) & source_mask_r[5][pixel];
        edrv32_ram_rnd_palette u_palette (
            .clk_i(clk_i),
            .wr_en_i(palette_write_w),
            .wr_addr_i(palette_index_r),
            .wr_data_i(palette_shift_w[31:0]),
            .rd_en_i((affine_w ? affine_palette_valid_w :
                pipe_valid_r[5] && g_step_ctrl[pixel].step_w) && !cancel_i),
            .rd_addr_i(affine_w ? affine_palette_index_w[pixel*8 +: 8] : palette_index_w[pixel]),
            .rd_data_o(palette_data_w[pixel])
        );
        assign sample_w = (raw_r[pixel][7:0] >> source_shift_r[6][pixel]) &
            source_mask_r[6][pixel];
        always @(*) begin
            expanded_w = 32'd0;
            case (format_w)
                4'd0: expanded_w = {
                    flags_w[2] && raw_r[pixel][15:0] == command_i[463:448] ? 8'd0 : 8'd255,
                    raw_r[pixel][15:11], raw_r[pixel][15:13],
                    raw_r[pixel][10:5], raw_r[pixel][10:9],
                    raw_r[pixel][4:0], raw_r[pixel][4:2]};
                4'd1: expanded_w = raw_r[pixel];
                4'd2: expanded_w = {raw_r[pixel][7:0], command_i[247:224]};
                4'd3: expanded_w = {sample_w[3:0], sample_w[3:0], command_i[247:224]};
                4'd4: expanded_w = {sample_w[1:0], sample_w[1:0],
                    sample_w[1:0], sample_w[1:0], command_i[247:224]};
                4'd5: expanded_w = {{8{sample_w[0]}}, command_i[247:224]};
                4'd6, 4'd7, 4'd8, 4'd9: expanded_w = palette_data_w[pixel];
                default: expanded_w = 32'd0;
            endcase
        end
        assign converted_w[pixel][31:24] = divide255(alpha_product8_r);
        genvar gradient_component;
        for (gradient_component = 0; gradient_component < 4;
            gradient_component = gradient_component + 1) begin : g_gradient
            assign gradient_value_w[gradient_component] = gradient_channel(
                gradient_low2_r[gradient_component], gradient_zero2_r[gradient_component],
                gradient_minus_one2_r[gradient_component],
                gradient_negative2_r[gradient_component]);
        end
        genvar color_channel;
        for (color_channel = 0; color_channel < 3; color_channel = color_channel + 1) begin
            : g_color
            assign converted_w[pixel][color_channel*8 +: 8] = op_w == 8'h03 ?
                command_i[224+color_channel*8 +: 8] :
                (op_w == 8'h04 || affine_w) && flags_w[3] ?
                    normalize_biased(recolor_back8_r[color_channel] +
                        recolor_bias_r[color_channel]) : expanded8_r[color_channel*8 +: 8];
        end
        always @(posedge clk_i) begin
            if (g_step_ctrl[pixel].step_w) begin
                post_product_r[pixel] <= pipe_src_r[pixel*32+24 +: 8] *
                    post_factor_w;
                post_src1_r[pixel*32 +: 32] <=
                    {divide255(post_product_r[pixel]), post_src0_r[pixel*32 +: 24]};
                if (issue_w) begin
                    kx0_r <= kx_w[15:0];
                    gradient_k0_r <= {1'b0, gradient_k_w[15:0]};
                    map_x0_r <= coordinate_w[3:0] + map_x_offset_r[3:0];
                    map_y0_r <= bank_y_r[render_bank_r][3:0] + map_y_offset_r[3:0];
                    tile_slot_r[0] <= issue_map_index_w[pixel];
                end
                if (pipe_valid_r[0]) begin
                    fill_coverage_r[1] <= geometry_w ? 8'd255 : outer_cov_w[pixel*8 +: 8];
                    shape_coverage_r[1] <= shape_factor_w;
                    fill_inner_r[1] <= 8'd255 - inner_cov_w[pixel*8 +: 8];
                    scaled_x1_r <= kx0_r * command_i[383:352];
                    kx1_r <= kx0_r;
                    tile_pixel1_r <= flags_w[0] ?
                        {map_entry_read_w[11:0], tile_y_w, tile_x_w} :
                        {2'd0, map_entry_read_w[11:0], tile_y_w[2:0], tile_x_w[2:0]};
                    tile_base_r[1] <= map_entry_read_w[22:16];
                    for (channel = 0; channel < 4; channel = channel + 1)
                        gradient_product1_r[channel] <= $signed(gradient_k0_r) *
                            $signed(command_i[320+channel*32 +: 32]);
                end
                if (pipe_valid_r[1]) begin
                    sample_u2_r <= {16'd0, command_i[335:320]} +
                        (op_w == 8'h04 ? scaled_x1_r[47:16] : {16'd0, kx1_r});
                    tile_pixel2_r <= tile_pixel1_r;
                    // Only a carry from the low 24 bits can change the saturation class.
                    for (channel = 0; channel < 4; channel = channel + 1) begin
                        gradient_low2_r[channel] <= {1'b0, gradient_product1_r[channel][23:0]} +
                            {1'b0, gradient_bias_r[channel]};
                        gradient_zero2_r[channel] <= gradient_product1_r[channel][48:24] == 0;
                        gradient_minus_one2_r[channel] <= &gradient_product1_r[channel][48:24];
                        gradient_negative2_r[channel] <= gradient_product1_r[channel][48];
                    end
                end
                if (pipe_valid_r[2]) begin
                    address3_r <= sample_base2_r + pixel_bits_w[34:3];
                    source_shift_r[3][pixel] <= (3'd0 - (3'd1 << bits_log2_w)) -
                        pixel_bits_w[2:0];
                    source_mask_r[3][pixel] <= bits_log2_w >= 3'd3 ? 8'hff :
                        8'hff >> (8 - (1 << bits_log2_w));
                    fill_color_r[3] <= gradient_w ?
                        {gradient_value_w[1],
                            gradient_value_w[2],
                            gradient_value_w[3]} : command_i[247:224];
                    fill_operand_a3_r <= plain_fill_w ?
                        command_i[255:248] : fill_coverage_r[2];
                    fill_operand_b3_r <= plain_fill_w ? (gradient_w ?
                        gradient_value_w[0] : 8'd255) : fill_inner_r[2];
                end
                if (pipe_valid_r[3]) begin
                    sample_line_r[pixel] <= address3_r[31:5];
                    sample_next_r[pixel] <= {address3_r[31:5], 5'd0} + 32'd32;
                    sample_cross_r[pixel] <= format_w == 4'd1 ? address3_r[4:0] > 5'd28 :
                        format_w == 4'd0 && address3_r[4:0] == 5'd31;
                    source_index_r[pixel] <= tile_w ? tile_slot_base_w + {7'd0, tile_beat_w} :
                        address3_r[13:5] - bank_source_r[pipe_tag_r[3][31]][13:5];
                    source_offset_r[4][pixel] <= address3_r[4:0];
                    fill_product4_r <= fill_operand_a3_r * fill_operand_b3_r;
                end
                if (pipe_valid_r[4]) begin
                    sparse_data_r[pixel] <= lane_cache_w[pixel];
                    source_offset_r[5][pixel] <= source_offset_r[4][pixel];
                    fill_alpha5_r <= divide255(fill_product4_r);
                    fill_factor5_r <= plain_fill_w ? fill_coverage_r[4] : command_i[255:248];
                end
                if (pipe_valid_r[5]) begin
                    raw_r[pixel] <= raw_shift_w[pixel][31:0];
                    fill_product6_r <= fill_alpha5_r * fill_factor5_r;
                end
                if (affine_w && affine_valid_w) begin
                    expanded7_r <= pixel == 0 ? affine_pixel_w : 32'd0;
                    shape_coverage_r[7] <= affine_coverage_w;
                end
                if (pipe_valid_r[6]) begin
                    expanded7_r <= expanded_w;
                    fill_pixel7_r <= {divide255(fill_product6_r), fill_color_r[6]};
                end
                if (pipe_valid_r[7]) begin
                    expanded8_r <= expanded7_r[23:0];
                    alpha_product8_r <= mask_w ?
                        pipe_dst_r[7][pixel*32+24 +: 8] * shape_coverage_r[7] :
                        expanded7_r[31:24] * source_factor_w;
                    for (channel = 0; channel < 3; channel = channel + 1)
                        recolor_back8_r[channel] <= recolor_inverse_r *
                            expanded7_r[channel*8 +: 8];
                    fill_pixel8_r <= fill_pixel7_r;
                end
                if (pipe_valid_r[8]) begin
                    if (mask_w)
                        pipe_src_r[pixel*32 +: 32] <= mask_alpha_w == 0 ? 32'd0 :
                            {mask_alpha_w, pipe_dst_r[8][pixel*32 +: 24]};
                    else
                        pipe_src_r[pixel*32 +: 32] <= fill_w ?
                            fill_pixel8_r : converted_w[pixel];
                end
                for (arithmetic_stage = 2; arithmetic_stage < 10;
                    arithmetic_stage = arithmetic_stage + 1)
                    if (pipe_valid_r[arithmetic_stage-1])
                        shape_coverage_r[arithmetic_stage] <=
                            shape_coverage_r[arithmetic_stage-1];
                for (arithmetic_stage = 1; arithmetic_stage < 4;
                    arithmetic_stage = arithmetic_stage + 1)
                    if (pipe_valid_r[arithmetic_stage-1])
                        tile_slot_r[arithmetic_stage] <= tile_slot_r[arithmetic_stage-1];
                for (arithmetic_stage = 2; arithmetic_stage < 4;
                    arithmetic_stage = arithmetic_stage + 1)
                    if (pipe_valid_r[arithmetic_stage-1])
                        tile_base_r[arithmetic_stage] <= tile_base_r[arithmetic_stage-1];
                for (arithmetic_stage = 4; arithmetic_stage < 7;
                    arithmetic_stage = arithmetic_stage + 1)
                    if (pipe_valid_r[arithmetic_stage-1]) begin
                        source_shift_r[arithmetic_stage][pixel] <=
                            source_shift_r[arithmetic_stage-1][pixel];
                        source_mask_r[arithmetic_stage][pixel] <=
                            source_mask_r[arithmetic_stage-1][pixel];
                    end
                for (arithmetic_stage = 2; arithmetic_stage < 5;
                    arithmetic_stage = arithmetic_stage + 1)
                    if (pipe_valid_r[arithmetic_stage-1])
                        fill_coverage_r[arithmetic_stage] <= fill_coverage_r[arithmetic_stage-1];
                for (arithmetic_stage = 2; arithmetic_stage < 3;
                    arithmetic_stage = arithmetic_stage + 1)
                    if (pipe_valid_r[arithmetic_stage-1])
                        fill_inner_r[arithmetic_stage] <= fill_inner_r[arithmetic_stage-1];
                for (arithmetic_stage = 4; arithmetic_stage < 7;
                    arithmetic_stage = arithmetic_stage + 1)
                    if (pipe_valid_r[arithmetic_stage-1])
                        fill_color_r[arithmetic_stage] <= fill_color_r[arithmetic_stage-1];
            end
        end
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
                    {sample_line_r[cache_lane], 5'd0}) begin
                    lane_low_hit_w[cache_lane] = 1'b1;
                    lane_cache_low_w[cache_lane] = cache_data_r[cache_entry];
                    if (cache_lane == 0 || pipe_tag_r[4][29])
                        cache_needed_w = 1'b1;
                end
                if (cache_valid_r[cache_entry] &&
                    cache_addr_r[cache_entry] == lane_next_w[cache_lane]) begin
                    lane_high_hit_w[cache_lane] = 1'b1;
                    lane_cache_high_w[cache_lane] = cache_data_r[cache_entry];
                    if (lane_cross_w[cache_lane] && (cache_lane == 0 || pipe_tag_r[4][29]))
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
                .rd_en_i(source_bank_w == bank && pipe_valid_r[4] &&
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
                .rd_en_i(source_bank_w == bank && pipe_valid_r[4] &&
                    pipeline_step_w && !cancel_i),
                .rd_addr_i(source_index_r[pixel] + 9'd1),
                .rd_data_o(source_next_w[bank][pixel])
            );
            edrv32_ram_rnd_palette u_map (
                .clk_i(clk_i),
                .wr_en_i(load_bank_r == bank && load_state_r == S_TILE_ADDR && !cancel_i),
                .wr_addr_i(tile_index_r),
                .wr_data_i({9'd0, tile_row_base_w[6:0], tile_entry_r}),
                .rd_en_i(render_read_w),
                .rd_addr_i(issue_map_index_w[pixel]),
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
            if (write_start_w || affine_skip_write_w)
                rendered_r[write_bank_r] <= 1'b0;
            if (write_finish_w) begin
                busy_r[write_bank_r] <= 1'b0;
                if (bank_y_r[write_bank_r] == clip_bottom_r &&
                    bank_right_r[write_bank_r] == clip_right_r) begin
                    active_r <= 1'b0;
                    done_r <= 1'b1;
                end
            end
        end
    end
    // Multipliers have explicit input/output registers; payload never needs reset.
    always @(posedge clk_i) begin
        if (start_i) begin
            dst_y_r <= top_w[11:0];
            clip_left_bytes_r <= argb_w ? {left_w[11:0], 2'd0} :
                {1'b0, left_w[11:0], 1'b0};
            clip_right_bytes_r <= argb_w ? {right_w[11:0], 2'd0} :
                {1'b0, right_w[11:0], 1'b0};
            recolor_inverse_r <= 8'd255 - command_i[511:504];
            for (lane = 0; lane < 3; lane = lane + 1)
                recolor_product_r[lane] <= command_i[511:504] *
                    command_i[480+lane*8 +: 8];
            gradient_bias_r[0] <= {command_i[319:312], 1'b1, 15'd0};
            gradient_bias_r[1] <= {command_i[311:304], 1'b1, 15'd0};
            gradient_bias_r[2] <= {command_i[303:296], 1'b1, 15'd0};
            gradient_bias_r[3] <= {command_i[295:288], 1'b1, 15'd0};
            source_last_base_r <= command_i[287:256] + (format_w == 4'd1 ? 32'd3 :
                format_w == 4'd0 ? 32'd1 : 32'd0);
            map_x_offset_r <= {16'd0, command_i[367:352]} -
                {{16{command_i[175]}}, command_i[175:160]};
            map_y_offset_r <= {16'd0, command_i[383:368]} -
                {{16{command_i[191]}}, command_i[191:176]};
        end
        // The parent publishes effective stride on the start edge (rnd 5.2).
        if (load_state_r == S_RADIUS) begin
            source_stride_r <= source_stride_i[17:0];
            tile_last_offset_r <= tile_last_offset_w[5:0];
            for (lane = 0; lane < 3; lane = lane + 1)
                recolor_bias_r[lane] <= recolor_product_r[lane] + 16'd128;
        end
        // Target descriptors own their captured address; prepare the following row now.
        if (load_state_r == S_BOUNDS)
            dst_y_r <= affine_w ? affine_next_y_w :
                load_last_r ? load_y_r + 12'd1 : load_y_r;
        dst_row_product_r <= dst_y_r * command_i[79:64];
        dst_row_base_r <= command_i[63:32] + dst_row_product_r;
        row_start_r <= dst_row_base_r + {18'd0, clip_left_bytes_r};
        clip_end_r <= clip_end_w[10:0];
        if (load_state_r == S_ROW) begin
            load_dst_r <= affine_w ? dst_row_base_r + affine_row_left_bytes_w : row_start_r;
            chunk_right_r <= {1'b0, clip_left_r} + 13'd511 -
                (argb_w ? {10'd0, row_start_r[4:2]} : {9'd0, row_start_r[4:1]});
        end
        if (load_state_r == S_LOADED) begin
            if (load_last_r)
                load_dst_r <= row_start_r;
            else begin
                load_dst_r <= {next_target_word_w,
                    argb_w ? {3'd0, load_dst_r[1:0]} : {4'd0, load_dst_r[0]}};
                // Following chunks begin at a beat, retaining only the pixel-byte remainder.
                chunk_right_r <= {1'b0, load_right_r} + 13'd512;
            end
        end
        if (load_state_r == S_CHUNK && !busy_r[load_bank_r] && !loaded_all_r)
            load_last_r <= affine_w || chunk_right_w >= {1'b0, clip_right_r};
        bounds_ky_r <= bounds_ky_w[15:0];
        bounds_scaled_y_r <= bounds_ky_r * command_i[415:384];
        bounds_y_r <= bounds_ky_r;
        bounds_v_r <= {16'd0, command_i[351:336]} +
            (op_w == 8'h04 ? bounds_scaled_y_r[47:16] : {16'd0, bounds_y_r});
        // v*SRC_STRIDE + v*(effective_stride-SRC_STRIDE) is v*effective_stride modulo 2^32.
        bounds_row_product_r <= bounds_v_r * source_stride_r;
        bounds_row_base_r <= command_i[287:256] + bounds_row_product_r;
        bounds_row_last_base_r <= source_last_base_r + bounds_row_product_r;
        for (bounds_lane = 0; bounds_lane < 2; bounds_lane = bounds_lane + 1) begin
            bounds_kx_r[bounds_lane] <= bounds_kx_w[bounds_lane][15:0];
            bounds_scaled_x_r[bounds_lane] <= bounds_kx_r[bounds_lane] * command_i[383:352];
            bounds_x_r[bounds_lane] <= bounds_kx_r[bounds_lane];
            bounds_u_r[bounds_lane] <= {16'd0, command_i[335:320]} +
                (op_w == 8'h04 ? bounds_scaled_x_r[bounds_lane][47:16] :
                    {16'd0, bounds_x_r[bounds_lane]});
            bounds_byte_r[bounds_lane] <= bounds_bits_w[bounds_lane][34:3];
            bounds_byte_delay_r[bounds_lane] <= bounds_byte_r[bounds_lane];
            bounds_addr_r[bounds_lane] <= bounds_row_base_r + bounds_byte_delay_r[bounds_lane];
            bounds_last_addr_r[bounds_lane] <= bounds_row_last_base_r +
                bounds_byte_delay_r[bounds_lane];
        end
        bounds_first_r <= {bounds_min_word_w, 5'd0};
        // Compare the original addresses, preserving wrap at the last pixel byte.
        bounds_last_r <= bounds_addr_r[0] > bounds_addr_r[1] ?
            bounds_last_addr_r[0] : bounds_last_addr_r[1];
        map_x_r <= map_x_w[16:0];
        map_y_r <= map_y_w[16:0];
        map_row_r <= flags_w[0] ? {1'b0, map_y_r[16:4]} : map_y_r[16:3];
        map_column_r <= ({15'd0, map_x_r} >> tile_log2_w) << 1;
        map_row_product_r <= map_row_r * command_i[335:320];
        map_row_base_r <= command_i[319:288] + map_row_product_r;
        load_map_r <= map_row_base_r + map_column_r;
        if (load_state_r == S_TILE_MAP && map_hit_w) begin
            tile_row_pixel_r <= ({20'd0, map_shift_w[11:0]} << (tile_log2_w << 1)) |
                (tile_pixel_y_w << tile_log2_w);
            tile_next_x_r <= next_tile_x_w;
        end
    end
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            bounds_valid_r <= 7'd0;
            bounds_ready_r <= 1'b0;
        end else if (cancel_i || start_i) begin
            bounds_valid_r <= 7'd0;
            bounds_ready_r <= 1'b0;
        end else begin
            bounds_valid_r <= {bounds_valid_r[5:0],
                load_state_r == S_CHUNK && !loaded_all_r && !fill_w && !tile_w &&
                    !bounds_ready_r && bounds_valid_r == 0};
            if (load_state_r == S_LOADED)
                bounds_ready_r <= 1'b0;
            if (bounds_valid_r[6])
                bounds_ready_r <= 1'b1;
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
                ((op_w == 8'h04 || tile_w || affine_w) && format_w >= 4'd6 ?
                    S_PALETTE_REQ : S_RADIUS);
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
                    inner_r <= shape_w;
                    inner_inside_r <= shape_w &&
                        $signed({6'd0, load_y_r}) >= inner_top_r &&
                        $signed({6'd0, load_y_r}) <= inner_bottom_r;
                    load_state_r <= round_fill_w || shape_w ? S_EDGE_REQ : S_CHUNK;
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
                    load_right_r <= chunk_end_w;
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
                    load_state_r <= solid_w ? S_LOADED : tile_w ? S_TILE_MAP :
                        bounds_available_w ? (bounds_sparse_w ? S_LOADED : S_SOURCE_REQ) :
                            S_TARGET_END;
                S_TARGET_END: if (bounds_available_w)
                    load_state_r <= bounds_sparse_w ? S_LOADED : S_SOURCE_REQ;
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
                S_TILE_NEXT: if (tile_next_x_r > {1'b0, load_right_r})
                    load_state_r <= S_LOADED;
                else begin
                    tile_x_r <= tile_next_x_r[11:0];
                    tile_index_r <= tile_index_r + 8'd1;
                    load_state_r <= S_TILE_MAP;
                end
                S_LOADED: begin
                    load_bank_r <= !load_bank_r;
                    if (affine_w) begin
                        load_left_r <= affine_next_left_w;
                        load_y_r <= affine_next_y_w;
                        if (load_y_r == clip_bottom_r && load_right_r == clip_right_r) begin
                            loaded_all_r <= 1'b1;
                            load_state_r <= S_IDLE;
                        end else
                            load_state_r <= S_ROW;
                    end else if (load_last_r) begin
                        if (load_y_r == clip_bottom_r) begin
                            loaded_all_r <= 1'b1;
                            load_state_r <= S_IDLE;
                        end else begin
                            load_left_r <= clip_left_r;
                            tile_x_r <= clip_left_r;
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
            clip_left_r <= left_w[11:0];
            clip_right_r <= right_w[11:0];
            clip_bottom_r <= bottom_w[11:0];
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
            inner_left_r <= shape_w ? shape_left_w : inner_left_w;
            inner_top_r <= shape_w ? shape_top_w : inner_top_w;
            inner_right_r <= shape_w ? shape_right_w : inner_right_w;
            inner_bottom_r <= shape_w ? shape_bottom_w : inner_bottom_w;
            inner_radius_r <= shape_w ? shape_radius_w : radius_r > command_i[299:288] ?
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
            if (solid_w || tile_w)
                bank_sparse_r[load_bank_r] <= 1'b0;
            bank_target_r[load_bank_r] <= {load_dst_w[31:5], 5'd0};
            bank_bytes_r[load_bank_r] <= target_bytes_w[15:0];
            bank_first_byte_r[load_bank_r] <= load_dst_w[4:0];
            bank_last_byte_r[load_bank_r] <= target_last_start_w + (argb_w ? 5'd3 : 5'd1);
            bank_tile_first_r[load_bank_r] <=
                (({20'd0, load_left_r} + map_x_offset_r) >> tile_log2_w);
            bank_outer_edge_r[load_bank_r] <= outer_edge_r;
            bank_inner_edge_r[load_bank_r] <= inner_edge_r;
            bank_inner_inside_r[load_bank_r] <= inner_inside_r;
        end
        if (load_state_r == S_TILE_MAP && map_hit_w)
            tile_entry_r <= map_shift_w[15:0];
        // Prepare while the next bank is busy, then publish only after CHUNK acquires it.
        // The existing arithmetic registers hold this chunk until LOADED advances its geometry.
        if ((load_state_r == S_BOUNDS && bounds_ready_r) ||
            (bounds_valid_r[6] && load_state_r != S_CHUNK)) begin
            bank_source_r[load_bank_r] <= bounds_first_r;
            bank_source_row_r[load_bank_r] <= bounds_row_base_r;
            bank_sparse_r[load_bank_r] <= bounds_sparse_result_w;
            load_source_base_r <= bounds_first_r;
            load_source_bytes_r <= bounds_span_w[15:0];
        end
        if (load_state_r == S_TILE_ADDR) begin
            load_source_base_r <= {tile_row_base_w[31:5], 5'd0};
            load_source_bytes_r <= tile_bytes_w[15:0];
        end
        if (load_accept_w && load_state_r == S_MAP_REQ)
            map_addr_r <= {load_map_r[31:5], 5'd0};
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
            pipe_valid_r <= 10'd0;
        end else if (cancel_i || start_i) begin
            render_state_r <= S_RENDER_IDLE;
            render_bank_r <= 1'b0;
            pipe_valid_r <= 10'd0;
        end else begin
            if (affine_w) begin
                if (affine_input_step_w)
                    pipe_valid_r[0] <= issue_w;
                pipe_valid_r[6:1] <= 6'd0;
                if (pipeline_step_w)
                    pipe_valid_r[9:7] <= {pipe_valid_r[8:7], affine_valid_w};
            end else if (pipeline_step_w)
                pipe_valid_r <= {pipe_valid_r[8:0], issue_w};
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
        if (issue_w) begin
            pipe_tag_r[0] <= {render_bank_r, issue_last_w, issue_pair_w,
                15'd0, issue_offset_w[13:0]};
            coverage_outer_x0_r <= $signed({6'd0, issue_x_r}) - rect_left_r;
            coverage_inner_x0_r <= $signed({6'd0, issue_x_r}) - inner_left_r;
        end
        if (g_step_ctrl[2].step_w) begin
            for (stage = 1; stage < 10; stage = stage + 1)
                if (pipe_valid_r[stage-1])
                    pipe_tag_r[stage] <= pipe_tag_r[stage-1];
            if (pipe_valid_r[1])
                sample_base2_r <= tile_w ? command_i[287:256] :
                    bank_source_row_r[pipe_tag_r[1][31]];
            if (pipe_valid_r[0])
                pipe_dst_r[1] <= argb_w ? target_shift_w[63:0] :
                    {16'd0, target_shift_w[31:16], 16'd0, target_shift_w[15:0]};
            for (stage = 2; stage < 10; stage = stage + 1)
                if (pipe_valid_r[stage-1])
                    pipe_dst_r[stage] <= pipe_dst_r[stage-1];
            if (affine_w && affine_valid_w) begin
                pipe_dst_r[7] <= {32'd0, affine_destination_w};
                pipe_tag_r[7] <= affine_tag_w;
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
                S_WRITE_IDLE: begin
                    if (affine_skip_write_w)
                        write_bank_r <= !write_bank_r;
                    else if (write_start_w)
                        write_state_r <= S_WRITE_DESC;
                end
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
    edrv32_rnd_affine u_affine (
        .clk_i(clk_i),
        .rst_n_i(rst_affine_n_i),
        .clear_i(cancel_i),
        .start_i(start_i && affine_w),
        .command_i({command_i[511:32], affine_control_i}),
        .parameters_i(parameters_i),
        .left_i(left_w[11:0]),
        .top_i(top_w[11:0]),
        .right_i(right_w[11:0]),
        .bottom_i(bottom_w[11:0]),
        .in_valid_i(pipe_valid_r[0] && affine_w),
        .in_ready_o(affine_ready_w),
        .destination_i(argb_w ? target_shift_w[31:0] : {16'd0, target_shift_w[15:0]}),
        .tag_i(pipe_tag_r[0]),
        .coverage_i(affine_input_cov_w),
        .out_valid_o(affine_valid_w),
        .out_ready_i(pipeline_step_w),
        .pixel_o(affine_pixel_w),
        .destination_o(affine_destination_w),
        .tag_o(affine_tag_w),
        .coverage_o(affine_coverage_w),
        .read_wait_o(affine_read_wait_w),
        .rd_valid_o(affine_rd_valid_w),
        .rd_ready_i(rd_valid_o && rd_ready_i && miss_request_w && affine_w),
        .rd_addr_o(affine_rd_addr_w),
        .rd_bytes_o(affine_rd_bytes_w),
        .rd_data_valid_i(rd_data_valid_i && read_busy_r && read_render_r && affine_w),
        .rd_data_i(rd_data_i),
        .rd_done_i(rd_done_i && read_busy_r && read_render_r && affine_w),
        .palette_valid_o(affine_palette_valid_w),
        .palette_index_o(affine_palette_index_w),
        .palette_data_i({palette_data_w[1], palette_data_w[0]})
    );
    always @(posedge clk_i) begin
        if (start_i) begin
            // Decode is combinational, unlike RECT data registers written on this edge.
            affine_tile_left_r <= left_w[11:0];
            affine_tile_top_r <= top_w[11:0];
            affine_tile_right_r <= affine_first_right_w < {1'b0, right_w[11:0]} ?
                affine_first_right_w[11:0] : right_w[11:0];
            affine_tile_bottom_r <= affine_first_bottom_w < {1'b0, bottom_w[11:0]} ?
                affine_first_bottom_w[11:0] : bottom_w[11:0];
        end else if (load_state_r == S_LOADED && affine_w && load_y_r == affine_tile_bottom_r) begin
            if (affine_tile_right_r < clip_right_r) begin
                affine_tile_left_r <= affine_tile_right_r + 12'd1;
                affine_tile_right_r <= affine_next_right_w < {1'b0, clip_right_r} ?
                    affine_next_right_w[11:0] : clip_right_r;
            end else begin
                affine_tile_left_r <= clip_left_r;
                affine_tile_right_r <= affine_first_right_w < {1'b0, clip_right_r} ?
                    affine_first_right_w[11:0] : clip_right_r;
                affine_tile_top_r <= affine_tile_bottom_r + 12'd1;
                affine_tile_bottom_r <= affine_next_bottom_w < {1'b0, clip_bottom_r} ?
                    affine_next_bottom_w[11:0] : clip_bottom_r;
            end
        end
    end
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i)
            affine_has_write_r <= 2'd0;
        else if (cancel_i || start_i)
            affine_has_write_r <= 2'd0;
        else begin
            if (load_state_r == S_CHUNK && !busy_r[load_bank_r])
                affine_has_write_r[load_bank_r] <= 1'b0;
            if (blend_valid_i && blend_tag_i[28])
                affine_has_write_r[blend_tag_i[31]] <= 1'b1;
        end
    end
    genvar write_bank;
    genvar write_word;
    generate for (write_bank = 0; write_bank < 2; write_bank = write_bank + 1) begin : g_mask_bank
        localparam [0:0] BANK = write_bank == 1;
        for (write_word = 0; write_word < 8; write_word = write_word + 1) begin : g_mask_word
            localparam [2:0] WORD = write_word;
            reg [31:0] mask_r;
            assign affine_write_mask_w[write_bank][write_word] = mask_r;
            always @(posedge clk_i) begin
                if (affine_w && load_data_w && load_state_r == S_TARGET_DATA &&
                    load_bank_r == BANK && load_beat_r[2:0] == WORD)
                    mask_r <= 32'd0;
                if (affine_w && blend_valid_i && blend_tag_i[28] &&
                    blend_tag_i[31] == BANK && blend_tag_i[7:5] == WORD)
                    mask_r <= mask_r | result_write_strb_w;
            end
        end
    end endgenerate
    edrv32_rnd_geometry u_geometry (
        .clk_i(clk_i),
        .rst_n_i(rst_geometry_n_i),
        .clear_i(cancel_i),
        .start_i(start_i && geometry_w),
        .out_ready_i(pipe_valid_r[7] && pipeline_step_w),
        .command_i({command_i[511:32], geometry_control_i}),
        .parameters_i(parameters_i),
        .left_i(left_w[11:0]),
        .top_i(top_w[11:0]),
        .request_i(issue_w && geometry_w),
        .ready_o(geometry_ready_w),
        .row_end_i(issue_x_r >= clip_right_r),
        .valid_o(geometry_valid_w),
        .coverage_o(geometry_cov_w)
    );
    always @(posedge clk_i) begin
        if (g_step_ctrl[3].step_w) begin
            geometry_cov_r[8] <= geometry_cov_w;
            geometry_cov_r[9] <= geometry_cov_r[8];
        end
    end
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i)
            post_valid_r <= 2'd0;
        else if (cancel_i || start_i)
            post_valid_r <= 2'd0;
        else if (pipeline_step_w)
            post_valid_r <= {post_valid_r[0], pipe_valid_r[9] && post_w};
    end
    always @(posedge clk_i) begin
        if (g_step_ctrl[3].step_w) begin
            post_src0_r <= pipe_src_r;
            post_dst_r[0] <= pipe_dst_r[9];
            post_dst_r[1] <= post_dst_r[0];
            post_tag_r[0] <= pipe_tag_r[9];
            post_tag_r[1] <= post_tag_r[0];
        end
    end
    assign unused_geometry_w = ^{left_w[17:12], right_w[17:12], top_w[17:12], bottom_w[17:12],
        row_local_w[17], row_width_w[17], row_height_w[17], inner_width_r[17],
        inner_height_r[17], target_shift_w[255:64],
        blend_tag_i[28:14], flags_w[15:4],
        affine_offset_x_w[17:5], affine_offset_y_w[17:4], post_src0_r[63:56], post_src0_r[31:24],
        map_shift_w[255:16], palette_shift_w[255:32],
        target_offset_w[31:5], issue_offset_w[31:14], clip_end_w[31:11],
        tile_bytes_w[31:16], tile_last_offset_w[31:6], tile_end_offset_w[4:0],
        bounds_last_r[4:0],
        bounds_kx_w[0][31:16], bounds_scaled_x_r[0][15:0],
        bounds_kx_w[1][31:16], bounds_scaled_x_r[1][15:0],
        bounds_ky_w[31:16], bounds_scaled_y_r[15:0], bounds_bits_w[0][2:0],
        bounds_bits_w[1][2:0], bounds_span_w[4:0],
        tile_row_bits_w[2:0], tile_entry_r[15:14], tile_entry_r[12],
        source_stride_i[31:18], map_x_w[31:17], map_y_w[31:17]};
endmodule
