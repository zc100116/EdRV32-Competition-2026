// File: edrv32_cpu_b2_tb.sv
// Spec: cpu-testplan 2.2, 3.8; cpu-spec 3.1-3.3, 7.1.
// Description: Execute software through the real CPU/cache subsystem and shared AXI memory.
//              Check AXI contracts, observe committed tohost and print performance windows.
// Clock domain: clk_sys.
/* verilator lint_off BLKSEQ */
module edrv32_cpu_b2_tb #(parameter RVC_EN = 1);
    import edrv32_axi64_memory_pkg::*;
    bit clk_i = 0;
    /* verilator lint_off SYNCASYNCNET */
    bit rst_n_i = 0;
    /* verilator lint_on SYNCASYNCNET */
    always #5 clk_i = !clk_i;
    edrv32_axi64_if ibus();
    edrv32_axi64_if dbus();
    int unsigned read_latency_w = 2;
    longint unsigned cycles_r = 0;
    longint unsigned timeout_w = 100000000;
    logic [63:0] debug_w;
    logic unused_irq_w;
    logic [31:0] unused_apb_prdata_w;
    logic unused_apb_pready_w;
    logic unused_apb_pslverr_w;
    bit [31:0] tohost_addr_w;
    bit [31:0] console_addr_w = 32'h40007000;
    bit [31:0] bus_write_addr_r;
    bit [31:0] store_addr_r;
    longint unsigned total_events_r [0:15];
    bit store_r;
    bit store_seen_r;
    bit [31:0] begin_pc_w [0:1];
    bit [31:0] end_pc_w [0:1];
    bit enabled_w [0:1];
    bit measuring_r [0:1];
    longint unsigned start_cycle_r [0:1];
    longint unsigned start_instret_r [0:1];
    longint unsigned events_r [0:1][0:15];
    longint unsigned start_hpm_r [0:1][0:7];
    string image;

    edrv32_cpu_subsys #(
        .RVC_EN(RVC_EN)
    ) u_dut (
        // Clock and reset.
        .clk_i(clk_i),
        .rst_n_i(rst_n_i),

        // I$ AXI64 read master.
        .iaxi_arid_o(ibus.arid),
        .iaxi_araddr_o(ibus.araddr),
        .iaxi_arlen_o(ibus.arlen),
        .iaxi_arsize_o(ibus.arsize),
        .iaxi_arburst_o(ibus.arburst),
        .iaxi_arvalid_o(ibus.arvalid),
        .iaxi_arready_i(ibus.arready),
        .iaxi_rid_i(ibus.rid),
        .iaxi_rdata_i(ibus.rdata),
        .iaxi_rresp_i(ibus.rresp),
        .iaxi_rlast_i(ibus.rlast),
        .iaxi_rvalid_i(ibus.rvalid),
        .iaxi_rready_o(ibus.rready),

        // D$ AXI64 read/write master.
        .daxi_awid_o(dbus.awid),
        .daxi_awaddr_o(dbus.awaddr),
        .daxi_awlen_o(dbus.awlen),
        .daxi_awsize_o(dbus.awsize),
        .daxi_awburst_o(dbus.awburst),
        .daxi_awvalid_o(dbus.awvalid),
        .daxi_awready_i(dbus.awready),
        .daxi_wdata_o(dbus.wdata),
        .daxi_wstrb_o(dbus.wstrb),
        .daxi_wlast_o(dbus.wlast),
        .daxi_wvalid_o(dbus.wvalid),
        .daxi_wready_i(dbus.wready),
        .daxi_bid_i(dbus.bid),
        .daxi_bresp_i(dbus.bresp),
        .daxi_bvalid_i(dbus.bvalid),
        .daxi_bready_o(dbus.bready),
        .daxi_arid_o(dbus.arid),
        .daxi_araddr_o(dbus.araddr),
        .daxi_arlen_o(dbus.arlen),
        .daxi_arsize_o(dbus.arsize),
        .daxi_arburst_o(dbus.arburst),
        .daxi_arvalid_o(dbus.arvalid),
        .daxi_arready_i(dbus.arready),
        .daxi_rid_i(dbus.rid),
        .daxi_rdata_i(dbus.rdata),
        .daxi_rresp_i(dbus.rresp),
        .daxi_rlast_i(dbus.rlast),
        .daxi_rvalid_i(dbus.rvalid),
        .daxi_rready_o(dbus.rready),

        // APB cache-control slave.
        .apb_paddr_i(12'b0),
        .apb_psel_i(1'b0),
        .apb_penable_i(1'b0),
        .apb_pwrite_i(1'b0),
        .apb_pwdata_i(32'b0),
        .apb_pstrb_i(4'b0),
        .apb_pready_o(unused_apb_pready_w),
        .apb_prdata_o(unused_apb_prdata_w),
        .apb_pslverr_o(unused_apb_pslverr_w),

        // Interrupts, CLINT time and debug.
        .irq_meip_i(1'b0),
        .irq_msip_i(1'b0),
        .irq_mtip_i(1'b0),
        .mtime_i(cycles_r),
        .debug_o(debug_w),
        .irq_o(unused_irq_w)
    );
    // I side has no write channels. Both memories use memory_pkg::memory.
    assign ibus.awid = 0;
    assign ibus.awaddr = 0;
    assign ibus.awlen = 0;
    assign ibus.awsize = 0;
    assign ibus.awburst = 0;
    assign ibus.awvalid = 0;
    assign ibus.wdata = 0;
    assign ibus.wstrb = 0;
    assign ibus.wlast = 0;
    assign ibus.wvalid = 0;
    assign ibus.bready = 1;
    edrv32_cpu_b2_memory u_imem (
        .clk_i(clk_i),
        .rst_n_i(rst_n_i),
        .read_latency_i(read_latency_w),
        .bus(ibus)
    );
    edrv32_cpu_b2_memory u_dmem (
        .clk_i(clk_i),
        .rst_n_i(rst_n_i),
        .read_latency_i(read_latency_w),
        .bus(dbus)
    );
    edrv32_axi64_checker #(.INSTRUCTION(1)) u_icheck (
        .clk_i(clk_i),
        .rst_n_i(rst_n_i),
        .bus(ibus)
    );
    edrv32_axi64_checker u_dcheck (
        .clk_i(clk_i),
        .rst_n_i(rst_n_i),
        .bus(dbus)
    );

    task automatic load_image(input string path, input bit [31:0] base);
        integer fd;
        integer parsed;
        string token;
        bit [31:0] addr;
        bit [31:0] value;
        fd = $fopen(path, "r");
        if (fd == 0) $fatal(1, "FAIL cannot open image %s", path);
        addr = base;
        while ($fscanf(fd, "%s", token) == 1) begin
            if (token.substr(0, 0) == "@") begin
                parsed = $sscanf(token, "@%h", value);
                addr = base + value;
            end else begin
                parsed = $sscanf(token, "%h", value);
                if (parsed != 1) $fatal(1, "FAIL invalid hex token %s in %s", token, path);
                bus_store(addr, value[7:0]);
                addr++;
            end
        end
        $fclose(fd);
    endtask

    initial begin
        random_stalls = 0;
        delay_max = 0;
        void'($value$plusargs("READ_LATENCY=%d", read_latency_w));
        void'($value$plusargs("TIMEOUT=%d", timeout_w));
        if (!$value$plusargs("TOHOST=%h", tohost_addr_w))
            $fatal(1, "FAIL +TOHOST=<ELF symbol address> required");
        if ($value$plusargs("MEM_HEX=%s", image)) load_image(image, 0);
        if ($value$plusargs("ROM_HEX=%s", image)) load_image(image, 32'h00000000);
        if ($value$plusargs("SRAM_HEX=%s", image)) load_image(image, 32'h10000000);
        if ($value$plusargs("DDR_HEX=%s", image)) load_image(image, 32'h80000000);
        // The small test-only device register bank is byte-addressable shared memory.
        for (int i = 0; i < 64; i++) bus_store(console_addr_w + 32'(i), 0);
        enabled_w[0] = $value$plusargs("PERF_BEGIN=%h", begin_pc_w[0]);
        enabled_w[1] = $value$plusargs("PERF2_BEGIN=%h", begin_pc_w[1]);
        void'($value$plusargs("PERF_END=%h", end_pc_w[0]));
        void'($value$plusargs("PERF2_END=%h", end_pc_w[1]));
        for (int e = 0; e < 16; e++) total_events_r[e] = 0;
        for (int w = 0; w < 2; w++) begin
            measuring_r[w] = 0;
            for (int e = 0; e < 16; e++) events_r[w][e] = 0;
        end
        repeat (5) @(negedge clk_i);
        rst_n_i = 1;
    end

    task automatic report_window(input int w);
        $display("B2_WINDOW window=%0d cycles=%0d instret=%0d", w,
                 u_dut.u_core.u_csr.cycle_r - start_cycle_r[w],
                 u_dut.u_core.u_csr.instret_r - start_instret_r[w]);
        for (int e = 0; e < 16; e++)
            $display("B2_HPM window=%0d event=%0d count=%0d", w, e + 1, events_r[w][e]);
        for (int c = 0; c < 8; c++)
            $display("B2_CSR_HPM window=%0d counter=%0d event=%0d count=%0d", w, c + 3,
                     u_dut.u_core.u_csr.event_r[c],
                     u_dut.u_core.u_csr.counter_r[c] - start_hpm_r[w][c]);
    endtask

    always @(posedge clk_i) begin
        if (rst_n_i) begin
            cycles_r <= cycles_r + 1;
            for (int e = 0; e < 16; e++)
                total_events_r[e] += 64'(u_dut.u_core.event_count_w[e*2 +: 2]);
            if (dbus.awvalid && dbus.awready) bus_write_addr_r <= dbus.awaddr;
            if (dbus.wvalid && dbus.wready && bus_write_addr_r == console_addr_w)
                $write("%c", dbus.wdata[7:0]);
            for (int w = 0; w < 2; w++) begin
                for (int lane = 0; lane < 2; lane++) begin
                    if (enabled_w[w] && u_dut.u_core.trace_valid_w[lane]) begin
                        if (u_dut.u_core.trace_pc_w[lane*32 +: 32] == begin_pc_w[w]) begin
                            measuring_r[w] = 1;
                            start_cycle_r[w] = u_dut.u_core.u_csr.cycle_r;
                            start_instret_r[w] = u_dut.u_core.u_csr.instret_r;
                            for (int c = 0; c < 8; c++)
                                start_hpm_r[w][c] = u_dut.u_core.u_csr.counter_r[c];
                        end
                        if (u_dut.u_core.trace_pc_w[lane*32 +: 32] == end_pc_w[w]) begin
                            report_window(w);
                            measuring_r[w] = 0;
                        end
                    end
                end
                if (measuring_r[w])
                    for (int e = 0; e < 16; e++)
                        events_r[w][e] += 64'(u_dut.u_core.event_count_w[e*2 +: 2]);
            end
            // A request owns one commit, even if a device commit is held until its B response.
            if (store_r && !store_seen_r && u_dut.dc_commit_w && !u_dut.dc_kill_w) begin
                store_seen_r <= 1;
                if (store_addr_r == tohost_addr_w && u_dut.dc_store_data_w[0]) begin
                    $display("B2_TOTAL mcycle=%0d minstret=%0d RVC_EN=%0d latency=%0d",
                             u_dut.u_core.u_csr.cycle_r, u_dut.u_core.u_csr.instret_r,
                             RVC_EN, read_latency_w);
                    for (int e = 0; e < 16; e++)
                        $display("B2_HPM window=total event=%0d count=%0d", e + 1,
                                 total_events_r[e]);
                    for (int c = 0; c < 8; c++)
                        $display("B2_CSR_HPM window=total counter=%0d event=%0d count=%0d",
                                 c + 3, u_dut.u_core.u_csr.event_r[c],
                                 u_dut.u_core.u_csr.counter_r[c]);
                    if (u_dut.dc_store_data_w != 1)
                        $fatal(1, "FAIL tohost status=%0d", u_dut.dc_store_data_w >> 1);
                    $display("PASS cpu_b2");
                    $finish;
                end
            end
            if (u_dut.dc_req_valid_w && u_dut.dc_req_ready_w) begin
                store_addr_r <= u_dut.dc_req_addr_w;
                store_r <= u_dut.dc_req_store_w;
                store_seen_r <= 0;
            end
            if (cycles_r >= timeout_w)
                $fatal(1, "FAIL B2 timeout cycles=%0d debug=%h", cycles_r, debug_w);
        end
    end
endmodule
