// File: edrv32_vin_ch2_tb.sv
// Spec: vin 2.4, 2.6-2.9, 4, 6; vin-testplan VI-19 through VI-23.
// Description: Independent CH2 byte scoreboard with real DVP and shared P1 traffic.
// Clock domain: clk_mem=125MHz, independently phased camera PCLK=48MHz.
`timescale 1ns/1ps
module edrv32_vin_ch2_tb #(parameter int HARNESS_SELFTEST = 0);
    logic clk_mem = 0;
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
    int checker_errors;
    int current_test = 0;
    int width = 1280;
    int height = 720;
    int completed[3];
    int camera_pixels = 0;
    bit camera_phase = 0;
    bit forbid_urgent = 0;
    string directory;
    string selected_case = "smoke";
    logic [15:0] loaded_input[921600];
    logic [15:0] loaded_small[512];
    logic [31:0] packed_output[245760];
    logic [15:0] image[];
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

    // CH0 uses the specified bypass; CH2 must consume the source before PIX.
    assign pix_in_ready = pix_out_ready;
    assign pix_out_valid = pix_in_valid;
    assign pix_out_data = pix_in_data;
    assign pix_out_sof = pix_in_sof;
    assign pix_out_eol = pix_in_eol;
    assign pix_out_eof = pix_in_eof;
    always @(posedge cam0_pclk) begin
        if (cam0_href) begin
            if (camera_phase) camera_pixels++;
            camera_phase = !camera_phase;
        end else camera_phase = 0;
    end
    always @(posedge clk_mem) begin
        if (rst_mem_n && forbid_urgent && p1_urgent)
            $fatal(1, "FAIL VI-%0d CH2 urgent expected=0 actual=1 time=%0t",
                current_test, $time);
    end

    task automatic equal(input string name_i,
        input bit [31:0] expected_i,
        input bit [31:0] actual_i);
        if (actual_i != expected_i)
            $fatal(1, "FAIL VI-%0d %s expected=%h actual=%h time=%0t",
                current_test, name_i, expected_i, actual_i, $time);
    endtask

    task automatic clocks(input int cycles_i);
        repeat (cycles_i) @(negedge clk_mem);
    endtask

    task automatic access(input bit write_i,
        input bit [11:0] address_i,
        input bit [31:0] data_i,
        output bit [31:0] data_o);
        @(negedge clk_mem);
        apb.paddr = address_i;
        apb.psel = 16'h0002;
        apb.penable = 0;
        apb.pwrite = write_i;
        apb.pwdata = data_i;
        apb.pstrb = 4'hf;
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
        $fatal(1, "FAIL APB timeout addr=%h expected=PREADY actual=0 time=%0t",
            address_i, $time);
    endtask

    task automatic write_reg(input bit [11:0] address_i,
        input bit [31:0] data_i);
        bit [31:0] unused_data;
        access(1, address_i, data_i, unused_data);
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
        return 12'('h200+128*channel_i+offset_i);
    endfunction

    function automatic bit [31:0] base(input int channel_i, input int slot_i);
        return 32'('h01000000+channel_i*'h01000000+slot_i*'h00400000);
    endfunction

    function automatic int stride(input int channel_i);
        return channel_i == 2 ? 2592 : width*2+32;
    endfunction

    task automatic reset(input bit small_i = 0);
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
        u_memory.check_read_ready = 0;
        u_memory.check_continuous_w = 1;
        forbid_urgent = 0;
        foreach (completed[c]) completed[c] = 0;
        width = small_i ? 64 : 1280;
        height = small_i ? 8 : 720;
        clocks(20);
        rst_mem_n = 1;
        @(negedge cam0_pclk);
        rst_cam0_n = 1;
        @(negedge cam1_pclk);
        rst_cam1_n = 1;
        clocks(30);
        if (HARNESS_SELFTEST == 0) begin
            write_reg('h100, 32'((height<<16)|width));
            write_reg('h00c, 'h307);
        end
    endtask

    task automatic load_image(input int variant_i);
        image = new[width*height];
        if (width == 64) begin
            $readmemh($sformatf("%s/small.hex", directory), loaded_small);
            foreach (image[i]) image[i] = loaded_small[i];
        end else begin
            $readmemh($sformatf("%s/in%0d.hex", directory, variant_i), loaded_input);
            foreach (image[i]) image[i] = loaded_input[i];
            $readmemh($sformatf("%s/out%0d.hex", directory, variant_i), packed_output);
        end
    endtask

    task automatic configure(input int channel_i, input int source_i);
        write_reg(channel_address(channel_i, 0), 32'('h31|(source_i<<1)));
        write_reg(channel_address(channel_i, 4), 32'(stride(channel_i)));
        for (int s = 0; s < 4; s++)
            write_reg(channel_address(channel_i, 8+s*4), base(channel_i, s));
    endtask

    task automatic warm_camera();
        write_reg('h004, 1);
        repeat (2) u_cam0.send_frame(width, height, image);
        clocks(100);
        check_reg('h040, 0);
        equal("two initial frames discarded AW", 0, 32'(u_memory.aw_count));
    endtask

    task automatic start_memory();
        for (int y = 0; y < height; y++) begin
            for (int x = 0; x < width; x++)
                u_memory.poke16('h08000000+32'(y*(width*2+64)+x*2), image[y*width+x]);
        end
        write_reg('h110, 'h08000000);
        write_reg('h114, 32'(width*2+64));
        write_reg('h118, 32'((height<<16)|width));
        write_reg('h11c, 1);
    endtask

    task automatic wait_irq(input bit [31:0] mask_i);
        bit [31:0] actual;
        bit [31:0] diagnostic;
        for (int cycle = 0; cycle < 300000; cycle++) begin
            read_reg('h010, actual);
            if ((actual & mask_i) == mask_i) return;
        end
        read_reg('h008, diagnostic);
        $display("STATUS=%h", diagnostic);
        read_reg('h014, diagnostic);
        $display("ERR_CODE=%h", diagnostic);
        read_reg('h120, diagnostic);
        $display("MSRC_STAT=%h", diagnostic);
        for (int p = 0; p < 16; p++) begin
            read_reg(12'('h040+4*p), diagnostic);
            $display("PERF%0d=%0d", p, diagnostic);
        end
        for (int c = 0; c < 3; c++) begin
            for (int offset = 'h20; offset <= 'h28; offset += 4) begin
                read_reg(channel_address(c, offset), diagnostic);
                $display("CH%0d offset=%h value=%h", c, offset, diagnostic);
            end
        end
        $fatal(1, "FAIL VI-%0d IRQ expected mask=%h actual=%h time=%0t",
            current_test, mask_i, actual, $time);
    endtask

    task automatic wait_idle();
        bit [31:0] actual;
        for (int cycle = 0; cycle < 300000; cycle++) begin
            read_reg('h008, actual);
            if ((actual & 3) == 2) begin
                equal("AW/B drained", 32'(u_memory.aw_count), 32'(u_memory.b_count));
                equal("AR/R drained", 32'(u_memory.ar_count), 32'(u_memory.r_count));
                equal("protocol checker", 0, 32'(checker_errors));
                return;
            end
        end
        $fatal(1, "FAIL VI-%0d IDLE expected=2 actual=%h time=%0t",
            current_test, actual, $time);
    endtask

    task automatic compare_surface(input int channel_i, input int slot_i);
        int rows;
        int line_bytes;
        bit [31:0] address;
        bit [31:0] pixel;
        bit [7:0] expected_byte;
        rows = channel_i == 2 ? 384 : height;
        line_bytes = channel_i == 2 ? 2560 : width*2;
        for (int y = 0; y < rows; y++) begin
            for (int b = 0; b < stride(channel_i); b++) begin
                address = base(channel_i, slot_i)+32'(y*stride(channel_i)+b);
                if (b >= line_bytes) expected_byte = 'ha5;
                else if (channel_i == 2) begin
                    pixel = packed_output[y*640+b/4];
                    expected_byte = pixel[(b%4)*8+:8];
                end else begin
                    expected_byte = image[y*width+b/2][(b%2)*8+:8];
                end
                equal($sformatf("CH%0d slot%0d y%0d byte%0d addr%h",
                    channel_i, slot_i, y, b, address), 32'(expected_byte),
                    32'(u_memory.peek(address)));
            end
        end
    endtask

    task automatic complete(input int channel_i, input int slot_i,
        input int source_i, input int id_i);
        bit [31:0] mask;
        bit [31:0] final_address;
        bit final_b_seen;
        mask = channel_i == 2 ? 'h200 : 4;
        wait_irq(mask);
        // The final B must have completed before publishing completion status.
        final_address = base(channel_i, slot_i)+32'(channel_i == 2
            ? 383*stride(2)+2528 : (height-1)*stride(0)+((width*2-1)/32)*32);
        final_b_seen = 0;
        for (int i = 0; i < u_memory.b_count; i++) begin
            if (u_memory.aw_addresses[i]+32'((u_memory.aw_lengths[i]-1)*32)
                == final_address) final_b_seen = 1;
        end
        equal("completion after last B", 1, 32'(final_b_seen));
        equal("enabled completion IRQ", 1, 32'(irq));
        check_reg(channel_address(channel_i, 'h20), 32'(slot_i|(source_i<<2)));
        check_reg(channel_address(channel_i, 'h24), 32'(id_i));
        compare_surface(channel_i, slot_i);
        completed[channel_i]++;
        check_reg(12'('h04c+4*channel_i), 32'(completed[channel_i]));
        write_reg('h010, mask);
    endtask

    task automatic check_error(input int code_i);
        wait_irq(2);
        check_reg('h014, 32'(code_i));
        equal("enabled error IRQ", 1, 32'(irq));
    endtask

    task automatic vi19();
        current_test = 19;
        reset();
        load_image(0);
        configure(0, 0);
        configure(2, 0);
        u_memory.random_percent = 35;
        warm_camera();
        for (int frame = 0; frame < 3; frame++) begin
            load_image(frame);
            u_cam0.send_frame(width, height, image);
            complete(0, frame, 0, frame);
            complete(2, frame, 0, frame);
            check_reg('h224, 32'(frame));
            check_reg('h324, 32'(frame));
        end
        check_reg('h040, 3);
        check_reg('h010, 0);
        wait_idle();
        $display("PASS VI-19 CH0/CH2 same source, three surfaces, slots and IDs");
    endtask

    task automatic vi20();
        current_test = 20;
        reset();
        load_image(1);
        configure(0, 2);
        configure(2, 2);
        // vin v0.3: memory frames use CH2 backpressure. VI-21 adds write-stop
        // and top-padding pacing checks to this complete-frame baseline.
        u_memory.check_read_ready = 1;
        forbid_urgent = 1;
        write_reg('h004, 1);
        start_memory();
        complete(0, 0, 2, 0);
        complete(2, 0, 2, 0);
        wait_irq(1);
        check_reg('h048, 1);
        check_reg('h324, 0);
        check_reg('h224, 0);
        check_reg('h010, 1);
        check_reg('h014, 0);
        check_reg('h058, 0);
        check_reg('h060, 0);
        wait_idle();
        $display("PASS VI-20 memory -> CH0/CH2, no read backpressure");
    endtask

    // vin v0.3: cameras still drop on valid-data overflow; memory frames pause.
    task automatic vi21_camera_overflow(input bit both_i);
        int before_pixels;
        bit [31:0] status;
        current_test = 21;
        reset();
        load_image(0);
        configure(2, 0);
        if (both_i) configure(0, 0);
        forbid_urgent = !both_i;
        warm_camera();
        u_memory.stop_write = 1;
        before_pixels = camera_pixels;
        u_cam0.send_frame(width, height, image);
        equal("camera not backpressured", 32'(width*height),
            32'(camera_pixels-before_pixels));
        wait_irq(2);
        check_reg('h060, 1);
        check_reg('h054, 0);
        check_reg('h320, 0);
        check_reg('h324, 0);
        if (!both_i) check_error(3);
        else begin
            check_reg('h058, 1);
            check_reg('h04c, 0);
        end
        read_reg('h010, status);
        equal("no dropped-frame completion", 0, status & 'h204);
        u_memory.stop_write = 0;
        wait_idle();
        check_reg('h054, 0);
        if (both_i) check_reg('h04c, 0);
        read_reg('h010, status);
        equal("no completion after abort drain", 0, status & 'h204);
        write_reg('h010, 'h3ff);
        load_image(2);
        u_cam0.send_frame(width, height, image);
        if (both_i) complete(0, 0, 0, 1);
        complete(2, 0, 0, 1);
        check_reg('h060, 1);
        check_reg('h014, 0);
        check_reg('h054, 1);
        wait_idle();
        $display("PASS VI-21%c camera drop, drain, slot reuse, recovery", both_i ? "c" : "a");
        $fflush();
    endtask

    task automatic vi21_memory_backpressure();
        int paused_reads;
        current_test = 21;
        reset();
        load_image(0);
        configure(2, 2);
        forbid_urgent = 1;
        u_memory.check_read_ready = 1;
        write_reg('h004, 1);
        u_memory.stop_write = 1;
        start_memory();
        // Long enough to fill the write FIFO and both memory-source input lines.
        clocks(20000);
        check_reg('h060, 0);
        check_reg('h014, 0);
        check_reg('h120, 1);
        check_reg('h054, 0);
        equal("VI-21b no AW during write stop", 0, 32'(u_memory.aw_count));
        paused_reads = u_memory.ar_count;
        clocks(4096);
        equal("VI-21b memory-source reads paused", 32'(paused_reads), 32'(u_memory.ar_count));
        u_memory.stop_write = 0;
        complete(2, 0, 2, 0);
        wait_irq(1);
        check_reg('h048, 1);
        check_reg('h060, 0);
        check_reg('h014, 0);
        wait_idle();
        $display("PASS VI-21b memory pauses, RREADY stays high, complete CH2 bytes");
        $fflush();
    endtask

    task automatic vi21_padding();
        current_test = 21;
        reset();
        load_image(0);
        configure(2, 0);
        forbid_urgent = 1;
        warm_camera();
        u_memory.stop_write = 1;
        fork
            begin
                u_cam0.send_frame(width, height, image);
            end
            begin : release_before_active_output
                bit [31:0] frames;
                // PERF0 marks the source SOF through the public APB interface.
                frames = 0;
                for (int cycle = 0; cycle < 300000 && frames == 0; cycle++)
                    read_reg('h040, frames);
                equal("VI-21d source SOF", 1, frames);
                clocks(1500);
                check_reg('h060, 0);
                check_reg('h014, 0);
                u_memory.stop_write = 0;
            end
        join
        complete(2, 0, 0, 0);
        check_reg('h060, 0);
        check_reg('h014, 0);
        wait_idle();
        $display("PASS VI-21d top padding paced while writes stop for 1500 cycles");
        $fflush();
    endtask

    task automatic vi21_memory_fullspeed();
        current_test = 21;
        reset();
        load_image(0);
        configure(0, 2);
        configure(2, 2);
        forbid_urgent = 1;
        u_memory.check_read_ready = 1;
        write_reg('h004, 1);
        start_memory();
        wait_irq('h204);
        check_reg('h058, 0);
        check_reg('h060, 0);
        check_reg('h014, 0);
        complete(0, 0, 2, 0);
        complete(2, 0, 2, 0);
        check_reg('h224, 0);
        check_reg('h324, 0);
        wait_irq(1);
        check_reg('h048, 1);
        wait_idle();
        $display("PASS VI-21e full-speed memory -> CH0/CH2, no overflow, complete bytes");
        $fflush();
    endtask

    task automatic vi21();
        if (selected_case == "full" || selected_case == "21" || selected_case == "21a")
            vi21_camera_overflow(0);
        if (selected_case == "full" || selected_case == "21" || selected_case == "21b")
            vi21_memory_backpressure();
        if (selected_case == "full" || selected_case == "21" || selected_case == "21c")
            vi21_camera_overflow(1);
        if (selected_case == "full" || selected_case == "21" || selected_case == "21d")
            vi21_padding();
        if (selected_case == "full" || selected_case == "21" || selected_case == "21e")
            vi21_memory_fullspeed();
    endtask

    task automatic vi22();
        int before_aw;
        current_test = 22;
        reset(1);
        load_image(0);
        configure(0, 0);
        configure(2, 0);
        warm_camera();
        before_aw = u_memory.aw_count;
        u_cam0.send_frame(width, height, image);
        complete(0, 0, 0, 0);
        check_error(8);
        check_reg('h07c, 1);
        check_reg('h054, 0);
        check_reg('h320, 0);
        check_reg('h324, 0);
        check_reg('h328, 0);
        check_reg('h010, 2);
        // Only CH0's surface may have been submitted on the shared write interface.
        for (int i = before_aw; i < u_memory.aw_count; i++)
            equal("invalid CH2 no AW", base(0, 0)>>22, u_memory.aw_addresses[i]>>22);
        wait_idle();
        $display("PASS VI-22 invalid CH2 source size, CH0 intact");
    endtask

    task automatic vi23();
        int before_pixels;
        int before_aw;
        current_test = 23;
        reset();
        load_image(0);
        configure(2, 0);
        forbid_urgent = 1;
        warm_camera();
        write_reg('h318, 7);
        u_cam0.send_frame(width, height, image);
        clocks(100);
        check_reg('h06c, 1);
        check_reg('h054, 0);
        equal("all slots busy no AW", 0, 32'(u_memory.aw_count));
        write_reg('h318, 2);
        before_pixels = camera_pixels;
        fork
            u_cam0.send_frame(width, height, image);
            begin
                wait (camera_pixels >= before_pixels+1280*20);
                // The current frame retains slot zero; the next frame sees busy bits 0/2.
                write_reg('h318, 5);
            end
        join
        complete(2, 0, 0, 1);
        u_cam0.send_frame(width, height, image);
        complete(2, 1, 0, 2);
        write_reg('h318, 7);
        before_aw = u_memory.aw_count;
        u_cam0.send_frame(width, height, image);
        clocks(100);
        check_reg('h06c, 2);
        check_reg('h054, 2);
        equal("second busy frame no AW", 32'(before_aw), 32'(u_memory.aw_count));
        write_reg('h318, 0);
        for (int frame = 4; frame <= 5; frame++) begin
            u_cam0.send_frame(width, height, image);
            complete(2, frame == 4 ? 2 : 0, 0, frame);
        end
        check_reg('h06c, 2);
        check_reg('h054, 4);
        check_reg('h040, 6);
        check_reg('h010, 0);
        wait_idle();
        $display("PASS VI-23 busy skip and live SLOT_BUSY, slots 0/1/2/0");
    endtask

    task automatic harness_selftest();
        current_test = 0;
        reset(1);
        load_image(0);
        u_cam0.send_frame(width, height, image);
        equal("DVP decoder pixels", 512, 32'(camera_pixels));
        equal("camera0 task idle", 0, 32'(u_cam0.transmitting));
        equal("camera1 task idle", 0, 32'(u_cam1.transmitting));
        u_memory.poke16('h1000, 'h5739);
        equal("RAM low byte", 'h39, 32'(u_memory.peek('h1000)));
        equal("RAM high byte", 'h57, 32'(u_memory.peek('h1001)));
        // Exercise the complete byte/stride scoreboard using model data, not the DUT.
        for (int y = 0; y < height; y++) begin
            for (int x = 0; x < width; x++)
                u_memory.poke16(base(0, 0)+32'(y*stride(0)+2*x), image[y*width+x]);
        end
        compare_surface(0, 0);
        foreach (packed_output[i]) packed_output[i] = 'h007f3955;
        for (int y = 0; y < 384; y++) begin
            for (int x = 0; x < 640; x++) begin
                u_memory.poke16(base(2, 0)+32'(y*stride(2)+4*x), 'h3955);
                u_memory.poke16(base(2, 0)+32'(y*stride(2)+4*x+2), 'h007f);
            end
        end
        compare_surface(2, 0);
        $display("PASS CH2 harness selftest (no VIN functional result)");
    endtask

    // Keep the full-size cases in separate processes to limit generated C++ coroutine size.
    int requested = 0;
    int finished = 0;
    generate
        if (HARNESS_SELFTEST == 0) begin : g_functional
            initial forever begin
                wait (requested == 19);
                vi19();
                finished = 19;
                wait (requested == 0);
            end
            initial forever begin
                wait (requested == 20);
                vi20();
                finished = 20;
                wait (requested == 0);
            end
            initial forever begin
                wait (requested == 21);
                vi21();
                finished = 21;
                wait (requested == 0);
            end
            initial forever begin
                wait (requested == 22);
                vi22();
                finished = 22;
                wait (requested == 0);
            end
            initial forever begin
                wait (requested == 23);
                vi23();
                finished = 23;
                wait (requested == 0);
            end
        end
    endgenerate
    task automatic run_test(input int number_i);
        requested = number_i;
        $display("VI-%0d BEGIN time=%0t", requested, $time);
        $fflush();
        wait (finished == number_i);
        requested = 0;
        clocks(1);
    endtask

    initial begin
        u_cam0.phase_ns = 1.271;
        u_cam1.phase_ns = 3.619;
        if (!$value$plusargs("DIR=%s", directory))
            $fatal(1, "FAIL expected=+DIR actual=missing time=%0t", $time);
        if ($value$plusargs("CASE=%s", selected_case)) begin end
        if (HARNESS_SELFTEST != 0) harness_selftest();
        else begin
            for (int test = 19; test <= 23; test++) begin
                if (selected_case == "full" || (selected_case == "smoke" && test == 22)
                    || selected_case.atoi() == test) begin
                    run_test(test);
                end
            end
            $display("PASS VIN CH2 %s", selected_case);
        end
        $finish;
    end
    initial begin
        #2000000000;
        $fatal(1, "FAIL VI-%0d timeout expected=finished actual=running time=%0t",
            current_test, $time);
    end
endmodule
