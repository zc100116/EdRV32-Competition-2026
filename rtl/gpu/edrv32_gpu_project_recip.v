// File: edrv32_gpu_project_recip.v
// Spec: gpu-spec 2.12; GPU microarchitecture 4.3, 4.10.
// Description: Q30 normalized reciprocal, midpoint seed and one Newton iteration.
//              Ten enabled pipeline stages; preserve the normalization exponent.
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

    // Normalized reciprocal and original leading-one exponent.
    output wire value_valid_o,
    output wire [30:0] reciprocal_o,
    output wire [5:0] exponent_o
);
    reg [39:0] input_value_r;
    reg [1:0] leading_group0;
    reg [1:0] leading_group1;
    reg [1:0] leading_group2;
    reg [1:0] leading_group3;
    reg [1:0] leading_group4;
    reg [1:0] leading_group5;
    reg [1:0] leading_group6;
    reg [1:0] leading_group7;
    reg [1:0] leading_group8;
    reg [1:0] leading_group9;
    reg [9:0] leading_nonzero;
    reg [5:0] leading_partial0;
    reg [5:0] leading_partial1;
    reg [5:0] leading_partial2;
    reg [9:0] leading_nonzero_d2;
    reg [5:0] exponent;
    reg [5:0] right_amount;
    reg [5:0] left_amount;
    wire [1:0] normalize_right_amt0_w;
    reg [39:0] normalize_right_0_w;
    reg [39:0] input_value_r_d1;
    reg [39:0] input_value_r_d2;
    reg [39:0] input_value_r_d3;
    reg [39:0] input_value_r_d4;
    reg [39:0] normalize_right_0_r;
    wire [1:0] normalize_right_amt1_w;
    reg [39:0] normalize_right_1_w;
    reg [1:0] normalize_right_amt1_w_d5;
    reg [39:0] normalize_right_1_r;
    wire [1:0] normalize_right_amt2_w;
    reg [39:0] normalize_right_2_w;
    reg [1:0] normalize_right_amt2_w_d5;
    reg [1:0] normalize_right_amt2_w_d6;
    reg [39:0] unused_normalize_right_2_r;
    wire [1:0] normalize_left_amt0_w;
    reg [39:0] normalize_left_0_w;
    reg [39:0] normalize_left_0_r;
    wire [1:0] normalize_left_amt1_w;
    reg [39:0] normalize_left_1_w;
    reg [1:0] normalize_left_amt1_w_d5;
    reg [39:0] normalize_left_1_r;
    wire [1:0] normalize_left_amt2_w;
    reg [39:0] normalize_left_2_w;
    reg [1:0] normalize_left_amt2_w_d5;
    reg [1:0] normalize_left_amt2_w_d6;
    reg [39:0] unused_normalize_left_2_r;
    reg [5:0] exponent_d4;
    reg [5:0] exponent_d5;
    reg [5:0] exponent_d6;
    reg [5:0] exponent_d7;
    reg [30:0] mantissa;
    wire [29:0] seed_data_w;
    reg [29:0] seed_output_r;
    reg [30:0] mantissa_d9;
    reg [30:0] mantissa_d10;
    reg [60:0] newton_product;
    reg [60:0] newton_product_p1;
    reg [60:0] unused_newton_product_p2;
    wire [31:0] newton_high_w;
    wire [31:0] newton_bit_w;
    reg [31:0] newton_round;
    reg [31:0] newton_correction;
    reg [29:0] seed_output_r_d11;
    reg [29:0] seed_output_r_d12;
    reg [29:0] seed_output_r_d13;
    reg [29:0] seed_output_r_d14;
    reg [29:0] seed_output_r_d15;
    reg [61:0] newton_result;
    reg [61:0] newton_result_p1;
    reg [61:0] unused_newton_result_p2;
    reg [30:0] reciprocal;
    reg [5:0] exponent_d8;
    reg [5:0] exponent_d9;
    reg [5:0] exponent_d10;
    reg [5:0] exponent_d11;
    reg [5:0] exponent_d12;
    reg [5:0] exponent_d13;
    reg [5:0] exponent_d14;
    reg [5:0] exponent_d15;
    reg [5:0] exponent_d16;
    reg [5:0] exponent_d17;
    reg [5:0] exponent_d18;
    reg [5:0] exponent_d19;
    reg [19:0] valid_r;
    assign value_valid_o = valid_r[19];
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) valid_r <= 0;
        else if (stop_i) valid_r <= 0;
        else if (enable_i) valid_r <= {valid_r[18:0], value_valid_i};
    end
    assign normalize_right_amt0_w = right_amount[0 +: 2];
    always @(*) begin
        normalize_right_0_w = input_value_r_d4;
        case (normalize_right_amt0_w)
            2'd0: normalize_right_0_w = input_value_r_d4 >> 0;
            2'd1: normalize_right_0_w = input_value_r_d4 >> 1;
            2'd2: normalize_right_0_w = input_value_r_d4 >> 2;
            2'd3: normalize_right_0_w = input_value_r_d4 >> 3;
            default: normalize_right_0_w = input_value_r_d4;
        endcase
    end
    assign normalize_right_amt1_w = right_amount[2 +: 2];
    always @(*) begin
        normalize_right_1_w = normalize_right_0_r;
        case (normalize_right_amt1_w_d5)
            2'd0: normalize_right_1_w = normalize_right_0_r >> 0;
            2'd1: normalize_right_1_w = normalize_right_0_r >> 4;
            2'd2: normalize_right_1_w = normalize_right_0_r >> 8;
            2'd3: normalize_right_1_w = normalize_right_0_r >> 12;
            default: normalize_right_1_w = normalize_right_0_r;
        endcase
    end
    assign normalize_right_amt2_w = right_amount[4 +: 2];
    always @(*) begin
        normalize_right_2_w = normalize_right_1_r;
        case (normalize_right_amt2_w_d6)
            2'd0: normalize_right_2_w = normalize_right_1_r >> 0;
            2'd1: normalize_right_2_w = normalize_right_1_r >> 16;
            2'd2: normalize_right_2_w = normalize_right_1_r >> 32;
            2'd3: normalize_right_2_w = normalize_right_1_r >> 48;
            default: normalize_right_2_w = normalize_right_1_r;
        endcase
    end
    assign normalize_left_amt0_w = left_amount[0 +: 2];
    always @(*) begin
        normalize_left_0_w = input_value_r_d4;
        case (normalize_left_amt0_w)
            2'd0: normalize_left_0_w = input_value_r_d4 << 0;
            2'd1: normalize_left_0_w = input_value_r_d4 << 1;
            2'd2: normalize_left_0_w = input_value_r_d4 << 2;
            2'd3: normalize_left_0_w = input_value_r_d4 << 3;
            default: normalize_left_0_w = input_value_r_d4;
        endcase
    end
    assign normalize_left_amt1_w = left_amount[2 +: 2];
    always @(*) begin
        normalize_left_1_w = normalize_left_0_r;
        case (normalize_left_amt1_w_d5)
            2'd0: normalize_left_1_w = normalize_left_0_r << 0;
            2'd1: normalize_left_1_w = normalize_left_0_r << 4;
            2'd2: normalize_left_1_w = normalize_left_0_r << 8;
            2'd3: normalize_left_1_w = normalize_left_0_r << 12;
            default: normalize_left_1_w = normalize_left_0_r;
        endcase
    end
    assign normalize_left_amt2_w = left_amount[4 +: 2];
    always @(*) begin
        normalize_left_2_w = normalize_left_1_r;
        case (normalize_left_amt2_w_d6)
            2'd0: normalize_left_2_w = normalize_left_1_r << 0;
            2'd1: normalize_left_2_w = normalize_left_1_r << 16;
            2'd2: normalize_left_2_w = normalize_left_1_r << 32;
            2'd3: normalize_left_2_w = normalize_left_1_r << 48;
            default: normalize_left_2_w = normalize_left_1_r;
        endcase
    end
    edrv32_rom_gpu_recip_q30 u_seed (
        .clk_i(clk_i),
        .en_i(enable_i),
        .addr_i(mantissa[29:20]),
        .rd_data_o(seed_data_w)
    );
    assign newton_high_w = {1'b0, unused_newton_product_p2[60:30]};
    assign newton_bit_w = {31'b0, unused_newton_product_p2[29]};
    assign reciprocal_o = reciprocal;
    assign exponent_o = exponent_d19;
    always @(posedge clk_i) begin
        if (enable_i) begin
            input_value_r <= value_i;
            leading_group0 <= input_value_r[3] ? 2'd3 : input_value_r[2] ? 2'd2 :
            input_value_r[1] ? 2'd1 : input_value_r[0] ? 2'd0 : 2'b0;
            leading_group1 <= input_value_r[7] ? 2'd3 : input_value_r[6] ? 2'd2 :
            input_value_r[5] ? 2'd1 : input_value_r[4] ? 2'd0 : 2'b0;
            leading_group2 <= input_value_r[11] ? 2'd3 : input_value_r[10] ? 2'd2 :
            input_value_r[9] ? 2'd1 : input_value_r[8] ? 2'd0 : 2'b0;
            leading_group3 <= input_value_r[15] ? 2'd3 : input_value_r[14] ? 2'd2 :
            input_value_r[13] ? 2'd1 : input_value_r[12] ? 2'd0 : 2'b0;
            leading_group4 <= input_value_r[19] ? 2'd3 : input_value_r[18] ? 2'd2 :
            input_value_r[17] ? 2'd1 : input_value_r[16] ? 2'd0 : 2'b0;
            leading_group5 <= input_value_r[23] ? 2'd3 : input_value_r[22] ? 2'd2 :
            input_value_r[21] ? 2'd1 : input_value_r[20] ? 2'd0 : 2'b0;
            leading_group6 <= input_value_r[27] ? 2'd3 : input_value_r[26] ? 2'd2 :
            input_value_r[25] ? 2'd1 : input_value_r[24] ? 2'd0 : 2'b0;
            leading_group7 <= input_value_r[31] ? 2'd3 : input_value_r[30] ? 2'd2 :
            input_value_r[29] ? 2'd1 : input_value_r[28] ? 2'd0 : 2'b0;
            leading_group8 <= input_value_r[35] ? 2'd3 : input_value_r[34] ? 2'd2 :
            input_value_r[33] ? 2'd1 : input_value_r[32] ? 2'd0 : 2'b0;
            leading_group9 <= input_value_r[39] ? 2'd3 : input_value_r[38] ? 2'd2 :
            input_value_r[37] ? 2'd1 : input_value_r[36] ? 2'd0 : 2'b0;
            leading_nonzero <= {(|input_value_r[36 +: 4]), (|input_value_r[32 +: 4]),
            (|input_value_r[28 +: 4]), (|input_value_r[24 +: 4]), (|input_value_r[20 +: 4]),
            (|input_value_r[16 +: 4]), (|input_value_r[12 +: 4]), (|input_value_r[8 +: 4]),
            (|input_value_r[4 +: 4]), (|input_value_r[0 +: 4])};
            leading_partial0 <= leading_nonzero[3] ? {4'd3, leading_group3} :
            leading_nonzero[2] ? {4'd2, leading_group2} : leading_nonzero[1] ? {4'd1,
            leading_group1} : leading_nonzero[0] ? {4'd0, leading_group0} : 6'b0;
            leading_partial1 <= leading_nonzero[7] ? {4'd7, leading_group7} :
            leading_nonzero[6] ? {4'd6, leading_group6} : leading_nonzero[5] ? {4'd5,
            leading_group5} : leading_nonzero[4] ? {4'd4, leading_group4} : 6'b0;
            leading_partial2 <= leading_nonzero[9] ? {4'd9, leading_group9} :
            leading_nonzero[8] ? {4'd8, leading_group8} : 6'b0;
            leading_nonzero_d2 <= leading_nonzero;
            exponent <= (|leading_nonzero_d2[8 +: 2]) ? leading_partial2 :
            (|leading_nonzero_d2[4 +: 4]) ? leading_partial1 : (|leading_nonzero_d2[0 +: 4]) ?
            leading_partial0 : 6'b0;
            right_amount <= exponent >= 30 ? exponent - 6'd30 : 6'b0;
            left_amount <= exponent < 30 ? 6'd30 - exponent : 6'b0;
            input_value_r_d1 <= input_value_r;
            input_value_r_d2 <= input_value_r_d1;
            input_value_r_d3 <= input_value_r_d2;
            input_value_r_d4 <= input_value_r_d3;
            normalize_right_0_r <= normalize_right_0_w;
            normalize_right_amt1_w_d5 <= normalize_right_amt1_w;
            normalize_right_1_r <= normalize_right_1_w;
            normalize_right_amt2_w_d5 <= normalize_right_amt2_w;
            normalize_right_amt2_w_d6 <= normalize_right_amt2_w_d5;
            unused_normalize_right_2_r <= normalize_right_2_w;
            normalize_left_0_r <= normalize_left_0_w;
            normalize_left_amt1_w_d5 <= normalize_left_amt1_w;
            normalize_left_1_r <= normalize_left_1_w;
            normalize_left_amt2_w_d5 <= normalize_left_amt2_w;
            normalize_left_amt2_w_d6 <= normalize_left_amt2_w_d5;
            unused_normalize_left_2_r <= normalize_left_2_w;
            exponent_d4 <= exponent;
            exponent_d5 <= exponent_d4;
            exponent_d6 <= exponent_d5;
            exponent_d7 <= exponent_d6;
            mantissa <= exponent_d7 >= 30 ? unused_normalize_right_2_r[30:0] :
            unused_normalize_left_2_r[30:0];
            seed_output_r <= seed_data_w;
            mantissa_d9 <= mantissa;
            mantissa_d10 <= mantissa_d9;
            newton_product <= mantissa_d10 * seed_output_r;
            newton_product_p1 <= newton_product;
            unused_newton_product_p2 <= newton_product_p1;
            newton_round <= newton_high_w + newton_bit_w;
            newton_correction <= 32'd2147483648 - newton_round;
            seed_output_r_d11 <= seed_output_r;
            seed_output_r_d12 <= seed_output_r_d11;
            seed_output_r_d13 <= seed_output_r_d12;
            seed_output_r_d14 <= seed_output_r_d13;
            seed_output_r_d15 <= seed_output_r_d14;
            newton_result <= seed_output_r_d15 * newton_correction;
            newton_result_p1 <= newton_result;
            unused_newton_result_p2 <= newton_result_p1;
            reciprocal <= unused_newton_result_p2[60:30] + {30'b0, unused_newton_result_p2[29]};
            exponent_d8 <= exponent_d7;
            exponent_d9 <= exponent_d8;
            exponent_d10 <= exponent_d9;
            exponent_d11 <= exponent_d10;
            exponent_d12 <= exponent_d11;
            exponent_d13 <= exponent_d12;
            exponent_d14 <= exponent_d13;
            exponent_d15 <= exponent_d14;
            exponent_d16 <= exponent_d15;
            exponent_d17 <= exponent_d16;
            exponent_d18 <= exponent_d17;
            exponent_d19 <= exponent_d18;
        end
    end
endmodule
