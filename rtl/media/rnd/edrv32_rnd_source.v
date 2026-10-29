// File: edrv32_rnd_source.v
// Spec: rnd-spec 2.1, 2.2, 2.6 GLYPH/BLIT/TILEMAP.
// Description: Expand packed masks, true-color and palette entries to straight ARGB8888.
//              Recolor precedes BLIT mode processing; overall opacity scales source alpha.
// Clock domain: combinational.
module edrv32_rnd_source (
    // Command-specific source conversion.
    input wire [3:0] format_i,
    input wire glyph_i,
    input wire [31:0] raw_i,
    input wire [2:0] sub_shift_i,
    input wire [7:0] sub_mask_i,
    input wire [31:0] palette_i,
    input wire [23:0] color_i,
    input wire [7:0] opacity_i,
    input wire colorkey_i,
    input wire [15:0] key_i,
    input wire recolor_i,
    input wire [31:0] recolor_value_i,
    output wire [7:0] index_o,
    output reg [31:0] pixel_o
);
    function automatic [7:0] divide255;
        input [15:0] value_i;
        reg [15:0] biased;
        reg [15:0] rounded;
        reg [7:0] unused_low;
        begin
            biased = value_i + 16'd128;
            rounded = biased + (biased >> 8);
            divide255 = rounded[15:8];
            unused_low = rounded[7:0];
        end
    endfunction
    wire [7:0] sample_w;
    wire [7:0] recolor_inverse_w;
    reg [31:0] expanded_w;
    integer channel;
    assign recolor_inverse_w = 8'd255 - recolor_value_i[31:24];
    assign sample_w = (raw_i[7:0] >> sub_shift_i) & sub_mask_i;
    assign index_o = sample_w;
    always @(*) begin
        expanded_w = 32'd0;
        pixel_o = 32'd0;
        case (format_i)
            4'd0: expanded_w = {
                colorkey_i && raw_i[15:0] == key_i ? 8'd0 : 8'd255,
                raw_i[15:11], raw_i[15:13], raw_i[10:5], raw_i[10:9],
                raw_i[4:0], raw_i[4:2]};
            4'd1: expanded_w = raw_i;
            4'd2: expanded_w = {raw_i[7:0], color_i};
            4'd3: expanded_w = {sample_w[3:0], sample_w[3:0], color_i};
            4'd4: expanded_w = {sample_w[1:0], sample_w[1:0],
                sample_w[1:0], sample_w[1:0], color_i};
            4'd5: expanded_w = {{8{sample_w[0]}}, color_i};
            4'd6, 4'd7, 4'd8, 4'd9: expanded_w = palette_i;
            default: expanded_w = 32'd0;
        endcase
        pixel_o[31:24] = divide255(expanded_w[31:24] * opacity_i);
        for (channel = 0; channel < 3; channel = channel + 1)
            pixel_o[channel*8 +: 8] = glyph_i ? color_i[channel*8 +: 8] :
                (recolor_i ? divide255(recolor_value_i[31:24] *
                    recolor_value_i[channel*8 +: 8] +
                    recolor_inverse_w * expanded_w[channel*8 +: 8]) :
                    expanded_w[channel*8 +: 8]);
    end
endmodule
