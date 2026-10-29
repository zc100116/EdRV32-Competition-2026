// File: edrv32_vin_tb.sv
// Spec: vin 2-6; vin-testplan VI-01 through VI-17.
// Description: Independent public-interface VIN scoreboard, camera stimuli and AXI RAM.
// Clock domain: clk_mem=125MHz, two independently controlled pclk domains.
`timescale 1ns/1ps
module edrv32_vin_tb #(parameter int HARNESS_SELFTEST = 0);
    import edrv32_vin_reference_pkg::*;
    logic clk_mem = 0;
    // The bench observes reset synchronously; the DUT uses asynchronous reset.
    /* verilator lint_off SYNCASYNCNET */
    logic rst_mem_n = 0;
    /* verilator lint_on SYNCASYNCNET */
    logic rst_cam0_n = 0;
    logic rst_cam1_n = 0;
    wire cam0_pclk;
    wire cam0_vsync;
    wire cam0_href;
    wire [7:0] cam0_data;
    wire cam1_pclk;
    wire cam1_vsync;
    wire cam1_href;
    wire [7:0] cam1_data;
    wire p1_urgent;
    wire irq;
    wire pix_in_valid;
    wire pix_in_ready;
    wire [31:0] pix_in_data;
    wire pix_in_sof;
    wire pix_in_eol;
    wire pix_in_eof;
    wire pix_out_valid;
    wire pix_out_ready;
    wire [31:0] pix_out_data;
    wire pix_out_sof;
    wire pix_out_eol;
    wire pix_out_eof;
    bit pix_backpressure = 0;
    bit pix_gate = 1;
    bit [31:0] rng = 32'h4621;
    int checker_errors;
    bit check_pix_stream = 1;
    vin_frame pix_frames[$];
    int pix_word = 0;
    int urgent_cycles = 0;
    int mem_cycle = 0;
    int last_b_cycle = -100;
    int source_count[3];
    int complete_count[2];
    int skip_count[2];
    int incomplete_count[2];
    int source_width[3];
    int source_height[3];
    int channel_source[2];
    int channel_ring[2];
    int channel_stride[2];
    bit channel_enable[2];
    bit [3:0] channel_busy[2];
    bit [31:0] channel_base[2][4];
    vin_reference reference;
    vin_frame expected[2][$];
    string selected_case = "smoke";
    bit full_size = 0;
    bit global_enable = 0;
    int current_test = 0;
    int requested_test = 0;
    int finished_test = 0;
    int camera_decoded[2];
    bit camera_phase[2];

    edrv32_axi256_if axi();
    edrv32_apb_if apb();
    always #4 clk_mem = ~clk_mem;

    dvp_camera_model u_cam0 (
        .pclk_o(cam0_pclk),
        .vsync_o(cam0_vsync),
        .href_o(cam0_href),
        .data_o(cam0_data)
    );
    dvp_camera_model u_cam1 (
        .pclk_o(cam1_pclk),
        .vsync_o(cam1_vsync),
        .href_o(cam1_href),
        .data_o(cam1_data)
    );
    edrv32_vin_memory u_memory (
        .clk_i(clk_mem),
        .rst_n_i(rst_mem_n),
        .bus(axi)
    );
    edrv32_axi256_checker u_checker (
        .clk_i(clk_mem),
        .rst_n_i(rst_mem_n),
        .bus(axi),
        .errors_o(checker_errors)
    );
    `include "dut_connections.svh"

    // Zero-storage PIX bypass; random READY is used for memory-source frames only.
    assign pix_in_ready = pix_out_ready && pix_gate;
    assign pix_out_valid = pix_in_valid && pix_gate;
    assign pix_out_data = pix_in_data;
    assign pix_out_sof = pix_in_sof;
    assign pix_out_eol = pix_in_eol;
    assign pix_out_eof = pix_in_eof;
    always @(negedge clk_mem) begin
        rng = u_memory.random_next(rng);
        if (!pix_gate || !pix_in_valid || pix_in_ready)
            pix_gate = !pix_backpressure || rng[0];
    end
    always @(posedge clk_mem) begin
        mem_cycle++;
        if (rst_mem_n && axi.bvalid && axi.bready) last_b_cycle = mem_cycle;
        if (!rst_mem_n) urgent_cycles = 0;
        else if (p1_urgent) urgent_cycles++;
    end
    always @(posedge cam0_pclk) begin
        if (cam0_href) begin
            if (camera_phase[0]) camera_decoded[0]++;
            camera_phase[0] = !camera_phase[0];
        end else camera_phase[0] = 0;
    end
    always @(posedge cam1_pclk) begin
        if (cam1_href) begin
            if (camera_phase[1]) camera_decoded[1]++;
            camera_phase[1] = !camera_phase[1];
        end else camera_phase[1] = 0;
    end

    // SoC 4.5: check the public VIN->PIX word stream, including every boundary marker.
    always @(posedge clk_mem) begin : pix_scoreboard
        vin_frame frame;
        int words_per_row;
        if (rst_mem_n && check_pix_stream && pix_in_valid && pix_in_ready) begin
            if (pix_frames.size() == 0)
                $fatal(1, "FAIL PIX unexpected word expected=no frame actual=%h time=%0t",
                    pix_in_data, $time);
            frame = pix_frames[0];
            words_per_row = frame.width/2;
            equal("PIX data", {frame.pixels[pix_word*2+1], frame.pixels[pix_word*2]},
                pix_in_data);
            equal("PIX SOF", 32'(pix_word == 0), 32'(pix_in_sof));
            equal("PIX EOL", 32'(pix_word%words_per_row == words_per_row-1),
                32'(pix_in_eol));
            equal("PIX EOF", 32'(pix_word == frame.width*frame.height/2-1),
                32'(pix_in_eof));
            pix_word++;
            if (pix_word == frame.width*frame.height/2) begin
                frame = pix_frames.pop_front();
                pix_word = 0;
            end
        end
    end

    task automatic equal(input string name_i,
        input bit [31:0] expected_i,
        input bit [31:0] actual_i);
        if (actual_i != expected_i)
            $fatal(1, "FAIL VI-%02d %s expected=%h actual=%h time=%0t",
                current_test, name_i, expected_i, actual_i, $time);
    endtask

    task automatic clocks(input int count_i);
        repeat (count_i) @(negedge clk_mem);
    endtask

    task automatic access(input bit write_i,
        input bit [11:0] address_i,
        input bit [31:0] data_i,
        output bit [31:0] data_o,
        input bit [3:0] strobe_i = 4'hf);
        @(negedge clk_mem);
        apb.paddr = address_i;
        apb.psel = 16'h0002;
        apb.penable = 0;
        apb.pwrite = write_i;
        apb.pwdata = data_i;
        apb.pstrb = strobe_i;
        @(negedge clk_mem);
        apb.penable = 1;
        for (int cycle = 0; cycle < 256; cycle++) begin
            @(posedge clk_mem);
            if (apb.pready[1]) begin
                equal("APB PSLVERR", 0, 32'(apb.pslverr[1]));
                data_o = apb.prdata[63:32];
                @(negedge clk_mem);
                apb.psel = 0;
                apb.penable = 0;
                return;
            end
        end
        $fatal(1, "FAIL APB timeout expected=PREADY actual=0 addr=%h time=%0t",
            address_i, $time);
    endtask

    task automatic write_reg(input bit [11:0] address_i,
        input bit [31:0] data_i,
        input bit [3:0] strobe_i = 4'hf);
        bit [31:0] unused_data;
        access(1, address_i, data_i, unused_data, strobe_i);
        if (address_i == 'h004) begin
            if (!global_enable && data_i[0]) reference.enable();
            global_enable = data_i[0];
        end
    endtask

    task automatic read_reg(input bit [11:0] address_i,
        output bit [31:0] data_o);
        access(0, address_i, 0, data_o);
    endtask

    task automatic check_reg(input bit [11:0] address_i,
        input bit [31:0] expected_i);
        bit [31:0] actual;
        read_reg(address_i, actual);
        equal($sformatf("register %03h", address_i), expected_i, actual);
    endtask

    function automatic bit [11:0] channel_address(input int channel_i,
        input int offset_i);
        return 12'('h200+channel_i*128+offset_i);
    endfunction

    task automatic reset();
        @(negedge clk_mem);
        rst_mem_n = 0;
        rst_cam0_n = 0;
        rst_cam1_n = 0;
        apb.psel = 0;
        apb.penable = 0;
        apb.paddr = 0;
        apb.pwrite = 0;
        apb.pwdata = 0;
        apb.pstrb = 0;
        u_memory.stop_write = 0;
        u_memory.stop_read = 0;
        u_memory.hold_b = 0;
        u_memory.random_percent = 0;
        u_memory.b_error_transaction = -1;
        u_memory.r_error_transaction = -1;
        u_memory.check_read_ready = 0;
        u_memory.check_continuous_w = 0;
        pix_backpressure = 0;
        check_pix_stream = 1;
        pix_frames.delete();
        pix_word = 0;
        reference.reset();
        global_enable = 0;
        foreach (source_count[i]) begin
            source_count[i] = 0;
            source_width[i] = 64;
            source_height[i] = 8;
        end
        foreach (complete_count[c]) begin
            complete_count[c] = 0;
            skip_count[c] = 0;
            incomplete_count[c] = 0;
            expected[c].delete();
            channel_enable[c] = 0;
            channel_source[c] = 0;
            channel_ring[c] = 3;
            channel_busy[c] = 0;
            channel_stride[c] = 128;
            for (int s = 0; s < 4; s++)
                channel_base[c][s] = 32'h01000000 + 32'(c*'h01000000+s*'h00400000);
        end
        clocks(20);
        rst_mem_n = 1;
        fork
            begin
                @(negedge cam0_pclk);
                rst_cam0_n = 1;
            end
            begin
                @(negedge cam1_pclk);
                rst_cam1_n = 1;
            end
        join
        clocks(30);
    endtask

    task automatic configure_channel(input int channel_i,
        input int source_i,
        input int ring_i = 3,
        input int stride_i = 128);
        channel_enable[channel_i] = 1;
        channel_source[channel_i] = source_i;
        channel_ring[channel_i] = ring_i;
        channel_stride[channel_i] = stride_i;
        write_reg(channel_address(channel_i, 0), 32'(1+(source_i<<1)+(ring_i<<4)));
        write_reg(channel_address(channel_i, 4), 32'(stride_i));
        for (int s = 0; s < 4; s++)
            write_reg(channel_address(channel_i, 8+s*4), channel_base[channel_i][s]);
    endtask

    task automatic configure_camera(input int source_i,
        input int width_i,
        input int height_i);
        source_width[source_i] = width_i;
        source_height[source_i] = height_i;
        write_reg(12'('h100+source_i*4), 32'((height_i<<16)|width_i));
    endtask

    task automatic start_enabled();
        write_reg('h00c, 'h107);
        write_reg('h004, 1);
    endtask

    function automatic logic [15:0] pattern(input int source_i,
        input int frame_i,
        input int x_i,
        input int y_i);
        return 16'('h9b61 ^ (source_i*'h6789) ^ (frame_i*'h3547) ^ (x_i*73) ^ (y_i*137));
    endfunction

    task automatic queue_frame(input vin_frame frame_i,
        input bit [1:0] drop_i = 0);
        vin_frame copy_frame;
        int slot;
        source_count[frame_i.source]++;
        if (frame_i.source < 2 && frame_i.incomplete) incomplete_count[frame_i.source]++;
        for (int c = 0; c < 2; c++) begin
            if (channel_enable[c] && channel_source[c] == frame_i.source) begin
                slot = reference.allocate(c, channel_ring[c], channel_busy[c]);
                if (slot < 0) skip_count[c]++;
                else if (!drop_i[c]) begin
                    copy_frame = new;
                    copy_frame.width = frame_i.width;
                    copy_frame.height = frame_i.height;
                    copy_frame.source = frame_i.source;
                    copy_frame.frame_id = frame_i.frame_id;
                    copy_frame.incomplete = frame_i.incomplete;
                    copy_frame.bus_error = frame_i.bus_error;
                    copy_frame.pixels = frame_i.pixels;
                    copy_frame.slot = slot;
                    copy_frame.stride = channel_stride[c];
                    copy_frame.base = channel_base[c][slot];
                    expected[c].push_back(copy_frame);
                    if (c == 0 && check_pix_stream) pix_frames.push_back(copy_frame);
                end
            end
        end
    endtask

    task automatic send_camera(input int source_i,
        input int dx_i = 0,
        input int dy_i = 0,
        input bit odd_i = 0,
        input int stop_i = -1,
        input bit [1:0] drop_i = 0,
        input bit bus_error_i = 0,
        input bit source_output_i = 1);
        logic [15:0] image[];
        vin_frame frame;
        int raw_width;
        int raw_height;
        int shaped_height;
        int old_slot[2];
        raw_width = source_width[source_i]+dx_i;
        raw_height = source_height[source_i]+dy_i;
        shaped_height = stop_i < 0 ? raw_height : stop_i;
        image = new[raw_width*raw_height];
        for (int y = 0; y < raw_height; y++) begin
            for (int x = 0; x < raw_width; x++)
                image[y*raw_width+x] = pattern(source_i, source_count[source_i], x, y);
        end
        if (source_output_i && global_enable && reference.output_frame(source_i)) begin
            frame = reference.shape(source_i, source_width[source_i], source_height[source_i],
                raw_width, shaped_height, image);
            frame.bus_error = bus_error_i;
            foreach (old_slot[c]) old_slot[c] = reference.last_slot[c];
            queue_frame(frame, drop_i);
            foreach (old_slot[c]) begin
                if (drop_i[c]) reference.last_slot[c] = old_slot[c];
            end
        end
        if (source_i == 0)
            u_cam0.send_frame(source_width[0], source_height[0], image, dx_i, dy_i,
                odd_i, stop_i);
        else u_cam1.send_frame(source_width[1], source_height[1], image, dx_i, dy_i,
            odd_i, stop_i);
    endtask

    task automatic warm_camera(input int source_i);
        repeat (2) send_camera(source_i);
        clocks(200);
    endtask

    function automatic bit final_b_seen(input vin_frame frame_i);
        bit [31:0] final_address;
        final_address = frame_i.base+32'((frame_i.height-1)*frame_i.stride
            + ((frame_i.width*2-1)/32)*32);
        for (int i = 0; i < u_memory.b_count; i++) begin
            if (u_memory.aw_addresses[i]+32'((u_memory.aw_lengths[i]-1)*32) == final_address)
                return 1;
        end
        return 0;
    endfunction

    task automatic compare_surface(input vin_frame frame_i);
        bit [31:0] address;
        bit [15:0] actual;
        for (int y = 0; y < frame_i.height; y++) begin
            for (int x = 0; x < frame_i.width; x++) begin
                address = frame_i.base+32'(y*frame_i.stride+x*2);
                actual = {u_memory.peek(address+1), u_memory.peek(address)};
                equal($sformatf("surface src%0d slot%0d x%0d y%0d addr%h",
                    frame_i.source, frame_i.slot, x, y, address),
                    32'(frame_i.pixels[y*frame_i.width+x]), 32'(actual));
            end
            // The tail lane and stride padding must retain the RAM's sentinel.
            for (int b = frame_i.width*2; b < frame_i.stride; b++)
                equal("WSTRB row padding", 'ha5,
                    32'(u_memory.peek(frame_i.base+32'(y*frame_i.stride+b))));
        end
    endtask

    task automatic drain_channel(input int channel_i,
        input int maximum_i = 1000000);
        bit [31:0] actual;
        vin_frame frame;
        int drained;
        drained = 0;
        while (expected[channel_i].size() != 0 && drained < maximum_i) begin
            frame = expected[channel_i][0];
            // One frame interrupt must be serviced before the next completion overwrites it.
            for (int tries = 0; tries < 200000; tries++) begin
                read_reg('h010, actual);
                if (actual[channel_i == 0 ? 2 : 8]) break;
                if (tries == 199999)
                    $fatal(1, "FAIL VI-%02d FRAME expected=1 actual=0 time=%0t",
                        current_test, $time);
            end
            equal("FRAME after last B", 1, 32'(final_b_seen(frame)));
            check_reg(channel_address(channel_i, 'h20), frame.done_info());
            check_reg(channel_address(channel_i, 'h24), frame.frame_id);
            equal("enabled frame IRQ", 1, 32'(irq));
            compare_surface(frame);
            complete_count[channel_i]++;
            check_reg(12'('h04c+4*channel_i), 32'(complete_count[channel_i]));
            if (channel_i == 0) check_reg('h02c, 32'(complete_count[0]));
            write_reg('h010, channel_i == 0 ? 4 : 'h100);
            frame = expected[channel_i].pop_front();
            drained++;
        end
    endtask

    task automatic drain();
        bit [31:0] source_incomplete;
        drain_channel(0);
        drain_channel(1);
        clocks(100);
        for (int source = 0; source < 3; source++)
            check_reg(12'('h040+source*4), 32'(source_count[source]));
        for (int c = 0; c < 2; c++) begin
            // A skipped, disabled or unselected channel must not report an extra frame.
            check_reg(12'('h04c+c*4), 32'(complete_count[c]));
            check_reg(12'('h064+c*4), 32'(skip_count[c]));
            // Rejected camera frames finish padding without a channel completion IRQ.
            for (int tries = 0; tries < 200000; tries++) begin
                read_reg(12'('h070+c*4), source_incomplete);
                if (source_incomplete >= 32'(incomplete_count[c])) break;
            end
            check_reg(12'('h070+c*4), 32'(incomplete_count[c]));
        end
        equal("protocol checker", 0, 32'(checker_errors));
    endtask

    task automatic wait_idle();
        bit [31:0] value;
        for (int tries = 0; tries < 200000; tries++) begin
            read_reg('h008, value);
            if (value[1] && !value[0]) begin
                equal("no pending write response", 32'(u_memory.aw_count),
                    32'(u_memory.b_count));
                equal("no pending read response", 32'(u_memory.ar_count),
                    32'(u_memory.r_count));
                return;
            end
        end
        $fatal(1, "FAIL IDLE expected=1 actual=%h time=%0t", value, $time);
    endtask

    task automatic expect_error(input int code_i);
        bit [31:0] value;
        check_reg('h014, 32'(code_i));
        read_reg('h010, value);
        equal("ERROR sticky", 2, value & 2);
        read_reg('h008, value);
        equal("STATUS ERROR", 4, value & 4);
        equal("error IRQ", 1, 32'(irq));
    endtask

    task automatic clear_error();
        write_reg('h010, 2);
        check_reg('h014, 0);
    endtask

    task automatic memory_frame(input int width_i = 34,
        input int height_i = 9,
        input int stride_i = 128,
        input bit bus_error_i = 0);
        logic [15:0] image[];
        vin_frame frame;
        image = new[width_i*height_i];
        source_width[2] = width_i;
        source_height[2] = height_i;
        for (int y = 0; y < height_i; y++) begin
            for (int x = 0; x < width_i; x++) begin
                image[y*width_i+x] = pattern(2, source_count[2], x, y);
                u_memory.poke16('h08000000+32'(y*stride_i+x*2), image[y*width_i+x]);
            end
        end
        frame = reference.shape(2, width_i, height_i, width_i, height_i, image);
        frame.bus_error = bus_error_i;
        queue_frame(frame);
        write_reg('h110, 'h08000000);
        write_reg('h114, 32'(stride_i));
        write_reg('h118, 32'((height_i<<16)|width_i));
        write_reg('h11c, 1);
    endtask

    task automatic check_memory_reads(input int width_i,
        input int height_i,
        input int stride_i);
        int index;
        int beat;
        int row_beats;
        bit [31:0] value;
        row_beats = (width_i*2+31)/32;
        index = 0;
        for (int y = 0; y < height_i; y++) begin
            beat = 0;
            while (beat < row_beats) begin
                equal("row AR address", 'h08000000+32'(y*stride_i+beat*32),
                    u_memory.ar_log[index]);
                beat += u_memory.ar_beats[index];
                index++;
            end
            equal("row read descriptor extent", 32'(row_beats), 32'(beat));
        end
        equal("AR descriptor count", 32'(index), 32'(u_memory.ar_count));
        read_reg('h010, value);
        equal("memory DONE", 1, value & 1);
        check_reg('h120, 0);
    endtask

    // Coordinator clarification: IRQ may follow final B by 1..4 memory clocks.
    // Preselect one APB read address and observe it at the IRQ transition; no writes occur.
    task automatic completion_edge(input bit [11:0] field_i,
        input bit [31:0] value_i);
        bit [31:0] irq_mask;
        read_reg('h00c, irq_mask);
        @(negedge clk_mem);
        apb.paddr = 12'(field_i);
        apb.psel = 16'h0002;
        apb.pwrite = 0;
        apb.penable = 0;
        do begin
            @(posedge clk_mem);
            #0.001;
        end while (!irq);
        equal("completion delay at least one cycle", 1, 32'(mem_cycle-last_b_cycle >= 1));
        equal("completion delay at most four cycles", 1, 32'(mem_cycle-last_b_cycle <= 4));
        equal("completion state atomic with IRQ", value_i, apb.prdata[63:32]);
        @(negedge clk_mem);
        apb.psel = 0;
        equal("FRAME IRQ enabled", 4, irq_mask & 4);
    endtask

    // VI-01: full resolution in full, three completed frames and ring order.
    task automatic vi01();
        int width;
        int height;
        bit first_complete;
        width = full_size ? 1280 : 64;
        height = full_size ? 720 : 8;
        reset();
        configure_camera(0, width, height);
        configure_channel(0, 0, 3, width*2);
        start_enabled();
        warm_camera(0);
        for (int i = 0; i < 3; i++) begin
            if (i > 0) begin
                fork
                    send_camera(0);
                    completion_edge(i == 1 ? 'h220 : 'h224, 32'(i));
                join
            end else send_camera(0);
            drain();
            check_reg('h220, 32'(i));
            check_reg('h224, 32'(i));
        end
        wait_idle();
        // A second frame must be accepted while the first awaits its final B.
        configure_camera(0, 16, 2);
        configure_channel(0, 0, 3, 32);
        u_memory.hold_b = 1;
        send_camera(0);
        equal("back-to-back pending B", 1, 32'(u_memory.aw_count > u_memory.b_count));
        send_camera(0);
        check_reg('h02c, 3);
        u_memory.hold_b = 0;
        // Keep the queue scan outside the loop condition for Verilator 5.020.
        do begin
            @(posedge clk_mem);
            #0.001;
            first_complete = final_b_seen(expected[0][0]);
        end while (!first_complete);
        u_memory.hold_b = 1;
        drain_channel(0, 1);
        u_memory.hold_b = 0;
        drain();
        check_reg('h224, 4);
        wait_idle();
    endtask

    // VI-02: initial/re-enabled discard must not allocate slots or source IDs.
    task automatic vi02();
        reset();
        configure_camera(0, 64, 8);
        configure_channel(0, 0);
        start_enabled();
        repeat (2) begin
            send_camera(0);
            clocks(200);
            check_reg('h040, 0);
            check_reg('h02c, 0);
            equal("discard has no AW", 0, 32'(u_memory.aw_count));
        end
        send_camera(0);
        drain();
        write_reg('h004, 0);
        send_camera(0, 0, 0, 0, -1, 2'b11);
        write_reg('h004, 1);
        repeat (2) begin
            send_camera(0);
            clocks(200);
            check_reg('h040, 1);
            check_reg('h02c, 1);
        end
        send_camera(0);
        drain();
        check_reg('h224, 1);
    endtask

    // VI-03: independently patterned bytes, HREF blanks and a trailing half-pixel.
    task automatic vi03();
        reset();
        configure_camera(0, 18, 5);
        configure_channel(0, 0, 3, 64);
        u_cam0.line_blank = 3;
        start_enabled();
        warm_camera(0);
        send_camera(0, 0, 0, 1);
        drain();
        check_reg('h220, 0);
        check_reg('h014, 0);
        u_cam0.line_blank = 16;
    endtask

    // VI-04: both cameras, all specified positive/negative row/column deviations.
    task automatic vi04();
        int deltas[4] = '{-64, -2, 2, 64};
        int row_deltas[4] = '{-10, -1, 1, 10};
        for (int source = 0; source < 2; source++) begin
            reset();
            configure_camera(source, 96, 16);
            configure_channel(0, source, 3, 192);
            start_enabled();
            warm_camera(source);
            for (int i = 0; i < 4; i++) begin
                send_camera(source, deltas[i]);
                drain();
                expect_error(4+source);
                clear_error();
                send_camera(source, 0, row_deltas[i]);
                drain();
                expect_error(4+source);
                clear_error();
                send_camera(source);
                drain();
                check_reg('h014, 0);
            end
            // Leave time for missing-row padding before the next frame's pixel bytes.
            if (source == 0) u_cam0.frame_blank = 1024;
            else u_cam1.frame_blank = 1024;
            send_camera(source, 0, 0, 0, 5);
            fork
                send_camera(source);
                drain();
            join
            drain();
            expect_error(4+source);
            if (source == 0) u_cam0.frame_blank = 32;
            else u_cam1.frame_blank = 32;
        end
    endtask

    // VI-05: independent cameras, same-source fanout and mid-frame shadow writes.
    task automatic vi05();
        reset();
        configure_camera(0, 64, 16);
        configure_camera(1, 64, 16);
        configure_channel(0, 0);
        configure_channel(1, 1);
        start_enabled();
        warm_camera(0);
        warm_camera(1);
        fork
            send_camera(0);
            send_camera(1);
        join
        drain();
        configure_channel(1, 0);
        send_camera(0);
        drain();
        check_reg('h224, 1);
        check_reg('h2a4, 1);
        fork
            send_camera(0);
            begin
                do @(posedge clk_mem);
                while (!(pix_in_valid && pix_in_ready && pix_in_sof));
                clocks(30);
                channel_base[0][3] = 'h03000000;
                configure_channel(0, 1, 4);
                channel_enable[1] = 0;
                write_reg('h280, 'h30);
            end
        join
        drain();
        send_camera(0);
        drain();
        check_reg('h050, 3);
        send_camera(1);
        drain();
        check_reg('h220, 'h7);
        // Clearing global ENABLE during a frame still completes that frame.
        fork
            send_camera(1);
            begin
                do @(posedge clk_mem);
                while (!(pix_in_valid && pix_in_ready && pix_in_sof));
                clocks(10);
                write_reg('h004, 0);
            end
        join
        drain();
        wait_idle();
    endtask

    // VI-06: enumerate every BUSY mask for every supported ring size, both channels.
    task automatic vi06();
        for (int ring = 2; ring <= 4; ring++) begin
            reset();
            configure_camera(0, 16, 2);
            configure_channel(0, 0, ring, 32);
            configure_channel(1, 0, ring, 32);
            start_enabled();
            warm_camera(0);
            for (int mask = 0; mask < 16; mask++) begin
                channel_busy[0] = 4'(mask);
                channel_busy[1] = 4'(15-mask);
                write_reg('h218, 32'(mask));
                write_reg('h298, 32'(15-mask));
                send_camera(0);
                drain();
                check_reg('h014, 0);
            end
            // SLOT_BUSY is sampled on allocation, even if changed during a frame.
            channel_busy[0] = 0;
            channel_busy[1] = 0;
            write_reg('h218, 0);
            write_reg('h298, 0);
            fork
                send_camera(0);
                begin
                    do @(posedge clk_mem);
                    while (!(pix_in_valid && pix_in_ready && pix_in_sof));
                    write_reg('h218, 'hf);
                    channel_busy[0] = 'hf;
                end
            join
            drain();
            send_camera(0);
            drain();
        end
    endtask

    // VI-07: a camera overfills 512 beats; the other source continues afterwards.
    task automatic vi07();
        for (int channel = 0; channel < 2; channel++) begin
            reset();
            configure_camera(0, 1280, 10);
            configure_camera(1, 32, 2);
            configure_channel(channel, 0, 3, 2560);
            configure_channel(1-channel, 1, 3, 64);
            start_enabled();
            warm_camera(0);
            warm_camera(1);
            @(negedge clk_mem);
            u_memory.stop_write = 1;
            check_pix_stream = 0;
            fork
                send_camera(0, 0, 0, 0, -1, 2'(1<<channel));
                begin
                    clocks(100);
                    send_camera(1);
                end
            join
            expect_error(1+channel);
            check_reg(12'('h058+4*channel), 1);
            check_reg(12'('h04c+4*channel), 0);
            @(negedge clk_mem);
            u_memory.stop_write = 0;
            wait_idle();
            drain();
            check_pix_stream = 1;
            send_camera(1);
            drain();
            // A dropped allocation is reused, not advanced.
            send_camera(0);
            drain();
            check_reg(channel_address(channel, 'h20), 0);
            write_reg('h004, 5);
            wait_idle();
        end
    endtask

    task automatic memory_done_edge(input int transactions_i);
        @(negedge clk_mem);
        apb.paddr = 'h010;
        apb.psel = 16'h0002;
        apb.penable = 0;
        apb.pwrite = 0;
        do begin
            @(posedge clk_mem);
            #0.001;
        end while (!apb.prdata[32]);
        equal("DONE after final read response", 32'(transactions_i), 32'(u_memory.r_count));
        @(negedge clk_mem);
        apb.psel = 0;
    endtask

    // VI-08: row-local reads, non-beat width and separate input/output strides.
    task automatic vi08();
        reset();
        configure_channel(0, 2, 3, 160);
        start_enabled();
        memory_frame();
        memory_done_edge(9);
        drain();
        check_memory_reads(34, 9, 128);
        check_reg('h224, 0);
    endtask

    // VI-09: source pauses under CH0/PIX backpressure; all accepted R beats drain.
    task automatic vi09();
        reset();
        configure_channel(0, 2, 3, 2560);
        start_enabled();
        u_memory.random_percent = 35;
        u_memory.stop_write = 1;
        pix_backpressure = 1;
        memory_frame(1280, 24, 2592);
        u_memory.check_read_ready = 1;
        clocks(20000);
        equal("memory pauses before reading entire Surface", 1,
            32'(u_memory.ar_count < 24*5));
        check_reg('h058, 0);
        check_reg('h014, 0);
        equal("memory urgent", 0, 32'(urgent_cycles));
        @(negedge clk_mem);
        u_memory.stop_write = 0;
        drain();
        u_memory.check_read_ready = 0;
        check_memory_reads(1280, 24, 2592);
    endtask

    // VI-10: busy START is ignored; an unselected memory frame is still read.
    task automatic vi10();
        reset();
        start_enabled();
        u_memory.stop_read = 1;
        memory_frame();
        check_reg('h120, 1);
        write_reg('h110, 'h09000000);
        write_reg('h11c, 1);
        @(negedge clk_mem);
        u_memory.stop_read = 0;
        wait_idle();
        check_memory_reads(34, 9, 128);
        check_reg('h048, 1);
        check_reg('h04c, 0);
        equal("unselected memory frame has no AW", 0, 32'(u_memory.aw_count));
        configure_channel(0, 2, 3, 128);
        memory_frame();
        drain();
        check_reg('h224, 1);
    endtask

    // VI-11: simultaneous sources under independent AW/W/B random delays.
    task automatic vi11();
        reset();
        configure_camera(0, 128, 12);
        configure_camera(1, 128, 12);
        configure_channel(0, 0, 3, 256);
        configure_channel(1, 1, 3, 256);
        start_enabled();
        warm_camera(0);
        warm_camera(1);
        u_memory.random_percent = 45;
        u_memory.check_continuous_w = 1;
        fork
            send_camera(0);
            send_camera(1);
        join
        drain();
        wait_idle();
    endtask

    // VI-12: block AW so FIFO occupancy necessarily crosses 256 but stays below 512.
    task automatic vi12();
        int initial_pixels;
        for (int channel = 0; channel < 2; channel++) begin
            reset();
            configure_camera(0, 1280, 5);
            configure_channel(channel, 0, 3, 2560);
            start_enabled();
            warm_camera(0);
            initial_pixels = camera_decoded[0];
            u_memory.stop_write = 1;
            fork
                send_camera(0);
                begin
                    do @(negedge clk_mem); while (!p1_urgent);
                    equal("urgent cannot precede 256 complete FIFO beats", 1,
                        32'(camera_decoded[0]-initial_pixels >= 256*16));
                    equal("urgent belongs to active camera frame", 0, 32'(cam0_vsync));
                    @(negedge clk_mem);
                    u_memory.stop_write = 0;
                end
            join
            drain();
            wait_idle();
            equal("camera urgent observed", 1, 32'(urgent_cycles > 0));
            equal("idle urgent", 0, 32'(p1_urgent));
            check_reg('h078, 32'(urgent_cycles));
        end
        reset();
        configure_channel(0, 2, 3, 2560);
        start_enabled();
        u_memory.stop_write = 1;
        memory_frame(1280, 8, 2560);
        clocks(15000);
        equal("memory source urgent", 0, 32'(urgent_cycles));
        u_memory.stop_write = 0;
        drain();
        check_reg('h078, 0);
    endtask

    // VI-13: abort camera and memory with outstanding requests, then resume.
    task automatic vi13();
        reset();
        configure_camera(0, 128, 32);
        configure_channel(0, 0, 3, 256);
        start_enabled();
        warm_camera(0);
        check_pix_stream = 0;
        fork
            send_camera(0, 0, 0, 0, -1, 1);
            begin
                wait (cam0_href);
                clocks(400);
                write_reg('h004, 5);
            end
        join
        wait_idle();
        check_reg('h004, 1);
        check_reg('h02c, 0);
        check_pix_stream = 1;
        send_camera(0);
        drain();
        check_reg('h220, 0);
        reset();
        configure_channel(0, 2, 3, 2560);
        start_enabled();
        u_memory.random_percent = 50;
        check_pix_stream = 0;
        memory_frame(1280, 100, 2560);
        expected[0].delete();
        reference.last_slot[0] = -1;
        clocks(100);
        write_reg('h004, 5);
        wait_idle();
        check_reg('h02c, 0);
        check_reg('h004, 1);
        check_pix_stream = 1;
        memory_frame(34, 9, 128);
        drain();
        check_reg('h220, 8);
        check_reg('h224, 1);
    endtask

    // VI-14: every implemented configuration and AXI response error code.
    task automatic vi14();
        int invalid_size[3] = '{'h00010000, 'h00010502, 'h00000040};
        int invalid_ctrl[4] = '{'h37, 'h01, 'h11, 'h51};
        for (int source = 0; source < 2; source++) begin
            for (int bad = 0; bad < 3; bad++) begin
                reset();
                configure_camera(source, 64, 8);
                configure_channel(0, source);
                start_enabled();
                warm_camera(source);
                write_reg(12'('h100+source*4), 32'(invalid_size[bad]));
                check_pix_stream = 0;
                // Keep sensor geometry valid while programming invalid expected geometry.
                send_camera(source, 0, 0, 0, -1, 3, 0, 0);
                clocks(300);
                expect_error(6);
                check_reg('h07c, 1);
                check_reg('h02c, 0);
                clear_error();
                configure_camera(source, 64, 8);
                check_pix_stream = 1;
                send_camera(source);
                drain();
            end
        end
        for (int bad = 0; bad < 3; bad++) begin
            reset();
            start_enabled();
            write_reg('h118, 32'(invalid_size[bad]));
            write_reg('h11c, 1);
            clocks(50);
            expect_error(7);
            check_reg('h07c, 1);
            check_reg('h120, 0);
            clear_error();
            configure_channel(0, 2);
            memory_frame();
            drain();
        end
        for (int bad = 0; bad < 4; bad++) begin
            reset();
            configure_camera(0, 64, 8);
            configure_channel(0, 0);
            start_enabled();
            warm_camera(0);
            write_reg('h200, 32'(invalid_ctrl[bad]));
            check_pix_stream = 0;
            send_camera(0, 0, 0, 0, -1, 3);
            clocks(300);
            expect_error(8);
            check_reg('h07c, 1);
            check_reg('h02c, 0);
            clear_error();
            configure_channel(0, 0);
            check_pix_stream = 1;
            send_camera(0);
            drain();
        end
        reset();
        configure_camera(0, 64, 8);
        configure_channel(0, 0);
        start_enabled();
        warm_camera(0);
        u_memory.b_error_transaction = 0;
        send_camera(0, 0, 0, 0, -1, 0, 1);
        drain();
        expect_error(9);
        check_reg('h220, 'h20);
        clear_error();
        send_camera(0);
        drain();
        reset();
        configure_channel(0, 2);
        start_enabled();
        u_memory.r_error_transaction = 0;
        memory_frame();
        drain();
        expect_error(10);
        check_reg('h220, 8);
        clear_error();
        memory_frame();
        drain();
    endtask

    // VI-15: complete reset map, alignment, RO, RW1C, CH2 registers and draining reset.
    task automatic vi15();
        reset();
        check_reg('h000, 'h00010001);
        check_reg('h004, 0);
        check_reg('h008, 2);
        check_reg('h00c, 0);
        check_reg('h010, 0);
        check_reg('h014, 0);
        check_reg('h02c, 0);
        check_reg('h100, 'h02d00500);
        check_reg('h104, 'h02d00500);
        check_reg('h110, 0);
        check_reg('h114, 'ha00);
        check_reg('h118, 'h02d00500);
        check_reg('h120, 0);
        for (int i = 0; i < 16; i++) check_reg(12'('h040+4*i), 0);
        for (int c = 0; c < 3; c++) begin
            check_reg(channel_address(c, 0), 'h30);
            check_reg(channel_address(c, 4), 'ha00);
            for (int s = 0; s < 4; s++) check_reg(channel_address(c, 8+s*4), 0);
            check_reg(channel_address(c, 'h18), 0);
            check_reg(channel_address(c, 'h20), 0);
            check_reg(channel_address(c, 'h24), 0);
            check_reg(channel_address(c, 'h28), 0);
            write_reg(channel_address(c, 4), 'h0000ffff, 0);
            check_reg(channel_address(c, 4), 'hffe0);
            for (int s = 0; s < 4; s++) begin
                write_reg(channel_address(c, 8+s*4), 'h12345fff);
                check_reg(channel_address(c, 8+s*4), 'h12345000);
            end
        end
        // spec vin 4.3: CH2 has the same writable and read-only register layout.
        write_reg('h300, 'hffffffff);
        check_reg('h300, 'h77);
        write_reg('h300, 'h30);
        write_reg('h318, 'hffffffff);
        check_reg('h318, 'hf);
        write_reg('h318, 0);
        for (int offset = 'h20; offset <= 'h28; offset += 4) begin
            write_reg(12'('h300+offset), 'hffffffff);
            check_reg(12'('h300+offset), 0);
        end
        write_reg('h31c, 'hffffffff);
        check_reg('h31c, 0);
        for (int address = 'h32c; address < 'h380; address += 4) begin
            write_reg(12'(address), 'hffffffff);
            check_reg(12'(address), 0);
        end
        for (int address = 'h020; address <= 'h028; address += 4) begin
            write_reg(12'(address), 'hffffffff);
            check_reg(12'(address), 0);
        end
        write_reg('h3fc, 'hffffffff);
        check_reg('h3fc, 0);
        write_reg('h000, 'hffffffff);
        check_reg('h000, 'h00010001);
        write_reg('h004, 2);
        check_reg('h004, 0);
        check_reg('h008, 2);
        write_reg('h008, 'hffffffff);
        check_reg('h008, 2);
        write_reg('h02c, 'hffffffff);
        check_reg('h02c, 0);
        write_reg('h04c, 'hffffffff);
        check_reg('h04c, 0);
        write_reg('h220, 'hffffffff);
        check_reg('h220, 0);
        write_reg('h224, 'hffffffff);
        check_reg('h224, 0);
        write_reg('h110, 'h12345fff);
        check_reg('h110, 'h12345000);
        write_reg('h114, 'hffff);
        check_reg('h114, 'hffe0);
        write_reg('h100, 'h00010003);
        check_reg('h100, 'h00010002);
        write_reg('h104, 'h00010003);
        check_reg('h104, 'h00010002);
        write_reg('h118, 'h00010003);
        check_reg('h118, 'h00010002);
        configure_camera(0, 64, 8);
        configure_channel(0, 0);
        start_enabled();
        warm_camera(0);
        send_camera(0, -2);
        drain();
        expect_error(4);
        write_reg('h00c, 0);
        equal("IRQ mask", 0, 32'(irq));
        write_reg('h00c, 2);
        equal("IRQ unmask", 1, 32'(irq));
        clear_error();
        equal("IRQ clear", 0, 32'(irq));
        // SOFT_RST must drain accepted AXI transfers before restoring defaults.
        u_memory.hold_b = 1;
        check_pix_stream = 0;
        fork
            send_camera(0, 0, 0, 0, -1, 1);
            begin
                do @(posedge clk_mem); while (!(axi.awvalid && axi.awready));
                write_reg('h004, 9);
                clocks(40);
                u_memory.hold_b = 0;
            end
        join
        wait_idle();
        check_reg('h004, 0);
        check_reg('h100, 'h02d00500);
        check_reg('h200, 'h30);
        check_reg('h300, 'h30);
        check_reg('h304, 'ha00);
        for (int s = 0; s < 4; s++) check_reg(12'('h308+s*4), 0);
        check_reg('h318, 0);
        check_reg('h320, 0);
        check_reg('h324, 0);
        check_reg('h328, 0);
        check_reg('h02c, 0);
        check_reg('h010, 0);
        for (int i = 0; i < 16; i++) check_reg(12'('h040+4*i), 0);
        reference.reset();
        global_enable = 0;
        pix_frames.delete();
        pix_word = 0;
        check_pix_stream = 1;
        foreach (source_count[i]) source_count[i] = 0;
        foreach (complete_count[i]) begin
            complete_count[i] = 0;
            skip_count[i] = 0;
            incomplete_count[i] = 0;
        end
        configure_camera(0, 64, 8);
        configure_channel(0, 0);
        start_enabled();
        warm_camera(0);
        send_camera(0);
        drain();
        check_reg('h224, 0);
        check_reg('h220, 0);
    endtask

    // VI-16: specified PCLK frequencies, independent phases against 125MHz memory.
    task automatic vi16();
        realtime half_periods[3] = '{20.833333, 10.416667, 5.952381};
        for (int frequency = 0; frequency < 3; frequency++) begin
            u_cam0.half_period_ns = half_periods[frequency];
            u_cam1.half_period_ns = half_periods[2-frequency];
            clocks(1+int'(rng[3:0]));
            vi01();
            reset();
            configure_camera(0, 64, 8);
            configure_camera(1, 64, 8);
            configure_channel(0, 0);
            configure_channel(1, 1);
            start_enabled();
            warm_camera(0);
            warm_camera(1);
            fork
                send_camera(0);
                send_camera(1);
            join
            drain();
        end
        u_cam0.half_period_ns = 10.416667;
        u_cam1.half_period_ns = 10.416667;
    endtask

    // VI-17: ten seeds, both sources, malformed dimensions, slots and memory interleave.
    task automatic vi17();
        int width[2];
        int height[2];
        int dx;
        int dy;
        int source;
        // With every slot busy, missing-row padding still completes source accounting.
        reset();
        configure_camera(1, 1044, 18);
        configure_channel(1, 1, 2, 2112);
        channel_busy[1] = 3;
        write_reg('h298, 3);
        start_enabled();
        warm_camera(1);
        send_camera(1, 0, -1);
        drain();
        for (int seed = 1; seed <= 10; seed++) begin
            reset();
            rng = 32'(seed*9733);
            u_memory.random_state = rng;
            u_memory.random_percent = 40;
            for (int camera = 0; camera < 2; camera++) begin
                rng = u_memory.random_next(rng);
                width[camera] = 2+2*int'(rng%640);
                height[camera] = 2+int'((rng>>10)%18);
                if (seed == 1 && camera == 0) width[camera] = 2;
                if (seed == 10 && camera == 1) width[camera] = 1280;
                configure_camera(camera, width[camera], height[camera]);
                configure_channel(camera, camera, 2+seed%3,
                    ((width[camera]*2+31)/32)*32);
            end
            start_enabled();
            warm_camera(0);
            warm_camera(1);
            for (int iteration = 0; iteration < 6; iteration++) begin
                rng = u_memory.random_next(rng);
                source = int'(rng[0]);
                dx = rng[1] ? 2 : 0;
                dy = rng[2] ? -1 : 0;
                channel_busy[source] = rng[7:4];
                write_reg(channel_address(source, 'h18), 32'(channel_busy[source]));
                if (iteration == 3) begin
                    u_memory.stop_write = 1;
                    fork
                        send_camera(source, dx, dy);
                        begin
                            clocks(200);
                            u_memory.stop_write = 0;
                        end
                    join
                end else if (iteration == 4) begin
                    fork
                        send_camera(0, dx, dy);
                        send_camera(1, width[1] > 2 ? -dx : dx, dy);
                    join
                end else send_camera(source, dx, dy);
                drain();
                clear_error();
                if (iteration == 2) begin
                    // Memory frames interleave with camera frames within the same seed.
                    configure_channel(0, 2, 3, ((width[0]*2+31)/32)*32);
                    channel_busy[0] = 0;
                    write_reg('h218, 0);
                    memory_frame(width[0], height[0], ((width[0]*2+31)/32)*32+32);
                    drain();
                    write_reg('h010, 1);
                    configure_channel(0, 0, 2+seed%3, ((width[0]*2+31)/32)*32);
                end
            end
            wait_idle();
            $display("VI-17 seed=%0d PASS", seed);
        end
    endtask

    // Separate SV processes keep each generated C++ coroutine small on the 3-core host.
    // Only the requested test runs; its completion returns control to the single runner.
    generate
        if (HARNESS_SELFTEST == 0) begin : g_functional
            initial begin
                forever begin
                    wait (requested_test == 1);
                    vi01();
                    finished_test = 1;
                    wait (requested_test == 0);
                end
            end
            initial begin
                forever begin
                    wait (requested_test == 2);
                    vi02();
                    finished_test = 2;
                    wait (requested_test == 0);
                end
            end
            initial begin
                forever begin
                    wait (requested_test == 3);
                    vi03();
                    finished_test = 3;
                    wait (requested_test == 0);
                end
            end
            initial begin
                forever begin
                    wait (requested_test == 4);
                    vi04();
                    finished_test = 4;
                    wait (requested_test == 0);
                end
            end
            initial begin
                forever begin
                    wait (requested_test == 5);
                    vi05();
                    finished_test = 5;
                    wait (requested_test == 0);
                end
            end
            initial begin
                forever begin
                    wait (requested_test == 6);
                    vi06();
                    finished_test = 6;
                    wait (requested_test == 0);
                end
            end
            initial begin
                forever begin
                    wait (requested_test == 7);
                    vi07();
                    finished_test = 7;
                    wait (requested_test == 0);
                end
            end
            initial begin
                forever begin
                    wait (requested_test == 8);
                    vi08();
                    finished_test = 8;
                    wait (requested_test == 0);
                end
            end
            initial begin
                forever begin
                    wait (requested_test == 9);
                    vi09();
                    finished_test = 9;
                    wait (requested_test == 0);
                end
            end
            initial begin
                forever begin
                    wait (requested_test == 10);
                    vi10();
                    finished_test = 10;
                    wait (requested_test == 0);
                end
            end
            initial begin
                forever begin
                    wait (requested_test == 11);
                    vi11();
                    finished_test = 11;
                    wait (requested_test == 0);
                end
            end
            initial begin
                forever begin
                    wait (requested_test == 12);
                    vi12();
                    finished_test = 12;
                    wait (requested_test == 0);
                end
            end
            initial begin
                forever begin
                    wait (requested_test == 13);
                    vi13();
                    finished_test = 13;
                    wait (requested_test == 0);
                end
            end
            initial begin
                forever begin
                    wait (requested_test == 14);
                    vi14();
                    finished_test = 14;
                    wait (requested_test == 0);
                end
            end
            initial begin
                forever begin
                    wait (requested_test == 15);
                    vi15();
                    finished_test = 15;
                    wait (requested_test == 0);
                end
            end
            initial begin
                forever begin
                    wait (requested_test == 16);
                    vi16();
                    finished_test = 16;
                    wait (requested_test == 0);
                end
            end
            initial begin
                forever begin
                    wait (requested_test == 17);
                    vi17();
                    finished_test = 17;
                    wait (requested_test == 0);
                end
            end
        end
    endgenerate

    task automatic run_test(input int number_i);
        current_test = number_i;
        if (number_i < 1 || number_i > 17)
            $fatal(1, "FAIL testcase expected=1..17 actual=%0d time=%0t", number_i, $time);
        $display("VI-%02d BEGIN time=%0t", number_i, $time);
        @(negedge clk_mem);
        requested_test = number_i;
        do @(negedge clk_mem); while (finished_test != number_i);
        requested_test = 0;
        @(negedge clk_mem);
        $display("VI-%02d PASS time=%0t", number_i, $time);
    endtask

    task automatic harness_selftest();
        logic [15:0] image[];
        int old_count;
        reference_selftest();
        image = new[16];
        foreach (image[i]) image[i] = 16'('h1234+i*'h101);
        old_count = camera_decoded[0];
        u_cam0.send_frame(8, 2, image, 0, 0, 1);
        equal("camera0 task returned idle", 0, 32'(u_cam0.transmitting));
        equal("harness camera0 decode count", 16, 32'(camera_decoded[0]-old_count));
        old_count = camera_decoded[1];
        u_cam1.send_frame(8, 2, image);
        equal("camera1 task returned idle", 0, 32'(u_cam1.transmitting));
        equal("harness camera1 decode count", 16, 32'(camera_decoded[1]-old_count));
        u_memory.poke16('h1000, 'hbeef);
        equal("memory little-endian low", 'hef, 32'(u_memory.peek('h1000)));
        equal("memory little-endian high", 'hbe, 32'(u_memory.peek('h1001)));
        $display("PASS VIN HARNESS SELFTEST (no VIN functional result)");
    endtask

    initial begin
        reference = new;
        apb.psel = 0;
        apb.penable = 0;
        apb.paddr = 0;
        apb.pwrite = 0;
        apb.pwdata = 0;
        apb.pstrb = 0;
        // Distinct initial phases are configurable independently of frequency.
        u_cam0.phase_ns = 1.271;
        u_cam1.phase_ns = 3.619;
        if ($value$plusargs("CASE=%s", selected_case)) begin end
        full_size = selected_case == "full";
        if (HARNESS_SELFTEST != 0) harness_selftest();
        else if (selected_case == "smoke" || full_size) begin
            for (int test = 1; test <= 17; test++) begin
                if (full_size || (test <= 8 || test == 11 || test == 14 || test == 15))
                    run_test(test);
            end
            $display("PASS VIN %s", selected_case);
        end else run_test(selected_case.atoi());
        $finish;
    end
    initial begin
        #2000000000;
        $fatal(1, "FAIL timeout expected=finished actual=VI-%02d time=%0t",
            current_test, $time);
    end
endmodule
