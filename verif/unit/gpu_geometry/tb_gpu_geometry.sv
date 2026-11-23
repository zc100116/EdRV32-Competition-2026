// File: tb_gpu_geometry.sv
// Spec: gpu-spec 2.4, 2.12 and section 7.
// Description: Independent geometry model scoreboard, vertex throughput and command drain.
// Clock domain: clk_gpu.
module tb_gpu_geometry;
    reg clk_i = 0;
    always #5 clk_i = !clk_i;
    reg rst_n_i = 0;
    reg finish_i = 0;
    reg stop_i = 0;
    wire unit_done_o;
    wire perf_vertex_o;
    reg cfg_valid = 0;
    wire cfg_ready;
    reg [511:0] matrix_data;
    reg [95:0] light_data;
    reg [255:0] target_data;
    reg [255:0] pixel_data;
    reg draw_valid = 0;
    wire draw_ready;
    reg [255:0] draw_data;
    reg input_valid = 0;
    wire input_ready;
    reg [127:0] input_data;
    reg output_ready = 1;
    wire output_valid;
    wire [776:0] output_data;
    reg [127:0] inputs [0:191];
    reg [776:0] expected [0:255];
    reg [776:0] held;
    reg holding;
    reg seed_enable = 0;
    reg [9:0] seed_address = 0;
    wire [29:0] seed_data;
    reg [29:0] seed_expected [0:1023];
    reg [29:0] seed_held;
    integer file_id;
    integer fields;
    integer cases;
    integer case_index;
    integer vertex_count;
    integer expected_count;
    integer throughput;
    integer index;
    integer sent;
    integer received;
    integer events;
    integer cycle;
    integer last_vertex;
    integer last_triangle;
    integer total_vertices = 0;
    integer total_triangles = 0;
    reg [31:0] random_state = 32'h87654321;

    edrv32_rom_gpu_recip_q30 u_seed_check (
        .clk_i(clk_i),
        .en_i(seed_enable),
        .addr_i(seed_address),
        .rd_data_o(seed_data)
    );

    edrv32_gpu_geometry u_dut (
        .clk_i(clk_i),
        .rst_n_i(rst_n_i),
        .geometry_cfg_valid_i(cfg_valid),
        .geometry_cfg_ready_o(cfg_ready),
        .geometry_cfg_matrix_i(matrix_data),
        .geometry_cfg_light_i(light_data),
        .geometry_cfg_target_i(target_data),
        .geometry_cfg_pixel_i(pixel_data),
        .geometry_cfg_wide_i(1'b0),
        .draw_valid_i(draw_valid),
        .draw_ready_o(draw_ready),
        .draw_command_i(draw_data),
        .vertex_valid_i(input_valid),
        .vertex_ready_o(input_ready),
        .vertex_data_i(input_data),
        .screen_triangle_valid_o(output_valid),
        .screen_triangle_ready_i(output_ready),
        .screen_triangle_x_o(output_data[0 +: 51]),
        .screen_triangle_y_o(output_data[51 +: 51]),
        .screen_triangle_depth_o(output_data[102 +: 48]),
        .screen_triangle_q_o(output_data[150 +: 105]),
        .screen_triangle_uq_o(output_data[255 +: 153]),
        .screen_triangle_vq_o(output_data[408 +: 153]),
        .screen_triangle_color_o(output_data[561 +: 216]),
        .finish_i(finish_i),
        .stop_i(stop_i),
        .unit_done_o(unit_done_o),
        .perf_vertex_o(perf_vertex_o)
    );

    initial begin
        file_id = $fopen("build/gpu_geometry/vectors.txt","r");
        if (file_id == 0) $fatal(1,"FAIL vectors file missing");
        fields = $fscanf(file_id,"%d",cases);
        if (fields != 1) $fatal(1,"FAIL missing case count");
        repeat (4) @(negedge clk_i);
        rst_n_i = 1;
        $readmemh("build/gpu_geometry/seeds.hex",seed_expected);
        seed_enable = 1;
        for (index = 0; index < 1024; index = index + 1) begin
            seed_address = index[9:0];
            @(negedge clk_i);
            if (seed_data !== seed_expected[index])
                $fatal(1,"FAIL Q30 seed address=%0d actual=%h expected=%h",
                    index,seed_data,seed_expected[index]);
        end
        seed_enable = 0;
        seed_held = seed_data;
        seed_address = 0;
        repeat (3) @(negedge clk_i);
        if (seed_data !== seed_held) $fatal(1,"FAIL seed enable hold");
        for (case_index = 0; case_index < cases; case_index = case_index + 1) begin
            fields = $fscanf(file_id,"%d %d %d",vertex_count,expected_count,throughput);
            if (fields != 3) $fatal(1,"FAIL case header");
            fields = $fscanf(file_id,"%h %h %h %h",matrix_data,light_data,target_data,pixel_data);
            if (fields != 4) $fatal(1,"FAIL configuration vector");
            for (index = 0; index < vertex_count; index = index + 1) begin
                fields = $fscanf(file_id,"%h",inputs[index]);
                if (fields != 1) $fatal(1,"FAIL vertex vector");
            end
            for (index = 0; index < expected_count; index = index + 1) begin
                fields = $fscanf(file_id,"%h",expected[index]);
                if (fields != 1) $fatal(1,"FAIL expected vector");
            end
            finish_i = 0;
            cfg_valid = 1;
            @(posedge clk_i);
            if (!cfg_ready) $fatal(1,"FAIL configuration refused while idle");
            @(negedge clk_i);
            cfg_valid = 0;
            draw_valid = 1;
            draw_data = 0;
            draw_data[119:96] = 24'(vertex_count/3);
            @(posedge clk_i);
            if (!draw_ready) $fatal(1,"FAIL draw refused after configuration");
            @(negedge clk_i);
            draw_valid = 0;
            sent = 0;
            received = 0;
            events = 0;
            cycle = 0;
            last_vertex = -1;
            last_triangle = -1;
            holding = 0;
            while (!unit_done_o) begin
                input_valid = sent < vertex_count;
                input_data = sent < vertex_count ? inputs[sent] : 128'd0;
                finish_i = sent == vertex_count;
                output_ready = throughput != 0 || random_state[1:0] == 0;
                random_state = {random_state[30:0], random_state[31] ^ random_state[21]
                    ^ random_state[1] ^ random_state[0]};
                @(posedge clk_i);
                cycle = cycle + 1;
                if (input_valid && input_ready) begin
                    if (throughput != 0 && sent > 0 && cycle-last_vertex != 2)
                        $fatal(1,"FAIL vertex II=%0d sent=%0d",cycle-last_vertex,sent);
                    last_vertex = cycle;
                    sent = sent + 1;
                end
                if (perf_vertex_o) events = events + 1;
                if (holding && (!output_valid || held !== output_data))
                    $fatal(1,"FAIL output changed while blocked");
                held = output_data;
                holding = output_valid && !output_ready;
                if (output_valid && output_ready) begin
                    if (received >= expected_count || output_data !== expected[received]) begin
                        $display("FAIL case=%0d triangle=%0d actual=%h expected=%h",case_index,
                            received,output_data,expected[received]);
                        $fatal(1,"FAIL geometry mismatch");
                    end
                    if (throughput != 0 && received > 0 && cycle-last_triangle != 6)
                        $fatal(1,"FAIL triangle interval=%0d",cycle-last_triangle);
                    last_triangle = cycle;
                    received = received + 1;
                end
                if (cycle > 1000000) $fatal(1,"FAIL timeout case=%0d",case_index);
                @(negedge clk_i);
            end
            if (sent != vertex_count || received != expected_count || events != vertex_count)
                $fatal(1,"FAIL case=%0d sent=%0d got=%0d events=%0d expected=%0d",case_index,
                    sent,received,events,expected_count);
            input_valid = 0;
            total_vertices = total_vertices + sent;
            total_triangles = total_triangles + received;
        end
        // Abort a partial triangle and prove no stale projection returns survive restart.
        finish_i = 0;
        cfg_valid = 1;
        @(negedge clk_i);
        cfg_valid = 0;
        draw_valid = 1;
        draw_data[119:96] = 24'd3;
        @(negedge clk_i);
        draw_valid = 0;
        sent = 0;
        input_valid = 1;
        input_data = inputs[0];
        while (sent < 5) begin
            @(posedge clk_i);
            if (input_ready) sent = sent + 1;
            @(negedge clk_i);
        end
        input_valid = 0;
        stop_i = 1;
        finish_i = 1;
        repeat (2) @(negedge clk_i);
        if (!unit_done_o || output_valid) $fatal(1,"FAIL geometry stop drain");
        stop_i = 0;
        finish_i = 0;
        cfg_valid = 1;
        @(negedge clk_i);
        cfg_valid = 0;
        draw_valid = 1;
        draw_data[119:96] = 0;
        @(negedge clk_i);
        draw_valid = 0;
        finish_i = 1;
        repeat (40) begin
            @(negedge clk_i);
            if (output_valid) $fatal(1,"FAIL stale geometry output after stop");
        end
        if (!unit_done_o) $fatal(1,"FAIL empty restart did not finish");
        $fclose(file_id);
        $display("PASS gpu_geometry %0d draws, %0d vertices, %0d triangles; vertex II=2",
            cases,total_vertices,total_triangles);
        $finish;
    end
endmodule
