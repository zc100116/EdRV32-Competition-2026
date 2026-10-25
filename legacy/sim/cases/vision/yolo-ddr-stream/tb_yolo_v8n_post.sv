`timescale 1ns/1ps

module tb_yolo_v8n_post;
    reg clk_i = 1'b0;
    reg rst_n_i = 1'b0;
    always #3.333 clk_i = !clk_i;
    reg start_i = 1'b0;
    wire start_ready_w, busy_w, done_w, error_w;
    wire [9:0] candidate_count_w;
    wire [6:0] detection_count_w, row_w, pixel_w;
    wire [1:0] scale_w;
    wire [31:0] load_cycles_w, class_cycles_w, dfl_cycles_w;
    wire [31:0] nms_cycles_w, meta_write_cycles_w;
    wire [31:0] post_rbeats_w, post_wbeats_w;
    wire [31:0] post_arstall_w, post_rwait_w;
    wire [31:0] post_awstall_w, post_wstall_w, post_bwait_w;
    wire [3:0] arid_w, awid_w;
    wire [31:0] araddr_w, awaddr_w;
    wire [7:0] arlen_w, awlen_w;
    wire [2:0] arsize_w, awsize_w;
    wire [1:0] arburst_w, awburst_w;
    wire arvalid_w, rready_w, awvalid_w;
    wire [255:0] wdata_w;
    wire [31:0] wstrb_w;
    wire wlast_w, wvalid_w, bready_w;
    reg read_active_r = 1'b0;
    reg [7:0] read_remaining_r = 8'd0;
    reg bvalid_r = 1'b0;
    reg [31:0] write_addr_r = 32'd0;
    reg [31:0] read_addr_r = 32'd0;
    reg [255:0] header_r = 256'd0;
    reg [255:0] geometry_r = 256'd0;
    reg [255:0] record_r = 256'd0;
    reg [255:0] records_r [0:99];
    integer read_beats_r = 0;
    integer write_beats_r = 0;
`ifdef TEST_REAL
    reg [255:0] logits_r [0:22711];
    wire [255:0] response_data_w =
        read_addr_r >= 32'h027d_3000 &&
        read_addr_r < 32'h0288_4700 ?
        logits_r[(read_addr_r - 32'h027d_3000) >> 5] : 256'd0;
    integer logits_fd, logits_length;
    initial begin
        logits_fd = $fopen("out/board/yolo_bus_head_logits_beats.bin", "rb");
        if (logits_fd == 0)
            $fatal(1, "missing packed bus logits");
        logits_length = $fread(logits_r, logits_fd);
        $fclose(logits_fd);
        if (logits_length != 726784)
            $fatal(1, "packed bus logits size mismatch %0d", logits_length);
    end
`elsif TEST_ONE
    wire [255:0] response_data_w =
        read_addr_r == 32'h0280_f000 ? 256'd127 : 256'd0;
`else
    wire [255:0] response_data_w = 256'd0;
`endif

    edrv32_yolo_v8n_post dut (
        .clk_i(clk_i), .rst_n_i(rst_n_i),
        .start_i(start_i), .start_ready_o(start_ready_w),
        .source_width_i(16'd810), .source_height_i(16'd1080),
        .scaled_width_i(16'd288), .scaled_height_i(16'd384),
        .pad_left_i(16'd176), .pad_top_i(16'd0),
        .busy_o(busy_w), .done_o(done_w), .error_o(error_w),
        .candidate_count_o(candidate_count_w),
        .detection_count_o(detection_count_w),
        .scale_o(scale_w), .row_o(row_w), .pixel_o(pixel_w),
        .load_cycles_o(load_cycles_w),
        .class_cycles_o(class_cycles_w),
        .dfl_cycles_o(dfl_cycles_w),
        .nms_cycles_o(nms_cycles_w),
        .meta_write_cycles_o(meta_write_cycles_w),
        .read_beats_o(post_rbeats_w),
        .write_beats_o(post_wbeats_w),
        .ar_stall_o(post_arstall_w),
        .read_wait_o(post_rwait_w),
        .aw_stall_o(post_awstall_w),
        .write_stall_o(post_wstall_w),
        .response_wait_o(post_bwait_w),
        .m_arid_o(arid_w), .m_araddr_o(araddr_w),
        .m_arlen_o(arlen_w), .m_arsize_o(arsize_w),
        .m_arburst_o(arburst_w), .m_arvalid_o(arvalid_w),
        .m_arready_i(!read_active_r),
        .m_rid_i(4'h8), .m_rdata_i(response_data_w),
        .m_rresp_i(2'b00), .m_rlast_i(read_remaining_r == 8'd1),
        .m_rvalid_i(read_active_r), .m_rready_o(rready_w),
        .m_awid_o(awid_w), .m_awaddr_o(awaddr_w),
        .m_awlen_o(awlen_w), .m_awsize_o(awsize_w),
        .m_awburst_o(awburst_w), .m_awvalid_o(awvalid_w),
        .m_awready_i(1'b1),
        .m_wdata_o(wdata_w), .m_wstrb_o(wstrb_w),
        .m_wlast_o(wlast_w), .m_wvalid_o(wvalid_w),
        .m_wready_i(1'b1),
        .m_bid_i(4'ha), .m_bresp_i(2'b00),
        .m_bvalid_i(bvalid_r), .m_bready_o(bready_w)
    );

    always @(posedge clk_i) begin
        if (arvalid_w && !read_active_r) begin
            if (arid_w != 4'h8 || arsize_w != 3'd5 ||
                arburst_w != 2'b01)
                $fatal(1, "post AXI read request invalid");
            read_active_r <= 1'b1;
            read_remaining_r <= arlen_w + 8'd1;
            read_addr_r <= araddr_w;
        end
        if (read_active_r && rready_w) begin
            read_beats_r <= read_beats_r + 1;
            read_remaining_r <= read_remaining_r - 8'd1;
            read_addr_r <= read_addr_r + 32'd32;
            if (read_remaining_r == 8'd1)
                read_active_r <= 1'b0;
        end
        if (awvalid_w) begin
            if (awid_w != 4'ha || awlen_w != 8'd0 ||
                awsize_w != 3'd5 || awburst_w != 2'b01)
                $fatal(1, "post AXI write request invalid");
            write_addr_r <= awaddr_w;
        end
        if (wvalid_w) begin
            if ((write_addr_r < 32'h02a0_b000 ||
                 write_addr_r > 32'h02a0_bca0) ||
                !wlast_w || wstrb_w != 32'hffff_ffff)
                $fatal(1, "unexpected post DDR write");
            if (write_addr_r == 32'h02a0_b000)
                header_r <= wdata_w;
            else if (write_addr_r == 32'h02a0_b020)
                geometry_r <= wdata_w;
            else begin
                records_r[(write_addr_r - 32'h02a0_b040) >> 5] <= wdata_w;
                if (write_addr_r == 32'h02a0_b040)
                    record_r <= wdata_w;
            end
            write_beats_r <= write_beats_r + 1;
            bvalid_r <= 1'b1;
        end else if (bvalid_r && bready_w)
            bvalid_r <= 1'b0;
    end

    initial begin
        repeat (5) @(negedge clk_i);
        rst_n_i = 1'b1;
        @(negedge clk_i);
        start_i = 1'b1;
        @(negedge clk_i);
        start_i = 1'b0;
        wait (done_w);
        if (error_w || read_beats_r != 22680 ||
            post_rbeats_w != 32'd22680 ||
            post_wbeats_w != write_beats_r ||
            load_cycles_w == 32'd0 || class_cycles_w < 32'd400000 ||
            nms_cycles_w == 32'd0 ||
            meta_write_cycles_w == 32'd0 ||
            header_r[31:0] != 32'h5445_4d59 ||
            header_r[63:32] != 32'd2 ||
            header_r[159:128] != 32'd640 ||
            header_r[191:160] != 32'd384 ||
            geometry_r[31:0] != 32'd810 ||
            geometry_r[63:32] != 32'd1080 ||
            geometry_r[95:64] != 32'd288 ||
            geometry_r[127:96] != 32'd384 ||
            geometry_r[159:128] != 32'd176 ||
            geometry_r[191:160] != 32'd0)
            $fatal(1, "post scan mismatch read=%0d write=%0d cand=%0d det=%0d error=%0d",
                   read_beats_r, write_beats_r,
                   candidate_count_w, detection_count_w, error_w);
`ifdef TEST_REAL
        $display("REAL META det=%0d cand=%0d first class=%0d score=%0d box=(%0d,%0d,%0d,%0d)",
                 detection_count_w, candidate_count_w,
                 record_r[135:128], record_r[151:136],
                 record_r[31:0], record_r[63:32],
                 record_r[95:64], record_r[127:96]);
        if (detection_count_w != 7'd4 ||
            write_beats_r != detection_count_w + 2 ||
            header_r[95:64] != detection_count_w ||
            records_r[0][135:128] != 8'd0 ||
            records_r[1][135:128] != 8'd0 ||
            records_r[2][135:128] != 8'd5 ||
            records_r[3][135:128] != 8'd0 ||
            records_r[0][151:136] != 16'd25739 ||
            records_r[1][151:136] != 16'd24106 ||
            records_r[2][151:136] != 16'd21521 ||
            records_r[3][151:136] != 16'd19692 ||
            records_r[0][31:0] < 32'd48201 ||
            records_r[0][31:0] > 32'd48713 ||
            records_r[0][63:32] < 32'd36259 ||
            records_r[0][63:32] > 32'd36771 ||
            records_r[0][95:64] < 32'd67608 ||
            records_r[0][95:64] > 32'd68120 ||
            records_r[0][127:96] < 32'd82484 ||
            records_r[0][127:96] > 32'd82996)
            $fatal(1, "real post META count mismatch");
`elsif TEST_ONE
        if (candidate_count_w != 10'd1 || detection_count_w != 7'd1 ||
            write_beats_r != 3 || header_r[95:64] != 32'd1 ||
            record_r[31:0] != 32'd0 || record_r[63:32] != 32'd0 ||
            record_r[95:64] != 32'd16384 ||
            record_r[127:96] != 32'd16384 ||
            record_r[135:128] != 8'd0 ||
            record_r[151:136] != 16'd28910 ||
            record_r[175:160] != 16'd0)
            $fatal(1, "post single-object META mismatch record=%h count=%0d",
                   record_r, detection_count_w);
`else
        if (candidate_count_w != 10'd0 || detection_count_w != 7'd0 ||
            write_beats_r != 2 || header_r[95:64] != 32'd0)
            $fatal(1, "post empty META mismatch");
`endif
        $display("tb_yolo_v8n_post PASS: %0d read beats, %0d detections",
                 read_beats_r, detection_count_w);
        $finish;
    end

    initial begin
        #10000000;
        $fatal(1, "post timeout scale=%0d row=%0d pixel=%0d state=%0d",
               scale_w, row_w, pixel_w, dut.state_r);
    end
endmodule
