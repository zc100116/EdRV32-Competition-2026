// File: edrv32_gpu_perspective_scale.v
// Spec: gpu-spec 2.13; microarch 4.6, 4.10.
// Description: Fixed-width registered arithmetic; global enable preserves pipeline alignment.
// Clock domain: clk_gpu.
module edrv32_gpu_perspective_scale (
    // Clock and common pipeline enable.
    input wire clk_i,
    input wire en_i,

    // Arithmetic payload.
    input wire [17:0] magnitude_i,
    input wire [9:0] exponent_i,
    output wire [95:0] magnitude_o
);
    reg [10:0] amount_r [0:7];
    reg left_r [0:7];
    reg [95:0] left_value_r [0:7];
    reg [18:0] right_value_r [0:7];
    reg [95:0] result_r;
    wire [18:0] rounded_w;
    assign rounded_w = {1'b0, right_value_r[7][18:1]} +
        {18'b0, right_value_r[7][0]};
    wire signed [10:0] exponent_w;
    assign exponent_w = {exponent_i[9], exponent_i};
    assign magnitude_o = result_r;
    always @(posedge clk_i) begin
        if (en_i) begin
            amount_r[0] <= exponent_w < 0 ? $unsigned(-exponent_w) : $unsigned(exponent_w);
            left_r[0] <= exponent_w >= 0;
            left_value_r[0] <= {78'b0, magnitude_i};
            right_value_r[0] <= {magnitude_i, 1'b0};
            amount_r[1] <= amount_r[0];
            left_r[1] <= left_r[0];
            left_value_r[1] <= amount_r[0][0] ?
                left_value_r[0] << 1 : left_value_r[0];
            right_value_r[1] <= amount_r[0][0] ?
                right_value_r[0] >> 1 : right_value_r[0];
            amount_r[2] <= amount_r[1];
            left_r[2] <= left_r[1];
            left_value_r[2] <= amount_r[1][1] ?
                left_value_r[1] << 2 : left_value_r[1];
            right_value_r[2] <= amount_r[1][1] ?
                right_value_r[1] >> 2 : right_value_r[1];
            amount_r[3] <= amount_r[2];
            left_r[3] <= left_r[2];
            left_value_r[3] <= amount_r[2][2] ?
                left_value_r[2] << 4 : left_value_r[2];
            right_value_r[3] <= amount_r[2][2] ?
                right_value_r[2] >> 4 : right_value_r[2];
            amount_r[4] <= amount_r[3];
            left_r[4] <= left_r[3];
            left_value_r[4] <= amount_r[3][3] ?
                left_value_r[3] << 8 : left_value_r[3];
            right_value_r[4] <= amount_r[3][3] ?
                right_value_r[3] >> 8 : right_value_r[3];
            amount_r[5] <= amount_r[4];
            left_r[5] <= left_r[4];
            left_value_r[5] <= amount_r[4][4] ?
                left_value_r[4] << 16 : left_value_r[4];
            right_value_r[5] <= amount_r[4][4] ?
                right_value_r[4] >> 16 : right_value_r[4];
            amount_r[6] <= amount_r[5];
            left_r[6] <= left_r[5];
            left_value_r[6] <= amount_r[5][5] ?
                left_value_r[5] << 32 : left_value_r[5];
            right_value_r[6] <= amount_r[5][5] ?
                right_value_r[5] >> 32 : right_value_r[5];
            amount_r[7] <= amount_r[6];
            left_r[7] <= left_r[6];
            left_value_r[7] <= amount_r[6][6] ?
                left_value_r[6] << 64 : left_value_r[6];
            right_value_r[7] <= amount_r[6][6] ?
                right_value_r[6] >> 64 : right_value_r[6];
            result_r <= amount_r[7][10:7] != 0 ? 96'b0 :
                left_r[7] ? left_value_r[7] :
                {77'b0, rounded_w};
        end
    end
endmodule
