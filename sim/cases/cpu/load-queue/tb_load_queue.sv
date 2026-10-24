`timescale 1ns/1ps
`include "edrv32_bus.vh"
`include "edrv32_lsu.vh"
`include "edrv32_uop.vh"

module tb_load_queue;
    reg clk;
    reg rst_n;
    reg alloc_valid;
    wire alloc_ready;
    wire [`EDRV32_LSU_TOKEN_W-1:0] alloc_token;
    reg [31:0] alloc_pc;
    reg [4:0] alloc_rd;
    reg [31:0] alloc_addr;
    reg [`BUS_SZ_W-1:0] alloc_size;
    reg alloc_unsigned;
    reg [`EDRV32_EPOCH_W-1:0] alloc_epoch;
    reg [`EDRV32_LSU_SEQUENCE_W-1:0] alloc_sequence;
    reg alloc_forward_valid;
    reg [31:0] alloc_forward_data;
    reg alloc_block_valid;
    reg [`EDRV32_LSU_TOKEN_W-1:0] alloc_block_token;
    reg store_release_valid;
    reg [`EDRV32_LSU_TOKEN_W-1:0] store_release_token;
    wire request_valid;
    reg request_ready;
    wire [`EDRV32_LSU_TOKEN_W-1:0] request_token;
    wire [31:0] request_addr;
    wire [`BUS_SZ_W-1:0] request_size;
    wire request_unsigned;
    wire [`EDRV32_LSU_SEQUENCE_W-1:0] request_sequence;
    wire pending_valid;
    wire [`EDRV32_LSU_SEQUENCE_W-1:0] pending_sequence;
    reg response_valid;
    wire response_ready;
    reg [`EDRV32_LSU_TOKEN_W-1:0] response_token;
    reg [31:0] response_data;
    reg response_error;
    wire completion_valid;
    wire [`EDRV32_LSU_TOKEN_W-1:0] completion_token;
    wire [31:0] completion_data;
    wire [31:0] completion_pc;
    reg commit_valid;
    reg [`EDRV32_LSU_TOKEN_W-1:0] commit_token;
    wire commit_ready;
    wire [31:0] commit_data;
    wire commit_error;
    reg commit_fire;
    reg [4:0] rs1_addr;
    reg uses_rs1;
    wire rs1_match;
    wire rs1_ready;
    wire [`EDRV32_LSU_TOKEN_W-1:0] rs1_token;
    wire [31:0] rs1_pc;
    wire [31:0] rs1_value;
    reg [4:0] rs2_addr;
    reg uses_rs2;
    wire rs2_match;
    wire rs2_ready;
    wire [`EDRV32_LSU_TOKEN_W-1:0] rs2_token;
    wire [31:0] rs2_pc;
    wire [31:0] rs2_value;
    reg observe_token_valid;
    reg [`EDRV32_LSU_TOKEN_W-1:0] observe_token;
    wire observe_match;
    wire observe_ready;
    wire [31:0] observe_value;
    wire operand0_match;
    wire operand0_ready;
    wire [31:0] operand0_value;
    reg [31:0] probe0_pc;
    wire probe0_ready;
    wire [31:0] probe0_value;
    reg [31:0] probe1_pc;
    wire probe1_ready;
    wire [31:0] probe1_value;
    reg flush;
    wire empty;
    wire full;
    integer checks;
    reg [`EDRV32_LSU_TOKEN_W-1:0] token_a;
    reg [`EDRV32_LSU_TOKEN_W-1:0] token_b;
    reg [`EDRV32_LSU_TOKEN_W-1:0] token_c;
    reg [`EDRV32_LSU_TOKEN_W-1:0] token_d;
    reg [`EDRV32_LSU_TOKEN_W-1:0] token_old;
    reg [`EDRV32_LSU_TOKEN_W-1:0] token_new;

    initial clk = 1'b0;
    always #5 clk = ~clk;

    edrv32_load_queue u_dut (
        .clk_i(clk), .rst_n_i(rst_n),
        .alloc_valid_i(alloc_valid), .alloc_ready_o(alloc_ready),
        .alloc_token_o(alloc_token), .alloc_pc_i(alloc_pc),
        .alloc_rd_i(alloc_rd), .alloc_addr_i(alloc_addr),
        .alloc_size_i(alloc_size), .alloc_unsigned_i(alloc_unsigned),
        .alloc_epoch_i(alloc_epoch),
        .alloc_sequence_i(alloc_sequence),
        .alloc_forward_valid_i(alloc_forward_valid),
        .alloc_forward_data_i(alloc_forward_data),
        .alloc_block_valid_i(alloc_block_valid),
        .alloc_block_token_i(alloc_block_token),
        .store_release_valid_i(store_release_valid),
        .store_release_token_i(store_release_token),
        .request_valid_o(request_valid), .request_ready_i(request_ready),
        .request_token_o(request_token), .request_addr_o(request_addr),
        .request_size_o(request_size),
        .request_unsigned_o(request_unsigned),
        .request_sequence_o(request_sequence),
        .pending_valid_o(pending_valid),
        .pending_sequence_o(pending_sequence),
        .response_valid_i(response_valid), .response_ready_o(response_ready),
        .response_token_i(response_token), .response_data_i(response_data),
        .response_error_i(response_error),
        .completion_valid_o(completion_valid),
        .completion_token_o(completion_token),
        .completion_data_o(completion_data),
        .completion_pc_o(completion_pc),
        .commit_valid_i(commit_valid), .commit_token_i(commit_token),
        .commit_ready_o(commit_ready), .commit_data_o(commit_data),
        .commit_error_o(commit_error), .commit_fire_i(commit_fire),
        .rs1_addr_i(rs1_addr), .uses_rs1_i(uses_rs1),
        .rs1_match_o(rs1_match), .rs1_ready_o(rs1_ready),
        .rs1_token_o(rs1_token), .rs1_pc_o(rs1_pc),
        .rs1_value_o(rs1_value),
        .rs2_addr_i(rs2_addr), .uses_rs2_i(uses_rs2),
        .rs2_match_o(rs2_match), .rs2_ready_o(rs2_ready),
        .rs2_token_o(rs2_token), .rs2_pc_o(rs2_pc),
        .rs2_value_o(rs2_value),
        .observe_token_valid_i(observe_token_valid),
        .observe_token_i(observe_token),
        .observe_match_o(observe_match),
        .observe_ready_o(observe_ready),
        .observe_value_o(observe_value),
        .operand0_token_valid_i(observe_token_valid),
        .operand0_token_i(observe_token),
        .operand0_match_o(operand0_match),
        .operand0_ready_o(operand0_ready),
        .operand0_value_o(operand0_value),
        .operand0_stored_ready_o(), .operand0_stored_value_o(),
        .operand1_token_valid_i(1'b0),
        .operand1_token_i({`EDRV32_LSU_TOKEN_W{1'b0}}),
        .operand1_match_o(), .operand1_ready_o(), .operand1_value_o(),
        .operand1_stored_ready_o(), .operand1_stored_value_o(),
        .probe0_pc_i(probe0_pc), .probe0_ready_o(probe0_ready),
        .probe0_value_o(probe0_value),
        .probe1_pc_i(probe1_pc), .probe1_ready_o(probe1_ready),
        .probe1_value_o(probe1_value),
        .flush_i(flush), .empty_o(empty), .full_o(full)
    );

    task automatic check_true;
        input condition;
        input [8*112-1:0] message;
        begin
            checks = checks + 1;
            if (!condition) begin
                $display("FAIL: %0s", message);
                $fatal(1);
            end
        end
    endtask

    task automatic allocate;
        input [31:0] pc_i;
        input [4:0] rd_i;
        input [31:0] addr_i;
        output [`EDRV32_LSU_TOKEN_W-1:0] token_o;
        begin
            @(negedge clk);
            alloc_pc = pc_i;
            alloc_rd = rd_i;
            alloc_addr = addr_i;
            alloc_sequence = pc_i[5:2];
            alloc_valid = 1'b1;
            #1;
            check_true(alloc_ready, "load queue accepts allocation");
            token_o = alloc_token;
            @(posedge clk); #1;
            alloc_valid = 1'b0;
        end
    endtask

    task automatic issue;
        input [`EDRV32_LSU_TOKEN_W-1:0] token_i;
        input [31:0] addr_i;
        begin
            @(negedge clk);
            request_ready = 1'b1;
            #1;
            check_true(request_valid && request_token == token_i &&
                       request_addr == addr_i,
                       "oldest unissued load owns D-cache request");
            @(posedge clk); #1;
            request_ready = 1'b0;
        end
    endtask

    task automatic respond;
        input [`EDRV32_LSU_TOKEN_W-1:0] token_i;
        input [31:0] data_i;
        input error_i;
        begin
            @(negedge clk);
            response_token = token_i;
            response_data = data_i;
            response_error = error_i;
            response_valid = 1'b1;
            #1;
            check_true(response_ready, "load queue always drains a response");
            @(posedge clk); #1;
            response_valid = 1'b0;
        end
    endtask

    task automatic commit;
        input [`EDRV32_LSU_TOKEN_W-1:0] token_i;
        input [31:0] data_i;
        input error_i;
        begin
            @(negedge clk);
            commit_valid = 1'b1;
            commit_token = token_i;
            #1;
            check_true(commit_ready && commit_data == data_i &&
                       commit_error == error_i,
                       "oldest completed load is ready at COMMIT");
            commit_fire = 1'b1;
            @(posedge clk); #1;
            commit_valid = 1'b0;
            commit_fire = 1'b0;
        end
    endtask

    initial begin
        checks = 0;
        rst_n = 1'b0;
        alloc_valid = 1'b0;
        alloc_pc = 32'd0;
        alloc_rd = 5'd0;
        alloc_addr = 32'd0;
        alloc_size = `BUS_SZ_WORD;
        alloc_unsigned = 1'b0;
        alloc_epoch = {`EDRV32_EPOCH_W{1'b0}};
        alloc_sequence = {`EDRV32_LSU_SEQUENCE_W{1'b0}};
        alloc_forward_valid = 1'b0;
        alloc_forward_data = 32'd0;
        alloc_block_valid = 1'b0;
        alloc_block_token = {`EDRV32_LSU_TOKEN_W{1'b0}};
        store_release_valid = 1'b0;
        store_release_token = {`EDRV32_LSU_TOKEN_W{1'b0}};
        request_ready = 1'b0;
        response_valid = 1'b0;
        response_token = {`EDRV32_LSU_TOKEN_W{1'b0}};
        response_data = 32'd0;
        response_error = 1'b0;
        commit_valid = 1'b0;
        commit_token = {`EDRV32_LSU_TOKEN_W{1'b0}};
        commit_fire = 1'b0;
        rs1_addr = 5'd0;
        uses_rs1 = 1'b0;
        rs2_addr = 5'd0;
        uses_rs2 = 1'b0;
        observe_token_valid = 1'b0;
        observe_token = {`EDRV32_LSU_TOKEN_W{1'b0}};
        probe0_pc = 32'd0;
        probe1_pc = 32'd0;
        flush = 1'b0;
        repeat (3) @(posedge clk);
        rst_n = 1'b1;
        #1;
        check_true(empty && !full, "load queue resets empty");

        allocate(32'h1000_0000, 5'd5, 32'h2000_0000, token_a);
        issue(token_a, 32'h2000_0000);
        observe_token_valid = 1'b1;
        observe_token = token_a;
        #1;
        check_true(observe_match && !observe_ready && operand0_match &&
                   !operand0_ready,
                   "exact token matches an incomplete live load");
        allocate(32'h1000_0004, 5'd5, 32'h2000_0004, token_b);
        issue(token_b, 32'h2000_0004);
        #1;
        check_true(!full && alloc_ready,
                   "two live loads leave room in four-entry queue");

        rs1_addr = 5'd5;
        uses_rs1 = 1'b1;
        #1;
        check_true(rs1_match && !rs1_ready && rs1_token == token_b &&
                   rs1_pc == 32'h1000_0004,
                   "youngest same-rd load blocks an older ready candidate");

        @(negedge clk);
        response_valid = 1'b1;
        response_token = token_a;
        response_data = 32'haaaa_0001;
        response_error = 1'b0;
        #1;
        check_true(completion_valid && completion_token == token_a &&
                   completion_data == 32'haaaa_0001,
                   "matching response produces tokenized completion bypass");
        check_true(rs1_match && !rs1_ready && rs1_token == token_b,
                   "older completion cannot satisfy younger same-rd load");
        check_true(observe_match && observe_ready &&
                   observe_value == 32'haaaa_0001 && operand0_ready &&
                   operand0_value == 32'haaaa_0001,
                   "exact token observes the response in its arrival cycle");
        @(posedge clk); #1;
        response_valid = 1'b0;
        check_true(observe_match && observe_ready &&
                   observe_value == 32'haaaa_0001,
                   "exact token observes the stored completion afterward");

        respond(token_b, 32'hbbbb_0002, 1'b0);
        #1;
        probe0_pc = 32'h1000_0000;
        probe1_pc = 32'h1000_0004;
        #1;
        check_true(probe0_ready && probe0_value == 32'haaaa_0001 &&
                   probe1_ready && probe1_value == 32'hbbbb_0002,
                   "two persistent EX probes preserve producer identity");
        check_true(rs1_ready && rs1_token == token_b &&
                   rs1_value == 32'hbbbb_0002,
                   "youngest completed load supplies Decode value");
        commit(token_a, 32'haaaa_0001, 1'b0);
        commit(token_b, 32'hbbbb_0002, 1'b0);
        uses_rs1 = 1'b0;
        #1;
        check_true(empty, "loads release strictly from queue head");

        allocate(32'h1000_0020, 5'd8, 32'h2000_0020, token_a);
        issue(token_a, 32'h2000_0020);
        allocate(32'h1000_0024, 5'd9, 32'h2000_0024, token_b);
        issue(token_b, 32'h2000_0024);
        allocate(32'h1000_0028, 5'd10, 32'h2000_0028, token_c);
        issue(token_c, 32'h2000_0028);
        allocate(32'h1000_002c, 5'd11, 32'h2000_002c, token_d);
        issue(token_d, 32'h2000_002c);
        #1;
        check_true(full && !alloc_ready, "four live loads fill the queue");
        alloc_valid = 1'b1;
        request_ready = 1'b1; #1;
        check_true(!request_valid && !alloc_ready,
                   "all-issued full queue cannot launch a fifth allocation");
        alloc_valid = 1'b0;
        request_ready = 1'b0;
        respond(token_a, 32'h0000_0008, 1'b0);
        respond(token_b, 32'h0000_0009, 1'b0);
        respond(token_c, 32'h0000_000a, 1'b0);
        respond(token_d, 32'h0000_000b, 1'b0);
        commit(token_a, 32'h0000_0008, 1'b0);
        commit(token_b, 32'h0000_0009, 1'b0);
        commit(token_c, 32'h0000_000a, 1'b0);
        commit(token_d, 32'h0000_000b, 1'b0);
        check_true(empty, "four-entry queue drains in order");

        allocate(32'h1000_0030, 5'd12, 32'h2000_0030, token_a);
        issue(token_a, 32'h2000_0030);
        allocate(32'h1000_0030, 5'd13, 32'h2000_0034, token_b);
        issue(token_b, 32'h2000_0034);
        respond(token_a, 32'h1111_1111, 1'b0);
        probe0_pc = 32'h1000_0030;
        probe1_pc = 32'h1000_0030;
        #1;
        check_true(!probe0_ready && !probe1_ready,
                   "newer same-PC load blocks an older completed value");
        respond(token_b, 32'h2222_2222, 1'b0);
        #1;
        check_true(probe0_ready && probe0_value == 32'h2222_2222 &&
                   probe1_ready && probe1_value == 32'h2222_2222,
                   "PC probes select the youngest dynamic load");
        commit(token_a, 32'h1111_1111, 1'b0);
        commit(token_b, 32'h2222_2222, 1'b0);
        #1;
        check_true(!probe0_ready && !probe1_ready,
                   "PC probes ignore released entries");
        observe_token_valid = 1'b0;

        allocate(32'h1000_0010, 5'd6, 32'h2000_0010, token_old);
        issue(token_old, 32'h2000_0010);
        @(negedge clk);
        flush = 1'b1;
        @(posedge clk); #1;
        flush = 1'b0;
        check_true(empty, "flush removes speculative loads");
        allocate(32'h1000_0014, 5'd7, 32'h2000_0014, token_new);
        check_true(token_new != token_old,
                   "slot reuse flips token generation");
        observe_token_valid = 1'b1;
        observe_token = token_old;
        #1;
        check_true(!observe_match && !observe_ready,
                   "stale token cannot observe a reallocated slot");
        observe_token_valid = 1'b0;
        issue(token_new, 32'h2000_0014);

        @(negedge clk);
        response_valid = 1'b1;
        response_token = token_old;
        response_data = 32'hdead_beef;
        #1;
        check_true(response_ready && !completion_valid,
                   "stale killed response is drained without completion");
        @(posedge clk); #1;
        response_valid = 1'b0;
        commit_valid = 1'b1;
        commit_token = token_new;
        #1;
        check_true(!commit_ready,
                   "stale response cannot complete a reallocated slot");
        commit_valid = 1'b0;

        respond(token_new, 32'd0, 1'b1);
        #1;
        check_true(!completion_valid,
                   "error response is never exposed as a bypass value");
        commit(token_new, 32'd0, 1'b1);
        check_true(empty, "error load releases only at precise COMMIT");

        alloc_block_valid = 1'b1;
        alloc_block_token = 2'b10;
        allocate(32'h1000_0018, 5'd8, 32'h2000_0018, token_new);
        alloc_block_valid = 1'b0;
        #1;
        check_true(!request_valid,
                   "partial-overlap load remains blocked after allocation");
        @(negedge clk);
        store_release_valid = 1'b1;
        store_release_token = 2'b11;
        @(posedge clk); #1;
        store_release_valid = 1'b0;
        check_true(!request_valid,
                   "unrelated store release does not wake blocked load");
        @(negedge clk);
        store_release_valid = 1'b1;
        store_release_token = 2'b10;
        @(posedge clk); #1;
        store_release_valid = 1'b0;
        check_true(request_valid && request_token == token_new,
                   "matching store token wakes blocked load request");
        issue(token_new, 32'h2000_0018);
        respond(token_new, 32'h1234_5678, 1'b0);
        commit(token_new, 32'h1234_5678, 1'b0);

        alloc_forward_valid = 1'b1;
        alloc_forward_data = 32'hcafe_f00d;
        allocate(32'h1000_001c, 5'd9, 32'h2000_001c, token_new);
        alloc_forward_valid = 1'b0;
        #1;
        check_true(!request_valid,
                   "store-forwarded load does not issue a D-cache request");
        probe0_pc = 32'h1000_001c;
        #1;
        check_true(probe0_ready && probe0_value == 32'hcafe_f00d,
                   "store-forwarded value is persistent for EX probe");
        commit(token_new, 32'hcafe_f00d, 1'b0);
        check_true(empty, "store-forwarded load retires from queue head");

        // A request can leave on the allocation edge even while an older,
        // already-issued load remains incomplete and owns the queue head.
        allocate(32'h1000_0100, 5'd5, 32'h2000_0100, token_a);
        issue(token_a, 32'h2000_0100);
        @(negedge clk);
        alloc_pc = 32'h1000_0104;
        alloc_rd = 5'd6;
        alloc_addr = 32'h2000_0104;
        alloc_sequence = 4'd7;
        alloc_valid = 1'b1;
        request_ready = 1'b1; #1;
        token_b = alloc_token;
        check_true(!empty && request_valid && request_token == token_b &&
                   request_addr == alloc_addr && request_sequence == 4'd7,
                   "new allocation launches behind an issued incomplete load");
        @(posedge clk); #1;
        alloc_valid = 1'b0;
        request_ready = 1'b0; #1;
        check_true(!request_valid, "allocation-edge request is issued exactly once");
        respond(token_b, 32'h2222_0104, 1'b0);
        commit_valid = 1'b1;
        commit_token = token_b; #1;
        check_true(!commit_ready, "early younger completion cannot retire before queue head");
        commit_valid = 1'b0;
        respond(token_a, 32'h1111_0100, 1'b0);
        commit(token_a, 32'h1111_0100, 1'b0);
        commit(token_b, 32'h2222_0104, 1'b0);

        // Cache backpressure moves the same offered request into its queue
        // entry without changing token, address, size, sign or sequence.
        allocate(32'h1000_0110, 5'd5, 32'h2000_0110, token_a);
        issue(token_a, 32'h2000_0110);
        @(negedge clk);
        alloc_pc = 32'h1000_0114;
        alloc_rd = 5'd6;
        alloc_addr = 32'h2000_0116;
        alloc_size = `BUS_SZ_HALF;
        alloc_unsigned = 1'b1;
        alloc_sequence = 4'd9;
        alloc_valid = 1'b1; #1;
        token_b = alloc_token;
        check_true(request_valid && request_token == token_b &&
                   request_addr == 32'h2000_0116 && request_size == `BUS_SZ_HALF &&
                   request_unsigned && request_sequence == 4'd9,
                   "new allocation offers its own payload while cache is stalled");
        @(posedge clk); #1;
        alloc_valid = 1'b0;
        alloc_addr = 32'hdead_0000;
        alloc_size = `BUS_SZ_WORD;
        alloc_unsigned = 1'b0;
        alloc_sequence = 4'd0;
        repeat (2) begin
            #1;
            check_true(request_valid && request_token == token_b &&
                       request_addr == 32'h2000_0116 && request_size == `BUS_SZ_HALF &&
                       request_unsigned && request_sequence == 4'd9,
                       "stalled allocation request retains its registered identity");
            @(posedge clk); #1;
        end
        issue(token_b, 32'h2000_0116);
        respond(token_a, 32'd10, 1'b0);
        respond(token_b, 32'd11, 1'b0);
        commit(token_a, 32'd10, 1'b0);
        commit(token_b, 32'd11, 1'b0);

        // A store-blocked, unissued older load forbids allocation-edge issue
        // of a younger load even though there is free queue capacity.
        alloc_block_valid = 1'b1;
        alloc_block_token = 3'b101;
        allocate(32'h1000_0120, 5'd7, 32'h2000_0120, token_a);
        alloc_block_valid = 1'b0;
        @(negedge clk);
        alloc_pc = 32'h1000_0124;
        alloc_rd = 5'd8;
        alloc_addr = 32'h2000_0124;
        alloc_valid = 1'b1;
        request_ready = 1'b1; #1;
        token_b = alloc_token;
        check_true(!request_valid && alloc_ready,
                   "new load cannot pass an older store-blocked request");
        @(posedge clk); #1;
        alloc_valid = 1'b0;
        request_ready = 1'b0;
        store_release_valid = 1'b1;
        store_release_token = 3'b101;
        @(posedge clk); #1;
        store_release_valid = 1'b0; #1;
        check_true(request_valid && request_token == token_a,
                   "store release exposes the oldest request first");
        issue(token_a, 32'h2000_0120);
        issue(token_b, 32'h2000_0124);
        respond(token_a, 32'd12, 1'b0);
        respond(token_b, 32'd13, 1'b0);
        commit(token_a, 32'd12, 1'b0);
        commit(token_b, 32'd13, 1'b0);
        check_true(empty, "allocation-edge issue cases drain in program order");

        // Repeated simultaneous head retirement and tail allocation crosses
        // every physical slot and generation boundary without emptying first.
        repeat (5) begin
            allocate(32'h1000_0130, 5'd9, 32'h2000_0130, token_a);
            issue(token_a, 32'h2000_0130);
            respond(token_a, 32'd14, 1'b0);
            @(negedge clk);
            commit_valid = 1'b1;
            commit_token = token_a;
            commit_fire = 1'b1;
            alloc_pc = 32'h1000_0134;
            alloc_rd = 5'd10;
            alloc_addr = 32'h2000_0134;
            alloc_valid = 1'b1;
            request_ready = 1'b1; #1;
            token_b = alloc_token;
            check_true(commit_ready && commit_data == 32'd14 && alloc_ready &&
                       request_valid && request_token == token_b &&
                       request_addr == 32'h2000_0134,
                       "head retirement and new request can share one edge");
            @(posedge clk); #1;
            commit_valid = 1'b0;
            commit_fire = 1'b0;
            alloc_valid = 1'b0;
            request_ready = 1'b0; #1;
            check_true(!empty && !request_valid,
                       "simultaneous turnover retains the issued younger owner");
            respond(token_b, 32'd15, 1'b0);
            commit(token_b, 32'd15, 1'b0);
        end

        $display("PASS: four-entry tokenized load queue (%0d checks)", checks);
        $finish;
    end
endmodule
