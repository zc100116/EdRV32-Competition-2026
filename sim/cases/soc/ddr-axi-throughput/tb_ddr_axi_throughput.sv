`timescale 1ns/1ps

module tb_ddr_axi_throughput;
    localparam NUM_M = 2;
    localparam ADDR_W = 32;
    localparam DATA_W = 256;
    localparam ID_W = 4;
    localparam DDR_ID_W = 4;
    localparam LEN_W = 8;
    localparam COUNT_W = DDR_ID_W + 1;
    localparam REQUESTS = 12;
    localparam SLOT_REQUESTS = (1 << DDR_ID_W);

    reg clk;
    reg rst_n;
    reg accept;
    integer checks;
    integer failures;
    integer accepted_m0;
    integer accepted_m1;
    integer issue_i;
    integer expected_master;
    integer response_master;
    reg [NUM_M-1:0] ready_sample;

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
    reg [NUM_M*4-1:0] read_weight;
    reg [NUM_M*5-1:0] read_credit;
    reg [NUM_M*5-1:0] read_max_burst;

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

    wire [NUM_M*COUNT_W-1:0] outstanding;
    wire protocol_error;

    reg [DDR_ID_W-1:0] issued_id [0:SLOT_REQUESTS-1];
    reg issued_master [0:SLOT_REQUESTS-1];

    initial clk = 1'b0;
    always #5 clk = ~clk;

    task automatic check_true;
        input condition;
        input [8*120-1:0] message;
        begin
            checks = checks + 1;
            if (!condition) begin
                failures = failures + 1;
                $display("FAIL issue=%0d: %0s", issue_i, message);
            end
        end
    endtask

    edrv32_axi_m2s_read #(
        .NUM_M(NUM_M),
        .ADDR_W(ADDR_W),
        .DATA_W(DATA_W),
        .ID_W(ID_W),
        .S_ID_W(DDR_ID_W),
        .LEN_W(LEN_W),
        .STARVE_CYCLES(32),
        .COUNT_W(COUNT_W)
    ) dut (
        .clk_i(clk),
        .rst_n_i(rst_n),
        .accept_i(accept),
        .m_arid_i(m_arid),
        .m_araddr_i(m_araddr),
        .m_arlen_i(m_arlen),
        .m_arsize_i(m_arsize),
        .m_arburst_i(m_arburst),
        .m_arqos_i(m_arqos),
        .m_arvalid_i(m_arvalid),
        .m_arready_o(m_arready),
        .m_rid_o(m_rid),
        .m_rdata_o(m_rdata),
        .m_rresp_o(m_rresp),
        .m_rlast_o(m_rlast),
        .m_rvalid_o(m_rvalid),
        .m_rready_i(m_rready),
        .m_read_urgent_i(read_urgent),
        .m_read_weight_i(read_weight),
        .m_read_credit_i(read_credit),
        .s_arid_o(s_arid),
        .s_araddr_o(s_araddr),
        .s_arlen_o(s_arlen),
        .s_arsize_o(s_arsize),
        .s_arburst_o(s_arburst),
        .s_arqos_o(s_arqos),
        .s_arvalid_o(s_arvalid),
        .s_arready_i(s_arready),
        .s_rid_i(s_rid),
        .s_rdata_i(s_rdata),
        .s_rresp_i(s_rresp),
        .s_rlast_i(s_rlast),
        .s_rvalid_i(s_rvalid),
        .s_rready_o(s_rready),
        .outstanding_o(outstanding),
        .protocol_error_o(protocol_error)
    );

    initial begin
        checks = 0;
        failures = 0;
        accepted_m0 = 0;
        accepted_m1 = 0;
        issue_i = 0;
        rst_n = 1'b0;
        accept = 1'b1;
        m_arid = 0;
        m_araddr = {32'h0000_2000, 32'h0000_1000};
        m_arlen = 0;
        m_arsize = {NUM_M{3'd5}};
        m_arburst = {NUM_M{2'b01}};
        m_arqos = 0;
        m_arvalid = 0;
        m_rready = {NUM_M{1'b1}};
        read_urgent = 0;
        read_weight = {4'd2, 4'd1};
        read_credit = {5'd16, 5'd16};
        read_max_burst = {5'd16, 5'd16};
        s_arready = 1'b1;
        s_rid = 0;
        s_rdata = 0;
        s_rresp = 0;
        s_rlast = 1'b0;
        s_rvalid = 1'b0;

        repeat (3) @(posedge clk);
        #1 rst_n = 1'b1;
        @(posedge clk); #1;

        // Four commands from M0 and eight from M1 are kept available. With
        // weights 1:2 the downstream AR channel must transfer every cycle.
        m_arvalid = 2'b11;
        #1;
        check_true(m_arready == 2'b11,
                   "both empty ingress buffers accept the first command");
        @(posedge clk); #1;
        accepted_m0 = 1;
        accepted_m1 = 1;
        m_arid[0 +: ID_W] = 4'd1;
        m_araddr[0 +: ADDR_W] = 32'h0000_1020;
        m_arid[ID_W +: ID_W] = 4'd1;
        m_araddr[ADDR_W +: ADDR_W] = 32'h0000_2020;

        for (issue_i = 0; issue_i < REQUESTS; issue_i = issue_i + 1) begin
            @(negedge clk);
            check_true(s_arvalid,
                       "ARVALID remains asserted with no scheduler bubble");
            expected_master = ((issue_i % 3) == 0) ? 0 : 1;
            check_true((expected_master == 0 && s_araddr[15:12] == 4'h1) ||
                       (expected_master == 1 && s_araddr[15:12] == 4'h2),
                       "weighted round-robin produces the 1:2 service pattern");
            issued_id[issue_i] = s_arid;
            issued_master[issue_i] = expected_master[0];
            ready_sample = m_arready;

            @(posedge clk);
            #1;
            if (ready_sample[0] && m_arvalid[0]) begin
                accepted_m0 = accepted_m0 + 1;
                if (accepted_m0 == 4) begin
                    m_arvalid[0] = 1'b0;
                end else begin
                    m_arid[0 +: ID_W] = accepted_m0[ID_W-1:0];
                    m_araddr[0 +: ADDR_W] = 32'h0000_1000 + accepted_m0*32;
                end
            end
            if (ready_sample[1] && m_arvalid[1]) begin
                accepted_m1 = accepted_m1 + 1;
                if (accepted_m1 == 8) begin
                    m_arvalid[1] = 1'b0;
                end else begin
                    m_arid[ID_W +: ID_W] = accepted_m1[ID_W-1:0];
                    m_araddr[ADDR_W +: ADDR_W] =
                        32'h0000_2000 + accepted_m1*32;
                end
            end
        end

        check_true(accepted_m0 == 4 && accepted_m1 == 8,
                   "the finite source streams are accepted exactly once");
        check_true(outstanding[0 +: COUNT_W] == 5'd4 &&
                   outstanding[COUNT_W +: COUNT_W] == 5'd8,
                   "outstanding accounting matches all accepted commands");

        // Feed one single-beat completion every cycle. Consecutive responses
        // for the same master exercise response-buffer pop plus replacement.
        for (issue_i = 0; issue_i < REQUESTS; issue_i = issue_i + 1) begin
            @(negedge clk);
            s_rid = issued_id[issue_i];
            s_rdata = issue_i;
            s_rresp = 2'b00;
            s_rlast = 1'b1;
            s_rvalid = 1'b1;
            #1;
            check_true(s_rready,
                       "RREADY remains asserted with no response-buffer bubble");
            @(posedge clk); #1;
            response_master = issued_master[issue_i];
            check_true(m_rvalid[response_master] &&
                       m_rdata[response_master*DATA_W +: DATA_W] == issue_i,
                       "each continuous response reaches its recorded owner");
        end
        s_rvalid = 1'b0;
        s_rlast = 1'b0;
        @(posedge clk); #1;

        check_true(outstanding == 0,
                   "all credits return after the continuous response stream");
        check_true(!protocol_error,
                   "continuous traffic completes without protocol errors");

        // Fill all downstream ID slots. A returned ID enters the registered
        // free queue and becomes available on the following cycle, cutting the
        // response-to-request combinational path without reducing steady-state
        // allocation throughput.
        rst_n = 1'b0;
        m_arvalid = 0;
        s_rvalid = 1'b0;
        repeat (3) @(posedge clk);
        #1 rst_n = 1'b1;
        @(posedge clk); #1;

        accepted_m0 = 0;
        accepted_m1 = 0;
        read_weight = {4'd1, 4'd1};
        m_arid = 0;
        m_araddr = {32'h0000_5000, 32'h0000_4000};
        m_arvalid = 2'b11;
        #1;
        check_true(m_arready == 2'b11,
                   "slot-fill streams enter both empty buffers");
        @(posedge clk); #1;
        accepted_m0 = 1;
        accepted_m1 = 1;
        m_arid[0 +: ID_W] = 4'd1;
        m_araddr[0 +: ADDR_W] = 32'h0000_4020;
        m_arid[ID_W +: ID_W] = 4'd1;
        m_araddr[ADDR_W +: ADDR_W] = 32'h0000_5020;

        for (issue_i = 0; issue_i < SLOT_REQUESTS; issue_i = issue_i + 1) begin
            @(negedge clk);
            check_true(s_arvalid,
                       "all ID slots fill without an AR bubble");
            expected_master = issue_i % 2;
            check_true((expected_master == 0 && s_araddr[15:12] == 4'h4) ||
                       (expected_master == 1 && s_araddr[15:12] == 4'h5),
                       "equal weights alternate while filling the ID table");
            issued_id[issue_i] = s_arid;
            issued_master[issue_i] = expected_master[0];
            ready_sample = m_arready;

            @(posedge clk); #1;
            if (ready_sample[0] && m_arvalid[0]) begin
                accepted_m0 = accepted_m0 + 1;
                if (accepted_m0 == 8) begin
                    m_arvalid[0] = 1'b0;
                end else begin
                    m_arid[0 +: ID_W] = accepted_m0[ID_W-1:0];
                    m_araddr[0 +: ADDR_W] =
                        32'h0000_4000 + accepted_m0*32;
                end
            end
            if (ready_sample[1] && m_arvalid[1]) begin
                accepted_m1 = accepted_m1 + 1;
                if (accepted_m1 == 8) begin
                    m_arvalid[1] = 1'b0;
                end else begin
                    m_arid[ID_W +: ID_W] = accepted_m1[ID_W-1:0];
                    m_araddr[ADDR_W +: ADDR_W] =
                        32'h0000_5000 + accepted_m1*32;
                end
            end
        end

        m_arid[0 +: ID_W] = 4'd8;
        m_araddr[0 +: ADDR_W] = 32'h0000_4100;
        m_arvalid[0] = 1'b1;
        #1;
        check_true(m_arready[0],
                   "an extra command can wait in the ingress buffer");
        @(posedge clk); #1;
        m_arvalid[0] = 1'b0;
        check_true(!s_arvalid,
                   "a genuinely full ID table blocks issue before retirement");

        s_rid = issued_id[0];
        s_rdata = 256'hcafe;
        s_rresp = 2'b00;
        s_rlast = 1'b1;
        s_rvalid = 1'b1;
        #1;
        check_true(s_rready && !s_arvalid,
                   "a full ID table does not bypass RLAST into AR scheduling");
        @(posedge clk); #1;
        s_rvalid = 1'b0;
        check_true(m_rvalid[0] && m_rdata[0 +: DATA_W] == 256'hcafe,
                   "the retiring response remains visible upstream");
        check_true(s_arvalid && s_arid == issued_id[0] &&
                   s_araddr == 32'h0000_4100,
                   "the registered free ID is presented in the next cycle");

        @(posedge clk); #1;
        check_true(!s_arvalid,
                   "the replacement command is accepted without an extra bubble");

        @(negedge clk);
        s_rid = issued_id[0];
        s_rdata = 256'hbeef;
        s_rvalid = 1'b1;
        #1;
        check_true(s_rready,
                   "the recycled ID immediately names the replacement route");
        @(posedge clk); #1;
        s_rvalid = 1'b0;
        check_true(m_rvalid[0] && m_rid[0 +: ID_W] == 4'd8 &&
                   m_rdata[0 +: DATA_W] == 256'hbeef,
                   "the replacement response uses the new local ID mapping");
        check_true(!protocol_error,
                   "registered ID recycling preserves protocol state");

        if (failures == 0)
            $display("DDR_AXI_THROUGHPUT_PASS checks=%0d ar_cycles=%0d r_cycles=%0d slot_cycles=%0d",
                     checks, REQUESTS, REQUESTS, SLOT_REQUESTS);
        else
            $fatal(1, "DDR_AXI_THROUGHPUT_FAIL checks=%0d failures=%0d",
                   checks, failures);
        $finish;
    end

    initial begin
        #20000;
        $fatal(1, "DDR AXI throughput timeout issue=%0d", issue_i);
    end

endmodule
