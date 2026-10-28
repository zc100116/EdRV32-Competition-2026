// File: edrv32_pix_kernel.v
// Spec: pix-spec 2.1, 2.4, 7.
// Description: Eight advancing stages for one RGB888 zero-padded window.
// Registered multiplier operands/results and balanced arithmetic preserve exact rounding.
// Clock: clk_mem.
module edrv32_pix_kernel (
    // Clock and pipeline enable; validity and frame tags belong to the filter.
    input wire clk_i,
    input wire advance_i,

    // Window, in row-major order, p00 in the low 24 bits.
    input wire [215:0] window_i,

    // Result after eight advances.
    output reg [23:0] data_o,

    // Configuration is constant until the frame drains.
    input wire [2:0] op_i
);
    reg [215:0] s1_window_r;
    reg [23:0] center_r [0:6];
    reg [15:0] s2_red_r [0:8];
    reg [15:0] s2_green_r [0:8];
    reg [15:0] s2_blue_r [0:8];
    reg [15:0] s3_rg_r [0:8];
    reg [15:0] s3_blue_r [0:8];
    reg [15:0] s4_gray_r [0:8];
    wire [7:0] gray_w [0:8];
    reg [8:0] s5_lobe_r [0:3];
    reg [7:0] s5_middle_r [0:3];
    reg [9:0] s6_lobe_r [0:3];
    reg [9:0] s7_abs_x_r;
    reg [9:0] s7_abs_y_r;
    wire [10:0] magnitude_w;
    reg [7:0] s5_min_r [0:4];
    reg [7:0] s5_max_r [0:4];
    reg [7:0] s6_min_r [0:2];
    reg [7:0] s6_max_r [0:2];
    reg [7:0] s7_min_r [0:1];
    reg [7:0] s7_max_r [0:1];
    wire [7:0] minimum_w;
    wire [7:0] maximum_w;
    wire [7:0] spatial_w;
    wire [23:0] color_w;
    integer idx_r;
    genvar pixel;
    genvar channel;

    assign magnitude_w = {1'b0, s7_abs_x_r} + {1'b0, s7_abs_y_r};
    assign minimum_w = s7_min_r[0] < s7_min_r[1] ? s7_min_r[0] : s7_min_r[1];
    assign maximum_w = s7_max_r[0] > s7_max_r[1] ? s7_max_r[0] : s7_max_r[1];
    assign spatial_w = op_i == 3'd5 ? minimum_w : (op_i == 3'd6 ? maximum_w
        : (|magnitude_w[10:8] ? 8'd255 : magnitude_w[7:0]));

    generate
        for (pixel = 0; pixel < 9; pixel = pixel + 1) begin : g_gray
            assign gray_w[pixel] = s4_gray_r[pixel][15:8];
            always @(posedge clk_i) begin
                if (advance_i) begin
                    // S1 is the dedicated APM input register; S2 is its output.
                    s2_red_r[pixel] <= 16'd77 * {8'd0, s1_window_r[pixel*24+16 +: 8]};
                    s2_green_r[pixel] <= 16'd150 * {8'd0, s1_window_r[pixel*24+8 +: 8]};
                    s2_blue_r[pixel] <= 16'd29 * {8'd0, s1_window_r[pixel*24 +: 8]};
                    s3_rg_r[pixel] <= s2_red_r[pixel] + s2_green_r[pixel];
                    s3_blue_r[pixel] <= s2_blue_r[pixel] + 16'd128;
                    s4_gray_r[pixel] <= s3_rg_r[pixel] + s3_blue_r[pixel];
                end
            end
        end
        for (channel = 0; channel < 3; channel = channel + 1) begin : g_color
            wire [11:0] sample_w [0:8];
            reg [11:0] s2_pair_r [0:3];
            reg [11:0] s2_tail_r;
            reg [11:0] s3_half_r [0:1];
            reg [11:0] s3_tail_r;
            reg [11:0] s4_eight_r;
            reg [11:0] s4_tail_r;
            reg [11:0] s5_sum_r;
            reg [23:0] s6_unused_divide_r;
            reg [7:0] s6_gaussian_r;
            reg [7:0] s6_sharp_r;
            reg [7:0] s7_color_r;
            reg [10:0] s2_center_r;
            reg [8:0] s2_vertical_r;
            reg [8:0] s2_horizontal_r;
            reg [10:0] s3_center_r;
            reg [10:0] s3_neighbors_r;
            reg signed [11:0] s4_sharp_r;
            reg [7:0] s5_sharp_r;
            genvar sample;
            for (sample = 0; sample < 9; sample = sample + 1) begin : g_sample
                localparam WEIGHT_SHIFT = sample == 4 ? 2
                    : (sample == 1 || sample == 3 || sample == 5 || sample == 7 ? 1 : 0);
                assign sample_w[sample] = op_i == 3'd2
                    ? ({4'd0, s1_window_r[sample*24+channel*8 +: 8]} << WEIGHT_SHIFT)
                    : {4'd0, s1_window_r[sample*24+channel*8 +: 8]};
            end
            assign color_w[channel*8 +: 8] = s7_color_r;
            always @(posedge clk_i) begin
                if (advance_i) begin
                    s2_pair_r[0] <= sample_w[0] + sample_w[1];
                    s2_pair_r[1] <= sample_w[2] + sample_w[3];
                    s2_pair_r[2] <= sample_w[4] + sample_w[5];
                    s2_pair_r[3] <= sample_w[6] + sample_w[7];
                    s2_tail_r <= sample_w[8] + (op_i == 3'd2 ? 12'd8 : 12'd4);
                    s3_half_r[0] <= s2_pair_r[0] + s2_pair_r[1];
                    s3_half_r[1] <= s2_pair_r[2] + s2_pair_r[3];
                    s3_tail_r <= s2_tail_r;
                    s4_eight_r <= s3_half_r[0] + s3_half_r[1];
                    s4_tail_r <= s3_tail_r;
                    s5_sum_r <= s4_eight_r + s4_tail_r;
                    // Exact for 0 <= x <= 2303: floor(x/9) = (x*3641)>>15.
                    // S5/S6 are the dedicated input/output registers of this multiply.
                    s6_unused_divide_r <= 24'd3641 * {12'd0, s5_sum_r};
                    s6_gaussian_r <= s5_sum_r[11:4];
                    s2_center_r <= {1'b0, s1_window_r[96+channel*8 +: 8], 2'd0}
                        + {3'd0, s1_window_r[96+channel*8 +: 8]};
                    s2_vertical_r <= {1'b0, s1_window_r[24+channel*8 +: 8]}
                        + {1'b0, s1_window_r[168+channel*8 +: 8]};
                    s2_horizontal_r <= {1'b0, s1_window_r[72+channel*8 +: 8]}
                        + {1'b0, s1_window_r[120+channel*8 +: 8]};
                    s3_center_r <= s2_center_r;
                    s3_neighbors_r <= {2'd0, s2_vertical_r} + {2'd0, s2_horizontal_r};
                    s4_sharp_r <= $signed({1'b0, s3_center_r})
                        - $signed({1'b0, s3_neighbors_r});
                    s5_sharp_r <= s4_sharp_r[11] ? 8'd0
                        : (|s4_sharp_r[10:8] ? 8'd255 : s4_sharp_r[7:0]);
                    s6_sharp_r <= s5_sharp_r;
                    s7_color_r <= op_i == 3'd1 ? s6_unused_divide_r[22:15]
                        : (op_i == 3'd2 ? s6_gaussian_r : s6_sharp_r);
                end
            end
        end
    endgenerate

    always @(posedge clk_i) begin
        if (advance_i) begin
            s1_window_r <= window_i;
            center_r[0] <= window_i[96 +: 24];
            for (idx_r = 1; idx_r < 7; idx_r = idx_r + 1) begin
                center_r[idx_r] <= center_r[idx_r-1];
            end
            // Positive Sobel lobes avoid a serial signed-sum / absolute-value chain.
            s5_lobe_r[0] <= {1'b0, gray_w[0]} + {1'b0, gray_w[6]};
            s5_lobe_r[1] <= {1'b0, gray_w[2]} + {1'b0, gray_w[8]};
            s5_lobe_r[2] <= {1'b0, gray_w[0]} + {1'b0, gray_w[2]};
            s5_lobe_r[3] <= {1'b0, gray_w[6]} + {1'b0, gray_w[8]};
            s5_middle_r[0] <= gray_w[3];
            s5_middle_r[1] <= gray_w[5];
            s5_middle_r[2] <= gray_w[1];
            s5_middle_r[3] <= gray_w[7];
            for (idx_r = 0; idx_r < 4; idx_r = idx_r + 1) begin
                s6_lobe_r[idx_r] <= {1'b0, s5_lobe_r[idx_r]}
                    + {1'b0, s5_middle_r[idx_r], 1'b0};
                s5_min_r[idx_r] <= gray_w[idx_r*2] < gray_w[idx_r*2+1]
                    ? gray_w[idx_r*2] : gray_w[idx_r*2+1];
                s5_max_r[idx_r] <= gray_w[idx_r*2] > gray_w[idx_r*2+1]
                    ? gray_w[idx_r*2] : gray_w[idx_r*2+1];
            end
            // Both subtractions are parallel; each selected path contains one adder.
            s7_abs_x_r <= s6_lobe_r[1] >= s6_lobe_r[0]
                ? s6_lobe_r[1] - s6_lobe_r[0] : s6_lobe_r[0] - s6_lobe_r[1];
            s7_abs_y_r <= s6_lobe_r[3] >= s6_lobe_r[2]
                ? s6_lobe_r[3] - s6_lobe_r[2] : s6_lobe_r[2] - s6_lobe_r[3];
            s5_min_r[4] <= gray_w[8];
            s5_max_r[4] <= gray_w[8];
            for (idx_r = 0; idx_r < 2; idx_r = idx_r + 1) begin
                s6_min_r[idx_r] <= s5_min_r[idx_r*2] < s5_min_r[idx_r*2+1]
                    ? s5_min_r[idx_r*2] : s5_min_r[idx_r*2+1];
                s6_max_r[idx_r] <= s5_max_r[idx_r*2] > s5_max_r[idx_r*2+1]
                    ? s5_max_r[idx_r*2] : s5_max_r[idx_r*2+1];
            end
            s6_min_r[2] <= s5_min_r[4];
            s6_max_r[2] <= s5_max_r[4];
            s7_min_r[0] <= s6_min_r[0] < s6_min_r[1] ? s6_min_r[0] : s6_min_r[1];
            s7_max_r[0] <= s6_max_r[0] > s6_max_r[1] ? s6_max_r[0] : s6_max_r[1];
            s7_min_r[1] <= s6_min_r[2];
            s7_max_r[1] <= s6_max_r[2];
            case (op_i)
                3'd1, 3'd2, 3'd3: data_o <= color_w;
                3'd4, 3'd5, 3'd6: data_o <= {spatial_w, spatial_w, spatial_w};
                default: data_o <= center_r[6];
            endcase
        end
    end
endmodule
