// File: tb_axi_async_bridge.sv
// Spec: mem-subsys-testplan 3.1 GW-01--GW-05; edrv32-soc-spec 4.1, 5.2, 5.3.
// Description: Self-checking directed and random AXI traffic with independent backpressure.
// Clock domain: independently generated clk_sys and clk_mem.
`timescale 1ns/1ps
module tb_axi_async_bridge #(
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
    wire [3:0] m_awid;
    wire [31:0] m_awaddr;
    wire [7:0] m_awlen;
    wire [2:0] m_awsize;
    wire [1:0] m_awburst;
    wire m_awvalid;
    reg m_awready = 0;
    wire [63:0] m_wdata;
    wire [7:0] m_wstrb;
    wire m_wlast;
    wire m_wvalid;
    reg m_wready = 0;
    reg [3:0] m_bid = 0;
    reg [1:0] m_bresp = 0;
    reg m_bvalid = 0;
    wire m_bready;
    wire [3:0] m_arid;
    wire [31:0] m_araddr;
    wire [7:0] m_arlen;
    wire [2:0] m_arsize;
    wire [1:0] m_arburst;
    wire m_arvalid;
    reg m_arready = 0;
    reg [3:0] m_rid = 0;
    reg [63:0] m_rdata = 0;
    reg [1:0] m_rresp = 0;
    reg m_rlast = 0;
    reg m_rvalid = 0;
    wire m_rready;
    edrv32_axi_async_bridge dut (
        .clk_sys_i(clk_sys),
        .rst_sys_n_i(rst_sys_n),
        .clk_mem_i(clk_mem),
        .rst_mem_n_i(rst_mem_n),
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
        .m_axi_awsize_o(m_awsize),
        .m_axi_awburst_o(m_awburst),
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
        .m_axi_arsize_o(m_arsize),
        .m_axi_arburst_o(m_arburst),
        .m_axi_arvalid_o(m_arvalid),
        .m_axi_arready_i(m_arready),
        .m_axi_rid_i(m_rid),
        .m_axi_rdata_i(m_rdata),
        .m_axi_rresp_i(m_rresp),
        .m_axi_rlast_i(m_rlast),
        .m_axi_rvalid_i(m_rvalid),
        .m_axi_rready_o(m_rready)
    );
    localparam integer COUNT = 256;
    reg run = 0;
    integer seed = 32'h6a1b42;
    integer seed_result;
    task reset_domains;
        begin
            rst_sys_n = 0;
            rst_mem_n = 0;
            repeat (3) @(negedge clk_mem);
            rst_mem_n = 1;
            repeat (3) @(negedge clk_sys);
            rst_sys_n = 1;
        end
    endtask
    integer aw_sent = 0;
    integer aw_received = 0;
    reg [48:0] aw_held;
    reg aw_stalled = 0;
    function automatic [48:0] aw_value(input integer idx);
        aw_value = (49'b1 << (idx % 49)) ^
            ((idx/49)%2 == 0 ? 49'b0 : {49{1'b1}});
    endfunction
    wire [48:0] aw_output = {m_awid, m_awaddr, m_awlen, m_awsize, m_awburst};
    task drive_aw;
        begin
            while (aw_sent < COUNT) begin
                @(negedge clk_sys);
                if ($urandom_range(0, 3) != 0) begin
                    s_awvalid = 1;
                    {s_awid, s_awaddr, s_awlen, s_awsize, s_awburst} = aw_value(aw_sent);
                    do @(posedge clk_sys); while (!s_awready);
                    aw_sent = aw_sent + 1;
                    @(negedge clk_sys);
                    s_awvalid = 0;
                end
            end
        end
    endtask
    always @(negedge clk_mem) begin
        m_awready = run && ($urandom_range(0, 3) != 0);
    end
    always @(posedge clk_mem) begin
        if (!rst_mem_n) begin
            aw_received = 0;
            aw_stalled = 0;
        end else if (run) begin
            if (aw_stalled && (!m_awvalid || aw_output !== aw_held))
                $fatal(1, "FAIL aw changed while stalled at %t", $time);
            if (m_awvalid && m_awready) begin
                if (aw_output !== aw_value(aw_received))
                    $fatal(1, "FAIL aw idx=%0d expected=%h actual=%h at %t",
                           aw_received, aw_value(aw_received), aw_output, $time);
                aw_received = aw_received + 1;
            end
            aw_stalled = m_awvalid && !m_awready;
            aw_held = aw_output;
        end
    end
    integer w_sent = 0;
    integer w_received = 0;
    reg [72:0] w_held;
    reg w_stalled = 0;
    function automatic [72:0] w_value(input integer idx);
        w_value = (73'b1 << (idx % 73)) ^
            ((idx/73)%2 == 0 ? 73'b0 : {73{1'b1}});
    endfunction
    wire [72:0] w_output = {m_wdata, m_wstrb, m_wlast};
    task drive_w;
        begin
            while (w_sent < COUNT) begin
                @(negedge clk_sys);
                if ($urandom_range(0, 3) != 0) begin
                    s_wvalid = 1;
                    {s_wdata, s_wstrb, s_wlast} = w_value(w_sent);
                    do @(posedge clk_sys); while (!s_wready);
                    w_sent = w_sent + 1;
                    @(negedge clk_sys);
                    s_wvalid = 0;
                end
            end
        end
    endtask
    always @(negedge clk_mem) begin
        m_wready = run && ($urandom_range(0, 3) != 0);
    end
    always @(posedge clk_mem) begin
        if (!rst_mem_n) begin
            w_received = 0;
            w_stalled = 0;
        end else if (run) begin
            if (w_stalled && (!m_wvalid || w_output !== w_held))
                $fatal(1, "FAIL w changed while stalled at %t", $time);
            if (m_wvalid && m_wready) begin
                if (w_output !== w_value(w_received))
                    $fatal(1, "FAIL w idx=%0d expected=%h actual=%h at %t",
                           w_received, w_value(w_received), w_output, $time);
                w_received = w_received + 1;
            end
            w_stalled = m_wvalid && !m_wready;
            w_held = w_output;
        end
    end
    integer b_sent = 0;
    integer b_received = 0;
    reg [5:0] b_held;
    reg b_stalled = 0;
    function automatic [5:0] b_value(input integer idx);
        b_value = (6'b1 << (idx % 6)) ^
            ((idx/6)%2 == 0 ? 6'b0 : {6{1'b1}});
    endfunction
    wire [5:0] b_output = {s_bid, s_bresp};
    task drive_b;
        begin
            while (b_sent < COUNT) begin
                @(negedge clk_mem);
                if ($urandom_range(0, 3) != 0) begin
                    m_bvalid = 1;
                    {m_bid, m_bresp} = b_value(b_sent);
                    do @(posedge clk_mem); while (!m_bready);
                    b_sent = b_sent + 1;
                    @(negedge clk_mem);
                    m_bvalid = 0;
                end
            end
        end
    endtask
    always @(negedge clk_sys) begin
        s_bready = run && ($urandom_range(0, 3) != 0);
    end
    always @(posedge clk_sys) begin
        if (!rst_sys_n) begin
            b_received = 0;
            b_stalled = 0;
        end else if (run) begin
            if (b_stalled && (!s_bvalid || b_output !== b_held))
                $fatal(1, "FAIL b changed while stalled at %t", $time);
            if (s_bvalid && s_bready) begin
                if (b_output !== b_value(b_received))
                    $fatal(1, "FAIL b idx=%0d expected=%h actual=%h at %t",
                           b_received, b_value(b_received), b_output, $time);
                b_received = b_received + 1;
            end
            b_stalled = s_bvalid && !s_bready;
            b_held = b_output;
        end
    end
    integer ar_sent = 0;
    integer ar_received = 0;
    reg [48:0] ar_held;
    reg ar_stalled = 0;
    function automatic [48:0] ar_value(input integer idx);
        ar_value = (49'b1 << (idx % 49)) ^
            ((idx/49)%2 == 0 ? 49'b0 : {49{1'b1}});
    endfunction
    wire [48:0] ar_output = {m_arid, m_araddr, m_arlen, m_arsize, m_arburst};
    task drive_ar;
        begin
            while (ar_sent < COUNT) begin
                @(negedge clk_sys);
                if ($urandom_range(0, 3) != 0) begin
                    s_arvalid = 1;
                    {s_arid, s_araddr, s_arlen, s_arsize, s_arburst} = ar_value(ar_sent);
                    do @(posedge clk_sys); while (!s_arready);
                    ar_sent = ar_sent + 1;
                    @(negedge clk_sys);
                    s_arvalid = 0;
                end
            end
        end
    endtask
    always @(negedge clk_mem) begin
        m_arready = run && ($urandom_range(0, 3) != 0);
    end
    always @(posedge clk_mem) begin
        if (!rst_mem_n) begin
            ar_received = 0;
            ar_stalled = 0;
        end else if (run) begin
            if (ar_stalled && (!m_arvalid || ar_output !== ar_held))
                $fatal(1, "FAIL ar changed while stalled at %t", $time);
            if (m_arvalid && m_arready) begin
                if (ar_output !== ar_value(ar_received))
                    $fatal(1, "FAIL ar idx=%0d expected=%h actual=%h at %t",
                           ar_received, ar_value(ar_received), ar_output, $time);
                ar_received = ar_received + 1;
            end
            ar_stalled = m_arvalid && !m_arready;
            ar_held = ar_output;
        end
    end
    integer r_sent = 0;
    integer r_received = 0;
    reg [70:0] r_held;
    reg r_stalled = 0;
    function automatic [70:0] r_value(input integer idx);
        r_value = (71'b1 << (idx % 71)) ^
            ((idx/71)%2 == 0 ? 71'b0 : {71{1'b1}});
    endfunction
    wire [70:0] r_output = {s_rid, s_rdata, s_rresp, s_rlast};
    task drive_r;
        begin
            while (r_sent < COUNT) begin
                @(negedge clk_mem);
                if ($urandom_range(0, 3) != 0) begin
                    m_rvalid = 1;
                    {m_rid, m_rdata, m_rresp, m_rlast} = r_value(r_sent);
                    do @(posedge clk_mem); while (!m_rready);
                    r_sent = r_sent + 1;
                    @(negedge clk_mem);
                    m_rvalid = 0;
                end
            end
        end
    endtask
    always @(negedge clk_sys) begin
        s_rready = run && ($urandom_range(0, 3) != 0);
    end
    always @(posedge clk_sys) begin
        if (!rst_sys_n) begin
            r_received = 0;
            r_stalled = 0;
        end else if (run) begin
            if (r_stalled && (!s_rvalid || r_output !== r_held))
                $fatal(1, "FAIL r changed while stalled at %t", $time);
            if (s_rvalid && s_rready) begin
                if (r_output !== r_value(r_received))
                    $fatal(1, "FAIL r idx=%0d expected=%h actual=%h at %t",
                           r_received, r_value(r_received), r_output, $time);
                r_received = r_received + 1;
            end
            r_stalled = s_rvalid && !s_rready;
            r_held = r_output;
        end
    end
    initial begin
        seed_result = $urandom(seed);
        reset_domains();
        // Populate all FIFOs with stale traffic, then reset both ends and prove it is discarded.
        s_awvalid = 1;
        s_wvalid = 1;
        s_arvalid = 1;
        m_bvalid = 1;
        m_rvalid = 1;
        repeat (12) @(negedge clk_mem);
        if (s_awready || s_wready || s_arready || m_bready || m_rready)
            $fatal(1, "FAIL depth-2 FIFOs did not become full");
        s_awvalid = 0;
        s_wvalid = 0;
        s_arvalid = 0;
        m_bvalid = 0;
        m_rvalid = 0;
        reset_domains();
        repeat (4) @(negedge clk_mem);
        if (m_awvalid !== 0 || m_wvalid !== 0 || m_arvalid !== 0 ||
            s_bvalid !== 0 || s_rvalid !== 0)
            $fatal(1, "FAIL reset retained stale valid or produced X");
        run = 1;
        fork
            drive_aw();
            drive_w();
            drive_ar();
            drive_b();
            drive_r();
        join
        wait (aw_received == COUNT && w_received == COUNT && ar_received == COUNT &&
              b_received == COUNT && r_received == COUNT);
        $display("PASS axi_async_bridge sys=%0d mem=%0d: 5 x %0d ordered payloads, stalls/reset",
                 SYS_MHZ, MEM_MHZ, COUNT);
        $finish;
    end
    initial begin
        #200000;
        $fatal(1, "FAIL timeout");
    end
endmodule
