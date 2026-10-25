`timescale 1ns/1ps
`include "edrv32_isa.vh"
`include "edrv32_uop.vh"
`include "edrv32_bus.vh"

module tb_foundation;

    reg clk;
    reg rst_n;
    integer checks;

    initial clk = 1'b0;
    always #5 clk = ~clk;

    task automatic check_true;
        input condition;
        input [8*80-1:0] message;
        begin
            checks = checks + 1;
            if (!condition) begin
                $display("FAIL: %0s", message);
                $fatal(1);
            end
        end
    endtask

    function automatic [31:0] enc_r;
        input [6:0] funct7;
        input [4:0] rs2;
        input [4:0] rs1;
        input [2:0] funct3;
        input [4:0] rd;
        input [6:0] opcode;
        begin
            enc_r = {funct7, rs2, rs1, funct3, rd, opcode};
        end
    endfunction

    function automatic [31:0] enc_i;
        input [11:0] imm;
        input [4:0] rs1;
        input [2:0] funct3;
        input [4:0] rd;
        input [6:0] opcode;
        begin
            enc_i = {imm, rs1, funct3, rd, opcode};
        end
    endfunction

    function automatic [31:0] enc_s;
        input [11:0] imm;
        input [4:0] rs2;
        input [4:0] rs1;
        input [2:0] funct3;
        begin
            enc_s = {imm[11:5], rs2, rs1, funct3, imm[4:0], `EDRV32_OPCODE_STORE};
        end
    endfunction

    function automatic [31:0] enc_b;
        input [12:0] imm;
        input [4:0] rs2;
        input [4:0] rs1;
        input [2:0] funct3;
        begin
            enc_b = {imm[12], imm[10:5], rs2, rs1, funct3,
                     imm[4:1], imm[11], `EDRV32_OPCODE_BRANCH};
        end
    endfunction

    function automatic [31:0] enc_j;
        input [20:0] imm;
        input [4:0] rd;
        begin
            enc_j = {imm[20], imm[10:1], imm[11], imm[19:12], rd,
                     `EDRV32_OPCODE_JAL};
        end
    endfunction

    reg  [31:0] instr;
    wire [4:0] dec_rs1;
    wire [4:0] dec_rs2;
    wire [4:0] dec_rd;
    wire dec_uses_rs1;
    wire dec_uses_rs2;
    wire dec_rd_write;
    wire [`EDRV32_OP_CLASS_W-1:0] dec_op_class;
    wire [`EDRV32_ALU_OP_W-1:0] dec_alu_op;
    wire [`EDRV32_OP_A_SEL_W-1:0] dec_op_a_sel;
    wire dec_op_b_imm;
    wire [`EDRV32_IMM_SEL_W-1:0] dec_imm_sel;
    wire [`EDRV32_BRANCH_OP_W-1:0] dec_branch_op;
    wire [`BUS_SZ_W-1:0] dec_mem_size;
    wire dec_mem_unsigned;
    wire [`EDRV32_MDU_OP_W-1:0] dec_mdu_op;
    wire [`EDRV32_CSR_OP_W-1:0] dec_csr_op;
    wire dec_csr_imm;
    wire dec_fence;
    wire dec_fencei;
    wire dec_ecall;
    wire dec_ebreak;
    wire dec_mret;
    wire dec_wfi;
    wire dec_illegal;

    edrv32_decoder u_decoder (
        .instr_i(instr),
        .rs1_addr_o(dec_rs1), .rs2_addr_o(dec_rs2), .rd_addr_o(dec_rd),
        .uses_rs1_o(dec_uses_rs1), .uses_rs2_o(dec_uses_rs2),
        .rd_write_o(dec_rd_write), .op_class_o(dec_op_class),
        .alu_op_o(dec_alu_op), .op_a_sel_o(dec_op_a_sel),
        .op_b_imm_o(dec_op_b_imm), .imm_sel_o(dec_imm_sel),
        .branch_op_o(dec_branch_op), .mem_size_o(dec_mem_size),
        .mem_unsigned_o(dec_mem_unsigned), .mdu_op_o(dec_mdu_op),
        .csr_op_o(dec_csr_op), .csr_imm_o(dec_csr_imm),
        .fence_o(dec_fence), .fencei_o(dec_fencei),
        .ecall_o(dec_ecall), .ebreak_o(dec_ebreak),
        .mret_o(dec_mret), .wfi_o(dec_wfi), .illegal_o(dec_illegal)
    );

    wire [31:0] immediate;
    edrv32_immgen u_immgen (
        .instr_i(instr), .imm_sel_i(dec_imm_sel), .imm_o(immediate)
    );

    reg  [`EDRV32_ALU_OP_W-1:0] alu_op;
    reg  [31:0] alu_lhs;
    reg  [31:0] alu_rhs;
    wire [31:0] alu_result;
    edrv32_alu u_alu (
        .op_i(alu_op), .lhs_i(alu_lhs), .rhs_i(alu_rhs), .result_o(alu_result)
    );

    reg  [4:0] rf_rs1_addr;
    reg  [4:0] rf_rs2_addr;
    wire [31:0] rf_rs1_data;
    wire [31:0] rf_rs2_data;
    reg         rf_write;
    reg  [4:0] rf_rd_addr;
    reg  [31:0] rf_rd_data;
    edrv32_regfile u_regfile (
        .clk_i(clk), .rs1_addr_i(rf_rs1_addr), .rs1_data_o(rf_rs1_data),
        .rs2_addr_i(rf_rs2_addr), .rs2_data_o(rf_rs2_data),
        .rd_write_i(rf_write), .rd_addr_i(rf_rd_addr), .rd_data_i(rf_rd_data)
    );

    reg sb_alloc_valid;
    wire sb_alloc_ready;
    reg [4:0] sb_alloc_rd;
    reg sb_alloc_rd_write;
    reg sb_authorize;
    reg sb_cancel;
    reg sb_writeback;
    reg sb_pass_mem1;
    reg sb_pass_mem2;
    wire sb_passed_mem1;
    wire sb_passed_mem2;
    reg [4:0] sb_rs1;
    reg sb_uses_rs1;
    reg [4:0] sb_rs2;
    reg sb_uses_rs2;
    reg [4:0] sb_issue_rd;
    reg sb_issue_rd_write;
    wire sb_pending;
    wire [4:0] sb_pending_rd;
    wire sb_authorized;
    wire sb_raw_hazard;
    wire sb_waw_hazard;

    edrv32_mdu_scoreboard u_scoreboard (
        .clk_i(clk), .rst_n_i(rst_n),
        .alloc_valid_i(sb_alloc_valid), .alloc_ready_o(sb_alloc_ready),
        .alloc_rd_i(sb_alloc_rd), .alloc_rd_write_i(sb_alloc_rd_write),
        .authorize_i(sb_authorize), .cancel_i(sb_cancel),
        .writeback_fire_i(sb_writeback),
        .pass_mem1_i(sb_pass_mem1), .pass_mem2_i(sb_pass_mem2),
        .passed_mem1_o(sb_passed_mem1), .passed_mem2_o(sb_passed_mem2),
        .rs1_addr_i(sb_rs1), .uses_rs1_i(sb_uses_rs1),
        .rs2_addr_i(sb_rs2), .uses_rs2_i(sb_uses_rs2),
        .issue_rd_i(sb_issue_rd), .issue_rd_write_i(sb_issue_rd_write),
        .pending_o(sb_pending), .pending_rd_o(sb_pending_rd),
        .authorized_o(sb_authorized), .raw_hazard_o(sb_raw_hazard),
        .waw_hazard_o(sb_waw_hazard)
    );

    reg redir_commit_exc;
    reg [31:0] redir_commit_exc_target;
    reg redir_commit_irq;
    reg [31:0] redir_commit_irq_target;
    reg redir_commit_mret;
    reg [31:0] redir_commit_mret_target;
    reg redir_commit_fencei;
    reg [31:0] redir_commit_fencei_target;
    wire redir_commit_ready;
    reg redir_ex;
    reg [31:0] redir_ex_target;
    wire redir_ex_ready;
    wire redir_valid;
    reg redir_accept;
    wire [31:0] redir_target;
    wire [`EDRV32_REDIRECT_REASON_W-1:0] redir_reason;
    wire [`EDRV32_EPOCH_W-1:0] redir_epoch;

    edrv32_redirect_ctrl u_redirect (
        .clk_i(clk), .rst_n_i(rst_n),
        .commit_exception_valid_i(redir_commit_exc),
        .commit_exception_target_i(redir_commit_exc_target),
        .commit_interrupt_valid_i(redir_commit_irq),
        .commit_interrupt_target_i(redir_commit_irq_target),
        .commit_mret_valid_i(redir_commit_mret),
        .commit_mret_target_i(redir_commit_mret_target),
        .commit_fencei_valid_i(redir_commit_fencei),
        .commit_fencei_target_i(redir_commit_fencei_target),
        .commit_event_ready_o(redir_commit_ready),
        .ex_redirect_valid_i(redir_ex), .ex_redirect_target_i(redir_ex_target),
        .ex_event_ready_o(redir_ex_ready),
        .redirect_valid_o(redir_valid), .redirect_accept_i(redir_accept),
        .redirect_target_o(redir_target), .redirect_reason_o(redir_reason),
        .redirect_epoch_o(redir_epoch)
    );

    initial begin
        checks = 0;
        rst_n = 1'b0;
        instr = 32'd0;
        alu_op = `EDRV32_ALU_ADD;
        alu_lhs = 32'd0;
        alu_rhs = 32'd0;
        rf_rs1_addr = 5'd0;
        rf_rs2_addr = 5'd0;
        rf_write = 1'b0;
        rf_rd_addr = 5'd0;
        rf_rd_data = 32'd0;
        sb_alloc_valid = 1'b0;
        sb_alloc_rd = 5'd0;
        sb_alloc_rd_write = 1'b0;
        sb_authorize = 1'b0;
        sb_cancel = 1'b0;
        sb_writeback = 1'b0;
        sb_pass_mem1 = 1'b0;
        sb_pass_mem2 = 1'b0;
        sb_rs1 = 5'd0;
        sb_uses_rs1 = 1'b0;
        sb_rs2 = 5'd0;
        sb_uses_rs2 = 1'b0;
        sb_issue_rd = 5'd0;
        sb_issue_rd_write = 1'b0;
        redir_commit_exc = 1'b0;
        redir_commit_exc_target = 32'd0;
        redir_commit_irq = 1'b0;
        redir_commit_irq_target = 32'd0;
        redir_commit_mret = 1'b0;
        redir_commit_mret_target = 32'd0;
        redir_commit_fencei = 1'b0;
        redir_commit_fencei_target = 32'd0;
        redir_ex = 1'b0;
        redir_ex_target = 32'd0;
        redir_accept = 1'b0;

        repeat (2) @(posedge clk);
        rst_n = 1'b1;
        #1;

        // Decoder and immediate generation.
        instr = enc_r(7'b0000000, 5'd2, 5'd1, 3'b000, 5'd3, `EDRV32_OPCODE_OP);
        #1;
        check_true(!dec_illegal && dec_op_class == `EDRV32_OP_ALU, "ADD class/legal");
        check_true(dec_alu_op == `EDRV32_ALU_ADD && dec_uses_rs1 && dec_uses_rs2, "ADD controls");
        check_true(dec_rd_write && dec_rd == 5'd3, "ADD destination");

        instr = enc_r(7'b0100000, 5'd2, 5'd1, 3'b000, 5'd3, `EDRV32_OPCODE_OP);
        #1;
        check_true(!dec_illegal && dec_alu_op == `EDRV32_ALU_SUB, "SUB decode");

        instr = enc_r(7'b0000001, 5'd2, 5'd1, 3'b000, 5'd3, `EDRV32_OPCODE_OP);
        #1;
        check_true(!dec_illegal && dec_op_class == `EDRV32_OP_MDU && dec_mdu_op == `EDRV32_MDU_MUL,
               "MUL decode");

        instr = enc_r(7'b0000001, 5'd2, 5'd1, 3'b101, 5'd3, `EDRV32_OPCODE_OP);
        #1;
        check_true(!dec_illegal && dec_mdu_op == `EDRV32_MDU_DIVU, "DIVU decode");

        instr = enc_i(12'hffc, 5'd1, 3'b000, 5'd5, `EDRV32_OPCODE_OP_IMM);
        #1;
        check_true(!dec_illegal && dec_op_b_imm && immediate == 32'hffff_fffc, "ADDI negative immediate");

        instr = enc_i(12'h00c, 5'd3, 3'b101, 5'd4, `EDRV32_OPCODE_LOAD);
        #1;
        check_true(!dec_illegal && dec_op_class == `EDRV32_OP_LOAD, "LHU class");
        check_true(dec_mem_size == `BUS_SZ_HALF && dec_mem_unsigned && immediate == 32'd12, "LHU controls");

        instr = enc_s(12'hff8, 5'd4, 5'd3, 3'b010);
        #1;
        check_true(!dec_illegal && dec_op_class == `EDRV32_OP_STORE, "SW class");
        check_true(dec_mem_size == `BUS_SZ_WORD && immediate == 32'hffff_fff8, "SW controls/immediate");

        instr = enc_b(13'd8, 5'd2, 5'd1, 3'b000);
        #1;
        check_true(!dec_illegal && dec_branch_op == `EDRV32_BRANCH_EQ && immediate == 32'd8,
               "BEQ decode/immediate");

        instr = enc_j(21'h1f_fffc, 5'd1);
        #1;
        check_true(!dec_illegal && dec_op_class == `EDRV32_OP_JUMP && immediate == 32'hffff_fffc,
               "JAL negative immediate");

        instr = {12'h300, 5'd1, 3'b010, 5'd5, `EDRV32_OPCODE_SYSTEM};
        #1;
        check_true(!dec_illegal && dec_op_class == `EDRV32_OP_CSR, "CSRRS class");
        check_true(dec_csr_op == `EDRV32_CSR_SET && dec_uses_rs1 && !dec_csr_imm, "CSRRS controls");

        instr = {12'h300, 5'd3, 3'b101, 5'd5, `EDRV32_OPCODE_SYSTEM};
        #1;
        check_true(!dec_illegal && dec_csr_op == `EDRV32_CSR_WRITE && dec_csr_imm,
               "CSRRWI controls");

        instr = `EDRV32_INSN_ECALL;
        #1;
        check_true(!dec_illegal && dec_ecall && dec_op_class == `EDRV32_OP_SYSTEM, "ECALL decode");
        instr = `EDRV32_INSN_MRET;
        #1;
        check_true(!dec_illegal && dec_mret, "MRET decode");
        instr = `EDRV32_INSN_WFI;
        #1;
        check_true(!dec_illegal && dec_wfi, "WFI decode");
        instr = 32'h0000_100f;
        #1;
        check_true(!dec_illegal && dec_fencei && !dec_fence, "FENCE.I decode");

        instr = enc_r(7'b1111111, 5'd2, 5'd1, 3'b000, 5'd3, `EDRV32_OPCODE_OP);
        #1;
        check_true(dec_illegal && !dec_rd_write, "Bad OP encoding has no write side effect");
        instr = 32'h0000_0053;
        #1;
        check_true(dec_illegal && dec_op_class == `EDRV32_OP_NONE, "Floating-point opcode is illegal");

        // Behavioral ALU.
        alu_op = `EDRV32_ALU_ADD; alu_lhs = 32'hffff_ffff; alu_rhs = 32'd2; #1;
        check_true(alu_result == 32'd1, "ALU add wrap");
        alu_op = `EDRV32_ALU_SLT; alu_lhs = 32'hffff_ffff; alu_rhs = 32'd1; #1;
        check_true(alu_result == 32'd1, "ALU signed compare");
        alu_op = `EDRV32_ALU_SLTU; #1;
        check_true(alu_result == 32'd0, "ALU unsigned compare");
        alu_op = `EDRV32_ALU_SRA; alu_lhs = 32'h8000_0000; alu_rhs = 32'd4; #1;
        check_true(alu_result == 32'hf800_0000, "ALU arithmetic shift");

        // Register file has no reset dependency, and x0 is immutable.
        rf_write = 1'b1; rf_rd_addr = 5'd5; rf_rd_data = 32'h1234_5678;
        @(posedge clk); #1;
        rf_write = 1'b0; rf_rs1_addr = 5'd5; rf_rs2_addr = 5'd0; #1;
        check_true(rf_rs1_data == 32'h1234_5678, "Register file write/read");
        check_true(rf_rs2_data == 32'd0, "Register file x0 read");
        rf_rs1_addr = 5'd6; rf_rs2_addr = 5'd6;
        rf_write = 1'b1; rf_rd_addr = 5'd6; rf_rd_data = 32'ha5a5_5a5a; #1;
        check_true(rf_rs1_data == 32'ha5a5_5a5a &&
                   rf_rs2_data == 32'ha5a5_5a5a,
                   "Register file explicit same-cycle write-first bypass");
        @(posedge clk); #1;
        rf_write = 1'b1; rf_rd_addr = 5'd0; rf_rd_data = 32'hffff_ffff;
        @(posedge clk); #1;
        rf_write = 1'b0; rf_rs1_addr = 5'd0; #1;
        check_true(rf_rs1_data == 32'd0, "Register file ignores x0 write");

        // MDU-only scoreboard.
        check_true(sb_alloc_ready && !sb_pending, "Scoreboard empty after reset");
        sb_alloc_valid = 1'b1; sb_alloc_rd_write = 1'b1; sb_alloc_rd = 5'd7;
        @(posedge clk); #1;
        sb_alloc_valid = 1'b0;
        check_true(sb_pending && sb_pending_rd == 5'd7 && !sb_alloc_ready, "Scoreboard allocation");
        check_true(!sb_passed_mem1 && !sb_passed_mem2, "New token starts before both age boundaries");
        sb_pass_mem1 = 1'b1;
        @(posedge clk); #1;
        sb_pass_mem1 = 1'b0;
        check_true(sb_passed_mem1 && !sb_passed_mem2, "MEM1 dequeue sets only MEM1 age boundary");
        sb_pass_mem2 = 1'b1;
        @(posedge clk); #1;
        sb_pass_mem2 = 1'b0;
        check_true(sb_passed_mem1 && sb_passed_mem2, "MEM2 transfer preserves earlier age boundary");
        sb_rs1 = 5'd7; sb_uses_rs1 = 1'b1; #1;
        check_true(sb_raw_hazard, "Scoreboard RAW hazard");
        sb_rs1 = 5'd4; sb_issue_rd = 5'd7; sb_issue_rd_write = 1'b1; #1;
        check_true(!sb_raw_hazard && sb_waw_hazard, "Scoreboard WAW and independent RAW");
        sb_authorize = 1'b1;
        @(posedge clk); #1;
        sb_authorize = 1'b0;
        check_true(sb_authorized, "Scoreboard authorization");
        sb_writeback = 1'b1;
        sb_pass_mem1 = 1'b1; sb_pass_mem2 = 1'b1;
        #1;
        check_true(!sb_alloc_ready, "Writeback does not transparently reuse MDU slot");
        @(posedge clk); #1;
        sb_writeback = 1'b0;
        sb_pass_mem1 = 1'b0; sb_pass_mem2 = 1'b0;
        check_true(!sb_pending && sb_alloc_ready, "Scoreboard clears only after writeback");
        check_true(!sb_passed_mem1 && !sb_passed_mem2, "Writeback clears age flags despite same-edge crossings");
        sb_alloc_valid = 1'b1; sb_alloc_rd = 5'd9;
        @(posedge clk); #1;
        sb_alloc_valid = 1'b0; sb_pass_mem1 = 1'b1;
        check_true(!sb_passed_mem1 && !sb_passed_mem2, "Reallocated generation has fresh age flags");
        @(posedge clk); #1;
        sb_pass_mem1 = 1'b0; sb_pass_mem2 = 1'b1; sb_cancel = 1'b1;
        @(posedge clk); #1;
        sb_cancel = 1'b0; sb_pass_mem2 = 1'b0;
        check_true(!sb_pending, "Scoreboard cancels younger MDU slot");
        check_true(!sb_passed_mem1 && !sb_passed_mem2, "Cancel clears age flags despite same-edge crossing");

        // Registered redirect and COMMIT-over-EX priority.
        redir_ex = 1'b1; redir_ex_target = 32'h1000_0040; #1;
        check_true(redir_ex_ready && !redir_valid, "EX redirect sees empty registered slot");
        @(posedge clk); #1;
        redir_ex = 1'b0;
        check_true(redir_valid && redir_target == 32'h1000_0040, "EX redirect registered target");
        check_true(redir_reason == `EDRV32_REDIR_EX_BRANCH && redir_epoch == 2'd1,
               "EX redirect reason/epoch");
        check_true(!redir_ex_ready && !redir_commit_ready,
                   "Full redirect slot backpressures producers");
        redir_accept = 1'b1;
        @(posedge clk); #1;
        redir_accept = 1'b0;
        check_true(!redir_valid, "Redirect accept clears slot without transparent refill");

        redir_commit_exc = 1'b1; redir_commit_exc_target = 32'h0000_0100;
        redir_ex = 1'b1; redir_ex_target = 32'h2000_0000; #1;
        check_true(redir_commit_ready && !redir_ex_ready,
                   "COMMIT event suppresses same-cycle EX event");
        @(posedge clk); #1;
        redir_commit_exc = 1'b0; redir_ex = 1'b0;
        check_true(redir_valid && redir_target == 32'h0000_0100,
                   "COMMIT exception wins redirect target");
        check_true(redir_reason == `EDRV32_REDIR_EXCEPTION && redir_epoch == 2'd2,
               "COMMIT exception reason/epoch");

        $display("PASS: cpu rewrite foundation (%0d checks)", checks);
        $finish;
    end

endmodule
