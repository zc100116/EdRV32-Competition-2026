`timescale 1ns/1ps

module tb_branch_predictor #(parameter FETCH_WIDE=0);
    reg clk;
    reg rst_n;
    reg invalidate;
    reg [31:0] query_pc0;
    wire predicted_taken0;
    wire [31:0] predicted_target0;
    wire [1:0] query_meta0;
    reg [31:0] query_pc1;
    wire predicted_taken1;
    wire [31:0] predicted_target1;
    wire predicted_taken2,predicted_taken3;
    wire [31:0] predicted_target2,predicted_target3;
    wire [1:0] query_meta2;
    reg update_valid;
    reg [31:0] update_pc;
    reg update_conditional;
    reg update_unconditional;
    reg update_indirect;
    reg update_taken;
    reg [31:0] update_target;
    reg update_push;
    reg update_pop;
    reg [31:0] update_link;
    integer checks;

    initial clk = 1'b0;
    always #5 clk = ~clk;

    edrv32_branch_predictor #(.RAS_DEPTH(4),.FETCH_WIDE(FETCH_WIDE)) u_dut (
        .clk_i(clk), .rst_n_i(rst_n), .invalidate_i(invalidate),
        .query_pc0_i(query_pc0), .predicted_taken0_o(predicted_taken0),
        .predicted_target0_o(predicted_target0),
        .query_meta0_o(query_meta0),
        .query_pc1_i(query_pc1), .predicted_taken1_o(predicted_taken1),
        .predicted_target1_o(predicted_target1),
        .query_pc2_i(query_pc0),.predicted_taken2_o(predicted_taken2),
        .predicted_target2_o(predicted_target2),.query_meta2_o(query_meta2),
        .query_pc3_i(query_pc1),.predicted_taken3_o(predicted_taken3),
        .predicted_target3_o(predicted_target3),.query_meta3_o(),
        .update_valid_i(update_valid), .update_pc_i(update_pc),
        .update_is_conditional_i(update_conditional),
        .update_is_unconditional_i(update_unconditional),
        .update_is_indirect_i(update_indirect),
        .update_taken_i(update_taken), .update_target_i(update_target),
        .update_ras_push_i(update_push), .update_ras_pop_i(update_pop),
        .update_link_addr_i(update_link)
    );

    task automatic check_true;
        input condition;
        input [8*96-1:0] message;
        begin
            checks = checks + 1;
            if(FETCH_WIDE!=0 && ({predicted_taken0,predicted_target0,query_meta0,
                    predicted_taken1,predicted_target1} !==
                {predicted_taken2,predicted_target2,query_meta2,predicted_taken3,predicted_target3}))
                $fatal(1,"Four predictor queries diverged for identical PCs");
            if (!condition) begin
                $display("FAIL: %0s", message);
                $fatal(1);
            end
        end
    endtask

    task automatic train;
        input [31:0] pc;
        input conditional;
        input unconditional;
        input taken;
        input [31:0] target;
        input push;
        input pop;
        input [31:0] link_address;
        begin
            @(negedge clk);
            update_valid = 1'b1;
            update_pc = pc;
            update_conditional = conditional;
            update_unconditional = unconditional;
            update_taken = taken;
            update_target = target;
            update_push = push;
            update_pop = pop;
            update_link = link_address;
            @(posedge clk); #1;
            update_valid = 1'b0;
            update_push = 1'b0;
            update_pop = 1'b0;
            // Predictor training is deliberately registered at its boundary.
            // The first edge accepts the EX training packet; the second edge
            // applies it to BTB/BHT/RAS state.
            @(posedge clk); #1;
        end
    endtask

    initial begin
        rst_n = 1'b0;
        invalidate = 1'b0;
        query_pc0 = 32'h8000_0100;
        query_pc1 = 32'h8000_0102;
        update_valid = 1'b0;
        update_pc = 32'd0;
        update_conditional = 1'b0;
        update_unconditional = 1'b0;
        update_indirect = 1'b1;
        update_taken = 1'b0;
        update_target = 32'd0;
        update_push = 1'b0;
        update_pop = 1'b0;
        update_link = 32'd0;
        checks = 0;
        repeat (3) @(posedge clk);
        rst_n = 1'b1;
        #1;

        check_true(!predicted_taken0 && !predicted_taken1,
                   "both cold predictor slots are not taken");
        @(negedge clk);
        update_valid = 1'b1;
        update_pc = 32'h8000_0100;
        update_conditional = 1'b1;
        update_unconditional = 1'b0;
        update_taken = 1'b1;
        update_target = 32'h8000_0080;
        @(posedge clk); #1;
        update_valid = 1'b0;
        check_true(predicted_taken0 &&
                   (predicted_target0 == 32'h8000_0080) &&
                   !u_dut.btb_valid_r[5'h00] &&
                   (u_dut.bht_r[2*8'h80 +: 2] == 2'b01),
                   "registered training forwards before the physical table write");
        @(posedge clk); #1;
        query_pc0 = 32'h8000_0100;
        query_pc1 = 32'h8000_0102; #1;
        check_true(predicted_taken0 && predicted_target0 == 32'h8000_0080 &&
                   !predicted_taken1,
                   "slot0 taken conditional is independent from cold slot1");

        train(32'h8000_0102, 1'b0, 1'b1, 1'b1,
              32'h8000_0180, 1'b0, 1'b0, 32'd0);
        #1;
        check_true(predicted_taken0 && predicted_taken1 &&
                   predicted_target1 == 32'h8000_0180,
                   "slot1 performs an independent parallel BTB query");

        train(32'h8000_0100, 1'b1, 1'b0, 1'b0,
              32'h8000_0080, 1'b0, 1'b0, 32'd0);
        #1;
        check_true(!predicted_taken0 && predicted_taken1,
                   "slot0 BHT update does not disturb slot1 prediction");

        // A pending write to an occupied index replaces that index for lookup;
        // a mismatching old tag must not leak through behind the forwarding
        // mux during the one-cycle physical RAM write delay.
        train(32'h8000_0120, 1'b0, 1'b1, 1'b1,
              32'h8000_0220, 1'b0, 1'b0, 32'd0);
        query_pc0 = 32'h8000_0120;
        query_pc1 = 32'h9000_0120;
        @(negedge clk);
        update_valid = 1'b1;
        update_pc = 32'h9000_0120;
        update_conditional = 1'b0;
        update_unconditional = 1'b1;
        update_taken = 1'b1;
        update_target = 32'h9000_0220;
        update_push = 1'b0;
        update_pop = 1'b0;
        @(posedge clk); #1;
        update_valid = 1'b0;
        check_true(!predicted_taken0 && predicted_taken1 &&
                   (predicted_target1 == 32'h9000_0220),
                   "forwarded BTB overwrite masks the stale same-index tag");
        @(posedge clk); #1;

        // Back-to-back updates must retain one-update-per-cycle throughput.
        // Two taken observations move a cold counter to strongly taken.  One
        // following not-taken observation must therefore remain predicted
        // taken; this detects a dropped second packet.
        query_pc0 = 32'h8000_0500;
        @(negedge clk);
        update_valid = 1'b1;
        update_pc = 32'h8000_0500;
        update_conditional = 1'b1;
        update_unconditional = 1'b0;
        update_taken = 1'b1;
        update_target = 32'h8000_0580;
        @(posedge clk); #1;
        @(negedge clk);
        update_valid = 1'b1;
        update_pc = 32'h8000_0500;
        update_conditional = 1'b1;
        update_taken = 1'b1;
        update_target = 32'h8000_0580;
        @(posedge clk); #1;
        update_valid = 1'b0;
        @(posedge clk); #1;
        train(32'h8000_0500, 1'b1, 1'b0, 1'b0,
              32'h8000_0580, 1'b0, 1'b0, 32'd0);
        check_true(predicted_taken0,
                   "back-to-back same-index BHT updates are both retained");

        // Preserve the existing FENCE.I priority contract: BTB/RAS updates
        // are discarded on an invalidation edge, while BHT training remains
        // valid because direction history itself is not invalidated.
        train(32'h8000_0600, 1'b1, 1'b0, 1'b1,
              32'h8000_0680, 1'b0, 1'b0, 32'd0);
        train(32'h8000_0600, 1'b1, 1'b0, 1'b1,
              32'h8000_0680, 1'b0, 1'b0, 32'd0);
        @(negedge clk);
        invalidate = 1'b1;
        update_valid = 1'b1;
        update_pc = 32'h8000_0600;
        update_conditional = 1'b1;
        update_unconditional = 1'b0;
        update_taken = 1'b0;
        update_target = 32'h8000_0680;
        @(posedge clk); #1;
        invalidate = 1'b0;
        update_valid = 1'b0;
        @(posedge clk); #1;
        check_true(!u_dut.btb_valid_r[0] &&
                   (u_dut.bht_r[2*8'h00 +: 2] == 2'b10),
                   "invalidate drops BTB update but preserves BHT training");

        // Learn a return while the RAS is empty, then accept a call push.  The
        // known return must see the projected top immediately, before the
        // physical RAS pointer and payload update on the following edge.
        train(32'h8000_0308, 1'b0, 1'b1, 1'b1,
              32'hdead_beee, 1'b0, 1'b1, 32'd0);
        query_pc0 = 32'h8000_0308;
        @(negedge clk);
        update_valid = 1'b1;
        update_pc = 32'h8000_0700;
        update_conditional = 1'b0;
        update_unconditional = 1'b1;
        update_taken = 1'b1;
        update_target = 32'h8000_0800;
        update_push = 1'b1;
        update_pop = 1'b0;
        update_link = 32'h8000_0704;
        @(posedge clk); #1;
        update_valid = 1'b0;
        update_push = 1'b0;
        check_true((u_dut.ras_count_r == 0) && predicted_taken0 &&
                   (predicted_target0 == 32'h8000_0704),
                   "pending RAS push forwards the projected return target");
        @(posedge clk); #1;

        train(32'h8000_0200, 1'b0, 1'b1, 1'b1,
              32'h8000_0300, 1'b1, 1'b0, 32'h8000_0204);
        train(32'h8000_0308, 1'b0, 1'b1, 1'b1,
              32'hdead_beee, 1'b0, 1'b1, 32'd0);
        // The resolved return above learns its BTB return type and consumes
        // the old RAS top.  A later call supplies the top that the next
        // prediction of the now-known return must select.
        train(32'h8000_0400, 1'b0, 1'b1, 1'b1,
              32'h8000_0308, 1'b1, 1'b0, 32'h8000_0404);
        query_pc0 = 32'h8000_0308;
        query_pc1 = 32'h8000_030a; #1;
        check_true(predicted_taken0 && predicted_target0 == 32'h8000_0404,
                   "return BTB entry selects RAS top");

        @(negedge clk); invalidate = 1'b1;
        @(posedge clk); #1; invalidate = 1'b0;
        check_true(!predicted_taken0 && !predicted_taken1,
                   "FENCE.I-style invalidate clears both BTB query slots");

        // Direct branches train direction but leave the target table for
        // indirect jumps. IF2 consumes the raw BHT bit in query_meta0.
        update_indirect = 1'b0;
        query_pc0 = 32'h8000_0800;
        train(32'h8000_0800, 1'b1, 1'b0, 1'b1,
              32'h8000_0810, 1'b0, 1'b0, 32'd0);
        train(32'h8000_0800, 1'b1, 1'b0, 1'b1,
              32'h8000_0810, 1'b0, 1'b0, 32'd0);
        #1;
        check_true(!predicted_taken0 && query_meta0 == 2'b10,
                   "direct branch trains BHT without allocating BTB");
        update_indirect = 1'b1;
        train(32'h8000_0800, 1'b0, 1'b1, 1'b1,
              32'h8000_0900, 1'b0, 1'b0, 32'd0);
        #1;
        check_true(predicted_taken0 && query_meta0[0] &&
                   predicted_target0 == 32'h8000_0900,
                   "indirect jump allocates BTB at the same index");

        $display("PASS: branch predictor BTB/BHT/RAS (%0d checks)", checks);
        $finish;
    end
endmodule
