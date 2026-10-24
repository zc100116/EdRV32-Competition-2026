`timescale 1ns/1ps

module tb_render_alpha_pipe;
    localparam integer COUNT = 256;
    reg clk;
    reg rst_n;
    reg in_valid;
    wire in_ready;
    reg [63:0] in_src;
    reg [63:0] in_dst;
    reg [15:0] in_opacity;
    reg in_src_premul;
    reg [31:0] in_tag;
    wire out_valid;
    reg out_ready;
    wire [63:0] out_pixel;
    wire [31:0] out_tag;

    reg [63:0] stimulus_src [0:COUNT-1];
    reg [63:0] stimulus_dst [0:COUNT-1];
    reg [15:0] stimulus_opacity [0:COUNT-1];
    reg stimulus_premul [0:COUNT-1];
    reg [63:0] expected [0:COUNT-1];
    integer sent;
    integer received;
    integer cycles;
    integer index;
    integer lane;
    integer chan;
    integer a;
    integer color;
    reg stalled;
    reg [63:0] stalled_pixel;
    reg [31:0] stalled_tag;

    always #5 clk = ~clk;

    function automatic [7:0] ref_mul;
        input [7:0] lhs;
        input [7:0] rhs;
        integer value;
        begin
            value = (integer'(lhs) * integer'(rhs) + 127) / 255;
            ref_mul = value[7:0];
        end
    endfunction

    function automatic [7:0] ref_sat;
        input integer value;
        begin
            ref_sat = value > 255 ? 8'hff : value[7:0];
        end
    endfunction

    function automatic [31:0] ref_pixel;
        input [31:0] src;
        input [31:0] dst;
        input [7:0] opacity;
        input premul;
        integer ch;
        reg [31:0] result;
        reg [7:0] source_channel;
        reg [7:0] effective_alpha;
        begin
            result = 32'b0;
            effective_alpha = ref_mul(src[31:24], opacity);
            for (ch = 0; ch < 4; ch = ch + 1) begin
                source_channel = src[ch*8 +: 8];
                if (!premul && ch != 3)
                    source_channel = ref_mul(source_channel, src[31:24]);
                source_channel = ref_mul(source_channel, opacity);
                result[ch*8 +: 8] = ref_sat(
                    integer'(source_channel) +
                    integer'(ref_mul(dst[ch*8 +: 8],
                                     8'hff - effective_alpha)));
            end
            ref_pixel = result;
        end
    endfunction

    edrv32_render_alpha_pipe u_dut (
        .clk_i            (clk),
        .rst_n_i          (rst_n),
        .in_valid_i       (in_valid),
        .in_ready_o       (in_ready),
        .in_src_i         (in_src),
        .in_dst_i         (in_dst),
        .in_opacity_i     (in_opacity),
        .in_src_premul_i  (in_src_premul),
        .in_tag_i         (in_tag),
        .out_valid_o      (out_valid),
        .out_ready_i      (out_ready),
        .out_pixel_o      (out_pixel),
        .out_tag_o        (out_tag)
    );

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        in_valid = 1'b0;
        in_src = 64'b0;
        in_dst = 64'b0;
        in_opacity = 16'b0;
        in_src_premul = 1'b0;
        in_tag = 32'b0;
        out_ready = 1'b0;
        sent = 0;
        received = 0;
        cycles = 0;
        stalled = 1'b0;

        for (index = 0; index < COUNT; index = index + 1) begin
            stimulus_premul[index] = index[0];
            stimulus_opacity[index] = {
                $urandom_range(0, 255), $urandom_range(0, 255)};
            stimulus_src[index] = 64'b0;
            stimulus_dst[index] = 64'b0;
            for (lane = 0; lane < 2; lane = lane + 1) begin
                a = $urandom_range(0, 255);
                if (index == 0) a = 0;
                if (index == 1) a = 255;
                stimulus_src[index][lane*32+24 +: 8] = a[7:0];
                stimulus_dst[index][lane*32+24 +: 8] =
                    $urandom_range(0, 255);
                for (chan = 0; chan < 3; chan = chan + 1) begin
                    color = $urandom_range(0, 255);
                    if (stimulus_premul[index]) color = (color * a) / 255;
                    stimulus_src[index][lane*32+chan*8 +: 8] = color[7:0];
                    stimulus_dst[index][lane*32+chan*8 +: 8] =
                        $urandom_range(0, 255);
                end
            end
            expected[index] = {
                ref_pixel(stimulus_src[index][63:32],
                          stimulus_dst[index][63:32],
                          stimulus_opacity[index][15:8],
                          stimulus_premul[index]),
                ref_pixel(stimulus_src[index][31:0],
                          stimulus_dst[index][31:0],
                          stimulus_opacity[index][7:0],
                          stimulus_premul[index])};
        end
        repeat (5) @(posedge clk);
        @(negedge clk);
        rst_n = 1'b1;
    end

    always @(negedge clk) begin
        if (rst_n) begin
            out_ready = cycles < 40 ? 1'b1 :
                        ($urandom_range(0, 3) != 0);
            in_valid = sent < COUNT;
            if (sent < COUNT) begin
                in_src = stimulus_src[sent];
                in_dst = stimulus_dst[sent];
                in_opacity = stimulus_opacity[sent];
                in_src_premul = stimulus_premul[sent];
                in_tag = sent;
            end
        end
    end

    always @(posedge clk) begin
        if (rst_n) begin
            cycles = cycles + 1;
            if (stalled && (!out_valid || out_pixel !== stalled_pixel ||
                            out_tag !== stalled_tag))
                $fatal(1, "stalled output changed");
            stalled = out_valid && !out_ready;
            if (stalled) begin
                stalled_pixel = out_pixel;
                stalled_tag = out_tag;
            end
            if (in_valid && in_ready)
                sent = sent + 1;
            if (out_valid && out_ready) begin
                if (received >= COUNT || out_tag !== received ||
                    out_pixel !== expected[received])
                    $fatal(1, "pixel mismatch index=%0d tag=%0d got=%h expected=%h",
                           received, out_tag, out_pixel, expected[received]);
                received = received + 1;
            end
            if (received == COUNT) begin
                $display("RENDER_ALPHA_PASS count=%0d cycles=%0d", COUNT, cycles);
                $finish;
            end
            if (cycles > 3000)
                $fatal(1, "alpha pipeline timeout sent=%0d received=%0d",
                       sent, received);
        end
    end
endmodule
