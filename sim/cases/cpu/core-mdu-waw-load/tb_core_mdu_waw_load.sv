`timescale 1ns/1ps
`include "edrv32_bus.vh"
`include "edrv32_csr.vh"

// Keep a divider pending while younger writers replace its destination.
module tb_core_mdu_waw_load;
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
        .RESET_PC(RESET_PC), .ICACHE_LINE_COUNT(16), .DCACHE_LINE_COUNT(16)
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
        .retire_instr_o(retire_instr), .retire_exception_o(trap),
        .retire_cause_o(trap_cause),
        .debug_decode_instr_o(), .debug_decode_pc_o(), .core_sleep_o()
    );

    edrv32_mem_model #(
        .MEM_DEPTH_WORDS(4096), .BASE_ADDR(RESET_PC),
        .IMEM_LAT(1), .DMEM_LAT(20)
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

    `define C u_core.u_cached_core.u_core
    integer overlapping_alu;
    integer overlapping_load;
    integer pending_unready;
    integer mdu_writebacks;
    function automatic [31:0] enc_r;
        input [4:0] rs2; input [4:0] rs1; input [4:0] rd; input [2:0] operation;
        begin enc_r = {7'h01, rs2, rs1, operation, rd, 7'h33}; end
    endfunction
    function automatic [31:0] enc_add;
        input [4:0] rs2; input [4:0] rs1; input [4:0] rd;
        begin enc_add = {7'h00, rs2, rs1, 3'b000, rd, 7'h33}; end
    endfunction
    initial begin
        rst_n = 1'b0;
        cycles = 0;
        overlapping_alu = 0;
        overlapping_load = 0;
        pending_unready = 0;
        mdu_writebacks = 0;
        // DIVU uses full-width operands so it remains pending past COMMIT.
        u_mem.mem[0] = 32'h8000_0237; // data base x4
        u_mem.mem[1] = 32'h7fff_f0b7;
        u_mem.mem[2] = enc_i(12'hfff, 5'd1, 3'b000, 5'd1, 7'h13);
        u_mem.mem[3] = enc_i(12'd37, 5'd0, 3'b000, 5'd2, 7'h13);
        u_mem.mem[4] = enc_r(5'd2, 5'd1, 5'd3, 3'b101);
        u_mem.mem[5] = enc_i(12'd123, 5'd0, 3'b000, 5'd3, 7'h13);
        u_mem.mem[6] = enc_i(12'd1, 5'd3, 3'b000, 5'd5, 7'h13);
        u_mem.mem[7] = enc_add(5'd3, 5'd3, 5'd6);
        // Missed word load replaces the same pending destination; both ports
        // must wait for this load rather than replay the old division value.
        u_mem.mem[8] = enc_r(5'd2, 5'd1, 5'd3, 3'b101);
        u_mem.mem[9] = enc_i(12'h400, 5'd4, 3'b010, 5'd3, 7'h03);
        u_mem.mem[10] = enc_add(5'd3, 5'd3, 5'd7);
        u_mem.mem[11] = enc_i(12'd1, 5'd3, 3'b000, 5'd8, 7'h13);
        // Repeat on a hot cache line, exercising ready load shadowing too.
        u_mem.mem[12] = enc_r(5'd2, 5'd1, 5'd3, 3'b101);
        u_mem.mem[13] = enc_i(12'h400, 5'd4, 3'b010, 5'd3, 7'h03);
        u_mem.mem[14] = enc_add(5'd3, 5'd3, 5'd9);
        // Signed halfword must win with its formatted value, not raw word.
        u_mem.mem[15] = enc_r(5'd2, 5'd1, 5'd3, 3'b101);
        u_mem.mem[16] = enc_i(12'h410, 5'd4, 3'b001, 5'd3, 7'h03);
        u_mem.mem[17] = enc_i(12'd1, 5'd3, 3'b000, 5'd10, 7'h13);
        u_mem.mem[18] = enc_add(5'd3, 5'd3, 5'd11);
        // Older missed load holds the MDU token and younger writer in MEM1's
        // two-entry queue; a consumer must not read past that younger writer.
        u_mem.mem[19] = enc_i(12'h480, 5'd4, 3'b010, 5'd15, 7'h03);
        u_mem.mem[20] = enc_r(5'd2, 5'd2, 5'd3, 3'b000);
        u_mem.mem[21] = enc_i(12'd321, 5'd0, 3'b000, 5'd3, 7'h13);
        u_mem.mem[22] = enc_add(5'd3, 5'd3, 5'd16);
        u_mem.mem[23] = enc_i(12'd1, 5'd0, 3'b000, 5'd12, 7'h13);
        u_mem.mem[24] = enc_j(21'd0, 5'd0);
        u_mem.mem[32'h400 >> 2] = 32'd456;
        u_mem.mem[32'h410 >> 2] = 32'h1234_ff80;
        u_mem.mem[32'h480 >> 2] = 32'd77;
        repeat (4) @(posedge clk);
        @(negedge clk); rst_n = 1'b1;
    end
    always @(posedge clk) begin
        if (rst_n) begin
            cycles <= cycles + 1;
            if (`C.mdu_pending_w && !`C.mdu_result_complete_w) begin
                pending_unready <= pending_unready + 1;
                if (`C.decode_valid_w && `C.decode_accept_w &&
                    `C.decode_instr_w[11:7] == 5'd3) begin
                    if (`C.decode_instr_w[6:0] == 7'h13)
                        overlapping_alu <= overlapping_alu + 1;
                    if (`C.decode_instr_w[6:0] == 7'h03)
                        overlapping_load <= overlapping_load + 1;
                end
            end
            if (`C.mdu_writeback_fire_w)
                mdu_writebacks <= mdu_writebacks + 1;
            if (trap || `C.mdu_cancel_w)
                $fatal(1, "unexpected trap/cancel pc=%08x cause=%08x", retire_pc, trap_cause);
            if (retire && retire_pc == RESET_PC + 32'd96) begin
                if (`C.u_decode_stage.u_regfile.regs_r[5] !== 32'd124 ||
                    `C.u_decode_stage.u_regfile.regs_r[6] !== 32'd246 ||
                    `C.u_decode_stage.u_regfile.regs_r[7] !== 32'd912 ||
                    `C.u_decode_stage.u_regfile.regs_r[8] !== 32'd457 ||
                    `C.u_decode_stage.u_regfile.regs_r[9] !== 32'd912 ||
                    `C.u_decode_stage.u_regfile.regs_r[10] !== 32'hffff_ff81 ||
                    `C.u_decode_stage.u_regfile.regs_r[11] !== 32'hffff_ff00 ||
                    `C.u_decode_stage.u_regfile.regs_r[15] !== 32'd77 ||
                    `C.u_decode_stage.u_regfile.regs_r[16] !== 32'd642)
                    $fatal(1, "younger ALU/load shadow failed");
                if (overlapping_alu < 1 || overlapping_load < 3 ||
                    pending_unready < 20 || mdu_writebacks != 5)
                    $fatal(1, "missing pending-MDU overlap coverage alu=%0d load=%0d pending=%0d wb=%0d",
                           overlapping_alu, overlapping_load, pending_unready, mdu_writebacks);
                $display("PASS: MDU WAW ALU/load shadow cycles=%0d alu=%0d load=%0d pending=%0d wb=%0d",
                         cycles, overlapping_alu, overlapping_load, pending_unready, mdu_writebacks);
                $finish;
            end
            if (cycles > 3000)
                $fatal(1, "MDU WAW/load timeout pc=%08x", retire_pc);
        end
    end
endmodule
