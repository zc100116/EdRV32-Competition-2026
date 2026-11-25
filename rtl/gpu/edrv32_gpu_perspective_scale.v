// File: edrv32_gpu_perspective_scale.v
// Spec: gpu-spec 2.13; microarch 4.13.
// Description: Fixed-width registered arithmetic; global enable preserves pipeline alignment.
// Clock domain: clk_gpu.
// Output widths are Q8 coordinates (32) and Q16 LOD spans (96), spec 2.13.12/14.
module edrv32_gpu_perspective_scale #(
    parameter WIDTH = 96
) (
    // Clock and common pipeline enable.
    input wire clk_i,
    input wire en_i,

    // Arithmetic payload.
    input wire [17:0] magnitude_i,
    input wire [9:0] exponent_i,
    output wire [WIDTH-1:0] magnitude_o,

    // Shared three-cycle RAM holds direction and the high shift-amount bits.
    output wire [4:0] delay_scale_wr_data_o,
    input wire [4:0] delay_scale_rd_data_i
);
    localparam MIDDLE_WIDTH = WIDTH < 33 ? WIDTH : 33;
    wire signed [10:0] exponent_w;
    wire [10:0] amount_w;
    reg [4:0] amount_1_r;
    reg [2:0] amount_2_r;
    reg [20:0] left_1_r;
    reg [MIDDLE_WIDTH-1:0] left_2_r;
    reg [WIDTH-1:0] left_3_r;
    reg [18:0] right_1_r;
    reg [18:0] right_2_r;
    reg [18:0] right_3_r;
    wire [20:0] left_1_w;
    wire [32:0] unused_left_2_w;
    wire [95:0] left_16_w;
    wire [95:0] unused_left_64_w;
    wire [18:0] right_1_w;
    wire [18:0] right_4_w;
    wire [18:0] right_16_w;
    wire [18:0] rounded_w;
    reg [WIDTH-1:0] result_r;
    assign exponent_w = {exponent_i[9], exponent_i};
    assign amount_w = exponent_w < 0 ? $unsigned(-exponent_w) : $unsigned(exponent_w);
    assign delay_scale_wr_data_o = {exponent_w >= 0, amount_w[10:7]};
    assign rounded_w = {1'b0, right_3_r[18:1]} + {18'b0, right_3_r[0]};
    assign magnitude_o = result_r;
    // Balanced four-input selectors use each two-bit amount field as one LUT6 stage.
    assign left_1_w = amount_w[1] ?
        (amount_w[0] ? {magnitude_i, 3'b0} :
        {1'b0, magnitude_i, 2'b0}) :
        (amount_w[0] ? {2'b0, magnitude_i, 1'b0} :
        {3'b0, magnitude_i});
    assign right_1_w = amount_w[1] ?
        (amount_w[0] ? {3'b0, magnitude_i[17:2]} :
        {2'b0, magnitude_i[17:1]}) :
        (amount_w[0] ? {1'b0, magnitude_i} :
        {magnitude_i, 1'b0});
    assign unused_left_2_w = amount_1_r[1] ?
        (amount_1_r[0] ? {left_1_r, 12'b0} :
        {4'b0, left_1_r, 8'b0}) :
        (amount_1_r[0] ? {8'b0, left_1_r, 4'b0} :
        {12'b0, left_1_r});
    assign right_4_w = amount_1_r[1] ?
        (amount_1_r[0] ? {12'b0, right_1_r[18:12]} :
        {8'b0, right_1_r[18:8]}) :
        (amount_1_r[0] ? {4'b0, right_1_r[18:4]} :
        right_1_r);
    assign left_16_w = amount_2_r[1] ?
        (amount_2_r[0] ? {{(48-MIDDLE_WIDTH){1'b0}}, left_2_r, 48'b0} :
        {{(64-MIDDLE_WIDTH){1'b0}}, left_2_r, 32'b0}) :
        (amount_2_r[0] ? {{(80-MIDDLE_WIDTH){1'b0}}, left_2_r, 16'b0} :
        {{(96-MIDDLE_WIDTH){1'b0}}, left_2_r});
    assign right_16_w = amount_2_r[1] ?
        (amount_2_r[0] ? 19'b0 :
        19'b0) :
        (amount_2_r[0] ? {16'b0, right_2_r[18:16]} :
        right_2_r);
    assign unused_left_64_w = amount_2_r[2] ? {left_16_w[31:0], 64'b0} : left_16_w;
    always @(posedge clk_i) begin
        if (en_i) begin
            amount_1_r <= amount_w[6:2];
            amount_2_r <= amount_1_r[4:2];
            left_1_r <= left_1_w;
            right_1_r <= right_1_w;
            left_2_r <= unused_left_2_w[MIDDLE_WIDTH-1:0];
            right_2_r <= right_4_w;
            left_3_r <= unused_left_64_w[WIDTH-1:0];
            right_3_r <= amount_2_r[2] ? 19'b0 : right_16_w;
            result_r <= delay_scale_rd_data_i[3:0] != 0 ? {WIDTH{1'b0}} :
                delay_scale_rd_data_i[4] ? left_3_r : {{(WIDTH-19){1'b0}}, rounded_w};
        end
    end
endmodule
