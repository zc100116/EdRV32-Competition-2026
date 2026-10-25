`timescale 1ns/1ps
`include "edrv32_uop.vh"

module tb_frontend_early_redirect #(parameter DUAL_WINDOW=0);
    localparam [31:0] RESET_PC = 32'h8000_0000;

    reg clk;
    reg rst_n;
    reg block_valid;
    wire block_ready;
    reg [31:0] block_addr;
    reg [31:0] block_data;
    reg block_error;
    reg [`EDRV32_EPOCH_W-1:0] block_epoch;
    reg block_predicted_taken0;
    reg [31:0] block_predicted_target0;
    reg [1:0] block_predictor_meta0;
    reg block_predicted_taken1;
    reg [31:0] block_predicted_target1;
    reg [1:0] block_predictor_meta1;
    wire prediction_redirect_valid;
    wire [31:0] prediction_redirect_target;
    reg [`EDRV32_EPOCH_W-1:0] prediction_redirect_epoch;
    integer checks;

    initial clk = 1'b0;
    always #5 clk = ~clk;

    edrv32_if2_stage #(.RESET_PC(RESET_PC), .DUAL_WINDOW(DUAL_WINDOW)) u_dut (
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
        .block_predictor_meta0_i(block_predictor_meta0),
        .block_predicted_taken1_i(block_predicted_taken1),
        .block_predicted_target1_i(block_predicted_target1),
        .block_predictor_meta1_i(block_predictor_meta1),
        .window_valid_o(),
        .window_ready_i(1'b0),
        .halfword0_o(),
        .halfword1_o(),
        .halfword1_valid_o(),
        .window_pc_o(),
        .halfword0_error_o(),
        .halfword1_error_o(),
        .window_epoch_o(),
        .window_predicted_taken_o(),
        .window_predicted_target_o(),
        .prediction_redirect_valid_o(prediction_redirect_valid),
        .prediction_redirect_target_o(prediction_redirect_target),
        .prediction_redirect_fire_i(prediction_redirect_valid),
        .prediction_redirect_epoch_i(prediction_redirect_epoch),
        .hpm_append_hw1_o(),
        .hpm_append_hw2_o(),
        .hpm_consume_hw1_o(),
        .hpm_consume_hw2_o(),
        .hpm_discard_block_o(),
        .redirect_fire_i(1'b0),
        .redirect_target_i(32'd0),
        .redirect_epoch_i({`EDRV32_EPOCH_W{1'b0}}),
        .kill_i(1'b0)
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

    task automatic reset_case;
        begin
            block_valid = 1'b0;
            block_epoch = {`EDRV32_EPOCH_W{1'b0}};
            prediction_redirect_epoch =
                {{(`EDRV32_EPOCH_W-1){1'b0}}, 1'b1};
            rst_n = 1'b0;
            repeat (2) @(posedge clk);
            rst_n = 1'b1;
            @(negedge clk);
        end
    endtask

    task automatic present_block;
        input [31:0] addr_i;
        input [31:0] data_i;
        input pred0_i;
        input [31:0] target0_i;
        input pred1_i;
        input [31:0] target1_i;
        begin
            block_addr = addr_i;
            block_data = data_i;
            block_predicted_taken0 = pred0_i;
            block_predicted_target0 = target0_i;
            block_predictor_meta0 = {pred0_i, pred0_i};
            block_predicted_taken1 = pred1_i;
            block_predicted_target1 = target1_i;
            block_predictor_meta1 = {pred1_i, pred1_i};
            block_valid = 1'b1;
        end
    endtask

    initial begin
        checks = 0;
        rst_n = 1'b0;
        block_valid = 1'b0;
        block_addr = RESET_PC;
        block_data = 32'd0;
        block_error = 1'b0;
        block_epoch = {`EDRV32_EPOCH_W{1'b0}};
        block_predicted_taken0 = 1'b0;
        block_predicted_target0 = 32'd0;
        block_predictor_meta0 = 2'b00;
        block_predicted_taken1 = 1'b0;
        block_predicted_target1 = 32'd0;
        block_predictor_meta1 = 2'b00;
        prediction_redirect_epoch = {{(`EDRV32_EPOCH_W-1){1'b0}}, 1'b1};

        // A complete compressed prediction in slot 0 redirects on the block
        // append edge and trims the younger upper halfword.
        reset_case();
        present_block(RESET_PC, 32'h0001_0001, 1'b1, 32'h9000_0000,
                      1'b0, 32'd0);
        #1;
        check_true(block_ready && prediction_redirect_valid &&
                   prediction_redirect_target == 32'h9000_0000,
                   "slot0 compressed prediction redirects at append");
        @(posedge clk); #1;
        block_valid = 1'b0;
        check_true(u_dut.count_r == 3'd1 &&
                   u_dut.prediction_redirected_r[u_dut.head_r] &&
                   u_dut.consume_pc_r == RESET_PC &&
                   u_dut.expected_block_addr_r == 32'h9000_0000,
                   "append redirect retains only the branch and starts target stream");
        check_true(!prediction_redirect_valid,
                   "redirected branch cannot request a second redirect");
        block_epoch = prediction_redirect_epoch;
        prediction_redirect_epoch = 2'd2;
        present_block(32'h9000_0000, 32'h0001_0001,
                      1'b1, 32'h9000_1000, 1'b0, 32'd0);
        #1;
        check_true(prediction_redirect_valid &&
                   prediction_redirect_target == 32'h9000_1000,
                   "younger target-stream prediction may chain at append");
        @(posedge clk); #1;
        block_valid = 1'b0;
        check_true(u_dut.count_r == 3'd1 &&
                   u_dut.consume_pc_r == 32'h9000_0000,
                   "older marked branch keeps its target during chained redirect");
        check_true(u_dut.prediction_redirected_r[u_dut.head_r] &&
                   u_dut.expected_block_addr_r == 32'h9000_1000,
                   "chained redirect retains and marks the younger branch");

        // A slot-0 32-bit branch is complete in this block; both halfwords
        // must be retained even though the redirect is issued immediately.
        reset_case();
        present_block(RESET_PC, 32'h1234_0063, 1'b1, 32'h9000_0100,
                      1'b0, 32'd0);
        #1;
        check_true(prediction_redirect_valid,
                   "complete slot0 32-bit prediction redirects at append");
        @(posedge clk); #1;
        block_valid = 1'b0;
        check_true(u_dut.count_r == 3'd2 &&
                   u_dut.prediction_redirected_r[u_dut.head_r] &&
                   !u_dut.prediction_redirected_r[u_dut.second_head_w],
                   "slot0 32-bit redirect retains branch continuation only");

        // A compressed prediction in slot 1 retains the older slot-0
        // instruction and marks only the predicted branch.
        reset_case();
        present_block(RESET_PC, 32'h0001_0001, 1'b0, 32'd0,
                      1'b1, 32'h9000_0200);
        #1;
        check_true(prediction_redirect_valid &&
                   prediction_redirect_target == 32'h9000_0200,
                   "slot1 compressed prediction redirects at append");
        @(posedge clk); #1;
        block_valid = 1'b0;
        check_true(u_dut.count_r == 3'd2 &&
                   !u_dut.prediction_redirected_r[u_dut.head_r] &&
                   u_dut.prediction_redirected_r[u_dut.second_head_w],
                   "slot1 redirect preserves the older lower instruction");
        @(posedge clk); #1;
        check_true(u_dut.count_r == 3'd1 &&
                   u_dut.consume_pc_r == RESET_PC + 32'd2 &&
                   !prediction_redirect_valid,
                   "older instruction consumes before the marked slot1 branch");
        @(posedge clk); #1;
        check_true(u_dut.count_r == 3'd0 &&
                   u_dut.consume_pc_r == 32'h9000_0200,
                   "marked slot1 branch transfers control exactly once");

        // A predicted 32-bit instruction starting in slot 1 cannot redirect
        // until the next block supplies its continuation.  That older pending
        // prediction must beat stale/new predictions in the continuation block.
        reset_case();
        present_block(RESET_PC, 32'h00b3_0001, 1'b0, 32'd0,
                      1'b1, 32'h9000_0300);
        #1;
        check_true(!prediction_redirect_valid,
                   "cross-block slot1 prediction waits for its continuation");
        @(posedge clk); #1;
        block_valid = 1'b0;
        check_true(u_dut.cross_block_prediction_r,
                   "cross-block prediction target is retained locally");
        @(posedge clk); #1;
        @(negedge clk);
        present_block(RESET_PC + 32'd4, 32'ha001_5678,
                      1'b1, 32'hdead_0000,
                      1'b1, 32'hdead_0002);
        #1;
        check_true(prediction_redirect_valid &&
                   prediction_redirect_target == 32'h9000_0300,
                   "older cross-block prediction wins on continuation append");
        @(posedge clk); #1;
        block_valid = 1'b0;
        check_true(u_dut.count_r == 3'd2 &&
                   u_dut.prediction_redirected_r[u_dut.head_r] &&
                   u_dut.expected_block_addr_r == 32'h9000_0300,
                   "continuation append trims the younger upper instruction");
        check_true(!prediction_redirect_valid,
                   "completed cross-block prediction is not replayed");

        // Direct targets are formed from instruction bits even with no BTB
        // entry. Conditional direction comes from the sampled BHT bit.
        reset_case();
        present_block(RESET_PC, 32'h0080_006f, 1'b0, 32'd0,
                      1'b0, 32'd0); // JAL +8
        #1;
        check_true(prediction_redirect_valid &&
                   prediction_redirect_target == RESET_PC + 32'd8,
                   "BTB-miss JAL redirects from decoded immediate");

        reset_case();
        present_block(RESET_PC, 32'h0000_1463, 1'b0, 32'd0,
                      1'b0, 32'd0); // BNE +8
        block_predictor_meta0 = 2'b10;
        #1;
        check_true(prediction_redirect_valid &&
                   prediction_redirect_target == RESET_PC + 32'd8,
                   "BTB-miss branch uses taken BHT and decoded target");
        block_predictor_meta0 = 2'b00;
        #1;
        check_true(!prediction_redirect_valid,
                   "BTB-miss branch obeys not-taken BHT");

        reset_case();
        present_block(RESET_PC, 32'ha001_0001, 1'b0, 32'd0,
                      1'b0, 32'd0); // C.NOP; C.J +0
        #1;
        check_true(prediction_redirect_valid &&
                   prediction_redirect_target == RESET_PC + 32'd2,
                   "BTB-miss compressed JAL slot1 uses decoded target");

        reset_case();
        present_block(RESET_PC, 32'h006f_0001, 1'b0, 32'd0,
                      1'b0, 32'd0); // C.NOP; first halfword of JAL +8
        #1;
        check_true(!prediction_redirect_valid,
                   "BTB-miss cross-block JAL waits for continuation");
        @(posedge clk); #1;
        block_valid = 1'b0;
        check_true(u_dut.cross_block_prediction_r,
                   "BTB-miss cross-block JAL is remembered");
        @(negedge clk);
        present_block(RESET_PC + 32'd4, 32'h0001_0080,
                      1'b0, 32'd0, 1'b0, 32'd0);
        #1;
        check_true(prediction_redirect_valid &&
                   prediction_redirect_target == RESET_PC + 32'd10,
                   "BTB-miss cross-block JAL target uses full instruction");

        $display("PASS: IF2 append-time prediction redirect (%0d checks)", checks);
        $finish;
    end
endmodule
