// File: edrv32_gpu_project_recip.v
// Spec: gpu-spec 2.12; GPU microarchitecture 4.3, 4.10.
// Description: Q30 normalized reciprocal_r, midpoint seed and one Newton iteration.
//              Twenty-four enabled pipeline stages; preserve the normalization exponent_r.
// Clock domain: clk_gpu.
module edrv32_gpu_project_recip (
    // Clock and reset.
    input wire clk_i,
    input wire rst_n_i,

    // Positive unsigned input and pipeline clock enable.
    input wire enable_i,
    input wire stop_i,
    input wire value_valid_i,
    input wire [39:0] value_i,

    // Normalized reciprocal_r and original leading-one exponent_r.
    output wire value_valid_o,
    output wire [30:0] reciprocal_o,
    output wire [5:0] exponent_o
);
    reg [39:0] input_value_r;
    reg [1:0] leading_group0_r;
    reg [1:0] leading_group1_r;
    reg [1:0] leading_group2_r;
    reg [1:0] leading_group3_r;
    reg [1:0] leading_group4_r;
    reg [1:0] leading_group5_r;
    reg [1:0] leading_group6_r;
    reg [1:0] leading_group7_r;
    reg [1:0] leading_group8_r;
    reg [1:0] leading_group9_r;
    reg [9:0] leading_nonzero_r;
    reg [5:0] leading_partial0_r;
    reg [5:0] leading_partial1_r;
    reg [5:0] leading_partial2_r;
    reg [9:0] leading_nonzero_d2_r;
    reg [5:0] exponent_r;
    reg [5:0] right_amount_r;
    reg [5:0] left_amount_r;
    wire [1:0] normalize_right_amt0_w;
    reg [39:0] normalize_right_0_w;
    reg [39:0] input_value_r_d1_r;
    reg [39:0] input_value_r_d2_r;
    reg [39:0] input_value_r_d3_r;
    reg [39:0] input_value_r_d4_r;
    reg [39:0] normalize_right_0_r;
    wire [1:0] normalize_right_amt1_w;
    reg [39:0] normalize_right_1_w;
    reg [1:0] normalize_right_amt1_w_d5_r;
    reg [39:0] normalize_right_1_r;
    wire [1:0] normalize_right_amt2_w;
    reg [39:0] unused_normalize_right_2_w;
    reg [1:0] normalize_right_amt2_w_d5_r;
    reg [1:0] normalize_right_amt2_w_d6_r;
    reg [30:0] unused_normalize_right_2_r;
    wire [1:0] normalize_left_amt0_w;
    reg [39:0] normalize_left_0_w;
    reg [39:0] normalize_left_0_r;
    wire [1:0] normalize_left_amt1_w;
    reg [39:0] normalize_left_1_w;
    reg [1:0] normalize_left_amt1_w_d5_r;
    reg [39:0] normalize_left_1_r;
    wire [1:0] normalize_left_amt2_w;
    reg [39:0] unused_normalize_left_2_w;
    reg [1:0] normalize_left_amt2_w_d5_r;
    reg [1:0] normalize_left_amt2_w_d6_r;
    reg [30:0] unused_normalize_left_2_r;
    reg [5:0] exponent_d4_r;
    reg [5:0] exponent_d5_r;
    reg [5:0] exponent_d6_r;
    reg [5:0] exponent_d7_r;
    reg [30:0] mantissa_r;
    wire [29:0] seed_data_w;
    reg [29:0] seed_output_r;
    reg [30:0] mantissa_d9_r;

    wire [60:0] unused_newton_product_p2_r;
    wire [31:0] newton_high_w;
    wire [31:0] newton_bit_w;
    reg [31:0] newton_round_r;

    reg [29:0] seed_output_r_d11_r;
    reg [29:0] seed_output_r_d12_r;
    reg [29:0] seed_output_r_d13_r;
    reg [29:0] seed_output_r_d14_r;
    reg [29:0] seed_output_r_d15_r;

    wire [61:0] unused_newton_result_p2_r;
    reg [30:0] reciprocal_r;
    reg [5:0] exponent_d8_r;
    reg [5:0] exponent_d9_r;
    reg [5:0] exponent_d10_r;
    reg [5:0] exponent_d11_r;
    reg [5:0] exponent_d12_r;
    reg [5:0] exponent_d13_r;
    reg [5:0] exponent_d14_r;
    reg [5:0] exponent_d15_r;
    reg [5:0] exponent_d16_r;
    reg [5:0] exponent_d17_r;
    reg [5:0] exponent_d18_r;
    reg [5:0] exponent_d19_r;
    reg [23:0] valid_r;
    assign value_valid_o = valid_r[23];
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) valid_r <= 0;
        else if (stop_i) valid_r <= 0;
        else if (enable_i) valid_r <= {valid_r[22:0], value_valid_i};
    end
    assign normalize_right_amt0_w = right_amount_r[0 +: 2];
    always @(*) begin
        normalize_right_0_w = input_value_r_d4_r;
        case (normalize_right_amt0_w)
            2'd0: normalize_right_0_w = input_value_r_d4_r >> 0;
            2'd1: normalize_right_0_w = input_value_r_d4_r >> 1;
            2'd2: normalize_right_0_w = input_value_r_d4_r >> 2;
            2'd3: normalize_right_0_w = input_value_r_d4_r >> 3;
            default: normalize_right_0_w = input_value_r_d4_r;
        endcase
    end
    assign normalize_right_amt1_w = right_amount_r[2 +: 2];
    always @(*) begin
        normalize_right_1_w = normalize_right_0_r;
        case (normalize_right_amt1_w_d5_r)
            2'd0: normalize_right_1_w = normalize_right_0_r >> 0;
            2'd1: normalize_right_1_w = normalize_right_0_r >> 4;
            2'd2: normalize_right_1_w = normalize_right_0_r >> 8;
            2'd3: normalize_right_1_w = normalize_right_0_r >> 12;
            default: normalize_right_1_w = normalize_right_0_r;
        endcase
    end
    assign normalize_right_amt2_w = right_amount_r[4 +: 2];
    always @(*) begin
        unused_normalize_right_2_w = normalize_right_1_r;
        case (normalize_right_amt2_w_d6_r)
            2'd0: unused_normalize_right_2_w = normalize_right_1_r >> 0;
            2'd1: unused_normalize_right_2_w = normalize_right_1_r >> 16;
            2'd2: unused_normalize_right_2_w = normalize_right_1_r >> 32;
            2'd3: unused_normalize_right_2_w = normalize_right_1_r >> 48;
            default: unused_normalize_right_2_w = normalize_right_1_r;
        endcase
    end
    assign normalize_left_amt0_w = left_amount_r[0 +: 2];
    always @(*) begin
        normalize_left_0_w = input_value_r_d4_r;
        case (normalize_left_amt0_w)
            2'd0: normalize_left_0_w = input_value_r_d4_r << 0;
            2'd1: normalize_left_0_w = input_value_r_d4_r << 1;
            2'd2: normalize_left_0_w = input_value_r_d4_r << 2;
            2'd3: normalize_left_0_w = input_value_r_d4_r << 3;
            default: normalize_left_0_w = input_value_r_d4_r;
        endcase
    end
    assign normalize_left_amt1_w = left_amount_r[2 +: 2];
    always @(*) begin
        normalize_left_1_w = normalize_left_0_r;
        case (normalize_left_amt1_w_d5_r)
            2'd0: normalize_left_1_w = normalize_left_0_r << 0;
            2'd1: normalize_left_1_w = normalize_left_0_r << 4;
            2'd2: normalize_left_1_w = normalize_left_0_r << 8;
            2'd3: normalize_left_1_w = normalize_left_0_r << 12;
            default: normalize_left_1_w = normalize_left_0_r;
        endcase
    end
    assign normalize_left_amt2_w = left_amount_r[4 +: 2];
    always @(*) begin
        unused_normalize_left_2_w = normalize_left_1_r;
        case (normalize_left_amt2_w_d6_r)
            2'd0: unused_normalize_left_2_w = normalize_left_1_r << 0;
            2'd1: unused_normalize_left_2_w = normalize_left_1_r << 16;
            2'd2: unused_normalize_left_2_w = normalize_left_1_r << 32;
            2'd3: unused_normalize_left_2_w = normalize_left_1_r << 48;
            default: unused_normalize_left_2_w = normalize_left_1_r;
        endcase
    end
    edrv32_rom_gpu_recip_q30 u_seed (
        .clk_i(clk_i),
        .en_i(enable_i),
        .addr_i(mantissa_r[29:20]),
        .rd_data_o(seed_data_w)
    );
    assign newton_high_w = {1'b0, unused_newton_product_p2_r[60:30]};
    assign newton_bit_w = {31'b0, unused_newton_product_p2_r[29]};
    assign reciprocal_o = reciprocal_r;
    assign exponent_o = exponent_extra3_r;
    always @(posedge clk_i) begin
        if (enable_i) begin
            input_value_r <= value_i;
            leading_group0_r <=
                input_value_r[3] ? 2'd3 : input_value_r[2] ? 2'd2 : input_value_r[1] ? 2'd1 :
                input_value_r[0] ? 2'd0 : 2'b0;
            leading_group1_r <=
                input_value_r[7] ? 2'd3 : input_value_r[6] ? 2'd2 : input_value_r[5] ? 2'd1 :
                input_value_r[4] ? 2'd0 : 2'b0;
            leading_group2_r <=
                input_value_r[11] ? 2'd3 : input_value_r[10] ? 2'd2 : input_value_r[9] ? 2'd1 :
                input_value_r[8] ? 2'd0 : 2'b0;
            leading_group3_r <=
                input_value_r[15] ? 2'd3 : input_value_r[14] ? 2'd2 : input_value_r[13] ? 2'd1 :
                input_value_r[12] ? 2'd0 : 2'b0;
            leading_group4_r <=
                input_value_r[19] ? 2'd3 : input_value_r[18] ? 2'd2 : input_value_r[17] ? 2'd1 :
                input_value_r[16] ? 2'd0 : 2'b0;
            leading_group5_r <=
                input_value_r[23] ? 2'd3 : input_value_r[22] ? 2'd2 : input_value_r[21] ? 2'd1 :
                input_value_r[20] ? 2'd0 : 2'b0;
            leading_group6_r <=
                input_value_r[27] ? 2'd3 : input_value_r[26] ? 2'd2 : input_value_r[25] ? 2'd1 :
                input_value_r[24] ? 2'd0 : 2'b0;
            leading_group7_r <=
                input_value_r[31] ? 2'd3 : input_value_r[30] ? 2'd2 : input_value_r[29] ? 2'd1 :
                input_value_r[28] ? 2'd0 : 2'b0;
            leading_group8_r <=
                input_value_r[35] ? 2'd3 : input_value_r[34] ? 2'd2 : input_value_r[33] ? 2'd1 :
                input_value_r[32] ? 2'd0 : 2'b0;
            leading_group9_r <=
                input_value_r[39] ? 2'd3 : input_value_r[38] ? 2'd2 : input_value_r[37] ? 2'd1 :
                input_value_r[36] ? 2'd0 : 2'b0;
            leading_nonzero_r <=
                {(|input_value_r[36 +: 4]), (|input_value_r[32 +: 4]), (|input_value_r[28 +: 4]),
                (|input_value_r[24 +: 4]), (|input_value_r[20 +: 4]), (|input_value_r[16 +: 4]),
                (|input_value_r[12 +: 4]), (|input_value_r[8 +: 4]), (|input_value_r[4 +: 4]),
                (|input_value_r[0 +: 4])};
            leading_partial0_r <=
                leading_nonzero_r[3] ? {4'd3, leading_group3_r} : leading_nonzero_r[2] ? {4'd2,
                leading_group2_r} : leading_nonzero_r[1] ? {4'd1, leading_group1_r} :
                leading_nonzero_r[0] ? {4'd0, leading_group0_r} : 6'b0;
            leading_partial1_r <=
                leading_nonzero_r[7] ? {4'd7, leading_group7_r} : leading_nonzero_r[6] ? {4'd6,
                leading_group6_r} : leading_nonzero_r[5] ? {4'd5, leading_group5_r} :
                leading_nonzero_r[4] ? {4'd4, leading_group4_r} : 6'b0;
            leading_partial2_r <=
                leading_nonzero_r[9] ? {4'd9, leading_group9_r} : leading_nonzero_r[8] ? {4'd8,
                leading_group8_r} : 6'b0;
            leading_nonzero_d2_r <= leading_nonzero_r;
            exponent_r <=
                (|leading_nonzero_d2_r[8 +: 2]) ? leading_partial2_r : (|leading_nonzero_d2_r[4 +:
                4]) ? leading_partial1_r : (|leading_nonzero_d2_r[0 +: 4]) ? leading_partial0_r :
                6'b0;
            right_amount_r <= exponent_r >= 30 ? exponent_r - 6'd30 : 6'b0;
            left_amount_r <= exponent_r < 30 ? 6'd30 - exponent_r : 6'b0;
            input_value_r_d1_r <= input_value_r;
            input_value_r_d2_r <= input_value_r_d1_r;
            input_value_r_d3_r <= input_value_r_d2_r;
            input_value_r_d4_r <= input_value_r_d3_r;
            normalize_right_0_r <= normalize_right_0_w;
            normalize_right_amt1_w_d5_r <= normalize_right_amt1_w;
            normalize_right_1_r <= normalize_right_1_w;
            normalize_right_amt2_w_d5_r <= normalize_right_amt2_w;
            normalize_right_amt2_w_d6_r <= normalize_right_amt2_w_d5_r;
            unused_normalize_right_2_r <= unused_normalize_right_2_w[30:0];
            normalize_left_0_r <= normalize_left_0_w;
            normalize_left_amt1_w_d5_r <= normalize_left_amt1_w;
            normalize_left_1_r <= normalize_left_1_w;
            normalize_left_amt2_w_d5_r <= normalize_left_amt2_w;
            normalize_left_amt2_w_d6_r <= normalize_left_amt2_w_d5_r;
            unused_normalize_left_2_r <= unused_normalize_left_2_w[30:0];
            exponent_d4_r <= exponent_r;
            exponent_d5_r <= exponent_d4_r;
            exponent_d6_r <= exponent_d5_r;
            exponent_d7_r <= exponent_d6_r;
            mantissa_r <=
                exponent_d7_r >= 30 ? unused_normalize_right_2_r[30:0] :
                unused_normalize_left_2_r[30:0] ;
            seed_output_r <= seed_data_w;
            mantissa_d9_r <= mantissa_r;

            newton_round_r <= newton_high_w + newton_bit_w;

            seed_output_r_d11_r <= seed_output_r;
            seed_output_r_d12_r <= seed_output_r_d11_r;
            seed_output_r_d13_r <= seed_output_r_d12_r;
            seed_output_r_d14_r <= seed_output_r_d13_r;
            seed_output_r_d15_r <= seed_output_r_d14_r;
            reciprocal_r <=
                unused_newton_result_p2_r[60:30] + {30'b0, unused_newton_result_p2_r[29] };
            exponent_d8_r <= exponent_d7_r;
            exponent_d9_r <= exponent_d8_r;
            exponent_d10_r <= exponent_d9_r;
            exponent_d11_r <= exponent_d10_r;
            exponent_d12_r <= exponent_d11_r;
            exponent_d13_r <= exponent_d12_r;
            exponent_d14_r <= exponent_d13_r;
            exponent_d15_r <= exponent_d14_r;
            exponent_d16_r <= exponent_d15_r;
            exponent_d17_r <= exponent_d16_r;
            exponent_d18_r <= exponent_d17_r;
            exponent_d19_r <= exponent_d18_r;
        end
    end
    // Alignment registers compensate only for the added multiplier stages.
    reg [29:0] seed_output_r_d15_align1_r;

    always @(posedge clk_i) begin
        if (enable_i) begin
            seed_output_r_d15_align1_r <= seed_output_r_d15_r;

        end
    end

    reg [5:0] exponent_extra0_r;
    reg [5:0] exponent_extra1_r;
    reg [5:0] exponent_extra2_r;
    reg [5:0] exponent_extra3_r;
    always @(posedge clk_i) begin
        if (enable_i) begin
            exponent_extra0_r <= exponent_d19_r;
            exponent_extra1_r <= exponent_extra0_r;
            exponent_extra2_r <= exponent_extra1_r;
            exponent_extra3_r <= exponent_extra2_r;
        end
    end
    // The X/Y banks replace mantissa/seed and correction input registers.
    wire [31:0] correction_apm_w;
    assign correction_apm_w = 32'd2147483648 - newton_round_r;
    edrv32_apm_gpu_u31xu30 u_newton_product (
        .clk_i(clk_i),
        .enable_i(enable_i),
        .a_i(mantissa_d9_r),
        .b_i(seed_data_w),
        .p_o(unused_newton_product_p2_r)
    );
    edrv32_apm_gpu_u30xu32 u_newton_result (
        .clk_i(clk_i),
        .enable_i(enable_i),
        .a_i(seed_output_r_d15_align1_r),
        .b_i(correction_apm_w),
        .p_o(unused_newton_result_p2_r)
    );
endmodule
