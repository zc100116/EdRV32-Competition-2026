// File: edrv32_gpu_quad.v
// Spec: gpu-spec 2.5, 2.8, 2.13; microarch 4.2, 4.4, 4.6.
// Description: Ordered quad/object scan with clipping and direct texture coordinates.
//              Prebuilt bounds and a three-stage coordinate/flip/UV pipeline.
// Clock domain: clk_gpu.
module edrv32_gpu_quad (
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

    // object_quad stream.,
    input wire object_quad_valid_i,
    output wire object_quad_ready_o,
    input wire [127:0] object_quad_data_i,
    input wire [16:0] object_quad_x_i,
    input wire [16:0] object_quad_y_i,
    input wire quad_record_valid_i,
    output wire quad_record_ready_o,
    input wire [127:0] quad_record_data_i,

    // Ordered fragment stream.,
    output wire fragment_valid_o,
    input wire fragment_ready_i,
    output wire [15:0] fragment_x_o,
    output wire [15:0] fragment_y_o,
    output wire [3:0] fragment_mask_o,
    output wire fragment_quad_o,
    output wire [1735:0] fragment_plane_o,
    output wire [69:0] fragment_h_o,
    output wire [3:0] fragment_palette_o,
    output wire [7:0] fragment_alpha_o,

    // Command lifecycle.,
    input wire finish_i,
    input wire stop_i,
    output reg unit_done_o,
    output reg perf_quad_o
);

    reg signed [17:0] clip_x0_r;
    reg signed [17:0] clip_y0_r;
    reg signed [17:0] clip_x1_r;
    reg signed [17:0] clip_y1_r;
    reg [3:0] unused_palette_r;
    reg [127:0] record_r;
    wire unused_state_w;
    assign unused_state_w = ^{render_state_pixel_i, render_state_tex_i, render_state_target_i,
        draw_command_i, draw_valid_i, record_r};
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
            unused_palette_r <= render_state_tex_i[78 +: 4];
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
    reg active_r;
    reg signed [17:0] x_r;
    reg signed [17:0] y_r;
    reg signed [17:0] x0_r;
    reg signed [17:0] x1_r;
    wire input_push_w;
    wire input_pop_w;
    wire output_push_w;
    wire output_pop_w;
    wire scan_w;
    wire last_w;
    reg [127:0] input_data_r [0:1];
    reg [16:0] input_x_r [0:1];
    reg [16:0] input_y_r [0:1];
    reg [15:0] output_x_r [0:1];
    assign fragment_x_o = output_x_r[output_read_r];
    reg [15:0] output_y_r [0:1];
    assign fragment_y_o = output_y_r[output_read_r];
    reg [3:0] output_mask_r [0:1];
    assign fragment_mask_o = output_mask_r[output_read_r];
    reg [0:0] output_quad_r [0:1];
    assign fragment_quad_o = output_quad_r[output_read_r];
    reg [69:0] output_h_r [0:1];
    assign fragment_h_o = output_h_r[output_read_r];
    reg [3:0] output_unused_palette_r [0:1];
    assign fragment_palette_o = output_unused_palette_r[output_read_r];
    reg [7:0] output_alpha_r [0:1];
    assign fragment_alpha_o = output_alpha_r[output_read_r];
    reg [2:0] valid_r;
    reg [1:0] prepared_r;
    reg [1:0] preparing_r;
    reg [1:0] prepare_index_r;
    reg [127:0] prepare_data_0_r;
    reg [127:0] prepare_data_1_r;
    reg [17:0] prepare_x_0_r;
    reg [17:0] unused_prepare_x_1_r;
    reg [17:0] prepare_y_0_r;
    reg [17:0] unused_prepare_y_1_r;
    reg signed [17:0] prepare_begin_x_0_r;
    reg signed [17:0] prepare_begin_x_1_r;
    reg signed [17:0] prepare_begin_y_0_r;
    reg signed [17:0] prepare_begin_y_1_r;
    reg signed [17:0] prepare_end_x_0_r;
    reg signed [17:0] prepare_end_x_1_r;
    reg signed [17:0] prepare_end_y_0_r;
    reg signed [17:0] prepare_end_y_1_r;
    reg [8:0] prepare_width_0_r;
    reg [8:0] prepare_width_1_r;
    reg [8:0] prepare_height_0_r;
    reg [8:0] prepare_height_1_r;
    reg signed [17:0] input_begin_x_r [0:1];
    reg signed [17:0] input_begin_y_r [0:1];
    reg signed [17:0] input_end_x_r [0:1];
    reg signed [17:0] input_end_y_r [0:1];
    reg [8:0] input_width_r [0:1];
    reg [8:0] input_height_r [0:1];
    wire [127:0] source_data_w;
    wire signed [17:0] source_x_w;
    wire signed [17:0] source_y_w;
    wire signed [17:0] begin_x_w;
    wire signed [17:0] begin_y_w;
    wire signed [17:0] end_x_w;
    wire signed [17:0] end_y_w;
    reg signed [17:0] position_x_r;
    reg signed [17:0] position_y_r;
    reg signed [17:0] unused_last_x_r;
    reg signed [17:0] last_y_r;
    reg [8:0] width_r;
    reg [8:0] height_r;
    reg [15:0] pipe_x_0_r;
    reg [15:0] pipe_x_1_r;
    reg [15:0] pipe_x_2_r;
    reg [15:0] pipe_y_0_r;
    reg [15:0] pipe_y_1_r;
    reg [15:0] pipe_y_2_r;
    reg [127:0] unused_pipe_record_0_r;
    reg [127:0] unused_pipe_record_1_r;
    reg [127:0] unused_pipe_record_2_r;
    wire [3:0] pipe_mask_w [0:2];
    wire advance_w;
    assign advance_w = output_count_r < 2;
    assign fragment_valid_o = (output_count_r != 0) && !stop_i;
    assign output_pop_w = fragment_valid_o && fragment_ready_i;
    assign scan_w = active_r && advance_w && !stop_i;
    assign last_w = x_r[17:2] == unused_last_x_r[17:2] && y_r == last_y_r;
    assign input_pop_w = prepared_r[input_read_r] &&
        (!active_r || (scan_w && last_w)) && !stop_i;
    assign output_push_w = valid_r[2] && pipe_mask_w[2] != 0 && advance_w && !stop_i;
    assign object_quad_ready_o = input_count_r < 2 && cfg_valid_r;
    assign quad_record_ready_o = input_count_r < 2 && cfg_valid_r;
    assign input_push_w = (object_quad_valid_i || quad_record_valid_i) &&
        input_count_r < 2 && cfg_valid_r && !stop_i;
    assign source_data_w = object_quad_valid_i ? object_quad_data_i : quad_record_data_i;
    assign source_x_w = object_quad_valid_i ? {object_quad_x_i[16], object_quad_x_i} :
        {{6{quad_record_data_i[11]}}, quad_record_data_i[0 +: 12]};
    assign source_y_w = object_quad_valid_i ? {object_quad_y_i[16], object_quad_y_i} :
        {{6{quad_record_data_i[23]}}, quad_record_data_i[12 +: 12]};
    assign begin_x_w = input_begin_x_r[input_read_r];
    assign begin_y_w = input_begin_y_r[input_read_r];
    assign end_x_w = input_end_x_r[input_read_r];
    assign end_y_w = input_end_y_r[input_read_r];
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            input_count_r <= 0;
            input_read_r <= 0;
            input_write_r <= 0;
            output_count_r <= 0;
            output_read_r <= 0;
            output_write_r <= 0;
            active_r <= 0;
            valid_r <= 0;
            preparing_r <= 0;
            prepared_r <= 0;
            unit_done_o <= 0;
            perf_quad_o <= 0;
        end else begin
            perf_quad_o <= input_pop_w && !stop_i;
            if (!finish_i) begin
                unit_done_o <= 0;
            end else if (input_count_r == 0 && !active_r && output_count_r == 0 &&
                valid_r == 0 && !cfg_pending_r) begin
                unit_done_o <= 1;
            end
            preparing_r <= {preparing_r[0], input_push_w};
            if (advance_w) begin
                valid_r <= {valid_r[1:0], scan_w};
            end
            if (input_pop_w) begin
                prepared_r[input_read_r] <= 0;
            end
            if (preparing_r[1]) begin
                prepared_r[prepare_index_r[1]] <= 1;
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
            if (scan_w && last_w) begin
                active_r <= 0;
            end
            if (input_pop_w) begin
                active_r <= begin_x_w < end_x_w && begin_y_w < end_y_w;
            end
            if (stop_i) begin
                input_count_r <= 0;
                output_count_r <= 0;
                input_read_r <= input_write_r;
                output_read_r <= output_write_r;
                active_r <= 0;
                valid_r <= 0;
                preparing_r <= 0;
                prepared_r <= 0;
            end
        end
    end

    always @(posedge clk_i) begin
        prepare_index_r <= {prepare_index_r[0], input_write_r};
        prepare_data_0_r <= source_data_w;
        prepare_data_1_r <= prepare_data_0_r;
        prepare_x_0_r <= source_x_w;
        prepare_y_0_r <= source_y_w;
        unused_prepare_x_1_r <= prepare_x_0_r;
        unused_prepare_y_1_r <= prepare_y_0_r;
        prepare_begin_x_0_r <= source_x_w > clip_x0_r ? source_x_w : clip_x0_r;
        prepare_begin_y_0_r <= source_y_w > clip_y0_r ? source_y_w : clip_y0_r;
        prepare_end_x_0_r <= source_x_w + $signed({9'b0, source_data_w[32 +: 9]});
        prepare_end_y_0_r <= source_y_w + $signed({9'b0, source_data_w[41 +: 9]});
        prepare_begin_x_1_r <= prepare_begin_x_0_r;
        prepare_begin_y_1_r <= prepare_begin_y_0_r;
        prepare_end_x_1_r <= prepare_end_x_0_r < clip_x1_r ?
            prepare_end_x_0_r : clip_x1_r;
        prepare_end_y_1_r <= prepare_end_y_0_r < clip_y1_r ?
            prepare_end_y_0_r : clip_y1_r;
        prepare_width_0_r <= source_data_w[32 +: 9] - 9'd1;
        prepare_height_0_r <= source_data_w[41 +: 9] - 9'd1;
        prepare_width_1_r <= prepare_width_0_r;
        prepare_height_1_r <= prepare_height_0_r;
        if (preparing_r[1]) begin
            input_data_r[prepare_index_r[1]] <= prepare_data_1_r;
            input_x_r[prepare_index_r[1]] <= unused_prepare_x_1_r[16:0];
            input_y_r[prepare_index_r[1]] <= unused_prepare_y_1_r[16:0];
            input_begin_x_r[prepare_index_r[1]] <= prepare_begin_x_1_r;
            input_begin_y_r[prepare_index_r[1]] <= prepare_begin_y_1_r;
            input_end_x_r[prepare_index_r[1]] <= prepare_end_x_1_r;
            input_end_y_r[prepare_index_r[1]] <= prepare_end_y_1_r;
            input_width_r[prepare_index_r[1]] <= prepare_width_1_r;
            input_height_r[prepare_index_r[1]] <= prepare_height_1_r;
        end
        if (advance_w) begin
            pipe_x_0_r <= x_r[15:0];
            pipe_y_0_r <= y_r[15:0];
            unused_pipe_record_0_r <= record_r;
            pipe_x_1_r <= pipe_x_0_r;
            pipe_y_1_r <= pipe_y_0_r;
            unused_pipe_record_1_r <= unused_pipe_record_0_r;
            pipe_x_2_r <= pipe_x_1_r;
            pipe_y_2_r <= pipe_y_1_r;
            unused_pipe_record_2_r <= unused_pipe_record_1_r;
        end
        if (scan_w) begin
            if (x_r[17:2] == unused_last_x_r[17:2]) begin
                x_r <= x0_r;
                y_r <= y_r + 1'b1;
            end else begin
                x_r <= x_r + 18'sd4;
            end
        end
        if (input_pop_w) begin
            x_r <= {begin_x_w[17:2], 2'b0};
            x0_r <= {begin_x_w[17:2], 2'b0};
            y_r <= begin_y_w;
            x1_r <= end_x_w;
            unused_last_x_r <= end_x_w - 18'sd1;
            last_y_r <= end_y_w - 18'sd1;
            width_r <= input_width_r[input_read_r];
            height_r <= input_height_r[input_read_r];
            position_x_r <= {input_x_r[input_read_r][16], input_x_r[input_read_r]};
            position_y_r <= {input_y_r[input_read_r][16], input_y_r[input_read_r]};
            record_r <= input_data_r[input_read_r];
        end
        if (output_push_w) begin
            output_x_r[output_write_r] <= pipe_x_2_r;
            output_y_r[output_write_r] <= pipe_y_2_r;
            output_mask_r[output_write_r] <= pipe_mask_w[2];
            output_quad_r[output_write_r] <= 1'b1;
            output_h_r[output_write_r] <= {-10'sd8, -10'sd8, -10'sd8,
                10'sd0, 10'sd0, 10'sd0, -10'sd16};
            output_unused_palette_r[output_write_r] <= unused_pipe_record_2_r[24 +: 4];
            output_alpha_r[output_write_r] <= unused_pipe_record_2_r[50 +: 8];
        end
    end
    // Four coordinate subtract/flip/add pipelines, preserving the three existing stages.
    genvar lane;
    generate
        for (lane = 0; lane < 4; lane = lane + 1) begin : g_lane
            reg signed [17:0] column_r;
            reg signed [17:0] row_r;
            reg [8:0] width_minus_one_r;
            reg [8:0] height_minus_one_r;
            reg signed [17:0] flipped_column_r;
            reg signed [17:0] flipped_row_r;
            reg signed [18:0] u_r;
            reg signed [18:0] v_r;
            wire signed [17:0] pixel_x_w;
            reg [2:0] mask_r;
            // Four lane-local 3-bit mask pipelines, advancing with the UV pipeline.
            assign pipe_mask_w[0][lane] = mask_r[0];
            assign pipe_mask_w[1][lane] = mask_r[1];
            assign pipe_mask_w[2][lane] = mask_r[2];
            assign pixel_x_w = {x_r[17:2], lane[1:0]};
            // Output stage: seven independent two-slot 70-bit field queues per lane.
            reg [61:0] plane_0_r [0:1];
            assign fragment_plane_o[lane*434+0 +: 62] = plane_0_r[output_read_r];
            always @(posedge clk_i) begin
                if (output_push_w)
                    plane_0_r[output_write_r] <= {38'b0, unused_pipe_record_2_r[80 +: 16], 8'b0};
            end
            reg [65:0] plane_1_r [0:1];
            assign fragment_plane_o[lane*434+62 +: 66] = plane_1_r[output_read_r];
            always @(posedge clk_i) begin
                if (output_push_w) plane_1_r[output_write_r] <= 66'd67108864;
            end
            reg [65:0] plane_2_r [0:1];
            assign fragment_plane_o[lane*434+128 +: 66] = plane_2_r[output_read_r];
            always @(posedge clk_i) begin
                if (output_push_w) plane_2_r[output_write_r] <= {{13{u_r[18]}}, u_r, 34'b0};
            end
            reg [65:0] plane_3_r [0:1];
            assign fragment_plane_o[lane*434+194 +: 66] = plane_3_r[output_read_r];
            always @(posedge clk_i) begin
                if (output_push_w) plane_3_r[output_write_r] <= {{13{v_r[18]}}, v_r, 34'b0};
            end
            reg [57:0] plane_4_r [0:1];
            assign fragment_plane_o[lane*434+260 +: 58] = plane_4_r[output_read_r];
            always @(posedge clk_i) begin
                if (output_push_w) plane_4_r[output_write_r] <= 58'd1044480;
            end
            reg [57:0] plane_5_r [0:1];
            assign fragment_plane_o[lane*434+318 +: 58] = plane_5_r[output_read_r];
            always @(posedge clk_i) begin
                if (output_push_w) plane_5_r[output_write_r] <= 58'd1044480;
            end
            reg [57:0] plane_6_r [0:1];
            assign fragment_plane_o[lane*434+376 +: 58] = plane_6_r[output_read_r];
            always @(posedge clk_i) begin
                if (output_push_w) plane_6_r[output_write_r] <= 58'd1044480;
            end
            always @(posedge clk_i) begin
                if (advance_w) begin
                    column_r <= pixel_x_w - position_x_r;
                    row_r <= y_r - position_y_r;
                    width_minus_one_r <= width_r;
                    height_minus_one_r <= height_r;
                    mask_r <= {mask_r[1:0], pixel_x_w >= clip_x0_r && pixel_x_w < x1_r &&
                        pixel_x_w >= position_x_r};
                    flipped_column_r <= unused_pipe_record_0_r[28] ?
                        $signed({9'b0, width_minus_one_r}) - column_r : column_r;
                    flipped_row_r <= unused_pipe_record_0_r[29] ?
                        $signed({9'b0, height_minus_one_r}) - row_r : row_r;
                    u_r <= $signed({flipped_column_r[17], flipped_column_r}) +
                        $signed({11'b0, unused_pipe_record_1_r[64 +: 8]});
                    v_r <= $signed({flipped_row_r[17], flipped_row_r}) +
                        $signed({11'b0, unused_pipe_record_1_r[72 +: 8]});
                end
            end
        end
    endgenerate
endmodule
