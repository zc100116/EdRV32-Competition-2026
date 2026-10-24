`timescale 1ns/1ps

module tb_yolo_v8n_reporter;
    reg clk_i = 1'b0;
    reg rst_n_i = 1'b0;
    reg start_i = 1'b0;
    reg detection_valid_i = 1'b0;
    reg [6:0] detection_index_i = 7'd0;
    reg [255:0] detection_record_i = 256'd0;
    always #3.333 clk_i = !clk_i;
    wire [6:0] step_w;
    wire tx_valid_w, busy_w, done_w;
    wire [7:0] tx_data_w;
    reg tx_ready_r = 1'b1;
    reg held_r = 1'b0;
    reg [7:0] held_data_r = 8'd0;
    integer stall_cycle_r = 0;
    reg [7:0] output_r [0:756];
    integer count_r = 0;
    integer index;
    integer log_fd;
    localparam [247:0] EXPECT_STATUS =
        "YV8 PASS STEP=01 CYC=000003E8\r\n";
    localparam [159:0] EXPECT_CORE =
        "YCORE CYC=00000384\r\n";
    localparam [295:0] EXPECT_POST =
        "YPOST CYC=00000064 CAND=0026 DET=04\r\n";
    localparam [519:0] EXPECT_PHASE =
        "YPH LD=0000000A CL=00000014 DF=0000001E NM=00000028 WR=00000032\r\n";
    localparam [719:0] EXPECT_IO =
        "YPIO RB=00005898 WB=00000006 AR=00000001 RW=00000002 AW=00000003 WW=00000004 BW=00000005\r\n";
    localparam [567:0] EXPECT_DET =
        "YDET 00 CL=05 SC=1234 X1=00000100 Y1=00000200 X2=00000300 Y2=00000400\r\n";

    edrv32_yolo_v8n_reporter dut (
        .clk_i(clk_i), .rst_n_i(rst_n_i),
        .start_i(start_i), .fail_i(1'b0), .last_step_i(7'd1),
        .total_cycles_i(32'd1000), .core_cycles_i(32'd900),
        .post_cycles_i(32'd100), .candidate_count_i(10'd38),
        .detection_count_i(7'd4), .profile_valid_i(1'b1),
        .post_load_cycles_i(32'd10),
        .post_class_cycles_i(32'd20),
        .post_dfl_cycles_i(32'd30),
        .post_nms_cycles_i(32'd40),
        .post_meta_cycles_i(32'd50),
        .post_rbeats_i(32'd22680),
        .post_wbeats_i(32'd6),
        .post_arstall_i(32'd1),
        .post_rwait_i(32'd2),
        .post_awstall_i(32'd3),
        .post_wstall_i(32'd4),
        .post_bwait_i(32'd5),
        .detection_valid_i(detection_valid_i),
        .detection_index_i(detection_index_i),
        .detection_record_i(detection_record_i),
        .profile_step_o(step_w),
        .profile_cycles_i(32'd100 + step_w),
        .profile_mac_i(32'd50 + step_w),
        .profile_rbeats_i(32'd20 + step_w),
        .profile_wbeats_i(32'd10 + step_w),
        .profile_arstall_i(32'd1 + step_w),
        .profile_rwait_i(32'd2 + step_w),
        .profile_awstall_i(32'd3 + step_w),
        .profile_wstall_i(32'd4 + step_w),
        .profile_bwait_i(32'd5 + step_w),
        .tx_valid_o(tx_valid_w), .tx_ready_i(tx_ready_r),
        .tx_data_o(tx_data_w), .busy_o(busy_w), .done_o(done_w)
    );

    always @(posedge clk_i) begin
        if (rst_n_i) begin
            stall_cycle_r <= stall_cycle_r + 1;
            tx_ready_r <= stall_cycle_r % 7 != 0 &&
                          stall_cycle_r % 7 != 1;
        end
        if (held_r && (!tx_valid_w || tx_data_w !== held_data_r))
            $fatal(1, "report byte changed during backpressure");
        held_r <= tx_valid_w && !tx_ready_r;
        held_data_r <= tx_data_w;
        if (tx_valid_w && tx_ready_r) begin
            if (count_r >= 757)
                $fatal(1, "reporter sent too many bytes");
            output_r[count_r] <= tx_data_w;
            count_r <= count_r + 1;
            $fwrite(log_fd, "%c", tx_data_w);
        end
    end

    initial begin
        log_fd = $fopen("sim/build/yolo_reporter_sample.log", "w");
        if (log_fd == 0)
            $fatal(1, "cannot create reporter sample log");
        repeat (5) @(negedge clk_i);
        rst_n_i = 1'b1;
        @(negedge clk_i);
        detection_record_i[31:0] = 32'h0000_0100;
        detection_record_i[63:32] = 32'h0000_0200;
        detection_record_i[95:64] = 32'h0000_0300;
        detection_record_i[127:96] = 32'h0000_0400;
        detection_record_i[135:128] = 8'd5;
        detection_record_i[151:136] = 16'h1234;
        detection_valid_i = 1'b1;
        repeat (4) begin
            @(negedge clk_i);
            detection_index_i = detection_index_i + 7'd1;
        end
        detection_valid_i = 1'b0;
        @(negedge clk_i); start_i = 1'b1;
        @(negedge clk_i); start_i = 1'b0;
        wait (done_w);
        if (count_r != 757)
            $fatal(1, "reporter length %0d", count_r);
        for (index = 0; index < 31; index = index + 1)
            if (output_r[index] !==
                (index == 29 ? 8'h0d : EXPECT_STATUS[(30-index)*8 +: 8]))
                $fatal(1, "status byte %0d mismatch", index);
        for (index = 0; index < 20; index = index + 1)
            if (output_r[31+index] !==
                (index == 18 ? 8'h0d : EXPECT_CORE[(19-index)*8 +: 8]))
                $fatal(1, "core byte %0d mismatch", index);
        for (index = 0; index < 37; index = index + 1)
            if (output_r[51+index] !==
                (index == 35 ? 8'h0d : EXPECT_POST[(36-index)*8 +: 8]))
                $fatal(1, "post byte %0d mismatch got=%h exp=%h", index,
                       output_r[51+index], EXPECT_POST[(36-index)*8 +: 8]);
        for (index = 0; index < 65; index = index + 1)
            if (output_r[88+index] !==
                (index == 63 ? 8'h0d : EXPECT_PHASE[(64-index)*8 +: 8]))
                $fatal(1, "phase byte %0d mismatch", index);
        for (index = 0; index < 90; index = index + 1)
            if (output_r[153+index] !==
                (index == 88 ? 8'h0d : EXPECT_IO[(89-index)*8 +: 8]))
                $fatal(1, "post IO byte %0d mismatch", index);
        if (output_r[243] !== "Y" || output_r[244] !== "S" ||
            output_r[246] !== "0" || output_r[247] !== "0" ||
            output_r[252] !== "0" || output_r[259] !== "4" ||
            output_r[356] !== 8'h0d || output_r[357] !== 8'h0a ||
            output_r[361] !== "0" || output_r[362] !== "1")
            $fatal(1, "per-step profile formatting mismatch");
        for (index = 0; index < 71; index = index + 1)
            if (output_r[473+index] !==
                (index == 69 ? 8'h0d : EXPECT_DET[(70-index)*8 +: 8]))
                $fatal(1, "detection byte %0d mismatch got=%h exp=%h",
                       index, output_r[473+index],
                       EXPECT_DET[(70-index)*8 +: 8]);
        $fclose(log_fd);
        $display("tb_yolo_v8n_reporter PASS");
        $finish;
    end
    initial begin
        #10000;
        $fatal(1, "reporter timeout");
    end
endmodule
