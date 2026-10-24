`timescale 1ns/1ps

module tb_yolo_ddr_test_system;
    reg clk_i = 1'b0;
    always #5 clk_i = !clk_i;
    reg rst_n_i = 1'b0;
    reg ddr_ready_i = 1'b0;
    wire init_done_w;
    wire layer_busy_w;
    wire done_w;
    wire fail_w;
    wire [31:0] mac_count_w;
    wire [31:0] read_count_w;
    wire [31:0] write_count_w;
    wire [31:0] cycle_count_w;
    wire [3:0] awid_w;
    wire [31:0] awaddr_w;
    wire [7:0] awlen_w;
    wire [2:0] awsize_w;
    wire [1:0] awburst_w;
    wire [3:0] awqos_w;
    wire awvalid_w;
    wire awready_w = cycle_r % 7 != 2;
    wire [255:0] wdata_w;
    wire [31:0] wstrb_w;
    wire wlast_w;
    wire wvalid_w;
    wire wready_w = cycle_r % 8 != 4;
    wire [3:0] bid_w = bq_id[bq_rd];
    wire [1:0] bresp_w = 2'b00;
    wire bvalid_w = bq_rd < bq_wr && cycle_r % 5 != 1;
    wire bready_w;
    wire [3:0] arid_w;
    wire [31:0] araddr_w;
    wire [7:0] arlen_w;
    wire [2:0] arsize_w;
    wire [1:0] arburst_w;
    wire [3:0] arqos_w;
    wire arvalid_w;
    wire arready_w = cycle_r % 9 != 3;
    wire [3:0] rid_w = arq_id[arq_rd];
    wire [255:0] rdata_w = memory_r[(arq_addr[arq_rd] >> 5)+arq_pos];
    wire [1:0] rresp_w = 2'b00;
    wire rlast_w = arq_pos+1 == arq_len[arq_rd];
    wire rvalid_w = arq_rd < arq_wr && cycle_r % 6 != 1;
    wire rready_w;

    reg [255:0] memory_r [0:8191];
    integer cycle_r = 0;
    integer awq_addr [0:63];
    integer awq_len [0:63];
    reg [3:0] awq_id [0:63];
    integer awq_rd = 0;
    integer awq_wr = 0;
    integer awq_pos = 0;
    reg [3:0] bq_id [0:63];
    integer bq_rd = 0;
    integer bq_wr = 0;
    integer arq_addr [0:63];
    integer arq_len [0:63];
    reg [3:0] arq_id [0:63];
    integer arq_rd = 0;
    integer arq_wr = 0;
    integer arq_pos = 0;
    integer init_write_beats = 0;
    integer layer_write_beats = 0;
    integer verify_read_beats = 0;
    integer i;

    edrv32_yolo_ddr_test_system dut (
        .clk_i(clk_i), .rst_n_i(rst_n_i),
        .ddr_ready_i(ddr_ready_i),
        .init_done_o(init_done_w),
        .layer_busy_o(layer_busy_w),
        .done_o(done_w), .fail_o(fail_w),
        .mac_count_o(mac_count_w),
        .read_count_o(read_count_w),
        .write_count_o(write_count_w),
        .cycle_count_o(cycle_count_w),
        .m_awid_o(awid_w), .m_awaddr_o(awaddr_w),
        .m_awlen_o(awlen_w), .m_awsize_o(awsize_w),
        .m_awburst_o(awburst_w), .m_awqos_o(awqos_w),
        .m_awvalid_o(awvalid_w), .m_awready_i(awready_w),
        .m_wdata_o(wdata_w), .m_wstrb_o(wstrb_w),
        .m_wlast_o(wlast_w), .m_wvalid_o(wvalid_w),
        .m_wready_i(wready_w),
        .m_bid_i(bid_w), .m_bresp_i(bresp_w),
        .m_bvalid_i(bvalid_w), .m_bready_o(bready_w),
        .m_arid_o(arid_w), .m_araddr_o(araddr_w),
        .m_arlen_o(arlen_w), .m_arsize_o(arsize_w),
        .m_arburst_o(arburst_w), .m_arqos_o(arqos_w),
        .m_arvalid_o(arvalid_w), .m_arready_i(arready_w),
        .m_rid_i(rid_w), .m_rdata_i(rdata_w),
        .m_rresp_i(rresp_w), .m_rlast_i(rlast_w),
        .m_rvalid_i(rvalid_w), .m_rready_o(rready_w)
    );

    always @(posedge clk_i) begin
        if (rst_n_i) begin
            cycle_r <= cycle_r+1;
            if (awvalid_w && awready_w) begin
                if (awaddr_w[4:0] != 5'd0 || awlen_w > 15 ||
                    awsize_w != 3'd5 || awburst_w != 2'b01)
                    $fatal(1, "Invalid AW");
                awq_addr[awq_wr] <= awaddr_w;
                awq_len[awq_wr] <= awlen_w+1;
                awq_id[awq_wr] <= awid_w;
                awq_wr <= awq_wr+1;
            end
            if (wvalid_w && wready_w) begin
                if (awq_rd >= awq_wr || wstrb_w != 32'hffff_ffff ||
                    wlast_w != (awq_pos+1 == awq_len[awq_rd]))
                    $fatal(1, "Invalid W ordering");
                memory_r[(awq_addr[awq_rd] >> 5)+awq_pos] <= wdata_w;
                if (awq_id[awq_rd] == 4'h1)
                    init_write_beats <= init_write_beats+1;
                else
                    layer_write_beats <= layer_write_beats+1;
                if (wlast_w) begin
                    bq_id[bq_wr] <= awq_id[awq_rd];
                    bq_wr <= bq_wr+1;
                    awq_rd <= awq_rd+1;
                    awq_pos <= 0;
                end else
                    awq_pos <= awq_pos+1;
            end
            if (bvalid_w && bready_w)
                bq_rd <= bq_rd+1;
            if (arvalid_w && arready_w) begin
                if (araddr_w[4:0] != 5'd0 || arlen_w > 15 ||
                    arsize_w != 3'd5 || arburst_w != 2'b01)
                    $fatal(1, "Invalid AR");
                arq_addr[arq_wr] <= araddr_w;
                arq_len[arq_wr] <= arlen_w+1;
                arq_id[arq_wr] <= arid_w;
                arq_wr <= arq_wr+1;
            end
            if (rvalid_w && rready_w) begin
                if (arq_id[arq_rd] == 4'h1)
                    verify_read_beats <= verify_read_beats+1;
                if (rlast_w) begin
                    arq_rd <= arq_rd+1;
                    arq_pos <= 0;
                end else
                    arq_pos <= arq_pos+1;
            end
        end
    end

    initial begin
        for (i = 0; i < 8192; i = i+1)
            memory_r[i] = 256'd0;
        repeat (5) @(negedge clk_i);
        rst_n_i = 1'b1;
        repeat (5) @(negedge clk_i);
        ddr_ready_i = 1'b1;
        wait (done_w);
        #1;
        if (fail_w || init_write_beats != 156 ||
            layer_write_beats != 24 || verify_read_beats != 24 ||
            mac_count_w != 216 || read_count_w != 156 ||
            write_count_w != 24)
            $fatal(1, "DDR BIST failed init=%0d layerwr=%0d verify=%0d mac=%0d rd=%0d wr=%0d fail=%0d state=%0d",
                   init_write_beats, layer_write_beats,
                   verify_read_beats, mac_count_w,
                   read_count_w, write_count_w, fail_w, dut.state_r);
        $display("PASS YOLO DDR board path: init=%0d read=%0d mac=%0d write=%0d verify=%0d cycles=%0d",
                 init_write_beats, read_count_w,
                 mac_count_w, write_count_w,
                 verify_read_beats, cycle_count_w);
        $finish;
    end
    initial begin
        #5000000;
        $fatal(1, "DDR board path timeout state=%0d init=%0d rd=%0d wr=%0d",
               dut.state_r, init_write_beats,
               read_count_w, layer_write_beats);
    end
endmodule
