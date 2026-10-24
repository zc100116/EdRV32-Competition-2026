`timescale 1ns/1ps
`include "edrv32_uop.vh"
`include "edrv32_csr.vh"
`include "edrv32_exception.vh"
module tb_mdu_commit;
    reg clk = 0;
    always #5 clk = ~clk;
    reg rst_n = 0;
    reg valid = 0;
    reg token = 0;
    reg [`EDRV32_OP_CLASS_W-1:0] op_class = `EDRV32_OP_ALU;
    reg [4:0] rd = 0;
    reg rd_write = 0;
    reg exception_valid = 0;
    reg irq_ext = 0;
    reg [11:0] csr_addr = 0;
    reg [31:0] csr_src = 0;
    reg req_valid = 0;
    reg [`EDRV32_MDU_OP_W-1:0] req_op = 0;
    reg [31:0] lhs = 0;
    reg [31:0] rhs = 0;
    wire ready, req_ready, slot_valid, authorized, result_complete;
    wire result_valid, result_ready, authorize, cancel, writeback;
    wire [4:0] result_rd, gpr_rd;
    wire [31:0] result_data, gpr_value;
    wire gpr_write, retire, trap, irq_redirect, exc_redirect;
    integer checks = 0;

    edrv32_mdu u_mdu (
        .clk_i(clk), .rst_n_i(rst_n),
        .req_valid_i(req_valid), .req_ready_o(req_ready), .req_op_i(req_op),
        .req_lhs_i(lhs), .req_rhs_i(rhs), .req_div_lhs_i(lhs), .req_div_rhs_i(rhs),
        .req_rd_i(5'd17), .authorize_i(authorize), .cancel_i(cancel),
        .result_valid_o(result_valid), .result_ready_i(result_ready),
        .result_rd_o(result_rd), .result_data_o(result_data),
        .slot_valid_o(slot_valid), .result_complete_o(result_complete),
        .authorized_o(authorized)
    );
    edrv32_commit_stage u_commit (
        .clk_i(clk),
        .rst_n_i(rst_n),
        .valid_i(valid),
        .ready_o(ready),
        .pc_i(32'h80000040),
        .instr_i({(31-(0)+1){1'b0}}),
        .is_compressed_i(1'b0),
        .epoch_i({(`EDRV32_EPOCH_W-1-(0)+1){1'b0}}),
        .rd_i(rd),
        .rd_write_i(rd_write),
        .op_class_i(op_class),
        .result_i(32'd99),
        .result_ready_i(1'b1),
        .mem_addr_i({(31-(0)+1){1'b0}}),
        .mem_size_i({(`BUS_SZ_W-1-(0)+1){1'b0}}),
        .mem_unsigned_i(1'b0),
        .store_data_i({(31-(0)+1){1'b0}}),
        .mem_cacheable_i(1'b0),
        .lsu_token_valid_i(1'b0),
        .lsu_token_i({(`EDRV32_LSU_TOKEN_W-1-(0)+1){1'b0}}),
        .mdu_token_i(token),
        .csr_op_i(`EDRV32_CSR_WRITE),
        .csr_addr_i(csr_addr),
        .csr_src_i(csr_src),
        .fence_i(1'b0),
        .fencei_i(1'b0),
        .mret_i(1'b0),
        .wfi_i(1'b0),
        .exception_valid_i(exception_valid),
        .exception_cause_i(`EDRV32_EXC_ILLEGAL_INSTR),
        .exception_tval_i({(31-(0)+1){1'b0}}),
        .mdu_pending_i(slot_valid),
        .mdu_authorized_i(authorized),
        .mdu_result_valid_i(result_valid),
        .mdu_result_ready_o(result_ready),
        .mdu_result_rd_i(result_rd),
        .mdu_result_data_i(result_data),
        .mdu_authorize_o(authorize),
        .mdu_cancel_o(cancel),
        .mdu_writeback_fire_o(writeback),
        .load_commit_valid_o(),
        .load_commit_token_o(),
        .load_commit_ready_i(1'b1),
        .load_commit_data_i({(31-(0)+1){1'b0}}),
        .load_commit_error_i(1'b0),
        .load_commit_fire_o(),
        .store_commit_valid_o(),
        .store_commit_token_o(),
        .store_commit_ready_i(1'b1),
        .store_commit_error_i(1'b0),
        .store_commit_fire_o(),
        .lsu_queues_empty_i(1'b1),
        .dmem_req_valid_o(),
        .dmem_req_ready_i(1'b1),
        .dmem_req_addr_o(),
        .dmem_req_we_o(),
        .dmem_req_size_o(),
        .dmem_req_wstrb_o(),
        .dmem_req_wdata_o(),
        .dmem_req_cacheable_o(),
        .dmem_resp_valid_i(1'b0),
        .dmem_resp_ready_o(),
        .dmem_resp_rdata_i({(31-(0)+1){1'b0}}),
        .dmem_resp_error_i(1'b0),
        .irq_soft_i(1'b0),
        .irq_timer_i(1'b0),
        .irq_ext_i(irq_ext),
        .time_value_i({(63-(0)+1){1'b0}}),
        .hpm_events_i({(`EDRV32_HPM_EVENT_W-1-(0)+1){1'b0}}),
        .redirect_exception_valid_o(exc_redirect),
        .redirect_exception_target_o(),
        .redirect_interrupt_valid_o(irq_redirect),
        .redirect_interrupt_target_o(),
        .redirect_mret_valid_o(),
        .redirect_mret_target_o(),
        .redirect_fencei_valid_o(),
        .redirect_fencei_target_o(),
        .redirect_event_ready_i(1'b1),
        .flush_younger_lsu_o(),
        .kill_younger_o(),
        .hpm_busy_memory_o(),
        .hpm_busy_other_o(),
        .gpr_write_o(gpr_write),
        .gpr_rd_o(gpr_rd),
        .gpr_value_o(gpr_value),
        .bypass_valid_o(),
        .bypass_write_o(),
        .bypass_ready_o(),
        .bypass_rd_o(),
        .bypass_value_o(),
        .retire_o(retire),
        .retire_pc_o(),
        .retire_instr_o(),
        .retire_exception_o(trap),
        .retire_cause_o(),
        .core_sleep_o()
    );

    task check;
        input condition;
        input [8*96-1:0] message;
        begin
            checks = checks + 1;
            if (!condition) $fatal(1, "%0s", message);
        end
    endtask

    task csr_write;
        input [11:0] address;
        input [31:0] value;
        begin
            @(negedge clk);
            valid = 1; token = 0; rd_write = 0;
            op_class = `EDRV32_OP_CSR; csr_addr = address; csr_src = value;
            @(posedge clk); #1;
            while (!ready) begin @(posedge clk); #1; end
            @(posedge clk); #1;
            valid = 0; op_class = `EDRV32_OP_ALU;
        end
    endtask

    task launch;
        input [`EDRV32_MDU_OP_W-1:0] operation;
        input [31:0] a;
        input [31:0] b;
        begin
            @(negedge clk);
            check(req_ready, "MDU must be empty before launch");
            req_valid = 1; req_op = operation; lhs = a; rhs = b;
            @(posedge clk); #1; req_valid = 0;
        end
    endtask

    task completed;
        begin
            while (!result_complete) @(negedge clk);
            #1;
            check(!result_valid && slot_valid && !authorized,
                  "speculative completion has no architectural write permission");
        end
    endtask

    initial begin
        repeat (3) @(posedge clk);
        @(negedge clk); rst_n = 1;

        // Ready result retires, writes its GPR, and releases ownership together.
        launch(`EDRV32_MDU_MUL, 32'd7, 32'd9);
        completed();
        @(negedge clk); valid = 1; token = 1; rd_write = 1; rd = 17;
        #1;
        check(ready && retire && authorize && writeback && gpr_write &&
              gpr_rd == 17 && gpr_value == 63 && !req_ready,
              "ready token must write exactly on its retirement edge");
        @(posedge clk); #1; valid = 0; token = 0; rd_write = 0;
        check(!slot_valid && !authorized && !result_valid,
              "same-edge retirement frees the MDU slot");

        // A long division keeps the existing authorization and retirement barrier.
        launch(`EDRV32_MDU_DIVU, 32'd100, 32'd7);
        @(negedge clk); valid = 1; token = 1;
        #1;
        check(retire && authorize && !writeback && !result_complete,
              "unfinished token may retire before arithmetic completion");
        @(posedge clk); #1; token = 0; rd_write = 1; rd = 18;
        #1;
        check(authorized && !ready && !retire && !gpr_write,
              "younger normal writer waits behind authorized division");
        while (!result_complete) @(negedge clk);
        #1;
        check(writeback && gpr_write && gpr_rd == 17 && gpr_value == 14 && !retire,
              "late division owns the only write port before younger retirement");
        @(posedge clk); #1;
        check(ready && retire && gpr_write && gpr_rd == 18 && gpr_value == 99,
              "younger retirement resumes after late result");
        @(posedge clk); #1; valid = 0; rd_write = 0;

        // An older synchronous exception cancels a completed speculative multiply.
        launch(`EDRV32_MDU_MUL, 32'd11, 32'd13);
        completed();
        @(negedge clk); valid = 1; exception_valid = 1;
        #1;
        check(exc_redirect && trap && cancel && !authorize && !writeback && !gpr_write,
              "exception must cancel a completed speculative result without writing");
        @(posedge clk); #1; valid = 0; exception_valid = 0;
        check(!slot_valid && !result_valid, "exception cancellation releases slot");

        // IRQ is sampled while COMMIT is empty, then competes with a ready token.
        csr_write(`EDRV32_CSR_MIE, 32'h800);
        csr_write(`EDRV32_CSR_MSTATUS, 32'h8);
        launch(`EDRV32_MDU_MUL, 32'd17, 32'd19);
        completed();
        @(negedge clk); irq_ext = 1;
        repeat (2) @(posedge clk);
        @(negedge clk); valid = 1; token = 1; rd_write = 1; rd = 17;
        #1;
        check(irq_redirect && trap && cancel && !retire && !authorize &&
              !writeback && !gpr_write,
              "IRQ at token retirement must cancel ready result and suppress GPR write");
        @(posedge clk); #1; valid = 0; token = 0; rd_write = 0; irq_ext = 0;
        check(!slot_valid && !result_valid && !authorized,
              "IRQ cancellation clears completed MDU ownership");
        repeat (5) @(posedge clk);
        check(!gpr_write && !writeback, "canceled result cannot leak a late write");
        $display("PASS: MDU/COMMIT retirement and cancellation (%0d checks)", checks);
        $finish;
    end
    initial begin #20000; $fatal(1, "MDU/COMMIT test timeout"); end
endmodule
