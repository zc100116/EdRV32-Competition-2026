// File: edrv32_cpu_b1_tb.sv
// Spec: cpu-spec 3.1-3.4, 4.7; cpu-testplan 2.2-2.3, 4
// Description: B1 wiring and real-core integration harness.
// Clock: clk_sys.
// Ordered observer/model updates intentionally use blocking assignments.
/* verilator lint_off BLKSEQ */
module edrv32_cpu_b1_core_tb;
    import edrv32_cpu_memory::*;
    logic clk;
    // The stimulus reset drives asynchronous DUT reset and synchronous observers.
    /* verilator lint_off SYNCASYNCNET */
    logic rst_n;
    /* verilator lint_on SYNCASYNCNET */
    logic ic_req_valid;
    logic [31:0] ic_req_addr;
    logic ic_kill;
    logic ic_inv;
    logic dc_early_valid;
    logic [31:0] dc_early_addr;
    wire dc_early_hit;
    assign dc_early_hit = |dc_early_way_hit;
    wire [1:0] dc_early_way_hit;
    wire [63:0] dc_early_way_data;

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
    wire dc_req_early;
    edrv32_cpu_core u_core (
        .clk_i(clk),
        .rst_n_i(rst_n),
        .rst_sys_csr_n_i(rst_n),
        .rst_sys_counter_n_i({10{rst_n}}),
        .ic_req_valid_o(ic_req_valid),
        .ic_req_addr_o(ic_req_addr),
        .ic_kill_o(ic_kill),
        .ic_inv_o(ic_inv),
        .dc_early_valid_o(dc_early_valid),
        .dc_early_addr_o(dc_early_addr),
        .dc_early_way_hit_i(dc_early_way_hit),
        .dc_early_way_data_i(dc_early_way_data),
        .dc_req_valid_o(dc_req_valid),
        .dc_req_early_o(dc_req_early),
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
    logic unused_ic_killed_fill;
    logic unused_dc_miss;
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
        .killed_fill_o(unused_ic_killed_fill)
    );
    edrv32_cpu_dc_model u_dc_model (
        .clk_i(clk),
        .rst_n_i(rst_n),
        .dc_early_valid_i(dc_early_valid),
        .dc_early_addr_i(dc_early_addr),
        .dc_early_way_hit_o(dc_early_way_hit),
        .dc_early_way_data_o(dc_early_way_data),
        .dc_req_valid_i(dc_req_valid),
        .dc_req_early_i(dc_req_early),
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
        .miss_o(unused_dc_miss),
        .device_execute_o(device_execute),
        .write_buffer_valid_o(write_buffer_valid)
    );
    logic [2:0] base_irq;
    logic [2:0] scheduled_irq = 0;
    logic [63:0] irq_arrival_debug = 0;
    logic [63:0] base_mtime;
    logic [63:0] fixed_mtime;
    bit mtime_fixed;
    assign {irq_mtip, irq_msip, irq_meip} = base_irq | scheduled_irq;
    assign mtime = mtime_fixed ? fixed_mtime : base_mtime;
    initial mtime_fixed = $value$plusargs("MTIME_FIXED=%h", fixed_mtime);

    integer irq_count = 0;
    integer irq_kind[16];
    integer irq_mask[16];
    integer irq_delay[16];
    integer irq_wait[16];
    logic [31:0] irq_pc[16];
    logic [31:0] irq_clear_pc[16];
    bit irq_fired[16];
    bit irq_armed[16];
    bit wake_every_wfi;
    logic [31:0] sleeping_wfi_pc=0;
    bit irq_taken;
    logic [31:0] taken_cause;
    integer dc_error_count = 0;
    logic [31:0] dc_error_pc[16];
    integer dc_delay_count = 0;
    logic [31:0] dc_delay_pc[16];
    integer dc_delay_cycles[16];
    bit hpm_ic_injected = 0;
    bit hpm_dc_injected = 0;
    integer hpm_active_cycles = 0;
    integer default_ic_miss;
    integer default_dc_miss;
    integer default_dc_min;
    integer default_dc_max;
    bit default_dc_error;
    bit buffer_hold_enabled;
    logic [31:0] buffer_hold_pc;
    integer buffer_hold_cycles;
    logic [31:0] ready_low_pc;
    integer ready_low_cycles;
    integer ready_low_remaining = 0;
    bit ready_low_enabled;
    bit ready_low_started = 0;
    initial begin
        ready_low_enabled = $value$plusargs("DC_READY_LOW_PC=%h", ready_low_pc);
        void'($value$plusargs("DC_READY_LOW_CYCLES=%d", ready_low_cycles));
    end
    initial begin
        buffer_hold_enabled = $value$plusargs("WB_HOLD_PC=%h", buffer_hold_pc);
        void'($value$plusargs("WB_HOLD_CYCLES=%d", buffer_hold_cycles));
        void'($value$plusargs("IRQ_COUNT=%d", irq_count));
        wake_every_wfi = $test$plusargs("WAKE_EVERY_WFI");
        for (int index = 0; index < irq_count; index++) begin
            void'($value$plusargs($sformatf("IRQ%0d_KIND=%%d", index), irq_kind[index]));
            void'($value$plusargs($sformatf("IRQ%0d_MASK=%%d", index), irq_mask[index]));
            void'($value$plusargs($sformatf("IRQ%0d_PC=%%h", index), irq_pc[index]));
            void'($value$plusargs($sformatf("IRQ%0d_CLEAR_PC=%%h", index), irq_clear_pc[index]));
            void'($value$plusargs($sformatf("IRQ%0d_DELAY=%%d", index), irq_delay[index]));
        end
        void'($value$plusargs("DC_ERROR_COUNT=%d", dc_error_count));
        for (int index = 0; index < dc_error_count; index++)
            void'($value$plusargs($sformatf("DC_ERROR%0d_PC=%%h", index), dc_error_pc[index]));
        void'($value$plusargs("DC_DELAY_COUNT=%d", dc_delay_count));
        for (int index = 0; index < dc_delay_count; index++) begin
            void'($value$plusargs($sformatf("DC_DELAY%0d_PC=%%h", index), dc_delay_pc[index]));
            void'($value$plusargs($sformatf("DC_DELAY%0d_CYCLES=%%d", index),
                dc_delay_cycles[index]));
        end
        @(negedge clk);
        default_ic_miss = u_ic_model.miss_pct;
        default_dc_miss = u_dc_model.miss_pct;
        default_dc_min = u_dc_model.delay_min;
        default_dc_max = u_dc_model.delay_max;
        default_dc_error = u_dc_model.error_enabled;
    end
    always @(posedge clk) begin
        irq_taken <= rst_n && u_core.trace_trap_w && u_core.trace_cause_w[31];
        taken_cause <= u_core.trace_cause_w;
        if (rst_n && test_id == "c-03" && hpm_reference_window) begin
            if (ic_req_valid && ic_req_ready)
                hpm_ic_injected = 1;
            if (dc_req_valid && dc_req_ready && !device(dc_req_addr))
                hpm_dc_injected = 1;
        end
    end
    // Inject between active edges so the next edge samples the precise pipeline window.
    always @(negedge clk) begin
        if (rst_n) begin
            if (debug[29] && u_core.trace_redirect_stage_w==3)
                sleeping_wfi_pc=u_core.trace_redirect_pc_w;
            if (irq_taken) begin
                case (taken_cause)
                    32'h8000000b: scheduled_irq[0] = 0;
                    32'h80000003: scheduled_irq[1] = 0;
                    32'h80000007: scheduled_irq[2] = 0;
                    default: begin end
                endcase
            end
            if (wake_every_wfi) begin
                if (debug[29])
                    scheduled_irq[1] = 1;
                else if (u_core.m_valid_r[0])
                    scheduled_irq[1] = 0;
            end
            for (int index = 0; index < irq_count; index++) begin
                if (irq_fired[index] && irq_clear_pc[index] != 0 &&
                    u_core.m_valid_r[0] && u_core.m_record_r[0][31:0] == irq_clear_pc[index])
                    scheduled_irq = scheduled_irq & ~3'(irq_mask[index]);
                if (!irq_fired[index]) begin
                    case (irq_kind[index])
                        1: irq_armed[index] =
                            (u_core.m_valid_r[0] &&
                                issued_slot[u_core.m_record_r[0][31:0]] == 0 &&
                                u_core.m_record_r[0][31:0] == irq_pc[index]) ||
                            (u_core.m_valid_r[1] &&
                                issued_slot[u_core.m_record_r[1][31:0]] == 0 &&
                                u_core.m_record_r[1][31:0] == irq_pc[index]);
                        2: irq_armed[index] = debug[25] &&
                            u_core.e_record_r[0][31:0] == irq_pc[index];
                        3: irq_armed[index] = debug[26] &&
                            u_core.m_record_r[0][31:0] == irq_pc[index];
                        4: irq_armed[index] = debug[28] &&
                            u_core.m_record_r[0][31:0] == irq_pc[index];
                        5: irq_armed[index] = u_core.trace_redirect_stage_w == 2 &&
                            u_core.trace_redirect_pc_w == irq_pc[index];
                        6: irq_armed[index] = debug[29] && sleeping_wfi_pc == irq_pc[index];
                        7: irq_armed[index] = dc_clean_all &&
                            u_core.m_record_r[0][31:0] == irq_pc[index];
                        default: irq_armed[index] = 0;
                    endcase
                    if (irq_armed[index]) begin
                        if (irq_wait[index] >= irq_delay[index]) begin
                            irq_arrival_debug = debug;
                            scheduled_irq = scheduled_irq | 3'(irq_mask[index]);
                            irq_fired[index] = 1;
                        end else
                            irq_wait[index]++;
                    end
                end
            end
            if (ready_low_enabled && !ready_low_started && u_core.e_valid_r[0] &&
                u_core.e_record_r[0][31:0] == ready_low_pc) begin
                ready_low_remaining = ready_low_cycles;
                ready_low_started = 1;
            end
            u_dc_model.forced_ready_low = ready_low_remaining > 0;
            if (ready_low_remaining > 0) begin
                ready_low_remaining--;
            end
            u_dc_model.buffer_hold_cycles = buffer_hold_enabled && u_core.m_valid_r[0] &&
                u_core.m_record_r[0][31:0] == buffer_hold_pc ? buffer_hold_cycles : 0;
            u_dc_model.error_enabled = default_dc_error;
            for (int index = 0; index < dc_error_count; index++) begin
                if (u_core.e_valid_r[0] && u_core.e_record_r[0][31:0] == dc_error_pc[index]) begin
                    u_dc_model.error_enabled = 1;
                    u_dc_model.error_addr = dc_req_addr;
                end
            end
            if (test_id == "c-03") begin
                if (!hpm_reference_window) begin
                    hpm_ic_injected = 0;
                    hpm_dc_injected = 0;
                    hpm_active_cycles = 0;
                end else begin
                    hpm_active_cycles++;
                    if (hpm_active_cycles == 2 || hpm_active_cycles == 6 ||
                        hpm_active_cycles == 10)
                        u_dc_model.wb_event_cycle = u_dc_model.cycle_r;
                end
                u_ic_model.miss_pct = hpm_reference_window && !hpm_ic_injected ? 100 :
                    default_ic_miss;
                u_ic_model.delay_min = 12;
                u_ic_model.delay_max = 12;
            end
            u_dc_model.miss_pct = default_dc_miss;
            u_dc_model.delay_min = default_dc_min;
            u_dc_model.delay_max = default_dc_max;
            if (test_id == "c-03" && hpm_reference_window) begin
                u_dc_model.miss_pct = hpm_dc_injected ? 0 : 100;
                u_dc_model.delay_min = 20;
                u_dc_model.delay_max = 20;
            end
            for (int index = 0; index < dc_delay_count; index++) begin
                if (u_core.e_valid_r[0] && u_core.e_record_r[0][31:0] == dc_delay_pc[index]) begin
                    u_dc_model.miss_pct = 100;
                    u_dc_model.delay_min = dc_delay_cycles[index];
                    u_dc_model.delay_max = dc_delay_cycles[index];
                end
            end
        end
    end
    edrv32_cpu_irq_model u_irq_model (
        .clk_i(clk),
        .rst_n_i(rst_n),
        .trace_valid_i(u_core.trace_valid_w),
        .trace_pc_i(u_core.trace_pc_w),
        .irq_meip_o(base_irq[0]),
        .irq_msip_o(base_irq[1]),
        .irq_mtip_o(base_irq[2]),
        .mtime_o(base_mtime)
    );
    logic [1:0] trace_valid;
    bit trace_ended = 0;
    bit tohost_pending = 0;
    logic [31:0] tohost_pc;
    logic [31:0] tohost_addr;
    initial begin
        if (!$value$plusargs("TOHOST_ADDR=%h", tohost_addr))
            $fatal(1, "FAIL missing TOHOST_ADDR");
    end
    // Stop at the architectural tohost store, including it and excluding younger lanes.
    assign trace_valid = trace_ended ? 2'b0 :
        tohost_pending && u_core.trace_pc_w[31:0] == tohost_pc ?
        {1'b0, u_core.trace_valid_w[0]} : u_core.trace_valid_w;
    always @(posedge clk) begin
        if (rst_n) begin
            if (dc_commit && u_core.m_instr_r[6:0] == 7'h23 &&
                u_core.m_result_r[0] == tohost_addr && dc_store_data != 0) begin
                tohost_pending <= 1;
                tohost_pc <= u_core.m_record_r[0][31:0];
            end
            if (tohost_pending &&
                ((trace_valid[0] && u_core.trace_pc_w[31:0] == tohost_pc) ||
                    (trace_valid[1] && u_core.trace_pc_w[63:32] == tohost_pc)))
                trace_ended <= 1;
        end
    end
    edrv32_cpu_trace u_trace (
        .clk_i(clk),
        .rst_n_i(rst_n),
        .trace_valid_i(trace_valid),
        .trace_pc_i(u_core.trace_pc_w),
        .trace_instr_i(u_core.trace_instr_w),
        .trace_rd_i(u_core.trace_rd_w),
        .trace_rd_data_i(u_core.trace_rd_data_w),
        .trace_trap_i(u_core.trace_trap_w && !trace_ended),
        .trace_cause_i(u_core.trace_cause_w)
    );
    edrv32_cpu_coverage u_coverage (
        .clk_i(clk),
        .rst_n_i(rst_n),
        .debug_i(debug),
        .irq_arrival_debug_i(test_id == "e-03" ? irq_arrival_debug : debug),
        .trace_valid_i(u_core.trace_valid_w),
        .trace_instr_i(u_core.trace_instr_w),
        .trace_trap_i(u_core.trace_trap_w),
        .trace_cause_i(u_core.trace_cause_w),
        .trace_bypass_i(u_core.trace_bypass_w),
        .trace_redirect_stage_i(u_core.trace_redirect_stage_w),
        .early_condition_i(early_condition),
        .early_bypass_i(early_issue_previous && dc_early_hit && u_core.e_valid_r[0] &&
            u_core.e_record_r[0][38:32] == 7'h03 &&
            (u_core.trace_bypass_w[2:0] == 1 || u_core.trace_bypass_w[5:3] == 1 ||
                u_core.trace_bypass_w[8:6] == 1 || u_core.trace_bypass_w[11:9] == 1)),
        .early_failure_i(u_dc_model.early_failure_r),
        .trace_redirect_cause_i(u_core.trace_redirect_cause_w),
        .trace_stall_cause_i(u_core.trace_stall_cause_w),
        .pair_valid_i(observed_pair_valid),
        .pair_swap_i(observed_pair_swap),
        .trap_slot_i(observed_trap_slot),
        .e_redirect_slot_i(observed_e_slot),
        .d_redirect_slot_i(observed_d_slot),
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
        .redirect_flush_i(u_core.trace_redirect_stage_w != 0 || u_core.trace_trap_w),
        .m_enter_i(u_core.e_advance_w),
        .device_execute_i(checker_device_execute)
    );
    integer dc_probe_count = 0;
    logic [31:0] dc_probe_pc[16];
    integer dc_probe_descriptor;
    string dc_probe_path;
    integer dc_probe_start = -1;
    logic [31:0] dc_probe_addr;
    initial begin
        if ($value$plusargs("DC_PROBE_FILE=%s", dc_probe_path)) begin
            dc_probe_descriptor = $fopen(dc_probe_path, "w");
            void'($value$plusargs("DC_PROBE_COUNT=%d", dc_probe_count));
            for (int index = 0; index < dc_probe_count; index++)
                void'($value$plusargs($sformatf("DC_PROBE%0d_PC=%%h", index),
                    dc_probe_pc[index]));
        end
    end
    always @(posedge clk) begin
        if (rst_n && dc_probe_count != 0) begin
            if (dc_probe_start >= 0 && dc_resp_valid && !dc_kill) begin
                $fdisplay(dc_probe_descriptor, "response %h %h %b %0d",
                    dc_probe_addr, dc_resp_data, dc_resp_err, cycles-dc_probe_start);
                dc_probe_start = -1;
            end
            for (int index = 0; index < dc_probe_count; index++) begin
                if (dc_req_valid && dc_req_ready &&
                    u_core.e_record_r[0][31:0] == dc_probe_pc[index]) begin
                    dc_probe_start = cycles;
                    dc_probe_addr = dc_req_addr;
                    $fdisplay(dc_probe_descriptor, "request %h %b %h %h %0d",
                        dc_probe_addr, write_buffer_valid, u_dc_model.buffer_addr_r,
                        u_dc_model.buffer_data_r, device_accesses);
                end
            end
            for (int index = 0; index < dc_probe_count; index++) begin
                if (dc_commit && u_core.m_record_r[0][31:0] == dc_probe_pc[index])
                    $fdisplay(dc_probe_descriptor, "commit %h", u_core.m_result_r[0]);
            end
        end
    end
    integer image_descriptor;
    integer cycles = 0;
    integer timeout_cycles = 1000000;
    integer signature_descriptor;
    logic [31:0] signature_begin;
    logic [31:0] signature_end;
    string signature_path;
    string mem_hex;
    assign checker_device_execute = device_execute;

    initial begin
        clk = 0;
        forever #5 clk = !clk;
    end
    initial begin
        rst_n = 0;
        if (!$value$plusargs("MEM_HEX=%s", mem_hex))
            $fatal(1, "FAIL missing MEM_HEX");
        image_descriptor = $fopen(mem_hex, "r");
        if (image_descriptor == 0)
            $fatal(1, "FAIL cannot open memory image %s", mem_hex);
        $fclose(image_descriptor);
        $readmemh(mem_hex, memory);
        void'($value$plusargs("TIMEOUT_CYCLES=%d", timeout_cycles));
        repeat (4) @(negedge clk);
        rst_n = 1;
        wait (tohost_valid && tohost_value != 0);
        @(negedge clk);
        if (tohost_value != 1)
            $fatal(1, "FAIL tohost=%08x cycle=%0d", tohost_value, cycles);
        // Architectural termination includes the tohost store in W2.
        wait (trace_ended);
        @(negedge clk);
        if ($value$plusargs("SIGNATURE_FILE=%s", signature_path)) begin
            if (!$value$plusargs("SIGNATURE_BEGIN=%h", signature_begin)
                || !$value$plusargs("SIGNATURE_END=%h", signature_end))
                $fatal(1, "FAIL missing signature bounds");
            signature_descriptor = $fopen(signature_path, "w");
            if (signature_descriptor == 0)
                $fatal(1, "FAIL cannot open signature %s", signature_path);
            for (logic [31:0] addr = signature_begin; addr < signature_end; addr += 4)
                $fdisplay(signature_descriptor, "%08x", read_data(addr, 2));
            $fclose(signature_descriptor);
        end
        if (dc_probe_count != 0)
            $fclose(dc_probe_descriptor);
        check_directed_completion();
        $display("PASS CPU B1 cycles=%0d no-C", cycles);
        $finish;
    end
    always @(posedge clk) begin
        if (rst_n) begin
            cycles <= cycles + 1;
            if (cycles >= timeout_cycles)
                $fatal(1, "FAIL B1 timeout cycle=%0d pc=%08x debug=%016x",
                    cycles, u_core.m_record_r[0][31:0], debug);
        end
    end
    `include "edrv32_cpu_directed_checks.svh"
endmodule

/* verilator lint_on BLKSEQ */
