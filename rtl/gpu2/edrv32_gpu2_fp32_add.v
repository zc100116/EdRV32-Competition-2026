// File: edrv32_gpu2_fp32_add.v
// Spec: gpu-v2-spec 2.4, staged DP3/DP4.
// Description: Three-edge independent FP32 RNE adder; no multiplier or fused dot.
// Clock domain: clk_gpu. Free-running data; caller owns validity.
module edrv32_gpu2_fp32_add (
    // Clock and operands.
    input wire clk_i,
    input wire [31:0] a_i,
    input wire [31:0] b_i,

    // Rounded result, including gradual underflow and IEEE development specials.
    output wire [31:0] rounded_o,
    output reg [31:0] result_o
);
    wire a_big_w;
    wire [31:0] big_w;
    wire [30:0] small_w;
    wire [7:0] big_exp_w;
    wire [7:0] small_exp_w;
    wire [7:0] delta_w;
    wire [4:0] shift_w;
    wire [26:0] small_mantissa_w;
    wire [26:0] small_shifted_w;
    wire sticky_w;
    assign a_big_w = a_i[30:0] >= b_i[30:0];
    assign big_w = a_big_w ? a_i : b_i;
    assign small_w = a_big_w ? b_i[30:0] : a_i[30:0];
    assign big_exp_w = big_w[30:23] == 0 ? 8'd1 : big_w[30:23];
    assign small_exp_w = small_w[30:23] == 0 ? 8'd1 : small_w[30:23];
    assign delta_w = big_exp_w - small_exp_w;
    assign shift_w = delta_w > 8'd27 ? 5'd27 : delta_w[4:0];
    assign small_mantissa_w = {|small_w[30:23], small_w[22:0], 3'b0};
    assign small_shifted_w = small_mantissa_w >> shift_w;
    assign sticky_w = |(small_mantissa_w & ~(27'h7ffffff << shift_w));
    reg [26:0] s1_big_r;
    reg [26:0] s1_small_r;
    reg s1_opposite_r;
    reg s1_sign_r;
    reg [7:0] s1_exp_r;
    reg s1_special_r;
    reg [31:0] s1_special_data_r;
    wire nan_w;
    assign nan_w = a_i[30:0] > 31'h7f800000 || b_i[30:0] > 31'h7f800000
        || (a_i[30:0] == 31'h7f800000 && b_i[30:0] == 31'h7f800000
            && a_i[31] != b_i[31]);
    always @(posedge clk_i) begin
        s1_big_r <= {|big_w[30:23], big_w[22:0], 3'b0};
        s1_small_r <= {small_shifted_w[26:1], small_shifted_w[0] | sticky_w};
        s1_opposite_r <= a_i[31] != b_i[31];
        s1_sign_r <= big_w[31];
        s1_exp_r <= big_exp_w;
        s1_special_r <= nan_w || (&a_i[30:23]) || (&b_i[30:23]);
        s1_special_data_r <= nan_w ? 32'h7fc00000 : big_w;
    end
    reg [27:0] s2_sum_r;
    reg [7:0] s2_exp_r;
    reg s2_sign_r;
    reg s2_opposite_r;
    reg s2_special_r;
    reg [31:0] s2_special_data_r;
    always @(posedge clk_i) begin
        s2_sum_r <= s1_opposite_r ? {1'b0, s1_big_r} - {1'b0, s1_small_r}
            : {1'b0, s1_big_r} + {1'b0, s1_small_r};
        s2_exp_r <= s1_exp_r;
        s2_sign_r <= s1_sign_r;
        s2_opposite_r <= s1_opposite_r;
        s2_special_r <= s1_special_r;
        s2_special_data_r <= s1_special_data_r;
    end
    wire [6:0] s3_lz_w;
    edrv32_gpu2_fp32_lz77 u_lz_sum (
        .data_i({s2_sum_r, 49'b0}),
        .count_o(s3_lz_w)
    );
    wire [4:0] s3_shift_w;
    wire [27:0] s3_shifted_w;
    wire [24:0] s3_rounded_w;
    wire [8:0] s3_exp_w;
    wire [8:0] s3_rounded_exp_w;
    assign s3_shift_w = {1'b0, s3_lz_w} > s2_exp_r ? s2_exp_r[4:0] : s3_lz_w[4:0];
    assign s3_shifted_w = s2_sum_r << s3_shift_w;
    assign s3_rounded_w = {1'b0, s3_shifted_w[27:4]}
        + {24'b0, s3_shifted_w[3] && (s3_shifted_w[4] || (|s3_shifted_w[2:0]))};
    assign s3_exp_w = {1'b0, s2_exp_r} + 9'd1 - {4'b0, s3_shift_w};
    assign s3_rounded_exp_w = s3_exp_w + {8'b0, s3_rounded_w[24]};
    assign rounded_o = s2_special_r ? s2_special_data_r
            : !(|s2_sum_r) ? {s2_sign_r && !s2_opposite_r, 31'b0}
            : s3_rounded_exp_w >= 9'd255 ? {s2_sign_r, 8'hff, 23'b0}
            : {s2_sign_r, s3_rounded_w[23] || s3_rounded_w[24]
                ? s3_rounded_exp_w[7:0] : 8'b0,
                s3_rounded_w[24] ? s3_rounded_w[23:1] : s3_rounded_w[22:0]};
    always @(posedge clk_i) begin
        result_o <= rounded_o;
    end
endmodule
