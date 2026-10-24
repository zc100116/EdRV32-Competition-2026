`timescale 1ns/1ps

module tb_yolo_axi_stream;
    reg clk_i = 1'b0;
    always #5 clk_i = !clk_i;
    reg rst_n_i = 1'b0;
    integer cycle_r = 0;

    reg rd_req_valid_i = 1'b0;
    wire rd_req_ready_w;
    reg [31:0] rd_req_addr_i = 32'h0000_0f80;
    reg [15:0] rd_req_beats_i = 16'd49;
    wire rd_beat_valid_w;
    wire [15:0] rd_beat_index_w;
    wire [255:0] rd_beat_data_w;
    wire rd_busy_w;
    wire rd_done_w;
    wire rd_error_w;
    wire [3:0] arid_w;
    wire [31:0] araddr_w;
    wire [3:0] arlen_w;
    wire [2:0] arsize_w;
    wire [1:0] arburst_w;
    wire arvalid_w;
    wire arready_w = cycle_r % 5 != 1;
    reg [3:0] rid_r = 4'h8;
    reg [255:0] rdata_r = 256'd0;
    reg [1:0] rresp_r = 2'b00;
    reg rlast_r = 1'b0;
    reg rvalid_r = 1'b0;
    wire rready_w;
    integer arq_len [0:15];
    integer arq_rd = 0;
    integer arq_wr = 0;
    integer arq_position = 0;
    integer ar_issued = 0;
    integer rd_received = 0;

    reg wr_start_i = 1'b0;
    wire wr_start_ready_w;
    reg [31:0] wr_plane0_i = 32'h0000_0fe0;
    reg [31:0] wr_plane1_i = 32'h0000_1fc0;
    reg [9:0] wr_pair_count_i = 10'd37;
    reg wr_in_valid_i = 1'b0;
    wire wr_in_ready_w;
    reg [511:0] wr_in_data_i = 512'd0;
    wire wr_busy_w;
    wire wr_done_w;
    wire wr_error_w;
    wire [3:0] awid_w;
    wire [31:0] awaddr_w;
    wire [7:0] awlen_w;
    wire [2:0] awsize_w;
    wire [1:0] awburst_w;
    wire awvalid_w;
    wire awready_w = cycle_r % 7 != 3;
    wire [255:0] wdata_w;
    wire [31:0] wstrb_w;
    wire wlast_w;
    wire wvalid_w;
    wire wready_w = cycle_r % 6 != 2;
    reg [3:0] bid_r = 4'h9;
    reg [1:0] bresp_r = 2'b00;
    reg slow_b_r = 1'b0;
    wire bvalid_w = b_pending > 0 &&
                    (slow_b_r ? cycle_r % 97 == 0 : cycle_r % 4 != 1);
    wire bready_w;
    integer b_pending = 0;
    integer aw_outstanding = 0;
    integer wr_sent = 0;
    integer wr_seen0 = 0;
    integer wr_seen1 = 0;
    integer aw_count = 0;
    integer current_aw_len = 0;
    integer current_aw_addr = 0;
    integer current_aw_plane = 0;
    integer current_w_index = 0;
    integer w_active = 0;
    integer w_last_fire;
    integer b_fire;
    integer rd_next_index;
    integer rd_burst_len;
    integer rd_addr;
    integer plane_pair;
    reg [511:0] expected_pair;

    edrv32_yolo_axi_reader u_reader (
        .clk_i(clk_i), .rst_n_i(rst_n_i),
        .req_valid_i(rd_req_valid_i), .req_ready_o(rd_req_ready_w),
        .req_addr_i(rd_req_addr_i), .req_beats_i(rd_req_beats_i),
        .beat_valid_o(rd_beat_valid_w), .beat_index_o(rd_beat_index_w),
        .beat_data_o(rd_beat_data_w), .busy_o(rd_busy_w),
        .done_o(rd_done_w), .error_o(rd_error_w),
        .m_arid_o(arid_w), .m_araddr_o(araddr_w),
        .m_arlen_o(arlen_w), .m_arsize_o(arsize_w),
        .m_arburst_o(arburst_w), .m_arvalid_o(arvalid_w),
        .m_arready_i(arready_w), .m_rid_i(rid_r),
        .m_rdata_i(rdata_r), .m_rresp_i(rresp_r),
        .m_rlast_i(rlast_r), .m_rvalid_i(rvalid_r),
        .m_rready_o(rready_w)
    );

    edrv32_yolo_axi_writer u_writer (
        .clk_i(clk_i), .rst_n_i(rst_n_i),
        .start_i(wr_start_i), .start_ready_o(wr_start_ready_w),
        .plane0_addr_i(wr_plane0_i), .plane1_addr_i(wr_plane1_i),
        .emit_plane1_i(1'b1),
        .pair_count_i(wr_pair_count_i),
        .in_valid_i(wr_in_valid_i), .in_ready_o(wr_in_ready_w),
        .in_data_i(wr_in_data_i), .busy_o(wr_busy_w),
        .done_o(wr_done_w), .error_o(wr_error_w),
        .m_awid_o(awid_w), .m_awaddr_o(awaddr_w),
        .m_awlen_o(awlen_w), .m_awsize_o(awsize_w),
        .m_awburst_o(awburst_w), .m_awvalid_o(awvalid_w),
        .m_awready_i(awready_w), .m_wdata_o(wdata_w),
        .m_wstrb_o(wstrb_w), .m_wlast_o(wlast_w),
        .m_wvalid_o(wvalid_w), .m_wready_i(wready_w),
        .m_bid_i(bid_r), .m_bresp_i(bresp_r),
        .m_bvalid_i(bvalid_w), .m_bready_o(bready_w)
    );

    function [511:0] pair_data;
        input integer pair_index;
        integer pixel;
        integer channel;
        begin
            pair_data = 512'd0;
            for (pixel = 0; pixel < 2; pixel = pixel + 1)
                for (channel = 0; channel < 32; channel = channel + 1)
                    pair_data[(pixel*32+channel)*8 +: 8] =
                        (pair_index*17 + pixel*53 + channel*7) & 255;
        end
    endfunction

    always @(negedge clk_i) begin
        if (rst_n_i) begin
            wr_in_valid_i = wr_sent < 37 && cycle_r % 9 != 5;
            wr_in_data_i = pair_data(wr_sent);
            rvalid_r = arq_rd < arq_wr && cycle_r % 7 != 4;
            rd_next_index = rd_received;
            rdata_r = {8{32'hcafe_0000 + rd_next_index}};
            rlast_r = rvalid_r &&
                      arq_position + 1 == arq_len[arq_rd];
        end
    end

    always @(posedge clk_i) begin
        if (rst_n_i) begin
            cycle_r <= cycle_r + 1;
            if (arvalid_w && arready_w) begin
                rd_burst_len = arlen_w + 1;
                rd_addr = araddr_w;
                if (arid_w != 4'h8 || arsize_w != 3'd5 ||
                    arburst_w != 2'b01 || rd_burst_len > 16 ||
                    rd_addr % 32 != 0 ||
                    (rd_addr % 4096) + rd_burst_len*32 > 4096 ||
                    rd_addr != 32'hf80 + ar_issued*32)
                    $fatal(1, "Bad AR address=%h len=%0d", rd_addr, rd_burst_len);
                arq_len[arq_wr] <= rd_burst_len;
                arq_wr <= arq_wr + 1;
                ar_issued <= ar_issued + rd_burst_len;
            end
            if (rvalid_r && rready_w) begin
                if (!rd_beat_valid_w || rd_beat_index_w != rd_received ||
                    rd_beat_data_w !== {8{32'hcafe_0000 + rd_received}})
                    $fatal(1, "Bad read beat %0d", rd_received);
                rd_received <= rd_received + 1;
                if (rlast_r) begin
                    arq_rd <= arq_rd + 1;
                    arq_position <= 0;
                end else
                    arq_position <= arq_position + 1;
            end
            if (wr_in_valid_i && wr_in_ready_w)
                wr_sent <= wr_sent + 1;

            if (awvalid_w && awready_w) begin
                if (w_active || awid_w != 4'h9 || awsize_w != 3'd5 ||
                    awburst_w != 2'b01 || awlen_w > 15 ||
                    awaddr_w % 32 != 0 ||
                    (awaddr_w % 4096) + (awlen_w+1)*32 > 4096)
                    $fatal(1, "Bad AW address=%h len=%0d", awaddr_w, awlen_w);
                current_aw_addr <= awaddr_w;
                current_aw_len <= awlen_w+1;
                current_w_index <= 0;
                current_aw_plane <= awaddr_w >= wr_plane1_i;
                w_active <= 1;
                aw_count <= aw_count + 1;
            end
            aw_outstanding <= aw_outstanding +
                              (awvalid_w && awready_w) -
                              (bvalid_w && bready_w);
            if (aw_outstanding > 4)
                $fatal(1, "Writer exceeded four pending B responses");
            if (wvalid_w && wready_w) begin
                if (!w_active || wstrb_w != 32'hffff_ffff ||
                    wlast_w != (current_w_index+1 == current_aw_len))
                    $fatal(1, "Bad W control");
                if (current_aw_plane == 0) begin
                    plane_pair = (current_aw_addr - wr_plane0_i)/32 +
                                 current_w_index;
                    expected_pair = pair_data(plane_pair);
                    if (wdata_w !== {expected_pair[383:256],
                                     expected_pair[127:0]} ||
                        plane_pair != wr_seen0)
                        $fatal(1, "Wrong C16 plane0 pair=%0d", plane_pair);
                    wr_seen0 <= wr_seen0+1;
                end else begin
                    plane_pair = (current_aw_addr - wr_plane1_i)/32 +
                                 current_w_index;
                    expected_pair = pair_data(plane_pair);
                    if (wdata_w !== {expected_pair[511:384],
                                     expected_pair[255:128]} ||
                        plane_pair != wr_seen1)
                        $fatal(1, "Wrong C16 plane1 pair=%0d", plane_pair);
                    wr_seen1 <= wr_seen1+1;
                end
                if (wlast_w)
                    w_active <= 0;
                else
                    current_w_index <= current_w_index+1;
            end
            w_last_fire = wvalid_w && wready_w && wlast_w;
            b_fire = bvalid_w && bready_w;
            b_pending <= b_pending + w_last_fire - b_fire;
        end
    end

    initial begin
        if ($test$plusargs("SLOW_B"))
            slow_b_r = 1'b1;
        repeat (5) @(negedge clk_i);
        rst_n_i = 1'b1;
        @(negedge clk_i);
        rd_req_valid_i = 1'b1;
        wr_start_i = 1'b1;
        @(negedge clk_i);
        rd_req_valid_i = 1'b0;
        wr_start_i = 1'b0;
        wait (rd_done_w && !rd_error_w);
        wait (wr_done_w && !wr_error_w);
        #1;
        if (rd_received != 49 || ar_issued != 49 ||
            wr_sent != 37 || wr_seen0 != 37 || wr_seen1 != 37 ||
            aw_count < 6 || b_pending != 0 || aw_outstanding != 0)
            $fatal(1, "Incomplete AXI stream read=%0d write=%0d/%0d",
                   rd_received, wr_seen0, wr_seen1);
        $display("PASS YOLO AXI: read=%0d beats in %0d bursts; write=%0d pairs in %0d bursts; cycles=%0d",
                 rd_received, arq_wr, wr_seen0, aw_count, cycle_r);
        $finish;
    end

    initial begin
        #100000;
        $fatal(1, "YOLO AXI stream timeout: rd=%0d wr=%0d/%0d",
               rd_received, wr_seen0, wr_seen1);
    end
endmodule
