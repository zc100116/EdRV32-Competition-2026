// File: environment.svh
// Spec: PIX 2-5; PIX testplan PX-01 through PX-14; SoC 4.3, 4.5, 7.1.
// Description: Stream source, independent file scoreboard, APB driver and timing checks.
//              PREPARE exports source frames before the Python model is invoked.
// Clock domain: clk_mem, 125 MHz.
    class frame_data;
        int width;
        int height;
        int enable;
        int cfg;
        int bc;
        int threshold;
        int pattern;
        int seed;
        int sent;
        int flow;
        int flags;
        int mid;
        int next_enable;
        int next_cfg;
        int next_bc;
        int next_threshold;
        logic [15:0] pixels[];
        logic [15:0] expected[];
        int input_eof_cycle;
        int first_input_cycle;
        int last_input_cycle;
        int accepted;
        bit done;
    endclass

    logic clk_mem = 0;
    logic rst_mem_n = 0;
    logic in_valid = 0;
    logic in_ready;
    logic [31:0] in_data = 0;
    logic in_sof = 0;
    logic in_eol = 0;
    logic in_eof = 0;
    logic out_valid;
    logic out_ready = 0;
    logic [31:0] out_data;
    logic out_sof;
    logic out_eol;
    logic out_eof;
    logic irq;
    edrv32_apb_if apb();
    frame_data frames[$];
    string directory;
    int case_number;
    int prepare;
    int source_frame = 0;
    int input_frame = -1;
    int output_frame = 0;
    int output_pixel = 0;
    int output_width = 64;
    int cycle = 0;
    int completed = 0;
    int dropped = 0;
    int input_stalls = 0;
    int output_stalls = 0;
    bit input_ended = 1;
    bit soft_pending = 0;
    bit soft_abort_active = 0;
    bit reset_seen = 0;
    bit irq_enabled = 0;
    bit hold_receiver = 0;
    bit receiver_enabled = 0;
    bit held_output = 0;
    logic [34:0] held_payload;
    int unsigned receiver_random = 32'h8192ab45;
    int unsigned source_random = 32'h13579bdf;

    always #4 clk_mem = ~clk_mem;

    function automatic int unsigned random_next(input int unsigned state_i);
        int unsigned value;
        value = state_i ^ (state_i << 13);
        value = value ^ (value >> 17);
        return value ^ (value << 5);
    endfunction

    task automatic expect_value(input string label_i, input logic [31:0] expected_i,
                                input logic [31:0] actual_i);
        if (actual_i !== expected_i) begin
            $display("FAIL PX-%02d frame=%0d x=%0d y=%0d %s expected=%08x actual=%08x t=%0t",
                        case_number, output_frame, output_pixel % output_width,
                        output_pixel / output_width, label_i,
                        expected_i, actual_i, $time);
            $fatal(1, "PIX comparison");
        end
    endtask

    task automatic apb_access(input bit write_i, input logic [11:0] address_i,
                                input logic [31:0] value_i, output logic [31:0] read_o);
        @(negedge clk_mem);
        apb.paddr = address_i;
        apb.psel = 16'h0004;
        apb.penable = 0;
        apb.pwrite = write_i;
        apb.pwdata = value_i;
        // PIX 4: ignores PSTRB, including zero and partial strobes (PX-13).
        apb.pstrb = case_number == 13 ? address_i[3:0] : 4'hf;
        @(negedge clk_mem);
        apb.penable = 1;
        @(posedge clk_mem);
        expect_value("APB PREADY", 1, {31'b0, apb.pready[2]});
        read_o = apb.prdata[95:64];
        expect_value("APB PSLVERR", 0, {31'b0, apb.pslverr[2]});
        @(negedge clk_mem);
        apb.psel = 0;
        apb.penable = 0;
    endtask

    task automatic write_reg(input logic [11:0] address_i, input logic [31:0] value_i);
        logic [31:0] unused_value;
        apb_access(1, address_i, value_i, unused_value);
        if (address_i == 12'h00c) irq_enabled = value_i[2];
    endtask

    task automatic read_expect(input logic [11:0] address_i, input logic [31:0] value_i);
        logic [31:0] actual;
        apb_access(0, address_i, 0, actual);
        expect_value($sformatf("APB %03x", address_i), value_i, actual);
    endtask

    task automatic configure(input int enable_i, input int cfg_i,
                                input int bc_i, input int threshold_i);
        write_reg(12'h100, 32'(cfg_i));
        write_reg(12'h104, 32'(bc_i));
        write_reg(12'h108, 32'(threshold_i));
        write_reg(12'h004, 32'(enable_i));
    endtask

    task automatic reset_registers;
        read_expect(12'h000, 32'h00020001);
        read_expect(12'h004, 0);
        read_expect(12'h008, 2);
        read_expect(12'h00c, 0);
        read_expect(12'h010, 0);
        read_expect(12'h014, 0);
        read_expect(12'h020, 0);
        read_expect(12'h024, 0);
        read_expect(12'h028, 0);
        read_expect(12'h02c, 0);
        for (int i = 0; i < 16; i++) read_expect(12'(64 + i * 4), 0);
        read_expect(12'h100, 0);
        read_expect(12'h104, 32'h100);
        read_expect(12'h108, 32'h80);
        read_expect(12'h10c, 0);
        read_expect(12'h110, 0);
    endtask

    task automatic gamma_initialize;
        for (int bank = 0; bank < 2; bank++) begin
            for (int i = 0; i < 256; i++) begin
                write_reg(12'h10c, ((bank == 0 ? 32'(i) : 32'(255-i)) << 16)
                            | (32'(bank) << 8) | 32'(i));
            end
        end
    endtask

    // Each exported frame is the actual source image used again during replay.
    task automatic load_scenario;
        int file_handle;
        int pixel_file;
        int count;
        int index;
        int unsigned state;
        int red;
        int green;
        int blue;
        int value;
        frame_data item;
        file_handle = $fopen({directory, "/scenario.txt"}, "r");
        if (file_handle == 0) $fatal(1, "FAIL cannot open scenario t=%0t", $time);
        index = 0;
        while (!$feof(file_handle)) begin
            item = new;
            count = $fscanf(file_handle,
                            "%d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d\n",
                            item.width, item.height, item.enable, item.cfg, item.bc,
                            item.threshold, item.pattern, item.seed, item.sent, item.flow,
                            item.flags, item.mid, item.next_enable, item.next_cfg,
                            item.next_bc, item.next_threshold);
            if (count != 16) $fatal(1, "FAIL scenario fields expected=16 actual=%0d", count);
            item.pixels = new[item.width * item.height];
            if (prepare != 0) begin
                pixel_file = $fopen($sformatf("%s/in%0d.hex", directory, index), "w");
                state = 32'(item.seed);
                for (int p = 0; p < item.width * item.height; p++) begin
                    state = random_next(state);
                    red = ((p % item.width) * 31) / (item.width - 1);
                    green = ((p / item.width) * 63) / (item.height > 1 ? item.height - 1 : 1);
                    blue = (p % item.width + p / item.width) % 32;
                    case (item.pattern)
                        0: value = int'(state & 32'hffff);
                        1: begin
                            case (item.seed % 6)
                                0: value = 0;
                                1: value = 65535;
                                2: value = 63488;
                                3: value = 2016;
                                4: value = 31;
                                default: value = 31760; // RGB565 0x7c10 has Y=128.
                            endcase
                        end
                        2: value = (red << 11) | (green << 5) | blue;
                        3: value = ((p % item.width + p / item.width) & 1) != 0 ? 65535 : 0;
                        default: begin
                            red = (red + int'(state & 7)) % 32;
                            green = (green + int'((state >> 3) & 7)) % 64;
                            blue = (blue + int'((state >> 6) & 7)) % 32;
                            value = (red << 11) | (green << 5) | blue;
                        end
                    endcase
                    item.pixels[p] = 16'(value);
                    $fdisplay(pixel_file, "%04x", item.pixels[p]);
                end
            end else begin
                pixel_file = $fopen($sformatf("%s/in%0d.hex", directory, index), "r");
                for (int p = 0; p < item.width * item.height; p++) begin
                    count = $fscanf(pixel_file, "%h\n", item.pixels[p]);
                    if (count != 1) $fatal(1, "FAIL missing source frame=%0d pixel=%0d", index, p);
                end
            end
            $fclose(pixel_file);
            if (prepare != 0) begin
                pixel_file = $fopen($sformatf("%s/cfg%0d.txt", directory, index), "w");
                $fdisplay(pixel_file, "%0d %0d %0d %0d %0d %0d %0d", item.width,
                            item.height, item.enable, item.cfg, item.bc, item.threshold, item.sent);
                $fclose(pixel_file);
            end
            if (item.sent == item.width * item.height / 2 && prepare == 0) begin
                item.expected = new[item.width * item.height];
                pixel_file = $fopen($sformatf("%s/out%0d.hex", directory, index), "r");
                for (int p = 0; p < item.width * item.height; p++) begin
                    count = $fscanf(pixel_file, "%h\n", item.expected[p]);
                    if (count != 1) begin
                        $fatal(1, "FAIL missing reference frame=%0d pixel=%0d", index, p);
                    end
                end
                $fclose(pixel_file);
            end
            frames.push_back(item);
            index++;
        end
        $fclose(file_handle);
    endtask

    // Sampling is at the handshake edge, before DUT nonblocking updates.
    always @(posedge clk_mem) begin : stream_monitor
        bit abandoning;
        frame_data item;
        logic [15:0] actual_pixel;
        cycle = cycle + 1;
        if (rst_mem_n && receiver_enabled) begin
            abandoning = in_valid && in_sof && !input_ended;
            // PIX 2.8 clarification: SOF appearance discards, before its handshake.
            if (abandoning) begin
                if (soft_pending) begin
                    soft_abort_active = 1;
                    reset_seen = 0;
                    expect_value("SOFT_RST abort must hold new SOF", 0, {31'b0, in_ready});
                end
                // Release output on the next falling edge after the discard notification.
                // A bypass implementation may require READY to accept the held new SOF.
                hold_receiver = 0;
                dropped++;
                input_ended = 1;
                input_frame = -1;
                output_frame = source_frame;
                output_pixel = 0;
                output_width = frames[source_frame].width;
            end
            if (soft_abort_active) begin
                // Continuous CFG read observes the specified register reset externally.
                if (!reset_seen && apb.prdata[95:64] == 0) begin
                    reset_seen = 1;
                    soft_pending = 0;
                    irq_enabled = 0;
                    completed = 0;
                    dropped = 0;
                    input_stalls = 0;
                    output_stalls = 0;
                end
                if (in_ready) begin
                    expect_value("SOF accepted only after register reset", 1, {31'b0, reset_seen});
                    soft_abort_active = 0;
                end
            end
            if (in_valid && !in_ready) input_stalls++;
            if (out_valid && !out_ready) output_stalls++;
            if (held_output && !abandoning) begin
                expect_value("stalled VALID", 1, {31'b0, out_valid});
                if ({out_sof, out_eol, out_eof, out_data} !== held_payload) begin
                    expect_value("stalled data", held_payload[31:0], out_data);
                    expect_value("stalled markers", {29'b0, held_payload[34:32]},
                                    {29'b0, out_sof, out_eol, out_eof});
                end
            end
            held_output = !abandoning && out_valid && !out_ready;
            held_payload = {out_sof, out_eol, out_eof, out_data};
            if (in_valid && in_ready) begin
                item = frames[source_frame];
                if (in_sof) begin
                    if (input_frame >= 0 && !frames[input_frame].done) begin
                        expect_value("next SOF before output EOF", 1,
                                        {31'b0, out_valid && out_ready && out_eof});
                    end
                    input_frame = source_frame;
                    input_ended = 0;
                    item.first_input_cycle = cycle;
                    expect_value("new SOF during pending SOFT_RST", 0, {31'b0, soft_pending});
                end
                item.accepted++;
                item.last_input_cycle = cycle;
                if (in_eof) begin
                    item.input_eof_cycle = cycle;
                    input_ended = 1;
                end
            end
            if (out_valid && out_ready) begin
                if (output_frame >= frames.size()) begin
                    expect_value("output frame count", 32'(frames.size()), 32'(output_frame + 1));
                end
                item = frames[output_frame];
                output_width = item.width;
                expect_value("SOF", 32'(output_pixel == 0), {31'b0, out_sof});
                expect_value("EOL", 32'(output_pixel % item.width == item.width - 2),
                                {31'b0, out_eol});
                if (item.sent < item.width * item.height / 2) begin
                    expect_value("incomplete frame EOF", 0, {31'b0, out_eof});
                end else begin
                    expect_value("EOF", 32'(output_pixel == item.width * item.height - 2),
                                    {31'b0, out_eof});
                    for (int lane = 0; lane < 2; lane++) begin
                        actual_pixel = 16'(out_data >> (lane * 16));
                        if (actual_pixel !== item.expected[output_pixel + lane]) begin
                            $display({"FAIL PX-%02d frame=%0d x=%0d y=%0d ",
                                        "expected=%04x actual=%04x t=%0t"},
                                        case_number, output_frame,
                                        (output_pixel + lane) % item.width,
                                        (output_pixel + lane) / item.width,
                                        item.expected[output_pixel + lane], actual_pixel, $time);
                            $fatal(1, "PIX pixel mismatch");
                        end
                    end
                end
                output_pixel += 2;
                if (out_eof) begin
                    item.done = 1;
                    completed++;
                    if ((item.flags & 1) != 0) begin
                        $display("PX-11 frame=%0d flush=%0d limit=%0d cycles",
                            output_frame, cycle - item.input_eof_cycle, item.width + 32);
                        if (cycle - item.input_eof_cycle > item.width + 32) begin
                            expect_value("EOF flush cycles maximum", 32'(item.width + 32),
                                            32'(cycle - item.input_eof_cycle));
                        end
                    end
                    output_frame++;
                    output_pixel = 0;
                end
            end
            if (out_valid && out_ready && out_eof) begin
                #1;
                expect_value("FRAME IRQ at output EOF edge", {31'b0, irq_enabled}, {31'b0, irq});
            end
        end
    end

    always @(negedge clk_mem) begin : receiver_drive
        receiver_random = random_next(receiver_random);
        if (!rst_mem_n || !receiver_enabled || hold_receiver) out_ready = 0;
        else if (frames[source_frame].flow == 1) out_ready = (receiver_random % 4) == 0;
        else out_ready = 1;
    end

    task automatic send_frame(input frame_data item_i);
        if ((item_i.flags & 16) != 0) begin
            // Keep a public CFG read active across abort/reset and held SOF.
            @(negedge clk_mem);
            apb.paddr = 12'h100;
            apb.psel = 16'h0004;
            apb.penable = 0;
            apb.pwrite = 0;
            @(negedge clk_mem);
            apb.penable = 1;
        end
        for (int beat = 0; beat < item_i.sent; beat++) begin
            @(negedge clk_mem);
            source_random = random_next(source_random);
            if (item_i.flow == 1 && source_random % 4 == 0) begin
                in_valid = 0;
                repeat (1 + int'((source_random >> 2) % 3)) @(negedge clk_mem);
            end
            in_valid = 1;
            in_data = {item_i.pixels[beat * 2 + 1], item_i.pixels[beat * 2]};
            in_sof = beat == 0;
            in_eol = (beat * 2) % item_i.width == item_i.width - 2;
            in_eof = beat == item_i.width * item_i.height / 2 - 1;
            @(posedge clk_mem);
            while (!in_ready) @(posedge clk_mem);
        end
        if ((item_i.flags & 2) != 0) begin
            // Return after sampling, so the next frame drives the very next cycle.
            #1;
        end else begin
            @(negedge clk_mem);
            in_valid = 0;
            in_sof = 0;
            in_eol = 0;
            in_eof = 0;
            if ((item_i.flags & 16) != 0) begin
                apb.psel = 0;
                apb.penable = 0;
            end
        end
    endtask

    task automatic midframe_write(input frame_data item_i);
        if (item_i.mid >= 0) begin
            while (item_i.accepted < item_i.mid) @(negedge clk_mem);
            if ((item_i.flags & 4) != 0) begin
                write_reg(12'h004, 32'(item_i.enable) | 8);
                soft_pending = 1;
                read_expect(12'h100, 32'(item_i.cfg));
                read_expect(12'h008, 1);
            end else begin
                configure(item_i.next_enable, item_i.next_cfg,
                            item_i.next_bc, item_i.next_threshold);
            end
        end
    endtask

    task automatic check_counters;
        read_expect(12'h02c, 32'(completed));
        read_expect(12'h040, 32'(completed));
        for (int p = 1; p < 16; p++) read_expect(12'(64+p*4), 0);
        // No stream transfer occurs while these snapshots are read.
        read_expect(12'h008, 2);
        read_expect(12'h014, 0);
    endtask

    task automatic register_writes;
        write_reg(12'h000, 32'hffffffff);
        read_expect(12'h000, 32'h00020001);
        write_reg(12'h008, 32'hffffffff);
        read_expect(12'h008, 2);
        write_reg(12'h014, 32'hffffffff);
        read_expect(12'h014, 0);
        write_reg(12'h020, 32'hffffffff);
        read_expect(12'h020, 0);
        write_reg(12'h024, 32'hffffffff);
        read_expect(12'h024, 0);
        write_reg(12'h028, 32'hffffffff);
        read_expect(12'h028, 0);
        write_reg(12'h02c, 32'hffffffff);
        read_expect(12'h02c, 0);
        for (int i = 0; i < 16; i++) begin
            write_reg(12'(64 + i * 4), 32'hffffffff);
            read_expect(12'(64 + i * 4), 0);
        end
        write_reg(12'h110, 32'hffffffff);
        read_expect(12'h110, 0);
        write_reg(12'h100, 32'hffffffff);
        read_expect(12'h100, 32'h00070777);
        write_reg(12'h104, 32'hffffffff);
        read_expect(12'h104, 32'h01ff01ff);
        write_reg(12'h108, 32'hffffffff);
        read_expect(12'h108, 32'hff);
        write_reg(12'h004, 6);
        read_expect(12'h004, 0);
        read_expect(12'h008, 2);
        write_reg(12'h010, 32'hffffffff);
        read_expect(12'h010, 0);
        read_expect(12'h10c, 0);
    endtask

    task automatic soft_reset_finished;
        // At this point the old frame has completed; allow the idle reset edge.
        repeat (3) @(negedge clk_mem);
        completed = 0;
        dropped = 0;
        input_stalls = 0;
        output_stalls = 0;
        soft_pending = 0;
        reset_registers();
        // Gamma is deliberately not rewritten: following frames check retention.
        write_reg(12'h00c, 4);
    endtask

    initial begin : scenario_run
        frame_data item;
        apb.paddr = 0;
        apb.psel = 0;
        apb.penable = 0;
        apb.pwrite = 0;
        apb.pwdata = 0;
        apb.pstrb = 0;
        if (!$value$plusargs("DIR=%s", directory)) $fatal(1, "FAIL missing DIR");
        if (!$value$plusargs("CASE=%d", case_number)) $fatal(1, "FAIL missing CASE");
        prepare = 0;
        void'($value$plusargs("PREPARE=%d", prepare));
        load_scenario();
        if (prepare != 0) begin
            $display("PASS PIX source export frames=%0d", frames.size());
            $finish;
        end else begin
            repeat (5) @(negedge clk_mem);
            rst_mem_n = 1;
            if (case_number == 13) begin
                reset_registers();
                register_writes();
            end
            gamma_initialize();
            write_reg(12'h00c, 4);
            receiver_enabled = 1;
            for (int index = 0; index < frames.size(); index++) begin
                source_frame = index;
                item = frames[index];
                source_random = 32'(item.seed) ^ 32'h13579bdf;
                receiver_random = 32'(item.seed) ^ 32'h8192ab45;
                if (index == 0) output_width = item.width;
                if ((item.flags & 16) == 0 &&
                    (index == 0 || (frames[index - 1].flags & 2) == 0)) begin
                    configure(item.enable, item.cfg, item.bc, item.threshold);
                end
                // At an abort boundary, no old output may handshake with the new SOF.
                if (index > 0 && !input_ended) hold_receiver = 1;
                fork
                    send_frame(item);
                    midframe_write(item);
                join
                // Yield before reusing this fork: Verilator 5.020 resumes JOIN inline.
                #1;
                if (item.sent == item.width * item.height / 2 && (item.flags & 2) == 0) begin
                    while (!item.done) @(negedge clk_mem);
                    @(negedge clk_mem);
                    if (item.flow == 2) begin
                        $display("PX-10 input beats=%0d cycles=%0d", item.sent,
                            item.last_input_cycle - item.first_input_cycle + 1);
                        expect_value("continuous input cycles", 32'(item.sent),
                                        32'(item.last_input_cycle - item.first_input_cycle + 1));
                    end
                    if ((item.flags & 4) != 0) soft_reset_finished();
                    else begin
                        check_counters();
                        if ((item.flags & 16) != 0) begin
                            expect_value("abort/reset was observed", 1, {31'b0, reset_seen});
                            read_expect(12'h004, 0);
                            read_expect(12'h100, 0);
                            read_expect(12'h104, 32'h100);
                            read_expect(12'h108, 32'h80);
                            read_expect(12'h00c, 0);
                            read_expect(12'h04c, 0);
                            expect_value("IRQ mask reset", 0, {31'b0, irq});
                            write_reg(12'h00c, 4);
                        end
                        read_expect(12'h010, 4);
                        expect_value("FRAME IRQ enabled", 1, {31'b0, irq});
                        write_reg(12'h00c, 0);
                        expect_value("FRAME IRQ masked", 0, {31'b0, irq});
                        read_expect(12'h010, 4);
                        write_reg(12'h00c, 4);
                        write_reg(12'h010, 4);
                        read_expect(12'h010, 0);
                        expect_value("FRAME IRQ cleared", 0, {31'b0, irq});
                    end
                    if ((item.flags & 8) != 0) begin
                        write_reg(12'h004, 8);
                        soft_reset_finished();
                    end
                end
            end
            repeat (8) @(negedge clk_mem);
            expect_value("final frame count", 32'(frames.size()), 32'(output_frame));
            $display("PASS PX-%02d frames=%0d t=%0t",
                        case_number, frames.size(), $time);
            $finish;
        end
    end

    // Test timeout required by CLAUDE.md 9.1; diagnose missing output at its coordinate.
    initial begin : simulation_timeout
        #1000000000;
        $display("FAIL PX-%02d frame=%0d x=%0d y=%0d expected=EOF actual=timeout t=%0t",
                    case_number, output_frame, output_pixel % output_width,
                    output_pixel / output_width, $time);
        $fatal(1, "PIX simulation timeout");
    end
