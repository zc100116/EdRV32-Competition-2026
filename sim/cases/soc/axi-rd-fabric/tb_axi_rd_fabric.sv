`timescale 1ns/1ps
`include "edrv32_axi4.vh"

module tb_axi_rd_fabric;
    reg clk;
    reg start_multi;
    reg start_single;
    wire multi_done;
    wire single_done;
    wire [31:0] multi_checks;
    wire [31:0] single_checks;
    wire [31:0] multi_errors;
    wire [31:0] single_errors;

    initial clk = 1'b0;
    always #5 clk = ~clk;

    axi_rd_fabric_multi_env u_multi (
        .clk_i    (clk),
        .start_i  (start_multi),
        .done_o   (multi_done),
        .checks_o (multi_checks),
        .errors_o (multi_errors)
    );

    axi_rd_fabric_single_env u_single (
        .clk_i    (clk),
        .start_i  (start_single),
        .done_o   (single_done),
        .checks_o (single_checks),
        .errors_o (single_errors)
    );

    initial begin
        start_multi  = 1'b0;
        start_single = 1'b0;

        repeat (2) @(posedge clk);
        @(negedge clk);
        start_multi = 1'b1;
        @(negedge clk);
        start_multi = 1'b0;
        wait (multi_done);

        @(negedge clk);
        start_single = 1'b1;
        @(negedge clk);
        start_single = 1'b0;
        wait (single_done);

        if ((multi_errors + single_errors) == 0) begin
            $display("PASS: axi_rd_fabric directed test (%0d checks)",
                     multi_checks + single_checks);
            $finish;
        end else begin
            $display("FAIL: axi_rd_fabric directed test (%0d failures in %0d checks)",
                     multi_errors + single_errors,
                     multi_checks + single_checks);
            $fatal(1);
        end
    end
endmodule


