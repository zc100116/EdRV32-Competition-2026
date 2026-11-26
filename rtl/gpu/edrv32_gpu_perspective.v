// File: edrv32_gpu_perspective.v
// Spec: gpu-spec 2.5, 2.8, 2.13; microarch 4.2, 4.4, 4.6.
// Description: Two-lane ordered streaming pixel arithmetic.
//              P18 coordinates, paired 2x2 differences for the triangle sample stream.
// Clock domain: clk_gpu.
module edrv32_gpu_perspective (
    // Clock and reset.,
    input wire clk_i,
    input wire rst_n_i,

    // Input fragment stream.,
    input wire fragment_valid_i,
    output wire fragment_ready_o,
    input wire [15:0] fragment_x_i,
    input wire [15:0] fragment_y_i,
    input wire [1:0] fragment_mask_i,
    input wire [867:0] fragment_plane_i,
    input wire [69:0] fragment_h_i,
    input wire [3:0] fragment_palette_i,
    input wire [7:0] fragment_alpha_i,

    // Output sample stream.,
    output wire sample_valid_o,
    input wire sample_ready_i,
    output wire [15:0] sample_x_o,
    output wire [15:0] sample_y_o,
    output wire [3:0] sample_mask_o,
    output wire sample_quad_o,
    output wire [127:0] sample_u_o,
    output wire [127:0] sample_v_o,
    output wire [383:0] sample_span_o,
    output wire [63:0] sample_depth_o,
    output wire [95:0] sample_color_o,
    output wire [3:0] sample_palette_o,
    output wire [7:0] sample_alpha_o,

    // Command lifecycle.,
    input wire finish_i,
    input wire stop_i,
    output reg unit_done_o
);

    reg [1:0] result_phase_r;
    reg second_row_r;
    wire block_complete_w;
    reg [1:0] input_count_r;
    reg input_read_r;
    reg input_write_r;
    reg [5:0] output_count_r;
    reg [6:0] outstanding_r;
    reg output_valid_r;
    wire output_read_w;
    wire [8:0] output_addr_w;
    reg [4:0] output_read_r;
    reg [4:0] output_write_r;
    reg [42:0] valid_r;
    wire advance_w;
    wire input_push_w;
    wire input_pop_w;
    wire output_push_w;
    wire output_pop_w;
    reg [15:0] input_x_r [0:1];
    reg [15:0] input_y_r [0:1];
    reg [3:0] input_mask_r [0:1];
    reg [69:0] input_h_r [0:1];
    reg [3:0] input_palette_r [0:1];
    reg [7:0] input_alpha_r [0:1];
    wire [15:0] pipe_x_w;
    wire [15:0] pipe_y_w;
    wire [1:0] pipe_mask_w;
    wire [3:0] pipe_palette_w;
    wire [7:0] pipe_alpha_w;
    wire [656:0] output_input_w;
    wire [719:0] unused_output_data_w;
    wire [63:0] raw_u_w;
    wire [63:0] raw_v_w;
    wire [191:0] unused_raw_span_w;
    wire [31:0] raw_depth_w;
    wire [47:0] raw_color_w;
    reg [8:0] delay_write_r;
    wire [3:0] delay_sign_input_w;
    wire [71:0] unused_delay_sign_data_w;
    wire [8:0] delay_sign_read_w;
    wire [23:0] delay_q_input_w;
    wire [71:0] unused_delay_q_data_w;
    wire [8:0] delay_q_read_w;
    wire [115:0] delay_uvq_input_w;
    wire [143:0] unused_delay_uvq_data_w;
    wire [8:0] delay_uvq_read_w;
    wire [127:0] delay_coordinate_input_w;
    wire [143:0] unused_delay_coordinate_data_w;
    wire [8:0] delay_coordinate_read_w;
    wire [79:0] delay_shade_input_w;
    wire [143:0] unused_delay_shade_data_w;
    wire [8:0] delay_shade_read_w;
    wire [48:0] delay_metadata_input_w;
    wire [71:0] unused_delay_metadata_data_w;
    wire [8:0] delay_metadata_read_w;
    wire [59:0] delay_scale_input_w;
    wire [71:0] unused_delay_scale_data_w;
    wire [8:0] delay_scale_read_w;
    wire [231:0] delay_bypass_input_w;
    wire [287:0] unused_delay_bypass_data_w;
    wire [8:0] delay_bypass_read_w;
    reg pair_second_r;
    wire [57:0] u_normal_w;
    wire [57:0] v_normal_w;
    reg [57:0] previous_u_r;
    reg [57:0] previous_v_r;
    wire [95:0] quad_span_w;
    reg [95:0] previous_span_r;
    // Two input slots decouple acceptance; 128 result credits cover the 43-stage arithmetic pipeline.

    assign advance_w = 1'b1;
    assign fragment_ready_o = input_count_r < 2 && outstanding_r < 64;
    assign sample_valid_o = output_valid_r && !stop_i;
    assign input_push_w = fragment_valid_i && fragment_ready_o && !stop_i;
    assign input_pop_w = input_count_r != 0 && !stop_i &&
        (pair_second_r || input_count_r == 2 || input_push_w);
    assign output_push_w = (block_complete_w || second_row_r) && !stop_i;
    assign output_pop_w = sample_valid_o && sample_ready_i;
    // The RAM output holds the prefetched head during downstream backpressure.
    assign output_read_w = !stop_i && ((output_count_r != 0 && !output_valid_r) ||
        (output_pop_w && output_count_r > 1));
    assign output_addr_w = {4'b0, output_read_r + {4'b0, output_pop_w}};

    assign pipe_x_w = unused_delay_metadata_data_w[0 +: 16];
    assign pipe_y_w = unused_delay_metadata_data_w[16 +: 16];
    assign pipe_mask_w = unused_delay_metadata_data_w[32 +: 2];
    assign pipe_palette_w = unused_delay_metadata_data_w[37 +: 4];
    assign pipe_alpha_w = unused_delay_metadata_data_w[41 +: 8];

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            input_count_r <= 0;
            input_read_r <= 0;
            input_write_r <= 0;
            output_count_r <= 0;
            outstanding_r <= 0;
            output_valid_r <= 0;
            output_read_r <= 0;
            output_write_r <= 0;
            valid_r <= 0;
            unit_done_o <= 0;
        end else begin
            if (!finish_i) begin
                unit_done_o <= 0;
            end else if (input_count_r == 0 && valid_r == 0 &&
                output_count_r == 0 && !second_row_r) begin
                unit_done_o <= 1;
            end
            if (stop_i) begin
                input_count_r <= 0;
                output_count_r <= 0;
                outstanding_r <= 0;
                output_valid_r <= 0;
                input_read_r <= input_write_r;
                output_read_r <= output_write_r;
                valid_r <= 0;
            end else begin
                if (input_push_w || output_pop_w) begin
                    outstanding_r <= outstanding_r + {6'b0, input_push_w}
                        - (output_pop_w ? 7'd2 : 7'd0);
                end
                if (output_read_w) output_valid_r <= 1;
                else if (output_pop_w) output_valid_r <= 0;
                if (input_push_w != input_pop_w) begin
                    input_count_r <= input_push_w ?
                        input_count_r + 1'b1 : input_count_r - 1'b1;
                end
                if (output_push_w != output_pop_w) begin
                    output_count_r <= output_push_w ?
                        output_count_r + 1'b1 : output_count_r - 1'b1;
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
                    valid_r <= {valid_r[41:0], input_pop_w};
                end
            end
        end
    end

    always @(posedge clk_i) begin
        if (input_push_w) begin
            input_x_r[input_write_r] <= fragment_x_i;
            input_y_r[input_write_r] <= fragment_y_i;
            input_mask_r[input_write_r] <= {2'b0, fragment_mask_i};
            input_h_r[input_write_r] <= fragment_h_i;
            input_palette_r[input_write_r] <= fragment_palette_i;
            input_alpha_r[input_write_r] <= fragment_alpha_i;
        end
    end

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) pair_second_r <= 0;
        else if (stop_i) pair_second_r <= 0;
        else if (input_pop_w) pair_second_r <= !pair_second_r;
    end
    always @(posedge clk_i) begin
        previous_u_r <= u_normal_w;
        previous_v_r <= v_normal_w;
        previous_span_r <= quad_span_w;
    end
    assign block_complete_w = valid_r[42] && result_phase_r == 3;
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            result_phase_r <= 0;
            second_row_r <= 0;
        end else if (stop_i) begin
            result_phase_r <= 0;
            second_row_r <= 0;
        end else begin
            if (valid_r[42]) result_phase_r <= result_phase_r + 1'b1;
            second_row_r <= block_complete_w;
        end
    end
    reg [63:0] row_u_0_r;
    reg [63:0] row_u_1_r;
    reg [63:0] row_u_2_r;
    reg [63:0] row_u_3_r;
    wire [127:0] output_u_w;
    assign output_u_w = second_row_r ?
        {row_u_3_r, row_u_1_r} : {row_u_2_r, row_u_0_r};
    always @(posedge clk_i) begin
        if (valid_r[42] && result_phase_r == 0) row_u_0_r <= raw_u_w;
    end
    always @(posedge clk_i) begin
        if (valid_r[42] && result_phase_r == 1) row_u_1_r <= raw_u_w;
    end
    always @(posedge clk_i) begin
        if (valid_r[42] && result_phase_r == 2) row_u_2_r <= raw_u_w;
    end
    always @(posedge clk_i) begin
        if (valid_r[42] && result_phase_r == 3) row_u_3_r <= raw_u_w;
    end
    reg [63:0] row_v_0_r;
    reg [63:0] row_v_1_r;
    reg [63:0] row_v_2_r;
    reg [63:0] row_v_3_r;
    wire [127:0] output_v_w;
    assign output_v_w = second_row_r ?
        {row_v_3_r, row_v_1_r} : {row_v_2_r, row_v_0_r};
    always @(posedge clk_i) begin
        if (valid_r[42] && result_phase_r == 0) row_v_0_r <= raw_v_w;
    end
    always @(posedge clk_i) begin
        if (valid_r[42] && result_phase_r == 1) row_v_1_r <= raw_v_w;
    end
    always @(posedge clk_i) begin
        if (valid_r[42] && result_phase_r == 2) row_v_2_r <= raw_v_w;
    end
    always @(posedge clk_i) begin
        if (valid_r[42] && result_phase_r == 3) row_v_3_r <= raw_v_w;
    end
    reg [31:0] row_depth_0_r;
    reg [31:0] row_depth_1_r;
    reg [31:0] row_depth_2_r;
    reg [31:0] row_depth_3_r;
    wire [63:0] output_depth_w;
    assign output_depth_w = second_row_r ?
        {row_depth_3_r, row_depth_1_r} : {row_depth_2_r, row_depth_0_r};
    always @(posedge clk_i) begin
        if (valid_r[42] && result_phase_r == 0) row_depth_0_r <= raw_depth_w;
    end
    always @(posedge clk_i) begin
        if (valid_r[42] && result_phase_r == 1) row_depth_1_r <= raw_depth_w;
    end
    always @(posedge clk_i) begin
        if (valid_r[42] && result_phase_r == 2) row_depth_2_r <= raw_depth_w;
    end
    always @(posedge clk_i) begin
        if (valid_r[42] && result_phase_r == 3) row_depth_3_r <= raw_depth_w;
    end
    reg [47:0] row_color_0_r;
    reg [47:0] row_color_1_r;
    reg [47:0] row_color_2_r;
    reg [47:0] row_color_3_r;
    wire [95:0] output_color_w;
    assign output_color_w = second_row_r ?
        {row_color_3_r, row_color_1_r} : {row_color_2_r, row_color_0_r};
    always @(posedge clk_i) begin
        if (valid_r[42] && result_phase_r == 0) row_color_0_r <= raw_color_w;
    end
    always @(posedge clk_i) begin
        if (valid_r[42] && result_phase_r == 1) row_color_1_r <= raw_color_w;
    end
    always @(posedge clk_i) begin
        if (valid_r[42] && result_phase_r == 2) row_color_2_r <= raw_color_w;
    end
    always @(posedge clk_i) begin
        if (valid_r[42] && result_phase_r == 3) row_color_3_r <= raw_color_w;
    end
    reg [1:0] row_mask_0_r;
    reg [1:0] row_mask_1_r;
    reg [1:0] row_mask_2_r;
    reg [1:0] row_mask_3_r;
    wire [3:0] output_mask_w;
    assign output_mask_w = second_row_r ?
        {row_mask_3_r, row_mask_1_r} : {row_mask_2_r, row_mask_0_r};
    always @(posedge clk_i) begin
        if (valid_r[42] && result_phase_r == 0) row_mask_0_r <= pipe_mask_w[1:0];
    end
    always @(posedge clk_i) begin
        if (valid_r[42] && result_phase_r == 1) row_mask_1_r <= pipe_mask_w[1:0];
    end
    always @(posedge clk_i) begin
        if (valid_r[42] && result_phase_r == 2) row_mask_2_r <= pipe_mask_w[1:0];
    end
    always @(posedge clk_i) begin
        if (valid_r[42] && result_phase_r == 3) row_mask_3_r <= pipe_mask_w[1:0];
    end
    reg [95:0] left_span_r;
    reg [95:0] right_span_r;
    reg [15:0] block_x_r;
    reg [15:0] block_y_r;
    reg [3:0] block_palette_r;
    reg [7:0] block_alpha_r;
    reg [3:0] second_palette_r;
    reg [7:0] second_alpha_r;
    always @(posedge clk_i) begin
        if (valid_r[42] && result_phase_r == 0) begin
            left_span_r <= unused_raw_span_w[0 +: 96];
            block_x_r <= pipe_x_w;
            block_y_r <= pipe_y_w;
            block_palette_r <= pipe_palette_w;
            block_alpha_r <= pipe_alpha_w;
        end
        if (valid_r[42] && result_phase_r == 1) begin
            second_palette_r <= pipe_palette_w;
            second_alpha_r <= pipe_alpha_w;
        end
        if (valid_r[42] && result_phase_r == 2)
            right_span_r <= unused_raw_span_w[0 +: 96];
    end
    assign output_input_w[0 +: 16] = block_x_r;
    assign sample_x_o = unused_output_data_w[0 +: 16];
    assign output_input_w[16 +: 16] = block_y_r + {15'b0, second_row_r};
    assign sample_y_o = unused_output_data_w[16 +: 16];
    assign output_input_w[32 +: 4] = output_mask_w;
    assign sample_mask_o = unused_output_data_w[32 +: 4];
    assign output_input_w[36 +: 1] = 1'b0;
    assign sample_quad_o = unused_output_data_w[36 +: 1];
    assign output_input_w[37 +: 4] = second_row_r ? second_palette_r : block_palette_r;
    assign sample_palette_o = unused_output_data_w[37 +: 4];
    assign output_input_w[41 +: 8] = second_row_r ? second_alpha_r : block_alpha_r;
    assign sample_alpha_o = unused_output_data_w[41 +: 8];
    assign output_input_w[49 +: 128] = output_u_w;
    assign sample_u_o = unused_output_data_w[49 +: 128];
    assign output_input_w[177 +: 128] = output_v_w;
    assign sample_v_o = unused_output_data_w[177 +: 128];
    assign output_input_w[305 +: 96] = left_span_r;
    assign sample_span_o[0 +: 96] = unused_output_data_w[305 +: 96];
    assign sample_span_o[96 +: 96] = unused_output_data_w[305 +: 96];
    assign output_input_w[401 +: 96] = right_span_r;
    assign sample_span_o[192 +: 96] = unused_output_data_w[401 +: 96];
    assign sample_span_o[288 +: 96] = unused_output_data_w[401 +: 96];
    assign output_input_w[497 +: 64] = output_depth_w;
    assign sample_depth_o = unused_output_data_w[497 +: 64];
    assign output_input_w[561 +: 96] = output_color_w;
    assign sample_color_o = unused_output_data_w[561 +: 96];
    edrv32_ram_gpu_delay u_output_0 (
        .clk_i(clk_i),
        .wr_en_i(output_push_w),
        .wr_addr_i({4'b0, output_write_r}),
        .wr_data_i(output_input_w[0 +: 72]),
        .rd_en_i(output_read_w),
        .rd_addr_i(output_addr_w),
        .rd_data_o(unused_output_data_w[0 +: 72])
    );
    edrv32_ram_gpu_delay u_output_1 (
        .clk_i(clk_i),
        .wr_en_i(output_push_w),
        .wr_addr_i({4'b0, output_write_r}),
        .wr_data_i(output_input_w[72 +: 72]),
        .rd_en_i(output_read_w),
        .rd_addr_i(output_addr_w),
        .rd_data_o(unused_output_data_w[72 +: 72])
    );
    edrv32_ram_gpu_delay u_output_2 (
        .clk_i(clk_i),
        .wr_en_i(output_push_w),
        .wr_addr_i({4'b0, output_write_r}),
        .wr_data_i(output_input_w[144 +: 72]),
        .rd_en_i(output_read_w),
        .rd_addr_i(output_addr_w),
        .rd_data_o(unused_output_data_w[144 +: 72])
    );
    edrv32_ram_gpu_delay u_output_3 (
        .clk_i(clk_i),
        .wr_en_i(output_push_w),
        .wr_addr_i({4'b0, output_write_r}),
        .wr_data_i(output_input_w[216 +: 72]),
        .rd_en_i(output_read_w),
        .rd_addr_i(output_addr_w),
        .rd_data_o(unused_output_data_w[216 +: 72])
    );
    edrv32_ram_gpu_delay u_output_4 (
        .clk_i(clk_i),
        .wr_en_i(output_push_w),
        .wr_addr_i({4'b0, output_write_r}),
        .wr_data_i(output_input_w[288 +: 72]),
        .rd_en_i(output_read_w),
        .rd_addr_i(output_addr_w),
        .rd_data_o(unused_output_data_w[288 +: 72])
    );
    edrv32_ram_gpu_delay u_output_5 (
        .clk_i(clk_i),
        .wr_en_i(output_push_w),
        .wr_addr_i({4'b0, output_write_r}),
        .wr_data_i(output_input_w[360 +: 72]),
        .rd_en_i(output_read_w),
        .rd_addr_i(output_addr_w),
        .rd_data_o(unused_output_data_w[360 +: 72])
    );
    edrv32_ram_gpu_delay u_output_6 (
        .clk_i(clk_i),
        .wr_en_i(output_push_w),
        .wr_addr_i({4'b0, output_write_r}),
        .wr_data_i(output_input_w[432 +: 72]),
        .rd_en_i(output_read_w),
        .rd_addr_i(output_addr_w),
        .rd_data_o(unused_output_data_w[432 +: 72])
    );
    edrv32_ram_gpu_delay u_output_7 (
        .clk_i(clk_i),
        .wr_en_i(output_push_w),
        .wr_addr_i({4'b0, output_write_r}),
        .wr_data_i(output_input_w[504 +: 72]),
        .rd_en_i(output_read_w),
        .rd_addr_i(output_addr_w),
        .rd_data_o(unused_output_data_w[504 +: 72])
    );
    edrv32_ram_gpu_delay u_output_8 (
        .clk_i(clk_i),
        .wr_en_i(output_push_w),
        .wr_addr_i({4'b0, output_write_r}),
        .wr_data_i(output_input_w[576 +: 72]),
        .rd_en_i(output_read_w),
        .rd_addr_i(output_addr_w),
        .rd_data_o(unused_output_data_w[576 +: 72])
    );
    edrv32_ram_gpu_delay u_output_9 (
        .clk_i(clk_i),
        .wr_en_i(output_push_w),
        .wr_addr_i({4'b0, output_write_r}),
        .wr_data_i({63'b0, output_input_w[648 +: 9]}),
        .rd_en_i(output_read_w),
        .rd_addr_i(output_addr_w),
        .rd_data_o(unused_output_data_w[648 +: 72])
    );

    // Fixed-distance circular RAM delays. The synchronous read is the last stage.
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) delay_write_r <= 0;
        else if (advance_w) delay_write_r <= delay_write_r + 1'b1;
    end
    assign delay_sign_read_w = delay_write_r - 9'd3;
    edrv32_ram_gpu_delay u_delay_sign_0 (
        .clk_i(clk_i),
        .wr_en_i(advance_w),
        .wr_addr_i(delay_write_r),
        .wr_data_i({68'b0, delay_sign_input_w[0 +: 4]}),
        .rd_en_i(advance_w),
        .rd_addr_i(delay_sign_read_w),
        .rd_data_o(unused_delay_sign_data_w[0 +: 72])
    );
    assign delay_q_read_w = delay_write_r - 9'd11;
    edrv32_ram_gpu_delay u_delay_q_0 (
        .clk_i(clk_i),
        .wr_en_i(advance_w),
        .wr_addr_i(delay_write_r),
        .wr_data_i({48'b0, delay_q_input_w[0 +: 24]}),
        .rd_en_i(advance_w),
        .rd_addr_i(delay_q_read_w),
        .rd_data_o(unused_delay_q_data_w[0 +: 72])
    );
    assign delay_uvq_read_w = delay_write_r - 9'd13;
    edrv32_ram_gpu_delay u_delay_uvq_0 (
        .clk_i(clk_i),
        .wr_en_i(advance_w),
        .wr_addr_i(delay_write_r),
        .wr_data_i(delay_uvq_input_w[0 +: 72]),
        .rd_en_i(advance_w),
        .rd_addr_i(delay_uvq_read_w),
        .rd_data_o(unused_delay_uvq_data_w[0 +: 72])
    );
    edrv32_ram_gpu_delay u_delay_uvq_1 (
        .clk_i(clk_i),
        .wr_en_i(advance_w),
        .wr_addr_i(delay_write_r),
        .wr_data_i({28'b0, delay_uvq_input_w[72 +: 44]}),
        .rd_en_i(advance_w),
        .rd_addr_i(delay_uvq_read_w),
        .rd_data_o(unused_delay_uvq_data_w[72 +: 72])
    );
    assign delay_coordinate_read_w = delay_write_r - 9'd12;
    edrv32_ram_gpu_delay u_delay_coordinate_0 (
        .clk_i(clk_i),
        .wr_en_i(advance_w),
        .wr_addr_i(delay_write_r),
        .wr_data_i(delay_coordinate_input_w[0 +: 72]),
        .rd_en_i(advance_w),
        .rd_addr_i(delay_coordinate_read_w),
        .rd_data_o(unused_delay_coordinate_data_w[0 +: 72])
    );
    edrv32_ram_gpu_delay u_delay_coordinate_1 (
        .clk_i(clk_i),
        .wr_en_i(advance_w),
        .wr_addr_i(delay_write_r),
        .wr_data_i({16'b0, delay_coordinate_input_w[72 +: 56]}),
        .rd_en_i(advance_w),
        .rd_addr_i(delay_coordinate_read_w),
        .rd_data_o(unused_delay_coordinate_data_w[72 +: 72])
    );
    assign delay_shade_read_w = delay_write_r - 9'd40;
    edrv32_ram_gpu_delay u_delay_shade_0 (
        .clk_i(clk_i),
        .wr_en_i(advance_w),
        .wr_addr_i(delay_write_r),
        .wr_data_i(delay_shade_input_w[0 +: 72]),
        .rd_en_i(advance_w),
        .rd_addr_i(delay_shade_read_w),
        .rd_data_o(unused_delay_shade_data_w[0 +: 72])
    );
    edrv32_ram_gpu_delay u_delay_shade_1 (
        .clk_i(clk_i),
        .wr_en_i(advance_w),
        .wr_addr_i(delay_write_r),
        .wr_data_i({64'b0, delay_shade_input_w[72 +: 8]}),
        .rd_en_i(advance_w),
        .rd_addr_i(delay_shade_read_w),
        .rd_data_o(unused_delay_shade_data_w[72 +: 72])
    );
    assign delay_metadata_read_w = delay_write_r - 9'd42;
    edrv32_ram_gpu_delay u_delay_metadata_0 (
        .clk_i(clk_i),
        .wr_en_i(advance_w),
        .wr_addr_i(delay_write_r),
        .wr_data_i({23'b0, delay_metadata_input_w[0 +: 49]}),
        .rd_en_i(advance_w),
        .rd_addr_i(delay_metadata_read_w),
        .rd_data_o(unused_delay_metadata_data_w[0 +: 72])
    );
    assign delay_scale_read_w = delay_write_r - 9'd2;
    edrv32_ram_gpu_delay u_delay_scale_0 (
        .clk_i(clk_i),
        .wr_en_i(advance_w),
        .wr_addr_i(delay_write_r),
        .wr_data_i({12'b0, delay_scale_input_w[0 +: 60]}),
        .rd_en_i(advance_w),
        .rd_addr_i(delay_scale_read_w),
        .rd_data_o(unused_delay_scale_data_w[0 +: 72])
    );
    assign delay_bypass_read_w = delay_write_r - 9'd9;
    edrv32_ram_gpu_delay u_delay_bypass_0 (
        .clk_i(clk_i),
        .wr_en_i(advance_w),
        .wr_addr_i(delay_write_r),
        .wr_data_i(delay_bypass_input_w[0 +: 72]),
        .rd_en_i(advance_w),
        .rd_addr_i(delay_bypass_read_w),
        .rd_data_o(unused_delay_bypass_data_w[0 +: 72])
    );
    edrv32_ram_gpu_delay u_delay_bypass_1 (
        .clk_i(clk_i),
        .wr_en_i(advance_w),
        .wr_addr_i(delay_write_r),
        .wr_data_i(delay_bypass_input_w[72 +: 72]),
        .rd_en_i(advance_w),
        .rd_addr_i(delay_bypass_read_w),
        .rd_data_o(unused_delay_bypass_data_w[72 +: 72])
    );
    edrv32_ram_gpu_delay u_delay_bypass_2 (
        .clk_i(clk_i),
        .wr_en_i(advance_w),
        .wr_addr_i(delay_write_r),
        .wr_data_i(delay_bypass_input_w[144 +: 72]),
        .rd_en_i(advance_w),
        .rd_addr_i(delay_bypass_read_w),
        .rd_data_o(unused_delay_bypass_data_w[144 +: 72])
    );
    edrv32_ram_gpu_delay u_delay_bypass_3 (
        .clk_i(clk_i),
        .wr_en_i(advance_w),
        .wr_addr_i(delay_write_r),
        .wr_data_i({56'b0, delay_bypass_input_w[216 +: 16]}),
        .rd_en_i(advance_w),
        .rd_addr_i(delay_bypass_read_w),
        .rd_data_o(unused_delay_bypass_data_w[216 +: 72])
    );
    assign delay_metadata_input_w[0 +: 49] =
        {input_alpha_r[input_read_r], input_palette_r[input_read_r],
        1'b0, input_mask_r[input_read_r],
        input_y_r[input_read_r], input_x_r[input_read_r]};

    genvar lane;
    generate
        for (lane = 0; lane < 2; lane = lane + 1) begin : g_lane
            // Four lanes, each owning seven 70-bit two-slot input field queues.
            // No queue array is shared between generated lanes or fields.
            wire [70*7-1:0] unused_plane_w;
            genvar attribute;
            for (attribute = 0; attribute < 7; attribute = attribute + 1) begin : g_plane
                localparam WIDTH = attribute == 0 ? 62 : attribute < 4 ? 66 : 58;
                localparam OFFSET = attribute == 0 ? 0 : attribute < 4 ?
                    62 + (attribute-1)*66 : 260 + (attribute-4)*58;
                reg [69:0] input_plane_r [0:1];
                always @(posedge clk_i) begin
                    if (input_push_w) begin
                        input_plane_r[input_write_r] <=
                            {{(70-WIDTH){fragment_plane_i[lane*434+OFFSET+WIDTH-1]}},
                            fragment_plane_i[lane*434+OFFSET +: WIDTH]};
                    end
                end
                assign unused_plane_w[70*attribute +: 70] = input_plane_r[input_read_r];
            end

            // Two short register delays stay local; deep delays share RAM across lanes.
            wire [65:0] q_absolute_w;
            wire [0:0] q_sign_w;
            wire [9:0] q_exponent_w;
            wire [28:0] unused_q_w;
            wire [65:0] uq_absolute_w;
            wire [0:0] uq_sign_w;
            wire [9:0] uq_exponent_w;
            wire [28:0] uq_w;
            wire [65:0] vq_absolute_w;
            wire [0:0] vq_sign_w;
            wire [9:0] vq_exponent_w;
            wire [28:0] vq_w;
            reg [9:0] seed_address_r;
            wire [17:0] seed_rom_w;
            reg [17:0] seed_r;
            wire [17:0] q_mantissa_w;
            assign q_mantissa_w = unused_q_w[17:0];
            reg [53:0] delay_1_r;
            wire [35:0] unused_newton_first_w;
            wire [0:0] unused_newton_first_sign_w;
            wire [9:0] unused_newton_first_exponent_w;
            wire [19:0] unused_newton_t_sum_w;
            assign unused_newton_t_sum_w = {1'b0, unused_newton_first_w[35:17]}
                + {19'b0, unused_newton_first_w[16]};
            reg [17:0] newton_t_r;
            reg [17:0] newton_term_r;
            reg [89:0] delay_2_r;
            wire [35:0] unused_newton_second_w;
            wire [0:0] unused_newton_second_sign_w;
            wire [9:0] unused_newton_second_exponent_w;
            wire [19:0] unused_newton_r1_sum_w;
            assign unused_newton_r1_sum_w = {1'b0, unused_newton_second_w[35:17]}
                + {19'b0, unused_newton_second_w[16]};
            reg [17:0] newton_r1_r;
            wire [9:0] q_normal_exponent_w;
            assign q_normal_exponent_w = unused_q_w[28:19];
            wire [11:0] delay_3_w;
            assign delay_3_w = unused_delay_q_data_w[lane*12 +: 12];
            assign delay_q_input_w[lane*12 +: 12] =
                {unused_q_w[18], unused_q_w[17:0] == 0, q_normal_exponent_w};
            reg [17:0] inverse_mantissa_r;
            reg [9:0] inverse_exponent_r;
            reg [28:0] inverse_r;
            reg inverse_sign_r;
            wire [28:0] delay_4_w;
            assign delay_4_w = unused_delay_uvq_data_w[0+lane*29 +: 29];
            assign delay_uvq_input_w[0+lane*29 +: 29] = uq_w;
            wire [35:0] u_multiply_magnitude_w;
            wire [0:0] u_multiply_sign_w;
            wire [9:0] u_multiply_exponent_w;
            wire [28:0] u_w;
            wire [28:0] delay_5_w;
            assign delay_5_w = unused_delay_uvq_data_w[58+lane*29 +: 29];
            assign delay_uvq_input_w[58+lane*29 +: 29] = vq_w;
            wire [35:0] v_multiply_magnitude_w;
            wire [0:0] v_multiply_sign_w;
            wire [9:0] v_multiply_exponent_w;
            wire [28:0] v_w;
            wire [31:0] unused_u_coordinate_magnitude_w;
            wire [0:0] u_coordinate_sign_w;
            assign u_coordinate_sign_w = u_w[18];
            wire [0:0] delay_6_w;
            assign delay_6_w = unused_delay_sign_data_w[0+lane*1 +: 1];
            assign delay_sign_input_w[0+lane*1 +: 1] = u_coordinate_sign_w;
            wire [31:0] u_coordinate_w;
            wire [31:0] delay_7_w;
            assign delay_7_w = unused_delay_coordinate_data_w[0+lane*32 +: 32];
            assign delay_coordinate_input_w[0+lane*32 +: 32] = u_coordinate_w;
            wire [31:0] unused_v_coordinate_magnitude_w;
            wire [0:0] v_coordinate_sign_w;
            assign v_coordinate_sign_w = v_w[18];
            wire [0:0] delay_scale_w;
            assign delay_scale_w = unused_delay_sign_data_w[2+lane*1 +: 1];
            assign delay_sign_input_w[2+lane*1 +: 1] = v_coordinate_sign_w;
            wire [31:0] v_coordinate_w;
            wire [31:0] delay_sign_w;
            assign delay_sign_w = unused_delay_coordinate_data_w[64+lane*32 +: 32];
            assign delay_coordinate_input_w[64+lane*32 +: 32] = v_coordinate_w;
            wire [69:0] unused_depth_raw_w;
            assign unused_depth_raw_w = unused_plane_w[0 +: 70];
            reg [16:0] unused_depth_rounded_r;
            reg [0:0] depth_overflow_r;
            reg [0:0] depth_negative_r;
            reg [15:0] depth_clamped_r;
            wire [15:0] delay_22_w;
            assign delay_22_w = unused_delay_shade_data_w[0+lane*16 +: 16];
            assign delay_shade_input_w[0+lane*16 +: 16] = depth_clamped_r;
            wire [15:0] final_depth_w;
            assign final_depth_w = delay_22_w;
            wire [69:0] unused_red_raw_w;
            assign unused_red_raw_w = unused_plane_w[280 +: 70];
            reg [8:0] unused_red_rounded_r;
            reg [0:0] red_overflow_r;
            reg [0:0] red_negative_r;
            reg [7:0] red_clamped_r;
            wire [7:0] delay_23_w;
            assign delay_23_w = unused_delay_shade_data_w[32+lane*8 +: 8];
            assign delay_shade_input_w[32+lane*8 +: 8] = red_clamped_r;
            wire [7:0] final_red_w;
            assign final_red_w = delay_23_w;
            wire [69:0] unused_green_raw_w;
            assign unused_green_raw_w = unused_plane_w[350 +: 70];
            reg [8:0] unused_green_rounded_r;
            reg [0:0] green_overflow_r;
            reg [0:0] green_negative_r;
            reg [7:0] green_clamped_r;
            wire [7:0] delay_24_w;
            assign delay_24_w = unused_delay_shade_data_w[48+lane*8 +: 8];
            assign delay_shade_input_w[48+lane*8 +: 8] = green_clamped_r;
            wire [7:0] final_green_w;
            assign final_green_w = delay_24_w;
            wire [69:0] unused_blue_raw_w;
            assign unused_blue_raw_w = unused_plane_w[420 +: 70];
            reg [8:0] unused_blue_rounded_r;
            reg [0:0] blue_overflow_r;
            reg [0:0] blue_negative_r;
            reg [7:0] blue_clamped_r;
            wire [7:0] delay_bypass_w;
            assign delay_bypass_w = unused_delay_shade_data_w[64+lane*8 +: 8];
            assign delay_shade_input_w[64+lane*8 +: 8] = blue_clamped_r;
            wire [7:0] final_blue_w;
            assign final_blue_w = delay_bypass_w;
            edrv32_gpu_perspective_absolute u_q_absolute (
                .clk_i(clk_i),
                .en_i(advance_w),
                .value_i(unused_plane_w[70 +: 66]),
                .exponent_i(input_h_r[input_read_r][10 +: 10] - 10'd26),
                .magnitude_o(q_absolute_w),
                .sign_o(q_sign_w),
                .exponent_o(q_exponent_w)
            );
            edrv32_gpu_perspective_normal #(
                .WIDTH(66)
            ) u_q (
                .clk_i(clk_i),
                .en_i(advance_w),
                .magnitude_i(q_absolute_w),
                .sign_i(q_sign_w),
                .exponent_i(q_exponent_w),
                .normal_o(unused_q_w)
            );
            edrv32_gpu_perspective_absolute u_uq_absolute (
                .clk_i(clk_i),
                .en_i(advance_w),
                .value_i(unused_plane_w[140 +: 66]),
                .exponent_i(input_h_r[input_read_r][20 +: 10] - 10'd34),
                .magnitude_o(uq_absolute_w),
                .sign_o(uq_sign_w),
                .exponent_o(uq_exponent_w)
            );
            edrv32_gpu_perspective_normal #(
                .WIDTH(66)
            ) u_uq (
                .clk_i(clk_i),
                .en_i(advance_w),
                .magnitude_i(uq_absolute_w),
                .sign_i(uq_sign_w),
                .exponent_i(uq_exponent_w),
                .normal_o(uq_w)
            );
            edrv32_gpu_perspective_absolute u_vq_absolute (
                .clk_i(clk_i),
                .en_i(advance_w),
                .value_i(unused_plane_w[210 +: 66]),
                .exponent_i(input_h_r[input_read_r][30 +: 10] - 10'd34),
                .magnitude_o(vq_absolute_w),
                .sign_o(vq_sign_w),
                .exponent_o(vq_exponent_w)
            );
            edrv32_gpu_perspective_normal #(
                .WIDTH(66)
            ) u_vq (
                .clk_i(clk_i),
                .en_i(advance_w),
                .magnitude_i(vq_absolute_w),
                .sign_i(vq_sign_w),
                .exponent_i(vq_exponent_w),
                .normal_o(vq_w)
            );
            edrv32_rom_gpu_recip_p18 u_seed (
                .clk_i(clk_i),
                .en_i(advance_w),
                .addr_i(seed_address_r),
                .rd_data_o(seed_rom_w)
            );
            edrv32_gpu_perspective_multiply u_newton_first (
                .clk_i(clk_i),
                .en_i(advance_w),
                .a_i(delay_1_r[36 +: 18]),
                .b_i(seed_r),
                .sign_i(1'b0),
                .exponent_i(10'b0),
                .magnitude_o(unused_newton_first_w),
                .sign_o(unused_newton_first_sign_w),
                .exponent_o(unused_newton_first_exponent_w)
            );
            edrv32_gpu_perspective_multiply u_newton_second (
                .clk_i(clk_i),
                .en_i(advance_w),
                .a_i(delay_2_r[72 +: 18]),
                .b_i(newton_term_r),
                .sign_i(1'b0),
                .exponent_i(10'b0),
                .magnitude_o(unused_newton_second_w),
                .sign_o(unused_newton_second_sign_w),
                .exponent_o(unused_newton_second_exponent_w)
            );
            edrv32_gpu_perspective_multiply u_u_multiply (
                .clk_i(clk_i),
                .en_i(advance_w),
                .a_i(delay_4_w[17:0]),
                .b_i(inverse_r[17:0]),
                .sign_i(delay_4_w[18] ^ inverse_r[18]),
                .exponent_i(delay_4_w[28:19] + inverse_r[28:19]),
                .magnitude_o(u_multiply_magnitude_w),
                .sign_o(u_multiply_sign_w),
                .exponent_o(u_multiply_exponent_w)
            );
            edrv32_gpu_perspective_normal #(
                .WIDTH(36)
            ) u_u (
                .clk_i(clk_i),
                .en_i(advance_w),
                .magnitude_i(u_multiply_magnitude_w),
                .sign_i(u_multiply_sign_w),
                .exponent_i(u_multiply_exponent_w),
                .normal_o(u_w)
            );
            edrv32_gpu_perspective_multiply u_v_multiply (
                .clk_i(clk_i),
                .en_i(advance_w),
                .a_i(delay_5_w[17:0]),
                .b_i(inverse_r[17:0]),
                .sign_i(delay_5_w[18] ^ inverse_r[18]),
                .exponent_i(delay_5_w[28:19] + inverse_r[28:19]),
                .magnitude_o(v_multiply_magnitude_w),
                .sign_o(v_multiply_sign_w),
                .exponent_o(v_multiply_exponent_w)
            );
            edrv32_gpu_perspective_normal #(
                .WIDTH(36)
            ) u_v (
                .clk_i(clk_i),
                .en_i(advance_w),
                .magnitude_i(v_multiply_magnitude_w),
                .sign_i(v_multiply_sign_w),
                .exponent_i(v_multiply_exponent_w),
                .normal_o(v_w)
            );
            assign u_normal_w[lane*29 +: 29] = u_w;
            assign v_normal_w[lane*29 +: 29] = v_w;
            edrv32_gpu_perspective_scale #(
                .WIDTH(32)
            ) u_u_coordinate_magnitude (
                .clk_i(clk_i),
                .en_i(advance_w),
                .delay_scale_wr_data_o(delay_scale_input_w[lane*10 +: 5]),
                .delay_scale_rd_data_i(unused_delay_scale_data_w[lane*10 +: 5]),
                .magnitude_i(u_w[17:0]),
                .exponent_i(u_w[28:19] + 10'd8),
                .magnitude_o(unused_u_coordinate_magnitude_w)
            );
            edrv32_gpu_perspective_sign u_u_coordinate (
                .clk_i(clk_i),
                .en_i(advance_w),
                .magnitude_i(unused_u_coordinate_magnitude_w[31:0]),
                .sign_i(delay_6_w),
                .value_o(u_coordinate_w)
            );
            edrv32_gpu_perspective_scale #(
                .WIDTH(32)
            ) u_v_coordinate_magnitude (
                .clk_i(clk_i),
                .en_i(advance_w),
                .delay_scale_wr_data_o(delay_scale_input_w[lane*10+5 +: 5]),
                .delay_scale_rd_data_i(unused_delay_scale_data_w[lane*10+5 +: 5]),
                .magnitude_i(v_w[17:0]),
                .exponent_i(v_w[28:19] + 10'd8),
                .magnitude_o(unused_v_coordinate_magnitude_w)
            );
            edrv32_gpu_perspective_sign u_v_coordinate (
                .clk_i(clk_i),
                .en_i(advance_w),
                .magnitude_i(unused_v_coordinate_magnitude_w[31:0]),
                .sign_i(delay_scale_w),
                .value_o(v_coordinate_w)
            );
            always @(posedge clk_i) begin
                if (advance_w) begin
                    seed_address_r <= unused_q_w[16:7];
                    seed_r <= seed_rom_w;
                    delay_1_r <= {delay_1_r[35:0], q_mantissa_w};
                    newton_t_r <= unused_newton_t_sum_w[17:0];
                    newton_term_r <= -newton_t_r;
                    delay_2_r <= {delay_2_r[71:0], seed_r};
                    newton_r1_r <= unused_newton_r1_sum_w[17:0];
                    inverse_mantissa_r <= delay_3_w[10] ? 18'b0 :
                        newton_r1_r[17] ? newton_r1_r : {newton_r1_r[16:0], 1'b0};
                    inverse_exponent_r <= -10'd34 - delay_3_w[9:0] - {9'b0, !newton_r1_r[17]};
                    inverse_sign_r <= delay_3_w[11];
                    inverse_r <= inverse_mantissa_r == 0 ? 29'b0
                        : {inverse_exponent_r, inverse_sign_r, inverse_mantissa_r};
                    unused_depth_rounded_r <= {1'b0, unused_depth_raw_w[8 +: 16]}
                        + {16'b0, unused_depth_raw_w[7]};
                    depth_overflow_r <= unused_depth_raw_w[69:24] != 0;
                    depth_negative_r <= unused_depth_raw_w[69];
                    depth_clamped_r <= depth_negative_r ? 16'b0 : (depth_overflow_r
                        || unused_depth_rounded_r[16]) ? 16'd65535 : unused_depth_rounded_r[15:0];
                    unused_red_rounded_r <= {1'b0, unused_red_raw_w[12 +: 8]}
                        + {8'b0, unused_red_raw_w[11]};
                    red_overflow_r <= unused_red_raw_w[69:20] != 0;
                    red_negative_r <= unused_red_raw_w[69];
                    red_clamped_r <= red_negative_r ? 8'b0 : (red_overflow_r
                        || unused_red_rounded_r[8]) ? 8'd255 : unused_red_rounded_r[7:0];
                    unused_green_rounded_r <= {1'b0, unused_green_raw_w[12 +: 8]}
                        + {8'b0, unused_green_raw_w[11]};
                    green_overflow_r <= unused_green_raw_w[69:20] != 0;
                    green_negative_r <= unused_green_raw_w[69];
                    green_clamped_r <= green_negative_r ? 8'b0 : (green_overflow_r
                        || unused_green_rounded_r[8]) ? 8'd255 : unused_green_rounded_r[7:0];
                    unused_blue_rounded_r <= {1'b0, unused_blue_raw_w[12 +: 8]}
                        + {8'b0, unused_blue_raw_w[11]};
                    blue_overflow_r <= unused_blue_raw_w[69:20] != 0;
                    blue_negative_r <= unused_blue_raw_w[69];
                    blue_clamped_r <= blue_negative_r ? 8'b0 : (blue_overflow_r
                        || unused_blue_rounded_r[8]) ? 8'd255 : unused_blue_rounded_r[7:0];
                end
            end
            assign raw_u_w[lane*32 +: 32] = delay_7_w;
            assign raw_v_w[lane*32 +: 32] = delay_sign_w;
            assign unused_raw_span_w[lane*96 +: 96] = pipe_y_w[0] ?
                previous_span_r[(lane/2)*96 +: 96] :
                quad_span_w[(lane/2)*96 +: 96];
            assign raw_depth_w[lane*16 +: 16] = final_depth_w;
            assign raw_color_w[lane*24 +: 24] =
                {final_blue_w, final_green_w, final_red_w};
        end
    endgenerate
    genvar quad_idx;
    genvar pair_idx;
    genvar axis;
    generate
        // Two quads, four edges and two texture axes: sixteen normalized subtractors.
        for (quad_idx = 0; quad_idx < 1; quad_idx = quad_idx + 1) begin : g_quad_span
            wire [767:0] edge_span_w;
            wire [383:0] maximum_1_w;
            wire [191:0] maximum_2_w;
            for (pair_idx = 0; pair_idx < 4; pair_idx = pair_idx + 1) begin : g_pair
                localparam PAIR_OFFSET = pair_idx*2;
                for (axis = 0; axis < 2; axis = axis + 1) begin : g_axis
                    localparam SLOT = quad_idx*8 + PAIR_OFFSET + axis;
                    localparam LEFT = quad_idx*2 + (pair_idx == 3 ? 1 : 0);
                    localparam RIGHT = quad_idx*2 + (pair_idx < 2 ? 1 : pair_idx-2);
                    wire [57:0] unused_top_w;
                    wire [57:0] unused_bottom_w;
                    wire [28:0] a_w;
                    wire [28:0] b_w;
                    wire [28:0] unused_difference_w;
                    assign unused_top_w = axis == 0 ? previous_u_r : previous_v_r;
                    assign unused_bottom_w = axis == 0 ? u_normal_w : v_normal_w;
                    assign a_w = pair_idx == 0 ? unused_top_w[RIGHT*29 +: 29] :
                        unused_bottom_w[RIGHT*29 +: 29];
                    assign b_w = pair_idx == 1 ? unused_bottom_w[LEFT*29 +: 29] :
                        unused_top_w[LEFT*29 +: 29];
                    edrv32_gpu_perspective_subtract u_difference (
                        .clk_i(clk_i),
                        .en_i(advance_w),
                        .a_i(a_w),
                        .b_i(b_w),
                        .normal_o(unused_difference_w),
                        .delay_bypass_wr_data_o(delay_bypass_input_w[SLOT*29 +: 29]),
                        .delay_bypass_rd_data_i(unused_delay_bypass_data_w[SLOT*29 +: 29])
                    );
                    edrv32_gpu_perspective_scale #(
                        .WIDTH(96)
                    ) u_span (
                        .clk_i(clk_i),
                        .en_i(advance_w),
                        .magnitude_i(unused_difference_w[17:0]),
                        .exponent_i(unused_difference_w[28:19] + 10'd16),
                        .magnitude_o(edge_span_w[(pair_idx*2+axis)*96 +: 96]),
                        .delay_scale_wr_data_o(delay_scale_input_w[20+SLOT*5 +: 5]),
                        .delay_scale_rd_data_i(unused_delay_scale_data_w[20+SLOT*5 +: 5])
                    );
                end
                edrv32_gpu_perspective_maximum u_maximum_1 (
                    .clk_i(clk_i),
                    .en_i(advance_w),
                    .a_i(edge_span_w[pair_idx*192 +: 96]),
                    .b_i(edge_span_w[pair_idx*192+96 +: 96]),
                    .value_o(maximum_1_w[pair_idx*96 +: 96])
                );
            end
            for (pair_idx = 0; pair_idx < 2; pair_idx = pair_idx + 1) begin : g_maximum
                edrv32_gpu_perspective_maximum u_maximum_2 (
                    .clk_i(clk_i),
                    .en_i(advance_w),
                    .a_i(maximum_1_w[pair_idx*192 +: 96]),
                    .b_i(maximum_1_w[pair_idx*192+96 +: 96]),
                    .value_o(maximum_2_w[pair_idx*96 +: 96])
                );
            end
            edrv32_gpu_perspective_maximum u_maximum_3 (
                .clk_i(clk_i),
                .en_i(advance_w),
                .a_i(maximum_2_w[0 +: 96]),
                .b_i(maximum_2_w[96 +: 96]),
                .value_o(quad_span_w[quad_idx*96 +: 96])
            );
        end
    endgenerate
endmodule
