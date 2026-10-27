// File: tb.sv
// Spec: disp-spec 2.4-2.6, 4.3.
// Description: Check every line descriptor, whole-line admission, count wrap and backlog.
// Clock domain: test memory clock.
module tb;
    reg clk = 0;
    always #5 clk = ~clk;
    reg rst_n = 0;
    reg frame_req = 0;
    reg soft_clear = 0;
    reg [31:0] next_base = 32'h1000;
    reg [31:0] stride = 32'd4096;
    reg [9:0] read_cnt = 0;
    reg write_data = 0;
    wire desc_valid;
    reg desc_ready = 0;
    wire [31:0] desc_base;
    wire [31:0] desc_stride;
    wire [15:0] desc_width;
    wire [11:0] desc_height;
    reg done = 0;
    wire frame_start;
    wire busy;
    wire urgent;
    wire delayed_req;
    wire [31:0] req_cnt;
    wire fifo_pending;
    int written = 0;
    int consumed = 0;
    int descriptors = 0;
    int starts = 0;
    int delayed = 0;
    edrv32_disp_reader dut (
        .clk_i(clk), .rst_n_i(rst_n), .frame_req_i(frame_req), .soft_clear_i(soft_clear),
        .next_base_i(next_base), .stride_i(stride), .read_cnt_i(read_cnt),
        .write_i(write_data), .desc_valid_o(desc_valid), .desc_ready_i(desc_ready),
        .desc_base_o(desc_base), .desc_stride_o(desc_stride),
        .desc_width_bytes_o(desc_width), .desc_height_o(desc_height), .done_i(done),
        .frame_start_o(frame_start), .busy_o(busy), .urgent_o(urgent),
        .delayed_req_o(delayed_req), .req_cnt_o(req_cnt), .fifo_pending_o(fifo_pending)
    );
    always @(posedge clk) begin
        if (rst_n) begin
            if (frame_start) starts++;
            if (delayed_req) delayed++;
            if (urgent !== (busy && written-consumed < 80)) begin
                // BUSY can additionally contain queued work for the single idle transition.
                if (!(frame_start && !urgent)) $fatal(1, "FAIL urgent threshold");
            end
            if (write_data) written++;
        end
    end
    task automatic tick;
        @(posedge clk);
        #1;
        @(negedge clk);
    endtask
    task automatic request;
        frame_req = 1;
        tick();
        frame_req = 0;
    endtask
    task automatic consume(input int total);
        consumed = total;
        read_cnt = 10'(total);
        #1;
    endtask
    task automatic line(input [31:0] base, input [31:0] line_stride,
                        input int row, input bit drain = 1);
        #1;
        if (!desc_valid || desc_base !== base + 32'(row)*line_stride ||
            desc_stride !== line_stride || desc_width !== 2560 || desc_height !== 1)
            $fatal(1, "FAIL descriptor row=%0d addr=%h expected=%h valid=%b", row,
                   desc_base, base + 32'(row)*line_stride, desc_valid);
        // A descriptor must remain stable until the DMA accepts it.
        repeat (2) tick();
        if (desc_base !== base + 32'(row)*line_stride)
            $fatal(1, "FAIL descriptor changed while stalled");
        desc_ready = 1;
        tick();
        desc_ready = 0;
        descriptors++;
        if (desc_valid) $fatal(1, "FAIL more than one line in flight");
        write_data = 1;
        repeat (80) tick();
        write_data = 0;
        if (drain) consume(written);
        done = 1;
        tick();
        done = 0;
    endtask
    initial begin
        repeat (3) @(negedge clk);
        rst_n = 1;
        if (busy || urgent || desc_valid) $fatal(1, "FAIL reset outputs");
        request();
        if (starts != 1 || req_cnt != 1 || !busy || !urgent)
            $fatal(1, "FAIL initial frame start");
        // Later software writes must not alter this frame's latched configuration.
        next_base = 32'h2000;
        stride = 32'd2560;
        for (int row = 0; row < 6; row++) line(32'h1000, 4096, row, 0);
        if (desc_valid || !fifo_pending) $fatal(1, "FAIL 480 occupied admission");
        consume(47);
        if (desc_valid) $fatal(1, "FAIL 79 free beats admitted a line");
        consume(48);
        if (!desc_valid) $fatal(1, "FAIL exactly 80 free beats not admitted");
        line(32'h1000, 4096, 6, 0);
        if (desc_valid || written-consumed != 512) $fatal(1, "FAIL full FIFO accounting");
        // Three blocked requests must all survive a long stalled first frame.
        request();
        request();
        request();
        if (starts != 1 || req_cnt != 4 || delayed != 3)
            $fatal(1, "FAIL pending request accounting");
        consume(written);
        if (fifo_pending) $fatal(1, "FAIL drained FIFO state");
        for (int row = 7; row < 720; row++) line(32'h1000, 4096, row);
        // Queue another request on the same edge an old queued request starts.
        if (!frame_start) $fatal(1, "FAIL pending frame did not start immediately");
        request();
        if (starts != 2 || req_cnt != 5) $fatal(1, "FAIL simultaneous enqueue/dequeue");
        for (int frame = 1; frame < 5; frame++) begin
            for (int row = 0; row < 720; row++) line(32'h2000, 2560, row);
            if (frame != 4) tick();
        end
        if (descriptors != 5*720 || starts != 5 || busy || urgent || fifo_pending)
            $fatal(1, "FAIL frame completion counts descriptors=%0d starts=%0d busy=%b",
                   descriptors, starts, busy);
        soft_clear = 1;
        tick();
        soft_clear = 0;
        if (req_cnt != 0 || busy || fifo_pending) $fatal(1, "FAIL local reset");
        // Write/read pointers survive local reset, including their modulo wraps.
        request();
        line(32'h2000, 2560, 0);
        $display("PASS reader: all 3600 descriptors, FIFO 79/80 threshold, backlog, wrap");
        $finish;
    end
endmodule
