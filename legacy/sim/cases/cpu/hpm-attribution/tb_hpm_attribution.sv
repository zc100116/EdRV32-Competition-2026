`timescale 1ns/1ps
`include "edrv32_bus.vh"
`include "edrv32_hpm.vh"

module tb_hpm_attribution;
    localparam [31:0] RESET_PC = 32'h8000_0000;
    localparam [31:0] TOHOST_ADDR = 32'h8000_0000;

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

    integer cycles;
    integer retires;
    integer empty_retires;
    integer dep_stalls;
    // One count per attribution event 41..56 (indexed 0..15).
    integer attr_cnt[0:15];
    integer gap_cnt[0:4];
    integer matrix_cnt[0:15];
    integer fe_cnt[0:5];
    integer index;

    function automatic [31:0] enc_i;
        input [11:0] imm;
        input [4:0] rs1;
        input [2:0] funct3;
        input [4:0] rd;
        input [6:0] opcode;
        begin enc_i = {imm, rs1, funct3, rd, opcode}; end
    endfunction

    function automatic [31:0] enc_r;
        input [6:0] funct7;
        input [4:0] rs2;
        input [4:0] rs1;
        input [2:0] funct3;
        input [4:0] rd;
        input [6:0] opcode;
        begin enc_r = {funct7, rs2, rs1, funct3, rd, opcode}; end
    endfunction

    function automatic [31:0] enc_s;
        input [11:0] imm;
        input [4:0] rs2;
        input [4:0] rs1;
        input [2:0] funct3;
        begin enc_s = {imm[11:5], rs2, rs1, funct3, imm[4:0], 7'h23}; end
    endfunction

    function automatic [31:0] enc_b;
        input [12:0] imm;
        input [4:0] rs2;
        input [4:0] rs1;
        input [2:0] funct3;
        begin
            enc_b = {imm[12], imm[10:5], rs2, rs1, funct3,
                     imm[4:1], imm[11], 7'h63};
        end
    endfunction

    function automatic [31:0] enc_j;
        input [20:0] imm;
        input [4:0] rd;
        begin enc_j = {imm[20], imm[10:1], imm[11], imm[19:12], rd, 7'h6f}; end
    endfunction

    initial clk = 1'b0;
    always #5 clk = ~clk;

`ifdef EDRV32_CACHED_TEST
    edrv32_cached_core_native_harness #(
        .RESET_PC(RESET_PC), .ICACHE_LINE_COUNT(16), .DCACHE_LINE_COUNT(16)
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
        .time_value_i(64'd0),
        .retire_o(retire), .retire_pc_o(retire_pc), .retire_instr_o(retire_instr),
        .retire_exception_o(retire_exception), .retire_cause_o(retire_cause),
        .debug_decode_instr_o(), .debug_decode_pc_o(), .core_sleep_o()
    );
