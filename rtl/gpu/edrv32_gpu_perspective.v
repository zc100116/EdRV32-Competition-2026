// File: edrv32_gpu_perspective.v
// Spec: gpu-spec 2.5, 2.8, 2.13; microarch 4.2, 4.4, 4.6.
// Description: Four-lane ordered streaming pixel arithmetic.
//              P18 quotient-rule derivatives and independent exact quad bypass.
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
    input wire [3:0] fragment_mask_i,
    input wire fragment_quad_i,
    input wire [1959:0] fragment_plane_i,
    input wire [69:0] fragment_h_i,
    input wire [173:0] fragment_gradient_i,
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

    reg [1:0] input_count_r;
    reg input_read_r;
    reg input_write_r;
    reg [7:0] output_count_r;
    reg [7:0] outstanding_r;
    reg output_valid_r;
    wire output_read_w;
    wire [8:0] output_addr_w;
    reg [8:0] output_read_r;
    reg [8:0] output_write_r;
    reg [104:0] valid_r;
    wire advance_w;
    wire input_push_w;
    wire input_pop_w;
    wire output_push_w;
    wire output_pop_w;
    reg [15:0] input_x_r [0:1];
    reg [15:0] input_y_r [0:1];
    reg [3:0] input_mask_r [0:1];
    reg [0:0] input_quad_r [0:1];
    reg [69:0] input_h_r [0:1];
    reg [173:0] input_gradient_r [0:1];
    reg [3:0] input_palette_r [0:1];
    reg [7:0] input_alpha_r [0:1];
    wire [15:0] pipe_x_w;
    wire [15:0] pipe_y_w;
    wire [3:0] pipe_mask_w;
    wire [0:0] pipe_quad_w;
    wire [3:0] pipe_palette_w;
    wire [7:0] pipe_alpha_w;
    wire [848:0] output_input_w;
    wire [863:0] unused_output_data_w;
    wire [15:0] output_x_w;
    wire [15:0] output_y_w;
    wire [3:0] output_mask_w;
    wire [0:0] output_quad_w;
    wire [3:0] output_palette_w;
    wire [7:0] output_alpha_w;
    wire [127:0] output_u_w;
    wire [127:0] output_v_w;
    wire [383:0] output_span_w;
    wire [63:0] output_depth_w;
    wire [95:0] output_color_w;
    reg [8:0] delay_write_r;
    wire [7:0] delay_9_input_w;
    wire [71:0] unused_delay_9_data_w;
    wire [8:0] delay_9_read_w;
    wire [39:0] delay_12_input_w;
    wire [71:0] unused_delay_12_data_w;
    wire [8:0] delay_12_read_w;
    wire [391:0] delay_14_input_w;
    wire [431:0] unused_delay_14_data_w;
    wire [8:0] delay_14_read_w;
    wire [57:0] delay_41_input_w;
    wire [71:0] unused_delay_41_data_w;
    wire [8:0] delay_41_read_w;
    wire [115:0] delay_51_input_w;
    wire [143:0] unused_delay_51_data_w;
    wire [8:0] delay_51_read_w;
    wire [255:0] delay_53_input_w;
    wire [287:0] unused_delay_53_data_w;
    wire [8:0] delay_53_read_w;
    wire [115:0] delay_54_input_w;
    wire [143:0] unused_delay_54_data_w;
    wire [8:0] delay_54_read_w;
    wire [159:0] delay_103_input_w;
    wire [215:0] unused_delay_103_data_w;
    wire [8:0] delay_103_read_w;
    wire [304:0] delay_105_input_w;
    wire [359:0] unused_delay_105_data_w;
    wire [8:0] delay_105_read_w;
    wire [119:0] delay_8_input_w;
    wire [143:0] unused_delay_8_data_w;
    wire [8:0] delay_8_read_w;
    wire [463:0] delay_25_input_w;
    wire [503:0] unused_delay_25_data_w;
    wire [8:0] delay_25_read_w;


    // Two input slots decouple acceptance; 128 result credits cover all 105 stages.

    assign advance_w = 1'b1;
    assign fragment_ready_o = input_count_r < 2 && outstanding_r < 128;
    assign sample_valid_o = output_valid_r && !stop_i;
    assign input_push_w = fragment_valid_i && fragment_ready_o && !stop_i;
    assign input_pop_w = (input_count_r != 0) && !stop_i;
    assign output_push_w = valid_r[104] && !stop_i;
    assign output_pop_w = sample_valid_o && sample_ready_i;
    // The RAM output holds the prefetched head during downstream backpressure.
    assign output_read_w = !stop_i && ((output_count_r != 0 && !output_valid_r) ||
        (output_pop_w && output_count_r > 1));
    assign output_addr_w = output_read_r + {8'b0, output_pop_w};

    assign pipe_x_w = unused_delay_105_data_w[256 +: 16];
    assign pipe_y_w = unused_delay_105_data_w[272 +: 16];
    assign pipe_mask_w = unused_delay_105_data_w[288 +: 4];
    assign pipe_quad_w = unused_delay_105_data_w[292 +: 1];
    assign pipe_palette_w = unused_delay_105_data_w[293 +: 4];
    assign pipe_alpha_w = unused_delay_105_data_w[297 +: 8];

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
            end else if (input_count_r == 0 && valid_r == 0 && output_count_r == 0) begin
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
                if (input_push_w != output_pop_w) begin
                    outstanding_r <= input_push_w ?
                        outstanding_r + 1'b1 : outstanding_r - 1'b1;
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
                    valid_r <= {valid_r[103:0], input_pop_w};
                end
            end
        end
    end

    always @(posedge clk_i) begin
        if (input_push_w) begin
            input_x_r[input_write_r] <= fragment_x_i;
            input_y_r[input_write_r] <= fragment_y_i;
            input_mask_r[input_write_r] <= fragment_mask_i;
            input_quad_r[input_write_r] <= fragment_quad_i;
            input_h_r[input_write_r] <= fragment_h_i;
            input_gradient_r[input_write_r] <= fragment_gradient_i;
            input_palette_r[input_write_r] <= fragment_palette_i;
            input_alpha_r[input_write_r] <= fragment_alpha_i;
        end
    end

    assign output_x_w = pipe_x_w;
    assign output_y_w = pipe_y_w;
    assign output_mask_w = pipe_mask_w;
    assign output_quad_w = pipe_quad_w;
    assign output_palette_w = pipe_palette_w;
    assign output_alpha_w = pipe_alpha_w;

    assign output_input_w[0 +: 16] = output_x_w;
    assign sample_x_o = unused_output_data_w[0 +: 16];
    assign output_input_w[16 +: 16] = output_y_w;
    assign sample_y_o = unused_output_data_w[16 +: 16];
    assign output_input_w[32 +: 4] = output_mask_w;
    assign sample_mask_o = unused_output_data_w[32 +: 4];
    assign output_input_w[36 +: 1] = output_quad_w;
    assign sample_quad_o = unused_output_data_w[36 +: 1];
    assign output_input_w[37 +: 4] = output_palette_w;
    assign sample_palette_o = unused_output_data_w[37 +: 4];
    assign output_input_w[41 +: 8] = output_alpha_w;
    assign sample_alpha_o = unused_output_data_w[41 +: 8];
    assign output_input_w[49 +: 128] = output_u_w;
    assign sample_u_o = unused_output_data_w[49 +: 128];
    assign output_input_w[177 +: 128] = output_v_w;
    assign sample_v_o = unused_output_data_w[177 +: 128];
    assign sample_span_o[0 +: 96] = unused_output_data_w[305 +: 96];
    assign sample_span_o[96 +: 96] = unused_output_data_w[401 +: 96];
    assign sample_span_o[192 +: 96] = unused_output_data_w[497 +: 96];
    assign sample_span_o[288 +: 96] = unused_output_data_w[593 +: 96];
    assign output_input_w[689 +: 64] = output_depth_w;
    assign sample_depth_o = unused_output_data_w[689 +: 64];
    assign output_input_w[753 +: 96] = output_color_w;
    assign sample_color_o = unused_output_data_w[753 +: 96];
    assign output_input_w[305 +: 96] = output_span_w[0 +: 96];
    assign output_input_w[401 +: 96] = output_span_w[96 +: 96];
    assign output_input_w[497 +: 96] = output_span_w[192 +: 96];
    assign output_input_w[593 +: 96] = output_span_w[288 +: 96];
    edrv32_ram_gpu_delay u_output_0 (
        .clk_i(clk_i),
        .wr_en_i(output_push_w),
        .wr_addr_i(output_write_r),
        .wr_data_i(output_input_w[0 +: 72]),
        .rd_en_i(output_read_w),
        .rd_addr_i(output_addr_w),
        .rd_data_o(unused_output_data_w[0 +: 72])
    );
    edrv32_ram_gpu_delay u_output_1 (
        .clk_i(clk_i),
        .wr_en_i(output_push_w),
        .wr_addr_i(output_write_r),
        .wr_data_i(output_input_w[72 +: 72]),
        .rd_en_i(output_read_w),
        .rd_addr_i(output_addr_w),
        .rd_data_o(unused_output_data_w[72 +: 72])
    );
    edrv32_ram_gpu_delay u_output_2 (
        .clk_i(clk_i),
        .wr_en_i(output_push_w),
        .wr_addr_i(output_write_r),
        .wr_data_i(output_input_w[144 +: 72]),
        .rd_en_i(output_read_w),
        .rd_addr_i(output_addr_w),
        .rd_data_o(unused_output_data_w[144 +: 72])
    );
    edrv32_ram_gpu_delay u_output_3 (
        .clk_i(clk_i),
        .wr_en_i(output_push_w),
        .wr_addr_i(output_write_r),
        .wr_data_i(output_input_w[216 +: 72]),
        .rd_en_i(output_read_w),
        .rd_addr_i(output_addr_w),
        .rd_data_o(unused_output_data_w[216 +: 72])
    );
    edrv32_ram_gpu_delay u_output_4 (
        .clk_i(clk_i),
        .wr_en_i(output_push_w),
        .wr_addr_i(output_write_r),
        .wr_data_i(output_input_w[288 +: 72]),
        .rd_en_i(output_read_w),
        .rd_addr_i(output_addr_w),
        .rd_data_o(unused_output_data_w[288 +: 72])
    );
    edrv32_ram_gpu_delay u_output_5 (
        .clk_i(clk_i),
        .wr_en_i(output_push_w),
        .wr_addr_i(output_write_r),
        .wr_data_i(output_input_w[360 +: 72]),
        .rd_en_i(output_read_w),
        .rd_addr_i(output_addr_w),
        .rd_data_o(unused_output_data_w[360 +: 72])
    );
    edrv32_ram_gpu_delay u_output_6 (
        .clk_i(clk_i),
        .wr_en_i(output_push_w),
        .wr_addr_i(output_write_r),
        .wr_data_i(output_input_w[432 +: 72]),
        .rd_en_i(output_read_w),
        .rd_addr_i(output_addr_w),
        .rd_data_o(unused_output_data_w[432 +: 72])
    );
    edrv32_ram_gpu_delay u_output_7 (
        .clk_i(clk_i),
        .wr_en_i(output_push_w),
        .wr_addr_i(output_write_r),
        .wr_data_i(output_input_w[504 +: 72]),
        .rd_en_i(output_read_w),
        .rd_addr_i(output_addr_w),
        .rd_data_o(unused_output_data_w[504 +: 72])
    );
    edrv32_ram_gpu_delay u_output_8 (
        .clk_i(clk_i),
        .wr_en_i(output_push_w),
        .wr_addr_i(output_write_r),
        .wr_data_i(output_input_w[576 +: 72]),
        .rd_en_i(output_read_w),
        .rd_addr_i(output_addr_w),
        .rd_data_o(unused_output_data_w[576 +: 72])
    );
    edrv32_ram_gpu_delay u_output_9 (
        .clk_i(clk_i),
        .wr_en_i(output_push_w),
        .wr_addr_i(output_write_r),
        .wr_data_i(output_input_w[648 +: 72]),
        .rd_en_i(output_read_w),
        .rd_addr_i(output_addr_w),
        .rd_data_o(unused_output_data_w[648 +: 72])
    );
    edrv32_ram_gpu_delay u_output_10 (
        .clk_i(clk_i),
        .wr_en_i(output_push_w),
        .wr_addr_i(output_write_r),
        .wr_data_i(output_input_w[720 +: 72]),
        .rd_en_i(output_read_w),
        .rd_addr_i(output_addr_w),
        .rd_data_o(unused_output_data_w[720 +: 72])
    );
    edrv32_ram_gpu_delay u_output_11 (
        .clk_i(clk_i),
        .wr_en_i(output_push_w),
        .wr_addr_i(output_write_r),
        .wr_data_i({15'b0, output_input_w[792 +: 57]}),
        .rd_en_i(output_read_w),
        .rd_addr_i(output_addr_w),
        .rd_data_o(unused_output_data_w[792 +: 72])
    );

    // Fixed-distance circular RAM delays. The synchronous read is the last stage.
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) delay_write_r <= 0;
        else if (advance_w) delay_write_r <= delay_write_r + 1'b1;
    end
    assign delay_9_read_w = delay_write_r - 9'd8;
    edrv32_ram_gpu_delay u_delay_9_0 (
        .clk_i(clk_i),
        .wr_en_i(advance_w),
        .wr_addr_i(delay_write_r),
        .wr_data_i({64'b0, delay_9_input_w[0 +: 8]}),
        .rd_en_i(advance_w),
        .rd_addr_i(delay_9_read_w),
        .rd_data_o(unused_delay_9_data_w[0 +: 72])
    );
    assign delay_12_read_w = delay_write_r - 9'd11;
    edrv32_ram_gpu_delay u_delay_12_0 (
        .clk_i(clk_i),
        .wr_en_i(advance_w),
        .wr_addr_i(delay_write_r),
        .wr_data_i({32'b0, delay_12_input_w[0 +: 40]}),
        .rd_en_i(advance_w),
        .rd_addr_i(delay_12_read_w),
        .rd_data_o(unused_delay_12_data_w[0 +: 72])
    );
    assign delay_14_read_w = delay_write_r - 9'd13;
    edrv32_ram_gpu_delay u_delay_14_0 (
        .clk_i(clk_i),
        .wr_en_i(advance_w),
        .wr_addr_i(delay_write_r),
        .wr_data_i(delay_14_input_w[0 +: 72]),
        .rd_en_i(advance_w),
        .rd_addr_i(delay_14_read_w),
        .rd_data_o(unused_delay_14_data_w[0 +: 72])
    );
    edrv32_ram_gpu_delay u_delay_14_1 (
        .clk_i(clk_i),
        .wr_en_i(advance_w),
        .wr_addr_i(delay_write_r),
        .wr_data_i(delay_14_input_w[72 +: 72]),
        .rd_en_i(advance_w),
        .rd_addr_i(delay_14_read_w),
        .rd_data_o(unused_delay_14_data_w[72 +: 72])
    );
    edrv32_ram_gpu_delay u_delay_14_2 (
        .clk_i(clk_i),
        .wr_en_i(advance_w),
        .wr_addr_i(delay_write_r),
        .wr_data_i(delay_14_input_w[144 +: 72]),
        .rd_en_i(advance_w),
        .rd_addr_i(delay_14_read_w),
        .rd_data_o(unused_delay_14_data_w[144 +: 72])
    );
    edrv32_ram_gpu_delay u_delay_14_3 (
        .clk_i(clk_i),
        .wr_en_i(advance_w),
        .wr_addr_i(delay_write_r),
        .wr_data_i(delay_14_input_w[216 +: 72]),
        .rd_en_i(advance_w),
        .rd_addr_i(delay_14_read_w),
        .rd_data_o(unused_delay_14_data_w[216 +: 72])
    );
    assign delay_41_read_w = delay_write_r - 9'd40;
    edrv32_ram_gpu_delay u_delay_41_0 (
        .clk_i(clk_i),
        .wr_en_i(advance_w),
        .wr_addr_i(delay_write_r),
        .wr_data_i({14'b0, delay_41_input_w[0 +: 58]}),
        .rd_en_i(advance_w),
        .rd_addr_i(delay_41_read_w),
        .rd_data_o(unused_delay_41_data_w[0 +: 72])
    );
    assign delay_51_read_w = delay_write_r - 9'd50;
    edrv32_ram_gpu_delay u_delay_51_0 (
        .clk_i(clk_i),
        .wr_en_i(advance_w),
        .wr_addr_i(delay_write_r),
        .wr_data_i(delay_51_input_w[0 +: 72]),
        .rd_en_i(advance_w),
        .rd_addr_i(delay_51_read_w),
        .rd_data_o(unused_delay_51_data_w[0 +: 72])
    );
    edrv32_ram_gpu_delay u_delay_51_1 (
        .clk_i(clk_i),
        .wr_en_i(advance_w),
        .wr_addr_i(delay_write_r),
        .wr_data_i({28'b0, delay_51_input_w[72 +: 44]}),
        .rd_en_i(advance_w),
        .rd_addr_i(delay_51_read_w),
        .rd_data_o(unused_delay_51_data_w[72 +: 72])
    );
    assign delay_53_read_w = delay_write_r - 9'd52;
    edrv32_ram_gpu_delay u_delay_53_0 (
        .clk_i(clk_i),
        .wr_en_i(advance_w),
        .wr_addr_i(delay_write_r),
        .wr_data_i(delay_53_input_w[0 +: 72]),
        .rd_en_i(advance_w),
        .rd_addr_i(delay_53_read_w),
        .rd_data_o(unused_delay_53_data_w[0 +: 72])
    );
    edrv32_ram_gpu_delay u_delay_53_1 (
        .clk_i(clk_i),
        .wr_en_i(advance_w),
        .wr_addr_i(delay_write_r),
        .wr_data_i(delay_53_input_w[72 +: 72]),
        .rd_en_i(advance_w),
        .rd_addr_i(delay_53_read_w),
        .rd_data_o(unused_delay_53_data_w[72 +: 72])
    );
    edrv32_ram_gpu_delay u_delay_53_2 (
        .clk_i(clk_i),
        .wr_en_i(advance_w),
        .wr_addr_i(delay_write_r),
        .wr_data_i(delay_53_input_w[144 +: 72]),
        .rd_en_i(advance_w),
        .rd_addr_i(delay_53_read_w),
        .rd_data_o(unused_delay_53_data_w[144 +: 72])
    );
    edrv32_ram_gpu_delay u_delay_53_3 (
        .clk_i(clk_i),
        .wr_en_i(advance_w),
        .wr_addr_i(delay_write_r),
        .wr_data_i({32'b0, delay_53_input_w[216 +: 40]}),
        .rd_en_i(advance_w),
        .rd_addr_i(delay_53_read_w),
        .rd_data_o(unused_delay_53_data_w[216 +: 72])
    );
    assign delay_54_read_w = delay_write_r - 9'd53;
    edrv32_ram_gpu_delay u_delay_54_0 (
        .clk_i(clk_i),
        .wr_en_i(advance_w),
        .wr_addr_i(delay_write_r),
        .wr_data_i(delay_54_input_w[0 +: 72]),
        .rd_en_i(advance_w),
        .rd_addr_i(delay_54_read_w),
        .rd_data_o(unused_delay_54_data_w[0 +: 72])
    );
    edrv32_ram_gpu_delay u_delay_54_1 (
        .clk_i(clk_i),
        .wr_en_i(advance_w),
        .wr_addr_i(delay_write_r),
        .wr_data_i({28'b0, delay_54_input_w[72 +: 44]}),
        .rd_en_i(advance_w),
        .rd_addr_i(delay_54_read_w),
        .rd_data_o(unused_delay_54_data_w[72 +: 72])
    );
    assign delay_103_read_w = delay_write_r - 9'd102;
    edrv32_ram_gpu_delay u_delay_103_0 (
        .clk_i(clk_i),
        .wr_en_i(advance_w),
        .wr_addr_i(delay_write_r),
        .wr_data_i(delay_103_input_w[0 +: 72]),
        .rd_en_i(advance_w),
        .rd_addr_i(delay_103_read_w),
        .rd_data_o(unused_delay_103_data_w[0 +: 72])
    );
    edrv32_ram_gpu_delay u_delay_103_1 (
        .clk_i(clk_i),
        .wr_en_i(advance_w),
        .wr_addr_i(delay_write_r),
        .wr_data_i(delay_103_input_w[72 +: 72]),
        .rd_en_i(advance_w),
        .rd_addr_i(delay_103_read_w),
        .rd_data_o(unused_delay_103_data_w[72 +: 72])
    );
    edrv32_ram_gpu_delay u_delay_103_2 (
        .clk_i(clk_i),
        .wr_en_i(advance_w),
        .wr_addr_i(delay_write_r),
        .wr_data_i({56'b0, delay_103_input_w[144 +: 16]}),
        .rd_en_i(advance_w),
        .rd_addr_i(delay_103_read_w),
        .rd_data_o(unused_delay_103_data_w[144 +: 72])
    );
    assign delay_105_read_w = delay_write_r - 9'd104;
    edrv32_ram_gpu_delay u_delay_105_0 (
        .clk_i(clk_i),
        .wr_en_i(advance_w),
        .wr_addr_i(delay_write_r),
        .wr_data_i(delay_105_input_w[0 +: 72]),
        .rd_en_i(advance_w),
        .rd_addr_i(delay_105_read_w),
        .rd_data_o(unused_delay_105_data_w[0 +: 72])
    );
    edrv32_ram_gpu_delay u_delay_105_1 (
        .clk_i(clk_i),
        .wr_en_i(advance_w),
        .wr_addr_i(delay_write_r),
        .wr_data_i(delay_105_input_w[72 +: 72]),
        .rd_en_i(advance_w),
        .rd_addr_i(delay_105_read_w),
        .rd_data_o(unused_delay_105_data_w[72 +: 72])
    );
    edrv32_ram_gpu_delay u_delay_105_2 (
        .clk_i(clk_i),
        .wr_en_i(advance_w),
        .wr_addr_i(delay_write_r),
        .wr_data_i(delay_105_input_w[144 +: 72]),
        .rd_en_i(advance_w),
        .rd_addr_i(delay_105_read_w),
        .rd_data_o(unused_delay_105_data_w[144 +: 72])
    );
    edrv32_ram_gpu_delay u_delay_105_3 (
        .clk_i(clk_i),
        .wr_en_i(advance_w),
        .wr_addr_i(delay_write_r),
        .wr_data_i(delay_105_input_w[216 +: 72]),
        .rd_en_i(advance_w),
        .rd_addr_i(delay_105_read_w),
        .rd_data_o(unused_delay_105_data_w[216 +: 72])
    );
    edrv32_ram_gpu_delay u_delay_105_4 (
        .clk_i(clk_i),
        .wr_en_i(advance_w),
        .wr_addr_i(delay_write_r),
        .wr_data_i({55'b0, delay_105_input_w[288 +: 17]}),
        .rd_en_i(advance_w),
        .rd_addr_i(delay_105_read_w),
        .rd_data_o(unused_delay_105_data_w[288 +: 72])
    );
    assign delay_41_input_w[0 +: 29] = input_gradient_r[input_read_r][0 +: 29];
    assign delay_41_input_w[29 +: 29] = input_gradient_r[input_read_r][87 +: 29];
    assign delay_54_input_w[0 +: 29] = input_gradient_r[input_read_r][29 +: 29];
    assign delay_54_input_w[29 +: 29] = input_gradient_r[input_read_r][58 +: 29];
    assign delay_54_input_w[58 +: 29] = input_gradient_r[input_read_r][116 +: 29];
    assign delay_54_input_w[87 +: 29] = input_gradient_r[input_read_r][145 +: 29];
    assign delay_105_input_w[256 +: 49] =
        {input_alpha_r[input_read_r], input_palette_r[input_read_r],
        input_quad_r[input_read_r], input_mask_r[input_read_r],
        input_y_r[input_read_r], input_x_r[input_read_r]};

    edrv32_ram_gpu_delay u_delay_14_4 (
        .clk_i(clk_i),
        .wr_en_i(advance_w),
        .wr_addr_i(delay_write_r),
        .wr_data_i(delay_14_input_w[288 +: 72]),
        .rd_en_i(advance_w),
        .rd_addr_i(delay_14_read_w),
        .rd_data_o(unused_delay_14_data_w[288 +: 72])
    );
    edrv32_ram_gpu_delay u_delay_14_5 (
        .clk_i(clk_i),
        .wr_en_i(advance_w),
        .wr_addr_i(delay_write_r),
        .wr_data_i({40'b0, delay_14_input_w[360 +: 32]}),
        .rd_en_i(advance_w),
        .rd_addr_i(delay_14_read_w),
        .rd_data_o(unused_delay_14_data_w[360 +: 72])
    );
    assign delay_8_read_w = delay_write_r - 9'd7;
    edrv32_ram_gpu_delay u_delay_8_0 (
        .clk_i(clk_i),
        .wr_en_i(advance_w),
        .wr_addr_i(delay_write_r),
        .wr_data_i(delay_8_input_w[0 +: 72]),
        .rd_en_i(advance_w),
        .rd_addr_i(delay_8_read_w),
        .rd_data_o(unused_delay_8_data_w[0 +: 72])
    );
    edrv32_ram_gpu_delay u_delay_8_1 (
        .clk_i(clk_i),
        .wr_en_i(advance_w),
        .wr_addr_i(delay_write_r),
        .wr_data_i({24'b0, delay_8_input_w[72 +: 48]}),
        .rd_en_i(advance_w),
        .rd_addr_i(delay_8_read_w),
        .rd_data_o(unused_delay_8_data_w[72 +: 72])
    );
    assign delay_25_read_w = delay_write_r - 9'd24;
    edrv32_ram_gpu_delay u_delay_25_0 (
        .clk_i(clk_i),
        .wr_en_i(advance_w),
        .wr_addr_i(delay_write_r),
        .wr_data_i(delay_25_input_w[0 +: 72]),
        .rd_en_i(advance_w),
        .rd_addr_i(delay_25_read_w),
        .rd_data_o(unused_delay_25_data_w[0 +: 72])
    );
    edrv32_ram_gpu_delay u_delay_25_1 (
        .clk_i(clk_i),
        .wr_en_i(advance_w),
        .wr_addr_i(delay_write_r),
        .wr_data_i(delay_25_input_w[72 +: 72]),
        .rd_en_i(advance_w),
        .rd_addr_i(delay_25_read_w),
        .rd_data_o(unused_delay_25_data_w[72 +: 72])
    );
    edrv32_ram_gpu_delay u_delay_25_2 (
        .clk_i(clk_i),
        .wr_en_i(advance_w),
        .wr_addr_i(delay_write_r),
        .wr_data_i(delay_25_input_w[144 +: 72]),
        .rd_en_i(advance_w),
        .rd_addr_i(delay_25_read_w),
        .rd_data_o(unused_delay_25_data_w[144 +: 72])
    );
    edrv32_ram_gpu_delay u_delay_25_3 (
        .clk_i(clk_i),
        .wr_en_i(advance_w),
        .wr_addr_i(delay_write_r),
        .wr_data_i(delay_25_input_w[216 +: 72]),
        .rd_en_i(advance_w),
        .rd_addr_i(delay_25_read_w),
        .rd_data_o(unused_delay_25_data_w[216 +: 72])
    );
    edrv32_ram_gpu_delay u_delay_25_4 (
        .clk_i(clk_i),
        .wr_en_i(advance_w),
        .wr_addr_i(delay_write_r),
        .wr_data_i(delay_25_input_w[288 +: 72]),
        .rd_en_i(advance_w),
        .rd_addr_i(delay_25_read_w),
        .rd_data_o(unused_delay_25_data_w[288 +: 72])
    );
    edrv32_ram_gpu_delay u_delay_25_5 (
        .clk_i(clk_i),
        .wr_en_i(advance_w),
        .wr_addr_i(delay_write_r),
        .wr_data_i(delay_25_input_w[360 +: 72]),
        .rd_en_i(advance_w),
        .rd_addr_i(delay_25_read_w),
        .rd_data_o(unused_delay_25_data_w[360 +: 72])
    );
    edrv32_ram_gpu_delay u_delay_25_6 (
        .clk_i(clk_i),
        .wr_en_i(advance_w),
        .wr_addr_i(delay_write_r),
        .wr_data_i({40'b0, delay_25_input_w[432 +: 32]}),
        .rd_en_i(advance_w),
        .rd_addr_i(delay_25_read_w),
        .rd_data_o(unused_delay_25_data_w[432 +: 72])
    );

    genvar lane;
    generate
        for (lane = 0; lane < 4; lane = lane + 1) begin : g_lane
            // Four lanes, each owning seven 70-bit two-slot input field queues.
            // No queue array is shared between generated lanes or fields.
            wire [70*7-1:0] plane_w;
            genvar attribute;
            for (attribute = 0; attribute < 7; attribute = attribute + 1) begin : g_plane
                reg [69:0] input_plane_r [0:1];
                always @(posedge clk_i) begin
                    if (input_push_w) begin
                        input_plane_r[input_write_r] <=
                            fragment_plane_i[lane*490+attribute*70 +: 70];
                    end
                end
                assign plane_w[70*attribute +: 70] = input_plane_r[input_read_r];
            end

            // Two short register delays stay local; deep delays share RAM across lanes.
            wire [69:0] q_absolute_w;
            wire [0:0] q_sign_w;
            wire [9:0] q_exponent_w;
            wire [28:0] unused_q_w;
            wire [69:0] uq_absolute_w;
            wire [0:0] uq_sign_w;
            wire [9:0] uq_exponent_w;
            wire [28:0] uq_w;
            wire [69:0] vq_absolute_w;
            wire [0:0] vq_sign_w;
            wire [9:0] vq_exponent_w;
            wire [28:0] vq_w;
            reg [9:0] seed_address_r;
            wire [17:0] seed_rom_w;
            reg [17:0] seed_r;
            wire [17:0] q_mantissa_w;
            assign q_mantissa_w = unused_q_w[17:0];
            reg [17:0] delay_1_r [0:2];
            wire [35:0] unused_newton_first_w;
            wire [0:0] unused_newton_first_sign_w;
            wire [9:0] unused_newton_first_exponent_w;
            wire [19:0] unused_newton_t_sum_w;
            assign unused_newton_t_sum_w = {1'b0, unused_newton_first_w[35:17]}
                + {19'b0, unused_newton_first_w[16]};
            reg [17:0] newton_t_r;
            reg [17:0] newton_term_r;
            reg [17:0] delay_2_r [0:4];
            wire [35:0] unused_newton_second_w;
            wire [0:0] unused_newton_second_sign_w;
            wire [9:0] unused_newton_second_exponent_w;
            wire [19:0] unused_newton_r1_sum_w;
            assign unused_newton_r1_sum_w = {1'b0, unused_newton_second_w[35:17]}
                + {19'b0, unused_newton_second_w[16]};
            reg [17:0] newton_r1_r;
            wire [9:0] q_normal_exponent_w;
            assign q_normal_exponent_w = unused_q_w[28:19];
            wire [9:0] delay_3_w;
            assign delay_3_w = unused_delay_12_data_w[0+lane*10 +: 10];
            assign delay_12_input_w[0+lane*10 +: 10] = q_normal_exponent_w;
            reg [17:0] inverse_mantissa_r;
            reg [9:0] inverse_exponent_r;
            reg [28:0] inverse_r;
            wire [28:0] delay_4_w;
            assign delay_4_w = unused_delay_14_data_w[0+lane*29 +: 29];
            assign delay_14_input_w[0+lane*29 +: 29] = uq_w;
            wire [35:0] u_multiply_magnitude_w;
            wire [0:0] u_multiply_sign_w;
            wire [9:0] u_multiply_exponent_w;
            wire [28:0] u_w;
            wire [28:0] delay_5_w;
            assign delay_5_w = unused_delay_14_data_w[116+lane*29 +: 29];
            assign delay_14_input_w[116+lane*29 +: 29] = vq_w;
            wire [35:0] v_multiply_magnitude_w;
            wire [0:0] v_multiply_sign_w;
            wire [9:0] v_multiply_exponent_w;
            wire [28:0] v_w;
            wire [95:0] unused_u_coordinate_magnitude_w;
            wire [0:0] u_coordinate_sign_w;
            assign u_coordinate_sign_w = u_w[18];
            wire [0:0] delay_6_w;
            assign delay_6_w = unused_delay_9_data_w[0+lane*1 +: 1];
            assign delay_9_input_w[0+lane*1 +: 1] = u_coordinate_sign_w;
            wire [31:0] u_coordinate_w;
            wire [31:0] delay_7_w;
            assign delay_7_w = unused_delay_53_data_w[0+lane*32 +: 32];
            assign delay_53_input_w[0+lane*32 +: 32] = u_coordinate_w;
            wire [95:0] unused_v_coordinate_magnitude_w;
            wire [0:0] v_coordinate_sign_w;
            assign v_coordinate_sign_w = v_w[18];
            wire [0:0] delay_8_w;
            assign delay_8_w = unused_delay_9_data_w[4+lane*1 +: 1];
            assign delay_9_input_w[4+lane*1 +: 1] = v_coordinate_sign_w;
            wire [31:0] v_coordinate_w;
            wire [31:0] delay_9_w;
            assign delay_9_w = unused_delay_53_data_w[128+lane*32 +: 32];
            assign delay_53_input_w[128+lane*32 +: 32] = v_coordinate_w;
            wire [28:0] delay_10_w;
            assign delay_10_w = unused_delay_41_data_w[0 +: 29];
            wire [35:0] gradient_multiply_0_magnitude_w;
            wire [0:0] gradient_multiply_0_sign_w;
            wire [9:0] gradient_multiply_0_exponent_w;
            wire [28:0] gradient_0_w;
            wire [28:0] delay_11_w;
            assign delay_11_w = unused_delay_54_data_w[0 +: 29];
            wire [28:0] delta_0_w;
            wire [28:0] delay_12_w;
            assign delay_12_w = unused_delay_51_data_w[0+lane*29 +: 29];
            assign delay_51_input_w[0+lane*29 +: 29] = inverse_r;
            wire [35:0] derivative_multiply_0_magnitude_w;
            wire [0:0] derivative_multiply_0_sign_w;
            wire [9:0] derivative_multiply_0_exponent_w;
            wire [28:0] unused_derivative_0_w;
            wire [95:0] span_0_w;
            wire [28:0] delay_13_w;
            assign delay_13_w = unused_delay_41_data_w[0 +: 29];
            wire [35:0] gradient_multiply_1_magnitude_w;
            wire [0:0] gradient_multiply_1_sign_w;
            wire [9:0] gradient_multiply_1_exponent_w;
            wire [28:0] gradient_1_w;
            wire [28:0] delay_14_w;
            assign delay_14_w = unused_delay_54_data_w[29 +: 29];
            wire [28:0] delta_1_w;
            wire [28:0] delay_15_w;
            assign delay_15_w = unused_delay_51_data_w[lane*29 +: 29];
            wire [35:0] derivative_multiply_1_magnitude_w;
            wire [0:0] derivative_multiply_1_sign_w;
            wire [9:0] derivative_multiply_1_exponent_w;
            wire [28:0] unused_derivative_1_w;
            wire [95:0] span_1_w;
            wire [28:0] delay_16_w;
            assign delay_16_w = unused_delay_41_data_w[29 +: 29];
            wire [35:0] gradient_multiply_2_magnitude_w;
            wire [0:0] gradient_multiply_2_sign_w;
            wire [9:0] gradient_multiply_2_exponent_w;
            wire [28:0] gradient_2_w;
            wire [28:0] delay_17_w;
            assign delay_17_w = unused_delay_54_data_w[58 +: 29];
            wire [28:0] delta_2_w;
            wire [28:0] delay_18_w;
            assign delay_18_w = unused_delay_51_data_w[lane*29 +: 29];
            wire [35:0] derivative_multiply_2_magnitude_w;
            wire [0:0] derivative_multiply_2_sign_w;
            wire [9:0] derivative_multiply_2_exponent_w;
            wire [28:0] unused_derivative_2_w;
            wire [95:0] span_2_w;
            wire [28:0] delay_19_w;
            assign delay_19_w = unused_delay_41_data_w[29 +: 29];
            wire [35:0] gradient_multiply_3_magnitude_w;
            wire [0:0] gradient_multiply_3_sign_w;
            wire [9:0] gradient_multiply_3_exponent_w;
            wire [28:0] gradient_3_w;
            wire [28:0] delay_20_w;
            assign delay_20_w = unused_delay_54_data_w[87 +: 29];
            wire [28:0] delta_3_w;
            wire [28:0] delay_21_w;
            assign delay_21_w = unused_delay_51_data_w[lane*29 +: 29];
            wire [35:0] derivative_multiply_3_magnitude_w;
            wire [0:0] derivative_multiply_3_sign_w;
            wire [9:0] derivative_multiply_3_exponent_w;
            wire [28:0] unused_derivative_3_w;
            wire [95:0] span_3_w;
            wire [95:0] span_x_w;
            wire [95:0] span_y_w;
            wire [95:0] span_w;
            wire [69:0] unused_depth_raw_w;
            assign unused_depth_raw_w = plane_w[0 +: 70];
            reg [16:0] unused_depth_rounded_r;
            reg [0:0] depth_overflow_r;
            reg [0:0] depth_negative_r;
            reg [15:0] depth_clamped_r;
            wire [15:0] delay_22_w;
            assign delay_22_w = unused_delay_103_data_w[0+lane*16 +: 16];
            assign delay_103_input_w[0+lane*16 +: 16] = depth_clamped_r;
            wire [15:0] final_depth_w;
            assign final_depth_w = delay_22_w;
            wire [69:0] unused_red_raw_w;
            assign unused_red_raw_w = plane_w[280 +: 70];
            reg [8:0] unused_red_rounded_r;
            reg [0:0] red_overflow_r;
            reg [0:0] red_negative_r;
            reg [7:0] red_clamped_r;
            wire [7:0] delay_23_w;
            assign delay_23_w = unused_delay_103_data_w[64+lane*8 +: 8];
            assign delay_103_input_w[64+lane*8 +: 8] = red_clamped_r;
            wire [7:0] final_red_w;
            assign final_red_w = delay_23_w;
            wire [69:0] unused_green_raw_w;
            assign unused_green_raw_w = plane_w[350 +: 70];
            reg [8:0] unused_green_rounded_r;
            reg [0:0] green_overflow_r;
            reg [0:0] green_negative_r;
            reg [7:0] green_clamped_r;
            wire [7:0] delay_24_w;
            assign delay_24_w = unused_delay_103_data_w[96+lane*8 +: 8];
            assign delay_103_input_w[96+lane*8 +: 8] = green_clamped_r;
            wire [7:0] final_green_w;
            assign final_green_w = delay_24_w;
            wire [69:0] unused_blue_raw_w;
            assign unused_blue_raw_w = plane_w[420 +: 70];
            reg [8:0] unused_blue_rounded_r;
            reg [0:0] blue_overflow_r;
            reg [0:0] blue_negative_r;
            reg [7:0] blue_clamped_r;
            wire [7:0] delay_25_w;
            assign delay_25_w = unused_delay_103_data_w[128+lane*8 +: 8];
            assign delay_103_input_w[128+lane*8 +: 8] = blue_clamped_r;
            wire [7:0] final_blue_w;
            assign final_blue_w = delay_25_w;
            wire [31:0] delay_26_w;
            assign delay_26_w = unused_delay_105_data_w[0+lane*32 +: 32];
            assign delay_105_input_w[0+lane*32 +: 32] = plane_w[170 +: 32];
            wire [31:0] bypass_u_w;
            assign bypass_u_w = delay_26_w;
            wire [31:0] delay_27_w;
            assign delay_27_w = unused_delay_105_data_w[128+lane*32 +: 32];
            assign delay_105_input_w[128+lane*32 +: 32] = plane_w[240 +: 32];
            wire [31:0] bypass_v_w;
            assign bypass_v_w = delay_27_w;
            edrv32_gpu_perspective_absolute u_q_absolute (
                .clk_i(clk_i),
                .en_i(advance_w),
                .value_i(plane_w[70 +: 70]),
                .exponent_i(input_h_r[input_read_r][10 +: 10] - 10'd30),
                .magnitude_o(q_absolute_w),
                .sign_o(q_sign_w),
                .exponent_o(q_exponent_w)
            );
            edrv32_gpu_perspective_normal u_q (
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
                .value_i(plane_w[140 +: 70]),
                .exponent_i(input_h_r[input_read_r][20 +: 10] - 10'd38),
                .magnitude_o(uq_absolute_w),
                .sign_o(uq_sign_w),
                .exponent_o(uq_exponent_w)
            );
            edrv32_gpu_perspective_normal u_uq (
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
                .value_i(plane_w[210 +: 70]),
                .exponent_i(input_h_r[input_read_r][30 +: 10] - 10'd38),
                .magnitude_o(vq_absolute_w),
                .sign_o(vq_sign_w),
                .exponent_o(vq_exponent_w)
            );
            edrv32_gpu_perspective_normal u_vq (
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
                .a_i(delay_1_r[2]),
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
                .a_i(delay_2_r[4]),
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
            edrv32_gpu_perspective_normal u_u (
                .clk_i(clk_i),
                .en_i(advance_w),
                .magnitude_i({34'b0, u_multiply_magnitude_w}),
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
            edrv32_gpu_perspective_normal u_v (
                .clk_i(clk_i),
                .en_i(advance_w),
                .magnitude_i({34'b0, v_multiply_magnitude_w}),
                .sign_i(v_multiply_sign_w),
                .exponent_i(v_multiply_exponent_w),
                .normal_o(v_w)
            );
            edrv32_gpu_perspective_scale u_u_coordinate_magnitude (
                .clk_i(clk_i),
                .en_i(advance_w),
                .delay_scale_wr_data_o(delay_8_input_w[lane*30+0 +: 5]),
                .delay_scale_rd_data_i(unused_delay_8_data_w[lane*30+0 +: 5]),
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
            edrv32_gpu_perspective_scale u_v_coordinate_magnitude (
                .clk_i(clk_i),
                .en_i(advance_w),
                .delay_scale_wr_data_o(delay_8_input_w[lane*30+5 +: 5]),
                .delay_scale_rd_data_i(unused_delay_8_data_w[lane*30+5 +: 5]),
                .magnitude_i(v_w[17:0]),
                .exponent_i(v_w[28:19] + 10'd8),
                .magnitude_o(unused_v_coordinate_magnitude_w)
            );
            edrv32_gpu_perspective_sign u_v_coordinate (
                .clk_i(clk_i),
                .en_i(advance_w),
                .magnitude_i(unused_v_coordinate_magnitude_w[31:0]),
                .sign_i(delay_8_w),
                .value_o(v_coordinate_w)
            );
            edrv32_gpu_perspective_multiply u_gradient_multiply_0 (
                .clk_i(clk_i),
                .en_i(advance_w),
                .a_i(u_w[17:0]),
                .b_i(delay_10_w[17:0]),
                .sign_i(u_w[18] ^ delay_10_w[18]),
                .exponent_i(u_w[28:19] + delay_10_w[28:19]),
                .magnitude_o(gradient_multiply_0_magnitude_w),
                .sign_o(gradient_multiply_0_sign_w),
                .exponent_o(gradient_multiply_0_exponent_w)
            );
            edrv32_gpu_perspective_normal u_gradient_0 (
                .clk_i(clk_i),
                .en_i(advance_w),
                .magnitude_i({34'b0, gradient_multiply_0_magnitude_w}),
                .sign_i(gradient_multiply_0_sign_w),
                .exponent_i(gradient_multiply_0_exponent_w),
                .normal_o(gradient_0_w)
            );
            edrv32_gpu_perspective_subtract u_delta_0 (
                .clk_i(clk_i),
                .en_i(advance_w),
                .delay_bypass_wr_data_o(delay_25_input_w[lane*116+0 +: 29]),
                .delay_bypass_rd_data_i(unused_delay_25_data_w[lane*116+0 +: 29]),
                .delay_exponent_wr_data_o(delay_14_input_w[232+lane*40+0 +: 10]),
                .delay_exponent_rd_data_i(unused_delay_14_data_w[232+lane*40+0 +: 10]),
                .a_i(delay_11_w),
                .b_i(gradient_0_w),
                .normal_o(delta_0_w)
            );
            edrv32_gpu_perspective_multiply u_derivative_multiply_0 (
                .clk_i(clk_i),
                .en_i(advance_w),
                .a_i(delta_0_w[17:0]),
                .b_i(delay_12_w[17:0]),
                .sign_i(delta_0_w[18] ^ delay_12_w[18]),
                .exponent_i(delta_0_w[28:19] + delay_12_w[28:19]),
                .magnitude_o(derivative_multiply_0_magnitude_w),
                .sign_o(derivative_multiply_0_sign_w),
                .exponent_o(derivative_multiply_0_exponent_w)
            );
            edrv32_gpu_perspective_normal u_derivative_0 (
                .clk_i(clk_i),
                .en_i(advance_w),
                .magnitude_i({34'b0, derivative_multiply_0_magnitude_w}),
                .sign_i(derivative_multiply_0_sign_w),
                .exponent_i(derivative_multiply_0_exponent_w),
                .normal_o(unused_derivative_0_w)
            );
            edrv32_gpu_perspective_scale u_span_0 (
                .clk_i(clk_i),
                .en_i(advance_w),
                .delay_scale_wr_data_o(delay_8_input_w[lane*30+10 +: 5]),
                .delay_scale_rd_data_i(unused_delay_8_data_w[lane*30+10 +: 5]),
                .magnitude_i(unused_derivative_0_w[17:0]),
                .exponent_i(unused_derivative_0_w[28:19] + 10'd16),
                .magnitude_o(span_0_w)
            );
            edrv32_gpu_perspective_multiply u_gradient_multiply_1 (
                .clk_i(clk_i),
                .en_i(advance_w),
                .a_i(v_w[17:0]),
                .b_i(delay_13_w[17:0]),
                .sign_i(v_w[18] ^ delay_13_w[18]),
                .exponent_i(v_w[28:19] + delay_13_w[28:19]),
                .magnitude_o(gradient_multiply_1_magnitude_w),
                .sign_o(gradient_multiply_1_sign_w),
                .exponent_o(gradient_multiply_1_exponent_w)
            );
            edrv32_gpu_perspective_normal u_gradient_1 (
                .clk_i(clk_i),
                .en_i(advance_w),
                .magnitude_i({34'b0, gradient_multiply_1_magnitude_w}),
                .sign_i(gradient_multiply_1_sign_w),
                .exponent_i(gradient_multiply_1_exponent_w),
                .normal_o(gradient_1_w)
            );
            edrv32_gpu_perspective_subtract u_delta_1 (
                .clk_i(clk_i),
                .en_i(advance_w),
                .delay_bypass_wr_data_o(delay_25_input_w[lane*116+29 +: 29]),
                .delay_bypass_rd_data_i(unused_delay_25_data_w[lane*116+29 +: 29]),
                .delay_exponent_wr_data_o(delay_14_input_w[232+lane*40+10 +: 10]),
                .delay_exponent_rd_data_i(unused_delay_14_data_w[232+lane*40+10 +: 10]),
                .a_i(delay_14_w),
                .b_i(gradient_1_w),
                .normal_o(delta_1_w)
            );
            edrv32_gpu_perspective_multiply u_derivative_multiply_1 (
                .clk_i(clk_i),
                .en_i(advance_w),
                .a_i(delta_1_w[17:0]),
                .b_i(delay_15_w[17:0]),
                .sign_i(delta_1_w[18] ^ delay_15_w[18]),
                .exponent_i(delta_1_w[28:19] + delay_15_w[28:19]),
                .magnitude_o(derivative_multiply_1_magnitude_w),
                .sign_o(derivative_multiply_1_sign_w),
                .exponent_o(derivative_multiply_1_exponent_w)
            );
            edrv32_gpu_perspective_normal u_derivative_1 (
                .clk_i(clk_i),
                .en_i(advance_w),
                .magnitude_i({34'b0, derivative_multiply_1_magnitude_w}),
                .sign_i(derivative_multiply_1_sign_w),
                .exponent_i(derivative_multiply_1_exponent_w),
                .normal_o(unused_derivative_1_w)
            );
            edrv32_gpu_perspective_scale u_span_1 (
                .clk_i(clk_i),
                .en_i(advance_w),
                .delay_scale_wr_data_o(delay_8_input_w[lane*30+15 +: 5]),
                .delay_scale_rd_data_i(unused_delay_8_data_w[lane*30+15 +: 5]),
                .magnitude_i(unused_derivative_1_w[17:0]),
                .exponent_i(unused_derivative_1_w[28:19] + 10'd16),
                .magnitude_o(span_1_w)
            );
            edrv32_gpu_perspective_multiply u_gradient_multiply_2 (
                .clk_i(clk_i),
                .en_i(advance_w),
                .a_i(u_w[17:0]),
                .b_i(delay_16_w[17:0]),
                .sign_i(u_w[18] ^ delay_16_w[18]),
                .exponent_i(u_w[28:19] + delay_16_w[28:19]),
                .magnitude_o(gradient_multiply_2_magnitude_w),
                .sign_o(gradient_multiply_2_sign_w),
                .exponent_o(gradient_multiply_2_exponent_w)
            );
            edrv32_gpu_perspective_normal u_gradient_2 (
                .clk_i(clk_i),
                .en_i(advance_w),
                .magnitude_i({34'b0, gradient_multiply_2_magnitude_w}),
                .sign_i(gradient_multiply_2_sign_w),
                .exponent_i(gradient_multiply_2_exponent_w),
                .normal_o(gradient_2_w)
            );
            edrv32_gpu_perspective_subtract u_delta_2 (
                .clk_i(clk_i),
                .en_i(advance_w),
                .delay_bypass_wr_data_o(delay_25_input_w[lane*116+58 +: 29]),
                .delay_bypass_rd_data_i(unused_delay_25_data_w[lane*116+58 +: 29]),
                .delay_exponent_wr_data_o(delay_14_input_w[232+lane*40+20 +: 10]),
                .delay_exponent_rd_data_i(unused_delay_14_data_w[232+lane*40+20 +: 10]),
                .a_i(delay_17_w),
                .b_i(gradient_2_w),
                .normal_o(delta_2_w)
            );
            edrv32_gpu_perspective_multiply u_derivative_multiply_2 (
                .clk_i(clk_i),
                .en_i(advance_w),
                .a_i(delta_2_w[17:0]),
                .b_i(delay_18_w[17:0]),
                .sign_i(delta_2_w[18] ^ delay_18_w[18]),
                .exponent_i(delta_2_w[28:19] + delay_18_w[28:19]),
                .magnitude_o(derivative_multiply_2_magnitude_w),
                .sign_o(derivative_multiply_2_sign_w),
                .exponent_o(derivative_multiply_2_exponent_w)
            );
            edrv32_gpu_perspective_normal u_derivative_2 (
                .clk_i(clk_i),
                .en_i(advance_w),
                .magnitude_i({34'b0, derivative_multiply_2_magnitude_w}),
                .sign_i(derivative_multiply_2_sign_w),
                .exponent_i(derivative_multiply_2_exponent_w),
                .normal_o(unused_derivative_2_w)
            );
            edrv32_gpu_perspective_scale u_span_2 (
                .clk_i(clk_i),
                .en_i(advance_w),
                .delay_scale_wr_data_o(delay_8_input_w[lane*30+20 +: 5]),
                .delay_scale_rd_data_i(unused_delay_8_data_w[lane*30+20 +: 5]),
                .magnitude_i(unused_derivative_2_w[17:0]),
                .exponent_i(unused_derivative_2_w[28:19] + 10'd16),
                .magnitude_o(span_2_w)
            );
            edrv32_gpu_perspective_multiply u_gradient_multiply_3 (
                .clk_i(clk_i),
                .en_i(advance_w),
                .a_i(v_w[17:0]),
                .b_i(delay_19_w[17:0]),
                .sign_i(v_w[18] ^ delay_19_w[18]),
                .exponent_i(v_w[28:19] + delay_19_w[28:19]),
                .magnitude_o(gradient_multiply_3_magnitude_w),
                .sign_o(gradient_multiply_3_sign_w),
                .exponent_o(gradient_multiply_3_exponent_w)
            );
            edrv32_gpu_perspective_normal u_gradient_3 (
                .clk_i(clk_i),
                .en_i(advance_w),
                .magnitude_i({34'b0, gradient_multiply_3_magnitude_w}),
                .sign_i(gradient_multiply_3_sign_w),
                .exponent_i(gradient_multiply_3_exponent_w),
                .normal_o(gradient_3_w)
            );
            edrv32_gpu_perspective_subtract u_delta_3 (
                .clk_i(clk_i),
                .en_i(advance_w),
                .delay_bypass_wr_data_o(delay_25_input_w[lane*116+87 +: 29]),
                .delay_bypass_rd_data_i(unused_delay_25_data_w[lane*116+87 +: 29]),
                .delay_exponent_wr_data_o(delay_14_input_w[232+lane*40+30 +: 10]),
                .delay_exponent_rd_data_i(unused_delay_14_data_w[232+lane*40+30 +: 10]),
                .a_i(delay_20_w),
                .b_i(gradient_3_w),
                .normal_o(delta_3_w)
            );
            edrv32_gpu_perspective_multiply u_derivative_multiply_3 (
                .clk_i(clk_i),
                .en_i(advance_w),
                .a_i(delta_3_w[17:0]),
                .b_i(delay_21_w[17:0]),
                .sign_i(delta_3_w[18] ^ delay_21_w[18]),
                .exponent_i(delta_3_w[28:19] + delay_21_w[28:19]),
                .magnitude_o(derivative_multiply_3_magnitude_w),
                .sign_o(derivative_multiply_3_sign_w),
                .exponent_o(derivative_multiply_3_exponent_w)
            );
            edrv32_gpu_perspective_normal u_derivative_3 (
                .clk_i(clk_i),
                .en_i(advance_w),
                .magnitude_i({34'b0, derivative_multiply_3_magnitude_w}),
                .sign_i(derivative_multiply_3_sign_w),
                .exponent_i(derivative_multiply_3_exponent_w),
                .normal_o(unused_derivative_3_w)
            );
            edrv32_gpu_perspective_scale u_span_3 (
                .clk_i(clk_i),
                .en_i(advance_w),
                .delay_scale_wr_data_o(delay_8_input_w[lane*30+25 +: 5]),
                .delay_scale_rd_data_i(unused_delay_8_data_w[lane*30+25 +: 5]),
                .magnitude_i(unused_derivative_3_w[17:0]),
                .exponent_i(unused_derivative_3_w[28:19] + 10'd16),
                .magnitude_o(span_3_w)
            );
            edrv32_gpu_perspective_maximum u_span_x (
                .clk_i(clk_i),
                .en_i(advance_w),
                .a_i(span_0_w),
                .b_i(span_1_w),
                .value_o(span_x_w)
            );
            edrv32_gpu_perspective_maximum u_span_y (
                .clk_i(clk_i),
                .en_i(advance_w),
                .a_i(span_2_w),
                .b_i(span_3_w),
                .value_o(span_y_w)
            );
            edrv32_gpu_perspective_maximum u_span (
                .clk_i(clk_i),
                .en_i(advance_w),
                .a_i(span_x_w),
                .b_i(span_y_w),
                .value_o(span_w)
            );
            always @(posedge clk_i) begin
                if (advance_w) begin
                    seed_address_r <= unused_q_w[16:7];
                    seed_r <= seed_rom_w;
                    delay_1_r[0] <= q_mantissa_w;
                    delay_1_r[1] <= delay_1_r[0];
                    delay_1_r[2] <= delay_1_r[1];
                    newton_t_r <= unused_newton_t_sum_w[17:0];
                    newton_term_r <= -newton_t_r;
                    delay_2_r[0] <= seed_r;
                    delay_2_r[1] <= delay_2_r[0];
                    delay_2_r[2] <= delay_2_r[1];
                    delay_2_r[3] <= delay_2_r[2];
                    delay_2_r[4] <= delay_2_r[3];
                    newton_r1_r <= unused_newton_r1_sum_w[17:0];
                    inverse_mantissa_r <= newton_r1_r[17] ? newton_r1_r : {newton_r1_r[16:0], 1'b0};
                    inverse_exponent_r <= -10'd34 - delay_3_w - {9'b0, !newton_r1_r[17]};
                    inverse_r <= inverse_mantissa_r == 0 ? 29'b0
                        : {inverse_exponent_r, 1'b0, inverse_mantissa_r};
                    unused_depth_rounded_r <= {1'b0, unused_depth_raw_w[16 +: 16]}
                        + {16'b0, unused_depth_raw_w[15]};
                    depth_overflow_r <= unused_depth_raw_w[69:32] != 0;
                    depth_negative_r <= unused_depth_raw_w[69];
                    depth_clamped_r <= depth_negative_r ? 16'b0 : (depth_overflow_r
                        || unused_depth_rounded_r[16]) ? 16'd65535 : unused_depth_rounded_r[15:0];
                    unused_red_rounded_r <= {1'b0, unused_red_raw_w[24 +: 8]}
                        + {8'b0, unused_red_raw_w[23]};
                    red_overflow_r <= unused_red_raw_w[69:32] != 0;
                    red_negative_r <= unused_red_raw_w[69];
                    red_clamped_r <= red_negative_r ? 8'b0 : (red_overflow_r
                        || unused_red_rounded_r[8]) ? 8'd255 : unused_red_rounded_r[7:0];
                    unused_green_rounded_r <= {1'b0, unused_green_raw_w[24 +: 8]}
                        + {8'b0, unused_green_raw_w[23]};
                    green_overflow_r <= unused_green_raw_w[69:32] != 0;
                    green_negative_r <= unused_green_raw_w[69];
                    green_clamped_r <= green_negative_r ? 8'b0 : (green_overflow_r
                        || unused_green_rounded_r[8]) ? 8'd255 : unused_green_rounded_r[7:0];
                    unused_blue_rounded_r <= {1'b0, unused_blue_raw_w[24 +: 8]}
                        + {8'b0, unused_blue_raw_w[23]};
                    blue_overflow_r <= unused_blue_raw_w[69:32] != 0;
                    blue_negative_r <= unused_blue_raw_w[69];
                    blue_clamped_r <= blue_negative_r ? 8'b0 : (blue_overflow_r
                        || unused_blue_rounded_r[8]) ? 8'd255 : unused_blue_rounded_r[7:0];
                end
            end
            assign output_u_w[lane*32 +: 32] = pipe_quad_w ?
                        bypass_u_w : delay_7_w;
            assign output_v_w[lane*32 +: 32] = pipe_quad_w ?
                        bypass_v_w : delay_9_w;
            assign output_span_w[lane*96 +: 96] = pipe_quad_w ?
                        96'b0 : span_w;
            assign output_depth_w[lane*16 +: 16] = final_depth_w;
            assign output_color_w[lane*24 +: 24] =
                {final_blue_w, final_green_w, final_red_w};
        end
    endgenerate
endmodule
