`timescale 1ns/1ps
`include "edrv32_bus.vh"

module tb_uncached_load_use;
    localparam [31:0] RESET_PC = 32'h8000_0000;

    reg clk;
    reg rst_n;
    wire imem_req_valid;
    wire imem_req_ready;
    wire [31:0] imem_req_addr;
    wire imem_resp_valid;
    wire imem_resp_ready;
    wire [31:0] imem_resp_rdata;
    wire imem_resp_error;
    wire dmem_req_valid;
    wire dmem_req_ready;
    wire [31:0] dmem_req_addr;
    wire dmem_req_we;
    wire [`BUS_SZ_W-1:0] dmem_req_size;
    wire [3:0] dmem_req_wstrb;
    wire [31:0] dmem_req_wdata;
    wire dmem_resp_valid;
    wire dmem_resp_ready;
    wire [31:0] dmem_resp_rdata;
    wire dmem_resp_error;
    wire retire;
    wire [31:0] retire_pc;
    wire retire_exception;
    wire [31:0] retire_cause;
    integer cycles;
    integer load_cycle;
    integer consumer_cycle;
    integer final_wait;

    function automatic [31:0] enc_i;
        input [11:0] imm;
        input [4:0] rs1;
        input [2:0] funct3;
        input [4:0] rd;
        input [6:0] opcode;
        begin enc_i = {imm, rs1, funct3, rd, opcode}; end
    endfunction

    function automatic [31:0] enc_j;
        input [20:0] imm;
        input [4:0] rd;
        begin enc_j = {imm[20], imm[10:1], imm[11], imm[19:12], rd, 7'h6f}; end
    endfunction

    initial clk = 1'b0;
    always #5 clk = ~clk;

    edrv32_cached_core_native_harness #(
        .RESET_PC(RESET_PC),
        .ICACHE_LINE_COUNT(16),
        .DCACHE_LINE_COUNT(16)
    ) u_core (
        .clk_i(clk), .rst_n_i(rst_n),
        .imem_req_valid_o(imem_req_valid),
        .imem_req_ready_i(imem_req_ready),
        .imem_req_addr_o(imem_req_addr),
        .imem_resp_valid_i(imem_resp_valid),
        .imem_resp_ready_o(imem_resp_ready),
        .imem_resp_rdata_i(imem_resp_rdata),
        .imem_resp_error_i(imem_resp_error),
        .dmem_req_valid_o(dmem_req_valid),
        .dmem_req_ready_i(dmem_req_ready),
        .dmem_req_addr_o(dmem_req_addr),
        .dmem_req_we_o(dmem_req_we),
        .dmem_req_size_o(dmem_req_size),
        .dmem_req_wstrb_o(dmem_req_wstrb),
        .dmem_req_wdata_o(dmem_req_wdata),
        .dmem_resp_valid_i(dmem_resp_valid),
        .dmem_resp_ready_o(dmem_resp_ready),
        .dmem_resp_rdata_i(dmem_resp_rdata),
        .dmem_resp_error_i(dmem_resp_error),
        .itcm_req_valid_o(), .itcm_req_ready_i(1'b0),
        .itcm_req_addr_o(), .itcm_resp_valid_i(1'b0),
        .itcm_resp_ready_o(), .itcm_resp_rdata_i(32'd0),
        .itcm_resp_error_i(1'b0),
        .dtcm_req_valid_o(), .dtcm_req_ready_i(1'b0),
        .dtcm_req_addr_o(), .dtcm_req_we_o(), .dtcm_req_size_o(),
        .dtcm_req_wstrb_o(), .dtcm_req_wdata_o(),
        .dtcm_resp_valid_i(1'b0), .dtcm_resp_ready_o(),
        .dtcm_resp_rdata_i(32'd0), .dtcm_resp_error_i(1'b0),
        .irq_soft_i(1'b0), .irq_timer_i(1'b0), .irq_ext_i(1'b0),
        .time_value_i(64'd0),
        .retire_o(retire), .retire_pc_o(retire_pc), .retire_instr_o(),
        .retire_exception_o(retire_exception),
        .retire_cause_o(retire_cause),
        .debug_decode_instr_o(), .debug_decode_pc_o(), .core_sleep_o()
    );

    edrv32_mem_model #(
        .MEM_DEPTH_WORDS(1024),
        .BASE_ADDR(RESET_PC),
        .IMEM_LAT(1),
        .DMEM_LAT(2),
        .DEBUG_IO_EN(1),
        .DEBUG_IO_BASE(32'h4000_0000)
    ) u_mem (
        .clk(clk), .rst_n(rst_n),
        .imem_req_valid_i(imem_req_valid),
        .imem_req_ready_o(imem_req_ready),
        .imem_req_addr_i(imem_req_addr),
        .imem_resp_valid_o(imem_resp_valid),
        .imem_resp_ready_i(imem_resp_ready),
        .imem_resp_rdata_o(imem_resp_rdata),
        .imem_resp_error_o(imem_resp_error),
        .dmem_req_valid_i(dmem_req_valid),
        .dmem_req_ready_o(dmem_req_ready),
        .dmem_req_addr_i(dmem_req_addr),
        .dmem_req_we_i(dmem_req_we),
        .dmem_req_size_i(dmem_req_size),
        .dmem_req_wstrb_i(dmem_req_wstrb),
        .dmem_req_wdata_i(dmem_req_wdata),
        .dmem_resp_valid_o(dmem_resp_valid),
        .dmem_resp_ready_i(dmem_resp_ready),
        .dmem_resp_rdata_o(dmem_resp_rdata),
        .dmem_resp_error_o(dmem_resp_error),
        .imem_req_stall_i(1'b0), .dmem_req_stall_i(1'b0)
    );

    initial begin
        rst_n = 1'b0;
        cycles = 0;
        load_cycle = -1;
        consumer_cycle = -1;
        final_wait = 0;
        u_mem.mem[0] = {20'h40000, 5'd10, 7'h37};
        u_mem.mem[1] = enc_i(12'd0, 5'd10, 3'b010, 5'd5, 7'h03);
        u_mem.mem[2] = enc_i(12'd7, 5'd5, 3'b000, 5'd6, 7'h13);
        u_mem.mem[3] = enc_j(21'd0, 5'd0);
        repeat (4) @(posedge clk);
        rst_n = 1'b1;
    end

    always @(posedge clk) begin
        if (rst_n) begin
            cycles = cycles + 1;
            if (retire_exception)
                $fatal(1, "unexpected exception pc=%08x cause=%08x",
                       retire_pc, retire_cause);
            if (retire && retire_pc == RESET_PC + 32'd4)
                load_cycle = cycles;
            if (retire && retire_pc == RESET_PC + 32'd8) begin
                consumer_cycle = cycles;
                final_wait = 1;
            end else if (final_wait != 0) begin
                final_wait = final_wait + 1;
            end
            if (final_wait == 2) begin
                if (u_core.u_cached_core.u_core.u_decode_stage.u_regfile.regs_r[6]
                    !== 32'd7)
                    $fatal(1, "uncached Load consumer used stale value x6=%08x",
                           u_core.u_cached_core.u_core.u_decode_stage.u_regfile.regs_r[6]);
                $display("PASS: uncached Load completion reaches resident EX gap=%0d cycles=%0d",
                         consumer_cycle - load_cycle, cycles);
                $finish;
            end
            if (cycles > 300)
                $fatal(1, "uncached Load-use timeout");
        end
    end
endmodule
