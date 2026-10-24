`timescale 1ns/1ps

module tb_render_image;
    localparam integer WIDTH = 64;
    localparam integer HEIGHT = 48;
    localparam integer PAIRS = WIDTH * HEIGHT / 2;
    reg clk;
    reg rst_n;
    reg in_valid;
    wire in_ready;
    reg [63:0] foreground;
    reg [31:0] base565;
    reg [31:0] in_tag;
    wire [63:0] base_argb;
    wire out_valid;
    wire [63:0] blended;
    wire [31:0] out565;
    wire [31:0] out_tag;
    integer sent;
    integer received;
    integer cycles;
    integer file_id;
    integer x;
    integer y;
    integer pix;
    integer lane;
    reg [15:0] color565;
    reg [31:0] overlay;
    reg [15:0] display_pixel;
    reg [31:0] display_argb;

    always #5 clk = ~clk;

    function automatic [7:0] mul_ref;
        input [7:0] lhs;
        input [7:0] rhs;
        begin
            mul_ref = (integer'(lhs) * integer'(rhs) + 127) / 255;
        end
    endfunction

    function automatic [31:0] overlay_at;
        input integer xpos;
        input integer ypos;
        reg [7:0] a;
        reg [7:0] r;
        reg [7:0] g;
        reg [7:0] b;
        begin
            a = 8'd0;
            r = 8'd0;
            g = 8'd0;
            b = 8'd0;
            if (xpos >= 8 && xpos < 56 && ypos >= 7 && ypos < 41) begin
                a = 8'd178;
                r = 8'd28;
                g = 8'd75;
                b = 8'd222;
            end
            if (xpos >= 13 && xpos < 51 && ypos >= 15 && ypos < 22) begin
                a = 8'd235;
                r = 8'd250;
                g = 8'd220;
                b = 8'd56;
            end
            if (xpos >= 14 && xpos < 50 && ypos >= 29 && ypos < 34) begin
                a = 8'd210;
                r = 8'd255;
                g = 8'd75;
                b = 8'd72;
            end
            overlay_at = {a, mul_ref(r,a), mul_ref(g,a), mul_ref(b,a)};
        end
    endfunction

    function automatic [15:0] background_at;
        input integer xpos;
        input integer ypos;
        reg [7:0] r;
        reg [7:0] g;
        reg [7:0] b;
        begin
            r = 8'd30 + xpos*3;
            g = 8'd45 + ypos*3;
            b = 8'd90 + xpos;
            background_at = {r[7:3], g[7:2], b[7:3]};
        end
    endfunction

    edrv32_render_compose_format u_format (
        .base565_i(base565), .base_argb_o(base_argb),
        .blended_argb_i(blended), .display565_o(out565)
    );

    edrv32_render_alpha_pipe u_pipe (
        .clk_i(clk), .rst_n_i(rst_n),
        .in_valid_i(in_valid), .in_ready_o(in_ready),
        .in_src_i(foreground), .in_dst_i(base_argb),
        .in_opacity_i(16'hffff), .in_src_premul_i(1'b1),
        .in_tag_i(in_tag),
        .out_valid_o(out_valid), .out_ready_i(1'b1),
        .out_pixel_o(blended), .out_tag_o(out_tag)
    );

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        in_valid = 1'b0;
        foreground = 64'b0;
        base565 = 32'b0;
        in_tag = 32'b0;
        sent = 0;
        received = 0;
        cycles = 0;
        file_id = $fopen("sim/build/cases/vision/render-image/render.ppm", "wb");
        if (file_id == 0) $fatal(1, "cannot open render.ppm");
        $fwrite(file_id, "P6\n%0d %0d\n255\n", WIDTH, HEIGHT);
        repeat (5) @(posedge clk);
        @(negedge clk);
        rst_n = 1'b1;
    end

    always @(negedge clk) begin
        if (rst_n) begin
            in_valid = sent < PAIRS;
            if (in_valid) begin
                in_tag = sent;
                for (lane = 0; lane < 2; lane = lane + 1) begin
                    pix = sent*2 + lane;
                    x = pix % WIDTH;
                    y = pix / WIDTH;
                    foreground[lane*32 +: 32] = overlay_at(x, y);
                    base565[lane*16 +: 16] = background_at(x, y);
                end
            end
        end
    end

    always @(posedge clk) begin
        if (rst_n) begin
            cycles = cycles + 1;
            if (in_valid && in_ready)
                sent = sent + 1;
            if (out_valid) begin
                if (out_tag !== received)
                    $fatal(1, "image output order mismatch");
                for (lane = 0; lane < 2; lane = lane + 1) begin
                    display_pixel = out565[lane*16 +: 16];
                    display_argb = u_format.unpack565(display_pixel);
                    $fwrite(file_id, "%c%c%c", display_argb[23:16],
                            display_argb[15:8], display_argb[7:0]);
                end
                received = received + 1;
            end
            if (received == PAIRS) begin
                $fclose(file_id);
                $display("RENDER_IMAGE_PASS pixels=%0d cycles=%0d", WIDTH*HEIGHT,
                         cycles);
                $finish;
            end
            if (cycles > PAIRS + 20)
                $fatal(1, "render image timeout");
        end
    end
endmodule
