`timescale 1ns/1ps
`include "edrv32_uop.vh"

module tb_frontend;

    localparam [31:0] RESET_PC = 32'h8000_0000;

    reg clk, rst_n;
    wire req_valid;
    reg req_ready;
    wire [31:0] req_addr;
    reg resp_valid;
    wire resp_ready;
    reg [31:0] resp_data;
    reg resp_error;
    wire block_valid, block_ready;
    wire [31:0] block_addr, block_data;
    wire block_error;
    wire [`EDRV32_EPOCH_W-1:0] block_epoch;
    wire block_predicted_taken0, block_predicted_taken1;
    wire [31:0] block_predicted_target0, block_predicted_target1;
    wire if1_candidate_valid, if1_candidate_ready;
    wire [31:0] if1_candidate_addr;
    wire [`EDRV32_EPOCH_W-1:0] if1_candidate_epoch;
    wire if1_predicted_taken0 = if1_candidate_addr[2];
    wire [31:0] if1_predicted_target0 = if1_candidate_addr + 32'h0000_0100;
    wire if1_predicted_taken1 = 1'b1;
    wire [31:0] if1_predicted_target1 = if1_candidate_addr + 32'h0000_0202;
    reg redirect_valid;
    wire redirect_accept, redirect_fire;
    reg [31:0] redirect_target;
    reg [`EDRV32_EPOCH_W-1:0] redirect_epoch;
    wire if2_window_valid, if2_window_accept;
    wire [15:0] if2_halfword0, if2_halfword1;
    wire if2_halfword1_valid;
    wire [31:0] if2_window_pc;
    wire if2_halfword0_error, if2_halfword1_error;
    wire [`EDRV32_EPOCH_W-1:0] if2_window_epoch;
    wire if2_window_predicted_taken;
    wire [31:0] if2_window_predicted_target;
    wire [1:0] if2_window_halfwords;
    wire if2_pipe_ready = u_if2.candidate_ready_w;
    wire window_valid, window_ready, window_accept;
    wire [15:0] halfword0, halfword1;
    wire halfword1_valid;
    wire [31:0] window_pc;
    wire halfword0_error, halfword1_error;
    wire [`EDRV32_EPOCH_W-1:0] window_epoch;
    wire window_predicted_taken;
    wire [31:0] window_predicted_target;
    wire [1:0] window_halfwords;
    wire align_candidate_valid, align_candidate_ready;
    wire [31:0] align_candidate_pc, align_candidate_instr;
    wire [31:0] align_candidate_raw_instr;
    wire align_candidate_is_compressed;
    wire align_candidate_fetch_fault, align_candidate_compressed_illegal;
    wire [`EDRV32_EPOCH_W-1:0] align_candidate_epoch;
    wire align_candidate_predicted_taken;
    wire [31:0] align_candidate_predicted_target;
    wire a_valid;
    reg a_accept;
    wire [31:0] a_pc, a_instr, a_raw_instr;
    wire a_is_compressed, a_fetch_fault, a_compressed_illegal;
    wire [`EDRV32_EPOCH_W-1:0] a_epoch;
    wire a_predicted_taken;
    wire [31:0] a_predicted_target;

    reg [31:0] request_log [0:31];
    integer request_count;
    reg [31:0] output_pc_log [0:31];
    reg [31:0] output_instr_log [0:31];
    reg output_predicted_taken_log [0:31];
    reg [31:0] output_predicted_target_log [0:31];
    integer output_count;
    integer output_count_before_kill;
    integer checks;

    reg cap_block_valid;
    wire cap_block_ready;
    reg [31:0] cap_block_addr;
    reg [31:0] cap_block_data;
    reg [`EDRV32_EPOCH_W-1:0] cap_block_epoch;
    wire cap_window_valid = u_capacity_if2.candidate_valid_w;
    wire [15:0] cap_halfword0 = u_capacity_if2.candidate_halfword0_w;
    wire [15:0] cap_halfword1 = u_capacity_if2.candidate_halfword1_w;
    wire cap_halfword1_valid = u_capacity_if2.candidate_halfword1_valid_w;
    wire [31:0] cap_window_pc = u_capacity_if2.candidate_pc_w;
    wire cap_window_predicted_taken =
        u_capacity_if2.candidate_predicted_taken_w;
    wire [31:0] cap_window_predicted_target =
        u_capacity_if2.candidate_predicted_target_w;
    reg cap_window_accept;
    reg cap_redirect_fire;
    reg [31:0] cap_redirect_target;
    reg [`EDRV32_EPOCH_W-1:0] cap_redirect_epoch;

    // Independent IF1 instance for registered architectural-redirect launch
    // timing.  Keeping its request interface blocked after reset leaves the
    // metadata queue empty before the directed redirect cycle.
    reg fast_redirect_valid;
    reg [31:0] fast_redirect_target;
    reg fast_req_ready;
    wire fast_redirect_accept;
    wire fast_redirect_fire;
    wire fast_req_valid;
    wire [31:0] fast_req_addr;
    wire [`EDRV32_EPOCH_W-1:0] fast_applied_epoch;

    initial clk = 1'b0;
    always #5 clk = ~clk;

    initial begin
        repeat (2000) @(posedge clk);
        $display("FAIL: frontend watchdog req=%0d out=%0d tags=%0d resp_v=%0b resp_r=%0b if2_words=%0d windows=%0d",
                 request_count, output_count, u_if1.tag_count_r,
                 resp_valid, resp_ready, u_if2.count_r,
                 u_if2.window_count_r);
        $fatal(1);
    end

    always @(posedge clk) begin
        if (rst_n && req_valid && req_ready) begin
            request_log[request_count] <= req_addr;
            request_count <= request_count + 1;
        end
        if (rst_n && a_valid && a_accept) begin
            output_pc_log[output_count] <= a_pc;
            output_instr_log[output_count] <= a_instr;
            output_predicted_taken_log[output_count] <= a_predicted_taken;
            output_predicted_target_log[output_count] <= a_predicted_target;
            output_count <= output_count + 1;
        end
    end

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

    task automatic send_response;
        input [31:0] data_i;
        input error_i;
        begin
            resp_data = data_i;
            resp_error = error_i;
            resp_valid = 1'b1;
            while (!resp_ready) @(posedge clk);
            @(posedge clk); #1;
            resp_valid = 1'b0;
            resp_error = 1'b0;
        end
    endtask

    task automatic push_capacity_block;
        input [31:0] addr_i;
        input [31:0] data_i;
        begin
            cap_block_addr = addr_i;
            cap_block_data = data_i;
            cap_block_valid = 1'b1;
            while (!cap_block_ready) @(posedge clk);
            @(posedge clk); #1;
            cap_block_valid = 1'b0;
        end
    endtask

    edrv32_if1_stage #(.RESET_PC(RESET_PC)) u_if1 (
        .clk_i(clk),
        .rst_n_i(rst_n),
        .predictor_query_pc0_o(if1_candidate_addr),
        .predictor_query_pc1_o(),
        .predicted_taken0_i(if1_predicted_taken0),
        .predicted_target0_i(if1_predicted_target0),
        .predictor_meta0_i({if1_predicted_taken0, if1_predicted_taken0}),
        .predicted_taken1_i(if1_predicted_taken1),
        .predicted_target1_i(if1_predicted_target1),
        .predictor_meta1_i({if1_predicted_taken1, if1_predicted_taken1}),
        .redirect_valid_i(redirect_valid),
        .redirect_accept_o(redirect_accept),
        .redirect_fire_o(redirect_fire),
        .redirect_target_i(redirect_target),
        .redirect_epoch_i(redirect_epoch),
        .prediction_redirect_valid_i(1'b0),
        .prediction_redirect_target_i(32'd0),
        .prediction_redirect_fire_o(),
        .applied_redirect_epoch_o(),
        .lookup_req_valid_o(req_valid),
        .lookup_req_ready_i(req_ready),
        .lookup_req_addr_o(req_addr),
        .lookup_resp_valid_i(resp_valid),
        .lookup_resp_ready_o(resp_ready),
        .lookup_resp_data_i(resp_data),
        .lookup_resp_error_i(resp_error),
        .block_valid_o(block_valid),
        .block_ready_i(block_ready),
        .block_addr_o(block_addr),
        .block_data_o(block_data),
        .block_error_o(block_error),
        .block_epoch_o(block_epoch),
        .block_predicted_taken0_o(block_predicted_taken0),
        .block_predicted_target0_o(block_predicted_target0),
        .block_predictor_meta0_o(),
        .block_predicted_taken1_o(block_predicted_taken1),
        .block_predicted_target1_o(block_predicted_target1),
        .block_predictor_meta1_o()
    );

    edrv32_if2_stage #(.RESET_PC(RESET_PC)) u_if2 (
        .clk_i(clk),
        .rst_n_i(rst_n),
        .block_valid_i(block_valid),
        .block_ready_o(block_ready),
        .block_addr_i(block_addr),
        .block_data_i(block_data),
        .block_error_i(block_error),
        .block_epoch_i(block_epoch),
        .block_predicted_taken0_i(block_predicted_taken0),
        .block_predicted_target0_i(block_predicted_target0),
        .block_predictor_meta0_i({block_predicted_taken0, block_predicted_taken0}),
        .block_predicted_taken1_i(block_predicted_taken1),
        .block_predicted_target1_i(block_predicted_target1),
        .block_predictor_meta1_i({block_predicted_taken1, block_predicted_taken1}),
        .window_valid_o(window_valid),
        .window_ready_i(window_accept),
        .halfword0_o(halfword0),
        .halfword1_o(halfword1),
        .halfword1_valid_o(halfword1_valid),
        .window_pc_o(window_pc),
        .halfword0_error_o(halfword0_error),
        .halfword1_error_o(halfword1_error),
        .window_epoch_o(window_epoch),
        .window_predicted_taken_o(window_predicted_taken),
        .window_predicted_target_o(window_predicted_target),
        .prediction_redirect_valid_o(),
        .prediction_redirect_target_o(),
        .prediction_redirect_fire_i(1'b0),
        .prediction_redirect_epoch_i({`EDRV32_EPOCH_W{1'b0}}),
        .redirect_fire_i(redirect_fire),
        .redirect_target_i(redirect_target),
        .redirect_epoch_i(redirect_epoch),
        .kill_i(redirect_fire)
    );

    edrv32_align_stage u_align (
        .clk_i(clk),
        .rst_n_i(rst_n),
        .window_valid_i(window_valid),
        .window_ready_o(window_ready),
        .window_accept_o(window_accept),
        .window_halfwords_o(window_halfwords),
        .halfword0_i(halfword0),
        .halfword1_i(halfword1),
        .halfword1_valid_i(halfword1_valid),
        .pc_i(window_pc),
        .halfword0_error_i(halfword0_error),
        .halfword1_error_i(halfword1_error),
        .epoch_i(window_epoch),
        .predicted_taken_i(window_predicted_taken),
        .predicted_target_i(window_predicted_target),
        .valid_o(a_valid),
        .ready_i(a_accept),
        .pc_o(a_pc),
        .instr_o(a_instr),
        .raw_instr_o(a_raw_instr),
        .is_compressed_o(a_is_compressed),
        .fetch_fault_o(a_fetch_fault),
        .compressed_illegal_o(a_compressed_illegal),
        .epoch_o(a_epoch),
        .predicted_taken_o(a_predicted_taken),
        .predicted_target_o(a_predicted_target),
        .kill_i(redirect_fire)
    );

    // Independent IF2 instance for full-capacity/backpressure invariants.
    edrv32_if2_stage #(.RESET_PC(32'h8000_0200)) u_capacity_if2 (
        .clk_i(clk), .rst_n_i(rst_n),
        .block_valid_i(cap_block_valid), .block_ready_o(cap_block_ready),
        .block_addr_i(cap_block_addr), .block_data_i(cap_block_data),
        .block_error_i(1'b0), .block_epoch_i(cap_block_epoch),
        .block_predicted_taken0_i(cap_block_addr[2]),
        .block_predicted_target0_i(cap_block_addr + 32'h0000_0100),
        .block_predictor_meta0_i({2{cap_block_addr[2]}}),
        .block_predicted_taken1_i(1'b1),
        .block_predicted_target1_i(cap_block_addr + 32'h0000_0202),
        .block_predictor_meta1_i(2'b11),
        .window_valid_o(), .window_ready_i(1'b0),
        .halfword0_o(), .halfword1_o(), .halfword1_valid_o(),
        .window_pc_o(), .halfword0_error_o(), .halfword1_error_o(),
        .window_epoch_o(), .window_predicted_taken_o(),
        .window_predicted_target_o(),
        .prediction_redirect_valid_o(), .prediction_redirect_target_o(),
        .prediction_redirect_fire_i(1'b0),
        .prediction_redirect_epoch_i({`EDRV32_EPOCH_W{1'b0}}),
        .redirect_fire_i(cap_redirect_fire),
        .redirect_target_i(cap_redirect_target),
        .redirect_epoch_i(cap_redirect_epoch),
        .kill_i(cap_redirect_fire)
    );

    edrv32_if1_stage #(.RESET_PC(32'h8000_0400)) u_fast_redirect_if1 (
        .clk_i(clk), .rst_n_i(rst_n),
        .predictor_query_pc0_o(), .predictor_query_pc1_o(),
        .predicted_taken0_i(1'b0), .predicted_target0_i(32'd0),
        .predictor_meta0_i(2'b00),
        .predicted_taken1_i(1'b0), .predicted_target1_i(32'd0),
        .predictor_meta1_i(2'b00),
        .redirect_valid_i(fast_redirect_valid),
        .redirect_accept_o(fast_redirect_accept),
        .redirect_fire_o(fast_redirect_fire),
        .redirect_target_i(fast_redirect_target),
        .redirect_epoch_i({`EDRV32_EPOCH_W{1'b0}}),
        .prediction_redirect_valid_i(1'b0),
        .prediction_redirect_target_i(32'd0),
        .prediction_redirect_fire_o(),
        .applied_redirect_epoch_o(fast_applied_epoch),
        .lookup_req_valid_o(fast_req_valid),
        .lookup_req_ready_i(fast_req_ready),
        .lookup_req_addr_o(fast_req_addr),
        .lookup_resp_valid_i(1'b0),
        .lookup_resp_ready_o(),
        .lookup_resp_data_i(32'd0),
        .lookup_resp_error_i(1'b0),
        .block_valid_o(), .block_ready_i(1'b1),
        .block_addr_o(), .block_data_o(), .block_error_o(),
        .block_epoch_o(), .block_predicted_taken0_o(),
        .block_predicted_target0_o(), .block_predicted_taken1_o(),
        .block_predicted_target1_o()
    );

    initial begin
        // White-box control for the independent IF2 FIFO-capacity checks.
        // The main frontend path above exercises the integrated outgoing pipe.
        force u_capacity_if2.candidate_accept_w = cap_window_accept;
        force u_capacity_if2.candidate_halfwords_w = 2'd2;
        checks = 0;
        request_count = 0;
        output_count = 0;
        rst_n = 1'b0;
        req_ready = 1'b1;
        resp_valid = 1'b0;
        resp_data = 32'd0;
        resp_error = 1'b0;
        redirect_valid = 1'b0;
        redirect_target = 32'd0;
        redirect_epoch = 2'd0;
        a_accept = 1'b1;
        cap_block_valid = 1'b0;
        cap_block_addr = 32'h8000_0200;
        cap_block_data = 32'd0;
        cap_block_epoch = {`EDRV32_EPOCH_W{1'b0}};
        cap_window_accept = 1'b0;
        cap_redirect_fire = 1'b0;
        cap_redirect_target = 32'd0;
        cap_redirect_epoch = {`EDRV32_EPOCH_W{1'b0}};
        fast_redirect_valid = 1'b0;
        fast_redirect_target = 32'h8000_0802;
        fast_req_ready = 1'b0;
        repeat (2) @(posedge clk);
        rst_n = 1'b1;

        // The architectural redirect command is already registered by the
        // core redirect controller.  IF1 should use that payload for a target
        // lookup in this cycle, rather than spend a cycle only loading its PC.
        fast_redirect_valid = 1'b1;
        fast_req_ready = 1'b1;
        #1;
        check_true(fast_redirect_accept && fast_redirect_fire &&
                   fast_req_valid && fast_req_addr == 32'h8000_0800,
                   "Registered redirect launches aligned target request immediately");
        check_true(fast_applied_epoch == {{(`EDRV32_EPOCH_W-1){1'b0}}, 1'b1},
                   "Immediate redirect request carries the newly applied epoch");
        @(posedge clk); #1;
        fast_redirect_valid = 1'b0;
        #1;
        check_true(fast_req_valid && fast_req_addr == 32'h8000_0804,
                   "Accepted redirect target advances without a duplicate request");
        fast_req_ready = 1'b0;

        // A target that is offered but not accepted must remain the resident
        // stream PC after the one-cycle redirect command has gone away.
        fast_redirect_target = 32'h8000_0c02;
        fast_redirect_valid = 1'b1;
        #1;
        check_true(fast_redirect_fire && fast_req_valid &&
                   fast_req_addr == 32'h8000_0c00,
                   "Blocked redirect target is offered without ready feedback");
        @(posedge clk); #1;
        fast_redirect_valid = 1'b0;
        fast_req_ready = 1'b1;
        #1;
        check_true(fast_req_valid && fast_req_addr == 32'h8000_0c00,
                   "Unaccepted redirect target is retried from registered PC");
        fast_req_ready = 1'b0;

        while (request_count < 2) @(posedge clk);
        #1;
        check_true(request_log[0] == RESET_PC &&
                   request_log[1] == RESET_PC + 32'd4,
                   "IF_REQ issues two sequential word blocks");
        check_true(!req_valid, "IF_REQ stops at two outstanding tags");

        // C.NOP at PC+0, a 32-bit ADDI straddling blocks at PC+2, then C.NOP.
        // Randomized downstream backpressure must not lose, duplicate, or
        // detach metadata from any instruction boundary.
        fork
            begin
                repeat (24) begin
                    @(negedge clk);
                    a_accept = $random;
                end
                a_accept = 1'b1;
            end
            begin
                send_response(32'h8293_0001, 1'b0);
                send_response(32'h0001_ffc0, 1'b0);
            end
        join
        while (output_count < 3) @(posedge clk);
        #1;
        check_true(output_pc_log[0] == RESET_PC && output_instr_log[0] == 32'h0000_0013,
                   "Frontend emits first compressed instruction");
        check_true(output_pc_log[1] == RESET_PC + 32'd2 &&
                   output_instr_log[1] == 32'hffc0_8293,
                   "Frontend assembles 32-bit instruction across blocks");
        check_true(output_pc_log[2] == RESET_PC + 32'd6 &&
                   output_instr_log[2] == 32'h0000_0013,
                   "Frontend preserves upper halfword after straddle");
        check_true(!output_predicted_taken_log[0] &&
                   output_predicted_target_log[0] == RESET_PC + 32'h0000_0100,
                   "Slot0 prediction metadata follows the first halfword");
        check_true(output_predicted_taken_log[1] &&
                   output_predicted_target_log[1] == RESET_PC + 32'h0000_0202,
                   "Slot1 prediction metadata survives cross-word assembly");
        check_true(output_predicted_taken_log[2] &&
                   output_predicted_target_log[2] == RESET_PC + 32'h0000_0206,
                   "Next-block slot1 metadata remains paired after buffering");

        // Redirect to an upper halfword. Both outstanding epoch-0 responses
        // are drained and dropped before target epoch-1 data is accepted. New
        // target requests may refill the metadata queue while these strictly
        // ordered stale responses leave its head.
        redirect_target = 32'h8000_0102;
        redirect_epoch = 2'd1;
        redirect_valid = 1'b1;
        while (!redirect_accept) @(posedge clk);
        @(posedge clk); #1;
        redirect_valid = 1'b0;

        send_response(32'h0001_0001, 1'b0);
        send_response(32'h0001_0001, 1'b0);

        while (request_count < 6) @(posedge clk);
        #1;
        check_true((request_log[request_count-1] == 32'h8000_0100) ||
                   (request_log[request_count-2] == 32'h8000_0100),
                   "IF_REQ restarts at redirected aligned block");

        send_response(32'h0001_dead, 1'b0);
        while (output_count < 4) @(posedge clk);
        #1;
        check_true(output_pc_log[3] == 32'h8000_0102 &&
                   output_instr_log[3] == 32'h0000_0013,
                   "IF_BUF skips lower halfword at redirected PC[1]");
        check_true(output_predicted_taken_log[3] &&
                   output_predicted_target_log[3] == 32'h8000_0302,
                   "Redirected upper halfword receives slot1 metadata");

        // Hold an instruction at the final frontend boundary, then redirect.
        // The local kill must clear visibility without allowing the held
        // instruction to retire into the output log.
        a_accept = 1'b0;
        send_response(32'h0001_0001, 1'b0);
        send_response(32'h0001_0001, 1'b0);
        while (!a_valid || (u_if2.window_count_r != 2'd2))
            @(posedge clk);
        #1;
        check_true(!if2_pipe_ready,
                   "Full IF2/ALIGN queue isolates downstream readiness");
        a_accept = 1'b1;
        #1;
        check_true(!if2_pipe_ready,
                   "Full IF2/ALIGN queue does not reclaim combinationally");
        @(posedge clk); #1;
        check_true(if2_pipe_ready,
                   "IF2/ALIGN capacity returns after registered dequeue");
        a_accept = 1'b0;
        output_count_before_kill = output_count;
        redirect_target = 32'h8000_0200;
        redirect_epoch = 2'd2;
        redirect_valid = 1'b1;
        while (!redirect_accept) @(posedge clk);
        @(posedge clk); #1;
        redirect_valid = 1'b0;
        check_true(!a_valid && output_count == output_count_before_kill,
                   "Redirect kill removes a backpressured younger instruction");
        a_accept = 1'b1;

        // Fill all six halfwords while the consumer is stopped.  A fourth
        // matching block must remain backpressured without changing the head.
        push_capacity_block(32'h8000_0200, 32'haaaa_0001);
        push_capacity_block(32'h8000_0204, 32'hbbbb_0002);
        push_capacity_block(32'h8000_0208, 32'hcccc_0003);
        cap_block_addr = 32'h8000_020c;
        cap_block_data = 32'hdddd_0004;
        cap_block_valid = 1'b1;
        #1;
        check_true(!cap_block_ready && cap_window_valid &&
                   cap_window_pc == 32'h8000_0200 &&
                   cap_halfword0 == 16'h0001 && cap_halfword1 == 16'haaaa,
                   "Full IF_BUF backpressures without overwriting its head");
        check_true(!cap_window_predicted_taken &&
                   cap_window_predicted_target == 32'h8000_0300,
                   "Full IF_BUF preserves head prediction metadata");
        repeat (3) @(posedge clk);
        #1;
        check_true(!cap_block_ready && cap_halfword0 == 16'h0001 &&
                   cap_halfword1 == 16'haaaa && !cap_window_predicted_taken &&
                   cap_window_predicted_target == 32'h8000_0300,
                   "Full IF_BUF payload is stable during sustained backpressure");

        // The IF2-local two-entry window queue is a registered capacity
        // boundary.  Reclaiming raw-FIFO space therefore becomes visible to
        // the response interface only after the consume edge.
        cap_window_accept = 1'b1;
        #1;
        check_true(!cap_block_ready,
                   "Full IF_BUF does not expose reclaimed capacity combinationally");
        @(posedge clk); #1;
        cap_window_accept = 1'b0;
        check_true(cap_block_ready &&
                   u_capacity_if2.head_r == 3'd2 &&
                   u_capacity_if2.tail_r == 3'd0 &&
                   u_capacity_if2.count_r == 3'd4,
                   "IF_BUF capacity returns after registered consume");
        check_true(cap_window_pc == 32'h8000_0204 &&
                   cap_halfword0 == 16'h0002 && cap_halfword1 == 16'hbbbb,
                   "IF_BUF exposes second block after registered consume");
        check_true(cap_window_predicted_taken &&
                   cap_window_predicted_target == 32'h8000_0304,
                   "IF_BUF indexes prediction metadata with its halfword");
        @(posedge clk); #1;
        cap_block_valid = 1'b0;
        check_true(u_capacity_if2.tail_r == 3'd2 &&
                   u_capacity_if2.count_r == 3'd6 &&
                   u_capacity_if2.halfword_r[0] == 16'h0004,
                   "IF_BUF appends the held block after registered capacity returns");
        cap_window_accept = 1'b1;
        @(posedge clk); #1;
        check_true(cap_window_pc == 32'h8000_0208 &&
                   cap_halfword0 == 16'h0003 && cap_halfword1 == 16'hcccc,
                   "IF_BUF preserves third block order");
        @(posedge clk); #1;
        cap_window_accept = 1'b0;
        check_true(cap_window_pc == 32'h8000_020c &&
                   cap_halfword0 == 16'h0004 && cap_halfword1 == 16'hdddd,
                   "IF_BUF appends held fourth block exactly once");

        // Drain the capacity test, then redirect to the upper halfword of the
        // last word in a 16-byte cache line. The following 32-bit instruction
        // must be formable from that slot1 and the next line's slot0 while
        // retaining the start halfword's slot1 prediction metadata.
        cap_window_accept = 1'b1;
        @(posedge clk); #1;
        cap_window_accept = 1'b0;
        cap_redirect_target = 32'h8000_100e;
        cap_redirect_epoch = 2'd1;
        cap_redirect_fire = 1'b1;
        @(posedge clk); #1;
        cap_redirect_fire = 1'b0;
        cap_block_epoch = 2'd1;
        push_capacity_block(32'h8000_100c, 32'h00b3_dead);
        push_capacity_block(32'h8000_1010, 32'h5678_1234);
        check_true(cap_window_pc == 32'h8000_100e &&
                   cap_halfword0 == 16'h00b3 && cap_halfword1 == 16'h1234 &&
                   cap_halfword1_valid,
                   "IF_BUF forms a 32-bit window across a cache-line boundary");
        check_true(cap_window_predicted_taken &&
                   cap_window_predicted_target == 32'h8000_120e,
                   "Cross-line window keeps its slot1 prediction metadata");

        $display("PASS: frontend IF_REQ/IF_BUF/ALIGN (%0d checks)", checks);
        $finish;
    end

endmodule
