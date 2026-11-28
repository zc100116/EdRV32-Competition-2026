// File: edrv32_gpu2_fp32_scalar.v
// Spec: gpu-v2-spec 2.4; architecture M-6 arithmetic reservation.
// Description: II1, ten-edge FP32 RNE MUL/FMA, exact 48-bit two-APM product.
// Clock domain: clk_gpu. Free-running data; caller owns validity and retirement.
module edrv32_gpu2_fp32_scalar (
    // Clock. No reset is required for data registers.
    input wire clk_i,

    // MUL selects signed zero as the addend, preserving the product zero sign.
    input wire mul_i,
    input wire [31:0] a_i,
    input wire [31:0] b_i,
    input wire [31:0] c_i,

    // Ten sampling edges including operand capture and result packing.
    output reg [31:0] product_o,
    output reg [31:0] result_o
);
    wire [31:0] c_w;
    wire product_sign_w;
    assign product_sign_w = a_i[31] ^ b_i[31];
    assign c_w = mul_i ? {product_sign_w, 31'b0} : c_i;
    wire [23:0] a_mantissa_w;
    wire [23:0] b_mantissa_w;
    wire [23:0] c_mantissa_w;
    assign a_mantissa_w = {|a_i[30:23], a_i[22:0]};
    assign b_mantissa_w = {|b_i[30:23], b_i[22:0]};
    assign c_mantissa_w = {|c_w[30:23], c_w[22:0]};
    wire [6:0] a_lz_w;
    wire [6:0] b_lz_w;
    wire [6:0] c_lz_w;
    edrv32_gpu2_fp32_lz24 u_lz_a (
        .data_i(a_mantissa_w),
        .count_o(a_lz_w)
    );
    edrv32_gpu2_fp32_lz24 u_lz_b (
        .data_i(b_mantissa_w),
        .count_o(b_lz_w)
    );
    edrv32_gpu2_fp32_lz24 u_lz_c (
        .data_i(c_mantissa_w),
        .count_o(c_lz_w)
    );
    reg [23:0] s1_a_r;
    reg [23:0] s1_b_r;
    reg [23:0] s1_c_r;
    reg [4:0] s1_a_lz_r;
    reg [4:0] s1_b_lz_r;
    reg [4:0] s1_c_lz_r;
    reg signed [9:0] s1_a_exp_r;
    reg signed [9:0] s1_b_exp_r;
    reg signed [9:0] s1_c_exp_r;
    wire a_inf_w;
    wire b_inf_w;
    wire c_inf_w;
    wire nan_w;
    wire product_zero_w;
    assign a_inf_w = a_i[30:0] == 31'h7f800000;
    assign b_inf_w = b_i[30:0] == 31'h7f800000;
    assign c_inf_w = c_w[30:0] == 31'h7f800000;
    assign product_zero_w = !(|a_i[30:0]) || !(|b_i[30:0]);
    assign nan_w = (a_i[30:0] > 31'h7f800000) || (b_i[30:0] > 31'h7f800000)
        || (c_w[30:0] > 31'h7f800000)
        || (a_inf_w && !(|b_i[30:0])) || (b_inf_w && !(|a_i[30:0]))
        || ((a_inf_w || b_inf_w) && c_inf_w && (product_sign_w != c_w[31]));
    // Each metadata array has one writer; data are never reset.
    reg [31:0] special_data_r [0:8];
    reg special_r [0:8];
    reg product_sign_r [0:6];
    reg addend_sign_r [0:6];
    reg product_zero_r [0:5];
    reg addend_zero_r [0:1];
    integer metadata_idx;
    always @(posedge clk_i) begin
        s1_a_r <= a_mantissa_w;
        s1_b_r <= b_mantissa_w;
        s1_c_r <= c_mantissa_w;
        s1_a_lz_r <= a_lz_w[4:0];
        s1_b_lz_r <= b_lz_w[4:0];
        s1_c_lz_r <= c_lz_w[4:0];
        s1_a_exp_r <= (a_i[30:23] == 0 ? -10'sd126
            : $signed({2'b0, a_i[30:23]}) - 10'sd127) - $signed({3'b0, a_lz_w});
        s1_b_exp_r <= (b_i[30:23] == 0 ? -10'sd126
            : $signed({2'b0, b_i[30:23]}) - 10'sd127) - $signed({3'b0, b_lz_w});
        s1_c_exp_r <= (c_w[30:23] == 0 ? -10'sd126
            : $signed({2'b0, c_w[30:23]}) - 10'sd127) - $signed({3'b0, c_lz_w});
        special_r[0] <= nan_w || a_inf_w || b_inf_w || c_inf_w;
        special_data_r[0] <= nan_w ? 32'h7fc00000
            : {a_inf_w || b_inf_w ? product_sign_w : c_w[31], 8'hff, 23'b0};
        for (metadata_idx = 1; metadata_idx < 9; metadata_idx = metadata_idx + 1) begin
            special_r[metadata_idx] <= special_r[metadata_idx-1];
            special_data_r[metadata_idx] <= special_data_r[metadata_idx-1];
        end
        product_sign_r[0] <= product_sign_w;
        addend_sign_r[0] <= c_w[31];
        for (metadata_idx = 1; metadata_idx < 7; metadata_idx = metadata_idx + 1) begin
            product_sign_r[metadata_idx] <= product_sign_r[metadata_idx-1];
            addend_sign_r[metadata_idx] <= addend_sign_r[metadata_idx-1];
        end
        product_zero_r[0] <= product_zero_w;
        for (metadata_idx = 1; metadata_idx < 6; metadata_idx = metadata_idx + 1)
            product_zero_r[metadata_idx] <= product_zero_r[metadata_idx-1];
        addend_zero_r[0] <= !(|c_w[30:0]);
        addend_zero_r[1] <= addend_zero_r[0];
    end
    wire [23:0] s2_a_w;
    wire [23:0] s2_b_w;
    wire [23:0] s2_c_w;
    wire signed [9:0] s2_product_exp_w;
    assign s2_a_w = s1_a_r << s1_a_lz_r;
    assign s2_b_w = s1_b_r << s1_b_lz_r;
    assign s2_c_w = s1_c_r << s1_c_lz_r;
    assign s2_product_exp_w = s1_a_exp_r + s1_b_exp_r;
    wire [47:0] s5_product_w;
    edrv32_apm_gpu2_u24xu24 u_product (
        .clk_i(clk_i),
        .enable_i(6'b111111),
        .a_i(s2_a_w),
        .b_i(s2_b_w),
        .product_o(s5_product_w)
    );
    wire signed [9:0] s2_product_top_w;
    wire signed [9:0] s2_base_w;
    wire [9:0] s2_product_delta_w;
    wire [9:0] s2_c_delta_w;
    assign s2_product_top_w = s2_product_exp_w + 10'sd1;
    assign s2_base_w = product_zero_r[0] ? s1_c_exp_r
        : addend_zero_r[0] || s2_product_top_w >= s1_c_exp_r
            ? s2_product_top_w : s1_c_exp_r;
    assign s2_product_delta_w = s2_base_w - s2_product_top_w;
    assign s2_c_delta_w = s2_base_w - s1_c_exp_r;
    reg [23:0] s2_c_r;
    reg [5:0] s2_c_shift_r;
    reg [5:0] product_shift_r [2:5];
    reg signed [9:0] base_exp_r [2:7];
    integer align_idx;
    always @(posedge clk_i) begin
        s2_c_r <= s2_c_w;
        s2_c_shift_r <= s2_c_delta_w > 10'd55 ? 6'd56 : s2_c_delta_w[5:0];
        product_shift_r[2] <= product_zero_r[0] || s2_product_delta_w > 10'd55
            ? 6'd56 : s2_product_delta_w[5:0];
        base_exp_r[2] <= s2_base_w;
        for (align_idx = 3; align_idx < 6; align_idx = align_idx + 1)
            product_shift_r[align_idx] <= product_shift_r[align_idx-1];
        for (align_idx = 3; align_idx < 8; align_idx = align_idx + 1)
            base_exp_r[align_idx] <= base_exp_r[align_idx-1];
    end
    wire [55:0] s3_c_input_w;
    wire [55:0] s3_c_shift_w;
    wire s3_sticky_w;
    assign s3_c_input_w = {1'b0, s2_c_r, 31'b0};
    assign s3_c_shift_w = s3_c_input_w >> s2_c_shift_r[2:0];
    assign s3_sticky_w = |(s3_c_input_w & ~(56'hffffffffffffff << s2_c_shift_r[2:0]));
    reg [55:0] s3_c_r;
    reg [5:3] s3_c_shift_r;
    always @(posedge clk_i) begin
        s3_c_r <= {s3_c_shift_w[55:1], s3_c_shift_w[0] | s3_sticky_w};
        s3_c_shift_r <= s2_c_shift_r[5:3];
    end
    wire [55:0] s4_c_shift_w;
    wire s4_sticky_w;
    assign s4_c_shift_w = s3_c_r >> {s3_c_shift_r, 3'b0};
    assign s4_sticky_w = |(s3_c_r & ~(56'hffffffffffffff << {s3_c_shift_r, 3'b0}));
    reg [55:0] s4_c_r;
    reg [55:0] s5_c_r;
    reg [55:0] s6_c_r;
    always @(posedge clk_i) begin
        s4_c_r <= {s4_c_shift_w[55:1], s4_c_shift_w[0] | s4_sticky_w};
        s5_c_r <= s4_c_r;
        s6_c_r <= s5_c_r;
    end
    wire [55:0] s6_product_input_w;
    wire [55:0] s6_product_shift_w;
    wire s6_product_sticky_w;
    assign s6_product_input_w = {1'b0, s5_product_w, 7'b0};
    assign s6_product_shift_w = s6_product_input_w >> product_shift_r[5];
    assign s6_product_sticky_w = |(s6_product_input_w
        & ~(56'hffffffffffffff << product_shift_r[5]));
    reg [55:0] s6_product_r;
    always @(posedge clk_i) begin
        s6_product_r <= {s6_product_shift_w[55:1],
            s6_product_shift_w[0] | s6_product_sticky_w};
    end
    wire opposite_w;
    assign opposite_w = product_sign_r[5] != addend_sign_r[5];
    reg [56:0] s7_forward_r;
    reg [55:0] s7_reverse_r;
    always @(posedge clk_i) begin
        s7_forward_r <= opposite_w ? {1'b0, s6_product_r} - {1'b0, s6_c_r}
            : {1'b0, s6_product_r} + {1'b0, s6_c_r};
        s7_reverse_r <= s6_c_r - s6_product_r;
    end
    wire [55:0] s8_magnitude_w;
    wire [6:0] s8_lz_w;
    assign s8_magnitude_w = s7_forward_r[56] ? s7_reverse_r : s7_forward_r[55:0];
    edrv32_gpu2_fp32_lz56 u_lz_sum (
        .data_i(s8_magnitude_w),
        .count_o(s8_lz_w)
    );
    wire signed [9:0] s8_exp_w;
    wire signed [9:0] s8_limit_w;
    assign s8_exp_w = base_exp_r[7] + 10'sd1 - $signed({3'b0, s8_lz_w});
    assign s8_limit_w = base_exp_r[7] + 10'sd127;
    reg [55:0] s8_magnitude_r;
    reg signed [9:0] s8_exp_r;
    reg [5:0] s8_shift_r;
    reg s8_right_r;
    reg s8_sign_r;
    reg s8_zero_r;
    always @(posedge clk_i) begin
        s8_magnitude_r <= s8_magnitude_w;
        s8_exp_r <= s8_exp_w;
        s8_right_r <= s8_limit_w < 0;
        s8_shift_r <= s8_limit_w < 0 ? (s8_limit_w < -10'sd55 ? 6'd56
            : -s8_limit_w[5:0]) : s8_exp_w < -10'sd126
                ? s8_limit_w[5:0] : s8_lz_w[5:0];
        s8_zero_r <= !(|s8_magnitude_w);
        s8_sign_r <= !(|s8_magnitude_w)
            ? product_sign_r[6] && addend_sign_r[6]
            : s7_forward_r[56] ? addend_sign_r[6] : product_sign_r[6];
    end
    wire [55:0] s9_shift_w;
    wire s9_sticky_w;
    assign s9_shift_w = s8_right_r ? s8_magnitude_r >> s8_shift_r
        : s8_magnitude_r << s8_shift_r;
    assign s9_sticky_w = s8_right_r
        && (|(s8_magnitude_r & ~(56'hffffffffffffff << s8_shift_r)));
    reg [23:0] s9_mantissa_r;
    reg s9_increment_r;
    reg signed [9:0] s9_exp_r;
    reg s9_sign_r;
    reg s9_zero_r;
    always @(posedge clk_i) begin
        s9_mantissa_r <= s9_shift_w[55:32];
        s9_increment_r <= s9_shift_w[31]
            && (s9_shift_w[32] || (|s9_shift_w[30:0]) || s9_sticky_w);
        s9_exp_r <= s8_exp_r < -10'sd126 ? -10'sd126 : s8_exp_r;
        s9_sign_r <= s8_sign_r;
        s9_zero_r <= s8_zero_r;
    end
    wire [24:0] s10_rounded_w;
    wire signed [9:0] s10_exp_w;
    wire [7:0] s10_biased_w;
    assign s10_rounded_w = {1'b0, s9_mantissa_r} + {24'b0, s9_increment_r};
    assign s10_exp_w = s9_exp_r + $signed({9'b0, s10_rounded_w[24]});
    assign s10_biased_w = s10_exp_w[7:0] + 8'd127;
    always @(posedge clk_i) begin
        result_o <= special_r[8] ? special_data_r[8]
            : s9_zero_r ? {s9_sign_r, 31'b0}
            : s10_exp_w > 10'sd127 ? {s9_sign_r, 8'hff, 23'b0}
            : {s9_sign_r, s10_rounded_w[24] ? s10_biased_w
                : s10_rounded_w[23] ? s10_biased_w : 8'b0,
                s10_rounded_w[24] ? s10_rounded_w[23:1] : s10_rounded_w[22:0]};
    end
    reg tap_special_r [0:5];
    reg [31:0] tap_special_data_r [0:5];
    wire tap_nan_w;
    assign tap_nan_w = (a_i[30:0] > 31'h7f800000) || (b_i[30:0] > 31'h7f800000)
        || (a_inf_w && !(|b_i[30:0])) || (b_inf_w && !(|a_i[30:0]));
    integer tap_idx;
    always @(posedge clk_i) begin
        tap_special_r[0] <= tap_nan_w || a_inf_w || b_inf_w;
        tap_special_data_r[0] <= tap_nan_w ? 32'h7fc00000
            : {product_sign_w, 8'hff, 23'b0};
        for (tap_idx = 1; tap_idx < 6; tap_idx = tap_idx + 1) begin
            tap_special_r[tap_idx] <= tap_special_r[tap_idx-1];
            tap_special_data_r[tap_idx] <= tap_special_data_r[tap_idx-1];
        end
    end
    reg signed [9:0] product_exp_r [2:5];
    integer exponent_idx;
    always @(posedge clk_i) begin
        product_exp_r[2] <= s2_product_exp_w;
        for (exponent_idx = 3; exponent_idx < 6; exponent_idx = exponent_idx + 1)
            product_exp_r[exponent_idx] <= product_exp_r[exponent_idx-1];
    end
    wire [76:0] tap_s6_magnitude_w;
    wire [6:0] tap_s6_lz_w;
    assign tap_s6_magnitude_w = {s5_product_w, 29'b0};
    edrv32_gpu2_fp32_lz77 u_lz_tap (
        .data_i(tap_s6_magnitude_w),
        .count_o(tap_s6_lz_w)
    );
    wire signed [9:0] tap_s6_exp_w;
    wire signed [9:0] tap_s6_limit_w;
    wire [6:0] tap_s6_shift_w;
    wire [76:0] tap_tap_s6_shifted_w;
    wire tap_s6_sticky_w;
    assign tap_s6_exp_w = product_exp_r[5] + 10'sd1 - $signed({3'b0, tap_s6_lz_w});
    assign tap_s6_limit_w = product_exp_r[5] + 10'sd127;
    assign tap_s6_shift_w = tap_s6_limit_w < 0 ? (tap_s6_limit_w < -10'sd76 ? 7'd77
        : -tap_s6_limit_w[6:0]) : tap_s6_exp_w < -10'sd126 ? tap_s6_limit_w[6:0] : tap_s6_lz_w;
    assign tap_tap_s6_shifted_w = tap_s6_limit_w < 0 ? tap_s6_magnitude_w >> tap_s6_shift_w
        : tap_s6_magnitude_w << tap_s6_shift_w;
    assign tap_s6_sticky_w = tap_s6_limit_w < 0
        && (|(tap_s6_magnitude_w & ~(77'h1fffffffffffffffffff << tap_s6_shift_w)));
    reg [23:0] tap_s6_mantissa_r;
    reg tap_s6_increment_r;
    reg signed [9:0] tap_s6_exp_r;
    always @(posedge clk_i) begin
        tap_s6_mantissa_r <= tap_tap_s6_shifted_w[76:53];
        tap_s6_increment_r <= tap_tap_s6_shifted_w[52]
            && (tap_tap_s6_shifted_w[53] || (|tap_tap_s6_shifted_w[51:0]) || tap_s6_sticky_w);
        tap_s6_exp_r <= tap_s6_exp_w < -10'sd126 ? -10'sd126 : tap_s6_exp_w;
    end
    wire [24:0] tap_s7_rounded_w;
    wire signed [9:0] tap_s7_exp_w;
    wire [7:0] tap_s7_biased_w;
    assign tap_s7_rounded_w = {1'b0, tap_s6_mantissa_r} + {24'b0, tap_s6_increment_r};
    assign tap_s7_exp_w = tap_s6_exp_r + $signed({9'b0, tap_s7_rounded_w[24]});
    assign tap_s7_biased_w = tap_s7_exp_w[7:0] + 8'd127;
    always @(posedge clk_i) begin
        product_o <= tap_special_r[5] ? tap_special_data_r[5]
            : product_zero_r[5] ? {product_sign_r[5], 31'b0}
            : tap_s7_exp_w > 10'sd127 ? {product_sign_r[5], 8'hff, 23'b0}
            : {product_sign_r[5], tap_s7_rounded_w[24] ? tap_s7_biased_w
                : tap_s7_rounded_w[23] ? tap_s7_biased_w : 8'b0,
                tap_s7_rounded_w[24] ? tap_s7_rounded_w[23:1] : tap_s7_rounded_w[22:0]};
    end
endmodule
