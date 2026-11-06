// File: edrv32_cpu_directed_checks.svh
// Spec: cpu-testplan 3.3-3.7; cpu-spec 5, 7
// Description: Independent issue/retirement event reference and directed obligations.
// Clock: clk_sys; included in the real-core B1 harness.
    `include "edrv32_cpu_tournament_checks.svh"
    string test_id;
    logic [31:0] expected_instret_addr;
    logic [31:0] expected_hpm_addr;
    bit has_instret_mailbox;
    bit has_hpm_mailbox;
    logic [31:0] reference_inhibit = 0;
    logic [63:0] reference_instret = 0;
    logic [63:0] reference_hpm = 0;
    integer reference_selector = 0;
    integer reference_events[17];
    integer delayed_reference_events[17];
    integer event_witness[17];
    integer window_events[17];
    bit hpm_reference_window = 0;
    logic reference_ic_expect = 0;
    logic reference_dc_expect = 0;
    logic [31:0] observer_instruction;
    logic [31:0] observer_operand;
    logic [31:0] observer_written;
    integer observer_retire;
    integer reference_pair_reason;
    logic [31:0] candidate0;
    logic [31:0] candidate1;
    logic [63:0] expected_debug;
    logic observer_div_previous = 0;
    logic [5:0] observer_pipeline_valid;
    logic [357:0] observer_e_records;
    logic [357:0] observer_m_records;
    logic [357:0] observer_w_records;
    integer device_wait_cycles = 0;
    bit store_stream_enabled;
    logic [31:0] store_stream_pc;
    integer store_stream_count = 0;
    integer store_stream_previous = -1;
    integer redirect_count = 0;
    integer dual_retire_count = 0;
    integer max_priority_overlap = 0;
    integer ic_miss_backend_progress = 0;
    bit clean_observed = 0;
    integer clean_begin_cycle = -1;
    integer invalidate_begin_cycle = -1;
    bit invalidate_observed = 0;
    bit buffer_hold_observed = 0;
    integer csr_issue_count = 0;
    bit predictor_probe_enabled;
    bit predictor_probe_seen = 0;
    logic [31:0] predictor_probe_pc;
    string predictor_path;
    integer predictor_descriptor;
    logic early_query_previous = 0;
    logic [31:0] early_query_pc;
    always @(posedge clk) begin
        early_query_previous <= rst_n && dc_early_valid;
        for (int slot = 0; slot < 2; slot++) begin
            if (rst_n && dc_early_valid && int'(u_core.d_issue_w) > slot &&
                u_core.d_record_w[slot][38:32] == 7'h03)
                early_query_pc <= u_core.d_record_w[slot][31:0];
        end
    end
    integer observer_file;
    integer observer_rows = 0;
    integer observer_status;
    string observer_path;
    integer obligation_kind[1024];
    logic [31:0] obligation_pc[1024];
    logic [31:0] obligation_other[1024];
    integer obligation_arg0[1024];
    integer obligation_arg1[1024];
    integer obligation_seen[1024];
    integer obligation_producer_cycle[1024];

    // Decoders deliberately inspect only the architecturally relevant fields.
    /* verilator lint_off UNUSEDSIGNAL */
    function automatic bit uses_rs1(input logic [31:0] instruction);
        return instruction[6:0] == 7'h33 || instruction[6:0] == 7'h13 ||
            instruction[6:0] == 7'h03 || instruction[6:0] == 7'h23 ||
            instruction[6:0] == 7'h63 || instruction[6:0] == 7'h67 ||
            (instruction[6:0] == 7'h73 && instruction[14:12] != 0 && !instruction[14]);
    endfunction
    function automatic bit uses_rs2(input logic [31:0] instruction);
        return instruction[6:0] == 7'h33 || instruction[6:0] == 7'h23 ||
            instruction[6:0] == 7'h63;
    endfunction
    function automatic bit writes_rd(input logic [31:0] instruction);
        return instruction[6:0] == 7'h33 || instruction[6:0] == 7'h13 ||
            instruction[6:0] == 7'h03 || instruction[6:0] == 7'h37 ||
            instruction[6:0] == 7'h17 || instruction[6:0] == 7'h6f ||
            instruction[6:0] == 7'h67 ||
            (instruction[6:0] == 7'h73 && instruction[14:12] != 0);
    endfunction
    function automatic bit alu_instruction(input logic [31:0] instruction);
        return instruction[6:0] == 7'h13 || instruction[6:0] == 7'h37 ||
            instruction[6:0] == 7'h17 ||
            (instruction[6:0] == 7'h33 && instruction[31:25] != 1);
    endfunction
    // cpu-spec 2.2/4.2: execution capability is independent of logical age.
    function automatic bit control_instruction(input logic [31:0] instruction);
        return instruction[6:0] == 7'h63 || instruction[6:0] == 7'h6f ||
            instruction[6:0] == 7'h67;
    endfunction
    function automatic bit pipe1_instruction(input logic [31:0] instruction);
        return alu_instruction(instruction) || instruction[6:0] == 7'h63 ||
            instruction[6:0] == 7'h6f;
    endfunction
    function automatic bit legal_instruction(input logic [31:0] instruction);
        case (instruction[6:0])
            7'h37, 7'h17, 7'h6f: return 1;
            7'h67: return instruction[14:12] == 0;
            7'h63: return instruction[14:12] != 2 && instruction[14:12] != 3;
            7'h03: return instruction[14:12] inside {0, 1, 2, 4, 5};
            7'h23: return instruction[14:12] <= 2;
            7'h13: begin
                if (instruction[14:12] == 1)
                    return instruction[31:25] == 0;
                if (instruction[14:12] == 5)
                    return instruction[31:25] inside {0, 7'h20};
                return 1;
            end
            7'h33: return instruction[31:25] inside {0, 1} ||
                (instruction[31:25] == 7'h20 && instruction[14:12] inside {0, 5});
            7'h0f: return instruction[14:12] inside {0, 1};
            7'h73: return instruction[14:12] inside {1, 2, 3, 5, 6, 7} ||
                instruction inside {32'h00000073, 32'h00100073, 32'h30200073, 32'h10500073};
            default: return 0;
        endcase
    endfunction
    /* verilator lint_on UNUSEDSIGNAL */
    integer issued_slot[logic [31:0]];
    integer issued_pipe[logic [31:0]];
    integer issued_order[logic [31:0]];
    integer issue_serial = 0;
    bit cold_jal_flushed[logic [31:0]];
    logic cold_slot0_redirect;
    assign cold_slot0_redirect = u_core.d_count_w != 0 &&
        !u_core.d_redirected_r && !u_core.d_redirect_r &&
        !u_core.d_record_w[0][99] &&
        u_core.d_record_w[0][38:32] == 7'h6f;
    logic observed_e_slot;
    logic observed_e_pipe;
    logic observed_d_slot;
    logic observed_trap_slot;
    logic observed_pair_swap;
    logic observed_pair_valid;
    logic [31:0] observed_e_pc;
    integer redirect_start[1024];
    bit obligation_redirect_seen[1024];
    integer expected_pipe;
    assign observed_pair_valid = u_core.d_issue_w == 2;
    assign observed_pair_swap = !pipe1_instruction(u_core.d_record_w[1][63:32]);
    assign observed_d_slot = 1'(issued_slot[u_core.trace_redirect_pc_w]);
    // A synchronous trap can commit one older instruction only for a slot-1 fault.
    assign observed_trap_slot = |u_core.m_commit_w;
    always_comb begin
        observed_e_pipe = u_core.e_valid_r[1] &&
            control_instruction(u_core.e_record_r[1][63:32]);
        observed_e_pc = u_core.e_record_r[observed_e_pipe][31:0];
        observed_e_slot = 1'(issued_slot[u_core.trace_redirect_pc_w]);
    end
    /* verilator lint_off UNUSEDSIGNAL */
    logic [3:0] early_condition;
    logic [31:0] early_candidate;
    logic [31:0] early_producer;
    logic [4:0] early_source;
    always_comb begin
        early_condition = 0;
        early_candidate = 0;
        early_producer = 0;
        early_source = 0;
        for (int slot = 0; slot < 2; slot++) begin
            if (early_condition == 0 && int'(u_core.d_count_w) > slot &&
                u_core.d_record_w[slot][38:32] == 7'h03) begin
                early_candidate = u_core.d_record_w[slot][63:32];
                early_source = early_candidate[19:15];
                early_condition = early_source == 0 ? 8 : 9;
                for (int pipe = 0; pipe < 2; pipe++) begin
                    early_producer = u_core.w_record_r[pipe][95:64];
                    if (early_source != 0 && u_core.w_valid_r[pipe] &&
                        writes_rd(early_producer) && early_producer[11:7] == early_source)
                        early_condition = early_producer[6:0] == 7'h33 &&
                            early_producer[31:25] == 1 && !early_producer[14] ? 6 : 7;
                end
                for (int pipe = 0; pipe < 2; pipe++) begin
                    early_producer = u_core.m_record_r[pipe][63:32];
                    if (early_source != 0 && u_core.m_valid_r[pipe] &&
                        writes_rd(early_producer) && early_producer[11:7] == early_source) begin
                        early_condition = 3;
                        if (early_producer[6:0] == 7'h03) early_condition = 4;
                        if (early_producer[6:0] == 7'h73) early_condition = 5;
                        if (early_producer[6:0] == 7'h33 &&
                            early_producer[31:25] == 1 && !early_producer[14])
                            early_condition = 6;
                    end
                end
                for (int pipe = 0; pipe < 2; pipe++) begin
                    early_producer = u_core.e_record_r[pipe][63:32];
                    if (early_source != 0 && u_core.e_valid_r[pipe] &&
                        writes_rd(early_producer) && early_producer[11:7] == early_source)
                        early_condition = early_producer[6:0] == 7'h33 &&
                            early_producer[31:25] == 1 && !early_producer[14] ? 6 : 2;
                end
                early_producer = u_core.d_record_w[0][63:32];
                if (slot == 1 && early_source != 0 && writes_rd(early_producer) &&
                    early_producer[11:7] == early_source)
                    early_condition = 1;
            end
        end
    end
    function automatic bit csr_instruction_write(input logic [31:0] instruction);
        return instruction[6:0] == 7'h73 && instruction[14:12] != 0 &&
            (instruction[13:12] == 1 || instruction[19:15] != 0);
    endfunction
    /* verilator lint_on UNUSEDSIGNAL */
    function automatic bit operand_pending(input logic [4:0] source);
        bit pending;
        logic [31:0] instruction;
        pending = 0;
        for (int lane = 0; lane < 2; lane++) begin
            instruction = u_core.m_record_r[lane][63:32];
            if (source != 0 && u_core.m_valid_r[lane] && writes_rd(instruction) &&
                instruction[11:7] == source)
                pending = instruction[6:0] == 7'h33 && instruction[31:25] == 1 &&
                    !instruction[14];
        end
        for (int lane = 0; lane < 2; lane++) begin
            instruction = u_core.e_record_r[lane][63:32];
            if (source != 0 && u_core.e_valid_r[lane] && writes_rd(instruction) &&
                instruction[11:7] == source)
                pending = (instruction[6:0] == 7'h03 &&
                    !(early_query_previous && early_query_pc ==
                        u_core.e_record_r[lane][31:0]) && candidate1[6:0] != 7'h63) ||
                    instruction[6:0] == 7'h73 ||
                    (instruction[6:0] == 7'h33 && instruction[31:25] == 1 && !instruction[14]);
        end
        return pending;
    endfunction
    function automatic logic [31:0] csr_operation(input logic [31:0] old_value,
                                                    input logic [31:0] operand,
                                                    input logic [1:0] command);
        case (command)
            2: return old_value | operand;
            3: return old_value & ~operand;
            default: return operand;
        endcase
    endfunction
    initial begin
        void'($value$plusargs("TEST_ID=%s", test_id));
        predictor_probe_enabled = $value$plusargs("PREDICTOR_PC=%h", predictor_probe_pc);
        if (predictor_probe_enabled) begin
            if (!$value$plusargs("PREDICTOR_FILE=%s", predictor_path))
                $fatal(1, "FAIL missing PREDICTOR_FILE");
            predictor_descriptor = $fopen(predictor_path, "w");
            if (predictor_descriptor == 0)
                $fatal(1, "FAIL cannot open predictor snapshot %s", predictor_path);
        end
        store_stream_enabled = $value$plusargs("STORES_BEGIN=%h", store_stream_pc);
        has_instret_mailbox = $value$plusargs("EXPECTED_INSTRET=%h", expected_instret_addr);
        has_hpm_mailbox = $value$plusargs("EXPECTED_HPM=%h", expected_hpm_addr);
        if ($value$plusargs("OBLIGATIONS=%s", observer_path)) begin
            observer_file = $fopen(observer_path, "r");
            if (observer_file == 0)
                $fatal(1, "FAIL cannot open obligations %s", observer_path);
            while (!$feof(observer_file)) begin
                observer_status = $fscanf(observer_file, "%d %h %h %d %d\n",
                    obligation_kind[observer_rows], obligation_pc[observer_rows],
                    obligation_other[observer_rows], obligation_arg0[observer_rows],
                    obligation_arg1[observer_rows]);
                if (observer_status != 5)
                    $fatal(1, "FAIL malformed obligation %0d in %s", observer_rows, observer_path);
                obligation_producer_cycle[observer_rows] = -1;
                redirect_start[observer_rows] = -1;
                observer_rows++;
            end
            $fclose(observer_file);
        end
    end
    always @(posedge rst_n) begin
        if (test_id == "c-01") begin
            if (u_core.u_csr.cycle_r != 0 || u_core.u_csr.instret_r != 0)
                $fatal(1, "FAIL architectural counters not zero at reset release");
            for (int index = 0; index < 8; index++) begin
                if (u_core.u_csr.counter_r[index] != 0 || u_core.u_csr.event_r[index] != 0)
                    $fatal(1, "FAIL HPM reset index=%0d", index);
            end
        end
    end
    always @(posedge clk) begin
        if (!rst_n) begin
            for (int code = 0; code <= 16; code++)
                delayed_reference_events[code] = 0;
        end else begin
            if (predictor_probe_enabled && !predictor_probe_seen && u_core.d_issue_w != 0 &&
                u_core.d_record_w[0][31:0] == predictor_probe_pc) begin
                predictor_probe_seen = 1;
                $fdisplay(predictor_descriptor, "probe %h", u_core.d_record_w[0][141:99]);
                $fdisplay(predictor_descriptor, "history %h ras %h %h valid %h",
                    u_core.u_frontend.u_predictor.history_r,
                    u_core.u_frontend.u_predictor.ras_ptr_r,
                    u_core.u_frontend.u_predictor.ras_count_r,
                    u_core.u_frontend.u_predictor.btb_valid_r);
                for (int entry = 0; entry < 128; entry++)
                    $fdisplay(predictor_descriptor, "btb %0d %h", entry,
                        u_core.u_frontend.u_predictor.u_btb.memory_r[entry]);
                for (int entry = 0; entry < 2048; entry++) begin
                    $fdisplay(predictor_descriptor, "direction %0d %h", entry * 2,
                        u_core.u_frontend.u_predictor.u_direction.memory_r[entry][1:0]);
                    $fdisplay(predictor_descriptor, "direction %0d %h", entry * 2 + 1,
                        u_core.u_frontend.u_predictor.u_direction.memory_r[entry][3:2]);
                end
                for (int entry = 0; entry < 256; entry++)
                    $fdisplay(predictor_descriptor, "local_history %0d %h", entry,
                        u_core.u_frontend.u_predictor.u_local_history.memory_r[entry]);
                for (int entry = 0; entry < 1024; entry++)
                    $fdisplay(predictor_descriptor, "local_direction %0d %h", entry,
                        u_core.u_frontend.u_predictor.u_local_direction.memory_r[entry]);
                for (int entry = 0; entry < 4096; entry++)
                    $fdisplay(predictor_descriptor, "chooser %0d %h", entry,
                        u_core.u_frontend.u_predictor.u_chooser.memory_r[entry]);
                $fclose(predictor_descriptor);
            end
            candidate0 = u_core.d_record_w[0][63:32];
            candidate1 = u_core.d_record_w[1][63:32];
            reference_pair_reason = 0;
            if (u_core.d_count_w < 2)
                reference_pair_reason = 4;
            else if (writes_rd(candidate0) && candidate0[11:7] != 0 &&
                ((uses_rs1(candidate1) && candidate1[19:15] == candidate0[11:7]) ||
                    (uses_rs2(candidate1) && candidate1[24:20] == candidate0[11:7])))
                reference_pair_reason = 1;
            else if (candidate0[6:0] == 7'h73 || candidate0[6:0] == 7'h0f ||
                candidate1[6:0] == 7'h73 || candidate1[6:0] == 7'h0f ||
                u_core.d_record_w[1][98:97] != 0 || !legal_instruction(candidate1) ||
                (uses_rs1(candidate1) && operand_pending(candidate1[19:15])) ||
                (uses_rs2(candidate1) && operand_pending(candidate1[24:20])))
                reference_pair_reason = 2;
            else if ((!pipe1_instruction(candidate0) && !pipe1_instruction(candidate1)) ||
                (control_instruction(candidate0) && control_instruction(candidate1)))
                reference_pair_reason = 3;
            if (cold_slot0_redirect)
                reference_pair_reason = 0;
            if (u_core.d_issue_w != 0) begin
                if (u_core.d_issue_w == 2 && reference_pair_reason != 0)
                    $fatal(1, "FAIL pairing forbidden pc=%08x reason=%0d", candidate0,
                        reference_pair_reason);
                if (test_id == "p-01" && reference_pair_reason == 0 &&
                    !cold_slot0_redirect && u_core.d_issue_w != 2)
                    $fatal(1, "FAIL permitted pair not issued together pc=%08x",
                        u_core.d_record_w[0][31:0]);
                if (test_id == "p-01" &&
                    debug[23:21] != 3'(u_core.d_issue_w == 2 ? 0 : reference_pair_reason))
                    $fatal(1, "FAIL pairing reason pc=%08x expected=%0d actual=%0d",
                        u_core.d_record_w[0][31:0], reference_pair_reason, debug[23:21]);
            end
            if (dc_early_valid && (early_condition inside {1, 2, 4, 5, 6} ||
                u_core.d_issue_w == 0))
                $fatal(1, "FAIL ineligible early query condition=%0d issue=%0d cycle=%0d",
                    early_condition, u_core.d_issue_w, cycles);
            // A D redirect may be emitted while its JAL has not issued: all E
            // instructions are then older. E/M redirects have issued age records.
            if (u_core.trace_redirect_stage_w inside {2, 3} && dc_req_valid &&
                u_core.e_valid_r[0] && issued_order[u_core.e_record_r[0][31:0]] >
                issued_order[u_core.trace_redirect_pc_w])
                $fatal(1, "FAIL wrong-path E request pc=%08x redirect=%08x cycle=%0d",
                    u_core.e_record_r[0][31:0], u_core.trace_redirect_pc_w, cycles);
            observer_retire = int'(u_core.trace_valid_w[0]) + int'(u_core.trace_valid_w[1]);
            for (int code = 0; code <= 16; code++)
                reference_events[code] = 0;
            reference_events[1] = int'(observer_retire == 2);
            reference_events[2] = int'(observer_retire == 1);
            reference_events[3] = int'(observer_retire == 0);
            for (int lane = 0; lane < 2; lane++) begin
                observer_instruction = u_core.trace_instr_w[lane*32 +: 32];
                if (u_core.trace_valid_w[lane] && (observer_instruction[6:0] == 7'h63 ||
                    observer_instruction[6:0] == 7'h6f || observer_instruction[6:0] == 7'h67))
                    reference_events[4]++;
            end
            if (u_core.d_issue_w == 1 && !cold_slot0_redirect && reference_pair_reason > 0)
                reference_events[reference_pair_reason + 4] = 1;
            // The documented stall reason also covers early failure repair.
            reference_events[9] = int'(u_core.trace_stall_cause_w == 1);
            reference_events[10] = int'(u_core.e_valid_r[0] &&
                u_core.e_record_r[0][38:32] == 7'h33 && u_core.e_record_r[0][63:57] == 1 &&
                u_core.e_record_r[0][46] && !(u_core.div_done_r || u_core.div_valid_w));
            reference_events[11] = int'(u_core.m_wait_w && dc_resp_device);
            reference_events[12] = int'(u_core.d_count_w == 0 && u_core.d_available_w);
            reference_events[13] = int'(reference_ic_expect && !ic_resp_valid && !ic_kill);
            reference_events[14] = int'(reference_dc_expect && !dc_resp_valid &&
                !dc_resp_device && !dc_kill);
            reference_events[15] = int'(dc_wb_event);
            reference_events[16] = int'(u_core.trace_redirect_stage_w == 1 ||
                u_core.trace_redirect_cause_w != 0);
            reference_ic_expect = ic_req_valid && ic_req_ready;
            reference_dc_expect = dc_req_valid && dc_req_ready;
            if (!reference_inhibit[2] && !(u_core.trace_valid_w[0] &&
                csr_instruction_write(u_core.trace_instr_w[31:0]) &&
                (u_core.trace_instr_w[31:20] == 12'hb02 ||
                    u_core.trace_instr_w[31:20] == 12'hb82)))
                reference_instret += 64'(observer_retire);
            if (test_id == "c-03" && hpm_reference_window) begin
                for (int code = 1; code <= 16; code++)
                    window_events[code] += reference_events[code];
            end
            if (!reference_inhibit[3] && reference_selector >= 1 && reference_selector <= 16) begin
                reference_hpm += 64'(delayed_reference_events[reference_selector]);
                event_witness[reference_selector] += delayed_reference_events[reference_selector];
            end
            // cpu-spec 7.1: select the preceding cycle using the current CSR controls.
            for (int code = 0; code <= 16; code++)
                delayed_reference_events[code] = reference_events[code];
            observer_instruction = u_core.m_instr_r;
            if (u_core.m_commit_w[0] && csr_instruction_write(observer_instruction)) begin
                observer_operand = observer_instruction[14] ?
                    {27'b0, observer_instruction[19:15]} : u_core.m_csr_data_r;
                case (observer_instruction[31:20])
                    12'h320: begin
                        observer_written = csr_operation(reference_inhibit, observer_operand,
                            observer_instruction[13:12]);
                        if (has_instret_mailbox && observer_written[2] && !reference_inhibit[2])
                            write_data(expected_instret_addr, 2, reference_instret[31:0]);
                        if (has_hpm_mailbox && observer_written[3] && !reference_inhibit[3])
                            write_data(expected_hpm_addr + 4*32'(reference_selector), 2,
                                reference_hpm[31:0]);
                        if (test_id == "c-03" && observer_written[3] &&
                            hpm_reference_window) begin
                            if (window_events[13] != 1 || window_events[14] != 1 ||
                                window_events[15] != 3)
                                $fatal(1, "FAIL HPM window=%0d injected events I=%0d D=%0d WB=%0d",
                                    reference_selector, window_events[13], window_events[14],
                                    window_events[15]);
                            hpm_reference_window = 0;
                        end
                        if (test_id == "c-03" && !observer_written[3] && reference_inhibit[3]) begin
                            hpm_reference_window = 1;
                            for (int code = 0; code <= 16; code++)
                                window_events[code] = 0;
                        end
                        reference_inhibit = observer_written;
                    end
                    12'hb02: reference_instret[31:0] = csr_operation(reference_instret[31:0],
                        observer_operand, observer_instruction[13:12]);
                    12'hb82: reference_instret[63:32] = csr_operation(reference_instret[63:32],
                        observer_operand, observer_instruction[13:12]);
                    12'h323: reference_selector = int'(csr_operation(32'(reference_selector),
                        observer_operand, observer_instruction[13:12]) & 31);
                    12'hb03: reference_hpm[31:0] = csr_operation(reference_hpm[31:0],
                        observer_operand, observer_instruction[13:12]);
                    12'hb83: reference_hpm[63:32] = csr_operation(reference_hpm[63:32],
                        observer_operand, observer_instruction[13:12]);
                    default: begin end
                endcase
            end
            if (test_id == "c-05" || test_id == "p-01" ||
                test_id == "b-01" || test_id == "e-01") begin
                expected_debug = 0;
                expected_debug[0] = u_core.f1_valid_w;
                expected_debug[1] = u_core.f2_valid_w;
                expected_debug[4:2] = u_core.ib_count_w;
                expected_debug[5] = u_core.d_count_w != 0;
                expected_debug[6] = u_core.d_count_w >= 2;
                expected_debug[8:7] = u_core.e_valid_r;
                expected_debug[10:9] = u_core.m_valid_r;
                // debug bits describe physical W2 lanes; retirement trace is ordered.
                for (int slot = 0; slot < 2; slot++) begin
                    if (u_core.trace_valid_w[slot])
                        expected_debug[11+issued_pipe[u_core.trace_pc_w[slot*32 +: 32]]] = 1;
                end
                expected_debug[13] = u_core.m_wait_w || u_core.div_wait_w ||
                    (u_core.d_count_w != 0 && u_core.d_issue_w == 0);
                expected_debug[14] = u_core.m_wait_w;
                expected_debug[15] = u_core.fetch_wait_w;
                expected_debug[16] = u_core.trace_redirect_stage_w == 2;
                expected_debug[17] = u_core.trace_redirect_stage_w == 1;
                expected_debug[18] = u_core.m_trap_w;
                expected_debug[20:19] = 2'(observer_retire);
                expected_debug[23:21] = u_core.d_issue_w == 1 ? 3'(reference_pair_reason) : 0;
                expected_debug[24] = 1'(reference_events[9]);
                expected_debug[25] = u_core.div_busy_w;
                expected_debug[26] = u_core.m_wait_w && dc_resp_device;
                expected_debug[27] = u_core.ic_miss_r;
                expected_debug[28] = u_core.dc_miss_r;
                expected_debug[29] = u_core.sleep_r;
                if (observer_retire != 0)
                    expected_debug[63:32] = u_core.trace_valid_w[0] ?
                        u_core.trace_pc_w[31:0] : u_core.trace_pc_w[63:32];
                for (int bit_index = 0; bit_index < 64; bit_index++) begin
                    if ((bit_index < 32 || observer_retire != 0) &&
                        debug[bit_index] != expected_debug[bit_index])
                        $fatal(1, "FAIL debug bit=%0d cycle=%0d expected=%b actual=%b",
                            bit_index, cycles, expected_debug[bit_index], debug[bit_index]);
                end
            end
            if (test_id == "p-01" && cold_slot0_redirect &&
                u_core.d_issue_w != 0 && u_core.d_count_w >= 2) begin
                if (u_core.d_issue_w != 1)
                    $fatal(1, "FAIL cold slot0 JAL issued younger slot cycle=%0d", cycles);
                if (u_core.d_target_w != u_core.d_record_w[1][31:0])
                    cold_jal_flushed[u_core.d_record_w[1][31:0]] = 1;
            end
            for (int pipe = 0; pipe < 2; pipe++) begin
                if (u_core.trace_valid_w[pipe] &&
                    cold_jal_flushed[u_core.trace_pc_w[pipe*32 +: 32]])
                    $fatal(1, "FAIL cold JAL younger instruction retired pc=%08x",
                        u_core.trace_pc_w[pipe*32 +: 32]);
                if (u_core.e_valid_r[pipe] && issued_pipe[u_core.e_record_r[pipe][31:0]] != pipe)
                    $fatal(1, "FAIL pipeline assignment pc=%08x expected=%0d actual=%0d cycle=%0d",
                        u_core.e_record_r[pipe][31:0],
                        issued_pipe[u_core.e_record_r[pipe][31:0]], pipe, cycles);
            end
            for (int slot = 0; slot < int'(u_core.d_issue_w); slot++) begin
                expected_pipe = int'(u_core.d_issue_w == 2 && observed_pair_swap) ^ slot;
                issued_order[u_core.d_record_w[slot][31:0]] = issue_serial;
                issue_serial++;
                issued_slot[u_core.d_record_w[slot][31:0]] = slot;
                issued_pipe[u_core.d_record_w[slot][31:0]] = expected_pipe;
            end
            if (observer_retire == 2)
                dual_retire_count++;
            if (u_core.trace_redirect_stage_w != 0)
                redirect_count++;
            if (debug[26])
                device_wait_cycles++;
            if (u_core.m_trap_w && u_core.e_valid_r[observed_e_pipe] &&
                u_core.d_count_w != 0 &&
                (u_core.e_lane_taken_w[observed_e_pipe] ?
                    u_core.e_lane_target_w[observed_e_pipe] :
                    u_core.e_lane_next_pc_w[observed_e_pipe]) !=
                (u_core.e_record_r[observed_e_pipe][100] ?
                    u_core.e_record_r[observed_e_pipe][132:101] : observed_e_pc + 4) &&
                candidate0[6:0] == 7'h6f && !u_core.d_record_w[0][99])
                max_priority_overlap++;
            if (ic_miss && (observer_retire != 0 || u_core.d_issue_w != 0))
                ic_miss_backend_progress++;
            if (u_dc_model.buffer_hold_r > 0)
                buffer_hold_observed = 1;
            if (store_stream_enabled && dc_req_valid && dc_req_ready && dc_req_store &&
                u_core.e_record_r[0][31:0] >= store_stream_pc &&
                u_core.e_record_r[0][31:0] < store_stream_pc + 16) begin
                if (store_stream_count != 0 && cycles != store_stream_previous + 1)
                    $fatal(1, "FAIL consecutive store throughput gap=%0d pc=%08x",
                        cycles-store_stream_previous, u_core.e_record_r[0][31:0]);
                store_stream_previous = cycles;
                store_stream_count++;
            end
            if (test_id == "m-02" && dc_resp_device && !dc_resp_valid &&
                u_dc_model.committed_r && u_dc_model.store_r) begin
                for (int lane = 0; lane < 2; lane++) begin
                    if (u_core.trace_valid_w[lane] && u_core.trace_pc_w[lane*32 +: 32] >=
                        u_core.m_record_r[0][31:0])
                        $fatal(1, "FAIL younger retirement before device write response");
                end
            end
            if (test_id == "m-03" && u_core.m_commit_w[0] &&
                u_core.m_instr_r[6:0] == 7'h0f && write_buffer_valid)
                $fatal(1, "FAIL FENCE committed with nonempty write buffer");
            if (test_id == "m-04") begin
                if (dc_clean_all && clean_begin_cycle < 0 && !write_buffer_valid &&
                    !u_dc_model.active_r)
                    clean_begin_cycle = cycles;
                if (dc_clean_all && dc_fence_done) begin
                    if (cycles-clean_begin_cycle != u_dc_model.clean_delay)
                        $fatal(1, "FAIL configured clean delay expected=%0d actual=%0d",
                            u_dc_model.clean_delay, cycles-clean_begin_cycle);
                    clean_observed = 1;
                end
                if (ic_inv) begin
                    if (invalidate_begin_cycle < 0)
                        invalidate_begin_cycle = cycles;
                    if (ic_inv_done && cycles-invalidate_begin_cycle != u_ic_model.inv_delay)
                        $fatal(1, "FAIL configured invalidation delay expected=%0d actual=%0d",
                            u_ic_model.inv_delay, cycles-invalidate_begin_cycle);
                    if (!clean_observed)
                        $fatal(1, "FAIL I invalidation before D clean completion");
                    if (ic_inv_done)
                        invalidate_observed = 1;
                end
                if (u_core.m_commit_w[0] && u_core.m_instr_r == 32'h0000100f &&
                    !(clean_observed && invalidate_observed))
                    $fatal(1, "FAIL FENCE.I committed before both maintenance completions");
                if (dc_clean_all && u_core.m_interrupt_w)
                    $fatal(1, "FAIL interrupt accepted during FENCE.I clean");
            end
            // A CSR is serialized against E and M before its D -> E transition.
            if (u_core.d_issue_w != 0 && candidate0[6:0] == 7'h73 && candidate0[14:12] != 0) begin
                csr_issue_count++;
                if (u_core.d_issue_w != 1 || u_core.e_valid_r != 0 || u_core.m_valid_r != 0)
                    $fatal(1, "FAIL CSR not serialized pc=%08x", u_core.d_record_w[0][31:0]);
            end
            if (test_id == "p-05" && observer_div_previous && u_core.div_busy_w) begin
                if (observer_pipeline_valid != {u_core.e_valid_r,u_core.m_valid_r,u_core.w_valid_r}
                    || observer_e_records != {u_core.e_record_r[1],u_core.e_record_r[0]}
                    || observer_m_records != {u_core.m_record_r[1],u_core.m_record_r[0]}
                    || observer_w_records != {u_core.w_record_r[1],u_core.w_record_r[0]})
                    $fatal(1, "FAIL divider changed frozen pipeline cycle=%0d", cycles);
            end
            observer_div_previous = u_core.div_busy_w;
            observer_pipeline_valid = {u_core.e_valid_r,u_core.m_valid_r,u_core.w_valid_r};
            observer_e_records = {u_core.e_record_r[1],u_core.e_record_r[0]};
            observer_m_records = {u_core.m_record_r[1],u_core.m_record_r[0]};
            observer_w_records = {u_core.w_record_r[1],u_core.w_record_r[0]};
            for (int row = 0; row < observer_rows; row++) begin
                if (obligation_kind[row] == 4 && u_core.d_issue_w != 0 &&
                    u_core.d_record_w[0][31:0] == obligation_pc[row] &&
                    u_core.d_count_w >= 2 &&
                    u_core.d_record_w[1][31:0] == obligation_other[row]) begin
                    if (int'(u_core.d_issue_w == 2) != obligation_arg0[row])
                        $fatal(1, "FAIL pair pc=%08x expected dual=%0d actual=%0d cycle=%0d",
                            obligation_pc[row], obligation_arg0[row], u_core.d_issue_w, cycles);
                    if (obligation_arg0[row] == 1 &&
                        int'(observed_pair_swap) != obligation_arg1[row])
                        $fatal(1, "FAIL swap pc=%08x expected=%0d actual=%b",
                            obligation_pc[row], obligation_arg1[row], observed_pair_swap);
                    if (obligation_arg0[row] == 0 &&
                        debug[23:21] != (cold_slot0_redirect ? 0 : 3))
                        $fatal(1, "FAIL double control pc=%08x reason=%0d expected=%0d",
                            obligation_pc[row], debug[23:21], cold_slot0_redirect ? 0 : 3);
                    obligation_seen[row]++;
                end
                if (obligation_kind[row] inside {5, 6} &&
                    u_core.trace_redirect_pc_w == obligation_pc[row] &&
                    int'(u_core.trace_redirect_stage_w) ==
                    (obligation_kind[row] == 5 ? 2 : 1)) begin
                    if (int'(u_core.trace_redirect_cause_w) == obligation_arg1[row] ||
                        obligation_kind[row] == 6)
                        obligation_redirect_seen[row] = 1;
                end
                // Measure from the labelled instruction's D -> E transition, not
                // from current E/D records: the redirect now comes from a register.
                if (obligation_kind[row] inside {5, 6}) begin
                    for (int slot = 0; slot < 2; slot++) begin
                        if (int'(u_core.d_issue_w) > slot &&
                            u_core.d_record_w[slot][31:0] == obligation_pc[row]) begin
                            redirect_start[row] = cycles;
                            obligation_redirect_seen[row] = 0;
                            if (slot != obligation_arg0[row])
                                $fatal(1, "FAIL redirect slot pc=%08x expected=%0d actual=%0d",
                                    obligation_pc[row], obligation_arg0[row], slot);
                        end
                    end
                    if (redirect_start[row] >= 0 && u_core.d_issue_w != 0 &&
                        u_core.d_record_w[0][31:0] == obligation_other[row]) begin
                        if (!obligation_redirect_seen[row])
                            $fatal(1, "FAIL missing registered redirect pc=%08x stage-kind=%0d",
                                obligation_pc[row], obligation_kind[row]);
                        // Penalty excludes the clock in which the source issues.
                        expected_pipe = obligation_kind[row] == 5 ? 4 : 3;
                        if (cycles-redirect_start[row]-1 != expected_pipe)
                            $fatal(1,
                                "FAIL redirect penalty pc=%08x expected=%0d actual=%0d cycle=%0d",
                                obligation_pc[row], expected_pipe,
                                cycles-redirect_start[row]-1, cycles);
                        obligation_seen[row]++;
                        redirect_start[row] = -1;
                        obligation_redirect_seen[row] = 0;
                    end
                end
                if (obligation_kind[row] == 7 && u_core.m_trap_w &&
                    u_core.m_trap_cause_w == 32'(obligation_arg1[row]) &&
                    ((u_core.m_valid_r[0] && u_core.m_record_r[0][31:0] == obligation_pc[row]) ||
                        (u_core.m_valid_r[1] &&
                        u_core.m_record_r[1][31:0] == obligation_pc[row]))) begin
                    if (int'(observed_trap_slot) != obligation_arg0[row])
                        $fatal(1, "FAIL trap slot expected=%0d actual=%b cause=%0d",
                            obligation_arg0[row], observed_trap_slot, obligation_arg1[row]);
                    obligation_seen[row]++;
                end
                if (obligation_kind[row] == 8) begin
                    if (dc_req_valid && u_core.e_valid_r[0] &&
                        u_core.e_record_r[0][31:0] == obligation_pc[row])
                        $fatal(1, "FAIL flushed load reached D$ pc=%08x", obligation_pc[row]);
                    obligation_seen[row]++;
                end
                if (obligation_kind[row] == 10 || obligation_kind[row] == 12) begin
                    for (int slot = 0; slot < 2; slot++) begin
                        if (u_core.trace_valid_w[slot] &&
                            u_core.trace_pc_w[slot*32 +: 32] == obligation_pc[row])
                            $fatal(1, "FAIL flushed instruction retired pc=%08x cycle=%0d",
                                obligation_pc[row], cycles);
                    end
                    if (obligation_kind[row] == 12 && dc_commit &&
                        u_core.m_record_r[0][31:0] == obligation_pc[row])
                        $fatal(1, "FAIL flushed D$ access committed pc=%08x cycle=%0d",
                            obligation_pc[row], cycles);
                    obligation_seen[row]++;
                end
                if (obligation_kind[row] == 16 && early_query_previous &&
                    early_query_pc == obligation_pc[row])
                    obligation_seen[row]++;
                if (obligation_kind[row] == 17 && early_query_previous &&
                    early_query_pc == obligation_pc[row]) begin
                    if (dc_early_hit || int'(u_dc_model.early_failure_r) != obligation_arg0[row])
                        $fatal(1, "FAIL early fallback pc=%08x expected=%0d actual=%0d hit=%b",
                            obligation_pc[row], obligation_arg0[row],
                            u_dc_model.early_failure_r, dc_early_hit);
                    obligation_seen[row]++;
                end
                if (obligation_kind[row] == 14) begin
                    for (int m_pipe = 0; m_pipe < 2; m_pipe++) begin
                        for (int e_pipe = 0; e_pipe < 2; e_pipe++) begin
                            if (u_core.m_valid_r[m_pipe] && u_core.e_valid_r[e_pipe] &&
                                u_core.m_record_r[m_pipe][31:0] == obligation_pc[row] &&
                                u_core.e_record_r[e_pipe][31:0] == obligation_other[row])
                                obligation_seen[row]++;
                        end
                    end
                end
                if (obligation_kind[row] == 13 && early_condition ==
                    4'(obligation_arg0[row])) begin
                    for (int slot = 0; slot < 2; slot++) begin
                        if (int'(u_core.d_count_w) > slot &&
                            u_core.d_record_w[slot][31:0] == obligation_pc[row])
                            obligation_seen[row]++;
                    end
                end
                if (obligation_kind[row] == 9 && u_core.trace_valid_w == 3 &&
                    u_core.trace_pc_w[31:0] == obligation_pc[row] &&
                    u_core.trace_pc_w[63:32] == obligation_other[row])
                    obligation_seen[row]++;
                if (u_core.d_issue_w != 0 && u_core.d_record_w[0][31:0] == obligation_other[row])
                    obligation_producer_cycle[row] = cycles;
                if (u_core.d_issue_w == 2 && u_core.d_record_w[1][31:0] == obligation_other[row])
                    obligation_producer_cycle[row] = cycles;
                for (int lane = 0; lane < 2; lane++) begin
                    if (int'(u_core.d_issue_w) > lane && u_core.d_record_w[lane][31:0] ==
                        obligation_pc[row]) begin
                        if (obligation_kind[row] == 1)
                            $display("BYPASS row=%0d pc=%08x lane=%0d source=%0d required=%0d/%0d",
                                row, obligation_pc[row], lane,
                                u_core.trace_bypass_w[obligation_arg0[row]*3 +: 3],
                                obligation_arg0[row]/2, obligation_arg1[row]);
                        if (obligation_kind[row] == 1 &&
                            lane == obligation_arg0[row] / 2 &&
                            int'(u_core.trace_bypass_w[obligation_arg0[row]*3 +: 3]) ==
                            obligation_arg1[row])
                            obligation_seen[row]++;
                        if (obligation_kind[row] == 2) begin
                            if (obligation_producer_cycle[row] < 0 ||
                                cycles - obligation_producer_cycle[row] < obligation_arg0[row])
                                $fatal(1, "FAIL result latency pc=%08x expected=%0d actual=%0d cycle=%0d",
                                    obligation_pc[row], obligation_arg0[row],
                                    cycles-obligation_producer_cycle[row], cycles);
                            if (obligation_arg1[row] == 0 &&
                                cycles-obligation_producer_cycle[row] != obligation_arg0[row])
                                $fatal(1, "FAIL consumer latency pc=%08x expected=%0d actual=%0d cycle=%0d",
                                    obligation_pc[row], obligation_arg0[row],
                                    cycles-obligation_producer_cycle[row], cycles);
                            obligation_seen[row]++;
                        end
                        if (obligation_kind[row] == 3 && lane == 0 &&
                            u_core.d_count_w >= 2 &&
                            u_core.d_record_w[1][31:0] == obligation_other[row])
                            obligation_seen[row]++;
                    end
                end
            end
        end
    end
    task automatic check_directed_completion;
        if (test_id == "b-12") begin
            if (tournament_corrections == 0 || tournament_agreements == 0 ||
                tournament_local_wins == 0)
                $fatal(1, "FAIL B-12 coverage corrections=%0d agreements=%0d local_wins=%0d",
                    tournament_corrections, tournament_agreements, tournament_local_wins);
            $display("PASS B-12 corrections=%0d agreements=%0d local_wins=%0d",
                tournament_corrections, tournament_agreements, tournament_local_wins);
        end
        if (predictor_probe_enabled && !predictor_probe_seen)
            $fatal(1, "FAIL predictor probe not reached pc=%08x", predictor_probe_pc);
        for (int row = 0; row < observer_rows; row++) begin
            if (obligation_seen[row] == 0)
                $fatal(1, "FAIL directed obligation row=%0d kind=%0d pc=%08x arg=%0d/%0d",
                    row, obligation_kind[row], obligation_pc[row], obligation_arg0[row],
                    obligation_arg1[row]);
        end
        for (int index = 0; index < irq_count; index++) begin
            if (!irq_fired[index])
                $fatal(1, "FAIL IRQ window %0d not exercised pc=%08x", index, irq_pc[index]);
        end
        if (store_stream_enabled && store_stream_count != 4)
            $fatal(1, "FAIL continuous store witness count=%0d", store_stream_count);
        if (test_id == "m-01" && device_accesses != 0)
            $fatal(1, "FAIL wrong-path device accesses=%0d", device_accesses);
        if (test_id == "m-03" && !buffer_hold_observed)
            $fatal(1, "FAIL M-03 did not exercise held write buffer");
        if (test_id == "p-07" && ic_miss_backend_progress == 0)
            $fatal(1, "FAIL no backend progress during I miss");
        if (test_id == "b-05" && max_priority_overlap == 0)
            $fatal(1, "FAIL missing concurrent M/E/D redirect contenders");
        if ((test_id == "p-01" || test_id == "p-02" || test_id == "c-02") &&
            dual_retire_count == 0)
            $fatal(1, "FAIL no dual retirement in %s", test_id);
        if (test_id == "c-03") begin
            for (int code = 1; code <= 16; code++) begin
                if (event_witness[code] == 0)
                    $fatal(1, "FAIL HPM event %0d not exercised in its window", code);
            end
        end
        if ((test_id == "m-02" || test_id == "e-08") && device_wait_cycles < 20)
            $fatal(1, "FAIL missing delayed device response: cycles=%0d", device_wait_cycles);
    endtask
