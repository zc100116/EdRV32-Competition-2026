// File: edrv32_rnd_filter.v
// Spec: rnd-spec v0.3 2.6 AFFINE_BLIT, 5.2.
// Description: One-pixel elastic premultiplied bilinear reconstruction; normalized
//              multiplier operands and products are registered before the next operation.
// Clock domain: clk_mem (clk_i).
module edrv32_rnd_filter (
    // Clock and cancellation.
    input wire clk_i,
    input wire rst_n_i,
    input wire clear_i,

    // Decoded tap order: 00, 10, 01, 11. Mode is stable for a command.
    input wire in_valid_i,
    output wire in_ready_o,
    input wire bilinear_i,
    input wire [127:0] taps_i,
    input wire [7:0] fraction_x_i,
    input wire [7:0] fraction_y_i,
    input wire [31:0] destination_i,
    input wire [31:0] tag_i,
    input wire [7:0] coverage_i,

    // Straight-alpha source, before recolor/opacity/target coverage.
    output wire out_valid_o,
    input wire out_ready_i,
    output wire [31:0] pixel_o,
    output wire [31:0] destination_o,
    output wire [31:0] tag_o,
    output wire [7:0] coverage_o
);
    `include "edrv32_rnd_q.vh"
    function automatic [7:0] divide255;
        input [15:0] product_i;
        reg [15:0] biased;
        reg [15:0] rounded;
        reg [7:0] unused_low;
        begin
            biased = product_i + 16'd128;
            rounded = biased + (biased >> 8);
            divide255 = rounded[15:8];
            unused_low = rounded[7:0];
        end
    endfunction
    function automatic [7:0] interpolate_round;
        input [25:0] sum_i;
        reg [25:0] biased;
        reg [17:0] unused_bits;
        begin
            biased = sum_i + 26'd32768;
            interpolate_round = biased[23:16];
            unused_bits = {biased[25:24], biased[15:0]};
        end
    endfunction
    function automatic [7:0] restore_round;
        input [31:0] product_i;
        reg [31:0] biased;
        reg [15:0] unused_bits;
        begin
            biased = product_i + 32'd32768;
            restore_round = |biased[31:24] ? 8'd255 : biased[23:16];
            unused_bits = biased[15:0];
        end
    endfunction
    wire advance_w;
    reg [9:0] valid_r;
    reg [71:0] payload_r [0:9];
    reg [31:0] nearest_r [0:8];
    reg [127:0] taps0_r;
    reg [8:0] fx0_r;
    reg [8:0] fy0_r;
    reg [8:0] inverse_x0_r;
    reg [8:0] inverse_y0_r;
    reg [16:0] weight1_r [0:3];
    reg [16:0] weight2_r [0:3];
    reg [15:0] premult1_r [0:3][0:2];
    reg [7:0] alpha1_r [0:3];
    reg [7:0] premult2_r [0:3][0:3];
    reg [23:0] product3_r [0:3][0:3];
    reg [24:0] pair4_r [0:3][0:1];
    reg [25:0] sum5_r [0:3];
    reg [7:0] interpolated6_r [0:3];
    reg [7:0] color7_r [0:2];
    reg [7:0] alpha7_r;
    reg [7:0] alpha8_r;
    reg [23:0] reciprocal7_r;
    reg [31:0] restored8_r [0:2];
    reg [31:0] pixel9_r;
    integer stage;
    integer tap;
    integer channel;
    assign advance_w = !valid_r[9] || out_ready_i;
    assign in_ready_o = advance_w && !clear_i;
    assign out_valid_o = valid_r[9];
    assign pixel_o = pixel9_r;
    assign destination_o = payload_r[9][31:0];
    assign tag_o = payload_r[9][63:32];
    assign coverage_o = payload_r[9][71:64];
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i)
            valid_r <= 10'd0;
        else if (clear_i)
            valid_r <= 10'd0;
        else if (advance_w)
            valid_r <= {valid_r[8:0], in_valid_i};
    end
    always @(posedge clk_i) begin
        if (advance_w) begin
            // Input operands: all multiplier inputs below are complete registers.
            taps0_r <= taps_i;
            fx0_r <= {1'b0, fraction_x_i};
            fy0_r <= {1'b0, fraction_y_i};
            inverse_x0_r <= 9'd256 - {1'b0, fraction_x_i};
            inverse_y0_r <= 9'd256 - {1'b0, fraction_y_i};
            payload_r[0] <= {coverage_i, tag_i, destination_i};
            nearest_r[0] <= taps_i[31:0];
            for (stage = 1; stage < 10; stage = stage + 1)
                payload_r[stage] <= payload_r[stage-1];
            for (stage = 1; stage < 9; stage = stage + 1)
                nearest_r[stage] <= nearest_r[stage-1];
            weight1_r[0] <= inverse_x0_r * inverse_y0_r;
            weight1_r[1] <= fx0_r * inverse_y0_r;
            weight1_r[2] <= inverse_x0_r * fy0_r;
            weight1_r[3] <= fx0_r * fy0_r;
            for (tap = 0; tap < 4; tap = tap + 1) begin
                alpha1_r[tap] <= taps0_r[tap*32+24 +: 8];
                weight2_r[tap] <= weight1_r[tap];
                premult2_r[tap][3] <= alpha1_r[tap];
                for (channel = 0; channel < 3; channel = channel + 1) begin
                    premult1_r[tap][channel] <= taps0_r[tap*32+24 +: 8] *
                        taps0_r[tap*32+channel*8 +: 8];
                    premult2_r[tap][channel] <= divide255(premult1_r[tap][channel]);
                end
                for (channel = 0; channel < 4; channel = channel + 1)
                    product3_r[tap][channel] <= weight2_r[tap] * premult2_r[tap][channel];
            end
            for (channel = 0; channel < 4; channel = channel + 1) begin
                pair4_r[channel][0] <= {1'b0, product3_r[0][channel]} +
                    {1'b0, product3_r[1][channel]};
                pair4_r[channel][1] <= {1'b0, product3_r[2][channel]} +
                    {1'b0, product3_r[3][channel]};
                sum5_r[channel] <= {1'b0, pair4_r[channel][0]} +
                    {1'b0, pair4_r[channel][1]};
                interpolated6_r[channel] <= interpolate_round(sum5_r[channel]);
            end
            reciprocal7_r <= edrv32_rnd_q(interpolated6_r[3]);
            alpha7_r <= interpolated6_r[3];
            alpha8_r <= alpha7_r;
            for (channel = 0; channel < 3; channel = channel + 1) begin
                color7_r[channel] <= interpolated6_r[channel];
                restored8_r[channel] <= color7_r[channel] * reciprocal7_r;
            end
            pixel9_r <= bilinear_i ? (alpha8_r == 0 ? 32'd0 : {alpha8_r,
                restore_round(restored8_r[2]), restore_round(restored8_r[1]),
                restore_round(restored8_r[0])}) : nearest_r[8];
        end
    end
endmodule
