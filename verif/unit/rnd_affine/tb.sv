// File: tb.sv
// Spec: rnd-spec v0.3 2.6 AFFINE_BLIT/5.2 traversal and sampling.
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
    reg [31:0] dest, tag;
    reg [7:0] cov;
    wire out_valid;
    wire read_wait;
    reg out_ready = 1;
    wire [31:0] pixel;
    reg [1023:0] parameters;
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
    reg [103:0] expected [0:4095];
    int head = 0, tail = 0, cycles = 0, checked = 0;
    int read_left = 0, read_addr = 0, read_count = 0;
    reg read_end = 0;
    assign rd_ready = read_left == 0 && !read_end && !rd_done && cycles%3 != 0;
    edrv32_rnd_affine u_affine (
        .clk_i(clk), .rst_n_i(rst_n), .clear_i(clear), .start_i(start),
        .command_i(command), .parameters_i(parameters),
        .left_i(12'd1), .top_i(12'd2), .right_i(12'd66), .bottom_i(12'd33),
        .in_valid_i(in_valid), .in_ready_o(in_ready),
        .destination_i(dest), .tag_i(tag), .coverage_i(cov),
        .out_valid_o(out_valid), .out_ready_i(out_ready), .pixel_o(pixel),
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
    function automatic int d(input int n);
        int t;
        t = n+128;
        return (t+(t>>8))>>8;
    endfunction
    function automatic reg [31:0] reference_pixel(input reg [127:0] values,
                                                 input int x, y);
        longint weights [0:3];
        longint sum, a, p, q, value;
        reg [31:0] result;
        weights[0] = (256-longint'(x))*(256-longint'(y));
        weights[1] = longint'(x)*(256-longint'(y));
        weights[2] = (256-longint'(x))*longint'(y);
        weights[3] = longint'(x)*longint'(y);
        sum = 0;
        for (int t = 0; t < 4; t++) sum += weights[t]*longint'(values[t*32+24 +: 8]);
        a = (sum+32768)/65536;
        if (a == 0) return 0;
        q = (255*65536+a/2)/a;
        result = 32'(a)<<24;
        for (int c = 0; c < 3; c++) begin
            sum = 0;
            for (int t = 0; t < 4; t++)
                sum += weights[t]*longint'(d(int'(values[t*32+24 +: 8])*
                    int'(values[t*32+c*8 +: 8])));
            p = (sum+32768)/65536;
            value = (p*q+32768)/65536;
            if (value > 255) value = 255;
            result[c*8 +: 8] = 8'(value);
        end
        return result;
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
            longint u, v, su, sv;
            reg [127:0] sampled;
            u = longint'($signed(parameters[31:0])) + (longint'(x)+3)*
                longint'($signed(parameters[95:64])) + (longint'(y)+2)*
                longint'($signed(parameters[159:128]));
            v = longint'($signed(parameters[63:32])) + (longint'(x)+3)*
                longint'($signed(parameters[127:96])) + (longint'(y)+2)*
                longint'($signed(parameters[191:160]));
            su = u-32768;
            sv = v-32768;
            sampled = {source(int'(su>>>16)+1,int'(sv>>>16)+1),
                source(int'(su>>>16),int'(sv>>>16)+1),
                source(int'(su>>>16)+1,int'(sv>>>16)),source(int'(su>>>16),int'(sv>>>16))};
            expected[tail] = {cov,tag,dest,command[16] ? reference_pixel(sampled,
                int'((su & 65535)>>8),int'((sv & 65535)>>8)) : source(int'(u>>>16),int'(v>>>16))};
            tail++;
        end
        if (out_valid && out_ready) begin
            if (head >= tail || {out_cov,out_tag,out_dest,pixel} !== expected[head])
                $fatal(1,"window fmt=%0d sample=%0d expected=%h actual=%h t=%0t",
                    command[15:12],head,expected[head],
                    {out_cov,out_tag,out_dest,pixel},$time);
            head++;
            checked++;
        end
        if (cycles > 2000000) $fatal(1,"window timeout");
    end
    always @(negedge clk) out_ready = cycles%7 != 0;
    task automatic sample(input int px, py);
        @(negedge clk);
        in_valid = 1;
        x = px; y = py;
        tag = 32'(tail); dest = 32'(px*7919+py*1471); cov = 8'(px+py);
        @(posedge clk);
        while (!in_ready) @(posedge clk);
    endtask
    task automatic run_mapping(input int mapping, input bit bilinear);
        @(negedge clk);
        in_valid = 0;
        head = 0; tail = 0;
        command = 0;
        parameters = 0;
        command[7:0] = 13;
        command[15:12] = 1;
        command[16] = bilinear;
        command[287:256] = 'hff1;
        command[303:288] = 277;
        command[351:320] = {16'd49,16'd65};
        command[191:160] = {16'(-2),16'(-3)};
        parameters[31:0] = 32'(-3*65536+32768);
        parameters[63:32] = 32'(-2*65536+32768);
        parameters[95:64] = 65536;
        parameters[191:160] = 65536;
        if (mapping == 1) begin
            parameters[31:0] = 41*65536+49152;
            parameters[63:32] = 32'(-2*65536+16384);
            parameters[95:64] = 0;
            parameters[127:96] = 65536;
            parameters[159:128] = 32'(-65536);
            parameters[191:160] = 0;
        end else if (mapping == 2) begin
            parameters[31:0] = 64*65536+32768;
            parameters[95:64] = 32'(-81920);
            parameters[159:128] = 16384;
            parameters[191:160] = 98304;
        end else if (mapping == 3) begin
            parameters[31:0] = 32768;
            parameters[95:64] = 32'h7fffffff;
        end
        start = 1;
        @(negedge clk); start = 0;
        for (int by = -2; by <= 33; by += 16)
            for (int bx = -3; bx <= 66; bx += 32)
                for (int py = by; py < by+16 && py <= 33; py++)
                    for (int px = bx; px < bx+32 && px <= 66; px++)
                        if (px >= 1 && py >= 2) sample(px,py);
        @(negedge clk); in_valid = 0;
        wait (head == tail);
        repeat (3) @(negedge clk);
    endtask
    initial begin
        for (int i = 0; i < 65536; i++) memory[i] = 8'(i*37+(i>>7)*11+3);
        repeat (4) @(negedge clk);
        rst_n = 1;
        run_mapping(0,0); run_mapping(0,1);
        run_mapping(1,0); run_mapping(1,1);
        run_mapping(2,1); run_mapping(3,0);
        $display("PASS rnd_affine %0d pixels",checked);
        $finish;
    end
endmodule
