// ============================================================================
// File        : tb_ddr_monitor_cdc.sv
// Description : DDR Monitor CDC, 16-beat/4-KiB split, metrics and error test.
// ============================================================================

`timescale 1ns/1ps
`include "edrv32_periph_abi.vh"

module tb_ddr_monitor_cdc;

    reg apb_clk_r;
    reg axi_clk_r;
    reg apb_rst_n_r;
    reg axi_rst_n_r;

    reg [31:0] paddr_r;
    reg psel_r;
    reg penable_r;
    reg pwrite_r;
    reg [31:0] pwdata_r;
    reg [3:0] pstrb_r;
    wire pready_w;
    wire [31:0] prdata_w;
    wire pslverr_w;

    wire [3:0] awid_w;
    wire [31:0] awaddr_w;
    wire [7:0] awlen_w;
    wire [2:0] awsize_w;
    wire [1:0] awburst_w;
    wire [3:0] awqos_w;
    wire awvalid_w;
    wire awready_w;
    wire [255:0] wdata_w;
    wire [31:0] wstrb_w;
    wire wlast_w;
    wire wvalid_w;
    wire wready_w;
    wire [3:0] bid_w;
    wire [1:0] bresp_w;
    wire bvalid_w;
    wire bready_w;
    wire [3:0] arid_w;
    wire [31:0] araddr_w;
    wire [7:0] arlen_w;
    wire [2:0] arsize_w;
    wire [1:0] arburst_w;
    wire [3:0] arqos_w;
    wire arvalid_w;
    wire arready_w;
    wire [3:0] rid_w;
    wire [255:0] rdata_w;
    wire [1:0] rresp_w;
    wire rlast_w;
    wire rvalid_w;
    wire rready_w;

    wire mem_awready_w;
    wire mem_wready_w;
    wire [3:0] mem_bid_w;
    wire [1:0] mem_bresp_w;
    wire mem_bvalid_w;
    wire mem_arready_w;
    wire [3:0] mem_rid_w;
    wire [255:0] mem_rdata_w;
    wire [1:0] mem_rresp_w;
    wire mem_rlast_w;
    wire mem_rvalid_w;

    integer axi_cycle_r;
    integer aw_count_r;
    integer ar_count_r;
    integer checks_r;
    integer failures_r;
    reg [31:0] status_r;
    reg [31:0] value_r;
    reg [31:0] total_cycles_r;
    reg [31:0] write_beats_r;
    reg [31:0] read_beats_r;
    reg [31:0] error_count_r;
    reg [31:0] first_error_addr_r;

    wire aw_allow_w = (axi_cycle_r % 5) != 1;
    wire w_allow_w  = (axi_cycle_r % 4) != 2;
    wire b_allow_w  = (axi_cycle_r % 7) != 3;
    wire ar_allow_w = (axi_cycle_r % 6) != 4;
    wire r_allow_w  = (axi_cycle_r % 3) != 1;

    always #5.0 apb_clk_r = ~apb_clk_r;
    always #4.0 axi_clk_r = ~axi_clk_r;

    task automatic check_true;
        input condition;
        input [8*120-1:0] message;
        begin
            checks_r = checks_r + 1;
            if (!condition) begin
                failures_r = failures_r + 1;
                $display("FAIL: %0s", message);
            end
        end
    endtask

    task automatic apb_write;
        input [7:0] offset;
        input [31:0] data;
        begin
            @(negedge apb_clk_r);
            paddr_r = {24'b0, offset};
            psel_r = 1'b1;
            penable_r = 1'b0;
            pwrite_r = 1'b1;
            pwdata_r = data;
            pstrb_r = 4'hf;
            @(negedge apb_clk_r);
            penable_r = 1'b1;
            @(posedge apb_clk_r);
            #1;
            check_true(pready_w, "APB write did not complete");
            check_true(!pslverr_w, "APB write returned PSLVERR");
            @(negedge apb_clk_r);
            psel_r = 1'b0;
            penable_r = 1'b0;
            pwrite_r = 1'b0;
        end
    endtask

    task automatic apb_read;
        input [7:0] offset;
        output [31:0] data;
        begin
            @(negedge apb_clk_r);
            paddr_r = {24'b0, offset};
            psel_r = 1'b1;
            penable_r = 1'b0;
            pwrite_r = 1'b0;
            pstrb_r = 4'h0;
            @(negedge apb_clk_r);
            penable_r = 1'b1;
            @(posedge apb_clk_r);
            #1;
            data = prdata_w;
            check_true(pready_w, "APB read did not complete");
            check_true(!pslverr_w, "APB read returned PSLVERR");
            @(negedge apb_clk_r);
            psel_r = 1'b0;
            penable_r = 1'b0;
        end
    endtask

    task automatic wait_done;
        integer poll_count;
        begin
            status_r = 32'b0;
            poll_count = 0;
            while (!status_r[`DDR_MON_STATUS_DONE] &&
                   (poll_count < 20000)) begin
                apb_read(`DDR_MON_STATUS, status_r);
                poll_count = poll_count + 1;
            end
            check_true(status_r[`DDR_MON_STATUS_DONE],
                       "monitor did not complete before timeout");
            check_true(!status_r[`DDR_MON_STATUS_BUSY],
                       "BUSY remained set after DONE");
        end
    endtask

    edrv32_ddr_monitor dut (
        .apb_clk_i    (apb_clk_r),
        .apb_rst_n_i  (apb_rst_n_r),
        .paddr_i      (paddr_r),
        .psel_i       (psel_r),
        .penable_i    (penable_r),
        .pwrite_i     (pwrite_r),
        .pwdata_i     (pwdata_r),
        .pstrb_i      (pstrb_r),
        .pready_o     (pready_w),
        .prdata_o     (prdata_w),
        .pslverr_o    (pslverr_w),
        .axi_clk_i    (axi_clk_r),
        .axi_rst_n_i  (axi_rst_n_r),
        .m_awid_o     (awid_w),
        .m_awaddr_o   (awaddr_w),
        .m_awlen_o    (awlen_w),
        .m_awsize_o   (awsize_w),
        .m_awburst_o  (awburst_w),
        .m_awqos_o    (awqos_w),
        .m_awvalid_o  (awvalid_w),
        .m_awready_i  (awready_w),
        .m_wdata_o    (wdata_w),
        .m_wstrb_o    (wstrb_w),
        .m_wlast_o    (wlast_w),
        .m_wvalid_o   (wvalid_w),
        .m_wready_i   (wready_w),
        .m_bid_i      (bid_w),
        .m_bresp_i    (bresp_w),
        .m_bvalid_i   (bvalid_w),
        .m_bready_o   (bready_w),
        .m_arid_o     (arid_w),
        .m_araddr_o   (araddr_w),
        .m_arlen_o    (arlen_w),
        .m_arsize_o   (arsize_w),
        .m_arburst_o  (arburst_w),
        .m_arqos_o    (arqos_w),
        .m_arvalid_o  (arvalid_w),
        .m_arready_i  (arready_w),
        .m_rid_i      (rid_w),
        .m_rdata_i    (rdata_w),
        .m_rresp_i    (rresp_w),
        .m_rlast_i    (rlast_w),
        .m_rvalid_i   (rvalid_w),
        .m_rready_o   (rready_w)
    );

    assign awready_w = mem_awready_w & aw_allow_w;
    assign wready_w  = mem_wready_w & w_allow_w;
    assign bid_w     = mem_bid_w;
    assign bresp_w   = mem_bresp_w;
    assign bvalid_w  = mem_bvalid_w & b_allow_w;
    assign arready_w = mem_arready_w & ar_allow_w;
    assign rid_w     = mem_rid_w;
    assign rdata_w   = mem_rdata_w;
    assign rresp_w   = mem_rresp_w;
    assign rlast_w   = mem_rlast_w;
    assign rvalid_w  = mem_rvalid_w & r_allow_w;

    axi256_mem_model #(
        .ID_W (4),
        .WORDS (4096)
    ) u_memory (
        .clk_i      (axi_clk_r),
        .rst_n_i    (axi_rst_n_r),
        .awid_i     (awid_w),
        .awaddr_i   (awaddr_w),
        .awlen_i    (awlen_w),
        .awsize_i   (awsize_w),
        .awburst_i  (awburst_w),
        .awvalid_i  (awvalid_w & aw_allow_w),
        .awready_o  (mem_awready_w),
        .wdata_i    (wdata_w),
        .wstrb_i    (wstrb_w),
        .wlast_i    (wlast_w),
        .wvalid_i   (wvalid_w & w_allow_w),
        .wready_o   (mem_wready_w),
        .bid_o      (mem_bid_w),
        .bresp_o    (mem_bresp_w),
        .bvalid_o   (mem_bvalid_w),
        .bready_i   (bready_w & b_allow_w),
        .arid_i     (arid_w),
        .araddr_i   (araddr_w),
        .arlen_i    (arlen_w),
        .arsize_i   (arsize_w),
        .arburst_i  (arburst_w),
        .arvalid_i  (arvalid_w & ar_allow_w),
        .arready_o  (mem_arready_w),
        .rid_o      (mem_rid_w),
        .rdata_o    (mem_rdata_w),
        .rresp_o    (mem_rresp_w),
        .rlast_o    (mem_rlast_w),
        .rvalid_o   (mem_rvalid_w),
        .rready_i   (rready_w & r_allow_w)
    );

    always @(posedge axi_clk_r or negedge axi_rst_n_r) begin
        if (!axi_rst_n_r) begin
            axi_cycle_r <= 0;
        end else begin
            axi_cycle_r <= axi_cycle_r + 1;
            if (awvalid_w && awready_w) begin
                aw_count_r <= aw_count_r + 1;
                check_true(awaddr_w[4:0] == 5'b0,
                           "AW address was not 32-byte aligned");
                check_true(({1'b0, awaddr_w[11:0]} +
                            (({5'b0, awlen_w} + 13'd1) << 5)) <= 13'd4096,
                           "AW burst crossed a 4-KiB boundary");
                check_true(awlen_w <= 8'd15,
                           "AW burst exceeded the 16-beat DDR profile");
            end
            if (arvalid_w && arready_w) begin
                ar_count_r <= ar_count_r + 1;
                check_true(araddr_w[4:0] == 5'b0,
                           "AR address was not 32-byte aligned");
                check_true(({1'b0, araddr_w[11:0]} +
                            (({5'b0, arlen_w} + 13'd1) << 5)) <= 13'd4096,
                           "AR burst crossed a 4-KiB boundary");
                check_true(arlen_w <= 8'd15,
                           "AR burst exceeded the 16-beat DDR profile");
            end
        end
    end

    initial begin
        apb_clk_r = 1'b0;
        axi_clk_r = 1'b0;
        apb_rst_n_r = 1'b0;
        axi_rst_n_r = 1'b0;
        paddr_r = 32'b0;
        psel_r = 1'b0;
        penable_r = 1'b0;
        pwrite_r = 1'b0;
        pwdata_r = 32'b0;
        pstrb_r = 4'b0;
        axi_cycle_r = 0;
        aw_count_r = 0;
        ar_count_r = 0;
        checks_r = 0;
        failures_r = 0;
        status_r = 32'b0;
        value_r = 32'b0;

        // APB can leave reset before the AXI domain. No command is allowed to
        // be lost when the destination pointer synchronizers start later.
        #21 apb_rst_n_r = 1'b1;
        #36 axi_rst_n_r = 1'b1;
        repeat (8) @(posedge apb_clk_r);

        apb_read(`DDR_MON_ID, value_r);
        check_true(value_r == 32'h4444_524d, "monitor ID mismatch");

        // Start one beat before a 4-KiB boundary. The programmed 256-beat
        // preference is capped to the DDR profile, so 130 beats become
        // 1 + eight 16-beat + 1 transactions in each write/read phase.
        apb_write(`DDR_MON_MODE, `DDR_MON_MODE_WRITE_READ);
        apb_write(`DDR_MON_BASE_ADDR, 32'h0000_0fe0);
        apb_write(`DDR_MON_TOTAL_BEATS, 32'd130);
        apb_write(`DDR_MON_BURST_LEN, 32'h0000_00ff);
        apb_write(`DDR_MON_PATTERN_SEED, 32'h1357_9bdf);
        apb_write(`DDR_MON_LOOP_COUNT, 32'd2);
        apb_write(`DDR_MON_CONTROL, 32'h0000_0001);
        wait_done();

        check_true(!status_r[`DDR_MON_STATUS_ERROR],
                   "write/read test unexpectedly reported an error");
        apb_read(`DDR_MON_TOTAL_CYCLES, total_cycles_r);
        apb_read(`DDR_MON_WRITE_BEATS, write_beats_r);
        apb_read(`DDR_MON_READ_BEATS, read_beats_r);
        apb_read(`DDR_MON_ERROR_COUNT, error_count_r);
        check_true(write_beats_r == 32'd260,
                   "write beat metric did not cross APB CDC correctly");
        check_true(read_beats_r == 32'd260,
                   "read beat metric did not cross APB CDC correctly");
        check_true(total_cycles_r > 32'd520,
                   "total cycle metric did not include stalls/control");
        check_true(error_count_r == 32'b0,
                   "clean write/read result has a nonzero error count");
        check_true(aw_count_r == 20 && ar_count_r == 20,
                   "16-beat/4-KiB transaction count mismatch");

        // Corrupt one 32-bit lane and run read-verify only. The failure record
        // must cross from the AXI domain back into APB without tearing.
        u_memory.store[128][31:0] =
            u_memory.store[128][31:0] ^ 32'h0000_0001;
        apb_write(`DDR_MON_CONTROL, 32'h0000_0002);
        apb_write(`DDR_MON_MODE, `DDR_MON_MODE_READ_VERIFY);
        apb_write(`DDR_MON_LOOP_COUNT, 32'd1);
        apb_write(`DDR_MON_CONTROL, 32'h0000_0001);
        wait_done();

        check_true(status_r[`DDR_MON_STATUS_ERROR],
                   "injected data error did not set STATUS.ERROR");
        apb_read(`DDR_MON_ERROR_COUNT, error_count_r);
        apb_read(`DDR_MON_FIRST_ERROR_ADDR, first_error_addr_r);
        check_true(error_count_r == 32'd1,
                   "injected data error count was not exactly one");
        check_true(first_error_addr_r == 32'h0000_1000,
                   "first error address was torn or incorrect");
        check_true(aw_count_r == 20 && ar_count_r == 30,
                   "read-only rerun burst count mismatch");

        if (failures_r == 0)
            $display("DDR_MONITOR_CDC_PASS checks=%0d aw=%0d ar=%0d cycles=%0d",
                     checks_r, aw_count_r, ar_count_r, total_cycles_r);
        else
            $fatal(1, "DDR_MONITOR_CDC_FAIL checks=%0d failures=%0d",
                   checks_r, failures_r);
        $finish;
    end

    initial begin
        #2000000;
        $fatal(1, "DDR_MONITOR_CDC_TIMEOUT");
    end

endmodule
