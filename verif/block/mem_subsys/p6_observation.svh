// File: p6_observation.svh
// Spec: mem-subsys 2.4; P6-01. Check round robin at the P6 ingress boundary.
// Description: Verification connections and observations.
// Clock domain: clk_mem (gateway parent observations also use clk_sys).
    bit p6_previous_ar;
    bit p6_previous_aw;
    bit p6_previous_ar_taken;
    bit p6_previous_aw_taken;
    bit p6_both_read;
    bit p6_both_write;
    bit p6_ar_contested;
    bit p6_aw_contested;
    bit p6_have_read_grant;
    bit p6_have_write_grant;
    bit p6_next_read;
    bit p6_next_write;
    int p6_read_contests;
    int p6_write_contests;
    always @(posedge clk_mem) begin : observe_p6_round_robin
        if (!rst_mem_n) begin
            p6_previous_ar = 0;
            p6_previous_aw = 0;
            p6_previous_ar_taken = 0;
            p6_previous_aw_taken = 0;
            p6_both_read = 0;
            p6_both_write = 0;
            p6_ar_contested = 0;
            p6_aw_contested = 0;
            p6_have_read_grant = 0;
            p6_have_write_grant = 0;
            p6_next_read = 0;
            p6_next_write = 0;
            p6_read_contests = 0;
            p6_write_contests = 0;
        end else begin
            if (xbar[6].arvalid && (!p6_previous_ar || p6_previous_ar_taken))
                p6_ar_contested = p6_both_read;
            if (xbar[6].awvalid && (!p6_previous_aw || p6_previous_aw_taken))
                p6_aw_contested = p6_both_write;
            if (xbar[6].arvalid && xbar[6].arready) begin
                if (selected_case == 401 && p6_ar_contested && p6_have_read_grant) begin
                    eq("P6 read round robin", int'(p6_next_read), int'(xbar[6].arid));
                    p6_read_contests++;
                end
                p6_next_read = !xbar[6].arid;
                p6_have_read_grant = 1;
            end
            if (xbar[6].awvalid && xbar[6].awready) begin
                if (selected_case == 401 && p6_aw_contested && p6_have_write_grant) begin
                    eq("P6 write round robin", int'(p6_next_write), int'(xbar[6].awid));
                    p6_write_contests++;
                end
                p6_next_write = !xbar[6].awid;
                p6_have_write_grant = 1;
            end
            p6_both_read = p[6].arvalid && u_dut.u_perf_mon.axi_arvalid_o;
            p6_both_write = p[6].awvalid && u_dut.u_perf_mon.axi_awvalid_o;
            p6_previous_ar = xbar[6].arvalid;
            p6_previous_aw = xbar[6].awvalid;
            p6_previous_ar_taken = xbar[6].arvalid && xbar[6].arready;
            p6_previous_aw_taken = xbar[6].awvalid && xbar[6].awready;
        end
    end
