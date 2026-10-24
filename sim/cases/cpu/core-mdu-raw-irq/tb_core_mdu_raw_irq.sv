`timescale 1ns/1ps
`include "edrv32_bus.vh"
`include "edrv32_csr.vh"

// Cancel a speculative MDU and its early EX consumer, replay with new
// operands, then overwrite and reuse the same destination register.
module tb_core_mdu_raw_irq #(parameter FRONTEND_DUAL_WINDOW=0, parameter DUAL_ISSUE=0, parameter FETCH_WIDE=0);
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
    integer cycles;
    integer trap_count;
    reg [31:0] interrupted_pc=0;
    integer cancel_count;
    integer killed_consumer_count;
    integer writeback_count;
    reg irq_sent;
    reg irq_ext;

    function automatic [31:0] enc_i;
        input [11:0] imm;
        input [4:0] rs1;
        input [2:0] funct3;
        input [4:0] rd;
        input [6:0] opcode;
        begin enc_i = {imm, rs1, funct3, rd, opcode}; end
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

    edrv32_cached_core_native_harness #(
        .RESET_PC(RESET_PC), .FRONTEND_DUAL_WINDOW(FRONTEND_DUAL_WINDOW), .DUAL_ISSUE(DUAL_ISSUE), .FETCH_WIDE(FETCH_WIDE), .ICACHE_LINE_COUNT(16), .DCACHE_LINE_COUNT(16)
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
        .irq_soft_i(1'b0), .irq_timer_i(1'b0), .irq_ext_i(irq_ext),
        .time_value_i(64'd0),
        .retire_o(retire), .retire_pc_o(retire_pc),
        .retire_instr_o(retire_instr), .retire_exception_o(trap),
        .retire_cause_o(trap_cause),
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

    function automatic [31:0] enc_csr;
        input [11:0] csr; input [4:0] rs1; input [2:0] funct3; input [4:0] rd;
        begin enc_csr = {csr, rs1, funct3, rd, 7'h73}; end
    endfunction
    function automatic [31:0] enc_s;
        input [11:0] imm; input [4:0] rs2; input [4:0] rs1; input [2:0] funct3;
        begin enc_s = {imm[11:5], rs2, rs1, funct3, imm[4:0], 7'h23}; end
    endfunction
    `define C u_core.u_cached_core.u_core
    integer killed_tagged_count;
    `ifdef EDRV32_TEST_MDU_IRQ_HIGH
    localparam HIGH = 1;
    `else
    localparam HIGH = 0;
    `endif
    function automatic [31:0] enc_r;
        input [4:0] rs2; input [4:0] rs1; input [4:0] rd; input [2:0] operation;
        begin enc_r = {7'h01, rs2, rs1, operation, rd, 7'h33}; end
    endfunction

    initial begin
        rst_n = 1'b0;
        irq_ext = 1'b0;
        irq_sent = 1'b0;
        cycles = 0;
        trap_count = 0;
        cancel_count = 0;
        killed_consumer_count = 0;
        killed_tagged_count = 0;
        writeback_count = 0;
        u_mem.mem[0] = 32'h8000_0237;
        u_mem.mem[1] = enc_i(12'h080, 5'd4, 3'b000, 5'd1, 7'h13);
        u_mem.mem[2] = enc_csr(`EDRV32_CSR_MTVEC, 5'd1, 3'b001, 5'd0);
        u_mem.mem[3] = 32'h0000_1137;
        u_mem.mem[4] = enc_i(12'h800, 5'd2, 3'b000, 5'd2, 7'h13);
        u_mem.mem[5] = enc_csr(`EDRV32_CSR_MIE, 5'd2, 3'b001, 5'd0);
        u_mem.mem[6] = enc_i(12'd8, 5'd0, 3'b000, 5'd2, 7'h13);
        u_mem.mem[7] = enc_csr(`EDRV32_CSR_MSTATUS, 5'd2, 3'b001, 5'd0);
        u_mem.mem[8] = HIGH ? 32'h1000_00b7 : enc_i(12'd7, 5'd0, 3'b000, 5'd1, 7'h13);
        u_mem.mem[9] = enc_i(HIGH ? 12'd16 : 12'd9, 5'd0, 3'b000, 5'd2, 7'h13);
        u_mem.mem[10] = enc_r(5'd2, 5'd1, 5'd3, HIGH ? 3'b011 : 3'b000);
        u_mem.mem[11] = enc_i(12'd1, 5'd3, 3'b000, 5'd5, 7'h13);
        u_mem.mem[12] = enc_i(12'd123, 5'd0, 3'b000, 5'd3, 7'h13);
        u_mem.mem[13] = enc_i(12'd1, 5'd3, 3'b000, 5'd6, 7'h13);
        u_mem.mem[14] = enc_r(5'd2, 5'd2, 5'd3, 3'b000); // same rd, new generation
        u_mem.mem[15] = enc_i(12'd1, 5'd3, 3'b000, 5'd7, 7'h13);
        u_mem.mem[16] = enc_i(12'd1, 5'd0, 3'b000, 5'd12, 7'h13);
        u_mem.mem[17] = enc_s(12'h104, 5'd12, 5'd4, 3'b010);
        u_mem.mem[18] = enc_j(21'd0, 5'd0);
        u_mem.mem[32] = enc_csr(`EDRV32_CSR_MCAUSE, 5'd0, 3'b010, 5'd18);
        u_mem.mem[33] = HIGH ? 32'h2000_00b7 : enc_i(12'd11, 5'd0, 3'b000, 5'd1, 7'h13);
        u_mem.mem[34] = 32'h3020_0073;
        repeat (4) @(posedge clk);
        @(negedge clk); rst_n = 1'b1;
    end

    always @(posedge clk) begin
        if (rst_n) begin
            cycles <= cycles + 1;
            if (`C.mdu_req_fire_w && !irq_sent) begin
                irq_ext <= 1'b1;
                irq_sent <= 1'b1;
            end
            if (`C.mdu_cancel_w) begin
                if (!HIGH && !`C.mdu_result_complete_w)
                    $fatal(1, "two-stage MUL must be complete at this IRQ boundary");
                cancel_count <= cancel_count + 1;
                if (`C.decode_valid_w && `C.decode_pc_w == RESET_PC + 32'd44)
                    killed_consumer_count <= killed_consumer_count + 1;
                if (`C.decode_valid_w &&
                    (`C.decode_late_mdu_rs1_w || `C.decode_late_mdu_rs2_w))
                    killed_tagged_count <= killed_tagged_count + 1;
            end
            if (`C.mdu_writeback_fire_w)
                writeback_count <= writeback_count + 1;
            if (trap) begin
                trap_count <= trap_count + 1;
                interrupted_pc <= retire_pc;
                irq_ext <= 1'b0;
                if (trap_cause != `EDRV32_CAUSE_INT_M_EXT ||
                    retire_pc < RESET_PC + ((FETCH_WIDE!=0)?32'd32:32'd36))
                    $fatal(1, "wrong IRQ cause/epc cause=%08x pc=%08x", trap_cause, retire_pc);
            end
            if (retire && retire_pc == RESET_PC + 32'd68) begin
                if (trap_count != 1 || cancel_count != 1 ||
                    writeback_count != 2 ||
                    (HIGH && (killed_consumer_count != 1 || killed_tagged_count != 1)) ||
                    `C.u_decode_stage.u_regfile.regs_r[5] != (HIGH ? ((interrupted_pc<=RESET_PC+32)?2:3)
                        : ((interrupted_pc<=RESET_PC+32)?64:100)) ||
                    `C.u_decode_stage.u_regfile.regs_r[6] != 124 ||
                    `C.u_decode_stage.u_regfile.regs_r[7] != (HIGH ? 257 : 82))
                    $fatal(1, "MDU IRQ replay failed traps=%0d cancels=%0d killed=%0d wb=%0d x5=%0d x6=%0d x7=%0d",
                           trap_count, cancel_count, killed_consumer_count, writeback_count,
                           `C.u_decode_stage.u_regfile.regs_r[5],
                           `C.u_decode_stage.u_regfile.regs_r[6],
                           `C.u_decode_stage.u_regfile.regs_r[7]);
                $display("PASS: MDU early-consumer IRQ/replay cycles=%0d cancels=%0d killed=%0d wb=%0d",
                         cycles, cancel_count, killed_consumer_count, writeback_count);
                $finish;
            end
            if (cycles > 1800) $fatal(1, "MDU IRQ replay timeout");
        end
    end
`undef C
endmodule
