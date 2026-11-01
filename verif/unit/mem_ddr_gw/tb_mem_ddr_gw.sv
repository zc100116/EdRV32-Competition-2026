// File: tb_mem_ddr_gw.sv
// Spec: mem-subsys-testplan 3.1 GW-01--GW-05; edrv32-soc-spec 4.1, 5.2, 5.3.
// Description: Self-checking directed and random AXI traffic with independent backpressure.
// Clock domain: independently generated clk_sys and clk_mem.
`timescale 1ns/1ps
module tb_mem_ddr_gw #(
    parameter integer SYS_MHZ = 150,
    parameter integer MEM_MHZ = 125,
    parameter integer FULL = 0
);
    reg clk_sys = 0;
    reg clk_mem = 0;
    reg rst_sys_n = 0;
    reg rst_mem_n = 0;
    always #(500.0 / SYS_MHZ) clk_sys = ~clk_sys;
    always #(500.0 / MEM_MHZ) clk_mem = ~clk_mem;
    reg [3:0] s_awid = 0;
    reg [31:0] s_awaddr = 0;
    reg [7:0] s_awlen = 0;
    reg [2:0] s_awsize = 0;
    reg [1:0] s_awburst = 0;
    reg s_awvalid = 0;
    wire s_awready;
    reg [63:0] s_wdata = 0;
    reg [7:0] s_wstrb = 0;
    reg s_wlast = 0;
    reg s_wvalid = 0;
    wire s_wready;
    wire [3:0] s_bid;
    wire [1:0] s_bresp;
    wire s_bvalid;
    reg s_bready = 0;
    reg [3:0] s_arid = 0;
    reg [31:0] s_araddr = 0;
    reg [7:0] s_arlen = 0;
    reg [2:0] s_arsize = 0;
    reg [1:0] s_arburst = 0;
    reg s_arvalid = 0;
    wire s_arready;
    wire [3:0] s_rid;
    wire [63:0] s_rdata;
    wire [1:0] s_rresp;
    wire s_rlast;
    wire s_rvalid;
    reg s_rready = 0;
    wire m_awid;
    wire [31:0] m_awaddr;
    wire [3:0] m_awlen;
    wire m_awvalid;
    reg m_awready = 0;
    wire [255:0] m_wdata;
    wire [31:0] m_wstrb;
    wire m_wlast;
    wire m_wvalid;
    reg m_wready = 0;
    reg m_bid = 0;
    reg [1:0] m_bresp = 0;
    reg m_bvalid = 0;
    wire m_bready;
    wire m_arid;
    wire [31:0] m_araddr;
    wire [3:0] m_arlen;
    wire m_arvalid;
    reg m_arready = 0;
    reg m_rid = 0;
    reg [255:0] m_rdata = 0;
    reg [1:0] m_rresp = 0;
    reg m_rlast = 0;
    reg m_rvalid = 0;
    wire m_rready;
    edrv32_mem_ddr_gw dut (
        .clk_sys_i(clk_sys),
        .rst_sys_n_i(rst_sys_n),
        .clk_mem_i(clk_mem),
        .rst_mem_n_i({3{rst_mem_n}}),
        .s_axi_awid_i(s_awid),
        .s_axi_awaddr_i(s_awaddr),
        .s_axi_awlen_i(s_awlen),
        .s_axi_awsize_i(s_awsize),
        .s_axi_awburst_i(s_awburst),
        .s_axi_awvalid_i(s_awvalid),
        .s_axi_awready_o(s_awready),
        .s_axi_wdata_i(s_wdata),
        .s_axi_wstrb_i(s_wstrb),
        .s_axi_wlast_i(s_wlast),
        .s_axi_wvalid_i(s_wvalid),
        .s_axi_wready_o(s_wready),
        .s_axi_bid_o(s_bid),
        .s_axi_bresp_o(s_bresp),
        .s_axi_bvalid_o(s_bvalid),
        .s_axi_bready_i(s_bready),
        .s_axi_arid_i(s_arid),
        .s_axi_araddr_i(s_araddr),
        .s_axi_arlen_i(s_arlen),
        .s_axi_arsize_i(s_arsize),
        .s_axi_arburst_i(s_arburst),
        .s_axi_arvalid_i(s_arvalid),
        .s_axi_arready_o(s_arready),
        .s_axi_rid_o(s_rid),
        .s_axi_rdata_o(s_rdata),
        .s_axi_rresp_o(s_rresp),
        .s_axi_rlast_o(s_rlast),
        .s_axi_rvalid_o(s_rvalid),
        .s_axi_rready_i(s_rready),
        .m_axi_awid_o(m_awid),
        .m_axi_awaddr_o(m_awaddr),
        .m_axi_awlen_o(m_awlen),
        .m_axi_awvalid_o(m_awvalid),
        .m_axi_awready_i(m_awready),
        .m_axi_wdata_o(m_wdata),
        .m_axi_wstrb_o(m_wstrb),
        .m_axi_wlast_o(m_wlast),
        .m_axi_wvalid_o(m_wvalid),
        .m_axi_wready_i(m_wready),
        .m_axi_bid_i(m_bid),
        .m_axi_bresp_i(m_bresp),
        .m_axi_bvalid_i(m_bvalid),
        .m_axi_bready_o(m_bready),
        .m_axi_arid_o(m_arid),
        .m_axi_araddr_o(m_araddr),
        .m_axi_arlen_o(m_arlen),
        .m_axi_arvalid_o(m_arvalid),
        .m_axi_arready_i(m_arready),
        .m_axi_rid_i(m_rid),
        .m_axi_rdata_i(m_rdata),
        .m_axi_rresp_i(m_rresp),
        .m_axi_rlast_i(m_rlast),
        .m_axi_rvalid_i(m_rvalid),
        .m_axi_rready_o(m_rready)
    );
    reg [7:0] memory [0:4095];
    reg [7:0] reference_mem [0:4095];
    reg random_stalls = 0;
    reg [1:0] response_code = 0;
    reg aw_saved = 0;
    reg w_saved = 0;
    reg [31:0] saved_awaddr;
    reg [255:0] saved_wdata;
    reg [31:0] saved_wstrb;
    reg [31:0] expected_awaddr;
    reg [31:0] expected_araddr;
    reg [255:0] expected_wdata;
    reg [31:0] expected_wstrb;
    integer downstream_aw = 0;
    integer downstream_ar = 0;
    integer downstream_w = 0;
    integer sys_cycles = 0;
    integer start_cycle;
    integer measured_latency;
    integer seed = 32'h5f82a91;
    integer seed_result;
    integer k;
    integer n;
    integer sz;
    integer pos;
    integer txn_count = 0;
    integer latency_min = 100000;
    integer latency_max = 0;
    reg [31:0] random_addr;
    reg [63:0] random_data;
    reg read_owned = 0;
    reg write_owned = 0;
    integer parent_write_left = 0;
    reg [63:0] beat_data [0:255];
    reg ar_stalled = 0;
    reg aw_stalled = 0;
    reg w_stalled = 0;
    reg r_stalled = 0;
    reg b_stalled = 0;
    reg [36:0] held_ar;
    reg [36:0] held_aw;
    reg [288:0] held_w;
    reg [70:0] held_r;
    reg [5:0] held_b;

    always @(posedge clk_sys) begin
        sys_cycles <= sys_cycles + 1;
        if (!rst_sys_n) begin
            read_owned = 0;
            write_owned = 0;
            parent_write_left = 0;
            r_stalled = 0;
            b_stalled = 0;
        end else begin
            if (s_arvalid && s_arready) begin
                if (read_owned) $fatal(1, "FAIL accepted two parent reads before RLAST");
                read_owned = 1;
            end
            if (s_awvalid && s_awready) begin
                if (write_owned) $fatal(1, "FAIL accepted two parent writes before B");
                write_owned = 1;
                parent_write_left = int'(s_awlen) + 1;
            end
            if (s_wvalid && s_wready) parent_write_left = parent_write_left - 1;
            if (s_bvalid && parent_write_left != 0)
                $fatal(1, "FAIL B before all parent W beats accepted: %0d left",parent_write_left);
            if (s_rvalid && s_rready && s_rlast) read_owned = 0;
            if (s_bvalid && s_bready) write_owned = 0;
            if (r_stalled && (!s_rvalid || {s_rid,s_rdata,s_rresp,s_rlast} !== held_r))
                $fatal(1, "FAIL upstream R payload changed during backpressure");
            if (b_stalled && (!s_bvalid || {s_bid,s_bresp} !== held_b))
                $fatal(1, "FAIL upstream B payload changed during backpressure");
            r_stalled = s_rvalid && !s_rready;
            b_stalled = s_bvalid && !s_bready;
            held_r = {s_rid,s_rdata,s_rresp,s_rlast};
            held_b = {s_bid,s_bresp};
        end
    end

    // Simple independently backpressured AXI256 slave; first R is available after AR edge.
    always @(negedge clk_mem) begin
        m_awready = rst_mem_n && !aw_saved && !m_bvalid &&
                    (!random_stalls || $urandom_range(0, 2) != 0);
        m_wready = rst_mem_n && !w_saved && !m_bvalid &&
                   (!random_stalls || $urandom_range(0, 2) != 0);
        m_arready = rst_mem_n && !m_rvalid &&
                    (!random_stalls || $urandom_range(0, 2) != 0);
    end
    always @(posedge clk_mem) begin
        if (!rst_mem_n) begin
            aw_saved <= 0;
            w_saved <= 0;
            m_bvalid <= 0;
            m_rvalid <= 0;
            downstream_aw <= 0;
            downstream_w <= 0;
            downstream_ar <= 0;
            ar_stalled = 0;
            aw_stalled = 0;
            w_stalled = 0;
        end else begin
            if (ar_stalled && (!m_arvalid || {m_arid,m_araddr,m_arlen} !== held_ar))
                $fatal(1, "FAIL downstream AR changed during backpressure");
            if (aw_stalled && (!m_awvalid || {m_awid,m_awaddr,m_awlen} !== held_aw))
                $fatal(1, "FAIL downstream AW changed during backpressure");
            if (w_stalled && (!m_wvalid || {m_wdata,m_wstrb,m_wlast} !== held_w))
                $fatal(1, "FAIL downstream W changed during backpressure");
            ar_stalled = m_arvalid && !m_arready;
            aw_stalled = m_awvalid && !m_awready;
            w_stalled = m_wvalid && !m_wready;
            held_ar = {m_arid,m_araddr,m_arlen};
            held_aw = {m_awid,m_awaddr,m_awlen};
            held_w = {m_wdata,m_wstrb,m_wlast};
            if (m_awvalid && m_awready) begin
                if (m_awid !== 0 || m_awlen !== 0 || m_awaddr !== expected_awaddr)
                    $fatal(1, "FAIL AW expected=%h actual=%h id=%h len=%h at %t",
                           expected_awaddr,m_awaddr,m_awid,m_awlen,$time);
                saved_awaddr <= m_awaddr;
                aw_saved <= 1;
                downstream_aw <= downstream_aw + 1;
            end
            if (m_wvalid && m_wready) begin
                if (!m_wlast || m_wstrb !== expected_wstrb)
                    $fatal(1, "FAIL W strobe expected=%h actual=%h last=%b",
                           expected_wstrb,m_wstrb,m_wlast);
                for (integer j = 0; j < 32; j = j + 1)
                    if (expected_wstrb[j] && m_wdata[j*8 +: 8] !== expected_wdata[j*8 +: 8])
                        $fatal(1, "FAIL W byte=%0d expected=%h actual=%h",j,
                               expected_wdata[j*8 +: 8],m_wdata[j*8 +: 8]);
                saved_wdata <= m_wdata;
                saved_wstrb <= m_wstrb;
                w_saved <= 1;
                downstream_w <= downstream_w + 1;
            end
            if (aw_saved && w_saved && !m_bvalid) begin
                for (integer j = 0; j < 32; j = j + 1)
                    if (saved_wstrb[j]) memory[saved_awaddr+j] <= saved_wdata[j*8 +: 8];
                m_bresp <= response_code;
                m_bid <= 0;
                m_bvalid <= 1;
                aw_saved <= 0;
                w_saved <= 0;
            end
            if (m_bvalid && m_bready) m_bvalid <= 0;
            if (m_arvalid && m_arready) begin
                if (m_arid !== 0 || m_arlen !== 0 || m_araddr !== expected_araddr)
                    $fatal(1, "FAIL AR expected=%h actual=%h id=%h len=%h",
                           expected_araddr,m_araddr,m_arid,m_arlen);
                for (integer j = 0; j < 32; j = j + 1)
                    m_rdata[j*8 +: 8] <= memory[m_araddr+j];
                m_rresp <= response_code;
                m_rid <= 0;
                m_rlast <= 1;
                m_rvalid <= 1;
                downstream_ar <= downstream_ar + 1;
            end
            if (m_rvalid && m_rready) m_rvalid <= 0;
        end
    end
    task reset_domains;
        begin
            rst_sys_n = 0;
            rst_mem_n = 0;
            repeat (3) @(negedge clk_mem);
            if (m_awvalid !== 0 || m_wvalid !== 0 || m_arvalid !== 0)
                $fatal(1, "FAIL gateway issued a transaction during reset");
            rst_mem_n = 1;
            repeat (3) @(negedge clk_sys);
            rst_sys_n = 1;
        end
    endtask
    function automatic [63:0] reference_lane(input [31:0] address);
        integer base;
        begin
            base = int'(address & 32'hff8);
            for (integer j = 0; j < 8; j = j + 1)
                reference_lane[j*8 +: 8] = reference_mem[base+j];
        end
    endfunction
    task send_ar(input [31:0] address, input [7:0] len, input [2:0] size,
                 input [1:0] burst, input [3:0] id);
        begin
            @(negedge clk_sys);
            s_araddr = address;
            s_arlen = len;
            s_arsize = size;
            s_arburst = burst;
            s_arid = id;
            s_arvalid = 1;
            do @(posedge clk_sys); while (!s_arready);
            start_cycle = sys_cycles;
            @(negedge clk_sys);
            s_arvalid = 0;
        end
    endtask
    task get_r(input [31:0] address, input [7:0] len, input [3:0] id,
               input [1:0] resp, input integer legal);
        reg [63:0] expected;
        begin
            for (integer j = 0; j <= int'(len); j = j + 1) begin
                @(negedge clk_sys);
                s_rready = 0;
                if (random_stalls) repeat ($urandom_range(0, 8)) @(negedge clk_sys);
                s_rready = 1;
                do @(posedge clk_sys); while (!s_rvalid);
                expected = legal != 0 ? reference_lane(address + 32'(j*8)) : 64'd0;
                if (s_rid !== id || s_rresp !== resp || s_rlast !== (j == int'(len)) ||
                    (legal != 0 && s_rdata !== expected))
                    $fatal(1, "FAIL R beat=%0d id=%h/%h resp=%h/%h last=%b data=%h/%h at %t",
                           j,s_rid,id,s_rresp,resp,s_rlast,s_rdata,expected,$time);
            end
            measured_latency = sys_cycles - start_cycle;
            @(negedge clk_sys);
            s_rready = 0;
        end
    endtask
    task send_aw(input [31:0] address, input [7:0] len, input [2:0] size,
                 input [1:0] burst, input [3:0] id);
        begin
            @(negedge clk_sys);
            s_awaddr = address;
            s_awlen = len;
            s_awsize = size;
            s_awburst = burst;
            s_awid = id;
            s_awvalid = 1;
            do @(posedge clk_sys); while (!s_awready);
            @(negedge clk_sys);
            s_awvalid = 0;
        end
    endtask
    task send_w(input [7:0] len);
        begin
            for (integer j = 0; j <= int'(len); j = j + 1) begin
                @(negedge clk_sys);
                if (random_stalls) repeat ($urandom_range(0, 3)) @(negedge clk_sys);
                s_wdata = beat_data[j];
                s_wstrb = 8'hff;
                s_wlast = (j == int'(len));
                s_wvalid = 1;
                do @(posedge clk_sys); while (!s_wready);
                @(negedge clk_sys);
                s_wvalid = 0;
            end
        end
    endtask
    task get_b(input [3:0] id, input [1:0] resp);
        begin
            @(negedge clk_sys);
            s_bready = 0;
            if (random_stalls) repeat ($urandom_range(0, 12)) @(negedge clk_sys);
            s_bready = 1;
            do @(posedge clk_sys); while (!s_bvalid);
            if (s_bid !== id || s_bresp !== resp)
                $fatal(1, "FAIL B id=%h/%h resp=%h/%h at %t",s_bid,id,s_bresp,resp,$time);
            @(negedge clk_sys);
            s_bready = 0;
        end
    endtask
    task prepare_write(input [31:0] address, input [7:0] len, input [2:0] size,
                       input [63:0] data);
        integer lane;
        begin
            expected_awaddr = address & 32'h3fff_ffe0;
            expected_wdata = 0;
            expected_wstrb = 0;
            for (integer j = 0; j <= int'(len); j = j + 1) begin
                beat_data[j] = data ^ (64'h1a2b3c4d5e6f7091 * 64'(j));
                lane = (int'(address[4:3]) + j) % 4;
                expected_wdata[lane*64 +: 64] = beat_data[j];
            end
            if (len == 3) expected_wstrb = 32'hffff_ffff;
            else for (integer j = 0; j < (1 << size); j = j + 1)
                expected_wstrb[int'(address[4:0])+j] = 1;
        end
    endtask
    task write_txn(input [31:0] address, input [7:0] len, input [2:0] size,
                   input [1:0] burst, input [3:0] id, input integer legal,
                   input [63:0] data);
        integer before_aw;
        integer before_w;
        begin
            before_aw = downstream_aw;
            before_w = downstream_w;
            // Illegal transactions do not use the conversion expectation.
            if (legal != 0) prepare_write(address,len,size,data);
            else for (integer j = 0; j <= int'(len); j = j + 1) beat_data[j] = data;
            send_aw(address,len,size,burst,id);
            send_w(len);
            get_b(id,legal != 0 ? response_code : 2'b10);
            if (downstream_aw != before_aw + legal || downstream_w != before_w + legal)
                $fatal(1, "FAIL illegal write escaped or legal write missing");
            if (legal != 0) for (integer j = 0; j < 32; j = j + 1)
                if (expected_wstrb[j]) reference_mem[expected_awaddr+j] = expected_wdata[j*8 +: 8];
            txn_count = txn_count + 1;
        end
    endtask
    task read_txn(input [31:0] address, input [7:0] len, input [2:0] size,
                  input [1:0] burst, input [3:0] id, input integer legal);
        integer before_ar;
        begin
            before_ar = downstream_ar;
            expected_araddr = address & 32'h3fff_ffe0;
            send_ar(address,len,size,burst,id);
            get_r(address,len,id,legal != 0 ? response_code : 2'b10,legal);
            if (downstream_ar != before_ar + legal)
                $fatal(1, "FAIL illegal read escaped or legal read missing");
            txn_count = txn_count + 1;
        end
    endtask

    // GW-04: present a second same-direction request while responses are blocked.
    // The opposite direction must still finish, proving independent ownership.
    task outstanding_test;
        integer before_ar;
        integer before_aw;
        begin
            random_stalls = 0;
            expected_araddr = 0;
            send_ar(32'h80000000,3,3,1,4'ha);
            wait (s_rvalid);
            before_ar = downstream_ar;
            @(negedge clk_sys);
            s_arvalid = 1;
            s_arid = 4'hb;
            repeat (20) begin
                @(posedge clk_sys);
                if (s_arready || downstream_ar != before_ar)
                    $fatal(1, "FAIL second read accepted before upstream response");
            end
            // A write completes while the read response is held.
            write_txn(32'hc0000040,3,3,1,4'hc,1,64'h0123456789abcdef);
            get_r(32'h80000000,3,4'ha,0,1);
            do @(posedge clk_sys); while (!s_arready);
            @(negedge clk_sys);
            s_arvalid = 0;
            get_r(32'h80000000,3,4'hb,0,1);

            prepare_write(32'h80000080,3,3,64'h98abcdef76543210);
            send_aw(32'h80000080,3,3,1,4'hd);
            send_w(3);
            wait (s_bvalid);
            for (integer j = 0; j < 32; j = j + 1)
                reference_mem[expected_awaddr+j] = expected_wdata[j*8 +: 8];
            before_aw = downstream_aw;
            @(negedge clk_sys);
            s_awvalid = 1;
            s_awid = 4'he;
            repeat (20) begin
                @(posedge clk_sys);
                if (s_awready || downstream_aw != before_aw)
                    $fatal(1, "FAIL second write accepted before upstream response");
            end
            // A read completes while the write response is held.
            read_txn(32'hc0000080,3,3,1,4'hf,1);
            get_b(4'hd,0);
            do @(posedge clk_sys); while (!s_awready);
            @(negedge clk_sys);
            s_awvalid = 0;
            send_w(3);
            get_b(4'he,0);
        end
    endtask

    initial begin
        seed_result = $urandom(seed);
        for (k = 0; k < 4096; k = k + 1) begin
            memory[k] = 0;
            reference_mem[k] = 0;
        end
        reset_domains();
        // GW-01: both virtual windows share one physical line, little-endian lanes.
        write_txn(32'h80000000,3,3,1,1,1,64'hffeeddccbbaa9988);
        read_txn(32'hc0000000,3,3,1,2,1);
        write_txn(32'hc0000020,3,3,1,3,1,64'h123456789abcdef0);
        read_txn(32'h80000020,3,3,1,4,1);
        // Zero-wait cache line latency over varying request phases.
        for (n = 0; n < 24; n = n + 1) begin
            repeat (n % 5) @(negedge clk_sys);
            read_txn(32'h80000000,3,3,1,4'(n),1);
            if (measured_latency < latency_min) latency_min = measured_latency;
            if (measured_latency > latency_max) latency_max = measured_latency;
        end
        $display("LATENCY sys=%0d MHz mem=%0d MHz S6 AR->last R: min=%0d max=%0d sys cycles",
                 SYS_MHZ,MEM_MHZ,latency_min,latency_max);
        // GW-02: every natural byte position for each SIZE, alternating windows.
        for (sz = 0; sz <= 3; sz = sz + 1) begin
            for (pos = 0; pos < 32; pos = pos + (1 << sz)) begin
                write_txn(32'hc0000100+32'(pos),0,3'(sz),1,4'(pos),1,
                          64'hc9f537a28e0416bd ^ 64'(pos));
                read_txn(32'h80000100+32'(pos),0,3'(sz),1,4'(pos+1),1);
            end
        end
        // GW-03: unsupported lengths/sizes, alignment and all non-INCR BURST values.
        for (n = 1; n <= 7; n = n + 1) begin
            if (n != 3) begin
                write_txn(32'h80000200,8'(n),3,1,4'(n),0,64'h1234);
                read_txn(32'hc0000200,8'(n),3,1,4'(n+1),0);
            end
        end
        write_txn(32'h80000200,255,3,1,4'hf,0,0);
        read_txn(32'h80000200,255,3,1,4'he,0);
        for (n = 0; n <= 3; n = n + 1) begin
            if (n != 1) begin
                write_txn(32'h80000200,0,2,2'(n),4'(n),0,0);
                read_txn(32'h80000200,3,3,2'(n),4'(n),0);
                write_txn(32'h80000200,3,3,2'(n),4'(n),0,0);
                read_txn(32'h80000200,0,2,2'(n),4'(n),0);
            end
        end
        for (sz = 0; sz <= 7; sz = sz + 1) begin
            if (sz > 3) begin
                write_txn(32'h80000200,0,3'(sz),1,4'(sz),0,0);
                read_txn(32'h80000200,0,3'(sz),1,4'(sz),0);
            end else if (sz != 0) begin
                write_txn(32'h80000201,0,3'(sz),1,4'(sz),0,0);
                read_txn(32'h80000201,0,3'(sz),1,4'(sz),0);
            end
            if (sz != 3) begin
                write_txn(32'h80000200,3,3'(sz),1,4'(sz),0,0);
                read_txn(32'h80000200,3,3'(sz),1,4'(sz),0);
            end
        end
        write_txn(32'h80000208,3,3,1,0,0,0);
        read_txn(32'h80000208,3,3,1,0,0);
        // Downstream error codes must propagate unchanged, including all four cache R beats.
        for (n = 0; n < 4; n = n + 1) begin
            response_code = 2'(n);
            write_txn(32'h80000300,3,3,1,4'(n),1,64'h9876543210012345);
            read_txn(32'hc0000300,3,3,1,4'(n+4),1);
        end
        response_code = 0;
        random_stalls = 1;
        // Force CDC FIFO full/empty and payload stability with upper-side response stalls.
        for (n = 0; n < 8; n = n + 1) begin
            write_txn(32'h80000320,3,3,1,4'(n),1,64'(n));
            read_txn(32'hc0000320,3,3,1,4'(n+8),1);
        end
        if (FULL != 0) begin
            outstanding_test();
            random_stalls = 1;
            // GW-05: random addresses, aliases, widths, payloads, IDs and both-side stalls.
            for (n = 0; n < 160; n = n + 1) begin
                sz = int'($urandom_range(0,3));
                random_addr = ($urandom_range(0,1) != 0 ? 32'hc0000000 : 32'h80000000)
                              | ($urandom_range(0,2047) & ~((32'd1 << sz)-1));
                random_data = {$urandom,$urandom};
                response_code = 2'($urandom_range(0,3));
                if (n % 4 == 0) begin
                    random_addr = random_addr & 32'hffffffe0;
                    write_txn(random_addr,3,3,1,4'(n),1,random_data);
                    read_txn(random_addr ^ 32'h40000000,3,3,1,4'(n+1),1);
                end else begin
                    write_txn(random_addr,0,3'(sz),1,4'(n),1,random_data);
                    read_txn(random_addr ^ 32'h40000000,0,3'(sz),1,4'(n+1),1);
                end
            end
        end
        // Reset with both directions active; stale FIFO payloads must not reappear.
        random_stalls = 0;
        response_code = 0;
        expected_araddr = 0;
        send_ar(32'h80000000,3,3,1,1);
        prepare_write(32'h80000000,3,3,64'h12345678);
        send_aw(32'h80000000,3,3,1,2);
        send_w(3);
        wait (s_rvalid && s_bvalid);
        reset_domains();
        repeat (8) @(negedge clk_sys);
        if (s_rvalid !== 0 || s_bvalid !== 0)
            $fatal(1, "FAIL reset left stale response or X");
        // Reinitialize the reference after the deliberately abandoned write.
        for (k = 0; k < 4096; k = k + 1) reference_mem[k] = memory[k];
        write_txn(32'hc0000000,3,3,1,7,1,64'h13579bdf2468ace0);
        read_txn(32'h80000000,3,3,1,8,1);
        $display("PASS mem_ddr_gw GW-01/02/03%s: %0d checked transactions sys=%0d mem=%0d",
                 FULL != 0 ? "/04/05" : "",txn_count,SYS_MHZ,MEM_MHZ);
        $finish;
    end
    initial begin
        #500000;
        $fatal(1, "FAIL timeout");
    end
endmodule
