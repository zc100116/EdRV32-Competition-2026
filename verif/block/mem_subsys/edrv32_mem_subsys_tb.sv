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
    edrv32_axi256_if p[7]();
    edrv32_axi256_if #(.ID_WIDTH(4)) ddr();
    logic [6:0] urgent;
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
    int local_errors[7];
    int local_reads[7];
    int local_writes[7];
    int total_limit = 8;
    int read_limit[7] = '{4,2,1,4,2,2,2};
    int write_limit[7] = '{0,4,1,2,2,2,2};
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
    bit coverage_snapshot;
    bit coverage_clear;
    bit [31:0] random_state;

    edrv32_axi64_master u_gateway (
        .clk_i(clk_sys),
        .rst_n_i(rst_sys_n),
        .bus(gw)
    );
    for (genvar n = 0; n < 7; n++) begin : g_port
        edrv32_axi256_master #(
            .READ_ONLY(n == 0)
        ) u_master (
            .clk_i(clk_mem),
            .rst_n_i(rst_mem_n),
            .urgent_o(urgent[n]),
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
        .urgent_i({5'b0, u_dut.u_xbar.p1_urgent_i, u_dut.u_xbar.p0_urgent_i}),
        .prepare_i(schedule_phase_w[1]),
        .grant_i(schedule_phase_w[0]),
        .apb_write_i(apb_psel[0] && apb_penable[0] && apb_pready[0] && apb_pwrite[0]),
        .apb_addr_i(apb_paddr[0]),
        .apb_data_i(apb_pwdata[0]),
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
            5: g_port[5].u_master.enqueue_read(addr, len, id);
            6: g_port[6].u_master.enqueue_read(addr, len, id);
            default: $fatal(1, "FAIL send_read expected=P0/P1/P3/P4/P5/P6 actual=%0d time=%0t",
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
            1: g_port[1].u_master.enqueue_write(addr, len, data, strb, id);
            3: g_port[3].u_master.enqueue_write(addr, len, data, strb, id);
            4: g_port[4].u_master.enqueue_write(addr, len, data, strb, id);
            5: g_port[5].u_master.enqueue_write(addr, len, data, strb, id);
            6: g_port[6].u_master.enqueue_write(addr, len, data, strb, id);
            default: $fatal(1, "FAIL send_write expected=P1/P3/P4/P5/P6 actual=%0d time=%0t",
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
            5: g_port[5].u_master.wait_done(nr, nw);
            6: g_port[6].u_master.wait_done(nr, nw);
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

    bit [6:0] upstream_take;
    for (genvar n = 0; n < 7; n++) begin : g_take
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
                for (int j = 0; j < 7; j++)
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
        int before_count[7];
        int before_refills[7];
        int before_completed[7];
        int delivered_total;
        int before_p0_ar_idle;
        int before_p1_aw_idle;
        int before_p0_empty;
        int before_p0_block[6];
        int before_rules[5];
        int before_ddr_read;
        int before_ddr_write;
        int before_rd_sum[7];
        int before_wr_sum[7];
        int before_rd_full[7];
        int before_wr_full[7];
        int before_ideal_credit_full[7];
        int before_ring_credit_full[7];
        int before_ring_slot_full[7];
        int before_global_full[7];
        int before_r_not_ready[7];
        int before_r_stall[7];

        int weights[7] = '{4,4,0,3,2,2,1};
        int total;
        real share;
        real expected;
        case (test)
            201: begin
                wr(0, 'h100, 1);
                total_limit = 1;
                wr(0, 'h208, 0);
                g_port[0].u_master.urgent_enable = 1;
                for (int k = 0; k < 16; k++) begin
                    send_read(0, 32'(k*512));
                    send_read(3, 'h10000+32'(k*512));
                end
                wait_port(0, 16, 0);
                wait_port(3, 16, 0);
                require_grants(32);
                for (int k = 0; k < 8; k++)
                    eq("urgent wins", 0, u_schedule.grants[k].port);
                truth("URG_MAX permits competitor", u_schedule.grants[8].port != 0);
            end
            202: begin
                // Measure token rate without the independent starvation bypass.
                wr(0, 'h108, 65535);
                wr(0, 'h24c, 4);
                for (int k = 0; k < 5000; k++) send_read(3, 32'((k%8)*512));
                start = cycle;
                for (int k = 0; k < 1000; k++) gateway_read('h80010000, 3, 3);
                elapsed = cycle-start;
                share = real'(u_schedule.beats[2]-32)/real'(elapsed);
                expected = 4.0/256.0;
                truth("P2 token rate <=2% error", share >= expected*0.98 && share <= expected*1.02);
                truth("P2 throttled", elapsed >= (1000-32)*64);
                truth("P2 grants present", u_schedule.transactions[2] == 1000);
                start = cycle;
                for (int k = 0; k < 500; k++) send_read(6, 'h30000+32'((k%8)*512));
                wait_port(6, 500, 0);
                elapsed = cycle-start;
                share = real'(u_schedule.beats[6]-32)/real'(elapsed);
                expected = 13.0/256.0;
                truth("P6 token rate <=2% relative error",
                      share >= expected*0.98 && share <= expected*1.02);
                truth("token insufficiency observed", u_schedule_reference.token_skips != 0);
                wait_port(3, 5000, 0);
                require_grants(6500);
            end
            203: begin
                wr(0, 'h108, 32);
                wr(0, 'h2a8, 0);
                wr(0, 'h100, 1);
                total_limit = 1;
                for (int k = 0; k < 64; k++) send_read(3, 32'((k%8)*512));
                start = cycle;
                send_read(5, 'h20000);
                wait_port(5, 1, 0);
                for (int k = 0; k < u_schedule.grants.size(); k++)
                    if (u_schedule.grants[k].port == 5) begin
                        truth("starve threshold reached", u_schedule.grants[k].cycle-start > 32);
                        truth("starve bound", u_schedule.grants[k].cycle-start <= 32+48);
                    end
                eq("zero-weight port served", 1, u_schedule.transactions[5]);
            end
            204: begin
                // Judge all ready read ports, including P1, at OUTST_TOTAL=1.
                wr(0, 'h100, 1);
                total_limit = 1;
                wr(0, 'h108, 65535);
                rd_eq(0, 'h108, 65535);
                wr(0, 'h2cc, 256);
                for (int k = 0; k < 4096; k++) begin
                    send_read(0, 32'((k%8)*512));
                    send_read(1, 'h10000+32'((k%8)*512));
                    send_read(3, 'h20000+32'((k%8)*512));
                    send_read(4, 'h30000+32'((k%8)*512));
                    send_read(5, 'h40000+32'((k%8)*512));
                    send_read(6, 'h50000+32'((k%8)*512));
                end
                for (int phase = 0; phase < 2; phase++) begin
                    if (phase == 1) begin
                        total_limit = 8;
                        wr(0, 'h100, 8);
                    end
                    $display("MX04 window TOTAL=%0d judge_reads=%0b", total_limit, phase == 0);
                    drain(1000);
                    truth("DRR grants present", u_schedule.grants.size() != 0);
                    for (int j = 0; j < 7; j++) begin
                        before_count[j] = u_schedule.beats[j];
                        before_refills[j] = u_schedule_reference.refill_count[j];
                        before_rd_sum[j] = u_schedule_reference.flow_rd_sum[j];
                        before_wr_sum[j] = u_schedule_reference.flow_wr_sum[j];
                        before_rd_full[j] = u_schedule_reference.flow_rd_full[j];
                        before_wr_full[j] = u_schedule_reference.flow_wr_full[j];
                        before_ideal_credit_full[j] =
                            u_schedule_reference.flow_ideal_credit_full[j];
                        before_ring_credit_full[j] = u_schedule_reference.flow_ring_credit_full[j];
                        before_ring_slot_full[j] = u_schedule_reference.flow_ring_slot_full[j];
                        before_global_full[j] = u_schedule_reference.flow_global_full[j];
                        before_r_not_ready[j] = u_schedule_reference.flow_r_not_ready[j];
                        before_r_stall[j] = u_schedule_reference.flow_r_stall[j];
                        if (j != 2) before_completed[j] = local_reads[j]+local_writes[j];
                    end
                    before_p0_ar_idle = u_schedule_reference.flow_p0_ar_idle;
                    before_p1_aw_idle = u_schedule_reference.flow_p1_aw_idle;
                    before_p0_empty = u_schedule_reference.flow_p0_empty;
                    for (int j = 0; j < 6; j++)
                        before_p0_block[j] = u_schedule_reference.flow_p0_block[j];
                    for (int j = 0; j < 5; j++)
                        before_rules[j] = u_schedule_reference.rule_hits[j];
                    before_ddr_read = u_ddr.read_data_beats;
                    before_ddr_write = u_ddr.write_data_beats;
                    ddr_latency_count = 0;
                    ddr_latency_sum = 0;
                    ddr_latency_min = 32'h7fffffff;
                    ddr_latency_max = 0;
                    start = cycle;
                    drain(50000);
                    elapsed = cycle-start;
                    $display("FLOW source p0_ar_idle=%0d p1_aw_idle=%0d p0_head_empty=%0d",
                        u_schedule_reference.flow_p0_ar_idle-before_p0_ar_idle,
                        u_schedule_reference.flow_p1_aw_idle-before_p1_aw_idle,
                        u_schedule_reference.flow_p0_empty-before_p0_empty);
                    $display("FLOW P0: 0=global 1=port 2=ring 3=slot 4=direction 5=deficit");
                    for (int j = 0; j < 6; j++)
                        $display("FLOW P0 exclusive_reason=%0d cycles=%0d", j,
                            u_schedule_reference.flow_p0_block[j]-before_p0_block[j]);
                    for (int j = 0; j < 4; j++)
                        $display("FLOW rule=%0d grants=%0d", j+1,
                            u_schedule_reference.rule_hits[j]-before_rules[j]);
                    $display("FLOW direction_switches=%0d",
                        u_schedule_reference.rule_hits[4]-before_rules[4]);
                    $display("FLOW DDR read=%0d write=%0d cyc=%0d busy=%f latency=%0d/%f/%0d",
                        u_ddr.read_data_beats-before_ddr_read,
                        u_ddr.write_data_beats-before_ddr_write, elapsed,
                        real'(u_ddr.read_data_beats-before_ddr_read+
                            u_ddr.write_data_beats-before_ddr_write)/real'(elapsed),
                        ddr_latency_min, real'(ddr_latency_sum)/real'(ddr_latency_count),
                        ddr_latency_max);
                    $display("FLOW DDR config hit=%0d miss=%0d turn=%0d refi=%0d rfc=%0d b=%0d",
                        u_ddr.t_hit, u_ddr.t_miss, u_ddr.t_turn, u_ddr.t_refi,
                        u_ddr.t_rfc, u_ddr.t_b);
                    total = 0;
                    for (int j = 0; j < 7; j++) total += u_schedule.beats[j]-before_count[j];
                    truth("DRR grants present", total > 10000);
                    delivered_total = 0;
                    for (int j = 0; j < 7; j++)
                        if (j != 2)
                            delivered_total +=
                                (local_reads[j]+local_writes[j]-before_completed[j])*16;
                    for (int j = 0; j < 7; j++)
                        if (j != 2)
                            $display("DRR port=%0d beats=%0d share=%f rounds=%0d deficit=%0d", j,
                                u_schedule.beats[j]-before_count[j],
                                real'(u_schedule.beats[j]-before_count[j])/real'(total),
                                u_schedule_reference.refill_count[j]-before_refills[j],
                                u_schedule_reference.deficit[j]);
                    for (int j = 0; j < 7; j++)
                        if (j != 2)
                            $display("DRR delivered port=%0d beats=%0d share=%f", j,
                                (local_reads[j]+local_writes[j]-before_completed[j])*16,
                                real'((local_reads[j]+local_writes[j]-before_completed[j])*16)/
                                real'(delivered_total));
                    for (int j = 0; j < 7; j++) begin
                        $display("FLOW occ p=%0d cyc=%0d rd=%f/%0d wr=%f/%0d", j, elapsed,
                            real'(u_schedule_reference.flow_rd_sum[j]-before_rd_sum[j])/
                                real'(elapsed),
                            u_schedule_reference.flow_rd_peak[j],
                            real'(u_schedule_reference.flow_wr_sum[j]-before_wr_sum[j])/
                                real'(elapsed),
                            u_schedule_reference.flow_wr_peak[j]);
                        $display("FLOW caps p=%0d rd_full=%0d wr_full=%0d global_full=%0d", j,
                            u_schedule_reference.flow_rd_full[j]-before_rd_full[j],
                            u_schedule_reference.flow_wr_full[j]-before_wr_full[j],
                            u_schedule_reference.flow_global_full[j]-before_global_full[j]);
                        $display("FLOW credit p=%0d ideal=%0d ring=%0d slots=%0d", j,
                            u_schedule_reference.flow_ideal_credit_full[j]-
                                before_ideal_credit_full[j],
                            u_schedule_reference.flow_ring_credit_full[j]-
                                before_ring_credit_full[j],
                            u_schedule_reference.flow_ring_slot_full[j]-before_ring_slot_full[j]);
                        $display("FLOW ready p=%0d r_not_ready=%0d r_stall=%0d", j,
                            u_schedule_reference.flow_r_not_ready[j]-before_r_not_ready[j],
                            u_schedule_reference.flow_r_stall[j]-before_r_stall[j]);
                    end
                    for (int j = 0; j < 7; j++)
                        if (phase == 0 && j != 2) begin
                            share = real'(u_schedule.beats[j]-before_count[j])/real'(total);
                            expected = real'(weights[j])/16.0;
                            if (share < expected-0.05 || share > expected+0.05)
                                $fatal(1, "FAIL DRR p=%0d expected=%f actual=%f time=%0t",
                                       j, expected, share, $time);
                            // Verify the allocated share also reaches the ready source ports.
                            share = real'((local_reads[j]+local_writes[j]-before_completed[j])*16)/
                                    real'(delivered_total);
                            if (share < expected-0.05 || share > expected+0.05)
                                $fatal(1, "FAIL DRR delivered p=%0d expected=%f actual=%f time=%0t",
                                    j, expected, share, $time);
                        end
                end
            end
            205: begin
                wr(0, 'h100, 1);
                total_limit = 1;
                wr(0, 'h108, 1000000);
                for (int k = 0; k < 64; k++) begin
                    send_read(0, 32'((k%8)*512));
                    send_write(1, 'h10000+32'((k%8)*512));
                end
                do @(negedge clk_mem); while (!(ddr.awvalid && ddr.awready));
                @(negedge clk_mem);
                direction_run = 0;
                last_direction = -1;
                wait_port(0, 60, 0);
                wait_port(1, 0, 60);
                // The reference checks the allowed direction at every grant, including
                // tail draining when only one direction still has eligible work.
                truth("DIR_BATCH contested choices", u_schedule_reference.batch_contests > 0);
                truth("read/write direction switched", u_schedule.direction_switches > 4);
            end
            206: begin
                u_ddr.t_hit = 150;
                u_ddr.t_b = 100;
                wr(0, 'h2cc, 256);
                for (int port = 0; port < 7; port++) begin
                    if (port == 2) continue;
                    for (int k = 0; k < read_limit[port]; k++)
                        send_read(port, 32'(port*65536+k*512));
                    wait_port(port, read_limit[port], 0);
                    eq("per-port RD cap reached", read_limit[port], u_schedule.max_read[port]);
                end
                for (int port = 1; port < 7; port++) begin
                    if (port == 2) continue;
                    for (int k = 0; k < write_limit[port]; k++)
                        send_write(port, 'ha0000+32'(port*65536+k*512));
                    wait_port(port, read_limit[port], write_limit[port]);
                    eq("per-port WR cap reached", write_limit[port], u_schedule.max_write[port]);
                end
                for (int k = 0; k < 16; k++) begin
                    send_read(0, 32'((k%8)*512));
                    send_write(1, 'h10000+32'((k%8)*512));
                    send_read(3, 'h20000+32'((k%8)*512));
                    send_write(3, 'h30000+32'((k%8)*512));
                    send_read(4, 'h40000+32'((k%8)*512));
                    send_write(4, 'h50000+32'((k%8)*512));
                    send_read(5, 'h60000+32'((k%8)*512));
                    send_write(5, 'h70000+32'((k%8)*512));
                    send_read(6, 'h80000+32'((k%8)*512));
                    send_write(6, 'h90000+32'((k%8)*512));
                end
                wait (u_schedule.outstanding == 8);
                wr(0, 'h100, 2);
                total_limit = 2;
                wr(0, 'h260, 1);
                read_limit[3] = 1;
                wait_port(0, 20, 0);
                wait_port(1, 2, 20);
                wait_port(3, 20, 18);
                wait_port(4, 18, 18);
                wait_port(5, 18, 18);
                wait_port(6, 18, 18);
                eq("global cap reached", 8, u_schedule.max_outstanding);
                require_grants(188);
            end
            207: begin
                g_port[0].u_master.r_on = 0;
                g_port[3].u_master.r_on = 0;
                g_port[4].u_master.r_on = 0;
                g_port[5].u_master.r_on = 0;
                g_port[6].u_master.r_on = 0;
                wr(0, 'h2cc, 256);
                for (int k = 0; k < 20; k++) begin
                    send_read(0, 32'((k%8)*512));
                    send_read(3, 'h10000+32'((k%8)*512));
                    send_read(4, 'h20000+32'((k%8)*512));
                    send_read(5, 'h30000+32'((k%8)*512));
                    send_read(6, 'h40000+32'((k%8)*512));
                end
                drain(2000);
                eq("read credit exhausted", 128, max_credit);
                start = u_schedule.grants.size();
                drain(200);
                eq("no grant without credit", start, u_schedule.grants.size());
                g_port[0].u_master.r_on = 1;
                g_port[3].u_master.r_on = 1;
                g_port[4].u_master.r_on = 1;
                g_port[5].u_master.r_on = 1;
                g_port[6].u_master.r_on = 1;
                wait_port(0, 20, 0);
                wait_port(3, 20, 0);
                wait_port(4, 20, 0);
                wait_port(5, 20, 0);
                wait_port(6, 20, 0);
                drain();
                eq("all credits released", 0, credit_reserved);
                require_grants(100);
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
            210: begin
                wr(0, 'h110, 2);
                for (int k = 0; k < 6; k++) begin
                    send_write(3, 'h10000+32'(k*512));
                    send_read(4, 'h20000+32'(k*512));
                end
                wait_port(3, 0, 6);
                wait_port(4, 6, 0);
                drain();
                // Same P5 alternates reads and writes with unequal beat counts.
                for (int k = 0; k < 3; k++) begin
                    send_write(5, 'h30000+32'(k*512), k);
                    wait_port(5, k, k+1);
                    send_read(5, 'h30000+32'(k*512), k+1);
                    wait_port(5, k+1, k+1);
                end
                drain();
                wr(0, 'h110, 3);
                for (int j = 0; j < 7; j++) begin
                    rd_eq(0, 12'('h400+j*32), j == 4 ? 6 : j == 5 ? 3 : 0);
                    rd_eq(0, 12'('h404+j*32), j == 4 ? 96 : j == 5 ? 9 : 0);
                    rd_eq(0, 12'('h414+j*32), j == 3 ? 6 : j == 5 ? 3 : 0);
                    rd_eq(0, 12'('h418+j*32), j == 3 ? 96 : j == 5 ? 6 : 0);
                    rd_eq(0, 12'('h408+j*32), u_schedule_reference.snap_wait_max[j]);
                    rd_eq(0, 12'('h40c+j*32), u_schedule_reference.snap_wait_sum[j]);
                    rd_eq(0, 12'('h410+j*32), u_schedule_reference.snap_urg[j]);
                end
                rd_eq(0, 'h500, u_schedule_reference.snap_switch);
                rd_eq(0, 'h504, u_schedule_reference.snap_busy);
                rd_eq(0, 'h508, u_schedule_reference.snap_window);
                coverage_snapshot = 1;
                wr(0, 'h110, 1);
                for (int j = 0; j < 7; j++) begin
                    rd_eq(0, 12'('h400+j*32), 0);
                    rd_eq(0, 12'('h404+j*32), 0);
                    rd_eq(0, 12'('h414+j*32), 0);
                    rd_eq(0, 12'('h418+j*32), 0);
                    rd_eq(0, 12'('h408+j*32), 0);
                    rd_eq(0, 12'('h40c+j*32), 0);
                    rd_eq(0, 12'('h410+j*32), 0);
                end
                rd(0, 'h508, value);
                eq("WINDOW_CYC exact snapshot", int'(u_schedule_reference.snap_window),
                   int'(value));
                truth("WINDOW_CYC advancing", value != 0);
                coverage_clear = 1;
                require_grants(18);
            end
            211: begin
                rd_eq(0, 0, 'h00080001);
                rd_eq(0, 'h100, 8);
                rd_eq(0, 'h104, 8);
                rd_eq(0, 'h108, 256);
                rd_eq(0, 'h10c, 4);
                for (int j = 0; j < 7; j++) begin
                    rd_eq(0, 12'('h200+j*32), 32'(read_limit[j]));
                    rd_eq(0, 12'('h204+j*32), 32'(write_limit[j]));
                    if (j != 2) rd_eq(0, 12'('h208+j*32), 32'(weights[j]));
                end
                rd_eq(0, 'h24c, 26);
                rd_eq(0, 'h2cc, 13);
                wr(0, 'h114, 'hffffffff);
                rd_eq(0, 'h114, 0);
                wr(0, 'h104, 2);
                wr(0, 'h108, 17);
                wr(0, 'h10c, 1);
                rd_eq(0, 'h104, 2);
                rd_eq(0, 'h108, 17);
                rd_eq(0, 'h10c, 1);
                wr(0, 'h260, 1);
                read_limit[3] = 1;
                for (int k = 0; k < 6; k++) send_read(3, 32'(k*512));
                wait_port(3, 6, 0);
                eq("runtime RD cap", 1, u_schedule.max_read[3]);
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
                g_port[4].u_master.seed_random(32'(seed*17+4));
                g_port[5].u_master.r_random = 1;
                g_port[5].u_master.b_random = 1;
                g_port[5].u_master.urgent_random = 1;
                g_port[5].u_master.seed_random(32'(seed*17+5));
                g_port[6].u_master.r_random = 1;
                g_port[6].u_master.b_random = 1;
                g_port[6].u_master.urgent_random = 1;
                g_port[6].u_master.seed_random(32'(seed*17+6));
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
                g_port[4].u_master.b_period = 9;
                g_port[4].u_master.b_on = 2;
                g_port[5].u_master.r_period = 11;
                g_port[5].u_master.r_on = 1;
                g_port[6].u_master.r_period = 5;
                g_port[6].u_master.r_on = 2;
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
                            send_write(1, 'h10000+32'(k*512), int'(random_next()%16), 1'(k), 1);
                            send_write(3, 'h20000+32'(k*512), int'(random_next()%16), 1'(k), 1);
                            send_write(4, 'h30000+32'(k*512), int'(random_next()%16), 1'(k), 1);
                            send_write(5, 'h40000+32'(k*512), int'(random_next()%16), 1'(k), 1);
                            send_write(6, 'h50000+32'(k*512), int'(random_next()%16), 1'(k), 1);
                        end
                        wait_port(1, 48, 48);
                        wait_port(3, 0, 48);
                        wait_port(4, 0, 48);
                        wait_port(5, 0, 48);
                        wait_port(6, 0, 48);
                        for (int k = 0; k < 48; k++) begin
                            send_read(3, 'h20000+32'(k*512), 15, 1'(k));
                            send_read(4, 'h30000+32'(k*512), 15, 1'(k));
                            send_read(5, 'h40000+32'(k*512), 15, 1'(k));
                            send_read(6, 'h50000+32'(k*512), 15, 1'(k));
                        end
                        wait_port(0, 48, 0);
                        wait_port(3, 48, 48);
                        wait_port(4, 48, 48);
                        wait_port(5, 48, 48);
                        wait_port(6, 48, 48);
                    end
                join
                require_grants(576);
            end
            213: begin
                rd_eq(0, 'h220, 2);
                // Read back committed P1 writes while new disjoint writes run.
                send_write(1, 'h10000, 15, 1);
                wait_port(1, 0, 1);
                g_port[1].u_master.r_on = 0;
                for (int k = 0; k < 4; k++)
                    send_read(1, 'h10000, 15, 1'(k));
                send_write(1, 'h20000, 15, 0);
                drain(200);
                eq("P1 completed writes under R stall", 2, local_writes[1]);
                eq("P1 buffered reads retain port slots", 2,
                    u_schedule_reference.rd_outstanding[1]);
                eq("P1 read cap stops further DDR grants", 2, u_schedule.max_read[1]);
                eq("P1 R backpressure", 0, local_reads[1]);
                eq("P1 two reads plus two writes", 4, u_schedule.transactions[1]);
                g_port[1].u_master.r_on = 1;
                wait_port(1, 4, 2);
                require_grants(6);

                // A zero-weight P1 can win here only through urgent priority.
                total_limit = 1;
                wr(0, 'h100, 1);
                wr(0, 'h104, 2);
                wr(0, 'h228, 0);
                g_port[1].u_master.urgent_enable = 1;
                start = u_schedule.grants.size();
                for (int k = 0; k < 6; k++) begin
                    send_read(1, 'h10000, 3, 1'(k));
                    send_read(3, 'h30000+32'(k*512), 3, 1'(k));
                end
                wait_port(1, 10, 2);
                wait_port(3, 6, 0);
                for (int k = 0; k < 2; k++) begin
                    eq("P1 urgent read wins", 1, u_schedule.grants[start+k].port);
                    eq("P1 urgent direction", 0, int'(u_schedule.grants[start+k].write));
                end
                eq("P1 URG_MAX lets P3 proceed", 3, u_schedule.grants[start+2].port);
                truth("P1 urgent read statistics", u_schedule_reference.urg[1] >= 6);
                require_grants(12);

                g_port[1].u_master.urgent_enable = 0;
                wr(0, 'h228, 4);
                total_limit = 8;
                wr(0, 'h100, 8);
                g_port[1].u_master.r_random = 1;
                g_port[1].u_master.b_random = 1;
                g_port[1].u_master.r_period = 11;
                g_port[1].u_master.r_on = 3;
                g_port[1].u_master.b_period = 7;
                g_port[1].u_master.b_on = 2;
                for (int k = 0; k < 32; k++) begin
                    send_read(1, 'h10000, int'(random_next()%16), 1'(k));
                    send_write(1, 'h40000+32'(k*512), int'(random_next()%16), 1'(k), 1);
                end
                wait_port(1, 42, 34);
                require_grants(64);
                eq("P1 protocol errors", 0, local_errors[1]);
                eq("P1 reference checked reads", 42, local_reads[1]);
            end
            default: $fatal(1, "FAIL unimplemented MX test=%0d time=%0t", test, $time);
        endcase
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
        send_write(1, 'h10000);
        for (int port = 3; port < 7; port++) begin
            send_write(port, 32'(port*65536));
            wait_port(port, 0, 1);
            send_read(port, 32'(port*65536));
            wait_port(port, 1, 1);
        end
        wait_port(0, 1, 0);
        wait_port(1, 0, 1);
        send_read(1, 'h10000, 15, 1);
        wait_port(1, 1, 1);
        gateway_write('h80070000, 3, 3);
        gateway_read('hc0070000, 3, 3);
        require_grants(13);
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
        for (int j = 0; j < 5; j++)
            $display("COVER schedule rule=%0d hits=%0d", j+1, u_schedule_reference.rule_hits[j]);
        $display("COVER schedule urg_cap=%0b token_skip=%0b starve=%0b switches=%0d",
                 u_schedule_reference.urg_cap_hits != 0, u_schedule_reference.token_skips != 0,
                 u_schedule_reference.starve_hits != 0, u_schedule.direction_switches);
        $display("COVER flow global_peak=%0d credit_peak=%0d credit_full=%0b",
                 u_schedule.max_outstanding, max_credit, coverage_credit);
        for (int j = 0; j < 7; j++)
            $display("COVER flow port=%0d rd_peak=%0d wr_peak=%0d", j,
                     u_schedule.max_read[j], u_schedule.max_write[j]);
        for (int kind = 0; kind < 2; kind++)
            for (int direction = 0; direction < 2; direction++)
                $display("COVER violation kind=%0d dir=%0d hit=%0b", kind,
                         direction, coverage_violation[kind][direction]);
        $display("COVER statistics snapshot=%0b clear=%0b saturation=unit_test",
                 coverage_snapshot, coverage_clear);
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
        for (int port = 0; port < 7; port++)
            preload(32'(port*65536), 32768, 'habcd0000);
        $display("MB START CASE=%0d SEED=%0d time=%0t", selected_case, seed, $time);
        if (CASE == 0) begin
            if (selected_case >= 101 && selected_case <= 105) test_gateway(selected_case);
            else if (selected_case >= 201 && selected_case <= 213) test_xbar(selected_case);
            else if (selected_case == 601) test_bandwidth();
            else if (selected_case == 501) test_top();
            else $fatal(1, "FAIL unknown CASE=%0d time=%0t", selected_case, $time);
        end else if (CASE >= 101 && CASE <= 105) test_gateway(CASE);
        else if (CASE >= 201 && CASE <= 213) test_xbar(CASE);
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
