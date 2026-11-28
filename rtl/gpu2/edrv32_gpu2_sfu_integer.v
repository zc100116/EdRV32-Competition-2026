// File: edrv32_gpu2_sfu_integer.v
// Spec: gpu-v2-spec 2.4, M-6 exact center residuals.
// Description: Exact conversion of a 24-bit magnitude times a binary power into normal FP32.
// Clock domain: clk_gpu (combinational); inputs are internal finite center/exponent quantities.
module edrv32_gpu2_sfu_integer (
    input wire sign_i,
    input wire [23:0] magnitude_i,
    input wire signed [7:0] exponent_i,
    output wire [31:0] data_o
);
    wire [6:0] lz_w;
    wire [22:0] fraction_w;
    wire [7:0] biased_w;
    edrv32_gpu2_fp32_lz24 u_lz (
        .data_i(magnitude_i),
        .count_o(lz_w)
    );
    assign fraction_w = magnitude_i[22:0] << lz_w[4:0];
    assign biased_w = exponent_i + 8'd150 - {1'b0, lz_w};
    assign data_o = magnitude_i == 0 ? 32'b0 : {sign_i, biased_w, fraction_w};
endmodule
