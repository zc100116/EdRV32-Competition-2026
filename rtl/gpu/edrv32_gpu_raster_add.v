// File: edrv32_gpu_raster_add.v
// Spec: gpu-spec 2.13.7; microarch 4.6, 4.10.
// Description: Lossless 70-bit arithmetic with four registered 20-bit carry slices.
// Clock domain: clk_gpu.
module edrv32_gpu_raster_add (
    // Clock and shared pipeline enable.
    input wire clk_i,
    input wire en_i,

    // Arithmetic payload.
    input wire [69:0] a_i,
    input wire [69:0] b_i,
    output wire [69:0] sum_o
);
    reg [69:0] unused_a_0_r;
    reg [69:0] unused_b_0_r;
    reg [69:0] sum_0_r;
    reg carry_0_r;
    wire [20:0] unused_slice_0_w;
    assign unused_slice_0_w = {1'b0, a_i[0 +: 20]} +
        {1'b0, b_i[0 +: 20]};
    reg [69:0] unused_a_1_r;
    reg [69:0] unused_b_1_r;
    reg [69:0] sum_1_r;
    reg carry_1_r;
    wire [20:0] unused_slice_1_w;
    assign unused_slice_1_w = {1'b0, unused_a_0_r[20 +: 20]} +
        {1'b0, unused_b_0_r[20 +: 20]} + {20'b0, carry_0_r};
    reg [69:0] unused_a_2_r;
    reg [69:0] unused_b_2_r;
    reg [69:0] sum_2_r;
    reg carry_2_r;
    wire [20:0] unused_slice_2_w;
    assign unused_slice_2_w = {1'b0, unused_a_1_r[40 +: 20]} +
        {1'b0, unused_b_1_r[40 +: 20]} + {20'b0, carry_1_r};
    reg [69:0] unused_a_3_r;
    reg [69:0] unused_b_3_r;
    reg [69:0] sum_3_r;
    wire [10:0] unused_slice_3_w;
    assign unused_slice_3_w = {1'b0, unused_a_2_r[60 +: 10]} +
        {1'b0, unused_b_2_r[60 +: 10]} + {10'b0, carry_2_r};
    assign sum_o = sum_3_r;
    always @(posedge clk_i) begin
        if (en_i) begin
            unused_a_0_r <= a_i;
            unused_b_0_r <= b_i;
            sum_0_r <= 70'b0;
            sum_0_r[0 +: 20] <= unused_slice_0_w[19:0];
            carry_0_r <= unused_slice_0_w[20];
            unused_a_1_r <= unused_a_0_r;
            unused_b_1_r <= unused_b_0_r;
            sum_1_r <= sum_0_r;
            sum_1_r[20 +: 20] <= unused_slice_1_w[19:0];
            carry_1_r <= unused_slice_1_w[20];
            unused_a_2_r <= unused_a_1_r;
            unused_b_2_r <= unused_b_1_r;
            sum_2_r <= sum_1_r;
            sum_2_r[40 +: 20] <= unused_slice_2_w[19:0];
            carry_2_r <= unused_slice_2_w[20];
            unused_a_3_r <= unused_a_2_r;
            unused_b_3_r <= unused_b_2_r;
            sum_3_r <= sum_2_r;
            sum_3_r[60 +: 10] <= unused_slice_3_w[9:0];
        end
    end
endmodule
