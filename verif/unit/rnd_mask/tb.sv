// File: tb.sv
// Spec: rnd-spec v0.3 2.3/2.6 MASK_RECT, BLIT ROUND_CLIP, BOX_SHADOW CUTOUT.
// Description: Draw-unit memory and alpha contracts under deterministic backpressure;
//              scalar geometric coverage and over check every destination byte.
// Clock domain: clk_mem.
module tb;
    reg clk = 0;
    always #4 clk = ~clk;
    reg rst_n = 0;
    reg start = 0;
    reg cancel = 0;
    reg [511:0] command;
    reg [63:0] round_area;
    reg [1023:0] parameters;
    wire done;
    wire idle;
    wire [4:0] pixels;
    wire read_wait;
    wire write_wait;
    wire rd_valid;
    wire rd_ready;
    wire [31:0] rd_addr;
    wire [15:0] rd_bytes;
    reg rd_done = 0;
    reg rd_data_valid = 0;
    reg [255:0] rd_data;
    wire wr_valid;
    wire wr_ready;
    wire [31:0] wr_addr;
    wire [15:0] wr_bytes;
    wire wr_data_valid;
    wire wr_data_ready;
    wire [255:0] wr_data;
    wire [31:0] wr_strb;
    reg wr_done = 0;
    wire blend_valid;
    wire blend_ready;
    wire [63:0] blend_src;
    wire [63:0] blend_dst;
    wire [31:0] blend_tag;
    wire result_valid;
    wire [63:0] result_pixel;
    wire [31:0] result_tag;
    wire alpha_ready;
    wire gate = cycle % 7 != 0;
    reg [7:0] memory [0:65535];
    reg [7:0] expected [0:65535];
    integer cycle = 0;
    integer rd_left = 0;
    integer wr_left = 0;
    integer read_addr = 0;
    integer write_addr = 0;
    reg rd_end = 0;
    reg wr_end = 0;
    integer tested = 0;
    reg check_transparent_row = 0;
    assign rd_ready = rd_left == 0 && !rd_end && !rd_done && cycle % 3 != 0;
    assign wr_ready = wr_left == 0 && !wr_end && !wr_done && cycle % 5 != 0;
    assign wr_data_ready = wr_left != 0 && cycle % 4 != 0;
    assign blend_ready = alpha_ready && gate;
    wire [39:0] blend_offset;
    edrv32_rnd_draw u_draw (
        .clk_i(clk),
        .rst_n_i(rst_n),
        .start_i(start),
        .command_i(command),
        .source_stride_i({16'd0, command[303:288]}),
        .round_area_i(round_area),
        .parameters_i(parameters),
        .cancel_i(cancel),
        .idle_o(idle),
        .done_o(done),
        .pixel_count_o(pixels),
        .read_wait_o(read_wait),
        .write_wait_o(write_wait),
        .rd_valid_o(rd_valid),
        .rd_ready_i(rd_ready),
        .rd_addr_o(rd_addr),
        .rd_bytes_o(rd_bytes),
        .rd_done_i(rd_done),
        .rd_data_valid_i(rd_data_valid),
        .rd_data_i(rd_data),
        .wr_valid_o(wr_valid),
        .wr_ready_i(wr_ready),
        .wr_addr_o(wr_addr),
        .wr_bytes_o(wr_bytes),
        .wr_data_valid_o(wr_data_valid),
        .wr_data_ready_i(wr_data_ready),
        .wr_data_o(wr_data),
        .wr_strb_o(wr_strb),
        .wr_done_i(wr_done),
        .blend_valid_o(blend_valid),
        .blend_ready_i(blend_ready),
        .blend_src_o(blend_src),
        .blend_dst_o(blend_dst),
        .blend_tag_o(blend_tag),
        .blend_offset_i(blend_offset[19:0]),
        .blend_tag_i(result_tag),
        .blend_valid_i(result_valid),
        .blend_pixel_i(result_pixel)
    );
    edrv32_rnd_alpha_pipe u_alpha (
        .clk_i(clk),
        .rst_n_i(rst_n),
        .in_valid_i(blend_valid && gate),
        .in_ready_o(alpha_ready),
        .in_src_i(blend_src),
        .in_dst_i(blend_dst),
        .in_argb_i(command[8]),
        .in_mode_i(2'd0),
        .in_tag_i(blend_tag),
        .out_valid_o(result_valid),
        .out_ready_i(1'b1),
        .out_pixel_o(result_pixel),
        .out_offset_o(blend_offset),
        .out_tag_o(result_tag),
        .clear_i(cancel)
    );
    always @(posedge clk) begin
        cycle <= cycle + 1;
        rd_done <= rd_end;
        rd_end <= 0;
        wr_done <= wr_end;
        wr_end <= 0;
        rd_data_valid <= 0;
        if (rd_valid && rd_ready) begin
            read_addr <= int'(rd_addr);
            rd_left <= int'(rd_bytes) / 32;
        end
        if (rd_left != 0 && cycle % 3 != 1) begin
            for (int b = 0; b < 32; b++) rd_data[b*8 +: 8] <= memory[read_addr+b];
            rd_data_valid <= 1;
            read_addr <= read_addr + 32;
            rd_left <= rd_left - 1;
            if (rd_left == 1) rd_end <= 1;
        end
        if (wr_valid && wr_ready) begin
            if (check_transparent_row && wr_addr == 32'h1000)
                $fatal(1,"fully transparent affine row issued a write");
            write_addr <= int'(wr_addr);
            wr_left <= int'(wr_bytes) / 32;
        end
        if (wr_data_valid && wr_data_ready) begin
            for (int b = 0; b < 32; b++)
                if (wr_strb[b]) memory[write_addr+b] = wr_data[b*8 +: 8];
            write_addr <= write_addr + 32;
            wr_left <= wr_left - 1;
            if (wr_left == 1) wr_end <= 1;
        end
        if (cycle > 100000) $fatal(1, "timeout t=%0t", $time);
    end
    function automatic int div255(input int n);
        int t;
        t = n + 128;
        return (t + (t >> 8)) >> 8;
    endfunction
    function automatic int shape_cov(input int x, y, x0, y0, x1, y1, radius);
        int w, h, r, j, e, dy, root, room;
        if (x < x0 || x > x1 || y < y0 || y > y1) return 0;
        w = x1 - x0 + 1;
        h = y1 - y0 + 1;
        r = radius;
        if (r > w/2) r = w/2;
        if (r > h/2) r = h/2;
        j = y-y0 < y1-y ? y-y0 : y1-y;
        e = 0;
        if (r > 0 && j < r) begin
            dy = 16*(r-j)-8;
            root = 0;
            while ((root+1)*(root+1) <= 256*r*r-dy*dy) root++;
            e = 16*r-root;
        end
        room = 16*(x-x0)+16-e;
        if (room > 16*w-e-16*(x-x0)) room = 16*w-e-16*(x-x0);
        return room <= 0 ? 0 : room >= 16 ? 255 : 16*room;
    endfunction
    function automatic reg [31:0] over(input reg [23:0] rgb, input int sa,
                                        input reg [31:0] dest, input bit argb);
        int da, oa, ratio, sc, dc, color;
        reg [31:0] result;
        if (sa == 0) return dest;
        da = argb ? int'(dest[31:24]) : 255;
        oa = sa + div255((255-sa)*da);
        ratio = argb ? (sa*((255*65536+oa/2)/oa)+32768) >> 16 : sa;
        result = 32'(oa) << 24;
        for (int c = 0; c < 3; c++) begin
            sc = int'(rgb[c*8 +: 8]);
            if (argb) dc = int'(dest[c*8 +: 8]);
            else if (c == 1) dc = int'(dest[10:5]) * 4 + int'(dest[10:9]);
            else if (c == 2) dc = int'(dest[15:11]) * 8 + int'(dest[15:13]);
            else dc = int'(dest[4:0]) * 8 + int'(dest[4:2]);
            color = div255(ratio*sc+(255-ratio)*dc);
            result[c*8 +: 8] = 8'(color);
        end
        if (!argb) result = {16'd0, result[23:19], result[15:10], result[7:3]};
        return result;
    endfunction
    task automatic run_case(input int kind, radius, input bit keep, argb);
        reg [31:0] dest, value;
        int addr, cov, a, x0, y0, x1, y1, bpp, hits, sx, sy, channel;
        int width, height, target_stride, source_stride;
        reg [23:0] color;
        width = kind == 4 ? 41 : 19;
        height = kind == 4 ? 19 : 7;
        target_stride = kind == 4 ? 256 : 128;
        source_stride = kind == 4 ? 197 : 89;
        check_transparent_row = kind == 4;
        for (int i = 0; i < 65536; i++) memory[i] = 8'(i*17+29);
        command = 0;
        parameters = 0;
        command[7:0] = kind == 0 ? 8'h0c : kind == 1 ? 8'h04 :
            kind == 3 ? 8'h09 : kind == 4 ? 8'h0d : 8'h06;
        command[8] = argb;
        command[15:12] = kind == 1 || kind == 4 ? 4'd1 : 4'd2;
        command[23:16] = kind == 1 ? 8'h80 : {7'd0, keep};
        command[63:32] = 32'h1000;
        command[79:64] = 16'(target_stride);
        command[127:96] = 0;
        command[159:128] = {4'd0, 12'(height-1), 4'd0, 12'(width-1)};
        command[191:160] = 0;
        command[223:192] = {16'(height-1), 16'(width-1)};
        command[255:224] = 32'h7974aa31;
        x0 = -2; y0 = 1; x1 = 12; y1 = 5;
        round_area = {16'(y1), 16'(x1), 16'(y0), 16'(x0)};
        if (kind == 4) begin
            command[31:16] = keep ? 16'h81 : 16'h01;
            command[287:256] = 32'h4001;
            command[303:288] = 16'(source_stride);
            command[351:320] = {16'(height), 16'(width)};
            command[395:384] = 12'(radius);
            parameters[31:0] = 32768;
            parameters[63:32] = 32768;
            parameters[95:64] = 65536;
            parameters[191:160] = 65536;
            parameters[223:192] = round_area[31:0];
            parameters[255:224] = round_area[63:32];
            for (int py = 0; py < height; py++)
                for (int px = 0; px < width; px++) begin
                    addr = 'h4001+py*source_stride+px*4;
                    value = py == 0 ? 32'd0 : 32'h937fc12b;
                    for (int b = 0; b < 4; b++) memory[addr+b] = value[b*8 +: 8];
                end
        end else if (kind == 3) begin
            command[31:16] = keep ? 16'h004f : 16'h000e;
            parameters[31:0] = 32'(-65536);
            parameters[63:32] = 65536;
            parameters[127:96] = 32'(-65536);
            parameters[191:160] = 65536;
            parameters[223:192] = 13*65536;
            parameters[255:224] = 32'(-65536);
            parameters[287:256] = 32'(-65536);
            command[319:288] = 32'h80102030;
            command[351:320] = 7*65536;
            command[383:352] = 5*65536;
            command[415:384] = 32'(-3*65536);
            command[447:416] = 9*65536;
        end else if (kind == 0) begin
            command[267:256] = 12'(radius);
            command[319:288] = round_area[31:0];
            command[351:320] = round_area[63:32];
        end else begin
            command[287:256] = 32'h4001;
            command[303:288] = 16'd89;
            command[351:320] = 0;
            if (kind == 1) begin
                command[383:352] = 32'h10000;
                command[415:384] = 32'h10000;
                command[475:464] = 12'(radius);
            end else begin
                command[383:352] = round_area[31:0];
                command[415:384] = round_area[63:32];
                command[427:416] = 12'(radius);
            end
            for (int y = 0; y < height; y++)
                for (int x = 0; x < width; x++) begin
                    addr = 'h4001+y*89+x*(kind == 1 ? 4 : 1);
                    value = kind == 1 ? 32'h937fc12b : 32'h99;
                    for (int b = 0; b < (kind == 1 ? 4 : 1); b++)
                        memory[addr+b] = value[b*8 +: 8];
                end
        end
        if (argb)
            for (int y = 0; y < height; y++)
                for (int x = 0; x < width; x++)
                    case (x % 4)
                        0: memory['h1000+y*target_stride+x*4+3] = 0;
                        1: memory['h1000+y*target_stride+x*4+3] = 1;
                        2: memory['h1000+y*target_stride+x*4+3] = 128;
                        default: memory['h1000+y*target_stride+x*4+3] = 255;
                    endcase
        for (int i = 0; i < 65536; i++) expected[i] = memory[i];
        bpp = argb ? 4 : 2;
        for (int y = 0; y < height; y++)
            for (int x = 0; x < width; x++) begin
                addr = 'h1000+y*target_stride+x*bpp;
                dest = 0;
                for (int b = 0; b < bpp; b++) dest[b*8 +: 8] = memory[addr+b];
                cov = shape_cov(x, y, x0, y0, x1, y1, radius);
                if (kind == 0) begin
                    a = keep && (x < x0 || x > x1 || y < y0 || y > y1) ?
                        int'(dest[31:24]) : div255(int'(dest[31:24])*cov);
                    value = a == 0 ? 0 : {8'(a), dest[23:0]};
                end else if (kind == 1) begin
                    if (radius == 0) cov = 255;
                    a = div255(div255(121*147)*cov);
                    value = over(24'h7fc12b, a, dest, argb);
                end else if (kind == 4) begin
                    if (!keep || radius == 0) cov = 255;
                    a = y == 0 ? 0 : div255(div255(121*147)*cov);
                    value = over(24'h7fc12b, a, dest, argb);
                end else if (kind == 3) begin
                    hits = 0;
                    for (int j = 0; j < 4; j++)
                        for (int i = 0; i < 4; i++) begin
                            sx = 8*x+(keep ? 2*i+1 : 4);
                            sy = 8*y+(keep ? 2*j+1 : 4);
                            if (sx >= 8 && sy >= 8 && sx+sy <= 13*8) hits++;
                        end
                    cov = (255*hits+8)/16;
                    color = 24'h74aa31;
                    a = 255;
                    if (keep) begin
                        a = 128+7*x;
                        if (a > 255) a = 255;
                        for (int c = 0; c < 3; c++) begin
                            channel = c == 2 ? 16+5*x : c == 1 ? 32-3*x : 48+9*x;
                            if (channel < 0) channel = 0;
                            if (channel > 255) channel = 255;
                            color[c*8 +: 8] = 8'(channel);
                        end
                    end
                    a = div255(div255(121*a)*cov);
                    value = over(color, a, dest, argb);
                end else begin
                    a = keep ? div255(121*div255(153*(255-cov))) : div255(121*153);
                    value = over(24'h74aa31, a, dest, argb);
                end
                for (int b = 0; b < bpp; b++) expected[addr+b] = value[b*8 +: 8];
            end
        @(negedge clk); start = 1;
        @(negedge clk); start = 0;
        wait (done);
        @(negedge clk);
        for (int i = 0; i < 65536; i++)
            if (memory[i] !== expected[i])
                $fatal(1, "kind=%0d r=%0d keep=%0b argb=%0b addr=%h expected=%h actual=%h t=%0t",
                    kind, radius, keep, argb, i, expected[i], memory[i], $time);
        tested++;
    endtask
    initial begin
        repeat (4) @(negedge clk);
        rst_n = 1;
        run_case(0, 0, 0, 1);
        run_case(0, 1, 1, 1);
        run_case(0, 7, 0, 1);
        run_case(0, 7, 1, 1);
        run_case(1, 0, 0, 0);
        run_case(1, 3, 0, 0);
        run_case(1, 7, 0, 1);
        run_case(2, 2, 1, 0);
        run_case(2, 7, 1, 1);
        run_case(2, 0, 0, 1);
        run_case(3, 0, 0, 0);
        run_case(3, 0, 1, 1);
        run_case(4, 0, 0, 1);
        run_case(4, 3, 1, 1);
        run_case(4, 0, 0, 0);
        $display("PASS rnd_mask %0d cases", tested);
        $finish;
    end
endmodule
