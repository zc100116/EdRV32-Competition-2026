// File: edrv32_cpu2_trace_check.sv
// Spec: cpu-v2-spec 3.11, testplan 2/4; fpu-spec 4/5.5.
// Description: Compare ordered architectural events and independent observation events.
// Clock: clk_i (retirement edge, before registered WB updates).
module edrv32_cpu2_trace_check #(
    parameter ISSUE_WIDTH = 2,
    parameter string FPU_FORMAT = "FD",
    localparam T = FPU_FORMAT == "NONE" ? 2 : (FPU_FORMAT == "F" ? 3 : 4)
) (
    // Clock, reset and caller-controlled end of test.
    input wire clk_i,
    input wire rst_n_i,
    input wire finish_i,

    // Architectural retirements, oldest slot in the low field.
    input wire [ISSUE_WIDTH-1:0] trace_valid_i,
    input wire [32*ISSUE_WIDTH-1:0] trace_pc_i,
    input wire [32*ISSUE_WIDTH-1:0] trace_instr_i,
    input wire [5*ISSUE_WIDTH-1:0] trace_rd_i,
    input wire [2*ISSUE_WIDTH-1:0] trace_rd_domain_i,
    input wire [64*ISSUE_WIDTH-1:0] trace_rd_data_i,
    input wire [5*ISSUE_WIDTH-1:0] trace_flags_i,
    input wire [1*ISSUE_WIDTH-1:0] trace_csr_valid_i,
    input wire [12*ISSUE_WIDTH-1:0] trace_csr_addr_i,
    input wire [32*ISSUE_WIDTH-1:0] trace_csr_data_i,
    input wire [1*ISSUE_WIDTH-1:0] trace_mem_valid_i,
    input wire [1*ISSUE_WIDTH-1:0] trace_mem_store_i,
    input wire [32*ISSUE_WIDTH-1:0] trace_mem_addr_i,
    input wire [64*ISSUE_WIDTH-1:0] trace_mem_data_i,
    input wire [8*ISSUE_WIDTH-1:0] trace_mem_mask_i,

    // Final architectural FP state after this edge.
    input wire [5-1:0] trace_fflags_i,
    input wire [3-1:0] trace_frm_i,
    input wire [2-1:0] trace_fs_i,

    // A faulting item is a trap event, never an extra retirement.
    input wire trace_trap_i,
    input wire [32-1:0] trace_cause_i,
    input wire [32-1:0] trace_trap_pc_i,
    input wire [32-1:0] trace_tval_i,

    // Actual authorized store effects.
    input wire trace_mem_effect_valid_i,
    input wire [T-1:0] trace_mem_effect_tag_i,
    input wire [32-1:0] trace_mem_effect_addr_i,
    input wire [32-1:0] trace_mem_effect_data_i,
    input wire [4-1:0] trace_mem_effect_mask_i,

    // Redirect and source observations retain the frozen physical interface.
    input wire trace_redirect_valid_i,
    input wire [T-1:0] trace_redirect_tag_i,
    input wire [32-1:0] trace_redirect_pc_i,
    input wire [32-1:0] trace_redirect_target_i,
    input wire [2-1:0] trace_redirect_stage_i,
    input wire [2-1:0] trace_redirect_cause_i,
    input wire trace_source0_valid_i,
    input wire [T-1:0] trace_source0_tag_i,
    input wire trace_source0_domain_i,
    input wire trace_source1_valid_i,
    input wire [T-1:0] trace_source1_tag_i,
    input wire trace_source1_domain_i,
    input wire trace_source2_valid_i,
    input wire [T-1:0] trace_source2_tag_i,
    input wire trace_source2_domain_i,
    input wire trace_source3_valid_i,
    input wire [T-1:0] trace_source3_tag_i,
    input wire trace_source3_domain_i,
    input wire trace_source4_valid_i,
    input wire [T-1:0] trace_source4_tag_i,
    input wire trace_source4_domain_i,

    // Independent normalized AXI memory-effect observations.
    input wire bfm_valid_i,
    input wire [32-1:0] bfm_addr_i,
    input wire [32-1:0] bfm_data_i,
    input wire [4-1:0] bfm_mask_i
);
    logic [4:0] check_fflags;
    logic [2:0] check_frm;
    logic [1:0] check_fs;
    logic [31:0] expected_next_pc;
    logic [6:0] retired_opcode;
    logic [31:0] retired_pc;
    localparam S = FPU_FORMAT == "NONE" ? 2*ISSUE_WIDTH :
                    (FPU_FORMAT == "F" ? (ISSUE_WIDTH == 1 ? 3 : 5) : 2*ISSUE_WIDTH);
    localparam R = FPU_FORMAT == "F" ? 3 : 2;
    integer arch_fd;
    integer count;
    integer cycle_r;
    integer retire_r;
    integer kind;
    string path;
    logic have_arch;
    logic [32-1:0] expected_pc;
    logic [32-1:0] expected_instr;
    logic [5-1:0] expected_rd;
    logic [2-1:0] expected_rd_domain;
    logic [64-1:0] expected_rd_data;
    logic expected_csr_valid;
    logic [12-1:0] expected_csr_addr;
    logic [32-1:0] expected_csr_data;
    logic expected_mem_valid;
    logic expected_mem_store;
    logic [32-1:0] expected_mem_addr;
    logic [64-1:0] expected_mem_data;
    logic [8-1:0] expected_mem_mask;
    logic [5-1:0] expected_fflags;
    logic [3-1:0] expected_frm;
    logic [2-1:0] expected_fs;
    logic [32-1:0] expected_cause;
    logic [32-1:0] expected_trap_pc;
    logic [32-1:0] expected_tval;
    typedef struct packed {
        logic [31:0] addr;
        logic [31:0] data;
        logic [3:0] mask;
    } store_beat;
    store_beat cache_expected[$];
    store_beat cache_actual[$];
    store_beat trace_beats[$];
    store_beat bfm_beats[$];
    store_beat trace_beat;
    store_beat bfm_beat;

    // SoC 6.1 PMA: SRAM 64KiB and DDR 1GiB are the two cacheable regions.
    function automatic logic cacheable(input logic [31:0] addr);
        cacheable = (addr >= 32'h10000000 && addr < 32'h10010000) ||
                    (addr >= 32'h80000000 && addr < 32'hc0000000);
    endfunction

    task automatic compare(input string field, input logic [63:0] expected_value,
                            input logic [63:0] actual_value);
        if (actual_value !== expected_value) begin
            $display("FAIL field=%s expected=%h actual=%h retire=%0d time=%0t",
                        field, expected_value, actual_value, retire_r, $time);
            $fatal(1, "trace mismatch");
        end
    endtask

    task automatic read_arch;
        count = $fscanf(arch_fd, "%h", kind);
        have_arch = count == 1;
        if (count != 1 && count != -1) $fatal(1, "FAIL malformed event kind");
        if (have_arch) begin
            if (kind == 1) begin
                count = $fscanf(arch_fd,
                    "%h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h",
                    expected_pc,
                    expected_instr,
                    expected_rd,
                    expected_rd_domain,
                    expected_rd_data,
                    expected_csr_valid,
                    expected_csr_addr,
                    expected_csr_data,
                    expected_mem_valid,
                    expected_mem_store,
                    expected_mem_addr,
                    expected_mem_data,
                    expected_mem_mask,
                    expected_fflags,
                    expected_frm,
                    expected_fs,
                    expected_next_pc);
                if (count != 17) $fatal(1, "FAIL malformed retirement record");
            end else if (kind == 2) begin
                count = $fscanf(arch_fd, "%h %h %h %h %h %h",
                    expected_cause,
                    expected_trap_pc,
                    expected_tval,
                    expected_fflags,
                    expected_frm,
                    expected_fs);
                if (count != 6) $fatal(1, "FAIL malformed trap record");
            end else $fatal(1, "FAIL unknown architectural event %0d", kind);
        end
    endtask

    initial begin
        if (!$value$plusargs("TRACE_EXPECT=%s", path)) $fatal(1, "FAIL missing TRACE_EXPECT");
        arch_fd = $fopen(path, "r");
        if (arch_fd == 0) $fatal(1, "FAIL cannot open %s", path);
        read_arch();
    end

    // trace fields describe the retirement edge, not the following registered WB edge.
    initial begin
        check_fflags = 0;
        check_frm = 0;
        check_fs = 0;
        cycle_r = 0;
        retire_r = 0;
        forever begin
            @(posedge clk_i);
            if (rst_n_i) begin
                if (ISSUE_WIDTH == 2)
                    compare("valid_age_order", 1, 64'(trace_valid_i != ISSUE_WIDTH'(2)));
                for (integer slot = 0; slot < ISSUE_WIDTH; slot = slot + 1) begin
                    if (trace_valid_i[slot]) begin
                        compare("retire_present", 1, 64'(have_arch));
                        compare("event_kind", 1, 64'(kind));
                        compare("pc", 64'(expected_pc),
                                64'(trace_pc_i[slot*32 +: 32]));
                        compare("instr", 64'(expected_instr),
                                64'(trace_instr_i[slot*32 +: 32]));
                        if (expected_rd_domain != 0)
                            compare("rd", 64'(expected_rd),
                                64'(trace_rd_i[slot*5 +: 5]));
                        compare("rd_domain", 64'(expected_rd_domain),
                                64'(trace_rd_domain_i[slot*2 +: 2]));
                        if (expected_rd_domain != 0)
                            compare("rd_data", 64'(expected_rd_data),
                                64'(trace_rd_data_i[slot*64 +: 64]));
                        compare("csr_valid", 64'(expected_csr_valid),
                                64'(trace_csr_valid_i[slot*1 +: 1]));
                        if (expected_csr_valid)
                            compare("csr_addr", 64'(expected_csr_addr),
                                64'(trace_csr_addr_i[slot*12 +: 12]));
                        if (expected_csr_valid)
                            compare("csr_data", 64'(expected_csr_data),
                                64'(trace_csr_data_i[slot*32 +: 32]));
                        compare("mem_valid", 64'(expected_mem_valid),
                                64'(trace_mem_valid_i[slot*1 +: 1]));
                        if (expected_mem_valid)
                            compare("mem_store", 64'(expected_mem_store),
                                64'(trace_mem_store_i[slot*1 +: 1]));
                        if (expected_mem_valid)
                            compare("mem_addr", 64'(expected_mem_addr),
                                64'(trace_mem_addr_i[slot*32 +: 32]));
                        if (expected_mem_valid)
                            compare("mem_data", 64'(expected_mem_data),
                                64'(trace_mem_data_i[slot*64 +: 64]));
                        if (expected_mem_valid)
                            compare("mem_mask", 64'(expected_mem_mask),
                                64'(trace_mem_mask_i[slot*8 +: 8]));
                        retired_opcode = trace_instr_i[slot*32 +: 7];
                        retired_pc = trace_pc_i[slot*32 +: 32];
                        if ((retired_opcode == 7'h63 || retired_opcode == 7'h67 ||
                                retired_opcode == 7'h6f) && trace_redirect_valid_i &&
                            trace_redirect_stage_i != 1 && trace_redirect_pc_i == retired_pc)
                            compare("redirect_target", 64'(expected_next_pc),
                                    64'(trace_redirect_target_i));
                        if (FPU_FORMAT == "NONE")
                            compare("flags_none", 0, 64'(trace_flags_i[slot*5 +: 5]));
                        if (expected_mem_valid && expected_mem_store &&
                            cacheable(expected_mem_addr)) begin
                            bfm_beat = '{expected_mem_addr, expected_mem_data[31:0],
                                            expected_mem_mask[3:0]};
                            cache_expected.push_back(bfm_beat);
                            if (expected_mem_mask == 8'hff) begin
                                bfm_beat = '{expected_mem_addr + 32'd4,
                                                expected_mem_data[63:32], 4'hf};
                                cache_expected.push_back(bfm_beat);
                            end
                        end
                        retire_r = retire_r + 1;
                        // Preserve post-event state through read_arch of the next record.
                        check_fflags = expected_fflags;
                        check_frm = expected_frm;
                        check_fs = expected_fs;
                        read_arch();
                    end
                end
                if (trace_trap_i) begin
                    compare("trap_present", 1, 64'(have_arch));
                    compare("event_kind", 2, 64'(kind));
                    compare("cause", 64'(expected_cause), 64'(trace_cause_i));
                    compare("trap_pc", 64'(expected_trap_pc), 64'(trace_trap_pc_i));
                    compare("tval", 64'(expected_tval), 64'(trace_tval_i));
                    check_fflags = expected_fflags;
                    check_frm = expected_frm;
                    check_fs = expected_fs;
                    read_arch();
                end
                if ((|trace_valid_i) || trace_trap_i) begin
                    compare("fflags", 64'(check_fflags), 64'(trace_fflags_i));
                    compare("frm", 64'(check_frm), 64'(trace_frm_i));
                    compare("fs", 64'(check_fs), 64'(trace_fs_i));
                end
                // Implementation observations are checked only against frozen local contracts.
                if (trace_redirect_valid_i) begin
                    if (trace_redirect_stage_i == 1) begin
                        compare("redirect_tag", 0, 64'(trace_redirect_tag_i));
                        compare("redirect_cause", 1,
                                64'(trace_redirect_cause_i == 1 || trace_redirect_cause_i == 3));
                    end else begin
                        compare("redirect_stage", 1,
                                64'(trace_redirect_stage_i == 2 || trace_redirect_stage_i == 3));
                        compare("redirect_cause", 1,
                                64'(trace_redirect_cause_i != 0));
                    end
                end
                if (trace_source0_valid_i) begin
                    compare("source0_port", 1, 64'(0 < S));
                    compare("source0_tag", 0, 64'($isunknown(trace_source0_tag_i)));
                    compare("source0_domain", 1,
                            64'(trace_source0_domain_i == 0 || (FPU_FORMAT != "NONE" && 0 < R)));
                end
                if (trace_source1_valid_i) begin
                    compare("source1_port", 1, 64'(1 < S));
                    compare("source1_tag", 0, 64'($isunknown(trace_source1_tag_i)));
                    compare("source1_domain", 1,
                            64'(trace_source1_domain_i == 0 || (FPU_FORMAT != "NONE" && 1 < R)));
                end
                if (trace_source2_valid_i) begin
                    compare("source2_port", 1, 64'(2 < S));
                    compare("source2_tag", 0, 64'($isunknown(trace_source2_tag_i)));
                    compare("source2_domain", 1,
                            64'(trace_source2_domain_i == 0 || (FPU_FORMAT != "NONE" && 2 < R)));
                end
                if (trace_source3_valid_i) begin
                    compare("source3_port", 1, 64'(3 < S));
                    compare("source3_tag", 0, 64'($isunknown(trace_source3_tag_i)));
                    compare("source3_domain", 1,
                            64'(trace_source3_domain_i == 0 || (FPU_FORMAT != "NONE" && 3 < R)));
                end
                if (trace_source4_valid_i) begin
                    compare("source4_port", 1, 64'(4 < S));
                    compare("source4_tag", 0, 64'($isunknown(trace_source4_tag_i)));
                    compare("source4_domain", 1,
                            64'(trace_source4_domain_i == 0 || (FPU_FORMAT != "NONE" && 4 < R)));
                end
                // Queue each side independently: AXI/BFM and trace need not pulse together.
                if (trace_mem_effect_valid_i) begin
                    trace_beat = '{trace_mem_effect_addr_i,
                                    trace_mem_effect_data_i, trace_mem_effect_mask_i};
                    compare("mem_effect_tag", 0, 64'($isunknown(trace_mem_effect_tag_i)));
                    if (cacheable(trace_mem_effect_addr_i))
                        cache_actual.push_back(trace_beat);
                    else
                        trace_beats.push_back(trace_beat);
                end
                if (bfm_valid_i) begin
                    bfm_beat = '{bfm_addr_i, bfm_data_i, bfm_mask_i};
                    bfm_beats.push_back(bfm_beat);
                end
                while (trace_beats.size() != 0 && bfm_beats.size() != 0) begin
                    trace_beat = trace_beats.pop_front();
                    bfm_beat = bfm_beats.pop_front();
                    compare("mem_effect_addr", 64'(bfm_beat.addr), 64'(trace_beat.addr));
                    compare("mem_effect_data", 64'(bfm_beat.data), 64'(trace_beat.data));
                    compare("mem_effect_mask", 64'(bfm_beat.mask), 64'(trace_beat.mask));
                end
                while (cache_actual.size() != 0 && cache_expected.size() != 0) begin
                    trace_beat = cache_actual.pop_front();
                    bfm_beat = cache_expected.pop_front();
                    compare("cache_effect_addr", 64'(bfm_beat.addr), 64'(trace_beat.addr));
                    compare("cache_effect_data", 64'(bfm_beat.data), 64'(trace_beat.data));
                    compare("cache_effect_mask", 64'(bfm_beat.mask), 64'(trace_beat.mask));
                end
                cycle_r = cycle_r + 1;
                if (finish_i) begin
                    compare("cache_effect_missing", 0, 64'(cache_expected.size()));
                    compare("cache_effect_extra", 0, 64'(cache_actual.size()));
                    compare("architectural_eof", 0, 64'(have_arch));
                    compare("mem_effect_missing", 0, 64'(bfm_beats.size()));
                    compare("mem_effect_extra", 0, 64'(trace_beats.size()));
                    $display("PASS trace retirements=%0d cycles=%0d", retire_r, cycle_r);
                end
            end
        end
    end
endmodule
