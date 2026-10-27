// File: tb_npu_weight_store.sv
// Spec: npu-spec 4.3, 5.2; datapath design 5.2 D1-B (TL-03, CP-01).
// Description: Self-check sequential DMA mapping, all 1152 rows, segment boundaries,
// three weight formats, concurrent block loading, enabled reads and cancellation.
// Clock: clk_npu.
module tb_npu_weight_store;
    reg clk = 0;
    reg rst_n = 0;
    reg cancel = 0;
    reg wr_valid = 0;
    reg [13:0] wr_addr = 0;
    reg [255:0] wr_data = 0;
    reg rd_en = 0;
    reg [10:0] rd_addr = 0;
    wire [2047:0] rd_data;
    reg [255:0] memory [0:9215];
    reg pending = 0;
    reg [13:0] pending_addr;
    reg [255:0] pending_data;
    reg [2047:0] array_data;
    reg array_known = 0;
    integer checks = 0;
    integer cycles = 0;

    always #5 clk <= ~clk;
    edrv32_npu_weight_store u_dut (
        .clk_i(clk),
        .rst_n_i(rst_n),
        .cancel_i(cancel),
        .weight_wr_valid_i(wr_valid),
        .weight_wr_addr_i(wr_addr),
        .weight_wr_data_i(wr_data),
        .weight_rd_en_i(rd_en),
        .weight_rd_addr_i(rd_addr),
        .weight_rd_data_o(rd_data)
    );

    // Reads use the old memory contents; writes commit one edge after input acceptance.
    initial begin : p_scoreboard
        reg [2047:0] expected;
        reg known;
        forever begin
            @(posedge clk);
            cycles = cycles + 1;
            expected = array_data;
            known = array_known;
            if (rd_en) begin
                for (int b = 0; b < 8; b++)
                    array_data[256*b +: 256] = memory[8*int'(rd_addr)+b];
                array_known = 1;
            end
            if (pending) memory[pending_addr] = pending_data;
            pending = rst_n && !cancel && wr_valid;
            pending_addr = wr_addr;
            pending_data = wr_data;
            #1;
            if (known) begin
                checks = checks + 1;
                if (rd_data !== expected)
                    $fatal(1, "FAIL cycle=%0d time=%0t expected=%h actual=%h",
                           cycles, $time, expected, rd_data);
            end
        end
    end

    task automatic cycle;
        @(posedge clk);
        #2;
        @(negedge clk);
    endtask

    function automatic [255:0] capacity_beat(input int row, input int bank);
        reg [255:0] value;
        for (int word_idx = 0; word_idx < 8; word_idx++)
            value[32*word_idx +: 32] = 32'h807f0000 ^ (row << 8) ^ (bank << 4) ^ word_idx;
        return value;
    endfunction

    // Synthetic W[cout,cin,ky,kx] is serialized independently for each frozen format.
    function automatic [255:0] format_beat(input int mode, input int row, input int bank);
        int oc;
        int cin;
        int kernel_pos;
        int byte_idx;
        reg [255:0] value;
        for (int j = 0; j < 32; j++) begin
            byte_idx = 32*bank+j;
            oc = byte_idx/8;
            cin = byte_idx%8;
            kernel_pos = row;
            if (mode == 0) begin
                cin = cin + 8*(row%2);
                kernel_pos = row/2;
            end else if (mode == 1) begin
                cin = cin + 8*(oc/16);
                oc = oc%16;
            end
            value[8*j +: 8] = 8'(oc*17 + cin*13 + kernel_pos*7 + mode*31);
            if (mode == 2 && cin >= 3) value[8*j +: 8] = 0;
        end
        return value;
    endfunction

    initial begin
        cycle();
        rst_n = 1;
        // L7: 8 blocks x 144 rows, 9216 contiguous 32-byte DMA beats.
        for (int m = 0; m < 9216; m++) begin
            wr_valid = 1;
            wr_addr = 14'(m);
            wr_data = capacity_beat(m/8, m%8);
            rd_en = (m >= 1153);
            rd_addr = 11'((m/8)%144);
            cycle();
        end
        wr_valid = 0;
        cycle();
        // First legal read of the last loaded row: final write input e, read array at e+2.
        rd_en = 1;
        rd_addr = 1151;
        cycle();
        for (int row = 0; row < 1152; row++) begin
            rd_en = 1;
            rd_addr = 11'(row);
            cycle();
        end
        // Alternate segments and pause at their exact boundaries, with changing idle addresses.
        for (int i = 0; i < 40; i++) begin
            rd_en = (i%4 != 2);
            case (i%5)
                0: rd_addr = 511;
                1: rd_addr = 512;
                2: rd_addr = 1023;
                3: rd_addr = 1024;
                default: rd_addr = 1151;
            endcase
            cycle();
        end
        rd_en = 0;
        repeat (3) cycle();
        // Pending write commits on cancel; the write presented with cancel is discarded.
        wr_valid = 1;
        wr_addr = 0;
        wr_data = ~capacity_beat(0, 0);
        cycle();
        cancel = 1;
        wr_addr = 8;
        wr_data = 0;
        cycle();
        cancel = 0;
        wr_valid = 0;
        repeat (2) cycle();
        rd_en = 1;
        rd_addr = 0;
        cycle();
        rd_addr = 1;
        cycle();
        // Reset/cancel affect write control, while read data and RAM remain live.
        rst_n = 0;
        cycle();
        rst_n = 1;
        cancel = 1;
        rd_addr = 1024;
        cycle();
        cancel = 0;
        for (int mode = 0; mode < 3; mode++) begin
            rd_en = 0;
            for (int m = 0; m < (mode == 0 ? 144 : 72); m++) begin
                wr_valid = 1;
                wr_addr = 14'(m);
                wr_data = format_beat(mode, m/8, m%8);
                cycle();
            end
            wr_valid = 0;
            repeat (2) cycle();
            for (int row = 0; row < (mode == 0 ? 18 : 9); row++) begin
                rd_en = 1;
                rd_addr = 11'(row);
                cycle();
            end
            rd_en = 0;
            repeat (3) cycle();
        end
        $display("PASS weight_store checks=%0d cycles=%0d write=1 read=2", checks, cycles);
        $finish;
    end
endmodule
