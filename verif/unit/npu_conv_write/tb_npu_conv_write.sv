// File: tb_npu_conv_write.sv
// Spec: npu-spec 3-6; edrv32-soc-spec 4.2, 7.1.
// Description: Self-checking isolated conv_write protocol and architectural tests.
// Clock: clk_npu.
`timescale 1ns/1ps
module tb_npu_conv_write;
    logic  clk_i = 0;
    logic  rst_n_i = 0;
    logic  stop_i = 0;
    logic  cancel_i = 0;
    logic start_i = 0;
    logic [3:0] cout_blocks_i = 2;
    logic result_chunk_last_i = 0;
    logic [31:0] out_addr_i = 0;
    logic [31:0] out_plane_stride_i = 0;
    logic [11:0] out_w_i = 0;
    logic  result_chunk_valid_i = 0;
    wire  result_chunk_ready_o;
    logic [4:0] result_chunk_base_i = 0;
    logic [4:0] result_chunk_pairs_i = 0;
    logic [2:0] result_chunk_block_i = 0;
    logic [10:0] result_chunk_pair_i = 0;
    logic  result_chunk_half_i = 0;
    wire  result_rd_en_o;
    wire [4:0] result_rd_index_o;
    wire  result_rd_plane_o;
    logic  result_rd_valid_i = 0;
    logic [255:0] result_rd_data_i = 0;
    wire  result_release_o;
    wire  write_req_valid_o;
    logic  write_req_ready_i = 0;
    wire [31:0] write_req_addr_o;
    wire [4:0] write_req_beats_o;
    wire  write_data_valid_o;
    logic  write_data_ready_i = 0;
    wire [255:0] write_data_o;
    logic  write_stream_idle_i = 0;
    wire  idle_o;
    always #5 clk_i = !clk_i;
    edrv32_npu_conv_write u_dut (
        .clk_i(clk_i),
        .rst_n_i(rst_n_i),
        .stop_i(stop_i),
        .cancel_i(cancel_i),
        .start_i(start_i),
        .cout_blocks_i(cout_blocks_i),
        .result_chunk_last_i(result_chunk_last_i),
        .out_addr_i(out_addr_i),
        .out_plane_stride_i(out_plane_stride_i),
        .out_w_i(out_w_i),
        .result_chunk_valid_i(result_chunk_valid_i),
        .result_chunk_ready_o(result_chunk_ready_o),
        .result_chunk_base_i(result_chunk_base_i),
        .result_chunk_pairs_i(result_chunk_pairs_i),
        .result_chunk_block_i(result_chunk_block_i),
        .result_chunk_pair_i(result_chunk_pair_i),
        .result_chunk_half_i(result_chunk_half_i),
        .result_rd_en_o(result_rd_en_o),
        .result_rd_index_o(result_rd_index_o),
        .result_rd_plane_o(result_rd_plane_o),
        .result_rd_valid_i(result_rd_valid_i),
        .result_rd_data_i(result_rd_data_i),
        .result_release_o(result_release_o),
        .write_req_valid_o(write_req_valid_o),
        .write_req_ready_i(write_req_ready_i),
        .write_req_addr_o(write_req_addr_o),
        .write_req_beats_o(write_req_beats_o),
        .write_data_valid_o(write_data_valid_o),
        .write_data_ready_i(write_data_ready_i),
        .write_data_o(write_data_o),
        .write_stream_idle_i(write_stream_idle_i),
        .idle_o(idle_o)
    );
    task automatic tick;
        @(posedge clk_i);
        @(negedge clk_i);
        #1;
    endtask
    task automatic check(input bit condition, input string label);
        if (!condition) $fatal(1, "FAIL %s time=%0t", label, $time);
    endtask
    initial begin
        #2000000;
        $fatal(1, "FAIL timeout");
    end
    typedef struct packed {
        logic [31:0] addr;
        logic [4:0] beats;
    } burst_t;
    burst_t expected_bursts[$];
    logic [255:0] expected_data[$];
    bit read_pending = 0;
    logic [4:0] read_index = 0;
    bit read_plane = 0;
    int outstanding = 0;
    int drain = 0;
    int cycle = 0;
    int releases = 0;
    int requests = 0;
    bit data_stalled = 0;
    logic [255:0] held_data;
    function automatic logic [255:0] pattern(input bit plane, input logic [4:0] index);
        return {8{32'(1000*int'(plane)+int'(index))}};
    endfunction
    always @(negedge clk_i) begin
        cycle++;
        write_req_ready_i = write_stream_idle_i && cycle % 3 != 0;
        write_data_ready_i = outstanding != 0 && cycle % 5 == 0;
    end
    always @(posedge clk_i) begin
        burst_t burst;
        logic [255:0] value;
        result_rd_valid_i <= read_pending;
        if (read_pending) result_rd_data_i <= pattern(read_plane, read_index);
        read_pending <= result_rd_en_o;
        if (result_rd_en_o) begin
            read_index <= result_rd_index_o;
            read_plane <= result_rd_plane_o;
        end
        if (rst_n_i) begin
            if (data_stalled) check(write_data_valid_o && write_data_o == held_data,
                "registered result data holds under W backpressure");
            data_stalled = write_data_valid_o && !write_data_ready_i;
            held_data = write_data_o;
            if (write_req_valid_o && write_req_ready_i) begin
                check(expected_bursts.size() != 0, "no unexpected burst");
                burst = expected_bursts.pop_front();
                if (write_req_addr_o != burst.addr || write_req_beats_o != burst.beats)
                    $fatal(1, "FAIL burst expected=%08x/%0d actual=%08x/%0d time=%0t",
                        burst.addr, burst.beats, write_req_addr_o, write_req_beats_o, $time);
                outstanding = int'(write_req_beats_o);
                write_stream_idle_i <= 0;
                requests++;
            end
            if (write_data_valid_o && write_data_ready_i) begin
                check(expected_data.size() != 0, "no duplicate result read");
                value = expected_data.pop_front();
                check(write_data_o == value, "RAM ring index and plane selection");
                outstanding--;
                if (outstanding == 0) drain = 3;
            end
            if (drain != 0) begin
                drain--;
                if (drain == 0) write_stream_idle_i <= 1;
            end
            if (result_release_o) begin
                check(expected_data.size() == 0 && expected_bursts.size() == 0,
                    "release after complete valid planes");
                releases++;
            end
        end
    end
    task automatic chunk(input int base, input int pairs, input int row,
                         input int block_number, input int pair_number, input bit half,
                         input bit abort_first);
        logic [31:0] address;
        int remaining;
        int length;
        burst_t burst;
        for (int plane = 0; plane < (half || abort_first ? 1 : 2); plane++) begin
            address = out_addr_i + 32'((2*block_number+plane))*out_plane_stride_i
                + 32'(row)*(32'(out_w_i)/2)*32 + 32'(pair_number)*32;
            remaining = pairs;
            while (remaining != 0) begin
                length = 16-int'(address[8:5]);
                if (length > remaining) length = remaining;
                burst = '{address, 5'(length)};
                expected_bursts.push_back(burst);
                remaining -= length;
                address += 32'(length*32);
            end
            for (int j = 0; j < pairs; j++) expected_data.push_back(pattern(1'(plane), 5'(base+j)));
        end
        result_chunk_valid_i = 1;
        result_chunk_base_i = 5'(base);
        result_chunk_pairs_i = 5'(pairs);
        result_chunk_block_i = 3'(block_number);
        result_chunk_pair_i = 11'(pair_number);
        result_chunk_half_i = half;
        result_chunk_last_i = pair_number+pairs == int'(out_w_i)/2;
        while (!result_chunk_ready_o) tick;
        tick;
        result_chunk_valid_i = 0;
        if (abort_first) begin
            while (write_stream_idle_i) tick;
            stop_i = 1;
        end
        while (!idle_o) tick;
        check(!result_release_o, "release is a pulse");
    endtask
    initial begin
        write_stream_idle_i = 1;
        tick;
        rst_n_i = 1;
        out_addr_i = 32'hfe0;
        out_plane_stride_i = 32'h3020;
        out_w_i = 40;
        start_i = 1;
        tick;
        start_i = 0;
        chunk(28, 16, 0, 0, 0, 0, 0);
        chunk(12, 4, 0, 0, 16, 0, 0);
        chunk(16, 7, 0, 1, 0, 1, 0);
        chunk(23, 13, 0, 1, 7, 1, 0);
        chunk(19, 4, 1, 0, 0, 0, 1);
        check(releases == 5 && requests >= 9, "normal and aborted chunk ownership");
        cancel_i = 1;
        tick;
        cancel_i = 0;
        stop_i = 0;
        out_addr_i = 32'h2000;
        cout_blocks_i = 1;
        start_i = 1;
        tick;
        start_i = 0;
        chunk(31, 2, 0, 0, 0, 1, 0);
        check(releases == 6 && idle_o, "restart after cancel");
        $display("PASS chunk write ring wrap, plane bursts, long W stalls and ABORT");
        $finish;
    end
endmodule
