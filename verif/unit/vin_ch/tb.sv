// File: tb.sv
// Spec: vin 2.4--2.7, 4.3, 5.3, 6.
// Description: Surface byte oracle checks packing, ring slots, pipelined descriptors and drops.
// Clock domain: clk_mem.
module tb;
    bit clk = 0;
    always #4 clk = ~clk;
    bit rst_n = 0;
    bit source_valid = 0;
    wire source_ready;
    bit [31:0] source_data;
    bit source_sof;
    bit source_eol;
    bit source_eof;
    bit [31:0] source_frame_id;
    bit [10:0] source_width;
    bit [11:0] source_height;
    bit source_incomplete;
    wire pipe_valid;
    wire pipe_ready;
    wire [31:0] pipe_data;
    wire pipe_sof;
    wire pipe_eol;
    wire pipe_eof;
    bit enable = 1;
    bit en = 1;
    bit [1:0] src = 0;
    bit [2:0] ring_count = 3;
    bit [15:0] stride = 64;
    bit [127:0] bases = {32'h18000,32'h10000,32'h08000,32'h00000};
    bit [3:0] slot_busy = 0;
    bit abort_request = 0;
    wire [1:0] source_select;
    wire busy;
    wire urgent;
    wire [9:0] count;
    wire dma_abort;
    wire [2:0] wr_stat;
    wire [5:0] done_info;
    wire [31:0] done_frame_id;
    wire done;
    wire bus_error;
    wire overflow;
    wire skip;
    wire cfg_error;
    wire [1:0] cfg_errors;
    wire [31:0] ch_awaddr;
    wire [3:0] ch_awlen;
    wire ch_awvalid;
    wire [2:0] ch_awready;
    wire [255:0] ch_wdata;
    wire [31:0] ch_wstrb;
    wire ch_wlast;
    wire ch_wvalid;
    wire [2:0] ch_wready;
    wire [5:0] ch_bresp;
    wire [2:0] ch_bvalid;
    wire ch_bready;
    wire awid;
    wire [31:0] awaddr;
    wire [3:0] awlen;
    wire awvalid;
    bit awready;
    wire [255:0] wdata;
    wire [31:0] wstrb;
    wire wlast;
    wire wvalid;
    bit wready;
    bit bvalid;
    bit [1:0] bresp;
    wire bready;
    bit freeze_bus = 0;
    bit hold_b = 0;
    bit inject_error = 0;
    bit drop_mode = 0;
    int cycles;
    int done_count;
    int overflow_count;
    int skip_count;
    int cfg_count;
    int bus_errors;
    int pending_b;
    bit [7:0] memory [0:262143];
    typedef struct packed {int addr; int beats;} burst_t;
    burst_t aw_queue[$];
    int write_addr;
    int write_left;
    int total_aw;
    int total_w;
    edrv32_vin_ch u_dut (
        .clk_i(clk),
        .rst_n_i(rst_n),
        .source_valid_i(source_valid),
        .source_ready_o(source_ready),
        .source_data_i(source_data),
        .source_sof_i(source_sof),
        .source_eol_i(source_eol),
        .source_eof_i(source_eof),
        .source_frame_id_i(source_frame_id),
        .source_width_i(source_width),
        .source_height_i(source_height),
        .source_incomplete_i(source_incomplete),
        .frame_boundary_i({2'd0, source_valid && source_sof}),
        .pipe_valid_o(pipe_valid),
        .pipe_ready_i(pipe_ready),
        .pipe_data_o(pipe_data),
        .pipe_sof_o(pipe_sof),
        .pipe_eol_o(pipe_eol),
        .pipe_eof_o(pipe_eof),
        .result_valid_i(pipe_valid),
        .result_ready_o(pipe_ready),
        .result_data_i(pipe_data),
        .result_eol_i(pipe_eol),
        .result_eof_i(pipe_eof),
        .enable_i(enable),
        .en_i(en),
        .src_i(src),
        .ring_i(ring_count),
        .stride_i(stride),
        .bases_i(bases),
        .slot_busy_i(slot_busy),
        .abort_i(abort_request),
        .source_select_o(source_select),
        .busy_o(busy),
        .urgent_o(urgent),
        .count_o(count),
        .dma_abort_o(dma_abort),
        .wr_stat_o(wr_stat),
        .done_info_o(done_info),
        .done_frame_id_o(done_frame_id),
        .done_o(done),
        .bus_error_o(bus_error),
        .overflow_o(overflow),
        .skip_o(skip),
        .cfg_error_o(cfg_error),
        .cfg_errors_o(cfg_errors),
        .axi_awaddr_o(ch_awaddr),
        .axi_awlen_o(ch_awlen),
        .axi_awvalid_o(ch_awvalid),
        .axi_awready_i(ch_awready[0]),
        .axi_wdata_o(ch_wdata),
        .axi_wstrb_o(ch_wstrb),
        .axi_wlast_o(ch_wlast),
        .axi_wvalid_o(ch_wvalid),
        .axi_wready_i(ch_wready[0]),
        .axi_bresp_i(ch_bresp[1:0]),
        .axi_bvalid_i(ch_bvalid[0]),
        .axi_bready_o(ch_bready)
    );
    edrv32_vin_p1_arb u_arb (
        .clk_i(clk),
        .rst_n_i(rst_n),
        .ch_awaddr_i({64'd0, ch_awaddr}),
        .ch_awlen_i({8'd0, ch_awlen}),
        .ch_awvalid_i({2'd0, ch_awvalid}),
        .ch_awready_o(ch_awready),
        .ch_wdata_i({512'd0, ch_wdata}),
        .ch_wstrb_i({64'd0, ch_wstrb}),
        .ch_wlast_i({2'd0, ch_wlast}),
        .ch_wvalid_i({2'd0, ch_wvalid}),
        .ch_wready_o(ch_wready),
        .ch_bresp_o(ch_bresp),
        .ch_bvalid_o(ch_bvalid),
        .ch_bready_i({2'd0, ch_bready}),
        .ch_count_i({20'd0, count}),
        .ch_abort_i({2'd0, dma_abort}),
        .p1_awid_o(awid),
        .p1_awaddr_o(awaddr),
        .p1_awlen_o(awlen),
        .p1_awvalid_o(awvalid),
        .p1_awready_i(awready),
        .p1_wdata_o(wdata),
        .p1_wstrb_o(wstrb),
        .p1_wlast_o(wlast),
        .p1_wvalid_o(wvalid),
        .p1_wready_i(wready),
        .p1_bresp_i(bresp),
        .p1_bvalid_i(bvalid),
        .p1_bready_o(bready),
        .p1_bid_i(1'b0)
    );

    function automatic bit [31:0] pattern(input int fid, input int row, input int word_no);
        return (32'(fid) << 24) | (32'(row) << 12) | 32'(word_no);
    endfunction
    always @(negedge clk) begin
        cycles++;
        awready = !freeze_bus && cycles % 5 != 0;
        wready = !freeze_bus && cycles % 7 != 0;
        bvalid = !freeze_bus && !hold_b && pending_b != 0 && cycles % 3 != 0;
        bresp = inject_error ? 2'b10 : 2'b00;
    end
    always @(posedge clk) begin
        burst_t burst;
        if (rst_n) begin
            if (done) done_count++;
            if (overflow) overflow_count++;
            if (skip) skip_count++;
            if (cfg_error) cfg_count++;
            if (bus_error) bus_errors++;
            if (awvalid && awready) begin
                if (!dma_abort && count < {6'd0, awlen} + 10'd1)
                    $fatal(1, "FAIL incomplete burst admitted");
                burst.addr = int'(awaddr);
                burst.beats = int'(awlen) + 1;
                aw_queue.push_back(burst);
                total_aw++;
            end
            if (wvalid && wready) begin
                if (write_left == 0) begin
                    if (aw_queue.size() == 0) $fatal(1, "FAIL W before AW");
                    burst = aw_queue.pop_front();
                    write_addr = burst.addr;
                    write_left = burst.beats;
                end
                if (wlast !== (write_left == 1)) $fatal(1, "FAIL WLAST");
                if (write_addr < 0 || write_addr >= 262144)
                    $fatal(1, "FAIL address outside test memory %h", write_addr);
                for (int b = 0; b < 32; b++)
                    if (wstrb[b]) memory[write_addr+b] = wdata[b*8 +: 8];
                write_addr += 32;
                write_left--;
                total_w++;
                if (wlast) pending_b++;
            end
            if (bvalid && bready) pending_b--;
        end
    end
    task automatic send_frame(input int fid, input int w, input int h,
                              input bit incomplete = 0, input bit change_en = 0);
        for (int y = 0; y < h; y++) begin
            for (int x = 0; x < w/2; x++) begin
                @(negedge clk);
                source_valid = 1;
                source_data = pattern(fid, y, x);
                source_sof = x == 0 && y == 0;
                source_eol = x == w/2-1;
                source_eof = source_eol && y == h-1;
                source_frame_id = 32'(fid);
                source_width = 11'(w);
                source_height = 12'(h);
                source_incomplete = incomplete && source_eof;
                do @(posedge clk); while (!source_ready);
                if (change_en && x == 2 && y == 0) en = 0;
            end
        end
        @(negedge clk);
        source_valid = 0;
        source_sof = 0;
        source_eof = 0;
    endtask
    task automatic idle;
        do @(negedge clk); while (busy);
        repeat (3) @(negedge clk);
    endtask
    task automatic check_surface(input int base, input int fid, input int w, input int h,
                                 input int line_stride);
        bit [31:0] want;
        bit [31:0] got;
        for (int y = 0; y < h; y++) begin
            for (int x = 0; x < w/2; x++) begin
                want = pattern(fid, y, x);
                for (int b = 0; b < 4; b++)
                    got[b*8 +: 8] = memory[base+y*line_stride+x*4+b];
                if (got !== want)
                    $fatal(1, "FAIL surface base=%h row=%0d word=%0d want=%h got=%h",
                        base, y, x, want, got);
            end
            for (int b = w*2; b < ((w*2+31)/32)*32; b++)
                if (memory[base+y*line_stride+b] !== 8'h5a)
                    $fatal(1, "FAIL masked tail overwritten base=%h row=%0d byte=%0d", base,y,b);
        end
    endtask
    task automatic check_done(input int expected_count, input int slot, input int fid,
                              input bit bad = 0, input bit bus_bad = 0);
        idle();
        if (done_count != expected_count || done_info !== {bus_bad,bad,src,2'(slot)} ||
            done_frame_id !== 32'(fid))
            $fatal(1, "FAIL done count=%0d want=%0d info=%h slot=%0d id=%0d wantid=%0d",
                done_count,expected_count,done_info,slot,done_frame_id,fid);
    endtask
    initial begin
        for (int b = 0; b < 262144; b++) memory[b] = 8'h5a;
        repeat (4) @(negedge clk);
        rst_n = 1;
        send_frame(0,18,2);
        check_done(1,0,0);
        check_surface(0,0,18,2,64);
        slot_busy = 4'b0010;
        send_frame(1,18,2,1,1); // EN changes midway; current frame must finish.
        check_done(2,2,1,1);
        check_surface('h10000,1,18,2,64);
        en = 1;
        slot_busy = 4'b0111;
        send_frame(2,18,2);
        idle();
        if (done_count != 2 || skip_count != 1) $fatal(1, "FAIL all-busy skip");
        slot_busy = 0;
        ring_count = 2;
        send_frame(3,18,2);
        check_done(3,0,3);
        ring_count = 4;
        slot_busy = 4'b0010;
        send_frame(4,18,2);
        check_done(4,2,4);
        slot_busy = 0;
        hold_b = 1;
        send_frame(5,18,2);
        send_frame(6,18,2); // Pending descriptor while previous B is held.
        repeat (30) @(negedge clk);
        if (done_count != 4) $fatal(1, "FAIL completion before B");
        hold_b = 0;
        check_done(6,0,6);
        check_surface('h18000,5,18,2,64);
        check_surface(0,6,18,2,64);
        inject_error = 1;
        send_frame(7,18,2);
        check_done(7,1,7,0,1);
        if (bus_errors != 1) $fatal(1, "FAIL bus error reporting");
        inject_error = 0;
        freeze_bus = 1;
        stride = 2560;
        send_frame(8,1280,8);
        if (overflow_count != 1) $fatal(1, "FAIL overflow count=%0d", overflow_count);
        freeze_bus = 0;
        idle();
        if (done_count != 7 || count != 0 || pending_b != 0)
            $fatal(1, "FAIL overflow did not drain cleanly");
        stride = 64;
        send_frame(9,18,2);
        check_done(8,2,9); // Overflow restores allocation history.
        src = 2;
        freeze_bus = 1;
        stride = 2560;
        fork
            begin
                wait(count == 512);
                repeat (30) @(negedge clk);
                if (source_ready || urgent) $fatal(1, "FAIL memory backpressure/urgent");
                freeze_bus = 0;
            end
            send_frame(10,1280,8);
        join
        check_done(9,3,10);
        if (overflow_count != 1) $fatal(1, "FAIL memory frame overflowed");
        check_surface('h18000,10,1280,8,2560);
        ring_count = 1;
        send_frame(11,18,2);
        idle();
        if (cfg_count != 1 || done_count != 9) $fatal(1, "FAIL invalid ring config");
        ring_count = 3;
        freeze_bus = 1;
        stride = 64;
        send_frame(12,18,2);
        @(negedge clk);
        abort_request = 1;
        @(negedge clk);
        abort_request = 0;
        freeze_bus = 0;
        idle();
        if (done_count != 9 || count != 0 || pending_b != 0)
            $fatal(1, "FAIL ABORT completion or residual traffic");
        begin
            int last_slot = 3;
            int expected_count = 9;
            int fid = 13;
            for (int n = 2; n <= 4; n++) begin
                for (int mask = 0; mask < 16; mask++) begin
                    int selected = -1;
                    int candidate;
                    ring_count = 3'(n);
                    slot_busy = 4'(mask);
                    candidate = last_slot+1;
                    if (candidate >= n) candidate = 0;
                    for (int scan = 0; scan < n; scan++) begin
                        if (selected == -1 && (mask & (1 << candidate)) == 0)
                            selected = candidate;
                        candidate = (candidate+1)%n;
                    end
                    send_frame(fid,18,2);
                    if (selected == -1) begin
                        idle();
                        if (done_count != expected_count) $fatal(1,"FAIL busy-mask skip");
                    end else begin
                        expected_count++;
                        check_done(expected_count,selected,fid);
                        last_slot = selected;
                    end
                    fid++;
                end
            end
        end
        if (skip_count != 8) $fatal(1,"FAIL exhaustive slot skips=%0d",skip_count);
        begin
            int before_done = done_count;
            int before_overflow = overflow_count;
            int first_slot;
            int dropped_slot;
            first_slot = (int'(done_info[1:0])+1)%4;
            dropped_slot = (first_slot+1)%4;
            src = 0;
            ring_count = 4;
            slot_busy = 0;
            stride = 64;
            freeze_bus = 1;
            send_frame(80,32,256); // Exactly 512 beats, fills FIFO without overflow.
            // Put the next SOF immediately after the preceding EOF. The last
            // accepted beat must retain its FIFO credit while this frame drops.
            source_valid = 1;
            source_data = pattern(81,0,0);
            source_sof = 1;
            source_eol = 1;
            source_eof = 1;
            source_frame_id = 81;
            source_width = 2;
            source_height = 1;
            source_incomplete = 0;
            @(posedge clk);
            if (!source_ready) $fatal(1,"FAIL camera back-to-back SOF backpressured");
            @(negedge clk);
            source_valid = 0;
            source_sof = 0;
            source_eof = 0;
            if (count != 512 || overflow_count != before_overflow+1)
                $fatal(1,"FAIL exact-full back-to-back overflow count=%0d events=%0d",
                    count,overflow_count-before_overflow);
            freeze_bus = 0;
            check_done(before_done+1,first_slot,80);
            check_surface(int'(bases[first_slot*32 +: 32]),80,32,256,64);
            send_frame(82,18,2);
            check_done(before_done+2,dropped_slot,82);
        end
        $display("PASS vin_ch aw=%0d w=%0d",total_aw,total_w);
        $finish;
    end
    initial begin #10000000; $fatal(1, "FAIL timeout"); end
endmodule
