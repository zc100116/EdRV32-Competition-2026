`timescale 1ns/1ps
`include "edrv32_bus.vh"
`include "edrv32_pair.vh"

module tb_core_compliance #(parameter DUAL_ISSUE=0, parameter FETCH_WIDE=0, parameter ACT_SELF_CHECK=1);
    localparam [31:0] RESET_PC = 32'h8000_0000;
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
    wire trap;
    wire [31:0] trap_cause;
    reg [63:0] time_value;
    reg [31:0] tohost_addr;
    integer max_cycles;
    integer cycles;
    integer retires;
    integer dual_retires;
    integer traps;
    integer quiet_cycles;
    integer trace_enable;
    reg monitor_armed;
    reg prev_frontend_kill, prev_commit_kill;
    reg prev_decode_to_ex_kill;
    reg prev_align_valid, prev_align_accept;
    reg [31:0] prev_align_pc, prev_align_instr;
    reg prev_decode_valid, prev_decode_accept;
    reg [31:0] prev_decode_pc, prev_decode_instr;
    reg [4:0] prev_decode_rd;
    reg prev_ex_valid, prev_ex_accept;
    reg [31:0] prev_ex_pc, prev_ex_instr, prev_ex_result;
    reg [4:0] prev_ex_rd;
    reg prev_mem1_packet_valid, prev_mem1_packet_accept;
    reg [31:0] prev_mem1_packet_pc, prev_mem1_packet_instr;
    reg [31:0] prev_mem1_packet_result;
    reg [4:0] prev_mem1_packet_rd;
    reg prev_mem2_packet_valid, prev_mem2_packet_accept;
    reg [31:0] prev_mem2_packet_pc, prev_mem2_packet_instr;
    reg [31:0] prev_mem2_packet_result;
    reg [4:0] prev_mem2_packet_rd;

    wire tohost_write_complete_w;
    wire [31:0] tohost_write_addr_w;
    wire [3:0] tohost_write_wstrb_w;
    wire [31:0] tohost_write_data_w;

    initial clk = 1'b0;
    always #5 clk = ~clk;

`ifdef EDRV32_CACHED_TEST
    edrv32_cached_core_native_harness #(
        .RESET_PC(RESET_PC), .DUAL_ISSUE(DUAL_ISSUE), .FETCH_WIDE(FETCH_WIDE), .ICACHE_LINE_COUNT(64), .DCACHE_LINE_COUNT(64)
    ) u_core (
        .clk_i(clk), .rst_n_i(rst_n),
        .imem_req_valid_o(imem_req_valid), .imem_req_ready_i(imem_req_ready),
        .imem_req_addr_o(imem_req_addr), .imem_resp_valid_i(imem_resp_valid),
        .imem_resp_ready_o(imem_resp_ready), .imem_resp_rdata_i(imem_resp_rdata),
        .imem_resp_error_i(imem_resp_error),
        .dmem_req_valid_o(dmem_req_valid), .dmem_req_ready_i(dmem_req_ready),
        .dmem_req_addr_o(dmem_req_addr), .dmem_req_we_o(dmem_req_we),
        .dmem_req_size_o(dmem_req_size), .dmem_req_wstrb_o(dmem_req_wstrb),
        .dmem_req_wdata_o(dmem_req_wdata), .dmem_resp_valid_i(dmem_resp_valid),
        .dmem_resp_ready_o(dmem_resp_ready), .dmem_resp_rdata_i(dmem_resp_rdata),
        .dmem_resp_error_i(dmem_resp_error),
        .itcm_req_valid_o(), .itcm_req_ready_i(1'b0), .itcm_req_addr_o(),
        .itcm_resp_valid_i(1'b0), .itcm_resp_ready_o(),
        .itcm_resp_rdata_i(32'd0), .itcm_resp_error_i(1'b0),
        .dtcm_req_valid_o(), .dtcm_req_ready_i(1'b0), .dtcm_req_addr_o(),
        .dtcm_req_we_o(), .dtcm_req_size_o(), .dtcm_req_wstrb_o(),
        .dtcm_req_wdata_o(), .dtcm_resp_valid_i(1'b0),
        .dtcm_resp_ready_o(), .dtcm_resp_rdata_i(32'd0),
        .dtcm_resp_error_i(1'b0),
        .irq_soft_i(1'b0), .irq_timer_i(1'b0), .irq_ext_i(1'b0),
        .time_value_i(time_value),
        .retire_o(retire), .retire_pc_o(retire_pc), .retire_instr_o(retire_instr),
        .retire_exception_o(trap), .retire_cause_o(trap_cause)
    );
`else
    edrv32_core #(.RESET_PC(RESET_PC), .DUAL_ISSUE(DUAL_ISSUE), .FETCH_WIDE(FETCH_WIDE)) u_core (
        .imem_req_words_i(2'd1),.imem_resp_upper_i(32'd0),.imem_preview_upper_i(32'd0),
        .clk_i(clk), .rst_n_i(rst_n),
        .imem_req_valid_o(imem_req_valid), .imem_req_ready_i(imem_req_ready),
        .imem_req_addr_o(imem_req_addr), .imem_resp_valid_i(imem_resp_valid),
        .imem_resp_ready_o(imem_resp_ready), .imem_resp_rdata_i(imem_resp_rdata),
        .imem_resp_error_i(imem_resp_error),
        .dmem_req_valid_o(dmem_req_valid), .dmem_req_ready_i(dmem_req_ready),
        .dmem_req_addr_o(dmem_req_addr), .dmem_req_we_o(dmem_req_we),
        .dmem_req_size_o(dmem_req_size), .dmem_req_wstrb_o(dmem_req_wstrb),
        .dmem_req_wdata_o(dmem_req_wdata), .dmem_req_cacheable_o(),
        .dmem_resp_valid_i(dmem_resp_valid),
        .dmem_resp_ready_o(dmem_resp_ready), .dmem_resp_rdata_i(dmem_resp_rdata),
        .dmem_resp_error_i(dmem_resp_error),
        .dcache_lookup_valid_o(), .dcache_lookup_ready_i(1'b0),
        .dcache_lookup_addr_o(), .dcache_lookup_store_o(),
        .dcache_lookup_resp_valid_i(1'b0), .dcache_lookup_resp_ready_o(),
        .dcache_lookup_resp_data_i(32'd0), .dcache_lookup_resp_error_i(1'b0),
        .dcache_lookup_cancel_o(),
        .cache_perf_events_i(5'd0),
        .irq_soft_i(1'b0), .irq_timer_i(1'b0), .irq_ext_i(1'b0),
        .time_value_i(time_value),
        .retire_o(retire), .retire_pc_o(retire_pc), .retire_instr_o(retire_instr),
        .retire_exception_o(trap), .retire_cause_o(trap_cause),
        .fencei_retire_o()
    );
`endif

    // Normalize the hierarchy so both cached and uncached configurations run
    // the same pipeline-boundary contract monitors.
`ifdef EDRV32_CACHED_TEST
`define EDRV32_MON_CORE u_core.u_cached_core.u_core
    wire monitor_dmem_req_valid_w =
        u_core.u_cached_core.core_dmem_req_valid_w;
`else
`define EDRV32_MON_CORE u_core
    wire monitor_dmem_req_valid_w = dmem_req_valid;
`endif
    wire monitor_store_drain_w = `EDRV32_MON_CORE.store_drain_select_w;

    wire monitor_frontend_kill_w = `EDRV32_MON_CORE.frontend_kill_w;
    wire monitor_decode_to_ex_kill_w =
        `EDRV32_MON_CORE.decode_to_ex_kill_w;
    wire monitor_commit_kill_w =
        `EDRV32_MON_CORE.commit_kill_younger_w;

    wire monitor_align_valid_w = `EDRV32_MON_CORE.align_valid_w;
    wire monitor_align_accept_w = `EDRV32_MON_CORE.align_accept_w;
    wire [31:0] monitor_align_pc_w = `EDRV32_MON_CORE.align_pc_w;
    wire [31:0] monitor_align_instr_w = `EDRV32_MON_CORE.align_instr_w;

    wire monitor_decode_valid_w = `EDRV32_MON_CORE.decode_valid_w;
    wire monitor_decode_accept_w = `EDRV32_MON_CORE.decode_accept_w;
    wire [31:0] monitor_decode_pc_w = `EDRV32_MON_CORE.decode_pc_w;
    wire [31:0] monitor_decode_instr_w = `EDRV32_MON_CORE.decode_instr_w;
    wire [4:0] monitor_decode_rd_w = `EDRV32_MON_CORE.decode_rd_w;

    wire monitor_ex_valid_w = `EDRV32_MON_CORE.ex_valid_w;
    wire monitor_ex_accept_w = `EDRV32_MON_CORE.ex_accept_w;
    wire [31:0] monitor_ex_pc_w = `EDRV32_MON_CORE.ex_pc_w;
    wire [31:0] monitor_ex_instr_w = `EDRV32_MON_CORE.ex_instr_w;
    wire [4:0] monitor_ex_rd_w = `EDRV32_MON_CORE.ex_rd_w;
    wire [31:0] monitor_ex_result_w = `EDRV32_MON_CORE.ex_result_w;

    wire monitor_mem1_packet_valid_w = `EDRV32_MON_CORE.mem1_packet_valid_w;
    wire monitor_mem1_packet_accept_w = `EDRV32_MON_CORE.mem1_packet_accept_w;
    wire [31:0] monitor_mem1_packet_pc_w = `EDRV32_MON_CORE.mem1_packet_pc_w;
    wire [31:0] monitor_mem1_packet_instr_w = `EDRV32_MON_CORE.mem1_packet_instr_w;
    wire [4:0] monitor_mem1_packet_rd_w = `EDRV32_MON_CORE.mem1_packet_rd_w;
    wire [31:0] monitor_mem1_packet_result_w = `EDRV32_MON_CORE.mem1_packet_result_w;

    wire monitor_mem2_packet_valid_w = `EDRV32_MON_CORE.mem2_packet_valid_w;
    wire monitor_mem2_packet_accept_w = `EDRV32_MON_CORE.mem2_packet_accept_w;
    wire [31:0] monitor_mem2_packet_pc_w = `EDRV32_MON_CORE.mem2_packet_pc_w;
    wire [31:0] monitor_mem2_packet_instr_w = `EDRV32_MON_CORE.mem2_packet_instr_w;
    wire [4:0] monitor_mem2_packet_rd_w = `EDRV32_MON_CORE.mem2_packet_rd_w;
    wire [31:0] monitor_mem2_packet_result_w =
        `EDRV32_MON_CORE.mem2_packet_result_w;

    wire [3:0] monitor_if2_count_w =
        `EDRV32_MON_CORE.u_if2_stage.count_r;
    wire [1:0] monitor_mem1_packet_count_w =
        `EDRV32_MON_CORE.u_mem1_stage.pipe_count_r;
`ifdef EDRV32_CACHED_TEST
    wire monitor_load_queue_empty_w = `EDRV32_MON_CORE.load_queue_empty_w;
    wire [1:0] monitor_store_valid_w =
        `EDRV32_MON_CORE.u_store_queue.valid_r;
    wire [1:0] monitor_store_committed_w =
        `EDRV32_MON_CORE.u_store_queue.committed_count_r;
    wire monitor_store_drain_valid_w =
        `EDRV32_MON_CORE.store_drain_valid_w;
    wire monitor_store_drain_ready_w =
        `EDRV32_MON_CORE.store_drain_ready_w;
    wire monitor_dmem_owner_valid_w = `EDRV32_MON_CORE.dmem_owner_valid_r;
    wire monitor_dmem_owner_store_w = `EDRV32_MON_CORE.dmem_owner_store_r;
`endif

    wire [1:0] monitor_retire_count_w = `EDRV32_MON_CORE.retire_count_o;
    wire monitor_second_retire_w = `EDRV32_MON_CORE.second_retire_o;
    wire [31:0] monitor_second_pc_w = `EDRV32_MON_CORE.second_retire_pc_o;
    wire [31:0] monitor_second_instr_w = `EDRV32_MON_CORE.second_retire_instr_o;
    wire [`EDRV32_PAIR_DECODE_W-1:0] monitor_decode_second_w = `EDRV32_MON_CORE.decode_second_w;
    wire [`EDRV32_PAIR_RESULT_W-1:0] monitor_ex_second_w = `EDRV32_MON_CORE.ex_second_w;
    wire [`EDRV32_PAIR_RESULT_W-1:0] monitor_mem1_second_w = `EDRV32_MON_CORE.mem1_second_w;
    wire [`EDRV32_PAIR_RESULT_W-1:0] monitor_commit_second_w = `EDRV32_MON_CORE.commit_second_w;
    reg [`EDRV32_PAIR_DECODE_W-1:0] prev_decode_second;
    reg [`EDRV32_PAIR_RESULT_W-1:0] prev_ex_second,prev_mem1_second,prev_commit_second;

`undef EDRV32_MON_CORE

`ifdef EDRV32_CACHED_TEST
    // Cacheable tohost stores in a write-back D$ need not reach the fabric
    // before program completion.  Observe the successfully completed COMMIT
    // packet while its formatted store metadata is still live.
    assign tohost_write_complete_w = retire &&
        u_core.u_cached_core.core_dmem_req_write_w;
    assign tohost_write_addr_w  =
        u_core.u_cached_core.core_dmem_req_addr_w;
    assign tohost_write_wstrb_w =
        u_core.u_cached_core.core_dmem_req_wstrb_w;
    assign tohost_write_data_w  =
        u_core.u_cached_core.core_dmem_req_wdata_w;
`else
    assign tohost_write_complete_w = dmem_req_valid && dmem_req_ready &&
                                      dmem_req_we;
    assign tohost_write_addr_w  = dmem_req_addr;
    assign tohost_write_wstrb_w = dmem_req_wstrb;
    assign tohost_write_data_w  = dmem_req_wdata;
`endif

    edrv32_mem_model #(
        .MEM_DEPTH_WORDS(65536), .BASE_ADDR(RESET_PC),
        .IMEM_LAT(0), .DMEM_LAT(0)
    ) u_mem (
        .clk(clk), .rst_n(rst_n),
        .imem_req_valid_i(imem_req_valid), .imem_req_ready_o(imem_req_ready),
        .imem_req_addr_i(imem_req_addr), .imem_resp_valid_o(imem_resp_valid),
        .imem_resp_ready_i(imem_resp_ready), .imem_resp_rdata_o(imem_resp_rdata),
        .imem_resp_error_o(imem_resp_error),
        .dmem_req_valid_i(dmem_req_valid), .dmem_req_ready_o(dmem_req_ready),
        .dmem_req_addr_i(dmem_req_addr), .dmem_req_we_i(dmem_req_we),
        .dmem_req_size_i(dmem_req_size), .dmem_req_wstrb_i(dmem_req_wstrb),
        .dmem_req_wdata_i(dmem_req_wdata), .dmem_resp_valid_o(dmem_resp_valid),
        .dmem_resp_ready_i(dmem_resp_ready), .dmem_resp_rdata_o(dmem_resp_rdata),
        .dmem_resp_error_o(dmem_resp_error),
        .imem_req_stall_i(1'b0), .dmem_req_stall_i(1'b0)
    );

    initial begin
        rst_n = 1'b0;
        time_value = 64'd0;
        cycles = 0;
        retires = 0;
        dual_retires = 0;
        traps = 0;
        quiet_cycles = 0;
        trace_enable = $test$plusargs("TRACE");
        monitor_armed = 1'b0;
        if (!$value$plusargs("TOHOST=%h", tohost_addr))
            tohost_addr = 32'h8000_1000;
        if (!$value$plusargs("MAX_CYCLES=%d", max_cycles))
            max_cycles = 2000000;
        repeat (5) @(posedge clk);
        rst_n = 1'b1;
    end

    // Pipeline-control contract monitors.  These are intentionally independent
    // of the test program: every held boundary must retain its identity and
    // payload until transfer or an age-qualified kill.
    always @(posedge clk) begin
        if (!rst_n) begin
            monitor_armed <= 1'b0;
        end else begin
            if (monitor_armed) begin
                if (prev_align_valid && !prev_align_accept && !prev_frontend_kill &&
                    (!monitor_align_valid_w ||
                     monitor_align_pc_w != prev_align_pc ||
                     monitor_align_instr_w != prev_align_instr))
                    $fatal(1, "ALIGN payload changed while stalled");
                if (prev_decode_valid && !prev_decode_accept &&
                    !prev_decode_to_ex_kill &&
                    (!monitor_decode_valid_w ||
                     monitor_decode_pc_w != prev_decode_pc ||
                     monitor_decode_instr_w != prev_decode_instr ||
                     monitor_decode_rd_w != prev_decode_rd))
                    $fatal(1, "DECODE payload changed while stalled");
                if (prev_ex_valid && !prev_ex_accept && !prev_commit_kill &&
                    (!monitor_ex_valid_w || monitor_ex_pc_w != prev_ex_pc ||
                     monitor_ex_instr_w != prev_ex_instr ||
                     monitor_ex_rd_w != prev_ex_rd ||
                     monitor_ex_result_w != prev_ex_result))
                    $fatal(1, "EX payload changed while stalled");
                if (prev_mem1_packet_valid && !prev_mem1_packet_accept && !prev_commit_kill &&
                    (!monitor_mem1_packet_valid_w ||
                     monitor_mem1_packet_pc_w != prev_mem1_packet_pc ||
                     monitor_mem1_packet_instr_w != prev_mem1_packet_instr ||
                     monitor_mem1_packet_rd_w != prev_mem1_packet_rd ||
                     monitor_mem1_packet_result_w != prev_mem1_packet_result))
                    $fatal(1, "MEM1 packet changed while stalled");
                if (prev_mem2_packet_valid && !prev_mem2_packet_accept && !prev_commit_kill &&
                    (!monitor_mem2_packet_valid_w ||
                     monitor_mem2_packet_pc_w != prev_mem2_packet_pc ||
                     monitor_mem2_packet_instr_w != prev_mem2_packet_instr ||
                     monitor_mem2_packet_rd_w != prev_mem2_packet_rd ||
                     monitor_mem2_packet_result_w != prev_mem2_packet_result))
                    $fatal(1, "MEM2 packet changed while stalled");
            end

            if (monitor_if2_count_w > ((FETCH_WIDE!=0)?4'd12:4'd6))
                $fatal(1, "IF_BUF occupancy exceeded capacity");
            if (monitor_mem1_packet_count_w > 2'd2)
                $fatal(1, "MEM1-to-MEM2 occupancy exceeded capacity");
            if (monitor_dmem_req_valid_w && !monitor_mem2_packet_valid_w &&
                !monitor_store_drain_w)
                $fatal(1, "ghost data-memory request without COMMIT input");
            if (retire && !monitor_mem2_packet_valid_w)
                $fatal(1, "ghost retire without COMMIT input");

            if(monitor_armed && prev_decode_valid && !prev_decode_accept && !prev_decode_to_ex_kill &&
                monitor_decode_second_w !== prev_decode_second)$fatal(1,"decode B changed while parent stalled");
            prev_decode_second <= monitor_decode_second_w;
            if(monitor_armed && prev_ex_valid && !prev_ex_accept && !prev_commit_kill &&
                monitor_ex_second_w !== prev_ex_second)$fatal(1,"ex B changed while parent stalled");
            prev_ex_second <= monitor_ex_second_w;
            if(monitor_armed && prev_mem1_packet_valid && !prev_mem1_packet_accept && !prev_commit_kill &&
                monitor_mem1_second_w !== prev_mem1_second)$fatal(1,"mem1 B changed while parent stalled");
            prev_mem1_second <= monitor_mem1_second_w;
            if(monitor_armed && prev_mem2_packet_valid && !prev_mem2_packet_accept && !prev_commit_kill &&
                monitor_commit_second_w !== prev_commit_second)$fatal(1,"commit B changed while parent stalled");
            prev_commit_second <= monitor_commit_second_w;
            monitor_armed <= 1'b1;
            prev_frontend_kill <= monitor_frontend_kill_w;
            prev_decode_to_ex_kill <= monitor_decode_to_ex_kill_w;
            prev_commit_kill <= monitor_commit_kill_w;
            prev_align_valid <= monitor_align_valid_w;
            prev_align_accept <= monitor_align_accept_w;
            prev_align_pc <= monitor_align_pc_w;
            prev_align_instr <= monitor_align_instr_w;
            prev_decode_valid <= monitor_decode_valid_w;
            prev_decode_accept <= monitor_decode_accept_w;
            prev_decode_pc <= monitor_decode_pc_w;
            prev_decode_instr <= monitor_decode_instr_w;
            prev_decode_rd <= monitor_decode_rd_w;
            prev_ex_valid <= monitor_ex_valid_w;
            prev_ex_accept <= monitor_ex_accept_w;
            prev_ex_pc <= monitor_ex_pc_w;
            prev_ex_instr <= monitor_ex_instr_w;
            prev_ex_rd <= monitor_ex_rd_w;
            prev_ex_result <= monitor_ex_result_w;
            prev_mem1_packet_valid <= monitor_mem1_packet_valid_w;
            prev_mem1_packet_accept <= monitor_mem1_packet_accept_w;
            prev_mem1_packet_pc <= monitor_mem1_packet_pc_w;
            prev_mem1_packet_instr <= monitor_mem1_packet_instr_w;
            prev_mem1_packet_rd <= monitor_mem1_packet_rd_w;
            prev_mem1_packet_result <= monitor_mem1_packet_result_w;
            prev_mem2_packet_valid <= monitor_mem2_packet_valid_w;
            prev_mem2_packet_accept <= monitor_mem2_packet_accept_w;
            prev_mem2_packet_pc <= monitor_mem2_packet_pc_w;
            prev_mem2_packet_instr <= monitor_mem2_packet_instr_w;
            prev_mem2_packet_rd <= monitor_mem2_packet_rd_w;
            prev_mem2_packet_result <= monitor_mem2_packet_result_w;
        end
    end

    always @(posedge clk) begin
        if (rst_n) begin
            time_value <= time_value + 64'd1;
            cycles <= cycles + 1;
            if (retire) retires <= retires + monitor_retire_count_w;
            if (monitor_second_retire_w) dual_retires <= dual_retires + 1;
            if (monitor_second_retire_w && !retire)$fatal(1,"B retirement without A");
            if (trap) traps <= traps + 1;
            if (trace_enable && retire)
                $display("TRACE_RETIRE cycle=%0d pc=%08x instr=%08x",
                         cycles, retire_pc, retire_instr);
            if (trace_enable && monitor_second_retire_w)
                $display("TRACE_RETIRE_B cycle=%0d pc=%08x instr=%08x",cycles,monitor_second_pc_w,monitor_second_instr_w);
            if (trace_enable && trap)
                $display("TRACE_TRAP cycle=%0d pc=%08x cause=%08x",
                         cycles, retire_pc, trap_cause);
            if (trace_enable && dmem_req_valid && dmem_req_ready)
                $display("TRACE_DMEM cycle=%0d we=%b addr=%08x strb=%x data=%08x",
                         cycles, dmem_req_we, dmem_req_addr,
                         dmem_req_wstrb, dmem_req_wdata);
`ifndef EDRV32_CACHED_TEST
            if (trace_enable && u_core.commit_gpr_write_w)
                $display("TRACE_GPR cycle=%0d rd=%0d data=%08x",
                         cycles, u_core.commit_gpr_rd_w,
                         u_core.commit_gpr_value_w);
            if (trace_enable && u_core.fetch_block_valid_w &&
                u_core.fetch_block_ready_w)
                $display("TRACE_IF_BLOCK cycle=%0d addr=%08x data=%08x epoch=%0d match=%b count=%0d expected=%08x",
                         cycles, u_core.fetch_block_addr_w,
                         u_core.fetch_block_data_w, u_core.fetch_block_epoch_w,
                         u_core.u_if2_stage.block_matches_w,
                         u_core.u_if2_stage.count_r,
                         u_core.u_if2_stage.expected_block_addr_r);
            if (trace_enable && u_core.u_if2_stage.candidate_accept_w)
                $display("TRACE_ALIGN_IN cycle=%0d pc=%08x h0=%04x h1=%04x count=%0d",
                         cycles, u_core.fetch_window_pc_w,
                         u_core.fetch_halfword0_w, u_core.fetch_halfword1_w,
                         u_core.u_if2_stage.count_r);
`else
            if (trace_enable &&
                u_core.u_cached_core.u_core.commit_gpr_write_w)
                $display("TRACE_GPR cycle=%0d rd=%0d data=%08x",
                         cycles,
                         u_core.u_cached_core.u_core.commit_gpr_rd_w,
                         u_core.u_cached_core.u_core.commit_gpr_value_w);
            if (trace_enable &&
                u_core.u_cached_core.dcache_lookup_resp_valid_w &&
                u_core.u_cached_core.dcache_lookup_resp_ready_w)
                $display("TRACE_DCACHE_LOOKUP cycle=%0d addr=%08x data=%08x error=%b",
                         cycles, u_core.u_cached_core.dcache_lookup_addr_w,
                         u_core.u_cached_core.dcache_lookup_resp_data_w,
                         u_core.u_cached_core.dcache_lookup_resp_error_w);
            if (trace_enable &&
                (u_core.u_cached_core.u_core.store_prepare_valid_w ||
                 u_core.u_cached_core.u_core.store_commit_valid_w ||
                 u_core.u_cached_core.u_core.store_drain_valid_w ||
                 u_core.u_cached_core.u_core.commit_flush_younger_lsu_w ||
                 u_core.u_cached_core.dcache_lookup_cancel_w))
                $display("TRACE_LSU cycle=%0d cpc=%08x prep=%b%b presp=%b commit=%b%b%b drain=%b%b sqv=%b sqc=%b state=%0d resv=%b cancel=%b fflush=%b",
                         cycles,
                         u_core.u_cached_core.u_core.mem2_packet_pc_w,
                         u_core.u_cached_core.u_core.store_prepare_valid_w,
                         u_core.u_cached_core.u_core.store_prepare_ready_w,
                         u_core.u_cached_core.u_core.u_store_queue.prepare_response_valid_i,
                         u_core.u_cached_core.u_core.store_commit_valid_w,
                         u_core.u_cached_core.u_core.store_commit_ready_w,
                         u_core.u_cached_core.u_core.store_commit_fire_w,
                         u_core.u_cached_core.u_core.store_drain_valid_w,
                         u_core.u_cached_core.u_core.store_drain_ready_w,
                         u_core.u_cached_core.u_core.u_store_queue.valid_r,
                         u_core.u_cached_core.u_core.u_store_queue.committed_count_r,
                         u_core.u_cached_core.u_dcache.state_r,
                         u_core.u_cached_core.u_dcache.store_reservation_valid_w,
                         u_core.u_cached_core.dcache_lookup_cancel_w,
                         u_core.u_cached_core.u_core.commit_flush_younger_lsu_w);
`endif
            if (retire || trap || (imem_req_valid && imem_req_ready) ||
                (dmem_req_valid && dmem_req_ready))
                quiet_cycles <= 0;
            else
                quiet_cycles <= quiet_cycles + 1;

            if (tohost_write_complete_w &&
                (tohost_write_addr_w == tohost_addr)) begin
                if (tohost_write_wstrb_w != 4'b1111)
                    $fatal(1, "EDRV32_TEST_FAIL tohost strobe=%x",
                           tohost_write_wstrb_w);
                // riscv-tests: 1=PASS, odd values encode failure test number.
                // ACT4 self-check ELFs: an even completion value is PASS.
                if ((tohost_write_data_w == 32'd1) ||
                    (ACT_SELF_CHECK != 0 && !tohost_write_data_w[0])) begin
                    $display("EDRV32_TEST_PASS cycles=%0d retires=%0d traps=%0d dual=%0d tohost=%08x",
                             cycles, retires, traps, dual_retires, tohost_write_data_w);
                    $finish;
                end else begin
                    $fatal(1, "EDRV32_TEST_FAIL tohost=%08x cycles=%0d pc=%08x",
                           tohost_write_data_w, cycles, retire_pc);
                end
            end
            if (quiet_cycles > 20000) begin
`ifdef EDRV32_CACHED_TEST
                $display("LSU_STUCK lq_empty=%b sq_valid=%b sq_committed=%b drain_vr=%b%b owner=%b%b dcache_state=%0d resv=%b",
                         monitor_load_queue_empty_w,
                         monitor_store_valid_w,
                         monitor_store_committed_w,
                         monitor_store_drain_valid_w,
                         monitor_store_drain_ready_w,
                         monitor_dmem_owner_valid_w,
                         monitor_dmem_owner_store_w,
                         u_core.u_cached_core.u_dcache.state_r,
                         u_core.u_cached_core.u_dcache.store_reservation_valid_w);
`endif
                $fatal(1, "EDRV32_TEST_FAIL no progress cycles=%0d pc=%08x instr=%08x",
                       cycles, retire_pc, retire_instr);
            end
            if (cycles > max_cycles)
                $fatal(1, "EDRV32_TEST_FAIL timeout cycles=%0d retires=%0d pc=%08x",
                       cycles, retires, retire_pc);
        end
    end
endmodule
