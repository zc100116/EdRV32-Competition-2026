// File: tb.sv
// Spec: disp-spec 2.3, 2.4, 2.7, 4.3, 6.
// Description: Directed late-beat schedules verify whole-group black and debt alignment.
// Clock domain: test pixel clock.
module tb;
    reg clk = 0;
    always #5 clk = ~clk;
    reg rst_n = 0;
    reg enable = 0;
    reg de = 0;
    reg [10:0] x = 0;
    reg [9:0] y = 0;
    reg vblank = 0;
    reg fifo_valid = 0;
    wire fifo_ready;
    reg [255:0] fifo_data;
    wire [23:0] rgb;
    wire frame_req;
    wire underflow;
    wire [9:0] read_cnt;
    wire [31:0] perf0;
    wire [31:0] perf1;
    wire [31:0] perf2;
    int pops = 0;
    int events = 0;
    edrv32_disp_scan dut (
        .clk_i(clk), .rst_n_i(rst_n), .enable_i(enable), .de_i(de), .x_i(x), .y_i(y),
        .vblank_i(vblank), .params_valid_i(1'b0), .params_i(56'd0),
        .fifo1_valid_i(1'b0), .fifo1_ready_o(), .fifo1_data_i(256'd0),
        .underflow1_o(), .read1_cnt_o(), .perf5_o(), .perf6_o(),
        .fifo_valid_i(fifo_valid), .fifo_ready_o(fifo_ready),
        .fifo_data_i(fifo_data), .rgb_o(rgb), .frame_req_o(frame_req),
        .underflow_o(underflow), .read_cnt_o(read_cnt),
        .perf0_o(perf0), .perf1_o(perf1), .perf2_o(perf2)
    );
    function automatic [255:0] packet(input int id);
        for (int index = 0; index < 16; index++)
            packet[16*index +: 16] = 16'(id*37 + index*2049);
    endfunction
    function automatic [23:0] expand(input [15:0] pixel);
        return {pixel[15:11], pixel[15:13], pixel[10:5], pixel[10:9],
                pixel[4:0], pixel[4:2]};
    endfunction
    task automatic sample(input [23:0] expected_rgb, input bit expected_pop,
                          input bit expected_underflow = 0);
        #1;
        if (rgb !== expected_rgb || (fifo_valid && fifo_ready) !== expected_pop ||
            underflow !== expected_underflow)
            $fatal(1, "FAIL scan x=%0d rgb=%h expected=%h pop=%b/%b event=%b/%b",
                   x, rgb, expected_rgb, fifo_valid && fifo_ready, expected_pop,
                   underflow, expected_underflow);
        pops += int'(expected_pop);
        events += int'(expected_underflow);
        @(posedge clk);
        #1;
        if (read_cnt !== 10'(pops)) $fatal(1, "FAIL read counter");
    endtask
    task automatic boundary(input bit next_enable);
        @(negedge clk);
        de = 0;
        fifo_valid = 0;
        enable = next_enable;
        vblank = 1;
        #1;
        if (frame_req !== next_enable) $fatal(1, "FAIL request enable");
        sample(0, 0);
        @(negedge clk);
        vblank = 0;
    endtask
    task automatic group(input int id, input bit good,
                         input int first_id = -1, input int second_id = -1,
                         input int third_id = -1, input int late_id = -1,
                         input bit first_error = 0);
        bit available;
        int arriving;
        reg [255:0] expected_packet;
        expected_packet = packet(id);
        for (int pixel = 0; pixel < 16; pixel++) begin
            @(negedge clk);
            de = 1;
            x = 11'(pixel);
            y = 0;
            arriving = pixel == 0 ? first_id : pixel == 1 ? second_id :
                       pixel == 2 ? third_id : pixel == 5 ? late_id : -1;
            available = arriving >= 0;
            fifo_valid = available;
            fifo_data = packet(arriving);
            sample(good ? expand(expected_packet[16*pixel +: 16]) : 24'd0,
                   available, pixel == 0 && first_error);
        end
    endtask
    initial begin
        repeat (3) @(negedge clk);
        rst_n = 1;
        // An unscanned frame never consumes ordinary FIFO data or reports an error.
        fifo_valid = 1;
        fifo_data = packet(0);
        de = 1;
        sample(0, 0);
        boundary(1);
        group(0, 1, 0);
        group(1, 0, -1, -1, -1, -1, 1);
        // Old beat at a new group boundary both repays one debt and incurs another.
        group(2, 0, 1, 2);
        group(3, 1, 3);
        // Data arriving within an already black group is discarded, never displayed.
        group(4, 0, -1, -1, -1, 4);
        group(5, 1, 5);
        group(6, 0);
        group(7, 0);
        if (perf1 != 1 || perf2 != 5) $fatal(1, "FAIL first-frame underflow counts");
        boundary(1);
        group(8, 0, 6, 7, 8, -1, 1);
        group(9, 1, 9);
        // Last visible group verifies completion at the last active pixel.
        for (int pixel = 0; pixel < 16; pixel++) begin
            @(negedge clk);
            de = 1;
            x = 11'(1264+pixel);
            y = 719;
            fifo_valid = pixel == 0;
            fifo_data = packet(99);
            sample(expand(16'(99*37+pixel*2049)), pixel == 0);
        end
        if (perf0 != 1 || perf1 != 2 || perf2 != 6 || events != 2)
            $fatal(1, "FAIL completed-frame/per-frame error counts");
        group(10, 0);
        boundary(0);
        @(negedge clk);
        fifo_valid = 1;
        fifo_data = packet(10);
        sample(0, 1);
        @(negedge clk);
        de = 1;
        x = 0;
        fifo_data = packet(11);
        sample(0, 0);
        if (perf2 != 7 || perf1 != 2) $fatal(1, "FAIL disable created underflow");
        // Debt can also be repaid in blanking before the next group.
        boundary(1);
        group(11, 1, 11);
        $display("PASS scan: RGB565, 16-pixel black, simultaneous/cross-frame/disabled debt");
        $finish;
    end
endmodule
