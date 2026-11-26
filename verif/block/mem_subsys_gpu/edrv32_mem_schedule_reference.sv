// File: edrv32_mem_schedule_reference.sv
// Spec: SoC 6.4.2-6.4.5; mem-subsys 2.2/4.1; testplan 4.
// Description: Reconstructs queues, credit, fixed limits and urgent/CPU/round-robin grants.
// Clock domain: clk_mem. Only declared module ports are observed.
`timescale 1ns/1ps
module edrv32_mem_schedule_reference (
    input logic clk_i,
    input logic rst_n_i,
    input logic [4:0] urgent_i,
    input logic prepare_i,
    input logic grant_i,
    edrv32_axi256_if upstream[5],
    edrv32_axi256_if downstream
);
    typedef struct packed {
        int beats;
        bit legal;
        int head_cycle;
    } request_t;
    // Power-of-two storage avoids Verilator 5.020 queue lvalue bounds temporaries.
    // Only ports 0-4 are used in the GPU SoC.
    request_t read_queue[8][$];
    request_t write_queue[8][$];
    int complete_writes[8][$];
    bit read_response_legal[8][$];
    bit write_response_legal[8][$];
    int downstream_w_remaining;
    int w_beats[5];
    int rd_limit[5];
    int wr_limit[5];
    int rd_outstanding[5];
    int wr_outstanding[5];
    int outstanding;
    int reserved;
    int cycle;
    int next_port;
    bit last_write[5];
    bit [4:0] allowed_read;
    bit [4:0] allowed_write;
    bit [4:0] latched_read;
    bit [4:0] latched_write;
    bit [4:0] urgent_sampled;
    bit grant_pending;
    int priority_class;
    int latched_class;
    int rule_hits[3];
    int invalid_read[5];
    int invalid_write[5];
    int urg[5];
    bit [4:0] ar_valid;
    bit [4:0] aw_valid;
    bit [4:0] ar_take;
    bit [4:0] aw_take;
    bit [4:0] w_take;
    bit [4:0] r_take;
    bit [4:0] r_ready;
    bit [4:0] r_valid;
    bit [4:0] b_take;
    bit [159:0] ar_addr;
    bit [159:0] aw_addr;
    bit [19:0] ar_len;
    bit [19:0] aw_len;
    bit [4:0] w_last;
    bit [4:0] r_last;
    for (genvar n = 0; n < 5; n++) begin : g_ingress
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

    int flow_ring_port[8];
    int flow_ring_beats[8];
    int flow_ring_sent[8];
    int flow_ring_head;
    int flow_ring_tail;
    int flow_ring_count;
    int flow_ring_used;

    task automatic flow_reset();
        flow_ring_head = 0;
        flow_ring_tail = 0;
        flow_ring_count = 0;
        flow_ring_used = 0;
    endtask

    task automatic flow_allocate(input int p, input int length);
        flow_ring_port[flow_ring_tail] = p;
        flow_ring_beats[flow_ring_tail] = length;
        flow_ring_sent[flow_ring_tail] = 0;
        flow_ring_tail = (flow_ring_tail+1)%8;
        flow_ring_count++;
        flow_ring_used += length;
    endtask

    task automatic flow_take(input int p);
        int slot;
        bit found;
        found = 0;
        for (int offset = 0; offset < 8; offset++) begin
            slot = (flow_ring_head+offset)%8;
            if (!found && offset < flow_ring_count && flow_ring_port[slot] == p &&
                flow_ring_sent[slot] < flow_ring_beats[slot]) begin
                flow_ring_sent[slot]++;
                found = 1;
            end
        end
        if (!found) $fatal(1, "FAIL read return has no reserved descriptor p=%0d time=%0t",
            p, $time);
    endtask

    task automatic flow_observe;
        if (flow_ring_count != 0 &&
            flow_ring_sent[flow_ring_head] == flow_ring_beats[flow_ring_head]) begin
            flow_ring_used -= flow_ring_beats[flow_ring_head];
            flow_ring_head = (flow_ring_head+1)%8;
            flow_ring_count--;
        end
    endtask

    function automatic bit legal(input bit [31:0] addr,
        input int length);
        return addr[4:0] == 0 && int'(addr[11:0])+length*32 <= 4096;
    endfunction

    // Independently reconstruct eligible heads and select one exact transaction.
    task automatic choose_allowed(input int ring_used, input int ring_count);
        bit [4:0] eligible_read;
        bit [4:0] eligible_write;
        int selected;
        int port;
        int nr;
        eligible_read = 0;
        eligible_write = 0;
        allowed_read = 0;
        allowed_write = 0;
        selected = -1;
        for (int p = 0; p < 5; p++) begin
            nr = read_queue[p].size() != 0 ? read_queue[p][0].beats : 0;
            eligible_read[p] = nr != 0 && outstanding < 8 &&
                rd_outstanding[p] < rd_limit[p] && ring_used+nr <= 128 && ring_count < 8;
            eligible_write[p] = write_queue[p].size() != 0 &&
                complete_writes[p].size() != 0 && outstanding < 8 &&
                wr_outstanding[p] < wr_limit[p] && downstream_w_remaining == 0;
        end
        priority_class = 3;
        if (urgent_sampled[0] && eligible_read[0]) begin
            selected = 0;
            priority_class = 1;
        end else if (urgent_sampled[1] && eligible_read[1]) begin
            selected = 1;
            priority_class = 1;
        end else if (eligible_read[2] || eligible_write[2]) begin
            selected = 2;
            priority_class = 2;
        end else begin
            for (int offset = 0; offset < 4; offset++) begin
                port = (next_port+offset)%4;
                if (port >= 2) port++;
                if (selected == -1 && (eligible_read[port] || eligible_write[port]))
                    selected = port;
            end
        end
        if (selected >= 0) begin
            if (eligible_write[selected] &&
                (!eligible_read[selected] || !last_write[selected])) allowed_write[selected] = 1;
            else allowed_read[selected] = 1;
        end
    endtask

    task automatic commit_command(input bit write, input int p, input int length);
        request_t request;
        int complete_beats;
        bit [4:0] mask;
        mask = write ? latched_write : latched_read;
        if (!mask[p])
            $fatal(1, "FAIL arbitration expected read=%b write=%b actual=P%0d write=%b time=%0t",
                latched_read, latched_write, p, write, $time);
        if (write) begin
            request = write_queue[p].pop_front();
            complete_beats = complete_writes[p].pop_front();
            if (complete_beats != length) $fatal(1, "FAIL complete W length");
            wr_outstanding[p]++;
        end else begin
            request = read_queue[p].pop_front();
            rd_outstanding[p]++;
            reserved += length;
            flow_allocate(p, length);
        end
        if (request.beats != length) $fatal(1, "FAIL ingress burst length");
        last_write[p] = write;
        if (latched_class == 3) next_port = p == 4 ? 0 : p == 3 ? 3 : p+1;
        rule_hits[latched_class-1]++;
        if (latched_class == 1) urg[p]++;
    endtask
    task automatic grant(input bit write, input int p, input int length);
        outstanding++;
        if (write) downstream_w_remaining += length;
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
            outstanding = 0;
            downstream_w_remaining = 0;
            reserved = 0;
            next_port = 0;
            urgent_sampled = 0;
            grant_pending = 0;
            latched_read = 0;
            latched_write = 0;
            latched_class = 3;
            for (int j = 0; j < 3; j++) rule_hits[j] = 0;
            for (int p = 0; p < 5; p++) begin
                read_queue[p].delete();
                read_response_legal[p].delete();
                write_response_legal[p].delete();
                write_queue[p].delete();
                complete_writes[p].delete();
                w_beats[p] = 0;
                rd_limit[p] = p == 1 || p == 2 ? 1 : p < 4 ? 4 : 2;
                wr_limit[p] = p < 2 ? 0 : p == 2 ? 1 : 2;
                rd_outstanding[p] = 0;
                wr_outstanding[p] = 0;
                invalid_read[p] = 0;
                invalid_write[p] = 0;
                urg[p] = 0;
                last_write[p] = 1;
            end
        end else begin
            cycle++;
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
            if (prepare_i) begin
                choose_allowed(ring_used, ring_count);
                latched_read = allowed_read;
                latched_write = allowed_write;
                latched_class = priority_class;
            end
            if (downstream.bvalid) outstanding--;
            if (downstream.rvalid && downstream.rlast) outstanding--;
            if (downstream.wvalid && downstream.wready) downstream_w_remaining--;
            if (downstream.arvalid && downstream.arready)
                grant(0, int'(downstream.arid)>>1, int'(downstream.arlen)+1);
            if (downstream.awvalid && downstream.awready)
                grant(1, int'(downstream.awid)>>1, int'(downstream.awlen)+1);
            for (int p = 0; p < 5; p++) begin
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
            urgent_sampled = urgent_i;
            grant_pending = grant_i;
        end
    end
endmodule
