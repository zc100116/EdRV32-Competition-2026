// File: tb.sv
// Spec: npu-testplan PP-02..07, PP-10, PP-P-01/02; npu-spec 5.6.
// Description: Stream labels, forwarding, all banks/tables, packed output and delayed B fence.
// Clock: clk_npu.
`timescale 1ns/1ps
module tb;
    bit clk = 0;
    always #2.5 clk = !clk;
    bit rst_n = 0;
    bit clear = 0;
    bit load = 0;
    logic [1:0] load_head = 0;
    logic [31:0] load_addr = 0;
    logic [31:0] box_offset = 0;
    logic [31:0] box_stride = 0;
    wire load_done;
    bit tail = 0;
    wire tail_done;
    wire writer_idle;
    wire [12:0] count;
    bit cls_valid = 0;
    logic [255:0] cls_data = 0;
    logic [1:0] cls_head = 0;
    logic [11:0] cls_row = 0;
    logic [10:0] cls_pair = 0;
    logic [2:0] cls_block = 0;
    bit cls_plane = 0;
    wire read_req;
    wire [31:0] read_addr;
    logic read_valid = 0;
    logic [255:0] read_data = 0;
    wire write_req;
    wire [31:0] write_addr;
    wire write_valid;
    wire [255:0] write_data;
    bit write_active = 0;
    int outstanding = 0;
    int b_delay = 0;
    int cycles = 0;
    int write_bytes = 0;
    int gather_beats = 0;
    int expected_count = 0;
    bit right_only = 0;
    byte unsigned actual [0:120991];
    byte unsigned expected [0:120991];
    int heads [0:5039];
    int cells [0:5039];
    wire memory_idle = !write_active && outstanding == 0;
    edrv32_npu_post dut (
        .clk_i(clk),
        .rst_n_i(rst_n),
        .clear_i(clear),
        .stop_i(1'b0),
        .cancel_i(1'b0),
        .int8_th_i({3{9'd103}}),
        .prob_th_i(32'd0),
        .post_base_i(32'h200000),
        .output_base_i(32'h10000),
        .load_i(load),
        .load_head_i(load_head),
        .load_addr_i(load_addr),
        .box_offset_i(box_offset),
        .box_stride_i(box_stride),
        .load_done_o(load_done),
        .tail_i(tail),
        .tail_done_o(tail_done),
        .writer_idle_o(writer_idle),
        .count_o(count),
        .cls_valid_i(cls_valid),
        .cls_data_i(cls_data),
        .cls_head_i(cls_head),
        .cls_row_i(cls_row),
        .cls_pair_i(cls_pair),
        .cls_block_i(cls_block),
        .cls_plane_i(cls_plane),
        .read_req_valid_o(read_req),
        .read_req_ready_i(1'b1),
        .read_req_addr_o(read_addr),
        .read_data_valid_i(read_valid),
        .read_data_i(read_data),
        .write_req_valid_o(write_req),
        .write_req_ready_i(!write_active),
        .write_req_addr_o(write_addr),
        .write_data_valid_o(write_valid),
        .write_data_ready_i(write_active),
        .write_data_o(write_data),
        .write_stream_idle_i(!write_active),
        .write_idle_i(memory_idle)
    );
    function automatic int width(input int head);
        return head == 0 ? 80 : head == 1 ? 40 : 20;
    endfunction
    function automatic int height(input int head);
        return head == 0 ? 48 : head == 1 ? 24 : 12;
    endfunction
    function automatic int base(input int head);
        return head == 0 ? 0 : head == 1 ? 3840 : 4800;
    endfunction
    always @(posedge clk) begin
        int h;
        int index;
        int c;
        int side;
        int addr;
        cycles <= cycles + 1;
        if (cycles > 4000000) $fatal(1, "FAIL timeout");
        read_valid <= read_req;
        if (read_req) begin
            read_data <= 0;
            if (read_addr < 'h3000) begin
                h = (int'(read_addr)-'h1000)/2048;
                index = (int'(read_addr)-'h1000)%2048/4;
                for (int w = 0; w < 8; w++) begin
                    if (index < 256)
                        read_data[32*w+:32] <= (index+w) == 0 ? 1048576
                            : (index+w) == 255 && h != 0 ? (h == 1 ? 524288 : 262144) : 0;
                    // spec 4.4: probability entry index is signed best+128.
                    else read_data[32*w+:32] <=
                        32'((((index+w-256)^128)+1)*100000+h*1000);
                end
            end else begin
                c = gather_beats/4;
                side = gather_beats%4;
                h = heads[c];
                addr = 'h10000 + h*'h40000 + side*width(h)*height(h)*16 + cells[c]*16;
                if (read_addr != 32'(addr & ~31))
                    $fatal(1, "FAIL gather candidate=%0d side=%0d want=%x got=%x",
                        c, side, addr & ~31, read_addr);
                read_data[255:128] <= {8'h7f, {15{8'h80}}};
                gather_beats <= gather_beats + 1;
            end
        end
        if (clear) begin
            write_bytes <= 0;
            gather_beats <= 0;
            outstanding <= 0;
            b_delay <= 0;
        end else begin
            case ({write_req && !write_active, outstanding != 0 && b_delay == 1})
                2'b10: outstanding <= outstanding + 1;
                2'b01: outstanding <= outstanding - 1;
                default: begin end
            endcase
            if (outstanding != 0)
                b_delay <= b_delay == 1 ? 40 : b_delay - 1;
            else b_delay <= 40;
        end
        if (write_req && !write_active) begin
            if (write_addr != 32'('h200000+write_bytes))
                $fatal(1, "FAIL output address expected=%x got=%x",
                    'h200000+write_bytes, write_addr);
            write_active <= 1;
        end
        if (write_valid && write_active) begin
            for (int b = 0; b < 32; b++) actual[write_bytes+b] <= write_data[8*b+:8];
            write_bytes <= write_bytes + 32;
            write_active <= 0;
        end
        if (tail_done && !memory_idle) $fatal(1, "FAIL DONE before last B time=%0t", $time);
    end
    task automatic tick;
        @(negedge clk);
    endtask
    task automatic expect_cell(input int head, input int row, input int x);
        logic [191:0] record_value;
        logic [15:0] anchor;
        int shift;
        int distance_value;
        anchor = 16'(base(head) + row*width(head) + x);
        shift = 3 + head;
        // Odd cells gather the high half: (15*w0 + 105*w255)*256/(w0+15*w255).
        distance_value = x%2 == 0 ? 1920 : head == 0 ? 3840 : head == 1 ? 2033 : 2223;
        record_value[31:0] = 32'((x*256+128-distance_value)*(1<<shift));
        record_value[63:32] = 32'((row*256+128-distance_value)*(1<<shift));
        record_value[95:64] = 32'((x*256+128+distance_value)*(1<<shift));
        record_value[127:96] = 32'((row*256+128+distance_value)*(1<<shift));
        record_value[159:128] = 32'((x%2 == 0 ? 104 : 105)*100000 + head*1000);
        record_value[175:160] = x%2 == 0 ? 16'd5 : 16'd79;
        record_value[191:176] = 16'(anchor);
        heads[expected_count] = head;
        cells[expected_count] = row*width(head)+x;
        for (int b = 0; b < 24; b++) expected[24*expected_count+b] = record_value[8*b+:8];
        expected_count++;
    endtask
    task automatic stream_pair(input int h, input int row, input int pair_index,
        input int accepted);
        for (int p = 0; p < 5; p++) begin
            cls_valid = 1;
            cls_head = 2'(h);
            cls_row = 12'(row);
            cls_pair = 11'(pair_index);
            cls_block = 3'(p/2);
            cls_plane = 1'(p%2);
            cls_data = {32{8'h80}};
            for (int pixel = 0; pixel < 2; pixel++) begin
                if (right_only ? pixel == 1 : pixel < accepted) begin
                    if (p == 0) cls_data[128*pixel+5*8+:8] = 103;
                    if (p == 1) cls_data[128*pixel+:8] = 103;
                    if (p == 4 && pixel == 1) cls_data[128+15*8+:8] = 104;
                end else cls_data[128*pixel+:8] = 101;
            end
            tick;
        end
        for (int pixel = 0; pixel < accepted; pixel++)
            expect_cell(h, row, pair_index*2+(right_only ? 1 : pixel));
    endtask
    task automatic run_frame(input int n);
        int start_cycles;
        int h;
        int row;
        int receive_start;
        expected_count = 0;
        right_only = n == 1;
        for (int b = 0; b < 120992; b++) begin
            expected[b] = 0;
            actual[b] = 'hda;
        end
        clear = 1;
        tick;
        clear = 0;
        for (int head = 0; head < 3; head++) begin
            load = 1;
            load_head = 2'(head);
            load_addr = 32'('h1000+head*2048);
            box_offset = 32'(head*'h40000);
            box_stride = 32'(width(head)*height(head)*16);
            tick;
            load = 0;
            while (!load_done) tick;
            tick;
        end
        receive_start = cycles;
        if (n == 5040) begin
            for (int head = 0; head < 3; head++)
                for (int y = 0; y < height(head); y++)
                    for (int pair_index = 0; pair_index < width(head)/2; pair_index++)
                        stream_pair(head, y, pair_index, 2);
        end else begin
            h = n <= 5 ? n%3 : 0;
            row = n <= 5 ? height(h)-1 : 1;
            for (int pair_index = 0; pair_index < (n+1)/2; pair_index++)
                stream_pair(h, row, pair_index, n-pair_index*2 >= 2 ? 2 : 1);
        end
        cls_valid = 0;
        if (n == 5040 && cycles-receive_start != 12600) $fatal(1, "FAIL II=1");
        start_cycles = cycles;
        tail = 1;
        tick;
        tail = 0;
        while (!tail_done) tick;
        if (int'(count) != n || expected_count != n || gather_beats != 4*n)
            $fatal(1, "FAIL count expected=%0d got=%0d gather=%0d", n, count, gather_beats);
        if (write_bytes != ((n*24+31)/32)*32)
            $fatal(1, "FAIL write size n=%0d got=%0d", n, write_bytes);
        for (int b = 0; b < write_bytes; b++)
            if (actual[b] !== expected[b])
                $fatal(1, "FAIL packed byte=%0d want=%x got=%x n=%0d time=%0t",
                    b, expected[b], actual[b], n, $time);
        $display("POST candidates=%0d tail_cycles=%0d recv_cycles=%0d gather=%0d writes=%0d",
            n, cycles-start_cycles, start_cycles-receive_start, gather_beats, write_bytes/32);
        tick;
    endtask
    initial begin
        repeat (3) tick;
        rst_n = 1;
        run_frame(0);
        for (int n = 1; n <= 5; n++) run_frame(n);
        run_frame(37);
        run_frame(5040);
        if (!writer_idle) $fatal(1, "FAIL writer busy at end");
        $display("PASS post tables, tie, labels, forwarding, II=1, pack, zero fill, B fence");
        $finish;
    end
endmodule
