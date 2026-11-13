// File: edrv32_rnd_tb.sv
// Spec: rnd 2–7; rnd-testplan RN-01–16, RN-18–19; SoC 4.2, 4.3, 7.1.
// Description: Public-port harness, whole-memory Python scoreboard, error/recovery,
//              ABORT, register checks and 125 MHz performance measurements.
// Clock domain: clk_mem.
`timescale 1ns/1ps
module edrv32_rnd_tb;
    logic clk_mem = 0;
    logic rst_mem_n = 0;
    logic irq;
    edrv32_apb_if apb();
    edrv32_axi256_if axi();
    int checker_errors;
    byte unsigned file_buffer[0:16*1024*1024-1];
    byte unsigned initial_memory[];
    byte unsigned expected[];
    byte unsigned partial[];
    byte unsigned recovery[];
    int test_case;
    int descriptor_count;
    int expected_error;
    int injection;
    int abort_phase;
    int latency;
    int stalls;
    int response_delay;
    int seed;
    int perf_kind;
    int zero_writes;
    int memory_size;
    int pixels;
    int expected_done;
    int temp_base[$];
    int temp_size[$];
    int current_desc = 0;
    int total_done = 0;
    int r_start;
    int w_start;
    time doorbell_time;
    int perf_lower;
    int perf_upper;
    bit normal_execution = 0;
    bit abort_accepted = 0;
    int abort_ar_count;
    string initial_path;
    string expected_path;
    string partial_path;
    string recovery_path;

    always #4 clk_mem = ~clk_mem;

    assign apb.prdata[127:0] = 0;
    assign apb.prdata[511:160] = 0;
    assign apb.pready[3:0] = 0;
    assign apb.pready[15:5] = 0;
    assign apb.pslverr[3:0] = 0;
    assign apb.pslverr[15:5] = 0;

    edrv32_rnd_memory u_memory (
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

    edrv32_rnd u_rnd (
        .clk_mem_i(clk_mem),
        .rst_mem_n_i(rst_mem_n),

        .apb_paddr_i(apb.paddr),
        .apb_psel_i(apb.psel[4]),
        .apb_penable_i(apb.penable),
        .apb_pwrite_i(apb.pwrite),
        .apb_pwdata_i(apb.pwdata),
        .apb_pstrb_i(apb.pstrb),
        .apb_pready_o(apb.pready[4]),
        .apb_prdata_o(apb.prdata[159:128]),
        .apb_pslverr_o(apb.pslverr[4]),

        .p4_awid_o(axi.awid),
        .p4_awaddr_o(axi.awaddr),
        .p4_awlen_o(axi.awlen),
        .p4_awvalid_o(axi.awvalid),
        .p4_awready_i(axi.awready),
        .p4_wdata_o(axi.wdata),
        .p4_wstrb_o(axi.wstrb),
        .p4_wlast_o(axi.wlast),
        .p4_wvalid_o(axi.wvalid),
        .p4_wready_i(axi.wready),
        .p4_bid_i(axi.bid),
        .p4_bresp_i(axi.bresp),
        .p4_bvalid_i(axi.bvalid),
        .p4_bready_o(axi.bready),

        .p4_arid_o(axi.arid),
        .p4_araddr_o(axi.araddr),
        .p4_arlen_o(axi.arlen),
        .p4_arvalid_o(axi.arvalid),
        .p4_arready_i(axi.arready),
        .p4_rid_i(axi.rid),
        .p4_rdata_i(axi.rdata),
        .p4_rresp_i(axi.rresp),
        .p4_rlast_i(axi.rlast),
        .p4_rvalid_i(axi.rvalid),
        .p4_rready_o(axi.rready),

        .irq_o(irq)
    );

    task automatic equal(input string what_i,
        input logic [31:0] expected_i,
        input logic [31:0] actual_i);
        if (actual_i !== expected_i)
            $fatal(1, "%s expected=%08h actual=%08h time=%0t",
                $sformatf("FAIL RN-%02d %s desc=%0d coord=(-1,-1)",
                    test_case, what_i, current_desc), expected_i, actual_i, $time);
    endtask

    always @(negedge clk_mem) begin
        if (rst_mem_n) begin
            equal("P4 ARID", 0, 32'(axi.arid));
            equal("P4 AWID", 0, 32'(axi.awid));
            if (normal_execution && irq) begin
                equal("DONE after B drain", 32'(u_memory.aw_count), 32'(u_memory.b_count));
                equal("DONE after R drain", 32'(u_memory.ar_count), 32'(u_memory.r_count));
            end
            if (abort_accepted)
                equal("ABORT stops new AR", 32'(abort_ar_count), 32'(u_memory.ar_count));
        end
    end

    task automatic apb_access(input bit write_i,
        input logic [11:0] address_i,
        input logic [31:0] data_i,
        output logic [31:0] data_o);
        @(negedge clk_mem);
        apb.paddr = address_i;
        apb.pwrite = write_i;
        apb.pwdata = data_i;
        // rnd 4: all writes are full-word regardless of PSTRB, including zero.
        apb.pstrb = address_i[3:0];
        apb.psel = 16'h0010;
        apb.penable = 0;
        @(negedge clk_mem);
        apb.penable = 1;
        @(posedge clk_mem);
        equal("APB PREADY", 1, 32'(apb.pready[4]));
        equal("APB PSLVERR", 0, 32'(apb.pslverr[4]));
        data_o = apb.prdata[159:128];
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

    function automatic bit temporary(input int address_i);
        foreach (temp_base[i]) begin
            if (address_i >= temp_base[i] && address_i < temp_base[i] + temp_size[i])
                return 1;
        end
        return 0;
    endfunction

    task automatic mismatch(input int address_i,
        input byte unsigned wanted_i,
        input byte unsigned actual_i);
        int base;
        int stride;
        int pixel_bytes;
        int height;
        int x;
        int y;
        x = -1;
        y = -1;
        current_desc = -1;
        // Last matching destination identifies command and coordinates; sources use (-1,-1).
        for (int index = 0; index < descriptor_count; index++) begin
            base = int'(memory_word(32'h1000 + index * 64 + 4));
            stride = int'(memory_word(32'h1000 + index * 64 + 8) & 32'hffff);
            pixel_bytes = (memory_word(32'h1000 + index * 64) & 32'h100) != 0 ? 4 : 2;
            height = int'((memory_word(32'h1000 + index * 64 + 16) >> 16) & 4095) + 1;
            if (stride != 0 && address_i >= base - stride
                && address_i < base + stride * (height + 1)) begin
                current_desc = index;
                x = (address_i - base) % stride / pixel_bytes;
                y = (address_i - base) / stride;
            end
        end
        $fatal(1, "%s addr=%08h expected=%02h actual=%02h time=%0t",
            $sformatf("FAIL RN-%02d memory desc=%0d coord=(%0d,%0d)",
                test_case, current_desc, x, y), address_i, wanted_i, actual_i, $time);
    endtask

    task automatic compare_memory(input bit incomplete_i);
        byte unsigned wanted;
        for (int address = 0; address < memory_size; address++) begin
            if (!temporary(address)) begin
                wanted = expected[address];
                if (incomplete_i)
                    wanted = u_memory.written.exists(32'(address)) != 0
                        ? partial[address] : initial_memory[address];
                if (u_memory.mem[address] !== wanted)
                    mismatch(address, wanted, u_memory.mem[address]);
            end
        end
    endtask

    task automatic drain_check;
        equal("AW/W/B drained", 0,
            32'(u_memory.writes.size()
                + u_memory.responses.size()));
        equal("AR/R drained", 0, 32'(u_memory.reads.size()));
        equal("AW count == B count", 32'(u_memory.aw_count), 32'(u_memory.b_count));
        equal("AR count == RLAST", 32'(u_memory.ar_count), 32'(u_memory.r_count));
        equal("checker errors", 0, 32'(checker_errors));
        equal("checker AW drained", 0, 32'(u_checker.aw_queue.size()));
        equal("checker W drained", 0, 32'(u_checker.w_queue.size()));
        equal("checker partial W drained", 0, 32'(u_checker.w_count));
        for (int id = 0; id < 16; id++) begin
            equal("checker B drained", 0, 32'(u_checker.b_pending[id]));
            equal("checker R drained", 0, 32'(u_checker.r_queue[id].size()));
        end
    endtask

    task automatic start_table;
        write_reg(12'h010, 3);
        write_reg(12'h00c, 3);
        write_reg(12'h020, 32'h103f);
        write_reg(12'h024, 32'habcd0000 | 32'(descriptor_count));
        r_start = u_memory.r_beats;
        w_start = u_memory.w_beats;
        normal_execution = expected_error == 0 && abort_phase == 0;
        write_reg(12'h028, 32'hfeed1234);
        doorbell_time = $time - 4;
        perf_lower = 0;
        perf_upper = 0;
    endtask

    task automatic wait_idle;
        logic [31:0] status;
        logic [31:0] completed;
        logic [31:0] cur;
        int previous;
        previous = total_done;
        do begin
            read_reg(12'h008, status);
            equal("STATUS reserved", 0, status & 32'hfffffff8);
            equal("STATUS IDLE inverse BUSY", 32'(!status[0]), 32'(status[1]));
            if (status[0]) perf_lower = int'(($time - 4 - doorbell_time) / 8);
            else perf_upper = int'(($time - 4 - doorbell_time) / 8);
            if (test_case == 14) begin
                read_reg(12'h02c, completed);
                if (completed != 32'(previous)) begin
                    equal("DONE_COUNT advances one command", 32'(previous + 1), completed);
                    previous++;
                    current_desc = previous - total_done - 1;
                    read_reg(12'h100, cur);
                    equal("CUR_DESC advances with DONE_COUNT", completed - 32'(total_done), cur);
                end
            end
        end while (status[0]);
        drain_check();
    endtask

    task automatic check_perf;
        logic [31:0] cycles;
        logic [31:0] source_wait;
        logic [31:0] writer_wait;
        read_reg(12'h040, cycles);
        equal("PERF0 within observed busy interval", 1,
            32'(cycles >= 32'(perf_lower) && cycles <= 32'(perf_upper)));
        expect_reg(12'h040, cycles);
        expect_reg(12'h044, 32'(pixels));
        expect_reg(12'h048, 32'(u_memory.r_beats - r_start));
        expect_reg(12'h04c, 32'(u_memory.w_beats - w_start));
        for (int index = 6; index < 16; index++) expect_reg(12'(64 + index * 4), 0);
        if (perf_kind != 0) begin
            read_reg(12'h050, source_wait);
            read_reg(12'h054, writer_wait);
            $write("RN-18 kind=%0d read_latency=%0d PERF0=%0d PERF1=%0d ",
                perf_kind < 0 ? -perf_kind : perf_kind, latency, cycles, pixels);
            $write("threshold_check=%0d time_ms=%0.6f pixels_per_cycle=%0.6f ",
                perf_kind > 0, real'(cycles) * 8.0 / 1000000.0,
                real'(pixels) / real'(cycles));
            $display("cycles_per_glyph=%0.3f PERF4=%0d PERF5=%0d",
                real'(cycles) / 1000.0, source_wait, writer_wait);
            if (perf_kind == 1) equal("ARGB fill <=3ms", 1, 32'(cycles <= 375000));
            if (perf_kind == 2) equal("RGB565 fill <=1.5ms", 1, 32'(cycles <= 187500));
            if (perf_kind == 3)
                equal("BLIT PERF1/PERF0 >=1.5", 1, 32'(pixels * 2 >= int'(cycles) * 3));
        end
    endtask

    task automatic check_completion;
        wait_idle();
        total_done += expected_done;
        expect_reg(12'h008, 2);
        expect_reg(12'h010, 1);
        expect_reg(12'h014, 0);
        expect_reg(12'h02c, 32'(total_done));
        expect_reg(12'h100, 32'(descriptor_count));
        equal("DONE IRQ enabled", 1, 32'(irq));
        if (zero_writes != 0) equal("empty area produces no W", 32'(w_start),
            32'(u_memory.w_beats));
        check_perf();
        compare_memory(0);
        write_reg(12'h00c, 0);
        equal("DONE IRQ masked", 0, 32'(irq));
        write_reg(12'h00c, 1);
        equal("DONE IRQ unmasked", 1, 32'(irq));
        write_reg(12'h010, 1);
        equal("DONE W1C", 0, 32'(irq));
    endtask

    task automatic load_binary(input string path_i,
        ref byte unsigned bytes_io[]);
        int fd;
        int count;
        bytes_io = new[memory_size];
        fd = $fopen(path_i, "rb");
        if (fd == 0) $fatal(1, "FAIL cannot open %s", path_i);
        count = $fread(file_buffer, fd, 0, memory_size);
        foreach (bytes_io[i]) bytes_io[i] = file_buffer[i];
        $fclose(fd);
        equal("binary size", 32'(memory_size), 32'(count));
    endtask

    task automatic check_error;
        logic [31:0] stopped_cycles;
        wait_idle();
        expect_reg(12'h008, 6);
        expect_reg(12'h010, 2);
        expect_reg(12'h014, 32'(expected_error));
        expect_reg(12'h02c, 0);
        expect_reg(12'h100, 0);
        equal("ERROR IRQ enabled", 1, 32'(irq));
        equal("no next descriptor", 0, 32'(u_memory.max_desc_read));
        read_reg(12'h040, stopped_cycles);
        equal("error PERF0 counts until idle", 1,
            32'(stopped_cycles >= 32'(perf_lower) && stopped_cycles <= 32'(perf_upper)));
        expect_reg(12'h040, stopped_cycles);
        if (expected_error == 3) begin
            equal("illegal before data AR", 0, 32'(u_memory.source_ar_count));
            equal("illegal has no AW", 0, 32'(u_memory.aw_count));
        end else equal("SLVERR injected", 1, 32'(u_memory.injected));
        compare_memory(1);
        write_reg(12'h00c, 0);
        equal("ERROR IRQ masked", 0, 32'(irq));
        write_reg(12'h00c, 2);
        equal("ERROR IRQ unmasked", 1, 32'(irq));
        write_reg(12'h010, 2);
        expect_reg(12'h014, 0);
        expect_reg(12'h010, 0);
        expect_reg(12'h008, 2);
        equal("ERROR clear IRQ", 0, 32'(irq));
        // RN-15 explicitly restarts after ERROR clear, without resetting the DUT.
        @(negedge clk_mem);
        foreach (recovery[i]) u_memory.mem[i] = recovery[i];
        u_memory.error_kind = 0;
        u_memory.max_desc_read = -1;
        u_memory.written.delete();
        expected_error = 0;
        start_table();
        check_completion();
    endtask

    task automatic check_abort;
        logic [31:0] stopped_cycles;
        if (abort_phase == 1) wait (u_memory.descriptor_ar_count != 0);
        else if (abort_phase == 2) begin
            if (u_memory.mem[32'h1000] == 8'h05) wait (u_memory.source_ar_count != 0);
            else wait (u_memory.target_ar_count != 0);
        end
        else wait (u_memory.w_beats != 0);
        if (abort_phase != 3) equal("ABORT with R pending", 1,
            32'(u_memory.ar_count > u_memory.r_count));
        else equal("ABORT with B pending", 1,
            32'(u_memory.aw_count > u_memory.b_count));
        write_reg(12'h004, 4);
        abort_accepted = 1;
        abort_ar_count = u_memory.ar_count;
        wait_idle();
        expect_reg(12'h008, 2);
        expect_reg(12'h010, 0);
        expect_reg(12'h014, 0);
        expect_reg(12'h02c, 0);
        expect_reg(12'h100, 0);
        equal("ABORT no IRQ", 0, 32'(irq));
        equal("ABORT no next descriptor", 0, 32'(u_memory.max_desc_read));
        read_reg(12'h040, stopped_cycles);
        equal("ABORT PERF0 counts until idle", 1,
            32'(stopped_cycles >= 32'(perf_lower) && stopped_cycles <= 32'(perf_upper)));
        expect_reg(12'h040, stopped_cycles);
        compare_memory(1);
    endtask

    task automatic reset_registers;
        expect_reg(12'h000, 32'h00040001);
        expect_reg(12'h004, 0);
        expect_reg(12'h008, 2);
        expect_reg(12'h00c, 0);
        expect_reg(12'h010, 0);
        expect_reg(12'h014, 0);
        expect_reg(12'h020, 0);
        expect_reg(12'h024, 0);
        expect_reg(12'h028, 0);
        expect_reg(12'h02c, 0);
        expect_reg(12'h100, 0);
        for (int index = 0; index < 16; index++) expect_reg(12'(64 + index * 4), 0);
        expect_reg(12'h080, 0);
        expect_reg(12'hffc, 0);
        equal("reset IRQ", 0, 32'(irq));
    endtask

    task automatic register_test;
        logic [31:0] value;
        logic [31:0] previous_perf;
        reset_registers();
        write_reg(12'h000, 32'hffffffff);
        expect_reg(12'h000, 32'h00040001);
        write_reg(12'h008, 32'hffffffff);
        expect_reg(12'h008, 2);
        write_reg(12'h014, 32'hffffffff);
        expect_reg(12'h014, 0);
        write_reg(12'h02c, 32'hffffffff);
        expect_reg(12'h02c, 0);
        write_reg(12'h100, 32'hffffffff);
        expect_reg(12'h100, 0);
        for (int index = 0; index < 16; index++) write_reg(12'(64 + index * 4), 32'hffffffff);
        for (int index = 0; index < 16; index++) expect_reg(12'(64 + index * 4), 0);
        write_reg(12'hffc, 32'hffffffff);
        expect_reg(12'hffc, 0);
        write_reg(12'h004, 3);
        expect_reg(12'h004, 1);
        write_reg(12'h004, 0);
        expect_reg(12'h004, 0);
        write_reg(12'h020, 32'h12345fff);
        expect_reg(12'h020, 32'h12345fc0);
        write_reg(12'h024, 32'hffff0000);
        expect_reg(12'h024, 0);
        write_reg(12'h00c, 3);
        write_reg(12'h028, 0);
        expect_reg(12'h010, 1);
        expect_reg(12'h02c, 0);
        expect_reg(12'h008, 2);
        equal("zero count DONE", 1, 32'(irq));
        write_reg(12'h004, 8);
        reset_registers();
        start_table();
        expect_reg(12'h008, 1);
        // Busy DOORBELL cannot queue a second list; busy SOFT_RST cannot erase registers.
        write_reg(12'h028, 1);
        write_reg(12'h004, 8);
        expect_reg(12'h020, 32'h1000);
        expect_reg(12'h024, 32'(descriptor_count));
        check_completion();
        write_reg(12'h004, 8);
        total_done = 0;
        reset_registers();
        // A second nonempty list followed by an empty list makes PERF reset observable.
        start_table();
        check_completion();
        read_reg(12'h044, value);
        equal("nonempty PERF1", 32'(pixels), value);
        read_reg(12'h040, previous_perf);
        write_reg(12'h024, 0);
        write_reg(12'h028, 1);
        expect_reg(12'h044, 0);
        expect_reg(12'h048, 0);
        expect_reg(12'h04c, 0);
        expect_reg(12'h050, 0);
        expect_reg(12'h054, 0);
        read_reg(12'h040, value);
        equal("empty list PERF0 resets", 1, 32'(value < previous_perf));
        expect_reg(12'h010, 1);
        expect_reg(12'h02c, 32'(total_done));
    endtask

    initial begin : stimulus
        string config_path;
        int fd;
        int count;
        int regions;
        int base;
        int size;
        apb.paddr = 0;
        apb.psel = 0;
        apb.penable = 0;
        apb.pwrite = 0;
        apb.pwdata = 0;
        apb.pstrb = 0;
        // Compile-only port-stub run never claims renderer correctness.
        if ($test$plusargs("PORT_STUB")) begin
            repeat (4) @(negedge clk_mem);
            $display("PASS RND public-port stub elaboration");
            $finish;
        end else begin
            if (!$value$plusargs("CONFIG=%s", config_path))
                $fatal(1, "FAIL CONFIG plusarg required");
            fd = $fopen(config_path, "r");
            if (fd == 0) $fatal(1, "FAIL cannot open %s", config_path);
            count = $fscanf(fd, "%d %d %d %d %d %d %d %d %d %d %d %d %d %d\n",
                test_case, descriptor_count, expected_error, injection, abort_phase,
                latency, stalls, response_delay, seed, perf_kind, zero_writes, memory_size,
                pixels, expected_done);
            equal("config header fields", 14, 32'(count));
            count = $fscanf(fd, "%s\n%s\n%s\n%s\n%d\n", initial_path, expected_path,
                partial_path, recovery_path, regions);
            equal("config image fields", 5, 32'(count));
            for (int i = 0; i < regions; i++) begin
                count = $fscanf(fd, "%d %d\n", base, size);
                equal("config temp fields", 2, 32'(count));
                temp_base.push_back(base);
                temp_size.push_back(size);
            end
            $fclose(fd);
            load_binary(initial_path, initial_memory);
            load_binary(expected_path, expected);
            load_binary(partial_path, partial);
            load_binary(recovery_path, recovery);
            foreach (initial_memory[i]) u_memory.mem[i] = initial_memory[i];
            u_memory.memory_size = memory_size;
            u_memory.desc_count = descriptor_count;
            u_memory.read_latency = latency;
            u_memory.random_percent = stalls;
            u_memory.b_delay = response_delay;
            u_memory.error_kind = injection;
            u_memory.random_state = 32'(seed) | 32'h524e4400;
            repeat (5) @(negedge clk_mem);
            rst_mem_n = 1;
            repeat (2) @(negedge clk_mem);
            if (test_case == 16) register_test();
            else begin
                start_table();
                if (abort_phase != 0) check_abort();
                else if (expected_error != 0) check_error();
                else check_completion();
            end
            $display("PASS RN-%02d commands=%0d seed=%0d", test_case, descriptor_count, seed);
            $finish;
        end
    end

    initial begin
        #2000000000;
        $fatal(1, "FAIL RN-%02d timeout desc=%0d coord=(-1,-1) expected=IDLE actual=BUSY time=%0t",
            test_case, current_desc, $time);
    end
endmodule
