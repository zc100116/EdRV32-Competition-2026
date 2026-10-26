// File: edrv32_mem_components_tb.sv
// Spec: mem-subsys-testplan 2.2-2.3; task M-V1 acceptance.
// Description: Self-tests DDR timing/data, checker alarms, and queued master traffic.
// Clock domain: clk_mem.
module edrv32_mem_components_tb;
    timeunit 1ns;
    timeprecision 1ps;
    parameter int CASE = 0;
    logic clk_mem = 0;
    logic rst_mem_n = 0;
    always #4ns clk_mem = !clk_mem;
    edrv32_axi256_if #(.ID_WIDTH(4)) ddr();
    edrv32_axi256_if #(.ID_WIDTH(4)) raw();
    bit specialized_done;
    logic urgent;
    int urgent_high;
    int urgent_low;
    typedef struct packed {
        bit [3:0] id;
        bit [255:0] data;
        bit [1:0] resp;
        bit last;
    } read_t;
    typedef struct packed {
        bit [3:0] id;
        bit [1:0] resp;
    } b_t;
    read_t read_queue[$];
    b_t b_queue[$];
    int errors;
    int checked;
    int committed;
    int cycle = 0;
    int ar_cycle;
    int first_r_cycle;
    int latency;
    bit capture_latency;
    bit capture_refresh_gap = 0;
    int seen_reads;
    int seen_writes;
    int last_data_cycle;
    bit last_data_write;
    int min_turn_gap;
    int last_write_cycle;
    int previous_refresh_r;
    int max_refresh_gap;
    bit [255:0] data[16];
    bit [31:0] strb[16];
    edrv32_axi256_master u_master (
        .clk_i(clk_mem),
        .rst_n_i(rst_mem_n),
        .urgent_o(urgent),
        .bus(ddr)
    );
    edrv32_axi256_checker #(
        .DOWNSTREAM(CASE != 2),
        .FATAL(CASE != 1)
    ) u_checker (
        .clk_i(clk_mem),
        .rst_n_i(rst_mem_n),
        .bus(ddr),
        .errors_o(errors)
    );
    edrv32_axi256_reference #(.DOWNSTREAM(CASE != 2)) u_reference (
        .clk_i(clk_mem),
        .rst_n_i(rst_mem_n),
        .bus(ddr),
        .checked_beats_o(checked),
        .committed_writes_o(committed)
    );
    `include "component_ddr_connection.svh"

    assign raw.awid = ddr.awid;
    assign raw.awaddr = ddr.awaddr;
    assign raw.awlen = ddr.awlen;
    assign raw.awvalid = ddr.awvalid;
    assign raw.wdata = ddr.wdata;
    assign raw.wstrb = ddr.wstrb;
    assign raw.wlast = ddr.wlast;
    assign raw.wvalid = ddr.wvalid;
    assign raw.arid = ddr.arid;
    assign raw.araddr = ddr.araddr;
    assign raw.arlen = ddr.arlen;
    assign raw.arvalid = ddr.arvalid;
    assign ddr.awready = raw.awready;
    assign ddr.wready = raw.wready;
    assign ddr.arready = raw.arready;
    if (CASE == 2) begin : g_backpressure
        always_comb begin
            ddr.bvalid = b_queue.size() != 0;
            ddr.bid = b_queue.size() != 0 ? b_queue[0].id : 0;
            ddr.bresp = b_queue.size() != 0 ? b_queue[0].resp : 0;
            ddr.rvalid = read_queue.size() != 0;
            ddr.rid = read_queue.size() != 0 ? read_queue[0].id : 0;
            ddr.rdata = read_queue.size() != 0 ? read_queue[0].data : 0;
            ddr.rresp = read_queue.size() != 0 ? read_queue[0].resp : 0;
            ddr.rlast = read_queue.size() != 0 ? read_queue[0].last : 0;
        end
        always @(posedge clk_mem) begin : buffer_responses
            read_t r;
            b_t b;
            if (!rst_mem_n) begin
                read_queue.delete();
                b_queue.delete();
            end else begin
                if (ddr.rvalid && ddr.rready) r = read_queue.pop_front();
                if (ddr.bvalid && ddr.bready) b = b_queue.pop_front();
                if (raw.rvalid) begin
                    r.id = raw.rid;
                    r.data = raw.rdata;
                    r.resp = raw.rresp;
                    r.last = raw.rlast;
                    read_queue.push_back(r);
                end
                if (raw.bvalid) begin
                    b.id = raw.bid;
                    b.resp = raw.bresp;
                    b_queue.push_back(b);
                end
            end
        end
    end else begin : g_unbuffered
        assign ddr.bid = raw.bid;
        assign ddr.bresp = raw.bresp;
        assign ddr.bvalid = raw.bvalid;
        assign ddr.rid = raw.rid;
        assign ddr.rdata = raw.rdata;
        assign ddr.rresp = raw.rresp;
        assign ddr.rlast = raw.rlast;
        assign ddr.rvalid = raw.rvalid;
    end

    if (CASE == 2) begin : g_specialized
        edrv32_axi256_if p0();
        edrv32_axi256_if p1();
        logic read_urgent;
        logic write_urgent;
        int read_errors;
        int write_errors;
        edrv32_axi256_master #(.READ_ONLY(1)) u_read (
            .clk_i(clk_mem),
            .rst_n_i(rst_mem_n),
            .urgent_o(read_urgent),
            .bus(p0)
        );
        edrv32_axi256_master #(.WRITE_ONLY(1)) u_write (
            .clk_i(clk_mem),
            .rst_n_i(rst_mem_n),
            .urgent_o(write_urgent),
            .bus(p1)
        );
        edrv32_mem_master_slave u_read_slave (
            .clk_i(clk_mem),
            .rst_n_i(rst_mem_n),
            .bus(p0)
        );
        edrv32_mem_master_slave u_write_slave (
            .clk_i(clk_mem),
            .rst_n_i(rst_mem_n),
            .bus(p1)
        );
        edrv32_axi256_checker u_read_checker (
            .clk_i(clk_mem),
            .rst_n_i(rst_mem_n),
            .bus(p0),
            .errors_o(read_errors)
        );
        edrv32_axi256_checker u_write_checker (
            .clk_i(clk_mem),
            .rst_n_i(rst_mem_n),
            .bus(p1),
            .errors_o(write_errors)
        );
        initial begin
            bit [255:0] zeros[16];
            bit [31:0] strobes[16];
            specialized_done = 0;
            wait (rst_mem_n);
            @(negedge clk_mem);
            g_specialized.u_read.r_period = 11;
            g_specialized.u_read.r_on = 2;
            g_specialized.u_write.b_period = 13;
            g_specialized.u_write.b_on = 2;
            for (int n = 0; n < 16; n++) begin
                zeros[n] = 0;
                strobes[n] = '1;
            end
            for (int n = 0; n < 8; n++) begin
                g_specialized.u_read.enqueue_read(32'(n*512), n);
                g_specialized.u_write.enqueue_write(32'(n*512), n, zeros, strobes);
            end
            g_specialized.u_read.wait_done(8, 0);
            g_specialized.u_write.wait_done(0, 8);
            eq("P0 no writes", 0, g_specialized.u_read.writes_done);
            eq("P1 no reads", 0, g_specialized.u_write.reads_done);
            eq("P0 protocol", 0, read_errors);
            eq("P1 protocol", 0, write_errors);
            specialized_done = 1;
        end
    end else begin : g_no_specialized
        assign specialized_done = 1;
    end

    always @(posedge clk_mem) begin
        if (rst_mem_n && urgent) urgent_high++;
        if (rst_mem_n && !urgent) urgent_low++;
        cycle <= cycle+1;
        if (ddr.arvalid && ddr.arready) ar_cycle <= cycle;
        if (ddr.rvalid && capture_latency) begin
            first_r_cycle <= cycle;
            latency <= cycle-ar_cycle;
            capture_latency <= 0;
        end
    end

    // The model's data-bus counters expose execution, distinct from buffered W acceptance.
    always @(negedge clk_mem) begin : check_model_data_timing
        bit write_data;
        int gap;
        if (!rst_mem_n) begin
            seen_reads = 0;
            seen_writes = 0;
            last_data_cycle = -1;
            min_turn_gap = 'h7fffffff;
            last_write_cycle = 0;
            previous_refresh_r = 0;
            max_refresh_gap = 0;
        end else if (CASE == 0) begin
            if (u_ddr.read_data_beats != seen_reads || u_ddr.write_data_beats != seen_writes) begin
                write_data = u_ddr.write_data_beats != seen_writes;
                if (last_data_cycle >= 0 && last_data_write != write_data) begin
                    gap = u_ddr.cycle-last_data_cycle;
                    if (gap < min_turn_gap) min_turn_gap = gap;
                end
                last_data_cycle = u_ddr.cycle;
                last_data_write = write_data;
                if (write_data && u_ddr.beat == 0) last_write_cycle = u_ddr.cycle;
                seen_reads = u_ddr.read_data_beats;
                seen_writes = u_ddr.write_data_beats;
            end
            if (raw.bvalid)
                eq("DDR last write to B delay", u_ddr.t_b, u_ddr.cycle-last_write_cycle+1);
            if (capture_refresh_gap && raw.rvalid) begin
                if (previous_refresh_r != 0) begin
                    gap = u_ddr.cycle-previous_refresh_r;
                    if (gap > max_refresh_gap) max_refresh_gap = gap;
                end
                previous_refresh_r = u_ddr.cycle;
            end
        end
    end

    task automatic eq(input string name,
        input int expected,
        input int actual);
        if (actual != expected)
            $fatal(1, "FAIL %s expected=%0d actual=%0d time=%0t", name, expected, actual, $time);
    endtask

    task automatic measure(input bit [31:0] addr,
        input int expected);
        capture_latency = 1;
        u_master.enqueue_read(addr, 0);
        u_master.wait_done(u_master.reads_done+1, u_master.writes_done);
        eq("first beat latency", expected, latency);
    endtask

    initial begin
        #2ms;
        $fatal(1, "FAIL component timeout expected=completion actual=stalled time=%0t", $time);
    end

    initial begin
        capture_latency = 0;
        repeat (4) @(negedge clk_mem);
        rst_mem_n = 1;
        @(negedge clk_mem);
        if (CASE == 0) begin
            measure(32'h0, 12);
            measure(32'h20, 8);
            measure(32'h8000, 12);
            measure(32'h1000, 12);
            measure(32'h1020, 8);
            for (int n = 0; n < 16; n++) begin
                data[n] = {8{32'h12345678 ^ 32'(n)}};
                strb[n] = n[0] ? 32'h55555555 : 32'haaaaaaaa;
            end
            u_master.enqueue_write(32'h2000, 15, data, strb, 1);
            u_master.wait_done(5, 1);
            u_master.enqueue_read(32'h2000, 15, 1);
            u_master.wait_done(6, 1);
            eq("committed writes", 1, committed);
            eq("reference checked beats", 21, checked);
            if (u_ddr.turns < 2)
                $fatal(1, "FAIL turnaround expected=>=2 actual=%0d time=%0t", u_ddr.turns, $time);
            // Both commands are queued before the write finishes, so turnaround
            // dominates the next read's ready time rather than command latency.
            u_master.enqueue_write(32'h8000, 15, data, strb);
            u_master.enqueue_read(32'h8000, 15);
            u_master.wait_done(7, 2);
            eq("DDR turnaround gap", u_ddr.t_turn+1, min_turn_gap);
            wait (u_ddr.cycle >= u_ddr.refresh_next-20);
            @(negedge clk_mem);
            capture_refresh_gap = 1;
            u_master.enqueue_read(32'h2000, 15);
            u_master.wait_done(8, 2);
            capture_refresh_gap = 0;
            eq("DDR exact refresh interruption", u_ddr.t_rfc+1, max_refresh_gap);
            eq("checker errors", 0, errors);
        end else if (CASE == 1) begin
            u_master.enqueue_read(32'h00000fe0, 1);
            u_master.wait_done(1, 0);
            eq("4KiB alarm", 1, errors);
            u_master.enqueue_read(32'h00001001, 0);
            u_master.wait_done(2, 0);
            eq("alignment alarm", 2, errors);
        end else begin
            u_master.r_random = 1;
            u_master.b_random = 1;
            u_master.urgent_random = 1;
            u_master.seed_random(32'h987123ad);
            u_master.r_period = 13;
            u_master.r_on = 3;
            u_master.b_period = 11;
            u_master.b_on = 2;
            u_master.data_delay = 7;
            u_master.data_gap = 3;
            u_master.urgent_enable = 1;
            u_master.urgent_period = 4;
            u_master.urgent_on = 2;
            for (int k = 0; k < 12; k++) begin
                for (int n = 0; n < 16; n++) begin
                    data[n] = {8{32'(k*16+n)}};
                    strb[n] = '1;
                end
                u_master.enqueue_write(32'(k*512), 15, data, strb, 1'(k));
            end
            u_master.wait_done(0, 12);
            for (int k = 0; k < 12; k++)
                u_master.enqueue_read(32'(k*512), 15, 1'(k));
            u_master.wait_done(12, 12);
            eq("master read beats", 192, u_master.r_beats);
            if (urgent_high == 0 || urgent_low == 0)
                $fatal(1, "FAIL urgent expected=both levels actual=%0d/%0d time=%0t",
                       urgent_high, urgent_low, $time);
            eq("checker errors", 0, errors);
        end
        do @(negedge clk_mem); while (!specialized_done);
        $display("PASS mem components CASE=%0d checked=%0d writes=%0d time=%0t",
                 CASE, checked, committed, $time);
        $finish;
    end
endmodule
