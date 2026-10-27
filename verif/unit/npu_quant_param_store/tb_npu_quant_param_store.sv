// File: tb_npu_quant_param_store.sv
// Spec: npu-spec 4.2, 5.2; datapath design 5.2 D1-B (TL-03, CP-03).
// Description: Check all eight blocks and phases, signed payload bit patterns, zero reserved
// bits, concurrent block loading, two-stage reads, read holds and cancelled writes.
// Clock: clk_npu.
module tb_npu_quant_param_store;
    reg clk = 0;
    reg rst_n = 0;
    reg cancel = 0;
    reg wr_valid = 0;
    reg [2:0] wr_block = 0;
    reg [4:0] wr_channel = 0;
    reg [31:0] wr_bias = 0;
    reg [15:0] wr_mult = 0;
    reg [5:0] wr_shift = 0;
    reg rd_en = 0;
    reg [2:0] rd_block = 0;
    reg [1:0] rd_phase = 0;
    wire [511:0] rd_data;
    reg [63:0] memory [0:255];
    reg pending = 0;
    reg [7:0] pending_addr;
    reg [63:0] pending_data;
    reg [511:0] array_data;
    reg array_known = 0;
    integer checks = 0;
    integer cycles = 0;

    always #5 clk <= ~clk;
    edrv32_npu_quant_param_store u_dut (
        .clk_i(clk),
        .rst_n_i(rst_n),
        .cancel_i(cancel),
        .quant_wr_valid_i(wr_valid),
        .quant_wr_block_i(wr_block),
        .quant_wr_channel_i(wr_channel),
        .quant_wr_bias_i(wr_bias),
        .quant_wr_mult_i(wr_mult),
        .quant_wr_shift_i(wr_shift),
        .param_rd_en_i(rd_en),
        .param_rd_block_i(rd_block),
        .param_rd_phase_i(rd_phase),
        .param_rd_data_o(rd_data)
    );

    initial begin : p_scoreboard
        reg [511:0] expected;
        reg known;
        forever begin
            @(posedge clk);
            cycles = cycles + 1;
            expected = array_data;
            known = array_known;
            if (rd_en) begin
                for (int lane = 0; lane < 8; lane++)
                    array_data[64*lane +: 64] =
                        memory[32*int'(rd_block)+8*int'(rd_phase)+lane];
                array_known = 1;
            end
            if (pending) memory[pending_addr] = pending_data;
            pending = rst_n && !cancel && wr_valid;
            pending_addr = 8'(32*int'(wr_block)+int'(wr_channel));
            // Build expected record by numeric fields, including all ten reserved zero bits.
            pending_data = 64'(wr_bias) | (64'(wr_mult) << 32) | (64'(wr_shift) << 48);
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
            for (int c = 0; c < 32; c++) begin
                wr_valid = 1;
                wr_block = 3'(block_idx);
                wr_channel = 5'(c);
                wr_bias = (c%2 == 0 ? 32'h80000000 : 32'h7fffffff) ^
                          32'(block_idx*257+c*65536);
                case (c%4)
                    0: wr_mult = 16'h8000;
                    1: wr_mult = 16'h7fff;
                    2: wr_mult = 0;
                    default: wr_mult = 16'(-c-block_idx);
                endcase
                wr_shift = c%2 == 0 ? 6'd0 : 6'd47;
                rd_en = block_idx != 0 && c != 0;
                rd_block = 3'(block_idx == 0 ? 0 : block_idx-1);
                rd_phase = 2'(c%4);
                cycle();
            end
        end
        wr_valid = 0;
        cycle();
        rd_en = 1;
        rd_block = 7;
        rd_phase = 3;
        cycle();
        for (int i = 0; i < 128; i++) begin
            rd_en = i%3 != 1;
            rd_block = 3'((i*5)%8);
            rd_phase = 2'((i/8)%4);
            cycle();
        end
        // Exhaustive block/phase sweep without bubbles.
        for (int i = 0; i < 32; i++) begin
            rd_en = 1;
            rd_block = 3'(i/4);
            rd_phase = 2'(i%4);
            cycle();
        end
        rd_en = 0;
        repeat (3) cycle();
        wr_valid = 1;
        wr_block = 7;
        wr_channel = 31;
        wr_bias = 32'h12345678;
        wr_mult = 16'hffff;
        wr_shift = 1;
        cycle();
        cancel = 1;
        wr_channel = 30;
        wr_bias = 0;
        cycle();
        cancel = 0;
        wr_valid = 0;
        repeat (2) cycle();
        rd_en = 1;
        rd_block = 7;
        rd_phase = 3;
        cycle();
        rst_n = 0;
        rd_block = 0;
        rd_phase = 0;
        cycle();
        rst_n = 1;
        rd_en = 0;
        repeat (4) cycle();
        $display("PASS quant_param_store checks=%0d cycles=%0d write=1 read=2", checks, cycles);
        $finish;
    end
endmodule
