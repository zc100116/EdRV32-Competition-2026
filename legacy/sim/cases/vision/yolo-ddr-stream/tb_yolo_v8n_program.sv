`timescale 1ns/1ps

module tb_yolo_v8n_program;
    reg clk = 0;
    always #5 clk = ~clk;
    reg rst_n = 0;
    reg start = 0;
    reg inject_error = 0;
    wire start_ready, busy, done, error, cmd_valid;
    wire [6:0] step;
    wire [1:0] op;
    wire [4:0] layer_id;
    wire [31:0] input_base, aux_base, output_base;
    wire [31:0] input_plane_stride, output_plane_stride;
    wire [31:0] weight_base, weight_block_stride, cfg_base;
    wire [10:0] input_width;
    wire [15:0] input_height, output_height, beat_count;
    wire [9:0] output_width_pairs, cache_row_stride, tile_pairs;
    wire [8:0] cache_bank_stride;
    wire [5:0] cin_blocks;
    wire [4:0] output_blocks;
    wire kernel3, stride2, last_c16_only, lut_enable;
    wire cmd_ready, cmd_done, cmd_error;
    reg exec_busy = 0;
    reg [2:0] exec_delay = 0;
    integer cycles = 0;
    integer accepted = 0;
    integer expected_step = 0;
    integer k_count;

    assign cmd_ready = !exec_busy && cycles % 4 == 0;
    assign cmd_done = exec_busy && exec_delay == 3;
    assign cmd_error = inject_error && step == 17;

    edrv32_yolo_v8n_program dut (
        .clk_i(clk), .rst_n_i(rst_n),
        .start_i(start), .start_ready_o(start_ready),
        .busy_o(busy), .done_o(done), .error_o(error),
        .step_o(step), .cmd_valid_o(cmd_valid),
        .cmd_ready_i(cmd_ready), .cmd_done_i(cmd_done),
        .cmd_error_i(cmd_error), .abort_i(1'b0),
        .cmd_op_o(op), .cmd_input_base_o(input_base),
        .cmd_aux_base_o(aux_base), .cmd_output_base_o(output_base),
        .cmd_input_plane_stride_o(input_plane_stride),
        .cmd_output_plane_stride_o(output_plane_stride),
        .cmd_weight_base_o(weight_base),
        .cmd_weight_block_stride_o(weight_block_stride),
        .cmd_input_width_o(input_width),
        .cmd_input_height_o(input_height),
        .cmd_output_width_pairs_o(output_width_pairs),
        .cmd_output_height_o(output_height),
        .cmd_cin_blocks_o(cin_blocks),
        .cmd_output_blocks_o(output_blocks),
        .cmd_cache_bank_stride_o(cache_bank_stride),
        .cmd_cache_row_stride_o(cache_row_stride),
        .cmd_tile_pairs_o(tile_pairs),
        .cmd_kernel3_o(kernel3), .cmd_stride2_o(stride2),
        .cmd_last_c16_only_o(last_c16_only),
        .cmd_beat_count_o(beat_count),
        .cmd_residual_zero_point_o(),
        .cmd_lut_enable_o(lut_enable),
        .cfg_base_o(cfg_base), .layer_id_o(layer_id)
    );

    always @(posedge clk) begin
        if (rst_n) begin
            cycles <= cycles + 1;
            if (cmd_valid && cmd_ready) begin
                if (step !== expected_step[6:0])
                    $fatal(1, "command skipped or repeated: %0d / %0d",
                           step, expected_step);
                accepted <= accepted + 1;
                expected_step <= expected_step + 1;
                exec_busy <= 1;
                exec_delay <= 0;
                if (step == 0 && (op != 0 || layer_id != 0 ||
                                  input_width != 640 ||
                                  output_width_pairs != 160 ||
                                  !last_c16_only))
                    $fatal(1, "first stride-2 layer is incorrect");
                if (step == 55 && (op != 0 || layer_id != 21 ||
                                   input_width != 20 || cin_blocks != 24 ||
                                   output_blocks != 8))
                    $fatal(1, "final neck layer is incorrect");
                if (step == 73 && (op != 0 || layer_id != 22 ||
                                   input_width != 20 || cin_blocks != 5 ||
                                   output_blocks != 3 || lut_enable))
                    $fatal(1, "final Detect logits layer is incorrect");
                case (op)
                    0: begin
                        k_count = 2 * cin_blocks * (kernel3 ? 9 : 1);
                        if (weight_base < 32'h0010_0000 ||
                            weight_block_stride != k_count * 256 ||
                            cfg_base == 0 ||
                            k_count > 512 || tile_pairs * k_count > 1024 ||
                            input_width[1:0] != 0 ||
                            (kernel3 && cache_row_stride * 5 > 1024))
                            $fatal(1, "invalid CONV descriptor at %0d", step);
                    end
                    1: if (beat_count == 0 || aux_base == 0 ||
                           output_base != aux_base)
                        $fatal(1, "invalid residual descriptor at %0d", step);
                    2: if (input_width != 20 || input_height != 12 ||
                           cin_blocks != 8)
                        $fatal(1, "invalid SPPF pool descriptor");
                    3: if (!((input_width == 20 && input_height == 12) ||
                             (input_width == 40 && input_height == 24)) ||
                           output_plane_stride != input_plane_stride * 4)
                        $fatal(1, "invalid upsample descriptor");
                    default: $fatal(1, "invalid op");
                endcase
            end
            if (exec_busy) begin
                if (cmd_done)
                    exec_busy <= 0;
                else
                    exec_delay <= exec_delay + 1;
            end
        end
    end

    initial begin
        repeat (4) @(negedge clk);
        rst_n = 1;
        inject_error = 1;
        @(negedge clk); start = 1;
        @(negedge clk); start = 0;
        wait (done);
        #1;
        if (!error || accepted != 18 || !start_ready)
            $fatal(1, "error did not stop command program");
        expected_step = 0;
        accepted = 0;
        inject_error = 0;
        @(negedge clk); start = 1;
        @(negedge clk); start = 0;
        wait (done);
        #1;
        if (error || accepted != 74 || !start_ready)
            $fatal(1, "full command program did not finish");
        $display("tb_yolo_v8n_program PASS: 74 commands");
        $finish;
    end

    initial begin
        #200000;
        $fatal(1, "program timeout step=%0d accepted=%0d", step, accepted);
    end
endmodule
