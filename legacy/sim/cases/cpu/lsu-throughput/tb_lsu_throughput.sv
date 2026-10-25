`timescale 1ns/1ps
`include "edrv32_bus.vh"
`include "edrv32_lsu.vh"

// Warm-cache, straight-line LSU throughput probe. CASEID selects the body:
// 0 ALU, 1 loads, 2 stores, 3 load/use, 4 store/unrelated load,
// 5 store/full-forward load, 6 repeated byte-store/partial word load,
// 7 one partial-overlap pair followed by unrelated ALU instructions.
module tb_lsu_throughput;
    localparam [31:0] RESET_PC = 32'h8000_0000;
    localparam integer BODY_START = 3;
    localparam integer BODY_LENGTH = 64;
    localparam integer BODY_END = BODY_START + BODY_LENGTH - 1;
    localparam integer LOOP_INDEX = BODY_END + 1;
    localparam integer SAMPLE_FIRST = BODY_START + 8;
    localparam integer SAMPLE_LAST = BODY_END - 8;

    reg clk;
    reg rst_n;
    wire imem_req_valid, imem_req_ready;
    wire [31:0] imem_req_addr;
    wire imem_resp_valid, imem_resp_ready;
    wire [31:0] imem_resp_rdata;
    wire imem_resp_error;
    wire dmem_req_valid, dmem_req_ready;
    wire [31:0] dmem_req_addr;
    wire dmem_req_we;
    wire [`BUS_SZ_W-1:0] dmem_req_size;
    wire [3:0] dmem_req_wstrb;
    wire [31:0] dmem_req_wdata;
    wire dmem_resp_valid, dmem_resp_ready;
    wire [31:0] dmem_resp_rdata;
    wire dmem_resp_error;
    wire retire;
    wire [31:0] retire_pc;
    wire [31:0] retire_instr;
    wire retire_exception;
    wire [31:0] retire_cause;

    integer caseid;
    integer i;
    integer cycle;
    integer pass;
    integer first_cycle;
    integer last_cycle;
    integer sampled_retires;
    integer lookup_fires;
    integer lookup_wait_lookup;
    integer lookup_wait_store;
    integer lookup_wait_other;
    integer load_full_cycles;
    integer store_full_cycles;
    integer ex_load_wait_cycles;
    integer commit_wait_cycles;
    integer decode_dep_cycles;
    integer decode_resident_cycles;
    integer decode_load_cycles;
    integer pair_first_cycle;
    integer pair_gap_sum;
    integer pair_count;
    integer last_lookup_cycle;
    integer lookup_gap_sum;
    integer lookup_gap_count;
    integer trace_enable;
    integer cold_first_request_cycle;
    integer cold_first_completion_cycle;
    integer cold_misses;
    integer warm_dcache_misses;
    integer warm_icache_misses;
    reg [`EDRV32_LSU_TOKEN_W-1:0] warm_sample_token;
    integer warm_sample_request_cycle;
    integer warm_sample_completion_cycle;
    integer partial_store_retire_cycle;
    integer partial_load_retire_cycle;

    function automatic [31:0] enc_i;
        input [11:0] imm;
        input [4:0] rs1;
        input [2:0] funct3;
        input [4:0] rd;
        input [6:0] opcode;
        begin enc_i = {imm, rs1, funct3, rd, opcode}; end
    endfunction
    function automatic [31:0] enc_s;
        input [11:0] imm;
        input [4:0] rs2;
        input [4:0] rs1;
        input [2:0] funct3;
        begin enc_s = {imm[11:5], rs2, rs1, funct3, imm[4:0], 7'h23}; end
    endfunction
    function automatic [31:0] enc_j;
        input [20:0] imm;
        input [4:0] rd;
        begin enc_j = {imm[20], imm[10:1], imm[11], imm[19:12], rd, 7'h6f}; end
    endfunction

    initial clk = 1'b0;
    always #5 clk = ~clk;

    edrv32_cached_core_native_harness #(
        .RESET_PC(RESET_PC), .ICACHE_LINE_COUNT(256),
        .DCACHE_LINE_COUNT(256)
    ) u_core (
        .clk_i(clk), .rst_n_i(rst_n),
        .imem_req_valid_o(imem_req_valid), .imem_req_ready_i(imem_req_ready),
        .imem_req_addr_o(imem_req_addr),
        .imem_resp_valid_i(imem_resp_valid), .imem_resp_ready_o(imem_resp_ready),
        .imem_resp_rdata_i(imem_resp_rdata), .imem_resp_error_i(imem_resp_error),
        .dmem_req_valid_o(dmem_req_valid), .dmem_req_ready_i(dmem_req_ready),
        .dmem_req_addr_o(dmem_req_addr), .dmem_req_we_o(dmem_req_we),
        .dmem_req_size_o(dmem_req_size), .dmem_req_wstrb_o(dmem_req_wstrb),
        .dmem_req_wdata_o(dmem_req_wdata),
        .dmem_resp_valid_i(dmem_resp_valid), .dmem_resp_ready_o(dmem_resp_ready),
        .dmem_resp_rdata_i(dmem_resp_rdata), .dmem_resp_error_i(dmem_resp_error),
        .itcm_req_valid_o(), .itcm_req_ready_i(1'b0), .itcm_req_addr_o(),
        .itcm_resp_valid_i(1'b0), .itcm_resp_ready_o(),
        .itcm_resp_rdata_i(32'd0), .itcm_resp_error_i(1'b0),
        .dtcm_req_valid_o(), .dtcm_req_ready_i(1'b0), .dtcm_req_addr_o(),
        .dtcm_req_we_o(), .dtcm_req_size_o(), .dtcm_req_wstrb_o(),
        .dtcm_req_wdata_o(), .dtcm_resp_valid_i(1'b0),
        .dtcm_resp_ready_o(), .dtcm_resp_rdata_i(32'd0),
        .dtcm_resp_error_i(1'b0),
        .irq_soft_i(1'b0), .irq_timer_i(1'b0), .irq_ext_i(1'b0),
        .time_value_i(64'd0),
        .retire_o(retire), .retire_pc_o(retire_pc),
        .retire_instr_o(retire_instr), .retire_exception_o(retire_exception),
        .retire_cause_o(retire_cause),
        .debug_decode_instr_o(), .debug_decode_pc_o(), .core_sleep_o()
    );

    edrv32_mem_model #(
        .MEM_DEPTH_WORDS(4096), .BASE_ADDR(RESET_PC),
        .IMEM_LAT(1), .DMEM_LAT(2)
    ) u_mem (
        .clk(clk), .rst_n(rst_n),
        .imem_req_valid_i(imem_req_valid), .imem_req_ready_o(imem_req_ready),
        .imem_req_addr_i(imem_req_addr), .imem_resp_valid_o(imem_resp_valid),
        .imem_resp_ready_i(imem_resp_ready), .imem_resp_rdata_o(imem_resp_rdata),
        .imem_resp_error_o(imem_resp_error),
        .dmem_req_valid_i(dmem_req_valid), .dmem_req_ready_o(dmem_req_ready),
        .dmem_req_addr_i(dmem_req_addr), .dmem_req_we_i(dmem_req_we),
        .dmem_req_size_i(dmem_req_size), .dmem_req_wstrb_i(dmem_req_wstrb),
        .dmem_req_wdata_i(dmem_req_wdata),
        .dmem_resp_valid_o(dmem_resp_valid), .dmem_resp_ready_i(dmem_resp_ready),
        .dmem_resp_rdata_o(dmem_resp_rdata), .dmem_resp_error_o(dmem_resp_error),
        .imem_req_stall_i(1'b0), .dmem_req_stall_i(1'b0)
    );

    initial begin
        if (!$value$plusargs("CASEID=%d", caseid)) caseid = 0;
        trace_enable = $test$plusargs("TRACE");
        if (caseid < 0 || caseid > 7) $fatal(1, "invalid CASEID=%0d", caseid);
        rst_n = 1'b0;
        cycle = 0;
        pass = 0;
        first_cycle = -1;
        last_cycle = -1;
        sampled_retires = 0;
        lookup_fires = 0;
        lookup_wait_lookup = 0;
        lookup_wait_store = 0;
        lookup_wait_other = 0;
        load_full_cycles = 0;
        store_full_cycles = 0;
        ex_load_wait_cycles = 0;
        commit_wait_cycles = 0;
        decode_dep_cycles = 0;
        decode_resident_cycles = 0;
        decode_load_cycles = 0;
        pair_first_cycle = -1;
        pair_gap_sum = 0;
        pair_count = 0;
        last_lookup_cycle = -1;
        lookup_gap_sum = 0;
        lookup_gap_count = 0;
        cold_first_request_cycle = -1;
        cold_first_completion_cycle = -1;
        cold_misses = 0;
        warm_dcache_misses = 0;
        warm_icache_misses = 0;
        warm_sample_token = {`EDRV32_LSU_TOKEN_W{1'b0}};
        warm_sample_request_cycle = -1;
        warm_sample_completion_cycle = -1;
        partial_store_retire_cycle = -1;
        partial_load_retire_cycle = -1;

        // Keep the instruction footprint within I$, and use two warm data
        // lines. The first loop is warmup; the measured loop uses same code.
        u_mem.mem[0] = {20'h80001, 5'd10, 7'h37};
        u_mem.mem[1] = (caseid == 6 || caseid == 7)
            ? enc_i(12'h055, 5'd0, 3'b000, 5'd5, 7'h13)
            : enc_i(12'h100, 5'd10, 3'b000, 5'd11, 7'h13);
        // For the partial-overlap case, warm the data line before any store.
        u_mem.mem[2] = (caseid == 6 || caseid == 7)
            ? enc_i(12'd0, 5'd10, 3'b010, 5'd4, 7'h03)
            : enc_i(12'h055, 5'd0, 3'b000, 5'd5, 7'h13);
        u_mem.mem[32'h1000 >> 2] = 32'h11223344;
        u_mem.mem[(32'h1000 >> 2)+1] = 32'h01020304;
        u_mem.mem[(32'h1000 >> 2)+2] = 32'h05060708;
        u_mem.mem[(32'h1000 >> 2)+3] = 32'h090a0b0c;
        u_mem.mem[32'h1100 >> 2] = 32'h55667788;
        for (i = 0; i < BODY_LENGTH; i = i + 1) begin
            case (caseid)
                0: u_mem.mem[BODY_START+i] = enc_i(12'd1, 5'd0, 3'b000, 5'd6, 7'h13);
                1: u_mem.mem[BODY_START+i] = enc_i((i%4)*4, 5'd10, 3'b010,
                                                   5'd6+(i%4), 7'h03);
                2: u_mem.mem[BODY_START+i] = enc_s((i%4)*4, 5'd5, 5'd10, 3'b010);
                3: u_mem.mem[BODY_START+i] = (i%2 == 0)
                    ? enc_i(12'd0, 5'd10, 3'b010, 5'd6, 7'h03)
                    : enc_i(12'd1, 5'd6, 3'b000, 5'd7, 7'h13);
                4: u_mem.mem[BODY_START+i] = (i%2 == 0)
                    ? enc_s(12'd0, 5'd5, 5'd10, 3'b010)
                    : enc_i(12'd0, 5'd11, 3'b010, 5'd6, 7'h03);
                5: u_mem.mem[BODY_START+i] = (i%2 == 0)
                    ? enc_s(12'd0, 5'd5, 5'd10, 3'b010)
                    : enc_i(12'd0, 5'd10, 3'b010, 5'd6, 7'h03);
                6: u_mem.mem[BODY_START+i] = (i%2 == 0)
                    ? enc_s(12'd0, 5'd5, 5'd10, 3'b000)
                    : enc_i(12'd0, 5'd10, 3'b010, 5'd6, 7'h03);
                7: u_mem.mem[BODY_START+i] = (i == 0)
                    ? enc_s(12'd0, 5'd5, 5'd10, 3'b000)
                    : (i == 1)
                    ? enc_i(12'd0, 5'd10, 3'b010, 5'd6, 7'h03)
                    : enc_i(12'd1, 5'd0, 3'b000, 5'd7, 7'h13);
            endcase
        end
        u_mem.mem[LOOP_INDEX] = enc_j(21'h1ff_f00, 5'd0);
        repeat (4) @(posedge clk);
        rst_n = 1'b1;
    end

    always @(posedge clk) begin
        if (rst_n) begin
            cycle = cycle + 1;
            if (retire_exception) $fatal(1, "unexpected exception pc=%08x", retire_pc);
            if (trace_enable && caseid == 6 && retire && cycle < 500)
                $display("DEBUG case=6 cyc=%0d retire_pc=%08x", cycle, retire_pc);
            if (trace_enable && caseid == 6 && cycle >= 55 && cycle <= 72)
                $display("STEP cyc=%0d commit_pc=%08x commit_valid=%b commit_ready=%b lq_blocked=%b sq_prepared=%b sq_committed=%b release=%b prep_valid=%b prep_token=%b load_req=%b dc_state=%0d dc_ready=%b",
                    cycle, u_core.u_cached_core.u_core.mem2_packet_pc_w,
                    u_core.u_cached_core.u_core.mem2_packet_valid_w,
                    u_core.u_cached_core.u_core.mem2_packet_accept_w,
                    u_core.u_cached_core.u_core.u_load_queue.blocked_r,
                    u_core.u_cached_core.u_core.u_store_queue.prepared_r,
                    u_core.u_cached_core.u_core.u_store_queue.committed_count_r,
                    u_core.u_cached_core.u_core.store_release_valid_w,
                    u_core.u_cached_core.u_core.store_prepare_valid_w,
                    u_core.u_cached_core.u_core.store_prepare_token_w,
                    u_core.u_cached_core.u_core.load_request_valid_w,
                    u_core.u_cached_core.u_dcache.state_r,
                    u_core.u_cached_core.u_core.dcache_lookup_ready_i);
            if (trace_enable && (caseid == 1 || caseid == 2) &&
                pass == 1 && first_cycle >= 0 && cycle < first_cycle+15)
                $display("CACHE case=%0d cyc=%0d state=%0d lookup_valid=%b lookup_ready=%b fast=%b store_fire=%b commit_valid=%b lq_full=%b sq_full=%b",
                    caseid, cycle, u_core.u_cached_core.u_dcache.state_r,
                    u_core.u_cached_core.u_core.dcache_lookup_valid_o,
                    u_core.u_cached_core.u_core.dcache_lookup_ready_i,
                    u_core.u_cached_core.u_dcache.lookup_fast_valid_o,
                    u_core.u_cached_core.u_dcache.local_store_fire_w,
                    u_core.u_cached_core.u_dcache.commit_req_valid_i,
                    u_core.u_cached_core.u_core.u_load_queue.full_o,
                    u_core.u_cached_core.u_core.u_store_queue.full_o);
            if (caseid == 1 && pass == 0) begin
                if (cold_first_request_cycle < 0 &&
                    u_core.u_cached_core.u_core.dcache_lookup_valid_o &&
                    u_core.u_cached_core.u_core.dcache_lookup_ready_i)
                    cold_first_request_cycle = cycle;
                if (cold_first_completion_cycle < 0 &&
                    u_core.u_cached_core.u_core.load_completion_valid_w &&
                    u_core.u_cached_core.u_core.load_completion_pc_w ==
                        RESET_PC + BODY_START*4)
                    cold_first_completion_cycle = cycle;
                if (u_core.u_cached_core.u_dcache.miss_o)
                    cold_misses = cold_misses + 1;
            end
            if (caseid == 1 && pass == 1 && first_cycle >= 0) begin
                if (warm_sample_request_cycle < 0 &&
                    u_core.u_cached_core.u_dcache.lookup_request_fire_w &&
                    !u_core.u_cached_core.u_dcache.lookup_issue_store_w) begin
                    warm_sample_token =
                        u_core.u_cached_core.u_dcache.lookup_issue_token_w;
                    warm_sample_request_cycle = cycle;
                end
                if (warm_sample_request_cycle >= 0 &&
                    warm_sample_completion_cycle < 0 &&
                    u_core.u_cached_core.u_dcache.lookup_fast_valid_o &&
                    u_core.u_cached_core.u_dcache.lookup_fast_token_o ==
                        warm_sample_token)
                    warm_sample_completion_cycle = cycle;
            end
            if (pass == 1 && first_cycle >= 0 &&
                sampled_retires < SAMPLE_LAST-SAMPLE_FIRST+1) begin
                if (u_core.u_cached_core.u_dcache.miss_o)
                    warm_dcache_misses = warm_dcache_misses + 1;
                if (u_core.u_cached_core.u_icache.miss_o)
                    warm_icache_misses = warm_icache_misses + 1;
            end
            if (caseid == 7 && pass == 1 && retire) begin
                if (retire_pc == RESET_PC + BODY_START*4)
                    partial_store_retire_cycle = cycle;
                if (retire_pc == RESET_PC + (BODY_START+1)*4)
                    partial_load_retire_cycle = cycle;
            end
            if (pass == 1 && first_cycle >= 0 && sampled_retires < SAMPLE_LAST-SAMPLE_FIRST+1) begin
                if (u_core.u_cached_core.u_core.dcache_lookup_valid_o &&
                    u_core.u_cached_core.u_core.dcache_lookup_ready_i) begin
                    lookup_fires = lookup_fires + 1;
                    if (last_lookup_cycle >= 0) begin
                        lookup_gap_sum = lookup_gap_sum + cycle - last_lookup_cycle;
                        lookup_gap_count = lookup_gap_count + 1;
                    end
                    last_lookup_cycle = cycle;
                end
                if (u_core.u_cached_core.u_core.dcache_lookup_valid_o &&
                    !u_core.u_cached_core.u_core.dcache_lookup_ready_i) begin
                    case (u_core.u_cached_core.u_dcache.state_r)
                        5'd1: lookup_wait_lookup = lookup_wait_lookup + 1;
                        5'd3: lookup_wait_store = lookup_wait_store + 1;
                        default: lookup_wait_other = lookup_wait_other + 1;
                    endcase
                end
                if (u_core.u_cached_core.u_core.u_load_queue.full_o)
                    load_full_cycles = load_full_cycles + 1;
                if (u_core.u_cached_core.u_core.u_store_queue.full_o)
                    store_full_cycles = store_full_cycles + 1;
                if (u_core.u_cached_core.u_core.ex_late_load_stall_w)
                    ex_load_wait_cycles = ex_load_wait_cycles + 1;
                if (u_core.u_cached_core.u_core.decode_dependency_stall_w)
                    decode_dep_cycles = decode_dep_cycles + 1;
                if (u_core.u_cached_core.u_core.decode_hpm_stall_resident_w)
                    decode_resident_cycles = decode_resident_cycles + 1;
                if (u_core.u_cached_core.u_core.decode_hpm_stall_load_w)
                    decode_load_cycles = decode_load_cycles + 1;
                if (u_core.u_cached_core.u_core.mem2_packet_valid_w &&
                    !u_core.u_cached_core.u_core.mem2_packet_accept_w)
                    commit_wait_cycles = commit_wait_cycles + 1;
            end
            if (retire && retire_pc == RESET_PC + LOOP_INDEX*4) begin
                pass = pass + 1;
            end
            if (retire && pass == 1 &&
                retire_pc >= RESET_PC + SAMPLE_FIRST*4 &&
                retire_pc <= RESET_PC + SAMPLE_LAST*4) begin
                if (first_cycle < 0) first_cycle = cycle;
                last_cycle = cycle;
                sampled_retires = sampled_retires + 1;
                if (trace_enable) $display("RET case=%0d cyc=%0d idx=%0d",
                                           caseid, cycle, (retire_pc-RESET_PC)/4);
                if ((caseid >= 3) && (caseid <= 6)) begin
                    if (((retire_pc-RESET_PC)/4 - BODY_START) % 2 == 0)
                        pair_first_cycle = cycle;
                    else if (pair_first_cycle >= 0) begin
                        pair_gap_sum = pair_gap_sum + cycle - pair_first_cycle;
                        pair_count = pair_count + 1;
                    end
                end
                if (sampled_retires == SAMPLE_LAST-SAMPLE_FIRST+1) begin
                    if (caseid == 1 &&
                        u_core.u_cached_core.u_core.u_decode_stage.u_regfile.regs_r[6]
                            !== 32'h11223344)
                        $fatal(1, "load stream returned wrong data");
                    if (caseid == 3 &&
                        u_core.u_cached_core.u_core.u_decode_stage.u_regfile.regs_r[7]
                            !== 32'h11223345)
                        $fatal(1, "load/use returned wrong data");
                    if (caseid == 4 &&
                        u_core.u_cached_core.u_core.u_decode_stage.u_regfile.regs_r[6]
                            !== 32'h55667788)
                        $fatal(1, "unrelated load returned wrong data");
                    if (caseid == 5 &&
                        u_core.u_cached_core.u_core.u_decode_stage.u_regfile.regs_r[6]
                            !== 32'h00000055)
                        $fatal(1, "full-forward load returned wrong data");
                    if (caseid == 6 &&
                        u_core.u_cached_core.u_core.u_decode_stage.u_regfile.regs_r[6]
                            !== 32'h11223355)
                        $fatal(1, "partial-overlap load returned %08x",
                            u_core.u_cached_core.u_core.u_decode_stage.u_regfile.regs_r[6]);
                    $display("RESULT case=%0d count=%0d first=%0d last=%0d span=%0d bubbles=%0d pair_gap_sum=%0d pairs=%0d lookup_fires=%0d lookup_gap_sum=%0d lookup_gaps=%0d wait_lookup=%0d wait_store=%0d wait_other=%0d lq_full=%0d sq_full=%0d ex_wait=%0d commit_wait=%0d decode_dep=%0d decode_resident=%0d decode_load=%0d warm_dmiss=%0d warm_imiss=%0d",
                        caseid, sampled_retires, first_cycle, last_cycle,
                        last_cycle-first_cycle, last_cycle-first_cycle-(sampled_retires-1),
                        pair_gap_sum, pair_count, lookup_fires, lookup_gap_sum,
                        lookup_gap_count, lookup_wait_lookup, lookup_wait_store,
                        lookup_wait_other, load_full_cycles, store_full_cycles,
                        ex_load_wait_cycles, commit_wait_cycles,
                        decode_dep_cycles, decode_resident_cycles,
                        decode_load_cycles, warm_dcache_misses,
                        warm_icache_misses);
                    if (caseid == 1)
                        $display("LOAD_LATENCY cold_request=%0d cold_completion=%0d cold_latency=%0d warm_request=%0d warm_completion=%0d warm_latency=%0d cold_misses=%0d",
                            cold_first_request_cycle, cold_first_completion_cycle,
                            cold_first_completion_cycle-cold_first_request_cycle,
                            warm_sample_request_cycle, warm_sample_completion_cycle,
                            warm_sample_completion_cycle-warm_sample_request_cycle,
                            cold_misses);
                    if (caseid == 7)
                        $display("PARTIAL_CONTROL store_retire=%0d load_retire=%0d gap=%0d",
                            partial_store_retire_cycle, partial_load_retire_cycle,
                            partial_load_retire_cycle-partial_store_retire_cycle);
                    $display("PASS: warm-cache LSU throughput case=%0d sample=%0d",caseid,sampled_retires);
                    $finish;
                end
            end
            if (cycle == 2000 && caseid == 6)
                $fatal(1, "PARTIAL_OVERLAP_DEADLOCK commit_pc=%08x op=%0d lq_count=%0d lq_blocked=%b sq_count=%0d sq_committed=%b sq_prepared=%b dcache_state=%0d lookup_valid=%b lookup_ready=%b",
                    u_core.u_cached_core.u_core.mem2_packet_pc_w,
                    u_core.u_cached_core.u_core.mem2_packet_op_class_w,
                    u_core.u_cached_core.u_core.u_load_queue.count_r,
                    u_core.u_cached_core.u_core.u_load_queue.blocked_r,
                    u_core.u_cached_core.u_core.u_store_queue.count_r,
                    u_core.u_cached_core.u_core.u_store_queue.committed_count_r,
                    u_core.u_cached_core.u_core.u_store_queue.prepared_r,
                    u_core.u_cached_core.u_dcache.state_r,
                    u_core.u_cached_core.u_core.dcache_lookup_valid_o,
                    u_core.u_cached_core.u_core.dcache_lookup_ready_i);
            if (cycle > 20000) $fatal(1, "timeout case=%0d pass=%0d", caseid, pass);
        end
    end
endmodule
