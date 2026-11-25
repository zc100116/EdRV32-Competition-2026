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
    output wire [95:0] magnitude_o,

    // Shared three-cycle RAM holds direction and the high shift-amount bits.
    output wire [4:0] delay_scale_wr_data_o,
    input wire [4:0] delay_scale_rd_data_i
);
    wire signed [10:0] exponent_w;
    wire [10:0] amount_w;
    reg [4:0] amount_1_r;
    reg [2:0] amount_2_r;
    reg [20:0] left_1_r;
    reg [32:0] left_2_r;
    reg [95:0] left_3_r;
    reg [18:0] right_1_r;
    reg [18:0] right_2_r;
    reg [18:0] right_3_r;
    wire [18:0] rounded_w;
    reg [95:0] result_r;
    assign exponent_w = {exponent_i[9], exponent_i};
    assign amount_w = exponent_w < 0 ? $unsigned(-exponent_w) : $unsigned(exponent_w);
    assign delay_scale_wr_data_o = {exponent_w >= 0, amount_w[10:7]};
    assign rounded_w = {1'b0, right_3_r[18:1]} + {18'b0, right_3_r[0]};
    assign magnitude_o = result_r;
    always @(posedge clk_i) begin
        if (en_i) begin
            amount_1_r <= amount_w[6:2];
            amount_2_r <= amount_1_r[4:2];
            left_1_r <= {3'b0, magnitude_i} << amount_w[1:0];
            right_1_r <= {magnitude_i, 1'b0} >> amount_w[1:0];
            left_2_r <= {12'b0, left_1_r} << {amount_1_r[1:0], 2'b0};
            right_2_r <= right_1_r >> {amount_1_r[1:0], 2'b0};
            left_3_r <= {63'b0, left_2_r} << {amount_2_r, 4'b0};
            right_3_r <= right_2_r >> {amount_2_r, 4'b0};
            result_r <= delay_scale_rd_data_i[3:0] != 0 ? 96'b0 :
                delay_scale_rd_data_i[4] ? left_3_r : {77'b0, rounded_w};
        end
    end
endmodule
