// File: edrv32_geo_tb.sv
// Spec: geo 2–7; geo-testplan GE-01–GE-13; SoC 4.2, 4.3, 7.1–7.3.
// Description: Independent public-port APB/AXI harness, Python Surface scoreboard,
//              register/error/abort checks and PERF0 frame-time measurement.
// Clock domain: clk_mem (125 MHz).
`timescale 1ns/1ps
module edrv32_geo_tb;
    localparam int MEM_BYTES = 32 * 1024 * 1024;
    logic clk_mem = 0;
    logic rst_mem_n = 0;
    logic irq;
    edrv32_apb_if apb();
    edrv32_axi256_if axi();
    int checker_errors;
    byte unsigned expected[0:MEM_BYTES-1];
    byte unsigned second_before[];
    int test_case;
    int descriptor_count;
    int expected_error;
    int injection;
    int abort_phase;
    int latency;
    int stalls;
    int bandwidth;
    int response_delay;
    int perf_limit_ns;
    int seed;
    int surface_count;
    int surface_desc[4];
    int surface_base[4];
    int surface_stride[4];
    int surface_height[4];
    int surface_x[4];
    int surface_y[4];
    int current_desc = 0;
    int expected_done = 0;
    time doorbell_time;
    int perf_busy_lower = 0;
    int perf_idle_upper = 0;
    bit expect_done_irq = 0;

    always #4 clk_mem = ~clk_mem;

    always @(negedge clk_mem) begin
        // geo 3 clarification: dma2d_rd/wr each have OUTSTANDING=4.
        if (rst_mem_n) begin
            equal("P5 read OUTSTANDING <=4", 1,
                32'(u_memory.ar_count - u_memory.r_count <= 4));
            equal("P5 write OUTSTANDING <=4", 1,
                32'(u_memory.aw_count - u_memory.b_count <= 4));
        end
        // geo 5.1: a normal completion IRQ cannot precede the last write response.
        if (rst_mem_n && expect_done_irq && irq) begin
            equal("DONE IRQ after all B responses", 32'(u_memory.aw_count),
                32'(u_memory.b_count));
            equal("DONE IRQ after all R responses", 32'(u_memory.ar_count),
                32'(u_memory.r_count));
        end
    end

    // Media APB slot 3; all other slots are unused in this block harness.
    assign apb.prdata[95:0] = 0;
    assign apb.prdata[511:128] = 0;
    assign apb.pready[2:0] = 0;
    assign apb.pready[15:4] = 0;
    assign apb.pslverr[2:0] = 0;
    assign apb.pslverr[15:4] = 0;

    edrv32_geo_memory u_memory (
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

    edrv32_geo u_geo (
        .clk_mem_i(clk_mem),
        .rst_mem_n_i(rst_mem_n),

        .apb_paddr_i(apb.paddr),
        .apb_psel_i(apb.psel[3]),
        .apb_penable_i(apb.penable),
        .apb_pwrite_i(apb.pwrite),
        .apb_pwdata_i(apb.pwdata),
        .apb_pstrb_i(apb.pstrb),
        .apb_pready_o(apb.pready[3]),
        .apb_prdata_o(apb.prdata[127:96]),
        .apb_pslverr_o(apb.pslverr[3]),

        .p5_awid_o(axi.awid),
        .p5_awaddr_o(axi.awaddr),
        .p5_awlen_o(axi.awlen),
        .p5_awvalid_o(axi.awvalid),
        .p5_awready_i(axi.awready),
        .p5_wdata_o(axi.wdata),
        .p5_wstrb_o(axi.wstrb),
        .p5_wlast_o(axi.wlast),
        .p5_wvalid_o(axi.wvalid),
        .p5_wready_i(axi.wready),
        .p5_bid_i(axi.bid),
        .p5_bresp_i(axi.bresp),
        .p5_bvalid_i(axi.bvalid),
        .p5_bready_o(axi.bready),

        .p5_arid_o(axi.arid),
        .p5_araddr_o(axi.araddr),
        .p5_arlen_o(axi.arlen),
        .p5_arvalid_o(axi.arvalid),
        .p5_arready_i(axi.arready),
        .p5_rid_i(axi.rid),
        .p5_rdata_i(axi.rdata),
        .p5_rresp_i(axi.rresp),
        .p5_rlast_i(axi.rlast),
        .p5_rvalid_i(axi.rvalid),
        .p5_rready_o(axi.rready),

        .irq_o(irq)
    );

    task automatic equal(input string what_i,
        input logic [31:0] expected_i,
        input logic [31:0] actual_i);
        if (actual_i !== expected_i)
            $fatal(1, string'({"FAIL GE-%02d %s desc=%0d coord=(-1,-1) ",
                "expected=%08h actual=%08h time=%0t"}),
                test_case, what_i, current_desc, expected_i, actual_i, $time);
    endtask

    task automatic apb_access(input bit write_i,
        input logic [11:0] address_i,
        input logic [31:0] data_i,
        output logic [31:0] data_o);
        @(negedge clk_mem);
        apb.paddr = address_i;
        apb.pwrite = write_i;
        apb.pwdata = data_i;
        // geo 4: pstrb is ignored, including zero strobes.
        apb.pstrb = 4'(address_i[3:0]);
        apb.psel = 16'h0008;
        apb.penable = 0;
        @(negedge clk_mem);
        apb.penable = 1;
        @(posedge clk_mem);
        equal("APB PREADY", 1, 32'(apb.pready[3]));
        equal("APB PSLVERR", 0, 32'(apb.pslverr[3]));
        data_o = apb.prdata[127:96];
        @(negedge clk_mem);
        apb.psel = 0;
        apb.penable = 0;
    endtask

    task automatic write_reg(input logic [11:0] address_i,
        input logic [31:0] data_i);
        logic [31:0] unused_data;
        apb_access(1, address_i, data_i, unused_data);
    endtask

    task automatic read_reg(input logic [11:0] address_i,
        output logic [31:0] data_o);
        apb_access(0, address_i, 0, data_o);
    endtask

    task automatic expect_reg(input logic [11:0] address_i,
        input logic [31:0] expected_i);
        logic [31:0] actual;
        read_reg(address_i, actual);
        equal($sformatf("register %03h", address_i), expected_i, actual);
    endtask

    function automatic logic [31:0] memory_word(input int address_i);
        return {u_memory.mem[address_i+3], u_memory.mem[address_i+2],
            u_memory.mem[address_i+1], u_memory.mem[address_i]};
    endfunction

    task automatic compare_surface(input bit [1:0] index_i,
        input bit initial_second_i = 0);
        int address;
        int offset;
        logic [15:0] actual_pixel;
        logic [15:0] expected_pixel;
        current_desc = surface_desc[index_i];
        // Include row padding: geo 2.3 requires every byte outside the rectangle unchanged.
        for (int y = 0; y < surface_height[index_i]; y++) begin
            for (int x = 0; x < surface_stride[index_i] / 2; x++) begin
                address = surface_base[index_i] + y * surface_stride[index_i] + x * 2;
                offset = y * surface_stride[index_i] + x * 2;
                actual_pixel = {u_memory.mem[address+1], u_memory.mem[address]};
                if (initial_second_i)
                    expected_pixel = {second_before[offset+1], second_before[offset]};
                else expected_pixel = {expected[address+1], expected[address]};
                if (actual_pixel !== expected_pixel)
                    $fatal(1, string'({"FAIL GE-%02d Surface desc=%0d coord=(%0d,%0d) ",
                        "expected=%04h actual=%04h time=%0t"}), test_case, current_desc,
                        x - surface_x[index_i], y - surface_y[index_i],
                        expected_pixel, actual_pixel, $time);
            end
        end
    endtask

    task automatic drain_check;
        equal("memory AW/W/B drained", 0,
            32'(u_memory.writes.size()
                + u_memory.responses.size()));
        equal("memory AR/R drained", 0, 32'(u_memory.reads.size()));
        equal("AW count == B count", 32'(u_memory.aw_count), 32'(u_memory.b_count));
        equal("AR count == RLAST count", 32'(u_memory.ar_count), 32'(u_memory.r_count));
        equal("checker errors", 0, 32'(checker_errors));
        equal("checker AW drained", 0, 32'(u_checker.aw_queue.size()));
        equal("checker W drained", 0, 32'(u_checker.w_queue.size()));
        equal("checker partial W drained", 0, 32'(u_checker.w_count));
        for (int id = 0; id < 16; id++) begin
            equal("checker B drained", 0, 32'(u_checker.b_pending[id]));
            equal("checker R drained", 0, 32'(u_checker.r_queue[id].size()));
        end
    endtask

    task automatic wait_idle;
        logic [31:0] status;
        do begin
            read_reg(12'h008, status);
            record_perf_bound(status[0]);
        end while (status[0]);
        equal("STATUS drained", expected_error != 0 ? 6 : 2, status);
        drain_check();
    endtask

    task automatic start_table;
        write_reg(12'h010, 3);
        expect_done_irq = (expected_error == 0 && abort_phase == 0)
            || (test_case == 9 && u_memory.error_kind == 0);
        write_reg(12'h00c, 3);
        write_reg(12'h020, 32'h101f);
        write_reg(12'h024, 32'habcd0000 | 32'(descriptor_count));
        write_reg(12'h028, 32'hfeed1234);
        doorbell_time = $time - 4;
        perf_busy_lower = 0;
        perf_idle_upper = 0;
    endtask

    task automatic record_perf_bound(input bit busy_i);
        int elapsed;
        // APB samples on the rising edge, four ns before read_reg returns.
        elapsed = int'(($time - 4 - doorbell_time) / 8);
        if (busy_i) perf_busy_lower = elapsed;
        else perf_idle_upper = elapsed;
    endtask

    task automatic check_perf_stopped;
        logic [31:0] cycles;
        read_reg(12'h040, cycles);
        // geo 4.3: errors and ABORT keep counting until BUSY deasserts, then freeze.
        // Consecutive APB STATUS samples bound that transition without DUT internals.
        if (cycles < 32'(perf_busy_lower) || cycles > 32'(perf_idle_upper))
            $fatal(1, string'({"FAIL GE-%02d PERF0 desc=%0d coord=(-1,-1) ",
                "expected_cycles=[%0d,%0d] actual=%0d time=%0t"}),
                test_case, current_desc, perf_busy_lower, perf_idle_upper, cycles, $time);
        expect_reg(12'h040, cycles);
    endtask

    task automatic check_completion;
        logic [31:0] status;
        logic [31:0] completed;
        logic [31:0] observed;
        logic [31:0] unused_field;
        int last_count;
        int pixels;
        int frame_ns;
        logic [31:0] source_wait;
        logic [31:0] writer_wait;
        last_count = expected_done;
        do begin
            read_reg(12'h008, status);
            record_perf_bound(status[0]);
            equal("STATUS normal execution", status[0] ? 1 : 2, status);
            if (!status[0]) drain_check();
            if (test_case == 7) begin
                read_reg(12'h02c, completed);
                if (completed != 32'(last_count)) begin
                    equal("DONE_COUNT increments one descriptor", 32'(last_count + 1),
                        completed);
                    last_count++;
                    read_reg(12'h100, observed);
                    equal("CUR_DESC follows DONE_COUNT", completed, observed);
                    compare_surface(2'(last_count - 1));
                end
            end
        end while (status[0]);
        expected_done += descriptor_count;
        expect_reg(12'h008, 2);
        expect_reg(12'h010, 1);
        expect_reg(12'h014, 0);
        expect_reg(12'h02c, 32'(expected_done));
        expect_reg(12'h100, 32'(descriptor_count));
        equal("DONE IRQ enabled", 1, 32'(irq));
        check_perf_stopped();
        pixels = 0;
        for (int index = 0; index < descriptor_count; index++) begin
            unused_field = memory_word(32'h1000 + index * 64 + 24);
            pixels += int'(unused_field[11:1]) * 2 * int'(unused_field[27:16]);
        end
        expect_reg(12'h044, 32'(pixels));
        expect_reg(12'h048, 32'(u_memory.r_beats));
        expect_reg(12'h04c, 32'(u_memory.w_beats));
        for (int index = 6; index < 16; index++) expect_reg(12'(64 + index * 4), 0);
        if (perf_limit_ns != 0) begin
            read_reg(12'h040, observed);
            read_reg(12'h050, source_wait);
            read_reg(12'h054, writer_wait);
            // GE-12: frame time comes exclusively from PERF0, at 125 MHz (8 ns/cycle).
            frame_ns = int'(observed) * 8;
            $display("GE-12 PERF0=%0d frame_ns=%0d limit_ns=%0d PERF4=%0d PERF5=%0d",
                observed, frame_ns, perf_limit_ns, source_wait, writer_wait);
            equal("PERF0 frame time within limit", 1, 32'(frame_ns <= perf_limit_ns));
        end
        for (int index = 0; index < surface_count; index++) compare_surface(2'(index));
    endtask

    task automatic check_error;
        wait_idle();
        check_perf_stopped();
        current_desc = 0;
        expect_reg(12'h008, 6);
        expect_reg(12'h010, 2);
        expect_reg(12'h014, 32'(expected_error));
        expect_reg(12'h100, 0);
        expect_reg(12'h02c, 0);
        equal("ERROR IRQ enabled", 1, 32'(irq));
        equal("no subsequent descriptor read", 0, 32'(u_memory.max_desc_read));
        write_reg(12'h00c, 0);
        equal("ERROR IRQ masked", 0, 32'(irq));
        write_reg(12'h00c, 2);
        equal("ERROR IRQ unmasked", 1, 32'(irq));
        if (expected_error == 3) begin
            equal("range rejection before source read", 0, 32'(u_memory.source_ar_count));
            equal("range rejection no AW", 0, 32'(u_memory.aw_count));
            for (int index = 0; index < surface_count; index++) compare_surface(2'(index));
        end else begin
            equal("SLVERR injected", 1, 32'(u_memory.injected));
            // The second descriptor must not execute, including when the first partially writes.
            compare_surface(2'd1, 1'b1);
            current_desc = 0;
            @(negedge clk_mem);
            u_memory.error_kind = 0;
        end
        write_reg(12'h010, 2);
        expect_reg(12'h014, 0);
        expect_reg(12'h010, 0);
        expect_reg(12'h008, 2);
        equal("ERROR clear IRQ", 0, 32'(irq));
        if (expected_error != 3) begin
            // Counters are per DOORBELL, while the RAM totals include the failed attempt.
            @(negedge clk_mem);
            u_memory.r_beats = 0;
            u_memory.w_beats = 0;
            start_table();
            check_completion();
        end
    endtask

    task automatic ge10_abort;
        if (abort_phase == 1) wait (u_memory.descriptor_ar_count != 0);
        else if (abort_phase == 2) wait (u_memory.source_ar_count != 0);
        else wait (u_memory.w_beats != 0);
        if (abort_phase != 3)
            equal("ABORT with R in flight", 1,
                32'(u_memory.ar_count > u_memory.r_count));
        else equal("ABORT with B in flight", 1,
            32'(u_memory.aw_count > u_memory.b_count));
        write_reg(12'h004, 4);
        wait_idle();
        check_perf_stopped();
        expect_reg(12'h008, 2);
        expect_reg(12'h010, 0);
        expect_reg(12'h014, 0);
        expect_reg(12'h02c, 0);
        expect_reg(12'h100, 0);
        equal("ABORT no IRQ", 0, 32'(irq));
        // Any bytes already emitted remain valid; unissued pixels are deliberately unspecified.
        foreach (u_memory.written[address]) begin
            if (u_memory.mem[address] !== expected[address])
                $fatal(1, string'({"FAIL GE-10 desc=0 coord=(%0d,%0d) ",
                    "expected_byte=%02h actual_byte=%02h time=%0t"}),
                    int'(address - 32'(surface_base[0])) % surface_stride[0] / 2,
                    int'(address - 32'(surface_base[0])) / surface_stride[0],
                    expected[address], u_memory.mem[address], $time);
        end
    endtask

    task automatic reset_registers;
        expect_reg(12'h000, 32'h00030001);
        expect_reg(12'h004, 0);
        expect_reg(12'h008, 2);
        expect_reg(12'h00c, 0);
        expect_reg(12'h010, 0);
        expect_reg(12'h014, 0);
        expect_reg(12'h020, 0);
        expect_reg(12'h024, 0);
        expect_reg(12'h02c, 0);
        expect_reg(12'h100, 0);
        for (int index = 0; index < 16; index++) expect_reg(12'(64 + index * 4), 0);
        expect_reg(12'h080, 0);
        expect_reg(12'hffc, 0);
        equal("reset IRQ", 0, 32'(irq));
    endtask

    task automatic ge11_registers;
        logic [31:0] first_perf;
        logic [31:0] next_perf;
        int elapsed;
        reset_registers();
        write_reg(12'h000, 32'hffffffff);
        expect_reg(12'h000, 32'h00030001);
        write_reg(12'h008, 32'hffffffff);
        expect_reg(12'h008, 2);
        write_reg(12'h014, 32'hffffffff);
        expect_reg(12'h014, 0);
        write_reg(12'h004, 32'hfffffff3);
        expect_reg(12'h004, 1);
        expect_reg(12'h008, 2);
        write_reg(12'h004, 0);
        expect_reg(12'h004, 0);
        write_reg(12'h020, 32'h12345fff);
        expect_reg(12'h020, 32'h12345fe0);
        write_reg(12'h024, 32'hffff0000);
        expect_reg(12'h024, 0);
        write_reg(12'h028, 0);
        expect_reg(12'h010, 1);
        expect_reg(12'h008, 2);
        expect_reg(12'h02c, 0);
        expect_reg(12'h100, 0);
        equal("zero count no AXI", 0, 32'(u_memory.ar_count + u_memory.aw_count));
        equal("DONE IRQ reset mask", 0, 32'(irq));
        write_reg(12'h00c, 1);
        equal("DONE IRQ unmasked", 1, 32'(irq));
        write_reg(12'h010, 0);
        expect_reg(12'h010, 1);
        write_reg(12'h010, 1);
        equal("DONE IRQ RW1C", 0, 32'(irq));
        write_reg(12'h080, 32'hffffffff);
        expect_reg(12'h080, 0);
        write_reg(12'h004, 9);
        reset_registers();
        start_table();
        wait (u_memory.descriptor_ar_count != 0);
        expect_reg(12'h008, 1);
        // Fixed latency keeps descriptor reads pending while these writes are exercised.
        write_reg(12'h004, 9);
        expect_reg(12'h004, 1);
        expect_reg(12'h020, 32'h1000);
        expect_reg(12'h024, 32'(descriptor_count));
        expect_reg(12'h048, 0);
        read_reg(12'h040, first_perf);
        write_reg(12'h028, 0);
        read_reg(12'h040, next_perf);
        equal("busy DOORBELL does not clear PERF0", 1, 32'(next_perf > first_perf));
        check_completion();
        read_reg(12'h040, first_perf);
        for (int index = 0; index < 16; index++) begin
            read_reg(12'(64 + index * 4), next_perf);
            write_reg(12'(64 + index * 4), 32'hffffffff);
            expect_reg(12'(64 + index * 4), next_perf);
        end
        write_reg(12'h02c, 32'hffffffff);
        expect_reg(12'h02c, 1);
        write_reg(12'h100, 32'hffffffff);
        expect_reg(12'h100, 1);
        @(negedge clk_mem);
        u_memory.stop_ar = 1;
        u_memory.r_beats = 0;
        u_memory.w_beats = 0;
        start_table();
        expect_reg(12'h044, 0);
        expect_reg(12'h048, 0);
        expect_reg(12'h04c, 0);
        // Waiting may resume immediately after the clear, bounded by elapsed cycles.
        for (int index = 4; index < 6; index++) begin
            read_reg(12'(64 + index * 4), next_perf);
            elapsed = int'(($time - 4 - doorbell_time) / 8);
            if (next_perf > 32'(elapsed))
                $fatal(1, string'({"FAIL GE-11 PERF%0d clear desc=0 coord=(-1,-1) ",
                    "expected_max=%0d actual=%0d time=%0t"}),
                    index, elapsed, next_perf, $time);
        end
        read_reg(12'h040, next_perf);
        equal("new DOORBELL clears PERF0", 1, 32'(next_perf < first_perf));
        @(negedge clk_mem);
        u_memory.stop_ar = 0;
        check_completion();
        write_reg(12'h004, 8);
        reset_registers();
    endtask

    initial begin : run
        string config_path;
        string binary_path;
        int config_file;
        int binary_file;
        int segments;
        int address;
        int length;
        int count;
        apb.paddr = 0;
        apb.psel = 0;
        apb.penable = 0;
        apb.pwrite = 0;
        apb.pwdata = 0;
        apb.pstrb = 0;
        if (!$value$plusargs("CONFIG=%s", config_path))
            $fatal(1, "FAIL config desc=0 coord=(-1,-1) expected=CONFIG actual=missing time=%0t",
                $time);
        config_file = $fopen(config_path, "r");
        equal("config open", 1, 32'(config_file != 0));
        count = $fscanf(config_file, "%d %d %d %d %d %d %d %d %d %d %d %d %d",
            test_case, descriptor_count, expected_error, injection, abort_phase,
            latency, stalls, bandwidth, response_delay, perf_limit_ns, seed, segments,
            surface_count);
        equal("config header fields", 13, 32'(count));
        repeat (5) @(negedge clk_mem);
        rst_mem_n = 1;
        for (int index = 0; index < segments; index++) begin
            count = $fscanf(config_file, "%d %d %s", address, length, binary_path);
            equal("input segment fields", 3, 32'(count));
            binary_file = $fopen(binary_path, "rb");
            equal("input binary open", 1, 32'(binary_file != 0));
            count = $fread(u_memory.mem, binary_file, address, length);
            equal("input byte count", 32'(length), 32'(count));
            $fclose(binary_file);
        end
        for (int index = 0; index < surface_count; index++) begin
            count = $fscanf(config_file, "%d %d %d %d %d %d %s", surface_desc[index],
                surface_base[index], surface_stride[index], surface_height[index],
                surface_x[index], surface_y[index], binary_path);
            equal("reference segment fields", 7, 32'(count));
            binary_file = $fopen(binary_path, "rb");
            equal("reference binary open", 1, 32'(binary_file != 0));
            length = surface_stride[index] * surface_height[index];
            count = $fread(expected, binary_file, surface_base[index], length);
            equal("reference byte count", 32'(length), 32'(count));
            $fclose(binary_file);
        end
        $fclose(config_file);
        if (test_case == 9) begin
            second_before = new[surface_stride[1] * surface_height[1]];
            for (int offset = 0; offset < second_before.size(); offset++)
                second_before[offset] = u_memory.mem[surface_base[1]+offset];
        end
        @(negedge clk_mem);
        u_memory.read_latency = latency;
        u_memory.b_delay = response_delay;
        u_memory.random_percent = stalls;
        u_memory.bandwidth_limit = bandwidth != 0;
        u_memory.random_state = 32'h6e012345 ^ 32'(seed);
        u_memory.error_kind = injection;
        u_memory.desc_count = descriptor_count;
        u_memory.check_dependency = test_case == 7;
        if (test_case == 11) ge11_registers();
        else begin
            start_table();
            if (test_case == 10) ge10_abort();
            else if (expected_error != 0) check_error();
            else check_completion();
        end
        $display("PASS GE-%02d seed=%0d (public-port checks)", test_case, seed);
        $finish;
    end

    initial begin : watchdog
        #100000000;
        $fatal(1, string'({"FAIL GE-%02d timeout desc=%0d coord=(-1,-1) ",
            "expected=completion actual=100ms time=%0t"}), test_case, current_desc, $time);
    end
endmodule
