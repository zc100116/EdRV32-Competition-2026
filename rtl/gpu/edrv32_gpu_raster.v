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

    wire [2252:0] output_input_w;
    wire [2303:0] unused_output_data_w;
    reg signed [17:0] clip_x0_r;
    reg signed [17:0] clip_y0_r;
    reg signed [17:0] clip_x1_r;
    reg signed [17:0] clip_y1_r;
    reg [3:0] palette_r;
    wire [839:0] edge_w;
    wire unused_state_w;
    wire signed [17:0] target_x0_w;
    wire signed [17:0] target_y0_w;
    wire signed [17:0] target_x1_w;
    wire signed [17:0] target_y1_w;
    wire signed [17:0] scissor_x0_w;
    wire signed [17:0] scissor_y0_w;
    wire signed [17:0] scissor_x1_w;
    wire signed [17:0] scissor_y1_w;
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
    reg [1:0] input_count_r;
    reg input_read_r;
    reg input_write_r;
    reg [4:0] output_count_r;
    reg [4:0] credit_used_r;
    reg output_valid_r;
    wire culled_w;
    wire output_read_w;
    wire [5:0] output_addr_w;
    reg [5:0] output_read_r;
    reg [5:0] output_write_r;
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
    wire [3:0] mask_w;
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
    reg [31:0] input_origin_r [0:1];
    reg [69:0] input_h_r [0:1];
    reg [173:0] input_normal_gradient_r [0:1];
    wire [11:0] edge_nonzero_w;
    wire [11:0] edge_negative_w;
    wire [2:0] edge_inclusive_w;
    wire [3:0] clip_w;
    reg [8:0] delay_write_r;
    wire [6:0] metadata_9_input_w;
    wire [71:0] unused_metadata_9_data_w;
    wire [8:0] metadata_9_read_w;
    wire [2:0] pipe_inclusive_w;
    wire [3:0] pipe_clip_w;
    wire [279:0] metadata_10_input_w;
    wire [287:0] unused_metadata_10_data_w;
    wire [8:0] metadata_10_read_w;
    wire [15:0] pipe_x_w;
    wire [15:0] pipe_y_w;
    wire [69:0] pipe_h_w;
    wire [173:0] pipe_gradient_w;
    wire [3:0] pipe_palette_w;

    assign unused_state_w = ^{render_state_pixel_i, render_state_tex_i, render_state_target_i,
        draw_command_i, draw_valid_i, triangle_setup_edge_i, edge_w};
    assign render_state_ready_o = 1'b1;
    assign draw_ready_o = 1'b1;

    assign target_x0_w = {{2{render_state_target_i[47]}}, render_state_target_i[32 +: 16]};
    assign target_y0_w = {{2{render_state_target_i[63]}}, render_state_target_i[48 +: 16]};
    assign target_x1_w = target_x0_w + (render_state_wide_i ? 18'sd1280 : 18'sd640);
    assign target_y1_w = target_y0_w + (render_state_wide_i ? 18'sd90 : 18'sd180);
    assign scissor_x0_w = {{2{render_state_target_i[79]}}, render_state_target_i[64 +: 16]};
    assign scissor_y0_w = {{2{render_state_target_i[95]}}, render_state_target_i[80 +: 16]};
    assign scissor_x1_w = {{2{render_state_target_i[111]}}, render_state_target_i[96 +: 16]};
    assign scissor_y1_w = {{2{render_state_target_i[127]}}, render_state_target_i[112 +: 16]};
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

    // Two setup slots and sixteen scan credits isolate downstream backpressure.
    localparam S_IDLE = 3'd0;
    localparam S_SIGN = 3'd1;
    localparam S_ACCUMULATE = 3'd2;
    localparam S_SEED = 3'd3;
    localparam S_LOAD = 3'd4;
    assign advance_w = 1'b1;
    assign fragment_valid_o = output_valid_r && !stop_i;
    assign output_pop_w = fragment_valid_o && fragment_ready_i;
    assign triangle_setup_ready_o = input_count_r < 2 && cfg_valid_r;
    assign input_push_w = triangle_setup_valid_i && triangle_setup_ready_o && !stop_i;
    assign row_end_w = x_r[17:2] == unused_last_x_r[17:2];
    assign last_w = row_end_w && y_r == last_y_r;
    assign scan_w = active_r && credit_used_r < 16 && !stop_i &&
        (!row_end_w || last_w || next_row_ready_r);
    assign input_pop_w = input_count_r != 0 && state_r == S_IDLE &&
        (!active_r || (scan_w && last_w)) && advance_w && !stop_i;
    assign seed_load_w = state_r == S_LOAD && advance_w;
    assign load_w = seed_load_w || (scan_w && row_end_w && !last_w);
    assign output_push_w = valid_r[9] && advance_w && mask_w != 0 && !stop_i;
    assign culled_w = valid_r[9] && mask_w == 0 && !stop_i;
    assign output_read_w = !stop_i && ((output_count_r != 0 && !output_valid_r) ||
        (output_pop_w && output_count_r > 1));
    assign output_addr_w = output_read_r + {5'b0, output_pop_w};
    assign offset_x_w = $signed({input_bounds_r[input_read_r][15],
        input_bounds_r[input_read_r][0 +: 16]}) -
        $signed({input_origin_r[input_read_r][15], input_origin_r[input_read_r][0 +: 16]});
    assign offset_y_w = $signed({input_bounds_r[input_read_r][31],
        input_bounds_r[input_read_r][16 +: 16]}) -
        $signed({input_origin_r[input_read_r][31], input_origin_r[input_read_r][16 +: 16]});
    assign unused_last_x_w = input_bounds_r[input_read_r][32 +: 16] - 16'd1;
    assign unused_last_y_w = input_bounds_r[input_read_r][48 +: 16] - 16'd1;
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) delay_write_r <= 0;
        else delay_write_r <= delay_write_r + 1'b1;
    end
    assign metadata_9_read_w = delay_write_r - 9'd8;
    assign metadata_9_input_w[0 +: 3] = inclusive_r;
    assign pipe_inclusive_w = unused_metadata_9_data_w[0 +: 3];
    assign metadata_9_input_w[3 +: 4] = clip_w;
    assign pipe_clip_w = unused_metadata_9_data_w[3 +: 4];
    edrv32_ram_gpu_delay u_metadata_9_0 (
        .clk_i(clk_i),
        .wr_en_i(1'b1),
        .wr_addr_i(delay_write_r),
        .wr_data_i({65'b0, metadata_9_input_w[0 +: 7]}),
        .rd_en_i(1'b1),
        .rd_addr_i(metadata_9_read_w),
        .rd_data_o(unused_metadata_9_data_w[0 +: 72])
    );
    assign metadata_10_read_w = delay_write_r - 9'd9;
    assign metadata_10_input_w[0 +: 16] = x_r[15:0];
    assign pipe_x_w = unused_metadata_10_data_w[0 +: 16];
    assign metadata_10_input_w[16 +: 16] = y_r[15:0];
    assign pipe_y_w = unused_metadata_10_data_w[16 +: 16];
    assign metadata_10_input_w[32 +: 70] = h_r;
    assign pipe_h_w = unused_metadata_10_data_w[32 +: 70];
    assign metadata_10_input_w[102 +: 174] = gradient_r;
    assign pipe_gradient_w = unused_metadata_10_data_w[102 +: 174];
    assign metadata_10_input_w[276 +: 4] = palette_r;
    assign pipe_palette_w = unused_metadata_10_data_w[276 +: 4];
    edrv32_ram_gpu_delay u_metadata_10_0 (
        .clk_i(clk_i),
        .wr_en_i(1'b1),
        .wr_addr_i(delay_write_r),
        .wr_data_i(metadata_10_input_w[0 +: 72]),
        .rd_en_i(1'b1),
        .rd_addr_i(metadata_10_read_w),
        .rd_data_o(unused_metadata_10_data_w[0 +: 72])
    );
    edrv32_ram_gpu_delay u_metadata_10_1 (
        .clk_i(clk_i),
        .wr_en_i(1'b1),
        .wr_addr_i(delay_write_r),
        .wr_data_i(metadata_10_input_w[72 +: 72]),
        .rd_en_i(1'b1),
        .rd_addr_i(metadata_10_read_w),
        .rd_data_o(unused_metadata_10_data_w[72 +: 72])
    );
    edrv32_ram_gpu_delay u_metadata_10_2 (
        .clk_i(clk_i),
        .wr_en_i(1'b1),
        .wr_addr_i(delay_write_r),
        .wr_data_i(metadata_10_input_w[144 +: 72]),
        .rd_en_i(1'b1),
        .rd_addr_i(metadata_10_read_w),
        .rd_data_o(unused_metadata_10_data_w[144 +: 72])
    );
    edrv32_ram_gpu_delay u_metadata_10_3 (
        .clk_i(clk_i),
        .wr_en_i(1'b1),
        .wr_addr_i(delay_write_r),
        .wr_data_i({8'b0, metadata_10_input_w[216 +: 64]}),
        .rd_en_i(1'b1),
        .rd_addr_i(metadata_10_read_w),
        .rd_data_o(unused_metadata_10_data_w[216 +: 72])
    );
    genvar attribute;
    genvar lane;
    generate
        // Ten channels each own one seed adder, one feedback adder and three lane adders.
        // Seven plane channels also own two sign adders and one CSA/preparation adder.
        // Each adder retains four registered carry stages; preparation adds its CSA stage.
        for (attribute = 0; attribute < 10; attribute = attribute + 1) begin : g_attribute
            reg [69:0] gx_r;
            reg [69:0] gy_r;
            reg [69:0] base_r;
            reg [69:0] gx3_r;
            reg [69:0] seed_accumulator_r;
            reg [69:0] row_accumulator_r;
            wire [279:0] next_seed_w;
            reg [69:0] row_seed_r;
            wire [69:0] seed_result_w;
            wire [69:0] seed_a_w;
            wire [69:0] seed_b_w;
            if (attribute < 7) begin : g_prepare
                reg [69:0] prepare_gx_r;
                reg [69:0] prepare_gy_r;
                wire [69:0] signed_gx_w;
                wire [69:0] signed_gy_w;
                wire [69:0] accumulated_w;
                reg [69:0] input_start_r [0:1];
                reg [55:0] input_gx_r [0:1];
                reg [55:0] input_gy_r [0:1];
                always @(posedge clk_i) begin
                    if (input_push_w) begin
                        input_start_r[input_write_r] <= triangle_setup_start_i[attribute*70 +: 70];
                        input_gx_r[input_write_r] <= triangle_setup_gradient_i[attribute*112 +: 56];
                        input_gy_r[input_write_r] <=
                            triangle_setup_gradient_i[attribute*112+56 +: 56];
                    end
                    if (advance_w) begin
                        if (state_r == S_SIGN && wait_r == 4) begin
                            prepare_gx_r <= signed_gx_w;
                            prepare_gy_r <= signed_gy_w;
                        end
                        if (state_r == S_ACCUMULATE && wait_r == 5) begin
                            prepare_gx_r <= prepare_gx_r << 1;
                            prepare_gy_r <= prepare_gy_r << 1;
                        end
                    end
                    if (input_pop_w) begin
                        gx_r <= {{14{input_gx_r[input_read_r][55]}}, input_gx_r[input_read_r]};
                        gy_r <= {{14{input_gy_r[input_read_r][55]}}, input_gy_r[input_read_r]};
                    end
                    if (input_pop_w || (advance_w && state_r == S_ACCUMULATE && wait_r == 5))
                        base_r <= input_pop_w ? input_start_r[input_read_r] : accumulated_w;
                end
                edrv32_gpu_raster_add u_sign_x (
                    .clk_i(clk_i),
                    .en_i(advance_w),
                    .a_i(gx_r ^ {70{negative_x_r}}),
                    .b_i({69'b0, negative_x_r}),
                    .sum_o(signed_gx_w)
                );
                edrv32_gpu_raster_add u_sign_y (
                    .clk_i(clk_i),
                    .en_i(advance_w),
                    .a_i(gy_r ^ {70{negative_y_r}}),
                    .b_i({69'b0, negative_y_r}),
                    .sum_o(signed_gy_w)
                );
                edrv32_gpu_raster_prepare u_accumulate (
                    .clk_i(clk_i),
                    .en_i(advance_w),
                    .a_i(base_r),
                    .b_i(offset_x_r[0] ? prepare_gx_r : 70'b0),
                    .c_i(offset_y_r[0] ? prepare_gy_r : 70'b0),
                    .sum_o(accumulated_w)
                );
            end else begin : g_edge_input
                reg [39:0] input_start_r [0:1];
                reg [39:0] input_gx_r [0:1];
                reg [39:0] input_gy_r [0:1];
                reg input_inclusive_r [0:1];
                assign edge_inclusive_w[attribute-7] = input_inclusive_r[input_read_r];
                always @(posedge clk_i) begin
                    if (input_push_w) begin
                        input_start_r[input_write_r] <=
                            triangle_setup_edge_i[(attribute-7)*160 +: 40];
                        input_gx_r[input_write_r] <=
                            triangle_setup_edge_i[(attribute-7)*160+40 +: 40];
                        input_gy_r[input_write_r] <=
                            triangle_setup_edge_i[(attribute-7)*160+80 +: 40];
                        input_inclusive_r[input_write_r] <=
                            triangle_setup_edge_i[(attribute-7)*160+159] == 0;
                    end
                    if (input_pop_w) begin
                        base_r <= {{30{input_start_r[input_read_r][39]}},
                            input_start_r[input_read_r]};
                        gx_r <= {{30{input_gx_r[input_read_r][39]}}, input_gx_r[input_read_r]};
                        gy_r <= {{30{input_gy_r[input_read_r][39]}}, input_gy_r[input_read_r]};
                    end
                end
            end
            assign seed_a_w = state_r == S_SIGN ? gx_r :
                state_r == S_SEED ? (seed_idx_r == 0 ? base_r :
                seed_accumulator_r) :
                (row_step_r == 0 ? row_seed_r : row_accumulator_r);
            assign seed_b_w = state_r == S_SIGN ? gx_r << 1 :
                state_r == S_SEED ? gx_r << 2 :
                (row_step_r == 0 ? gy_r : gx_r << 2);
            edrv32_gpu_raster_add u_seed (
                .clk_i(clk_i),
                .en_i(advance_w),
                .a_i(seed_a_w),
                .b_i(seed_b_w),
                .sum_o(seed_result_w)
            );
            wire [69:0] base_w;
            edrv32_gpu_raster_plane u_plane (
                .clk_i(clk_i),
                .en_i(advance_w),
                .load_i(load_w),
                .issue_i(scan_w),
                .reuse_i($signed(x_r[17:2]) < reuse_limit_r),
                .seed_i(next_seed_w),
                .delta_i(gx_r << 4),
                .plane_o(base_w)
            );
            reg [69:0] gx_pipe_0_r;
            reg [69:0] gx_pipe_1_r;
            reg [69:0] gx_pipe_2_r;
            reg [69:0] gx_pipe_3_r;
            reg [69:0] gx3_pipe_0_r;
            reg [69:0] gx3_pipe_1_r;
            reg [69:0] gx3_pipe_2_r;
            reg [69:0] gx3_pipe_3_r;
            reg [69:0] base_pipe_0_r;
            reg [69:0] base_pipe_1_r;
            reg [69:0] base_pipe_2_r;
            reg [69:0] base_pipe_3_r;
            always @(posedge clk_i) begin
                if (advance_w) begin
                    gx_pipe_0_r <= gx_r;
                    gx_pipe_1_r <= gx_pipe_0_r;
                    gx_pipe_2_r <= gx_pipe_1_r;
                    gx_pipe_3_r <= gx_pipe_2_r;
                    gx3_pipe_0_r <= gx3_r;
                    gx3_pipe_1_r <= gx3_pipe_0_r;
                    gx3_pipe_2_r <= gx3_pipe_1_r;
                    gx3_pipe_3_r <= gx3_pipe_2_r;
                    base_pipe_0_r <= base_w;
                    base_pipe_1_r <= base_pipe_0_r;
                    base_pipe_2_r <= base_pipe_1_r;
                    base_pipe_3_r <= base_pipe_2_r;
                    if (state_r == S_SIGN && wait_r == 4) begin
                        gx3_r <= seed_result_w;
                    end
                    if (state_r == S_SEED && wait_r == 4)
                        seed_accumulator_r <= seed_result_w;
                    if (active_r && !next_row_ready_r && row_wait_r == 4)
                        row_accumulator_r <= seed_result_w;
                    if (load_w) row_seed_r <= next_seed_w[69:0];
                end
            end
            // Four independent 70-bit phase seeds; one priority-selected update per phase.
            for (lane = 0; lane < 4; lane = lane + 1) begin : g_seed
                reg [69:0] value_r;
                wire initial_w;
                wire step_w;
                wire row_w;
                assign initial_w = lane == 0 && state_r == S_SEED
                    && seed_idx_r == 0 && wait_r == 0;
                assign step_w = lane > 0 && state_r == S_SEED
                    && seed_idx_r == lane-1 && wait_r == 4;
                assign row_w = active_r && !next_row_ready_r && row_wait_r == 4
                    && row_step_r == lane;
                always @(posedge clk_i) begin
                    if (advance_w && (initial_w || step_w || row_w))
                        value_r <= row_w || step_w ? seed_result_w : base_r;
                end
                assign next_seed_w[lane*70 +: 70] = value_r;
            end
            for (lane = 0; lane < 4; lane = lane + 1) begin : g_lane
                wire [69:0] attribute_w;
                if (lane == 0) begin : g_base
                    assign attribute_w = base_pipe_3_r;
                end else begin : g_expand
                    edrv32_gpu_raster_add u_add (
                        .clk_i(clk_i),
                        .en_i(advance_w),
                        .a_i(base_w),
                        .b_i(lane == 3 ? gx3_pipe_3_r : gx_pipe_3_r << (lane-1)),
                        .sum_o(attribute_w)
                    );
                end
                if (attribute < 7) begin : g_plane
                    reg [69:0] plane_8_r;
                    reg [69:0] plane_9_r;
                    always @(posedge clk_i) begin
                        if (advance_w) begin
                            plane_8_r <= attribute_w;
                            plane_9_r <= plane_8_r;
                        end
                    end
                    assign output_input_w[293+lane*490+attribute*70 +: 70] =
                        plane_9_r;
                    assign fragment_plane_o[lane*490+attribute*70 +: 70] =
                        unused_output_data_w[293+lane*490+attribute*70 +: 70];
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
            credit_used_r <= 0;
            output_valid_r <= 0;
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
            begin
                case ({scan_w, output_pop_w, culled_w})
                    3'b100: credit_used_r <= credit_used_r + 1'b1;
                    3'b001, 3'b010, 3'b111: credit_used_r <= credit_used_r - 1'b1;
                    3'b011: credit_used_r <= credit_used_r - 5'd2;
                    default: credit_used_r <= credit_used_r;
                endcase
            end
            if (output_read_w) output_valid_r <= 1;
            else if (output_pop_w) output_valid_r <= 0;
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
                output_write_r <= output_write_r + 1'b1;
            end
            if (output_pop_w) begin
                output_read_r <= output_read_r + 1'b1;
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
                credit_used_r <= 0;
                output_valid_r <= 0;
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
            input_origin_r[input_write_r] <= triangle_setup_origin_i;
            input_h_r[input_write_r] <= triangle_setup_h_i;
            input_normal_gradient_r[input_write_r] <= triangle_setup_normal_gradient_i;
        end
        if (advance_w) begin
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
            inclusive_r <= edge_inclusive_w;
        end
    end
    assign output_input_w[0 +: 16] = pipe_x_w;
    assign fragment_x_o = unused_output_data_w[0 +: 16];
    assign output_input_w[16 +: 16] = pipe_y_w;
    assign fragment_y_o = unused_output_data_w[16 +: 16];
    assign output_input_w[32 +: 4] = mask_w;
    assign fragment_mask_o = unused_output_data_w[32 +: 4];
    assign output_input_w[36 +: 1] = 1'b0;
    assign fragment_quad_o = unused_output_data_w[36 +: 1];
    assign output_input_w[37 +: 70] = pipe_h_w;
    assign fragment_h_o = unused_output_data_w[37 +: 70];
    assign output_input_w[107 +: 174] = pipe_gradient_w;
    assign fragment_gradient_o = unused_output_data_w[107 +: 174];
    assign output_input_w[281 +: 4] = pipe_palette_w;
    assign fragment_palette_o = unused_output_data_w[281 +: 4];
    assign output_input_w[285 +: 8] = 8'd255;
    assign fragment_alpha_o = unused_output_data_w[285 +: 8];
    edrv32_ram_gpu_read_pool u_output_0 (
        .clk_i(clk_i),
        .wr_en_i(output_push_w),
        .wr_addr_i(output_write_r),
        .wr_data_i(output_input_w[0 +: 256]),
        .rd_en_i(output_read_w),
        .rd_addr_i(output_addr_w),
        .rd_data_o(unused_output_data_w[0 +: 256])
    );
    edrv32_ram_gpu_read_pool u_output_1 (
        .clk_i(clk_i),
        .wr_en_i(output_push_w),
        .wr_addr_i(output_write_r),
        .wr_data_i(output_input_w[256 +: 256]),
        .rd_en_i(output_read_w),
        .rd_addr_i(output_addr_w),
        .rd_data_o(unused_output_data_w[256 +: 256])
    );
    edrv32_ram_gpu_read_pool u_output_2 (
        .clk_i(clk_i),
        .wr_en_i(output_push_w),
        .wr_addr_i(output_write_r),
        .wr_data_i(output_input_w[512 +: 256]),
        .rd_en_i(output_read_w),
        .rd_addr_i(output_addr_w),
        .rd_data_o(unused_output_data_w[512 +: 256])
    );
    edrv32_ram_gpu_read_pool u_output_3 (
        .clk_i(clk_i),
        .wr_en_i(output_push_w),
        .wr_addr_i(output_write_r),
        .wr_data_i(output_input_w[768 +: 256]),
        .rd_en_i(output_read_w),
        .rd_addr_i(output_addr_w),
        .rd_data_o(unused_output_data_w[768 +: 256])
    );
    edrv32_ram_gpu_read_pool u_output_4 (
        .clk_i(clk_i),
        .wr_en_i(output_push_w),
        .wr_addr_i(output_write_r),
        .wr_data_i(output_input_w[1024 +: 256]),
        .rd_en_i(output_read_w),
        .rd_addr_i(output_addr_w),
        .rd_data_o(unused_output_data_w[1024 +: 256])
    );
    edrv32_ram_gpu_read_pool u_output_5 (
        .clk_i(clk_i),
        .wr_en_i(output_push_w),
        .wr_addr_i(output_write_r),
        .wr_data_i(output_input_w[1280 +: 256]),
        .rd_en_i(output_read_w),
        .rd_addr_i(output_addr_w),
        .rd_data_o(unused_output_data_w[1280 +: 256])
    );
    edrv32_ram_gpu_read_pool u_output_6 (
        .clk_i(clk_i),
        .wr_en_i(output_push_w),
        .wr_addr_i(output_write_r),
        .wr_data_i(output_input_w[1536 +: 256]),
        .rd_en_i(output_read_w),
        .rd_addr_i(output_addr_w),
        .rd_data_o(unused_output_data_w[1536 +: 256])
    );
    edrv32_ram_gpu_read_pool u_output_7 (
        .clk_i(clk_i),
        .wr_en_i(output_push_w),
        .wr_addr_i(output_write_r),
        .wr_data_i(output_input_w[1792 +: 256]),
        .rd_en_i(output_read_w),
        .rd_addr_i(output_addr_w),
        .rd_data_o(unused_output_data_w[1792 +: 256])
    );
    edrv32_ram_gpu_read_pool u_output_8 (
        .clk_i(clk_i),
        .wr_en_i(output_push_w),
        .wr_addr_i(output_write_r),
        .wr_data_i({51'b0, output_input_w[2048 +: 205]}),
        .rd_en_i(output_read_w),
        .rd_addr_i(output_addr_w),
        .rd_data_o(unused_output_data_w[2048 +: 256])
    );

    genvar coverage_lane;
    genvar coverage_edge;
    generate
        // Four coverage lanes: three x bounds, two y bounds and three edge tests each.
        for (coverage_lane = 0; coverage_lane < 4; coverage_lane = coverage_lane + 1) begin : g_mask
            localparam [1:0] LANE = coverage_lane;
            reg covered_r;
            assign mask_w[coverage_lane] = covered_r;
            assign clip_w[coverage_lane] =
                $signed({x_r[17:2], LANE}) >= clip_x0_r &&
                $signed({x_r[17:2], LANE}) < clip_x1_r &&
                $signed({x_r[17:2], LANE}) < x1_r && y_r >= clip_y0_r && y_r < clip_y1_r;
            always @(posedge clk_i) begin
                if (advance_w) covered_r <= pipe_clip_w[coverage_lane] &&
                    !edge_negative_w[coverage_lane*3] &&
                    (pipe_inclusive_w[0] || edge_nonzero_w[coverage_lane*3]) &&
                    !edge_negative_w[coverage_lane*3+1] &&
                    (pipe_inclusive_w[1] || edge_nonzero_w[coverage_lane*3+1]) &&
                    !edge_negative_w[coverage_lane*3+2] &&
                    (pipe_inclusive_w[2] || edge_nonzero_w[coverage_lane*3+2]);
            end
            for (coverage_edge = 0; coverage_edge < 3;
                coverage_edge = coverage_edge + 1) begin : g_edge
                reg nonzero_r;
                reg negative_r;
                assign edge_nonzero_w[coverage_lane*3+coverage_edge] = nonzero_r;
                assign edge_negative_w[coverage_lane*3+coverage_edge] = negative_r;
                always @(posedge clk_i) begin
                    if (advance_w) begin
                        nonzero_r <=
                            edge_w[coverage_lane*210+coverage_edge*70 +: 39] != 0;
                        negative_r <=
                            edge_w[coverage_lane*210+coverage_edge*70+69];
                    end
                end
            end
        end
    endgenerate
endmodule
