`timescale 1ns/1ps
`include "edrv32_isa.vh"
`include "edrv32_uop.vh"
`include "edrv32_bus.vh"
`include "edrv32_exception.vh"

module tb_ex_mul_stable;

    reg clk, rst_n;
    reg in_valid;
    wire in_ready;
    reg [31:0] in_pc, in_instr;
    reg in_is_compressed;
    reg [`EDRV32_EPOCH_W-1:0] in_epoch;
    reg in_predicted_taken;
    reg [31:0] in_predicted_target;
    reg [4:0] in_rd;
    reg in_rd_write;
    reg [`EDRV32_OP_CLASS_W-1:0] in_op_class;
    reg [`EDRV32_ALU_OP_W-1:0] in_alu_op;
    reg [`EDRV32_BRANCH_OP_W-1:0] in_branch_op;
    reg [`BUS_SZ_W-1:0] in_mem_size;
    reg in_mem_unsigned;
    reg [`EDRV32_MDU_OP_W-1:0] in_mdu_op;
    reg [`EDRV32_CSR_OP_W-1:0] in_csr_op;
    reg [11:0] in_csr_addr;
    reg [31:0] in_csr_src;
    reg [31:0] in_lhs, in_rhs, in_rs2_value, in_imm;
    reg in_resident_bypass_rs1, in_resident_bypass_rs2;
    reg [31:0] in_resident_bypass_pc;
    reg in_late_mdu_rs1, in_late_mdu_rs2;
    reg mdu_bypass_valid;
    reg [31:0] mdu_bypass_value;
    wire late_mdu_stall;
    reg in_late_load_rs1, in_late_load_rs2;
    reg [31:0] in_late_load_rs1_pc, in_late_load_rs2_pc;
    reg load_bypass_valid;
    reg [31:0] load_bypass_pc;
    reg [31:0] load_bypass_value;
    reg in_late_load_rs1_token_valid, in_late_load_rs2_token_valid;
    reg queue_rs1_ready, queue_rs2_ready;
    reg queue_rs1_stored_ready, queue_rs2_stored_ready;
    reg [31:0] queue_rs1_value, queue_rs2_value;
    reg [31:0] queue_rs1_stored_value, queue_rs2_stored_value;
    reg result_bypass_valid, result_bypass_ready;
    reg [31:0] result_bypass_pc, result_bypass_value;
    wire late_load_stall;
    reg in_fence, in_fencei, in_mret, in_wfi;
    reg in_exception_valid;
    reg [`EDRV32_EXC_CAUSE_W-1:0] in_exception_cause;
    reg [31:0] in_exception_tval;
    wire redirect_valid;
    reg redirect_ready;
    wire [31:0] redirect_target;
    wire younger_kill;
    wire predictor_update_valid;
    wire [31:0] predictor_update_pc;
    wire predictor_update_is_conditional;
    wire predictor_update_is_unconditional;
    wire predictor_update_taken;
    wire [31:0] predictor_update_target;
    wire predictor_update_ras_push;
    wire predictor_update_ras_pop;
    wire [31:0] predictor_update_link_addr;
    wire mdu_req_valid;
    reg mdu_req_ready;
    wire [`EDRV32_MDU_OP_W-1:0] mdu_req_op;
    wire [31:0] mdu_req_lhs, mdu_req_rhs;
    wire [31:0] mul_lhs, mul_rhs;
    wire [4:0] mdu_req_rd;
    wire mdu_req_fire;
    wire candidate_valid, candidate_ready;
    wire [31:0] candidate_pc, candidate_instr;
    wire candidate_is_compressed;
    wire [`EDRV32_EPOCH_W-1:0] candidate_epoch;
    wire [4:0] candidate_rd;
    wire candidate_rd_write;
    wire [`EDRV32_OP_CLASS_W-1:0] candidate_op_class;
    wire [31:0] candidate_result;
    wire candidate_result_ready;
    wire [31:0] candidate_mem_addr;
    wire [`BUS_SZ_W-1:0] candidate_mem_size;
    wire candidate_mem_unsigned;
    wire [31:0] candidate_store_data;
    wire candidate_mdu_token;
    wire [`EDRV32_CSR_OP_W-1:0] candidate_csr_op;
    wire [11:0] candidate_csr_addr;
    wire [31:0] candidate_csr_src;
    wire candidate_fence, candidate_fencei, candidate_mret, candidate_wfi;
    wire candidate_exception_valid;
    wire [`EDRV32_EXC_CAUSE_W-1:0] candidate_exception_cause;
    wire [31:0] candidate_exception_tval;
    wire out_valid;
    reg out_accept;
    wire [31:0] out_pc, out_instr;
    wire out_is_compressed;
    wire [`EDRV32_EPOCH_W-1:0] out_epoch;
    wire [4:0] out_rd;
    wire out_rd_write;
    wire [`EDRV32_OP_CLASS_W-1:0] out_op_class;
    wire [31:0] out_result;
    wire out_result_ready;
    wire [31:0] out_mem_addr;
    wire [`BUS_SZ_W-1:0] out_mem_size;
    wire out_mem_unsigned;
    wire [31:0] out_store_data;
    wire out_mdu_token;
    wire [`EDRV32_CSR_OP_W-1:0] out_csr_op;
    wire [11:0] out_csr_addr;
    wire [31:0] out_csr_src;
    wire out_fence, out_fencei, out_mret, out_wfi;
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

    task automatic defaults;
        begin
            in_valid = 1'b0;
            in_pc = 32'h8000_0000;
            in_instr = 32'h0000_0013;
            in_is_compressed = 1'b0;
            in_epoch = 2'd0;
            in_predicted_taken = 1'b0;
            in_predicted_target = 32'd0;
            in_rd = 5'd0;
            in_rd_write = 1'b0;
            in_op_class = `EDRV32_OP_NONE;
            in_alu_op = `EDRV32_ALU_ADD;
            in_branch_op = `EDRV32_BRANCH_NONE;
            in_mem_size = `BUS_SZ_WORD;
            in_mem_unsigned = 1'b0;
            in_mdu_op = `EDRV32_MDU_MUL;
            in_csr_op = `EDRV32_CSR_NONE;
            in_csr_addr = 12'd0;
            in_csr_src = 32'd0;
            in_lhs = 32'd0;
            in_rhs = 32'd0;
            in_rs2_value = 32'd0;
            in_resident_bypass_rs1 = 1'b0;
            in_resident_bypass_rs2 = 1'b0;
            in_resident_bypass_pc = 32'd0;
            in_late_mdu_rs1 = 1'b0;
            in_late_mdu_rs2 = 1'b0;
            mdu_bypass_valid = 1'b0;
            mdu_bypass_value = 32'd0;
            in_late_load_rs1 = 1'b0;
            in_late_load_rs2 = 1'b0;
            in_late_load_rs1_pc = 32'd0;
            in_late_load_rs2_pc = 32'd0;
            load_bypass_valid = 1'b0;
            load_bypass_pc = 32'd0;
            load_bypass_value = 32'd0;
            in_late_load_rs1_token_valid = 1'b0;
            in_late_load_rs2_token_valid = 1'b0;
            queue_rs1_ready = 1'b0;
            queue_rs2_ready = 1'b0;
            queue_rs1_stored_ready = 1'b0;
            queue_rs2_stored_ready = 1'b0;
            queue_rs1_value = 32'd0;
            queue_rs2_value = 32'd0;
            queue_rs1_stored_value = 32'd0;
            queue_rs2_stored_value = 32'd0;
            result_bypass_valid = 1'b0;
            result_bypass_ready = 1'b0;
            result_bypass_pc = 32'd0;
            result_bypass_value = 32'd0;
            in_imm = 32'd0;
            in_fence = 1'b0;
            in_fencei = 1'b0;
            in_mret = 1'b0;
            in_wfi = 1'b0;
            in_exception_valid = 1'b0;
            in_exception_cause = `EDRV32_EXC_ILLEGAL_INSTR;
            in_exception_tval = 32'd0;
        end
    endtask

    task automatic run_mdu_consumer;
        input [`EDRV32_ALU_OP_W-1:0] operation;
        input [31:0] lhs;
        input [31:0] rhs;
        input [1:0] mdu_sources;
        input [31:0] completed_value;
        input [31:0] expected;
        begin
            @(negedge clk);
            defaults();
            in_valid = 1'b1;
            in_op_class = `EDRV32_OP_ALU;
            in_alu_op = operation;
            in_lhs = lhs;
            in_rhs = rhs;
            in_rs2_value = rhs;
            in_late_mdu_rs1 = mdu_sources[0];
            in_late_mdu_rs2 = mdu_sources[1];
            mdu_bypass_value = completed_value;
            #1;
            check_true(!in_ready && late_mdu_stall && !late_load_stall &&
                       !mdu_req_valid,
                       "early MDU consumer waits in EX without counting a Load stall");
            mdu_bypass_valid = 1'b1;
            #1;
            check_true(in_ready && !late_mdu_stall,
                       "registered MDU completion releases EX on arrival");
            @(posedge clk); #1;
            defaults();
            check_true(out_valid && out_result == expected,
                       "early MDU operand replaces stale decoded payload");
            drain_output();
        end
    endtask

    task automatic run_queued_branch;
        input [`EDRV32_BRANCH_OP_W-1:0] operation;
        input [31:0] lhs;
        input [31:0] rhs;
        input [1:0] load_sources;
        reg expected_taken;
        reg equality_operation;
        begin
            case (operation)
                `EDRV32_BRANCH_EQ: expected_taken = (lhs == rhs);
                `EDRV32_BRANCH_NE: expected_taken = (lhs != rhs);
                `EDRV32_BRANCH_LT: expected_taken = ($signed(lhs) < $signed(rhs));
                `EDRV32_BRANCH_GE: expected_taken = ($signed(lhs) >= $signed(rhs));
                `EDRV32_BRANCH_LTU: expected_taken = (lhs < rhs);
                default: expected_taken = (lhs >= rhs);
            endcase
            equality_operation = (operation == `EDRV32_BRANCH_EQ) ||
                                 (operation == `EDRV32_BRANCH_NE);
            @(negedge clk);
            defaults();
            in_valid = 1'b1;
            in_pc = 32'h8000_0900;
            in_instr = 32'h0020_8463;
            in_op_class = `EDRV32_OP_BRANCH;
            in_branch_op = operation;
            in_lhs = lhs;
            in_rs2_value = rhs;
            in_imm = 32'd8;
            in_late_load_rs1 = load_sources[0];
            in_late_load_rs2 = load_sources[1];
            in_late_load_rs1_token_valid = load_sources[0];
            in_late_load_rs2_token_valid = load_sources[1];
            queue_rs1_value = lhs;
            queue_rs2_value = rhs;
            // Stored payload is deliberately stale on response arrival.
            queue_rs1_stored_value = ~lhs;
            queue_rs2_stored_value = ~rhs;
            redirect_ready = 1'b1;
            #1;
            check_true(!in_ready && late_load_stall && !predictor_update_valid,
                       "queued branch waits for matching successful completion");
            queue_rs1_ready = load_sources[0];
            queue_rs2_ready = load_sources[1];
            #1;
            if (equality_operation) begin
                check_true(in_ready && !late_load_stall && predictor_update_valid &&
                           predictor_update_taken == expected_taken &&
                           redirect_valid == expected_taken,
                           "BEQ/BNE uses arriving response before stored payload updates");
            end else begin
                check_true(!in_ready && late_load_stall && !predictor_update_valid,
                           "ordered branch retains its capture boundary");
                @(posedge clk); #1;
                queue_rs1_ready = 1'b0;
                queue_rs2_ready = 1'b0;
                #1;
                check_true(in_ready && predictor_update_valid &&
                           predictor_update_taken == expected_taken,
                           "ordered branch compares locally captured operands");
            end
            @(posedge clk); #1;
            defaults();
            check_true(out_valid && out_op_class == `EDRV32_OP_BRANCH,
                       "queued branch transfers one executed packet");
            drain_output();
        end
    endtask

    task automatic drain_output;
        begin
            out_accept = 1'b1;
            @(posedge clk); #1;
            out_accept = 1'b0;
            check_true(!out_valid, "EX output drained");
        end
    endtask

    edrv32_ex_stage #(.MUL_CAPTURE_LIVE_LOAD(1)) u_dut (
        .clk_i(clk),
        .rst_n_i(rst_n),
        .valid_i(in_valid),
        .ready_o(in_ready),
        .pc_i(in_pc),
        .instr_i(in_instr),
        .is_compressed_i(in_is_compressed),
        .epoch_i(in_epoch),
        .predicted_taken_i(in_predicted_taken),
        .predicted_target_i(in_predicted_target),
        .rd_i(in_rd),
        .rd_write_i(in_rd_write),
        .op_class_i(in_op_class),
        .alu_op_i(in_alu_op),
        .branch_op_i(in_branch_op),
        .mem_size_i(in_mem_size),
        .mem_unsigned_i(in_mem_unsigned),
        .mdu_op_i(in_mdu_op),
        .csr_op_i(in_csr_op),
        .csr_addr_i(in_csr_addr),
        .csr_src_i(in_csr_src),
        .lhs_i(in_lhs),
        .rhs_i(in_rhs),
        .rs2_value_i(in_rs2_value),
        .resident_bypass_rs1_i(in_resident_bypass_rs1),
        .resident_bypass_rs2_i(in_resident_bypass_rs2),
        .resident_bypass_pc_i(in_resident_bypass_pc),
        .late_mdu_rs1_i(in_late_mdu_rs1),
        .late_mdu_rs2_i(in_late_mdu_rs2),
        .late_load_rs1_i(in_late_load_rs1),
        .late_load_rs2_i(in_late_load_rs2),
        .late_load_rs1_pc_i(in_late_load_rs1_pc),
        .late_load_rs2_pc_i(in_late_load_rs2_pc),
        .late_load_rs1_token_valid_i(in_late_load_rs1_token_valid),
        .late_load_rs2_token_valid_i(in_late_load_rs2_token_valid),
        .imm_i(in_imm),
        .fence_i(in_fence),
        .fencei_i(in_fencei),
        .mret_i(in_mret),
        .wfi_i(in_wfi),
        .exception_valid_i(in_exception_valid),
        .exception_cause_i(in_exception_cause),
        .exception_tval_i(in_exception_tval),
        .load_bypass_valid_i(load_bypass_valid),
        .load_bypass_pc_i(load_bypass_pc),
        .load_bypass_value_i(load_bypass_value),
        .load_queue_rs1_ready_i(queue_rs1_ready),
        .load_queue_rs1_value_i(queue_rs1_value),
        .load_queue_rs1_stored_ready_i(queue_rs1_stored_ready),
        .load_queue_rs1_stored_value_i(queue_rs1_stored_value),
        .load_queue_rs2_ready_i(queue_rs2_ready),
        .load_queue_rs2_value_i(queue_rs2_value),
        .load_queue_rs2_stored_ready_i(queue_rs2_stored_ready),
        .load_queue_rs2_stored_value_i(queue_rs2_stored_value),
        .result_bypass_valid_i(result_bypass_valid),
        .result_bypass_ready_i(result_bypass_ready),
        .result_bypass_pc_i(result_bypass_pc),
        .result_bypass_value_i(result_bypass_value),
        .late_load_stall_o(late_load_stall),
        .mdu_bypass_valid_i(mdu_bypass_valid),
        .mdu_bypass_value_i(mdu_bypass_value),
        .late_mdu_stall_o(late_mdu_stall),
        .redirect_valid_o(redirect_valid),
        .redirect_ready_i(redirect_ready),
        .redirect_target_o(redirect_target),
        .younger_kill_o(younger_kill),
        .predictor_update_valid_o(predictor_update_valid),
        .predictor_update_pc_o(predictor_update_pc),
        .predictor_update_is_conditional_o(predictor_update_is_conditional),
        .predictor_update_is_unconditional_o(predictor_update_is_unconditional),
        .predictor_update_taken_o(predictor_update_taken),
        .predictor_update_target_o(predictor_update_target),
        .direction_mispredict_o(), .target_mispredict_o(),
        .predictor_update_ras_push_o(predictor_update_ras_push),
        .predictor_update_ras_pop_o(predictor_update_ras_pop),
        .predictor_update_link_addr_o(predictor_update_link_addr),
        .mdu_req_valid_o(mdu_req_valid),
        .mdu_req_ready_i(mdu_req_ready),
        .mdu_req_op_o(mdu_req_op),
        .mdu_req_lhs_o(mdu_req_lhs),
        .mdu_req_rhs_o(mdu_req_rhs),
        .mdu_req_mul_lhs_o(mul_lhs),
        .mdu_req_mul_rhs_o(mul_rhs),
        .mdu_req_div_lhs_o(), .mdu_req_div_rhs_o(),
        .mdu_req_rd_o(mdu_req_rd),
        .mdu_req_fire_o(mdu_req_fire),
        .result_valid_o(out_valid),
        .result_ready_i(out_accept),
        .result_pc_o(out_pc),
        .result_instr_o(out_instr),
        .result_is_compressed_o(out_is_compressed),
        .result_epoch_o(out_epoch),
        .result_rd_o(out_rd),
        .result_rd_write_o(out_rd_write),
        .result_op_class_o(out_op_class),
        .result_value_o(out_result),
        .result_value_ready_o(out_result_ready),
        .result_mem_addr_o(out_mem_addr),
        .result_mem_size_o(out_mem_size),
        .result_mem_unsigned_o(out_mem_unsigned),
        .result_store_data_o(out_store_data),
        .result_mdu_token_o(out_mdu_token),
        .result_csr_op_o(out_csr_op),
        .result_csr_addr_o(out_csr_addr),
        .result_csr_src_o(out_csr_src),
        .result_fence_o(out_fence),
        .result_fencei_o(out_fencei),
        .result_mret_o(out_mret),
        .result_wfi_o(out_wfi),
        .result_exception_valid_o(out_exception_valid),
        .result_exception_cause_o(out_exception_cause),
        .result_exception_tval_o(out_exception_tval),
        .kill_i(kill)
    );


    integer mask;
    initial begin
        checks = 0;
        rst_n = 0;
        defaults();
        redirect_ready = 1;
        mdu_req_ready = 0;
        out_accept = 0;
        kill = 0;
        repeat (3) @(posedge clk);
        @(negedge clk); rst_n = 1;
        for (mask = 1; mask <= 3; mask = mask + 1) begin
            defaults();
            in_valid = 1;
            in_op_class = `EDRV32_OP_MDU;
            in_mdu_op = `EDRV32_MDU_MUL;
            in_instr = 32'h0220_81b3;
            in_rd = 3;
            in_rd_write = 1;
            in_lhs = 7;
            in_rs2_value = 9;
            in_late_load_rs1 = (mask & 1) != 0;
            in_late_load_rs2 = (mask & 2) != 0;
            in_late_load_rs1_token_valid = in_late_load_rs1;
            in_late_load_rs2_token_valid = in_late_load_rs2;
            queue_rs1_ready = in_late_load_rs1;
            queue_rs2_ready = in_late_load_rs2;
            queue_rs1_value = 7;
            queue_rs2_value = 9;
            queue_rs1_stored_value = 111;
            queue_rs2_stored_value = 222;
            mdu_req_ready = 1; #1;
            check_true(!in_ready && !mdu_req_valid,
                       "one-stage MUL cannot launch from live unregistered load response");
            @(posedge clk); #1;
            mdu_req_ready = 0;
            queue_rs1_ready = 0;
            queue_rs2_ready = 0;
            queue_rs1_value = 32'hdead_beef;
            queue_rs2_value = 32'hbad0_ffff;
            repeat (3) begin
                #1;
                check_true(!in_ready && mdu_req_valid && mul_lhs == 7 && mul_rhs == 9,
                           "captured multiply operands survive request backpressure");
                @(posedge clk); #1;
            end
            mdu_req_ready = 1; #1;
            check_true(in_ready && mdu_req_fire && mul_lhs == 7 && mul_rhs == 9,
                       "captured load operands launch exactly when MDU accepts");
            @(posedge clk); #1;
            defaults();
            check_true(out_valid && out_mdu_token,
                       "accepted one-stage MUL emits its in-order token");
            drain_output();
        end

        defaults();
        in_valid = 1;
        in_op_class = `EDRV32_OP_MDU;
        in_rd_write = 1;
        in_rd = 3;
        in_late_load_rs1 = 1;
        in_late_load_rs1_token_valid = 1;
        queue_rs1_ready = 1;
        queue_rs1_stored_ready = 1;
        queue_rs1_value = 32'hdead_beef;
        queue_rs1_stored_value = 23;
        in_rs2_value = 4;
        mdu_req_ready = 1; #1;
        check_true(in_ready && mdu_req_fire && mul_lhs == 23 && mul_rhs == 4,
                   "stored queue data feeds short MUL independently of live response data");
        @(posedge clk); #1;
        defaults(); drain_output();

        defaults();
        in_valid = 1;
        in_op_class = `EDRV32_OP_MDU;
        in_rd_write = 1;
        in_rd = 3;
        in_late_load_rs1 = 1;
        in_late_load_rs1_pc = 32'h8000_0450;
        load_bypass_valid = 1;
        load_bypass_pc = 32'h8000_0450;
        load_bypass_value = 17;
        in_rs2_value = 3;
        mdu_req_ready = 1; #1;
        check_true(!mdu_req_valid && !in_ready,
                   "legacy load completion also crosses the local capture boundary");
        @(posedge clk); #1;
        mdu_req_ready = 0;
        load_bypass_valid = 0; #1;
        check_true(mul_lhs == 17, "legacy completion is retained while MDU is blocked");
        kill = 1; #1;
        check_true(!mdu_req_valid && !mdu_req_fire, "kill suppresses short multiplier request");
        @(posedge clk); #1;
        defaults();
        kill = 0;
        in_valid = 1;
        in_op_class = `EDRV32_OP_MDU;
        in_rd_write = 1;
        in_rd = 3;
        in_lhs = 99;
        in_rs2_value = 3;
        mdu_req_ready = 1; #1;
        check_true(in_ready && mul_lhs == 99 && mul_rhs == 3,
                   "new owner cannot inherit a killed operand capture");
        @(posedge clk); #1;
        defaults(); drain_output();

        // Prime the payload register, then clear only its ownership. A new
        // live MDU completion must cross that register before reaching MUL
        // data pins, including while the multiplier request is blocked.
        in_valid = 1;
        in_op_class = `EDRV32_OP_MDU;
        in_rd_write = 1;
        in_rd = 3;
        in_late_mdu_rs1 = 1;
        in_late_mdu_rs2 = 1;
        mdu_req_ready = 0;
        mdu_bypass_valid = 1;
        mdu_bypass_value = 5;
        @(posedge clk); #1;
        kill = 1;
        @(posedge clk); #1;
        kill = 0;
        mdu_bypass_value = 31;
        #1;
        check_true(!mdu_req_valid && mul_lhs == 5 && mul_rhs == 5,
                   "live MDU result stays off registered MUL pins before capture");
        @(posedge clk); #1;
        mdu_bypass_valid = 0;
        mdu_bypass_value = 32'hdead_beef;
        #1;
        check_true(mdu_req_valid && !mdu_req_fire && mul_lhs == 31 && mul_rhs == 31,
                   "captured MDU operands survive live-result bus changes");
        mdu_req_ready = 1; #1;
        check_true(mdu_req_fire && mul_lhs == 31 && mul_rhs == 31,
                   "dependent MUL launches from captured MDU result");
        $display("PASS: short MUL registered-input boundary (%0d checks)", checks);
        $finish;
    end
endmodule
