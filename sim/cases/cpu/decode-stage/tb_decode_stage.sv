`timescale 1ns/1ps
`include "edrv32_uop.vh"
`include "edrv32_bus.vh"
`include "edrv32_exception.vh"

module tb_decode_stage;

    reg clk;
    reg rst_n;
    reg in_valid;
    wire in_ready;
    reg [31:0] in_pc;
    reg [31:0] in_instr;
    reg [31:0] in_raw_instr;
    reg in_is_compressed;
    reg in_fetch_fault;
    reg in_compressed_illegal;
    reg [`EDRV32_EPOCH_W-1:0] in_epoch;
    reg in_predicted_taken;
    reg [31:0] in_predicted_target;
    reg commit_rd_write;
    reg [4:0] commit_rd;
    reg [31:0] commit_rd_value;

    reg ex_bp_valid, ex_bp_write, ex_bp_ready, ex_bp_is_load;
    reg [31:0] ex_bp_pc;
    reg [4:0] ex_bp_rd;
    reg [31:0] ex_bp_value;
    reg mem1_bp_valid, mem1_bp_write, mem1_bp_ready, mem1_bp_is_load;
    reg [31:0] mem1_bp_pc;
    reg [4:0] mem1_bp_rd;
    reg [31:0] mem1_bp_value;
    reg mem2_bp_valid, mem2_bp_write, mem2_bp_ready, mem2_bp_is_load;
    reg [31:0] mem2_bp_pc;
    reg [4:0] mem2_bp_rd;
    reg [31:0] mem2_bp_value;
    reg commit_bp_valid, commit_bp_write, commit_bp_ready;
    reg [4:0] commit_bp_rd;
    reg [31:0] commit_bp_value;
    reg mdu_bp_valid, mdu_bp_ready;
    reg [4:0] mdu_bp_rd;
    reg [31:0] mdu_bp_value;
    reg mdu_raw_hazard;
    reg mdu_waw_hazard;
    reg mdu_issue_ready;
    reg issue_block;

    wire [4:0] hazard_rs1_addr;
    wire hazard_uses_rs1;
    wire [4:0] hazard_rs2_addr;
    wire hazard_uses_rs2;
    wire [4:0] hazard_rd_addr;
    wire hazard_rd_write;
    wire dependency_stall;
    wire structural_stall;

    wire candidate_valid;
    wire candidate_ready;
    wire [31:0] candidate_pc;
    wire [31:0] candidate_instr;
    wire candidate_is_compressed;
    wire [`EDRV32_EPOCH_W-1:0] candidate_epoch;
    wire candidate_predicted_taken;
    wire [31:0] candidate_predicted_target;
    wire [4:0] candidate_rd;
    wire candidate_rd_write;
    wire [`EDRV32_OP_CLASS_W-1:0] candidate_op_class;
    wire [`EDRV32_ALU_OP_W-1:0] candidate_alu_op;
    wire [`EDRV32_BRANCH_OP_W-1:0] candidate_branch_op;
    wire [`BUS_SZ_W-1:0] candidate_mem_size;
    wire candidate_mem_unsigned;
    wire [`EDRV32_MDU_OP_W-1:0] candidate_mdu_op;
    wire [`EDRV32_CSR_OP_W-1:0] candidate_csr_op;
    wire [11:0] candidate_csr_addr;
    wire [31:0] candidate_csr_src;
    wire [31:0] candidate_lhs;
    wire [31:0] candidate_rhs;
    wire [31:0] candidate_rs2_value;
    wire [31:0] candidate_imm;
    wire candidate_fence;
    wire candidate_fencei;
    wire candidate_mret;
    wire candidate_wfi;
    wire candidate_exception_valid;
    wire [`EDRV32_EXC_CAUSE_W-1:0] candidate_exception_cause;
    wire [31:0] candidate_exception_tval;

    wire out_valid;
    reg out_accept;
    wire [31:0] out_pc;
    wire [31:0] out_instr;
    wire out_is_compressed;
    wire [`EDRV32_EPOCH_W-1:0] out_epoch;
    wire out_predicted_taken;
    wire [31:0] out_predicted_target;
    wire [4:0] out_rd;
    wire out_rd_write;
    wire [`EDRV32_OP_CLASS_W-1:0] out_op_class;
    wire [`EDRV32_ALU_OP_W-1:0] out_alu_op;
    wire [`EDRV32_BRANCH_OP_W-1:0] out_branch_op;
    wire [`BUS_SZ_W-1:0] out_mem_size;
    wire out_mem_unsigned;
    wire [`EDRV32_MDU_OP_W-1:0] out_mdu_op;
    wire [`EDRV32_CSR_OP_W-1:0] out_csr_op;
    wire [11:0] out_csr_addr;
    wire [31:0] out_csr_src;
    wire [31:0] out_lhs;
    wire [31:0] out_rhs;
    wire [31:0] out_rs2_value;
    wire out_resident_bypass_rs1;
    wire out_resident_bypass_rs2;
    wire [31:0] out_resident_bypass_pc;
    wire out_late_mdu_rs1;
    wire out_late_mdu_rs2;
    wire out_late_load_rs1;
    wire out_late_load_rs2;
    wire [31:0] out_late_load_rs1_pc;
    wire [31:0] out_late_load_rs2_pc;
    wire [31:0] out_imm;
    wire out_fence;
    wire out_fencei;
    wire out_mret;
    wire out_wfi;
    wire out_exception_valid;
    wire [`EDRV32_EXC_CAUSE_W-1:0] out_exception_cause;
    wire [31:0] out_exception_tval;
    reg kill;
    integer checks;

    initial clk = 1'b0;
    always #5 clk = ~clk;

    task automatic check_true;
        input condition;
        input [8*96-1:0] message;
        begin
            checks = checks + 1;
            if (!condition) begin
                $display("FAIL: %0s", message);
                $fatal(1);
            end
        end
    endtask

    task automatic clear_bypass;
        begin
            ex_bp_valid = 1'b0; ex_bp_write = 1'b0; ex_bp_ready = 1'b0;
            ex_bp_is_load = 1'b0; ex_bp_pc = 32'd0;
            ex_bp_rd = 5'd0; ex_bp_value = 32'd0;
            mem1_bp_valid = 1'b0; mem1_bp_write = 1'b0; mem1_bp_ready = 1'b0;
            mem1_bp_is_load = 1'b0; mem1_bp_pc = 32'd0;
            mem1_bp_rd = 5'd0; mem1_bp_value = 32'd0;
            mem2_bp_valid = 1'b0; mem2_bp_write = 1'b0; mem2_bp_ready = 1'b0;
            mem2_bp_is_load = 1'b0; mem2_bp_pc = 32'd0;
            mem2_bp_rd = 5'd0; mem2_bp_value = 32'd0;
            commit_bp_valid = 1'b0; commit_bp_write = 1'b0; commit_bp_ready = 1'b0;
            commit_bp_rd = 5'd0; commit_bp_value = 32'd0;
            mdu_bp_valid = 1'b0; mdu_bp_ready = 1'b0;
            mdu_bp_rd = 5'd0; mdu_bp_value = 32'd0;
        end
    endtask

    edrv32_decode_stage u_dut (
        .clk_i(clk),
        .rst_n_i(rst_n),
        .valid_i(in_valid),
        .ready_o(in_ready),
        .pc_i(in_pc),
        .instr_i(in_instr),
        .raw_instr_i(in_raw_instr),
        .is_compressed_i(in_is_compressed),
        .fetch_fault_i(in_fetch_fault),
        .compressed_illegal_i(in_compressed_illegal),
        .epoch_i(in_epoch),
        .predicted_taken_i(in_predicted_taken),
        .predicted_target_i(in_predicted_target),
        .commit_rd_write_i(commit_rd_write),
        .commit_rd_i(commit_rd),
        .commit_rd_value_i(commit_rd_value),
        .ex_bypass_valid_i(ex_bp_valid),
        .ex_bypass_write_i(ex_bp_write),
        .ex_bypass_ready_i(ex_bp_ready),
        .ex_bypass_is_load_i(ex_bp_is_load),
        .ex_bypass_pc_i(ex_bp_pc),
        .ex_bypass_rd_i(ex_bp_rd),
        .ex_bypass_value_i(ex_bp_value),
        .ex_bypass_lsu_token_valid_i(1'b0),
        .ex_bypass_lsu_token_i(3'd0),
        .mem1_bypass_valid_i(mem1_bp_valid),
        .mem1_bypass_write_i(mem1_bp_write),
        .mem1_bypass_ready_i(mem1_bp_ready),
        .mem1_bypass_is_load_i(mem1_bp_is_load),
        .mem1_bypass_pc_i(mem1_bp_pc),
        .mem1_bypass_rd_i(mem1_bp_rd),
        .mem1_bypass_value_i(mem1_bp_value),
        .mem1_bypass_lsu_token_valid_i(1'b0),
        .mem1_bypass_lsu_token_i(3'd0),
        .mem2_bypass_valid_i(mem2_bp_valid),
        .mem2_bypass_write_i(mem2_bp_write),
        .mem2_bypass_ready_i(mem2_bp_ready),
        .mem2_bypass_is_load_i(mem2_bp_is_load),
        .mem2_bypass_pc_i(mem2_bp_pc),
        .mem2_bypass_rd_i(mem2_bp_rd),
        .mem2_bypass_value_i(mem2_bp_value),
        .mem2_bypass_lsu_token_valid_i(1'b0),
        .mem2_bypass_lsu_token_i(3'd0),
        .commit_bypass_valid_i(commit_bp_valid),
        .commit_bypass_write_i(commit_bp_write),
        .commit_bypass_ready_i(commit_bp_ready),
        .commit_bypass_rd_i(commit_bp_rd),
        .commit_bypass_value_i(commit_bp_value),
        .mdu_bypass_valid_i(mdu_bp_valid),
        .mdu_bypass_ready_i(mdu_bp_ready),
        .mdu_bypass_rd_i(mdu_bp_rd),
        .mdu_bypass_value_i(mdu_bp_value),
        .mdu_passed_mem1_i(1'b0),
        .mdu_passed_mem2_i(1'b0),
        .mdu_authorized_i(1'b0),
        .ex_bypass_mdu_token_i(1'b0),
        .mdu_waw_hazard_i(mdu_waw_hazard),
        .mdu_issue_ready_i(mdu_issue_ready),
        .issue_block_i(issue_block),
        .hazard_rs1_addr_o(hazard_rs1_addr),
        .hazard_uses_rs1_o(hazard_uses_rs1),
        .hazard_rs2_addr_o(hazard_rs2_addr),
        .hazard_uses_rs2_o(hazard_uses_rs2),
        .hazard_rd_addr_o(hazard_rd_addr),
        .hazard_rd_write_o(hazard_rd_write),
        .dependency_stall_o(dependency_stall),
        .structural_stall_o(structural_stall),
        .hpm_stall_resident_o(), .hpm_stall_load_o(),
        .hpm_stall_mdu_o(), .hpm_candidate_class_o(),
        .valid_o(out_valid),
        .ready_i(out_accept),
        .pc_o(out_pc),
        .instr_o(out_instr),
        .is_compressed_o(out_is_compressed),
        .epoch_o(out_epoch),
        .predicted_taken_o(out_predicted_taken),
        .predicted_target_o(out_predicted_target),
        .rd_o(out_rd),
        .rd_write_o(out_rd_write),
        .op_class_o(out_op_class),
        .alu_op_o(out_alu_op),
        .branch_op_o(out_branch_op),
        .mem_size_o(out_mem_size),
        .mem_unsigned_o(out_mem_unsigned),
        .mdu_op_o(out_mdu_op),
        .csr_op_o(out_csr_op),
        .csr_addr_o(out_csr_addr),
        .csr_src_o(out_csr_src),
        .lhs_o(out_lhs),
        .rhs_o(out_rhs),
        .rs2_value_o(out_rs2_value),
        .resident_bypass_rs1_o(out_resident_bypass_rs1),
        .resident_bypass_rs2_o(out_resident_bypass_rs2),
        .resident_bypass_pc_o(out_resident_bypass_pc),
        .late_mdu_rs1_o(out_late_mdu_rs1),
        .late_mdu_rs2_o(out_late_mdu_rs2),
        .late_load_rs1_o(out_late_load_rs1),
        .late_load_rs2_o(out_late_load_rs2),
        .late_load_rs1_pc_o(out_late_load_rs1_pc),
        .late_load_rs2_pc_o(out_late_load_rs2_pc),
        .late_load_rs1_token_valid_o(), .late_load_rs1_token_o(),
        .late_load_rs2_token_valid_o(), .late_load_rs2_token_o(),
        .imm_o(out_imm),
        .fence_o(out_fence),
        .fencei_o(out_fencei),
        .mret_o(out_mret),
        .wfi_o(out_wfi),
        .exception_valid_o(out_exception_valid),
        .exception_cause_o(out_exception_cause),
        .exception_tval_o(out_exception_tval),
        .frontend_kill_i(kill),
        .boundary_kill_i(kill)
    );

    initial begin
        checks = 0;
        rst_n = 1'b0;
        in_valid = 1'b0;
        in_pc = 32'h8000_0000;
        in_instr = 32'd0;
        in_raw_instr = 32'd0;
        in_is_compressed = 1'b0;
        in_fetch_fault = 1'b0;
        in_compressed_illegal = 1'b0;
        in_epoch = 2'd0;
        in_predicted_taken = 1'b0;
        in_predicted_target = 32'd0;
        commit_rd_write = 1'b0;
        commit_rd = 5'd0;
        commit_rd_value = 32'd0;
        clear_bypass();
        mdu_raw_hazard = 1'b0;
        mdu_waw_hazard = 1'b0;
        mdu_issue_ready = 1'b1;
        issue_block = 1'b0;
        out_accept = 1'b0;
        kill = 1'b0;

        repeat (2) @(posedge clk);
        rst_n = 1'b1;
        #1;
        check_true(!out_valid, "DECODE reset only clears valid");

        // Seed x1 and x2 through the sole COMMIT write port.
        commit_rd_write = 1'b1; commit_rd = 5'd1; commit_rd_value = 32'd10;
        @(posedge clk); #1;
        commit_rd = 5'd2; commit_rd_value = 32'd20;
        @(posedge clk); #1;
        commit_rd_write = 1'b0;

        // ADD reads both register-file ports in DECODE and registers resolved data.
        in_instr = 32'h0020_81b3; // add x3,x1,x2
        in_raw_instr = in_instr;
        in_pc = 32'h8000_0100;
        in_epoch = 2'd1;
        in_predicted_taken = 1'b0;
        in_valid = 1'b1;
        #1;
        check_true(in_ready && !dependency_stall && !structural_stall, "ADD can issue");
        check_true(hazard_rs1_addr == 5'd1 && hazard_rs2_addr == 5'd2,
                   "DECODE exposes exact scoreboard query addresses");
        @(posedge clk); #1;
        in_valid = 1'b0;
        check_true(out_valid && out_op_class == `EDRV32_OP_ALU, "DECODE registers ADD class");
        check_true(out_lhs == 32'd10 && out_rhs == 32'd20 && out_rd == 5'd3,
                   "DECODE registers RF operands and destination");

        // No transparent overwrite while EX stops.
        in_valid = 1'b1;
        in_instr = 32'h4020_81b3; // sub x3,x1,x2
        in_raw_instr = in_instr;
        #1;
        check_true(!in_ready && out_lhs == 32'd10 && out_rhs == 32'd20,
                   "DECODE holds output under EX backpressure");

        // Refill while previous output advances. Youngest matching bypass wins.
        out_accept = 1'b1;
        ex_bp_valid = 1'b1; ex_bp_write = 1'b1; ex_bp_ready = 1'b1;
        ex_bp_rd = 5'd1; ex_bp_value = 32'd100;
        mem1_bp_valid = 1'b1; mem1_bp_write = 1'b1; mem1_bp_ready = 1'b1;
        mem1_bp_rd = 5'd1; mem1_bp_value = 32'd50;
        mem2_bp_valid = 1'b1; mem2_bp_write = 1'b1; mem2_bp_ready = 1'b1;
        mem2_bp_rd = 5'd2; mem2_bp_value = 32'd30;
        #1;
        check_true(in_ready, "DECODE can refill on EX accept");
        @(posedge clk); #1;
        out_accept = 1'b0;
        in_valid = 1'b0;
        clear_bypass();
        check_true(out_alu_op == `EDRV32_ALU_SUB, "DECODE registers SUB control");
        check_true(out_lhs == 32'd100 && out_rhs == 32'd30,
                   "DECODE selects youngest rs1 and independent rs2 bypasses");

        // A same-cycle refill records the forwardable resident ALU producer;
        // EX consumes its registered EX/MEM1 result on the following cycle.
        out_accept = 1'b1;
        in_valid = 1'b1;
        in_instr = 32'h0011_8213; // addi x4,x3,1
        in_raw_instr = in_instr;
        in_pc = 32'h8000_0104;
        #1;
        check_true(!dependency_stall && in_ready,
                   "Forwardable resident ALU RAW refills without a bubble");
        @(posedge clk); #1;
        out_accept = 1'b0;
        in_valid = 1'b0;
        clear_bypass();
        check_true(out_valid && out_rd == 5'd4 &&
                   out_resident_bypass_rs1 && !out_resident_bypass_rs2 &&
                   out_resident_bypass_pc == 32'h8000_0100,
                   "DECODE records the exact resident producer identity");

        // A youngest matching producer blocks even when an older value is ready.
        out_accept = 1'b1;
        @(posedge clk); #1;
        out_accept = 1'b0;
        in_valid = 1'b1;
        in_instr = 32'h0020_81b3;
        in_raw_instr = in_instr;
        ex_bp_valid = 1'b1; ex_bp_write = 1'b1; ex_bp_ready = 1'b0;
        ex_bp_rd = 5'd1; ex_bp_value = 32'hdead_beef;
        mem1_bp_valid = 1'b1; mem1_bp_write = 1'b1; mem1_bp_ready = 1'b1;
        mem1_bp_rd = 5'd1; mem1_bp_value = 32'd77;
        #1;
        check_true(dependency_stall && !in_ready, "Unready youngest bypass stalls DECODE");
        ex_bp_ready = 1'b1; ex_bp_value = 32'd88;
        #1;
        check_true(!dependency_stall && in_ready,
                   "DECODE releases when youngest result becomes ready");
        @(posedge clk); #1;
        in_valid = 1'b0;
        clear_bypass();
        check_true(out_lhs == 32'd88, "DECODE never selects stale older bypass");

        // An instruction waiting only for the registered MEM2 load owner may
        // enter EX early. EX will hold it until the D-cache response record is
        // ready instead of spending the same cycle in the DECODE boundary.
        out_accept = 1'b1;
        @(posedge clk); #1;
        out_accept = 1'b0;
        in_valid = 1'b1;
        in_instr = 32'h0010_8213; // addi x4,x1,1
        in_raw_instr = in_instr;
        mem2_bp_valid = 1'b1;
        mem2_bp_write = 1'b1;
        mem2_bp_ready = 1'b0;
        mem2_bp_is_load = 1'b1;
        mem2_bp_rd = 5'd1;
        #1;
        check_true(!dependency_stall && in_ready,
                   "MEM2 load-only dependency issues early to EX");
        @(posedge clk); #1;
        in_valid = 1'b0;
        clear_bypass();
        check_true(out_valid && out_late_load_rs1 && !out_late_load_rs2,
                   "DECODE registers the late rs1 load qualifier");

        // MDU scoreboard RAW/WAW are local DECODE dependency stalls.
        out_accept = 1'b1;
        @(posedge clk); #1;
        out_accept = 1'b0;
        in_valid = 1'b1;
        in_instr = 32'h0020_8463; // branch cannot soft-release an unready MDU
        in_raw_instr = in_instr;
        mdu_raw_hazard = 1'b1;
        mdu_bp_valid = 1'b1;
        mdu_bp_ready = 1'b0;
        mdu_bp_rd = 5'd1;
        #1;
        check_true(dependency_stall && !in_ready, "MDU RAW stalls DECODE");
        mdu_bp_valid = 1'b1;
        mdu_bp_ready = 1'b1;
        mdu_bp_rd = 5'd1;
        mdu_bp_value = 32'd1234;
        in_instr = 32'h0020_81b3;
        in_raw_instr = in_instr;
        #1;
        check_true(!dependency_stall && in_ready,
                   "Completed MDU result releases RAW before writeback");
        @(posedge clk); #1;
        out_accept = 1'b0;
        in_valid = 1'b0;
        check_true(out_lhs == 32'd1234,
                   "DECODE captures completed MDU bypass data");
        clear_bypass();
        mdu_raw_hazard = 1'b0;
        out_accept = 1'b1;
        @(posedge clk); #1;
        out_accept = 1'b0;
        mdu_raw_hazard = 1'b1;
        mdu_bp_valid = 1'b1;
        mdu_bp_ready = 1'b0;
        mdu_bp_rd = 5'd1;
        in_valid = 1'b1;
        #1;
        check_true(!dependency_stall && in_ready,
                   "short MDU consumer may reserve EX before completion");
        mdu_waw_hazard = 1'b1;
        in_instr = 32'h0010_8093; // same-rd read/modify/write
        in_raw_instr = in_instr;
        #1;
        check_true(!dependency_stall && in_ready,
                   "ordinary same-rd writer may reserve EX before MDU completion");
        mdu_waw_hazard = 1'b0;
        @(posedge clk); #1;
        in_valid = 1'b0;
        clear_bypass();
        mdu_raw_hazard = 1'b0;
        check_true(out_valid && out_late_mdu_rs1 && !out_late_mdu_rs2,
                   "DECODE stores a separate late MDU source tag");
        out_accept = 1'b1;
        @(posedge clk); #1;
        out_accept = 1'b0;
        mdu_waw_hazard = 1'b1;
        in_valid = 1'b1;
        in_instr = 32'h0220_80b3; // mul x1,x1,x2
        in_raw_instr = in_instr;
        #1;
        check_true(dependency_stall && !in_ready, "MDU WAW stalls DECODE");
        mdu_waw_hazard = 1'b0;
        in_valid = 1'b0;

        // MDU request readiness is structural and separate from data hazards.
        in_valid = 1'b1;
        in_instr = 32'h0220_81b3; // mul x3,x1,x2
        in_raw_instr = in_instr;
        mdu_issue_ready = 1'b0;
        #1;
        check_true(structural_stall && !dependency_stall && !in_ready,
                   "Busy MDU is a structural stall");
        mdu_issue_ready = 1'b1;
        #1;
        check_true(in_ready, "Ready MDU accepts request token");
        @(posedge clk); #1;
        in_valid = 1'b0;
        check_true(out_op_class == `EDRV32_OP_MDU && out_mdu_op == `EDRV32_MDU_MUL,
                   "DECODE registers MDU operation");

        // The resident MDU and its short consumer transfer/refill together.
        // Control consumers still wait; stalled producers cannot release a tag.
        in_valid = 1'b1;
        in_instr = 32'h0001_8463; // beq x3,x0,+8
        in_raw_instr = in_instr;
        out_accept = 1'b1; #1;
        check_true(dependency_stall && !in_ready,
                   "resident MDU still blocks an early control consumer");
        in_instr = 32'h0031_8233; // add x4,x3,x3
        in_raw_instr = in_instr;
        out_accept = 1'b0; #1;
        check_true(!dependency_stall && !in_ready,
                   "short consumer does not reuse a held resident MDU boundary");
        out_accept = 1'b1; #1;
        check_true(!dependency_stall && in_ready,
                   "resident MDU transfer permits short consumer refill");
        @(posedge clk); #1;
        in_valid = 1'b0;
        out_accept = 1'b0;
        check_true(out_valid && out_op_class == `EDRV32_OP_ALU &&
                   out_late_mdu_rs1 && out_late_mdu_rs2,
                   "refilled consumer waits on the newly allocated MDU generation");
        out_accept = 1'b1;
        @(posedge clk); #1;
        out_accept = 1'b0;

        // Illegal instructions become side-effect-free exception packets.
        out_accept = 1'b1;
        @(posedge clk); #1;
        out_accept = 1'b0;
        in_valid = 1'b1;
        in_instr = 32'h0000_0053;
        in_raw_instr = 32'h0000_0053;
        in_pc = 32'h8000_0200;
        issue_block = 1'b1;
        #1;
        check_true(!in_ready && structural_stall,
                   "Decode-discovered exception waits behind a full backend");
        issue_block = 1'b0;
        #1;
        check_true(in_ready && !structural_stall,
                   "Illegal exception advances when backend capacity returns");
        @(posedge clk); #1;
        in_valid = 1'b0;
        check_true(out_exception_valid && out_exception_cause == `EDRV32_EXC_ILLEGAL_INSTR,
                   "DECODE classifies illegal instruction");
        check_true(out_exception_tval == 32'h0000_0053 && !out_rd_write,
                   "Illegal instruction carries raw mtval and no GPR write");

        // Fetch access fault has priority over decode/compressed illegality.
        out_accept = 1'b1;
        in_valid = 1'b1;
        in_instr = 32'h0000_0013;
        in_raw_instr = 32'h0000_0000;
        in_pc = 32'h8000_0300;
        in_fetch_fault = 1'b1;
        in_compressed_illegal = 1'b1;
        issue_block = 1'b1;
        #1;
        check_true(in_ready && !structural_stall,
                   "Frontend fault bypasses backend issue block");
        @(posedge clk); #1;
        out_accept = 1'b0;
        in_valid = 1'b0;
        in_fetch_fault = 1'b0;
        in_compressed_illegal = 1'b0;
        issue_block = 1'b0;
        check_true(out_exception_cause == `EDRV32_EXC_INSTR_ACCESS &&
                   out_exception_tval == 32'h8000_0300, "Fetch fault priority/tval");

        // CSR immediate source is zero-extended zimm, not an I immediate.
        out_accept = 1'b1;
        in_valid = 1'b1;
        in_instr = {12'h300, 5'd3, 3'b101, 5'd5, 7'b1110011};
        in_raw_instr = in_instr;
        #1;
        @(posedge clk); #1;
        out_accept = 1'b0;
        in_valid = 1'b0;
        check_true(out_op_class == `EDRV32_OP_CSR && out_csr_addr == 12'h300,
                   "DECODE registers CSR class/address");
        check_true(out_csr_src == 32'd3 && out_csr_op == `EDRV32_CSR_WRITE,
                   "DECODE registers CSR zimm source");

        // Kill wins over accept/refill.
        out_accept = 1'b1;
        in_valid = 1'b1;
        in_instr = 32'h0020_81b3;
        in_raw_instr = in_instr;
        kill = 1'b1;
        #1;
        check_true(!in_ready, "DECODE kill prevents new capture");
        @(posedge clk); #1;
        kill = 1'b0;
        out_accept = 1'b0;
        in_valid = 1'b0;
        check_true(!out_valid, "DECODE kill clears output valid");

        $display("PASS: DECODE stage (%0d checks)", checks);
        $finish;
    end

endmodule
