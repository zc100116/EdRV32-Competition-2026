// File: edrv32_gpu_perspective_absolute.v
// Spec: gpu-spec 2.13; microarch 4.6, 4.10.
// Description: Fixed-width registered arithmetic; global enable preserves pipeline alignment.
// Clock domain: clk_gpu.
module edrv32_gpu_perspective_absolute (
    // Clock and common pipeline enable.
    input wire clk_i,
    input wire en_i,

    // Arithmetic payload.
    input wire signed [69:0] value_i,
    input wire [9:0] exponent_i,
    output wire [69:0] magnitude_o,
    output wire sign_o,
    output wire [9:0] exponent_o
);
    reg [69:0] unused_value_0_r;
    reg [69:0] magnitude_0_r;
    reg sign_0_r;
    reg [9:0] exponent_0_r;
    reg carry_0_r;
    wire [20:0] sum_0_w;
    assign sum_0_w = {1'b0, (value_i[0 +: 20] ^ {20{value_i[69]}})} +
        {20'b0, value_i[69]};
    reg [69:0] unused_value_1_r;
    reg [69:0] magnitude_1_r;
    reg sign_1_r;
    reg [9:0] exponent_1_r;
    reg carry_1_r;
    wire [20:0] sum_1_w;
    assign sum_1_w = {1'b0, (unused_value_0_r[20 +: 20] ^ {20{sign_0_r}})} +
        {20'b0, carry_0_r};
    reg [69:0] unused_value_2_r;
    reg [69:0] magnitude_2_r;
    reg sign_2_r;
    reg [9:0] exponent_2_r;
    reg carry_2_r;
    wire [20:0] sum_2_w;
    assign sum_2_w = {1'b0, (unused_value_1_r[40 +: 20] ^ {20{sign_1_r}})} +
        {20'b0, carry_1_r};
    reg [69:0] unused_value_3_r;
    reg [69:0] magnitude_3_r;
    reg sign_3_r;
    reg [9:0] exponent_3_r;
    wire [10:0] unused_sum_3_w;
    assign unused_sum_3_w = {1'b0, (unused_value_2_r[60 +: 10] ^ {10{sign_2_r}})} +
        {10'b0, carry_2_r};
    assign magnitude_o = magnitude_3_r;
    assign sign_o = sign_3_r;
    assign exponent_o = exponent_3_r;
    always @(posedge clk_i) begin
        if (en_i) begin
            unused_value_0_r <= value_i;
            sign_0_r <= value_i[69];
            exponent_0_r <= exponent_i;
            magnitude_0_r <= 70'b0;
            magnitude_0_r[0 +: 20] <= sum_0_w[19:0];
            carry_0_r <= sum_0_w[20];
            unused_value_1_r <= unused_value_0_r;
            sign_1_r <= sign_0_r;
            exponent_1_r <= exponent_0_r;
            magnitude_1_r <= magnitude_0_r;
            magnitude_1_r[20 +: 20] <= sum_1_w[19:0];
            carry_1_r <= sum_1_w[20];
            unused_value_2_r <= unused_value_1_r;
            sign_2_r <= sign_1_r;
            exponent_2_r <= exponent_1_r;
            magnitude_2_r <= magnitude_1_r;
            magnitude_2_r[40 +: 20] <= sum_2_w[19:0];
            carry_2_r <= sum_2_w[20];
            unused_value_3_r <= unused_value_2_r;
            sign_3_r <= sign_2_r;
            exponent_3_r <= exponent_2_r;
            magnitude_3_r <= magnitude_2_r;
            magnitude_3_r[60 +: 10] <= unused_sum_3_w[9:0];
        end
    end
endmodule
