// edrv32_cache_env.sv
// cache-spec 3–7; independent module verification.
// Clock domain: clk_sys.
module edrv32_cache_env #(parameter int TEST = 0, parameter int SEEDS = 1);
    // The generated map also declares constants for other SoC clients.
    /* verilator lint_off UNUSEDPARAM */
    `include "edrv32_soc_map.vh"
    /* verilator lint_on UNUSEDPARAM */
    import edrv32_axi64_memory_pkg::*;
    logic clk = 0;
    // RTL resets asynchronously; bus models and monitors sample reset on clk.
    /* verilator lint_off SYNCASYNCNET */
    logic rst_n = 0;
    /* verilator lint_on SYNCASYNCNET */
    always #5 clk <= ~clk;
    edrv32_axi64_if ia();
    edrv32_axi64_if da();
    logic ic_req_valid;
    logic [31:0] ic_req_addr;
    logic ic_req_ready;
    logic ic_resp_valid;
    logic [63:0] ic_resp_data;
    logic ic_resp_err;
    logic ic_kill;
    logic ic_inv;
    logic ic_inv_done;
    logic dc_req_valid;
    logic [31:0] dc_req_addr;
    logic dc_req_store;
    logic [1:0] dc_req_size;
    logic dc_kill;
    logic dc_commit;
    logic [31:0] dc_store_data;
    logic dc_fence;
    logic dc_clean_all;
    logic dc_req_ready;
    logic dc_resp_valid;
    logic [31:0] dc_resp_data;
    logic dc_resp_err;
    logic dc_resp_device;
    logic dc_fence_done;
    logic dc_wb_event;
    int unsigned wb_event_count = 0;
    int unsigned wb_aw_count = 0;
    int unsigned device_reads = 0;
    int unsigned device_writes = 0;
    logic maint_req_valid;
    logic maint_req_ready;
    logic [2:0] maint_cmd;
    logic [31:0] maint_addr;
    logic [31:0] maint_size;
    logic maint_busy;
    logic wb_err;
    logic [31:0] wb_err_addr;
    logic [11:0] apb_paddr;
    logic apb_psel;
    logic apb_penable;
    logic apb_pwrite;
    logic [31:0] apb_pwdata;
    logic [3:0] apb_pstrb;
    logic apb_pready;
    logic [31:0] apb_prdata;
    logic apb_pslverr;
    logic irq;
    wire [7:0] unused_ic_resp_valid_copy_w;
    wire [43:0] t4_predecode_w;
    edrv32_icache u_icache (
        // Clock and reset
        .clk_i(clk),
        .rst_n_i(rst_n),
        .rst_sys_ivalid0_n_i({2{rst_n}}),
        .rst_sys_ivalid1_n_i({2{rst_n}}),
        .rst_sys_ilru_n_i({2{rst_n}}),

        // Core interface
        .ic_req_valid_i(ic_req_valid),
        .ic_req_addr_i(ic_req_addr),
        .ic_req_ready_o(ic_req_ready),
        .ic_resp_valid_o(ic_resp_valid),
        .ic_resp_valid_copy_o(unused_ic_resp_valid_copy_w),
        .ic_resp_data_o(ic_resp_data),
        .ic_resp_predecode_o(t4_predecode_w),
        .ic_resp_err_o(ic_resp_err),
        .ic_kill_i(ic_kill),
        .ic_inv_i(ic_inv),
        .ic_inv_done_o(ic_inv_done),

        // AXI memory interface
        .axi_arid_o(ia.arid),
        .axi_araddr_o(ia.araddr),
        .axi_arlen_o(ia.arlen),
        .axi_arsize_o(ia.arsize),
        .axi_arburst_o(ia.arburst),
        .axi_arvalid_o(ia.arvalid),
        .axi_arready_i(ia.arready),
        .axi_rid_i(ia.rid),
        .axi_rdata_i(ia.rdata),
        .axi_rresp_i(ia.rresp),
        .axi_rlast_i(ia.rlast),
        .axi_rvalid_i(ia.rvalid),
        .axi_rready_o(ia.rready)
    );
    edrv32_dcache u_dcache (
        // Clock and reset
        .clk_i(clk),
        .rst_n_i(rst_n),
        .rst_sys_dlru_n_i({2{rst_n}}),

        // Core interface
        .dc_req_valid_i(dc_req_valid),
        .dc_req_early_i(1'b0),
        .dc_req_addr_i(dc_req_addr),
        .dc_req_store_i(dc_req_store),
        .dc_req_size_i(dc_req_size),
        .dc_kill_i(dc_kill),
        .dc_commit_i(dc_commit),
        .dc_store_data_i(dc_store_data),
        .dc_fence_i(dc_fence),
        .dc_clean_all_i(dc_clean_all),
        .dc_req_ready_o(dc_req_ready),
        .dc_resp_valid_o(dc_resp_valid),
        .dc_resp_data_o(dc_resp_data),
        .dc_resp_err_o(dc_resp_err),
        .dc_resp_device_o(dc_resp_device),
        .dc_fence_done_o(dc_fence_done),
        .dc_wb_event_o(dc_wb_event),

        // AXI memory interface
        .axi_awid_o(da.awid),
        .axi_awaddr_o(da.awaddr),
        .axi_awlen_o(da.awlen),
        .axi_awsize_o(da.awsize),
        .axi_awburst_o(da.awburst),
        .axi_awvalid_o(da.awvalid),
        .axi_awready_i(da.awready),
        .axi_arid_o(da.arid),
        .axi_araddr_o(da.araddr),
        .axi_arlen_o(da.arlen),
        .axi_arsize_o(da.arsize),
        .axi_arburst_o(da.arburst),
        .axi_arvalid_o(da.arvalid),
        .axi_arready_i(da.arready),
        .axi_wdata_o(da.wdata),
        .axi_wstrb_o(da.wstrb),
        .axi_wlast_o(da.wlast),
        .axi_wvalid_o(da.wvalid),
        .axi_wready_i(da.wready),
        .axi_bid_i(da.bid),
        .axi_bresp_i(da.bresp),
        .axi_bvalid_i(da.bvalid),
        .axi_bready_o(da.bready),
        .axi_rid_i(da.rid),
        .axi_rdata_i(da.rdata),
        .axi_rresp_i(da.rresp),
        .axi_rlast_i(da.rlast),
        .axi_rvalid_i(da.rvalid),
        .axi_rready_o(da.rready),

        // Maintenance and status
        .maint_req_valid_i(maint_req_valid),
        .maint_req_ready_o(maint_req_ready),
        .maint_cmd_i(maint_cmd),
        .maint_addr_i(maint_addr),
        .maint_size_i(maint_size),
        .maint_busy_o(maint_busy),
        .wb_err_o(wb_err),
        .wb_err_addr_o(wb_err_addr)
    );
    edrv32_cache_ctrl u_cache_ctrl (
        // Clock and reset
        .clk_i(clk),
        .rst_n_i(rst_n),

        // APB register interface
        .apb_paddr_i(apb_paddr),
        .apb_psel_i(apb_psel),
        .apb_penable_i(apb_penable),
        .apb_pwrite_i(apb_pwrite),
        .apb_pwdata_i(apb_pwdata),
        .apb_pstrb_i(apb_pstrb),
        .apb_pready_o(apb_pready),
        .apb_prdata_o(apb_prdata),
        .apb_pslverr_o(apb_pslverr),

        // Maintenance and status
        .maint_req_valid_o(maint_req_valid),
        .maint_req_ready_i(maint_req_ready),
        .maint_cmd_o(maint_cmd),
        .maint_addr_o(maint_addr),
        .maint_size_o(maint_size),
        .maint_busy_i(maint_busy),
        .wb_err_i(wb_err),
        .wb_err_addr_i(wb_err_addr),
        .irq_o(irq)
    );
    assign ia.awid = 0;
    assign ia.awaddr = 0;
    assign ia.awlen = 0;
    assign ia.awsize = 0;
    assign ia.awburst = 1;
    assign ia.awvalid = 0;
    assign ia.wdata = 0;
    assign ia.wstrb = 0;
    assign ia.wlast = 0;
    assign ia.wvalid = 0;
    assign ia.bready = 1;
    edrv32_axi64_memory u_imem (
        // Clock and reset
        .clk_i(clk),
        .rst_n_i(rst_n),

        // AXI memory interface
        .bus(ia)
    );
    edrv32_axi64_memory u_dmem (
        // Clock and reset
        .clk_i(clk),
        .rst_n_i(rst_n),

        // AXI memory interface
        .bus(da)
    );
    edrv32_axi64_checker #(
        .INSTRUCTION(1)
    ) u_icheck (
        // Clock and reset
        .clk_i(clk),
        .rst_n_i(rst_n),

        // AXI memory interface
        .bus(ia)
    );
    edrv32_axi64_checker u_dcheck (
        // Clock and reset
        .clk_i(clk),
        .rst_n_i(rst_n),

        // AXI memory interface
        .bus(da)
    );
    edrv32_cache_core_checker u_core_check (
        // Clock and reset
        .clk_i(clk),
        .rst_n_i(rst_n),

        // Core interface
        .ic_accept_i(ic_req_valid && ic_req_ready),
        .dc_accept_i(dc_req_valid && dc_req_ready),
        .ic_hit_i(expect_ic_hit),
        .dc_hit_i(expect_dc_hit),
        .ic_resp_i(ic_resp_valid),
        .dc_resp_i(dc_resp_valid),
        .ic_kill_i(ic_kill),
        .dc_kill_i(dc_kill),
        .dc_device_i(dc_resp_device),
        .dc_commit_i(dc_commit),
        .dc_arvalid_i(da.arvalid),
        .dc_awvalid_i(da.awvalid),
        .dc_addr_i(dc_req_addr),
        .dc_store_i(dc_req_store),
        .dc_size_i(dc_req_size),
        .dc_store_data_i(dc_store_data),
        .bus(da)
    );
    int unsigned cycles;
    int unsigned instruction_hits;
    int unsigned hit_count[2];
    int unsigned miss_count[2][2];
    int unsigned bypass_count[2];
    int unsigned kill_count[3];
    int unsigned pma_count[9];
    int unsigned command_count[6];
    int unsigned error_count[3];
    int unsigned seed = 1;
    int unsigned random_count = 300;
    int unsigned conflict_lines = 6;
    int unsigned store_percent = 50;
    int unsigned kill_percent = 15;
    bit [31:0] random_base = 32'h80000000;
    bit expect_ic_hit;
    bit expect_dc_hit;
    localparam bit [31:0] A = 32'h10000000;
    localparam bit [31:0] B = 32'h10004000;
    localparam bit [31:0] C = 32'h10008000;
    // I$ same-set aliases: 32 KiB, 2 ways -> 512 sets x 32 B, so sets repeat every 16 KiB.
    localparam bit [31:0] IC_B = 32'h10004000;
    localparam bit [31:0] IC_C = 32'h10008000;
    localparam bit [31:0] DEV = 32'h20000000;
    localparam bit [31:0] STATUS = 32'h40005008;

    int measured_cycles = 0;
    int measured_reads = 0;
    time maintenance_accepted;
    bit [511:0] measured_groups = 0;
    bit measuring = 0;
    always @(posedge clk) begin
        if (maint_req_valid && maint_req_ready) begin
            maintenance_accepted = $time;
            measured_reads = 0;
            measured_groups = 0;
            measuring = 1;
        end
        if (maint_busy && u_dcache.scan_read_w) begin
            if (u_dcache.maint_cmd_r != 4 && measured_groups[u_dcache.scan_read_idx_w])
                $fatal(1, "FAIL repeated range group index=%0d", u_dcache.scan_read_idx_w);
            measured_groups[u_dcache.scan_read_idx_w] = 1;
            measured_reads++;
        end
    end
    always @(negedge clk) begin
        if (measuring && !maint_busy) begin
            measured_cycles = int'(($time - maintenance_accepted) / 10);
            measuring = 0;
        end
    end

    always @(posedge clk) cycles <= cycles + 1;
    initial begin
        #10000000;
        $fatal(1, "FAIL timeout expected=completion actual=timeout time=%0t", $time);
    end

    task automatic eq(input string name, input logic [63:0] expected,
                      input logic [63:0] actual);
        if (expected !== actual)
            $fatal(1, "FAIL %s expected=%h actual=%h time=%0t", name, expected,
                   actual, $time);
    endtask

    function automatic int pma(input bit [31:0] addr);
        if (addr < 32'h4000) return 0;
        if (addr >= A && addr < EDRV32_SRAM_BASE + EDRV32_SRAM_SIZE) return 1;
        if (addr >= DEV && addr < 32'h20010000) return 2;
        if (addr >= 32'h30000000 && addr < 32'h30400000) return 3;
        if (addr >= 32'h40000000 && addr < 32'h40010000) return 4;
        if (addr >= 32'h41000000 && addr < 32'h41010000) return 5;
        if (addr >= 32'h80000000 && addr < 32'hc0000000) return 6;
        if (addr >= 32'hc0000000) return 7;
        return 8;
    endfunction

    // cache-spec 5.1–5.3: transaction shape follows PMA, not DUT-reported SIZE.
    always @(posedge clk) begin
        if (rst_n) begin
            eq("writeback event timing", 64'(da.awvalid && da.awready && da.awlen == 3),
               64'(dc_wb_event));
            if (da.arvalid && da.arready && da.arlen == 0) device_reads <= device_reads + 1;
            if (da.awvalid && da.awready && da.awlen == 0) device_writes <= device_writes + 1;
            if (dc_wb_event) wb_event_count <= wb_event_count + 1;
            if (da.awvalid && da.awready && da.awlen == 3) wb_aw_count <= wb_aw_count + 1;
            if (ia.arvalid) eq("I ARSIZE", 3, 64'(ia.arsize));
            if (da.arvalid && (pma(da.araddr) == 1 || pma(da.araddr) == 6))
                eq("D fill ARSIZE", 3, 64'(da.arsize));
            if (da.awvalid && (pma(da.awaddr) == 1 || pma(da.awaddr) == 6))
                eq("D writeback AWSIZE", 3, 64'(da.awsize));
        end
    end

    task automatic idle(input int n = 1);
        repeat (n) @(posedge clk);
        @(negedge clk);
    endtask

    task automatic apb(input bit write_access, input bit [11:0] addr,
                       input bit [31:0] data, output bit [31:0] result);
        @(negedge clk);
        apb_psel = 1;
        apb_penable = 0;
        apb_pwrite = write_access;
        apb_paddr = addr;
        apb_pwdata = data;
        apb_pstrb = 15;
        @(negedge clk);
        apb_penable = 1;
        do @(posedge clk); while (!apb_pready);
        result = apb_prdata;
        eq("APB response", 0, 64'(apb_pslverr));
        @(negedge clk);
        apb_psel = 0;
        apb_penable = 0;
    endtask

    task automatic put(input bit [11:0] addr, input bit [31:0] data);
        bit [31:0] unused_readback;
        apb(1, addr, data, unused_readback);
    endtask

    task automatic reg_eq(input bit [11:0] addr, input bit [31:0] expected);
        bit [31:0] result;
        apb(0, addr, 0, result);
        eq($sformatf("APB %h", addr), 64'(expected), 64'(result));
    endtask

    task automatic fetch(input bit [31:0] addr, input bit error_expected = 0,
                         input bit kill_request = 0, input bit hit_expected = 0,
                         input bit kill_during_fill = 0);
        int before_reads;
        time accepted;
        before_reads = u_imem.reads;
        @(negedge clk);
        ic_req_addr = addr;
        ic_req_valid = 1;
        expect_ic_hit = hit_expected;
        do @(posedge clk); while (!ic_req_ready);
        accepted = $time;
        begin
            bit [3:0] region;
            region = 4'(pma(addr));
            pma_count[region]++;
        end
        @(negedge clk);
        ic_req_valid = 0;
        expect_ic_hit = 0;
        if (kill_during_fill) begin
            do @(posedge clk); while (!(ia.arvalid && ia.arready));
            @(negedge clk);
        end
        ic_kill = kill_request;
        if (kill_request) begin
            @(posedge clk);
            @(negedge clk);
            ic_kill = 0;
            while (!ic_req_ready) begin
                eq("killed instruction response", 0, 64'(ic_resp_valid));
                @(negedge clk);
            end
            repeat (3) begin
                eq("killed instruction response", 0, 64'(ic_resp_valid));
                @(negedge clk);
            end
        end else begin
            do @(posedge clk); while (!ic_resp_valid);
            eq("instruction error", 64'(error_expected), 64'(ic_resp_err));
            if (!error_expected) eq("instruction data", read_data(addr, 8), ic_resp_data);
            if (hit_expected) eq("instruction hit latency", 10, 64'($time - accepted));
            @(negedge clk);
        end
        if (kill_request) kill_count[u_imem.reads == before_reads ? 0 : 1]++;
        if (!error_expected && !kill_request && u_imem.reads == before_reads)
            instruction_hits++;
    endtask

    task automatic data_access(input bit [31:0] addr, input bit store = 0,
                               input int size = 2, input bit [31:0] data = 0,
                               input bit error_expected = 0, input bit killed = 0,
                               input bit hit_expected = 0, input bit kill_during_fill = 0);
        bit device;
        bit [63:0] mask;
        int before_reads;
        int before_writes;
        int before_device_reads;
        int before_device_writes;
        time accepted;
        before_device_reads = int'(device_reads);
        before_device_writes = int'(device_writes);
        before_reads = u_dmem.reads;
        before_writes = u_dmem.writes;
        mask = (64'b1 << (8 * (1 << size))) - 1;
        @(negedge clk);
        dc_req_valid = 1;
        dc_req_addr = addr;
        dc_req_store = store;
        dc_req_size = 2'(size);
        expect_dc_hit = hit_expected;
        do @(posedge clk); while (!dc_req_ready);
        accepted = $time;
        begin
            bit [3:0] region;
            region = 4'(pma(addr));
            pma_count[region]++;
        end
        @(negedge clk);
        dc_req_valid = 0;
        expect_dc_hit = 0;
        device = (addr < 32'h4000 && !store) ||
                 (addr >= DEV && addr < 32'h20010000) ||
                 (addr >= 32'h30000000 && addr < 32'h30400000) ||
                 (addr >= 32'h40000000 && addr < 32'h40010000) ||
                 (addr >= 32'h41000000 && addr < 32'h41010000) ||
                 addr >= 32'hc0000000;
        eq("PMA device classification", 64'(device), 64'(dc_resp_device));
        if (killed) begin
            if (kill_during_fill) begin
                do @(posedge clk); while (!(da.arvalid && da.arready));
                @(negedge clk);
            end
            dc_kill = 1;
            @(negedge clk);
            dc_kill = 0;
            while (!dc_req_ready) begin
                eq("killed data response", 0, 64'(dc_resp_valid));
                @(negedge clk);
            end
            idle(3);
            if (device) begin
                eq("killed device reads", 64'(before_device_reads), 64'(device_reads));
                eq("killed device writes", 64'(before_device_writes), 64'(device_writes));
            end
            // Expected-hit is optional in random tests; observed bus traffic
            // distinguishes an actual hit from a refill after cancellation.
            kill_count[device ? 2 : (u_dmem.reads == before_reads ? 0 : 1)]++;
            return;
        end
        if (device) begin
            // cache-spec 5.3: several uncommitted cycles must produce no AXI request.
            repeat (3) begin
                eq("device before commit AR", 64'(before_device_reads), 64'(device_reads));
                eq("device before commit AW", 64'(before_device_writes), 64'(device_writes));
                eq("device before commit response", 0, 64'(dc_resp_valid));
                @(negedge clk);
            end
            dc_commit = 1;
            dc_store_data = data;
            @(posedge clk);
            if (store && !error_expected) commit_store(addr, data, size);
            @(negedge clk);
            dc_commit = 0;
        end
        do @(posedge clk); while (!dc_resp_valid);
        $display("PERF access addr=%h store=%0b response_cycles=%0d", addr, store,
                 int'(($time-accepted)/10));
        eq("data error", 64'(error_expected), 64'(dc_resp_err));
        if (!error_expected && !store)
            eq("load data", read_data(addr, 1 << size, 1) & mask,
               64'(dc_resp_data) & mask);
        if (hit_expected) eq("data hit latency", 10, 64'($time - accepted));
        @(negedge clk);
        if (store && !device && !error_expected) begin
            dc_commit = 1;
            dc_store_data = data;
            @(posedge clk);
            commit_store(addr, data, size);
            @(negedge clk);
            dc_commit = 0;
        end
        if (u_dmem.reads == before_reads && !device && !error_expected)
            hit_count[store]++;
        if (u_dmem.reads != before_reads && !device && !error_expected)
            miss_count[store][u_dmem.writes != before_writes]++;
    endtask

    task automatic invalidate_ic;
        @(negedge clk);
        ic_inv = 1;
        @(posedge clk);
        @(negedge clk);
        ic_inv = 0;
        @(posedge clk);
        eq("instruction invalidation done", 1, 64'(ic_inv_done));
        @(negedge clk);
    endtask

    task automatic fence(input bit clean = 0);
        @(negedge clk);
        dc_fence = !clean;
        dc_clean_all = clean;
        command_count[clean ? 4 : 5]++;
        do @(posedge clk); while (!dc_fence_done);
        @(negedge clk);
        dc_fence = 0;
        dc_clean_all = 0;
    endtask

    task automatic maintain(input int cmd, input bit [31:0] addr = 0,
                            input bit [31:0] size = 0);
        put(12'h020, addr);
        put(12'h024, size);
        put(12'h028, 32'(cmd));
        command_count[cmd-1]++;
        while (maint_req_valid || maint_busy) idle();
        // Sample after the completion-edge measurement monitor has updated.
        #1;
    endtask

    task automatic compare_memory;
        foreach (memory[addr])
            eq($sformatf("physical memory %h", addr), 64'(read_byte(addr, 1)),
               64'(memory[addr]));
        foreach (reference_memory[addr])
            eq($sformatf("clean memory %h", addr), 64'(reference_memory[addr]),
               64'(read_byte(addr)));
    endtask

    task automatic expect_fetch_bus(input bit [31:0] addr, input int expected_reads,
                                    input bit error_expected = 0,
                                    input bit killed = 0);
        int count;
        count = u_imem.reads;
        fetch(addr, error_expected, killed,
              expected_reads == 0 && !error_expected && !killed, killed && expected_reads != 0);
        eq("I AXI transaction count", 64'(expected_reads), (64'(u_imem.reads) - 64'(count)));
    endtask

    task automatic expect_data_bus(input bit [31:0] addr, input int reads,
                                   input int writes, input bit store = 0,
                                   input bit [31:0] value = 0,
                                   input bit error_expected = 0);
        int r;
        int w;
        r = u_dmem.reads;
        w = u_dmem.writes;
        data_access(addr, store, 2, value, error_expected);
        eq("D AXI read count", 64'(reads), (64'(u_dmem.reads) - 64'(r)));
        eq("D AXI write count", 64'(writes), (64'(u_dmem.writes) - 64'(w)));
    endtask

    task automatic random_stream(input bit instruction);
        bit [31:0] addr;
        bit store;
        bit killed;
        int size;
        for (int n = 0; n < int'(random_count); n++) begin
            size = int'($urandom_range(0, 2));
            addr = random_base + $urandom_range(0, conflict_lines-1) *
                   ((pma(random_base) == 1 || pma(random_base) == 6) ? 16384 : 4096) +
                   ($urandom_range(0, 7) * 4);
            store = $urandom_range(0, 99) < store_percent;
            killed = $urandom_range(0, 99) < kill_percent;
            if (instruction) fetch({addr[31:3], 3'b0}, 0, killed);
            else data_access(addr, store, size, $urandom, 0, killed);
        end
        if (!instruction) begin
            fence(1);
            compare_memory();
        end
    endtask
    task automatic random_seeds(input bit instruction);
        int first_seed;
        int draw;
        first_seed = int'(seed);
        for (int run_seed = 0; run_seed < SEEDS; run_seed++) begin
            @(negedge clk);
            rst_n = 0;
            memory.delete();
            reference_memory.delete();
            idle(4);
            seed = 32'(first_seed + run_seed);
            draw = int'($urandom(seed));
            $display("RANDOM test=%0d seed=%0d first_draw=%h", TEST, seed, draw);
            rst_n = 1;
            idle(2);
            random_stream(instruction);
            $display("PASS seed test=%0d seed=%0d", TEST, seed);
        end
    endtask

    // Warm line before this task. All transfers are sampled at rising edges.
    task automatic hit_stream(input bit instruction, input bit stores = 0);
        @(negedge clk);
        for (int n = 0; n < 16; n++) begin
            if (instruction) begin
                ic_req_valid = 1;
                ic_req_addr = A + 32'((n % 4) * 8);
            end else begin
                dc_req_valid = 1;
                dc_req_addr = A + 32'((n % 8) * 4);
                dc_req_store = stores;
                dc_req_size = 2;
                dc_commit = stores && n != 0;
                dc_store_data = 32'h60000000 + 32'(n-1);
            end
            @(posedge clk);
            eq("hit stream ready", 1, (instruction ? 64'(ic_req_ready) : 64'(dc_req_ready)));
            if (n != 0) begin
                eq("hit stream response", 1,
                   (instruction ? 64'(ic_resp_valid) : 64'(dc_resp_valid)));
                if (instruction)
                    eq("instruction stream data", read_data(A + 32'(((n-1)%4)*8), 8),
                       ic_resp_data);
                else if (!stores)
                    eq("load stream data", read_data(A + 32'(((n-1)%8)*4), 4, 1),
                       64'(dc_resp_data));
                if (stores) commit_store(A + 32'(((n-1)%8)*4), dc_store_data, 2);
            end
            @(negedge clk);
        end
        ic_req_valid = 0;
        dc_req_valid = 0;
        dc_commit = stores;
        dc_store_data = 32'h6000000f;
        @(posedge clk);
        eq("last hit response", 1, (instruction ? 64'(ic_resp_valid) : 64'(dc_resp_valid)));
        if (stores) commit_store(A + 28, dc_store_data, 2);
        @(negedge clk);
        dc_commit = 0;
        $display("PERF hit_stream accepted=16 cycles=16 instruction=%0b stores=%0b",
                 instruction, stores);
    endtask

    task automatic bypass(input int size);
        bit [31:0] value;
        value = 32'hf19ac35e;
        data_access(A);
        @(negedge clk);
        dc_req_valid = 1;
        dc_req_addr = A;
        dc_req_store = 1;
        dc_req_size = 2'(size);
        @(posedge clk);
        eq("bypass store ready", 1, 64'(dc_req_ready));
        @(negedge clk);
        dc_req_valid = 0;
        @(posedge clk);
        eq("bypass store response", 1, 64'(dc_resp_valid));
        @(negedge clk);
        dc_commit = 1;
        dc_store_data = value;
        dc_req_valid = 1;
        dc_req_addr = A;
        dc_req_store = 0;
        dc_req_size = 2;
        @(posedge clk);
        commit_store(A, value, size);
        eq("bypass load ready", 1, 64'(dc_req_ready));
        @(negedge clk);
        dc_commit = 0;
        dc_req_valid = 0;
        @(posedge clk);
        eq("bypass load response", 1, 64'(dc_resp_valid));
        eq("bypass merged data", read_data(A, 4, 1), 64'(dc_resp_data));
        bypass_count[size == 2 ? 0 : 1]++;
        @(negedge clk);
    endtask

    task automatic dirty_lines;
        data_access(A, 1, 2, 32'h12345678);
        data_access(A+32, 1, 2, 32'h90abcdef);
        data_access(B, 1, 2, 32'h5555aaaa);
        idle(2);
    endtask

    task automatic coverage_report;
        eq("writeback event count", 64'(wb_aw_count), 64'(wb_event_count));
        $display("WB events=%0d bursts=%0d", wb_event_count, wb_aw_count);
        $display("COVER instruction_hits=%0d", instruction_hits);
        for (int i = 0; i < 2; i++) begin
            $display("COVER hit[%0d]=%0d", i, hit_count[i]);
            for (int j = 0; j < 2; j++)
                $display("COVER miss[store=%0d][dirty=%0d]=%0d", i, j, miss_count[i][j]);
            $display("COVER bypass[%0d]=%0d", i, bypass_count[i]);
        end
        for (int i = 0; i < 3; i++) begin
            $display("COVER kill[%0d]=%0d", i, kill_count[i]);
            $display("COVER error[%0d]=%0d", i, error_count[i]);
        end
        for (int i = 0; i < 9; i++) $display("COVER pma[%0d]=%0d", i, pma_count[i]);
        for (int i = 0; i < 6; i++)
            $display("COVER command[%0d]=%0d", i, command_count[i]);
    endtask

    initial begin : run
        int count;
        cycles = 0;
        ic_req_valid = 0;
        ic_req_addr = 0;
        ic_kill = 0;
        ic_inv = 0;
        dc_req_valid = 0;
        dc_req_addr = 0;
        dc_req_store = 0;
        dc_req_size = 0;
        dc_kill = 0;
        dc_commit = 0;
        dc_store_data = 0;
        dc_fence = 0;
        dc_clean_all = 0;
        apb_psel = 0;
        apb_penable = 0;
        apb_pwrite = 0;
        apb_paddr = 0;
        apb_pwdata = 0;
        apb_pstrb = 0;
        expect_ic_hit = 0;
        expect_dc_hit = 0;
        if ($value$plusargs("SEED=%d", seed)) begin end
        if ($value$plusargs("COUNT=%d", random_count)) begin end
        if ($value$plusargs("BASE=%h", random_base)) begin end
        if ($value$plusargs("CONFLICT_LINES=%d", conflict_lines)) begin end
        if ($value$plusargs("STORE_PERCENT=%d", store_percent)) begin end
        if ($value$plusargs("KILL_PERCENT=%d", kill_percent)) begin end
        count = int'($urandom(seed));
        $display("RANDOM seed=%0d first_draw=%h", seed, count);
        if (TEST == 216) begin
            for (int i = 0; i < 512; i++) begin
                u_dcache.u_tag0.memory_r[i] = 20'hc0000 | 20'($urandom_range(0, 262143));
                u_dcache.u_tag1.memory_r[i] = 20'hc0000 | 20'($urandom_range(0, 262143));
            end
        end
        repeat (4) @(negedge clk);
        rst_n = 1;
        idle(2);
        if (TEST == 216) begin
            for (int i = 0; i < 129; i++) begin
                eq("initialization blocks core", 0, 64'(dc_req_ready));
                eq("initialization blocks maintenance", 0, 64'(maint_req_ready));
                idle();
            end
            rst_n = 0;
            idle(4);
            rst_n = 1;
            for (int i = 0; i < 512; i++) begin
                eq("restarted initialization blocks core", 0, 64'(dc_req_ready));
                eq("restarted initialization blocks maintenance", 0, 64'(maint_req_ready));
                eq("initialization has no writeback", 0, 64'(da.awvalid));
                idle();
            end
            eq("initialization ready after 512 cycles", 1, 64'(dc_req_ready));
        end else begin
            while (!dc_req_ready) idle();
        end
        case (TEST)
            0: begin
                if ($test$plusargs("BAD_AXI_LEN")) fetch(A);
                fetch(0, 0, 0, $test$plusargs("BAD_CORE_HIT"));
                fetch(A);
                fetch(B, 0, 1, 0, 1);
                data_access(DEV+4, 1, 2, 32'h12345678);
                data_access(DEV+4);
                data_access(DEV+2, 1, 1, 32'hbeef);
                data_access(DEV+2, 0, 1);
                data_access(DEV+1, 1, 0, 32'h19);
                data_access(DEV+1, 0, 0);
                data_access(DEV, 0, 2, 0, 0, 1);
                fetch(32'h20, 0, 1);
                reg_eq(0, 32'h00050001);
                put(12'h00c, 2);
                reg_eq(12'h00c, 2);
                maintain(1, A, 0);
                fence();
                compare_memory();
                random_count = 40;
                random_base = 0;
                conflict_lines = 1;
                random_stream(1);
                random_base = DEV;
                conflict_lines = 6;
                random_stream(0);
            end
            101: begin
                for (int line = 0; line < 4; line++) begin
                    expect_fetch_bus(A+32'(line*32), 1);
                    for (int word = 0; word < 4; word++)
                        expect_fetch_bus(A+32'(line*32+word*8), 0);
                end
                hit_stream(1);
            end
            102: begin
                expect_fetch_bus(A, 1);
                expect_fetch_bus(IC_B, 1);
                expect_fetch_bus(A, 0);
                expect_fetch_bus(IC_C, 1);
                expect_fetch_bus(A, 0);
                expect_fetch_bus(IC_B, 1);
                expect_fetch_bus(IC_C, 1);
            end
            103: begin
                expect_fetch_bus(0, 1);
                expect_fetch_bus(0, 1);
            end
            104: begin
                foreach (pma_count[i]) begin
                    case (i)
                        2: expect_fetch_bus(DEV, 0, 1);
                        3: expect_fetch_bus(32'h30000000, 0, 1);
                        4: expect_fetch_bus(32'h40000000, 0, 1);
                        5: expect_fetch_bus(32'h41000000, 0, 1);
                        7: begin
                            expect_fetch_bus(32'hc0000000, 0, 1);
                            expect_fetch_bus(32'h50000000, 0, 1);
                        end
                        default: begin end
                    endcase
                end
            end
            105: begin
                expect_fetch_bus(A, 1, 0, 1);
                expect_fetch_bus(A, 0);
            end
            106: begin
                fetch(A);
                fetch(B);
                invalidate_ic();
                expect_fetch_bus(A, 1);
                expect_fetch_bus(B, 1);
            end
            107: begin
                error_read_addr = A;
                expect_fetch_bus(A, 1, 1);
                error_count[0]++;
                error_read_addr = '1;
                expect_fetch_bus(A, 1);
            end
            108: random_seeds(1);
            201: begin
                data_access(A);
                data_access(A, 0, 2, 0, 0, 0, 1);
                hit_stream(0);
            end
            202: begin
                data_access(A);
                for (int size = 0; size <= 2; size++)
                    for (int off = 0; off < 8; off += (1 << size)) begin
                        data_access(A+32'(off), 1, size, 32'h19283746);
                        data_access(A+32'(off), 0, size);
                    end
                fence(1);
                compare_memory();
            end
            203: begin
                bypass(2);
                bypass(0);
                bypass(1);
            end
            204: begin
                data_access(A);
                hit_stream(0, 1);
                fence(1);
                compare_memory();
            end
            205: begin
                expect_data_bus(A, 1, 0);
                expect_data_bus(B, 1, 0);
                expect_data_bus(C, 1, 0);
            end
            206: begin
                data_access(A, 1, 2, 32'haf123456);
                data_access(B, 1, 2, 32'hbe654321);
                expect_data_bus(C, 1, 1);
                eq("dirty victim data", read_data(A, 4, 1), read_data(A, 4));
                fence(1);
                compare_memory();
            end
            207: begin
                expect_data_bus(A, 1, 0, 1, 32'hdeadbeef);
                data_access(A, 0, 2, 0, 0, 0, 1);
                data_access(B);
                expect_data_bus(C, 1, 1, 1, 32'h17181920);
                fence(1);
                compare_memory();
            end
            216: begin
                for (int i = 0; i < 512; i++) begin
                    eq("reset way0 metadata", 0, 64'(u_dcache.u_tag0.memory_r[i][19:18]));
                    eq("reset way1 metadata", 0, 64'(u_dcache.u_tag1.memory_r[i][19:18]));
                end
                for (int i = 0; i < 1024; i++)
                    expect_data_bus(A + 32'(i*32), 1, 0);
            end
            217: begin
                random_stalls = 0;
                delay_max = 0;
                data_access(A, 1, 2, 32'h12345678);
                hit_stream(0, 1);
                hit_stream(0);
                bypass(0);
                bypass(1);
                data_access(B, 1, 2, 32'habcd9876);
                expect_data_bus(C, 1, 1, 1, 32'h1234abcd);
                data_access(C, 0, 2, 0, 0, 0, 1);
                fence(1);
                compare_memory();
            end
            208: begin
                data_access(A, 0, 2, 0, 0, 1, 0, 1);
                expect_data_bus(A, 0, 0);
                data_access(A, 1, 2, 32'hbadbad, 0, 1, 1);
                data_access(A);
                data_access(B, 1, 2, 32'hbadbad, 0, 1, 0, 1);
                expect_data_bus(B, 0, 0);
                fence(1);
                compare_memory();
            end
            209: begin
                for (int size = 0; size <= 2; size++)
                    for (int off = 0; off < 8; off += (1 << size)) begin
                        data_access(DEV+32'(off), 1, size, 32'hcafef00d);
                        data_access(DEV+32'(off), 0, size);
                    end
                compare_memory();
            end
            210: begin
                data_access(DEV, 0, 2, 0, 0, 1);
                data_access(DEV, 1, 2, 32'hbadbad, 0, 1);
                compare_memory();
            end
            211: begin
                expect_data_bus(0, 0, 0, 1, 0, 1);
                expect_data_bus(32'h50000000, 0, 0, 0, 0, 1);
                expect_data_bus(32'h50000000, 0, 0, 1, 0, 1);
            end
            212: begin
                expect_data_bus(32'hc0000000, 1, 0);
                expect_data_bus(32'hc0000000, 1, 0);
                expect_data_bus(32'hc0000004, 0, 1, 1, 32'h1234abcd);
                data_access(32'h80000004);
            end
            213: begin
                error_read_addr = A;
                expect_data_bus(A, 1, 0, 0, 0, 1);
                error_count[0]++;
                error_read_addr = '1;
                expect_data_bus(A, 1, 0);
            end
            214: begin
                error_read_addr = DEV;
                data_access(DEV, 0, 2, 0, 1);
                error_read_addr = '1;
                error_write_addr = DEV;
                data_access(DEV, 1, 2, 32'hbadbad, 1);
                error_write_addr = '1;
                error_count[1] += 2;
            end
            215: random_seeds(0);
            301, 302, 303: begin
                dirty_lines();
                count = u_dmem.writes;
                maintain(TEST-300, A+3, 30);
                eq("range writeback count", TEST == 302 ? 0 : 2,
                   (64'(u_dmem.writes) - 64'(count)));
                eq("outside dirty line unchanged", 64'(initial_byte(B)),
                   64'(read_byte(B)));
                if (TEST != 302) begin
                    eq("range first line", read_data(A, 4, 1), read_data(A, 4));
                    eq("range last line", read_data(A+32, 4, 1), read_data(A+32, 4));
                end else begin
                    eq("invalidate discards dirty", 64'(initial_byte(A)),
                       64'(read_byte(A)));
                    // Architecture changes deliberately discarded by invalidate.
                    for (int off = 0; off < 64; off++)
                        reference_memory[physical(A+32'(off))] = read_byte(A+32'(off));
                end
                expect_data_bus(A, TEST == 301 ? 0 : 1, 0);
                count = u_dmem.writes;
                maintain(1, A+3, 30);
                eq("range dirty cleared", 64'(count), 64'(u_dmem.writes));
                expect_data_bus(B, 0, 0);
                fence(1);
                compare_memory();
            end
            304: begin
                dirty_lines();
                // Command 4 ignores both range registers, including zero size.
                maintain(4, 32'hfffffff0, 0);
                compare_memory();
                count = u_dmem.writes;
                maintain(4, 0, 32);
                eq("all dirty cleared", 64'(count), 64'(u_dmem.writes));
            end
            305: begin
                fetch(A);
                data_access(A, 1, 2, 32'h00000013);
                fence(1);
                invalidate_ic();
                expect_fetch_bus(A, 1);
                compare_memory();
            end
            306: begin
                data_access(A);
                @(negedge clk);
                dc_req_valid = 1;
                dc_req_addr = A;
                dc_req_store = 1;
                dc_req_size = 2;
                @(posedge clk);
                eq("fence store ready", 1, 64'(dc_req_ready));
                @(negedge clk);
                dc_req_valid = 0;
                @(posedge clk);
                eq("fence store response", 1, 64'(dc_resp_valid));
                @(negedge clk);
                dc_commit = 1;
                dc_store_data = 32'habcd1234;
                @(posedge clk);
                commit_store(A, dc_store_data, 2);
                @(negedge clk);
                dc_commit = 0;
                dc_fence = 1;
                command_count[5]++;
                @(posedge clk);
                eq("fence waits for buffer", 0, 64'(dc_fence_done));
                do @(posedge clk); while (!dc_fence_done);
                @(negedge clk);
                dc_fence = 0;
                data_access(A, 0, 2, 0, 0, 0, 1);
                fence(1);
                compare_memory();
            end
            307, 308: begin
                dirty_lines();
                if (TEST == 308) begin
                    count = u_dmem.writes;
                    put(12'h020, A);
                    put(12'h024, 0);
                    put(12'h028, 1);
                    command_count[0]++;
                    while (maint_req_valid) begin
                        eq("zero size busy", 0, 64'(maint_busy));
                        idle();
                    end
                    eq("zero size completed", 0, 64'(maint_busy));
                    eq("zero size writes", 64'(count), 64'(u_dmem.writes));
                end
                put(12'h020, A);
                put(12'h024, TEST == 307 ? 16384 : 64);
                put(12'h028, 1);
                command_count[0]++;
                // APB completion queues the mailbox; D$ acceptance is a later edge.
                while (maint_req_valid) idle();
                eq("maintenance active", 1, 64'(maint_busy));
                if (TEST == 308) begin
                    put(12'h020, B);
                    put(12'h028, 2);
                end else begin
                    // cpu-spec 3.3: unoccupied acceptance is independent of
                    // request PMA, read/write type and size during maintenance.
                    for (int kind = 0; kind < 6; kind++) begin
                        for (int op = 0; op < 6; op++) begin
                            @(negedge clk);
                            case (kind)
                                0: dc_req_addr = A;
                                1: dc_req_addr = STATUS;
                                2: dc_req_addr = 32'h80000000;
                                3: dc_req_addr = 32'hc0000000;
                                4: dc_req_addr = 0;
                                default: dc_req_addr = 32'h50000000;
                            endcase
                            dc_req_store = 1'(op / 3);
                            dc_req_size = 2'(op % 3);
                            #1;
                            eq("maintenance request ready", 1, 64'(dc_req_ready));
                        end
                    end
                    // cache-spec 2.3/5.4: a PMA violation returns in M without
                    // joining the cached request's maintenance wait.
                    begin : maintenance_pma_error
                        int before_reads;
                        before_reads = u_dmem.reads;
                        @(negedge clk);
                        dc_req_addr = 32'h50000000;
                        dc_req_store = 0;
                        dc_req_size = 2;
                        dc_req_valid = 1;
                        #1;
                        eq("PMA request accepted during maintenance", 1, 64'(dc_req_ready));
                        @(posedge clk);
                        @(negedge clk);
                        dc_req_valid = 0;
                        eq("PMA response during maintenance", 1, 64'(dc_resp_valid));
                        eq("PMA error during maintenance", 1, 64'(dc_resp_err));
                        eq("maintenance continues after PMA", 1, 64'(maint_busy));
                        eq("PMA has no AXI read", 64'(before_reads), 64'(u_dmem.reads));
                        if (u_dcache.ram_read_w)
                            eq("PMA does not take arrays", 1,
                               64'(u_dcache.state_r == u_dcache.S_MREAD ||
                                   u_dcache.state_r == u_dcache.S_MCHECK ||
                                   u_dcache.state_r == u_dcache.S_WB_READ));
                        @(negedge clk);
                        eq("PMA response clears", 0, 64'(dc_resp_valid));
                        eq("PMA error clears", 0, 64'(dc_resp_err));
                    end
                    data_access(STATUS);
                    eq("STATUS completed during maintenance", 1, 64'(maint_busy));
                    // cache-spec 5.4: accept once, then retain the cached request
                    // until the maintenance walker releases the arrays.
                    fork
                        data_access(A);
                        begin
                            wait (dc_req_valid && dc_req_ready);
                            @(posedge clk);
                            @(negedge clk);
                            eq("cached accepted while busy", 1, 64'(maint_busy));
                            while (maint_busy) begin
                                eq("cached response waits for maintenance", 0,
                                   64'(dc_resp_valid));
                                if (u_dcache.ram_read_w) begin
                                    eq("maintenance owns array reads", 1,
                                       64'(u_dcache.state_r == u_dcache.S_MREAD ||
                                   u_dcache.state_r == u_dcache.S_MCHECK ||
                                           u_dcache.state_r == u_dcache.S_WB_READ));
                                end
                                @(negedge clk);
                            end
                        end
                    join
                end
                while (maint_busy || maint_req_valid) idle();
                expect_data_bus(B, 0, 0);
                eq("busy command did not write outside", 64'(initial_byte(B)),
                   64'(read_byte(B)));
            end
            309: begin
                data_access(A, 1, 2, 32'habcd1234);
                error_write_addr = A;
                put(12'h00c, 2);
                maintain(1, A, 32);
                error_count[2]++;
                reg_eq(12'h010, 2);
                reg_eq(12'h014, A);
                eq("writeback IRQ enabled", 1, 64'(irq));
                put(12'h00c, 0);
                eq("writeback IRQ disabled", 0, 64'(irq));
                put(12'h00c, 2);
                eq("writeback IRQ reenabled", 1, 64'(irq));
                put(12'h010, 2);
                reg_eq(12'h010, 0);
                eq("writeback IRQ cleared", 0, 64'(irq));
            end
            310: begin : covered_groups
                int lengths[8] = '{1, 2, 16, 128, 511, 512, 513, 2048};
                random_stalls = 0;
                delay_max = 0;
                for (int n = 0; n < 8; n++) begin
                    maintain(1, A + 511*32 + 3, 32'(lengths[n]*32-3));
                    eq("range tag reads", (lengths[n] < 512 ? 64'(lengths[n]) : 64'd512),
                       64'(measured_reads));
                    if (measured_cycles > (lengths[n] < 512 ? lengths[n] : 512)+8)
                        $fatal(1, "FAIL range cycle bound N=%0d cycles=%0d",
                               lengths[n], measured_cycles);
                    $display("PERF range lines=%0d cycles=%0d reads=%0d",
                             lengths[n], measured_cycles, measured_reads);
                end
                // Identical groups with different tags must retain the outside line.
                data_access(A);
                data_access(B);
                maintain(2, A+3, 1);
                expect_data_bus(B, 0, 0);
                expect_data_bus(A, 1, 0);
                // Unaligned crossing of group 511 -> 0 and an exclusive range end.
                for (int n = 510; n < 514; n++) data_access(A + 32'(n*32));
                maintain(2, A+16383, 2);
                eq("wrap visits two groups", 2, 64'(measured_reads));
                expect_data_bus(A+510*32, 0, 0);
                expect_data_bus(A+513*32, 0, 0);
                expect_data_bus(A+511*32, 1, 0);
                expect_data_bus(A+512*32, 1, 0);
                // Full 32 KiB capacity: every group and both ways remain resident.
                for (int n = 0; n < 1024; n++) data_access(A + 32'(n*32));
                for (int n = 0; n < 1024; n++) expect_data_bus(A + 32'(n*32), 0, 0);
                maintain(2, A, 2048*32);
                eq("large range reads each group once", 512, 64'(measured_reads));
                for (int n = 0; n < 1024; n++) expect_data_bus(A + 32'(n*32), 1, 0);
            end
            311: begin : dirty_segments
                random_stalls = 0;
                delay_max = 0;
                maintain(4);
                eq("empty clean tag reads", 0, 64'(measured_reads));
                if (measured_cycles > 40) $fatal(1, "FAIL empty clean cycles=%0d", measured_cycles);
                $display("PERF clean dirty=0 cycles=%0d", measured_cycles);
                for (int n = 0; n < 2; n++) begin
                    data_access(A + 32'(n*511*32), 1, 2, 32'h45670000 + 32'(n));
                    count = u_dmem.writes;
                    maintain(4);
                    eq("one dirty writeback", (64'(count)+64'd1), 64'(u_dmem.writes));
                    eq("dirty segment groups read", 16, 64'(measured_reads));
                    $display("PERF clean dirty=1 group=%0d cycles=%0d", n*511, measured_cycles);
                    compare_memory();
                end
                for (int n = 0; n < 32; n++)
                    data_access(A + 32'(n*16*32), 1, 2, 32'h12340000 + 32'(n));
                count = u_dmem.writes;
                maintain(4);
                eq("all segments written", (64'(count)+64'd32), 64'(u_dmem.writes));
                eq("dirty segments scanned", 512, 64'(measured_reads));
                $display("PERF clean dirty=32 segments=32 cycles=%0d", measured_cycles);
                compare_memory();
                for (int n = 0; n < 1024; n++)
                    data_access(A + 32'(n*32), 1, 2, 32'hfeed0000 + 32'(n));
                count = u_dmem.writes;
                maintain(4);
                eq("full dirty capacity written", (64'(count)+64'd1024), 64'(u_dmem.writes));
                eq("full dirty groups", 512, 64'(measured_reads));
                $display("PERF clean dirty=1024 cycles=%0d", measured_cycles);
                compare_memory();
            end
            313: begin
                data_access(A, 1, 2, 32'h12345678);
                data_access(A+32'h1e0, 1, 2, 32'h87654321);
                data_access(A+32'h3fe0, 1, 2, 32'habcdef01);
                idle(2);
                eq("first segment dirty", 1, 64'(u_dcache.segment_dirty_r[0]));
                eq("last segment dirty", 1, 64'(u_dcache.segment_dirty_r[31]));
                maintain(1, A, 32);
                eq("range clean retains other dirty line", 1,
                   64'(u_dcache.segment_dirty_r[0]));
                maintain(1, A+32'h1e0, 32);
                maintain(2, A+32'h1e0, 32);
                eq("range invalidate leaves conservative flag", 1,
                   64'(u_dcache.segment_dirty_r[0]));
                maintain(4);
                eq("whole clean clears flags", 0, 64'(u_dcache.segment_dirty_r));
                compare_memory();
                data_access(A+32'h200, 1, 2, 32'h11223344);
                idle(2);
                eq("store sets next segment", 2, 64'(u_dcache.segment_dirty_r));
                maintain(4);
                eq("second clean clears flags", 0, 64'(u_dcache.segment_dirty_r));
                compare_memory();
            end
            312: begin : interleaved_writeback
                for (int mode = 0; mode < 2; mode++) begin
                    for (int way = 0; way < 2; way++)
                        for (int n = 0; n < 8; n++)
                            data_access(A + 32'(way*16384+n*32), 1, 2,
                                        32'h76540000 + 32'(mode*32+way*8+n));
                    count = u_dmem.writes;
                    put(12'h020, A);
                    put(12'h024, 520*32);
                    put(12'h028, 3);
                    while (maint_req_valid) idle();
                    if (mode == 0) begin
                        while (maint_busy) data_access(STATUS);
                    end else data_access(A);
                    while (maint_busy) idle();
                    eq("interleaved dirty writes", (64'(count)+64'd16), 64'(u_dmem.writes));
                    eq("interleaved unique group reads", 512, 64'(measured_reads));
                    compare_memory();
                end
                random_stalls = 0;
                delay_max = 0;
                put(12'h020, A);
                put(12'h024, 512*32);
                put(12'h028, 1);
                while (maint_req_valid) idle();
                while (maint_busy) data_access(STATUS);
                if (measured_cycles > 520)
                    $fatal(1, "FAIL polling stalls traversal cycles=%0d", measured_cycles);
                $display("PERF polling range lines=512 cycles=%0d", measured_cycles);
            end
            401: begin
                fetch(A);
                data_access(A);
                hit_stream(1);
                hit_stream(0);
                hit_stream(0, 1);
            end
            402: begin : miss_performance
                time accepted_time;
                time first_read_time;
                time ar_time;
                int elapsed;
                int round_trip;
                random_stalls = 0;
                delay_max = 0;
                @(negedge clk);
                ic_req_valid = 1;
                ic_req_addr = A;
                do @(posedge clk); while (!ic_req_ready);
                accepted_time = $time;
                fork
                    begin
                        do @(posedge clk); while (!(ia.arvalid && ia.arready));
                        ar_time = $time;
                        do @(posedge clk); while (!(ia.rvalid && ia.rready));
                        first_read_time = $time;
                    end
                    begin
                        @(negedge clk);
                        ic_req_valid = 0;
                        do @(posedge clk); while (!ic_resp_valid);
                        elapsed = int'(($time-accepted_time)/10);
                        eq("performance instruction data", read_data(A, 8), ic_resp_data);
                    end
                join
                round_trip = int'((first_read_time-ar_time)/10);
                $display("PERF request_to_response=%0d axi_round_trip=%0d bound=%0d",
                         elapsed, round_trip, 1+4+round_trip+4);
                // One synchronous lookup cycle precedes miss determination.
                if (elapsed > 1+4+round_trip+4)
                    $fatal(1, "FAIL miss latency expected<=%0d actual=%0d time=%0t",
                           1+4+round_trip+4, elapsed, $time);
            end
            default: $fatal(1, "FAIL test selector expected=known actual=%0d time=%0t",
                            TEST, $time);
        endcase
        coverage_report();
        $display("PASS cache TEST=%0d seed=%0d cycles=%0d", TEST, seed, cycles);
        $finish;
    end
endmodule
