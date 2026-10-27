// File: edrv32_mem_schedule_reference.sv
// Spec: SoC 6.4.2-6.4.5; mem-subsys 2.2/4.1; testplan 4.
// Description: Reconstructs ingress queues, W completion, token credit and arbitration classes.
// Clock domain: clk_mem. Only declared module ports are observed.
`timescale 1ns/1ps
module edrv32_mem_schedule_reference (
    input logic clk_i,
    input logic rst_n_i,
    input logic [6:0] urgent_i,
    input logic prepare_i,
    input logic grant_i,
    input logic apb_write_i,
    input logic [11:0] apb_addr_i,
    input logic [31:0] apb_data_i,
    edrv32_axi256_if upstream[7],
    edrv32_axi256_if downstream
);
    typedef struct packed {
        int beats;
        bit legal;
        int head_cycle;
    } request_t;
    // Power-of-two storage avoids Verilator 5.020 queue lvalue bounds temporaries.
    // Only ports 0-6 are used; protocol checks reject DDR port ID 7.
    request_t read_queue[8][$];
    request_t write_queue[8][$];
    int complete_writes[8][$];
    bit read_response_legal[8][$];
    bit write_response_legal[8][$];
    int downstream_w_remaining;
    int w_beats[7];
    int weights[7];
    int rates[7];
    int tokens[7];
    int rd_limit[7];
    int wr_limit[7];
    int rd_outstanding[7];
    int wr_outstanding[7];
    int total_limit;
    int outstanding;
    int reserved;
    int urgent_count[7];
    int urg_max;
    int starve;
    int batch;
    int cycle;
    int last_direction;
    int direction_run;
    int deficit[7];
    int refill_count[7];
    bit prepared_expected;
    bit [6:0] refill_ports;
    bit [6:0] frozen_refill_ports;
    bit candidates_present;
    bit drr_candidate_present;
    bit frozen_drr_candidate_present;
    bit [6:0] allowed_read;
    bit [6:0] allowed_write;
    bit [6:0] latched_read;
    bit [6:0] latched_write;
    int priority_class;
    int latched_read_class;
    int latched_write_class;
    bit [6:0] urgent_sampled;
    bit grant_pending;
    bit [6:0] grant_urgent_sample;
    int grant_tokens[7];
    int grant_rates[7];
    int grant_urgent_count[7];
    int command_class;
    int command_head_cycle;
    bit command_switch;
    int rule_hits[5];
    int token_skips;
    int urg_cap_hits;
    int starve_hits;
    int credit_full_hits;
    int batch_contests;
    int invalid_read[7];
    int invalid_write[7];
    int unsigned txn[7];
    int unsigned beats[7];
    int unsigned wait_max[7];
    int unsigned wait_sum[7];
    int unsigned urg[7];
    int unsigned dir_switch;
    int unsigned busy;
    int unsigned window_cycles;
    int unsigned snap_txn[7];
    int unsigned snap_beats[7];
    int unsigned snap_wait_max[7];
    int unsigned snap_wait_sum[7];
    int unsigned snap_urg[7];
    int unsigned snap_switch;
    int unsigned snap_busy;
    int unsigned snap_window;
    bit clear_statistics;
    bit [6:0] ar_valid;
    bit [6:0] aw_valid;
    bit [6:0] ar_take;
    bit [6:0] aw_take;
    bit [6:0] w_take;
    bit [6:0] r_take;
    bit [6:0] r_ready;
    bit [6:0] r_valid;
    bit [6:0] b_take;
    bit [223:0] ar_addr;
    bit [223:0] aw_addr;
    bit [27:0] ar_len;
    bit [27:0] aw_len;
    bit [6:0] w_last;
    bit [6:0] r_last;
    for (genvar n = 0; n < 7; n++) begin : g_ingress
        assign ar_valid[n] = upstream[n].arvalid;
        assign aw_valid[n] = upstream[n].awvalid;
        assign ar_take[n] = upstream[n].arvalid && upstream[n].arready;
        assign aw_take[n] = upstream[n].awvalid && upstream[n].awready;
        assign w_take[n] = upstream[n].wvalid && upstream[n].wready;
        assign r_take[n] = upstream[n].rvalid && upstream[n].rready;
        assign r_ready[n] = upstream[n].rready;
        assign r_valid[n] = upstream[n].rvalid;
        assign b_take[n] = upstream[n].bvalid && upstream[n].bready;
        assign ar_addr[n*32 +: 32] = upstream[n].araddr;
        assign aw_addr[n*32 +: 32] = upstream[n].awaddr;
        assign ar_len[n*4 +: 4] = upstream[n].arlen;
        assign aw_len[n*4 +: 4] = upstream[n].awlen;
        assign w_last[n] = upstream[n].wlast;
        assign r_last[n] = upstream[n].rlast;
    end

    `include "edrv32_mem_flow_observation.svh"

    function automatic int unsigned sat_add(input int unsigned a,
        input int unsigned b);
        bit [32:0] sum;
        sum = {1'b0,a}+{1'b0,b};
        return sum[32] ? 32'hffffffff : sum[31:0];
    endfunction

    function automatic bit legal(input bit [31:0] addr,
        input int length);
        return addr[4:0] == 0 && int'(addr[11:0])+length*32 <= 4096;
    endfunction

    task automatic choose_allowed(input int ring_used,
        input int ring_count);
        bit [6:0] eligible_r;
        bit [6:0] eligible_w;
        bit [6:0] urgent_r;
        bit [6:0] urgent_w;
        bit [6:0] token_r;
        bit [6:0] token_w;
        bit [6:0] starved_r;
        bit [6:0] starved_w;
        int nr;
        int nw;
        eligible_r = 0;
        eligible_w = 0;
        refill_ports = 0;
        candidates_present = 0;
        drr_candidate_present = 0;
        urgent_r = 0;
        urgent_w = 0;
        starved_r = 0;
        starved_w = 0;
        for (int p = 0; p < 7; p++) begin
            nr = read_queue[p].size() != 0 ? read_queue[p][0].beats : 0;
            nw = write_queue[p].size() != 0 ? write_queue[p][0].beats : 0;
            eligible_r[p] = nr != 0 && outstanding < total_limit &&
                            rd_outstanding[p] < rd_limit[p] && ring_used+nr <= 128 && ring_count < 8;
            eligible_w[p] = nw != 0 && complete_writes[p].size() != 0 &&
                            outstanding < total_limit && wr_outstanding[p] < wr_limit[p] &&
                            downstream_w_remaining == 0;
            token_r[p] = eligible_r[p];
            token_w[p] = eligible_w[p];
            if ((p == 2 || p == 6) && tokens[p] < nr*256) begin
                if (eligible_r[p]) token_skips++;
                token_r[p] = 0;
            end
            if ((p == 2 || p == 6) && tokens[p] < nw*256) begin
                if (eligible_w[p]) token_skips++;
                token_w[p] = 0;
            end
            candidates_present |= eligible_r[p] || eligible_w[p];
            if (p != 2 && weights[p] != 0 && (token_r[p] || token_w[p]))
                drr_candidate_present = 1;
            // Confirmed DRR round: credit a queued insufficient deficit regardless
            // of token/capacity eligibility; a sufficient deficit keeps its credit.
            refill_ports[p] = weights[p] != 0 &&
                (nr != 0 && deficit[p] < nr || nw != 0 &&
                complete_writes[p].size() != 0 && deficit[p] < nw);
            if (p < 2 && urgent_sampled[p]) begin
                urgent_r[p] = eligible_r[p] && urgent_count[p] < urg_max;
                urgent_w[p] = eligible_w[p] && urgent_count[p] < urg_max;
                if (urgent_count[p] == urg_max) urg_cap_hits++;
            end
            if (nr != 0)
                starved_r[p] = eligible_r[p] &&
                               cycle-read_queue[p][0].head_cycle+1 > starve;
            if (nw != 0 && complete_writes[p].size() != 0)
                starved_w[p] = eligible_w[p] &&
                               cycle-write_queue[p][0].head_cycle+1 > starve;
        end
        priority_class = 4;
        if (|urgent_r || |urgent_w) begin
            priority_class = 1;
            allowed_read = urgent_r;
            allowed_write = urgent_w;
        end else if (token_r[2] || token_w[2]) begin
            priority_class = 2;
            allowed_read = token_r & 7'b0000100;
            allowed_write = token_w & 7'b0000100;
        end else if (|starved_r || |starved_w) begin
            priority_class = 3;
            allowed_read = starved_r;
            allowed_write = starved_w;
        end else begin
            allowed_read = token_r;
            allowed_write = token_w;
            for (int p = 0; p < 7; p++) begin
                nr = read_queue[p].size() != 0 ? read_queue[p][0].beats : 0;
                nw = write_queue[p].size() != 0 ? write_queue[p][0].beats : 0;
                allowed_read[p] &= deficit[p] >= nr;
                allowed_write[p] &= deficit[p] >= nw;
            end
            for (int p = 0; p < 7; p++) begin
                if (weights[p] == 0 || p == 2) begin
                    allowed_read[p] = 0;
                    allowed_write[p] = 0;
                end
            end
            // Direction batching only constrains a choice when both directions qualify.
            if (|allowed_read && |allowed_write && last_direction >= 0) begin
                batch_contests++;
                if (direction_run < batch) begin
                    if (last_direction == 0) allowed_write = 0;
                    else allowed_read = 0;
                end else begin
                    if (last_direction == 0) allowed_read = 0;
                    else allowed_write = 0;
                end
            end
        end
    endtask

    // DDR VALID reveals the decision one cycle after grant_i. Replay its saved
    // token/urgent state at that decision edge; DDR backpressure cannot change it.
    task automatic commit_command(input bit write, input int p, input int length);
        request_t request;
        int complete_beats;
        bit [6:0] mask;
        mask = write ? latched_write : latched_read;
        command_class = write ? latched_write_class : latched_read_class;
        if (!mask[p])
            $fatal(1, "FAIL allowed set expected=%b actual=port%0d dir=%0b time=%0t",
                mask, p, write, $time);
        if (write) begin
            request = write_queue[p].pop_front();
            complete_beats = complete_writes[p].pop_front();
            if (complete_beats != length)
                $fatal(1, "FAIL complete W beats expected=%0d actual=%0d time=%0t",
                    length, complete_beats, $time);
            wr_outstanding[p]++;
        end else begin
            request = read_queue[p].pop_front();
            rd_outstanding[p]++;
            reserved += length;
            flow_allocate(p, length);
        end
        if (request.beats != length)
            $fatal(1, "FAIL ingress burst expected=%0d actual=%0d time=%0t",
                request.beats, length, $time);
        command_head_cycle = request.head_cycle;
        if (command_class == 4) deficit[p] -= length;
        if (p == 2 || p == 6) begin
            tokens[p] = grant_tokens[p]+grant_rates[p]-length*256;
            if (tokens[p] < 0) tokens[p] = 0;
            if (tokens[p] > 8192) tokens[p] = 8192;
        end
        for (int j = 0; j < 7; j++) begin
            urgent_count[j] = 0;
            if (j == p) begin
                if (command_class == 1) urgent_count[j] = grant_urgent_count[j]+1;
                else if (grant_urgent_sample[j]) urgent_count[j] = grant_urgent_count[j];
            end
        end
        command_switch = last_direction >= 0 && last_direction != int'(write);
        if (last_direction == int'(write)) direction_run++;
        else direction_run = 1;
        last_direction = int'(write);
        for (int port = 0; port < 7; port++) begin
            if (port == p && write_queue[port].size() != 0 &&
                complete_writes[port].size() != 0 && write_queue[port][0].head_cycle == -1) begin
                request = write_queue[port].pop_front();
                request.head_cycle = cycle+1;
                write_queue[port].push_front(request);
            end
        end
    endtask

    // All public statistics remain tied to the DDR handshake, including WAIT.
    task automatic grant(input bit write, input int p, input int length);
        int wait_cycles;
        wait_cycles = cycle-command_head_cycle+1;
        outstanding++;
        if (write) downstream_w_remaining += length;
        if (!clear_statistics) begin
            txn[p] = sat_add(txn[p], 1);
            beats[p] = sat_add(beats[p], 32'(length));
            wait_sum[p] = sat_add(wait_sum[p], 32'(wait_cycles));
            if (32'(wait_cycles) > wait_max[p]) wait_max[p] = 32'(wait_cycles);
            if (command_class == 1) urg[p] = sat_add(urg[p], 1);
            if (command_switch) dir_switch = sat_add(dir_switch, 1);
        end
        rule_hits[command_class-1]++;
        if (command_class == 3) starve_hits++;
        if (command_switch) rule_hits[4]++;
    endtask

    always @(posedge clk_i) begin : reconstruct
        request_t request;
        bit [31:0] addr;
        int port;
        int ring_used;
        int ring_count;
        if (!rst_n_i) begin
            cycle = 0;
            flow_reset();
            total_limit = 8;
            urg_max = 8;
            starve = 256;
            batch = 4;
            outstanding = 0;
            downstream_w_remaining = 0;
            reserved = 0;
            last_direction = -1;
            direction_run = 0;
            prepared_expected = 0;
            frozen_refill_ports = 0;
            frozen_drr_candidate_present = 0;
            urgent_sampled = 0;
            grant_pending = 0;
            grant_urgent_sample = 0;
            latched_read = 0;
            latched_write = 0;
            latched_read_class = 4;
            latched_write_class = 4;
            token_skips = 0;
            urg_cap_hits = 0;
            starve_hits = 0;
            credit_full_hits = 0;
            batch_contests = 0;
            dir_switch = 0;
            busy = 0;
            window_cycles = 0;
            snap_switch = 0;
            snap_busy = 0;
            snap_window = 0;
            for (int j = 0; j < 5; j++) rule_hits[j] = 0;
            for (int p = 0; p < 7; p++) begin
                read_queue[p].delete();
                read_response_legal[p].delete();
                write_response_legal[p].delete();
                write_queue[p].delete();
                complete_writes[p].delete();
                w_beats[p] = 0;
                weights[p] = p < 2 ? 4 : p == 3 ? 3 : p == 6 ? 1 : 2;
                rates[p] = p == 2 ? 26 : p == 6 ? 13 : 0;
                tokens[p] = 32*256;
                rd_limit[p] = p == 1 ? 2 : p == 2 ? 1 : p < 4 ? 4 : 2;
                wr_limit[p] = p == 0 ? 0 : p == 1 ? 4 : p == 2 ? 1 : 2;
                rd_outstanding[p] = 0;
                wr_outstanding[p] = 0;
                urgent_count[p] = 0;
                deficit[p] = 0;
                refill_count[p] = 0;
                invalid_read[p] = 0;
                invalid_write[p] = 0;
                txn[p] = 0;
                beats[p] = 0;
                wait_max[p] = 0;
                wait_sum[p] = 0;
                urg[p] = 0;
                snap_txn[p] = 0;
                snap_beats[p] = 0;
                snap_wait_max[p] = 0;
                snap_wait_sum[p] = 0;
                snap_urg[p] = 0;
            end
        end else begin
            cycle++;
            clear_statistics = apb_write_i && apb_addr_i == 'h110 && apb_data_i[1];
            if (apb_write_i && apb_addr_i == 'h110 && apb_data_i[0]) begin
                for (int p = 0; p < 7; p++) begin
                    snap_txn[p] = txn[p];
                    snap_beats[p] = beats[p];
                    snap_wait_max[p] = wait_max[p];
                    snap_wait_sum[p] = wait_sum[p];
                    snap_urg[p] = urg[p];
                end
                snap_switch = dir_switch;
                snap_busy = busy;
                snap_window = window_cycles;
            end
            if (clear_statistics) begin
                for (int p = 0; p < 7; p++) begin
                    txn[p] = 0;
                    beats[p] = 0;
                    wait_max[p] = 0;
                    wait_sum[p] = 0;
                    urg[p] = 0;
                end
                dir_switch = 0;
                busy = 0;
                window_cycles = 0;
            end else begin
                window_cycles = sat_add(window_cycles, 1);
                if (outstanding != 0) busy = sat_add(busy, 1);
            end
            if (grant_pending) begin
                if (!(downstream.awvalid ^ downstream.arvalid))
                    $fatal(1, "FAIL grant pipeline expected=one DDR VALID actual=AW%0b AR%0b",
                        downstream.awvalid, downstream.arvalid);
                if (downstream.awvalid)
                    commit_command(1, int'(downstream.awid)>>1, int'(downstream.awlen)+1);
                else commit_command(0, int'(downstream.arid)>>1, int'(downstream.arlen)+1);
            end
            // Eligibility samples occupancy before this edge retires the oldest slot.
            ring_used = flow_ring_used;
            ring_count = flow_ring_count;
            flow_observe();
            // Only a capacity/token-ready weighted head can start the next round.
            // Configuration writes cancel that decision before it can refill.
            if (prepared_expected && frozen_drr_candidate_present &&
                !prepare_i && !grant_i &&
                !(apb_write_i && (apb_addr_i[11:4] == 8'h10 ||
                    (apb_addr_i[11:8] == 4'h2 && apb_addr_i[7:5] != 7 &&
                    !apb_addr_i[4])))) begin
                for (int p = 0; p < 7; p++)
                    if (p != 2 && frozen_refill_ports[p]) begin
                        deficit[p] += weights[p]*16;
                        refill_count[p]++;
                    end
            end
            if (prepare_i) begin
                choose_allowed(ring_used, ring_count);
                frozen_refill_ports = refill_ports;
                frozen_drr_candidate_present = drr_candidate_present;
                latched_read = allowed_read;
                latched_write = allowed_write;
                latched_read_class = priority_class;
                latched_write_class = priority_class;
            end
            if (grant_i) begin
                grant_urgent_sample = urgent_sampled;
                for (int p = 0; p < 7; p++) begin
                    grant_tokens[p] = tokens[p];
                    grant_rates[p] = rates[p];
                    grant_urgent_count[p] = urgent_count[p];
                end
            end
            if (downstream.bvalid) outstanding--;
            if (downstream.rvalid && downstream.rlast) outstanding--;
            if (downstream.wvalid && downstream.wready) downstream_w_remaining--;
            if (downstream.arvalid && downstream.arready)
                grant(0, int'(downstream.arid)>>1, int'(downstream.arlen)+1);
            if (downstream.awvalid && downstream.awready)
                grant(1, int'(downstream.awid)>>1, int'(downstream.awlen)+1);
            for (int p = 0; p < 7; p++) begin
                // Port limits retire at the source response, unlike the global DDR limit.
                if (r_take[p]) begin
                    if (read_response_legal[p][0]) begin
                        reserved--;
                        flow_take(p);
                    end
                    if (r_last[p]) begin
                        if (read_response_legal[p][0]) rd_outstanding[p]--;
                        else invalid_read[p]--;
                        read_response_legal[p].delete(0);
                    end
                end
                if (b_take[p]) begin
                    if (write_response_legal[p][0]) wr_outstanding[p]--;
                    else invalid_write[p]--;
                    write_response_legal[p].delete(0);
                end
                if (!urgent_sampled[p]) urgent_count[p] = 0;
                if (tokens[p] < 8192) begin
                    tokens[p] += rates[p];
                    if (tokens[p] > 8192) tokens[p] = 8192;
                    // Starvation may use the remainder of an underfunded bucket.
                    if (tokens[p] < 0) tokens[p] = 0;
                end
                if (ar_take[p]) begin
                    addr = ar_addr[p*32 +: 32];
                    request.beats = int'(ar_len[p*4 +: 4])+1;
                    request.legal = legal(addr, request.beats);
                    // ARREADY admits the next head after the previous command commits,
                    // which can precede its DDR handshake under downstream backpressure.
                    request.head_cycle = cycle+1;
                    read_response_legal[p].push_back(request.legal);
                    if (request.legal) read_queue[p].push_back(request);
                    else invalid_read[p]++;
                end
                if (aw_take[p]) begin
                    addr = aw_addr[p*32 +: 32];
                    request.beats = int'(aw_len[p*4 +: 4])+1;
                    request.legal = legal(addr, request.beats);
                    request.head_cycle = -1;
                    write_response_legal[p].push_back(request.legal);
                    write_queue[p].push_back(request);
                end
                if (w_take[p]) begin
                    w_beats[p]++;
                    if (w_last[p]) begin
                        complete_writes[p].push_back(w_beats[p]);
                        w_beats[p] = 0;
                        if (write_queue[p].size() != 0 && !write_queue[p][0].legal) begin
                            request = write_queue[p].pop_front();
                            complete_writes[p].delete(0);
                            invalid_write[p]++;
                        end
                    end
                end
                if (write_queue[p].size() != 0 && complete_writes[p].size() != 0 &&
                    write_queue[p][0].head_cycle == -1)
                begin
                    request = write_queue[p].pop_front();
                    request.head_cycle = cycle+1;
                    write_queue[p].push_front(request);
                end
            end
            if (reserved == 128) credit_full_hits++;
            prepared_expected = prepare_i && candidates_present;
            urgent_sampled = urgent_i;
            grant_pending = grant_i;
            if (apb_write_i) begin
                case (apb_addr_i)
                    'h100: total_limit = int'(apb_data_i[3:0]);
                    'h104: urg_max = int'(apb_data_i[7:0]);
                    'h108: starve = int'(apb_data_i[15:0]);
                    'h10c: batch = int'(apb_data_i[7:0]);
                    default: begin
                        if (apb_addr_i >= 'h200 && apb_addr_i < 'h2e0) begin
                            port = (int'(apb_addr_i)-'h200)/32;
                            case (apb_addr_i[4:0])
                                0: rd_limit[port] = int'(apb_data_i[3:0]);
                                4: wr_limit[port] = int'(apb_data_i[3:0]);
                                8: weights[port] = int'(apb_data_i[3:0]);
                                12: rates[port] = int'(apb_data_i[8:0]);
                                default: begin end
                            endcase
                        end
                    end
                endcase
            end
        end
    end
endmodule