module axi_rd_fabric_multi_env (
    input  wire        clk_i,
    input  wire        start_i,
    output reg         done_o,
    output reg  [31:0] checks_o,
    output reg  [31:0] errors_o
);
    localparam integer NUM_M = 2;
    localparam integer NUM_S = 3;
    localparam integer ID_W = `AXI_ID_W;
    localparam integer DATA_W = `AXI_DATA_W;
    localparam integer GID_W = ID_W + 1;

    reg rst_n;
    reg [7:0] stage;

    reg  [NUM_M*ID_W-1:0]             m_arid;
    reg  [NUM_M*32-1:0]               m_araddr;
    reg  [NUM_M*`AXI_LEN_W-1:0]       m_arlen;
    reg  [NUM_M*`AXI_SIZE_W-1:0]      m_arsize;
    reg  [NUM_M*`AXI_BURST_W-1:0]     m_arburst;
    reg  [NUM_M-1:0]                  m_arvalid;
    wire [NUM_M-1:0]                  m_arready;
    wire [NUM_M*ID_W-1:0]             m_rid;
    wire [NUM_M*DATA_W-1:0]           m_rdata;
    wire [NUM_M*`AXI_RESP_W-1:0]      m_rresp;
    wire [NUM_M-1:0]                  m_rlast;
    wire [NUM_M-1:0]                  m_rvalid;
    reg  [NUM_M-1:0]                  m_rready;

    reg  [NUM_S*32-1:0]               s_base;
    reg  [NUM_S*32-1:0]               s_limit;
    reg  [NUM_M*NUM_S-1:0]            read_connect;
    wire [NUM_S*GID_W-1:0]            s_arid;
    wire [NUM_S*32-1:0]               s_araddr;
    wire [NUM_S*`AXI_LEN_W-1:0]       s_arlen;
    wire [NUM_S*`AXI_SIZE_W-1:0]      s_arsize;
    wire [NUM_S*`AXI_BURST_W-1:0]     s_arburst;
    wire [NUM_S-1:0]                  s_arvalid;
    reg  [NUM_S-1:0]                  s_arready;
    reg  [NUM_S*GID_W-1:0]            s_rid;
    reg  [NUM_S*DATA_W-1:0]           s_rdata;
    reg  [NUM_S*`AXI_RESP_W-1:0]      s_rresp;
    reg  [NUM_S-1:0]                  s_rlast;
    reg  [NUM_S-1:0]                  s_rvalid;
    wire [NUM_S-1:0]                  s_rready;

    wire [NUM_M-1:0]                  fs_rd_fail;
    wire [NUM_M*32-1:0]               fs_rd_addr;
    wire [NUM_M*ID_W-1:0]             fs_rd_id;
    wire [NUM_M*32-1:0]               mon_rd_beats;
    wire [NUM_M*32-1:0]               mon_rd_bursts;
    wire [NUM_M*32-1:0]               mon_rd_err;
    wire [NUM_M*32-1:0]               mon_rd_maxwait;

    function automatic [GID_W-1:0] global_id;
        input integer master;
        input [ID_W-1:0] local_id;
        begin
            global_id = {master[0], local_id};
        end
    endfunction

    task automatic check_true;
        input condition;
        input [8*112-1:0] message;
        begin
            checks_o = checks_o + 1'b1;
            if (condition !== 1'b1) begin
                errors_o = errors_o + 1'b1;
                $display("FAIL [multi stage %0d]: %0s", stage, message);
            end
        end
    endtask

    task automatic mark_stage;
        input [7:0] value;
        input [8*80-1:0] name;
        begin
            stage = value;
            $display("MULTI stage %0d: %0s", value, name);
        end
    endtask

    task automatic reset_dut;
        begin
            rst_n = 1'b0;
            m_arid = 0;
            m_araddr = 0;
            m_arlen = 0;
            m_arsize = {NUM_M{`AXI_SIZE_8B}};
            m_arburst = {NUM_M{`AXI_BURST_INCR}};
            m_arvalid = 0;
            m_rready = {NUM_M{1'b1}};
            s_base = {32'hffff_f000, 32'h0000_3000, 32'h0000_1000};
            s_limit = {32'h0000_1000, 32'h0000_4000, 32'h0000_2000};
            read_connect = {NUM_M*NUM_S{1'b1}};
            s_arready = {NUM_S{1'b1}};
            s_rid = 0;
            s_rdata = 0;
            s_rresp = 0;
            s_rlast = 0;
            s_rvalid = 0;
            repeat (3) @(posedge clk_i);
            @(negedge clk_i);
            rst_n = 1'b1;
            @(posedge clk_i);
            #1;
        end
    endtask

    task automatic drive_ar;
        input integer master;
        input [31:0] address;
        input [ID_W-1:0] id;
        input [`AXI_LEN_W-1:0] length;
        begin
            m_araddr[master*32 +: 32] = address;
            m_arid[master*ID_W +: ID_W] = id;
            m_arlen[master*`AXI_LEN_W +: `AXI_LEN_W] = length;
            m_arsize[master*`AXI_SIZE_W +: `AXI_SIZE_W] = `AXI_SIZE_8B;
            m_arburst[master*`AXI_BURST_W +: `AXI_BURST_W] = `AXI_BURST_INCR;
            m_arvalid[master] = 1'b1;
        end
    endtask

    task automatic clear_ar;
        input integer master;
        begin
            m_arvalid[master] = 1'b0;
        end
    endtask

    task automatic accept_ar;
        input integer master;
        input integer slave;
        input [31:0] address;
        input [ID_W-1:0] id;
        input [`AXI_LEN_W-1:0] length;
        begin
            @(negedge clk_i);
            drive_ar(master, address, id, length);
            #1;
            check_true(m_arready[master] && s_arvalid[slave],
                       "AR was not accepted by the expected slave");
            check_true(s_arid[slave*GID_W +: GID_W] == global_id(master, id),
                       "global ARID prefix is incorrect");
            check_true(s_araddr[slave*32 +: 32] == address,
                       "ARADDR was not forwarded unchanged");
            @(posedge clk_i);
            #1;
            clear_ar(master);
        end
    endtask

    task automatic send_last_r;
        input integer slave;
        input integer master;
        input [ID_W-1:0] id;
        input [DATA_W-1:0] data;
        begin
            @(negedge clk_i);
            s_rid[slave*GID_W +: GID_W] = global_id(master, id);
            s_rdata[slave*DATA_W +: DATA_W] = data;
            s_rresp[slave*`AXI_RESP_W +: `AXI_RESP_W] = `AXI_RESP_OKAY;
            s_rlast[slave] = 1'b1;
            s_rvalid[slave] = 1'b1;
            #1;
            check_true(m_rvalid[master] && s_rready[slave],
                       "R response did not reach its master");
            check_true(m_rid[master*ID_W +: ID_W] == id &&
                       m_rdata[master*DATA_W +: DATA_W] == data,
                       "RID stripping or RDATA routing is incorrect");
            @(posedge clk_i);
            #1;
            s_rvalid[slave] = 1'b0;
            s_rlast[slave] = 1'b0;
        end
    endtask

    axi_rd_fabric #(
        .NUM_M              (NUM_M),
        .NUM_S              (NUM_S),
        .ADDR_W             (32),
        .DATA_W             (DATA_W),
        .ID_W               (ID_W),
        .LEN_W              (`AXI_LEN_W),
        .SIZE_W             (`AXI_SIZE_W),
        .BURST_W            (`AXI_BURST_W),
        .RESP_W             (`AXI_RESP_W),
        .GID_W              (GID_W),
        .M_MAX_OUTSTANDING  (3),
        .RD_TIMEOUT_CYCLES  (0),
        .AXI_MON_ENABLE     (0)
    ) dut (
        .clk(clk_i), .rst_n(rst_n),
        .m_arid_i(m_arid), .m_araddr_i(m_araddr),
        .m_arlen_i(m_arlen), .m_arsize_i(m_arsize),
        .m_arburst_i(m_arburst), .m_arvalid_i(m_arvalid),
        .m_arready_o(m_arready), .m_rid_o(m_rid),
        .m_rdata_o(m_rdata), .m_rresp_o(m_rresp),
        .m_rlast_o(m_rlast), .m_rvalid_o(m_rvalid),
        .m_rready_i(m_rready), .s_base_i(s_base),
        .s_limit_i(s_limit), .m_read_connect_i(read_connect),
        .s_arid_o(s_arid), .s_araddr_o(s_araddr),
        .s_arlen_o(s_arlen), .s_arsize_o(s_arsize),
        .s_arburst_o(s_arburst), .s_arvalid_o(s_arvalid),
        .s_arready_i(s_arready), .s_rid_i(s_rid),
        .s_rdata_i(s_rdata), .s_rresp_i(s_rresp),
        .s_rlast_i(s_rlast), .s_rvalid_i(s_rvalid),
        .s_rready_o(s_rready), .fs_rd_fail_o(fs_rd_fail),
        .fs_rd_addr_o(fs_rd_addr), .fs_rd_id_o(fs_rd_id),
        .mon_rd_beats_o(mon_rd_beats),
        .mon_rd_bursts_o(mon_rd_bursts),
        .mon_rd_err_o(mon_rd_err),
        .mon_rd_maxwait_o(mon_rd_maxwait)
    );

    initial begin
        done_o = 1'b0;
        checks_o = 0;
        errors_o = 0;
        stage = 0;
        rst_n = 1'b0;
        m_arvalid = 0;
        m_rready = 0;
        s_arready = 0;
        s_rvalid = 0;
        wait (start_i);

        reset_dut();

        // A general multi-outstanding route can accept AR and the matching
        // zero-latency R response on the same rising edge.
        mark_stage(1, "zero-latency AR and R");
        @(negedge clk_i);
        drive_ar(0, 32'h0000_1000, 4'h1, 8'd0);
        s_rid[0*GID_W +: GID_W] = global_id(0, 4'h1);
        s_rdata[0*DATA_W +: DATA_W] = 64'h0101_0101_0101_0101;
        s_rresp[0*`AXI_RESP_W +: `AXI_RESP_W] = `AXI_RESP_OKAY;
        s_rlast[0] = 1'b1;
        s_rvalid[0] = 1'b1;
        #1;
        check_true(m_arready[0] && s_arvalid[0],
                   "zero-latency AR path is not ready");
        check_true(m_rvalid[0] && s_rready[0] && m_rlast[0],
                   "zero-latency R response was not routed in the AR cycle");
        @(posedge clk_i);
        #1;
        clear_ar(0);
        s_rvalid[0] = 1'b0;
        s_rlast[0] = 1'b0;

        reset_dut();

        mark_stage(2, "outstanding admission limit");
        accept_ar(0, 0, 32'h0000_1000, 4'h1, 8'd0);
        accept_ar(0, 1, 32'h0000_3000, 4'h2, 8'd0);
        accept_ar(0, 2, 32'hffff_f000, 4'h3, 8'd0);
        @(negedge clk_i);
        drive_ar(0, 32'h0000_1010, 4'h4, 8'd0);
        #1;
        check_true(!m_arready[0] && !(|s_arvalid),
                   "fourth AR bypassed M_MAX_OUTSTANDING=3");
        clear_ar(0);

        mark_stage(3, "out-of-order completion across slaves and IDs");
        send_last_r(2, 0, 4'h3, 64'h3333_3333_3333_3333);
        accept_ar(0, 0, 32'h0000_1010, 4'h4, 8'd0);
        send_last_r(0, 0, 4'h4, 64'h4444_4444_4444_4444);
        send_last_r(0, 0, 4'h1, 64'h1111_1111_1111_1111);
        send_last_r(1, 0, 4'h2, 64'h2222_2222_2222_2222);

        reset_dut();

        mark_stage(4, "R burst source hold and response round-robin");
        accept_ar(0, 0, 32'h0000_1000, 4'h5, 8'd1);
        accept_ar(0, 1, 32'h0000_3000, 4'h6, 8'd0);
        @(negedge clk_i);
        s_rid[0*GID_W +: GID_W] = global_id(0, 4'h5);
        s_rdata[0*DATA_W +: DATA_W] = 64'h5000_0000_0000_0000;
        s_rresp[0*`AXI_RESP_W +: `AXI_RESP_W] = `AXI_RESP_OKAY;
        s_rlast[0] = 1'b0;
        s_rvalid[0] = 1'b1;
        s_rid[1*GID_W +: GID_W] = global_id(0, 4'h6);
        s_rdata[1*DATA_W +: DATA_W] = 64'h6000_0000_0000_0000;
        s_rresp[1*`AXI_RESP_W +: `AXI_RESP_W] = `AXI_RESP_OKAY;
        s_rlast[1] = 1'b1;
        s_rvalid[1] = 1'b1;
        #1;
        check_true(m_rvalid[0] && s_rready[0] && !s_rready[1] &&
                   m_rid[0*ID_W +: ID_W] == 4'h5,
                   "initial response arbiter did not select slave zero");
        @(posedge clk_i);
        #1;
        @(negedge clk_i);
        s_rvalid[0] = 1'b0;
        #1;
        check_true(!m_rvalid[0] && !s_rready[1],
                   "second slave interleaved into a held R burst");
        @(negedge clk_i);
        s_rdata[0*DATA_W +: DATA_W] = 64'h5000_0000_0000_0001;
        s_rlast[0] = 1'b1;
        s_rvalid[0] = 1'b1;
        #1;
        check_true(m_rvalid[0] && s_rready[0] && m_rlast[0] &&
                   m_rdata[0*DATA_W +: DATA_W] == 64'h5000_0000_0000_0001,
                   "held source did not deliver its final beat");
        @(posedge clk_i);
        #1;
        s_rvalid[0] = 1'b0;
        s_rlast[0] = 1'b0;
        check_true(m_rvalid[0] && s_rready[1] &&
                   m_rid[0*ID_W +: ID_W] == 4'h6,
                   "waiting slave was not selected after RLAST");
        @(posedge clk_i);
        #1;
        s_rvalid[1] = 1'b0;
        s_rlast[1] = 1'b0;

        mark_stage(5, "monitor disabled outputs");
        check_true(mon_rd_beats == 0 && mon_rd_bursts == 0 &&
                   mon_rd_err == 0 && mon_rd_maxwait == 0,
                   "monitor-disabled outputs are not tied to zero");
        check_true(fs_rd_fail == 0,
                   "timeout-disabled environment raised fail-stop");

        done_o = 1'b1;
        $display("MULTI complete: %0d checks, %0d failures", checks_o, errors_o);
    end
endmodule


module axi_rd_fabric_single_env (
    input  wire        clk_i,
    input  wire        start_i,
    output reg         done_o,
    output reg  [31:0] checks_o,
    output reg  [31:0] errors_o
);
    localparam integer NUM_M = 2;
    localparam integer NUM_S = 3;
    localparam integer ID_W = `AXI_ID_W;
    localparam integer DATA_W = `AXI_DATA_W;
    localparam integer GID_W = ID_W + 1;
    localparam integer TIMEOUT_CYCLES = 4;

    reg rst_n;
    reg [7:0] stage;

    reg  [NUM_M*ID_W-1:0]             m_arid;
    reg  [NUM_M*32-1:0]               m_araddr;
    reg  [NUM_M*`AXI_LEN_W-1:0]       m_arlen;
    reg  [NUM_M*`AXI_SIZE_W-1:0]      m_arsize;
    reg  [NUM_M*`AXI_BURST_W-1:0]     m_arburst;
    reg  [NUM_M-1:0]                  m_arvalid;
    wire [NUM_M-1:0]                  m_arready;
    wire [NUM_M*ID_W-1:0]             m_rid;
    wire [NUM_M*DATA_W-1:0]           m_rdata;
    wire [NUM_M*`AXI_RESP_W-1:0]      m_rresp;
    wire [NUM_M-1:0]                  m_rlast;
    wire [NUM_M-1:0]                  m_rvalid;
    reg  [NUM_M-1:0]                  m_rready;

    reg  [NUM_S*32-1:0]               s_base;
    reg  [NUM_S*32-1:0]               s_limit;
    reg  [NUM_M*NUM_S-1:0]            read_connect;
    wire [NUM_S*GID_W-1:0]            s_arid;
    wire [NUM_S*32-1:0]               s_araddr;
    wire [NUM_S*`AXI_LEN_W-1:0]       s_arlen;
    wire [NUM_S*`AXI_SIZE_W-1:0]      s_arsize;
    wire [NUM_S*`AXI_BURST_W-1:0]     s_arburst;
    wire [NUM_S-1:0]                  s_arvalid;
    reg  [NUM_S-1:0]                  s_arready;
    reg  [NUM_S*GID_W-1:0]            s_rid;
    reg  [NUM_S*DATA_W-1:0]           s_rdata;
    reg  [NUM_S*`AXI_RESP_W-1:0]      s_rresp;
    reg  [NUM_S-1:0]                  s_rlast;
    reg  [NUM_S-1:0]                  s_rvalid;
    wire [NUM_S-1:0]                  s_rready;

    wire [NUM_M-1:0]                  fs_rd_fail;
    wire [NUM_M*32-1:0]               fs_rd_addr;
    wire [NUM_M*ID_W-1:0]             fs_rd_id;
    wire [NUM_M*32-1:0]               mon_rd_beats;
    wire [NUM_M*32-1:0]               mon_rd_bursts;
    wire [NUM_M*32-1:0]               mon_rd_err;
    wire [NUM_M*32-1:0]               mon_rd_maxwait;

    function automatic [GID_W-1:0] global_id;
        input integer master;
        input [ID_W-1:0] local_id;
        begin
            global_id = {master[0], local_id};
        end
    endfunction

    task automatic check_true;
        input condition;
        input [8*112-1:0] message;
        begin
            checks_o = checks_o + 1'b1;
            if (condition !== 1'b1) begin
                errors_o = errors_o + 1'b1;
                $display("FAIL [single stage %0d]: %0s", stage, message);
            end
        end
    endtask

    task automatic mark_stage;
        input [7:0] value;
        input [8*80-1:0] name;
        begin
            stage = value;
            $display("SINGLE stage %0d: %0s", value, name);
        end
    endtask

    task automatic reset_dut;
        begin
            rst_n = 1'b0;
            m_arid = 0;
            m_araddr = 0;
            m_arlen = 0;
            m_arsize = {NUM_M{`AXI_SIZE_8B}};
            m_arburst = {NUM_M{`AXI_BURST_INCR}};
            m_arvalid = 0;
            m_rready = {NUM_M{1'b1}};
            s_base = {32'hffff_f000, 32'h0000_3000, 32'h0000_1000};
            s_limit = {32'h0000_1000, 32'h0000_4000, 32'h0000_2000};
            read_connect = 0;
            read_connect[0*NUM_S + 0] = 1'b1;
            read_connect[0*NUM_S + 1] = 1'b1;
            read_connect[1*NUM_S + 0] = 1'b1;
            read_connect[1*NUM_S + 1] = 1'b1;
            read_connect[1*NUM_S + 2] = 1'b1;
            s_arready = {NUM_S{1'b1}};
            s_rid = 0;
            s_rdata = 0;
            s_rresp = 0;
            s_rlast = 0;
            s_rvalid = 0;
            repeat (3) @(posedge clk_i);
            @(negedge clk_i);
            rst_n = 1'b1;
            @(posedge clk_i);
            #1;
        end
    endtask

    task automatic drive_ar;
        input integer master;
        input [31:0] address;
        input [ID_W-1:0] id;
        input [`AXI_LEN_W-1:0] length;
        begin
            m_araddr[master*32 +: 32] = address;
            m_arid[master*ID_W +: ID_W] = id;
            m_arlen[master*`AXI_LEN_W +: `AXI_LEN_W] = length;
            m_arsize[master*`AXI_SIZE_W +: `AXI_SIZE_W] = `AXI_SIZE_8B;
            m_arburst[master*`AXI_BURST_W +: `AXI_BURST_W] = `AXI_BURST_INCR;
            m_arvalid[master] = 1'b1;
        end
    endtask

    task automatic accept_ar;
        input integer master;
        input integer slave;
        input [31:0] address;
        input [ID_W-1:0] id;
        input [`AXI_LEN_W-1:0] length;
        begin
            @(negedge clk_i);
            drive_ar(master, address, id, length);
            #1;
            check_true(m_arready[master] && s_arvalid[slave],
                       "AR was not accepted by the expected slave");
            check_true(s_arid[slave*GID_W +: GID_W] == global_id(master, id),
                       "global ARID is incorrect");
            check_true(s_araddr[slave*32 +: 32] == address &&
                       s_arlen[slave*`AXI_LEN_W +: `AXI_LEN_W] == length &&
                       s_arsize[slave*`AXI_SIZE_W +: `AXI_SIZE_W] == `AXI_SIZE_8B &&
                       s_arburst[slave*`AXI_BURST_W +: `AXI_BURST_W] == `AXI_BURST_INCR,
                       "AR payload was not forwarded unchanged");
            @(posedge clk_i);
            #1;
            m_arvalid[master] = 1'b0;
        end
    endtask

    task automatic send_r_beat;
        input integer slave;
        input integer master;
        input [ID_W-1:0] id;
        input [DATA_W-1:0] data;
        input [`AXI_RESP_W-1:0] response;
        input last;
        begin
            @(negedge clk_i);
            s_rid[slave*GID_W +: GID_W] = global_id(master, id);
            s_rdata[slave*DATA_W +: DATA_W] = data;
            s_rresp[slave*`AXI_RESP_W +: `AXI_RESP_W] = response;
            s_rlast[slave] = last;
            s_rvalid[slave] = 1'b1;
            #1;
            check_true(m_rvalid[master] && s_rready[slave],
                       "R beat did not reach its recorded owner");
            check_true(m_rid[master*ID_W +: ID_W] == id &&
                       m_rdata[master*DATA_W +: DATA_W] == data &&
                       m_rresp[master*`AXI_RESP_W +: `AXI_RESP_W] == response &&
                       m_rlast[master] == last,
                       "R payload changed while crossing the fabric");
            @(posedge clk_i);
            #1;
            s_rvalid[slave] = 1'b0;
            s_rlast[slave] = 1'b0;
        end
    endtask

    task automatic expect_decerr;
        input integer master;
        input [31:0] address;
        input [ID_W-1:0] id;
        input [`AXI_LEN_W-1:0] length;
        integer beat;
        begin
            @(negedge clk_i);
            drive_ar(master, address, id, length);
            #1;
            check_true(m_arready[master] && !(|s_arvalid),
                       "invalid AR was forwarded to a slave");
            @(posedge clk_i);
            #1;
            m_arvalid[master] = 1'b0;
            m_rready[master] = 1'b0;
            check_true(m_rvalid[master] &&
                       m_rid[master*ID_W +: ID_W] == id &&
                       m_rresp[master*`AXI_RESP_W +: `AXI_RESP_W] == `AXI_RESP_DECERR &&
                       m_rdata[master*DATA_W +: DATA_W] == 0,
                       "inline DECERR first beat is incorrect");
            repeat (2) @(posedge clk_i);
            #1;
            check_true(m_rvalid[master] &&
                       m_rlast[master] == (length == 0),
                       "DECERR response did not remain stable under backpressure");
            @(negedge clk_i);
            m_rready[master] = 1'b1;
            for (beat = 0; beat <= length; beat = beat + 1) begin
                #1;
                check_true(m_rvalid[master] &&
                           m_rid[master*ID_W +: ID_W] == id &&
                           m_rresp[master*`AXI_RESP_W +: `AXI_RESP_W] == `AXI_RESP_DECERR &&
                           m_rdata[master*DATA_W +: DATA_W] == 0 &&
                           m_rlast[master] == (beat == length),
                           "DECERR burst length or payload is incorrect");
                @(posedge clk_i);
                #1;
            end
            check_true(!m_rvalid[master],
                       "DECERR responder stayed active after final beat");
        end
    endtask

    axi_rd_fabric #(
        .NUM_M              (NUM_M),
        .NUM_S              (NUM_S),
        .ADDR_W             (32),
        .DATA_W             (DATA_W),
        .ID_W               (ID_W),
        .LEN_W              (`AXI_LEN_W),
        .SIZE_W             (`AXI_SIZE_W),
        .BURST_W            (`AXI_BURST_W),
        .RESP_W             (`AXI_RESP_W),
        .GID_W              (GID_W),
        .M_MAX_OUTSTANDING  (1),
        .RD_TIMEOUT_CYCLES  (TIMEOUT_CYCLES),
        .AXI_MON_ENABLE     (1)
    ) dut (
        .clk(clk_i), .rst_n(rst_n),
        .m_arid_i(m_arid), .m_araddr_i(m_araddr),
        .m_arlen_i(m_arlen), .m_arsize_i(m_arsize),
        .m_arburst_i(m_arburst), .m_arvalid_i(m_arvalid),
        .m_arready_o(m_arready), .m_rid_o(m_rid),
        .m_rdata_o(m_rdata), .m_rresp_o(m_rresp),
        .m_rlast_o(m_rlast), .m_rvalid_o(m_rvalid),
        .m_rready_i(m_rready), .s_base_i(s_base),
        .s_limit_i(s_limit), .m_read_connect_i(read_connect),
        .s_arid_o(s_arid), .s_araddr_o(s_araddr),
        .s_arlen_o(s_arlen), .s_arsize_o(s_arsize),
        .s_arburst_o(s_arburst), .s_arvalid_o(s_arvalid),
        .s_arready_i(s_arready), .s_rid_i(s_rid),
        .s_rdata_i(s_rdata), .s_rresp_i(s_rresp),
        .s_rlast_i(s_rlast), .s_rvalid_i(s_rvalid),
        .s_rready_o(s_rready), .fs_rd_fail_o(fs_rd_fail),
        .fs_rd_addr_o(fs_rd_addr), .fs_rd_id_o(fs_rd_id),
        .mon_rd_beats_o(mon_rd_beats),
        .mon_rd_bursts_o(mon_rd_bursts),
        .mon_rd_err_o(mon_rd_err),
        .mon_rd_maxwait_o(mon_rd_maxwait)
    );

    initial begin
        done_o = 1'b0;
        checks_o = 0;
        errors_o = 0;
        stage = 0;
        rst_n = 1'b0;
        m_arvalid = 0;
        m_rready = 0;
        s_arready = 0;
        s_rvalid = 0;
        wait (start_i);

        reset_dut();
        mark_stage(1, "reset and idle outputs");
        check_true(m_arready == 0 && m_rvalid == 0 && s_arvalid == 0 &&
                   s_rready == 0 && fs_rd_fail == 0,
                   "idle outputs or fail-stop state are not clear");
        check_true(mon_rd_beats == 0 && mon_rd_bursts == 0 &&
                   mon_rd_err == 0 && mon_rd_maxwait == 0,
                   "monitor counters did not reset");

        mark_stage(2, "AR backpressure and payload forwarding");
        @(negedge clk_i);
        s_arready[0] = 1'b0;
        drive_ar(0, 32'h0000_1000, 4'ha, 8'd2);
        #1;
        check_true(s_arvalid[0] && !m_arready[0],
                   "slave AR backpressure did not reach the master");
        check_true(s_arid[0*GID_W +: GID_W] == global_id(0, 4'ha) &&
                   s_araddr[0*32 +: 32] == 32'h0000_1000 &&
                   s_arlen[0*`AXI_LEN_W +: `AXI_LEN_W] == 8'd2 &&
                   s_arsize[0*`AXI_SIZE_W +: `AXI_SIZE_W] == `AXI_SIZE_8B &&
                   s_arburst[0*`AXI_BURST_W +: `AXI_BURST_W] == `AXI_BURST_INCR,
                   "AR payload changed while stalled");
        repeat (2) @(posedge clk_i);
        #1;
        check_true(s_arvalid[0] && !m_arready[0],
                   "ARVALID was lost before handshake");
        @(negedge clk_i);
        s_arready[0] = 1'b1;
        #1;
        check_true(m_arready[0],
                   "ARREADY did not return when the slave became ready");
        @(posedge clk_i);
        #1;
        m_arvalid[0] = 1'b0;

        mark_stage(3, "single-outstanding admission gate");
        @(negedge clk_i);
        drive_ar(0, 32'h0000_3000, 4'hb, 8'd0);
        #1;
        check_true(!m_arready[0] && !s_arvalid[1],
                   "second AR was accepted before the first RLAST");
        m_arvalid[0] = 1'b0;

        mark_stage(4, "recorded slave and RID isolation");
        @(negedge clk_i);
        s_rid[1*GID_W +: GID_W] = global_id(0, 4'ha);
        s_rdata[1*DATA_W +: DATA_W] = 64'hbad0_bad0_bad0_bad0;
        s_rlast[1] = 1'b1;
        s_rvalid[1] = 1'b1;
        #1;
        check_true(!m_rvalid[0] && !s_rready[1],
                   "unowned slave response reached the master");
        s_rvalid[1] = 1'b0;
        s_rlast[1] = 1'b0;
        s_rid[0*GID_W +: GID_W] = global_id(0, 4'hb);
        s_rdata[0*DATA_W +: DATA_W] = 64'hbad1_bad1_bad1_bad1;
        s_rlast[0] = 1'b1;
        s_rvalid[0] = 1'b1;
        #1;
        check_true(!m_rvalid[0] && !s_rready[0],
                   "mismatched RID reached the master");
        s_rvalid[0] = 1'b0;
        s_rlast[0] = 1'b0;

        mark_stage(5, "R burst, backpressure and monitor counters");
        send_r_beat(0, 0, 4'ha, 64'h0000_0000_0000_0000,
                    `AXI_RESP_OKAY, 1'b0);
        @(negedge clk_i);
        m_rready[0] = 1'b0;
        s_rid[0*GID_W +: GID_W] = global_id(0, 4'ha);
        s_rdata[0*DATA_W +: DATA_W] = 64'h0000_0000_0000_0001;
        s_rresp[0*`AXI_RESP_W +: `AXI_RESP_W] = `AXI_RESP_OKAY;
        s_rlast[0] = 1'b0;
        s_rvalid[0] = 1'b1;
        #1;
        check_true(m_rvalid[0] && !s_rready[0] &&
                   m_rdata[0*DATA_W +: DATA_W] == 64'h0000_0000_0000_0001,
                   "Master backpressure did not hold the R payload");
        repeat (2) @(posedge clk_i);
        #1;
        check_true(m_rvalid[0] && !s_rready[0] &&
                   mon_rd_beats[0*32 +: 32] == 32'd1,
                   "stalled R beat was consumed or monitor count advanced");
        @(negedge clk_i);
        m_rready[0] = 1'b1;
        #1;
        check_true(s_rready[0],
                   "RREADY was not returned to the recorded slave");
        @(posedge clk_i);
        #1;
        s_rvalid[0] = 1'b0;
        send_r_beat(0, 0, 4'ha, 64'h0000_0000_0000_0002,
                    `AXI_RESP_SLVERR, 1'b1);
        check_true(mon_rd_bursts[0*32 +: 32] == 32'd1 &&
                   mon_rd_beats[0*32 +: 32] == 32'd3 &&
                   mon_rd_err[0*32 +: 32] == 32'd1 &&
                   mon_rd_maxwait[0*32 +: 32] == 32'd3,
                   "enabled monitor counters do not match accepted traffic");

        mark_stage(6, "parallel transfers to independent slaves");
        @(negedge clk_i);
        drive_ar(0, 32'h0000_1008, 4'h1, 8'd0);
        drive_ar(1, 32'h0000_3008, 4'h2, 8'd0);
        #1;
        check_true(m_arready == 2'b11 && s_arvalid[0] && s_arvalid[1],
                   "independent slaves did not accept ARs concurrently");
        @(posedge clk_i);
        #1;
        m_arvalid = 0;
        @(negedge clk_i);
        s_rid[0*GID_W +: GID_W] = global_id(0, 4'h1);
        s_rdata[0*DATA_W +: DATA_W] = 64'h1111_1111_1111_1111;
        s_rresp[0*`AXI_RESP_W +: `AXI_RESP_W] = `AXI_RESP_OKAY;
        s_rlast[0] = 1'b1;
        s_rvalid[0] = 1'b1;
        s_rid[1*GID_W +: GID_W] = global_id(1, 4'h2);
        s_rdata[1*DATA_W +: DATA_W] = 64'h2222_2222_2222_2222;
        s_rresp[1*`AXI_RESP_W +: `AXI_RESP_W] = `AXI_RESP_OKAY;
        s_rlast[1] = 1'b1;
        s_rvalid[1] = 1'b1;
        #1;
        check_true(m_rvalid == 2'b11 && s_rready[0] && s_rready[1] &&
                   m_rid[0*ID_W +: ID_W] == 4'h1 &&
                   m_rid[1*ID_W +: ID_W] == 4'h2,
                   "parallel R responses were not routed independently");
        @(posedge clk_i);
        #1;
        s_rvalid = 0;
        s_rlast = 0;

        reset_dut();
        mark_stage(7, "per-slave round-robin arbitration");
        @(negedge clk_i);
        drive_ar(0, 32'h0000_1000, 4'h3, 8'd0);
        drive_ar(1, 32'h0000_1008, 4'h4, 8'd0);
        #1;
        check_true(m_arready == 2'b01 && s_arvalid == 3'b001 &&
                   s_arid[0*GID_W +: GID_W] == global_id(0, 4'h3),
                   "initial round-robin grant did not select master zero");
        @(posedge clk_i);
        #1;
        m_arvalid[0] = 1'b0;
        check_true(m_arready == 2'b10 && s_arvalid == 3'b001 &&
                   s_arid[0*GID_W +: GID_W] == global_id(1, 4'h4),
                   "round-robin pointer did not advance to master one");
        @(posedge clk_i);
        #1;
        m_arvalid[1] = 1'b0;
        send_r_beat(0, 0, 4'h3, 64'h3333_3333_3333_3333,
                    `AXI_RESP_OKAY, 1'b1);
        send_r_beat(0, 1, 4'h4, 64'h4444_4444_4444_4444,
                    `AXI_RESP_OKAY, 1'b1);

        reset_dut();
        mark_stage(8, "ordinary and wrap-through-zero address ranges");
        accept_ar(1, 2, 32'hffff_f100, 4'h5, 8'd0);
        send_r_beat(2, 1, 4'h5, 64'hffff_f100_0000_0000,
                    `AXI_RESP_OKAY, 1'b1);
        accept_ar(1, 2, 32'h0000_0080, 4'h6, 8'd0);
        send_r_beat(2, 1, 4'h6, 64'h0000_0080_0000_0000,
                    `AXI_RESP_OKAY, 1'b1);
        accept_ar(0, 0, 32'h0000_1000, 4'h7, 8'd0);
        send_r_beat(0, 0, 4'h7, 64'h0000_1000_0000_0000,
                    `AXI_RESP_OKAY, 1'b1);

        mark_stage(9, "decode miss, disconnect, overlap and empty range");
        expect_decerr(1, 32'h0000_2500, 4'h8, 8'd2);
        expect_decerr(0, 32'hffff_f100, 4'h9, 8'd0);
        s_base[1*32 +: 32] = 32'h0000_1800;
        s_limit[1*32 +: 32] = 32'h0000_2800;
        expect_decerr(1, 32'h0000_1900, 4'ha, 8'd0);
        s_base[1*32 +: 32] = 32'h0000_5000;
        s_limit[1*32 +: 32] = 32'h0000_5000;
        expect_decerr(1, 32'h0000_5000, 4'hb, 8'd0);
        s_base[1*32 +: 32] = 32'h0000_3000;
        s_limit[1*32 +: 32] = 32'h0000_4000;
        expect_decerr(1, 32'h0000_2000, 4'hc, 8'd0);

        reset_dut();
        mark_stage(10, "timeout fail-stop and reset clearing");
        accept_ar(0, 0, 32'h0000_1018, 4'hd, 8'd0);
        repeat (TIMEOUT_CYCLES + 1) @(posedge clk_i);
        #1;
        check_true(fs_rd_fail[0] &&
                   fs_rd_addr[0*32 +: 32] == 32'h0000_1018 &&
                   fs_rd_id[0*ID_W +: ID_W] == 4'hd,
                   "timeout did not latch its address and ID context");
        @(negedge clk_i);
        drive_ar(0, 32'h0000_3000, 4'he, 8'd0);
        #1;
        check_true(!m_arready[0] && !(|s_arvalid),
                   "fail-stop master was allowed to issue a new AR");
        m_arvalid[0] = 1'b0;
        send_r_beat(0, 0, 4'hd, 64'hdddd_dddd_dddd_dddd,
                    `AXI_RESP_OKAY, 1'b1);
        check_true(fs_rd_fail[0],
                   "fail-stop flag was not sticky after the old transaction drained");
        reset_dut();
        check_true(fs_rd_fail == 0 && mon_rd_beats == 0 &&
                   mon_rd_bursts == 0 && mon_rd_err == 0,
                   "reset did not clear sticky status and monitor counters");

        done_o = 1'b1;
        $display("SINGLE complete: %0d checks, %0d failures", checks_o, errors_o);
    end
endmodule
