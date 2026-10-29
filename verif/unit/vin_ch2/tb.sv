// File: tb.sv
// Spec: vin 2.6--2.9, 4.3, 5, 6.
// Description: Independent RGB565/average/formula oracle checks every surface byte.
//              Cover all 256 channel averages, padding edges, drops, rings and abort.
// Clock domain: clk_mem.
module tb;
    bit clk = 0;
    always #4 clk = ~clk;
    bit rst_n = 0;
    bit valid = 0;
    wire ready;
    bit [31:0] data = 0;
    bit sof = 0;
    bit eol = 0;
    bit eof = 0;
    bit [31:0] frame_id = 0;
    bit [10:0] width = 1280;
    bit [11:0] height = 720;
    bit incomplete = 0;
    bit [2:0] boundaries = 0;
    bit en = 1;
    bit [1:0] source = 2;
    bit [2:0] ring_size = 3;
    bit [3:0] slots_busy = 0;
    bit abort_request = 0;
    wire [1:0] selected;
    wire busy;
    wire [9:0] count;
    wire dma_abort;
    wire [2:0] wr_stat;
    wire [5:0] done_info;
    wire [31:0] done_id;
    wire done;
    wire bus_error;
    wire overflow;
    wire skip;
    wire cfg_error;
    wire [1:0] cfg_errors;
    wire [31:0] ch_addr;
    wire [3:0] ch_len;
    wire ch_valid;
    wire [2:0] ch_ready;
    wire [255:0] ch_data;
    wire [31:0] ch_strb;
    wire ch_last;
    wire ch_wvalid;
    wire [2:0] ch_wready;
    wire [5:0] ch_resp;
    wire [2:0] ch_bvalid;
    wire ch_bready;
    wire id;
    wire [31:0] addr;
    wire [3:0] len;
    wire awvalid;
    wire [255:0] wdata;
    wire [31:0] strb;
    wire last;
    wire wvalid;
    wire bready;
    bit awready = 0;
    bit wready = 0;
    bit bvalid = 0;
    bit [1:0] bresp = 0;
    bit stalled = 0;
    bit inject_error = 0;
    bit checking = 0;
    int cycle = 0;
    int pattern_frame = 0;
    int expected_slot = 0;
    int expected_src = 2;
    bit expected_incomplete = 0;
    int observed_bytes = 0;
    int completions = 0;
    int overflows = 0;
    int skips = 0;
    int configs = 0;
    int responses = 0;
    int write_left = 0;
    int write_address = 0;
    int readback_base = 0;
    int quartets[256][4];
    int pair_a[511];
    int pair_b[511];
    bit pair_valid[511];
    bit average_seen[256];
    int source_words = 0;
    int sof_cycle;
    int eof_cycle;
    int first_write_cycle;
    int last_write_cycle;
    int output_beats = 0;
    bit [255:0] stalled_data;
    bit [31:0] stalled_strb;
    bit stalled_last;
    bit write_held = 0;

    edrv32_vin_ch2 u_dut (
        .clk_i(clk),
        .rst_n_i(rst_n),
        .source_valid_i(valid),
        .source_ready_o(ready),
        .source_data_i(data),
        .source_sof_i(sof),
        .source_eol_i(eol),
        .source_eof_i(eof),
        .source_frame_id_i(frame_id),
        .source_width_i(width),
        .source_height_i(height),
        .source_incomplete_i(incomplete),
        .frame_boundary_i(boundaries),
        .axi_awaddr_o(ch_addr),
        .axi_awlen_o(ch_len),
        .axi_awvalid_o(ch_valid),
        .axi_awready_i(ch_ready[2]),
        .axi_wdata_o(ch_data),
        .axi_wstrb_o(ch_strb),
        .axi_wlast_o(ch_last),
        .axi_wvalid_o(ch_wvalid),
        .axi_wready_i(ch_wready[2]),
        .axi_bresp_i(ch_resp[5:4]),
        .axi_bvalid_i(ch_bvalid[2]),
        .axi_bready_o(ch_bready),
        .enable_i(1'b1),
        .en_i(en),
        .src_i(source),
        .ring_i(ring_size),
        .stride_i(16'd2624),
        .bases_i(128'h00400000_00300000_00200000_00100000),
        .slot_busy_i(slots_busy),
        .abort_i(abort_request),
        .source_select_o(selected),
        .busy_o(busy),
        .count_o(count),
        .dma_abort_o(dma_abort),
        .wr_stat_o(wr_stat),
        .done_info_o(done_info),
        .done_frame_id_o(done_id),
        .done_o(done),
        .bus_error_o(bus_error),
        .overflow_o(overflow),
        .skip_o(skip),
        .cfg_error_o(cfg_error),
        .cfg_errors_o(cfg_errors)
    );
    edrv32_vin_p1_arb u_arb (
        .clk_i(clk),
        .rst_n_i(rst_n),
        .ch_awaddr_i({ch_addr, 64'd0}),
        .ch_awlen_i({ch_len, 8'd0}),
        .ch_awvalid_i({ch_valid, 2'd0}),
        .ch_awready_o(ch_ready),
        .ch_wdata_i({ch_data, 512'd0}),
        .ch_wstrb_i({ch_strb, 64'd0}),
        .ch_wlast_i({ch_last, 2'd0}),
        .ch_wvalid_i({ch_wvalid, 2'd0}),
        .ch_wready_o(ch_wready),
        .ch_bresp_o(ch_resp),
        .ch_bvalid_o(ch_bvalid),
        .ch_bready_i({ch_bready, 2'd0}),
        .ch_count_i({count, 20'd0}),
        .ch_abort_i({dma_abort, 2'd0}),
        .p1_awid_o(id),
        .p1_awaddr_o(addr),
        .p1_awlen_o(len),
        .p1_awvalid_o(awvalid),
        .p1_awready_i(awready),
        .p1_wdata_o(wdata),
        .p1_wstrb_o(strb),
        .p1_wlast_o(last),
        .p1_wvalid_o(wvalid),
        .p1_wready_i(wready),
        .p1_bid_i(1'b0),
        .p1_bresp_i(bresp),
        .p1_bvalid_i(bvalid),
        .p1_bready_o(bready)
    );

    function automatic int expand(input int value, input int bits);
        return (value * 256 / (1 << bits)) | (value >> (2 * bits - 8));
    endfunction
    function automatic bit [15:0] pixel(input int f, input int x, input int y);
        int block_x = x / 2;
        int q = (y % 2) * 2 + x % 2;
        int red = (block_x * 7 + y * 11 + f * 13 + q) % 32;
        int green = quartets[(block_x + f * 73) % 256][q];
        int blue = (x * 19 + y * 3 + f * 17) % 32;
        if (block_x == 0) return 16'h0000;
        if (block_x == 1) return 16'hffff;
        return {5'(red), 6'(green), 5'(blue)};
    endfunction
    function automatic int expected_byte(input int f, input int x, input int y,
                                          input int component);
        int sum = 0;
        int c;
        bit [15:0] p;
        if (component == 3) return 0;
        if (y < 12 || y >= 372) return 57;
        for (int dy = 0; dy < 2; dy++) begin
            for (int dx = 0; dx < 2; dx++) begin
                p = pixel(f, x * 2 + dx, (y - 12) * 2 + dy);
                case (component)
                    0: sum += expand(int'(p[15:11]),5);
                    1: sum += expand(int'(p[10:5]),6);
                    2: sum += expand(int'(p[4:0]),5);
                    default: $fatal(1,"FAIL bad oracle component");
                endcase
            end
        end
        c = (sum + 2) / 4;
        average_seen[c] = 1;
        return (254 * c + 255) / 510;
    endfunction

    always @(negedge clk) begin
        cycle++;
        awready = !stalled && cycle % 5 != 0;
        wready = !stalled && cycle % 7 != 0;
        bvalid = !stalled && responses != 0 && cycle % 3 != 0;
        bresp = inject_error ? 2'b10 : 2'b00;
    end
    always @(posedge clk) begin
        int offset;
        int row_index;
        int byte_index;
        int expected;
        if (rst_n) begin
            if (!ready) $fatal(1,"FAIL CH2 backpressures source t=%0t",$time);
            if (valid) begin
                source_words++;
                if (sof) sof_cycle = cycle;
                if (eof) eof_cycle = cycle;
            end
            if (overflow) overflows++;
            if (skip) skips++;
            if (cfg_error) configs += int'(cfg_errors);
            if (awvalid && awready) begin
                if (write_left != 0) $fatal(1,"FAIL overlapping W bursts");
                if (id || addr[4:0] != 0 || int'(addr[11:0]) + (int'(len)+1)*32 > 4096)
                    $fatal(1,"FAIL AXI address geometry");
                write_left = int'(len) + 1;
                write_address = int'(addr);
            end
            if (write_held && (!wvalid || wdata !== stalled_data ||
                strb !== stalled_strb || last !== stalled_last))
                $fatal(1,"FAIL stalled W changed t=%0t",$time);
            write_held = wvalid && !wready;
            stalled_data = wdata;
            stalled_strb = strb;
            stalled_last = last;
            if (wvalid && wready) begin
                if (write_left == 0 || last != (write_left == 1))
                    $fatal(1,"FAIL W burst geometry");
                if (checking) begin
                    if (strb !== '1) $fatal(1,"FAIL CH2 partial beat");
                    offset = write_address - readback_base;
                    row_index = offset / 2624;
                    byte_index = offset % 2624;
                    if (byte_index >= 2560 || row_index >= 384 ||
                        observed_bytes != row_index * 2560 + byte_index)
                        $fatal(1,"FAIL surface order offset=%0d bytes=%0d",offset,observed_bytes);
                    for (int b = 0; b < 32; b++) begin
                        expected = expected_byte(pattern_frame,(byte_index+b)/4,
                                                 row_index,(byte_index+b)%4);
                        if (wdata[b*8 +: 8] !== 8'(expected))
                            $fatal(1,"FAIL byte f=%0d y=%0d byte=%0d expected=%0d got=%0d t=%0t",
                                pattern_frame,row_index,byte_index+b,expected,wdata[b*8 +: 8],$time);
                    end
                    if (observed_bytes == 0) first_write_cycle = cycle;
                    observed_bytes += 32;
                    last_write_cycle = cycle;
                    output_beats++;
                end
                write_address += 32;
                write_left--;
                if (write_left == 0) responses++;
            end
            if (bvalid && bready) responses--;
            if (done) begin
                if (!checking || observed_bytes != 983040)
                    $fatal(1,"FAIL early/unexpected completion bytes=%0d",observed_bytes);
                if (bus_error != inject_error)
                    $fatal(1,"FAIL bus error event");
                completions++;
            end
        end
    end

    task automatic boundary;
        @(negedge clk);
        valid = 1;
        sof = 1;
        eol = 1;
        eof = 1;
        boundaries = 3'b100;
        @(negedge clk);
        valid = 0;
        sof = 0;
        eol = 0;
        eof = 0;
        boundaries = 0;
        repeat (4) @(negedge clk);
    endtask
    task automatic send_frame(input int f, input bit gaps);
        frame_id = 32'(f);
        for (int y = 0; y < 720; y++) begin
            for (int x = 0; x < 1280; x += 2) begin
                @(negedge clk);
                if (gaps && (x + y) % 37 == 0) begin
                    valid = 0;
                    boundaries = 0;
                    @(negedge clk);
                end
                valid = 1;
                data = {pixel(f,x+1,y),pixel(f,x,y)};
                sof = y == 0 && x == 0;
                eol = x == 1278;
                eof = y == 719 && eol;
                incomplete = expected_incomplete && eof;
                boundaries = sof ? (3'b001 << source) : 3'd0;
            end
        end
        @(negedge clk);
        valid = 0;
        sof = 0;
        eol = 0;
        eof = 0;
        boundaries = 0;
    endtask
    task automatic finish_frame(input int wanted);
        wait (completions == wanted);
        repeat (4) @(negedge clk);
        if (busy || done_id !== 32'(pattern_frame) ||
            done_info !== {inject_error,expected_incomplete,2'(expected_src),2'(expected_slot)})
            $fatal(1,"FAIL metadata busy=%b id=%0d info=%h",busy,done_id,done_info);
        $display("frame %0d bytes=%0d beats=%0d firstAWdata=%0d EOFflush=%0d",
            pattern_frame,observed_bytes,output_beats,first_write_cycle-sof_cycle,
            last_write_cycle-eof_cycle);
        checking = 0;
    endtask
    task automatic start_check(input int f, input int slot_number);
        pattern_frame = f;
        expected_slot = slot_number;
        expected_src = int'(source);
        readback_base = (slot_number+1) * 'h100000;
        observed_bytes = 0;
        output_beats = 0;
        checking = 1;
    endtask
    initial begin
        int sum;
        int other;
        bit found;
        // Construct 2x2 green blocks realizing each 8-bit average. The reference
        // still expands and averages all four RGB565 pixels independently.
        for (int a = 0; a < 64; a++) begin
            for (int b = 0; b < 64; b++) begin
                sum = expand(a,6) + expand(b,6);
                pair_valid[sum] = 1;
                pair_a[sum] = a;
                pair_b[sum] = b;
            end
        end
        for (int c = 0; c < 256; c++) begin
            found = 0;
            for (int a = 0; a <= 510; a++) begin
                for (int delta = -2; delta <= 1; delta++) begin
                    other = c*4 + delta - a;
                    if (!found && other >= 0 && other <= 510 &&
                        pair_valid[a] && pair_valid[other]) begin
                        quartets[c][0] = pair_a[a];
                        quartets[c][1] = pair_b[a];
                        quartets[c][2] = pair_a[other];
                        quartets[c][3] = pair_b[other];
                        found = 1;
                    end
                end
            end
            if (!found) $fatal(1,"FAIL missing average stimulus %0d",c);
        end
        repeat (4) @(negedge clk);
        rst_n = 1;
        width = 640;
        boundary();
        if (configs != 1 || busy) $fatal(1,"FAIL CH2 size rejection");
        width = 1280;
        ring_size = 1;
        boundary();
        if (configs != 2 || busy) $fatal(1,"FAIL ring rejection");
        ring_size = 3;
        source = 3;
        boundary();
        if (configs != 3 || busy) $fatal(1,"FAIL source rejection");
        source = 2;
        slots_busy = 15;
        boundary();
        if (skips != 1 || configs != 3 || busy) $fatal(1,"FAIL busy slots");
        slots_busy = 0;
        start_check(0,0);
        send_frame(0,0);
        finish_frame(1);
        source = 0;
        expected_incomplete = 1;
        inject_error = 1;
        start_check(1,1);
        send_frame(1,1);
        finish_frame(2);
        expected_incomplete = 0;
        inject_error = 0;
        source = 2;
        stalled = 1;
        send_frame(2,0);
        if (overflows != 1 || completions != 2)
            $fatal(1,"FAIL memory-source CH2 overflow/drop");
        stalled = 0;
        wait (!busy);
        repeat (4) @(negedge clk);
        // Overflow rolls allocation back: reuse slot two.
        start_check(3,2);
        send_frame(3,0);
        finish_frame(3);
        for (int c = 0; c < 256; c++) begin
            if (!average_seen[c]) $fatal(1,"FAIL untested quantizer input %0d",c);
        end
        // ABORT during padding must retire without publishing a frame.
        @(negedge clk);
        valid = 1;
        sof = 1;
        data = 0;
        @(negedge clk);
        valid = 0;
        sof = 0;
        repeat (100) @(negedge clk);
        abort_request = 1;
        @(negedge clk);
        abort_request = 0;
        wait (!busy);
        repeat (4) @(negedge clk);
        if (completions != 3) $fatal(1,"FAIL abort reports completion");
        start_check(4,0);
        send_frame(4,1);
        finish_frame(4);
        if (overflows != 1 || configs != 3 || skips != 1)
            $fatal(1,"FAIL event accounting");
        $display("PASS vin_ch2: all 256 averages, every byte, padding, FIFO, errors and recovery");
        $finish;
    end
    initial begin #100000000; $fatal(1,"FAIL timeout busy=%b count=%0d",busy,count); end
endmodule
