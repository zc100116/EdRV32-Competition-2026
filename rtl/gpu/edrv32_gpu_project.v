// File: edrv32_gpu_project.v
// Spec: gpu-spec 2.4, 2.12; GPU microarchitecture 4.3.
// Description: Q30 perspective division with full coordinate and viewport products.
//              Only the final screen coordinate and depth conversions round and saturate.
//              24 reciprocal stages + 50 projection stages + one output FIFO write, II=1.
// Clock domain: clk_gpu.
module edrv32_gpu_project (
    // Clock and reset.
    input wire clk_i,
    input wire rst_n_i,

    // Clipped vertex with stable viewport.
    input wire clipped_valid_i,
    output wire clipped_ready_o,
    input wire [263:0] clipped_data_i,
    input wire [63:0] viewport_i,

    // Screen vertex: x/y/depth/q/uq/vq/RGB, low fields first.
    output wire projected_valid_o,
    input wire projected_ready_i,
    output wire [258:0] projected_data_o,

    // Drain control.
    input wire stop_i,
    output wire idle_o
);
    reg [30:0] reciprocal_input_r;
    reg [5:0] restore_exponent_r;
    reg [5:0] restore_right_r;
    reg [5:0] restore_left_r;
    reg [5:0] restore_bit_r;
    reg [39:0] restore_bias_r;
    wire [39:0] reciprocal40_w;
    reg [39:0] reciprocal40_w_d1_r;
    reg [39:0] reciprocal40_w_d2_r;
    reg [39:0] reciprocal40_w_d3_r;
    wire [34:0] restore_round_a0_w;
    wire [34:0] restore_round_b0_w;
    reg [35:0] restore_round_part0_r;
    wire [34:0] restore_round_low0_w;
    wire [4:0] restore_round_a1_w;
    wire [4:0] restore_round_b1_w;
    reg [4:0] restore_round_a1_w_d4_r;
    reg [4:0] restore_round_b1_w_d4_r;
    reg [5:0] unused_restore_round_part1_r;
    wire [4:0] restore_round_low1_w;
    wire [39:0] restore_round_w;
    reg [34:0] restore_round_low0_w_d5_r;
    wire [1:0] restore_shift_right_amt0_w;
    reg [39:0] restore_shift_right_0_w;
    reg [1:0] restore_shift_right_amt0_w_d2_r;
    reg [1:0] restore_shift_right_amt0_w_d3_r;
    reg [1:0] restore_shift_right_amt0_w_d4_r;
    reg [1:0] restore_shift_right_amt0_w_d5_r;
    reg [39:0] restore_shift_right_0_r;
    wire [1:0] restore_shift_right_amt1_w;
    reg [39:0] restore_shift_right_1_w;
    reg [1:0] restore_shift_right_amt1_w_d2_r;
    reg [1:0] restore_shift_right_amt1_w_d3_r;
    reg [1:0] restore_shift_right_amt1_w_d4_r;
    reg [1:0] restore_shift_right_amt1_w_d5_r;
    reg [1:0] restore_shift_right_amt1_w_d6_r;
    reg [39:0] restore_shift_right_1_r;
    wire [1:0] restore_shift_right_amt2_w;
    reg [39:0] restore_shift_right_2_w;
    reg [1:0] restore_shift_right_amt2_w_d2_r;
    reg [1:0] restore_shift_right_amt2_w_d3_r;
    reg [1:0] restore_shift_right_amt2_w_d4_r;
    reg [1:0] restore_shift_right_amt2_w_d5_r;
    reg [1:0] restore_shift_right_amt2_w_d6_r;
    reg [1:0] restore_shift_right_amt2_w_d7_r;
    reg [39:0] unused_restore_shift_right_2_r;
    wire [1:0] restore_shift_left_amt0_w;
    reg [39:0] restore_shift_left_0_w;
    reg [39:0] restore_shift_left_0_r;
    wire [1:0] restore_shift_left_amt1_w;
    reg [39:0] restore_shift_left_1_w;
    reg [1:0] restore_shift_left_amt1_w_d2_r;
    reg [39:0] restore_shift_left_1_r;
    wire [1:0] restore_shift_left_amt2_w;
    reg [39:0] restore_shift_left_2_w;
    reg [1:0] restore_shift_left_amt2_w_d2_r;
    reg [1:0] restore_shift_left_amt2_w_d3_r;
    reg [39:0] restore_shift_left_2_r;
    reg [5:0] restore_exponent_r_d1_r;
    reg [5:0] restore_exponent_r_d2_r;
    reg [5:0] restore_exponent_r_d3_r;
    reg [5:0] restore_exponent_r_d4_r;
    reg [5:0] restore_exponent_r_d5_r;
    reg [5:0] restore_exponent_r_d6_r;
    reg [5:0] restore_exponent_r_d7_r;
    reg [5:0] restore_exponent_r_d8_r;
    reg [39:0] restore_shift_left_2_r_d5_r;
    reg [39:0] restore_shift_left_2_r_d6_r;
    reg [39:0] restore_shift_left_2_r_d7_r;
    reg [39:0] unused_restore_shift_left_2_r_d8_r;
    reg [34:0] restored_r;
    reg [39:0] position_input0_r;
    reg [39:0] position_input1_r;
    reg [39:0] position_input2_r;
    reg [15:0] uv_input0_r;
    reg [15:0] uv_input1_r;

    wire [74:0] position_product0_p2_r;

    wire [74:0] position_product1_p2_r;

    wire [74:0] position_product2_p2_r;

    wire [50:0] uv_product0_p2_r;

    wire [50:0] uv_product1_p2_r;
    wire [93:0] position_ext0_w;
    wire [93:0] viewport_one0_w;
    wire [34:0] viewport_adjust0_a0_w;
    wire [34:0] viewport_adjust0_b0_w;
    reg [35:0] viewport_adjust0_part0_r;
    wire [34:0] viewport_adjust0_low0_w;
    wire [34:0] viewport_adjust0_a1_w;
    wire [34:0] viewport_adjust0_b1_w;
    reg [34:0] viewport_adjust0_a1_w_d13_r;
    reg [35:0] viewport_adjust0_part1_r;
    wire [34:0] viewport_adjust0_low1_w;
    wire [23:0] viewport_adjust0_a2_w;
    wire [23:0] viewport_adjust0_b2_w;
    reg [23:0] viewport_adjust0_a2_w_d13_r;
    reg [23:0] viewport_adjust0_a2_w_d14_r;
    reg [24:0] unused_viewport_adjust0_part2_r;
    wire [23:0] viewport_adjust0_low2_w;
    wire [93:0] viewport_adjust0_w;
    reg [34:0] viewport_adjust0_low1_w_d15_r;
    reg [34:0] viewport_adjust0_low0_w_d14_r;
    reg [34:0] viewport_adjust0_low0_w_d15_r;
    reg [15:0] viewport_size0_r;

    wire [93:0] viewport_product0_p2_r;
    reg [93:0] viewport_shift0_r;
    wire [93:0] position_ext1_w;
    wire [93:0] viewport_one1_w;
    reg [93:0] position_negative_r;
    wire [93:0] position_negate_one_w;
    wire [34:0] position_negate_a0_w;
    wire [34:0] position_negate_b0_w;
    reg [35:0] position_negate_part0_r;
    wire [34:0] position_negate_low0_w;
    wire [34:0] position_negate_a1_w;
    wire [34:0] position_negate_b1_w;
    reg [34:0] position_negate_a1_w_d14_r;
    reg [35:0] position_negate_part1_r;
    wire [34:0] position_negate_low1_w;
    wire [23:0] position_negate_a2_w;
    wire [23:0] position_negate_b2_w;
    reg [23:0] position_negate_a2_w_d14_r;
    reg [23:0] position_negate_a2_w_d15_r;
    reg [24:0] unused_position_negate_part2_r;
    wire [23:0] position_negate_low2_w;
    wire [93:0] position_negate_w;
    reg [34:0] position_negate_low1_w_d16_r;
    reg [34:0] position_negate_low0_w_d15_r;
    reg [34:0] position_negate_low0_w_d16_r;
    wire [34:0] viewport_adjust1_a0_w;
    wire [34:0] viewport_adjust1_b0_w;
    reg [35:0] viewport_adjust1_part0_r;
    wire [34:0] viewport_adjust1_low0_w;
    wire [34:0] viewport_adjust1_a1_w;
    wire [34:0] viewport_adjust1_b1_w;
    reg [34:0] viewport_adjust1_b1_w_d17_r;
    reg [35:0] viewport_adjust1_part1_r;
    wire [34:0] viewport_adjust1_low1_w;
    wire [23:0] viewport_adjust1_a2_w;
    wire [23:0] viewport_adjust1_b2_w;
    reg [23:0] viewport_adjust1_b2_w_d17_r;
    reg [23:0] viewport_adjust1_b2_w_d18_r;
    reg [24:0] unused_viewport_adjust1_part2_r;
    wire [23:0] viewport_adjust1_low2_w;
    wire [93:0] viewport_adjust1_w;
    reg [34:0] viewport_adjust1_low1_w_d19_r;
    reg [34:0] viewport_adjust1_low0_w_d18_r;
    reg [34:0] viewport_adjust1_low0_w_d19_r;
    reg [15:0] viewport_size1_r;

    wire [93:0] viewport_product1_p2_r;
    reg [93:0] viewport_shift1_r;
    wire [93:0] position_ext2_w;
    wire [93:0] depth_left_w;
    reg [93:0] depth_invert_r;
    wire [93:0] depth_one_w;
    wire [34:0] depth_negate_a0_w;
    wire [34:0] depth_negate_b0_w;
    reg [35:0] depth_negate_part0_r;
    wire [34:0] depth_negate_low0_w;
    wire [34:0] depth_negate_a1_w;
    wire [34:0] depth_negate_b1_w;
    reg [34:0] depth_negate_a1_w_d14_r;
    reg [35:0] depth_negate_part1_r;
    wire [34:0] depth_negate_low1_w;
    wire [23:0] depth_negate_a2_w;
    wire [23:0] depth_negate_b2_w;
    reg [23:0] depth_negate_a2_w_d14_r;
    reg [23:0] depth_negate_a2_w_d15_r;
    reg [24:0] unused_depth_negate_part2_r;
    wire [23:0] depth_negate_low2_w;
    wire [93:0] depth_negate_w;
    reg [34:0] depth_negate_low1_w_d16_r;
    reg [34:0] depth_negate_low0_w_d15_r;
    reg [34:0] depth_negate_low0_w_d16_r;
    reg [93:0] depth_left_w_d13_r;
    reg [93:0] depth_left_w_d14_r;
    reg [93:0] depth_left_w_d15_r;
    reg [93:0] depth_left_w_d16_r;
    wire [34:0] depth_subtract_a0_w;
    wire [34:0] depth_subtract_b0_w;
    reg [35:0] depth_subtract_part0_r;
    wire [34:0] depth_subtract_low0_w;
    wire [34:0] depth_subtract_a1_w;
    wire [34:0] depth_subtract_b1_w;
    reg [34:0] depth_subtract_a1_w_d17_r;
    reg [34:0] depth_subtract_b1_w_d17_r;
    reg [35:0] depth_subtract_part1_r;
    wire [34:0] depth_subtract_low1_w;
    wire [23:0] depth_subtract_a2_w;
    wire [23:0] depth_subtract_b2_w;
    reg [23:0] depth_subtract_a2_w_d17_r;
    reg [23:0] depth_subtract_a2_w_d18_r;
    reg [23:0] depth_subtract_b2_w_d17_r;
    reg [23:0] depth_subtract_b2_w_d18_r;
    reg [24:0] unused_depth_subtract_part2_r;
    wire [23:0] depth_subtract_low2_w;
    wire [93:0] depth_subtract_w;
    reg [34:0] depth_subtract_low1_w_d19_r;
    reg [34:0] depth_subtract_low0_w_d18_r;
    reg [34:0] depth_subtract_low0_w_d19_r;
    reg [0:0] screen_abs0_sign_r;
    reg [93:0] screen_abs0_invert_r;
    wire [93:0] screen_abs0_carry_w;
    wire [34:0] screen_abs0_a0_w;
    wire [34:0] screen_abs0_b0_w;
    reg [35:0] screen_abs0_part0_r;
    wire [34:0] screen_abs0_low0_w;
    wire [34:0] screen_abs0_a1_w;
    wire [34:0] screen_abs0_b1_w;
    reg [34:0] screen_abs0_a1_w_d21_r;
    reg [34:0] screen_abs0_b1_w_d21_r;
    reg [35:0] screen_abs0_part1_r;
    wire [34:0] screen_abs0_low1_w;
    wire [23:0] screen_abs0_a2_w;
    wire [23:0] screen_abs0_b2_w;
    reg [23:0] screen_abs0_a2_w_d21_r;
    reg [23:0] screen_abs0_a2_w_d22_r;
    reg [23:0] screen_abs0_b2_w_d21_r;
    reg [23:0] screen_abs0_b2_w_d22_r;
    reg [24:0] unused_screen_abs0_part2_r;
    wire [23:0] screen_abs0_low2_w;
    wire [93:0] unused_screen_abs0_w;
    reg [34:0] screen_abs0_low1_w_d23_r;
    reg [34:0] screen_abs0_low0_w_d22_r;
    reg [34:0] screen_abs0_low0_w_d23_r;
    wire [48:0] screen_high0_w;
    wire [48:0] screen_bit0_w;
    wire [34:0] screen_round0_a0_w;
    wire [34:0] screen_round0_b0_w;
    reg [35:0] screen_round0_part0_r;
    wire [34:0] screen_round0_low0_w;
    wire [13:0] screen_round0_a1_w;
    wire [13:0] screen_round0_b1_w;
    reg [13:0] screen_round0_a1_w_d24_r;
    reg [13:0] screen_round0_b1_w_d24_r;
    reg [14:0] unused_screen_round0_part1_r;
    wire [13:0] screen_round0_low1_w;
    wire [48:0] screen_round0_w;
    reg [34:0] screen_round0_low0_w_d25_r;
    reg [0:0] screen_abs0_sign_d21_r;
    reg [0:0] screen_abs0_sign_d22_r;
    reg [0:0] screen_abs0_sign_d23_r;
    reg [0:0] screen_abs0_sign_d24_r;
    reg [0:0] screen_abs0_sign_d25_r;
    reg [48:0] screen_signed0_invert_r;
    reg [0:0] screen_abs0_sign_d26_r;
    wire [48:0] screen_signed0_carry_w;
    wire [34:0] screen_signed0_a0_w;
    wire [34:0] screen_signed0_b0_w;
    reg [35:0] screen_signed0_part0_r;
    wire [34:0] screen_signed0_low0_w;
    wire [13:0] screen_signed0_a1_w;
    wire [13:0] screen_signed0_b1_w;
    reg [13:0] screen_signed0_a1_w_d27_r;
    reg [13:0] screen_signed0_b1_w_d27_r;
    reg [14:0] unused_screen_signed0_part1_r;
    wire [13:0] screen_signed0_low1_w;
    wire [48:0] screen_signed0_w;
    reg [34:0] screen_signed0_low0_w_d28_r;
    reg [15:0] viewport_offset0_r;
    wire [34:0] screen_offset0_a0_w;
    reg [35:0] screen_offset0_part0_r;
    wire [34:0] screen_offset0_low0_w;
    wire [13:0] screen_offset0_a1_w;
    reg [13:0] screen_offset0_a1_w_d29_r;
    reg [14:0] unused_screen_offset0_part1_r;
    wire [13:0] screen_offset0_low1_w;
    wire [48:0] screen_offset0_w;
    reg [34:0] screen_offset0_low0_w_d30_r;
    reg [16:0] screen_clamp0_r;
    reg [0:0] screen_abs1_sign_r;
    reg [93:0] screen_abs1_invert_r;
    wire [93:0] screen_abs1_carry_w;
    wire [34:0] screen_abs1_a0_w;
    wire [34:0] screen_abs1_b0_w;
    reg [35:0] screen_abs1_part0_r;
    wire [34:0] screen_abs1_low0_w;
    wire [34:0] screen_abs1_a1_w;
    wire [34:0] screen_abs1_b1_w;
    reg [34:0] screen_abs1_a1_w_d25_r;
    reg [34:0] screen_abs1_b1_w_d25_r;
    reg [35:0] screen_abs1_part1_r;
    wire [34:0] screen_abs1_low1_w;
    wire [23:0] screen_abs1_a2_w;
    wire [23:0] screen_abs1_b2_w;
    reg [23:0] screen_abs1_a2_w_d25_r;
    reg [23:0] screen_abs1_a2_w_d26_r;
    reg [23:0] screen_abs1_b2_w_d25_r;
    reg [23:0] screen_abs1_b2_w_d26_r;
    reg [24:0] unused_screen_abs1_part2_r;
    wire [23:0] screen_abs1_low2_w;
    wire [93:0] unused_screen_abs1_w;
    reg [34:0] screen_abs1_low1_w_d27_r;
    reg [34:0] screen_abs1_low0_w_d26_r;
    reg [34:0] screen_abs1_low0_w_d27_r;
    wire [48:0] screen_high1_w;
    wire [48:0] screen_bit1_w;
    wire [34:0] screen_round1_a0_w;
    wire [34:0] screen_round1_b0_w;
    reg [35:0] screen_round1_part0_r;
    wire [34:0] screen_round1_low0_w;
    wire [13:0] screen_round1_a1_w;
    wire [13:0] screen_round1_b1_w;
    reg [13:0] screen_round1_a1_w_d28_r;
    reg [13:0] screen_round1_b1_w_d28_r;
    reg [14:0] unused_screen_round1_part1_r;
    wire [13:0] screen_round1_low1_w;
    wire [48:0] screen_round1_w;
    reg [34:0] screen_round1_low0_w_d29_r;
    reg [0:0] screen_abs1_sign_d25_r;
    reg [0:0] screen_abs1_sign_d26_r;
    reg [0:0] screen_abs1_sign_d27_r;
    reg [0:0] screen_abs1_sign_d28_r;
    reg [0:0] screen_abs1_sign_d29_r;
    reg [48:0] screen_signed1_invert_r;
    reg [0:0] screen_abs1_sign_d30_r;
    wire [48:0] screen_signed1_carry_w;
    wire [34:0] screen_signed1_a0_w;
    wire [34:0] screen_signed1_b0_w;
    reg [35:0] screen_signed1_part0_r;
    wire [34:0] screen_signed1_low0_w;
    wire [13:0] screen_signed1_a1_w;
    wire [13:0] screen_signed1_b1_w;
    reg [13:0] screen_signed1_a1_w_d31_r;
    reg [13:0] screen_signed1_b1_w_d31_r;
    reg [14:0] unused_screen_signed1_part1_r;
    wire [13:0] screen_signed1_low1_w;
    wire [48:0] screen_signed1_w;
    reg [34:0] screen_signed1_low0_w_d32_r;
    reg [15:0] viewport_offset1_r;
    wire [34:0] screen_offset1_a0_w;
    reg [35:0] screen_offset1_part0_r;
    wire [34:0] screen_offset1_low0_w;
    wire [13:0] screen_offset1_a1_w;
    reg [13:0] screen_offset1_a1_w_d33_r;
    reg [14:0] unused_screen_offset1_part1_r;
    wire [13:0] screen_offset1_low1_w;
    wire [48:0] screen_offset1_w;
    reg [34:0] screen_offset1_low0_w_d34_r;
    reg [16:0] screen_clamp1_r;
    wire [48:0] depth_high_w;
    wire [48:0] depth_bit_w;
    wire [34:0] depth_round_a0_w;
    wire [34:0] depth_round_b0_w;
    reg [35:0] depth_round_part0_r;
    wire [34:0] depth_round_low0_w;
    wire [13:0] depth_round_a1_w;
    wire [13:0] depth_round_b1_w;
    reg [13:0] depth_round_a1_w_d20_r;
    reg [13:0] depth_round_b1_w_d20_r;
    reg [14:0] unused_depth_round_part1_r;
    wire [13:0] depth_round_low1_w;
    wire [48:0] depth_round_w;
    reg [34:0] depth_round_low0_w_d21_r;
    reg [93:0] depth_subtract_w_d20_r;
    reg [93:0] unused_depth_subtract_w_d21_r;
    reg [15:0] depth_clamp_r;
    reg [16:0] screen_clamp0_d32_r;
    reg [16:0] screen_clamp0_d33_r;
    reg [16:0] screen_clamp0_d34_r;
    reg [16:0] screen_clamp0_d35_r;
    reg [16:0] output_0_r [0:1];
    reg [16:0] output_1_r [0:1];
    reg [15:0] output_2_r [0:1];
    reg [34:0] output_3_r [0:1];
    reg [50:0] output_4_r [0:1];
    reg [50:0] output_5_r [0:1];
    reg [71:0] output_6_r [0:1];
    reg [49:0] valid_r;
    reg [23:0] input_valid_r;
    reg [1:0] count_r;
    reg read_r;
    reg write_r;
    wire enable_w;
    // Independent occupancy replicas keep the common datapath CE local (microarch 4.14).
    wire [2:0] control_enable_w;
    genvar control_region;
    generate
        for (control_region = 0; control_region < 3;
            control_region = control_region + 1) begin : g_control_enable
            (* keep = "true", syn_preserve = 1 *) reg [1:0] occupancy_r;
            assign control_enable_w[control_region] = occupancy_r != 2 && !stop_i;
            always @(posedge clk_i or negedge rst_n_i) begin
                if (!rst_n_i) occupancy_r <= 0;
                else if (stop_i) occupancy_r <= 0;
                else begin
                    case ({push_w, pop_w})
                        2'b10: occupancy_r <= occupancy_r + 2'd1;
                        2'b01: occupancy_r <= occupancy_r - 2'd1;
                        default: occupancy_r <= occupancy_r;
                    endcase
                end
            end
        end
    endgenerate

    wire accept_w;
    wire push_w;
    wire pop_w;
    wire reciprocal_valid_w;
    wire [30:0] reciprocal_w;
    wire [5:0] exponent_w;
    reg [5:0] input_delay_write_r;
    wire [5:0] input_delay_read_w;
    wire [223:0] input_prefix_w;
    wire [287:0] unused_input_delay_w;
    wire [39:0] position_input_w [0:2];
    wire [15:0] uv_input_w [0:1];
    wire [71:0] color_input_w;
    assign enable_w = count_r != 2 && !stop_i;
    assign clipped_ready_o = enable_w;
    assign accept_w = clipped_valid_i && clipped_ready_o;
    assign projected_valid_o = count_r != 0;
    assign push_w = enable_w && valid_r[49];
    assign pop_w = projected_valid_o && projected_ready_i;
    assign idle_o = count_r == 0 && valid_r == 0 && !reciprocal_valid_w && input_valid_r == 0;
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            valid_r <= 0;
            input_valid_r <= 0;
            count_r <= 0;
            read_r <= 0;
            write_r <= 0;
        end else if (stop_i) begin
            valid_r <= 0;
            input_valid_r <= 0;
            count_r <= 0;
            read_r <= 0;
            write_r <= 0;
        end else begin
            if (control_enable_w[0]) begin
                valid_r <= {valid_r[48:0], reciprocal_valid_w};
                input_valid_r <= {input_valid_r[22:0], accept_w};
            end
            if (push_w) write_r <= !write_r;
            if (pop_w) read_r <= !read_r;
            case ({push_w, pop_w})
                2'b10: count_r <= count_r + 1'b1;
                2'b01: count_r <= count_r - 1'b1;
                default: count_r <= count_r;
            endcase
        end
    end
    edrv32_gpu_project_recip u_reciprocal (
        .clk_i(clk_i),
        .rst_n_i(rst_n_i),
        .enable_i(control_enable_w[1]),
        .stop_i(stop_i),
        .value_valid_i(accept_w),
        .value_i(clipped_data_i[159:120]),
        .value_valid_o(reciprocal_valid_w),
        .reciprocal_o(reciprocal_w),
        .exponent_o(exponent_w)
    );

    // Payload latency is 1+24; reciprocal metadata uses the same 24-cycle alignment.
    assign input_delay_read_w = input_delay_write_r - 6'd23;
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) input_delay_write_r <= 0;
        else if (control_enable_w[2]) input_delay_write_r <= input_delay_write_r + 1'b1;
    end
    wire [71:0] u_input_delay_0_data_w;
    reg [71:0] u_input_delay_0_data_r;
    assign unused_input_delay_w[0 +: 72] = u_input_delay_0_data_r;
    always @(posedge clk_i) begin
        if (control_enable_w[0]) u_input_delay_0_data_r <= u_input_delay_0_data_w;
    end
    edrv32_ram_gpu_table u_input_delay_0 (
        .clk_i(clk_i),
        .wr_en_i(control_enable_w[1]),
        .wr_addr_i(input_delay_write_r),
        .wr_data_i(input_prefix_w[0 +: 72]),
        .rd_addr_i(input_delay_read_w),
        .rd_data_o(u_input_delay_0_data_w)
    );
    wire [71:0] u_input_delay_1_data_w;
    reg [71:0] u_input_delay_1_data_r;
    assign unused_input_delay_w[72 +: 72] = u_input_delay_1_data_r;
    always @(posedge clk_i) begin
        if (control_enable_w[2]) u_input_delay_1_data_r <= u_input_delay_1_data_w;
    end
    edrv32_ram_gpu_table u_input_delay_1 (
        .clk_i(clk_i),
        .wr_en_i(control_enable_w[0]),
        .wr_addr_i(input_delay_write_r),
        .wr_data_i(input_prefix_w[72 +: 72]),
        .rd_addr_i(input_delay_read_w),
        .rd_data_o(u_input_delay_1_data_w)
    );
    wire [71:0] u_input_delay_2_data_w;
    reg [71:0] u_input_delay_2_data_r;
    assign unused_input_delay_w[144 +: 72] = u_input_delay_2_data_r;
    always @(posedge clk_i) begin
        if (control_enable_w[1]) u_input_delay_2_data_r <= u_input_delay_2_data_w;
    end
    edrv32_ram_gpu_table u_input_delay_2 (
        .clk_i(clk_i),
        .wr_en_i(control_enable_w[2]),
        .wr_addr_i(input_delay_write_r),
        .wr_data_i(input_prefix_w[144 +: 72]),
        .rd_addr_i(input_delay_read_w),
        .rd_data_o(u_input_delay_2_data_w)
    );
    wire [71:0] u_input_delay_3_data_w;
    reg [71:0] u_input_delay_3_data_r;
    assign unused_input_delay_w[216 +: 72] = u_input_delay_3_data_r;
    always @(posedge clk_i) begin
        if (control_enable_w[0]) u_input_delay_3_data_r <= u_input_delay_3_data_w;
    end
    edrv32_ram_gpu_table u_input_delay_3 (
        .clk_i(clk_i),
        .wr_en_i(control_enable_w[1]),
        .wr_addr_i(input_delay_write_r),
        .wr_data_i({64'b0, input_prefix_w[223:216]}),
        .rd_addr_i(input_delay_read_w),
        .rd_data_o(u_input_delay_3_data_w)
    );

    genvar field_g;
    generate
        for (field_g = 0; field_g < 8; field_g = field_g + 1) begin : g_input_field
            localparam WIDTH = field_g < 3 ? 40 : (field_g < 5 ? 16 : 24);
            localparam INPUT_OFFSET = field_g < 3 ? field_g * 40
                : (field_g < 5 ? 160 + (field_g - 3) * 16 : 192 + (field_g - 5) * 24);
            localparam RAM_OFFSET = field_g < 3 ? field_g * 40
                : (field_g < 5 ? 120 + (field_g - 3) * 16 : 152 + (field_g - 5) * 24);
            reg [WIDTH-1:0] prefix_r;
            always @(posedge clk_i) begin
                if (control_enable_w[2]) prefix_r <= clipped_data_i[INPUT_OFFSET +: WIDTH];
            end
            assign input_prefix_w[RAM_OFFSET +: WIDTH] = prefix_r;
            if (field_g < 3) begin : g_position
                assign position_input_w[field_g] = unused_input_delay_w[RAM_OFFSET +: WIDTH];
            end else if (field_g < 5) begin : g_uv
                assign uv_input_w[field_g - 3] = unused_input_delay_w[RAM_OFFSET +: WIDTH];
            end else begin : g_color
                assign color_input_w[(field_g - 5) * 24 +: 24] =
                    unused_input_delay_w[RAM_OFFSET +: WIDTH];
            end
        end
    endgenerate
    assign reciprocal40_w = {9'b0, reciprocal_input_r};
    assign restore_round_a0_w = reciprocal40_w_d3_r[0 +: 35];
    assign restore_round_b0_w = restore_bias_r[0 +: 35];
    assign restore_round_low0_w = restore_round_part0_r[34:0];
    assign restore_round_a1_w = reciprocal40_w_d3_r[35 +: 5];
    assign restore_round_b1_w = restore_bias_r[35 +: 5];
    assign restore_round_low1_w = unused_restore_round_part1_r[4:0];
    assign restore_round_w = {restore_round_low1_w, restore_round_low0_w_d5_r};
    assign restore_shift_right_amt0_w = restore_right_r[0 +: 2];
    always @(*) begin
        restore_shift_right_0_w = restore_round_w;
        case (restore_shift_right_amt0_w_d5_r)
            2'd0: restore_shift_right_0_w = restore_round_w >> 0;
            2'd1: restore_shift_right_0_w = restore_round_w >> 1;
            2'd2: restore_shift_right_0_w = restore_round_w >> 2;
            2'd3: restore_shift_right_0_w = restore_round_w >> 3;
            default: restore_shift_right_0_w = restore_round_w;
        endcase
    end
    assign restore_shift_right_amt1_w = restore_right_r[2 +: 2];
    always @(*) begin
        restore_shift_right_1_w = restore_shift_right_0_r;
        case (restore_shift_right_amt1_w_d6_r)
            2'd0: restore_shift_right_1_w = restore_shift_right_0_r >> 0;
            2'd1: restore_shift_right_1_w = restore_shift_right_0_r >> 4;
            2'd2: restore_shift_right_1_w = restore_shift_right_0_r >> 8;
            2'd3: restore_shift_right_1_w = restore_shift_right_0_r >> 12;
            default: restore_shift_right_1_w = restore_shift_right_0_r;
        endcase
    end
    assign restore_shift_right_amt2_w = restore_right_r[4 +: 2];
    always @(*) begin
        restore_shift_right_2_w = restore_shift_right_1_r;
        case (restore_shift_right_amt2_w_d7_r)
            2'd0: restore_shift_right_2_w = restore_shift_right_1_r >> 0;
            2'd1: restore_shift_right_2_w = restore_shift_right_1_r >> 16;
            2'd2: restore_shift_right_2_w = restore_shift_right_1_r >> 32;
            2'd3: restore_shift_right_2_w = restore_shift_right_1_r >> 48;
            default: restore_shift_right_2_w = restore_shift_right_1_r;
        endcase
    end
    assign restore_shift_left_amt0_w = restore_left_r[0 +: 2];
    always @(*) begin
        restore_shift_left_0_w = reciprocal40_w_d1_r;
        case (restore_shift_left_amt0_w)
            2'd0: restore_shift_left_0_w = reciprocal40_w_d1_r << 0;
            2'd1: restore_shift_left_0_w = reciprocal40_w_d1_r << 1;
            2'd2: restore_shift_left_0_w = reciprocal40_w_d1_r << 2;
            2'd3: restore_shift_left_0_w = reciprocal40_w_d1_r << 3;
            default: restore_shift_left_0_w = reciprocal40_w_d1_r;
        endcase
    end
    assign restore_shift_left_amt1_w = restore_left_r[2 +: 2];
    always @(*) begin
        restore_shift_left_1_w = restore_shift_left_0_r;
        case (restore_shift_left_amt1_w_d2_r)
            2'd0: restore_shift_left_1_w = restore_shift_left_0_r << 0;
            2'd1: restore_shift_left_1_w = restore_shift_left_0_r << 4;
            2'd2: restore_shift_left_1_w = restore_shift_left_0_r << 8;
            2'd3: restore_shift_left_1_w = restore_shift_left_0_r << 12;
            default: restore_shift_left_1_w = restore_shift_left_0_r;
        endcase
    end
    assign restore_shift_left_amt2_w = restore_left_r[4 +: 2];
    always @(*) begin
        restore_shift_left_2_w = restore_shift_left_1_r;
        case (restore_shift_left_amt2_w_d3_r)
            2'd0: restore_shift_left_2_w = restore_shift_left_1_r << 0;
            2'd1: restore_shift_left_2_w = restore_shift_left_1_r << 16;
            2'd2: restore_shift_left_2_w = restore_shift_left_1_r << 32;
            2'd3: restore_shift_left_2_w = restore_shift_left_1_r << 48;
            default: restore_shift_left_2_w = restore_shift_left_1_r;
        endcase
    end
    assign position_ext0_w = {{19{position_product0_p2_r[74]}}, position_product0_p2_r};
    assign viewport_one0_w = 94'd70368744177664;
    assign viewport_adjust0_a0_w = position_ext0_w[0 +: 35];
    assign viewport_adjust0_b0_w = viewport_one0_w[0 +: 35];
    assign viewport_adjust0_low0_w = viewport_adjust0_part0_r[34:0];
    assign viewport_adjust0_a1_w = position_ext0_w[35 +: 35];
    assign viewport_adjust0_b1_w = viewport_one0_w[35 +: 35];
    assign viewport_adjust0_low1_w = viewport_adjust0_part1_r[34:0];
    assign viewport_adjust0_a2_w = position_ext0_w[70 +: 24];
    assign viewport_adjust0_b2_w = viewport_one0_w[70 +: 24];
    assign viewport_adjust0_low2_w = unused_viewport_adjust0_part2_r[23:0];
    assign viewport_adjust0_w =
                {viewport_adjust0_low2_w, viewport_adjust0_low1_w_d15_r,
                viewport_adjust0_low0_w_d15_r};
    assign position_ext1_w = {{19{position_product1_p2_r[74]}}, position_product1_p2_r};
    assign viewport_one1_w = 94'd70368744177664;
    assign position_negate_one_w = 94'd1;
    assign position_negate_a0_w = position_negative_r[0 +: 35];
    assign position_negate_b0_w = position_negate_one_w[0 +: 35];
    assign position_negate_low0_w = position_negate_part0_r[34:0];
    assign position_negate_a1_w = position_negative_r[35 +: 35];
    assign position_negate_b1_w = position_negate_one_w[35 +: 35];
    assign position_negate_low1_w = position_negate_part1_r[34:0];
    assign position_negate_a2_w = position_negative_r[70 +: 24];
    assign position_negate_b2_w = position_negate_one_w[70 +: 24];
    assign position_negate_low2_w = unused_position_negate_part2_r[23:0];
    assign position_negate_w =
                {position_negate_low2_w, position_negate_low1_w_d16_r,
                position_negate_low0_w_d16_r};
    assign viewport_adjust1_a0_w = viewport_one1_w[0 +: 35];
    assign viewport_adjust1_b0_w = position_negate_w[0 +: 35];
    assign viewport_adjust1_low0_w = viewport_adjust1_part0_r[34:0];
    assign viewport_adjust1_a1_w = viewport_one1_w[35 +: 35];
    assign viewport_adjust1_b1_w = position_negate_w[35 +: 35];
    assign viewport_adjust1_low1_w = viewport_adjust1_part1_r[34:0];
    assign viewport_adjust1_a2_w = viewport_one1_w[70 +: 24];
    assign viewport_adjust1_b2_w = position_negate_w[70 +: 24];
    assign viewport_adjust1_low2_w = unused_viewport_adjust1_part2_r[23:0];
    assign viewport_adjust1_w =
                {viewport_adjust1_low2_w, viewport_adjust1_low1_w_d19_r,
                viewport_adjust1_low0_w_d19_r};
    assign position_ext2_w = {{19{position_product2_p2_r[74]}}, position_product2_p2_r};
    assign depth_left_w = position_ext2_w << 16;
    assign depth_one_w = 94'd1;
    assign depth_negate_a0_w = depth_invert_r[0 +: 35];
    assign depth_negate_b0_w = depth_one_w[0 +: 35];
    assign depth_negate_low0_w = depth_negate_part0_r[34:0];
    assign depth_negate_a1_w = depth_invert_r[35 +: 35];
    assign depth_negate_b1_w = depth_one_w[35 +: 35];
    assign depth_negate_low1_w = depth_negate_part1_r[34:0];
    assign depth_negate_a2_w = depth_invert_r[70 +: 24];
    assign depth_negate_b2_w = depth_one_w[70 +: 24];
    assign depth_negate_low2_w = unused_depth_negate_part2_r[23:0];
    assign depth_negate_w =
                {depth_negate_low2_w, depth_negate_low1_w_d16_r, depth_negate_low0_w_d16_r};
    assign depth_subtract_a0_w = depth_left_w_d16_r[0 +: 35];
    assign depth_subtract_b0_w = depth_negate_w[0 +: 35];
    assign depth_subtract_low0_w = depth_subtract_part0_r[34:0];
    assign depth_subtract_a1_w = depth_left_w_d16_r[35 +: 35];
    assign depth_subtract_b1_w = depth_negate_w[35 +: 35];
    assign depth_subtract_low1_w = depth_subtract_part1_r[34:0];
    assign depth_subtract_a2_w = depth_left_w_d16_r[70 +: 24];
    assign depth_subtract_b2_w = depth_negate_w[70 +: 24];
    assign depth_subtract_low2_w = unused_depth_subtract_part2_r[23:0];
    assign depth_subtract_w =
                {depth_subtract_low2_w, depth_subtract_low1_w_d19_r, depth_subtract_low0_w_d19_r};
    assign screen_abs0_carry_w = {93'b0, screen_abs0_sign_r};
    assign screen_abs0_a0_w = screen_abs0_invert_r[0 +: 35];
    assign screen_abs0_b0_w = screen_abs0_carry_w[0 +: 35];
    assign screen_abs0_low0_w = screen_abs0_part0_r[34:0];
    assign screen_abs0_a1_w = screen_abs0_invert_r[35 +: 35];
    assign screen_abs0_b1_w = screen_abs0_carry_w[35 +: 35];
    assign screen_abs0_low1_w = screen_abs0_part1_r[34:0];
    assign screen_abs0_a2_w = screen_abs0_invert_r[70 +: 24];
    assign screen_abs0_b2_w = screen_abs0_carry_w[70 +: 24];
    assign screen_abs0_low2_w = unused_screen_abs0_part2_r[23:0];
    assign unused_screen_abs0_w =
                {screen_abs0_low2_w, screen_abs0_low1_w_d23_r, screen_abs0_low0_w_d23_r};
    assign screen_high0_w = {1'b0, unused_screen_abs0_w[93:46]};
    assign screen_bit0_w = {48'b0, unused_screen_abs0_w[45]};
    assign screen_round0_a0_w = screen_high0_w[0 +: 35];
    assign screen_round0_b0_w = screen_bit0_w[0 +: 35];
    assign screen_round0_low0_w = screen_round0_part0_r[34:0];
    assign screen_round0_a1_w = screen_high0_w[35 +: 14];
    assign screen_round0_b1_w = screen_bit0_w[35 +: 14];
    assign screen_round0_low1_w = unused_screen_round0_part1_r[13:0];
    assign screen_round0_w = {screen_round0_low1_w, screen_round0_low0_w_d25_r};
    assign screen_signed0_carry_w = {48'b0, screen_abs0_sign_d26_r};
    assign screen_signed0_a0_w = screen_signed0_invert_r[0 +: 35];
    assign screen_signed0_b0_w = screen_signed0_carry_w[0 +: 35];
    assign screen_signed0_low0_w = screen_signed0_part0_r[34:0];
    assign screen_signed0_a1_w = screen_signed0_invert_r[35 +: 14];
    assign screen_signed0_b1_w = screen_signed0_carry_w[35 +: 14];
    assign screen_signed0_low1_w = unused_screen_signed0_part1_r[13:0];
    assign screen_signed0_w = {screen_signed0_low1_w, screen_signed0_low0_w_d28_r};
    assign screen_offset0_a0_w = screen_signed0_w[0 +: 35];
    assign screen_offset0_low0_w = screen_offset0_part0_r[34:0];
    assign screen_offset0_a1_w = screen_signed0_w[35 +: 14];
    assign screen_offset0_low1_w = unused_screen_offset0_part1_r[13:0];
    assign screen_offset0_w = {screen_offset0_low1_w, screen_offset0_low0_w_d30_r};
    assign screen_abs1_carry_w = {93'b0, screen_abs1_sign_r};
    assign screen_abs1_a0_w = screen_abs1_invert_r[0 +: 35];
    assign screen_abs1_b0_w = screen_abs1_carry_w[0 +: 35];
    assign screen_abs1_low0_w = screen_abs1_part0_r[34:0];
    assign screen_abs1_a1_w = screen_abs1_invert_r[35 +: 35];
    assign screen_abs1_b1_w = screen_abs1_carry_w[35 +: 35];
    assign screen_abs1_low1_w = screen_abs1_part1_r[34:0];
    assign screen_abs1_a2_w = screen_abs1_invert_r[70 +: 24];
    assign screen_abs1_b2_w = screen_abs1_carry_w[70 +: 24];
    assign screen_abs1_low2_w = unused_screen_abs1_part2_r[23:0];
    assign unused_screen_abs1_w =
                {screen_abs1_low2_w, screen_abs1_low1_w_d27_r, screen_abs1_low0_w_d27_r};
    assign screen_high1_w = {1'b0, unused_screen_abs1_w[93:46]};
    assign screen_bit1_w = {48'b0, unused_screen_abs1_w[45]};
    assign screen_round1_a0_w = screen_high1_w[0 +: 35];
    assign screen_round1_b0_w = screen_bit1_w[0 +: 35];
    assign screen_round1_low0_w = screen_round1_part0_r[34:0];
    assign screen_round1_a1_w = screen_high1_w[35 +: 14];
    assign screen_round1_b1_w = screen_bit1_w[35 +: 14];
    assign screen_round1_low1_w = unused_screen_round1_part1_r[13:0];
    assign screen_round1_w = {screen_round1_low1_w, screen_round1_low0_w_d29_r};
    assign screen_signed1_carry_w = {48'b0, screen_abs1_sign_d30_r};
    assign screen_signed1_a0_w = screen_signed1_invert_r[0 +: 35];
    assign screen_signed1_b0_w = screen_signed1_carry_w[0 +: 35];
    assign screen_signed1_low0_w = screen_signed1_part0_r[34:0];
    assign screen_signed1_a1_w = screen_signed1_invert_r[35 +: 14];
    assign screen_signed1_b1_w = screen_signed1_carry_w[35 +: 14];
    assign screen_signed1_low1_w = unused_screen_signed1_part1_r[13:0];
    assign screen_signed1_w = {screen_signed1_low1_w, screen_signed1_low0_w_d32_r};
    assign screen_offset1_a0_w = screen_signed1_w[0 +: 35];
    assign screen_offset1_low0_w = screen_offset1_part0_r[34:0];
    assign screen_offset1_a1_w = screen_signed1_w[35 +: 14];
    assign screen_offset1_low1_w = unused_screen_offset1_part1_r[13:0];
    assign screen_offset1_w = {screen_offset1_low1_w, screen_offset1_low0_w_d34_r};
    assign depth_high_w = {1'b0, depth_subtract_w[93:46]};
    assign depth_bit_w = {48'b0, depth_subtract_w[45]};
    assign depth_round_a0_w = depth_high_w[0 +: 35];
    assign depth_round_b0_w = depth_bit_w[0 +: 35];
    assign depth_round_low0_w = depth_round_part0_r[34:0];
    assign depth_round_a1_w = depth_high_w[35 +: 14];
    assign depth_round_b1_w = depth_bit_w[35 +: 14];
    assign depth_round_low1_w = unused_depth_round_part1_r[13:0];
    assign depth_round_w = {depth_round_low1_w, depth_round_low0_w_d21_r};
    assign projected_data_o[0 +: 17] = output_0_r[read_r];
    always @(posedge clk_i) begin
        if (push_w) output_0_r[write_r] <= screen_clamp0_d35_r;
    end
    assign projected_data_o[17 +: 17] = output_1_r[read_r];
    always @(posedge clk_i) begin
        if (push_w) output_1_r[write_r] <= screen_clamp1_r;
    end
    assign projected_data_o[34 +: 16] = output_2_r[read_r];
    always @(posedge clk_i) begin
        if (push_w) output_2_r[write_r] <= depth_clamp_d35_align6_r;
    end
    assign projected_data_o[50 +: 35] = output_3_r[read_r];
    always @(posedge clk_i) begin
        if (push_w) output_3_r[write_r] <= restored_d35_align14_r;
    end
    assign projected_data_o[85 +: 51] = output_4_r[read_r];
    always @(posedge clk_i) begin
        if (push_w) output_4_r[write_r] <= uv_product0_p2_d35_align12_r;
    end
    assign projected_data_o[136 +: 51] = output_5_r[read_r];
    always @(posedge clk_i) begin
        if (push_w) output_5_r[write_r] <= uv_product1_p2_d35_align12_r;
    end
    assign projected_data_o[187 +: 72] = output_6_r[read_r];
    always @(posedge clk_i) begin
        if (push_w) output_6_r[write_r] <= color_input_r_d35_align14_r;
    end
    // Each region owns the output-credit count used by its local clock enable.
    wire [10:0] pipeline_enable_w;
    genvar enable_region;
    generate
        for (enable_region = 0; enable_region < 11;
            enable_region = enable_region + 1) begin : g_enable_region
            (* keep = "true", syn_preserve = 1 *) reg [1:0] region_count_r;
            assign pipeline_enable_w[enable_region] = region_count_r != 2 && !stop_i;
            (* keep = 1 *) always @(posedge clk_i or negedge rst_n_i) begin
                if (!rst_n_i) region_count_r <= 0;
                else if (stop_i) region_count_r <= 0;
                else begin
                    case ({push_w, pop_w})
                        2'b10: region_count_r <= region_count_r + 1'b1;
                        2'b01: region_count_r <= region_count_r - 1'b1;
                        default: region_count_r <= region_count_r;
                    endcase
                end
            end
        end
    endgenerate
    always @(posedge clk_i) begin
        if (pipeline_enable_w[0]) begin
            reciprocal_input_r <= reciprocal_w;
            restore_exponent_r <= exponent_w;
            restore_right_r <= restore_exponent_r > 6'd16 ? restore_exponent_r - 6'd16 : 6'b0;
            restore_left_r <= restore_exponent_r < 6'd16 ? 6'd16 - restore_exponent_r : 6'b0;
            restore_bit_r <= restore_right_r - 6'd1;
            restore_bias_r <= 40'd1 << restore_bit_r;
            reciprocal40_w_d1_r <= reciprocal40_w;
            reciprocal40_w_d2_r <= reciprocal40_w_d1_r;
            reciprocal40_w_d3_r <= reciprocal40_w_d2_r;
            restore_round_part0_r <= {1'b0, restore_round_a0_w} + {1'b0, restore_round_b0_w};
            restore_round_a1_w_d4_r <= restore_round_a1_w;
            restore_round_b1_w_d4_r <= restore_round_b1_w;
            unused_restore_round_part1_r <=
                {1'b0, restore_round_a1_w_d4_r} + {1'b0, restore_round_b1_w_d4_r} + {5'b0,
                restore_round_part0_r[35]};
            restore_round_low0_w_d5_r <= restore_round_low0_w;
            restore_shift_right_amt0_w_d2_r <= restore_shift_right_amt0_w;
            restore_shift_right_amt0_w_d3_r <= restore_shift_right_amt0_w_d2_r;
            restore_shift_right_amt0_w_d4_r <= restore_shift_right_amt0_w_d3_r;
            restore_shift_right_amt0_w_d5_r <= restore_shift_right_amt0_w_d4_r;
            restore_shift_right_0_r <= restore_shift_right_0_w;
            restore_shift_right_amt1_w_d2_r <= restore_shift_right_amt1_w;
            restore_shift_right_amt1_w_d3_r <= restore_shift_right_amt1_w_d2_r;
            restore_shift_right_amt1_w_d4_r <= restore_shift_right_amt1_w_d3_r;
            restore_shift_right_amt1_w_d5_r <= restore_shift_right_amt1_w_d4_r;
            restore_shift_right_amt1_w_d6_r <= restore_shift_right_amt1_w_d5_r;
            restore_shift_right_1_r <= restore_shift_right_1_w;
            restore_shift_right_amt2_w_d2_r <= restore_shift_right_amt2_w;
            restore_shift_right_amt2_w_d3_r <= restore_shift_right_amt2_w_d2_r;
            restore_shift_right_amt2_w_d4_r <= restore_shift_right_amt2_w_d3_r;
            restore_shift_right_amt2_w_d5_r <= restore_shift_right_amt2_w_d4_r;
            restore_shift_right_amt2_w_d6_r <= restore_shift_right_amt2_w_d5_r;
            restore_shift_right_amt2_w_d7_r <= restore_shift_right_amt2_w_d6_r;
            unused_restore_shift_right_2_r <= restore_shift_right_2_w;
            restore_shift_left_0_r <= restore_shift_left_0_w;
            restore_shift_left_amt1_w_d2_r <= restore_shift_left_amt1_w;
            restore_shift_left_1_r <= restore_shift_left_1_w;
            restore_shift_left_amt2_w_d2_r <= restore_shift_left_amt2_w;
            restore_shift_left_amt2_w_d3_r <= restore_shift_left_amt2_w_d2_r;
            restore_shift_left_2_r <= restore_shift_left_2_w;
            restore_exponent_r_d1_r <= restore_exponent_r;
            restore_exponent_r_d2_r <= restore_exponent_r_d1_r;
            restore_exponent_r_d3_r <= restore_exponent_r_d2_r;
            restore_exponent_r_d4_r <= restore_exponent_r_d3_r;
            restore_exponent_r_d5_r <= restore_exponent_r_d4_r;
            restore_exponent_r_d6_r <= restore_exponent_r_d5_r;
            restore_exponent_r_d7_r <= restore_exponent_r_d6_r;
            restore_exponent_r_d8_r <= restore_exponent_r_d7_r;
            restore_shift_left_2_r_d5_r <= restore_shift_left_2_r;
            restore_shift_left_2_r_d6_r <= restore_shift_left_2_r_d5_r;
            restore_shift_left_2_r_d7_r <= restore_shift_left_2_r_d6_r;
            unused_restore_shift_left_2_r_d8_r <= restore_shift_left_2_r_d7_r;
            restored_r <=
                restore_exponent_r_d8_r > 6'd16 ? unused_restore_shift_right_2_r[34:0] :
                unused_restore_shift_left_2_r_d8_r[34:0];
            position_input0_r <= position_input_w[0];
            position_input1_r <= position_input_w[1];
            position_input2_r <= position_input_w[2];
            uv_input0_r <= uv_input_w[0];
            uv_input1_r <= uv_input_w[1];
        end
    end
    always @(posedge clk_i) begin
        if (pipeline_enable_w[2]) begin
            viewport_adjust0_part0_r <=
                {1'b0, viewport_adjust0_a0_w} + {1'b0, viewport_adjust0_b0_w};
            viewport_adjust0_a1_w_d13_r <= viewport_adjust0_a1_w;
            viewport_adjust0_part1_r <=
                {1'b0, viewport_adjust0_a1_w_d13_r} + {1'b0, viewport_adjust0_b1_w} +
                {35'b0, viewport_adjust0_part0_r[35]};
            viewport_adjust0_a2_w_d13_r <= viewport_adjust0_a2_w;
            viewport_adjust0_a2_w_d14_r <= viewport_adjust0_a2_w_d13_r;
            unused_viewport_adjust0_part2_r <=
                {1'b0, viewport_adjust0_a2_w_d14_r} + {1'b0, viewport_adjust0_b2_w} +
                {24'b0, viewport_adjust0_part1_r[35]};
        end
    end
    always @(posedge clk_i) begin
        if (pipeline_enable_w[3]) begin
            viewport_adjust0_low1_w_d15_r <= viewport_adjust0_low1_w;
            viewport_adjust0_low0_w_d14_r <= viewport_adjust0_low0_w;
            viewport_adjust0_low0_w_d15_r <= viewport_adjust0_low0_w_d14_r;
            viewport_size0_r <= viewport_i[32 +: 16];
            viewport_shift0_r <= viewport_product0_p2_r << 3;
            position_negative_r <= ~position_ext1_w;
            position_negate_part0_r <=
                {1'b0, position_negate_a0_w} + {1'b0, position_negate_b0_w};
            position_negate_a1_w_d14_r <= position_negate_a1_w;
            position_negate_part1_r <=
                {1'b0, position_negate_a1_w_d14_r} + {1'b0, position_negate_b1_w} +
                {35'b0, position_negate_part0_r[35]};
            position_negate_a2_w_d14_r <= position_negate_a2_w;
            position_negate_a2_w_d15_r <= position_negate_a2_w_d14_r;
            unused_position_negate_part2_r <=
                {1'b0, position_negate_a2_w_d15_r} + {1'b0, position_negate_b2_w} +
                {24'b0, position_negate_part1_r[35]};
            position_negate_low1_w_d16_r <= position_negate_low1_w;
            position_negate_low0_w_d15_r <= position_negate_low0_w;
            position_negate_low0_w_d16_r <= position_negate_low0_w_d15_r;
        end
    end
    always @(posedge clk_i) begin
        if (pipeline_enable_w[4]) begin
            viewport_adjust1_part0_r <=
                {1'b0, viewport_adjust1_a0_w} + {1'b0, viewport_adjust1_b0_w};
            viewport_adjust1_b1_w_d17_r <= viewport_adjust1_b1_w;
            viewport_adjust1_part1_r <=
                {1'b0, viewport_adjust1_a1_w} + {1'b0, viewport_adjust1_b1_w_d17_r} +
                {35'b0, viewport_adjust1_part0_r[35]};
            viewport_adjust1_b2_w_d17_r <= viewport_adjust1_b2_w;
            viewport_adjust1_b2_w_d18_r <= viewport_adjust1_b2_w_d17_r;
            unused_viewport_adjust1_part2_r <=
                {1'b0, viewport_adjust1_a2_w} + {1'b0, viewport_adjust1_b2_w_d18_r} +
                {24'b0, viewport_adjust1_part1_r[35]};
            viewport_adjust1_low1_w_d19_r <= viewport_adjust1_low1_w;
            viewport_adjust1_low0_w_d18_r <= viewport_adjust1_low0_w;
            viewport_adjust1_low0_w_d19_r <= viewport_adjust1_low0_w_d18_r;
            viewport_size1_r <= viewport_i[48 +: 16];
        end
    end
    always @(posedge clk_i) begin
        if (pipeline_enable_w[5]) begin
            viewport_shift1_r <= viewport_product1_p2_r << 3;
            depth_invert_r <= ~position_ext2_w;
            depth_negate_part0_r <= {1'b0, depth_negate_a0_w} + {1'b0, depth_negate_b0_w};
            depth_negate_a1_w_d14_r <= depth_negate_a1_w;
            depth_negate_part1_r <=
                {1'b0, depth_negate_a1_w_d14_r} + {1'b0, depth_negate_b1_w} + {35'b0,
                depth_negate_part0_r[35]};
            depth_negate_a2_w_d14_r <= depth_negate_a2_w;
            depth_negate_a2_w_d15_r <= depth_negate_a2_w_d14_r;
            unused_depth_negate_part2_r <=
                {1'b0, depth_negate_a2_w_d15_r} + {1'b0, depth_negate_b2_w} + {24'b0,
                depth_negate_part1_r[35]};
            depth_negate_low1_w_d16_r <= depth_negate_low1_w;
            depth_negate_low0_w_d15_r <= depth_negate_low0_w;
            depth_negate_low0_w_d16_r <= depth_negate_low0_w_d15_r;
            depth_left_w_d13_r <= depth_left_w;
            depth_left_w_d14_r <= depth_left_w_d13_r;
            depth_left_w_d15_r <= depth_left_w_d14_r;
            depth_left_w_d16_r <= depth_left_w_d15_r;
            depth_subtract_part0_r <= {1'b0, depth_subtract_a0_w} + {1'b0, depth_subtract_b0_w};
            depth_subtract_a1_w_d17_r <= depth_subtract_a1_w;
        end
    end
    always @(posedge clk_i) begin
        if (pipeline_enable_w[6]) begin
            depth_subtract_b1_w_d17_r <= depth_subtract_b1_w;
            depth_subtract_part1_r <=
                {1'b0, depth_subtract_a1_w_d17_r} + {1'b0, depth_subtract_b1_w_d17_r} + {35'b0,
                depth_subtract_part0_r[35]};
            depth_subtract_a2_w_d17_r <= depth_subtract_a2_w;
            depth_subtract_a2_w_d18_r <= depth_subtract_a2_w_d17_r;
            depth_subtract_b2_w_d17_r <= depth_subtract_b2_w;
            depth_subtract_b2_w_d18_r <= depth_subtract_b2_w_d17_r;
            unused_depth_subtract_part2_r <=
                {1'b0, depth_subtract_a2_w_d18_r} + {1'b0, depth_subtract_b2_w_d18_r} + {24'b0,
                depth_subtract_part1_r[35]};
            depth_subtract_low1_w_d19_r <= depth_subtract_low1_w;
            depth_subtract_low0_w_d18_r <= depth_subtract_low0_w;
            depth_subtract_low0_w_d19_r <= depth_subtract_low0_w_d18_r;
            screen_abs0_sign_r <= viewport_shift0_r[93];
            screen_abs0_invert_r <= viewport_shift0_r[93] ? ~viewport_shift0_r : viewport_shift0_r;
            screen_abs0_part0_r <= {1'b0, screen_abs0_a0_w} + {1'b0, screen_abs0_b0_w};
            screen_abs0_a1_w_d21_r <= screen_abs0_a1_w;
            screen_abs0_b1_w_d21_r <= screen_abs0_b1_w;
            screen_abs0_part1_r <=
                {1'b0, screen_abs0_a1_w_d21_r} + {1'b0, screen_abs0_b1_w_d21_r} + {35'b0,
                screen_abs0_part0_r[35]};
            screen_abs0_a2_w_d21_r <= screen_abs0_a2_w;
            screen_abs0_a2_w_d22_r <= screen_abs0_a2_w_d21_r;
            screen_abs0_b2_w_d21_r <= screen_abs0_b2_w;
            screen_abs0_b2_w_d22_r <= screen_abs0_b2_w_d21_r;
            unused_screen_abs0_part2_r <=
                {1'b0, screen_abs0_a2_w_d22_r} + {1'b0, screen_abs0_b2_w_d22_r} + {24'b0,
                screen_abs0_part1_r[35]};
            screen_abs0_low1_w_d23_r <= screen_abs0_low1_w;
            screen_abs0_low0_w_d22_r <= screen_abs0_low0_w;
            screen_abs0_low0_w_d23_r <= screen_abs0_low0_w_d22_r;
            screen_round0_part0_r <= {1'b0, screen_round0_a0_w} + {1'b0, screen_round0_b0_w};
            screen_round0_a1_w_d24_r <= screen_round0_a1_w;
            screen_round0_b1_w_d24_r <= screen_round0_b1_w;
            unused_screen_round0_part1_r <=
                {1'b0, screen_round0_a1_w_d24_r} + {1'b0, screen_round0_b1_w_d24_r} + {14'b0,
                screen_round0_part0_r[35]};
            screen_round0_low0_w_d25_r <= screen_round0_low0_w;
            screen_abs0_sign_d21_r <= screen_abs0_sign_r;
            screen_abs0_sign_d22_r <= screen_abs0_sign_d21_r;
            screen_abs0_sign_d23_r <= screen_abs0_sign_d22_r;
            screen_abs0_sign_d24_r <= screen_abs0_sign_d23_r;
            screen_abs0_sign_d25_r <= screen_abs0_sign_d24_r;
            screen_signed0_invert_r <= screen_abs0_sign_d25_r ? ~screen_round0_w : screen_round0_w;
            screen_abs0_sign_d26_r <= screen_abs0_sign_d25_r;
            screen_signed0_part0_r <= {1'b0, screen_signed0_a0_w} + {1'b0, screen_signed0_b0_w};
            screen_signed0_a1_w_d27_r <= screen_signed0_a1_w;
            screen_signed0_b1_w_d27_r <= screen_signed0_b1_w;
            unused_screen_signed0_part1_r <=
                {1'b0, screen_signed0_a1_w_d27_r} + {1'b0, screen_signed0_b1_w_d27_r} + {14'b0,
                screen_signed0_part0_r[35]};
            screen_signed0_low0_w_d28_r <= screen_signed0_low0_w;
            viewport_offset0_r <= viewport_i[0 +: 16];
        end
    end
    always @(posedge clk_i) begin
        if (pipeline_enable_w[7]) begin
            screen_offset0_part0_r <=
                {1'b0, screen_offset0_a0_w} + {1'b0, screen_offset0_b0_align14_r};
            screen_offset0_a1_w_d29_r <= screen_offset0_a1_w;
            unused_screen_offset0_part1_r <=
                {1'b0, screen_offset0_a1_w_d29_r} + {1'b0, screen_offset0_b1_w_d29_align14_r} +
                {14'b0, screen_offset0_part0_r[35]};
            screen_offset0_low0_w_d30_r <= screen_offset0_low0_w;
            screen_clamp0_r <=
                screen_offset0_w[48] ? ((&screen_offset0_w[47:16]) ? screen_offset0_w[16:0] :
                17'h10000) : ((|screen_offset0_w[47:16]) ? 17'h0ffff : screen_offset0_w[16:0] );
            screen_abs1_sign_r <= viewport_shift1_r[93];
            screen_abs1_invert_r <= viewport_shift1_r[93] ? ~viewport_shift1_r : viewport_shift1_r;
            screen_abs1_part0_r <= {1'b0, screen_abs1_a0_w} + {1'b0, screen_abs1_b0_w};
            screen_abs1_a1_w_d25_r <= screen_abs1_a1_w;
            screen_abs1_b1_w_d25_r <= screen_abs1_b1_w;
            screen_abs1_part1_r <=
                {1'b0, screen_abs1_a1_w_d25_r} + {1'b0, screen_abs1_b1_w_d25_r} + {35'b0,
                screen_abs1_part0_r[35]};
            screen_abs1_a2_w_d25_r <= screen_abs1_a2_w;
            screen_abs1_a2_w_d26_r <= screen_abs1_a2_w_d25_r;
            screen_abs1_b2_w_d25_r <= screen_abs1_b2_w;
            screen_abs1_b2_w_d26_r <= screen_abs1_b2_w_d25_r;
            unused_screen_abs1_part2_r <=
                {1'b0, screen_abs1_a2_w_d26_r} + {1'b0, screen_abs1_b2_w_d26_r} + {24'b0,
                screen_abs1_part1_r[35]};
            screen_abs1_low1_w_d27_r <= screen_abs1_low1_w;
            screen_abs1_low0_w_d26_r <= screen_abs1_low0_w;
            screen_abs1_low0_w_d27_r <= screen_abs1_low0_w_d26_r;
            screen_round1_part0_r <= {1'b0, screen_round1_a0_w} + {1'b0, screen_round1_b0_w};
            screen_round1_a1_w_d28_r <= screen_round1_a1_w;
            screen_round1_b1_w_d28_r <= screen_round1_b1_w;
            unused_screen_round1_part1_r <=
                {1'b0, screen_round1_a1_w_d28_r} + {1'b0, screen_round1_b1_w_d28_r} + {14'b0,
                screen_round1_part0_r[35]};
            screen_round1_low0_w_d29_r <= screen_round1_low0_w;
            screen_abs1_sign_d25_r <= screen_abs1_sign_r;
            screen_abs1_sign_d26_r <= screen_abs1_sign_d25_r;
            screen_abs1_sign_d27_r <= screen_abs1_sign_d26_r;
            screen_abs1_sign_d28_r <= screen_abs1_sign_d27_r;
            screen_abs1_sign_d29_r <= screen_abs1_sign_d28_r;
            screen_signed1_invert_r <= screen_abs1_sign_d29_r ? ~screen_round1_w : screen_round1_w;
            screen_abs1_sign_d30_r <= screen_abs1_sign_d29_r;
            screen_signed1_part0_r <= {1'b0, screen_signed1_a0_w} + {1'b0, screen_signed1_b0_w};
            screen_signed1_a1_w_d31_r <= screen_signed1_a1_w;
            screen_signed1_b1_w_d31_r <= screen_signed1_b1_w;
            unused_screen_signed1_part1_r <=
                {1'b0, screen_signed1_a1_w_d31_r} + {1'b0, screen_signed1_b1_w_d31_r} + {14'b0,
                screen_signed1_part0_r[35]};
            screen_signed1_low0_w_d32_r <= screen_signed1_low0_w;
            viewport_offset1_r <= viewport_i[16 +: 16];
        end
    end
    always @(posedge clk_i) begin
        if (pipeline_enable_w[8]) begin
            screen_offset1_part0_r <=
                {1'b0, screen_offset1_a0_w} + {1'b0, screen_offset1_b0_align14_r};
            screen_offset1_a1_w_d33_r <= screen_offset1_a1_w;
            unused_screen_offset1_part1_r <=
                {1'b0, screen_offset1_a1_w_d33_r} + {1'b0, screen_offset1_b1_w_d33_align14_r} +
                {14'b0, screen_offset1_part0_r[35]};
            screen_offset1_low0_w_d34_r <= screen_offset1_low0_w;
            screen_clamp1_r <=
                screen_offset1_w[48] ? ((&screen_offset1_w[47:16]) ? screen_offset1_w[16:0] :
                17'h10000) : ((|screen_offset1_w[47:16]) ? 17'h0ffff : screen_offset1_w[16:0] );
            depth_round_part0_r <= {1'b0, depth_round_a0_w} + {1'b0, depth_round_b0_w};
            depth_round_a1_w_d20_r <= depth_round_a1_w;
            depth_round_b1_w_d20_r <= depth_round_b1_w;
            unused_depth_round_part1_r <=
                {1'b0, depth_round_a1_w_d20_r} + {1'b0, depth_round_b1_w_d20_r} + {14'b0,
                depth_round_part0_r[35]};
            depth_round_low0_w_d21_r <= depth_round_low0_w;
            depth_subtract_w_d20_r <= depth_subtract_w;
            unused_depth_subtract_w_d21_r <= depth_subtract_w_d20_r;
            depth_clamp_r <=
                unused_depth_subtract_w_d21_r[93] ? 16'b0 : (|depth_round_w[48:16]) ? 16'hffff :
                depth_round_w[15:0];
            screen_clamp0_d32_r <= screen_clamp0_r;
            screen_clamp0_d33_r <= screen_clamp0_d32_r;
            screen_clamp0_d34_r <= screen_clamp0_d33_r;
            screen_clamp0_d35_r <= screen_clamp0_d34_r;
        end
    end

    // position_product0: 40x35, 9 registered APM products; 11 enabled stages.
    wire [39:0] position_product0_a_w;
    assign position_product0_a_w = position_input0_r_d9_r;
    wire [34:0] position_product0_b_w;
    assign position_product0_b_w = restored_r;
    reg [33:0] position_product0_pp00_r;
    wire [74:0] unused_position_product0_term00_w;
    assign unused_position_product0_term00_w = {41'b0, position_product0_pp00_r} << 0;
    reg [33:0] position_product0_pp01_r;
    wire [74:0] unused_position_product0_term01_w;
    assign unused_position_product0_term01_w = {41'b0, position_product0_pp01_r} << 17;
    reg [17:0] position_product0_pp02_r;
    wire [74:0] unused_position_product0_term02_w;
    assign unused_position_product0_term02_w = {57'b0, position_product0_pp02_r} << 34;
    reg [33:0] position_product0_pp10_r;
    wire [74:0] unused_position_product0_term10_w;
    assign unused_position_product0_term10_w = {41'b0, position_product0_pp10_r} << 17;
    reg [33:0] position_product0_pp11_r;
    wire [74:0] unused_position_product0_term11_w;
    assign unused_position_product0_term11_w = {41'b0, position_product0_pp11_r} << 34;
    reg [17:0] position_product0_pp12_r;
    wire [74:0] unused_position_product0_term12_w;
    assign unused_position_product0_term12_w = {57'b0, position_product0_pp12_r} << 51;
    reg [22:0] position_product0_pp20_r;
    wire [74:0] unused_position_product0_term20_w;
    assign unused_position_product0_term20_w =
                {{52{position_product0_pp20_r[22]}}, position_product0_pp20_r} << 34;
    reg [22:0] position_product0_pp21_r;
    wire [74:0] unused_position_product0_term21_w;
    assign unused_position_product0_term21_w =
                {{52{position_product0_pp21_r[22]}}, position_product0_pp21_r} << 51;
    reg [6:0] position_product0_pp22_r;
    wire [74:0] unused_position_product0_term22_w;
    assign unused_position_product0_term22_w =
                {{68{position_product0_pp22_r[6]}}, position_product0_pp22_r} << 68;
    reg [35:0] unused_position_product0_l0n0_part0_r;
    reg [34:0] position_product0_l0n0_low0d0_r;
    reg [16:0] position_product0_l0n0_a1d0_r;
    reg [16:0] position_product0_l0n0_b1d0_r;
    reg [17:0] unused_position_product0_l0n0_part1_r;
    wire [74:0] unused_position_product0_l0n0_w;
    assign unused_position_product0_l0n0_w =
                {23'b0, {unused_position_product0_l0n0_part1_r[16:0],
                position_product0_l0n0_low0d0_r}};
    reg [35:0] unused_position_product0_l0n1_part0_r;
    reg [34:0] position_product0_l0n1_low0d0_r;
    reg [0:0] position_product0_l0n1_a1d0_r;
    reg [0:0] position_product0_l0n1_b1d0_r;
    reg [1:0] unused_position_product0_l0n1_part1_r;
    wire [74:0] unused_position_product0_l0n1_w;
    assign unused_position_product0_l0n1_w =
                {22'b0, {unused_position_product0_l0n1_part1_r[0:0],
                position_product0_l0n1_low0d0_r}, 17'b0};
    reg [35:0] unused_position_product0_l0n2_part0_r;
    reg [34:0] position_product0_l0n2_low0d0_r;
    reg [0:0] position_product0_l0n2_a1d0_r;
    reg [0:0] position_product0_l0n2_b1d0_r;
    reg [1:0] unused_position_product0_l0n2_part1_r;
    wire [74:0] unused_position_product0_l0n2_w;
    assign unused_position_product0_l0n2_w =
                {5'b0, {unused_position_product0_l0n2_part1_r[0:0],
                position_product0_l0n2_low0d0_r}, 34'b0};
    reg [35:0] unused_position_product0_l0n3_part0_r;
    reg [34:0] position_product0_l0n3_low0d0_r;
    reg [5:0] position_product0_l0n3_a1d0_r;
    reg [5:0] position_product0_l0n3_b1d0_r;
    reg [6:0] unused_position_product0_l0n3_part1_r;
    wire [74:0] unused_position_product0_l0n3_w;
    assign unused_position_product0_l0n3_w =
                {{unused_position_product0_l0n3_part1_r[5:0], position_product0_l0n3_low0d0_r},
                34'b0};
    reg [6:0] position_product0_l0n4_d0_r;
    reg [6:0] position_product0_l0n4_d1_r;
    wire [74:0] unused_position_product0_l0n4_w;
    assign unused_position_product0_l0n4_w = {position_product0_l0n4_d1_r, 68'b0};
    reg [35:0] unused_position_product0_l1n0_part0_r;
    reg [34:0] position_product0_l1n0_low0d0_r;
    reg [18:0] position_product0_l1n0_a1d0_r;
    reg [18:0] position_product0_l1n0_b1d0_r;
    reg [19:0] unused_position_product0_l1n0_part1_r;
    wire [74:0] unused_position_product0_l1n0_w;
    assign unused_position_product0_l1n0_w =
                {21'b0, {unused_position_product0_l1n0_part1_r[18:0],
                position_product0_l1n0_low0d0_r}};
    reg [35:0] unused_position_product0_l1n1_part0_r;
    reg [34:0] position_product0_l1n1_low0d0_r;
    reg [5:0] position_product0_l1n1_a1d0_r;
    reg [5:0] position_product0_l1n1_b1d0_r;
    reg [6:0] unused_position_product0_l1n1_part1_r;
    wire [74:0] unused_position_product0_l1n1_w;
    assign unused_position_product0_l1n1_w =
                {{unused_position_product0_l1n1_part1_r[5:0], position_product0_l1n1_low0d0_r},
                34'b0};
    reg [6:0] position_product0_l1n2_d0_r;
    reg [6:0] position_product0_l1n2_d1_r;
    wire [74:0] unused_position_product0_l1n2_w;
    assign unused_position_product0_l1n2_w = {position_product0_l1n2_d1_r, 68'b0};
    reg [35:0] unused_position_product0_l2n0_part0_r;
    reg [34:0] position_product0_l2n0_low0d0_r;
    reg [34:0] position_product0_l2n0_low0d1_r;
    reg [34:0] position_product0_l2n0_a1d0_r;
    reg [34:0] position_product0_l2n0_b1d0_r;
    reg [35:0] unused_position_product0_l2n0_part1_r;
    reg [34:0] position_product0_l2n0_low1d0_r;
    reg [4:0] position_product0_l2n0_a2d0_r;
    reg [4:0] position_product0_l2n0_a2d1_r;
    reg [4:0] position_product0_l2n0_b2d0_r;
    reg [4:0] position_product0_l2n0_b2d1_r;
    reg [5:0] unused_position_product0_l2n0_part2_r;
    wire [74:0] unused_position_product0_l2n0_w;
    assign unused_position_product0_l2n0_w =
                {unused_position_product0_l2n0_part2_r[4:0], position_product0_l2n0_low1d0_r,
                position_product0_l2n0_low0d1_r};
    reg [6:0] position_product0_l2n1_d0_r;
    reg [6:0] position_product0_l2n1_d1_r;
    reg [6:0] position_product0_l2n1_d2_r;
    wire [74:0] unused_position_product0_l2n1_w;
    assign unused_position_product0_l2n1_w = {position_product0_l2n1_d2_r, 68'b0};
    reg [35:0] unused_position_product0_l3n0_part0_r;
    reg [34:0] position_product0_l3n0_low0d0_r;
    reg [34:0] position_product0_l3n0_low0d1_r;
    reg [34:0] position_product0_l3n0_a1d0_r;
    reg [34:0] position_product0_l3n0_b1d0_r;
    reg [35:0] unused_position_product0_l3n0_part1_r;
    reg [34:0] position_product0_l3n0_low1d0_r;
    reg [4:0] position_product0_l3n0_a2d0_r;
    reg [4:0] position_product0_l3n0_a2d1_r;
    reg [4:0] position_product0_l3n0_b2d0_r;
    reg [4:0] position_product0_l3n0_b2d1_r;
    reg [5:0] unused_position_product0_l3n0_part2_r;
    wire [74:0] unused_position_product0_l3n0_w;
    assign unused_position_product0_l3n0_w =
                {unused_position_product0_l3n0_part2_r[4:0], position_product0_l3n0_low1d0_r,
                position_product0_l3n0_low0d1_r};
    assign position_product0_p2_r = unused_position_product0_l3n0_w;
    always @(posedge clk_i) begin
        if (pipeline_enable_w[1]) begin
            position_product0_pp00_r <=
                $signed({1'b0, position_product0_a_w[0 +: 17]}) * $signed({1'b0,
                position_product0_b_w[0 +: 17]});
            position_product0_pp01_r <=
                $signed({1'b0, position_product0_a_w[0 +: 17]}) * $signed({1'b0,
                position_product0_b_w[17 +: 17]});
            position_product0_pp02_r <=
                $signed({1'b0, position_product0_a_w[0 +: 17]}) * $signed({1'b0,
                position_product0_b_w[34 +: 1]});
            position_product0_pp10_r <=
                $signed({1'b0, position_product0_a_w[17 +: 17]}) * $signed({1'b0,
                position_product0_b_w[0 +: 17]});
            position_product0_pp11_r <=
                $signed({1'b0, position_product0_a_w[17 +: 17]}) * $signed({1'b0,
                position_product0_b_w[17 +: 17]});
            position_product0_pp12_r <=
                $signed({1'b0, position_product0_a_w[17 +: 17]}) * $signed({1'b0,
                position_product0_b_w[34 +: 1]});
            position_product0_pp20_r <=
                $signed(position_product0_a_w[34 +: 6]) * $signed({1'b0,
                position_product0_b_w[0 +: 17]});
            position_product0_pp21_r <=
                $signed(position_product0_a_w[34 +: 6]) * $signed({1'b0,
                position_product0_b_w[17 +: 17]});
            position_product0_pp22_r <=
                $signed(position_product0_a_w[34 +: 6]) * $signed({1'b0,
                position_product0_b_w[34 +: 1]});
            unused_position_product0_l0n0_part0_r <=
                {1'b0, unused_position_product0_term00_w[0 +: 35]} + {1'b0,
                unused_position_product0_term01_w[0 +: 35]};
            position_product0_l0n0_low0d0_r <= unused_position_product0_l0n0_part0_r[34:0];
            position_product0_l0n0_a1d0_r <= unused_position_product0_term00_w[35 +: 17];
            position_product0_l0n0_b1d0_r <= unused_position_product0_term01_w[35 +: 17];
            unused_position_product0_l0n0_part1_r <=
                {1'b0, position_product0_l0n0_a1d0_r} + {1'b0, position_product0_l0n0_b1d0_r} +
                {17'b0, unused_position_product0_l0n0_part0_r[35]};
            unused_position_product0_l0n1_part0_r <=
                {1'b0, unused_position_product0_term02_w[17 +: 35]} + {1'b0,
                unused_position_product0_term10_w[17 +: 35]};
            position_product0_l0n1_low0d0_r <= unused_position_product0_l0n1_part0_r[34:0];
            position_product0_l0n1_a1d0_r <= unused_position_product0_term02_w[52 +: 1];
            position_product0_l0n1_b1d0_r <= unused_position_product0_term10_w[52 +: 1];
            unused_position_product0_l0n1_part1_r <=
                {1'b0, position_product0_l0n1_a1d0_r} + {1'b0, position_product0_l0n1_b1d0_r} +
                {1'b0, unused_position_product0_l0n1_part0_r[35]};
            unused_position_product0_l0n2_part0_r <=
                {1'b0, unused_position_product0_term11_w[34 +: 35]} + {1'b0,
                unused_position_product0_term12_w[34 +: 35]};
            position_product0_l0n2_low0d0_r <= unused_position_product0_l0n2_part0_r[34:0];
            position_product0_l0n2_a1d0_r <= unused_position_product0_term11_w[69 +: 1];
            position_product0_l0n2_b1d0_r <= unused_position_product0_term12_w[69 +: 1];
            unused_position_product0_l0n2_part1_r <=
                {1'b0, position_product0_l0n2_a1d0_r} + {1'b0, position_product0_l0n2_b1d0_r} +
                {1'b0, unused_position_product0_l0n2_part0_r[35]};
            unused_position_product0_l0n3_part0_r <=
                {1'b0, unused_position_product0_term20_w[34 +: 35]} + {1'b0,
                unused_position_product0_term21_w[34 +: 35]};
            position_product0_l0n3_low0d0_r <= unused_position_product0_l0n3_part0_r[34:0];
            position_product0_l0n3_a1d0_r <= unused_position_product0_term20_w[69 +: 6];
            position_product0_l0n3_b1d0_r <= unused_position_product0_term21_w[69 +: 6];
            unused_position_product0_l0n3_part1_r <=
                {1'b0, position_product0_l0n3_a1d0_r} + {1'b0, position_product0_l0n3_b1d0_r} +
                {6'b0, unused_position_product0_l0n3_part0_r[35]};
            position_product0_l0n4_d0_r <= unused_position_product0_term22_w[68 +: 7];
            position_product0_l0n4_d1_r <= position_product0_l0n4_d0_r;
            unused_position_product0_l1n0_part0_r <=
                {1'b0, unused_position_product0_l0n0_w[0 +: 35]} + {1'b0,
                unused_position_product0_l0n1_w[0 +: 35]};
            position_product0_l1n0_low0d0_r <= unused_position_product0_l1n0_part0_r[34:0];
            position_product0_l1n0_a1d0_r <= unused_position_product0_l0n0_w[35 +: 19];
            position_product0_l1n0_b1d0_r <= unused_position_product0_l0n1_w[35 +: 19];
            unused_position_product0_l1n0_part1_r <=
                {1'b0, position_product0_l1n0_a1d0_r} + {1'b0, position_product0_l1n0_b1d0_r} +
                {19'b0, unused_position_product0_l1n0_part0_r[35]};
            unused_position_product0_l1n1_part0_r <=
                {1'b0, unused_position_product0_l0n2_w[34 +: 35]} + {1'b0,
                unused_position_product0_l0n3_w[34 +: 35]};
            position_product0_l1n1_low0d0_r <= unused_position_product0_l1n1_part0_r[34:0];
            position_product0_l1n1_a1d0_r <= unused_position_product0_l0n2_w[69 +: 6];
            position_product0_l1n1_b1d0_r <= unused_position_product0_l0n3_w[69 +: 6];
            unused_position_product0_l1n1_part1_r <=
                {1'b0, position_product0_l1n1_a1d0_r} + {1'b0, position_product0_l1n1_b1d0_r} +
                {6'b0, unused_position_product0_l1n1_part0_r[35]};
            position_product0_l1n2_d0_r <= unused_position_product0_l0n4_w[68 +: 7];
            position_product0_l1n2_d1_r <= position_product0_l1n2_d0_r;
            unused_position_product0_l2n0_part0_r <=
                {1'b0, unused_position_product0_l1n0_w[0 +: 35]} + {1'b0,
                unused_position_product0_l1n1_w[0 +: 35]};
            position_product0_l2n0_low0d0_r <= unused_position_product0_l2n0_part0_r[34:0];
            position_product0_l2n0_low0d1_r <= position_product0_l2n0_low0d0_r;
            position_product0_l2n0_a1d0_r <= unused_position_product0_l1n0_w[35 +: 35];
            position_product0_l2n0_b1d0_r <= unused_position_product0_l1n1_w[35 +: 35];
            unused_position_product0_l2n0_part1_r <=
                {1'b0, position_product0_l2n0_a1d0_r} + {1'b0, position_product0_l2n0_b1d0_r} +
                {35'b0, unused_position_product0_l2n0_part0_r[35]};
            position_product0_l2n0_low1d0_r <= unused_position_product0_l2n0_part1_r[34:0];
            position_product0_l2n0_a2d0_r <= unused_position_product0_l1n0_w[70 +: 5];
            position_product0_l2n0_a2d1_r <= position_product0_l2n0_a2d0_r;
            position_product0_l2n0_b2d0_r <= unused_position_product0_l1n1_w[70 +: 5];
            position_product0_l2n0_b2d1_r <= position_product0_l2n0_b2d0_r;
            unused_position_product0_l2n0_part2_r <=
                {1'b0, position_product0_l2n0_a2d1_r} + {1'b0, position_product0_l2n0_b2d1_r} +
                {5'b0, unused_position_product0_l2n0_part1_r[35]};
            position_product0_l2n1_d0_r <= unused_position_product0_l1n2_w[68 +: 7];
            position_product0_l2n1_d1_r <= position_product0_l2n1_d0_r;
            position_product0_l2n1_d2_r <= position_product0_l2n1_d1_r;
            unused_position_product0_l3n0_part0_r <=
                {1'b0, unused_position_product0_l2n0_w[0 +: 35]} + {1'b0,
                unused_position_product0_l2n1_w[0 +: 35]};
            position_product0_l3n0_low0d0_r <= unused_position_product0_l3n0_part0_r[34:0];
            position_product0_l3n0_low0d1_r <= position_product0_l3n0_low0d0_r;
            position_product0_l3n0_a1d0_r <= unused_position_product0_l2n0_w[35 +: 35];
            position_product0_l3n0_b1d0_r <= unused_position_product0_l2n1_w[35 +: 35];
            unused_position_product0_l3n0_part1_r <=
                {1'b0, position_product0_l3n0_a1d0_r} + {1'b0, position_product0_l3n0_b1d0_r} +
                {35'b0, unused_position_product0_l3n0_part0_r[35]};
            position_product0_l3n0_low1d0_r <= unused_position_product0_l3n0_part1_r[34:0];
            position_product0_l3n0_a2d0_r <= unused_position_product0_l2n0_w[70 +: 5];
            position_product0_l3n0_a2d1_r <= position_product0_l3n0_a2d0_r;
            position_product0_l3n0_b2d0_r <= unused_position_product0_l2n1_w[70 +: 5];
            position_product0_l3n0_b2d1_r <= position_product0_l3n0_b2d0_r;
            unused_position_product0_l3n0_part2_r <=
                {1'b0, position_product0_l3n0_a2d1_r} + {1'b0, position_product0_l3n0_b2d1_r} +
                {5'b0, unused_position_product0_l3n0_part1_r[35]};
        end
    end

    // position_product1: 40x35, 9 registered APM products; 11 enabled stages.
    wire [39:0] position_product1_a_w;
    assign position_product1_a_w = position_input1_r_d9_r;
    wire [34:0] position_product1_b_w;
    assign position_product1_b_w = restored_r;
    reg [33:0] position_product1_pp00_r;
    wire [74:0] unused_position_product1_term00_w;
    assign unused_position_product1_term00_w = {41'b0, position_product1_pp00_r} << 0;
    reg [33:0] position_product1_pp01_r;
    wire [74:0] unused_position_product1_term01_w;
    assign unused_position_product1_term01_w = {41'b0, position_product1_pp01_r} << 17;
    reg [17:0] position_product1_pp02_r;
    wire [74:0] unused_position_product1_term02_w;
    assign unused_position_product1_term02_w = {57'b0, position_product1_pp02_r} << 34;
    reg [33:0] position_product1_pp10_r;
    wire [74:0] unused_position_product1_term10_w;
    assign unused_position_product1_term10_w = {41'b0, position_product1_pp10_r} << 17;
    reg [33:0] position_product1_pp11_r;
    wire [74:0] unused_position_product1_term11_w;
    assign unused_position_product1_term11_w = {41'b0, position_product1_pp11_r} << 34;
    reg [17:0] position_product1_pp12_r;
    wire [74:0] unused_position_product1_term12_w;
    assign unused_position_product1_term12_w = {57'b0, position_product1_pp12_r} << 51;
    reg [22:0] position_product1_pp20_r;
    wire [74:0] unused_position_product1_term20_w;
    assign unused_position_product1_term20_w =
                {{52{position_product1_pp20_r[22]}}, position_product1_pp20_r} << 34;
    reg [22:0] position_product1_pp21_r;
    wire [74:0] unused_position_product1_term21_w;
    assign unused_position_product1_term21_w =
                {{52{position_product1_pp21_r[22]}}, position_product1_pp21_r} << 51;
    reg [6:0] position_product1_pp22_r;
    wire [74:0] unused_position_product1_term22_w;
    assign unused_position_product1_term22_w =
                {{68{position_product1_pp22_r[6]}}, position_product1_pp22_r} << 68;
    reg [35:0] unused_position_product1_l0n0_part0_r;
    reg [34:0] position_product1_l0n0_low0d0_r;
    reg [16:0] position_product1_l0n0_a1d0_r;
    reg [16:0] position_product1_l0n0_b1d0_r;
    reg [17:0] unused_position_product1_l0n0_part1_r;
    wire [74:0] unused_position_product1_l0n0_w;
    assign unused_position_product1_l0n0_w =
                {23'b0, {unused_position_product1_l0n0_part1_r[16:0],
                position_product1_l0n0_low0d0_r}};
    reg [35:0] unused_position_product1_l0n1_part0_r;
    reg [34:0] position_product1_l0n1_low0d0_r;
    reg [0:0] position_product1_l0n1_a1d0_r;
    reg [0:0] position_product1_l0n1_b1d0_r;
    reg [1:0] unused_position_product1_l0n1_part1_r;
    wire [74:0] unused_position_product1_l0n1_w;
    assign unused_position_product1_l0n1_w =
                {22'b0, {unused_position_product1_l0n1_part1_r[0:0],
                position_product1_l0n1_low0d0_r}, 17'b0};
    reg [35:0] unused_position_product1_l0n2_part0_r;
    reg [34:0] position_product1_l0n2_low0d0_r;
    reg [0:0] position_product1_l0n2_a1d0_r;
    reg [0:0] position_product1_l0n2_b1d0_r;
    reg [1:0] unused_position_product1_l0n2_part1_r;
    wire [74:0] unused_position_product1_l0n2_w;
    assign unused_position_product1_l0n2_w =
                {5'b0, {unused_position_product1_l0n2_part1_r[0:0],
                position_product1_l0n2_low0d0_r}, 34'b0};
    reg [35:0] unused_position_product1_l0n3_part0_r;
    reg [34:0] position_product1_l0n3_low0d0_r;
    reg [5:0] position_product1_l0n3_a1d0_r;
    reg [5:0] position_product1_l0n3_b1d0_r;
    reg [6:0] unused_position_product1_l0n3_part1_r;
    wire [74:0] unused_position_product1_l0n3_w;
    assign unused_position_product1_l0n3_w =
                {{unused_position_product1_l0n3_part1_r[5:0], position_product1_l0n3_low0d0_r},
                34'b0};
    reg [6:0] position_product1_l0n4_d0_r;
    reg [6:0] position_product1_l0n4_d1_r;
    wire [74:0] unused_position_product1_l0n4_w;
    assign unused_position_product1_l0n4_w = {position_product1_l0n4_d1_r, 68'b0};
    reg [35:0] unused_position_product1_l1n0_part0_r;
    reg [34:0] position_product1_l1n0_low0d0_r;
    reg [18:0] position_product1_l1n0_a1d0_r;
    reg [18:0] position_product1_l1n0_b1d0_r;
    reg [19:0] unused_position_product1_l1n0_part1_r;
    wire [74:0] unused_position_product1_l1n0_w;
    assign unused_position_product1_l1n0_w =
                {21'b0, {unused_position_product1_l1n0_part1_r[18:0],
                position_product1_l1n0_low0d0_r}};
    reg [35:0] unused_position_product1_l1n1_part0_r;
    reg [34:0] position_product1_l1n1_low0d0_r;
    reg [5:0] position_product1_l1n1_a1d0_r;
    reg [5:0] position_product1_l1n1_b1d0_r;
    reg [6:0] unused_position_product1_l1n1_part1_r;
    wire [74:0] unused_position_product1_l1n1_w;
    assign unused_position_product1_l1n1_w =
                {{unused_position_product1_l1n1_part1_r[5:0], position_product1_l1n1_low0d0_r},
                34'b0};
    reg [6:0] position_product1_l1n2_d0_r;
    reg [6:0] position_product1_l1n2_d1_r;
    wire [74:0] unused_position_product1_l1n2_w;
    assign unused_position_product1_l1n2_w = {position_product1_l1n2_d1_r, 68'b0};
    reg [35:0] unused_position_product1_l2n0_part0_r;
    reg [34:0] position_product1_l2n0_low0d0_r;
    reg [34:0] position_product1_l2n0_low0d1_r;
    reg [34:0] position_product1_l2n0_a1d0_r;
    reg [34:0] position_product1_l2n0_b1d0_r;
    reg [35:0] unused_position_product1_l2n0_part1_r;
    reg [34:0] position_product1_l2n0_low1d0_r;
    reg [4:0] position_product1_l2n0_a2d0_r;
    reg [4:0] position_product1_l2n0_a2d1_r;
    reg [4:0] position_product1_l2n0_b2d0_r;
    reg [4:0] position_product1_l2n0_b2d1_r;
    reg [5:0] unused_position_product1_l2n0_part2_r;
    wire [74:0] unused_position_product1_l2n0_w;
    assign unused_position_product1_l2n0_w =
                {unused_position_product1_l2n0_part2_r[4:0], position_product1_l2n0_low1d0_r,
                position_product1_l2n0_low0d1_r};
    reg [6:0] position_product1_l2n1_d0_r;
    reg [6:0] position_product1_l2n1_d1_r;
    reg [6:0] position_product1_l2n1_d2_r;
    wire [74:0] unused_position_product1_l2n1_w;
    assign unused_position_product1_l2n1_w = {position_product1_l2n1_d2_r, 68'b0};
    reg [35:0] unused_position_product1_l3n0_part0_r;
    reg [34:0] position_product1_l3n0_low0d0_r;
    reg [34:0] position_product1_l3n0_low0d1_r;
    reg [34:0] position_product1_l3n0_a1d0_r;
    reg [34:0] position_product1_l3n0_b1d0_r;
    reg [35:0] unused_position_product1_l3n0_part1_r;
    reg [34:0] position_product1_l3n0_low1d0_r;
    reg [4:0] position_product1_l3n0_a2d0_r;
    reg [4:0] position_product1_l3n0_a2d1_r;
    reg [4:0] position_product1_l3n0_b2d0_r;
    reg [4:0] position_product1_l3n0_b2d1_r;
    reg [5:0] unused_position_product1_l3n0_part2_r;
    wire [74:0] unused_position_product1_l3n0_w;
    assign unused_position_product1_l3n0_w =
                {unused_position_product1_l3n0_part2_r[4:0], position_product1_l3n0_low1d0_r,
                position_product1_l3n0_low0d1_r};
    assign position_product1_p2_r = unused_position_product1_l3n0_w;
    always @(posedge clk_i) begin
        if (pipeline_enable_w[9]) begin
            position_product1_pp00_r <=
                $signed({1'b0, position_product1_a_w[0 +: 17]}) * $signed({1'b0,
                position_product1_b_w[0 +: 17]});
            position_product1_pp01_r <=
                $signed({1'b0, position_product1_a_w[0 +: 17]}) * $signed({1'b0,
                position_product1_b_w[17 +: 17]});
            position_product1_pp02_r <=
                $signed({1'b0, position_product1_a_w[0 +: 17]}) * $signed({1'b0,
                position_product1_b_w[34 +: 1]});
            position_product1_pp10_r <=
                $signed({1'b0, position_product1_a_w[17 +: 17]}) * $signed({1'b0,
                position_product1_b_w[0 +: 17]});
            position_product1_pp11_r <=
                $signed({1'b0, position_product1_a_w[17 +: 17]}) * $signed({1'b0,
                position_product1_b_w[17 +: 17]});
            position_product1_pp12_r <=
                $signed({1'b0, position_product1_a_w[17 +: 17]}) * $signed({1'b0,
                position_product1_b_w[34 +: 1]});
            position_product1_pp20_r <=
                $signed(position_product1_a_w[34 +: 6]) * $signed({1'b0,
                position_product1_b_w[0 +: 17]});
            position_product1_pp21_r <=
                $signed(position_product1_a_w[34 +: 6]) * $signed({1'b0,
                position_product1_b_w[17 +: 17]});
            position_product1_pp22_r <=
                $signed(position_product1_a_w[34 +: 6]) * $signed({1'b0,
                position_product1_b_w[34 +: 1]});
            unused_position_product1_l0n0_part0_r <=
                {1'b0, unused_position_product1_term00_w[0 +: 35]} + {1'b0,
                unused_position_product1_term01_w[0 +: 35]};
            position_product1_l0n0_low0d0_r <= unused_position_product1_l0n0_part0_r[34:0];
            position_product1_l0n0_a1d0_r <= unused_position_product1_term00_w[35 +: 17];
            position_product1_l0n0_b1d0_r <= unused_position_product1_term01_w[35 +: 17];
            unused_position_product1_l0n0_part1_r <=
                {1'b0, position_product1_l0n0_a1d0_r} + {1'b0, position_product1_l0n0_b1d0_r} +
                {17'b0, unused_position_product1_l0n0_part0_r[35]};
            unused_position_product1_l0n1_part0_r <=
                {1'b0, unused_position_product1_term02_w[17 +: 35]} + {1'b0,
                unused_position_product1_term10_w[17 +: 35]};
            position_product1_l0n1_low0d0_r <= unused_position_product1_l0n1_part0_r[34:0];
            position_product1_l0n1_a1d0_r <= unused_position_product1_term02_w[52 +: 1];
            position_product1_l0n1_b1d0_r <= unused_position_product1_term10_w[52 +: 1];
            unused_position_product1_l0n1_part1_r <=
                {1'b0, position_product1_l0n1_a1d0_r} + {1'b0, position_product1_l0n1_b1d0_r} +
                {1'b0, unused_position_product1_l0n1_part0_r[35]};
            unused_position_product1_l0n2_part0_r <=
                {1'b0, unused_position_product1_term11_w[34 +: 35]} + {1'b0,
                unused_position_product1_term12_w[34 +: 35]};
            position_product1_l0n2_low0d0_r <= unused_position_product1_l0n2_part0_r[34:0];
            position_product1_l0n2_a1d0_r <= unused_position_product1_term11_w[69 +: 1];
            position_product1_l0n2_b1d0_r <= unused_position_product1_term12_w[69 +: 1];
            unused_position_product1_l0n2_part1_r <=
                {1'b0, position_product1_l0n2_a1d0_r} + {1'b0, position_product1_l0n2_b1d0_r} +
                {1'b0, unused_position_product1_l0n2_part0_r[35]};
            unused_position_product1_l0n3_part0_r <=
                {1'b0, unused_position_product1_term20_w[34 +: 35]} + {1'b0,
                unused_position_product1_term21_w[34 +: 35]};
            position_product1_l0n3_low0d0_r <= unused_position_product1_l0n3_part0_r[34:0];
            position_product1_l0n3_a1d0_r <= unused_position_product1_term20_w[69 +: 6];
            position_product1_l0n3_b1d0_r <= unused_position_product1_term21_w[69 +: 6];
            unused_position_product1_l0n3_part1_r <=
                {1'b0, position_product1_l0n3_a1d0_r} + {1'b0, position_product1_l0n3_b1d0_r} +
                {6'b0, unused_position_product1_l0n3_part0_r[35]};
            position_product1_l0n4_d0_r <= unused_position_product1_term22_w[68 +: 7];
            position_product1_l0n4_d1_r <= position_product1_l0n4_d0_r;
            unused_position_product1_l1n0_part0_r <=
                {1'b0, unused_position_product1_l0n0_w[0 +: 35]} + {1'b0,
                unused_position_product1_l0n1_w[0 +: 35]};
            position_product1_l1n0_low0d0_r <= unused_position_product1_l1n0_part0_r[34:0];
            position_product1_l1n0_a1d0_r <= unused_position_product1_l0n0_w[35 +: 19];
            position_product1_l1n0_b1d0_r <= unused_position_product1_l0n1_w[35 +: 19];
            unused_position_product1_l1n0_part1_r <=
                {1'b0, position_product1_l1n0_a1d0_r} + {1'b0, position_product1_l1n0_b1d0_r} +
                {19'b0, unused_position_product1_l1n0_part0_r[35]};
            unused_position_product1_l1n1_part0_r <=
                {1'b0, unused_position_product1_l0n2_w[34 +: 35]} + {1'b0,
                unused_position_product1_l0n3_w[34 +: 35]};
            position_product1_l1n1_low0d0_r <= unused_position_product1_l1n1_part0_r[34:0];
            position_product1_l1n1_a1d0_r <= unused_position_product1_l0n2_w[69 +: 6];
            position_product1_l1n1_b1d0_r <= unused_position_product1_l0n3_w[69 +: 6];
            unused_position_product1_l1n1_part1_r <=
                {1'b0, position_product1_l1n1_a1d0_r} + {1'b0, position_product1_l1n1_b1d0_r} +
                {6'b0, unused_position_product1_l1n1_part0_r[35]};
            position_product1_l1n2_d0_r <= unused_position_product1_l0n4_w[68 +: 7];
            position_product1_l1n2_d1_r <= position_product1_l1n2_d0_r;
            unused_position_product1_l2n0_part0_r <=
                {1'b0, unused_position_product1_l1n0_w[0 +: 35]} + {1'b0,
                unused_position_product1_l1n1_w[0 +: 35]};
            position_product1_l2n0_low0d0_r <= unused_position_product1_l2n0_part0_r[34:0];
            position_product1_l2n0_low0d1_r <= position_product1_l2n0_low0d0_r;
            position_product1_l2n0_a1d0_r <= unused_position_product1_l1n0_w[35 +: 35];
            position_product1_l2n0_b1d0_r <= unused_position_product1_l1n1_w[35 +: 35];
            unused_position_product1_l2n0_part1_r <=
                {1'b0, position_product1_l2n0_a1d0_r} + {1'b0, position_product1_l2n0_b1d0_r} +
                {35'b0, unused_position_product1_l2n0_part0_r[35]};
            position_product1_l2n0_low1d0_r <= unused_position_product1_l2n0_part1_r[34:0];
            position_product1_l2n0_a2d0_r <= unused_position_product1_l1n0_w[70 +: 5];
            position_product1_l2n0_a2d1_r <= position_product1_l2n0_a2d0_r;
            position_product1_l2n0_b2d0_r <= unused_position_product1_l1n1_w[70 +: 5];
            position_product1_l2n0_b2d1_r <= position_product1_l2n0_b2d0_r;
            unused_position_product1_l2n0_part2_r <=
                {1'b0, position_product1_l2n0_a2d1_r} + {1'b0, position_product1_l2n0_b2d1_r} +
                {5'b0, unused_position_product1_l2n0_part1_r[35]};
            position_product1_l2n1_d0_r <= unused_position_product1_l1n2_w[68 +: 7];
            position_product1_l2n1_d1_r <= position_product1_l2n1_d0_r;
            position_product1_l2n1_d2_r <= position_product1_l2n1_d1_r;
            unused_position_product1_l3n0_part0_r <=
                {1'b0, unused_position_product1_l2n0_w[0 +: 35]} + {1'b0,
                unused_position_product1_l2n1_w[0 +: 35]};
            position_product1_l3n0_low0d0_r <= unused_position_product1_l3n0_part0_r[34:0];
            position_product1_l3n0_low0d1_r <= position_product1_l3n0_low0d0_r;
            position_product1_l3n0_a1d0_r <= unused_position_product1_l2n0_w[35 +: 35];
            position_product1_l3n0_b1d0_r <= unused_position_product1_l2n1_w[35 +: 35];
            unused_position_product1_l3n0_part1_r <=
                {1'b0, position_product1_l3n0_a1d0_r} + {1'b0, position_product1_l3n0_b1d0_r} +
                {35'b0, unused_position_product1_l3n0_part0_r[35]};
            position_product1_l3n0_low1d0_r <= unused_position_product1_l3n0_part1_r[34:0];
            position_product1_l3n0_a2d0_r <= unused_position_product1_l2n0_w[70 +: 5];
            position_product1_l3n0_a2d1_r <= position_product1_l3n0_a2d0_r;
            position_product1_l3n0_b2d0_r <= unused_position_product1_l2n1_w[70 +: 5];
            position_product1_l3n0_b2d1_r <= position_product1_l3n0_b2d0_r;
            unused_position_product1_l3n0_part2_r <=
                {1'b0, position_product1_l3n0_a2d1_r} + {1'b0, position_product1_l3n0_b2d1_r} +
                {5'b0, unused_position_product1_l3n0_part1_r[35]};
        end
    end

    // position_product2: 40x35, 9 registered APM products; 11 enabled stages.
    wire [39:0] position_product2_a_w;
    assign position_product2_a_w = position_input2_r_d9_r;
    wire [34:0] position_product2_b_w;
    assign position_product2_b_w = restored_r;
    reg [33:0] position_product2_pp00_r;
    wire [74:0] unused_position_product2_term00_w;
    assign unused_position_product2_term00_w = {41'b0, position_product2_pp00_r} << 0;
    reg [33:0] position_product2_pp01_r;
    wire [74:0] unused_position_product2_term01_w;
    assign unused_position_product2_term01_w = {41'b0, position_product2_pp01_r} << 17;
    reg [17:0] position_product2_pp02_r;
    wire [74:0] unused_position_product2_term02_w;
    assign unused_position_product2_term02_w = {57'b0, position_product2_pp02_r} << 34;
    reg [33:0] position_product2_pp10_r;
    wire [74:0] unused_position_product2_term10_w;
    assign unused_position_product2_term10_w = {41'b0, position_product2_pp10_r} << 17;
    reg [33:0] position_product2_pp11_r;
    wire [74:0] unused_position_product2_term11_w;
    assign unused_position_product2_term11_w = {41'b0, position_product2_pp11_r} << 34;
    reg [17:0] position_product2_pp12_r;
    wire [74:0] unused_position_product2_term12_w;
    assign unused_position_product2_term12_w = {57'b0, position_product2_pp12_r} << 51;
    reg [22:0] position_product2_pp20_r;
    wire [74:0] unused_position_product2_term20_w;
    assign unused_position_product2_term20_w =
                {{52{position_product2_pp20_r[22]}}, position_product2_pp20_r} << 34;
    reg [22:0] position_product2_pp21_r;
    wire [74:0] unused_position_product2_term21_w;
    assign unused_position_product2_term21_w =
                {{52{position_product2_pp21_r[22]}}, position_product2_pp21_r} << 51;
    reg [6:0] position_product2_pp22_r;
    wire [74:0] unused_position_product2_term22_w;
    assign unused_position_product2_term22_w =
                {{68{position_product2_pp22_r[6]}}, position_product2_pp22_r} << 68;
    reg [35:0] unused_position_product2_l0n0_part0_r;
    reg [34:0] position_product2_l0n0_low0d0_r;
    reg [16:0] position_product2_l0n0_a1d0_r;
    reg [16:0] position_product2_l0n0_b1d0_r;
    reg [17:0] unused_position_product2_l0n0_part1_r;
    wire [74:0] unused_position_product2_l0n0_w;
    assign unused_position_product2_l0n0_w =
                {23'b0, {unused_position_product2_l0n0_part1_r[16:0],
                position_product2_l0n0_low0d0_r}};
    reg [35:0] unused_position_product2_l0n1_part0_r;
    reg [34:0] position_product2_l0n1_low0d0_r;
    reg [0:0] position_product2_l0n1_a1d0_r;
    reg [0:0] position_product2_l0n1_b1d0_r;
    reg [1:0] unused_position_product2_l0n1_part1_r;
    wire [74:0] unused_position_product2_l0n1_w;
    assign unused_position_product2_l0n1_w =
                {22'b0, {unused_position_product2_l0n1_part1_r[0:0],
                position_product2_l0n1_low0d0_r}, 17'b0};
    reg [35:0] unused_position_product2_l0n2_part0_r;
    reg [34:0] position_product2_l0n2_low0d0_r;
    reg [0:0] position_product2_l0n2_a1d0_r;
    reg [0:0] position_product2_l0n2_b1d0_r;
    reg [1:0] unused_position_product2_l0n2_part1_r;
    wire [74:0] unused_position_product2_l0n2_w;
    assign unused_position_product2_l0n2_w =
                {5'b0, {unused_position_product2_l0n2_part1_r[0:0],
                position_product2_l0n2_low0d0_r}, 34'b0};
    reg [35:0] unused_position_product2_l0n3_part0_r;
    reg [34:0] position_product2_l0n3_low0d0_r;
    reg [5:0] position_product2_l0n3_a1d0_r;
    reg [5:0] position_product2_l0n3_b1d0_r;
    reg [6:0] unused_position_product2_l0n3_part1_r;
    wire [74:0] unused_position_product2_l0n3_w;
    assign unused_position_product2_l0n3_w =
                {{unused_position_product2_l0n3_part1_r[5:0], position_product2_l0n3_low0d0_r},
                34'b0};
    reg [6:0] position_product2_l0n4_d0_r;
    reg [6:0] position_product2_l0n4_d1_r;
    wire [74:0] unused_position_product2_l0n4_w;
    assign unused_position_product2_l0n4_w = {position_product2_l0n4_d1_r, 68'b0};
    reg [35:0] unused_position_product2_l1n0_part0_r;
    reg [34:0] position_product2_l1n0_low0d0_r;
    reg [18:0] position_product2_l1n0_a1d0_r;
    reg [18:0] position_product2_l1n0_b1d0_r;
    reg [19:0] unused_position_product2_l1n0_part1_r;
    wire [74:0] unused_position_product2_l1n0_w;
    assign unused_position_product2_l1n0_w =
                {21'b0, {unused_position_product2_l1n0_part1_r[18:0],
                position_product2_l1n0_low0d0_r}};
    reg [35:0] unused_position_product2_l1n1_part0_r;
    reg [34:0] position_product2_l1n1_low0d0_r;
    reg [5:0] position_product2_l1n1_a1d0_r;
    reg [5:0] position_product2_l1n1_b1d0_r;
    reg [6:0] unused_position_product2_l1n1_part1_r;
    wire [74:0] unused_position_product2_l1n1_w;
    assign unused_position_product2_l1n1_w =
                {{unused_position_product2_l1n1_part1_r[5:0], position_product2_l1n1_low0d0_r},
                34'b0};
    reg [6:0] position_product2_l1n2_d0_r;
    reg [6:0] position_product2_l1n2_d1_r;
    wire [74:0] unused_position_product2_l1n2_w;
    assign unused_position_product2_l1n2_w = {position_product2_l1n2_d1_r, 68'b0};
    reg [35:0] unused_position_product2_l2n0_part0_r;
    reg [34:0] position_product2_l2n0_low0d0_r;
    reg [34:0] position_product2_l2n0_low0d1_r;
    reg [34:0] position_product2_l2n0_a1d0_r;
    reg [34:0] position_product2_l2n0_b1d0_r;
    reg [35:0] unused_position_product2_l2n0_part1_r;
    reg [34:0] position_product2_l2n0_low1d0_r;
    reg [4:0] position_product2_l2n0_a2d0_r;
    reg [4:0] position_product2_l2n0_a2d1_r;
    reg [4:0] position_product2_l2n0_b2d0_r;
    reg [4:0] position_product2_l2n0_b2d1_r;
    reg [5:0] unused_position_product2_l2n0_part2_r;
    wire [74:0] unused_position_product2_l2n0_w;
    assign unused_position_product2_l2n0_w =
                {unused_position_product2_l2n0_part2_r[4:0], position_product2_l2n0_low1d0_r,
                position_product2_l2n0_low0d1_r};
    reg [6:0] position_product2_l2n1_d0_r;
    reg [6:0] position_product2_l2n1_d1_r;
    reg [6:0] position_product2_l2n1_d2_r;
    wire [74:0] unused_position_product2_l2n1_w;
    assign unused_position_product2_l2n1_w = {position_product2_l2n1_d2_r, 68'b0};
    reg [35:0] unused_position_product2_l3n0_part0_r;
    reg [34:0] position_product2_l3n0_low0d0_r;
    reg [34:0] position_product2_l3n0_low0d1_r;
    reg [34:0] position_product2_l3n0_a1d0_r;
    reg [34:0] position_product2_l3n0_b1d0_r;
    reg [35:0] unused_position_product2_l3n0_part1_r;
    reg [34:0] position_product2_l3n0_low1d0_r;
    reg [4:0] position_product2_l3n0_a2d0_r;
    reg [4:0] position_product2_l3n0_a2d1_r;
    reg [4:0] position_product2_l3n0_b2d0_r;
    reg [4:0] position_product2_l3n0_b2d1_r;
    reg [5:0] unused_position_product2_l3n0_part2_r;
    wire [74:0] unused_position_product2_l3n0_w;
    assign unused_position_product2_l3n0_w =
                {unused_position_product2_l3n0_part2_r[4:0], position_product2_l3n0_low1d0_r,
                position_product2_l3n0_low0d1_r};
    assign position_product2_p2_r = unused_position_product2_l3n0_w;
    always @(posedge clk_i) begin
        if (pipeline_enable_w[10]) begin
            position_product2_pp00_r <=
                $signed({1'b0, position_product2_a_w[0 +: 17]}) * $signed({1'b0,
                position_product2_b_w[0 +: 17]});
            position_product2_pp01_r <=
                $signed({1'b0, position_product2_a_w[0 +: 17]}) * $signed({1'b0,
                position_product2_b_w[17 +: 17]});
            position_product2_pp02_r <=
                $signed({1'b0, position_product2_a_w[0 +: 17]}) * $signed({1'b0,
                position_product2_b_w[34 +: 1]});
            position_product2_pp10_r <=
                $signed({1'b0, position_product2_a_w[17 +: 17]}) * $signed({1'b0,
                position_product2_b_w[0 +: 17]});
            position_product2_pp11_r <=
                $signed({1'b0, position_product2_a_w[17 +: 17]}) * $signed({1'b0,
                position_product2_b_w[17 +: 17]});
            position_product2_pp12_r <=
                $signed({1'b0, position_product2_a_w[17 +: 17]}) * $signed({1'b0,
                position_product2_b_w[34 +: 1]});
            position_product2_pp20_r <=
                $signed(position_product2_a_w[34 +: 6]) * $signed({1'b0,
                position_product2_b_w[0 +: 17]});
            position_product2_pp21_r <=
                $signed(position_product2_a_w[34 +: 6]) * $signed({1'b0,
                position_product2_b_w[17 +: 17]});
            position_product2_pp22_r <=
                $signed(position_product2_a_w[34 +: 6]) * $signed({1'b0,
                position_product2_b_w[34 +: 1]});
            unused_position_product2_l0n0_part0_r <=
                {1'b0, unused_position_product2_term00_w[0 +: 35]} + {1'b0,
                unused_position_product2_term01_w[0 +: 35]};
            position_product2_l0n0_low0d0_r <= unused_position_product2_l0n0_part0_r[34:0];
            position_product2_l0n0_a1d0_r <= unused_position_product2_term00_w[35 +: 17];
            position_product2_l0n0_b1d0_r <= unused_position_product2_term01_w[35 +: 17];
            unused_position_product2_l0n0_part1_r <=
                {1'b0, position_product2_l0n0_a1d0_r} + {1'b0, position_product2_l0n0_b1d0_r} +
                {17'b0, unused_position_product2_l0n0_part0_r[35]};
            unused_position_product2_l0n1_part0_r <=
                {1'b0, unused_position_product2_term02_w[17 +: 35]} + {1'b0,
                unused_position_product2_term10_w[17 +: 35]};
            position_product2_l0n1_low0d0_r <= unused_position_product2_l0n1_part0_r[34:0];
            position_product2_l0n1_a1d0_r <= unused_position_product2_term02_w[52 +: 1];
            position_product2_l0n1_b1d0_r <= unused_position_product2_term10_w[52 +: 1];
            unused_position_product2_l0n1_part1_r <=
                {1'b0, position_product2_l0n1_a1d0_r} + {1'b0, position_product2_l0n1_b1d0_r} +
                {1'b0, unused_position_product2_l0n1_part0_r[35]};
            unused_position_product2_l0n2_part0_r <=
                {1'b0, unused_position_product2_term11_w[34 +: 35]} + {1'b0,
                unused_position_product2_term12_w[34 +: 35]};
            position_product2_l0n2_low0d0_r <= unused_position_product2_l0n2_part0_r[34:0];
            position_product2_l0n2_a1d0_r <= unused_position_product2_term11_w[69 +: 1];
            position_product2_l0n2_b1d0_r <= unused_position_product2_term12_w[69 +: 1];
            unused_position_product2_l0n2_part1_r <=
                {1'b0, position_product2_l0n2_a1d0_r} + {1'b0, position_product2_l0n2_b1d0_r} +
                {1'b0, unused_position_product2_l0n2_part0_r[35]};
            unused_position_product2_l0n3_part0_r <=
                {1'b0, unused_position_product2_term20_w[34 +: 35]} + {1'b0,
                unused_position_product2_term21_w[34 +: 35]};
            position_product2_l0n3_low0d0_r <= unused_position_product2_l0n3_part0_r[34:0];
            position_product2_l0n3_a1d0_r <= unused_position_product2_term20_w[69 +: 6];
            position_product2_l0n3_b1d0_r <= unused_position_product2_term21_w[69 +: 6];
            unused_position_product2_l0n3_part1_r <=
                {1'b0, position_product2_l0n3_a1d0_r} + {1'b0, position_product2_l0n3_b1d0_r} +
                {6'b0, unused_position_product2_l0n3_part0_r[35]};
            position_product2_l0n4_d0_r <= unused_position_product2_term22_w[68 +: 7];
            position_product2_l0n4_d1_r <= position_product2_l0n4_d0_r;
            unused_position_product2_l1n0_part0_r <=
                {1'b0, unused_position_product2_l0n0_w[0 +: 35]} + {1'b0,
                unused_position_product2_l0n1_w[0 +: 35]};
            position_product2_l1n0_low0d0_r <= unused_position_product2_l1n0_part0_r[34:0];
            position_product2_l1n0_a1d0_r <= unused_position_product2_l0n0_w[35 +: 19];
            position_product2_l1n0_b1d0_r <= unused_position_product2_l0n1_w[35 +: 19];
            unused_position_product2_l1n0_part1_r <=
                {1'b0, position_product2_l1n0_a1d0_r} + {1'b0, position_product2_l1n0_b1d0_r} +
                {19'b0, unused_position_product2_l1n0_part0_r[35]};
            unused_position_product2_l1n1_part0_r <=
                {1'b0, unused_position_product2_l0n2_w[34 +: 35]} + {1'b0,
                unused_position_product2_l0n3_w[34 +: 35]};
            position_product2_l1n1_low0d0_r <= unused_position_product2_l1n1_part0_r[34:0];
            position_product2_l1n1_a1d0_r <= unused_position_product2_l0n2_w[69 +: 6];
            position_product2_l1n1_b1d0_r <= unused_position_product2_l0n3_w[69 +: 6];
            unused_position_product2_l1n1_part1_r <=
                {1'b0, position_product2_l1n1_a1d0_r} + {1'b0, position_product2_l1n1_b1d0_r} +
                {6'b0, unused_position_product2_l1n1_part0_r[35]};
            position_product2_l1n2_d0_r <= unused_position_product2_l0n4_w[68 +: 7];
            position_product2_l1n2_d1_r <= position_product2_l1n2_d0_r;
            unused_position_product2_l2n0_part0_r <=
                {1'b0, unused_position_product2_l1n0_w[0 +: 35]} + {1'b0,
                unused_position_product2_l1n1_w[0 +: 35]};
            position_product2_l2n0_low0d0_r <= unused_position_product2_l2n0_part0_r[34:0];
            position_product2_l2n0_low0d1_r <= position_product2_l2n0_low0d0_r;
            position_product2_l2n0_a1d0_r <= unused_position_product2_l1n0_w[35 +: 35];
            position_product2_l2n0_b1d0_r <= unused_position_product2_l1n1_w[35 +: 35];
            unused_position_product2_l2n0_part1_r <=
                {1'b0, position_product2_l2n0_a1d0_r} + {1'b0, position_product2_l2n0_b1d0_r} +
                {35'b0, unused_position_product2_l2n0_part0_r[35]};
            position_product2_l2n0_low1d0_r <= unused_position_product2_l2n0_part1_r[34:0];
            position_product2_l2n0_a2d0_r <= unused_position_product2_l1n0_w[70 +: 5];
            position_product2_l2n0_a2d1_r <= position_product2_l2n0_a2d0_r;
            position_product2_l2n0_b2d0_r <= unused_position_product2_l1n1_w[70 +: 5];
            position_product2_l2n0_b2d1_r <= position_product2_l2n0_b2d0_r;
            unused_position_product2_l2n0_part2_r <=
                {1'b0, position_product2_l2n0_a2d1_r} + {1'b0, position_product2_l2n0_b2d1_r} +
                {5'b0, unused_position_product2_l2n0_part1_r[35]};
            position_product2_l2n1_d0_r <= unused_position_product2_l1n2_w[68 +: 7];
            position_product2_l2n1_d1_r <= position_product2_l2n1_d0_r;
            position_product2_l2n1_d2_r <= position_product2_l2n1_d1_r;
            unused_position_product2_l3n0_part0_r <=
                {1'b0, unused_position_product2_l2n0_w[0 +: 35]} + {1'b0,
                unused_position_product2_l2n1_w[0 +: 35]};
            position_product2_l3n0_low0d0_r <= unused_position_product2_l3n0_part0_r[34:0];
            position_product2_l3n0_low0d1_r <= position_product2_l3n0_low0d0_r;
            position_product2_l3n0_a1d0_r <= unused_position_product2_l2n0_w[35 +: 35];
            position_product2_l3n0_b1d0_r <= unused_position_product2_l2n1_w[35 +: 35];
            unused_position_product2_l3n0_part1_r <=
                {1'b0, position_product2_l3n0_a1d0_r} + {1'b0, position_product2_l3n0_b1d0_r} +
                {35'b0, unused_position_product2_l3n0_part0_r[35]};
            position_product2_l3n0_low1d0_r <= unused_position_product2_l3n0_part1_r[34:0];
            position_product2_l3n0_a2d0_r <= unused_position_product2_l2n0_w[70 +: 5];
            position_product2_l3n0_a2d1_r <= position_product2_l3n0_a2d0_r;
            position_product2_l3n0_b2d0_r <= unused_position_product2_l2n1_w[70 +: 5];
            position_product2_l3n0_b2d1_r <= position_product2_l3n0_b2d0_r;
            unused_position_product2_l3n0_part2_r <=
                {1'b0, position_product2_l3n0_a2d1_r} + {1'b0, position_product2_l3n0_b2d1_r} +
                {5'b0, unused_position_product2_l3n0_part1_r[35]};
        end
    end

    // uv_product0: 16x35, 3 registered APM products; 5 enabled stages.
    wire [15:0] uv_product0_a_w;
    assign uv_product0_a_w = uv_input0_r_d9_r;
    wire [34:0] uv_product0_b_w;
    assign uv_product0_b_w = restored_r;
    reg [32:0] uv_product0_pp00_r;
    wire [50:0] unused_uv_product0_term00_w;
    assign unused_uv_product0_term00_w = {18'b0, uv_product0_pp00_r} << 0;
    reg [32:0] uv_product0_pp01_r;
    wire [50:0] unused_uv_product0_term01_w;
    assign unused_uv_product0_term01_w = {18'b0, uv_product0_pp01_r} << 17;
    reg [16:0] uv_product0_pp02_r;
    wire [50:0] unused_uv_product0_term02_w;
    assign unused_uv_product0_term02_w = {34'b0, uv_product0_pp02_r} << 34;
    reg [35:0] unused_uv_product0_l0n0_part0_r;
    reg [34:0] uv_product0_l0n0_low0d0_r;
    reg [15:0] uv_product0_l0n0_a1d0_r;
    reg [15:0] uv_product0_l0n0_b1d0_r;
    reg [16:0] unused_uv_product0_l0n0_part1_r;
    wire [50:0] unused_uv_product0_l0n0_w;
    assign unused_uv_product0_l0n0_w =
                {unused_uv_product0_l0n0_part1_r[15:0], uv_product0_l0n0_low0d0_r};
    reg [16:0] uv_product0_l0n1_d0_r;
    reg [16:0] uv_product0_l0n1_d1_r;
    wire [50:0] unused_uv_product0_l0n1_w;
    assign unused_uv_product0_l0n1_w = {uv_product0_l0n1_d1_r, 34'b0};
    reg [35:0] unused_uv_product0_l1n0_part0_r;
    reg [34:0] uv_product0_l1n0_low0d0_r;
    reg [15:0] uv_product0_l1n0_a1d0_r;
    reg [15:0] uv_product0_l1n0_b1d0_r;
    reg [16:0] unused_uv_product0_l1n0_part1_r;
    wire [50:0] unused_uv_product0_l1n0_w;
    assign unused_uv_product0_l1n0_w =
                {unused_uv_product0_l1n0_part1_r[15:0], uv_product0_l1n0_low0d0_r};
    assign uv_product0_p2_r = unused_uv_product0_l1n0_w;
    always @(posedge clk_i) begin
        if (pipeline_enable_w[2]) begin
            uv_product0_pp00_r <=
                $signed({1'b0, uv_product0_a_w[0 +: 16]}) * $signed({1'b0, uv_product0_b_w[0 +: 17]
                });
            uv_product0_pp01_r <=
                $signed({1'b0, uv_product0_a_w[0 +: 16]}) * $signed({1'b0,
                uv_product0_b_w[17 +: 17]});
            uv_product0_pp02_r <=
                $signed({1'b0, uv_product0_a_w[0 +: 16]}) * $signed({1'b0, uv_product0_b_w[34 +: 1]
                });
            unused_uv_product0_l0n0_part0_r <=
                {1'b0, unused_uv_product0_term00_w[0 +: 35]} + {1'b0,
                unused_uv_product0_term01_w[0 +: 35]};
            uv_product0_l0n0_low0d0_r <= unused_uv_product0_l0n0_part0_r[34:0];
            uv_product0_l0n0_a1d0_r <= unused_uv_product0_term00_w[35 +: 16];
            uv_product0_l0n0_b1d0_r <= unused_uv_product0_term01_w[35 +: 16];
            unused_uv_product0_l0n0_part1_r <=
                {1'b0, uv_product0_l0n0_a1d0_r} + {1'b0, uv_product0_l0n0_b1d0_r} + {16'b0,
                unused_uv_product0_l0n0_part0_r[35]};
            uv_product0_l0n1_d0_r <= unused_uv_product0_term02_w[34 +: 17];
            uv_product0_l0n1_d1_r <= uv_product0_l0n1_d0_r;
            unused_uv_product0_l1n0_part0_r <=
                {1'b0, unused_uv_product0_l0n0_w[0 +: 35]} + {1'b0,
                unused_uv_product0_l0n1_w[0 +: 35]};
            uv_product0_l1n0_low0d0_r <= unused_uv_product0_l1n0_part0_r[34:0];
            uv_product0_l1n0_a1d0_r <= unused_uv_product0_l0n0_w[35 +: 16];
            uv_product0_l1n0_b1d0_r <= unused_uv_product0_l0n1_w[35 +: 16];
            unused_uv_product0_l1n0_part1_r <=
                {1'b0, uv_product0_l1n0_a1d0_r} + {1'b0, uv_product0_l1n0_b1d0_r} + {16'b0,
                unused_uv_product0_l1n0_part0_r[35]};
        end
    end

    // uv_product1: 16x35, 3 registered APM products; 5 enabled stages.
    wire [15:0] uv_product1_a_w;
    assign uv_product1_a_w = uv_input1_r_d9_r;
    wire [34:0] uv_product1_b_w;
    assign uv_product1_b_w = restored_r;
    reg [32:0] uv_product1_pp00_r;
    wire [50:0] unused_uv_product1_term00_w;
    assign unused_uv_product1_term00_w = {18'b0, uv_product1_pp00_r} << 0;
    reg [32:0] uv_product1_pp01_r;
    wire [50:0] unused_uv_product1_term01_w;
    assign unused_uv_product1_term01_w = {18'b0, uv_product1_pp01_r} << 17;
    reg [16:0] uv_product1_pp02_r;
    wire [50:0] unused_uv_product1_term02_w;
    assign unused_uv_product1_term02_w = {34'b0, uv_product1_pp02_r} << 34;
    reg [35:0] unused_uv_product1_l0n0_part0_r;
    reg [34:0] uv_product1_l0n0_low0d0_r;
    reg [15:0] uv_product1_l0n0_a1d0_r;
    reg [15:0] uv_product1_l0n0_b1d0_r;
    reg [16:0] unused_uv_product1_l0n0_part1_r;
    wire [50:0] unused_uv_product1_l0n0_w;
    assign unused_uv_product1_l0n0_w =
                {unused_uv_product1_l0n0_part1_r[15:0], uv_product1_l0n0_low0d0_r};
    reg [16:0] uv_product1_l0n1_d0_r;
    reg [16:0] uv_product1_l0n1_d1_r;
    wire [50:0] unused_uv_product1_l0n1_w;
    assign unused_uv_product1_l0n1_w = {uv_product1_l0n1_d1_r, 34'b0};
    reg [35:0] unused_uv_product1_l1n0_part0_r;
    reg [34:0] uv_product1_l1n0_low0d0_r;
    reg [15:0] uv_product1_l1n0_a1d0_r;
    reg [15:0] uv_product1_l1n0_b1d0_r;
    reg [16:0] unused_uv_product1_l1n0_part1_r;
    wire [50:0] unused_uv_product1_l1n0_w;
    assign unused_uv_product1_l1n0_w =
                {unused_uv_product1_l1n0_part1_r[15:0], uv_product1_l1n0_low0d0_r};
    assign uv_product1_p2_r = unused_uv_product1_l1n0_w;
    always @(posedge clk_i) begin
        if (pipeline_enable_w[2]) begin
            uv_product1_pp00_r <=
                $signed({1'b0, uv_product1_a_w[0 +: 16]}) * $signed({1'b0, uv_product1_b_w[0 +: 17]
                });
            uv_product1_pp01_r <=
                $signed({1'b0, uv_product1_a_w[0 +: 16]}) * $signed({1'b0,
                uv_product1_b_w[17 +: 17]});
            uv_product1_pp02_r <=
                $signed({1'b0, uv_product1_a_w[0 +: 16]}) * $signed({1'b0, uv_product1_b_w[34 +: 1]
                });
            unused_uv_product1_l0n0_part0_r <=
                {1'b0, unused_uv_product1_term00_w[0 +: 35]} + {1'b0,
                unused_uv_product1_term01_w[0 +: 35]};
            uv_product1_l0n0_low0d0_r <= unused_uv_product1_l0n0_part0_r[34:0];
            uv_product1_l0n0_a1d0_r <= unused_uv_product1_term00_w[35 +: 16];
            uv_product1_l0n0_b1d0_r <= unused_uv_product1_term01_w[35 +: 16];
            unused_uv_product1_l0n0_part1_r <=
                {1'b0, uv_product1_l0n0_a1d0_r} + {1'b0, uv_product1_l0n0_b1d0_r} + {16'b0,
                unused_uv_product1_l0n0_part0_r[35]};
            uv_product1_l0n1_d0_r <= unused_uv_product1_term02_w[34 +: 17];
            uv_product1_l0n1_d1_r <= uv_product1_l0n1_d0_r;
            unused_uv_product1_l1n0_part0_r <=
                {1'b0, unused_uv_product1_l0n0_w[0 +: 35]} + {1'b0,
                unused_uv_product1_l0n1_w[0 +: 35]};
            uv_product1_l1n0_low0d0_r <= unused_uv_product1_l1n0_part0_r[34:0];
            uv_product1_l1n0_a1d0_r <= unused_uv_product1_l0n0_w[35 +: 16];
            uv_product1_l1n0_b1d0_r <= unused_uv_product1_l0n1_w[35 +: 16];
            unused_uv_product1_l1n0_part1_r <=
                {1'b0, uv_product1_l1n0_a1d0_r} + {1'b0, uv_product1_l1n0_b1d0_r} + {16'b0,
                unused_uv_product1_l1n0_part0_r[35]};
        end
    end

    // viewport_product0: 94x16, 6 registered APM products; 9 enabled stages.
    wire [93:0] viewport_product0_a_w;
    assign viewport_product0_a_w = viewport_adjust0_w;
    reg [32:0] viewport_product0_pp00_r;
    wire [93:0] unused_viewport_product0_term00_w;
    assign unused_viewport_product0_term00_w = {61'b0, viewport_product0_pp00_r} << 0;
    reg [32:0] viewport_product0_pp10_r;
    wire [93:0] unused_viewport_product0_term10_w;
    assign unused_viewport_product0_term10_w = {61'b0, viewport_product0_pp10_r} << 17;
    reg [32:0] viewport_product0_pp20_r;
    wire [93:0] unused_viewport_product0_term20_w;
    assign unused_viewport_product0_term20_w = {61'b0, viewport_product0_pp20_r} << 34;
    reg [32:0] viewport_product0_pp30_r;
    wire [93:0] unused_viewport_product0_term30_w;
    assign unused_viewport_product0_term30_w = {61'b0, viewport_product0_pp30_r} << 51;
    reg [32:0] viewport_product0_pp40_r;
    wire [93:0] unused_viewport_product0_term40_w;
    assign unused_viewport_product0_term40_w = {61'b0, viewport_product0_pp40_r} << 68;
    reg [24:0] viewport_product0_pp50_r;
    wire [93:0] unused_viewport_product0_term50_w;
    assign unused_viewport_product0_term50_w =
                {{69{viewport_product0_pp50_r[24]}}, viewport_product0_pp50_r} << 85;
    reg [35:0] unused_viewport_product0_l0n0_part0_r;
    reg [34:0] viewport_product0_l0n0_low0d0_r;
    reg [15:0] viewport_product0_l0n0_a1d0_r;
    reg [15:0] viewport_product0_l0n0_b1d0_r;
    reg [16:0] unused_viewport_product0_l0n0_part1_r;
    wire [93:0] unused_viewport_product0_l0n0_w;
    assign unused_viewport_product0_l0n0_w =
                {43'b0, {unused_viewport_product0_l0n0_part1_r[15:0],
                viewport_product0_l0n0_low0d0_r}};
    reg [35:0] unused_viewport_product0_l0n1_part0_r;
    reg [34:0] viewport_product0_l0n1_low0d0_r;
    reg [15:0] viewport_product0_l0n1_a1d0_r;
    reg [15:0] viewport_product0_l0n1_b1d0_r;
    reg [16:0] unused_viewport_product0_l0n1_part1_r;
    wire [93:0] unused_viewport_product0_l0n1_w;
    assign unused_viewport_product0_l0n1_w =
                {9'b0, {unused_viewport_product0_l0n1_part1_r[15:0],
                viewport_product0_l0n1_low0d0_r}, 34'b0};
    reg [26:0] unused_viewport_product0_l0n2_part0_r;
    reg [25:0] viewport_product0_l0n2_hold0_r;
    wire [93:0] unused_viewport_product0_l0n2_w;
    assign unused_viewport_product0_l0n2_w = {viewport_product0_l0n2_hold0_r, 68'b0};
    reg [35:0] unused_viewport_product0_l1n0_part0_r;
    reg [34:0] viewport_product0_l1n0_low0d0_r;
    reg [34:0] viewport_product0_l1n0_low0d1_r;
    reg [34:0] viewport_product0_l1n0_a1d0_r;
    reg [34:0] viewport_product0_l1n0_b1d0_r;
    reg [35:0] unused_viewport_product0_l1n0_part1_r;
    reg [34:0] viewport_product0_l1n0_low1d0_r;
    reg [15:0] viewport_product0_l1n0_a2d0_r;
    reg [15:0] viewport_product0_l1n0_a2d1_r;
    reg [15:0] viewport_product0_l1n0_b2d0_r;
    reg [15:0] viewport_product0_l1n0_b2d1_r;
    reg [16:0] unused_viewport_product0_l1n0_part2_r;
    wire [93:0] unused_viewport_product0_l1n0_w;
    assign unused_viewport_product0_l1n0_w =
                {8'b0, {unused_viewport_product0_l1n0_part2_r[15:0],
                viewport_product0_l1n0_low1d0_r, viewport_product0_l1n0_low0d1_r}};
    reg [25:0] viewport_product0_l1n1_d0_r;
    reg [25:0] viewport_product0_l1n1_d1_r;
    reg [25:0] viewport_product0_l1n1_d2_r;
    wire [93:0] unused_viewport_product0_l1n1_w;
    assign unused_viewport_product0_l1n1_w = {viewport_product0_l1n1_d2_r, 68'b0};
    reg [35:0] unused_viewport_product0_l2n0_part0_r;
    reg [34:0] viewport_product0_l2n0_low0d0_r;
    reg [34:0] viewport_product0_l2n0_low0d1_r;
    reg [34:0] viewport_product0_l2n0_a1d0_r;
    reg [34:0] viewport_product0_l2n0_b1d0_r;
    reg [35:0] unused_viewport_product0_l2n0_part1_r;
    reg [34:0] viewport_product0_l2n0_low1d0_r;
    reg [23:0] viewport_product0_l2n0_a2d0_r;
    reg [23:0] viewport_product0_l2n0_a2d1_r;
    reg [23:0] viewport_product0_l2n0_b2d0_r;
    reg [23:0] viewport_product0_l2n0_b2d1_r;
    reg [24:0] unused_viewport_product0_l2n0_part2_r;
    wire [93:0] unused_viewport_product0_l2n0_w;
    assign unused_viewport_product0_l2n0_w =
                {unused_viewport_product0_l2n0_part2_r[23:0], viewport_product0_l2n0_low1d0_r,
                viewport_product0_l2n0_low0d1_r};
    assign viewport_product0_p2_r = unused_viewport_product0_l2n0_w;
    always @(posedge clk_i) begin
        if (pipeline_enable_w[3]) begin
            viewport_product0_pp00_r <=
                $signed({1'b0, viewport_product0_a_w[0 +: 17]}) * $signed({1'b0,
                viewport_product0_b_w[0 +: 16]});
            viewport_product0_pp10_r <=
                $signed({1'b0, viewport_product0_a_w[17 +: 17]}) * $signed({1'b0,
                viewport_product0_b_w[0 +: 16]});
            viewport_product0_pp20_r <=
                $signed({1'b0, viewport_product0_a_w[34 +: 17]}) * $signed({1'b0,
                viewport_product0_b_w[0 +: 16]});
            viewport_product0_pp30_r <=
                $signed({1'b0, viewport_product0_a_w[51 +: 17]}) * $signed({1'b0,
                viewport_product0_b_w[0 +: 16]});
            viewport_product0_pp40_r <=
                $signed({1'b0, viewport_product0_a_w[68 +: 17]}) * $signed({1'b0,
                viewport_product0_b_w[0 +: 16]});
            viewport_product0_pp50_r <=
                $signed(viewport_product0_a_w[85 +: 9]) * $signed({1'b0,
                viewport_product0_b_w[0 +: 16]});
            unused_viewport_product0_l0n0_part0_r <=
                {1'b0, unused_viewport_product0_term00_w[0 +: 35]} + {1'b0,
                unused_viewport_product0_term10_w[0 +: 35]};
            viewport_product0_l0n0_low0d0_r <= unused_viewport_product0_l0n0_part0_r[34:0];
            viewport_product0_l0n0_a1d0_r <= unused_viewport_product0_term00_w[35 +: 16];
            viewport_product0_l0n0_b1d0_r <= unused_viewport_product0_term10_w[35 +: 16];
            unused_viewport_product0_l0n0_part1_r <=
                {1'b0, viewport_product0_l0n0_a1d0_r} + {1'b0, viewport_product0_l0n0_b1d0_r} +
                {16'b0, unused_viewport_product0_l0n0_part0_r[35]};
            unused_viewport_product0_l0n1_part0_r <=
                {1'b0, unused_viewport_product0_term20_w[34 +: 35]} + {1'b0,
                unused_viewport_product0_term30_w[34 +: 35]};
            viewport_product0_l0n1_low0d0_r <= unused_viewport_product0_l0n1_part0_r[34:0];
            viewport_product0_l0n1_a1d0_r <= unused_viewport_product0_term20_w[69 +: 16];
            viewport_product0_l0n1_b1d0_r <= unused_viewport_product0_term30_w[69 +: 16];
            unused_viewport_product0_l0n1_part1_r <=
                {1'b0, viewport_product0_l0n1_a1d0_r} + {1'b0, viewport_product0_l0n1_b1d0_r} +
                {16'b0, unused_viewport_product0_l0n1_part0_r[35]};
            unused_viewport_product0_l0n2_part0_r <=
                {1'b0, unused_viewport_product0_term40_w[68 +: 26]} + {1'b0,
                unused_viewport_product0_term50_w[68 +: 26]};
            viewport_product0_l0n2_hold0_r <= {unused_viewport_product0_l0n2_part0_r[25:0]};
            unused_viewport_product0_l1n0_part0_r <=
                {1'b0, unused_viewport_product0_l0n0_w[0 +: 35]} + {1'b0,
                unused_viewport_product0_l0n1_w[0 +: 35]};
            viewport_product0_l1n0_low0d0_r <= unused_viewport_product0_l1n0_part0_r[34:0];
            viewport_product0_l1n0_low0d1_r <= viewport_product0_l1n0_low0d0_r;
            viewport_product0_l1n0_a1d0_r <= unused_viewport_product0_l0n0_w[35 +: 35];
            viewport_product0_l1n0_b1d0_r <= unused_viewport_product0_l0n1_w[35 +: 35];
            unused_viewport_product0_l1n0_part1_r <=
                {1'b0, viewport_product0_l1n0_a1d0_r} + {1'b0, viewport_product0_l1n0_b1d0_r} +
                {35'b0, unused_viewport_product0_l1n0_part0_r[35]};
            viewport_product0_l1n0_low1d0_r <= unused_viewport_product0_l1n0_part1_r[34:0];
            viewport_product0_l1n0_a2d0_r <= unused_viewport_product0_l0n0_w[70 +: 16];
            viewport_product0_l1n0_a2d1_r <= viewport_product0_l1n0_a2d0_r;
            viewport_product0_l1n0_b2d0_r <= unused_viewport_product0_l0n1_w[70 +: 16];
            viewport_product0_l1n0_b2d1_r <= viewport_product0_l1n0_b2d0_r;
            unused_viewport_product0_l1n0_part2_r <=
                {1'b0, viewport_product0_l1n0_a2d1_r} + {1'b0, viewport_product0_l1n0_b2d1_r} +
                {16'b0, unused_viewport_product0_l1n0_part1_r[35]};
            viewport_product0_l1n1_d0_r <= unused_viewport_product0_l0n2_w[68 +: 26];
            viewport_product0_l1n1_d1_r <= viewport_product0_l1n1_d0_r;
            viewport_product0_l1n1_d2_r <= viewport_product0_l1n1_d1_r;
            unused_viewport_product0_l2n0_part0_r <=
                {1'b0, unused_viewport_product0_l1n0_w[0 +: 35]} + {1'b0,
                unused_viewport_product0_l1n1_w[0 +: 35]};
            viewport_product0_l2n0_low0d0_r <= unused_viewport_product0_l2n0_part0_r[34:0];
            viewport_product0_l2n0_low0d1_r <= viewport_product0_l2n0_low0d0_r;
            viewport_product0_l2n0_a1d0_r <= unused_viewport_product0_l1n0_w[35 +: 35];
            viewport_product0_l2n0_b1d0_r <= unused_viewport_product0_l1n1_w[35 +: 35];
            unused_viewport_product0_l2n0_part1_r <=
                {1'b0, viewport_product0_l2n0_a1d0_r} + {1'b0, viewport_product0_l2n0_b1d0_r} +
                {35'b0, unused_viewport_product0_l2n0_part0_r[35]};
            viewport_product0_l2n0_low1d0_r <= unused_viewport_product0_l2n0_part1_r[34:0];
            viewport_product0_l2n0_a2d0_r <= unused_viewport_product0_l1n0_w[70 +: 24];
            viewport_product0_l2n0_a2d1_r <= viewport_product0_l2n0_a2d0_r;
            viewport_product0_l2n0_b2d0_r <= unused_viewport_product0_l1n1_w[70 +: 24];
            viewport_product0_l2n0_b2d1_r <= viewport_product0_l2n0_b2d0_r;
            unused_viewport_product0_l2n0_part2_r <=
                {1'b0, viewport_product0_l2n0_a2d1_r} + {1'b0, viewport_product0_l2n0_b2d1_r} +
                {24'b0, unused_viewport_product0_l2n0_part1_r[35]};
        end
    end

    // viewport_product1: 94x16, 6 registered APM products; 9 enabled stages.
    wire [93:0] viewport_product1_a_w;
    assign viewport_product1_a_w = viewport_adjust1_w;
    reg [32:0] viewport_product1_pp00_r;
    wire [93:0] unused_viewport_product1_term00_w;
    assign unused_viewport_product1_term00_w = {61'b0, viewport_product1_pp00_r} << 0;
    reg [32:0] viewport_product1_pp10_r;
    wire [93:0] unused_viewport_product1_term10_w;
    assign unused_viewport_product1_term10_w = {61'b0, viewport_product1_pp10_r} << 17;
    reg [32:0] viewport_product1_pp20_r;
    wire [93:0] unused_viewport_product1_term20_w;
    assign unused_viewport_product1_term20_w = {61'b0, viewport_product1_pp20_r} << 34;
    reg [32:0] viewport_product1_pp30_r;
    wire [93:0] unused_viewport_product1_term30_w;
    assign unused_viewport_product1_term30_w = {61'b0, viewport_product1_pp30_r} << 51;
    reg [32:0] viewport_product1_pp40_r;
    wire [93:0] unused_viewport_product1_term40_w;
    assign unused_viewport_product1_term40_w = {61'b0, viewport_product1_pp40_r} << 68;
    reg [24:0] viewport_product1_pp50_r;
    wire [93:0] unused_viewport_product1_term50_w;
    assign unused_viewport_product1_term50_w =
                {{69{viewport_product1_pp50_r[24]}}, viewport_product1_pp50_r} << 85;
    reg [35:0] unused_viewport_product1_l0n0_part0_r;
    reg [34:0] viewport_product1_l0n0_low0d0_r;
    reg [15:0] viewport_product1_l0n0_a1d0_r;
    reg [15:0] viewport_product1_l0n0_b1d0_r;
    reg [16:0] unused_viewport_product1_l0n0_part1_r;
    wire [93:0] unused_viewport_product1_l0n0_w;
    assign unused_viewport_product1_l0n0_w =
                {43'b0, {unused_viewport_product1_l0n0_part1_r[15:0],
                viewport_product1_l0n0_low0d0_r}};
    reg [35:0] unused_viewport_product1_l0n1_part0_r;
    reg [34:0] viewport_product1_l0n1_low0d0_r;
    reg [15:0] viewport_product1_l0n1_a1d0_r;
    reg [15:0] viewport_product1_l0n1_b1d0_r;
    reg [16:0] unused_viewport_product1_l0n1_part1_r;
    wire [93:0] unused_viewport_product1_l0n1_w;
    assign unused_viewport_product1_l0n1_w =
                {9'b0, {unused_viewport_product1_l0n1_part1_r[15:0],
                viewport_product1_l0n1_low0d0_r}, 34'b0};
    reg [26:0] unused_viewport_product1_l0n2_part0_r;
    reg [25:0] viewport_product1_l0n2_hold0_r;
    wire [93:0] unused_viewport_product1_l0n2_w;
    assign unused_viewport_product1_l0n2_w = {viewport_product1_l0n2_hold0_r, 68'b0};
    reg [35:0] unused_viewport_product1_l1n0_part0_r;
    reg [34:0] viewport_product1_l1n0_low0d0_r;
    reg [34:0] viewport_product1_l1n0_low0d1_r;
    reg [34:0] viewport_product1_l1n0_a1d0_r;
    reg [34:0] viewport_product1_l1n0_b1d0_r;
    reg [35:0] unused_viewport_product1_l1n0_part1_r;
    reg [34:0] viewport_product1_l1n0_low1d0_r;
    reg [15:0] viewport_product1_l1n0_a2d0_r;
    reg [15:0] viewport_product1_l1n0_a2d1_r;
    reg [15:0] viewport_product1_l1n0_b2d0_r;
    reg [15:0] viewport_product1_l1n0_b2d1_r;
    reg [16:0] unused_viewport_product1_l1n0_part2_r;
    wire [93:0] unused_viewport_product1_l1n0_w;
    assign unused_viewport_product1_l1n0_w =
                {8'b0, {unused_viewport_product1_l1n0_part2_r[15:0],
                viewport_product1_l1n0_low1d0_r, viewport_product1_l1n0_low0d1_r}};
    reg [25:0] viewport_product1_l1n1_d0_r;
    reg [25:0] viewport_product1_l1n1_d1_r;
    reg [25:0] viewport_product1_l1n1_d2_r;
    wire [93:0] unused_viewport_product1_l1n1_w;
    assign unused_viewport_product1_l1n1_w = {viewport_product1_l1n1_d2_r, 68'b0};
    reg [35:0] unused_viewport_product1_l2n0_part0_r;
    reg [34:0] viewport_product1_l2n0_low0d0_r;
    reg [34:0] viewport_product1_l2n0_low0d1_r;
    reg [34:0] viewport_product1_l2n0_a1d0_r;
    reg [34:0] viewport_product1_l2n0_b1d0_r;
    reg [35:0] unused_viewport_product1_l2n0_part1_r;
    reg [34:0] viewport_product1_l2n0_low1d0_r;
    reg [23:0] viewport_product1_l2n0_a2d0_r;
    reg [23:0] viewport_product1_l2n0_a2d1_r;
    reg [23:0] viewport_product1_l2n0_b2d0_r;
    reg [23:0] viewport_product1_l2n0_b2d1_r;
    reg [24:0] unused_viewport_product1_l2n0_part2_r;
    wire [93:0] unused_viewport_product1_l2n0_w;
    assign unused_viewport_product1_l2n0_w =
                {unused_viewport_product1_l2n0_part2_r[23:0], viewport_product1_l2n0_low1d0_r,
                viewport_product1_l2n0_low0d1_r};
    assign viewport_product1_p2_r = unused_viewport_product1_l2n0_w;
    always @(posedge clk_i) begin
        if (pipeline_enable_w[5]) begin
            viewport_product1_pp00_r <=
                $signed({1'b0, viewport_product1_a_w[0 +: 17]}) * $signed({1'b0,
                viewport_product1_b_w[0 +: 16]});
            viewport_product1_pp10_r <=
                $signed({1'b0, viewport_product1_a_w[17 +: 17]}) * $signed({1'b0,
                viewport_product1_b_w[0 +: 16]});
            viewport_product1_pp20_r <=
                $signed({1'b0, viewport_product1_a_w[34 +: 17]}) * $signed({1'b0,
                viewport_product1_b_w[0 +: 16]});
            viewport_product1_pp30_r <=
                $signed({1'b0, viewport_product1_a_w[51 +: 17]}) * $signed({1'b0,
                viewport_product1_b_w[0 +: 16]});
            viewport_product1_pp40_r <=
                $signed({1'b0, viewport_product1_a_w[68 +: 17]}) * $signed({1'b0,
                viewport_product1_b_w[0 +: 16]});
            viewport_product1_pp50_r <=
                $signed(viewport_product1_a_w[85 +: 9]) * $signed({1'b0,
                viewport_product1_b_w[0 +: 16]});
            unused_viewport_product1_l0n0_part0_r <=
                {1'b0, unused_viewport_product1_term00_w[0 +: 35]} + {1'b0,
                unused_viewport_product1_term10_w[0 +: 35]};
            viewport_product1_l0n0_low0d0_r <= unused_viewport_product1_l0n0_part0_r[34:0];
            viewport_product1_l0n0_a1d0_r <= unused_viewport_product1_term00_w[35 +: 16];
            viewport_product1_l0n0_b1d0_r <= unused_viewport_product1_term10_w[35 +: 16];
            unused_viewport_product1_l0n0_part1_r <=
                {1'b0, viewport_product1_l0n0_a1d0_r} + {1'b0, viewport_product1_l0n0_b1d0_r} +
                {16'b0, unused_viewport_product1_l0n0_part0_r[35]};
            unused_viewport_product1_l0n1_part0_r <=
                {1'b0, unused_viewport_product1_term20_w[34 +: 35]} + {1'b0,
                unused_viewport_product1_term30_w[34 +: 35]};
            viewport_product1_l0n1_low0d0_r <= unused_viewport_product1_l0n1_part0_r[34:0];
            viewport_product1_l0n1_a1d0_r <= unused_viewport_product1_term20_w[69 +: 16];
            viewport_product1_l0n1_b1d0_r <= unused_viewport_product1_term30_w[69 +: 16];
            unused_viewport_product1_l0n1_part1_r <=
                {1'b0, viewport_product1_l0n1_a1d0_r} + {1'b0, viewport_product1_l0n1_b1d0_r} +
                {16'b0, unused_viewport_product1_l0n1_part0_r[35]};
            unused_viewport_product1_l0n2_part0_r <=
                {1'b0, unused_viewport_product1_term40_w[68 +: 26]} + {1'b0,
                unused_viewport_product1_term50_w[68 +: 26]};
            viewport_product1_l0n2_hold0_r <= {unused_viewport_product1_l0n2_part0_r[25:0]};
            unused_viewport_product1_l1n0_part0_r <=
                {1'b0, unused_viewport_product1_l0n0_w[0 +: 35]} + {1'b0,
                unused_viewport_product1_l0n1_w[0 +: 35]};
            viewport_product1_l1n0_low0d0_r <= unused_viewport_product1_l1n0_part0_r[34:0];
            viewport_product1_l1n0_low0d1_r <= viewport_product1_l1n0_low0d0_r;
            viewport_product1_l1n0_a1d0_r <= unused_viewport_product1_l0n0_w[35 +: 35];
            viewport_product1_l1n0_b1d0_r <= unused_viewport_product1_l0n1_w[35 +: 35];
            unused_viewport_product1_l1n0_part1_r <=
                {1'b0, viewport_product1_l1n0_a1d0_r} + {1'b0, viewport_product1_l1n0_b1d0_r} +
                {35'b0, unused_viewport_product1_l1n0_part0_r[35]};
            viewport_product1_l1n0_low1d0_r <= unused_viewport_product1_l1n0_part1_r[34:0];
            viewport_product1_l1n0_a2d0_r <= unused_viewport_product1_l0n0_w[70 +: 16];
            viewport_product1_l1n0_a2d1_r <= viewport_product1_l1n0_a2d0_r;
            viewport_product1_l1n0_b2d0_r <= unused_viewport_product1_l0n1_w[70 +: 16];
            viewport_product1_l1n0_b2d1_r <= viewport_product1_l1n0_b2d0_r;
            unused_viewport_product1_l1n0_part2_r <=
                {1'b0, viewport_product1_l1n0_a2d1_r} + {1'b0, viewport_product1_l1n0_b2d1_r} +
                {16'b0, unused_viewport_product1_l1n0_part1_r[35]};
            viewport_product1_l1n1_d0_r <= unused_viewport_product1_l0n2_w[68 +: 26];
            viewport_product1_l1n1_d1_r <= viewport_product1_l1n1_d0_r;
            viewport_product1_l1n1_d2_r <= viewport_product1_l1n1_d1_r;
            unused_viewport_product1_l2n0_part0_r <=
                {1'b0, unused_viewport_product1_l1n0_w[0 +: 35]} + {1'b0,
                unused_viewport_product1_l1n1_w[0 +: 35]};
            viewport_product1_l2n0_low0d0_r <= unused_viewport_product1_l2n0_part0_r[34:0];
            viewport_product1_l2n0_low0d1_r <= viewport_product1_l2n0_low0d0_r;
            viewport_product1_l2n0_a1d0_r <= unused_viewport_product1_l1n0_w[35 +: 35];
            viewport_product1_l2n0_b1d0_r <= unused_viewport_product1_l1n1_w[35 +: 35];
            unused_viewport_product1_l2n0_part1_r <=
                {1'b0, viewport_product1_l2n0_a1d0_r} + {1'b0, viewport_product1_l2n0_b1d0_r} +
                {35'b0, unused_viewport_product1_l2n0_part0_r[35]};
            viewport_product1_l2n0_low1d0_r <= unused_viewport_product1_l2n0_part1_r[34:0];
            viewport_product1_l2n0_a2d0_r <= unused_viewport_product1_l1n0_w[70 +: 24];
            viewport_product1_l2n0_a2d1_r <= viewport_product1_l2n0_a2d0_r;
            viewport_product1_l2n0_b2d0_r <= unused_viewport_product1_l1n1_w[70 +: 24];
            viewport_product1_l2n0_b2d1_r <= viewport_product1_l2n0_b2d0_r;
            unused_viewport_product1_l2n0_part2_r <=
                {1'b0, viewport_product1_l2n0_a2d1_r} + {1'b0, viewport_product1_l2n0_b2d1_r} +
                {24'b0, unused_viewport_product1_l2n0_part1_r[35]};
        end
    end
    // Viewport snapshots stay in a tag-indexed LUTRAM until their consuming stage.
    wire [5:0] viewport_size0_tags_read_w;
    wire [255:0] unused_viewport_size0_tags_data_w;
    assign viewport_size0_tags_read_w = input_delay_write_r[5:0] - 6'd22;
    edrv32_ram_gpu_read_pool u_viewport_size0_tags (
        .clk_i(clk_i),
        .wr_en_i(control_enable_w[0]),
        .wr_addr_i(input_delay_write_r[5:0]),
        .wr_data_i({240'b0, viewport_size0_r}),
        .rd_en_i(control_enable_w[1]),
        .rd_addr_i(viewport_size0_tags_read_w),
        .rd_data_o(unused_viewport_size0_tags_data_w)
    );
    wire [15:0] viewport_size0_tags_d23_w;
    assign viewport_size0_tags_d23_w = unused_viewport_size0_tags_data_w[15:0];
    wire [15:0] viewport_product0_b_w;
    assign viewport_product0_b_w = viewport_size0_tags_d23_w[15:0];
    wire [5:0] viewport_size1_tags_read_w;
    wire [255:0] unused_viewport_size1_tags_data_w;
    assign viewport_size1_tags_read_w = input_delay_write_r[5:0] - 6'd26;
    edrv32_ram_gpu_read_pool u_viewport_size1_tags (
        .clk_i(clk_i),
        .wr_en_i(control_enable_w[2]),
        .wr_addr_i(input_delay_write_r[5:0]),
        .wr_data_i({240'b0, viewport_size1_r}),
        .rd_en_i(control_enable_w[0]),
        .rd_addr_i(viewport_size1_tags_read_w),
        .rd_data_o(unused_viewport_size1_tags_data_w)
    );
    wire [15:0] viewport_size1_tags_d27_w;
    assign viewport_size1_tags_d27_w = unused_viewport_size1_tags_data_w[15:0];
    wire [15:0] viewport_product1_b_w;
    assign viewport_product1_b_w = viewport_size1_tags_d27_w[15:0];
    wire [5:0] viewport_offset0_tags_read_w;
    wire [255:0] unused_viewport_offset0_tags_data_w;
    assign viewport_offset0_tags_read_w = input_delay_write_r[5:0] - 6'd41;
    edrv32_ram_gpu_read_pool u_viewport_offset0_tags (
        .clk_i(clk_i),
        .wr_en_i(control_enable_w[1]),
        .wr_addr_i(input_delay_write_r[5:0]),
        .wr_data_i({240'b0, viewport_offset0_r}),
        .rd_en_i(control_enable_w[2]),
        .rd_addr_i(viewport_offset0_tags_read_w),
        .rd_data_o(unused_viewport_offset0_tags_data_w)
    );
    reg [0:0] viewport_offset0_tags_d43_r;
    always @(posedge clk_i) begin
        if (control_enable_w[0])
            viewport_offset0_tags_d43_r <= unused_viewport_offset0_tags_data_w[15];
    end
    wire [15:0] viewport_offset0_tags_d42_w;
    assign viewport_offset0_tags_d42_w = unused_viewport_offset0_tags_data_w[15:0];
    wire [34:0] screen_offset0_b0_align14_r;
    assign screen_offset0_b0_align14_r =
                {{16{viewport_offset0_tags_d42_w[15]}}, viewport_offset0_tags_d42_w[14:0] , 4'b0};
    wire [13:0] screen_offset0_b1_w_d29_align14_r;
    assign screen_offset0_b1_w_d29_align14_r = {14{viewport_offset0_tags_d43_r[0]}};
    wire [5:0] viewport_offset1_tags_read_w;
    wire [255:0] unused_viewport_offset1_tags_data_w;
    assign viewport_offset1_tags_read_w = input_delay_write_r[5:0] - 6'd45;
    edrv32_ram_gpu_read_pool u_viewport_offset1_tags (
        .clk_i(clk_i),
        .wr_en_i(control_enable_w[1]),
        .wr_addr_i(input_delay_write_r[5:0]),
        .wr_data_i({240'b0, viewport_offset1_r}),
        .rd_en_i(control_enable_w[2]),
        .rd_addr_i(viewport_offset1_tags_read_w),
        .rd_data_o(unused_viewport_offset1_tags_data_w)
    );
    reg [0:0] viewport_offset1_tags_d47_r;
    always @(posedge clk_i) begin
        if (control_enable_w[0])
            viewport_offset1_tags_d47_r <= unused_viewport_offset1_tags_data_w[15];
    end
    wire [15:0] viewport_offset1_tags_d46_w;
    assign viewport_offset1_tags_d46_w = unused_viewport_offset1_tags_data_w[15:0];
    wire [34:0] screen_offset1_b0_align14_r;
    assign screen_offset1_b0_align14_r =
                {{16{viewport_offset1_tags_d46_w[15]}}, viewport_offset1_tags_d46_w[14:0] , 4'b0};
    wire [13:0] screen_offset1_b1_w_d33_align14_r;
    assign screen_offset1_b1_w_d33_align14_r = {14{viewport_offset1_tags_d47_r[0]}};
    // Circular enabled-cycle tags replace long payload and viewport delay chains.
    wire [5:0] payload_delay0_read_w;
    wire [71:0] unused_payload_delay0_data_w;
    assign payload_delay0_read_w = input_delay_write_r - 6'd48;
    wire [71:0] color_input_r_d35_align14_r;
    assign color_input_r_d35_align14_r = unused_payload_delay0_data_w[0 +: 72];
    wire [71:0] u_payload_delay0_data_w;
    reg [71:0] u_payload_delay0_data_r;
    assign unused_payload_delay0_data_w = u_payload_delay0_data_r;
    always @(posedge clk_i) begin
        if (control_enable_w[1]) u_payload_delay0_data_r <= u_payload_delay0_data_w;
    end
    edrv32_ram_gpu_table u_payload_delay0 (
        .clk_i(clk_i),
        .wr_en_i(control_enable_w[2]),
        .wr_addr_i(input_delay_write_r),
        .wr_data_i(color_input_w),
        .rd_addr_i(payload_delay0_read_w),
        .rd_data_o(u_payload_delay0_data_w)
    );
    wire [5:0] payload_delay1_read_w;
    wire [71:0] unused_payload_delay1_data_w;
    assign payload_delay1_read_w = input_delay_write_r - 6'd7;
    wire [39:0] position_input0_r_d9_r;
    assign position_input0_r_d9_r = unused_payload_delay1_data_w[0 +: 40];
    wire [15:0] uv_input0_r_d9_r;
    assign uv_input0_r_d9_r = unused_payload_delay1_data_w[40 +: 16];
    wire [15:0] uv_input1_r_d9_r;
    assign uv_input1_r_d9_r = unused_payload_delay1_data_w[56 +: 16];
    wire [71:0] u_payload_delay1_data_w;
    reg [71:0] u_payload_delay1_data_r;
    assign unused_payload_delay1_data_w = u_payload_delay1_data_r;
    always @(posedge clk_i) begin
        if (control_enable_w[0]) u_payload_delay1_data_r <= u_payload_delay1_data_w;
    end
    edrv32_ram_gpu_table u_payload_delay1 (
        .clk_i(clk_i),
        .wr_en_i(control_enable_w[1]),
        .wr_addr_i(input_delay_write_r),
        .wr_data_i({uv_input1_r, uv_input0_r, position_input0_r}),
        .rd_addr_i(payload_delay1_read_w),
        .rd_data_o(u_payload_delay1_data_w)
    );
    wire [5:0] payload_delay2_read_w;
    wire [71:0] unused_payload_delay2_data_w;
    assign payload_delay2_read_w = input_delay_write_r - 6'd7;
    wire [39:0] position_input1_r_d9_r;
    assign position_input1_r_d9_r = unused_payload_delay2_data_w[0 +: 40];
    wire [71:0] u_payload_delay2_data_w;
    reg [71:0] u_payload_delay2_data_r;
    assign unused_payload_delay2_data_w = u_payload_delay2_data_r;
    always @(posedge clk_i) begin
        if (control_enable_w[2]) u_payload_delay2_data_r <= u_payload_delay2_data_w;
    end
    edrv32_ram_gpu_table u_payload_delay2 (
        .clk_i(clk_i),
        .wr_en_i(control_enable_w[0]),
        .wr_addr_i(input_delay_write_r),
        .wr_data_i({32'b0, position_input1_r}),
        .rd_addr_i(payload_delay2_read_w),
        .rd_data_o(u_payload_delay2_data_w)
    );
    wire [5:0] payload_delay3_read_w;
    wire [71:0] unused_payload_delay3_data_w;
    assign payload_delay3_read_w = input_delay_write_r - 6'd7;
    wire [39:0] position_input2_r_d9_r;
    assign position_input2_r_d9_r = unused_payload_delay3_data_w[0 +: 40];
    wire [71:0] u_payload_delay3_data_w;
    reg [71:0] u_payload_delay3_data_r;
    assign unused_payload_delay3_data_w = u_payload_delay3_data_r;
    always @(posedge clk_i) begin
        if (control_enable_w[1]) u_payload_delay3_data_r <= u_payload_delay3_data_w;
    end
    edrv32_ram_gpu_table u_payload_delay3 (
        .clk_i(clk_i),
        .wr_en_i(control_enable_w[2]),
        .wr_addr_i(input_delay_write_r),
        .wr_data_i({32'b0, position_input2_r}),
        .rd_addr_i(payload_delay3_read_w),
        .rd_data_o(u_payload_delay3_data_w)
    );
    wire [5:0] payload_delay4_read_w;
    wire [255:0] unused_payload_delay4_data_w;
    assign payload_delay4_read_w = input_delay_write_r[5:0] - 6'd18;
    wire [15:0] depth_clamp_d35_align6_r;
    assign depth_clamp_d35_align6_r = unused_payload_delay4_data_w[0 +: 16];
    edrv32_ram_gpu_read_pool u_payload_delay4 (
        .clk_i(clk_i),
        .wr_en_i(control_enable_w[0]),
        .wr_addr_i(input_delay_write_r[5:0]),
        .wr_data_i({240'b0, depth_clamp_r}),
        .rd_en_i(control_enable_w[1]),
        .rd_addr_i(payload_delay4_read_w),
        .rd_data_o(unused_payload_delay4_data_w)
    );
    wire [5:0] payload_delay5_read_w;
    wire [255:0] unused_payload_delay5_data_w;
    assign payload_delay5_read_w = input_delay_write_r[5:0] - 6'd39;
    wire [34:0] restored_d35_align14_r;
    assign restored_d35_align14_r = unused_payload_delay5_data_w[0 +: 35];
    edrv32_ram_gpu_read_pool u_payload_delay5 (
        .clk_i(clk_i),
        .wr_en_i(control_enable_w[2]),
        .wr_addr_i(input_delay_write_r[5:0]),
        .wr_data_i({221'b0, restored_r}),
        .rd_en_i(control_enable_w[0]),
        .rd_addr_i(payload_delay5_read_w),
        .rd_data_o(unused_payload_delay5_data_w)
    );
    wire [5:0] payload_delay6_read_w;
    wire [255:0] unused_payload_delay6_data_w;
    assign payload_delay6_read_w = input_delay_write_r[5:0] - 6'd34;
    wire [50:0] uv_product0_p2_d35_align12_r;
    assign uv_product0_p2_d35_align12_r = unused_payload_delay6_data_w[0 +: 51];
    wire [50:0] uv_product1_p2_d35_align12_r;
    assign uv_product1_p2_d35_align12_r = unused_payload_delay6_data_w[51 +: 51];
    edrv32_ram_gpu_read_pool u_payload_delay6 (
        .clk_i(clk_i),
        .wr_en_i(control_enable_w[1]),
        .wr_addr_i(input_delay_write_r[5:0]),
        .wr_data_i({154'b0, uv_product1_p2_r, uv_product0_p2_r}),
        .rd_en_i(control_enable_w[2]),
        .rd_addr_i(payload_delay6_read_w),
        .rd_data_o(unused_payload_delay6_data_w)
    );
endmodule
