// File: tb_npu_writeback.sv
// Spec: npu-spec 5.2, 5.4, 5.5; datapath 4.2.2, 4.8; OP-07, SQ-01, ER-05 local behavior.
// Description: Transaction model checks credit and ordered chunks under long DMA stalls.
// Fill all in-flight reservations, wrap the ring/metadata queue and cancel at each phase.
// Clock: clk_npu test clock.
module tb_npu_writeback;
    reg clk = 0;
    initial forever #5 clk = !clk;
    reg rst_n = 0;
    reg cancel = 0;
    reg wb_valid = 0;
    reg [48:0] wb_tag = 0;
    reg [511:0] wb_data = 0;
    reg reserve = 0;
    wire [4:0] slot;
    wire [5:0] credit;
    wire chunk_valid;
    reg chunk_ready = 0;
    wire [4:0] chunk_base;
    wire [4:0] chunk_pairs;
    wire [11:0] chunk_row;
    wire [2:0] chunk_block;
    wire [10:0] chunk_pair;
    wire chunk_half;
    wire chunk_last;
    reg result_release = 0;
    reg rd_en = 0;
    reg [4:0] rd_index = 0;
    reg rd_plane = 0;
    wire rd_valid;
    wire [255:0] rd_data;
    wire cmd_done;
    wire [11:0] cmd_row;
    wire [2:0] cmd_block;
    wire idle;

    typedef struct packed {
        bit [4:0] base;
        bit [4:0] pairs;
        bit [11:0] row;
        bit [2:0] block_number;
        bit [10:0] first_pair;
        bit half;
        bit last;
    } chunk_t;
    chunk_t expected_chunks [$];
    chunk_t granted_chunk;
    chunk_t held_chunk;
    wire [37:0] actual_chunk = {chunk_base, chunk_pairs, chunk_row, chunk_block,
        chunk_pair, chunk_half, chunk_last};
    reg [48:0] issued_tags [0:1023];
    reg [511:0] issued_vectors [0:1023];
    reg [511:0] memory [0:31];
    integer issue_count = 0;
    integer completion_count = 0;
    integer model_slot = 0;
    integer model_credit = 32;
    bit model_granted = 0;
    bit held_valid = 0;
    bit pending_valid = 0;
    reg [255:0] pending_data;
    integer reads = 0;
    integer grants = 0;
    integer commands = 0;

    edrv32_npu_writeback dut (
        .clk_i(clk),
        .rst_n_i(rst_n),
        .cancel_i(cancel),
        .writeback_valid_i(wb_valid),
        .writeback_tag_i(wb_tag),
        .writeback_data_i(wb_data),
        .pair_reserve_i(reserve),
        .pair_result_slot_o(slot),
        .result_credit_o(credit),
        .result_chunk_valid_o(chunk_valid),
        .result_chunk_ready_i(chunk_ready),
        .result_chunk_base_o(chunk_base),
        .result_chunk_pairs_o(chunk_pairs),
        .result_chunk_row_o(chunk_row),
        .result_chunk_block_o(chunk_block),
        .result_chunk_pair_o(chunk_pair),
        .result_chunk_half_o(chunk_half),
        .result_chunk_last_o(chunk_last),
        .result_release_i(result_release),
        .result_rd_en_i(rd_en),
        .result_rd_index_i({rd_index, rd_index}),
        .result_rd_plane_i(rd_plane),
        .result_rd_valid_o(rd_valid),
        .result_rd_data_o(rd_data),
        .cmd_done_o(cmd_done),
        .cmd_done_row_o(cmd_row),
        .cmd_done_block_o(cmd_block),
        .idle_o(idle)
    );

    task automatic tick;
        bit expected_rd_valid;
        bit expected_done;
        reg [255:0] expected_rd_data;
        chunk_t popped_chunk;
        begin
            @(posedge clk);
            expected_rd_valid = rst_n && !cancel && pending_valid;
            expected_rd_data = pending_data;
            expected_done = rst_n && !cancel && wb_valid && wb_tag[37];
            if (!rst_n || cancel) begin
                model_slot = 0;
                model_credit = 32;
                model_granted = 0;
                expected_chunks.delete();
                pending_valid = 0;
                held_valid = 0;
            end else begin
                if (held_valid && actual_chunk !== held_chunk)
                    $fatal(1, "FAIL unstable stalled chunk expected=%h actual=%h t=%0t",
                        held_chunk, actual_chunk, $time);
                held_valid = chunk_valid && !chunk_ready;
                held_chunk = actual_chunk;
                if (model_granted && chunk_valid)
                    $fatal(1, "FAIL second grant before release t=%0t", $time);
                if (chunk_valid) begin
                    if (expected_chunks.size() == 0 || actual_chunk !== expected_chunks[0])
                        $fatal(1, "FAIL chunk expected=%h actual=%h queued=%0d t=%0t",
                            expected_chunks[0], actual_chunk, expected_chunks.size(), $time);
                end
                if (chunk_valid && chunk_ready) begin
                    model_granted = 1;
                    granted_chunk = expected_chunks[0];
                    grants++;
                end
                if (result_release) begin
                    if (!model_granted) $fatal(1, "FAIL test released an ungranted chunk");
                    model_credit += int'(granted_chunk.pairs);
                    popped_chunk = expected_chunks.pop_front();
                    if (popped_chunk !== granted_chunk) $fatal(1, "FAIL release order");
                    model_granted = 0;
                end
                if (reserve) begin
                    // Credit that is released on this edge is available next cycle.
                    if (credit == 0) $fatal(1, "FAIL test allocated with no registered credit");
                    if (slot !== 5'(model_slot)) $fatal(1, "FAIL reservation slot");
                    model_slot = (model_slot + 1) % 32;
                    model_credit--;
                end
                pending_valid = rd_en;
                if (rd_en) pending_data = rd_plane ? memory[rd_index][511:256]
                    : memory[rd_index][255:0];
                if (wb_valid) memory[wb_tag[42:38]] = wb_data;
            end
            #1;
            if (credit !== 6'(model_credit) || slot !== 5'(model_slot))
                $fatal(1, "FAIL credit expected=%0d actual=%0d slot expected=%0d actual=%0d t=%0t",
                    model_credit, credit, model_slot, slot, $time);
            if (rd_valid !== expected_rd_valid)
                $fatal(1, "FAIL two-edge read valid expected=%b actual=%b t=%0t",
                    expected_rd_valid, rd_valid, $time);
            if (expected_rd_valid) begin
                reads++;
                if (rd_data !== expected_rd_data)
                    $fatal(1, "FAIL result data expected=%h actual=%h t=%0t",
                        expected_rd_data, rd_data, $time);
            end
            if (cmd_done !== expected_done)
                $fatal(1, "FAIL WB2 command done expected=%b actual=%b t=%0t",
                    expected_done, cmd_done, $time);
            if (expected_done) begin
                commands++;
                if (cmd_row !== wb_tag[11:0] || cmd_block !== wb_tag[14:12])
                    $fatal(1, "FAIL command done tag t=%0t", $time);
            end
        end
    endtask

    // Command lengths define the expected chunks independently of completion logic.
    task automatic prepare_command(input integer row_number, input integer block_number,
        input integer pairs, input bit half);
        chunk_t descriptor;
        integer base;
        reg [48:0] tag_value;
        begin
            base = model_slot;
            for (integer p = 0; p < pairs; p += 16) begin
                descriptor.base = 5'((base+p) % 32);
                descriptor.pairs = 5'(((pairs-p) > 16) ? 16 : (pairs-p));
                descriptor.row = 12'(row_number);
                descriptor.block_number = 3'(block_number);
                descriptor.first_pair = 11'(p);
                descriptor.half = half;
                descriptor.last = ((p+16) >= pairs);
                expected_chunks.push_back(descriptor);
            end
            for (integer p = 0; p < pairs; p++) begin
                tag_value = 0;
                tag_value[11:0] = 12'(row_number);
                tag_value[14:12] = 3'(block_number);
                tag_value[25:15] = 11'(p);
                tag_value[26] = half;
                tag_value[37] = (p == pairs-1);
                tag_value[42:38] = 5'(model_slot);
                issued_tags[issue_count] = tag_value;
                for (integer lane = 0; lane < 64; lane++) begin
                    issued_vectors[issue_count][8*lane +: 8] = (half && lane >= 32)
                        ? 8'd0 : 8'(row_number*13 + block_number*29 + p*3 + lane*7);
                end
                issue_count++;
                reserve = 1;
                tick();
                result_release = 0;
                wb_valid = 0;
            end
            reserve = 0;
        end
    endtask

    task automatic complete_pairs(input integer pairs);
        begin
            for (integer p = 0; p < pairs; p++) begin
                wb_valid = 1;
                wb_tag = issued_tags[completion_count];
                wb_data = issued_vectors[completion_count];
                tick();
                completion_count++;
            end
            wb_valid = 0;
        end
    endtask

    task automatic grant_and_read;
        integer planes;
        begin
            if (!chunk_valid) $fatal(1, "FAIL completed chunk was not offered t=%0t", $time);
            chunk_ready = 1;
            tick();
            chunk_ready = 0;
            planes = granted_chunk.half ? 1 : 2;
            for (integer plane = 0; plane < planes; plane++) begin
                for (integer p = 0; p < int'(granted_chunk.pairs); p++) begin
                    rd_en = 1;
                    rd_index = 5'((int'(granted_chunk.base)+p) % 32);
                    rd_plane = 1'(plane);
                    tick();
                end
            end
            rd_en = 0;
            tick();
            tick();
        end
    endtask

    task automatic release_chunk;
        begin
            result_release = 1;
            tick();
            result_release = 0;
        end
    endtask

    task automatic cancel_work;
        begin
            cancel = 1;
            tick();
            cancel = 0;
            wb_valid = 0;
            reserve = 0;
            rd_en = 0;
            chunk_ready = 0;
            result_release = 0;
            completion_count = issue_count;
            if (!idle || chunk_valid || rd_valid || cmd_done)
                $fatal(1, "FAIL cancel did not clear controls t=%0t", $time);
        end
    endtask

    initial begin
        tick();
        tick();
        rst_n = 1;
        tick();
        if (!idle || credit != 32) $fatal(1, "FAIL initial state");

        // All 32 slots are reserved before any WB2, while DMA stays blocked.
        prepare_command(11, 3, 20, 0);
        prepare_command(11, 4, 12, 1);
        if (credit != 0 || chunk_valid || idle) $fatal(1, "FAIL first-item reservations");
        repeat (50) tick();
        complete_pairs(32);
        if (credit != 0) $fatal(1, "FAIL WB2 incorrectly released credit");
        repeat (300) tick();
        grant_and_read();
        repeat (200) tick();
        if (credit != 0 || chunk_valid) $fatal(1, "FAIL grant incorrectly released credit");
        release_chunk();
        if (credit != 16) $fatal(1, "FAIL release credit");
        // Wrap into slots 0..4 while the two older command tails remain owned.
        prepare_command(12, 0, 5, 0);
        complete_pairs(5);
        repeat (3) begin
            grant_and_read();
            release_chunk();
        end
        if (!idle || credit != 32) $fatal(1, "FAIL initial drain");

        // Up to 32 short commands need distinct metadata, including queue pointer wrap.
        for (integer round_number = 0; round_number < 3; round_number++) begin
            for (integer c = 0; c < 32; c++)
                prepare_command(30+round_number, c % 8, 1, (c % 2) != 0);
            complete_pairs(32);
            repeat (31) tick();
            for (integer c = 0; c < 32; c++) begin
                grant_and_read();
                release_chunk();
            end
            if (!idle || credit != 32) $fatal(1, "FAIL short-command drain");
        end

        // Release, allocation and a closing WB2 share an edge: net credit is +3-1.
        prepare_command(70, 0, 3, 0);
        complete_pairs(3);
        grant_and_read();
        prepare_command(70, 1, 2, 1);
        complete_pairs(1);
        wb_valid = 1;
        wb_tag = issued_tags[completion_count];
        wb_data = issued_vectors[completion_count];
        completion_count++;
        result_release = 1;
        prepare_command(70, 2, 1, 0);
        complete_pairs(1);
        repeat (2) begin
            grant_and_read();
            release_chunk();
        end
        if (!idle) $fatal(1, "FAIL simultaneous credit drain");

        // A tail chunk itself straddles ring slot 31 and reads both planes alternately.
        prepare_command(71, 0, 25, 0);
        complete_pairs(25);
        repeat (2) begin
            grant_and_read();
            release_chunk();
        end
        prepare_command(72, 1, 10, 0);
        complete_pairs(10);
        grant_and_read();
        for (integer p = 0; p < 10; p++) begin
            for (integer plane = 0; plane < 2; plane++) begin
                rd_en = 1;
                rd_index = 5'((int'(granted_chunk.base)+p) % 32);
                rd_plane = 1'(plane);
                tick();
            end
        end
        rd_en = 0;
        tick();
        tick();
        release_chunk();

        // Cancel idle, in-flight reservations, partial chunk, offered chunk and DMA read.
        cancel_work();
        prepare_command(80, 0, 2, 1);
        cancel_work();
        prepare_command(81, 1, 3, 0);
        complete_pairs(1);
        cancel_work();
        prepare_command(82, 2, 2, 1);
        complete_pairs(2);
        cancel_work();
        prepare_command(83, 3, 1, 0);
        complete_pairs(1);
        chunk_ready = 1;
        tick();
        chunk_ready = 0;
        rd_en = 1;
        rd_index = granted_chunk.base;
        tick();
        cancel_work();
        prepare_command(84, 4, 17, 1);
        complete_pairs(17);
        repeat (2) begin
            grant_and_read();
            release_chunk();
        end
        if (!idle || credit != 32 || expected_chunks.size() != 0)
            $fatal(1, "FAIL final state idle=%b credit=%0d queued=%0d",
                idle, credit, expected_chunks.size());
        $display("PASS writeback: reads=%0d chunks=%0d commands=%0d, credit/stalls/wrap/cancel",
            reads, grants, commands);
        $finish;
    end
endmodule
