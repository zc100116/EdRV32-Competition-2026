// File: edrv32_gpu_raster.v
// Spec: gpu-spec 2.5, 2.8, 2.13; microarch 4.2, 4.4, 4.6.
// Description: Top-left triangle coverage and lossless four-pixel plane stepping.
//              Four interleaved phases, sliced carries and registered coverage.
// Clock domain: clk_gpu.
module edrv32_gpu_raster (
    // Clock and reset.,
    input wire clk_i,
    input wire rst_n_i,

    // State and command snapshots.,
    input wire render_state_valid_i,
    output wire render_state_ready_o,
    input wire [255:0] render_state_tex_i,
    input wire [255:0] render_state_pixel_i,
    input wire [255:0] render_state_target_i,
    input wire render_state_wide_i,
    input wire draw_valid_i,
    output wire draw_ready_o,
    input wire [255:0] draw_command_i,

    // triangle_setup stream.,
    input wire triangle_setup_valid_i,
    output wire triangle_setup_ready_o,
    input wire [63:0] triangle_setup_bounds_i,
    input wire [479:0] triangle_setup_edge_i,
    input wire [31:0] triangle_setup_origin_i,
    input wire [489:0] triangle_setup_start_i,
    input wire [783:0] triangle_setup_gradient_i,
    input wire [69:0] triangle_setup_h_i,
    input wire [173:0] triangle_setup_normal_gradient_i,

    // Ordered fragment stream.,
    output wire fragment_valid_o,
    input wire fragment_ready_i,
    output wire [15:0] fragment_x_o,
    output wire [15:0] fragment_y_o,
    output wire [3:0] fragment_mask_o,
    output wire fragment_quad_o,
    output wire [1959:0] fragment_plane_o,
    output wire [69:0] fragment_h_o,
    output wire [173:0] fragment_gradient_o,
    output wire [3:0] fragment_palette_o,
    output wire [7:0] fragment_alpha_o,

    // Command lifecycle.,
    input wire finish_i,
    input wire stop_i,
    output reg unit_done_o
);

    reg signed [17:0] clip_x0_r;
    reg signed [17:0] clip_y0_r;
    reg signed [17:0] clip_x1_r;
    reg signed [17:0] clip_y1_r;
    reg [3:0] palette_r;
    wire unused_state_w;
    assign unused_state_w = ^{render_state_pixel_i, render_state_tex_i, render_state_target_i,
        draw_command_i, draw_valid_i};
    assign render_state_ready_o = 1'b1;
    assign draw_ready_o = 1'b1;

    wire signed [17:0] target_x0_w;
    wire signed [17:0] target_y0_w;
    wire signed [17:0] target_x1_w;
    wire signed [17:0] target_y1_w;
    wire signed [17:0] scissor_x0_w;
    wire signed [17:0] scissor_y0_w;
    wire signed [17:0] scissor_x1_w;
    wire signed [17:0] scissor_y1_w;
    assign target_x0_w = {{2{render_state_target_i[47]}}, render_state_target_i[32 +: 16]};
    assign target_y0_w = {{2{render_state_target_i[63]}}, render_state_target_i[48 +: 16]};
    assign target_x1_w = target_x0_w + (render_state_wide_i ? 18'sd1280 : 18'sd640);
    assign target_y1_w = target_y0_w + (render_state_wide_i ? 18'sd90 : 18'sd180);
    assign scissor_x0_w = {{2{render_state_target_i[79]}}, render_state_target_i[64 +: 16]};
    assign scissor_y0_w = {{2{render_state_target_i[95]}}, render_state_target_i[80 +: 16]};
    assign scissor_x1_w = {{2{render_state_target_i[111]}}, render_state_target_i[96 +: 16]};
    assign scissor_y1_w = {{2{render_state_target_i[127]}}, render_state_target_i[112 +: 16]};
    reg cfg_pending_r;
    reg cfg_valid_r;
    reg signed [17:0] target_x0_r;
    reg signed [17:0] scissor_x0_r;
    reg signed [17:0] target_y0_r;
    reg signed [17:0] scissor_y0_r;
    reg signed [17:0] target_x1_r;
    reg signed [17:0] scissor_x1_r;
    reg signed [17:0] target_y1_r;
    reg signed [17:0] scissor_y1_r;
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            cfg_pending_r <= 0;
            cfg_valid_r <= 0;
        end else begin
            cfg_pending_r <= render_state_valid_i;
            if (cfg_pending_r) begin
                cfg_valid_r <= 1;
            end
            if (render_state_valid_i) begin
                cfg_valid_r <= 0;
            end
        end
    end
    always @(posedge clk_i) begin
        if (render_state_valid_i) begin
            target_x0_r <= target_x0_w;
            scissor_x0_r <= scissor_x0_w;
            target_y0_r <= target_y0_w;
            scissor_y0_r <= scissor_y0_w;
            target_x1_r <= target_x1_w;
            scissor_x1_r <= scissor_x1_w;
            target_y1_r <= target_y1_w;
            scissor_y1_r <= scissor_y1_w;
            palette_r <= render_state_tex_i[78 +: 4];
        end
        if (cfg_pending_r) begin
            clip_x0_r <= target_x0_r > scissor_x0_r ? target_x0_r : scissor_x0_r;
            clip_y0_r <= target_y0_r > scissor_y0_r ? target_y0_r : scissor_y0_r;
            clip_x1_r <= target_x1_r < scissor_x1_r ? target_x1_r : scissor_x1_r;
            clip_y1_r <= target_y1_r < scissor_y1_r ? target_y1_r : scissor_y1_r;
        end
    end

    // Two input slots and two output slots isolate backpressure at both boundaries.
    reg [1:0] input_count_r;
    reg input_read_r;
    reg input_write_r;
    reg [1:0] output_count_r;
    reg output_read_r;
    reg output_write_r;
    localparam S_IDLE = 3'd0;
    localparam S_SIGN = 3'd1;
    localparam S_ACCUMULATE = 3'd2;
    localparam S_SEED = 3'd3;
    localparam S_LOAD = 3'd4;
    reg [2:0] state_r;
    reg active_r;
    reg prepared_nonempty_r;
    reg [4:0] wait_r;
    reg [4:0] bit_r;
    reg [1:0] seed_idx_r;
    reg [1:0] row_step_r;
    reg [2:0] row_wait_r;
    reg next_row_ready_r;
    reg [16:0] offset_x_r;
    reg [16:0] offset_y_r;
    reg negative_x_r;
    reg negative_y_r;
    reg signed [17:0] x_r;
    reg signed [17:0] y_r;
    reg signed [17:0] x0_r;
    reg signed [17:0] x1_r;
    reg signed [17:0] unused_last_x_r;
    reg signed [17:0] last_y_r;
    reg signed [15:0] reuse_limit_r;
    reg [69:0] h_r;
    reg [173:0] gradient_r;
    reg [2:0] inclusive_r;
    reg [9:0] valid_r;
    reg [3:0] mask_r;
    wire advance_w;
    wire input_push_w;
    wire input_pop_w;
    wire output_push_w;
    wire output_pop_w;
    wire scan_w;
    wire last_w;
    wire row_end_w;
    wire seed_load_w;
    wire load_w;
    wire signed [16:0] offset_x_w;
    wire signed [16:0] offset_y_w;
    wire [15:0] unused_last_x_w;
    wire [15:0] unused_last_y_w;
    reg [63:0] input_bounds_r [0:1];
    reg [479:0] input_edge_r [0:1];
    reg [31:0] input_origin_r [0:1];
    reg [489:0] input_start_r [0:1];
    reg [783:0] input_gradient_r [0:1];
    reg [69:0] input_h_r [0:1];
    reg [173:0] input_normal_gradient_r [0:1];
    reg [15:0] output_x_r [0:1];
    assign fragment_x_o = output_x_r[output_read_r];
    reg [15:0] output_y_r [0:1];
    assign fragment_y_o = output_y_r[output_read_r];
    reg [3:0] output_mask_r [0:1];
    assign fragment_mask_o = output_mask_r[output_read_r];
    reg [0:0] output_quad_r [0:1];
    assign fragment_quad_o = output_quad_r[output_read_r];
    reg [1959:0] output_plane_r [0:1];
    assign fragment_plane_o = output_plane_r[output_read_r];
    reg [69:0] output_h_r [0:1];
    assign fragment_h_o = output_h_r[output_read_r];
    reg [173:0] output_gradient_r [0:1];
    assign fragment_gradient_o = output_gradient_r[output_read_r];
    reg [3:0] output_palette_r [0:1];
    assign fragment_palette_o = output_palette_r[output_read_r];
    reg [7:0] output_alpha_r [0:1];
    assign fragment_alpha_o = output_alpha_r[output_read_r];
    assign advance_w = output_count_r < 2;
    assign fragment_valid_o = (output_count_r != 0) && !stop_i;
    assign output_pop_w = fragment_valid_o && fragment_ready_i;
    assign triangle_setup_ready_o = input_count_r < 2 && cfg_valid_r;
    assign input_push_w = triangle_setup_valid_i && triangle_setup_ready_o && !stop_i;
    assign row_end_w = x_r[17:2] == unused_last_x_r[17:2];
    assign last_w = row_end_w && y_r == last_y_r;
    assign scan_w = active_r && advance_w && !stop_i &&
        (!row_end_w || last_w || next_row_ready_r);
    assign input_pop_w = input_count_r != 0 && state_r == S_IDLE &&
        (!active_r || (scan_w && last_w)) && advance_w && !stop_i;
    assign seed_load_w = state_r == S_LOAD && advance_w;
    assign load_w = seed_load_w || (scan_w && row_end_w && !last_w);
    assign output_push_w = valid_r[9] && advance_w && mask_r != 0 && !stop_i;
    assign offset_x_w = $signed({input_bounds_r[input_read_r][15],
        input_bounds_r[input_read_r][0 +: 16]}) -
        $signed({input_origin_r[input_read_r][15], input_origin_r[input_read_r][0 +: 16]});
    assign offset_y_w = $signed({input_bounds_r[input_read_r][31],
        input_bounds_r[input_read_r][16 +: 16]}) -
        $signed({input_origin_r[input_read_r][31], input_origin_r[input_read_r][16 +: 16]});
    assign unused_last_x_w = input_bounds_r[input_read_r][32 +: 16] - 16'd1;
    assign unused_last_y_w = input_bounds_r[input_read_r][48 +: 16] - 16'd1;
    reg [1959:0] plane_8_r;
    reg [1959:0] plane_9_r;
    reg [11:0] edge_nonzero_r;
    reg [11:0] edge_negative_r;
    reg [15:0] pipe_x_r [0:9];
    reg [15:0] pipe_y_r [0:9];
    reg [69:0] pipe_h_r [0:9];
    reg [173:0] pipe_gradient_r [0:9];
    reg [3:0] pipe_palette_r [0:9];
    reg [2:0] pipe_inclusive_r [0:8];
    reg [3:0] pipe_clip_r [0:8];
    wire [1959:0] plane_w;
    wire [839:0] edge_w;
    integer index_r;
    integer lane_r;
    reg [279:0] next_seed_r [0:9];
    reg [279:0] row_seed_r [0:9];
    reg [69:0] seed_accumulator_r [0:9];
    reg [69:0] row_accumulator_r [0:9];
    reg [69:0] gx3_r [0:9];
    wire [69:0] seed_result_w [0:9];
    reg [69:0] gx_r [0:9];
    reg [69:0] gy_r [0:9];
    reg [69:0] base_r [0:9];
    reg [69:0] prepare_gx_r [0:6];
    reg [69:0] prepare_gy_r [0:6];
    wire [69:0] signed_gx_w [0:6];
    wire [69:0] signed_gy_w [0:6];
    wire [69:0] accumulated_w [0:6];
    genvar stage;
    generate
        for (stage = 1; stage < 10; stage = stage + 1) begin : g_metadata
            always @(posedge clk_i) begin
                if (advance_w) begin
                    pipe_x_r[stage] <= pipe_x_r[stage-1];
                    pipe_y_r[stage] <= pipe_y_r[stage-1];
                    pipe_h_r[stage] <= pipe_h_r[stage-1];
                    pipe_gradient_r[stage] <= pipe_gradient_r[stage-1];
                    pipe_palette_r[stage] <= pipe_palette_r[stage-1];
                end
            end
            if (stage < 9) begin : g_coverage
                always @(posedge clk_i) begin
                    if (advance_w) begin
                        pipe_inclusive_r[stage] <= pipe_inclusive_r[stage-1];
                        pipe_clip_r[stage] <= pipe_clip_r[stage-1];
                    end
                end
            end
        end
    endgenerate
    genvar attribute;
    genvar lane;
    generate
        for (attribute = 0; attribute < 10; attribute = attribute + 1) begin : g_attribute
            wire [69:0] seed_a_w;
            wire [69:0] seed_b_w;
            if (attribute < 7) begin : g_prepare
                edrv32_gpu_raster_add u_sign_x (
                    .clk_i(clk_i),
                    .en_i(advance_w),
                    .a_i(gx_r[attribute] ^ {70{negative_x_r}}),
                    .b_i({69'b0, negative_x_r}),
                    .sum_o(signed_gx_w[attribute])
                );
                edrv32_gpu_raster_add u_sign_y (
                    .clk_i(clk_i),
                    .en_i(advance_w),
                    .a_i(gy_r[attribute] ^ {70{negative_y_r}}),
                    .b_i({69'b0, negative_y_r}),
                    .sum_o(signed_gy_w[attribute])
                );
                edrv32_gpu_raster_prepare u_accumulate (
                    .clk_i(clk_i),
                    .en_i(advance_w),
                    .a_i(base_r[attribute]),
                    .b_i(offset_x_r[0] ? prepare_gx_r[attribute] : 70'b0),
                    .c_i(offset_y_r[0] ? prepare_gy_r[attribute] : 70'b0),
                    .sum_o(accumulated_w[attribute])
                );
            end
            assign seed_a_w = state_r == S_SIGN ? gx_r[attribute] :
                state_r == S_SEED ? (seed_idx_r == 0 ? base_r[attribute] :
                seed_accumulator_r[attribute]) :
                (row_step_r == 0 ? row_seed_r[attribute][0 +: 70] : row_accumulator_r[attribute]);
            assign seed_b_w = state_r == S_SIGN ? gx_r[attribute] << 1 :
                state_r == S_SEED ? gx_r[attribute] << 2 :
                (row_step_r == 0 ? gy_r[attribute] : gx_r[attribute] << 2);
            edrv32_gpu_raster_add u_seed (
                .clk_i(clk_i),
                .en_i(advance_w),
                .a_i(seed_a_w),
                .b_i(seed_b_w),
                .sum_o(seed_result_w[attribute])
            );
            wire [69:0] base_w;
            edrv32_gpu_raster_plane u_plane (
                .clk_i(clk_i),
                .en_i(advance_w),
                .load_i(load_w),
                .issue_i(scan_w),
                .reuse_i($signed(x_r[17:2]) < reuse_limit_r),
                .seed_i(next_seed_r[attribute]),
                .delta_i(gx_r[attribute] << 4),
                .plane_o(base_w)
            );
            reg [69:0] gx_pipe_r [0:3];
            reg [69:0] gx3_pipe_r [0:3];
            reg [69:0] base_pipe_r [0:3];
            always @(posedge clk_i) begin
                if (advance_w) begin
                    gx_pipe_r[0] <= gx_r[attribute];
                    gx_pipe_r[1] <= gx_pipe_r[0];
                    gx_pipe_r[2] <= gx_pipe_r[1];
                    gx_pipe_r[3] <= gx_pipe_r[2];
                    gx3_pipe_r[0] <= gx3_r[attribute];
                    gx3_pipe_r[1] <= gx3_pipe_r[0];
                    gx3_pipe_r[2] <= gx3_pipe_r[1];
                    gx3_pipe_r[3] <= gx3_pipe_r[2];
                    base_pipe_r[0] <= base_w;
                    base_pipe_r[1] <= base_pipe_r[0];
                    base_pipe_r[2] <= base_pipe_r[1];
                    base_pipe_r[3] <= base_pipe_r[2];
                    if (state_r == S_SIGN && wait_r == 4) begin
                        gx3_r[attribute] <= seed_result_w[attribute];
                    end
                    if (state_r == S_SEED) begin
                        if (seed_idx_r == 0 && wait_r == 0) begin
                            next_seed_r[attribute][0 +: 70] <= base_r[attribute];
                        end
                        if (wait_r == 4) begin
                            next_seed_r[attribute][({30'b0, seed_idx_r}+1)*70 +: 70] <=
                                seed_result_w[attribute];
                            seed_accumulator_r[attribute] <= seed_result_w[attribute];
                        end
                    end
                    if (active_r && !next_row_ready_r && row_wait_r == 4) begin
                        next_seed_r[attribute][row_step_r*70 +: 70] <= seed_result_w[attribute];
                        row_accumulator_r[attribute] <= seed_result_w[attribute];
                    end
                    if (load_w) begin
                        row_seed_r[attribute] <= next_seed_r[attribute];
                    end
                end
            end
            for (lane = 0; lane < 4; lane = lane + 1) begin : g_lane
                wire [69:0] attribute_w;
                if (lane == 0) begin : g_base
                    assign attribute_w = base_pipe_r[3];
                end else begin : g_expand
                    edrv32_gpu_raster_add u_add (
                        .clk_i(clk_i),
                        .en_i(advance_w),
                        .a_i(base_w),
                        .b_i(lane == 3 ? gx3_pipe_r[3] : gx_pipe_r[3] << (lane-1)),
                        .sum_o(attribute_w)
                    );
                end
                if (attribute < 7) begin : g_plane
                    assign plane_w[lane*490+attribute*70 +: 70] = attribute_w;
                end else begin : g_edge
                    assign edge_w[lane*210+(attribute-7)*70 +: 70] = attribute_w;
                end
            end
        end
    endgenerate

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            input_count_r <= 0;
            input_read_r <= 0;
            input_write_r <= 0;
            output_count_r <= 0;
            output_read_r <= 0;
            output_write_r <= 0;
            state_r <= S_IDLE;
            active_r <= 0;
            prepared_nonempty_r <= 0;
            wait_r <= 0;
            bit_r <= 0;
            seed_idx_r <= 0;
            row_step_r <= 0;
            row_wait_r <= 0;
            next_row_ready_r <= 0;
            valid_r <= 0;
            unit_done_o <= 0;
        end else begin
            if (!finish_i) begin
                unit_done_o <= 0;
            end else if (input_count_r == 0 && !active_r && state_r == S_IDLE &&
                output_count_r == 0 && valid_r == 0 && !cfg_pending_r) begin
                unit_done_o <= 1;
            end
            if (input_push_w != input_pop_w) begin
                input_count_r <= input_push_w ? input_count_r + 1'b1 : input_count_r - 1'b1;
            end
            if (output_push_w != output_pop_w) begin
                output_count_r <= output_push_w ? output_count_r + 1'b1 : output_count_r - 1'b1;
            end
            if (input_push_w) begin
                input_write_r <= !input_write_r;
            end
            if (input_pop_w) begin
                input_read_r <= !input_read_r;
            end
            if (output_push_w) begin
                output_write_r <= !output_write_r;
            end
            if (output_pop_w) begin
                output_read_r <= !output_read_r;
            end
            if (advance_w) begin
                valid_r <= {valid_r[8:0], scan_w};
                if (active_r && !next_row_ready_r) begin
                    row_wait_r <= row_wait_r + 1'b1;
                    if (row_wait_r == 4) begin
                        row_wait_r <= 0;
                        row_step_r <= row_step_r + 1'b1;
                        if (row_step_r == 3) begin
                            next_row_ready_r <= 1;
                        end
                    end
                end
                if (load_w) begin
                    row_step_r <= 0;
                    row_wait_r <= 0;
                    next_row_ready_r <= 0;
                end
                if (scan_w && last_w) begin
                    active_r <= 0;
                end
                if (state_r == S_SIGN || state_r == S_ACCUMULATE || state_r == S_SEED) begin
                    wait_r <= wait_r + 1'b1;
                end
                if (state_r == S_SIGN && wait_r == 4) begin
                    state_r <= S_ACCUMULATE;
                    wait_r <= 0;
                end
                if (state_r == S_ACCUMULATE && wait_r == 5) begin
                    wait_r <= 0;
                    bit_r <= bit_r + 1'b1;
                    if (bit_r == 16) begin
                        state_r <= S_SEED;
                        seed_idx_r <= 0;
                    end
                end
                if (state_r == S_SEED && wait_r == 4) begin
                    wait_r <= 0;
                    seed_idx_r <= seed_idx_r + 1'b1;
                    if (seed_idx_r == 2) begin
                        state_r <= S_LOAD;
                    end
                end
                if (seed_load_w) begin
                    state_r <= S_IDLE;
                    active_r <= prepared_nonempty_r;
                end
            end
            if (input_pop_w) begin
                state_r <= S_SIGN;
                wait_r <= 0;
                bit_r <= 0;
                active_r <= 0;
                prepared_nonempty_r <= $signed(input_bounds_r[input_read_r][0 +: 16]) <
                    $signed(input_bounds_r[input_read_r][32 +: 16]) &&
                    $signed(input_bounds_r[input_read_r][16 +: 16]) <
                    $signed(input_bounds_r[input_read_r][48 +: 16]);
            end
            if (stop_i) begin
                input_count_r <= 0;
                output_count_r <= 0;
                input_read_r <= input_write_r;
                output_read_r <= output_write_r;
                state_r <= S_IDLE;
                active_r <= 0;
                valid_r <= 0;
            end
        end
    end
    always @(posedge clk_i) begin
        if (input_push_w) begin
            input_bounds_r[input_write_r] <= triangle_setup_bounds_i;
            input_edge_r[input_write_r] <= triangle_setup_edge_i;
            input_origin_r[input_write_r] <= triangle_setup_origin_i;
            input_start_r[input_write_r] <= triangle_setup_start_i;
            input_gradient_r[input_write_r] <= triangle_setup_gradient_i;
            input_h_r[input_write_r] <= triangle_setup_h_i;
            input_normal_gradient_r[input_write_r] <= triangle_setup_normal_gradient_i;
        end
        if (advance_w) begin
            pipe_x_r[0] <= x_r[15:0];
            pipe_y_r[0] <= y_r[15:0];
            pipe_h_r[0] <= h_r;
            pipe_gradient_r[0] <= gradient_r;
            pipe_palette_r[0] <= palette_r;
            pipe_inclusive_r[0] <= inclusive_r;
            plane_8_r <= plane_w;
            plane_9_r <= plane_8_r;
            for (lane_r = 0; lane_r < 4; lane_r = lane_r + 1) begin
                pipe_clip_r[0][lane_r] <=
                    $signed({x_r[17:2], lane_r[1:0]}) >= clip_x0_r &&
                    $signed({x_r[17:2], lane_r[1:0]}) < clip_x1_r &&
                    $signed({x_r[17:2], lane_r[1:0]}) < x1_r &&
                    y_r >= clip_y0_r && y_r < clip_y1_r;
                for (index_r = 0; index_r < 3; index_r = index_r + 1) begin
                    edge_nonzero_r[lane_r*3+index_r] <=
                        edge_w[lane_r*210+index_r*70 +: 39] != 0;
                    edge_negative_r[lane_r*3+index_r] <= edge_w[lane_r*210+index_r*70+69];
                end
                mask_r[lane_r] <= pipe_clip_r[8][lane_r] &&
                    !edge_negative_r[lane_r*3] &&
                    (pipe_inclusive_r[8][0] || edge_nonzero_r[lane_r*3]) &&
                    !edge_negative_r[lane_r*3+1] &&
                    (pipe_inclusive_r[8][1] || edge_nonzero_r[lane_r*3+1]) &&
                    !edge_negative_r[lane_r*3+2] &&
                    (pipe_inclusive_r[8][2] || edge_nonzero_r[lane_r*3+2]);
            end
            if (state_r == S_ACCUMULATE && wait_r == 5) begin
                offset_x_r <= offset_x_r >> 1;
                offset_y_r <= offset_y_r >> 1;
            end
        end
        if (scan_w) begin
            if (row_end_w) begin
                x_r <= x0_r;
                y_r <= y_r + 1'b1;
            end else begin
                x_r <= x_r + 18'sd4;
            end
        end
        if (advance_w && state_r == S_SIGN && wait_r == 0) begin
            reuse_limit_r <= $signed(unused_last_x_r[17:2]) - 16'sd3;
        end
        if (input_pop_w) begin
            negative_x_r <= offset_x_w[16];
            negative_y_r <= offset_y_w[16];
            offset_x_r <= offset_x_w[16] ? $unsigned(-offset_x_w) : $unsigned(offset_x_w);
            offset_y_r <= offset_y_w[16] ? $unsigned(-offset_y_w) : $unsigned(offset_y_w);
            x_r <= {{2{input_bounds_r[input_read_r][15]}},
                input_bounds_r[input_read_r][0 +: 16]};
            x0_r <= {{2{input_bounds_r[input_read_r][15]}},
                input_bounds_r[input_read_r][0 +: 16]};
            y_r <= {{2{input_bounds_r[input_read_r][31]}},
                input_bounds_r[input_read_r][16 +: 16]};
            x1_r <= {{2{input_bounds_r[input_read_r][47]}},
                input_bounds_r[input_read_r][32 +: 16]};
            unused_last_x_r <= {{2{unused_last_x_w[15]}}, unused_last_x_w[15:2], 2'b0};
            last_y_r <= {{2{unused_last_y_w[15]}}, unused_last_y_w};
            h_r <= input_h_r[input_read_r];
            gradient_r <= input_normal_gradient_r[input_read_r];
            for (index_r = 0; index_r < 3; index_r = index_r + 1) begin
                inclusive_r[index_r] <= input_edge_r[input_read_r][index_r*160+159] == 0;
            end
        end
        for (index_r = 0; index_r < 7; index_r = index_r + 1) begin
            if (advance_w) begin
                if (state_r == S_SIGN && wait_r == 4) begin
                    prepare_gx_r[index_r] <= signed_gx_w[index_r];
                    prepare_gy_r[index_r] <= signed_gy_w[index_r];
                end
                if (state_r == S_ACCUMULATE && wait_r == 5) begin
                    base_r[index_r] <= accumulated_w[index_r];
                    prepare_gx_r[index_r] <= prepare_gx_r[index_r] << 1;
                    prepare_gy_r[index_r] <= prepare_gy_r[index_r] << 1;
                end
            end
            if (input_pop_w) begin
                base_r[index_r] <= input_start_r[input_read_r][index_r*70 +: 70];
                gx_r[index_r] <= {{14{input_gradient_r[input_read_r][index_r*112+55]}},
                    input_gradient_r[input_read_r][index_r*112 +: 56]};
                gy_r[index_r] <= {{14{input_gradient_r[input_read_r][index_r*112+111]}},
                    input_gradient_r[input_read_r][index_r*112+56 +: 56]};
            end
        end
        for (index_r = 0; index_r < 3; index_r = index_r + 1) begin
            if (input_pop_w) begin
                base_r[index_r+7] <= {{30{input_edge_r[input_read_r][index_r*160+39]}},
                    input_edge_r[input_read_r][index_r*160 +: 40]};
                gx_r[index_r+7] <= {{30{input_edge_r[input_read_r][index_r*160+79]}},
                    input_edge_r[input_read_r][index_r*160+40 +: 40]};
                gy_r[index_r+7] <= {{30{input_edge_r[input_read_r][index_r*160+119]}},
                    input_edge_r[input_read_r][index_r*160+80 +: 40]};
            end
        end
        if (output_push_w) begin
            output_x_r[output_write_r] <= pipe_x_r[9];
            output_y_r[output_write_r] <= pipe_y_r[9];
            output_mask_r[output_write_r] <= mask_r;
            output_plane_r[output_write_r] <= plane_9_r;
            output_quad_r[output_write_r] <= 1'b0;
            output_h_r[output_write_r] <= pipe_h_r[9];
            output_gradient_r[output_write_r] <= pipe_gradient_r[9];
            output_palette_r[output_write_r] <= pipe_palette_r[9];
            output_alpha_r[output_write_r] <= 8'd255;
        end
    end
endmodule
