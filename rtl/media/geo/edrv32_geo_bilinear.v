// File: edrv32_geo_bilinear.v
// Spec: geo-spec 2.2, 5.2.
// Description: Two-stage exact separable interpolation; rounding occurs only after both axes.
// Clock domain: clk_mem.
module edrv32_geo_bilinear (
    // Clock and reset.
    input wire clk_i,
    input wire rst_n_i,
    // Common pipeline enable provides lossless backpressure.
    input wire advance_i,
    input wire clear_i,
    input wire valid_i,
    input wire eol_i,
    input wire [15:0] p00_i,
    input wire [15:0] p01_i,
    input wire [15:0] p10_i,
    input wire [15:0] p11_i,
    input wire [7:0] fx_i,
    input wire [7:0] fy_i,
    // Rounded RGB565 output.
    output wire valid_o,
    output wire eol_o,
    output wire [15:0] pixel_o
);
    reg [1:0] valid_r;
    reg [1:0] eol_r;
    reg [7:0] fy_r;
    wire [23:0] rgb_w;
    wire unused_rgb_w;
    assign unused_rgb_w = &{rgb_w[18:16], rgb_w[9:8], rgb_w[2:0]};
    assign valid_o = valid_r[1];
    assign eol_o = eol_r[1];
    assign pixel_o = {rgb_w[23:19], rgb_w[15:10], rgb_w[7:3]};
    function [23:0] expand;
        input [15:0] pixel_i;
        begin
            expand = {pixel_i[15:11], pixel_i[15:13], pixel_i[10:5], pixel_i[10:9],
                pixel_i[4:0], pixel_i[4:2]};
        end
    endfunction
    wire [23:0] p00_w;
    wire [23:0] p01_w;
    wire [23:0] p10_w;
    wire [23:0] p11_w;
    assign p00_w = expand(p00_i);
    assign p01_w = expand(p01_i);
    assign p10_w = expand(p10_i);
    assign p11_w = expand(p11_i);
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i)
            valid_r <= 2'd0;
        else if (clear_i)
            valid_r <= 2'd0;
        else if (advance_i)
            valid_r <= {valid_r[0], valid_i};
    end
    always @(posedge clk_i) begin
        if (advance_i) begin
            eol_r <= {eol_r[0], eol_i};
            fy_r <= fy_i;
        end
    end
    genvar channel;
    generate
        for (channel = 0; channel < 3; channel = channel + 1) begin : g_channel
            reg [15:0] top_r;
            reg [15:0] bottom_r;
            reg [23:0] rounded_r;
            wire signed [8:0] top_delta_w;
            wire signed [8:0] bottom_delta_w;
            wire signed [16:0] vertical_delta_w;
            wire signed [25:0] vertical_w;
            wire signed [17:0] horizontal_top_w;
            wire signed [17:0] horizontal_bottom_w;
            assign top_delta_w = $signed({1'b0, p01_w[channel*8 +: 8]}) -
                $signed({1'b0, p00_w[channel*8 +: 8]});
            assign bottom_delta_w = $signed({1'b0, p11_w[channel*8 +: 8]}) -
                $signed({1'b0, p10_w[channel*8 +: 8]});
            assign horizontal_top_w = $signed({2'b0, p00_w[channel*8 +: 8], 8'd0}) +
                top_delta_w * $signed({1'b0, fx_i});
            assign horizontal_bottom_w = $signed({2'b0, p10_w[channel*8 +: 8], 8'd0}) +
                bottom_delta_w * $signed({1'b0, fx_i});
            assign vertical_delta_w = $signed({1'b0, bottom_r}) - $signed({1'b0, top_r});
            assign vertical_w = $signed({2'b0, top_r, 8'd0}) +
                vertical_delta_w * $signed({1'b0, fy_r}) + 26'sd32768;
            assign rgb_w[channel*8 +: 8] = rounded_r[23:16];
            wire unused_w;
            assign unused_w = &{horizontal_top_w[17:16], horizontal_bottom_w[17:16],
                vertical_w[25:24], rounded_r[15:0]};
            always @(posedge clk_i) begin
                if (advance_i) begin
                    top_r <= horizontal_top_w[15:0];
                    bottom_r <= horizontal_bottom_w[15:0];
                    rounded_r <= vertical_w[23:0];
                end
            end
        end
    endgenerate
endmodule
