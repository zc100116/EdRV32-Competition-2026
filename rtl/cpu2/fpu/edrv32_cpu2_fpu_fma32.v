// File: edrv32_cpu2_fpu_fma32.v
// Spec: fpu-spec 2.2, 5.2, 5.3, 7.1.
// Description: Fully pipelined single-round FP32 fused multiply-add, II=1.
//              E1 classification through E8 result; all data registers advance.
// Clock domain: clk_sys.
module edrv32_cpu2_fpu_fma32 (
    // Clock. Data registers do not require reset.
    input wire clk_i,

    // RISC-V opcode bits [3:2]: 00 MADD, 01 MSUB, 10 NMSUB, 11 NMADD.
    input wire [31:0] a_i,
    input wire [31:0] b_i,
    input wire [31:0] c_i,
    input wire [1:0] op_i,
    input wire [2:0] rm_i,

    // Per-instruction result and NV/DZ/OF/UF/NX.
    output reg [31:0] result_o,
    output reg [4:0] flags_o
);
    wire [23:0] a_mantissa_w;
    wire [6:0] a_lz_w;
    wire a_zero_w;
    wire a_inf_w;
    wire a_nan_w;
    wire a_snan_w;
    assign a_mantissa_w = {|a_i[30:23], a_i[22:0]};
    assign a_zero_w = ~|a_i[30:0];
    assign a_inf_w = (&a_i[30:23]) && !(|a_i[22:0]);
    assign a_nan_w = (&a_i[30:23]) && (|a_i[22:0]);
    assign a_snan_w = a_nan_w && !a_i[22];
    edrv32_cpu2_fpu_lz24 u_lz_a (
        .data_i(a_mantissa_w),
        .count_o(a_lz_w)
    );
    reg [23:0] e1_a_mantissa_r;
    reg [4:0] e1_a_lz_r;
    reg signed [9:0] e1_a_exp_r;
    wire [23:0] b_mantissa_w;
    wire [6:0] b_lz_w;
    wire b_zero_w;
    wire b_inf_w;
    wire b_nan_w;
    wire b_snan_w;
    assign b_mantissa_w = {|b_i[30:23], b_i[22:0]};
    assign b_zero_w = ~|b_i[30:0];
    assign b_inf_w = (&b_i[30:23]) && !(|b_i[22:0]);
    assign b_nan_w = (&b_i[30:23]) && (|b_i[22:0]);
    assign b_snan_w = b_nan_w && !b_i[22];
    edrv32_cpu2_fpu_lz24 u_lz_b (
        .data_i(b_mantissa_w),
        .count_o(b_lz_w)
    );
    reg [23:0] e1_b_mantissa_r;
    reg [4:0] e1_b_lz_r;
    reg signed [9:0] e1_b_exp_r;
    wire [23:0] c_mantissa_w;
    wire [6:0] c_lz_w;
    wire c_zero_w;
    wire c_inf_w;
    wire c_nan_w;
    wire c_snan_w;
    assign c_mantissa_w = {|c_i[30:23], c_i[22:0]};
    assign c_zero_w = ~|c_i[30:0];
    assign c_inf_w = (&c_i[30:23]) && !(|c_i[22:0]);
    assign c_nan_w = (&c_i[30:23]) && (|c_i[22:0]);
    assign c_snan_w = c_nan_w && !c_i[22];
    edrv32_cpu2_fpu_lz24 u_lz_c (
        .data_i(c_mantissa_w),
        .count_o(c_lz_w)
    );
    reg [23:0] e1_c_mantissa_r;
    reg [4:0] e1_c_lz_r;
    reg signed [9:0] e1_c_exp_r;
    wire [6:0] unused_c_trailing_w;
    edrv32_cpu2_fpu_lz24 u_trailing_c (
        .data_i({
            c_mantissa_w[0], c_mantissa_w[1], c_mantissa_w[2], c_mantissa_w[3],
            c_mantissa_w[4], c_mantissa_w[5], c_mantissa_w[6], c_mantissa_w[7],
            c_mantissa_w[8], c_mantissa_w[9], c_mantissa_w[10], c_mantissa_w[11],
            c_mantissa_w[12], c_mantissa_w[13], c_mantissa_w[14], c_mantissa_w[15],
            c_mantissa_w[16], c_mantissa_w[17], c_mantissa_w[18], c_mantissa_w[19],
            c_mantissa_w[20], c_mantissa_w[21], c_mantissa_w[22], c_mantissa_w[23]}),
        .count_o(unused_c_trailing_w)
    );
    reg [4:0] e1_c_trailing_r;
    reg [5:0] e2_c_trailing_r;
    reg [5:0] e3_c_trailing_r;
    always @(posedge clk_i) begin
        e1_c_trailing_r <= unused_c_trailing_w[4:0];
        e2_c_trailing_r <= {1'b0, e1_c_trailing_r} + {1'b0, e1_c_lz_r};
        e3_c_trailing_r <= e2_c_trailing_r;
    end
    wire product_sign_w;
    wire c_sign_w;
    wire invalid_product_w;
    wire product_inf_w;
    wire invalid_sum_w;
    wire invalid_w;
    wire nan_w;
    assign product_sign_w = a_i[31] ^ b_i[31] ^ op_i[1];
    assign c_sign_w = c_i[31] ^ op_i[0];
    assign invalid_product_w = (a_zero_w && b_inf_w) || (b_zero_w && a_inf_w);
    assign product_inf_w = (a_inf_w || b_inf_w) && !a_nan_w && !b_nan_w;
    assign invalid_sum_w = product_inf_w && c_inf_w && !invalid_product_w
        && (product_sign_w != c_sign_w);
    assign invalid_w = a_snan_w || b_snan_w || c_snan_w
        || invalid_product_w || invalid_sum_w;
    assign nan_w = a_nan_w || b_nan_w || c_nan_w || invalid_w;

    reg e1_product_sign_r;
    reg e1_c_sign_r;
    reg e1_product_zero_r;
    reg e1_c_zero_r;
    reg [2:0] e1_rm_r;
    reg e1_special_r;
    reg [31:0] e1_special_result_r;
    reg [4:0] e1_special_flags_r;
    always @(posedge clk_i) begin
        e1_a_mantissa_r <= a_mantissa_w;
        e1_a_lz_r <= a_lz_w[4:0];
        e1_a_exp_r <= ($signed({2'b0, a_i[30:23]}) == 10'sd0
            ? -10'sd126 : $signed({2'b0, a_i[30:23]}) - 10'sd127)
            - $signed({3'b0, a_lz_w});
        e1_b_mantissa_r <= b_mantissa_w;
        e1_b_lz_r <= b_lz_w[4:0];
        e1_b_exp_r <= ($signed({2'b0, b_i[30:23]}) == 10'sd0
            ? -10'sd126 : $signed({2'b0, b_i[30:23]}) - 10'sd127)
            - $signed({3'b0, b_lz_w});
        e1_c_mantissa_r <= c_mantissa_w;
        e1_c_lz_r <= c_lz_w[4:0];
        e1_c_exp_r <= ($signed({2'b0, c_i[30:23]}) == 10'sd0
            ? -10'sd126 : $signed({2'b0, c_i[30:23]}) - 10'sd127)
            - $signed({3'b0, c_lz_w});
        e1_product_sign_r <= product_sign_w;
        e1_c_sign_r <= c_sign_w;
        e1_product_zero_r <= a_zero_w || b_zero_w;
        e1_c_zero_r <= c_zero_w;
        e1_rm_r <= rm_i;
        e1_special_r <= nan_w || product_inf_w || c_inf_w;
        e1_special_result_r <= nan_w ? 32'h7fc00000
            : {product_inf_w ? product_sign_w : c_sign_w, 8'hff, 23'b0};
        e1_special_flags_r <= {invalid_w, 4'b0};
    end

    wire [23:0] e2_a_w;
    wire [23:0] e2_b_w;
    wire [23:0] e2_c_w;
    wire [47:0] e5_product_w;
    assign e2_a_w = e1_a_mantissa_r << e1_a_lz_r;
    assign e2_b_w = e1_b_mantissa_r << e1_b_lz_r;
    assign e2_c_w = e1_c_mantissa_r << e1_c_lz_r;
    edrv32_apm_cpu2_u24xu24 u_product (
        .clk_i(clk_i),
        .a_i(e2_a_w),
        .b_i(e2_b_w),
        .product_o(e5_product_w)
    );

    // Product has its binary point below bit 48. C can extend 27 bits above it.
    // Larger C makes all product bits sticky; its sign still participates in the add.
    wire signed [9:0] e2_product_exp_w;
    wire signed [9:0] e2_delta_w;
    assign e2_product_exp_w = e1_a_exp_r + e1_b_exp_r;
    assign e2_delta_w = e1_c_exp_r - e2_product_exp_w;
    reg [23:0] e2_c_r;
    reg signed [9:0] e2_delta_r;
    reg e2_far_r;
    reg signed [9:0] e2_base_exp_r;
    always @(posedge clk_i) begin
        e2_delta_r <= e2_delta_w;
        e2_far_r <= ((e2_delta_w > 10'sd27) || e1_product_zero_r) && !e1_c_zero_r;
        e2_base_exp_r <= (((e2_delta_w > 10'sd27) || e1_product_zero_r) && !e1_c_zero_r)
            ? e1_c_exp_r - 10'sd27 : e2_product_exp_w;
        e2_c_r <= e2_c_w;
    end
    wire [6:0] e3_c_shift_w;
    wire [6:0] e3_negative_shift_w;
    assign e3_c_shift_w = 7'd25 + e2_delta_r[6:0];
    assign e3_negative_shift_w = -e3_c_shift_w[6:0];
    reg [76:0] e3_c_r;
    reg [6:0] e3_shift_r;
    reg e3_right_r;
    always @(posedge clk_i) begin
        e3_c_r <= {53'b0, e2_c_r};
        e3_right_r <= (e2_delta_r < -10'sd25) && !e2_product_zero_r;
        e3_shift_r <= e2_product_zero_r ? 7'd52
            : e2_delta_r < -10'sd102 ? 7'd77
            : e2_delta_r > 10'sd27 ? 7'd52
            : e2_delta_r < -10'sd25 ? e3_negative_shift_w : e3_c_shift_w[6:0];
    end
    wire [76:0] e4_shift0_w;
    assign e4_shift0_w = !e3_shift_r[0] ? e3_c_r
        : e3_right_r ? (e3_c_r >> 1) : (e3_c_r << 1);
    wire [76:0] e4_shift1_w;
    assign e4_shift1_w = !e3_shift_r[1] ? e4_shift0_w
        : e3_right_r ? (e4_shift0_w >> 2) : (e4_shift0_w << 2);
    wire [76:0] e4_shift2_w;
    assign e4_shift2_w = !e3_shift_r[2] ? e4_shift1_w
        : e3_right_r ? (e4_shift1_w >> 4) : (e4_shift1_w << 4);
    reg [76:0] e4_c_r;
    reg [6:3] e4_shift_r;
    reg e4_right_r;
    reg e4_sticky_r;
    always @(posedge clk_i) begin
        e4_c_r <= e4_shift2_w;
        e4_shift_r <= e3_shift_r[6:3];
        e4_right_r <= e3_right_r;
        e4_sticky_r <= e3_right_r && (e3_shift_r > {1'b0, e3_c_trailing_r})
            && (|e3_c_r);
    end
    wire [76:0] e5_shift3_w;
    assign e5_shift3_w = !e4_shift_r[3] ? e4_c_r
        : e4_right_r ? (e4_c_r >> 8) : (e4_c_r << 8);
    wire [76:0] e5_shift4_w;
    assign e5_shift4_w = !e4_shift_r[4] ? e5_shift3_w
        : e4_right_r ? (e5_shift3_w >> 16) : (e5_shift3_w << 16);
    wire [76:0] e5_shift5_w;
    assign e5_shift5_w = !e4_shift_r[5] ? e5_shift4_w
        : e4_right_r ? (e5_shift4_w >> 32) : (e5_shift4_w << 32);
    wire [76:0] e5_shift6_w;
    assign e5_shift6_w = !e4_shift_r[6] ? e5_shift5_w
        : e4_right_r ? (e5_shift5_w >> 64) : (e5_shift5_w << 64);
    reg [76:0] e5_c_r;
    reg e3_far_r;
    reg e4_far_r;
    reg e5_far_r;
    reg signed [9:0] e3_base_exp_r;
    reg signed [9:0] e4_base_exp_r;
    reg signed [9:0] e5_base_exp_r;
    always @(posedge clk_i) begin
        e3_far_r <= e2_far_r;
        e4_far_r <= e3_far_r;
        e5_far_r <= e4_far_r;
        e3_base_exp_r <= e2_base_exp_r;
        e4_base_exp_r <= e3_base_exp_r;
        e5_base_exp_r <= e4_base_exp_r;
        e5_c_r <= {e5_shift6_w[76:1], e5_shift6_w[0] | e4_sticky_r};
    end
    reg e2_product_sign_r;
    reg e2_c_sign_r;
    reg e2_product_zero_r;
    reg [2:0] e2_rm_r;
    reg e2_special_r;
    reg [31:0] e2_special_result_r;
    reg [4:0] e2_special_flags_r;
    always @(posedge clk_i) begin
        e2_product_sign_r <= e1_product_sign_r;
        e2_c_sign_r <= e1_c_sign_r;
        e2_product_zero_r <= e1_product_zero_r;
        e2_rm_r <= e1_rm_r;
        e2_special_r <= e1_special_r;
        e2_special_result_r <= e1_special_result_r;
        e2_special_flags_r <= e1_special_flags_r;
    end
    reg e3_product_sign_r;
    reg e3_c_sign_r;
    reg e3_product_zero_r;
    reg [2:0] e3_rm_r;
    reg e3_special_r;
    reg [31:0] e3_special_result_r;
    reg [4:0] e3_special_flags_r;
    always @(posedge clk_i) begin
        e3_product_sign_r <= e2_product_sign_r;
        e3_c_sign_r <= e2_c_sign_r;
        e3_product_zero_r <= e2_product_zero_r;
        e3_rm_r <= e2_rm_r;
        e3_special_r <= e2_special_r;
        e3_special_result_r <= e2_special_result_r;
        e3_special_flags_r <= e2_special_flags_r;
    end
    reg e4_product_sign_r;
    reg e4_c_sign_r;
    reg e4_product_zero_r;
    reg [2:0] e4_rm_r;
    reg e4_special_r;
    reg [31:0] e4_special_result_r;
    reg [4:0] e4_special_flags_r;
    always @(posedge clk_i) begin
        e4_product_sign_r <= e3_product_sign_r;
        e4_c_sign_r <= e3_c_sign_r;
        e4_product_zero_r <= e3_product_zero_r;
        e4_rm_r <= e3_rm_r;
        e4_special_r <= e3_special_r;
        e4_special_result_r <= e3_special_result_r;
        e4_special_flags_r <= e3_special_flags_r;
    end
    reg e5_product_sign_r;
    reg e5_c_sign_r;
    reg e5_product_zero_r;
    reg [2:0] e5_rm_r;
    reg e5_special_r;
    reg [31:0] e5_special_result_r;
    reg [4:0] e5_special_flags_r;
    always @(posedge clk_i) begin
        e5_product_sign_r <= e4_product_sign_r;
        e5_c_sign_r <= e4_c_sign_r;
        e5_product_zero_r <= e4_product_zero_r;
        e5_rm_r <= e4_rm_r;
        e5_special_r <= e4_special_r;
        e5_special_result_r <= e4_special_result_r;
        e5_special_flags_r <= e4_special_flags_r;
    end

    // Insert the min-normal position into both anticipators before their trees.
    // The first hit then clamps the left shift without a count/compare/barrel chain.
    // Very tiny products use an independently prepared right shift instead.
    wire signed [9:0] e3_limit_w;
    wire [6:0] e3_negative_limit_w;
    assign e3_limit_w = e2_base_exp_r + 10'sd154;
    assign e3_negative_limit_w = -e3_limit_w[6:0];
    reg [6:0] e3_limit_r;
    reg e3_tiny_right_r;
    reg [6:0] e3_tiny_shift_r;
    always @(posedge clk_i) begin
        e3_limit_r <= e3_limit_w < 10'sd0 ? 7'd0
            : e3_limit_w > 10'sd76 ? 7'd77 : e3_limit_w[6:0];
        e3_tiny_right_r <= e3_limit_w < 10'sd0;
        e3_tiny_shift_r <= e3_limit_w < -10'sd77 ? 7'd77 : e3_negative_limit_w;
    end
    reg [76:0] e4_marker_r;
    reg [2:0] e4_limit_r;
    reg [76:0] e5_marker_r;
    reg e4_tiny_right_r;
    reg e5_tiny_right_r;
    reg e6_tiny_right_r;
    reg [6:0] e4_tiny_shift_r;
    reg [6:0] e5_tiny_shift_r;
    reg [6:0] e6_tiny_shift_r;
    always @(posedge clk_i) begin
        e4_marker_r <= (77'b1 << 76) >> {e3_limit_r[6:3], 3'b0};
        e4_limit_r <= e3_limit_r[2:0];
        e5_marker_r <= e4_marker_r >> e4_limit_r;
        e4_tiny_right_r <= e3_tiny_right_r;
        e5_tiny_right_r <= e4_tiny_right_r;
        e6_tiny_right_r <= e5_tiny_right_r;
        e4_tiny_shift_r <= e3_tiny_shift_r;
        e5_tiny_shift_r <= e4_tiny_shift_r;
        e6_tiny_shift_r <= e5_tiny_shift_r;
    end
    wire [76:0] e6_product_w;
    wire e6_subtract_w;
    wire [77:0] e6_forward_w;
    wire [76:0] e6_reverse_w;
    wire [76:0] e6_forward_predict_w;
    wire [76:0] e6_reverse_predict_w;
    assign e6_product_w = e5_far_r ? {76'b0, !e5_product_zero_r}
        : {27'b0, e5_product_w, 2'b0};
    assign e6_subtract_w = e5_product_sign_r ^ e5_c_sign_r;
    // Two magnitude candidates keep sign selection off both 77-bit carry paths.
    assign e6_forward_w = {1'b0, e6_product_w}
        + {1'b0, (e5_c_r ^ {77{e6_subtract_w}})} + {77'b0, e6_subtract_w};
    assign e6_reverse_w = e5_c_r - e6_product_w;
    // For A-B >= 0, the first nonzero signed digit followed by a digit other
    // than -1 predicts the leading one exactly or one position high.
    // A+B uses A|B and may produce a carry one position above that prediction.
    assign e6_forward_predict_w = e6_subtract_w
        ? (e6_product_w ^ e5_c_r)
            & ~{(~e6_product_w[75:0] & e5_c_r[75:0]), 1'b0}
        : e6_product_w | e5_c_r;
    assign e6_reverse_predict_w = (e5_c_r ^ e6_product_w)
        & ~{(~e5_c_r[75:0] & e6_product_w[75:0]), 1'b0};
    wire [127:0] e6_forward_padded_w;
    wire [127:0] e6_reverse_padded_w;
    assign e6_forward_padded_w = {(e6_forward_predict_w | e5_marker_r), 51'b0};
    assign e6_reverse_padded_w = {(e6_reverse_predict_w | e5_marker_r), 51'b0};
    wire e6_forward_hit0_w;
    wire [4:0] e6_forward_count0_w;
    reg e6_forward_hit0_r;
    reg [4:0] e6_forward_count0_r;
    edrv32_cpu2_fpu_lza32 u_forward_group0 (
        .data_i(e6_forward_padded_w[127:96]),
        .hit_o(e6_forward_hit0_w),
        .count_o(e6_forward_count0_w)
    );
    always @(posedge clk_i) begin
        e6_forward_hit0_r <= e6_forward_hit0_w;
        e6_forward_count0_r <= e6_forward_count0_w;
    end
    wire e6_forward_hit1_w;
    wire [4:0] e6_forward_count1_w;
    reg e6_forward_hit1_r;
    reg [4:0] e6_forward_count1_r;
    edrv32_cpu2_fpu_lza32 u_forward_group1 (
        .data_i(e6_forward_padded_w[95:64]),
        .hit_o(e6_forward_hit1_w),
        .count_o(e6_forward_count1_w)
    );
    always @(posedge clk_i) begin
        e6_forward_hit1_r <= e6_forward_hit1_w;
        e6_forward_count1_r <= e6_forward_count1_w;
    end
    wire e6_forward_hit2_w;
    wire [4:0] e6_forward_count2_w;
    reg e6_forward_hit2_r;
    reg [4:0] e6_forward_count2_r;
    edrv32_cpu2_fpu_lza32 u_forward_group2 (
        .data_i(e6_forward_padded_w[63:32]),
        .hit_o(e6_forward_hit2_w),
        .count_o(e6_forward_count2_w)
    );
    always @(posedge clk_i) begin
        e6_forward_hit2_r <= e6_forward_hit2_w;
        e6_forward_count2_r <= e6_forward_count2_w;
    end
    wire e6_forward_hit3_w;
    wire [4:0] e6_forward_count3_w;
    reg e6_forward_hit3_r;
    reg [4:0] e6_forward_count3_r;
    edrv32_cpu2_fpu_lza32 u_forward_group3 (
        .data_i(e6_forward_padded_w[31:0]),
        .hit_o(e6_forward_hit3_w),
        .count_o(e6_forward_count3_w)
    );
    always @(posedge clk_i) begin
        e6_forward_hit3_r <= e6_forward_hit3_w;
        e6_forward_count3_r <= e6_forward_count3_w;
    end
    wire [6:0] e7_forward_count_w;
    assign e7_forward_count_w = e6_forward_hit0_r
        ? {2'b00, e6_forward_count0_r}
        : e6_forward_hit1_r ? {2'b01, e6_forward_count1_r}
        : e6_forward_hit2_r ? {2'b10, e6_forward_count2_r}
        : e6_forward_hit3_r ? {2'b11, e6_forward_count3_r} : 7'd77;
    wire e6_reverse_hit0_w;
    wire [4:0] e6_reverse_count0_w;
    reg e6_reverse_hit0_r;
    reg [4:0] e6_reverse_count0_r;
    edrv32_cpu2_fpu_lza32 u_reverse_group0 (
        .data_i(e6_reverse_padded_w[127:96]),
        .hit_o(e6_reverse_hit0_w),
        .count_o(e6_reverse_count0_w)
    );
    always @(posedge clk_i) begin
        e6_reverse_hit0_r <= e6_reverse_hit0_w;
        e6_reverse_count0_r <= e6_reverse_count0_w;
    end
    wire e6_reverse_hit1_w;
    wire [4:0] e6_reverse_count1_w;
    reg e6_reverse_hit1_r;
    reg [4:0] e6_reverse_count1_r;
    edrv32_cpu2_fpu_lza32 u_reverse_group1 (
        .data_i(e6_reverse_padded_w[95:64]),
        .hit_o(e6_reverse_hit1_w),
        .count_o(e6_reverse_count1_w)
    );
    always @(posedge clk_i) begin
        e6_reverse_hit1_r <= e6_reverse_hit1_w;
        e6_reverse_count1_r <= e6_reverse_count1_w;
    end
    wire e6_reverse_hit2_w;
    wire [4:0] e6_reverse_count2_w;
    reg e6_reverse_hit2_r;
    reg [4:0] e6_reverse_count2_r;
    edrv32_cpu2_fpu_lza32 u_reverse_group2 (
        .data_i(e6_reverse_padded_w[63:32]),
        .hit_o(e6_reverse_hit2_w),
        .count_o(e6_reverse_count2_w)
    );
    always @(posedge clk_i) begin
        e6_reverse_hit2_r <= e6_reverse_hit2_w;
        e6_reverse_count2_r <= e6_reverse_count2_w;
    end
    wire e6_reverse_hit3_w;
    wire [4:0] e6_reverse_count3_w;
    reg e6_reverse_hit3_r;
    reg [4:0] e6_reverse_count3_r;
    edrv32_cpu2_fpu_lza32 u_reverse_group3 (
        .data_i(e6_reverse_padded_w[31:0]),
        .hit_o(e6_reverse_hit3_w),
        .count_o(e6_reverse_count3_w)
    );
    always @(posedge clk_i) begin
        e6_reverse_hit3_r <= e6_reverse_hit3_w;
        e6_reverse_count3_r <= e6_reverse_count3_w;
    end
    wire [6:0] e7_reverse_count_w;
    assign e7_reverse_count_w = e6_reverse_hit0_r
        ? {2'b00, e6_reverse_count0_r}
        : e6_reverse_hit1_r ? {2'b01, e6_reverse_count1_r}
        : e6_reverse_hit2_r ? {2'b10, e6_reverse_count2_r}
        : e6_reverse_hit3_r ? {2'b11, e6_reverse_count3_r} : 7'd77;
    reg [76:0] e6_forward_r;
    reg [76:0] e6_reverse_r;
    reg e6_reverse_select_r;
    reg e6_product_sign_r;
    reg e6_c_sign_r;
    reg signed [9:0] e6_top_exp_r;
    always @(posedge clk_i) begin
        e6_forward_r <= e6_forward_w[76:0];
        e6_reverse_r <= e6_reverse_w;
        e6_reverse_select_r <= e6_subtract_w && !e6_forward_w[77];
        e6_product_sign_r <= e5_product_sign_r;
        e6_c_sign_r <= e5_c_sign_r;
        e6_top_exp_r <= e5_base_exp_r + 10'sd28;
    end
    reg [8:0] e6_bias_minus_r;
    reg [8:0] e7_bias_minus_r;
    always @(posedge clk_i) begin
        e6_bias_minus_r <= e5_base_exp_r[8:0] + 9'd154;
        e7_bias_minus_r <= e6_tiny_right_r ? 9'd0
            : e6_bias_minus_r - {2'b0, e7_count_w};
    end
    reg [8:0] e6_bias_base_r;
    reg [8:0] e7_bias_base_r;
    always @(posedge clk_i) begin
        e6_bias_base_r <= e5_base_exp_r[8:0] + 9'd155;
        e7_bias_base_r <= e6_tiny_right_r ? 9'd1
            : e6_bias_base_r - {2'b0, e7_count_w};
    end
    reg [8:0] e6_bias_plus_r;
    reg [8:0] e7_bias_plus_r;
    always @(posedge clk_i) begin
        e6_bias_plus_r <= e5_base_exp_r[8:0] + 9'd156;
        e7_bias_plus_r <= e6_tiny_right_r ? 9'd2
            : e6_bias_plus_r - {2'b0, e7_count_w};
    end
    reg [8:0] e6_bias_plus2_r;
    reg [8:0] e7_bias_plus2_r;
    always @(posedge clk_i) begin
        e6_bias_plus2_r <= e5_base_exp_r[8:0] + 9'd157;
        e7_bias_plus2_r <= e6_tiny_right_r ? 9'd3
            : e6_bias_plus2_r - {2'b0, e7_count_w};
    end
    wire [76:0] e7_magnitude_w;
    wire [6:0] e7_count_w;
    wire signed [9:0] e7_predicted_exp_w;
    wire e7_right_w;
    wire [6:0] e7_shift_w;
    assign e7_magnitude_w = e6_reverse_select_r ? e6_reverse_r : e6_forward_r;
    assign e7_count_w = e6_reverse_select_r ? e7_reverse_count_w : e7_forward_count_w;
    assign e7_predicted_exp_w = e6_top_exp_r - $signed({3'b0, e7_count_w});
    assign e7_right_w = e6_tiny_right_r;
    assign e7_shift_w = e6_tiny_right_r ? e6_tiny_shift_r : e7_count_w;
    wire [77:0] e7_extended_w;
    assign e7_extended_w = {1'b0, e7_magnitude_w};
    wire [77:0] e7_shift6_w;
    assign e7_shift6_w = !e7_shift_w[6] ? {1'b0, e7_magnitude_w}
        : e7_right_w ? {64'b0, e7_extended_w[77:65], |e7_extended_w[64:0]}
        : ({1'b0, e7_magnitude_w} << 64);
    wire [77:0] e7_shift5_w;
    assign e7_shift5_w = !e7_shift_w[5] ? e7_shift6_w
        : e7_right_w ? {32'b0, e7_shift6_w[77:33], |e7_shift6_w[32:0]}
        : (e7_shift6_w << 32);
    wire [77:0] e7_shift4_w;
    assign e7_shift4_w = !e7_shift_w[4] ? e7_shift5_w
        : e7_right_w ? {16'b0, e7_shift5_w[77:17], |e7_shift5_w[16:0]}
        : (e7_shift5_w << 16);
    wire [77:0] e7_shift3_w;
    assign e7_shift3_w = !e7_shift_w[3] ? e7_shift4_w
        : e7_right_w ? {8'b0, e7_shift4_w[77:9], |e7_shift4_w[8:0]}
        : (e7_shift4_w << 8);
    reg [77:0] e7_magnitude_r;
    reg [2:0] e7_shift_r;
    reg e7_right_r;
    reg e7_floor_r;
    reg e7_sign_r;
    reg e7_zero_sign_r;
    always @(posedge clk_i) begin
        e7_magnitude_r <= e7_shift3_w;
        e7_shift_r <= e7_shift_w[2:0];
        e7_right_r <= e7_right_w;
        e7_floor_r <= e7_predicted_exp_w <= -10'sd126;
        e7_sign_r <= e6_reverse_select_r ? e6_c_sign_r : e6_product_sign_r;
        e7_zero_sign_r <= (e6_product_sign_r == e6_c_sign_r)
            ? e6_product_sign_r : e6_rm_r == 3'b010;
    end
    reg [2:0] e6_rm_r;
    reg e6_special_r;
    reg [31:0] e6_special_result_r;
    reg [4:0] e6_special_flags_r;
    always @(posedge clk_i) begin
        e6_rm_r <= e5_rm_r;
        e6_special_r <= e5_special_r;
        e6_special_result_r <= e5_special_result_r;
        e6_special_flags_r <= e5_special_flags_r;
    end
    reg [2:0] e7_rm_r;
    reg e7_special_r;
    reg [31:0] e7_special_result_r;
    reg [4:0] e7_special_flags_r;
    always @(posedge clk_i) begin
        e7_rm_r <= e6_rm_r;
        e7_special_r <= e6_special_r;
        e7_special_result_r <= e6_special_result_r;
        e7_special_flags_r <= e6_special_flags_r;
    end
    wire [77:0] e8_shift2_w;
    assign e8_shift2_w = !e7_shift_r[2] ? e7_magnitude_r
        : e7_right_r ? {4'b0, e7_magnitude_r[77:5], |e7_magnitude_r[4:0]}
        : (e7_magnitude_r << 4);
    wire [77:0] e8_shift1_w;
    assign e8_shift1_w = !e7_shift_r[1] ? e8_shift2_w
        : e7_right_r ? {2'b0, e8_shift2_w[77:3], |e8_shift2_w[2:0]}
        : (e8_shift2_w << 2);
    wire [77:0] e8_shift0_w;
    assign e8_shift0_w = !e7_shift_r[0] ? e8_shift1_w
        : e7_right_r ? {1'b0, e8_shift1_w[77:2], |e8_shift1_w[1:0]}
        : (e8_shift1_w << 1);
    reg [76:0] e8_normal_w;
    wire e8_correct_up_w;
    wire e8_correct_down_w;
    wire [8:0] e8_bias_w;
    reg e8_increment_w;
    wire e8_inexact_w;
    wire [24:0] e8_rounded_w;
    wire e8_overflow_w;
    wire e8_overflow_inf_w;
    wire [7:0] e8_exp_field_w;
    wire [22:0] e8_fraction_w;
    wire [31:0] e8_result_w;
    wire [4:0] e8_flags_w;
    assign e8_correct_up_w = e8_shift0_w[77];
    assign e8_correct_down_w = !e8_shift0_w[76] && !e7_floor_r;
    // Biased exponent candidates were prepared alongside the coarse shift.
    // No exponent increment follows the final significand carry chain.
    assign e8_bias_w = e8_correct_up_w
        ? (e8_rounded_w[24] ? e7_bias_plus2_r : e7_bias_plus_r)
        : e8_correct_down_w ? (e8_rounded_w[24] ? e7_bias_base_r : e7_bias_minus_r)
        : (e8_rounded_w[24] ? e7_bias_plus_r : e7_bias_base_r);
    // Anticipator correction is at most one bit and is separate from the carry.
    always @(*) begin
        e8_normal_w = e8_shift0_w[76:0];
        if (e8_shift0_w[77]) begin
            e8_normal_w = {e8_shift0_w[77:2], |e8_shift0_w[1:0]};
        end else if (e8_correct_down_w) begin
            e8_normal_w = {e8_shift0_w[75:0], 1'b0};
        end
    end
    assign e8_inexact_w = |e8_normal_w[52:0];
    always @(*) begin
        e8_increment_w = 1'b0;
        case (e7_rm_r)
            3'b000: e8_increment_w = e8_normal_w[52]
                && ((|e8_normal_w[51:0]) || e8_normal_w[53]);
            3'b001: e8_increment_w = 1'b0;
            3'b010: e8_increment_w = e7_sign_r && e8_inexact_w;
            3'b011: e8_increment_w = !e7_sign_r && e8_inexact_w;
            3'b100: e8_increment_w = e8_normal_w[52];
            default: e8_increment_w = 1'b0;
        endcase
    end
    assign e8_rounded_w = {1'b0, e8_normal_w[76:53]} + {24'b0, e8_increment_w};
    assign e8_overflow_w = e8_bias_w > 9'd254;
    assign e8_overflow_inf_w = (e7_rm_r == 3'b000) || (e7_rm_r == 3'b100)
        || ((e7_rm_r == 3'b010) && e7_sign_r)
        || ((e7_rm_r == 3'b011) && !e7_sign_r);
    assign e8_exp_field_w = !e8_rounded_w[24] && !e8_rounded_w[23]
        ? 8'b0 : e8_bias_w[7:0];
    assign e8_fraction_w = e8_rounded_w[24] ? e8_rounded_w[23:1] : e8_rounded_w[22:0];
    assign e8_result_w = e8_overflow_w
        ? {e7_sign_r, e8_overflow_inf_w ? 31'h7f800000 : 31'h7f7fffff}
        : {!(|e8_rounded_w) && !e8_inexact_w ? e7_zero_sign_r : e7_sign_r,
            e8_exp_field_w, e8_fraction_w};
    assign e8_flags_w = {2'b00, e8_overflow_w,
        e8_inexact_w && !e8_overflow_w
            && !e8_rounded_w[24] && !e8_rounded_w[23], e8_inexact_w || e8_overflow_w};
    always @(posedge clk_i) begin
        result_o <= e7_special_r ? e7_special_result_r : e8_result_w;
        flags_o <= e7_special_r ? e7_special_flags_r : e8_flags_w;
    end
endmodule
