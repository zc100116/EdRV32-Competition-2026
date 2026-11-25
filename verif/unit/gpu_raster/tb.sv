// File: tb.sv
// Spec: gpu-spec 2.5, 2.8, 2.13; microarch 4.2, 4.4.
// Description: Streaming scoreboard against Python model vectors, with stalls and drain.
// Clock domain: clk_gpu.
module tb;
    reg clk_i = 0;
    always #5 clk_i = !clk_i;
    reg rst_n_i = 0;
    reg finish_i = 0;
    reg stop_i = 0;
    wire unit_done_o;
    reg source_valid_r = 0;
    wire source_ready_w;
    reg sink_ready_r = 0;
    wire sink_valid_w;
    reg [1751:0] stimulus_r [0:32767];
    reg [1854:0] expected_r [0:262143];
    reg [1751:0] source_r = 0;
    wire [1854:0] actual_w;
    integer input_total_r;
    integer output_total_r;
    integer sent_r = 0;
    integer received_r = 0;
    integer cycle_r = 0;
    integer first_r = -1;
    integer last_r = -1;
    integer object_r = 0;
    integer stall_r = 0;
    integer wide_r = 0;
    integer perf_r = 0;
    integer streak_r = 0;
    integer max_streak_r = 0;
    reg measure_r = 0;
    reg [4095:0] input_path_r;
    reg [4095:0] expected_path_r;
    wire [63:0] triangle_setup_bounds_w;
    wire [479:0] triangle_setup_edge_w;
    wire [31:0] triangle_setup_origin_w;
    wire [433:0] triangle_setup_start_w;
    wire [671:0] triangle_setup_gradient_w;
    wire [69:0] triangle_setup_h_w;
    wire [15:0] fragment_x_w;
    wire [15:0] fragment_y_w;
    wire [3:0] fragment_mask_w;
    wire [0:0] fragment_quad_w;
    wire [1735:0] fragment_plane_w;
    wire [69:0] fragment_h_w;
    wire [3:0] fragment_palette_w;
    wire [7:0] fragment_alpha_w;
    assign {triangle_setup_h_w, triangle_setup_gradient_w, triangle_setup_start_w, triangle_setup_origin_w, triangle_setup_edge_w, triangle_setup_bounds_w} = source_r;
    assign actual_w = {fragment_alpha_w, fragment_palette_w, fragment_h_w, fragment_plane_w, fragment_quad_w, fragment_mask_w, fragment_y_w, fragment_x_w};
    reg state_valid_r = 0;
    reg [255:0] target_r = 0;
    wire state_ready_w;
    wire draw_ready_w;
    edrv32_gpu_raster u_dut (
        .clk_i(clk_i),
        .rst_n_i(rst_n_i),
        .finish_i(finish_i),
        .stop_i(stop_i),
        .unit_done_o(unit_done_o),
        .render_state_valid_i(state_valid_r),
        .render_state_ready_o(state_ready_w),
        .render_state_tex_i(256'd0),
        .render_state_pixel_i(256'd0),
        .render_state_target_i(target_r),
        .render_state_wide_i(wide_r != 0),
        .draw_valid_i(1'b0),
        .draw_ready_o(draw_ready_w),
        .draw_command_i(256'd0),
        .triangle_setup_valid_i(source_valid_r),
        .triangle_setup_ready_o(source_ready_w),
        .triangle_setup_bounds_i(triangle_setup_bounds_w),
        .triangle_setup_edge_i(triangle_setup_edge_w),
        .triangle_setup_origin_i(triangle_setup_origin_w),
        .triangle_setup_start_i(triangle_setup_start_w),
        .triangle_setup_gradient_i(triangle_setup_gradient_w),
        .triangle_setup_h_i(triangle_setup_h_w),
        .fragment_valid_o(sink_valid_w),
        .fragment_ready_i(sink_ready_r),
        .fragment_x_o(fragment_x_w),
        .fragment_y_o(fragment_y_w),
        .fragment_mask_o(fragment_mask_w),
        .fragment_quad_o(fragment_quad_w),
        .fragment_plane_o(fragment_plane_w),
        .fragment_h_o(fragment_h_w),
        .fragment_palette_o(fragment_palette_w),
        .fragment_alpha_o(fragment_alpha_w)
    );
    initial begin
        if (!$value$plusargs("INPUT=%s", input_path_r) ||
            !$value$plusargs("EXPECTED=%s", expected_path_r) ||
            !$value$plusargs("INPUT_COUNT=%d", input_total_r) ||
            !$value$plusargs("OUTPUT_COUNT=%d", output_total_r)) $fatal(1, "missing vectors");
        if ($value$plusargs("OBJECT=%d", object_r)) begin end
        if ($value$plusargs("STALL=%d", stall_r)) begin end
        if ($value$plusargs("WIDE=%d", wide_r)) begin end
        if ($value$plusargs("PERF=%d", perf_r)) begin end
        $readmemh(input_path_r, stimulus_r, 0, input_total_r-1);
        if (output_total_r > 0) $readmemh(expected_path_r, expected_r, 0, output_total_r-1);
        repeat (3) @(negedge clk_i);
        rst_n_i = 1;
        // Target origin (-8,-4); scissor cuts both near and far target boundaries.
        target_r[32 +: 16] = -16'sd8;
        target_r[48 +: 16] = -16'sd4;
        target_r[64 +: 16] = -16'sd5;
        target_r[80 +: 16] = -16'sd2;
        target_r[96 +: 16] = wide_r != 0 ? 16'd1275 : 16'd636;
        target_r[112 +: 16] = wide_r != 0 ? 16'd88 : 16'd178;
        state_valid_r = 1;
        @(negedge clk_i);
        state_valid_r = 0;
        // Stop must discard queued work, then a fresh finish-low command starts cleanly.
        source_r = stimulus_r[0];
        source_valid_r = 1;
        repeat (8) @(negedge clk_i);
        source_valid_r = 0;
        stop_i = 1;
        finish_i = 1;
        repeat (4) @(negedge clk_i);
        if (!unit_done_o) $fatal(1, "stop did not drain");
        stop_i = 0;
        finish_i = 0;
        repeat (2) @(negedge clk_i);
        measure_r = 1;
        while (!unit_done_o) begin
            @(negedge clk_i);
            source_valid_r = sent_r < input_total_r;
            if (source_valid_r) source_r = stimulus_r[sent_r];
            sink_ready_r = stall_r == 0 || (cycle_r % 17 < 11 && cycle_r % 7 != 0);
            finish_i = sent_r == input_total_r;
            if (cycle_r > 2000000) $fatal(1, "timeout sent=%0d received=%0d", sent_r, received_r);
        end
        if (received_r != output_total_r) $fatal(1, "count expected=%0d actual=%0d",
            output_total_r, received_r);
        if (stall_r == 0 && max_streak_r < 20000)
            $fatal(1, "raster steady group throughput mismatch");
        if (perf_r != 0 && last_r-first_r+1 != output_total_r)
            $fatal(1, "quad group throughput mismatch");
        $display("PASS inputs=%0d groups=%0d first=%0d last=%0d cycles=%0d streak=%0d",
            sent_r, received_r, first_r, last_r, cycle_r, max_streak_r);
        $finish;
    end
    always @(posedge clk_i) begin
        if (rst_n_i) begin
            cycle_r <= cycle_r + 1;
            if (measure_r && source_valid_r && source_ready_w) sent_r <= sent_r + 1;
            if (!(sink_valid_w && sink_ready_r)) streak_r <= 0;
            if (sink_valid_w && sink_ready_r) begin
                streak_r <= streak_r + 1;
                if (streak_r + 1 > max_streak_r) max_streak_r <= streak_r + 1;
                if (received_r >= output_total_r || actual_w !== expected_r[received_r]) begin
                    $display("FAIL group=%0d expected=%h actual=%h", received_r,
                        expected_r[received_r], actual_w);
                    $fatal(1, "scoreboard mismatch at cycle %0d", cycle_r);
                end
                received_r <= received_r + 1;
                if (first_r == -1) first_r <= cycle_r;
                last_r <= cycle_r;
            end
        end
    end
endmodule
