// File: tb.sv
// Spec: V-P2; edrv32-soc-spec 5.2, 5.3.
// Description: External-RAM FIFO ordering, boundaries, stalls and throughput.
// Clock domain: independent test clocks for async, one clock for sync.
module fifo_case #(
    parameter DEPTH = 16,
    parameter WRITE_HALF = 5,
    parameter READ_HALF = 5,
    parameter CASE_ID = 0
) (
    output bit done = 0
);
    bit write_clk = 0;
    bit read_clk = 0;
    bit rst_n = 1;
    bit valid = 0;
    wire ready;
    reg [31:0] data = 0;
    wire out_valid;
    bit out_ready = 0;
    wire [31:0] out_data;
    wire wr_en;
    wire [$clog2(DEPTH)-1:0] wr_addr;
    wire [31:0] wr_data;
    wire rd_en;
    wire [$clog2(DEPTH)-1:0] rd_addr;
    reg [31:0] rd_data;
    reg [31:0] memory [0:DEPTH-1];
    integer sent = 0;
    integer received = 0;
    integer fetched = 0;
    integer limit = 0;
    integer write_mode = 0;
    integer read_mode = 0;
    bit accepted = 0;
    bit stalled = 0;
    reg [31:0] held_data;
    bit throughput = 0;
    integer streaming_end;

    always #(WRITE_HALF) write_clk = !write_clk;
    integer phase;
    initial begin
        phase = $urandom_range(1, 19);
        #(phase);
        forever #(READ_HALF) read_clk = !read_clk;
    end

    edrv32_async_fifo_ram #(
        .WIDTH(32),
        .DEPTH(DEPTH)
    ) u_dut (
        .clk_write_i(write_clk),
        .rst_write_n_i(rst_n),
        .clk_read_i(read_clk),
        .rst_read_n_i(rst_n),
        .valid_i(valid),
        .ready_o(ready),
        .data_i(data),
        .valid_o(out_valid),
        .ready_i(out_ready),
        .data_o(out_data),
        .wr_en_o(wr_en),
        .wr_addr_o(wr_addr),
        .wr_data_o(wr_data),
        .rd_en_o(rd_en),
        .rd_addr_o(rd_addr),
        .rd_data_i(rd_data)
    );

    // RAM payload and output deliberately have no reset or initialization.
    always @(posedge write_clk) begin
        if (wr_en) memory[wr_addr] <= wr_data;
    end
    always @(posedge read_clk) begin
        if (rd_en) rd_data <= memory[rd_addr];
    end

    always @(negedge write_clk) begin
        if (rst_n && (!valid || accepted)) begin
            valid = sent < limit && write_mode != 0 &&
                    (write_mode == 1 || $urandom_range(0, 3) != 0);
            data = 32'(sent);
        end
    end
    always @(negedge read_clk) begin
        out_ready = rst_n && read_mode != 0 &&
                    (read_mode == 1 || $urandom_range(0, 3) != 0);
    end
    always @(posedge write_clk) begin
        accepted = rst_n && valid && ready;
        if (!rst_n) sent = 0;
        else if (accepted) sent = sent + 1;
    end
    always @(posedge read_clk) begin
        if (!rst_n) begin
            received = 0;
            fetched = 0;
            stalled = 0;
        end else begin
            if (rd_en) begin
                if (wr_en && wr_addr == rd_addr &&
                    $time % (2 * WRITE_HALF) == WRITE_HALF)
                    $fatal(1, "FAIL case %0d RAM address collision at %0t", CASE_ID, $time);
                if (fetched >= sent)
                    $fatal(1, "FAIL case %0d read unwritten item at %0t", CASE_ID, $time);
                fetched = fetched + 1;
            end
            if (stalled && (!out_valid || out_data !== held_data))
                $fatal(1, "FAIL case %0d head changed while stalled at %0t", CASE_ID, $time);
            if (throughput && !out_valid)
                $fatal(1, "FAIL case %0d throughput bubble at %0t", CASE_ID, $time);
            stalled = out_valid && !out_ready;
            held_data = out_data;
            if (out_valid && out_ready) begin
                if (out_data !== 32'(received))
                    $fatal(1, "FAIL case %0d expected %0d actual %0d at %0t",
                           CASE_ID, received, out_data, $time);
                received = received + 1;
            end
        end
    end

    initial begin
        #1 rst_n = 0;
        repeat (5) @(negedge write_clk);
        rst_n = 1;
        // Empty reads, then exact capacity with output prefetch stalled.
        read_mode = 1;
        repeat (10) @(negedge read_clk);
        if (out_valid || !ready) $fatal(1, "FAIL reset/empty case %0d", CASE_ID);
        read_mode = 0;
        limit = DEPTH;
        write_mode = 1;
        wait (sent == DEPTH);
        repeat (10) @(negedge read_clk);
        if (ready || !out_valid) $fatal(1, "FAIL full case %0d", CASE_ID);
        // A producer held valid against full must not overwrite any queued item.
        limit = DEPTH + 1;
        repeat (10) @(negedge write_clk);
        if (sent != DEPTH) $fatal(1, "FAIL full accepted write case %0d", CASE_ID);
        // A full backlog must drain on consecutive read edges despite RAM latency.
        @(negedge read_clk);
        #1;
        read_mode = 1;
        wait (out_ready);
        throughput = 1;
        wait (received == DEPTH);
        #1 throughput = 0;
        wait (received == DEPTH + 1);
        repeat (10) @(negedge read_clk);
        if (out_valid) $fatal(1, "FAIL drain case %0d", CASE_ID);
        // Keep both sides continuously active across many RAM address wraps.
        // A slower producer is checked by the prefilled-burst throughput test above.
        if (DEPTH >= 16 && WRITE_HALF <= READ_HALF) begin
            read_mode = 0;
            limit = sent + DEPTH / 2;
            write_mode = 1;
            wait (sent == limit);
            repeat (10) @(negedge read_clk);
            limit = sent + 4096;
            streaming_end = received + 2048;
            read_mode = 1;
            wait (out_ready);
            throughput = 1;
            wait (received == streaming_end);
            #1 throughput = 0;
            wait (sent == limit);
            wait (received == limit);
            repeat (10) @(negedge read_clk);
        end
        // Long randomized valid/ready sequence spans many wraps and empty/full transitions.
        limit = sent + 12000;
        write_mode = 2;
        read_mode = 2;
        wait (sent == limit);
        write_mode = 0;
        read_mode = 1;
        wait (received == limit);
        repeat (10) @(negedge read_clk);
        if (out_valid) $fatal(1, "FAIL random drain case %0d", CASE_ID);
        // Reset with prefetched data, then write new traffic without resetting RAM.
        read_mode = 0;
        write_mode = 1;
        limit = limit + DEPTH;
        wait (sent == limit);
        repeat (10) @(negedge read_clk);
        #1 rst_n = 0;
        valid = 0;
        write_mode = 0;
        repeat (5) @(negedge write_clk);
        repeat (5) @(negedge read_clk);
        limit = DEPTH * 3;
        rst_n = 1;
        write_mode = 2;
        read_mode = 2;
        wait (sent == limit);
        write_mode = 0;
        read_mode = 1;
        wait (received == limit);
        repeat (10) @(negedge read_clk);
        if (out_valid || !ready) $fatal(1, "FAIL final empty case %0d", CASE_ID);
        $display("case %0d DEPTH=%0d half-periods=%0d/%0d passed",
                 CASE_ID, DEPTH, WRITE_HALF, READ_HALF);
        done = 1;
    end
endmodule

module tb;
    wire done_0;
    fifo_case #(.DEPTH(2), .WRITE_HALF(10), .READ_HALF(3), .CASE_ID(0))
        u_case_0 (.done(done_0));
    wire done_1;
    fifo_case #(.DEPTH(16), .WRITE_HALF(10), .READ_HALF(5), .CASE_ID(1))
        u_case_1 (.done(done_1));
    wire done_2;
    fifo_case #(.DEPTH(512), .WRITE_HALF(10), .READ_HALF(10), .CASE_ID(2))
        u_case_2 (.done(done_2));
    wire done_3;
    fifo_case #(.DEPTH(16), .WRITE_HALF(5), .READ_HALF(10), .CASE_ID(3))
        u_case_3 (.done(done_3));
    wire done_4;
    fifo_case #(.DEPTH(512), .WRITE_HALF(10), .READ_HALF(30), .CASE_ID(4))
        u_case_4 (.done(done_4));
    initial begin
        wait (done_0 && done_1 && done_2 && done_3 && done_4);
        $display("PASS");
        $finish;
    end
    initial begin
        #20000000;
        $fatal(1, "FAIL timeout at %0t", $time);
    end
endmodule
