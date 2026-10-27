// File: tb_npu_activation_lut.sv
// Spec: npu-spec 2.3, 4.2, 5.2; datapath design 5.2 D1-B (OP-05, CP-03).
// Description: Check eight different tables, all 16 independent read addresses, index
// boundaries, concurrent block loading, enabled two-stage reads and cancelled writes.
// Clock: clk_npu.
module tb_npu_activation_lut;
    reg clk = 0;
    reg rst_n = 0;
    reg cancel = 0;
    reg wr_valid = 0;
    reg [2:0] wr_block = 0;
    reg [7:0] wr_addr = 0;
    reg [7:0] wr_data = 0;
    reg rd_en = 0;
    reg [2:0] rd_block = 0;
    reg [127:0] rd_addr = 0;
    wire [127:0] rd_data;
    reg [7:0] memory [0:2047];
    reg pending = 0;
    reg [10:0] pending_addr;
    reg [7:0] pending_data;
    reg [127:0] array_data;
    reg array_known = 0;
    integer checks = 0;
    integer cycles = 0;

    always #5 clk <= ~clk;
    edrv32_npu_activation_lut u_dut (
        .clk_i(clk),
        .rst_n_i(rst_n),
        .cancel_i(cancel),
        .lut_wr_valid_i(wr_valid),
        .lut_wr_block_i(wr_block),
        .lut_wr_addr_i(wr_addr),
        .lut_wr_data_i(wr_data),
        .lut_rd_en_i(rd_en),
        .lut_rd_block_i(rd_block),
        .lut_rd_addr_i(rd_addr),
        .lut_rd_data_o(rd_data)
    );

    initial begin : p_scoreboard
        reg [127:0] expected;
        reg known;
        forever begin
            @(posedge clk);
            cycles = cycles + 1;
            expected = array_data;
            known = array_known;
            if (rd_en) begin
                for (int lane = 0; lane < 16; lane++)
                    array_data[8*lane +: 8] = memory[256*int'(rd_block) +
                                                   int'(rd_addr[8*lane +: 8])];
                array_known = 1;
            end
            if (pending) memory[pending_addr] = pending_data;
            pending = rst_n && !cancel && wr_valid;
            pending_addr = 11'(256*int'(wr_block)+int'(wr_addr));
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

    initial begin
        cycle();
        rst_n = 1;
        for (int block_idx = 0; block_idx < 8; block_idx++) begin
            for (int idx = 0; idx < 256; idx++) begin
                wr_valid = 1;
                wr_block = 3'(block_idx);
                wr_addr = 8'(idx);
                wr_data = 8'((idx*73) ^ (block_idx*29) ^ (idx/8));
                rd_en = block_idx != 0 && idx != 0;
                rd_block = 3'(block_idx == 0 ? 0 : block_idx-1);
                for (int lane = 0; lane < 16; lane++)
                    rd_addr[8*lane +: 8] = 8'(idx+lane*17);
                cycle();
            end
        end
        wr_valid = 0;
        cycle();
        rd_en = 1;
        rd_block = 7;
        rd_addr = {16{8'd255}};
        cycle();
        // Every lane visits every index in each block, with distinct simultaneous addresses.
        for (int block_idx = 0; block_idx < 8; block_idx++) begin
            rd_block = 3'(block_idx);
            for (int idx = 0; idx < 256; idx++) begin
                rd_en = 1;
                for (int lane = 0; lane < 16; lane++)
                    rd_addr[8*lane +: 8] = 8'(idx+lane*17);
                cycle();
            end
        end
        // Rapid block switches, bubbles and 0/127/128/255 on all lanes.
        for (int i = 0; i < 64; i++) begin
            rd_en = i%4 != 1;
            rd_block = 3'((i*3)%8);
            for (int lane = 0; lane < 16; lane++) begin
                case ((lane+i)%4)
                    0: rd_addr[8*lane +: 8] = 0;
                    1: rd_addr[8*lane +: 8] = 127;
                    2: rd_addr[8*lane +: 8] = 128;
                    default: rd_addr[8*lane +: 8] = 255;
                endcase
            end
            cycle();
        end
        rd_en = 0;
        repeat (3) cycle();
        wr_valid = 1;
        wr_block = 7;
        wr_addr = 255;
        wr_data = 8'h42;
        cycle();
        cancel = 1;
        wr_addr = 0;
        wr_data = 0;
        cycle();
        cancel = 0;
        wr_valid = 0;
        repeat (2) cycle();
        rd_en = 1;
        rd_block = 7;
        for (int lane = 0; lane < 16; lane++)
            rd_addr[8*lane +: 8] = lane%2 == 0 ? 8'd0 : 8'd255;
        cycle();
        rst_n = 0;
        rd_block = 0;
        cycle();
        rst_n = 1;
        rd_en = 0;
        repeat (4) cycle();
        $display("PASS activation_lut checks=%0d cycles=%0d write=1 read=2", checks, cycles);
        $finish;
    end
endmodule
