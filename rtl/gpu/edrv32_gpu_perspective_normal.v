// File: edrv32_gpu_perspective_normal.v
// Spec: gpu-spec 2.13; microarch 4.6, 4.10.
// Description: Fixed-width registered arithmetic; global enable preserves pipeline alignment.
// Clock domain: clk_gpu.
module edrv32_gpu_perspective_normal (
    // Clock and common pipeline enable.
    input wire clk_i,
    input wire en_i,

    // Arithmetic payload.
    input wire [69:0] magnitude_i,
    input wire sign_i,
    input wire [9:0] exponent_i,
    output wire [28:0] normal_o
);
    // Count, three levels of 4:1 shift, then rounding and packing.
    // When the upper six bits are used, the discarded six LSBs lie below the guard bit.
    wire high_w;
    wire [63:0] count_value_w;
    wire [7:0] group_w;
    wire [23:0] position_w;
    reg [5:0] leading_w;
    reg [63:0] value_r;
    reg [5:0] shift_r;
    reg [9:0] exponent_r;
    reg sign_r;
    reg [18:0] shifted_r;
    reg [9:0] shifted_exponent_r;
    reg shifted_sign_r;
    wire [63:0] unused_shifted_w;
    wire [18:0] rounded_w;
    reg [28:0] result_r;
    assign high_w = |magnitude_i[69:64];
    assign count_value_w = high_w ? magnitude_i[69:6] : magnitude_i[63:0];
    assign unused_shifted_w = value_r << shift_r;
    assign rounded_w = {1'b0, shifted_r[18:1]} + {18'b0, shifted_r[0]};
    assign normal_o = result_r;
    genvar group_idx;
    generate
        // Eight parallel 8-bit encoders and an eight-way group encoder.
        for (group_idx = 0; group_idx < 8; group_idx = group_idx + 1) begin : g_count
            reg [2:0] position_select_w;
            assign group_w[group_idx] = |count_value_w[group_idx*8 +: 8];
            assign position_w[group_idx*3 +: 3] = position_select_w;
            always @(*) begin
                position_select_w = 0;
                casez (count_value_w[group_idx*8 +: 8])
                    8'b1???????: position_select_w = 7;
                    8'b01??????: position_select_w = 6;
                    8'b001?????: position_select_w = 5;
                    8'b0001????: position_select_w = 4;
                    8'b00001???: position_select_w = 3;
                    8'b000001??: position_select_w = 2;
                    8'b0000001?: position_select_w = 1;
                    default: begin end
                endcase
            end
        end
    endgenerate
    always @(*) begin
        leading_w = 0;
        casez (group_w)
            8'b1???????: leading_w = {3'd7, position_w[21 +: 3]};
            8'b01??????: leading_w = {3'd6, position_w[18 +: 3]};
            8'b001?????: leading_w = {3'd5, position_w[15 +: 3]};
            8'b0001????: leading_w = {3'd4, position_w[12 +: 3]};
            8'b00001???: leading_w = {3'd3, position_w[9 +: 3]};
            8'b000001??: leading_w = {3'd2, position_w[6 +: 3]};
            8'b0000001?: leading_w = {3'd1, position_w[3 +: 3]};
            8'b00000001: leading_w = {3'd0, position_w[0 +: 3]};
            default: begin end
        endcase
    end
    always @(posedge clk_i) begin
        if (en_i) begin
            value_r <= count_value_w;
            shift_r <= 6'd63 - leading_w;
            exponent_r <= exponent_i + {4'b0, leading_w} + (high_w ? 10'd6 : 10'd0)
                - 10'd17;
            sign_r <= sign_i;
            shifted_r <= unused_shifted_w[63:45];
            shifted_exponent_r <= exponent_r;
            shifted_sign_r <= sign_r;
            result_r <= shifted_r[18:1] == 0 ? 29'b0 :
                {shifted_exponent_r + {9'b0, rounded_w[18]}, shifted_sign_r,
                rounded_w[18] ? rounded_w[18:1] : rounded_w[17:0]};
        end
    end
endmodule
