// File: tb_gpu_setup.sv
// Spec: gpu-spec 2.13.1-6 and section 7.
// Description: Exact model scoreboard with throughput, output hold, and command drain checks.
// Clock domain: clk_gpu.
module tb_gpu_setup;
    reg clk_i = 0;
    always #5 clk_i = !clk_i;
    reg rst_n_i = 0;
    reg finish_i = 0;
    reg stop_i = 0;
    wire unit_done_o;
    wire perf_triangle_o;
    reg input_valid = 0;
    wire input_ready;
    reg output_ready = 1;
    wire output_valid;
    reg [776:0] input_data;
    wire [2093:0] output_data;
    reg [776:0] inputs [0:263];
    reg [2093:0] expected [0:261];
    reg [2093:0] held;
    reg holding = 0;
    integer sent = 0;
    integer received = 0;
    integer events = 0;
    integer cycle = 0;
    integer last_input = -1;
    integer last_output = -1;
    reg [31:0] random_state = 32'h12345678;

    edrv32_gpu_setup u_dut (
        .clk_i(clk_i),
        .rst_n_i(rst_n_i),
        .screen_triangle_valid_i(input_valid),
        .screen_triangle_ready_o(input_ready),
        .screen_triangle_x_i(input_data[0 +: 51]),
        .screen_triangle_y_i(input_data[51 +: 51]),
        .screen_triangle_depth_i(input_data[102 +: 48]),
        .screen_triangle_q_i(input_data[150 +: 105]),
        .screen_triangle_uq_i(input_data[255 +: 153]),
        .screen_triangle_vq_i(input_data[408 +: 153]),
        .screen_triangle_color_i(input_data[561 +: 216]),
        .triangle_setup_valid_o(output_valid),
        .triangle_setup_ready_i(output_ready),
        .triangle_setup_bounds_o(output_data[0 +: 64]),
        .triangle_setup_edge_o(output_data[64 +: 480]),
        .triangle_setup_origin_o(output_data[544 +: 32]),
        .triangle_setup_start_o(output_data[576 +: 490]),
        .triangle_setup_gradient_o(output_data[1066 +: 784]),
        .triangle_setup_h_o(output_data[1850 +: 70]),
        .triangle_setup_normal_gradient_o(output_data[1920 +: 174]),
        .finish_i(finish_i),
        .stop_i(stop_i),
        .unit_done_o(unit_done_o),
        .perf_triangle_o(perf_triangle_o)
    );

    initial begin
        $readmemh("build/gpu_setup/input.hex", inputs);
        $readmemh("build/gpu_setup/expected.hex", expected);
        repeat (4) @(negedge clk_i);
        rst_n_i = 1;
        while (!unit_done_o) begin
            input_data = sent < 264 ? inputs[sent] : 777'd0;
            input_valid = sent < 264;
            finish_i = sent == 264;
            output_ready = sent < 64 || random_state[2:0] == 0;
            random_state = {random_state[30:0], random_state[31] ^ random_state[21]
                ^ random_state[1] ^ random_state[0]};
            @(posedge clk_i);
            cycle = cycle + 1;
            if (input_valid && input_ready) begin
                if (sent > 0 && sent < 64 && cycle - last_input != 8)
                    $fatal(1, "FAIL input II %0d", cycle-last_input);
                last_input = cycle;
                sent = sent + 1;
            end
            if (holding && (!output_valid || output_data !== held))
                $fatal(1, "FAIL output changed while blocked");
            holding = output_valid && !output_ready;
            held = output_data;
            if (perf_triangle_o) events = events + 1;
            if (output_valid && output_ready) begin
                if (output_data !== expected[received]) begin
                    $display("FAIL index=%0d actual=%h expected=%h", received,
                        output_data, expected[received]);
                    $fatal(1, "FAIL setup coefficient mismatch");
                end
                if (received > 0 && sent < 64 && cycle - last_output != 8)
                    $fatal(1, "FAIL output II %0d", cycle-last_output);
                last_output = cycle;
                received = received + 1;
            end
            if (cycle > 10000) $fatal(1, "FAIL timeout");
            @(negedge clk_i);
        end
        if (sent != 264 || received != 262 || events != 262)
            $fatal(1, "FAIL totals sent=%0d received=%0d events=%0d", sent,received,events);
        // Fill and stop with work in flight, then reuse the same unit without reset.
        finish_i = 0;
        output_ready = 0;
        input_valid = 1;
        input_data = inputs[0];
        repeat (24) @(negedge clk_i);
        stop_i = 1;
        finish_i = 1;
        input_valid = 0;
        repeat (2) @(negedge clk_i);
        if (!unit_done_o || output_valid) $fatal(1,"FAIL stop did not drain setup");
        stop_i = 0;
        finish_i = 0;
        output_ready = 1;
        @(negedge clk_i);
        input_valid = 1;
        do @(posedge clk_i); while (!input_ready);
        @(negedge clk_i);
        input_valid = 0;
        finish_i = 1;
        received = 0;
        cycle = 0;
        while (!unit_done_o) begin
            @(posedge clk_i);
            if (output_valid) begin
                if (received != 0 || output_data !== expected[0])
                    $fatal(1,"FAIL setup restart after stop");
                received = received + 1;
            end
            cycle = cycle + 1;
            if (cycle > 200) $fatal(1,"FAIL setup restart timeout");
            @(negedge clk_i);
        end
        if (received != 1) $fatal(1,"FAIL missing setup restart output");
        $display("PASS gpu_setup 264 inputs, 262 nondegenerate outputs; triangle II=8");
        $finish;
    end
endmodule
