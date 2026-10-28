// File: edrv32_pix_kernel.v
// Spec: pix-spec 2.1, 2.4.
// Description: RGB888 spatial arithmetic for one zero-padded 3x3 window.
// Two independent instances process the two lanes of a beat.
// Clock: combinational in clk_mem.
module edrv32_pix_kernel (
    // Window, in row-major order, p00 in the low 24 bits.
    input wire [215:0] window_i,

    // Result.
    output reg [23:0] data_o,

    // Frame configuration.
    input wire [2:0] op_i
);
    wire [7:0] gray_w [0:8];
    reg [7:0] value_w;
    reg [7:0] minimum_w;
    reg [7:0] maximum_w;
    reg signed [11:0] gx_w;
    reg signed [11:0] gy_w;
    reg [11:0] abs_x_w;
    reg [11:0] abs_y_w;
    reg [12:0] magnitude_w;
    integer idx_w;
    genvar pixel;

    function [7:0] gray;
        input [23:0] rgb_i;
        reg [15:0] unused_sum;
        begin
            unused_sum = 16'd77 * {8'd0, rgb_i[23:16]} + 16'd150 * {8'd0, rgb_i[15:8]}
                + 16'd29 * {8'd0, rgb_i[7:0]} + 16'd128;
            gray = unused_sum[15:8];
        end
    endfunction

    function [7:0] channel;
        input [71:0] samples_i;
        input [2:0] arg_op_i;
        reg [11:0] sum;
        reg signed [12:0] sharp;
        reg [11:0] unused_quotient;
        integer idx;
        begin
            sum = 12'd0;
            sharp = 13'sd0;
            unused_quotient = 12'd0;
            channel = samples_i[32 +: 8];
            case (arg_op_i)
                3'd1: begin
                    for (idx = 0; idx < 9; idx = idx + 1) begin
                        sum = sum + {4'd0, samples_i[idx*8 +: 8]};
                    end
                    // sum+4 <= 2299, and the quotient fits exactly in 8 bits.
                    unused_quotient = (sum + 12'd4) / 12'd9;
                    channel = unused_quotient[7:0];
                end
                3'd2: begin
                    sum = {4'd0, samples_i[0 +: 8]} + {3'd0, samples_i[8 +: 8], 1'b0}
                        + {4'd0, samples_i[16 +: 8]} + {3'd0, samples_i[24 +: 8], 1'b0}
                        + {2'd0, samples_i[32 +: 8], 2'b0}
                        + {3'd0, samples_i[40 +: 8], 1'b0} + {4'd0, samples_i[48 +: 8]}
                        + {3'd0, samples_i[56 +: 8], 1'b0} + {4'd0, samples_i[64 +: 8]}
                        + 12'd8;
                    channel = sum[11:4];
                end
                3'd3: begin
                    sharp = 13'sd5 * $signed({5'd0, samples_i[32 +: 8]})
                        - $signed({5'd0, samples_i[8 +: 8]})
                        - $signed({5'd0, samples_i[24 +: 8]})
                        - $signed({5'd0, samples_i[40 +: 8]})
                        - $signed({5'd0, samples_i[56 +: 8]});
                    if (sharp < 0) begin
                        channel = 8'd0;
                    end else if (sharp > 255) begin
                        channel = 8'd255;
                    end else begin
                        channel = sharp[7:0];
                    end
                end
                default: begin
                    channel = samples_i[32 +: 8];
                end
            endcase
        end
    endfunction

    generate
        for (pixel = 0; pixel < 9; pixel = pixel + 1) begin : g_gray
            assign gray_w[pixel] = gray(window_i[pixel*24 +: 24]);
        end
    endgenerate

    always @(*) begin
        data_o = window_i[96 +: 24];
        value_w = 8'd0;
        minimum_w = 8'd255;
        maximum_w = 8'd0;
        gx_w = -$signed({4'd0, gray_w[0]}) + $signed({4'd0, gray_w[2]})
            - $signed({3'd0, gray_w[3], 1'b0}) + $signed({3'd0, gray_w[5], 1'b0})
            - $signed({4'd0, gray_w[6]}) + $signed({4'd0, gray_w[8]});
        gy_w = -$signed({4'd0, gray_w[0]}) - $signed({3'd0, gray_w[1], 1'b0})
            - $signed({4'd0, gray_w[2]}) + $signed({4'd0, gray_w[6]})
            + $signed({3'd0, gray_w[7], 1'b0}) + $signed({4'd0, gray_w[8]});
        abs_x_w = gx_w[11] ? $unsigned(-gx_w) : $unsigned(gx_w);
        abs_y_w = gy_w[11] ? $unsigned(-gy_w) : $unsigned(gy_w);
        magnitude_w = {1'b0, abs_x_w} + {1'b0, abs_y_w};
        for (idx_w = 0; idx_w < 9; idx_w = idx_w + 1) begin
            if (gray_w[idx_w] < minimum_w) begin
                minimum_w = gray_w[idx_w];
            end
            if (gray_w[idx_w] > maximum_w) begin
                maximum_w = gray_w[idx_w];
            end
        end
        case (op_i)
            3'd1, 3'd2, 3'd3: begin
                data_o[23:16] = channel({window_i[208 +: 8], window_i[184 +: 8],
                    window_i[160 +: 8], window_i[136 +: 8], window_i[112 +: 8],
                    window_i[88 +: 8], window_i[64 +: 8], window_i[40 +: 8],
                    window_i[16 +: 8]}, op_i);
                data_o[15:8] = channel({window_i[200 +: 8], window_i[176 +: 8],
                    window_i[152 +: 8], window_i[128 +: 8], window_i[104 +: 8],
                    window_i[80 +: 8], window_i[56 +: 8], window_i[32 +: 8],
                    window_i[8 +: 8]}, op_i);
                data_o[7:0] = channel({window_i[192 +: 8], window_i[168 +: 8],
                    window_i[144 +: 8], window_i[120 +: 8], window_i[96 +: 8],
                    window_i[72 +: 8], window_i[48 +: 8], window_i[24 +: 8],
                    window_i[0 +: 8]}, op_i);
            end
            3'd4, 3'd5, 3'd6: begin
                case (op_i)
                    3'd4: value_w = magnitude_w > 13'd255 ? 8'd255 : magnitude_w[7:0];
                    3'd5: value_w = minimum_w;
                    default: value_w = maximum_w;
                endcase
                data_o = {value_w, value_w, value_w};
            end
            default: begin
                data_o = window_i[96 +: 24];
            end
        endcase
    end
endmodule
