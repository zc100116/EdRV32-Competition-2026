// File: edrv32_mem_subsys_tb.sv
// Spec: mem-subsys v0.6; testplan 3.1-3.4, 4-6.
// Description: Independent top-level stimulus, byte scoreboard, scheduling and register checks.
// Clock domains: asynchronous clk_sys and clk_mem.
module edrv32_mem_subsys_tb;
    timeunit 1ns;
    timeprecision 1ps;
    parameter int CASE = 101;
    parameter int SEED = 1;
    int selected_case = CASE;
    int seed = SEED;
    logic clk_sys = 0;
    logic clk_mem = 0;
    logic rst_sys_n = 0;
    logic rst_mem_n = 0;
    realtime sys_half = 3.333ns;
    always begin
        #(sys_half);
        clk_sys = !clk_sys;
    end
    always #4ns clk_mem = !clk_mem;
    edrv32_axi64_if gw();
    edrv32_axi256_if p[5]();
    edrv32_axi256_if #(.ID_WIDTH(4)) ddr();
    wire [4:0] urgent;
    wire [4:0] bfm_urgent;
    int rt_level[2];
    int rt_reserved[2];
    int rt_min[2];
    bit rt_running = 0;
    bit rt_consume = 0;
    int rt_rows;
    int rt_samples;
    int row_phase;
    int sample_phase;
    assign urgent[0] = stress_active ? rt_level[0] < 40 : bfm_urgent[0];
    assign urgent[1] = stress_active ? rt_level[1] < 64 : bfm_urgent[1];
    assign urgent[4:2] = bfm_urgent[4:2];
    logic [0:0][11:0] apb_paddr;
    logic [0:0] apb_psel;
    logic [0:0] apb_penable;
    logic [0:0] apb_pwrite;
    logic [0:0][31:0] apb_pwdata;
    logic [0:0][3:0] apb_pstrb;
    logic [0:0] apb_pready;
    logic [0:0][31:0] apb_prdata;
    logic [0:0] apb_pslverr;
    logic irq;
    int checker_errors;
    int checked_beats;
    int committed_writes;
    int local_errors[5];
    int local_reads[5];
    int local_writes[5];
    int total_limit = 8;
    int read_limit[5] = '{4,1,1,4,2};
    int write_limit[5] = '{0,0,1,2,2};
    bit check_read_data = 1;
    int grant_start;
    int cycle;
    int credit_reserved;
    int max_credit;
    int upstream_read_beats;
    int direction_run;
    int last_direction = -1;
    bit check_w_contiguous = 0;
    int w_remaining;
    int gw_count;
    int coverage_gateway[2][2][2];
    bit coverage_size[4][32];
    int coverage_illegal_gw[10];
    bit coverage_credit;
    bit coverage_violation[2][2];
    bit [31:0] random_state;

    edrv32_axi64_master u_gateway (
        .clk_i(clk_sys),
        .rst_n_i(rst_sys_n),
        .bus(gw)
    );
    for (genvar n = 0; n < 5; n++) begin : g_port
        edrv32_axi256_master #(
            .READ_ONLY(n < 2)
        ) u_master (
            .clk_i(clk_mem),
            .rst_n_i(rst_mem_n),
            .urgent_o(bfm_urgent[n]),
            .bus(p[n])
        );
        if (n != 2) begin : g_checker
            edrv32_axi256_checker #(.CHECK_ADDRESS(0)) u_checker (
                .clk_i(clk_mem),
                .rst_n_i(rst_mem_n),
                .bus(p[n]),
                .errors_o(local_errors[n])
            );
            typedef struct packed {
                bit [31:0] addr;
                int len;
                bit id;
            } request_t;
            request_t requests[2][$];
            int beat[2];
            always @(posedge clk_mem) begin : upstream_scoreboard
                request_t request;
                bit [255:0] expected;
                int local_id;
                if (!rst_mem_n) begin
                    for (int id = 0; id < 2; id++) begin
                        requests[id].delete();
                        beat[id] = 0;
                    end
                    local_reads[n] = 0;
                    local_writes[n] = 0;
                end else begin
                    if (p[n].arvalid && p[n].arready) begin
                        request.addr = p[n].araddr;
                        request.len = int'(p[n].arlen);
                        request.id = p[n].arid;
                        requests[int'(p[n].arid)].push_back(request);
                    end
                    if (p[n].rvalid && p[n].rready) begin
                        local_id = int'(p[n].rid);
                        request = requests[local_id][0];
                        if (p[n].rid != request.id)
                            $fatal(1, "FAIL local RID p=%0d expected=%h actual=%h time=%0t",
                                   n, request.id, p[n].rid, $time);
                        for (int b = 0; b < 32; b++)
                            expected[b*8 +: 8] =
                                u_reference.peek(request.addr+32'(beat[local_id]*32+b));
                        if (check_read_data && p[n].rresp == 0 && p[n].rdata !== expected)
                            $fatal(1, "FAIL local data expected=%h actual=%h time=%0t",
                                   expected, p[n].rdata, $time);
                        if (p[n].rlast) begin
                            request = requests[local_id].pop_front();
                            beat[local_id] = 0;
                            local_reads[n]++;
                        end else beat[local_id]++;
                    end
                    if (p[n].bvalid && p[n].bready) local_writes[n]++;
                end
            end
        end
    end
    // P2 is internal to the subsystem, and the P0 write channels are not exposed.
    assign p[2].awready = 0;
    assign p[2].wready = 0;
    assign p[2].bvalid = 0;
    assign p[2].bid = 0;
    assign p[2].bresp = 0;
    assign p[2].arready = 0;
    assign p[2].rvalid = 0;
    assign p[2].rid = 0;
    assign p[2].rdata = 0;
    assign p[2].rresp = 0;
    assign p[2].rlast = 0;
    assign p[0].awready = 0;
    assign p[0].wready = 0;
    assign p[0].bvalid = 0;
    assign p[0].bid = 0;
    assign p[0].bresp = 0;
    assign p[1].awready = 0;
    assign p[1].wready = 0;
    assign p[1].bvalid = 0;
    assign p[1].bid = 0;
    assign p[1].bresp = 0;

    edrv32_axi256_checker #(.DOWNSTREAM(1)) u_checker (
        .clk_i(clk_mem),
        .rst_n_i(rst_mem_n),
        .bus(ddr),
        .errors_o(checker_errors)
    );
    edrv32_axi256_reference u_reference (
        .clk_i(clk_mem),
        .rst_n_i(rst_mem_n),
        .bus(ddr),
        .checked_beats_o(checked_beats),
        .committed_writes_o(committed_writes)
    );
    edrv32_mem_schedule_observer u_schedule (
        .clk_i(clk_mem),
        .rst_n_i(rst_mem_n),
        .total_limit_i(total_limit),
        .read_limit_i(read_limit),
        .write_limit_i(write_limit),
        .bus(ddr)
    );
    `include "dut_connection.svh"
    `include "ddr_connection.svh"

    `include "xbar_observation.svh"
    `include "gateway_observation.svh"
    `include "gateway_overlap.svh"
    // Two-stage grant pipeline sampling times, see M-R2b (coordinator-approved observation).
    wire [1:0] schedule_phase_w = {u_dut.u_xbar.u_sched.prepare_o,
        u_dut.u_xbar.u_sched.grant_o};
    edrv32_mem_schedule_reference u_schedule_reference (
        .clk_i(clk_mem),
        .rst_n_i(rst_mem_n),
        .urgent_i({3'b0, u_dut.u_xbar.p1_urgent_i, u_dut.u_xbar.p0_urgent_i}),
        .prepare_i(schedule_phase_w[1]),
        .grant_i(schedule_phase_w[0]),
        .upstream(xbar),
        .downstream(ddr)
    );

    edrv32_mem_write_scoreboard u_write_scoreboard (
        .clk_i(clk_mem),
        .rst_n_i(rst_mem_n),
        .masters(p),
        .downstream(ddr)
    );

    function automatic int unsigned random_next();
        random_state ^= random_state << 13;
        random_state ^= random_state >> 17;
        random_state ^= random_state << 5;
        return random_state;
    endfunction

    task automatic eq(input string name,
        input int expected,
        input int actual);
        if (actual != expected)
            $fatal(1, "FAIL %s expected=%0h actual=%0h time=%0t", name, expected, actual, $time);
    endtask

    task automatic truth(input string name,
        input bit actual);
        if (!actual) $fatal(1, "FAIL %s expected=1 actual=0 time=%0t", name, $time);
    endtask

    task automatic apb(input int slot,
        input bit write,
        input bit [11:0] addr,
                       input bit [31:0] data, output bit [31:0] result);
        @(negedge clk_mem);
        // Whole-vector writes keep timed driver changes visible to Verilator 5.020.
        apb_psel = 1'b1;
        apb_paddr = addr;
        apb_pwrite = write;
        apb_pwdata = data;
        apb_pstrb = 4'hf;
        @(negedge clk_mem);
        apb_penable = apb_psel;
        do @(posedge clk_mem); while (!apb_pready[slot]);
        eq("APB PSLVERR", 0, int'(apb_pslverr[slot]));
        result = apb_prdata[slot];
        @(negedge clk_mem);
        apb_psel = 1'b0;
        apb_penable = 1'b0;
    endtask

    task automatic wr(input int slot,
        input bit [11:0] addr,
        input bit [31:0] data);
        bit [31:0] unused_result;
        apb(slot, 1, addr, data, unused_result);
    endtask

    task automatic rd_eq(input int slot,
        input bit [11:0] addr,
        input bit [31:0] expected);
        bit [31:0] actual;
        apb(slot, 0, addr, 0, actual);
        if (actual != expected)
            $fatal(1, "FAIL APB slot=%0d addr=%h expected=%h actual=%h time=%0t",
                   slot, addr, expected, actual, $time);
    endtask

    task automatic rd(input int slot,
        input bit [11:0] addr, output bit [31:0] actual);
        apb(slot, 0, addr, 0, actual);
    endtask

    task automatic preload(input bit [31:0] addr,
        input int bytes,
        input bit [31:0] pattern_seed);
        bit [31:0] word_value;
        for (int b = 0; b < bytes; b++) begin
            word_value = ((addr+32'(b)) & 32'hfffffffc) ^ pattern_seed;
            u_ddr.poke(addr+32'(b), word_value[(b%4)*8 +: 8]);
            u_reference.poke(addr+32'(b), word_value[(b%4)*8 +: 8]);
        end
    endtask

    task automatic send_read(input int port,
        input bit [31:0] addr,
                             input int len = 15,
        input bit id = 0);
        case (port)
            0: g_port[0].u_master.enqueue_read(addr, len, id);
            1: g_port[1].u_master.enqueue_read(addr, len, id);
            3: g_port[3].u_master.enqueue_read(addr, len, id);
            4: g_port[4].u_master.enqueue_read(addr, len, id);
            default: $fatal(1, "FAIL send_read expected=P0/P1/P3/P4 actual=%0d time=%0t",
                            port, $time);
        endcase
    endtask

    task automatic send_write(input int port,
        input bit [31:0] addr,
                              input int len = 15,
        input bit id = 0,
                              input bit partial = 0);
        bit [255:0] data[16];
        bit [31:0] strb[16];
        for (int n = 0; n <= len; n++) begin
            for (int word_index = 0; word_index < 8; word_index++)
                data[n][word_index*32 +: 32] = (addr+32'(n*32+word_index*4)) ^ 32'h5a37abcd;
            strb[n] = partial ? (32'h55555555 << n%2) : '1;
        end
        case (port)
            3: g_port[3].u_master.enqueue_write(addr, len, data, strb, id);
            4: g_port[4].u_master.enqueue_write(addr, len, data, strb, id);
            default: $fatal(1, "FAIL send_write expected=P3/P4 actual=%0d time=%0t",
                            port, $time);
        endcase
    endtask

    task automatic wait_port(input int port,
        input int nr,
        input int nw);
        case (port)
            0: g_port[0].u_master.wait_done(nr, nw);
            1: g_port[1].u_master.wait_done(nr, nw);
            3: g_port[3].u_master.wait_done(nr, nw);
            4: g_port[4].u_master.wait_done(nr, nw);
            default: $fatal(1, "FAIL wait_port actual=%0d time=%0t", port, $time);
        endcase
    endtask

    task automatic require_grants(input int nr);
        eq("forwarded transaction count", nr, u_schedule.grants.size()-grant_start);
        grant_start = u_schedule.grants.size();
    endtask

    function automatic bit gateway_legal(input bit [31:0] addr,
        input int size,
                                          input int len,
        input bit [1:0] burst);
        return burst == 1 && ((len == 3 && size == 3 && addr[4:0] == 0) ||
               (len == 0 && size <= 3 && (addr & ((32'b1 << size)-1)) == 0));
    endfunction

    task automatic gateway_write(input bit [31:0] addr,
        input int size,
                                 input int len,
        input bit [1:0] resp = 0,
                                 input bit [1:0] burst = 1);
        bit [63:0] data[256];
        bit [7:0] strb[256];
        bit [1:0] actual;
        bit [3:0] transaction_id;
        gateway_expected_t expected_write;
        transaction_id = 4'(gw_count++);
        for (int n = 0; n <= len; n++) begin
            data[n] = {32'hcc55aa33 ^ 32'(n), 32'h551122aa ^ addr ^ 32'(n)};
            strb[n] = len == 3 ? 8'hff : 8'(((1 << (1 << size))-1) << addr[2:0]);
        end
        if (gateway_legal(addr, size, len, burst)) begin
            expected_write = '0;
            expected_write.addr = addr & 32'h3fffffe0;
            if (len == 3) begin
                for (int n = 0; n < 4; n++) expected_write.data[n*64 +: 64] = data[n];
                expected_write.strb = '1;
            end else begin
                expected_write.data[int'(addr[4:3])*64 +: 64] = data[0];
                expected_write.strb = ((32'b1 << (1 << size))-1) << addr[4:0];
            end
            gateway_writes.push_back(expected_write);
        end
        gw.awid = transaction_id;
        gw.awburst = burst;
        u_gateway.write(addr, 3'(size), len, data, strb, actual);
        eq("gateway BRESP", int'(resp), int'(actual));
        eq("gateway BID", int'(transaction_id), int'(gateway_response_bid));
    endtask

    task automatic gateway_read(input bit [31:0] addr,
        input int size,
                                input int len,
        input bit [1:0] resp = 0,
                                input bit [1:0] burst = 1);
        bit [63:0] data[256];
        bit [1:0] actual[256];
        bit [63:0] expected;
        bit [31:0] physical;
        bit [3:0] transaction_id;
        transaction_id = 4'(gw_count++);
        if (gateway_legal(addr, size, len, burst)) gateway_reads.push_back(addr & 32'h3fffffe0);
        gw.arid = transaction_id;
        gw.arburst = burst;
        u_gateway.read(addr, 3'(size), len, data, actual);
        eq("gateway RID", int'(transaction_id), int'(gateway_response_rid));
        for (int n = 0; n <= len; n++) begin
            eq("gateway RRESP", int'(resp), int'(actual[n]));
            physical = (addr & 32'h3ffffff8)+32'(n*8);
            for (int b = 0; b < 8; b++) expected[b*8 +: 8] = u_reference.peek(physical+32'(b));
            if (resp == 0 && data[n] !== expected)
                $fatal(1, "FAIL GW read beat=%0d expected=%h actual=%h time=%0t",
                       n, expected, data[n], $time);
        end
    endtask

    bit [4:0] upstream_take;
    for (genvar n = 0; n < 5; n++) begin : g_take
        assign upstream_take[n] = n != 2 && p[n].rvalid && p[n].rready;
    end

    int ddr_read_stamp[16][$];
    bit ddr_read_started[16];
    int ddr_latency_count;
    int ddr_latency_sum;
    int ddr_latency_min;
    int ddr_latency_max;

    always @(posedge clk_mem) begin : downstream_observation
        int id;
        int latency;
        int length;
        int direction;
        if (!rst_mem_n) begin
            cycle = 0;
            ddr_latency_count = 0;
            ddr_latency_sum = 0;
            ddr_latency_min = 32'h7fffffff;
            ddr_latency_max = 0;
            for (int j = 0; j < 16; j++) begin
                ddr_read_stamp[j].delete();
                ddr_read_started[j] = 0;
            end
            credit_reserved = 0;
            max_credit = 0;
            upstream_read_beats = 0;
            w_remaining = 0;
            direction_run = 0;
            last_direction = -1;
        end else begin
            cycle++;
            if (check_w_contiguous && w_remaining > 0)
                truth("downstream W continuous", ddr.wvalid);
            if (ddr.wvalid && ddr.wready) w_remaining--;
            if (ddr.awvalid && ddr.awready) w_remaining += int'(ddr.awlen)+1;
            if (ddr.arvalid && ddr.arready) begin
                id = int'(ddr.arid);
                ddr_read_stamp[id].push_back(cycle);
                length = int'(ddr.arlen)+1;
                if (selected_case == 207) begin
                    credit_reserved += length;
                    if (credit_reserved > max_credit) max_credit = credit_reserved;
                    truth("credit capacity", credit_reserved <= 128);
                    if (credit_reserved == 128) coverage_credit = 1;
                end
            end
            if (selected_case == 207) begin
                for (int j = 0; j < 5; j++)
                    if (upstream_take[j]) begin
                        credit_reserved--;
                        upstream_read_beats++;
                    end
            end
            if (ddr.rvalid) begin
                id = int'(ddr.rid);
                if (!ddr_read_started[id]) begin
                    latency = cycle-ddr_read_stamp[id][0];
                    ddr_latency_count++;
                    ddr_latency_sum += latency;
                    if (latency < ddr_latency_min) ddr_latency_min = latency;
                    if (latency > ddr_latency_max) ddr_latency_max = latency;
                    ddr_read_started[id] = 1;
                end
                if (ddr.rlast) begin
                    ddr_read_stamp[id].delete(0);
                    ddr_read_started[id] = 0;
                end
            end
            if (ddr.arvalid && ddr.arready || ddr.awvalid && ddr.awready) begin
                direction = ddr.awvalid && ddr.awready ? 1 : 0;
                if (direction == last_direction) direction_run++;
                else direction_run = 1;
                last_direction = direction;
            end
        end
    end

    task automatic drain(input int clocks = 20);
        repeat (clocks) @(negedge clk_mem);
    endtask

    task automatic test_gateway(input int test);
        int before_grants;
        bit [31:0] window_addr;
        case (test)
            101: begin
                for (int window = 0; window < 2; window++) begin
                    window_addr = window == 0 ? 32'h80002000 : 32'hc0002400;
                    gateway_write(window_addr, 3, 3);
                    gateway_read(window_addr, 3, 3);
                    require_grants(2);
                    coverage_gateway[0][window][0]++;
                    coverage_gateway[0][window][1]++;
                end
                for (int response = 2; response <= 3; response++) begin
                    u_ddr.write_response = 2'(response);
                    gateway_write('h8000a000+32'(response*32), 3, 3, 2'(response));
                    u_ddr.write_response = 0;
                    u_ddr.read_response = 2'(response);
                    gateway_read('hc000b000+32'(response*32), 3, 3, 2'(response));
                    u_ddr.read_response = 0;
                end
                require_grants(4);
            end
            102: begin
                for (int window = 0; window < 2; window++)
                    for (int size = 0; size <= 3; size++)
                        for (int offset = 0; offset < 32; offset += 1 << size) begin
                            window_addr = (window == 0 ? 32'h80003000 : 32'hc0003400)+32'(offset);
                            gateway_write(window_addr, size, 0);
                            gateway_read(window_addr, size, 0);
                            require_grants(2);
                            coverage_size[size][offset] = 1;
                            coverage_gateway[1][window][0]++;
                            coverage_gateway[1][window][1]++;
                        end
            end
            103: begin
                before_grants = u_schedule.grants.size();
                for (int j = 0; j < 3; j++) begin
                    gateway_write('h80004000, 3, j == 0 ? 1 : j == 1 ? 2 : 7, 2);
                    gateway_read('h80004000, 3, j == 0 ? 1 : j == 1 ? 2 : 7, 2);
                    coverage_illegal_gw[j]++;
                end
                gateway_write('h80004001, 3, 0, 2);
                gateway_read('h80004001, 3, 0, 2);
                coverage_illegal_gw[3]++;
                gateway_write('hc0004000, 3, 3, 2, 2);
                gateway_read('hc0004000, 3, 3, 2, 2);
                coverage_illegal_gw[4]++;
                gateway_write('h80004000, 4, 0, 2);
                gateway_read('h80004000, 4, 0, 2);
                coverage_illegal_gw[5]++;
                gateway_write('h80004000, 2, 3, 2);
                gateway_read('h80004000, 2, 3, 2);
                coverage_illegal_gw[6]++;
                gateway_write('h80004008, 3, 3, 2);
                gateway_read('h80004008, 3, 3, 2);
                coverage_illegal_gw[7]++;
                gateway_write('h80004000, 3, 0, 2, 0);
                gateway_read('h80004000, 3, 0, 2, 0);
                coverage_illegal_gw[8]++;
                gateway_write('h80004000, 3, 0, 2, 3);
                gateway_read('h80004000, 3, 0, 2, 3);
                coverage_illegal_gw[9]++;
                eq("illegal gateway not forwarded", before_grants, u_schedule.grants.size());
            end
            104: begin
                gateway_overlap_read();
                gateway_overlap_write();
                require_grants(4);
                u_gateway.response_stall = 23;
                fork
                    begin
                        for (int k = 0; k < 12; k++)
                            gateway_write('h80005000+32'(k*32), 3, 3);
                    end
                    begin
                        for (int k = 0; k < 12; k++)
                            gateway_read('hc0006000+32'(k*32), 3, 3);
                    end
                join
                require_grants(24);
                truth("gateway one read in flight", u_schedule.max_read[2] <= 1);
                truth("gateway one write in flight", u_schedule.max_write[2] <= 1);
            end
            105: begin
                for (int ratio = 0; ratio < 3; ratio++) begin
                    sys_half = ratio == 0 ? 3.333ns : ratio == 1 ? 4ns : 6.5ns;
                    for (int k = 0; k < 30; k++) begin
                        window_addr = (k[0] ? 32'h80008000 : 32'hc0008000)+
                                      32'((random_next()%128)*32);
                        gateway_write(window_addr, 3, 3);
                        gateway_read(window_addr, 3, 3);
                    end
                    require_grants(60);
                end
            end
            default: $fatal(1, "FAIL unimplemented gateway test=%0d time=%0t", test, $time);
        endcase
    endtask

    task automatic test_xbar(input int test);
        bit [31:0] value;
        int start;
        int elapsed;
        case (test)
            206: begin
                u_ddr.t_hit = 150;
                u_ddr.t_b = 100;

                for (int port = 0; port < 5; port++) begin
                    if (port == 2) continue;
                    for (int k = 0; k < read_limit[port]; k++)
                        send_read(port, 32'(port*65536+k*512));
                    wait_port(port, read_limit[port], 0);
                    eq("per-port RD cap reached", read_limit[port], u_schedule.max_read[port]);
                end
                for (int port = 3; port < 5; port++) begin
                    if (port == 2) continue;
                    for (int k = 0; k < write_limit[port]; k++)
                        send_write(port, 'ha0000+32'(port*65536+k*512));
                    wait_port(port, read_limit[port], write_limit[port]);
                    eq("per-port WR cap reached", write_limit[port], u_schedule.max_write[port]);
                end
                for (int k = 0; k < 16; k++) begin
                    send_read(0, 32'((k%8)*512));
                    send_read(1, 'h10000+32'((k%8)*512));
                    send_read(3, 'h20000+32'((k%8)*512));
                    send_write(3, 'h30000+32'((k%8)*512));
                    send_read(4, 'h80000+32'((k%8)*512));
                    send_write(4, 'h90000+32'((k%8)*512));
                end
                wait (u_schedule.outstanding == 8);
                wait_port(0, 20, 0);
                wait_port(1, 17, 0);
                wait_port(3, 20, 18);
                wait_port(4, 18, 18);
                eq("global cap reached", 8, u_schedule.max_outstanding);
                require_grants(111);
            end
            207: begin
                g_port[0].u_master.r_on = 0;
                g_port[3].u_master.r_on = 0;
                g_port[4].u_master.r_on = 0;

                for (int k = 0; k < 20; k++) begin
                    send_read(0, 32'((k%8)*512));
                    send_read(3, 'h10000+32'((k%8)*512));
                    send_read(4, 'h40000+32'((k%8)*512));
                end
                drain(2000);
                eq("read credit exhausted", 128, max_credit);
                start = u_schedule.grants.size();
                drain(200);
                eq("no grant without credit", start, u_schedule.grants.size());
                g_port[0].u_master.r_on = 1;
                g_port[3].u_master.r_on = 1;
                g_port[4].u_master.r_on = 1;
                wait_port(0, 20, 0);
                wait_port(3, 20, 0);
                wait_port(4, 20, 0);
                drain();
                eq("all credits released", 0, credit_reserved);
                require_grants(60);
            end
            208: begin
                g_port[3].u_master.data_delay = 70;
                g_port[3].u_master.data_gap = 3;
                send_write(3, 'h10000);
                send_read(0, 'h20000);
                drain(65);
                eq("late W excludes AW", 0, u_schedule.transactions[3]);
                check_w_contiguous = 1;
                wait_port(3, 0, 1);
                wait_port(0, 1, 0);
                check_w_contiguous = 0;
                require_grants(2);
            end
            209: begin
                wr(0, 'h00c, 0);
                g_port[3].u_master.expected_resp = 2;
                for (int kind = 0; kind < 2; kind++)
                    for (int direction = 0; direction < 2; direction++) begin
                        start = u_schedule.grants.size();
                        if (direction == 0) begin
                            send_read(3, kind == 0 ? 'hfe0 : 'h1001, kind == 0 ? 1 : 0);
                            wait_port(3, kind+1, kind);
                        end else begin
                            send_write(3, kind == 0 ? 'hfe0 : 'h1001, kind == 0 ? 1 : 0);
                            wait_port(3, kind+1, kind+1);
                        end
                        eq("illegal request not forwarded", start, u_schedule.grants.size());
                        rd_eq(0, 'h120, 3);
                        rd_eq(0, 'h124, kind == 0 ? 'hfe0 : 'h1001);
                        rd_eq(0, 'h128, kind == 0 ? 1 : 4);
                        eq("MEM_XBAR masked IRQ", 0, int'(irq));
                        wr(0, 'h00c, 2);
                        truth("MEM_XBAR IRQ", irq);
                        wr(0, 'h010, 2);
                        rd_eq(0, 'h128, 0);
                        eq("IRQ cleared", 0, int'(irq));
                        wr(0, 'h00c, 0);
                        coverage_violation[kind][direction] = 1;
                    end
                g_port[3].u_master.expected_resp = 0;
                send_write(3, 'h20000, 0);
                wait_port(3, 2, 3);
                send_read(3, 'h20000, 0);
                wait_port(3, 3, 3);
                require_grants(2);
            end
            211: begin
                rd_eq(0, 0, 'h00080001);
                for (int offset = 'h100; offset <= 'h110; offset += 4) begin
                    wr(0, 12'(offset), '1);
                    rd_eq(0, 12'(offset), 0);
                end
                for (int offset = 'h200; offset <= 'h508; offset += 4) begin
                    wr(0, 12'(offset), '1);
                    rd_eq(0, 12'(offset), 0);
                end
                for (int k = 0; k < 6; k++) send_read(3, 32'(k*512));
                wait_port(3, 6, 0);
                require_grants(6);
            end
            212: begin
                g_port[0].u_master.r_random = 1;
                g_port[0].u_master.b_random = 1;
                g_port[0].u_master.urgent_random = 1;
                g_port[0].u_master.seed_random(32'(seed*17+0));
                g_port[1].u_master.r_random = 1;
                g_port[1].u_master.b_random = 1;
                g_port[1].u_master.urgent_random = 1;
                g_port[1].u_master.seed_random(32'(seed*17+1));
                g_port[3].u_master.r_random = 1;
                g_port[3].u_master.b_random = 1;
                g_port[3].u_master.urgent_random = 1;
                g_port[3].u_master.seed_random(32'(seed*17+3));
                g_port[4].u_master.r_random = 1;
                g_port[4].u_master.b_random = 1;
                g_port[4].u_master.urgent_random = 1;
                g_port[4].u_master.seed_random(32'(seed*17+6));
                g_port[0].u_master.r_period = 13;
                g_port[0].u_master.r_on = 3;
                g_port[0].u_master.urgent_enable = 1;
                g_port[0].u_master.urgent_period = 17;
                g_port[0].u_master.urgent_on = 5;
                g_port[1].u_master.r_period = 13;
                g_port[1].u_master.r_on = 3;
                g_port[1].u_master.b_period = 11;
                g_port[1].u_master.b_on = 2;
                g_port[1].u_master.urgent_enable = 1;
                g_port[1].u_master.urgent_period = 19;
                g_port[1].u_master.urgent_on = 6;
                g_port[3].u_master.r_period = 7;
                g_port[3].u_master.r_on = 2;
                g_port[4].u_master.r_period = 5;
                g_port[4].u_master.r_on = 2;
                fork
                    begin
                        for (int k = 0; k < 24; k++) begin
                            gateway_write('h80070000+32'(k*32), 3, 3);
                            gateway_read('hc0070000+32'(k*32), 3, 3);
                        end
                    end
                    begin
                        for (int k = 0; k < 48; k++) begin
                            send_read(0, 32'(k*512), int'(random_next()%16));
                            send_read(1, 'h60000+32'(k*512),
                                int'(random_next()%16), 1'(k));
                            send_write(3, 'h20000+32'(k*512), int'(random_next()%16), 1'(k), 1);
                            send_write(4, 'h50000+32'(k*512), int'(random_next()%16), 1'(k), 1);
                        end
                        wait_port(1, 48, 0);
                        wait_port(3, 0, 48);
                        wait_port(4, 0, 48);
                        for (int k = 0; k < 48; k++) begin
                            send_read(3, 'h20000+32'(k*512), 15, 1'(k));
                            send_read(4, 'h50000+32'(k*512), 15, 1'(k));
                        end
                        wait_port(0, 48, 0);
                        wait_port(3, 48, 48);
                        wait_port(4, 48, 48);
                    end
                join
                require_grants(336);
            end
            213: begin
                rd_eq(0, 'h220, 0);
                rd_eq(0, 'h224, 0);
                g_port[1].u_master.r_on = 0;
                for (int k = 0; k < 4; k++) send_read(1, 'h10000, 15, 1'(k));
                drain(200);
                eq("P1 buffered read retains port slot", 1,
                    u_schedule_reference.rd_outstanding[1]);
                eq("P1 read cap", 1, u_schedule.max_read[1]);
                eq("P1 R backpressure", 0, local_reads[1]);
                g_port[1].u_master.r_on = 1;
                wait_port(1, 4, 0);
                require_grants(4);
                g_port[1].u_master.r_random = 1;
                g_port[1].u_master.r_period = 11;
                g_port[1].u_master.r_on = 3;
                for (int k = 0; k < 32; k++)
                    send_read(1, 'h10000, int'(random_next()%16), 1'(k));
                wait_port(1, 36, 0);
                require_grants(32);
                eq("P1 protocol errors", 0, local_errors[1]);
                eq("P1 reference checked reads", 36, local_reads[1]);
            end
            default: $fatal(1, "FAIL unimplemented MX test=%0d time=%0t", test, $time);
        endcase
    endtask

    // gpu-soc-testplan ST-03: all five sources stay queued under random delays.
    bit stress_active = 0;
    bit [31:0] delay_state = 32'h10ab35ce;
    always @(negedge clk_mem) begin
        if (stress_active) begin
            delay_state = {delay_state[30:0],
                delay_state[31]^delay_state[21]^delay_state[1]^delay_state[0]};
            u_ddr.t_hit = 2+int'(delay_state[3:0]);
            u_ddr.t_miss = 8+int'(delay_state[7:4]);
            u_ddr.t_b = 1+int'(delay_state[11:8]);
        end
    end
    // ST-03 consumption: 720p60 has 750 total rows, hence 45000 rows/s.
    // Each X2 active row consumes 40 beats; AUD consumes one 32-bit frame at 48kHz.
    // Integer phase accumulators preserve fractional clk_mem periods exactly.
    always @(posedge clk_mem) begin
        if (stress_active) begin
            if (p[0].rvalid && p[0].rready) begin
                rt_level[0]++;
                rt_reserved[0]--;
            end
            if (p[1].rvalid && p[1].rready) begin
                rt_level[1] += 8;
                rt_reserved[1] -= 8;
            end
            if (rt_consume) begin
                row_phase += 45000;
                sample_phase += 48000;
                if (row_phase >= 125000000) begin
                    row_phase -= 125000000;
                    if (rt_level[0] < 40)
                        $fatal(1,"FAIL ST-03 DISP underflow row=%0d level=%0d time=%0t",
                            rt_rows, rt_level[0], $time);
                    rt_level[0] -= 40;
                    rt_rows++;
                    if (rt_rows%180 == 0) begin
                        $display("ST-03 rows=%0d samples=%0d FIFO=%0d/%0d time=%0t",
                            rt_rows,rt_samples,rt_level[0],rt_level[1],$time);
                        $fflush();
                    end
                end
                if (sample_phase >= 125000000) begin
                    sample_phase -= 125000000;
                    if (rt_level[1] == 0)
                        $fatal(1,"FAIL ST-03 AUD underrun sample=%0d time=%0t",rt_samples,$time);
                    rt_level[1]--;
                    rt_samples++;
                end
                for (int port = 0; port < 2; port++)
                    if (rt_level[port] < rt_min[port]) rt_min[port] = rt_level[port];
            end
            for (int port = 0; port < 2; port++)
                if (rt_level[port]+rt_reserved[port] > 512)
                    $fatal(1,"FAIL ST-03 FIFO reservation overflow P%0d",port);
        end
    end
    task automatic test_stress();
        int reads0;
        int reads1;
        int gpu_count;
        int eth_count;
        int cpu_count;
        int total_grants;
        reads0 = 0;
        reads1 = 0;
        gpu_count = 0;
        eth_count = 0;
        cpu_count = 0;
        rt_level[0] = 0;
        rt_level[1] = 0;
        rt_reserved[0] = 0;
        rt_reserved[1] = 0;
        rt_min[0] = 512;
        rt_min[1] = 512;
        rt_rows = 0;
        rt_samples = 0;
        row_phase = 0;
        sample_phase = 0;
        stress_active = 1;
        rt_running = 1;
        g_port[0].u_master.r_random = 1;
        g_port[0].u_master.r_period = 7;
        g_port[0].u_master.r_on = 3;
        g_port[1].u_master.r_random = 1;
        g_port[1].u_master.r_period = 7;
        g_port[1].u_master.r_on = 3;
        g_port[3].u_master.r_random = 1;
        g_port[3].u_master.r_period = 7;
        g_port[3].u_master.r_on = 3;
        g_port[3].u_master.b_random = 1;
        g_port[3].u_master.b_period = 9;
        g_port[3].u_master.b_on = 3;
        g_port[4].u_master.r_random = 1;
        g_port[4].u_master.r_period = 7;
        g_port[4].u_master.r_on = 3;
        g_port[4].u_master.b_random = 1;
        g_port[4].u_master.b_period = 9;
        g_port[4].u_master.b_on = 3;
        g_port[0].u_master.seed_random(32'(seed*17));
        g_port[1].u_master.seed_random(32'(seed*17+1));
        g_port[3].u_master.seed_random(32'(seed*17+3));
        g_port[4].u_master.seed_random(32'(seed*17+4));
        fork
            begin
                while (rt_running) begin
                    @(negedge clk_mem);
                    if (rt_level[0]+rt_reserved[0] <= 472) begin
                        rt_reserved[0] += 40;
                        send_read(0, 32'((reads0%32)*512), 15, 1'(reads0)); reads0++;
                        send_read(0, 32'((reads0%32)*512), 15, 1'(reads0)); reads0++;
                        send_read(0, 32'((reads0%32)*512), 7, 1'(reads0)); reads0++;
                    end
                end
            end
            begin
                while (rt_running) begin
                    @(negedge clk_mem);
                    if (rt_level[1]+rt_reserved[1] <= 384) begin
                        rt_reserved[1] += 128;
                        send_read(1, 'h10000+32'((reads1%32)*512), 15, 1'(reads1));
                        reads1++;
                    end
                end
            end
            begin
                // Prime actual FIFO contents before starting screen/audio consumption.
                wait (rt_level[0] >= 80 && rt_level[1] >= 128);
                @(negedge clk_mem);
                rt_consume = 1;
                $display("ST-03 primed FIFO=%0d beats/%0d samples time=%0t",
                    rt_level[0],rt_level[1],$time);
                $fflush();
                wait (rt_rows == 720);
                @(negedge clk_mem);
                rt_consume = 0;
                rt_running = 0;
            end
            begin
                while (rt_running) begin
                    gateway_write('h80070000+32'((cpu_count%32)*32), 3, 3);
                    gateway_read('hc0070000+32'((cpu_count%32)*32), 3, 3);
                    cpu_count++;
                end
            end
            begin
                while (rt_running) begin
                    if (gpu_count-local_reads[3] < 16 && gpu_count-local_writes[3] < 16) begin
                        send_write(3, 'h30000+32'((gpu_count%32)*512), 15, 1'(gpu_count));
                        send_read(3, 'h40000+32'((gpu_count%32)*512), 15, 1'(gpu_count));
                        gpu_count++;
                    end
                    @(negedge clk_mem);
                end
            end
            begin
                while (rt_running) begin
                    if (eth_count-local_reads[4] < 16 && eth_count-local_writes[4] < 16) begin
                        send_write(4, 'h50000+32'((eth_count%32)*512), 15, 1'(eth_count));
                        send_read(4, 'h60000+32'((eth_count%32)*512), 15, 1'(eth_count));
                        eth_count++;
                    end
                    @(negedge clk_mem);
                end
            end
        join
        wait_port(0, reads0, 0);
        wait_port(1, reads1, 0);
        wait_port(3, gpu_count, gpu_count);
        wait_port(4, eth_count, eth_count);
        drain();
        stress_active = 0;
        total_grants = reads0+reads1+2*(cpu_count+gpu_count+eth_count);
        require_grants(total_grants);
        truth("ST-03 P0 urgent grants", u_schedule_reference.urg[0] > 0);
        truth("ST-03 P1 urgent grants", u_schedule_reference.urg[1] > 0);
        truth("ST-03 CPU progresses", cpu_count > 0);
        truth("ST-03 GPU progresses", gpu_count > 0);
        truth("ST-03 ETH progresses", eth_count > 0);
        eq("ST-03 P0 protocol errors", 0, local_errors[0]);
        eq("ST-03 P1 protocol errors", 0, local_errors[1]);
        eq("ST-03 GPU protocol errors", 0, local_errors[3]);
        eq("ST-03 ETH protocol errors", 0, local_errors[4]);
        $display("ST-03 grants=%0d rows=%0d samples=%0d min_fifo_beats=%0d min_samples=%0d",
            total_grants,rt_rows,rt_samples,rt_min[0],rt_min[1]);
    endtask

    // BW-01: one testbench master keeps same-row sequential read bursts queued.
    task automatic test_bandwidth();
        int start_cycle;
        int elapsed_cycles;
        int beats;
        start_cycle = cycle;
        for (int k = 0; k < 4096; k++)
            send_read(0, 32'((k%8)*512), 15, 1'(k));
        wait_port(0, 4096, 0);
        elapsed_cycles = cycle-start_cycle;
        beats = g_port[0].u_master.r_beats;
        eq("BW-01 returned beats", 4096*16, beats);
        truth("BW-01 bandwidth >=90%", 64'(beats)*100 >= 64'(elapsed_cycles)*90);
        $display("BW-01 beats=%0d cycles=%0d utilization=%0.3f%%",
                 beats, elapsed_cycles, 100.0*real'(beats)/real'(elapsed_cycles));
        require_grants(4096);
    endtask

    task automatic test_top();
        rd_eq(0, 0, 'h00080001);
        send_read(0, 0);
        for (int port = 3; port < 5; port++) begin
            send_write(port, 32'(port*65536));
            wait_port(port, 0, 1);
            send_read(port, 32'(port*65536));
            wait_port(port, 1, 1);
        end
        wait_port(0, 1, 0);
        send_read(1, 'h10000, 15, 1);
        wait_port(1, 1, 0);
        gateway_write('h80070000, 3, 3);
        gateway_read('hc0070000, 3, 3);
        require_grants(8);
        wr(0, 'h00c, 2);
        g_port[3].u_master.expected_resp = 2;
        send_read(3, 'h80001, 0);
        wait_port(3, 2, 1);
        truth("top IRQ connected", irq);
    endtask

    task automatic report_coverage();
        for (int kind = 0; kind < 2; kind++)
            for (int window = 0; window < 2; window++)
                for (int direction = 0; direction < 2; direction++)
                    $display("COVER GW legal=%0d window=%0d dir=%0d hits=%0d",
                             kind, window, direction, coverage_gateway[kind][window][direction]);
        for (int size = 0; size < 4; size++)
            for (int offset = 0; offset < 32; offset += 1 << size)
                $display("COVER GW size=%0d offset=%0d hit=%0b", size, offset,
                         coverage_size[size][offset]);
        for (int j = 0; j < 10; j++)
            $display("COVER GW illegal=%0d hits=%0d", j, coverage_illegal_gw[j]);
        for (int j = 0; j < 3; j++)
            $display("COVER schedule rule=%0d hits=%0d", j+1, u_schedule_reference.rule_hits[j]);
        $display("COVER flow global_peak=%0d credit_peak=%0d credit_full=%0b",
                 u_schedule.max_outstanding, max_credit, coverage_credit);
        for (int j = 0; j < 5; j++)
            $display("COVER flow port=%0d rd_peak=%0d wr_peak=%0d", j,
                     u_schedule.max_read[j], u_schedule.max_write[j]);
        for (int kind = 0; kind < 2; kind++)
            for (int direction = 0; direction < 2; direction++)
                $display("COVER violation kind=%0d dir=%0d hit=%0b", kind,
                         direction, coverage_violation[kind][direction]);
    endtask

    initial begin
        int max_cycles;
        max_cycles = 2500000;
        void'($value$plusargs("MAX_CYCLES=%d", max_cycles));
        repeat (max_cycles) @(posedge clk_mem);
        $fatal(1, "FAIL MB timeout case=%0d seed=%0d expected=completion actual=stalled time=%0t",
               selected_case, seed, $time);
    end

    initial begin
        void'($value$plusargs("CASE=%d", selected_case));
        void'($value$plusargs("SEED=%d", seed));
        random_state = 32'(seed);
        u_gateway.idle();
        gw_count = 0;
        apb_paddr = '0;
        apb_psel = '0;
        apb_penable = '0;
        apb_pwrite = '0;
        apb_pwdata = '0;
        apb_pstrb = '0;
        repeat (5) @(negedge clk_mem);
        eq("reset AR idle", 0, int'(ddr.arvalid));
        eq("reset AW idle", 0, int'(ddr.awvalid));
        eq("reset W idle", 0, int'(ddr.wvalid));
        rst_mem_n = 1;
        repeat (3) @(negedge clk_sys);
        rst_sys_n = 1;
        drain(5);
        grant_start = u_schedule.grants.size();
        // Distinct address-derived bytes expose read misrouting even before any write.
        for (int port = 0; port < 5; port++)
            preload(32'(port*65536), 32768, 'habcd0000);
        $display("MB START CASE=%0d SEED=%0d time=%0t", selected_case, seed, $time);
        if (CASE == 0) begin
            if (selected_case >= 101 && selected_case <= 105) test_gateway(selected_case);
            else if (selected_case >= 201 && selected_case <= 213) test_xbar(selected_case);
            else if (selected_case == 214) test_stress();
            else if (selected_case == 601) test_bandwidth();
            else if (selected_case == 501) test_top();
            else $fatal(1, "FAIL unknown CASE=%0d time=%0t", selected_case, $time);
        end else if (CASE >= 101 && CASE <= 105) test_gateway(CASE);
        else if (CASE >= 201 && CASE <= 213) test_xbar(CASE);
        else if (CASE == 214) test_stress();
        else if (CASE == 601) test_bandwidth();
        else if (CASE == 501) test_top();
        else $fatal(1, "FAIL unknown CASE=%0d time=%0t", CASE, $time);
        eq("DDR protocol errors", 0, checker_errors);
        report_coverage();
        $display("PASS mem_subsys CASE=%0d SEED=%0d checked_beats=%0d writes=%0d time=%0t",
                 selected_case, seed, checked_beats, committed_writes, $time);
        $finish;
    end
endmodule
