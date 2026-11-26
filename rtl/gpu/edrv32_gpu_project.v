// File: edrv32_gpu_project.v
// Spec: gpu-spec 2.4, 2.12; GPU microarchitecture 4.3.
// Description: Q30 perspective division with full coordinate and viewport products.
//              Only the final screen coordinate and depth conversions round and saturate.
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
    reg [5:0] restore_right;
    reg [5:0] restore_left;
    reg [5:0] restore_bit;
    reg [39:0] restore_bias;
    wire [39:0] reciprocal40_w;
    reg [39:0] reciprocal40_w_d1;
    reg [39:0] reciprocal40_w_d2;
    reg [39:0] reciprocal40_w_d3;
    wire [34:0] restore_round_a0_w;
    wire [34:0] restore_round_b0_w;
    reg [35:0] restore_round_part0;
    wire [34:0] restore_round_low0_w;
    wire [4:0] restore_round_a1_w;
    wire [4:0] restore_round_b1_w;
    reg [4:0] restore_round_a1_w_d4;
    reg [4:0] restore_round_b1_w_d4;
    reg [5:0] unused_restore_round_part1;
    wire [4:0] restore_round_low1_w;
    wire [39:0] restore_round_w;
    reg [34:0] restore_round_low0_w_d5;
    wire [1:0] restore_shift_right_amt0_w;
    reg [39:0] restore_shift_right_0_w;
    reg [1:0] restore_shift_right_amt0_w_d2;
    reg [1:0] restore_shift_right_amt0_w_d3;
    reg [1:0] restore_shift_right_amt0_w_d4;
    reg [1:0] restore_shift_right_amt0_w_d5;
    reg [39:0] restore_shift_right_0_r;
    wire [1:0] restore_shift_right_amt1_w;
    reg [39:0] restore_shift_right_1_w;
    reg [1:0] restore_shift_right_amt1_w_d2;
    reg [1:0] restore_shift_right_amt1_w_d3;
    reg [1:0] restore_shift_right_amt1_w_d4;
    reg [1:0] restore_shift_right_amt1_w_d5;
    reg [1:0] restore_shift_right_amt1_w_d6;
    reg [39:0] restore_shift_right_1_r;
    wire [1:0] restore_shift_right_amt2_w;
    reg [39:0] restore_shift_right_2_w;
    reg [1:0] restore_shift_right_amt2_w_d2;
    reg [1:0] restore_shift_right_amt2_w_d3;
    reg [1:0] restore_shift_right_amt2_w_d4;
    reg [1:0] restore_shift_right_amt2_w_d5;
    reg [1:0] restore_shift_right_amt2_w_d6;
    reg [1:0] restore_shift_right_amt2_w_d7;
    reg [39:0] unused_restore_shift_right_2_r;
    wire [1:0] restore_shift_left_amt0_w;
    reg [39:0] restore_shift_left_0_w;
    reg [39:0] restore_shift_left_0_r;
    wire [1:0] restore_shift_left_amt1_w;
    reg [39:0] restore_shift_left_1_w;
    reg [1:0] restore_shift_left_amt1_w_d2;
    reg [39:0] restore_shift_left_1_r;
    wire [1:0] restore_shift_left_amt2_w;
    reg [39:0] restore_shift_left_2_w;
    reg [1:0] restore_shift_left_amt2_w_d2;
    reg [1:0] restore_shift_left_amt2_w_d3;
    reg [39:0] restore_shift_left_2_r;
    reg [5:0] restore_exponent_r_d1;
    reg [5:0] restore_exponent_r_d2;
    reg [5:0] restore_exponent_r_d3;
    reg [5:0] restore_exponent_r_d4;
    reg [5:0] restore_exponent_r_d5;
    reg [5:0] restore_exponent_r_d6;
    reg [5:0] restore_exponent_r_d7;
    reg [5:0] restore_exponent_r_d8;
    reg [39:0] restore_shift_left_2_r_d5;
    reg [39:0] restore_shift_left_2_r_d6;
    reg [39:0] restore_shift_left_2_r_d7;
    reg [39:0] unused_restore_shift_left_2_r_d8;
    reg [34:0] restored;
    reg [39:0] position_input0_r;
    reg [39:0] position_input1_r;
    reg [39:0] position_input2_r;
    reg [15:0] uv_input0_r;
    reg [15:0] uv_input1_r;
    reg [71:0] color_input_r;
    reg [39:0] position_input0_r_d2;
    reg [39:0] position_input0_r_d3;
    reg [39:0] position_input0_r_d4;
    reg [39:0] position_input0_r_d5;
    reg [39:0] position_input0_r_d6;
    reg [39:0] position_input0_r_d7;
    reg [39:0] position_input0_r_d8;
    reg [39:0] position_input0_r_d9;
    reg [74:0] position_product0;
    reg [74:0] position_product0_p1;
    reg [74:0] position_product0_p2;
    reg [39:0] position_input1_r_d2;
    reg [39:0] position_input1_r_d3;
    reg [39:0] position_input1_r_d4;
    reg [39:0] position_input1_r_d5;
    reg [39:0] position_input1_r_d6;
    reg [39:0] position_input1_r_d7;
    reg [39:0] position_input1_r_d8;
    reg [39:0] position_input1_r_d9;
    reg [74:0] position_product1;
    reg [74:0] position_product1_p1;
    reg [74:0] position_product1_p2;
    reg [39:0] position_input2_r_d2;
    reg [39:0] position_input2_r_d3;
    reg [39:0] position_input2_r_d4;
    reg [39:0] position_input2_r_d5;
    reg [39:0] position_input2_r_d6;
    reg [39:0] position_input2_r_d7;
    reg [39:0] position_input2_r_d8;
    reg [39:0] position_input2_r_d9;
    reg [74:0] position_product2;
    reg [74:0] position_product2_p1;
    reg [74:0] position_product2_p2;
    reg [15:0] uv_input0_r_d2;
    reg [15:0] uv_input0_r_d3;
    reg [15:0] uv_input0_r_d4;
    reg [15:0] uv_input0_r_d5;
    reg [15:0] uv_input0_r_d6;
    reg [15:0] uv_input0_r_d7;
    reg [15:0] uv_input0_r_d8;
    reg [15:0] uv_input0_r_d9;
    reg [50:0] uv_product0;
    reg [50:0] uv_product0_p1;
    reg [50:0] uv_product0_p2;
    reg [15:0] uv_input1_r_d2;
    reg [15:0] uv_input1_r_d3;
    reg [15:0] uv_input1_r_d4;
    reg [15:0] uv_input1_r_d5;
    reg [15:0] uv_input1_r_d6;
    reg [15:0] uv_input1_r_d7;
    reg [15:0] uv_input1_r_d8;
    reg [15:0] uv_input1_r_d9;
    reg [50:0] uv_product1;
    reg [50:0] uv_product1_p1;
    reg [50:0] uv_product1_p2;
    wire [93:0] position_ext0_w;
    wire [93:0] viewport_one0_w;
    wire [34:0] viewport_adjust0_a0_w;
    wire [34:0] viewport_adjust0_b0_w;
    reg [35:0] viewport_adjust0_part0;
    wire [34:0] viewport_adjust0_low0_w;
    wire [34:0] viewport_adjust0_a1_w;
    wire [34:0] viewport_adjust0_b1_w;
    reg [34:0] viewport_adjust0_a1_w_d13;
    reg [34:0] viewport_adjust0_b1_w_d13;
    reg [35:0] viewport_adjust0_part1;
    wire [34:0] viewport_adjust0_low1_w;
    wire [23:0] viewport_adjust0_a2_w;
    wire [23:0] viewport_adjust0_b2_w;
    reg [23:0] viewport_adjust0_a2_w_d13;
    reg [23:0] viewport_adjust0_a2_w_d14;
    reg [23:0] viewport_adjust0_b2_w_d13;
    reg [23:0] viewport_adjust0_b2_w_d14;
    reg [24:0] unused_viewport_adjust0_part2;
    wire [23:0] viewport_adjust0_low2_w;
    wire [93:0] viewport_adjust0_w;
    reg [34:0] viewport_adjust0_low1_w_d15;
    reg [34:0] viewport_adjust0_low0_w_d14;
    reg [34:0] viewport_adjust0_low0_w_d15;
    reg [15:0] viewport_size0_r;
    reg [15:0] viewport_size0_r_d1;
    reg [15:0] viewport_size0_r_d2;
    reg [15:0] viewport_size0_r_d3;
    reg [15:0] viewport_size0_r_d4;
    reg [15:0] viewport_size0_r_d5;
    reg [15:0] viewport_size0_r_d6;
    reg [15:0] viewport_size0_r_d7;
    reg [15:0] viewport_size0_r_d8;
    reg [15:0] viewport_size0_r_d9;
    reg [15:0] viewport_size0_r_d10;
    reg [15:0] viewport_size0_r_d11;
    reg [15:0] viewport_size0_r_d12;
    reg [15:0] viewport_size0_r_d13;
    reg [15:0] viewport_size0_r_d14;
    reg [15:0] viewport_size0_r_d15;
    reg [93:0] viewport_product0;
    reg [93:0] viewport_product0_p1;
    reg [93:0] viewport_product0_p2;
    reg [93:0] viewport_shift0;
    wire [93:0] position_ext1_w;
    wire [93:0] viewport_one1_w;
    reg [93:0] position_negative;
    wire [93:0] position_negate_one_w;
    wire [34:0] position_negate_a0_w;
    wire [34:0] position_negate_b0_w;
    reg [35:0] position_negate_part0;
    wire [34:0] position_negate_low0_w;
    wire [34:0] position_negate_a1_w;
    wire [34:0] position_negate_b1_w;
    reg [34:0] position_negate_a1_w_d14;
    reg [34:0] position_negate_b1_w_d14;
    reg [35:0] position_negate_part1;
    wire [34:0] position_negate_low1_w;
    wire [23:0] position_negate_a2_w;
    wire [23:0] position_negate_b2_w;
    reg [23:0] position_negate_a2_w_d14;
    reg [23:0] position_negate_a2_w_d15;
    reg [23:0] position_negate_b2_w_d14;
    reg [23:0] position_negate_b2_w_d15;
    reg [24:0] unused_position_negate_part2;
    wire [23:0] position_negate_low2_w;
    wire [93:0] position_negate_w;
    reg [34:0] position_negate_low1_w_d16;
    reg [34:0] position_negate_low0_w_d15;
    reg [34:0] position_negate_low0_w_d16;
    reg [93:0] viewport_one1_w_d13;
    reg [93:0] viewport_one1_w_d14;
    reg [93:0] viewport_one1_w_d15;
    reg [93:0] viewport_one1_w_d16;
    wire [34:0] viewport_adjust1_a0_w;
    wire [34:0] viewport_adjust1_b0_w;
    reg [35:0] viewport_adjust1_part0;
    wire [34:0] viewport_adjust1_low0_w;
    wire [34:0] viewport_adjust1_a1_w;
    wire [34:0] viewport_adjust1_b1_w;
    reg [34:0] viewport_adjust1_a1_w_d17;
    reg [34:0] viewport_adjust1_b1_w_d17;
    reg [35:0] viewport_adjust1_part1;
    wire [34:0] viewport_adjust1_low1_w;
    wire [23:0] viewport_adjust1_a2_w;
    wire [23:0] viewport_adjust1_b2_w;
    reg [23:0] viewport_adjust1_a2_w_d17;
    reg [23:0] viewport_adjust1_a2_w_d18;
    reg [23:0] viewport_adjust1_b2_w_d17;
    reg [23:0] viewport_adjust1_b2_w_d18;
    reg [24:0] unused_viewport_adjust1_part2;
    wire [23:0] viewport_adjust1_low2_w;
    wire [93:0] viewport_adjust1_w;
    reg [34:0] viewport_adjust1_low1_w_d19;
    reg [34:0] viewport_adjust1_low0_w_d18;
    reg [34:0] viewport_adjust1_low0_w_d19;
    reg [15:0] viewport_size1_r;
    reg [15:0] viewport_size1_r_d1;
    reg [15:0] viewport_size1_r_d2;
    reg [15:0] viewport_size1_r_d3;
    reg [15:0] viewport_size1_r_d4;
    reg [15:0] viewport_size1_r_d5;
    reg [15:0] viewport_size1_r_d6;
    reg [15:0] viewport_size1_r_d7;
    reg [15:0] viewport_size1_r_d8;
    reg [15:0] viewport_size1_r_d9;
    reg [15:0] viewport_size1_r_d10;
    reg [15:0] viewport_size1_r_d11;
    reg [15:0] viewport_size1_r_d12;
    reg [15:0] viewport_size1_r_d13;
    reg [15:0] viewport_size1_r_d14;
    reg [15:0] viewport_size1_r_d15;
    reg [15:0] viewport_size1_r_d16;
    reg [15:0] viewport_size1_r_d17;
    reg [15:0] viewport_size1_r_d18;
    reg [15:0] viewport_size1_r_d19;
    reg [93:0] viewport_product1;
    reg [93:0] viewport_product1_p1;
    reg [93:0] viewport_product1_p2;
    reg [93:0] viewport_shift1;
    wire [93:0] position_ext2_w;
    wire [93:0] depth_left_w;
    reg [93:0] depth_invert;
    wire [93:0] depth_one_w;
    wire [34:0] depth_negate_a0_w;
    wire [34:0] depth_negate_b0_w;
    reg [35:0] depth_negate_part0;
    wire [34:0] depth_negate_low0_w;
    wire [34:0] depth_negate_a1_w;
    wire [34:0] depth_negate_b1_w;
    reg [34:0] depth_negate_a1_w_d14;
    reg [34:0] depth_negate_b1_w_d14;
    reg [35:0] depth_negate_part1;
    wire [34:0] depth_negate_low1_w;
    wire [23:0] depth_negate_a2_w;
    wire [23:0] depth_negate_b2_w;
    reg [23:0] depth_negate_a2_w_d14;
    reg [23:0] depth_negate_a2_w_d15;
    reg [23:0] depth_negate_b2_w_d14;
    reg [23:0] depth_negate_b2_w_d15;
    reg [24:0] unused_depth_negate_part2;
    wire [23:0] depth_negate_low2_w;
    wire [93:0] depth_negate_w;
    reg [34:0] depth_negate_low1_w_d16;
    reg [34:0] depth_negate_low0_w_d15;
    reg [34:0] depth_negate_low0_w_d16;
    reg [93:0] depth_left_w_d13;
    reg [93:0] depth_left_w_d14;
    reg [93:0] depth_left_w_d15;
    reg [93:0] depth_left_w_d16;
    wire [34:0] depth_subtract_a0_w;
    wire [34:0] depth_subtract_b0_w;
    reg [35:0] depth_subtract_part0;
    wire [34:0] depth_subtract_low0_w;
    wire [34:0] depth_subtract_a1_w;
    wire [34:0] depth_subtract_b1_w;
    reg [34:0] depth_subtract_a1_w_d17;
    reg [34:0] depth_subtract_b1_w_d17;
    reg [35:0] depth_subtract_part1;
    wire [34:0] depth_subtract_low1_w;
    wire [23:0] depth_subtract_a2_w;
    wire [23:0] depth_subtract_b2_w;
    reg [23:0] depth_subtract_a2_w_d17;
    reg [23:0] depth_subtract_a2_w_d18;
    reg [23:0] depth_subtract_b2_w_d17;
    reg [23:0] depth_subtract_b2_w_d18;
    reg [24:0] unused_depth_subtract_part2;
    wire [23:0] depth_subtract_low2_w;
    wire [93:0] depth_subtract_w;
    reg [34:0] depth_subtract_low1_w_d19;
    reg [34:0] depth_subtract_low0_w_d18;
    reg [34:0] depth_subtract_low0_w_d19;
    reg [0:0] screen_abs0_sign;
    reg [93:0] screen_abs0_invert;
    wire [93:0] screen_abs0_carry_w;
    wire [34:0] screen_abs0_a0_w;
    wire [34:0] screen_abs0_b0_w;
    reg [35:0] screen_abs0_part0;
    wire [34:0] screen_abs0_low0_w;
    wire [34:0] screen_abs0_a1_w;
    wire [34:0] screen_abs0_b1_w;
    reg [34:0] screen_abs0_a1_w_d21;
    reg [34:0] screen_abs0_b1_w_d21;
    reg [35:0] screen_abs0_part1;
    wire [34:0] screen_abs0_low1_w;
    wire [23:0] screen_abs0_a2_w;
    wire [23:0] screen_abs0_b2_w;
    reg [23:0] screen_abs0_a2_w_d21;
    reg [23:0] screen_abs0_a2_w_d22;
    reg [23:0] screen_abs0_b2_w_d21;
    reg [23:0] screen_abs0_b2_w_d22;
    reg [24:0] unused_screen_abs0_part2;
    wire [23:0] screen_abs0_low2_w;
    wire [93:0] unused_screen_abs0_w;
    reg [34:0] screen_abs0_low1_w_d23;
    reg [34:0] screen_abs0_low0_w_d22;
    reg [34:0] screen_abs0_low0_w_d23;
    wire [48:0] screen_high0_w;
    wire [48:0] screen_bit0_w;
    wire [34:0] screen_round0_a0_w;
    wire [34:0] screen_round0_b0_w;
    reg [35:0] screen_round0_part0;
    wire [34:0] screen_round0_low0_w;
    wire [13:0] screen_round0_a1_w;
    wire [13:0] screen_round0_b1_w;
    reg [13:0] screen_round0_a1_w_d24;
    reg [13:0] screen_round0_b1_w_d24;
    reg [14:0] unused_screen_round0_part1;
    wire [13:0] screen_round0_low1_w;
    wire [48:0] screen_round0_w;
    reg [34:0] screen_round0_low0_w_d25;
    reg [0:0] screen_abs0_sign_d21;
    reg [0:0] screen_abs0_sign_d22;
    reg [0:0] screen_abs0_sign_d23;
    reg [0:0] screen_abs0_sign_d24;
    reg [0:0] screen_abs0_sign_d25;
    reg [48:0] screen_signed0_invert;
    reg [0:0] screen_abs0_sign_d26;
    wire [48:0] screen_signed0_carry_w;
    wire [34:0] screen_signed0_a0_w;
    wire [34:0] screen_signed0_b0_w;
    reg [35:0] screen_signed0_part0;
    wire [34:0] screen_signed0_low0_w;
    wire [13:0] screen_signed0_a1_w;
    wire [13:0] screen_signed0_b1_w;
    reg [13:0] screen_signed0_a1_w_d27;
    reg [13:0] screen_signed0_b1_w_d27;
    reg [14:0] unused_screen_signed0_part1;
    wire [13:0] screen_signed0_low1_w;
    wire [48:0] screen_signed0_w;
    reg [34:0] screen_signed0_low0_w_d28;
    reg [15:0] viewport_offset0_r;
    wire [48:0] viewport_offset_ext0_w;
    reg [48:0] viewport_offset_ext0_w_d1;
    reg [48:0] viewport_offset_ext0_w_d2;
    reg [48:0] viewport_offset_ext0_w_d3;
    reg [48:0] viewport_offset_ext0_w_d4;
    reg [48:0] viewport_offset_ext0_w_d5;
    reg [48:0] viewport_offset_ext0_w_d6;
    reg [48:0] viewport_offset_ext0_w_d7;
    reg [48:0] viewport_offset_ext0_w_d8;
    reg [48:0] viewport_offset_ext0_w_d9;
    reg [48:0] viewport_offset_ext0_w_d10;
    reg [48:0] viewport_offset_ext0_w_d11;
    reg [48:0] viewport_offset_ext0_w_d12;
    reg [48:0] viewport_offset_ext0_w_d13;
    reg [48:0] viewport_offset_ext0_w_d14;
    reg [48:0] viewport_offset_ext0_w_d15;
    reg [48:0] viewport_offset_ext0_w_d16;
    reg [48:0] viewport_offset_ext0_w_d17;
    reg [48:0] viewport_offset_ext0_w_d18;
    reg [48:0] viewport_offset_ext0_w_d19;
    reg [48:0] viewport_offset_ext0_w_d20;
    reg [48:0] viewport_offset_ext0_w_d21;
    reg [48:0] viewport_offset_ext0_w_d22;
    reg [48:0] viewport_offset_ext0_w_d23;
    reg [48:0] viewport_offset_ext0_w_d24;
    reg [48:0] viewport_offset_ext0_w_d25;
    reg [48:0] viewport_offset_ext0_w_d26;
    reg [48:0] viewport_offset_ext0_w_d27;
    reg [48:0] viewport_offset_ext0_w_d28;
    wire [34:0] screen_offset0_a0_w;
    wire [34:0] screen_offset0_b0_w;
    reg [35:0] screen_offset0_part0;
    wire [34:0] screen_offset0_low0_w;
    wire [13:0] screen_offset0_a1_w;
    wire [13:0] screen_offset0_b1_w;
    reg [13:0] screen_offset0_a1_w_d29;
    reg [13:0] screen_offset0_b1_w_d29;
    reg [14:0] unused_screen_offset0_part1;
    wire [13:0] screen_offset0_low1_w;
    wire [48:0] screen_offset0_w;
    reg [34:0] screen_offset0_low0_w_d30;
    reg [16:0] screen_clamp0;
    reg [0:0] screen_abs1_sign;
    reg [93:0] screen_abs1_invert;
    wire [93:0] screen_abs1_carry_w;
    wire [34:0] screen_abs1_a0_w;
    wire [34:0] screen_abs1_b0_w;
    reg [35:0] screen_abs1_part0;
    wire [34:0] screen_abs1_low0_w;
    wire [34:0] screen_abs1_a1_w;
    wire [34:0] screen_abs1_b1_w;
    reg [34:0] screen_abs1_a1_w_d25;
    reg [34:0] screen_abs1_b1_w_d25;
    reg [35:0] screen_abs1_part1;
    wire [34:0] screen_abs1_low1_w;
    wire [23:0] screen_abs1_a2_w;
    wire [23:0] screen_abs1_b2_w;
    reg [23:0] screen_abs1_a2_w_d25;
    reg [23:0] screen_abs1_a2_w_d26;
    reg [23:0] screen_abs1_b2_w_d25;
    reg [23:0] screen_abs1_b2_w_d26;
    reg [24:0] unused_screen_abs1_part2;
    wire [23:0] screen_abs1_low2_w;
    wire [93:0] unused_screen_abs1_w;
    reg [34:0] screen_abs1_low1_w_d27;
    reg [34:0] screen_abs1_low0_w_d26;
    reg [34:0] screen_abs1_low0_w_d27;
    wire [48:0] screen_high1_w;
    wire [48:0] screen_bit1_w;
    wire [34:0] screen_round1_a0_w;
    wire [34:0] screen_round1_b0_w;
    reg [35:0] screen_round1_part0;
    wire [34:0] screen_round1_low0_w;
    wire [13:0] screen_round1_a1_w;
    wire [13:0] screen_round1_b1_w;
    reg [13:0] screen_round1_a1_w_d28;
    reg [13:0] screen_round1_b1_w_d28;
    reg [14:0] unused_screen_round1_part1;
    wire [13:0] screen_round1_low1_w;
    wire [48:0] screen_round1_w;
    reg [34:0] screen_round1_low0_w_d29;
    reg [0:0] screen_abs1_sign_d25;
    reg [0:0] screen_abs1_sign_d26;
    reg [0:0] screen_abs1_sign_d27;
    reg [0:0] screen_abs1_sign_d28;
    reg [0:0] screen_abs1_sign_d29;
    reg [48:0] screen_signed1_invert;
    reg [0:0] screen_abs1_sign_d30;
    wire [48:0] screen_signed1_carry_w;
    wire [34:0] screen_signed1_a0_w;
    wire [34:0] screen_signed1_b0_w;
    reg [35:0] screen_signed1_part0;
    wire [34:0] screen_signed1_low0_w;
    wire [13:0] screen_signed1_a1_w;
    wire [13:0] screen_signed1_b1_w;
    reg [13:0] screen_signed1_a1_w_d31;
    reg [13:0] screen_signed1_b1_w_d31;
    reg [14:0] unused_screen_signed1_part1;
    wire [13:0] screen_signed1_low1_w;
    wire [48:0] screen_signed1_w;
    reg [34:0] screen_signed1_low0_w_d32;
    reg [15:0] viewport_offset1_r;
    wire [48:0] viewport_offset_ext1_w;
    reg [48:0] viewport_offset_ext1_w_d1;
    reg [48:0] viewport_offset_ext1_w_d2;
    reg [48:0] viewport_offset_ext1_w_d3;
    reg [48:0] viewport_offset_ext1_w_d4;
    reg [48:0] viewport_offset_ext1_w_d5;
    reg [48:0] viewport_offset_ext1_w_d6;
    reg [48:0] viewport_offset_ext1_w_d7;
    reg [48:0] viewport_offset_ext1_w_d8;
    reg [48:0] viewport_offset_ext1_w_d9;
    reg [48:0] viewport_offset_ext1_w_d10;
    reg [48:0] viewport_offset_ext1_w_d11;
    reg [48:0] viewport_offset_ext1_w_d12;
    reg [48:0] viewport_offset_ext1_w_d13;
    reg [48:0] viewport_offset_ext1_w_d14;
    reg [48:0] viewport_offset_ext1_w_d15;
    reg [48:0] viewport_offset_ext1_w_d16;
    reg [48:0] viewport_offset_ext1_w_d17;
    reg [48:0] viewport_offset_ext1_w_d18;
    reg [48:0] viewport_offset_ext1_w_d19;
    reg [48:0] viewport_offset_ext1_w_d20;
    reg [48:0] viewport_offset_ext1_w_d21;
    reg [48:0] viewport_offset_ext1_w_d22;
    reg [48:0] viewport_offset_ext1_w_d23;
    reg [48:0] viewport_offset_ext1_w_d24;
    reg [48:0] viewport_offset_ext1_w_d25;
    reg [48:0] viewport_offset_ext1_w_d26;
    reg [48:0] viewport_offset_ext1_w_d27;
    reg [48:0] viewport_offset_ext1_w_d28;
    reg [48:0] viewport_offset_ext1_w_d29;
    reg [48:0] viewport_offset_ext1_w_d30;
    reg [48:0] viewport_offset_ext1_w_d31;
    reg [48:0] viewport_offset_ext1_w_d32;
    wire [34:0] screen_offset1_a0_w;
    wire [34:0] screen_offset1_b0_w;
    reg [35:0] screen_offset1_part0;
    wire [34:0] screen_offset1_low0_w;
    wire [13:0] screen_offset1_a1_w;
    wire [13:0] screen_offset1_b1_w;
    reg [13:0] screen_offset1_a1_w_d33;
    reg [13:0] screen_offset1_b1_w_d33;
    reg [14:0] unused_screen_offset1_part1;
    wire [13:0] screen_offset1_low1_w;
    wire [48:0] screen_offset1_w;
    reg [34:0] screen_offset1_low0_w_d34;
    reg [16:0] screen_clamp1;
    wire [48:0] depth_high_w;
    wire [48:0] depth_bit_w;
    wire [34:0] depth_round_a0_w;
    wire [34:0] depth_round_b0_w;
    reg [35:0] depth_round_part0;
    wire [34:0] depth_round_low0_w;
    wire [13:0] depth_round_a1_w;
    wire [13:0] depth_round_b1_w;
    reg [13:0] depth_round_a1_w_d20;
    reg [13:0] depth_round_b1_w_d20;
    reg [14:0] unused_depth_round_part1;
    wire [13:0] depth_round_low1_w;
    wire [48:0] depth_round_w;
    reg [34:0] depth_round_low0_w_d21;
    reg [93:0] depth_subtract_w_d20;
    reg [93:0] unused_depth_subtract_w_d21;
    reg [15:0] depth_clamp;
    reg [16:0] screen_clamp0_d32;
    reg [16:0] screen_clamp0_d33;
    reg [16:0] screen_clamp0_d34;
    reg [16:0] screen_clamp0_d35;
    reg [16:0] output_0_r [0:1];
    reg [16:0] output_1_r [0:1];
    reg [15:0] depth_clamp_d23;
    reg [15:0] depth_clamp_d24;
    reg [15:0] depth_clamp_d25;
    reg [15:0] depth_clamp_d26;
    reg [15:0] depth_clamp_d27;
    reg [15:0] depth_clamp_d28;
    reg [15:0] depth_clamp_d29;
    reg [15:0] depth_clamp_d30;
    reg [15:0] depth_clamp_d31;
    reg [15:0] depth_clamp_d32;
    reg [15:0] depth_clamp_d33;
    reg [15:0] depth_clamp_d34;
    reg [15:0] depth_clamp_d35;
    reg [15:0] output_2_r [0:1];
    reg [34:0] restored_d10;
    reg [34:0] restored_d11;
    reg [34:0] restored_d12;
    reg [34:0] restored_d13;
    reg [34:0] restored_d14;
    reg [34:0] restored_d15;
    reg [34:0] restored_d16;
    reg [34:0] restored_d17;
    reg [34:0] restored_d18;
    reg [34:0] restored_d19;
    reg [34:0] restored_d20;
    reg [34:0] restored_d21;
    reg [34:0] restored_d22;
    reg [34:0] restored_d23;
    reg [34:0] restored_d24;
    reg [34:0] restored_d25;
    reg [34:0] restored_d26;
    reg [34:0] restored_d27;
    reg [34:0] restored_d28;
    reg [34:0] restored_d29;
    reg [34:0] restored_d30;
    reg [34:0] restored_d31;
    reg [34:0] restored_d32;
    reg [34:0] restored_d33;
    reg [34:0] restored_d34;
    reg [34:0] restored_d35;
    reg [34:0] output_3_r [0:1];
    reg [50:0] uv_product0_p2_d13;
    reg [50:0] uv_product0_p2_d14;
    reg [50:0] uv_product0_p2_d15;
    reg [50:0] uv_product0_p2_d16;
    reg [50:0] uv_product0_p2_d17;
    reg [50:0] uv_product0_p2_d18;
    reg [50:0] uv_product0_p2_d19;
    reg [50:0] uv_product0_p2_d20;
    reg [50:0] uv_product0_p2_d21;
    reg [50:0] uv_product0_p2_d22;
    reg [50:0] uv_product0_p2_d23;
    reg [50:0] uv_product0_p2_d24;
    reg [50:0] uv_product0_p2_d25;
    reg [50:0] uv_product0_p2_d26;
    reg [50:0] uv_product0_p2_d27;
    reg [50:0] uv_product0_p2_d28;
    reg [50:0] uv_product0_p2_d29;
    reg [50:0] uv_product0_p2_d30;
    reg [50:0] uv_product0_p2_d31;
    reg [50:0] uv_product0_p2_d32;
    reg [50:0] uv_product0_p2_d33;
    reg [50:0] uv_product0_p2_d34;
    reg [50:0] uv_product0_p2_d35;
    reg [50:0] output_4_r [0:1];
    reg [50:0] uv_product1_p2_d13;
    reg [50:0] uv_product1_p2_d14;
    reg [50:0] uv_product1_p2_d15;
    reg [50:0] uv_product1_p2_d16;
    reg [50:0] uv_product1_p2_d17;
    reg [50:0] uv_product1_p2_d18;
    reg [50:0] uv_product1_p2_d19;
    reg [50:0] uv_product1_p2_d20;
    reg [50:0] uv_product1_p2_d21;
    reg [50:0] uv_product1_p2_d22;
    reg [50:0] uv_product1_p2_d23;
    reg [50:0] uv_product1_p2_d24;
    reg [50:0] uv_product1_p2_d25;
    reg [50:0] uv_product1_p2_d26;
    reg [50:0] uv_product1_p2_d27;
    reg [50:0] uv_product1_p2_d28;
    reg [50:0] uv_product1_p2_d29;
    reg [50:0] uv_product1_p2_d30;
    reg [50:0] uv_product1_p2_d31;
    reg [50:0] uv_product1_p2_d32;
    reg [50:0] uv_product1_p2_d33;
    reg [50:0] uv_product1_p2_d34;
    reg [50:0] uv_product1_p2_d35;
    reg [50:0] output_5_r [0:1];
    reg [71:0] color_input_r_d2;
    reg [71:0] color_input_r_d3;
    reg [71:0] color_input_r_d4;
    reg [71:0] color_input_r_d5;
    reg [71:0] color_input_r_d6;
    reg [71:0] color_input_r_d7;
    reg [71:0] color_input_r_d8;
    reg [71:0] color_input_r_d9;
    reg [71:0] color_input_r_d10;
    reg [71:0] color_input_r_d11;
    reg [71:0] color_input_r_d12;
    reg [71:0] color_input_r_d13;
    reg [71:0] color_input_r_d14;
    reg [71:0] color_input_r_d15;
    reg [71:0] color_input_r_d16;
    reg [71:0] color_input_r_d17;
    reg [71:0] color_input_r_d18;
    reg [71:0] color_input_r_d19;
    reg [71:0] color_input_r_d20;
    reg [71:0] color_input_r_d21;
    reg [71:0] color_input_r_d22;
    reg [71:0] color_input_r_d23;
    reg [71:0] color_input_r_d24;
    reg [71:0] color_input_r_d25;
    reg [71:0] color_input_r_d26;
    reg [71:0] color_input_r_d27;
    reg [71:0] color_input_r_d28;
    reg [71:0] color_input_r_d29;
    reg [71:0] color_input_r_d30;
    reg [71:0] color_input_r_d31;
    reg [71:0] color_input_r_d32;
    reg [71:0] color_input_r_d33;
    reg [71:0] color_input_r_d34;
    reg [71:0] color_input_r_d35;
    reg [71:0] output_6_r [0:1];
    reg [35:0] valid_r;
    reg [19:0] input_valid_r;
    reg [1:0] count_r;
    reg read_r;
    reg write_r;
    wire enable_w;
    wire accept_w;
    wire push_w;
    wire pop_w;
    wire reciprocal_valid_w;
    wire [30:0] reciprocal_w;
    wire [5:0] exponent_w;
    reg [8:0] input_delay_write_r;
    wire [8:0] input_delay_read_w;
    wire [223:0] input_prefix_w;
    wire [287:0] unused_input_delay_w;
    wire [39:0] position_input_w [0:2];
    wire [15:0] uv_input_w [0:1];
    wire [71:0] color_input_w;
    assign enable_w = count_r != 2 && !stop_i;
    assign clipped_ready_o = enable_w;
    assign accept_w = clipped_valid_i && clipped_ready_o;
    assign projected_valid_o = count_r != 0;
    assign push_w = enable_w && valid_r[35];
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
            if (enable_w) begin
                valid_r <= {valid_r[34:0], reciprocal_valid_w};
                input_valid_r <= {input_valid_r[18:0], accept_w};
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
        .enable_i(enable_w),
        .stop_i(stop_i),
        .value_valid_i(accept_w),
        .value_i(clipped_data_i[159:120]),
        .value_valid_o(reciprocal_valid_w),
        .reciprocal_o(reciprocal_w),
        .exponent_o(exponent_w)
    );

    // Payload latency is 1+10; the reciprocal exponent uses the same ten RAM cycles.
    assign input_delay_read_w = input_delay_write_r - 9'd19;
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) input_delay_write_r <= 0;
        else if (enable_w) input_delay_write_r <= input_delay_write_r + 1'b1;
    end
    edrv32_ram_gpu_delay u_input_delay_0 (
        .clk_i(clk_i),
        .wr_en_i(enable_w),
        .wr_addr_i(input_delay_write_r),
        .wr_data_i(input_prefix_w[0 +: 72]),
        .rd_en_i(enable_w),
        .rd_addr_i(input_delay_read_w),
        .rd_data_o(unused_input_delay_w[0 +: 72])
    );
    edrv32_ram_gpu_delay u_input_delay_1 (
        .clk_i(clk_i),
        .wr_en_i(enable_w),
        .wr_addr_i(input_delay_write_r),
        .wr_data_i(input_prefix_w[72 +: 72]),
        .rd_en_i(enable_w),
        .rd_addr_i(input_delay_read_w),
        .rd_data_o(unused_input_delay_w[72 +: 72])
    );
    edrv32_ram_gpu_delay u_input_delay_2 (
        .clk_i(clk_i),
        .wr_en_i(enable_w),
        .wr_addr_i(input_delay_write_r),
        .wr_data_i(input_prefix_w[144 +: 72]),
        .rd_en_i(enable_w),
        .rd_addr_i(input_delay_read_w),
        .rd_data_o(unused_input_delay_w[144 +: 72])
    );
    edrv32_ram_gpu_delay u_input_delay_3 (
        .clk_i(clk_i),
        .wr_en_i(enable_w),
        .wr_addr_i(input_delay_write_r),
        .wr_data_i({64'b0, input_prefix_w[223:216]}),
        .rd_en_i(enable_w),
        .rd_addr_i(input_delay_read_w),
        .rd_data_o(unused_input_delay_w[216 +: 72])
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
                if (enable_w) prefix_r <= clipped_data_i[INPUT_OFFSET +: WIDTH];
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
    assign restore_round_a0_w = reciprocal40_w_d3[0 +: 35];
    assign restore_round_b0_w = restore_bias[0 +: 35];
    assign restore_round_low0_w = restore_round_part0[34:0];
    assign restore_round_a1_w = reciprocal40_w_d3[35 +: 5];
    assign restore_round_b1_w = restore_bias[35 +: 5];
    assign restore_round_low1_w = unused_restore_round_part1[4:0];
    assign restore_round_w = {restore_round_low1_w, restore_round_low0_w_d5};
    assign restore_shift_right_amt0_w = restore_right[0 +: 2];
    always @(*) begin
        restore_shift_right_0_w = restore_round_w;
        case (restore_shift_right_amt0_w_d5)
            2'd0: restore_shift_right_0_w = restore_round_w >> 0;
            2'd1: restore_shift_right_0_w = restore_round_w >> 1;
            2'd2: restore_shift_right_0_w = restore_round_w >> 2;
            2'd3: restore_shift_right_0_w = restore_round_w >> 3;
            default: restore_shift_right_0_w = restore_round_w;
        endcase
    end
    assign restore_shift_right_amt1_w = restore_right[2 +: 2];
    always @(*) begin
        restore_shift_right_1_w = restore_shift_right_0_r;
        case (restore_shift_right_amt1_w_d6)
            2'd0: restore_shift_right_1_w = restore_shift_right_0_r >> 0;
            2'd1: restore_shift_right_1_w = restore_shift_right_0_r >> 4;
            2'd2: restore_shift_right_1_w = restore_shift_right_0_r >> 8;
            2'd3: restore_shift_right_1_w = restore_shift_right_0_r >> 12;
            default: restore_shift_right_1_w = restore_shift_right_0_r;
        endcase
    end
    assign restore_shift_right_amt2_w = restore_right[4 +: 2];
    always @(*) begin
        restore_shift_right_2_w = restore_shift_right_1_r;
        case (restore_shift_right_amt2_w_d7)
            2'd0: restore_shift_right_2_w = restore_shift_right_1_r >> 0;
            2'd1: restore_shift_right_2_w = restore_shift_right_1_r >> 16;
            2'd2: restore_shift_right_2_w = restore_shift_right_1_r >> 32;
            2'd3: restore_shift_right_2_w = restore_shift_right_1_r >> 48;
            default: restore_shift_right_2_w = restore_shift_right_1_r;
        endcase
    end
    assign restore_shift_left_amt0_w = restore_left[0 +: 2];
    always @(*) begin
        restore_shift_left_0_w = reciprocal40_w_d1;
        case (restore_shift_left_amt0_w)
            2'd0: restore_shift_left_0_w = reciprocal40_w_d1 << 0;
            2'd1: restore_shift_left_0_w = reciprocal40_w_d1 << 1;
            2'd2: restore_shift_left_0_w = reciprocal40_w_d1 << 2;
            2'd3: restore_shift_left_0_w = reciprocal40_w_d1 << 3;
            default: restore_shift_left_0_w = reciprocal40_w_d1;
        endcase
    end
    assign restore_shift_left_amt1_w = restore_left[2 +: 2];
    always @(*) begin
        restore_shift_left_1_w = restore_shift_left_0_r;
        case (restore_shift_left_amt1_w_d2)
            2'd0: restore_shift_left_1_w = restore_shift_left_0_r << 0;
            2'd1: restore_shift_left_1_w = restore_shift_left_0_r << 4;
            2'd2: restore_shift_left_1_w = restore_shift_left_0_r << 8;
            2'd3: restore_shift_left_1_w = restore_shift_left_0_r << 12;
            default: restore_shift_left_1_w = restore_shift_left_0_r;
        endcase
    end
    assign restore_shift_left_amt2_w = restore_left[4 +: 2];
    always @(*) begin
        restore_shift_left_2_w = restore_shift_left_1_r;
        case (restore_shift_left_amt2_w_d3)
            2'd0: restore_shift_left_2_w = restore_shift_left_1_r << 0;
            2'd1: restore_shift_left_2_w = restore_shift_left_1_r << 16;
            2'd2: restore_shift_left_2_w = restore_shift_left_1_r << 32;
            2'd3: restore_shift_left_2_w = restore_shift_left_1_r << 48;
            default: restore_shift_left_2_w = restore_shift_left_1_r;
        endcase
    end
    assign position_ext0_w = {{19{position_product0_p2[74]}}, position_product0_p2};
    assign viewport_one0_w = 94'd70368744177664;
    assign viewport_adjust0_a0_w = position_ext0_w[0 +: 35];
    assign viewport_adjust0_b0_w = viewport_one0_w[0 +: 35];
    assign viewport_adjust0_low0_w = viewport_adjust0_part0[34:0];
    assign viewport_adjust0_a1_w = position_ext0_w[35 +: 35];
    assign viewport_adjust0_b1_w = viewport_one0_w[35 +: 35];
    assign viewport_adjust0_low1_w = viewport_adjust0_part1[34:0];
    assign viewport_adjust0_a2_w = position_ext0_w[70 +: 24];
    assign viewport_adjust0_b2_w = viewport_one0_w[70 +: 24];
    assign viewport_adjust0_low2_w = unused_viewport_adjust0_part2[23:0];
    assign viewport_adjust0_w = {viewport_adjust0_low2_w, viewport_adjust0_low1_w_d15,
            viewport_adjust0_low0_w_d15};
    assign position_ext1_w = {{19{position_product1_p2[74]}}, position_product1_p2};
    assign viewport_one1_w = 94'd70368744177664;
    assign position_negate_one_w = 94'd1;
    assign position_negate_a0_w = position_negative[0 +: 35];
    assign position_negate_b0_w = position_negate_one_w[0 +: 35];
    assign position_negate_low0_w = position_negate_part0[34:0];
    assign position_negate_a1_w = position_negative[35 +: 35];
    assign position_negate_b1_w = position_negate_one_w[35 +: 35];
    assign position_negate_low1_w = position_negate_part1[34:0];
    assign position_negate_a2_w = position_negative[70 +: 24];
    assign position_negate_b2_w = position_negate_one_w[70 +: 24];
    assign position_negate_low2_w = unused_position_negate_part2[23:0];
    assign position_negate_w = {position_negate_low2_w, position_negate_low1_w_d16,
            position_negate_low0_w_d16};
    assign viewport_adjust1_a0_w = viewport_one1_w_d16[0 +: 35];
    assign viewport_adjust1_b0_w = position_negate_w[0 +: 35];
    assign viewport_adjust1_low0_w = viewport_adjust1_part0[34:0];
    assign viewport_adjust1_a1_w = viewport_one1_w_d16[35 +: 35];
    assign viewport_adjust1_b1_w = position_negate_w[35 +: 35];
    assign viewport_adjust1_low1_w = viewport_adjust1_part1[34:0];
    assign viewport_adjust1_a2_w = viewport_one1_w_d16[70 +: 24];
    assign viewport_adjust1_b2_w = position_negate_w[70 +: 24];
    assign viewport_adjust1_low2_w = unused_viewport_adjust1_part2[23:0];
    assign viewport_adjust1_w = {viewport_adjust1_low2_w, viewport_adjust1_low1_w_d19,
            viewport_adjust1_low0_w_d19};
    assign position_ext2_w = {{19{position_product2_p2[74]}}, position_product2_p2};
    assign depth_left_w = position_ext2_w << 16;
    assign depth_one_w = 94'd1;
    assign depth_negate_a0_w = depth_invert[0 +: 35];
    assign depth_negate_b0_w = depth_one_w[0 +: 35];
    assign depth_negate_low0_w = depth_negate_part0[34:0];
    assign depth_negate_a1_w = depth_invert[35 +: 35];
    assign depth_negate_b1_w = depth_one_w[35 +: 35];
    assign depth_negate_low1_w = depth_negate_part1[34:0];
    assign depth_negate_a2_w = depth_invert[70 +: 24];
    assign depth_negate_b2_w = depth_one_w[70 +: 24];
    assign depth_negate_low2_w = unused_depth_negate_part2[23:0];
    assign depth_negate_w = {depth_negate_low2_w, depth_negate_low1_w_d16, depth_negate_low0_w_d16};
    assign depth_subtract_a0_w = depth_left_w_d16[0 +: 35];
    assign depth_subtract_b0_w = depth_negate_w[0 +: 35];
    assign depth_subtract_low0_w = depth_subtract_part0[34:0];
    assign depth_subtract_a1_w = depth_left_w_d16[35 +: 35];
    assign depth_subtract_b1_w = depth_negate_w[35 +: 35];
    assign depth_subtract_low1_w = depth_subtract_part1[34:0];
    assign depth_subtract_a2_w = depth_left_w_d16[70 +: 24];
    assign depth_subtract_b2_w = depth_negate_w[70 +: 24];
    assign depth_subtract_low2_w = unused_depth_subtract_part2[23:0];
    assign depth_subtract_w = {depth_subtract_low2_w, depth_subtract_low1_w_d19,
            depth_subtract_low0_w_d19};
    assign screen_abs0_carry_w = {93'b0, screen_abs0_sign};
    assign screen_abs0_a0_w = screen_abs0_invert[0 +: 35];
    assign screen_abs0_b0_w = screen_abs0_carry_w[0 +: 35];
    assign screen_abs0_low0_w = screen_abs0_part0[34:0];
    assign screen_abs0_a1_w = screen_abs0_invert[35 +: 35];
    assign screen_abs0_b1_w = screen_abs0_carry_w[35 +: 35];
    assign screen_abs0_low1_w = screen_abs0_part1[34:0];
    assign screen_abs0_a2_w = screen_abs0_invert[70 +: 24];
    assign screen_abs0_b2_w = screen_abs0_carry_w[70 +: 24];
    assign screen_abs0_low2_w = unused_screen_abs0_part2[23:0];
    assign unused_screen_abs0_w = {screen_abs0_low2_w, screen_abs0_low1_w_d23,
            screen_abs0_low0_w_d23};
    assign screen_high0_w = {1'b0, unused_screen_abs0_w[93:46]};
    assign screen_bit0_w = {48'b0, unused_screen_abs0_w[45]};
    assign screen_round0_a0_w = screen_high0_w[0 +: 35];
    assign screen_round0_b0_w = screen_bit0_w[0 +: 35];
    assign screen_round0_low0_w = screen_round0_part0[34:0];
    assign screen_round0_a1_w = screen_high0_w[35 +: 14];
    assign screen_round0_b1_w = screen_bit0_w[35 +: 14];
    assign screen_round0_low1_w = unused_screen_round0_part1[13:0];
    assign screen_round0_w = {screen_round0_low1_w, screen_round0_low0_w_d25};
    assign screen_signed0_carry_w = {48'b0, screen_abs0_sign_d26};
    assign screen_signed0_a0_w = screen_signed0_invert[0 +: 35];
    assign screen_signed0_b0_w = screen_signed0_carry_w[0 +: 35];
    assign screen_signed0_low0_w = screen_signed0_part0[34:0];
    assign screen_signed0_a1_w = screen_signed0_invert[35 +: 14];
    assign screen_signed0_b1_w = screen_signed0_carry_w[35 +: 14];
    assign screen_signed0_low1_w = unused_screen_signed0_part1[13:0];
    assign screen_signed0_w = {screen_signed0_low1_w, screen_signed0_low0_w_d28};
    assign viewport_offset_ext0_w = {{29{viewport_offset0_r[15]}}, viewport_offset0_r, 4'b0};
    assign screen_offset0_a0_w = screen_signed0_w[0 +: 35];
    assign screen_offset0_b0_w = viewport_offset_ext0_w_d28[0 +: 35];
    assign screen_offset0_low0_w = screen_offset0_part0[34:0];
    assign screen_offset0_a1_w = screen_signed0_w[35 +: 14];
    assign screen_offset0_b1_w = viewport_offset_ext0_w_d28[35 +: 14];
    assign screen_offset0_low1_w = unused_screen_offset0_part1[13:0];
    assign screen_offset0_w = {screen_offset0_low1_w, screen_offset0_low0_w_d30};
    assign screen_abs1_carry_w = {93'b0, screen_abs1_sign};
    assign screen_abs1_a0_w = screen_abs1_invert[0 +: 35];
    assign screen_abs1_b0_w = screen_abs1_carry_w[0 +: 35];
    assign screen_abs1_low0_w = screen_abs1_part0[34:0];
    assign screen_abs1_a1_w = screen_abs1_invert[35 +: 35];
    assign screen_abs1_b1_w = screen_abs1_carry_w[35 +: 35];
    assign screen_abs1_low1_w = screen_abs1_part1[34:0];
    assign screen_abs1_a2_w = screen_abs1_invert[70 +: 24];
    assign screen_abs1_b2_w = screen_abs1_carry_w[70 +: 24];
    assign screen_abs1_low2_w = unused_screen_abs1_part2[23:0];
    assign unused_screen_abs1_w = {screen_abs1_low2_w, screen_abs1_low1_w_d27,
            screen_abs1_low0_w_d27};
    assign screen_high1_w = {1'b0, unused_screen_abs1_w[93:46]};
    assign screen_bit1_w = {48'b0, unused_screen_abs1_w[45]};
    assign screen_round1_a0_w = screen_high1_w[0 +: 35];
    assign screen_round1_b0_w = screen_bit1_w[0 +: 35];
    assign screen_round1_low0_w = screen_round1_part0[34:0];
    assign screen_round1_a1_w = screen_high1_w[35 +: 14];
    assign screen_round1_b1_w = screen_bit1_w[35 +: 14];
    assign screen_round1_low1_w = unused_screen_round1_part1[13:0];
    assign screen_round1_w = {screen_round1_low1_w, screen_round1_low0_w_d29};
    assign screen_signed1_carry_w = {48'b0, screen_abs1_sign_d30};
    assign screen_signed1_a0_w = screen_signed1_invert[0 +: 35];
    assign screen_signed1_b0_w = screen_signed1_carry_w[0 +: 35];
    assign screen_signed1_low0_w = screen_signed1_part0[34:0];
    assign screen_signed1_a1_w = screen_signed1_invert[35 +: 14];
    assign screen_signed1_b1_w = screen_signed1_carry_w[35 +: 14];
    assign screen_signed1_low1_w = unused_screen_signed1_part1[13:0];
    assign screen_signed1_w = {screen_signed1_low1_w, screen_signed1_low0_w_d32};
    assign viewport_offset_ext1_w = {{29{viewport_offset1_r[15]}}, viewport_offset1_r, 4'b0};
    assign screen_offset1_a0_w = screen_signed1_w[0 +: 35];
    assign screen_offset1_b0_w = viewport_offset_ext1_w_d32[0 +: 35];
    assign screen_offset1_low0_w = screen_offset1_part0[34:0];
    assign screen_offset1_a1_w = screen_signed1_w[35 +: 14];
    assign screen_offset1_b1_w = viewport_offset_ext1_w_d32[35 +: 14];
    assign screen_offset1_low1_w = unused_screen_offset1_part1[13:0];
    assign screen_offset1_w = {screen_offset1_low1_w, screen_offset1_low0_w_d34};
    assign depth_high_w = {1'b0, depth_subtract_w[93:46]};
    assign depth_bit_w = {48'b0, depth_subtract_w[45]};
    assign depth_round_a0_w = depth_high_w[0 +: 35];
    assign depth_round_b0_w = depth_bit_w[0 +: 35];
    assign depth_round_low0_w = depth_round_part0[34:0];
    assign depth_round_a1_w = depth_high_w[35 +: 14];
    assign depth_round_b1_w = depth_bit_w[35 +: 14];
    assign depth_round_low1_w = unused_depth_round_part1[13:0];
    assign depth_round_w = {depth_round_low1_w, depth_round_low0_w_d21};
    assign projected_data_o[0 +: 17] = output_0_r[read_r];
    always @(posedge clk_i) begin
        if (push_w) output_0_r[write_r] <= screen_clamp0_d35;
    end
    assign projected_data_o[17 +: 17] = output_1_r[read_r];
    always @(posedge clk_i) begin
        if (push_w) output_1_r[write_r] <= screen_clamp1;
    end
    assign projected_data_o[34 +: 16] = output_2_r[read_r];
    always @(posedge clk_i) begin
        if (push_w) output_2_r[write_r] <= depth_clamp_d35;
    end
    assign projected_data_o[50 +: 35] = output_3_r[read_r];
    always @(posedge clk_i) begin
        if (push_w) output_3_r[write_r] <= restored_d35;
    end
    assign projected_data_o[85 +: 51] = output_4_r[read_r];
    always @(posedge clk_i) begin
        if (push_w) output_4_r[write_r] <= uv_product0_p2_d35;
    end
    assign projected_data_o[136 +: 51] = output_5_r[read_r];
    always @(posedge clk_i) begin
        if (push_w) output_5_r[write_r] <= uv_product1_p2_d35;
    end
    assign projected_data_o[187 +: 72] = output_6_r[read_r];
    always @(posedge clk_i) begin
        if (push_w) output_6_r[write_r] <= color_input_r_d35;
    end
    always @(posedge clk_i) begin
        if (enable_w) begin
            reciprocal_input_r <= reciprocal_w;
            restore_exponent_r <= exponent_w;
            restore_right <= restore_exponent_r > 6'd16 ? restore_exponent_r - 6'd16 : 6'b0;
            restore_left <= restore_exponent_r < 6'd16 ? 6'd16 - restore_exponent_r : 6'b0;
            restore_bit <= restore_right - 6'd1;
            restore_bias <= 40'd1 << restore_bit;
            reciprocal40_w_d1 <= reciprocal40_w;
            reciprocal40_w_d2 <= reciprocal40_w_d1;
            reciprocal40_w_d3 <= reciprocal40_w_d2;
            restore_round_part0 <= {1'b0, restore_round_a0_w} + {1'b0, restore_round_b0_w};
            restore_round_a1_w_d4 <= restore_round_a1_w;
            restore_round_b1_w_d4 <= restore_round_b1_w;
            unused_restore_round_part1 <= {1'b0, restore_round_a1_w_d4} + {1'b0,
            restore_round_b1_w_d4} + {5'b0, restore_round_part0[35]};
            restore_round_low0_w_d5 <= restore_round_low0_w;
            restore_shift_right_amt0_w_d2 <= restore_shift_right_amt0_w;
            restore_shift_right_amt0_w_d3 <= restore_shift_right_amt0_w_d2;
            restore_shift_right_amt0_w_d4 <= restore_shift_right_amt0_w_d3;
            restore_shift_right_amt0_w_d5 <= restore_shift_right_amt0_w_d4;
            restore_shift_right_0_r <= restore_shift_right_0_w;
            restore_shift_right_amt1_w_d2 <= restore_shift_right_amt1_w;
            restore_shift_right_amt1_w_d3 <= restore_shift_right_amt1_w_d2;
            restore_shift_right_amt1_w_d4 <= restore_shift_right_amt1_w_d3;
            restore_shift_right_amt1_w_d5 <= restore_shift_right_amt1_w_d4;
            restore_shift_right_amt1_w_d6 <= restore_shift_right_amt1_w_d5;
            restore_shift_right_1_r <= restore_shift_right_1_w;
            restore_shift_right_amt2_w_d2 <= restore_shift_right_amt2_w;
            restore_shift_right_amt2_w_d3 <= restore_shift_right_amt2_w_d2;
            restore_shift_right_amt2_w_d4 <= restore_shift_right_amt2_w_d3;
            restore_shift_right_amt2_w_d5 <= restore_shift_right_amt2_w_d4;
            restore_shift_right_amt2_w_d6 <= restore_shift_right_amt2_w_d5;
            restore_shift_right_amt2_w_d7 <= restore_shift_right_amt2_w_d6;
            unused_restore_shift_right_2_r <= restore_shift_right_2_w;
            restore_shift_left_0_r <= restore_shift_left_0_w;
            restore_shift_left_amt1_w_d2 <= restore_shift_left_amt1_w;
            restore_shift_left_1_r <= restore_shift_left_1_w;
            restore_shift_left_amt2_w_d2 <= restore_shift_left_amt2_w;
            restore_shift_left_amt2_w_d3 <= restore_shift_left_amt2_w_d2;
            restore_shift_left_2_r <= restore_shift_left_2_w;
            restore_exponent_r_d1 <= restore_exponent_r;
            restore_exponent_r_d2 <= restore_exponent_r_d1;
            restore_exponent_r_d3 <= restore_exponent_r_d2;
            restore_exponent_r_d4 <= restore_exponent_r_d3;
            restore_exponent_r_d5 <= restore_exponent_r_d4;
            restore_exponent_r_d6 <= restore_exponent_r_d5;
            restore_exponent_r_d7 <= restore_exponent_r_d6;
            restore_exponent_r_d8 <= restore_exponent_r_d7;
            restore_shift_left_2_r_d5 <= restore_shift_left_2_r;
            restore_shift_left_2_r_d6 <= restore_shift_left_2_r_d5;
            restore_shift_left_2_r_d7 <= restore_shift_left_2_r_d6;
            unused_restore_shift_left_2_r_d8 <= restore_shift_left_2_r_d7;
            restored <= restore_exponent_r_d8 > 6'd16 ? unused_restore_shift_right_2_r[34:0] :
            unused_restore_shift_left_2_r_d8[34:0];
            position_input0_r <= position_input_w[0];
            position_input1_r <= position_input_w[1];
            position_input2_r <= position_input_w[2];
            uv_input0_r <= uv_input_w[0];
            uv_input1_r <= uv_input_w[1];
            color_input_r <= color_input_w;
            position_input0_r_d2 <= position_input0_r;
            position_input0_r_d3 <= position_input0_r_d2;
            position_input0_r_d4 <= position_input0_r_d3;
            position_input0_r_d5 <= position_input0_r_d4;
            position_input0_r_d6 <= position_input0_r_d5;
            position_input0_r_d7 <= position_input0_r_d6;
            position_input0_r_d8 <= position_input0_r_d7;
            position_input0_r_d9 <= position_input0_r_d8;
            position_product0 <= $signed(position_input0_r_d9) * $signed({1'b0, restored});
            position_product0_p1 <= position_product0;
            position_product0_p2 <= position_product0_p1;
            position_input1_r_d2 <= position_input1_r;
            position_input1_r_d3 <= position_input1_r_d2;
            position_input1_r_d4 <= position_input1_r_d3;
            position_input1_r_d5 <= position_input1_r_d4;
            position_input1_r_d6 <= position_input1_r_d5;
            position_input1_r_d7 <= position_input1_r_d6;
            position_input1_r_d8 <= position_input1_r_d7;
            position_input1_r_d9 <= position_input1_r_d8;
            position_product1 <= $signed(position_input1_r_d9) * $signed({1'b0, restored});
            position_product1_p1 <= position_product1;
            position_product1_p2 <= position_product1_p1;
            position_input2_r_d2 <= position_input2_r;
            position_input2_r_d3 <= position_input2_r_d2;
            position_input2_r_d4 <= position_input2_r_d3;
            position_input2_r_d5 <= position_input2_r_d4;
            position_input2_r_d6 <= position_input2_r_d5;
            position_input2_r_d7 <= position_input2_r_d6;
            position_input2_r_d8 <= position_input2_r_d7;
            position_input2_r_d9 <= position_input2_r_d8;
            position_product2 <= $signed(position_input2_r_d9) * $signed({1'b0, restored});
            position_product2_p1 <= position_product2;
            position_product2_p2 <= position_product2_p1;
            uv_input0_r_d2 <= uv_input0_r;
            uv_input0_r_d3 <= uv_input0_r_d2;
            uv_input0_r_d4 <= uv_input0_r_d3;
            uv_input0_r_d5 <= uv_input0_r_d4;
            uv_input0_r_d6 <= uv_input0_r_d5;
            uv_input0_r_d7 <= uv_input0_r_d6;
            uv_input0_r_d8 <= uv_input0_r_d7;
            uv_input0_r_d9 <= uv_input0_r_d8;
            uv_product0 <= uv_input0_r_d9 * restored;
            uv_product0_p1 <= uv_product0;
            uv_product0_p2 <= uv_product0_p1;
            uv_input1_r_d2 <= uv_input1_r;
            uv_input1_r_d3 <= uv_input1_r_d2;
            uv_input1_r_d4 <= uv_input1_r_d3;
            uv_input1_r_d5 <= uv_input1_r_d4;
            uv_input1_r_d6 <= uv_input1_r_d5;
            uv_input1_r_d7 <= uv_input1_r_d6;
            uv_input1_r_d8 <= uv_input1_r_d7;
            uv_input1_r_d9 <= uv_input1_r_d8;
            uv_product1 <= uv_input1_r_d9 * restored;
            uv_product1_p1 <= uv_product1;
            uv_product1_p2 <= uv_product1_p1;
            viewport_adjust0_part0 <= {1'b0, viewport_adjust0_a0_w} + {1'b0, viewport_adjust0_b0_w};
            viewport_adjust0_a1_w_d13 <= viewport_adjust0_a1_w;
            viewport_adjust0_b1_w_d13 <= viewport_adjust0_b1_w;
            viewport_adjust0_part1 <= {1'b0, viewport_adjust0_a1_w_d13} + {1'b0,
            viewport_adjust0_b1_w_d13} + {35'b0, viewport_adjust0_part0[35]};
            viewport_adjust0_a2_w_d13 <= viewport_adjust0_a2_w;
            viewport_adjust0_a2_w_d14 <= viewport_adjust0_a2_w_d13;
            viewport_adjust0_b2_w_d13 <= viewport_adjust0_b2_w;
            viewport_adjust0_b2_w_d14 <= viewport_adjust0_b2_w_d13;
            unused_viewport_adjust0_part2 <= {1'b0, viewport_adjust0_a2_w_d14} + {1'b0,
            viewport_adjust0_b2_w_d14} + {24'b0, viewport_adjust0_part1[35]};
            viewport_adjust0_low1_w_d15 <= viewport_adjust0_low1_w;
            viewport_adjust0_low0_w_d14 <= viewport_adjust0_low0_w;
            viewport_adjust0_low0_w_d15 <= viewport_adjust0_low0_w_d14;
            viewport_size0_r <= viewport_i[32 +: 16];
            viewport_size0_r_d1 <= viewport_size0_r;
            viewport_size0_r_d2 <= viewport_size0_r_d1;
            viewport_size0_r_d3 <= viewport_size0_r_d2;
            viewport_size0_r_d4 <= viewport_size0_r_d3;
            viewport_size0_r_d5 <= viewport_size0_r_d4;
            viewport_size0_r_d6 <= viewport_size0_r_d5;
            viewport_size0_r_d7 <= viewport_size0_r_d6;
            viewport_size0_r_d8 <= viewport_size0_r_d7;
            viewport_size0_r_d9 <= viewport_size0_r_d8;
            viewport_size0_r_d10 <= viewport_size0_r_d9;
            viewport_size0_r_d11 <= viewport_size0_r_d10;
            viewport_size0_r_d12 <= viewport_size0_r_d11;
            viewport_size0_r_d13 <= viewport_size0_r_d12;
            viewport_size0_r_d14 <= viewport_size0_r_d13;
            viewport_size0_r_d15 <= viewport_size0_r_d14;
            viewport_product0 <= $signed(viewport_adjust0_w) * $signed({1'b0,
            viewport_size0_r_d15});
            viewport_product0_p1 <= viewport_product0;
            viewport_product0_p2 <= viewport_product0_p1;
            viewport_shift0 <= viewport_product0_p2 << 3;
            position_negative <= ~position_ext1_w;
            position_negate_part0 <= {1'b0, position_negate_a0_w} + {1'b0, position_negate_b0_w};
            position_negate_a1_w_d14 <= position_negate_a1_w;
            position_negate_b1_w_d14 <= position_negate_b1_w;
            position_negate_part1 <= {1'b0, position_negate_a1_w_d14} + {1'b0,
            position_negate_b1_w_d14} + {35'b0, position_negate_part0[35]};
            position_negate_a2_w_d14 <= position_negate_a2_w;
            position_negate_a2_w_d15 <= position_negate_a2_w_d14;
            position_negate_b2_w_d14 <= position_negate_b2_w;
            position_negate_b2_w_d15 <= position_negate_b2_w_d14;
            unused_position_negate_part2 <= {1'b0, position_negate_a2_w_d15} + {1'b0,
            position_negate_b2_w_d15} + {24'b0, position_negate_part1[35]};
            position_negate_low1_w_d16 <= position_negate_low1_w;
            position_negate_low0_w_d15 <= position_negate_low0_w;
            position_negate_low0_w_d16 <= position_negate_low0_w_d15;
            viewport_one1_w_d13 <= viewport_one1_w;
            viewport_one1_w_d14 <= viewport_one1_w_d13;
            viewport_one1_w_d15 <= viewport_one1_w_d14;
            viewport_one1_w_d16 <= viewport_one1_w_d15;
            viewport_adjust1_part0 <= {1'b0, viewport_adjust1_a0_w} + {1'b0, viewport_adjust1_b0_w};
            viewport_adjust1_a1_w_d17 <= viewport_adjust1_a1_w;
            viewport_adjust1_b1_w_d17 <= viewport_adjust1_b1_w;
            viewport_adjust1_part1 <= {1'b0, viewport_adjust1_a1_w_d17} + {1'b0,
            viewport_adjust1_b1_w_d17} + {35'b0, viewport_adjust1_part0[35]};
            viewport_adjust1_a2_w_d17 <= viewport_adjust1_a2_w;
            viewport_adjust1_a2_w_d18 <= viewport_adjust1_a2_w_d17;
            viewport_adjust1_b2_w_d17 <= viewport_adjust1_b2_w;
            viewport_adjust1_b2_w_d18 <= viewport_adjust1_b2_w_d17;
            unused_viewport_adjust1_part2 <= {1'b0, viewport_adjust1_a2_w_d18} + {1'b0,
            viewport_adjust1_b2_w_d18} + {24'b0, viewport_adjust1_part1[35]};
            viewport_adjust1_low1_w_d19 <= viewport_adjust1_low1_w;
            viewport_adjust1_low0_w_d18 <= viewport_adjust1_low0_w;
            viewport_adjust1_low0_w_d19 <= viewport_adjust1_low0_w_d18;
            viewport_size1_r <= viewport_i[48 +: 16];
            viewport_size1_r_d1 <= viewport_size1_r;
            viewport_size1_r_d2 <= viewport_size1_r_d1;
            viewport_size1_r_d3 <= viewport_size1_r_d2;
            viewport_size1_r_d4 <= viewport_size1_r_d3;
            viewport_size1_r_d5 <= viewport_size1_r_d4;
            viewport_size1_r_d6 <= viewport_size1_r_d5;
            viewport_size1_r_d7 <= viewport_size1_r_d6;
            viewport_size1_r_d8 <= viewport_size1_r_d7;
            viewport_size1_r_d9 <= viewport_size1_r_d8;
            viewport_size1_r_d10 <= viewport_size1_r_d9;
            viewport_size1_r_d11 <= viewport_size1_r_d10;
            viewport_size1_r_d12 <= viewport_size1_r_d11;
            viewport_size1_r_d13 <= viewport_size1_r_d12;
            viewport_size1_r_d14 <= viewport_size1_r_d13;
            viewport_size1_r_d15 <= viewport_size1_r_d14;
            viewport_size1_r_d16 <= viewport_size1_r_d15;
            viewport_size1_r_d17 <= viewport_size1_r_d16;
            viewport_size1_r_d18 <= viewport_size1_r_d17;
            viewport_size1_r_d19 <= viewport_size1_r_d18;
            viewport_product1 <= $signed(viewport_adjust1_w) * $signed({1'b0,
            viewport_size1_r_d19});
            viewport_product1_p1 <= viewport_product1;
            viewport_product1_p2 <= viewport_product1_p1;
            viewport_shift1 <= viewport_product1_p2 << 3;
            depth_invert <= ~position_ext2_w;
            depth_negate_part0 <= {1'b0, depth_negate_a0_w} + {1'b0, depth_negate_b0_w};
            depth_negate_a1_w_d14 <= depth_negate_a1_w;
            depth_negate_b1_w_d14 <= depth_negate_b1_w;
            depth_negate_part1 <= {1'b0, depth_negate_a1_w_d14} + {1'b0, depth_negate_b1_w_d14}
            + {35'b0, depth_negate_part0[35]};
            depth_negate_a2_w_d14 <= depth_negate_a2_w;
            depth_negate_a2_w_d15 <= depth_negate_a2_w_d14;
            depth_negate_b2_w_d14 <= depth_negate_b2_w;
            depth_negate_b2_w_d15 <= depth_negate_b2_w_d14;
            unused_depth_negate_part2 <= {1'b0, depth_negate_a2_w_d15} + {1'b0,
            depth_negate_b2_w_d15} + {24'b0, depth_negate_part1[35]};
            depth_negate_low1_w_d16 <= depth_negate_low1_w;
            depth_negate_low0_w_d15 <= depth_negate_low0_w;
            depth_negate_low0_w_d16 <= depth_negate_low0_w_d15;
            depth_left_w_d13 <= depth_left_w;
            depth_left_w_d14 <= depth_left_w_d13;
            depth_left_w_d15 <= depth_left_w_d14;
            depth_left_w_d16 <= depth_left_w_d15;
            depth_subtract_part0 <= {1'b0, depth_subtract_a0_w} + {1'b0, depth_subtract_b0_w};
            depth_subtract_a1_w_d17 <= depth_subtract_a1_w;
            depth_subtract_b1_w_d17 <= depth_subtract_b1_w;
            depth_subtract_part1 <= {1'b0, depth_subtract_a1_w_d17} + {1'b0,
            depth_subtract_b1_w_d17} + {35'b0, depth_subtract_part0[35]};
            depth_subtract_a2_w_d17 <= depth_subtract_a2_w;
            depth_subtract_a2_w_d18 <= depth_subtract_a2_w_d17;
            depth_subtract_b2_w_d17 <= depth_subtract_b2_w;
            depth_subtract_b2_w_d18 <= depth_subtract_b2_w_d17;
            unused_depth_subtract_part2 <= {1'b0, depth_subtract_a2_w_d18} + {1'b0,
            depth_subtract_b2_w_d18} + {24'b0, depth_subtract_part1[35]};
            depth_subtract_low1_w_d19 <= depth_subtract_low1_w;
            depth_subtract_low0_w_d18 <= depth_subtract_low0_w;
            depth_subtract_low0_w_d19 <= depth_subtract_low0_w_d18;
            screen_abs0_sign <= viewport_shift0[93];
            screen_abs0_invert <= viewport_shift0[93] ? ~viewport_shift0 : viewport_shift0;
            screen_abs0_part0 <= {1'b0, screen_abs0_a0_w} + {1'b0, screen_abs0_b0_w};
            screen_abs0_a1_w_d21 <= screen_abs0_a1_w;
            screen_abs0_b1_w_d21 <= screen_abs0_b1_w;
            screen_abs0_part1 <= {1'b0, screen_abs0_a1_w_d21} + {1'b0, screen_abs0_b1_w_d21} +
            {35'b0, screen_abs0_part0[35]};
            screen_abs0_a2_w_d21 <= screen_abs0_a2_w;
            screen_abs0_a2_w_d22 <= screen_abs0_a2_w_d21;
            screen_abs0_b2_w_d21 <= screen_abs0_b2_w;
            screen_abs0_b2_w_d22 <= screen_abs0_b2_w_d21;
            unused_screen_abs0_part2 <= {1'b0, screen_abs0_a2_w_d22} + {1'b0,
            screen_abs0_b2_w_d22} + {24'b0, screen_abs0_part1[35]};
            screen_abs0_low1_w_d23 <= screen_abs0_low1_w;
            screen_abs0_low0_w_d22 <= screen_abs0_low0_w;
            screen_abs0_low0_w_d23 <= screen_abs0_low0_w_d22;
            screen_round0_part0 <= {1'b0, screen_round0_a0_w} + {1'b0, screen_round0_b0_w};
            screen_round0_a1_w_d24 <= screen_round0_a1_w;
            screen_round0_b1_w_d24 <= screen_round0_b1_w;
            unused_screen_round0_part1 <= {1'b0, screen_round0_a1_w_d24} + {1'b0,
            screen_round0_b1_w_d24} + {14'b0, screen_round0_part0[35]};
            screen_round0_low0_w_d25 <= screen_round0_low0_w;
            screen_abs0_sign_d21 <= screen_abs0_sign;
            screen_abs0_sign_d22 <= screen_abs0_sign_d21;
            screen_abs0_sign_d23 <= screen_abs0_sign_d22;
            screen_abs0_sign_d24 <= screen_abs0_sign_d23;
            screen_abs0_sign_d25 <= screen_abs0_sign_d24;
            screen_signed0_invert <= screen_abs0_sign_d25 ? ~screen_round0_w : screen_round0_w;
            screen_abs0_sign_d26 <= screen_abs0_sign_d25;
            screen_signed0_part0 <= {1'b0, screen_signed0_a0_w} + {1'b0, screen_signed0_b0_w};
            screen_signed0_a1_w_d27 <= screen_signed0_a1_w;
            screen_signed0_b1_w_d27 <= screen_signed0_b1_w;
            unused_screen_signed0_part1 <= {1'b0, screen_signed0_a1_w_d27} + {1'b0,
            screen_signed0_b1_w_d27} + {14'b0, screen_signed0_part0[35]};
            screen_signed0_low0_w_d28 <= screen_signed0_low0_w;
            viewport_offset0_r <= viewport_i[0 +: 16];
            viewport_offset_ext0_w_d1 <= viewport_offset_ext0_w;
            viewport_offset_ext0_w_d2 <= viewport_offset_ext0_w_d1;
            viewport_offset_ext0_w_d3 <= viewport_offset_ext0_w_d2;
            viewport_offset_ext0_w_d4 <= viewport_offset_ext0_w_d3;
            viewport_offset_ext0_w_d5 <= viewport_offset_ext0_w_d4;
            viewport_offset_ext0_w_d6 <= viewport_offset_ext0_w_d5;
            viewport_offset_ext0_w_d7 <= viewport_offset_ext0_w_d6;
            viewport_offset_ext0_w_d8 <= viewport_offset_ext0_w_d7;
            viewport_offset_ext0_w_d9 <= viewport_offset_ext0_w_d8;
            viewport_offset_ext0_w_d10 <= viewport_offset_ext0_w_d9;
            viewport_offset_ext0_w_d11 <= viewport_offset_ext0_w_d10;
            viewport_offset_ext0_w_d12 <= viewport_offset_ext0_w_d11;
            viewport_offset_ext0_w_d13 <= viewport_offset_ext0_w_d12;
            viewport_offset_ext0_w_d14 <= viewport_offset_ext0_w_d13;
            viewport_offset_ext0_w_d15 <= viewport_offset_ext0_w_d14;
            viewport_offset_ext0_w_d16 <= viewport_offset_ext0_w_d15;
            viewport_offset_ext0_w_d17 <= viewport_offset_ext0_w_d16;
            viewport_offset_ext0_w_d18 <= viewport_offset_ext0_w_d17;
            viewport_offset_ext0_w_d19 <= viewport_offset_ext0_w_d18;
            viewport_offset_ext0_w_d20 <= viewport_offset_ext0_w_d19;
            viewport_offset_ext0_w_d21 <= viewport_offset_ext0_w_d20;
            viewport_offset_ext0_w_d22 <= viewport_offset_ext0_w_d21;
            viewport_offset_ext0_w_d23 <= viewport_offset_ext0_w_d22;
            viewport_offset_ext0_w_d24 <= viewport_offset_ext0_w_d23;
            viewport_offset_ext0_w_d25 <= viewport_offset_ext0_w_d24;
            viewport_offset_ext0_w_d26 <= viewport_offset_ext0_w_d25;
            viewport_offset_ext0_w_d27 <= viewport_offset_ext0_w_d26;
            viewport_offset_ext0_w_d28 <= viewport_offset_ext0_w_d27;
            screen_offset0_part0 <= {1'b0, screen_offset0_a0_w} + {1'b0, screen_offset0_b0_w};
            screen_offset0_a1_w_d29 <= screen_offset0_a1_w;
            screen_offset0_b1_w_d29 <= screen_offset0_b1_w;
            unused_screen_offset0_part1 <= {1'b0, screen_offset0_a1_w_d29} + {1'b0,
            screen_offset0_b1_w_d29} + {14'b0, screen_offset0_part0[35]};
            screen_offset0_low0_w_d30 <= screen_offset0_low0_w;
            screen_clamp0 <= $signed(screen_offset0_w) > 49'sd65535 ? 17'h0ffff :
            $signed(screen_offset0_w) < -49'sd65536 ? 17'h10000 : screen_offset0_w[16:0];
            screen_abs1_sign <= viewport_shift1[93];
            screen_abs1_invert <= viewport_shift1[93] ? ~viewport_shift1 : viewport_shift1;
            screen_abs1_part0 <= {1'b0, screen_abs1_a0_w} + {1'b0, screen_abs1_b0_w};
            screen_abs1_a1_w_d25 <= screen_abs1_a1_w;
            screen_abs1_b1_w_d25 <= screen_abs1_b1_w;
            screen_abs1_part1 <= {1'b0, screen_abs1_a1_w_d25} + {1'b0, screen_abs1_b1_w_d25} +
            {35'b0, screen_abs1_part0[35]};
            screen_abs1_a2_w_d25 <= screen_abs1_a2_w;
            screen_abs1_a2_w_d26 <= screen_abs1_a2_w_d25;
            screen_abs1_b2_w_d25 <= screen_abs1_b2_w;
            screen_abs1_b2_w_d26 <= screen_abs1_b2_w_d25;
            unused_screen_abs1_part2 <= {1'b0, screen_abs1_a2_w_d26} + {1'b0,
            screen_abs1_b2_w_d26} + {24'b0, screen_abs1_part1[35]};
            screen_abs1_low1_w_d27 <= screen_abs1_low1_w;
            screen_abs1_low0_w_d26 <= screen_abs1_low0_w;
            screen_abs1_low0_w_d27 <= screen_abs1_low0_w_d26;
            screen_round1_part0 <= {1'b0, screen_round1_a0_w} + {1'b0, screen_round1_b0_w};
            screen_round1_a1_w_d28 <= screen_round1_a1_w;
            screen_round1_b1_w_d28 <= screen_round1_b1_w;
            unused_screen_round1_part1 <= {1'b0, screen_round1_a1_w_d28} + {1'b0,
            screen_round1_b1_w_d28} + {14'b0, screen_round1_part0[35]};
            screen_round1_low0_w_d29 <= screen_round1_low0_w;
            screen_abs1_sign_d25 <= screen_abs1_sign;
            screen_abs1_sign_d26 <= screen_abs1_sign_d25;
            screen_abs1_sign_d27 <= screen_abs1_sign_d26;
            screen_abs1_sign_d28 <= screen_abs1_sign_d27;
            screen_abs1_sign_d29 <= screen_abs1_sign_d28;
            screen_signed1_invert <= screen_abs1_sign_d29 ? ~screen_round1_w : screen_round1_w;
            screen_abs1_sign_d30 <= screen_abs1_sign_d29;
            screen_signed1_part0 <= {1'b0, screen_signed1_a0_w} + {1'b0, screen_signed1_b0_w};
            screen_signed1_a1_w_d31 <= screen_signed1_a1_w;
            screen_signed1_b1_w_d31 <= screen_signed1_b1_w;
            unused_screen_signed1_part1 <= {1'b0, screen_signed1_a1_w_d31} + {1'b0,
            screen_signed1_b1_w_d31} + {14'b0, screen_signed1_part0[35]};
            screen_signed1_low0_w_d32 <= screen_signed1_low0_w;
            viewport_offset1_r <= viewport_i[16 +: 16];
            viewport_offset_ext1_w_d1 <= viewport_offset_ext1_w;
            viewport_offset_ext1_w_d2 <= viewport_offset_ext1_w_d1;
            viewport_offset_ext1_w_d3 <= viewport_offset_ext1_w_d2;
            viewport_offset_ext1_w_d4 <= viewport_offset_ext1_w_d3;
            viewport_offset_ext1_w_d5 <= viewport_offset_ext1_w_d4;
            viewport_offset_ext1_w_d6 <= viewport_offset_ext1_w_d5;
            viewport_offset_ext1_w_d7 <= viewport_offset_ext1_w_d6;
            viewport_offset_ext1_w_d8 <= viewport_offset_ext1_w_d7;
            viewport_offset_ext1_w_d9 <= viewport_offset_ext1_w_d8;
            viewport_offset_ext1_w_d10 <= viewport_offset_ext1_w_d9;
            viewport_offset_ext1_w_d11 <= viewport_offset_ext1_w_d10;
            viewport_offset_ext1_w_d12 <= viewport_offset_ext1_w_d11;
            viewport_offset_ext1_w_d13 <= viewport_offset_ext1_w_d12;
            viewport_offset_ext1_w_d14 <= viewport_offset_ext1_w_d13;
            viewport_offset_ext1_w_d15 <= viewport_offset_ext1_w_d14;
            viewport_offset_ext1_w_d16 <= viewport_offset_ext1_w_d15;
            viewport_offset_ext1_w_d17 <= viewport_offset_ext1_w_d16;
            viewport_offset_ext1_w_d18 <= viewport_offset_ext1_w_d17;
            viewport_offset_ext1_w_d19 <= viewport_offset_ext1_w_d18;
            viewport_offset_ext1_w_d20 <= viewport_offset_ext1_w_d19;
            viewport_offset_ext1_w_d21 <= viewport_offset_ext1_w_d20;
            viewport_offset_ext1_w_d22 <= viewport_offset_ext1_w_d21;
            viewport_offset_ext1_w_d23 <= viewport_offset_ext1_w_d22;
            viewport_offset_ext1_w_d24 <= viewport_offset_ext1_w_d23;
            viewport_offset_ext1_w_d25 <= viewport_offset_ext1_w_d24;
            viewport_offset_ext1_w_d26 <= viewport_offset_ext1_w_d25;
            viewport_offset_ext1_w_d27 <= viewport_offset_ext1_w_d26;
            viewport_offset_ext1_w_d28 <= viewport_offset_ext1_w_d27;
            viewport_offset_ext1_w_d29 <= viewport_offset_ext1_w_d28;
            viewport_offset_ext1_w_d30 <= viewport_offset_ext1_w_d29;
            viewport_offset_ext1_w_d31 <= viewport_offset_ext1_w_d30;
            viewport_offset_ext1_w_d32 <= viewport_offset_ext1_w_d31;
            screen_offset1_part0 <= {1'b0, screen_offset1_a0_w} + {1'b0, screen_offset1_b0_w};
            screen_offset1_a1_w_d33 <= screen_offset1_a1_w;
            screen_offset1_b1_w_d33 <= screen_offset1_b1_w;
            unused_screen_offset1_part1 <= {1'b0, screen_offset1_a1_w_d33} + {1'b0,
            screen_offset1_b1_w_d33} + {14'b0, screen_offset1_part0[35]};
            screen_offset1_low0_w_d34 <= screen_offset1_low0_w;
            screen_clamp1 <= $signed(screen_offset1_w) > 49'sd65535 ? 17'h0ffff :
            $signed(screen_offset1_w) < -49'sd65536 ? 17'h10000 : screen_offset1_w[16:0];
            depth_round_part0 <= {1'b0, depth_round_a0_w} + {1'b0, depth_round_b0_w};
            depth_round_a1_w_d20 <= depth_round_a1_w;
            depth_round_b1_w_d20 <= depth_round_b1_w;
            unused_depth_round_part1 <= {1'b0, depth_round_a1_w_d20} + {1'b0,
            depth_round_b1_w_d20} + {14'b0, depth_round_part0[35]};
            depth_round_low0_w_d21 <= depth_round_low0_w;
            depth_subtract_w_d20 <= depth_subtract_w;
            unused_depth_subtract_w_d21 <= depth_subtract_w_d20;
            depth_clamp <= unused_depth_subtract_w_d21[93] ? 16'b0 : depth_round_w > 65535 ?
            16'hffff : depth_round_w[15:0];
            screen_clamp0_d32 <= screen_clamp0;
            screen_clamp0_d33 <= screen_clamp0_d32;
            screen_clamp0_d34 <= screen_clamp0_d33;
            screen_clamp0_d35 <= screen_clamp0_d34;
            depth_clamp_d23 <= depth_clamp;
            depth_clamp_d24 <= depth_clamp_d23;
            depth_clamp_d25 <= depth_clamp_d24;
            depth_clamp_d26 <= depth_clamp_d25;
            depth_clamp_d27 <= depth_clamp_d26;
            depth_clamp_d28 <= depth_clamp_d27;
            depth_clamp_d29 <= depth_clamp_d28;
            depth_clamp_d30 <= depth_clamp_d29;
            depth_clamp_d31 <= depth_clamp_d30;
            depth_clamp_d32 <= depth_clamp_d31;
            depth_clamp_d33 <= depth_clamp_d32;
            depth_clamp_d34 <= depth_clamp_d33;
            depth_clamp_d35 <= depth_clamp_d34;
            restored_d10 <= restored;
            restored_d11 <= restored_d10;
            restored_d12 <= restored_d11;
            restored_d13 <= restored_d12;
            restored_d14 <= restored_d13;
            restored_d15 <= restored_d14;
            restored_d16 <= restored_d15;
            restored_d17 <= restored_d16;
            restored_d18 <= restored_d17;
            restored_d19 <= restored_d18;
            restored_d20 <= restored_d19;
            restored_d21 <= restored_d20;
            restored_d22 <= restored_d21;
            restored_d23 <= restored_d22;
            restored_d24 <= restored_d23;
            restored_d25 <= restored_d24;
            restored_d26 <= restored_d25;
            restored_d27 <= restored_d26;
            restored_d28 <= restored_d27;
            restored_d29 <= restored_d28;
            restored_d30 <= restored_d29;
            restored_d31 <= restored_d30;
            restored_d32 <= restored_d31;
            restored_d33 <= restored_d32;
            restored_d34 <= restored_d33;
            restored_d35 <= restored_d34;
            uv_product0_p2_d13 <= uv_product0_p2;
            uv_product0_p2_d14 <= uv_product0_p2_d13;
            uv_product0_p2_d15 <= uv_product0_p2_d14;
            uv_product0_p2_d16 <= uv_product0_p2_d15;
            uv_product0_p2_d17 <= uv_product0_p2_d16;
            uv_product0_p2_d18 <= uv_product0_p2_d17;
            uv_product0_p2_d19 <= uv_product0_p2_d18;
            uv_product0_p2_d20 <= uv_product0_p2_d19;
            uv_product0_p2_d21 <= uv_product0_p2_d20;
            uv_product0_p2_d22 <= uv_product0_p2_d21;
            uv_product0_p2_d23 <= uv_product0_p2_d22;
            uv_product0_p2_d24 <= uv_product0_p2_d23;
            uv_product0_p2_d25 <= uv_product0_p2_d24;
            uv_product0_p2_d26 <= uv_product0_p2_d25;
            uv_product0_p2_d27 <= uv_product0_p2_d26;
            uv_product0_p2_d28 <= uv_product0_p2_d27;
            uv_product0_p2_d29 <= uv_product0_p2_d28;
            uv_product0_p2_d30 <= uv_product0_p2_d29;
            uv_product0_p2_d31 <= uv_product0_p2_d30;
            uv_product0_p2_d32 <= uv_product0_p2_d31;
            uv_product0_p2_d33 <= uv_product0_p2_d32;
            uv_product0_p2_d34 <= uv_product0_p2_d33;
            uv_product0_p2_d35 <= uv_product0_p2_d34;
            uv_product1_p2_d13 <= uv_product1_p2;
            uv_product1_p2_d14 <= uv_product1_p2_d13;
            uv_product1_p2_d15 <= uv_product1_p2_d14;
            uv_product1_p2_d16 <= uv_product1_p2_d15;
            uv_product1_p2_d17 <= uv_product1_p2_d16;
            uv_product1_p2_d18 <= uv_product1_p2_d17;
            uv_product1_p2_d19 <= uv_product1_p2_d18;
            uv_product1_p2_d20 <= uv_product1_p2_d19;
            uv_product1_p2_d21 <= uv_product1_p2_d20;
            uv_product1_p2_d22 <= uv_product1_p2_d21;
            uv_product1_p2_d23 <= uv_product1_p2_d22;
            uv_product1_p2_d24 <= uv_product1_p2_d23;
            uv_product1_p2_d25 <= uv_product1_p2_d24;
            uv_product1_p2_d26 <= uv_product1_p2_d25;
            uv_product1_p2_d27 <= uv_product1_p2_d26;
            uv_product1_p2_d28 <= uv_product1_p2_d27;
            uv_product1_p2_d29 <= uv_product1_p2_d28;
            uv_product1_p2_d30 <= uv_product1_p2_d29;
            uv_product1_p2_d31 <= uv_product1_p2_d30;
            uv_product1_p2_d32 <= uv_product1_p2_d31;
            uv_product1_p2_d33 <= uv_product1_p2_d32;
            uv_product1_p2_d34 <= uv_product1_p2_d33;
            uv_product1_p2_d35 <= uv_product1_p2_d34;
            color_input_r_d2 <= color_input_r;
            color_input_r_d3 <= color_input_r_d2;
            color_input_r_d4 <= color_input_r_d3;
            color_input_r_d5 <= color_input_r_d4;
            color_input_r_d6 <= color_input_r_d5;
            color_input_r_d7 <= color_input_r_d6;
            color_input_r_d8 <= color_input_r_d7;
            color_input_r_d9 <= color_input_r_d8;
            color_input_r_d10 <= color_input_r_d9;
            color_input_r_d11 <= color_input_r_d10;
            color_input_r_d12 <= color_input_r_d11;
            color_input_r_d13 <= color_input_r_d12;
            color_input_r_d14 <= color_input_r_d13;
            color_input_r_d15 <= color_input_r_d14;
            color_input_r_d16 <= color_input_r_d15;
            color_input_r_d17 <= color_input_r_d16;
            color_input_r_d18 <= color_input_r_d17;
            color_input_r_d19 <= color_input_r_d18;
            color_input_r_d20 <= color_input_r_d19;
            color_input_r_d21 <= color_input_r_d20;
            color_input_r_d22 <= color_input_r_d21;
            color_input_r_d23 <= color_input_r_d22;
            color_input_r_d24 <= color_input_r_d23;
            color_input_r_d25 <= color_input_r_d24;
            color_input_r_d26 <= color_input_r_d25;
            color_input_r_d27 <= color_input_r_d26;
            color_input_r_d28 <= color_input_r_d27;
            color_input_r_d29 <= color_input_r_d28;
            color_input_r_d30 <= color_input_r_d29;
            color_input_r_d31 <= color_input_r_d30;
            color_input_r_d32 <= color_input_r_d31;
            color_input_r_d33 <= color_input_r_d32;
            color_input_r_d34 <= color_input_r_d33;
            color_input_r_d35 <= color_input_r_d34;
        end
    end
endmodule
