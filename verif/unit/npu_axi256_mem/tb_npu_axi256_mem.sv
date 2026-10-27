// File: tb_npu_axi256_mem.sv
// Spec: npu-testplan 2.3; SoC 4.2.
// Description: Memory timing, byte enables, delayed visibility, errors and accounting.
// Clock domain: clk_mem at 125 MHz.
`timescale 1ns/1ps
module tb_npu_axi256_mem;
    bit clk = 0;
    bit rst_n = 0;
    wire unused_urgent;
    int checker_errors;
    int cycles;
    int first_ar = -1;
    int first_r = -1;
    int final_response;
    int requests_start = -1;
    int observed_reads;
    int observed_writes;
    int read_index;
    bit stalled_r;
    bit stalled_b;
    bit [255:0] expected[$];
    bit [255:0] data[16];
    bit [31:0] strb[16];
    edrv32_axi256_if bus();
    npu_axi256_mem u_mem (
        .clk_i(clk),
        .rst_n_i(rst_n),
        .bus(bus)
    );
    edrv32_axi256_master u_master (
        .clk_i(clk),
        .rst_n_i(rst_n),
        .urgent_o(unused_urgent),
        .bus(bus)
    );
    edrv32_axi256_checker u_checker (
        .clk_i(clk),
        .rst_n_i(rst_n),
        .bus(bus),
        .errors_o(checker_errors)
    );
    always #4 clk = ~clk;

    task automatic check(input bit condition, input string detail);
        if (!condition) $fatal(1, "FAIL %s time=%0t", detail, $time);
    endtask

    task automatic expect_read(input bit [31:0] addr, input int len, input bit id);
        bit [255:0] beat;
        for (int n = 0; n <= len; n++) begin
            for (int b = 0; b < 32; b++) beat[b*8 +: 8] = byte'(addr+n*32+32'(b));
            expected.push_back(beat);
        end
        u_master.enqueue_read(addr, len, id);
    endtask

    always @(posedge clk) begin
        if (rst_n) begin
            cycles++;
            if (requests_start < 0 && ((bus.arvalid && bus.arready) ||
                (bus.awvalid && bus.awready))) requests_start = cycles;
            if (bus.arvalid && bus.arready && first_ar < 0) first_ar = cycles;
            if (bus.rvalid && first_r < 0) first_r = cycles;
            stalled_r |= bus.rvalid && !bus.rready;
            stalled_b |= bus.bvalid && !bus.bready;
            if (bus.rvalid && bus.rready) begin
                if (read_index < expected.size()) begin
                    check(bus.rdata == expected[read_index],
                        $sformatf("RDATA beat=%0d expected=%h actual=%h",
                            read_index, expected[read_index], bus.rdata));
                end
                read_index++;
                observed_reads++;
                final_response = cycles;
            end
            if (bus.wvalid && bus.wready) observed_writes++;
            if (bus.bvalid && bus.bready) final_response = cycles;
        end
    end

    initial begin : exercise
        bit [255:0] changed;
        int target;
        int duration;
        int before_bulk;
        cycles = 0;
        for (int b = 0; b < 4096; b++) begin
            u_mem.poke(32'(b), byte'(b));
            u_mem.poke('hf000+32'(b), byte'(b));
        end
        repeat (4) @(negedge clk);
        rst_n = 1;
        expect_read('h100, 15, 1);
        u_master.wait_done(1, 0);
        check(first_r-first_ar == (u_mem.mode == "zero" ? 1 : u_mem.latency),
            $sformatf("first latency expected=%0d actual=%0d",
                u_mem.mode == "zero" ? 1 : u_mem.latency, first_r-first_ar));
        duration = final_response-first_r;
        if (u_mem.mode == "bw") check(duration >= 14*32*125/1400, "bandwidth limit");

        // A held B response must not reveal writes before its first assertion.
        u_master.b_on = 0;
        for (int n = 0; n < 16; n++) begin
            data[n] = {32{8'ha5}};
            strb[n] = 'h55555555;
        end
        u_master.enqueue_write('h800, 1, data, strb, 1);
        wait (u_mem.write_beats == 2);
        while (!bus.bvalid) begin
            @(negedge clk);
            if (!bus.bvalid) check(u_mem.peek('h800) == 0, "write visible before B");
        end
        check(u_mem.peek('h800) == 'ha5, "write invisible at B assertion");
        check(u_mem.peek('h801) == 1, "WSTRB disabled byte modified");
        changed = 0;
        for (int b = 0; b < 32; b++)
            changed[b*8 +: 8] = (b % 2 == 0) ? 8'ha5 : byte'(b);
        expected.push_back(changed);
        u_master.enqueue_read('h800, 0, 0);
        u_master.wait_done(2, 0);
        repeat (4) @(negedge clk);
        u_master.b_on = 1;
        u_master.wait_done(2, 1);

        // Fill both independent outstanding windows while R/B are backpressured.
        u_master.r_on = 0;
        u_master.b_on = 0;
        target = u_mem.max_outstanding+2;
        for (int n = 0; n < target; n++) begin
            expect_read('h200+32'(n*32), 0, 1'(n));
            u_master.enqueue_write('h1000+32'(n*32), 0, data, strb, 1'(n));
        end
        repeat (u_mem.latency+u_mem.b_delay+target*5+40) @(negedge clk);
        check(u_mem.read_outstanding == u_mem.max_outstanding, "read window limit");
        check(u_mem.write_outstanding == u_mem.max_outstanding, "write window limit");
        check(!bus.arready && !bus.awready, "full window did not backpressure");
        u_master.r_period = 5;
        u_master.r_on = 2;
        u_master.b_period = 7;
        u_master.b_on = 2;
        before_bulk = cycles;
        u_master.wait_done(2+target, 1+target);
        check(cycles > before_bulk, "bulk response retirement");

        // Error ranges hit the interior of a burst, and the following burst is OKAY.
        u_master.expected_resp = 2;
        expect_read('hf000, 1, 1);
        u_master.enqueue_write('hf000, 1, data, strb, 1);
        u_master.wait_done(3+target, 2+target);
        u_master.expected_resp = 0;
        expect_read('hf040, 0, 0);
        u_master.wait_done(4+target, 2+target);
        expected.push_back(256'hffeeddccbbaa99887766554433221100_00112233445566778899aabbccddeeff);
        expected.push_back({128'h0123456789abcdef_fedcba9876543210,
            128'h80017f00ff008001_1020304050607080});
        u_master.enqueue_read('h20000, 1, 1);
        u_master.wait_done(5+target, 2+target);
        check(stalled_r && stalled_b, "response backpressure was not exercised");
        check(u_mem.read_beats == 64'(observed_reads), "read beat statistics");
        check(u_mem.write_beats == 64'(observed_writes), "write beat statistics");
        check(u_mem.elapsed_cycles() == final_response-requests_start+1, "elapsed statistics");
        check(u_mem.peak_reads == u_mem.max_outstanding, "peak read statistics");
        check(u_mem.peak_writes == u_mem.max_outstanding, "peak write statistics");
        check(checker_errors == 0, "protocol checker");
        $display("PASS memory mode=%s reads=%0d writes=%0d cycles=%0d", u_mem.mode,
            u_mem.read_beats, u_mem.write_beats, u_mem.elapsed_cycles());
        $finish;
    end
    initial begin
        #1000000;
        $fatal(1, "FAIL memory timeout time=%0t", $time);
    end
endmodule
