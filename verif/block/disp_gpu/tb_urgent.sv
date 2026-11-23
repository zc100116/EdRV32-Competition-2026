// File: tb_urgent.sv
// Spec: gpu-soc-spec 8.2; disp-spec 2.4-2.6.
// Description: Exact X2/native urgent boundaries, frame latching and 40-beat admission.
// Clock domain: test memory clock.
module tb_urgent;
    reg clk = 0;
    always #5 clk = ~clk;
    reg rst_n = 0;
    reg frame_req = 0;
    reg soft_clear = 0;
    reg [31:0] next_base = 32'h1000;
    reg [31:0] stride = 4096;
    reg [31:0] scroll = 0;
    reg [2:0] layers = 1;
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
    edrv32_disp_reader_gpu dut (
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
        layers = 5;
        scroll = 32'h00030020;
        request();
        line(0, 32'h1000+3*4096+64, 4096, 40, 0);
        #1;
        if (urgent) $fatal(1, "FAIL ST-07 occupancy 40 must clear urgent");
        consume(0, 1);
        if (!urgent) $fatal(1, "FAIL ST-07 occupancy 39 must assert urgent");
        consume(0, 0);
        if (urgent) $fatal(1, "FAIL ST-07 occupancy 40 must clear urgent again");
        // Shadow mode changes cannot change the active frame's threshold/address.
        layers = 1;
        line(0, 32'h1000+3*4096+64, 4096, 40, 0);
        if (urgent) $fatal(1, "FAIL ST-07 occupancy 80 uses latched threshold 40");
        for (int row = 2; row < 12; row++)
            line(0, 32'h1000+32'(3+row/2)*4096+64, 4096, 40, 0);
        repeat (8) tick();
        if (desc_valid) $fatal(1, "FAIL ST-07 X2 admission with only 32 free beats");
        consume(0, 7);
        repeat (3) tick();
        if (desc_valid) $fatal(1, "FAIL ST-07 X2 admission with only 39 free beats");
        consume(0, 8);
        line(0, 32'h1000+9*4096+64, 4096, 40, 0);
        if (written[0]-consumed[0] != 512)
            $fatal(1, "FAIL ST-07 X2 40-beat reservation reaches exact FIFO capacity");
        consume(0, written[0]);
        for (int row = 13; row < 720; row++)
            line(0, 32'h1000+32'(3+row/2)*4096+64, 4096, 40);
        drained();
        request();
        line(0, 32'h1000+3*4096+64, 4096, 80, 0);
        if (!urgent) $fatal(1, "FAIL ST-07 next frame baseline threshold 81");
        line(0, 32'h1000+4*4096+64, 4096, 80, 0);
        consume(0, written[0]-81);
        if (urgent) $fatal(1, "FAIL ST-07 baseline occupancy 81 clears urgent");
        consume(0, written[0]-80);
        if (!urgent) $fatal(1, "FAIL ST-07 baseline occupancy 80 asserts urgent");
        consume(0, written[0]);
        for (int row = 2; row < 720; row++)
            line(0, 32'h1000+32'(3+row)*4096+64, 4096, 80);
        drained();
        $display("PASS ST-07 exact L0 urgent threshold: 39/40/80, frame latch, 720 rows");
        $finish;
    end
endmodule
