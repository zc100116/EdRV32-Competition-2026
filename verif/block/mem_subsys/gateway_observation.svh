// File: gateway_observation.svh
// Spec: mem-subsys 2.1; compare the conversion independently of DDR storage.
// Description: Verification connections and observations.
// Clock domain: clk_mem (gateway parent observations also use clk_sys).
    typedef struct packed {
        bit [31:0] addr;
        bit [255:0] data;
        bit [31:0] strb;
    } gateway_expected_t;
    typedef struct packed {
        int port;
        int beats;
        gateway_expected_t gateway;
    } downstream_write_t;
    gateway_expected_t gateway_writes[$];
    bit [31:0] gateway_reads[$];
    downstream_write_t downstream_writes[$];
    int downstream_write_beat;
    int gateway_reads_inflight;
    int gateway_writes_inflight;
    int local_gateway_reads_inflight;
    int local_gateway_writes_inflight;
    bit [3:0] gateway_parent_read_id;
    bit [3:0] gateway_parent_write_id;
    always @(posedge clk_mem) begin : observe_gateway_conversion
        downstream_write_t command;
        gateway_expected_t expected;
        bit [31:0] expected_addr;
        if (!rst_mem_n) begin
            gateway_writes.delete();
            gateway_reads.delete();
            downstream_writes.delete();
            downstream_write_beat = 0;
            gateway_reads_inflight = 0;
            gateway_writes_inflight = 0;
        end else begin
            if (ddr.bvalid && ddr.bid[3:1] == 2) gateway_writes_inflight--;
            if (ddr.rvalid && ddr.rlast && ddr.rid[3:1] == 2) gateway_reads_inflight--;
            if (ddr.arvalid && ddr.arready && ddr.arid[3:1] == 2) begin
                truth("GW has expected AR", gateway_reads.size() != 0);
                expected_addr = gateway_reads.pop_front();
                eq("GW DDR ARADDR", int'(expected_addr), int'(ddr.araddr));
                eq("GW DDR ARLEN", 0, int'(ddr.arlen));
                eq("GW DDR ARID", 4, int'(ddr.arid));
                truth("GW one read downstream", gateway_reads_inflight == 0);
                gateway_reads_inflight++;
            end
            if (ddr.awvalid && ddr.awready) begin
                command = '0;
                command.port = int'(ddr.awid[3:1]);
                command.beats = int'(ddr.awlen)+1;
                if (command.port == 2) begin
                    truth("GW has expected AW", gateway_writes.size() != 0);
                    command.gateway = gateway_writes.pop_front();
                    eq("GW DDR AWADDR", int'(command.gateway.addr), int'(ddr.awaddr));
                    eq("GW DDR AWLEN", 0, int'(ddr.awlen));
                    eq("GW DDR AWID", 4, int'(ddr.awid));
                    truth("GW one write downstream", gateway_writes_inflight == 0);
                    gateway_writes_inflight++;
                end
                downstream_writes.push_back(command);
            end
            if (ddr.wvalid && ddr.wready) begin
                command = downstream_writes[0];
                if (command.port == 2) begin
                    expected = command.gateway;
                    eq("GW WSTRB", int'(expected.strb), int'(ddr.wstrb));
                    for (int b = 0; b < 32; b++)
                        if (expected.strb[b])
                            eq($sformatf("GW WDATA byte %0d", b),
                               int'(expected.data[b*8 +: 8]), int'(ddr.wdata[b*8 +: 8]));
                end
                downstream_write_beat++;
                if (downstream_write_beat == command.beats) begin
                    command = downstream_writes.pop_front();
                    downstream_write_beat = 0;
                end
            end
        end
    end
    // Parent transactions remain outstanding until their upstream response completes.
    always @(posedge clk_sys) begin
        if (!rst_sys_n) begin
            local_gateway_reads_inflight = 0;
            local_gateway_writes_inflight = 0;
        end else begin
            if (gw.rvalid && gw.rready) begin
                eq("GW every R beat RID", int'(gateway_parent_read_id), int'(gw.rid));
                truth("GW read has parent", local_gateway_reads_inflight != 0);
                if (gw.rlast) local_gateway_reads_inflight--;
            end
            if (gw.bvalid && gw.bready) begin
                eq("GW parent BID", int'(gateway_parent_write_id), int'(gw.bid));
                truth("GW write has parent", local_gateway_writes_inflight != 0);
                local_gateway_writes_inflight--;
            end
            if (gw.arvalid && gw.arready) begin
                eq("GW parent reads at most one", 0, local_gateway_reads_inflight);
                local_gateway_reads_inflight++;
                gateway_parent_read_id = gw.arid;
            end
            if (gw.awvalid && gw.awready) begin
                eq("GW parent writes at most one", 0, local_gateway_writes_inflight);
                local_gateway_writes_inflight++;
                gateway_parent_write_id = gw.awid;
            end
        end
    end
