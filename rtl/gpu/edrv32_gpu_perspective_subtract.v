// File: edrv32_gpu_perspective_subtract.v
// Spec: gpu-spec 2.13; microarch 4.6, 4.10.
// Description: Fixed-width registered arithmetic; global enable preserves pipeline alignment.
// Clock domain: clk_gpu.
module edrv32_gpu_perspective_subtract (
    // Clock and common pipeline enable.
    input wire clk_i,
    input wire en_i,

    // Arithmetic payload.
    input wire [28:0] a_i,
    input wire [28:0] b_i,
    output wire [28:0] normal_o,

    // Shared delay RAM: 25-cycle bypass and 14-cycle exponent storage.
    output wire [28:0] delay_bypass_wr_data_o,
    input wire [28:0] delay_bypass_rd_data_i,
    output wire [9:0] delay_exponent_wr_data_o,
    input wire [9:0] delay_exponent_rd_data_i
);
    reg [28:0] a_r;
    reg [28:0] b_r;
    reg [9:0] maximum_r;
    reg [9:0] difference_a_r [0:6];
    reg [9:0] difference_b_r [0:6];
    reg [21:0] aligned_a_r [0:6];
    reg [21:0] aligned_b_r [0:6];
    reg sign_a_r [0:8];
    reg sign_b_r [0:8];
    reg [24:0] bypass_valid_r;
    wire [28:0] normalized_w;
    reg [19:0] round_low_a_r;
    reg round_carry_a_r;
    reg round_high_a_r;
    reg [21:0] rounded_a_r;
    reg [19:0] sign_low_a_r;
    reg sign_carry_a_r;
    reg [21:0] unused_sign_magnitude_a_r;
    reg sign_negative_a_r;
    reg [22:0] signed_a_r;
    wire [20:0] round_low_a_w;
    wire [2:0] unused_round_high_a_w;
    wire [20:0] sign_low_a_w;
    wire [3:0] unused_sign_high_a_w;
    assign round_low_a_w = {1'b0, aligned_a_r[6][20:1]} +
        {20'b0, aligned_a_r[6][0]};
    assign unused_round_high_a_w = {2'b0, round_high_a_r} +
        {2'b0, round_carry_a_r};
    assign sign_low_a_w = {1'b0, (rounded_a_r[19:0] ^ {20{sign_a_r[8]}})} +
        {20'b0, sign_a_r[8]};
    assign unused_sign_high_a_w =
        {1'b0, ({1'b0, unused_sign_magnitude_a_r[21:20]} ^ {3{sign_negative_a_r}})} +
        {3'b0, sign_carry_a_r};
    reg [19:0] round_low_b_r;
    reg round_carry_b_r;
    reg round_high_b_r;
    reg [21:0] rounded_b_r;
    reg [19:0] sign_low_b_r;
    reg sign_carry_b_r;
    reg [21:0] unused_sign_magnitude_b_r;
    reg sign_negative_b_r;
    reg [22:0] signed_b_r;
    wire [20:0] round_low_b_w;
    wire [2:0] unused_round_high_b_w;
    wire [20:0] sign_low_b_w;
    wire [3:0] unused_sign_high_b_w;
    assign round_low_b_w = {1'b0, aligned_b_r[6][20:1]} +
        {20'b0, aligned_b_r[6][0]};
    assign unused_round_high_b_w = {2'b0, round_high_b_r} +
        {2'b0, round_carry_b_r};
    assign sign_low_b_w = {1'b0, (rounded_b_r[19:0] ^ {20{sign_b_r[8]}})} +
        {20'b0, sign_b_r[8]};
    assign unused_sign_high_b_w =
        {1'b0, ({1'b0, unused_sign_magnitude_b_r[21:20]} ^ {3{sign_negative_b_r}})} +
        {3'b0, sign_carry_b_r};
    reg [19:0] subtract_low_r;
    reg subtract_carry_r;
    reg [2:0] subtract_a_r;
    reg [2:0] subtract_b_r;
    reg [22:0] difference_r;
    wire [20:0] subtract_low_w;
    wire [3:0] unused_subtract_high_w;
    assign subtract_low_w = {1'b0, signed_a_r[19:0]} +
        {1'b0, ~signed_b_r[19:0]} + 21'd1;
    assign unused_subtract_high_w = {1'b0, subtract_a_r} +
        {1'b0, ~subtract_b_r} + {3'b0, subtract_carry_r};
    reg [22:0] unused_absolute_value_r;
    reg absolute_sign_r;
    reg [19:0] absolute_low_r;
    reg absolute_carry_r;
    reg [22:0] absolute_r;
    reg sign_r;
    wire [20:0] absolute_low_w;
    wire [3:0] unused_absolute_high_w;
    assign absolute_low_w = {1'b0, (difference_r[19:0] ^ {20{difference_r[22]}})} +
        {20'b0, difference_r[22]};
    assign unused_absolute_high_w =
        {1'b0, (unused_absolute_value_r[22:20] ^ {3{absolute_sign_r}})} +
        {3'b0, absolute_carry_r};
    assign delay_bypass_wr_data_o = b_i[17:0] == 0 ? a_i :
        {b_i[28:19], !b_i[18], b_i[17:0]};
    assign delay_exponent_wr_data_o = maximum_r - 10'd3;
    assign normal_o = bypass_valid_r[24] ? delay_bypass_rd_data_i : normalized_w;
    edrv32_gpu_perspective_normal u_normal (
        .clk_i(clk_i),
        .en_i(en_i),
        .magnitude_i({47'b0, absolute_r}),
        .sign_i(sign_r),
        .exponent_i(delay_exponent_rd_data_i),
        .normal_o(normalized_w)
    );
    always @(posedge clk_i) begin
        if (en_i) begin
            a_r <= a_i;
            b_r <= b_i;
            maximum_r <= $signed(a_i[28:19]) > $signed(b_i[28:19]) ?
                a_i[28:19] : b_i[28:19];
            bypass_valid_r <= {bypass_valid_r[23:0], a_i[17:0] == 0 || b_i[17:0] == 0};
            difference_a_r[1] <= maximum_r - a_r[28:19];
            difference_b_r[1] <= maximum_r - b_r[28:19];
            aligned_a_r[1] <= {a_r[17:0], 4'b0};
            aligned_b_r[1] <= {b_r[17:0], 4'b0};
            sign_a_r[1] <= a_r[18];
            sign_b_r[1] <= b_r[18];
            difference_a_r[2] <= difference_a_r[1];
            aligned_a_r[2] <= difference_a_r[1][0] ?
                aligned_a_r[1] >> 1 : aligned_a_r[1];
            difference_b_r[2] <= difference_b_r[1];
            aligned_b_r[2] <= difference_b_r[1][0] ?
                aligned_b_r[1] >> 1 : aligned_b_r[1];
            difference_a_r[3] <= difference_a_r[2];
            aligned_a_r[3] <= difference_a_r[2][1] ?
                aligned_a_r[2] >> 2 : aligned_a_r[2];
            difference_b_r[3] <= difference_b_r[2];
            aligned_b_r[3] <= difference_b_r[2][1] ?
                aligned_b_r[2] >> 2 : aligned_b_r[2];
            difference_a_r[4] <= difference_a_r[3];
            aligned_a_r[4] <= difference_a_r[3][2] ?
                aligned_a_r[3] >> 4 : aligned_a_r[3];
            difference_b_r[4] <= difference_b_r[3];
            aligned_b_r[4] <= difference_b_r[3][2] ?
                aligned_b_r[3] >> 4 : aligned_b_r[3];
            difference_a_r[5] <= difference_a_r[4];
            aligned_a_r[5] <= difference_a_r[4][3] ?
                aligned_a_r[4] >> 8 : aligned_a_r[4];
            difference_b_r[5] <= difference_b_r[4];
            aligned_b_r[5] <= difference_b_r[4][3] ?
                aligned_b_r[4] >> 8 : aligned_b_r[4];
            difference_a_r[6] <= difference_a_r[5];
            aligned_a_r[6] <= difference_a_r[5][4] ?
                aligned_a_r[5] >> 16 : aligned_a_r[5];
            difference_b_r[6] <= difference_b_r[5];
            aligned_b_r[6] <= difference_b_r[5][4] ?
                aligned_b_r[5] >> 16 : aligned_b_r[5];
            sign_a_r[2] <= sign_a_r[1];
            sign_b_r[2] <= sign_b_r[1];
            sign_a_r[3] <= sign_a_r[2];
            sign_b_r[3] <= sign_b_r[2];
            sign_a_r[4] <= sign_a_r[3];
            sign_b_r[4] <= sign_b_r[3];
            sign_a_r[5] <= sign_a_r[4];
            sign_b_r[5] <= sign_b_r[4];
            sign_a_r[6] <= sign_a_r[5];
            sign_b_r[6] <= sign_b_r[5];
            sign_a_r[7] <= sign_a_r[6];
            sign_b_r[7] <= sign_b_r[6];
            sign_a_r[8] <= sign_a_r[7];
            sign_b_r[8] <= sign_b_r[7];
            round_low_a_r <= difference_a_r[6][9:5] != 0 ?
                20'b0 : round_low_a_w[19:0];
            round_carry_a_r <= difference_a_r[6][9:5] == 0 && round_low_a_w[20];
            round_high_a_r <= difference_a_r[6][9:5] == 0 && aligned_a_r[6][21];
            rounded_a_r <= {unused_round_high_a_w[1:0], round_low_a_r};
            sign_low_a_r <= sign_low_a_w[19:0];
            sign_carry_a_r <= sign_low_a_w[20];
            unused_sign_magnitude_a_r <= rounded_a_r;
            sign_negative_a_r <= sign_a_r[8];
            signed_a_r <= {unused_sign_high_a_w[2:0], sign_low_a_r};
            round_low_b_r <= difference_b_r[6][9:5] != 0 ?
                20'b0 : round_low_b_w[19:0];
            round_carry_b_r <= difference_b_r[6][9:5] == 0 && round_low_b_w[20];
            round_high_b_r <= difference_b_r[6][9:5] == 0 && aligned_b_r[6][21];
            rounded_b_r <= {unused_round_high_b_w[1:0], round_low_b_r};
            sign_low_b_r <= sign_low_b_w[19:0];
            sign_carry_b_r <= sign_low_b_w[20];
            unused_sign_magnitude_b_r <= rounded_b_r;
            sign_negative_b_r <= sign_b_r[8];
            signed_b_r <= {unused_sign_high_b_w[2:0], sign_low_b_r};
            subtract_low_r <= subtract_low_w[19:0];
            subtract_carry_r <= subtract_low_w[20];
            subtract_a_r <= signed_a_r[22:20];
            subtract_b_r <= signed_b_r[22:20];
            difference_r <= {unused_subtract_high_w[2:0], subtract_low_r};
            unused_absolute_value_r <= difference_r;
            absolute_sign_r <= difference_r[22];
            absolute_low_r <= absolute_low_w[19:0];
            absolute_carry_r <= absolute_low_w[20];
            absolute_r <= {unused_absolute_high_w[2:0], absolute_low_r};
            sign_r <= absolute_sign_r;
        end
    end
endmodule
