// File: edrv32_rnd_blur.v
// Spec: rnd-spec v0.2 2.3, 2.4, 2.6 BOX_SHADOW/BLUR.
// Description: Generate a shadow seed and execute separable fixed-point box-filter passes.
//              DDR scratch preserves full 8-bit channels; each pass fences its writes.
// Clock domain: clk_mem (clk_i).
module edrv32_rnd_blur (
    // Clock and reset.
    input wire clk_i,
    input wire rst_n_i,

    // One blur/shadow command, stable until completion.
    input wire start_i,
    input wire cancel_i,
    input wire [511:0] command_i,
    output wire done_o,
    output wire [4:0] pixel_count_o,
    output wire [511:0] shadow_draw_o,
    output wire [31:0] shadow_stride_o,

    // One-beat read client.
    output wire rd_valid_o,
    input wire rd_ready_i,
    output wire [31:0] rd_addr_o,
    input wire rd_data_valid_i,
    input wire [255:0] rd_data_i,

    // One-beat writes; done is the DDR response fence.
    output wire wr_valid_o,
    input wire wr_ready_i,
    output wire [31:0] wr_addr_o,
    output wire [255:0] wr_data_o,
    output wire [31:0] wr_strb_o,
    input wire wr_done_i
);
    localparam [4:0] S_IDLE = 5'd0;
    localparam [4:0] S_COEFF = 5'd1;
    localparam [4:0] S_COEFF_WAIT = 5'd2;
    localparam [4:0] S_ROW = 5'd3;
    localparam [4:0] S_EDGE = 5'd4;
    localparam [4:0] S_EDGE_WAIT = 5'd5;
    localparam [4:0] S_PIXEL = 5'd6;
    localparam [4:0] S_SAMPLE = 5'd7;
    localparam [4:0] S_READ = 5'd8;
    localparam [4:0] S_READ_WAIT = 5'd9;
    localparam [4:0] S_ADD = 5'd10;
    localparam [4:0] S_NORMALIZE = 5'd11;
    localparam [4:0] S_NORMALIZE_WAIT = 5'd12;
    localparam [4:0] S_OUTPUT = 5'd13;
    localparam [4:0] S_STORE = 5'd14;
    localparam [4:0] S_WRITE = 5'd15;
    localparam [4:0] S_WRITE_WAIT = 5'd16;
    localparam [4:0] S_NEXT_ROW = 5'd17;
    localparam [4:0] S_DONE = 5'd18;
    reg [4:0] state_r;
    reg [4:0] write_return_r;
    reg [1:0] phase_r;
    reg signed [17:0] x_r;
    reg signed [17:0] y_r;
    reg signed [6:0] tap_r;
    reg [55:0] sum_r;
    reg [31:0] output_pixel_r;
    reg [15:0] edge_r;
    reg cache_valid_r;
    reg [31:0] cache_addr_r;
    reg [255:0] cache_data_r;
    reg work_valid_r;
    reg [31:0] work_addr_r;
    reg [255:0] work_data_r;
    reg [31:0] work_strb_r;
    reg [4:0] pixel_count_r;
    wire shadow_w;
    wire argb_w;
    wire [4:0] radius_w;
    reg signed [17:0] drawing_left_r;
    reg signed [17:0] drawing_top_r;
    reg signed [17:0] drawing_right_r;
    reg signed [17:0] drawing_bottom_r;
    wire signed [17:0] rect_left_w;
    wire signed [17:0] rect_top_w;
    wire signed [17:0] rect_right_w;
    wire signed [17:0] rect_bottom_w;
    reg signed [17:0] left_r;
    reg signed [17:0] top_r;
    reg signed [17:0] right_r;
    reg signed [17:0] bottom_r;
    reg signed [17:0] raw_left_r;
    reg [11:0] clip_left_r;
    reg [9:0] expanded_left_low_r;
    reg [8:0] expanded_left_high_r;
    reg signed [17:0] expanded_left_r;
    reg signed [17:0] raw_top_r;
    reg [11:0] clip_top_r;
    reg [9:0] expanded_top_low_r;
    reg [8:0] expanded_top_high_r;
    reg signed [17:0] expanded_top_r;
    reg signed [17:0] raw_right_r;
    reg [11:0] clip_right_r;
    reg [9:0] expanded_right_low_r;
    reg [8:0] expanded_right_high_r;
    reg signed [17:0] expanded_right_r;
    reg signed [17:0] raw_bottom_r;
    reg [11:0] clip_bottom_r;
    reg [9:0] expanded_bottom_low_r;
    reg [8:0] expanded_bottom_high_r;
    reg signed [17:0] expanded_bottom_r;
    reg shadow_r;
    reg [4:0] radius_r;
    reg [9:0] grid_width_low_r;
    reg [7:0] grid_width_high_r;
    reg [8:0] rect_width_low_r;
    reg [8:0] rect_width_high_r;
    reg [16:0] grid_width_delta_r;
    reg [9:0] grid_height_low_r;
    reg [7:0] grid_height_high_r;
    reg [8:0] rect_height_low_r;
    reg [8:0] rect_height_high_r;
    reg [16:0] grid_height_delta_r;
    reg signed [16:0] rect_width_delta_r;
    reg signed [16:0] rect_height_delta_r;
    reg [16:0] width_r;
    reg [16:0] height_r;
    reg [16:0] row_local_r;
    reg signed [17:0] rect_row_coordinate_r;
    reg signed [17:0] coverage_x_r;
    reg rect_row_inside_r;
    reg [14:0] dst_offset_low_r;
    reg [13:0] dst_offset_high_r;
    reg [27:0] dst_offset_r;
    reg [2:0] source_bytes_r;
    reg [2:0] output_bytes_r;
    reg [16:0] grid_width_r;
    reg [16:0] grid_height_r;
    reg [16:0] stride_r;
    reg [33:0] temp_product_r;
    reg [31:0] temp1_r;
    reg [27:0] dst_product_r;
    reg [11:0] dst_y_r;
    reg [13:0] dst_column_r;
    reg [31:0] dst_origin_r;
    reg [16:0] source_stride_r;
    reg [16:0] output_stride_r;
    reg [16:0] sample_step_r;
    reg [31:0] source_first_row_r;
    reg [31:0] first_addr_r;
    reg [31:0] output_row_r;
    reg [31:0] output_addr_r;
    reg [31:0] sample_addr_r;
    reg sample_advance_r;
    reg last_pixel_r;
    reg last_row_r;
    reg [31:0] store_mask_r;
    reg [31:0] store_pixel_r;
    wire [31:0] packed_pixel_w;
    reg [16:0] column_distance_r;
    reg [16:0] column_remaining_r;
    reg [16:0] row_distance_r;
    reg [16:0] row_remaining_r;
    reg [9:0] row_remaining_low_r;
    reg signed [6:0] tap_min_r;
    reg signed [6:0] tap_max_r;
    wire [16:0] distance_before_w;
    wire [16:0] distance_after_w;
    reg [12:0] sample_low_r;
    reg [12:0] sample_mid_zero_r;
    reg [12:0] sample_mid_one_r;
    reg [7:0] sample_high_r;
    wire [12:0] sample_mid_w;
    reg [31:0] sample_pixel_r;
    wire [2:0] source_pixel_bytes_w;
    wire [2:0] output_pixel_bytes_w;
    wire sample_advance_w;
    wire first_x_advance_w;
    reg first_x_advance_r;
    reg first_y_advance_r;
    wire first_y_advance_w;
    wire [31:0] next_source_row_w;
    wire [31:0] next_source_origin_w;
    wire [31:0] next_output_origin_w;
    wire [255:0] sample_data_w;
    wire [17:0] stride_round_w;
    wire [31:0] temp0_w;
    wire horizontal_w;
    wire seed_w;
    wire outside_w;
    wire [255:0] sample_shift_w;
    wire [31:0] sample_pixel_w;
    wire [31:0] raw_pixel_w;
    wire [16:0] coefficient_w;
    wire coefficient_ready_w;
    wire coefficient_valid_w;
    wire math_ready_w;
    wire math_valid_w;
    wire [63:0] math_pixel_w;
    wire round_ready_w;
    wire round_valid_w;
    wire [15:0] round_edge_w;
    wire [11:0] unused_radius_w;
    wire [15:0] coverage_w;
    wire rect_row_inside_w;
    reg [15:0] shadow_src_x_r;
    reg [15:0] shadow_src_y_r;
    reg [8:0] shadow_x_low_r;
    reg [8:0] shadow_y_low_r;
    reg [7:0] shadow_x_high_r;
    reg [7:0] shadow_y_high_r;
    wire [17:0] shadow_x1_w;
    wire [17:0] shadow_y1_w;
    wire unused_data_w;
    reg [511:0] shadow_draw_w;
    wire [31:0] temp_base_a_w;
    wire [31:0] temp_base_b_w;
    reg [12:0] temp_base_low_r;
    reg [12:0] temp_base_mid_r;
    reg [7:0] temp_base_high_r;
    reg [11:0] temp_base_low_delay_r;
    reg [12:0] temp_base_mid_carry_r;
    reg [7:0] temp_base_high_delay_r;
    wire [31:0] temp_base_result_w;
    wire [31:0] dst_base_a_w;
    wire [31:0] dst_base_b_w;
    reg [12:0] dst_base_low_r;
    reg [12:0] dst_base_mid_r;
    reg [7:0] dst_base_high_r;
    reg [11:0] dst_base_low_delay_r;
    reg [12:0] dst_base_mid_carry_r;
    reg [7:0] dst_base_high_delay_r;
    wire [31:0] dst_base_result_w;
    wire [31:0] src_row_a_w;
    wire [31:0] src_row_b_w;
    reg [12:0] src_row_low_r;
    reg [12:0] src_row_mid_r;
    reg [7:0] src_row_high_r;
    reg [11:0] src_row_low_delay_r;
    reg [12:0] src_row_mid_carry_r;
    reg [7:0] src_row_high_delay_r;
    wire [31:0] src_row_result_w;
    wire [31:0] out_row_a_w;
    wire [31:0] out_row_b_w;
    reg [12:0] out_row_low_r;
    reg [12:0] out_row_mid_r;
    reg [7:0] out_row_high_r;
    reg [11:0] out_row_low_delay_r;
    reg [12:0] out_row_mid_carry_r;
    reg [7:0] out_row_high_delay_r;
    wire [31:0] out_row_result_w;
    wire [31:0] src_pixel_a_w;
    wire [31:0] src_pixel_b_w;
    reg [12:0] src_pixel_low_r;
    reg [12:0] src_pixel_mid_r;
    reg [7:0] src_pixel_high_r;
    reg [11:0] src_pixel_low_delay_r;
    reg [12:0] src_pixel_mid_carry_r;
    reg [7:0] src_pixel_high_delay_r;
    wire [31:0] src_pixel_result_w;
    wire [31:0] out_pixel_a_w;
    wire [31:0] out_pixel_b_w;
    reg [12:0] out_pixel_low_r;
    reg [12:0] out_pixel_mid_r;
    reg [7:0] out_pixel_high_r;
    reg [11:0] out_pixel_low_delay_r;
    reg [12:0] out_pixel_mid_carry_r;
    reg [7:0] out_pixel_high_delay_r;
    wire [31:0] out_pixel_result_w;
    reg raw_left_high_take_r;
    reg raw_left_high_equal_r;
    reg raw_left_low_take_r;
    reg raw_left_take_r;
    reg draw_left_high_take_r;
    reg draw_left_high_equal_r;
    reg draw_left_low_take_r;
    reg draw_left_take_r;
    reg raw_top_high_take_r;
    reg raw_top_high_equal_r;
    reg raw_top_low_take_r;
    reg raw_top_take_r;
    reg draw_top_high_take_r;
    reg draw_top_high_equal_r;
    reg draw_top_low_take_r;
    reg draw_top_take_r;
    reg raw_right_high_take_r;
    reg raw_right_high_equal_r;
    reg raw_right_low_take_r;
    reg raw_right_take_r;
    reg draw_right_high_take_r;
    reg draw_right_high_equal_r;
    reg draw_right_low_take_r;
    reg draw_right_take_r;
    reg raw_bottom_high_take_r;
    reg raw_bottom_high_equal_r;
    reg raw_bottom_low_take_r;
    reg raw_bottom_take_r;
    reg draw_bottom_high_take_r;
    reg draw_bottom_high_equal_r;
    reg draw_bottom_low_take_r;
    reg draw_bottom_take_r;
    integer channel;
    integer byte_lane;

    assign argb_w = command_i[8];
    assign temp_base_a_w = temp0_w;
    assign temp_base_b_w = temp_product_r[31:0];
    assign temp_base_result_w = {temp_base_high_delay_r + {7'd0, temp_base_mid_carry_r[12]},
        temp_base_mid_carry_r[11:0], temp_base_low_delay_r};
    assign dst_base_a_w = command_i[63:32];
    assign dst_base_b_w = {4'd0, dst_offset_r};
    assign dst_base_result_w = {dst_base_high_delay_r + {7'd0, dst_base_mid_carry_r[12]},
        dst_base_mid_carry_r[11:0], dst_base_low_delay_r};
    assign src_row_a_w = source_first_row_r;
    assign src_row_b_w = {15'd0, source_stride_r};
    assign src_row_result_w = {src_row_high_delay_r + {7'd0, src_row_mid_carry_r[12]},
        src_row_mid_carry_r[11:0], src_row_low_delay_r};
    assign out_row_a_w = output_row_r;
    assign out_row_b_w = {15'd0, output_stride_r};
    assign out_row_result_w = {out_row_high_delay_r + {7'd0, out_row_mid_carry_r[12]},
        out_row_mid_carry_r[11:0], out_row_low_delay_r};
    assign src_pixel_a_w = first_addr_r;
    assign src_pixel_b_w = {29'd0, source_bytes_r};
    assign src_pixel_result_w = {src_pixel_high_delay_r + {7'd0, src_pixel_mid_carry_r[12]},
        src_pixel_mid_carry_r[11:0], src_pixel_low_delay_r};
    assign out_pixel_a_w = output_addr_r;
    assign out_pixel_b_w = {29'd0, output_bytes_r};
    assign out_pixel_result_w = {out_pixel_high_delay_r + {7'd0, out_pixel_mid_carry_r[12]},
        out_pixel_mid_carry_r[11:0], out_pixel_low_delay_r};
    assign shadow_w = command_i[7:0] == 8'h06;
    assign radius_w = shadow_w ? command_i[292:288] : command_i[260:256];
    assign rect_left_w = {{2{command_i[175]}}, command_i[175:160]};
    assign rect_top_w = {{2{command_i[191]}}, command_i[191:176]};
    assign rect_right_w = {{2{command_i[207]}}, command_i[207:192]};
    assign rect_bottom_w = {{2{command_i[223]}}, command_i[223:208]};
    assign stride_round_w = ({1'b0, grid_width_r} << (shadow_r ? 0 : 2)) + 18'd31;
    assign temp0_w = shadow_r ? command_i[351:320] : command_i[319:288];
    assign seed_w = shadow_r && phase_r == 0;
    assign horizontal_w = shadow_r ? phase_r == 1 : phase_r == 0;
    assign source_pixel_bytes_w = shadow_r ? 3'd1 : horizontal_w && !argb_w ? 3'd2 : 3'd4;
    assign output_pixel_bytes_w = shadow_r ? 3'd1 : !horizontal_w && !argb_w ? 3'd2 : 3'd4;
    assign distance_before_w = horizontal_w ? column_distance_r : row_distance_r;
    assign distance_after_w = horizontal_w ? column_remaining_r : row_remaining_r;
    assign outside_w = shadow_r && (tap_r < tap_min_r || tap_r > tap_max_r);
    assign sample_advance_w = tap_r >= tap_min_r && tap_r < tap_max_r;
    assign first_x_advance_w = !horizontal_w || |column_distance_r[16:5] ||
        column_distance_r[4:0] >= radius_r;
    assign first_y_advance_w = horizontal_w || |row_distance_r[16:5] ||
        row_distance_r[4:0] >= radius_r;
    assign next_source_row_w = first_y_advance_r ?
        src_row_result_w : source_first_row_r;
    assign next_source_origin_w = shadow_r && phase_r == 1 ? temp1_r : temp0_w;
    assign next_output_origin_w = shadow_r ? (phase_r == 0 ? temp1_r : temp0_w) : dst_origin_r;
    assign packed_pixel_w = shadow_r ? {24'd0, output_pixel_r[7:0]} :
        !horizontal_w && !argb_w ?
        {16'd0, output_pixel_r[23:19], output_pixel_r[15:10], output_pixel_r[7:3]} :
        output_pixel_r;
    assign sample_mid_w = sample_low_r[12] ? sample_mid_one_r : sample_mid_zero_r;
    assign sample_data_w = state_r == S_READ_WAIT ? rd_data_i : cache_data_r;
    assign sample_shift_w = sample_data_w >> {sample_addr_r[4:0], 3'd0};
    assign raw_pixel_w = sample_shift_w[31:0];
    assign sample_pixel_w = outside_w ? 32'd0 : shadow_r ? {24'd0, raw_pixel_w[7:0]} :
        horizontal_w && !argb_w ? {8'd0, raw_pixel_w[15:11], raw_pixel_w[15:13],
            raw_pixel_w[10:5], raw_pixel_w[10:9], raw_pixel_w[4:0], raw_pixel_w[4:2]} :
        raw_pixel_w;
    assign rect_row_inside_w = (|row_distance_r[16:5] || row_distance_r[4:0] >= radius_r) &&
        (|row_remaining_r[16:5] || row_remaining_r[4:0] >= radius_r);
    edrv32_rnd_blur_coeff u_coefficient (
        .clk_i(clk_i),
        .rst_n_i(rst_n_i),
        .clear_i(cancel_i),
        .valid_i(state_r == S_COEFF),
        .ready_o(coefficient_ready_w),
        .radius_i(radius_r),
        .valid_o(coefficient_valid_w),
        .ready_i(state_r == S_DONE),
        .coefficient_o(coefficient_w)
    );
    edrv32_rnd_blur_math u_normalize (
        .clk_i(clk_i),
        .rst_n_i(rst_n_i),
        .valid_i(state_r == S_NORMALIZE),
        .ready_o(math_ready_w),
        .sum_i({56'd0, sum_r}),
        .coefficient_i(coefficient_w),
        .valid_o(math_valid_w),
        .ready_i(1'b1),
        .pixel_o(math_pixel_w)
    );
    edrv32_rnd_round_row u_round_row (
        .clk_i(clk_i),
        .rst_n_i(rst_n_i),
        .clear_i(cancel_i),
        .row_valid_i(state_r == S_EDGE),
        .row_ready_o(round_ready_w),
        .width_i(width_r),
        .height_i(height_r),
        .row_y_i(row_local_r),
        .radius_i(command_i[267:256]),
        .edge_valid_o(round_valid_w),
        .edge_ready_i(state_r == S_EDGE_WAIT),
        .edge_q4_o(round_edge_w),
        .radius_o(unused_radius_w)
    );
    edrv32_rnd_coverage u_coverage (
        .x_i(coverage_x_r),
        .width_i(width_r),
        .edge_q4_i(edge_r),
        .row_inside_i(rect_row_inside_r),
        .coverage_o(coverage_w)
    );
    assign shadow_x1_w = drawing_right_r;
    assign shadow_y1_w = drawing_bottom_r;
    assign unused_data_w = ^{stride_round_w[17], stride_round_w[4:0],
        temp_product_r[33:32], math_pixel_w[63:32], coverage_w[15:8],
        sample_shift_w[255:32], rect_row_coordinate_r[17], drawing_left_r[17:16],
        drawing_top_r[17:16], shadow_x1_w[17:16], shadow_y1_w[17:16]};
    always @(*) begin
        shadow_draw_w = command_i;
        shadow_draw_w[31:0] = {16'd0, 4'd2, 3'd0, argb_w, 8'h03};
        shadow_draw_w[191:160] = {drawing_top_r[15:0], drawing_left_r[15:0]};
        shadow_draw_w[223:192] = {shadow_y1_w[15:0], shadow_x1_w[15:0]};
        shadow_draw_w[287:256] = temp0_w;
        shadow_draw_w[319:288] = {15'd0, stride_r};
        shadow_draw_w[351:320] = {shadow_src_y_r, shadow_src_x_r};
    end
    assign shadow_draw_o = shadow_draw_w;
    assign shadow_stride_o = {15'd0, stride_r};
    assign done_o = state_r == S_DONE;
    assign pixel_count_o = pixel_count_r;
    assign rd_valid_o = state_r == S_READ && !cancel_i;
    assign rd_addr_o = {sample_addr_r[31:5], 5'd0};
    assign wr_valid_o = state_r == S_WRITE && !cancel_i;
    assign wr_addr_o = work_addr_r;
    assign wr_data_o = work_data_r;
    assign wr_strb_o = work_strb_r;

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            state_r <= S_IDLE;
            write_return_r <= S_IDLE;
            phase_r <= 2'd0;
            x_r <= 18'sd0;
            y_r <= 18'sd0;
            tap_r <= 7'sd0;
            cache_valid_r <= 1'b0;
            work_valid_r <= 1'b0;
            pixel_count_r <= 5'd0;
        end else if (cancel_i) begin
            state_r <= S_IDLE;
            cache_valid_r <= 1'b0;
            work_valid_r <= 1'b0;
            pixel_count_r <= 5'd0;
        end else begin
            pixel_count_r <= 5'd0;
            case (state_r)
                S_IDLE: if (start_i) begin
                    phase_r <= 2'd0;
                    cache_valid_r <= 1'b0;
                    work_valid_r <= 1'b0;
                    state_r <= S_COEFF;
                end
                S_COEFF: if (coefficient_ready_w)
                    state_r <= S_COEFF_WAIT;
                S_COEFF_WAIT: if (coefficient_valid_w) begin
                    x_r <= left_r;
                    y_r <= top_r;
                    state_r <= S_ROW;
                end
                S_ROW: state_r <= seed_w && rect_row_inside_w ? S_EDGE : S_PIXEL;
                S_EDGE: if (round_ready_w)
                    state_r <= S_EDGE_WAIT;
                S_EDGE_WAIT: if (round_valid_w)
                    state_r <= S_PIXEL;
                S_PIXEL: begin
                    tap_r <= -$signed({2'd0, radius_r});
                    state_r <= seed_w ? S_OUTPUT : S_SAMPLE;
                end
                S_SAMPLE: begin
                    if (outside_w || (cache_valid_r &&
                        cache_addr_r == {sample_addr_r[31:5], 5'd0}))
                        state_r <= S_ADD;
                    else
                        state_r <= S_READ;
                end
                S_READ: if (rd_ready_i)
                    state_r <= S_READ_WAIT;
                S_READ_WAIT: if (rd_data_valid_i) begin
                    cache_valid_r <= 1'b1;
                    state_r <= S_ADD;
                end
                S_ADD: begin
                    if (tap_r == $signed({2'd0, radius_r}))
                        state_r <= S_NORMALIZE;
                    else begin
                        tap_r <= tap_r + 7'sd1;
                        state_r <= S_SAMPLE;
                    end
                end
                S_NORMALIZE: if (math_ready_w)
                    state_r <= S_NORMALIZE_WAIT;
                S_NORMALIZE_WAIT: if (math_valid_w)
                    state_r <= S_OUTPUT;
                S_OUTPUT: begin
                    if (work_valid_r && work_addr_r != {output_addr_r[31:5], 5'd0}) begin
                        write_return_r <= S_OUTPUT;
                        state_r <= S_WRITE;
                    end else begin
                        work_valid_r <= 1'b1;
                        state_r <= S_STORE;
                    end
                end
                S_STORE: begin
                    if (!shadow_r && !horizontal_w)
                        pixel_count_r <= 5'd1;
                    if (last_pixel_r) begin
                        write_return_r <= S_NEXT_ROW;
                        state_r <= S_WRITE;
                    end else begin
                        x_r <= x_r + 18'sd1;
                        state_r <= S_PIXEL;
                    end
                end
                S_WRITE: if (wr_ready_i)
                    state_r <= S_WRITE_WAIT;
                S_WRITE_WAIT: if (wr_done_i) begin
                    work_valid_r <= 1'b0;
                    state_r <= write_return_r;
                end
                S_NEXT_ROW: begin
                    x_r <= left_r;
                    if (last_row_r) begin
                        if ((shadow_r && phase_r == 2) || (!shadow_r && phase_r == 1))
                            state_r <= S_DONE;
                        else begin
                            y_r <= top_r;
                            phase_r <= phase_r + 2'd1;
                            cache_valid_r <= 1'b0;
                            state_r <= S_ROW;
                        end
                    end else begin
                        y_r <= y_r + 18'sd1;
                        state_r <= S_ROW;
                    end
                end
                S_DONE: state_r <= S_IDLE;
                default: state_r <= state_r;
            endcase
        end
    end
    // spec rnd 5.2: 12/12/8-bit registered sums overlap coefficient, row and pixel work.
    always @(posedge clk_i) begin
        temp_base_low_r <= {1'b0, temp_base_a_w[11:0]} + {1'b0, temp_base_b_w[11:0]};
        temp_base_mid_r <= {1'b0, temp_base_a_w[23:12]} + {1'b0, temp_base_b_w[23:12]};
        temp_base_high_r <= temp_base_a_w[31:24] + temp_base_b_w[31:24];
        temp_base_low_delay_r <= temp_base_low_r[11:0];
        temp_base_mid_carry_r <= temp_base_mid_r + {12'd0, temp_base_low_r[12]};
        temp_base_high_delay_r <= temp_base_high_r;
    end
    always @(posedge clk_i) begin
        dst_base_low_r <= {1'b0, dst_base_a_w[11:0]} + {1'b0, dst_base_b_w[11:0]};
        dst_base_mid_r <= {1'b0, dst_base_a_w[23:12]} + {1'b0, dst_base_b_w[23:12]};
        dst_base_high_r <= dst_base_a_w[31:24] + dst_base_b_w[31:24];
        dst_base_low_delay_r <= dst_base_low_r[11:0];
        dst_base_mid_carry_r <= dst_base_mid_r + {12'd0, dst_base_low_r[12]};
        dst_base_high_delay_r <= dst_base_high_r;
    end
    always @(posedge clk_i) begin
        src_row_low_r <= {1'b0, src_row_a_w[11:0]} + {1'b0, src_row_b_w[11:0]};
        src_row_mid_r <= {1'b0, src_row_a_w[23:12]} + {1'b0, src_row_b_w[23:12]};
        src_row_high_r <= src_row_a_w[31:24] + src_row_b_w[31:24];
        src_row_low_delay_r <= src_row_low_r[11:0];
        src_row_mid_carry_r <= src_row_mid_r + {12'd0, src_row_low_r[12]};
        src_row_high_delay_r <= src_row_high_r;
    end
    always @(posedge clk_i) begin
        out_row_low_r <= {1'b0, out_row_a_w[11:0]} + {1'b0, out_row_b_w[11:0]};
        out_row_mid_r <= {1'b0, out_row_a_w[23:12]} + {1'b0, out_row_b_w[23:12]};
        out_row_high_r <= out_row_a_w[31:24] + out_row_b_w[31:24];
        out_row_low_delay_r <= out_row_low_r[11:0];
        out_row_mid_carry_r <= out_row_mid_r + {12'd0, out_row_low_r[12]};
        out_row_high_delay_r <= out_row_high_r;
    end
    always @(posedge clk_i) begin
        src_pixel_low_r <= {1'b0, src_pixel_a_w[11:0]} + {1'b0, src_pixel_b_w[11:0]};
        src_pixel_mid_r <= {1'b0, src_pixel_a_w[23:12]} + {1'b0, src_pixel_b_w[23:12]};
        src_pixel_high_r <= src_pixel_a_w[31:24] + src_pixel_b_w[31:24];
        src_pixel_low_delay_r <= src_pixel_low_r[11:0];
        src_pixel_mid_carry_r <= src_pixel_mid_r + {12'd0, src_pixel_low_r[12]};
        src_pixel_high_delay_r <= src_pixel_high_r;
    end
    always @(posedge clk_i) begin
        out_pixel_low_r <= {1'b0, out_pixel_a_w[11:0]} + {1'b0, out_pixel_b_w[11:0]};
        out_pixel_mid_r <= {1'b0, out_pixel_a_w[23:12]} + {1'b0, out_pixel_b_w[23:12]};
        out_pixel_high_r <= out_pixel_a_w[31:24] + out_pixel_b_w[31:24];
        out_pixel_low_delay_r <= out_pixel_low_r[11:0];
        out_pixel_mid_carry_r <= out_pixel_mid_r + {12'd0, out_pixel_low_r[12]};
        out_pixel_high_delay_r <= out_pixel_high_r;
    end
    always @(posedge clk_i) begin
        raw_left_high_take_r <= $signed(raw_left_r[17:9]) >
            $signed({6'd0, clip_left_r[11:9]});
        raw_left_high_equal_r <= raw_left_r[17:9] == {6'd0, clip_left_r[11:9]};
        raw_left_low_take_r <= raw_left_r[8:0] > clip_left_r[8:0];
        raw_left_take_r <= raw_left_high_take_r ||
            (raw_left_high_equal_r && raw_left_low_take_r);
    end
    always @(posedge clk_i) begin
        draw_left_high_take_r <= $signed(left_r[17:9]) >
            $signed({6'd0, clip_left_r[11:9]});
        draw_left_high_equal_r <= left_r[17:9] == {6'd0, clip_left_r[11:9]};
        draw_left_low_take_r <= left_r[8:0] > clip_left_r[8:0];
        draw_left_take_r <= draw_left_high_take_r ||
            (draw_left_high_equal_r && draw_left_low_take_r);
    end
    always @(posedge clk_i) begin
        raw_top_high_take_r <= $signed(raw_top_r[17:9]) >
            $signed({6'd0, clip_top_r[11:9]});
        raw_top_high_equal_r <= raw_top_r[17:9] == {6'd0, clip_top_r[11:9]};
        raw_top_low_take_r <= raw_top_r[8:0] > clip_top_r[8:0];
        raw_top_take_r <= raw_top_high_take_r ||
            (raw_top_high_equal_r && raw_top_low_take_r);
    end
    always @(posedge clk_i) begin
        draw_top_high_take_r <= $signed(top_r[17:9]) >
            $signed({6'd0, clip_top_r[11:9]});
        draw_top_high_equal_r <= top_r[17:9] == {6'd0, clip_top_r[11:9]};
        draw_top_low_take_r <= top_r[8:0] > clip_top_r[8:0];
        draw_top_take_r <= draw_top_high_take_r ||
            (draw_top_high_equal_r && draw_top_low_take_r);
    end
    always @(posedge clk_i) begin
        raw_right_high_take_r <= $signed(raw_right_r[17:9]) <
            $signed({6'd0, clip_right_r[11:9]});
        raw_right_high_equal_r <= raw_right_r[17:9] == {6'd0, clip_right_r[11:9]};
        raw_right_low_take_r <= raw_right_r[8:0] < clip_right_r[8:0];
        raw_right_take_r <= raw_right_high_take_r ||
            (raw_right_high_equal_r && raw_right_low_take_r);
    end
    always @(posedge clk_i) begin
        draw_right_high_take_r <= $signed(right_r[17:9]) <
            $signed({6'd0, clip_right_r[11:9]});
        draw_right_high_equal_r <= right_r[17:9] == {6'd0, clip_right_r[11:9]};
        draw_right_low_take_r <= right_r[8:0] < clip_right_r[8:0];
        draw_right_take_r <= draw_right_high_take_r ||
            (draw_right_high_equal_r && draw_right_low_take_r);
    end
    always @(posedge clk_i) begin
        raw_bottom_high_take_r <= $signed(raw_bottom_r[17:9]) <
            $signed({6'd0, clip_bottom_r[11:9]});
        raw_bottom_high_equal_r <= raw_bottom_r[17:9] == {6'd0, clip_bottom_r[11:9]};
        raw_bottom_low_take_r <= raw_bottom_r[8:0] < clip_bottom_r[8:0];
        raw_bottom_take_r <= raw_bottom_high_take_r ||
            (raw_bottom_high_equal_r && raw_bottom_low_take_r);
    end
    always @(posedge clk_i) begin
        draw_bottom_high_take_r <= $signed(bottom_r[17:9]) <
            $signed({6'd0, clip_bottom_r[11:9]});
        draw_bottom_high_equal_r <= bottom_r[17:9] == {6'd0, clip_bottom_r[11:9]};
        draw_bottom_low_take_r <= bottom_r[8:0] < clip_bottom_r[8:0];
        draw_bottom_take_r <= draw_bottom_high_take_r ||
            (draw_bottom_high_equal_r && draw_bottom_low_take_r);
    end
    // spec rnd 2.5/2.6: signed 16-bit RECT plus R<=31 fits 18-bit bounds;
    // shadow dimensions/stride fit 17 bits, with maximum aligned stride 65600.
    // Command setup overlaps the 17-step coefficient division. Subsequent rows,
    // pixels and taps use clamped address recurrences, preserving two cycles/tap.
    always @(posedge clk_i) begin
        if (state_r == S_IDLE && start_i) begin
            raw_left_r <= rect_left_w;
            clip_left_r <= command_i[107:96];
            raw_top_r <= rect_top_w;
            clip_top_r <= command_i[123:112];
            raw_right_r <= rect_right_w;
            clip_right_r <= command_i[139:128];
            raw_bottom_r <= rect_bottom_w;
            clip_bottom_r <= command_i[155:144];
            shadow_r <= shadow_w;
            radius_r <= radius_w;
        end
        expanded_left_low_r <= {1'b0, raw_left_r[8:0]} - {5'd0, radius_r};
        expanded_left_high_r <= raw_left_r[17:9];
        expanded_left_r <= {expanded_left_high_r -
            {8'd0, expanded_left_low_r[9]}, expanded_left_low_r[8:0]};
        left_r <= shadow_r ? expanded_left_r :
            raw_left_take_r ? raw_left_r : $signed({6'd0, clip_left_r});
        expanded_top_low_r <= {1'b0, raw_top_r[8:0]} - {5'd0, radius_r};
        expanded_top_high_r <= raw_top_r[17:9];
        expanded_top_r <= {expanded_top_high_r -
            {8'd0, expanded_top_low_r[9]}, expanded_top_low_r[8:0]};
        top_r <= shadow_r ? expanded_top_r :
            raw_top_take_r ? raw_top_r : $signed({6'd0, clip_top_r});
        expanded_right_low_r <= {1'b0, raw_right_r[8:0]} + {5'd0, radius_r};
        expanded_right_high_r <= raw_right_r[17:9];
        expanded_right_r <= {expanded_right_high_r +
            {8'd0, expanded_right_low_r[9]}, expanded_right_low_r[8:0]};
        right_r <= shadow_r ? expanded_right_r :
            raw_right_take_r ? raw_right_r : $signed({6'd0, clip_right_r});
        expanded_bottom_low_r <= {1'b0, raw_bottom_r[8:0]} + {5'd0, radius_r};
        expanded_bottom_high_r <= raw_bottom_r[17:9];
        expanded_bottom_r <= {expanded_bottom_high_r +
            {8'd0, expanded_bottom_low_r[9]}, expanded_bottom_low_r[8:0]};
        bottom_r <= shadow_r ? expanded_bottom_r :
            raw_bottom_take_r ? raw_bottom_r : $signed({6'd0, clip_bottom_r});
        drawing_left_r <= draw_left_take_r ?
            left_r : $signed({6'd0, clip_left_r});
        drawing_top_r <= draw_top_take_r ?
            top_r : $signed({6'd0, clip_top_r});
        drawing_right_r <= draw_right_take_r ?
            right_r : $signed({6'd0, clip_right_r});
        drawing_bottom_r <= draw_bottom_take_r ?
            bottom_r : $signed({6'd0, clip_bottom_r});
        shadow_x_low_r <= {1'b0, drawing_left_r[7:0]} - {1'b0, left_r[7:0]};
        shadow_y_low_r <= {1'b0, drawing_top_r[7:0]} - {1'b0, top_r[7:0]};
        shadow_x_high_r <= drawing_left_r[15:8] - left_r[15:8];
        shadow_y_high_r <= drawing_top_r[15:8] - top_r[15:8];
        shadow_src_x_r <= {shadow_x_high_r - {7'd0, shadow_x_low_r[8]}, shadow_x_low_r[7:0]};
        shadow_src_y_r <= {shadow_y_high_r - {7'd0, shadow_y_low_r[8]}, shadow_y_low_r[7:0]};
        grid_width_low_r <= {1'b0, right_r[8:0]} - {1'b0, left_r[8:0]};
        grid_width_high_r <= right_r[16:9] - left_r[16:9];
        grid_width_delta_r <= {grid_width_high_r - {7'd0, grid_width_low_r[9]},
            grid_width_low_r[8:0]};
        grid_height_low_r <= {1'b0, bottom_r[8:0]} - {1'b0, top_r[8:0]};
        grid_height_high_r <= bottom_r[16:9] - top_r[16:9];
        grid_height_delta_r <= {grid_height_high_r - {7'd0, grid_height_low_r[9]},
            grid_height_low_r[8:0]};
        grid_width_r <= grid_width_delta_r + 17'd1;
        grid_height_r <= grid_height_delta_r + 17'd1;
        rect_width_low_r <= {1'b0, command_i[199:192]} - {1'b0, command_i[167:160]};
        rect_width_high_r <= {command_i[207], command_i[207:200]} -
            {command_i[175], command_i[175:168]};
        rect_width_delta_r <= {rect_width_high_r - {8'd0, rect_width_low_r[8]},
            rect_width_low_r[7:0]};
        rect_height_low_r <= {1'b0, command_i[215:208]} - {1'b0, command_i[183:176]};
        rect_height_high_r <= {command_i[223], command_i[223:216]} -
            {command_i[191], command_i[191:184]};
        rect_height_delta_r <= {rect_height_high_r - {8'd0, rect_height_low_r[8]},
            rect_height_low_r[7:0]};
        width_r <= rect_width_delta_r + 17'd1;
        height_r <= rect_height_delta_r + 17'd1;
        stride_r <= {stride_round_w[16:5], 5'd0};
        temp_product_r <= stride_r * grid_height_r;
        temp1_r <= temp_base_result_w;
        dst_y_r <= top_r[11:0];
        dst_column_r <= {2'd0, left_r[11:0]} << (argb_w ? 2 : 1);
        dst_product_r <= dst_y_r * command_i[79:64];
        dst_offset_low_r <= {1'b0, dst_product_r[13:0]} + {1'b0, dst_column_r};
        dst_offset_high_r <= dst_product_r[27:14];
        dst_offset_r <= {dst_offset_high_r + {13'd0, dst_offset_low_r[14]},
            dst_offset_low_r[13:0]};
        dst_origin_r <= dst_base_result_w;
        source_bytes_r <= source_pixel_bytes_w;
        output_bytes_r <= output_pixel_bytes_w;
        if (state_r == S_ROW) begin
            last_row_r <= y_r == bottom_r;
            row_remaining_low_r <= {1'b0, row_remaining_r[8:0]} - 10'd1;
            first_y_advance_r <= first_y_advance_w;
            column_distance_r <= 17'd0;
            column_remaining_r <= grid_width_delta_r;
            coverage_x_r <= -$signed({13'd0, radius_r});
            row_local_r <= rect_row_coordinate_r[16:0];
            rect_row_inside_r <= rect_row_inside_w;
        end
        if (state_r == S_COEFF_WAIT && coefficient_valid_w) begin
            row_distance_r <= 17'd0;
            row_remaining_r <= grid_height_delta_r;
            rect_row_coordinate_r <= -$signed({13'd0, radius_r});
            source_first_row_r <= shadow_r ? temp1_r : dst_origin_r;
            first_addr_r <= shadow_r ? temp1_r : dst_origin_r;
            output_row_r <= temp0_w;
            output_addr_r <= temp0_w;
            source_stride_r <= shadow_r ? stride_r : {1'b0, command_i[79:64]};
            output_stride_r <= stride_r;
            sample_step_r <= shadow_r ? stride_r : {14'd0, source_pixel_bytes_w};
        end
        if (state_r == S_PIXEL) begin
            last_pixel_r <= x_r == right_r;
            first_x_advance_r <= first_x_advance_w;
            sample_addr_r <= first_addr_r;
            // Distances above 31 cannot clamp any specified tap; +/-32 are exact sentinels.
            tap_min_r <= |distance_before_w[16:5] ? -7'sd32 :
                -$signed({2'd0, distance_before_w[4:0]});
            tap_max_r <= |distance_after_w[16:5] ? 7'sd32 :
                $signed({2'd0, distance_after_w[4:0]});
        end
        // Both middle sums are ready before ADD selects the registered low carry.
        if (state_r == S_SAMPLE) begin
            sample_advance_r <= sample_advance_w;
            sample_low_r <= {1'b0, sample_addr_r[11:0]} + {1'b0, sample_step_r[11:0]};
            sample_mid_zero_r <= {1'b0, sample_addr_r[23:12]} + {8'd0, sample_step_r[16:12]};
            sample_mid_one_r <= {1'b0, sample_addr_r[23:12]} +
                {8'd0, sample_step_r[16:12]} + 13'd1;
            sample_high_r <= sample_addr_r[31:24];
        end
        if ((state_r == S_SAMPLE && (outside_w ||
            (cache_valid_r && cache_addr_r == {sample_addr_r[31:5], 5'd0}))) ||
            (state_r == S_READ_WAIT && rd_data_valid_i))
            sample_pixel_r <= sample_pixel_w;
        if (state_r == S_ADD) begin
            if (sample_advance_r)
                sample_addr_r <= {sample_high_r + {7'd0, sample_mid_w[12]},
                    sample_mid_w[11:0], sample_low_r[11:0]};
        end
        if (state_r == S_STORE && !last_pixel_r) begin
            if (first_x_advance_r)
                first_addr_r <= src_pixel_result_w;
            output_addr_r <= out_pixel_result_w;
            coverage_x_r <= coverage_x_r + 18'sd1;
            column_distance_r <= column_distance_r + 17'd1;
            column_remaining_r <= column_remaining_r - 17'd1;
        end
        if (state_r == S_NEXT_ROW) begin
            if (last_row_r) begin
                row_distance_r <= 17'd0;
                row_remaining_r <= grid_height_delta_r;
                rect_row_coordinate_r <= -$signed({13'd0, radius_r});
                source_first_row_r <= next_source_origin_w;
                first_addr_r <= next_source_origin_w;
                output_row_r <= next_output_origin_w;
                output_addr_r <= next_output_origin_w;
                source_stride_r <= stride_r;
                output_stride_r <= shadow_r ? stride_r : {1'b0, command_i[79:64]};
                sample_step_r <= shadow_r && phase_r == 0 ? 17'd1 : stride_r;
            end else begin
                row_distance_r <= row_distance_r + 17'd1;
                row_remaining_r <= {row_remaining_r[16:9] -
                    {7'd0, row_remaining_low_r[9]}, row_remaining_low_r[8:0]};
                rect_row_coordinate_r <= rect_row_coordinate_r + 18'sd1;
                source_first_row_r <= next_source_row_w;
                first_addr_r <= next_source_row_w;
                output_row_r <= out_row_result_w;
                output_addr_r <= out_row_result_w;
            end
        end
    end
    always @(posedge clk_i) begin
        if (state_r == S_EDGE_WAIT && round_valid_w)
            edge_r <= round_edge_w;
        if (state_r == S_PIXEL) begin
            sum_r <= 56'd0;
            if (seed_w)
                output_pixel_r <= {24'd0, coverage_w[7:0]};
        end
        if (state_r == S_READ_WAIT && rd_data_valid_i) begin
            cache_data_r <= rd_data_i;
            cache_addr_r <= {sample_addr_r[31:5], 5'd0};
        end
        if (state_r == S_ADD)
            for (channel = 0; channel < 4; channel = channel + 1)
                sum_r[channel*14 +: 14] <= sum_r[channel*14 +: 14] +
                    {6'd0, sample_pixel_r[channel*8 +: 8]};
        if (state_r == S_NORMALIZE_WAIT && math_valid_w)
            output_pixel_r <= math_pixel_w[31:0];
        if (state_r == S_OUTPUT && !work_valid_r) begin
            work_addr_r <= {output_addr_r[31:5], 5'd0};
            work_data_r <= 256'd0;
            work_strb_r <= 32'd0;
        end
        // Prepare the byte mask and the four rotated pixel bytes before STORE.
        if (state_r == S_OUTPUT) begin
            store_mask_r <= (shadow_r ? 32'h0000_0001 :
                !horizontal_w && !argb_w ? 32'h0000_0003 : 32'h0000_000f) << output_addr_r[4:0];
            case (output_addr_r[1:0])
                2'd0: store_pixel_r <= packed_pixel_w;
                2'd1: store_pixel_r <= {packed_pixel_w[23:0], packed_pixel_w[31:24]};
                2'd2: store_pixel_r <= {packed_pixel_w[15:0], packed_pixel_w[31:16]};
                2'd3: store_pixel_r <= {packed_pixel_w[7:0], packed_pixel_w[31:8]};
                default: store_pixel_r <= packed_pixel_w;
            endcase
        end
        if (state_r == S_STORE) begin
            for (byte_lane = 0; byte_lane < 32; byte_lane = byte_lane + 1)
                if (store_mask_r[byte_lane])
                    work_data_r[byte_lane*8 +: 8] <= store_pixel_r[(byte_lane%4)*8 +: 8];
            work_strb_r <= work_strb_r | store_mask_r;
        end
    end
endmodule
