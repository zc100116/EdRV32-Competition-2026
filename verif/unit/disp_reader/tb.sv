// File: tb.sv
// Spec: disp-spec 2.4-2.6, 4.3.
// Description: Ordered two-layer descriptors, scrolling, per-layer admission and backlog.
// Clock domain: test memory clock.
module tb;
    reg clk = 0;
    always #5 clk = ~clk;
    reg rst_n = 0;
    reg frame_req = 0;
    reg soft_clear = 0;
    reg [31:0] next_base = 32'h1000;
    reg [31:0] stride = 4096;
    reg [31:0] scroll = 0;
    reg [1:0] layers = 1;
    reg [31:0] base1 = 32'h800000;
    reg [31:0] stride1 = 6144;
    reg [31:0] pos1 = 0;
    reg [31:0] size1 = 32'h02d00500;
    reg [9:0] read_cnt = 0;
    reg [9:0] read1_cnt = 0;
    reg write_data = 0;
    wire desc_valid;
    reg desc_ready = 0;
    wire [31:0] desc_base;
    wire [31:0] desc_stride;
    wire [15:0] desc_width;
    wire [11:0] desc_height;
    wire write_layer;
    reg done = 0;
    wire frame_start;
    wire busy;
    wire urgent;
    wire delayed_req;
    wire [31:0] req_cnt;
    wire fifo_pending;
    int written[2] = '{0, 0};
    int consumed[2] = '{0, 0};
    int descriptors = 0;
    int starts = 0;
    int delayed = 0;
    edrv32_disp_reader dut (
        .clk_i(clk), .rst_n_i(rst_n), .frame_req_i(frame_req), .soft_clear_i(soft_clear),
        .next_base_i(next_base), .stride_i(stride), .l0_scroll_i(scroll),
        .layer_ctrl_i(layers), .l1_next_base_i(base1), .l1_stride_i(stride1),
        .l1_pos_i(pos1), .l1_size_i(size1), .read_cnt_i(read_cnt),
        .read1_cnt_i(read1_cnt), .write_i(write_data), .write_layer_o(write_layer),
        .desc_valid_o(desc_valid), .desc_ready_i(desc_ready), .desc_base_o(desc_base),
        .desc_stride_o(desc_stride), .desc_width_bytes_o(desc_width),
        .desc_height_o(desc_height), .done_i(done), .frame_start_o(frame_start),
        .busy_o(busy), .urgent_o(urgent), .delayed_req_o(delayed_req),
        .req_cnt_o(req_cnt), .fifo_pending_o(fifo_pending)
    );
    always @(posedge clk) begin
        if (rst_n) begin
            if (frame_start) starts++;
            if (delayed_req) delayed++;
            if (write_data) written[int'(write_layer)]++;
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
    task automatic consume(input int layer, input int total);
        consumed[layer] = total;
        if (layer == 0) read_cnt = 10'(total);
        else read1_cnt = 10'(total);
        #1;
    endtask
    task automatic line(input bit layer, input [31:0] address,
                        input int line_stride, input int beats, input bit drain = 1);
        int cycles;
        cycles = 0;
        while (!desc_valid && cycles < 5000) begin tick(); cycles++; end
        if (!desc_valid || desc_base !== address || desc_stride !== 32'(line_stride) ||
            desc_width !== 16'(beats*32) || desc_height !== 1 || write_layer !== layer)
            $fatal(1, "FAIL descriptor %0d layer=%b/%b addr=%h/%h width=%0d/%0d valid=%b",
                   descriptors, write_layer, layer, desc_base, address, desc_width,
                   beats*32, desc_valid);
        repeat (3) begin
            tick();
            if (!desc_valid || desc_base !== address || write_layer !== layer)
                $fatal(1, "FAIL descriptor unstable under backpressure");
        end
        if (written[int'(layer)]-consumed[int'(layer)]+beats > 512)
            $fatal(1, "FAIL descriptor overflow reservation");
        desc_ready = 1;
        tick();
        desc_ready = 0;
        descriptors++;
        write_data = 1;
        repeat (beats) begin
            if (desc_valid || write_layer !== layer)
                $fatal(1, "FAIL next descriptor before previous DONE");
            tick();
        end
        write_data = 0;
        if (drain) consume(int'(layer), written[int'(layer)]);
        done = 1;
        tick();
        done = 0;
    endtask
    task automatic drained;
        repeat (8) tick();
        if (busy || urgent || fifo_pending || desc_valid) $fatal(1, "FAIL not drained");
    endtask
    initial begin
        repeat (3) @(negedge clk);
        rst_n = 1;
        if (busy || urgent || desc_valid) $fatal(1, "FAIL reset outputs");
        request();
        if (starts != 1 || req_cnt != 1 || !busy || !urgent)
            $fatal(1, "FAIL initial frame start");
        next_base = 32'h2000;
        stride = 2560;
        for (int row = 0; row < 6; row++) line(0, 32'h1000+32'(row)*4096, 4096, 80, 0);
        repeat (8) tick();
        if (desc_valid || !fifo_pending) $fatal(1, "FAIL 480 occupied admission");
        consume(0, 47);
        repeat (3) tick();
        if (desc_valid) $fatal(1, "FAIL 79 free admitted");
        consume(0, 48);
        line(0, 32'h1000+6*4096, 4096, 80, 0);
        if (written[0]-consumed[0] != 512) $fatal(1, "FAIL full FIFO accounting");
        request(); request(); request();
        if (starts != 1 || req_cnt != 4 || delayed != 3) $fatal(1, "FAIL backlog");
        consume(0, written[0]-81);
        if (urgent) $fatal(1, "FAIL L0 81 watermark urgent");
        consume(0, written[0]-80);
        if (!urgent) $fatal(1, "FAIL L0 80 watermark urgent");
        consume(0, written[0]);
        for (int row = 7; row < 720; row++) line(0, 32'h1000+32'(row)*4096, 4096, 80);
        request();
        for (int frame = 1; frame < 5; frame++)
            for (int row = 0; row < 720; row++) line(0, 32'h2000+32'(row)*2560, 2560, 80);
        drained();
        if (descriptors != 3600 || starts != 5 || req_cnt != 5)
            $fatal(1, "FAIL baseline descriptor/frame counts");
        // p=1..15, nonzero vertical scroll, L1 starts at Y and advances by STRIDE.
        layers = 3;
        for (int offset = 0; offset < 16; offset++) begin
            scroll = (3 << 16) | (32+32'(offset));
            pos1 = (2 << 16) | 8;
            size1 = (3 << 16) | (offset == 0 ? 1280 : 8);
            request();
            // Mutating shadow values after the latch cannot affect either layer.
            base1 = 32'h900000;
            for (int row = 0; row < 720; row++) begin
                line(0, 32'h2000+32'(row+3)*2560+64, 2560, offset == 0 ? 80 : 81);
                if (row >= 2 && row < 5)
                    line(1, (offset == 0 ? 32'h800000 : 32'h900000)+32'(row-2)*6144,
                         6144, offset == 0 ? 160 : 1);
            end
            drained();
        end
        // L1 admission is independent: 3 full rows occupy 480 beats.
        layers = 2;
        pos1 = 0;
        size1 = 32'h02d00500;
        request();
        for (int row = 0; row < 3; row++) line(1, base1+32'(row)*6144, 6144, 160, 0);
        repeat (8) tick();
        if (desc_valid || urgent) $fatal(1, "FAIL L1 full admission/urgent");
        consume(1, written[1]-480+127);
        repeat (3) tick();
        if (desc_valid) $fatal(1, "FAIL L1 159 free admitted");
        consume(1, written[1]-480+128);
        line(1, base1+3*6144, 6144, 160, 0);
        consume(1, written[1]-159);
        #1;
        if (!urgent) $fatal(1, "FAIL L1 159 watermark urgent");
        consume(1, written[1]-160);
        #1;
        if (urgent) $fatal(1, "FAIL L1 160 watermark urgent");
        consume(1, written[1]);
        for (int row = 4; row < 720; row++) line(1, base1+32'(row)*6144, 6144, 160);
        drained();
        layers = 0;
        request();
        repeat (3000) begin
            if (desc_valid || urgent) $fatal(1, "FAIL disabled layer generated traffic");
            tick();
        end
        drained();
        soft_clear = 1;
        tick();
        soft_clear = 0;
        if (req_cnt != 0 || fifo_pending) $fatal(1, "FAIL local reset");
        layers = 1;
        scroll = 0;
        request();
        line(0, next_base, 2560, 80);
        $display("PASS reader: descriptors, scroll p=0..15, L1 Y/stride, admission, backlog");
        $finish;
    end
endmodule
