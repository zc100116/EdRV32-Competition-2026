`timescale 1ns/1ps

module tb_yolo_maxpool5_dma #(
    parameter integer PAIRS = 4,
    parameter integer HEIGHT = 4,
    parameter integer PLANES = 2
);
    localparam integer PLANE_STRIDE = PAIRS*HEIGHT*32 + 256;
    localparam [3:0] PAIRS_W = PAIRS;
    localparam [3:0] HEIGHT_W = HEIGHT;
    localparam [3:0] PLANES_W = PLANES;
    reg clk_i = 1'b0;
    always #5 clk_i = !clk_i;
    reg rst_n_i = 1'b0;
    reg start_i = 1'b0;
    wire start_ready_w, busy_w, done_w, error_w;
    wire [3:0] arid_w, rid_w, awid_w, bid_w;
    wire [31:0] araddr_w, awaddr_w;
    wire [7:0] arlen_w, awlen_w;
    wire [2:0] arsize_w, awsize_w;
    wire [1:0] arburst_w, awburst_w, rresp_w, bresp_w;
    wire arvalid_w, arready_w, rlast_w, rvalid_w, rready_w;
    wire awvalid_w, awready_w, wlast_w, wvalid_w, wready_w;
    wire bvalid_w, bready_w;
    wire [255:0] rdata_w, wdata_w;
    wire [31:0] wstrb_w;
    integer plane, row, pair, pix, ch, ky, kx;
    integer x, value, candidate, expected;
    integer read_count_r = 0;
    integer write_count_r = 0;
    reg [255:0] actual_beat;

    function integer source_value;
        input integer p, yy, xx, cc;
        begin
            source_value = ((p*43 + yy*19 + xx*7 + cc*3) % 256) - 128;
        end
    endfunction

    edrv32_yolo_maxpool5_dma dut (
        .clk_i(clk_i), .rst_n_i(rst_n_i),
        .start_i(start_i), .start_ready_o(start_ready_w),
        .input_base_i(32'h1FE0),
        .input_plane_stride_i(PLANE_STRIDE),
        .output_base_i(32'h4FE0),
        .output_plane_stride_i(PLANE_STRIDE),
        .plane_count_i(PLANES_W),
        .width_pairs_i(PAIRS_W), .height_i(HEIGHT_W),
        .busy_o(busy_w), .done_o(done_w), .error_o(error_w),
        .m_arid_o(arid_w), .m_araddr_o(araddr_w),
        .m_arlen_o(arlen_w), .m_arsize_o(arsize_w),
        .m_arburst_o(arburst_w), .m_arvalid_o(arvalid_w),
        .m_arready_i(arready_w), .m_rid_i(rid_w),
        .m_rdata_i(rdata_w), .m_rresp_i(rresp_w),
        .m_rlast_i(rlast_w), .m_rvalid_i(rvalid_w),
        .m_rready_o(rready_w),
        .m_awid_o(awid_w), .m_awaddr_o(awaddr_w),
        .m_awlen_o(awlen_w), .m_awsize_o(awsize_w),
        .m_awburst_o(awburst_w), .m_awvalid_o(awvalid_w),
        .m_awready_i(awready_w), .m_wdata_o(wdata_w),
        .m_wstrb_o(wstrb_w), .m_wlast_o(wlast_w),
        .m_wvalid_o(wvalid_w), .m_wready_i(wready_w),
        .m_bid_i(bid_w), .m_bresp_i(bresp_w),
        .m_bvalid_i(bvalid_w), .m_bready_o(bready_w)
    );

    axi256_mem_model #(.WORDS(4096)) u_memory (
        .clk_i(clk_i), .rst_n_i(rst_n_i),
        .awid_i(awid_w), .awaddr_i(awaddr_w),
        .awlen_i(awlen_w), .awsize_i(awsize_w),
        .awburst_i(awburst_w), .awvalid_i(awvalid_w),
        .awready_o(awready_w),
        .wdata_i(wdata_w), .wstrb_i(wstrb_w),
        .wlast_i(wlast_w), .wvalid_i(wvalid_w),
        .wready_o(wready_w),
        .bid_o(bid_w), .bresp_o(bresp_w),
        .bvalid_o(bvalid_w), .bready_i(bready_w),
        .arid_i(arid_w), .araddr_i(araddr_w),
        .arlen_i(arlen_w), .arsize_i(arsize_w),
        .arburst_i(arburst_w), .arvalid_i(arvalid_w),
        .arready_o(arready_w),
        .rid_o(rid_w), .rdata_o(rdata_w),
        .rresp_o(rresp_w), .rlast_o(rlast_w),
        .rvalid_o(rvalid_w), .rready_i(rready_w)
    );

    always @(posedge clk_i) begin
        if (rst_n_i) begin
            if (arvalid_w && arready_w &&
                ({1'b0, araddr_w[11:0]} +
                 ({5'd0, arlen_w}+13'd1)*13'd32 > 13'd4096 ||
                 arlen_w >= 8'd16))
                $fatal(1, "Maxpool invalid read burst");
            if (awvalid_w && awready_w &&
                ({1'b0, awaddr_w[11:0]} +
                 ({5'd0, awlen_w}+13'd1)*13'd32 > 13'd4096 ||
                 awlen_w >= 8'd16))
                $fatal(1, "Maxpool invalid write burst");
            if (rvalid_w && rready_w)
                read_count_r <= read_count_r + 1;
            if (wvalid_w && wready_w)
                write_count_r <= write_count_r + 1;
        end
    end

    initial begin
        for (plane = 0; plane < PLANES; plane = plane + 1)
            for (row = 0; row < HEIGHT; row = row + 1)
                for (pair = 0; pair < PAIRS; pair = pair + 1)
                    for (pix = 0; pix < 2; pix = pix + 1)
                        for (ch = 0; ch < 16; ch = ch + 1) begin
                            value = source_value(plane, row,
                                                 pair*2+pix, ch);
                            u_memory.store[((32'h1FE0 +
                                             plane*PLANE_STRIDE) >> 5) +
                                            row*PAIRS+pair]
                                [(pix*16+ch)*8 +: 8] = value[7:0];
                        end
        repeat (5) @(negedge clk_i);
        rst_n_i = 1'b1;
        @(negedge clk_i);
        if (!start_ready_w)
            $fatal(1, "Maxpool start not ready");
        start_i = 1'b1;
        @(negedge clk_i);
        start_i = 1'b0;
        wait (done_w);
        #1;
        if (error_w || busy_w || read_count_r != PLANES*PAIRS*HEIGHT ||
            write_count_r != PLANES*PAIRS*HEIGHT)
            $fatal(1, "Maxpool status err=%0d read=%0d write=%0d",
                   error_w, read_count_r, write_count_r);
        for (plane = 0; plane < PLANES; plane = plane + 1)
            for (row = 0; row < HEIGHT; row = row + 1)
                for (pair = 0; pair < PAIRS; pair = pair + 1) begin
                    actual_beat = u_memory.store[((32'h4FE0 +
                                                   plane*PLANE_STRIDE) >> 5)
                                                 + row*PAIRS+pair];
                    for (pix = 0; pix < 2; pix = pix + 1)
                        for (ch = 0; ch < 16; ch = ch + 1) begin
                            x = pair*2+pix;
                            expected = -128;
                            for (ky = -2; ky <= 2; ky = ky + 1)
                                for (kx = -2; kx <= 2; kx = kx + 1)
                                    if (row+ky >= 0 && row+ky < HEIGHT &&
                                        x+kx >= 0 && x+kx < PAIRS*2) begin
                                        candidate = source_value(
                                            plane, row+ky, x+kx, ch);
                                        if (candidate > expected)
                                            expected = candidate;
                                    end
                            if (actual_beat[(pix*16+ch)*8 +: 8] !==
                                expected[7:0])
                                $fatal(1, "Maxpool mismatch plane=%0d row=%0d x=%0d ch=%0d got=%0d expected=%0d",
                                       plane, row, x, ch,
                                       actual_beat[(pix*16+ch)*8 +: 8],
                                       expected);
                        end
                end
        $display("PASS YOLO maxpool5 pairs=%0d height=%0d planes=%0d read=%0d write=%0d",
                 PAIRS, HEIGHT, PLANES, read_count_r, write_count_r);
        $finish;
    end

    initial begin
        #10000000;
        $fatal(1, "Maxpool timeout state=%0d", dut.state_r);
    end
endmodule
