// File: tb_axi256_async_bridge.sv
// Spec: edrv32-soc-spec 4.2, 5.2 X9, 5.3; task N-C0; npu-testplan 2.1, SQ-03.
// Description: Ordered five-channel burst traffic with random independent stalls.
//              Single-beat streams measure worst-case channel credit throughput.
// Clock domain: independently generated clk_npu and clk_mem.
`timescale 1ns/1fs
module tb_axi256_async_bridge #(
    parameter integer NPU_MHZ = 150,
    parameter integer MEM_MHZ = 125
);
    reg clk_npu = 0;
    reg clk_mem = 0;
    reg rst_npu_n = 0;
    reg rst_mem_n = 0;
    always #(500.0 / NPU_MHZ) clk_npu <= ~clk_npu;
    always #(500.0 / MEM_MHZ) clk_mem <= ~clk_mem;

    // NPU-side AXI256 interface.
    reg [0:0] s_awid = 0;
    reg [31:0] s_awaddr = 0;
    reg [3:0] s_awlen = 0;
    reg s_awvalid = 0;
    wire s_awready;
    reg [255:0] s_wdata = 0;
    reg [31:0] s_wstrb = 0;
    reg s_wlast = 0;
    reg s_wvalid = 0;
    wire s_wready;
    wire [0:0] s_bid;
    wire [1:0] s_bresp;
    wire s_bvalid;
    reg s_bready = 0;
    reg [0:0] s_arid = 0;
    reg [31:0] s_araddr = 0;
    reg [3:0] s_arlen = 0;
    reg s_arvalid = 0;
    wire s_arready;
    wire [0:0] s_rid;
    wire [255:0] s_rdata;
    wire [1:0] s_rresp;
    wire s_rlast;
    wire s_rvalid;
    reg s_rready = 0;

    // Memory-side AXI256 interface.
    wire [0:0] m_awid;
    wire [31:0] m_awaddr;
    wire [3:0] m_awlen;
    wire m_awvalid;
    reg m_awready = 0;
    wire [255:0] m_wdata;
    wire [31:0] m_wstrb;
    wire m_wlast;
    wire m_wvalid;
    reg m_wready = 0;
    reg [0:0] m_bid = 0;
    reg [1:0] m_bresp = 0;
    reg m_bvalid = 0;
    wire m_bready;
    wire [0:0] m_arid;
    wire [31:0] m_araddr;
    wire [3:0] m_arlen;
    wire m_arvalid;
    reg m_arready = 0;
    reg [0:0] m_rid = 0;
    reg [255:0] m_rdata = 0;
    reg [1:0] m_rresp = 0;
    reg m_rlast = 0;
    reg m_rvalid = 0;
    wire m_rready;

    edrv32_axi256_async_bridge dut (
        // Clocks and resets.
        .clk_npu_i(clk_npu),
        .rst_npu_n_i(rst_npu_n),
        .clk_mem_i(clk_mem),
        .rst_mem_n_i(rst_mem_n),

        // NPU-side AXI256.
        .s_axi_awid_i(s_awid),
        .s_axi_awaddr_i(s_awaddr),
        .s_axi_awlen_i(s_awlen),
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
        .s_axi_arvalid_i(s_arvalid),
        .s_axi_arready_o(s_arready),
        .s_axi_rid_o(s_rid),
        .s_axi_rdata_o(s_rdata),
        .s_axi_rresp_o(s_rresp),
        .s_axi_rlast_o(s_rlast),
        .s_axi_rvalid_o(s_rvalid),
        .s_axi_rready_i(s_rready),

        // Memory-side AXI256.
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
    localparam integer MAX_TX = 4096;
    localparam integer MAX_BEATS = MAX_TX * 16;
    localparam integer WINDOW = 1024;
    reg run = 0;
    reg random_mode = 0;
    reg hold_responses = 0;
    integer tx_count;
    integer w_count;
    integer r_count;
    integer w_completed = 0;
    integer r_started = 0;
    integer seed = 32'h6a1b42;
    reg [36:0] aw_expected [0:MAX_TX-1];
    reg [36:0] ar_expected [0:MAX_TX-1];
    reg [288:0] w_expected [0:MAX_BEATS-1];
    reg [2:0] b_expected [0:MAX_TX-1];
    reg [259:0] r_expected [0:MAX_BEATS-1];

    // Generate legal bursts; response IDs and LAST markers follow their requests.
    task prepare(input integer count_i, input integer random_i);
        integer idx;
        integer beat;
        integer beats;
        integer word_idx;
        reg [255:0] data_value;
        reg [31:0] addr_value;
        reg id_value;
        begin
            tx_count = count_i;
            w_count = 0;
            r_count = 0;
            for (idx = 0; idx < tx_count; idx = idx + 1) begin
                beats = random_i != 0 ? int'($urandom_range(1, 16)) : 1;
                addr_value = ($urandom & 32'hfffff000) | ($urandom_range(0, 112) << 5);
                id_value = 1'($urandom);
                aw_expected[idx] = {id_value, addr_value, 4'(beats - 1)};
                b_expected[idx] = {id_value, ($urandom_range(0, 1) != 0 ? 2'b10 : 2'b00)};
                for (beat = 0; beat < beats; beat = beat + 1) begin
                    for (word_idx = 0; word_idx < 8; word_idx = word_idx + 1)
                        data_value[word_idx*32 +: 32] = $urandom;
                    w_expected[w_count] = {data_value, $urandom, (beat == beats - 1)};
                    w_count = w_count + 1;
                end
                beats = random_i != 0 ? int'($urandom_range(1, 16)) : 1;
                addr_value = ($urandom & 32'hfffff000) | ($urandom_range(0, 112) << 5);
                id_value = 1'($urandom);
                ar_expected[idx] = {id_value, addr_value, 4'(beats - 1)};
                for (beat = 0; beat < beats; beat = beat + 1) begin
                    for (word_idx = 0; word_idx < 8; word_idx = word_idx + 1)
                        data_value[word_idx*32 +: 32] = $urandom;
                    r_expected[r_count] = {id_value, data_value,
                        ($urandom_range(0, 1) != 0 ? 2'b10 : 2'b00), (beat == beats - 1)};
                    r_count = r_count + 1;
                end
            end
        end
    endtask

    task reset_domains;
        begin
            run = 0;
            rst_npu_n = 0;
            rst_mem_n = 0;
            repeat (4) @(negedge clk_mem);
            rst_mem_n = 1;
            repeat (4) @(negedge clk_npu);
            rst_npu_n = 1;
        end
    endtask

    integer aw_sent = 0;
    integer aw_received = 0;
    integer aw_input_stalls = 0;
    integer aw_output_stalls = 0;
    reg [36:0] aw_held;
    reg aw_stalled = 0;
    wire [36:0] aw_output = {m_awid, m_awaddr, m_awlen};
    task drive_aw;
        begin
            while (aw_sent < tx_count) begin
                @(negedge clk_npu);
                if (!random_mode || $urandom_range(0, 3) != 0) begin
                    s_awvalid = 1;
                    {s_awid, s_awaddr, s_awlen} = aw_expected[aw_sent];
                    do @(posedge clk_npu); while (!s_awready);
                    aw_sent = aw_sent + 1;
                end else begin
                    s_awvalid = 0;
                end
            end
            @(negedge clk_npu);
            s_awvalid = 0;
        end
    endtask
    always @(negedge clk_mem) begin
        m_awready <= run && (!random_mode || $urandom_range(0, 1) != 0);
    end
    always @(posedge clk_npu) begin
        if (run && s_awvalid && !s_awready)
            aw_input_stalls <= aw_input_stalls + 1;
    end
    always @(posedge clk_mem or negedge rst_mem_n) begin
        if (!rst_mem_n) begin
            aw_received <= 0;
            aw_stalled <= 0;
        end else if (run) begin
            if (aw_stalled && (!m_awvalid || aw_output !== aw_held))
                $fatal(1, "FAIL aw stalled expected=%h actual=%h valid=%b at %t",
                    aw_held, aw_output, m_awvalid, $time);
            if (m_awvalid && m_awready) begin
                if (aw_received >= aw_sent ||
                    aw_output !== aw_expected[aw_received])
                    $fatal(1, "FAIL aw idx=%0d expected=%h actual=%h at %t",
                        aw_received, aw_expected[aw_received], aw_output, $time);
                aw_received <= aw_received + 1;
            end
            if (m_awvalid && !m_awready)
                aw_output_stalls <= aw_output_stalls + 1;
            aw_stalled <= m_awvalid && !m_awready;
            aw_held <= aw_output;
        end
    end

    integer w_sent = 0;
    integer w_received = 0;
    integer w_input_stalls = 0;
    integer w_output_stalls = 0;
    reg [288:0] w_held;
    reg w_stalled = 0;
    wire [288:0] w_output = {m_wdata, m_wstrb, m_wlast};
    task drive_w;
        begin
            while (w_sent < w_count) begin
                @(negedge clk_npu);
                if (!random_mode || $urandom_range(0, 3) != 0) begin
                    s_wvalid = 1;
                    {s_wdata, s_wstrb, s_wlast} = w_expected[w_sent];
                    do @(posedge clk_npu); while (!s_wready);
                    w_sent = w_sent + 1;
                end else begin
                    s_wvalid = 0;
                end
            end
            @(negedge clk_npu);
            s_wvalid = 0;
        end
    endtask
    always @(negedge clk_mem) begin
        m_wready <= run && (!random_mode || $urandom_range(0, 1) != 0);
    end
    always @(posedge clk_npu) begin
        if (run && s_wvalid && !s_wready)
            w_input_stalls <= w_input_stalls + 1;
    end
    always @(posedge clk_mem or negedge rst_mem_n) begin
        if (!rst_mem_n) begin
            w_received <= 0;
            w_stalled <= 0;
            w_completed <= 0;
        end else if (run) begin
            if (w_stalled && (!m_wvalid || w_output !== w_held))
                $fatal(1, "FAIL w stalled expected=%h actual=%h valid=%b at %t",
                    w_held, w_output, m_wvalid, $time);
            if (m_wvalid && m_wready) begin
                if (w_received >= w_sent ||
                    w_output !== w_expected[w_received])
                    $fatal(1, "FAIL w idx=%0d expected=%h actual=%h at %t",
                        w_received, w_expected[w_received], w_output, $time);
                w_received <= w_received + 1;
                if (m_wlast) w_completed <= w_completed + 1;
            end
            if (m_wvalid && !m_wready)
                w_output_stalls <= w_output_stalls + 1;
            w_stalled <= m_wvalid && !m_wready;
            w_held <= w_output;
        end
    end

    integer b_sent = 0;
    integer b_received = 0;
    integer b_input_stalls = 0;
    integer b_output_stalls = 0;
    reg [2:0] b_held;
    reg b_stalled = 0;
    wire [2:0] b_output = {s_bid, s_bresp};
    task drive_b;
        begin
            while (b_sent < tx_count) begin
                @(negedge clk_mem);
                if ((!random_mode || $urandom_range(0, 3) != 0) &&
                    aw_received > b_sent && w_completed > b_sent) begin
                    m_bvalid = 1;
                    {m_bid, m_bresp} = b_expected[b_sent];
                    do @(posedge clk_mem); while (!m_bready);
                    b_sent = b_sent + 1;
                end else begin
                    m_bvalid = 0;
                end
            end
            @(negedge clk_mem);
            m_bvalid = 0;
        end
    endtask
    always @(negedge clk_npu) begin
        s_bready <= run && !hold_responses && (!random_mode || $urandom_range(0, 1) != 0);
    end
    always @(posedge clk_mem) begin
        if (run && m_bvalid && !m_bready)
            b_input_stalls <= b_input_stalls + 1;
    end
    always @(posedge clk_npu or negedge rst_npu_n) begin
        if (!rst_npu_n) begin
            b_received <= 0;
            b_stalled <= 0;
        end else if (run) begin
            if (b_stalled && (!s_bvalid || b_output !== b_held))
                $fatal(1, "FAIL b stalled expected=%h actual=%h valid=%b at %t",
                    b_held, b_output, s_bvalid, $time);
            if (s_bvalid && s_bready) begin
                if (b_received >= b_sent ||
                    b_output !== b_expected[b_received])
                    $fatal(1, "FAIL b idx=%0d expected=%h actual=%h at %t",
                        b_received, b_expected[b_received], b_output, $time);
                b_received <= b_received + 1;
            end
            if (s_bvalid && !s_bready)
                b_output_stalls <= b_output_stalls + 1;
            b_stalled <= s_bvalid && !s_bready;
            b_held <= b_output;
        end
    end

    integer ar_sent = 0;
    integer ar_received = 0;
    integer ar_input_stalls = 0;
    integer ar_output_stalls = 0;
    reg [36:0] ar_held;
    reg ar_stalled = 0;
    wire [36:0] ar_output = {m_arid, m_araddr, m_arlen};
    task drive_ar;
        begin
            while (ar_sent < tx_count) begin
                @(negedge clk_npu);
                if (!random_mode || $urandom_range(0, 3) != 0) begin
                    s_arvalid = 1;
                    {s_arid, s_araddr, s_arlen} = ar_expected[ar_sent];
                    do @(posedge clk_npu); while (!s_arready);
                    ar_sent = ar_sent + 1;
                end else begin
                    s_arvalid = 0;
                end
            end
            @(negedge clk_npu);
            s_arvalid = 0;
        end
    endtask
    always @(negedge clk_mem) begin
        m_arready <= run && (!random_mode || $urandom_range(0, 1) != 0);
    end
    always @(posedge clk_npu) begin
        if (run && s_arvalid && !s_arready)
            ar_input_stalls <= ar_input_stalls + 1;
    end
    always @(posedge clk_mem or negedge rst_mem_n) begin
        if (!rst_mem_n) begin
            ar_received <= 0;
            ar_stalled <= 0;
        end else if (run) begin
            if (ar_stalled && (!m_arvalid || ar_output !== ar_held))
                $fatal(1, "FAIL ar stalled expected=%h actual=%h valid=%b at %t",
                    ar_held, ar_output, m_arvalid, $time);
            if (m_arvalid && m_arready) begin
                if (ar_received >= ar_sent ||
                    ar_output !== ar_expected[ar_received])
                    $fatal(1, "FAIL ar idx=%0d expected=%h actual=%h at %t",
                        ar_received, ar_expected[ar_received], ar_output, $time);
                ar_received <= ar_received + 1;
            end
            if (m_arvalid && !m_arready)
                ar_output_stalls <= ar_output_stalls + 1;
            ar_stalled <= m_arvalid && !m_arready;
            ar_held <= ar_output;
        end
    end

    integer r_sent = 0;
    integer r_received = 0;
    integer r_input_stalls = 0;
    integer r_output_stalls = 0;
    reg [259:0] r_held;
    reg r_stalled = 0;
    wire [259:0] r_output = {s_rid, s_rdata, s_rresp, s_rlast};
    task drive_r;
        begin
            while (r_sent < r_count) begin
                @(negedge clk_mem);
                if ((!random_mode || $urandom_range(0, 3) != 0) && ar_received > r_started) begin
                    m_rvalid = 1;
                    {m_rid, m_rdata, m_rresp, m_rlast} = r_expected[r_sent];
                    do @(posedge clk_mem); while (!m_rready);
                    if (m_rlast) r_started = r_started + 1;
                    r_sent = r_sent + 1;
                end else begin
                    m_rvalid = 0;
                end
            end
            @(negedge clk_mem);
            m_rvalid = 0;
        end
    endtask
    always @(negedge clk_npu) begin
        s_rready <= run && !hold_responses && (!random_mode || $urandom_range(0, 1) != 0);
    end
    always @(posedge clk_mem) begin
        if (run && m_rvalid && !m_rready)
            r_input_stalls <= r_input_stalls + 1;
    end
    always @(posedge clk_npu or negedge rst_npu_n) begin
        if (!rst_npu_n) begin
            r_received <= 0;
            r_stalled <= 0;
        end else if (run) begin
            if (r_stalled && (!s_rvalid || r_output !== r_held))
                $fatal(1, "FAIL r stalled expected=%h actual=%h valid=%b at %t",
                    r_held, r_output, s_rvalid, $time);
            if (s_rvalid && s_rready) begin
                if (r_received >= r_sent ||
                    r_output !== r_expected[r_received])
                    $fatal(1, "FAIL r idx=%0d expected=%h actual=%h at %t",
                        r_received, r_expected[r_received], r_output, $time);
                r_received <= r_received + 1;
            end
            if (s_rvalid && !s_rready)
                r_output_stalls <= r_output_stalls + 1;
            r_stalled <= s_rvalid && !s_rready;
            r_held <= r_output;
        end
    end

    wire clk_slow = NPU_MHZ <= MEM_MHZ ? clk_npu : clk_mem;
    wire aw_slow_transfer = NPU_MHZ <= MEM_MHZ ?
        (s_awvalid && s_awready) : (m_awvalid && m_awready);
    integer aw_measured = 0;
    wire w_slow_transfer = NPU_MHZ <= MEM_MHZ ?
        (s_wvalid && s_wready) : (m_wvalid && m_wready);
    integer w_measured = 0;
    wire b_slow_transfer = NPU_MHZ <= MEM_MHZ ?
        (s_bvalid && s_bready) : (m_bvalid && m_bready);
    integer b_measured = 0;
    wire ar_slow_transfer = NPU_MHZ <= MEM_MHZ ?
        (s_arvalid && s_arready) : (m_arvalid && m_arready);
    integer ar_measured = 0;
    wire r_slow_transfer = NPU_MHZ <= MEM_MHZ ?
        (s_rvalid && s_rready) : (m_rvalid && m_rready);
    integer r_measured = 0;
    task measure_throughput;
        integer cycle;
        begin
            // Let all five request/response paths reach steady state before sampling.
            repeat (128) @(negedge clk_slow);
            for (cycle = 0; cycle < WINDOW; cycle = cycle + 1) begin
                @(posedge clk_slow);
                if (!aw_slow_transfer)
                    $fatal(1, "FAIL aw throughput bubble slow cycle=%0d at %t", cycle, $time);
                aw_measured = aw_measured + int'(aw_slow_transfer);
                if (!w_slow_transfer)
                    $fatal(1, "FAIL w throughput bubble slow cycle=%0d at %t", cycle, $time);
                w_measured = w_measured + int'(w_slow_transfer);
                if (!b_slow_transfer)
                    $fatal(1, "FAIL b throughput bubble slow cycle=%0d at %t", cycle, $time);
                b_measured = b_measured + int'(b_slow_transfer);
                if (!ar_slow_transfer)
                    $fatal(1, "FAIL ar throughput bubble slow cycle=%0d at %t", cycle, $time);
                ar_measured = ar_measured + int'(ar_slow_transfer);
                if (!r_slow_transfer)
                    $fatal(1, "FAIL r throughput bubble slow cycle=%0d at %t", cycle, $time);
                r_measured = r_measured + int'(r_slow_transfer);
            end
            $display("THROUGHPUT npu=%0d mem=%0d slow_cycles=%0d W=%0d R=%0d AW=%0d AR=%0d B=%0d",
                NPU_MHZ, MEM_MHZ, WINDOW, w_measured, r_measured,
                aw_measured, ar_measured, b_measured);
        end
    endtask

    task run_phase(input integer random_i);
        begin
            reset_domains();
            random_mode = (random_i != 0);
            hold_responses = random_mode;
            prepare(random_mode ? 512 : MAX_TX, random_i);
            aw_sent = 0;
            w_sent = 0;
            b_sent = 0;
            ar_sent = 0;
            r_sent = 0;
            aw_input_stalls = 0;
            aw_output_stalls = 0;
            w_input_stalls = 0;
            w_output_stalls = 0;
            b_input_stalls = 0;
            b_output_stalls = 0;
            ar_input_stalls = 0;
            ar_output_stalls = 0;
            r_input_stalls = 0;
            r_output_stalls = 0;
            r_started = 0;
            @(negedge clk_npu);
            run = 1;
            fork
                drive_aw();
                drive_w();
                drive_b();
                drive_ar();
                drive_r();
                begin
                    if (!random_mode) begin
                        measure_throughput();
                    end else begin
                        // Fill response FIFOs even though random bursts return B infrequently.
                        repeat (512) @(negedge clk_slow);
                        hold_responses = 0;
                    end
                end
            join
            wait (aw_received == tx_count && ar_received == tx_count &&
                b_received == tx_count && w_received == w_count && r_received == r_count);
            // Keep monitors active after draining to catch any duplicated trailing beat.
            repeat (16) @(negedge clk_slow);
            $display("PHASE random=%0d AW=%0d W=%0d B=%0d AR=%0d R=%0d",
                random_i, aw_received, w_received, b_received, ar_received, r_received);
        end
    endtask

    initial begin
        void'($urandom(seed));
        run_phase(0);
        run_phase(1);
        if (aw_input_stalls == 0 || aw_output_stalls == 0)
            $fatal(1, "FAIL aw random backpressure coverage input=%0d output=%0d",
                aw_input_stalls, aw_output_stalls);
        $display("STALLS aw input=%0d output=%0d", aw_input_stalls, aw_output_stalls);
        if (w_input_stalls == 0 || w_output_stalls == 0)
            $fatal(1, "FAIL w random backpressure coverage input=%0d output=%0d",
                w_input_stalls, w_output_stalls);
        $display("STALLS w input=%0d output=%0d", w_input_stalls, w_output_stalls);
        if (b_input_stalls == 0 || b_output_stalls == 0)
            $fatal(1, "FAIL b random backpressure coverage input=%0d output=%0d",
                b_input_stalls, b_output_stalls);
        $display("STALLS b input=%0d output=%0d", b_input_stalls, b_output_stalls);
        if (ar_input_stalls == 0 || ar_output_stalls == 0)
            $fatal(1, "FAIL ar random backpressure coverage input=%0d output=%0d",
                ar_input_stalls, ar_output_stalls);
        $display("STALLS ar input=%0d output=%0d", ar_input_stalls, ar_output_stalls);
        if (r_input_stalls == 0 || r_output_stalls == 0)
            $fatal(1, "FAIL r random backpressure coverage input=%0d output=%0d",
                r_input_stalls, r_output_stalls);
        $display("STALLS r input=%0d output=%0d", r_input_stalls, r_output_stalls);
        $display("PASS axi256_async_bridge npu=%0d mem=%0d: ordered bursts and full throughput",
            NPU_MHZ, MEM_MHZ);
        $finish;
    end
endmodule
