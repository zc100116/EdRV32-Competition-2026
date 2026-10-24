`timescale 1ns/1ps
`include "edrv32_axi4.vh"

module tb_axi_single_outstanding_write_route;
    localparam NUM_M = 2;
    localparam NUM_S = 3;
    localparam GID_W = `AXI_ID_W + 1;

    reg clk;
    reg rst_n;
    integer checks;

    reg  [NUM_M*`AXI_ID_W-1:0] m_awid;
    reg  [NUM_M*32-1:0] m_awaddr;
    reg  [NUM_M*`AXI_LEN_W-1:0] m_awlen;
    reg  [NUM_M*`AXI_SIZE_W-1:0] m_awsize;
    reg  [NUM_M*`AXI_BURST_W-1:0] m_awburst;
    reg  [NUM_M-1:0] m_awvalid;
    wire [NUM_M-1:0] m_awready;
    reg  [NUM_M*`AXI_DATA_W-1:0] m_wdata;
    reg  [NUM_M*`AXI_STRB_W-1:0] m_wstrb;
    reg  [NUM_M-1:0] m_wlast;
    reg  [NUM_M-1:0] m_wvalid;
    wire [NUM_M-1:0] m_wready;
    wire [NUM_M*`AXI_ID_W-1:0] m_bid;
    wire [NUM_M*`AXI_RESP_W-1:0] m_bresp;
    wire [NUM_M-1:0] m_bvalid;
    reg  [NUM_M-1:0] m_bready;

    reg  [NUM_S*32-1:0] s_base;
    reg  [NUM_S*32-1:0] s_limit;
    reg  [NUM_M*NUM_S-1:0] write_connect;
    wire [NUM_S*GID_W-1:0] s_awid;
    wire [NUM_S*32-1:0] s_awaddr;
    wire [NUM_S*`AXI_LEN_W-1:0] s_awlen;
    wire [NUM_S*`AXI_SIZE_W-1:0] s_awsize;
    wire [NUM_S*`AXI_BURST_W-1:0] s_awburst;
    wire [NUM_S-1:0] s_awvalid;
    reg  [NUM_S-1:0] s_awready;
    wire [NUM_S*`AXI_DATA_W-1:0] s_wdata;
    wire [NUM_S*`AXI_STRB_W-1:0] s_wstrb;
    wire [NUM_S-1:0] s_wlast;
    wire [NUM_S-1:0] s_wvalid;
    reg  [NUM_S-1:0] s_wready;
    reg  [NUM_S*GID_W-1:0] s_bid;
    reg  [NUM_S*`AXI_RESP_W-1:0] s_bresp;
    reg  [NUM_S-1:0] s_bvalid;
    wire [NUM_S-1:0] s_bready;

    wire [NUM_M-1:0] fs_wr_fail;
    wire [NUM_M*32-1:0] fs_wr_addr;
    wire [NUM_M*`AXI_ID_W-1:0] fs_wr_id;
    wire [NUM_M*32-1:0] mon_wr_beats;
    wire [NUM_M*32-1:0] mon_wr_bursts;
    wire [NUM_M*32-1:0] mon_wr_err;
    wire [NUM_M*32-1:0] mon_wr_maxwait;

    initial clk = 1'b0;
    always #5 clk = ~clk;

    task automatic check_true;
        input condition;
        input [8*112-1:0] message;
        begin
            checks = checks + 1;
            if (!condition) begin
                $display("FAIL: %0s", message);
                $fatal(1);
            end
        end
    endtask

    task automatic issue_aw_m0;
        input [31:0] address;
        input [`AXI_ID_W-1:0] id;
        input [`AXI_LEN_W-1:0] len;
        begin
            m_awaddr[0 +: 32] = address;
            m_awid[0 +: `AXI_ID_W] = id;
            m_awlen[0 +: `AXI_LEN_W] = len;
            m_awvalid[0] = 1'b1;
            @(posedge clk);
            while (!m_awready[0]) @(posedge clk);
            #1;
            m_awvalid[0] = 1'b0;
        end
    endtask

    axi_wr_fabric #(
        .NUM_M(NUM_M), .NUM_S(NUM_S), .ADDR_W(32),
        .DATA_W(`AXI_DATA_W), .STRB_W(`AXI_STRB_W),
        .ID_W(`AXI_ID_W), .LEN_W(`AXI_LEN_W),
        .SIZE_W(`AXI_SIZE_W), .BURST_W(`AXI_BURST_W),
        .RESP_W(`AXI_RESP_W), .GID_W(GID_W),
        .M_MAX_OUTSTANDING(1), .S_MAX_WR(1),
        .WR_TIMEOUT_CYCLES(0), .AXI_MON_ENABLE(1)
    ) dut (
        .clk(clk), .rst_n(rst_n),
        .m_awid_i(m_awid), .m_awaddr_i(m_awaddr),
        .m_awlen_i(m_awlen), .m_awsize_i(m_awsize),
        .m_awburst_i(m_awburst), .m_awvalid_i(m_awvalid),
        .m_awready_o(m_awready), .m_wdata_i(m_wdata),
        .m_wstrb_i(m_wstrb), .m_wlast_i(m_wlast),
        .m_wvalid_i(m_wvalid), .m_wready_o(m_wready),
        .m_bid_o(m_bid), .m_bresp_o(m_bresp),
        .m_bvalid_o(m_bvalid), .m_bready_i(m_bready),
        .s_base_i(s_base), .s_limit_i(s_limit),
        .m_write_connect_i(write_connect),
        .s_awid_o(s_awid), .s_awaddr_o(s_awaddr),
        .s_awlen_o(s_awlen), .s_awsize_o(s_awsize),
        .s_awburst_o(s_awburst), .s_awvalid_o(s_awvalid),
        .s_awready_i(s_awready), .s_wdata_o(s_wdata),
        .s_wstrb_o(s_wstrb), .s_wlast_o(s_wlast),
        .s_wvalid_o(s_wvalid), .s_wready_i(s_wready),
        .s_bid_i(s_bid), .s_bresp_i(s_bresp),
        .s_bvalid_i(s_bvalid), .s_bready_o(s_bready),
        .fs_wr_fail_o(fs_wr_fail), .fs_wr_addr_o(fs_wr_addr),
        .fs_wr_id_o(fs_wr_id), .mon_wr_beats_o(mon_wr_beats),
        .mon_wr_bursts_o(mon_wr_bursts), .mon_wr_err_o(mon_wr_err),
        .mon_wr_maxwait_o(mon_wr_maxwait)
    );

    initial begin
        checks = 0;
        rst_n = 1'b0;
        m_awid = 0; m_awaddr = 0; m_awlen = 0;
        m_awsize = {NUM_M{`AXI_SIZE_8B}};
        m_awburst = {NUM_M{`AXI_BURST_INCR}};
        m_awvalid = 0; m_wdata = 0;
        m_wstrb = {NUM_M*`AXI_STRB_W{1'b1}};
        m_wlast = 0; m_wvalid = 0; m_bready = 2'b11;
        s_base = {32'h0000_3000, 32'h0000_2000, 32'h0000_1000};
        s_limit = {32'h0000_4000, 32'h0000_3000, 32'h0000_2000};
        write_connect = {3'b111, 3'b011};
        s_awready = 3'b111; s_wready = 3'b111;
        s_bid = 0; s_bresp = 0; s_bvalid = 0;
        repeat (3) @(posedge clk);
        rst_n = 1'b1;
        @(posedge clk); #1;

        // Two masters accept AWs to independent slaves concurrently.
        m_awaddr[0 +: 32] = 32'h0000_1000;
        m_awid[0 +: `AXI_ID_W] = 4'h1;
        m_awaddr[32 +: 32] = 32'h0000_3000;
        m_awid[`AXI_ID_W +: `AXI_ID_W] = 4'h2;
        m_awvalid = 2'b11;
        #1;
        check_true(m_awready == 2'b11 && s_awvalid[0] && s_awvalid[2],
                   "independent AW requests accept together");
        @(posedge clk); #1;
        m_awvalid = 0;
        m_wdata[0 +: `AXI_DATA_W] = 64'h1111;
        m_wdata[`AXI_DATA_W +: `AXI_DATA_W] = 64'h2222;
        m_wlast = 2'b11; m_wvalid = 2'b11;
        #1;
        check_true(m_wready == 2'b11 && s_wvalid[0] && s_wvalid[2],
                   "W beats follow their accepted AW owners");
        @(posedge clk); #1;
        m_wvalid = 0; m_wlast = 0;

        // Wrong slave with matching BID prefix cannot steal M0 response.
        s_bid[GID_W +: GID_W] = {1'b0, 4'h1};
        s_bvalid[1] = 1'b1;
        #1;
        check_true(!m_bvalid[0] && !s_bready[1],
                   "unowned B response is isolated");
        s_bvalid[1] = 1'b0;

        s_bid[0 +: GID_W] = {1'b0, 4'h1};
        s_bresp[0 +: `AXI_RESP_W] = `AXI_RESP_OKAY;
        s_bvalid[0] = 1'b1;
        s_bid[2*GID_W +: GID_W] = {1'b1, 4'h2};
        s_bresp[2*`AXI_RESP_W +: `AXI_RESP_W] = `AXI_RESP_SLVERR;
        s_bvalid[2] = 1'b1;
        #1;
        check_true(m_bvalid == 2'b11 && s_bready[0] && s_bready[2],
                   "recorded B owners return concurrently");
        check_true(m_bid[0 +: `AXI_ID_W] == 4'h1 &&
                   m_bresp[0 +: `AXI_RESP_W] == `AXI_RESP_OKAY,
                   "master zero receives slave zero B payload");
        check_true(m_bid[`AXI_ID_W +: `AXI_ID_W] == 4'h2 &&
                   m_bresp[`AXI_RESP_W +: `AXI_RESP_W] == `AXI_RESP_SLVERR,
                   "master one receives slave two B payload");
        @(posedge clk); #1;
        s_bvalid = 0; s_bresp = 0;

        // BID mismatch is fail-stop until the selected slave corrects it.
        issue_aw_m0(32'h0000_1008, 4'h3, 8'd0);
        m_wlast[0] = 1'b1; m_wvalid[0] = 1'b1;
        @(posedge clk); #1;
        m_wvalid[0] = 1'b0; m_wlast[0] = 1'b0;
        s_bid[0 +: GID_W] = {1'b0, 4'h4};
        s_bvalid[0] = 1'b1;
        #1;
        check_true(!m_bvalid[0] && !s_bready[0],
                   "mismatched BID is not delivered");
        s_bid[0 +: GID_W] = {1'b0, 4'h3};
        #1;
        check_true(m_bvalid[0] && s_bready[0],
                   "corrected BID completes transaction");
        @(posedge clk); #1;
        s_bvalid[0] = 1'b0;

        // Disconnected AW stays local, drains W, then produces DECERR B.
        issue_aw_m0(32'h0000_3000, 4'h6, 8'd0);
        check_true(!s_awvalid[2], "disconnected AW never reaches slave two");
        m_wdata[0 +: `AXI_DATA_W] = 64'hfeed_face;
        m_wlast[0] = 1'b1; m_wvalid[0] = 1'b1;
        #1;
        check_true(m_wready[0] && !s_wvalid[2],
                   "DECERR write drains W locally");
        @(posedge clk); #1;
        m_wvalid[0] = 1'b0; m_wlast[0] = 1'b0;
        #1;
        check_true(m_bvalid[0] &&
                   m_bresp[0 +: `AXI_RESP_W] == `AXI_RESP_DECERR &&
                   m_bid[0 +: `AXI_ID_W] == 4'h6,
                   "drained disconnected write returns DECERR");
        @(posedge clk); #1;

        check_true(mon_wr_bursts[0 +: 32] == 32'd3 &&
                   mon_wr_bursts[32 +: 32] == 32'd1 &&
                   mon_wr_err[0 +: 32] == 32'd1 &&
                   mon_wr_err[32 +: 32] == 32'd1 &&
                   !fs_wr_fail[0] && !fs_wr_fail[1],
                   "write monitors and fail-stop status stay coherent");
        $display("PASS: AXI single-outstanding recorded B routing (%0d checks)", checks);
        $finish;
    end
endmodule
