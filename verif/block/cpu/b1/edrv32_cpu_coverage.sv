// File: edrv32_cpu_coverage.sv
// Spec: cpu-spec 3.4, 7.1-7.2; cpu-testplan 4 (C-V5)
// Description: Count functional coverage using only documented debug, trace
//              and interrupt stimulus signals; emit JSON at finish.
// Clock: clk_sys.
module edrv32_cpu_coverage (
    // Clock and reset.
    input logic clk_i,
    input logic rst_n_i,

    // Retirement and public debug interface.
    input logic [63:0] debug_i,
    input logic [63:0] irq_arrival_debug_i,
    input logic [1:0] trace_valid_i,
    input logic [63:0] trace_instr_i,
    input logic trace_trap_i,
    input logic [31:0] trace_cause_i,
    input logic [11:0] trace_bypass_i,
    input logic [1:0] trace_redirect_cause_i,
    input logic [2:0] trace_stall_cause_i,

    // Environment observations of logical age and physical assignment (spec 4.2).
    input logic pair_valid_i,
    input logic pair_swap_i,
    input logic trap_slot_i,
    input logic e_redirect_slot_i,
    input logic d_redirect_slot_i,

    // Interrupt stimulus.
    input logic irq_meip_i,
    input logic irq_msip_i,
    input logic irq_mtip_i
);
    longint unsigned counts[string];
    string sources[6] = '{"e0", "e1", "m0", "m1", "w0", "w1"};
    int causes[9] = '{0, 1, 2, 3, 4, 5, 6, 7, 11};
    string path = "build/cpu-coverage.json";
    integer descriptor;
    bit first;
    logic [2:0] irq_previous_r;
    wire [2:0] irq_w = {irq_mtip_i, irq_msip_i, irq_meip_i};

    initial begin
        void'($value$plusargs("COVERAGE_FILE=%s", path));
        counts["pair.dual"] = 0;
        counts["pair.normal"] = 0;
        counts["pair.swap"] = 0;
        counts["pair.raw"] = 0;
        counts["pair.structure"] = 0;
        counts["pair.slot1_type"] = 0;
        counts["pair.ib_single"] = 0;
        for (int source_idx = 0; source_idx < 6; source_idx++) begin
            for (int operand = 0; operand < 2; operand++) begin
                for (int slot = 0; slot < 2; slot++)
                    counts[$sformatf("bypass.%s.rs%0d.slot%0d", sources[source_idx],
                        operand + 1, slot)] = 0;
            end
        end
        for (int cause = 0; cause <= 7; cause++) begin
            if (cause == 0 || cause >= 4)
                counts[$sformatf("exception.%0d.slot1", cause)] = 0;
        end
        for (int slot = 0; slot < 2; slot++) begin
            counts[$sformatf("redirect.e_direction.slot%0d", slot)] = 0;
            counts[$sformatf("redirect.e_target.slot%0d", slot)] = 0;
            counts[$sformatf("redirect.d.slot%0d", slot)] = 0;
        end
        foreach (causes[index])
            counts[$sformatf("exception.%0d.slot0", causes[index])] = 0;
        counts["redirect.e_direction"] = 0;
        counts["redirect.e_target"] = 0;
        counts["redirect.d"] = 0;
        counts["redirect.exception"] = 0;
        counts["redirect.interrupt"] = 0;
        counts["redirect.mret"] = 0;
        counts["redirect.fence_i"] = 0;
        counts["stall.load_use"] = 0;
        counts["stall.multiply"] = 0;
        counts["stall.divide"] = 0;
        counts["stall.csr"] = 0;
        counts["stall.ic_miss"] = 0;
        counts["stall.dc_miss"] = 0;
        counts["stall.device"] = 0;
        counts["irq.normal"] = 0;
        counts["irq.divide"] = 0;
        counts["irq.device"] = 0;
        counts["irq.dc_miss"] = 0;
        counts["irq.branch_flush"] = 0;
    end

    initial forever begin
        @(posedge clk_i);
        if (!rst_n_i) begin
            irq_previous_r = 0;
        end else begin
            // A dual retirement witnesses a successfully issued pair. Failure
            // reasons are already qualified by D issue (spec 7.1 priority 5>6>7>8).
            if (trace_valid_i == 2'b11)
                counts["pair.dual"] += 1;
            if (pair_valid_i)
                counts[pair_swap_i ? "pair.swap" : "pair.normal"] += 1;
            case (debug_i[23:21])
                1: counts["pair.raw"] += 1;
                2: counts["pair.structure"] += 1;
                3: counts["pair.slot1_type"] += 1;
                4: counts["pair.ib_single"] += 1;
                default: begin end
            endcase
            for (int source_idx = 0; source_idx < 6; source_idx++) begin
                for (int operand = 0; operand < 2; operand++) begin
                    for (int slot = 0; slot < 2; slot++) begin
                        if (trace_bypass_i[(slot*2 + operand)*3 +: 3] == 3'(source_idx + 1))
                            counts[$sformatf("bypass.%s.rs%0d.slot%0d", sources[source_idx],
                                operand + 1, slot)] += 1;
                    end
                end
            end
            if (trace_trap_i) begin
                if (trace_cause_i[31]) begin
                    counts["redirect.interrupt"] += 1;
                end else begin
                    counts["redirect.exception"] += 1;
                    foreach (causes[index]) begin
                        if (trace_cause_i == 32'(causes[index]))
                            counts[$sformatf("exception.%0d.slot%0d",
                                causes[index], trap_slot_i)] += 1;
                    end
                end
            end
            if (debug_i[17]) begin
                counts["redirect.d"] += 1;
                counts[$sformatf("redirect.d.slot%0d", d_redirect_slot_i)] += 1;
            end
            if (trace_redirect_cause_i == 1) begin
                counts["redirect.e_direction"] += 1;
                counts[$sformatf("redirect.e_direction.slot%0d", e_redirect_slot_i)] += 1;
            end
            if (trace_redirect_cause_i == 2) begin
                counts["redirect.e_target"] += 1;
                counts[$sformatf("redirect.e_target.slot%0d", e_redirect_slot_i)] += 1;
            end
            for (int slot = 0; slot < 2; slot++) begin
                if (trace_valid_i[slot]) begin
                    if (trace_instr_i[slot*32 +: 32] == 32'h30200073)
                        counts["redirect.mret"] += 1;
                    if ((trace_instr_i[slot*32 +: 32] & 32'h0000707f) == 32'h0000100f)
                        counts["redirect.fence_i"] += 1;
                end
            end
            if (debug_i[24])
                counts["stall.load_use"] += 1;
            if (trace_stall_cause_i == 2)
                counts["stall.multiply"] += 1;
            if (trace_stall_cause_i == 3 || trace_stall_cause_i == 4)
                counts["stall.csr"] += 1;
            if (debug_i[25])
                counts["stall.divide"] += 1;
            if (debug_i[15])
                counts["stall.ic_miss"] += 1;
            if (debug_i[14] && debug_i[28])
                counts["stall.dc_miss"] += 1;
            if (debug_i[26])
                counts["stall.device"] += 1;
            // Each input rising edge is an arrival; overlapping timing classes
            // are counted independently. Held-high requests are not new arrivals.
            for (int irq = 0; irq < 3; irq++) begin
                if (irq_w[irq] && !irq_previous_r[irq]) begin
                    if (irq_arrival_debug_i[25])
                        counts["irq.divide"] += 1;
                    if (irq_arrival_debug_i[26])
                        counts["irq.device"] += 1;
                    if (irq_arrival_debug_i[28])
                        counts["irq.dc_miss"] += 1;
                    if (irq_arrival_debug_i[16] || irq_arrival_debug_i[17])
                        counts["irq.branch_flush"] += 1;
                    if (!(irq_arrival_debug_i[25] || irq_arrival_debug_i[26] || irq_arrival_debug_i[28]
                        || irq_arrival_debug_i[16] || irq_arrival_debug_i[17] || irq_arrival_debug_i[18] || irq_arrival_debug_i[29])
                        && ((|irq_arrival_debug_i[12:5]) || (|trace_valid_i)))
                        counts["irq.normal"] += 1;
                end
            end
            irq_previous_r = irq_w;
        end
    end

    wire unused_w = &{1'b0, debug_i, irq_arrival_debug_i};

    final begin
        descriptor = $fopen(path, "w");
        if (descriptor == 0)
            $fatal(1, "FAIL cannot open coverage file %s", path);
        $fdisplay(descriptor, "{\"counts\": {");
        first = 1;
        foreach (counts[key]) begin
            if (!first)
                $fwrite(descriptor, ",\n");
            $fwrite(descriptor, "  \"%s\": %0d", key, counts[key]);
            first = 0;
        end
        $fdisplay(descriptor, "\n}}");
        $fclose(descriptor);
    end
endmodule
