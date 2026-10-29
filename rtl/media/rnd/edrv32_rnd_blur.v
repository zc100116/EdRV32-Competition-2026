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
    wire [7:0] unused_op_w;
    wire [3:0] unused_format_w;
    wire [15:0] unused_flags_w;
    wire signed [17:0] clip_left_w;
    wire signed [17:0] clip_top_w;
    wire signed [17:0] clip_right_w;
    wire signed [17:0] clip_bottom_w;
    wire [16:0] width_w;
    wire [16:0] height_w;
    wire unused_illegal_w;
    wire unused_empty_w;
    wire unused_fast_w;
    wire signed [17:0] rect_left_w;
    wire signed [17:0] rect_top_w;
    wire signed [17:0] rect_right_w;
    wire signed [17:0] rect_bottom_w;
    wire signed [17:0] left_w;
    wire signed [17:0] top_w;
    wire signed [17:0] right_w;
    wire signed [17:0] bottom_w;
    wire [17:0] grid_width_w;
    wire [17:0] grid_height_w;
    wire [17:0] stride_w;
    wire [17:0] stride_round_w;
    wire [31:0] temp0_w;
    wire [31:0] temp1_w;
    wire horizontal_w;
    wire seed_w;
    wire signed [17:0] sample_x_w;
    wire signed [17:0] sample_y_w;
    wire signed [17:0] clamped_x_w;
    wire signed [17:0] clamped_y_w;
    wire outside_w;
    wire [31:0] sample_addr_w;
    wire [255:0] sample_shift_w;
    wire [31:0] sample_pixel_w;
    wire [31:0] raw_pixel_w;
    wire [31:0] output_addr_w;
    wire [31:0] source_base_w;
    wire [31:0] output_base_w;
    wire [31:0] source_stride_w;
    wire [31:0] output_stride_w;
    wire [31:0] source_x_w;
    wire [31:0] source_y_w;
    wire [31:0] output_x_w;
    wire [31:0] output_y_w;
    wire [1:0] source_log2_w;
    wire [1:0] output_log2_w;
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
    wire [17:0] row_local_w;
    wire [17:0] shadow_src_x_w;
    wire [17:0] shadow_src_y_w;
    wire [17:0] shadow_x1_w;
    wire [17:0] shadow_y1_w;
    wire unused_data_w;
    reg [511:0] shadow_draw_w;
    integer channel;

    edrv32_rnd_decode u_decode (
        .command_i(command_i),
        .illegal_o(unused_illegal_w),
        .empty_o(unused_empty_w),
        .op_o(unused_op_w),
        .argb_o(argb_w),
        .src_fmt_o(unused_format_w),
        .flags_o(unused_flags_w),
        .left_o(clip_left_w),
        .top_o(clip_top_w),
        .right_o(clip_right_w),
        .bottom_o(clip_bottom_w),
        .width_o(width_w),
        .height_o(height_w),
        .fast_fill_o(unused_fast_w)
    );
    assign shadow_w = command_i[7:0] == 8'h06;
    assign radius_w = shadow_w ? command_i[292:288] : command_i[260:256];
    assign rect_left_w = {{2{command_i[175]}}, command_i[175:160]};
    assign rect_top_w = {{2{command_i[191]}}, command_i[191:176]};
    assign rect_right_w = {{2{command_i[207]}}, command_i[207:192]};
    assign rect_bottom_w = {{2{command_i[223]}}, command_i[223:208]};
    assign left_w = shadow_w ? rect_left_w - $signed({13'd0, radius_w}) : clip_left_w;
    assign top_w = shadow_w ? rect_top_w - $signed({13'd0, radius_w}) : clip_top_w;
    assign right_w = shadow_w ? rect_right_w + $signed({13'd0, radius_w}) : clip_right_w;
    assign bottom_w = shadow_w ? rect_bottom_w + $signed({13'd0, radius_w}) : clip_bottom_w;
    assign grid_width_w = right_w - left_w + 18'd1;
    assign grid_height_w = bottom_w - top_w + 18'd1;
    assign stride_round_w = (grid_width_w << (shadow_w ? 0 : 2)) + 18'd31;
    assign stride_w = {stride_round_w[17:5], 5'd0};
    assign temp0_w = shadow_w ? command_i[351:320] : command_i[319:288];
    assign temp1_w = temp0_w + {14'd0, stride_w} * {14'd0, grid_height_w};
    assign seed_w = shadow_w && phase_r == 0;
    assign horizontal_w = shadow_w ? phase_r == 1 : phase_r == 0;
    assign sample_x_w = x_r + (horizontal_w ? {{11{tap_r[6]}}, tap_r} : 18'sd0);
    assign sample_y_w = y_r + (horizontal_w ? 18'sd0 : {{11{tap_r[6]}}, tap_r});
    assign clamped_x_w = sample_x_w < left_w ? left_w :
        sample_x_w > right_w ? right_w : sample_x_w;
    assign clamped_y_w = sample_y_w < top_w ? top_w :
        sample_y_w > bottom_w ? bottom_w : sample_y_w;
    assign outside_w = shadow_w && (sample_x_w < left_w || sample_x_w > right_w ||
        sample_y_w < top_w || sample_y_w > bottom_w);
    assign source_base_w = shadow_w ? (horizontal_w ? temp0_w : temp1_w) :
        horizontal_w ? command_i[63:32] : temp0_w;
    assign output_base_w = shadow_w ? (phase_r == 1 ? temp1_w : temp0_w) :
        horizontal_w ? temp0_w : command_i[63:32];
    assign source_stride_w = !shadow_w && horizontal_w ?
        {16'd0, command_i[79:64]} : {14'd0, stride_w};
    assign output_stride_w = !shadow_w && !horizontal_w ?
        {16'd0, command_i[79:64]} : {14'd0, stride_w};
    assign source_x_w = !shadow_w && horizontal_w ?
        {{14{clamped_x_w[17]}}, clamped_x_w} :
        {{14{clamped_x_w[17]}}, clamped_x_w} - {{14{left_w[17]}}, left_w};
    assign source_y_w = !shadow_w && horizontal_w ?
        {{14{clamped_y_w[17]}}, clamped_y_w} :
        {{14{clamped_y_w[17]}}, clamped_y_w} - {{14{top_w[17]}}, top_w};
    assign output_x_w = !shadow_w && !horizontal_w ? {{14{x_r[17]}}, x_r} :
        {{14{x_r[17]}}, x_r} - {{14{left_w[17]}}, left_w};
    assign output_y_w = !shadow_w && !horizontal_w ? {{14{y_r[17]}}, y_r} :
        {{14{y_r[17]}}, y_r} - {{14{top_w[17]}}, top_w};
    assign source_log2_w = shadow_w ? 2'd0 : horizontal_w && !argb_w ? 2'd1 : 2'd2;
    assign output_log2_w = shadow_w ? 2'd0 : !horizontal_w && !argb_w ? 2'd1 : 2'd2;
    assign sample_addr_w = source_base_w + source_y_w * source_stride_w +
        (source_x_w << source_log2_w);
    assign output_addr_w = output_base_w + output_y_w * output_stride_w +
        (output_x_w << output_log2_w);
    assign sample_shift_w = cache_data_r >> {sample_addr_w[4:0], 3'd0};
    assign raw_pixel_w = sample_shift_w[31:0];
    assign sample_pixel_w = outside_w ? 32'd0 : shadow_w ? {24'd0, raw_pixel_w[7:0]} :
        horizontal_w && !argb_w ? {8'd0, raw_pixel_w[15:11], raw_pixel_w[15:13],
            raw_pixel_w[10:5], raw_pixel_w[10:9], raw_pixel_w[4:0], raw_pixel_w[4:2]} :
        raw_pixel_w;
    assign row_local_w = y_r - rect_top_w;
    assign rect_row_inside_w = y_r >= rect_top_w && y_r <= rect_bottom_w;
    edrv32_rnd_blur_coeff u_coefficient (
        .clk_i(clk_i),
        .rst_n_i(rst_n_i),
        .clear_i(cancel_i),
        .valid_i(state_r == S_COEFF),
        .ready_o(coefficient_ready_w),
        .radius_i(radius_w),
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
        .width_i(width_w),
        .height_i(height_w),
        .row_y_i(row_local_w[16:0]),
        .radius_i(command_i[267:256]),
        .edge_valid_o(round_valid_w),
        .edge_ready_i(state_r == S_EDGE_WAIT),
        .edge_q4_o(round_edge_w),
        .radius_o(unused_radius_w)
    );
    edrv32_rnd_coverage u_coverage (
        .x_i(x_r - rect_left_w),
        .width_i(width_w),
        .edge_q4_i(edge_r),
        .row_inside_i(rect_row_inside_w),
        .coverage_o(coverage_w)
    );
    assign shadow_src_x_w = clip_left_w - left_w;
    assign shadow_src_y_w = clip_top_w - top_w;
    assign shadow_x1_w = clip_right_w;
    assign shadow_y1_w = clip_bottom_w;
    assign unused_data_w = ^{stride_round_w[4:0], math_pixel_w[63:32], coverage_w[15:8],
        sample_shift_w[255:32], row_local_w[17], shadow_src_x_w[17:16],
        shadow_src_y_w[17:16], shadow_x1_w[17:16], shadow_y1_w[17:16]};
    always @(*) begin
        shadow_draw_w = command_i;
        shadow_draw_w[31:0] = {16'd0, 4'd2, 3'd0, argb_w, 8'h03};
        shadow_draw_w[191:160] = {clip_top_w[15:0], clip_left_w[15:0]};
        shadow_draw_w[223:192] = {shadow_y1_w[15:0], shadow_x1_w[15:0]};
        shadow_draw_w[287:256] = temp0_w;
        shadow_draw_w[319:288] = {14'd0, stride_w};
        shadow_draw_w[351:320] = {shadow_src_y_w[15:0], shadow_src_x_w[15:0]};
    end
    assign shadow_draw_o = shadow_draw_w;
    assign shadow_stride_o = {14'd0, stride_w};
    assign done_o = state_r == S_DONE;
    assign pixel_count_o = pixel_count_r;
    assign rd_valid_o = state_r == S_READ && !cancel_i;
    assign rd_addr_o = {sample_addr_w[31:5], 5'd0};
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
                    x_r <= left_w;
                    y_r <= top_w;
                    cache_valid_r <= 1'b0;
                    work_valid_r <= 1'b0;
                    state_r <= S_COEFF;
                end
                S_COEFF: if (coefficient_ready_w)
                    state_r <= S_COEFF_WAIT;
                S_COEFF_WAIT: if (coefficient_valid_w)
                    state_r <= S_ROW;
                S_ROW: state_r <= seed_w && rect_row_inside_w ? S_EDGE : S_PIXEL;
                S_EDGE: if (round_ready_w)
                    state_r <= S_EDGE_WAIT;
                S_EDGE_WAIT: if (round_valid_w)
                    state_r <= S_PIXEL;
                S_PIXEL: begin
                    tap_r <= -$signed({2'd0, radius_w});
                    state_r <= seed_w ? S_OUTPUT : S_SAMPLE;
                end
                S_SAMPLE: begin
                    if (outside_w || (cache_valid_r &&
                        cache_addr_r == {sample_addr_w[31:5], 5'd0}))
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
                    if (tap_r == $signed({2'd0, radius_w}))
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
                    if (work_valid_r && work_addr_r != {output_addr_w[31:5], 5'd0}) begin
                        write_return_r <= S_OUTPUT;
                        state_r <= S_WRITE;
                    end else begin
                        work_valid_r <= 1'b1;
                        state_r <= S_STORE;
                    end
                end
                S_STORE: begin
                    if (!shadow_w && !horizontal_w)
                        pixel_count_r <= 5'd1;
                    if (x_r == right_w) begin
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
                    x_r <= left_w;
                    if (y_r == bottom_w) begin
                        if ((shadow_w && phase_r == 2) || (!shadow_w && phase_r == 1))
                            state_r <= S_DONE;
                        else begin
                            y_r <= top_w;
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
            cache_addr_r <= {sample_addr_w[31:5], 5'd0};
        end
        if (state_r == S_ADD)
            for (channel = 0; channel < 4; channel = channel + 1)
                sum_r[channel*14 +: 14] <= sum_r[channel*14 +: 14] +
                    {6'd0, sample_pixel_w[channel*8 +: 8]};
        if (state_r == S_NORMALIZE_WAIT && math_valid_w)
            output_pixel_r <= math_pixel_w[31:0];
        if (state_r == S_OUTPUT && !work_valid_r) begin
            work_addr_r <= {output_addr_w[31:5], 5'd0};
            work_data_r <= 256'd0;
            work_strb_r <= 32'd0;
        end
        if (state_r == S_STORE) begin
            if (shadow_w) begin
                work_data_r[output_addr_w[4:0]*8 +: 8] <= output_pixel_r[7:0];
                work_strb_r[output_addr_w[4:0]] <= 1'b1;
            end else if (!horizontal_w && !argb_w) begin
                work_data_r[output_addr_w[4:0]*8 +: 16] <=
                    {output_pixel_r[23:19], output_pixel_r[15:10], output_pixel_r[7:3]};
                work_strb_r[output_addr_w[4:0] +: 2] <= 2'b11;
            end else begin
                work_data_r[output_addr_w[4:0]*8 +: 32] <= output_pixel_r;
                work_strb_r[output_addr_w[4:0] +: 4] <= 4'hf;
            end
        end
    end
endmodule
