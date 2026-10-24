`timescale 1ns/1ps
`include "edrv32_bus.vh"
`include "edrv32_lsu.vh"
`include "edrv32_uop.vh"

module tb_store_queue;
    reg clk;
    reg rst_n;
    reg alloc_valid;
    wire alloc_ready;
    wire [`EDRV32_LSU_TOKEN_W-1:0] alloc_token;
    reg [31:0] alloc_pc;
    reg [31:0] alloc_addr;
    reg [3:0] alloc_wstrb;
    reg [31:0] alloc_wdata;
    reg [`EDRV32_EPOCH_W-1:0] alloc_epoch;
    reg [`EDRV32_LSU_SEQUENCE_W-1:0] alloc_sequence;
    wire prepare_valid;
    reg prepare_ready;
    wire [`EDRV32_LSU_TOKEN_W-1:0] prepare_token;
    wire [31:0] prepare_addr;
    wire [`EDRV32_LSU_SEQUENCE_W-1:0] prepare_sequence;
    reg prepare_response_valid;
    wire prepare_response_ready;
    reg [`EDRV32_LSU_TOKEN_W-1:0] prepare_response_token;
    reg prepare_response_error;
    reg prepare_cancel_valid;
    reg [`EDRV32_LSU_TOKEN_W-1:0] prepare_cancel_token;
    reg commit_valid;
    reg [`EDRV32_LSU_TOKEN_W-1:0] commit_token;
    wire commit_ready;
    wire commit_error;
    reg commit_fire;
    wire drain_valid;
    reg drain_ready;
    wire [`EDRV32_LSU_TOKEN_W-1:0] drain_token;
    wire [31:0] drain_addr;
    wire [3:0] drain_wstrb;
    wire [31:0] drain_wdata;
    reg drain_response_valid;
    wire drain_response_ready;
    reg [`EDRV32_LSU_TOKEN_W-1:0] drain_response_token;
    reg drain_response_error;
    wire async_error;
    reg load_query_valid;
    reg [31:0] load_query_addr;
    reg [`BUS_SZ_W-1:0] load_query_size;
    reg load_query_unsigned;
    wire load_match;
    wire load_forward_ready;
    wire [31:0] load_forward_data;
    wire [`EDRV32_LSU_TOKEN_W-1:0] load_match_token;
    wire release_valid;
    wire [`EDRV32_LSU_TOKEN_W-1:0] release_token;
    reg flush;
    wire empty;
    wire full;
    wire committed_empty;
    wire [1:0] committed_reservation_count;
    integer checks;
    reg [`EDRV32_LSU_TOKEN_W-1:0] token_a;
    reg [`EDRV32_LSU_TOKEN_W-1:0] token_b;
    reg [`EDRV32_LSU_TOKEN_W-1:0] token_c;
    reg [`EDRV32_LSU_TOKEN_W-1:0] token_d;
    reg [`EDRV32_LSU_TOKEN_W-1:0] token_old;
    reg [`EDRV32_LSU_TOKEN_W-1:0] token_new;

    initial clk = 1'b0;
    always #5 clk = ~clk;

    edrv32_store_queue u_dut (
        .clk_i(clk), .rst_n_i(rst_n),
        .alloc_valid_i(alloc_valid), .alloc_ready_o(alloc_ready),
        .alloc_token_o(alloc_token), .alloc_pc_i(alloc_pc),
        .alloc_addr_i(alloc_addr), .alloc_wstrb_i(alloc_wstrb),
        .alloc_wdata_i(alloc_wdata), .alloc_epoch_i(alloc_epoch),
        .alloc_sequence_i(alloc_sequence),
        .prepare_valid_o(prepare_valid), .prepare_ready_i(prepare_ready),
        .prepare_token_o(prepare_token), .prepare_addr_o(prepare_addr),
        .prepare_sequence_o(prepare_sequence),
        .prepare_response_valid_i(prepare_response_valid),
        .prepare_response_ready_o(prepare_response_ready),
        .prepare_response_token_i(prepare_response_token),
        .prepare_response_error_i(prepare_response_error),
        .prepare_cancel_valid_i(prepare_cancel_valid),
        .prepare_cancel_token_i(prepare_cancel_token),
        .commit_valid_i(commit_valid), .commit_token_i(commit_token),
        .commit_ready_o(commit_ready), .commit_error_o(commit_error),
        .commit_fire_i(commit_fire),
        .drain_valid_o(drain_valid), .drain_ready_i(drain_ready),
        .drain_token_o(drain_token), .drain_addr_o(drain_addr),
        .drain_wstrb_o(drain_wstrb), .drain_wdata_o(drain_wdata),
        .drain_response_valid_i(drain_response_valid),
        .drain_response_ready_o(drain_response_ready),
        .drain_response_token_i(drain_response_token),
        .drain_response_error_i(drain_response_error),
        .async_error_o(async_error),
        .load_query_valid_i(load_query_valid),
        .load_query_addr_i(load_query_addr),
        .load_query_size_i(load_query_size),
        .load_query_unsigned_i(load_query_unsigned),
        .load_match_o(load_match),
        .load_forward_ready_o(load_forward_ready),
        .load_forward_data_o(load_forward_data),
        .load_match_token_o(load_match_token),
        .release_valid_o(release_valid),
        .release_token_o(release_token),
        .flush_i(flush), .empty_o(empty), .full_o(full),
        .committed_empty_o(committed_empty),
        .committed_reservation_count_o(committed_reservation_count)
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
        input [31:0] addr_i;
        input [3:0] wstrb_i;
        input [31:0] wdata_i;
        output [`EDRV32_LSU_TOKEN_W-1:0] token_o;
        begin
            @(negedge clk);
            alloc_pc = pc_i;
            alloc_addr = addr_i;
            alloc_wstrb = wstrb_i;
            alloc_wdata = wdata_i;
            alloc_sequence = pc_i[5:2];
            alloc_valid = 1'b1;
            #1;
            check_true(alloc_ready, "store queue accepts allocation");
            token_o = alloc_token;
            @(posedge clk); #1;
            alloc_valid = 1'b0;
        end
    endtask

    task automatic prepare_issue;
        input [`EDRV32_LSU_TOKEN_W-1:0] token_i;
        input [31:0] addr_i;
        begin
            @(negedge clk);
            prepare_ready = 1'b1;
            #1;
            check_true(prepare_valid && prepare_token == token_i &&
                       prepare_addr == addr_i,
                       "oldest unprepared store owns prepare request");
            @(posedge clk); #1;
            prepare_ready = 1'b0;
        end
    endtask

    task automatic prepare_respond;
        input [`EDRV32_LSU_TOKEN_W-1:0] token_i;
        input error_i;
        begin
            @(negedge clk);
            prepare_response_valid = 1'b1;
            prepare_response_token = token_i;
            prepare_response_error = error_i;
            #1;
            check_true(prepare_response_ready,
                       "store queue drains prepare response");
            @(posedge clk); #1;
            prepare_response_valid = 1'b0;
        end
    endtask

    task automatic commit_store;
        input [`EDRV32_LSU_TOKEN_W-1:0] token_i;
        input error_i;
        begin
            @(negedge clk);
            commit_valid = 1'b1;
            commit_token = token_i;
            #1;
            check_true(commit_ready && commit_error == error_i,
                       "prepared store is accepted in architectural order");
            commit_fire = 1'b1;
            @(posedge clk); #1;
            commit_valid = 1'b0;
            commit_fire = 1'b0;
        end
    endtask

    task automatic drain_store;
        input [`EDRV32_LSU_TOKEN_W-1:0] token_i;
        input [31:0] addr_i;
        begin
            @(negedge clk);
            drain_ready = 1'b1;
            #1;
            check_true(drain_valid && drain_token == token_i &&
                       drain_addr == addr_i,
                       "oldest committed store owns drain request");
            @(posedge clk); #1;
            drain_ready = 1'b0;
            @(negedge clk);
            drain_response_valid = 1'b1;
            drain_response_token = token_i;
            drain_response_error = 1'b0;
            #1;
            check_true(drain_response_ready,
                       "store queue accepts matching drain response");
            @(posedge clk); #1;
            drain_response_valid = 1'b0;
        end
    endtask

    initial begin
        checks = 0;
        rst_n = 1'b0;
        alloc_valid = 1'b0;
        alloc_pc = 32'd0;
        alloc_addr = 32'd0;
        alloc_wstrb = 4'd0;
        alloc_wdata = 32'd0;
        alloc_epoch = {`EDRV32_EPOCH_W{1'b0}};
        alloc_sequence = {`EDRV32_LSU_SEQUENCE_W{1'b0}};
        prepare_ready = 1'b0;
        prepare_response_valid = 1'b0;
        prepare_response_token = {`EDRV32_LSU_TOKEN_W{1'b0}};
        prepare_response_error = 1'b0;
        prepare_cancel_valid = 1'b0;
        prepare_cancel_token = {`EDRV32_LSU_TOKEN_W{1'b0}};
        commit_valid = 1'b0;
        commit_token = {`EDRV32_LSU_TOKEN_W{1'b0}};
        commit_fire = 1'b0;
        drain_ready = 1'b0;
        drain_response_valid = 1'b0;
        drain_response_token = {`EDRV32_LSU_TOKEN_W{1'b0}};
        drain_response_error = 1'b0;
        load_query_valid = 1'b0;
        load_query_addr = 32'd0;
        load_query_size = `BUS_SZ_WORD;
        load_query_unsigned = 1'b0;
        flush = 1'b0;
        repeat (3) @(posedge clk);
        rst_n = 1'b1;
        #1;
        check_true(empty && committed_empty, "store queue resets empty");

        allocate(32'h1000_0000, 32'h2000_0000, 4'b1111,
                 32'h1122_3344, token_a);
        prepare_issue(token_a, 32'h2000_0000);
        prepare_respond(token_a, 1'b0);
        allocate(32'h1000_0004, 32'h2000_0001, 4'b0010,
                 32'h0000_aa00, token_b);
        prepare_issue(token_b, 32'h2000_0001);
        prepare_respond(token_b, 1'b0);
        #1;
        check_true(!full && alloc_ready,
                   "two stores leave room in four-entry speculative queue");

        load_query_valid = 1'b1;
        load_query_addr = 32'h2000_0001;
        load_query_size = `BUS_SZ_BYTE;
        load_query_unsigned = 1'b1;
        #1;
        check_true(load_match && load_forward_ready &&
                   load_forward_data == 32'h0000_00aa &&
                   load_match_token == token_b,
                   "youngest store forwards a fully covered byte");
        load_query_addr = 32'h2000_0000;
        load_query_size = `BUS_SZ_BYTE;
        #1;
        check_true(load_match && load_forward_ready &&
                   load_forward_data == 32'h0000_0044,
                   "disjoint younger byte store does not hide older overlap");
        load_query_addr = 32'h2000_0002;
        #1;
        check_true(load_match && load_forward_ready &&
                   load_forward_data == 32'h0000_0022,
                   "disjoint same-word store does not block requested byte");
        load_query_addr = 32'h2000_0000;
        load_query_size = `BUS_SZ_WORD;
        #1;
        check_true(load_match && !load_forward_ready,
                   "partial youngest overlap blocks whole-word load");
        load_query_valid = 1'b0;

        commit_store(token_a, 1'b0);
        #1;
        check_true(drain_valid && drain_token == token_a &&
                   committed_reservation_count == 2'd1,
                   "first committed store owns one unissued reservation");
        commit_store(token_b, 1'b0);
        #1;
        check_true(!committed_empty && committed_reservation_count == 2'd2,
                   "two committed stores preserve two unissued reservations");
        @(negedge clk);
        flush = 1'b1;
        @(posedge clk); #1;
        flush = 1'b0;
        check_true(!full && !committed_empty,
                   "flush preserves both committed-buffer stores");
        drain_store(token_a, 32'h2000_0000);
        check_true(committed_reservation_count == 2'd1,
                   "completed first drain leaves the second reservation");
        drain_store(token_b, 32'h2000_0001);
        #1;
        check_true(empty && committed_empty,
                   "committed stores drain in order");

        allocate(32'h1000_0008, 32'h2000_0008, 4'b1111,
                 32'hdead_beef, token_a);
        prepare_issue(token_a, 32'h2000_0008);
        prepare_respond(token_a, 1'b0);
        commit_store(token_a, 1'b0);
        @(negedge clk);
        drain_ready = 1'b1;
        drain_response_valid = 1'b1;
        drain_response_token = token_a;
        flush = 1'b1;
        #1;
        check_true(drain_valid && drain_response_ready && release_valid &&
                   release_token == token_a,
                   "flush cycle permits same-cycle committed drain response");
        @(posedge clk); #1;
        drain_ready = 1'b0;
        drain_response_valid = 1'b0;
        flush = 1'b0;
        check_true(empty && committed_empty,
                   "flush releases a store whose drain completed concurrently");

        allocate(32'h1000_0010, 32'h2000_0010, 4'b1111,
                 32'h5566_7788, token_old);
        prepare_issue(token_old, 32'h2000_0010);
        @(negedge clk);
        prepare_cancel_valid = 1'b1;
        prepare_cancel_token = token_old;
        @(posedge clk); #1;
        prepare_cancel_valid = 1'b0;
        check_true(prepare_valid && prepare_token == token_old,
                   "canceled prepare is retried with the same owner token");
        prepare_ready = 1'b1;
        @(posedge clk); #1;
        prepare_ready = 1'b0;
        @(negedge clk);
        flush = 1'b1;
        @(posedge clk); #1;
        flush = 1'b0;
        check_true(empty, "flush removes an uncommitted store");

        allocate(32'h1000_0014, 32'h2000_0014, 4'b1111,
                 32'h99aa_bbcc, token_new);
        check_true(token_new != token_old,
                   "store slot reuse flips token generation");
        prepare_issue(token_new, 32'h2000_0014);
        @(negedge clk);
        prepare_response_valid = 1'b1;
        prepare_response_token = token_old;
        prepare_response_error = 1'b0;
        @(posedge clk); #1;
        prepare_response_valid = 1'b0;
        commit_valid = 1'b1;
        commit_token = token_new;
        #1;
        check_true(!commit_ready,
                   "stale prepare response cannot prepare a new store");
        commit_valid = 1'b0;
        prepare_respond(token_new, 1'b1);
        commit_store(token_new, 1'b1);
        #1;
        check_true(empty && committed_empty,
                   "precise prepare error releases without committed drain");

        allocate(32'h1000_0020, 32'h2000_0020, 4'b1111,
                 32'h1111_1111, token_a);
        allocate(32'h1000_0024, 32'h2000_0024, 4'b1111,
                 32'h2222_2222, token_b);
        allocate(32'h1000_0028, 32'h2000_0028, 4'b1111,
                 32'h3333_3333, token_c);
        allocate(32'h1000_002c, 32'h2000_002c, 4'b1111,
                 32'h4444_4444, token_d);
        #1;
        check_true(full && !alloc_ready,
                   "four speculative Stores fill the queue");
        prepare_issue(token_a, 32'h2000_0020);
        prepare_issue(token_b, 32'h2000_0024);
        prepare_issue(token_c, 32'h2000_0028);
        prepare_issue(token_d, 32'h2000_002c);
        prepare_respond(token_a, 1'b0);
        prepare_respond(token_b, 1'b0);
        prepare_respond(token_c, 1'b0);
        prepare_respond(token_d, 1'b0);
        commit_store(token_a, 1'b0);
        commit_store(token_b, 1'b0);
        @(negedge clk);
        commit_valid = 1'b1;
        commit_token = token_c;
        #1;
        check_true(!commit_ready,
                   "full committed buffer backpressures the next Store");
        commit_valid = 1'b0;
        drain_store(token_a, 32'h2000_0020);
        commit_store(token_c, 1'b0);
        drain_store(token_b, 32'h2000_0024);
        commit_store(token_d, 1'b0);
        drain_store(token_c, 32'h2000_0028);
        drain_store(token_d, 32'h2000_002c);
        check_true(empty && committed_empty,
                   "four-entry speculative and two-entry committed queues drain");

        $display("PASS: speculative store queue/committed buffer (%0d checks)",
                 checks);
        $finish;
    end
endmodule
