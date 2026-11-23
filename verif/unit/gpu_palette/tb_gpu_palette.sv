// File: tb_gpu_palette.sv
// Spec: gpu-spec 2.6; GPU microarchitecture 4.8.
// Description: Front-door storage, physical bank boundaries and read latency.
// Clock: testbench GPU clock.
`timescale 1ns/1ps
module tb_gpu_palette;
    logic  clk;
    logic  rst_n;
    logic  finish;
    logic  stop;
    logic  unit_done;
    logic  palette_load_valid;
    logic  palette_load_ready;
    logic [11:0] palette_load_idx;
    logic [19:0] palette_load_data;
    logic  palette_prepare_valid;
    logic  palette_prepare_ready;
    logic [3:0] palette_prepare_group;
    logic  palette_prepared_valid;
    logic  palette_prepared_ready;
    logic  full_read_en;
    logic [47:0] full_read_idx;
    logic [79:0] full_read_data;
    logic  current_read_en;
    logic [63:0] current_read_idx;
    logic [159:0] current_read_data;
    always #5 clk = ~clk;
    edrv32_gpu_palette u_dut (
        .clk_i(clk),
        .rst_n_i(rst_n),
        .finish_i(finish),
        .stop_i(stop),
        .unit_done_o(unit_done),
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
    reg [19:0] pal [0:4095];
    reg [19:0] expected_full [0:3][0:3];
    reg [19:0] expected_current [0:3][0:7];
    reg [3:0] full_valid = 0;
    reg [3:0] current_valid = 0;
    integer group_idx;
    integer index;
    integer stage;
    integer port_idx;
    integer cycle = 0;
    integer begin_cycle;
    integer preload_max = 0;
    integer checked = 0;
    always @(posedge clk) begin
        cycle <= cycle + 1;
        full_valid <= {full_valid[2:0], full_read_en};
        current_valid <= {current_valid[2:0], current_read_en};
        for (stage = 3; stage > 0; stage = stage - 1) begin
            for (port_idx = 0; port_idx < 4; port_idx = port_idx + 1) begin
                expected_full[stage][port_idx] <= expected_full[stage-1][port_idx];
            end
            for (port_idx = 0; port_idx < 8; port_idx = port_idx + 1) begin
                expected_current[stage][port_idx] <= expected_current[stage-1][port_idx];
            end
        end
        for (port_idx = 0; port_idx < 4; port_idx = port_idx + 1) begin
            expected_full[0][port_idx] <= pal[full_read_idx[port_idx*12 +: 12]];
            if (full_valid[3]) begin
                if (full_read_data[port_idx*20 +: 20] !== expected_full[3][port_idx]) begin
                    $fatal(1, "FAIL full port=%0d cycle=%0d expected=%h actual=%h",
                           port_idx, cycle, expected_full[3][port_idx],
                           full_read_data[port_idx*20 +: 20]);
                end
                checked = checked + 1;
            end
        end
        for (port_idx = 0; port_idx < 8; port_idx = port_idx + 1) begin
            expected_current[0][port_idx] <=
                pal[group_idx*256 + int'(current_read_idx[port_idx*8 +: 8])];
            if (current_valid[3]) begin
                if (current_read_data[port_idx*20 +: 20] !== expected_current[3][port_idx]) begin
                    $fatal(1, "FAIL current group=%0d port=%0d cycle=%0d expected=%h actual=%h",
                           group_idx, port_idx, cycle, expected_current[3][port_idx],
                           current_read_data[port_idx*20 +: 20]);
                end
                checked = checked + 1;
            end
        end
    end
    initial begin
        clk = 0;
        rst_n = 0;
        finish = 0;
        stop = 0;
        palette_load_valid = 0;
        palette_load_idx = 0;
        palette_load_data = 0;
        palette_prepare_valid = 0;
        palette_prepare_group = 0;
        palette_prepared_ready = 0;
        full_read_en = 0;
        full_read_idx = 0;
        current_read_en = 0;
        current_read_idx = 0;
        $readmemh("build/gpu_texture/vectors/palette.hex", pal);
        repeat (4) @(negedge clk);
        rst_n = 1;
        for (index = 0; index < 4096; index = index + 1) begin
            palette_load_valid = 1;
            palette_load_idx = 12'(index);
            palette_load_data = pal[index];
            @(negedge clk);
        end
        palette_load_valid = 0;
        for (index = 0; index < 4096; index = index + 1) begin
            full_read_en = 1;
            for (port_idx = 0; port_idx < 4; port_idx = port_idx + 1) begin
                full_read_idx[port_idx*12 +: 12] = 12'((index + port_idx*1031) % 4096);
            end
            @(negedge clk);
        end
        full_read_en = 0;
        repeat (5) @(negedge clk);
        for (group_idx = 0; group_idx < 16; group_idx = group_idx + 1) begin
            palette_prepare_valid = 1;
            palette_prepare_group = 4'(group_idx);
            begin_cycle = cycle;
            @(posedge clk);
            while (!palette_prepare_ready) @(posedge clk);
            @(negedge clk);
            palette_prepare_valid = 0;
            wait (palette_prepared_valid);
            @(negedge clk);
            if (cycle-begin_cycle > 264) $fatal(1, "FAIL preload budget");
            if (cycle-begin_cycle > preload_max) preload_max = cycle-begin_cycle;
            repeat (4) @(negedge clk);
            if (!palette_prepared_valid) $fatal(1, "FAIL response hold");
            palette_prepared_ready = 1;
            @(negedge clk);
            palette_prepared_ready = 0;
            for (index = 0; index < 256; index = index + 1) begin
                current_read_en = 1;
                for (port_idx = 0; port_idx < 8; port_idx = port_idx + 1) begin
                    current_read_idx[port_idx*8 +: 8] = 8'(index + port_idx*31);
                end
                @(negedge clk);
            end
            current_read_en = 0;
            repeat (5) @(negedge clk);
        end
        finish = 1;
        wait (unit_done);
        $display("PASS gpu_palette: %0d responses, preload=%0d cycles, latency=4",
                 checked, preload_max);
        $finish;
    end
    initial begin
        #10000000;
        $fatal(1, "FAIL timeout");
    end
endmodule
