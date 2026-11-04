// File: tb_npu_mac_array.sv
// Spec: npu-testplan OP-01/02/04/07/08; datapath design 4.2/4.3/5.2 D1-C.
// Description: Independently model signed dot products and all ten register boundaries.
// Check full throughput, D2 input selection, local activation copies, tags and cancel.
// Clock: clk_npu, 10 ns test clock.
module tb_npu_mac_array;
    bit clk_i = 0;
    bit rst_n_i = 0;
    bit cancel_i = 0;
    bit term_valid_i = 0;
    bit term_first_i = 0;
    bit term_last_i = 0;
    bit [48:0] term_tag_i = 0;
    bit [1023:0] term_activation_i = 0;
    bit [2047:0] term_weight_i = 0;
    wire sum_valid_o;
    wire sum_first_o;
    wire sum_last_o;
    wire [48:0] sum_tag_o;
    wire [63:0] sum_fold_o;
    wire [1215:0] sum_data_o;
    wire mac_beat_o;
    wire idle_o;

    bit [11:0] expected_valid = 0;
    bit [11:0] expected_first = 0;
    bit [11:0] expected_last = 0;
    bit [48:0] expected_tag [0:11];
    bit [1215:0] expected_data [0:11];
    wire [2047:0] skew_weight_w;
    genvar skew_item;
    genvar skew_channel;
    generate
        for (skew_item = 0; skew_item < 8; skew_item++) begin : g_skew_item
            for (skew_channel = 0; skew_channel < 32; skew_channel++) begin : g_skew_channel
                if (skew_item == 0) begin : g_direct
                    assign skew_weight_w[8*(8*skew_channel+skew_item) +: 8] =
                        term_weight_i[8*(8*skew_channel+skew_item) +: 8];
                end else begin : g_skew
                    reg [8*skew_item-1:0] history;
                    always @(posedge clk_i)
                        history <= (history << 8) |
                            {{(8*skew_item-8){1'b0}}, term_weight_i[8*(8*skew_channel+skew_item) +: 8]};
                    assign skew_weight_w[8*(8*skew_channel+skew_item) +: 8] =
                        history[8*(skew_item-1) +: 8];
                end
            end
        end
    endgenerate
    int checked = 0;
    int cycle = 0;
    int seed = 32'h326ac851;

    always #5 clk_i = ~clk_i;

    edrv32_npu_mac_array dut (
        .clk_i(clk_i),
        .rst_n_i(rst_n_i),
        .cancel_i(cancel_i),

        .term_valid_i(term_valid_i),
        .term_first_i(term_first_i),
        .term_last_i(term_last_i),
        .term_tag_i(term_tag_i),
        .term_activation_i(term_activation_i),
        .term_weight_i(skew_weight_w),

        .sum_valid_o(sum_valid_o),
        .sum_first_o(sum_first_o),
        .sum_last_o(sum_last_o),
        .sum_tag_o(sum_tag_o),
        .sum_fold_o(sum_fold_o),
        .sum_data_o(sum_data_o),

        .mac_beat_o(mac_beat_o),
        .idle_o(idle_o)
    );

    // The reference uses scalar integer multiplication and one eight-term loop,
    // independently of the DUT's SIMD packaging and pairwise reduction tree.
    always @(posedge clk_i) begin : monitor
        int activation;
        int weight;
        int dot;
        int offset;
        cycle++;
        for (int stage = 11; stage > 0; stage--) begin
            expected_tag[stage] = expected_tag[stage-1];
            expected_data[stage] = expected_data[stage-1];
        end
        expected_first = {expected_first[10:0], term_first_i};
        expected_last = {expected_last[10:0], term_last_i};
        expected_tag[0] = term_tag_i;
        for (int pixel = 0; pixel < 2; pixel++) begin
            for (int channel = 0; channel < 32; channel++) begin
                dot = 0;
                for (int lane = 0; lane < 8; lane++) begin
                    offset = 256*(channel/8) + 128*pixel + 8*lane;
                    if (term_tag_i[48] && channel >= 16) offset += 64;
                    activation = int'($signed(term_activation_i[offset +: 8]));
                    weight = int'($signed(term_weight_i[8*(8*channel+lane) +: 8]));
                    dot += activation * weight;
                end
                expected_data[0][19*(32*pixel+channel) +: 19] = 19'(dot);
            end
        end
        if (!rst_n_i || cancel_i) expected_valid = 0;
        else expected_valid = {expected_valid[10:0], term_valid_i};
        #1;
        if (sum_valid_o !== expected_valid[11] || mac_beat_o !== expected_valid[0] ||
            idle_o !== !(|expected_valid))
            $fatal(1, "FAIL MAC valid/beat/idle cycle=%0d expected=%b actual=%b/%b/%b t=%0t",
                cycle, expected_valid, sum_valid_o, mac_beat_o, idle_o, $time);
        if (sum_valid_o) begin
            if (sum_first_o !== expected_first[11] || sum_last_o !== expected_last[11] ||
                sum_tag_o !== expected_tag[11] ||
                sum_fold_o !== {64{expected_tag[11][48]}})
                $fatal(1, "FAIL MAC control cycle=%0d tag exp=%h actual=%h t=%0t",
                    cycle, expected_tag[11], sum_tag_o, $time);
            for (int item = 0; item < 64; item++) begin
                if (sum_data_o[19*item +: 19] !== expected_data[11][19*item +: 19])
                    $fatal(1, "FAIL MAC item=%0d exp=%0d actual=%0d cycle=%0d t=%0t",
                        item, $signed(expected_data[11][19*item +: 19]),
                        $signed(sum_data_o[19*item +: 19]), cycle, $time);
            end
            checked++;
        end
    end

    task automatic drive_term(input int mode, input int pattern, input bit first,
        input bit last, input bit [48:0] tag);
        bit [255:0] activation;
        int value;
        @(negedge clk_i);
        term_valid_i = 1;
        term_first_i = first;
        term_last_i = last;
        term_tag_i = tag;
        term_tag_i[48] = (mode == 1);
        term_tag_i[26] = (mode != 0);
        activation = 0;
        for (int pixel = 0; pixel < 2; pixel++) begin
            for (int channel = 0; channel < 16; channel++) begin
                case (pattern)
                    0: value = -128;
                    1: value = 127;
                    2: value = (pixel == 0) ? -128 : 127;
                    3: value = channel == (int'(tag[2:0])) ? 127 : 0;
                    default: value = int'($urandom_range(0, 255)) - 128;
                endcase
                if ((mode != 1 && channel >= 8) || (mode == 2 && channel >= 4))
                    value = 0;
                activation[128*pixel+8*channel +: 8] = 8'(value);
            end
        end
        for (int copy_idx = 0; copy_idx < 4; copy_idx++)
            term_activation_i[256*copy_idx +: 256] = activation;
        for (int channel = 0; channel < 32; channel++) begin
            for (int lane = 0; lane < 8; lane++) begin
                case (pattern)
                    0: value = -128;
                    1: value = 127;
                    2: value = (channel % 2 == 0) ? 127 : -128;
                    3: value = channel - 16;
                    default: value = int'($urandom_range(0, 255)) - 128;
                endcase
                if (mode == 2 && (channel >= 16 || lane >= 4)) value = 0;
                term_weight_i[8*(8*channel+lane) +: 8] = 8'(value);
            end
        end
    endtask

    task automatic bubble(input int count);
        repeat (count) begin
            @(negedge clk_i);
            term_valid_i = 0;
            term_first_i = 0;
            term_last_i = 0;
            // Invalid payload still changes; it must not acquire validity.
            term_activation_i = ~term_activation_i;
            term_weight_i = ~term_weight_i;
        end
    endtask

    initial begin : stimulus
        bit [48:0] tag;
        int length;
        void'($urandom(seed));
        repeat (2) @(negedge clk_i);
        rst_n_i = 1;
        // Extremes and each of the eight lanes, ordinary, D2 and C4 half.
        for (int mode = 0; mode < 3; mode++) begin
            for (int pattern = 0; pattern < 4; pattern++) begin
                for (int lane = 0; lane < 8; lane++) begin
                    tag = 49'(lane);
                    drive_term(mode, pattern, lane == 0, lane == 7, tag);
                end
            end
        end
        bubble(12);
        // Back-to-back block/row tags and randomized signed arithmetic at II=1.
        for (int pair_idx = 0; pair_idx < 180; pair_idx++) begin
            tag = {17'($urandom), 32'($urandom)};
            length = int'($urandom_range(1, 12));
            for (int term_idx = 0; term_idx < length; term_idx++)
                drive_term(pair_idx % 3, 4, term_idx == 0, term_idx == length-1, tag);
            if (pair_idx % 9 == 0) bubble(2);
        end
        bubble(12);
        // Cancel at every occupied boundary, then restart without resetting data.
        for (int depth = 0; depth < 12; depth++) begin
            drive_term(1, 0, 1, 1, 49'(depth));
            bubble(depth);
            @(negedge clk_i);
            cancel_i = 1;
            term_valid_i = 1;
            @(negedge clk_i);
            cancel_i = 0;
            term_valid_i = 0;
            bubble(11);
            drive_term(0, 2, 1, 1, 49'(depth)+49'd32);
            bubble(11);
        end
        // Asynchronous reset also flushes occupied control without data reset.
        drive_term(0, 0, 1, 1, 49'h100);
        @(negedge clk_i);
        rst_n_i = 0;
        term_valid_i = 0;
        bubble(2);
        rst_n_i = 1;
        drive_term(2, 4, 1, 1, 49'h200);
        bubble(12);
        @(negedge clk_i);
        if (checked < 1000) $fatal(1, "FAIL insufficient MAC coverage: %0d", checked);
        $display("PASS MAC: %0d terms, 12 boundaries local/M1/M2/C1-C8/tail, seed=326ac851", checked);
        $finish;
    end
endmodule
