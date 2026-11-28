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

    // Ten edges for FMA/MUL; the separately rounded DP product tap takes eight edges.
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
    // Keep all 48 product bits plus seven low guard positions when cancellation is possible.
    // E6 captures low alignment; E7 combines high alignment and carry; E10 completes RNE/pack.
    // This replaces the 77-bit alignment without changing the ten-edge arithmetic contract.
    reg signed [9:0] s2_product_exp_r;
    reg signed [9:0] s2_c_exp_r;
    reg s2_product_zero_r;
    reg s2_c_zero_r;
    always @(posedge clk_i) begin
        s2_product_exp_r <= s2_product_exp_w;
        s2_c_exp_r <= s1_c_exp_r;
        s2_product_zero_r <= product_zero_r[0];
        s2_c_zero_r <= addend_zero_r[0];
    end
    wire signed [9:0] s3_product_top_w;
    wire signed [9:0] s3_base_w;
    wire [9:0] s3_product_delta_w;
    wire [9:0] s3_c_delta_w;
    assign s3_product_top_w = s2_product_exp_r + 10'sd1;
    assign s3_base_w = s2_product_zero_r ? s2_c_exp_r
        : s2_c_zero_r || s3_product_top_w >= s2_c_exp_r
            ? s3_product_top_w : s2_c_exp_r;
    assign s3_product_delta_w = s3_base_w - s3_product_top_w;
    assign s3_c_delta_w = s3_base_w - s2_c_exp_r;
    reg [23:0] s2_c_r;
    reg [23:0] s3_c_mantissa_r;
    (* keep = "true", syn_preserve = 1 *) reg [47:0] s3_c_shift_r;
    reg [5:0] product_shift_r [3:4];
    (* keep = "true", syn_preserve = 1 *) reg [47:0] s5_product_shift_r;
    reg signed [9:0] base_exp_r [3:7];
    integer align_idx;
    always @(posedge clk_i) begin
        s2_c_r <= s2_c_w;
        s3_c_mantissa_r <= s2_c_r;
        s3_c_shift_r <= {8{s3_c_delta_w > 10'd55 ? 6'd56 : s3_c_delta_w[5:0]}};
        product_shift_r[3] <= s2_product_zero_r || s3_product_delta_w > 10'd55
            ? 6'd56 : s3_product_delta_w[5:0];
        base_exp_r[3] <= s3_base_w;
        s5_product_shift_r <= {8{product_shift_r[4]}};
        for (align_idx = 4; align_idx < 5; align_idx = align_idx + 1)
            product_shift_r[align_idx] <= product_shift_r[align_idx-1];
        for (align_idx = 4; align_idx < 8; align_idx = align_idx + 1)
            base_exp_r[align_idx] <= base_exp_r[align_idx-1];
    end
    wire [55:0] s4_c_input_w;
    assign s4_c_input_w = {1'b0, s3_c_mantissa_r, 31'b0};
    wire [55:0] c_low_w [0:3];
    wire [55:0] c_high_w [0:3];
    assign c_low_w[0] = s4_c_input_w;
    reg [55:0] s4_c_r;
    (* keep = "true", syn_preserve = 1 *) reg [23:0] s4_c_high_r;
    reg [55:0] s5_c_r;
    reg [55:0] s6_c_r;
    assign c_high_w[0] = s4_c_r;
    genvar c_stage;
    genvar c_bit;
    generate
        for (c_stage = 0; c_stage < 3; c_stage = c_stage+1) begin : g_c_shift
            localparam LOW_STEP = 1 << c_stage;
            localparam HIGH_STEP = 8 << c_stage;
            for (c_bit = 0; c_bit < 56; c_bit = c_bit+1) begin : g_bit
                localparam LOW_CONTROL = (c_bit/7)*6 + c_stage;
                localparam HIGH_CONTROL = (c_bit/7)*3 + c_stage;
                if (c_bit+LOW_STEP < 56) begin : g_low
                    assign c_low_w[c_stage+1][c_bit] = s3_c_shift_r[LOW_CONTROL]
                        ? c_low_w[c_stage][c_bit+LOW_STEP] : c_low_w[c_stage][c_bit];
                end else begin : g_low_zero
                    assign c_low_w[c_stage+1][c_bit] = !s3_c_shift_r[LOW_CONTROL]
                        && c_low_w[c_stage][c_bit];
                end
                if (c_bit == 0) begin : g_jam
                    assign c_high_w[c_stage+1][c_bit] = s4_c_high_r[HIGH_CONTROL]
                        ? (|c_high_w[c_stage][HIGH_STEP:0]) : c_high_w[c_stage][0];
                end else if (c_bit+HIGH_STEP < 56) begin : g_high
                    assign c_high_w[c_stage+1][c_bit] = s4_c_high_r[HIGH_CONTROL]
                        ? c_high_w[c_stage][c_bit+HIGH_STEP] : c_high_w[c_stage][c_bit];
                end else begin : g_high_zero
                    assign c_high_w[c_stage+1][c_bit] = !s4_c_high_r[HIGH_CONTROL]
                        && c_high_w[c_stage][c_bit];
                end
            end
        end
    endgenerate
    always @(posedge clk_i) begin
        s4_c_r <= c_low_w[3];
        s4_c_high_r <= {s3_c_shift_r[47:45], s3_c_shift_r[41:39], s3_c_shift_r[35:33],
            s3_c_shift_r[29:27], s3_c_shift_r[23:21], s3_c_shift_r[17:15],
            s3_c_shift_r[11:9], s3_c_shift_r[5:3]};
        s5_c_r <= c_high_w[3];
        s6_c_r <= s5_c_r;
    end
    wire [55:0] s6_product_input_w;
    assign s6_product_input_w = {1'b0, s5_product_w, 7'b0};
    wire [55:0] s6_low_w [0:3];
    assign s6_low_w[0] = s6_product_input_w;
    reg [55:0] s6_product_partial_r;
    (* keep = "true", syn_preserve = 1 *) reg [23:0] s6_product_high_r;
    // E6 consumes only three muxes after the APM. The input has seven exact low zeros.
    genvar product_stage;
    genvar product_bit;
    generate
        for (product_stage = 0; product_stage < 3; product_stage = product_stage+1)
            begin : g_product_low
            localparam STEP = 1 << product_stage;
            for (product_bit = 0; product_bit < 56; product_bit = product_bit+1) begin : g_bit
                localparam CONTROL = (product_bit/7)*6 + product_stage;
                if (product_bit+STEP < 56) begin : g_data
                    assign s6_low_w[product_stage+1][product_bit] = s5_product_shift_r[CONTROL]
                        ? s6_low_w[product_stage][product_bit+STEP]
                        : s6_low_w[product_stage][product_bit];
                end else begin : g_zero
                    assign s6_low_w[product_stage+1][product_bit] = !s5_product_shift_r[CONTROL]
                        && s6_low_w[product_stage][product_bit];
                end
            end
        end
    endgenerate
    always @(posedge clk_i) begin
        s6_product_partial_r <= s6_low_w[3];
        s6_product_high_r <= {s5_product_shift_r[47:45], s5_product_shift_r[41:39],
            s5_product_shift_r[35:33], s5_product_shift_r[29:27], s5_product_shift_r[23:21],
            s5_product_shift_r[17:15], s5_product_shift_r[11:9], s5_product_shift_r[5:3]};
    end
    // Card112 E7 carry segment had +1.772ns: absorb the three high alignment muxes here.
    wire [55:0] s7_high_w [0:3];
    assign s7_high_w[0] = s6_product_partial_r;
    genvar high_stage;
    genvar high_bit;
    generate
        for (high_stage = 0; high_stage < 3; high_stage = high_stage+1) begin : g_product_high
            localparam STEP = 8 << high_stage;
            for (high_bit = 0; high_bit < 56; high_bit = high_bit+1) begin : g_bit
                localparam CONTROL = (high_bit/7)*3 + high_stage;
                if (high_bit == 0) begin : g_jam
                    assign s7_high_w[high_stage+1][high_bit] = s6_product_high_r[CONTROL]
                        ? (|s7_high_w[high_stage][STEP:0]) : s7_high_w[high_stage][0];
                end else if (high_bit+STEP < 56) begin : g_data
                    assign s7_high_w[high_stage+1][high_bit] = s6_product_high_r[CONTROL]
                        ? s7_high_w[high_stage][high_bit+STEP] : s7_high_w[high_stage][high_bit];
                end else begin : g_zero
                    assign s7_high_w[high_stage+1][high_bit] = !s6_product_high_r[CONTROL]
                        && s7_high_w[high_stage][high_bit];
                end
            end
        end
    endgenerate
    wire opposite_w;
    assign opposite_w = product_sign_r[5] != addend_sign_r[5];
    reg [56:0] s7_forward_r;
    reg [55:0] s7_reverse_r;
    always @(posedge clk_i) begin
        s7_forward_r <= opposite_w ? {1'b0, s7_high_w[3]} - {1'b0, s6_c_r}
            : {1'b0, s7_high_w[3]} + {1'b0, s6_c_r};
        s7_reverse_r <= s6_c_r - s7_high_w[3];
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
    reg signed [9:0] s7_limit_r;
    always @(posedge clk_i) begin
        s7_limit_r <= base_exp_r[6] + 10'sd127;
    end
    assign s8_exp_w = base_exp_r[7] + 10'sd1 - $signed({3'b0, s8_lz_w});
    assign s8_limit_w = s7_limit_r;
    reg [55:0] s8_magnitude_r;
    reg signed [9:0] s8_exp_r;
    // Eight same-edge leaves: each shift bit drives <=14 data muxes plus one jam mux.
    (* keep = "true", syn_preserve = 1 *) reg [47:0] s8_shift_r;
    (* keep = "true", syn_preserve = 1 *) reg [7:0] s8_right_r;
    wire [5:0] s8_shift_control_w;
    assign s8_shift_control_w = s8_limit_w < 0 ? (s8_limit_w < -10'sd55 ? 6'd56
        : -s8_limit_w[5:0]) : $signed({3'b0, s8_lz_w}) > s8_limit_w
            ? s8_limit_w[5:0] : s8_lz_w[5:0];
    reg s8_sign_r;
    reg s8_zero_r;
    always @(posedge clk_i) begin
        s8_magnitude_r <= s8_magnitude_w;
        s8_exp_r <= s8_exp_w;
        s8_right_r <= {8{s8_limit_w < 0}};
        s8_shift_r <= {8{s8_shift_control_w}};
        s8_zero_r <= !(|s8_magnitude_w);
        s8_sign_r <= !(|s8_magnitude_w)
            ? product_sign_r[6] && addend_sign_r[6]
            : s7_forward_r[56] ? addend_sign_r[6] : product_sign_r[6];
    end
    wire [55:0] s9_shift_w;
    wire [55:0] s9_left_w [2:6];
    wire [55:0] s9_right_w [2:6];
    assign s9_left_w[2] = s8_magnitude_r;
    assign s9_right_w[2] = s8_magnitude_r;
    genvar shift_stage;
    genvar shift_bit;
    generate
        for (shift_stage = 2; shift_stage < 6; shift_stage = shift_stage+1) begin : g_shift
            localparam STEP = 1 << shift_stage;
            for (shift_bit = 0; shift_bit < 56; shift_bit = shift_bit+1) begin : g_bit
                localparam CONTROL = (shift_bit / 7)*6 + shift_stage;
                if (shift_bit >= STEP) begin : g_left_data
                    assign s9_left_w[shift_stage+1][shift_bit] = s8_shift_r[CONTROL]
                        ? s9_left_w[shift_stage][shift_bit-STEP]
                        : s9_left_w[shift_stage][shift_bit];
                end else begin : g_left_zero
                    assign s9_left_w[shift_stage+1][shift_bit] = !s8_shift_r[CONTROL]
                        && s9_left_w[shift_stage][shift_bit];
                end
                if (shift_bit == 0) begin : g_right_jam
                    assign s9_right_w[shift_stage+1][shift_bit] = s8_shift_r[CONTROL]
                        ? (|s9_right_w[shift_stage][STEP:0]) : s9_right_w[shift_stage][0];
                end else if (shift_bit+STEP < 56) begin : g_right_data
                    assign s9_right_w[shift_stage+1][shift_bit] = s8_shift_r[CONTROL]
                        ? s9_right_w[shift_stage][shift_bit+STEP]
                        : s9_right_w[shift_stage][shift_bit];
                end else begin : g_right_zero
                    assign s9_right_w[shift_stage+1][shift_bit] = !s8_shift_r[CONTROL]
                        && s9_right_w[shift_stage][shift_bit];
                end
            end
        end
        for (shift_bit = 0; shift_bit < 56; shift_bit = shift_bit+1) begin : g_shift_direction
            assign s9_shift_w[shift_bit] = s8_right_r[shift_bit/7]
                ? s9_right_w[6][shift_bit] : s9_left_w[6][shift_bit];
        end
    endgenerate
    reg [55:0] s9_partial_r;
    reg [3:0] s9_sticky_groups_r;
    (* keep = "true", syn_preserve = 1 *) reg [15:0] s9_low_shift_r;
    (* keep = "true", syn_preserve = 1 *) reg [7:0] s9_right_r;
    wire [23:0] s10_mantissa_w;
    wire s10_increment_w;
    reg signed [9:0] s9_exp_r;
    reg s9_sign_r;
    reg s9_zero_r;
    always @(posedge clk_i) begin
        // Move the last two normalization muxes into E10's short RNE/pack segment.
        s9_partial_r <= s9_shift_w;
        s9_sticky_groups_r <= {|s9_shift_w[27:21], |s9_shift_w[20:14],
            |s9_shift_w[13:7], |s9_shift_w[6:0]};
        s9_low_shift_r <= {s8_shift_r[43:42], s8_shift_r[37:36],
            s8_shift_r[31:30], s8_shift_r[25:24], s8_shift_r[19:18],
            s8_shift_r[13:12], s8_shift_r[7:6], s8_shift_r[1:0]};
        s9_right_r <= s8_right_r;
        s9_exp_r <= s8_exp_r < -10'sd126 ? -10'sd126 : s8_exp_r;
        s9_sign_r <= s8_sign_r;
        s9_zero_r <= s8_zero_r;
    end
    wire [55:0] s10_left_w [0:2];
    wire [55:0] s10_right_w [0:2];
    wire [55:0] unused_s10_normal_w;
    assign s10_left_w[0] = s9_partial_r;
    assign s10_right_w[0] = s9_partial_r;
    genvar low_stage;
    genvar low_bit;
    generate
        for (low_stage = 0; low_stage < 2; low_stage = low_stage+1) begin : g_low_shift
            localparam STEP = 1 << low_stage;
            for (low_bit = 0; low_bit < 56; low_bit = low_bit+1) begin : g_bit
                localparam CONTROL = (low_bit/7)*2 + low_stage;
                if (low_bit >= STEP) begin : g_left_data
                    assign s10_left_w[low_stage+1][low_bit] = s9_low_shift_r[CONTROL]
                        ? s10_left_w[low_stage][low_bit-STEP] : s10_left_w[low_stage][low_bit];
                end else begin : g_left_zero
                    assign s10_left_w[low_stage+1][low_bit] = !s9_low_shift_r[CONTROL]
                        && s10_left_w[low_stage][low_bit];
                end
                if (low_bit+STEP < 56) begin : g_right_data
                    assign s10_right_w[low_stage+1][low_bit] = s9_low_shift_r[CONTROL]
                        ? s10_right_w[low_stage][low_bit+STEP] : s10_right_w[low_stage][low_bit];
                end else begin : g_right_zero
                    assign s10_right_w[low_stage+1][low_bit] = !s9_low_shift_r[CONTROL]
                        && s10_right_w[low_stage][low_bit];
                end
            end
        end
        for (low_bit = 0; low_bit < 56; low_bit = low_bit+1) begin : g_low_direction
            assign unused_s10_normal_w[low_bit] = s9_right_r[low_bit/7]
                ? s10_right_w[2][low_bit] : s10_left_w[2][low_bit];
        end
    endgenerate
    assign s10_mantissa_w = unused_s10_normal_w[55:32];
    assign s10_increment_w = unused_s10_normal_w[31]
        && (unused_s10_normal_w[32] || (|unused_s10_normal_w[30:24]) || (|s9_sticky_groups_r));
    wire [24:0] s10_rounded_w;
    wire signed [9:0] s10_exp_w;
    wire [7:0] s10_biased_w;
    assign s10_rounded_w = {1'b0, s10_mantissa_w} + {24'b0, s10_increment_w};
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
    reg tap_special_r [0:6];
    reg [31:0] tap_special_data_r [0:6];
    wire tap_nan_w;
    assign tap_nan_w = (a_i[30:0] > 31'h7f800000) || (b_i[30:0] > 31'h7f800000)
        || (a_inf_w && !(|b_i[30:0])) || (b_inf_w && !(|a_i[30:0]));
    integer tap_idx;
    always @(posedge clk_i) begin
        tap_special_r[0] <= tap_nan_w || a_inf_w || b_inf_w;
        tap_special_data_r[0] <= tap_nan_w ? 32'h7fc00000
            : {product_sign_w, 8'hff, 23'b0};
        for (tap_idx = 1; tap_idx < 7; tap_idx = tap_idx + 1) begin
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
    // APM output used to feed a 77-bit LZ/variable-shift/GRS chain (15 PDS levels).
    // Exponent-only underflow control is computed while the two APMs run.
    (* syn_preserve = 1 *) reg [35:0] tap_shift_r [3:5];
    reg tap_normal_r [3:5];
    reg signed [9:0] tap_high_exp_r [3:5];
    reg signed [9:0] tap_exp_r [3:5];
    integer tap_control_idx;
    wire signed [9:0] tap_limit_w;
    wire [5:0] tap_shift_control_w;
    assign tap_shift_control_w = tap_limit_w < -10'sd47 ? 6'd48
        : tap_limit_w < 0 ? -tap_limit_w[5:0] : 6'd0;
    assign tap_limit_w = product_exp_r[2] + 10'sd127;
    always @(posedge clk_i) begin
        tap_shift_r[3] <= {6{tap_shift_control_w}};
        tap_normal_r[3] <= product_exp_r[2] >= -10'sd126;
        tap_exp_r[3] <= product_exp_r[2] < -10'sd126 ? -10'sd126 : product_exp_r[2];
        tap_high_exp_r[3] <= product_exp_r[2] < -10'sd126 ? -10'sd126
            : product_exp_r[2] + 10'sd1;
        for (tap_control_idx = 4; tap_control_idx < 6; tap_control_idx = tap_control_idx+1) begin
            tap_shift_r[tap_control_idx] <= tap_shift_r[tap_control_idx-1];
            tap_normal_r[tap_control_idx] <= tap_normal_r[tap_control_idx-1];
            tap_high_exp_r[tap_control_idx] <= tap_high_exp_r[tap_control_idx-1];
            tap_exp_r[tap_control_idx] <= tap_exp_r[tap_control_idx-1];
        end
    end
    wire [47:0] tap_low_w [0:3];
    assign tap_low_w[0] = s5_product_w;
    reg [47:0] tap_partial_r;
    (* syn_preserve = 1 *) reg [17:0] tap_high_r;
    (* syn_preserve = 1 *) reg [5:0] tap_left_r;
    reg signed [9:0] tap_normal_exp_r;
    always @(posedge clk_i) begin
        tap_partial_r <= tap_low_w[3];
        tap_high_r <= {tap_shift_r[5][35:33], tap_shift_r[5][29:27],
            tap_shift_r[5][23:21], tap_shift_r[5][17:15],
            tap_shift_r[5][11:9], tap_shift_r[5][5:3]};
        tap_left_r <= {6{tap_normal_r[5] && !s5_product_w[47]}};
        tap_normal_exp_r <= s5_product_w[47] ? tap_high_exp_r[5] : tap_exp_r[5];
    end
    wire [47:0] tap_high_w [0:3];
    wire [47:0] tap_normal_w;
    assign tap_high_w[0] = tap_partial_r;
    genvar tap_stage;
    genvar tap_bit;
    generate
        for (tap_stage = 0; tap_stage < 3; tap_stage = tap_stage+1) begin : g_tap_shift
            localparam LOW_STEP = 1 << tap_stage;
            localparam HIGH_STEP = 8 << tap_stage;
            for (tap_bit = 0; tap_bit < 48; tap_bit = tap_bit+1) begin : g_bit
                localparam LOW_CONTROL = (tap_bit/8)*6 + tap_stage;
                localparam HIGH_CONTROL = (tap_bit/8)*3 + tap_stage;
                if (tap_bit == 0) begin : g_jam
                    assign tap_low_w[tap_stage+1][tap_bit] = tap_shift_r[5][LOW_CONTROL]
                        ? (|tap_low_w[tap_stage][LOW_STEP:0]) : tap_low_w[tap_stage][0];
                    assign tap_high_w[tap_stage+1][tap_bit] = tap_high_r[HIGH_CONTROL]
                        ? (|tap_high_w[tap_stage][HIGH_STEP:0]) : tap_high_w[tap_stage][0];
                end else begin : g_data
                    localparam LOW_EXISTS = tap_bit+LOW_STEP < 48;
                    if (LOW_EXISTS) begin : g_low
                        assign tap_low_w[tap_stage+1][tap_bit] = tap_shift_r[5][LOW_CONTROL]
                            ? tap_low_w[tap_stage][tap_bit+LOW_STEP]
                            : tap_low_w[tap_stage][tap_bit];
                    end else begin : g_low_zero
                        assign tap_low_w[tap_stage+1][tap_bit] = !tap_shift_r[5][LOW_CONTROL]
                            && tap_low_w[tap_stage][tap_bit];
                    end
                    if (tap_bit+HIGH_STEP < 48) begin : g_high
                        assign tap_high_w[tap_stage+1][tap_bit] = tap_high_r[HIGH_CONTROL]
                            ? tap_high_w[tap_stage][tap_bit+HIGH_STEP]
                            : tap_high_w[tap_stage][tap_bit];
                    end else begin : g_high_zero
                        assign tap_high_w[tap_stage+1][tap_bit] = !tap_high_r[HIGH_CONTROL]
                            && tap_high_w[tap_stage][tap_bit];
                    end
                end
            end
        end
        for (tap_bit = 0; tap_bit < 48; tap_bit = tap_bit+1) begin : g_tap_left
            localparam BIT = tap_bit;
            if (BIT == 0) begin : g_zero
                assign tap_normal_w[tap_bit] = !tap_left_r[0] && tap_high_w[3][0];
            end else begin : g_data
                assign tap_normal_w[tap_bit] = tap_left_r[tap_bit/8]
                    ? tap_high_w[3][tap_bit-1] : tap_high_w[3][tap_bit];
            end
        end
    endgenerate
    reg [23:0] tap_s6_mantissa_r;
    reg tap_s6_increment_r;
    reg signed [9:0] tap_s6_exp_r;
    always @(posedge clk_i) begin
        tap_s6_mantissa_r <= tap_normal_w[47:24];
        tap_s6_increment_r <= tap_normal_w[23]
            && (tap_normal_w[24] || (|tap_normal_w[22:0]));
        tap_s6_exp_r <= tap_normal_exp_r;
    end
    reg tap_product_sign_r;
    reg tap_product_zero_r;
    always @(posedge clk_i) begin
        tap_product_sign_r <= product_sign_r[5];
        tap_product_zero_r <= product_zero_r[5];
    end
    wire [24:0] tap_s7_rounded_w;
    wire signed [9:0] tap_s7_exp_w;
    wire [7:0] tap_s7_biased_w;
    assign tap_s7_rounded_w = {1'b0, tap_s6_mantissa_r} + {24'b0, tap_s6_increment_r};
    assign tap_s7_exp_w = tap_s6_exp_r + $signed({9'b0, tap_s7_rounded_w[24]});
    assign tap_s7_biased_w = tap_s7_exp_w[7:0] + 8'd127;
    always @(posedge clk_i) begin
        product_o <= tap_special_r[6] ? tap_special_data_r[6]
            : tap_product_zero_r ? {tap_product_sign_r, 31'b0}
            : tap_s7_exp_w > 10'sd127 ? {tap_product_sign_r, 8'hff, 23'b0}
            : {tap_product_sign_r, tap_s7_rounded_w[24] ? tap_s7_biased_w
                : tap_s7_rounded_w[23] ? tap_s7_biased_w : 8'b0,
                tap_s7_rounded_w[24] ? tap_s7_rounded_w[23:1] : tap_s7_rounded_w[22:0]};
    end
endmodule
