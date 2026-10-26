// File: tb_mem_perf_mon.sv
// Spec: mem-subsys-testplan PM-01 through PM-07.
// Description: APB-driven traffic and independent measurement scoreboard.
// Clock: clk (clk_mem).
module tb_mem_perf_mon;
    parameter FULL = 0;
    reg clk = 0;
    always #4 clk = !clk;
    reg rst_n = 0;
    reg [11:0] paddr = 0;
    reg psel = 0;
    reg penable = 0;
    reg pwrite = 0;
    reg [31:0] pwdata = 0;
    reg [3:0] pstrb = 15;
    wire [31:0] prdata;
    wire pready;
    wire pslverr;
    wire axi_awid;
    wire [31:0] axi_awaddr;
    wire [3:0] axi_awlen;
    wire axi_awvalid;
    wire axi_awready;
    wire [255:0] axi_wdata;
    wire [31:0] axi_wstrb;
    wire axi_wlast;
    wire axi_wvalid;
    wire axi_wready;
    wire axi_bid;
    wire [1:0] axi_bresp;
    wire axi_bvalid;
    wire axi_bready;
    wire axi_arid;
    wire [31:0] axi_araddr;
    wire [3:0] axi_arlen;
    wire axi_arvalid;
    wire axi_arready;
    wire axi_rid;
    wire [255:0] axi_rdata;
    wire [1:0] axi_rresp;
    wire axi_rlast;
    wire axi_rvalid;
    wire axi_rready;
    reg [31:0] read_delay = 8;
    reg [31:0] b_delay = 3;
    reg allow_ar = 1;
    reg allow_aw = 1;
    reg allow_w = 1;
    reg [31:0] mem_seed = 32'h1357_2468;
    reg observe = 0;
    reg [31:0] expected_base = 0;
    reg [31:0] expected_size = 4096;
    reg [31:0] expected_burst = 16;
    reg [31:0] expected_seed = 0;
    reg [31:0] expected_mode = 0;
    reg [31:0] expected_ratio = 8;
    reg [31:0] expected_addr_mode = 0;
    reg [31:0] expected_outstanding = 4;
    integer tick = 0;
    integer rd_pending = 0;
    integer wr_pending = 0;
    integer max_rd = 0;
    integer max_wr = 0;
    integer seen_ar = 0;
    integer seen_aw = 0;
    integer seen_r = 0;
    integer seen_w = 0;
    integer seen_done = 0;
    integer seen_reads = 0;
    integer observed_min = 32'h7fff_ffff;
    integer observed_max = 0;
    integer observed_sum = 0;
    integer ar_time [0:1023];
    integer ar_beat [0:1023];
    integer ar_head = 0;
    integer ar_tail = 0;
    integer hist [0:15];
    integer hist_width = 16;
    integer ref_offset = 0;
    reg [31:0] ref_lfsr = 0;
    integer ref_ratio = 0;
    integer issued = 0;
    integer i;
    integer j;
    integer latency;
    integer bucket;
    integer accepted_addr;
    integer accepted_len;
    integer wanted_addr;
    reg [63:0] scaled_block;
    integer wanted_beats;
    reg want_read;
    integer result;
    integer before_abort;
    integer start_tick;
    integer elapsed_cycles;
    reg [31:0] got;

    edrv32_mem_perf_mon dut (
        .clk_i(clk),
        .rst_n_i(rst_n),
        .apb_paddr_i(paddr),
        .apb_psel_i(psel),
        .apb_penable_i(penable),
        .apb_pwrite_i(pwrite),
        .apb_pwdata_i(pwdata),
        .apb_pstrb_i(pstrb),
        .apb_prdata_o(prdata),
        .apb_pready_o(pready),
        .apb_pslverr_o(pslverr),
        .axi_awid_o(axi_awid),
        .axi_awaddr_o(axi_awaddr),
        .axi_awlen_o(axi_awlen),
        .axi_awvalid_o(axi_awvalid),
        .axi_awready_i(axi_awready),
        .axi_wdata_o(axi_wdata),
        .axi_wstrb_o(axi_wstrb),
        .axi_wlast_o(axi_wlast),
        .axi_wvalid_o(axi_wvalid),
        .axi_wready_i(axi_wready),
        .axi_bid_i(axi_bid),
        .axi_bresp_i(axi_bresp),
        .axi_bvalid_i(axi_bvalid),
        .axi_bready_o(axi_bready),
        .axi_arid_o(axi_arid),
        .axi_araddr_o(axi_araddr),
        .axi_arlen_o(axi_arlen),
        .axi_arvalid_o(axi_arvalid),
        .axi_arready_i(axi_arready),
        .axi_rid_i(axi_rid),
        .axi_rdata_i(axi_rdata),
        .axi_rresp_i(axi_rresp),
        .axi_rlast_i(axi_rlast),
        .axi_rvalid_i(axi_rvalid),
        .axi_rready_o(axi_rready)
    );
    axi256_storage storage (
        .clk_i(clk),
        .rst_n_i(rst_n),
        .read_delay_i(read_delay),
        .b_delay_i(b_delay),
        .allow_ar_i(allow_ar),
        .allow_aw_i(allow_aw),
        .allow_w_i(allow_w),
        .axi_awid_i(axi_awid),
        .axi_awaddr_i(axi_awaddr),
        .axi_awlen_i(axi_awlen),
        .axi_awvalid_i(axi_awvalid),
        .axi_awready_o(axi_awready),
        .axi_wdata_i(axi_wdata),
        .axi_wstrb_i(axi_wstrb),
        .axi_wlast_i(axi_wlast),
        .axi_wvalid_i(axi_wvalid),
        .axi_wready_o(axi_wready),
        .axi_bid_o(axi_bid),
        .axi_bresp_o(axi_bresp),
        .axi_bvalid_o(axi_bvalid),
        .axi_bready_i(axi_bready),
        .axi_arid_i(axi_arid),
        .axi_araddr_i(axi_araddr),
        .axi_arlen_i(axi_arlen),
        .axi_arvalid_i(axi_arvalid),
        .axi_arready_o(axi_arready),
        .axi_rid_o(axi_rid),
        .axi_rdata_o(axi_rdata),
        .axi_rresp_o(axi_rresp),
        .axi_rlast_o(axi_rlast),
        .axi_rvalid_o(axi_rvalid),
        .axi_rready_i(axi_rready)
    );

    task wr(input [11:0] addr, input [31:0] data);
        begin
            @(negedge clk);
            paddr = addr; pwdata = data; pwrite = 1; psel = 1; penable = 0;
            @(negedge clk); penable = 1;
            @(negedge clk); psel = 0; penable = 0; pwrite = 0;
        end
    endtask
    task eq_reg(input [11:0] addr, input [31:0] wanted);
        begin
            @(negedge clk); paddr = addr;
            #1;
            if (prdata !== wanted)
                $fatal(1, "FAIL reg %h expected=%h actual=%h time=%0t",
                    addr, wanted, prdata, $time);
        end
    endtask
    task configure(input integer mode, input integer address_mode,
        input integer ratio, input integer burst, input integer count,
        input integer size_bytes, input integer limit, input integer seed,
        input integer check_enable, input integer width_cycles, input integer base_addr = 0);
        begin
            observe = 0;
            wr('h010, 3);
            wr('h100, mode); wr('h104, base_addr); wr('h108, size_bytes);
            wr('h10c, burst); wr('h110, address_mode); wr('h114, ratio);
            wr('h118, count); wr('h11c, limit); wr('h120, seed);
            wr('h124, check_enable); wr('h128, width_cycles);
            expected_mode = mode; expected_addr_mode = address_mode;
            expected_base = base_addr;
            expected_ratio = ratio; expected_burst = burst; expected_size = size_bytes;
            expected_outstanding = limit; expected_seed = seed; hist_width = width_cycles;
            seen_ar = 0; seen_aw = 0; seen_r = 0; seen_w = 0;
            seen_done = 0; seen_reads = 0;
            rd_pending = 0; wr_pending = 0; max_rd = 0; max_wr = 0;
            ar_head = 0; ar_tail = 0; observed_min = 32'h7fff_ffff;
            observed_max = 0; observed_sum = 0;
            ref_offset = 0; ref_lfsr = seed; ref_ratio = 0; issued = 0;
            for (integer k = 0; k < 16; k = k + 1) hist[k] = 0;
            observe = 1;
        end
    endtask
    task wait_idle;
        begin
            @(negedge clk); paddr = 'h008;
            result = 0;
            while (!prdata[1] || result == 0) begin
                @(negedge clk);
                result = result + 1;
                if (result > 100000) $fatal(1, "FAIL timeout");
            end
        end
    endtask
    task finish_check(input integer count);
        begin
            wait_idle();
            elapsed_cycles = tick - start_tick;
            eq_reg('h010, 1);
            eq_reg('h208, elapsed_cycles);
            eq_reg('h200, count);
            eq_reg('h204, seen_w + seen_r);
            eq_reg('h218, seen_reads);
            if (seen_ar + seen_aw != count || seen_done != count)
                $fatal(1, "FAIL transaction accounting");
            if (seen_ar != 0) begin
                eq_reg('h20c, observed_min); eq_reg('h210, observed_max);
                eq_reg('h214, observed_sum);
                for (integer k = 0; k < 16; k = k + 1) eq_reg(12'h300 + 12'(k*4), hist[k]);
            end else eq_reg('h20c, 32'hffff_ffff);
        end
    endtask

    // Scoreboard derives addresses and mix independently from register configuration.
    always @(posedge clk) begin
        tick = tick + 1;
        if (!rst_n) begin
            if (axi_awvalid || axi_arvalid || axi_wvalid)
                $fatal(1, "FAIL transaction during reset");
        end else if (observe) begin
            if (psel && penable && pwrite && paddr == 'h004 && pwdata[1])
                start_tick = tick;
            if ((axi_arvalid && axi_arready) || (axi_awvalid && axi_awready)) begin
                accepted_addr = axi_arvalid ? axi_araddr : axi_awaddr;
                accepted_len = axi_arvalid ? int'(axi_arlen) : int'(axi_awlen);
                if (expected_addr_mode == 1) begin
                    scaled_block = {48'b0, ref_lfsr[31:16]} * ({32'b0, expected_size}/64'd512);
                    wanted_addr = int'(scaled_block >> 16)*512;
                end else wanted_addr = ref_offset;
                wanted_beats = expected_burst;
                if (wanted_beats > (4096 - wanted_addr%4096)/32)
                    wanted_beats = (4096 - wanted_addr%4096)/32;
                if (wanted_beats > (expected_size - wanted_addr)/32)
                    wanted_beats = (expected_size - wanted_addr)/32;
                ref_ratio = ref_ratio + expected_ratio;
                want_read = expected_mode == 0 || (expected_mode == 2 && ref_ratio >= 16);
                if (want_read) ref_ratio = ref_ratio - 16;
                if (accepted_addr != expected_base + wanted_addr ||
                    accepted_len + 1 != wanted_beats ||
                    (axi_arvalid != (want_read != 0)))
                    $fatal(1, "FAIL command %0d addr=%h/%h beats=%0d/%0d read=%b/%b",
                        issued, accepted_addr, expected_base + wanted_addr,
                        accepted_len+1, wanted_beats,
                        axi_arvalid, want_read != 0);
                if (accepted_addr < expected_base ||
                    accepted_addr + wanted_beats*32 > expected_base + expected_size ||
                    accepted_addr%32 != 0 || accepted_addr%4096 + wanted_beats*32 > 4096)
                    $fatal(1, "FAIL address region/4KiB contract");
                ref_offset = (wanted_addr + wanted_beats*32)%expected_size;
                ref_lfsr = {ref_lfsr[30:0],
                    ref_lfsr[31]^ref_lfsr[21]^ref_lfsr[1]^ref_lfsr[0]};
                issued = issued + 1;
            end
            if (axi_arvalid && axi_arready) begin
                ar_time[ar_tail] = tick; ar_beat[ar_tail] = 0; ar_tail = ar_tail + 1;
                seen_ar = seen_ar + 1; rd_pending = rd_pending + 1;
                if (axi_arid !== 0) $fatal(1, "FAIL read ID");
            end
            if (axi_awvalid && axi_awready) begin
                seen_aw = seen_aw + 1; wr_pending = wr_pending + 1;
                if (axi_awid !== 0) $fatal(1, "FAIL write ID");
            end
            if (rd_pending > expected_outstanding || wr_pending > expected_outstanding)
                $fatal(1, "FAIL outstanding limit");
            if (rd_pending > max_rd) max_rd = rd_pending;
            if (wr_pending > max_wr) max_wr = wr_pending;
            if (axi_rvalid && axi_rready) begin
                seen_r = seen_r + 1;
                if (ar_beat[ar_head] == 0) begin
                    latency = tick - ar_time[ar_head];
                    if (latency < observed_min) observed_min = latency;
                    if (latency > observed_max) observed_max = latency;
                    observed_sum = observed_sum + latency;
                    bucket = latency/hist_width;
                    if (bucket > 15) bucket = 15;
                    hist[bucket] = hist[bucket] + 1;
                end
                ar_beat[ar_head] = ar_beat[ar_head] + 1;
                if (axi_rlast) begin
                    ar_head = ar_head + 1; rd_pending = rd_pending - 1;
                    seen_done = seen_done + 1; seen_reads = seen_reads + 1;
                end
            end
            if (axi_wvalid && axi_wready) begin
                seen_w = seen_w + 1;
                if (axi_wstrb !== 32'hffff_ffff) $fatal(1, "FAIL WSTRB");
            end
            if (axi_bvalid && axi_bready) begin
                wr_pending = wr_pending - 1; seen_done = seen_done + 1;
            end
        end
    end

    initial begin
        repeat (4) @(negedge clk);
        rst_n = 1;
        eq_reg('h000, 'h0009_0001); eq_reg('h008, 2);
        eq_reg('h108, 4096); eq_reg('h10c, 16); eq_reg('h11c, 4);
        eq_reg('h114, 8); eq_reg('h128, 16); eq_reg('h20c, 32'hffff_ffff);
        wr('h104, 'hc000_0fff); eq_reg('h104, 0);
        wr('h108, 'hc000_11ff); eq_reg('h108, 'h1000);
        pstrb = 1; wr('h120, 'h1234_5678); pstrb = 15; eq_reg('h120, 'h78);
        wr('h020, 123); eq_reg('h020, 0);
        wr('h024, 123); eq_reg('h024, 0);
        wr('h028, 123); eq_reg('h028, 0); eq_reg('h040, 0);
        eq_reg('hffc, 0);
        // PM-01: fill a full region and check every lane, then read it back.
        configure(1, 0, 8, 16, 8, 4096, 4, mem_seed, 0, 16, 'h1000);
        wr('h004, 2); finish_check(8); eq_reg('h21c, 0);
        for (i = 0; i < 1024; i = i + 1)
            if (storage.memory[1024+i] !== (('h1000+i*4)^mem_seed))
                $fatal(1, "FAIL write pattern word=%0d actual=%h", i, storage.memory[1024+i]);
        configure(0, 0, 8, 16, 8, 4096, 4, mem_seed, 1, 16, 'h1000);
        wr('h004, 2); finish_check(8); eq_reg('h21c, 0);
        $display("PASS PM-01 sequential pattern and readback");
        // PM-02: a bad byte reports the containing beat, once.
        storage.memory[1024+27] = storage.memory[1024+27] ^ 32'h0000_0100;
        configure(0, 0, 8, 16, 8, 4096, 4, mem_seed, 1, 16, 'h1000);
        wr('h004, 2); finish_check(8); eq_reg('h21c, 1); eq_reg('h220, 'h1060);
        eq_reg('h010, 1);
        $display("PASS PM-02 corrupt byte");
        // PM-04: exact bin boundaries, all sixteen bins, overflow to last bin.
        for (i = 0; i < 18; i = i + 1) begin
            read_delay = i < 16 ? (i+1)*4 : 100;
            configure(0, 0, 8, 1, 1, 4096, 1, 0, 0, 4);
            wr('h004, 2); finish_check(1);
            eq_reg('h20c, read_delay); eq_reg('h210, read_delay);
            eq_reg('h214, read_delay);
        end
        read_delay = 1;
        configure(0, 0, 8, 1, 1, 4096, 1, 0, 0, 4);
        wr('h004, 2); finish_check(1); eq_reg('h300, 1);
        $display("PASS PM-04 fixed latency and histogram boundaries");
        // Idle soft reset resets common/private registers and all results.
        observe = 0; wr('h004, 8);
        eq_reg('h004, 0); eq_reg('h02c, 0); eq_reg('h200, 0);
        eq_reg('h108, 4096); eq_reg('h20c, 32'hffff_ffff);
        if (FULL != 0) begin
            // PM-03: all modes by both address modes, extremes and balanced ratio.
            read_delay = 24;
            for (i = 0; i < 2; i = i + 1) begin
                for (j = 0; j < 3; j = j + 1) begin
                    configure(j, i, 8, 7, 40, 4608, 4, 'h19ad_732b, 0, 8, 'h1000);
                    wr('h004, 2); finish_check(40);
                end
                configure(2, i, 0, 16, 32, 8192, 4, 0, 0, 16);
                wr('h004, 2); finish_check(32);
                if (seen_ar != 0) $fatal(1, "FAIL ratio zero");
                configure(2, i, 16, 16, 32, 8192, 4, 123, 0, 16);
                wr('h004, 2); finish_check(32);
                if (seen_aw != 0) $fatal(1, "FAIL ratio sixteen");
            end
            for (i = 1; i <= 4; i = i + 1) begin
                configure(0, 0, 8, 1, 32, 4096, i, 0, 0, 16);
                wr('h004, 2); finish_check(32);
                if (max_rd != i) $fatal(1, "FAIL did not reach read outstanding %0d", i);
                b_delay = 24;
                configure(1, 0, 8, 1, 32, 4096, i, 0, 0, 16);
                wr('h004, 2); finish_check(32);
                if (max_wr != i) $fatal(1, "FAIL did not reach write outstanding %0d", i);
            end
            $display("PASS PM-03 mixed/random/truncated bursts/outstanding");
            // PM-05: every enumerated invalid value leaves the master idle.
            for (i = 0; i < 8; i = i + 1) begin
                configure(0, 0, 8, 16, 1, 4096, 4, 0, 0, 16);
                case (i)
                    0: wr('h10c, 0);
                    1: wr('h10c, 17);
                    2: wr('h11c, 0);
                    3: wr('h11c, 5);
                    4: wr('h108, 0);
                    5: wr('h118, 0);
                    6: wr('h128, 0);
                    7: wr('h10c, 32'hffff_ffff);
                    default: $fatal(1, "FAIL test configuration");
                endcase
                wr('h004, 2); wait_idle(); eq_reg('h010, 2); eq_reg('h014, 1);
                eq_reg('h008, 6);
                if (seen_ar != 0 || seen_aw != 0) $fatal(1, "FAIL invalid issued traffic");
                wr('h010, 2); eq_reg('h014, 0); eq_reg('h008, 2);
            end
            $display("PASS PM-05 invalid configuration");
            // PM-06: stall an already asserted AR across ABORT, then drain.
            read_delay = 40; allow_ar = 0;
            configure(0, 0, 8, 16, 100, 4096, 4, 0, 0, 16);
            wr('h004, 2); repeat (4) @(negedge clk);
            if (!axi_arvalid) $fatal(1, "FAIL no pending AR");
            before_abort = axi_araddr;
            wr('h004, 4); repeat (5) @(negedge clk);
            if (!axi_arvalid || axi_araddr != before_abort)
                $fatal(1, "FAIL ABORT withdrew stalled address");
            allow_ar = 1; wait_idle(); eq_reg('h010, 0);
            if (seen_done != seen_ar || rd_pending != 0 || seen_ar != 1)
                $fatal(1, "FAIL read abort drain");
            allow_w = 0;
            configure(1, 0, 8, 16, 100, 4096, 4, 0, 0, 16);
            wr('h004, 2); repeat (15) @(negedge clk);
            if (seen_aw != 4) $fatal(1, "FAIL expected four pending writes");
            wr('h004, 4); allow_w = 1; wait_idle(); eq_reg('h010, 0);
            if (wr_pending != 0 || seen_aw != seen_done)
                $fatal(1, "FAIL write abort drain");
            $display("PASS PM-06 abort stalled AR and outstanding writes");
            // Saturating public counters must not corrupt subsequent read latency.
            read_delay = 8;
            configure(0, 0, 8, 1, 4, 4096, 1, 0, 0, 32'hffff_ffff);
            wr('h004, 2);
            wait (axi_arvalid && axi_arready);
            @(negedge clk);
            dut.txn_done_r = 32'hffff_fffe;
            dut.beats_r = 32'hffff_fffe;
            dut.cycles_r = 32'hffff_fffe;
            dut.lat_sum_r = 32'hffff_fffe;
            dut.read_cnt_r = 32'hffff_fffe;
            dut.hist_r[0] = 32'hffff_fffe;
            wait_idle();
            eq_reg('h200, 32'hffff_ffff); eq_reg('h204, 32'hffff_ffff);
            eq_reg('h208, 32'hffff_ffff); eq_reg('h214, 32'hffff_ffff);
            eq_reg('h218, 32'hffff_ffff); eq_reg('h300, 32'hffff_ffff);
            eq_reg('h20c, 8); eq_reg('h210, 8);
            read_delay = 1;
            configure(0, 0, 8, 1, 4, 4096, 1, 32'hdead_beef, 1, 16);
            wr('h004, 2);
            wait (axi_arvalid && axi_arready);
            @(negedge clk); dut.err_beats_r = 32'hffff_fffe;
            wait_idle(); eq_reg('h21c, 32'hffff_ffff);
            $display("PASS PM saturation and latency after CYCLES saturation");
            // PM-07: continuous same-row read data with small fixed first latency.
            read_delay = 8;
            configure(0, 0, 8, 16, 256, 4096, 4, 0, 0, 16);
            wr('h004, 2); finish_check(256);
            @(negedge clk); paddr = 'h208; #1; got = prdata;
            if (seen_r*100 < got*90) $fatal(1, "FAIL throughput %0d/%0d", seen_r, got);
            $display("PASS PM-07 bandwidth %0d/%0d beats/cycles", seen_r, got);
        end
        observe = 0;
        rst_n = 0;
        repeat (3) @(negedge clk);
        rst_n = 1;
        eq_reg('h008, 2); eq_reg('h010, 0); eq_reg('h200, 0);
        eq_reg('h20c, 32'hffff_ffff);
        if ((^{axi_awvalid, axi_arvalid, axi_wvalid, axi_bready, axi_rready}) === 1'bx)
            $fatal(1, "FAIL unknown control after reset");
        $display("PASS mem_perf_mon FULL=%0d", FULL);
        $finish;
    end
    initial begin #5000000; $fatal(1, "FAIL testbench timeout"); end
endmodule
