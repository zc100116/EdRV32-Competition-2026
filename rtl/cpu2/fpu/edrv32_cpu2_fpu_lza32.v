// File: edrv32_cpu2_fpu_lza32.v
// Spec: fpu-spec 5.2.
// Description: Parallel 32-bit anticipation group; parent reduction is in E7.
// Clock domain: clk_sys (combinational).
module edrv32_cpu2_fpu_lza32 (
    input wire [31:0] data_i,
    output wire hit_o,
    output wire [4:0] count_o
);
    wire hit_2_0_w;
    wire [0:0] count_2_0_w;
    assign hit_2_0_w = |data_i[31:30];
    assign count_2_0_w = ~data_i[31];
    wire hit_2_1_w;
    wire [0:0] count_2_1_w;
    assign hit_2_1_w = |data_i[29:28];
    assign count_2_1_w = ~data_i[29];
    wire hit_2_2_w;
    wire [0:0] count_2_2_w;
    assign hit_2_2_w = |data_i[27:26];
    assign count_2_2_w = ~data_i[27];
    wire hit_2_3_w;
    wire [0:0] count_2_3_w;
    assign hit_2_3_w = |data_i[25:24];
    assign count_2_3_w = ~data_i[25];
    wire hit_2_4_w;
    wire [0:0] count_2_4_w;
    assign hit_2_4_w = |data_i[23:22];
    assign count_2_4_w = ~data_i[23];
    wire hit_2_5_w;
    wire [0:0] count_2_5_w;
    assign hit_2_5_w = |data_i[21:20];
    assign count_2_5_w = ~data_i[21];
    wire hit_2_6_w;
    wire [0:0] count_2_6_w;
    assign hit_2_6_w = |data_i[19:18];
    assign count_2_6_w = ~data_i[19];
    wire hit_2_7_w;
    wire [0:0] count_2_7_w;
    assign hit_2_7_w = |data_i[17:16];
    assign count_2_7_w = ~data_i[17];
    wire hit_2_8_w;
    wire [0:0] count_2_8_w;
    assign hit_2_8_w = |data_i[15:14];
    assign count_2_8_w = ~data_i[15];
    wire hit_2_9_w;
    wire [0:0] count_2_9_w;
    assign hit_2_9_w = |data_i[13:12];
    assign count_2_9_w = ~data_i[13];
    wire hit_2_10_w;
    wire [0:0] count_2_10_w;
    assign hit_2_10_w = |data_i[11:10];
    assign count_2_10_w = ~data_i[11];
    wire hit_2_11_w;
    wire [0:0] count_2_11_w;
    assign hit_2_11_w = |data_i[9:8];
    assign count_2_11_w = ~data_i[9];
    wire hit_2_12_w;
    wire [0:0] count_2_12_w;
    assign hit_2_12_w = |data_i[7:6];
    assign count_2_12_w = ~data_i[7];
    wire hit_2_13_w;
    wire [0:0] count_2_13_w;
    assign hit_2_13_w = |data_i[5:4];
    assign count_2_13_w = ~data_i[5];
    wire hit_2_14_w;
    wire [0:0] count_2_14_w;
    assign hit_2_14_w = |data_i[3:2];
    assign count_2_14_w = ~data_i[3];
    wire hit_2_15_w;
    wire [0:0] count_2_15_w;
    assign hit_2_15_w = |data_i[1:0];
    assign count_2_15_w = ~data_i[1];
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
    assign hit_o = hit_32_0_w;
    assign count_o = count_32_0_w;
endmodule
