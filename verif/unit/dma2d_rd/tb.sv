// File: tb.sv
// Spec: dma2d 2, 3, 5, 6; dma2d-testplan DM-01--DM-09.
// Description: Independent burst-list oracle, byte memory, randomized AXI and stream peers.
// Clock domain: clk_mem.
`timescale 1ns/1ps
module tb #(
    parameter int OUTSTANDING = 4
);
    bit full_run;
    localparam bit IS_READ = 1;
    bit clk = 0;
    always #5 clk = ~clk;
    bit rst_n = 0;
    bit desc_valid = 0;
    wire desc_ready;
    bit [31:0] desc_base;
    bit [31:0] desc_stride;
    bit [15:0] desc_width;
    bit [11:0] desc_height;
    bit abort_request = 0;
    wire idle;
    wire done;
    wire error;
    wire out_valid;
    bit out_ready;
    wire [255:0] out_data;
    wire out_sol;
    wire out_eol;
    wire out_eof;
    bit in_valid;
    wire in_ready;
    bit [255:0] in_data;
    bit [31:0] in_strb;
    edrv32_axi256_if bus();
    int checker_errors;
    edrv32_axi256_checker u_checker (
        .clk_i(clk),
        .rst_n_i(rst_n),
        .bus(bus),
        .errors_o(checker_errors)
    );
    edrv32_dma2d_rd #(.OUTSTANDING(OUTSTANDING)) u_dut (
        .clk_i(clk),
        .rst_n_i(rst_n),
        .desc_valid_i(desc_valid),
        .desc_ready_o(desc_ready),
        .desc_base_i(desc_base),
        .desc_stride_i(desc_stride),
        .desc_width_bytes_i(desc_width),
        .desc_height_i(desc_height),
        .abort_i(abort_request),
        .idle_o(idle),
        .done_o(done),
        .err_o(error),
        .data_valid_o(out_valid),
        .data_ready_i(out_ready),
        .data_o(out_data),
        .data_sol_o(out_sol),
        .data_eol_o(out_eol),
        .data_eof_o(out_eof),
        .axi_arid_o(bus.arid),
        .axi_araddr_o(bus.araddr),
        .axi_arlen_o(bus.arlen),
        .axi_arvalid_o(bus.arvalid),
        .axi_rready_o(bus.rready),
        .axi_arready_i(bus.arready),
        .axi_rid_i(bus.rid),
        .axi_rdata_i(bus.rdata),
        .axi_rresp_i(bus.rresp),
        .axi_rlast_i(bus.rlast),
        .axi_rvalid_i(bus.rvalid)
    );
    assign bus.awid = '0;
    assign bus.awaddr = '0;
    assign bus.awlen = '0;
    assign bus.awvalid = '0;
    assign bus.wdata = '0;
    assign bus.wstrb = '0;
    assign bus.wlast = '0;
    assign bus.wvalid = '0;
    assign bus.bready = '0;
    typedef struct {
        bit [31:0] addr;
        int beats;
        int position;
        int index;
    } command_t;
    command_t expected[$];
    command_t read_queue[$];
    command_t write_queue[$];
    command_t response_queue[$];
    byte unsigned memory [0:262143];
    byte unsigned reference [0:262143];
    int width_beats;
    int total_beats;
    int next_address;
    int stream_sent;
    int received;
    int writes;
    int retired;
    int pending;
    int maximum_pending;
    int descriptor_seed = 0;
    int descriptors = 0;
    int error_burst;
    bit [1:0] error_response;
    bit running = 0;
    bit accepted;
    bit randomized;
    bit performance;
    bit started_data;
    bit expected_done;
    bit completion_seen;
    bit aborted;
    bit preserve_write;
    bit previous_address_stall;
    bit previous_write_stall;
    int abort_address_limit;
    bit freeze_address;
    bit freeze_response;
    bit freeze_data;
    int cycles;
    bit read_taken;
    bit response_taken;
    bit input_taken;

    function automatic byte unsigned initial_byte(input bit [31:0] addr);
        return 8'((addr >> 3) ^ addr ^ (addr >> 11) ^ 32'hb7);
    endfunction

    function automatic bit [255:0] memory_word(input bit [31:0] addr);
        bit [255:0] word_value;
        for (int lane = 0; lane < 32; lane++)
            word_value[lane*8 +: 8] = initial_byte(addr + 32'(lane));
        return word_value;
    endfunction

    function automatic bit [255:0] source_word(input int index);
        bit [255:0] word_value;
        for (int lane = 0; lane < 32; lane++)
            word_value[lane*8 +: 8] = 8'(index*37 + descriptor_seed*13 + lane*19);
        return word_value;
    endfunction

    function automatic bit [31:0] source_mask(input int index);
        bit [31:0] mask;
        int remaining;
        mask = 32'(index + descriptor_seed*103) * 32'h9e3779b9;
        mask = mask ^ (mask >> 13) ^ (mask << 7);
        remaining = int'(desc_width) - (index % width_beats)*32;
        if (remaining < 32) mask = mask & ((32'h1 << remaining) - 1);
        return mask;
    endfunction

    function automatic bit [31:0] stream_address(input int index);
        return desc_base + 32'(index / width_beats)*desc_stride +
            32'((index % width_beats)*32);
    endfunction

    // DM-01: build an independent byte-based oracle, without RTL counters or helpers.
    task automatic make_expected;
        command_t cmd;
        bit [31:0] addr;
        int remaining;
        int beats;
        expected.delete();
        for (int row = 0; row < int'(desc_height); row++) begin
            addr = desc_base + 32'(row)*desc_stride;
            remaining = (int'(desc_width) + 31) / 32;
            while (remaining > 0) begin
                beats = remaining;
                if (beats > 16) beats = 16;
                if (beats*32 > 4096 - int'(addr % 4096))
                    beats = (4096 - int'(addr % 4096)) / 32;
                cmd.addr = addr;
                cmd.beats = beats;
                cmd.position = 0;
                cmd.index = expected.size();
                expected.push_back(cmd);
                remaining -= beats;
                addr += 32'(beats*32);
            end
        end
    endtask

    // Peers retain VALID payloads until handshake, with independently randomized gaps.
    always @(negedge clk) begin : drive_peers
        command_t cmd;
        if (!rst_n) begin
            bus.arready = 0;
            bus.awready = 0;
            bus.wready = 0;
            bus.rvalid = 0;
            bus.rdata = 0;
            bus.rid = 0;
            bus.rlast = 0;
            bus.rresp = 0;
            bus.bvalid = 0;
            bus.bid = 0;
            bus.bresp = 0;
            in_valid = 0;
            in_data = 0;
            in_strb = 0;
            out_ready = 0;
        end else begin
            bus.arready = !freeze_address && (!randomized || $urandom_range(0, 3) != 0);
            bus.awready = !freeze_address && (!randomized || $urandom_range(0, 3) != 0);
            bus.wready = !freeze_data && (!randomized || $urandom_range(0, 3) != 0);
            out_ready = !freeze_data && (!randomized || $urandom_range(0, 3) != 0);
            if (!bus.rvalid || read_taken) begin
                bus.rvalid = read_queue.size() != 0 && !freeze_response &&
                    (!randomized || $urandom_range(0, 3) != 0);
                if (bus.rvalid) begin
                    cmd = read_queue[0];
                    bus.rdata = memory_word(cmd.addr + 32'(cmd.position*32));
                    bus.rlast = cmd.position == cmd.beats-1;
                    bus.rresp = (cmd.index == error_burst && cmd.position == 0) ?
                        error_response : 2'b00;
                end
            end
            if (!bus.bvalid || response_taken) begin
                bus.bvalid = response_queue.size() != 0 && !freeze_response &&
                    (!randomized || $urandom_range(0, 3) != 0);
                if (bus.bvalid) begin
                    cmd = response_queue[0];
                    bus.bresp = cmd.index == error_burst ? error_response : 2'b00;
                end
            end
            if (!in_valid || input_taken || aborted) begin
                in_valid = running && accepted && !aborted && stream_sent < total_beats &&
                    (!randomized || $urandom_range(0, 3) != 0);
                in_data = source_word(stream_sent);
                in_strb = source_mask(stream_sent);
            end
        end
    end

    always @(posedge clk) begin : score_and_memory
        command_t cmd;
        bit address_fire;
        bit response_fire;
        bit [31:0] address;
        bit [3:0] len;
        bit [31:0] mask;
        bit [255:0] word_value;
        int byte_index;
        int valid_bytes;
        read_taken = bus.rvalid && bus.rready;
        response_taken = bus.bvalid && bus.bready;
        input_taken = in_valid && in_ready;
        if (rst_n && running) begin
            cycles++;
            if (done !== expected_done)
                $fatal(1, "FAIL DM-06 done expected=%b actual=%b cycle=%0d",
                    expected_done, done, cycles);
            expected_done = 0;
            if (done) begin
                if (aborted || error !== (error_burst >= 0))
                    $fatal(1, "FAIL DM-07/08 done/error aborted=%b err=%b burst=%0d",
                        aborted, error, error_burst);
                if (pending != 0 || next_address != expected.size())
                    $fatal(1, "FAIL completion pending=%0d addresses=%0d/%0d",
                        pending, next_address, expected.size());
                completion_seen = 1;
            end else if (error) $fatal(1, "FAIL err without done");
            if (desc_valid && desc_ready) accepted = 1;
            else if (accepted && !done && !aborted && !completion_seen && desc_ready)
                $fatal(1, "FAIL DM-06 desc_ready before completion");
            if (IS_READ && bus.rready !== (aborted || abort_request || out_ready))
                $fatal(1, "FAIL spec 5.1/5.3 RREADY");
            if (abort_request) begin
                aborted = 1;
                preserve_write = previous_write_stall;
                abort_address_limit = next_address + int'(previous_address_stall);
            end
            if (aborted && (done || (IS_READ && out_valid) || (!IS_READ && in_ready)))
                $fatal(1, "FAIL DM-08 stream/done during abort");
            address_fire = IS_READ ? bus.arvalid && bus.arready :
                bus.awvalid && bus.awready;
            response_fire = IS_READ ? bus.rvalid && bus.rready && bus.rlast :
                bus.bvalid && bus.bready;
            address = IS_READ ? bus.araddr : bus.awaddr;
            len = IS_READ ? bus.arlen : bus.awlen;
            if (address_fire) begin
                if (next_address >= expected.size())
                    $fatal(1, "FAIL DM-01 extra address %h", address);
                cmd = expected[next_address];
                if (address !== cmd.addr || int'(len)+1 != cmd.beats)
                    $fatal(1, "FAIL DM-01 burst=%0d expected=%h/%0d actual=%h/%0d",
                        next_address, cmd.addr, cmd.beats, address, int'(len)+1);
                next_address++;
                if (aborted && next_address > abort_address_limit)
                    $fatal(1, "FAIL DM-08 new address after abort");
                if (IS_READ) read_queue.push_back(cmd);
                else write_queue.push_back(cmd);
            end
            if (IS_READ && bus.rvalid && bus.rready) begin
                cmd = read_queue[0];
                if (cmd.position == cmd.beats-1) cmd = read_queue.pop_front();
                else read_queue[0].position++;
            end
            if (IS_READ && out_valid && out_ready) begin
                if (received >= total_beats) $fatal(1, "FAIL DM-02 extra beat");
                address = stream_address(received);
                valid_bytes = int'(desc_width) - (received % width_beats)*32;
                if (valid_bytes > 32) valid_bytes = 32;
                for (int lane = 0; lane < valid_bytes; lane++) begin
                    if (out_data[lane*8 +: 8] !== initial_byte(address + 32'(lane)))
                        $fatal(1, "FAIL DM-02 beat=%0d lane=%0d address=%h",
                            received, lane, address);
                end
                if (out_sol !== (received % width_beats == 0) ||
                    out_eol !== (received % width_beats == width_beats-1) ||
                    out_eof !== (received == total_beats-1))
                    $fatal(1, "FAIL DM-02 markers beat=%0d sol/eol/eof=%b%b%b",
                        received, out_sol, out_eol, out_eof);
                received++;
                if (received == total_beats) expected_done = 1;
            end
            if (!IS_READ && bus.wvalid && bus.wready) begin
                if (write_queue.size() == 0) $fatal(1, "FAIL W without AW");
                cmd = write_queue[0];
                address = cmd.addr + 32'(cmd.position*32);
                mask = aborted && !preserve_write ? 32'd0 : source_mask(writes);
                word_value = source_word(writes);
                if (bus.wstrb !== mask || (mask != 0 && bus.wdata !== word_value))
                    $fatal(1, "FAIL DM-03/08 beat=%0d mask expected=%h actual=%h",
                        writes, mask, bus.wstrb);
                for (int lane = 0; lane < 32; lane++) begin
                    byte_index = int'((address + 32'(lane)) % 262144);
                    if (bus.wstrb[lane]) memory[byte_index] = bus.wdata[lane*8 +: 8];
                    if (mask[lane]) reference[byte_index] = word_value[lane*8 +: 8];
                end
                preserve_write = 0;
                writes++;
                if (cmd.position == cmd.beats-1) begin
                    cmd = write_queue.pop_front();
                    response_queue.push_back(cmd);
                end else write_queue[0].position++;
            end
            if (!IS_READ && in_valid && in_ready) stream_sent++;
            if (!IS_READ && response_fire) begin
                cmd = response_queue.pop_front();
                retired++;
                if (!aborted && retired == expected.size()) expected_done = 1;
            end
            pending += int'(address_fire) - int'(response_fire);
            if (pending < 0 || pending > OUTSTANDING)
                $fatal(1, "FAIL DM-04 pending=%0d limit=%0d", pending, OUTSTANDING);
            if (pending > maximum_pending) maximum_pending = pending;
            if (performance) begin
                if ((IS_READ && received > 0 && received < total_beats) ||
                    (!IS_READ && writes > 0 && writes < total_beats)) begin
                    if (started_data && !(IS_READ ? out_valid && out_ready :
                        bus.wvalid && bus.wready))
                        $fatal(1, "FAIL DM-05 gap cycle=%0d received=%0d writes=%0d",
                            cycles, received, writes);
                    started_data = 1;
                end
            end
            previous_address_stall = IS_READ ? bus.arvalid && !bus.arready :
                bus.awvalid && !bus.awready;
            previous_write_stall = bus.wvalid && !bus.wready;
        end
    end

    task automatic tick;
        @(posedge clk);
        #1;
        if (cycles > 2000000)
            $fatal(1, "FAIL timeout addresses=%0d/%0d pending=%0d beats=%0d/%0d idle=%b",
                next_address, expected.size(), pending,
                IS_READ ? received : writes, total_beats, idle);
    endtask

    task automatic run_descriptor(input bit [31:0] base,
        input int width_bytes, input int height, input int stride,
        input bit random_stalls, input bit measure,
        input int inject, input bit [1:0] response, input int abort_mode);
        int extent;
        int byte_index;
        @(negedge clk);
        #1;
        if (!idle || !desc_ready || read_queue.size() != 0 || write_queue.size() != 0 ||
            response_queue.size() != 0) $fatal(1, "FAIL descriptor begins with live transaction");
        desc_base = base;
        desc_width = 16'(width_bytes);
        desc_height = 12'(height);
        desc_stride = 32'(stride);
        width_beats = (width_bytes + 31) / 32;
        total_beats = width_beats*height;
        descriptor_seed++;
        descriptors++;
        make_expected();
        extent = (height-1)*stride + width_beats*32;
        if (!IS_READ) begin
            for (int i = 0; i < extent; i++) begin
                byte_index = int'((base + 32'(i)) % 262144);
                memory[byte_index] = initial_byte(base + 32'(i));
                reference[byte_index] = initial_byte(base + 32'(i));
            end
        end
        next_address = 0;
        stream_sent = 0;
        received = 0;
        writes = 0;
        retired = 0;
        pending = 0;
        maximum_pending = 0;
        accepted = 0;
        started_data = 0;
        expected_done = 0;
        completion_seen = 0;
        aborted = 0;
        preserve_write = 0;
        previous_address_stall = 0;
        previous_write_stall = 0;
        cycles = 0;
        randomized = random_stalls;
        performance = measure;
        error_burst = inject == -2 ? expected.size()-1 :
            (inject == -3 ? expected.size()/2 : inject);
        error_response = response;
        freeze_address = abort_mode == 1;
        freeze_data = abort_mode == 3;
        freeze_response = abort_mode == 4;
        running = 1;
        desc_valid = 1;
        while (!accepted) tick();
        @(negedge clk);
        #1;
        desc_valid = 0;
        if (abort_mode != 0) begin
            case (abort_mode)
                1: while (!(IS_READ ? bus.arvalid : bus.awvalid)) tick();
                2: while ((IS_READ ? received : writes) < 3) tick();
                3: begin
                    if (IS_READ) while (!bus.rvalid) tick();
                    else while (!previous_write_stall) tick();
                end
                4: while (pending != OUTSTANDING) tick();
                default: $fatal(1, "FAIL invalid test abort mode");
            endcase
            @(negedge clk);
            #1;
            abort_request = 1;
            tick();
            @(negedge clk);
            #1;
            abort_request = 0;
            freeze_address = 0;
            freeze_data = 0;
            freeze_response = 0;
            repeat (2) tick();
            while (!idle) tick();
            repeat (2) tick();
            if (pending != 0 || completion_seen || read_queue.size() != 0 || write_queue.size() != 0 ||
                response_queue.size() != 0) $fatal(1, "FAIL DM-08 drain incomplete");
            if (abort_mode == 4 && maximum_pending != OUTSTANDING)
                $fatal(1, "FAIL DM-04 outstanding boundary not reached");
        end else begin
            while (!completion_seen) tick();
            tick();
        end
        if (!IS_READ) begin
            for (int i = 0; i < extent; i++) begin
                byte_index = int'((base + 32'(i)) % 262144);
                if (memory[byte_index] !== reference[byte_index])
                    $fatal(1, "FAIL DM-03 memory address=%h expected=%h actual=%h",
                        base + 32'(i), reference[byte_index], memory[byte_index]);
            end
        end
        @(negedge clk);
        #1;
        running = 0;
    endtask

    initial begin : tests
        int offsets[4] = '{0, 32, 480, 512};
        int widths[7] = '{1, 32, 33, 512, 513, 2560, 5120};
        int heights[3] = '{1, 2, 17};
        int width_value;
        int height_value;
        int stride_value;
        int seed_value;
        full_run = $test$plusargs("FULL");
        seed_value = 32'h1a2b3c4d + OUTSTANDING;
        seed_value = $urandom(seed_value);
        repeat (4) @(negedge clk);
        #1;
        rst_n = 1;
        // DM-01, DM-02/03 and DM-06 across the complete directed cross product.
        foreach (offsets[a]) foreach (widths[w]) foreach (heights[h])
            run_descriptor(32'h20001000 - 32'(offsets[a]), widths[w], heights[h],
                ((widths[w]+31)/32)*32 + 96, 1, 0, -1, 0, 0);
        // Boundary descriptor dimensions, including the maximum legal width/height.
        run_descriptor(32'h20000fe0, 65535, 2, 65568, 1, 0, -1, 0, 0);
        run_descriptor(32'h20000000, 1, 4095, 32, 1, 0, -1, 0, 0);
        // DM-05: the data stream includes every row and burst transition.
        run_descriptor(32'h20000e00, 5120, 8, 5216, 0, 1, -1, 0, 0);
        // DM-07: both error types at first/middle/last bursts, with ordinary data checks.
        for (int resp = 2; resp <= 3; resp++) begin
            run_descriptor(32'h20000fe0, 5120, 2, 5184, 1, 0, 0, 2'(resp), 0);
            run_descriptor(32'h20000e00, 5120, 2, 5184, 1, 0, -3, 2'(resp), 0);
            run_descriptor(32'h20001000, 5120, 2, 5184, 1, 0, -2, 2'(resp), 0);
        end
        if (full_run) begin
            // DM-04/08: credit saturation, stalled addresses, partial streams and stalled data.
            for (int mode = 1; mode <= 4; mode++) begin
                run_descriptor(32'h20000fe0, 5120, 2, 5184, 0, 0, -1, 0, mode);
                // A new descriptor immediately verifies reuse after draining ABORT.
                run_descriptor(32'h20001000, 33, 2, 128, 1, 0, -1, 0, 0);
            end
            // DM-09: 1000 legal descriptors and independent random backpressure.
            for (int trial = 0; trial < 1000; trial++) begin
                width_value = int'($urandom_range(1, 12000));
                height_value = int'($urandom_range(1, 5));
                stride_value = ((width_value+31)/32 + int'($urandom_range(0, 16)))*32;
                run_descriptor(32'h20000000 + 32'($urandom_range(0, 127)*32),
                    width_value, height_value, stride_value, 1, 0, -1, 0, 0);
            end
        end
        if (checker_errors != 0) $fatal(1, "FAIL checker_errors=%0d", checker_errors);
        $display("PASS dma2d_%s OUTSTANDING=%0d FULL=%b descriptors=%0d DM-01--DM-09",
            IS_READ ? "rd" : "wr", OUTSTANDING, full_run, descriptors);
        $finish;
    end
endmodule
