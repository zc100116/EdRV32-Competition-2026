// File: tb_edrv32_async_fifo.sv
// Spec: infra-plan I-06; edrv32-soc-spec 5.2, 5.3
// Description: Self-checking directed primitive tests.
// Clock domain: test clocks below.
module tb_edrv32_async_fifo;
    task automatic check(input bit condition, input string message);
        if (!condition) begin
            $display("FAIL: %s (expected true, actual false) at %0t", message, $time);
            $fatal(1);
        end
    endtask

    initial begin
        #100000;
        $fatal(1, "FAIL: timeout at %0t", $time);
    end

    reg write_clk = 0;
    reg read_clk = 0;
    reg rst_n = 1;
    reg valid = 0;
    wire ready;
    reg [7:0] data = 0;
    wire out_valid;
    reg out_ready = 0;
    wire [7:0] out_data;
    always #5 write_clk = ~write_clk;
    always #7 read_clk = ~read_clk;

    edrv32_async_fifo #(.WIDTH(8), .DEPTH(4)) u_dut (
        .clk_write_i(write_clk),
        .rst_write_n_i(rst_n),
        .clk_read_i(read_clk),
        .rst_read_n_i(rst_n),
        .valid_i(valid),
        .ready_o(ready),
        .data_i(data),
        .valid_o(out_valid),
        .ready_i(out_ready),
        .data_o(out_data)
    );

    task automatic push(input integer value);
        @(negedge write_clk);
        valid = 1;
        data = 8'(value);
        do @(posedge write_clk); while (!ready);
        @(negedge write_clk);
        valid = 0;
    endtask

    task automatic pop(input integer expected);
        @(negedge read_clk);
        out_ready = 1;
        do @(posedge read_clk); while (!out_valid);
        check(out_data === 8'(expected),
              $sformatf("FIFO expected %0d actual %0d", expected, out_data));
        @(negedge read_clk);
        out_ready = 0;
    endtask

    initial begin
        #1 rst_n = 0;
        repeat (4) @(negedge write_clk);
        check(!out_valid && ready, "empty after reset");
        rst_n = 1;
        // Empty reads must not advance the consumer pointer.
        @(negedge read_clk);
        out_ready = 1;
        repeat (3) @(negedge read_clk);
        check(!out_valid, "empty read remains empty");
        out_ready = 0;
        for (integer round_idx = 0; round_idx < 3; round_idx = round_idx + 1) begin
            for (integer index = 0; index < 4; index = index + 1)
                push(round_idx * 4 + index);
            check(!ready, "full after four writes");
            // Full writes must not replace queued payloads.
            @(negedge write_clk);
            valid = 1;
            data = 8'hff;
            repeat (3) @(negedge write_clk);
            check(!ready, "full stalls producer");
            valid = 0;
            for (integer index = 0; index < 4; index = index + 1)
                pop(round_idx * 4 + index);
            repeat (5) @(negedge read_clk);
            check(!out_valid, "empty after drain");
        end
        // Overlap producer and consumer to exercise independent handshakes and wrap.
        fork
            begin
                for (integer index = 32; index < 64; index = index + 1) push(index);
            end
            begin
                for (integer index = 32; index < 64; index = index + 1) pop(index);
            end
        join
        repeat (5) @(negedge read_clk);
        check(!out_valid, "stream fully drained");
        push(91);
        #1 rst_n = 0;
        #1 check(!out_valid && ready, "reset discards occupancy");
        repeat (3) @(negedge write_clk);
        rst_n = 1;
        push(92);
        pop(92);
        $display("PASS");
        $finish;
    end
endmodule
