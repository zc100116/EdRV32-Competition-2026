// File: edrv32_rnd_util_memory.sv
// Spec: rnd 5.2/7; RN-18 DDR first-read latency.
// Description: Ordered AXI256 RAM with captured physical-page translation.
// Clock domain: clk_mem. The RN-18 BFM's no-random-wait handshake timing is retained.
`timescale 1ns/1ps
module edrv32_rnd_util_memory (
    input logic clk_i,
    input logic rst_n_i,
    edrv32_axi256_if bus
);
    typedef struct packed {
        bit id;
        bit [31:0] addr;
        int beats;
        int due;
    } command_t;
    byte unsigned mem[0:16*1024*1024-1];
    int page_index[0:1048575];
    command_t writes[$];
    command_t reads[$];
    command_t responses[$];
    int cycle = 0;
    int write_beat = 0;
    int read_beat = 0;
    int read_latency;
    bit b_taken = 0;
    bit r_taken = 0;

    function automatic int offset(input bit [31:0] address_i);
        return page_index[address_i[31:12]] * 4096 + int'(address_i[11:0]);
    endfunction

    always @(posedge clk_i) begin : capture
        command_t command;
        b_taken = bus.bvalid && bus.bready;
        r_taken = bus.rvalid && bus.rready;
        if (!rst_n_i) begin
            writes.delete();
            reads.delete();
            responses.delete();
            cycle = 0;
            write_beat = 0;
            read_beat = 0;
        end else begin
            cycle++;
            if (bus.awvalid && bus.awready) begin
                command = '0;
                command.id = bus.awid;
                command.addr = bus.awaddr;
                command.beats = int'(bus.awlen) + 1;
                writes.push_back(command);
            end
            if (bus.wvalid && bus.wready) begin
                command = writes[0];
                for (int lane = 0; lane < 32; lane++) begin
                    if (bus.wstrb[lane])
                        mem[offset(command.addr + 32'(write_beat * 32 + lane))] =
                            bus.wdata[lane*8+:8];
                end
                write_beat++;
                if (bus.wlast) begin
                    command.due = cycle;
                    responses.push_back(command);
                    command = writes.pop_front();
                    write_beat = 0;
                end
            end
            if (b_taken) command = responses.pop_front();
            if (bus.arvalid && bus.arready) begin
                command = '0;
                command.id = bus.arid;
                command.addr = bus.araddr;
                command.beats = int'(bus.arlen) + 1;
                command.due = cycle + read_latency;
                reads.push_back(command);
            end
            if (r_taken) begin
                read_beat++;
                if (bus.rlast) begin
                    command = reads.pop_front();
                    read_beat = 0;
                end
            end
        end
    end

    always @(negedge clk_i) begin : drive
        command_t command;
        if (!rst_n_i) begin
            bus.awready = 0;
            bus.wready = 0;
            bus.bvalid = 0;
            bus.bid = 0;
            bus.bresp = 0;
            bus.arready = 0;
            bus.rvalid = 0;
            bus.rid = 0;
            bus.rresp = 0;
            bus.rlast = 0;
            bus.rdata = 0;
        end else begin
            bus.awready = 1;
            bus.arready = 1;
            if (!bus.bvalid || b_taken) begin
                bus.bvalid = 0;
                if (responses.size() != 0) begin
                    command = responses[0];
                    bus.bvalid = cycle + 1 >= command.due;
                    bus.bid = command.id;
                    bus.bresp = 0;
                end
            end
            if (!bus.rvalid || r_taken) begin
                bus.rvalid = 0;
                if (reads.size() != 0) begin
                    command = reads[0];
                    bus.rvalid = cycle + 1 >= command.due;
                    bus.rid = command.id;
                    bus.rlast = read_beat == command.beats - 1;
                    bus.rresp = 0;
                    for (int lane = 0; lane < 32; lane++)
                        bus.rdata[lane*8+:8] =
                            mem[offset(command.addr + 32'(read_beat * 32 + lane))];
                end
            end
            bus.wready = writes.size() != 0;
        end
    end
endmodule
