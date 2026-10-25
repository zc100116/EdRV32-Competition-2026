// ============================================================================
// File        : tb_axi_async_bridge_cdc.sv
// Description : Five-channel AXI CDC bridge test with unrelated clocks,
//               staggered resets and independent channel backpressure.
// ============================================================================

`timescale 1ns/1ps

module tb_axi_async_bridge_cdc;

    reg s_clk_r;
    reg m_clk_r;
    reg s_rst_n_r;
    reg m_rst_n_r;

    wire [3:0] s_awid_w;
    wire [31:0] s_awaddr_w;
    wire [7:0] s_awlen_w;
    wire [2:0] s_awsize_w;
    wire [1:0] s_awburst_w;
    wire [3:0] s_awqos_w;
    wire s_awvalid_w;
    wire s_awready_w;
    wire [255:0] s_wdata_w;
    wire [31:0] s_wstrb_w;
    wire s_wlast_w;
    wire s_wvalid_w;
    wire s_wready_w;
    wire [3:0] s_bid_w;
    wire [1:0] s_bresp_w;
    wire s_bvalid_w;
    wire s_bready_w;
    wire [3:0] s_arid_w;
    wire [31:0] s_araddr_w;
    wire [7:0] s_arlen_w;
    wire [2:0] s_arsize_w;
    wire [1:0] s_arburst_w;
    wire [3:0] s_arqos_w;
    wire s_arvalid_w;
    wire s_arready_w;
    wire [3:0] s_rid_w;
    wire [255:0] s_rdata_w;
    wire [1:0] s_rresp_w;
    wire s_rlast_w;
    wire s_rvalid_w;
    wire s_rready_w;

    wire [3:0] m_awid_w;
    wire [31:0] m_awaddr_w;
    wire [7:0] m_awlen_w;
    wire [2:0] m_awsize_w;
    wire [1:0] m_awburst_w;
    wire [3:0] m_awqos_w;
    wire m_awvalid_w;
    wire m_awready_w;
    wire [255:0] m_wdata_w;
    wire [31:0] m_wstrb_w;
    wire m_wlast_w;
    wire m_wvalid_w;
    wire m_wready_w;
    wire [3:0] m_bid_w;
    wire [1:0] m_bresp_w;
    wire m_bvalid_w;
    wire m_bready_w;
    wire [3:0] m_arid_w;
    wire [31:0] m_araddr_w;
    wire [7:0] m_arlen_w;
    wire [2:0] m_arsize_w;
    wire [1:0] m_arburst_w;
    wire [3:0] m_arqos_w;
    wire m_arvalid_w;
    wire m_arready_w;
    wire [3:0] m_rid_w;
    wire [255:0] m_rdata_w;
    wire [1:0] m_rresp_w;
    wire m_rlast_w;
    wire m_rvalid_w;
    wire m_rready_w;

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

    integer m_cycle_r;
    integer aw_count_r;
    integer w_count_r;
    integer b_count_r;
    integer ar_count_r;
    integer r_count_r;
    integer source_w_stalls_r;
    integer return_r_stalls_r;

    wire aw_allow_w = (m_cycle_r % 5) != 1;
    wire w_allow_w  = (m_cycle_r % 4) == 0;
    wire b_allow_w  = (m_cycle_r % 6) != 2;
    wire ar_allow_w = (m_cycle_r % 5) != 3;
    wire r_allow_w  = (m_cycle_r % 3) != 1;

    always #6.25 s_clk_r = ~s_clk_r;
    always #4.0 m_clk_r = ~m_clk_r;

    axi256_master_bfm #(
        .ID_W (4),
        .TAG  (32'h4344_4301)
    ) u_master (
        .clk_i       (s_clk_r),
        .rst_n_i     (s_rst_n_r),
        .awid_o      (s_awid_w),
        .awaddr_o    (s_awaddr_w),
        .awlen_o     (s_awlen_w),
        .awsize_o    (s_awsize_w),
        .awburst_o   (s_awburst_w),
        .awqos_o     (s_awqos_w),
        .awvalid_o   (s_awvalid_w),
        .awready_i   (s_awready_w),
        .wdata_o     (s_wdata_w),
        .wstrb_o     (s_wstrb_w),
        .wlast_o     (s_wlast_w),
        .wvalid_o    (s_wvalid_w),
        .wready_i    (s_wready_w),
        .bid_i       (s_bid_w),
        .bresp_i     (s_bresp_w),
        .bvalid_i    (s_bvalid_w),
        .bready_o    (s_bready_w),
        .arid_o      (s_arid_w),
        .araddr_o    (s_araddr_w),
        .arlen_o     (s_arlen_w),
        .arsize_o    (s_arsize_w),
        .arburst_o   (s_arburst_w),
        .arqos_o     (s_arqos_w),
        .arvalid_o   (s_arvalid_w),
        .arready_i   (s_arready_w),
        .rid_i       (s_rid_w),
        .rdata_i     (s_rdata_w),
        .rresp_i     (s_rresp_w),
        .rlast_i     (s_rlast_w),
        .rvalid_i    (s_rvalid_w),
        .rready_o    (s_rready_w)
    );

    edrv32_axi_async_bridge dut (
        .s_clk_i      (s_clk_r),
        .s_rst_n_i    (s_rst_n_r),
        .m_clk_i      (m_clk_r),
        .m_rst_n_i    (m_rst_n_r),
        .s_awid_i     (s_awid_w),
        .s_awaddr_i   (s_awaddr_w),
        .s_awlen_i    (s_awlen_w),
        .s_awsize_i   (s_awsize_w),
        .s_awburst_i  (s_awburst_w),
        .s_awqos_i    (s_awqos_w),
        .s_awvalid_i  (s_awvalid_w),
        .s_awready_o  (s_awready_w),
        .s_wdata_i    (s_wdata_w),
        .s_wstrb_i    (s_wstrb_w),
        .s_wlast_i    (s_wlast_w),
        .s_wvalid_i   (s_wvalid_w),
        .s_wready_o   (s_wready_w),
        .s_bid_o      (s_bid_w),
        .s_bresp_o    (s_bresp_w),
        .s_bvalid_o   (s_bvalid_w),
        .s_bready_i   (s_bready_w),
        .s_arid_i     (s_arid_w),
        .s_araddr_i   (s_araddr_w),
        .s_arlen_i    (s_arlen_w),
        .s_arsize_i   (s_arsize_w),
        .s_arburst_i  (s_arburst_w),
        .s_arqos_i    (s_arqos_w),
        .s_arvalid_i  (s_arvalid_w),
        .s_arready_o  (s_arready_w),
        .s_rid_o      (s_rid_w),
        .s_rdata_o    (s_rdata_w),
        .s_rresp_o    (s_rresp_w),
        .s_rlast_o    (s_rlast_w),
        .s_rvalid_o   (s_rvalid_w),
        .s_rready_i   (s_rready_w),
        .m_awid_o     (m_awid_w),
        .m_awaddr_o   (m_awaddr_w),
        .m_awlen_o    (m_awlen_w),
        .m_awsize_o   (m_awsize_w),
        .m_awburst_o  (m_awburst_w),
        .m_awqos_o    (m_awqos_w),
        .m_awvalid_o  (m_awvalid_w),
        .m_awready_i  (m_awready_w),
        .m_wdata_o    (m_wdata_w),
        .m_wstrb_o    (m_wstrb_w),
        .m_wlast_o    (m_wlast_w),
        .m_wvalid_o   (m_wvalid_w),
        .m_wready_i   (m_wready_w),
        .m_bid_i      (m_bid_w),
        .m_bresp_i    (m_bresp_w),
        .m_bvalid_i   (m_bvalid_w),
        .m_bready_o   (m_bready_w),
        .m_arid_o     (m_arid_w),
        .m_araddr_o   (m_araddr_w),
        .m_arlen_o    (m_arlen_w),
        .m_arsize_o   (m_arsize_w),
        .m_arburst_o  (m_arburst_w),
        .m_arqos_o    (m_arqos_w),
        .m_arvalid_o  (m_arvalid_w),
        .m_arready_i  (m_arready_w),
        .m_rid_i      (m_rid_w),
        .m_rdata_i    (m_rdata_w),
        .m_rresp_i    (m_rresp_w),
        .m_rlast_i    (m_rlast_w),
        .m_rvalid_i   (m_rvalid_w),
        .m_rready_o   (m_rready_w)
    );

    assign m_awready_w = mem_awready_w & aw_allow_w;
    assign m_wready_w  = mem_wready_w & w_allow_w;
    assign m_bid_w     = mem_bid_w;
    assign m_bresp_w   = mem_bresp_w;
    assign m_bvalid_w  = mem_bvalid_w & b_allow_w;
    assign m_arready_w = mem_arready_w & ar_allow_w;
    assign m_rid_w     = mem_rid_w;
    assign m_rdata_w   = mem_rdata_w;
    assign m_rresp_w   = mem_rresp_w;
    assign m_rlast_w   = mem_rlast_w;
    assign m_rvalid_w  = mem_rvalid_w & r_allow_w;

    axi256_mem_model #(
        .ID_W (4),
        .WORDS (4096)
    ) u_memory (
        .clk_i      (m_clk_r),
        .rst_n_i    (m_rst_n_r),
        .awid_i     (m_awid_w),
        .awaddr_i   (m_awaddr_w),
        .awlen_i    (m_awlen_w),
        .awsize_i   (m_awsize_w),
        .awburst_i  (m_awburst_w),
        .awvalid_i  (m_awvalid_w & aw_allow_w),
        .awready_o  (mem_awready_w),
        .wdata_i    (m_wdata_w),
        .wstrb_i    (m_wstrb_w),
        .wlast_i    (m_wlast_w),
        .wvalid_i   (m_wvalid_w & w_allow_w),
        .wready_o   (mem_wready_w),
        .bid_o      (mem_bid_w),
        .bresp_o    (mem_bresp_w),
        .bvalid_o   (mem_bvalid_w),
        .bready_i   (m_bready_w & b_allow_w),
        .arid_i     (m_arid_w),
        .araddr_i   (m_araddr_w),
        .arlen_i    (m_arlen_w),
        .arsize_i   (m_arsize_w),
        .arburst_i  (m_arburst_w),
        .arvalid_i  (m_arvalid_w & ar_allow_w),
        .arready_o  (mem_arready_w),
        .rid_o      (mem_rid_w),
        .rdata_o    (mem_rdata_w),
        .rresp_o    (mem_rresp_w),
        .rlast_o    (mem_rlast_w),
        .rvalid_o   (mem_rvalid_w),
        .rready_i   (m_rready_w & r_allow_w)
    );

    always @(posedge m_clk_r or negedge m_rst_n_r) begin
        if (!m_rst_n_r) begin
            m_cycle_r <= 0;
        end else begin
            m_cycle_r <= m_cycle_r + 1;
            if (m_awvalid_w && m_awready_w)
                aw_count_r <= aw_count_r + 1;
            if (m_wvalid_w && m_wready_w)
                w_count_r <= w_count_r + 1;
            if (m_bvalid_w && m_bready_w)
                b_count_r <= b_count_r + 1;
            if (m_arvalid_w && m_arready_w)
                ar_count_r <= ar_count_r + 1;
            if (m_rvalid_w && m_rready_w)
                r_count_r <= r_count_r + 1;
            if (mem_rvalid_w && !(m_rready_w && r_allow_w))
                return_r_stalls_r <= return_r_stalls_r + 1;
        end
    end

    always @(posedge s_clk_r) begin
        if (s_rst_n_r && s_wvalid_w && !s_wready_w)
            source_w_stalls_r <= source_w_stalls_r + 1;
    end

    initial begin
        s_clk_r = 1'b0;
        m_clk_r = 1'b0;
        s_rst_n_r = 1'b0;
        m_rst_n_r = 1'b0;
        m_cycle_r = 0;
        aw_count_r = 0;
        w_count_r = 0;
        b_count_r = 0;
        ar_count_r = 0;
        r_count_r = 0;
        source_w_stalls_r = 0;
        return_r_stalls_r = 0;

        #23 s_rst_n_r = 1'b1;
        #38 m_rst_n_r = 1'b1;
        repeat (8) @(posedge s_clk_r);

        u_master.write_burst(32'h0000_0000, 4'h1, 1,
                             32'h1111_0001);
        u_master.read_check(32'h0000_0000, 4'h1, 1,
                            32'h1111_0001);

        u_master.write_burst(32'h0000_1000, 4'h5, 37,
                             32'h2222_0002);
        u_master.read_check(32'h0000_1000, 4'h5, 37,
                            32'h2222_0002);

        // Reset is asserted only at an idle boundary. Both directions use
        // different deassertion times to exercise pointer synchronizers.
        #3 s_rst_n_r = 1'b0;
        m_rst_n_r = 1'b0;
        #29 m_rst_n_r = 1'b1;
        #41 s_rst_n_r = 1'b1;
        repeat (8) @(posedge s_clk_r);

        u_master.write_burst(32'h0000_4000, 4'ha, 64,
                             32'h3333_0003);
        u_master.read_check(32'h0000_4000, 4'ha, 64,
                            32'h3333_0003);

        repeat (12) @(posedge s_clk_r);
        if (aw_count_r != 3 || w_count_r != 102 || b_count_r != 3 ||
            ar_count_r != 3 || r_count_r != 102)
            $fatal(1,
                   "AXI_ASYNC_BRIDGE_CDC_COUNT_FAIL aw=%0d w=%0d b=%0d ar=%0d r=%0d",
                   aw_count_r, w_count_r, b_count_r, ar_count_r, r_count_r);
        if (source_w_stalls_r == 0 || return_r_stalls_r == 0)
            $fatal(1,
                   "AXI_ASYNC_BRIDGE_CDC_BACKPRESSURE_FAIL sw=%0d rr=%0d",
                   source_w_stalls_r, return_r_stalls_r);

        $display("AXI_ASYNC_BRIDGE_CDC_PASS aw=%0d w=%0d b=%0d ar=%0d r=%0d sw_stall=%0d rr_stall=%0d",
                 aw_count_r, w_count_r, b_count_r, ar_count_r, r_count_r,
                 source_w_stalls_r, return_r_stalls_r);
        $finish;
    end

    initial begin
        #1000000;
        $fatal(1, "AXI_ASYNC_BRIDGE_CDC_TIMEOUT");
    end

endmodule
