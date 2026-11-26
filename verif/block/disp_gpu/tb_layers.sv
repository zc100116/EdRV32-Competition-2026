// File: tb_layers.sv
// Spec: DISP v0.3 2.4-2.7, 4-6; testplan DS-06/07/09/13 through DS-19.
// Description: Independent L0 APB/AXI/TMDS scoreboard and directed stimuli.
// Clock domains: clk_mem and clk_pix, with independently varied phase and period.
`timescale 1ns/1ps
module tb_layers;
    localparam logic [31:0] BASE_A = 32'h80000000;
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
    int seed = 1;
    int variant;
    int frame_index = -1;
    int symbol_index;
    int x;
    int y;
    bit locked;
    bit stopped;
    bit irq_seen;
    bit software_enable;
    logic [31:0] rng = 32'h83592001;
    logic [31:0] stimulus_rng;
    int cycles;
    int urgent_cycles;
    int outstanding;
    int latest;
    int ar_frame;
    int ar_row;
    int ar_layer;
    int ar_column;
    int urgent_row;
    bit urgent_row_valid;
    int frame_request[64];
    int scanned;
    int accepted[1];
    int returned[1];
    int demanded[1];
    int missing[1];
    int missing_frames[1];
    bit frame_missing[1];
    bit group_missing[1];
    bit repayment[1];
    int capacity_checks[1];
    int urgent_low[1];
    int urgent_high;
    int urgent_outside;
    int last_return[1];
    int last_demand[1];
    int descriptor_count[1];
    int expected_descriptors[1];
    int reference_fd;
    int reference_pixels;
    string reference_path;
    realtime latch_time;
    realtime previous_latch;
    realtime frame_period;
    typedef struct packed {
        logic [31:0] base0;
        int stride0;
        int sx;
        int sy;
        bit en0;
        bit x2;
    } config_t;
    config_t software_cfg;
    config_t latched[64];
    typedef struct packed {
        logic [31:0] address;
        int beats;
        int index;
        int layer;
        int frame_id;
    } command_t;
    command_t commands[$];
    always #(mem_half) clk_mem = !clk_mem;
    initial begin
        #0.123;
        #(real'((seed*53)%97)*0.071);
        forever #(pix_half) clk_pix = !clk_pix;
    end
    edrv32_disp_gpu u_dut (
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
                            input logic [31:0] actual_i, input int layer_i = -1);
        if (actual_i != expected_i)
            $fatal(1, "FAIL DS-%02d %s expected=%0h actual=%0h layer=%0d row=%0d col=%0d t=%0t",
                    test_case, name_i, expected_i, actual_i, layer_i, y, x, $time);
    endtask

    function automatic int draw(input int limit_i);
        stimulus_rng ^= stimulus_rng << 13;
        stimulus_rng ^= stimulus_rng >> 17;
        stimulus_rng ^= stimulus_rng << 5;
        return int'(stimulus_rng % 32'(limit_i));
    endfunction

    function automatic logic [23:0] expand(input logic [15:0] v);
        return {v[15:11], v[15:13], v[10:5], v[10:9], v[4:0], v[4:2]};
    endfunction

    function automatic logic [15:0] pixel565(input logic [31:0] base_i,
                                            input int column_i, input int row_i);
        logic [31:0] word;
        int tag;
        tag = int'((base_i - BASE_A) >> 22);
        if (test_case == 7 || test_case == 12 || test_case == 13 || test_case == 21)
            return {5'(1 + (column_i + row_i + tag*7) % 31),
                    6'((row_i*3 + column_i/7 + tag*13) % 64), 5'b0};
        word = 32'(column_i+1)*32'h045d9f3b ^ 32'(row_i+1)*32'h119de1f3 ^
                32'(seed)*32'h10204081 ^ 32'(tag)*32'h17234567;
        return 16'(word ^ (word >> 16));
    endfunction



    function automatic logic [255:0] memory_beat(input command_t command_i);
        logic [31:0] address;
        logic [31:0] base;
        logic [255:0] result;
        int offset;
        int pitch;
        int row;
        int column;
        config_t cfg;
        cfg = latched[command_i.frame_id];
        address = command_i.address + 32'(command_i.index*32);
        base = cfg.base0;
        // RAM contents depend on physical address, not this frame's programmed
        // stride. DS-18 changes the view of the same stored surface.
        pitch = 4096;
        offset = int'(address - base);
        row = offset / pitch;
        column = offset % pitch;
        for (int p = 0; p < 16; p++)
            result[p*16+:16] = pixel565(base, column/2+p, row);
        return result;
    endfunction

    task automatic next_descriptor;
        if (!latched[ar_frame].en0) ar_row = 720;
    endtask

    // FRAME is the sole enabled interrupt. Capture the public latch event before AR.
    always @(negedge clk_mem) begin : memory_drive
        if (rst_mem_n) begin
            if (!irq) irq_seen = 0;
            if (irq && !irq_seen) begin
                irq_seen = 1;
                latest++;
                latched[latest] = software_cfg;
                previous_latch = latch_time;
                latch_time = $realtime;
                if (previous_latch != 0) frame_period = latch_time - previous_latch;
                ar_frame = latest;
                ar_row = 0;
                ar_layer = 0;
                ar_column = 0;
                urgent_row_valid = 0;
                expected_descriptors[0] += software_cfg.en0 ? 720 : 0;
                next_descriptor();
                frame_request[frame_index+1] = latest;
            end
            rng = {rng[30:0], rng[31] ^ rng[21] ^ rng[1] ^ rng[0]};
            axi.arready = !stopped && rng[2:0] != 0;
            axi.rvalid = !stopped && commands.size() != 0 && rng[6:4] != 0;
            axi.rid = 0;
            axi.rdata = 0;
            axi.rlast = 0;
            axi.rresp = 0;
            if (axi.rvalid) begin
                axi.rdata = memory_beat(commands[0]);
                axi.rlast = commands[0].index == commands[0].beats-1;
            end
        end
    end

    always @(posedge clk_mem) begin : memory_monitor
        command_t cmd;
        config_t cfg;
        int row_beats;
        int burst_beats;
        int occupancy;
        int reserved;
        logic [31:0] expected_address;
        if (rst_mem_n) begin
            cycles++;
            if (urgent) urgent_cycles++;
            check("RREADY always high", 1, 32'(axi.rready));
            if (axi.arvalid) begin
                urgent_row = ar_row;
                urgent_row_valid = 1;
            end
            if (axi.arvalid && axi.arready) begin
                cfg = latched[ar_frame];
                check("descriptor has a latched frame", 1, 32'(ar_frame > 0), ar_layer);
                check("descriptor row in frame", 1, 32'(ar_row < 720), ar_layer);
                row_beats = cfg.x2 ? 40 : (cfg.sx%16 == 0 ? 80 : 81);
                expected_address = cfg.base0 + 32'((cfg.sy+(cfg.x2 ? ar_row/2 : ar_row))*cfg.stride0 + (cfg.sx/16)*32);
                expected_address += 32'(ar_column*32);
                check($sformatf("AR order row=%0d beat=%0d", ar_row, ar_column), expected_address,
                        axi.araddr, ar_layer);
                check("AR ID", 0, 32'(axi.arid), ar_layer);
                if (test_case == 20 || test_case == 21) begin
                    burst_beats = row_beats-ar_column;
                    if (burst_beats > 16) burst_beats = 16;
                    if (burst_beats > (4096-int'(expected_address[11:0]))/32)
                        burst_beats = (4096-int'(expected_address[11:0]))/32;
                    check("ST-05/06 exact AR length", 32'(burst_beats-1),
                            32'(axi.arlen), ar_layer);
                end
                check("burst stays inside descriptor", 1,
                        32'(ar_column+int'(axi.arlen)+1 <= row_beats), ar_layer);
                if (ar_column == 0) begin
                    // accepted-demanded includes all reserved in-flight beats. CDC and
                    // TMDS latency introduce only an eight-beat boundary uncertainty.
                    reserved = accepted[ar_layer] - demanded[ar_layer];
                    if (!repayment[ar_layer] && reserved > 512-row_beats+8)
                        check("row reserves FIFO space including in-flight", 512-row_beats+8,
                                32'(reserved), ar_layer);
                    capacity_checks[ar_layer]++;
                    descriptor_count[ar_layer]++;
                end
                cmd.address = axi.araddr;
                cmd.beats = int'(axi.arlen)+1;
                cmd.index = 0;
                cmd.layer = ar_layer;
                cmd.frame_id = ar_frame;
                commands.push_back(cmd);
                outstanding++;
                accepted[ar_layer] += cmd.beats;
                ar_column += cmd.beats;
                if (ar_column == row_beats) begin
                    ar_column = 0;
                    ar_row++;
                    next_descriptor();
                end
            end
            if (axi.rvalid && axi.rready) begin
                returned[commands[0].layer]++;
                last_return[commands[0].layer] = cycles;
                if (axi.rlast) begin
                    cmd = commands.pop_front();
                    outstanding--;
                end else commands[0].index++;
            end
            check("at most four outstanding", 1, 32'(outstanding <= 4));

        end
    end

    // Both underflow patterns have disjoint channel contributions. Infer missing
    // beats independently, then compare every channel against the complete formula.
    always @(negedge clk_pix) begin : display_monitor
        config_t cfg;
        int request;
        int p;
        int within0;
        int offset;
        bit need0;
        logic [23:0] background;
        logic [23:0] expected;
        if (rst_pix_n) begin
            if (!locked && de) begin
                locked = 1;
                frame_index = 0;
                symbol_index = 0;
            end
            if (locked) begin
                x = symbol_index % 1650;
                y = symbol_index / 1650;
                check("DE coordinates", 32'(x < 1280 && y < 720), 32'(de));
                if (de) begin
                    request = frame_request[frame_index];
                    expected = 0;
                    if (request != 0) begin
                        cfg = latched[request];
                        p = cfg.sx % 16;
                        within0 = ((cfg.x2 ? x/2 : x)+p) % 16;
                        need0 = cfg.en0 && (x == 0 || (within0 == 0 && (!cfg.x2 || x%2 == 0)));
                        if (need0) begin
                            for (int l = 0; l < 1; l++) begin
                                if (need0) begin
                                    demanded[l]++;
                                    last_demand[l] = cycles;
                                    group_missing[l] = 0;
                                    if (test_case == 7 || test_case == 12 || test_case == 13 || test_case == 21)
                                        group_missing[l] = rgb[23:16] == 0;
                                    if (group_missing[l]) begin
                                        if (!repayment[l] && returned[l]-demanded[l] > 8)
                                            check("miss requires exhausted returned data", 0,
                                                    32'(returned[l]-demanded[l]), l);
                                        missing[l]++;
                                        frame_missing[l] = 1;
                                        repayment[l] = 1;
                                    end else begin
                                        check("displayed beat has returned", 1,
                                                32'(returned[l] >= demanded[l]), l);
                                        repayment[l] = 0;
                                    end
                                end
                            end
                        end
                        background = 0;
                        if (cfg.en0 && !group_missing[0]) begin
                            offset = ((cfg.x2 ? y/2 : y)+cfg.sy)*cfg.stride0 +
                                2*((cfg.x2 ? x/2 : x)+cfg.sx);
                            background = expand(pixel565(cfg.base0, (offset%4096)/2,
                                                            offset/4096));
                        end
                        expected = background;
                    end
                    check("L0 scroll / X2 / debt position", 32'(expected),
                            32'(rgb));
                    if (x == 1279 && y == 719 && request != 0) begin
                        scanned++;
                        for (int l = 0; l < 1; l++) begin
                            if (frame_missing[l]) missing_frames[l]++;
                            frame_missing[l] = 0;
                        end
                    end
                end
                symbol_index++;
                if (symbol_index == 1650*750) begin
                    symbol_index = 0;
                    frame_index++;
                end
            end
        end
    end

    task automatic transfer(input bit write_i, input logic [11:0] address_i,
                            input logic [31:0] value_i, output logic [31:0] result_o);
        @(negedge clk_mem);
        apb.psel = 16'h20;
        apb.penable = 0;
        apb.paddr = address_i;
        apb.pwrite = write_i;
        apb.pwdata = value_i;
        @(negedge clk_mem);
        apb.penable = 1;
        @(posedge clk_mem);
        while (!apb.pready[5]) @(posedge clk_mem);
        check("APB response", 0, 32'(apb.pslverr[5]));
        result_o = apb.prdata[160+:32];
        @(negedge clk_mem);
        apb.psel = 0;
        apb.penable = 0;
    endtask

    task automatic wr(input logic [11:0] address_i, input logic [31:0] value_i);
        logic [31:0] unused;
        transfer(1, address_i, value_i, unused);
        case (address_i)
            12'h004: software_enable = value_i[0] && !value_i[2] && !value_i[3];
            12'h100: software_cfg.base0 = value_i & 32'hfffff000;
            12'h104: software_cfg.stride0 = int'(value_i & 32'hffe0);
            12'h114: begin
                software_cfg.sx = int'(value_i[14:0]);
                software_cfg.sy = int'(value_i[27:16]);
            end
            12'h118: begin
                software_cfg.en0 = value_i[0];
                software_cfg.x2 = value_i[2];
            end
            default: begin end
        endcase
    endtask

    task automatic rd_check(input logic [11:0] address_i, input logic [31:0] expected_i);
        logic [31:0] value;
        transfer(0, address_i, 0, value);
        check($sformatf("register %03h", address_i), expected_i, value);
    endtask

    task automatic position(input int frame_i, input int row_i, input int column_i = 0);
        wait (frame_index == frame_i && y == row_i && x >= column_i);
    endtask

    task automatic await_frame(input int frame_i);
        wait (latest == frame_i);
        rd_check(12'h110, 32'(frame_i));
        if (latched[frame_i].en0) rd_check(12'h108, latched[frame_i].base0);
        wr(12'h010, 4);
    endtask

    task automatic finish_scan;
        logic [31:0] status;
        wr(12'h004, 0);
        do transfer(0, 12'h008, 0, status); while (!status[1]);
        check("IDLE has no outstanding transactions", 0, 32'(outstanding));
        repeat (40) @(negedge clk_mem);
        for (int l = 0; l < 1; l++) begin
            check("all accepted beats returned", 32'(accepted[l]), 32'(returned[l]), l);
            check("descriptor count", 32'(expected_descriptors[l]),
                    32'(descriptor_count[l]), l);
        end
        rd_check(12'h040, 32'(scanned));
        rd_check(12'h044, 32'(missing_frames[0]));
        rd_check(12'h048, 0);
        rd_check(12'h054, 0);
        rd_check(12'h058, 0);
        rd_check(12'h04c, 0);
        rd_check(12'h110, 32'(latest));
    endtask

    task automatic configure;
        wr(12'h100, BASE_A);
        wr(12'h104, 4096);
        wr(12'h118, 1);
        wr(12'h00c, 4);
    endtask

    initial begin : scenarios
        int old_missing[1];
        logic [31:0] value;
        void'($value$plusargs("CASE=%d", test_case));
        void'($value$plusargs("SEED=%d", seed));
        void'($value$plusargs("VARIANT=%d", variant));
        stimulus_rng = 32'h91a740d3 ^ 32'(seed);
        rng ^= 32'(seed)*32'h01010101;
        if (test_case == 13) begin
            pix_half = 5.9 + real'(seed%4)*0.55;
            mem_half = 3.7 + real'(seed%3)*0.4;
        end
        software_cfg = '{BASE_A, 2560, 0, 0, 1, 0};
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
        axi.rvalid = 0;
        axi.rid = 0;
        axi.rdata = 0;
        axi.rresp = 0;
        axi.rlast = 0;
        repeat (8) @(negedge clk_mem);
        rst_mem_n = 1;
        repeat (3) @(negedge clk_pix);
        rst_pix_n = 1;
        wait (locked);
        configure();
        case (test_case)
            20: begin
                // ST-05: a 640x360 source window at nonzero SCROLL expands to 720p.
                wr(12'h118, 5);
                wr(12'h114, 32'h00030020);
                wr(12'h004, 1);
                await_frame(1);
                position(1, 700);
                finish_scan();
                check("ST-05 all 720 repeated source rows", 720, 32'(descriptor_count[0]));
                check("ST-05 40 beats per output row", 720*40, 32'(accepted[0]));
            end
            21: begin
                // ST-06: mid-frame shadow writes take effect at the next FRAME only.
                wr(12'h114, 32'h00030020);
                wr(12'h118, 5);
                wr(12'h004, 1);
                await_frame(1);
                position(1, 100);
                wr(12'h118, 1);
                await_frame(2);
                position(2, 100);
                wr(12'h118, 5);
                await_frame(3);
                position(3, 120);
                stopped = 1;
                position(3, 220);
                wr(12'h004, 0);
                position(4, 180);
                stopped = 0;
                position(4, 400);
                for (int l = 0; l < 1; l++) begin
                    old_missing[l] = missing[l];
                    check("ST-06 L0 missed beats", 1, 32'(missing[l] > 0), l);
                end
                wr(12'h004, 1);
                await_frame(4);
                position(5, 700);
                for (int l = 0; l < 1; l++)
                    check("ST-06 debt repaid and next frame aligned", 32'(old_missing[l]),
                            32'(missing[l]), l);
                finish_scan();
            end
            default: $fatal(1, "FAIL unknown layer case actual=%0d", test_case);
        endcase
        check("protocol checker", 0, 32'(checker_errors));
        $display("PASS DS-%02d seed=%0d variant=%0d frames=%0d miss0=%0d",
                    test_case, seed, variant, scanned, missing[0]);
        $finish;
    end
    initial begin
        #400000000;
        $fatal(1, "FAIL DS-%02d timeout expected=completion actual=stalled row=%0d col=%0d",
                test_case, y, x);
    end
endmodule
