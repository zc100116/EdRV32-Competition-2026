`timescale 1ns/1ps
`include "edrv32_uop.vh"

module tb_align_stage;

    reg clk;
    reg rst_n;
    reg window_valid;
    reg [15:0] halfword0;
    reg [15:0] halfword1;
    reg halfword1_valid;
    reg [31:0] pc;
    reg halfword0_error;
    reg halfword1_error;
    reg [`EDRV32_EPOCH_W-1:0] epoch;
    reg predicted_taken;
    reg [31:0] predicted_target;
    wire window_ready;
    wire window_accept;
    wire [1:0] window_halfwords;
    wire candidate_valid;
    wire candidate_ready;
    wire [31:0] candidate_pc;
    wire [31:0] candidate_instr;
    wire [31:0] candidate_raw_instr;
    wire candidate_is_compressed;
    wire candidate_fetch_fault;
    wire candidate_compressed_illegal;
    wire [`EDRV32_EPOCH_W-1:0] candidate_epoch;
    wire candidate_predicted_taken;
    wire [31:0] candidate_predicted_target;
    wire out_valid;
    reg out_accept;
    wire [31:0] out_pc;
    wire [31:0] out_instr;
    wire [31:0] out_raw_instr;
    wire out_is_compressed;
    wire out_fetch_fault;
    wire out_compressed_illegal;
    wire [`EDRV32_EPOCH_W-1:0] out_epoch;
    wire out_predicted_taken;
    wire [31:0] out_predicted_target;
    reg kill;
    integer checks;

    initial clk = 1'b0;
    always #5 clk = ~clk;

    task automatic check_true;
        input condition;
        input [8*80-1:0] message;
        begin
            checks = checks + 1;
            if (!condition) begin
                $display("FAIL: %0s", message);
                $fatal(1);
            end
        end
    endtask

    edrv32_align_stage u_dut (
        .clk_i(clk), .rst_n_i(rst_n),
        .window_valid_i(window_valid),
        .window_ready_o(window_ready),
        .window_accept_o(window_accept),
        .window_halfwords_o(window_halfwords),
        .halfword0_i(halfword0), .halfword1_i(halfword1),
        .halfword1_valid_i(halfword1_valid), .pc_i(pc),
        .halfword0_error_i(halfword0_error),
        .halfword1_error_i(halfword1_error),
        .epoch_i(epoch), .predicted_taken_i(predicted_taken),
        .predicted_target_i(predicted_target),
        .valid_o(out_valid), .ready_i(out_accept),
        .pc_o(out_pc), .instr_o(out_instr),
        .raw_instr_o(out_raw_instr),
        .is_compressed_o(out_is_compressed),
        .fetch_fault_o(out_fetch_fault),
        .compressed_illegal_o(out_compressed_illegal),
        .epoch_o(out_epoch), .predicted_taken_o(out_predicted_taken),
        .predicted_target_o(out_predicted_target), .kill_i(kill)
    );

    initial begin
        checks = 0;
        rst_n = 1'b0;
        window_valid = 1'b0;
        halfword0 = 16'd0;
        halfword1 = 16'd0;
        halfword1_valid = 1'b0;
        pc = 32'd0;
        halfword0_error = 1'b0;
        halfword1_error = 1'b0;
        epoch = 2'd0;
        predicted_taken = 1'b0;
        predicted_target = 32'd0;
        out_accept = 1'b0;
        kill = 1'b0;

        repeat (2) @(posedge clk);
        rst_n = 1'b1;
        #1;
        check_true(!out_valid && window_ready, "ALIGN reset leaves output empty");

        // Compressed instruction only consumes the first halfword.
        window_valid = 1'b1;
        halfword0 = 16'h0001; // C.NOP
        halfword1 = 16'h0001;
        halfword1_valid = 1'b1;
        pc = 32'h8000_0000;
        epoch = 2'd1;
        predicted_taken = 1'b1;
        predicted_target = 32'h8000_0100;
        #1;
        check_true(window_accept && window_halfwords == 2'd1, "C instruction consumes one halfword");
        @(posedge clk); #1;
        window_valid = 1'b0;
        check_true(out_valid && out_pc == 32'h8000_0000, "ALIGN registers compressed PC");
        check_true(out_instr == 32'h0000_0013 && out_is_compressed, "ALIGN decompresses C.NOP");
        check_true(out_raw_instr == 32'h0000_0001, "ALIGN preserves raw compressed bits");
        check_true(out_epoch == 2'd1 && out_predicted_taken && out_predicted_target == 32'h8000_0100,
                   "ALIGN preserves scalar prediction metadata");

        // Backpressure holds every output bit and refuses another window.
        halfword0 = 16'h0001;
        pc = 32'h8000_0002;
        window_valid = 1'b1;
        #1;
        check_true(!window_ready && !window_accept,
                   "ALIGN backpressures IF_BUF while DECODE is stopped");
        check_true(out_pc == 32'h8000_0000 && out_instr == 32'h0000_0013,
                   "ALIGN payload stable under backpressure");

        // Accept old output and refill with an aligned 32-bit ADDI in one edge.
        out_accept = 1'b1;
        halfword0 = 16'h8293;
        halfword1 = 16'hffc0; // ffc08293 = addi x5,x1,-4
        halfword1_valid = 1'b1;
        pc = 32'h8000_0002;
        epoch = 2'd2;
        predicted_taken = 1'b0;
        predicted_target = 32'd0;
        #1;
        check_true(window_ready && window_accept && window_halfwords == 2'd2,
                   "ALIGN refills a 32-bit instruction on DECODE accept");
        @(posedge clk); #1;
        out_accept = 1'b0;
        window_valid = 1'b0;
        check_true(out_valid && out_instr == 32'hffc0_8293 && !out_is_compressed,
                   "ALIGN assembles cross-block 32-bit instruction");
        check_true(out_raw_instr == 32'hffc0_8293, "ALIGN preserves raw 32-bit instruction");
        check_true(!out_fetch_fault && !out_compressed_illegal && out_epoch == 2'd2,
                   "ALIGN clean 32-bit metadata");

        // A 32-bit prefix cannot be consumed before the second halfword exists.
        out_accept = 1'b1;
        @(posedge clk); #1;
        out_accept = 1'b0;
        window_valid = 1'b1;
        halfword0 = 16'h5013;
        halfword1_valid = 1'b0;
        pc = 32'h8000_0006;
        #1;
        check_true(window_ready && !window_accept && window_halfwords == 2'd2,
                   "ALIGN waits for crossing second halfword");
        halfword1 = 16'h1234;
        halfword1_valid = 1'b1;
        halfword1_error = 1'b1;
        #1;
        check_true(window_accept, "ALIGN accepts crossing instruction when complete");
        @(posedge clk); #1;
        window_valid = 1'b0;
        halfword1_error = 1'b0;
        check_true(out_instr == 32'h1234_5013 && out_fetch_fault,
                   "ALIGN includes second-halfword fetch error");

        // Illegal compressed encoding is carried as metadata, not hidden.
        out_accept = 1'b1;
        window_valid = 1'b1;
        halfword0 = 16'h0000;
        halfword1_valid = 1'b0;
        halfword0_error = 1'b0;
        pc = 32'h8000_000a;
        #1;
        check_true(window_accept && window_halfwords == 2'd1, "Illegal C still forms one instruction");
        @(posedge clk); #1;
        out_accept = 1'b0;
        window_valid = 1'b0;
        check_true(out_valid && out_compressed_illegal && !out_fetch_fault,
                   "ALIGN marks compressed illegal independently of fetch fault");

        // Registered kill wins over simultaneous downstream accept/new input.
        out_accept = 1'b1;
        window_valid = 1'b1;
        halfword0 = 16'h0001;
        kill = 1'b1;
        #1;
        check_true(!window_ready && !window_accept, "ALIGN kill blocks wrong-epoch capture");
        @(posedge clk); #1;
        kill = 1'b0;
        out_accept = 1'b0;
        window_valid = 1'b0;
        check_true(!out_valid, "ALIGN kill clears valid regardless of payload");

        $display("PASS: ALIGN stage (%0d checks)", checks);
        $finish;
    end

endmodule


