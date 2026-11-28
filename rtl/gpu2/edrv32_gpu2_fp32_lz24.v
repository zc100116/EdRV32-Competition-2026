// File: edrv32_gpu2_fp32_lz24.v
// Spec: gpu-v2-spec 2.4.
// Description: Balanced leading-zero tree for normalization.
// Clock domain: clk_gpu (combinational).
module edrv32_gpu2_fp32_lz24 (
    input wire [23:0] data_i,
    output wire [6:0] count_o
);
    wire [31:0] padded_w;
    assign padded_w = {data_i, 8'b0};
    wire hit_2_0_w;
    wire [0:0] count_2_0_w;
    assign hit_2_0_w = padded_w[31] | padded_w[30];
    assign count_2_0_w = ~padded_w[31];
    wire hit_2_1_w;
    wire [0:0] count_2_1_w;
    assign hit_2_1_w = padded_w[29] | padded_w[28];
    assign count_2_1_w = ~padded_w[29];
    wire hit_2_2_w;
    wire [0:0] count_2_2_w;
    assign hit_2_2_w = padded_w[27] | padded_w[26];
    assign count_2_2_w = ~padded_w[27];
    wire hit_2_3_w;
    wire [0:0] count_2_3_w;
    assign hit_2_3_w = padded_w[25] | padded_w[24];
    assign count_2_3_w = ~padded_w[25];
    wire hit_2_4_w;
    wire [0:0] count_2_4_w;
    assign hit_2_4_w = padded_w[23] | padded_w[22];
    assign count_2_4_w = ~padded_w[23];
    wire hit_2_5_w;
    wire [0:0] count_2_5_w;
    assign hit_2_5_w = padded_w[21] | padded_w[20];
    assign count_2_5_w = ~padded_w[21];
    wire hit_2_6_w;
    wire [0:0] count_2_6_w;
    assign hit_2_6_w = padded_w[19] | padded_w[18];
    assign count_2_6_w = ~padded_w[19];
    wire hit_2_7_w;
    wire [0:0] count_2_7_w;
    assign hit_2_7_w = padded_w[17] | padded_w[16];
    assign count_2_7_w = ~padded_w[17];
    wire hit_2_8_w;
    wire [0:0] count_2_8_w;
    assign hit_2_8_w = padded_w[15] | padded_w[14];
    assign count_2_8_w = ~padded_w[15];
    wire hit_2_9_w;
    wire [0:0] count_2_9_w;
    assign hit_2_9_w = padded_w[13] | padded_w[12];
    assign count_2_9_w = ~padded_w[13];
    wire hit_2_10_w;
    wire [0:0] count_2_10_w;
    assign hit_2_10_w = padded_w[11] | padded_w[10];
    assign count_2_10_w = ~padded_w[11];
    wire hit_2_11_w;
    wire [0:0] count_2_11_w;
    assign hit_2_11_w = padded_w[9] | padded_w[8];
    assign count_2_11_w = ~padded_w[9];
    wire hit_2_12_w;
    wire [0:0] count_2_12_w;
    assign hit_2_12_w = padded_w[7] | padded_w[6];
    assign count_2_12_w = ~padded_w[7];
    wire hit_2_13_w;
    wire [0:0] count_2_13_w;
    assign hit_2_13_w = padded_w[5] | padded_w[4];
    assign count_2_13_w = ~padded_w[5];
    wire hit_2_14_w;
    wire [0:0] count_2_14_w;
    assign hit_2_14_w = padded_w[3] | padded_w[2];
    assign count_2_14_w = ~padded_w[3];
    wire hit_2_15_w;
    wire [0:0] count_2_15_w;
    assign hit_2_15_w = padded_w[1] | padded_w[0];
    assign count_2_15_w = ~padded_w[1];
    wire hit_4_0_w;
    wire [1:0] count_4_0_w;
    assign hit_4_0_w = hit_2_0_w | hit_2_1_w;
    assign count_4_0_w = hit_2_0_w ? {1'b0, count_2_0_w}
        : {1'b1, count_2_1_w};
    wire hit_4_1_w;
    wire [1:0] count_4_1_w;
    assign hit_4_1_w = hit_2_2_w | hit_2_3_w;
    assign count_4_1_w = hit_2_2_w ? {1'b0, count_2_2_w}
        : {1'b1, count_2_3_w};
    wire hit_4_2_w;
    wire [1:0] count_4_2_w;
    assign hit_4_2_w = hit_2_4_w | hit_2_5_w;
    assign count_4_2_w = hit_2_4_w ? {1'b0, count_2_4_w}
        : {1'b1, count_2_5_w};
    wire hit_4_3_w;
    wire [1:0] count_4_3_w;
    assign hit_4_3_w = hit_2_6_w | hit_2_7_w;
    assign count_4_3_w = hit_2_6_w ? {1'b0, count_2_6_w}
        : {1'b1, count_2_7_w};
    wire hit_4_4_w;
    wire [1:0] count_4_4_w;
    assign hit_4_4_w = hit_2_8_w | hit_2_9_w;
    assign count_4_4_w = hit_2_8_w ? {1'b0, count_2_8_w}
        : {1'b1, count_2_9_w};
    wire hit_4_5_w;
    wire [1:0] count_4_5_w;
    assign hit_4_5_w = hit_2_10_w | hit_2_11_w;
    assign count_4_5_w = hit_2_10_w ? {1'b0, count_2_10_w}
        : {1'b1, count_2_11_w};
    wire hit_4_6_w;
    wire [1:0] count_4_6_w;
    assign hit_4_6_w = hit_2_12_w | hit_2_13_w;
    assign count_4_6_w = hit_2_12_w ? {1'b0, count_2_12_w}
        : {1'b1, count_2_13_w};
    wire hit_4_7_w;
    wire [1:0] count_4_7_w;
    assign hit_4_7_w = hit_2_14_w | hit_2_15_w;
    assign count_4_7_w = hit_2_14_w ? {1'b0, count_2_14_w}
        : {1'b1, count_2_15_w};
    wire hit_8_0_w;
    wire [2:0] count_8_0_w;
    assign hit_8_0_w = hit_4_0_w | hit_4_1_w;
    assign count_8_0_w = hit_4_0_w ? {1'b0, count_4_0_w}
        : {1'b1, count_4_1_w};
    wire hit_8_1_w;
    wire [2:0] count_8_1_w;
    assign hit_8_1_w = hit_4_2_w | hit_4_3_w;
    assign count_8_1_w = hit_4_2_w ? {1'b0, count_4_2_w}
        : {1'b1, count_4_3_w};
    wire hit_8_2_w;
    wire [2:0] count_8_2_w;
    assign hit_8_2_w = hit_4_4_w | hit_4_5_w;
    assign count_8_2_w = hit_4_4_w ? {1'b0, count_4_4_w}
        : {1'b1, count_4_5_w};
    wire hit_8_3_w;
    wire [2:0] count_8_3_w;
    assign hit_8_3_w = hit_4_6_w | hit_4_7_w;
    assign count_8_3_w = hit_4_6_w ? {1'b0, count_4_6_w}
        : {1'b1, count_4_7_w};
    wire hit_16_0_w;
    wire [3:0] count_16_0_w;
    assign hit_16_0_w = hit_8_0_w | hit_8_1_w;
    assign count_16_0_w = hit_8_0_w ? {1'b0, count_8_0_w}
        : {1'b1, count_8_1_w};
    wire hit_16_1_w;
    wire [3:0] count_16_1_w;
    assign hit_16_1_w = hit_8_2_w | hit_8_3_w;
    assign count_16_1_w = hit_8_2_w ? {1'b0, count_8_2_w}
        : {1'b1, count_8_3_w};
    wire hit_32_0_w;
    wire [4:0] count_32_0_w;
    assign hit_32_0_w = hit_16_0_w | hit_16_1_w;
    assign count_32_0_w = hit_16_0_w ? {1'b0, count_16_0_w}
        : {1'b1, count_16_1_w};
    assign count_o = hit_32_0_w ? {2'b0, count_32_0_w} : 7'd24;
endmodule
