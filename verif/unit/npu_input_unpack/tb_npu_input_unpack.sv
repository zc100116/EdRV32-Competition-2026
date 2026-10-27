// File: tb_npu_input_unpack.sv
// Spec: npu-spec 2.2, 5.1; datapath design 4.3.2, 4.4.2; OP-04.
// Description: Self-check C16 direct writes, timed C4 expansion and row completions.
// Clock: clk_npu.
module tb_npu_input_unpack;
    reg clk = 0;
    always #5 clk <= ~clk;
    reg rst_n = 0;
    bit monitor_active = 0;
    reg cancel = 0;
    reg c4 = 0;
    reg valid = 0;
    wire ready;
    reg bank = 0;
    reg [9:0] addr = 0;
    reg [255:0] data = 0;
    reg row_last = 0;
    wire row_done;
    wire idle;
    wire cache_valid;
    wire cache_bank;
    wire [9:0] cache_addr;
    wire [255:0] cache_data;
    integer cycle = 0;
    integer head = 0;
    integer tail = 0;
    integer writes = 0;
    integer rows = 0;
    integer due [0:1023];
    reg expected_bank [0:1023];
    reg [9:0] expected_addr [0:1023];
    reg [255:0] expected_data [0:1023];
    reg expected_last [0:1023];
    reg expected_done;
    bit continuous_stream = 0;
    integer previous_accept = -1;

    edrv32_npu_input_unpack dut (
        .clk_i(clk),
        .rst_n_i(rst_n),
        .cancel_i(cancel),
        .cfg_in_c4_i(c4),
        .line_wr_valid_i(valid),
        .line_wr_ready_o(ready),
        .line_wr_bank_i(bank),
        .line_wr_addr_i(addr),
        .line_wr_data_i(data),
        .line_wr_row_last_i(row_last),
        .line_wr_row_done_o(row_done),
        .line_wr_idle_o(idle),
        .cache_wr_valid_o(cache_valid),
        .cache_wr_bank_o(cache_bank),
        .cache_wr_addr_o(cache_addr),
        .cache_wr_data_o(cache_data)
    );

    initial forever begin
        @(posedge clk);
        cycle = cycle + 1;
        expected_done = 0;
        if (!monitor_active || cancel) begin
            head = tail;
        end else begin
            if (!continuous_stream) previous_accept = -1;
            if (valid && ready) begin
                if (continuous_stream && previous_accept >= 0 &&
                    cycle-previous_accept != (c4 ? 4 : 1))
                    $fatal(1, "FAIL acceptance interval cycle=%0d previous=%0d C4=%b",
                        cycle, previous_accept, c4);
                previous_accept = cycle;
                for (integer item = 0; item < (c4 ? 4 : 1); item++) begin
                    due[tail] = cycle + (c4 ? item + 1 : 0);
                    expected_bank[tail] = c4 ? 1'(item % 2) : bank;
                    expected_addr[tail] = c4 ? addr + 10'(item / 2) : addr;
                    expected_data[tail] = c4 ?
                        {96'd0, data[64*item+32+:32], 96'd0, data[64*item+:32]} : data;
                    expected_last[tail] = row_last && (!c4 || item == 3);
                    tail++;
                end
            end
            if (cache_valid !== (head < tail && due[head] == cycle)) begin
                $fatal(1, "FAIL write timing cycle=%0d valid=%b head=%0d", cycle,
                    cache_valid, head);
            end
            if (cache_valid) begin
                if ({cache_bank, cache_addr, cache_data} !==
                    {expected_bank[head], expected_addr[head], expected_data[head]}) begin
                    $fatal(1, "FAIL cache write cycle=%0d bank=%b addr=%0d data=%h expected=%h",
                        cycle, cache_bank, cache_addr, cache_data, expected_data[head]);
                end
                expected_done = expected_last[head];
                writes++;
                head++;
            end
        end
        #1;
        if (row_done !== expected_done) begin
            $fatal(1, "FAIL row_done cycle=%0d expected=%b got=%b", cycle,
                expected_done, row_done);
        end
        if (row_done) rows++;
    end

    task automatic send_beat(input integer number, input bit last);
        @(negedge clk);
        valid = 1;
        bank = c4 ? 1'b0 : 1'(number % 2);
        addr = 10'(200 + 2*number);
        for (integer b = 0; b < 32; b++)
            data[8*b+:8] = (c4 && b % 4 == 3) ? 8'd0 : 8'(number*32+b);
        row_last = last;
        do @(posedge clk); while (!ready);
        #2;
        valid = 0;
    endtask

    initial begin
        repeat (3) @(negedge clk);
        rst_n = 1;
        monitor_active = 1;
        continuous_stream = 1;
        for (integer beat = 0; beat < 20; beat++) send_beat(beat, beat % 4 == 3);
        continuous_stream = 0;
        repeat (2) @(negedge clk);
        if (rows != 5 || writes != 20 || !idle) $fatal(1, "FAIL C16 counts/idle");
        c4 = 1;
        // All eight pixels are distinct; each new beat is accepted on the fourth write.
        continuous_stream = 1;
        for (integer beat = 0; beat < 24; beat++) send_beat(beat, beat % 3 == 2);
        continuous_stream = 0;
        repeat (6) @(negedge clk);
        if (rows != 13 || writes != 116 || !idle) $fatal(1, "FAIL C4 counts/idle");
        send_beat(30, 1);
        @(negedge clk);
        cancel = 1;
        @(negedge clk);
        cancel = 0;
        if (!idle) $fatal(1, "FAIL cancel idle");
        send_beat(31, 1);
        repeat (6) @(negedge clk);
        if (rows != 14 || head != tail || !idle) $fatal(1, "FAIL recovery row completion");
        $display("PASS input_unpack: %0d writes, %0d rows; C16 e, C4 e+1..e+4", writes, rows);
        $finish;
    end
endmodule
