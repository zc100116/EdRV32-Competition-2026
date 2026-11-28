// File: edrv32_gpu2_fp32_add.v
// Spec: gpu-v2-spec 2.4, staged DP3/DP4.
// Description: Four-edge independent FP32 RNE adder; no multiplier or fused dot.
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
    assign a_big_w = a_i[30:0] >= b_i[30:0];
    assign big_w = a_big_w ? a_i : b_i;
    assign small_w = a_big_w ? b_i[30:0] : a_i[30:0];
    assign big_exp_w = big_w[30:23] == 0 ? 8'd1 : big_w[30:23];
    assign small_exp_w = small_w[30:23] == 0 ? 8'd1 : small_w[30:23];
    assign delta_w = big_exp_w - small_exp_w;
    assign shift_w = delta_w > 8'd27 ? 5'd27 : delta_w[4:0];
    assign small_mantissa_w = {|small_w[30:23], small_w[22:0], 3'b0};
    reg [26:0] s1_big_r;
    reg [26:0] s1_small_r;
    (* keep = "true", syn_preserve = 1 *) reg [19:0] s1_shift_r;
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
        s1_small_r <= small_mantissa_w;
        s1_shift_r <= {4{shift_w}};
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
    wire [26:0] aligned_w;
    wire [26:0] aligned_stage_w [0:5];
    assign aligned_stage_w[0] = s1_small_r;
    genvar stage;
    genvar bit_idx;
    generate
        for (stage = 0; stage < 5; stage = stage+1) begin : g_align
            localparam STEP = 1 << stage;
            for (bit_idx = 0; bit_idx < 27; bit_idx = bit_idx+1) begin : g_bit
                localparam CONTROL = (bit_idx/7)*5 + stage;
                if (bit_idx == 0) begin : g_jam
                    assign aligned_stage_w[stage+1][bit_idx] = s1_shift_r[CONTROL]
                        ? (|aligned_stage_w[stage][STEP:0]) : aligned_stage_w[stage][0];
                end else if (bit_idx+STEP < 27) begin : g_data
                    assign aligned_stage_w[stage+1][bit_idx] = s1_shift_r[CONTROL]
                        ? aligned_stage_w[stage][bit_idx+STEP] : aligned_stage_w[stage][bit_idx];
                end else begin : g_zero
                    assign aligned_stage_w[stage+1][bit_idx] = !s1_shift_r[CONTROL]
                        && aligned_stage_w[stage][bit_idx];
                end
            end
        end
    endgenerate
    assign aligned_w = aligned_stage_w[5];
    // Move the barrel shifter into the measured +2.701 ns carry-chain segment.
    always @(posedge clk_i) begin
        s2_sum_r <= s1_opposite_r ? {1'b0, s1_big_r} - {1'b0, aligned_w}
            : {1'b0, s1_big_r} + {1'b0, aligned_w};
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
    reg [27:0] s3_partial_r;
    reg [2:0] s3_low_shift_r;
    reg [8:0] s3_exp_r;
    reg s3_sign_r;
    reg s3_zero_r;
    reg s3_opposite_r;
    reg s3_special_r;
    reg [31:0] s3_special_data_r;
    wire [24:0] s3_rounded_w;
    wire [8:0] s3_exp_w;
    wire [8:0] s3_rounded_exp_w;
    assign s3_shift_w = {1'b0, s3_lz_w} > s2_exp_r ? s2_exp_r[4:0] : s3_lz_w[4:0];
    // E3 normalizes by multiples of eight; E4 finishes the three low shifts and RNE.
    always @(posedge clk_i) begin
        s3_partial_r <= s2_sum_r << {s3_shift_w[4:3], 3'b0};
        s3_low_shift_r <= s3_shift_w[2:0];
        s3_exp_r <= {1'b0, s2_exp_r} + 9'd1 - {4'b0, s3_shift_w};
        s3_sign_r <= s2_sign_r;
        s3_zero_r <= !(|s2_sum_r);
        s3_opposite_r <= s2_opposite_r;
        s3_special_r <= s2_special_r;
        s3_special_data_r <= s2_special_data_r;
    end
    assign s3_shifted_w = s3_partial_r << s3_low_shift_r;
    assign s3_rounded_w = {1'b0, s3_shifted_w[27:4]}
        + {24'b0, s3_shifted_w[3] && (s3_shifted_w[4] || (|s3_shifted_w[2:0]))};
    assign s3_exp_w = s3_exp_r;
    assign s3_rounded_exp_w = s3_exp_w + {8'b0, s3_rounded_w[24]};
    assign rounded_o = s3_special_r ? s3_special_data_r
            : s3_zero_r ? {s3_sign_r && !s3_opposite_r, 31'b0}
            : s3_rounded_exp_w >= 9'd255 ? {s3_sign_r, 8'hff, 23'b0}
            : {s3_sign_r, s3_rounded_w[23] || s3_rounded_w[24]
                ? s3_rounded_exp_w[7:0] : 8'b0,
                s3_rounded_w[24] ? s3_rounded_w[23:1] : s3_rounded_w[22:0]};
    always @(posedge clk_i) begin
        result_o <= rounded_o;
    end
endmodule
