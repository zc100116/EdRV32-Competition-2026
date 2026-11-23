// File: tb_gpu_texture_ram.sv
// Spec: gpu-spec 2.6; GPU microarchitecture 4.8.
// Description: Front-door storage, physical bank boundaries and read latency.
// Clock: testbench GPU clock.
`timescale 1ns/1ps
module tb_gpu_texture_ram;
    logic  clk;
    logic  rst_n;
    logic  finish;
    logic  stop;
    logic  unit_done;
    logic  texture_load_valid;
    logic  texture_load_ready;
    logic [17:0] texture_load_addr;
    logic [255:0] texture_load_data;
    logic [31:0] texture_load_keep;
    logic [7:0] read_en;
    logic [119:0] read_addr;
    logic [127:0] read_data;
    always #5 clk = ~clk;
    edrv32_gpu_texture_ram u_dut (
        .clk_i(clk),
        .rst_n_i(rst_n),
        .finish_i(finish),
        .stop_i(stop),
        .unit_done_o(unit_done),
        .texture_load_valid_i(texture_load_valid),
        .texture_load_ready_o(texture_load_ready),
        .texture_load_addr_i(texture_load_addr),
        .texture_load_data_i(texture_load_data),
        .texture_load_keep_i(texture_load_keep),
        .read_en_i(read_en),
        .read_addr_i(read_addr),
        .read_data_o(read_data)
    );
    reg [255:0] ram [0:6143];
    reg [15:0] expected [0:4][0:7];
    reg [4:0] valid = 0;
    integer cycle = 0;
    integer beat;
    integer row;
    integer bank;
    integer port_idx;
    integer stage;
    integer i;
    integer address;
    integer checked = 0;
    always @(posedge clk) begin
        cycle <= cycle + 1;
        valid <= {valid[3:0], read_en != 0};
        for (stage = 4; stage > 0; stage = stage - 1) begin
            for (i = 0; i < 8; i = i + 1) expected[stage][i] <= expected[stage-1][i];
        end
        for (i = 0; i < 8; i = i + 1) begin
            address = (int'(read_addr[i*15 +: 15])*4 + i/2)*2;
            expected[0][i] <= ram[address/32][(address%32)*8 +: 16];
            if (valid[4]) begin
                if (read_data[i*16 +: 16] !== expected[4][i]) begin
                    $fatal(1, "FAIL bank/port=%0d cycle=%0d expected=%h actual=%h",
                           i, cycle, expected[4][i], read_data[i*16 +: 16]);
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
        texture_load_valid = 0;
        texture_load_addr = 0;
        texture_load_data = 0;
        texture_load_keep = 0;
        read_en = 0;
        read_addr = 0;
        $readmemh("build/gpu_texture/vectors/ram.hex", ram);
        repeat (4) @(negedge clk);
        rst_n = 1;
        for (beat = 0; beat < 6144; beat = beat + 1) begin
            texture_load_valid = 1;
            texture_load_addr = 18'(beat*32);
            texture_load_data = ram[beat];
            texture_load_keep = '1;
            @(posedge clk);
            while (!texture_load_ready) @(posedge clk);
            @(negedge clk);
        end
        texture_load_valid = 0;
        finish = 1;
        wait (unit_done);
        @(negedge clk);
        // Every row and every segment, both sides of 96 KiB, two distinct ports.
        for (row = 0; row < 24576; row = row + 1) begin
            read_en = '1;
            for (bank = 0; bank < 4; bank = bank + 1) begin
                read_addr[bank*30 +: 15] = 15'(row);
                read_addr[bank*30+15 +: 15] = 15'(24575-row);
            end
            @(negedge clk);
        end
        read_en = 0;
        repeat (6) @(negedge clk);
        // Byte enables preserve the unselected bytes, including final physical beat.
        finish = 0;
        texture_load_valid = 1;
        texture_load_addr = 18'd196576;
        texture_load_data = ~ram[6143];
        texture_load_keep = 32'h55555555;
        for (i = 0; i < 32; i = i + 2) ram[6143][i*8 +: 8] = ~ram[6143][i*8 +: 8];
        @(negedge clk);
        texture_load_valid = 0;
        stop = 1;
        finish = 1;
        wait (unit_done);
        @(negedge clk);
        stop = 0;
        read_en = '1;
        read_addr = {8{15'd24575}};
        @(negedge clk);
        read_en = 0;
        repeat (6) @(negedge clk);
        $display("PASS gpu_texture_ram: %0d port responses, latency=5", checked);
        $finish;
    end
    initial begin
        #10000000;
        $fatal(1, "FAIL timeout");
    end
endmodule
