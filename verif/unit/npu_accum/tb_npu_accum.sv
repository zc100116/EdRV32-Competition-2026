// File: tb_npu_accum.sv
// Spec: npu-testplan OP-01/02/07/08; datapath design 4.2/4.3/5.2 D1-C.
// Description: Model complete pair sums from independent signed physical channel terms.
// Check first replacement, D2, final-only output and combinational early preparation.
// Clock: clk_npu, 10 ns test clock.
module tb_npu_accum;
    bit clk_i = 0;
    bit rst_n_i = 0;
    bit cancel_i = 0;
    bit sum_valid_i = 0;
    bit sum_first_i = 0;
    bit sum_last_i = 0;
    bit [48:0] sum_tag_i = 0;
    bit [1215:0] sum_data_i = 0;
    wire quant_prepare_valid_o;
    wire [48:0] quant_prepare_tag_o;
    wire accum_valid_o;
    wire [48:0] accum_tag_o;
    wire [2047:0] accum_data_o;
    wire idle_o;

    bit [1:0] expected_valid = 0;
    bit [48:0] expected_tag [0:1];
    bit [2047:0] expected_data [0:1];
    int working [0:63];
    bit expected_r4_valid;
    bit sampled_prepare;
    bit previous_prepare = 0;
    bit [48:0] sampled_prepare_tag;
    bit [48:0] previous_prepare_tag;
    int checked = 0;
    int prepared = 0;
    int cycle = 0;
    int seed = 32'h1accc602;

    always #5 clk_i = ~clk_i;

    edrv32_npu_accum dut (
        .clk_i(clk_i),
        .rst_n_i(rst_n_i),
        .cancel_i(cancel_i),

        .sum_valid_i(sum_valid_i),
        .sum_first_i(sum_first_i),
        .sum_last_i(sum_last_i),
        .sum_tag_i(sum_tag_i),
        .sum_data_i(sum_data_i),

        .quant_prepare_valid_o(quant_prepare_valid_o),
        .quant_prepare_tag_o(quant_prepare_tag_o),
        .accum_valid_o(accum_valid_o),
        .accum_tag_o(accum_tag_o),
        .accum_data_o(accum_data_o),

        .idle_o(idle_o)
    );

    always @(posedge clk_i) begin : monitor
        int value;
        cycle++;
        // Sample like the parameter RAM: prepare must already be present before R4.
        sampled_prepare = quant_prepare_valid_o;
        sampled_prepare_tag = quant_prepare_tag_o;
        if (rst_n_i && sampled_prepare !== (sum_valid_i && sum_last_i && !cancel_i))
            $fatal(1, "FAIL prepare before R4 cycle=%0d expected=%b actual=%b t=%0t",
                cycle, (sum_valid_i && sum_last_i && !cancel_i), sampled_prepare, $time);
        if (sampled_prepare && sampled_prepare_tag !== sum_tag_i)
            $fatal(1, "FAIL prepare tag cycle=%0d exp=%h actual=%h t=%0t",
                cycle, sum_tag_i, sampled_prepare_tag, $time);
        if (rst_n_i && sampled_prepare) prepared++;

        expected_data[1] = expected_data[0];
        expected_tag[1] = expected_tag[0];
        if (!rst_n_i || cancel_i) begin
            expected_valid = 0;
            expected_r4_valid = 0;
            previous_prepare = 0;
        end else begin
            expected_valid = {expected_valid[0], sum_valid_i && sum_last_i};
            expected_r4_valid = sum_valid_i;
            if (sum_valid_i) begin
                for (int pixel = 0; pixel < 2; pixel++) begin
                    for (int channel = 0; channel < 32; channel++) begin
                        value = int'($signed(sum_data_i[19*(32*pixel+channel) +: 19]));
                        if (sum_tag_i[48]) begin
                            if (channel < 16)
                                value += int'($signed(
                                    sum_data_i[19*(32*pixel+channel+16) +: 19]));
                            else value = 0;
                        end
                        if (sum_first_i) working[32*pixel+channel] = value;
                        else working[32*pixel+channel] += value;
                        expected_data[0][32*(32*pixel+channel) +: 32] =
                            32'(working[32*pixel+channel]);
                    end
                end
                expected_tag[0] = sum_tag_i;
            end
        end
        #1;
        if (accum_valid_o !== expected_valid[1] ||
            idle_o !== !(expected_r4_valid || expected_valid[1]))
            $fatal(1, "FAIL ACC valid/idle cycle=%0d exp=%b/%b actual=%b/%b t=%0t",
                cycle, expected_valid[1], !(expected_r4_valid || expected_valid[1]),
                accum_valid_o, idle_o, $time);
        if (rst_n_i && !cancel_i && accum_valid_o !== previous_prepare)
            $fatal(1, "FAIL prepare-to-ACC latency cycle=%0d exp=%b actual=%b t=%0t",
                cycle, previous_prepare, accum_valid_o, $time);
        if (accum_valid_o) begin
            if (accum_tag_o !== expected_tag[1] || accum_tag_o !== previous_prepare_tag)
                $fatal(1, "FAIL ACC tag cycle=%0d exp=%h actual=%h prepared=%h t=%0t",
                    cycle, expected_tag[1], accum_tag_o, previous_prepare_tag, $time);
            for (int item = 0; item < 64; item++) begin
                if (accum_data_o[32*item +: 32] !== expected_data[1][32*item +: 32])
                    $fatal(1, "FAIL ACC item=%0d exp=%0d actual=%0d cycle=%0d t=%0t",
                        item, $signed(expected_data[1][32*item +: 32]),
                        $signed(accum_data_o[32*item +: 32]), cycle, $time);
            end
            checked++;
        end
        previous_prepare = rst_n_i && !cancel_i && sampled_prepare;
        previous_prepare_tag = sampled_prepare_tag;
    end

    task automatic drive_sum(input bit d2, input bit half, input int pattern,
        input bit first, input bit last, input bit [48:0] tag);
        int value;
        @(negedge clk_i);
        sum_valid_i = 1;
        sum_first_i = first;
        sum_last_i = last;
        sum_tag_i = tag;
        sum_tag_i[48] = d2;
        sum_tag_i[26] = half;
        for (int pixel = 0; pixel < 2; pixel++) begin
            for (int channel = 0; channel < 32; channel++) begin
                case (pattern)
                    0: value = 131072;   // Eight (-128)*(-128) products.
                    1: value = -130048;  // Eight (-128)*127 products.
                    2: value = (channel < 16) ? -130048 : 131072;
                    3: value = (pixel == 0) ? 131072 : -130048;
                    default: value = int'($urandom_range(0, 261120)) - 130048;
                endcase
                if (half && !d2 && channel >= 16) value = 0;
                sum_data_i[19*(32*pixel+channel) +: 19] = 19'(value);
            end
        end
        // Detect a registered prepare immediately, before any posedge is available.
        #1;
        if (quant_prepare_valid_o !== last || quant_prepare_tag_o !== sum_tag_i)
            $fatal(1, "FAIL combinational prepare exp=%b/%h actual=%b/%h t=%0t",
                last, sum_tag_i, quant_prepare_valid_o, quant_prepare_tag_o, $time);
    endtask

    task automatic bubble(input int count);
        repeat (count) begin
            @(negedge clk_i);
            sum_valid_i = 0;
            // Invalid first/last and payload must neither prepare nor accumulate.
            sum_first_i = 1;
            sum_last_i = 1;
            sum_data_i = ~sum_data_i;
        end
    endtask

    task automatic drive_pair(input int length, input bit d2, input bit half,
        input int pattern, input bit [48:0] tag);
        for (int term_idx = 0; term_idx < length; term_idx++)
            drive_sum(d2, half, pattern, term_idx == 0, term_idx == length-1, tag);
    endtask

    initial begin : stimulus
        bit [48:0] tag;
        int mode;
        void'($urandom(seed));
        repeat (2) @(negedge clk_i);
        rst_n_i = 1;
        for (int pattern = 0; pattern < 4; pattern++) begin
            drive_pair(144, 0, 0, pattern, 49'(pattern));
            drive_pair(72, 1, 1, pattern, 49'(pattern)+49'd16);
            drive_pair(9, 0, 1, pattern, 49'(pattern)+49'd32);
            bubble(3);
        end
        // Long sums exercise sign extension beyond the 20-bit R4 value.
        drive_pair(1152, 0, 0, 0, 49'h40567);
        drive_pair(576, 1, 1, 1, 49'h80567);
        // Consecutive last/first and immediate mode/block/row/tag changes.
        for (int pair_idx = 0; pair_idx < 240; pair_idx++) begin
            tag = {17'($urandom), 32'($urandom)};
            mode = pair_idx % 3;
            drive_pair(pair_idx < 30 ? 1 : int'($urandom_range(1, 16)),
                mode == 1, mode != 0, 4, tag);
            if (pair_idx % 11 == 0) bubble(2);
        end
        bubble(4);
        // Cancel a partial accumulation and a final item resident in R4.
        for (int depth = 0; depth < 2; depth++) begin
            drive_sum(1, 1, 0, 1, depth == 1, 49'h321);
            @(negedge clk_i);
            cancel_i = 1;
            sum_valid_i = 1;
            sum_last_i = 1;
            #1;
            if (quant_prepare_valid_o) $fatal(1, "FAIL cancel did not mask prepare t=%0t", $time);
            @(negedge clk_i);
            cancel_i = 0;
            sum_valid_i = 0;
            bubble(3);
            drive_pair(1, 0, 0, 1, 49'h123);
            bubble(3);
        end
        drive_sum(0, 0, 0, 1, 1, 49'h456);
        @(negedge clk_i);
        rst_n_i = 0;
        sum_valid_i = 0;
        bubble(2);
        rst_n_i = 1;
        drive_pair(1, 1, 1, 3, 49'h789);
        bubble(4);
        @(negedge clk_i);
        if (checked != 257) $fatal(1, "FAIL ACC coverage expected=257 actual=%0d", checked);
        $display("PASS ACC: %0d vectors, %0d prepares, R4/ACC=2 boundaries, seed=1accc602",
            checked, prepared);
        $display("PASS prepare sampled at R4; final vector follows one register boundary later");
        $finish;
    end
endmodule
