// File: tb_post_stream.sv
// Spec: npu-testplan PP-P-02; npu-spec 5.6.
// Description: Drive the documented branch without gaps, then read every queued anchor.
// Clock domain: clk_npu at 200 MHz budget.
`timescale 1ns/1ps
module tb_post_stream;
    bit clk = 0;
    always #2.5 clk = !clk;
    bit rst_n = 0;
    bit clear = 0;
    bit load = 0;
    bit tail = 0;
    logic [1:0] load_head = 0;
    wire load_done;
    wire tail_done;
    wire unused_writer_idle;
    wire [12:0] count;
    bit valid = 0;
    logic [255:0] data_value = 0;
    logic [1:0] head = 0;
    logic [11:0] row = 0;
    logic [10:0] pair_value = 0;
    logic [2:0] block_value = 0;
    bit plane = 0;
    wire read_req;
    wire [31:0] read_addr;
    bit read_valid = 0;
    logic [255:0] read_data = 0;
    wire write_req;
    wire [31:0] write_addr;
    wire write_valid;
    wire [255:0] write_data;
    bit write_active = 0;
    int cycle = 0;
    int first_enqueue = -1;
    int written = 0;
    int stream_file;
    int output_file;
    string case_dir;
    edrv32_npu_post u_post (
        .clk_i(clk),
        .rst_n_i(rst_n),
        .clear_i(clear),
        .stop_i(1'b0),
        .cancel_i(1'b0),
        .int8_th_i({3{9'd103}}),
        .prob_th_i(32'd4194304),
        .post_base_i(32'h200000),
        .output_base_i(32'h10000),
        .load_i(load),
        .load_head_i(load_head),
        .load_addr_i(32'h1000 + 32'(load_head)*2048),
        .box_offset_i(32'd0),
        .box_stride_i(32'd61440),
        .load_done_o(load_done),
        .tail_i(tail),
        .tail_done_o(tail_done),
        .writer_idle_o(unused_writer_idle),
        .count_o(count),
        .cls_valid_i(valid),
        .cls_data_i(data_value),
        .cls_head_i(head),
        .cls_row_i(row),
        .cls_pair_i(pair_value),
        .cls_block_i(block_value),
        .cls_plane_i(plane),
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
        .write_idle_i(!write_active)
    );
    always @(posedge clk) begin
        cycle <= cycle + 1;
        if (cycle > 3000000) $fatal(1, "FAIL stream timeout");
        if (valid)
            $display("ACCEPT %0d %0d %0d %0d %0d %0d %064x", cycle,
                head, row, block_value, plane, pair_value, data_value);
        read_valid <= read_req;
        if (read_req) begin
            read_data <= 0;
            if (read_addr < 'h3000)
                for (int w = 0; w < 8; w++)
                    read_data[w*32+:32] <= read_addr[10] ? 16777216 : 1048576;
        end
        if (write_req && !write_active) begin
            if (write_addr != 32'('h200000+written))
                $fatal(1, "FAIL write address %x expected=%x", write_addr, 'h200000+written);
            write_active <= 1;
        end
        if (write_valid && write_active) begin
            $fdisplay(output_file, "%064x", write_data);
            written <= written + 32;
            write_active <= 0;
        end
    end
    always @(negedge clk) begin
        if (count != 0 && first_enqueue == -1) begin
            first_enqueue = cycle - 1;
            $display("FIRST_ENQUEUE %0d", first_enqueue);
        end
    end
    task automatic tick;
        @(negedge clk);
    endtask
    initial begin
        logic [1:0] h;
        logic [11:0] r;
        logic [2:0] b;
        int p;
        logic [10:0] pair_index;
        int left_anchor;
        int right_anchor;
        logic [255:0] value;
        int scanned;
        if (!$value$plusargs("CASE_DIR=%s", case_dir)) $fatal(1, "FAIL missing CASE_DIR");
        stream_file = $fopen({case_dir, "/stream.txt"}, "r");
        output_file = $fopen({case_dir, "/output.hex"}, "w");
        repeat (4) tick;
        rst_n = 1;
        clear = 1;
        tick;
        clear = 0;
        for (int n = 0; n < 3; n++) begin
            load_head = 2'(n);
            load = 1;
            tick;
            load = 0;
            while (!load_done) tick;
            tick;
        end
        for (int n = 0; n < 12600; n++) begin
            scanned = $fscanf(stream_file, "%d %d %d %d %d %d %d %h\n",
                h, r, b, p, pair_index, left_anchor, right_anchor, value);
            if (scanned != 8) $fatal(1, "FAIL stream row %0d", n);
            if (right_anchor != left_anchor + 1) $fatal(1, "FAIL stream anchor pair");
            head = 2'(h);
            row = 12'(r);
            block_value = 3'(b);
            plane = 1'(p%2);
            pair_value = 11'(pair_index);
            data_value = value;
            valid = 1;
            tick;
        end
        valid = 0;
        repeat (16) tick;
        if (count != 5040) $fatal(1, "FAIL count expected=5040 actual=%0d", count);
        tail = 1;
        tick;
        tail = 0;
        while (!tail_done) tick;
        if (written != 120960 || write_active)
            $fatal(1, "FAIL queue drain bytes=%0d active=%b", written, write_active);
        $fclose(output_file);
        $fclose(stream_file);
        $display("PASS POST stream: 12600 beats, 5040 queued records");
        $finish;
    end
endmodule
