// File: edrv32_sys_cases.svh
// Spec: sys-subsys-testplan 3.1-3.5, 5, 6.
// Description: Shared self-checking scenarios, included in the SB environment.
// Clock domains: sys/mem plus asynchronous UART/SCCB.
    int coverage_count[string];
    bit [63:0] read_words[256];
    bit [31:0] value;

    // Coverage bins are a simulation scoreboard updated atomically by monitors.
    /* verilator lint_off BLKSEQ */
    task automatic hit_coverage(
        input string name
    );
        coverage_count[name]++;
    endtask
    /* verilator lint_on BLKSEQ */
    task automatic report_coverage();
        foreach (coverage_count[name])
            $display("COVER %s=%0d", name, coverage_count[name]);
    endtask

    task automatic rd(
        input int master,
        input bit [31:0] addr,
        input int size = 2,
        input int len = 0,
        input int expected = -1,
        input bit compare = 0
    );
        bit [63:0] data[256];
        bit [1:0] resp[256];
        bit [1:0] want;
        bit [31:0] beat_addr;
        bit [63:0] mask;
        want = expected < 0 ? edrv32_sys_reference::response(master, 0, addr, size, len)
                            : 2'(expected);
        if (master == 0) u_m0.read(addr, 3'(size), len, data, resp);
        else u_m1.read(addr, 3'(size), len, data, resp);
        if ((master == 0 && u_m0.last_read_cancelled) ||
            (master == 1 && u_m1.last_read_cancelled)) return;
        for (int n = 0; n <= len; n++) begin
            check(resp[n] == want, "RRESP", 64'(want), 64'(resp[n]));
            beat_addr = addr + (32'(n) << size);
            mask = size == 3 ? '1 : ((64'b1 << (8 * (1 << size))) - 1)
                                    << (8 * int'(beat_addr[2:0]));
            if (want == 3) check(data[n] == 0, "DECERR data", 0, data[n]);
            if (compare && want == 0)
                check((data[n] & mask) ==
                        (edrv32_axi64_memory_pkg::read_data({beat_addr[31:3], 3'b0}, 8, 1) &
                        mask), "reference read",
                        edrv32_axi64_memory_pkg::read_data({beat_addr[31:3], 3'b0}, 8, 1) &
                        mask, data[n] & mask);
        end
        read_words = data;
    endtask

    task automatic wr(
        input bit [31:0] addr,
        input bit [63:0] data,
        input bit [7:0] strb = 8'hff,
        input int size = 2,
        input int len = 0,
        input int expected = -1
    );
        bit [63:0] words[256];
        bit [7:0] strobes[256];
        bit [1:0] resp;
        bit [1:0] want;
        want = expected < 0 ? edrv32_sys_reference::response(1, 1, addr, size, len)
                            : 2'(expected);
        for (int n = 0; n <= len; n++) begin
            words[n] = data + 64'(n);
            strobes[n] = strb;
        end
        u_m1.write(addr, 3'(size), len, words, strobes, resp);
        if (u_m1.last_write_cancelled) return;
        check(resp == want, "BRESP", 64'(want), 64'(resp));
        if (want == 0 && (edrv32_sys_reference::region(addr) == 1 || addr[31]))
            for (int n = 0; n <= len; n++)
                edrv32_sys_reference::store(addr + (32'(n) << size), words[n], strb);
    endtask

    task automatic w32(
        input bit [31:0] addr,
        input bit [31:0] data,
        input bit [3:0] strb = 4'hf
    );
        wr(addr, 64'(data) << (addr[2] ? 32 : 0),
            8'(strb) << (addr[2] ? 4 : 0));
    endtask
    task automatic r32(
        input bit [31:0] addr,
        output bit [31:0] data
    );
        rd(1, addr);
        data = 32'(read_words[0] >> (addr[2] ? 32 : 0));
        if (addr == EDRV32_PLIC_BASE + 'h200004 && data != 0)
            hit_coverage($sformatf("plic.claim.%0d", data));
    endtask
    task automatic eq32(
        input bit [31:0] addr,
        input bit [31:0] expected,
        input bit [31:0] mask = '1
    );
        bit [31:0] actual;
        r32(addr, actual);
        check((actual & mask) == (expected & mask), $sformatf("reg %h", addr),
                64'(int'(expected & mask)), 64'(int'(actual & mask)));
    endtask
    task automatic wait_sys(
        input int cycles
    );
        repeat (cycles) @(negedge clk_sys);
    endtask

    task automatic memory_case(
        input int id
    );
        bit [63:0] before_data;
        bit [31:0] addr;
        case (id)
            201: begin
                check(rom_image_loaded, "MEM-01 requires +ROM_HEX", 1, 64'(rom_image_loaded));
                for (int size = 0; size <= 3; size++) begin
                    rd(0, EDRV32_ROM_BASE, size, 0, -1, 1);
                    rd(0, EDRV32_ROM_BASE + EDRV32_ROM_SIZE - (32'b1 << size),
                        size, 0, -1, 1);
                end
            end
            202: begin
                rd(0, EDRV32_ROM_BASE, 3);
                before_data = read_words[0];
                wr(EDRV32_ROM_BASE, '1, 8'hff, 3, 3);
                rd(0, EDRV32_ROM_BASE, 3);
                check(read_words[0] == before_data, "ROM immutable", before_data,
                        read_words[0]);
            end
            203: begin
                for (int size = 0; size <= 2; size++) begin
                    for (int strb = 0; strb < 256; strb++) begin
                        addr = EDRV32_SRAM_BASE + 32'(8 * size);
                        wr(addr, 64'h123456789abcdef0 ^ 64'(strb), 8'(strb), size);
                        rd(1, addr, 2, 0, -1, 1);
                        rd(1, addr + 4, 2, 0, -1, 1);
                    end
                end
            end
            204: begin
                wr(EDRV32_SRAM_BASE + 'h100, 64'h8877665544332211, 8'hff, 3, 3);
                rd(1, EDRV32_SRAM_BASE + 'h100, 3, 3, -1, 1);
                for (int n = 1; n < 4; n++)
                    check(u_m1.beat_cycle[n] - u_m1.beat_cycle[n-1] == 1,
                            "SRAM burst period", 1,
                            64'(int'(u_m1.beat_cycle[n] - u_m1.beat_cycle[n-1])));
            end
            205: begin
                check(sram_image_loaded, "MEM-05 requires +SRAM_HEX", 1,
                        64'(sram_image_loaded));
                rd(0, EDRV32_SRAM_BASE, 2, 0, -1, 1);
                rd(1, EDRV32_SRAM_BASE + 4, 2, 0, -1, 1);
                rd(1, EDRV32_SRAM_BASE + EDRV32_SRAM_SIZE - 4, 2, 0, -1, 1);
            end
            default: $fatal(1, "FAIL memory case %0d", id);
        endcase
    endtask

    task automatic xbar_case(
        input int id
    );
        bit [31:0] bases[8];
        bit [31:0] sizes[8];
        int done0;
        int done1;
        int first0;
        int first1;
        int latency0;
        int latency1;
        int random_start;
        bases = '{EDRV32_ROM_BASE, EDRV32_SRAM_BASE, EDRV32_CLINT_BASE, EDRV32_PLIC_BASE,
                    EDRV32_SYS_APB_BASE, EDRV32_MEDIA_APB_BASE, EDRV32_DDR_BASE,
                    EDRV32_DDR_UNCACHED_BASE};
        sizes = '{EDRV32_ROM_SIZE, EDRV32_SRAM_SIZE, EDRV32_CLINT_SIZE, EDRV32_PLIC_SIZE,
                    EDRV32_SYS_APB_SIZE, EDRV32_MEDIA_APB_SIZE, EDRV32_DDR_SIZE,
                    EDRV32_DDR_UNCACHED_SIZE};
        case (id)
            101: begin
                for (int s = 0; s < 8; s++) begin
                    rd(1, bases[s], 2, 0, -1, s < 2 || s >= 6);
                    rd(1, bases[s] + sizes[s] - 4, 2, 0, -1, s < 2 || s >= 6);
                end
                wr(EDRV32_DDR_BASE, 64'h0123456789abcdef, 8'hff, 3, 3);
                rd(0, EDRV32_DDR_UNCACHED_BASE, 3, 3, -1, 1);
            end
            102: begin
                for (int slave = 2; slave <= 5; slave++) begin
                    fork
                        begin
                            bit [63:0] data[256];
                            bit [1:0] resp[256];
                            u_m0.read(bases[slave], 3, 3, data, resp);
                            for (int n = 0; n < 4; n++) begin
                                check(resp[n] == 3, "M0 forbidden response", 3, 64'(resp[n]));
                                check(data[n] == 0, "M0 DECERR data", 0, data[n]);
                            end
                        end
                        begin
                            bit [63:0] unused_data[256];
                            bit [1:0] resp[256];
                            u_m1.read(bases[slave], 2, 0, unused_data, resp);
                            check(resp[0] == 0, "M1 legal isolated response", 0, 64'(resp[0]));
                        end
                    join
                    hit_coverage($sformatf("isolation.s%0d", slave));
                end
            end
            103: begin
                rd(0, 32'h50000000, 3, 3, 3);
                rd(1, 32'h50000000, 2, 0, 3);
                wr(32'h50000000, '1, 8'hff, 3, 3, 3);
            end
            104: begin
                for (int slave = 0; slave < 7; slave++) begin
                    if (slave == 0 || slave == 1 || slave == 6) begin
                        for (int round = 0; round < 8; round++) begin
                            // Prime the last owner; the next tie must favor the other master.
                            rd(round % 2, bases[slave], 3, 3);
                            fork
                                begin
                                    bit [63:0] unused_data[256];
                                    bit [1:0] resp[256];
                                    u_m0.read(bases[slave], 3, 3, unused_data, resp);
                                    check(resp[0] == 0, "M0 contended response", 0, 64'(resp[0]));
                                    done0 = u_m0.cycle;
                                end
                                begin
                                    bit [63:0] unused_data[256];
                                    bit [1:0] resp[256];
                                    u_m1.read(bases[slave], 3, 3, unused_data, resp);
                                    check(resp[0] == 0, "M1 contended response", 0, 64'(resp[0]));
                                    done1 = u_m1.cycle;
                                end
                            join
                            check((done0 < done1) == (round % 2 != 0),
                                    "round-robin follows the last completed owner",
                                    64'(round % 2 != 0), 64'(done0 < done1));
                            hit_coverage($sformatf("contention.s%0d", slave));
                        end
                    end
                end
            end
            105: begin
                edrv32_axi64_memory_pkg::random_stalls = 0;
                edrv32_axi64_memory_pkg::delay_max = 0;
                wait_sys(3);
                for (int slave = 0; slave < 7; slave++) begin
                    if (slave == 0 || slave == 1 || slave == 6) begin
                        // Different intrinsic slave latencies need not overlap R windows.
                        rd(0, bases[slave], 3, 3);
                        latency0 = u_m0.first_latency;
                        rd(1, bases[slave == 0 ? 1 : 0], 3, 3);
                        latency1 = u_m1.first_latency;
                        for (int round = 0; round < 8; round++) begin
                            fork
                                begin
                                    bit [63:0] unused_data[256];
                                    bit [1:0] resp[256];
                                    u_m0.read(bases[slave], 3, 3, unused_data, resp);
                                    check(resp[0] == 0, "M0 concurrent response", 0, 64'(resp[0]));
                                    first0 = u_m0.first_latency;
                                end
                                begin
                                    bit [63:0] unused_data[256];
                                    bit [1:0] resp[256];
                                    u_m1.read(bases[slave == 0 ? 1 : 0], 3, 3, unused_data, resp);
                                    check(resp[0] == 0, "M1 concurrent response", 0, 64'(resp[0]));
                                    first1 = u_m1.first_latency;
                                end
                            join
                            check(first0 <= latency0, "M0 independent slave latency",
                                    64'(latency0), 64'(first0));
                            check(first1 <= latency1, "M1 independent slave latency",
                                    64'(latency1), 64'(first1));
                        end
                    end
                end
            end
            106: begin
                for (int s = 0; s < 2; s++) begin
                    rd(0, bases[s], 3, s == 0 ? 0 : 3, -1, 1);
                    check(u_m0.first_latency <= 3, "M0 first latency", 3,
                            64'(u_m0.first_latency));
                    rd(1, bases[s], 2, 0, -1, 1);
                    check(u_m1.first_latency <= 3, "M1 first latency", 3,
                            64'(u_m1.first_latency));
                end
            end
            107: begin
                wr(EDRV32_SRAM_BASE + 'h1000, 0, 8'hff, 3, 3);
                wr(EDRV32_DDR_BASE + 'h1000, 0, 8'hff, 3, 3);
                wr(EDRV32_SRAM_BASE + 'h2000, 0, 8'hff, 3, 3);
                wr(EDRV32_DDR_BASE + 'h2000, 0, 8'hff, 3, 3);
                done0 = 0;
                done1 = 0;
                random_start = 0;
                // Reuse two long-lived streams; avoid recreating timed fork children per seed.
                fork
                    begin
                        for (int seed = 1; seed <= 50; seed++) begin
                            while (random_start != seed) @(negedge clk_sys);
                            random_master0();
                            done0 = seed;
                        end
                    end
                    begin
                        for (int seed = 1; seed <= 50; seed++) begin
                            while (random_start != seed) @(negedge clk_sys);
                            random_master1();
                            done1 = seed;
                        end
                    end
                    begin
                        int rng;
                        for (int seed = 1; seed <= 50; seed++) begin
                            rng = seed;
                            rng = $urandom(rng);
                            $display("SEED %0d first=%0d", seed, rng);
                            $fflush();
                            random_start = seed;
                            while (done0 != seed || done1 != seed) @(negedge clk_sys);
                        end
                    end
                join
            end
            default: $fatal(1, "FAIL xbar case %0d", id);
        endcase
    endtask
    task automatic random_master0();
        bit [31:0] addr;
        bit [63:0] data[256];
        bit [1:0] resp[256];
        bit [63:0] mask;
        bit [63:0] expected;
        int target;
        int size;
        int len;
        for (int n = 0; n < 100; n++) begin
            target = int'($urandom_range(0, 7));
            case (target)
                0: addr = EDRV32_ROM_BASE;
                1: addr = EDRV32_SRAM_BASE + 'h1000;
                2: addr = EDRV32_DDR_BASE + 'h1000;
                3: addr = 32'h50000000;
                4: addr = EDRV32_CLINT_BASE;
                5: addr = EDRV32_PLIC_BASE;
                6: addr = EDRV32_SYS_APB_BASE;
                default: addr = EDRV32_MEDIA_APB_BASE;
            endcase
            size = int'($urandom_range(0, target < 3 ? 3 : 7));
            len = size >= 3 && target != 0 ? 3 : 0;
            u_m0.gap = int'($urandom_range(0, 4));
            u_m0.response_stall = int'($urandom_range(0, 3));
            u_m0.read(addr, 3'(size), len, data, resp);
            mask = size == 3 ? '1 : (64'b1 << (8 * (1 << size))) - 1;
            for (int b = 0; b <= len; b++) begin
                check(resp[b] == (target >= 3 ? 3 : 0), "random M0 response",
                        64'(target >= 3 ? 3 : 0), 64'(resp[b]));
                if (target < 3) begin
                    expected = edrv32_axi64_memory_pkg::read_data(
                        addr + (32'(b) << size), 8, 1);
                    check((data[b] & mask) == (expected & mask), "random M0 data",
                            expected & mask, data[b] & mask);
                end else check(data[b] == 0, "random DECERR data", 0, data[b]);
            end
        end
    endtask
    task automatic random_master1();
        bit [31:0] addr;
        int target;
        int size;
        int len;
        for (int n = 0; n < 100; n++) begin
            target = int'($urandom_range(0, 7));
            case (target)
                0: addr = EDRV32_ROM_BASE + 'h200;
                1: addr = EDRV32_SRAM_BASE + 'h2000;
                2: addr = EDRV32_DDR_UNCACHED_BASE + 'h2000;
                3: addr = 32'h50000000;
                4: addr = EDRV32_CLINT_BASE;
                5: addr = EDRV32_PLIC_BASE;
                6: addr = EDRV32_CACHE_CTRL_BASE + 'h100;
                default: addr = EDRV32_MEDIA_APB_BASE + 'h100;
            endcase
            size = int'($urandom_range(0, target < 4 ? 3 : 7));
            len = size >= 3 ? 3 : 0;
            // Interrupt-register traffic here deliberately exercises the defined error path.
            if ((target == 4 || target == 5) && size == 2) len = 3;
            u_m1.gap = int'($urandom_range(0, 4));
            u_m1.response_stall = int'($urandom_range(0, 3));
            if ($urandom_range(0, 1) != 0)
                wr(addr, {$urandom, $urandom}, 8'($urandom), size, len);
            else begin
                rd(1, addr, size, len, -1, target < 3);
                if (size == 2 && len == 0 && target >= 6) begin
                    value = target == 6 ? u_cache.memory[5]['h100/4] :
                                            u_media.memory[0]['h100/4];
                    check(read_words[0][31:0] == value, "random APB read", 64'(value),
                            64'(read_words[0][31:0]));
                end
            end
        end
    endtask
    task automatic apb_case(
        input int id
    );
        int before_count;
        int start_cycle;
        bit [31:0] addr;
        realtime ratios[4];
        case (id)
            301: begin
                for (int slot = 0; slot < 16; slot++) begin
                    if (edrv32_sys_reference::used_slot(4, slot)) begin
                        addr = EDRV32_SYS_APB_BASE + (32'(slot) << 12);
                        w32(addr + 'h100, 32'h12345678);
                        r32(addr, value);
                        if (slot != 5)
                            check(value == (32'(slot) << 16 | 1), "APB slot ID",
                                    64'(int'(32'(slot) << 16 | 1)), 64'(value));
                        hit_coverage($sformatf("apb.sys.slot%0d.read", slot));
                        hit_coverage($sformatf("apb.sys.slot%0d.write", slot));
                    end
                    if (slot < 10) begin
                        addr = EDRV32_MEDIA_APB_BASE + (32'(slot) << 12) + 'h100;
                        w32(addr, 32'hfeed0000 | 32'(slot));
                        eq32(addr, 32'hfeed0000 | 32'(slot));
                        hit_coverage($sformatf("apb.media.slot%0d.read", slot));
                        hit_coverage($sformatf("apb.media.slot%0d.write", slot));
                    end
                end
            end
            302: begin
                before_count = u_media.transfers + u_cache.transfers +
                                edrv32_apb_observation_pkg::used_setups;
                for (int slot = 0; slot < 16; slot++) begin
                    if (!edrv32_sys_reference::used_slot(4, slot)) begin
                        rd(1, EDRV32_SYS_APB_BASE + (32'(slot) << 12), 2, 0, 2);
                        wr(EDRV32_SYS_APB_BASE + (32'(slot) << 12), 0, 8'h0f, 2, 0, 2);
                    end
                    if (slot >= 10) begin
                        rd(1, EDRV32_MEDIA_APB_BASE + (32'(slot) << 12), 2, 0, 2);
                        wr(EDRV32_MEDIA_APB_BASE + (32'(slot) << 12), 0, 8'h0f, 2, 0, 2);
                    end
                end
                check(u_media.transfers + u_cache.transfers +
                        edrv32_apb_observation_pkg::used_setups == before_count,
                        "reserved APB no used slot selected", 64'(before_count),
                        64'(int'(u_media.transfers + u_cache.transfers +
                                edrv32_apb_observation_pkg::used_setups)));
                hit_coverage("apb.reserved");
            end
            303: begin
                before_count = u_media.transfers + u_cache.transfers +
                                edrv32_apb_observation_pkg::setups;
                for (int target = 0; target < 2; target++) begin
                    addr = target == 0 ? EDRV32_CACHE_CTRL_BASE : EDRV32_MEDIA_APB_BASE;
                    for (int size = 0; size < 8; size++) begin
                        if (size != 2) begin
                            rd(1, addr, size, 0, 2);
                            wr(addr, 0, 8'hff, size, 0, 2);
                        end
                    end
                    for (int offset = 1; offset <= 3; offset++) begin
                        rd(1, addr + 32'(offset), 2, 0, 2);
                        wr(addr + 32'(offset), 0, 8'hff, 2, 0, 2);
                    end
                    rd(1, addr, 3, 3, 2);
                    wr(addr, 0, 8'hff, 3, 3, 2);
                end
                check(u_media.transfers + u_cache.transfers +
                        edrv32_apb_observation_pkg::setups == before_count,
                        "invalid APB not forwarded", 64'(before_count),
                        64'(int'(u_media.transfers + u_cache.transfers +
                                edrv32_apb_observation_pkg::setups)));
            end
            304: begin
                u_media.never_ready = 1;
                start_cycle = mem_access_cycles;
                rd(1, EDRV32_MEDIA_APB_BASE, 2, 0, 2);
                check(mem_access_cycles - start_cycle == 256, "APB timeout PCLK count", 256,
                        64'(int'(mem_access_cycles - start_cycle)));
                u_media.never_ready = 0;
                w32(EDRV32_MEDIA_APB_BASE, 32'hfedcba98);
                eq32(EDRV32_MEDIA_APB_BASE, 32'hfedcba98);
                u_cache.never_ready = 1;
                start_cycle = cache_access_cycles;
                wr(EDRV32_CACHE_CTRL_BASE, 0, 8'h0f, 2, 0, 2);
                check(cache_access_cycles - start_cycle == 256, "system APB timeout", 256,
                        64'(int'(cache_access_cycles - start_cycle)));
                u_cache.never_ready = 0;
                w32(EDRV32_CACHE_CTRL_BASE + 'h100, 32'h11223344);
                hit_coverage("apb.timeout");
            end
            305: begin
                u_media.inject_error = 1;
                rd(1, EDRV32_MEDIA_APB_BASE, 2, 0, 2);
                wr(EDRV32_MEDIA_APB_BASE, 0, 8'h0f, 2, 0, 2);
                u_media.inject_error = 0;
                u_cache.inject_error = 1;
                rd(1, EDRV32_CACHE_CTRL_BASE, 2, 0, 2);
                wr(EDRV32_CACHE_CTRL_BASE, 0, 8'h0f, 2, 0, 2);
                u_cache.inject_error = 0;
                hit_coverage("apb.pslverr");
            end
            306: begin
                for (int half = 0; half < 2; half++) begin
                    addr = EDRV32_MEDIA_APB_BASE + 32'(half * 4);
                    for (int strb = 0; strb < 256; strb++) begin
                        wr(addr, 64'h123456789abcdef0, 8'(strb));
                        check(u_media.last_strb == (half == 0 ? 4'(strb) : 4'(strb >> 4)),
                                "APB pstrb half", 64'(int'(half == 0 ? strb & 15 : strb >> 4)),
                                64'(u_media.last_strb));
                        check(u_media.last_data == (half == 0 ? 32'h9abcdef0 : 32'h12345678),
                                "APB pwdata half", half == 0 ? 64'h9abcdef0 : 64'h12345678,
                                64'(u_media.last_data));
                    end
                end
            end
            307: begin
                ratios = '{0.5, 0.83, 1.0, 2.0};
                for (int ratio = 0; ratio < 4; ratio++) begin
                    mem_half = sys_half / ratios[ratio];
                    #(real'($urandom_range(1, 1000)) / 100.0);
                    u_media.delay_cycles = int'($urandom_range(0, 7));
                    for (int n = 0; n < 32; n++) begin
                        addr = EDRV32_MEDIA_APB_BASE + 32'((n % 10) * 'h1000 + 'h100);
                        w32(addr, 32'(n));
                        eq32(addr, 32'(n));
                    end
                    hit_coverage($sformatf("apb.ratio.%0d", ratio));
                end
            end
            default: $fatal(1, "FAIL APB case %0d", id);
        endcase
    endtask
    int mem_access_cycles = 0;
    int cache_access_cycles = 0;
    always @(posedge clk_mem)
        if (rst_mem_n && media.psel != 0 && media.penable)
            mem_access_cycles <= mem_access_cycles + 1;
    always @(posedge clk_sys)
        if (rst_sys_n && cache.psel != 0 && cache.penable)
            cache_access_cycles <= cache_access_cycles + 1;

    task automatic clint_case(
        input int id
    );
        bit [63:0] start_time;
        bit [31:0] lo;
        bit [31:0] hi;
        case (id)
            401: begin
                @(negedge clk_sys);
                start_time = mtime;
                wait_sys(17);
                check(mtime == start_time + 17, "mtime cycle increment", start_time + 17,
                        mtime);
                // Read value is sampled at the AXI request acceptance boundary.
                fork
                    r32(EDRV32_CLINT_BASE + 'hbff8, lo);
                    begin
                        wait (m1.arvalid && m1.arready);
                        start_time = mtime;
                    end
                join
                check(lo >= start_time[31:0] && lo <= mtime[31:0], "mtime register/output range",
                        64'(start_time[31:0]), 64'(lo));
            end
            402: begin
                w32(EDRV32_CLINT_BASE + 'hbffc, 32'h12345678);
                w32(EDRV32_CLINT_BASE + 'hbff8, 32'hfffffffc);
                wait_sys(8);
                r32(EDRV32_CLINT_BASE + 'hbffc, hi);
                check(hi == 32'h12345679, "MTIME_LO other half counts carry",
                        'h12345679, 64'(hi));
                start_time = mtime;
                w32(EDRV32_CLINT_BASE + 'hbffc, 32'h12345678);
                check(mtime[31:0] > start_time[31:0], "MTIME_HI low half counts", 1,
                        64'(mtime[31:0] > start_time[31:0]));
            end
            403: begin
                check(!irq_mtip, "reset MTIP", 0, 64'(irq_mtip));
                w32(EDRV32_CLINT_BASE + 'h4000, 32'hffffffff);
                w32(EDRV32_CLINT_BASE + 'h4004, 0);
                w32(EDRV32_CLINT_BASE + 'hbffc, 0);
                w32(EDRV32_CLINT_BASE + 'hbff8, 0);
                w32(EDRV32_CLINT_BASE + 'h4000, mtime[31:0] + 40);
                r32(EDRV32_CLINT_BASE + 'h4000, lo);
                wait (mtime == 64'(lo) - 1);
                @(negedge clk_sys);
                check(!irq_mtip, "MTIP below comparator", 0, 64'(irq_mtip));
                wait (mtime == 64'(lo) + 1);
                @(negedge clk_sys);
                check(irq_mtip, "MTIP registered compare", 1, 64'(irq_mtip));
            end
            404: begin
                w32(EDRV32_CLINT_BASE, 1);
                check(irq_msip, "MSIP set", 1, 64'(irq_msip));
                w32(EDRV32_CLINT_BASE, 0);
                check(!irq_msip, "MSIP clear", 0, 64'(irq_msip));
            end
            405: begin
                for (int target = 0; target < 2; target++) begin
                    rd(1, target == 0 ? EDRV32_CLINT_BASE : EDRV32_PLIC_BASE, 3, 3, 2);
                    wr(target == 0 ? EDRV32_CLINT_BASE : EDRV32_PLIC_BASE,
                        0, 8'hff, 3, 3, 2);
                    for (int size = 0; size < 8; size++)
                        if (size != 2) begin
                            rd(1, target == 0 ? EDRV32_CLINT_BASE : EDRV32_PLIC_BASE,
                                size, 0, 2);
                            wr(target == 0 ? EDRV32_CLINT_BASE : EDRV32_PLIC_BASE,
                                0, 8'h0f, size, 0, 2);
                        end
                end
            end
            default: $fatal(1, "FAIL CLINT case %0d", id);
        endcase
    endtask

    task automatic plic_config();
        for (int n = 1; n <= 15; n++) w32(EDRV32_PLIC_BASE + 32'(4*n), 1);
        w32(EDRV32_PLIC_BASE + 'h2000, 'hfffe);
        w32(EDRV32_PLIC_BASE + 'h200000, 0);
    endtask
    task automatic plic_case(
        input int id
    );
        bit [31:0] claim;
        case (id)
            501: begin
                plic_config();
                w32(EDRV32_PLIC_BASE + 4*8, 4);
                w32(EDRV32_PLIC_BASE + 4*9, 4);
                w32(EDRV32_PLIC_BASE + 4*10, 0);
                w32(EDRV32_PLIC_BASE + 4*11, 2);
                w32(EDRV32_PLIC_BASE + 'h200000, 2);
                irq_src = 8'h0f;
                wait_sys(12);
                r32(EDRV32_PLIC_BASE + 'h200004, claim);
                check(claim == 8, "PLIC equal priority lower source", 8, 64'(claim));
                r32(EDRV32_PLIC_BASE + 'h200004, claim);
                check(claim == 9, "PLIC second source", 9, 64'(claim));
                r32(EDRV32_PLIC_BASE + 'h200004, claim);
                check(claim == 0, "PLIC priority zero and threshold", 0, 64'(claim));
                hit_coverage("plic.tie");
            end
            502, 503: begin
                plic_config();
                irq_src[8] = 1;
                wait_sys(12);
                r32(EDRV32_PLIC_BASE + 'h200004, claim);
                check(claim == 8, "PLIC claim", 8, 64'(claim));
                eq32(EDRV32_PLIC_BASE + 'h1000, 0, 'h100);
                w32(EDRV32_PLIC_BASE + 'h200004, 9);
                wait_sys(12);
                eq32(EDRV32_PLIC_BASE + 'h1000, 0, 'h100);
                check(!irq_meip, "claimed level suppressed", 0, 64'(irq_meip));
                if (id == 503) begin
                    w32(EDRV32_PLIC_BASE + 'h200004, 8);
                    wait_sys(12);
                    eq32(EDRV32_PLIC_BASE + 'h1000, 'h100, 'h100);
                    check(irq_meip, "completed high source repends", 1, 64'(irq_meip));
                end
            end
            504: begin
                plic_config();
                irq_cache = 1;
                wait_sys(12);
                r32(EDRV32_PLIC_BASE + 'h200004, claim);
                check(claim == 6, "cache IRQ source", 6, 64'(claim));
                irq_cache = 0;
                wait_sys(12);
                w32(EDRV32_PLIC_BASE + 'h200004, 6);
                for (int ratio = 0; ratio < 2; ratio++) begin
                    mem_half = ratio == 0 ? 2 * sys_half : sys_half / 2;
                    for (int src = 8; src <= 15; src++) begin
                        @(negedge clk_mem);
                        irq_src = 8'(1 << (src-8));
                        wait_sys(12);
                        r32(EDRV32_PLIC_BASE + 'h200004, claim);
                        check(claim == 32'(src), "PLIC asynchronous source", 64'(src),
                                64'(claim));
                        irq_src = 0;
                        wait_sys(12);
                        w32(EDRV32_PLIC_BASE + 'h200004, 32'(src));
                    end
                end
            end
            505: begin
                plic_config();
                w32(EDRV32_PLIC_BASE + 'h2000, '1);
                eq32(EDRV32_PLIC_BASE + 'h2000, 'hfffe);
                eq32(EDRV32_PLIC_BASE + 'h1000, 0, 'h99);
            end
            default: $fatal(1, "FAIL PLIC case %0d", id);
        endcase
    endtask
    task automatic uart_config(
        input real baud
    );
        u_uart.baud = baud;
        w32(EDRV32_UART0_BASE + 'h014, 32'($rtoi(real'(EDRV32_CLK_SYS_HZ) * 16.0 / baud + 0.5)));
        w32(EDRV32_UART0_BASE + 'h004, 'hf);
    endtask
    task automatic uart_byte_rx(
        input byte unsigned data,
        input bit bad_frame = 0
    );
        u_uart.send(data, bad_frame);
        wait_sys(12);
    endtask
    task automatic uart_pop(
        input byte unsigned expected
    );
        r32(EDRV32_UART0_BASE + 'h024, value);
        check(value[8:0] == {1'b1, expected}, "UART RXDATA", 64'({1'b1, expected}),
                64'(value[8:0]));
    endtask
    task automatic irq_route(
        input int source
    );
        w32(EDRV32_PLIC_BASE + 32'(4*source), 1);
        w32(EDRV32_PLIC_BASE + 'h2000, 32'b1 << source);
        w32(EDRV32_PLIC_BASE + 'h200000, 0);
    endtask
    task automatic uart_case(
        input int id
    );
        real bauds[3];
        bit [31:0] status;
        bauds = '{115200.0, 921600.0, 3000000.0};
        case (id)
            601: begin
                for (int rate = 0; rate < 3; rate++) begin
                    uart_config(bauds[rate]);
                    for (int n = 0; n < 4; n++) begin
                        fork
                            begin
                                w32(EDRV32_UART0_BASE + 'h020, 32'('h31 + n));
                                u_uart.expect_byte(8'('h31 + n));
                            end
                            uart_byte_rx(8'('ha1 + n));
                        join
                        uart_pop(8'('ha1 + n));
                    end
                    hit_coverage($sformatf("uart.baud.%0d", rate));
                end
            end
            602: begin
                uart_config(3000000.0);
                w32(EDRV32_UART0_BASE + 'h004, 2);
                eq32(EDRV32_UART0_BASE + 'h008, 5, 15);
                for (int n = 0; n < 16; n++) w32(EDRV32_UART0_BASE + 'h020, 32'(n));
                eq32(EDRV32_UART0_BASE + 'h008, 'h1002, 'h1f03);
                w32(EDRV32_UART0_BASE + 'h020, 'hff);
                w32(EDRV32_UART0_BASE + 'h004, 3);
                for (int n = 0; n < 16; n++) u_uart.expect_byte(8'(n));
                #(u_uart.bit_time() * 12.0);
                check(u_uart.received.size() == 0, "TX full write ignored", 0,
                        64'(u_uart.received.size()));
                eq32(EDRV32_UART0_BASE + 'h008, 1, 'h1f13);
                uart_byte_rx('h55);
                eq32(EDRV32_UART0_BASE + 'h008, 'h10000, 'h1f0004);
                w32(EDRV32_UART0_BASE + 'h004, 'hf);
                eq32(EDRV32_UART0_BASE + 'h008, 5, 'h1f1f0f);
                r32(EDRV32_UART0_BASE + 'h024, status);
                check(!status[8], "RX empty VALID", 0, 64'(status));
            end
            603: begin
                uart_config(3000000.0);
                for (int n = 0; n < 18; n++) uart_byte_rx(8'(n));
                eq32(EDRV32_UART0_BASE + 'h008, 'h100008, 'h1f000c);
                eq32(EDRV32_UART0_BASE + 'h010, 4, 4);
                for (int n = 0; n < 16; n++) uart_pop(8'(n));
                eq32(EDRV32_UART0_BASE + 'h008, 4, 12);
                hit_coverage("uart.overrun");
            end
            604: begin
                uart_config(3000000.0);
                uart_byte_rx('h6d, 1);
                eq32(EDRV32_UART0_BASE + 'h010, 8, 8);
                eq32(EDRV32_UART0_BASE + 'h008, 4, 4);
                uart_byte_rx('ha5);
                uart_pop('ha5);
                w32(EDRV32_UART0_BASE + 'h010, 8);
                eq32(EDRV32_UART0_BASE + 'h010, 0, 8);
                hit_coverage("uart.frame_error");
            end
            605: begin
                uart_config(3000000.0);
                irq_route(1);
                for (int condition = 0; condition < 4; condition++) begin
                    w32(EDRV32_UART0_BASE + 'h004, 'hf);
                    w32(EDRV32_UART0_BASE + 'h010, 12);
                    w32(EDRV32_UART0_BASE + 'h00c, 32'b1 << condition);
                    case (condition)
                        0: uart_byte_rx('h25);
                        1: wait_sys(8);
                        2: for (int n = 0; n < 17; n++) uart_byte_rx(8'(n));
                        3: uart_byte_rx('h26, 1);
                        default: $fatal(1, "FAIL UART IRQ case");
                    endcase
                    eq32(EDRV32_UART0_BASE + 'h010, 32'b1 << condition, 32'b1 << condition);
                    wait_sys(12);
                    check(irq_meip, "UART IRQ through PLIC", 1, 64'(irq_meip));
                    r32(EDRV32_PLIC_BASE + 'h200004, status);
                    check(status == 1, "UART IRQ source", 1, 64'(status));
                    w32(EDRV32_UART0_BASE + 'h00c, 0);
                    wait_sys(12);
                    w32(EDRV32_PLIC_BASE + 'h200004, 1);
                    wait_sys(12);
                    check(!irq_meip, "UART IRQ disabled", 0, 64'(irq_meip));
                    hit_coverage($sformatf("uart.irq.%0d", condition));
                end
            end
            606: begin
                uart_config(3000000.0);
                for (int sign = 0; sign < 2; sign++) begin
                    u_uart.deviation = sign == 0 ? -0.02 : 0.02;
                    for (int n = 0; n < 16; n++) begin
                        uart_byte_rx(8'(n ^ 'ha5));
                        uart_pop(8'(n ^ 'ha5));
                    end
                end
                u_uart.deviation = 0;
            end
            default: $fatal(1, "FAIL UART case %0d", id);
        endcase
    endtask

    task automatic gpio_case(
        input int id
    );
        case (id)
            701: begin
                w32(EDRV32_GPIO0_BASE + 4, 'h1234);
                w32(EDRV32_GPIO0_BASE + 4, 'habcd, 1);
                check(gpio_out == 'h12cd, "GPIO OUT byte low", 'h12cd, 64'(gpio_out));
                w32(EDRV32_GPIO0_BASE + 4, 'habcd, 2);
                check(gpio_out == 'habcd, "GPIO OUT byte high", 'habcd, 64'(gpio_out));
                w32(EDRV32_GPIO0_BASE + 8, 'h1234);
                w32(EDRV32_GPIO0_BASE + 8, 'habcd, 1);
                check(gpio_oe == 'h12cd, "GPIO OE byte low", 'h12cd, 64'(gpio_oe));
                w32(EDRV32_GPIO0_BASE + 8, 'habcd, 2);
                check(gpio_oe == 'habcd, "GPIO OE byte high", 'habcd, 64'(gpio_oe));
                gpio = 'h5aa5;
                wait_sys(8);
                eq32(EDRV32_GPIO0_BASE + 12, 'h5aa5);
            end
            702: begin
                w32(EDRV32_GPIO0_BASE + 'h1c, 20);
                gpio = 1;
                wait_sys(5);
                gpio = 0;
                wait_sys(30);
                eq32(EDRV32_GPIO0_BASE + 12, 0);
                gpio = 1;
                wait_sys(30);
                eq32(EDRV32_GPIO0_BASE + 12, 1);
                w32(EDRV32_GPIO0_BASE + 'h1c, 0);
                gpio = 2;
                wait_sys(5);
                eq32(EDRV32_GPIO0_BASE + 12, 2);
            end
            703: begin
                irq_route(2);
                w32(EDRV32_GPIO0_BASE + 'h10, 1);
                w32(EDRV32_GPIO0_BASE + 'h14, 2);
                gpio = 3;
                wait_sys(12);
                eq32(EDRV32_GPIO0_BASE + 'h18, 1);
                check(irq_meip, "GPIO rising IRQ", 1, 64'(irq_meip));
                r32(EDRV32_PLIC_BASE + 'h200004, value);
                check(value == 2, "GPIO claim source", 2, 64'(value));
                w32(EDRV32_GPIO0_BASE + 'h18, 1);
                eq32(EDRV32_GPIO0_BASE + 'h18, 0);
                gpio = 0;
                wait_sys(12);
                eq32(EDRV32_GPIO0_BASE + 'h18, 2);
                w32(EDRV32_GPIO0_BASE + 'h18, 2);
                eq32(EDRV32_GPIO0_BASE + 'h18, 0);
            end
            default: $fatal(1, "FAIL GPIO case %0d", id);
        endcase
    endtask

    task automatic i2c_cmd(
        input bit [11:0] command
    );
        w32(EDRV32_I2C0_BASE + 'h018, 32'(command));
        do r32(EDRV32_I2C0_BASE + 8, value); while (value[0]);
        eq32(EDRV32_I2C0_BASE + 'h010, 1, 1);
    endtask
    task automatic i2c_pointer(
        input bit stop_after
    );
        i2c_cmd('h178);
        i2c_cmd('h030);
        i2c_cmd(stop_after ? 'h210 : 'h010);
    endtask
    task automatic i2c_write_register(
        input bit port_index,
        input byte unsigned data
    );
        w32(EDRV32_I2C0_BASE + 4, 32'(1 | (int'(port_index) << 1)));
        i2c_pointer(0);
        i2c_cmd(12'h200 | 12'(data));
    endtask
    task automatic i2c_case(
        input int id
    );
        int before_bytes;
        w32(EDRV32_I2C0_BASE + 'h014, 93);
        case (id)
            801: begin
                for (int port_index = 0; port_index < 2; port_index++) begin
                    i2c_write_register(1'(port_index), 8'('ha5 + port_index));
                    if (port_index == 0)
                        check(u_cam0.registers['h3010] == 'ha5, "cam0 SCCB write", 'ha5,
                                64'(u_cam0.registers['h3010]));
                    else check(u_cam1.registers['h3010] == 'ha6, "cam1 SCCB write", 'ha6,
                                64'(u_cam1.registers['h3010]));
                    hit_coverage($sformatf("i2c.port.%0d", port_index));
                end
                hit_coverage("i2c.write");
            end
            802: begin
                u_cam0.registers['h3010] = 'hd3;
                w32(EDRV32_I2C0_BASE + 4, 1);
                for (int repeated = 0; repeated < 2; repeated++) begin
                    i2c_pointer(repeated == 0);
                    i2c_cmd('h179);
                    i2c_cmd('he00);
                    eq32(EDRV32_I2C0_BASE + 'h01c, 'hd3, 255);
                end
                hit_coverage("i2c.read");
            end
            803: begin
                irq_route(5);
                w32(EDRV32_I2C0_BASE + 'h00c, 1);
                u_cam0.nack_byte = 1;
                w32(EDRV32_I2C0_BASE + 4, 1);
                i2c_cmd('h178);
                i2c_cmd('h230);
                eq32(EDRV32_I2C0_BASE + 8, 2, 3);
                eq32(EDRV32_I2C0_BASE + 'h010, 1, 1);
                wait_sys(12);
                check(irq_meip, "I2C DONE IRQ", 1, 64'(irq_meip));
                r32(EDRV32_PLIC_BASE + 'h200004, value);
                check(value == 5, "I2C claim source", 5, 64'(value));
                check(u_cam0.nacks == 1, "SCCB configured NACK", 1, 64'(u_cam0.nacks));
                hit_coverage("i2c.nack");
            end
            804: begin
                for (int port_index = 0; port_index < 2; port_index++) begin
                    monitored_port = port_index;
                    check_unselected = 1;
                    i2c_write_register(1'(port_index), 'h5a);
                    check_unselected = 0;
                end
            end
            805: begin
                for (int speed = 0; speed < 2; speed++) begin
                    int div;
                    div = speed == 0 ? 374 : 93;
                    w32(EDRV32_I2C0_BASE + 'h014, 32'(div));
                    u_cam0.quarter_ns = real'(div + 1) * 2.0 * sys_half;
                    i2c_write_register(0, 'hc3);
                    hit_coverage($sformatf("i2c.speed.%0d", speed));
                end
            end
            806: begin
                w32(EDRV32_I2C0_BASE + 4, 1);
                w32(EDRV32_I2C0_BASE + 'h018, 'h178);
                eq32(EDRV32_I2C0_BASE + 8, 1, 1);
                before_bytes = u_cam0.bytes_seen.size();
                w32(EDRV32_I2C0_BASE + 'h018, 'h2ff);
                do r32(EDRV32_I2C0_BASE + 8, value); while (value[0]);
                check(u_cam0.bytes_seen.size() == before_bytes + 1,
                        "BUSY command ignored", 64'(int'(before_bytes + 1)),
                        64'(u_cam0.bytes_seen.size()));
                check(u_cam0.bytes_seen[$] == 'h78, "BUSY preserves active byte", 'h78,
                        64'(u_cam0.bytes_seen[$]));
                i2c_cmd('h200);
            end
            default: $fatal(1, "FAIL I2C case %0d", id);
        endcase
    endtask
    int monitored_port = 0;
    bit check_unselected = 0;
    always @(posedge clk_sys) begin
        if (rst_sys_n && check_unselected)
            check(!scl_oe[1-monitored_port] && !sda_oe[1-monitored_port],
                    "unselected I2C released", 0,
                    64'({scl_oe[1-monitored_port], sda_oe[1-monitored_port]}));
        if (rst_sys_n)
            check((scl_o & scl_oe) == 0 && (sda_o & sda_oe) == 0,
                    "I2C open drain", 0, 64'({scl_o & scl_oe, sda_o & sda_oe}));
    end
    task automatic power_reset();
        @(negedge clk_sys);
        rst_n = 0;
        mem_ready = 0;
        #0.001;
        check(!rst_sys_n && !rst_mem_core_n && !rst_mem_n && !rst_pix_n &&
                !rst_cam0_n && !rst_cam1_n && !rst_eth_rx_n && !rst_eth_tx_n,
                "asynchronous reset assertion", 0,
                64'({rst_sys_n, rst_mem_core_n, rst_mem_n, rst_pix_n, rst_cam0_n,
                    rst_cam1_n, rst_eth_rx_n, rst_eth_tx_n}));
        wait_sys(5);
        rst_n = 1;
        wait_sys(20);
        check(!rst_sys_n && !rst_mem_n && !rst_mem_core_n, "wait for mem_ready", 0,
                64'({rst_sys_n, rst_mem_n, rst_mem_core_n}));
        mem_ready = 1;
        wait (rst_mem_core_n);
        check(!rst_sys_n, "memory releases before system", 0, 64'(rst_sys_n));
        wait (rst_sys_n);
        wait_sys(3);
        check(rst_mem_n && rst_pix_n && rst_cam0_n && rst_cam1_n &&
                rst_eth_rx_n && rst_eth_tx_n, "peripheral reset release", 1,
                64'(rst_mem_n && rst_pix_n && rst_cam0_n && rst_cam1_n &&
                    rst_eth_rx_n && rst_eth_tx_n));
    endtask
    task automatic soft_reset(
        input bit soc
    );
        bit observed;
        int low_cycles;
        observed = 0;
        low_cycles = 0;
        fork
            w32(EDRV32_SYSCTRL_BASE + 'h018, soc ? 2 : 1);
            begin
                @(negedge rst_mem_n);
                observed = 1;
                #0.001;
                check(!rst_pix_n && !rst_cam0_n && !rst_cam1_n && !rst_eth_rx_n &&
                        !rst_eth_tx_n, "all media resets assert", 0,
                        64'({rst_pix_n, rst_cam0_n, rst_cam1_n, rst_eth_rx_n, rst_eth_tx_n}));
                if (soc) check(!rst_sys_n, "SOC asserts system reset", 0, 64'(rst_sys_n));
                check(rst_mem_core_n, "memory core survives soft reset", 1,
                        64'(rst_mem_core_n));
                if (!soc) check(rst_sys_n, "media reset leaves sys running", 1,
                                64'(rst_sys_n));
                while (!rst_mem_n) begin
                    @(negedge clk_sys);
                    if (!rst_mem_n) low_cycles++;
                    check(rst_mem_core_n, "memory core reset retention", 1,
                            64'(rst_mem_core_n));
                    if (!soc) check(rst_sys_n, "sys reset retention", 1, 64'(rst_sys_n));
                end
                check(low_cycles >= 16, "soft reset minimum pulse", 16, 64'(low_cycles));
                if (soc) check(!rst_sys_n, "SOC releases memory before system", 0,
                                64'(rst_sys_n));
                wait (rst_sys_n);
                wait_sys(5);
                check(rst_pix_n && rst_cam0_n && rst_cam1_n && rst_eth_rx_n && rst_eth_tx_n,
                        "media resets release", 1,
                        64'(rst_pix_n && rst_cam0_n && rst_cam1_n && rst_eth_rx_n &&
                            rst_eth_tx_n));
            end
        join
        check(observed, "soft reset observed", 1, 64'(observed));
    endtask
    task automatic sysctrl_case(
        input int id
    );
        case (id)
            901: begin
                eq32(EDRV32_SYSCTRL_BASE, 'h00060001);
                eq32(EDRV32_SYSCTRL_BASE + 4, 'hed320001);
                eq32(EDRV32_SYSCTRL_BASE + 8, EDRV32_CLK_SYS_HZ);
                eq32(EDRV32_SYSCTRL_BASE + 12, 1, 1);
            end
            902: begin
                w32(EDRV32_SYSCTRL_BASE + 'h010, 'h11223344);
                w32(EDRV32_SYSCTRL_BASE + 'h014, 'h55667788);
                soft_reset(1);
                eq32(EDRV32_SYSCTRL_BASE + 'h010, 'h11223344);
                eq32(EDRV32_SYSCTRL_BASE + 'h014, 'h55667788);
                power_reset();
                eq32(EDRV32_SYSCTRL_BASE + 'h010, 0);
                eq32(EDRV32_SYSCTRL_BASE + 'h014, 0);
            end
            903, 904: begin
                soft_reset(id == 904);
                hit_coverage(id == 903 ? "reset.media" : "reset.soc");
            end
            905: begin
                power_reset();
                hit_coverage("reset.power");
            end
            906: begin
                fork
                    w32(EDRV32_SYSCTRL_BASE + 'h01c, 'h12345678);
                    begin
                        @(posedge sim_exit_valid);
                        check(sim_exit_code == 'h12345678, "SIM_EXIT payload", 'h12345678,
                                64'(sim_exit_code));
                    end
                join
                fork
                    w32(EDRV32_SYSCTRL_BASE + 'h01c, 0);
                    begin
                        @(posedge sim_exit_valid);
                        check(sim_exit_code == 0, "SIM_EXIT pass", 0, 64'(sim_exit_code));
                    end
                join
            end
            default: $fatal(1, "FAIL SYSCTRL case %0d", id);
        endcase
    endtask

    // Selftest directly drives external SCCB pins while the DUT I2C controller is disabled.
    task automatic peer_start(
        input bit port_index
    );
        test_sda_oe = (test_sda_oe & ~(2'b01 << port_index)) |
                        (2'(0) << port_index);
        test_scl_oe = (test_scl_oe & ~(2'b01 << port_index)) |
                        (2'(0) << port_index);
        #1000;
        test_sda_oe = (test_sda_oe & ~(2'b01 << port_index)) |
                        (2'(1) << port_index);
        #1000;
        test_scl_oe = (test_scl_oe & ~(2'b01 << port_index)) |
                        (2'(1) << port_index);
        #1000;
    endtask
    task automatic peer_byte(
        input bit port_index,
        input byte unsigned data,
        input bit expect_ack = 1
    );
        for (int b = 7; b >= 0; b--) begin
            test_sda_oe = (test_sda_oe & ~(2'b01 << port_index)) |
                        (2'(!data[b]) << port_index);
            #1000;
            test_scl_oe = (test_scl_oe & ~(2'b01 << port_index)) |
                        (2'(0) << port_index);
            #2000;
            test_scl_oe = (test_scl_oe & ~(2'b01 << port_index)) |
                        (2'(1) << port_index);
            #1000;
        end
        test_sda_oe = (test_sda_oe & ~(2'b01 << port_index)) |
                        (2'(0) << port_index);
        #1000;
        test_scl_oe = (test_scl_oe & ~(2'b01 << port_index)) |
                        (2'(0) << port_index);
        #1000;
        check(sda_i[port_index] == !expect_ack, "SCCB model ACK/NACK",
                64'(!expect_ack), 64'(sda_i[port_index]));
        #1000;
        test_scl_oe = (test_scl_oe & ~(2'b01 << port_index)) |
                        (2'(1) << port_index);
        #1000;
    endtask
    task automatic peer_read(
        input bit port_index,
        output byte unsigned data
    );
        test_sda_oe = test_sda_oe & ~(2'b01 << port_index);
        for (int b = 7; b >= 0; b--) begin
            #1000;
            test_scl_oe = test_scl_oe & ~(2'b01 << port_index);
            #1000;
            data[b] = sda_i[port_index];
            #1000;
            test_scl_oe = test_scl_oe | (2'b01 << port_index);
            #1000;
        end
        // Release the ninth bit to NACK the final byte.
        #1000;
        test_scl_oe = test_scl_oe & ~(2'b01 << port_index);
        #2000;
        test_scl_oe = test_scl_oe | (2'b01 << port_index);
        #1000;
    endtask
    task automatic peer_stop(
        input bit port_index
    );
        test_sda_oe = (test_sda_oe & ~(2'b01 << port_index)) |
                        (2'(1) << port_index);
        #1000;
        test_scl_oe = (test_scl_oe & ~(2'b01 << port_index)) |
                        (2'(0) << port_index);
        #2000;
        test_sda_oe = (test_sda_oe & ~(2'b01 << port_index)) |
                        (2'(0) << port_index);
        #2000;
    endtask
    task automatic selftest();
        byte unsigned serial_data;
        int timeout_start;
        bit [63:0] unused_data0[256];
        bit [63:0] unused_data1[256];
        bit [1:0] resp0[256];
        bit [1:0] resp1[256];
        fork
            u_m0.read(EDRV32_ROM_BASE, 3, 0, unused_data0, resp0);
            u_m1.read(EDRV32_SRAM_BASE, 3, 3, unused_data1, resp1);
        join
        check(resp0[0] == 0 && resp1[3] == 0, "dual master access", 0,
                64'({resp0[0], resp1[3]}));
        wr(EDRV32_SRAM_BASE + 'h100, 64'h123456789abcdef0, 8'hff, 3, 3);
        rd(1, EDRV32_SRAM_BASE + 'h100, 3, 3, -1, 1);
        rd(0, EDRV32_CLINT_BASE, 3, 3, 3);
        rd(1, 32'h50000000, 3, 3, 3);
        wr(32'h50000000, 0, 8'hff, 3, 3, 3);
        if (rom_image_loaded) begin
            rd(0, EDRV32_ROM_BASE, 3, 0, -1, 1);
            rd(0, EDRV32_ROM_BASE + EDRV32_ROM_SIZE - 8, 3, 0, -1, 1);
        end
        if (sram_image_loaded)
            rd(1, EDRV32_SRAM_BASE + EDRV32_SRAM_SIZE - 4, 2, 0, -1, 1);
        u_media.delay_cycles = 3;
        w32(EDRV32_MEDIA_APB_BASE + 'h100, 'h12345678);
        eq32(EDRV32_MEDIA_APB_BASE + 'h100, 'h12345678);
        u_media.inject_error = 1;
        rd(1, EDRV32_MEDIA_APB_BASE, 2, 0, 2);
        u_media.inject_error = 0;
        wr(EDRV32_ROM_BASE, '1, 8'h0f, 2, 0, 2);
        u_media.never_ready = 1;
        timeout_start = mem_access_cycles;
        rd(1, EDRV32_MEDIA_APB_BASE, 2, 0, 2);
        check(mem_access_cycles - timeout_start == 256, "selftest APB timeout", 256,
                64'(int'(mem_access_cycles - timeout_start)));
        u_media.never_ready = 0;
        eq32(EDRV32_MEDIA_APB_BASE + 'h100, 'h12345678);
        uart_config(3000000.0);
        fork
            begin
                w32(EDRV32_UART0_BASE + 'h020, 'h5a);
                u_uart.expect_byte('h5a);
            end
            uart_byte_rx('h5a);
        join
        uart_pop('h5a);
        uart_byte_rx('h0d, 1);
        eq32(EDRV32_UART0_BASE + 'h010, 8, 8);
        eq32(EDRV32_UART0_BASE + 'h008, 4, 4);
        u_cam0.quarter_ns = 1000;
        peer_start(0);
        peer_byte(0, 'h78);
        peer_byte(0, 'h30);
        peer_byte(0, 'h10);
        peer_byte(0, 'hba);
        peer_stop(0);
        check(u_cam0.writes == 1 && u_cam0.registers['h3010] == 'hba,
                "SCCB model write", 'hba, 64'(u_cam0.registers['h3010]));
        peer_start(0);
        peer_byte(0, 'h78);
        peer_byte(0, 'h30);
        peer_byte(0, 'h10);
        peer_stop(0);
        peer_start(0);
        peer_byte(0, 'h79);
        peer_read(0, serial_data);
        peer_stop(0);
        check(serial_data == 'hba, "SCCB model read", 'hba, 64'(serial_data));
        u_cam1.nack_byte = 2;
        peer_start(1);
        peer_byte(1, 'h78);
        peer_byte(1, 'h30);
        peer_byte(1, 'h10, 0);
        peer_stop(1);
        check(u_cam1.nacks == 1 && u_cam1.writes == 0, "SCCB model NACK", 1,
                64'(u_cam1.nacks));
        $display("SELFTEST dual-master DECERR APB UART SCCB complete");
    endtask

    // Atomic simulation coverage updates observe interface handshakes, including raw drivers.
    /* verilator lint_off BLKSEQ */
    always @(posedge clk_sys) begin
        if (rst_sys_n) begin
            if (m0.arvalid && m0.arready)
                hit_coverage($sformatf("route.m0.s%0d.read",
                                edrv32_sys_reference::region(m0.araddr)));
            if (m1.arvalid && m1.arready)
                hit_coverage($sformatf("route.m1.s%0d.read",
                                edrv32_sys_reference::region(m1.araddr)));
            if (m1.awvalid && m1.awready)
                hit_coverage($sformatf("route.m1.s%0d.write",
                                edrv32_sys_reference::region(m1.awaddr)));
            if (m0.rvalid && m0.rready)
                hit_coverage($sformatf("response.read.%0d", m0.rresp));
            if (m1.rvalid && m1.rready)
                hit_coverage($sformatf("response.read.%0d", m1.rresp));
            if (m1.bvalid && m1.bready)
                hit_coverage($sformatf("response.write.%0d", m1.bresp));
        end
    end
    /* verilator lint_on BLKSEQ */

    bit rom_image_loaded = 0;
    bit sram_image_loaded = 0;
    task automatic load_reference_images();
        string path;
        bit [63:0] rom[2048];
        bit [63:0] sram[EDRV32_SRAM_SIZE/8];
        if ($value$plusargs("ROM_HEX=%s", path)) begin
            $readmemh(path, rom);
            for (int n = 0; n < 2048; n++)
                edrv32_sys_reference::store(EDRV32_ROM_BASE + 32'(n*8), rom[n], 8'hff);
            rom_image_loaded = 1;
        end
        if ($value$plusargs("SRAM_HEX=%s", path)) begin
            $readmemh(path, sram);
            for (int n = 0; n < EDRV32_SRAM_SIZE/8; n++)
                edrv32_sys_reference::store(EDRV32_SRAM_BASE + 32'(n*8), sram[n], 8'hff);
            sram_image_loaded = 1;
        end
    endtask
