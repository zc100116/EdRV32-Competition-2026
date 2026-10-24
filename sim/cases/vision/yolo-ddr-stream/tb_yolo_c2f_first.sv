`timescale 1ns/1ps

module tb_yolo_c2f_first;
    reg clk_i = 1'b0;
    reg rst_n_i = 1'b0;
    reg start_i = 1'b0;
    always #5 clk_i = !clk_i;

    wire start_ready_w, busy_w, done_w, error_w, mac_beat_w;
    wire [2:0] cfg_op_w;
    wire [4:0] cfg_block_w;
    wire [4:0] cfg_channel_w;
    wire cfg_ready_w;
    wire cfg_lut_ready_w;
    wire [7:0] cfg_lut_addr_w;
    integer cycle_r = 0;
    integer cfg_count_r = 0;
    integer lut_count_r = 0;
    integer mac_count_r = 0;
    integer read_count_r = 0;
    integer write_count_r = 0;
    integer idx;
    integer row;
    integer pair;
    integer plane;
    integer pixel;
    integer channel;
    integer expected;
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
        input integer y_i;
        input integer x_i;
        integer ky;
        integer kx;
        begin
            tap_count = 0;
            for (ky = -1; ky <= 1; ky = ky + 1)
                for (kx = -1; kx <= 1; kx = kx + 1)
                    if (y_i+ky >= 0 && y_i+ky < 4 &&
                        x_i+kx >= 0 && x_i+kx < 8)
                        tap_count = tap_count + 1;
        end
    endfunction

    function integer bottleneck1_value;
        input integer y_i;
        input integer x_i;
        integer ky;
        integer kx;
        integer sum;
        begin
            sum = 0;
            for (ky = -1; ky <= 1; ky = ky + 1)
                for (kx = -1; kx <= 1; kx = kx + 1)
                    if (y_i+ky >= 0 && y_i+ky < 4 &&
                        x_i+kx >= 0 && x_i+kx < 8)
                        sum = sum + tap_count(y_i+ky, x_i+kx);
            bottleneck1_value = sum;
        end
    endfunction

    edrv32_yolo_c2f dut (
        .clk_i(clk_i), .rst_n_i(rst_n_i),
        .start_i(start_i), .start_ready_o(start_ready_w),
        .input_base_i(32'h7000),
        .workspace_base_i(32'h9000),
        .temp_base_i(32'hB000),
        .output_base_i(32'hD000),
        .plane_stride_i(32'd512), .plane_beats_i(16'd16),
        .weight_split_i(32'h0000),
        .weight_bottleneck0_i(32'h1000),
        .weight_bottleneck1_i(32'h3000),
        .weight_bottleneck2_i(32'd0),
        .weight_bottleneck3_i(32'd0),
        .weight_fuse_i(32'h5000),
        .width_i(11'd8), .height_i(16'd4),
        .tile_pairs_i(10'd2),
        .input_blocks_i(6'd2),
        .hidden_blocks_log2_i(2'd0),
        .output_blocks_i(5'd1),
        .input_cache_row_stride_i(10'd4),
        .two_bottlenecks_i(1'b0),
        .shortcut_i(1'b1),
        .residual_zero_point_i(8'd0),
        .busy_o(busy_w), .done_o(done_w),
        .error_o(error_w), .mac_beat_o(mac_beat_w),
        .cfg_op_o(cfg_op_w), .cfg_block_o(cfg_block_w),
        .cfg_channel_o(cfg_channel_w),
        .cfg_valid_i(cycle_r % 7 != 3),
        .cfg_ready_o(cfg_ready_w),
        .cfg_bias_i(32'd0),
        .cfg_multiplier_i(16'd1),
        .cfg_shift_i(cfg_op_w == 3'd0 || cfg_op_w == 3'd2 ?
                     6'd5 : 6'd4),
        .cfg_zero_point_i(8'd0),
        .cfg_lut_enable_i(1'b1),
        .cfg_lut_valid_i(cycle_r % 5 != 1),
        .cfg_lut_ready_o(cfg_lut_ready_w),
        .cfg_lut_addr_o(cfg_lut_addr_w),
        .cfg_lut_data_i(cfg_lut_addr_w),
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
            cycle_r <= cycle_r + 1;
            if (cfg_ready_w && cycle_r % 7 != 3) begin
                if (cfg_op_w != (cfg_count_r / 32 == 3 ? 5 :
                                 cfg_count_r / 32) ||
                    cfg_channel_w != cfg_count_r % 32)
                    $fatal(1, "C2f quant order op=%0d channel=%0d count=%0d",
                           cfg_op_w, cfg_channel_w, cfg_count_r);
                cfg_count_r <= cfg_count_r + 1;
            end
            if (cfg_lut_ready_w && cycle_r % 5 != 1) begin
                if (cfg_op_w != (lut_count_r / 256 == 3 ? 5 :
                                 lut_count_r / 256) ||
                    cfg_lut_addr_w != lut_count_r % 256)
                    $fatal(1, "C2f LUT order op=%0d addr=%0d count=%0d",
                           cfg_op_w, cfg_lut_addr_w, lut_count_r);
                lut_count_r <= lut_count_r + 1;
            end
            if (mac_beat_w)
                mac_count_r <= mac_count_r + 1;
            if (rvalid_w && rready_w)
                read_count_r <= read_count_r + 1;
            if (wvalid_w && wready_w)
                write_count_r <= write_count_r + 1;
        end
    end

    initial begin
        for (idx = 0; idx < 32; idx = idx + 1)
            u_memory.store[(32'h0000 >> 5) + idx] =
                idx % 8 < 4 ? {32{8'd1}} : {32{8'd2}};
        for (idx = 0; idx < 144; idx = idx + 1) begin
            u_memory.store[(32'h1000 >> 5) + idx] = {32{8'd1}};
            u_memory.store[(32'h3000 >> 5) + idx] = {32{8'd1}};
        end
        for (idx = 0; idx < 48; idx = idx + 1)
            u_memory.store[(32'h5000 >> 5) + idx] = {32{8'd1}};
        for (idx = 0; idx < 32; idx = idx + 1)
            u_memory.store[(32'h7000 >> 5) + idx] = {32{8'd1}};
        for (idx = 0; idx < 16; idx = idx + 1) begin
            u_memory.store[(32'hB200 >> 5) + idx] = {32{8'hA5}};
            u_memory.store[(32'h9600 >> 5) + idx] = {32{8'hA5}};
        end

        repeat (5) @(negedge clk_i);
        rst_n_i = 1'b1;
        @(negedge clk_i);
        if (!start_ready_w)
            $fatal(1, "C2f start not ready");
        start_i = 1'b1;
        @(negedge clk_i);
        start_i = 1'b0;
        wait (done_w);
        #1;
        if (error_w || busy_w || cfg_count_r != 128 ||
            lut_count_r != 1024 ||
            mac_count_r != 736 || read_count_r != 512 ||
            write_count_r != 112)
            $fatal(1, "C2f counters err=%0d cfg=%0d lut=%0d mac=%0d read=%0d write=%0d",
                   error_w, cfg_count_r, lut_count_r, mac_count_r,
                   read_count_r, write_count_r);

        for (plane = 0; plane < 2; plane = plane + 1)
            for (row = 0; row < 4; row = row + 1)
                for (pair = 0; pair < 4; pair = pair + 1) begin
                    actual_beat = u_memory.store[(32'hD000 >> 5) +
                                                 plane*16 + row*4 + pair];
                    for (pixel = 0; pixel < 2; pixel = pixel + 1) begin
                        expected = 5 + bottleneck1_value(row,
                                                          pair*2 + pixel);
                        for (channel = 0; channel < 16;
                             channel = channel + 1)
                            if (actual_beat[(pixel*16+channel)*8 +: 8]
                                !== expected[7:0])
                                $fatal(1, "C2f output mismatch plane=%0d y=%0d x=%0d channel=%0d got=%0d expected=%0d",
                                       plane, row, pair*2+pixel, channel,
                                       actual_beat[(pixel*16+channel)*8 +: 8],
                                       expected);
                    end
                end
        for (row = 0; row < 4; row = row + 1)
            for (pair = 0; pair < 4; pair = pair + 1)
                for (pixel = 0; pixel < 2; pixel = pixel + 1)
                    for (channel = 0; channel < 16;
                         channel = channel + 1) begin
                        if (u_memory.store[(32'h9000 >> 5) + row*4 + pair]
                                [(pixel*16+channel)*8 +: 8] !== 8'd1 ||
                            u_memory.store[(32'h9200 >> 5) + row*4 + pair]
                                [(pixel*16+channel)*8 +: 8] !== 8'd2 ||
                            u_memory.store[(32'hB000 >> 5) + row*4 + pair]
                                [(pixel*16+channel)*8 +: 8] !==
                                2*tap_count(row, pair*2+pixel) ||
                            u_memory.store[(32'h9400 >> 5) + row*4 + pair]
                                [(pixel*16+channel)*8 +: 8] !==
                                bottleneck1_value(row, pair*2+pixel)+2)
                            $fatal(1, "C2f intermediate mismatch y=%0d x=%0d ch=%0d",
                                   row, pair*2+pixel, channel);
                    end
        for (idx = 0; idx < 16; idx = idx + 1)
            if (u_memory.store[(32'hB200 >> 5) + idx] !== {32{8'hA5}} ||
                u_memory.store[(32'h9600 >> 5) + idx] !== {32{8'hA5}})
                $fatal(1, "C2f disabled C16 plane modified at beat %0d", idx);
        $display("PASS YOLO first C2f DDR path: cfg=%0d lut=%0d mac=%0d read=%0d write=%0d",
                 cfg_count_r, lut_count_r, mac_count_r,
                 read_count_r, write_count_r);
        $finish;
    end

    initial begin
        #2000000;
        $fatal(1, "C2f timeout state=%0d cfg=%0d", dut.state_r,
               cfg_count_r);
    end
endmodule
