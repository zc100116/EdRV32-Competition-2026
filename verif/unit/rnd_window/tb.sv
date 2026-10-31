// File: tb.sv
// Spec: rnd-spec v0.3 2.6 AFFINE_BLIT/5.2 source window.
// Description: Raw-byte source decoding checks all six formats, four-block taps,
//              arbitrary alignment, replacement conflicts and per-command invalidation.
// Clock domain: clk_mem.
module tb;
    reg clk = 0;
    always #4 clk = ~clk;
    reg rst_n = 0, clear = 0, start = 0;
    reg [511:0] command;
    reg in_valid = 0;
    wire in_ready;
    reg signed [31:0] x, y;
    reg [7:0] fx, fy;
    reg [31:0] dest, tag;
    reg [7:0] cov;
    wire out_valid;
    wire read_wait;
    reg out_ready = 1;
    wire [127:0] taps;
    wire [7:0] out_fx, out_fy;
    wire [31:0] out_dest, out_tag;
    wire [7:0] out_cov;
    wire rd_valid;
    wire rd_ready;
    wire [31:0] rd_addr;
    wire [15:0] rd_bytes;
    reg rd_data_valid = 0, rd_done = 0;
    reg [255:0] rd_data;
    wire pal_valid;
    wire [15:0] pal_index;
    reg [63:0] pal_data;
    reg [7:0] memory [0:65535];
    reg [215:0] expected [0:4095];
    int head = 0, tail = 0, cycles = 0, checked = 0;
    int read_left = 0, read_addr = 0, read_count = 0;
    reg read_end = 0;
    assign rd_ready = read_left == 0 && !read_end && !rd_done && cycles%3 != 0;
    edrv32_rnd_window u_window (
        .clk_i(clk), .rst_n_i(rst_n), .clear_i(clear), .start_i(start),
        .command_i(command), .in_valid_i(in_valid), .in_ready_o(in_ready),
        .x_i(x), .y_i(y), .fraction_x_i(fx), .fraction_y_i(fy),
        .destination_i(dest), .tag_i(tag), .coverage_i(cov),
        .out_valid_o(out_valid), .out_ready_i(out_ready), .taps_o(taps),
        .fraction_x_o(out_fx), .fraction_y_o(out_fy),
        .destination_o(out_dest), .tag_o(out_tag), .coverage_o(out_cov), .read_wait_o(read_wait),
        .rd_valid_o(rd_valid), .rd_ready_i(rd_ready), .rd_addr_o(rd_addr),
        .rd_bytes_o(rd_bytes), .rd_data_valid_i(rd_data_valid),
        .rd_data_i(rd_data), .rd_done_i(rd_done),
        .palette_valid_o(pal_valid), .palette_index_o(pal_index), .palette_data_i(pal_data)
    );
    function automatic reg [31:0] palette(input int index);
        return {8'(index*11),8'(index*13+7),8'(index*17+9),8'(index*19+3)};
    endfunction
    function automatic reg [31:0] source(input int sx, sy);
        int fmt, bpp, bit_offset, address, raw;
        reg [15:0] rgb;
        if (sx < 0 || sy < 0 || sx >= 65 || sy >= 49) return 0;
        fmt = int'(command[15:12]);
        bpp = fmt == 0 ? 16 : fmt == 1 ? 32 : fmt == 6 ? 8 :
            fmt == 7 ? 4 : fmt == 8 ? 2 : 1;
        bit_offset = sx*bpp;
        address = 'hff1+sy*277+bit_offset/8;
        raw = int'(memory[address]);
        if (bpp < 8) raw = (raw >> (8-bpp-bit_offset%8)) & ((1<<bpp)-1);
        if (fmt >= 6) return palette(raw);
        rgb = {memory[address+1],memory[address]};
        if (fmt == 0) return {command[18] && rgb == command[463:448] ? 8'd0 : 8'd255,
            rgb[15:11],rgb[15:13],rgb[10:5],rgb[10:9],rgb[4:0],rgb[4:2]};
        return {memory[address+3],memory[address+2],memory[address+1],memory[address]};
    endfunction
    always @(posedge clk) begin
        cycles <= cycles+1;
        rd_data_valid <= 0;
        rd_done <= read_end;
        read_end <= 0;
        if (rd_valid && rd_ready) begin
            if (rd_addr[4:0] != 0 || (rd_bytes != 32 && rd_bytes != 64))
                $fatal(1,"invalid fill descriptor");
            read_addr <= int'(rd_addr);
            read_left <= int'(rd_bytes)/32;
            read_count++;
        end
        if (read_left != 0 && cycles%4 != 0) begin
            for (int b = 0; b < 32; b++) rd_data[b*8 +: 8] <= memory[read_addr+b];
            rd_data_valid <= 1;
            read_addr <= read_addr+32;
            read_left <= read_left-1;
            if (read_left == 1) read_end <= 1;
        end
        if (pal_valid) pal_data <= {palette(int'(pal_index[15:8])),
            palette(int'(pal_index[7:0]))};
        if (in_valid && in_ready) begin
            expected[tail] = {cov,tag,dest,fy,fx,
                command[16] ? source(x+1,y+1) : 32'd0,
                command[16] ? source(x,y+1) : 32'd0,
                command[16] ? source(x+1,y) : 32'd0,source(x,y)};
            tail++;
        end
        if (out_valid && out_ready) begin
            if (head >= tail || {out_cov,out_tag,out_dest,out_fy,out_fx,taps} !== expected[head])
                $fatal(1,"window fmt=%0d sample=%0d expected=%h actual=%h t=%0t",
                    command[15:12],head,expected[head],
                    {out_cov,out_tag,out_dest,out_fy,out_fx,taps},$time);
            head++;
            checked++;
        end
        if (cycles > 500000) $fatal(1,"window timeout");
    end
    always @(negedge clk) out_ready = cycles%7 != 0;
    task automatic sample(input int px, py);
        @(negedge clk);
        in_valid = 1;
        x = px; y = py;
        fx = 8'(px*17); fy = 8'(py*19);
        tag = 32'(tail); dest = 32'(px*7919+py*1471); cov = 8'(px+py);
        @(posedge clk);
        while (!in_ready) @(posedge clk);
    endtask
    task automatic run_format(input int fmt, input bit bilinear);
        @(negedge clk);
        in_valid = 0;
        command = 0;
        command[7:0] = 13;
        command[15:12] = 4'(fmt);
        command[16] = bilinear;
        command[18] = 1;
        command[287:256] = 'hff1;
        command[303:288] = 277;
        command[351:320] = {16'd49,16'd65};
        command[463:448] = {memory['hff2],memory['hff1]};
        start = 1;
        @(negedge clk); start = 0;
        // Each cell can touch four source blocks; the scan exceeds 32 tags.
        for (int py = 7; py < 49; py += 8)
            for (int px = 7; px < 65; px += 8) sample(px,py);
        for (int i = 0; i < 48; i++) sample((i*17)%67-1,(i*11)%51-1);
        sample(0,0); sample(64,48); sample(-1,-1); sample(65,49);
        @(negedge clk); in_valid = 0;
        wait (head == tail);
        begin
            int before_reads;
            before_reads = read_count;
            sample(-8,-8);
            @(negedge clk); in_valid = 0;
            wait (head == tail);
            if (read_count != before_reads) $fatal(1,"out-of-source group fetched memory");
        end
    endtask
    initial begin
        for (int i = 0; i < 65536; i++) memory[i] = 8'(i*37+(i>>7)*11+3);
        repeat (4) @(negedge clk);
        rst_n = 1;
        run_format(0,1); run_format(1,1);
        run_format(6,1); run_format(7,1); run_format(8,1); run_format(9,1);
        run_format(1,0);
        // Rewrite source between commands: start must discard all decoded tags.
        memory['hff1] = 8'(~memory['hff1]);
        run_format(1,1);
        $display("PASS rnd_window %0d tap groups",checked);
        $finish;
    end
endmodule
