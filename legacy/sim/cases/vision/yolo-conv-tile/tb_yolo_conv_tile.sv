`timescale 1ns/1ps

module tb_yolo_conv_tile;
    reg clk_i = 1'b0;
    always #5 clk_i = !clk_i;

    reg rst_n_i = 1'b0;
    reg weight_valid_i = 1'b0;
    wire weight_ready_o;
    reg [11:0] weight_addr_i = 12'b0;
    reg [255:0] weight_data_i = 256'b0;
    reg activation_valid_i = 1'b0;
    wire activation_ready_o;
    reg [10:0] activation_addr_i = 11'b0;
    reg [127:0] activation_data_i = 128'b0;
    reg start_i = 1'b0;
    wire start_ready_o;
    reg [10:0] activation_base_i = 11'b0;
    reg [9:0] k_count_i = 10'b0;
    reg [11:0] pair_count_i = 12'b0;
    wire busy_o;
    wire done_o;
    wire result_valid_o;
    reg result_ready_i = 1'b1;
    wire result_last_o;
    wire [2047:0] result_accum_o;
    integer cycle_r = 0;
    integer case_mode_r = 0;
    reg held_valid_r = 1'b0;
    reg [2047:0] held_accum_r;
    reg held_last_r;

    edrv32_yolo_conv_tile dut (
        .clk_i(clk_i), .rst_n_i(rst_n_i),
        .weight_valid_i(weight_valid_i), .weight_ready_o(weight_ready_o),
        .weight_addr_i(weight_addr_i), .weight_data_i(weight_data_i),
        .activation_valid_i(activation_valid_i),
        .activation_ready_o(activation_ready_o),
        .activation_addr_i(activation_addr_i),
        .activation_data_i(activation_data_i),
        .start_i(start_i), .start_ready_o(start_ready_o),
        .activation_base_i(activation_base_i),
        .k_count_i(k_count_i), .pair_count_i(pair_count_i),
        .busy_o(busy_o), .done_o(done_o),
        .result_valid_o(result_valid_o), .result_ready_i(result_ready_i),
        .result_last_o(result_last_o), .result_accum_o(result_accum_o)
    );

    function integer feature_value;
        input integer source_pixel;
        input integer source_channel;
        begin
            feature_value = ((source_pixel * 17 + source_channel * 31 + 11)
                             % 256) - 128;
        end
    endfunction

    function integer weight_value;
        input integer mode;
        input integer output_channel;
        input integer term;
        begin
            weight_value = ((mode * 37 + output_channel * 13 + term * 7)
                            % 255) - 127;
        end
    endfunction

    function integer activation_value;
        input integer mode;
        input integer output_pixel;
        input integer term;
        integer source_x;
        integer source_y;
        integer kernel_x;
        integer kernel_y;
        integer channels;
        begin
            if (mode == 0) begin
                activation_value = feature_value(output_pixel, term);
            end else begin
                channels = mode == 2 ? 16 : 8;
                source_x = output_pixel % 4;
                source_y = output_pixel / 4;
                kernel_y = term / (3*channels);
                kernel_x = (term % (3*channels)) / channels;
                source_x = source_x + kernel_x - 1;
                source_y = source_y + kernel_y - 1;
                if (source_x < 0 || source_x >= 4 ||
                    source_y < 0 || source_y >= 4)
                    activation_value = 0;
                else
                    activation_value = feature_value(
                        source_y * 4 + source_x, term % channels);
            end
        end
    endfunction

    function integer reference_value;
        input integer mode;
        input integer output_pixel;
        input integer output_channel;
        input integer terms;
        integer t;
        begin
            reference_value = 0;
            for (t = 0; t < terms; t = t + 1)
                reference_value = reference_value +
                    activation_value(mode, output_pixel, t) *
                    weight_value(mode, output_channel, t);
        end
    endfunction

    always @(negedge clk_i) begin
        if (rst_n_i) begin
            cycle_r = cycle_r + 1;
            result_ready_i = (cycle_r % 13 < 8);
        end
    end

    always @(posedge clk_i) begin
        if (rst_n_i) begin
            if (dut.mac_group_ready_w !== {32{dut.mac_in_ready_w}})
                $fatal(1, "MAC output-channel ready groups diverged");
            if (held_valid_r && (!result_valid_o ||
                result_accum_o !== held_accum_r ||
                result_last_o !== held_last_r))
                $fatal(1, "Result changed during backpressure");
            held_valid_r <= result_valid_o && !result_ready_i;
            if (result_valid_o && !result_ready_i) begin
                held_accum_r <= result_accum_o;
                held_last_r <= result_last_o;
            end
        end
    end

    task load_weights;
        input integer mode;
        input integer rows;
        integer r;
        integer b;
        integer j;
        integer oc;
        integer term;
        integer value;
        begin
            for (r = 0; r < rows; r = r + 1)
                for (b = 0; b < 8; b = b + 1) begin
                    @(negedge clk_i);
                    if (!weight_ready_o)
                        $fatal(1, "Weight store not ready");
                    weight_addr_i = r * 8 + b;
                    for (j = 0; j < 32; j = j + 1) begin
                        oc = b * 4 + j / 8;
                        term = r * 8 + j % 8;
                        value = weight_value(mode, oc, term);
                        weight_data_i[j*8 +: 8] = value[7:0];
                    end
                    weight_valid_i = 1'b1;
                end
            @(negedge clk_i);
            weight_valid_i = 1'b0;
        end
    endtask

    task load_activations;
        input integer mode;
        input integer pairs;
        input integer rows;
        input integer base;
        integer q;
        integer r;
        integer p;
        integer k;
        integer value;
        begin
            for (q = 0; q < pairs; q = q + 1)
                for (r = 0; r < rows; r = r + 1) begin
                    @(negedge clk_i);
                    if (!activation_ready_o)
                        $fatal(1, "Activation store not ready");
                    activation_addr_i = base + q * rows + r;
                    for (p = 0; p < 2; p = p + 1)
                        for (k = 0; k < 8; k = k + 1) begin
                            value = activation_value(mode, q*2+p, r*8+k);
                            activation_data_i[(p*8+k)*8 +: 8] = value[7:0];
                        end
                    activation_valid_i = 1'b1;
                end
            @(negedge clk_i);
            activation_valid_i = 1'b0;
        end
    endtask

    task run_case;
        input integer mode;
        input integer pairs;
        input integer rows;
        input integer base;
        integer out_pair;
        integer p;
        integer oc;
        integer expected_word;
        integer observed_word;
        integer timeout;
        begin
            case_mode_r = mode;
            load_weights(mode, rows);
            load_activations(mode, pairs, rows, base);
            @(negedge clk_i);
            activation_base_i = base;
            k_count_i = rows;
            pair_count_i = pairs;
            #1;
            if (!start_ready_o)
                $fatal(1, "Tile did not accept start");
            start_i = 1'b1;
            @(negedge clk_i);
            start_i = 1'b0;
            if (base + pairs*rows < 2048) begin
                // The RAM write port remains available for a future tile.
                activation_addr_i = 11'd2047;
                activation_data_i = 128'h1234_5678_9abc_def0;
                activation_valid_i = 1'b1;
                #1;
                if (!activation_ready_o)
                    $fatal(1, "Concurrent activation preload blocked");
                @(negedge clk_i);
                activation_valid_i = 1'b0;
            end
            out_pair = 0;
            timeout = 0;
            while (out_pair < pairs && timeout < 10000) begin
                @(posedge clk_i);
                timeout = timeout + 1;
                if (result_valid_o && result_ready_i) begin
                    if (result_last_o !== (out_pair == pairs-1))
                        $fatal(1, "Wrong result_last pair=%0d", out_pair);
                    for (p = 0; p < 2; p = p + 1)
                        for (oc = 0; oc < 32; oc = oc + 1) begin
                            expected_word = reference_value(
                                mode, out_pair*2+p, oc, rows*8);
                            observed_word = $signed(
                                result_accum_o[(p*32+oc)*32 +: 32]);
                            if (observed_word !== expected_word)
                                $fatal(1, "mode=%0d pair=%0d pixel=%0d oc=%0d expected=%0d actual=%0d",
                                       mode, out_pair, p, oc,
                                       expected_word, observed_word);
                        end
                    out_pair = out_pair + 1;
                end
            end
            if (out_pair != pairs)
                $fatal(1, "Tile timeout mode=%0d results=%0d/%0d",
                       mode, out_pair, pairs);
            @(negedge clk_i);
            if (!done_o || busy_o)
                $fatal(1, "Missing done mode=%0d", mode);
            $display("PASS mode=%0d pairs=%0d K_rows=%0d cycles=%0d",
                     mode, pairs, rows, timeout);
        end
    endtask

    initial begin
        repeat (5) @(negedge clk_i);
        rst_n_i = 1'b1;
        run_case(0, 16, 1, 1536);// K=1: first/last on the same beat.
        run_case(0, 8, 4, 0);   // 1x1, Cin=32, 16 output pixels.
        run_case(1, 8, 9, 1024);// 3x3, Cin=8, pad=1, 4x4 output.
        run_case(2, 8, 18, 0);  // 3x3, Cin=16, pad=1, 4x4 output.
        if (!$test$plusargs("SKIP_MAX"))
            run_case(0, 4, 512, 0); // Full RAM address bounds.
        $display("PASS YOLO convolution tile: 1x1 and 3x3 with result stalls");
        $finish;
    end

    initial begin
        #300000;
        $fatal(1, "Global timeout");
    end
endmodule
