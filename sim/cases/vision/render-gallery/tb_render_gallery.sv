`timescale 1ns/1ps

module tb_render_gallery #(
    parameter integer SCALE = 1
);
    localparam integer WIDTH = 640*SCALE;
    localparam integer HEIGHT = 360*SCALE;
    localparam integer BASE_STRIDE = WIDTH*2;
    localparam integer FRONT_STRIDE = WIDTH*4;
    localparam [31:0] LIST_BASE = 32'h0000_1000;
    localparam [31:0] BASE = 32'h0002_0000;
    localparam [31:0] FRONT = 32'h0020_0000;
    localparam [31:0] MASK_BASE = 32'h0060_0000;
    localparam [31:0] BITMAP565 = 32'h0068_0000;
    localparam [31:0] BITMAPARGB = 32'h006a_0000;
    localparam integer SPRITE_W = 24*SCALE;
    localparam integer SPRITE_H = 24*SCALE;
    localparam integer ARGB_W = 20*SCALE;
    localparam integer ARGB_H = 20*SCALE;
    localparam integer FONT_STEP = 3+SCALE;
    localparam integer FONT_W = 5*FONT_STEP;
    localparam integer FONT_H = 7*FONT_STEP;
    localparam [15:0] BASE_COLOR = 16'he73c;

    reg clk, rst_n;
    reg start;
    wire start_ready, busy, done, error;
    reg [31:0] list_base;
    reg [15:0] list_count;
    wire [15:0] completed_count;
    wire [3:0] arid, awid, rid, bid;
    wire [31:0] araddr, awaddr;
    wire [7:0] arlen, awlen;
    wire [2:0] arsize, awsize;
    wire [1:0] arburst, awburst;
    wire [3:0] arqos, awqos;
    wire arvalid, awvalid, rready, wvalid, wlast, bready;
    wire [255:0] wdata, rdata;
    wire [31:0] wstrb;
    wire [1:0] rresp, bresp;
    wire rlast;
    wire model_arready, model_awready, model_rvalid;
    wire model_wready, model_bvalid;
    reg ar_gate, r_gate, aw_gate, w_gate, b_gate;
    reg [511:0] command [0:17];
    integer i, j, x, y, g, gx, gy, font_x, file_id, cycles;
    reg [4:0] font_bits;
    reg [15:0] sprite565_color;
    reg [7:0] sprite_alpha;
    integer sprite_dx, sprite_dy, sprite_radius;
    integer sprite_x565, sprite_xargb, copy_target_x;
    integer round_reads, round_writes;
    integer round_read_bursts, round_write_bursts;
    reg [15:0] actual;
    reg [31:0] rgb;

    always #5 clk = ~clk;

    edrv32_render_engine u_dut (
        .clk_i(clk), .rst_n_i(rst_n),
        .start_i(start), .start_ready_o(start_ready),
        .list_base_i(list_base), .list_count_i(list_count),
        .busy_o(busy), .done_o(done), .error_o(error),
        .completed_count_o(completed_count),
        .compose_direct_start_i(1'b0),
        .compose_direct_ready_o(),
        .compose_direct_base_i(32'd0),
        .compose_direct_base_stride_i(32'd0),
        .compose_direct_front_i(32'd0),
        .compose_direct_front_stride_i(32'd0),
        .compose_direct_target_i(32'd0),
        .compose_direct_target_stride_i(32'd0),
        .compose_direct_width_i(16'd0),
        .compose_direct_height_i(16'd0),
        .compose_direct_done_o(),
        .compose_direct_error_o(),
        .m_arid_o(arid), .m_araddr_o(araddr),
        .m_arlen_o(arlen), .m_arsize_o(arsize),
        .m_arburst_o(arburst), .m_arqos_o(arqos),
        .m_arvalid_o(arvalid), .m_arready_i(model_arready && ar_gate),
        .m_rid_i(rid), .m_rdata_i(rdata), .m_rresp_i(rresp),
        .m_rlast_i(rlast), .m_rvalid_i(model_rvalid && r_gate),
        .m_rready_o(rready),
        .m_awid_o(awid), .m_awaddr_o(awaddr),
        .m_awlen_o(awlen), .m_awsize_o(awsize),
        .m_awburst_o(awburst), .m_awqos_o(awqos),
        .m_awvalid_o(awvalid), .m_awready_i(model_awready && aw_gate),
        .m_wdata_o(wdata), .m_wstrb_o(wstrb),
        .m_wlast_o(wlast), .m_wvalid_o(wvalid),
        .m_wready_i(model_wready && w_gate),
        .m_bid_i(bid), .m_bresp_i(bresp),
        .m_bvalid_i(model_bvalid && b_gate),
        .m_bready_o(bready)
    );

    axi256_mem_model #(.WORDS(262144)) u_mem (
        .clk_i(clk), .rst_n_i(rst_n),
        .awid_i(awid), .awaddr_i(awaddr),
        .awlen_i(awlen), .awsize_i(awsize),
        .awburst_i(awburst), .awvalid_i(awvalid && aw_gate),
        .awready_o(model_awready),
        .wdata_i(wdata), .wstrb_i(wstrb),
        .wlast_i(wlast), .wvalid_i(wvalid && w_gate),
        .wready_o(model_wready),
        .bid_o(bid), .bresp_o(bresp),
        .bvalid_o(model_bvalid), .bready_i(bready && b_gate),
        .arid_i(arid), .araddr_i(araddr),
        .arlen_i(arlen), .arsize_i(arsize),
        .arburst_i(arburst), .arvalid_i(arvalid && ar_gate),
        .arready_o(model_arready),
        .rid_o(rid), .rdata_o(rdata), .rresp_o(rresp),
        .rlast_o(rlast), .rvalid_o(model_rvalid),
        .rready_i(rready && r_gate)
    );

    function automatic [15:0] read_pixel16;
        input integer byte_address;
        begin
            read_pixel16 = u_mem.store[byte_address >> 5]
                                       [(byte_address & 31)*8 +: 16];
        end
    endfunction

    function automatic [4:0] glyph_row;
        input integer glyph;
        input integer row;
        begin
            case (glyph)
                0,3: glyph_row = row == 6 ? 5'b11111 : 5'b10000;
                1: begin
                    if (row <= 3)
                        glyph_row = 5'b10001;
                    else if (row <= 5)
                        glyph_row = 5'b01010;
                    else
                        glyph_row = 5'b00100;
                end
                2: begin
                    case (row)
                        0,6: glyph_row = 5'b01111;
                        1,2: glyph_row = 5'b10000;
                        3: glyph_row = 5'b10111;
                        default: glyph_row = 5'b10001;
                    endcase
                end
                default: glyph_row = 5'b00000;
            endcase
        end
    endfunction

    task automatic set_round;
        input integer index;
        input integer px, py, w, h, radius, border;
        input [31:0] fill_color, border_color;
        integer sx, sy, sw, sh, sr, sb;
        begin
            sx = px*SCALE;
            sy = py*SCALE;
            sw = w*SCALE;
            sh = h*SCALE;
            sr = radius*SCALE;
            sb = border*SCALE;
            command[index] = 512'b0;
            command[index][7:0] = 8'h04;
            command[index][63:32] = FRONT + sy*FRONT_STRIDE;
            command[index][95:64] = FRONT_STRIDE;
            command[index][127:96] = {sw[15:0], sx[15:0]};
            command[index][159:128] = {sr[15:0], sh[15:0]};
            command[index][191:160] = {16'd0, sb[15:0]};
            command[index][223:192] = fill_color;
            command[index][255:224] = border_color;
        end
    endtask

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        start = 1'b0;
        list_base = LIST_BASE;
        list_count = 16'd18;
        ar_gate = 1'b1;
        r_gate = 1'b1;
        aw_gate = 1'b1;
        w_gate = 1'b1;
        b_gate = 1'b1;
        cycles = 0;
        round_reads = 0;
        round_writes = 0;
        round_read_bursts = 0;
        round_write_bursts = 0;
        for (i=0; i<18; i=i+1)
            command[i] = 512'b0;

        command[0][7:0] = 8'h01;
        command[0][63:32] = BASE;
        command[0][95:64] = BASE_STRIDE;
        command[0][127:96] = {WIDTH[15:0],16'd0};
        command[0][143:128] = HEIGHT[15:0];
        command[0][191:160] = {16'd0,BASE_COLOR};

        command[1][7:0] = 8'h02;
        command[1][63:32] = FRONT;
        command[1][95:64] = FRONT_STRIDE;
        command[1][127:96] = {WIDTH[15:0],16'd0};
        command[1][143:128] = HEIGHT[15:0];
        command[1][191:160] = 32'd0;

        set_round(2, 45, 28, 550, 185, 32, 4,
                  32'he8ff_ffff, 32'hff46_6988);
        set_round(3, 76, 64, 206, 44, 22, 2,
                  32'he833_a8e8, 32'hffff_ffff);
        set_round(4, 319, 65, 158, 132, 8, 4,
                  32'hf0f0_ca68, 32'hffa0_5829);
        set_round(5, 494, 68, 72, 72, 4, 2,
                  32'hff84_62b5, 32'hff52_3678);
        set_round(6, 79, 236, 100, 100, 50, 3,
                  32'hffef_6a63, 32'hff8f_3534);
        set_round(7, 227, 244, 84, 84, 42, 4,
                  32'hc846_c9a0, 32'hff1f_6d61);
        set_round(8, 360, 256, 40, 40, 20, 0,
                  32'hff42_6dd1, 32'd0);
        set_round(9, 433, 251, 145, 54, 27, 5,
                  32'he861_8ac5, 32'hff39_4a7c);

        for (g=0; g<4; g=g+1) begin
            font_x = 95*SCALE + g*(FONT_W+2*FONT_STEP);
            for (gy=0; gy<FONT_H; gy=gy+1) begin
                j = (MASK_BASE + g*FONT_H*32 + gy*32) >> 5;
                u_mem.store[j] = 256'd0;
                font_bits = glyph_row(g,gy/FONT_STEP);
                for (gx=0; gx<FONT_W; gx=gx+1)
                    if (font_bits[4-gx/FONT_STEP])
                        u_mem.store[j][gx*8 +: 8] = 8'hff;
            end
            command[10+g][7:0] = 8'h05;
            command[10+g][63:32] = FRONT +
                                    (135*SCALE)*FRONT_STRIDE;
            command[10+g][95:64] = FRONT_STRIDE;
            command[10+g][127:96] = {FONT_W[15:0],font_x[15:0]};
            command[10+g][143:128] = FONT_H[15:0];
            command[10+g][191:160] = MASK_BASE + g*FONT_H*32;
            command[10+g][223:192] = 32'd32;
            command[10+g][255:224] = 32'hf028_3e51;
        end

        for (gy=0; gy<SPRITE_H; gy=gy+1) begin
            for (j=0; j<4; j=j+1)
                u_mem.store[(BITMAP565 + gy*128 + j*32) >> 5] = 256'd0;
            for (gx=0; gx<64; gx=gx+1) begin
                sprite565_color = (((gx/8)+(gy/8)) & 1) ?
                                  16'h2d58 : 16'hfc48;
                u_mem.store[(BITMAP565 + gy*128 + gx*2) >> 5]
                    [((gx*2)&31)*8 +: 16] = sprite565_color;
            end
        end
        sprite_radius = ARGB_W/2;
        sprite_x565 = 238*SCALE;
        sprite_xargb = 278*SCALE+1;
        copy_target_x = 250*SCALE;
        for (gy=0; gy<ARGB_H; gy=gy+1) begin
            for (j=0; j<8; j=j+1)
                u_mem.store[(BITMAPARGB + gy*256 + j*32) >> 5] =
                    256'd0;
            for (gx=3; gx<3+ARGB_W; gx=gx+1) begin
                sprite_dx = gx-3-sprite_radius;
                sprite_dy = gy-sprite_radius;
                if (sprite_dx*sprite_dx + sprite_dy*sprite_dy <
                    (sprite_radius-1)*(sprite_radius-1))
                    sprite_alpha = 8'hd0;
                else if (sprite_dx*sprite_dx + sprite_dy*sprite_dy <=
                         sprite_radius*sprite_radius)
                    sprite_alpha = 8'h80;
                else
                    sprite_alpha = 8'h00;
                u_mem.store[(BITMAPARGB + gy*256 + gx*4) >> 5]
                    [((gx*4)&31)*8 +: 32] =
                        {sprite_alpha,8'h78,8'h40,8'hd8};
            end
        end

        command[14][31:0] = 32'h00ff_0006;
        command[14][63:32] = FRONT + (135*SCALE)*FRONT_STRIDE;
        command[14][95:64] = FRONT_STRIDE;
        command[14][127:96] = {SPRITE_W[15:0],sprite_x565[15:0]};
        command[14][159:128] = {16'd5,SPRITE_H[15:0]};
        command[14][191:160] = BITMAP565;
        command[14][223:192] = 32'd128;

        command[15][31:0] = 32'h00e0_0106;
        command[15][63:32] = FRONT + (135*SCALE)*FRONT_STRIDE;
        command[15][95:64] = FRONT_STRIDE;
        command[15][127:96] = {ARGB_W[15:0],sprite_xargb[15:0]};
        command[15][159:128] = {16'd3,ARGB_H[15:0]};
        command[15][191:160] = BITMAPARGB;
        command[15][223:192] = 32'd256;

        // Shift a premultiplied foreground tile diagonally with overlap.
        command[16][31:0] = 32'h0000_0107;
        command[16][63:32] = FRONT + (135*SCALE)*FRONT_STRIDE;
        command[16][95:64] = FRONT_STRIDE;
        command[16][127:96] = {SPRITE_W[15:0],sprite_x565[15:0]};
        command[16][159:128] = FRONT + (147*SCALE)*FRONT_STRIDE;
        command[16][191:160] = FRONT_STRIDE;
        command[16][223:192] = {SPRITE_H[15:0],copy_target_x[15:0]};

        command[17][7:0] = 8'h03;
        command[17][63:32] = BASE;
        command[17][95:64] = BASE_STRIDE;
        command[17][127:96] = FRONT;
        command[17][159:128] = FRONT_STRIDE;
        command[17][191:160] = BASE;
        command[17][223:192] = BASE_STRIDE;
        command[17][255:224] = {HEIGHT[15:0],WIDTH[15:0]};

        for (i=0; i<18; i=i+1) begin
            j = (LIST_BASE >> 5) + i*2;
            u_mem.store[j] = command[i][255:0];
            u_mem.store[j+1] = command[i][511:256];
        end

        repeat (5) @(posedge clk);
        @(negedge clk);
        rst_n = 1'b1;
        start = 1'b1;
        @(negedge clk);
        start = 1'b0;
        wait(done);
        if (error || completed_count != 18)
            $fatal(1, "gallery command failure count=%0d error=%b",
                   completed_count,error);
        if (read_pixel16(BASE) !== BASE_COLOR ||
            read_pixel16(BASE + (286*SCALE)*BASE_STRIDE +
                         (380*SCALE)*2) === BASE_COLOR ||
            read_pixel16(BASE + (286*SCALE)*BASE_STRIDE +
                         (100*SCALE)*2) === BASE_COLOR)
            $fatal(1, "gallery background/circle spot check failed");

        file_id = $fopen("sim/build/cases/vision/render-gallery/gallery.ppm",
                         "wb");
        if (file_id == 0)
            $fatal(1, "cannot open gallery.ppm");
        $fwrite(file_id, "P6\n%0d %0d\n255\n", WIDTH, HEIGHT);
        for (y=0; y<HEIGHT; y=y+1)
            for (x=0; x<WIDTH; x=x+1) begin
                actual = read_pixel16(BASE + y*BASE_STRIDE + x*2);
                if (^actual === 1'bx)
                    $fatal(1, "unknown display pixel x=%0d y=%0d",x,y);
                rgb = {8'hff,actual[15:11],actual[15:13],
                       actual[10:5],actual[10:9],
                       actual[4:0],actual[4:2]};
                $fwrite(file_id,"%c%c%c",rgb[23:16],rgb[15:8],rgb[7:0]);
            end
        $fclose(file_id);
        $display("RENDER_GALLERY_PASS size=%0dx%0d shapes=8 glyphs=4 bitmaps=2 copy=1 round_beats=%0d read_bursts=%0d write_bursts=%0d cycles=%0d",
                 WIDTH,HEIGHT,round_reads,round_read_bursts,
                 round_write_bursts,cycles);
        $finish;
    end
    always @(negedge clk) begin
        if (rst_n) begin
            ar_gate = $urandom_range(0,7) != 0;
            r_gate = $urandom_range(0,7) != 0;
            aw_gate = $urandom_range(0,7) != 0;
            w_gate = $urandom_range(0,7) != 0;
            b_gate = $urandom_range(0,7) != 0;
        end
    end

    always @(posedge clk) begin
        if (rst_n) begin
            cycles = cycles + 1;
            if (arvalid && model_arready && ar_gate &&
                u_dut.state_r == 3'd4) begin
                if (arlen > 15 || (araddr[11:0] +
                    (arlen+1)*32) > 4096)
                    $fatal(1, "invalid round read burst");
                round_read_bursts = round_read_bursts + 1;
            end
            if (awvalid && model_awready && aw_gate &&
                u_dut.state_r == 3'd4) begin
                if (awlen > 15 || (awaddr[11:0] +
                    (awlen+1)*32) > 4096)
                    $fatal(1, "invalid round write burst");
                round_write_bursts = round_write_bursts + 1;
            end
            if (rready && model_rvalid && r_gate &&
                u_dut.state_r == 3'd4)
                round_reads = round_reads + 1;
            if (wvalid && model_wready && w_gate &&
                u_dut.state_r == 3'd4)
                round_writes = round_writes + 1;
            if (cycles > 3000000)
                $fatal(1, "render engine timeout state=%0d fetch_busy=%b round_state=%0d done=%b error=%b",
                       u_dut.state_r,u_dut.u_fetch.busy_o,u_dut.u_round.state_r,done,error);
        end
    end
endmodule
