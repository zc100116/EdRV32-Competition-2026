// ============================================================================
// File        : edrv32_render_alpha_pipe.v
// Description : Two-pixel premultiplied source-over pipeline.
// Notes       : Three elastic stages; accepted inputs may advance every clock.
// ============================================================================

module edrv32_render_alpha_pipe (
    input  wire         clk_i,
    input  wire         rst_n_i,

    input  wire         in_valid_i,
    output wire         in_ready_o,
    input  wire [63:0]  in_src_i,
    input  wire [63:0]  in_dst_i,
    input  wire [15:0]  in_opacity_i,
    input  wire         in_src_premul_i,
    input  wire [31:0]  in_tag_i,

    output wire         out_valid_o,
    input  wire         out_ready_i,
    output wire [63:0]  out_pixel_o,
    output wire [31:0]  out_tag_o
);

    function [7:0] mul255;
        input [7:0] a;
        input [7:0] b;
        reg [15:0] product;
        reg [16:0] rounded;
        begin
            product = a * b;
            rounded = {1'b0, product} + 17'd128;
            rounded = rounded + (rounded >> 8);
            mul255 = rounded[15:8];
        end
    endfunction

    function [7:0] sat_add;
        input [7:0] a;
        input [7:0] b;
        reg [8:0] sum;
        begin
            sum = {1'b0, a} + {1'b0, b};
            sat_add = sum[8] ? 8'hff : sum[7:0];
        end
    endfunction

    reg         valid1_r;
    reg [63:0]  src1_r;
    reg [63:0]  dst1_r;
    reg [15:0]  opacity1_r;
    reg [31:0]  tag1_r;

    reg         valid2_r;
    reg [63:0]  src2_r;
    reg [63:0]  dst2_r;
    reg [31:0]  tag2_r;

    reg         valid3_r;
    reg [63:0]  pixel3_r;
    reg [31:0]  tag3_r;

    wire ready3_w = !valid3_r || out_ready_i;
    wire ready2_w = !valid2_r || ready3_w;
    wire ready1_w = !valid1_r || ready2_w;
    wire [7:0] inv_alpha0_w = 8'hff - src2_r[31:24];
    wire [7:0] inv_alpha1_w = 8'hff - src2_r[63:56];

    assign in_ready_o   = ready1_w;
    assign out_valid_o  = valid3_r;
    assign out_pixel_o  = pixel3_r;
    assign out_tag_o    = tag3_r;

    integer lane1;
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            valid1_r <= 1'b0;
        end else if (ready1_w) begin
            valid1_r <= in_valid_i;
            if (in_valid_i) begin
                dst1_r     <= in_dst_i;
                opacity1_r <= in_opacity_i;
                tag1_r     <= in_tag_i;
                for (lane1 = 0; lane1 < 2; lane1 = lane1 + 1) begin
                    src1_r[lane1*32+24 +: 8] <=
                        in_src_i[lane1*32+24 +: 8];
                    src1_r[lane1*32+16 +: 8] <= in_src_premul_i ?
                        in_src_i[lane1*32+16 +: 8] :
                        mul255(in_src_i[lane1*32+16 +: 8],
                               in_src_i[lane1*32+24 +: 8]);
                    src1_r[lane1*32+8 +: 8] <= in_src_premul_i ?
                        in_src_i[lane1*32+8 +: 8] :
                        mul255(in_src_i[lane1*32+8 +: 8],
                               in_src_i[lane1*32+24 +: 8]);
                    src1_r[lane1*32 +: 8] <= in_src_premul_i ?
                        in_src_i[lane1*32 +: 8] :
                        mul255(in_src_i[lane1*32 +: 8],
                               in_src_i[lane1*32+24 +: 8]);
                end
            end
        end
    end

    integer lane2;
    integer channel2;
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            valid2_r <= 1'b0;
        end else if (ready2_w) begin
            valid2_r <= valid1_r;
            if (valid1_r) begin
                dst2_r <= dst1_r;
                tag2_r <= tag1_r;
                for (lane2 = 0; lane2 < 2; lane2 = lane2 + 1)
                    for (channel2 = 0; channel2 < 4;
                         channel2 = channel2 + 1)
                        src2_r[lane2*32+channel2*8 +: 8] <=
                            mul255(src1_r[lane2*32+channel2*8 +: 8],
                                   opacity1_r[lane2*8 +: 8]);
            end
        end
    end

    integer lane3;
    integer channel3;
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            valid3_r <= 1'b0;
        end else if (ready3_w) begin
            valid3_r <= valid2_r;
            if (valid2_r) begin
                tag3_r <= tag2_r;
                for (lane3 = 0; lane3 < 2; lane3 = lane3 + 1) begin
                    for (channel3 = 0; channel3 < 4;
                         channel3 = channel3 + 1)
                        pixel3_r[lane3*32+channel3*8 +: 8] <=
                            sat_add(src2_r[lane3*32+channel3*8 +: 8],
                                    mul255(dst2_r[lane3*32+channel3*8 +: 8],
                                           lane3 == 0 ? inv_alpha0_w :
                                                        inv_alpha1_w));
                end
            end
        end
    end

endmodule
