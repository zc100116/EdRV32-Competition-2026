// File: edrv32_rnd_blur_math.v
// Spec: rnd-spec 2.4.
// Description: Normalize two four-channel box sums with the specified fixed-point reciprocal.
//              Multiplication and rounding are separated by a register for 125 MHz operation.
// Clock domain: clk_mem (clk_i).
module edrv32_rnd_blur_math (
    // Clock and reset.
    input wire clk_i,
    input wire rst_n_i,

    // Eight 14-bit sums: B,G,R,A for the first pixel, then the second pixel.
    input wire valid_i,
    output wire ready_o,
    input wire [111:0] sum_i,
    input wire [16:0] coefficient_i,
    output wire valid_o,
    input wire ready_i,
    output wire [63:0] pixel_o
);
    reg [1:0] valid_r;
    reg [247:0] product_r;
    reg [63:0] pixel_r;
    wire advance_w;
    integer channel;
    assign advance_w = !valid_r[1] || ready_i;
    assign ready_o = advance_w;
    assign valid_o = valid_r[1];
    assign pixel_o = pixel_r;
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i)
            valid_r <= 2'd0;
        else if (advance_w)
            valid_r <= {valid_r[0], valid_i};
    end
    genvar c;
    generate for (c = 0; c < 8; c = c + 1) begin : g_channel
        wire [30:0] rounded_w;
        wire unused_product_w;
        assign rounded_w = (product_r[c*31 +: 31] + 31'd32768) >> 16;
        assign unused_product_w = ^rounded_w[30:8];
        always @(posedge clk_i) begin
            if (advance_w)
                pixel_r[c*8 +: 8] <= rounded_w[7:0];
        end
    end endgenerate
    always @(posedge clk_i) begin
        if (advance_w)
            for (channel = 0; channel < 8; channel = channel + 1)
                product_r[channel*31 +: 31] <=
                    sum_i[channel*14 +: 14] * coefficient_i;
    end
endmodule
