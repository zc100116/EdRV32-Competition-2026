// File: edrv32_mem_flow_observation.svh
// Spec: mem-subsys 2.2; MX-04 capacity investigation requested during M-I1.
// Description: Reconstruct read-ring retirement and measure source occupancy/stalls.
// Clock domain: clk_mem; all observations come from AXI pins and grant phase timestamps.
    int flow_p0_ar_idle;
    int flow_p1_aw_idle;
    int flow_p0_empty;
    int flow_p0_block[6];
    int flow_rd_sum[7];
    int flow_wr_sum[7];
    int flow_rd_peak[7];
    int flow_wr_peak[7];
    int flow_rd_full[7];
    int flow_wr_full[7];
    int flow_ideal_credit_full[7];
    int flow_ring_credit_full[7];
    int flow_ring_slot_full[7];
    int flow_global_full[7];
    int flow_r_not_ready[7];
    int flow_r_stall[7];
    int flow_ring_port[8];
    int flow_ring_beats[8];
    int flow_ring_sent[8];
    int flow_ring_head;
    int flow_ring_tail;
    int flow_ring_count;
    int flow_ring_used;

    task automatic flow_reset();
        flow_p0_ar_idle = 0;
        flow_p1_aw_idle = 0;
        flow_p0_empty = 0;
        for (int j = 0; j < 6; j++) flow_p0_block[j] = 0;
        flow_ring_head = 0;
        flow_ring_tail = 0;
        flow_ring_count = 0;
        flow_ring_used = 0;
        for (int p = 0; p < 7; p++) begin
            flow_rd_sum[p] = 0;
            flow_wr_sum[p] = 0;
            flow_rd_peak[p] = 0;
            flow_wr_peak[p] = 0;
            flow_rd_full[p] = 0;
            flow_wr_full[p] = 0;
            flow_ideal_credit_full[p] = 0;
            flow_ring_credit_full[p] = 0;
            flow_ring_slot_full[p] = 0;
            flow_global_full[p] = 0;
            flow_r_not_ready[p] = 0;
            flow_r_stall[p] = 0;
        end
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

    task automatic flow_observe();
        int nr;
        bit write_head;
        bit qualified_write;
        bit prefer_write;
        qualified_write = 0;
        for (int p = 0; p < 7; p++)
            if (write_queue[p].size() != 0 && complete_writes[p].size() != 0 &&
                outstanding < total_limit && wr_outstanding[p] < wr_limit[p] &&
                downstream_w_remaining == 0 && weights[p] != 0 &&
                deficit[p] >= write_queue[p][0].beats &&
                (p != 2 && p != 6 || tokens[p] >= write_queue[p][0].beats*256))
                qualified_write = 1;
        prefer_write = last_direction >= 0 &&
            (last_direction == 1 && direction_run < batch ||
             last_direction == 0 && direction_run >= batch);
        if (!ar_valid[0]) flow_p0_ar_idle++;
        if (!aw_valid[1]) flow_p1_aw_idle++;
        for (int p = 0; p < 7; p++) begin
            nr = read_queue[p].size() != 0 ? read_queue[p][0].beats : 0;
            if (p == 0) begin
                // Exclusive first blocking reason; the per-port counters below overlap.
                if (nr == 0) flow_p0_empty++;
                else if (outstanding >= total_limit) flow_p0_block[0]++;
                else if (rd_outstanding[p] >= rd_limit[p]) flow_p0_block[1]++;
                else if (flow_ring_used+nr > 128) flow_p0_block[2]++;
                else if (flow_ring_count == 8) flow_p0_block[3]++;
                else if (deficit[p] < nr) flow_p0_block[5]++;
                else if (prefer_write && qualified_write) flow_p0_block[4]++;
            end
            write_head = write_queue[p].size() != 0 && complete_writes[p].size() != 0;
            flow_rd_sum[p] += rd_outstanding[p];
            flow_wr_sum[p] += wr_outstanding[p];
            if (rd_outstanding[p] > flow_rd_peak[p]) flow_rd_peak[p] = rd_outstanding[p];
            if (wr_outstanding[p] > flow_wr_peak[p]) flow_wr_peak[p] = wr_outstanding[p];
            if (nr != 0 && rd_outstanding[p] >= rd_limit[p]) flow_rd_full[p]++;
            if (write_head && wr_outstanding[p] >= wr_limit[p]) flow_wr_full[p]++;
            if (nr != 0 && reserved+nr > 128) flow_ideal_credit_full[p]++;
            if (nr != 0 && flow_ring_used+nr > 128) flow_ring_credit_full[p]++;
            if (nr != 0 && flow_ring_count == 8) flow_ring_slot_full[p]++;
            if ((nr != 0 || write_head) && outstanding >= total_limit) flow_global_full[p]++;
            if (!r_ready[p]) flow_r_not_ready[p]++;
            if (r_valid[p] && !r_ready[p]) flow_r_stall[p]++;
        end
        // Like the ring, release one completed oldest allocation per edge.
        // Current-edge source transfers are applied after this observation.
        if (flow_ring_count != 0 &&
            flow_ring_sent[flow_ring_head] == flow_ring_beats[flow_ring_head]) begin
            flow_ring_used -= flow_ring_beats[flow_ring_head];
            flow_ring_head = (flow_ring_head+1)%8;
            flow_ring_count--;
        end
    endtask
