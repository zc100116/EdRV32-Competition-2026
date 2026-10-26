// File: pmon_observation.svh
// Spec: mem-subsys 2.3; observation of module ports approved for task M-V1.
// Description: These are interface observations, independent of the PERF_MON implementation.
// Clock domain: clk_mem (gateway parent observations also use clk_sys).
// These are interface observations, independent of the PERF_MON implementation.
    int pmon_observation_cycle = 0;
    int pmon_outstanding;
    always @(posedge clk_mem) begin : observe_pmon_ports
        int started;
        int measured;
        pmon_observation_cycle <= pmon_observation_cycle+1;
        if (!rst_mem_n) begin
            pmon_outstanding = 0;
        end else begin
            if (u_dut.u_perf_mon.axi_arvalid_o && u_dut.u_perf_mon.axi_arready_i) begin
                pmon_latency[0].push_back(pmon_observation_cycle);
                pmon_outstanding++;
            end
            if (u_dut.u_perf_mon.axi_awvalid_o && u_dut.u_perf_mon.axi_awready_i)
                pmon_outstanding++;
            if (u_dut.u_perf_mon.axi_bvalid_i && u_dut.u_perf_mon.axi_bready_o)
                pmon_outstanding--;
            if (u_dut.u_perf_mon.axi_rvalid_i && u_dut.u_perf_mon.axi_rready_o) begin
                if (!pmon_read_started[0]) begin
                    measured = pmon_observation_cycle-pmon_latency[0][0];
                    observed_latencies.push_back(measured);
                    observed_hist[measured/hist_width > 15 ? 15 : measured/hist_width]++;
                    pmon_read_started[0] = 1;
                end
                if (u_dut.u_perf_mon.axi_rlast_i) begin
                    started = pmon_latency[0].pop_front();
                    pmon_read_started[0] = 0;
                    pmon_outstanding--;
                end
            end
        end
    end
    typedef struct packed {
        bit [31:0] addr;
        int beats;
    } pmon_write_address_t;
    pmon_write_address_t pmon_write_addresses[$];
    bit [287:0] pmon_write_data[$];
    always @(posedge clk_mem) begin : observe_pmon_pattern
        pmon_write_address_t address;
        bit [287:0] data;
        bit [31:0] expected;
        if (!rst_mem_n) begin
            pmon_write_addresses.delete();
            pmon_write_data.delete();
        end else begin
            if (u_dut.u_perf_mon.axi_awvalid_o && u_dut.u_perf_mon.axi_awready_i) begin
                address.addr = u_dut.u_perf_mon.axi_awaddr_o;
                address.beats = int'(u_dut.u_perf_mon.axi_awlen_o)+1;
                pmon_write_addresses.push_back(address);
            end
            if (u_dut.u_perf_mon.axi_wvalid_o && u_dut.u_perf_mon.axi_wready_i)
                pmon_write_data.push_back({u_dut.u_perf_mon.axi_wstrb_o,
                                           u_dut.u_perf_mon.axi_wdata_o});
            while (pmon_write_addresses.size() != 0 &&
                   pmon_write_data.size() >= pmon_write_addresses[0].beats) begin
                address = pmon_write_addresses.pop_front();
                for (int n = 0; n < address.beats; n++) begin
                    data = pmon_write_data.pop_front();
                    eq("PM full WSTRB", -1, int'(data[287:256]));
                    for (int word_index = 0; word_index < 8; word_index++) begin
                        expected = (address.addr+32'(n*32+word_index*4)) ^ pmon_pattern_seed;
                        eq("PM write pattern", int'(expected), int'(data[word_index*32 +: 32]));
                    end
                end
            end
        end
    end
