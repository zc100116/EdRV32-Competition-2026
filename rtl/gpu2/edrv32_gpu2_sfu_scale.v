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
    wire [24:0] magnitude_w;
    wire [24:0] shifted_w;
    wire sticky_w;
    assign exponent_w = $signed({3'b0, data_i[30:23]}) - 11'sd127
        + $signed({scale_i[9], scale_i});
    assign delta_w = -11'sd126 - exponent_w;
    assign shift_w = exponent_w >= -11'sd126 ? 5'd0
        : delta_w > 11'sd24 ? 5'd25 : delta_w[4:0];
    assign magnitude_w = {1'b1, data_i[22:0], 1'b0};
    assign shifted_w = magnitude_w >> shift_w;
    assign sticky_w = |(magnitude_w & ~(25'h1ffffff << shift_w));
    reg [23:0] s1_magnitude_r;
    reg s1_increment_r;
    reg signed [10:0] s1_exponent_r;
    reg s1_zero_r;
    reg s1_sign_r;
    reg s1_special_r;
    reg [31:0] s1_special_data_r;
    always @(posedge clk_i) begin
        s1_magnitude_r <= shifted_w[24:1];
        s1_increment_r <= shifted_w[0] && (shifted_w[1] || sticky_w);
        s1_exponent_r <= exponent_w;
        s1_zero_r <= data_i[30:0] == 0;
        s1_sign_r <= data_i[31] ^ sign_i;
        s1_special_r <= special_i;
        s1_special_data_r <= special_data_i;
    end
    wire [23:0] s2_rounded_w;
    wire [7:0] s2_biased_w;
    assign s2_rounded_w = s1_magnitude_r + {23'b0, s1_increment_r};
    assign s2_biased_w = s1_exponent_r[7:0] + 8'd127;
    always @(posedge clk_i) begin
        data_o <= s1_special_r ? s1_special_data_r
            : s1_zero_r ? {s1_sign_r, 31'b0}
            : s1_exponent_r > 11'sd127 ? {s1_sign_r, 8'hff, 23'b0}
            : {s1_sign_r, s1_exponent_r < -11'sd126 ? {7'b0, s2_rounded_w[23]}
                : s2_biased_w, s2_rounded_w[22:0]};
    end
endmodule
