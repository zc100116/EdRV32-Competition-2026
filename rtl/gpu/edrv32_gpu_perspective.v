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

    // Both boundary queues have two slots; readiness never crosses the unit combinationally.
    reg [1:0] input_count_r;
    reg input_read_r;
    reg input_write_r;
    reg [1:0] output_count_r;
    reg output_read_r;
    reg output_write_r;
    reg [104:0] valid_r;
    wire advance_w;
    wire input_push_w;
    wire input_pop_w;
    wire output_push_w;
    wire output_pop_w;

    assign advance_w = output_count_r < 2;
    assign fragment_ready_o = input_count_r < 2;
    assign sample_valid_o = (output_count_r != 0) && !stop_i;
    assign input_push_w = fragment_valid_i && fragment_ready_o && !stop_i;
    assign input_pop_w = (input_count_r != 0) && advance_w;
    assign output_push_w = valid_r[104] && advance_w && !stop_i;
    assign output_pop_w = sample_valid_o && sample_ready_i;
    reg [15:0] input_x_r [0:1];
    reg [15:0] input_y_r [0:1];
    reg [3:0] input_mask_r [0:1];
    reg [0:0] input_quad_r [0:1];
    reg [69:0] input_h_r [0:1];
    reg [173:0] input_gradient_r [0:1];
    reg [3:0] input_palette_r [0:1];
    reg [7:0] input_alpha_r [0:1];
    reg [15:0] output_x_r [0:1];
    assign sample_x_o = output_x_r[output_read_r];
    reg [15:0] output_y_r [0:1];
    assign sample_y_o = output_y_r[output_read_r];
    reg [3:0] output_mask_r [0:1];
    assign sample_mask_o = output_mask_r[output_read_r];
    reg [0:0] output_quad_r [0:1];
    assign sample_quad_o = output_quad_r[output_read_r];
    reg [3:0] output_palette_r [0:1];
    assign sample_palette_o = output_palette_r[output_read_r];
    reg [7:0] output_alpha_r [0:1];
    assign sample_alpha_o = output_alpha_r[output_read_r];
    reg [48:0] pipe_metadata_r [0:104];
    wire [15:0] pipe_x_w;
    assign pipe_x_w = pipe_metadata_r[104][0 +: 16];
    wire [15:0] pipe_y_w;
    assign pipe_y_w = pipe_metadata_r[104][16 +: 16];
    wire [3:0] pipe_mask_w;
    assign pipe_mask_w = pipe_metadata_r[104][32 +: 4];
    wire [0:0] pipe_quad_w;
    assign pipe_quad_w = pipe_metadata_r[104][36 +: 1];
    wire [3:0] pipe_palette_w;
    assign pipe_palette_w = pipe_metadata_r[104][37 +: 4];
    wire [7:0] pipe_alpha_w;
    assign pipe_alpha_w = pipe_metadata_r[104][41 +: 8];

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            input_count_r <= 0;
            input_read_r <= 0;
            input_write_r <= 0;
            output_count_r <= 0;
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
                input_read_r <= input_write_r;
                output_read_r <= output_write_r;
                valid_r <= 0;
            end else begin
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
                    output_write_r <= !output_write_r;
                end
                if (output_pop_w) begin
                    output_read_r <= !output_read_r;
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
        if (output_push_w) begin
            output_x_r[output_write_r] <= pipe_x_w;
            output_y_r[output_write_r] <= pipe_y_w;
            output_mask_r[output_write_r] <= pipe_mask_w;
            output_quad_r[output_write_r] <= pipe_quad_w;
            output_palette_r[output_write_r] <= pipe_palette_w;
            output_alpha_r[output_write_r] <= pipe_alpha_w;
        end
    end

    // One 105-stage, 49-bit metadata chain; fields are below the 256-bit record limit.
    // A single writer shifts whole elements without reset; advance stalls every stage.
    // Explicit constant stages also avoid simulator loop-unroll limits.
    always @(posedge clk_i) begin
        if (advance_w) begin
            pipe_metadata_r[0] <= {input_alpha_r[input_read_r], input_palette_r[input_read_r],
                input_quad_r[input_read_r], input_mask_r[input_read_r],
                input_y_r[input_read_r], input_x_r[input_read_r]};
            pipe_metadata_r[1] <= pipe_metadata_r[0];
            pipe_metadata_r[2] <= pipe_metadata_r[1];
            pipe_metadata_r[3] <= pipe_metadata_r[2];
            pipe_metadata_r[4] <= pipe_metadata_r[3];
            pipe_metadata_r[5] <= pipe_metadata_r[4];
            pipe_metadata_r[6] <= pipe_metadata_r[5];
            pipe_metadata_r[7] <= pipe_metadata_r[6];
            pipe_metadata_r[8] <= pipe_metadata_r[7];
            pipe_metadata_r[9] <= pipe_metadata_r[8];
            pipe_metadata_r[10] <= pipe_metadata_r[9];
            pipe_metadata_r[11] <= pipe_metadata_r[10];
            pipe_metadata_r[12] <= pipe_metadata_r[11];
            pipe_metadata_r[13] <= pipe_metadata_r[12];
            pipe_metadata_r[14] <= pipe_metadata_r[13];
            pipe_metadata_r[15] <= pipe_metadata_r[14];
            pipe_metadata_r[16] <= pipe_metadata_r[15];
            pipe_metadata_r[17] <= pipe_metadata_r[16];
            pipe_metadata_r[18] <= pipe_metadata_r[17];
            pipe_metadata_r[19] <= pipe_metadata_r[18];
            pipe_metadata_r[20] <= pipe_metadata_r[19];
            pipe_metadata_r[21] <= pipe_metadata_r[20];
            pipe_metadata_r[22] <= pipe_metadata_r[21];
            pipe_metadata_r[23] <= pipe_metadata_r[22];
            pipe_metadata_r[24] <= pipe_metadata_r[23];
            pipe_metadata_r[25] <= pipe_metadata_r[24];
            pipe_metadata_r[26] <= pipe_metadata_r[25];
            pipe_metadata_r[27] <= pipe_metadata_r[26];
            pipe_metadata_r[28] <= pipe_metadata_r[27];
            pipe_metadata_r[29] <= pipe_metadata_r[28];
            pipe_metadata_r[30] <= pipe_metadata_r[29];
            pipe_metadata_r[31] <= pipe_metadata_r[30];
            pipe_metadata_r[32] <= pipe_metadata_r[31];
            pipe_metadata_r[33] <= pipe_metadata_r[32];
            pipe_metadata_r[34] <= pipe_metadata_r[33];
            pipe_metadata_r[35] <= pipe_metadata_r[34];
            pipe_metadata_r[36] <= pipe_metadata_r[35];
            pipe_metadata_r[37] <= pipe_metadata_r[36];
            pipe_metadata_r[38] <= pipe_metadata_r[37];
            pipe_metadata_r[39] <= pipe_metadata_r[38];
            pipe_metadata_r[40] <= pipe_metadata_r[39];
            pipe_metadata_r[41] <= pipe_metadata_r[40];
            pipe_metadata_r[42] <= pipe_metadata_r[41];
            pipe_metadata_r[43] <= pipe_metadata_r[42];
            pipe_metadata_r[44] <= pipe_metadata_r[43];
            pipe_metadata_r[45] <= pipe_metadata_r[44];
            pipe_metadata_r[46] <= pipe_metadata_r[45];
            pipe_metadata_r[47] <= pipe_metadata_r[46];
            pipe_metadata_r[48] <= pipe_metadata_r[47];
            pipe_metadata_r[49] <= pipe_metadata_r[48];
            pipe_metadata_r[50] <= pipe_metadata_r[49];
            pipe_metadata_r[51] <= pipe_metadata_r[50];
            pipe_metadata_r[52] <= pipe_metadata_r[51];
            pipe_metadata_r[53] <= pipe_metadata_r[52];
            pipe_metadata_r[54] <= pipe_metadata_r[53];
            pipe_metadata_r[55] <= pipe_metadata_r[54];
            pipe_metadata_r[56] <= pipe_metadata_r[55];
            pipe_metadata_r[57] <= pipe_metadata_r[56];
            pipe_metadata_r[58] <= pipe_metadata_r[57];
            pipe_metadata_r[59] <= pipe_metadata_r[58];
            pipe_metadata_r[60] <= pipe_metadata_r[59];
            pipe_metadata_r[61] <= pipe_metadata_r[60];
            pipe_metadata_r[62] <= pipe_metadata_r[61];
            pipe_metadata_r[63] <= pipe_metadata_r[62];
            pipe_metadata_r[64] <= pipe_metadata_r[63];
            pipe_metadata_r[65] <= pipe_metadata_r[64];
            pipe_metadata_r[66] <= pipe_metadata_r[65];
            pipe_metadata_r[67] <= pipe_metadata_r[66];
            pipe_metadata_r[68] <= pipe_metadata_r[67];
            pipe_metadata_r[69] <= pipe_metadata_r[68];
            pipe_metadata_r[70] <= pipe_metadata_r[69];
            pipe_metadata_r[71] <= pipe_metadata_r[70];
            pipe_metadata_r[72] <= pipe_metadata_r[71];
            pipe_metadata_r[73] <= pipe_metadata_r[72];
            pipe_metadata_r[74] <= pipe_metadata_r[73];
            pipe_metadata_r[75] <= pipe_metadata_r[74];
            pipe_metadata_r[76] <= pipe_metadata_r[75];
            pipe_metadata_r[77] <= pipe_metadata_r[76];
            pipe_metadata_r[78] <= pipe_metadata_r[77];
            pipe_metadata_r[79] <= pipe_metadata_r[78];
            pipe_metadata_r[80] <= pipe_metadata_r[79];
            pipe_metadata_r[81] <= pipe_metadata_r[80];
            pipe_metadata_r[82] <= pipe_metadata_r[81];
            pipe_metadata_r[83] <= pipe_metadata_r[82];
            pipe_metadata_r[84] <= pipe_metadata_r[83];
            pipe_metadata_r[85] <= pipe_metadata_r[84];
            pipe_metadata_r[86] <= pipe_metadata_r[85];
            pipe_metadata_r[87] <= pipe_metadata_r[86];
            pipe_metadata_r[88] <= pipe_metadata_r[87];
            pipe_metadata_r[89] <= pipe_metadata_r[88];
            pipe_metadata_r[90] <= pipe_metadata_r[89];
            pipe_metadata_r[91] <= pipe_metadata_r[90];
            pipe_metadata_r[92] <= pipe_metadata_r[91];
            pipe_metadata_r[93] <= pipe_metadata_r[92];
            pipe_metadata_r[94] <= pipe_metadata_r[93];
            pipe_metadata_r[95] <= pipe_metadata_r[94];
            pipe_metadata_r[96] <= pipe_metadata_r[95];
            pipe_metadata_r[97] <= pipe_metadata_r[96];
            pipe_metadata_r[98] <= pipe_metadata_r[97];
            pipe_metadata_r[99] <= pipe_metadata_r[98];
            pipe_metadata_r[100] <= pipe_metadata_r[99];
            pipe_metadata_r[101] <= pipe_metadata_r[100];
            pipe_metadata_r[102] <= pipe_metadata_r[101];
            pipe_metadata_r[103] <= pipe_metadata_r[102];
            pipe_metadata_r[104] <= pipe_metadata_r[103];
        end
    end
    // Four copies of the unchanged arithmetic pipeline below, one per pixel lane.
    // Each lane has 12 three-stage multipliers: Newton x2, UV x2, derivatives x8.
    // Their results retain the original 22/28/41/79/92/105-cycle alignment.
    genvar lane;
    generate
        for (lane = 0; lane < 4; lane = lane + 1) begin : g_lane
            // Four lanes, each owning seven 70-bit two-slot input field queues.
            // No queue array is shared between generated lanes or fields.
            wire [69:0] plane_w [0:6];
            genvar attribute;
            for (attribute = 0; attribute < 7; attribute = attribute + 1) begin : g_plane
                reg [69:0] input_plane_r [0:1];
                always @(posedge clk_i) begin
                    if (input_push_w) begin
                        input_plane_r[input_write_r] <=
                            fragment_plane_i[lane*490+attribute*70 +: 70];
                    end
                end
                assign plane_w[attribute] = input_plane_r[input_read_r];
            end

            // Five independent two-slot output fields per lane, written at stage 105.
            reg [31:0] output_u_r [0:1];
            assign sample_u_o[lane*32 +: 32] =
                output_u_r[output_read_r];
            reg [31:0] output_v_r [0:1];
            assign sample_v_o[lane*32 +: 32] =
                output_v_r[output_read_r];
            reg [95:0] output_span_r [0:1];
            assign sample_span_o[lane*96 +: 96] =
                output_span_r[output_read_r];
            reg [15:0] output_depth_r [0:1];
            assign sample_depth_o[lane*16 +: 16] =
                output_depth_r[output_read_r];
            reg [23:0] output_color_r [0:1];
            assign sample_color_o[lane*24 +: 24] =
                output_color_r[output_read_r];

            // Each lane owns 27 unreset, whole-element delay chains below.
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
            reg [9:0] delay_3_r [0:11];
            reg [17:0] inverse_mantissa_r;
            reg [9:0] inverse_exponent_r;
            reg [28:0] inverse_r;
            reg [28:0] delay_4_r [0:13];
            wire [35:0] u_multiply_magnitude_w;
            wire [0:0] u_multiply_sign_w;
            wire [9:0] u_multiply_exponent_w;
            wire [28:0] u_w;
            reg [28:0] delay_5_r [0:13];
            wire [35:0] v_multiply_magnitude_w;
            wire [0:0] v_multiply_sign_w;
            wire [9:0] v_multiply_exponent_w;
            wire [28:0] v_w;
            wire [95:0] unused_u_coordinate_magnitude_w;
            wire [0:0] u_coordinate_sign_w;
            assign u_coordinate_sign_w = u_w[18];
            reg [0:0] delay_6_r [0:8];
            wire [31:0] u_coordinate_w;
            reg [31:0] delay_7_r [0:52];
            wire [95:0] unused_v_coordinate_magnitude_w;
            wire [0:0] v_coordinate_sign_w;
            assign v_coordinate_sign_w = v_w[18];
            reg [0:0] delay_8_r [0:8];
            wire [31:0] v_coordinate_w;
            reg [31:0] delay_9_r [0:52];
            wire [28:0] dq_0_0_w;
            assign dq_0_0_w = input_gradient_r[input_read_r][0 +: 29];
            reg [28:0] delay_10_r [0:40];
            wire [35:0] gradient_multiply_0_magnitude_w;
            wire [0:0] gradient_multiply_0_sign_w;
            wire [9:0] gradient_multiply_0_exponent_w;
            wire [28:0] gradient_0_w;
            wire [28:0] guq_0_w;
            assign guq_0_w = input_gradient_r[input_read_r][29 +: 29];
            reg [28:0] delay_11_r [0:53];
            wire [28:0] delta_0_w;
            reg [28:0] delay_12_r [0:50];
            wire [35:0] derivative_multiply_0_magnitude_w;
            wire [0:0] derivative_multiply_0_sign_w;
            wire [9:0] derivative_multiply_0_exponent_w;
            wire [28:0] unused_derivative_0_w;
            wire [95:0] span_0_w;
            wire [28:0] dq_0_1_w;
            assign dq_0_1_w = input_gradient_r[input_read_r][0 +: 29];
            reg [28:0] delay_13_r [0:40];
            wire [35:0] gradient_multiply_1_magnitude_w;
            wire [0:0] gradient_multiply_1_sign_w;
            wire [9:0] gradient_multiply_1_exponent_w;
            wire [28:0] gradient_1_w;
            wire [28:0] guq_1_w;
            assign guq_1_w = input_gradient_r[input_read_r][58 +: 29];
            reg [28:0] delay_14_r [0:53];
            wire [28:0] delta_1_w;
            reg [28:0] delay_15_r [0:50];
            wire [35:0] derivative_multiply_1_magnitude_w;
            wire [0:0] derivative_multiply_1_sign_w;
            wire [9:0] derivative_multiply_1_exponent_w;
            wire [28:0] unused_derivative_1_w;
            wire [95:0] span_1_w;
            wire [28:0] dq_1_2_w;
            assign dq_1_2_w = input_gradient_r[input_read_r][87 +: 29];
            reg [28:0] delay_16_r [0:40];
            wire [35:0] gradient_multiply_2_magnitude_w;
            wire [0:0] gradient_multiply_2_sign_w;
            wire [9:0] gradient_multiply_2_exponent_w;
            wire [28:0] gradient_2_w;
            wire [28:0] guq_2_w;
            assign guq_2_w = input_gradient_r[input_read_r][116 +: 29];
            reg [28:0] delay_17_r [0:53];
            wire [28:0] delta_2_w;
            reg [28:0] delay_18_r [0:50];
            wire [35:0] derivative_multiply_2_magnitude_w;
            wire [0:0] derivative_multiply_2_sign_w;
            wire [9:0] derivative_multiply_2_exponent_w;
            wire [28:0] unused_derivative_2_w;
            wire [95:0] span_2_w;
            wire [28:0] dq_1_3_w;
            assign dq_1_3_w = input_gradient_r[input_read_r][87 +: 29];
            reg [28:0] delay_19_r [0:40];
            wire [35:0] gradient_multiply_3_magnitude_w;
            wire [0:0] gradient_multiply_3_sign_w;
            wire [9:0] gradient_multiply_3_exponent_w;
            wire [28:0] gradient_3_w;
            wire [28:0] guq_3_w;
            assign guq_3_w = input_gradient_r[input_read_r][145 +: 29];
            reg [28:0] delay_20_r [0:53];
            wire [28:0] delta_3_w;
            reg [28:0] delay_21_r [0:50];
            wire [35:0] derivative_multiply_3_magnitude_w;
            wire [0:0] derivative_multiply_3_sign_w;
            wire [9:0] derivative_multiply_3_exponent_w;
            wire [28:0] unused_derivative_3_w;
            wire [95:0] span_3_w;
            wire [95:0] span_x_w;
            wire [95:0] span_y_w;
            wire [95:0] span_w;
            wire [69:0] unused_depth_raw_w;
            assign unused_depth_raw_w = plane_w[0];
            reg [16:0] unused_depth_rounded_r;
            reg [0:0] depth_overflow_r;
            reg [0:0] depth_negative_r;
            reg [15:0] depth_clamped_r;
            reg [15:0] delay_22_r [0:102];
            wire [15:0] final_depth_w;
            assign final_depth_w = delay_22_r[102];
            wire [69:0] unused_red_raw_w;
            assign unused_red_raw_w = plane_w[4];
            reg [8:0] unused_red_rounded_r;
            reg [0:0] red_overflow_r;
            reg [0:0] red_negative_r;
            reg [7:0] red_clamped_r;
            reg [7:0] delay_23_r [0:102];
            wire [7:0] final_red_w;
            assign final_red_w = delay_23_r[102];
            wire [69:0] unused_green_raw_w;
            assign unused_green_raw_w = plane_w[5];
            reg [8:0] unused_green_rounded_r;
            reg [0:0] green_overflow_r;
            reg [0:0] green_negative_r;
            reg [7:0] green_clamped_r;
            reg [7:0] delay_24_r [0:102];
            wire [7:0] final_green_w;
            assign final_green_w = delay_24_r[102];
            wire [69:0] unused_blue_raw_w;
            assign unused_blue_raw_w = plane_w[6];
            reg [8:0] unused_blue_rounded_r;
            reg [0:0] blue_overflow_r;
            reg [0:0] blue_negative_r;
            reg [7:0] blue_clamped_r;
            reg [7:0] delay_25_r [0:102];
            wire [7:0] final_blue_w;
            assign final_blue_w = delay_25_r[102];
            reg [31:0] delay_26_r [0:104];
            wire [31:0] bypass_u_w;
            assign bypass_u_w = delay_26_r[104];
            reg [31:0] delay_27_r [0:104];
            wire [31:0] bypass_v_w;
            assign bypass_v_w = delay_27_r[104];
            edrv32_gpu_perspective_absolute u_q_absolute (
                .clk_i(clk_i),
                .en_i(advance_w),
                .value_i(plane_w[1]),
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
                .value_i(plane_w[2]),
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
                .value_i(plane_w[3]),
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
                .a_i(delay_4_r[13][17:0]),
                .b_i(inverse_r[17:0]),
                .sign_i(delay_4_r[13][18] ^ inverse_r[18]),
                .exponent_i(delay_4_r[13][28:19] + inverse_r[28:19]),
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
                .a_i(delay_5_r[13][17:0]),
                .b_i(inverse_r[17:0]),
                .sign_i(delay_5_r[13][18] ^ inverse_r[18]),
                .exponent_i(delay_5_r[13][28:19] + inverse_r[28:19]),
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
                .magnitude_i(u_w[17:0]),
                .exponent_i(u_w[28:19] + 10'd8),
                .magnitude_o(unused_u_coordinate_magnitude_w)
            );
            edrv32_gpu_perspective_sign u_u_coordinate (
                .clk_i(clk_i),
                .en_i(advance_w),
                .magnitude_i(unused_u_coordinate_magnitude_w[31:0]),
                .sign_i(delay_6_r[8]),
                .value_o(u_coordinate_w)
            );
            edrv32_gpu_perspective_scale u_v_coordinate_magnitude (
                .clk_i(clk_i),
                .en_i(advance_w),
                .magnitude_i(v_w[17:0]),
                .exponent_i(v_w[28:19] + 10'd8),
                .magnitude_o(unused_v_coordinate_magnitude_w)
            );
            edrv32_gpu_perspective_sign u_v_coordinate (
                .clk_i(clk_i),
                .en_i(advance_w),
                .magnitude_i(unused_v_coordinate_magnitude_w[31:0]),
                .sign_i(delay_8_r[8]),
                .value_o(v_coordinate_w)
            );
            edrv32_gpu_perspective_multiply u_gradient_multiply_0 (
                .clk_i(clk_i),
                .en_i(advance_w),
                .a_i(u_w[17:0]),
                .b_i(delay_10_r[40][17:0]),
                .sign_i(u_w[18] ^ delay_10_r[40][18]),
                .exponent_i(u_w[28:19] + delay_10_r[40][28:19]),
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
                .a_i(delay_11_r[53]),
                .b_i(gradient_0_w),
                .normal_o(delta_0_w)
            );
            edrv32_gpu_perspective_multiply u_derivative_multiply_0 (
                .clk_i(clk_i),
                .en_i(advance_w),
                .a_i(delta_0_w[17:0]),
                .b_i(delay_12_r[50][17:0]),
                .sign_i(delta_0_w[18] ^ delay_12_r[50][18]),
                .exponent_i(delta_0_w[28:19] + delay_12_r[50][28:19]),
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
                .magnitude_i(unused_derivative_0_w[17:0]),
                .exponent_i(unused_derivative_0_w[28:19] + 10'd16),
                .magnitude_o(span_0_w)
            );
            edrv32_gpu_perspective_multiply u_gradient_multiply_1 (
                .clk_i(clk_i),
                .en_i(advance_w),
                .a_i(v_w[17:0]),
                .b_i(delay_13_r[40][17:0]),
                .sign_i(v_w[18] ^ delay_13_r[40][18]),
                .exponent_i(v_w[28:19] + delay_13_r[40][28:19]),
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
                .a_i(delay_14_r[53]),
                .b_i(gradient_1_w),
                .normal_o(delta_1_w)
            );
            edrv32_gpu_perspective_multiply u_derivative_multiply_1 (
                .clk_i(clk_i),
                .en_i(advance_w),
                .a_i(delta_1_w[17:0]),
                .b_i(delay_15_r[50][17:0]),
                .sign_i(delta_1_w[18] ^ delay_15_r[50][18]),
                .exponent_i(delta_1_w[28:19] + delay_15_r[50][28:19]),
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
                .magnitude_i(unused_derivative_1_w[17:0]),
                .exponent_i(unused_derivative_1_w[28:19] + 10'd16),
                .magnitude_o(span_1_w)
            );
            edrv32_gpu_perspective_multiply u_gradient_multiply_2 (
                .clk_i(clk_i),
                .en_i(advance_w),
                .a_i(u_w[17:0]),
                .b_i(delay_16_r[40][17:0]),
                .sign_i(u_w[18] ^ delay_16_r[40][18]),
                .exponent_i(u_w[28:19] + delay_16_r[40][28:19]),
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
                .a_i(delay_17_r[53]),
                .b_i(gradient_2_w),
                .normal_o(delta_2_w)
            );
            edrv32_gpu_perspective_multiply u_derivative_multiply_2 (
                .clk_i(clk_i),
                .en_i(advance_w),
                .a_i(delta_2_w[17:0]),
                .b_i(delay_18_r[50][17:0]),
                .sign_i(delta_2_w[18] ^ delay_18_r[50][18]),
                .exponent_i(delta_2_w[28:19] + delay_18_r[50][28:19]),
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
                .magnitude_i(unused_derivative_2_w[17:0]),
                .exponent_i(unused_derivative_2_w[28:19] + 10'd16),
                .magnitude_o(span_2_w)
            );
            edrv32_gpu_perspective_multiply u_gradient_multiply_3 (
                .clk_i(clk_i),
                .en_i(advance_w),
                .a_i(v_w[17:0]),
                .b_i(delay_19_r[40][17:0]),
                .sign_i(v_w[18] ^ delay_19_r[40][18]),
                .exponent_i(v_w[28:19] + delay_19_r[40][28:19]),
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
                .a_i(delay_20_r[53]),
                .b_i(gradient_3_w),
                .normal_o(delta_3_w)
            );
            edrv32_gpu_perspective_multiply u_derivative_multiply_3 (
                .clk_i(clk_i),
                .en_i(advance_w),
                .a_i(delta_3_w[17:0]),
                .b_i(delay_21_r[50][17:0]),
                .sign_i(delta_3_w[18] ^ delay_21_r[50][18]),
                .exponent_i(delta_3_w[28:19] + delay_21_r[50][28:19]),
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
                    delay_3_r[0] <= q_normal_exponent_w;
                    delay_3_r[1] <= delay_3_r[0];
                    delay_3_r[2] <= delay_3_r[1];
                    delay_3_r[3] <= delay_3_r[2];
                    delay_3_r[4] <= delay_3_r[3];
                    delay_3_r[5] <= delay_3_r[4];
                    delay_3_r[6] <= delay_3_r[5];
                    delay_3_r[7] <= delay_3_r[6];
                    delay_3_r[8] <= delay_3_r[7];
                    delay_3_r[9] <= delay_3_r[8];
                    delay_3_r[10] <= delay_3_r[9];
                    delay_3_r[11] <= delay_3_r[10];
                    inverse_mantissa_r <= newton_r1_r[17] ? newton_r1_r : {newton_r1_r[16:0], 1'b0};
                    inverse_exponent_r <= -10'd34 - delay_3_r[11] - {9'b0, !newton_r1_r[17]};
                    inverse_r <= inverse_mantissa_r == 0 ? 29'b0
                        : {inverse_exponent_r, 1'b0, inverse_mantissa_r};
                    delay_4_r[0] <= uq_w;
                    delay_4_r[1] <= delay_4_r[0];
                    delay_4_r[2] <= delay_4_r[1];
                    delay_4_r[3] <= delay_4_r[2];
                    delay_4_r[4] <= delay_4_r[3];
                    delay_4_r[5] <= delay_4_r[4];
                    delay_4_r[6] <= delay_4_r[5];
                    delay_4_r[7] <= delay_4_r[6];
                    delay_4_r[8] <= delay_4_r[7];
                    delay_4_r[9] <= delay_4_r[8];
                    delay_4_r[10] <= delay_4_r[9];
                    delay_4_r[11] <= delay_4_r[10];
                    delay_4_r[12] <= delay_4_r[11];
                    delay_4_r[13] <= delay_4_r[12];
                    delay_5_r[0] <= vq_w;
                    delay_5_r[1] <= delay_5_r[0];
                    delay_5_r[2] <= delay_5_r[1];
                    delay_5_r[3] <= delay_5_r[2];
                    delay_5_r[4] <= delay_5_r[3];
                    delay_5_r[5] <= delay_5_r[4];
                    delay_5_r[6] <= delay_5_r[5];
                    delay_5_r[7] <= delay_5_r[6];
                    delay_5_r[8] <= delay_5_r[7];
                    delay_5_r[9] <= delay_5_r[8];
                    delay_5_r[10] <= delay_5_r[9];
                    delay_5_r[11] <= delay_5_r[10];
                    delay_5_r[12] <= delay_5_r[11];
                    delay_5_r[13] <= delay_5_r[12];
                    delay_6_r[0] <= u_coordinate_sign_w;
                    delay_6_r[1] <= delay_6_r[0];
                    delay_6_r[2] <= delay_6_r[1];
                    delay_6_r[3] <= delay_6_r[2];
                    delay_6_r[4] <= delay_6_r[3];
                    delay_6_r[5] <= delay_6_r[4];
                    delay_6_r[6] <= delay_6_r[5];
                    delay_6_r[7] <= delay_6_r[6];
                    delay_6_r[8] <= delay_6_r[7];
                    delay_7_r[0] <= u_coordinate_w;
                    delay_7_r[1] <= delay_7_r[0];
                    delay_7_r[2] <= delay_7_r[1];
                    delay_7_r[3] <= delay_7_r[2];
                    delay_7_r[4] <= delay_7_r[3];
                    delay_7_r[5] <= delay_7_r[4];
                    delay_7_r[6] <= delay_7_r[5];
                    delay_7_r[7] <= delay_7_r[6];
                    delay_7_r[8] <= delay_7_r[7];
                    delay_7_r[9] <= delay_7_r[8];
                    delay_7_r[10] <= delay_7_r[9];
                    delay_7_r[11] <= delay_7_r[10];
                    delay_7_r[12] <= delay_7_r[11];
                    delay_7_r[13] <= delay_7_r[12];
                    delay_7_r[14] <= delay_7_r[13];
                    delay_7_r[15] <= delay_7_r[14];
                    delay_7_r[16] <= delay_7_r[15];
                    delay_7_r[17] <= delay_7_r[16];
                    delay_7_r[18] <= delay_7_r[17];
                    delay_7_r[19] <= delay_7_r[18];
                    delay_7_r[20] <= delay_7_r[19];
                    delay_7_r[21] <= delay_7_r[20];
                    delay_7_r[22] <= delay_7_r[21];
                    delay_7_r[23] <= delay_7_r[22];
                    delay_7_r[24] <= delay_7_r[23];
                    delay_7_r[25] <= delay_7_r[24];
                    delay_7_r[26] <= delay_7_r[25];
                    delay_7_r[27] <= delay_7_r[26];
                    delay_7_r[28] <= delay_7_r[27];
                    delay_7_r[29] <= delay_7_r[28];
                    delay_7_r[30] <= delay_7_r[29];
                    delay_7_r[31] <= delay_7_r[30];
                    delay_7_r[32] <= delay_7_r[31];
                    delay_7_r[33] <= delay_7_r[32];
                    delay_7_r[34] <= delay_7_r[33];
                    delay_7_r[35] <= delay_7_r[34];
                    delay_7_r[36] <= delay_7_r[35];
                    delay_7_r[37] <= delay_7_r[36];
                    delay_7_r[38] <= delay_7_r[37];
                    delay_7_r[39] <= delay_7_r[38];
                    delay_7_r[40] <= delay_7_r[39];
                    delay_7_r[41] <= delay_7_r[40];
                    delay_7_r[42] <= delay_7_r[41];
                    delay_7_r[43] <= delay_7_r[42];
                    delay_7_r[44] <= delay_7_r[43];
                    delay_7_r[45] <= delay_7_r[44];
                    delay_7_r[46] <= delay_7_r[45];
                    delay_7_r[47] <= delay_7_r[46];
                    delay_7_r[48] <= delay_7_r[47];
                    delay_7_r[49] <= delay_7_r[48];
                    delay_7_r[50] <= delay_7_r[49];
                    delay_7_r[51] <= delay_7_r[50];
                    delay_7_r[52] <= delay_7_r[51];
                    delay_8_r[0] <= v_coordinate_sign_w;
                    delay_8_r[1] <= delay_8_r[0];
                    delay_8_r[2] <= delay_8_r[1];
                    delay_8_r[3] <= delay_8_r[2];
                    delay_8_r[4] <= delay_8_r[3];
                    delay_8_r[5] <= delay_8_r[4];
                    delay_8_r[6] <= delay_8_r[5];
                    delay_8_r[7] <= delay_8_r[6];
                    delay_8_r[8] <= delay_8_r[7];
                    delay_9_r[0] <= v_coordinate_w;
                    delay_9_r[1] <= delay_9_r[0];
                    delay_9_r[2] <= delay_9_r[1];
                    delay_9_r[3] <= delay_9_r[2];
                    delay_9_r[4] <= delay_9_r[3];
                    delay_9_r[5] <= delay_9_r[4];
                    delay_9_r[6] <= delay_9_r[5];
                    delay_9_r[7] <= delay_9_r[6];
                    delay_9_r[8] <= delay_9_r[7];
                    delay_9_r[9] <= delay_9_r[8];
                    delay_9_r[10] <= delay_9_r[9];
                    delay_9_r[11] <= delay_9_r[10];
                    delay_9_r[12] <= delay_9_r[11];
                    delay_9_r[13] <= delay_9_r[12];
                    delay_9_r[14] <= delay_9_r[13];
                    delay_9_r[15] <= delay_9_r[14];
                    delay_9_r[16] <= delay_9_r[15];
                    delay_9_r[17] <= delay_9_r[16];
                    delay_9_r[18] <= delay_9_r[17];
                    delay_9_r[19] <= delay_9_r[18];
                    delay_9_r[20] <= delay_9_r[19];
                    delay_9_r[21] <= delay_9_r[20];
                    delay_9_r[22] <= delay_9_r[21];
                    delay_9_r[23] <= delay_9_r[22];
                    delay_9_r[24] <= delay_9_r[23];
                    delay_9_r[25] <= delay_9_r[24];
                    delay_9_r[26] <= delay_9_r[25];
                    delay_9_r[27] <= delay_9_r[26];
                    delay_9_r[28] <= delay_9_r[27];
                    delay_9_r[29] <= delay_9_r[28];
                    delay_9_r[30] <= delay_9_r[29];
                    delay_9_r[31] <= delay_9_r[30];
                    delay_9_r[32] <= delay_9_r[31];
                    delay_9_r[33] <= delay_9_r[32];
                    delay_9_r[34] <= delay_9_r[33];
                    delay_9_r[35] <= delay_9_r[34];
                    delay_9_r[36] <= delay_9_r[35];
                    delay_9_r[37] <= delay_9_r[36];
                    delay_9_r[38] <= delay_9_r[37];
                    delay_9_r[39] <= delay_9_r[38];
                    delay_9_r[40] <= delay_9_r[39];
                    delay_9_r[41] <= delay_9_r[40];
                    delay_9_r[42] <= delay_9_r[41];
                    delay_9_r[43] <= delay_9_r[42];
                    delay_9_r[44] <= delay_9_r[43];
                    delay_9_r[45] <= delay_9_r[44];
                    delay_9_r[46] <= delay_9_r[45];
                    delay_9_r[47] <= delay_9_r[46];
                    delay_9_r[48] <= delay_9_r[47];
                    delay_9_r[49] <= delay_9_r[48];
                    delay_9_r[50] <= delay_9_r[49];
                    delay_9_r[51] <= delay_9_r[50];
                    delay_9_r[52] <= delay_9_r[51];
                    delay_10_r[0] <= dq_0_0_w;
                    delay_10_r[1] <= delay_10_r[0];
                    delay_10_r[2] <= delay_10_r[1];
                    delay_10_r[3] <= delay_10_r[2];
                    delay_10_r[4] <= delay_10_r[3];
                    delay_10_r[5] <= delay_10_r[4];
                    delay_10_r[6] <= delay_10_r[5];
                    delay_10_r[7] <= delay_10_r[6];
                    delay_10_r[8] <= delay_10_r[7];
                    delay_10_r[9] <= delay_10_r[8];
                    delay_10_r[10] <= delay_10_r[9];
                    delay_10_r[11] <= delay_10_r[10];
                    delay_10_r[12] <= delay_10_r[11];
                    delay_10_r[13] <= delay_10_r[12];
                    delay_10_r[14] <= delay_10_r[13];
                    delay_10_r[15] <= delay_10_r[14];
                    delay_10_r[16] <= delay_10_r[15];
                    delay_10_r[17] <= delay_10_r[16];
                    delay_10_r[18] <= delay_10_r[17];
                    delay_10_r[19] <= delay_10_r[18];
                    delay_10_r[20] <= delay_10_r[19];
                    delay_10_r[21] <= delay_10_r[20];
                    delay_10_r[22] <= delay_10_r[21];
                    delay_10_r[23] <= delay_10_r[22];
                    delay_10_r[24] <= delay_10_r[23];
                    delay_10_r[25] <= delay_10_r[24];
                    delay_10_r[26] <= delay_10_r[25];
                    delay_10_r[27] <= delay_10_r[26];
                    delay_10_r[28] <= delay_10_r[27];
                    delay_10_r[29] <= delay_10_r[28];
                    delay_10_r[30] <= delay_10_r[29];
                    delay_10_r[31] <= delay_10_r[30];
                    delay_10_r[32] <= delay_10_r[31];
                    delay_10_r[33] <= delay_10_r[32];
                    delay_10_r[34] <= delay_10_r[33];
                    delay_10_r[35] <= delay_10_r[34];
                    delay_10_r[36] <= delay_10_r[35];
                    delay_10_r[37] <= delay_10_r[36];
                    delay_10_r[38] <= delay_10_r[37];
                    delay_10_r[39] <= delay_10_r[38];
                    delay_10_r[40] <= delay_10_r[39];
                    delay_11_r[0] <= guq_0_w;
                    delay_11_r[1] <= delay_11_r[0];
                    delay_11_r[2] <= delay_11_r[1];
                    delay_11_r[3] <= delay_11_r[2];
                    delay_11_r[4] <= delay_11_r[3];
                    delay_11_r[5] <= delay_11_r[4];
                    delay_11_r[6] <= delay_11_r[5];
                    delay_11_r[7] <= delay_11_r[6];
                    delay_11_r[8] <= delay_11_r[7];
                    delay_11_r[9] <= delay_11_r[8];
                    delay_11_r[10] <= delay_11_r[9];
                    delay_11_r[11] <= delay_11_r[10];
                    delay_11_r[12] <= delay_11_r[11];
                    delay_11_r[13] <= delay_11_r[12];
                    delay_11_r[14] <= delay_11_r[13];
                    delay_11_r[15] <= delay_11_r[14];
                    delay_11_r[16] <= delay_11_r[15];
                    delay_11_r[17] <= delay_11_r[16];
                    delay_11_r[18] <= delay_11_r[17];
                    delay_11_r[19] <= delay_11_r[18];
                    delay_11_r[20] <= delay_11_r[19];
                    delay_11_r[21] <= delay_11_r[20];
                    delay_11_r[22] <= delay_11_r[21];
                    delay_11_r[23] <= delay_11_r[22];
                    delay_11_r[24] <= delay_11_r[23];
                    delay_11_r[25] <= delay_11_r[24];
                    delay_11_r[26] <= delay_11_r[25];
                    delay_11_r[27] <= delay_11_r[26];
                    delay_11_r[28] <= delay_11_r[27];
                    delay_11_r[29] <= delay_11_r[28];
                    delay_11_r[30] <= delay_11_r[29];
                    delay_11_r[31] <= delay_11_r[30];
                    delay_11_r[32] <= delay_11_r[31];
                    delay_11_r[33] <= delay_11_r[32];
                    delay_11_r[34] <= delay_11_r[33];
                    delay_11_r[35] <= delay_11_r[34];
                    delay_11_r[36] <= delay_11_r[35];
                    delay_11_r[37] <= delay_11_r[36];
                    delay_11_r[38] <= delay_11_r[37];
                    delay_11_r[39] <= delay_11_r[38];
                    delay_11_r[40] <= delay_11_r[39];
                    delay_11_r[41] <= delay_11_r[40];
                    delay_11_r[42] <= delay_11_r[41];
                    delay_11_r[43] <= delay_11_r[42];
                    delay_11_r[44] <= delay_11_r[43];
                    delay_11_r[45] <= delay_11_r[44];
                    delay_11_r[46] <= delay_11_r[45];
                    delay_11_r[47] <= delay_11_r[46];
                    delay_11_r[48] <= delay_11_r[47];
                    delay_11_r[49] <= delay_11_r[48];
                    delay_11_r[50] <= delay_11_r[49];
                    delay_11_r[51] <= delay_11_r[50];
                    delay_11_r[52] <= delay_11_r[51];
                    delay_11_r[53] <= delay_11_r[52];
                    delay_12_r[0] <= inverse_r;
                    delay_12_r[1] <= delay_12_r[0];
                    delay_12_r[2] <= delay_12_r[1];
                    delay_12_r[3] <= delay_12_r[2];
                    delay_12_r[4] <= delay_12_r[3];
                    delay_12_r[5] <= delay_12_r[4];
                    delay_12_r[6] <= delay_12_r[5];
                    delay_12_r[7] <= delay_12_r[6];
                    delay_12_r[8] <= delay_12_r[7];
                    delay_12_r[9] <= delay_12_r[8];
                    delay_12_r[10] <= delay_12_r[9];
                    delay_12_r[11] <= delay_12_r[10];
                    delay_12_r[12] <= delay_12_r[11];
                    delay_12_r[13] <= delay_12_r[12];
                    delay_12_r[14] <= delay_12_r[13];
                    delay_12_r[15] <= delay_12_r[14];
                    delay_12_r[16] <= delay_12_r[15];
                    delay_12_r[17] <= delay_12_r[16];
                    delay_12_r[18] <= delay_12_r[17];
                    delay_12_r[19] <= delay_12_r[18];
                    delay_12_r[20] <= delay_12_r[19];
                    delay_12_r[21] <= delay_12_r[20];
                    delay_12_r[22] <= delay_12_r[21];
                    delay_12_r[23] <= delay_12_r[22];
                    delay_12_r[24] <= delay_12_r[23];
                    delay_12_r[25] <= delay_12_r[24];
                    delay_12_r[26] <= delay_12_r[25];
                    delay_12_r[27] <= delay_12_r[26];
                    delay_12_r[28] <= delay_12_r[27];
                    delay_12_r[29] <= delay_12_r[28];
                    delay_12_r[30] <= delay_12_r[29];
                    delay_12_r[31] <= delay_12_r[30];
                    delay_12_r[32] <= delay_12_r[31];
                    delay_12_r[33] <= delay_12_r[32];
                    delay_12_r[34] <= delay_12_r[33];
                    delay_12_r[35] <= delay_12_r[34];
                    delay_12_r[36] <= delay_12_r[35];
                    delay_12_r[37] <= delay_12_r[36];
                    delay_12_r[38] <= delay_12_r[37];
                    delay_12_r[39] <= delay_12_r[38];
                    delay_12_r[40] <= delay_12_r[39];
                    delay_12_r[41] <= delay_12_r[40];
                    delay_12_r[42] <= delay_12_r[41];
                    delay_12_r[43] <= delay_12_r[42];
                    delay_12_r[44] <= delay_12_r[43];
                    delay_12_r[45] <= delay_12_r[44];
                    delay_12_r[46] <= delay_12_r[45];
                    delay_12_r[47] <= delay_12_r[46];
                    delay_12_r[48] <= delay_12_r[47];
                    delay_12_r[49] <= delay_12_r[48];
                    delay_12_r[50] <= delay_12_r[49];
                    delay_13_r[0] <= dq_0_1_w;
                    delay_13_r[1] <= delay_13_r[0];
                    delay_13_r[2] <= delay_13_r[1];
                    delay_13_r[3] <= delay_13_r[2];
                    delay_13_r[4] <= delay_13_r[3];
                    delay_13_r[5] <= delay_13_r[4];
                    delay_13_r[6] <= delay_13_r[5];
                    delay_13_r[7] <= delay_13_r[6];
                    delay_13_r[8] <= delay_13_r[7];
                    delay_13_r[9] <= delay_13_r[8];
                    delay_13_r[10] <= delay_13_r[9];
                    delay_13_r[11] <= delay_13_r[10];
                    delay_13_r[12] <= delay_13_r[11];
                    delay_13_r[13] <= delay_13_r[12];
                    delay_13_r[14] <= delay_13_r[13];
                    delay_13_r[15] <= delay_13_r[14];
                    delay_13_r[16] <= delay_13_r[15];
                    delay_13_r[17] <= delay_13_r[16];
                    delay_13_r[18] <= delay_13_r[17];
                    delay_13_r[19] <= delay_13_r[18];
                    delay_13_r[20] <= delay_13_r[19];
                    delay_13_r[21] <= delay_13_r[20];
                    delay_13_r[22] <= delay_13_r[21];
                    delay_13_r[23] <= delay_13_r[22];
                    delay_13_r[24] <= delay_13_r[23];
                    delay_13_r[25] <= delay_13_r[24];
                    delay_13_r[26] <= delay_13_r[25];
                    delay_13_r[27] <= delay_13_r[26];
                    delay_13_r[28] <= delay_13_r[27];
                    delay_13_r[29] <= delay_13_r[28];
                    delay_13_r[30] <= delay_13_r[29];
                    delay_13_r[31] <= delay_13_r[30];
                    delay_13_r[32] <= delay_13_r[31];
                    delay_13_r[33] <= delay_13_r[32];
                    delay_13_r[34] <= delay_13_r[33];
                    delay_13_r[35] <= delay_13_r[34];
                    delay_13_r[36] <= delay_13_r[35];
                    delay_13_r[37] <= delay_13_r[36];
                    delay_13_r[38] <= delay_13_r[37];
                    delay_13_r[39] <= delay_13_r[38];
                    delay_13_r[40] <= delay_13_r[39];
                    delay_14_r[0] <= guq_1_w;
                    delay_14_r[1] <= delay_14_r[0];
                    delay_14_r[2] <= delay_14_r[1];
                    delay_14_r[3] <= delay_14_r[2];
                    delay_14_r[4] <= delay_14_r[3];
                    delay_14_r[5] <= delay_14_r[4];
                    delay_14_r[6] <= delay_14_r[5];
                    delay_14_r[7] <= delay_14_r[6];
                    delay_14_r[8] <= delay_14_r[7];
                    delay_14_r[9] <= delay_14_r[8];
                    delay_14_r[10] <= delay_14_r[9];
                    delay_14_r[11] <= delay_14_r[10];
                    delay_14_r[12] <= delay_14_r[11];
                    delay_14_r[13] <= delay_14_r[12];
                    delay_14_r[14] <= delay_14_r[13];
                    delay_14_r[15] <= delay_14_r[14];
                    delay_14_r[16] <= delay_14_r[15];
                    delay_14_r[17] <= delay_14_r[16];
                    delay_14_r[18] <= delay_14_r[17];
                    delay_14_r[19] <= delay_14_r[18];
                    delay_14_r[20] <= delay_14_r[19];
                    delay_14_r[21] <= delay_14_r[20];
                    delay_14_r[22] <= delay_14_r[21];
                    delay_14_r[23] <= delay_14_r[22];
                    delay_14_r[24] <= delay_14_r[23];
                    delay_14_r[25] <= delay_14_r[24];
                    delay_14_r[26] <= delay_14_r[25];
                    delay_14_r[27] <= delay_14_r[26];
                    delay_14_r[28] <= delay_14_r[27];
                    delay_14_r[29] <= delay_14_r[28];
                    delay_14_r[30] <= delay_14_r[29];
                    delay_14_r[31] <= delay_14_r[30];
                    delay_14_r[32] <= delay_14_r[31];
                    delay_14_r[33] <= delay_14_r[32];
                    delay_14_r[34] <= delay_14_r[33];
                    delay_14_r[35] <= delay_14_r[34];
                    delay_14_r[36] <= delay_14_r[35];
                    delay_14_r[37] <= delay_14_r[36];
                    delay_14_r[38] <= delay_14_r[37];
                    delay_14_r[39] <= delay_14_r[38];
                    delay_14_r[40] <= delay_14_r[39];
                    delay_14_r[41] <= delay_14_r[40];
                    delay_14_r[42] <= delay_14_r[41];
                    delay_14_r[43] <= delay_14_r[42];
                    delay_14_r[44] <= delay_14_r[43];
                    delay_14_r[45] <= delay_14_r[44];
                    delay_14_r[46] <= delay_14_r[45];
                    delay_14_r[47] <= delay_14_r[46];
                    delay_14_r[48] <= delay_14_r[47];
                    delay_14_r[49] <= delay_14_r[48];
                    delay_14_r[50] <= delay_14_r[49];
                    delay_14_r[51] <= delay_14_r[50];
                    delay_14_r[52] <= delay_14_r[51];
                    delay_14_r[53] <= delay_14_r[52];
                    delay_15_r[0] <= inverse_r;
                    delay_15_r[1] <= delay_15_r[0];
                    delay_15_r[2] <= delay_15_r[1];
                    delay_15_r[3] <= delay_15_r[2];
                    delay_15_r[4] <= delay_15_r[3];
                    delay_15_r[5] <= delay_15_r[4];
                    delay_15_r[6] <= delay_15_r[5];
                    delay_15_r[7] <= delay_15_r[6];
                    delay_15_r[8] <= delay_15_r[7];
                    delay_15_r[9] <= delay_15_r[8];
                    delay_15_r[10] <= delay_15_r[9];
                    delay_15_r[11] <= delay_15_r[10];
                    delay_15_r[12] <= delay_15_r[11];
                    delay_15_r[13] <= delay_15_r[12];
                    delay_15_r[14] <= delay_15_r[13];
                    delay_15_r[15] <= delay_15_r[14];
                    delay_15_r[16] <= delay_15_r[15];
                    delay_15_r[17] <= delay_15_r[16];
                    delay_15_r[18] <= delay_15_r[17];
                    delay_15_r[19] <= delay_15_r[18];
                    delay_15_r[20] <= delay_15_r[19];
                    delay_15_r[21] <= delay_15_r[20];
                    delay_15_r[22] <= delay_15_r[21];
                    delay_15_r[23] <= delay_15_r[22];
                    delay_15_r[24] <= delay_15_r[23];
                    delay_15_r[25] <= delay_15_r[24];
                    delay_15_r[26] <= delay_15_r[25];
                    delay_15_r[27] <= delay_15_r[26];
                    delay_15_r[28] <= delay_15_r[27];
                    delay_15_r[29] <= delay_15_r[28];
                    delay_15_r[30] <= delay_15_r[29];
                    delay_15_r[31] <= delay_15_r[30];
                    delay_15_r[32] <= delay_15_r[31];
                    delay_15_r[33] <= delay_15_r[32];
                    delay_15_r[34] <= delay_15_r[33];
                    delay_15_r[35] <= delay_15_r[34];
                    delay_15_r[36] <= delay_15_r[35];
                    delay_15_r[37] <= delay_15_r[36];
                    delay_15_r[38] <= delay_15_r[37];
                    delay_15_r[39] <= delay_15_r[38];
                    delay_15_r[40] <= delay_15_r[39];
                    delay_15_r[41] <= delay_15_r[40];
                    delay_15_r[42] <= delay_15_r[41];
                    delay_15_r[43] <= delay_15_r[42];
                    delay_15_r[44] <= delay_15_r[43];
                    delay_15_r[45] <= delay_15_r[44];
                    delay_15_r[46] <= delay_15_r[45];
                    delay_15_r[47] <= delay_15_r[46];
                    delay_15_r[48] <= delay_15_r[47];
                    delay_15_r[49] <= delay_15_r[48];
                    delay_15_r[50] <= delay_15_r[49];
                    delay_16_r[0] <= dq_1_2_w;
                    delay_16_r[1] <= delay_16_r[0];
                    delay_16_r[2] <= delay_16_r[1];
                    delay_16_r[3] <= delay_16_r[2];
                    delay_16_r[4] <= delay_16_r[3];
                    delay_16_r[5] <= delay_16_r[4];
                    delay_16_r[6] <= delay_16_r[5];
                    delay_16_r[7] <= delay_16_r[6];
                    delay_16_r[8] <= delay_16_r[7];
                    delay_16_r[9] <= delay_16_r[8];
                    delay_16_r[10] <= delay_16_r[9];
                    delay_16_r[11] <= delay_16_r[10];
                    delay_16_r[12] <= delay_16_r[11];
                    delay_16_r[13] <= delay_16_r[12];
                    delay_16_r[14] <= delay_16_r[13];
                    delay_16_r[15] <= delay_16_r[14];
                    delay_16_r[16] <= delay_16_r[15];
                    delay_16_r[17] <= delay_16_r[16];
                    delay_16_r[18] <= delay_16_r[17];
                    delay_16_r[19] <= delay_16_r[18];
                    delay_16_r[20] <= delay_16_r[19];
                    delay_16_r[21] <= delay_16_r[20];
                    delay_16_r[22] <= delay_16_r[21];
                    delay_16_r[23] <= delay_16_r[22];
                    delay_16_r[24] <= delay_16_r[23];
                    delay_16_r[25] <= delay_16_r[24];
                    delay_16_r[26] <= delay_16_r[25];
                    delay_16_r[27] <= delay_16_r[26];
                    delay_16_r[28] <= delay_16_r[27];
                    delay_16_r[29] <= delay_16_r[28];
                    delay_16_r[30] <= delay_16_r[29];
                    delay_16_r[31] <= delay_16_r[30];
                    delay_16_r[32] <= delay_16_r[31];
                    delay_16_r[33] <= delay_16_r[32];
                    delay_16_r[34] <= delay_16_r[33];
                    delay_16_r[35] <= delay_16_r[34];
                    delay_16_r[36] <= delay_16_r[35];
                    delay_16_r[37] <= delay_16_r[36];
                    delay_16_r[38] <= delay_16_r[37];
                    delay_16_r[39] <= delay_16_r[38];
                    delay_16_r[40] <= delay_16_r[39];
                    delay_17_r[0] <= guq_2_w;
                    delay_17_r[1] <= delay_17_r[0];
                    delay_17_r[2] <= delay_17_r[1];
                    delay_17_r[3] <= delay_17_r[2];
                    delay_17_r[4] <= delay_17_r[3];
                    delay_17_r[5] <= delay_17_r[4];
                    delay_17_r[6] <= delay_17_r[5];
                    delay_17_r[7] <= delay_17_r[6];
                    delay_17_r[8] <= delay_17_r[7];
                    delay_17_r[9] <= delay_17_r[8];
                    delay_17_r[10] <= delay_17_r[9];
                    delay_17_r[11] <= delay_17_r[10];
                    delay_17_r[12] <= delay_17_r[11];
                    delay_17_r[13] <= delay_17_r[12];
                    delay_17_r[14] <= delay_17_r[13];
                    delay_17_r[15] <= delay_17_r[14];
                    delay_17_r[16] <= delay_17_r[15];
                    delay_17_r[17] <= delay_17_r[16];
                    delay_17_r[18] <= delay_17_r[17];
                    delay_17_r[19] <= delay_17_r[18];
                    delay_17_r[20] <= delay_17_r[19];
                    delay_17_r[21] <= delay_17_r[20];
                    delay_17_r[22] <= delay_17_r[21];
                    delay_17_r[23] <= delay_17_r[22];
                    delay_17_r[24] <= delay_17_r[23];
                    delay_17_r[25] <= delay_17_r[24];
                    delay_17_r[26] <= delay_17_r[25];
                    delay_17_r[27] <= delay_17_r[26];
                    delay_17_r[28] <= delay_17_r[27];
                    delay_17_r[29] <= delay_17_r[28];
                    delay_17_r[30] <= delay_17_r[29];
                    delay_17_r[31] <= delay_17_r[30];
                    delay_17_r[32] <= delay_17_r[31];
                    delay_17_r[33] <= delay_17_r[32];
                    delay_17_r[34] <= delay_17_r[33];
                    delay_17_r[35] <= delay_17_r[34];
                    delay_17_r[36] <= delay_17_r[35];
                    delay_17_r[37] <= delay_17_r[36];
                    delay_17_r[38] <= delay_17_r[37];
                    delay_17_r[39] <= delay_17_r[38];
                    delay_17_r[40] <= delay_17_r[39];
                    delay_17_r[41] <= delay_17_r[40];
                    delay_17_r[42] <= delay_17_r[41];
                    delay_17_r[43] <= delay_17_r[42];
                    delay_17_r[44] <= delay_17_r[43];
                    delay_17_r[45] <= delay_17_r[44];
                    delay_17_r[46] <= delay_17_r[45];
                    delay_17_r[47] <= delay_17_r[46];
                    delay_17_r[48] <= delay_17_r[47];
                    delay_17_r[49] <= delay_17_r[48];
                    delay_17_r[50] <= delay_17_r[49];
                    delay_17_r[51] <= delay_17_r[50];
                    delay_17_r[52] <= delay_17_r[51];
                    delay_17_r[53] <= delay_17_r[52];
                    delay_18_r[0] <= inverse_r;
                    delay_18_r[1] <= delay_18_r[0];
                    delay_18_r[2] <= delay_18_r[1];
                    delay_18_r[3] <= delay_18_r[2];
                    delay_18_r[4] <= delay_18_r[3];
                    delay_18_r[5] <= delay_18_r[4];
                    delay_18_r[6] <= delay_18_r[5];
                    delay_18_r[7] <= delay_18_r[6];
                    delay_18_r[8] <= delay_18_r[7];
                    delay_18_r[9] <= delay_18_r[8];
                    delay_18_r[10] <= delay_18_r[9];
                    delay_18_r[11] <= delay_18_r[10];
                    delay_18_r[12] <= delay_18_r[11];
                    delay_18_r[13] <= delay_18_r[12];
                    delay_18_r[14] <= delay_18_r[13];
                    delay_18_r[15] <= delay_18_r[14];
                    delay_18_r[16] <= delay_18_r[15];
                    delay_18_r[17] <= delay_18_r[16];
                    delay_18_r[18] <= delay_18_r[17];
                    delay_18_r[19] <= delay_18_r[18];
                    delay_18_r[20] <= delay_18_r[19];
                    delay_18_r[21] <= delay_18_r[20];
                    delay_18_r[22] <= delay_18_r[21];
                    delay_18_r[23] <= delay_18_r[22];
                    delay_18_r[24] <= delay_18_r[23];
                    delay_18_r[25] <= delay_18_r[24];
                    delay_18_r[26] <= delay_18_r[25];
                    delay_18_r[27] <= delay_18_r[26];
                    delay_18_r[28] <= delay_18_r[27];
                    delay_18_r[29] <= delay_18_r[28];
                    delay_18_r[30] <= delay_18_r[29];
                    delay_18_r[31] <= delay_18_r[30];
                    delay_18_r[32] <= delay_18_r[31];
                    delay_18_r[33] <= delay_18_r[32];
                    delay_18_r[34] <= delay_18_r[33];
                    delay_18_r[35] <= delay_18_r[34];
                    delay_18_r[36] <= delay_18_r[35];
                    delay_18_r[37] <= delay_18_r[36];
                    delay_18_r[38] <= delay_18_r[37];
                    delay_18_r[39] <= delay_18_r[38];
                    delay_18_r[40] <= delay_18_r[39];
                    delay_18_r[41] <= delay_18_r[40];
                    delay_18_r[42] <= delay_18_r[41];
                    delay_18_r[43] <= delay_18_r[42];
                    delay_18_r[44] <= delay_18_r[43];
                    delay_18_r[45] <= delay_18_r[44];
                    delay_18_r[46] <= delay_18_r[45];
                    delay_18_r[47] <= delay_18_r[46];
                    delay_18_r[48] <= delay_18_r[47];
                    delay_18_r[49] <= delay_18_r[48];
                    delay_18_r[50] <= delay_18_r[49];
                    delay_19_r[0] <= dq_1_3_w;
                    delay_19_r[1] <= delay_19_r[0];
                    delay_19_r[2] <= delay_19_r[1];
                    delay_19_r[3] <= delay_19_r[2];
                    delay_19_r[4] <= delay_19_r[3];
                    delay_19_r[5] <= delay_19_r[4];
                    delay_19_r[6] <= delay_19_r[5];
                    delay_19_r[7] <= delay_19_r[6];
                    delay_19_r[8] <= delay_19_r[7];
                    delay_19_r[9] <= delay_19_r[8];
                    delay_19_r[10] <= delay_19_r[9];
                    delay_19_r[11] <= delay_19_r[10];
                    delay_19_r[12] <= delay_19_r[11];
                    delay_19_r[13] <= delay_19_r[12];
                    delay_19_r[14] <= delay_19_r[13];
                    delay_19_r[15] <= delay_19_r[14];
                    delay_19_r[16] <= delay_19_r[15];
                    delay_19_r[17] <= delay_19_r[16];
                    delay_19_r[18] <= delay_19_r[17];
                    delay_19_r[19] <= delay_19_r[18];
                    delay_19_r[20] <= delay_19_r[19];
                    delay_19_r[21] <= delay_19_r[20];
                    delay_19_r[22] <= delay_19_r[21];
                    delay_19_r[23] <= delay_19_r[22];
                    delay_19_r[24] <= delay_19_r[23];
                    delay_19_r[25] <= delay_19_r[24];
                    delay_19_r[26] <= delay_19_r[25];
                    delay_19_r[27] <= delay_19_r[26];
                    delay_19_r[28] <= delay_19_r[27];
                    delay_19_r[29] <= delay_19_r[28];
                    delay_19_r[30] <= delay_19_r[29];
                    delay_19_r[31] <= delay_19_r[30];
                    delay_19_r[32] <= delay_19_r[31];
                    delay_19_r[33] <= delay_19_r[32];
                    delay_19_r[34] <= delay_19_r[33];
                    delay_19_r[35] <= delay_19_r[34];
                    delay_19_r[36] <= delay_19_r[35];
                    delay_19_r[37] <= delay_19_r[36];
                    delay_19_r[38] <= delay_19_r[37];
                    delay_19_r[39] <= delay_19_r[38];
                    delay_19_r[40] <= delay_19_r[39];
                    delay_20_r[0] <= guq_3_w;
                    delay_20_r[1] <= delay_20_r[0];
                    delay_20_r[2] <= delay_20_r[1];
                    delay_20_r[3] <= delay_20_r[2];
                    delay_20_r[4] <= delay_20_r[3];
                    delay_20_r[5] <= delay_20_r[4];
                    delay_20_r[6] <= delay_20_r[5];
                    delay_20_r[7] <= delay_20_r[6];
                    delay_20_r[8] <= delay_20_r[7];
                    delay_20_r[9] <= delay_20_r[8];
                    delay_20_r[10] <= delay_20_r[9];
                    delay_20_r[11] <= delay_20_r[10];
                    delay_20_r[12] <= delay_20_r[11];
                    delay_20_r[13] <= delay_20_r[12];
                    delay_20_r[14] <= delay_20_r[13];
                    delay_20_r[15] <= delay_20_r[14];
                    delay_20_r[16] <= delay_20_r[15];
                    delay_20_r[17] <= delay_20_r[16];
                    delay_20_r[18] <= delay_20_r[17];
                    delay_20_r[19] <= delay_20_r[18];
                    delay_20_r[20] <= delay_20_r[19];
                    delay_20_r[21] <= delay_20_r[20];
                    delay_20_r[22] <= delay_20_r[21];
                    delay_20_r[23] <= delay_20_r[22];
                    delay_20_r[24] <= delay_20_r[23];
                    delay_20_r[25] <= delay_20_r[24];
                    delay_20_r[26] <= delay_20_r[25];
                    delay_20_r[27] <= delay_20_r[26];
                    delay_20_r[28] <= delay_20_r[27];
                    delay_20_r[29] <= delay_20_r[28];
                    delay_20_r[30] <= delay_20_r[29];
                    delay_20_r[31] <= delay_20_r[30];
                    delay_20_r[32] <= delay_20_r[31];
                    delay_20_r[33] <= delay_20_r[32];
                    delay_20_r[34] <= delay_20_r[33];
                    delay_20_r[35] <= delay_20_r[34];
                    delay_20_r[36] <= delay_20_r[35];
                    delay_20_r[37] <= delay_20_r[36];
                    delay_20_r[38] <= delay_20_r[37];
                    delay_20_r[39] <= delay_20_r[38];
                    delay_20_r[40] <= delay_20_r[39];
                    delay_20_r[41] <= delay_20_r[40];
                    delay_20_r[42] <= delay_20_r[41];
                    delay_20_r[43] <= delay_20_r[42];
                    delay_20_r[44] <= delay_20_r[43];
                    delay_20_r[45] <= delay_20_r[44];
                    delay_20_r[46] <= delay_20_r[45];
                    delay_20_r[47] <= delay_20_r[46];
                    delay_20_r[48] <= delay_20_r[47];
                    delay_20_r[49] <= delay_20_r[48];
                    delay_20_r[50] <= delay_20_r[49];
                    delay_20_r[51] <= delay_20_r[50];
                    delay_20_r[52] <= delay_20_r[51];
                    delay_20_r[53] <= delay_20_r[52];
                    delay_21_r[0] <= inverse_r;
                    delay_21_r[1] <= delay_21_r[0];
                    delay_21_r[2] <= delay_21_r[1];
                    delay_21_r[3] <= delay_21_r[2];
                    delay_21_r[4] <= delay_21_r[3];
                    delay_21_r[5] <= delay_21_r[4];
                    delay_21_r[6] <= delay_21_r[5];
                    delay_21_r[7] <= delay_21_r[6];
                    delay_21_r[8] <= delay_21_r[7];
                    delay_21_r[9] <= delay_21_r[8];
                    delay_21_r[10] <= delay_21_r[9];
                    delay_21_r[11] <= delay_21_r[10];
                    delay_21_r[12] <= delay_21_r[11];
                    delay_21_r[13] <= delay_21_r[12];
                    delay_21_r[14] <= delay_21_r[13];
                    delay_21_r[15] <= delay_21_r[14];
                    delay_21_r[16] <= delay_21_r[15];
                    delay_21_r[17] <= delay_21_r[16];
                    delay_21_r[18] <= delay_21_r[17];
                    delay_21_r[19] <= delay_21_r[18];
                    delay_21_r[20] <= delay_21_r[19];
                    delay_21_r[21] <= delay_21_r[20];
                    delay_21_r[22] <= delay_21_r[21];
                    delay_21_r[23] <= delay_21_r[22];
                    delay_21_r[24] <= delay_21_r[23];
                    delay_21_r[25] <= delay_21_r[24];
                    delay_21_r[26] <= delay_21_r[25];
                    delay_21_r[27] <= delay_21_r[26];
                    delay_21_r[28] <= delay_21_r[27];
                    delay_21_r[29] <= delay_21_r[28];
                    delay_21_r[30] <= delay_21_r[29];
                    delay_21_r[31] <= delay_21_r[30];
                    delay_21_r[32] <= delay_21_r[31];
                    delay_21_r[33] <= delay_21_r[32];
                    delay_21_r[34] <= delay_21_r[33];
                    delay_21_r[35] <= delay_21_r[34];
                    delay_21_r[36] <= delay_21_r[35];
                    delay_21_r[37] <= delay_21_r[36];
                    delay_21_r[38] <= delay_21_r[37];
                    delay_21_r[39] <= delay_21_r[38];
                    delay_21_r[40] <= delay_21_r[39];
                    delay_21_r[41] <= delay_21_r[40];
                    delay_21_r[42] <= delay_21_r[41];
                    delay_21_r[43] <= delay_21_r[42];
                    delay_21_r[44] <= delay_21_r[43];
                    delay_21_r[45] <= delay_21_r[44];
                    delay_21_r[46] <= delay_21_r[45];
                    delay_21_r[47] <= delay_21_r[46];
                    delay_21_r[48] <= delay_21_r[47];
                    delay_21_r[49] <= delay_21_r[48];
                    delay_21_r[50] <= delay_21_r[49];
                    unused_depth_rounded_r <= {1'b0, unused_depth_raw_w[16 +: 16]}
                        + {16'b0, unused_depth_raw_w[15]};
                    depth_overflow_r <= unused_depth_raw_w[69:32] != 0;
                    depth_negative_r <= unused_depth_raw_w[69];
                    depth_clamped_r <= depth_negative_r ? 16'b0 : (depth_overflow_r
                        || unused_depth_rounded_r[16]) ? 16'd65535 : unused_depth_rounded_r[15:0];
                    delay_22_r[0] <= depth_clamped_r;
                    delay_22_r[1] <= delay_22_r[0];
                    delay_22_r[2] <= delay_22_r[1];
                    delay_22_r[3] <= delay_22_r[2];
                    delay_22_r[4] <= delay_22_r[3];
                    delay_22_r[5] <= delay_22_r[4];
                    delay_22_r[6] <= delay_22_r[5];
                    delay_22_r[7] <= delay_22_r[6];
                    delay_22_r[8] <= delay_22_r[7];
                    delay_22_r[9] <= delay_22_r[8];
                    delay_22_r[10] <= delay_22_r[9];
                    delay_22_r[11] <= delay_22_r[10];
                    delay_22_r[12] <= delay_22_r[11];
                    delay_22_r[13] <= delay_22_r[12];
                    delay_22_r[14] <= delay_22_r[13];
                    delay_22_r[15] <= delay_22_r[14];
                    delay_22_r[16] <= delay_22_r[15];
                    delay_22_r[17] <= delay_22_r[16];
                    delay_22_r[18] <= delay_22_r[17];
                    delay_22_r[19] <= delay_22_r[18];
                    delay_22_r[20] <= delay_22_r[19];
                    delay_22_r[21] <= delay_22_r[20];
                    delay_22_r[22] <= delay_22_r[21];
                    delay_22_r[23] <= delay_22_r[22];
                    delay_22_r[24] <= delay_22_r[23];
                    delay_22_r[25] <= delay_22_r[24];
                    delay_22_r[26] <= delay_22_r[25];
                    delay_22_r[27] <= delay_22_r[26];
                    delay_22_r[28] <= delay_22_r[27];
                    delay_22_r[29] <= delay_22_r[28];
                    delay_22_r[30] <= delay_22_r[29];
                    delay_22_r[31] <= delay_22_r[30];
                    delay_22_r[32] <= delay_22_r[31];
                    delay_22_r[33] <= delay_22_r[32];
                    delay_22_r[34] <= delay_22_r[33];
                    delay_22_r[35] <= delay_22_r[34];
                    delay_22_r[36] <= delay_22_r[35];
                    delay_22_r[37] <= delay_22_r[36];
                    delay_22_r[38] <= delay_22_r[37];
                    delay_22_r[39] <= delay_22_r[38];
                    delay_22_r[40] <= delay_22_r[39];
                    delay_22_r[41] <= delay_22_r[40];
                    delay_22_r[42] <= delay_22_r[41];
                    delay_22_r[43] <= delay_22_r[42];
                    delay_22_r[44] <= delay_22_r[43];
                    delay_22_r[45] <= delay_22_r[44];
                    delay_22_r[46] <= delay_22_r[45];
                    delay_22_r[47] <= delay_22_r[46];
                    delay_22_r[48] <= delay_22_r[47];
                    delay_22_r[49] <= delay_22_r[48];
                    delay_22_r[50] <= delay_22_r[49];
                    delay_22_r[51] <= delay_22_r[50];
                    delay_22_r[52] <= delay_22_r[51];
                    delay_22_r[53] <= delay_22_r[52];
                    delay_22_r[54] <= delay_22_r[53];
                    delay_22_r[55] <= delay_22_r[54];
                    delay_22_r[56] <= delay_22_r[55];
                    delay_22_r[57] <= delay_22_r[56];
                    delay_22_r[58] <= delay_22_r[57];
                    delay_22_r[59] <= delay_22_r[58];
                    delay_22_r[60] <= delay_22_r[59];
                    delay_22_r[61] <= delay_22_r[60];
                    delay_22_r[62] <= delay_22_r[61];
                    delay_22_r[63] <= delay_22_r[62];
                    delay_22_r[64] <= delay_22_r[63];
                    delay_22_r[65] <= delay_22_r[64];
                    delay_22_r[66] <= delay_22_r[65];
                    delay_22_r[67] <= delay_22_r[66];
                    delay_22_r[68] <= delay_22_r[67];
                    delay_22_r[69] <= delay_22_r[68];
                    delay_22_r[70] <= delay_22_r[69];
                    delay_22_r[71] <= delay_22_r[70];
                    delay_22_r[72] <= delay_22_r[71];
                    delay_22_r[73] <= delay_22_r[72];
                    delay_22_r[74] <= delay_22_r[73];
                    delay_22_r[75] <= delay_22_r[74];
                    delay_22_r[76] <= delay_22_r[75];
                    delay_22_r[77] <= delay_22_r[76];
                    delay_22_r[78] <= delay_22_r[77];
                    delay_22_r[79] <= delay_22_r[78];
                    delay_22_r[80] <= delay_22_r[79];
                    delay_22_r[81] <= delay_22_r[80];
                    delay_22_r[82] <= delay_22_r[81];
                    delay_22_r[83] <= delay_22_r[82];
                    delay_22_r[84] <= delay_22_r[83];
                    delay_22_r[85] <= delay_22_r[84];
                    delay_22_r[86] <= delay_22_r[85];
                    delay_22_r[87] <= delay_22_r[86];
                    delay_22_r[88] <= delay_22_r[87];
                    delay_22_r[89] <= delay_22_r[88];
                    delay_22_r[90] <= delay_22_r[89];
                    delay_22_r[91] <= delay_22_r[90];
                    delay_22_r[92] <= delay_22_r[91];
                    delay_22_r[93] <= delay_22_r[92];
                    delay_22_r[94] <= delay_22_r[93];
                    delay_22_r[95] <= delay_22_r[94];
                    delay_22_r[96] <= delay_22_r[95];
                    delay_22_r[97] <= delay_22_r[96];
                    delay_22_r[98] <= delay_22_r[97];
                    delay_22_r[99] <= delay_22_r[98];
                    delay_22_r[100] <= delay_22_r[99];
                    delay_22_r[101] <= delay_22_r[100];
                    delay_22_r[102] <= delay_22_r[101];
                    unused_red_rounded_r <= {1'b0, unused_red_raw_w[24 +: 8]}
                        + {8'b0, unused_red_raw_w[23]};
                    red_overflow_r <= unused_red_raw_w[69:32] != 0;
                    red_negative_r <= unused_red_raw_w[69];
                    red_clamped_r <= red_negative_r ? 8'b0 : (red_overflow_r
                        || unused_red_rounded_r[8]) ? 8'd255 : unused_red_rounded_r[7:0];
                    delay_23_r[0] <= red_clamped_r;
                    delay_23_r[1] <= delay_23_r[0];
                    delay_23_r[2] <= delay_23_r[1];
                    delay_23_r[3] <= delay_23_r[2];
                    delay_23_r[4] <= delay_23_r[3];
                    delay_23_r[5] <= delay_23_r[4];
                    delay_23_r[6] <= delay_23_r[5];
                    delay_23_r[7] <= delay_23_r[6];
                    delay_23_r[8] <= delay_23_r[7];
                    delay_23_r[9] <= delay_23_r[8];
                    delay_23_r[10] <= delay_23_r[9];
                    delay_23_r[11] <= delay_23_r[10];
                    delay_23_r[12] <= delay_23_r[11];
                    delay_23_r[13] <= delay_23_r[12];
                    delay_23_r[14] <= delay_23_r[13];
                    delay_23_r[15] <= delay_23_r[14];
                    delay_23_r[16] <= delay_23_r[15];
                    delay_23_r[17] <= delay_23_r[16];
                    delay_23_r[18] <= delay_23_r[17];
                    delay_23_r[19] <= delay_23_r[18];
                    delay_23_r[20] <= delay_23_r[19];
                    delay_23_r[21] <= delay_23_r[20];
                    delay_23_r[22] <= delay_23_r[21];
                    delay_23_r[23] <= delay_23_r[22];
                    delay_23_r[24] <= delay_23_r[23];
                    delay_23_r[25] <= delay_23_r[24];
                    delay_23_r[26] <= delay_23_r[25];
                    delay_23_r[27] <= delay_23_r[26];
                    delay_23_r[28] <= delay_23_r[27];
                    delay_23_r[29] <= delay_23_r[28];
                    delay_23_r[30] <= delay_23_r[29];
                    delay_23_r[31] <= delay_23_r[30];
                    delay_23_r[32] <= delay_23_r[31];
                    delay_23_r[33] <= delay_23_r[32];
                    delay_23_r[34] <= delay_23_r[33];
                    delay_23_r[35] <= delay_23_r[34];
                    delay_23_r[36] <= delay_23_r[35];
                    delay_23_r[37] <= delay_23_r[36];
                    delay_23_r[38] <= delay_23_r[37];
                    delay_23_r[39] <= delay_23_r[38];
                    delay_23_r[40] <= delay_23_r[39];
                    delay_23_r[41] <= delay_23_r[40];
                    delay_23_r[42] <= delay_23_r[41];
                    delay_23_r[43] <= delay_23_r[42];
                    delay_23_r[44] <= delay_23_r[43];
                    delay_23_r[45] <= delay_23_r[44];
                    delay_23_r[46] <= delay_23_r[45];
                    delay_23_r[47] <= delay_23_r[46];
                    delay_23_r[48] <= delay_23_r[47];
                    delay_23_r[49] <= delay_23_r[48];
                    delay_23_r[50] <= delay_23_r[49];
                    delay_23_r[51] <= delay_23_r[50];
                    delay_23_r[52] <= delay_23_r[51];
                    delay_23_r[53] <= delay_23_r[52];
                    delay_23_r[54] <= delay_23_r[53];
                    delay_23_r[55] <= delay_23_r[54];
                    delay_23_r[56] <= delay_23_r[55];
                    delay_23_r[57] <= delay_23_r[56];
                    delay_23_r[58] <= delay_23_r[57];
                    delay_23_r[59] <= delay_23_r[58];
                    delay_23_r[60] <= delay_23_r[59];
                    delay_23_r[61] <= delay_23_r[60];
                    delay_23_r[62] <= delay_23_r[61];
                    delay_23_r[63] <= delay_23_r[62];
                    delay_23_r[64] <= delay_23_r[63];
                    delay_23_r[65] <= delay_23_r[64];
                    delay_23_r[66] <= delay_23_r[65];
                    delay_23_r[67] <= delay_23_r[66];
                    delay_23_r[68] <= delay_23_r[67];
                    delay_23_r[69] <= delay_23_r[68];
                    delay_23_r[70] <= delay_23_r[69];
                    delay_23_r[71] <= delay_23_r[70];
                    delay_23_r[72] <= delay_23_r[71];
                    delay_23_r[73] <= delay_23_r[72];
                    delay_23_r[74] <= delay_23_r[73];
                    delay_23_r[75] <= delay_23_r[74];
                    delay_23_r[76] <= delay_23_r[75];
                    delay_23_r[77] <= delay_23_r[76];
                    delay_23_r[78] <= delay_23_r[77];
                    delay_23_r[79] <= delay_23_r[78];
                    delay_23_r[80] <= delay_23_r[79];
                    delay_23_r[81] <= delay_23_r[80];
                    delay_23_r[82] <= delay_23_r[81];
                    delay_23_r[83] <= delay_23_r[82];
                    delay_23_r[84] <= delay_23_r[83];
                    delay_23_r[85] <= delay_23_r[84];
                    delay_23_r[86] <= delay_23_r[85];
                    delay_23_r[87] <= delay_23_r[86];
                    delay_23_r[88] <= delay_23_r[87];
                    delay_23_r[89] <= delay_23_r[88];
                    delay_23_r[90] <= delay_23_r[89];
                    delay_23_r[91] <= delay_23_r[90];
                    delay_23_r[92] <= delay_23_r[91];
                    delay_23_r[93] <= delay_23_r[92];
                    delay_23_r[94] <= delay_23_r[93];
                    delay_23_r[95] <= delay_23_r[94];
                    delay_23_r[96] <= delay_23_r[95];
                    delay_23_r[97] <= delay_23_r[96];
                    delay_23_r[98] <= delay_23_r[97];
                    delay_23_r[99] <= delay_23_r[98];
                    delay_23_r[100] <= delay_23_r[99];
                    delay_23_r[101] <= delay_23_r[100];
                    delay_23_r[102] <= delay_23_r[101];
                    unused_green_rounded_r <= {1'b0, unused_green_raw_w[24 +: 8]}
                        + {8'b0, unused_green_raw_w[23]};
                    green_overflow_r <= unused_green_raw_w[69:32] != 0;
                    green_negative_r <= unused_green_raw_w[69];
                    green_clamped_r <= green_negative_r ? 8'b0 : (green_overflow_r
                        || unused_green_rounded_r[8]) ? 8'd255 : unused_green_rounded_r[7:0];
                    delay_24_r[0] <= green_clamped_r;
                    delay_24_r[1] <= delay_24_r[0];
                    delay_24_r[2] <= delay_24_r[1];
                    delay_24_r[3] <= delay_24_r[2];
                    delay_24_r[4] <= delay_24_r[3];
                    delay_24_r[5] <= delay_24_r[4];
                    delay_24_r[6] <= delay_24_r[5];
                    delay_24_r[7] <= delay_24_r[6];
                    delay_24_r[8] <= delay_24_r[7];
                    delay_24_r[9] <= delay_24_r[8];
                    delay_24_r[10] <= delay_24_r[9];
                    delay_24_r[11] <= delay_24_r[10];
                    delay_24_r[12] <= delay_24_r[11];
                    delay_24_r[13] <= delay_24_r[12];
                    delay_24_r[14] <= delay_24_r[13];
                    delay_24_r[15] <= delay_24_r[14];
                    delay_24_r[16] <= delay_24_r[15];
                    delay_24_r[17] <= delay_24_r[16];
                    delay_24_r[18] <= delay_24_r[17];
                    delay_24_r[19] <= delay_24_r[18];
                    delay_24_r[20] <= delay_24_r[19];
                    delay_24_r[21] <= delay_24_r[20];
                    delay_24_r[22] <= delay_24_r[21];
                    delay_24_r[23] <= delay_24_r[22];
                    delay_24_r[24] <= delay_24_r[23];
                    delay_24_r[25] <= delay_24_r[24];
                    delay_24_r[26] <= delay_24_r[25];
                    delay_24_r[27] <= delay_24_r[26];
                    delay_24_r[28] <= delay_24_r[27];
                    delay_24_r[29] <= delay_24_r[28];
                    delay_24_r[30] <= delay_24_r[29];
                    delay_24_r[31] <= delay_24_r[30];
                    delay_24_r[32] <= delay_24_r[31];
                    delay_24_r[33] <= delay_24_r[32];
                    delay_24_r[34] <= delay_24_r[33];
                    delay_24_r[35] <= delay_24_r[34];
                    delay_24_r[36] <= delay_24_r[35];
                    delay_24_r[37] <= delay_24_r[36];
                    delay_24_r[38] <= delay_24_r[37];
                    delay_24_r[39] <= delay_24_r[38];
                    delay_24_r[40] <= delay_24_r[39];
                    delay_24_r[41] <= delay_24_r[40];
                    delay_24_r[42] <= delay_24_r[41];
                    delay_24_r[43] <= delay_24_r[42];
                    delay_24_r[44] <= delay_24_r[43];
                    delay_24_r[45] <= delay_24_r[44];
                    delay_24_r[46] <= delay_24_r[45];
                    delay_24_r[47] <= delay_24_r[46];
                    delay_24_r[48] <= delay_24_r[47];
                    delay_24_r[49] <= delay_24_r[48];
                    delay_24_r[50] <= delay_24_r[49];
                    delay_24_r[51] <= delay_24_r[50];
                    delay_24_r[52] <= delay_24_r[51];
                    delay_24_r[53] <= delay_24_r[52];
                    delay_24_r[54] <= delay_24_r[53];
                    delay_24_r[55] <= delay_24_r[54];
                    delay_24_r[56] <= delay_24_r[55];
                    delay_24_r[57] <= delay_24_r[56];
                    delay_24_r[58] <= delay_24_r[57];
                    delay_24_r[59] <= delay_24_r[58];
                    delay_24_r[60] <= delay_24_r[59];
                    delay_24_r[61] <= delay_24_r[60];
                    delay_24_r[62] <= delay_24_r[61];
                    delay_24_r[63] <= delay_24_r[62];
                    delay_24_r[64] <= delay_24_r[63];
                    delay_24_r[65] <= delay_24_r[64];
                    delay_24_r[66] <= delay_24_r[65];
                    delay_24_r[67] <= delay_24_r[66];
                    delay_24_r[68] <= delay_24_r[67];
                    delay_24_r[69] <= delay_24_r[68];
                    delay_24_r[70] <= delay_24_r[69];
                    delay_24_r[71] <= delay_24_r[70];
                    delay_24_r[72] <= delay_24_r[71];
                    delay_24_r[73] <= delay_24_r[72];
                    delay_24_r[74] <= delay_24_r[73];
                    delay_24_r[75] <= delay_24_r[74];
                    delay_24_r[76] <= delay_24_r[75];
                    delay_24_r[77] <= delay_24_r[76];
                    delay_24_r[78] <= delay_24_r[77];
                    delay_24_r[79] <= delay_24_r[78];
                    delay_24_r[80] <= delay_24_r[79];
                    delay_24_r[81] <= delay_24_r[80];
                    delay_24_r[82] <= delay_24_r[81];
                    delay_24_r[83] <= delay_24_r[82];
                    delay_24_r[84] <= delay_24_r[83];
                    delay_24_r[85] <= delay_24_r[84];
                    delay_24_r[86] <= delay_24_r[85];
                    delay_24_r[87] <= delay_24_r[86];
                    delay_24_r[88] <= delay_24_r[87];
                    delay_24_r[89] <= delay_24_r[88];
                    delay_24_r[90] <= delay_24_r[89];
                    delay_24_r[91] <= delay_24_r[90];
                    delay_24_r[92] <= delay_24_r[91];
                    delay_24_r[93] <= delay_24_r[92];
                    delay_24_r[94] <= delay_24_r[93];
                    delay_24_r[95] <= delay_24_r[94];
                    delay_24_r[96] <= delay_24_r[95];
                    delay_24_r[97] <= delay_24_r[96];
                    delay_24_r[98] <= delay_24_r[97];
                    delay_24_r[99] <= delay_24_r[98];
                    delay_24_r[100] <= delay_24_r[99];
                    delay_24_r[101] <= delay_24_r[100];
                    delay_24_r[102] <= delay_24_r[101];
                    unused_blue_rounded_r <= {1'b0, unused_blue_raw_w[24 +: 8]}
                        + {8'b0, unused_blue_raw_w[23]};
                    blue_overflow_r <= unused_blue_raw_w[69:32] != 0;
                    blue_negative_r <= unused_blue_raw_w[69];
                    blue_clamped_r <= blue_negative_r ? 8'b0 : (blue_overflow_r
                        || unused_blue_rounded_r[8]) ? 8'd255 : unused_blue_rounded_r[7:0];
                    delay_25_r[0] <= blue_clamped_r;
                    delay_25_r[1] <= delay_25_r[0];
                    delay_25_r[2] <= delay_25_r[1];
                    delay_25_r[3] <= delay_25_r[2];
                    delay_25_r[4] <= delay_25_r[3];
                    delay_25_r[5] <= delay_25_r[4];
                    delay_25_r[6] <= delay_25_r[5];
                    delay_25_r[7] <= delay_25_r[6];
                    delay_25_r[8] <= delay_25_r[7];
                    delay_25_r[9] <= delay_25_r[8];
                    delay_25_r[10] <= delay_25_r[9];
                    delay_25_r[11] <= delay_25_r[10];
                    delay_25_r[12] <= delay_25_r[11];
                    delay_25_r[13] <= delay_25_r[12];
                    delay_25_r[14] <= delay_25_r[13];
                    delay_25_r[15] <= delay_25_r[14];
                    delay_25_r[16] <= delay_25_r[15];
                    delay_25_r[17] <= delay_25_r[16];
                    delay_25_r[18] <= delay_25_r[17];
                    delay_25_r[19] <= delay_25_r[18];
                    delay_25_r[20] <= delay_25_r[19];
                    delay_25_r[21] <= delay_25_r[20];
                    delay_25_r[22] <= delay_25_r[21];
                    delay_25_r[23] <= delay_25_r[22];
                    delay_25_r[24] <= delay_25_r[23];
                    delay_25_r[25] <= delay_25_r[24];
                    delay_25_r[26] <= delay_25_r[25];
                    delay_25_r[27] <= delay_25_r[26];
                    delay_25_r[28] <= delay_25_r[27];
                    delay_25_r[29] <= delay_25_r[28];
                    delay_25_r[30] <= delay_25_r[29];
                    delay_25_r[31] <= delay_25_r[30];
                    delay_25_r[32] <= delay_25_r[31];
                    delay_25_r[33] <= delay_25_r[32];
                    delay_25_r[34] <= delay_25_r[33];
                    delay_25_r[35] <= delay_25_r[34];
                    delay_25_r[36] <= delay_25_r[35];
                    delay_25_r[37] <= delay_25_r[36];
                    delay_25_r[38] <= delay_25_r[37];
                    delay_25_r[39] <= delay_25_r[38];
                    delay_25_r[40] <= delay_25_r[39];
                    delay_25_r[41] <= delay_25_r[40];
                    delay_25_r[42] <= delay_25_r[41];
                    delay_25_r[43] <= delay_25_r[42];
                    delay_25_r[44] <= delay_25_r[43];
                    delay_25_r[45] <= delay_25_r[44];
                    delay_25_r[46] <= delay_25_r[45];
                    delay_25_r[47] <= delay_25_r[46];
                    delay_25_r[48] <= delay_25_r[47];
                    delay_25_r[49] <= delay_25_r[48];
                    delay_25_r[50] <= delay_25_r[49];
                    delay_25_r[51] <= delay_25_r[50];
                    delay_25_r[52] <= delay_25_r[51];
                    delay_25_r[53] <= delay_25_r[52];
                    delay_25_r[54] <= delay_25_r[53];
                    delay_25_r[55] <= delay_25_r[54];
                    delay_25_r[56] <= delay_25_r[55];
                    delay_25_r[57] <= delay_25_r[56];
                    delay_25_r[58] <= delay_25_r[57];
                    delay_25_r[59] <= delay_25_r[58];
                    delay_25_r[60] <= delay_25_r[59];
                    delay_25_r[61] <= delay_25_r[60];
                    delay_25_r[62] <= delay_25_r[61];
                    delay_25_r[63] <= delay_25_r[62];
                    delay_25_r[64] <= delay_25_r[63];
                    delay_25_r[65] <= delay_25_r[64];
                    delay_25_r[66] <= delay_25_r[65];
                    delay_25_r[67] <= delay_25_r[66];
                    delay_25_r[68] <= delay_25_r[67];
                    delay_25_r[69] <= delay_25_r[68];
                    delay_25_r[70] <= delay_25_r[69];
                    delay_25_r[71] <= delay_25_r[70];
                    delay_25_r[72] <= delay_25_r[71];
                    delay_25_r[73] <= delay_25_r[72];
                    delay_25_r[74] <= delay_25_r[73];
                    delay_25_r[75] <= delay_25_r[74];
                    delay_25_r[76] <= delay_25_r[75];
                    delay_25_r[77] <= delay_25_r[76];
                    delay_25_r[78] <= delay_25_r[77];
                    delay_25_r[79] <= delay_25_r[78];
                    delay_25_r[80] <= delay_25_r[79];
                    delay_25_r[81] <= delay_25_r[80];
                    delay_25_r[82] <= delay_25_r[81];
                    delay_25_r[83] <= delay_25_r[82];
                    delay_25_r[84] <= delay_25_r[83];
                    delay_25_r[85] <= delay_25_r[84];
                    delay_25_r[86] <= delay_25_r[85];
                    delay_25_r[87] <= delay_25_r[86];
                    delay_25_r[88] <= delay_25_r[87];
                    delay_25_r[89] <= delay_25_r[88];
                    delay_25_r[90] <= delay_25_r[89];
                    delay_25_r[91] <= delay_25_r[90];
                    delay_25_r[92] <= delay_25_r[91];
                    delay_25_r[93] <= delay_25_r[92];
                    delay_25_r[94] <= delay_25_r[93];
                    delay_25_r[95] <= delay_25_r[94];
                    delay_25_r[96] <= delay_25_r[95];
                    delay_25_r[97] <= delay_25_r[96];
                    delay_25_r[98] <= delay_25_r[97];
                    delay_25_r[99] <= delay_25_r[98];
                    delay_25_r[100] <= delay_25_r[99];
                    delay_25_r[101] <= delay_25_r[100];
                    delay_25_r[102] <= delay_25_r[101];
                    delay_26_r[0] <= plane_w[2][30 +: 32];
                    delay_26_r[1] <= delay_26_r[0];
                    delay_26_r[2] <= delay_26_r[1];
                    delay_26_r[3] <= delay_26_r[2];
                    delay_26_r[4] <= delay_26_r[3];
                    delay_26_r[5] <= delay_26_r[4];
                    delay_26_r[6] <= delay_26_r[5];
                    delay_26_r[7] <= delay_26_r[6];
                    delay_26_r[8] <= delay_26_r[7];
                    delay_26_r[9] <= delay_26_r[8];
                    delay_26_r[10] <= delay_26_r[9];
                    delay_26_r[11] <= delay_26_r[10];
                    delay_26_r[12] <= delay_26_r[11];
                    delay_26_r[13] <= delay_26_r[12];
                    delay_26_r[14] <= delay_26_r[13];
                    delay_26_r[15] <= delay_26_r[14];
                    delay_26_r[16] <= delay_26_r[15];
                    delay_26_r[17] <= delay_26_r[16];
                    delay_26_r[18] <= delay_26_r[17];
                    delay_26_r[19] <= delay_26_r[18];
                    delay_26_r[20] <= delay_26_r[19];
                    delay_26_r[21] <= delay_26_r[20];
                    delay_26_r[22] <= delay_26_r[21];
                    delay_26_r[23] <= delay_26_r[22];
                    delay_26_r[24] <= delay_26_r[23];
                    delay_26_r[25] <= delay_26_r[24];
                    delay_26_r[26] <= delay_26_r[25];
                    delay_26_r[27] <= delay_26_r[26];
                    delay_26_r[28] <= delay_26_r[27];
                    delay_26_r[29] <= delay_26_r[28];
                    delay_26_r[30] <= delay_26_r[29];
                    delay_26_r[31] <= delay_26_r[30];
                    delay_26_r[32] <= delay_26_r[31];
                    delay_26_r[33] <= delay_26_r[32];
                    delay_26_r[34] <= delay_26_r[33];
                    delay_26_r[35] <= delay_26_r[34];
                    delay_26_r[36] <= delay_26_r[35];
                    delay_26_r[37] <= delay_26_r[36];
                    delay_26_r[38] <= delay_26_r[37];
                    delay_26_r[39] <= delay_26_r[38];
                    delay_26_r[40] <= delay_26_r[39];
                    delay_26_r[41] <= delay_26_r[40];
                    delay_26_r[42] <= delay_26_r[41];
                    delay_26_r[43] <= delay_26_r[42];
                    delay_26_r[44] <= delay_26_r[43];
                    delay_26_r[45] <= delay_26_r[44];
                    delay_26_r[46] <= delay_26_r[45];
                    delay_26_r[47] <= delay_26_r[46];
                    delay_26_r[48] <= delay_26_r[47];
                    delay_26_r[49] <= delay_26_r[48];
                    delay_26_r[50] <= delay_26_r[49];
                    delay_26_r[51] <= delay_26_r[50];
                    delay_26_r[52] <= delay_26_r[51];
                    delay_26_r[53] <= delay_26_r[52];
                    delay_26_r[54] <= delay_26_r[53];
                    delay_26_r[55] <= delay_26_r[54];
                    delay_26_r[56] <= delay_26_r[55];
                    delay_26_r[57] <= delay_26_r[56];
                    delay_26_r[58] <= delay_26_r[57];
                    delay_26_r[59] <= delay_26_r[58];
                    delay_26_r[60] <= delay_26_r[59];
                    delay_26_r[61] <= delay_26_r[60];
                    delay_26_r[62] <= delay_26_r[61];
                    delay_26_r[63] <= delay_26_r[62];
                    delay_26_r[64] <= delay_26_r[63];
                    delay_26_r[65] <= delay_26_r[64];
                    delay_26_r[66] <= delay_26_r[65];
                    delay_26_r[67] <= delay_26_r[66];
                    delay_26_r[68] <= delay_26_r[67];
                    delay_26_r[69] <= delay_26_r[68];
                    delay_26_r[70] <= delay_26_r[69];
                    delay_26_r[71] <= delay_26_r[70];
                    delay_26_r[72] <= delay_26_r[71];
                    delay_26_r[73] <= delay_26_r[72];
                    delay_26_r[74] <= delay_26_r[73];
                    delay_26_r[75] <= delay_26_r[74];
                    delay_26_r[76] <= delay_26_r[75];
                    delay_26_r[77] <= delay_26_r[76];
                    delay_26_r[78] <= delay_26_r[77];
                    delay_26_r[79] <= delay_26_r[78];
                    delay_26_r[80] <= delay_26_r[79];
                    delay_26_r[81] <= delay_26_r[80];
                    delay_26_r[82] <= delay_26_r[81];
                    delay_26_r[83] <= delay_26_r[82];
                    delay_26_r[84] <= delay_26_r[83];
                    delay_26_r[85] <= delay_26_r[84];
                    delay_26_r[86] <= delay_26_r[85];
                    delay_26_r[87] <= delay_26_r[86];
                    delay_26_r[88] <= delay_26_r[87];
                    delay_26_r[89] <= delay_26_r[88];
                    delay_26_r[90] <= delay_26_r[89];
                    delay_26_r[91] <= delay_26_r[90];
                    delay_26_r[92] <= delay_26_r[91];
                    delay_26_r[93] <= delay_26_r[92];
                    delay_26_r[94] <= delay_26_r[93];
                    delay_26_r[95] <= delay_26_r[94];
                    delay_26_r[96] <= delay_26_r[95];
                    delay_26_r[97] <= delay_26_r[96];
                    delay_26_r[98] <= delay_26_r[97];
                    delay_26_r[99] <= delay_26_r[98];
                    delay_26_r[100] <= delay_26_r[99];
                    delay_26_r[101] <= delay_26_r[100];
                    delay_26_r[102] <= delay_26_r[101];
                    delay_26_r[103] <= delay_26_r[102];
                    delay_26_r[104] <= delay_26_r[103];
                    delay_27_r[0] <= plane_w[3][30 +: 32];
                    delay_27_r[1] <= delay_27_r[0];
                    delay_27_r[2] <= delay_27_r[1];
                    delay_27_r[3] <= delay_27_r[2];
                    delay_27_r[4] <= delay_27_r[3];
                    delay_27_r[5] <= delay_27_r[4];
                    delay_27_r[6] <= delay_27_r[5];
                    delay_27_r[7] <= delay_27_r[6];
                    delay_27_r[8] <= delay_27_r[7];
                    delay_27_r[9] <= delay_27_r[8];
                    delay_27_r[10] <= delay_27_r[9];
                    delay_27_r[11] <= delay_27_r[10];
                    delay_27_r[12] <= delay_27_r[11];
                    delay_27_r[13] <= delay_27_r[12];
                    delay_27_r[14] <= delay_27_r[13];
                    delay_27_r[15] <= delay_27_r[14];
                    delay_27_r[16] <= delay_27_r[15];
                    delay_27_r[17] <= delay_27_r[16];
                    delay_27_r[18] <= delay_27_r[17];
                    delay_27_r[19] <= delay_27_r[18];
                    delay_27_r[20] <= delay_27_r[19];
                    delay_27_r[21] <= delay_27_r[20];
                    delay_27_r[22] <= delay_27_r[21];
                    delay_27_r[23] <= delay_27_r[22];
                    delay_27_r[24] <= delay_27_r[23];
                    delay_27_r[25] <= delay_27_r[24];
                    delay_27_r[26] <= delay_27_r[25];
                    delay_27_r[27] <= delay_27_r[26];
                    delay_27_r[28] <= delay_27_r[27];
                    delay_27_r[29] <= delay_27_r[28];
                    delay_27_r[30] <= delay_27_r[29];
                    delay_27_r[31] <= delay_27_r[30];
                    delay_27_r[32] <= delay_27_r[31];
                    delay_27_r[33] <= delay_27_r[32];
                    delay_27_r[34] <= delay_27_r[33];
                    delay_27_r[35] <= delay_27_r[34];
                    delay_27_r[36] <= delay_27_r[35];
                    delay_27_r[37] <= delay_27_r[36];
                    delay_27_r[38] <= delay_27_r[37];
                    delay_27_r[39] <= delay_27_r[38];
                    delay_27_r[40] <= delay_27_r[39];
                    delay_27_r[41] <= delay_27_r[40];
                    delay_27_r[42] <= delay_27_r[41];
                    delay_27_r[43] <= delay_27_r[42];
                    delay_27_r[44] <= delay_27_r[43];
                    delay_27_r[45] <= delay_27_r[44];
                    delay_27_r[46] <= delay_27_r[45];
                    delay_27_r[47] <= delay_27_r[46];
                    delay_27_r[48] <= delay_27_r[47];
                    delay_27_r[49] <= delay_27_r[48];
                    delay_27_r[50] <= delay_27_r[49];
                    delay_27_r[51] <= delay_27_r[50];
                    delay_27_r[52] <= delay_27_r[51];
                    delay_27_r[53] <= delay_27_r[52];
                    delay_27_r[54] <= delay_27_r[53];
                    delay_27_r[55] <= delay_27_r[54];
                    delay_27_r[56] <= delay_27_r[55];
                    delay_27_r[57] <= delay_27_r[56];
                    delay_27_r[58] <= delay_27_r[57];
                    delay_27_r[59] <= delay_27_r[58];
                    delay_27_r[60] <= delay_27_r[59];
                    delay_27_r[61] <= delay_27_r[60];
                    delay_27_r[62] <= delay_27_r[61];
                    delay_27_r[63] <= delay_27_r[62];
                    delay_27_r[64] <= delay_27_r[63];
                    delay_27_r[65] <= delay_27_r[64];
                    delay_27_r[66] <= delay_27_r[65];
                    delay_27_r[67] <= delay_27_r[66];
                    delay_27_r[68] <= delay_27_r[67];
                    delay_27_r[69] <= delay_27_r[68];
                    delay_27_r[70] <= delay_27_r[69];
                    delay_27_r[71] <= delay_27_r[70];
                    delay_27_r[72] <= delay_27_r[71];
                    delay_27_r[73] <= delay_27_r[72];
                    delay_27_r[74] <= delay_27_r[73];
                    delay_27_r[75] <= delay_27_r[74];
                    delay_27_r[76] <= delay_27_r[75];
                    delay_27_r[77] <= delay_27_r[76];
                    delay_27_r[78] <= delay_27_r[77];
                    delay_27_r[79] <= delay_27_r[78];
                    delay_27_r[80] <= delay_27_r[79];
                    delay_27_r[81] <= delay_27_r[80];
                    delay_27_r[82] <= delay_27_r[81];
                    delay_27_r[83] <= delay_27_r[82];
                    delay_27_r[84] <= delay_27_r[83];
                    delay_27_r[85] <= delay_27_r[84];
                    delay_27_r[86] <= delay_27_r[85];
                    delay_27_r[87] <= delay_27_r[86];
                    delay_27_r[88] <= delay_27_r[87];
                    delay_27_r[89] <= delay_27_r[88];
                    delay_27_r[90] <= delay_27_r[89];
                    delay_27_r[91] <= delay_27_r[90];
                    delay_27_r[92] <= delay_27_r[91];
                    delay_27_r[93] <= delay_27_r[92];
                    delay_27_r[94] <= delay_27_r[93];
                    delay_27_r[95] <= delay_27_r[94];
                    delay_27_r[96] <= delay_27_r[95];
                    delay_27_r[97] <= delay_27_r[96];
                    delay_27_r[98] <= delay_27_r[97];
                    delay_27_r[99] <= delay_27_r[98];
                    delay_27_r[100] <= delay_27_r[99];
                    delay_27_r[101] <= delay_27_r[100];
                    delay_27_r[102] <= delay_27_r[101];
                    delay_27_r[103] <= delay_27_r[102];
                    delay_27_r[104] <= delay_27_r[103];
                end
                if (output_push_w) begin
                    output_u_r[output_write_r] <= pipe_quad_w ?
                        bypass_u_w : delay_7_r[52];
                    output_v_r[output_write_r] <= pipe_quad_w ?
                        bypass_v_w : delay_9_r[52];
                    output_span_r[output_write_r] <= pipe_quad_w ?
                        96'b0 : span_w;
                    output_depth_r[output_write_r] <= final_depth_w;
                    output_color_r[output_write_r] <=
                        {final_blue_w, final_green_w, final_red_w};
                end
            end
        end
    endgenerate
endmodule