`else
    edrv32_core #(.RESET_PC(RESET_PC)) u_core (
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
        .time_value_i(64'd0),
        .retire_o(retire), .retire_pc_o(retire_pc), .retire_instr_o(retire_instr),
        .retire_exception_o(retire_exception), .retire_cause_o(retire_cause),
        .fencei_retire_o()
    );
`endif

    edrv32_mem_model #(
        .MEM_DEPTH_WORDS(1024), .BASE_ADDR(RESET_PC),
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
        .dmem_req_wdata_i(dmem_req_wdata), .dmem_resp_valid_o(dmem_resp_valid),
        .dmem_resp_ready_i(dmem_resp_ready), .dmem_resp_rdata_o(dmem_resp_rdata),
        .dmem_resp_error_o(dmem_resp_error),
        .imem_req_stall_i(1'b0), .dmem_req_stall_i(1'b0)
    );

    initial begin
        rst_n = 1'b0;
        cycles = 0;
        retires = 0;
        empty_retires = 0;
        dep_stalls = 0;
        for (index = 0; index < 16; index = index + 1) begin
            attr_cnt[index] = 0;
            matrix_cnt[index] = 0;
        end
        for (index = 0; index < 5; index = index + 1) gap_cnt[index] = 0;
        for (index = 0; index < 6; index = index + 1) fe_cnt[index] = 0;

        u_mem.mem[0]  = enc_i(12'd1, 5'd0, 3'b000, 5'd1, 7'h13);  // x1=1
        u_mem.mem[1]  = enc_i(12'd1, 5'd1, 3'b000, 5'd2, 7'h13);  // x2=2 RAW
        u_mem.mem[2]  = enc_i(12'd1, 5'd2, 3'b000, 5'd3, 7'h13);  // x3=3 RAW
        u_mem.mem[3]  = enc_i(12'd1, 5'd3, 3'b000, 5'd4, 7'h13);  // x4=4 RAW
        u_mem.mem[4]  = 32'h8000_0537;                             // lui x10
        u_mem.mem[5]  = enc_s(12'd0, 5'd4, 5'd10, 3'b010);        // sw x4,(x10)
        u_mem.mem[6]  = enc_i(12'd3, 5'd0, 3'b000, 5'd7, 7'h13);  // x7=3
        u_mem.mem[7]  = enc_i(12'd33, 5'd0, 3'b000, 5'd8, 7'h13); // x8=33
        u_mem.mem[8]  = enc_r(7'h01, 5'd7, 5'd8, 3'b100, 5'd9, 7'h33); // div
        u_mem.mem[9]  = enc_i(12'd1, 5'd9, 3'b000, 5'd11, 7'h13); // MDU RAW
        u_mem.mem[10] = enc_i(12'd3, 5'd0, 3'b000, 5'd12, 7'h13); // loop cnt
        u_mem.mem[11] = enc_i(12'd0, 5'd10, 3'b010, 5'd5, 7'h03); // lw x5,(x10)
        u_mem.mem[12] = enc_i(12'd1, 5'd5, 3'b000, 5'd6, 7'h13);  // x6 load-use
        u_mem.mem[13] = enc_i(12'hFFF, 5'd12, 3'b000, 5'd12, 7'h13); // dec
        u_mem.mem[14] = enc_b(13'h1FF4, 5'd0, 5'd12, 3'b001);     // bne -12
        u_mem.mem[15] = enc_s(12'd0, 5'd11, 5'd10, 3'b010);       // sw result
        u_mem.mem[16] = enc_j(21'd0, 5'd0);                        // spin

        repeat (4) @(posedge clk);
        rst_n = 1'b1;
    end

    // One-hot and histogram checks run every cycle.
`ifdef EDRV32_CACHED_TEST
    wire [(`EDRV32_HPM_EVENT_W-40)-1:0] attr_events =
        u_core.u_cached_core.u_core.u_hpm_attribution.events_o;
    wire dep_stall_w =
        u_core.u_cached_core.u_core.decode_dependency_stall_w;
    wire resident_stall_w =
        u_core.u_cached_core.u_core.decode_hpm_stall_resident_w;
`else
    wire [(`EDRV32_HPM_EVENT_W-40)-1:0] attr_events =
        u_core.u_hpm_attribution.events_o;
    wire dep_stall_w = u_core.decode_dependency_stall_w;
    wire resident_stall_w = u_core.decode_hpm_stall_resident_w;
`endif
    reg [15:0] attr_bits;
    integer ones;
    integer idx;
    reg final_store_fired;
    integer final_wait;
    initial begin
        final_store_fired = 1'b0;
        final_wait = 0;
    end
    always @(posedge clk) begin
        if (rst_n) begin
            cycles = cycles + 1;
            attr_bits = attr_events[15:0];
            if (attr_bits[8] && !resident_stall_w)
                $fatal(1, "resident RAW attribution has no resident dependency");
            ones = 0;
            for (idx = 0; idx < 16; idx = idx + 1)
                if (attr_bits[idx]) ones = ones + 1;
            if (!retire && ones != 1)
                $fatal(1, "attribution not one-hot on empty retire, bits=%04x",
                       attr_bits);
            if (retire && ones != 0)
                $fatal(1, "attribution fired on retire cycle, bits=%04x",
                       attr_bits);
            for (idx = 0; idx < 16; idx = idx + 1)
                if (attr_bits[idx]) attr_cnt[idx] = attr_cnt[idx] + 1;
            for (idx = 0; idx < 5; idx = idx + 1)
                if (attr_events[16 + idx])
                    gap_cnt[idx] = gap_cnt[idx] + 1;
            for (idx = 0; idx < 16; idx = idx + 1)
                if (attr_events[21 + idx])
                    matrix_cnt[idx] = matrix_cnt[idx] + 1;
            for (idx = 0; idx < 6; idx = idx + 1)
                if (attr_events[37 + idx])
                    fe_cnt[idx] = fe_cnt[idx] + 1;
            if (retire) retires = retires + 1;
            if (!retire) empty_retires = empty_retires + 1;
            if (dep_stall_w) dep_stalls = dep_stalls + 1;
            if (retire_exception)
                $fatal(1, "unexpected exception pc=%08x cause=%08x",
                       retire_pc, retire_cause);
`ifdef EDRV32_CACHED_TEST
            if (retire && (retire_pc == RESET_PC + 32'd60))
                final_store_fired = 1'b1;
`else
            if (dmem_req_valid && dmem_req_ready && dmem_req_we &&
                (dmem_req_addr == TOHOST_ADDR) && (dmem_req_wdata == 32'd12))
                final_store_fired = 1'b1;
`endif
            if (final_store_fired) begin
                final_wait = final_wait + 1;
                if (final_wait == 4) begin
`ifdef EDRV32_CACHED_TEST
                    if (u_core.u_cached_core.u_core.u_decode_stage.u_regfile.regs_r[11]
                        !== 32'd12)
                        $fatal(1, "cached final result x11=%08x",
                               u_core.u_cached_core.u_core.u_decode_stage.u_regfile.regs_r[11]);
`else
                    if (u_mem.mem[0] != 32'd12)
                        $fatal(1, "final data word corrupted: %08x", u_mem.mem[0]);
`endif
                    // With early MDU issue, the deeper EX MDU wait can shadow
                    // every younger resident stall in this short program.
                    // Check any resident attribution causally above; require
                    // MDU coverage and all conservation identities below.
                    // RAW_LOAD is no longer required: with the late-load
                    // producer-PC release, load consumers soft-transfer from
                    // DECODE and the wait shows in the deeper COMMIT/MEM2
                    // buckets or in EX_LATE_LOAD instead.
                    if (attr_cnt[10] == 0)  // RAW_MDU
                        $fatal(1, "no MDU RAW attribution observed");
                    // EX_LATE_LOAD is a defensive bucket: an EX-side late-load
                    // wait is normally shadowed by the deeper COMMIT/MEM2 wait
                    // for the producer, so it is not required in this test.
`ifdef EDRV32_CACHED_TEST
                    // The decoupled MEM2 stage transports a token and does
                    // not own the cache transaction. A cold queued Load waits
                    // at architectural COMMIT, so it belongs to COMMIT_MEM;
                    // event 44 must no longer count a completed LQ token as a
                    // cache wait.
                    if (attr_cnt[0] == 0)   // COMMIT_MEM
                        $fatal(1, "no queued-Load COMMIT wait observed");
                    if (attr_cnt[12] == 0)  // FE_REDIRECT
                        $fatal(1, "no frontend redirect attribution observed");
`else
                    if (attr_cnt[0] == 0)   // COMMIT_MEM
                        $fatal(1, "no COMMIT memory attribution observed");
`endif
                    if (fe_cnt[4] == 0)     // FE_PRED_REDIRECT
                        $fatal(1, "no prediction redirect counted");
                    begin : check_sums
                        integer sum_attr;
                        integer sum_gap;
                        integer sum_matrix;
                        sum_attr = 0;
                        sum_gap = 0;
                        sum_matrix = 0;
                        for (idx = 0; idx < 16; idx = idx + 1)
                            sum_attr = sum_attr + attr_cnt[idx];
                        for (idx = 0; idx < 5; idx = idx + 1)
                            sum_gap = sum_gap + gap_cnt[idx];
                        for (idx = 0; idx < 16; idx = idx + 1)
                            sum_matrix = sum_matrix + matrix_cnt[idx];
                        if (sum_attr != empty_retires)
                            $fatal(1, "attribution sum %0d != empty retire %0d",
                                   sum_attr, empty_retires);
                        if (sum_gap != retires)
                            $fatal(1, "gap histogram sum %0d != retires %0d",
                                   sum_gap, retires);
                        if (sum_matrix != dep_stalls)
                            $fatal(1, "RAW matrix sum %0d != dep stalls %0d",
                                   sum_matrix, dep_stalls);
                        if ((fe_cnt[0] + 2 * fe_cnt[1]) <
                            (fe_cnt[2] + 2 * fe_cnt[3]))
                            $fatal(1, "appended halfwords fewer than consumed");
                        $display("PASS: attribution one-hot sum=%0d empty=%0d gap=%0d retires=%0d matrix=%0d dep=%0d",
                                 sum_attr, empty_retires, sum_gap, retires,
                                 sum_matrix, dep_stalls);
                        $display("PASS: hpm attribution cycles=%0d", cycles);
                        $finish;
                    end
                end
            end
            if (cycles > 4000) begin
                $fatal(1, "attribution timeout retires=%0d pc=%08x",
                       retires, retire_pc);
            end
        end
    end

endmodule
