// File: edrv32_gpu2_setup_normalize.v
// Spec: gpu-v2-spec 2.6.1-5.
// Description: N48 of a signed82 complete intermediate, ties away from zero.
//              Four clocks: magnitude, leading zero, shift, rounding/renormalization.
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
    reg [3:0] valid_r;
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) valid_r <= 4'b0;
        else valid_r <= {valid_r[2:0], valid_i};
    end
    wire [81:0] magnitude_w;
    assign magnitude_w = mantissa_i[81] ? -mantissa_i : mantissa_i;
    // Card112: the old magnitude + serial LZ/shift path was 27 PDS levels.
    reg [81:0] s1_magnitude_r;
    reg [9:0] s1_exponent_r;
    reg s1_sign_r;
    always @(posedge clk_i) begin
        s1_magnitude_r <= magnitude_w;
        s1_exponent_r <= exponent_i + 10'd81;
        s1_sign_r <= mantissa_i[81];
    end
    // Balanced count/hit tree; every count is independent of the shifting data.
    wire [127:0] padded_w;
    assign padded_w = {46'b0, s1_magnitude_r};
    wire hit_2_0_w;
    wire [0:0] count_2_0_w;
    assign hit_2_0_w = |padded_w[127:126];
    assign count_2_0_w = ~padded_w[127];
    wire hit_2_1_w;
    wire [0:0] count_2_1_w;
    assign hit_2_1_w = |padded_w[125:124];
    assign count_2_1_w = ~padded_w[125];
    wire hit_2_2_w;
    wire [0:0] count_2_2_w;
    assign hit_2_2_w = |padded_w[123:122];
    assign count_2_2_w = ~padded_w[123];
    wire hit_2_3_w;
    wire [0:0] count_2_3_w;
    assign hit_2_3_w = |padded_w[121:120];
    assign count_2_3_w = ~padded_w[121];
    wire hit_2_4_w;
    wire [0:0] count_2_4_w;
    assign hit_2_4_w = |padded_w[119:118];
    assign count_2_4_w = ~padded_w[119];
    wire hit_2_5_w;
    wire [0:0] count_2_5_w;
    assign hit_2_5_w = |padded_w[117:116];
    assign count_2_5_w = ~padded_w[117];
    wire hit_2_6_w;
    wire [0:0] count_2_6_w;
    assign hit_2_6_w = |padded_w[115:114];
    assign count_2_6_w = ~padded_w[115];
    wire hit_2_7_w;
    wire [0:0] count_2_7_w;
    assign hit_2_7_w = |padded_w[113:112];
    assign count_2_7_w = ~padded_w[113];
    wire hit_2_8_w;
    wire [0:0] count_2_8_w;
    assign hit_2_8_w = |padded_w[111:110];
    assign count_2_8_w = ~padded_w[111];
    wire hit_2_9_w;
    wire [0:0] count_2_9_w;
    assign hit_2_9_w = |padded_w[109:108];
    assign count_2_9_w = ~padded_w[109];
    wire hit_2_10_w;
    wire [0:0] count_2_10_w;
    assign hit_2_10_w = |padded_w[107:106];
    assign count_2_10_w = ~padded_w[107];
    wire hit_2_11_w;
    wire [0:0] count_2_11_w;
    assign hit_2_11_w = |padded_w[105:104];
    assign count_2_11_w = ~padded_w[105];
    wire hit_2_12_w;
    wire [0:0] count_2_12_w;
    assign hit_2_12_w = |padded_w[103:102];
    assign count_2_12_w = ~padded_w[103];
    wire hit_2_13_w;
    wire [0:0] count_2_13_w;
    assign hit_2_13_w = |padded_w[101:100];
    assign count_2_13_w = ~padded_w[101];
    wire hit_2_14_w;
    wire [0:0] count_2_14_w;
    assign hit_2_14_w = |padded_w[99:98];
    assign count_2_14_w = ~padded_w[99];
    wire hit_2_15_w;
    wire [0:0] count_2_15_w;
    assign hit_2_15_w = |padded_w[97:96];
    assign count_2_15_w = ~padded_w[97];
    wire hit_2_16_w;
    wire [0:0] count_2_16_w;
    assign hit_2_16_w = |padded_w[95:94];
    assign count_2_16_w = ~padded_w[95];
    wire hit_2_17_w;
    wire [0:0] count_2_17_w;
    assign hit_2_17_w = |padded_w[93:92];
    assign count_2_17_w = ~padded_w[93];
    wire hit_2_18_w;
    wire [0:0] count_2_18_w;
    assign hit_2_18_w = |padded_w[91:90];
    assign count_2_18_w = ~padded_w[91];
    wire hit_2_19_w;
    wire [0:0] count_2_19_w;
    assign hit_2_19_w = |padded_w[89:88];
    assign count_2_19_w = ~padded_w[89];
    wire hit_2_20_w;
    wire [0:0] count_2_20_w;
    assign hit_2_20_w = |padded_w[87:86];
    assign count_2_20_w = ~padded_w[87];
    wire hit_2_21_w;
    wire [0:0] count_2_21_w;
    assign hit_2_21_w = |padded_w[85:84];
    assign count_2_21_w = ~padded_w[85];
    wire hit_2_22_w;
    wire [0:0] count_2_22_w;
    assign hit_2_22_w = |padded_w[83:82];
    assign count_2_22_w = ~padded_w[83];
    wire hit_2_23_w;
    wire [0:0] count_2_23_w;
    assign hit_2_23_w = |padded_w[81:80];
    assign count_2_23_w = ~padded_w[81];
    wire hit_2_24_w;
    wire [0:0] count_2_24_w;
    assign hit_2_24_w = |padded_w[79:78];
    assign count_2_24_w = ~padded_w[79];
    wire hit_2_25_w;
    wire [0:0] count_2_25_w;
    assign hit_2_25_w = |padded_w[77:76];
    assign count_2_25_w = ~padded_w[77];
    wire hit_2_26_w;
    wire [0:0] count_2_26_w;
    assign hit_2_26_w = |padded_w[75:74];
    assign count_2_26_w = ~padded_w[75];
    wire hit_2_27_w;
    wire [0:0] count_2_27_w;
    assign hit_2_27_w = |padded_w[73:72];
    assign count_2_27_w = ~padded_w[73];
    wire hit_2_28_w;
    wire [0:0] count_2_28_w;
    assign hit_2_28_w = |padded_w[71:70];
    assign count_2_28_w = ~padded_w[71];
    wire hit_2_29_w;
    wire [0:0] count_2_29_w;
    assign hit_2_29_w = |padded_w[69:68];
    assign count_2_29_w = ~padded_w[69];
    wire hit_2_30_w;
    wire [0:0] count_2_30_w;
    assign hit_2_30_w = |padded_w[67:66];
    assign count_2_30_w = ~padded_w[67];
    wire hit_2_31_w;
    wire [0:0] count_2_31_w;
    assign hit_2_31_w = |padded_w[65:64];
    assign count_2_31_w = ~padded_w[65];
    wire hit_2_32_w;
    wire [0:0] count_2_32_w;
    assign hit_2_32_w = |padded_w[63:62];
    assign count_2_32_w = ~padded_w[63];
    wire hit_2_33_w;
    wire [0:0] count_2_33_w;
    assign hit_2_33_w = |padded_w[61:60];
    assign count_2_33_w = ~padded_w[61];
    wire hit_2_34_w;
    wire [0:0] count_2_34_w;
    assign hit_2_34_w = |padded_w[59:58];
    assign count_2_34_w = ~padded_w[59];
    wire hit_2_35_w;
    wire [0:0] count_2_35_w;
    assign hit_2_35_w = |padded_w[57:56];
    assign count_2_35_w = ~padded_w[57];
    wire hit_2_36_w;
    wire [0:0] count_2_36_w;
    assign hit_2_36_w = |padded_w[55:54];
    assign count_2_36_w = ~padded_w[55];
    wire hit_2_37_w;
    wire [0:0] count_2_37_w;
    assign hit_2_37_w = |padded_w[53:52];
    assign count_2_37_w = ~padded_w[53];
    wire hit_2_38_w;
    wire [0:0] count_2_38_w;
    assign hit_2_38_w = |padded_w[51:50];
    assign count_2_38_w = ~padded_w[51];
    wire hit_2_39_w;
    wire [0:0] count_2_39_w;
    assign hit_2_39_w = |padded_w[49:48];
    assign count_2_39_w = ~padded_w[49];
    wire hit_2_40_w;
    wire [0:0] count_2_40_w;
    assign hit_2_40_w = |padded_w[47:46];
    assign count_2_40_w = ~padded_w[47];
    wire hit_2_41_w;
    wire [0:0] count_2_41_w;
    assign hit_2_41_w = |padded_w[45:44];
    assign count_2_41_w = ~padded_w[45];
    wire hit_2_42_w;
    wire [0:0] count_2_42_w;
    assign hit_2_42_w = |padded_w[43:42];
    assign count_2_42_w = ~padded_w[43];
    wire hit_2_43_w;
    wire [0:0] count_2_43_w;
    assign hit_2_43_w = |padded_w[41:40];
    assign count_2_43_w = ~padded_w[41];
    wire hit_2_44_w;
    wire [0:0] count_2_44_w;
    assign hit_2_44_w = |padded_w[39:38];
    assign count_2_44_w = ~padded_w[39];
    wire hit_2_45_w;
    wire [0:0] count_2_45_w;
    assign hit_2_45_w = |padded_w[37:36];
    assign count_2_45_w = ~padded_w[37];
    wire hit_2_46_w;
    wire [0:0] count_2_46_w;
    assign hit_2_46_w = |padded_w[35:34];
    assign count_2_46_w = ~padded_w[35];
    wire hit_2_47_w;
    wire [0:0] count_2_47_w;
    assign hit_2_47_w = |padded_w[33:32];
    assign count_2_47_w = ~padded_w[33];
    wire hit_2_48_w;
    wire [0:0] count_2_48_w;
    assign hit_2_48_w = |padded_w[31:30];
    assign count_2_48_w = ~padded_w[31];
    wire hit_2_49_w;
    wire [0:0] count_2_49_w;
    assign hit_2_49_w = |padded_w[29:28];
    assign count_2_49_w = ~padded_w[29];
    wire hit_2_50_w;
    wire [0:0] count_2_50_w;
    assign hit_2_50_w = |padded_w[27:26];
    assign count_2_50_w = ~padded_w[27];
    wire hit_2_51_w;
    wire [0:0] count_2_51_w;
    assign hit_2_51_w = |padded_w[25:24];
    assign count_2_51_w = ~padded_w[25];
    wire hit_2_52_w;
    wire [0:0] count_2_52_w;
    assign hit_2_52_w = |padded_w[23:22];
    assign count_2_52_w = ~padded_w[23];
    wire hit_2_53_w;
    wire [0:0] count_2_53_w;
    assign hit_2_53_w = |padded_w[21:20];
    assign count_2_53_w = ~padded_w[21];
    wire hit_2_54_w;
    wire [0:0] count_2_54_w;
    assign hit_2_54_w = |padded_w[19:18];
    assign count_2_54_w = ~padded_w[19];
    wire hit_2_55_w;
    wire [0:0] count_2_55_w;
    assign hit_2_55_w = |padded_w[17:16];
    assign count_2_55_w = ~padded_w[17];
    wire hit_2_56_w;
    wire [0:0] count_2_56_w;
    assign hit_2_56_w = |padded_w[15:14];
    assign count_2_56_w = ~padded_w[15];
    wire hit_2_57_w;
    wire [0:0] count_2_57_w;
    assign hit_2_57_w = |padded_w[13:12];
    assign count_2_57_w = ~padded_w[13];
    wire hit_2_58_w;
    wire [0:0] count_2_58_w;
    assign hit_2_58_w = |padded_w[11:10];
    assign count_2_58_w = ~padded_w[11];
    wire hit_2_59_w;
    wire [0:0] count_2_59_w;
    assign hit_2_59_w = |padded_w[9:8];
    assign count_2_59_w = ~padded_w[9];
    wire hit_2_60_w;
    wire [0:0] count_2_60_w;
    assign hit_2_60_w = |padded_w[7:6];
    assign count_2_60_w = ~padded_w[7];
    wire hit_2_61_w;
    wire [0:0] count_2_61_w;
    assign hit_2_61_w = |padded_w[5:4];
    assign count_2_61_w = ~padded_w[5];
    wire hit_2_62_w;
    wire [0:0] count_2_62_w;
    assign hit_2_62_w = |padded_w[3:2];
    assign count_2_62_w = ~padded_w[3];
    wire hit_2_63_w;
    wire [0:0] count_2_63_w;
    assign hit_2_63_w = |padded_w[1:0];
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
    reg [81:0] s2_magnitude_r;
    (* keep = "true", syn_preserve = 1 *) reg [55:0] s2_shift_r;
    reg [9:0] s2_exponent_r;
    reg s2_sign_r;
    reg s2_zero_r;
    always @(posedge clk_i) begin
        s2_magnitude_r <= s1_magnitude_r;
        s2_shift_r <= {8{count_128_0_w}};
        s2_exponent_r <= s1_exponent_r - {3'b0, count_128_0_w};
        s2_sign_r <= s1_sign_r;
        s2_zero_r <= !hit_128_0_w;
    end
    wire [127:0] shift7_w;
    // Eight leaves per stage, sixteen mux sinks per leaf; no new data edge.
    wire [127:0] shift_w [0:7];
    assign shift_w[0] = {46'b0, s2_magnitude_r};
    genvar stage;
    genvar bit_idx;
    generate
        for (stage = 0; stage < 7; stage = stage+1) begin : g_shift
            localparam STEP = 1 << stage;
            for (bit_idx = 0; bit_idx < 128; bit_idx = bit_idx+1) begin : g_bit
                localparam CONTROL = (bit_idx/16)*7 + stage;
                if (bit_idx >= STEP) begin : g_data
                    assign shift_w[stage+1][bit_idx] = s2_shift_r[CONTROL]
                        ? shift_w[stage][bit_idx-STEP] : shift_w[stage][bit_idx];
                end else begin : g_zero
                    assign shift_w[stage+1][bit_idx] = !s2_shift_r[CONTROL]
                        && shift_w[stage][bit_idx];
                end
            end
        end
    endgenerate
    assign shift7_w = shift_w[7];
    reg [47:0] truncated_r;
    reg [9:0] shifted_exponent_r;
    reg shifted_sign_r;
    reg shifted_zero_r;
    always @(posedge clk_i) begin
        truncated_r <= shift7_w[127:80];
        shifted_exponent_r <= s2_exponent_r;
        shifted_sign_r <= s2_sign_r;
        shifted_zero_r <= s2_zero_r;
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
    assign valid_o = valid_r[3];
    assign mantissa_o = mantissa_r;
    assign exponent_o = result_exponent_r;
    wire unused_w;
    assign unused_w = ^shift7_w[79:0];
endmodule
