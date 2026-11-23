// File: tb_gpu_texture.sv
// Spec: gpu-spec 2.6; R-4a unit verification.
// Description: Front-door texture/palette load and Python model comparison.
// Clock: testbench GPU clock.
`timescale 1ns/1ps
module tb_gpu_texture;
    logic  clk;
    logic  rst_n;
    logic  finish;
    logic  stop;
    logic  texture_done;
    logic  render_state_valid;
    logic  render_state_ready;
    logic [255:0] render_state_tex;
    logic [255:0] render_state_pixel;
    logic [255:0] render_state_target;
    logic  render_state_wide;
    logic  sample_valid;
    logic  sample_ready;
    logic [15:0] sample_x;
    logic [15:0] sample_y;
    logic [3:0] sample_mask;
    logic  sample_quad;
    logic [127:0] sample_u;
    logic [127:0] sample_v;
    logic [383:0] sample_span;
    logic [63:0] sample_depth;
    logic [95:0] sample_color;
    logic [3:0] sample_palette;
    logic [7:0] sample_alpha;
    logic  shaded_valid;
    logic  shaded_ready;
    logic [15:0] shaded_x;
    logic [15:0] shaded_y;
    logic [3:0] shaded_mask;
    logic [63:0] shaded_depth;
    logic [95:0] shaded_color;
    logic [31:0] shaded_alpha;
    logic [7:0] texture_read_en;
    logic [119:0] texture_read_addr;
    logic [127:0] texture_read_data;
    logic  full_read_en;
    logic [47:0] full_read_idx;
    logic [79:0] full_read_data;
    logic  current_read_en;
    logic [63:0] current_read_idx;
    logic [159:0] current_read_data;
    logic  perf_texture_stall;
    logic  texture_ram_done;
    logic  texture_load_valid;
    logic  texture_load_ready;
    logic [17:0] texture_load_addr;
    logic [255:0] texture_load_data;
    logic [31:0] texture_load_keep;
    logic  palette_done;
    logic  palette_load_valid;
    logic  palette_load_ready;
    logic [11:0] palette_load_idx;
    logic [19:0] palette_load_data;
    logic  palette_prepare_valid;
    logic  palette_prepare_ready;
    logic [3:0] palette_prepare_group;
    logic  palette_prepared_valid;
    logic  palette_prepared_ready;
    always #5 clk = ~clk;
    edrv32_gpu_texture u_texture (
        .clk_i(clk),
        .rst_n_i(rst_n),
        .finish_i(finish),
        .stop_i(stop),
        .unit_done_o(texture_done),
        .render_state_valid_i(render_state_valid),
        .render_state_ready_o(render_state_ready),
        .render_state_tex_i(render_state_tex),
        .render_state_pixel_i(render_state_pixel),
        .render_state_target_i(render_state_target),
        .render_state_wide_i(render_state_wide),
        .sample_valid_i(sample_valid),
        .sample_ready_o(sample_ready),
        .sample_x_i(sample_x),
        .sample_y_i(sample_y),
        .sample_mask_i(sample_mask),
        .sample_quad_i(sample_quad),
        .sample_u_i(sample_u),
        .sample_v_i(sample_v),
        .sample_span_i(sample_span),
        .sample_depth_i(sample_depth),
        .sample_color_i(sample_color),
        .sample_palette_i(sample_palette),
        .sample_alpha_i(sample_alpha),
        .shaded_valid_o(shaded_valid),
        .shaded_ready_i(shaded_ready),
        .shaded_x_o(shaded_x),
        .shaded_y_o(shaded_y),
        .shaded_mask_o(shaded_mask),
        .shaded_depth_o(shaded_depth),
        .shaded_color_o(shaded_color),
        .shaded_alpha_o(shaded_alpha),
        .texture_read_en_o(texture_read_en),
        .texture_read_addr_o(texture_read_addr),
        .texture_read_data_i(texture_read_data),
        .full_read_en_o(full_read_en),
        .full_read_idx_o(full_read_idx),
        .full_read_data_i(full_read_data),
        .current_read_en_o(current_read_en),
        .current_read_idx_o(current_read_idx),
        .current_read_data_i(current_read_data),
        .perf_texture_stall_o(perf_texture_stall)
    );
    edrv32_gpu_texture_ram u_texture_ram (
        .clk_i(clk),
        .rst_n_i(rst_n),
        .finish_i(finish),
        .stop_i(stop),
        .unit_done_o(texture_ram_done),
        .texture_load_valid_i(texture_load_valid),
        .texture_load_ready_o(texture_load_ready),
        .texture_load_addr_i(texture_load_addr),
        .texture_load_data_i(texture_load_data),
        .texture_load_keep_i(texture_load_keep),
        .read_en_i(texture_read_en),
        .read_addr_i(texture_read_addr),
        .read_data_o(texture_read_data)
    );
    edrv32_gpu_palette u_palette (
        .clk_i(clk),
        .rst_n_i(rst_n),
        .finish_i(finish),
        .stop_i(stop),
        .unit_done_o(palette_done),
        .palette_load_valid_i(palette_load_valid),
        .palette_load_ready_o(palette_load_ready),
        .palette_load_idx_i(palette_load_idx),
        .palette_load_data_i(palette_load_data),
        .palette_prepare_valid_i(palette_prepare_valid),
        .palette_prepare_ready_o(palette_prepare_ready),
        .palette_prepare_group_i(palette_prepare_group),
        .palette_prepared_valid_o(palette_prepared_valid),
        .palette_prepared_ready_i(palette_prepared_ready),
        .full_read_en_i(full_read_en),
        .full_read_idx_i(full_read_idx),
        .full_read_data_o(full_read_data),
        .current_read_en_i(current_read_en),
        .current_read_idx_i(current_read_idx),
        .current_read_data_o(current_read_data)
    );
    reg [255:0] ram [0:6143];
    reg [19:0] pal [0:4095];
    reg [271:0] cases [0:383];
    reg [959:0] inputs [0:13247];
    reg [227:0] expected [0:13247];
    integer cycle = 0;
    integer received = 0;
    integer first_cycle;
    integer last_cycle;
    integer case_received = 0;
    integer stalls = 0;
    integer begin_stalls;
    integer preload_max = 0;
    integer start_cycle;
    integer case_id;
    integer count;
    integer vector_idx = 0;
    integer k;
    reg backpressure = 1;
    reg [31:0] random_state = 32'h812346ab;
    reg [227:0] actual;
    reg [227:0] held;
    reg holding = 0;
    always @(negedge clk) begin
        random_state = (random_state << 1) ^ (random_state[31] ? 32'h04c11db7 : 0);
        shaded_ready = !backpressure || random_state[2:0] != 0;
    end
    always @(posedge clk) begin
        cycle <= cycle + 1;
        if (holding && {shaded_alpha, shaded_color, shaded_depth, shaded_mask,
                        shaded_y, shaded_x} !== held) $fatal(1, "FAIL output hold");
        holding = shaded_valid && !shaded_ready;
        held = {shaded_alpha, shaded_color, shaded_depth, shaded_mask, shaded_y, shaded_x};
        if (perf_texture_stall) stalls = stalls + 1;
        if (shaded_valid && shaded_ready) begin
            actual = {shaded_alpha, shaded_color, shaded_depth, shaded_mask, shaded_y, shaded_x};
            if (actual !== expected[received]) begin
                $display("FAIL case=%0d vector=%0d cycle=%0d expected=%h actual=%h",
                         case_id, received, cycle, expected[received], actual);
                $fatal(1);
            end
            if (case_received == 0) first_cycle = cycle;
            last_cycle = cycle;
            case_received = case_received + 1;
            received = received + 1;
        end
    end
    task drive_sample(input reg [959:0] value);
        begin
            {sample_alpha, sample_palette, sample_color, sample_depth, sample_span,
             sample_v, sample_u, sample_quad, sample_mask, sample_y, sample_x} = value[848:0];
            sample_valid = 1;
            @(posedge clk);
            while (!sample_ready) @(posedge clk);
            @(negedge clk);
        end
    endtask
    initial begin
        clk = 0;
        rst_n = 0;
        finish = 0;
        stop = 0;
        render_state_valid = 0;
        render_state_tex = 0;
        render_state_pixel = 0;
        render_state_target = 0;
        render_state_wide = 0;
        sample_valid = 0;
        sample_x = 0;
        sample_y = 0;
        sample_mask = 0;
        sample_quad = 0;
        sample_u = 0;
        sample_v = 0;
        sample_span = 0;
        sample_depth = 0;
        sample_color = 0;
        sample_palette = 0;
        sample_alpha = 0;
        shaded_ready = 0;
        texture_load_valid = 0;
        texture_load_addr = 0;
        texture_load_data = 0;
        texture_load_keep = 0;
        palette_load_valid = 0;
        palette_load_idx = 0;
        palette_load_data = 0;
        palette_prepare_valid = 0;
        palette_prepare_group = 0;
        palette_prepared_ready = 0;
        $readmemh("build/gpu_texture/vectors/ram.hex", ram);
        $readmemh("build/gpu_texture/vectors/palette.hex", pal);
        $readmemh("build/gpu_texture/vectors/cases.hex", cases);
        $readmemh("build/gpu_texture/vectors/samples.hex", inputs);
        $readmemh("build/gpu_texture/vectors/expected.hex", expected);
        repeat (4) @(negedge clk);
        rst_n = 1;
        for (k = 0; k < 6144; k = k + 1) begin
            texture_load_valid = 1;
            texture_load_addr = 18'(k*32);
            texture_load_data = ram[k];
            texture_load_keep = '1;
            @(posedge clk);
            while (!texture_load_ready) @(posedge clk);
            @(negedge clk);
        end
        texture_load_valid = 0;
        finish = 1;
        wait (texture_ram_done);
        @(negedge clk);
        finish = 0;
        for (k = 0; k < 4096; k = k + 1) begin
            palette_load_valid = 1;
            palette_load_idx = 12'(k);
            palette_load_data = pal[k];
            @(posedge clk);
            @(negedge clk);
        end
        palette_load_valid = 0;
        palette_prepared_ready = 0;
        for (case_id = 0; case_id < 384; case_id = case_id + 1) begin
            begin_stalls = stalls;
            count = {16'b0, cases[case_id][271:256]};
            case_received = 0;
            finish = 0;
            backpressure = case_id < 375;
            render_state_tex = cases[case_id][255:0];
            render_state_valid = 1;
            @(posedge clk);
            while (!render_state_ready) @(posedge clk);
            @(negedge clk);
            render_state_valid = 0;
            if (render_state_tex[73:72] != 2 && render_state_tex[83:82] != 0) begin
                palette_prepare_valid = 1;
                palette_prepare_group = render_state_tex[81:78];
                start_cycle = cycle;
                @(posedge clk);
                while (!palette_prepare_ready) @(posedge clk);
                @(negedge clk);
                palette_prepare_valid = 0;
                wait (palette_prepared_valid);
                @(negedge clk);
                if (cycle - start_cycle > 264) $fatal(1, "FAIL preload budget");
                if (cycle - start_cycle > preload_max) preload_max = cycle-start_cycle;
                // Response must remain asserted under command backpressure.
                repeat (3) @(negedge clk);
                if (!palette_prepared_valid) $fatal(1, "FAIL prepared hold");
                palette_prepared_ready = 1;
                @(negedge clk);
                palette_prepared_ready = 0;
            end
            for (k = 0; k < count; k = k + 1) begin
                drive_sample(inputs[vector_idx]);
                vector_idx = vector_idx + 1;
            end
            sample_valid = 0;
            finish = 1;
            wait (texture_done);
            @(negedge clk);
            if (case_received != count) $fatal(1, "FAIL early completion");
            if (case_id >= 372 && case_id < 375 && stalls-begin_stalls != 64) begin
                $fatal(1, "FAIL conflict/merge accounting %0d", stalls-begin_stalls);
            end
            if (case_id >= 375) begin
                $display("PERF format=%0d mode=%0d groups=%0d output_interval=%0d pixels/cycle=%f",
                         (case_id-375)/3, (case_id-375)%3, count, last_cycle-first_cycle,
                         4.0*(count-1)/(last_cycle-first_cycle));
                if (last_cycle-first_cycle != (count-1)*(1 << ((case_id-375)%3))) begin
                    $fatal(1, "FAIL throughput");
                end
            end
        end
        // Empty draws and aborting accepted, in-flight work use the same finish contract.
        finish = 0;
        @(negedge clk);
        if (texture_done) $fatal(1, "FAIL completion did not clear");
        for (k = 0; k < 16; k = k + 1) drive_sample(inputs[k]);
        sample_valid = 0;
        stop = 1;
        finish = 1;
        repeat (20) @(negedge clk);
        if (!texture_done || shaded_valid) $fatal(1, "FAIL stop drain");
        stop = 0;
        finish = 0;
        @(negedge clk);
        if (texture_done) $fatal(1, "FAIL new empty draw");
        finish = 1;
        wait (texture_done);
        if (stalls == 0) $fatal(1, "FAIL no conflict coverage");
        $display("PASS gpu_texture: %0d groups, preload=%0d cycles, PERF5=%0d",
                 received, preload_max, stalls);
        $finish;
    end
    initial begin
        #10000000;
        $fatal(1, "FAIL timeout");
    end
endmodule
