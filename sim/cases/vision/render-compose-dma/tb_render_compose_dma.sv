`timescale 1ns/1ps

module tb_render_compose_dma;
    localparam integer WIDTH = 64;
    localparam integer HEIGHT = 48;
    localparam [31:0] BASE0 = 32'h0000_1000;
    localparam [31:0] FRONT0 = 32'h0000_4000;
    localparam [31:0] BASE1 = 32'h0000_7000;
    localparam [31:0] FRONT1 = 32'h0000_8000;
    localparam [31:0] TARGET1 = 32'h0000_9000;

    reg clk, rst_n;
    reg start;
    wire start_ready;
    reg [31:0] base_addr, base_stride;
    reg [31:0] front_addr, front_stride;
    reg [31:0] target_addr, target_stride;
    reg [15:0] width, height;
    wire busy, done, error;
    wire [31:0] read_beats, write_beats;
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
    integer i, x, y, addr, file_id, cycles;
    integer ar_count, aw_count;
    reg [15:0] actual565, wanted565;
    reg [31:0] rgb;

    always #5 clk = ~clk;

    edrv32_render_compose_dma u_dut (
        .clk_i(clk), .rst_n_i(rst_n),
        .start_i(start), .start_ready_o(start_ready),
        .base_addr_i(base_addr), .base_stride_i(base_stride),
        .front_addr_i(front_addr), .front_stride_i(front_stride),
        .target_addr_i(target_addr), .target_stride_i(target_stride),
        .width_i(width), .height_i(height),
        .busy_o(busy), .done_o(done), .error_o(error),
        .read_beat_count_o(read_beats),
        .write_beat_count_o(write_beats),
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
        .m_bvalid_i(model_bvalid && b_gate), .m_bready_o(bready)
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

    function automatic [15:0] base_at;
        input integer xpos;
        input integer ypos;
        reg [7:0] r, g, b;
        begin
            r = 8'd25 + xpos*3;
            g = 8'd45 + ypos*3;
            b = 8'd80 + xpos;
            base_at = {r[7:3], g[7:2], b[7:3]};
        end
    endfunction

    function automatic [31:0] front_at;
        input integer xpos;
        input integer ypos;
        reg [7:0] a, r, g, b;
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
            front_at = {a, mul_ref(r,a), mul_ref(g,a), mul_ref(b,a)};
        end
    endfunction

    function automatic [15:0] expected_at;
        input integer xpos;
        input integer ypos;
        reg [15:0] bg;
        reg [31:0] fg;
        reg [7:0] br, bgc, bb;
        reg [7:0] rr, gg, bb_out;
        begin
            bg = base_at(xpos, ypos);
            fg = front_at(xpos, ypos);
            br = {bg[15:11], bg[15:13]};
            bgc = {bg[10:5], bg[10:9]};
            bb = {bg[4:0], bg[4:2]};
            rr = fg[23:16] + mul_ref(br, 8'hff - fg[31:24]);
            gg = fg[15:8] + mul_ref(bgc, 8'hff - fg[31:24]);
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

    task automatic write_pixel16;
        input integer byte_address;
        input [15:0] pixel;
        begin
            u_mem.store[byte_address >> 5]
                       [(byte_address & 31)*8 +: 16] = pixel;
        end
    endtask

    task automatic write_pixel32;
        input integer byte_address;
        input [31:0] pixel;
        begin
            u_mem.store[byte_address >> 5]
                       [(byte_address & 31)*8 +: 32] = pixel;
        end
    endtask

    task automatic launch;
        begin
            @(negedge clk);
            if (!start_ready) $fatal(1, "composer not ready");
            start = 1'b1;
            @(negedge clk);
            start = 1'b0;
            wait(done);
            if (error) $fatal(1, "compose AXI error");
        end
    endtask

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        start = 1'b0;
        base_addr = 32'b0;
        base_stride = 32'b0;
        front_addr = 32'b0;
        front_stride = 32'b0;
        target_addr = 32'b0;
        target_stride = 32'b0;
        width = 16'b0;
        height = 16'b0;
        ar_gate = 1'b1;
        r_gate = 1'b1;
        aw_gate = 1'b1;
        w_gate = 1'b1;
        b_gate = 1'b1;
        cycles = 0;
        ar_count = 0;
        aw_count = 0;
        for (i = 0; i < 8192; i = i + 1)
            u_mem.store[i] = {32{8'ha5}};
        for (y = 0; y < HEIGHT; y = y + 1)
            for (x = 0; x < WIDTH; x = x + 1) begin
                write_pixel16(BASE0 + y*128 + x*2, base_at(x,y));
                write_pixel32(FRONT0 + y*256 + x*4, front_at(x,y));
            end

        repeat (5) @(posedge clk);
        @(negedge clk);
        rst_n = 1'b1;
        base_addr = BASE0;
        base_stride = 32'd128;
        front_addr = FRONT0;
        front_stride = 32'd256;
        target_addr = BASE0;
        target_stride = 32'd128;
        width = WIDTH;
        height = HEIGHT;
        launch();
        if (read_beats != 576 || write_beats != 192)
            $fatal(1, "unexpected full-frame beats read=%0d write=%0d",
                   read_beats, write_beats);
        file_id = $fopen("sim/build/cases/vision/render-compose-dma/render.ppm", "wb");
        if (file_id == 0) $fatal(1, "cannot open render.ppm");
        $fwrite(file_id, "P6\n%0d %0d\n255\n", WIDTH, HEIGHT);
        for (y = 0; y < HEIGHT; y = y + 1)
            for (x = 0; x < WIDTH; x = x + 1) begin
                actual565 = read_pixel16(BASE0 + y*128 + x*2);
                wanted565 = expected_at(x,y);
                if (actual565 !== wanted565)
                    $fatal(1, "compose pixel x=%0d y=%0d got=%h want=%h",
                           x, y, actual565, wanted565);
                rgb = {8'hff,
                       actual565[15:11], actual565[15:13],
                       actual565[10:5], actual565[10:9],
                       actual565[4:0], actual565[4:2]};
                $fwrite(file_id, "%c%c%c", rgb[23:16], rgb[15:8], rgb[7:0]);
            end
        $fclose(file_id);

        for (y = 0; y < 8; y = y + 1)
            for (x = 0; x < 32; x = x + 1) begin
                write_pixel16(BASE1 + y*64 + x*2, base_at(x,y));
                write_pixel32(FRONT1 + y*128 + x*4, front_at(x,y));
            end
        base_addr = BASE1;
        base_stride = 32'd64;
        front_addr = FRONT1;
        front_stride = 32'd128;
        target_addr = TARGET1;
        target_stride = 32'd64;
        width = 16'd32;
        height = 16'd8;
        launch();
        if (read_beats != 48 || write_beats != 16)
            $fatal(1, "unexpected separate-target beats");
        for (y = 0; y < 8; y = y + 1)
            for (x = 0; x < 32; x = x + 1) begin
                actual565 = read_pixel16(TARGET1 + y*64 + x*2);
                wanted565 = expected_at(x,y);
                if (actual565 !== wanted565)
                    $fatal(1, "separate target x=%0d y=%0d got=%h want=%h",
                           x, y, actual565, wanted565);
            end
        $display("RENDER_COMPOSE_DMA_PASS pixels=%0d in_place=1 separate=1",
                 WIDTH*HEIGHT+32*8);
        $finish;
    end

    always @(negedge clk) begin
        if (rst_n) begin
            ar_gate = $urandom_range(0, 7) != 0;
            r_gate = $urandom_range(0, 7) != 0;
            aw_gate = $urandom_range(0, 7) != 0;
            w_gate = $urandom_range(0, 7) != 0;
            b_gate = $urandom_range(0, 7) != 0;
        end
    end

    always @(posedge clk) begin
        if (rst_n) begin
            cycles = cycles + 1;
            if (arvalid && model_arready && ar_gate) begin
                ar_count = ar_count + 1;
                if (araddr[4:0] != 5'd0 || arlen > 8'd15 ||
                    arsize != 3'd5 || arburst != 2'b01 ||
                    araddr[11:0] + (arlen+1)*32 > 4096)
                    $fatal(1, "invalid compose read burst");
            end
            if (awvalid && model_awready && aw_gate) begin
                aw_count = aw_count + 1;
                if (awaddr[4:0] != 5'd0 || awlen > 8'd15 ||
                    awsize != 3'd5 || awburst != 2'b01 ||
                    awaddr[11:0] + (awlen+1)*32 > 4096)
                    $fatal(1, "invalid compose write burst");
            end
            if (cycles > 100000)
                $fatal(1, "compose timeout read=%0d write=%0d", read_beats,
                       write_beats);
        end
    end
endmodule
