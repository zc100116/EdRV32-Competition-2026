// File: edrv32_mem_schedule_observer.sv
// Spec: mem-subsys-testplan 2.2, 4; SoC 6.4.
// Description: Records grants and occupancy; the separate reference computes allowed grants.
// Clock domain: clk_mem.
`timescale 1ns/1ps
module edrv32_mem_schedule_observer (
    input logic clk_i,
    input logic rst_n_i,
    input int total_limit_i,
    input int read_limit_i[7],
    input int write_limit_i[7],
    edrv32_axi256_if bus
);
    typedef struct packed {
        int cycle;
        int port;
        bit write;
        int beats;
    } grant_t;
    grant_t grants[$];
    int cycle;
    int outstanding;
    int read_outstanding[7];
    int write_outstanding[7];
    int max_outstanding;
    int max_read[7];
    int max_write[7];
    int transactions[7];
    int beats[7];
    int direction_switches;
    int busy_cycles;
    int last_direction;

    task automatic record_grant(input bit write,
        input int port,
        input int length);
        grant_t grant;
        // A smaller runtime limit prevents new grants; existing work may exceed it.
        if (outstanding >= total_limit_i)
            $fatal(1, "FAIL total limit expected=<%0d actual=%0d time=%0t",
                   total_limit_i, outstanding+1, $time);
        if ((write ? write_outstanding[port] : read_outstanding[port]) >=
            (write ? write_limit_i[port] : read_limit_i[port]))
            $fatal(1, "FAIL port limit p=%0d dir=%0b expected=<%0d actual=%0d time=%0t",
                   port, write, write ? write_limit_i[port] : read_limit_i[port],
                   write ? write_outstanding[port]+1 : read_outstanding[port]+1, $time);
        grant.cycle = cycle;
        grant.port = port;
        grant.write = write;
        grant.beats = length;
        grants.push_back(grant);
        outstanding++;
        if (write) write_outstanding[port]++;
        else read_outstanding[port]++;
        if (outstanding > max_outstanding) max_outstanding = outstanding;
        if (read_outstanding[port] > max_read[port]) max_read[port] = read_outstanding[port];
        if (write_outstanding[port] > max_write[port]) max_write[port] = write_outstanding[port];
        transactions[port]++;
        beats[port] += length;
        if (last_direction >= 0 && last_direction != int'(write)) direction_switches++;
        last_direction = int'(write);
    endtask

    always @(posedge clk_i) begin
        if (!rst_n_i) begin
            grants.delete();
            cycle = 0;
            outstanding = 0;
            max_outstanding = 0;
            direction_switches = 0;
            busy_cycles = 0;
            last_direction = -1;
            for (int p = 0; p < 7; p++) begin
                read_outstanding[p] = 0;
                write_outstanding[p] = 0;
                max_read[p] = 0;
                max_write[p] = 0;
                transactions[p] = 0;
                beats[p] = 0;
            end
        end else begin
            cycle++;
            if (outstanding != 0) busy_cycles++;
            if (bus.bvalid) begin
                outstanding--;
                write_outstanding[int'(bus.bid)>>1]--;
            end
            if (bus.rvalid && bus.rlast) begin
                outstanding--;
                read_outstanding[int'(bus.rid)>>1]--;
            end
            if (bus.awvalid && bus.awready)
                record_grant(1, int'(bus.awid)>>1, int'(bus.awlen)+1);
            if (bus.arvalid && bus.arready)
                record_grant(0, int'(bus.arid)>>1, int'(bus.arlen)+1);
        end
    end
endmodule
