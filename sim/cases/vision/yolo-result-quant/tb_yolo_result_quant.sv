`timescale 1ns/1ps

module tb_yolo_result_quant;
    reg clk_i = 1'b0;
    always #5 clk_i = !clk_i;

    reg rst_n_i = 1'b0;
    reg in_valid_i = 1'b0;
    wire in_ready_o;
    reg in_last_i = 1'b0;
    reg [11:0] in_pair_i = 12'd0;
    reg [2047:0] in_accum_i = 2048'd0;
    wire out_valid_o;
    reg out_ready_i = 1'b1;
    wire out_last_o;
    wire [11:0] out_pair_o;
    wire [511:0] out_data_o;
    reg cfg_valid_i = 1'b0;
    wire cfg_ready_o;
    reg [4:0] cfg_channel_i = 5'd0;
    reg [31:0] cfg_bias_i = 32'd0;
    reg [15:0] cfg_multiplier_i = 16'd0;
    reg [5:0] cfg_shift_i = 6'd0;
    reg [7:0] cfg_zero_point_i = 8'd0;

    reg [511:0] expected_r [0:23];
    reg [511:0] held_data_r;
    reg [11:0] held_pair_r;
    reg held_last_r;
    reg held_valid_r = 1'b0;
    reg send_started_r = 1'b0;
    integer receive_count_r = 0;
    integer run_cycle_r = 0;
    integer last_receive_cycle_r = 0;
    integer input_stall_cycles_r = 0;
    integer output_stall_cycles_r = 0;
    integer seq_index;
    integer pixel;
    integer channel;
    integer value;
    integer scaled;
    integer cfg_channel;

    edrv32_yolo_result_quant dut (
        .clk_i(clk_i), .rst_n_i(rst_n_i),
        .in_valid_i(in_valid_i), .in_ready_o(in_ready_o),
        .in_last_i(in_last_i), .in_pair_i(in_pair_i),
        .in_accum_i(in_accum_i),
        .out_valid_o(out_valid_o), .out_ready_i(out_ready_i),
        .out_last_o(out_last_o), .out_pair_o(out_pair_o),
        .out_data_o(out_data_o),
        .cfg_valid_i(cfg_valid_i), .cfg_ready_o(cfg_ready_o),
        .cfg_channel_i(cfg_channel_i), .cfg_bias_i(cfg_bias_i),
        .cfg_multiplier_i(cfg_multiplier_i), .cfg_shift_i(cfg_shift_i),
        .cfg_zero_point_i(cfg_zero_point_i),
        .lut_enable_i(1'b0), .lut_cfg_valid_i(1'b0),
        .lut_cfg_ready_o(), .lut_cfg_addr_i(8'd0),
        .lut_cfg_data_i(8'd0)
    );

    function integer source_value;
        input integer seq;
        input integer pix;
        input integer chan;
        begin
            if (seq == 0 && pix == 0 && chan == 0)
                source_value = 32'h7fff_ffff;
            else if (seq == 0 && pix == 1 && chan == 31)
                source_value = -32'sh8000_0000;
            else
                source_value = (seq*109 + pix*23 + chan*17) % 1024 - 512;
        end
    endfunction

    function integer quant_value;
        input integer accum;
        input integer chan;
        reg signed [63:0] product;
        reg signed [63:0] rounded;
        begin
            product = (64'sd0 + accum + (chan % 7 - 3)) * (chan % 5 + 1);
            rounded = (product + (64'sd1 << (chan % 4))) >>>
                      (chan % 4 + 1);
            rounded = rounded - 64'sd3;
            if (rounded > 127)
                quant_value = 127;
            else if (rounded < -128)
                quant_value = -128;
            else
                quant_value = rounded;
        end
    endfunction

    always @(negedge clk_i) begin
        if (send_started_r) begin
            run_cycle_r = run_cycle_r + 1;
            out_ready_i = run_cycle_r < 80 ||
                          (run_cycle_r >= 130 && run_cycle_r % 13 < 5);
        end
    end

    always @(posedge clk_i) begin
        if (rst_n_i) begin
            if (in_valid_i && !in_ready_o)
                input_stall_cycles_r <= input_stall_cycles_r + 1;
            if (out_valid_o && !out_ready_i)
                output_stall_cycles_r <= output_stall_cycles_r + 1;
            if (held_valid_r && (!out_valid_o ||
                out_data_o !== held_data_r ||
                out_pair_o !== held_pair_r ||
                out_last_o !== held_last_r))
                $fatal(1, "Quant output changed under backpressure");
            held_valid_r <= out_valid_o && !out_ready_i;
            if (out_valid_o && !out_ready_i) begin
                held_data_r <= out_data_o;
                held_pair_r <= out_pair_o;
                held_last_r <= out_last_o;
            end
            if (out_valid_o && out_ready_i) begin
                if (receive_count_r >= 24 ||
                    out_data_o !== expected_r[receive_count_r] ||
                    out_pair_o !== receive_count_r[11:0] ||
                    out_last_o !== (receive_count_r == 23))
                    $fatal(1, "Quant mismatch at pair %0d", receive_count_r);
                if (receive_count_r >= 2 && receive_count_r <= 7 &&
                    run_cycle_r - last_receive_cycle_r != 4)
                    $fatal(1, "Quant throughput below one pair/4 clocks");
                last_receive_cycle_r <= run_cycle_r;
                receive_count_r <= receive_count_r + 1;
            end
        end
    end

    initial begin
        for (seq_index = 0; seq_index < 24; seq_index = seq_index + 1)
            for (pixel = 0; pixel < 2; pixel = pixel + 1)
                for (channel = 0; channel < 32; channel = channel + 1) begin
                    value = quant_value(source_value(seq_index, pixel, channel),
                                        channel);
                    expected_r[seq_index][(pixel*32+channel)*8 +: 8] =
                        value[7:0];
                end

        repeat (5) @(negedge clk_i);
        rst_n_i = 1'b1;
        for (cfg_channel = 0; cfg_channel < 32; cfg_channel = cfg_channel + 1) begin
            @(negedge clk_i);
            if (!cfg_ready_o)
                $fatal(1, "Quant configuration not ready");
            cfg_valid_i = 1'b1;
            cfg_channel_i = cfg_channel[4:0];
            cfg_bias_i = cfg_channel % 7 - 3;
            cfg_multiplier_i = cfg_channel % 5 + 1;
            cfg_shift_i = cfg_channel % 4 + 1;
            cfg_zero_point_i = -8'sd3;
        end
        @(negedge clk_i);
        cfg_valid_i = 1'b0;
        send_started_r = 1'b1;
        for (seq_index = 0; seq_index < 24; seq_index = seq_index + 1) begin
            in_valid_i = 1'b1;
            in_pair_i = seq_index[11:0];
            in_last_i = seq_index == 23;
            for (pixel = 0; pixel < 2; pixel = pixel + 1)
                for (channel = 0; channel < 32; channel = channel + 1) begin
                    value = source_value(seq_index, pixel, channel);
                    in_accum_i[(pixel*32+channel)*32 +: 32] = value[31:0];
                end
            do @(posedge clk_i); while (!in_ready_o);
            @(negedge clk_i);
        end
        in_valid_i = 1'b0;
        wait (receive_count_r == 24);
        repeat (3) @(negedge clk_i);
        if (out_valid_o)
            $fatal(1, "Unexpected extra quant output");
        if (input_stall_cycles_r == 0 || output_stall_cycles_r == 0)
            $fatal(1, "Directed quant backpressure did not occur");
        $display("PASS YOLO result quant: arithmetic, buffering, stalls, 4-clock throughput");
        $finish;
    end

    initial begin
        #100000;
        $fatal(1, "Quant test timeout");
    end
endmodule
