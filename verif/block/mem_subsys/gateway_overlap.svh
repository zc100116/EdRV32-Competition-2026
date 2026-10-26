// File: gateway_overlap.svh
// Spec: mem-subsys 2.1; GW-04, hold a second parent request during response stalls.
// Description: Verification connections and observations.
// Clock domain: clk_mem (gateway parent observations also use clk_sys).
    task automatic gateway_overlap_read();
        int accepted;
        int completed;
        int beat_index;
        gateway_reads.push_back('h5000);
        gateway_reads.push_back('h5020);
        @(negedge clk_sys);
        gw.araddr = 'h80005000;
        gw.arsize = 3;
        gw.arlen = 3;
        gw.arburst = 1;
        gw.arid = 5;
        gw.arvalid = 1;
        gw.rready = 0;
        do @(posedge clk_sys); while (!gw.arready);
        @(negedge clk_sys);
        gw.araddr = 'hc0005020;
        gw.arid = 6;
        repeat (30) begin
            @(posedge clk_sys);
            eq("GW second AR blocked before first R", 0, int'(gw.arready));
            @(negedge clk_sys);
        end
        gw.rready = 1;
        accepted = 1;
        completed = 0;
        beat_index = 0;
        while (completed < 2) begin
            @(posedge clk_sys);
            if (gw.rvalid && gw.rready) begin
                eq("GW overlapping RID", completed == 0 ? 5 : 6, int'(gw.rid));
                eq("GW overlapping RLAST", int'(beat_index == 3), int'(gw.rlast));
                eq("GW overlapping RRESP", 0, int'(gw.rresp));
                if (gw.rlast) begin
                    completed++;
                    beat_index = 0;
                end else beat_index++;
            end
            if (gw.arvalid && gw.arready) begin
                truth("GW AR only after first response", completed >= 1);
                accepted++;
            end
            @(negedge clk_sys);
            if (accepted == 2) gw.arvalid = 0;
        end
        gw.rready = 0;
        eq("GW two parent reads accepted", 2, accepted);
    endtask

    task automatic gateway_overlap_write();
        gateway_expected_t expected;
        expected = '0;
        expected.addr = 'h6000;
        expected.strb = '1;
        gateway_writes.push_back(expected);
        expected.addr = 'h6020;
        gateway_writes.push_back(expected);
        @(negedge clk_sys);
        gw.awaddr = 'h80006000;
        gw.awsize = 3;
        gw.awlen = 3;
        gw.awburst = 1;
        gw.awid = 9;
        gw.awvalid = 1;
        gw.bready = 0;
        do @(posedge clk_sys); while (!gw.awready);
        @(negedge clk_sys);
        gw.awvalid = 0;
        for (int b = 0; b < 4; b++) begin
            gw.wvalid = 1;
            gw.wdata = 0;
            gw.wstrb = '1;
            gw.wlast = b == 3;
            do @(posedge clk_sys); while (!gw.wready);
            @(negedge clk_sys);
        end
        gw.wvalid = 0;
        gw.wlast = 0;
        gw.awaddr = 'hc0006020;
        gw.awid = 10;
        gw.awvalid = 1;
        repeat (30) begin
            @(posedge clk_sys);
            eq("GW second AW blocked before first B", 0, int'(gw.awready));
            @(negedge clk_sys);
        end
        gw.bready = 1;
        do @(posedge clk_sys); while (!gw.bvalid);
        eq("GW overlapping first BID", 9, int'(gw.bid));
        eq("GW overlapping first BRESP", 0, int'(gw.bresp));
        // A response and acceptance of the next parent may share an edge.
        if (!gw.awready) do @(posedge clk_sys); while (!gw.awready);
        @(negedge clk_sys);
        gw.awvalid = 0;
        gw.bready = 0;
        for (int b = 0; b < 4; b++) begin
            gw.wvalid = 1;
            gw.wdata = 0;
            gw.wstrb = '1;
            gw.wlast = b == 3;
            do @(posedge clk_sys); while (!gw.wready);
            @(negedge clk_sys);
        end
        gw.wvalid = 0;
        gw.wlast = 0;
        gw.bready = 1;
        do @(posedge clk_sys); while (!gw.bvalid);
        eq("GW overlapping second BID", 10, int'(gw.bid));
        eq("GW overlapping second BRESP", 0, int'(gw.bresp));
        @(negedge clk_sys);
        gw.bready = 0;
    endtask
