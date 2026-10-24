`timescale 1ns/1ps
`include "edrv32_isa.vh"
`include "edrv32_uop.vh"
`include "edrv32_bus.vh"
`include "edrv32_exception.vh"

module tb_ex_stage;

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

    edrv32_ex_stage u_dut (
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

    initial begin
        checks = 0;
        rst_n = 1'b0;
        defaults();
        redirect_ready = 1'b1;
        mdu_req_ready = 1'b1;
        out_accept = 1'b0;
        kill = 1'b0;
        repeat (2) @(posedge clk);
        rst_n = 1'b1;
        #1;
        check_true(!out_valid && in_ready, "EX empty after reset");

        // Ordinary ALU instruction has no redirect and is immediately bypassable.
        in_valid = 1'b1;
        in_pc = 32'h8000_0000;
        in_instr = 32'h0020_81b3;
        in_rd = 5'd3;
        in_rd_write = 1'b1;
        in_op_class = `EDRV32_OP_ALU;
        in_alu_op = `EDRV32_ALU_ADD;
        in_lhs = 32'd10;
        in_rhs = 32'd20;
        in_rs2_value = 32'd20;
        #1;
        check_true(in_ready && !redirect_valid && !mdu_req_valid, "ALU side handshakes idle");
        @(posedge clk); #1;
        defaults();
        check_true(out_valid && out_result == 32'd30 && out_result_ready,
                   "EX registers ready ALU result");
        check_true(out_rd_write && out_rd == 5'd3 && !out_exception_valid,
                   "EX ALU destination remains architectural");
        drain_output();

        // A consumer refilled behind a forwardable DECODE/EX resident uses
        // the producer's registered EX/MEM1 value without a RAW bubble.
        defaults();
        in_valid = 1'b1;
        in_instr = 32'h0011_8213; // addi x4,x3,1
        in_rd = 5'd4;
        in_rd_write = 1'b1;
        in_op_class = `EDRV32_OP_ALU;
        in_alu_op = `EDRV32_ALU_ADD;
        in_lhs = 32'hdead_beef;
        in_rhs = 32'd1;
        in_resident_bypass_rs1 = 1'b1;
        in_resident_bypass_pc = 32'h8000_0000;
        result_bypass_valid = 1'b1;
        result_bypass_ready = 1'b1;
        result_bypass_pc = 32'h8000_0004;
        result_bypass_value = 32'd30;
        #1;
        check_true(!in_ready && late_load_stall,
                   "EX rejects a resident result from another producer PC");
        result_bypass_pc = 32'h8000_0000;
        #1;
        check_true(in_ready && !late_load_stall,
                   "EX accepts the matching registered resident result");
        @(posedge clk); #1;
        defaults();
        check_true(out_valid && out_result_ready && out_result == 32'd31,
                   "EX computes with the resident ALU forward value");
        drain_output();

        // A MEM2 load-dependent ALU uop resides in EX while the registered
        // cache response is pending, then executes on the matching response
        // without exposing raw tag/data RAM outputs.
        defaults();
        in_valid = 1'b1;
        in_instr = 32'h0010_8213; // addi x4,x1,1
        in_rd = 5'd4;
        in_rd_write = 1'b1;
        in_op_class = `EDRV32_OP_ALU;
        in_alu_op = `EDRV32_ALU_ADD;
        in_lhs = 32'hdead_beef;
        in_rhs = 32'd1;
        in_late_load_rs1 = 1'b1;
        in_late_load_rs1_pc = 32'h8000_0100;
        #1;
        check_true(!in_ready && late_load_stall,
                   "EX holds an early-issued load consumer before response");
        load_bypass_valid = 1'b1;
        load_bypass_pc = 32'h8000_0104;
        load_bypass_value = 32'd41;
        #1;
        check_true(!in_ready && late_load_stall,
                   "EX rejects a late load response from another producer PC");
        load_bypass_pc = 32'h8000_0100;
        #1;
        check_true(in_ready && !late_load_stall,
                   "EX accepts the matching registered load response");
        @(posedge clk); #1;
        defaults();
        check_true(out_valid && out_result_ready && out_result == 32'd42,
                   "EX computes with the late load value");
        drain_output();

        // The matching response must also survive an occupied EX/MEM1 slot.
        defaults();
        in_valid = 1'b1;
        in_op_class = `EDRV32_OP_ALU;
        in_rd = 5'd9;
        in_rd_write = 1'b1;
        in_lhs = 32'd2;
        in_rhs = 32'd3;
        @(posedge clk); #1;
        defaults();
        in_valid = 1'b1;
        in_instr = 32'h0010_8213; // addi x4,x1,1
        in_rd = 5'd4;
        in_rd_write = 1'b1;
        in_op_class = `EDRV32_OP_ALU;
        in_late_load_rs1 = 1'b1;
        in_late_load_rs1_pc = 32'h8000_0200;
        in_rhs = 32'd1;
        load_bypass_valid = 1'b1;
        load_bypass_pc = 32'h8000_0200;
        load_bypass_value = 32'd50;
        #1;
        check_true(!in_ready && !late_load_stall,
                   "full EX output blocks but observes late load response");
        @(posedge clk); #1;
        load_bypass_valid = 1'b0;
        out_accept = 1'b1;
        #1;
        check_true(in_ready && !late_load_stall,
                   "EX replays captured late value after response disappears");
        @(posedge clk); #1;
        out_accept = 1'b0;
        defaults();
        check_true(out_valid && out_result == 32'd51,
                   "captured late value survives EX backpressure");
        drain_output();

        // Store address and store data use different operands. A late rs2 load
        // must replace only the store payload, never the immediate address.
        defaults();
        in_valid = 1'b1;
        in_instr = 32'h0020_a223; // sw x2,4(x1)
        in_op_class = `EDRV32_OP_STORE;
        in_alu_op = `EDRV32_ALU_ADD;
        in_lhs = 32'h1000_0000;
        in_rhs = 32'd4;
        in_rs2_value = 32'hbad0_bad0;
        in_late_load_rs2 = 1'b1;
        in_late_load_rs2_pc = 32'h8000_0300;
        load_bypass_valid = 1'b1;
        load_bypass_pc = 32'h8000_0300;
        load_bypass_value = 32'h1234_5678;
        #1;
        check_true(in_ready && !late_load_stall,
                   "late load store-data dependency is ready");
        @(posedge clk); #1;
        defaults();
        check_true(out_mem_addr == 32'h1000_0004 &&
                   out_store_data == 32'h1234_5678,
                   "late rs2 forwarding preserves store address and data");
        drain_output();

        // Taken BEQ cannot advance until its registered redirect slot is ready.
        defaults();
        in_valid = 1'b1;
        in_pc = 32'h8000_0100;
        in_instr = 32'h0020_8463;
        in_op_class = `EDRV32_OP_BRANCH;
        in_branch_op = `EDRV32_BRANCH_EQ;
        in_lhs = 32'd5;
        in_rs2_value = 32'd5;
        in_imm = 32'd8;
        redirect_ready = 1'b0;
        #1;
        check_true(redirect_valid && redirect_target == 32'h8000_0108,
                   "EX resolves taken BEQ target locally");
        check_true(!in_ready && !younger_kill && !predictor_update_valid,
                   "Full redirect slot holds branch and predictor training");
        redirect_ready = 1'b1;
        #1;
        check_true(in_ready && younger_kill && predictor_update_valid,
                   "Accepted mispredict trains predictor and kills younger work");
        check_true(predictor_update_pc == 32'h8000_0100 &&
                   predictor_update_is_conditional &&
                   !predictor_update_is_unconditional && predictor_update_taken &&
                   predictor_update_target == 32'h8000_0108,
                   "Accepted BEQ emits the complete predictor training payload");
        @(posedge clk); #1;
        defaults();
        check_true(out_valid && out_op_class == `EDRV32_OP_BRANCH,
                   "Resolved branch continues toward commit");
        drain_output();

        // Every branch reserves the redirect slot before its compare result is
        // known.  A correct prediction therefore cannot make EX ready depend
        // combinationally on the branch comparator/mispredict result.
        defaults();
        in_valid = 1'b1;
        in_pc = 32'h8000_0180;
        in_instr = 32'h0020_8463;
        in_op_class = `EDRV32_OP_BRANCH;
        in_branch_op = `EDRV32_BRANCH_EQ;
        in_lhs = 32'd5;
        in_rs2_value = 32'd6;
        in_imm = 32'd8;
        redirect_ready = 1'b0;
        #1;
        check_true(!redirect_valid && !in_ready && !younger_kill,
                   "Correctly predicted branch reserves a full redirect slot");
        redirect_ready = 1'b1;
        #1;
        check_true(in_ready && !redirect_valid && !younger_kill,
                   "Correctly predicted branch advances when redirect slot is ready");
        @(posedge clk); #1;
        defaults();
        check_true(out_valid && out_op_class == `EDRV32_OP_BRANCH,
                   "Correctly predicted branch continues toward commit");
        drain_output();

        // A stale BTB taken prediction on a non-control instruction redirects
        // to the scalar fallthrough instead of being silently trusted.
        defaults();
        in_valid = 1'b1;
        in_pc = 32'h8000_0200;
        in_instr = 32'h0000_0013;
        in_op_class = `EDRV32_OP_ALU;
        in_predicted_taken = 1'b1;
        in_predicted_target = 32'h9000_0000;
        redirect_ready = 1'b0;
        #1;
        check_true(redirect_valid && redirect_target == 32'h8000_0204,
                   "EX repairs false predicted-taken metadata");
        check_true(!in_ready && !younger_kill,
                   "Predicted-taken metadata reserves a full redirect slot");
        redirect_ready = 1'b1;
        #1;
        check_true(in_ready && younger_kill,
                   "Accepted stale prediction kills younger DECODE work");
        @(posedge clk); #1;
        defaults();
        drain_output();

        // Compressed JAL writes pc+2 and redirects to pc+imm.
        defaults();
        in_valid = 1'b1;
        in_pc = 32'h8000_0300;
        in_instr = 32'h0080_00ef; // canonical jal x1,+8
        in_is_compressed = 1'b1;
        in_rd = 5'd1;
        in_rd_write = 1'b1;
        in_op_class = `EDRV32_OP_JUMP;
        in_lhs = in_pc;
        in_rhs = 32'd8;
        in_imm = 32'd8;
        #1;
        check_true(redirect_valid && redirect_target == 32'h8000_0308,
                   "EX JAL target");
        @(posedge clk); #1;
        defaults();
        check_true(out_result == 32'h8000_0302 && out_result_ready,
                   "Compressed JAL link uses instruction length");
        drain_output();

        // A pre-existing exception on a control-flow uop suppresses both
        // redirect repair and predictor training.
        defaults();
        in_valid = 1'b1;
        in_pc = 32'h8000_0380;
        in_instr = 32'h0020_8463;
        in_op_class = `EDRV32_OP_BRANCH;
        in_branch_op = `EDRV32_BRANCH_EQ;
        in_lhs = 32'd7;
        in_rs2_value = 32'd7;
        in_exception_valid = 1'b1;
        in_exception_cause = `EDRV32_EXC_ILLEGAL_INSTR;
        #1;
        check_true(in_ready && !redirect_valid && !predictor_update_valid,
                   "Incoming exception suppresses branch predictor training");
        @(posedge clk); #1;
        defaults();
        check_true(out_exception_valid,
                   "Excepting branch remains an exception packet");
        drain_output();

        // Misaligned word load becomes an exception packet and never bypasses.
        defaults();
        in_valid = 1'b1;
        in_pc = 32'h8000_0400;
        in_instr = 32'h0000_a183;
        in_rd = 5'd3;
        in_rd_write = 1'b1;
        in_op_class = `EDRV32_OP_LOAD;
        in_lhs = 32'h1000_0001;
        in_rhs = 32'd0;
        in_mem_size = `BUS_SZ_WORD;
        #1;
        check_true(!predictor_update_valid,
                   "Misaligned load cannot train branch predictor");
        @(posedge clk); #1;
        defaults();
        check_true(out_exception_valid && out_exception_cause == `EDRV32_EXC_LOAD_MISALIGNED,
                   "EX detects load alignment");
        check_true(out_mem_addr == 32'h1000_0001 &&
                   out_exception_tval == 32'd0 && !out_rd_write &&
                   !out_result_ready,
                   "Misaligned load carries address for MEM1 tval reconstruction");
        drain_output();

        // A Load-fed DIV/REM captures the arriving value locally before the
        // long divider request cone is allowed to issue.
        defaults();
        in_valid = 1'b1;
        in_pc = 32'h8000_04f0;
        in_rd = 5'd3;
        in_rd_write = 1'b1;
        in_op_class = `EDRV32_OP_MDU;
        in_mdu_op = `EDRV32_MDU_DIV;
        in_late_load_rs1 = 1'b1;
        in_late_load_rs1_pc = 32'h8000_0200;
        in_rs2_value = 32'd5;
        load_bypass_valid = 1'b1;
        load_bypass_pc = 32'h8000_0200;
        load_bypass_value = 32'd45;
        mdu_req_ready = 1'b1;
        #1;
        check_true(!in_ready && late_load_stall && !mdu_req_valid,
                   "Load-fed DIV captures before request issue");
        @(posedge clk); #1;
        load_bypass_valid = 1'b0;
        check_true(in_ready && !late_load_stall && mdu_req_fire &&
                   mdu_req_lhs == 32'd45 && mdu_req_rhs == 32'd5,
                   "captured Load value issues DIV on the following cycle");
        @(posedge clk); #1;
        defaults();
        check_true(out_mdu_token && out_op_class == `EDRV32_OP_MDU,
                   "captured DIV registers its authorization token");
        drain_output();

        run_mdu_consumer(`EDRV32_ALU_ADD, 32'd111, 32'd5, 2'b01, 32'd63, 32'd68);
        run_mdu_consumer(`EDRV32_ALU_ADD, 32'd5, 32'd111, 2'b10, 32'd63, 32'd68);
        run_mdu_consumer(`EDRV32_ALU_ADD, 32'd111, 32'd222, 2'b11, 32'd63, 32'd126);
        run_mdu_consumer(`EDRV32_ALU_SUB, 32'd111, 32'd5, 2'b01, 32'd63, 32'd58);
        run_mdu_consumer(`EDRV32_ALU_SRA, 32'd111, 32'd2, 2'b01,
                         32'hffff_fff0, 32'hffff_fffc);
        run_mdu_consumer(`EDRV32_ALU_SRL, 32'd111, 32'd4, 2'b01,
                         32'h8000_0000, 32'h0800_0000);

        // Store-data forwarding must leave the address immediate intact.
        @(negedge clk);
        defaults();
        in_valid = 1'b1;
        in_op_class = `EDRV32_OP_STORE;
        in_lhs = 32'h1000_0000;
        in_rhs = 32'd4;
        in_rs2_value = 32'd0;
        in_late_mdu_rs2 = 1'b1;
        mdu_bypass_valid = 1'b1;
        mdu_bypass_value = 32'hfeed_0042;
        #1;
        check_true(in_ready, "MDU Store data is available on completion");
        @(posedge clk); #1;
        defaults();
        check_true(out_mem_addr == 32'h1000_0004 && out_store_data == 32'hfeed_0042,
                   "MDU Store forwarding preserves address and payload independently");
        drain_output();

        // The MDU and a queued Load can be different sources of one ADD.
        @(negedge clk);
        defaults();
        in_valid = 1'b1;
        in_op_class = `EDRV32_OP_ALU;
        in_alu_op = `EDRV32_ALU_ADD;
        in_late_mdu_rs1 = 1'b1;
        in_late_load_rs2 = 1'b1;
        in_late_load_rs2_token_valid = 1'b1;
        mdu_bypass_valid = 1'b1;
        mdu_bypass_value = 32'd3;
        #1;
        check_true(!in_ready && late_load_stall && !late_mdu_stall,
                   "first MDU completion is held while the Load is pending");
        @(posedge clk); #1;
        mdu_bypass_valid = 1'b0;
        mdu_bypass_value = 32'd100;
        queue_rs2_ready = 1'b1;
        queue_rs2_value = 32'd7;
        #1;
        check_true(in_ready && !late_mdu_stall,
                   "second producer releases EX after MDU slot is gone");
        @(posedge clk); #1;
        defaults();
        check_true(out_result == 32'd10, "MDU replay survives a changing result bus");
        drain_output();

        // Fill the output slot, then complete an MDU-fed consumer behind it.
        @(negedge clk);
        defaults();
        in_valid = 1'b1;
        in_op_class = `EDRV32_OP_ALU;
        in_lhs = 32'd7;
        @(posedge clk); #1;
        defaults();
        in_valid = 1'b1;
        in_op_class = `EDRV32_OP_ALU;
        in_late_mdu_rs1 = 1'b1;
        in_rhs = 32'd5;
        mdu_bypass_valid = 1'b1;
        mdu_bypass_value = 32'd42;
        #1;
        check_true(!in_ready, "full output slot holds a completed MDU consumer");
        @(posedge clk); #1;
        mdu_bypass_valid = 1'b0;
        mdu_bypass_value = 32'd999;
        out_accept = 1'b1;
        #1;
        check_true(in_ready && !late_mdu_stall,
                   "output capacity releases the captured MDU consumer");
        @(posedge clk); #1;
        out_accept = 1'b0;
        defaults();
        check_true(out_result == 32'd47, "backpressure replays the original MDU value");
        drain_output();

        // A kill must remove the captured result from the next EX instruction.
        @(negedge clk);
        defaults();
        in_valid = 1'b1;
        in_op_class = `EDRV32_OP_ALU;
        in_late_mdu_rs1 = 1'b1;
        in_late_load_rs2 = 1'b1;
        in_late_load_rs2_token_valid = 1'b1;
        mdu_bypass_valid = 1'b1;
        mdu_bypass_value = 32'd88;
        @(posedge clk); #1;
        kill = 1'b1;
        @(posedge clk); #1;
        kill = 1'b0;
        defaults();
        in_valid = 1'b1;
        in_op_class = `EDRV32_OP_ALU;
        in_late_mdu_rs1 = 1'b1;
        #1;
        check_true(!in_ready && late_mdu_stall,
                   "killed MDU replay cannot satisfy a later producer");
        defaults();
        @(posedge clk); #1;

        run_queued_branch(`EDRV32_BRANCH_EQ, 32'd37, 32'd37, 2'b01);
        run_queued_branch(`EDRV32_BRANCH_EQ, 32'd37, 32'd38, 2'b01);
        run_queued_branch(`EDRV32_BRANCH_NE, 32'hffff_ff80, 32'hffff_ff80, 2'b01);
        run_queued_branch(`EDRV32_BRANCH_NE, 32'hffff_ff80, 32'd128, 2'b01);
        run_queued_branch(`EDRV32_BRANCH_EQ, 32'h8000_0000, 32'h8000_0000, 2'b10);
        run_queued_branch(`EDRV32_BRANCH_EQ, 32'd1, 32'd2, 2'b10);
        run_queued_branch(`EDRV32_BRANCH_NE, 32'h1234_5678, 32'h1234_5678, 2'b10);
        run_queued_branch(`EDRV32_BRANCH_NE, 32'h1234_5678, 32'h1234_5679, 2'b10);
        run_queued_branch(`EDRV32_BRANCH_EQ, 32'hdead_beef, 32'hdead_beef, 2'b11);
        run_queued_branch(`EDRV32_BRANCH_NE, 32'd3, 32'd4, 2'b11);
        run_queued_branch(`EDRV32_BRANCH_LT, 32'hffff_ffff, 32'd1, 2'b01);
        run_queued_branch(`EDRV32_BRANCH_GE, 32'h8000_0000, 32'd0, 2'b10);
        run_queued_branch(`EDRV32_BRANCH_LTU, 32'hffff_ffff, 32'd1, 2'b01);
        run_queued_branch(`EDRV32_BRANCH_GEU, 32'd7, 32'd7, 2'b11);

        // Redirect backpressure must preserve a one-cycle arriving response.
        @(negedge clk);
        defaults();
        in_valid = 1'b1;
        in_instr = 32'h0020_8463;
        in_op_class = `EDRV32_OP_BRANCH;
        in_branch_op = `EDRV32_BRANCH_EQ;
        in_lhs = 32'd99;
        in_rs2_value = 32'd42;
        in_late_load_rs1 = 1'b1;
        in_late_load_rs1_token_valid = 1'b1;
        queue_rs1_ready = 1'b1;
        queue_rs1_value = 32'd42;
        redirect_ready = 1'b0;
        #1;
        check_true(!in_ready && !predictor_update_valid,
                   "live equality branch still reserves redirect capacity");
        @(posedge clk); #1;
        queue_rs1_ready = 1'b0;
        queue_rs1_value = 32'd99;
        redirect_ready = 1'b1;
        #1;
        check_true(in_ready && predictor_update_valid && predictor_update_taken,
                   "held equality branch replays captured response after live bus changes");
        @(posedge clk); #1;
        defaults();
        drain_output();

        // Two producers complete separately; the first value must be retained.
        @(negedge clk);
        defaults();
        in_valid = 1'b1;
        in_instr = 32'h0020_8463;
        in_op_class = `EDRV32_OP_BRANCH;
        in_branch_op = `EDRV32_BRANCH_EQ;
        in_late_load_rs1 = 1'b1;
        in_late_load_rs2 = 1'b1;
        in_late_load_rs1_token_valid = 1'b1;
        in_late_load_rs2_token_valid = 1'b1;
        queue_rs2_ready = 1'b1;
        queue_rs2_value = 32'hcafe_0007;
        redirect_ready = 1'b1;
        #1;
        check_true(!in_ready && late_load_stall,
                   "one arriving source cannot release a two-load branch");
        @(posedge clk); #1;
        queue_rs2_ready = 1'b0;
        queue_rs2_value = 32'd0;
        queue_rs1_ready = 1'b1;
        queue_rs1_value = 32'hcafe_0007;
        #1;
        check_true(in_ready && predictor_update_valid && predictor_update_taken,
                   "second response compares against first captured producer");
        @(posedge clk); #1;
        defaults();
        drain_output();

        // MDU request holds until accepted and creates exactly one token/fire.
        defaults();
        in_valid = 1'b1;
        in_pc = 32'h8000_0500;
        in_instr = 32'h0220_81b3;
        in_rd = 5'd3;
        in_rd_write = 1'b1;
        in_op_class = `EDRV32_OP_MDU;
        in_mdu_op = `EDRV32_MDU_MUL;
        in_lhs = 32'd7;
        in_rs2_value = 32'd9;
        mdu_req_ready = 1'b0;
        #1;
        check_true(mdu_req_valid && !mdu_req_fire && !in_ready,
                   "MDU backpressure holds EX instruction");
        check_true(mdu_req_lhs == 32'd7 && mdu_req_rhs == 32'd9 && mdu_req_rd == 5'd3,
                   "MDU request payload stable");
        mdu_req_ready = 1'b1;
        #1;
        check_true(mdu_req_fire && in_ready, "MDU request and EX advance are atomic");
        @(posedge clk); #1;
        defaults();
        check_true(out_mdu_token && out_op_class == `EDRV32_OP_MDU && !out_result_ready,
                   "EX registers MDU authorization token");
        drain_output();

        // An existing exception suppresses prediction repair and MDU dispatch.
        defaults();
        in_valid = 1'b1;
        in_pc = 32'h8000_0600;
        in_op_class = `EDRV32_OP_MDU;
        in_rd = 5'd4;
        in_rd_write = 1'b1;
        in_predicted_taken = 1'b1;
        in_predicted_target = 32'hdead_0000;
        in_exception_valid = 1'b1;
        in_exception_cause = `EDRV32_EXC_ILLEGAL_INSTR;
        in_exception_tval = 32'hffff_ffff;
        #1;
        check_true(in_ready && !redirect_valid && !mdu_req_valid,
                   "Exception suppresses EX side requests");
        @(posedge clk); #1;
        defaults();
        check_true(out_exception_valid && !out_rd_write && !out_mdu_token,
                   "Exception packet remains side-effect free");

        // COMMIT/global kill wins over output acceptance and new input.
        out_accept = 1'b1;
        in_valid = 1'b1;
        kill = 1'b1;
        #1;
        check_true(!in_ready && !redirect_valid && !mdu_req_valid,
                   "EX kill blocks all new handshakes");
        @(posedge clk); #1;
        kill = 1'b0;
        out_accept = 1'b0;
        defaults();
        check_true(!out_valid, "EX kill clears valid");

        $display("PASS: EX stage (%0d checks)", checks);
        $finish;
    end

endmodule
