// File: edrv32_gpu_setup_plane.v
// Spec: gpu-spec 2.13.3-6, 13; GPU microarchitecture 4.4, 4.10.
// Description: One attribute per enabled clock, with complete products and explicit rounding.
//              Difference form removes one vertex product per numerator without changing its sum.
// Clock domain: clk_gpu.
module edrv32_gpu_setup_plane (
    // Clock and pipeline control.
    input wire clk_i,
    input wire rst_n_i,
    input wire enable_i,
    input wire credit_push_i,
    input wire credit_pop_i,
    input wire stop_i,

    // Attribute and triangle context.
    input wire plane_valid_i,
    input wire [6:0] plane_tag_i,
    input wire [152:0] plane_value_i,
    input wire [71:0] plane_delta_i,
    input wire [35:0] plane_offset_i,
    input wire [30:0] plane_reciprocal_i,
    input wire [5:0] plane_exponent_i,

    // Complete coefficient for the tagged attribute.
    output wire plane_valid_o,
    output wire [6:0] plane_tag_o,
    output wire [65:0] plane_start_o,
    output wire [103:0] plane_gradient_o,
    output wire [9:0] plane_h_o
);
    // S-5: registered 18x18 APM partial products, sliced add trees and tagged context.
    reg [152:0] value_0_r;
    reg [6:0] tag_0_r;
    reg [30:0] reciprocal_context_r [0:15];
    reg [5:0] exponent_context_r [0:15];
    reg [17:0] delta_context0_r [0:15];
    reg [17:0] delta_context1_r [0:15];
    reg [17:0] delta_context2_r [0:15];
    reg [17:0] delta_context3_r [0:15];
    reg [17:0] offset_context0_r [0:15];
    reg [17:0] offset_context1_r [0:15];
    wire [50:0] vertex0_w;
    wire [50:0] vertex1_w;
    wire [50:0] vertex2_w;
    reg [2:0] maximum01_compare_r;
    wire [50:0] vertex0_w_d1_r;
    wire [50:0] vertex1_w_d1_r;
    reg [50:0] maximum01_select_r;
    wire [50:0] vertex2_w_d2_r;
    reg [2:0] maximum012_compare_r;
    wire [50:0] maximum01_select_d3_r;
    wire [50:0] vertex2_w_d3_r;
    reg [50:0] maximum012_select_r;
    reg [5:0] leading_group0_r;
    reg [5:0] leading_group1_r;
    reg [5:0] leading_group2_r;
    reg [5:0] leading_group3_r;
    reg [5:0] leading_group4_r;
    reg [5:0] leading_group5_r;
    reg [5:0] leading_group6_r;
    reg [5:0] leading_group7_r;
    reg [5:0] leading_group8_r;
    reg [5:0] leading_group9_r;
    reg [5:0] leading_group10_r;
    reg [5:0] leading_group11_r;
    reg [5:0] leading_group12_r;
    reg [12:0] nonzero_groups_r;
    reg [5:0] leading_partial0_r;
    reg [5:0] leading_partial1_r;
    reg [5:0] leading_partial2_r;
    reg [5:0] leading_partial3_r;
    wire [12:0] nonzero_groups_d6_r;
    reg [5:0] leading_r;
    wire [6:0] tag_0_r_d7_r;
    wire [50:0] maximum012_select_d7_r;
    reg [9:0] h_r;
    reg [5:0] right_amount_r;
    reg [5:0] left_amount_r;
    wire [51:0] v52_0_w;
    wire [1:0] scale_left0_amt0_w;
    reg [51:0] scale_left0_0_w;
    wire [51:0] v52_0_w_d9_r;
    reg [51:0] scale_left0_0_r;
    wire [1:0] scale_left0_amt1_w;
    reg [51:0] scale_left0_1_w;
    wire [1:0] scale_left0_amt1_w_d10_r;
    reg [51:0] scale_left0_1_r;
    wire [1:0] scale_left0_amt2_w;
    reg [51:0] unused_scale_left0_2_w;
    wire [1:0] scale_left0_amt2_w_d11_r;
    reg [32:0] scale_left0_2_r;
    reg [5:0] scale_bit0_r;
    wire [51:0] scale_one0_w;
    wire [1:0] scale_bias0_amt0_w;
    reg [51:0] scale_bias0_0_w;
    reg [51:0] scale_bias0_0_r;
    wire [1:0] scale_bias0_amt1_w;
    reg [51:0] scale_bias0_1_w;
    wire [1:0] scale_bias0_amt1_w_d11_r;
    reg [51:0] scale_bias0_1_r;
    wire [1:0] scale_bias0_amt2_w;
    reg [51:0] scale_bias0_2_w;
    wire [1:0] scale_bias0_amt2_w_d12_r;
    reg [51:0] scale_bias0_2_r;
    wire [51:0] v52_0_w_d13_r;
    wire [34:0] scale_add0_a0_w;
    wire [34:0] scale_add0_b0_w;
    reg [35:0] scale_add0_part0_r;
    wire [34:0] scale_add0_low0_w;
    wire [16:0] scale_add0_a1_w;
    wire [16:0] scale_add0_b1_w;
    wire [16:0] scale_add0_a1_w_d14_r;
    wire [16:0] scale_add0_b1_w_d14_r;
    reg [16:0] scale_add0_part1_r;
    wire [16:0] scale_add0_low1_w;
    wire [51:0] scale_add0_w;
    wire [34:0] scale_add0_low0_w_d15_r;
    wire [1:0] scale_rounded0_amt0_w;
    reg [51:0] scale_rounded0_0_w;
    wire [1:0] scale_rounded0_amt0_w_d15_r;
    reg [51:0] scale_rounded0_0_r;
    wire [1:0] scale_rounded0_amt1_w;
    reg [51:0] scale_rounded0_1_w;
    wire [1:0] scale_rounded0_amt1_w_d16_r;
    reg [51:0] scale_rounded0_1_r;
    wire [1:0] scale_rounded0_amt2_w;
    reg [51:0] unused_scale_rounded0_2_w;
    wire [1:0] scale_rounded0_amt2_w_d17_r;
    reg [32:0] scale_rounded0_2_r;
    wire [9:0] h_d18_r;
    wire [32:0] scale_left0_2_r_d18_r;
    reg [32:0] scaled0_r;
    wire [51:0] v52_1_w;
    wire [1:0] scale_left1_amt0_w;
    reg [51:0] scale_left1_0_w;
    wire [51:0] v52_1_w_d9_r;
    reg [51:0] scale_left1_0_r;
    wire [1:0] scale_left1_amt1_w;
    reg [51:0] scale_left1_1_w;
    wire [1:0] scale_left1_amt1_w_d10_r;
    reg [51:0] scale_left1_1_r;
    wire [1:0] scale_left1_amt2_w;
    reg [51:0] unused_scale_left1_2_w;
    wire [1:0] scale_left1_amt2_w_d11_r;
    reg [32:0] scale_left1_2_r;
    reg [5:0] scale_bit1_r;
    wire [51:0] scale_one1_w;
    wire [1:0] scale_bias1_amt0_w;
    reg [51:0] scale_bias1_0_w;
    reg [51:0] scale_bias1_0_r;
    wire [1:0] scale_bias1_amt1_w;
    reg [51:0] scale_bias1_1_w;
    wire [1:0] scale_bias1_amt1_w_d11_r;
    reg [51:0] scale_bias1_1_r;
    wire [1:0] scale_bias1_amt2_w;
    reg [51:0] scale_bias1_2_w;
    wire [1:0] scale_bias1_amt2_w_d12_r;
    reg [51:0] scale_bias1_2_r;
    wire [51:0] v52_1_w_d13_r;
    wire [34:0] scale_add1_a0_w;
    wire [34:0] scale_add1_b0_w;
    reg [35:0] scale_add1_part0_r;
    wire [34:0] scale_add1_low0_w;
    wire [16:0] scale_add1_a1_w;
    wire [16:0] scale_add1_b1_w;
    wire [16:0] scale_add1_a1_w_d14_r;
    wire [16:0] scale_add1_b1_w_d14_r;
    reg [16:0] scale_add1_part1_r;
    wire [16:0] scale_add1_low1_w;
    wire [51:0] scale_add1_w;
    wire [34:0] scale_add1_low0_w_d15_r;
    wire [1:0] scale_rounded1_amt0_w;
    reg [51:0] scale_rounded1_0_w;
    wire [1:0] scale_rounded1_amt0_w_d15_r;
    reg [51:0] scale_rounded1_0_r;
    wire [1:0] scale_rounded1_amt1_w;
    reg [51:0] scale_rounded1_1_w;
    wire [1:0] scale_rounded1_amt1_w_d16_r;
    reg [51:0] scale_rounded1_1_r;
    wire [1:0] scale_rounded1_amt2_w;
    reg [51:0] unused_scale_rounded1_2_w;
    wire [1:0] scale_rounded1_amt2_w_d17_r;
    reg [32:0] scale_rounded1_2_r;
    wire [32:0] scale_left1_2_r_d18_r;
    reg [32:0] scaled1_r;
    wire [51:0] v52_2_w;
    wire [1:0] scale_left2_amt0_w;
    reg [51:0] scale_left2_0_w;
    wire [51:0] v52_2_w_d9_r;
    reg [51:0] scale_left2_0_r;
    wire [1:0] scale_left2_amt1_w;
    reg [51:0] scale_left2_1_w;
    wire [1:0] scale_left2_amt1_w_d10_r;
    reg [51:0] scale_left2_1_r;
    wire [1:0] scale_left2_amt2_w;
    reg [51:0] unused_scale_left2_2_w;
    wire [1:0] scale_left2_amt2_w_d11_r;
    reg [32:0] scale_left2_2_r;
    reg [5:0] scale_bit2_r;
    wire [51:0] scale_one2_w;
    wire [1:0] scale_bias2_amt0_w;
    reg [51:0] scale_bias2_0_w;
    reg [51:0] scale_bias2_0_r;
    wire [1:0] scale_bias2_amt1_w;
    reg [51:0] scale_bias2_1_w;
    wire [1:0] scale_bias2_amt1_w_d11_r;
    reg [51:0] scale_bias2_1_r;
    wire [1:0] scale_bias2_amt2_w;
    reg [51:0] scale_bias2_2_w;
    wire [1:0] scale_bias2_amt2_w_d12_r;
    reg [51:0] scale_bias2_2_r;
    wire [51:0] v52_2_w_d13_r;
    wire [34:0] scale_add2_a0_w;
    wire [34:0] scale_add2_b0_w;
    reg [35:0] scale_add2_part0_r;
    wire [34:0] scale_add2_low0_w;
    wire [16:0] scale_add2_a1_w;
    wire [16:0] scale_add2_b1_w;
    wire [16:0] scale_add2_a1_w_d14_r;
    wire [16:0] scale_add2_b1_w_d14_r;
    reg [16:0] scale_add2_part1_r;
    wire [16:0] scale_add2_low1_w;
    wire [51:0] scale_add2_w;
    wire [34:0] scale_add2_low0_w_d15_r;
    wire [1:0] scale_rounded2_amt0_w;
    reg [51:0] scale_rounded2_0_w;
    wire [1:0] scale_rounded2_amt0_w_d15_r;
    reg [51:0] scale_rounded2_0_r;
    wire [1:0] scale_rounded2_amt1_w;
    reg [51:0] scale_rounded2_1_w;
    wire [1:0] scale_rounded2_amt1_w_d16_r;
    reg [51:0] scale_rounded2_1_r;
    wire [1:0] scale_rounded2_amt2_w;
    reg [51:0] unused_scale_rounded2_2_w;
    wire [1:0] scale_rounded2_amt2_w_d17_r;
    reg [32:0] scale_rounded2_2_r;
    wire [32:0] scale_left2_2_r_d18_r;
    reg [32:0] scaled2_r;
    reg [33:0] difference0_r;
    reg [33:0] difference1_r;
    wire [6:0] tag_0_r_d19_r;
    wire [3:0] delta_context0_r_0_index20_w;
    reg [17:0] delta_context0_r_0_read20_r;
    reg [35:0] product0_0_pp0_0_r;
    wire [51:0] product0_0_pp0_0_extend_w;
    wire [51:0] product0_0_pp0_0_aligned_w;
    reg [34:0] product0_0_pp1_0_r;
    wire [51:0] product0_0_pp1_0_extend_w;
    wire [51:0] product0_0_pp1_0_aligned_w;
    wire [34:0] product0_0_sum0_0_a0_w;
    wire [34:0] product0_0_sum0_0_b0_w;
    reg [35:0] product0_0_sum0_0_part0_r;
    wire [34:0] product0_0_sum0_0_low0_w;
    wire [16:0] product0_0_sum0_0_a1_w;
    wire [16:0] product0_0_sum0_0_b1_w;
    wire [16:0] product0_0_sum0_0_a1_w_d22_r;
    wire [16:0] product0_0_sum0_0_b1_w_d22_r;
    reg [16:0] product0_0_sum0_0_part1_r;
    wire [16:0] product0_0_sum0_0_low1_w;
    wire [51:0] product0_0_sum0_0_w;
    wire [34:0] product0_0_sum0_0_low0_w_d23_r;
    wire [3:0] delta_context1_r_0_index20_w;
    reg [17:0] delta_context1_r_0_read20_r;
    reg [35:0] product0_1_pp0_0_r;
    wire [51:0] product0_1_pp0_0_extend_w;
    wire [51:0] product0_1_pp0_0_aligned_w;
    reg [34:0] product0_1_pp1_0_r;
    wire [51:0] product0_1_pp1_0_extend_w;
    wire [51:0] product0_1_pp1_0_aligned_w;
    wire [34:0] product0_1_sum0_0_a0_w;
    wire [34:0] product0_1_sum0_0_b0_w;
    reg [35:0] product0_1_sum0_0_part0_r;
    wire [34:0] product0_1_sum0_0_low0_w;
    wire [16:0] product0_1_sum0_0_a1_w;
    wire [16:0] product0_1_sum0_0_b1_w;
    wire [16:0] product0_1_sum0_0_a1_w_d22_r;
    wire [16:0] product0_1_sum0_0_b1_w_d22_r;
    reg [16:0] product0_1_sum0_0_part1_r;
    wire [16:0] product0_1_sum0_0_low1_w;
    wire [51:0] product0_1_sum0_0_w;
    wire [34:0] product0_1_sum0_0_low0_w_d23_r;
    wire [55:0] product_ext0_0_w;
    wire [55:0] product_ext0_1_w;
    wire [34:0] numerator0_a0_w;
    wire [34:0] numerator0_b0_w;
    reg [35:0] numerator0_part0_r;
    wire [34:0] numerator0_low0_w;
    wire [20:0] numerator0_a1_w;
    wire [20:0] numerator0_b1_w;
    wire [20:0] numerator0_a1_w_d24_r;
    wire [20:0] numerator0_b1_w_d24_r;
    reg [20:0] numerator0_part1_r;
    wire [20:0] numerator0_low1_w;
    wire [55:0] numerator0_w;
    wire [34:0] numerator0_low0_w_d25_r;
    reg [55:0] numerator_shift0_r;
    wire [6:0] tag_0_r_d25_r;
    wire [3:0] reciprocal_context_r_0_index26_w;
    reg [30:0] reciprocal_context_r_0_read26_r;
    reg [35:0] inverse0_pp0_0_r;
    wire [86:0] inverse0_pp0_0_extend_w;
    wire [86:0] inverse0_pp0_0_aligned_w;
    reg [32:0] inverse0_pp0_1_r;
    wire [86:0] inverse0_pp0_1_extend_w;
    wire [86:0] inverse0_pp0_1_aligned_w;
    reg [35:0] inverse0_pp1_0_r;
    wire [86:0] inverse0_pp1_0_extend_w;
    wire [86:0] inverse0_pp1_0_aligned_w;
    reg [32:0] inverse0_pp1_1_r;
    wire [86:0] inverse0_pp1_1_extend_w;
    wire [86:0] inverse0_pp1_1_aligned_w;
    reg [35:0] inverse0_pp2_0_r;
    wire [86:0] inverse0_pp2_0_extend_w;
    wire [86:0] inverse0_pp2_0_aligned_w;
    reg [32:0] inverse0_pp2_1_r;
    wire [86:0] inverse0_pp2_1_extend_w;
    wire [86:0] inverse0_pp2_1_aligned_w;
    reg [22:0] inverse0_pp3_0_r;
    wire [86:0] inverse0_pp3_0_extend_w;
    wire [86:0] inverse0_pp3_0_aligned_w;
    reg [19:0] inverse0_pp3_1_r;
    wire [86:0] inverse0_pp3_1_extend_w;
    wire [86:0] inverse0_pp3_1_aligned_w;
    wire [34:0] inverse0_sum0_0_a0_w;
    wire [34:0] inverse0_sum0_0_b0_w;
    reg [35:0] inverse0_sum0_0_part0_r;
    wire [34:0] inverse0_sum0_0_low0_w;
    wire [34:0] inverse0_sum0_0_a1_w;
    wire [34:0] inverse0_sum0_0_b1_w;
    wire [34:0] inverse0_sum0_0_a1_w_d28_r;
    wire [34:0] inverse0_sum0_0_b1_w_d28_r;
    reg [35:0] inverse0_sum0_0_part1_r;
    wire [34:0] inverse0_sum0_0_low1_w;
    wire [16:0] inverse0_sum0_0_a2_w;
    wire [16:0] inverse0_sum0_0_b2_w;
    wire [16:0] inverse0_sum0_0_a2_w_d29_r;
    wire [16:0] inverse0_sum0_0_b2_w_d29_r;
    reg [16:0] inverse0_sum0_0_part2_r;
    wire [16:0] inverse0_sum0_0_low2_w;
    wire [86:0] inverse0_sum0_0_w;
    wire [34:0] inverse0_sum0_0_low1_w_d30_r;
    wire [34:0] inverse0_sum0_0_low0_w_d30_r;
    wire [34:0] inverse0_sum0_1_a0_w;
    wire [34:0] inverse0_sum0_1_b0_w;
    reg [35:0] inverse0_sum0_1_part0_r;
    wire [34:0] inverse0_sum0_1_low0_w;
    wire [34:0] inverse0_sum0_1_a1_w;
    wire [34:0] inverse0_sum0_1_b1_w;
    wire [34:0] inverse0_sum0_1_a1_w_d28_r;
    wire [34:0] inverse0_sum0_1_b1_w_d28_r;
    reg [35:0] inverse0_sum0_1_part1_r;
    wire [34:0] inverse0_sum0_1_low1_w;
    wire [16:0] inverse0_sum0_1_a2_w;
    wire [16:0] inverse0_sum0_1_b2_w;
    wire [16:0] inverse0_sum0_1_a2_w_d29_r;
    wire [16:0] inverse0_sum0_1_b2_w_d29_r;
    reg [16:0] inverse0_sum0_1_part2_r;
    wire [16:0] inverse0_sum0_1_low2_w;
    wire [86:0] inverse0_sum0_1_w;
    wire [34:0] inverse0_sum0_1_low1_w_d30_r;
    wire [34:0] inverse0_sum0_1_low0_w_d30_r;
    wire [34:0] inverse0_sum0_2_a0_w;
    wire [34:0] inverse0_sum0_2_b0_w;
    reg [35:0] inverse0_sum0_2_part0_r;
    wire [34:0] inverse0_sum0_2_low0_w;
    wire [34:0] inverse0_sum0_2_a1_w;
    wire [34:0] inverse0_sum0_2_b1_w;
    wire [34:0] inverse0_sum0_2_a1_w_d28_r;
    wire [34:0] inverse0_sum0_2_b1_w_d28_r;
    reg [35:0] inverse0_sum0_2_part1_r;
    wire [34:0] inverse0_sum0_2_low1_w;
    wire [16:0] inverse0_sum0_2_a2_w;
    wire [16:0] inverse0_sum0_2_b2_w;
    wire [16:0] inverse0_sum0_2_a2_w_d29_r;
    wire [16:0] inverse0_sum0_2_b2_w_d29_r;
    reg [16:0] inverse0_sum0_2_part2_r;
    wire [16:0] inverse0_sum0_2_low2_w;
    wire [86:0] inverse0_sum0_2_w;
    wire [34:0] inverse0_sum0_2_low1_w_d30_r;
    wire [34:0] inverse0_sum0_2_low0_w_d30_r;
    wire [34:0] inverse0_sum0_3_a0_w;
    wire [34:0] inverse0_sum0_3_b0_w;
    reg [35:0] inverse0_sum0_3_part0_r;
    wire [34:0] inverse0_sum0_3_low0_w;
    wire [34:0] inverse0_sum0_3_a1_w;
    wire [34:0] inverse0_sum0_3_b1_w;
    wire [34:0] inverse0_sum0_3_a1_w_d28_r;
    wire [34:0] inverse0_sum0_3_b1_w_d28_r;
    reg [35:0] inverse0_sum0_3_part1_r;
    wire [34:0] inverse0_sum0_3_low1_w;
    wire [16:0] inverse0_sum0_3_a2_w;
    wire [16:0] inverse0_sum0_3_b2_w;
    wire [16:0] inverse0_sum0_3_a2_w_d29_r;
    wire [16:0] inverse0_sum0_3_b2_w_d29_r;
    reg [16:0] inverse0_sum0_3_part2_r;
    wire [16:0] inverse0_sum0_3_low2_w;
    wire [86:0] inverse0_sum0_3_w;
    wire [34:0] inverse0_sum0_3_low1_w_d30_r;
    wire [34:0] inverse0_sum0_3_low0_w_d30_r;
    wire [34:0] inverse0_sum1_0_a0_w;
    wire [34:0] inverse0_sum1_0_b0_w;
    reg [35:0] inverse0_sum1_0_part0_r;
    wire [34:0] inverse0_sum1_0_low0_w;
    wire [34:0] inverse0_sum1_0_a1_w;
    wire [34:0] inverse0_sum1_0_b1_w;
    wire [34:0] inverse0_sum1_0_a1_w_d31_r;
    wire [34:0] inverse0_sum1_0_b1_w_d31_r;
    reg [35:0] inverse0_sum1_0_part1_r;
    wire [34:0] inverse0_sum1_0_low1_w;
    wire [16:0] inverse0_sum1_0_a2_w;
    wire [16:0] inverse0_sum1_0_b2_w;
    wire [16:0] inverse0_sum1_0_a2_w_d32_r;
    wire [16:0] inverse0_sum1_0_b2_w_d32_r;
    reg [16:0] inverse0_sum1_0_part2_r;
    wire [16:0] inverse0_sum1_0_low2_w;
    wire [86:0] inverse0_sum1_0_w;
    wire [34:0] inverse0_sum1_0_low1_w_d33_r;
    wire [34:0] inverse0_sum1_0_low0_w_d33_r;
    wire [34:0] inverse0_sum1_1_a0_w;
    wire [34:0] inverse0_sum1_1_b0_w;
    reg [35:0] inverse0_sum1_1_part0_r;
    wire [34:0] inverse0_sum1_1_low0_w;
    wire [34:0] inverse0_sum1_1_a1_w;
    wire [34:0] inverse0_sum1_1_b1_w;
    wire [34:0] inverse0_sum1_1_a1_w_d31_r;
    wire [34:0] inverse0_sum1_1_b1_w_d31_r;
    reg [35:0] inverse0_sum1_1_part1_r;
    wire [34:0] inverse0_sum1_1_low1_w;
    wire [16:0] inverse0_sum1_1_a2_w;
    wire [16:0] inverse0_sum1_1_b2_w;
    wire [16:0] inverse0_sum1_1_a2_w_d32_r;
    wire [16:0] inverse0_sum1_1_b2_w_d32_r;
    reg [16:0] inverse0_sum1_1_part2_r;
    wire [16:0] inverse0_sum1_1_low2_w;
    wire [86:0] inverse0_sum1_1_w;
    wire [34:0] inverse0_sum1_1_low1_w_d33_r;
    wire [34:0] inverse0_sum1_1_low0_w_d33_r;
    wire [34:0] inverse0_sum2_0_a0_w;
    wire [34:0] inverse0_sum2_0_b0_w;
    reg [35:0] inverse0_sum2_0_part0_r;
    wire [34:0] inverse0_sum2_0_low0_w;
    wire [34:0] inverse0_sum2_0_a1_w;
    wire [34:0] inverse0_sum2_0_b1_w;
    wire [34:0] inverse0_sum2_0_a1_w_d34_r;
    wire [34:0] inverse0_sum2_0_b1_w_d34_r;
    reg [35:0] inverse0_sum2_0_part1_r;
    wire [34:0] inverse0_sum2_0_low1_w;
    wire [16:0] inverse0_sum2_0_a2_w;
    wire [16:0] inverse0_sum2_0_b2_w;
    wire [16:0] inverse0_sum2_0_a2_w_d35_r;
    wire [16:0] inverse0_sum2_0_b2_w_d35_r;
    reg [16:0] inverse0_sum2_0_part2_r;
    wire [16:0] inverse0_sum2_0_low2_w;
    wire [86:0] inverse0_sum2_0_w;
    wire [34:0] inverse0_sum2_0_low1_w_d36_r;
    wire [34:0] inverse0_sum2_0_low0_w_d36_r;
    reg [0:0] inverse_abs0_sign_r;
    reg [86:0] inverse_abs0_invert_r;
    wire [86:0] inverse_abs0_carry_w;
    wire [34:0] inverse_abs0_a0_w;
    wire [34:0] inverse_abs0_b0_w;
    reg [35:0] inverse_abs0_part0_r;
    wire [34:0] inverse_abs0_low0_w;
    wire [34:0] inverse_abs0_a1_w;
    wire [34:0] inverse_abs0_b1_w;
    wire [34:0] inverse_abs0_a1_w_d38_r;
    wire [34:0] inverse_abs0_b1_w_d38_r;
    reg [35:0] inverse_abs0_part1_r;
    wire [34:0] inverse_abs0_low1_w;
    wire [16:0] inverse_abs0_a2_w;
    wire [16:0] inverse_abs0_b2_w;
    wire [16:0] inverse_abs0_a2_w_d39_r;
    wire [16:0] inverse_abs0_b2_w_d39_r;
    reg [16:0] inverse_abs0_part2_r;
    wire [16:0] inverse_abs0_low2_w;
    wire [86:0] inverse_abs0_w;
    wire [34:0] inverse_abs0_low1_w_d40_r;
    wire [34:0] inverse_abs0_low0_w_d40_r;
    wire [3:0] exponent_context_r_0_index1_w;
    reg [5:0] exponent_context_r_0_read1_r;
    reg [6:0] rounding_bit0_r;
    reg [6:0] rounding_shift0_r;
    wire [87:0] gradient_one0_w;
    wire [1:0] gradient_bias0_amt0_w;
    reg [87:0] gradient_bias0_0_w;
    reg [87:0] gradient_bias0_0_r;
    wire [1:0] gradient_bias0_amt1_w;
    reg [87:0] gradient_bias0_1_w;
    wire [1:0] gradient_bias0_amt1_w_d3_r;
    reg [87:0] gradient_bias0_1_r;
    wire [1:0] gradient_bias0_amt2_w;
    reg [87:0] gradient_bias0_2_w;
    wire [1:0] gradient_bias0_amt2_w_d4_r;
    reg [87:0] gradient_bias0_2_r;
    wire [0:0] gradient_bias0_amt3_w;
    reg [87:0] gradient_bias0_3_w;
    wire [0:0] gradient_bias0_amt3_w_d5_r;
    reg [87:0] gradient_bias0_3_r;
    wire [87:0] mag88_0_w;
    wire [87:0] gradient_bias0_3_r_d40_r;
    wire [34:0] gradient_round0_a0_w;
    wire [34:0] gradient_round0_b0_w;
    reg [35:0] gradient_round0_part0_r;
    wire [34:0] gradient_round0_low0_w;
    wire [34:0] gradient_round0_a1_w;
    wire [34:0] gradient_round0_b1_w;
    wire [34:0] gradient_round0_a1_w_d41_r;
    wire [34:0] gradient_round0_b1_w_d41_r;
    reg [35:0] gradient_round0_part1_r;
    wire [34:0] gradient_round0_low1_w;
    wire [17:0] gradient_round0_a2_w;
    wire [17:0] gradient_round0_b2_w;
    wire [17:0] gradient_round0_a2_w_d42_r;
    wire [17:0] gradient_round0_b2_w_d42_r;
    reg [17:0] gradient_round0_part2_r;
    wire [17:0] gradient_round0_low2_w;
    wire [87:0] gradient_round0_w;
    wire [34:0] gradient_round0_low1_w_d43_r;
    wire [34:0] gradient_round0_low0_w_d43_r;
    wire [1:0] gradient_shift0_amt0_w;
    reg [87:0] gradient_shift0_0_w;
    wire [1:0] gradient_shift0_amt0_w_d43_r;
    reg [87:0] gradient_shift0_0_r;
    wire [1:0] gradient_shift0_amt1_w;
    reg [87:0] gradient_shift0_1_w;
    wire [1:0] gradient_shift0_amt1_w_d44_r;
    reg [87:0] gradient_shift0_1_r;
    wire [1:0] gradient_shift0_amt2_w;
    reg [87:0] gradient_shift0_2_w;
    wire [1:0] gradient_shift0_amt2_w_d45_r;
    reg [87:0] gradient_shift0_2_r;
    wire [0:0] gradient_shift0_amt3_w;
    reg [87:0] unused_gradient_shift0_3_w;
    wire [0:0] gradient_shift0_amt3_w_d46_r;
    reg [55:0] gradient_shift0_3_r;
    wire [55:0] gradient56_0_w;
    wire [0:0] inverse_abs0_sign_d47_r;
    reg [55:0] gradient_signed0_invert_r;
    wire [0:0] inverse_abs0_sign_d48_r;
    wire [55:0] gradient_signed0_carry_w;
    wire [34:0] gradient_signed0_a0_w;
    wire [34:0] gradient_signed0_b0_w;
    reg [35:0] gradient_signed0_part0_r;
    wire [34:0] gradient_signed0_low0_w;
    wire [20:0] gradient_signed0_a1_w;
    wire [20:0] gradient_signed0_b1_w;
    wire [20:0] gradient_signed0_a1_w_d49_r;
    wire [20:0] gradient_signed0_b1_w_d49_r;
    reg [20:0] gradient_signed0_part1_r;
    wire [20:0] gradient_signed0_low1_w;
    wire [55:0] gradient_signed0_w;
    wire [34:0] gradient_signed0_low0_w_d50_r;
    wire [6:0] tag_0_r_d49_r;
    wire [3:0] offset_context0_r_0_index50_w;
    reg [17:0] offset_context0_r_0_read50_r;
    reg [35:0] origin_product0_pp0_0_r;
    wire [73:0] origin_product0_pp0_0_extend_w;
    wire [73:0] origin_product0_pp0_0_aligned_w;
    reg [35:0] origin_product0_pp1_0_r;
    wire [73:0] origin_product0_pp1_0_extend_w;
    wire [73:0] origin_product0_pp1_0_aligned_w;
    reg [35:0] origin_product0_pp2_0_r;
    wire [73:0] origin_product0_pp2_0_extend_w;
    wire [73:0] origin_product0_pp2_0_aligned_w;
    reg [22:0] origin_product0_pp3_0_r;
    wire [73:0] origin_product0_pp3_0_extend_w;
    wire [73:0] origin_product0_pp3_0_aligned_w;
    wire [34:0] origin_product0_sum0_0_a0_w;
    wire [34:0] origin_product0_sum0_0_b0_w;
    reg [35:0] origin_product0_sum0_0_part0_r;
    wire [34:0] origin_product0_sum0_0_low0_w;
    wire [34:0] origin_product0_sum0_0_a1_w;
    wire [34:0] origin_product0_sum0_0_b1_w;
    wire [34:0] origin_product0_sum0_0_a1_w_d52_r;
    wire [34:0] origin_product0_sum0_0_b1_w_d52_r;
    reg [35:0] origin_product0_sum0_0_part1_r;
    wire [34:0] origin_product0_sum0_0_low1_w;
    wire [3:0] origin_product0_sum0_0_a2_w;
    wire [3:0] origin_product0_sum0_0_b2_w;
    wire [3:0] origin_product0_sum0_0_a2_w_d53_r;
    wire [3:0] origin_product0_sum0_0_b2_w_d53_r;
    reg [3:0] origin_product0_sum0_0_part2_r;
    wire [3:0] origin_product0_sum0_0_low2_w;
    wire [73:0] origin_product0_sum0_0_w;
    wire [34:0] origin_product0_sum0_0_low1_w_d54_r;
    wire [34:0] origin_product0_sum0_0_low0_w_d54_r;
    wire [34:0] origin_product0_sum0_1_a0_w;
    wire [34:0] origin_product0_sum0_1_b0_w;
    reg [35:0] origin_product0_sum0_1_part0_r;
    wire [34:0] origin_product0_sum0_1_low0_w;
    wire [34:0] origin_product0_sum0_1_a1_w;
    wire [34:0] origin_product0_sum0_1_b1_w;
    wire [34:0] origin_product0_sum0_1_a1_w_d52_r;
    wire [34:0] origin_product0_sum0_1_b1_w_d52_r;
    reg [35:0] origin_product0_sum0_1_part1_r;
    wire [34:0] origin_product0_sum0_1_low1_w;
    wire [3:0] origin_product0_sum0_1_a2_w;
    wire [3:0] origin_product0_sum0_1_b2_w;
    wire [3:0] origin_product0_sum0_1_a2_w_d53_r;
    wire [3:0] origin_product0_sum0_1_b2_w_d53_r;
    reg [3:0] origin_product0_sum0_1_part2_r;
    wire [3:0] origin_product0_sum0_1_low2_w;
    wire [73:0] origin_product0_sum0_1_w;
    wire [34:0] origin_product0_sum0_1_low1_w_d54_r;
    wire [34:0] origin_product0_sum0_1_low0_w_d54_r;
    wire [34:0] origin_product0_sum1_0_a0_w;
    wire [34:0] origin_product0_sum1_0_b0_w;
    reg [35:0] origin_product0_sum1_0_part0_r;
    wire [34:0] origin_product0_sum1_0_low0_w;
    wire [34:0] origin_product0_sum1_0_a1_w;
    wire [34:0] origin_product0_sum1_0_b1_w;
    wire [34:0] origin_product0_sum1_0_a1_w_d55_r;
    wire [34:0] origin_product0_sum1_0_b1_w_d55_r;
    reg [35:0] origin_product0_sum1_0_part1_r;
    wire [34:0] origin_product0_sum1_0_low1_w;
    wire [3:0] origin_product0_sum1_0_a2_w;
    wire [3:0] origin_product0_sum1_0_b2_w;
    wire [3:0] origin_product0_sum1_0_a2_w_d56_r;
    wire [3:0] origin_product0_sum1_0_b2_w_d56_r;
    reg [3:0] origin_product0_sum1_0_part2_r;
    wire [3:0] origin_product0_sum1_0_low2_w;
    wire [73:0] origin_product0_sum1_0_w;
    wire [34:0] origin_product0_sum1_0_low1_w_d57_r;
    wire [34:0] origin_product0_sum1_0_low0_w_d57_r;
    reg [3:0] drop_gradient0_r;
    reg [0:0] gradient_abs0_sign_r;
    reg [55:0] gradient_abs0_invert_r;
    wire [55:0] gradient_abs0_carry_w;
    wire [34:0] gradient_abs0_a0_w;
    wire [34:0] gradient_abs0_b0_w;
    reg [35:0] gradient_abs0_part0_r;
    wire [34:0] gradient_abs0_low0_w;
    wire [20:0] gradient_abs0_a1_w;
    wire [20:0] gradient_abs0_b1_w;
    wire [20:0] gradient_abs0_a1_w_d52_r;
    wire [20:0] gradient_abs0_b1_w_d52_r;
    reg [20:0] gradient_abs0_part1_r;
    wire [20:0] gradient_abs0_low1_w;
    wire [55:0] gradient_abs0_w;
    wire [34:0] gradient_abs0_low0_w_d53_r;
    wire [1:0] gradient_drop0_amt0_w;
    reg [55:0] gradient_drop0_0_w;
    wire [1:0] gradient_drop0_amt0_w_d53_r;
    reg [55:0] gradient_drop0_0_r;
    wire [1:0] gradient_drop0_amt1_w;
    reg [55:0] unused_gradient_drop0_1_w;
    wire [1:0] gradient_drop0_amt1_w_d54_r;
    reg [52:0] gradient_drop0_1_r;
    wire [51:0] stored52_0_w;
    wire [51:0] stored_bit0_w;
    wire [34:0] stored_round0_a0_w;
    wire [34:0] stored_round0_b0_w;
    reg [35:0] stored_round0_part0_r;
    wire [34:0] stored_round0_low0_w;
    wire [16:0] stored_round0_a1_w;
    wire [16:0] stored_round0_b1_w;
    wire [16:0] stored_round0_a1_w_d56_r;
    wire [16:0] stored_round0_b1_w_d56_r;
    reg [16:0] stored_round0_part1_r;
    wire [16:0] stored_round0_low1_w;
    wire [51:0] stored_round0_w;
    wire [34:0] stored_round0_low0_w_d57_r;
    wire [0:0] gradient_abs0_sign_d57_r;
    reg [51:0] stored_signed0_invert_r;
    wire [0:0] gradient_abs0_sign_d58_r;
    wire [51:0] stored_signed0_carry_w;
    wire [34:0] stored_signed0_a0_w;
    wire [34:0] stored_signed0_b0_w;
    reg [35:0] stored_signed0_part0_r;
    wire [34:0] stored_signed0_low0_w;
    wire [16:0] stored_signed0_a1_w;
    wire [16:0] stored_signed0_b1_w;
    wire [16:0] stored_signed0_a1_w_d59_r;
    wire [16:0] stored_signed0_b1_w_d59_r;
    reg [16:0] stored_signed0_part1_r;
    wire [16:0] stored_signed0_low1_w;
    wire [51:0] stored_signed0_w;
    wire [34:0] stored_signed0_low0_w_d60_r;
    wire [3:0] delta_context2_r_0_index20_w;
    reg [17:0] delta_context2_r_0_read20_r;
    reg [35:0] product1_0_pp0_0_r;
    wire [51:0] product1_0_pp0_0_extend_w;
    wire [51:0] product1_0_pp0_0_aligned_w;
    reg [34:0] product1_0_pp1_0_r;
    wire [51:0] product1_0_pp1_0_extend_w;
    wire [51:0] product1_0_pp1_0_aligned_w;
    wire [34:0] product1_0_sum0_0_a0_w;
    wire [34:0] product1_0_sum0_0_b0_w;
    reg [35:0] product1_0_sum0_0_part0_r;
    wire [34:0] product1_0_sum0_0_low0_w;
    wire [16:0] product1_0_sum0_0_a1_w;
    wire [16:0] product1_0_sum0_0_b1_w;
    wire [16:0] product1_0_sum0_0_a1_w_d22_r;
    wire [16:0] product1_0_sum0_0_b1_w_d22_r;
    reg [16:0] product1_0_sum0_0_part1_r;
    wire [16:0] product1_0_sum0_0_low1_w;
    wire [51:0] product1_0_sum0_0_w;
    wire [34:0] product1_0_sum0_0_low0_w_d23_r;
    wire [3:0] delta_context3_r_0_index20_w;
    reg [17:0] delta_context3_r_0_read20_r;
    reg [35:0] product1_1_pp0_0_r;
    wire [51:0] product1_1_pp0_0_extend_w;
    wire [51:0] product1_1_pp0_0_aligned_w;
    reg [34:0] product1_1_pp1_0_r;
    wire [51:0] product1_1_pp1_0_extend_w;
    wire [51:0] product1_1_pp1_0_aligned_w;
    wire [34:0] product1_1_sum0_0_a0_w;
    wire [34:0] product1_1_sum0_0_b0_w;
    reg [35:0] product1_1_sum0_0_part0_r;
    wire [34:0] product1_1_sum0_0_low0_w;
    wire [16:0] product1_1_sum0_0_a1_w;
    wire [16:0] product1_1_sum0_0_b1_w;
    wire [16:0] product1_1_sum0_0_a1_w_d22_r;
    wire [16:0] product1_1_sum0_0_b1_w_d22_r;
    reg [16:0] product1_1_sum0_0_part1_r;
    wire [16:0] product1_1_sum0_0_low1_w;
    wire [51:0] product1_1_sum0_0_w;
    wire [34:0] product1_1_sum0_0_low0_w_d23_r;
    wire [55:0] product_ext1_0_w;
    wire [55:0] product_ext1_1_w;
    wire [34:0] numerator1_a0_w;
    wire [34:0] numerator1_b0_w;
    reg [35:0] numerator1_part0_r;
    wire [34:0] numerator1_low0_w;
    wire [20:0] numerator1_a1_w;
    wire [20:0] numerator1_b1_w;
    wire [20:0] numerator1_a1_w_d24_r;
    wire [20:0] numerator1_b1_w_d24_r;
    reg [20:0] numerator1_part1_r;
    wire [20:0] numerator1_low1_w;
    wire [55:0] numerator1_w;
    wire [34:0] numerator1_low0_w_d25_r;
    reg [55:0] numerator_shift1_r;
    reg [35:0] inverse1_pp0_0_r;
    wire [86:0] inverse1_pp0_0_extend_w;
    wire [86:0] inverse1_pp0_0_aligned_w;
    reg [32:0] inverse1_pp0_1_r;
    wire [86:0] inverse1_pp0_1_extend_w;
    wire [86:0] inverse1_pp0_1_aligned_w;
    reg [35:0] inverse1_pp1_0_r;
    wire [86:0] inverse1_pp1_0_extend_w;
    wire [86:0] inverse1_pp1_0_aligned_w;
    reg [32:0] inverse1_pp1_1_r;
    wire [86:0] inverse1_pp1_1_extend_w;
    wire [86:0] inverse1_pp1_1_aligned_w;
    reg [35:0] inverse1_pp2_0_r;
    wire [86:0] inverse1_pp2_0_extend_w;
    wire [86:0] inverse1_pp2_0_aligned_w;
    reg [32:0] inverse1_pp2_1_r;
    wire [86:0] inverse1_pp2_1_extend_w;
    wire [86:0] inverse1_pp2_1_aligned_w;
    reg [22:0] inverse1_pp3_0_r;
    wire [86:0] inverse1_pp3_0_extend_w;
    wire [86:0] inverse1_pp3_0_aligned_w;
    reg [19:0] inverse1_pp3_1_r;
    wire [86:0] inverse1_pp3_1_extend_w;
    wire [86:0] inverse1_pp3_1_aligned_w;
    wire [34:0] inverse1_sum0_0_a0_w;
    wire [34:0] inverse1_sum0_0_b0_w;
    reg [35:0] inverse1_sum0_0_part0_r;
    wire [34:0] inverse1_sum0_0_low0_w;
    wire [34:0] inverse1_sum0_0_a1_w;
    wire [34:0] inverse1_sum0_0_b1_w;
    wire [34:0] inverse1_sum0_0_a1_w_d28_r;
    wire [34:0] inverse1_sum0_0_b1_w_d28_r;
    reg [35:0] inverse1_sum0_0_part1_r;
    wire [34:0] inverse1_sum0_0_low1_w;
    wire [16:0] inverse1_sum0_0_a2_w;
    wire [16:0] inverse1_sum0_0_b2_w;
    wire [16:0] inverse1_sum0_0_a2_w_d29_r;
    wire [16:0] inverse1_sum0_0_b2_w_d29_r;
    reg [16:0] inverse1_sum0_0_part2_r;
    wire [16:0] inverse1_sum0_0_low2_w;
    wire [86:0] inverse1_sum0_0_w;
    wire [34:0] inverse1_sum0_0_low1_w_d30_r;
    wire [34:0] inverse1_sum0_0_low0_w_d30_r;
    wire [34:0] inverse1_sum0_1_a0_w;
    wire [34:0] inverse1_sum0_1_b0_w;
    reg [35:0] inverse1_sum0_1_part0_r;
    wire [34:0] inverse1_sum0_1_low0_w;
    wire [34:0] inverse1_sum0_1_a1_w;
    wire [34:0] inverse1_sum0_1_b1_w;
    wire [34:0] inverse1_sum0_1_a1_w_d28_r;
    wire [34:0] inverse1_sum0_1_b1_w_d28_r;
    reg [35:0] inverse1_sum0_1_part1_r;
    wire [34:0] inverse1_sum0_1_low1_w;
    wire [16:0] inverse1_sum0_1_a2_w;
    wire [16:0] inverse1_sum0_1_b2_w;
    wire [16:0] inverse1_sum0_1_a2_w_d29_r;
    wire [16:0] inverse1_sum0_1_b2_w_d29_r;
    reg [16:0] inverse1_sum0_1_part2_r;
    wire [16:0] inverse1_sum0_1_low2_w;
    wire [86:0] inverse1_sum0_1_w;
    wire [34:0] inverse1_sum0_1_low1_w_d30_r;
    wire [34:0] inverse1_sum0_1_low0_w_d30_r;
    wire [34:0] inverse1_sum0_2_a0_w;
    wire [34:0] inverse1_sum0_2_b0_w;
    reg [35:0] inverse1_sum0_2_part0_r;
    wire [34:0] inverse1_sum0_2_low0_w;
    wire [34:0] inverse1_sum0_2_a1_w;
    wire [34:0] inverse1_sum0_2_b1_w;
    wire [34:0] inverse1_sum0_2_a1_w_d28_r;
    wire [34:0] inverse1_sum0_2_b1_w_d28_r;
    reg [35:0] inverse1_sum0_2_part1_r;
    wire [34:0] inverse1_sum0_2_low1_w;
    wire [16:0] inverse1_sum0_2_a2_w;
    wire [16:0] inverse1_sum0_2_b2_w;
    wire [16:0] inverse1_sum0_2_a2_w_d29_r;
    wire [16:0] inverse1_sum0_2_b2_w_d29_r;
    reg [16:0] inverse1_sum0_2_part2_r;
    wire [16:0] inverse1_sum0_2_low2_w;
    wire [86:0] inverse1_sum0_2_w;
    wire [34:0] inverse1_sum0_2_low1_w_d30_r;
    wire [34:0] inverse1_sum0_2_low0_w_d30_r;
    wire [34:0] inverse1_sum0_3_a0_w;
    wire [34:0] inverse1_sum0_3_b0_w;
    reg [35:0] inverse1_sum0_3_part0_r;
    wire [34:0] inverse1_sum0_3_low0_w;
    wire [34:0] inverse1_sum0_3_a1_w;
    wire [34:0] inverse1_sum0_3_b1_w;
    wire [34:0] inverse1_sum0_3_a1_w_d28_r;
    wire [34:0] inverse1_sum0_3_b1_w_d28_r;
    reg [35:0] inverse1_sum0_3_part1_r;
    wire [34:0] inverse1_sum0_3_low1_w;
    wire [16:0] inverse1_sum0_3_a2_w;
    wire [16:0] inverse1_sum0_3_b2_w;
    wire [16:0] inverse1_sum0_3_a2_w_d29_r;
    wire [16:0] inverse1_sum0_3_b2_w_d29_r;
    reg [16:0] inverse1_sum0_3_part2_r;
    wire [16:0] inverse1_sum0_3_low2_w;
    wire [86:0] inverse1_sum0_3_w;
    wire [34:0] inverse1_sum0_3_low1_w_d30_r;
    wire [34:0] inverse1_sum0_3_low0_w_d30_r;
    wire [34:0] inverse1_sum1_0_a0_w;
    wire [34:0] inverse1_sum1_0_b0_w;
    reg [35:0] inverse1_sum1_0_part0_r;
    wire [34:0] inverse1_sum1_0_low0_w;
    wire [34:0] inverse1_sum1_0_a1_w;
    wire [34:0] inverse1_sum1_0_b1_w;
    wire [34:0] inverse1_sum1_0_a1_w_d31_r;
    wire [34:0] inverse1_sum1_0_b1_w_d31_r;
    reg [35:0] inverse1_sum1_0_part1_r;
    wire [34:0] inverse1_sum1_0_low1_w;
    wire [16:0] inverse1_sum1_0_a2_w;
    wire [16:0] inverse1_sum1_0_b2_w;
    wire [16:0] inverse1_sum1_0_a2_w_d32_r;
    wire [16:0] inverse1_sum1_0_b2_w_d32_r;
    reg [16:0] inverse1_sum1_0_part2_r;
    wire [16:0] inverse1_sum1_0_low2_w;
    wire [86:0] inverse1_sum1_0_w;
    wire [34:0] inverse1_sum1_0_low1_w_d33_r;
    wire [34:0] inverse1_sum1_0_low0_w_d33_r;
    wire [34:0] inverse1_sum1_1_a0_w;
    wire [34:0] inverse1_sum1_1_b0_w;
    reg [35:0] inverse1_sum1_1_part0_r;
    wire [34:0] inverse1_sum1_1_low0_w;
    wire [34:0] inverse1_sum1_1_a1_w;
    wire [34:0] inverse1_sum1_1_b1_w;
    wire [34:0] inverse1_sum1_1_a1_w_d31_r;
    wire [34:0] inverse1_sum1_1_b1_w_d31_r;
    reg [35:0] inverse1_sum1_1_part1_r;
    wire [34:0] inverse1_sum1_1_low1_w;
    wire [16:0] inverse1_sum1_1_a2_w;
    wire [16:0] inverse1_sum1_1_b2_w;
    wire [16:0] inverse1_sum1_1_a2_w_d32_r;
    wire [16:0] inverse1_sum1_1_b2_w_d32_r;
    reg [16:0] inverse1_sum1_1_part2_r;
    wire [16:0] inverse1_sum1_1_low2_w;
    wire [86:0] inverse1_sum1_1_w;
    wire [34:0] inverse1_sum1_1_low1_w_d33_r;
    wire [34:0] inverse1_sum1_1_low0_w_d33_r;
    wire [34:0] inverse1_sum2_0_a0_w;
    wire [34:0] inverse1_sum2_0_b0_w;
    reg [35:0] inverse1_sum2_0_part0_r;
    wire [34:0] inverse1_sum2_0_low0_w;
    wire [34:0] inverse1_sum2_0_a1_w;
    wire [34:0] inverse1_sum2_0_b1_w;
    wire [34:0] inverse1_sum2_0_a1_w_d34_r;
    wire [34:0] inverse1_sum2_0_b1_w_d34_r;
    reg [35:0] inverse1_sum2_0_part1_r;
    wire [34:0] inverse1_sum2_0_low1_w;
    wire [16:0] inverse1_sum2_0_a2_w;
    wire [16:0] inverse1_sum2_0_b2_w;
    wire [16:0] inverse1_sum2_0_a2_w_d35_r;
    wire [16:0] inverse1_sum2_0_b2_w_d35_r;
    reg [16:0] inverse1_sum2_0_part2_r;
    wire [16:0] inverse1_sum2_0_low2_w;
    wire [86:0] inverse1_sum2_0_w;
    wire [34:0] inverse1_sum2_0_low1_w_d36_r;
    wire [34:0] inverse1_sum2_0_low0_w_d36_r;
    reg [0:0] inverse_abs1_sign_r;
    reg [86:0] inverse_abs1_invert_r;
    wire [86:0] inverse_abs1_carry_w;
    wire [34:0] inverse_abs1_a0_w;
    wire [34:0] inverse_abs1_b0_w;
    reg [35:0] inverse_abs1_part0_r;
    wire [34:0] inverse_abs1_low0_w;
    wire [34:0] inverse_abs1_a1_w;
    wire [34:0] inverse_abs1_b1_w;
    wire [34:0] inverse_abs1_a1_w_d38_r;
    wire [34:0] inverse_abs1_b1_w_d38_r;
    reg [35:0] inverse_abs1_part1_r;
    wire [34:0] inverse_abs1_low1_w;
    wire [16:0] inverse_abs1_a2_w;
    wire [16:0] inverse_abs1_b2_w;
    wire [16:0] inverse_abs1_a2_w_d39_r;
    wire [16:0] inverse_abs1_b2_w_d39_r;
    reg [16:0] inverse_abs1_part2_r;
    wire [16:0] inverse_abs1_low2_w;
    wire [86:0] inverse_abs1_w;
    wire [34:0] inverse_abs1_low1_w_d40_r;
    wire [34:0] inverse_abs1_low0_w_d40_r;
    reg [6:0] rounding_bit1_r;
    reg [6:0] rounding_shift1_r;
    wire [87:0] gradient_one1_w;
    wire [1:0] gradient_bias1_amt0_w;
    reg [87:0] gradient_bias1_0_w;
    reg [87:0] gradient_bias1_0_r;
    wire [1:0] gradient_bias1_amt1_w;
    reg [87:0] gradient_bias1_1_w;
    wire [1:0] gradient_bias1_amt1_w_d3_r;
    reg [87:0] gradient_bias1_1_r;
    wire [1:0] gradient_bias1_amt2_w;
    reg [87:0] gradient_bias1_2_w;
    wire [1:0] gradient_bias1_amt2_w_d4_r;
    reg [87:0] gradient_bias1_2_r;
    wire [0:0] gradient_bias1_amt3_w;
    reg [87:0] gradient_bias1_3_w;
    wire [0:0] gradient_bias1_amt3_w_d5_r;
    reg [87:0] gradient_bias1_3_r;
    wire [87:0] mag88_1_w;
    wire [87:0] gradient_bias1_3_r_d40_r;
    wire [34:0] gradient_round1_a0_w;
    wire [34:0] gradient_round1_b0_w;
    reg [35:0] gradient_round1_part0_r;
    wire [34:0] gradient_round1_low0_w;
    wire [34:0] gradient_round1_a1_w;
    wire [34:0] gradient_round1_b1_w;
    wire [34:0] gradient_round1_a1_w_d41_r;
    wire [34:0] gradient_round1_b1_w_d41_r;
    reg [35:0] gradient_round1_part1_r;
    wire [34:0] gradient_round1_low1_w;
    wire [17:0] gradient_round1_a2_w;
    wire [17:0] gradient_round1_b2_w;
    wire [17:0] gradient_round1_a2_w_d42_r;
    wire [17:0] gradient_round1_b2_w_d42_r;
    reg [17:0] gradient_round1_part2_r;
    wire [17:0] gradient_round1_low2_w;
    wire [87:0] gradient_round1_w;
    wire [34:0] gradient_round1_low1_w_d43_r;
    wire [34:0] gradient_round1_low0_w_d43_r;
    wire [1:0] gradient_shift1_amt0_w;
    reg [87:0] gradient_shift1_0_w;
    wire [1:0] gradient_shift1_amt0_w_d43_r;
    reg [87:0] gradient_shift1_0_r;
    wire [1:0] gradient_shift1_amt1_w;
    reg [87:0] gradient_shift1_1_w;
    wire [1:0] gradient_shift1_amt1_w_d44_r;
    reg [87:0] gradient_shift1_1_r;
    wire [1:0] gradient_shift1_amt2_w;
    reg [87:0] gradient_shift1_2_w;
    wire [1:0] gradient_shift1_amt2_w_d45_r;
    reg [87:0] gradient_shift1_2_r;
    wire [0:0] gradient_shift1_amt3_w;
    reg [87:0] unused_gradient_shift1_3_w;
    wire [0:0] gradient_shift1_amt3_w_d46_r;
    reg [55:0] gradient_shift1_3_r;
    wire [55:0] gradient56_1_w;
    wire [0:0] inverse_abs1_sign_d47_r;
    reg [55:0] gradient_signed1_invert_r;
    wire [0:0] inverse_abs1_sign_d48_r;
    wire [55:0] gradient_signed1_carry_w;
    wire [34:0] gradient_signed1_a0_w;
    wire [34:0] gradient_signed1_b0_w;
    reg [35:0] gradient_signed1_part0_r;
    wire [34:0] gradient_signed1_low0_w;
    wire [20:0] gradient_signed1_a1_w;
    wire [20:0] gradient_signed1_b1_w;
    wire [20:0] gradient_signed1_a1_w_d49_r;
    wire [20:0] gradient_signed1_b1_w_d49_r;
    reg [20:0] gradient_signed1_part1_r;
    wire [20:0] gradient_signed1_low1_w;
    wire [55:0] gradient_signed1_w;
    wire [34:0] gradient_signed1_low0_w_d50_r;
    wire [3:0] offset_context1_r_0_index50_w;
    reg [17:0] offset_context1_r_0_read50_r;
    reg [35:0] origin_product1_pp0_0_r;
    wire [73:0] origin_product1_pp0_0_extend_w;
    wire [73:0] origin_product1_pp0_0_aligned_w;
    reg [35:0] origin_product1_pp1_0_r;
    wire [73:0] origin_product1_pp1_0_extend_w;
    wire [73:0] origin_product1_pp1_0_aligned_w;
    reg [35:0] origin_product1_pp2_0_r;
    wire [73:0] origin_product1_pp2_0_extend_w;
    wire [73:0] origin_product1_pp2_0_aligned_w;
    reg [22:0] origin_product1_pp3_0_r;
    wire [73:0] origin_product1_pp3_0_extend_w;
    wire [73:0] origin_product1_pp3_0_aligned_w;
    wire [34:0] origin_product1_sum0_0_a0_w;
    wire [34:0] origin_product1_sum0_0_b0_w;
    reg [35:0] origin_product1_sum0_0_part0_r;
    wire [34:0] origin_product1_sum0_0_low0_w;
    wire [34:0] origin_product1_sum0_0_a1_w;
    wire [34:0] origin_product1_sum0_0_b1_w;
    wire [34:0] origin_product1_sum0_0_a1_w_d52_r;
    wire [34:0] origin_product1_sum0_0_b1_w_d52_r;
    reg [35:0] origin_product1_sum0_0_part1_r;
    wire [34:0] origin_product1_sum0_0_low1_w;
    wire [3:0] origin_product1_sum0_0_a2_w;
    wire [3:0] origin_product1_sum0_0_b2_w;
    wire [3:0] origin_product1_sum0_0_a2_w_d53_r;
    wire [3:0] origin_product1_sum0_0_b2_w_d53_r;
    reg [3:0] origin_product1_sum0_0_part2_r;
    wire [3:0] origin_product1_sum0_0_low2_w;
    wire [73:0] origin_product1_sum0_0_w;
    wire [34:0] origin_product1_sum0_0_low1_w_d54_r;
    wire [34:0] origin_product1_sum0_0_low0_w_d54_r;
    wire [34:0] origin_product1_sum0_1_a0_w;
    wire [34:0] origin_product1_sum0_1_b0_w;
    reg [35:0] origin_product1_sum0_1_part0_r;
    wire [34:0] origin_product1_sum0_1_low0_w;
    wire [34:0] origin_product1_sum0_1_a1_w;
    wire [34:0] origin_product1_sum0_1_b1_w;
    wire [34:0] origin_product1_sum0_1_a1_w_d52_r;
    wire [34:0] origin_product1_sum0_1_b1_w_d52_r;
    reg [35:0] origin_product1_sum0_1_part1_r;
    wire [34:0] origin_product1_sum0_1_low1_w;
    wire [3:0] origin_product1_sum0_1_a2_w;
    wire [3:0] origin_product1_sum0_1_b2_w;
    wire [3:0] origin_product1_sum0_1_a2_w_d53_r;
    wire [3:0] origin_product1_sum0_1_b2_w_d53_r;
    reg [3:0] origin_product1_sum0_1_part2_r;
    wire [3:0] origin_product1_sum0_1_low2_w;
    wire [73:0] origin_product1_sum0_1_w;
    wire [34:0] origin_product1_sum0_1_low1_w_d54_r;
    wire [34:0] origin_product1_sum0_1_low0_w_d54_r;
    wire [34:0] origin_product1_sum1_0_a0_w;
    wire [34:0] origin_product1_sum1_0_b0_w;
    reg [35:0] origin_product1_sum1_0_part0_r;
    wire [34:0] origin_product1_sum1_0_low0_w;
    wire [34:0] origin_product1_sum1_0_a1_w;
    wire [34:0] origin_product1_sum1_0_b1_w;
    wire [34:0] origin_product1_sum1_0_a1_w_d55_r;
    wire [34:0] origin_product1_sum1_0_b1_w_d55_r;
    reg [35:0] origin_product1_sum1_0_part1_r;
    wire [34:0] origin_product1_sum1_0_low1_w;
    wire [3:0] origin_product1_sum1_0_a2_w;
    wire [3:0] origin_product1_sum1_0_b2_w;
    wire [3:0] origin_product1_sum1_0_a2_w_d56_r;
    wire [3:0] origin_product1_sum1_0_b2_w_d56_r;
    reg [3:0] origin_product1_sum1_0_part2_r;
    wire [3:0] origin_product1_sum1_0_low2_w;
    wire [73:0] origin_product1_sum1_0_w;
    wire [34:0] origin_product1_sum1_0_low1_w_d57_r;
    wire [34:0] origin_product1_sum1_0_low0_w_d57_r;
    reg [3:0] drop_gradient1_r;
    reg [0:0] gradient_abs1_sign_r;
    reg [55:0] gradient_abs1_invert_r;
    wire [55:0] gradient_abs1_carry_w;
    wire [34:0] gradient_abs1_a0_w;
    wire [34:0] gradient_abs1_b0_w;
    reg [35:0] gradient_abs1_part0_r;
    wire [34:0] gradient_abs1_low0_w;
    wire [20:0] gradient_abs1_a1_w;
    wire [20:0] gradient_abs1_b1_w;
    wire [20:0] gradient_abs1_a1_w_d52_r;
    wire [20:0] gradient_abs1_b1_w_d52_r;
    reg [20:0] gradient_abs1_part1_r;
    wire [20:0] gradient_abs1_low1_w;
    wire [55:0] gradient_abs1_w;
    wire [34:0] gradient_abs1_low0_w_d53_r;
    wire [1:0] gradient_drop1_amt0_w;
    reg [55:0] gradient_drop1_0_w;
    wire [1:0] gradient_drop1_amt0_w_d53_r;
    reg [55:0] gradient_drop1_0_r;
    wire [1:0] gradient_drop1_amt1_w;
    reg [55:0] unused_gradient_drop1_1_w;
    wire [1:0] gradient_drop1_amt1_w_d54_r;
    reg [52:0] gradient_drop1_1_r;
    wire [51:0] stored52_1_w;
    wire [51:0] stored_bit1_w;
    wire [34:0] stored_round1_a0_w;
    wire [34:0] stored_round1_b0_w;
    reg [35:0] stored_round1_part0_r;
    wire [34:0] stored_round1_low0_w;
    wire [16:0] stored_round1_a1_w;
    wire [16:0] stored_round1_b1_w;
    wire [16:0] stored_round1_a1_w_d56_r;
    wire [16:0] stored_round1_b1_w_d56_r;
    reg [16:0] stored_round1_part1_r;
    wire [16:0] stored_round1_low1_w;
    wire [51:0] stored_round1_w;
    wire [34:0] stored_round1_low0_w_d57_r;
    wire [0:0] gradient_abs1_sign_d57_r;
    reg [51:0] stored_signed1_invert_r;
    wire [0:0] gradient_abs1_sign_d58_r;
    wire [51:0] stored_signed1_carry_w;
    wire [34:0] stored_signed1_a0_w;
    wire [34:0] stored_signed1_b0_w;
    reg [35:0] stored_signed1_part0_r;
    wire [34:0] stored_signed1_low0_w;
    wire [16:0] stored_signed1_a1_w;
    wire [16:0] stored_signed1_b1_w;
    wire [16:0] stored_signed1_a1_w_d59_r;
    wire [16:0] stored_signed1_b1_w_d59_r;
    reg [16:0] stored_signed1_part1_r;
    wire [16:0] stored_signed1_low1_w;
    wire [51:0] stored_signed1_w;
    wire [34:0] stored_signed1_low0_w_d60_r;
    wire [74:0] origin_ext0_w;
    wire [74:0] origin_ext1_w;
    wire [34:0] origin_sum_a0_w;
    wire [34:0] origin_sum_b0_w;
    reg [35:0] origin_sum_part0_r;
    wire [34:0] origin_sum_low0_w;
    wire [34:0] origin_sum_a1_w;
    wire [34:0] origin_sum_b1_w;
    wire [34:0] origin_sum_a1_w_d58_r;
    wire [34:0] origin_sum_b1_w_d58_r;
    reg [35:0] origin_sum_part1_r;
    wire [34:0] origin_sum_low1_w;
    wire [4:0] origin_sum_a2_w;
    wire [4:0] origin_sum_b2_w;
    wire [4:0] origin_sum_a2_w_d59_r;
    wire [4:0] origin_sum_b2_w_d59_r;
    reg [4:0] origin_sum_part2_r;
    wire [4:0] origin_sum_low2_w;
    wire [74:0] origin_sum_w;
    wire [34:0] origin_sum_low1_w_d60_r;
    wire [34:0] origin_sum_low0_w_d60_r;
    reg [0:0] origin_absolute_sign_r;
    reg [74:0] origin_absolute_invert_r;
    wire [74:0] origin_absolute_carry_w;
    wire [34:0] origin_absolute_a0_w;
    wire [34:0] origin_absolute_b0_w;
    reg [35:0] origin_absolute_part0_r;
    wire [34:0] origin_absolute_low0_w;
    wire [34:0] origin_absolute_a1_w;
    wire [34:0] origin_absolute_b1_w;
    wire [34:0] origin_absolute_a1_w_d62_r;
    wire [34:0] origin_absolute_b1_w_d62_r;
    reg [35:0] origin_absolute_part1_r;
    wire [34:0] origin_absolute_low1_w;
    wire [4:0] origin_absolute_a2_w;
    wire [4:0] origin_absolute_b2_w;
    wire [4:0] origin_absolute_a2_w_d63_r;
    wire [4:0] origin_absolute_b2_w_d63_r;
    reg [4:0] origin_absolute_part2_r;
    wire [4:0] origin_absolute_low2_w;
    wire [74:0] origin_absolute_w;
    wire [34:0] origin_absolute_low1_w_d64_r;
    wire [34:0] origin_absolute_low0_w_d64_r;
    wire [74:0] origin_eight_w;
    wire [34:0] origin_round_a0_w;
    wire [34:0] origin_round_b0_w;
    reg [35:0] origin_round_part0_r;
    wire [34:0] origin_round_low0_w;
    wire [34:0] origin_round_a1_w;
    wire [34:0] origin_round_b1_w;
    wire [34:0] origin_round_a1_w_d65_r;
    wire [34:0] origin_round_b1_w_d65_r;
    reg [35:0] origin_round_part1_r;
    wire [34:0] origin_round_low1_w;
    wire [4:0] origin_round_a2_w;
    wire [4:0] origin_round_b2_w;
    wire [4:0] origin_round_a2_w_d66_r;
    wire [4:0] origin_round_b2_w_d66_r;
    reg [4:0] origin_round_part2_r;
    wire [4:0] origin_round_low2_w;
    wire [74:0] origin_round_w;
    wire [34:0] origin_round_low1_w_d67_r;
    wire [34:0] origin_round_low0_w_d67_r;
    reg [74:0] origin_shift_r;
    wire [0:0] origin_absolute_sign_d68_r;
    reg [74:0] origin_signed_invert_r;
    wire [0:0] origin_absolute_sign_d69_r;
    wire [74:0] origin_signed_carry_w;
    wire [34:0] origin_signed_a0_w;
    wire [34:0] origin_signed_b0_w;
    reg [35:0] origin_signed_part0_r;
    wire [34:0] origin_signed_low0_w;
    wire [34:0] origin_signed_a1_w;
    wire [34:0] origin_signed_b1_w;
    wire [34:0] origin_signed_a1_w_d70_r;
    wire [34:0] origin_signed_b1_w_d70_r;
    reg [35:0] origin_signed_part1_r;
    wire [34:0] origin_signed_low1_w;
    wire [4:0] origin_signed_a2_w;
    wire [4:0] origin_signed_b2_w;
    wire [4:0] origin_signed_a2_w_d71_r;
    wire [4:0] origin_signed_b2_w_d71_r;
    reg [4:0] origin_signed_part2_r;
    wire [4:0] origin_signed_low2_w;
    wire [74:0] unused_origin_signed_w;
    wire [34:0] origin_signed_low1_w_d72_r;
    wire [34:0] origin_signed_low0_w_d72_r;
    wire [69:0] start_base_w;
    wire [69:0] origin70_w;
    wire [69:0] start_base_w_d72_r;
    wire [34:0] start_sum_a0_w;
    wire [34:0] start_sum_b0_w;
    reg [35:0] start_sum_part0_r;
    wire [34:0] start_sum_low0_w;
    wire [34:0] start_sum_a1_w;
    wire [34:0] start_sum_b1_w;
    wire [34:0] start_sum_a1_w_d73_r;
    wire [34:0] start_sum_b1_w_d73_r;
    reg [34:0] start_sum_part1_r;
    wire [34:0] start_sum_low1_w;
    wire [69:0] start_sum_w;
    wire [34:0] start_sum_low0_w_d74_r;
    reg [0:0] start_absolute_sign_r;
    reg [69:0] start_absolute_invert_r;
    wire [69:0] start_absolute_carry_w;
    wire [34:0] start_absolute_a0_w;
    wire [34:0] start_absolute_b0_w;
    reg [35:0] start_absolute_part0_r;
    wire [34:0] start_absolute_low0_w;
    wire [34:0] start_absolute_a1_w;
    wire [34:0] start_absolute_b1_w;
    wire [34:0] start_absolute_a1_w_d76_r;
    wire [34:0] start_absolute_b1_w_d76_r;
    reg [34:0] start_absolute_part1_r;
    wire [34:0] start_absolute_low1_w;
    wire [69:0] start_absolute_w;
    wire [34:0] start_absolute_low0_w_d77_r;
    reg [3:0] drop_start_r;
    wire [1:0] start_drop_amt0_w;
    reg [69:0] start_drop_0_w;
    wire [1:0] start_drop_amt0_w_d77_r;
    reg [69:0] start_drop_0_r;
    wire [1:0] start_drop_amt1_w;
    reg [69:0] unused_start_drop_1_w;
    wire [1:0] start_drop_amt1_w_d78_r;
    reg [66:0] start_drop_1_r;
    wire [65:0] start66_w;
    wire [65:0] start_bit_w;
    wire [34:0] start_round_a0_w;
    wire [34:0] start_round_b0_w;
    reg [35:0] start_round_part0_r;
    wire [34:0] start_round_low0_w;
    wire [30:0] start_round_a1_w;
    wire [30:0] start_round_b1_w;
    wire [30:0] start_round_a1_w_d80_r;
    wire [30:0] start_round_b1_w_d80_r;
    reg [30:0] start_round_part1_r;
    wire [30:0] start_round_low1_w;
    wire [65:0] start_round_w;
    wire [34:0] start_round_low0_w_d81_r;
    wire [0:0] start_absolute_sign_d81_r;
    reg [65:0] start_signed_invert_r;
    wire [0:0] start_absolute_sign_d82_r;
    wire [65:0] start_signed_carry_w;
    wire [34:0] start_signed_a0_w;
    wire [34:0] start_signed_b0_w;
    reg [35:0] start_signed_part0_r;
    wire [34:0] start_signed_low0_w;
    wire [30:0] start_signed_a1_w;
    wire [30:0] start_signed_b1_w;
    wire [30:0] start_signed_a1_w_d83_r;
    wire [30:0] start_signed_b1_w_d83_r;
    reg [30:0] start_signed_part1_r;
    wire [30:0] start_signed_low1_w;
    wire [65:0] start_signed_w;
    wire [34:0] start_signed_low0_w_d84_r;
    wire [51:0] stored_signed1_w_d84_r;
    wire [51:0] stored_signed0_w_d84_r;
    wire [9:0] h_d84_r;
    wire [6:0] tag_0_r_d84_r;
    reg [50:0] vertex0_w_delay1_r;
    reg [50:0] vertex1_w_delay1_r;
    reg [50:0] vertex2_w_delay1_r;
    reg [50:0] vertex2_w_delay2_r;
    reg [50:0] vertex2_w_delay3_r;
    reg [50:0] maximum01_select_delay3_r;
    reg [12:0] nonzero_groups_delay6_r;
    reg [6:0] tag_0_r_delay1_r;
    reg [6:0] tag_0_r_delay2_r;
    reg [6:0] tag_0_r_delay3_r;
    reg [6:0] tag_0_r_delay4_r;
    reg [6:0] tag_0_r_delay5_r;
    reg [6:0] tag_0_r_delay6_r;
    reg [6:0] tag_0_r_delay7_r;
    reg [6:0] tag_0_r_delay8_r;
    reg [6:0] tag_0_r_delay9_r;
    reg [6:0] tag_0_r_delay10_r;
    reg [6:0] tag_0_r_delay11_r;
    reg [6:0] tag_0_r_delay12_r;
    reg [6:0] tag_0_r_delay13_r;
    reg [6:0] tag_0_r_delay14_r;
    reg [6:0] tag_0_r_delay15_r;
    reg [6:0] tag_0_r_delay16_r;
    reg [6:0] tag_0_r_delay17_r;
    reg [6:0] tag_0_r_delay18_r;
    reg [6:0] tag_0_r_delay19_r;
    reg [6:0] tag_0_r_delay20_r;
    reg [6:0] tag_0_r_delay21_r;
    reg [6:0] tag_0_r_delay22_r;
    reg [6:0] tag_0_r_delay23_r;
    reg [6:0] tag_0_r_delay24_r;
    reg [6:0] tag_0_r_delay25_r;
    reg [6:0] tag_0_r_delay26_r;
    reg [6:0] tag_0_r_delay27_r;
    reg [6:0] tag_0_r_delay28_r;
    reg [6:0] tag_0_r_delay29_r;
    reg [6:0] tag_0_r_delay30_r;
    reg [6:0] tag_0_r_delay31_r;
    reg [6:0] tag_0_r_delay32_r;
    reg [6:0] tag_0_r_delay33_r;
    reg [6:0] tag_0_r_delay34_r;
    reg [6:0] tag_0_r_delay35_r;
    reg [6:0] tag_0_r_delay36_r;
    reg [6:0] tag_0_r_delay37_r;
    reg [6:0] tag_0_r_delay38_r;
    reg [6:0] tag_0_r_delay39_r;
    reg [6:0] tag_0_r_delay40_r;
    reg [6:0] tag_0_r_delay41_r;
    reg [6:0] tag_0_r_delay42_r;
    reg [6:0] tag_0_r_delay43_r;
    reg [6:0] tag_0_r_delay44_r;
    reg [6:0] tag_0_r_delay45_r;
    reg [6:0] tag_0_r_delay46_r;
    reg [6:0] tag_0_r_delay47_r;
    reg [6:0] tag_0_r_delay48_r;
    reg [6:0] tag_0_r_delay49_r;
    reg [6:0] tag_0_r_delay50_r;
    reg [6:0] tag_0_r_delay51_r;
    reg [6:0] tag_0_r_delay52_r;
    reg [6:0] tag_0_r_delay53_r;
    reg [6:0] tag_0_r_delay54_r;
    reg [6:0] tag_0_r_delay55_r;
    reg [6:0] tag_0_r_delay56_r;
    reg [6:0] tag_0_r_delay57_r;
    reg [6:0] tag_0_r_delay58_r;
    reg [6:0] tag_0_r_delay59_r;
    reg [6:0] tag_0_r_delay60_r;
    reg [6:0] tag_0_r_delay61_r;
    reg [6:0] tag_0_r_delay62_r;
    reg [6:0] tag_0_r_delay63_r;
    reg [6:0] tag_0_r_delay64_r;
    reg [6:0] tag_0_r_delay65_r;
    reg [6:0] tag_0_r_delay66_r;
    reg [6:0] tag_0_r_delay67_r;
    reg [6:0] tag_0_r_delay68_r;
    reg [6:0] tag_0_r_delay69_r;
    reg [6:0] tag_0_r_delay70_r;
    reg [6:0] tag_0_r_delay71_r;
    reg [6:0] tag_0_r_delay72_r;
    reg [6:0] tag_0_r_delay73_r;
    reg [6:0] tag_0_r_delay74_r;
    reg [6:0] tag_0_r_delay75_r;
    reg [6:0] tag_0_r_delay76_r;
    reg [6:0] tag_0_r_delay77_r;
    reg [6:0] tag_0_r_delay78_r;
    reg [6:0] tag_0_r_delay79_r;
    reg [6:0] tag_0_r_delay80_r;
    reg [6:0] tag_0_r_delay81_r;
    reg [6:0] tag_0_r_delay82_r;
    reg [6:0] tag_0_r_delay83_r;
    reg [6:0] tag_0_r_delay84_r;
    reg [50:0] maximum012_select_delay5_r;
    reg [50:0] maximum012_select_delay6_r;
    reg [50:0] maximum012_select_delay7_r;
    wire [8:0] v52_0_w_d9_r_address_w;
    wire [71:0] unused_v52_0_w_d9_r_data_w;
    reg [51:0] v52_0_w_delay10_r;
    reg [51:0] v52_0_w_delay11_r;
    reg [51:0] v52_0_w_delay12_r;
    reg [51:0] v52_0_w_delay13_r;
    reg [1:0] scale_left0_amt1_w_delay10_r;
    reg [1:0] scale_left0_amt2_w_delay10_r;
    reg [1:0] scale_left0_amt2_w_delay11_r;
    reg [1:0] scale_bias0_amt1_w_delay11_r;
    reg [1:0] scale_bias0_amt2_w_delay11_r;
    reg [1:0] scale_bias0_amt2_w_delay12_r;
    reg [16:0] scale_add0_a1_w_delay14_r;
    reg [16:0] scale_add0_b1_w_delay14_r;
    reg [34:0] scale_add0_low0_w_delay15_r;
    reg [1:0] scale_rounded0_amt0_w_delay10_r;
    reg [1:0] scale_rounded0_amt0_w_delay11_r;
    reg [1:0] scale_rounded0_amt0_w_delay12_r;
    reg [1:0] scale_rounded0_amt0_w_delay13_r;
    reg [1:0] scale_rounded0_amt0_w_delay14_r;
    reg [1:0] scale_rounded0_amt0_w_delay15_r;
    reg [1:0] scale_rounded0_amt1_w_delay10_r;
    reg [1:0] scale_rounded0_amt1_w_delay11_r;
    reg [1:0] scale_rounded0_amt1_w_delay12_r;
    reg [1:0] scale_rounded0_amt1_w_delay13_r;
    reg [1:0] scale_rounded0_amt1_w_delay14_r;
    reg [1:0] scale_rounded0_amt1_w_delay15_r;
    reg [1:0] scale_rounded0_amt1_w_delay16_r;
    reg [1:0] scale_rounded0_amt2_w_delay10_r;
    reg [1:0] scale_rounded0_amt2_w_delay11_r;
    reg [1:0] scale_rounded0_amt2_w_delay12_r;
    reg [1:0] scale_rounded0_amt2_w_delay13_r;
    reg [1:0] scale_rounded0_amt2_w_delay14_r;
    reg [1:0] scale_rounded0_amt2_w_delay15_r;
    reg [1:0] scale_rounded0_amt2_w_delay16_r;
    reg [1:0] scale_rounded0_amt2_w_delay17_r;
    reg [9:0] h_delay9_r;
    reg [9:0] h_delay10_r;
    reg [9:0] h_delay11_r;
    reg [9:0] h_delay12_r;
    reg [9:0] h_delay13_r;
    reg [9:0] h_delay14_r;
    reg [9:0] h_delay15_r;
    reg [9:0] h_delay16_r;
    reg [9:0] h_delay17_r;
    reg [9:0] h_delay18_r;
    reg [9:0] h_delay19_r;
    reg [9:0] h_delay20_r;
    reg [9:0] h_delay21_r;
    reg [9:0] h_delay22_r;
    reg [9:0] h_delay23_r;
    reg [9:0] h_delay24_r;
    reg [9:0] h_delay25_r;
    reg [9:0] h_delay26_r;
    reg [9:0] h_delay27_r;
    reg [9:0] h_delay28_r;
    reg [9:0] h_delay29_r;
    reg [9:0] h_delay30_r;
    reg [9:0] h_delay31_r;
    reg [9:0] h_delay32_r;
    reg [9:0] h_delay33_r;
    reg [9:0] h_delay34_r;
    reg [9:0] h_delay35_r;
    reg [9:0] h_delay36_r;
    reg [9:0] h_delay37_r;
    reg [9:0] h_delay38_r;
    reg [9:0] h_delay39_r;
    reg [9:0] h_delay40_r;
    reg [9:0] h_delay41_r;
    reg [9:0] h_delay42_r;
    reg [9:0] h_delay43_r;
    reg [9:0] h_delay44_r;
    reg [9:0] h_delay45_r;
    reg [9:0] h_delay46_r;
    reg [9:0] h_delay47_r;
    reg [9:0] h_delay48_r;
    reg [9:0] h_delay49_r;
    reg [9:0] h_delay50_r;
    reg [9:0] h_delay51_r;
    reg [9:0] h_delay52_r;
    reg [9:0] h_delay53_r;
    reg [9:0] h_delay54_r;
    reg [9:0] h_delay55_r;
    reg [9:0] h_delay56_r;
    reg [9:0] h_delay57_r;
    reg [9:0] h_delay58_r;
    reg [9:0] h_delay59_r;
    reg [9:0] h_delay60_r;
    reg [9:0] h_delay61_r;
    reg [9:0] h_delay62_r;
    reg [9:0] h_delay63_r;
    reg [9:0] h_delay64_r;
    reg [9:0] h_delay65_r;
    reg [9:0] h_delay66_r;
    reg [9:0] h_delay67_r;
    reg [9:0] h_delay68_r;
    reg [9:0] h_delay69_r;
    reg [9:0] h_delay70_r;
    reg [9:0] h_delay71_r;
    reg [9:0] h_delay72_r;
    reg [9:0] h_delay73_r;
    reg [9:0] h_delay74_r;
    reg [9:0] h_delay75_r;
    reg [9:0] h_delay76_r;
    reg [9:0] h_delay77_r;
    reg [9:0] h_delay78_r;
    reg [9:0] h_delay79_r;
    reg [9:0] h_delay80_r;
    reg [9:0] h_delay81_r;
    reg [9:0] h_delay82_r;
    reg [9:0] h_delay83_r;
    reg [9:0] h_delay84_r;
    reg [32:0] scale_left0_2_r_delay13_r;
    reg [32:0] scale_left0_2_r_delay14_r;
    reg [32:0] scale_left0_2_r_delay15_r;
    reg [32:0] scale_left0_2_r_delay16_r;
    reg [32:0] scale_left0_2_r_delay17_r;
    reg [32:0] scale_left0_2_r_delay18_r;
    wire [8:0] v52_1_w_d9_r_address_w;
    wire [71:0] unused_v52_1_w_d9_r_data_w;
    reg [51:0] v52_1_w_delay10_r;
    reg [51:0] v52_1_w_delay11_r;
    reg [51:0] v52_1_w_delay12_r;
    reg [51:0] v52_1_w_delay13_r;
    reg [1:0] scale_left1_amt1_w_delay10_r;
    reg [1:0] scale_left1_amt2_w_delay10_r;
    reg [1:0] scale_left1_amt2_w_delay11_r;
    reg [1:0] scale_bias1_amt1_w_delay11_r;
    reg [1:0] scale_bias1_amt2_w_delay11_r;
    reg [1:0] scale_bias1_amt2_w_delay12_r;
    reg [16:0] scale_add1_a1_w_delay14_r;
    reg [16:0] scale_add1_b1_w_delay14_r;
    reg [34:0] scale_add1_low0_w_delay15_r;
    reg [1:0] scale_rounded1_amt0_w_delay10_r;
    reg [1:0] scale_rounded1_amt0_w_delay11_r;
    reg [1:0] scale_rounded1_amt0_w_delay12_r;
    reg [1:0] scale_rounded1_amt0_w_delay13_r;
    reg [1:0] scale_rounded1_amt0_w_delay14_r;
    reg [1:0] scale_rounded1_amt0_w_delay15_r;
    reg [1:0] scale_rounded1_amt1_w_delay10_r;
    reg [1:0] scale_rounded1_amt1_w_delay11_r;
    reg [1:0] scale_rounded1_amt1_w_delay12_r;
    reg [1:0] scale_rounded1_amt1_w_delay13_r;
    reg [1:0] scale_rounded1_amt1_w_delay14_r;
    reg [1:0] scale_rounded1_amt1_w_delay15_r;
    reg [1:0] scale_rounded1_amt1_w_delay16_r;
    reg [1:0] scale_rounded1_amt2_w_delay10_r;
    reg [1:0] scale_rounded1_amt2_w_delay11_r;
    reg [1:0] scale_rounded1_amt2_w_delay12_r;
    reg [1:0] scale_rounded1_amt2_w_delay13_r;
    reg [1:0] scale_rounded1_amt2_w_delay14_r;
    reg [1:0] scale_rounded1_amt2_w_delay15_r;
    reg [1:0] scale_rounded1_amt2_w_delay16_r;
    reg [1:0] scale_rounded1_amt2_w_delay17_r;
    reg [32:0] scale_left1_2_r_delay13_r;
    reg [32:0] scale_left1_2_r_delay14_r;
    reg [32:0] scale_left1_2_r_delay15_r;
    reg [32:0] scale_left1_2_r_delay16_r;
    reg [32:0] scale_left1_2_r_delay17_r;
    reg [32:0] scale_left1_2_r_delay18_r;
    wire [8:0] v52_2_w_d9_r_address_w;
    wire [71:0] unused_v52_2_w_d9_r_data_w;
    reg [51:0] v52_2_w_delay10_r;
    reg [51:0] v52_2_w_delay11_r;
    reg [51:0] v52_2_w_delay12_r;
    reg [51:0] v52_2_w_delay13_r;
    reg [1:0] scale_left2_amt1_w_delay10_r;
    reg [1:0] scale_left2_amt2_w_delay10_r;
    reg [1:0] scale_left2_amt2_w_delay11_r;
    reg [1:0] scale_bias2_amt1_w_delay11_r;
    reg [1:0] scale_bias2_amt2_w_delay11_r;
    reg [1:0] scale_bias2_amt2_w_delay12_r;
    reg [16:0] scale_add2_a1_w_delay14_r;
    reg [16:0] scale_add2_b1_w_delay14_r;
    reg [34:0] scale_add2_low0_w_delay15_r;
    reg [1:0] scale_rounded2_amt0_w_delay10_r;
    reg [1:0] scale_rounded2_amt0_w_delay11_r;
    reg [1:0] scale_rounded2_amt0_w_delay12_r;
    reg [1:0] scale_rounded2_amt0_w_delay13_r;
    reg [1:0] scale_rounded2_amt0_w_delay14_r;
    reg [1:0] scale_rounded2_amt0_w_delay15_r;
    reg [1:0] scale_rounded2_amt1_w_delay10_r;
    reg [1:0] scale_rounded2_amt1_w_delay11_r;
    reg [1:0] scale_rounded2_amt1_w_delay12_r;
    reg [1:0] scale_rounded2_amt1_w_delay13_r;
    reg [1:0] scale_rounded2_amt1_w_delay14_r;
    reg [1:0] scale_rounded2_amt1_w_delay15_r;
    reg [1:0] scale_rounded2_amt1_w_delay16_r;
    reg [1:0] scale_rounded2_amt2_w_delay10_r;
    reg [1:0] scale_rounded2_amt2_w_delay11_r;
    reg [1:0] scale_rounded2_amt2_w_delay12_r;
    reg [1:0] scale_rounded2_amt2_w_delay13_r;
    reg [1:0] scale_rounded2_amt2_w_delay14_r;
    reg [1:0] scale_rounded2_amt2_w_delay15_r;
    reg [1:0] scale_rounded2_amt2_w_delay16_r;
    reg [1:0] scale_rounded2_amt2_w_delay17_r;
    reg [32:0] scale_left2_2_r_delay13_r;
    reg [32:0] scale_left2_2_r_delay14_r;
    reg [32:0] scale_left2_2_r_delay15_r;
    reg [32:0] scale_left2_2_r_delay16_r;
    reg [32:0] scale_left2_2_r_delay17_r;
    reg [32:0] scale_left2_2_r_delay18_r;
    reg [16:0] product0_0_sum0_0_a1_w_delay22_r;
    reg [16:0] product0_0_sum0_0_b1_w_delay22_r;
    reg [34:0] product0_0_sum0_0_low0_w_delay23_r;
    reg [16:0] product0_1_sum0_0_a1_w_delay22_r;
    reg [16:0] product0_1_sum0_0_b1_w_delay22_r;
    reg [34:0] product0_1_sum0_0_low0_w_delay23_r;
    reg [20:0] numerator0_a1_w_delay24_r;
    reg [20:0] numerator0_b1_w_delay24_r;
    reg [34:0] numerator0_low0_w_delay25_r;
    reg [34:0] inverse0_sum0_0_a1_w_delay28_r;
    reg [34:0] inverse0_sum0_0_b1_w_delay28_r;
    reg [16:0] inverse0_sum0_0_a2_w_delay28_r;
    reg [16:0] inverse0_sum0_0_a2_w_delay29_r;
    reg [16:0] inverse0_sum0_0_b2_w_delay28_r;
    reg [16:0] inverse0_sum0_0_b2_w_delay29_r;
    reg [34:0] inverse0_sum0_0_low1_w_delay30_r;
    reg [34:0] inverse0_sum0_0_low0_w_delay29_r;
    reg [34:0] inverse0_sum0_0_low0_w_delay30_r;
    reg [34:0] inverse0_sum0_1_a1_w_delay28_r;
    reg [34:0] inverse0_sum0_1_b1_w_delay28_r;
    reg [16:0] inverse0_sum0_1_a2_w_delay28_r;
    reg [16:0] inverse0_sum0_1_a2_w_delay29_r;
    reg [16:0] inverse0_sum0_1_b2_w_delay28_r;
    reg [16:0] inverse0_sum0_1_b2_w_delay29_r;
    reg [34:0] inverse0_sum0_1_low1_w_delay30_r;
    reg [34:0] inverse0_sum0_1_low0_w_delay29_r;
    reg [34:0] inverse0_sum0_1_low0_w_delay30_r;
    reg [34:0] inverse0_sum0_2_a1_w_delay28_r;
    reg [34:0] inverse0_sum0_2_b1_w_delay28_r;
    reg [16:0] inverse0_sum0_2_a2_w_delay28_r;
    reg [16:0] inverse0_sum0_2_a2_w_delay29_r;
    reg [16:0] inverse0_sum0_2_b2_w_delay28_r;
    reg [16:0] inverse0_sum0_2_b2_w_delay29_r;
    reg [34:0] inverse0_sum0_2_low1_w_delay30_r;
    reg [34:0] inverse0_sum0_2_low0_w_delay29_r;
    reg [34:0] inverse0_sum0_2_low0_w_delay30_r;
    reg [34:0] inverse0_sum0_3_a1_w_delay28_r;
    reg [34:0] inverse0_sum0_3_b1_w_delay28_r;
    reg [16:0] inverse0_sum0_3_a2_w_delay28_r;
    reg [16:0] inverse0_sum0_3_a2_w_delay29_r;
    reg [16:0] inverse0_sum0_3_b2_w_delay28_r;
    reg [16:0] inverse0_sum0_3_b2_w_delay29_r;
    reg [34:0] inverse0_sum0_3_low1_w_delay30_r;
    reg [34:0] inverse0_sum0_3_low0_w_delay29_r;
    reg [34:0] inverse0_sum0_3_low0_w_delay30_r;
    reg [34:0] inverse0_sum1_0_a1_w_delay31_r;
    reg [34:0] inverse0_sum1_0_b1_w_delay31_r;
    reg [16:0] inverse0_sum1_0_a2_w_delay31_r;
    reg [16:0] inverse0_sum1_0_a2_w_delay32_r;
    reg [16:0] inverse0_sum1_0_b2_w_delay31_r;
    reg [16:0] inverse0_sum1_0_b2_w_delay32_r;
    reg [34:0] inverse0_sum1_0_low1_w_delay33_r;
    reg [34:0] inverse0_sum1_0_low0_w_delay32_r;
    reg [34:0] inverse0_sum1_0_low0_w_delay33_r;
    reg [34:0] inverse0_sum1_1_a1_w_delay31_r;
    reg [34:0] inverse0_sum1_1_b1_w_delay31_r;
    reg [16:0] inverse0_sum1_1_a2_w_delay31_r;
    reg [16:0] inverse0_sum1_1_a2_w_delay32_r;
    reg [16:0] inverse0_sum1_1_b2_w_delay31_r;
    reg [16:0] inverse0_sum1_1_b2_w_delay32_r;
    reg [34:0] inverse0_sum1_1_low1_w_delay33_r;
    reg [34:0] inverse0_sum1_1_low0_w_delay32_r;
    reg [34:0] inverse0_sum1_1_low0_w_delay33_r;
    reg [34:0] inverse0_sum2_0_a1_w_delay34_r;
    reg [34:0] inverse0_sum2_0_b1_w_delay34_r;
    reg [16:0] inverse0_sum2_0_a2_w_delay34_r;
    reg [16:0] inverse0_sum2_0_a2_w_delay35_r;
    reg [16:0] inverse0_sum2_0_b2_w_delay34_r;
    reg [16:0] inverse0_sum2_0_b2_w_delay35_r;
    reg [34:0] inverse0_sum2_0_low1_w_delay36_r;
    reg [34:0] inverse0_sum2_0_low0_w_delay35_r;
    reg [34:0] inverse0_sum2_0_low0_w_delay36_r;
    reg [34:0] inverse_abs0_a1_w_delay38_r;
    reg [34:0] inverse_abs0_b1_w_delay38_r;
    reg [16:0] inverse_abs0_a2_w_delay38_r;
    reg [16:0] inverse_abs0_a2_w_delay39_r;
    reg [16:0] inverse_abs0_b2_w_delay38_r;
    reg [16:0] inverse_abs0_b2_w_delay39_r;
    reg [34:0] inverse_abs0_low1_w_delay40_r;
    reg [34:0] inverse_abs0_low0_w_delay39_r;
    reg [34:0] inverse_abs0_low0_w_delay40_r;
    reg [1:0] gradient_bias0_amt1_w_delay3_r;
    reg [1:0] gradient_bias0_amt2_w_delay3_r;
    reg [1:0] gradient_bias0_amt2_w_delay4_r;
    reg [0:0] gradient_bias0_amt3_w_delay3_r;
    reg [0:0] gradient_bias0_amt3_w_delay4_r;
    reg [0:0] gradient_bias0_amt3_w_delay5_r;
    wire [8:0] gradient_bias0_3_r_d40_r_address_w;
    wire [143:0] unused_gradient_bias0_3_r_d40_r_data_w;
    reg [34:0] gradient_round0_a1_w_delay41_r;
    reg [34:0] gradient_round0_b1_w_delay41_r;
    reg [17:0] gradient_round0_a2_w_delay41_r;
    reg [17:0] gradient_round0_a2_w_delay42_r;
    reg [17:0] gradient_round0_b2_w_delay41_r;
    reg [17:0] gradient_round0_b2_w_delay42_r;
    reg [34:0] gradient_round0_low1_w_delay43_r;
    reg [34:0] gradient_round0_low0_w_delay42_r;
    reg [34:0] gradient_round0_low0_w_delay43_r;
    reg [1:0] gradient_shift0_amt0_w_delay3_r;
    reg [1:0] gradient_shift0_amt0_w_delay4_r;
    reg [1:0] gradient_shift0_amt0_w_delay5_r;
    reg [1:0] gradient_shift0_amt0_w_delay6_r;
    reg [1:0] gradient_shift0_amt0_w_delay7_r;
    reg [1:0] gradient_shift0_amt0_w_delay8_r;
    reg [1:0] gradient_shift0_amt0_w_delay9_r;
    reg [1:0] gradient_shift0_amt0_w_delay10_r;
    reg [1:0] gradient_shift0_amt0_w_delay11_r;
    reg [1:0] gradient_shift0_amt0_w_delay12_r;
    reg [1:0] gradient_shift0_amt0_w_delay13_r;
    reg [1:0] gradient_shift0_amt0_w_delay14_r;
    reg [1:0] gradient_shift0_amt0_w_delay15_r;
    reg [1:0] gradient_shift0_amt0_w_delay16_r;
    reg [1:0] gradient_shift0_amt0_w_delay17_r;
    reg [1:0] gradient_shift0_amt0_w_delay18_r;
    reg [1:0] gradient_shift0_amt0_w_delay19_r;
    reg [1:0] gradient_shift0_amt0_w_delay20_r;
    reg [1:0] gradient_shift0_amt0_w_delay21_r;
    reg [1:0] gradient_shift0_amt0_w_delay22_r;
    reg [1:0] gradient_shift0_amt0_w_delay23_r;
    reg [1:0] gradient_shift0_amt0_w_delay24_r;
    reg [1:0] gradient_shift0_amt0_w_delay25_r;
    reg [1:0] gradient_shift0_amt0_w_delay26_r;
    reg [1:0] gradient_shift0_amt0_w_delay27_r;
    reg [1:0] gradient_shift0_amt0_w_delay28_r;
    reg [1:0] gradient_shift0_amt0_w_delay29_r;
    reg [1:0] gradient_shift0_amt0_w_delay30_r;
    reg [1:0] gradient_shift0_amt0_w_delay31_r;
    reg [1:0] gradient_shift0_amt0_w_delay32_r;
    reg [1:0] gradient_shift0_amt0_w_delay33_r;
    reg [1:0] gradient_shift0_amt0_w_delay34_r;
    reg [1:0] gradient_shift0_amt0_w_delay35_r;
    reg [1:0] gradient_shift0_amt0_w_delay36_r;
    reg [1:0] gradient_shift0_amt0_w_delay37_r;
    reg [1:0] gradient_shift0_amt0_w_delay38_r;
    reg [1:0] gradient_shift0_amt0_w_delay39_r;
    reg [1:0] gradient_shift0_amt0_w_delay40_r;
    reg [1:0] gradient_shift0_amt0_w_delay41_r;
    reg [1:0] gradient_shift0_amt0_w_delay42_r;
    reg [1:0] gradient_shift0_amt0_w_delay43_r;
    reg [1:0] gradient_shift0_amt1_w_delay3_r;
    reg [1:0] gradient_shift0_amt1_w_delay4_r;
    reg [1:0] gradient_shift0_amt1_w_delay5_r;
    reg [1:0] gradient_shift0_amt1_w_delay6_r;
    reg [1:0] gradient_shift0_amt1_w_delay7_r;
    reg [1:0] gradient_shift0_amt1_w_delay8_r;
    reg [1:0] gradient_shift0_amt1_w_delay9_r;
    reg [1:0] gradient_shift0_amt1_w_delay10_r;
    reg [1:0] gradient_shift0_amt1_w_delay11_r;
    reg [1:0] gradient_shift0_amt1_w_delay12_r;
    reg [1:0] gradient_shift0_amt1_w_delay13_r;
    reg [1:0] gradient_shift0_amt1_w_delay14_r;
    reg [1:0] gradient_shift0_amt1_w_delay15_r;
    reg [1:0] gradient_shift0_amt1_w_delay16_r;
    reg [1:0] gradient_shift0_amt1_w_delay17_r;
    reg [1:0] gradient_shift0_amt1_w_delay18_r;
    reg [1:0] gradient_shift0_amt1_w_delay19_r;
    reg [1:0] gradient_shift0_amt1_w_delay20_r;
    reg [1:0] gradient_shift0_amt1_w_delay21_r;
    reg [1:0] gradient_shift0_amt1_w_delay22_r;
    reg [1:0] gradient_shift0_amt1_w_delay23_r;
    reg [1:0] gradient_shift0_amt1_w_delay24_r;
    reg [1:0] gradient_shift0_amt1_w_delay25_r;
    reg [1:0] gradient_shift0_amt1_w_delay26_r;
    reg [1:0] gradient_shift0_amt1_w_delay27_r;
    reg [1:0] gradient_shift0_amt1_w_delay28_r;
    reg [1:0] gradient_shift0_amt1_w_delay29_r;
    reg [1:0] gradient_shift0_amt1_w_delay30_r;
    reg [1:0] gradient_shift0_amt1_w_delay31_r;
    reg [1:0] gradient_shift0_amt1_w_delay32_r;
    reg [1:0] gradient_shift0_amt1_w_delay33_r;
    reg [1:0] gradient_shift0_amt1_w_delay34_r;
    reg [1:0] gradient_shift0_amt1_w_delay35_r;
    reg [1:0] gradient_shift0_amt1_w_delay36_r;
    reg [1:0] gradient_shift0_amt1_w_delay37_r;
    reg [1:0] gradient_shift0_amt1_w_delay38_r;
    reg [1:0] gradient_shift0_amt1_w_delay39_r;
    reg [1:0] gradient_shift0_amt1_w_delay40_r;
    reg [1:0] gradient_shift0_amt1_w_delay41_r;
    reg [1:0] gradient_shift0_amt1_w_delay42_r;
    reg [1:0] gradient_shift0_amt1_w_delay43_r;
    reg [1:0] gradient_shift0_amt1_w_delay44_r;
    reg [1:0] gradient_shift0_amt2_w_delay3_r;
    reg [1:0] gradient_shift0_amt2_w_delay4_r;
    reg [1:0] gradient_shift0_amt2_w_delay5_r;
    reg [1:0] gradient_shift0_amt2_w_delay6_r;
    reg [1:0] gradient_shift0_amt2_w_delay7_r;
    reg [1:0] gradient_shift0_amt2_w_delay8_r;
    reg [1:0] gradient_shift0_amt2_w_delay9_r;
    reg [1:0] gradient_shift0_amt2_w_delay10_r;
    reg [1:0] gradient_shift0_amt2_w_delay11_r;
    reg [1:0] gradient_shift0_amt2_w_delay12_r;
    reg [1:0] gradient_shift0_amt2_w_delay13_r;
    reg [1:0] gradient_shift0_amt2_w_delay14_r;
    reg [1:0] gradient_shift0_amt2_w_delay15_r;
    reg [1:0] gradient_shift0_amt2_w_delay16_r;
    reg [1:0] gradient_shift0_amt2_w_delay17_r;
    reg [1:0] gradient_shift0_amt2_w_delay18_r;
    reg [1:0] gradient_shift0_amt2_w_delay19_r;
    reg [1:0] gradient_shift0_amt2_w_delay20_r;
    reg [1:0] gradient_shift0_amt2_w_delay21_r;
    reg [1:0] gradient_shift0_amt2_w_delay22_r;
    reg [1:0] gradient_shift0_amt2_w_delay23_r;
    reg [1:0] gradient_shift0_amt2_w_delay24_r;
    reg [1:0] gradient_shift0_amt2_w_delay25_r;
    reg [1:0] gradient_shift0_amt2_w_delay26_r;
    reg [1:0] gradient_shift0_amt2_w_delay27_r;
    reg [1:0] gradient_shift0_amt2_w_delay28_r;
    reg [1:0] gradient_shift0_amt2_w_delay29_r;
    reg [1:0] gradient_shift0_amt2_w_delay30_r;
    reg [1:0] gradient_shift0_amt2_w_delay31_r;
    reg [1:0] gradient_shift0_amt2_w_delay32_r;
    reg [1:0] gradient_shift0_amt2_w_delay33_r;
    reg [1:0] gradient_shift0_amt2_w_delay34_r;
    reg [1:0] gradient_shift0_amt2_w_delay35_r;
    reg [1:0] gradient_shift0_amt2_w_delay36_r;
    reg [1:0] gradient_shift0_amt2_w_delay37_r;
    reg [1:0] gradient_shift0_amt2_w_delay38_r;
    reg [1:0] gradient_shift0_amt2_w_delay39_r;
    reg [1:0] gradient_shift0_amt2_w_delay40_r;
    reg [1:0] gradient_shift0_amt2_w_delay41_r;
    reg [1:0] gradient_shift0_amt2_w_delay42_r;
    reg [1:0] gradient_shift0_amt2_w_delay43_r;
    reg [1:0] gradient_shift0_amt2_w_delay44_r;
    reg [1:0] gradient_shift0_amt2_w_delay45_r;
    reg [0:0] gradient_shift0_amt3_w_delay3_r;
    reg [0:0] gradient_shift0_amt3_w_delay4_r;
    reg [0:0] gradient_shift0_amt3_w_delay5_r;
    reg [0:0] gradient_shift0_amt3_w_delay6_r;
    reg [0:0] gradient_shift0_amt3_w_delay7_r;
    reg [0:0] gradient_shift0_amt3_w_delay8_r;
    reg [0:0] gradient_shift0_amt3_w_delay9_r;
    reg [0:0] gradient_shift0_amt3_w_delay10_r;
    reg [0:0] gradient_shift0_amt3_w_delay11_r;
    reg [0:0] gradient_shift0_amt3_w_delay12_r;
    reg [0:0] gradient_shift0_amt3_w_delay13_r;
    reg [0:0] gradient_shift0_amt3_w_delay14_r;
    reg [0:0] gradient_shift0_amt3_w_delay15_r;
    reg [0:0] gradient_shift0_amt3_w_delay16_r;
    reg [0:0] gradient_shift0_amt3_w_delay17_r;
    reg [0:0] gradient_shift0_amt3_w_delay18_r;
    reg [0:0] gradient_shift0_amt3_w_delay19_r;
    reg [0:0] gradient_shift0_amt3_w_delay20_r;
    reg [0:0] gradient_shift0_amt3_w_delay21_r;
    reg [0:0] gradient_shift0_amt3_w_delay22_r;
    reg [0:0] gradient_shift0_amt3_w_delay23_r;
    reg [0:0] gradient_shift0_amt3_w_delay24_r;
    reg [0:0] gradient_shift0_amt3_w_delay25_r;
    reg [0:0] gradient_shift0_amt3_w_delay26_r;
    reg [0:0] gradient_shift0_amt3_w_delay27_r;
    reg [0:0] gradient_shift0_amt3_w_delay28_r;
    reg [0:0] gradient_shift0_amt3_w_delay29_r;
    reg [0:0] gradient_shift0_amt3_w_delay30_r;
    reg [0:0] gradient_shift0_amt3_w_delay31_r;
    reg [0:0] gradient_shift0_amt3_w_delay32_r;
    reg [0:0] gradient_shift0_amt3_w_delay33_r;
    reg [0:0] gradient_shift0_amt3_w_delay34_r;
    reg [0:0] gradient_shift0_amt3_w_delay35_r;
    reg [0:0] gradient_shift0_amt3_w_delay36_r;
    reg [0:0] gradient_shift0_amt3_w_delay37_r;
    reg [0:0] gradient_shift0_amt3_w_delay38_r;
    reg [0:0] gradient_shift0_amt3_w_delay39_r;
    reg [0:0] gradient_shift0_amt3_w_delay40_r;
    reg [0:0] gradient_shift0_amt3_w_delay41_r;
    reg [0:0] gradient_shift0_amt3_w_delay42_r;
    reg [0:0] gradient_shift0_amt3_w_delay43_r;
    reg [0:0] gradient_shift0_amt3_w_delay44_r;
    reg [0:0] gradient_shift0_amt3_w_delay45_r;
    reg [0:0] gradient_shift0_amt3_w_delay46_r;
    reg [0:0] inverse_abs0_sign_delay38_r;
    reg [0:0] inverse_abs0_sign_delay39_r;
    reg [0:0] inverse_abs0_sign_delay40_r;
    reg [0:0] inverse_abs0_sign_delay41_r;
    reg [0:0] inverse_abs0_sign_delay42_r;
    reg [0:0] inverse_abs0_sign_delay43_r;
    reg [0:0] inverse_abs0_sign_delay44_r;
    reg [0:0] inverse_abs0_sign_delay45_r;
    reg [0:0] inverse_abs0_sign_delay46_r;
    reg [0:0] inverse_abs0_sign_delay47_r;
    reg [0:0] inverse_abs0_sign_delay48_r;
    reg [20:0] gradient_signed0_a1_w_delay49_r;
    reg [20:0] gradient_signed0_b1_w_delay49_r;
    reg [34:0] gradient_signed0_low0_w_delay50_r;
    reg [34:0] origin_product0_sum0_0_a1_w_delay52_r;
    reg [34:0] origin_product0_sum0_0_b1_w_delay52_r;
    reg [3:0] origin_product0_sum0_0_a2_w_delay52_r;
    reg [3:0] origin_product0_sum0_0_a2_w_delay53_r;
    reg [3:0] origin_product0_sum0_0_b2_w_delay52_r;
    reg [3:0] origin_product0_sum0_0_b2_w_delay53_r;
    reg [34:0] origin_product0_sum0_0_low1_w_delay54_r;
    reg [34:0] origin_product0_sum0_0_low0_w_delay53_r;
    reg [34:0] origin_product0_sum0_0_low0_w_delay54_r;
    reg [34:0] origin_product0_sum0_1_a1_w_delay52_r;
    reg [34:0] origin_product0_sum0_1_b1_w_delay52_r;
    reg [3:0] origin_product0_sum0_1_a2_w_delay52_r;
    reg [3:0] origin_product0_sum0_1_a2_w_delay53_r;
    reg [3:0] origin_product0_sum0_1_b2_w_delay52_r;
    reg [3:0] origin_product0_sum0_1_b2_w_delay53_r;
    reg [34:0] origin_product0_sum0_1_low1_w_delay54_r;
    reg [34:0] origin_product0_sum0_1_low0_w_delay53_r;
    reg [34:0] origin_product0_sum0_1_low0_w_delay54_r;
    reg [34:0] origin_product0_sum1_0_a1_w_delay55_r;
    reg [34:0] origin_product0_sum1_0_b1_w_delay55_r;
    reg [3:0] origin_product0_sum1_0_a2_w_delay55_r;
    reg [3:0] origin_product0_sum1_0_a2_w_delay56_r;
    reg [3:0] origin_product0_sum1_0_b2_w_delay55_r;
    reg [3:0] origin_product0_sum1_0_b2_w_delay56_r;
    reg [34:0] origin_product0_sum1_0_low1_w_delay57_r;
    reg [34:0] origin_product0_sum1_0_low0_w_delay56_r;
    reg [34:0] origin_product0_sum1_0_low0_w_delay57_r;
    reg [20:0] gradient_abs0_a1_w_delay52_r;
    reg [20:0] gradient_abs0_b1_w_delay52_r;
    reg [34:0] gradient_abs0_low0_w_delay53_r;
    reg [1:0] gradient_drop0_amt0_w_delay2_r;
    reg [1:0] gradient_drop0_amt0_w_delay3_r;
    reg [1:0] gradient_drop0_amt0_w_delay4_r;
    reg [1:0] gradient_drop0_amt0_w_delay5_r;
    reg [1:0] gradient_drop0_amt0_w_delay6_r;
    reg [1:0] gradient_drop0_amt0_w_delay7_r;
    reg [1:0] gradient_drop0_amt0_w_delay8_r;
    reg [1:0] gradient_drop0_amt0_w_delay9_r;
    reg [1:0] gradient_drop0_amt0_w_delay10_r;
    reg [1:0] gradient_drop0_amt0_w_delay11_r;
    reg [1:0] gradient_drop0_amt0_w_delay12_r;
    reg [1:0] gradient_drop0_amt0_w_delay13_r;
    reg [1:0] gradient_drop0_amt0_w_delay14_r;
    reg [1:0] gradient_drop0_amt0_w_delay15_r;
    reg [1:0] gradient_drop0_amt0_w_delay16_r;
    reg [1:0] gradient_drop0_amt0_w_delay17_r;
    reg [1:0] gradient_drop0_amt0_w_delay18_r;
    reg [1:0] gradient_drop0_amt0_w_delay19_r;
    reg [1:0] gradient_drop0_amt0_w_delay20_r;
    reg [1:0] gradient_drop0_amt0_w_delay21_r;
    reg [1:0] gradient_drop0_amt0_w_delay22_r;
    reg [1:0] gradient_drop0_amt0_w_delay23_r;
    reg [1:0] gradient_drop0_amt0_w_delay24_r;
    reg [1:0] gradient_drop0_amt0_w_delay25_r;
    reg [1:0] gradient_drop0_amt0_w_delay26_r;
    reg [1:0] gradient_drop0_amt0_w_delay27_r;
    reg [1:0] gradient_drop0_amt0_w_delay28_r;
    reg [1:0] gradient_drop0_amt0_w_delay29_r;
    reg [1:0] gradient_drop0_amt0_w_delay30_r;
    reg [1:0] gradient_drop0_amt0_w_delay31_r;
    reg [1:0] gradient_drop0_amt0_w_delay32_r;
    reg [1:0] gradient_drop0_amt0_w_delay33_r;
    reg [1:0] gradient_drop0_amt0_w_delay34_r;
    reg [1:0] gradient_drop0_amt0_w_delay35_r;
    reg [1:0] gradient_drop0_amt0_w_delay36_r;
    reg [1:0] gradient_drop0_amt0_w_delay37_r;
    reg [1:0] gradient_drop0_amt0_w_delay38_r;
    reg [1:0] gradient_drop0_amt0_w_delay39_r;
    reg [1:0] gradient_drop0_amt0_w_delay40_r;
    reg [1:0] gradient_drop0_amt0_w_delay41_r;
    reg [1:0] gradient_drop0_amt0_w_delay42_r;
    reg [1:0] gradient_drop0_amt0_w_delay43_r;
    reg [1:0] gradient_drop0_amt0_w_delay44_r;
    reg [1:0] gradient_drop0_amt0_w_delay45_r;
    reg [1:0] gradient_drop0_amt0_w_delay46_r;
    reg [1:0] gradient_drop0_amt0_w_delay47_r;
    reg [1:0] gradient_drop0_amt0_w_delay48_r;
    reg [1:0] gradient_drop0_amt0_w_delay49_r;
    reg [1:0] gradient_drop0_amt0_w_delay50_r;
    reg [1:0] gradient_drop0_amt0_w_delay51_r;
    reg [1:0] gradient_drop0_amt0_w_delay52_r;
    reg [1:0] gradient_drop0_amt0_w_delay53_r;
    reg [1:0] gradient_drop0_amt1_w_delay2_r;
    reg [1:0] gradient_drop0_amt1_w_delay3_r;
    reg [1:0] gradient_drop0_amt1_w_delay4_r;
    reg [1:0] gradient_drop0_amt1_w_delay5_r;
    reg [1:0] gradient_drop0_amt1_w_delay6_r;
    reg [1:0] gradient_drop0_amt1_w_delay7_r;
    reg [1:0] gradient_drop0_amt1_w_delay8_r;
    reg [1:0] gradient_drop0_amt1_w_delay9_r;
    reg [1:0] gradient_drop0_amt1_w_delay10_r;
    reg [1:0] gradient_drop0_amt1_w_delay11_r;
    reg [1:0] gradient_drop0_amt1_w_delay12_r;
    reg [1:0] gradient_drop0_amt1_w_delay13_r;
    reg [1:0] gradient_drop0_amt1_w_delay14_r;
    reg [1:0] gradient_drop0_amt1_w_delay15_r;
    reg [1:0] gradient_drop0_amt1_w_delay16_r;
    reg [1:0] gradient_drop0_amt1_w_delay17_r;
    reg [1:0] gradient_drop0_amt1_w_delay18_r;
    reg [1:0] gradient_drop0_amt1_w_delay19_r;
    reg [1:0] gradient_drop0_amt1_w_delay20_r;
    reg [1:0] gradient_drop0_amt1_w_delay21_r;
    reg [1:0] gradient_drop0_amt1_w_delay22_r;
    reg [1:0] gradient_drop0_amt1_w_delay23_r;
    reg [1:0] gradient_drop0_amt1_w_delay24_r;
    reg [1:0] gradient_drop0_amt1_w_delay25_r;
    reg [1:0] gradient_drop0_amt1_w_delay26_r;
    reg [1:0] gradient_drop0_amt1_w_delay27_r;
    reg [1:0] gradient_drop0_amt1_w_delay28_r;
    reg [1:0] gradient_drop0_amt1_w_delay29_r;
    reg [1:0] gradient_drop0_amt1_w_delay30_r;
    reg [1:0] gradient_drop0_amt1_w_delay31_r;
    reg [1:0] gradient_drop0_amt1_w_delay32_r;
    reg [1:0] gradient_drop0_amt1_w_delay33_r;
    reg [1:0] gradient_drop0_amt1_w_delay34_r;
    reg [1:0] gradient_drop0_amt1_w_delay35_r;
    reg [1:0] gradient_drop0_amt1_w_delay36_r;
    reg [1:0] gradient_drop0_amt1_w_delay37_r;
    reg [1:0] gradient_drop0_amt1_w_delay38_r;
    reg [1:0] gradient_drop0_amt1_w_delay39_r;
    reg [1:0] gradient_drop0_amt1_w_delay40_r;
    reg [1:0] gradient_drop0_amt1_w_delay41_r;
    reg [1:0] gradient_drop0_amt1_w_delay42_r;
    reg [1:0] gradient_drop0_amt1_w_delay43_r;
    reg [1:0] gradient_drop0_amt1_w_delay44_r;
    reg [1:0] gradient_drop0_amt1_w_delay45_r;
    reg [1:0] gradient_drop0_amt1_w_delay46_r;
    reg [1:0] gradient_drop0_amt1_w_delay47_r;
    reg [1:0] gradient_drop0_amt1_w_delay48_r;
    reg [1:0] gradient_drop0_amt1_w_delay49_r;
    reg [1:0] gradient_drop0_amt1_w_delay50_r;
    reg [1:0] gradient_drop0_amt1_w_delay51_r;
    reg [1:0] gradient_drop0_amt1_w_delay52_r;
    reg [1:0] gradient_drop0_amt1_w_delay53_r;
    reg [1:0] gradient_drop0_amt1_w_delay54_r;
    reg [16:0] stored_round0_a1_w_delay56_r;
    reg [16:0] stored_round0_b1_w_delay56_r;
    reg [34:0] stored_round0_low0_w_delay57_r;
    reg [0:0] gradient_abs0_sign_delay52_r;
    reg [0:0] gradient_abs0_sign_delay53_r;
    reg [0:0] gradient_abs0_sign_delay54_r;
    reg [0:0] gradient_abs0_sign_delay55_r;
    reg [0:0] gradient_abs0_sign_delay56_r;
    reg [0:0] gradient_abs0_sign_delay57_r;
    reg [0:0] gradient_abs0_sign_delay58_r;
    reg [16:0] stored_signed0_a1_w_delay59_r;
    reg [16:0] stored_signed0_b1_w_delay59_r;
    reg [34:0] stored_signed0_low0_w_delay60_r;
    reg [16:0] product1_0_sum0_0_a1_w_delay22_r;
    reg [16:0] product1_0_sum0_0_b1_w_delay22_r;
    reg [34:0] product1_0_sum0_0_low0_w_delay23_r;
    reg [16:0] product1_1_sum0_0_a1_w_delay22_r;
    reg [16:0] product1_1_sum0_0_b1_w_delay22_r;
    reg [34:0] product1_1_sum0_0_low0_w_delay23_r;
    reg [20:0] numerator1_a1_w_delay24_r;
    reg [20:0] numerator1_b1_w_delay24_r;
    reg [34:0] numerator1_low0_w_delay25_r;
    reg [34:0] inverse1_sum0_0_a1_w_delay28_r;
    reg [34:0] inverse1_sum0_0_b1_w_delay28_r;
    reg [16:0] inverse1_sum0_0_a2_w_delay28_r;
    reg [16:0] inverse1_sum0_0_a2_w_delay29_r;
    reg [16:0] inverse1_sum0_0_b2_w_delay28_r;
    reg [16:0] inverse1_sum0_0_b2_w_delay29_r;
    reg [34:0] inverse1_sum0_0_low1_w_delay30_r;
    reg [34:0] inverse1_sum0_0_low0_w_delay29_r;
    reg [34:0] inverse1_sum0_0_low0_w_delay30_r;
    reg [34:0] inverse1_sum0_1_a1_w_delay28_r;
    reg [34:0] inverse1_sum0_1_b1_w_delay28_r;
    reg [16:0] inverse1_sum0_1_a2_w_delay28_r;
    reg [16:0] inverse1_sum0_1_a2_w_delay29_r;
    reg [16:0] inverse1_sum0_1_b2_w_delay28_r;
    reg [16:0] inverse1_sum0_1_b2_w_delay29_r;
    reg [34:0] inverse1_sum0_1_low1_w_delay30_r;
    reg [34:0] inverse1_sum0_1_low0_w_delay29_r;
    reg [34:0] inverse1_sum0_1_low0_w_delay30_r;
    reg [34:0] inverse1_sum0_2_a1_w_delay28_r;
    reg [34:0] inverse1_sum0_2_b1_w_delay28_r;
    reg [16:0] inverse1_sum0_2_a2_w_delay28_r;
    reg [16:0] inverse1_sum0_2_a2_w_delay29_r;
    reg [16:0] inverse1_sum0_2_b2_w_delay28_r;
    reg [16:0] inverse1_sum0_2_b2_w_delay29_r;
    reg [34:0] inverse1_sum0_2_low1_w_delay30_r;
    reg [34:0] inverse1_sum0_2_low0_w_delay29_r;
    reg [34:0] inverse1_sum0_2_low0_w_delay30_r;
    reg [34:0] inverse1_sum0_3_a1_w_delay28_r;
    reg [34:0] inverse1_sum0_3_b1_w_delay28_r;
    reg [16:0] inverse1_sum0_3_a2_w_delay28_r;
    reg [16:0] inverse1_sum0_3_a2_w_delay29_r;
    reg [16:0] inverse1_sum0_3_b2_w_delay28_r;
    reg [16:0] inverse1_sum0_3_b2_w_delay29_r;
    reg [34:0] inverse1_sum0_3_low1_w_delay30_r;
    reg [34:0] inverse1_sum0_3_low0_w_delay29_r;
    reg [34:0] inverse1_sum0_3_low0_w_delay30_r;
    reg [34:0] inverse1_sum1_0_a1_w_delay31_r;
    reg [34:0] inverse1_sum1_0_b1_w_delay31_r;
    reg [16:0] inverse1_sum1_0_a2_w_delay31_r;
    reg [16:0] inverse1_sum1_0_a2_w_delay32_r;
    reg [16:0] inverse1_sum1_0_b2_w_delay31_r;
    reg [16:0] inverse1_sum1_0_b2_w_delay32_r;
    reg [34:0] inverse1_sum1_0_low1_w_delay33_r;
    reg [34:0] inverse1_sum1_0_low0_w_delay32_r;
    reg [34:0] inverse1_sum1_0_low0_w_delay33_r;
    reg [34:0] inverse1_sum1_1_a1_w_delay31_r;
    reg [34:0] inverse1_sum1_1_b1_w_delay31_r;
    reg [16:0] inverse1_sum1_1_a2_w_delay31_r;
    reg [16:0] inverse1_sum1_1_a2_w_delay32_r;
    reg [16:0] inverse1_sum1_1_b2_w_delay31_r;
    reg [16:0] inverse1_sum1_1_b2_w_delay32_r;
    reg [34:0] inverse1_sum1_1_low1_w_delay33_r;
    reg [34:0] inverse1_sum1_1_low0_w_delay32_r;
    reg [34:0] inverse1_sum1_1_low0_w_delay33_r;
    reg [34:0] inverse1_sum2_0_a1_w_delay34_r;
    reg [34:0] inverse1_sum2_0_b1_w_delay34_r;
    reg [16:0] inverse1_sum2_0_a2_w_delay34_r;
    reg [16:0] inverse1_sum2_0_a2_w_delay35_r;
    reg [16:0] inverse1_sum2_0_b2_w_delay34_r;
    reg [16:0] inverse1_sum2_0_b2_w_delay35_r;
    reg [34:0] inverse1_sum2_0_low1_w_delay36_r;
    reg [34:0] inverse1_sum2_0_low0_w_delay35_r;
    reg [34:0] inverse1_sum2_0_low0_w_delay36_r;
    reg [34:0] inverse_abs1_a1_w_delay38_r;
    reg [34:0] inverse_abs1_b1_w_delay38_r;
    reg [16:0] inverse_abs1_a2_w_delay38_r;
    reg [16:0] inverse_abs1_a2_w_delay39_r;
    reg [16:0] inverse_abs1_b2_w_delay38_r;
    reg [16:0] inverse_abs1_b2_w_delay39_r;
    reg [34:0] inverse_abs1_low1_w_delay40_r;
    reg [34:0] inverse_abs1_low0_w_delay39_r;
    reg [34:0] inverse_abs1_low0_w_delay40_r;
    reg [1:0] gradient_bias1_amt1_w_delay3_r;
    reg [1:0] gradient_bias1_amt2_w_delay3_r;
    reg [1:0] gradient_bias1_amt2_w_delay4_r;
    reg [0:0] gradient_bias1_amt3_w_delay3_r;
    reg [0:0] gradient_bias1_amt3_w_delay4_r;
    reg [0:0] gradient_bias1_amt3_w_delay5_r;
    wire [8:0] gradient_bias1_3_r_d40_r_address_w;
    wire [143:0] unused_gradient_bias1_3_r_d40_r_data_w;
    reg [34:0] gradient_round1_a1_w_delay41_r;
    reg [34:0] gradient_round1_b1_w_delay41_r;
    reg [17:0] gradient_round1_a2_w_delay41_r;
    reg [17:0] gradient_round1_a2_w_delay42_r;
    reg [17:0] gradient_round1_b2_w_delay41_r;
    reg [17:0] gradient_round1_b2_w_delay42_r;
    reg [34:0] gradient_round1_low1_w_delay43_r;
    reg [34:0] gradient_round1_low0_w_delay42_r;
    reg [34:0] gradient_round1_low0_w_delay43_r;
    reg [1:0] gradient_shift1_amt0_w_delay3_r;
    reg [1:0] gradient_shift1_amt0_w_delay4_r;
    reg [1:0] gradient_shift1_amt0_w_delay5_r;
    reg [1:0] gradient_shift1_amt0_w_delay6_r;
    reg [1:0] gradient_shift1_amt0_w_delay7_r;
    reg [1:0] gradient_shift1_amt0_w_delay8_r;
    reg [1:0] gradient_shift1_amt0_w_delay9_r;
    reg [1:0] gradient_shift1_amt0_w_delay10_r;
    reg [1:0] gradient_shift1_amt0_w_delay11_r;
    reg [1:0] gradient_shift1_amt0_w_delay12_r;
    reg [1:0] gradient_shift1_amt0_w_delay13_r;
    reg [1:0] gradient_shift1_amt0_w_delay14_r;
    reg [1:0] gradient_shift1_amt0_w_delay15_r;
    reg [1:0] gradient_shift1_amt0_w_delay16_r;
    reg [1:0] gradient_shift1_amt0_w_delay17_r;
    reg [1:0] gradient_shift1_amt0_w_delay18_r;
    reg [1:0] gradient_shift1_amt0_w_delay19_r;
    reg [1:0] gradient_shift1_amt0_w_delay20_r;
    reg [1:0] gradient_shift1_amt0_w_delay21_r;
    reg [1:0] gradient_shift1_amt0_w_delay22_r;
    reg [1:0] gradient_shift1_amt0_w_delay23_r;
    reg [1:0] gradient_shift1_amt0_w_delay24_r;
    reg [1:0] gradient_shift1_amt0_w_delay25_r;
    reg [1:0] gradient_shift1_amt0_w_delay26_r;
    reg [1:0] gradient_shift1_amt0_w_delay27_r;
    reg [1:0] gradient_shift1_amt0_w_delay28_r;
    reg [1:0] gradient_shift1_amt0_w_delay29_r;
    reg [1:0] gradient_shift1_amt0_w_delay30_r;
    reg [1:0] gradient_shift1_amt0_w_delay31_r;
    reg [1:0] gradient_shift1_amt0_w_delay32_r;
    reg [1:0] gradient_shift1_amt0_w_delay33_r;
    reg [1:0] gradient_shift1_amt0_w_delay34_r;
    reg [1:0] gradient_shift1_amt0_w_delay35_r;
    reg [1:0] gradient_shift1_amt0_w_delay36_r;
    reg [1:0] gradient_shift1_amt0_w_delay37_r;
    reg [1:0] gradient_shift1_amt0_w_delay38_r;
    reg [1:0] gradient_shift1_amt0_w_delay39_r;
    reg [1:0] gradient_shift1_amt0_w_delay40_r;
    reg [1:0] gradient_shift1_amt0_w_delay41_r;
    reg [1:0] gradient_shift1_amt0_w_delay42_r;
    reg [1:0] gradient_shift1_amt0_w_delay43_r;
    reg [1:0] gradient_shift1_amt1_w_delay3_r;
    reg [1:0] gradient_shift1_amt1_w_delay4_r;
    reg [1:0] gradient_shift1_amt1_w_delay5_r;
    reg [1:0] gradient_shift1_amt1_w_delay6_r;
    reg [1:0] gradient_shift1_amt1_w_delay7_r;
    reg [1:0] gradient_shift1_amt1_w_delay8_r;
    reg [1:0] gradient_shift1_amt1_w_delay9_r;
    reg [1:0] gradient_shift1_amt1_w_delay10_r;
    reg [1:0] gradient_shift1_amt1_w_delay11_r;
    reg [1:0] gradient_shift1_amt1_w_delay12_r;
    reg [1:0] gradient_shift1_amt1_w_delay13_r;
    reg [1:0] gradient_shift1_amt1_w_delay14_r;
    reg [1:0] gradient_shift1_amt1_w_delay15_r;
    reg [1:0] gradient_shift1_amt1_w_delay16_r;
    reg [1:0] gradient_shift1_amt1_w_delay17_r;
    reg [1:0] gradient_shift1_amt1_w_delay18_r;
    reg [1:0] gradient_shift1_amt1_w_delay19_r;
    reg [1:0] gradient_shift1_amt1_w_delay20_r;
    reg [1:0] gradient_shift1_amt1_w_delay21_r;
    reg [1:0] gradient_shift1_amt1_w_delay22_r;
    reg [1:0] gradient_shift1_amt1_w_delay23_r;
    reg [1:0] gradient_shift1_amt1_w_delay24_r;
    reg [1:0] gradient_shift1_amt1_w_delay25_r;
    reg [1:0] gradient_shift1_amt1_w_delay26_r;
    reg [1:0] gradient_shift1_amt1_w_delay27_r;
    reg [1:0] gradient_shift1_amt1_w_delay28_r;
    reg [1:0] gradient_shift1_amt1_w_delay29_r;
    reg [1:0] gradient_shift1_amt1_w_delay30_r;
    reg [1:0] gradient_shift1_amt1_w_delay31_r;
    reg [1:0] gradient_shift1_amt1_w_delay32_r;
    reg [1:0] gradient_shift1_amt1_w_delay33_r;
    reg [1:0] gradient_shift1_amt1_w_delay34_r;
    reg [1:0] gradient_shift1_amt1_w_delay35_r;
    reg [1:0] gradient_shift1_amt1_w_delay36_r;
    reg [1:0] gradient_shift1_amt1_w_delay37_r;
    reg [1:0] gradient_shift1_amt1_w_delay38_r;
    reg [1:0] gradient_shift1_amt1_w_delay39_r;
    reg [1:0] gradient_shift1_amt1_w_delay40_r;
    reg [1:0] gradient_shift1_amt1_w_delay41_r;
    reg [1:0] gradient_shift1_amt1_w_delay42_r;
    reg [1:0] gradient_shift1_amt1_w_delay43_r;
    reg [1:0] gradient_shift1_amt1_w_delay44_r;
    reg [1:0] gradient_shift1_amt2_w_delay3_r;
    reg [1:0] gradient_shift1_amt2_w_delay4_r;
    reg [1:0] gradient_shift1_amt2_w_delay5_r;
    reg [1:0] gradient_shift1_amt2_w_delay6_r;
    reg [1:0] gradient_shift1_amt2_w_delay7_r;
    reg [1:0] gradient_shift1_amt2_w_delay8_r;
    reg [1:0] gradient_shift1_amt2_w_delay9_r;
    reg [1:0] gradient_shift1_amt2_w_delay10_r;
    reg [1:0] gradient_shift1_amt2_w_delay11_r;
    reg [1:0] gradient_shift1_amt2_w_delay12_r;
    reg [1:0] gradient_shift1_amt2_w_delay13_r;
    reg [1:0] gradient_shift1_amt2_w_delay14_r;
    reg [1:0] gradient_shift1_amt2_w_delay15_r;
    reg [1:0] gradient_shift1_amt2_w_delay16_r;
    reg [1:0] gradient_shift1_amt2_w_delay17_r;
    reg [1:0] gradient_shift1_amt2_w_delay18_r;
    reg [1:0] gradient_shift1_amt2_w_delay19_r;
    reg [1:0] gradient_shift1_amt2_w_delay20_r;
    reg [1:0] gradient_shift1_amt2_w_delay21_r;
    reg [1:0] gradient_shift1_amt2_w_delay22_r;
    reg [1:0] gradient_shift1_amt2_w_delay23_r;
    reg [1:0] gradient_shift1_amt2_w_delay24_r;
    reg [1:0] gradient_shift1_amt2_w_delay25_r;
    reg [1:0] gradient_shift1_amt2_w_delay26_r;
    reg [1:0] gradient_shift1_amt2_w_delay27_r;
    reg [1:0] gradient_shift1_amt2_w_delay28_r;
    reg [1:0] gradient_shift1_amt2_w_delay29_r;
    reg [1:0] gradient_shift1_amt2_w_delay30_r;
    reg [1:0] gradient_shift1_amt2_w_delay31_r;
    reg [1:0] gradient_shift1_amt2_w_delay32_r;
    reg [1:0] gradient_shift1_amt2_w_delay33_r;
    reg [1:0] gradient_shift1_amt2_w_delay34_r;
    reg [1:0] gradient_shift1_amt2_w_delay35_r;
    reg [1:0] gradient_shift1_amt2_w_delay36_r;
    reg [1:0] gradient_shift1_amt2_w_delay37_r;
    reg [1:0] gradient_shift1_amt2_w_delay38_r;
    reg [1:0] gradient_shift1_amt2_w_delay39_r;
    reg [1:0] gradient_shift1_amt2_w_delay40_r;
    reg [1:0] gradient_shift1_amt2_w_delay41_r;
    reg [1:0] gradient_shift1_amt2_w_delay42_r;
    reg [1:0] gradient_shift1_amt2_w_delay43_r;
    reg [1:0] gradient_shift1_amt2_w_delay44_r;
    reg [1:0] gradient_shift1_amt2_w_delay45_r;
    reg [0:0] gradient_shift1_amt3_w_delay3_r;
    reg [0:0] gradient_shift1_amt3_w_delay4_r;
    reg [0:0] gradient_shift1_amt3_w_delay5_r;
    reg [0:0] gradient_shift1_amt3_w_delay6_r;
    reg [0:0] gradient_shift1_amt3_w_delay7_r;
    reg [0:0] gradient_shift1_amt3_w_delay8_r;
    reg [0:0] gradient_shift1_amt3_w_delay9_r;
    reg [0:0] gradient_shift1_amt3_w_delay10_r;
    reg [0:0] gradient_shift1_amt3_w_delay11_r;
    reg [0:0] gradient_shift1_amt3_w_delay12_r;
    reg [0:0] gradient_shift1_amt3_w_delay13_r;
    reg [0:0] gradient_shift1_amt3_w_delay14_r;
    reg [0:0] gradient_shift1_amt3_w_delay15_r;
    reg [0:0] gradient_shift1_amt3_w_delay16_r;
    reg [0:0] gradient_shift1_amt3_w_delay17_r;
    reg [0:0] gradient_shift1_amt3_w_delay18_r;
    reg [0:0] gradient_shift1_amt3_w_delay19_r;
    reg [0:0] gradient_shift1_amt3_w_delay20_r;
    reg [0:0] gradient_shift1_amt3_w_delay21_r;
    reg [0:0] gradient_shift1_amt3_w_delay22_r;
    reg [0:0] gradient_shift1_amt3_w_delay23_r;
    reg [0:0] gradient_shift1_amt3_w_delay24_r;
    reg [0:0] gradient_shift1_amt3_w_delay25_r;
    reg [0:0] gradient_shift1_amt3_w_delay26_r;
    reg [0:0] gradient_shift1_amt3_w_delay27_r;
    reg [0:0] gradient_shift1_amt3_w_delay28_r;
    reg [0:0] gradient_shift1_amt3_w_delay29_r;
    reg [0:0] gradient_shift1_amt3_w_delay30_r;
    reg [0:0] gradient_shift1_amt3_w_delay31_r;
    reg [0:0] gradient_shift1_amt3_w_delay32_r;
    reg [0:0] gradient_shift1_amt3_w_delay33_r;
    reg [0:0] gradient_shift1_amt3_w_delay34_r;
    reg [0:0] gradient_shift1_amt3_w_delay35_r;
    reg [0:0] gradient_shift1_amt3_w_delay36_r;
    reg [0:0] gradient_shift1_amt3_w_delay37_r;
    reg [0:0] gradient_shift1_amt3_w_delay38_r;
    reg [0:0] gradient_shift1_amt3_w_delay39_r;
    reg [0:0] gradient_shift1_amt3_w_delay40_r;
    reg [0:0] gradient_shift1_amt3_w_delay41_r;
    reg [0:0] gradient_shift1_amt3_w_delay42_r;
    reg [0:0] gradient_shift1_amt3_w_delay43_r;
    reg [0:0] gradient_shift1_amt3_w_delay44_r;
    reg [0:0] gradient_shift1_amt3_w_delay45_r;
    reg [0:0] gradient_shift1_amt3_w_delay46_r;
    reg [0:0] inverse_abs1_sign_delay38_r;
    reg [0:0] inverse_abs1_sign_delay39_r;
    reg [0:0] inverse_abs1_sign_delay40_r;
    reg [0:0] inverse_abs1_sign_delay41_r;
    reg [0:0] inverse_abs1_sign_delay42_r;
    reg [0:0] inverse_abs1_sign_delay43_r;
    reg [0:0] inverse_abs1_sign_delay44_r;
    reg [0:0] inverse_abs1_sign_delay45_r;
    reg [0:0] inverse_abs1_sign_delay46_r;
    reg [0:0] inverse_abs1_sign_delay47_r;
    reg [0:0] inverse_abs1_sign_delay48_r;
    reg [20:0] gradient_signed1_a1_w_delay49_r;
    reg [20:0] gradient_signed1_b1_w_delay49_r;
    reg [34:0] gradient_signed1_low0_w_delay50_r;
    reg [34:0] origin_product1_sum0_0_a1_w_delay52_r;
    reg [34:0] origin_product1_sum0_0_b1_w_delay52_r;
    reg [3:0] origin_product1_sum0_0_a2_w_delay52_r;
    reg [3:0] origin_product1_sum0_0_a2_w_delay53_r;
    reg [3:0] origin_product1_sum0_0_b2_w_delay52_r;
    reg [3:0] origin_product1_sum0_0_b2_w_delay53_r;
    reg [34:0] origin_product1_sum0_0_low1_w_delay54_r;
    reg [34:0] origin_product1_sum0_0_low0_w_delay53_r;
    reg [34:0] origin_product1_sum0_0_low0_w_delay54_r;
    reg [34:0] origin_product1_sum0_1_a1_w_delay52_r;
    reg [34:0] origin_product1_sum0_1_b1_w_delay52_r;
    reg [3:0] origin_product1_sum0_1_a2_w_delay52_r;
    reg [3:0] origin_product1_sum0_1_a2_w_delay53_r;
    reg [3:0] origin_product1_sum0_1_b2_w_delay52_r;
    reg [3:0] origin_product1_sum0_1_b2_w_delay53_r;
    reg [34:0] origin_product1_sum0_1_low1_w_delay54_r;
    reg [34:0] origin_product1_sum0_1_low0_w_delay53_r;
    reg [34:0] origin_product1_sum0_1_low0_w_delay54_r;
    reg [34:0] origin_product1_sum1_0_a1_w_delay55_r;
    reg [34:0] origin_product1_sum1_0_b1_w_delay55_r;
    reg [3:0] origin_product1_sum1_0_a2_w_delay55_r;
    reg [3:0] origin_product1_sum1_0_a2_w_delay56_r;
    reg [3:0] origin_product1_sum1_0_b2_w_delay55_r;
    reg [3:0] origin_product1_sum1_0_b2_w_delay56_r;
    reg [34:0] origin_product1_sum1_0_low1_w_delay57_r;
    reg [34:0] origin_product1_sum1_0_low0_w_delay56_r;
    reg [34:0] origin_product1_sum1_0_low0_w_delay57_r;
    reg [20:0] gradient_abs1_a1_w_delay52_r;
    reg [20:0] gradient_abs1_b1_w_delay52_r;
    reg [34:0] gradient_abs1_low0_w_delay53_r;
    reg [1:0] gradient_drop1_amt0_w_delay2_r;
    reg [1:0] gradient_drop1_amt0_w_delay3_r;
    reg [1:0] gradient_drop1_amt0_w_delay4_r;
    reg [1:0] gradient_drop1_amt0_w_delay5_r;
    reg [1:0] gradient_drop1_amt0_w_delay6_r;
    reg [1:0] gradient_drop1_amt0_w_delay7_r;
    reg [1:0] gradient_drop1_amt0_w_delay8_r;
    reg [1:0] gradient_drop1_amt0_w_delay9_r;
    reg [1:0] gradient_drop1_amt0_w_delay10_r;
    reg [1:0] gradient_drop1_amt0_w_delay11_r;
    reg [1:0] gradient_drop1_amt0_w_delay12_r;
    reg [1:0] gradient_drop1_amt0_w_delay13_r;
    reg [1:0] gradient_drop1_amt0_w_delay14_r;
    reg [1:0] gradient_drop1_amt0_w_delay15_r;
    reg [1:0] gradient_drop1_amt0_w_delay16_r;
    reg [1:0] gradient_drop1_amt0_w_delay17_r;
    reg [1:0] gradient_drop1_amt0_w_delay18_r;
    reg [1:0] gradient_drop1_amt0_w_delay19_r;
    reg [1:0] gradient_drop1_amt0_w_delay20_r;
    reg [1:0] gradient_drop1_amt0_w_delay21_r;
    reg [1:0] gradient_drop1_amt0_w_delay22_r;
    reg [1:0] gradient_drop1_amt0_w_delay23_r;
    reg [1:0] gradient_drop1_amt0_w_delay24_r;
    reg [1:0] gradient_drop1_amt0_w_delay25_r;
    reg [1:0] gradient_drop1_amt0_w_delay26_r;
    reg [1:0] gradient_drop1_amt0_w_delay27_r;
    reg [1:0] gradient_drop1_amt0_w_delay28_r;
    reg [1:0] gradient_drop1_amt0_w_delay29_r;
    reg [1:0] gradient_drop1_amt0_w_delay30_r;
    reg [1:0] gradient_drop1_amt0_w_delay31_r;
    reg [1:0] gradient_drop1_amt0_w_delay32_r;
    reg [1:0] gradient_drop1_amt0_w_delay33_r;
    reg [1:0] gradient_drop1_amt0_w_delay34_r;
    reg [1:0] gradient_drop1_amt0_w_delay35_r;
    reg [1:0] gradient_drop1_amt0_w_delay36_r;
    reg [1:0] gradient_drop1_amt0_w_delay37_r;
    reg [1:0] gradient_drop1_amt0_w_delay38_r;
    reg [1:0] gradient_drop1_amt0_w_delay39_r;
    reg [1:0] gradient_drop1_amt0_w_delay40_r;
    reg [1:0] gradient_drop1_amt0_w_delay41_r;
    reg [1:0] gradient_drop1_amt0_w_delay42_r;
    reg [1:0] gradient_drop1_amt0_w_delay43_r;
    reg [1:0] gradient_drop1_amt0_w_delay44_r;
    reg [1:0] gradient_drop1_amt0_w_delay45_r;
    reg [1:0] gradient_drop1_amt0_w_delay46_r;
    reg [1:0] gradient_drop1_amt0_w_delay47_r;
    reg [1:0] gradient_drop1_amt0_w_delay48_r;
    reg [1:0] gradient_drop1_amt0_w_delay49_r;
    reg [1:0] gradient_drop1_amt0_w_delay50_r;
    reg [1:0] gradient_drop1_amt0_w_delay51_r;
    reg [1:0] gradient_drop1_amt0_w_delay52_r;
    reg [1:0] gradient_drop1_amt0_w_delay53_r;
    reg [1:0] gradient_drop1_amt1_w_delay2_r;
    reg [1:0] gradient_drop1_amt1_w_delay3_r;
    reg [1:0] gradient_drop1_amt1_w_delay4_r;
    reg [1:0] gradient_drop1_amt1_w_delay5_r;
    reg [1:0] gradient_drop1_amt1_w_delay6_r;
    reg [1:0] gradient_drop1_amt1_w_delay7_r;
    reg [1:0] gradient_drop1_amt1_w_delay8_r;
    reg [1:0] gradient_drop1_amt1_w_delay9_r;
    reg [1:0] gradient_drop1_amt1_w_delay10_r;
    reg [1:0] gradient_drop1_amt1_w_delay11_r;
    reg [1:0] gradient_drop1_amt1_w_delay12_r;
    reg [1:0] gradient_drop1_amt1_w_delay13_r;
    reg [1:0] gradient_drop1_amt1_w_delay14_r;
    reg [1:0] gradient_drop1_amt1_w_delay15_r;
    reg [1:0] gradient_drop1_amt1_w_delay16_r;
    reg [1:0] gradient_drop1_amt1_w_delay17_r;
    reg [1:0] gradient_drop1_amt1_w_delay18_r;
    reg [1:0] gradient_drop1_amt1_w_delay19_r;
    reg [1:0] gradient_drop1_amt1_w_delay20_r;
    reg [1:0] gradient_drop1_amt1_w_delay21_r;
    reg [1:0] gradient_drop1_amt1_w_delay22_r;
    reg [1:0] gradient_drop1_amt1_w_delay23_r;
    reg [1:0] gradient_drop1_amt1_w_delay24_r;
    reg [1:0] gradient_drop1_amt1_w_delay25_r;
    reg [1:0] gradient_drop1_amt1_w_delay26_r;
    reg [1:0] gradient_drop1_amt1_w_delay27_r;
    reg [1:0] gradient_drop1_amt1_w_delay28_r;
    reg [1:0] gradient_drop1_amt1_w_delay29_r;
    reg [1:0] gradient_drop1_amt1_w_delay30_r;
    reg [1:0] gradient_drop1_amt1_w_delay31_r;
    reg [1:0] gradient_drop1_amt1_w_delay32_r;
    reg [1:0] gradient_drop1_amt1_w_delay33_r;
    reg [1:0] gradient_drop1_amt1_w_delay34_r;
    reg [1:0] gradient_drop1_amt1_w_delay35_r;
    reg [1:0] gradient_drop1_amt1_w_delay36_r;
    reg [1:0] gradient_drop1_amt1_w_delay37_r;
    reg [1:0] gradient_drop1_amt1_w_delay38_r;
    reg [1:0] gradient_drop1_amt1_w_delay39_r;
    reg [1:0] gradient_drop1_amt1_w_delay40_r;
    reg [1:0] gradient_drop1_amt1_w_delay41_r;
    reg [1:0] gradient_drop1_amt1_w_delay42_r;
    reg [1:0] gradient_drop1_amt1_w_delay43_r;
    reg [1:0] gradient_drop1_amt1_w_delay44_r;
    reg [1:0] gradient_drop1_amt1_w_delay45_r;
    reg [1:0] gradient_drop1_amt1_w_delay46_r;
    reg [1:0] gradient_drop1_amt1_w_delay47_r;
    reg [1:0] gradient_drop1_amt1_w_delay48_r;
    reg [1:0] gradient_drop1_amt1_w_delay49_r;
    reg [1:0] gradient_drop1_amt1_w_delay50_r;
    reg [1:0] gradient_drop1_amt1_w_delay51_r;
    reg [1:0] gradient_drop1_amt1_w_delay52_r;
    reg [1:0] gradient_drop1_amt1_w_delay53_r;
    reg [1:0] gradient_drop1_amt1_w_delay54_r;
    reg [16:0] stored_round1_a1_w_delay56_r;
    reg [16:0] stored_round1_b1_w_delay56_r;
    reg [34:0] stored_round1_low0_w_delay57_r;
    reg [0:0] gradient_abs1_sign_delay52_r;
    reg [0:0] gradient_abs1_sign_delay53_r;
    reg [0:0] gradient_abs1_sign_delay54_r;
    reg [0:0] gradient_abs1_sign_delay55_r;
    reg [0:0] gradient_abs1_sign_delay56_r;
    reg [0:0] gradient_abs1_sign_delay57_r;
    reg [0:0] gradient_abs1_sign_delay58_r;
    reg [16:0] stored_signed1_a1_w_delay59_r;
    reg [16:0] stored_signed1_b1_w_delay59_r;
    reg [34:0] stored_signed1_low0_w_delay60_r;
    reg [34:0] origin_sum_a1_w_delay58_r;
    reg [34:0] origin_sum_b1_w_delay58_r;
    reg [4:0] origin_sum_a2_w_delay58_r;
    reg [4:0] origin_sum_a2_w_delay59_r;
    reg [4:0] origin_sum_b2_w_delay58_r;
    reg [4:0] origin_sum_b2_w_delay59_r;
    reg [34:0] origin_sum_low1_w_delay60_r;
    reg [34:0] origin_sum_low0_w_delay59_r;
    reg [34:0] origin_sum_low0_w_delay60_r;
    reg [34:0] origin_absolute_a1_w_delay62_r;
    reg [34:0] origin_absolute_b1_w_delay62_r;
    reg [4:0] origin_absolute_a2_w_delay62_r;
    reg [4:0] origin_absolute_a2_w_delay63_r;
    reg [4:0] origin_absolute_b2_w_delay62_r;
    reg [4:0] origin_absolute_b2_w_delay63_r;
    reg [34:0] origin_absolute_low1_w_delay64_r;
    reg [34:0] origin_absolute_low0_w_delay63_r;
    reg [34:0] origin_absolute_low0_w_delay64_r;
    reg [34:0] origin_round_a1_w_delay65_r;
    reg [34:0] origin_round_b1_w_delay65_r;
    reg [4:0] origin_round_a2_w_delay65_r;
    reg [4:0] origin_round_a2_w_delay66_r;
    reg [4:0] origin_round_b2_w_delay65_r;
    reg [4:0] origin_round_b2_w_delay66_r;
    reg [34:0] origin_round_low1_w_delay67_r;
    reg [34:0] origin_round_low0_w_delay66_r;
    reg [34:0] origin_round_low0_w_delay67_r;
    reg [0:0] origin_absolute_sign_delay62_r;
    reg [0:0] origin_absolute_sign_delay63_r;
    reg [0:0] origin_absolute_sign_delay64_r;
    reg [0:0] origin_absolute_sign_delay65_r;
    reg [0:0] origin_absolute_sign_delay66_r;
    reg [0:0] origin_absolute_sign_delay67_r;
    reg [0:0] origin_absolute_sign_delay68_r;
    reg [0:0] origin_absolute_sign_delay69_r;
    reg [34:0] origin_signed_a1_w_delay70_r;
    reg [34:0] origin_signed_b1_w_delay70_r;
    reg [4:0] origin_signed_a2_w_delay70_r;
    reg [4:0] origin_signed_a2_w_delay71_r;
    reg [4:0] origin_signed_b2_w_delay70_r;
    reg [4:0] origin_signed_b2_w_delay71_r;
    reg [34:0] origin_signed_low1_w_delay72_r;
    reg [34:0] origin_signed_low0_w_delay71_r;
    reg [34:0] origin_signed_low0_w_delay72_r;
    wire [8:0] start_base_w_d72_r_address_w;
    wire [71:0] unused_start_base_w_d72_r_data_w;
    reg [34:0] start_sum_a1_w_delay73_r;
    reg [34:0] start_sum_b1_w_delay73_r;
    reg [34:0] start_sum_low0_w_delay74_r;
    reg [34:0] start_absolute_a1_w_delay76_r;
    reg [34:0] start_absolute_b1_w_delay76_r;
    reg [34:0] start_absolute_low0_w_delay77_r;
    reg [1:0] start_drop_amt0_w_delay2_r;
    reg [1:0] start_drop_amt0_w_delay3_r;
    reg [1:0] start_drop_amt0_w_delay4_r;
    reg [1:0] start_drop_amt0_w_delay5_r;
    reg [1:0] start_drop_amt0_w_delay6_r;
    reg [1:0] start_drop_amt0_w_delay7_r;
    reg [1:0] start_drop_amt0_w_delay8_r;
    reg [1:0] start_drop_amt0_w_delay9_r;
    reg [1:0] start_drop_amt0_w_delay10_r;
    reg [1:0] start_drop_amt0_w_delay11_r;
    reg [1:0] start_drop_amt0_w_delay12_r;
    reg [1:0] start_drop_amt0_w_delay13_r;
    reg [1:0] start_drop_amt0_w_delay14_r;
    reg [1:0] start_drop_amt0_w_delay15_r;
    reg [1:0] start_drop_amt0_w_delay16_r;
    reg [1:0] start_drop_amt0_w_delay17_r;
    reg [1:0] start_drop_amt0_w_delay18_r;
    reg [1:0] start_drop_amt0_w_delay19_r;
    reg [1:0] start_drop_amt0_w_delay20_r;
    reg [1:0] start_drop_amt0_w_delay21_r;
    reg [1:0] start_drop_amt0_w_delay22_r;
    reg [1:0] start_drop_amt0_w_delay23_r;
    reg [1:0] start_drop_amt0_w_delay24_r;
    reg [1:0] start_drop_amt0_w_delay25_r;
    reg [1:0] start_drop_amt0_w_delay26_r;
    reg [1:0] start_drop_amt0_w_delay27_r;
    reg [1:0] start_drop_amt0_w_delay28_r;
    reg [1:0] start_drop_amt0_w_delay29_r;
    reg [1:0] start_drop_amt0_w_delay30_r;
    reg [1:0] start_drop_amt0_w_delay31_r;
    reg [1:0] start_drop_amt0_w_delay32_r;
    reg [1:0] start_drop_amt0_w_delay33_r;
    reg [1:0] start_drop_amt0_w_delay34_r;
    reg [1:0] start_drop_amt0_w_delay35_r;
    reg [1:0] start_drop_amt0_w_delay36_r;
    reg [1:0] start_drop_amt0_w_delay37_r;
    reg [1:0] start_drop_amt0_w_delay38_r;
    reg [1:0] start_drop_amt0_w_delay39_r;
    reg [1:0] start_drop_amt0_w_delay40_r;
    reg [1:0] start_drop_amt0_w_delay41_r;
    reg [1:0] start_drop_amt0_w_delay42_r;
    reg [1:0] start_drop_amt0_w_delay43_r;
    reg [1:0] start_drop_amt0_w_delay44_r;
    reg [1:0] start_drop_amt0_w_delay45_r;
    reg [1:0] start_drop_amt0_w_delay46_r;
    reg [1:0] start_drop_amt0_w_delay47_r;
    reg [1:0] start_drop_amt0_w_delay48_r;
    reg [1:0] start_drop_amt0_w_delay49_r;
    reg [1:0] start_drop_amt0_w_delay50_r;
    reg [1:0] start_drop_amt0_w_delay51_r;
    reg [1:0] start_drop_amt0_w_delay52_r;
    reg [1:0] start_drop_amt0_w_delay53_r;
    reg [1:0] start_drop_amt0_w_delay54_r;
    reg [1:0] start_drop_amt0_w_delay55_r;
    reg [1:0] start_drop_amt0_w_delay56_r;
    reg [1:0] start_drop_amt0_w_delay57_r;
    reg [1:0] start_drop_amt0_w_delay58_r;
    reg [1:0] start_drop_amt0_w_delay59_r;
    reg [1:0] start_drop_amt0_w_delay60_r;
    reg [1:0] start_drop_amt0_w_delay61_r;
    reg [1:0] start_drop_amt0_w_delay62_r;
    reg [1:0] start_drop_amt0_w_delay63_r;
    reg [1:0] start_drop_amt0_w_delay64_r;
    reg [1:0] start_drop_amt0_w_delay65_r;
    reg [1:0] start_drop_amt0_w_delay66_r;
    reg [1:0] start_drop_amt0_w_delay67_r;
    reg [1:0] start_drop_amt0_w_delay68_r;
    reg [1:0] start_drop_amt0_w_delay69_r;
    reg [1:0] start_drop_amt0_w_delay70_r;
    reg [1:0] start_drop_amt0_w_delay71_r;
    reg [1:0] start_drop_amt0_w_delay72_r;
    reg [1:0] start_drop_amt0_w_delay73_r;
    reg [1:0] start_drop_amt0_w_delay74_r;
    reg [1:0] start_drop_amt0_w_delay75_r;
    reg [1:0] start_drop_amt0_w_delay76_r;
    reg [1:0] start_drop_amt0_w_delay77_r;
    reg [1:0] start_drop_amt1_w_delay2_r;
    reg [1:0] start_drop_amt1_w_delay3_r;
    reg [1:0] start_drop_amt1_w_delay4_r;
    reg [1:0] start_drop_amt1_w_delay5_r;
    reg [1:0] start_drop_amt1_w_delay6_r;
    reg [1:0] start_drop_amt1_w_delay7_r;
    reg [1:0] start_drop_amt1_w_delay8_r;
    reg [1:0] start_drop_amt1_w_delay9_r;
    reg [1:0] start_drop_amt1_w_delay10_r;
    reg [1:0] start_drop_amt1_w_delay11_r;
    reg [1:0] start_drop_amt1_w_delay12_r;
    reg [1:0] start_drop_amt1_w_delay13_r;
    reg [1:0] start_drop_amt1_w_delay14_r;
    reg [1:0] start_drop_amt1_w_delay15_r;
    reg [1:0] start_drop_amt1_w_delay16_r;
    reg [1:0] start_drop_amt1_w_delay17_r;
    reg [1:0] start_drop_amt1_w_delay18_r;
    reg [1:0] start_drop_amt1_w_delay19_r;
    reg [1:0] start_drop_amt1_w_delay20_r;
    reg [1:0] start_drop_amt1_w_delay21_r;
    reg [1:0] start_drop_amt1_w_delay22_r;
    reg [1:0] start_drop_amt1_w_delay23_r;
    reg [1:0] start_drop_amt1_w_delay24_r;
    reg [1:0] start_drop_amt1_w_delay25_r;
    reg [1:0] start_drop_amt1_w_delay26_r;
    reg [1:0] start_drop_amt1_w_delay27_r;
    reg [1:0] start_drop_amt1_w_delay28_r;
    reg [1:0] start_drop_amt1_w_delay29_r;
    reg [1:0] start_drop_amt1_w_delay30_r;
    reg [1:0] start_drop_amt1_w_delay31_r;
    reg [1:0] start_drop_amt1_w_delay32_r;
    reg [1:0] start_drop_amt1_w_delay33_r;
    reg [1:0] start_drop_amt1_w_delay34_r;
    reg [1:0] start_drop_amt1_w_delay35_r;
    reg [1:0] start_drop_amt1_w_delay36_r;
    reg [1:0] start_drop_amt1_w_delay37_r;
    reg [1:0] start_drop_amt1_w_delay38_r;
    reg [1:0] start_drop_amt1_w_delay39_r;
    reg [1:0] start_drop_amt1_w_delay40_r;
    reg [1:0] start_drop_amt1_w_delay41_r;
    reg [1:0] start_drop_amt1_w_delay42_r;
    reg [1:0] start_drop_amt1_w_delay43_r;
    reg [1:0] start_drop_amt1_w_delay44_r;
    reg [1:0] start_drop_amt1_w_delay45_r;
    reg [1:0] start_drop_amt1_w_delay46_r;
    reg [1:0] start_drop_amt1_w_delay47_r;
    reg [1:0] start_drop_amt1_w_delay48_r;
    reg [1:0] start_drop_amt1_w_delay49_r;
    reg [1:0] start_drop_amt1_w_delay50_r;
    reg [1:0] start_drop_amt1_w_delay51_r;
    reg [1:0] start_drop_amt1_w_delay52_r;
    reg [1:0] start_drop_amt1_w_delay53_r;
    reg [1:0] start_drop_amt1_w_delay54_r;
    reg [1:0] start_drop_amt1_w_delay55_r;
    reg [1:0] start_drop_amt1_w_delay56_r;
    reg [1:0] start_drop_amt1_w_delay57_r;
    reg [1:0] start_drop_amt1_w_delay58_r;
    reg [1:0] start_drop_amt1_w_delay59_r;
    reg [1:0] start_drop_amt1_w_delay60_r;
    reg [1:0] start_drop_amt1_w_delay61_r;
    reg [1:0] start_drop_amt1_w_delay62_r;
    reg [1:0] start_drop_amt1_w_delay63_r;
    reg [1:0] start_drop_amt1_w_delay64_r;
    reg [1:0] start_drop_amt1_w_delay65_r;
    reg [1:0] start_drop_amt1_w_delay66_r;
    reg [1:0] start_drop_amt1_w_delay67_r;
    reg [1:0] start_drop_amt1_w_delay68_r;
    reg [1:0] start_drop_amt1_w_delay69_r;
    reg [1:0] start_drop_amt1_w_delay70_r;
    reg [1:0] start_drop_amt1_w_delay71_r;
    reg [1:0] start_drop_amt1_w_delay72_r;
    reg [1:0] start_drop_amt1_w_delay73_r;
    reg [1:0] start_drop_amt1_w_delay74_r;
    reg [1:0] start_drop_amt1_w_delay75_r;
    reg [1:0] start_drop_amt1_w_delay76_r;
    reg [1:0] start_drop_amt1_w_delay77_r;
    reg [1:0] start_drop_amt1_w_delay78_r;
    reg [30:0] start_round_a1_w_delay80_r;
    reg [30:0] start_round_b1_w_delay80_r;
    reg [34:0] start_round_low0_w_delay81_r;
    reg [0:0] start_absolute_sign_delay76_r;
    reg [0:0] start_absolute_sign_delay77_r;
    reg [0:0] start_absolute_sign_delay78_r;
    reg [0:0] start_absolute_sign_delay79_r;
    reg [0:0] start_absolute_sign_delay80_r;
    reg [0:0] start_absolute_sign_delay81_r;
    reg [0:0] start_absolute_sign_delay82_r;
    reg [30:0] start_signed_a1_w_delay83_r;
    reg [30:0] start_signed_b1_w_delay83_r;
    reg [34:0] start_signed_low0_w_delay84_r;
    wire [8:0] stored_signed1_w_d84_r_address_w;
    wire [71:0] unused_stored_signed1_w_d84_r_data_w;
    wire [8:0] stored_signed0_w_d84_r_address_w;
    wire [71:0] unused_stored_signed0_w_d84_r_data_w;
    reg [84:0] valid_r;
    assign plane_valid_o = valid_r[84];
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) valid_r <= 0;
        else if (stop_i) valid_r <= 0;
        else if (enable_i) valid_r <= {valid_r[83:0], plane_valid_i};
    end
    // Enabled-cycle addresses keep RAM delays aligned through backpressure.
    reg [8:0] delay_pointer_r;
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) delay_pointer_r <= 0;
        else if (enable_i) delay_pointer_r <= delay_pointer_r + 1'b1;
    end
    always @(posedge clk_i) begin
        if (enable_i && plane_valid_i && plane_tag_i[2:0] == 0)
            reciprocal_context_r[plane_tag_i[6:3]] <= plane_reciprocal_i;
    end
    always @(posedge clk_i) begin
        if (enable_i && plane_valid_i && plane_tag_i[2:0] == 0)
            exponent_context_r[plane_tag_i[6:3]] <= plane_exponent_i;
    end
    always @(posedge clk_i) begin
        if (enable_i && plane_valid_i && plane_tag_i[2:0] == 0)
            delta_context0_r[plane_tag_i[6:3]] <= plane_delta_i[0 +: 18];
    end
    always @(posedge clk_i) begin
        if (enable_i && plane_valid_i && plane_tag_i[2:0] == 0)
            delta_context1_r[plane_tag_i[6:3]] <= plane_delta_i[18 +: 18];
    end
    always @(posedge clk_i) begin
        if (enable_i && plane_valid_i && plane_tag_i[2:0] == 0)
            delta_context2_r[plane_tag_i[6:3]] <= plane_delta_i[36 +: 18];
    end
    always @(posedge clk_i) begin
        if (enable_i && plane_valid_i && plane_tag_i[2:0] == 0)
            delta_context3_r[plane_tag_i[6:3]] <= plane_delta_i[54 +: 18];
    end
    always @(posedge clk_i) begin
        if (enable_i && plane_valid_i && plane_tag_i[2:0] == 0)
            offset_context0_r[plane_tag_i[6:3]] <= plane_offset_i[0 +: 18];
    end
    always @(posedge clk_i) begin
        if (enable_i && plane_valid_i && plane_tag_i[2:0] == 0)
            offset_context1_r[plane_tag_i[6:3]] <= plane_offset_i[18 +: 18];
    end
    assign vertex0_w = value_0_r[0 +: 51];
    assign vertex1_w = value_0_r[51 +: 51];
    assign vertex2_w = value_0_r[102 +: 51];
    assign v52_0_w = {1'b0, vertex0_w};
    assign scale_left0_amt0_w = left_amount_r[0 +: 2];
    always @(*) begin
        scale_left0_0_w = v52_0_w_d9_r;
        case (scale_left0_amt0_w)
            2'd0: scale_left0_0_w = v52_0_w_d9_r << 0;
            2'd1: scale_left0_0_w = v52_0_w_d9_r << 1;
            2'd2: scale_left0_0_w = v52_0_w_d9_r << 2;
            2'd3: scale_left0_0_w = v52_0_w_d9_r << 3;
            default: scale_left0_0_w = v52_0_w_d9_r;
        endcase
    end
    assign scale_left0_amt1_w = left_amount_r[2 +: 2];
    always @(*) begin
        scale_left0_1_w = scale_left0_0_r;
        case (scale_left0_amt1_w_d10_r)
            2'd0: scale_left0_1_w = scale_left0_0_r << 0;
            2'd1: scale_left0_1_w = scale_left0_0_r << 4;
            2'd2: scale_left0_1_w = scale_left0_0_r << 8;
            2'd3: scale_left0_1_w = scale_left0_0_r << 12;
            default: scale_left0_1_w = scale_left0_0_r;
        endcase
    end
    assign scale_left0_amt2_w = left_amount_r[4 +: 2];
    always @(*) begin
        unused_scale_left0_2_w = scale_left0_1_r;
        case (scale_left0_amt2_w_d11_r)
            2'd0: unused_scale_left0_2_w = scale_left0_1_r << 0;
            2'd1: unused_scale_left0_2_w = scale_left0_1_r << 16;
            2'd2: unused_scale_left0_2_w = scale_left0_1_r << 32;
            2'd3: unused_scale_left0_2_w = scale_left0_1_r << 48;
            default: unused_scale_left0_2_w = scale_left0_1_r;
        endcase
    end
    assign scale_one0_w = 52'd1;
    assign scale_bias0_amt0_w = scale_bit0_r[0 +: 2];
    always @(*) begin
        scale_bias0_0_w = scale_one0_w;
        case (scale_bias0_amt0_w)
            2'd0: scale_bias0_0_w = scale_one0_w << 0;
            2'd1: scale_bias0_0_w = scale_one0_w << 1;
            2'd2: scale_bias0_0_w = scale_one0_w << 2;
            2'd3: scale_bias0_0_w = scale_one0_w << 3;
            default: scale_bias0_0_w = scale_one0_w;
        endcase
    end
    assign scale_bias0_amt1_w = scale_bit0_r[2 +: 2];
    always @(*) begin
        scale_bias0_1_w = scale_bias0_0_r;
        case (scale_bias0_amt1_w_d11_r)
            2'd0: scale_bias0_1_w = scale_bias0_0_r << 0;
            2'd1: scale_bias0_1_w = scale_bias0_0_r << 4;
            2'd2: scale_bias0_1_w = scale_bias0_0_r << 8;
            2'd3: scale_bias0_1_w = scale_bias0_0_r << 12;
            default: scale_bias0_1_w = scale_bias0_0_r;
        endcase
    end
    assign scale_bias0_amt2_w = scale_bit0_r[4 +: 2];
    always @(*) begin
        scale_bias0_2_w = scale_bias0_1_r;
        case (scale_bias0_amt2_w_d12_r)
            2'd0: scale_bias0_2_w = scale_bias0_1_r << 0;
            2'd1: scale_bias0_2_w = scale_bias0_1_r << 16;
            2'd2: scale_bias0_2_w = scale_bias0_1_r << 32;
            2'd3: scale_bias0_2_w = scale_bias0_1_r << 48;
            default: scale_bias0_2_w = scale_bias0_1_r;
        endcase
    end
    assign scale_add0_a0_w = v52_0_w_d13_r[0 +: 35];
    assign scale_add0_b0_w = scale_bias0_2_r[0 +: 35];
    assign scale_add0_low0_w = scale_add0_part0_r[34:0];
    assign scale_add0_a1_w = v52_0_w_d13_r[35 +: 17];
    assign scale_add0_b1_w = scale_bias0_2_r[35 +: 17];
    assign scale_add0_low1_w = scale_add0_part1_r[16:0];
    assign scale_add0_w = {scale_add0_low1_w, scale_add0_low0_w_d15_r};
    assign scale_rounded0_amt0_w = right_amount_r[0 +: 2];
    always @(*) begin
        scale_rounded0_0_w = scale_add0_w;
        case (scale_rounded0_amt0_w_d15_r)
            2'd0: scale_rounded0_0_w = scale_add0_w >> 0;
            2'd1: scale_rounded0_0_w = scale_add0_w >> 1;
            2'd2: scale_rounded0_0_w = scale_add0_w >> 2;
            2'd3: scale_rounded0_0_w = scale_add0_w >> 3;
            default: scale_rounded0_0_w = scale_add0_w;
        endcase
    end
    assign scale_rounded0_amt1_w = right_amount_r[2 +: 2];
    always @(*) begin
        scale_rounded0_1_w = scale_rounded0_0_r;
        case (scale_rounded0_amt1_w_d16_r)
            2'd0: scale_rounded0_1_w = scale_rounded0_0_r >> 0;
            2'd1: scale_rounded0_1_w = scale_rounded0_0_r >> 4;
            2'd2: scale_rounded0_1_w = scale_rounded0_0_r >> 8;
            2'd3: scale_rounded0_1_w = scale_rounded0_0_r >> 12;
            default: scale_rounded0_1_w = scale_rounded0_0_r;
        endcase
    end
    assign scale_rounded0_amt2_w = right_amount_r[4 +: 2];
    always @(*) begin
        unused_scale_rounded0_2_w = scale_rounded0_1_r;
        case (scale_rounded0_amt2_w_d17_r)
            2'd0: unused_scale_rounded0_2_w = scale_rounded0_1_r >> 0;
            2'd1: unused_scale_rounded0_2_w = scale_rounded0_1_r >> 16;
            2'd2: unused_scale_rounded0_2_w = scale_rounded0_1_r >> 32;
            2'd3: unused_scale_rounded0_2_w = scale_rounded0_1_r >> 48;
            default: unused_scale_rounded0_2_w = scale_rounded0_1_r;
        endcase
    end
    assign v52_1_w = {1'b0, vertex1_w};
    assign scale_left1_amt0_w = left_amount_r[0 +: 2];
    always @(*) begin
        scale_left1_0_w = v52_1_w_d9_r;
        case (scale_left1_amt0_w)
            2'd0: scale_left1_0_w = v52_1_w_d9_r << 0;
            2'd1: scale_left1_0_w = v52_1_w_d9_r << 1;
            2'd2: scale_left1_0_w = v52_1_w_d9_r << 2;
            2'd3: scale_left1_0_w = v52_1_w_d9_r << 3;
            default: scale_left1_0_w = v52_1_w_d9_r;
        endcase
    end
    assign scale_left1_amt1_w = left_amount_r[2 +: 2];
    always @(*) begin
        scale_left1_1_w = scale_left1_0_r;
        case (scale_left1_amt1_w_d10_r)
            2'd0: scale_left1_1_w = scale_left1_0_r << 0;
            2'd1: scale_left1_1_w = scale_left1_0_r << 4;
            2'd2: scale_left1_1_w = scale_left1_0_r << 8;
            2'd3: scale_left1_1_w = scale_left1_0_r << 12;
            default: scale_left1_1_w = scale_left1_0_r;
        endcase
    end
    assign scale_left1_amt2_w = left_amount_r[4 +: 2];
    always @(*) begin
        unused_scale_left1_2_w = scale_left1_1_r;
        case (scale_left1_amt2_w_d11_r)
            2'd0: unused_scale_left1_2_w = scale_left1_1_r << 0;
            2'd1: unused_scale_left1_2_w = scale_left1_1_r << 16;
            2'd2: unused_scale_left1_2_w = scale_left1_1_r << 32;
            2'd3: unused_scale_left1_2_w = scale_left1_1_r << 48;
            default: unused_scale_left1_2_w = scale_left1_1_r;
        endcase
    end
    assign scale_one1_w = 52'd1;
    assign scale_bias1_amt0_w = scale_bit1_r[0 +: 2];
    always @(*) begin
        scale_bias1_0_w = scale_one1_w;
        case (scale_bias1_amt0_w)
            2'd0: scale_bias1_0_w = scale_one1_w << 0;
            2'd1: scale_bias1_0_w = scale_one1_w << 1;
            2'd2: scale_bias1_0_w = scale_one1_w << 2;
            2'd3: scale_bias1_0_w = scale_one1_w << 3;
            default: scale_bias1_0_w = scale_one1_w;
        endcase
    end
    assign scale_bias1_amt1_w = scale_bit1_r[2 +: 2];
    always @(*) begin
        scale_bias1_1_w = scale_bias1_0_r;
        case (scale_bias1_amt1_w_d11_r)
            2'd0: scale_bias1_1_w = scale_bias1_0_r << 0;
            2'd1: scale_bias1_1_w = scale_bias1_0_r << 4;
            2'd2: scale_bias1_1_w = scale_bias1_0_r << 8;
            2'd3: scale_bias1_1_w = scale_bias1_0_r << 12;
            default: scale_bias1_1_w = scale_bias1_0_r;
        endcase
    end
    assign scale_bias1_amt2_w = scale_bit1_r[4 +: 2];
    always @(*) begin
        scale_bias1_2_w = scale_bias1_1_r;
        case (scale_bias1_amt2_w_d12_r)
            2'd0: scale_bias1_2_w = scale_bias1_1_r << 0;
            2'd1: scale_bias1_2_w = scale_bias1_1_r << 16;
            2'd2: scale_bias1_2_w = scale_bias1_1_r << 32;
            2'd3: scale_bias1_2_w = scale_bias1_1_r << 48;
            default: scale_bias1_2_w = scale_bias1_1_r;
        endcase
    end
    assign scale_add1_a0_w = v52_1_w_d13_r[0 +: 35];
    assign scale_add1_b0_w = scale_bias1_2_r[0 +: 35];
    assign scale_add1_low0_w = scale_add1_part0_r[34:0];
    assign scale_add1_a1_w = v52_1_w_d13_r[35 +: 17];
    assign scale_add1_b1_w = scale_bias1_2_r[35 +: 17];
    assign scale_add1_low1_w = scale_add1_part1_r[16:0];
    assign scale_add1_w = {scale_add1_low1_w, scale_add1_low0_w_d15_r};
    assign scale_rounded1_amt0_w = right_amount_r[0 +: 2];
    always @(*) begin
        scale_rounded1_0_w = scale_add1_w;
        case (scale_rounded1_amt0_w_d15_r)
            2'd0: scale_rounded1_0_w = scale_add1_w >> 0;
            2'd1: scale_rounded1_0_w = scale_add1_w >> 1;
            2'd2: scale_rounded1_0_w = scale_add1_w >> 2;
            2'd3: scale_rounded1_0_w = scale_add1_w >> 3;
            default: scale_rounded1_0_w = scale_add1_w;
        endcase
    end
    assign scale_rounded1_amt1_w = right_amount_r[2 +: 2];
    always @(*) begin
        scale_rounded1_1_w = scale_rounded1_0_r;
        case (scale_rounded1_amt1_w_d16_r)
            2'd0: scale_rounded1_1_w = scale_rounded1_0_r >> 0;
            2'd1: scale_rounded1_1_w = scale_rounded1_0_r >> 4;
            2'd2: scale_rounded1_1_w = scale_rounded1_0_r >> 8;
            2'd3: scale_rounded1_1_w = scale_rounded1_0_r >> 12;
            default: scale_rounded1_1_w = scale_rounded1_0_r;
        endcase
    end
    assign scale_rounded1_amt2_w = right_amount_r[4 +: 2];
    always @(*) begin
        unused_scale_rounded1_2_w = scale_rounded1_1_r;
        case (scale_rounded1_amt2_w_d17_r)
            2'd0: unused_scale_rounded1_2_w = scale_rounded1_1_r >> 0;
            2'd1: unused_scale_rounded1_2_w = scale_rounded1_1_r >> 16;
            2'd2: unused_scale_rounded1_2_w = scale_rounded1_1_r >> 32;
            2'd3: unused_scale_rounded1_2_w = scale_rounded1_1_r >> 48;
            default: unused_scale_rounded1_2_w = scale_rounded1_1_r;
        endcase
    end
    assign v52_2_w = {1'b0, vertex2_w};
    assign scale_left2_amt0_w = left_amount_r[0 +: 2];
    always @(*) begin
        scale_left2_0_w = v52_2_w_d9_r;
        case (scale_left2_amt0_w)
            2'd0: scale_left2_0_w = v52_2_w_d9_r << 0;
            2'd1: scale_left2_0_w = v52_2_w_d9_r << 1;
            2'd2: scale_left2_0_w = v52_2_w_d9_r << 2;
            2'd3: scale_left2_0_w = v52_2_w_d9_r << 3;
            default: scale_left2_0_w = v52_2_w_d9_r;
        endcase
    end
    assign scale_left2_amt1_w = left_amount_r[2 +: 2];
    always @(*) begin
        scale_left2_1_w = scale_left2_0_r;
        case (scale_left2_amt1_w_d10_r)
            2'd0: scale_left2_1_w = scale_left2_0_r << 0;
            2'd1: scale_left2_1_w = scale_left2_0_r << 4;
            2'd2: scale_left2_1_w = scale_left2_0_r << 8;
            2'd3: scale_left2_1_w = scale_left2_0_r << 12;
            default: scale_left2_1_w = scale_left2_0_r;
        endcase
    end
    assign scale_left2_amt2_w = left_amount_r[4 +: 2];
    always @(*) begin
        unused_scale_left2_2_w = scale_left2_1_r;
        case (scale_left2_amt2_w_d11_r)
            2'd0: unused_scale_left2_2_w = scale_left2_1_r << 0;
            2'd1: unused_scale_left2_2_w = scale_left2_1_r << 16;
            2'd2: unused_scale_left2_2_w = scale_left2_1_r << 32;
            2'd3: unused_scale_left2_2_w = scale_left2_1_r << 48;
            default: unused_scale_left2_2_w = scale_left2_1_r;
        endcase
    end
    assign scale_one2_w = 52'd1;
    assign scale_bias2_amt0_w = scale_bit2_r[0 +: 2];
    always @(*) begin
        scale_bias2_0_w = scale_one2_w;
        case (scale_bias2_amt0_w)
            2'd0: scale_bias2_0_w = scale_one2_w << 0;
            2'd1: scale_bias2_0_w = scale_one2_w << 1;
            2'd2: scale_bias2_0_w = scale_one2_w << 2;
            2'd3: scale_bias2_0_w = scale_one2_w << 3;
            default: scale_bias2_0_w = scale_one2_w;
        endcase
    end
    assign scale_bias2_amt1_w = scale_bit2_r[2 +: 2];
    always @(*) begin
        scale_bias2_1_w = scale_bias2_0_r;
        case (scale_bias2_amt1_w_d11_r)
            2'd0: scale_bias2_1_w = scale_bias2_0_r << 0;
            2'd1: scale_bias2_1_w = scale_bias2_0_r << 4;
            2'd2: scale_bias2_1_w = scale_bias2_0_r << 8;
            2'd3: scale_bias2_1_w = scale_bias2_0_r << 12;
            default: scale_bias2_1_w = scale_bias2_0_r;
        endcase
    end
    assign scale_bias2_amt2_w = scale_bit2_r[4 +: 2];
    always @(*) begin
        scale_bias2_2_w = scale_bias2_1_r;
        case (scale_bias2_amt2_w_d12_r)
            2'd0: scale_bias2_2_w = scale_bias2_1_r << 0;
            2'd1: scale_bias2_2_w = scale_bias2_1_r << 16;
            2'd2: scale_bias2_2_w = scale_bias2_1_r << 32;
            2'd3: scale_bias2_2_w = scale_bias2_1_r << 48;
            default: scale_bias2_2_w = scale_bias2_1_r;
        endcase
    end
    assign scale_add2_a0_w = v52_2_w_d13_r[0 +: 35];
    assign scale_add2_b0_w = scale_bias2_2_r[0 +: 35];
    assign scale_add2_low0_w = scale_add2_part0_r[34:0];
    assign scale_add2_a1_w = v52_2_w_d13_r[35 +: 17];
    assign scale_add2_b1_w = scale_bias2_2_r[35 +: 17];
    assign scale_add2_low1_w = scale_add2_part1_r[16:0];
    assign scale_add2_w = {scale_add2_low1_w, scale_add2_low0_w_d15_r};
    assign scale_rounded2_amt0_w = right_amount_r[0 +: 2];
    always @(*) begin
        scale_rounded2_0_w = scale_add2_w;
        case (scale_rounded2_amt0_w_d15_r)
            2'd0: scale_rounded2_0_w = scale_add2_w >> 0;
            2'd1: scale_rounded2_0_w = scale_add2_w >> 1;
            2'd2: scale_rounded2_0_w = scale_add2_w >> 2;
            2'd3: scale_rounded2_0_w = scale_add2_w >> 3;
            default: scale_rounded2_0_w = scale_add2_w;
        endcase
    end
    assign scale_rounded2_amt1_w = right_amount_r[2 +: 2];
    always @(*) begin
        scale_rounded2_1_w = scale_rounded2_0_r;
        case (scale_rounded2_amt1_w_d16_r)
            2'd0: scale_rounded2_1_w = scale_rounded2_0_r >> 0;
            2'd1: scale_rounded2_1_w = scale_rounded2_0_r >> 4;
            2'd2: scale_rounded2_1_w = scale_rounded2_0_r >> 8;
            2'd3: scale_rounded2_1_w = scale_rounded2_0_r >> 12;
            default: scale_rounded2_1_w = scale_rounded2_0_r;
        endcase
    end
    assign scale_rounded2_amt2_w = right_amount_r[4 +: 2];
    always @(*) begin
        unused_scale_rounded2_2_w = scale_rounded2_1_r;
        case (scale_rounded2_amt2_w_d17_r)
            2'd0: unused_scale_rounded2_2_w = scale_rounded2_1_r >> 0;
            2'd1: unused_scale_rounded2_2_w = scale_rounded2_1_r >> 16;
            2'd2: unused_scale_rounded2_2_w = scale_rounded2_1_r >> 32;
            2'd3: unused_scale_rounded2_2_w = scale_rounded2_1_r >> 48;
            default: unused_scale_rounded2_2_w = scale_rounded2_1_r;
        endcase
    end
    assign delta_context0_r_0_index20_w = tag_0_r_d19_r[6:3];
    assign product0_0_pp0_0_extend_w = {{16{product0_0_pp0_0_r[35]}}, product0_0_pp0_0_r};
    assign product0_0_pp0_0_aligned_w = product0_0_pp0_0_extend_w << 0;
    assign product0_0_pp1_0_extend_w = {{17{product0_0_pp1_0_r[34]}}, product0_0_pp1_0_r};
    assign product0_0_pp1_0_aligned_w = product0_0_pp1_0_extend_w << 17;
    // product0_0: 34 x 18, 2 registered APM products; sliced adder tree.
    assign product0_0_sum0_0_a0_w = product0_0_pp0_0_aligned_w[0 +: 35];
    assign product0_0_sum0_0_b0_w = product0_0_pp1_0_aligned_w[0 +: 35];
    assign product0_0_sum0_0_low0_w = product0_0_sum0_0_part0_r[34:0];
    assign product0_0_sum0_0_a1_w = product0_0_pp0_0_aligned_w[35 +: 17];
    assign product0_0_sum0_0_b1_w = product0_0_pp1_0_aligned_w[35 +: 17];
    assign product0_0_sum0_0_low1_w = product0_0_sum0_0_part1_r[16:0];
    assign product0_0_sum0_0_w = {product0_0_sum0_0_low1_w, product0_0_sum0_0_low0_w_d23_r};
    assign delta_context1_r_0_index20_w = tag_0_r_d19_r[6:3];
    assign product0_1_pp0_0_extend_w = {{16{product0_1_pp0_0_r[35]}}, product0_1_pp0_0_r};
    assign product0_1_pp0_0_aligned_w = product0_1_pp0_0_extend_w << 0;
    assign product0_1_pp1_0_extend_w = {{17{product0_1_pp1_0_r[34]}}, product0_1_pp1_0_r};
    assign product0_1_pp1_0_aligned_w = product0_1_pp1_0_extend_w << 17;
    // product0_1: 34 x 18, 2 registered APM products; sliced adder tree.
    assign product0_1_sum0_0_a0_w = product0_1_pp0_0_aligned_w[0 +: 35];
    assign product0_1_sum0_0_b0_w = product0_1_pp1_0_aligned_w[0 +: 35];
    assign product0_1_sum0_0_low0_w = product0_1_sum0_0_part0_r[34:0];
    assign product0_1_sum0_0_a1_w = product0_1_pp0_0_aligned_w[35 +: 17];
    assign product0_1_sum0_0_b1_w = product0_1_pp1_0_aligned_w[35 +: 17];
    assign product0_1_sum0_0_low1_w = product0_1_sum0_0_part1_r[16:0];
    assign product0_1_sum0_0_w = {product0_1_sum0_0_low1_w, product0_1_sum0_0_low0_w_d23_r};
    assign product_ext0_0_w = {{4{product0_0_sum0_0_w[51]}}, product0_0_sum0_0_w};
    assign product_ext0_1_w = {{4{product0_1_sum0_0_w[51]}}, product0_1_sum0_0_w};
    assign numerator0_a0_w = product_ext0_0_w[0 +: 35];
    assign numerator0_b0_w = product_ext0_1_w[0 +: 35];
    assign numerator0_low0_w = numerator0_part0_r[34:0];
    assign numerator0_a1_w = product_ext0_0_w[35 +: 21];
    assign numerator0_b1_w = product_ext0_1_w[35 +: 21];
    assign numerator0_low1_w = numerator0_part1_r[20:0];
    assign numerator0_w = {numerator0_low1_w, numerator0_low0_w_d25_r};
    assign reciprocal_context_r_0_index26_w = tag_0_r_d25_r[6:3];
    assign inverse0_pp0_0_extend_w = {{51{inverse0_pp0_0_r[35]}}, inverse0_pp0_0_r};
    assign inverse0_pp0_0_aligned_w = inverse0_pp0_0_extend_w << 0;
    assign inverse0_pp0_1_extend_w = {{54{inverse0_pp0_1_r[32]}}, inverse0_pp0_1_r};
    assign inverse0_pp0_1_aligned_w = inverse0_pp0_1_extend_w << 17;
    assign inverse0_pp1_0_extend_w = {{51{inverse0_pp1_0_r[35]}}, inverse0_pp1_0_r};
    assign inverse0_pp1_0_aligned_w = inverse0_pp1_0_extend_w << 17;
    assign inverse0_pp1_1_extend_w = {{54{inverse0_pp1_1_r[32]}}, inverse0_pp1_1_r};
    assign inverse0_pp1_1_aligned_w = inverse0_pp1_1_extend_w << 34;
    assign inverse0_pp2_0_extend_w = {{51{inverse0_pp2_0_r[35]}}, inverse0_pp2_0_r};
    assign inverse0_pp2_0_aligned_w = inverse0_pp2_0_extend_w << 34;
    assign inverse0_pp2_1_extend_w = {{54{inverse0_pp2_1_r[32]}}, inverse0_pp2_1_r};
    assign inverse0_pp2_1_aligned_w = inverse0_pp2_1_extend_w << 51;
    assign inverse0_pp3_0_extend_w = {{64{inverse0_pp3_0_r[22]}}, inverse0_pp3_0_r};
    assign inverse0_pp3_0_aligned_w = inverse0_pp3_0_extend_w << 51;
    assign inverse0_pp3_1_extend_w = {{67{inverse0_pp3_1_r[19]}}, inverse0_pp3_1_r};
    assign inverse0_pp3_1_aligned_w = inverse0_pp3_1_extend_w << 68;
    // inverse0: 56 x 31, 8 registered APM products; sliced adder tree.
    assign inverse0_sum0_0_a0_w = inverse0_pp0_0_aligned_w[0 +: 35];
    assign inverse0_sum0_0_b0_w = inverse0_pp0_1_aligned_w[0 +: 35];
    assign inverse0_sum0_0_low0_w = inverse0_sum0_0_part0_r[34:0];
    assign inverse0_sum0_0_a1_w = inverse0_pp0_0_aligned_w[35 +: 35];
    assign inverse0_sum0_0_b1_w = inverse0_pp0_1_aligned_w[35 +: 35];
    assign inverse0_sum0_0_low1_w = inverse0_sum0_0_part1_r[34:0];
    assign inverse0_sum0_0_a2_w = inverse0_pp0_0_aligned_w[70 +: 17];
    assign inverse0_sum0_0_b2_w = inverse0_pp0_1_aligned_w[70 +: 17];
    assign inverse0_sum0_0_low2_w = inverse0_sum0_0_part2_r[16:0];
    assign inverse0_sum0_0_w = {inverse0_sum0_0_low2_w, inverse0_sum0_0_low1_w_d30_r,
            inverse0_sum0_0_low0_w_d30_r};
    assign inverse0_sum0_1_a0_w = inverse0_pp1_0_aligned_w[0 +: 35];
    assign inverse0_sum0_1_b0_w = inverse0_pp1_1_aligned_w[0 +: 35];
    assign inverse0_sum0_1_low0_w = inverse0_sum0_1_part0_r[34:0];
    assign inverse0_sum0_1_a1_w = inverse0_pp1_0_aligned_w[35 +: 35];
    assign inverse0_sum0_1_b1_w = inverse0_pp1_1_aligned_w[35 +: 35];
    assign inverse0_sum0_1_low1_w = inverse0_sum0_1_part1_r[34:0];
    assign inverse0_sum0_1_a2_w = inverse0_pp1_0_aligned_w[70 +: 17];
    assign inverse0_sum0_1_b2_w = inverse0_pp1_1_aligned_w[70 +: 17];
    assign inverse0_sum0_1_low2_w = inverse0_sum0_1_part2_r[16:0];
    assign inverse0_sum0_1_w = {inverse0_sum0_1_low2_w, inverse0_sum0_1_low1_w_d30_r,
            inverse0_sum0_1_low0_w_d30_r};
    assign inverse0_sum0_2_a0_w = inverse0_pp2_0_aligned_w[0 +: 35];
    assign inverse0_sum0_2_b0_w = inverse0_pp2_1_aligned_w[0 +: 35];
    assign inverse0_sum0_2_low0_w = inverse0_sum0_2_part0_r[34:0];
    assign inverse0_sum0_2_a1_w = inverse0_pp2_0_aligned_w[35 +: 35];
    assign inverse0_sum0_2_b1_w = inverse0_pp2_1_aligned_w[35 +: 35];
    assign inverse0_sum0_2_low1_w = inverse0_sum0_2_part1_r[34:0];
    assign inverse0_sum0_2_a2_w = inverse0_pp2_0_aligned_w[70 +: 17];
    assign inverse0_sum0_2_b2_w = inverse0_pp2_1_aligned_w[70 +: 17];
    assign inverse0_sum0_2_low2_w = inverse0_sum0_2_part2_r[16:0];
    assign inverse0_sum0_2_w = {inverse0_sum0_2_low2_w, inverse0_sum0_2_low1_w_d30_r,
            inverse0_sum0_2_low0_w_d30_r};
    assign inverse0_sum0_3_a0_w = inverse0_pp3_0_aligned_w[0 +: 35];
    assign inverse0_sum0_3_b0_w = inverse0_pp3_1_aligned_w[0 +: 35];
    assign inverse0_sum0_3_low0_w = inverse0_sum0_3_part0_r[34:0];
    assign inverse0_sum0_3_a1_w = inverse0_pp3_0_aligned_w[35 +: 35];
    assign inverse0_sum0_3_b1_w = inverse0_pp3_1_aligned_w[35 +: 35];
    assign inverse0_sum0_3_low1_w = inverse0_sum0_3_part1_r[34:0];
    assign inverse0_sum0_3_a2_w = inverse0_pp3_0_aligned_w[70 +: 17];
    assign inverse0_sum0_3_b2_w = inverse0_pp3_1_aligned_w[70 +: 17];
    assign inverse0_sum0_3_low2_w = inverse0_sum0_3_part2_r[16:0];
    assign inverse0_sum0_3_w = {inverse0_sum0_3_low2_w, inverse0_sum0_3_low1_w_d30_r,
            inverse0_sum0_3_low0_w_d30_r};
    assign inverse0_sum1_0_a0_w = inverse0_sum0_0_w[0 +: 35];
    assign inverse0_sum1_0_b0_w = inverse0_sum0_1_w[0 +: 35];
    assign inverse0_sum1_0_low0_w = inverse0_sum1_0_part0_r[34:0];
    assign inverse0_sum1_0_a1_w = inverse0_sum0_0_w[35 +: 35];
    assign inverse0_sum1_0_b1_w = inverse0_sum0_1_w[35 +: 35];
    assign inverse0_sum1_0_low1_w = inverse0_sum1_0_part1_r[34:0];
    assign inverse0_sum1_0_a2_w = inverse0_sum0_0_w[70 +: 17];
    assign inverse0_sum1_0_b2_w = inverse0_sum0_1_w[70 +: 17];
    assign inverse0_sum1_0_low2_w = inverse0_sum1_0_part2_r[16:0];
    assign inverse0_sum1_0_w = {inverse0_sum1_0_low2_w, inverse0_sum1_0_low1_w_d33_r,
            inverse0_sum1_0_low0_w_d33_r};
    assign inverse0_sum1_1_a0_w = inverse0_sum0_2_w[0 +: 35];
    assign inverse0_sum1_1_b0_w = inverse0_sum0_3_w[0 +: 35];
    assign inverse0_sum1_1_low0_w = inverse0_sum1_1_part0_r[34:0];
    assign inverse0_sum1_1_a1_w = inverse0_sum0_2_w[35 +: 35];
    assign inverse0_sum1_1_b1_w = inverse0_sum0_3_w[35 +: 35];
    assign inverse0_sum1_1_low1_w = inverse0_sum1_1_part1_r[34:0];
    assign inverse0_sum1_1_a2_w = inverse0_sum0_2_w[70 +: 17];
    assign inverse0_sum1_1_b2_w = inverse0_sum0_3_w[70 +: 17];
    assign inverse0_sum1_1_low2_w = inverse0_sum1_1_part2_r[16:0];
    assign inverse0_sum1_1_w = {inverse0_sum1_1_low2_w, inverse0_sum1_1_low1_w_d33_r,
            inverse0_sum1_1_low0_w_d33_r};
    assign inverse0_sum2_0_a0_w = inverse0_sum1_0_w[0 +: 35];
    assign inverse0_sum2_0_b0_w = inverse0_sum1_1_w[0 +: 35];
    assign inverse0_sum2_0_low0_w = inverse0_sum2_0_part0_r[34:0];
    assign inverse0_sum2_0_a1_w = inverse0_sum1_0_w[35 +: 35];
    assign inverse0_sum2_0_b1_w = inverse0_sum1_1_w[35 +: 35];
    assign inverse0_sum2_0_low1_w = inverse0_sum2_0_part1_r[34:0];
    assign inverse0_sum2_0_a2_w = inverse0_sum1_0_w[70 +: 17];
    assign inverse0_sum2_0_b2_w = inverse0_sum1_1_w[70 +: 17];
    assign inverse0_sum2_0_low2_w = inverse0_sum2_0_part2_r[16:0];
    assign inverse0_sum2_0_w = {inverse0_sum2_0_low2_w, inverse0_sum2_0_low1_w_d36_r,
            inverse0_sum2_0_low0_w_d36_r};
    assign inverse_abs0_carry_w = {86'b0, inverse_abs0_sign_r};
    assign inverse_abs0_a0_w = inverse_abs0_invert_r[0 +: 35];
    assign inverse_abs0_b0_w = inverse_abs0_carry_w[0 +: 35];
    assign inverse_abs0_low0_w = inverse_abs0_part0_r[34:0];
    assign inverse_abs0_a1_w = inverse_abs0_invert_r[35 +: 35];
    assign inverse_abs0_b1_w = inverse_abs0_carry_w[35 +: 35];
    assign inverse_abs0_low1_w = inverse_abs0_part1_r[34:0];
    assign inverse_abs0_a2_w = inverse_abs0_invert_r[70 +: 17];
    assign inverse_abs0_b2_w = inverse_abs0_carry_w[70 +: 17];
    assign inverse_abs0_low2_w = inverse_abs0_part2_r[16:0];
    assign inverse_abs0_w = {inverse_abs0_low2_w, inverse_abs0_low1_w_d40_r,
            inverse_abs0_low0_w_d40_r};
    assign exponent_context_r_0_index1_w = tag_0_r[6:3];
    assign gradient_one0_w = 88'd1;
    assign gradient_bias0_amt0_w = rounding_bit0_r[0 +: 2];
    always @(*) begin
        gradient_bias0_0_w = gradient_one0_w;
        case (gradient_bias0_amt0_w)
            2'd0: gradient_bias0_0_w = gradient_one0_w << 0;
            2'd1: gradient_bias0_0_w = gradient_one0_w << 1;
            2'd2: gradient_bias0_0_w = gradient_one0_w << 2;
            2'd3: gradient_bias0_0_w = gradient_one0_w << 3;
            default: gradient_bias0_0_w = gradient_one0_w;
        endcase
    end
    assign gradient_bias0_amt1_w = rounding_bit0_r[2 +: 2];
    always @(*) begin
        gradient_bias0_1_w = gradient_bias0_0_r;
        case (gradient_bias0_amt1_w_d3_r)
            2'd0: gradient_bias0_1_w = gradient_bias0_0_r << 0;
            2'd1: gradient_bias0_1_w = gradient_bias0_0_r << 4;
            2'd2: gradient_bias0_1_w = gradient_bias0_0_r << 8;
            2'd3: gradient_bias0_1_w = gradient_bias0_0_r << 12;
            default: gradient_bias0_1_w = gradient_bias0_0_r;
        endcase
    end
    assign gradient_bias0_amt2_w = rounding_bit0_r[4 +: 2];
    always @(*) begin
        gradient_bias0_2_w = gradient_bias0_1_r;
        case (gradient_bias0_amt2_w_d4_r)
            2'd0: gradient_bias0_2_w = gradient_bias0_1_r << 0;
            2'd1: gradient_bias0_2_w = gradient_bias0_1_r << 16;
            2'd2: gradient_bias0_2_w = gradient_bias0_1_r << 32;
            2'd3: gradient_bias0_2_w = gradient_bias0_1_r << 48;
            default: gradient_bias0_2_w = gradient_bias0_1_r;
        endcase
    end
    assign gradient_bias0_amt3_w = rounding_bit0_r[6 +: 1];
    always @(*) begin
        gradient_bias0_3_w = gradient_bias0_2_r;
        case (gradient_bias0_amt3_w_d5_r)
            1'd0: gradient_bias0_3_w = gradient_bias0_2_r << 0;
            1'd1: gradient_bias0_3_w = gradient_bias0_2_r << 64;
            default: gradient_bias0_3_w = gradient_bias0_2_r;
        endcase
    end
    assign mag88_0_w = {1'b0, inverse_abs0_w};
    assign gradient_round0_a0_w = mag88_0_w[0 +: 35];
    assign gradient_round0_b0_w = gradient_bias0_3_r_d40_r[0 +: 35];
    assign gradient_round0_low0_w = gradient_round0_part0_r[34:0];
    assign gradient_round0_a1_w = mag88_0_w[35 +: 35];
    assign gradient_round0_b1_w = gradient_bias0_3_r_d40_r[35 +: 35];
    assign gradient_round0_low1_w = gradient_round0_part1_r[34:0];
    assign gradient_round0_a2_w = mag88_0_w[70 +: 18];
    assign gradient_round0_b2_w = gradient_bias0_3_r_d40_r[70 +: 18];
    assign gradient_round0_low2_w = gradient_round0_part2_r[17:0];
    assign gradient_round0_w = {gradient_round0_low2_w, gradient_round0_low1_w_d43_r,
            gradient_round0_low0_w_d43_r};
    assign gradient_shift0_amt0_w = rounding_shift0_r[0 +: 2];
    always @(*) begin
        gradient_shift0_0_w = gradient_round0_w;
        case (gradient_shift0_amt0_w_d43_r)
            2'd0: gradient_shift0_0_w = gradient_round0_w >> 0;
            2'd1: gradient_shift0_0_w = gradient_round0_w >> 1;
            2'd2: gradient_shift0_0_w = gradient_round0_w >> 2;
            2'd3: gradient_shift0_0_w = gradient_round0_w >> 3;
            default: gradient_shift0_0_w = gradient_round0_w;
        endcase
    end
    assign gradient_shift0_amt1_w = rounding_shift0_r[2 +: 2];
    always @(*) begin
        gradient_shift0_1_w = gradient_shift0_0_r;
        case (gradient_shift0_amt1_w_d44_r)
            2'd0: gradient_shift0_1_w = gradient_shift0_0_r >> 0;
            2'd1: gradient_shift0_1_w = gradient_shift0_0_r >> 4;
            2'd2: gradient_shift0_1_w = gradient_shift0_0_r >> 8;
            2'd3: gradient_shift0_1_w = gradient_shift0_0_r >> 12;
            default: gradient_shift0_1_w = gradient_shift0_0_r;
        endcase
    end
    assign gradient_shift0_amt2_w = rounding_shift0_r[4 +: 2];
    always @(*) begin
        gradient_shift0_2_w = gradient_shift0_1_r;
        case (gradient_shift0_amt2_w_d45_r)
            2'd0: gradient_shift0_2_w = gradient_shift0_1_r >> 0;
            2'd1: gradient_shift0_2_w = gradient_shift0_1_r >> 16;
            2'd2: gradient_shift0_2_w = gradient_shift0_1_r >> 32;
            2'd3: gradient_shift0_2_w = gradient_shift0_1_r >> 48;
            default: gradient_shift0_2_w = gradient_shift0_1_r;
        endcase
    end
    assign gradient_shift0_amt3_w = rounding_shift0_r[6 +: 1];
    always @(*) begin
        unused_gradient_shift0_3_w = gradient_shift0_2_r;
        case (gradient_shift0_amt3_w_d46_r)
            1'd0: unused_gradient_shift0_3_w = gradient_shift0_2_r >> 0;
            1'd1: unused_gradient_shift0_3_w = gradient_shift0_2_r >> 64;
            default: unused_gradient_shift0_3_w = gradient_shift0_2_r;
        endcase
    end
    assign gradient56_0_w = gradient_shift0_3_r[55:0];
    assign gradient_signed0_carry_w = {55'b0, inverse_abs0_sign_d48_r};
    assign gradient_signed0_a0_w = gradient_signed0_invert_r[0 +: 35];
    assign gradient_signed0_b0_w = gradient_signed0_carry_w[0 +: 35];
    assign gradient_signed0_low0_w = gradient_signed0_part0_r[34:0];
    assign gradient_signed0_a1_w = gradient_signed0_invert_r[35 +: 21];
    assign gradient_signed0_b1_w = gradient_signed0_carry_w[35 +: 21];
    assign gradient_signed0_low1_w = gradient_signed0_part1_r[20:0];
    assign gradient_signed0_w = {gradient_signed0_low1_w, gradient_signed0_low0_w_d50_r};
    assign offset_context0_r_0_index50_w = tag_0_r_d49_r[6:3];
    assign origin_product0_pp0_0_extend_w = {{38{origin_product0_pp0_0_r[35]}},
            origin_product0_pp0_0_r};
    assign origin_product0_pp0_0_aligned_w = origin_product0_pp0_0_extend_w << 0;
    assign origin_product0_pp1_0_extend_w = {{38{origin_product0_pp1_0_r[35]}},
            origin_product0_pp1_0_r};
    assign origin_product0_pp1_0_aligned_w = origin_product0_pp1_0_extend_w << 17;
    assign origin_product0_pp2_0_extend_w = {{38{origin_product0_pp2_0_r[35]}},
            origin_product0_pp2_0_r};
    assign origin_product0_pp2_0_aligned_w = origin_product0_pp2_0_extend_w << 34;
    assign origin_product0_pp3_0_extend_w = {{51{origin_product0_pp3_0_r[22]}},
            origin_product0_pp3_0_r};
    assign origin_product0_pp3_0_aligned_w = origin_product0_pp3_0_extend_w << 51;
    // origin_product0: 56 x 18, 4 registered APM products; sliced adder tree.
    assign origin_product0_sum0_0_a0_w = origin_product0_pp0_0_aligned_w[0 +: 35];
    assign origin_product0_sum0_0_b0_w = origin_product0_pp1_0_aligned_w[0 +: 35];
    assign origin_product0_sum0_0_low0_w = origin_product0_sum0_0_part0_r[34:0];
    assign origin_product0_sum0_0_a1_w = origin_product0_pp0_0_aligned_w[35 +: 35];
    assign origin_product0_sum0_0_b1_w = origin_product0_pp1_0_aligned_w[35 +: 35];
    assign origin_product0_sum0_0_low1_w = origin_product0_sum0_0_part1_r[34:0];
    assign origin_product0_sum0_0_a2_w = origin_product0_pp0_0_aligned_w[70 +: 4];
    assign origin_product0_sum0_0_b2_w = origin_product0_pp1_0_aligned_w[70 +: 4];
    assign origin_product0_sum0_0_low2_w = origin_product0_sum0_0_part2_r[3:0];
    assign origin_product0_sum0_0_w = {origin_product0_sum0_0_low2_w,
            origin_product0_sum0_0_low1_w_d54_r, origin_product0_sum0_0_low0_w_d54_r};
    assign origin_product0_sum0_1_a0_w = origin_product0_pp2_0_aligned_w[0 +: 35];
    assign origin_product0_sum0_1_b0_w = origin_product0_pp3_0_aligned_w[0 +: 35];
    assign origin_product0_sum0_1_low0_w = origin_product0_sum0_1_part0_r[34:0];
    assign origin_product0_sum0_1_a1_w = origin_product0_pp2_0_aligned_w[35 +: 35];
    assign origin_product0_sum0_1_b1_w = origin_product0_pp3_0_aligned_w[35 +: 35];
    assign origin_product0_sum0_1_low1_w = origin_product0_sum0_1_part1_r[34:0];
    assign origin_product0_sum0_1_a2_w = origin_product0_pp2_0_aligned_w[70 +: 4];
    assign origin_product0_sum0_1_b2_w = origin_product0_pp3_0_aligned_w[70 +: 4];
    assign origin_product0_sum0_1_low2_w = origin_product0_sum0_1_part2_r[3:0];
    assign origin_product0_sum0_1_w = {origin_product0_sum0_1_low2_w,
            origin_product0_sum0_1_low1_w_d54_r, origin_product0_sum0_1_low0_w_d54_r};
    assign origin_product0_sum1_0_a0_w = origin_product0_sum0_0_w[0 +: 35];
    assign origin_product0_sum1_0_b0_w = origin_product0_sum0_1_w[0 +: 35];
    assign origin_product0_sum1_0_low0_w = origin_product0_sum1_0_part0_r[34:0];
    assign origin_product0_sum1_0_a1_w = origin_product0_sum0_0_w[35 +: 35];
    assign origin_product0_sum1_0_b1_w = origin_product0_sum0_1_w[35 +: 35];
    assign origin_product0_sum1_0_low1_w = origin_product0_sum1_0_part1_r[34:0];
    assign origin_product0_sum1_0_a2_w = origin_product0_sum0_0_w[70 +: 4];
    assign origin_product0_sum1_0_b2_w = origin_product0_sum0_1_w[70 +: 4];
    assign origin_product0_sum1_0_low2_w = origin_product0_sum1_0_part2_r[3:0];
    assign origin_product0_sum1_0_w = {origin_product0_sum1_0_low2_w,
            origin_product0_sum1_0_low1_w_d57_r, origin_product0_sum1_0_low0_w_d57_r};
    assign gradient_abs0_carry_w = {55'b0, gradient_abs0_sign_r};
    assign gradient_abs0_a0_w = gradient_abs0_invert_r[0 +: 35];
    assign gradient_abs0_b0_w = gradient_abs0_carry_w[0 +: 35];
    assign gradient_abs0_low0_w = gradient_abs0_part0_r[34:0];
    assign gradient_abs0_a1_w = gradient_abs0_invert_r[35 +: 21];
    assign gradient_abs0_b1_w = gradient_abs0_carry_w[35 +: 21];
    assign gradient_abs0_low1_w = gradient_abs0_part1_r[20:0];
    assign gradient_abs0_w = {gradient_abs0_low1_w, gradient_abs0_low0_w_d53_r};
    assign gradient_drop0_amt0_w = drop_gradient0_r[0 +: 2];
    always @(*) begin
        gradient_drop0_0_w = gradient_abs0_w;
        case (gradient_drop0_amt0_w_d53_r)
            2'd0: gradient_drop0_0_w = gradient_abs0_w >> 0;
            2'd1: gradient_drop0_0_w = gradient_abs0_w >> 1;
            2'd2: gradient_drop0_0_w = gradient_abs0_w >> 2;
            2'd3: gradient_drop0_0_w = gradient_abs0_w >> 3;
            default: gradient_drop0_0_w = gradient_abs0_w;
        endcase
    end
    assign gradient_drop0_amt1_w = drop_gradient0_r[2 +: 2];
    always @(*) begin
        unused_gradient_drop0_1_w = gradient_drop0_0_r;
        case (gradient_drop0_amt1_w_d54_r)
            2'd0: unused_gradient_drop0_1_w = gradient_drop0_0_r >> 0;
            2'd1: unused_gradient_drop0_1_w = gradient_drop0_0_r >> 4;
            2'd2: unused_gradient_drop0_1_w = gradient_drop0_0_r >> 8;
            2'd3: unused_gradient_drop0_1_w = gradient_drop0_0_r >> 12;
            default: unused_gradient_drop0_1_w = gradient_drop0_0_r;
        endcase
    end
    assign stored52_0_w = gradient_drop0_1_r[52:1];
    assign stored_bit0_w = {51'b0, gradient_drop0_1_r[0]};
    assign stored_round0_a0_w = stored52_0_w[0 +: 35];
    assign stored_round0_b0_w = stored_bit0_w[0 +: 35];
    assign stored_round0_low0_w = stored_round0_part0_r[34:0];
    assign stored_round0_a1_w = stored52_0_w[35 +: 17];
    assign stored_round0_b1_w = stored_bit0_w[35 +: 17];
    assign stored_round0_low1_w = stored_round0_part1_r[16:0];
    assign stored_round0_w = {stored_round0_low1_w, stored_round0_low0_w_d57_r};
    assign stored_signed0_carry_w = {51'b0, gradient_abs0_sign_d58_r};
    assign stored_signed0_a0_w = stored_signed0_invert_r[0 +: 35];
    assign stored_signed0_b0_w = stored_signed0_carry_w[0 +: 35];
    assign stored_signed0_low0_w = stored_signed0_part0_r[34:0];
    assign stored_signed0_a1_w = stored_signed0_invert_r[35 +: 17];
    assign stored_signed0_b1_w = stored_signed0_carry_w[35 +: 17];
    assign stored_signed0_low1_w = stored_signed0_part1_r[16:0];
    assign stored_signed0_w = {stored_signed0_low1_w, stored_signed0_low0_w_d60_r};
    assign delta_context2_r_0_index20_w = tag_0_r_d19_r[6:3];
    assign product1_0_pp0_0_extend_w = {{16{product1_0_pp0_0_r[35]}}, product1_0_pp0_0_r};
    assign product1_0_pp0_0_aligned_w = product1_0_pp0_0_extend_w << 0;
    assign product1_0_pp1_0_extend_w = {{17{product1_0_pp1_0_r[34]}}, product1_0_pp1_0_r};
    assign product1_0_pp1_0_aligned_w = product1_0_pp1_0_extend_w << 17;
    // product1_0: 34 x 18, 2 registered APM products; sliced adder tree.
    assign product1_0_sum0_0_a0_w = product1_0_pp0_0_aligned_w[0 +: 35];
    assign product1_0_sum0_0_b0_w = product1_0_pp1_0_aligned_w[0 +: 35];
    assign product1_0_sum0_0_low0_w = product1_0_sum0_0_part0_r[34:0];
    assign product1_0_sum0_0_a1_w = product1_0_pp0_0_aligned_w[35 +: 17];
    assign product1_0_sum0_0_b1_w = product1_0_pp1_0_aligned_w[35 +: 17];
    assign product1_0_sum0_0_low1_w = product1_0_sum0_0_part1_r[16:0];
    assign product1_0_sum0_0_w = {product1_0_sum0_0_low1_w, product1_0_sum0_0_low0_w_d23_r};
    assign delta_context3_r_0_index20_w = tag_0_r_d19_r[6:3];
    assign product1_1_pp0_0_extend_w = {{16{product1_1_pp0_0_r[35]}}, product1_1_pp0_0_r};
    assign product1_1_pp0_0_aligned_w = product1_1_pp0_0_extend_w << 0;
    assign product1_1_pp1_0_extend_w = {{17{product1_1_pp1_0_r[34]}}, product1_1_pp1_0_r};
    assign product1_1_pp1_0_aligned_w = product1_1_pp1_0_extend_w << 17;
    // product1_1: 34 x 18, 2 registered APM products; sliced adder tree.
    assign product1_1_sum0_0_a0_w = product1_1_pp0_0_aligned_w[0 +: 35];
    assign product1_1_sum0_0_b0_w = product1_1_pp1_0_aligned_w[0 +: 35];
    assign product1_1_sum0_0_low0_w = product1_1_sum0_0_part0_r[34:0];
    assign product1_1_sum0_0_a1_w = product1_1_pp0_0_aligned_w[35 +: 17];
    assign product1_1_sum0_0_b1_w = product1_1_pp1_0_aligned_w[35 +: 17];
    assign product1_1_sum0_0_low1_w = product1_1_sum0_0_part1_r[16:0];
    assign product1_1_sum0_0_w = {product1_1_sum0_0_low1_w, product1_1_sum0_0_low0_w_d23_r};
    assign product_ext1_0_w = {{4{product1_0_sum0_0_w[51]}}, product1_0_sum0_0_w};
    assign product_ext1_1_w = {{4{product1_1_sum0_0_w[51]}}, product1_1_sum0_0_w};
    assign numerator1_a0_w = product_ext1_0_w[0 +: 35];
    assign numerator1_b0_w = product_ext1_1_w[0 +: 35];
    assign numerator1_low0_w = numerator1_part0_r[34:0];
    assign numerator1_a1_w = product_ext1_0_w[35 +: 21];
    assign numerator1_b1_w = product_ext1_1_w[35 +: 21];
    assign numerator1_low1_w = numerator1_part1_r[20:0];
    assign numerator1_w = {numerator1_low1_w, numerator1_low0_w_d25_r};
    assign inverse1_pp0_0_extend_w = {{51{inverse1_pp0_0_r[35]}}, inverse1_pp0_0_r};
    assign inverse1_pp0_0_aligned_w = inverse1_pp0_0_extend_w << 0;
    assign inverse1_pp0_1_extend_w = {{54{inverse1_pp0_1_r[32]}}, inverse1_pp0_1_r};
    assign inverse1_pp0_1_aligned_w = inverse1_pp0_1_extend_w << 17;
    assign inverse1_pp1_0_extend_w = {{51{inverse1_pp1_0_r[35]}}, inverse1_pp1_0_r};
    assign inverse1_pp1_0_aligned_w = inverse1_pp1_0_extend_w << 17;
    assign inverse1_pp1_1_extend_w = {{54{inverse1_pp1_1_r[32]}}, inverse1_pp1_1_r};
    assign inverse1_pp1_1_aligned_w = inverse1_pp1_1_extend_w << 34;
    assign inverse1_pp2_0_extend_w = {{51{inverse1_pp2_0_r[35]}}, inverse1_pp2_0_r};
    assign inverse1_pp2_0_aligned_w = inverse1_pp2_0_extend_w << 34;
    assign inverse1_pp2_1_extend_w = {{54{inverse1_pp2_1_r[32]}}, inverse1_pp2_1_r};
    assign inverse1_pp2_1_aligned_w = inverse1_pp2_1_extend_w << 51;
    assign inverse1_pp3_0_extend_w = {{64{inverse1_pp3_0_r[22]}}, inverse1_pp3_0_r};
    assign inverse1_pp3_0_aligned_w = inverse1_pp3_0_extend_w << 51;
    assign inverse1_pp3_1_extend_w = {{67{inverse1_pp3_1_r[19]}}, inverse1_pp3_1_r};
    assign inverse1_pp3_1_aligned_w = inverse1_pp3_1_extend_w << 68;
    // inverse1: 56 x 31, 8 registered APM products; sliced adder tree.
    assign inverse1_sum0_0_a0_w = inverse1_pp0_0_aligned_w[0 +: 35];
    assign inverse1_sum0_0_b0_w = inverse1_pp0_1_aligned_w[0 +: 35];
    assign inverse1_sum0_0_low0_w = inverse1_sum0_0_part0_r[34:0];
    assign inverse1_sum0_0_a1_w = inverse1_pp0_0_aligned_w[35 +: 35];
    assign inverse1_sum0_0_b1_w = inverse1_pp0_1_aligned_w[35 +: 35];
    assign inverse1_sum0_0_low1_w = inverse1_sum0_0_part1_r[34:0];
    assign inverse1_sum0_0_a2_w = inverse1_pp0_0_aligned_w[70 +: 17];
    assign inverse1_sum0_0_b2_w = inverse1_pp0_1_aligned_w[70 +: 17];
    assign inverse1_sum0_0_low2_w = inverse1_sum0_0_part2_r[16:0];
    assign inverse1_sum0_0_w = {inverse1_sum0_0_low2_w, inverse1_sum0_0_low1_w_d30_r,
            inverse1_sum0_0_low0_w_d30_r};
    assign inverse1_sum0_1_a0_w = inverse1_pp1_0_aligned_w[0 +: 35];
    assign inverse1_sum0_1_b0_w = inverse1_pp1_1_aligned_w[0 +: 35];
    assign inverse1_sum0_1_low0_w = inverse1_sum0_1_part0_r[34:0];
    assign inverse1_sum0_1_a1_w = inverse1_pp1_0_aligned_w[35 +: 35];
    assign inverse1_sum0_1_b1_w = inverse1_pp1_1_aligned_w[35 +: 35];
    assign inverse1_sum0_1_low1_w = inverse1_sum0_1_part1_r[34:0];
    assign inverse1_sum0_1_a2_w = inverse1_pp1_0_aligned_w[70 +: 17];
    assign inverse1_sum0_1_b2_w = inverse1_pp1_1_aligned_w[70 +: 17];
    assign inverse1_sum0_1_low2_w = inverse1_sum0_1_part2_r[16:0];
    assign inverse1_sum0_1_w = {inverse1_sum0_1_low2_w, inverse1_sum0_1_low1_w_d30_r,
            inverse1_sum0_1_low0_w_d30_r};
    assign inverse1_sum0_2_a0_w = inverse1_pp2_0_aligned_w[0 +: 35];
    assign inverse1_sum0_2_b0_w = inverse1_pp2_1_aligned_w[0 +: 35];
    assign inverse1_sum0_2_low0_w = inverse1_sum0_2_part0_r[34:0];
    assign inverse1_sum0_2_a1_w = inverse1_pp2_0_aligned_w[35 +: 35];
    assign inverse1_sum0_2_b1_w = inverse1_pp2_1_aligned_w[35 +: 35];
    assign inverse1_sum0_2_low1_w = inverse1_sum0_2_part1_r[34:0];
    assign inverse1_sum0_2_a2_w = inverse1_pp2_0_aligned_w[70 +: 17];
    assign inverse1_sum0_2_b2_w = inverse1_pp2_1_aligned_w[70 +: 17];
    assign inverse1_sum0_2_low2_w = inverse1_sum0_2_part2_r[16:0];
    assign inverse1_sum0_2_w = {inverse1_sum0_2_low2_w, inverse1_sum0_2_low1_w_d30_r,
            inverse1_sum0_2_low0_w_d30_r};
    assign inverse1_sum0_3_a0_w = inverse1_pp3_0_aligned_w[0 +: 35];
    assign inverse1_sum0_3_b0_w = inverse1_pp3_1_aligned_w[0 +: 35];
    assign inverse1_sum0_3_low0_w = inverse1_sum0_3_part0_r[34:0];
    assign inverse1_sum0_3_a1_w = inverse1_pp3_0_aligned_w[35 +: 35];
    assign inverse1_sum0_3_b1_w = inverse1_pp3_1_aligned_w[35 +: 35];
    assign inverse1_sum0_3_low1_w = inverse1_sum0_3_part1_r[34:0];
    assign inverse1_sum0_3_a2_w = inverse1_pp3_0_aligned_w[70 +: 17];
    assign inverse1_sum0_3_b2_w = inverse1_pp3_1_aligned_w[70 +: 17];
    assign inverse1_sum0_3_low2_w = inverse1_sum0_3_part2_r[16:0];
    assign inverse1_sum0_3_w = {inverse1_sum0_3_low2_w, inverse1_sum0_3_low1_w_d30_r,
            inverse1_sum0_3_low0_w_d30_r};
    assign inverse1_sum1_0_a0_w = inverse1_sum0_0_w[0 +: 35];
    assign inverse1_sum1_0_b0_w = inverse1_sum0_1_w[0 +: 35];
    assign inverse1_sum1_0_low0_w = inverse1_sum1_0_part0_r[34:0];
    assign inverse1_sum1_0_a1_w = inverse1_sum0_0_w[35 +: 35];
    assign inverse1_sum1_0_b1_w = inverse1_sum0_1_w[35 +: 35];
    assign inverse1_sum1_0_low1_w = inverse1_sum1_0_part1_r[34:0];
    assign inverse1_sum1_0_a2_w = inverse1_sum0_0_w[70 +: 17];
    assign inverse1_sum1_0_b2_w = inverse1_sum0_1_w[70 +: 17];
    assign inverse1_sum1_0_low2_w = inverse1_sum1_0_part2_r[16:0];
    assign inverse1_sum1_0_w = {inverse1_sum1_0_low2_w, inverse1_sum1_0_low1_w_d33_r,
            inverse1_sum1_0_low0_w_d33_r};
    assign inverse1_sum1_1_a0_w = inverse1_sum0_2_w[0 +: 35];
    assign inverse1_sum1_1_b0_w = inverse1_sum0_3_w[0 +: 35];
    assign inverse1_sum1_1_low0_w = inverse1_sum1_1_part0_r[34:0];
    assign inverse1_sum1_1_a1_w = inverse1_sum0_2_w[35 +: 35];
    assign inverse1_sum1_1_b1_w = inverse1_sum0_3_w[35 +: 35];
    assign inverse1_sum1_1_low1_w = inverse1_sum1_1_part1_r[34:0];
    assign inverse1_sum1_1_a2_w = inverse1_sum0_2_w[70 +: 17];
    assign inverse1_sum1_1_b2_w = inverse1_sum0_3_w[70 +: 17];
    assign inverse1_sum1_1_low2_w = inverse1_sum1_1_part2_r[16:0];
    assign inverse1_sum1_1_w = {inverse1_sum1_1_low2_w, inverse1_sum1_1_low1_w_d33_r,
            inverse1_sum1_1_low0_w_d33_r};
    assign inverse1_sum2_0_a0_w = inverse1_sum1_0_w[0 +: 35];
    assign inverse1_sum2_0_b0_w = inverse1_sum1_1_w[0 +: 35];
    assign inverse1_sum2_0_low0_w = inverse1_sum2_0_part0_r[34:0];
    assign inverse1_sum2_0_a1_w = inverse1_sum1_0_w[35 +: 35];
    assign inverse1_sum2_0_b1_w = inverse1_sum1_1_w[35 +: 35];
    assign inverse1_sum2_0_low1_w = inverse1_sum2_0_part1_r[34:0];
    assign inverse1_sum2_0_a2_w = inverse1_sum1_0_w[70 +: 17];
    assign inverse1_sum2_0_b2_w = inverse1_sum1_1_w[70 +: 17];
    assign inverse1_sum2_0_low2_w = inverse1_sum2_0_part2_r[16:0];
    assign inverse1_sum2_0_w = {inverse1_sum2_0_low2_w, inverse1_sum2_0_low1_w_d36_r,
            inverse1_sum2_0_low0_w_d36_r};
    assign inverse_abs1_carry_w = {86'b0, inverse_abs1_sign_r};
    assign inverse_abs1_a0_w = inverse_abs1_invert_r[0 +: 35];
    assign inverse_abs1_b0_w = inverse_abs1_carry_w[0 +: 35];
    assign inverse_abs1_low0_w = inverse_abs1_part0_r[34:0];
    assign inverse_abs1_a1_w = inverse_abs1_invert_r[35 +: 35];
    assign inverse_abs1_b1_w = inverse_abs1_carry_w[35 +: 35];
    assign inverse_abs1_low1_w = inverse_abs1_part1_r[34:0];
    assign inverse_abs1_a2_w = inverse_abs1_invert_r[70 +: 17];
    assign inverse_abs1_b2_w = inverse_abs1_carry_w[70 +: 17];
    assign inverse_abs1_low2_w = inverse_abs1_part2_r[16:0];
    assign inverse_abs1_w = {inverse_abs1_low2_w, inverse_abs1_low1_w_d40_r,
            inverse_abs1_low0_w_d40_r};
    assign gradient_one1_w = 88'd1;
    assign gradient_bias1_amt0_w = rounding_bit1_r[0 +: 2];
    always @(*) begin
        gradient_bias1_0_w = gradient_one1_w;
        case (gradient_bias1_amt0_w)
            2'd0: gradient_bias1_0_w = gradient_one1_w << 0;
            2'd1: gradient_bias1_0_w = gradient_one1_w << 1;
            2'd2: gradient_bias1_0_w = gradient_one1_w << 2;
            2'd3: gradient_bias1_0_w = gradient_one1_w << 3;
            default: gradient_bias1_0_w = gradient_one1_w;
        endcase
    end
    assign gradient_bias1_amt1_w = rounding_bit1_r[2 +: 2];
    always @(*) begin
        gradient_bias1_1_w = gradient_bias1_0_r;
        case (gradient_bias1_amt1_w_d3_r)
            2'd0: gradient_bias1_1_w = gradient_bias1_0_r << 0;
            2'd1: gradient_bias1_1_w = gradient_bias1_0_r << 4;
            2'd2: gradient_bias1_1_w = gradient_bias1_0_r << 8;
            2'd3: gradient_bias1_1_w = gradient_bias1_0_r << 12;
            default: gradient_bias1_1_w = gradient_bias1_0_r;
        endcase
    end
    assign gradient_bias1_amt2_w = rounding_bit1_r[4 +: 2];
    always @(*) begin
        gradient_bias1_2_w = gradient_bias1_1_r;
        case (gradient_bias1_amt2_w_d4_r)
            2'd0: gradient_bias1_2_w = gradient_bias1_1_r << 0;
            2'd1: gradient_bias1_2_w = gradient_bias1_1_r << 16;
            2'd2: gradient_bias1_2_w = gradient_bias1_1_r << 32;
            2'd3: gradient_bias1_2_w = gradient_bias1_1_r << 48;
            default: gradient_bias1_2_w = gradient_bias1_1_r;
        endcase
    end
    assign gradient_bias1_amt3_w = rounding_bit1_r[6 +: 1];
    always @(*) begin
        gradient_bias1_3_w = gradient_bias1_2_r;
        case (gradient_bias1_amt3_w_d5_r)
            1'd0: gradient_bias1_3_w = gradient_bias1_2_r << 0;
            1'd1: gradient_bias1_3_w = gradient_bias1_2_r << 64;
            default: gradient_bias1_3_w = gradient_bias1_2_r;
        endcase
    end
    assign mag88_1_w = {1'b0, inverse_abs1_w};
    assign gradient_round1_a0_w = mag88_1_w[0 +: 35];
    assign gradient_round1_b0_w = gradient_bias1_3_r_d40_r[0 +: 35];
    assign gradient_round1_low0_w = gradient_round1_part0_r[34:0];
    assign gradient_round1_a1_w = mag88_1_w[35 +: 35];
    assign gradient_round1_b1_w = gradient_bias1_3_r_d40_r[35 +: 35];
    assign gradient_round1_low1_w = gradient_round1_part1_r[34:0];
    assign gradient_round1_a2_w = mag88_1_w[70 +: 18];
    assign gradient_round1_b2_w = gradient_bias1_3_r_d40_r[70 +: 18];
    assign gradient_round1_low2_w = gradient_round1_part2_r[17:0];
    assign gradient_round1_w = {gradient_round1_low2_w, gradient_round1_low1_w_d43_r,
            gradient_round1_low0_w_d43_r};
    assign gradient_shift1_amt0_w = rounding_shift1_r[0 +: 2];
    always @(*) begin
        gradient_shift1_0_w = gradient_round1_w;
        case (gradient_shift1_amt0_w_d43_r)
            2'd0: gradient_shift1_0_w = gradient_round1_w >> 0;
            2'd1: gradient_shift1_0_w = gradient_round1_w >> 1;
            2'd2: gradient_shift1_0_w = gradient_round1_w >> 2;
            2'd3: gradient_shift1_0_w = gradient_round1_w >> 3;
            default: gradient_shift1_0_w = gradient_round1_w;
        endcase
    end
    assign gradient_shift1_amt1_w = rounding_shift1_r[2 +: 2];
    always @(*) begin
        gradient_shift1_1_w = gradient_shift1_0_r;
        case (gradient_shift1_amt1_w_d44_r)
            2'd0: gradient_shift1_1_w = gradient_shift1_0_r >> 0;
            2'd1: gradient_shift1_1_w = gradient_shift1_0_r >> 4;
            2'd2: gradient_shift1_1_w = gradient_shift1_0_r >> 8;
            2'd3: gradient_shift1_1_w = gradient_shift1_0_r >> 12;
            default: gradient_shift1_1_w = gradient_shift1_0_r;
        endcase
    end
    assign gradient_shift1_amt2_w = rounding_shift1_r[4 +: 2];
    always @(*) begin
        gradient_shift1_2_w = gradient_shift1_1_r;
        case (gradient_shift1_amt2_w_d45_r)
            2'd0: gradient_shift1_2_w = gradient_shift1_1_r >> 0;
            2'd1: gradient_shift1_2_w = gradient_shift1_1_r >> 16;
            2'd2: gradient_shift1_2_w = gradient_shift1_1_r >> 32;
            2'd3: gradient_shift1_2_w = gradient_shift1_1_r >> 48;
            default: gradient_shift1_2_w = gradient_shift1_1_r;
        endcase
    end
    assign gradient_shift1_amt3_w = rounding_shift1_r[6 +: 1];
    always @(*) begin
        unused_gradient_shift1_3_w = gradient_shift1_2_r;
        case (gradient_shift1_amt3_w_d46_r)
            1'd0: unused_gradient_shift1_3_w = gradient_shift1_2_r >> 0;
            1'd1: unused_gradient_shift1_3_w = gradient_shift1_2_r >> 64;
            default: unused_gradient_shift1_3_w = gradient_shift1_2_r;
        endcase
    end
    assign gradient56_1_w = gradient_shift1_3_r[55:0];
    assign gradient_signed1_carry_w = {55'b0, inverse_abs1_sign_d48_r};
    assign gradient_signed1_a0_w = gradient_signed1_invert_r[0 +: 35];
    assign gradient_signed1_b0_w = gradient_signed1_carry_w[0 +: 35];
    assign gradient_signed1_low0_w = gradient_signed1_part0_r[34:0];
    assign gradient_signed1_a1_w = gradient_signed1_invert_r[35 +: 21];
    assign gradient_signed1_b1_w = gradient_signed1_carry_w[35 +: 21];
    assign gradient_signed1_low1_w = gradient_signed1_part1_r[20:0];
    assign gradient_signed1_w = {gradient_signed1_low1_w, gradient_signed1_low0_w_d50_r};
    assign offset_context1_r_0_index50_w = tag_0_r_d49_r[6:3];
    assign origin_product1_pp0_0_extend_w = {{38{origin_product1_pp0_0_r[35]}},
            origin_product1_pp0_0_r};
    assign origin_product1_pp0_0_aligned_w = origin_product1_pp0_0_extend_w << 0;
    assign origin_product1_pp1_0_extend_w = {{38{origin_product1_pp1_0_r[35]}},
            origin_product1_pp1_0_r};
    assign origin_product1_pp1_0_aligned_w = origin_product1_pp1_0_extend_w << 17;
    assign origin_product1_pp2_0_extend_w = {{38{origin_product1_pp2_0_r[35]}},
            origin_product1_pp2_0_r};
    assign origin_product1_pp2_0_aligned_w = origin_product1_pp2_0_extend_w << 34;
    assign origin_product1_pp3_0_extend_w = {{51{origin_product1_pp3_0_r[22]}},
            origin_product1_pp3_0_r};
    assign origin_product1_pp3_0_aligned_w = origin_product1_pp3_0_extend_w << 51;
    // origin_product1: 56 x 18, 4 registered APM products; sliced adder tree.
    assign origin_product1_sum0_0_a0_w = origin_product1_pp0_0_aligned_w[0 +: 35];
    assign origin_product1_sum0_0_b0_w = origin_product1_pp1_0_aligned_w[0 +: 35];
    assign origin_product1_sum0_0_low0_w = origin_product1_sum0_0_part0_r[34:0];
    assign origin_product1_sum0_0_a1_w = origin_product1_pp0_0_aligned_w[35 +: 35];
    assign origin_product1_sum0_0_b1_w = origin_product1_pp1_0_aligned_w[35 +: 35];
    assign origin_product1_sum0_0_low1_w = origin_product1_sum0_0_part1_r[34:0];
    assign origin_product1_sum0_0_a2_w = origin_product1_pp0_0_aligned_w[70 +: 4];
    assign origin_product1_sum0_0_b2_w = origin_product1_pp1_0_aligned_w[70 +: 4];
    assign origin_product1_sum0_0_low2_w = origin_product1_sum0_0_part2_r[3:0];
    assign origin_product1_sum0_0_w = {origin_product1_sum0_0_low2_w,
            origin_product1_sum0_0_low1_w_d54_r, origin_product1_sum0_0_low0_w_d54_r};
    assign origin_product1_sum0_1_a0_w = origin_product1_pp2_0_aligned_w[0 +: 35];
    assign origin_product1_sum0_1_b0_w = origin_product1_pp3_0_aligned_w[0 +: 35];
    assign origin_product1_sum0_1_low0_w = origin_product1_sum0_1_part0_r[34:0];
    assign origin_product1_sum0_1_a1_w = origin_product1_pp2_0_aligned_w[35 +: 35];
    assign origin_product1_sum0_1_b1_w = origin_product1_pp3_0_aligned_w[35 +: 35];
    assign origin_product1_sum0_1_low1_w = origin_product1_sum0_1_part1_r[34:0];
    assign origin_product1_sum0_1_a2_w = origin_product1_pp2_0_aligned_w[70 +: 4];
    assign origin_product1_sum0_1_b2_w = origin_product1_pp3_0_aligned_w[70 +: 4];
    assign origin_product1_sum0_1_low2_w = origin_product1_sum0_1_part2_r[3:0];
    assign origin_product1_sum0_1_w = {origin_product1_sum0_1_low2_w,
            origin_product1_sum0_1_low1_w_d54_r, origin_product1_sum0_1_low0_w_d54_r};
    assign origin_product1_sum1_0_a0_w = origin_product1_sum0_0_w[0 +: 35];
    assign origin_product1_sum1_0_b0_w = origin_product1_sum0_1_w[0 +: 35];
    assign origin_product1_sum1_0_low0_w = origin_product1_sum1_0_part0_r[34:0];
    assign origin_product1_sum1_0_a1_w = origin_product1_sum0_0_w[35 +: 35];
    assign origin_product1_sum1_0_b1_w = origin_product1_sum0_1_w[35 +: 35];
    assign origin_product1_sum1_0_low1_w = origin_product1_sum1_0_part1_r[34:0];
    assign origin_product1_sum1_0_a2_w = origin_product1_sum0_0_w[70 +: 4];
    assign origin_product1_sum1_0_b2_w = origin_product1_sum0_1_w[70 +: 4];
    assign origin_product1_sum1_0_low2_w = origin_product1_sum1_0_part2_r[3:0];
    assign origin_product1_sum1_0_w = {origin_product1_sum1_0_low2_w,
            origin_product1_sum1_0_low1_w_d57_r, origin_product1_sum1_0_low0_w_d57_r};
    assign gradient_abs1_carry_w = {55'b0, gradient_abs1_sign_r};
    assign gradient_abs1_a0_w = gradient_abs1_invert_r[0 +: 35];
    assign gradient_abs1_b0_w = gradient_abs1_carry_w[0 +: 35];
    assign gradient_abs1_low0_w = gradient_abs1_part0_r[34:0];
    assign gradient_abs1_a1_w = gradient_abs1_invert_r[35 +: 21];
    assign gradient_abs1_b1_w = gradient_abs1_carry_w[35 +: 21];
    assign gradient_abs1_low1_w = gradient_abs1_part1_r[20:0];
    assign gradient_abs1_w = {gradient_abs1_low1_w, gradient_abs1_low0_w_d53_r};
    assign gradient_drop1_amt0_w = drop_gradient1_r[0 +: 2];
    always @(*) begin
        gradient_drop1_0_w = gradient_abs1_w;
        case (gradient_drop1_amt0_w_d53_r)
            2'd0: gradient_drop1_0_w = gradient_abs1_w >> 0;
            2'd1: gradient_drop1_0_w = gradient_abs1_w >> 1;
            2'd2: gradient_drop1_0_w = gradient_abs1_w >> 2;
            2'd3: gradient_drop1_0_w = gradient_abs1_w >> 3;
            default: gradient_drop1_0_w = gradient_abs1_w;
        endcase
    end
    assign gradient_drop1_amt1_w = drop_gradient1_r[2 +: 2];
    always @(*) begin
        unused_gradient_drop1_1_w = gradient_drop1_0_r;
        case (gradient_drop1_amt1_w_d54_r)
            2'd0: unused_gradient_drop1_1_w = gradient_drop1_0_r >> 0;
            2'd1: unused_gradient_drop1_1_w = gradient_drop1_0_r >> 4;
            2'd2: unused_gradient_drop1_1_w = gradient_drop1_0_r >> 8;
            2'd3: unused_gradient_drop1_1_w = gradient_drop1_0_r >> 12;
            default: unused_gradient_drop1_1_w = gradient_drop1_0_r;
        endcase
    end
    assign stored52_1_w = gradient_drop1_1_r[52:1];
    assign stored_bit1_w = {51'b0, gradient_drop1_1_r[0]};
    assign stored_round1_a0_w = stored52_1_w[0 +: 35];
    assign stored_round1_b0_w = stored_bit1_w[0 +: 35];
    assign stored_round1_low0_w = stored_round1_part0_r[34:0];
    assign stored_round1_a1_w = stored52_1_w[35 +: 17];
    assign stored_round1_b1_w = stored_bit1_w[35 +: 17];
    assign stored_round1_low1_w = stored_round1_part1_r[16:0];
    assign stored_round1_w = {stored_round1_low1_w, stored_round1_low0_w_d57_r};
    assign stored_signed1_carry_w = {51'b0, gradient_abs1_sign_d58_r};
    assign stored_signed1_a0_w = stored_signed1_invert_r[0 +: 35];
    assign stored_signed1_b0_w = stored_signed1_carry_w[0 +: 35];
    assign stored_signed1_low0_w = stored_signed1_part0_r[34:0];
    assign stored_signed1_a1_w = stored_signed1_invert_r[35 +: 17];
    assign stored_signed1_b1_w = stored_signed1_carry_w[35 +: 17];
    assign stored_signed1_low1_w = stored_signed1_part1_r[16:0];
    assign stored_signed1_w = {stored_signed1_low1_w, stored_signed1_low0_w_d60_r};
    assign origin_ext0_w = {origin_product0_sum1_0_w[73], origin_product0_sum1_0_w};
    assign origin_ext1_w = {origin_product1_sum1_0_w[73], origin_product1_sum1_0_w};
    assign origin_sum_a0_w = origin_ext0_w[0 +: 35];
    assign origin_sum_b0_w = origin_ext1_w[0 +: 35];
    assign origin_sum_low0_w = origin_sum_part0_r[34:0];
    assign origin_sum_a1_w = origin_ext0_w[35 +: 35];
    assign origin_sum_b1_w = origin_ext1_w[35 +: 35];
    assign origin_sum_low1_w = origin_sum_part1_r[34:0];
    assign origin_sum_a2_w = origin_ext0_w[70 +: 5];
    assign origin_sum_b2_w = origin_ext1_w[70 +: 5];
    assign origin_sum_low2_w = origin_sum_part2_r[4:0];
    assign origin_sum_w = {origin_sum_low2_w, origin_sum_low1_w_d60_r, origin_sum_low0_w_d60_r};
    assign origin_absolute_carry_w = {74'b0, origin_absolute_sign_r};
    assign origin_absolute_a0_w = origin_absolute_invert_r[0 +: 35];
    assign origin_absolute_b0_w = origin_absolute_carry_w[0 +: 35];
    assign origin_absolute_low0_w = origin_absolute_part0_r[34:0];
    assign origin_absolute_a1_w = origin_absolute_invert_r[35 +: 35];
    assign origin_absolute_b1_w = origin_absolute_carry_w[35 +: 35];
    assign origin_absolute_low1_w = origin_absolute_part1_r[34:0];
    assign origin_absolute_a2_w = origin_absolute_invert_r[70 +: 5];
    assign origin_absolute_b2_w = origin_absolute_carry_w[70 +: 5];
    assign origin_absolute_low2_w = origin_absolute_part2_r[4:0];
    assign origin_absolute_w = {origin_absolute_low2_w, origin_absolute_low1_w_d64_r,
            origin_absolute_low0_w_d64_r};
    assign origin_eight_w = 75'd8;
    assign origin_round_a0_w = origin_absolute_w[0 +: 35];
    assign origin_round_b0_w = origin_eight_w[0 +: 35];
    assign origin_round_low0_w = origin_round_part0_r[34:0];
    assign origin_round_a1_w = origin_absolute_w[35 +: 35];
    assign origin_round_b1_w = origin_eight_w[35 +: 35];
    assign origin_round_low1_w = origin_round_part1_r[34:0];
    assign origin_round_a2_w = origin_absolute_w[70 +: 5];
    assign origin_round_b2_w = origin_eight_w[70 +: 5];
    assign origin_round_low2_w = origin_round_part2_r[4:0];
    assign origin_round_w = {origin_round_low2_w, origin_round_low1_w_d67_r,
            origin_round_low0_w_d67_r};
    assign origin_signed_carry_w = {74'b0, origin_absolute_sign_d69_r};
    assign origin_signed_a0_w = origin_signed_invert_r[0 +: 35];
    assign origin_signed_b0_w = origin_signed_carry_w[0 +: 35];
    assign origin_signed_low0_w = origin_signed_part0_r[34:0];
    assign origin_signed_a1_w = origin_signed_invert_r[35 +: 35];
    assign origin_signed_b1_w = origin_signed_carry_w[35 +: 35];
    assign origin_signed_low1_w = origin_signed_part1_r[34:0];
    assign origin_signed_a2_w = origin_signed_invert_r[70 +: 5];
    assign origin_signed_b2_w = origin_signed_carry_w[70 +: 5];
    assign origin_signed_low2_w = origin_signed_part2_r[4:0];
    assign unused_origin_signed_w = {origin_signed_low2_w, origin_signed_low1_w_d72_r,
            origin_signed_low0_w_d72_r};
    assign start_base_w = {37'b0, scaled0_r};
    assign origin70_w = unused_origin_signed_w[69:0];
    assign start_sum_a0_w = start_base_w_d72_r[0 +: 35];
    assign start_sum_b0_w = origin70_w[0 +: 35];
    assign start_sum_low0_w = start_sum_part0_r[34:0];
    assign start_sum_a1_w = start_base_w_d72_r[35 +: 35];
    assign start_sum_b1_w = origin70_w[35 +: 35];
    assign start_sum_low1_w = start_sum_part1_r[34:0];
    assign start_sum_w = {start_sum_low1_w, start_sum_low0_w_d74_r};
    assign start_absolute_carry_w = {69'b0, start_absolute_sign_r};
    assign start_absolute_a0_w = start_absolute_invert_r[0 +: 35];
    assign start_absolute_b0_w = start_absolute_carry_w[0 +: 35];
    assign start_absolute_low0_w = start_absolute_part0_r[34:0];
    assign start_absolute_a1_w = start_absolute_invert_r[35 +: 35];
    assign start_absolute_b1_w = start_absolute_carry_w[35 +: 35];
    assign start_absolute_low1_w = start_absolute_part1_r[34:0];
    assign start_absolute_w = {start_absolute_low1_w, start_absolute_low0_w_d77_r};
    assign start_drop_amt0_w = drop_start_r[0 +: 2];
    always @(*) begin
        start_drop_0_w = start_absolute_w;
        case (start_drop_amt0_w_d77_r)
            2'd0: start_drop_0_w = start_absolute_w >> 0;
            2'd1: start_drop_0_w = start_absolute_w >> 1;
            2'd2: start_drop_0_w = start_absolute_w >> 2;
            2'd3: start_drop_0_w = start_absolute_w >> 3;
            default: start_drop_0_w = start_absolute_w;
        endcase
    end
    assign start_drop_amt1_w = drop_start_r[2 +: 2];
    always @(*) begin
        unused_start_drop_1_w = start_drop_0_r;
        case (start_drop_amt1_w_d78_r)
            2'd0: unused_start_drop_1_w = start_drop_0_r >> 0;
            2'd1: unused_start_drop_1_w = start_drop_0_r >> 4;
            2'd2: unused_start_drop_1_w = start_drop_0_r >> 8;
            2'd3: unused_start_drop_1_w = start_drop_0_r >> 12;
            default: unused_start_drop_1_w = start_drop_0_r;
        endcase
    end
    assign start66_w = start_drop_1_r[66:1];
    assign start_bit_w = {65'b0, start_drop_1_r[0]};
    assign start_round_a0_w = start66_w[0 +: 35];
    assign start_round_b0_w = start_bit_w[0 +: 35];
    assign start_round_low0_w = start_round_part0_r[34:0];
    assign start_round_a1_w = start66_w[35 +: 31];
    assign start_round_b1_w = start_bit_w[35 +: 31];
    assign start_round_low1_w = start_round_part1_r[30:0];
    assign start_round_w = {start_round_low1_w, start_round_low0_w_d81_r};
    assign start_signed_carry_w = {65'b0, start_absolute_sign_d82_r};
    assign start_signed_a0_w = start_signed_invert_r[0 +: 35];
    assign start_signed_b0_w = start_signed_carry_w[0 +: 35];
    assign start_signed_low0_w = start_signed_part0_r[34:0];
    assign start_signed_a1_w = start_signed_invert_r[35 +: 31];
    assign start_signed_b1_w = start_signed_carry_w[35 +: 31];
    assign start_signed_low1_w = start_signed_part1_r[30:0];
    assign start_signed_w = {start_signed_low1_w, start_signed_low0_w_d84_r};
    assign plane_start_o = start_signed_w;
    assign plane_gradient_o = {stored_signed1_w_d84_r, stored_signed0_w_d84_r};
    assign plane_h_o = h_d84_r;
    assign plane_tag_o = tag_0_r_d84_r;
    assign vertex0_w_d1_r = vertex0_w_delay1_r;
    assign vertex1_w_d1_r = vertex1_w_delay1_r;
    assign vertex2_w_d2_r = vertex2_w_delay2_r;
    assign vertex2_w_d3_r = vertex2_w_delay3_r;
    assign maximum01_select_d3_r = maximum01_select_delay3_r;
    assign nonzero_groups_d6_r = nonzero_groups_delay6_r;
    assign tag_0_r_d7_r = tag_0_r_delay7_r;
    assign tag_0_r_d19_r = tag_0_r_delay19_r;
    assign tag_0_r_d25_r = tag_0_r_delay25_r;
    assign tag_0_r_d49_r = tag_0_r_delay49_r;
    assign tag_0_r_d84_r = tag_0_r_delay84_r;
    assign maximum012_select_d7_r = maximum012_select_delay7_r;
    assign v52_0_w_d9_r_address_w = delay_pointer_r - 9'd8;
    edrv32_ram_gpu_delay u_v52_0_w_d9_r_bank0 (
        .clk_i(clk_i),
        .wr_en_i(enable_i),
        .wr_addr_i(delay_pointer_r),
        .wr_data_i({20'b0, v52_0_w}),
        .rd_en_i(enable_i),
        .rd_addr_i(v52_0_w_d9_r_address_w),
        .rd_data_o(unused_v52_0_w_d9_r_data_w[0 +: 72])
    );
    assign v52_0_w_d9_r = unused_v52_0_w_d9_r_data_w[51:0];
    assign v52_0_w_d13_r = v52_0_w_delay13_r;
    assign scale_left0_amt1_w_d10_r = scale_left0_amt1_w_delay10_r;
    assign scale_left0_amt2_w_d11_r = scale_left0_amt2_w_delay11_r;
    assign scale_bias0_amt1_w_d11_r = scale_bias0_amt1_w_delay11_r;
    assign scale_bias0_amt2_w_d12_r = scale_bias0_amt2_w_delay12_r;
    assign scale_add0_a1_w_d14_r = scale_add0_a1_w_delay14_r;
    assign scale_add0_b1_w_d14_r = scale_add0_b1_w_delay14_r;
    assign scale_add0_low0_w_d15_r = scale_add0_low0_w_delay15_r;
    assign scale_rounded0_amt0_w_d15_r = scale_rounded0_amt0_w_delay15_r;
    assign scale_rounded0_amt1_w_d16_r = scale_rounded0_amt1_w_delay16_r;
    assign scale_rounded0_amt2_w_d17_r = scale_rounded0_amt2_w_delay17_r;
    assign h_d18_r = h_delay18_r;
    assign h_d84_r = h_delay84_r;
    assign scale_left0_2_r_d18_r = scale_left0_2_r_delay18_r;
    assign v52_1_w_d9_r_address_w = delay_pointer_r - 9'd8;
    edrv32_ram_gpu_delay u_v52_1_w_d9_r_bank0 (
        .clk_i(clk_i),
        .wr_en_i(enable_i),
        .wr_addr_i(delay_pointer_r),
        .wr_data_i({20'b0, v52_1_w}),
        .rd_en_i(enable_i),
        .rd_addr_i(v52_1_w_d9_r_address_w),
        .rd_data_o(unused_v52_1_w_d9_r_data_w[0 +: 72])
    );
    assign v52_1_w_d9_r = unused_v52_1_w_d9_r_data_w[51:0];
    assign v52_1_w_d13_r = v52_1_w_delay13_r;
    assign scale_left1_amt1_w_d10_r = scale_left1_amt1_w_delay10_r;
    assign scale_left1_amt2_w_d11_r = scale_left1_amt2_w_delay11_r;
    assign scale_bias1_amt1_w_d11_r = scale_bias1_amt1_w_delay11_r;
    assign scale_bias1_amt2_w_d12_r = scale_bias1_amt2_w_delay12_r;
    assign scale_add1_a1_w_d14_r = scale_add1_a1_w_delay14_r;
    assign scale_add1_b1_w_d14_r = scale_add1_b1_w_delay14_r;
    assign scale_add1_low0_w_d15_r = scale_add1_low0_w_delay15_r;
    assign scale_rounded1_amt0_w_d15_r = scale_rounded1_amt0_w_delay15_r;
    assign scale_rounded1_amt1_w_d16_r = scale_rounded1_amt1_w_delay16_r;
    assign scale_rounded1_amt2_w_d17_r = scale_rounded1_amt2_w_delay17_r;
    assign scale_left1_2_r_d18_r = scale_left1_2_r_delay18_r;
    assign v52_2_w_d9_r_address_w = delay_pointer_r - 9'd8;
    edrv32_ram_gpu_delay u_v52_2_w_d9_r_bank0 (
        .clk_i(clk_i),
        .wr_en_i(enable_i),
        .wr_addr_i(delay_pointer_r),
        .wr_data_i({20'b0, v52_2_w}),
        .rd_en_i(enable_i),
        .rd_addr_i(v52_2_w_d9_r_address_w),
        .rd_data_o(unused_v52_2_w_d9_r_data_w[0 +: 72])
    );
    assign v52_2_w_d9_r = unused_v52_2_w_d9_r_data_w[51:0];
    assign v52_2_w_d13_r = v52_2_w_delay13_r;
    assign scale_left2_amt1_w_d10_r = scale_left2_amt1_w_delay10_r;
    assign scale_left2_amt2_w_d11_r = scale_left2_amt2_w_delay11_r;
    assign scale_bias2_amt1_w_d11_r = scale_bias2_amt1_w_delay11_r;
    assign scale_bias2_amt2_w_d12_r = scale_bias2_amt2_w_delay12_r;
    assign scale_add2_a1_w_d14_r = scale_add2_a1_w_delay14_r;
    assign scale_add2_b1_w_d14_r = scale_add2_b1_w_delay14_r;
    assign scale_add2_low0_w_d15_r = scale_add2_low0_w_delay15_r;
    assign scale_rounded2_amt0_w_d15_r = scale_rounded2_amt0_w_delay15_r;
    assign scale_rounded2_amt1_w_d16_r = scale_rounded2_amt1_w_delay16_r;
    assign scale_rounded2_amt2_w_d17_r = scale_rounded2_amt2_w_delay17_r;
    assign scale_left2_2_r_d18_r = scale_left2_2_r_delay18_r;
    assign product0_0_sum0_0_a1_w_d22_r = product0_0_sum0_0_a1_w_delay22_r;
    assign product0_0_sum0_0_b1_w_d22_r = product0_0_sum0_0_b1_w_delay22_r;
    assign product0_0_sum0_0_low0_w_d23_r = product0_0_sum0_0_low0_w_delay23_r;
    assign product0_1_sum0_0_a1_w_d22_r = product0_1_sum0_0_a1_w_delay22_r;
    assign product0_1_sum0_0_b1_w_d22_r = product0_1_sum0_0_b1_w_delay22_r;
    assign product0_1_sum0_0_low0_w_d23_r = product0_1_sum0_0_low0_w_delay23_r;
    assign numerator0_a1_w_d24_r = numerator0_a1_w_delay24_r;
    assign numerator0_b1_w_d24_r = numerator0_b1_w_delay24_r;
    assign numerator0_low0_w_d25_r = numerator0_low0_w_delay25_r;
    assign inverse0_sum0_0_a1_w_d28_r = inverse0_sum0_0_a1_w_delay28_r;
    assign inverse0_sum0_0_b1_w_d28_r = inverse0_sum0_0_b1_w_delay28_r;
    assign inverse0_sum0_0_a2_w_d29_r = inverse0_sum0_0_a2_w_delay29_r;
    assign inverse0_sum0_0_b2_w_d29_r = inverse0_sum0_0_b2_w_delay29_r;
    assign inverse0_sum0_0_low1_w_d30_r = inverse0_sum0_0_low1_w_delay30_r;
    assign inverse0_sum0_0_low0_w_d30_r = inverse0_sum0_0_low0_w_delay30_r;
    assign inverse0_sum0_1_a1_w_d28_r = inverse0_sum0_1_a1_w_delay28_r;
    assign inverse0_sum0_1_b1_w_d28_r = inverse0_sum0_1_b1_w_delay28_r;
    assign inverse0_sum0_1_a2_w_d29_r = inverse0_sum0_1_a2_w_delay29_r;
    assign inverse0_sum0_1_b2_w_d29_r = inverse0_sum0_1_b2_w_delay29_r;
    assign inverse0_sum0_1_low1_w_d30_r = inverse0_sum0_1_low1_w_delay30_r;
    assign inverse0_sum0_1_low0_w_d30_r = inverse0_sum0_1_low0_w_delay30_r;
    assign inverse0_sum0_2_a1_w_d28_r = inverse0_sum0_2_a1_w_delay28_r;
    assign inverse0_sum0_2_b1_w_d28_r = inverse0_sum0_2_b1_w_delay28_r;
    assign inverse0_sum0_2_a2_w_d29_r = inverse0_sum0_2_a2_w_delay29_r;
    assign inverse0_sum0_2_b2_w_d29_r = inverse0_sum0_2_b2_w_delay29_r;
    assign inverse0_sum0_2_low1_w_d30_r = inverse0_sum0_2_low1_w_delay30_r;
    assign inverse0_sum0_2_low0_w_d30_r = inverse0_sum0_2_low0_w_delay30_r;
    assign inverse0_sum0_3_a1_w_d28_r = inverse0_sum0_3_a1_w_delay28_r;
    assign inverse0_sum0_3_b1_w_d28_r = inverse0_sum0_3_b1_w_delay28_r;
    assign inverse0_sum0_3_a2_w_d29_r = inverse0_sum0_3_a2_w_delay29_r;
    assign inverse0_sum0_3_b2_w_d29_r = inverse0_sum0_3_b2_w_delay29_r;
    assign inverse0_sum0_3_low1_w_d30_r = inverse0_sum0_3_low1_w_delay30_r;
    assign inverse0_sum0_3_low0_w_d30_r = inverse0_sum0_3_low0_w_delay30_r;
    assign inverse0_sum1_0_a1_w_d31_r = inverse0_sum1_0_a1_w_delay31_r;
    assign inverse0_sum1_0_b1_w_d31_r = inverse0_sum1_0_b1_w_delay31_r;
    assign inverse0_sum1_0_a2_w_d32_r = inverse0_sum1_0_a2_w_delay32_r;
    assign inverse0_sum1_0_b2_w_d32_r = inverse0_sum1_0_b2_w_delay32_r;
    assign inverse0_sum1_0_low1_w_d33_r = inverse0_sum1_0_low1_w_delay33_r;
    assign inverse0_sum1_0_low0_w_d33_r = inverse0_sum1_0_low0_w_delay33_r;
    assign inverse0_sum1_1_a1_w_d31_r = inverse0_sum1_1_a1_w_delay31_r;
    assign inverse0_sum1_1_b1_w_d31_r = inverse0_sum1_1_b1_w_delay31_r;
    assign inverse0_sum1_1_a2_w_d32_r = inverse0_sum1_1_a2_w_delay32_r;
    assign inverse0_sum1_1_b2_w_d32_r = inverse0_sum1_1_b2_w_delay32_r;
    assign inverse0_sum1_1_low1_w_d33_r = inverse0_sum1_1_low1_w_delay33_r;
    assign inverse0_sum1_1_low0_w_d33_r = inverse0_sum1_1_low0_w_delay33_r;
    assign inverse0_sum2_0_a1_w_d34_r = inverse0_sum2_0_a1_w_delay34_r;
    assign inverse0_sum2_0_b1_w_d34_r = inverse0_sum2_0_b1_w_delay34_r;
    assign inverse0_sum2_0_a2_w_d35_r = inverse0_sum2_0_a2_w_delay35_r;
    assign inverse0_sum2_0_b2_w_d35_r = inverse0_sum2_0_b2_w_delay35_r;
    assign inverse0_sum2_0_low1_w_d36_r = inverse0_sum2_0_low1_w_delay36_r;
    assign inverse0_sum2_0_low0_w_d36_r = inverse0_sum2_0_low0_w_delay36_r;
    assign inverse_abs0_a1_w_d38_r = inverse_abs0_a1_w_delay38_r;
    assign inverse_abs0_b1_w_d38_r = inverse_abs0_b1_w_delay38_r;
    assign inverse_abs0_a2_w_d39_r = inverse_abs0_a2_w_delay39_r;
    assign inverse_abs0_b2_w_d39_r = inverse_abs0_b2_w_delay39_r;
    assign inverse_abs0_low1_w_d40_r = inverse_abs0_low1_w_delay40_r;
    assign inverse_abs0_low0_w_d40_r = inverse_abs0_low0_w_delay40_r;
    assign gradient_bias0_amt1_w_d3_r = gradient_bias0_amt1_w_delay3_r;
    assign gradient_bias0_amt2_w_d4_r = gradient_bias0_amt2_w_delay4_r;
    assign gradient_bias0_amt3_w_d5_r = gradient_bias0_amt3_w_delay5_r;
    assign gradient_bias0_3_r_d40_r_address_w = delay_pointer_r - 9'd33;
    edrv32_ram_gpu_delay u_gradient_bias0_3_r_d40_r_bank0 (
        .clk_i(clk_i),
        .wr_en_i(enable_i),
        .wr_addr_i(delay_pointer_r),
        .wr_data_i(gradient_bias0_3_r[0 +: 72]),
        .rd_en_i(enable_i),
        .rd_addr_i(gradient_bias0_3_r_d40_r_address_w),
        .rd_data_o(unused_gradient_bias0_3_r_d40_r_data_w[0 +: 72])
    );
    edrv32_ram_gpu_delay u_gradient_bias0_3_r_d40_r_bank1 (
        .clk_i(clk_i),
        .wr_en_i(enable_i),
        .wr_addr_i(delay_pointer_r),
        .wr_data_i({56'b0, gradient_bias0_3_r[72 +: 16]}),
        .rd_en_i(enable_i),
        .rd_addr_i(gradient_bias0_3_r_d40_r_address_w),
        .rd_data_o(unused_gradient_bias0_3_r_d40_r_data_w[72 +: 72])
    );
    assign gradient_bias0_3_r_d40_r = unused_gradient_bias0_3_r_d40_r_data_w[87:0];
    assign gradient_round0_a1_w_d41_r = gradient_round0_a1_w_delay41_r;
    assign gradient_round0_b1_w_d41_r = gradient_round0_b1_w_delay41_r;
    assign gradient_round0_a2_w_d42_r = gradient_round0_a2_w_delay42_r;
    assign gradient_round0_b2_w_d42_r = gradient_round0_b2_w_delay42_r;
    assign gradient_round0_low1_w_d43_r = gradient_round0_low1_w_delay43_r;
    assign gradient_round0_low0_w_d43_r = gradient_round0_low0_w_delay43_r;
    assign gradient_shift0_amt0_w_d43_r = gradient_shift0_amt0_w_delay43_r;
    assign gradient_shift0_amt1_w_d44_r = gradient_shift0_amt1_w_delay44_r;
    assign gradient_shift0_amt2_w_d45_r = gradient_shift0_amt2_w_delay45_r;
    assign gradient_shift0_amt3_w_d46_r = gradient_shift0_amt3_w_delay46_r;
    assign inverse_abs0_sign_d47_r = inverse_abs0_sign_delay47_r;
    assign inverse_abs0_sign_d48_r = inverse_abs0_sign_delay48_r;
    assign gradient_signed0_a1_w_d49_r = gradient_signed0_a1_w_delay49_r;
    assign gradient_signed0_b1_w_d49_r = gradient_signed0_b1_w_delay49_r;
    assign gradient_signed0_low0_w_d50_r = gradient_signed0_low0_w_delay50_r;
    assign origin_product0_sum0_0_a1_w_d52_r = origin_product0_sum0_0_a1_w_delay52_r;
    assign origin_product0_sum0_0_b1_w_d52_r = origin_product0_sum0_0_b1_w_delay52_r;
    assign origin_product0_sum0_0_a2_w_d53_r = origin_product0_sum0_0_a2_w_delay53_r;
    assign origin_product0_sum0_0_b2_w_d53_r = origin_product0_sum0_0_b2_w_delay53_r;
    assign origin_product0_sum0_0_low1_w_d54_r = origin_product0_sum0_0_low1_w_delay54_r;
    assign origin_product0_sum0_0_low0_w_d54_r = origin_product0_sum0_0_low0_w_delay54_r;
    assign origin_product0_sum0_1_a1_w_d52_r = origin_product0_sum0_1_a1_w_delay52_r;
    assign origin_product0_sum0_1_b1_w_d52_r = origin_product0_sum0_1_b1_w_delay52_r;
    assign origin_product0_sum0_1_a2_w_d53_r = origin_product0_sum0_1_a2_w_delay53_r;
    assign origin_product0_sum0_1_b2_w_d53_r = origin_product0_sum0_1_b2_w_delay53_r;
    assign origin_product0_sum0_1_low1_w_d54_r = origin_product0_sum0_1_low1_w_delay54_r;
    assign origin_product0_sum0_1_low0_w_d54_r = origin_product0_sum0_1_low0_w_delay54_r;
    assign origin_product0_sum1_0_a1_w_d55_r = origin_product0_sum1_0_a1_w_delay55_r;
    assign origin_product0_sum1_0_b1_w_d55_r = origin_product0_sum1_0_b1_w_delay55_r;
    assign origin_product0_sum1_0_a2_w_d56_r = origin_product0_sum1_0_a2_w_delay56_r;
    assign origin_product0_sum1_0_b2_w_d56_r = origin_product0_sum1_0_b2_w_delay56_r;
    assign origin_product0_sum1_0_low1_w_d57_r = origin_product0_sum1_0_low1_w_delay57_r;
    assign origin_product0_sum1_0_low0_w_d57_r = origin_product0_sum1_0_low0_w_delay57_r;
    assign gradient_abs0_a1_w_d52_r = gradient_abs0_a1_w_delay52_r;
    assign gradient_abs0_b1_w_d52_r = gradient_abs0_b1_w_delay52_r;
    assign gradient_abs0_low0_w_d53_r = gradient_abs0_low0_w_delay53_r;
    assign gradient_drop0_amt0_w_d53_r = gradient_drop0_amt0_w_delay53_r;
    assign gradient_drop0_amt1_w_d54_r = gradient_drop0_amt1_w_delay54_r;
    assign stored_round0_a1_w_d56_r = stored_round0_a1_w_delay56_r;
    assign stored_round0_b1_w_d56_r = stored_round0_b1_w_delay56_r;
    assign stored_round0_low0_w_d57_r = stored_round0_low0_w_delay57_r;
    assign gradient_abs0_sign_d57_r = gradient_abs0_sign_delay57_r;
    assign gradient_abs0_sign_d58_r = gradient_abs0_sign_delay58_r;
    assign stored_signed0_a1_w_d59_r = stored_signed0_a1_w_delay59_r;
    assign stored_signed0_b1_w_d59_r = stored_signed0_b1_w_delay59_r;
    assign stored_signed0_low0_w_d60_r = stored_signed0_low0_w_delay60_r;
    assign product1_0_sum0_0_a1_w_d22_r = product1_0_sum0_0_a1_w_delay22_r;
    assign product1_0_sum0_0_b1_w_d22_r = product1_0_sum0_0_b1_w_delay22_r;
    assign product1_0_sum0_0_low0_w_d23_r = product1_0_sum0_0_low0_w_delay23_r;
    assign product1_1_sum0_0_a1_w_d22_r = product1_1_sum0_0_a1_w_delay22_r;
    assign product1_1_sum0_0_b1_w_d22_r = product1_1_sum0_0_b1_w_delay22_r;
    assign product1_1_sum0_0_low0_w_d23_r = product1_1_sum0_0_low0_w_delay23_r;
    assign numerator1_a1_w_d24_r = numerator1_a1_w_delay24_r;
    assign numerator1_b1_w_d24_r = numerator1_b1_w_delay24_r;
    assign numerator1_low0_w_d25_r = numerator1_low0_w_delay25_r;
    assign inverse1_sum0_0_a1_w_d28_r = inverse1_sum0_0_a1_w_delay28_r;
    assign inverse1_sum0_0_b1_w_d28_r = inverse1_sum0_0_b1_w_delay28_r;
    assign inverse1_sum0_0_a2_w_d29_r = inverse1_sum0_0_a2_w_delay29_r;
    assign inverse1_sum0_0_b2_w_d29_r = inverse1_sum0_0_b2_w_delay29_r;
    assign inverse1_sum0_0_low1_w_d30_r = inverse1_sum0_0_low1_w_delay30_r;
    assign inverse1_sum0_0_low0_w_d30_r = inverse1_sum0_0_low0_w_delay30_r;
    assign inverse1_sum0_1_a1_w_d28_r = inverse1_sum0_1_a1_w_delay28_r;
    assign inverse1_sum0_1_b1_w_d28_r = inverse1_sum0_1_b1_w_delay28_r;
    assign inverse1_sum0_1_a2_w_d29_r = inverse1_sum0_1_a2_w_delay29_r;
    assign inverse1_sum0_1_b2_w_d29_r = inverse1_sum0_1_b2_w_delay29_r;
    assign inverse1_sum0_1_low1_w_d30_r = inverse1_sum0_1_low1_w_delay30_r;
    assign inverse1_sum0_1_low0_w_d30_r = inverse1_sum0_1_low0_w_delay30_r;
    assign inverse1_sum0_2_a1_w_d28_r = inverse1_sum0_2_a1_w_delay28_r;
    assign inverse1_sum0_2_b1_w_d28_r = inverse1_sum0_2_b1_w_delay28_r;
    assign inverse1_sum0_2_a2_w_d29_r = inverse1_sum0_2_a2_w_delay29_r;
    assign inverse1_sum0_2_b2_w_d29_r = inverse1_sum0_2_b2_w_delay29_r;
    assign inverse1_sum0_2_low1_w_d30_r = inverse1_sum0_2_low1_w_delay30_r;
    assign inverse1_sum0_2_low0_w_d30_r = inverse1_sum0_2_low0_w_delay30_r;
    assign inverse1_sum0_3_a1_w_d28_r = inverse1_sum0_3_a1_w_delay28_r;
    assign inverse1_sum0_3_b1_w_d28_r = inverse1_sum0_3_b1_w_delay28_r;
    assign inverse1_sum0_3_a2_w_d29_r = inverse1_sum0_3_a2_w_delay29_r;
    assign inverse1_sum0_3_b2_w_d29_r = inverse1_sum0_3_b2_w_delay29_r;
    assign inverse1_sum0_3_low1_w_d30_r = inverse1_sum0_3_low1_w_delay30_r;
    assign inverse1_sum0_3_low0_w_d30_r = inverse1_sum0_3_low0_w_delay30_r;
    assign inverse1_sum1_0_a1_w_d31_r = inverse1_sum1_0_a1_w_delay31_r;
    assign inverse1_sum1_0_b1_w_d31_r = inverse1_sum1_0_b1_w_delay31_r;
    assign inverse1_sum1_0_a2_w_d32_r = inverse1_sum1_0_a2_w_delay32_r;
    assign inverse1_sum1_0_b2_w_d32_r = inverse1_sum1_0_b2_w_delay32_r;
    assign inverse1_sum1_0_low1_w_d33_r = inverse1_sum1_0_low1_w_delay33_r;
    assign inverse1_sum1_0_low0_w_d33_r = inverse1_sum1_0_low0_w_delay33_r;
    assign inverse1_sum1_1_a1_w_d31_r = inverse1_sum1_1_a1_w_delay31_r;
    assign inverse1_sum1_1_b1_w_d31_r = inverse1_sum1_1_b1_w_delay31_r;
    assign inverse1_sum1_1_a2_w_d32_r = inverse1_sum1_1_a2_w_delay32_r;
    assign inverse1_sum1_1_b2_w_d32_r = inverse1_sum1_1_b2_w_delay32_r;
    assign inverse1_sum1_1_low1_w_d33_r = inverse1_sum1_1_low1_w_delay33_r;
    assign inverse1_sum1_1_low0_w_d33_r = inverse1_sum1_1_low0_w_delay33_r;
    assign inverse1_sum2_0_a1_w_d34_r = inverse1_sum2_0_a1_w_delay34_r;
    assign inverse1_sum2_0_b1_w_d34_r = inverse1_sum2_0_b1_w_delay34_r;
    assign inverse1_sum2_0_a2_w_d35_r = inverse1_sum2_0_a2_w_delay35_r;
    assign inverse1_sum2_0_b2_w_d35_r = inverse1_sum2_0_b2_w_delay35_r;
    assign inverse1_sum2_0_low1_w_d36_r = inverse1_sum2_0_low1_w_delay36_r;
    assign inverse1_sum2_0_low0_w_d36_r = inverse1_sum2_0_low0_w_delay36_r;
    assign inverse_abs1_a1_w_d38_r = inverse_abs1_a1_w_delay38_r;
    assign inverse_abs1_b1_w_d38_r = inverse_abs1_b1_w_delay38_r;
    assign inverse_abs1_a2_w_d39_r = inverse_abs1_a2_w_delay39_r;
    assign inverse_abs1_b2_w_d39_r = inverse_abs1_b2_w_delay39_r;
    assign inverse_abs1_low1_w_d40_r = inverse_abs1_low1_w_delay40_r;
    assign inverse_abs1_low0_w_d40_r = inverse_abs1_low0_w_delay40_r;
    assign gradient_bias1_amt1_w_d3_r = gradient_bias1_amt1_w_delay3_r;
    assign gradient_bias1_amt2_w_d4_r = gradient_bias1_amt2_w_delay4_r;
    assign gradient_bias1_amt3_w_d5_r = gradient_bias1_amt3_w_delay5_r;
    assign gradient_bias1_3_r_d40_r_address_w = delay_pointer_r - 9'd33;
    edrv32_ram_gpu_delay u_gradient_bias1_3_r_d40_r_bank0 (
        .clk_i(clk_i),
        .wr_en_i(enable_i),
        .wr_addr_i(delay_pointer_r),
        .wr_data_i(gradient_bias1_3_r[0 +: 72]),
        .rd_en_i(enable_i),
        .rd_addr_i(gradient_bias1_3_r_d40_r_address_w),
        .rd_data_o(unused_gradient_bias1_3_r_d40_r_data_w[0 +: 72])
    );
    edrv32_ram_gpu_delay u_gradient_bias1_3_r_d40_r_bank1 (
        .clk_i(clk_i),
        .wr_en_i(enable_i),
        .wr_addr_i(delay_pointer_r),
        .wr_data_i({56'b0, gradient_bias1_3_r[72 +: 16]}),
        .rd_en_i(enable_i),
        .rd_addr_i(gradient_bias1_3_r_d40_r_address_w),
        .rd_data_o(unused_gradient_bias1_3_r_d40_r_data_w[72 +: 72])
    );
    assign gradient_bias1_3_r_d40_r = unused_gradient_bias1_3_r_d40_r_data_w[87:0];
    assign gradient_round1_a1_w_d41_r = gradient_round1_a1_w_delay41_r;
    assign gradient_round1_b1_w_d41_r = gradient_round1_b1_w_delay41_r;
    assign gradient_round1_a2_w_d42_r = gradient_round1_a2_w_delay42_r;
    assign gradient_round1_b2_w_d42_r = gradient_round1_b2_w_delay42_r;
    assign gradient_round1_low1_w_d43_r = gradient_round1_low1_w_delay43_r;
    assign gradient_round1_low0_w_d43_r = gradient_round1_low0_w_delay43_r;
    assign gradient_shift1_amt0_w_d43_r = gradient_shift1_amt0_w_delay43_r;
    assign gradient_shift1_amt1_w_d44_r = gradient_shift1_amt1_w_delay44_r;
    assign gradient_shift1_amt2_w_d45_r = gradient_shift1_amt2_w_delay45_r;
    assign gradient_shift1_amt3_w_d46_r = gradient_shift1_amt3_w_delay46_r;
    assign inverse_abs1_sign_d47_r = inverse_abs1_sign_delay47_r;
    assign inverse_abs1_sign_d48_r = inverse_abs1_sign_delay48_r;
    assign gradient_signed1_a1_w_d49_r = gradient_signed1_a1_w_delay49_r;
    assign gradient_signed1_b1_w_d49_r = gradient_signed1_b1_w_delay49_r;
    assign gradient_signed1_low0_w_d50_r = gradient_signed1_low0_w_delay50_r;
    assign origin_product1_sum0_0_a1_w_d52_r = origin_product1_sum0_0_a1_w_delay52_r;
    assign origin_product1_sum0_0_b1_w_d52_r = origin_product1_sum0_0_b1_w_delay52_r;
    assign origin_product1_sum0_0_a2_w_d53_r = origin_product1_sum0_0_a2_w_delay53_r;
    assign origin_product1_sum0_0_b2_w_d53_r = origin_product1_sum0_0_b2_w_delay53_r;
    assign origin_product1_sum0_0_low1_w_d54_r = origin_product1_sum0_0_low1_w_delay54_r;
    assign origin_product1_sum0_0_low0_w_d54_r = origin_product1_sum0_0_low0_w_delay54_r;
    assign origin_product1_sum0_1_a1_w_d52_r = origin_product1_sum0_1_a1_w_delay52_r;
    assign origin_product1_sum0_1_b1_w_d52_r = origin_product1_sum0_1_b1_w_delay52_r;
    assign origin_product1_sum0_1_a2_w_d53_r = origin_product1_sum0_1_a2_w_delay53_r;
    assign origin_product1_sum0_1_b2_w_d53_r = origin_product1_sum0_1_b2_w_delay53_r;
    assign origin_product1_sum0_1_low1_w_d54_r = origin_product1_sum0_1_low1_w_delay54_r;
    assign origin_product1_sum0_1_low0_w_d54_r = origin_product1_sum0_1_low0_w_delay54_r;
    assign origin_product1_sum1_0_a1_w_d55_r = origin_product1_sum1_0_a1_w_delay55_r;
    assign origin_product1_sum1_0_b1_w_d55_r = origin_product1_sum1_0_b1_w_delay55_r;
    assign origin_product1_sum1_0_a2_w_d56_r = origin_product1_sum1_0_a2_w_delay56_r;
    assign origin_product1_sum1_0_b2_w_d56_r = origin_product1_sum1_0_b2_w_delay56_r;
    assign origin_product1_sum1_0_low1_w_d57_r = origin_product1_sum1_0_low1_w_delay57_r;
    assign origin_product1_sum1_0_low0_w_d57_r = origin_product1_sum1_0_low0_w_delay57_r;
    assign gradient_abs1_a1_w_d52_r = gradient_abs1_a1_w_delay52_r;
    assign gradient_abs1_b1_w_d52_r = gradient_abs1_b1_w_delay52_r;
    assign gradient_abs1_low0_w_d53_r = gradient_abs1_low0_w_delay53_r;
    assign gradient_drop1_amt0_w_d53_r = gradient_drop1_amt0_w_delay53_r;
    assign gradient_drop1_amt1_w_d54_r = gradient_drop1_amt1_w_delay54_r;
    assign stored_round1_a1_w_d56_r = stored_round1_a1_w_delay56_r;
    assign stored_round1_b1_w_d56_r = stored_round1_b1_w_delay56_r;
    assign stored_round1_low0_w_d57_r = stored_round1_low0_w_delay57_r;
    assign gradient_abs1_sign_d57_r = gradient_abs1_sign_delay57_r;
    assign gradient_abs1_sign_d58_r = gradient_abs1_sign_delay58_r;
    assign stored_signed1_a1_w_d59_r = stored_signed1_a1_w_delay59_r;
    assign stored_signed1_b1_w_d59_r = stored_signed1_b1_w_delay59_r;
    assign stored_signed1_low0_w_d60_r = stored_signed1_low0_w_delay60_r;
    assign origin_sum_a1_w_d58_r = origin_sum_a1_w_delay58_r;
    assign origin_sum_b1_w_d58_r = origin_sum_b1_w_delay58_r;
    assign origin_sum_a2_w_d59_r = origin_sum_a2_w_delay59_r;
    assign origin_sum_b2_w_d59_r = origin_sum_b2_w_delay59_r;
    assign origin_sum_low1_w_d60_r = origin_sum_low1_w_delay60_r;
    assign origin_sum_low0_w_d60_r = origin_sum_low0_w_delay60_r;
    assign origin_absolute_a1_w_d62_r = origin_absolute_a1_w_delay62_r;
    assign origin_absolute_b1_w_d62_r = origin_absolute_b1_w_delay62_r;
    assign origin_absolute_a2_w_d63_r = origin_absolute_a2_w_delay63_r;
    assign origin_absolute_b2_w_d63_r = origin_absolute_b2_w_delay63_r;
    assign origin_absolute_low1_w_d64_r = origin_absolute_low1_w_delay64_r;
    assign origin_absolute_low0_w_d64_r = origin_absolute_low0_w_delay64_r;
    assign origin_round_a1_w_d65_r = origin_round_a1_w_delay65_r;
    assign origin_round_b1_w_d65_r = origin_round_b1_w_delay65_r;
    assign origin_round_a2_w_d66_r = origin_round_a2_w_delay66_r;
    assign origin_round_b2_w_d66_r = origin_round_b2_w_delay66_r;
    assign origin_round_low1_w_d67_r = origin_round_low1_w_delay67_r;
    assign origin_round_low0_w_d67_r = origin_round_low0_w_delay67_r;
    assign origin_absolute_sign_d68_r = origin_absolute_sign_delay68_r;
    assign origin_absolute_sign_d69_r = origin_absolute_sign_delay69_r;
    assign origin_signed_a1_w_d70_r = origin_signed_a1_w_delay70_r;
    assign origin_signed_b1_w_d70_r = origin_signed_b1_w_delay70_r;
    assign origin_signed_a2_w_d71_r = origin_signed_a2_w_delay71_r;
    assign origin_signed_b2_w_d71_r = origin_signed_b2_w_delay71_r;
    assign origin_signed_low1_w_d72_r = origin_signed_low1_w_delay72_r;
    assign origin_signed_low0_w_d72_r = origin_signed_low0_w_delay72_r;
    assign start_base_w_d72_r_address_w = delay_pointer_r - 9'd52;
    edrv32_ram_gpu_delay u_start_base_w_d72_r_bank0 (
        .clk_i(clk_i),
        .wr_en_i(enable_i),
        .wr_addr_i(delay_pointer_r),
        .wr_data_i({2'b0, start_base_w}),
        .rd_en_i(enable_i),
        .rd_addr_i(start_base_w_d72_r_address_w),
        .rd_data_o(unused_start_base_w_d72_r_data_w[0 +: 72])
    );
    assign start_base_w_d72_r = unused_start_base_w_d72_r_data_w[69:0];
    assign start_sum_a1_w_d73_r = start_sum_a1_w_delay73_r;
    assign start_sum_b1_w_d73_r = start_sum_b1_w_delay73_r;
    assign start_sum_low0_w_d74_r = start_sum_low0_w_delay74_r;
    assign start_absolute_a1_w_d76_r = start_absolute_a1_w_delay76_r;
    assign start_absolute_b1_w_d76_r = start_absolute_b1_w_delay76_r;
    assign start_absolute_low0_w_d77_r = start_absolute_low0_w_delay77_r;
    assign start_drop_amt0_w_d77_r = start_drop_amt0_w_delay77_r;
    assign start_drop_amt1_w_d78_r = start_drop_amt1_w_delay78_r;
    assign start_round_a1_w_d80_r = start_round_a1_w_delay80_r;
    assign start_round_b1_w_d80_r = start_round_b1_w_delay80_r;
    assign start_round_low0_w_d81_r = start_round_low0_w_delay81_r;
    assign start_absolute_sign_d81_r = start_absolute_sign_delay81_r;
    assign start_absolute_sign_d82_r = start_absolute_sign_delay82_r;
    assign start_signed_a1_w_d83_r = start_signed_a1_w_delay83_r;
    assign start_signed_b1_w_d83_r = start_signed_b1_w_delay83_r;
    assign start_signed_low0_w_d84_r = start_signed_low0_w_delay84_r;
    assign stored_signed1_w_d84_r_address_w = delay_pointer_r - 9'd23;
    edrv32_ram_gpu_delay u_stored_signed1_w_d84_r_bank0 (
        .clk_i(clk_i),
        .wr_en_i(enable_i),
        .wr_addr_i(delay_pointer_r),
        .wr_data_i({20'b0, stored_signed1_w}),
        .rd_en_i(enable_i),
        .rd_addr_i(stored_signed1_w_d84_r_address_w),
        .rd_data_o(unused_stored_signed1_w_d84_r_data_w[0 +: 72])
    );
    assign stored_signed1_w_d84_r = unused_stored_signed1_w_d84_r_data_w[51:0];
    assign stored_signed0_w_d84_r_address_w = delay_pointer_r - 9'd23;
    edrv32_ram_gpu_delay u_stored_signed0_w_d84_r_bank0 (
        .clk_i(clk_i),
        .wr_en_i(enable_i),
        .wr_addr_i(delay_pointer_r),
        .wr_data_i({20'b0, stored_signed0_w}),
        .rd_en_i(enable_i),
        .rd_addr_i(stored_signed0_w_d84_r_address_w),
        .rd_data_o(unused_stored_signed0_w_d84_r_data_w[0 +: 72])
    );
    assign stored_signed0_w_d84_r = unused_stored_signed0_w_d84_r_data_w[51:0];
    // Local credit copies preserve the enable contract for each arithmetic region.
    wire [18:0] pipeline_enable_w;
    genvar enable_region;
    generate
        for (enable_region = 0; enable_region < 19;
            enable_region = enable_region + 1) begin : g_enable_region
            (* keep = "true", syn_preserve = 1 *) reg [1:0] region_count_r;
            assign pipeline_enable_w[enable_region] = region_count_r != 2 && !stop_i;
            always @(posedge clk_i or negedge rst_n_i) begin
                if (!rst_n_i) region_count_r <= 0;
                else if (stop_i) region_count_r <= 0;
                else begin
                    case ({credit_push_i, credit_pop_i})
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
            value_0_r <= plane_value_i;
            tag_0_r <= plane_tag_i;
            maximum01_compare_r <= {vertex0_w[50:26] > vertex1_w[50:26], vertex0_w[50:26] ==
            vertex1_w[50:26], vertex0_w[25:0] > vertex1_w[25:0]};
            maximum01_select_r <= (maximum01_compare_r[2] || (maximum01_compare_r[1] &&
            maximum01_compare_r[0])) ? vertex0_w_d1_r : vertex1_w_d1_r;
            maximum012_compare_r <= {maximum01_select_r[50:26] > vertex2_w_d2_r[50:26],
            maximum01_select_r[50:26] == vertex2_w_d2_r[50:26], maximum01_select_r[25:0] >
            vertex2_w_d2_r[25:0]};
            maximum012_select_r <= (maximum012_compare_r[2] || (maximum012_compare_r[1] &&
            maximum012_compare_r[0])) ? maximum01_select_d3_r : vertex2_w_d3_r;
            leading_group0_r <= maximum012_select_r[3] ? 6'd3 : maximum012_select_r[2] ? 6'd2 :
            maximum012_select_r[1] ? 6'd1 : maximum012_select_r[0] ? 6'd0 : 6'd0;
            leading_group1_r <= maximum012_select_r[7] ? 6'd7 : maximum012_select_r[6] ? 6'd6 :
            maximum012_select_r[5] ? 6'd5 : maximum012_select_r[4] ? 6'd4 : 6'd0;
            leading_group2_r <= maximum012_select_r[11] ? 6'd11 : maximum012_select_r[10] ?
            6'd10 : maximum012_select_r[9] ? 6'd9 : maximum012_select_r[8] ? 6'd8 : 6'd0;
            leading_group3_r <= maximum012_select_r[15] ? 6'd15 : maximum012_select_r[14] ?
            6'd14 : maximum012_select_r[13] ? 6'd13 : maximum012_select_r[12] ? 6'd12 : 6'd0;
            leading_group4_r <= maximum012_select_r[19] ? 6'd19 : maximum012_select_r[18] ?
            6'd18 : maximum012_select_r[17] ? 6'd17 : maximum012_select_r[16] ? 6'd16 : 6'd0;
            leading_group5_r <= maximum012_select_r[23] ? 6'd23 : maximum012_select_r[22] ?
            6'd22 : maximum012_select_r[21] ? 6'd21 : maximum012_select_r[20] ? 6'd20 : 6'd0;
            leading_group6_r <= maximum012_select_r[27] ? 6'd27 : maximum012_select_r[26] ?
            6'd26 : maximum012_select_r[25] ? 6'd25 : maximum012_select_r[24] ? 6'd24 : 6'd0;
            leading_group7_r <= maximum012_select_r[31] ? 6'd31 : maximum012_select_r[30] ?
            6'd30 : maximum012_select_r[29] ? 6'd29 : maximum012_select_r[28] ? 6'd28 : 6'd0;
            leading_group8_r <= maximum012_select_r[35] ? 6'd35 : maximum012_select_r[34] ?
            6'd34 : maximum012_select_r[33] ? 6'd33 : maximum012_select_r[32] ? 6'd32 : 6'd0;
            leading_group9_r <= maximum012_select_r[39] ? 6'd39 : maximum012_select_r[38] ?
            6'd38 : maximum012_select_r[37] ? 6'd37 : maximum012_select_r[36] ? 6'd36 : 6'd0;
            leading_group10_r <= maximum012_select_r[43] ? 6'd43 : maximum012_select_r[42] ?
            6'd42 : maximum012_select_r[41] ? 6'd41 : maximum012_select_r[40] ? 6'd40 : 6'd0;
            leading_group11_r <= maximum012_select_r[47] ? 6'd47 : maximum012_select_r[46] ?
            6'd46 : maximum012_select_r[45] ? 6'd45 : maximum012_select_r[44] ? 6'd44 : 6'd0;
            leading_group12_r <= maximum012_select_r[50] ? 6'd50 : maximum012_select_r[49] ?
            6'd49 : maximum012_select_r[48] ? 6'd48 : 6'd0;
            nonzero_groups_r <= {(|maximum012_select_r[48 +: 3]), (|maximum012_select_r[44 +:
            4]), (|maximum012_select_r[40 +: 4]), (|maximum012_select_r[36 +: 4]),
            (|maximum012_select_r[32 +: 4]), (|maximum012_select_r[28 +: 4]),
            (|maximum012_select_r[24 +: 4]), (|maximum012_select_r[20 +: 4]),
            (|maximum012_select_r[16 +: 4]), (|maximum012_select_r[12 +: 4]),
            (|maximum012_select_r[8 +: 4]), (|maximum012_select_r[4 +: 4]),
            (|maximum012_select_r[0 +: 4])};
            leading_partial0_r <= nonzero_groups_r[3] ? leading_group3_r : nonzero_groups_r[2]
            ? leading_group2_r : nonzero_groups_r[1] ? leading_group1_r : nonzero_groups_r[0] ?
            leading_group0_r : 6'd0;
            leading_partial1_r <= nonzero_groups_r[7] ? leading_group7_r : nonzero_groups_r[6]
            ? leading_group6_r : nonzero_groups_r[5] ? leading_group5_r : nonzero_groups_r[4] ?
            leading_group4_r : 6'd0;
            leading_partial2_r <= nonzero_groups_r[11] ? leading_group11_r :
            nonzero_groups_r[10] ? leading_group10_r : nonzero_groups_r[9] ? leading_group9_r :
            nonzero_groups_r[8] ? leading_group8_r : 6'd0;
            leading_partial3_r <= nonzero_groups_r[12] ? leading_group12_r : 6'd0;
            leading_r <= (|nonzero_groups_d6_r[12 +: 1]) ? leading_partial3_r :
            (|nonzero_groups_d6_r[8 +: 4]) ? leading_partial2_r : (|nonzero_groups_d6_r[4 +:
            4]) ? leading_partial1_r : (|nonzero_groups_d6_r[0 +: 4]) ? leading_partial0_r : 6'd0;
            h_r <= tag_0_r_d7_r[2:0] == 0 ? -10'sd16 : tag_0_r_d7_r[2:0] < 4 ?
            (maximum012_select_d7_r == 0 ? -10'sd32 : {4'b0, leading_r} - 10'd31) : -10'sd8;
            right_amount_r <= $signed(h_r) > 0 ? h_r[5:0] : 6'b0;
            left_amount_r <= $signed(h_r) < 0 ? -h_r[5:0] : 6'b0;
            scale_left0_0_r <= scale_left0_0_w;
            scale_left0_1_r <= scale_left0_1_w;
            scale_left0_2_r <= unused_scale_left0_2_w[32:0];
            scale_bit0_r <= right_amount_r - 6'd1;
            scale_bias0_0_r <= scale_bias0_0_w;
            scale_bias0_1_r <= scale_bias0_1_w;
            scale_bias0_2_r <= scale_bias0_2_w;
            scale_add0_part0_r <= {1'b0, scale_add0_a0_w} + {1'b0, scale_add0_b0_w};
            scale_add0_part1_r <= scale_add0_a1_w_d14_r + scale_add0_b1_w_d14_r + {16'b0,
            scale_add0_part0_r[35]};
            scale_rounded0_0_r <= scale_rounded0_0_w;
            scale_rounded0_1_r <= scale_rounded0_1_w;
            scale_rounded0_2_r <= unused_scale_rounded0_2_w[32:0];
            scaled0_r <= $signed(h_d18_r) > 0 ? scale_rounded0_2_r[32:0] :
            scale_left0_2_r_d18_r[32:0];
            scale_left1_0_r <= scale_left1_0_w;
            scale_left1_1_r <= scale_left1_1_w;
            scale_left1_2_r <= unused_scale_left1_2_w[32:0];
            scale_bit1_r <= right_amount_r - 6'd1;
            scale_bias1_0_r <= scale_bias1_0_w;
            scale_bias1_1_r <= scale_bias1_1_w;
        end
    end
    always @(posedge clk_i) begin
        if (pipeline_enable_w[1]) begin
            scale_bias1_2_r <= scale_bias1_2_w;
            scale_add1_part0_r <= {1'b0, scale_add1_a0_w} + {1'b0, scale_add1_b0_w};
            scale_add1_part1_r <= scale_add1_a1_w_d14_r + scale_add1_b1_w_d14_r + {16'b0,
            scale_add1_part0_r[35]};
            scale_rounded1_0_r <= scale_rounded1_0_w;
            scale_rounded1_1_r <= scale_rounded1_1_w;
            scale_rounded1_2_r <= unused_scale_rounded1_2_w[32:0];
            scaled1_r <= $signed(h_d18_r) > 0 ? scale_rounded1_2_r[32:0] :
            scale_left1_2_r_d18_r[32:0];
            scale_left2_0_r <= scale_left2_0_w;
            scale_left2_1_r <= scale_left2_1_w;
            scale_left2_2_r <= unused_scale_left2_2_w[32:0];
            scale_bit2_r <= right_amount_r - 6'd1;
            scale_bias2_0_r <= scale_bias2_0_w;
            scale_bias2_1_r <= scale_bias2_1_w;
            scale_bias2_2_r <= scale_bias2_2_w;
            scale_add2_part0_r <= {1'b0, scale_add2_a0_w} + {1'b0, scale_add2_b0_w};
            scale_add2_part1_r <= scale_add2_a1_w_d14_r + scale_add2_b1_w_d14_r + {16'b0,
            scale_add2_part0_r[35]};
            scale_rounded2_0_r <= scale_rounded2_0_w;
            scale_rounded2_1_r <= scale_rounded2_1_w;
            scale_rounded2_2_r <= unused_scale_rounded2_2_w[32:0];
            scaled2_r <= $signed(h_d18_r) > 0 ? scale_rounded2_2_r[32:0] :
            scale_left2_2_r_d18_r[32:0];
            difference0_r <= $signed({1'b0, scaled1_r}) - $signed({1'b0, scaled0_r});
            difference1_r <= $signed({1'b0, scaled2_r}) - $signed({1'b0, scaled0_r});
            delta_context0_r_0_read20_r <= delta_context0_r[delta_context0_r_0_index20_w];
            product0_0_pp0_0_r <= $signed({1'b0, difference0_r[0 +: 17]}) *
            $signed(delta_context0_r_0_read20_r);
            product0_0_pp1_0_r <= $signed(difference0_r[17 +: 17]) *
            $signed(delta_context0_r_0_read20_r);
            product0_0_sum0_0_part0_r <= {1'b0, product0_0_sum0_0_a0_w} + {1'b0,
            product0_0_sum0_0_b0_w};
            product0_0_sum0_0_part1_r <= product0_0_sum0_0_a1_w_d22_r +
            product0_0_sum0_0_b1_w_d22_r + {16'b0, product0_0_sum0_0_part0_r[35]};
            delta_context1_r_0_read20_r <= delta_context1_r[delta_context1_r_0_index20_w];
            product0_1_pp0_0_r <= $signed({1'b0, difference1_r[0 +: 17]}) *
            $signed(delta_context1_r_0_read20_r);
            product0_1_pp1_0_r <= $signed(difference1_r[17 +: 17]) *
            $signed(delta_context1_r_0_read20_r);
            product0_1_sum0_0_part0_r <= {1'b0, product0_1_sum0_0_a0_w} + {1'b0,
            product0_1_sum0_0_b0_w};
            product0_1_sum0_0_part1_r <= product0_1_sum0_0_a1_w_d22_r +
            product0_1_sum0_0_b1_w_d22_r + {16'b0, product0_1_sum0_0_part0_r[35]};
            numerator0_part0_r <= {1'b0, numerator0_a0_w} + {1'b0, numerator0_b0_w};
        end
    end
    always @(posedge clk_i) begin
        if (pipeline_enable_w[2]) begin
            numerator0_part1_r <= numerator0_a1_w_d24_r + numerator0_b1_w_d24_r + {20'b0,
            numerator0_part0_r[35]};
            numerator_shift0_r <= numerator0_w << 4;
            reciprocal_context_r_0_read26_r <=
            reciprocal_context_r[reciprocal_context_r_0_index26_w];
            inverse0_pp0_0_r <= $signed({1'b0, numerator_shift0_r[0 +: 17]}) * $signed({1'b0,
            reciprocal_context_r_0_read26_r[0 +: 17]});
            inverse0_pp0_1_r <= $signed({1'b0, numerator_shift0_r[0 +: 17]}) * $signed({1'b0,
            reciprocal_context_r_0_read26_r[17 +: 14]});
            inverse0_pp1_0_r <= $signed({1'b0, numerator_shift0_r[17 +: 17]}) * $signed({1'b0,
            reciprocal_context_r_0_read26_r[0 +: 17]});
            inverse0_pp1_1_r <= $signed({1'b0, numerator_shift0_r[17 +: 17]}) * $signed({1'b0,
            reciprocal_context_r_0_read26_r[17 +: 14]});
            inverse0_pp2_0_r <= $signed({1'b0, numerator_shift0_r[34 +: 17]}) * $signed({1'b0,
            reciprocal_context_r_0_read26_r[0 +: 17]});
            inverse0_pp2_1_r <= $signed({1'b0, numerator_shift0_r[34 +: 17]}) * $signed({1'b0,
            reciprocal_context_r_0_read26_r[17 +: 14]});
            inverse0_pp3_0_r <= $signed(numerator_shift0_r[51 +: 5]) * $signed({1'b0,
            reciprocal_context_r_0_read26_r[0 +: 17]});
            inverse0_pp3_1_r <= $signed(numerator_shift0_r[51 +: 5]) * $signed({1'b0,
            reciprocal_context_r_0_read26_r[17 +: 14]});
            inverse0_sum0_0_part0_r <= {1'b0, inverse0_sum0_0_a0_w} + {1'b0, inverse0_sum0_0_b0_w};
            inverse0_sum0_0_part1_r <= {1'b0, inverse0_sum0_0_a1_w_d28_r} + {1'b0,
            inverse0_sum0_0_b1_w_d28_r} + {35'b0, inverse0_sum0_0_part0_r[35]};
            inverse0_sum0_0_part2_r <= inverse0_sum0_0_a2_w_d29_r + inverse0_sum0_0_b2_w_d29_r
            + {16'b0, inverse0_sum0_0_part1_r[35]};
            inverse0_sum0_1_part0_r <= {1'b0, inverse0_sum0_1_a0_w} + {1'b0, inverse0_sum0_1_b0_w};
            inverse0_sum0_1_part1_r <= {1'b0, inverse0_sum0_1_a1_w_d28_r} + {1'b0,
            inverse0_sum0_1_b1_w_d28_r} + {35'b0, inverse0_sum0_1_part0_r[35]};
            inverse0_sum0_1_part2_r <= inverse0_sum0_1_a2_w_d29_r + inverse0_sum0_1_b2_w_d29_r
            + {16'b0, inverse0_sum0_1_part1_r[35]};
            inverse0_sum0_2_part0_r <= {1'b0, inverse0_sum0_2_a0_w} + {1'b0, inverse0_sum0_2_b0_w};
            inverse0_sum0_2_part1_r <= {1'b0, inverse0_sum0_2_a1_w_d28_r} + {1'b0,
            inverse0_sum0_2_b1_w_d28_r} + {35'b0, inverse0_sum0_2_part0_r[35]};
            inverse0_sum0_2_part2_r <= inverse0_sum0_2_a2_w_d29_r + inverse0_sum0_2_b2_w_d29_r
            + {16'b0, inverse0_sum0_2_part1_r[35]};
            inverse0_sum0_3_part0_r <= {1'b0, inverse0_sum0_3_a0_w} + {1'b0, inverse0_sum0_3_b0_w};
            inverse0_sum0_3_part1_r <= {1'b0, inverse0_sum0_3_a1_w_d28_r} + {1'b0,
            inverse0_sum0_3_b1_w_d28_r} + {35'b0, inverse0_sum0_3_part0_r[35]};
            inverse0_sum0_3_part2_r <= inverse0_sum0_3_a2_w_d29_r + inverse0_sum0_3_b2_w_d29_r
            + {16'b0, inverse0_sum0_3_part1_r[35]};
            inverse0_sum1_0_part0_r <= {1'b0, inverse0_sum1_0_a0_w} + {1'b0, inverse0_sum1_0_b0_w};
            inverse0_sum1_0_part1_r <= {1'b0, inverse0_sum1_0_a1_w_d31_r} + {1'b0,
            inverse0_sum1_0_b1_w_d31_r} + {35'b0, inverse0_sum1_0_part0_r[35]};
            inverse0_sum1_0_part2_r <= inverse0_sum1_0_a2_w_d32_r + inverse0_sum1_0_b2_w_d32_r
            + {16'b0, inverse0_sum1_0_part1_r[35]};
            inverse0_sum1_1_part0_r <= {1'b0, inverse0_sum1_1_a0_w} + {1'b0, inverse0_sum1_1_b0_w};
            inverse0_sum1_1_part1_r <= {1'b0, inverse0_sum1_1_a1_w_d31_r} + {1'b0,
            inverse0_sum1_1_b1_w_d31_r} + {35'b0, inverse0_sum1_1_part0_r[35]};
            inverse0_sum1_1_part2_r <= inverse0_sum1_1_a2_w_d32_r + inverse0_sum1_1_b2_w_d32_r
            + {16'b0, inverse0_sum1_1_part1_r[35]};
            inverse0_sum2_0_part0_r <= {1'b0, inverse0_sum2_0_a0_w} + {1'b0, inverse0_sum2_0_b0_w};
            inverse0_sum2_0_part1_r <= {1'b0, inverse0_sum2_0_a1_w_d34_r} + {1'b0,
            inverse0_sum2_0_b1_w_d34_r} + {35'b0, inverse0_sum2_0_part0_r[35]};
            inverse0_sum2_0_part2_r <= inverse0_sum2_0_a2_w_d35_r + inverse0_sum2_0_b2_w_d35_r
            + {16'b0, inverse0_sum2_0_part1_r[35]};
            inverse_abs0_sign_r <= inverse0_sum2_0_w[86];
            inverse_abs0_invert_r <= inverse0_sum2_0_w[86] ? ~inverse0_sum2_0_w : inverse0_sum2_0_w;
            inverse_abs0_part0_r <= {1'b0, inverse_abs0_a0_w} + {1'b0, inverse_abs0_b0_w};
            inverse_abs0_part1_r <= {1'b0, inverse_abs0_a1_w_d38_r} + {1'b0,
            inverse_abs0_b1_w_d38_r} + {35'b0, inverse_abs0_part0_r[35]};
            inverse_abs0_part2_r <= inverse_abs0_a2_w_d39_r + inverse_abs0_b2_w_d39_r + {16'b0,
            inverse_abs0_part1_r[35]};
            exponent_context_r_0_read1_r <= exponent_context_r[exponent_context_r_0_index1_w];
            rounding_bit0_r <= 7'd29 + {1'b0, exponent_context_r_0_read1_r};
            rounding_shift0_r <= 7'd30 + {1'b0, exponent_context_r_0_read1_r};
        end
    end
    always @(posedge clk_i) begin
        if (pipeline_enable_w[3]) begin
            gradient_bias0_0_r <= gradient_bias0_0_w;
            gradient_bias0_1_r <= gradient_bias0_1_w;
            gradient_bias0_2_r <= gradient_bias0_2_w;
            gradient_bias0_3_r <= gradient_bias0_3_w;
            gradient_round0_part0_r <= {1'b0, gradient_round0_a0_w} + {1'b0, gradient_round0_b0_w};
            gradient_round0_part1_r <= {1'b0, gradient_round0_a1_w_d41_r} + {1'b0,
            gradient_round0_b1_w_d41_r} + {35'b0, gradient_round0_part0_r[35]};
            gradient_round0_part2_r <= gradient_round0_a2_w_d42_r + gradient_round0_b2_w_d42_r
            + {17'b0, gradient_round0_part1_r[35]};
            gradient_shift0_0_r <= gradient_shift0_0_w;
            gradient_shift0_1_r <= gradient_shift0_1_w;
            gradient_shift0_2_r <= gradient_shift0_2_w;
            gradient_shift0_3_r <= unused_gradient_shift0_3_w[55:0];
            gradient_signed0_invert_r <= inverse_abs0_sign_d47_r ? ~gradient56_0_w : gradient56_0_w;
            gradient_signed0_part0_r <= {1'b0, gradient_signed0_a0_w} + {1'b0,
            gradient_signed0_b0_w};
            gradient_signed0_part1_r <= gradient_signed0_a1_w_d49_r +
            gradient_signed0_b1_w_d49_r + {20'b0, gradient_signed0_part0_r[35]};
            offset_context0_r_0_read50_r <= offset_context0_r[offset_context0_r_0_index50_w];
            origin_product0_pp0_0_r <= $signed({1'b0, gradient_signed0_w[0 +: 17]}) *
            $signed(offset_context0_r_0_read50_r);
            origin_product0_pp1_0_r <= $signed({1'b0, gradient_signed0_w[17 +: 17]}) *
            $signed(offset_context0_r_0_read50_r);
            origin_product0_pp2_0_r <= $signed({1'b0, gradient_signed0_w[34 +: 17]}) *
            $signed(offset_context0_r_0_read50_r);
            origin_product0_pp3_0_r <= $signed(gradient_signed0_w[51 +: 5]) *
            $signed(offset_context0_r_0_read50_r);
            origin_product0_sum0_0_part0_r <= {1'b0, origin_product0_sum0_0_a0_w} + {1'b0,
            origin_product0_sum0_0_b0_w};
            origin_product0_sum0_0_part1_r <= {1'b0, origin_product0_sum0_0_a1_w_d52_r} +
            {1'b0, origin_product0_sum0_0_b1_w_d52_r} + {35'b0, origin_product0_sum0_0_part0_r[35]};
            origin_product0_sum0_0_part2_r <= origin_product0_sum0_0_a2_w_d53_r +
            origin_product0_sum0_0_b2_w_d53_r + {3'b0, origin_product0_sum0_0_part1_r[35]};
            origin_product0_sum0_1_part0_r <= {1'b0, origin_product0_sum0_1_a0_w} + {1'b0,
            origin_product0_sum0_1_b0_w};
            origin_product0_sum0_1_part1_r <= {1'b0, origin_product0_sum0_1_a1_w_d52_r} +
            {1'b0, origin_product0_sum0_1_b1_w_d52_r} + {35'b0, origin_product0_sum0_1_part0_r[35]};
            origin_product0_sum0_1_part2_r <= origin_product0_sum0_1_a2_w_d53_r +
            origin_product0_sum0_1_b2_w_d53_r + {3'b0, origin_product0_sum0_1_part1_r[35]};
        end
    end
    always @(posedge clk_i) begin
        if (pipeline_enable_w[4]) begin
            origin_product0_sum1_0_part0_r <= {1'b0, origin_product0_sum1_0_a0_w} + {1'b0,
            origin_product0_sum1_0_b0_w};
            origin_product0_sum1_0_part1_r <= {1'b0, origin_product0_sum1_0_a1_w_d55_r} +
            {1'b0, origin_product0_sum1_0_b1_w_d55_r} + {35'b0, origin_product0_sum1_0_part0_r[35]};
            origin_product0_sum1_0_part2_r <= origin_product0_sum1_0_a2_w_d56_r +
            origin_product0_sum1_0_b2_w_d56_r + {3'b0, origin_product0_sum1_0_part1_r[35]};
            drop_gradient0_r <= tag_0_r[2:0] == 0 ? 4'd7 : tag_0_r[2:0] < 4 ? 4'd3 : 4'd11;
            gradient_abs0_sign_r <= gradient_signed0_w[55];
            gradient_abs0_invert_r <= gradient_signed0_w[55] ? ~gradient_signed0_w :
            gradient_signed0_w;
            gradient_abs0_part0_r <= {1'b0, gradient_abs0_a0_w} + {1'b0, gradient_abs0_b0_w};
            gradient_abs0_part1_r <= gradient_abs0_a1_w_d52_r + gradient_abs0_b1_w_d52_r +
            {20'b0, gradient_abs0_part0_r[35]};
            gradient_drop0_0_r <= gradient_drop0_0_w;
            gradient_drop0_1_r <= unused_gradient_drop0_1_w[52:0];
            stored_round0_part0_r <= {1'b0, stored_round0_a0_w} + {1'b0, stored_round0_b0_w};
            stored_round0_part1_r <= stored_round0_a1_w_d56_r + stored_round0_b1_w_d56_r +
            {16'b0, stored_round0_part0_r[35]};
            stored_signed0_invert_r <= gradient_abs0_sign_d57_r ? ~stored_round0_w :
            stored_round0_w;
            stored_signed0_part0_r <= {1'b0, stored_signed0_a0_w} + {1'b0, stored_signed0_b0_w};
            stored_signed0_part1_r <= stored_signed0_a1_w_d59_r + stored_signed0_b1_w_d59_r +
            {16'b0, stored_signed0_part0_r[35]};
            delta_context2_r_0_read20_r <= delta_context2_r[delta_context2_r_0_index20_w];
            product1_0_pp0_0_r <= $signed({1'b0, difference0_r[0 +: 17]}) *
            $signed(delta_context2_r_0_read20_r);
            product1_0_pp1_0_r <= $signed(difference0_r[17 +: 17]) *
            $signed(delta_context2_r_0_read20_r);
            product1_0_sum0_0_part0_r <= {1'b0, product1_0_sum0_0_a0_w} + {1'b0,
            product1_0_sum0_0_b0_w};
            product1_0_sum0_0_part1_r <= product1_0_sum0_0_a1_w_d22_r +
            product1_0_sum0_0_b1_w_d22_r + {16'b0, product1_0_sum0_0_part0_r[35]};
            delta_context3_r_0_read20_r <= delta_context3_r[delta_context3_r_0_index20_w];
            product1_1_pp0_0_r <= $signed({1'b0, difference1_r[0 +: 17]}) *
            $signed(delta_context3_r_0_read20_r);
            product1_1_pp1_0_r <= $signed(difference1_r[17 +: 17]) *
            $signed(delta_context3_r_0_read20_r);
            product1_1_sum0_0_part0_r <= {1'b0, product1_1_sum0_0_a0_w} + {1'b0,
            product1_1_sum0_0_b0_w};
            product1_1_sum0_0_part1_r <= product1_1_sum0_0_a1_w_d22_r +
            product1_1_sum0_0_b1_w_d22_r + {16'b0, product1_1_sum0_0_part0_r[35]};
            numerator1_part0_r <= {1'b0, numerator1_a0_w} + {1'b0, numerator1_b0_w};
            numerator1_part1_r <= numerator1_a1_w_d24_r + numerator1_b1_w_d24_r + {20'b0,
            numerator1_part0_r[35]};
            numerator_shift1_r <= numerator1_w << 4;
            inverse1_pp0_0_r <= $signed({1'b0, numerator_shift1_r[0 +: 17]}) * $signed({1'b0,
            reciprocal_context_r_0_read26_r[0 +: 17]});
            inverse1_pp0_1_r <= $signed({1'b0, numerator_shift1_r[0 +: 17]}) * $signed({1'b0,
            reciprocal_context_r_0_read26_r[17 +: 14]});
            inverse1_pp1_0_r <= $signed({1'b0, numerator_shift1_r[17 +: 17]}) * $signed({1'b0,
            reciprocal_context_r_0_read26_r[0 +: 17]});
            inverse1_pp1_1_r <= $signed({1'b0, numerator_shift1_r[17 +: 17]}) * $signed({1'b0,
            reciprocal_context_r_0_read26_r[17 +: 14]});
            inverse1_pp2_0_r <= $signed({1'b0, numerator_shift1_r[34 +: 17]}) * $signed({1'b0,
            reciprocal_context_r_0_read26_r[0 +: 17]});
            inverse1_pp2_1_r <= $signed({1'b0, numerator_shift1_r[34 +: 17]}) * $signed({1'b0,
            reciprocal_context_r_0_read26_r[17 +: 14]});
            inverse1_pp3_0_r <= $signed(numerator_shift1_r[51 +: 5]) * $signed({1'b0,
            reciprocal_context_r_0_read26_r[0 +: 17]});
            inverse1_pp3_1_r <= $signed(numerator_shift1_r[51 +: 5]) * $signed({1'b0,
            reciprocal_context_r_0_read26_r[17 +: 14]});
            inverse1_sum0_0_part0_r <= {1'b0, inverse1_sum0_0_a0_w} + {1'b0, inverse1_sum0_0_b0_w};
            inverse1_sum0_0_part1_r <= {1'b0, inverse1_sum0_0_a1_w_d28_r} + {1'b0,
            inverse1_sum0_0_b1_w_d28_r} + {35'b0, inverse1_sum0_0_part0_r[35]};
            inverse1_sum0_0_part2_r <= inverse1_sum0_0_a2_w_d29_r + inverse1_sum0_0_b2_w_d29_r
            + {16'b0, inverse1_sum0_0_part1_r[35]};
        end
    end
    always @(posedge clk_i) begin
        if (pipeline_enable_w[5]) begin
            inverse1_sum0_1_part0_r <= {1'b0, inverse1_sum0_1_a0_w} + {1'b0, inverse1_sum0_1_b0_w};
            inverse1_sum0_1_part1_r <= {1'b0, inverse1_sum0_1_a1_w_d28_r} + {1'b0,
            inverse1_sum0_1_b1_w_d28_r} + {35'b0, inverse1_sum0_1_part0_r[35]};
            inverse1_sum0_1_part2_r <= inverse1_sum0_1_a2_w_d29_r + inverse1_sum0_1_b2_w_d29_r
            + {16'b0, inverse1_sum0_1_part1_r[35]};
            inverse1_sum0_2_part0_r <= {1'b0, inverse1_sum0_2_a0_w} + {1'b0, inverse1_sum0_2_b0_w};
            inverse1_sum0_2_part1_r <= {1'b0, inverse1_sum0_2_a1_w_d28_r} + {1'b0,
            inverse1_sum0_2_b1_w_d28_r} + {35'b0, inverse1_sum0_2_part0_r[35]};
            inverse1_sum0_2_part2_r <= inverse1_sum0_2_a2_w_d29_r + inverse1_sum0_2_b2_w_d29_r
            + {16'b0, inverse1_sum0_2_part1_r[35]};
            inverse1_sum0_3_part0_r <= {1'b0, inverse1_sum0_3_a0_w} + {1'b0, inverse1_sum0_3_b0_w};
            inverse1_sum0_3_part1_r <= {1'b0, inverse1_sum0_3_a1_w_d28_r} + {1'b0,
            inverse1_sum0_3_b1_w_d28_r} + {35'b0, inverse1_sum0_3_part0_r[35]};
            inverse1_sum0_3_part2_r <= inverse1_sum0_3_a2_w_d29_r + inverse1_sum0_3_b2_w_d29_r
            + {16'b0, inverse1_sum0_3_part1_r[35]};
            inverse1_sum1_0_part0_r <= {1'b0, inverse1_sum1_0_a0_w} + {1'b0, inverse1_sum1_0_b0_w};
            inverse1_sum1_0_part1_r <= {1'b0, inverse1_sum1_0_a1_w_d31_r} + {1'b0,
            inverse1_sum1_0_b1_w_d31_r} + {35'b0, inverse1_sum1_0_part0_r[35]};
            inverse1_sum1_0_part2_r <= inverse1_sum1_0_a2_w_d32_r + inverse1_sum1_0_b2_w_d32_r
            + {16'b0, inverse1_sum1_0_part1_r[35]};
            inverse1_sum1_1_part0_r <= {1'b0, inverse1_sum1_1_a0_w} + {1'b0, inverse1_sum1_1_b0_w};
            inverse1_sum1_1_part1_r <= {1'b0, inverse1_sum1_1_a1_w_d31_r} + {1'b0,
            inverse1_sum1_1_b1_w_d31_r} + {35'b0, inverse1_sum1_1_part0_r[35]};
            inverse1_sum1_1_part2_r <= inverse1_sum1_1_a2_w_d32_r + inverse1_sum1_1_b2_w_d32_r
            + {16'b0, inverse1_sum1_1_part1_r[35]};
            inverse1_sum2_0_part0_r <= {1'b0, inverse1_sum2_0_a0_w} + {1'b0, inverse1_sum2_0_b0_w};
            inverse1_sum2_0_part1_r <= {1'b0, inverse1_sum2_0_a1_w_d34_r} + {1'b0,
            inverse1_sum2_0_b1_w_d34_r} + {35'b0, inverse1_sum2_0_part0_r[35]};
            inverse1_sum2_0_part2_r <= inverse1_sum2_0_a2_w_d35_r + inverse1_sum2_0_b2_w_d35_r
            + {16'b0, inverse1_sum2_0_part1_r[35]};
            inverse_abs1_sign_r <= inverse1_sum2_0_w[86];
            inverse_abs1_invert_r <= inverse1_sum2_0_w[86] ? ~inverse1_sum2_0_w : inverse1_sum2_0_w;
            inverse_abs1_part0_r <= {1'b0, inverse_abs1_a0_w} + {1'b0, inverse_abs1_b0_w};
            inverse_abs1_part1_r <= {1'b0, inverse_abs1_a1_w_d38_r} + {1'b0,
            inverse_abs1_b1_w_d38_r} + {35'b0, inverse_abs1_part0_r[35]};
            inverse_abs1_part2_r <= inverse_abs1_a2_w_d39_r + inverse_abs1_b2_w_d39_r + {16'b0,
            inverse_abs1_part1_r[35]};
            rounding_bit1_r <= 7'd29 + {1'b0, exponent_context_r_0_read1_r};
            rounding_shift1_r <= 7'd30 + {1'b0, exponent_context_r_0_read1_r};
            gradient_bias1_0_r <= gradient_bias1_0_w;
            gradient_bias1_1_r <= gradient_bias1_1_w;
            gradient_bias1_2_r <= gradient_bias1_2_w;
            gradient_bias1_3_r <= gradient_bias1_3_w;
            gradient_round1_part0_r <= {1'b0, gradient_round1_a0_w} + {1'b0, gradient_round1_b0_w};
            gradient_round1_part1_r <= {1'b0, gradient_round1_a1_w_d41_r} + {1'b0,
            gradient_round1_b1_w_d41_r} + {35'b0, gradient_round1_part0_r[35]};
            gradient_round1_part2_r <= gradient_round1_a2_w_d42_r + gradient_round1_b2_w_d42_r
            + {17'b0, gradient_round1_part1_r[35]};
        end
    end
    always @(posedge clk_i) begin
        if (pipeline_enable_w[6]) begin
            gradient_shift1_0_r <= gradient_shift1_0_w;
            gradient_shift1_1_r <= gradient_shift1_1_w;
            gradient_shift1_2_r <= gradient_shift1_2_w;
            gradient_shift1_3_r <= unused_gradient_shift1_3_w[55:0];
            gradient_signed1_invert_r <= inverse_abs1_sign_d47_r ? ~gradient56_1_w : gradient56_1_w;
            gradient_signed1_part0_r <= {1'b0, gradient_signed1_a0_w} + {1'b0,
            gradient_signed1_b0_w};
            gradient_signed1_part1_r <= gradient_signed1_a1_w_d49_r +
            gradient_signed1_b1_w_d49_r + {20'b0, gradient_signed1_part0_r[35]};
            offset_context1_r_0_read50_r <= offset_context1_r[offset_context1_r_0_index50_w];
            origin_product1_pp0_0_r <= $signed({1'b0, gradient_signed1_w[0 +: 17]}) *
            $signed(offset_context1_r_0_read50_r);
            origin_product1_pp1_0_r <= $signed({1'b0, gradient_signed1_w[17 +: 17]}) *
            $signed(offset_context1_r_0_read50_r);
            origin_product1_pp2_0_r <= $signed({1'b0, gradient_signed1_w[34 +: 17]}) *
            $signed(offset_context1_r_0_read50_r);
            origin_product1_pp3_0_r <= $signed(gradient_signed1_w[51 +: 5]) *
            $signed(offset_context1_r_0_read50_r);
            origin_product1_sum0_0_part0_r <= {1'b0, origin_product1_sum0_0_a0_w} + {1'b0,
            origin_product1_sum0_0_b0_w};
            origin_product1_sum0_0_part1_r <= {1'b0, origin_product1_sum0_0_a1_w_d52_r} +
            {1'b0, origin_product1_sum0_0_b1_w_d52_r} + {35'b0, origin_product1_sum0_0_part0_r[35]};
            origin_product1_sum0_0_part2_r <= origin_product1_sum0_0_a2_w_d53_r +
            origin_product1_sum0_0_b2_w_d53_r + {3'b0, origin_product1_sum0_0_part1_r[35]};
            origin_product1_sum0_1_part0_r <= {1'b0, origin_product1_sum0_1_a0_w} + {1'b0,
            origin_product1_sum0_1_b0_w};
            origin_product1_sum0_1_part1_r <= {1'b0, origin_product1_sum0_1_a1_w_d52_r} +
            {1'b0, origin_product1_sum0_1_b1_w_d52_r} + {35'b0, origin_product1_sum0_1_part0_r[35]};
            origin_product1_sum0_1_part2_r <= origin_product1_sum0_1_a2_w_d53_r +
            origin_product1_sum0_1_b2_w_d53_r + {3'b0, origin_product1_sum0_1_part1_r[35]};
            origin_product1_sum1_0_part0_r <= {1'b0, origin_product1_sum1_0_a0_w} + {1'b0,
            origin_product1_sum1_0_b0_w};
            origin_product1_sum1_0_part1_r <= {1'b0, origin_product1_sum1_0_a1_w_d55_r} +
            {1'b0, origin_product1_sum1_0_b1_w_d55_r} + {35'b0, origin_product1_sum1_0_part0_r[35]};
            origin_product1_sum1_0_part2_r <= origin_product1_sum1_0_a2_w_d56_r +
            origin_product1_sum1_0_b2_w_d56_r + {3'b0, origin_product1_sum1_0_part1_r[35]};
            drop_gradient1_r <= tag_0_r[2:0] == 0 ? 4'd7 : tag_0_r[2:0] < 4 ? 4'd3 : 4'd11;
            gradient_abs1_sign_r <= gradient_signed1_w[55];
            gradient_abs1_invert_r <= gradient_signed1_w[55] ? ~gradient_signed1_w :
            gradient_signed1_w;
            gradient_abs1_part0_r <= {1'b0, gradient_abs1_a0_w} + {1'b0, gradient_abs1_b0_w};
            gradient_abs1_part1_r <= gradient_abs1_a1_w_d52_r + gradient_abs1_b1_w_d52_r +
            {20'b0, gradient_abs1_part0_r[35]};
            gradient_drop1_0_r <= gradient_drop1_0_w;
            gradient_drop1_1_r <= unused_gradient_drop1_1_w[52:0];
            stored_round1_part0_r <= {1'b0, stored_round1_a0_w} + {1'b0, stored_round1_b0_w};
            stored_round1_part1_r <= stored_round1_a1_w_d56_r + stored_round1_b1_w_d56_r +
            {16'b0, stored_round1_part0_r[35]};
            stored_signed1_invert_r <= gradient_abs1_sign_d57_r ? ~stored_round1_w :
            stored_round1_w;
            stored_signed1_part0_r <= {1'b0, stored_signed1_a0_w} + {1'b0, stored_signed1_b0_w};
            stored_signed1_part1_r <= stored_signed1_a1_w_d59_r + stored_signed1_b1_w_d59_r +
            {16'b0, stored_signed1_part0_r[35]};
        end
    end
    always @(posedge clk_i) begin
        if (pipeline_enable_w[7]) begin
            origin_sum_part0_r <= {1'b0, origin_sum_a0_w} + {1'b0, origin_sum_b0_w};
            origin_sum_part1_r <= {1'b0, origin_sum_a1_w_d58_r} + {1'b0, origin_sum_b1_w_d58_r}
            + {35'b0, origin_sum_part0_r[35]};
            origin_sum_part2_r <= origin_sum_a2_w_d59_r + origin_sum_b2_w_d59_r + {4'b0,
            origin_sum_part1_r[35]};
            origin_absolute_sign_r <= origin_sum_w[74];
            origin_absolute_invert_r <= origin_sum_w[74] ? ~origin_sum_w : origin_sum_w;
            origin_absolute_part0_r <= {1'b0, origin_absolute_a0_w} + {1'b0, origin_absolute_b0_w};
            origin_absolute_part1_r <= {1'b0, origin_absolute_a1_w_d62_r} + {1'b0,
            origin_absolute_b1_w_d62_r} + {35'b0, origin_absolute_part0_r[35]};
            origin_absolute_part2_r <= origin_absolute_a2_w_d63_r + origin_absolute_b2_w_d63_r
            + {4'b0, origin_absolute_part1_r[35]};
            origin_round_part0_r <= {1'b0, origin_round_a0_w} + {1'b0, origin_round_b0_w};
            origin_round_part1_r <= {1'b0, origin_round_a1_w_d65_r} + {1'b0,
            origin_round_b1_w_d65_r} + {35'b0, origin_round_part0_r[35]};
            origin_round_part2_r <= origin_round_a2_w_d66_r + origin_round_b2_w_d66_r + {4'b0,
            origin_round_part1_r[35]};
            origin_shift_r <= origin_round_w >> 4;
            origin_signed_invert_r <= origin_absolute_sign_d68_r ? ~origin_shift_r : origin_shift_r;
            origin_signed_part0_r <= {1'b0, origin_signed_a0_w} + {1'b0, origin_signed_b0_w};
            origin_signed_part1_r <= {1'b0, origin_signed_a1_w_d70_r} + {1'b0,
            origin_signed_b1_w_d70_r} + {35'b0, origin_signed_part0_r[35]};
            origin_signed_part2_r <= origin_signed_a2_w_d71_r + origin_signed_b2_w_d71_r +
            {4'b0, origin_signed_part1_r[35]};
            start_sum_part0_r <= {1'b0, start_sum_a0_w} + {1'b0, start_sum_b0_w};
            start_sum_part1_r <= start_sum_a1_w_d73_r + start_sum_b1_w_d73_r + {34'b0,
            start_sum_part0_r[35]};
            start_absolute_sign_r <= start_sum_w[69];
            start_absolute_invert_r <= start_sum_w[69] ? ~start_sum_w : start_sum_w;
            start_absolute_part0_r <= {1'b0, start_absolute_a0_w} + {1'b0, start_absolute_b0_w};
            start_absolute_part1_r <= start_absolute_a1_w_d76_r + start_absolute_b1_w_d76_r +
            {34'b0, start_absolute_part0_r[35]};
            drop_start_r <= tag_0_r[2:0] == 0 ? 4'd7 : tag_0_r[2:0] < 4 ? 4'd3 : 4'd11;
            start_drop_0_r <= start_drop_0_w;
            start_drop_1_r <= unused_start_drop_1_w[66:0];
            start_round_part0_r <= {1'b0, start_round_a0_w} + {1'b0, start_round_b0_w};
            start_round_part1_r <= start_round_a1_w_d80_r + start_round_b1_w_d80_r + {30'b0,
            start_round_part0_r[35]};
            start_signed_invert_r <= start_absolute_sign_d81_r ? ~start_round_w : start_round_w;
            start_signed_part0_r <= {1'b0, start_signed_a0_w} + {1'b0, start_signed_b0_w};
            start_signed_part1_r <= start_signed_a1_w_d83_r + start_signed_b1_w_d83_r + {30'b0,
            start_signed_part0_r[35]};
            vertex0_w_delay1_r <= vertex0_w;
            vertex1_w_delay1_r <= vertex1_w;
        end
    end
    always @(posedge clk_i) begin
        if (pipeline_enable_w[8]) begin
            vertex2_w_delay1_r <= vertex2_w;
            vertex2_w_delay2_r <= vertex2_w_delay1_r;
            vertex2_w_delay3_r <= vertex2_w_d2_r;
            maximum01_select_delay3_r <= maximum01_select_r;
            nonzero_groups_delay6_r <= nonzero_groups_r;
            tag_0_r_delay1_r <= tag_0_r;
            tag_0_r_delay2_r <= tag_0_r_delay1_r;
            tag_0_r_delay3_r <= tag_0_r_delay2_r;
            tag_0_r_delay4_r <= tag_0_r_delay3_r;
            tag_0_r_delay5_r <= tag_0_r_delay4_r;
            tag_0_r_delay6_r <= tag_0_r_delay5_r;
            tag_0_r_delay7_r <= tag_0_r_delay6_r;
            tag_0_r_delay8_r <= tag_0_r_d7_r;
            tag_0_r_delay9_r <= tag_0_r_delay8_r;
            tag_0_r_delay10_r <= tag_0_r_delay9_r;
            tag_0_r_delay11_r <= tag_0_r_delay10_r;
            tag_0_r_delay12_r <= tag_0_r_delay11_r;
            tag_0_r_delay13_r <= tag_0_r_delay12_r;
            tag_0_r_delay14_r <= tag_0_r_delay13_r;
            tag_0_r_delay15_r <= tag_0_r_delay14_r;
            tag_0_r_delay16_r <= tag_0_r_delay15_r;
            tag_0_r_delay17_r <= tag_0_r_delay16_r;
            tag_0_r_delay18_r <= tag_0_r_delay17_r;
            tag_0_r_delay19_r <= tag_0_r_delay18_r;
            tag_0_r_delay20_r <= tag_0_r_d19_r;
            tag_0_r_delay21_r <= tag_0_r_delay20_r;
            tag_0_r_delay22_r <= tag_0_r_delay21_r;
            tag_0_r_delay23_r <= tag_0_r_delay22_r;
            tag_0_r_delay24_r <= tag_0_r_delay23_r;
            tag_0_r_delay25_r <= tag_0_r_delay24_r;
            tag_0_r_delay26_r <= tag_0_r_d25_r;
            tag_0_r_delay27_r <= tag_0_r_delay26_r;
            tag_0_r_delay28_r <= tag_0_r_delay27_r;
            tag_0_r_delay29_r <= tag_0_r_delay28_r;
            tag_0_r_delay30_r <= tag_0_r_delay29_r;
            tag_0_r_delay31_r <= tag_0_r_delay30_r;
            tag_0_r_delay32_r <= tag_0_r_delay31_r;
            tag_0_r_delay33_r <= tag_0_r_delay32_r;
            tag_0_r_delay34_r <= tag_0_r_delay33_r;
            tag_0_r_delay35_r <= tag_0_r_delay34_r;
            tag_0_r_delay36_r <= tag_0_r_delay35_r;
            tag_0_r_delay37_r <= tag_0_r_delay36_r;
            tag_0_r_delay38_r <= tag_0_r_delay37_r;
            tag_0_r_delay39_r <= tag_0_r_delay38_r;
            tag_0_r_delay40_r <= tag_0_r_delay39_r;
            tag_0_r_delay41_r <= tag_0_r_delay40_r;
            tag_0_r_delay42_r <= tag_0_r_delay41_r;
            tag_0_r_delay43_r <= tag_0_r_delay42_r;
            tag_0_r_delay44_r <= tag_0_r_delay43_r;
            tag_0_r_delay45_r <= tag_0_r_delay44_r;
            tag_0_r_delay46_r <= tag_0_r_delay45_r;
            tag_0_r_delay47_r <= tag_0_r_delay46_r;
            tag_0_r_delay48_r <= tag_0_r_delay47_r;
            tag_0_r_delay49_r <= tag_0_r_delay48_r;
            tag_0_r_delay50_r <= tag_0_r_d49_r;
            tag_0_r_delay51_r <= tag_0_r_delay50_r;
            tag_0_r_delay52_r <= tag_0_r_delay51_r;
            tag_0_r_delay53_r <= tag_0_r_delay52_r;
            tag_0_r_delay54_r <= tag_0_r_delay53_r;
            tag_0_r_delay55_r <= tag_0_r_delay54_r;
            tag_0_r_delay56_r <= tag_0_r_delay55_r;
            tag_0_r_delay57_r <= tag_0_r_delay56_r;
            tag_0_r_delay58_r <= tag_0_r_delay57_r;
            tag_0_r_delay59_r <= tag_0_r_delay58_r;
            tag_0_r_delay60_r <= tag_0_r_delay59_r;
            tag_0_r_delay61_r <= tag_0_r_delay60_r;
            tag_0_r_delay62_r <= tag_0_r_delay61_r;
            tag_0_r_delay63_r <= tag_0_r_delay62_r;
            tag_0_r_delay64_r <= tag_0_r_delay63_r;
            tag_0_r_delay65_r <= tag_0_r_delay64_r;
            tag_0_r_delay66_r <= tag_0_r_delay65_r;
            tag_0_r_delay67_r <= tag_0_r_delay66_r;
            tag_0_r_delay68_r <= tag_0_r_delay67_r;
            tag_0_r_delay69_r <= tag_0_r_delay68_r;
            tag_0_r_delay70_r <= tag_0_r_delay69_r;
            tag_0_r_delay71_r <= tag_0_r_delay70_r;
            tag_0_r_delay72_r <= tag_0_r_delay71_r;
            tag_0_r_delay73_r <= tag_0_r_delay72_r;
            tag_0_r_delay74_r <= tag_0_r_delay73_r;
            tag_0_r_delay75_r <= tag_0_r_delay74_r;
            tag_0_r_delay76_r <= tag_0_r_delay75_r;
            tag_0_r_delay77_r <= tag_0_r_delay76_r;
            tag_0_r_delay78_r <= tag_0_r_delay77_r;
            tag_0_r_delay79_r <= tag_0_r_delay78_r;
            tag_0_r_delay80_r <= tag_0_r_delay79_r;
            tag_0_r_delay81_r <= tag_0_r_delay80_r;
            tag_0_r_delay82_r <= tag_0_r_delay81_r;
            tag_0_r_delay83_r <= tag_0_r_delay82_r;
            tag_0_r_delay84_r <= tag_0_r_delay83_r;
            maximum012_select_delay5_r <= maximum012_select_r;
            maximum012_select_delay6_r <= maximum012_select_delay5_r;
            maximum012_select_delay7_r <= maximum012_select_delay6_r;
            v52_0_w_delay10_r <= v52_0_w_d9_r;
            v52_0_w_delay11_r <= v52_0_w_delay10_r;
            v52_0_w_delay12_r <= v52_0_w_delay11_r;
            v52_0_w_delay13_r <= v52_0_w_delay12_r;
            scale_left0_amt1_w_delay10_r <= scale_left0_amt1_w;
            scale_left0_amt2_w_delay10_r <= scale_left0_amt2_w;
            scale_left0_amt2_w_delay11_r <= scale_left0_amt2_w_delay10_r;
            scale_bias0_amt1_w_delay11_r <= scale_bias0_amt1_w;
            scale_bias0_amt2_w_delay11_r <= scale_bias0_amt2_w;
            scale_bias0_amt2_w_delay12_r <= scale_bias0_amt2_w_delay11_r;
            scale_add0_a1_w_delay14_r <= scale_add0_a1_w;
        end
    end
    always @(posedge clk_i) begin
        if (pipeline_enable_w[9]) begin
            scale_add0_b1_w_delay14_r <= scale_add0_b1_w;
            scale_add0_low0_w_delay15_r <= scale_add0_low0_w;
            scale_rounded0_amt0_w_delay10_r <= scale_rounded0_amt0_w;
            scale_rounded0_amt0_w_delay11_r <= scale_rounded0_amt0_w_delay10_r;
            scale_rounded0_amt0_w_delay12_r <= scale_rounded0_amt0_w_delay11_r;
            scale_rounded0_amt0_w_delay13_r <= scale_rounded0_amt0_w_delay12_r;
            scale_rounded0_amt0_w_delay14_r <= scale_rounded0_amt0_w_delay13_r;
            scale_rounded0_amt0_w_delay15_r <= scale_rounded0_amt0_w_delay14_r;
            scale_rounded0_amt1_w_delay10_r <= scale_rounded0_amt1_w;
            scale_rounded0_amt1_w_delay11_r <= scale_rounded0_amt1_w_delay10_r;
            scale_rounded0_amt1_w_delay12_r <= scale_rounded0_amt1_w_delay11_r;
            scale_rounded0_amt1_w_delay13_r <= scale_rounded0_amt1_w_delay12_r;
            scale_rounded0_amt1_w_delay14_r <= scale_rounded0_amt1_w_delay13_r;
            scale_rounded0_amt1_w_delay15_r <= scale_rounded0_amt1_w_delay14_r;
            scale_rounded0_amt1_w_delay16_r <= scale_rounded0_amt1_w_delay15_r;
            scale_rounded0_amt2_w_delay10_r <= scale_rounded0_amt2_w;
            scale_rounded0_amt2_w_delay11_r <= scale_rounded0_amt2_w_delay10_r;
            scale_rounded0_amt2_w_delay12_r <= scale_rounded0_amt2_w_delay11_r;
            scale_rounded0_amt2_w_delay13_r <= scale_rounded0_amt2_w_delay12_r;
            scale_rounded0_amt2_w_delay14_r <= scale_rounded0_amt2_w_delay13_r;
            scale_rounded0_amt2_w_delay15_r <= scale_rounded0_amt2_w_delay14_r;
            scale_rounded0_amt2_w_delay16_r <= scale_rounded0_amt2_w_delay15_r;
            scale_rounded0_amt2_w_delay17_r <= scale_rounded0_amt2_w_delay16_r;
            h_delay9_r <= h_r;
            h_delay10_r <= h_delay9_r;
            h_delay11_r <= h_delay10_r;
            h_delay12_r <= h_delay11_r;
            h_delay13_r <= h_delay12_r;
            h_delay14_r <= h_delay13_r;
            h_delay15_r <= h_delay14_r;
            h_delay16_r <= h_delay15_r;
            h_delay17_r <= h_delay16_r;
            h_delay18_r <= h_delay17_r;
            h_delay19_r <= h_d18_r;
            h_delay20_r <= h_delay19_r;
            h_delay21_r <= h_delay20_r;
            h_delay22_r <= h_delay21_r;
            h_delay23_r <= h_delay22_r;
            h_delay24_r <= h_delay23_r;
            h_delay25_r <= h_delay24_r;
            h_delay26_r <= h_delay25_r;
            h_delay27_r <= h_delay26_r;
            h_delay28_r <= h_delay27_r;
            h_delay29_r <= h_delay28_r;
            h_delay30_r <= h_delay29_r;
            h_delay31_r <= h_delay30_r;
            h_delay32_r <= h_delay31_r;
            h_delay33_r <= h_delay32_r;
            h_delay34_r <= h_delay33_r;
            h_delay35_r <= h_delay34_r;
            h_delay36_r <= h_delay35_r;
            h_delay37_r <= h_delay36_r;
            h_delay38_r <= h_delay37_r;
            h_delay39_r <= h_delay38_r;
            h_delay40_r <= h_delay39_r;
            h_delay41_r <= h_delay40_r;
            h_delay42_r <= h_delay41_r;
            h_delay43_r <= h_delay42_r;
            h_delay44_r <= h_delay43_r;
            h_delay45_r <= h_delay44_r;
            h_delay46_r <= h_delay45_r;
            h_delay47_r <= h_delay46_r;
            h_delay48_r <= h_delay47_r;
            h_delay49_r <= h_delay48_r;
            h_delay50_r <= h_delay49_r;
            h_delay51_r <= h_delay50_r;
            h_delay52_r <= h_delay51_r;
            h_delay53_r <= h_delay52_r;
            h_delay54_r <= h_delay53_r;
            h_delay55_r <= h_delay54_r;
            h_delay56_r <= h_delay55_r;
            h_delay57_r <= h_delay56_r;
            h_delay58_r <= h_delay57_r;
            h_delay59_r <= h_delay58_r;
            h_delay60_r <= h_delay59_r;
            h_delay61_r <= h_delay60_r;
            h_delay62_r <= h_delay61_r;
            h_delay63_r <= h_delay62_r;
            h_delay64_r <= h_delay63_r;
            h_delay65_r <= h_delay64_r;
            h_delay66_r <= h_delay65_r;
            h_delay67_r <= h_delay66_r;
            h_delay68_r <= h_delay67_r;
            h_delay69_r <= h_delay68_r;
            h_delay70_r <= h_delay69_r;
            h_delay71_r <= h_delay70_r;
            h_delay72_r <= h_delay71_r;
            h_delay73_r <= h_delay72_r;
            h_delay74_r <= h_delay73_r;
            h_delay75_r <= h_delay74_r;
            h_delay76_r <= h_delay75_r;
            h_delay77_r <= h_delay76_r;
            h_delay78_r <= h_delay77_r;
            h_delay79_r <= h_delay78_r;
            h_delay80_r <= h_delay79_r;
            h_delay81_r <= h_delay80_r;
            h_delay82_r <= h_delay81_r;
            h_delay83_r <= h_delay82_r;
            h_delay84_r <= h_delay83_r;
            scale_left0_2_r_delay13_r <= scale_left0_2_r;
            scale_left0_2_r_delay14_r <= scale_left0_2_r_delay13_r;
            scale_left0_2_r_delay15_r <= scale_left0_2_r_delay14_r;
            scale_left0_2_r_delay16_r <= scale_left0_2_r_delay15_r;
            scale_left0_2_r_delay17_r <= scale_left0_2_r_delay16_r;
            scale_left0_2_r_delay18_r <= scale_left0_2_r_delay17_r;
            v52_1_w_delay10_r <= v52_1_w_d9_r;
            v52_1_w_delay11_r <= v52_1_w_delay10_r;
        end
    end
    always @(posedge clk_i) begin
        if (pipeline_enable_w[10]) begin
            v52_1_w_delay12_r <= v52_1_w_delay11_r;
            v52_1_w_delay13_r <= v52_1_w_delay12_r;
            scale_left1_amt1_w_delay10_r <= scale_left1_amt1_w;
            scale_left1_amt2_w_delay10_r <= scale_left1_amt2_w;
            scale_left1_amt2_w_delay11_r <= scale_left1_amt2_w_delay10_r;
            scale_bias1_amt1_w_delay11_r <= scale_bias1_amt1_w;
            scale_bias1_amt2_w_delay11_r <= scale_bias1_amt2_w;
            scale_bias1_amt2_w_delay12_r <= scale_bias1_amt2_w_delay11_r;
            scale_add1_a1_w_delay14_r <= scale_add1_a1_w;
            scale_add1_b1_w_delay14_r <= scale_add1_b1_w;
            scale_add1_low0_w_delay15_r <= scale_add1_low0_w;
            scale_rounded1_amt0_w_delay10_r <= scale_rounded1_amt0_w;
            scale_rounded1_amt0_w_delay11_r <= scale_rounded1_amt0_w_delay10_r;
            scale_rounded1_amt0_w_delay12_r <= scale_rounded1_amt0_w_delay11_r;
            scale_rounded1_amt0_w_delay13_r <= scale_rounded1_amt0_w_delay12_r;
            scale_rounded1_amt0_w_delay14_r <= scale_rounded1_amt0_w_delay13_r;
            scale_rounded1_amt0_w_delay15_r <= scale_rounded1_amt0_w_delay14_r;
            scale_rounded1_amt1_w_delay10_r <= scale_rounded1_amt1_w;
            scale_rounded1_amt1_w_delay11_r <= scale_rounded1_amt1_w_delay10_r;
            scale_rounded1_amt1_w_delay12_r <= scale_rounded1_amt1_w_delay11_r;
            scale_rounded1_amt1_w_delay13_r <= scale_rounded1_amt1_w_delay12_r;
            scale_rounded1_amt1_w_delay14_r <= scale_rounded1_amt1_w_delay13_r;
            scale_rounded1_amt1_w_delay15_r <= scale_rounded1_amt1_w_delay14_r;
            scale_rounded1_amt1_w_delay16_r <= scale_rounded1_amt1_w_delay15_r;
            scale_rounded1_amt2_w_delay10_r <= scale_rounded1_amt2_w;
            scale_rounded1_amt2_w_delay11_r <= scale_rounded1_amt2_w_delay10_r;
            scale_rounded1_amt2_w_delay12_r <= scale_rounded1_amt2_w_delay11_r;
            scale_rounded1_amt2_w_delay13_r <= scale_rounded1_amt2_w_delay12_r;
            scale_rounded1_amt2_w_delay14_r <= scale_rounded1_amt2_w_delay13_r;
            scale_rounded1_amt2_w_delay15_r <= scale_rounded1_amt2_w_delay14_r;
            scale_rounded1_amt2_w_delay16_r <= scale_rounded1_amt2_w_delay15_r;
            scale_rounded1_amt2_w_delay17_r <= scale_rounded1_amt2_w_delay16_r;
            scale_left1_2_r_delay13_r <= scale_left1_2_r;
            scale_left1_2_r_delay14_r <= scale_left1_2_r_delay13_r;
            scale_left1_2_r_delay15_r <= scale_left1_2_r_delay14_r;
            scale_left1_2_r_delay16_r <= scale_left1_2_r_delay15_r;
            scale_left1_2_r_delay17_r <= scale_left1_2_r_delay16_r;
            scale_left1_2_r_delay18_r <= scale_left1_2_r_delay17_r;
            v52_2_w_delay10_r <= v52_2_w_d9_r;
            v52_2_w_delay11_r <= v52_2_w_delay10_r;
            v52_2_w_delay12_r <= v52_2_w_delay11_r;
            v52_2_w_delay13_r <= v52_2_w_delay12_r;
            scale_left2_amt1_w_delay10_r <= scale_left2_amt1_w;
            scale_left2_amt2_w_delay10_r <= scale_left2_amt2_w;
            scale_left2_amt2_w_delay11_r <= scale_left2_amt2_w_delay10_r;
            scale_bias2_amt1_w_delay11_r <= scale_bias2_amt1_w;
            scale_bias2_amt2_w_delay11_r <= scale_bias2_amt2_w;
            scale_bias2_amt2_w_delay12_r <= scale_bias2_amt2_w_delay11_r;
            scale_add2_a1_w_delay14_r <= scale_add2_a1_w;
            scale_add2_b1_w_delay14_r <= scale_add2_b1_w;
            scale_add2_low0_w_delay15_r <= scale_add2_low0_w;
            scale_rounded2_amt0_w_delay10_r <= scale_rounded2_amt0_w;
            scale_rounded2_amt0_w_delay11_r <= scale_rounded2_amt0_w_delay10_r;
            scale_rounded2_amt0_w_delay12_r <= scale_rounded2_amt0_w_delay11_r;
            scale_rounded2_amt0_w_delay13_r <= scale_rounded2_amt0_w_delay12_r;
            scale_rounded2_amt0_w_delay14_r <= scale_rounded2_amt0_w_delay13_r;
            scale_rounded2_amt0_w_delay15_r <= scale_rounded2_amt0_w_delay14_r;
            scale_rounded2_amt1_w_delay10_r <= scale_rounded2_amt1_w;
            scale_rounded2_amt1_w_delay11_r <= scale_rounded2_amt1_w_delay10_r;
            scale_rounded2_amt1_w_delay12_r <= scale_rounded2_amt1_w_delay11_r;
            scale_rounded2_amt1_w_delay13_r <= scale_rounded2_amt1_w_delay12_r;
            scale_rounded2_amt1_w_delay14_r <= scale_rounded2_amt1_w_delay13_r;
            scale_rounded2_amt1_w_delay15_r <= scale_rounded2_amt1_w_delay14_r;
            scale_rounded2_amt1_w_delay16_r <= scale_rounded2_amt1_w_delay15_r;
            scale_rounded2_amt2_w_delay10_r <= scale_rounded2_amt2_w;
            scale_rounded2_amt2_w_delay11_r <= scale_rounded2_amt2_w_delay10_r;
            scale_rounded2_amt2_w_delay12_r <= scale_rounded2_amt2_w_delay11_r;
            scale_rounded2_amt2_w_delay13_r <= scale_rounded2_amt2_w_delay12_r;
            scale_rounded2_amt2_w_delay14_r <= scale_rounded2_amt2_w_delay13_r;
            scale_rounded2_amt2_w_delay15_r <= scale_rounded2_amt2_w_delay14_r;
            scale_rounded2_amt2_w_delay16_r <= scale_rounded2_amt2_w_delay15_r;
            scale_rounded2_amt2_w_delay17_r <= scale_rounded2_amt2_w_delay16_r;
            scale_left2_2_r_delay13_r <= scale_left2_2_r;
            scale_left2_2_r_delay14_r <= scale_left2_2_r_delay13_r;
            scale_left2_2_r_delay15_r <= scale_left2_2_r_delay14_r;
            scale_left2_2_r_delay16_r <= scale_left2_2_r_delay15_r;
            scale_left2_2_r_delay17_r <= scale_left2_2_r_delay16_r;
            scale_left2_2_r_delay18_r <= scale_left2_2_r_delay17_r;
            product0_0_sum0_0_a1_w_delay22_r <= product0_0_sum0_0_a1_w;
            product0_0_sum0_0_b1_w_delay22_r <= product0_0_sum0_0_b1_w;
            product0_0_sum0_0_low0_w_delay23_r <= product0_0_sum0_0_low0_w;
            product0_1_sum0_0_a1_w_delay22_r <= product0_1_sum0_0_a1_w;
            product0_1_sum0_0_b1_w_delay22_r <= product0_1_sum0_0_b1_w;
            product0_1_sum0_0_low0_w_delay23_r <= product0_1_sum0_0_low0_w;
            numerator0_a1_w_delay24_r <= numerator0_a1_w;
            numerator0_b1_w_delay24_r <= numerator0_b1_w;
            numerator0_low0_w_delay25_r <= numerator0_low0_w;
        end
    end
    always @(posedge clk_i) begin
        if (pipeline_enable_w[11]) begin
            inverse0_sum0_0_a1_w_delay28_r <= inverse0_sum0_0_a1_w;
            inverse0_sum0_0_b1_w_delay28_r <= inverse0_sum0_0_b1_w;
            inverse0_sum0_0_a2_w_delay28_r <= inverse0_sum0_0_a2_w;
            inverse0_sum0_0_a2_w_delay29_r <= inverse0_sum0_0_a2_w_delay28_r;
            inverse0_sum0_0_b2_w_delay28_r <= inverse0_sum0_0_b2_w;
            inverse0_sum0_0_b2_w_delay29_r <= inverse0_sum0_0_b2_w_delay28_r;
            inverse0_sum0_0_low1_w_delay30_r <= inverse0_sum0_0_low1_w;
            inverse0_sum0_0_low0_w_delay29_r <= inverse0_sum0_0_low0_w;
            inverse0_sum0_0_low0_w_delay30_r <= inverse0_sum0_0_low0_w_delay29_r;
            inverse0_sum0_1_a1_w_delay28_r <= inverse0_sum0_1_a1_w;
            inverse0_sum0_1_b1_w_delay28_r <= inverse0_sum0_1_b1_w;
            inverse0_sum0_1_a2_w_delay28_r <= inverse0_sum0_1_a2_w;
            inverse0_sum0_1_a2_w_delay29_r <= inverse0_sum0_1_a2_w_delay28_r;
            inverse0_sum0_1_b2_w_delay28_r <= inverse0_sum0_1_b2_w;
            inverse0_sum0_1_b2_w_delay29_r <= inverse0_sum0_1_b2_w_delay28_r;
            inverse0_sum0_1_low1_w_delay30_r <= inverse0_sum0_1_low1_w;
            inverse0_sum0_1_low0_w_delay29_r <= inverse0_sum0_1_low0_w;
            inverse0_sum0_1_low0_w_delay30_r <= inverse0_sum0_1_low0_w_delay29_r;
            inverse0_sum0_2_a1_w_delay28_r <= inverse0_sum0_2_a1_w;
            inverse0_sum0_2_b1_w_delay28_r <= inverse0_sum0_2_b1_w;
            inverse0_sum0_2_a2_w_delay28_r <= inverse0_sum0_2_a2_w;
            inverse0_sum0_2_a2_w_delay29_r <= inverse0_sum0_2_a2_w_delay28_r;
            inverse0_sum0_2_b2_w_delay28_r <= inverse0_sum0_2_b2_w;
            inverse0_sum0_2_b2_w_delay29_r <= inverse0_sum0_2_b2_w_delay28_r;
            inverse0_sum0_2_low1_w_delay30_r <= inverse0_sum0_2_low1_w;
            inverse0_sum0_2_low0_w_delay29_r <= inverse0_sum0_2_low0_w;
            inverse0_sum0_2_low0_w_delay30_r <= inverse0_sum0_2_low0_w_delay29_r;
            inverse0_sum0_3_a1_w_delay28_r <= inverse0_sum0_3_a1_w;
            inverse0_sum0_3_b1_w_delay28_r <= inverse0_sum0_3_b1_w;
            inverse0_sum0_3_a2_w_delay28_r <= inverse0_sum0_3_a2_w;
            inverse0_sum0_3_a2_w_delay29_r <= inverse0_sum0_3_a2_w_delay28_r;
            inverse0_sum0_3_b2_w_delay28_r <= inverse0_sum0_3_b2_w;
            inverse0_sum0_3_b2_w_delay29_r <= inverse0_sum0_3_b2_w_delay28_r;
            inverse0_sum0_3_low1_w_delay30_r <= inverse0_sum0_3_low1_w;
            inverse0_sum0_3_low0_w_delay29_r <= inverse0_sum0_3_low0_w;
            inverse0_sum0_3_low0_w_delay30_r <= inverse0_sum0_3_low0_w_delay29_r;
            inverse0_sum1_0_a1_w_delay31_r <= inverse0_sum1_0_a1_w;
            inverse0_sum1_0_b1_w_delay31_r <= inverse0_sum1_0_b1_w;
            inverse0_sum1_0_a2_w_delay31_r <= inverse0_sum1_0_a2_w;
            inverse0_sum1_0_a2_w_delay32_r <= inverse0_sum1_0_a2_w_delay31_r;
            inverse0_sum1_0_b2_w_delay31_r <= inverse0_sum1_0_b2_w;
            inverse0_sum1_0_b2_w_delay32_r <= inverse0_sum1_0_b2_w_delay31_r;
            inverse0_sum1_0_low1_w_delay33_r <= inverse0_sum1_0_low1_w;
            inverse0_sum1_0_low0_w_delay32_r <= inverse0_sum1_0_low0_w;
        end
    end
    always @(posedge clk_i) begin
        if (pipeline_enable_w[12]) begin
            inverse0_sum1_0_low0_w_delay33_r <= inverse0_sum1_0_low0_w_delay32_r;
            inverse0_sum1_1_a1_w_delay31_r <= inverse0_sum1_1_a1_w;
            inverse0_sum1_1_b1_w_delay31_r <= inverse0_sum1_1_b1_w;
            inverse0_sum1_1_a2_w_delay31_r <= inverse0_sum1_1_a2_w;
            inverse0_sum1_1_a2_w_delay32_r <= inverse0_sum1_1_a2_w_delay31_r;
            inverse0_sum1_1_b2_w_delay31_r <= inverse0_sum1_1_b2_w;
            inverse0_sum1_1_b2_w_delay32_r <= inverse0_sum1_1_b2_w_delay31_r;
            inverse0_sum1_1_low1_w_delay33_r <= inverse0_sum1_1_low1_w;
            inverse0_sum1_1_low0_w_delay32_r <= inverse0_sum1_1_low0_w;
            inverse0_sum1_1_low0_w_delay33_r <= inverse0_sum1_1_low0_w_delay32_r;
            inverse0_sum2_0_a1_w_delay34_r <= inverse0_sum2_0_a1_w;
            inverse0_sum2_0_b1_w_delay34_r <= inverse0_sum2_0_b1_w;
            inverse0_sum2_0_a2_w_delay34_r <= inverse0_sum2_0_a2_w;
            inverse0_sum2_0_a2_w_delay35_r <= inverse0_sum2_0_a2_w_delay34_r;
            inverse0_sum2_0_b2_w_delay34_r <= inverse0_sum2_0_b2_w;
            inverse0_sum2_0_b2_w_delay35_r <= inverse0_sum2_0_b2_w_delay34_r;
            inverse0_sum2_0_low1_w_delay36_r <= inverse0_sum2_0_low1_w;
            inverse0_sum2_0_low0_w_delay35_r <= inverse0_sum2_0_low0_w;
            inverse0_sum2_0_low0_w_delay36_r <= inverse0_sum2_0_low0_w_delay35_r;
            inverse_abs0_a1_w_delay38_r <= inverse_abs0_a1_w;
            inverse_abs0_b1_w_delay38_r <= inverse_abs0_b1_w;
            inverse_abs0_a2_w_delay38_r <= inverse_abs0_a2_w;
            inverse_abs0_a2_w_delay39_r <= inverse_abs0_a2_w_delay38_r;
            inverse_abs0_b2_w_delay38_r <= inverse_abs0_b2_w;
            inverse_abs0_b2_w_delay39_r <= inverse_abs0_b2_w_delay38_r;
            inverse_abs0_low1_w_delay40_r <= inverse_abs0_low1_w;
            inverse_abs0_low0_w_delay39_r <= inverse_abs0_low0_w;
            inverse_abs0_low0_w_delay40_r <= inverse_abs0_low0_w_delay39_r;
            gradient_bias0_amt1_w_delay3_r <= gradient_bias0_amt1_w;
            gradient_bias0_amt2_w_delay3_r <= gradient_bias0_amt2_w;
            gradient_bias0_amt2_w_delay4_r <= gradient_bias0_amt2_w_delay3_r;
            gradient_bias0_amt3_w_delay3_r <= gradient_bias0_amt3_w;
            gradient_bias0_amt3_w_delay4_r <= gradient_bias0_amt3_w_delay3_r;
            gradient_bias0_amt3_w_delay5_r <= gradient_bias0_amt3_w_delay4_r;
            gradient_round0_a1_w_delay41_r <= gradient_round0_a1_w;
            gradient_round0_b1_w_delay41_r <= gradient_round0_b1_w;
            gradient_round0_a2_w_delay41_r <= gradient_round0_a2_w;
            gradient_round0_a2_w_delay42_r <= gradient_round0_a2_w_delay41_r;
            gradient_round0_b2_w_delay41_r <= gradient_round0_b2_w;
            gradient_round0_b2_w_delay42_r <= gradient_round0_b2_w_delay41_r;
            gradient_round0_low1_w_delay43_r <= gradient_round0_low1_w;
            gradient_round0_low0_w_delay42_r <= gradient_round0_low0_w;
            gradient_round0_low0_w_delay43_r <= gradient_round0_low0_w_delay42_r;
            gradient_shift0_amt0_w_delay3_r <= gradient_shift0_amt0_w;
            gradient_shift0_amt0_w_delay4_r <= gradient_shift0_amt0_w_delay3_r;
            gradient_shift0_amt0_w_delay5_r <= gradient_shift0_amt0_w_delay4_r;
            gradient_shift0_amt0_w_delay6_r <= gradient_shift0_amt0_w_delay5_r;
            gradient_shift0_amt0_w_delay7_r <= gradient_shift0_amt0_w_delay6_r;
            gradient_shift0_amt0_w_delay8_r <= gradient_shift0_amt0_w_delay7_r;
            gradient_shift0_amt0_w_delay9_r <= gradient_shift0_amt0_w_delay8_r;
            gradient_shift0_amt0_w_delay10_r <= gradient_shift0_amt0_w_delay9_r;
            gradient_shift0_amt0_w_delay11_r <= gradient_shift0_amt0_w_delay10_r;
            gradient_shift0_amt0_w_delay12_r <= gradient_shift0_amt0_w_delay11_r;
            gradient_shift0_amt0_w_delay13_r <= gradient_shift0_amt0_w_delay12_r;
            gradient_shift0_amt0_w_delay14_r <= gradient_shift0_amt0_w_delay13_r;
            gradient_shift0_amt0_w_delay15_r <= gradient_shift0_amt0_w_delay14_r;
            gradient_shift0_amt0_w_delay16_r <= gradient_shift0_amt0_w_delay15_r;
            gradient_shift0_amt0_w_delay17_r <= gradient_shift0_amt0_w_delay16_r;
            gradient_shift0_amt0_w_delay18_r <= gradient_shift0_amt0_w_delay17_r;
            gradient_shift0_amt0_w_delay19_r <= gradient_shift0_amt0_w_delay18_r;
            gradient_shift0_amt0_w_delay20_r <= gradient_shift0_amt0_w_delay19_r;
            gradient_shift0_amt0_w_delay21_r <= gradient_shift0_amt0_w_delay20_r;
            gradient_shift0_amt0_w_delay22_r <= gradient_shift0_amt0_w_delay21_r;
            gradient_shift0_amt0_w_delay23_r <= gradient_shift0_amt0_w_delay22_r;
            gradient_shift0_amt0_w_delay24_r <= gradient_shift0_amt0_w_delay23_r;
            gradient_shift0_amt0_w_delay25_r <= gradient_shift0_amt0_w_delay24_r;
            gradient_shift0_amt0_w_delay26_r <= gradient_shift0_amt0_w_delay25_r;
            gradient_shift0_amt0_w_delay27_r <= gradient_shift0_amt0_w_delay26_r;
            gradient_shift0_amt0_w_delay28_r <= gradient_shift0_amt0_w_delay27_r;
            gradient_shift0_amt0_w_delay29_r <= gradient_shift0_amt0_w_delay28_r;
            gradient_shift0_amt0_w_delay30_r <= gradient_shift0_amt0_w_delay29_r;
            gradient_shift0_amt0_w_delay31_r <= gradient_shift0_amt0_w_delay30_r;
            gradient_shift0_amt0_w_delay32_r <= gradient_shift0_amt0_w_delay31_r;
            gradient_shift0_amt0_w_delay33_r <= gradient_shift0_amt0_w_delay32_r;
            gradient_shift0_amt0_w_delay34_r <= gradient_shift0_amt0_w_delay33_r;
            gradient_shift0_amt0_w_delay35_r <= gradient_shift0_amt0_w_delay34_r;
            gradient_shift0_amt0_w_delay36_r <= gradient_shift0_amt0_w_delay35_r;
            gradient_shift0_amt0_w_delay37_r <= gradient_shift0_amt0_w_delay36_r;
            gradient_shift0_amt0_w_delay38_r <= gradient_shift0_amt0_w_delay37_r;
            gradient_shift0_amt0_w_delay39_r <= gradient_shift0_amt0_w_delay38_r;
            gradient_shift0_amt0_w_delay40_r <= gradient_shift0_amt0_w_delay39_r;
            gradient_shift0_amt0_w_delay41_r <= gradient_shift0_amt0_w_delay40_r;
            gradient_shift0_amt0_w_delay42_r <= gradient_shift0_amt0_w_delay41_r;
            gradient_shift0_amt0_w_delay43_r <= gradient_shift0_amt0_w_delay42_r;
            gradient_shift0_amt1_w_delay3_r <= gradient_shift0_amt1_w;
            gradient_shift0_amt1_w_delay4_r <= gradient_shift0_amt1_w_delay3_r;
            gradient_shift0_amt1_w_delay5_r <= gradient_shift0_amt1_w_delay4_r;
            gradient_shift0_amt1_w_delay6_r <= gradient_shift0_amt1_w_delay5_r;
            gradient_shift0_amt1_w_delay7_r <= gradient_shift0_amt1_w_delay6_r;
            gradient_shift0_amt1_w_delay8_r <= gradient_shift0_amt1_w_delay7_r;
            gradient_shift0_amt1_w_delay9_r <= gradient_shift0_amt1_w_delay8_r;
            gradient_shift0_amt1_w_delay10_r <= gradient_shift0_amt1_w_delay9_r;
            gradient_shift0_amt1_w_delay11_r <= gradient_shift0_amt1_w_delay10_r;
            gradient_shift0_amt1_w_delay12_r <= gradient_shift0_amt1_w_delay11_r;
            gradient_shift0_amt1_w_delay13_r <= gradient_shift0_amt1_w_delay12_r;
            gradient_shift0_amt1_w_delay14_r <= gradient_shift0_amt1_w_delay13_r;
            gradient_shift0_amt1_w_delay15_r <= gradient_shift0_amt1_w_delay14_r;
            gradient_shift0_amt1_w_delay16_r <= gradient_shift0_amt1_w_delay15_r;
            gradient_shift0_amt1_w_delay17_r <= gradient_shift0_amt1_w_delay16_r;
            gradient_shift0_amt1_w_delay18_r <= gradient_shift0_amt1_w_delay17_r;
            gradient_shift0_amt1_w_delay19_r <= gradient_shift0_amt1_w_delay18_r;
            gradient_shift0_amt1_w_delay20_r <= gradient_shift0_amt1_w_delay19_r;
            gradient_shift0_amt1_w_delay21_r <= gradient_shift0_amt1_w_delay20_r;
            gradient_shift0_amt1_w_delay22_r <= gradient_shift0_amt1_w_delay21_r;
            gradient_shift0_amt1_w_delay23_r <= gradient_shift0_amt1_w_delay22_r;
            gradient_shift0_amt1_w_delay24_r <= gradient_shift0_amt1_w_delay23_r;
            gradient_shift0_amt1_w_delay25_r <= gradient_shift0_amt1_w_delay24_r;
            gradient_shift0_amt1_w_delay26_r <= gradient_shift0_amt1_w_delay25_r;
            gradient_shift0_amt1_w_delay27_r <= gradient_shift0_amt1_w_delay26_r;
            gradient_shift0_amt1_w_delay28_r <= gradient_shift0_amt1_w_delay27_r;
            gradient_shift0_amt1_w_delay29_r <= gradient_shift0_amt1_w_delay28_r;
            gradient_shift0_amt1_w_delay30_r <= gradient_shift0_amt1_w_delay29_r;
            gradient_shift0_amt1_w_delay31_r <= gradient_shift0_amt1_w_delay30_r;
            gradient_shift0_amt1_w_delay32_r <= gradient_shift0_amt1_w_delay31_r;
            gradient_shift0_amt1_w_delay33_r <= gradient_shift0_amt1_w_delay32_r;
            gradient_shift0_amt1_w_delay34_r <= gradient_shift0_amt1_w_delay33_r;
            gradient_shift0_amt1_w_delay35_r <= gradient_shift0_amt1_w_delay34_r;
            gradient_shift0_amt1_w_delay36_r <= gradient_shift0_amt1_w_delay35_r;
            gradient_shift0_amt1_w_delay37_r <= gradient_shift0_amt1_w_delay36_r;
            gradient_shift0_amt1_w_delay38_r <= gradient_shift0_amt1_w_delay37_r;
            gradient_shift0_amt1_w_delay39_r <= gradient_shift0_amt1_w_delay38_r;
            gradient_shift0_amt1_w_delay40_r <= gradient_shift0_amt1_w_delay39_r;
            gradient_shift0_amt1_w_delay41_r <= gradient_shift0_amt1_w_delay40_r;
            gradient_shift0_amt1_w_delay42_r <= gradient_shift0_amt1_w_delay41_r;
            gradient_shift0_amt1_w_delay43_r <= gradient_shift0_amt1_w_delay42_r;
            gradient_shift0_amt1_w_delay44_r <= gradient_shift0_amt1_w_delay43_r;
            gradient_shift0_amt2_w_delay3_r <= gradient_shift0_amt2_w;
            gradient_shift0_amt2_w_delay4_r <= gradient_shift0_amt2_w_delay3_r;
            gradient_shift0_amt2_w_delay5_r <= gradient_shift0_amt2_w_delay4_r;
            gradient_shift0_amt2_w_delay6_r <= gradient_shift0_amt2_w_delay5_r;
            gradient_shift0_amt2_w_delay7_r <= gradient_shift0_amt2_w_delay6_r;
            gradient_shift0_amt2_w_delay8_r <= gradient_shift0_amt2_w_delay7_r;
            gradient_shift0_amt2_w_delay9_r <= gradient_shift0_amt2_w_delay8_r;
        end
    end
    always @(posedge clk_i) begin
        if (pipeline_enable_w[13]) begin
            gradient_shift0_amt2_w_delay10_r <= gradient_shift0_amt2_w_delay9_r;
            gradient_shift0_amt2_w_delay11_r <= gradient_shift0_amt2_w_delay10_r;
            gradient_shift0_amt2_w_delay12_r <= gradient_shift0_amt2_w_delay11_r;
            gradient_shift0_amt2_w_delay13_r <= gradient_shift0_amt2_w_delay12_r;
            gradient_shift0_amt2_w_delay14_r <= gradient_shift0_amt2_w_delay13_r;
            gradient_shift0_amt2_w_delay15_r <= gradient_shift0_amt2_w_delay14_r;
            gradient_shift0_amt2_w_delay16_r <= gradient_shift0_amt2_w_delay15_r;
            gradient_shift0_amt2_w_delay17_r <= gradient_shift0_amt2_w_delay16_r;
            gradient_shift0_amt2_w_delay18_r <= gradient_shift0_amt2_w_delay17_r;
            gradient_shift0_amt2_w_delay19_r <= gradient_shift0_amt2_w_delay18_r;
            gradient_shift0_amt2_w_delay20_r <= gradient_shift0_amt2_w_delay19_r;
            gradient_shift0_amt2_w_delay21_r <= gradient_shift0_amt2_w_delay20_r;
            gradient_shift0_amt2_w_delay22_r <= gradient_shift0_amt2_w_delay21_r;
            gradient_shift0_amt2_w_delay23_r <= gradient_shift0_amt2_w_delay22_r;
            gradient_shift0_amt2_w_delay24_r <= gradient_shift0_amt2_w_delay23_r;
            gradient_shift0_amt2_w_delay25_r <= gradient_shift0_amt2_w_delay24_r;
            gradient_shift0_amt2_w_delay26_r <= gradient_shift0_amt2_w_delay25_r;
            gradient_shift0_amt2_w_delay27_r <= gradient_shift0_amt2_w_delay26_r;
            gradient_shift0_amt2_w_delay28_r <= gradient_shift0_amt2_w_delay27_r;
            gradient_shift0_amt2_w_delay29_r <= gradient_shift0_amt2_w_delay28_r;
            gradient_shift0_amt2_w_delay30_r <= gradient_shift0_amt2_w_delay29_r;
            gradient_shift0_amt2_w_delay31_r <= gradient_shift0_amt2_w_delay30_r;
            gradient_shift0_amt2_w_delay32_r <= gradient_shift0_amt2_w_delay31_r;
            gradient_shift0_amt2_w_delay33_r <= gradient_shift0_amt2_w_delay32_r;
            gradient_shift0_amt2_w_delay34_r <= gradient_shift0_amt2_w_delay33_r;
            gradient_shift0_amt2_w_delay35_r <= gradient_shift0_amt2_w_delay34_r;
            gradient_shift0_amt2_w_delay36_r <= gradient_shift0_amt2_w_delay35_r;
            gradient_shift0_amt2_w_delay37_r <= gradient_shift0_amt2_w_delay36_r;
            gradient_shift0_amt2_w_delay38_r <= gradient_shift0_amt2_w_delay37_r;
            gradient_shift0_amt2_w_delay39_r <= gradient_shift0_amt2_w_delay38_r;
            gradient_shift0_amt2_w_delay40_r <= gradient_shift0_amt2_w_delay39_r;
            gradient_shift0_amt2_w_delay41_r <= gradient_shift0_amt2_w_delay40_r;
            gradient_shift0_amt2_w_delay42_r <= gradient_shift0_amt2_w_delay41_r;
            gradient_shift0_amt2_w_delay43_r <= gradient_shift0_amt2_w_delay42_r;
            gradient_shift0_amt2_w_delay44_r <= gradient_shift0_amt2_w_delay43_r;
            gradient_shift0_amt2_w_delay45_r <= gradient_shift0_amt2_w_delay44_r;
            gradient_shift0_amt3_w_delay3_r <= gradient_shift0_amt3_w;
            gradient_shift0_amt3_w_delay4_r <= gradient_shift0_amt3_w_delay3_r;
            gradient_shift0_amt3_w_delay5_r <= gradient_shift0_amt3_w_delay4_r;
            gradient_shift0_amt3_w_delay6_r <= gradient_shift0_amt3_w_delay5_r;
            gradient_shift0_amt3_w_delay7_r <= gradient_shift0_amt3_w_delay6_r;
            gradient_shift0_amt3_w_delay8_r <= gradient_shift0_amt3_w_delay7_r;
            gradient_shift0_amt3_w_delay9_r <= gradient_shift0_amt3_w_delay8_r;
            gradient_shift0_amt3_w_delay10_r <= gradient_shift0_amt3_w_delay9_r;
            gradient_shift0_amt3_w_delay11_r <= gradient_shift0_amt3_w_delay10_r;
            gradient_shift0_amt3_w_delay12_r <= gradient_shift0_amt3_w_delay11_r;
            gradient_shift0_amt3_w_delay13_r <= gradient_shift0_amt3_w_delay12_r;
            gradient_shift0_amt3_w_delay14_r <= gradient_shift0_amt3_w_delay13_r;
            gradient_shift0_amt3_w_delay15_r <= gradient_shift0_amt3_w_delay14_r;
            gradient_shift0_amt3_w_delay16_r <= gradient_shift0_amt3_w_delay15_r;
            gradient_shift0_amt3_w_delay17_r <= gradient_shift0_amt3_w_delay16_r;
            gradient_shift0_amt3_w_delay18_r <= gradient_shift0_amt3_w_delay17_r;
            gradient_shift0_amt3_w_delay19_r <= gradient_shift0_amt3_w_delay18_r;
            gradient_shift0_amt3_w_delay20_r <= gradient_shift0_amt3_w_delay19_r;
            gradient_shift0_amt3_w_delay21_r <= gradient_shift0_amt3_w_delay20_r;
            gradient_shift0_amt3_w_delay22_r <= gradient_shift0_amt3_w_delay21_r;
            gradient_shift0_amt3_w_delay23_r <= gradient_shift0_amt3_w_delay22_r;
            gradient_shift0_amt3_w_delay24_r <= gradient_shift0_amt3_w_delay23_r;
            gradient_shift0_amt3_w_delay25_r <= gradient_shift0_amt3_w_delay24_r;
            gradient_shift0_amt3_w_delay26_r <= gradient_shift0_amt3_w_delay25_r;
            gradient_shift0_amt3_w_delay27_r <= gradient_shift0_amt3_w_delay26_r;
            gradient_shift0_amt3_w_delay28_r <= gradient_shift0_amt3_w_delay27_r;
            gradient_shift0_amt3_w_delay29_r <= gradient_shift0_amt3_w_delay28_r;
            gradient_shift0_amt3_w_delay30_r <= gradient_shift0_amt3_w_delay29_r;
            gradient_shift0_amt3_w_delay31_r <= gradient_shift0_amt3_w_delay30_r;
            gradient_shift0_amt3_w_delay32_r <= gradient_shift0_amt3_w_delay31_r;
            gradient_shift0_amt3_w_delay33_r <= gradient_shift0_amt3_w_delay32_r;
            gradient_shift0_amt3_w_delay34_r <= gradient_shift0_amt3_w_delay33_r;
            gradient_shift0_amt3_w_delay35_r <= gradient_shift0_amt3_w_delay34_r;
            gradient_shift0_amt3_w_delay36_r <= gradient_shift0_amt3_w_delay35_r;
            gradient_shift0_amt3_w_delay37_r <= gradient_shift0_amt3_w_delay36_r;
            gradient_shift0_amt3_w_delay38_r <= gradient_shift0_amt3_w_delay37_r;
            gradient_shift0_amt3_w_delay39_r <= gradient_shift0_amt3_w_delay38_r;
            gradient_shift0_amt3_w_delay40_r <= gradient_shift0_amt3_w_delay39_r;
            gradient_shift0_amt3_w_delay41_r <= gradient_shift0_amt3_w_delay40_r;
            gradient_shift0_amt3_w_delay42_r <= gradient_shift0_amt3_w_delay41_r;
            gradient_shift0_amt3_w_delay43_r <= gradient_shift0_amt3_w_delay42_r;
            gradient_shift0_amt3_w_delay44_r <= gradient_shift0_amt3_w_delay43_r;
            gradient_shift0_amt3_w_delay45_r <= gradient_shift0_amt3_w_delay44_r;
            gradient_shift0_amt3_w_delay46_r <= gradient_shift0_amt3_w_delay45_r;
            inverse_abs0_sign_delay38_r <= inverse_abs0_sign_r;
            inverse_abs0_sign_delay39_r <= inverse_abs0_sign_delay38_r;
            inverse_abs0_sign_delay40_r <= inverse_abs0_sign_delay39_r;
            inverse_abs0_sign_delay41_r <= inverse_abs0_sign_delay40_r;
            inverse_abs0_sign_delay42_r <= inverse_abs0_sign_delay41_r;
            inverse_abs0_sign_delay43_r <= inverse_abs0_sign_delay42_r;
            inverse_abs0_sign_delay44_r <= inverse_abs0_sign_delay43_r;
            inverse_abs0_sign_delay45_r <= inverse_abs0_sign_delay44_r;
            inverse_abs0_sign_delay46_r <= inverse_abs0_sign_delay45_r;
            inverse_abs0_sign_delay47_r <= inverse_abs0_sign_delay46_r;
            inverse_abs0_sign_delay48_r <= inverse_abs0_sign_d47_r;
            gradient_signed0_a1_w_delay49_r <= gradient_signed0_a1_w;
            gradient_signed0_b1_w_delay49_r <= gradient_signed0_b1_w;
            gradient_signed0_low0_w_delay50_r <= gradient_signed0_low0_w;
            origin_product0_sum0_0_a1_w_delay52_r <= origin_product0_sum0_0_a1_w;
            origin_product0_sum0_0_b1_w_delay52_r <= origin_product0_sum0_0_b1_w;
            origin_product0_sum0_0_a2_w_delay52_r <= origin_product0_sum0_0_a2_w;
            origin_product0_sum0_0_a2_w_delay53_r <= origin_product0_sum0_0_a2_w_delay52_r;
            origin_product0_sum0_0_b2_w_delay52_r <= origin_product0_sum0_0_b2_w;
            origin_product0_sum0_0_b2_w_delay53_r <= origin_product0_sum0_0_b2_w_delay52_r;
            origin_product0_sum0_0_low1_w_delay54_r <= origin_product0_sum0_0_low1_w;
            origin_product0_sum0_0_low0_w_delay53_r <= origin_product0_sum0_0_low0_w;
            origin_product0_sum0_0_low0_w_delay54_r <= origin_product0_sum0_0_low0_w_delay53_r;
            origin_product0_sum0_1_a1_w_delay52_r <= origin_product0_sum0_1_a1_w;
            origin_product0_sum0_1_b1_w_delay52_r <= origin_product0_sum0_1_b1_w;
            origin_product0_sum0_1_a2_w_delay52_r <= origin_product0_sum0_1_a2_w;
            origin_product0_sum0_1_a2_w_delay53_r <= origin_product0_sum0_1_a2_w_delay52_r;
            origin_product0_sum0_1_b2_w_delay52_r <= origin_product0_sum0_1_b2_w;
            origin_product0_sum0_1_b2_w_delay53_r <= origin_product0_sum0_1_b2_w_delay52_r;
            origin_product0_sum0_1_low1_w_delay54_r <= origin_product0_sum0_1_low1_w;
            origin_product0_sum0_1_low0_w_delay53_r <= origin_product0_sum0_1_low0_w;
            origin_product0_sum0_1_low0_w_delay54_r <= origin_product0_sum0_1_low0_w_delay53_r;
            origin_product0_sum1_0_a1_w_delay55_r <= origin_product0_sum1_0_a1_w;
            origin_product0_sum1_0_b1_w_delay55_r <= origin_product0_sum1_0_b1_w;
            origin_product0_sum1_0_a2_w_delay55_r <= origin_product0_sum1_0_a2_w;
            origin_product0_sum1_0_a2_w_delay56_r <= origin_product0_sum1_0_a2_w_delay55_r;
            origin_product0_sum1_0_b2_w_delay55_r <= origin_product0_sum1_0_b2_w;
            origin_product0_sum1_0_b2_w_delay56_r <= origin_product0_sum1_0_b2_w_delay55_r;
            origin_product0_sum1_0_low1_w_delay57_r <= origin_product0_sum1_0_low1_w;
            origin_product0_sum1_0_low0_w_delay56_r <= origin_product0_sum1_0_low0_w;
            origin_product0_sum1_0_low0_w_delay57_r <= origin_product0_sum1_0_low0_w_delay56_r;
            gradient_abs0_a1_w_delay52_r <= gradient_abs0_a1_w;
            gradient_abs0_b1_w_delay52_r <= gradient_abs0_b1_w;
            gradient_abs0_low0_w_delay53_r <= gradient_abs0_low0_w;
            gradient_drop0_amt0_w_delay2_r <= gradient_drop0_amt0_w;
            gradient_drop0_amt0_w_delay3_r <= gradient_drop0_amt0_w_delay2_r;
            gradient_drop0_amt0_w_delay4_r <= gradient_drop0_amt0_w_delay3_r;
            gradient_drop0_amt0_w_delay5_r <= gradient_drop0_amt0_w_delay4_r;
            gradient_drop0_amt0_w_delay6_r <= gradient_drop0_amt0_w_delay5_r;
            gradient_drop0_amt0_w_delay7_r <= gradient_drop0_amt0_w_delay6_r;
            gradient_drop0_amt0_w_delay8_r <= gradient_drop0_amt0_w_delay7_r;
            gradient_drop0_amt0_w_delay9_r <= gradient_drop0_amt0_w_delay8_r;
            gradient_drop0_amt0_w_delay10_r <= gradient_drop0_amt0_w_delay9_r;
            gradient_drop0_amt0_w_delay11_r <= gradient_drop0_amt0_w_delay10_r;
            gradient_drop0_amt0_w_delay12_r <= gradient_drop0_amt0_w_delay11_r;
            gradient_drop0_amt0_w_delay13_r <= gradient_drop0_amt0_w_delay12_r;
            gradient_drop0_amt0_w_delay14_r <= gradient_drop0_amt0_w_delay13_r;
            gradient_drop0_amt0_w_delay15_r <= gradient_drop0_amt0_w_delay14_r;
            gradient_drop0_amt0_w_delay16_r <= gradient_drop0_amt0_w_delay15_r;
            gradient_drop0_amt0_w_delay17_r <= gradient_drop0_amt0_w_delay16_r;
            gradient_drop0_amt0_w_delay18_r <= gradient_drop0_amt0_w_delay17_r;
            gradient_drop0_amt0_w_delay19_r <= gradient_drop0_amt0_w_delay18_r;
            gradient_drop0_amt0_w_delay20_r <= gradient_drop0_amt0_w_delay19_r;
            gradient_drop0_amt0_w_delay21_r <= gradient_drop0_amt0_w_delay20_r;
            gradient_drop0_amt0_w_delay22_r <= gradient_drop0_amt0_w_delay21_r;
            gradient_drop0_amt0_w_delay23_r <= gradient_drop0_amt0_w_delay22_r;
            gradient_drop0_amt0_w_delay24_r <= gradient_drop0_amt0_w_delay23_r;
            gradient_drop0_amt0_w_delay25_r <= gradient_drop0_amt0_w_delay24_r;
            gradient_drop0_amt0_w_delay26_r <= gradient_drop0_amt0_w_delay25_r;
            gradient_drop0_amt0_w_delay27_r <= gradient_drop0_amt0_w_delay26_r;
            gradient_drop0_amt0_w_delay28_r <= gradient_drop0_amt0_w_delay27_r;
            gradient_drop0_amt0_w_delay29_r <= gradient_drop0_amt0_w_delay28_r;
            gradient_drop0_amt0_w_delay30_r <= gradient_drop0_amt0_w_delay29_r;
            gradient_drop0_amt0_w_delay31_r <= gradient_drop0_amt0_w_delay30_r;
            gradient_drop0_amt0_w_delay32_r <= gradient_drop0_amt0_w_delay31_r;
            gradient_drop0_amt0_w_delay33_r <= gradient_drop0_amt0_w_delay32_r;
            gradient_drop0_amt0_w_delay34_r <= gradient_drop0_amt0_w_delay33_r;
            gradient_drop0_amt0_w_delay35_r <= gradient_drop0_amt0_w_delay34_r;
            gradient_drop0_amt0_w_delay36_r <= gradient_drop0_amt0_w_delay35_r;
            gradient_drop0_amt0_w_delay37_r <= gradient_drop0_amt0_w_delay36_r;
            gradient_drop0_amt0_w_delay38_r <= gradient_drop0_amt0_w_delay37_r;
            gradient_drop0_amt0_w_delay39_r <= gradient_drop0_amt0_w_delay38_r;
            gradient_drop0_amt0_w_delay40_r <= gradient_drop0_amt0_w_delay39_r;
            gradient_drop0_amt0_w_delay41_r <= gradient_drop0_amt0_w_delay40_r;
            gradient_drop0_amt0_w_delay42_r <= gradient_drop0_amt0_w_delay41_r;
            gradient_drop0_amt0_w_delay43_r <= gradient_drop0_amt0_w_delay42_r;
            gradient_drop0_amt0_w_delay44_r <= gradient_drop0_amt0_w_delay43_r;
            gradient_drop0_amt0_w_delay45_r <= gradient_drop0_amt0_w_delay44_r;
            gradient_drop0_amt0_w_delay46_r <= gradient_drop0_amt0_w_delay45_r;
            gradient_drop0_amt0_w_delay47_r <= gradient_drop0_amt0_w_delay46_r;
            gradient_drop0_amt0_w_delay48_r <= gradient_drop0_amt0_w_delay47_r;
            gradient_drop0_amt0_w_delay49_r <= gradient_drop0_amt0_w_delay48_r;
            gradient_drop0_amt0_w_delay50_r <= gradient_drop0_amt0_w_delay49_r;
            gradient_drop0_amt0_w_delay51_r <= gradient_drop0_amt0_w_delay50_r;
            gradient_drop0_amt0_w_delay52_r <= gradient_drop0_amt0_w_delay51_r;
            gradient_drop0_amt0_w_delay53_r <= gradient_drop0_amt0_w_delay52_r;
            gradient_drop0_amt1_w_delay2_r <= gradient_drop0_amt1_w;
            gradient_drop0_amt1_w_delay3_r <= gradient_drop0_amt1_w_delay2_r;
            gradient_drop0_amt1_w_delay4_r <= gradient_drop0_amt1_w_delay3_r;
            gradient_drop0_amt1_w_delay5_r <= gradient_drop0_amt1_w_delay4_r;
            gradient_drop0_amt1_w_delay6_r <= gradient_drop0_amt1_w_delay5_r;
            gradient_drop0_amt1_w_delay7_r <= gradient_drop0_amt1_w_delay6_r;
            gradient_drop0_amt1_w_delay8_r <= gradient_drop0_amt1_w_delay7_r;
            gradient_drop0_amt1_w_delay9_r <= gradient_drop0_amt1_w_delay8_r;
            gradient_drop0_amt1_w_delay10_r <= gradient_drop0_amt1_w_delay9_r;
            gradient_drop0_amt1_w_delay11_r <= gradient_drop0_amt1_w_delay10_r;
            gradient_drop0_amt1_w_delay12_r <= gradient_drop0_amt1_w_delay11_r;
            gradient_drop0_amt1_w_delay13_r <= gradient_drop0_amt1_w_delay12_r;
            gradient_drop0_amt1_w_delay14_r <= gradient_drop0_amt1_w_delay13_r;
            gradient_drop0_amt1_w_delay15_r <= gradient_drop0_amt1_w_delay14_r;
            gradient_drop0_amt1_w_delay16_r <= gradient_drop0_amt1_w_delay15_r;
            gradient_drop0_amt1_w_delay17_r <= gradient_drop0_amt1_w_delay16_r;
            gradient_drop0_amt1_w_delay18_r <= gradient_drop0_amt1_w_delay17_r;
            gradient_drop0_amt1_w_delay19_r <= gradient_drop0_amt1_w_delay18_r;
            gradient_drop0_amt1_w_delay20_r <= gradient_drop0_amt1_w_delay19_r;
            gradient_drop0_amt1_w_delay21_r <= gradient_drop0_amt1_w_delay20_r;
            gradient_drop0_amt1_w_delay22_r <= gradient_drop0_amt1_w_delay21_r;
            gradient_drop0_amt1_w_delay23_r <= gradient_drop0_amt1_w_delay22_r;
            gradient_drop0_amt1_w_delay24_r <= gradient_drop0_amt1_w_delay23_r;
            gradient_drop0_amt1_w_delay25_r <= gradient_drop0_amt1_w_delay24_r;
            gradient_drop0_amt1_w_delay26_r <= gradient_drop0_amt1_w_delay25_r;
            gradient_drop0_amt1_w_delay27_r <= gradient_drop0_amt1_w_delay26_r;
            gradient_drop0_amt1_w_delay28_r <= gradient_drop0_amt1_w_delay27_r;
            gradient_drop0_amt1_w_delay29_r <= gradient_drop0_amt1_w_delay28_r;
            gradient_drop0_amt1_w_delay30_r <= gradient_drop0_amt1_w_delay29_r;
            gradient_drop0_amt1_w_delay31_r <= gradient_drop0_amt1_w_delay30_r;
            gradient_drop0_amt1_w_delay32_r <= gradient_drop0_amt1_w_delay31_r;
            gradient_drop0_amt1_w_delay33_r <= gradient_drop0_amt1_w_delay32_r;
            gradient_drop0_amt1_w_delay34_r <= gradient_drop0_amt1_w_delay33_r;
            gradient_drop0_amt1_w_delay35_r <= gradient_drop0_amt1_w_delay34_r;
            gradient_drop0_amt1_w_delay36_r <= gradient_drop0_amt1_w_delay35_r;
            gradient_drop0_amt1_w_delay37_r <= gradient_drop0_amt1_w_delay36_r;
            gradient_drop0_amt1_w_delay38_r <= gradient_drop0_amt1_w_delay37_r;
            gradient_drop0_amt1_w_delay39_r <= gradient_drop0_amt1_w_delay38_r;
            gradient_drop0_amt1_w_delay40_r <= gradient_drop0_amt1_w_delay39_r;
            gradient_drop0_amt1_w_delay41_r <= gradient_drop0_amt1_w_delay40_r;
            gradient_drop0_amt1_w_delay42_r <= gradient_drop0_amt1_w_delay41_r;
            gradient_drop0_amt1_w_delay43_r <= gradient_drop0_amt1_w_delay42_r;
            gradient_drop0_amt1_w_delay44_r <= gradient_drop0_amt1_w_delay43_r;
            gradient_drop0_amt1_w_delay45_r <= gradient_drop0_amt1_w_delay44_r;
            gradient_drop0_amt1_w_delay46_r <= gradient_drop0_amt1_w_delay45_r;
            gradient_drop0_amt1_w_delay47_r <= gradient_drop0_amt1_w_delay46_r;
            gradient_drop0_amt1_w_delay48_r <= gradient_drop0_amt1_w_delay47_r;
            gradient_drop0_amt1_w_delay49_r <= gradient_drop0_amt1_w_delay48_r;
            gradient_drop0_amt1_w_delay50_r <= gradient_drop0_amt1_w_delay49_r;
            gradient_drop0_amt1_w_delay51_r <= gradient_drop0_amt1_w_delay50_r;
            gradient_drop0_amt1_w_delay52_r <= gradient_drop0_amt1_w_delay51_r;
            gradient_drop0_amt1_w_delay53_r <= gradient_drop0_amt1_w_delay52_r;
            gradient_drop0_amt1_w_delay54_r <= gradient_drop0_amt1_w_delay53_r;
            stored_round0_a1_w_delay56_r <= stored_round0_a1_w;
            stored_round0_b1_w_delay56_r <= stored_round0_b1_w;
            stored_round0_low0_w_delay57_r <= stored_round0_low0_w;
            gradient_abs0_sign_delay52_r <= gradient_abs0_sign_r;
            gradient_abs0_sign_delay53_r <= gradient_abs0_sign_delay52_r;
            gradient_abs0_sign_delay54_r <= gradient_abs0_sign_delay53_r;
            gradient_abs0_sign_delay55_r <= gradient_abs0_sign_delay54_r;
            gradient_abs0_sign_delay56_r <= gradient_abs0_sign_delay55_r;
            gradient_abs0_sign_delay57_r <= gradient_abs0_sign_delay56_r;
            gradient_abs0_sign_delay58_r <= gradient_abs0_sign_d57_r;
            stored_signed0_a1_w_delay59_r <= stored_signed0_a1_w;
            stored_signed0_b1_w_delay59_r <= stored_signed0_b1_w;
        end
    end
    always @(posedge clk_i) begin
        if (pipeline_enable_w[14]) begin
            stored_signed0_low0_w_delay60_r <= stored_signed0_low0_w;
            product1_0_sum0_0_a1_w_delay22_r <= product1_0_sum0_0_a1_w;
            product1_0_sum0_0_b1_w_delay22_r <= product1_0_sum0_0_b1_w;
            product1_0_sum0_0_low0_w_delay23_r <= product1_0_sum0_0_low0_w;
            product1_1_sum0_0_a1_w_delay22_r <= product1_1_sum0_0_a1_w;
            product1_1_sum0_0_b1_w_delay22_r <= product1_1_sum0_0_b1_w;
            product1_1_sum0_0_low0_w_delay23_r <= product1_1_sum0_0_low0_w;
            numerator1_a1_w_delay24_r <= numerator1_a1_w;
            numerator1_b1_w_delay24_r <= numerator1_b1_w;
            numerator1_low0_w_delay25_r <= numerator1_low0_w;
            inverse1_sum0_0_a1_w_delay28_r <= inverse1_sum0_0_a1_w;
            inverse1_sum0_0_b1_w_delay28_r <= inverse1_sum0_0_b1_w;
            inverse1_sum0_0_a2_w_delay28_r <= inverse1_sum0_0_a2_w;
            inverse1_sum0_0_a2_w_delay29_r <= inverse1_sum0_0_a2_w_delay28_r;
            inverse1_sum0_0_b2_w_delay28_r <= inverse1_sum0_0_b2_w;
            inverse1_sum0_0_b2_w_delay29_r <= inverse1_sum0_0_b2_w_delay28_r;
            inverse1_sum0_0_low1_w_delay30_r <= inverse1_sum0_0_low1_w;
            inverse1_sum0_0_low0_w_delay29_r <= inverse1_sum0_0_low0_w;
            inverse1_sum0_0_low0_w_delay30_r <= inverse1_sum0_0_low0_w_delay29_r;
            inverse1_sum0_1_a1_w_delay28_r <= inverse1_sum0_1_a1_w;
            inverse1_sum0_1_b1_w_delay28_r <= inverse1_sum0_1_b1_w;
            inverse1_sum0_1_a2_w_delay28_r <= inverse1_sum0_1_a2_w;
            inverse1_sum0_1_a2_w_delay29_r <= inverse1_sum0_1_a2_w_delay28_r;
            inverse1_sum0_1_b2_w_delay28_r <= inverse1_sum0_1_b2_w;
            inverse1_sum0_1_b2_w_delay29_r <= inverse1_sum0_1_b2_w_delay28_r;
            inverse1_sum0_1_low1_w_delay30_r <= inverse1_sum0_1_low1_w;
            inverse1_sum0_1_low0_w_delay29_r <= inverse1_sum0_1_low0_w;
            inverse1_sum0_1_low0_w_delay30_r <= inverse1_sum0_1_low0_w_delay29_r;
            inverse1_sum0_2_a1_w_delay28_r <= inverse1_sum0_2_a1_w;
            inverse1_sum0_2_b1_w_delay28_r <= inverse1_sum0_2_b1_w;
            inverse1_sum0_2_a2_w_delay28_r <= inverse1_sum0_2_a2_w;
            inverse1_sum0_2_a2_w_delay29_r <= inverse1_sum0_2_a2_w_delay28_r;
            inverse1_sum0_2_b2_w_delay28_r <= inverse1_sum0_2_b2_w;
            inverse1_sum0_2_b2_w_delay29_r <= inverse1_sum0_2_b2_w_delay28_r;
            inverse1_sum0_2_low1_w_delay30_r <= inverse1_sum0_2_low1_w;
            inverse1_sum0_2_low0_w_delay29_r <= inverse1_sum0_2_low0_w;
            inverse1_sum0_2_low0_w_delay30_r <= inverse1_sum0_2_low0_w_delay29_r;
            inverse1_sum0_3_a1_w_delay28_r <= inverse1_sum0_3_a1_w;
            inverse1_sum0_3_b1_w_delay28_r <= inverse1_sum0_3_b1_w;
            inverse1_sum0_3_a2_w_delay28_r <= inverse1_sum0_3_a2_w;
            inverse1_sum0_3_a2_w_delay29_r <= inverse1_sum0_3_a2_w_delay28_r;
            inverse1_sum0_3_b2_w_delay28_r <= inverse1_sum0_3_b2_w;
            inverse1_sum0_3_b2_w_delay29_r <= inverse1_sum0_3_b2_w_delay28_r;
            inverse1_sum0_3_low1_w_delay30_r <= inverse1_sum0_3_low1_w;
            inverse1_sum0_3_low0_w_delay29_r <= inverse1_sum0_3_low0_w;
        end
    end
    always @(posedge clk_i) begin
        if (pipeline_enable_w[15]) begin
            inverse1_sum0_3_low0_w_delay30_r <= inverse1_sum0_3_low0_w_delay29_r;
            inverse1_sum1_0_a1_w_delay31_r <= inverse1_sum1_0_a1_w;
            inverse1_sum1_0_b1_w_delay31_r <= inverse1_sum1_0_b1_w;
            inverse1_sum1_0_a2_w_delay31_r <= inverse1_sum1_0_a2_w;
            inverse1_sum1_0_a2_w_delay32_r <= inverse1_sum1_0_a2_w_delay31_r;
            inverse1_sum1_0_b2_w_delay31_r <= inverse1_sum1_0_b2_w;
            inverse1_sum1_0_b2_w_delay32_r <= inverse1_sum1_0_b2_w_delay31_r;
            inverse1_sum1_0_low1_w_delay33_r <= inverse1_sum1_0_low1_w;
            inverse1_sum1_0_low0_w_delay32_r <= inverse1_sum1_0_low0_w;
            inverse1_sum1_0_low0_w_delay33_r <= inverse1_sum1_0_low0_w_delay32_r;
            inverse1_sum1_1_a1_w_delay31_r <= inverse1_sum1_1_a1_w;
            inverse1_sum1_1_b1_w_delay31_r <= inverse1_sum1_1_b1_w;
            inverse1_sum1_1_a2_w_delay31_r <= inverse1_sum1_1_a2_w;
            inverse1_sum1_1_a2_w_delay32_r <= inverse1_sum1_1_a2_w_delay31_r;
            inverse1_sum1_1_b2_w_delay31_r <= inverse1_sum1_1_b2_w;
            inverse1_sum1_1_b2_w_delay32_r <= inverse1_sum1_1_b2_w_delay31_r;
            inverse1_sum1_1_low1_w_delay33_r <= inverse1_sum1_1_low1_w;
            inverse1_sum1_1_low0_w_delay32_r <= inverse1_sum1_1_low0_w;
            inverse1_sum1_1_low0_w_delay33_r <= inverse1_sum1_1_low0_w_delay32_r;
            inverse1_sum2_0_a1_w_delay34_r <= inverse1_sum2_0_a1_w;
            inverse1_sum2_0_b1_w_delay34_r <= inverse1_sum2_0_b1_w;
            inverse1_sum2_0_a2_w_delay34_r <= inverse1_sum2_0_a2_w;
            inverse1_sum2_0_a2_w_delay35_r <= inverse1_sum2_0_a2_w_delay34_r;
            inverse1_sum2_0_b2_w_delay34_r <= inverse1_sum2_0_b2_w;
            inverse1_sum2_0_b2_w_delay35_r <= inverse1_sum2_0_b2_w_delay34_r;
            inverse1_sum2_0_low1_w_delay36_r <= inverse1_sum2_0_low1_w;
            inverse1_sum2_0_low0_w_delay35_r <= inverse1_sum2_0_low0_w;
            inverse1_sum2_0_low0_w_delay36_r <= inverse1_sum2_0_low0_w_delay35_r;
            inverse_abs1_a1_w_delay38_r <= inverse_abs1_a1_w;
            inverse_abs1_b1_w_delay38_r <= inverse_abs1_b1_w;
            inverse_abs1_a2_w_delay38_r <= inverse_abs1_a2_w;
            inverse_abs1_a2_w_delay39_r <= inverse_abs1_a2_w_delay38_r;
            inverse_abs1_b2_w_delay38_r <= inverse_abs1_b2_w;
            inverse_abs1_b2_w_delay39_r <= inverse_abs1_b2_w_delay38_r;
            inverse_abs1_low1_w_delay40_r <= inverse_abs1_low1_w;
            inverse_abs1_low0_w_delay39_r <= inverse_abs1_low0_w;
            inverse_abs1_low0_w_delay40_r <= inverse_abs1_low0_w_delay39_r;
            gradient_bias1_amt1_w_delay3_r <= gradient_bias1_amt1_w;
            gradient_bias1_amt2_w_delay3_r <= gradient_bias1_amt2_w;
            gradient_bias1_amt2_w_delay4_r <= gradient_bias1_amt2_w_delay3_r;
            gradient_bias1_amt3_w_delay3_r <= gradient_bias1_amt3_w;
            gradient_bias1_amt3_w_delay4_r <= gradient_bias1_amt3_w_delay3_r;
            gradient_bias1_amt3_w_delay5_r <= gradient_bias1_amt3_w_delay4_r;
            gradient_round1_a1_w_delay41_r <= gradient_round1_a1_w;
            gradient_round1_b1_w_delay41_r <= gradient_round1_b1_w;
            gradient_round1_a2_w_delay41_r <= gradient_round1_a2_w;
            gradient_round1_a2_w_delay42_r <= gradient_round1_a2_w_delay41_r;
            gradient_round1_b2_w_delay41_r <= gradient_round1_b2_w;
            gradient_round1_b2_w_delay42_r <= gradient_round1_b2_w_delay41_r;
            gradient_round1_low1_w_delay43_r <= gradient_round1_low1_w;
        end
    end
    always @(posedge clk_i) begin
        if (pipeline_enable_w[16]) begin
            gradient_round1_low0_w_delay42_r <= gradient_round1_low0_w;
            gradient_round1_low0_w_delay43_r <= gradient_round1_low0_w_delay42_r;
            gradient_shift1_amt0_w_delay3_r <= gradient_shift1_amt0_w;
            gradient_shift1_amt0_w_delay4_r <= gradient_shift1_amt0_w_delay3_r;
            gradient_shift1_amt0_w_delay5_r <= gradient_shift1_amt0_w_delay4_r;
            gradient_shift1_amt0_w_delay6_r <= gradient_shift1_amt0_w_delay5_r;
            gradient_shift1_amt0_w_delay7_r <= gradient_shift1_amt0_w_delay6_r;
            gradient_shift1_amt0_w_delay8_r <= gradient_shift1_amt0_w_delay7_r;
            gradient_shift1_amt0_w_delay9_r <= gradient_shift1_amt0_w_delay8_r;
            gradient_shift1_amt0_w_delay10_r <= gradient_shift1_amt0_w_delay9_r;
            gradient_shift1_amt0_w_delay11_r <= gradient_shift1_amt0_w_delay10_r;
            gradient_shift1_amt0_w_delay12_r <= gradient_shift1_amt0_w_delay11_r;
            gradient_shift1_amt0_w_delay13_r <= gradient_shift1_amt0_w_delay12_r;
            gradient_shift1_amt0_w_delay14_r <= gradient_shift1_amt0_w_delay13_r;
            gradient_shift1_amt0_w_delay15_r <= gradient_shift1_amt0_w_delay14_r;
            gradient_shift1_amt0_w_delay16_r <= gradient_shift1_amt0_w_delay15_r;
            gradient_shift1_amt0_w_delay17_r <= gradient_shift1_amt0_w_delay16_r;
            gradient_shift1_amt0_w_delay18_r <= gradient_shift1_amt0_w_delay17_r;
            gradient_shift1_amt0_w_delay19_r <= gradient_shift1_amt0_w_delay18_r;
            gradient_shift1_amt0_w_delay20_r <= gradient_shift1_amt0_w_delay19_r;
            gradient_shift1_amt0_w_delay21_r <= gradient_shift1_amt0_w_delay20_r;
            gradient_shift1_amt0_w_delay22_r <= gradient_shift1_amt0_w_delay21_r;
            gradient_shift1_amt0_w_delay23_r <= gradient_shift1_amt0_w_delay22_r;
            gradient_shift1_amt0_w_delay24_r <= gradient_shift1_amt0_w_delay23_r;
            gradient_shift1_amt0_w_delay25_r <= gradient_shift1_amt0_w_delay24_r;
            gradient_shift1_amt0_w_delay26_r <= gradient_shift1_amt0_w_delay25_r;
            gradient_shift1_amt0_w_delay27_r <= gradient_shift1_amt0_w_delay26_r;
            gradient_shift1_amt0_w_delay28_r <= gradient_shift1_amt0_w_delay27_r;
            gradient_shift1_amt0_w_delay29_r <= gradient_shift1_amt0_w_delay28_r;
            gradient_shift1_amt0_w_delay30_r <= gradient_shift1_amt0_w_delay29_r;
            gradient_shift1_amt0_w_delay31_r <= gradient_shift1_amt0_w_delay30_r;
            gradient_shift1_amt0_w_delay32_r <= gradient_shift1_amt0_w_delay31_r;
            gradient_shift1_amt0_w_delay33_r <= gradient_shift1_amt0_w_delay32_r;
            gradient_shift1_amt0_w_delay34_r <= gradient_shift1_amt0_w_delay33_r;
            gradient_shift1_amt0_w_delay35_r <= gradient_shift1_amt0_w_delay34_r;
            gradient_shift1_amt0_w_delay36_r <= gradient_shift1_amt0_w_delay35_r;
            gradient_shift1_amt0_w_delay37_r <= gradient_shift1_amt0_w_delay36_r;
            gradient_shift1_amt0_w_delay38_r <= gradient_shift1_amt0_w_delay37_r;
            gradient_shift1_amt0_w_delay39_r <= gradient_shift1_amt0_w_delay38_r;
            gradient_shift1_amt0_w_delay40_r <= gradient_shift1_amt0_w_delay39_r;
            gradient_shift1_amt0_w_delay41_r <= gradient_shift1_amt0_w_delay40_r;
            gradient_shift1_amt0_w_delay42_r <= gradient_shift1_amt0_w_delay41_r;
            gradient_shift1_amt0_w_delay43_r <= gradient_shift1_amt0_w_delay42_r;
            gradient_shift1_amt1_w_delay3_r <= gradient_shift1_amt1_w;
            gradient_shift1_amt1_w_delay4_r <= gradient_shift1_amt1_w_delay3_r;
            gradient_shift1_amt1_w_delay5_r <= gradient_shift1_amt1_w_delay4_r;
            gradient_shift1_amt1_w_delay6_r <= gradient_shift1_amt1_w_delay5_r;
            gradient_shift1_amt1_w_delay7_r <= gradient_shift1_amt1_w_delay6_r;
            gradient_shift1_amt1_w_delay8_r <= gradient_shift1_amt1_w_delay7_r;
            gradient_shift1_amt1_w_delay9_r <= gradient_shift1_amt1_w_delay8_r;
            gradient_shift1_amt1_w_delay10_r <= gradient_shift1_amt1_w_delay9_r;
            gradient_shift1_amt1_w_delay11_r <= gradient_shift1_amt1_w_delay10_r;
            gradient_shift1_amt1_w_delay12_r <= gradient_shift1_amt1_w_delay11_r;
            gradient_shift1_amt1_w_delay13_r <= gradient_shift1_amt1_w_delay12_r;
            gradient_shift1_amt1_w_delay14_r <= gradient_shift1_amt1_w_delay13_r;
            gradient_shift1_amt1_w_delay15_r <= gradient_shift1_amt1_w_delay14_r;
            gradient_shift1_amt1_w_delay16_r <= gradient_shift1_amt1_w_delay15_r;
            gradient_shift1_amt1_w_delay17_r <= gradient_shift1_amt1_w_delay16_r;
            gradient_shift1_amt1_w_delay18_r <= gradient_shift1_amt1_w_delay17_r;
            gradient_shift1_amt1_w_delay19_r <= gradient_shift1_amt1_w_delay18_r;
            gradient_shift1_amt1_w_delay20_r <= gradient_shift1_amt1_w_delay19_r;
            gradient_shift1_amt1_w_delay21_r <= gradient_shift1_amt1_w_delay20_r;
            gradient_shift1_amt1_w_delay22_r <= gradient_shift1_amt1_w_delay21_r;
            gradient_shift1_amt1_w_delay23_r <= gradient_shift1_amt1_w_delay22_r;
            gradient_shift1_amt1_w_delay24_r <= gradient_shift1_amt1_w_delay23_r;
            gradient_shift1_amt1_w_delay25_r <= gradient_shift1_amt1_w_delay24_r;
            gradient_shift1_amt1_w_delay26_r <= gradient_shift1_amt1_w_delay25_r;
            gradient_shift1_amt1_w_delay27_r <= gradient_shift1_amt1_w_delay26_r;
            gradient_shift1_amt1_w_delay28_r <= gradient_shift1_amt1_w_delay27_r;
            gradient_shift1_amt1_w_delay29_r <= gradient_shift1_amt1_w_delay28_r;
            gradient_shift1_amt1_w_delay30_r <= gradient_shift1_amt1_w_delay29_r;
            gradient_shift1_amt1_w_delay31_r <= gradient_shift1_amt1_w_delay30_r;
            gradient_shift1_amt1_w_delay32_r <= gradient_shift1_amt1_w_delay31_r;
            gradient_shift1_amt1_w_delay33_r <= gradient_shift1_amt1_w_delay32_r;
            gradient_shift1_amt1_w_delay34_r <= gradient_shift1_amt1_w_delay33_r;
            gradient_shift1_amt1_w_delay35_r <= gradient_shift1_amt1_w_delay34_r;
            gradient_shift1_amt1_w_delay36_r <= gradient_shift1_amt1_w_delay35_r;
            gradient_shift1_amt1_w_delay37_r <= gradient_shift1_amt1_w_delay36_r;
            gradient_shift1_amt1_w_delay38_r <= gradient_shift1_amt1_w_delay37_r;
            gradient_shift1_amt1_w_delay39_r <= gradient_shift1_amt1_w_delay38_r;
            gradient_shift1_amt1_w_delay40_r <= gradient_shift1_amt1_w_delay39_r;
            gradient_shift1_amt1_w_delay41_r <= gradient_shift1_amt1_w_delay40_r;
            gradient_shift1_amt1_w_delay42_r <= gradient_shift1_amt1_w_delay41_r;
            gradient_shift1_amt1_w_delay43_r <= gradient_shift1_amt1_w_delay42_r;
            gradient_shift1_amt1_w_delay44_r <= gradient_shift1_amt1_w_delay43_r;
            gradient_shift1_amt2_w_delay3_r <= gradient_shift1_amt2_w;
            gradient_shift1_amt2_w_delay4_r <= gradient_shift1_amt2_w_delay3_r;
            gradient_shift1_amt2_w_delay5_r <= gradient_shift1_amt2_w_delay4_r;
            gradient_shift1_amt2_w_delay6_r <= gradient_shift1_amt2_w_delay5_r;
            gradient_shift1_amt2_w_delay7_r <= gradient_shift1_amt2_w_delay6_r;
            gradient_shift1_amt2_w_delay8_r <= gradient_shift1_amt2_w_delay7_r;
            gradient_shift1_amt2_w_delay9_r <= gradient_shift1_amt2_w_delay8_r;
            gradient_shift1_amt2_w_delay10_r <= gradient_shift1_amt2_w_delay9_r;
            gradient_shift1_amt2_w_delay11_r <= gradient_shift1_amt2_w_delay10_r;
            gradient_shift1_amt2_w_delay12_r <= gradient_shift1_amt2_w_delay11_r;
            gradient_shift1_amt2_w_delay13_r <= gradient_shift1_amt2_w_delay12_r;
            gradient_shift1_amt2_w_delay14_r <= gradient_shift1_amt2_w_delay13_r;
            gradient_shift1_amt2_w_delay15_r <= gradient_shift1_amt2_w_delay14_r;
            gradient_shift1_amt2_w_delay16_r <= gradient_shift1_amt2_w_delay15_r;
            gradient_shift1_amt2_w_delay17_r <= gradient_shift1_amt2_w_delay16_r;
            gradient_shift1_amt2_w_delay18_r <= gradient_shift1_amt2_w_delay17_r;
            gradient_shift1_amt2_w_delay19_r <= gradient_shift1_amt2_w_delay18_r;
            gradient_shift1_amt2_w_delay20_r <= gradient_shift1_amt2_w_delay19_r;
            gradient_shift1_amt2_w_delay21_r <= gradient_shift1_amt2_w_delay20_r;
            gradient_shift1_amt2_w_delay22_r <= gradient_shift1_amt2_w_delay21_r;
            gradient_shift1_amt2_w_delay23_r <= gradient_shift1_amt2_w_delay22_r;
            gradient_shift1_amt2_w_delay24_r <= gradient_shift1_amt2_w_delay23_r;
            gradient_shift1_amt2_w_delay25_r <= gradient_shift1_amt2_w_delay24_r;
            gradient_shift1_amt2_w_delay26_r <= gradient_shift1_amt2_w_delay25_r;
            gradient_shift1_amt2_w_delay27_r <= gradient_shift1_amt2_w_delay26_r;
            gradient_shift1_amt2_w_delay28_r <= gradient_shift1_amt2_w_delay27_r;
            gradient_shift1_amt2_w_delay29_r <= gradient_shift1_amt2_w_delay28_r;
            gradient_shift1_amt2_w_delay30_r <= gradient_shift1_amt2_w_delay29_r;
            gradient_shift1_amt2_w_delay31_r <= gradient_shift1_amt2_w_delay30_r;
            gradient_shift1_amt2_w_delay32_r <= gradient_shift1_amt2_w_delay31_r;
            gradient_shift1_amt2_w_delay33_r <= gradient_shift1_amt2_w_delay32_r;
            gradient_shift1_amt2_w_delay34_r <= gradient_shift1_amt2_w_delay33_r;
            gradient_shift1_amt2_w_delay35_r <= gradient_shift1_amt2_w_delay34_r;
            gradient_shift1_amt2_w_delay36_r <= gradient_shift1_amt2_w_delay35_r;
            gradient_shift1_amt2_w_delay37_r <= gradient_shift1_amt2_w_delay36_r;
            gradient_shift1_amt2_w_delay38_r <= gradient_shift1_amt2_w_delay37_r;
            gradient_shift1_amt2_w_delay39_r <= gradient_shift1_amt2_w_delay38_r;
            gradient_shift1_amt2_w_delay40_r <= gradient_shift1_amt2_w_delay39_r;
            gradient_shift1_amt2_w_delay41_r <= gradient_shift1_amt2_w_delay40_r;
            gradient_shift1_amt2_w_delay42_r <= gradient_shift1_amt2_w_delay41_r;
            gradient_shift1_amt2_w_delay43_r <= gradient_shift1_amt2_w_delay42_r;
            gradient_shift1_amt2_w_delay44_r <= gradient_shift1_amt2_w_delay43_r;
            gradient_shift1_amt2_w_delay45_r <= gradient_shift1_amt2_w_delay44_r;
            gradient_shift1_amt3_w_delay3_r <= gradient_shift1_amt3_w;
            gradient_shift1_amt3_w_delay4_r <= gradient_shift1_amt3_w_delay3_r;
            gradient_shift1_amt3_w_delay5_r <= gradient_shift1_amt3_w_delay4_r;
            gradient_shift1_amt3_w_delay6_r <= gradient_shift1_amt3_w_delay5_r;
            gradient_shift1_amt3_w_delay7_r <= gradient_shift1_amt3_w_delay6_r;
            gradient_shift1_amt3_w_delay8_r <= gradient_shift1_amt3_w_delay7_r;
            gradient_shift1_amt3_w_delay9_r <= gradient_shift1_amt3_w_delay8_r;
            gradient_shift1_amt3_w_delay10_r <= gradient_shift1_amt3_w_delay9_r;
            gradient_shift1_amt3_w_delay11_r <= gradient_shift1_amt3_w_delay10_r;
            gradient_shift1_amt3_w_delay12_r <= gradient_shift1_amt3_w_delay11_r;
            gradient_shift1_amt3_w_delay13_r <= gradient_shift1_amt3_w_delay12_r;
            gradient_shift1_amt3_w_delay14_r <= gradient_shift1_amt3_w_delay13_r;
            gradient_shift1_amt3_w_delay15_r <= gradient_shift1_amt3_w_delay14_r;
            gradient_shift1_amt3_w_delay16_r <= gradient_shift1_amt3_w_delay15_r;
            gradient_shift1_amt3_w_delay17_r <= gradient_shift1_amt3_w_delay16_r;
            gradient_shift1_amt3_w_delay18_r <= gradient_shift1_amt3_w_delay17_r;
            gradient_shift1_amt3_w_delay19_r <= gradient_shift1_amt3_w_delay18_r;
            gradient_shift1_amt3_w_delay20_r <= gradient_shift1_amt3_w_delay19_r;
            gradient_shift1_amt3_w_delay21_r <= gradient_shift1_amt3_w_delay20_r;
            gradient_shift1_amt3_w_delay22_r <= gradient_shift1_amt3_w_delay21_r;
            gradient_shift1_amt3_w_delay23_r <= gradient_shift1_amt3_w_delay22_r;
            gradient_shift1_amt3_w_delay24_r <= gradient_shift1_amt3_w_delay23_r;
            gradient_shift1_amt3_w_delay25_r <= gradient_shift1_amt3_w_delay24_r;
            gradient_shift1_amt3_w_delay26_r <= gradient_shift1_amt3_w_delay25_r;
            gradient_shift1_amt3_w_delay27_r <= gradient_shift1_amt3_w_delay26_r;
            gradient_shift1_amt3_w_delay28_r <= gradient_shift1_amt3_w_delay27_r;
            gradient_shift1_amt3_w_delay29_r <= gradient_shift1_amt3_w_delay28_r;
            gradient_shift1_amt3_w_delay30_r <= gradient_shift1_amt3_w_delay29_r;
            gradient_shift1_amt3_w_delay31_r <= gradient_shift1_amt3_w_delay30_r;
            gradient_shift1_amt3_w_delay32_r <= gradient_shift1_amt3_w_delay31_r;
            gradient_shift1_amt3_w_delay33_r <= gradient_shift1_amt3_w_delay32_r;
            gradient_shift1_amt3_w_delay34_r <= gradient_shift1_amt3_w_delay33_r;
            gradient_shift1_amt3_w_delay35_r <= gradient_shift1_amt3_w_delay34_r;
            gradient_shift1_amt3_w_delay36_r <= gradient_shift1_amt3_w_delay35_r;
            gradient_shift1_amt3_w_delay37_r <= gradient_shift1_amt3_w_delay36_r;
            gradient_shift1_amt3_w_delay38_r <= gradient_shift1_amt3_w_delay37_r;
            gradient_shift1_amt3_w_delay39_r <= gradient_shift1_amt3_w_delay38_r;
            gradient_shift1_amt3_w_delay40_r <= gradient_shift1_amt3_w_delay39_r;
            gradient_shift1_amt3_w_delay41_r <= gradient_shift1_amt3_w_delay40_r;
            gradient_shift1_amt3_w_delay42_r <= gradient_shift1_amt3_w_delay41_r;
            gradient_shift1_amt3_w_delay43_r <= gradient_shift1_amt3_w_delay42_r;
            gradient_shift1_amt3_w_delay44_r <= gradient_shift1_amt3_w_delay43_r;
            gradient_shift1_amt3_w_delay45_r <= gradient_shift1_amt3_w_delay44_r;
            gradient_shift1_amt3_w_delay46_r <= gradient_shift1_amt3_w_delay45_r;
            inverse_abs1_sign_delay38_r <= inverse_abs1_sign_r;
            inverse_abs1_sign_delay39_r <= inverse_abs1_sign_delay38_r;
            inverse_abs1_sign_delay40_r <= inverse_abs1_sign_delay39_r;
            inverse_abs1_sign_delay41_r <= inverse_abs1_sign_delay40_r;
            inverse_abs1_sign_delay42_r <= inverse_abs1_sign_delay41_r;
            inverse_abs1_sign_delay43_r <= inverse_abs1_sign_delay42_r;
            inverse_abs1_sign_delay44_r <= inverse_abs1_sign_delay43_r;
            inverse_abs1_sign_delay45_r <= inverse_abs1_sign_delay44_r;
            inverse_abs1_sign_delay46_r <= inverse_abs1_sign_delay45_r;
            inverse_abs1_sign_delay47_r <= inverse_abs1_sign_delay46_r;
            inverse_abs1_sign_delay48_r <= inverse_abs1_sign_d47_r;
            gradient_signed1_a1_w_delay49_r <= gradient_signed1_a1_w;
            gradient_signed1_b1_w_delay49_r <= gradient_signed1_b1_w;
            gradient_signed1_low0_w_delay50_r <= gradient_signed1_low0_w;
            origin_product1_sum0_0_a1_w_delay52_r <= origin_product1_sum0_0_a1_w;
            origin_product1_sum0_0_b1_w_delay52_r <= origin_product1_sum0_0_b1_w;
            origin_product1_sum0_0_a2_w_delay52_r <= origin_product1_sum0_0_a2_w;
            origin_product1_sum0_0_a2_w_delay53_r <= origin_product1_sum0_0_a2_w_delay52_r;
            origin_product1_sum0_0_b2_w_delay52_r <= origin_product1_sum0_0_b2_w;
            origin_product1_sum0_0_b2_w_delay53_r <= origin_product1_sum0_0_b2_w_delay52_r;
            origin_product1_sum0_0_low1_w_delay54_r <= origin_product1_sum0_0_low1_w;
            origin_product1_sum0_0_low0_w_delay53_r <= origin_product1_sum0_0_low0_w;
            origin_product1_sum0_0_low0_w_delay54_r <= origin_product1_sum0_0_low0_w_delay53_r;
            origin_product1_sum0_1_a1_w_delay52_r <= origin_product1_sum0_1_a1_w;
            origin_product1_sum0_1_b1_w_delay52_r <= origin_product1_sum0_1_b1_w;
            origin_product1_sum0_1_a2_w_delay52_r <= origin_product1_sum0_1_a2_w;
            origin_product1_sum0_1_a2_w_delay53_r <= origin_product1_sum0_1_a2_w_delay52_r;
            origin_product1_sum0_1_b2_w_delay52_r <= origin_product1_sum0_1_b2_w;
            origin_product1_sum0_1_b2_w_delay53_r <= origin_product1_sum0_1_b2_w_delay52_r;
            origin_product1_sum0_1_low1_w_delay54_r <= origin_product1_sum0_1_low1_w;
            origin_product1_sum0_1_low0_w_delay53_r <= origin_product1_sum0_1_low0_w;
            origin_product1_sum0_1_low0_w_delay54_r <= origin_product1_sum0_1_low0_w_delay53_r;
            origin_product1_sum1_0_a1_w_delay55_r <= origin_product1_sum1_0_a1_w;
            origin_product1_sum1_0_b1_w_delay55_r <= origin_product1_sum1_0_b1_w;
            origin_product1_sum1_0_a2_w_delay55_r <= origin_product1_sum1_0_a2_w;
            origin_product1_sum1_0_a2_w_delay56_r <= origin_product1_sum1_0_a2_w_delay55_r;
            origin_product1_sum1_0_b2_w_delay55_r <= origin_product1_sum1_0_b2_w;
            origin_product1_sum1_0_b2_w_delay56_r <= origin_product1_sum1_0_b2_w_delay55_r;
            origin_product1_sum1_0_low1_w_delay57_r <= origin_product1_sum1_0_low1_w;
            origin_product1_sum1_0_low0_w_delay56_r <= origin_product1_sum1_0_low0_w;
            origin_product1_sum1_0_low0_w_delay57_r <= origin_product1_sum1_0_low0_w_delay56_r;
            gradient_abs1_a1_w_delay52_r <= gradient_abs1_a1_w;
            gradient_abs1_b1_w_delay52_r <= gradient_abs1_b1_w;
            gradient_abs1_low0_w_delay53_r <= gradient_abs1_low0_w;
            gradient_drop1_amt0_w_delay2_r <= gradient_drop1_amt0_w;
            gradient_drop1_amt0_w_delay3_r <= gradient_drop1_amt0_w_delay2_r;
            gradient_drop1_amt0_w_delay4_r <= gradient_drop1_amt0_w_delay3_r;
            gradient_drop1_amt0_w_delay5_r <= gradient_drop1_amt0_w_delay4_r;
            gradient_drop1_amt0_w_delay6_r <= gradient_drop1_amt0_w_delay5_r;
            gradient_drop1_amt0_w_delay7_r <= gradient_drop1_amt0_w_delay6_r;
            gradient_drop1_amt0_w_delay8_r <= gradient_drop1_amt0_w_delay7_r;
            gradient_drop1_amt0_w_delay9_r <= gradient_drop1_amt0_w_delay8_r;
            gradient_drop1_amt0_w_delay10_r <= gradient_drop1_amt0_w_delay9_r;
            gradient_drop1_amt0_w_delay11_r <= gradient_drop1_amt0_w_delay10_r;
            gradient_drop1_amt0_w_delay12_r <= gradient_drop1_amt0_w_delay11_r;
            gradient_drop1_amt0_w_delay13_r <= gradient_drop1_amt0_w_delay12_r;
            gradient_drop1_amt0_w_delay14_r <= gradient_drop1_amt0_w_delay13_r;
            gradient_drop1_amt0_w_delay15_r <= gradient_drop1_amt0_w_delay14_r;
            gradient_drop1_amt0_w_delay16_r <= gradient_drop1_amt0_w_delay15_r;
            gradient_drop1_amt0_w_delay17_r <= gradient_drop1_amt0_w_delay16_r;
            gradient_drop1_amt0_w_delay18_r <= gradient_drop1_amt0_w_delay17_r;
            gradient_drop1_amt0_w_delay19_r <= gradient_drop1_amt0_w_delay18_r;
            gradient_drop1_amt0_w_delay20_r <= gradient_drop1_amt0_w_delay19_r;
            gradient_drop1_amt0_w_delay21_r <= gradient_drop1_amt0_w_delay20_r;
            gradient_drop1_amt0_w_delay22_r <= gradient_drop1_amt0_w_delay21_r;
            gradient_drop1_amt0_w_delay23_r <= gradient_drop1_amt0_w_delay22_r;
            gradient_drop1_amt0_w_delay24_r <= gradient_drop1_amt0_w_delay23_r;
            gradient_drop1_amt0_w_delay25_r <= gradient_drop1_amt0_w_delay24_r;
            gradient_drop1_amt0_w_delay26_r <= gradient_drop1_amt0_w_delay25_r;
            gradient_drop1_amt0_w_delay27_r <= gradient_drop1_amt0_w_delay26_r;
            gradient_drop1_amt0_w_delay28_r <= gradient_drop1_amt0_w_delay27_r;
            gradient_drop1_amt0_w_delay29_r <= gradient_drop1_amt0_w_delay28_r;
            gradient_drop1_amt0_w_delay30_r <= gradient_drop1_amt0_w_delay29_r;
            gradient_drop1_amt0_w_delay31_r <= gradient_drop1_amt0_w_delay30_r;
            gradient_drop1_amt0_w_delay32_r <= gradient_drop1_amt0_w_delay31_r;
            gradient_drop1_amt0_w_delay33_r <= gradient_drop1_amt0_w_delay32_r;
            gradient_drop1_amt0_w_delay34_r <= gradient_drop1_amt0_w_delay33_r;
            gradient_drop1_amt0_w_delay35_r <= gradient_drop1_amt0_w_delay34_r;
            gradient_drop1_amt0_w_delay36_r <= gradient_drop1_amt0_w_delay35_r;
            gradient_drop1_amt0_w_delay37_r <= gradient_drop1_amt0_w_delay36_r;
            gradient_drop1_amt0_w_delay38_r <= gradient_drop1_amt0_w_delay37_r;
            gradient_drop1_amt0_w_delay39_r <= gradient_drop1_amt0_w_delay38_r;
            gradient_drop1_amt0_w_delay40_r <= gradient_drop1_amt0_w_delay39_r;
            gradient_drop1_amt0_w_delay41_r <= gradient_drop1_amt0_w_delay40_r;
            gradient_drop1_amt0_w_delay42_r <= gradient_drop1_amt0_w_delay41_r;
            gradient_drop1_amt0_w_delay43_r <= gradient_drop1_amt0_w_delay42_r;
            gradient_drop1_amt0_w_delay44_r <= gradient_drop1_amt0_w_delay43_r;
            gradient_drop1_amt0_w_delay45_r <= gradient_drop1_amt0_w_delay44_r;
            gradient_drop1_amt0_w_delay46_r <= gradient_drop1_amt0_w_delay45_r;
            gradient_drop1_amt0_w_delay47_r <= gradient_drop1_amt0_w_delay46_r;
            gradient_drop1_amt0_w_delay48_r <= gradient_drop1_amt0_w_delay47_r;
            gradient_drop1_amt0_w_delay49_r <= gradient_drop1_amt0_w_delay48_r;
        end
    end
    always @(posedge clk_i) begin
        if (pipeline_enable_w[17]) begin
            gradient_drop1_amt0_w_delay50_r <= gradient_drop1_amt0_w_delay49_r;
            gradient_drop1_amt0_w_delay51_r <= gradient_drop1_amt0_w_delay50_r;
            gradient_drop1_amt0_w_delay52_r <= gradient_drop1_amt0_w_delay51_r;
            gradient_drop1_amt0_w_delay53_r <= gradient_drop1_amt0_w_delay52_r;
            gradient_drop1_amt1_w_delay2_r <= gradient_drop1_amt1_w;
            gradient_drop1_amt1_w_delay3_r <= gradient_drop1_amt1_w_delay2_r;
            gradient_drop1_amt1_w_delay4_r <= gradient_drop1_amt1_w_delay3_r;
            gradient_drop1_amt1_w_delay5_r <= gradient_drop1_amt1_w_delay4_r;
            gradient_drop1_amt1_w_delay6_r <= gradient_drop1_amt1_w_delay5_r;
            gradient_drop1_amt1_w_delay7_r <= gradient_drop1_amt1_w_delay6_r;
            gradient_drop1_amt1_w_delay8_r <= gradient_drop1_amt1_w_delay7_r;
            gradient_drop1_amt1_w_delay9_r <= gradient_drop1_amt1_w_delay8_r;
            gradient_drop1_amt1_w_delay10_r <= gradient_drop1_amt1_w_delay9_r;
            gradient_drop1_amt1_w_delay11_r <= gradient_drop1_amt1_w_delay10_r;
            gradient_drop1_amt1_w_delay12_r <= gradient_drop1_amt1_w_delay11_r;
            gradient_drop1_amt1_w_delay13_r <= gradient_drop1_amt1_w_delay12_r;
            gradient_drop1_amt1_w_delay14_r <= gradient_drop1_amt1_w_delay13_r;
            gradient_drop1_amt1_w_delay15_r <= gradient_drop1_amt1_w_delay14_r;
            gradient_drop1_amt1_w_delay16_r <= gradient_drop1_amt1_w_delay15_r;
            gradient_drop1_amt1_w_delay17_r <= gradient_drop1_amt1_w_delay16_r;
            gradient_drop1_amt1_w_delay18_r <= gradient_drop1_amt1_w_delay17_r;
            gradient_drop1_amt1_w_delay19_r <= gradient_drop1_amt1_w_delay18_r;
            gradient_drop1_amt1_w_delay20_r <= gradient_drop1_amt1_w_delay19_r;
            gradient_drop1_amt1_w_delay21_r <= gradient_drop1_amt1_w_delay20_r;
            gradient_drop1_amt1_w_delay22_r <= gradient_drop1_amt1_w_delay21_r;
            gradient_drop1_amt1_w_delay23_r <= gradient_drop1_amt1_w_delay22_r;
            gradient_drop1_amt1_w_delay24_r <= gradient_drop1_amt1_w_delay23_r;
            gradient_drop1_amt1_w_delay25_r <= gradient_drop1_amt1_w_delay24_r;
            gradient_drop1_amt1_w_delay26_r <= gradient_drop1_amt1_w_delay25_r;
            gradient_drop1_amt1_w_delay27_r <= gradient_drop1_amt1_w_delay26_r;
            gradient_drop1_amt1_w_delay28_r <= gradient_drop1_amt1_w_delay27_r;
            gradient_drop1_amt1_w_delay29_r <= gradient_drop1_amt1_w_delay28_r;
            gradient_drop1_amt1_w_delay30_r <= gradient_drop1_amt1_w_delay29_r;
            gradient_drop1_amt1_w_delay31_r <= gradient_drop1_amt1_w_delay30_r;
            gradient_drop1_amt1_w_delay32_r <= gradient_drop1_amt1_w_delay31_r;
            gradient_drop1_amt1_w_delay33_r <= gradient_drop1_amt1_w_delay32_r;
            gradient_drop1_amt1_w_delay34_r <= gradient_drop1_amt1_w_delay33_r;
            gradient_drop1_amt1_w_delay35_r <= gradient_drop1_amt1_w_delay34_r;
            gradient_drop1_amt1_w_delay36_r <= gradient_drop1_amt1_w_delay35_r;
            gradient_drop1_amt1_w_delay37_r <= gradient_drop1_amt1_w_delay36_r;
            gradient_drop1_amt1_w_delay38_r <= gradient_drop1_amt1_w_delay37_r;
            gradient_drop1_amt1_w_delay39_r <= gradient_drop1_amt1_w_delay38_r;
            gradient_drop1_amt1_w_delay40_r <= gradient_drop1_amt1_w_delay39_r;
            gradient_drop1_amt1_w_delay41_r <= gradient_drop1_amt1_w_delay40_r;
            gradient_drop1_amt1_w_delay42_r <= gradient_drop1_amt1_w_delay41_r;
            gradient_drop1_amt1_w_delay43_r <= gradient_drop1_amt1_w_delay42_r;
            gradient_drop1_amt1_w_delay44_r <= gradient_drop1_amt1_w_delay43_r;
            gradient_drop1_amt1_w_delay45_r <= gradient_drop1_amt1_w_delay44_r;
            gradient_drop1_amt1_w_delay46_r <= gradient_drop1_amt1_w_delay45_r;
            gradient_drop1_amt1_w_delay47_r <= gradient_drop1_amt1_w_delay46_r;
            gradient_drop1_amt1_w_delay48_r <= gradient_drop1_amt1_w_delay47_r;
            gradient_drop1_amt1_w_delay49_r <= gradient_drop1_amt1_w_delay48_r;
            gradient_drop1_amt1_w_delay50_r <= gradient_drop1_amt1_w_delay49_r;
            gradient_drop1_amt1_w_delay51_r <= gradient_drop1_amt1_w_delay50_r;
            gradient_drop1_amt1_w_delay52_r <= gradient_drop1_amt1_w_delay51_r;
            gradient_drop1_amt1_w_delay53_r <= gradient_drop1_amt1_w_delay52_r;
            gradient_drop1_amt1_w_delay54_r <= gradient_drop1_amt1_w_delay53_r;
            stored_round1_a1_w_delay56_r <= stored_round1_a1_w;
            stored_round1_b1_w_delay56_r <= stored_round1_b1_w;
            stored_round1_low0_w_delay57_r <= stored_round1_low0_w;
            gradient_abs1_sign_delay52_r <= gradient_abs1_sign_r;
            gradient_abs1_sign_delay53_r <= gradient_abs1_sign_delay52_r;
            gradient_abs1_sign_delay54_r <= gradient_abs1_sign_delay53_r;
            gradient_abs1_sign_delay55_r <= gradient_abs1_sign_delay54_r;
            gradient_abs1_sign_delay56_r <= gradient_abs1_sign_delay55_r;
            gradient_abs1_sign_delay57_r <= gradient_abs1_sign_delay56_r;
            gradient_abs1_sign_delay58_r <= gradient_abs1_sign_d57_r;
            stored_signed1_a1_w_delay59_r <= stored_signed1_a1_w;
            stored_signed1_b1_w_delay59_r <= stored_signed1_b1_w;
            stored_signed1_low0_w_delay60_r <= stored_signed1_low0_w;
            origin_sum_a1_w_delay58_r <= origin_sum_a1_w;
            origin_sum_b1_w_delay58_r <= origin_sum_b1_w;
            origin_sum_a2_w_delay58_r <= origin_sum_a2_w;
            origin_sum_a2_w_delay59_r <= origin_sum_a2_w_delay58_r;
            origin_sum_b2_w_delay58_r <= origin_sum_b2_w;
            origin_sum_b2_w_delay59_r <= origin_sum_b2_w_delay58_r;
            origin_sum_low1_w_delay60_r <= origin_sum_low1_w;
            origin_sum_low0_w_delay59_r <= origin_sum_low0_w;
            origin_sum_low0_w_delay60_r <= origin_sum_low0_w_delay59_r;
            origin_absolute_a1_w_delay62_r <= origin_absolute_a1_w;
            origin_absolute_b1_w_delay62_r <= origin_absolute_b1_w;
            origin_absolute_a2_w_delay62_r <= origin_absolute_a2_w;
            origin_absolute_a2_w_delay63_r <= origin_absolute_a2_w_delay62_r;
            origin_absolute_b2_w_delay62_r <= origin_absolute_b2_w;
            origin_absolute_b2_w_delay63_r <= origin_absolute_b2_w_delay62_r;
            origin_absolute_low1_w_delay64_r <= origin_absolute_low1_w;
            origin_absolute_low0_w_delay63_r <= origin_absolute_low0_w;
            origin_absolute_low0_w_delay64_r <= origin_absolute_low0_w_delay63_r;
            origin_round_a1_w_delay65_r <= origin_round_a1_w;
            origin_round_b1_w_delay65_r <= origin_round_b1_w;
            origin_round_a2_w_delay65_r <= origin_round_a2_w;
            origin_round_a2_w_delay66_r <= origin_round_a2_w_delay65_r;
            origin_round_b2_w_delay65_r <= origin_round_b2_w;
            origin_round_b2_w_delay66_r <= origin_round_b2_w_delay65_r;
            origin_round_low1_w_delay67_r <= origin_round_low1_w;
            origin_round_low0_w_delay66_r <= origin_round_low0_w;
            origin_round_low0_w_delay67_r <= origin_round_low0_w_delay66_r;
            origin_absolute_sign_delay62_r <= origin_absolute_sign_r;
            origin_absolute_sign_delay63_r <= origin_absolute_sign_delay62_r;
            origin_absolute_sign_delay64_r <= origin_absolute_sign_delay63_r;
            origin_absolute_sign_delay65_r <= origin_absolute_sign_delay64_r;
            origin_absolute_sign_delay66_r <= origin_absolute_sign_delay65_r;
            origin_absolute_sign_delay67_r <= origin_absolute_sign_delay66_r;
            origin_absolute_sign_delay68_r <= origin_absolute_sign_delay67_r;
            origin_absolute_sign_delay69_r <= origin_absolute_sign_d68_r;
            origin_signed_a1_w_delay70_r <= origin_signed_a1_w;
            origin_signed_b1_w_delay70_r <= origin_signed_b1_w;
            origin_signed_a2_w_delay70_r <= origin_signed_a2_w;
            origin_signed_a2_w_delay71_r <= origin_signed_a2_w_delay70_r;
            origin_signed_b2_w_delay70_r <= origin_signed_b2_w;
            origin_signed_b2_w_delay71_r <= origin_signed_b2_w_delay70_r;
            origin_signed_low1_w_delay72_r <= origin_signed_low1_w;
            origin_signed_low0_w_delay71_r <= origin_signed_low0_w;
            origin_signed_low0_w_delay72_r <= origin_signed_low0_w_delay71_r;
            start_sum_a1_w_delay73_r <= start_sum_a1_w;
            start_sum_b1_w_delay73_r <= start_sum_b1_w;
            start_sum_low0_w_delay74_r <= start_sum_low0_w;
            start_absolute_a1_w_delay76_r <= start_absolute_a1_w;
        end
    end
    always @(posedge clk_i) begin
        if (pipeline_enable_w[18]) begin
            start_absolute_b1_w_delay76_r <= start_absolute_b1_w;
            start_absolute_low0_w_delay77_r <= start_absolute_low0_w;
            start_drop_amt0_w_delay2_r <= start_drop_amt0_w;
            start_drop_amt0_w_delay3_r <= start_drop_amt0_w_delay2_r;
            start_drop_amt0_w_delay4_r <= start_drop_amt0_w_delay3_r;
            start_drop_amt0_w_delay5_r <= start_drop_amt0_w_delay4_r;
            start_drop_amt0_w_delay6_r <= start_drop_amt0_w_delay5_r;
            start_drop_amt0_w_delay7_r <= start_drop_amt0_w_delay6_r;
            start_drop_amt0_w_delay8_r <= start_drop_amt0_w_delay7_r;
            start_drop_amt0_w_delay9_r <= start_drop_amt0_w_delay8_r;
            start_drop_amt0_w_delay10_r <= start_drop_amt0_w_delay9_r;
            start_drop_amt0_w_delay11_r <= start_drop_amt0_w_delay10_r;
            start_drop_amt0_w_delay12_r <= start_drop_amt0_w_delay11_r;
            start_drop_amt0_w_delay13_r <= start_drop_amt0_w_delay12_r;
            start_drop_amt0_w_delay14_r <= start_drop_amt0_w_delay13_r;
            start_drop_amt0_w_delay15_r <= start_drop_amt0_w_delay14_r;
            start_drop_amt0_w_delay16_r <= start_drop_amt0_w_delay15_r;
            start_drop_amt0_w_delay17_r <= start_drop_amt0_w_delay16_r;
            start_drop_amt0_w_delay18_r <= start_drop_amt0_w_delay17_r;
            start_drop_amt0_w_delay19_r <= start_drop_amt0_w_delay18_r;
            start_drop_amt0_w_delay20_r <= start_drop_amt0_w_delay19_r;
            start_drop_amt0_w_delay21_r <= start_drop_amt0_w_delay20_r;
            start_drop_amt0_w_delay22_r <= start_drop_amt0_w_delay21_r;
            start_drop_amt0_w_delay23_r <= start_drop_amt0_w_delay22_r;
            start_drop_amt0_w_delay24_r <= start_drop_amt0_w_delay23_r;
            start_drop_amt0_w_delay25_r <= start_drop_amt0_w_delay24_r;
            start_drop_amt0_w_delay26_r <= start_drop_amt0_w_delay25_r;
            start_drop_amt0_w_delay27_r <= start_drop_amt0_w_delay26_r;
            start_drop_amt0_w_delay28_r <= start_drop_amt0_w_delay27_r;
            start_drop_amt0_w_delay29_r <= start_drop_amt0_w_delay28_r;
            start_drop_amt0_w_delay30_r <= start_drop_amt0_w_delay29_r;
            start_drop_amt0_w_delay31_r <= start_drop_amt0_w_delay30_r;
            start_drop_amt0_w_delay32_r <= start_drop_amt0_w_delay31_r;
            start_drop_amt0_w_delay33_r <= start_drop_amt0_w_delay32_r;
            start_drop_amt0_w_delay34_r <= start_drop_amt0_w_delay33_r;
            start_drop_amt0_w_delay35_r <= start_drop_amt0_w_delay34_r;
            start_drop_amt0_w_delay36_r <= start_drop_amt0_w_delay35_r;
            start_drop_amt0_w_delay37_r <= start_drop_amt0_w_delay36_r;
            start_drop_amt0_w_delay38_r <= start_drop_amt0_w_delay37_r;
            start_drop_amt0_w_delay39_r <= start_drop_amt0_w_delay38_r;
            start_drop_amt0_w_delay40_r <= start_drop_amt0_w_delay39_r;
            start_drop_amt0_w_delay41_r <= start_drop_amt0_w_delay40_r;
            start_drop_amt0_w_delay42_r <= start_drop_amt0_w_delay41_r;
            start_drop_amt0_w_delay43_r <= start_drop_amt0_w_delay42_r;
            start_drop_amt0_w_delay44_r <= start_drop_amt0_w_delay43_r;
            start_drop_amt0_w_delay45_r <= start_drop_amt0_w_delay44_r;
            start_drop_amt0_w_delay46_r <= start_drop_amt0_w_delay45_r;
            start_drop_amt0_w_delay47_r <= start_drop_amt0_w_delay46_r;
            start_drop_amt0_w_delay48_r <= start_drop_amt0_w_delay47_r;
            start_drop_amt0_w_delay49_r <= start_drop_amt0_w_delay48_r;
            start_drop_amt0_w_delay50_r <= start_drop_amt0_w_delay49_r;
            start_drop_amt0_w_delay51_r <= start_drop_amt0_w_delay50_r;
            start_drop_amt0_w_delay52_r <= start_drop_amt0_w_delay51_r;
            start_drop_amt0_w_delay53_r <= start_drop_amt0_w_delay52_r;
            start_drop_amt0_w_delay54_r <= start_drop_amt0_w_delay53_r;
            start_drop_amt0_w_delay55_r <= start_drop_amt0_w_delay54_r;
            start_drop_amt0_w_delay56_r <= start_drop_amt0_w_delay55_r;
            start_drop_amt0_w_delay57_r <= start_drop_amt0_w_delay56_r;
            start_drop_amt0_w_delay58_r <= start_drop_amt0_w_delay57_r;
            start_drop_amt0_w_delay59_r <= start_drop_amt0_w_delay58_r;
            start_drop_amt0_w_delay60_r <= start_drop_amt0_w_delay59_r;
            start_drop_amt0_w_delay61_r <= start_drop_amt0_w_delay60_r;
            start_drop_amt0_w_delay62_r <= start_drop_amt0_w_delay61_r;
            start_drop_amt0_w_delay63_r <= start_drop_amt0_w_delay62_r;
            start_drop_amt0_w_delay64_r <= start_drop_amt0_w_delay63_r;
            start_drop_amt0_w_delay65_r <= start_drop_amt0_w_delay64_r;
            start_drop_amt0_w_delay66_r <= start_drop_amt0_w_delay65_r;
            start_drop_amt0_w_delay67_r <= start_drop_amt0_w_delay66_r;
            start_drop_amt0_w_delay68_r <= start_drop_amt0_w_delay67_r;
            start_drop_amt0_w_delay69_r <= start_drop_amt0_w_delay68_r;
            start_drop_amt0_w_delay70_r <= start_drop_amt0_w_delay69_r;
            start_drop_amt0_w_delay71_r <= start_drop_amt0_w_delay70_r;
            start_drop_amt0_w_delay72_r <= start_drop_amt0_w_delay71_r;
            start_drop_amt0_w_delay73_r <= start_drop_amt0_w_delay72_r;
            start_drop_amt0_w_delay74_r <= start_drop_amt0_w_delay73_r;
            start_drop_amt0_w_delay75_r <= start_drop_amt0_w_delay74_r;
            start_drop_amt0_w_delay76_r <= start_drop_amt0_w_delay75_r;
            start_drop_amt0_w_delay77_r <= start_drop_amt0_w_delay76_r;
            start_drop_amt1_w_delay2_r <= start_drop_amt1_w;
            start_drop_amt1_w_delay3_r <= start_drop_amt1_w_delay2_r;
            start_drop_amt1_w_delay4_r <= start_drop_amt1_w_delay3_r;
            start_drop_amt1_w_delay5_r <= start_drop_amt1_w_delay4_r;
            start_drop_amt1_w_delay6_r <= start_drop_amt1_w_delay5_r;
            start_drop_amt1_w_delay7_r <= start_drop_amt1_w_delay6_r;
            start_drop_amt1_w_delay8_r <= start_drop_amt1_w_delay7_r;
            start_drop_amt1_w_delay9_r <= start_drop_amt1_w_delay8_r;
            start_drop_amt1_w_delay10_r <= start_drop_amt1_w_delay9_r;
            start_drop_amt1_w_delay11_r <= start_drop_amt1_w_delay10_r;
            start_drop_amt1_w_delay12_r <= start_drop_amt1_w_delay11_r;
            start_drop_amt1_w_delay13_r <= start_drop_amt1_w_delay12_r;
            start_drop_amt1_w_delay14_r <= start_drop_amt1_w_delay13_r;
            start_drop_amt1_w_delay15_r <= start_drop_amt1_w_delay14_r;
            start_drop_amt1_w_delay16_r <= start_drop_amt1_w_delay15_r;
            start_drop_amt1_w_delay17_r <= start_drop_amt1_w_delay16_r;
            start_drop_amt1_w_delay18_r <= start_drop_amt1_w_delay17_r;
            start_drop_amt1_w_delay19_r <= start_drop_amt1_w_delay18_r;
            start_drop_amt1_w_delay20_r <= start_drop_amt1_w_delay19_r;
            start_drop_amt1_w_delay21_r <= start_drop_amt1_w_delay20_r;
            start_drop_amt1_w_delay22_r <= start_drop_amt1_w_delay21_r;
            start_drop_amt1_w_delay23_r <= start_drop_amt1_w_delay22_r;
            start_drop_amt1_w_delay24_r <= start_drop_amt1_w_delay23_r;
            start_drop_amt1_w_delay25_r <= start_drop_amt1_w_delay24_r;
            start_drop_amt1_w_delay26_r <= start_drop_amt1_w_delay25_r;
            start_drop_amt1_w_delay27_r <= start_drop_amt1_w_delay26_r;
            start_drop_amt1_w_delay28_r <= start_drop_amt1_w_delay27_r;
            start_drop_amt1_w_delay29_r <= start_drop_amt1_w_delay28_r;
            start_drop_amt1_w_delay30_r <= start_drop_amt1_w_delay29_r;
            start_drop_amt1_w_delay31_r <= start_drop_amt1_w_delay30_r;
            start_drop_amt1_w_delay32_r <= start_drop_amt1_w_delay31_r;
            start_drop_amt1_w_delay33_r <= start_drop_amt1_w_delay32_r;
            start_drop_amt1_w_delay34_r <= start_drop_amt1_w_delay33_r;
            start_drop_amt1_w_delay35_r <= start_drop_amt1_w_delay34_r;
            start_drop_amt1_w_delay36_r <= start_drop_amt1_w_delay35_r;
            start_drop_amt1_w_delay37_r <= start_drop_amt1_w_delay36_r;
            start_drop_amt1_w_delay38_r <= start_drop_amt1_w_delay37_r;
            start_drop_amt1_w_delay39_r <= start_drop_amt1_w_delay38_r;
            start_drop_amt1_w_delay40_r <= start_drop_amt1_w_delay39_r;
            start_drop_amt1_w_delay41_r <= start_drop_amt1_w_delay40_r;
            start_drop_amt1_w_delay42_r <= start_drop_amt1_w_delay41_r;
            start_drop_amt1_w_delay43_r <= start_drop_amt1_w_delay42_r;
            start_drop_amt1_w_delay44_r <= start_drop_amt1_w_delay43_r;
            start_drop_amt1_w_delay45_r <= start_drop_amt1_w_delay44_r;
            start_drop_amt1_w_delay46_r <= start_drop_amt1_w_delay45_r;
            start_drop_amt1_w_delay47_r <= start_drop_amt1_w_delay46_r;
            start_drop_amt1_w_delay48_r <= start_drop_amt1_w_delay47_r;
            start_drop_amt1_w_delay49_r <= start_drop_amt1_w_delay48_r;
            start_drop_amt1_w_delay50_r <= start_drop_amt1_w_delay49_r;
            start_drop_amt1_w_delay51_r <= start_drop_amt1_w_delay50_r;
            start_drop_amt1_w_delay52_r <= start_drop_amt1_w_delay51_r;
            start_drop_amt1_w_delay53_r <= start_drop_amt1_w_delay52_r;
            start_drop_amt1_w_delay54_r <= start_drop_amt1_w_delay53_r;
            start_drop_amt1_w_delay55_r <= start_drop_amt1_w_delay54_r;
            start_drop_amt1_w_delay56_r <= start_drop_amt1_w_delay55_r;
            start_drop_amt1_w_delay57_r <= start_drop_amt1_w_delay56_r;
            start_drop_amt1_w_delay58_r <= start_drop_amt1_w_delay57_r;
            start_drop_amt1_w_delay59_r <= start_drop_amt1_w_delay58_r;
            start_drop_amt1_w_delay60_r <= start_drop_amt1_w_delay59_r;
            start_drop_amt1_w_delay61_r <= start_drop_amt1_w_delay60_r;
            start_drop_amt1_w_delay62_r <= start_drop_amt1_w_delay61_r;
            start_drop_amt1_w_delay63_r <= start_drop_amt1_w_delay62_r;
            start_drop_amt1_w_delay64_r <= start_drop_amt1_w_delay63_r;
            start_drop_amt1_w_delay65_r <= start_drop_amt1_w_delay64_r;
            start_drop_amt1_w_delay66_r <= start_drop_amt1_w_delay65_r;
            start_drop_amt1_w_delay67_r <= start_drop_amt1_w_delay66_r;
            start_drop_amt1_w_delay68_r <= start_drop_amt1_w_delay67_r;
            start_drop_amt1_w_delay69_r <= start_drop_amt1_w_delay68_r;
            start_drop_amt1_w_delay70_r <= start_drop_amt1_w_delay69_r;
            start_drop_amt1_w_delay71_r <= start_drop_amt1_w_delay70_r;
            start_drop_amt1_w_delay72_r <= start_drop_amt1_w_delay71_r;
            start_drop_amt1_w_delay73_r <= start_drop_amt1_w_delay72_r;
            start_drop_amt1_w_delay74_r <= start_drop_amt1_w_delay73_r;
            start_drop_amt1_w_delay75_r <= start_drop_amt1_w_delay74_r;
            start_drop_amt1_w_delay76_r <= start_drop_amt1_w_delay75_r;
            start_drop_amt1_w_delay77_r <= start_drop_amt1_w_delay76_r;
            start_drop_amt1_w_delay78_r <= start_drop_amt1_w_delay77_r;
            start_round_a1_w_delay80_r <= start_round_a1_w;
            start_round_b1_w_delay80_r <= start_round_b1_w;
            start_round_low0_w_delay81_r <= start_round_low0_w;
            start_absolute_sign_delay76_r <= start_absolute_sign_r;
            start_absolute_sign_delay77_r <= start_absolute_sign_delay76_r;
            start_absolute_sign_delay78_r <= start_absolute_sign_delay77_r;
            start_absolute_sign_delay79_r <= start_absolute_sign_delay78_r;
            start_absolute_sign_delay80_r <= start_absolute_sign_delay79_r;
            start_absolute_sign_delay81_r <= start_absolute_sign_delay80_r;
            start_absolute_sign_delay82_r <= start_absolute_sign_d81_r;
            start_signed_a1_w_delay83_r <= start_signed_a1_w;
            start_signed_b1_w_delay83_r <= start_signed_b1_w;
            start_signed_low0_w_delay84_r <= start_signed_low0_w;
        end
    end
endmodule
