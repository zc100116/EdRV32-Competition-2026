`timescale 1ns/1ps

module tb_render_engine;
    localparam integer WIDTH = 64;
    localparam integer HEIGHT = 32;
    localparam [31:0] LIST_BASE = 32'h0000_1000;
    localparam [31:0] BASE = 32'h0000_2000;
    localparam [31:0] FRONT = 32'h0000_4000;
    localparam [31:0] MASK = 32'h0000_8000;
    localparam [31:0] SRC565 = 32'h0000_9000;
    localparam [31:0] SRCARGB = 32'h0000_a000;
    localparam [31:0] PANEL = 32'hc828_88d0;
    localparam [31:0] BORDER = 32'hffec_6d40;
    localparam [31:0] BAR = 32'hd0e8_dd4a;
    localparam [31:0] A8_COLOR = 32'hc0ff_8040;
    localparam [15:0] BASE_COLOR = 16'h52aa;

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
    reg [511:0] command [0:7];
    integer i, j, x, y, file_id, cycles;
    integer round_reads, round_writes;
    integer round_read_bursts, round_write_bursts;
    integer a8_target_read_bursts, a8_write_bursts;
    integer a8_target_read_beats, a8_write_beats;
    integer bitmap_write_bursts, bitmap_write_beats;
    integer copy_write_bursts, copy_write_beats;
    reg bitmap_eight_beat_witness;
    reg [31:0] fg;
    reg [15:0] actual, wanted;
    reg [31:0] rgb;
    reg [7:0] copy_snapshot [0:303];
    reg [7:0] copy_left_guard [0:15];
    reg [7:0] copy_right_guard [0:15];
    integer copy_byte_address;
    reg [15:0] bitmap_sample565;
    reg [31:0] bitmap_expected_argb;

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

    axi256_mem_model #(.WORDS(8192)) u_mem (
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

    function automatic [7:0] mul_ref;
        input [7:0] lhs;
        input [7:0] rhs;
        begin
            mul_ref = (integer'(lhs) * integer'(rhs) + 127) / 255;
        end
    endfunction

    function automatic integer isqrt_ref;
        input integer n;
        integer root;
        begin
            root = 0;
            while ((root+1)*(root+1) <= n)
                root = root + 1;
            isqrt_ref = root;
        end
    endfunction

    function automatic integer edge_ref;
        input integer r;
        input integer ydist;
        integer rq4, dyq4;
        begin
            if (r == 0 || ydist >= r)
                edge_ref = 0;
            else begin
                rq4 = r*16;
                dyq4 = (r-ydist)*16-8;
                edge_ref = rq4-isqrt_ref(rq4*rq4-dyq4*dyq4);
            end
        end
    endfunction

    function automatic [7:0] coverage_ref;
        input integer px;
        input integer w;
        input integer edge_q4;
        integer room;
        begin
            room = (px+1)*16-edge_q4;
            if (w*16-edge_q4-px*16 < room)
                room = w*16-edge_q4-px*16;
            if (room <= 0)
                coverage_ref = 0;
            else if (room >= 16)
                coverage_ref = 255;
            else
                coverage_ref = room*16;
        end
    endfunction

    function automatic [31:0] over_ref;
        input [31:0] src;
        input [31:0] dst;
        integer c;
        integer v;
        reg [31:0] result;
        begin
            result = 0;
            for (c=0; c<4; c=c+1) begin
                v = integer'(src[c*8 +: 8]) +
                    integer'(mul_ref(dst[c*8 +: 8], 255-src[31:24]));
                result[c*8 +: 8] = v > 255 ? 255 : v;
            end
            over_ref = result;
        end
    endfunction

    function automatic [31:0] round_src_ref;
        input integer xx, yy, ww, hh, radius, border;
        input [31:0] fill_color, border_color;
        integer rad, ydist, outer_edge, inner_edge;
        integer inner_h, inner_y, inner_r, outer_cov, inner_cov;
        integer fa, ba, bv, c;
        integer v;
        reg [31:0] result;
        begin
            rad = radius < (ww<hh ? ww:hh)/2 ? radius : (ww<hh ? ww:hh)/2;
            ydist = yy < hh-1-yy ? yy : hh-1-yy;
            outer_edge = edge_ref(rad, ydist);
            outer_cov = coverage_ref(xx, ww, outer_edge);
            inner_cov = 0;
            inner_h = hh-2*border;
            inner_y = yy-border;
            inner_r = rad > border ? rad-border : 0;
            if (ww>2*border && hh>2*border &&
                yy>=border && yy<hh-border) begin
                ydist = inner_y < inner_h-1-inner_y ?
                        inner_y : inner_h-1-inner_y;
                inner_edge = border*16+edge_ref(inner_r,ydist);
                inner_cov = coverage_ref(xx,ww,inner_edge);
            end
            fa = mul_ref(fill_color[31:24], inner_cov[7:0]);
            ba = mul_ref(border_color[31:24], (outer_cov-inner_cov));
            bv = mul_ref(ba[7:0], 255-fa);
            result = 0;
            v = fa+bv;
            result[31:24] = v>255 ? 255 : v;
            for (c=0; c<3; c=c+1) begin
                v = integer'(mul_ref(fill_color[c*8 +: 8], fa[7:0]))+
                    integer'(mul_ref(border_color[c*8 +: 8], bv[7:0]));
                result[c*8 +: 8] = v>255 ? 255 : v;
            end
            round_src_ref = result;
        end
    endfunction

    function automatic [15:0] source565_at;
        input integer sx, sy;
        reg [4:0] r, b;
        reg [5:0] g;
        begin
            r = (sx*3+sy*7)&31;
            g = (sx*5+sy*11)&63;
            b = (sx*7+sy*13)&31;
            source565_at = {r,g,b};
        end
    endfunction

    function automatic [31:0] source_argb_at;
        input integer sx, sy;
        reg [7:0] a, r, g, b;
        begin
            a = (sx*15+sy*29)&255;
            r = (sx*9+sy*17)&255;
            g = (sx*11+sy*31)&255;
            b = (sx*21+sy*13)&255;
            source_argb_at = {a,r,g,b};
        end
    endfunction

    function automatic [15:0] expected_at;
        input integer xpos;
        input integer ypos;
        reg [7:0] br, bg, bb, rr, gg, bb_out;
        reg [7:0] mask, alpha;
        reg [31:0] glyph_src;
        reg [31:0] bitmap_src, source_color;
        reg [15:0] src565;
        integer c;
        begin
            fg = 32'b0;
            if (xpos >= 8 && xpos < 56 && ypos >= 7 && ypos < 29)
                fg = over_ref(round_src_ref(xpos-8,ypos-7,
                              48,22,8,3,PANEL,BORDER),fg);
            if (xpos >= 13 && xpos < 51 && ypos >= 15 && ypos < 22)
                fg = over_ref(round_src_ref(xpos-13,ypos-15,
                              38,7,3,0,BAR,0),fg);
            if (xpos >= 22 && xpos < 38 && ypos >= 11 && ypos < 19) begin
                mask = ((xpos-22)*17 + (ypos-11)*11) & 8'hff;
                alpha = mul_ref(A8_COLOR[31:24],mask);
                glyph_src = {alpha,
                             mul_ref(A8_COLOR[23:16],alpha),
                             mul_ref(A8_COLOR[15:8],alpha),
                             mul_ref(A8_COLOR[7:0],alpha)};
                fg = over_ref(glyph_src,fg);
            end
            if (xpos >= 5 && xpos < 24 && ypos >= 22 && ypos < 26) begin
                src565 = source565_at(5+xpos-5,ypos-22);
                source_color = {8'hff,
                                src565[15:11],src565[15:13],
                                src565[10:5],src565[10:9],
                                src565[4:0],src565[4:2]};
                for (c=0; c<4; c=c+1)
                    bitmap_src[c*8 +: 8] =
                        mul_ref(source_color[c*8 +: 8],8'hb4);
                fg = over_ref(bitmap_src,fg);
            end
            if (xpos >= 39 && xpos < 53 && ypos >= 9 && ypos < 14) begin
                source_color = source_argb_at(3+xpos-39,ypos-9);
                bitmap_src[31:24] = source_color[31:24];
                for (c=0; c<3; c=c+1)
                    bitmap_src[c*8 +: 8] =
                        mul_ref(source_color[c*8 +: 8],
                                source_color[31:24]);
                for (c=0; c<4; c=c+1)
                    bitmap_src[c*8 +: 8] =
                        mul_ref(bitmap_src[c*8 +: 8],8'h9f);
                fg = over_ref(bitmap_src,fg);
            end
            br = {BASE_COLOR[15:11], BASE_COLOR[15:13]};
            bg = {BASE_COLOR[10:5], BASE_COLOR[10:9]};
            bb = {BASE_COLOR[4:0], BASE_COLOR[4:2]};
            rr = fg[23:16] + mul_ref(br, 8'hff - fg[31:24]);
            gg = fg[15:8] + mul_ref(bg, 8'hff - fg[31:24]);
            bb_out = fg[7:0] + mul_ref(bb, 8'hff - fg[31:24]);
            expected_at = {rr[7:3], gg[7:2], bb_out[7:3]};
        end
    endfunction

    function automatic [15:0] read_pixel16;
        input integer byte_address;
        begin
            read_pixel16 = u_mem.store[byte_address >> 5]
                                       [(byte_address & 31)*8 +: 16];
        end
    endfunction

    function automatic [7:0] read_byte;
        input integer byte_address;
        begin
            read_byte = u_mem.store[byte_address >> 5]
                                   [(byte_address & 31)*8 +: 8];
        end
    endfunction

    function automatic [31:0] read_pixel32;
        input integer byte_address;
        begin
            read_pixel32 = u_mem.store[byte_address >> 5]
                                        [(byte_address & 31)*8 +: 32];
        end
    endfunction

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        start = 1'b0;
        list_base = LIST_BASE;
        list_count = 16'd8;
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
        a8_target_read_bursts = 0;
        a8_write_bursts = 0;
        a8_target_read_beats = 0;
        a8_write_beats = 0;
        bitmap_write_bursts = 0;
        bitmap_write_beats = 0;
        copy_write_bursts = 0;
        copy_write_beats = 0;
        bitmap_eight_beat_witness = 1'b0;
        for (i = 0; i < 8192; i = i + 1)
            u_mem.store[i] = {32{8'ha5}};
        for (i = 0; i < 8; i = i + 1)
            command[i] = 512'b0;
        for (y = 0; y < 8; y = y + 1) begin
            u_mem.store[(MASK + y*32) >> 5] = 256'd0;
            for (x = 0; x < 16; x = x + 1)
                u_mem.store[(MASK + y*32) >> 5][x*8 +: 8] =
                    (x*17 + y*11) & 8'hff;
        end
        for (y = 0; y < 4; y = y + 1) begin
            u_mem.store[(SRC565 + y*64) >> 5] = 256'd0;
            u_mem.store[(SRC565 + y*64 + 32) >> 5] = 256'd0;
            for (x = 0; x < 32; x = x + 1)
                u_mem.store[(SRC565 + y*64 + x*2) >> 5]
                    [((x*2)&31)*8 +: 16] = source565_at(x,y);
        end
        for (y = 0; y < 5; y = y + 1) begin
            for (j = 0; j < 3; j = j + 1)
                u_mem.store[(SRCARGB + y*96 + j*32) >> 5] = 256'd0;
            for (x = 0; x < 24; x = x + 1)
                u_mem.store[(SRCARGB + y*96 + x*4) >> 5]
                    [((x*4)&31)*8 +: 32] = source_argb_at(x,y);
        end

        // Opaque RGB565 base.
        command[0][31:0] = 32'h0000_0001;
        command[0][63:32] = BASE;
        command[0][95:64] = 32'd128;
        command[0][127:96] = {16'd64,16'd0};
        command[0][143:128] = 16'd32;
        command[0][191:160] = {16'b0, BASE_COLOR};

        // Transparent foreground followed by two rounded shapes.
        command[1][31:0] = 32'h0000_0002;
        command[1][63:32] = FRONT;
        command[1][95:64] = 32'd256;
        command[1][127:96] = {16'd64,16'd0};
        command[1][143:128] = 16'd32;
        command[1][191:160] = 32'b0;
        command[2][31:0] = 32'h0000_0004;
        command[2][63:32] = FRONT + 7*256;
        command[2][95:64] = 32'd256;
        command[2][127:96] = {16'd48,16'd8};
        command[2][143:128] = 16'd22;
        command[2][159:144] = 16'd8;
        command[2][175:160] = 16'd3;
        command[2][223:192] = PANEL;
        command[2][255:224] = BORDER;
        command[3][31:0] = 32'h0000_0004;
        command[3][63:32] = FRONT + 15*256;
        command[3][95:64] = 32'd256;
        command[3][127:96] = {16'd38,16'd13};
        command[3][143:128] = 16'd7;
        command[3][159:144] = 16'd3;
        command[3][175:160] = 16'd0;
        command[3][223:192] = BAR;

        command[4][31:0] = 32'h0000_0005;
        command[4][63:32] = FRONT + 11*256;
        command[4][95:64] = 32'd256;
        command[4][127:96] = {16'd16,16'd22};
        command[4][143:128] = 16'd8;
        command[4][191:160] = MASK;
        command[4][223:192] = 32'd32;
        command[4][255:224] = A8_COLOR;

        command[5][31:0] = 32'h00b4_0006;
        command[5][63:32] = FRONT + 22*256;
        command[5][95:64] = 32'd256;
        command[5][127:96] = {16'd19,16'd5};
        command[5][159:128] = {16'd5,16'd4};
        command[5][191:160] = SRC565;
        command[5][223:192] = 32'd64;

        command[6][31:0] = 32'h009f_0106;
        command[6][63:32] = FRONT + 9*256;
        command[6][95:64] = 32'd256;
        command[6][127:96] = {16'd14,16'd39};
        command[6][159:128] = {16'd3,16'd5};
        command[6][191:160] = SRCARGB;
        command[6][223:192] = 32'd96;

        command[7][31:0] = 32'h0000_0003;
        command[7][63:32] = BASE;
        command[7][95:64] = 32'd128;
        command[7][127:96] = FRONT;
        command[7][159:128] = 32'd256;
        command[7][191:160] = BASE;
        command[7][223:192] = 32'd128;
        command[7][255:224] = {16'd32,16'd64};

        for (i = 0; i < 8; i = i + 1) begin
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
        if (error || completed_count != 8 ||
            round_reads != 174 || round_writes != 174 ||
            round_read_bursts != 29 || round_write_bursts != 29 ||
            a8_target_read_bursts != 8 || a8_write_bursts != 8 ||
            a8_target_read_beats != 24 || a8_write_beats != 24 ||
            bitmap_write_bursts != 9 || bitmap_write_beats != 27)
            $fatal(1, "engine commands=%0d error=%b round_read=%0d round_write=%0d",
                   completed_count,error,round_reads,round_writes);

        file_id = $fopen("sim/build/cases/vision/render-engine/render.ppm", "wb");
        if (file_id == 0) $fatal(1, "cannot open render.ppm");
        $fwrite(file_id, "P6\n64 32\n255\n");
        for (y = 0; y < HEIGHT; y = y + 1)
            for (x = 0; x < WIDTH; x = x + 1) begin
                actual = read_pixel16(BASE + y*128 + x*2);
                wanted = expected_at(x,y);
                if (actual !== wanted)
                    $fatal(1, "render mismatch x=%0d y=%0d got=%h want=%h",
                           x,y,actual,wanted);
                rgb = {8'hff, actual[15:11],actual[15:13],
                       actual[10:5],actual[10:9],
                       actual[4:0],actual[4:2]};
                $fwrite(file_id, "%c%c%c", rgb[23:16],rgb[15:8],rgb[7:0]);
            end
        $fclose(file_id);

        u_mem.store[LIST_BASE >> 5][7:0] = 8'hff;
        @(negedge clk);
        if (!start_ready) $fatal(1, "engine did not release command list");
        list_count = 16'd1;
        start = 1'b1;
        @(negedge clk);
        start = 1'b0;
        wait(done);
        if (!error || completed_count != 0)
            $fatal(1, "unsupported opcode did not stop batch");

        // Invalid rounded rectangle must stop without issuing a Surface read.
        wait(start_ready);
        @(negedge clk);
        command[0] = 512'b0;
        command[0][7:0] = 8'h04;
        command[0][63:32] = FRONT;
        command[0][95:64] = 32'd256;
        command[0][127:96] = {16'd16,16'hfff8};
        command[0][143:128] = 16'd2;
        u_mem.store[LIST_BASE >> 5] = command[0][255:0];
        u_mem.store[(LIST_BASE >> 5)+1] = command[0][511:256];
        start = 1'b1;
        @(negedge clk);
        start = 1'b0;
        wait(done);
        if (!error || completed_count != 1 ||
            round_reads != 174 || round_writes != 174 ||
            round_read_bursts != 29 || round_write_bursts != 29)
            $fatal(1, "invalid rounded rectangle was not rejected");

        // A two-beat row straddles 4 KiB, so it must use two AXI bursts.
        wait(start_ready);
        @(negedge clk);
        command[0] = 512'b0;
        command[0][7:0] = 8'h04;
        command[0][63:32] = 32'h0000_5fe0;
        command[0][95:64] = 32'd256;
        command[0][127:96] = {16'd16,16'd0};
        command[0][143:128] = 16'd1;
        command[0][223:192] = 32'hffff_ffff;
        u_mem.store[LIST_BASE >> 5] = command[0][255:0];
        u_mem.store[(LIST_BASE >> 5)+1] = command[0][511:256];
        u_mem.store[32'h5fe0 >> 5] = {32{8'h55}};
        u_mem.store[32'h6000 >> 5] = {32{8'h55}};
        start = 1'b1;
        @(negedge clk);
        start = 1'b0;
        wait(done);
        if (error || completed_count != 1 ||
            round_reads != 176 || round_writes != 176 ||
            round_read_bursts != 31 || round_write_bursts != 31 ||
            u_mem.store[32'h5fe0 >> 5] !== {8{32'hffff_ffff}} ||
            u_mem.store[32'h6000 >> 5] !== {8{32'hffff_ffff}})
            $fatal(1, "4 KiB boundary rounded rectangle failed");

        // Command path for overlapping ARGB COPY; the source is snapshotted.
        for (y=0; y<4; y=y+1) begin
            for (x=0; x<76; x=x+1) begin
                copy_byte_address = FRONT + (24+y)*256 + 5*4 + x;
                copy_snapshot[y*76+x] = read_byte(copy_byte_address);
            end
            for (x=0; x<4; x=x+1) begin
                copy_left_guard[y*4+x] =
                    read_byte(FRONT + (24+y)*256 + 8*4+x);
                copy_right_guard[y*4+x] =
                    read_byte(FRONT + (24+y)*256 + 28*4+x);
            end
        end
        wait(start_ready);
        @(negedge clk);
        command[0] = 512'b0;
        command[0][31:0] = 32'h0000_0107;
        command[0][63:32] = FRONT + 24*256;
        command[0][95:64] = 32'd256;
        command[0][127:96] = {16'd19,16'd5};
        command[0][159:128] = FRONT + 24*256;
        command[0][191:160] = 32'd256;
        command[0][223:192] = {16'd4,16'd9};
        u_mem.store[LIST_BASE >> 5] = command[0][255:0];
        u_mem.store[(LIST_BASE >> 5)+1] = command[0][511:256];
        start = 1'b1;
        @(negedge clk);
        start = 1'b0;
        wait(done);
        if (error || completed_count != 1 ||
            copy_write_bursts != 4 || copy_write_beats != 12)
            $fatal(1, "engine overlapping COPY failed");
        for (y=0; y<4; y=y+1) begin
            for (x=0; x<76; x=x+1)
                if (read_byte(FRONT + (24+y)*256 + 9*4 + x) !==
                    copy_snapshot[y*76+x])
                    $fatal(1, "engine COPY mismatch row=%0d byte=%0d",
                           y,x);
            for (x=0; x<4; x=x+1)
                if (read_byte(FRONT + (24+y)*256 + 8*4+x) !==
                        copy_left_guard[y*4+x] ||
                    read_byte(FRONT + (24+y)*256 + 28*4+x) !==
                        copy_right_guard[y*4+x])
                    $fatal(1, "engine COPY changed edge pixel");
        end

        // Two A8 destination beats straddle 4 KiB and must split.
        wait(start_ready);
        @(negedge clk);
        command[0] = 512'b0;
        command[0][31:0] = 32'h0000_0005;
        command[0][63:32] = 32'h0000_5fe0;
        command[0][95:64] = 32'd256;
        command[0][127:96] = {16'd16,16'd0};
        command[0][143:128] = 16'd1;
        command[0][191:160] = MASK;
        command[0][223:192] = 32'd32;
        command[0][255:224] = 32'hffff_ffff;
        u_mem.store[LIST_BASE >> 5] = command[0][255:0];
        u_mem.store[(LIST_BASE >> 5)+1] = command[0][511:256];
        u_mem.store[MASK >> 5] = {32{8'hff}};
        u_mem.store[32'h5fe0 >> 5] = 256'd0;
        u_mem.store[32'h6000 >> 5] = 256'd0;
        start = 1'b1;
        @(negedge clk);
        start = 1'b0;
        wait(done);
        if (error || completed_count != 1 ||
            a8_target_read_bursts != 10 || a8_write_bursts != 10 ||
            a8_target_read_beats != 26 || a8_write_beats != 26 ||
            u_mem.store[32'h5fe0 >> 5] !== {8{32'hffff_ffff}} ||
            u_mem.store[32'h6000 >> 5] !== {8{32'hffff_ffff}})
            $fatal(1,"A8 4 KiB split failed");

        // Maximum 32-pixel mask at X=7 spans five destination beats.
        wait(start_ready);
        @(negedge clk);
        command[0] = 512'b0;
        command[0][31:0] = 32'h0000_0005;
        command[0][63:32] = 32'h0000_7000;
        command[0][95:64] = 32'd256;
        command[0][127:96] = {16'd32,16'd7};
        command[0][143:128] = 16'd1;
        command[0][191:160] = MASK;
        command[0][223:192] = 32'd32;
        command[0][255:224] = 32'hff00_11cc;
        u_mem.store[LIST_BASE >> 5] = command[0][255:0];
        u_mem.store[(LIST_BASE >> 5)+1] = command[0][511:256];
        for (x=0; x<5; x=x+1)
            u_mem.store[(32'h7000 >> 5)+x] = 256'd0;
        start = 1'b1;
        @(negedge clk);
        start = 1'b0;
        wait(done);
        if (error || completed_count != 1 ||
            a8_target_read_bursts != 11 || a8_write_bursts != 11 ||
            a8_target_read_beats != 31 || a8_write_beats != 31)
            $fatal(1,"A8 five-beat tile failed");
        for (x=0; x<40; x=x+1)
            if (read_pixel32(32'h7000+x*4) !==
                ((x>=7 && x<39) ? 32'hff00_11cc : 32'd0))
                $fatal(1,"A8 five-beat pixel mismatch x=%0d",x);

        // Bitmap write tile: one beat before 4 KiB, then eight beats after.
        wait(start_ready);
        @(negedge clk);
        command[0] = 512'b0;
        command[0][31:0] = 32'h00ff_0006;
        command[0][63:32] = 32'h0000_bfe0;
        command[0][95:64] = 32'd512;
        command[0][127:96] = {16'd64,16'd7};
        command[0][159:128] = {16'd0,16'd1};
        command[0][191:160] = 32'h0000_d000;
        command[0][223:192] = 32'd128;
        u_mem.store[LIST_BASE >> 5] = command[0][255:0];
        u_mem.store[(LIST_BASE >> 5)+1] = command[0][511:256];
        for (x=0; x<4; x=x+1)
            u_mem.store[(32'hd000 >> 5)+x] = 256'd0;
        for (x=0; x<64; x=x+1)
            u_mem.store[(32'hd000+x*2) >> 5]
                [((x*2)&31)*8 +: 16] = source565_at(x,0);
        for (x=0; x<9; x=x+1)
            u_mem.store[(32'hbfe0 >> 5)+x] = 256'd0;
        start = 1'b1;
        @(negedge clk);
        start = 1'b0;
        wait(done);
        if (error || completed_count != 1 ||
            bitmap_write_bursts != 11 ||
            bitmap_write_beats != 36 ||
            !bitmap_eight_beat_witness)
            $fatal(1,"bitmap eight-beat write tile failed");
        for (x=0; x<72; x=x+1) begin
            bitmap_expected_argb = 32'd0;
            if (x>=7 && x<71) begin
                bitmap_sample565 = source565_at(x-7,0);
                bitmap_expected_argb = {8'hff,
                    bitmap_sample565[15:11],bitmap_sample565[15:13],
                    bitmap_sample565[10:5],bitmap_sample565[10:9],
                    bitmap_sample565[4:0],bitmap_sample565[4:2]};
            end
            if (read_pixel32(32'hbfe0+x*4) !== bitmap_expected_argb)
                $fatal(1,"bitmap tile pixel mismatch x=%0d",x);
        end

        // Flip both axes and leave color-key pixels untouched.
        wait(start_ready);
        @(negedge clk);
        command[0] = 512'd0;
        command[0][31:0] = 32'h00ff_1c06;
        command[0][63:32] = 32'h0000_e100;
        command[0][95:64] = 32'd128;
        command[0][127:96] = {16'd8,16'd3};
        command[0][159:128] = {16'd0,16'd2};
        command[0][191:160] = 32'h0000_e020;
        command[0][223:192] = 32'd32;
        command[0][255:224] = 32'h0000_001f;
        u_mem.store[LIST_BASE >> 5] = command[0][255:0];
        u_mem.store[(LIST_BASE >> 5)+1] = command[0][511:256];
        for (y=0; y<2; y=y+1) begin
            for (x=0; x<8; x=x+1)
                u_mem.store[((32'h0000_e000+y*32) >> 5)]
                    [x*16 +: 16] = (x & 1) ? 16'h001f :
                                   (y == 0 ? 16'hf800 : 16'h07e0);
            for (x=0; x<4; x=x+1)
                u_mem.store[((32'h0000_e100+y*128) >> 5)+x] =
                    {8{32'hff11_2233}};
        end
        start = 1'b1;
        @(negedge clk);
        start = 1'b0;
        wait(done);
        if (error || completed_count != 1)
            $fatal(1,"bitmap flip and color key command failed");
        for (y=0; y<2; y=y+1)
            for (x=0; x<16; x=x+1) begin
                bitmap_expected_argb = 32'hff11_2233;
                if (x>=3 && x<11 && ((10-x) & 1) == 0)
                    bitmap_expected_argb = y == 0 ?
                        32'hff00_ff00 : 32'hffff_0000;
                if (read_pixel32(32'h0000_e100+y*128+x*4) !==
                    bitmap_expected_argb)
                    $fatal(1,"bitmap flip/key mismatch x=%0d y=%0d got=%h want=%h",
                           x,y,
                           read_pixel32(32'h0000_e100+y*128+x*4),
                           bitmap_expected_argb);
            end

        // Premultiplied ARGB color key is tested before source-over mixing.
        wait(start_ready);
        @(negedge clk);
        command[0] = 512'd0;
        command[0][31:0] = 32'h00ff_1706;
        command[0][63:32] = 32'h0000_e500;
        command[0][95:64] = 32'd64;
        command[0][127:96] = {16'd8,16'd0};
        command[0][159:128] = {16'd0,16'd1};
        command[0][191:160] = 32'h0000_e400;
        command[0][223:192] = 32'd32;
        command[0][255:224] = 32'hffff_00ff;
        u_mem.store[LIST_BASE >> 5] = command[0][255:0];
        u_mem.store[(LIST_BASE >> 5)+1] = command[0][511:256];
        for (x=0; x<8; x=x+1)
            u_mem.store[32'h0000_e400 >> 5][x*32 +: 32] =
                (x & 1) ? 32'h8080_0000 : 32'hffff_00ff;
        u_mem.store[32'h0000_e500 >> 5] = {8{32'hff00_00ff}};
        start = 1'b1;
        @(negedge clk);
        start = 1'b0;
        wait(done);
        if (error || completed_count != 1)
            $fatal(1,"ARGB color key command failed");
        for (x=0; x<8; x=x+1) begin
            bitmap_expected_argb = (x & 1) ?
                32'hff00_00ff : 32'hff80_007f;
            if (read_pixel32(32'h0000_e500+x*4) !==
                bitmap_expected_argb)
                $fatal(1,"ARGB color key mismatch x=%0d got=%h want=%h",
                       x,read_pixel32(32'h0000_e500+x*4),
                       bitmap_expected_argb);
        end

        // Reversed source selection crosses a 256-bit source-beat boundary.
        wait(start_ready);
        @(negedge clk);
        command[0] = 512'd0;
        command[0][31:0] = 32'h00ff_0406;
        command[0][63:32] = 32'h0000_e700;
        command[0][95:64] = 32'd128;
        command[0][127:96] = {16'd8,16'd7};
        command[0][159:128] = {16'd13,16'd1};
        command[0][191:160] = 32'h0000_e600;
        command[0][223:192] = 32'd64;
        u_mem.store[LIST_BASE >> 5] = command[0][255:0];
        u_mem.store[(LIST_BASE >> 5)+1] = command[0][511:256];
        for (x=0; x<32; x=x+1)
            u_mem.store[(32'h0000_e600+x*2) >> 5]
                [((x*2)&31)*8 +: 16] = source565_at(x,0);
        for (x=0; x<2; x=x+1)
            u_mem.store[(32'h0000_e700 >> 5)+x] = 256'd0;
        start = 1'b1;
        @(negedge clk);
        start = 1'b0;
        wait(done);
        if (error || completed_count != 1)
            $fatal(1,"flipped source-boundary bitmap failed");
        for (x=0; x<16; x=x+1) begin
            bitmap_expected_argb = 32'd0;
            if (x>=7 && x<15) begin
                bitmap_sample565 = source565_at(27-x,0);
                bitmap_expected_argb = {8'hff,
                    bitmap_sample565[15:11],bitmap_sample565[15:13],
                    bitmap_sample565[10:5],bitmap_sample565[10:9],
                    bitmap_sample565[4:0],bitmap_sample565[4:2]};
            end
            if (read_pixel32(32'h0000_e700+x*4) !==
                bitmap_expected_argb)
                $fatal(1,"flipped source boundary mismatch x=%0d",x);
        end

        // Explicitly disjoint COPY uses independent source/target strides.
        wait(start_ready);
        @(negedge clk);
        command[0] = 512'd0;
        command[0][31:0] = 32'h0000_0207;
        command[0][63:32] = 32'h0000_e000;
        command[0][95:64] = 32'd32;
        command[0][127:96] = {16'd8,16'd0};
        command[0][159:128] = 32'h0000_e800;
        command[0][191:160] = 32'd64;
        command[0][223:192] = {16'd2,16'd3};
        u_mem.store[LIST_BASE >> 5] = command[0][255:0];
        u_mem.store[(LIST_BASE >> 5)+1] = command[0][511:256];
        for (y=0; y<2; y=y+1)
            for (x=0; x<2; x=x+1)
                u_mem.store[((32'h0000_e800+y*64) >> 5)+x] =
                    {16{16'h1234}};
        start = 1'b1;
        @(negedge clk);
        start = 1'b0;
        wait(done);
        if (error || completed_count != 1)
            $fatal(1,"different-stride COPY command failed");
        for (y=0; y<2; y=y+1)
            for (x=0; x<16; x=x+1) begin
                bitmap_sample565 = x>=3 && x<11 ?
                    read_pixel16(32'h0000_e000+y*32+(x-3)*2) :
                    16'h1234;
                if (read_pixel16(32'h0000_e800+y*64+x*2) !==
                    bitmap_sample565)
                    $fatal(1,"different-stride COPY mismatch x=%0d y=%0d",
                           x,y);
            end

        // RGB565 nearest-neighbor upscale: 4x2 source to 8x4 output.
        wait(start_ready);
        @(negedge clk);
        command[0] = 512'd0;
        command[0][31:0] = 32'h00ff_2006;
        command[0][63:32] = 32'h0000_f200;
        command[0][95:64] = 32'd64;
        command[0][127:96] = {16'd8,16'd3};
        command[0][159:128] = {16'd0,16'd4};
        command[0][191:160] = 32'h0000_f000;
        command[0][223:192] = 32'd32;
        command[0][287:256] = 32'h0000_8000;
        command[0][319:288] = 32'h0000_8000;
        u_mem.store[LIST_BASE >> 5] = command[0][255:0];
        u_mem.store[(LIST_BASE >> 5)+1] = command[0][511:256];
        for (y=0; y<2; y=y+1)
            for (x=0; x<4; x=x+1)
                u_mem.store[(32'h0000_f000+y*32) >> 5]
                    [x*16 +: 16] = source565_at(x,y);
        for (y=0; y<4; y=y+1)
            for (x=0; x<2; x=x+1)
                u_mem.store[((32'h0000_f200+y*64) >> 5)+x] =
                    256'd0;
        start = 1'b1;
        @(negedge clk);
        start = 1'b0;
        wait(done);
        if (error || completed_count != 1)
            $fatal(1,"RGB565 nearest upscale failed");
        for (y=0; y<4; y=y+1)
            for (x=0; x<16; x=x+1) begin
                bitmap_expected_argb = 32'd0;
                if (x>=3 && x<11) begin
                    bitmap_sample565 = source565_at((x-3)/2,y/2);
                    bitmap_expected_argb = {8'hff,
                        bitmap_sample565[15:11],bitmap_sample565[15:13],
                        bitmap_sample565[10:5],bitmap_sample565[10:9],
                        bitmap_sample565[4:0],bitmap_sample565[4:2]};
                end
                if (read_pixel32(32'h0000_f200+y*64+x*4) !==
                    bitmap_expected_argb)
                    $fatal(1,"RGB565 upscale mismatch x=%0d y=%0d got=%h want=%h",
                           x,y,read_pixel32(32'h0000_f200+y*64+x*4),
                           bitmap_expected_argb);
            end

        // Flipped upscale starts at the last source pixel and last row.
        wait(start_ready);
        @(negedge clk);
        command[0] = 512'd0;
        command[0][31:0] = 32'h00ff_2c06;
        command[0][63:32] = 32'h0000_f300;
        command[0][95:64] = 32'd64;
        command[0][127:96] = {16'd8,16'd0};
        command[0][159:128] = {16'd3,16'd4};
        command[0][191:160] = 32'h0000_f020;
        command[0][223:192] = 32'd32;
        command[0][287:256] = 32'h0000_8000;
        command[0][319:288] = 32'h0000_8000;
        u_mem.store[LIST_BASE >> 5] = command[0][255:0];
        u_mem.store[(LIST_BASE >> 5)+1] = command[0][511:256];
        for (y=0; y<4; y=y+1)
            for (x=0; x<2; x=x+1)
                u_mem.store[((32'h0000_f300+y*64) >> 5)+x] =
                    256'd0;
        start = 1'b1;
        @(negedge clk);
        start = 1'b0;
        wait(done);
        if (error || completed_count != 1)
            $fatal(1,"flipped nearest upscale failed");
        for (y=0; y<4; y=y+1)
            for (x=0; x<16; x=x+1) begin
                bitmap_expected_argb = 32'd0;
                if (x<8) begin
                    bitmap_sample565 =
                        source565_at(3-(x/2),1-(y/2));
                    bitmap_expected_argb = {8'hff,
                        bitmap_sample565[15:11],bitmap_sample565[15:13],
                        bitmap_sample565[10:5],bitmap_sample565[10:9],
                        bitmap_sample565[4:0],bitmap_sample565[4:2]};
                end
                if (read_pixel32(32'h0000_f300+y*64+x*4) !==
                    bitmap_expected_argb)
                    $fatal(1,"flipped upscale mismatch x=%0d y=%0d",
                           x,y);
            end

        // ARGB nearest-neighbor downscale crosses source beats.
        wait(start_ready);
        @(negedge clk);
        command[0] = 512'd0;
        command[0][31:0] = 32'h00ff_2306;
        command[0][63:32] = 32'h0001_0800;
        command[0][95:64] = 32'd64;
        command[0][127:96] = {16'd4,16'd7};
        command[0][159:128] = {16'd0,16'd2};
        command[0][191:160] = 32'h0001_0000;
        command[0][223:192] = 32'd64;
        command[0][287:256] = 32'h0004_0000;
        command[0][319:288] = 32'h0002_0000;
        u_mem.store[LIST_BASE >> 5] = command[0][255:0];
        u_mem.store[(LIST_BASE >> 5)+1] = command[0][511:256];
        for (y=0; y<4; y=y+1)
            for (x=0; x<16; x=x+1)
                u_mem.store[(32'h0001_0000+y*64+x*4) >> 5]
                    [((x*4)&31)*8 +: 32] =
                    {8'hff,8'(x*10),8'(y*40),8'h55};
        for (y=0; y<2; y=y+1)
            for (x=0; x<2; x=x+1)
                u_mem.store[((32'h0001_0800+y*64) >> 5)+x] =
                    256'd0;
        start = 1'b1;
        @(negedge clk);
        start = 1'b0;
        wait(done);
        if (error || completed_count != 1)
            $fatal(1,"ARGB nearest downscale failed");
        for (y=0; y<2; y=y+1)
            for (x=0; x<16; x=x+1) begin
                bitmap_expected_argb = x>=7 && x<11 ?
                    {8'hff,8'((x-7)*40),8'(y*80),8'h55} :
                    32'd0;
                if (read_pixel32(32'h0001_0800+y*64+x*4) !==
                    bitmap_expected_argb)
                    $fatal(1,"ARGB downscale mismatch x=%0d y=%0d got=%h want=%h",
                           x,y,read_pixel32(32'h0001_0800+y*64+x*4),
                           bitmap_expected_argb);
            end

        // Horizontal RGB565 gradient through the command decoder.
        wait(start_ready);
        @(negedge clk);
        command[0] = 512'd0;
        command[0][31:0] = 32'h0000_0008;
        command[0][63:32] = 32'h0000_fa00;
        command[0][95:64] = 32'd64;
        command[0][127:96] = {16'd19,16'd3};
        command[0][143:128] = 16'd2;
        command[0][191:160] = 32'hff00_0000;
        command[0][255:224] = 32'h0008_0000;
        command[0][287:256] = 32'h0004_0000;
        u_mem.store[LIST_BASE >> 5] = command[0][255:0];
        u_mem.store[(LIST_BASE >> 5)+1] = command[0][511:256];
        for (y=0; y<2; y=y+1)
            for (x=0; x<2; x=x+1)
                u_mem.store[((32'h0000_fa00+y*64) >> 5)+x] =
                    {16{16'h1234}};
        start = 1'b1;
        @(negedge clk);
        start = 1'b0;
        wait(done);
        if (error || completed_count != 1)
            $fatal(1,"horizontal gradient command failed");
        for (y=0; y<2; y=y+1)
            for (x=0; x<32; x=x+1) begin
                bitmap_sample565 = x>=3 && x<22 ?
                    {5'(x-3),6'(x-3),5'd0} : 16'h1234;
                if (read_pixel16(32'h0000_fa00+y*64+x*2) !==
                    bitmap_sample565)
                    $fatal(1,"gradient command mismatch x=%0d y=%0d",
                           x,y);
            end

        // Vertical premultiplied ARGB gradient in the same fill path.
        wait(start_ready);
        @(negedge clk);
        command[0] = 512'd0;
        command[0][31:0] = 32'h0000_0308;
        command[0][63:32] = 32'h0001_0a00;
        command[0][95:64] = 32'd96;
        command[0][127:96] = {16'd10,16'd5};
        command[0][143:128] = 16'd5;
        command[0][191:160] = 32'h2020_0000;
        command[0][223:192] = 32'h0020_0000;
        command[0][255:224] = 32'h0020_0000;
        command[0][287:256] = 32'h0008_0000;
        u_mem.store[LIST_BASE >> 5] = command[0][255:0];
        u_mem.store[(LIST_BASE >> 5)+1] = command[0][511:256];
        for (y=0; y<5; y=y+1)
            for (x=0; x<3; x=x+1)
                u_mem.store[((32'h0001_0a00+y*96) >> 5)+x] =
                    256'd0;
        start = 1'b1;
        @(negedge clk);
        start = 1'b0;
        wait(done);
        if (error || completed_count != 1)
            $fatal(1,"vertical gradient command failed");
        for (y=0; y<5; y=y+1)
            for (x=0; x<24; x=x+1) begin
                bitmap_expected_argb = x>=5 && x<15 ?
                    {8'(32+y*32),8'(32+y*32),8'(y*8),8'd0} :
                    32'd0;
                if (read_pixel32(32'h0001_0a00+y*96+x*4) !==
                    bitmap_expected_argb)
                    $fatal(1,"vertical gradient mismatch x=%0d y=%0d",
                           x,y);
            end

        // Blur an A8 mask in DDR, then colorize the result into ARGB front.
        wait(start_ready);
        @(negedge clk);
        list_count = 16'd2;
        command[0] = 512'd0;
        command[1] = 512'd0;
        command[0][7:0] = 8'h09;
        command[0][63:32] = 32'h0001_2000;
        command[0][95:64] = 32'd32;
        command[0][127:96] = 32'h0001_3000;
        command[0][159:128] = 32'd32;
        command[0][191:160] = 32'h0001_4000;
        command[0][223:192] = 32'd32;
        command[0][255:224] = {16'd8,16'd32};
        command[0][260:256] = 5'd2;
        command[1][7:0] = 8'h05;
        command[1][63:32] = 32'h0001_5000;
        command[1][95:64] = 32'd128;
        command[1][127:96] = {16'd32,16'd0};
        command[1][143:128] = 16'd8;
        command[1][191:160] = 32'h0001_4000;
        command[1][223:192] = 32'd32;
        command[1][255:224] = 32'hff40_60c0;
        for (y=0; y<8; y=y+1) begin
            u_mem.store[(32'h0001_2000+y*32) >> 5] =
                {32{8'hff}};
            u_mem.store[(32'h0001_3000+y*32) >> 5] =
                256'd0;
            u_mem.store[(32'h0001_4000+y*32) >> 5] =
                256'd0;
            for (x=0; x<4; x=x+1)
                u_mem.store[((32'h0001_5000+y*128) >> 5)+x] =
                    256'd0;
        end
        u_mem.store[LIST_BASE >> 5] = command[0][255:0];
        u_mem.store[(LIST_BASE >> 5)+1] = command[0][511:256];
        u_mem.store[(LIST_BASE >> 5)+2] = command[1][255:0];
        u_mem.store[(LIST_BASE >> 5)+3] = command[1][511:256];
        start = 1'b1;
        @(negedge clk);
        start = 1'b0;
        wait(done);
        if (error || completed_count != 2 ||
            read_byte(32'h0001_4000) != 8'd92 ||
            read_byte(32'h0001_4000+4*32+4) != 8'hff ||
            (read_pixel32(32'h0001_5000) >> 24) != 8'd92 ||
            read_pixel32(32'h0001_5000+4*128+4*4) !==
                32'hff40_60c0)
            $fatal(1,"A8 blur and colorization command failed");

        // One BOX_SHADOW command generates, blurs and colorizes a 61x45 mask.
        wait(start_ready);
        @(negedge clk);
        list_count = 16'd1;
        command[0] = 512'd0;
        command[0][7:0] = 8'h0a;
        command[0][63:32] = 32'h0001_6000;
        command[0][95:64] = 32'd288;
        command[0][127:96] = {16'd61,16'd5};
        command[0][159:128] = {16'd12,16'd45};
        command[0][191:160] = 32'h0001_a000;
        command[0][223:192] = 32'h0001_b000;
        command[0][255:224] = 32'h0001_c000;
        command[0][287:256] = 32'd64;
        command[0][319:288] = 32'ha000_0000;
        command[0][324:320] = 5'd4;
        u_mem.store[LIST_BASE >> 5] = command[0][255:0];
        u_mem.store[(LIST_BASE >> 5)+1] = command[0][511:256];
        for (y=0; y<45; y=y+1)
            for (x=0; x<9; x=x+1)
                u_mem.store[((32'h0001_6000+y*288) >> 5)+x] =
                    256'd0;
        start = 1'b1;
        @(negedge clk);
        start = 1'b0;
        wait(done);
        if (error || completed_count != 1 ||
            read_byte(32'h0001_a000+22*64+30) != 8'hff ||
            read_byte(32'h0001_c000+22*64+30) != 8'hff ||
            read_byte(32'h0001_c000+22*64+2) == 8'd0)
            $fatal(1,"BOX_SHADOW command failed");
        for (y=0; y<45; y=y+1)
            for (x=0; x<72; x=x+1) begin
                bitmap_expected_argb = 32'd0;
                if (x>=5 && x<66) begin
                    bitmap_expected_argb = {
                        mul_ref(8'ha0,
                            read_byte(32'h0001_c000+y*64+x-5)),
                        24'd0};
                end
                if (read_pixel32(32'h0001_6000+y*288+x*4) !==
                    bitmap_expected_argb)
                    $fatal(1,"BOX_SHADOW chunk mismatch x=%0d y=%0d got=%h want=%h",
                           x,y,
                           read_pixel32(32'h0001_6000+y*288+x*4),
                           bitmap_expected_argb);
            end

        wait(start_ready);
        @(negedge clk);
        list_count = 16'd0;
        start = 1'b1;
        @(posedge clk);
        #1;
        if (!done || error || completed_count != 0)
            $fatal(1, "empty batch did not recover after error");
        $display("RENDER_ENGINE_PASS commands=8 pixels=%0d round_beats=%0d a8_target_beats=%0d a8_bursts=%0d bitmap_write_beats=%0d bitmap_bursts=%0d errors=2 boundary=3 copy=1 max_tile=2 cycles=%0d",
                 WIDTH*HEIGHT,round_reads,a8_target_read_beats,
                 a8_target_read_bursts,bitmap_write_beats,
                 bitmap_write_bursts,cycles);
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
            if (u_dut.state_r == 3'd5) begin
                if (arvalid && model_arready && ar_gate &&
                    u_dut.u_a8.state_r == 4'd3) begin
                    if (arlen > 8'd15 ||
                        araddr[11:0] + (arlen+1)*32 > 4096)
                        $fatal(1,"A8 target read burst length mismatch");
                    a8_target_read_bursts =
                        a8_target_read_bursts + 1;
                end
                if (awvalid && model_awready && aw_gate) begin
                    if (awlen > 8'd15 ||
                        awaddr[11:0] + (awlen+1)*32 > 4096)
                        $fatal(1,"A8 target write burst length mismatch");
                    a8_write_bursts = a8_write_bursts + 1;
                end
                if (rready && model_rvalid && r_gate &&
                    u_dut.u_a8.state_r == 4'd4)
                    a8_target_read_beats = a8_target_read_beats + 1;
                if (wvalid && model_wready && w_gate)
                    a8_write_beats = a8_write_beats + 1;
            end
            if (u_dut.state_r == 3'd6) begin
                if (awvalid && model_awready && aw_gate) begin
                    if (awlen > 8'd7 ||
                        awaddr[11:0] + (awlen+1)*32 > 4096)
                        $fatal(1,"bitmap write burst invalid");
                    bitmap_write_bursts = bitmap_write_bursts + 1;
                    if (awaddr == 32'h0000_c000 && awlen == 8'd7)
                        bitmap_eight_beat_witness = 1'b1;
                end
                if (wvalid && model_wready && w_gate)
                    bitmap_write_beats = bitmap_write_beats + 1;
            end
            if (u_dut.state_r == 3'd7) begin
                if (awvalid && model_awready && aw_gate) begin
                    if (awlen > 8'd7 ||
                        awaddr[11:0] + (awlen+1)*32 > 4096)
                        $fatal(1,"COPY write burst invalid");
                    copy_write_bursts = copy_write_bursts + 1;
                end
                if (wvalid && model_wready && w_gate)
                    copy_write_beats = copy_write_beats + 1;
            end
            if (cycles > 100000)
                $fatal(1, "render engine timeout state=%0d fetch_busy=%b round_state=%0d done=%b error=%b",
                       u_dut.state_r,u_dut.u_fetch.busy_o,u_dut.u_round.state_r,done,error);
        end
    end
endmodule
