// File: edrv32_gpu2_setup_normalize.v
// Spec: gpu-v2-spec 2.6.1-5.
// Description: N48 of a signed82 complete intermediate, ties away from zero.
//              Two clocks: magnitude/leading-zero shift, rounding/renormalization.
// Clock domain: clk_gpu.
module edrv32_gpu2_setup_normalize (
    // Clock and control validity, data registers do not reset.
    input wire clk_i,
    input wire rst_n_i,
    input wire valid_i,

    // Full intermediate and physical exponent.
    input wire [81:0] mantissa_i,
    input wire [9:0] exponent_i,
    output wire valid_o,
    output wire [47:0] mantissa_o,
    output wire [9:0] exponent_o
);
    reg [1:0] valid_r;
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) valid_r <= 2'b0;
        else valid_r <= {valid_r[0], valid_i};
    end
    wire [81:0] magnitude_w;
    assign magnitude_w = mantissa_i[81] ? -mantissa_i : mantissa_i;
    // Binary leading-zero tree; no serial scan or dynamic vector slice.
    wire [127:0] shift0_w;
    assign shift0_w = {46'b0, magnitude_w};
    wire [6:0] zero_w;
    wire [127:0] shift1_w;
    assign zero_w[6] = ~|shift0_w[127:64];
    assign shift1_w = zero_w[6] ? {shift0_w[63:0], 64'b0} : shift0_w;
    wire [127:0] shift2_w;
    assign zero_w[5] = ~|shift1_w[127:96];
    assign shift2_w = zero_w[5] ? {shift1_w[95:0], 32'b0} : shift1_w;
    wire [127:0] shift3_w;
    assign zero_w[4] = ~|shift2_w[127:112];
    assign shift3_w = zero_w[4] ? {shift2_w[111:0], 16'b0} : shift2_w;
    wire [127:0] shift4_w;
    assign zero_w[3] = ~|shift3_w[127:120];
    assign shift4_w = zero_w[3] ? {shift3_w[119:0], 8'b0} : shift3_w;
    wire [127:0] shift5_w;
    assign zero_w[2] = ~|shift4_w[127:124];
    assign shift5_w = zero_w[2] ? {shift4_w[123:0], 4'b0} : shift4_w;
    wire [127:0] shift6_w;
    assign zero_w[1] = ~|shift5_w[127:126];
    assign shift6_w = zero_w[1] ? {shift5_w[125:0], 2'b0} : shift5_w;
    wire [127:0] shift7_w;
    assign zero_w[0] = ~shift6_w[127];
    assign shift7_w = zero_w[0] ? {shift6_w[126:0], 1'b0} : shift6_w;
    reg [47:0] truncated_r;
    reg [9:0] shifted_exponent_r;
    reg shifted_sign_r;
    reg shifted_zero_r;
    always @(posedge clk_i) begin
        truncated_r <= shift7_w[127:80];
        shifted_exponent_r <= exponent_i + 10'd81 - {3'b0, zero_w};
        shifted_sign_r <= mantissa_i[81];
        shifted_zero_r <= magnitude_w == 82'b0;
    end
    wire [47:0] rounded_w;
    wire [47:0] normalized_w;
    assign rounded_w = {1'b0, truncated_r[47:1]} + {47'b0, truncated_r[0]};
    assign normalized_w = rounded_w[47] ? {1'b0, rounded_w[47:1]} : rounded_w;
    reg [47:0] mantissa_r;
    reg [9:0] result_exponent_r;
    always @(posedge clk_i) begin
        mantissa_r <= shifted_sign_r ? -normalized_w : normalized_w;
        result_exponent_r <= shifted_zero_r ? 10'b0 :
            shifted_exponent_r + {9'b0, rounded_w[47]};
    end
    assign valid_o = valid_r[1];
    assign mantissa_o = mantissa_r;
    assign exponent_o = result_exponent_r;
    wire unused_w;
    assign unused_w = ^shift7_w[79:0];
endmodule
