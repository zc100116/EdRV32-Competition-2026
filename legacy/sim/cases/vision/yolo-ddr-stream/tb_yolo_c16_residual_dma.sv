`timescale 1ns/1ps

module tb_yolo_c16_residual_dma;
    reg clk_i = 1'b0;
    reg rst_n_i = 1'b0;
    always #5 clk_i = !clk_i;

    reg start_i = 1'b0;
    wire start_ready_w;
    reg [31:0] a_base_i = 32'h0000_0fe0;
    reg [31:0] b_base_i = 32'h0000_4fe0;
    reg [31:0] output_base_i = 32'h0000_9fe0;
    wire busy_w;
    wire done_w;
    wire error_w;
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
    wire arready_mem_w, awready_mem_w, wready_mem_w;
    wire rvalid_mem_w, bvalid_mem_w;
    integer cycle_r = 0;
    wire ar_gate_w = cycle_r % 7 != 2;
    wire aw_gate_w = cycle_r % 9 != 3;
    wire w_gate_w = cycle_r % 8 != 5;
    wire r_gate_w = cycle_r % 6 != 1;
    wire b_gate_w = cycle_r % 5 != 4;
    assign arready_w = arready_mem_w && ar_gate_w;
    assign awready_w = awready_mem_w && aw_gate_w;
    assign wready_w = wready_mem_w && w_gate_w;
    assign rvalid_w = rvalid_mem_w && r_gate_w;
    assign bvalid_w = bvalid_mem_w && b_gate_w;

    integer ar_count_r = 0;
    integer aw_count_r = 0;
    integer read_count_r = 0;
    integer write_count_r = 0;
    integer b_count_r = 0;
    integer beat;
    integer lane;
    reg [7:0] expected_byte;

    function [7:0] a_byte;
        input integer beat_i;
        input integer lane_i;
        integer value;
        begin
            value = (beat_i*37 + lane_i*19) % 256 - 128;
            a_byte = value[7:0];
        end
    endfunction

    function [7:0] b_byte;
        input integer beat_i;
        input integer lane_i;
        integer value;
        begin
            value = (beat_i*11 + lane_i*29) % 256 - 128;
            b_byte = value[7:0];
        end
    endfunction

    function [7:0] saturate_add;
        input [7:0] a_i;
        input [7:0] b_i;
        integer sum;
        begin
            sum = $signed(a_i) + $signed(b_i) + 5;
            if (sum > 127)
                saturate_add = 8'h7f;
            else if (sum < -128)
                saturate_add = 8'h80;
            else
                saturate_add = sum[7:0];
        end
    endfunction

    edrv32_yolo_c16_residual_dma dut (
        .clk_i(clk_i), .rst_n_i(rst_n_i),
        .start_i(start_i), .start_ready_o(start_ready_w),
        .a_base_i(a_base_i), .b_base_i(b_base_i),
        .output_base_i(output_base_i),
        .beat_count_i(16'd37), .zero_point_i(8'hfb),
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
        .awburst_i(awburst_w), .awvalid_i(awvalid_w && aw_gate_w),
        .awready_o(awready_mem_w),
        .wdata_i(wdata_w), .wstrb_i(wstrb_w),
        .wlast_i(wlast_w), .wvalid_i(wvalid_w && w_gate_w),
        .wready_o(wready_mem_w),
        .bid_o(bid_w), .bresp_o(bresp_w),
        .bvalid_o(bvalid_mem_w), .bready_i(bready_w && b_gate_w),
        .arid_i(arid_w), .araddr_i(araddr_w),
        .arlen_i(arlen_w), .arsize_i(arsize_w),
        .arburst_i(arburst_w), .arvalid_i(arvalid_w && ar_gate_w),
        .arready_o(arready_mem_w),
        .rid_o(rid_w), .rdata_o(rdata_w),
        .rresp_o(rresp_w), .rlast_o(rlast_w),
        .rvalid_o(rvalid_mem_w), .rready_i(rready_w && r_gate_w)
    );

    always @(posedge clk_i) begin
        if (rst_n_i) begin
            cycle_r <= cycle_r + 1;
            if (arvalid_w && arready_w) begin
                if (arid_w != 4'h8 || arsize_w != 3'd5 ||
                    arburst_w != 2'b01 || arlen_w > 8'd15 ||
                    araddr_w[4:0] != 5'd0 ||
                    araddr_w[11:0] + ({24'd0, arlen_w} + 32'd1)*32 >
                    32'd4096)
                    $fatal(1, "Invalid residual AR addr=%h len=%0d",
                           araddr_w, arlen_w);
                ar_count_r <= ar_count_r + 1;
            end
            if (awvalid_w && awready_w) begin
                if (awid_w != 4'h9 || awsize_w != 3'd5 ||
                    awburst_w != 2'b01 || awlen_w > 8'd15 ||
                    awaddr_w[4:0] != 5'd0 ||
                    awaddr_w[11:0] + ({24'd0, awlen_w} + 32'd1)*32 >
                    32'd4096)
                    $fatal(1, "Invalid residual AW addr=%h len=%0d",
                           awaddr_w, awlen_w);
                aw_count_r <= aw_count_r + 1;
            end
            if (rvalid_w && rready_w)
                read_count_r <= read_count_r + 1;
            if (wvalid_w && wready_w)
                write_count_r <= write_count_r + 1;
            if (bvalid_w && bready_w)
                b_count_r <= b_count_r + 1;
        end
    end

    task automatic run_dma;
        begin
            @(negedge clk_i);
            if (!start_ready_w)
                $fatal(1, "Residual DMA not ready");
            start_i = 1'b1;
            @(negedge clk_i);
            start_i = 1'b0;
            wait (done_w);
            #1;
            if (error_w || busy_w)
                $fatal(1, "Residual DMA error");
        end
    endtask

    initial begin
        for (beat = 0; beat < 37; beat = beat + 1) begin
            u_memory.store[(32'h0fe0 >> 5) + beat] = 256'd0;
            u_memory.store[(32'h4fe0 >> 5) + beat] = 256'd0;
            for (lane = 0; lane < 32; lane = lane + 1) begin
                u_memory.store[(32'h0fe0 >> 5) + beat][lane*8 +: 8] =
                    a_byte(beat, lane);
                u_memory.store[(32'h4fe0 >> 5) + beat][lane*8 +: 8] =
                    b_byte(beat, lane);
            end
        end

        repeat (5) @(negedge clk_i);
        rst_n_i = 1'b1;
        run_dma();
        for (beat = 0; beat < 37; beat = beat + 1)
            for (lane = 0; lane < 32; lane = lane + 1) begin
                expected_byte = saturate_add(a_byte(beat, lane),
                                             b_byte(beat, lane));
                if (u_memory.store[(32'h9fe0 >> 5) + beat][lane*8 +: 8]
                    !== expected_byte)
                    $fatal(1, "Residual output mismatch beat=%0d lane=%0d",
                           beat, lane);
            end

        // The second pass writes in place after each source chunk is read.
        a_base_i = 32'h0000_9fe0;
        run_dma();
        for (beat = 0; beat < 37; beat = beat + 1)
            for (lane = 0; lane < 32; lane = lane + 1) begin
                expected_byte = saturate_add(
                    saturate_add(a_byte(beat, lane), b_byte(beat, lane)),
                    b_byte(beat, lane));
                if (u_memory.store[(32'h9fe0 >> 5) + beat][lane*8 +: 8]
                    !== expected_byte)
                    $fatal(1, "In-place residual mismatch beat=%0d lane=%0d",
                           beat, lane);
            end
        if (ar_count_r != 16 || aw_count_r != 8 ||
            read_count_r != 148 || write_count_r != 74 ||
            b_count_r != 8)
            $fatal(1, "Residual DMA counters AR=%0d AW=%0d R=%0d W=%0d B=%0d",
                   ar_count_r, aw_count_r, read_count_r,
                   write_count_r, b_count_r);
        $display("PASS YOLO residual DDR DMA: two 37-beat runs, 4KiB splits and in-place write");
        $finish;
    end

    initial begin
        #1000000;
        $fatal(1, "Residual DMA timeout state=%0d completed=%0d",
               dut.state_r, dut.completed_beats_r);
    end
endmodule
