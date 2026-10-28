// File: tb.sv
// Spec: DISP 2-6; DISP testplan DS-01 through DS-13; SoC 4.2, 4.3, 7.1.
// Description: Black-box APB/AXI/TMDS verification with deterministic surfaces,
//              independent pixel/debt accounting and observable FIFO bounds.
// Clock domains: independent clk_mem and clk_pix.
`timescale 1ns/1ps
module tb;
    localparam int FRAME_SYMBOLS = 1650 * 750;
    localparam int FRAME_BEATS = 80 * 720;
    localparam logic [31:0] BASE_A = 32'h80000000;
    localparam logic [31:0] BASE_B = 32'h80400000;
    localparam logic [31:0] BASE_C = 32'h80800000;
    logic clk_mem = 0;
    logic clk_pix = 0;
    logic rst_mem_n = 0;
    logic rst_pix_n = 0;
    realtime mem_half = 4;
    realtime pix_half = 6.734007;
    edrv32_apb_if apb();
    edrv32_axi256_if axi();
    logic [29:0] symbols;
    logic urgent;
    logic irq;
    logic hs;
    logic vs;
    logic de;
    logic [23:0] rgb;
    int rx_frames;
    int rx_pixels;
    int checker_errors;
    int test_case;
    int seed;
    int stride;
    int memory_stride;
    int stop_phase = 999;
    bit boundary_mode;
    bit boundary_request_seen;
    bit boundary_idle_seen;
    logic [31:0] random_state;
    logic [31:0] stimulus_state;
    bit stop_memory;
    bit inject_error;
    bit injected;
    bit software_enable;
    logic [31:0] software_next;
    int software_stride;
    int mem_cycles;
    int urgent_cycles;
    int returned_beats;
    int accepted_beats;
    int read_frames;
    int returned_frames;
    int outstanding;
    int peak_outstanding;
    logic [31:0] read_base[32];
    int read_stride[32];
    int frame_request[32];
    int requests;
    int display_groups;
    int black_groups;
    int black_frames;
    int nonblack_groups;
    int group_black_pixels;
    bit frame_had_black;
    bit group_is_black;
    bit debt_possible;
    int frame_index = -1;
    int symbol_index;
    int x;
    int y;
    bit timing_locked;
    int finished_frames;
    int boundary_crossed;
    int low_urgent_checks;
    int high_urgent_checks;
    int capacity_checks;
    int last_return_cycle;
    int last_group_cycle;
    logic [29:0] reference_symbols[FRAME_SYMBOLS];
    string reference_path;

    typedef struct packed {
        logic [31:0] address;
        int beats;
        int index;
    } command_t;
    command_t commands[$];

    always #(mem_half) clk_mem = !clk_mem;
    initial begin
        wait (seed != 0);
        #(0.123 + real'((seed*53)%97)*0.071);
        forever #(pix_half) clk_pix = !clk_pix;
    end

    edrv32_disp u_dut (
        // Clock domains.
        .clk_mem_i(clk_mem),
        .rst_mem_n_i(rst_mem_n),
        .clk_pix_i(clk_pix),
        .rst_pix_n_i(rst_pix_n),
        // Media APB slot 5.
        .apb_paddr_i(apb.paddr),
        .apb_psel_i(apb.psel[5]),
        .apb_penable_i(apb.penable),
        .apb_pwrite_i(apb.pwrite),
        .apb_pwdata_i(apb.pwdata),
        .apb_pstrb_i(apb.pstrb),
        .apb_prdata_o(apb.prdata[160+:32]),
        .apb_pready_o(apb.pready[5]),
        .apb_pslverr_o(apb.pslverr[5]),
        // P0 read-only local AXI256.
        .p0_arid_o(axi.arid),
        .p0_araddr_o(axi.araddr),
        .p0_arlen_o(axi.arlen),
        .p0_arvalid_o(axi.arvalid),
        .p0_arready_i(axi.arready),
        .p0_rid_i(axi.rid),
        .p0_rdata_i(axi.rdata),
        .p0_rresp_i(axi.rresp),
        .p0_rlast_i(axi.rlast),
        .p0_rvalid_i(axi.rvalid),
        .p0_rready_o(axi.rready),
        // Display, priority and interrupt.
        .p0_urgent_o(urgent),
        .tmds_sym_o(symbols),
        .irq_o(irq)
    );
    edrv32_axi256_checker u_protocol (
        .clk_i(clk_mem),
        .rst_n_i(rst_mem_n),
        .bus(axi),
        .errors_o(checker_errors)
    );
    tmds_rx_model u_receiver (
        .clk_pix_i(clk_pix),
        .rst_n_i(rst_pix_n),
        .sym_i(symbols),
        .hs_o(hs),
        .vs_o(vs),
        .de_o(de),
        .rgb_o(rgb),
        .frame_count_o(rx_frames),
        .frame_pixel_count_o(rx_pixels)
    );

    task automatic check(input string name_i, input logic [31:0] expected_i,
                            input logic [31:0] actual_i);
        if (actual_i != expected_i)
            $fatal(1, "FAIL DS-%02d %s expected=%0h actual=%0h time=%0t frame=%0d x=%0d y=%0d",
                    test_case, name_i, expected_i, actual_i, $time, frame_index, x, y);
    endtask

    function automatic logic [15:0] pixel565(input logic [31:0] base_i,
                                            input int x_i, input int y_i);
        int tag;
        int red;
        int green;
        int blue;
        tag = int'((base_i - BASE_A) >> 22);
        red = 1 + (x_i + y_i + tag * 7) % 31;
        green = (y_i * 3 + x_i / 7 + tag * 13) % 64;
        blue = (x_i * 3 + y_i * 5 + tag * 11) % 32;
        return {5'(red), 6'(green), 5'(blue)};
    endfunction

    function automatic logic [23:0] expand(input logic [15:0] value_i);
        return {value_i[15:11], value_i[15:13], value_i[10:5], value_i[10:9],
                value_i[4:0], value_i[4:2]};
    endfunction

    function automatic logic [255:0] memory_beat(input logic [31:0] address_i);
        logic [31:0] base;
        int offset;
        int column;
        int row;
        logic [255:0] data;
        base = BASE_A + ((address_i - BASE_A) & 32'hffc00000);
        offset = int'(address_i - base);
        row = offset / memory_stride;
        column = (offset % memory_stride) / 2;
        for (int p = 0; p < 16; p++)
            data[p*16+:16] = pixel565(base, column+p, row);
        return data;
    endfunction

    function automatic int draw(input int limit_i);
        stimulus_state ^= stimulus_state << 13;
        stimulus_state ^= stimulus_state >> 17;
        stimulus_state ^= stimulus_state << 5;
        return int'(stimulus_state % 32'(limit_i));
    endfunction

    // BFM drives on falling edges and accepts on rising edges; no response races.
    always @(negedge clk_mem) begin : memory_drive
        if (rst_mem_n) begin
            random_state = {random_state[30:0], random_state[31] ^ random_state[21] ^
                            random_state[1] ^ random_state[0]};
            axi.arready = !stop_memory && random_state[2:0] != 0;
            axi.rvalid = !stop_memory && commands.size() != 0 &&
                            random_state[6:4] != 0;
            axi.rid = 0;
            axi.rdata = 0;
            axi.rlast = 0;
            axi.rresp = 0;
            if (axi.rvalid) begin
                axi.rdata = memory_beat(commands[0].address + 32'(commands[0].index*32));
                axi.rlast = commands[0].index == commands[0].beats-1;
                if (inject_error && !injected) axi.rresp = 2;
            end
        end
    end

    always @(posedge clk_mem) begin : memory_monitor
        command_t cmd;
        int frame_offset;
        int row;
        int beat_column;
        int occupancy_lower;
        if (rst_mem_n) begin
            mem_cycles++;
            if (urgent) urgent_cycles++;
            if (boundary_idle_seen)
                check("no AR after first IDLE", 0, 32'(axi.arvalid));
            check("RREADY permanently high", 1, 32'(axi.rready));
            if (axi.arvalid && axi.arready) begin
                frame_offset = accepted_beats % FRAME_BEATS;
                row = frame_offset / 80;
                beat_column = frame_offset % 80;
                if (frame_offset == 0) begin
                    read_frames++;
                    if (boundary_mode) begin
                        check("at most one critical request", 0, 32'(boundary_request_seen));
                        boundary_request_seen = 1;
                        requests++;
                        frame_request[1] = requests;
                    end
                    read_base[read_frames] = software_next;
                    read_stride[read_frames] = software_stride;
                    // The visible TMDS boundary follows the source timing through
                    // the encoder. AXI may start just before that output boundary.
                    if (read_frames > requests &&
                        !(software_enable && y == 719 && x >= 1280))
                        check("read only requested frames", requests, read_frames);
                    if (read_frames > 1)
                        check("previous frame completed before next AR", read_frames-1,
                                returned_frames);
                end
                check("AR local ID", 0, 32'(axi.arid));
                check("AR row/stride/order",
                        32'(read_base[read_frames]) + row*read_stride[read_frames] +
                        beat_column*32, 32'(axi.araddr));
                if (beat_column + int'(axi.arlen) + 1 > 80)
                    check("burst ends within row", 80, beat_column + int'(axi.arlen)+1);
                if (beat_column == 0) begin
                    // Lower bound excludes all possible debt immediately; CDC and encoder
                    // latency may shift a few beats. Check only the unambiguous region.
                    occupancy_lower = returned_beats - display_groups;
                    if (occupancy_lower > 440)
                        check("new row reserves 80 FIFO beats (bound)", 440, occupancy_lower);
                    capacity_checks++;
                end
                accepted_beats += int'(axi.arlen) + 1;
                cmd.address = axi.araddr;
                cmd.beats = int'(axi.arlen) + 1;
                cmd.index = 0;
                commands.push_back(cmd);
                outstanding++;
            end
            if (axi.rvalid && axi.rready) begin
                returned_beats++;
                last_return_cycle = mem_cycles;
                if (axi.rresp == 2) injected = 1;
                if (axi.rlast) begin
                    cmd = commands.pop_front();
                    outstanding--;
                end else commands[0].index++;
                if (returned_beats % FRAME_BEATS == 0) returned_frames++;
            end
            if (outstanding > peak_outstanding) peak_outstanding = outstanding;
            if (outstanding > 4) check("OUTSTANDING <= 4", 4, outstanding);
            if (test_case == 9 && accepted_beats > returned_frames*FRAME_BEATS) begin
                occupancy_lower = returned_beats - display_groups;
                if (occupancy_lower >= 96) begin
                    check("urgent clear above one row", 0, 32'(urgent));
                    high_urgent_checks++;
                end
                if (occupancy_lower < 64 && mem_cycles-last_return_cycle > 24 &&
                    mem_cycles-last_group_cycle > 24) begin
                    check("urgent asserted below one row", 1, 32'(urgent));
                    low_urgent_checks++;
                end
            end
        end
    end

    // DS-01/02/03/05/06/07/11/13: decode and compare every output symbol/pixel.
    always @(negedge clk_pix) begin : display_monitor
        logic [23:0] expected_rgb;
        int request;
        int sync_line;
        if (rst_pix_n) begin
            if (!timing_locked && de) begin
                timing_locked = 1;
                frame_index = 0;
                symbol_index = 0;
            end
            if (timing_locked) begin
                x = symbol_index % 1650;
                y = symbol_index / 1650;
                check("DE position/polarity", 32'(x < 1280 && y < 720), 32'(de));
                check("HS position/polarity", 32'(x >= 1390 && x < 1430), 32'(hs));
                // CEA line boundaries are HS rising edges; active coordinates start
                // 260 pixels later. Thus vertical blank starts at y=719, x=1390.
                sync_line = (y + int'(x >= 1390)) % 750;
                check("VS position/polarity", 32'(sync_line >= 725 && sync_line < 730),
                        32'(vs));
                if (x == 1390 && y == 719 && software_enable && !boundary_mode) begin
                    requests++;
                    frame_request[frame_index+1] = requests;
                end
                if (x == 0 && y == 720 && read_frames > requests)
                    check("requests accounted after visible VBlank", requests, read_frames);
                if (test_case == 2 && frame_index == 1)
                    check("Python TMDS symbol", 32'(reference_symbols[symbol_index]),
                            32'(symbols));
                if (de) begin
                    request = frame_request[frame_index];
                    expected_rgb = 0;
                    if (request != 0) begin
                        if (x % 16 == 0) begin
                            display_groups++;
                            last_group_cycle = mem_cycles;
                            group_is_black = rgb == 0;
                            if (group_is_black) begin
                                if (test_case != 7 && test_case != 8 && test_case != 13)
                                    check("no underflow", 1, 0);
                                // A nonblack source makes black groups observable. Already
                                // returned beats bound the empty decision outside an
                                // existing repayment window. A FIFO may still contain late
                                // beats ahead of usable data while debt is being repaid.
                                if (!debt_possible && returned_beats - display_groups > 8)
                                    check("black group requires insufficient data", 0,
                                            returned_beats-display_groups);
                                debt_possible = 1;
                                black_groups++;
                                frame_had_black = 1;
                            end else begin
                                debt_possible = 0;
                                if (returned_beats < display_groups)
                                    check("pixel requires returned AXI beat", display_groups,
                                            returned_beats);
                                nonblack_groups++;
                            end
                            group_black_pixels = 0;
                        end
                        if (!group_is_black)
                            expected_rgb = expand(pixel565(read_base[request], x, y));
                        if (rgb == 0) group_black_pixels++;
                        if (x % 16 == 15 && group_is_black)
                            check("underflow covers entire 16-pixel group", 16,
                                    group_black_pixels);
                    end
                    check("RGB565 expansion/pixel position", 32'(expected_rgb),
                            32'(rgb));
                    if (x == 1279 && y == 719) begin
                        finished_frames++;
                        if (request != 0 && frame_had_black) black_frames++;
                        frame_had_black = 0;
                    end
                end
                if (x == 0 && y == 726 && frame_index > 0)
                    check("receiver collected active pixels", 1280*720, rx_pixels);
                symbol_index++;
                if (symbol_index == FRAME_SYMBOLS) begin
                    symbol_index = 0;
                    frame_index++;
                    if (stop_memory) boundary_crossed++;
                end
            end
        end
    end

    task automatic apb_transfer(input bit write_i, input logic [11:0] address_i,
                                input logic [31:0] value_i,
                                output logic [31:0] read_o, input logic [3:0] strobe_i = 15);
        @(negedge clk_mem);
        apb.paddr = address_i;
        apb.psel = 16'h0020;
        apb.penable = 0;
        apb.pwrite = write_i;
        apb.pwdata = value_i;
        apb.pstrb = strobe_i;
        @(negedge clk_mem);
        apb.penable = 1;
        @(posedge clk_mem);
        while (!apb.pready[5]) @(posedge clk_mem);
        check("APB response", 0, 32'(apb.pslverr[5]));
        read_o = apb.prdata[160+:32];
        @(negedge clk_mem);
        apb.psel = 0;
        apb.penable = 0;
    endtask

    task automatic wr(input logic [11:0] address_i, input logic [31:0] value_i,
                        input logic [3:0] strobe_i = 15);
        logic [31:0] unused;
        apb_transfer(1, address_i, value_i, unused, strobe_i);
        case (address_i)
            12'h004: software_enable = value_i[0] && !value_i[2] && !value_i[3];
            12'h100: software_next = value_i & 32'hfffff000;
            12'h104: software_stride = int'(value_i & 32'h0000ffe0);
            default: begin end
        endcase
    endtask

    task automatic rd_check(input logic [11:0] address_i, input logic [31:0] expected_i);
        logic [31:0] value;
        apb_transfer(0, address_i, 0, value);
        check($sformatf("register %03h", address_i), 32'(expected_i), 32'(value));
    endtask

    task automatic position(input int frame_i, input int row_i, input int column_i = 0);
        wait (frame_index == frame_i && y == row_i && x >= column_i);
    endtask

    task automatic settle_cdc;
        repeat (40) @(negedge clk_mem);
    endtask

    task automatic wait_idle;
        logic [31:0] value;
        do apb_transfer(0, 12'h008, 0, value); while (!value[1]);
        check("IDLE implies !BUSY", 0, 32'(value[0]));
        check("IDLE leaves no outstanding responses", 0, outstanding);
        check("IDLE completes all accepted read beats", accepted_beats, returned_beats);
    endtask

    task automatic check_perf;
        int scanned;
        settle_cdc();
        scanned = 0;
        for (int f = 0; f < frame_index; f++)
            if (frame_request[f] != 0) scanned++;
        if ((y >= 720 || (y == 719 && x >= 1280)) &&
            frame_request[frame_index] != 0) scanned++;
        rd_check(12'h040, 32'(scanned));
        rd_check(12'h044, 32'(black_frames));
        rd_check(12'h048, 32'(black_groups));
        rd_check(12'h04c, 32'(urgent_cycles));
        rd_check(12'h02c, 32'(read_frames));
        rd_check(12'h110, 32'(read_frames));
        check("protocol checker", 0, checker_errors);
    endtask

    task automatic start_surface;
        wr(12'h100, BASE_A);
        wr(12'h104, 32'(stride));
        wr(12'h00c, 32'h106);
        wr(12'h004, 1);
    endtask

    // DS-10/12, spec 2.8: source/output encoder latency and ENABLE synchronizer
    // phase permit either zero or one critical request. Adopt that optional request
    // from AR, then require its complete scan and forbid every AR after first IDLE.
    task automatic boundary_stop_test(input bit soft_reset_i);
        int before_idle_reads;
        start_surface();
        position(0, 719, 1390 + stop_phase);
        if (soft_reset_i) wr(12'h004, 8);
        else wr(12'h004, 4);
        wait_idle();
        boundary_idle_seen = 1;
        before_idle_reads = read_frames;
        settle_cdc();
        rd_check(12'h004, 0);
        rd_check(12'h008, 2);
        position(2, 721);
        check("critical requests remain stopped", before_idle_reads, read_frames);
        rd_check(12'h008, 2);
        if (soft_reset_i) begin
            rd_check(12'h00c, 0);
            rd_check(12'h010, 0);
            rd_check(12'h014, 0);
            rd_check(12'h100, 0);
            rd_check(12'h104, 2560);
            rd_check(12'h108, 0);
            rd_check(12'h10c, 0);
            rd_check(12'h110, 0);
            for (int p = 0; p < 16; p++) rd_check(12'(64+p*4), 0);
        end else begin
            rd_check(12'h100, BASE_A);
            rd_check(12'h108, boundary_request_seen ? BASE_A : 0);
            check_perf();
        end
        $display("boundary stop phase=%0d request=%0d soft=%0d",
                stop_phase, boundary_request_seen, soft_reset_i);
    endtask

    // DS-12: reset values, field alignment, RO/unused locations and ignored PSTRB.
    task automatic register_reset_checks;
        rd_check(12'h000, 32'h00050001);
        rd_check(12'h004, 0);
        rd_check(12'h008, 2);
        rd_check(12'h00c, 0);
        rd_check(12'h010, 0);
        rd_check(12'h014, 0);
        rd_check(12'h100, 0);
        rd_check(12'h104, 32'h00000a00);
        rd_check(12'h108, 0);
        rd_check(12'h10c, 0);
        rd_check(12'h110, 0);
        for (int p = 0; p < 16; p++) rd_check(12'(64+p*4), 0);
        wr(12'h100, BASE_A | 32'hfff, 0);
        rd_check(12'h100, BASE_A);
        wr(12'h104, 32'hffff101f, 1);
        rd_check(12'h104, 32'h1000);
        wr(12'h020, 32'hffffffff);
        wr(12'h024, 32'hffffffff);
        wr(12'h028, 32'hffffffff);
        wr(12'h11c, 32'hffffffff);
        rd_check(12'h020, 0);
        rd_check(12'h024, 0);
        rd_check(12'h028, 0);
        rd_check(12'h11c, 0);
        wr(12'h000, 32'hffffffff);
        rd_check(12'h000, 32'h00050001);
        wr(12'h004, 2);
        rd_check(12'h004, 0);
    endtask

    initial begin : scenarios
        logic [31:0] value;
        int saved_frames;
        int old_urgent;
        int old_black;
        void'($value$plusargs("CASE=%d", test_case));
        void'($value$plusargs("SEED=%d", seed));
        void'($value$plusargs("STRIDE=%d", stride));
        void'($value$plusargs("STOP_PHASE=%d", stop_phase));
        boundary_mode = (test_case == 10 || test_case == 12) && stop_phase != 999;
        $display("DISP case=%0d seed=%0d stride=%0d", test_case, seed, stride);
        stimulus_state = 32'h91a740d3 ^ 32'(seed);
        random_state = 32'h83592001 ^ (32'(seed)*32'h01010101);
        if (test_case == 13) begin
            pix_half = 5.9 + real'(seed % 4) * 0.55;
            mem_half = 3.7 + real'(seed % 3) * 0.4;
        end
        if (test_case == 2) begin
            void'($value$plusargs("REF=%s", reference_path));
            $readmemh(reference_path, reference_symbols);
        end
        memory_stride = stride;
        software_stride = 2560;
        apb.paddr = 0;
        apb.psel = 0;
        apb.penable = 0;
        apb.pwrite = 0;
        apb.pwdata = 0;
        apb.pstrb = 15;
        axi.awid = 0;
        axi.awaddr = 0;
        axi.awlen = 0;
        axi.awvalid = 0;
        axi.awready = 0;
        axi.wdata = 0;
        axi.wstrb = 0;
        axi.wlast = 0;
        axi.wvalid = 0;
        axi.wready = 0;
        axi.bid = 0;
        axi.bresp = 0;
        axi.bvalid = 0;
        axi.bready = 1;
        axi.arready = 0;
        axi.rid = 0;
        axi.rdata = 0;
        axi.rresp = 0;
        axi.rlast = 0;
        axi.rvalid = 0;
        repeat (8) @(negedge clk_mem);
        rst_mem_n = 1;
        repeat (3) @(negedge clk_pix);
        rst_pix_n = 1;
        wait (timing_locked);
        case (test_case)
            1: begin // DS-01: two complete frames while disabled.
                position(2, 0);
                check("disabled makes no AXI requests", 0, accepted_beats);
                check("two complete timing frames", 2, finished_frames);
            end
            2, 3, 6, 11: begin // DS-02/03/06/11: whole-frame checks above.
                if (test_case == 11) inject_error = 1;
                start_surface();
                position(1, 720);
                if (test_case == 11) begin
                    rd_check(12'h014, 2);
                    apb_transfer(0, 12'h010, 0, value);
                    check("SLVERR ERROR IRQ", 2, 32'(value & 2));
                    check("enabled IRQ output", 1, 32'(irq));
                    check("SLVERR injected", 1, 32'(injected));
                    wr(12'h010, 2);
                    rd_check(12'h014, 0);
                end
                wr(12'h004, 0);
                wait_idle();
                check_perf();
                check("row capacity checks exercised", 1, 32'(capacity_checks >= 720));
            end
            4: begin // DS-04: active-frame update, repeat and VBlank update.
                start_surface();
                position(1, 100);
                rd_check(12'h108, BASE_A);
                rd_check(12'h10c, 0);
                rd_check(12'h110, 1);
                rd_check(12'h010, 32'h104);
                wr(12'h010, 32'h104);
                rd_check(12'h010, 0);
                check("RW1C deasserts IRQ", 0, 32'(irq));
                wr(12'h100, BASE_B);
                rd_check(12'h108, BASE_A);
                position(1, 721);
                rd_check(12'h108, BASE_B);
                rd_check(12'h10c, BASE_A);
                rd_check(12'h110, 2);
                rd_check(12'h010, 32'h104);
                wr(12'h010, 32'h104);
                position(2, 721);
                rd_check(12'h010, 4);
                rd_check(12'h10c, BASE_A);
                rd_check(12'h110, 3);
                // Already-prefetched frame stays B, update C in VBlank for next request.
                wr(12'h100, BASE_C);
                rd_check(12'h108, BASE_B);
                wr(12'h010, 4);
                position(3, 721);
                rd_check(12'h108, BASE_C);
                rd_check(12'h10c, BASE_B);
                rd_check(12'h010, 32'h104);
                wr(12'h004, 0);
                wait_idle();
                check_perf();
            end
            5: begin // DS-05: black before enable, first request and graceful stop.
                position(1, 100);
                start_surface();
                rd_check(12'h108, 0);
                rd_check(12'h110, 0);
                position(1, 721);
                rd_check(12'h110, 1);
                rd_check(12'h008, 1);
                position(2, 180);
                wr(12'h004, 0);
                rd_check(12'h004, 0);
                rd_check(12'h008, 1);
                wait_idle();
                position(3, 721);
                check("single requested scan", 1, requests);
                check_perf();
            end
            7, 8: begin // DS-07/08: stall across frame boundary and repay late beats.
                start_surface();
                position(1, 120);
                stop_memory = 1;
                if (test_case == 7) begin
                    // Leave the next frame unscanned while late data repays debt.
                    position(1, 200);
                    wr(12'h004, 0);
                end
                position(2, 180);
                check("stalled across frame boundary", 1, 32'(boundary_crossed != 0));
                stop_memory = 0;
                if (test_case == 7) begin
                    position(2, 400);
                    wr(12'h004, 1);
                end
                position(2, 721);
                settle_cdc();
                apb_transfer(0, 12'h050, 0, value);
                if (test_case == 8)
                    check("pending request PERF4", 1, value);
                else check("disabled frame makes no pending request", 0, value);
                check("underflow generated", 1, 32'(black_groups > 0));
                check("directed underflow frame count", test_case == 7 ? 1 : 2, black_frames);
                rd_check(12'h014, 1);
                old_black = black_groups;
                position(3, 720);
                check("following frame fully recovered", old_black, black_groups);
                wr(12'h004, 0);
                wait_idle();
                check_perf();
            end
            9: begin // DS-09: force both known watermarks and count exact urgent clocks.
                start_surface();
                wait (requests == 1);
                wait (axi.arvalid);
                @(posedge clk_mem);
                stop_memory = 1;
                repeat (200) @(negedge clk_mem);
                stop_memory = 0;
                position(1, 720);
                wr(12'h004, 0);
                wait_idle();
                check("urgent low-water observations", 1, 32'(low_urgent_checks > 0));
                check("urgent high-water observations", 1, 32'(high_urgent_checks > 0));
                check_perf();
            end
            10: begin // DS-10: ABORT during read and phase-swept stopping handshake.
                if (boundary_mode) boundary_stop_test(0);
                else begin
                    start_surface();
                    position(1, 100);
                    check("ABORT while reads active", 1, 32'(returned_frames == 0));
                    wr(12'h004, 4);
                    rd_check(12'h004, 0);
                    rd_check(12'h008, 1);
                    wait_idle();
                    saved_frames = read_frames;
                    position(3, 721);
                    check("no post-ABORT requests", saved_frames, read_frames);
                    rd_check(12'h008, 2);
                    check_perf();
                end
            end
            12: begin // DS-12: SOFT_RST drains, register reset, phase-swept handshake.
                if (boundary_mode) boundary_stop_test(1);
                else begin
                    register_reset_checks();
                    start_surface();
                    position(1, 120);
                    old_urgent = urgent_cycles;
                    check("PERF3 populated", 1, 32'(old_urgent > 0));
                    wr(12'h004, 8);
                    wait_idle();
                    settle_cdc();
                    rd_check(12'h000, 32'h00050001);
                    rd_check(12'h004, 0);
                    rd_check(12'h008, 2);
                    rd_check(12'h00c, 0);
                    rd_check(12'h010, 0);
                    rd_check(12'h014, 0);
                    rd_check(12'h100, 0);
                    rd_check(12'h104, 2560);
                    rd_check(12'h108, 0);
                    rd_check(12'h10c, 0);
                    rd_check(12'h110, 0);
                    for (int p = 0; p < 16; p++) rd_check(12'(64+p*4), 0);
                    saved_frames = read_frames;
                    position(3, 721);
                    check("SOFT_RST no late requests", saved_frames, read_frames);
                    rd_check(12'h008, 2);
                end
            end
            13: begin // DS-13: ten seeds, six frames, random surfaces/stop/enable/phase.
                start_surface();
                for (int f = 1; f <= 5; f++) begin
                    position(f, 40 + draw(400), draw(1000));
                    wr(12'h100, BASE_A + 32'(draw(3))*32'h00400000);
                    if (draw(3) == 0) begin
                        stop_memory = 1;
                        position(f, 500+draw(150));
                        stop_memory = 0;
                    end
                    wr(12'h004, 32'(draw(2)));
                end
                position(5, 700);
                wr(12'h004, 0);
                wait_idle();
                position(6, 721);
                check_perf();
            end
            default: $fatal(1, "FAIL unknown case expected=1..13 actual=%0d time=%0t",
                            test_case, $time);
        endcase
        check("receiver collected frames", 1, 32'(rx_frames >= 2));
        $display("PASS DS-%02d seed=%0d stride=%0d reads=%0d blackbeats=%0d blackframes=%0d",
                    test_case, seed, stride, read_frames, black_groups, black_frames);
        $finish;
    end

    initial begin
        #180000000;
        $fatal(1, "FAIL DS-%02d timeout expected=completion actual=stalled time=%0t",
                test_case, $time);
    end
endmodule
