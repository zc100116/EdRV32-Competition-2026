`timescale 1ns/1ps

module tb_ddr_axi_interconnect;
    localparam NUM_M = 2;
    localparam ADDR_W = 32;
    localparam DATA_W = 256;
    localparam STRB_W = DATA_W / 8;
    localparam ID_W = 4;
    localparam DDR_ID_W = 4;
    localparam LEN_W = 8;
    localparam COUNT_W = DDR_ID_W + 1;

    reg clk;
    reg rst_n;
    reg accept;
    integer checks;
    integer failures;
    integer stage;

    reg [NUM_M*ID_W-1:0] m_awid;
    reg [NUM_M*ADDR_W-1:0] m_awaddr;
    reg [NUM_M*LEN_W-1:0] m_awlen;
    reg [NUM_M*3-1:0] m_awsize;
    reg [NUM_M*2-1:0] m_awburst;
    reg [NUM_M*4-1:0] m_awqos;
    reg [NUM_M-1:0] m_awvalid;
    wire [NUM_M-1:0] m_awready;
    reg [NUM_M*DATA_W-1:0] m_wdata;
    reg [NUM_M*STRB_W-1:0] m_wstrb;
    reg [NUM_M-1:0] m_wlast;
    reg [NUM_M-1:0] m_wvalid;
    wire [NUM_M-1:0] m_wready;
    wire [NUM_M*ID_W-1:0] m_bid;
    wire [NUM_M*2-1:0] m_bresp;
    wire [NUM_M-1:0] m_bvalid;
    reg [NUM_M-1:0] m_bready;

    reg [NUM_M*ID_W-1:0] m_arid;
    reg [NUM_M*ADDR_W-1:0] m_araddr;
    reg [NUM_M*LEN_W-1:0] m_arlen;
    reg [NUM_M*3-1:0] m_arsize;
    reg [NUM_M*2-1:0] m_arburst;
    reg [NUM_M*4-1:0] m_arqos;
    reg [NUM_M-1:0] m_arvalid;
    wire [NUM_M-1:0] m_arready;
    wire [NUM_M*ID_W-1:0] m_rid;
    wire [NUM_M*DATA_W-1:0] m_rdata;
    wire [NUM_M*2-1:0] m_rresp;
    wire [NUM_M-1:0] m_rlast;
    wire [NUM_M-1:0] m_rvalid;
    reg [NUM_M-1:0] m_rready;

    reg [NUM_M-1:0] read_urgent;
    reg [NUM_M-1:0] write_urgent;
    reg [NUM_M*4-1:0] read_weight;
    reg [NUM_M*4-1:0] write_weight;
    reg [NUM_M*5-1:0] read_credit;
    reg [NUM_M*5-1:0] write_credit;
    reg [NUM_M*5-1:0] read_max_burst;
    reg [NUM_M*5-1:0] write_max_burst;

    wire [DDR_ID_W-1:0] s_awid;
    wire [ADDR_W-1:0] s_awaddr;
    wire [LEN_W-1:0] s_awlen;
    wire [2:0] s_awsize;
    wire [1:0] s_awburst;
    wire [3:0] s_awqos;
    wire s_awvalid;
    reg s_awready;
    wire [DATA_W-1:0] s_wdata;
    wire [STRB_W-1:0] s_wstrb;
    wire s_wlast;
    wire s_wvalid;
    reg s_wready;
    reg [DDR_ID_W-1:0] s_bid;
    reg [1:0] s_bresp;
    reg s_bvalid;
    wire s_bready;

    wire [DDR_ID_W-1:0] s_arid;
    wire [ADDR_W-1:0] s_araddr;
    wire [LEN_W-1:0] s_arlen;
    wire [2:0] s_arsize;
    wire [1:0] s_arburst;
    wire [3:0] s_arqos;
    wire s_arvalid;
    reg s_arready;
    reg [DDR_ID_W-1:0] s_rid;
    reg [DATA_W-1:0] s_rdata;
    reg [1:0] s_rresp;
    reg s_rlast;
    reg s_rvalid;
    wire s_rready;

    wire [NUM_M*COUNT_W-1:0] read_outstanding;
    wire [NUM_M*COUNT_W-1:0] write_outstanding;
    wire read_protocol_error;
    wire write_protocol_error;

    initial clk = 1'b0;
    always #5 clk = ~clk;

    task automatic check_true;
        input condition;
        input [8*120-1:0] message;
        begin
            checks = checks + 1;
            if (!condition) begin
                failures = failures + 1;
                $display("FAIL stage=%0d: %0s", stage, message);
            end
        end
    endtask

    task automatic reset_dut;
        begin
            rst_n = 1'b0;
            repeat (3) @(posedge clk);
            #1 rst_n = 1'b1;
            @(posedge clk); #1;
        end
    endtask

    task automatic send_ar;
        input integer master;
        input [ID_W-1:0] id;
        input [ADDR_W-1:0] addr;
        input [LEN_W-1:0] len;
        input [3:0] qos;
        begin
            m_arid[master*ID_W +: ID_W] = id;
            m_araddr[master*ADDR_W +: ADDR_W] = addr;
            m_arlen[master*LEN_W +: LEN_W] = len;
            m_arqos[master*4 +: 4] = qos;
            m_arvalid[master] = 1'b1;
            @(posedge clk);
            while (!m_arready[master])
                @(posedge clk);
            #1;
            m_arvalid[master] = 1'b0;
        end
    endtask

    task automatic send_aw;
        input integer master;
        input [ID_W-1:0] id;
        input [ADDR_W-1:0] addr;
        input [LEN_W-1:0] len;
        input [3:0] qos;
        begin
            m_awid[master*ID_W +: ID_W] = id;
            m_awaddr[master*ADDR_W +: ADDR_W] = addr;
            m_awlen[master*LEN_W +: LEN_W] = len;
            m_awqos[master*4 +: 4] = qos;
            m_awvalid[master] = 1'b1;
            @(posedge clk);
            while (!m_awready[master])
                @(posedge clk);
            #1;
            m_awvalid[master] = 1'b0;
        end
    endtask

    task automatic return_r;
        input [DDR_ID_W-1:0] id;
        input [DATA_W-1:0] data;
        input last;
        begin
            s_rid = id;
            s_rdata = data;
            s_rresp = 2'b00;
            s_rlast = last;
            s_rvalid = 1'b1;
            @(posedge clk);
            while (!s_rready)
                @(posedge clk);
            #1;
            s_rvalid = 1'b0;
            s_rlast = 1'b0;
        end
    endtask

    task automatic return_b;
        input [DDR_ID_W-1:0] id;
        input [1:0] resp;
        begin
            s_bid = id;
            s_bresp = resp;
            s_bvalid = 1'b1;
            @(posedge clk);
            while (!s_bready)
                @(posedge clk);
            #1;
            s_bvalid = 1'b0;
        end
    endtask

    edrv32_axi_m2s_interconnect #(
        .NUM_M(NUM_M), .ADDR_W(ADDR_W), .DATA_W(DATA_W),
        .ID_W(ID_W), .S_ID_W(DDR_ID_W), .LEN_W(LEN_W),
        .WR_ORDER_DEPTH(4), .STARVE_CYCLES(8), .COUNT_W(COUNT_W)
    ) dut (
        .clk_i(clk), .rst_n_i(rst_n), .accept_i(accept),
        .m_awid_i(m_awid), .m_awaddr_i(m_awaddr), .m_awlen_i(m_awlen),
        .m_awsize_i(m_awsize), .m_awburst_i(m_awburst), .m_awqos_i(m_awqos),
        .m_awvalid_i(m_awvalid), .m_awready_o(m_awready),
        .m_wdata_i(m_wdata), .m_wstrb_i(m_wstrb), .m_wlast_i(m_wlast),
        .m_wvalid_i(m_wvalid), .m_wready_o(m_wready),
        .m_bid_o(m_bid), .m_bresp_o(m_bresp), .m_bvalid_o(m_bvalid),
        .m_bready_i(m_bready), .m_arid_i(m_arid), .m_araddr_i(m_araddr),
        .m_arlen_i(m_arlen), .m_arsize_i(m_arsize),
        .m_arburst_i(m_arburst), .m_arqos_i(m_arqos),
        .m_arvalid_i(m_arvalid), .m_arready_o(m_arready),
        .m_rid_o(m_rid), .m_rdata_o(m_rdata), .m_rresp_o(m_rresp),
        .m_rlast_o(m_rlast), .m_rvalid_o(m_rvalid), .m_rready_i(m_rready),
        .m_read_urgent_i(read_urgent), .m_write_urgent_i(write_urgent),
        .m_read_weight_i(read_weight), .m_write_weight_i(write_weight),
        .m_read_credit_i(read_credit), .m_write_credit_i(write_credit),
        .s_awid_o(s_awid), .s_awaddr_o(s_awaddr), .s_awlen_o(s_awlen),
        .s_awsize_o(s_awsize), .s_awburst_o(s_awburst), .s_awqos_o(s_awqos),
        .s_awvalid_o(s_awvalid), .s_awready_i(s_awready),
        .s_wdata_o(s_wdata), .s_wstrb_o(s_wstrb), .s_wlast_o(s_wlast),
        .s_wvalid_o(s_wvalid), .s_wready_i(s_wready),
        .s_bid_i(s_bid), .s_bresp_i(s_bresp), .s_bvalid_i(s_bvalid),
        .s_bready_o(s_bready), .s_arid_o(s_arid), .s_araddr_o(s_araddr),
        .s_arlen_o(s_arlen), .s_arsize_o(s_arsize),
        .s_arburst_o(s_arburst), .s_arqos_o(s_arqos),
        .s_arvalid_o(s_arvalid), .s_arready_i(s_arready),
        .s_rid_i(s_rid), .s_rdata_i(s_rdata), .s_rresp_i(s_rresp),
        .s_rlast_i(s_rlast), .s_rvalid_i(s_rvalid), .s_rready_o(s_rready),
        .read_outstanding_o(read_outstanding),
        .write_outstanding_o(write_outstanding),
        .read_protocol_error_o(read_protocol_error),
        .write_protocol_error_o(write_protocol_error)
    );

    reg [DDR_ID_W-1:0] read_id_m0;
    reg [DDR_ID_W-1:0] read_id_m1;
    reg [DDR_ID_W-1:0] write_id_m0;
    reg [DDR_ID_W-1:0] write_id_m1;

    initial begin
        checks = 0;
        failures = 0;
        stage = 0;
        rst_n = 1'b0;
        accept = 1'b1;
        m_awid = 0; m_awaddr = 0; m_awlen = 0;
        m_awsize = {NUM_M{3'd5}}; m_awburst = {NUM_M{2'b01}};
        m_awqos = 0; m_awvalid = 0;
        m_wdata = 0; m_wstrb = {NUM_M*STRB_W{1'b1}};
        m_wlast = 0; m_wvalid = 0; m_bready = {NUM_M{1'b1}};
        m_arid = 0; m_araddr = 0; m_arlen = 0;
        m_arsize = {NUM_M{3'd5}}; m_arburst = {NUM_M{2'b01}};
        m_arqos = 0; m_arvalid = 0; m_rready = {NUM_M{1'b1}};
        read_urgent = 0; write_urgent = 0;
        read_weight = {4'd1, 4'd1}; write_weight = {4'd1, 4'd1};
        read_credit = {5'd4, 5'd4}; write_credit = {5'd4, 5'd4};
        read_max_burst = {5'd16, 5'd16};
        write_max_burst = {5'd16, 5'd16};
        s_awready = 1'b0; s_wready = 1'b1;
        s_bid = 0; s_bresp = 0; s_bvalid = 1'b0;
        s_arready = 1'b0; s_rid = 0; s_rdata = 0;
        s_rresp = 0; s_rlast = 0; s_rvalid = 1'b0;

        reset_dut();

        // -----------------------------------------------------------------
        // Read: QoS/urgent arbitration, finite-ID mapping and out-of-order R.
        // -----------------------------------------------------------------
        stage = 1;
        m_arid[0 +: ID_W] = 4'h3;
        m_araddr[0 +: ADDR_W] = 32'h0000_1000;
        m_arlen[0 +: LEN_W] = 0;
        m_arqos[0 +: 4] = 4'd1;
        m_arid[ID_W +: ID_W] = 4'ha;
        m_araddr[ADDR_W +: ADDR_W] = 32'h0000_2000;
        m_arlen[LEN_W +: LEN_W] = 0;
        m_arqos[4 +: 4] = 4'd1;
        read_urgent = 2'b10;
        m_arvalid = 2'b11;
        #1;
        check_true(m_arready == 2'b11, "both AR ingress buffers accept together");
        @(posedge clk); #1;
        m_arvalid = 0;
        #1;
        check_true(s_arvalid && s_araddr == 32'h0000_2000,
                   "urgent master wins the next read burst");
        read_id_m1 = s_arid;
        @(posedge clk); #1;
        read_urgent = 2'b01;
        #1;
        check_true(s_arvalid && s_araddr == 32'h0000_2000 &&
                   s_arid == read_id_m1,
                   "stalled AR payload stays fixed when priority changes");
        read_urgent = 0;
        s_arready = 1'b1;
        @(posedge clk); #1;
        check_true(s_arvalid && s_araddr == 32'h0000_1000,
                   "other buffered read follows without scheduler idle state");
        read_id_m0 = s_arid;
        @(posedge clk); #1;
        s_arready = 1'b0;
        check_true(read_id_m0 != read_id_m1,
                   "concurrent reads receive distinct downstream IDs");

        m_rready[0] = 1'b0;
        return_r(read_id_m0, 256'h1111, 1'b1);
        check_true(m_rvalid[0] && m_rid[0 +: ID_W] == 4'h3 &&
                   m_rdata[0 +: DATA_W] == 256'h1111,
                   "out-of-order read response routes to master zero buffer");
        return_r(read_id_m1, 256'h2222, 1'b1);
        check_true(m_rvalid[1] && m_rid[ID_W +: ID_W] == 4'ha &&
                   m_rdata[DATA_W +: DATA_W] == 256'h2222,
                   "other read response routes independently");
        @(posedge clk); #1;
        check_true(m_rvalid[0], "master zero response survives backpressure");
        m_rready[0] = 1'b1;
        @(posedge clk); #1;
        check_true(!m_rvalid[0] && read_outstanding == 0,
                   "read credits return only after upstream RLAST acceptance");

        // -----------------------------------------------------------------
        // Invalid AR returns a full local DECERR burst and never reaches DDR.
        // -----------------------------------------------------------------
        stage = 2;
        m_rready[0] = 1'b0;
        fork
            send_ar(0, 4'h5, 32'h0000_1004, 8'd1, 4'd0);
        join
        repeat (2) @(posedge clk); #1;
        check_true(!s_arvalid && m_rvalid[0] &&
                   m_rresp[0 +: 2] == 2'b11 && !m_rlast[0],
                   "unaligned AR starts a two-beat local DECERR response");
        m_rready[0] = 1'b1;
        @(posedge clk); #1;
        check_true(m_rvalid[0] && m_rlast[0] &&
                   m_rresp[0 +: 2] == 2'b11,
                   "DECERR burst terminates at ARLEN plus one beats");
        @(posedge clk); #1;
        check_true(!m_rvalid[0], "DECERR response drains cleanly");

        // -----------------------------------------------------------------
        // Write: AW arbitration, W ownership through WLAST and reverse B order.
        // -----------------------------------------------------------------
        stage = 3;
        reset_dut();
        s_awready = 1'b0;
        write_urgent = 2'b10;
        m_awid[0 +: ID_W] = 4'h2;
        m_awaddr[0 +: ADDR_W] = 32'h0000_3000;
        m_awlen[0 +: LEN_W] = 0;
        m_awid[ID_W +: ID_W] = 4'h9;
        m_awaddr[ADDR_W +: ADDR_W] = 32'h0000_4000;
        m_awlen[LEN_W +: LEN_W] = 1;
        m_awvalid = 2'b11;
        #1;
        check_true(m_awready == 2'b11, "both AW ingress buffers accept together");
        @(posedge clk); #1;
        m_awvalid = 0;
        check_true(s_awvalid && s_awaddr == 32'h0000_4000,
                   "urgent write burst is scheduled first");
        write_id_m1 = s_awid;
        s_awready = 1'b1;
        @(posedge clk); #1;
        write_urgent = 0;
        check_true(s_awvalid && s_awaddr == 32'h0000_3000,
                   "second AW issues on the following cycle");
        write_id_m0 = s_awid;
        @(posedge clk); #1;
        s_awready = 1'b0;

        m_wdata[DATA_W +: DATA_W] = 256'ha1;
        m_wdata[0 +: DATA_W] = 256'hb1;
        m_wvalid = 2'b11;
        m_wlast = 2'b00;
        #1;
        check_true(m_wready == 2'b10 && s_wvalid && !s_wlast &&
                   s_wdata == 256'ha1,
                   "W ownership belongs only to first scheduled master");
        @(posedge clk); #1;
        m_wdata[DATA_W +: DATA_W] = 256'ha2;
        m_wlast[1] = 1'b1;
        check_true(s_wvalid && s_wlast,
                   "first write burst presents its expected last beat");
        @(posedge clk); #1;
        m_wlast = 2'b01;
        check_true(m_wready == 2'b01 && s_wvalid && s_wlast &&
                   s_wdata == 256'hb1,
                   "next write burst starts immediately after prior WLAST");
        @(posedge clk); #1;
        m_wvalid = 0;
        m_wlast = 0;

        m_bready[0] = 1'b0;
        return_b(write_id_m0, 2'b00);
        check_true(m_bvalid[0] && m_bid[0 +: ID_W] == 4'h2,
                   "reverse-order B response reaches master zero");
        return_b(write_id_m1, 2'b00);
        check_true(m_bvalid[1] && m_bid[ID_W +: ID_W] == 4'h9,
                   "write ID map preserves master-local BID");
        @(posedge clk); #1;
        m_bready[0] = 1'b1;
        @(posedge clk); #1;
        check_true(write_outstanding == 0,
                   "write credits return after upstream B acceptance");

        // -----------------------------------------------------------------
        // Invalid AW drains W locally and returns DECERR.
        // -----------------------------------------------------------------
        stage = 4;
        m_bready[0] = 1'b0;
        send_aw(0, 4'h6, 32'h0000_5004, 8'd0, 4'd0);
        repeat (2) @(posedge clk); #1;
        check_true(!s_awvalid, "invalid AW is not forwarded to DDR");
        m_wdata[0 +: DATA_W] = 256'hdead;
        m_wlast[0] = 1'b1;
        m_wvalid[0] = 1'b1;
        @(posedge clk);
        while (!m_wready[0]) @(posedge clk);
        #1;
        m_wvalid[0] = 1'b0;
        m_wlast[0] = 1'b0;
        check_true(m_bvalid[0] && m_bid[0 +: ID_W] == 4'h6 &&
                   m_bresp[0 +: 2] == 2'b11,
                   "invalid write drains W and returns local DECERR");
        m_bready[0] = 1'b1;
        @(posedge clk); #1;

        stage = 5;
        accept = 1'b0;
        m_arvalid[0] = 1'b1;
        m_awvalid[0] = 1'b1;
        #1;
        check_true(!m_arready[0] && !m_awready[0],
                   "accept gate blocks new commands without disturbing drain paths");
        m_arvalid = 0;
        m_awvalid = 0;
        check_true(!read_protocol_error && !write_protocol_error,
                   "all legal downstream protocol activity remains clean");

        if (failures == 0)
            $display("DDR_AXI_INTERCONNECT_PASS checks=%0d", checks);
        else
            $fatal(1, "DDR_AXI_INTERCONNECT_FAIL checks=%0d failures=%0d",
                   checks, failures);
        $finish;
    end

    initial begin
        #20000;
        $fatal(1, "DDR AXI interconnect timeout stage=%0d", stage);
    end

endmodule
