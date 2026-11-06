// File: edrv32_cpu_b1_tb.sv
// Spec: cpu-spec 3.1-3.4, 4.7; cpu-testplan 2.2-2.3, 4
// Description: B1 wiring and self-checking fixed-table stub harness.
// Clock: clk_sys.
module edrv32_cpu_b1_tb;
    import edrv32_cpu_memory::*;
    logic clk;
    logic rst_n;
    logic ic_req_valid;
    logic [31:0] ic_req_addr;
    logic ic_kill;
    logic ic_inv;
    wire [31:0] unused_early_data;
    wire [1:0] unused_early_way_hit;
    wire [63:0] unused_early_way_data;
    assign unused_early_data = ({32{unused_early_way_hit[0]}} & unused_early_way_data[31:0]) |
        ({32{unused_early_way_hit[1]}} & unused_early_way_data[63:32]);
    wire unused_early_failure_w = &{1'b0, u_dc_model.early_failure_r};
    logic dc_req_valid;
    logic [31:0] dc_req_addr;
    logic dc_req_store;
    logic [1:0] dc_req_size;
    logic dc_kill;
    logic dc_commit;
    logic [31:0] dc_store_data;
    logic dc_fence;
    logic dc_clean_all;
    logic [63:0] debug;
    logic ic_req_ready;
    logic ic_resp_valid;
    logic [63:0] ic_resp_data;
    logic ic_resp_err;
    logic ic_inv_done;
    logic dc_req_ready;
    logic dc_resp_valid;
    wire [31:0] dc_resp_data;
    wire [1:0] dc_resp_way_hit;
    wire [63:0] dc_resp_way_data;
    assign dc_resp_data = ({32{dc_resp_way_hit[0]}} & dc_resp_way_data[31:0]) |
        ({32{dc_resp_way_hit[1]}} & dc_resp_way_data[63:32]);
    logic dc_resp_err;
    logic dc_resp_device;
    logic dc_fence_done;
    logic dc_wb_event;
    logic irq_meip;
    logic irq_msip;
    logic irq_mtip;
    logic [63:0] mtime;
    logic done;
    edrv32_cpu_core u_core (
        .clk_i(clk),
        .rst_n_i(rst_n),
        .rst_sys_csr_n_i(rst_n),
        .rst_sys_counter_n_i({10{rst_n}}),
        .ic_req_valid_o(ic_req_valid),
        .ic_req_addr_o(ic_req_addr),
        .ic_kill_o(ic_kill),
        .ic_inv_o(ic_inv),
        .dc_req_valid_o(dc_req_valid),
        .dc_req_addr_o(dc_req_addr),
        .dc_req_store_o(dc_req_store),
        .dc_req_size_o(dc_req_size),
        .dc_kill_o(dc_kill),
        .dc_commit_o(dc_commit),
        .dc_store_data_o(dc_store_data),
        .dc_fence_o(dc_fence),
        .dc_clean_all_o(dc_clean_all),
        .debug_o(debug),
        .ic_req_ready_i(ic_req_ready),
        .ic_resp_valid_i(ic_resp_valid),
        .ic_resp_valid_copy_i({8{ic_resp_valid}}),
        .ic_resp_data_i(ic_resp_data),
        .ic_resp_err_i(ic_resp_err),
        .ic_inv_done_i(ic_inv_done),
        .dc_req_ready_i(dc_req_ready),
        .dc_resp_valid_i(dc_resp_valid),
        .dc_resp_way_data_i(dc_resp_way_data),
        .dc_resp_way_hit_i(dc_resp_way_hit),
        .dc_resp_err_i(dc_resp_err),
        .dc_resp_device_i(dc_resp_device),
        .dc_fence_done_i(dc_fence_done),
        .dc_wb_event_i(dc_wb_event),
        .irq_meip_i(irq_meip),
        .irq_msip_i(irq_msip),
        .irq_mtip_i(irq_mtip),
        .mtime_i(mtime)
    );
    logic ic_miss;
    logic ic_killed_fill;
    logic dc_miss;
    logic device_execute;
    logic write_buffer_valid;
    logic checker_device_execute;
    edrv32_cpu_ic_model u_ic_model (
        .clk_i(clk),
        .rst_n_i(rst_n),
        .ic_req_valid_i(ic_req_valid),
        .ic_req_addr_i(ic_req_addr),
        .ic_req_ready_o(ic_req_ready),
        .ic_resp_valid_o(ic_resp_valid),
        .ic_resp_data_o(ic_resp_data),
        .ic_resp_err_o(ic_resp_err),
        .ic_kill_i(ic_kill),
        .ic_inv_i(ic_inv),
        .ic_inv_done_o(ic_inv_done),
        .miss_o(ic_miss),
        .killed_fill_o(ic_killed_fill)
    );
    edrv32_cpu_dc_model u_dc_model (
        .clk_i(clk),
        .rst_n_i(rst_n),
        .dc_early_valid_i(1'b0),
        .dc_early_addr_i(32'b0),
        .dc_early_way_hit_o(unused_early_way_hit),
        .dc_early_way_data_o(unused_early_way_data),
        .dc_req_valid_i(dc_req_valid),
        .dc_req_addr_i(dc_req_addr),
        .dc_req_store_i(dc_req_store),
        .dc_req_size_i(dc_req_size),
        .dc_req_ready_o(dc_req_ready),
        .dc_resp_valid_o(dc_resp_valid),
        .dc_resp_way_data_o(dc_resp_way_data),
        .dc_resp_way_hit_o(dc_resp_way_hit),
        .dc_resp_err_o(dc_resp_err),
        .dc_resp_device_o(dc_resp_device),
        .dc_kill_i(dc_kill),
        .dc_commit_i(dc_commit),
        .dc_store_data_i(dc_store_data),
        .dc_fence_i(dc_fence),
        .dc_clean_all_i(dc_clean_all),
        .dc_fence_done_o(dc_fence_done),
        .dc_wb_event_o(dc_wb_event),
        .miss_o(dc_miss),
        .device_execute_o(device_execute),
        .write_buffer_valid_o(write_buffer_valid)
    );
    edrv32_cpu_irq_model u_irq_model (
        .clk_i(clk),
        .rst_n_i(rst_n),
        .trace_valid_i(u_core.trace_valid_w),
        .trace_pc_i(u_core.trace_pc_w),
        .irq_meip_o(irq_meip),
        .irq_msip_o(irq_msip),
        .irq_mtip_o(irq_mtip),
        .mtime_o(mtime)
    );
    edrv32_cpu_trace u_trace (
        .clk_i(clk),
        .rst_n_i(rst_n),
        .trace_valid_i(u_core.trace_valid_w),
        .trace_pc_i(u_core.trace_pc_w),
        .trace_instr_i(u_core.trace_instr_w),
        .trace_rd_i(u_core.trace_rd_w),
        .trace_rd_data_i(u_core.trace_rd_data_w),
        .trace_trap_i(u_core.trace_trap_w),
        .trace_cause_i(u_core.trace_cause_w)
    );
    edrv32_cpu_coverage u_coverage (
        .clk_i(clk),
        .rst_n_i(rst_n),
        .debug_i(debug),
        .irq_arrival_debug_i(debug),
        .trace_valid_i(u_core.trace_valid_w),
        .trace_instr_i(u_core.trace_instr_w),
        .trace_trap_i(u_core.trace_trap_w),
        .trace_cause_i(u_core.trace_cause_w),
        .trace_bypass_i(u_core.trace_bypass_w),
        .trace_redirect_stage_i(debug[17] ? 2'd1 : (debug[16] ? 2'd2 : 2'd0)),
        .early_condition_i(4'b0),
        .early_bypass_i(1'b0),
        .early_failure_i(3'b0),
        .trace_redirect_cause_i(u_core.trace_redirect_cause_w),
        .trace_stall_cause_i(u_core.trace_stall_cause_w),
        .pair_valid_i(1'b0),
        .pair_swap_i(1'b0),
        .trap_slot_i(1'b0),
        .e_redirect_slot_i(1'b0),
        .d_redirect_slot_i(1'b0),
        .irq_meip_i(irq_meip),
        .irq_msip_i(irq_msip),
        .irq_mtip_i(irq_mtip)
    );
    edrv32_cpu_protocol_checker u_checker (
        .clk_i(clk),
        .rst_n_i(rst_n),
        .ic_req_valid_i(ic_req_valid),
        .ic_req_addr_i(ic_req_addr),
        .ic_req_ready_i(ic_req_ready),
        .ic_resp_valid_i(ic_resp_valid),
        .ic_resp_err_i(ic_resp_err),
        .ic_kill_i(ic_kill),
        .dc_req_valid_i(dc_req_valid),
        .dc_req_ready_i(dc_req_ready),
        .dc_req_addr_i(dc_req_addr),
        .dc_req_store_i(dc_req_store),
        .dc_req_size_i(dc_req_size),
        .dc_resp_valid_i(dc_resp_valid),
        .dc_resp_err_i(dc_resp_err),
        .dc_resp_device_i(dc_resp_device),
        .dc_kill_i(dc_kill),
        .dc_commit_i(dc_commit),
        .redirect_flush_i(1'b0),
        .m_enter_i(u_core.m_enter_w && violation != 3),
        .device_execute_i(checker_device_execute)
    );
    assign done = u_core.done_w;
    integer image_descriptor;
    integer cycles = 0;
    integer ic_miss_cycles = 0;
    integer dc_miss_cycles = 0;
    integer backpressure_cycles = 0;
    integer killed_fills = 0;
    integer irq_seen = 0;
    integer wb_seen = 0;
    integer violation = 0;
    string mem_hex = "verif/block/cpu/b1/program.hex";
    bit injected_device_execute = 0;
    assign checker_device_execute = device_execute || injected_device_execute;

    initial begin
        clk = 0;
        forever #5 clk = !clk;
    end
    initial begin
        rst_n = 0;
        void'($value$plusargs("MEM_HEX=%s", mem_hex));
        image_descriptor = $fopen(mem_hex, "r");
        if (image_descriptor == 0)
            $fatal(1, "FAIL cannot open memory image %s", mem_hex);
        $fclose(image_descriptor);
        $readmemh(mem_hex, memory);
        void'($value$plusargs("VIOLATION=%d", violation));
        // Self-test defaults deliberately exercise every required environment component.
        // Explicit plusargs override these deterministic stress settings.
        @(negedge clk);
        if (!$test$plusargs("IC_MISS_PCT="))
            u_ic_model.miss_pct = 100;
        if (!$test$plusargs("IC_DELAY_MAX="))
            u_ic_model.delay_max = 8;
        if (!$test$plusargs("DC_MISS_PCT="))
            u_dc_model.miss_pct = 100;
        if (!$test$plusargs("DC_DELAY_MAX="))
            u_dc_model.delay_max = 8;
        if (!$test$plusargs("IC_READY_LOW_PCT="))
            u_ic_model.ready_low_pct = 40;
        if (!$test$plusargs("DC_READY_LOW_PCT="))
            u_dc_model.ready_low_pct = 40;
        if (!$test$plusargs("DC_WB_EVENT_CYCLE="))
            u_dc_model.wb_event_cycle = 3;
        if (!$test$plusargs("TOHOST_ADDR=")) begin
            u_dc_model.tohost_enabled = 1;
            u_dc_model.tohost_addr = 32'h10001000;
        end
        for (int index = 0; index < 3; index++) begin
            if (u_irq_model.start_cycle[index] == -1 && !u_irq_model.pc_enabled[index])
                u_irq_model.start_cycle[index] = 2 + index;
        end
        repeat (3) @(negedge clk);
        rst_n = 1;
        if (violation == 2) begin
            @(negedge clk);
            injected_device_execute = 1;
            repeat (2) @(negedge clk);
            $fatal(1, "FAIL checker failed to reject uncommitted device execution");
        end
        wait (done);
        repeat (2) @(negedge clk);
        if (irq_seen != 7)
            $fatal(1, "FAIL missing interrupt stimulus: seen %03b", irq_seen);
        if (wb_seen != 1 || u_dc_model.wb_event_count != 1)
            $fatal(1, "FAIL dirty writeback pulse expected 1 got %0d", wb_seen);
        if (!tohost_valid || tohost_value != 1)
            $fatal(1, "FAIL tohost expected 1 got valid=%b value=%08x", tohost_valid, tohost_value);
        if (!$test$plusargs("IC_MISS_PCT=") && (ic_miss_cycles == 0 || killed_fills == 0))
            $fatal(1, "FAIL self-test did not exercise I$ miss and killed fill");
        if (!$test$plusargs("DC_MISS_PCT=") && dc_miss_cycles == 0)
            $fatal(1, "FAIL self-test did not exercise D$ miss");
        if (backpressure_cycles == 0)
            $fatal(1, "FAIL self-test did not exercise backpressure");
        if (u_core.retired != 3)
            $fatal(1, "FAIL retired count expected 3 got %0d", u_core.retired);
        if (!$test$plusargs("DC_ERROR_ADDR=") && device_accesses != 2)
            $fatal(1, "FAIL device accesses expected 2 got %0d", device_accesses);
        $display("PASS B1 cycles=%0d ic_miss=%0d dc_miss=%0d backpressure=%0d killed=%0d",
            cycles, ic_miss_cycles, dc_miss_cycles, backpressure_cycles, killed_fills);
        $display("debug=%016x write_buffer=%b tohost=%b:%08x",
            debug, write_buffer_valid, tohost_valid, tohost_value);
        $finish;
    end

    // C-V5 mounting points: cache events, trace lanes, debug_o and all interrupt inputs
    // are named wires above. These counters verify the environment's own exercise only.
    always @(posedge clk) begin
        if (rst_n) begin
            cycles <= cycles + 1;
            if (ic_miss)
                ic_miss_cycles <= cycles + 1;
            if (dc_miss)
                dc_miss_cycles <= cycles + 1;
            if ((ic_req_valid && !ic_req_ready) || !dc_req_ready)
                backpressure_cycles <= cycles + 1;
            if (ic_killed_fill)
                killed_fills <= killed_fills + 1;
            irq_seen <= irq_seen | {29'b0, irq_mtip, irq_msip, irq_meip};
            if (dc_wb_event)
                wb_seen <= wb_seen + 1;
            if (cycles > 2000)
                $fatal(1, "FAIL B1 self-test timeout at cycle %0d", cycles);
        end
    end
endmodule
