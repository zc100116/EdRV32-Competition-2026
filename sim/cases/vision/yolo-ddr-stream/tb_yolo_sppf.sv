`timescale 1ns/1ps

module tb_yolo_sppf;
    reg clk_i = 1'b0;
    always #5 clk_i = !clk_i;
    reg rst_n_i = 1'b0;
    reg start_i = 1'b0;
    wire start_ready_w, busy_w, done_w, error_w, mac_beat_w;
    wire cfg_op_w;
    wire [4:0] cfg_block_w, cfg_channel_w;
    wire cfg_ready_w;
    integer cfg_count_r = 0;
    integer mac_count_r = 0;
    integer read_count_r = 0;
    integer write_count_r = 0;
    integer g0 [0:31];
    integer g1 [0:31];
    integer g2 [0:31];
    integer g3 [0:31];
    integer plane, row, pair, pix, ch, idx, y, x, dy, dx;
    integer max_val, candidate, expected, expect_op, expect_block;
    reg [255:0] actual_beat;
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

    edrv32_yolo_sppf dut (
        .clk_i(clk_i), .rst_n_i(rst_n_i),
        .start_i(start_i), .start_ready_o(start_ready_w),
        .input_base_i(32'h40000),
        .workspace_base_i(32'h50000),
        .output_base_i(32'h60000),
        .plane_stride_i(32'd512),
        .weight_cv1_i(32'h00000),
        .weight_cv2_i(32'h10000),
        .width_i(11'd8), .height_i(16'd4),
        .tile_pairs_i(10'd2),
        .busy_o(busy_w), .done_o(done_w),
        .error_o(error_w), .mac_beat_o(mac_beat_w),
        .cfg_op_o(cfg_op_w), .cfg_block_o(cfg_block_w),
        .cfg_channel_o(cfg_channel_w),
        .cfg_valid_i(1'b1), .cfg_ready_o(cfg_ready_w),
        .cfg_bias_i(32'd0), .cfg_multiplier_i(16'd1),
        .cfg_shift_i(cfg_op_w ? 6'd7 : 6'd8),
        .cfg_zero_point_i(8'd0),
        .cfg_lut_enable_i(1'b0), .cfg_lut_valid_i(1'b0),
        .cfg_lut_ready_o(), .cfg_lut_addr_o(),
        .cfg_lut_data_i(8'd0),
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

    axi256_mem_model #(.WORDS(32768)) u_memory (
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
            if (cfg_ready_w) begin
                expect_op = cfg_count_r >= 128;
                expect_block = cfg_count_r < 128 ?
                               cfg_count_r / 32 :
                               (cfg_count_r - 128) / 32;
                if (cfg_op_w !== expect_op ||
                    cfg_block_w !== expect_block ||
                    cfg_channel_w !== cfg_count_r % 32)
                    $fatal(1, "SPPF config mismatch count=%0d op=%0d block=%0d channel=%0d",
                           cfg_count_r, cfg_op_w, cfg_block_w,
                           cfg_channel_w);
                cfg_count_r <= cfg_count_r + 1;
            end
            if (mac_beat_w) mac_count_r <= mac_count_r + 1;
            if (rvalid_w && rready_w)
                read_count_r <= read_count_r + 1;
            if (wvalid_w && wready_w)
                write_count_r <= write_count_r + 1;
        end
    end

    initial begin
        for (idx = 0; idx < 1024; idx = idx + 1)
            u_memory.store[(32'h00000 >> 5) + idx] = {32{8'd1}};
        for (idx = 0; idx < 4096; idx = idx + 1)
            u_memory.store[(32'h10000 >> 5) + idx] = {32{8'd1}};
        for (plane = 0; plane < 16; plane = plane + 1)
            for (row = 0; row < 4; row = row + 1)
                for (pair = 0; pair < 4; pair = pair + 1)
                    for (pix = 0; pix < 2; pix = pix + 1)
                        for (ch = 0; ch < 16; ch = ch + 1) begin
                            x = pair*2+pix;
                            expected = row*3 + x*2 - 8;
                            u_memory.store[(32'h40000 >> 5) +
                                           plane*16+row*4+pair]
                                [(pix*16+ch)*8 +: 8] = expected[7:0];
                        end
        for (y = 0; y < 4; y = y + 1)
            for (x = 0; x < 8; x = x + 1)
                g0[y*8+x] = y*3+x*2-8;
        for (y = 0; y < 4; y = y + 1)
            for (x = 0; x < 8; x = x + 1) begin
                max_val = -128;
                for (dy = -2; dy <= 2; dy = dy + 1)
                    for (dx = -2; dx <= 2; dx = dx + 1)
                        if (y+dy >= 0 && y+dy < 4 &&
                            x+dx >= 0 && x+dx < 8) begin
                            candidate = g0[(y+dy)*8+x+dx];
                            if (candidate > max_val) max_val = candidate;
                        end
                g1[y*8+x] = max_val;
            end
        for (y = 0; y < 4; y = y + 1)
            for (x = 0; x < 8; x = x + 1) begin
                max_val = -128;
                for (dy = -2; dy <= 2; dy = dy + 1)
                    for (dx = -2; dx <= 2; dx = dx + 1)
                        if (y+dy >= 0 && y+dy < 4 &&
                            x+dx >= 0 && x+dx < 8) begin
                            candidate = g1[(y+dy)*8+x+dx];
                            if (candidate > max_val) max_val = candidate;
                        end
                g2[y*8+x] = max_val;
            end
        for (y = 0; y < 4; y = y + 1)
            for (x = 0; x < 8; x = x + 1) begin
                max_val = -128;
                for (dy = -2; dy <= 2; dy = dy + 1)
                    for (dx = -2; dx <= 2; dx = dx + 1)
                        if (y+dy >= 0 && y+dy < 4 &&
                            x+dx >= 0 && x+dx < 8) begin
                            candidate = g2[(y+dy)*8+x+dx];
                            if (candidate > max_val) max_val = candidate;
                        end
                g3[y*8+x] = max_val;
            end

        repeat (5) @(negedge clk_i);
        rst_n_i = 1'b1;
        @(negedge clk_i);
        if (!start_ready_w) $fatal(1, "SPPF start not ready");
        start_i = 1'b1;
        @(negedge clk_i);
        start_i = 1'b0;
        wait (done_w);
        #1;
        if (error_w || busy_w || cfg_count_r != 384 ||
            mac_count_r != 10240 || read_count_r != 10624 ||
            write_count_r != 768)
            $fatal(1, "SPPF status err=%0d cfg=%0d mac=%0d read=%0d write=%0d",
                   error_w, cfg_count_r, mac_count_r,
                   read_count_r, write_count_r);
        for (plane = 0; plane < 32; plane = plane + 1)
            for (row = 0; row < 4; row = row + 1)
                for (pair = 0; pair < 4; pair = pair + 1) begin
                    actual_beat = u_memory.store[(32'h50000 >> 5) +
                                                 plane*16+row*4+pair];
                    for (pix = 0; pix < 2; pix = pix + 1) begin
                        idx = row*8+pair*2+pix;
                        expected = plane < 8 ? g0[idx] :
                                   plane < 16 ? g1[idx] :
                                   plane < 24 ? g2[idx] : g3[idx];
                        for (ch = 0; ch < 16; ch = ch + 1)
                            if (actual_beat[(pix*16+ch)*8 +: 8] !==
                                expected[7:0])
                                $fatal(1, "SPPF workspace mismatch plane=%0d pos=%0d got=%0d exp=%0d",
                                       plane, idx,
                                       actual_beat[(pix*16+ch)*8 +: 8],
                                       expected);
                    end
                end
        for (plane = 0; plane < 16; plane = plane + 1)
            for (row = 0; row < 4; row = row + 1)
                for (pair = 0; pair < 4; pair = pair + 1) begin
                    actual_beat = u_memory.store[(32'h60000 >> 5) +
                                                 plane*16+row*4+pair];
                    for (pix = 0; pix < 2; pix = pix + 1) begin
                        idx = row*8+pair*2+pix;
                        expected = g0[idx]+g1[idx]+g2[idx]+g3[idx];
                        for (ch = 0; ch < 16; ch = ch + 1)
                            if (actual_beat[(pix*16+ch)*8 +: 8] !==
                                expected[7:0])
                                $fatal(1, "SPPF output mismatch plane=%0d pos=%0d got=%0d exp=%0d",
                                       plane, idx,
                                       actual_beat[(pix*16+ch)*8 +: 8],
                                       expected);
                    end
                end
        $display("PASS YOLO SPPF DDR chain cfg=%0d mac=%0d read=%0d write=%0d",
                 cfg_count_r, mac_count_r, read_count_r, write_count_r);
        $finish;
    end

    initial begin
        #5000000;
        $fatal(1, "SPPF timeout state=%0d cfg=%0d",
               dut.state_r, cfg_count_r);
    end
endmodule
