// File: tb.sv
// Spec: npu-testplan PP-01/02/03; npu-spec 2.6, 5.6.
// Description: Signed max/tie across five planes, exact thresholds and two-pixel masks.
// Clock: clk_npu.
`timescale 1ns/1ps
module tb;
    bit clk = 0;
    always #2.5 clk = !clk;
    bit rst_n = 0;
    bit clear = 0;
    bit valid = 0;
    logic [255:0] data_value = 0;
    logic [1:0] head = 0;
    logic [2:0] block_value = 0;
    bit plane = 0;
    logic [26:0] thresholds = 0;
    logic [31:0] probability_threshold = 1000;
    logic [31:0] probability = 1001;
    wire prob_en;
    wire [9:0] addr0;
    wire [9:0] addr1;
    wire [1:0] candidate_valid;
    wire [31:0] candidate0;
    wire [31:0] candidate1;
    wire idle;
    int observed;
    logic [6:0] expected_class;
    logic [7:0] expected_best;
    int expected_head;
    logic [1:0] expected_mask;
    edrv32_npu_post_classify dut (
        .clk_i(clk),
        .rst_n_i(rst_n),
        .clear_i(clear),
        .valid_i(valid),
        .data_i(data_value),
        .head_i(head),
        .row_i(12'd1),
        .pair_i(11'd1),
        .block_i(block_value),
        .plane_i(plane),
        .int8_th_i(thresholds),
        .prob_th_i(probability_threshold),
        .prob_en_o(prob_en),
        .prob_addr0_o(addr0),
        .prob_addr1_o(addr1),
        .prob_data0_i(probability),
        .prob_data1_i(probability),
        .candidate_valid_o(candidate_valid),
        .candidate0_o(candidate0),
        .candidate1_o(candidate1),
        .idle_o(idle)
    );
    always @(negedge clk) begin
        logic [12:0] anchor;
        logic [31:0] expected;
        if (prob_en && (addr0 != {2'(expected_head), 8'(expected_best)} || addr1 != addr0))
            $fatal(1, "FAIL lookup addresses %x %x", addr0, addr1);
        if (candidate_valid != 0) begin
            anchor = expected_head == 0 ? 82 : expected_head == 1 ? 3882 : 4822;
            expected = {4'd0, 8'(expected_best), 7'(expected_class), 13'(anchor)};
            if (candidate_valid != expected_mask || candidate0 != expected
                || candidate1 != (expected + 1))
                $fatal(1, "FAIL candidate mask=%b/%b expected=%x actual=%x %x time=%0t",
                    expected_mask, candidate_valid, expected, candidate0, candidate1, $time);
            observed++;
        end
    end
    task automatic tick;
        @(posedge clk);
        #1;
    endtask
    task automatic run_case(input int h, input logic [8:0] threshold, input logic [7:0] raw_best,
        input int winning_class, input int duplicate_class, input int prob,
        input logic [1:0] mask_value);
        clear = 1;
        valid = 0;
        tick;
        clear = 0;
        observed = 0;
        expected_head = h;
        expected_best = 8'(raw_best);
        expected_class = 7'(winning_class);
        expected_mask = mask_value;
        head = 2'(h);
        thresholds = {3{9'(threshold)}};
        probability = 32'(prob);
        for (int p = 0; p < 5; p++) begin
            data_value = {32{8'h80}};
            if (winning_class/16 == p)
                for (int pixel = 0; pixel < 2; pixel++)
                    data_value[128*pixel+8*(winning_class%16)+:8] = 8'(raw_best);
            if (duplicate_class/16 == p)
                for (int pixel = 0; pixel < 2; pixel++)
                    data_value[128*pixel+8*(duplicate_class%16)+:8] = 8'(raw_best);
            valid = 1;
            block_value = 3'(p/2);
            plane = 1'(p%2);
            tick;
        end
        valid = 0;
        repeat (14) tick;
        if (observed != (mask_value == 0 ? 0 : 1) || !idle)
            $fatal(1, "FAIL missing/extra candidate observed=%0d mask=%b", observed, mask_value);
    endtask
    initial begin
        repeat (3) tick;
        rst_n = 1;
        run_case(0, 103, 102, 0, 79, 1001, 0);
        run_case(0, 103, 103, 0, 79, 1001, 3);
        run_case(0, 103, 104, 15, 16, 1001, 3);
        run_case(1, 105, 105, 16, 63, 1001, 3);
        run_case(2, 103, 103, 63, 64, 1001, 3);
        run_case(2, -128, -128, 0, 79, 1001, 3);
        run_case(1, 127, 127, 64, 79, 1001, 3);
        run_case(2, 128, 127, 79, 79, 1001, 0);
        run_case(0, -128, 127, 79, 79, 999, 0);
        run_case(0, -128, 127, 79, 79, 1000, 0);
        run_case(0, -128, 127, 79, 79, 1001, 3);
        $display("PASS signed max/tie classes0/15/16/63/64/79 and both threshold boundaries");
        $finish;
    end
endmodule
