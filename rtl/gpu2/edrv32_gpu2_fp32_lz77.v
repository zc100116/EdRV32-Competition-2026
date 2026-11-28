// File: edrv32_gpu2_fp32_lz77.v
// Spec: gpu-v2-spec 2.4.
// Description: Balanced leading-zero tree for normalization.
// Clock domain: clk_gpu (combinational).
module edrv32_gpu2_fp32_lz77 (
    input wire [76:0] data_i,
    output wire [6:0] count_o
);
    wire [127:0] padded_w;
    assign padded_w = {data_i, 51'b0};
    wire hit_2_0_w;
    wire [0:0] count_2_0_w;
    assign hit_2_0_w = padded_w[127] | padded_w[126];
    assign count_2_0_w = ~padded_w[127];
    wire hit_2_1_w;
    wire [0:0] count_2_1_w;
    assign hit_2_1_w = padded_w[125] | padded_w[124];
    assign count_2_1_w = ~padded_w[125];
    wire hit_2_2_w;
    wire [0:0] count_2_2_w;
    assign hit_2_2_w = padded_w[123] | padded_w[122];
    assign count_2_2_w = ~padded_w[123];
    wire hit_2_3_w;
    wire [0:0] count_2_3_w;
    assign hit_2_3_w = padded_w[121] | padded_w[120];
    assign count_2_3_w = ~padded_w[121];
    wire hit_2_4_w;
    wire [0:0] count_2_4_w;
    assign hit_2_4_w = padded_w[119] | padded_w[118];
    assign count_2_4_w = ~padded_w[119];
    wire hit_2_5_w;
    wire [0:0] count_2_5_w;
    assign hit_2_5_w = padded_w[117] | padded_w[116];
    assign count_2_5_w = ~padded_w[117];
    wire hit_2_6_w;
    wire [0:0] count_2_6_w;
    assign hit_2_6_w = padded_w[115] | padded_w[114];
    assign count_2_6_w = ~padded_w[115];
    wire hit_2_7_w;
    wire [0:0] count_2_7_w;
    assign hit_2_7_w = padded_w[113] | padded_w[112];
    assign count_2_7_w = ~padded_w[113];
    wire hit_2_8_w;
    wire [0:0] count_2_8_w;
    assign hit_2_8_w = padded_w[111] | padded_w[110];
    assign count_2_8_w = ~padded_w[111];
    wire hit_2_9_w;
    wire [0:0] count_2_9_w;
    assign hit_2_9_w = padded_w[109] | padded_w[108];
    assign count_2_9_w = ~padded_w[109];
    wire hit_2_10_w;
    wire [0:0] count_2_10_w;
    assign hit_2_10_w = padded_w[107] | padded_w[106];
    assign count_2_10_w = ~padded_w[107];
    wire hit_2_11_w;
    wire [0:0] count_2_11_w;
    assign hit_2_11_w = padded_w[105] | padded_w[104];
    assign count_2_11_w = ~padded_w[105];
    wire hit_2_12_w;
    wire [0:0] count_2_12_w;
    assign hit_2_12_w = padded_w[103] | padded_w[102];
    assign count_2_12_w = ~padded_w[103];
    wire hit_2_13_w;
    wire [0:0] count_2_13_w;
    assign hit_2_13_w = padded_w[101] | padded_w[100];
    assign count_2_13_w = ~padded_w[101];
    wire hit_2_14_w;
    wire [0:0] count_2_14_w;
    assign hit_2_14_w = padded_w[99] | padded_w[98];
    assign count_2_14_w = ~padded_w[99];
    wire hit_2_15_w;
    wire [0:0] count_2_15_w;
    assign hit_2_15_w = padded_w[97] | padded_w[96];
    assign count_2_15_w = ~padded_w[97];
    wire hit_2_16_w;
    wire [0:0] count_2_16_w;
    assign hit_2_16_w = padded_w[95] | padded_w[94];
    assign count_2_16_w = ~padded_w[95];
    wire hit_2_17_w;
    wire [0:0] count_2_17_w;
    assign hit_2_17_w = padded_w[93] | padded_w[92];
    assign count_2_17_w = ~padded_w[93];
    wire hit_2_18_w;
    wire [0:0] count_2_18_w;
    assign hit_2_18_w = padded_w[91] | padded_w[90];
    assign count_2_18_w = ~padded_w[91];
    wire hit_2_19_w;
    wire [0:0] count_2_19_w;
    assign hit_2_19_w = padded_w[89] | padded_w[88];
    assign count_2_19_w = ~padded_w[89];
    wire hit_2_20_w;
    wire [0:0] count_2_20_w;
    assign hit_2_20_w = padded_w[87] | padded_w[86];
    assign count_2_20_w = ~padded_w[87];
    wire hit_2_21_w;
    wire [0:0] count_2_21_w;
    assign hit_2_21_w = padded_w[85] | padded_w[84];
    assign count_2_21_w = ~padded_w[85];
    wire hit_2_22_w;
    wire [0:0] count_2_22_w;
    assign hit_2_22_w = padded_w[83] | padded_w[82];
    assign count_2_22_w = ~padded_w[83];
    wire hit_2_23_w;
    wire [0:0] count_2_23_w;
    assign hit_2_23_w = padded_w[81] | padded_w[80];
    assign count_2_23_w = ~padded_w[81];
    wire hit_2_24_w;
    wire [0:0] count_2_24_w;
    assign hit_2_24_w = padded_w[79] | padded_w[78];
    assign count_2_24_w = ~padded_w[79];
    wire hit_2_25_w;
    wire [0:0] count_2_25_w;
    assign hit_2_25_w = padded_w[77] | padded_w[76];
    assign count_2_25_w = ~padded_w[77];
    wire hit_2_26_w;
    wire [0:0] count_2_26_w;
    assign hit_2_26_w = padded_w[75] | padded_w[74];
    assign count_2_26_w = ~padded_w[75];
    wire hit_2_27_w;
    wire [0:0] count_2_27_w;
    assign hit_2_27_w = padded_w[73] | padded_w[72];
    assign count_2_27_w = ~padded_w[73];
    wire hit_2_28_w;
    wire [0:0] count_2_28_w;
    assign hit_2_28_w = padded_w[71] | padded_w[70];
    assign count_2_28_w = ~padded_w[71];
    wire hit_2_29_w;
    wire [0:0] count_2_29_w;
    assign hit_2_29_w = padded_w[69] | padded_w[68];
    assign count_2_29_w = ~padded_w[69];
    wire hit_2_30_w;
    wire [0:0] count_2_30_w;
    assign hit_2_30_w = padded_w[67] | padded_w[66];
    assign count_2_30_w = ~padded_w[67];
    wire hit_2_31_w;
    wire [0:0] count_2_31_w;
    assign hit_2_31_w = padded_w[65] | padded_w[64];
    assign count_2_31_w = ~padded_w[65];
    wire hit_2_32_w;
    wire [0:0] count_2_32_w;
    assign hit_2_32_w = padded_w[63] | padded_w[62];
    assign count_2_32_w = ~padded_w[63];
    wire hit_2_33_w;
    wire [0:0] count_2_33_w;
    assign hit_2_33_w = padded_w[61] | padded_w[60];
    assign count_2_33_w = ~padded_w[61];
    wire hit_2_34_w;
    wire [0:0] count_2_34_w;
    assign hit_2_34_w = padded_w[59] | padded_w[58];
    assign count_2_34_w = ~padded_w[59];
    wire hit_2_35_w;
    wire [0:0] count_2_35_w;
    assign hit_2_35_w = padded_w[57] | padded_w[56];
    assign count_2_35_w = ~padded_w[57];
    wire hit_2_36_w;
    wire [0:0] count_2_36_w;
    assign hit_2_36_w = padded_w[55] | padded_w[54];
    assign count_2_36_w = ~padded_w[55];
    wire hit_2_37_w;
    wire [0:0] count_2_37_w;
    assign hit_2_37_w = padded_w[53] | padded_w[52];
    assign count_2_37_w = ~padded_w[53];
    wire hit_2_38_w;
    wire [0:0] count_2_38_w;
    assign hit_2_38_w = padded_w[51] | padded_w[50];
    assign count_2_38_w = ~padded_w[51];
    wire hit_2_39_w;
    wire [0:0] count_2_39_w;
    assign hit_2_39_w = padded_w[49] | padded_w[48];
    assign count_2_39_w = ~padded_w[49];
    wire hit_2_40_w;
    wire [0:0] count_2_40_w;
    assign hit_2_40_w = padded_w[47] | padded_w[46];
    assign count_2_40_w = ~padded_w[47];
    wire hit_2_41_w;
    wire [0:0] count_2_41_w;
    assign hit_2_41_w = padded_w[45] | padded_w[44];
    assign count_2_41_w = ~padded_w[45];
    wire hit_2_42_w;
    wire [0:0] count_2_42_w;
    assign hit_2_42_w = padded_w[43] | padded_w[42];
    assign count_2_42_w = ~padded_w[43];
    wire hit_2_43_w;
    wire [0:0] count_2_43_w;
    assign hit_2_43_w = padded_w[41] | padded_w[40];
    assign count_2_43_w = ~padded_w[41];
    wire hit_2_44_w;
    wire [0:0] count_2_44_w;
    assign hit_2_44_w = padded_w[39] | padded_w[38];
    assign count_2_44_w = ~padded_w[39];
    wire hit_2_45_w;
    wire [0:0] count_2_45_w;
    assign hit_2_45_w = padded_w[37] | padded_w[36];
    assign count_2_45_w = ~padded_w[37];
    wire hit_2_46_w;
    wire [0:0] count_2_46_w;
    assign hit_2_46_w = padded_w[35] | padded_w[34];
    assign count_2_46_w = ~padded_w[35];
    wire hit_2_47_w;
    wire [0:0] count_2_47_w;
    assign hit_2_47_w = padded_w[33] | padded_w[32];
    assign count_2_47_w = ~padded_w[33];
    wire hit_2_48_w;
    wire [0:0] count_2_48_w;
    assign hit_2_48_w = padded_w[31] | padded_w[30];
    assign count_2_48_w = ~padded_w[31];
    wire hit_2_49_w;
    wire [0:0] count_2_49_w;
    assign hit_2_49_w = padded_w[29] | padded_w[28];
    assign count_2_49_w = ~padded_w[29];
    wire hit_2_50_w;
    wire [0:0] count_2_50_w;
    assign hit_2_50_w = padded_w[27] | padded_w[26];
    assign count_2_50_w = ~padded_w[27];
    wire hit_2_51_w;
    wire [0:0] count_2_51_w;
    assign hit_2_51_w = padded_w[25] | padded_w[24];
    assign count_2_51_w = ~padded_w[25];
    wire hit_2_52_w;
    wire [0:0] count_2_52_w;
    assign hit_2_52_w = padded_w[23] | padded_w[22];
    assign count_2_52_w = ~padded_w[23];
    wire hit_2_53_w;
    wire [0:0] count_2_53_w;
    assign hit_2_53_w = padded_w[21] | padded_w[20];
    assign count_2_53_w = ~padded_w[21];
    wire hit_2_54_w;
    wire [0:0] count_2_54_w;
    assign hit_2_54_w = padded_w[19] | padded_w[18];
    assign count_2_54_w = ~padded_w[19];
    wire hit_2_55_w;
    wire [0:0] count_2_55_w;
    assign hit_2_55_w = padded_w[17] | padded_w[16];
    assign count_2_55_w = ~padded_w[17];
    wire hit_2_56_w;
    wire [0:0] count_2_56_w;
    assign hit_2_56_w = padded_w[15] | padded_w[14];
    assign count_2_56_w = ~padded_w[15];
    wire hit_2_57_w;
    wire [0:0] count_2_57_w;
    assign hit_2_57_w = padded_w[13] | padded_w[12];
    assign count_2_57_w = ~padded_w[13];
    wire hit_2_58_w;
    wire [0:0] count_2_58_w;
    assign hit_2_58_w = padded_w[11] | padded_w[10];
    assign count_2_58_w = ~padded_w[11];
    wire hit_2_59_w;
    wire [0:0] count_2_59_w;
    assign hit_2_59_w = padded_w[9] | padded_w[8];
    assign count_2_59_w = ~padded_w[9];
    wire hit_2_60_w;
    wire [0:0] count_2_60_w;
    assign hit_2_60_w = padded_w[7] | padded_w[6];
    assign count_2_60_w = ~padded_w[7];
    wire hit_2_61_w;
    wire [0:0] count_2_61_w;
    assign hit_2_61_w = padded_w[5] | padded_w[4];
    assign count_2_61_w = ~padded_w[5];
    wire hit_2_62_w;
    wire [0:0] count_2_62_w;
    assign hit_2_62_w = padded_w[3] | padded_w[2];
    assign count_2_62_w = ~padded_w[3];
    wire hit_2_63_w;
    wire [0:0] count_2_63_w;
    assign hit_2_63_w = padded_w[1] | padded_w[0];
    assign count_2_63_w = ~padded_w[1];
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
    wire hit_4_8_w;
    wire [1:0] count_4_8_w;
    assign hit_4_8_w = hit_2_16_w | hit_2_17_w;
    assign count_4_8_w = hit_2_16_w ? {1'b0, count_2_16_w}
        : {1'b1, count_2_17_w};
    wire hit_4_9_w;
    wire [1:0] count_4_9_w;
    assign hit_4_9_w = hit_2_18_w | hit_2_19_w;
    assign count_4_9_w = hit_2_18_w ? {1'b0, count_2_18_w}
        : {1'b1, count_2_19_w};
    wire hit_4_10_w;
    wire [1:0] count_4_10_w;
    assign hit_4_10_w = hit_2_20_w | hit_2_21_w;
    assign count_4_10_w = hit_2_20_w ? {1'b0, count_2_20_w}
        : {1'b1, count_2_21_w};
    wire hit_4_11_w;
    wire [1:0] count_4_11_w;
    assign hit_4_11_w = hit_2_22_w | hit_2_23_w;
    assign count_4_11_w = hit_2_22_w ? {1'b0, count_2_22_w}
        : {1'b1, count_2_23_w};
    wire hit_4_12_w;
    wire [1:0] count_4_12_w;
    assign hit_4_12_w = hit_2_24_w | hit_2_25_w;
    assign count_4_12_w = hit_2_24_w ? {1'b0, count_2_24_w}
        : {1'b1, count_2_25_w};
    wire hit_4_13_w;
    wire [1:0] count_4_13_w;
    assign hit_4_13_w = hit_2_26_w | hit_2_27_w;
    assign count_4_13_w = hit_2_26_w ? {1'b0, count_2_26_w}
        : {1'b1, count_2_27_w};
    wire hit_4_14_w;
    wire [1:0] count_4_14_w;
    assign hit_4_14_w = hit_2_28_w | hit_2_29_w;
    assign count_4_14_w = hit_2_28_w ? {1'b0, count_2_28_w}
        : {1'b1, count_2_29_w};
    wire hit_4_15_w;
    wire [1:0] count_4_15_w;
    assign hit_4_15_w = hit_2_30_w | hit_2_31_w;
    assign count_4_15_w = hit_2_30_w ? {1'b0, count_2_30_w}
        : {1'b1, count_2_31_w};
    wire hit_4_16_w;
    wire [1:0] count_4_16_w;
    assign hit_4_16_w = hit_2_32_w | hit_2_33_w;
    assign count_4_16_w = hit_2_32_w ? {1'b0, count_2_32_w}
        : {1'b1, count_2_33_w};
    wire hit_4_17_w;
    wire [1:0] count_4_17_w;
    assign hit_4_17_w = hit_2_34_w | hit_2_35_w;
    assign count_4_17_w = hit_2_34_w ? {1'b0, count_2_34_w}
        : {1'b1, count_2_35_w};
    wire hit_4_18_w;
    wire [1:0] count_4_18_w;
    assign hit_4_18_w = hit_2_36_w | hit_2_37_w;
    assign count_4_18_w = hit_2_36_w ? {1'b0, count_2_36_w}
        : {1'b1, count_2_37_w};
    wire hit_4_19_w;
    wire [1:0] count_4_19_w;
    assign hit_4_19_w = hit_2_38_w | hit_2_39_w;
    assign count_4_19_w = hit_2_38_w ? {1'b0, count_2_38_w}
        : {1'b1, count_2_39_w};
    wire hit_4_20_w;
    wire [1:0] count_4_20_w;
    assign hit_4_20_w = hit_2_40_w | hit_2_41_w;
    assign count_4_20_w = hit_2_40_w ? {1'b0, count_2_40_w}
        : {1'b1, count_2_41_w};
    wire hit_4_21_w;
    wire [1:0] count_4_21_w;
    assign hit_4_21_w = hit_2_42_w | hit_2_43_w;
    assign count_4_21_w = hit_2_42_w ? {1'b0, count_2_42_w}
        : {1'b1, count_2_43_w};
    wire hit_4_22_w;
    wire [1:0] count_4_22_w;
    assign hit_4_22_w = hit_2_44_w | hit_2_45_w;
    assign count_4_22_w = hit_2_44_w ? {1'b0, count_2_44_w}
        : {1'b1, count_2_45_w};
    wire hit_4_23_w;
    wire [1:0] count_4_23_w;
    assign hit_4_23_w = hit_2_46_w | hit_2_47_w;
    assign count_4_23_w = hit_2_46_w ? {1'b0, count_2_46_w}
        : {1'b1, count_2_47_w};
    wire hit_4_24_w;
    wire [1:0] count_4_24_w;
    assign hit_4_24_w = hit_2_48_w | hit_2_49_w;
    assign count_4_24_w = hit_2_48_w ? {1'b0, count_2_48_w}
        : {1'b1, count_2_49_w};
    wire hit_4_25_w;
    wire [1:0] count_4_25_w;
    assign hit_4_25_w = hit_2_50_w | hit_2_51_w;
    assign count_4_25_w = hit_2_50_w ? {1'b0, count_2_50_w}
        : {1'b1, count_2_51_w};
    wire hit_4_26_w;
    wire [1:0] count_4_26_w;
    assign hit_4_26_w = hit_2_52_w | hit_2_53_w;
    assign count_4_26_w = hit_2_52_w ? {1'b0, count_2_52_w}
        : {1'b1, count_2_53_w};
    wire hit_4_27_w;
    wire [1:0] count_4_27_w;
    assign hit_4_27_w = hit_2_54_w | hit_2_55_w;
    assign count_4_27_w = hit_2_54_w ? {1'b0, count_2_54_w}
        : {1'b1, count_2_55_w};
    wire hit_4_28_w;
    wire [1:0] count_4_28_w;
    assign hit_4_28_w = hit_2_56_w | hit_2_57_w;
    assign count_4_28_w = hit_2_56_w ? {1'b0, count_2_56_w}
        : {1'b1, count_2_57_w};
    wire hit_4_29_w;
    wire [1:0] count_4_29_w;
    assign hit_4_29_w = hit_2_58_w | hit_2_59_w;
    assign count_4_29_w = hit_2_58_w ? {1'b0, count_2_58_w}
        : {1'b1, count_2_59_w};
    wire hit_4_30_w;
    wire [1:0] count_4_30_w;
    assign hit_4_30_w = hit_2_60_w | hit_2_61_w;
    assign count_4_30_w = hit_2_60_w ? {1'b0, count_2_60_w}
        : {1'b1, count_2_61_w};
    wire hit_4_31_w;
    wire [1:0] count_4_31_w;
    assign hit_4_31_w = hit_2_62_w | hit_2_63_w;
    assign count_4_31_w = hit_2_62_w ? {1'b0, count_2_62_w}
        : {1'b1, count_2_63_w};
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
    wire hit_8_4_w;
    wire [2:0] count_8_4_w;
    assign hit_8_4_w = hit_4_8_w | hit_4_9_w;
    assign count_8_4_w = hit_4_8_w ? {1'b0, count_4_8_w}
        : {1'b1, count_4_9_w};
    wire hit_8_5_w;
    wire [2:0] count_8_5_w;
    assign hit_8_5_w = hit_4_10_w | hit_4_11_w;
    assign count_8_5_w = hit_4_10_w ? {1'b0, count_4_10_w}
        : {1'b1, count_4_11_w};
    wire hit_8_6_w;
    wire [2:0] count_8_6_w;
    assign hit_8_6_w = hit_4_12_w | hit_4_13_w;
    assign count_8_6_w = hit_4_12_w ? {1'b0, count_4_12_w}
        : {1'b1, count_4_13_w};
    wire hit_8_7_w;
    wire [2:0] count_8_7_w;
    assign hit_8_7_w = hit_4_14_w | hit_4_15_w;
    assign count_8_7_w = hit_4_14_w ? {1'b0, count_4_14_w}
        : {1'b1, count_4_15_w};
    wire hit_8_8_w;
    wire [2:0] count_8_8_w;
    assign hit_8_8_w = hit_4_16_w | hit_4_17_w;
    assign count_8_8_w = hit_4_16_w ? {1'b0, count_4_16_w}
        : {1'b1, count_4_17_w};
    wire hit_8_9_w;
    wire [2:0] count_8_9_w;
    assign hit_8_9_w = hit_4_18_w | hit_4_19_w;
    assign count_8_9_w = hit_4_18_w ? {1'b0, count_4_18_w}
        : {1'b1, count_4_19_w};
    wire hit_8_10_w;
    wire [2:0] count_8_10_w;
    assign hit_8_10_w = hit_4_20_w | hit_4_21_w;
    assign count_8_10_w = hit_4_20_w ? {1'b0, count_4_20_w}
        : {1'b1, count_4_21_w};
    wire hit_8_11_w;
    wire [2:0] count_8_11_w;
    assign hit_8_11_w = hit_4_22_w | hit_4_23_w;
    assign count_8_11_w = hit_4_22_w ? {1'b0, count_4_22_w}
        : {1'b1, count_4_23_w};
    wire hit_8_12_w;
    wire [2:0] count_8_12_w;
    assign hit_8_12_w = hit_4_24_w | hit_4_25_w;
    assign count_8_12_w = hit_4_24_w ? {1'b0, count_4_24_w}
        : {1'b1, count_4_25_w};
    wire hit_8_13_w;
    wire [2:0] count_8_13_w;
    assign hit_8_13_w = hit_4_26_w | hit_4_27_w;
    assign count_8_13_w = hit_4_26_w ? {1'b0, count_4_26_w}
        : {1'b1, count_4_27_w};
    wire hit_8_14_w;
    wire [2:0] count_8_14_w;
    assign hit_8_14_w = hit_4_28_w | hit_4_29_w;
    assign count_8_14_w = hit_4_28_w ? {1'b0, count_4_28_w}
        : {1'b1, count_4_29_w};
    wire hit_8_15_w;
    wire [2:0] count_8_15_w;
    assign hit_8_15_w = hit_4_30_w | hit_4_31_w;
    assign count_8_15_w = hit_4_30_w ? {1'b0, count_4_30_w}
        : {1'b1, count_4_31_w};
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
    wire hit_16_2_w;
    wire [3:0] count_16_2_w;
    assign hit_16_2_w = hit_8_4_w | hit_8_5_w;
    assign count_16_2_w = hit_8_4_w ? {1'b0, count_8_4_w}
        : {1'b1, count_8_5_w};
    wire hit_16_3_w;
    wire [3:0] count_16_3_w;
    assign hit_16_3_w = hit_8_6_w | hit_8_7_w;
    assign count_16_3_w = hit_8_6_w ? {1'b0, count_8_6_w}
        : {1'b1, count_8_7_w};
    wire hit_16_4_w;
    wire [3:0] count_16_4_w;
    assign hit_16_4_w = hit_8_8_w | hit_8_9_w;
    assign count_16_4_w = hit_8_8_w ? {1'b0, count_8_8_w}
        : {1'b1, count_8_9_w};
    wire hit_16_5_w;
    wire [3:0] count_16_5_w;
    assign hit_16_5_w = hit_8_10_w | hit_8_11_w;
    assign count_16_5_w = hit_8_10_w ? {1'b0, count_8_10_w}
        : {1'b1, count_8_11_w};
    wire hit_16_6_w;
    wire [3:0] count_16_6_w;
    assign hit_16_6_w = hit_8_12_w | hit_8_13_w;
    assign count_16_6_w = hit_8_12_w ? {1'b0, count_8_12_w}
        : {1'b1, count_8_13_w};
    wire hit_16_7_w;
    wire [3:0] count_16_7_w;
    assign hit_16_7_w = hit_8_14_w | hit_8_15_w;
    assign count_16_7_w = hit_8_14_w ? {1'b0, count_8_14_w}
        : {1'b1, count_8_15_w};
    wire hit_32_0_w;
    wire [4:0] count_32_0_w;
    assign hit_32_0_w = hit_16_0_w | hit_16_1_w;
    assign count_32_0_w = hit_16_0_w ? {1'b0, count_16_0_w}
        : {1'b1, count_16_1_w};
    wire hit_32_1_w;
    wire [4:0] count_32_1_w;
    assign hit_32_1_w = hit_16_2_w | hit_16_3_w;
    assign count_32_1_w = hit_16_2_w ? {1'b0, count_16_2_w}
        : {1'b1, count_16_3_w};
    wire hit_32_2_w;
    wire [4:0] count_32_2_w;
    assign hit_32_2_w = hit_16_4_w | hit_16_5_w;
    assign count_32_2_w = hit_16_4_w ? {1'b0, count_16_4_w}
        : {1'b1, count_16_5_w};
    wire hit_32_3_w;
    wire [4:0] count_32_3_w;
    assign hit_32_3_w = hit_16_6_w | hit_16_7_w;
    assign count_32_3_w = hit_16_6_w ? {1'b0, count_16_6_w}
        : {1'b1, count_16_7_w};
    wire hit_64_0_w;
    wire [5:0] count_64_0_w;
    assign hit_64_0_w = hit_32_0_w | hit_32_1_w;
    assign count_64_0_w = hit_32_0_w ? {1'b0, count_32_0_w}
        : {1'b1, count_32_1_w};
    wire hit_64_1_w;
    wire [5:0] count_64_1_w;
    assign hit_64_1_w = hit_32_2_w | hit_32_3_w;
    assign count_64_1_w = hit_32_2_w ? {1'b0, count_32_2_w}
        : {1'b1, count_32_3_w};
    wire hit_128_0_w;
    wire [6:0] count_128_0_w;
    assign hit_128_0_w = hit_64_0_w | hit_64_1_w;
    assign count_128_0_w = hit_64_0_w ? {1'b0, count_64_0_w}
        : {1'b1, count_64_1_w};
    assign count_o = hit_128_0_w ? count_128_0_w : 7'd77;
endmodule
