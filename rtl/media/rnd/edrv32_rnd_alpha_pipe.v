// File: edrv32_rnd_alpha_pipe.v
// Spec: rnd-spec 2.2, 5.2.
// Description: Two-lane non-premultiplied over, normal BLIT blending and synchronous Q lookup.
//              Registered multiplier operands/products and the ROM share an elastic enable.
// Clock domain: clk_mem (clk_i).
module edrv32_rnd_alpha_pipe (
    // Clock and reset.
    input wire clk_i,
    input wire rst_n_i,

    // Pixels: source alpha is the command's effective sa; RGB565 occupies low 16 bits.
    input wire in_valid_i,
    output wire in_ready_o,
    input wire [63:0] in_src_i,
    input wire [63:0] in_dst_i,
    input wire in_argb_i,
    input wire [31:0] in_tag_i,
    output wire out_valid_o,
    input wire out_ready_i,
    output wire [63:0] out_pixel_o,
    output wire [31:0] out_tag_o,
    output wire [39:0] out_offset_o,

    // Discard pending arithmetic on ABORT; bus drainage belongs to the DMA units.
    input wire clear_i
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

    function automatic [31:0] expand565;
        input [15:0] value_i;
        begin
            expand565 = {8'hff, value_i[15:11], value_i[15:13],
                value_i[10:5], value_i[10:9], value_i[4:0], value_i[4:2]};
        end
    endfunction

    wire advance_w;
    reg [8:0] valid_r;
    reg [31:0] tag_r [0:8];
    wire [15:0] oa_w;
    reg [47:0] q_r;
    `include "edrv32_rnd_q.vh"
    integer stage;
    assign advance_w = !valid_r[8] || out_ready_i;
    assign in_ready_o = advance_w && !clear_i;
    assign out_valid_o = valid_r[8];
    assign out_tag_o = tag_r[8];

    always @(posedge clk_i) begin
        if (advance_w) begin
            q_r[23:0] <= edrv32_rnd_q(oa_w[7:0]);
            q_r[47:24] <= edrv32_rnd_q(oa_w[15:8]);
        end
    end

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i)
            valid_r <= 9'd0;
        else if (clear_i)
            valid_r <= 9'd0;
        else if (advance_w)
            valid_r <= {valid_r[7:0], in_valid_i};
    end
    always @(posedge clk_i) begin
        if (advance_w) begin
            tag_r[0] <= in_tag_i;
            for (stage = 1; stage < 9; stage = stage + 1)
                tag_r[stage] <= tag_r[stage-1];
        end
    end

    // Each result-RAM quadrant owns a same-cycle copy of the final shift control.
    genvar quadrant;
    generate for (quadrant = 0; quadrant < 8; quadrant = quadrant + 1) begin : g_offset
        reg [4:0] offset_r /* synthesis syn_preserve=1 */;
        always @(posedge clk_i) begin
            if (advance_w)
                offset_r <= tag_r[7][4:0];
        end
        assign out_offset_o[quadrant*5 +: 5] = offset_r;
    end endgenerate

    genvar lane;
    generate for (lane = 0; lane < 2; lane = lane + 1) begin : g_lane
        wire [31:0] dst_w;
        reg [31:0] dst_input_r;
        reg [31:0] src_input_r;
        reg [31:0] raw_input_r;
        reg [7:0] inverse_input_r;
        reg argb_input_r;
        reg [7:0] inverse_ratio4_r;
        reg [47:0] foreground_product5_r;
        reg [47:0] background_product5_r;
        reg [31:0] raw6_r;
        reg [7:0] oa6_r;
        reg argb6_r;
        reg zero6_r;
        reg [47:0] mix6_r;
        reg [31:0] dst0_r;
        reg [31:0] src0_r;
        reg [31:0] raw0_r;
        reg argb0_r;
        reg [15:0] alpha_product0_r;
        reg [31:0] src1_r;
        reg [31:0] dst1_r;
        reg [31:0] raw1_r;
        reg [7:0] oa1_r;
        reg argb1_r;
        reg [31:0] src2_r;
        reg [31:0] dst2_r;
        reg [31:0] raw2_r;
        reg [7:0] oa2_r;
        reg argb2_r;
        reg [31:0] src3_r;
        reg [31:0] dst3_r;
        reg [31:0] raw3_r;
        reg [7:0] oa3_r;
        reg argb3_r;
        reg [31:0] ratio_product3_r;
        reg [31:0] src4_r;
        reg [31:0] dst4_r;
        reg [31:0] raw4_r;
        reg [7:0] oa4_r;
        reg argb4_r;
        reg [7:0] ratio4_r;
        reg [31:0] raw5_r;
        reg [7:0] oa5_r;
        reg argb5_r;
        reg zero5_r;
        reg [31:0] pixel7_r;
        wire [31:0] rounded_ratio_w;
        wire [23:0] color_w;
        wire unused_ratio_w;
        integer channel;
        assign dst_w = in_argb_i ? in_dst_i[lane*32 +: 32] :
            expand565(in_dst_i[lane*32 +: 16]);
        assign oa_w[lane*8 +: 8] = oa1_r;
        assign rounded_ratio_w = (ratio_product3_r + 32'd32768) >> 16;
        assign unused_ratio_w = ^rounded_ratio_w[31:8];
        assign color_w = {divide255(mix6_r[47:32]), divide255(mix6_r[31:16]),
            divide255(mix6_r[15:0])};
        assign out_pixel_o[lane*32 +: 32] = pixel7_r;

        always @(posedge clk_i) begin
            if (advance_w) begin
                // Input stage: expand destination format and prepare multiplier operands.
                dst_input_r <= dst_w;
                src_input_r <= in_src_i[lane*32 +: 32];
                raw_input_r <= in_dst_i[lane*32 +: 32];
                inverse_input_r <= 8'd255 - in_src_i[lane*32+24 +: 8];
                argb_input_r <= in_argb_i;
                // Stage 0: products go directly to registers.
                dst0_r <= dst_input_r;
                src0_r <= src_input_r;
                raw0_r <= raw_input_r;
                argb0_r <= argb_input_r;
                alpha_product0_r <= inverse_input_r * dst_input_r[31:24];
                // Stage 1: over alpha and normal source color (spec 2.2).
                dst1_r <= dst0_r;
                raw1_r <= raw0_r;
                argb1_r <= argb0_r;
                oa1_r <= src0_r[31:24] + divide255(alpha_product0_r);
                src1_r <= src0_r;
                // Stage 2: synchronous Q read in parallel with payload registration.
                src2_r <= src1_r;
                dst2_r <= dst1_r;
                raw2_r <= raw1_r;
                oa2_r <= oa1_r;
                argb2_r <= argb1_r;
                // Stage 3: reciprocal multiply, 24 x 8 bits.
                src3_r <= src2_r;
                dst3_r <= dst2_r;
                raw3_r <= raw2_r;
                oa3_r <= oa2_r;
                argb3_r <= argb2_r;
                ratio_product3_r <= src2_r[31:24] * q_r[lane*24 +: 24];
                // Stage 4: rounded straight-alpha ratio; RGB565 is always opaque.
                src4_r <= src3_r;
                dst4_r <= dst3_r;
                raw4_r <= raw3_r;
                oa4_r <= oa3_r;
                argb4_r <= argb3_r;
                ratio4_r <= (!argb3_r || dst3_r[31:24] == 8'd255) ?
                    src3_r[31:24] : rounded_ratio_w[7:0];
                inverse_ratio4_r <= 8'd255 - ((!argb3_r || dst3_r[31:24] == 8'd255) ?
                    src3_r[31:24] : rounded_ratio_w[7:0]);
                // Stage 5: foreground/background products have separate registers.
                raw5_r <= raw4_r;
                oa5_r <= oa4_r;
                argb5_r <= argb4_r;
                zero5_r <= src4_r[31:24] == 0;
                for (channel = 0; channel < 3; channel = channel + 1) begin
                    foreground_product5_r[channel*16 +: 16] <=
                        ratio4_r * src4_r[channel*8 +: 8];
                    background_product5_r[channel*16 +: 16] <=
                        inverse_ratio4_r * dst4_r[channel*8 +: 8];
                end
                // Stage 6: complementary weights bound the sum to 16 bits.
                raw6_r <= raw5_r;
                oa6_r <= oa5_r;
                argb6_r <= argb5_r;
                zero6_r <= zero5_r;
                for (channel = 0; channel < 3; channel = channel + 1)
                    mix6_r[channel*16 +: 16] <= foreground_product5_r[channel*16 +: 16] +
                        background_product5_r[channel*16 +: 16];
                // Stage 7: normalize and pack; the output remains registered.
                if (zero6_r)
                    pixel7_r <= raw6_r;
                else if (argb6_r)
                    pixel7_r <= oa6_r == 0 ? 32'd0 : {oa6_r, color_w};
                else
                    pixel7_r <= {16'd0, color_w[23:19], color_w[15:10], color_w[7:3]};
            end
        end
    end endgenerate
endmodule
