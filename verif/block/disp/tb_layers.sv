// File: tb_layers.sv
// Spec: DISP v0.3 2.4-2.7, 4-6; testplan DS-06/07/09/13 through DS-19.
// Description: Independent two-layer APB/AXI/TMDS scoreboard and directed stimuli.
// Clock domains: clk_mem and clk_pix, with independently varied phase and period.
`timescale 1ns/1ps
module tb_layers;
    localparam logic [31:0] BASE_A = 32'h80000000;
    localparam logic [31:0] BASE_1 = 32'h81000000;
    localparam int FRAME_PIXELS = 1280*720;
    localparam int OPACITY[6] = '{0, 1, 128, 255, 73, 219};
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
    int frame_request[64];
    int scanned;
    int accepted[2];
    int returned[2];
    int demanded[2];
    int missing[2];
    int missing_frames[2];
    bit frame_missing[2];
    bit group_missing[2];
    bit repayment[2];
    int capacity_checks[2];
    int urgent_low[2];
    int urgent_high;
    int urgent_outside;
    int last_return[2];
    int last_demand[2];
    int descriptor_count[2];
    int expected_descriptors[2];
    int reference_fd;
    int reference_pixels;
    string reference_path;
    realtime latch_time;
    realtime previous_latch;
    realtime frame_period;
    typedef struct packed {
        logic [31:0] base0;
        logic [31:0] base1;
        int stride0;
        int stride1;
        int sx;
        int sy;
        bit en0;
        bit en1;
        int left;
        int top;
        int width;
        int height;
        int opacity;
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

    `include "blend_ref.svh"

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
        base = command_i.layer == 0 ? cfg.base0 : cfg.base1;
        pitch = command_i.layer == 0 ? cfg.stride0 : cfg.stride1;
        offset = int'(address - base);
        row = offset / pitch;
        column = offset % pitch;
        if (command_i.layer == 0) begin
            for (int p = 0; p < 16; p++)
                result[p*16+:16] = pixel565(base, column/2+p, row);
        end else begin
            for (int p = 0; p < 8; p++)
                result[p*32+:32] = pixel_argb(base, column/4+p, row);
        end
        return result;
    endfunction

    // Skip exactly those descriptors omitted by spec 2.5, preserving L0/L1 order.
    task automatic next_descriptor;
        config_t cfg;
        cfg = latched[ar_frame];
        while (ar_row < 720 && ((ar_layer == 0 && !cfg.en0) ||
                (ar_layer == 1 && (!cfg.en1 || ar_row < cfg.top ||
                                                    ar_row >= cfg.top+cfg.height)))) begin
            if (ar_layer == 0) ar_layer = 1;
            else begin
                ar_layer = 0;
                ar_row++;
            end
        end
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
                expected_descriptors[0] += software_cfg.en0 ? 720 : 0;
                expected_descriptors[1] += software_cfg.en1 ? software_cfg.height : 0;
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
        int occupancy;
        int reserved;
        logic [31:0] expected_address;
        bit l1_inside;
        bit l1_outside;
        if (rst_mem_n) begin
            cycles++;
            if (urgent) urgent_cycles++;
            check("RREADY always high", 1, 32'(axi.rready));
            if (axi.arvalid && axi.arready) begin
                cfg = latched[ar_frame];
                check("descriptor has a latched frame", 1, 32'(ar_frame > 0), ar_layer);
                check("descriptor row in frame", 1, 32'(ar_row < 720), ar_layer);
                row_beats = ar_layer == 0 ? (cfg.sx%16 == 0 ? 80 : 81) : cfg.width/8;
                expected_address = ar_layer == 0 ?
                    cfg.base0 + 32'((cfg.sy+ar_row)*cfg.stride0 + (cfg.sx/16)*32) :
                    cfg.base1 + 32'((ar_row-cfg.top)*cfg.stride1);
                expected_address += 32'(ar_column*32);
                check($sformatf("AR order row=%0d beat=%0d", ar_row, ar_column), expected_address,
                        axi.araddr, ar_layer);
                check("AR ID", 0, 32'(axi.arid), ar_layer);
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
                    if (ar_layer == 0) ar_layer = 1;
                    else begin
                        ar_layer = 0;
                        ar_row++;
                    end
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
            if (test_case == 9 && ar_frame != 0 && ar_row < 720) begin
                cfg = latched[ar_frame];
                // FRAME case 9 uses full-width L1 when L0 is off. Otherwise L0
                // constrains descriptor lookahead: 512 FIFO beats / >=80 per row
                // permits at most seven partial/full rows; eight rows bound it.
                // AR is observable, the DMA's pending descriptor is not. Only
                // classify intervals wholly inside/outside the rectangle.
                l1_inside = cfg.en1 && ar_row >= cfg.top &&
                            ar_row+8 < cfg.top+cfg.height;
                l1_outside = !cfg.en1 || ar_row+8 < cfg.top ||
                                ar_row >= cfg.top+cfg.height;
                for (int l = 0; l < 2; l++) begin
                    occupancy = returned[l] - demanded[l];
                    row_beats = l == 0 ? 81 : cfg.width/8;
                    if ((l == 0 ? cfg.en0 : l1_inside) &&
                        occupancy < row_beats-16 && cycles-last_return[l] > 24 &&
                        cycles-last_demand[l] > 24) begin
                        check("urgent below layer row watermark", 1, 32'(urgent), l);
                        urgent_low[l]++;
                    end
                end
                if ((l1_inside || l1_outside) &&
                    (!cfg.en0 || returned[0]-demanded[0] >= 97) &&
                    (l1_outside || returned[1]-demanded[1] >= cfg.width/8+16)) begin
                    check("urgent clear above applicable watermarks", 0, 32'(urgent));
                    urgent_high++;
                    if (cfg.en1 && l1_outside) urgent_outside++;
                end
            end
        end
    end

    // Both underflow patterns have disjoint channel contributions. Infer missing
    // beats independently, then compare every channel against the complete formula.
    always @(negedge clk_pix) begin : display_monitor
        config_t cfg;
        int request;
        int p;
        int within0;
        bit inside1;
        bit need0;
        bit need1;
        logic [23:0] background;
        logic [31:0] foreground;
        logic [23:0] expected;
        logic [23:0] python_pixel;
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
                        within0 = (x+p) % 16;
                        inside1 = cfg.en1 && x >= cfg.left && x < cfg.left+cfg.width &&
                                    y >= cfg.top && y < cfg.top+cfg.height;
                        need0 = cfg.en0 && (x == 0 || within0 == 0);
                        need1 = inside1 && (x-cfg.left)%8 == 0;
                        if (need0 || need1) begin
                            for (int l = 0; l < 2; l++) begin
                                if (l == 0 ? need0 : need1) begin
                                    demanded[l]++;
                                    last_demand[l] = cycles;
                                    group_missing[l] = 0;
                                    if (test_case == 7 || test_case == 12 || test_case == 13)
                                        group_missing[l] = l == 0 ? rgb[23:16] == 0 :
                                                                    rgb[7:0] == 0;
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
                        foreground = 0;
                        if (cfg.en0 && !group_missing[0])
                            background = expand(pixel565(cfg.base0, x+cfg.sx, y+cfg.sy));
                        if (inside1 && !group_missing[1])
                            foreground = pixel_argb(cfg.base1, x-cfg.left, y-cfg.top);
                        expected = mix(background, foreground, cfg.opacity);
                        if (test_case == 15 && request <= 6) begin
                            check("Python reference available", 1,
                                    32'($fscanf(reference_fd, "%h", python_pixel) == 1));
                            check("Python versus SV blend reference", 32'(python_pixel),
                                    32'(expected));
                            reference_pixels++;
                        end
                    end
                    check("window / rectangle / blend / debt position", 32'(expected),
                            32'(rgb));
                    if (x == 1279 && y == 719 && request != 0) begin
                        scanned++;
                        for (int l = 0; l < 2; l++) begin
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
                software_cfg.en1 = value_i[1];
            end
            12'h120: software_cfg.base1 = value_i & 32'hfffff000;
            12'h124: software_cfg.stride1 = int'(value_i & 32'hffe0);
            12'h128: begin
                software_cfg.left = int'({value_i[10:3], 3'b0});
                software_cfg.top = int'(value_i[25:16]);
            end
            12'h12c: begin
                software_cfg.width = int'({value_i[10:3], 3'b0});
                software_cfg.height = int'(value_i[25:16]);
            end
            12'h130: software_cfg.opacity = int'(value_i[7:0]);
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
        if (latched[frame_i].en1) rd_check(12'h134, latched[frame_i].base1);
        wr(12'h010, 4);
    endtask

    task automatic finish_scan;
        logic [31:0] status;
        wr(12'h004, 0);
        do transfer(0, 12'h008, 0, status); while (!status[1]);
        check("IDLE has no outstanding transactions", 0, 32'(outstanding));
        repeat (40) @(negedge clk_mem);
        for (int l = 0; l < 2; l++) begin
            check("all accepted beats returned", 32'(accepted[l]), 32'(returned[l]), l);
            check("descriptor count", 32'(expected_descriptors[l]),
                    32'(descriptor_count[l]), l);
        end
        rd_check(12'h040, 32'(scanned));
        rd_check(12'h044, 32'(missing_frames[0]));
        rd_check(12'h048, 32'(missing[0]));
        rd_check(12'h054, 32'(missing_frames[1]));
        rd_check(12'h058, 32'(missing[1]));
        rd_check(12'h04c, 32'(urgent_cycles));
        rd_check(12'h110, 32'(latest));
    endtask

    task automatic configure;
        wr(12'h100, BASE_A);
        wr(12'h104, 4096);
        wr(12'h120, BASE_1);
        wr(12'h124, 5120);
        wr(12'h118, 3);
        wr(12'h00c, 4);
    endtask

    task automatic release_check(input logic [31:0] flags_i,
                                    input logic [31:0] rel0_i, input logic [31:0] rel1_i);
        rd_check(12'h010, flags_i);
        rd_check(12'h10c, rel0_i);
        rd_check(12'h138, rel1_i);
        wr(12'h010, 32'h300);
        rd_check(12'h010, 0);
    endtask

    initial begin : scenarios
        int old_missing[2];
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
        software_cfg = '{BASE_A, BASE_1, 2560, 5120, 0, 0, 1, 0,
                            0, 0, 1280, 720, 255};
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
        if (test_case == 15) begin
            void'($value$plusargs("BLEND_REF=%s", reference_path));
            reference_fd = $fopen(reference_path, "r");
            check("Python blend frame open", 1, 32'(reference_fd != 0));
        end
        repeat (8) @(negedge clk_mem);
        rst_mem_n = 1;
        repeat (3) @(negedge clk_pix);
        rst_pix_n = 1;
        wait (locked);
        configure();
        case (test_case)
            6: begin
                wr(12'h004, 1);
                await_frame(1);
                position(1, 700);
                finish_scan();
                for (int l = 0; l < 2; l++)
                    check("full-screen row capacity exercised", 720,
                            32'(capacity_checks[l]), l);
            end
            7: begin
                wr(12'h130, 128);
                wr(12'h118, variant == 0 ? 2 : (variant == 1 ? 1 : 3));
                wr(12'h004, 1);
                await_frame(1);
                position(1, 120);
                stopped = 1;
                position(1, 200);
                wr(12'h004, 0);
                position(2, 180);
                stopped = 0;
                position(2, 400);
                repeat (40) @(negedge clk_mem);
                transfer(0, 12'h014, 0, value);
                if (variant == 0) check("L1-only underflow code", 3, value, 1);
                if (variant == 1) check("L0-only underflow code", 1, value, 0);
                if (variant == 2)
                    check("both report a specified underflow code", 1,
                            32'(value == 1 || value == 3));
                transfer(0, 12'h010, 0, value);
                check("underflow ERROR flag", 2, value & 2);
                wr(12'h010, 2);
                for (int l = 0; l < 2; l++) old_missing[l] = missing[l];
                wr(12'h004, 1);
                await_frame(2);
                position(3, 700);
                for (int l = 0; l < 2; l++) begin
                    check("next scan fully aligned and recovered", 32'(old_missing[l]),
                            32'(missing[l]), l);
                    if (l == 0 ? variant != 0 : variant != 1)
                        check("layer underflow exercised", 1, 32'(missing[l] > 0), l);
                end
                finish_scan();
            end
            9: begin
                // L1-only top/bottom rectangles expose the 'outside rectangle' predicate.
                wr(12'h118, 2);
                wr(12'h128, 32'h00640000);
                wr(12'h12c, 32'h00640500);
                wr(12'h004, 1);
                await_frame(1);
                stopped = 1;
                repeat (200) @(negedge clk_mem);
                stopped = 0;
                position(1, 600);
                wr(12'h118, 1);
                await_frame(2);
                stopped = 1;
                repeat (200) @(negedge clk_mem);
                stopped = 0;
                position(2, 600);
                wr(12'h12c, 32'h00640100);
                wr(12'h118, 3);
                await_frame(3);
                position(3, 700);
                finish_scan();
                for (int l = 0; l < 2; l++)
                    check("layer low urgent observations", 1, 32'(urgent_low[l] > 0), l);
                check("urgent high observations", 1, 32'(urgent_high > 0));
                check("L1 outside rectangle does not assert urgent", 1,
                        32'(urgent_outside > 0), 1);
            end
            12: begin
                wr(12'h130, 128);
                wr(12'h004, 1);
                await_frame(1);
                position(1, 100);
                wr(12'h120, BASE_1+32'h00400000);
                await_frame(2);
                release_check(32'h200, 0, BASE_1);
                position(2, 120);
                stopped = 1;
                position(2, 300);
                stopped = 0;
                position(2, 600);
                check("L1 PERF6 populated before SOFT_RST", 1, 32'(missing[1] > 0), 1);
                wr(12'h004, 8);
                do transfer(0, 12'h008, 0, value); while (!value[1]);
                check("SOFT_RST leaves no outstanding responses", 0, 32'(outstanding));
                repeat (40) @(negedge clk_mem);
                rd_check(12'h004, 0);
                rd_check(12'h010, 0);
                rd_check(12'h014, 0);
                rd_check(12'h118, 1);
                rd_check(12'h134, 0);
                rd_check(12'h138, 0);
                for (int p = 0; p < 7; p++) rd_check(12'(64+4*p), 0);
                position(3, 720);
                rd_check(12'h054, 0);
                rd_check(12'h058, 0);
                rd_check(12'h008, 2);
            end
            13: begin
                wr(12'h130, 128);
                wr(12'h004, 1);
                for (int f = 1; f <= 6; f++) begin
                    await_frame(f);
                    position(f, 40+draw(120), draw(600));
                    wr(12'h100, BASE_A + 32'(draw(3))*32'h00400000);
                    wr(12'h120, BASE_1 + 32'(draw(3))*32'h00400000);
                    wr(12'h118, 32'(draw(4)));
                    wr(12'h130, 32'(32+draw(192)));
                    wr(12'h114, 32'(draw(8))*65536 + 32'(draw(49)));
                    wr(12'h128, 32'(draw(600))*65536 + 32'(draw(80))*8);
                    wr(12'h12c, 32'(1+draw(120))*65536 + 32'(1+draw(80))*8);
                    if (draw(2) == 0) begin
                        stopped = 1;
                        position(f, 400+draw(200));
                        stopped = 0;
                    end
                    // Disable/re-enable within a frame, preserving six requested frames.
                    wr(12'h004, 0);
                    repeat (10+draw(100)) @(negedge clk_mem);
                    wr(12'h004, 1);
                end
                position(6, 700);
                finish_scan();
            end
            14: begin
                wr(12'h118, 1);
                wr(12'h114, 32'h00030000 | 32'(variant));
                wr(12'h004, 1);
                await_frame(1);
                position(1, 700);
                finish_scan();
                check("all scrolled row descriptors", 720, 32'(descriptor_count[0]), 0);
            end
            15: begin
                wr(12'h130, 32'(OPACITY[0]));
                wr(12'h004, 1);
                for (int f = 1; f <= 6; f++) begin
                    await_frame(f);
                    position(f, 100);
                    if (f < 6) wr(12'h130, 32'(OPACITY[f]));
                end
                position(6, 700);
                finish_scan();
                check("six Python/SV expected frames", 6*FRAME_PIXELS,
                        32'(reference_pixels));
                $fclose(reference_fd);
            end
            16: begin
                case (variant)
                    0: begin
                        wr(12'h128, 0);
                        wr(12'h12c, 32'h00010008);
                    end
                    1: begin
                        wr(12'h128, 32'h02cf04f8);
                        wr(12'h12c, 32'h00010008);
                    end
                    2: begin
                        wr(12'h128, 32'h00100008);
                        wr(12'h12c, 32'h02c004f8);
                    end
                    default: $fatal(1, "FAIL rectangle variant expected=0..2 actual=%0d",
                                    variant);
                endcase
                wr(12'h130, 128);
                wr(12'h004, 1);
                await_frame(1);
                position(1, 700);
                finish_scan();
            end
            17: begin
                wr(12'h004, 1);
                await_frame(1);
                release_check(0, 0, 0);
                position(1, 100);
                wr(12'h100, BASE_A+32'h00400000);
                rd_check(12'h108, BASE_A);
                await_frame(2);
                release_check(32'h100, BASE_A, 0);
                position(2, 100);
                wr(12'h120, BASE_1+32'h00400000);
                await_frame(3);
                release_check(32'h200, BASE_A, BASE_1);
                position(3, 100);
                wr(12'h118, 1);
                await_frame(4);
                release_check(32'h200, BASE_A, BASE_1+32'h00400000);
                position(4, 100);
                wr(12'h118, 3);
                await_frame(5);
                release_check(0, BASE_A, BASE_1+32'h00400000);
                position(5, 100);
                wr(12'h114, 32'h00020011);
                wr(12'h128, 32'h00010008);
                wr(12'h12c, 32'h02cf04f8);
                wr(12'h130, 73);
                await_frame(6);
                release_check(0, BASE_A, BASE_1+32'h00400000);
                position(6, 700);
                finish_scan();
            end
            18: begin
                wr(12'h12c, 32'h02ce04f0);
                wr(12'h004, 1);
                await_frame(1);
                await_frame(2);
                // A separate run per register places its write immediately before/after
                // the predicted public FRAME event. No DUT internals are inspected.
                #(frame_period - ($realtime-latch_time) + (variant%2 == 0 ? -64 : 64));
                check("write falls on intended side of FRAME", variant%2 == 0 ? 2 : 3,
                        32'(latest));
                case (variant/2)
                    0: wr(12'h100, BASE_A+32'h00400000);
                    1: wr(12'h104, 4128);
                    2: wr(12'h114, 32'h0003001f);
                    3: wr(12'h118, 2);
                    4: wr(12'h120, BASE_1+32'h00400000);
                    5: wr(12'h124, 5152);
                    6: wr(12'h128, 32'h00010008);
                    7: wr(12'h12c, 32'h02cf04f8);
                    8: wr(12'h130, 73);
                    default: $fatal(1, "FAIL latch variant expected=0..17 actual=%0d", variant);
                endcase
                await_frame(3);
                position(3, 100);
                await_frame(4);
                position(4, 700);
                finish_scan();
            end
            19: begin
                wr(12'h118, 0);
                wr(12'h004, 1);
                await_frame(1);
                position(1, 600);
                check("both layers off: no AR", 0, 32'(accepted[0]+accepted[1]));
                wr(12'h118, 2);
                await_frame(2);
                position(2, 700);
                finish_scan();
                check("L1-only has no L0 reads", 0, 32'(accepted[0]), 0);
            end
            default: $fatal(1, "FAIL unknown layer case actual=%0d", test_case);
        endcase
        check("protocol checker", 0, 32'(checker_errors));
        $display("PASS DS-%02d seed=%0d variant=%0d frames=%0d miss0=%0d miss1=%0d",
                    test_case, seed, variant, scanned, missing[0], missing[1]);
        $finish;
    end
    initial begin
        #400000000;
        $fatal(1, "FAIL DS-%02d timeout expected=completion actual=stalled row=%0d col=%0d",
                test_case, y, x);
    end
endmodule
