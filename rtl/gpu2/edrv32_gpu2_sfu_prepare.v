// File: edrv32_gpu2_sfu_prepare.v
// Spec: gpu-v2-spec 2.4; M-6 small-table centers and exact residuals.
// Description: Five-stage numerical front end; two edges separate normalization from table indexing.
// Clock domain: clk_gpu. Caller pairs fields with the synchronous ROM responses.
module edrv32_gpu2_sfu_prepare (
    // Free-running clock and scalar request.
    input wire clk_i,
    input wire [1:0] op_i,
    input wire [31:0] x_i,

    // Two-edge index for the first synchronous ROM read.
    output wire [5:0] index_o,

    // Five-edge fields: field0 is RCP/RSQ operand or LOG exponent; field3 is LOG/EXP residual.
    // EXP field0 and RCP/RSQ field3 are unused. op 0 RCP, 1 RSQ, 2 LOG2, 3 EXP2.
    output reg [31:0] field0_o,
    output reg [31:0] field3_o,
    output reg signed [9:0] scale_o,
    output reg sign_o,
    output reg exp_fma_o,
    output reg special_o,
    output reg [31:0] special_data_o
);
    wire [23:0] mantissa_w;
    wire [6:0] lz_w;
    wire [23:0] normalized_w;
    wire signed [9:0] exponent_w;
    assign mantissa_w = {|x_i[30:23], x_i[22:0]};
    edrv32_gpu2_fp32_lz24 u_lz_input (
        .data_i(mantissa_w),
        .count_o(lz_w)
    );
    // Card112 request -> ROM was 14 levels: isolate LZ, normalization and indexing.
    reg [23:0] input_mantissa_r;
    reg [6:0] input_lz_r;
    reg signed [9:0] input_exponent_r;
    reg [31:0] input_x_r;
    reg [1:0] input_op_r;
    reg [23:0] normalized_r;
    reg signed [9:0] exponent_r;
    reg [31:0] normalized_x_r;
    reg normalized_exp_small_r;
    reg [23:0] normalized_exp_mask_r;
    reg [15:0] normalized_exp_magnitude_r;
    reg normalized_exp_correction_r;
    wire [23:0] input_exp_mask_w;
    wire [23:0] unused_input_exp_shifted_w;
    wire input_exp_small_w;
    wire signed [9:0] input_normal_exponent_w;
    wire [4:0] input_exp_shift_w;
    assign input_exp_small_w = input_exponent_r < -10'sd6;
    assign input_exp_mask_w = ~(24'hffffff << input_exp_shift_w);
    assign unused_input_exp_shifted_w = input_mantissa_r >> input_exp_shift_w;
    assign input_normal_exponent_w = input_exponent_r - $signed({3'b0, input_lz_r});
    // Every subnormal is below 2^-6, so EXP indexing never needs its normalized exponent.
    assign input_exp_shift_w = input_exp_small_w
        || input_exponent_r > 10'sd7 ? 5'b0 : 5'd17 - input_exponent_r[4:0];
    reg [1:0] normalized_op_r;
    always @(posedge clk_i) begin
        input_mantissa_r <= mantissa_w;
        input_lz_r <= lz_w;
        input_exponent_r <= x_i[30:23] == 0 ? -10'sd126
            : $signed({2'b0, x_i[30:23]}) - 10'sd127;
        input_x_r <= x_i;
        input_op_r <= op_i;
        normalized_r <= input_mantissa_r << input_lz_r[4:0];
        exponent_r <= input_normal_exponent_w;
        normalized_exp_small_r <= input_exp_small_w;
        normalized_exp_mask_r <= input_exp_mask_w;
        normalized_exp_magnitude_r <= input_exp_small_w ? 16'b0 : unused_input_exp_shifted_w[15:0];
        normalized_exp_correction_r <= (|(input_mantissa_r & input_exp_mask_w))
            || (input_exp_small_w && (|input_x_r[30:0]));
        normalized_x_r <= input_x_r;
        normalized_op_r <= input_op_r;
    end
    assign normalized_w = normalized_r;
    assign exponent_w = exponent_r;
    wire [7:0] rsq_numerator_w;
    wire [7:0] unused_rsq_index_w;
    assign rsq_numerator_w = (exponent_w[0] ? normalized_w[23:16]
        : {1'b0, normalized_w[23:17]}) - 8'd64;
    assign unused_rsq_index_w = rsq_numerator_w / 8'd3;
    wire log_high_w;
    wire [24:0] log_fixed_w;
    wire [23:0] log_distance_w;
    wire [5:0] log_index_w;
    wire [24:0] log_center_w;
    wire signed [24:0] log_delta_w;
    wire signed [9:0] log_exponent_w;
    assign log_high_w = normalized_w >= 24'hc00000;
    assign log_fixed_w = log_high_w ? {1'b0, normalized_w} : {normalized_w, 1'b0};
    assign log_distance_w = log_fixed_w[23:0] - 24'hc00000;
    assign log_index_w = log_distance_w[23:18] + {5'b0, log_distance_w[17]
        && (log_distance_w[18] || (|log_distance_w[16:0]))};
    assign log_center_w = 25'h0c00000 + {1'b0, log_index_w[5:0], 18'b0};
    assign log_delta_w = $signed(log_fixed_w) - $signed(log_center_w);
    assign log_exponent_w = exponent_w + $signed({9'b0, log_high_w});
    wire exp_small_w;
    wire [23:0] exp_remainder_w;
    wire [15:0] exp_magnitude_fixed_w;
    wire signed [15:0] exp_fixed_w;
    wire [23:0] exp_residual_w;
    assign exp_small_w = normalized_exp_small_r;
    assign exp_remainder_w = normalized_w & normalized_exp_mask_r;
    assign exp_magnitude_fixed_w = normalized_exp_magnitude_r;
    assign exp_fixed_w = normalized_x_r[31] ? $signed(~exp_magnitude_fixed_w)
        + $signed({15'b0, !normalized_exp_correction_r}) : $signed(exp_magnitude_fixed_w);
    assign exp_residual_w = normalized_x_r[31] && exp_remainder_w != 0
        ? (-exp_remainder_w & normalized_exp_mask_r) : exp_remainder_w;
    assign index_o = normalized_op_r == 2'd0 ? normalized_w[22:17]
        : normalized_op_r == 2'd1 ? unused_rsq_index_w[5:0]
        : normalized_op_r == 2'd2 ? log_index_w[5:0] : exp_fixed_w[5:0];
    reg [1:0] s1_op_r;
    reg [31:0] s1_norm_r;
    reg [31:0] s1_x_r;
    reg s1_small_r;
    reg [23:0] s1_delta_r;
    reg s1_delta_sign_r;
    reg signed [7:0] s1_delta_exp_r;
    reg signed [9:0] s1_log_exp_r;
    reg signed [9:0] scale_r [0:1];
    reg sign_r [0:1];
    reg exp_fma_r [0:1];
    reg special_r [0:1];
    reg [31:0] special_data_r [0:1];
    wire nan_w;
    wire zero_w;
    wire inf_w;
    wire special_w;
    reg [31:0] special_data_w;
    assign nan_w = normalized_x_r[30:0] > 31'h7f800000;
    assign zero_w = normalized_x_r[30:0] == 0;
    assign inf_w = normalized_x_r[30:0] == 31'h7f800000;
    assign special_w = nan_w || inf_w || ((normalized_op_r != 2'd3) && zero_w)
        || ((normalized_op_r == 2'd1 || normalized_op_r == 2'd2) && normalized_x_r[31])
        || (normalized_op_r == 2'd3 && (normalized_x_r[31] ? normalized_x_r[30:0] >= 31'h43160000
            : normalized_x_r[30:0] >= 31'h43000000));
    always @(*) begin
        special_data_w = 32'h7fc00000;
        if (!nan_w) begin
            case (normalized_op_r)
                2'd0: special_data_w = {normalized_x_r[31], zero_w ? 8'hff : 8'b0, 23'b0};
                2'd1: special_data_w = zero_w ? 32'h7f800000 : normalized_x_r[31]
                    ? 32'h7fc00000 : 32'b0;
                2'd2: special_data_w = zero_w ? 32'hff800000 : normalized_x_r[31]
                    ? 32'h7fc00000 : 32'h7f800000;
                2'd3: special_data_w = normalized_x_r[31] ? 32'b0 : 32'h7f800000;
                default: special_data_w = 32'h7fc00000;
            endcase
        end
    end
    always @(posedge clk_i) begin
        s1_op_r <= normalized_op_r;
        s1_norm_r <= normalized_op_r == 2'd0 ? {1'b1, 8'd127, normalized_w[22:0]}
            : {1'b1, 7'd63, exponent_w[0], normalized_w[22:0]};
        s1_x_r <= normalized_x_r;
        s1_small_r <= exp_small_w;
        s1_delta_r <= normalized_op_r == 2'd2 ? (log_delta_w[24]
            ? -log_delta_w[23:0] : log_delta_w[23:0]) : exp_residual_w;
        s1_delta_sign_r <= normalized_op_r == 2'd2 && log_delta_w[24];
        s1_delta_exp_r <= normalized_op_r == 2'd2 ? -8'sd24 : exponent_w[7:0] - 8'd23;
        s1_log_exp_r <= log_exponent_w;
        scale_r[0] <= normalized_op_r == 2'd0 ? -exponent_w
            : normalized_op_r == 2'd1 ? -($signed({exponent_w[9:1], 1'b0}) >>> 1)
            : normalized_op_r == 2'd3 ? $signed(exp_fixed_w[15:6]) : 10'sd0;
        sign_r[0] <= normalized_op_r == 2'd0 && normalized_x_r[31];
        exp_fma_r[0] <= normalized_op_r == 2'd3 && exp_small_w && normalized_x_r[31] && !zero_w;
        special_r[0] <= special_w;
        special_data_r[0] <= special_data_w;
        scale_r[1] <= scale_r[0];
        sign_r[1] <= sign_r[0];
        exp_fma_r[1] <= exp_fma_r[0];
        special_r[1] <= special_r[0];
        special_data_r[1] <= special_data_r[0];
        scale_o <= scale_r[1];
        sign_o <= sign_r[1];
        exp_fma_o <= exp_fma_r[1];
        special_o <= special_r[1];
        special_data_o <= special_data_r[1];
    end
    wire [31:0] delta_fp_w;
    wire [31:0] exponent_fp_w;
    edrv32_gpu2_sfu_integer u_delta (
        .sign_i(s1_delta_sign_r),
        .magnitude_i(s1_delta_r),
        .exponent_i(s1_delta_exp_r),
        .data_o(delta_fp_w)
    );
    edrv32_gpu2_sfu_integer u_exponent (
        .sign_i(s1_log_exp_r[9]),
        .magnitude_i({14'b0, s1_log_exp_r[9] ? -s1_log_exp_r : s1_log_exp_r}),
        .exponent_i(8'sd0),
        .data_o(exponent_fp_w)
    );
    reg [31:0] s2_field0_r;
    reg [31:0] s2_field3_r;
    always @(posedge clk_i) begin
        s2_field0_r <= s1_op_r == 2'd2 ? exponent_fp_w : s1_norm_r;
        s2_field3_r <= s1_op_r == 2'd3 && s1_small_r ? s1_x_r : delta_fp_w;
        field0_o <= s2_field0_r;
        field3_o <= s2_field3_r;
    end
endmodule
