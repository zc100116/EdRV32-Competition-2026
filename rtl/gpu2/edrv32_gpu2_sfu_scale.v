// File: edrv32_gpu2_sfu_scale.v
// Spec: gpu-v2-spec 2.4; M-6 final two-edge SFU scaling/packing.
// Description: Exact binary scaling with RNE gradual underflow and arithmetic classification.
// Clock domain: clk_gpu. Arithmetic input is a finite normal or zero; front end owns specials.
module edrv32_gpu2_sfu_scale (
    // Clock and numerical result from an arithmetic engine.
    input wire clk_i,
    input wire [31:0] data_i,
    input wire signed [9:0] scale_i,
    input wire sign_i,
    input wire special_i,
    input wire [31:0] special_data_i,

    // Final scalar return after two sampling edges.
    output reg [31:0] data_o
);
    wire signed [10:0] exponent_w;
    wire signed [10:0] delta_w;
    wire [4:0] shift_w;
    assign exponent_w = $signed({3'b0, data_i[30:23]}) - 11'sd127
        + $signed({scale_i[9], scale_i});
    assign delta_w = -11'sd126 - exponent_w;
    assign shift_w = exponent_w >= -11'sd126 ? 5'd0
        : delta_w > 11'sd24 ? 5'd25 : delta_w[4:0];
    // Keep guard and jam separate; split the five shift muxes across the existing two edges.
    wire [25:0] low_shift_w [0:2];
    assign low_shift_w[0] = {1'b1, data_i[22:0], 2'b0};
    genvar low_stage;
    genvar low_bit;
    generate
        for (low_stage = 0; low_stage < 2; low_stage = low_stage+1) begin : g_low
            localparam STEP = 1 << low_stage;
            for (low_bit = 0; low_bit < 26; low_bit = low_bit+1) begin : g_bit
                localparam BIT = low_bit;
                if (BIT == 0) begin : g_jam
                    assign low_shift_w[low_stage+1][BIT] = shift_w[low_stage]
                        ? (|low_shift_w[low_stage][STEP:0]) : low_shift_w[low_stage][0];
                end else if (BIT+STEP < 26) begin : g_data
                    assign low_shift_w[low_stage+1][BIT] = shift_w[low_stage]
                        ? low_shift_w[low_stage][BIT+STEP] : low_shift_w[low_stage][BIT];
                end else begin : g_zero
                    assign low_shift_w[low_stage+1][BIT] = !shift_w[low_stage]
                        && low_shift_w[low_stage][BIT];
                end
            end
        end
    endgenerate
    reg [25:0] s1_partial_r;
    (* keep = "true", syn_preserve = 1 *) reg [11:0] s1_high_shift_r;
    reg signed [10:0] s1_exponent_r;
    reg s1_zero_r;
    reg s1_sign_r;
    reg s1_special_r;
    reg [31:0] s1_special_data_r;
    always @(posedge clk_i) begin
        s1_partial_r <= low_shift_w[2];
        s1_high_shift_r <= {4{shift_w[4:2]}};
        s1_exponent_r <= exponent_w;
        s1_zero_r <= data_i[30:0] == 0;
        s1_sign_r <= data_i[31] ^ sign_i;
        s1_special_r <= special_i;
        s1_special_data_r <= special_data_i;
    end
    wire [25:0] high_shift_w [0:3];
    assign high_shift_w[0] = s1_partial_r;
    genvar high_stage;
    genvar high_bit;
    generate
        for (high_stage = 0; high_stage < 3; high_stage = high_stage+1) begin : g_high
            localparam STEP = 4 << high_stage;
            for (high_bit = 0; high_bit < 26; high_bit = high_bit+1) begin : g_bit
                localparam CONTROL = (high_bit/7)*3 + high_stage;
                if (high_bit == 0) begin : g_jam
                    assign high_shift_w[high_stage+1][high_bit] = s1_high_shift_r[CONTROL]
                        ? (|high_shift_w[high_stage][STEP:0]) : high_shift_w[high_stage][0];
                end else if (high_bit+STEP < 26) begin : g_data
                    assign high_shift_w[high_stage+1][high_bit] = s1_high_shift_r[CONTROL]
                        ? high_shift_w[high_stage][high_bit+STEP]
                        : high_shift_w[high_stage][high_bit];
                end else begin : g_zero
                    assign high_shift_w[high_stage+1][high_bit] = !s1_high_shift_r[CONTROL]
                        && high_shift_w[high_stage][high_bit];
                end
            end
        end
    endgenerate
    wire increment_w;
    assign increment_w = high_shift_w[3][1] && (high_shift_w[3][2] || high_shift_w[3][0]);
    wire [23:0] s2_rounded_w;
    wire [7:0] s2_biased_w;
    assign s2_rounded_w = high_shift_w[3][25:2] + {23'b0, increment_w};
    assign s2_biased_w = s1_exponent_r[7:0] + 8'd127;
    always @(posedge clk_i) begin
        data_o <= s1_special_r ? s1_special_data_r
            : s1_zero_r ? {s1_sign_r, 31'b0}
            : s1_exponent_r > 11'sd127 ? {s1_sign_r, 8'hff, 23'b0}
            : {s1_sign_r, s1_exponent_r < -11'sd126 ? {7'b0, s2_rounded_w[23]}
                : s2_biased_w, s2_rounded_w[22:0]};
    end
endmodule
