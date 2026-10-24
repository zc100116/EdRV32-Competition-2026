`timescale 1ns/1ps
`include "edrv32_axi4.vh"

module tb_axi_single_outstanding_route;
    localparam NUM_M = 2;
    localparam NUM_S = 3;
    localparam GID_W = `AXI_ID_W + 1;

    reg clk;
    reg rst_n;
    integer checks;

    reg  [NUM_M*`AXI_ID_W-1:0] m_arid;
    reg  [NUM_M*32-1:0] m_araddr;
    reg  [NUM_M*`AXI_LEN_W-1:0] m_arlen;
    reg  [NUM_M*`AXI_SIZE_W-1:0] m_arsize;
    reg  [NUM_M*`AXI_BURST_W-1:0] m_arburst;
    reg  [NUM_M-1:0] m_arvalid;
    wire [NUM_M-1:0] m_arready;
    wire [NUM_M*`AXI_ID_W-1:0] m_rid;
    wire [NUM_M*`AXI_DATA_W-1:0] m_rdata;
    wire [NUM_M*`AXI_RESP_W-1:0] m_rresp;
    wire [NUM_M-1:0] m_rlast;
    wire [NUM_M-1:0] m_rvalid;
    reg  [NUM_M-1:0] m_rready;

    reg  [NUM_S*32-1:0] s_base;
    reg  [NUM_S*32-1:0] s_limit;
    reg  [NUM_M*NUM_S-1:0] read_connect;
    wire [NUM_S*GID_W-1:0] s_arid;
    wire [NUM_S*32-1:0] s_araddr;
    wire [NUM_S*`AXI_LEN_W-1:0] s_arlen;
    wire [NUM_S*`AXI_SIZE_W-1:0] s_arsize;
    wire [NUM_S*`AXI_BURST_W-1:0] s_arburst;
    wire [NUM_S-1:0] s_arvalid;
    reg  [NUM_S-1:0] s_arready;
    reg  [NUM_S*GID_W-1:0] s_rid;
    reg  [NUM_S*`AXI_DATA_W-1:0] s_rdata;
    reg  [NUM_S*`AXI_RESP_W-1:0] s_rresp;
    reg  [NUM_S-1:0] s_rlast;
    reg  [NUM_S-1:0] s_rvalid;
    wire [NUM_S-1:0] s_rready;

    wire [NUM_M-1:0] fs_rd_fail;
    wire [NUM_M*32-1:0] fs_rd_addr;
    wire [NUM_M*`AXI_ID_W-1:0] fs_rd_id;
    wire [NUM_M*32-1:0] mon_rd_beats;
    wire [NUM_M*32-1:0] mon_rd_bursts;
    wire [NUM_M*32-1:0] mon_rd_err;
    wire [NUM_M*32-1:0] mon_rd_maxwait;

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

    task automatic issue_m0;
        input [31:0] address;
        input [`AXI_ID_W-1:0] id;
        input [`AXI_LEN_W-1:0] len;
        begin
            m_araddr[0 +: 32] = address;
            m_arid[0 +: `AXI_ID_W] = id;
            m_arlen[0 +: `AXI_LEN_W] = len;
            m_arvalid[0] = 1'b1;
            @(posedge clk);
            while (!m_arready[0]) @(posedge clk);
            #1;
            m_arvalid[0] = 1'b0;
        end
    endtask

    axi_rd_fabric #(
        .NUM_M(NUM_M), .NUM_S(NUM_S), .ADDR_W(32),
        .DATA_W(`AXI_DATA_W), .ID_W(`AXI_ID_W),
        .LEN_W(`AXI_LEN_W), .SIZE_W(`AXI_SIZE_W),
        .BURST_W(`AXI_BURST_W), .RESP_W(`AXI_RESP_W),
        .GID_W(GID_W), .M_MAX_OUTSTANDING(1),
        .RD_TIMEOUT_CYCLES(0), .AXI_MON_ENABLE(1)
    ) dut (
        .clk(clk), .rst_n(rst_n),
        .m_arid_i(m_arid), .m_araddr_i(m_araddr),
        .m_arlen_i(m_arlen), .m_arsize_i(m_arsize),
        .m_arburst_i(m_arburst), .m_arvalid_i(m_arvalid),
        .m_arready_o(m_arready), .m_rid_o(m_rid),
        .m_rdata_o(m_rdata), .m_rresp_o(m_rresp),
        .m_rlast_o(m_rlast), .m_rvalid_o(m_rvalid),
        .m_rready_i(m_rready),
        .s_base_i(s_base), .s_limit_i(s_limit),
        .m_read_connect_i(read_connect),
        .s_arid_o(s_arid), .s_araddr_o(s_araddr),
        .s_arlen_o(s_arlen), .s_arsize_o(s_arsize),
        .s_arburst_o(s_arburst), .s_arvalid_o(s_arvalid),
        .s_arready_i(s_arready), .s_rid_i(s_rid),
        .s_rdata_i(s_rdata), .s_rresp_i(s_rresp),
        .s_rlast_i(s_rlast), .s_rvalid_i(s_rvalid),
        .s_rready_o(s_rready),
        .fs_rd_fail_o(fs_rd_fail), .fs_rd_addr_o(fs_rd_addr),
        .fs_rd_id_o(fs_rd_id), .mon_rd_beats_o(mon_rd_beats),
        .mon_rd_bursts_o(mon_rd_bursts), .mon_rd_err_o(mon_rd_err),
        .mon_rd_maxwait_o(mon_rd_maxwait)
    );

    initial begin
        checks = 0;
        rst_n = 1'b0;
        m_arid = 0; m_araddr = 0; m_arlen = 0;
        m_arsize = {NUM_M{`AXI_SIZE_8B}};
        m_arburst = {NUM_M{`AXI_BURST_INCR}};
        m_arvalid = 0; m_rready = {NUM_M{1'b1}};
        s_base = {32'h0000_3000, 32'h0000_2000, 32'h0000_1000};
        s_limit = {32'h0000_4000, 32'h0000_3000, 32'h0000_2000};
        read_connect = {3'b111, 3'b011};
        s_arready = {NUM_S{1'b1}};
        s_rid = 0; s_rdata = 0; s_rresp = 0; s_rlast = 0; s_rvalid = 0;
        repeat (3) @(posedge clk);
        rst_n = 1'b1;
        @(posedge clk); #1;

        m_araddr[0 +: 32] = 32'h0000_1000;
        m_arid[0 +: `AXI_ID_W] = 4'h5;
        m_araddr[32 +: 32] = 32'h0000_3000;
        m_arid[`AXI_ID_W +: `AXI_ID_W] = 4'h9;
        m_arvalid = 2'b11;
        #1;
        check_true(m_arready == 2'b11 && s_arvalid[0] && s_arvalid[2],
                   "independent AR requests accept together");
        @(posedge clk); #1;
        m_arvalid = 0;

        s_rid[GID_W +: GID_W] = {1'b0, 4'h5};
        s_rdata[`AXI_DATA_W +: `AXI_DATA_W] = 64'hdead_beef_dead_beef;
        s_rlast[1] = 1'b1; s_rvalid[1] = 1'b1;
        #1;
        check_true(!m_rvalid[0] && !s_rready[1],
                   "unowned slave response is isolated");
        s_rvalid[1] = 1'b0;

        s_rid[0 +: GID_W] = {1'b0, 4'h5};
        s_rdata[0 +: `AXI_DATA_W] = 64'h1111_2222_3333_4444;
        s_rlast[0] = 1'b1; s_rvalid[0] = 1'b1;
        s_rid[2*GID_W +: GID_W] = {1'b1, 4'h9};
        s_rdata[2*`AXI_DATA_W +: `AXI_DATA_W] = 64'haaaa_bbbb_cccc_dddd;
        s_rlast[2] = 1'b1; s_rvalid[2] = 1'b1;
        #1;
        check_true(m_rvalid == 2'b11 && s_rready[0] && s_rready[2],
                   "recorded owners return concurrently");
        check_true(m_rid[0 +: `AXI_ID_W] == 4'h5 &&
                   m_rdata[0 +: `AXI_DATA_W] == 64'h1111_2222_3333_4444,
                   "master zero receives slave zero payload");
        check_true(m_rid[`AXI_ID_W +: `AXI_ID_W] == 4'h9 &&
                   m_rdata[`AXI_DATA_W +: `AXI_DATA_W] == 64'haaaa_bbbb_cccc_dddd,
                   "master one receives slave two payload");
        @(posedge clk); #1;
        s_rvalid = 0; s_rlast = 0;

        issue_m0(32'h0000_3000, 4'h6, 8'd0);
        #1;
        check_true(m_rvalid[0] &&
                   m_rresp[0 +: `AXI_RESP_W] == `AXI_RESP_DECERR &&
                   m_rid[0 +: `AXI_ID_W] == 4'h6 && m_rlast[0] &&
                   !s_arvalid[2],
                   "disconnected target returns DECERR");
        @(posedge clk); #1;

        m_rready[1] = 1'b0;
        m_araddr[32 +: 32] = 32'h0000_2000;
        m_arid[`AXI_ID_W +: `AXI_ID_W] = 4'h7;
        m_arvalid[1] = 1'b1;
        @(posedge clk);
        while (!m_arready[1]) @(posedge clk);
        #1;
        m_arvalid[1] = 1'b0;
        s_rid[GID_W +: GID_W] = {1'b1, 4'h7};
        s_rdata[`AXI_DATA_W +: `AXI_DATA_W] = 64'h0123_4567_89ab_cdef;
        s_rlast[1] = 1'b1; s_rvalid[1] = 1'b1;
        s_rid[0 +: GID_W] = {1'b1, 4'h7};
        s_rdata[0 +: `AXI_DATA_W] = 64'hffff_ffff_ffff_ffff;
        s_rlast[0] = 1'b1; s_rvalid[0] = 1'b1;
        #1;
        check_true(m_rvalid[1] && !s_rready[1] && !s_rready[0] &&
                   m_rdata[`AXI_DATA_W +: `AXI_DATA_W] ==
                       64'h0123_4567_89ab_cdef,
                   "backpressured owner is stable and exclusive");
        m_rready[1] = 1'b1;
        #1;
        check_true(s_rready[1] && !s_rready[0],
                   "READY returns only to recorded owner");
        @(posedge clk); #1;
        s_rvalid = 0; s_rlast = 0;

        issue_m0(32'h0000_1008, 4'h3, 8'd0);
        s_rid[0 +: GID_W] = {1'b0, 4'h4};
        s_rdata[0 +: `AXI_DATA_W] = 64'h5555_aaaa_5555_aaaa;
        s_rlast[0] = 1'b1; s_rvalid[0] = 1'b1;
        #1;
        check_true(!m_rvalid[0] && !s_rready[0],
                   "mismatched RID is not delivered");
        s_rid[0 +: GID_W] = {1'b0, 4'h3};
        #1;
        check_true(m_rvalid[0] && s_rready[0],
                   "corrected RID completes transaction");
        @(posedge clk); #1;
        s_rvalid[0] = 1'b0; s_rlast[0] = 1'b0;

        issue_m0(32'h0000_2000, 4'ha, 8'd1);
        s_rid[GID_W +: GID_W] = {1'b0, 4'ha};
        s_rdata[`AXI_DATA_W +: `AXI_DATA_W] = 64'h1;
        s_rlast[1] = 1'b0; s_rvalid[1] = 1'b1;
        #1;
        check_true(m_rvalid[0] && s_rready[1] && !m_rlast[0],
                   "owner persists for non-last beat");
        @(posedge clk); #1;
        s_rdata[`AXI_DATA_W +: `AXI_DATA_W] = 64'h2;
        s_rlast[1] = 1'b1;
        #1;
        check_true(m_rvalid[0] && m_rlast[0] &&
                   m_rdata[0 +: `AXI_DATA_W] == 64'h2,
                   "owner releases on accepted RLAST");
        @(posedge clk); #1;
        s_rvalid[1] = 1'b0; s_rlast[1] = 1'b0;

        check_true(mon_rd_bursts[0 +: 32] == 32'd4 &&
                   mon_rd_bursts[32 +: 32] == 32'd2 &&
                   !fs_rd_fail[0] && !fs_rd_fail[1],
                   "monitor counts and fail-stop stay coherent");
        $display("PASS: AXI single-outstanding recorded routing (%0d checks)", checks);
        $finish;
    end
endmodule
