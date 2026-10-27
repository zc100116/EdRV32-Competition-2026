// File: tb.sv
// Spec: vin 2.1, 8.1.
// Description: Check byte order, item boundaries, partial pixels and overflow recovery.
// Clock domain: independent camera and memory clocks.
module tb;
    bit clk_cam = 0;
    bit clk_mem = 0;
    int half_period = 7;
    always begin #(half_period) clk_cam = ~clk_cam; end
    always #4 clk_mem = ~clk_mem;
    bit rst_n = 0;
    bit vsync = 1;
    bit href = 0;
    bit [7:0] data;
    wire valid;
    bit ready = 1;
    wire [35:0] item;
    bit [35:0] expected[$];
    bit overflow_mode = 0;
    bit overflow_end = 0;
    int overflow_words;
    int overflow_starts;
    int overflow_ends;
    edrv32_vin_dvp u_dut (
        .clk_cam_i(clk_cam),
        .rst_cam_n_i(rst_n),
        .clk_mem_i(clk_mem),
        .rst_mem_n_i(rst_n),
        .vsync_i(vsync),
        .href_i(href),
        .data_i(data),
        .item_valid_o(valid),
        .item_ready_i(ready),
        .item_data_o(item)
    );
    always @(posedge clk_mem) begin
        bit [35:0] want;
        if (rst_n && valid && ready) begin
            if (overflow_mode) begin
                if (item[35:34] == 2) overflow_starts++;
                if (item[35:34] == 0) overflow_words++;
                if (item[35:34] == 3) begin
                    overflow_ends++;
                    if (!item[32]) $fatal(1, "FAIL overflow EOF lost flag, t=%0t", $time);
                    overflow_end = 1;
                end
            end else begin
                if (expected.size() == 0) $fatal(1, "FAIL unexpected item %h", item);
                want = expected.pop_front();
                if (item !== want)
                    $fatal(1, "FAIL item want=%h got=%h t=%0t", want, item, $time);
            end
        end
    end
    task automatic tick(input bit v, input bit h, input bit [7:0] d);
        @(negedge clk_cam);
        vsync = v;
        href = h;
        data = d;
    endtask
    task automatic pixel(input bit [15:0] p);
        tick(0, 1, p[15:8]);
        tick(0, 1, p[7:0]);
    endtask
    task automatic exact_frame;
        expected.push_back({2'd2, 34'd0});
        expected.push_back({2'd0, 1'b0, 1'b0, 32'habcd_1234});
        expected.push_back({2'd0, 1'b1, 1'b0, 32'h07e0_f800});
        expected.push_back({2'd1, 34'd0});
        expected.push_back({2'd3, 34'd0});
        tick(0, 0, 0);
        pixel(16'h1234);
        pixel(16'habcd);
        pixel(16'hf800);
        pixel(16'h07e0);
        tick(0, 1, 8'hff); // A half pixel is discarded, without disturbing full words.
        tick(0, 0, 0);
        tick(0, 1, 8'h11); // A line containing only a half pixel produces EOL.
        tick(0, 0, 0);
        tick(1, 0, 0);
        repeat (16) @(negedge clk_cam);
        if (expected.size() != 0) $fatal(1, "FAIL missing %0d items", expected.size());
    endtask
    initial begin
        repeat (5) @(negedge clk_mem);
        rst_n = 1;
        exact_frame();
        half_period = 3;
        exact_frame();
        half_period = 11;
        exact_frame();
        expected.push_back({2'd2, 34'd0});
        expected.push_back({2'd0, 1'b1, 1'b0, 32'h3333_2222});
        expected.push_back({2'd3, 1'b0, 1'b1, 32'd0});
        tick(0, 0, 0);
        pixel(16'h2222);
        pixel(16'h3333);
        pixel(16'h4444); // The odd complete pixel cannot form an output word.
        tick(0, 0, 0);
        tick(1, 0, 0);
        repeat (16) @(negedge clk_cam);
        if (expected.size() != 0) $fatal(1,"FAIL odd-line boundary missing");
        expected.push_back({2'd2, 34'd0});
        expected.push_back({2'd0, 1'b1, 1'b0, 32'habcd_1234});
        expected.push_back({2'd3, 34'd0});
        tick(0, 0, 0);
        pixel(16'h1234);
        pixel(16'habcd);
        tick(1, 0, 0); // Simultaneous line and frame end must serialize both items.
        repeat (16) @(negedge clk_cam);
        if (expected.size() != 0) $fatal(1,"FAIL coincident EOF boundary missing");
        overflow_mode = 1;
        ready = 0;
        tick(0, 0, 0);
        for (int p = 0; p < 100; p++) pixel(16'(p));
        tick(0, 0, 0);
        tick(1, 0, 0);
        repeat (8) @(negedge clk_cam);
        repeat (2) begin // Full FIFO spans later raw frames; old EOF must not be overwritten.
            tick(0,0,0);
            repeat (8) pixel(16'hffff);
            tick(0,0,0);
            tick(1,0,0);
        end
        ready = 1;
        wait (overflow_end);
        if (overflow_words >= 50) $fatal(1, "FAIL overflow failed to discard pixels");
        repeat (10) @(negedge clk_cam);
        if (overflow_starts != 1 || overflow_ends != 1)
            $fatal(1,"FAIL pending EOF frame ownership");
        overflow_mode = 0;
        exact_frame();
        ready = 0;
        expected.push_back({2'd2,34'd0});
        tick(0,0,0);
        for (int w = 0; w < 14; w++) begin
            expected.push_back({2'd0,w==13,1'b0,16'(2*w+1),16'(2*w)});
            pixel(16'(2*w));
            pixel(16'(2*w+1));
        end
        expected.push_back({2'd3,34'd0});
        tick(0,0,0);
        tick(1,0,0);
        repeat (8) @(negedge clk_cam);
        expected.push_back({2'd2,34'd0});
        expected.push_back({2'd3,1'b0,1'b1,32'd0});
        tick(0,0,0); // This SOF cannot enter the full FIFO yet.
        repeat (8) pixel(16'h1111);
        tick(0,0,0);
        tick(1,0,0);
        tick(0,0,0); // Another whole raw frame must be skipped.
        repeat (8) pixel(16'h2222);
        tick(0,0,0);
        tick(1,0,0);
        ready = 1;
        repeat (100) @(negedge clk_cam);
        if (expected.size() != 0) $fatal(1,"FAIL pending SOF/EOF serialization");
        exact_frame();
        $display("PASS vin_dvp");
        $finish;
    end
    initial begin #1000000; $fatal(1, "FAIL timeout"); end
endmodule
