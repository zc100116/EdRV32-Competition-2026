`timescale 1ns/1ps
`include "edrv32_bus.vh"
`include "edrv32_uop.vh"

// Queued LSU acceptance test: Store forwarding, COMMIT throughput, and
// load-use recovery with the single cacheable-memory implementation.
module tb_lsu_early_lookup;
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
    wire retire_exception;
    wire [31:0] retire_cause;

    integer cycles;
    integer retires;
    integer commit_backpressure;
    integer load1_retire_cycle;
    integer consumer1_retire_cycle;
    integer load2_retire_cycle;
    integer consumer2_retire_cycle;
    reg final_store_fired;
    integer final_wait;

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
        commit_backpressure = 0;
        load1_retire_cycle = -1;
        consumer1_retire_cycle = -1;
        load2_retire_cycle = -1;
        consumer2_retire_cycle = -1;
        final_store_fired = 1'b0;
        final_wait = 0;

        // 0: lui x10,0x80000  1: lw x5,(x10) miss+refill  2: addi x6,x5,1
        // 3: lw x7,(x10) hit  4: addi x8,x7,2  5: sw x8,(x10)
        // 6: sw x6,4(x10)  7: lw x9,(x10) forwarded  8: addi x11,x9,1
        // 9: sw x11,(x10) final  10: jal x0,0
        u_mem.mem[0]  = 32'h8000_0537;
        u_mem.mem[1]  = enc_i(12'd0, 5'd10, 3'b010, 5'd5, 7'h03);
        u_mem.mem[2]  = enc_i(12'd1, 5'd5, 3'b000, 5'd6, 7'h13);
        u_mem.mem[3]  = enc_i(12'd0, 5'd10, 3'b010, 5'd7, 7'h03);
        u_mem.mem[4]  = enc_i(12'd2, 5'd7, 3'b000, 5'd8, 7'h13);
        u_mem.mem[5]  = enc_s(12'd0, 5'd8, 5'd10, 3'b010);
        u_mem.mem[6]  = enc_s(12'd4, 5'd6, 5'd10, 3'b010);
        u_mem.mem[7]  = enc_i(12'd0, 5'd10, 3'b010, 5'd9, 7'h03);
        u_mem.mem[8]  = enc_i(12'd1, 5'd9, 3'b000, 5'd11, 7'h13);
        u_mem.mem[9]  = enc_s(12'd0, 5'd11, 5'd10, 3'b010);
        u_mem.mem[10] = enc_j(21'd0, 5'd0);

        repeat (4) @(posedge clk);
        rst_n = 1'b1;
    end

    always @(posedge clk) begin
        if (rst_n) begin
            cycles = cycles + 1;
            if (retire) retires = retires + 1;
            if (retire && (retire_pc == RESET_PC + 32'd4))
                load1_retire_cycle = cycles;
            if (retire && (retire_pc == RESET_PC + 32'd8))
                consumer1_retire_cycle = cycles;
            if (retire && (retire_pc == RESET_PC + 32'd12))
                load2_retire_cycle = cycles;
            if (retire && (retire_pc == RESET_PC + 32'd16))
                consumer2_retire_cycle = cycles;
            if (retire_exception)
                $fatal(1, "unexpected exception pc=%08x cause=%08x",
                       retire_pc, retire_cause);
            if (u_core.u_cached_core.u_core.mem2_packet_valid_w &&
                !u_core.u_cached_core.u_core.mem2_packet_accept_w &&
                (u_core.u_cached_core.u_core.mem2_packet_op_class_w ==
                 `EDRV32_OP_STORE))
                commit_backpressure = commit_backpressure + 1;
            if (retire && (retire_pc == RESET_PC + 32'd36))
                final_store_fired = 1'b1;
            if (final_store_fired) begin
                final_wait = final_wait + 1;
                if (final_wait == 4) begin
                    // word0 = x8 = x5+2 after the first store, loaded by the
                    // store-buffer-forwarded load, then x11 = x9+1 = x5+3.
                    if (u_core.u_cached_core.u_core.u_decode_stage.u_regfile.regs_r[11] !==
                        u_core.u_cached_core.u_core.u_decode_stage.u_regfile.regs_r[5] +
                        32'd3)
                        $fatal(1, "store buffer forward produced wrong x11=%08x",
                               u_core.u_cached_core.u_core.u_decode_stage.u_regfile.regs_r[11]);
                    if (commit_backpressure >= 3)
                        $fatal(1, "queued Store wait %0d did not improve",
                               commit_backpressure);
                    if ((load2_retire_cycle < 0) ||
                        (consumer2_retire_cycle < 0))
                        $fatal(1, "second load-use retirement markers missing");
                    // The consumer now soft-releases beside the EX producer
                    // and observes the exact LQ entry in EX. A warm hit keeps
                    // one unavoidable data-availability gap, giving a
                    // two-cycle retirement distance for this pair.
                    if ((consumer2_retire_cycle - load2_retire_cycle) != 2)
                        $fatal(1, "cached-hit load-use gap is %0d, want 2",
                               consumer2_retire_cycle - load2_retire_cycle);
                    $display("PASS: queued LSU: commit_bp=%0d gap=%0d",
                             commit_backpressure,
                             consumer2_retire_cycle - load2_retire_cycle);
                    $display("PASS: queued LSU cycles=%0d retires=%0d",
                             cycles, retires);
                    $finish;
                end
            end
            if (cycles > 4000) begin
                $fatal(1, "lsu early lookup timeout retires=%0d pc=%08x",
                       retires, retire_pc);
            end
        end
    end

endmodule
