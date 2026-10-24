`timescale 1ns/1ps

module tb_yolo_v8n_profiler;
    reg clk_i = 1'b0;
    reg rst_n_i = 1'b0;
    always #3.333 clk_i = !clk_i;
    reg run_start_i = 1'b0, run_done_i = 1'b0;
    reg [6:0] step_i = 7'd0, read_step_i = 7'd0;
    reg mac_i = 1'b0, arvalid_i = 1'b0, rvalid_i = 1'b0;
    reg awvalid_i = 1'b0, wvalid_i = 1'b0, bvalid_i = 1'b0;
    reg [7:0] arlen_i = 8'd0, awlen_i = 8'd0;
    wire [31:0] cycles_w, mac_w, rbeats_w, wbeats_w;
    wire [31:0] arstall_w, rwait_w, awstall_w, wstall_w, bwait_w;

    edrv32_yolo_v8n_profiler dut (
        .clk_i(clk_i), .rst_n_i(rst_n_i),
        .run_start_i(run_start_i), .run_done_i(run_done_i),
        .step_i(step_i), .mac_beat_i(mac_i),
        .arvalid_i(arvalid_i), .arready_i(1'b1), .arlen_i(arlen_i),
        .rvalid_i(rvalid_i), .rready_i(1'b1),
        .awvalid_i(awvalid_i), .awready_i(1'b1), .awlen_i(awlen_i),
        .wvalid_i(wvalid_i), .wready_i(1'b1),
        .bvalid_i(bvalid_i), .bready_i(1'b1),
        .read_step_i(read_step_i),
        .read_cycles_o(cycles_w), .read_mac_o(mac_w),
        .read_rbeats_o(rbeats_w), .read_wbeats_o(wbeats_w),
        .read_arstall_o(arstall_w), .read_rwait_o(rwait_w),
        .read_awstall_o(awstall_w), .read_wstall_o(wstall_w),
        .read_bwait_o(bwait_w)
    );

    initial begin
        repeat (4) @(negedge clk_i);
        rst_n_i = 1'b1;
        @(negedge clk_i); run_start_i = 1'b1;
        @(negedge clk_i); run_start_i = 1'b0;
        arvalid_i = 1'b1; arlen_i = 8'd1; mac_i = 1'b1;
        @(negedge clk_i); arvalid_i = 1'b0; mac_i = 1'b0;
        repeat (2) @(negedge clk_i);
        rvalid_i = 1'b1;
        @(negedge clk_i); rvalid_i = 1'b0; mac_i = 1'b1;
        @(negedge clk_i); rvalid_i = 1'b1; mac_i = 1'b0;
        @(negedge clk_i); rvalid_i = 1'b0; awvalid_i = 1'b1;
        @(negedge clk_i); awvalid_i = 1'b0; wvalid_i = 1'b1;
        @(negedge clk_i); wvalid_i = 1'b0; bvalid_i = 1'b1;
        @(negedge clk_i); bvalid_i = 1'b0; step_i = 7'd1;
        repeat (3) @(negedge clk_i);
        run_done_i = 1'b1;
        @(negedge clk_i); run_done_i = 1'b0;
        read_step_i = 7'd0;
        @(negedge clk_i);
        if (cycles_w < 32'd8 || mac_w != 32'd2 ||
            rbeats_w != 32'd2 || wbeats_w != 32'd1 ||
            rwait_w < 32'd2 || arstall_w != 32'd0 ||
            awstall_w != 32'd0 || wstall_w != 32'd0)
            $fatal(1, "step0 counters wrong cyc=%0d mac=%0d rb=%0d wb=%0d rw=%0d",
                   cycles_w, mac_w, rbeats_w, wbeats_w, rwait_w);
        read_step_i = 7'd1;
        @(negedge clk_i);
        if (cycles_w < 32'd2 || mac_w != 32'd0 ||
            rbeats_w != 32'd0 || wbeats_w != 32'd0)
            $fatal(1, "step1 counters wrong");
        $display("tb_yolo_v8n_profiler PASS");
        $finish;
    end
    initial begin
        #10000;
        $fatal(1, "profiler timeout");
    end
endmodule
