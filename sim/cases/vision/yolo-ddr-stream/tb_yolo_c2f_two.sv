`timescale 1ns/1ps

module tb_yolo_c2f_two #(
    parameter integer SHORTCUT = 1
);
    reg clk_i = 1'b0;
    always #5 clk_i = !clk_i;
    reg rst_n_i = 1'b0;
    reg start_i = 1'b0;
    wire start_ready_w, busy_w, done_w, error_w, mac_beat_w;
    wire [2:0] cfg_op_w;
    wire [4:0] cfg_block_w, cfg_channel_w;
    wire cfg_ready_w;
    integer cfg_count_r = 0;
    integer mac_count_r = 0;
    integer read_count_r = 0;
    integer write_count_r = 0;
    integer b0a [0:31];
    integer b0b [0:31];
    integer y0 [0:31];
    integer b1a [0:31];
    integer b1b [0:31];
    integer y1 [0:31];
    integer x, y, ky, kx, idx, plane, pair, pix, ch, sum;
    integer expect_op, expect_block, expect_byte;
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

    function integer tap_count;
        input integer yy;
        input integer xx;
        integer dy, dx;
        begin
            tap_count = 0;
            for (dy = -1; dy <= 1; dy = dy + 1)
                for (dx = -1; dx <= 1; dx = dx + 1)
                    if (yy+dy >= 0 && yy+dy < 4 &&
                        xx+dx >= 0 && xx+dx < 8)
                        tap_count = tap_count + 1;
        end
    endfunction

    edrv32_yolo_c2f dut (
        .clk_i(clk_i), .rst_n_i(rst_n_i),
        .start_i(start_i), .start_ready_o(start_ready_w),
        .input_base_i(32'h10000),
        .workspace_base_i(32'h10800),
        .temp_base_i(32'h12000),
        .output_base_i(32'h12800),
        .plane_stride_i(32'd512), .plane_beats_i(16'd16),
        .weight_split_i(32'h0000),
        .weight_bottleneck0_i(32'h1000),
        .weight_bottleneck1_i(32'h4000),
        .weight_bottleneck2_i(32'h7000),
        .weight_bottleneck3_i(32'hA000),
        .weight_fuse_i(32'hD000),
        .width_i(11'd8), .height_i(16'd4),
        .tile_pairs_i(10'd2),
        .input_blocks_i(6'd2),
        .hidden_blocks_log2_i(2'd1),
        .output_blocks_i(5'd2),
        .input_cache_row_stride_i(10'd4),
        .two_bottlenecks_i(1'b1),
        .shortcut_i(SHORTCUT != 0),
        .residual_zero_point_i(8'd0),
        .busy_o(busy_w), .done_o(done_w),
        .error_o(error_w), .mac_beat_o(mac_beat_w),
        .cfg_op_o(cfg_op_w), .cfg_block_o(cfg_block_w),
        .cfg_channel_o(cfg_channel_w),
        .cfg_valid_i(1'b1), .cfg_ready_o(cfg_ready_w),
        .cfg_bias_i(32'd0), .cfg_multiplier_i(16'd1),
        .cfg_shift_i(cfg_op_w == 3'd0 || cfg_op_w == 3'd5 ?
                     6'd5 : cfg_op_w == 3'd1 ? 6'd7 : 6'd8),
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
            if (cfg_ready_w) begin
                expect_op = cfg_count_r < 64 ? 0 :
                            cfg_count_r < 96 ? 1 :
                            cfg_count_r < 128 ? 2 :
                            cfg_count_r < 160 ? 3 :
                            cfg_count_r < 192 ? 4 : 5;
                expect_block = cfg_count_r < 64 ? cfg_count_r / 32 :
                               cfg_count_r >= 192 ?
                               (cfg_count_r - 192) / 32 : 0;
                if (cfg_op_w !== expect_op ||
                    cfg_block_w !== expect_block ||
                    cfg_channel_w !== cfg_count_r % 32)
                    $fatal(1, "C2f two config order count=%0d op=%0d block=%0d ch=%0d",
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
        for (idx = 0; idx < 64; idx = idx + 1)
            u_memory.store[(32'h0000 >> 5) + idx] = {32{8'd1}};
        for (idx = 0; idx < 288; idx = idx + 1) begin
            u_memory.store[(32'h1000 >> 5) + idx] = {32{8'd1}};
            u_memory.store[(32'h4000 >> 5) + idx] = {32{8'd1}};
            u_memory.store[(32'h7000 >> 5) + idx] = {32{8'd1}};
            u_memory.store[(32'hA000 >> 5) + idx] = {32{8'd1}};
        end
        for (idx = 0; idx < 256; idx = idx + 1)
            u_memory.store[(32'hD000 >> 5) + idx] = {32{8'd1}};
        for (idx = 0; idx < 32; idx = idx + 1)
            u_memory.store[(32'h10000 >> 5) + idx] = {32{8'd1}};

        for (y = 0; y < 4; y = y + 1)
            for (x = 0; x < 8; x = x + 1)
                b0a[y*8+x] = (32*tap_count(y, x) + 64) >> 7;
        for (y = 0; y < 4; y = y + 1)
            for (x = 0; x < 8; x = x + 1) begin
                sum = 0;
                for (ky = -1; ky <= 1; ky = ky + 1)
                    for (kx = -1; kx <= 1; kx = kx + 1)
                        if (y+ky >= 0 && y+ky < 4 &&
                            x+kx >= 0 && x+kx < 8)
                            sum = sum + b0a[(y+ky)*8+x+kx];
                b0b[y*8+x] = (32*sum + 128) >> 8;
                y0[y*8+x] = b0b[y*8+x] + (SHORTCUT != 0);
            end
        for (y = 0; y < 4; y = y + 1)
            for (x = 0; x < 8; x = x + 1) begin
                sum = 0;
                for (ky = -1; ky <= 1; ky = ky + 1)
                    for (kx = -1; kx <= 1; kx = kx + 1)
                        if (y+ky >= 0 && y+ky < 4 &&
                            x+kx >= 0 && x+kx < 8)
                            sum = sum + y0[(y+ky)*8+x+kx];
                b1a[y*8+x] = (32*sum + 128) >> 8;
            end
        for (y = 0; y < 4; y = y + 1)
            for (x = 0; x < 8; x = x + 1) begin
                sum = 0;
                for (ky = -1; ky <= 1; ky = ky + 1)
                    for (kx = -1; kx <= 1; kx = kx + 1)
                        if (y+ky >= 0 && y+ky < 4 &&
                            x+kx >= 0 && x+kx < 8)
                            sum = sum + b1a[(y+ky)*8+x+kx];
                b1b[y*8+x] = (32*sum + 128) >> 8;
                y1[y*8+x] = b1b[y*8+x] +
                            (SHORTCUT != 0 ? y0[y*8+x] : 0);
            end

        repeat (5) @(negedge clk_i);
        rst_n_i = 1'b1;
        @(negedge clk_i);
        if (!start_ready_w) $fatal(1, "C2f two start not ready");
        start_i = 1'b1;
        @(negedge clk_i);
        start_i = 1'b0;
        wait (done_w);
        #1;
        if (error_w || busy_w || cfg_count_r != 256 ||
            mac_count_r != 2944)
            $fatal(1, "C2f two status error=%0d cfg=%0d mac=%0d",
                   error_w, cfg_count_r, mac_count_r);
        for (plane = 0; plane < 8; plane = plane + 1)
            for (y = 0; y < 4; y = y + 1)
                for (pair = 0; pair < 4; pair = pair + 1) begin
                    actual_beat = u_memory.store[(32'h10800 >> 5) +
                                                 plane*16+y*4+pair];
                    for (pix = 0; pix < 2; pix = pix + 1) begin
                        idx = y*8+pair*2+pix;
                        expect_byte = plane < 4 ? 1 :
                                      plane < 6 ? y0[idx] : y1[idx];
                        for (ch = 0; ch < 16; ch = ch + 1)
                            if (actual_beat[(pix*16+ch)*8 +: 8] !==
                                expect_byte[7:0])
                                $fatal(1, "C2f two workspace mismatch plane=%0d pos=%0d got=%0d expected=%0d",
                                       plane, idx,
                                       actual_beat[(pix*16+ch)*8 +: 8],
                                       expect_byte);
                    end
                end
        for (plane = 0; plane < 4; plane = plane + 1)
            for (y = 0; y < 4; y = y + 1)
                for (pair = 0; pair < 4; pair = pair + 1) begin
                    actual_beat = u_memory.store[(32'h12800 >> 5) +
                                                 plane*16+y*4+pair];
                    for (pix = 0; pix < 2; pix = pix + 1) begin
                        idx = y*8+pair*2+pix;
                        expect_byte = 2+y0[idx]+y1[idx];
                        for (ch = 0; ch < 16; ch = ch + 1)
                            if (actual_beat[(pix*16+ch)*8 +: 8] !==
                                expect_byte[7:0])
                                $fatal(1, "C2f two output mismatch plane=%0d pos=%0d got=%0d expected=%0d",
                                       plane, idx,
                                       actual_beat[(pix*16+ch)*8 +: 8],
                                       expect_byte);
                    end
                end
        $display("PASS YOLO C2f two bottlenecks shortcut=%0d cfg=%0d mac=%0d read=%0d write=%0d",
                 SHORTCUT, cfg_count_r, mac_count_r,
                 read_count_r, write_count_r);
        $finish;
    end

    initial begin
        #5000000;
        $fatal(1, "C2f two timeout state=%0d cfg=%0d",
               dut.state_r, cfg_count_r);
    end
endmodule
