// ============================================================================
// File        : edrv32_pixel_filter_3x3.v
// Description : Combinational grayscale 3x3 filter kernel with RGB565 output.
// Notes       : Mode 0 bypass, 1 Sobel, 2 mean, 3 Gaussian, 4 sharpen,
//               5 erosion and 6 dilation. Spatial modes emit grayscale RGB565.
// ============================================================================

module edrv32_pixel_filter_3x3 (
    input  wire [7:0]  p00_i,
    input  wire [7:0]  p01_i,
    input  wire [7:0]  p02_i,
    input  wire [7:0]  p10_i,
    input  wire [7:0]  p11_i,
    input  wire [7:0]  p12_i,
    input  wire [7:0]  p20_i,
    input  wire [7:0]  p21_i,
    input  wire [7:0]  p22_i,
    input  wire [15:0] center_rgb_i,
    input  wire        enable_i,
    input  wire [2:0]  mode_i,
    input  wire [7:0]  threshold_i,
    output wire [15:0] pixel_o
);

    function [15:0] gray_to_rgb565;
        input [7:0] gray;
        begin
            gray_to_rgb565 = {gray[7:3], gray[7:2], gray[7:3]};
        end
    endfunction

    function [7:0] clamp_signed;
        input signed [13:0] value;
        begin
            if (value < 0)
                clamp_signed = 8'b0;
            else if (value > 14'sd255)
                clamp_signed = 8'hff;
            else
                clamp_signed = value[7:0];
        end
    endfunction

    wire [11:0] sum_w = {4'b0, p00_i} + {4'b0, p01_i} +
        {4'b0, p02_i} + {4'b0, p10_i} + {4'b0, p11_i} +
        {4'b0, p12_i} + {4'b0, p20_i} + {4'b0, p21_i} +
        {4'b0, p22_i};
    wire [11:0] gaussian_sum_w = {4'b0, p00_i} +
        ({4'b0, p01_i} << 1) + {4'b0, p02_i} +
        ({4'b0, p10_i} << 1) + ({4'b0, p11_i} << 2) +
        ({4'b0, p12_i} << 1) + {4'b0, p20_i} +
        ({4'b0, p21_i} << 1) + {4'b0, p22_i};

    wire signed [12:0] s00_w = $signed({5'b0, p00_i});
    wire signed [12:0] s01_w = $signed({5'b0, p01_i});
    wire signed [12:0] s02_w = $signed({5'b0, p02_i});
    wire signed [12:0] s10_w = $signed({5'b0, p10_i});
    wire signed [12:0] s11_w = $signed({5'b0, p11_i});
    wire signed [12:0] s12_w = $signed({5'b0, p12_i});
    wire signed [12:0] s20_w = $signed({5'b0, p20_i});
    wire signed [12:0] s21_w = $signed({5'b0, p21_i});
    wire signed [12:0] s22_w = $signed({5'b0, p22_i});

    wire signed [12:0] sobel_x_w =
        -s00_w + s02_w - (s10_w <<< 1) +
        (s12_w <<< 1) - s20_w + s22_w;
    wire signed [12:0] sobel_y_w =
        -s00_w - (s01_w <<< 1) - s02_w + s20_w +
        (s21_w <<< 1) + s22_w;
    wire [12:0] sobel_abs_x_w = sobel_x_w[12] ?
        -sobel_x_w : sobel_x_w;
    wire [12:0] sobel_abs_y_w = sobel_y_w[12] ?
        -sobel_y_w : sobel_y_w;
    wire [13:0] sobel_sum_w = sobel_abs_x_w + sobel_abs_y_w;
    wire [7:0] sobel_w = |sobel_sum_w[13:8] ? 8'hff : sobel_sum_w[7:0];

    wire signed [13:0] sharpen_sum_w =
        (s11_w * 5) - s01_w - s10_w - s12_w - s21_w;

    wire erode_white_w =
        (p00_i >= threshold_i) && (p01_i >= threshold_i) &&
        (p02_i >= threshold_i) && (p10_i >= threshold_i) &&
        (p11_i >= threshold_i) && (p12_i >= threshold_i) &&
        (p20_i >= threshold_i) && (p21_i >= threshold_i) &&
        (p22_i >= threshold_i);
    wire dilate_white_w =
        (p00_i >= threshold_i) || (p01_i >= threshold_i) ||
        (p02_i >= threshold_i) || (p10_i >= threshold_i) ||
        (p11_i >= threshold_i) || (p12_i >= threshold_i) ||
        (p20_i >= threshold_i) || (p21_i >= threshold_i) ||
        (p22_i >= threshold_i);

    reg [15:0] pixel_r;
    always @(*) begin
        pixel_r = center_rgb_i;
        if (enable_i) begin
            case (mode_i)
                3'd1: pixel_r = gray_to_rgb565(sobel_w);
                3'd2: pixel_r = gray_to_rgb565((sum_w + 4) / 9);
                3'd3: pixel_r = gray_to_rgb565(
                    (gaussian_sum_w + 8) >> 4);
                3'd4: pixel_r = gray_to_rgb565(
                    clamp_signed(sharpen_sum_w));
                3'd5: pixel_r = erode_white_w ? 16'hffff : 16'h0000;
                3'd6: pixel_r = dilate_white_w ? 16'hffff : 16'h0000;
                default: pixel_r = center_rgb_i;
            endcase
        end
    end

    assign pixel_o = pixel_r;

endmodule
