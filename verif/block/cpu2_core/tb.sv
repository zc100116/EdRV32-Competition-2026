// File: tb.sv
// Spec: cpu-v2-testplan CV01/CV06/CV15; cpu-v2-spec 3.9, 3.11.
// Description: Real core with shared AXI64 memory, fixed latency and architectural tohost.
// Clock domain: clk_sys.
// The observer updates ordered software state at each accepted edge.
/* verilator lint_off BLKSEQ */
/* verilator lint_off SYNCASYNCNET */
module tb;
    parameter ISSUE_WIDTH = 2;
    import edrv32_axi64_memory_pkg::*;
    bit clk;
    initial clk = 0;
    bit rst_n = 0;
    always #5 clk = !clk;
    edrv32_axi64_if ic();
    edrv32_axi64_if dc();
    edrv32_axi64_memory u_ic (.clk_i(clk), .rst_n_i(rst_n), .bus(ic));
    edrv32_axi64_memory u_dc (.clk_i(clk), .rst_n_i(rst_n), .bus(dc));
    wire [63:0] debug;
    wire cache_irq;
    wire apb_ready;
    wire [31:0] apb_data;
    wire apb_error;
    edrv32_cpu2_top #(.ISSUE_WIDTH(ISSUE_WIDTH), .FPU_FORMAT("NONE")) dut (
        .clk_i(clk),
        .rst_n_i(rst_n),
        .ic_axi_arid_o(ic.arid),
        .ic_axi_araddr_o(ic.araddr),
        .ic_axi_arlen_o(ic.arlen),
        .ic_axi_arsize_o(ic.arsize),
        .ic_axi_arburst_o(ic.arburst),
        .ic_axi_arvalid_o(ic.arvalid),
        .ic_axi_arready_i(ic.arready),
        .ic_axi_rid_i(ic.rid),
        .ic_axi_rdata_i(ic.rdata),
        .ic_axi_rresp_i(ic.rresp),
        .ic_axi_rlast_i(ic.rlast),
        .ic_axi_rvalid_i(ic.rvalid),
        .ic_axi_rready_o(ic.rready),
        .dc_axi_arid_o(dc.arid),
        .dc_axi_araddr_o(dc.araddr),
        .dc_axi_arlen_o(dc.arlen),
        .dc_axi_arsize_o(dc.arsize),
        .dc_axi_arburst_o(dc.arburst),
        .dc_axi_arvalid_o(dc.arvalid),
        .dc_axi_arready_i(dc.arready),
        .dc_axi_rid_i(dc.rid),
        .dc_axi_rdata_i(dc.rdata),
        .dc_axi_rresp_i(dc.rresp),
        .dc_axi_rlast_i(dc.rlast),
        .dc_axi_rvalid_i(dc.rvalid),
        .dc_axi_rready_o(dc.rready),
        .dc_axi_awid_o(dc.awid),
        .dc_axi_awaddr_o(dc.awaddr),
        .dc_axi_awlen_o(dc.awlen),
        .dc_axi_awsize_o(dc.awsize),
        .dc_axi_awburst_o(dc.awburst),
        .dc_axi_awvalid_o(dc.awvalid),
        .dc_axi_awready_i(dc.awready),
        .dc_axi_wdata_o(dc.wdata),
        .dc_axi_wstrb_o(dc.wstrb),
        .dc_axi_wlast_o(dc.wlast),
        .dc_axi_wvalid_o(dc.wvalid),
        .dc_axi_wready_i(dc.wready),
        .dc_axi_bid_i(dc.bid),
        .dc_axi_bresp_i(dc.bresp),
        .dc_axi_bvalid_i(dc.bvalid),
        .dc_axi_bready_o(dc.bready),
        .apb_paddr_i('0),
        .apb_psel_i('0),
        .apb_penable_i('0),
        .apb_pwrite_i('0),
        .apb_pwdata_i('0),
        .apb_pstrb_i('0),
        .apb_pready_o(apb_ready),
        .apb_prdata_o(apb_data),
        .apb_pslverr_o(apb_error),
        .cache_irq_o(cache_irq),
        .irq_meip_i('0),
        .irq_msip_i('0),
        .irq_mtip_i('0),
        .mtime_i('0),
        .debug_o(debug)
    );
    string mem_hex;
    bit [31:0] tohost_addr;
    longint unsigned cycles;
    longint unsigned retired;
    longint unsigned cycle_limit;
    bit perf_enabled;
    bit [31:0] perf_begin;
    bit [31:0] perf_end;
    longint unsigned perf_start;
    bit perf_started;
    integer trace_fd;
    string trace_path;
    initial begin
        if (!$value$plusargs("MEM_HEX=%s", mem_hex)) $fatal(1, "FAIL missing MEM_HEX");
        if (!$value$plusargs("TOHOST_ADDR=%h", tohost_addr))
            $fatal(1, "FAIL missing TOHOST_ADDR");
        if (!$value$plusargs("MAX_CYCLES=%d", cycle_limit)) cycle_limit = 1000000;
        if ($value$plusargs("TRACE=%s", trace_path)) trace_fd = $fopen(trace_path, "w");
        perf_enabled = $value$plusargs("PERF_BEGIN=%h", perf_begin);
        if (perf_enabled && !$value$plusargs("PERF_END=%h", perf_end))
            $fatal(1, "FAIL missing PERF_END");
        random_stalls = 0;
        delay_max = 0;
        $readmemh(mem_hex, memory);
        repeat (5) @(negedge clk);
        rst_n = 1;
    end
    always @(posedge clk) begin
        if (!rst_n) begin
            cycles <= 0;
            retired = 0;
            perf_started = 0;
            perf_start = 0;
        end else begin
            cycles <= cycles + 1;
            if ((dut.commit_redirect_valid_w || dut.branch_redirect_valid_w) &&
                (dut.allocate_valid_w || dut.ib_remove_count_w != 0))
                $fatal(1, "FAIL recovery allocated stale IB head cycle=%0d", cycles);
            if ($test$plusargs("CONTROL_LOG") && (dut.allocate_valid_w ||
                dut.cancel_valid_w || dut.commit_redirect_valid_w ||
                dut.execute0_valid_w || dut.execute1_valid_w ||
                dut.wb0_valid_w || dut.wb1_valid_w || cycles+4 >= cycle_limit)) begin
                $display("CTRL cycle=%0d alloc=%b pc=%08x cnt=%0d cancel=%b/%0d redirect=%b",
                    cycles, dut.allocate_valid_w, dut.allocate0_pc_w, dut.allocate_count_w,
                    dut.cancel_valid_w, dut.cancel_tag_w, dut.commit_redirect_valid_w);
                $display("EX0 v/r=%b%b tag=%0d pc=%08x late=%b wait=%b%b tags=%0d/%0d",
                    dut.execute0_valid_w, dut.execute0_ready_w, dut.execute0_tag_w,
                    dut.execute0_pc_w, dut.execute0_late_w, dut.execute0_source1_wait_w,
                    dut.execute0_source2_wait_w, dut.execute0_source1_tag_w,
                    dut.execute0_source2_tag_w);
                $display("EX1 v/r=%b%b tag=%0d pc=%08x late=%b wait=%b%b tags=%0d/%0d",
                    dut.execute1_valid_w, dut.execute1_ready_w, dut.execute1_tag_w,
                    dut.execute1_pc_w, dut.execute1_late_w, dut.execute1_source1_wait_w,
                    dut.execute1_source2_wait_w, dut.execute1_source1_tag_w,
                    dut.execute1_source2_tag_w);
                $display("HEAD pc=%08x tag=%0d done=%b mem=%b WB=%b/%0d %b/%0d",
                    dut.head0_pc_w, dut.head0_tag_w, dut.head0_done_w,
                    dut.branch_debug_mem_valid_w, dut.wb0_valid_w, dut.wb0_tag_w,
                    dut.wb1_valid_w, dut.wb1_tag_w);
                $display("ALU0 %b%b/%0d ALU1 %b%b/%0d BR %b%b/%0d",
                    dut.alu0_complete_valid_w, dut.alu0_complete_ready_w,
                    dut.alu0_complete_tag_w, dut.alu1_complete_valid_w,
                    dut.alu1_complete_ready_w, dut.alu1_complete_tag_w,
                    dut.branch_complete_valid_w, dut.branch_complete_ready_w,
                    dut.branch_complete_tag_w);
            end
            if (dut.trace_trap_w)
                $display("TRAP pc=%08x cause=%08x tval=%08x cycle=%0d",
                    dut.trace_trap_pc_w, dut.trace_cause_w, dut.trace_tval_w, cycles);
            if (cycles >= cycle_limit)
                $fatal(1, "FAIL timeout width=%0d cycles=%0d retired=%0d pc=%08x",
                    ISSUE_WIDTH, cycles, retired, debug[63:32]);
            for (int j = 0; j < 2; j++) begin
                if (dut.trace_valid_w[j]) begin
                    retired = retired + 1;
                    if (perf_enabled && dut.trace_pc_w[j*32 +: 32] == perf_begin) begin
                        perf_start = cycles;
                        perf_started = 1;
                    end
                    if (perf_enabled && perf_started &&
                        dut.trace_pc_w[j*32 +: 32] == perf_end) begin
                        $display("PERF width=%0d cycles=%0d", ISSUE_WIDTH, cycles-perf_start);
                        perf_started = 0;
                    end
                    if (dut.trace_mem_valid_w[j] && dut.trace_mem_store_w[j] &&
                        dut.trace_mem_addr_w[j*32 +: 32] == 32'h40007000)
                        $write("%c", dut.trace_mem_data_w[j*64 +: 8]);
                    if (trace_fd != 0)
                        $fdisplay(trace_fd, "%0d %08x %08x %0d %08x", cycles,
                            dut.trace_pc_w[j*32 +: 32], dut.trace_instr_w[j*32 +: 32],
                            dut.trace_rd_w[j*5 +: 5], dut.trace_rd_data_w[j*64 +: 32]);
                    if (dut.trace_mem_valid_w[j] && dut.trace_mem_store_w[j] &&
                        dut.trace_mem_addr_w[j*32 +: 32] == tohost_addr &&
                        dut.trace_mem_data_w[j*64 +: 32] != 0) begin
                        if (dut.trace_mem_data_w[j*64 +: 32] != 1)
                            $fatal(1, "FAIL tohost=%08x pc=%08x cycle=%0d",
                                dut.trace_mem_data_w[j*64 +: 32],
                                dut.trace_pc_w[j*32 +: 32], cycles);
                        $display("PASS width=%0d cycles=%0d retired=%0d",
                            ISSUE_WIDTH, cycles, retired);
                        $finish;
                    end
                end
            end
        end
    end
    /* verilator lint_off UNUSEDSIGNAL */
    wire unused_w = ^{debug, cache_irq, apb_ready, apb_data, apb_error,
        ic.arid, ic.arburst, ic.awid, ic.awburst, ic.wlast,
        dc.arid, dc.arburst, dc.awid, dc.awburst, dc.wlast};
    /* verilator lint_on UNUSEDSIGNAL */
endmodule
