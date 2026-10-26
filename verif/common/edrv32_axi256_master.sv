// File: edrv32_axi256_master.sv
// Spec: SoC 4.2; mem-subsys-testplan 2.2.
// Description: Queued requests, independent address/data issue and response backpressure.
// Clock domain: clk_mem.
`timescale 1ns/1ps
module edrv32_axi256_master #(
    parameter bit READ_ONLY = 0,
    parameter bit WRITE_ONLY = 0
) (
    input logic clk_i,
    input logic rst_n_i,
    output logic urgent_o,
    edrv32_axi256_if bus
);
    typedef struct packed {
        bit id;
        bit [31:0] addr;
        bit [3:0] len;
        bit [511:0][7:0] bytes;
        bit [15:0][31:0] strb;
    } transaction_t;
    transaction_t reads[$];
    transaction_t writes[$];
    transaction_t write_data[$];
    transaction_t read_active;
    transaction_t write_active;
    transaction_t data_active;
    bit ar_taken;
    bit aw_taken;
    bit w_taken;
    int data_beat;
    int data_gap = 0;
    int data_delay = 0;
    int data_wait;
    bit r_random = 0;
    bit b_random = 0;
    bit urgent_random = 0;
    bit [31:0] random_state = 1;
    int r_period = 1;
    int r_on = 1;
    int b_period = 1;
    int b_on = 1;
    int cycle;
    int reads_done;
    int writes_done;
    int r_beats;
    bit [1:0] expected_resp = 0;
    bit urgent_enable = 0;
    int urgent_period = 1;
    int urgent_on = 1;

    task automatic enqueue_read(input bit [31:0] addr,
        input int len,
                                input bit id = 0);
        transaction_t t;
        if (WRITE_ONLY) $fatal(1, "FAIL read on P1 time=%0t", $time);
        t = '0;
        t.addr = addr;
        t.len = 4'(len);
        t.id = id;
        reads.push_back(t);
    endtask

    task automatic enqueue_write(input bit [31:0] addr,
        input int len,
                                 input bit [255:0] data[16],
                                 input bit [31:0] strb[16],
        input bit id = 0);
        transaction_t t;
        if (READ_ONLY) $fatal(1, "FAIL write on P0 time=%0t", $time);
        t = '0;
        t.addr = addr;
        t.len = 4'(len);
        t.id = id;
        for (int n = 0; n <= len; n++) begin
            t.bytes[n*32 +: 32] = data[n];
            t.strb[n] = strb[n];
        end
        writes.push_back(t);
    endtask

    task automatic seed_random(input bit [31:0] seed);
        random_state = seed;
    endtask

    function automatic int unsigned random_next();
        random_state ^= random_state << 13;
        random_state ^= random_state >> 17;
        random_state ^= random_state << 5;
        return random_state;
    endfunction

    task automatic wait_done(input int nr,
        input int nw);
        wait (reads_done >= nr && writes_done >= nw);
        @(negedge clk_i);
    endtask

    // Drivers update on falling edges; monitors sample settled rising-edge wires.
    always @(negedge clk_i) begin
        if (!rst_n_i) begin
            bus.awid = 0;
            bus.awaddr = 0;
            bus.awlen = 0;
            bus.awvalid = 0;
            bus.wdata = 0;
            bus.wstrb = 0;
            bus.wlast = 0;
            bus.wvalid = 0;
            bus.bready = 0;
            bus.arid = 0;
            bus.araddr = 0;
            bus.arlen = 0;
            bus.arvalid = 0;
            bus.rready = 0;
            urgent_o = 0;
            cycle = 0;
            data_beat = 0;
            data_wait = 0;
        end else begin
            cycle++;
            if (ar_taken) bus.arvalid = 0;
            if (aw_taken) bus.awvalid = 0;
            if (w_taken) bus.wvalid = 0;
            bus.rready = !WRITE_ONLY && (r_random ? int'(random_next()%32'(r_period)) :
                         cycle % r_period) < r_on;
            bus.bready = !READ_ONLY && (b_random ? int'(random_next()%32'(b_period)) :
                         cycle % b_period) < b_on;
            urgent_o = urgent_enable && (urgent_random ?
                       int'(random_next()%32'(urgent_period)) : cycle % urgent_period) < urgent_on;
            if (!bus.arvalid && reads.size() != 0) begin
                read_active = reads.pop_front();
                bus.arid = $bits(bus.arid)'(read_active.id);
                bus.araddr = read_active.addr;
                bus.arlen = read_active.len;
                bus.arvalid = 1;
            end
            if (!bus.awvalid && writes.size() != 0) begin
                write_active = writes.pop_front();
                bus.awid = $bits(bus.awid)'(write_active.id);
                bus.awaddr = write_active.addr;
                bus.awlen = write_active.len;
                bus.awvalid = 1;
            end
            if (!bus.wvalid && data_wait == 0 && write_data.size() != 0) begin
                data_active = write_data[0];
                bus.wdata = data_active.bytes[data_beat*32 +: 32];
                bus.wstrb = data_active.strb[data_beat];
                bus.wlast = data_beat == int'(data_active.len);
                bus.wvalid = 1;
            end
            if (data_wait > 0) data_wait--;
        end
    end

    always @(posedge clk_i) begin
        if (!rst_n_i) begin
            reads.delete();
            writes.delete();
            write_data.delete();
            reads_done = 0;
            writes_done = 0;
            r_beats = 0;
            ar_taken = 0;
            aw_taken = 0;
            w_taken = 0;
        end else begin
            ar_taken = bus.arvalid && bus.arready;
            aw_taken = bus.awvalid && bus.awready;
            w_taken = bus.wvalid && bus.wready;
            if (bus.awvalid && bus.awready) begin
                write_data.push_back(write_active);
                if (write_data.size() == 1) data_wait = data_delay;
            end
            if (bus.wvalid && bus.wready) begin
                if (bus.wlast) begin
                    data_active = write_data.pop_front();
                    data_beat = 0;
                end else data_beat++;
                data_wait = data_gap;
            end
            if (bus.rvalid && bus.rready) begin
                r_beats++;
                if (bus.rresp != expected_resp)
                    $fatal(1, "FAIL RRESP expected=%0h actual=%0h time=%0t",
                           expected_resp, bus.rresp, $time);
                if (bus.rlast) reads_done++;
            end
            if (bus.bvalid && bus.bready) begin
                if (bus.bresp != expected_resp)
                    $fatal(1, "FAIL BRESP expected=%0h actual=%0h time=%0t",
                           expected_resp, bus.bresp, $time);
                writes_done++;
            end
        end
    end
endmodule
