// File: edrv32_aud_tb.sv
// Spec: aud-spec 2-6; aud-testplan AT-01..AT-09.
// Description: Independent APB-driven AUD tests with a software-owned ring mirror.
//              Only public APB, AXI and I2S interfaces participate in checking.
// Clock domain: clk_mem 125 MHz; clk_aud 12.288 MHz with randomized initial phase.
`timescale 1ns/1ps
module edrv32_aud_tb;
    /* verilator lint_off UNUSEDPARAM */
    `include "edrv32_aud_regs.vh"
    /* verilator lint_on UNUSEDPARAM */
    logic clk_mem;
    logic clk_aud;
    logic rst_mem_n = 0;
    logic rst_aud_n = 0;
    logic [11:0] paddr = 0;
    logic psel = 0;
    logic penable = 0;
    logic pwrite = 0;
    logic [31:0] pwdata = 0;
    logic [31:0] prdata;
    logic pready;
    logic pslverr;
    logic urgent;
    logic irq;
    logic bclk;
    logic lrck;
    logic sdata;
    logic [31:0] received;
    logic received_valid;
    int checker_errors;
    int test_id = 1;
    int frames;
    int checked_samples;
    int silence_frames;
    int serial_number;
    int discarded_samples;
    bit compare_samples = 1;
    bit started;
    bit [31:0] expected[$];
    bit [31:0] ring_mirror[bit [31:0]];
    edrv32_axi256_if bus();

    initial begin
        clk_mem = 0;
        forever #4 clk_mem = ~clk_mem;
    end
    initial begin
        clk_aud = 0;
        repeat ($urandom_range(1, 80)) #1;
        forever #(1000000000.0/12288000.0/2.0) clk_aud = ~clk_aud;
    end

    edrv32_aud u_dut (
        .clk_mem_i(clk_mem),
        .rst_mem_n_i(rst_mem_n),
        .clk_aud_i(clk_aud),
        .rst_aud_n_i(rst_aud_n),
        .s_apb_paddr_i(paddr),
        .s_apb_psel_i(psel),
        .s_apb_penable_i(penable),
        .s_apb_pwrite_i(pwrite),
        .s_apb_pwdata_i(pwdata),
        .s_apb_pstrb_i(4'hf),
        .s_apb_prdata_o(prdata),
        .s_apb_pready_o(pready),
        .s_apb_pslverr_o(pslverr),
        .m_axi_arid_o(bus.arid),
        .m_axi_araddr_o(bus.araddr),
        .m_axi_arlen_o(bus.arlen),
        .m_axi_arvalid_o(bus.arvalid),
        .m_axi_arready_i(bus.arready),
        .m_axi_rid_i(bus.rid),
        .m_axi_rdata_i(bus.rdata),
        .m_axi_rresp_i(bus.rresp),
        .m_axi_rlast_i(bus.rlast),
        .m_axi_rvalid_i(bus.rvalid),
        .m_axi_rready_o(bus.rready),
        .urgent_o(urgent),
        .irq_o(irq),
        .aud_bclk_o(bclk),
        .aud_lrck_o(lrck),
        .aud_sdata_o(sdata)
    );
    assign bus.awid = 0;
    assign bus.awaddr = 0;
    assign bus.awlen = 0;
    assign bus.awvalid = 0;
    assign bus.awready = 0;
    assign bus.wdata = 0;
    assign bus.wstrb = 0;
    assign bus.wlast = 0;
    assign bus.wvalid = 0;
    assign bus.wready = 0;
    assign bus.bid = 0;
    assign bus.bresp = 0;
    assign bus.bvalid = 0;
    assign bus.bready = 1;

    edrv32_aud_memory u_memory (
        .clk_i(clk_mem),
        .rst_n_i(rst_mem_n),
        .bus(bus)
    );
    edrv32_axi256_checker u_checker (
        .clk_i(clk_mem),
        .rst_n_i(rst_mem_n),
        .bus(bus),
        .errors_o(checker_errors)
    );
    i2s_rx_model u_receiver (
        .clk_aud_i(clk_aud),
        .rst_n_i(rst_aud_n),
        .bclk_i(bclk),
        .lrck_i(lrck),
        .sdata_i(sdata),
        .sample_o(received),
        .sample_valid_o(received_valid)
    );

    always @(posedge received_valid) begin : scoreboard
        bit [31:0] want;
        frames++;
        if (compare_samples) begin
            if (expected.size() != 0 && (started || received != 0)) begin
                want = expected.pop_front();
                if (received !== want)
                    $fatal(1, "FAIL AT-%02d sample=%0d expected=%h actual=%h time=%0t",
                        test_id, checked_samples, want, received, $time);
                checked_samples++;
                started = expected.size() != 0;
            end else if (received != 0)
                $fatal(1, "FAIL unexpected sample actual=%h time=%0t", received, $time);
            else silence_frames++;
        end
    end

    task automatic apb(input bit write_access, input bit [31:0] offset,
        input bit [31:0] data, output bit [31:0] result);
        @(negedge clk_mem);
        paddr = 12'(offset);
        pwdata = data;
        pwrite = write_access;
        psel = 1;
        penable = 0;
        @(negedge clk_mem);
        penable = 1;
        do @(posedge clk_mem); while (!pready);
        result = prdata;
        if (pslverr) $fatal(1, "FAIL APB offset=%h SLVERR time=%0t", offset, $time);
        @(negedge clk_mem);
        psel = 0;
        penable = 0;
    endtask

    task automatic write_reg(input bit [31:0] offset, input bit [31:0] data);
        bit [31:0] unused_result;
        apb(1, offset, data, unused_result);
    endtask

    task automatic read_reg(input bit [31:0] offset, output bit [31:0] data);
        apb(0, offset, 0, data);
    endtask

    task automatic check_reg(input bit [31:0] offset, input bit [31:0] want,
        input bit [31:0] mask = 32'hffffffff);
        bit [31:0] actual;
        read_reg(offset, actual);
        if ((actual & mask) != (want & mask))
            $fatal(1, "FAIL register=%h expected=%h actual=%h mask=%h time=%0t",
                offset, want, actual, mask, $time);
    endtask

    task automatic wait_frames(input int count);
        repeat (count) @(posedge received_valid);
        @(negedge clk_mem);
    endtask

    task automatic drain();
        wait (expected.size() == 0);
        wait_frames(2);
    endtask

    task automatic fetched();
        bit [31:0] rd_ptr;
        do read_reg(EDRV32_AUD_RD_PTR_OFFSET, rd_ptr);
        while (rd_ptr != 32'(u_memory.producer) || u_memory.active);
    endtask

    task automatic configure(input int base, input int size);
        u_memory.ring_base = base;
        u_memory.ring_size = size;
        u_memory.producer = 0;
        u_memory.consumer = 0;
        write_reg(EDRV32_AUD_RING_BASE_OFFSET, 32'(base));
        write_reg(EDRV32_AUD_RING_SIZE_OFFSET, 32'(size));
        write_reg(EDRV32_AUD_WR_PTR_OFFSET, 0);
    endtask

    task automatic enable_audio();
        u_memory.enabled = 1;
        u_memory.consumer = 0;
        write_reg(EDRV32_AUD_CTRL_OFFSET, 1);
    endtask

    // The producer writes little-endian stereo frames to the independent ring mirror.
    // Expected samples are copied in publication order, before the APB WR_PTR update.
    task automatic publish(input int bytes_count);
        int offset;
        bit [31:0] sample_value;
        offset = u_memory.producer;
        for (int n = 0; n < bytes_count/4; n++) begin
            case (serial_number % 8)
                0: sample_value = 32'h7fff8000;
                1: sample_value = 32'h80007fff;
                2: sample_value = 32'h0001ffff;
                3: sample_value = 32'hffff0001;
                default: sample_value = {16'(serial_number ^ 'h5a5a), 16'(serial_number)};
            endcase
            ring_mirror[32'(offset)] = sample_value;
            u_memory.memory[32'(u_memory.ring_base+offset)] = ring_mirror[32'(offset)];
            expected.push_back(ring_mirror[32'(offset)]);
            serial_number++;
            offset = (offset+4)%u_memory.ring_size;
        end
        u_memory.producer = offset;
        write_reg(EDRV32_AUD_WR_PTR_OFFSET, 32'(offset));
    endtask

    task automatic disable_audio();
        // The current serial frame may already have been latched before ENABLE crosses.
        compare_samples = 0;
        write_reg(EDRV32_AUD_CTRL_OFFSET, 0);
        u_memory.enabled = 0;
        wait (!u_memory.active);
        wait_frames(2);
        discarded_samples += expected.size();
        expected.delete();
        started = 0;
        compare_samples = 1;
    endtask

    task automatic test_waveform();
        configure('h10000, 2048);
        publish(1024);
        enable_audio();
        drain();
        if (checked_samples != 256) $fatal(1, "FAIL AT-01 sample count=%0d", checked_samples);
    endtask

    task automatic test_ring();
        configure('h10e00, 1536);
        enable_audio();
        wait_frames(2);
        for (int n = 0; n < 10; n++) begin
            publish(n%2 == 0 ? 992 : 416);
            drain();
            check_reg(EDRV32_AUD_RD_PTR_OFFSET, 32'(u_memory.producer));
        end
        if (u_memory.ring_end_splits < 4 || u_memory.page_end_splits < 1 ||
            u_memory.short_reads < 1)
            $fatal(1, "FAIL AT-02 coverage ring=%0d page=%0d short=%0d",
                u_memory.ring_end_splits, u_memory.page_end_splits, u_memory.short_reads);
    endtask

    task automatic test_low();
        configure('h10000, 2048);
        write_reg(EDRV32_AUD_LOW_LEVEL_OFFSET, 256);
        write_reg(EDRV32_AUD_IRQ_EN_OFFSET, 'h100);
        publish(1024);
        enable_audio();
        fetched();
        repeat (32) @(negedge clk_mem);
        check_reg(EDRV32_AUD_IRQ_STAT_OFFSET, 'h100, 'h100);
        if (!irq) $fatal(1, "FAIL AT-03 LOW irq expected=1 time=%0t", $time);
        write_reg(EDRV32_AUD_IRQ_STAT_OFFSET, 'h100);
        wait_frames(4);
        check_reg(EDRV32_AUD_IRQ_STAT_OFFSET, 0, 'h100);
        if (irq) $fatal(1, "FAIL AT-03 LOW repeated time=%0t", $time);
        publish(512);
        fetched();
        repeat (32) @(negedge clk_mem);
        check_reg(EDRV32_AUD_IRQ_STAT_OFFSET, 'h100, 'h100);
        drain();
    endtask

    task automatic test_underrun();
        bit [31:0] before_count;
        bit [31:0] after_count;
        configure('h10000, 1024);
        enable_audio();
        wait_frames(4);
        read_reg(EDRV32_AUD_UNDERRUN_CNT_OFFSET, before_count);
        wait_frames(8);
        read_reg(EDRV32_AUD_UNDERRUN_CNT_OFFSET, after_count);
        if (after_count-before_count != 8)
            $fatal(1, "FAIL AT-04 underrun delta expected=8 actual=%0d time=%0t",
                after_count-before_count, $time);
        check_reg(EDRV32_AUD_STATUS_OFFSET, 0, 4);
        check_reg(EDRV32_AUD_ERR_CODE_OFFSET, 0);
        publish(256);
        drain();
        if (checked_samples != 64) $fatal(1, "FAIL AT-04 recovery count=%0d", checked_samples);
    endtask

    task automatic test_enable();
        bit [31:0] count;
        int requests_before;
        int restarted_before;
        configure('h10000, 4096);
        publish(3072);
        enable_audio();
        wait (u_memory.active && u_memory.requests >= 2);
        disable_audio();
        restarted_before = checked_samples;
        requests_before = u_memory.requests;
        read_reg(EDRV32_AUD_UNDERRUN_CNT_OFFSET, count);
        wait_frames(8);
        check_reg(EDRV32_AUD_UNDERRUN_CNT_OFFSET, count);
        if (u_memory.requests != requests_before)
            $fatal(1, "FAIL AT-05 disabled DMA time=%0t", $time);
        write_reg(EDRV32_AUD_WR_PTR_OFFSET, 0);
        u_memory.producer = 0;
        enable_audio();
        check_reg(EDRV32_AUD_RD_PTR_OFFSET, 0);
        wait_frames(2);
        publish(256);
        drain();
        if (checked_samples-restarted_before != 64 || discarded_samples == 0)
            $fatal(1, "FAIL AT-05 restarted=%0d discarded=%0d",
                checked_samples-restarted_before, discarded_samples);
    endtask

    task automatic test_error();
        int requests_before;
        configure('h10000, 4096);
        publish(512);
        enable_audio();
        fetched();
        u_memory.inject_error = 1;
        // Keep the successful prefix under comparison; the error response payload is unspecified.
        publish(512);
        wait (!u_memory.inject_error);
        wait (!u_memory.active);
        repeat (32) @(negedge clk_mem);
        check_reg(EDRV32_AUD_ERR_CODE_OFFSET, 1);
        check_reg(EDRV32_AUD_STATUS_OFFSET, 4, 4);
        check_reg(EDRV32_AUD_IRQ_STAT_OFFSET, 2, 2);
        u_memory.stopped = 1;
        publish(512);
        requests_before = u_memory.requests;
        wait (checked_samples == 128);
        compare_samples = 0;
        expected.delete();
        wait_frames(520);
        compare_samples = 1;
        wait_frames(8);
        if (u_memory.requests != requests_before)
            $fatal(1, "FAIL AT-06 DMA continued after error time=%0t", $time);
    endtask

    task automatic test_urgent();
        configure('h10000, 2048);
        if (urgent) $fatal(1, "FAIL AT-07 disabled urgent time=%0t", $time);
        enable_audio();
        wait_frames(2);
        if (!urgent) $fatal(1, "FAIL AT-07 empty urgent time=%0t", $time);
        publish(512);
        fetched();
        repeat (64) @(negedge clk_mem);
        if (urgent) $fatal(1, "FAIL AT-07 high water urgent time=%0t", $time);
        // At the end of the 64th sample, exactly 64 frames remain in the FIFO.
        // The following falling LRCK starts frame 65; allow clk_mem CDC settling.
        wait (checked_samples == 64);
        #0.001;
        if (urgent) $fatal(1, "FAIL AT-07 occupancy=64 urgent time=%0t", $time);
        @(negedge lrck);
        repeat (32) @(negedge clk_mem);
        if (!urgent) $fatal(1, "FAIL AT-07 occupancy=63 urgent time=%0t", $time);
        drain();
        disable_audio();
        if (urgent) $fatal(1, "FAIL AT-07 disable urgent time=%0t", $time);
    endtask

    task automatic test_registers();
        bit [31:0] offsets[13] = '{4, 12, 16, 20, 32, 36, 40, 44, 256, 260, 264, 268, 272};
        check_reg(EDRV32_AUD_ID_OFFSET, 'h10000, 'hffff0000);
        check_reg(EDRV32_AUD_STATUS_OFFSET, 2);
        foreach (offsets[n]) check_reg(offsets[n], 0);
        check_reg(EDRV32_AUD_UNDERRUN_CNT_OFFSET, 0);
        for (int n = 0; n < 16; n++) check_reg(EDRV32_AUD_PERF_OFFSET+32'(n*4), 0);
        write_reg(EDRV32_AUD_RING_BASE_OFFSET, 'h12345fff);
        check_reg(EDRV32_AUD_RING_BASE_OFFSET, 'h12345e00);
        write_reg(EDRV32_AUD_RING_SIZE_OFFSET, 'hff001fff);
        check_reg(EDRV32_AUD_RING_SIZE_OFFSET, 'h1e00);
        write_reg(EDRV32_AUD_WR_PTR_OFFSET, 'hff001fff);
        check_reg(EDRV32_AUD_WR_PTR_OFFSET, 'h1fe0);
        configure('h10000, 2048);
        enable_audio();
        write_reg(EDRV32_AUD_RING_BASE_OFFSET, 'h20000);
        write_reg(EDRV32_AUD_RING_SIZE_OFFSET, 4096);
        check_reg(EDRV32_AUD_RING_BASE_OFFSET, 'h10000);
        check_reg(EDRV32_AUD_RING_SIZE_OFFSET, 2048);
        wait_frames(4);
    endtask

    task automatic test_random();
        int amount;
        int outstanding;
        configure('h10e00, 8192);
        // Large initial supply avoids startup underruns while the asynchronous enable settles.
        publish(4096);
        @(negedge lrck);
        repeat (8) @(negedge clk_mem);
        enable_audio();
        wait (checked_samples >= 8);
        for (int n = 0; n < 80; n++) begin
            wait_frames(int'($urandom_range(1, 16)));
            outstanding = expected.size()*4;
            if (outstanding < 3072) begin
                amount = 32*int'($urandom_range(1, 16));
                publish(amount);
            end
        end
        wait (expected.size() == 0);
        check_reg(EDRV32_AUD_UNDERRUN_CNT_OFFSET, 0);
        disable_audio();
    endtask

    initial begin : run
        void'($value$plusargs("AT=%d", test_id));
        repeat (12) @(negedge clk_mem);
        rst_mem_n = 1;
        repeat (4) @(negedge clk_aud);
        rst_aud_n = 1;
        wait_frames(2);
        case (test_id)
            1: test_waveform();
            2: test_ring();
            3: test_low();
            4: test_underrun();
            5: test_enable();
            6: test_error();
            7: test_urgent();
            8: test_registers();
            9: test_random();
            default: $fatal(1, "FAIL invalid AT=%0d", test_id);
        endcase
        if (checker_errors != 0) $fatal(1, "FAIL AXI checker errors=%0d", checker_errors);
        $display("PASS AT-%02d frames=%0d samples=%0d silence=%0d AR=%0d Rframes=%0d",
            test_id, frames, checked_samples, silence_frames,
            u_memory.requests, u_memory.returned_frames);
        $finish;
    end

    initial begin
        #100000000;
        $fatal(1, "FAIL AT-%02d timeout samples=%0d pending=%0d time=%0t",
            test_id, checked_samples, expected.size(), $time);
    end
endmodule
