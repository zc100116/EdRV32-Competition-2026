`timescale 1ns/1ps

module tb_yolo_v8n_test_system;
    reg clk_i = 1'b0;
    always #5 clk_i = !clk_i;
    reg rst_n_i = 1'b0;
    reg ddr_ready_i = 1'b0;
    wire init_done_w, layer_busy_w, done_w, fail_w;
    wire [4:0] error_flags_w;
    wire [15:0] first_bad_index_w;
    wire [31:0] first_bad_got_w, first_bad_expected_w;
    wire [31:0] mac_count_w, read_count_w, write_count_w;
    wire [31:0] cycle_count_w;
    wire [3:0] awid_w, bid_w, arid_w, rid_w;
    wire [31:0] awaddr_w, araddr_w;
    wire [7:0] awlen_w, arlen_w;
    wire [2:0] awsize_w, arsize_w;
    wire [1:0] awburst_w, arburst_w, bresp_w, rresp_w;
    wire [3:0] awqos_w, arqos_w;
    wire awvalid_w, awready_w, wlast_w, wvalid_w, wready_w;
    wire bvalid_w, bready_w, arvalid_w, arready_w;
    wire rlast_w, rvalid_w, rready_w;
    wire [255:0] wdata_w, rdata_w;
    wire [31:0] wstrb_w;

    edrv32_yolo_v8n_test_system dut (
        .clk_i(clk_i), .rst_n_i(rst_n_i),
        .ddr_ready_i(ddr_ready_i),
        .init_done_o(init_done_w),
        .layer_busy_o(layer_busy_w),
        .done_o(done_w), .fail_o(fail_w),
        .error_flags_o(error_flags_w),
        .first_bad_index_o(first_bad_index_w),
        .first_bad_got_o(first_bad_got_w),
        .first_bad_expected_o(first_bad_expected_w),
        .mac_count_o(mac_count_w),
        .read_count_o(read_count_w),
        .write_count_o(write_count_w),
        .cycle_count_o(cycle_count_w),
        .conv_cycle_count_o(), .pool_cycle_count_o(),
        .other_cycle_count_o(),
        .ar_wait_count_o(), .w_wait_count_o(),
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

    initial begin
        repeat (5) @(negedge clk_i);
        rst_n_i = 1'b1;
        repeat (5) @(negedge clk_i);
        ddr_ready_i = 1'b1;
        wait (done_w);
        #1;
        if (fail_w || error_flags_w != 5'd0 ||
            mac_count_w != 32'd24 || read_count_w != 32'd76 ||
            write_count_w != 32'd96 || !init_done_w)
            $fatal(1, "V8n BIST failed flags=%h mac=%0d read=%0d write=%0d",
                   error_flags_w, mac_count_w,
                   read_count_w, write_count_w);
        $display("PASS YOLO shared BIST: mac=%0d read=%0d write=%0d cycles=%0d",
                 mac_count_w, read_count_w, write_count_w,
                 cycle_count_w);
        $finish;
    end

    initial begin
        #1000000;
        $fatal(1, "V8n BIST timeout state=%0d cmd=%0d",
               dut.state_r, dut.cmd_index_r);
    end
endmodule
