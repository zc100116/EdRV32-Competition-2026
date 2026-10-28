// File: edrv32_geo_memory.sv
// Spec: SoC 4.2; geo-testplan 2, GE-07,09,10,12,13.
// Description: Byte-addressed AXI256 RAM, ordered per-request IDs, random handshakes,
//              fixed first-read latency, B delay, SLVERR injection and shared bandwidth.
// Clock domain: clk_mem. Test controls are set on falling edges.
`timescale 1ns/1ps
module edrv32_geo_memory (
    input logic clk_i,
    input logic rst_n_i,
    edrv32_axi256_if bus
);
    localparam int MEM_BYTES = 32 * 1024 * 1024;
    typedef struct packed {
        bit id;
        bit [31:0] addr;
        int beats;
        int due;
        bit error;
    } command_t;
    byte unsigned mem[0:MEM_BYTES-1];
    bit written[bit [31:0]];
    command_t writes[$];
    command_t reads[$];
    command_t responses[$];
    int cycle = 0;
    int aw_count = 0;
    int b_count = 0;
    int ar_count = 0;
    int r_count = 0;
    int r_beats = 0;
    int w_beats = 0;
    int source_ar_count = 0;
    int descriptor_ar_count = 0;
    int max_desc_read = -1;
    int write_beat = 0;
    int read_beat = 0;
    int read_latency = 3;
    int b_delay = 3;
    int random_percent = 35;
    int error_kind = 0;
    int r_error_transaction = -1;
    int b_error_transaction = -1;
    int desc_count = 1;
    bit injected = 0;
    bit bandwidth_limit = 0;
    bit stop_ar = 0;
    bit check_dependency = 0;
    bit b_taken = 0;
    bit r_taken = 0;
    int credits = 0;
    bit [31:0] random_state = 32'h6e012345;

    function automatic bit [31:0] random_next(input bit [31:0] state_i);
        bit [31:0] value;
        value = state_i ^ (state_i << 13);
        value = value ^ (value >> 17);
        return value ^ (value << 5);
    endfunction

    always @(posedge clk_i) begin : capture
        command_t command;
        bit descriptor;
        b_taken = bus.bvalid && bus.bready;
        r_taken = bus.rvalid && bus.rready;
        if (!rst_n_i) begin
            writes.delete();
            reads.delete();
            responses.delete();
            written.delete();
            cycle = 0;
            aw_count = 0;
            b_count = 0;
            ar_count = 0;
            r_count = 0;
            r_beats = 0;
            w_beats = 0;
            source_ar_count = 0;
            descriptor_ar_count = 0;
            max_desc_read = -1;
            write_beat = 0;
            read_beat = 0;
            credits = 0;
            injected = 0;
        end else begin
            cycle++;
            if (bandwidth_limit) begin
                // geo 7: 1.2 GB/s / 125 MHz = 9.6 B/cycle.
                // Credits are fifths of a byte; R and W share the same budget.
                credits += 48;
                if (credits > 320) credits = 320;
            end
            if (bus.awvalid && bus.awready) begin
                command = '0;
                command.id = bus.awid;
                command.addr = bus.awaddr;
                command.beats = int'(bus.awlen) + 1;
                aw_count++;
                command.error = !injected && (error_kind == 3
                    || aw_count - 1 == b_error_transaction);
                if (command.error) injected = 1;
                writes.push_back(command);
            end
            if (bus.wvalid && bus.wready) begin
                command = writes[0];
                for (int lane = 0; lane < 32; lane++) begin
                    if (bus.wstrb[lane]) begin
                        mem[command.addr + 32'(write_beat * 32 + lane)] =
                            bus.wdata[lane*8+:8];
                        written[command.addr + 32'(write_beat * 32 + lane)] = 1;
                    end
                end
                w_beats++;
                write_beat++;
                if (bandwidth_limit) credits -= 160;
                if (bus.wlast) begin
                    command.due = cycle + b_delay;
                    responses.push_back(command);
                    command = writes.pop_front();
                    write_beat = 0;
                end
            end
            if (b_taken) begin
                command = responses.pop_front();
                b_count++;
            end
            if (bus.arvalid && bus.arready) begin
                command = '0;
                command.id = bus.arid;
                command.addr = bus.araddr;
                command.beats = int'(bus.arlen) + 1;
                ar_count++;
                command.due = cycle + read_latency;
                descriptor = bus.araddr >= 32'h1000
                    && bus.araddr < 32'h1000 + 32'(desc_count * 64);
                if (descriptor) begin
                    descriptor_ar_count++;
                    if (int'((bus.araddr - 32'h1000) / 64) > max_desc_read) begin
                        // geo 2.5: prior writes drain before the next descriptor starts.
                        // Reads and writes belonging to that next descriptor may overlap.
                        if (check_dependency && b_count != aw_count)
                            $fatal(1, string'({"FAIL dependency desc=%0d coord=(-1,-1) ",
                                "expected_B=%0d actual_B=%0d time=%0t"}),
                                (bus.araddr - 32'h1000) / 64, aw_count, b_count, $time);
                        max_desc_read = int'((bus.araddr - 32'h1000) / 64);
                    end
                end else source_ar_count++;
                command.error = !injected && ((error_kind == 1 && descriptor)
                    || (error_kind == 2 && !descriptor)
                    || ar_count - 1 == r_error_transaction);
                if (command.error) injected = 1;
                reads.push_back(command);
            end
            if (r_taken) begin
                read_beat++;
                r_beats++;
                if (bandwidth_limit) credits -= 160;
                if (bus.rlast) begin
                    command = reads.pop_front();
                    read_beat = 0;
                    r_count++;
                end
            end
        end
    end

    always @(negedge clk_i) begin : drive
        command_t command;
        int reserved;
        random_state = random_next(random_state);
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
            bus.awready = int'(random_state[7:0]) % 100 >= random_percent;
            bus.arready = !stop_ar && int'(random_state[15:8]) % 100 >= random_percent;
            if (!bus.bvalid || b_taken) begin
                bus.bvalid = 0;
                if (responses.size() != 0) begin
                    command = responses[0];
                    bus.bvalid = cycle + 1 >= command.due
                        && int'(random_state[23:16]) % 100 >= random_percent;
                    bus.bid = command.id;
                    bus.bresp = command.error ? 2'b10 : 2'b00;
                end
            end
            if (!bus.rvalid || r_taken) begin
                bus.rvalid = 0;
                if (reads.size() != 0) begin
                    command = reads[0];
                    bus.rvalid = cycle + 1 >= command.due
                        && int'(random_state[31:24]) % 100 >= random_percent
                        && (!bandwidth_limit || credits >= 160);
                    bus.rid = command.id;
                    bus.rlast = read_beat == command.beats - 1;
                    bus.rresp = command.error ? 2'b10 : 2'b00;
                    for (int lane = 0; lane < 32; lane++)
                        bus.rdata[lane*8+:8] = mem[command.addr + 32'(read_beat * 32 + lane)];
                end
            end
            // Reserve held R payload bandwidth before granting a simultaneous W beat.
            reserved = bus.rvalid ? 160 : 0;
            bus.wready = writes.size() != 0
                && int'(random_state[23:16]) % 100 >= random_percent
                && (!bandwidth_limit || credits - reserved >= 160);
        end
    end
endmodule
