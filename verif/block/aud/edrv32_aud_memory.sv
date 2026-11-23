// File: edrv32_aud_memory.sv
// Spec: aud-spec 2.2, 2.3, 6; aud-testplan 2.
// Description: AXI256 read memory with random AR stalls and inter-beat latency.
//              The test owns the ring mirror and controls one injected SLVERR transaction.
// Clock domain: clk_mem.
`timescale 1ns/1ps
module edrv32_aud_memory (
    input logic clk_i,
    input logic rst_n_i,
    edrv32_axi256_if bus
);
    logic [31:0] memory[bit [31:0]];
    bit inject_error;
    bit hold_reads = 0;
    bit active;
    bit response_error;
    bit id;
    bit [31:0] addr;
    int left_beats;
    int delay_cycles;
    int requests;
    int completed;
    int returned_frames;
    int max_delay = 24;
    int ring_base;
    int ring_size;
    int producer;
    int consumer;
    int ring_end_splits;
    int page_end_splits;
    int short_reads;
    bit enabled;
    bit stopped;

    always @(negedge clk_i) begin
        bus.arready = rst_n_i && !active && !hold_reads && $urandom_range(0, 3) != 0;
    end

    always @(posedge clk_i) begin : serve
        int bytes_read;
        int available;
        if (!rst_n_i) begin
            active = 0;
            bus.rvalid <= 0;
            bus.rlast <= 0;
            bus.rdata <= 0;
            bus.rresp <= 0;
            bus.rid <= 0;
            requests = 0;
            completed = 0;
            returned_frames = 0;
            ring_end_splits = 0;
            page_end_splits = 0;
            short_reads = 0;
        end else begin
            if (bus.rvalid && bus.rready) begin
                bus.rvalid <= 0;
                returned_frames += 8;
                left_beats--;
                addr += 32;
                delay_cycles = int'($urandom_range(0, max_delay));
                if (left_beats == 0) begin
                    active = 0;
                    completed++;
                end
            end
            if (bus.arvalid && bus.arready) begin
                if (active || !enabled || stopped)
                    $fatal(1, "FAIL DMA request active=%b enable=%b stopped=%b time=%0t",
                        active, enabled, stopped, $time);
                bytes_read = (int'(bus.arlen)+1)*32;
                available = (producer-consumer+ring_size)%ring_size;
                if (bus.araddr != 32'(ring_base+consumer) || bytes_read > available ||
                    consumer+bytes_read > ring_size)
                    $fatal(1, "FAIL ring AR addr=%h expected=%h bytes=%0d avail=%0d time=%0t",
                        bus.araddr, ring_base+consumer, bytes_read, available, $time);
                if (consumer+bytes_read == ring_size) ring_end_splits++;
                if (int'(bus.araddr[11:0])+bytes_read == 4096) page_end_splits++;
                if (bytes_read < 512) short_reads++;
                consumer = (consumer+bytes_read)%ring_size;
                active = 1;
                response_error = inject_error;
                inject_error = 0;
                id = bus.arid;
                addr = bus.araddr;
                left_beats = int'(bus.arlen)+1;
                delay_cycles = int'($urandom_range(1, max_delay));
                requests++;
            end
            if (active && !bus.rvalid) begin
                if (delay_cycles > 0) delay_cycles--;
                else begin
                    for (int n = 0; n < 8; n++) bus.rdata[n*32 +: 32] <= memory[addr+32'(n*4)];
                    bus.rid <= id;
                    bus.rresp <= response_error ? 2'b10 : 2'b00;
                    bus.rlast <= left_beats == 1;
                    bus.rvalid <= 1;
                end
            end
        end
    end
endmodule
