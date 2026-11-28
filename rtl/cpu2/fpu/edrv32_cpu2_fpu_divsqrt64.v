// File: edrv32_cpu2_fpu_divsqrt64.v
// Spec: fpu-spec 2.2, 5.2, 5.3.
// Description: Independent radix-four 64-bit recurrence and rounded tail.
//              Three preparation stages, 27/28 divide/root digit stages, 6 tail stages.
// Clock domain: clk_sys.
module edrv32_cpu2_fpu_divsqrt64 (
    // Clock and registered schedule from the single-entry owner.
    input wire clk_i,
    input wire rst_n_i,
    input wire capture_next_i,
    input wire prepare_next_i,
    input wire iterate_next_i,
    input wire shift_next_i,
    input wire align_next_i,
    input wire round_next_i,
    input wire normalize_next_i,
    input wire encode_next_i,
    input wire pack_next_i,

    // Operands and resolved rounding mode.
    input wire [63:0] unit_req_src1_i,
    input wire [63:0] unit_req_src2_i,
    input wire sqrt_i,
    input wire [2:0] unit_req_rm_i,

    // Tail registers remain stable while the owner holds completion.
    output wire [63:0] result_o,
    output wire [4:0] flags_o
);
    wire [52:0] a_mantissa_w;
    assign a_mantissa_w = {|unit_req_src1_i[62:52], unit_req_src1_i[51:0]};
    wire [6:0] a_lz_full_w;
    wire [5:0] a_lz_w;
    edrv32_cpu2_fpu_lz53 u_lz_a (
        .data_i(a_mantissa_w),
        .count_o(a_lz_full_w)
    );
    assign a_lz_w = a_lz_full_w[5:0];
    wire a_zero_w;
    wire a_inf_w;
    wire a_nan_w;
    wire a_snan_w;
    assign a_zero_w = ~|unit_req_src1_i[62:0];
    assign a_inf_w = (&unit_req_src1_i[62:52]) && !(|unit_req_src1_i[51:0]);
    assign a_nan_w = (&unit_req_src1_i[62:52]) && (|unit_req_src1_i[51:0]);
    assign a_snan_w = a_nan_w && !unit_req_src1_i[51];
    reg [52:0] a_mantissa_r;
    reg [5:0] a_lz_r;
    reg signed [13:0] a_exponent_r;
    wire [52:0] a_normalized_w;
    reg [52:0] a_normalized_r;
    reg signed [13:0] a_adjusted_r;
    always @(posedge clk_i) begin
        a_normalized_r <= a_normalized_w;
        a_adjusted_r <= a_exponent_r - $signed({8'b0, a_lz_r});
    end
    assign a_normalized_w = a_mantissa_r << a_lz_r;
    wire [52:0] b_mantissa_w;
    assign b_mantissa_w = {|unit_req_src2_i[62:52], unit_req_src2_i[51:0]};
    wire [6:0] b_lz_full_w;
    wire [5:0] b_lz_w;
    edrv32_cpu2_fpu_lz53 u_lz_b (
        .data_i(b_mantissa_w),
        .count_o(b_lz_full_w)
    );
    assign b_lz_w = b_lz_full_w[5:0];
    wire b_zero_w;
    wire b_inf_w;
    wire b_nan_w;
    wire b_snan_w;
    assign b_zero_w = ~|unit_req_src2_i[62:0];
    assign b_inf_w = (&unit_req_src2_i[62:52]) && !(|unit_req_src2_i[51:0]);
    assign b_nan_w = (&unit_req_src2_i[62:52]) && (|unit_req_src2_i[51:0]);
    assign b_snan_w = b_nan_w && !unit_req_src2_i[51];
    reg [52:0] b_mantissa_r;
    reg [5:0] b_lz_r;
    reg signed [13:0] b_exponent_r;
    wire [52:0] b_normalized_w;
    reg [52:0] b_normalized_r;
    reg signed [13:0] b_adjusted_r;
    always @(posedge clk_i) begin
        b_normalized_r <= b_normalized_w;
        b_adjusted_r <= b_exponent_r - $signed({8'b0, b_lz_r});
    end
    assign b_normalized_w = b_mantissa_r << b_lz_r;
    wire sqrt_r;
    wire sign_r;
    wire [2:0] rm_r;
    wire special_r;
    wire [63:0] special_data_r;
    wire [4:0] special_flags_r;
    wire invalid_w;
    wire nan_w;
    assign invalid_w = a_snan_w || (!sqrt_i && b_snan_w)
        || (sqrt_i ? (unit_req_src1_i[63] && !a_zero_w && !a_nan_w)
                    : ((a_zero_w && b_zero_w) || (a_inf_w && b_inf_w)));
    assign nan_w = a_nan_w || (!sqrt_i && b_nan_w) || invalid_w;
    reg sqrt_capture_r;
    reg sign_capture_r;
    reg [2:0] rm_capture_r;
    reg special_capture_r;
    reg [63:0] special_data_capture_r;
    reg [4:0] special_flags_capture_r;
    always @(posedge clk_i) begin
        a_mantissa_r <= a_mantissa_w;
        b_mantissa_r <= b_mantissa_w;
        a_lz_r <= a_lz_w;
        b_lz_r <= b_lz_w;
        a_exponent_r <= |unit_req_src1_i[62:52]
            ? $signed({3'b0, unit_req_src1_i[62:52]}) : 14'sd1;
        b_exponent_r <= |unit_req_src2_i[62:52]
            ? $signed({3'b0, unit_req_src2_i[62:52]}) : 14'sd1;
        sqrt_capture_r <= sqrt_i;
        rm_capture_r <= unit_req_rm_i;
        sign_capture_r <= sqrt_i ? unit_req_src1_i[63]
            : unit_req_src1_i[63] ^ unit_req_src2_i[63];
        special_capture_r <= nan_w || a_zero_w || a_inf_w
            || (!sqrt_i && (b_zero_w || b_inf_w));
        special_flags_capture_r <= {invalid_w, (!sqrt_i && b_zero_w && !a_zero_w
            && !a_inf_w && !a_nan_w), 3'b0};
        if (nan_w) special_data_capture_r <= 64'h7ff8000000000000;
        else if (sqrt_i) special_data_capture_r <= unit_req_src1_i;
        else special_data_capture_r <= {unit_req_src1_i[63] ^ unit_req_src2_i[63],
            ((a_inf_w || b_zero_w) ? 63'h7ff0000000000000 : 63'b0)};
    end
    wire sqrt_next_w;
    assign sqrt_next_w = sqrt_capture_r;
    genvar j0;
    generate
        for (j0 = 0; j0 < 1; j0 = j0 + 16) begin : g_sqrt
            localparam WORD = (1 - j0 < 16) ? 1 - j0 : 16;
            // Each preserved local enable owns at most sixteen data bits.
            (* keep = "true", syn_preserve = 1 *) reg enable_r;
            reg [WORD-1:0] data_r;
            always @(posedge clk_i or negedge rst_n_i) begin
                if (!rst_n_i) enable_r <= 1'b0;
                else enable_r <= capture_next_i;
            end
            always @(posedge clk_i) begin
                if (enable_r) data_r <= sqrt_next_w;
            end
            assign sqrt_r = data_r;
        end
    endgenerate
    wire sign_next_w;
    assign sign_next_w = sign_capture_r;
    genvar j1;
    generate
        for (j1 = 0; j1 < 1; j1 = j1 + 16) begin : g_sign
            localparam WORD = (1 - j1 < 16) ? 1 - j1 : 16;
            // Each preserved local enable owns at most sixteen data bits.
            (* keep = "true", syn_preserve = 1 *) reg enable_r;
            reg [WORD-1:0] data_r;
            always @(posedge clk_i or negedge rst_n_i) begin
                if (!rst_n_i) enable_r <= 1'b0;
                else enable_r <= capture_next_i;
            end
            always @(posedge clk_i) begin
                if (enable_r) data_r <= sign_next_w;
            end
            assign sign_r = data_r;
        end
    endgenerate
    wire [2:0] rm_next_w;
    assign rm_next_w = rm_capture_r;
    genvar j2;
    generate
        for (j2 = 0; j2 < 3; j2 = j2 + 16) begin : g_rm
            localparam WORD = (3 - j2 < 16) ? 3 - j2 : 16;
            // Each preserved local enable owns at most sixteen data bits.
            (* keep = "true", syn_preserve = 1 *) reg enable_r;
            reg [WORD-1:0] data_r;
            always @(posedge clk_i or negedge rst_n_i) begin
                if (!rst_n_i) enable_r <= 1'b0;
                else enable_r <= capture_next_i;
            end
            always @(posedge clk_i) begin
                if (enable_r) data_r <= rm_next_w[j2 +: WORD];
            end
            assign rm_r[j2 +: WORD] = data_r;
        end
    endgenerate
    wire special_next_w;
    assign special_next_w = special_capture_r;
    genvar j3;
    generate
        for (j3 = 0; j3 < 1; j3 = j3 + 16) begin : g_special
            localparam WORD = (1 - j3 < 16) ? 1 - j3 : 16;
            // Each preserved local enable owns at most sixteen data bits.
            (* keep = "true", syn_preserve = 1 *) reg enable_r;
            reg [WORD-1:0] data_r;
            always @(posedge clk_i or negedge rst_n_i) begin
                if (!rst_n_i) enable_r <= 1'b0;
                else enable_r <= capture_next_i;
            end
            always @(posedge clk_i) begin
                if (enable_r) data_r <= special_next_w;
            end
            assign special_r = data_r;
        end
    endgenerate
    wire [63:0] special_data_next_w;
    assign special_data_next_w = special_data_capture_r;
    genvar j4;
    generate
        for (j4 = 0; j4 < 64; j4 = j4 + 16) begin : g_special_data
            localparam WORD = (64 - j4 < 16) ? 64 - j4 : 16;
            // Each preserved local enable owns at most sixteen data bits.
            (* keep = "true", syn_preserve = 1 *) reg enable_r;
            reg [WORD-1:0] data_r;
            always @(posedge clk_i or negedge rst_n_i) begin
                if (!rst_n_i) enable_r <= 1'b0;
                else enable_r <= capture_next_i;
            end
            always @(posedge clk_i) begin
                if (enable_r) data_r <= special_data_next_w[j4 +: WORD];
            end
            assign special_data_r[j4 +: WORD] = data_r;
        end
    endgenerate
    wire [4:0] special_flags_next_w;
    assign special_flags_next_w = special_flags_capture_r;
    genvar j5;
    generate
        for (j5 = 0; j5 < 5; j5 = j5 + 16) begin : g_special_flags
            localparam WORD = (5 - j5 < 16) ? 5 - j5 : 16;
            // Each preserved local enable owns at most sixteen data bits.
            (* keep = "true", syn_preserve = 1 *) reg enable_r;
            reg [WORD-1:0] data_r;
            always @(posedge clk_i or negedge rst_n_i) begin
                if (!rst_n_i) enable_r <= 1'b0;
                else enable_r <= capture_next_i;
            end
            always @(posedge clk_i) begin
                if (enable_r) data_r <= special_flags_next_w[j5 +: WORD];
            end
            assign special_flags_r[j5 +: WORD] = data_r;
        end
    endgenerate


    (* keep = "true", syn_preserve = 1 *) reg sqrt_seed0_r;
    (* keep = "true", syn_preserve = 1 *) reg sqrt_capture0_r;
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) sqrt_capture0_r <= 1'b0;
        else sqrt_capture0_r <= capture_next_i;
    end
    always @(posedge clk_i) begin
        if (sqrt_capture0_r) sqrt_seed0_r <= sqrt_capture_r;
    end
    (* keep = "true", syn_preserve = 1 *) reg sqrt_seed1_r;
    (* keep = "true", syn_preserve = 1 *) reg sqrt_capture1_r;
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) sqrt_capture1_r <= 1'b0;
        else sqrt_capture1_r <= capture_next_i;
    end
    always @(posedge clk_i) begin
        if (sqrt_capture1_r) sqrt_seed1_r <= sqrt_capture_r;
    end

    // Radix-four divider: three parallel trial remainders select digit 0..3.
    // Square root uses the same remainder register, with (8*root+d)*d trials.
    wire signed [13:0] exponent_r;
    wire [57:0] denominator_r;
    wire [57:0] denominator2_r;
    wire [57:0] denominator3_r;
    wire [57:0] remainder_r;
    wire [55:0] quotient_r;
    wire [111:0] radicand_r;
    wire [57:0] normalized_a_w;
    wire [57:0] normalized_b_w;
    assign normalized_a_w = {5'b0, a_normalized_r};
    assign normalized_b_w = {5'b0, b_normalized_r};
    wire [57:0] trial1_w;
    wire [57:0] trial2_w;
    wire [57:0] trial3_w;
    wire [57:0] root_trial3_r;
    wire [57:0] root_trial30_w;
    wire [57:0] root_trial31_w;
    wire [57:0] root_trial32_w;
    wire [57:0] root_trial33_w;
    assign root_trial30_w = (root_trial3_r << 2) - 58'd27;
    assign root_trial31_w = (root_trial3_r << 2) - 58'd3;
    assign root_trial32_w = (root_trial3_r << 2) + 58'd21;
    assign root_trial33_w = (root_trial3_r << 2) + 58'd45;
    wire [57:0] sqrt_trial1_w;
    assign sqrt_trial1_w = {quotient_r[54:0], 3'b001};
    wire [57:0] sqrt_trial2_w;
    assign sqrt_trial2_w = {quotient_r[53:0], 4'b0100};

    wire [57:0] dividend_w;
    wire [57:0] sqrt_dividend_w;
    wire [57:0] div_dividend_w;
    assign sqrt_dividend_w = (remainder_r << 4)
        | {54'b0, radicand_r[111:108]};
    assign div_dividend_w = remainder_r << 2;
    genvar mode_trial1;
    generate
        for (mode_trial1 = 0; mode_trial1 < 58; mode_trial1 = mode_trial1 + 16)
            begin : g_mode_trial1
            localparam WORD = (58 - mode_trial1 < 16) ? 58 - mode_trial1 : 16;
            (* keep = "true", syn_preserve = 1 *) reg mode_r;
            always @(posedge clk_i) begin
                mode_r <= (0 + mode_trial1/16) % 2 == 0 ? sqrt_seed0_r : sqrt_seed1_r;
            end
            assign trial1_w[mode_trial1 +: WORD] = mode_r
                ? sqrt_trial1_w[mode_trial1 +: WORD] : denominator_r[mode_trial1 +: WORD];
        end
    endgenerate
    genvar mode_trial2;
    generate
        for (mode_trial2 = 0; mode_trial2 < 58; mode_trial2 = mode_trial2 + 16)
            begin : g_mode_trial2
            localparam WORD = (58 - mode_trial2 < 16) ? 58 - mode_trial2 : 16;
            (* keep = "true", syn_preserve = 1 *) reg mode_r;
            always @(posedge clk_i) begin
                mode_r <= (4 + mode_trial2/16) % 2 == 0 ? sqrt_seed0_r : sqrt_seed1_r;
            end
            assign trial2_w[mode_trial2 +: WORD] = mode_r
                ? sqrt_trial2_w[mode_trial2 +: WORD] : denominator2_r[mode_trial2 +: WORD];
        end
    endgenerate
    genvar mode_trial3;
    generate
        for (mode_trial3 = 0; mode_trial3 < 58; mode_trial3 = mode_trial3 + 16)
            begin : g_mode_trial3
            localparam WORD = (58 - mode_trial3 < 16) ? 58 - mode_trial3 : 16;
            (* keep = "true", syn_preserve = 1 *) reg mode_r;
            always @(posedge clk_i) begin
                mode_r <= (8 + mode_trial3/16) % 2 == 0 ? sqrt_seed0_r : sqrt_seed1_r;
            end
            assign trial3_w[mode_trial3 +: WORD] = mode_r
                ? root_trial3_r[mode_trial3 +: WORD] : denominator3_r[mode_trial3 +: WORD];
        end
    endgenerate
    genvar mode_dividend;
    generate
        for (mode_dividend = 0; mode_dividend < 58; mode_dividend = mode_dividend + 16)
            begin : g_mode_dividend
            localparam WORD = (58 - mode_dividend < 16) ? 58 - mode_dividend : 16;
            (* keep = "true", syn_preserve = 1 *) reg mode_r;
            always @(posedge clk_i) begin
                mode_r <= (12 + mode_dividend/16) % 2 == 0 ? sqrt_seed0_r : sqrt_seed1_r;
            end
            assign dividend_w[mode_dividend +: WORD] = mode_r
                ? sqrt_dividend_w[mode_dividend +: WORD] : div_dividend_w[mode_dividend +: WORD];
        end
    endgenerate
    wire [58:0] difference1_w;
    wire [58:0] difference2_w;
    wire [58:0] difference3_w;
    assign difference1_w = {1'b0, dividend_w} - {1'b0, trial1_w};
    assign difference2_w = {1'b0, dividend_w} - {1'b0, trial2_w};
    assign difference3_w = {1'b0, dividend_w} - {1'b0, trial3_w};
    wire select0_w;
    wire select1_w;
    wire select2_w;
    wire select3_w;
    assign select0_w = difference1_w[58];
    assign select1_w = !difference1_w[58] && difference2_w[58];
    assign select2_w = !difference2_w[58] && difference3_w[58];
    assign select3_w = !difference3_w[58];
    wire [1:0] digit_w;
    wire [57:0] remainder_w;
    assign digit_w = {!difference2_w[58], select1_w || select3_w};
    assign remainder_w = ({58{select0_w}} & dividend_w)
        | ({58{select1_w}} & difference1_w[57:0])
        | ({58{select2_w}} & difference2_w[57:0])
        | ({58{select3_w}} & difference3_w[57:0]);
    // A fractional low bit carries the normalization decrement through one subtractor.
    wire signed [14:0] division_exponent_w;
    assign division_exponent_w = {a_adjusted_r, 1'b0}
        - {b_adjusted_r, (a_normalized_r < b_normalized_r)};
    wire [13:0] exponent_next_w;
    assign exponent_next_w = sqrt_r ? ((a_adjusted_r - 14'sd1023) >>> 1)
                : $signed(division_exponent_w[14:1]);
    genvar j6;
    generate
        for (j6 = 0; j6 < 14; j6 = j6 + 16) begin : g_exponent
            localparam WORD = (14 - j6 < 16) ? 14 - j6 : 16;
            // Each preserved local enable owns at most sixteen data bits.
            (* keep = "true", syn_preserve = 1 *) reg enable_r;
            reg [WORD-1:0] data_r;
            always @(posedge clk_i or negedge rst_n_i) begin
                if (!rst_n_i) enable_r <= 1'b0;
                else enable_r <= prepare_next_i;
            end
            always @(posedge clk_i) begin
                if (enable_r) data_r <= exponent_next_w[j6 +: WORD];
            end
            assign exponent_r[j6 +: WORD] = data_r;
        end
    endgenerate
    wire [57:0] denominator_next_w;
    assign denominator_next_w = normalized_b_w;
    genvar j7;
    generate
        for (j7 = 0; j7 < 58; j7 = j7 + 16) begin : g_denominator
            localparam WORD = (58 - j7 < 16) ? 58 - j7 : 16;
            // Each preserved local enable owns at most sixteen data bits.
            (* keep = "true", syn_preserve = 1 *) reg enable_r;
            reg [WORD-1:0] data_r;
            always @(posedge clk_i or negedge rst_n_i) begin
                if (!rst_n_i) enable_r <= 1'b0;
                else enable_r <= prepare_next_i;
            end
            always @(posedge clk_i) begin
                if (enable_r) data_r <= denominator_next_w[j7 +: WORD];
            end
            assign denominator_r[j7 +: WORD] = data_r;
        end
    endgenerate
    wire [57:0] denominator2_next_w;
    assign denominator2_next_w = normalized_b_w << 1;
    genvar j8;
    generate
        for (j8 = 0; j8 < 58; j8 = j8 + 16) begin : g_denominator2
            localparam WORD = (58 - j8 < 16) ? 58 - j8 : 16;
            // Each preserved local enable owns at most sixteen data bits.
            (* keep = "true", syn_preserve = 1 *) reg enable_r;
            reg [WORD-1:0] data_r;
            always @(posedge clk_i or negedge rst_n_i) begin
                if (!rst_n_i) enable_r <= 1'b0;
                else enable_r <= prepare_next_i;
            end
            always @(posedge clk_i) begin
                if (enable_r) data_r <= denominator2_next_w[j8 +: WORD];
            end
            assign denominator2_r[j8 +: WORD] = data_r;
        end
    endgenerate
    wire [57:0] denominator3_next_w;
    assign denominator3_next_w = normalized_b_w + (normalized_b_w << 1);
    genvar j9;
    generate
        for (j9 = 0; j9 < 58; j9 = j9 + 16) begin : g_denominator3
            localparam WORD = (58 - j9 < 16) ? 58 - j9 : 16;
            // Each preserved local enable owns at most sixteen data bits.
            (* keep = "true", syn_preserve = 1 *) reg enable_r;
            reg [WORD-1:0] data_r;
            always @(posedge clk_i or negedge rst_n_i) begin
                if (!rst_n_i) enable_r <= 1'b0;
                else enable_r <= prepare_next_i;
            end
            always @(posedge clk_i) begin
                if (enable_r) data_r <= denominator3_next_w[j9 +: WORD];
            end
            assign denominator3_r[j9 +: WORD] = data_r;
        end
    endgenerate
    wire [57:0] remainder_next_w;
    wire [57:0] division_remainder_w;
    assign division_remainder_w = (a_normalized_r < b_normalized_r
                ? (normalized_a_w << 1) - normalized_b_w : normalized_a_w - normalized_b_w);
    genvar initial_word;
    generate
        for (initial_word = 0; initial_word < 58; initial_word = initial_word + 16)
            begin : g_initial_mode
            localparam WORD = (58 - initial_word < 16) ? 58 - initial_word : 16;
            (* keep = "true", syn_preserve = 1 *) reg capture_r;
            (* keep = "true", syn_preserve = 1 *) reg mode_r;
            always @(posedge clk_i or negedge rst_n_i) begin
                if (!rst_n_i) capture_r <= 1'b0;
                else capture_r <= capture_next_i;
            end
            always @(posedge clk_i) begin
                if (capture_r) mode_r <= sqrt_capture_r;
            end
            assign remainder_next_w[initial_word +: WORD] = mode_r
                ? {WORD{1'b0}} : division_remainder_w[initial_word +: WORD];
        end
    endgenerate
    wire [57:0] remainder_iterate_w;
    assign remainder_iterate_w = remainder_w;
    genvar j10;
    generate
        for (j10 = 0; j10 < 58; j10 = j10 + 16) begin : g_remainder
            localparam WORD = (58 - j10 < 16) ? 58 - j10 : 16;
            // Each preserved local enable owns at most sixteen data bits.
            (* keep = "true", syn_preserve = 1 *) reg enable_r;
            reg [WORD-1:0] data_r;
            always @(posedge clk_i or negedge rst_n_i) begin
                if (!rst_n_i) enable_r <= 1'b0;
                else enable_r <= prepare_next_i;
            end
            (* keep = "true", syn_preserve = 1 *) reg iterate_r;
            always @(posedge clk_i or negedge rst_n_i) begin
                if (!rst_n_i) iterate_r <= 1'b0;
                else iterate_r <= iterate_next_i;
            end
            always @(posedge clk_i) begin
                if (enable_r) data_r <= remainder_next_w[j10 +: WORD];
                else if (iterate_r) data_r <= remainder_iterate_w[j10 +: WORD];
            end
            assign remainder_r[j10 +: WORD] = data_r;
        end
    endgenerate
    wire [55:0] quotient_next_w;
    assign quotient_next_w = sqrt_r ? 56'd0 : 56'd1;
    wire [55:0] quotient_iterate_w;
    assign quotient_iterate_w = {quotient_r[53:0], digit_w};
    genvar j11;
    generate
        for (j11 = 0; j11 < 56; j11 = j11 + 16) begin : g_quotient
            localparam WORD = (56 - j11 < 16) ? 56 - j11 : 16;
            // Each preserved local enable owns at most sixteen data bits.
            (* keep = "true", syn_preserve = 1 *) reg enable_r;
            reg [WORD-1:0] data_r;
            always @(posedge clk_i or negedge rst_n_i) begin
                if (!rst_n_i) enable_r <= 1'b0;
                else enable_r <= prepare_next_i;
            end
            (* keep = "true", syn_preserve = 1 *) reg iterate_r;
            always @(posedge clk_i or negedge rst_n_i) begin
                if (!rst_n_i) iterate_r <= 1'b0;
                else iterate_r <= iterate_next_i;
            end
            always @(posedge clk_i) begin
                if (enable_r) data_r <= quotient_next_w[j11 +: WORD];
                else if (iterate_r) data_r <= quotient_iterate_w[j11 +: WORD];
            end
            assign quotient_r[j11 +: WORD] = data_r;
        end
    endgenerate
    wire [57:0] root_trial3_next_w;
    assign root_trial3_next_w = 58'd9;
    wire [57:0] root_trial3_iterate_w;
    assign root_trial3_iterate_w = ({58{select0_w}} & root_trial30_w)
        | ({58{select1_w}} & root_trial31_w)
        | ({58{select2_w}} & root_trial32_w)
        | ({58{select3_w}} & root_trial33_w);
    genvar j12;
    generate
        for (j12 = 0; j12 < 58; j12 = j12 + 16) begin : g_root_trial3
            localparam WORD = (58 - j12 < 16) ? 58 - j12 : 16;
            // Each preserved local enable owns at most sixteen data bits.
            (* keep = "true", syn_preserve = 1 *) reg enable_r;
            reg [WORD-1:0] data_r;
            always @(posedge clk_i or negedge rst_n_i) begin
                if (!rst_n_i) enable_r <= 1'b0;
                else enable_r <= prepare_next_i;
            end
            (* keep = "true", syn_preserve = 1 *) reg iterate_r;
            always @(posedge clk_i or negedge rst_n_i) begin
                if (!rst_n_i) iterate_r <= 1'b0;
                else iterate_r <= iterate_next_i;
            end
            always @(posedge clk_i) begin
                if (enable_r) data_r <= root_trial3_next_w[j12 +: WORD];
                else if (iterate_r) data_r <= root_trial3_iterate_w[j12 +: WORD];
            end
            assign root_trial3_r[j12 +: WORD] = data_r;
        end
    endgenerate
    wire [111:0] radicand_next_w;
    assign radicand_next_w = {3'b0, a_normalized_r, 56'b0}
                << !a_adjusted_r[0];
    wire [111:0] radicand_iterate_w;
    assign radicand_iterate_w = radicand_r << 4;
    genvar j13;
    generate
        for (j13 = 0; j13 < 112; j13 = j13 + 16) begin : g_radicand
            localparam WORD = (112 - j13 < 16) ? 112 - j13 : 16;
            // Each preserved local enable owns at most sixteen data bits.
            (* keep = "true", syn_preserve = 1 *) reg enable_r;
            reg [WORD-1:0] data_r;
            always @(posedge clk_i or negedge rst_n_i) begin
                if (!rst_n_i) enable_r <= 1'b0;
                else enable_r <= prepare_next_i;
            end
            (* keep = "true", syn_preserve = 1 *) reg iterate_r;
            always @(posedge clk_i or negedge rst_n_i) begin
                if (!rst_n_i) iterate_r <= 1'b0;
                else iterate_r <= iterate_next_i;
            end
            always @(posedge clk_i) begin
                if (enable_r) data_r <= radicand_next_w[j13 +: WORD];
                else if (iterate_r) data_r <= radicand_iterate_w[j13 +: WORD];
            end
            assign radicand_r[j13 +: WORD] = data_r;
        end
    endgenerate


    // Tail stage 1: gradual-underflow alignment with sticky retained separately.
    wire [13:0] shift_distance_w;
    reg [5:0] shift_amount_r;
    wire [55:0] discarded_mask_r;
    assign shift_distance_w = $unsigned(-14'sd1022 - exponent_r);
    always @(posedge clk_i) begin
        shift_amount_r <= exponent_r >= -14'sd1022 ? 6'd0
            : shift_distance_w >= 14'd56 ? 6'd56
            : shift_distance_w[5:0];
    end
    // Three registered roots each fan out to at most seven local shift selectors.
    (* keep = "true", syn_preserve = 1 *) reg [2:0] shift_low_region_r;
    (* keep = "true", syn_preserve = 1 *) reg [2:0] shift_high_region_r;
    (* keep = "true", syn_preserve = 1 *) reg [5:0] shift_mask_region_r;
    always @(posedge clk_i) begin
        shift_low_region_r <= shift_amount_r[2:0];
        shift_high_region_r <= shift_amount_r[5:3];
        shift_mask_region_r <= shift_amount_r;
    end
    genvar mask_word;
    generate
        for (mask_word = 0; mask_word < 56; mask_word = mask_word + 8) begin : g_mask
            localparam WORD = (56 - mask_word < 8) ? 56 - mask_word : 8;
            (* keep = "true", syn_preserve = 1 *) reg [5:0] shift_r;
            wire [55:0] shifted_w;
            reg [WORD-1:0] data_r;
            assign shifted_w = ~(56'hffffffffffffff << shift_r);
            /* verilator lint_off UNUSEDSIGNAL */
            wire unused_shifted_w;
            assign unused_shifted_w = &{1'b0, shifted_w};
            /* verilator lint_on UNUSEDSIGNAL */
            always @(posedge clk_i) begin
                shift_r <= shift_mask_region_r;
                data_r <= shifted_w[mask_word +: WORD];
            end
            assign discarded_mask_r[mask_word +: WORD] = data_r;
        end
    endgenerate
    wire [55:0] partial_r;
    genvar partial_word;
    generate
        for (partial_word = 0; partial_word < 56; partial_word = partial_word + 8)
            begin : g_partial
            localparam WORD = (56 - partial_word < 8) ? 56 - partial_word : 8;
            (* keep = "true", syn_preserve = 1 *) reg [2:0] shift_r;
            wire [55:0] shifted_w;
            assign shifted_w = quotient_r >> shift_r;
            /* verilator lint_off UNUSEDSIGNAL */
            wire unused_shifted_w;
            assign unused_shifted_w = &{1'b0, shifted_w};
            /* verilator lint_on UNUSEDSIGNAL */
            always @(posedge clk_i) begin
                shift_r <= shift_low_region_r;
            end
            (* keep = "true", syn_preserve = 1 *) reg enable_r;
            reg [WORD-1:0] data_r;
            always @(posedge clk_i or negedge rst_n_i) begin
                if (!rst_n_i) enable_r <= 1'b0;
                else enable_r <= shift_next_i;
            end
            always @(posedge clk_i) begin
                if (enable_r) data_r <= shifted_w[partial_word +: WORD];
            end
            assign partial_r[partial_word +: WORD] = data_r;
        end
    endgenerate
    wire [55:0] aligned_r;
    wire sticky_r;
    wire signed [13:0] aligned_exponent_r;
    genvar j14;
    generate
        for (j14 = 0; j14 < 56; j14 = j14 + 8) begin : g_aligned
            localparam WORD = (56 - j14 < 8) ? 56 - j14 : 8;
            // Each preserved local enable owns at most sixteen data bits.
            (* keep = "true", syn_preserve = 1 *) reg [2:0] shift_r;
            reg [WORD-1:0] selected_w;
            (* keep = "true", syn_preserve = 1 *) reg enable_r;
            reg [WORD-1:0] data_r;
            always @(posedge clk_i) begin
                shift_r <= shift_high_region_r;
            end
            wire [55:0] candidate0_w;
            assign candidate0_w = partial_r >> 6'd0;
            /* verilator lint_off UNUSEDSIGNAL */
            wire unused_candidate0_w;
            assign unused_candidate0_w = &{1'b0, candidate0_w};
            /* verilator lint_on UNUSEDSIGNAL */
            wire [55:0] candidate1_w;
            assign candidate1_w = partial_r >> 6'd8;
            /* verilator lint_off UNUSEDSIGNAL */
            wire unused_candidate1_w;
            assign unused_candidate1_w = &{1'b0, candidate1_w};
            /* verilator lint_on UNUSEDSIGNAL */
            wire [55:0] candidate2_w;
            assign candidate2_w = partial_r >> 6'd16;
            /* verilator lint_off UNUSEDSIGNAL */
            wire unused_candidate2_w;
            assign unused_candidate2_w = &{1'b0, candidate2_w};
            /* verilator lint_on UNUSEDSIGNAL */
            wire [55:0] candidate3_w;
            assign candidate3_w = partial_r >> 6'd24;
            /* verilator lint_off UNUSEDSIGNAL */
            wire unused_candidate3_w;
            assign unused_candidate3_w = &{1'b0, candidate3_w};
            /* verilator lint_on UNUSEDSIGNAL */
            wire [55:0] candidate4_w;
            assign candidate4_w = partial_r >> 6'd32;
            /* verilator lint_off UNUSEDSIGNAL */
            wire unused_candidate4_w;
            assign unused_candidate4_w = &{1'b0, candidate4_w};
            /* verilator lint_on UNUSEDSIGNAL */
            wire [55:0] candidate5_w;
            assign candidate5_w = partial_r >> 6'd40;
            /* verilator lint_off UNUSEDSIGNAL */
            wire unused_candidate5_w;
            assign unused_candidate5_w = &{1'b0, candidate5_w};
            /* verilator lint_on UNUSEDSIGNAL */
            wire [55:0] candidate6_w;
            assign candidate6_w = partial_r >> 6'd48;
            /* verilator lint_off UNUSEDSIGNAL */
            wire unused_candidate6_w;
            assign unused_candidate6_w = &{1'b0, candidate6_w};
            /* verilator lint_on UNUSEDSIGNAL */
            wire [55:0] candidate7_w;
            assign candidate7_w = partial_r >> 6'd56;
            /* verilator lint_off UNUSEDSIGNAL */
            wire unused_candidate7_w;
            assign unused_candidate7_w = &{1'b0, candidate7_w};
            /* verilator lint_on UNUSEDSIGNAL */
            always @(*) begin
                selected_w = {WORD{1'b0}};
                case (shift_r)
                    3'd0: selected_w = candidate0_w[j14 +: WORD];
                    3'd1: selected_w = candidate1_w[j14 +: WORD];
                    3'd2: selected_w = candidate2_w[j14 +: WORD];
                    3'd3: selected_w = candidate3_w[j14 +: WORD];
                    3'd4: selected_w = candidate4_w[j14 +: WORD];
                    3'd5: selected_w = candidate5_w[j14 +: WORD];
                    3'd6: selected_w = candidate6_w[j14 +: WORD];
                    3'd7: selected_w = candidate7_w[j14 +: WORD];
                    default: selected_w = {WORD{1'b0}};
                endcase
            end
            always @(posedge clk_i or negedge rst_n_i) begin
                if (!rst_n_i) enable_r <= 1'b0;
                else enable_r <= align_next_i;
            end
            always @(posedge clk_i) begin
                if (enable_r) data_r <= selected_w;
            end
            assign aligned_r[j14 +: WORD] = data_r;
        end
    endgenerate
    // Parallel sixteen-bit reductions keep sticky out of a wide serial OR path.
    wire [55:0] masked_quotient_w;
    wire [7:0] sticky_parts_r;
    assign masked_quotient_w = quotient_r & discarded_mask_r;
    genvar sticky_rem;
    generate
        for (sticky_rem = 0; sticky_rem < 4; sticky_rem = sticky_rem + 1)
            begin : g_sticky_rem
            localparam LOW = sticky_rem * 16;
            localparam WORD = (58 - LOW < 16) ? 58 - LOW : 16;
            (* keep = "true", syn_preserve = 1 *) reg enable_r;
            reg data_r;
            always @(posedge clk_i or negedge rst_n_i) begin
                if (!rst_n_i) enable_r <= 1'b0;
                else enable_r <= shift_next_i;
            end
            always @(posedge clk_i) begin
                if (enable_r) data_r <= |remainder_r[LOW +: WORD];
            end
            assign sticky_parts_r[0 + sticky_rem] = data_r;
        end
    endgenerate
    genvar sticky_mask;
    generate
        for (sticky_mask = 0; sticky_mask < 4; sticky_mask = sticky_mask + 1)
            begin : g_sticky_mask
            localparam LOW = sticky_mask * 16;
            localparam WORD = (56 - LOW < 16) ? 56 - LOW : 16;
            (* keep = "true", syn_preserve = 1 *) reg enable_r;
            reg data_r;
            always @(posedge clk_i or negedge rst_n_i) begin
                if (!rst_n_i) enable_r <= 1'b0;
                else enable_r <= shift_next_i;
            end
            always @(posedge clk_i) begin
                if (enable_r) data_r <= |masked_quotient_w[LOW +: WORD];
            end
            assign sticky_parts_r[4 + sticky_mask] = data_r;
        end
    endgenerate
    wire sticky_next_w;
    assign sticky_next_w = |sticky_parts_r;
    genvar j15;
    generate
        for (j15 = 0; j15 < 1; j15 = j15 + 16) begin : g_sticky
            localparam WORD = (1 - j15 < 16) ? 1 - j15 : 16;
            // Each preserved local enable owns at most sixteen data bits.
            (* keep = "true", syn_preserve = 1 *) reg enable_r;
            reg [WORD-1:0] data_r;
            always @(posedge clk_i or negedge rst_n_i) begin
                if (!rst_n_i) enable_r <= 1'b0;
                else enable_r <= align_next_i;
            end
            always @(posedge clk_i) begin
                if (enable_r) data_r <= sticky_next_w;
            end
            assign sticky_r = data_r;
        end
    endgenerate
    wire [13:0] aligned_exponent_next_w;
    assign aligned_exponent_next_w = exponent_r < -14'sd1022
                ? -14'sd1022 : exponent_r;
    genvar j16;
    generate
        for (j16 = 0; j16 < 14; j16 = j16 + 16) begin : g_aligned_exponent
            localparam WORD = (14 - j16 < 16) ? 14 - j16 : 16;
            // Each preserved local enable owns at most sixteen data bits.
            (* keep = "true", syn_preserve = 1 *) reg enable_r;
            reg [WORD-1:0] data_r;
            always @(posedge clk_i or negedge rst_n_i) begin
                if (!rst_n_i) enable_r <= 1'b0;
                else enable_r <= shift_next_i;
            end
            always @(posedge clk_i) begin
                if (enable_r) data_r <= aligned_exponent_next_w[j16 +: WORD];
            end
            assign aligned_exponent_r[j16 +: WORD] = data_r;
        end
    endgenerate

    wire inexact_w;
    wire increment_w;
    assign inexact_w = (|aligned_r[1:0]) || sticky_r;
    assign increment_w = (rm_r == 3'd0 && aligned_r[1]
        && ((|aligned_r[0:0]) || sticky_r || aligned_r[2]))
        || (rm_r == 3'd2 && sign_r && inexact_w)
        || (rm_r == 3'd3 && !sign_r && inexact_w)
        || (rm_r == 3'd4 && aligned_r[1]);
    wire [53:0] rounded_r;
    wire inexact_r;
    wire [53:0] rounded_next_w;
    assign rounded_next_w = {1'b0, aligned_r[54:2]}
                + {{53{1'b0}}, increment_w};
    genvar j17;
    generate
        for (j17 = 0; j17 < 54; j17 = j17 + 16) begin : g_rounded
            localparam WORD = (54 - j17 < 16) ? 54 - j17 : 16;
            // Each preserved local enable owns at most sixteen data bits.
            (* keep = "true", syn_preserve = 1 *) reg enable_r;
            reg [WORD-1:0] data_r;
            always @(posedge clk_i or negedge rst_n_i) begin
                if (!rst_n_i) enable_r <= 1'b0;
                else enable_r <= round_next_i;
            end
            always @(posedge clk_i) begin
                if (enable_r) data_r <= rounded_next_w[j17 +: WORD];
            end
            assign rounded_r[j17 +: WORD] = data_r;
        end
    endgenerate
    wire inexact_next_w;
    assign inexact_next_w = inexact_w;
    genvar j18;
    generate
        for (j18 = 0; j18 < 1; j18 = j18 + 16) begin : g_inexact
            localparam WORD = (1 - j18 < 16) ? 1 - j18 : 16;
            // Each preserved local enable owns at most sixteen data bits.
            (* keep = "true", syn_preserve = 1 *) reg enable_r;
            reg [WORD-1:0] data_r;
            always @(posedge clk_i or negedge rst_n_i) begin
                if (!rst_n_i) enable_r <= 1'b0;
                else enable_r <= round_next_i;
            end
            always @(posedge clk_i) begin
                if (enable_r) data_r <= inexact_next_w;
            end
            assign inexact_r = data_r;
        end
    endgenerate

    wire [52:0] rounded_mantissa_r;
    wire signed [13:0] rounded_exponent_r;
    wire overflow_r;
    wire infinity_w;
    wire [10:0] encoded_exponent_r;
    wire [13:0] biased_exponent_w;
    assign biased_exponent_w = $unsigned(rounded_exponent_r + 14'sd1023);
    wire [52:0] rounded_mantissa_next_w;
    assign rounded_mantissa_next_w = rounded_r[53] ? rounded_r[53:1] : rounded_r[52:0];
    genvar j19;
    generate
        for (j19 = 0; j19 < 53; j19 = j19 + 16) begin : g_rounded_mantissa
            localparam WORD = (53 - j19 < 16) ? 53 - j19 : 16;
            // Each preserved local enable owns at most sixteen data bits.
            (* keep = "true", syn_preserve = 1 *) reg enable_r;
            reg [WORD-1:0] data_r;
            always @(posedge clk_i or negedge rst_n_i) begin
                if (!rst_n_i) enable_r <= 1'b0;
                else enable_r <= normalize_next_i;
            end
            always @(posedge clk_i) begin
                if (enable_r) data_r <= rounded_mantissa_next_w[j19 +: WORD];
            end
            assign rounded_mantissa_r[j19 +: WORD] = data_r;
        end
    endgenerate
    wire [13:0] rounded_exponent_next_w;
    assign rounded_exponent_next_w = aligned_exponent_r + (rounded_r[53] ? 14'sd1 : 14'sd0);
    genvar j20;
    generate
        for (j20 = 0; j20 < 14; j20 = j20 + 16) begin : g_rounded_exponent
            localparam WORD = (14 - j20 < 16) ? 14 - j20 : 16;
            // Each preserved local enable owns at most sixteen data bits.
            (* keep = "true", syn_preserve = 1 *) reg enable_r;
            reg [WORD-1:0] data_r;
            always @(posedge clk_i or negedge rst_n_i) begin
                if (!rst_n_i) enable_r <= 1'b0;
                else enable_r <= normalize_next_i;
            end
            always @(posedge clk_i) begin
                if (enable_r) data_r <= rounded_exponent_next_w[j20 +: WORD];
            end
            assign rounded_exponent_r[j20 +: WORD] = data_r;
        end
    endgenerate


    assign infinity_w = rm_r == 3'd0 || rm_r == 3'd4
        || (rm_r == 3'd2 && sign_r) || (rm_r == 3'd3 && !sign_r);
    wire overflow_next_w;
    assign overflow_next_w = rounded_exponent_r > 14'sd1023;
    genvar j21;
    generate
        for (j21 = 0; j21 < 1; j21 = j21 + 16) begin : g_overflow
            localparam WORD = (1 - j21 < 16) ? 1 - j21 : 16;
            // Each preserved local enable owns at most sixteen data bits.
            (* keep = "true", syn_preserve = 1 *) reg enable_r;
            reg [WORD-1:0] data_r;
            always @(posedge clk_i or negedge rst_n_i) begin
                if (!rst_n_i) enable_r <= 1'b0;
                else enable_r <= encode_next_i;
            end
            always @(posedge clk_i) begin
                if (enable_r) data_r <= overflow_next_w;
            end
            assign overflow_r = data_r;
        end
    endgenerate
    wire [10:0] encoded_exponent_next_w;
    assign encoded_exponent_next_w = rounded_mantissa_r[52] ? biased_exponent_w[10:0] : 11'b0;
    genvar j22;
    generate
        for (j22 = 0; j22 < 11; j22 = j22 + 16) begin : g_encoded_exponent
            localparam WORD = (11 - j22 < 16) ? 11 - j22 : 16;
            // Each preserved local enable owns at most sixteen data bits.
            (* keep = "true", syn_preserve = 1 *) reg enable_r;
            reg [WORD-1:0] data_r;
            always @(posedge clk_i or negedge rst_n_i) begin
                if (!rst_n_i) enable_r <= 1'b0;
                else enable_r <= encode_next_i;
            end
            always @(posedge clk_i) begin
                if (enable_r) data_r <= encoded_exponent_next_w[j22 +: WORD];
            end
            assign encoded_exponent_r[j22 +: WORD] = data_r;
        end
    endgenerate

    reg [4:0] packed_flags_w;
    always @(*) begin
        packed_flags_w = 5'b0;
        if (special_r) begin
            packed_flags_w = special_flags_r;
        end else if (overflow_r) begin
            packed_flags_w = 5'b00101;
        end else begin
            packed_flags_w = {3'b0, (encoded_exponent_r == 11'b0 && inexact_r), inexact_r};
        end
    end
    wire [63:0] finite_packet_w;
    wire [63:0] infinity_packet_w;
    wire [63:0] maximum_packet_w;
    assign finite_packet_w = {sign_r, encoded_exponent_r, rounded_mantissa_r[51:0]};
    assign infinity_packet_w = {sign_r, 63'h7ff0000000000000};
    assign maximum_packet_w = {sign_r, 63'h7fefffffffffffff};
    genvar packet_word;
    generate
        for (packet_word = 0; packet_word < 64; packet_word = packet_word + 16)
            begin : g_result
            edrv32_cpu2_fpu_divsqrt_result_word u_word (
                .clk_i(clk_i),
                .rst_n_i(rst_n_i),
                .capture_next_i(capture_next_i),
                .encode_next_i(encode_next_i),
                .pack_next_i(pack_next_i),
                .special_i(special_capture_r),
                .overflow_i(rounded_exponent_r > 14'sd1023),
                .infinity_i(infinity_w),
                .special_data_i(special_data_r[packet_word +: 16]),
                .finite_data_i(finite_packet_w[packet_word +: 16]),
                .infinity_data_i(infinity_packet_w[packet_word +: 16]),
                .maximum_data_i(maximum_packet_w[packet_word +: 16]),
                .result_o(result_o[packet_word +: 16])
            );
        end
    endgenerate
    wire [4:0] flags_next_w;
    assign flags_next_w = packed_flags_w;
    genvar j24;
    generate
        for (j24 = 0; j24 < 5; j24 = j24 + 16) begin : g_flags
            localparam WORD = (5 - j24 < 16) ? 5 - j24 : 16;
            // Each preserved local enable owns at most sixteen data bits.
            (* keep = "true", syn_preserve = 1 *) reg enable_r;
            reg [WORD-1:0] data_r;
            always @(posedge clk_i or negedge rst_n_i) begin
                if (!rst_n_i) enable_r <= 1'b0;
                else enable_r <= pack_next_i;
            end
            always @(posedge clk_i) begin
                if (enable_r) data_r <= flags_next_w[j24 +: WORD];
            end
            assign flags_o[j24 +: WORD] = data_r;
        end
    endgenerate

    // Unused leading-zero leaf and exponent carry do not affect packed fields.
    /* verilator lint_off UNUSEDSIGNAL */
    wire unused_w;
    assign unused_w = &{1'b0, a_lz_full_w[6:6], b_lz_full_w[6:6],
        division_exponent_w[0], aligned_r[55],
        biased_exponent_w[13:11]};
    /* verilator lint_on UNUSEDSIGNAL */
endmodule
