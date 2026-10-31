// File: edrv32_rnd_memory.sv
// Spec: SoC 4.2; rnd-testplan 2, RN-14–16,18,19.
// Description: Byte-addressed AXI256 RAM, ordered per-request IDs, random handshakes,
//              fixed first-read latency, B delay and address-selected SLVERR injection.
// Clock domain: clk_mem. Test controls are set on falling edges.
`timescale 1ns/1ps
module edrv32_rnd_memory (
    input logic clk_i,
    input logic rst_n_i,
    edrv32_axi256_if bus
);
    typedef struct packed {
        bit id;
        bit [31:0] addr;
        int beats;
        int due;
        bit error;
    } command_t;
    byte unsigned mem[0:16*1024*1024-1];
    int memory_size;
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
    int target_ar_count = 0;
    int parameter_ar_count = 0;
    int image_ar_count = 0;
    int parameter_beats = 0;
    int image_beats = 0;
    int descriptor_ar_count = 0;
    int max_desc_read = -1;
    int write_beat = 0;
    int read_beat = 0;
    int read_latency = 3;
    int b_delay = 3;
    int random_percent = 35;
    int error_kind = 0;
    int desc_count = 1;
    bit injected = 0;
    bit check_dependency = 1;
    bit b_taken = 0;
    bit r_taken = 0;
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
            target_ar_count = 0;
            parameter_ar_count = 0;
            image_ar_count = 0;
            parameter_beats = 0;
            image_beats = 0;
            descriptor_ar_count = 0;
            max_desc_read = -1;
            write_beat = 0;
            read_beat = 0;
            injected = 0;
        end else begin
            cycle++;
            if (bus.awvalid && bus.awready) begin
                if (bus.awaddr + (32'(bus.awlen) + 1) * 32 > 32'(memory_size))
                    $fatal(1, "FAIL AW memory extent expected_end=%0d actual_end=%0d time=%0t",
                        memory_size, bus.awaddr + (32'(bus.awlen) + 1) * 32, $time);
                command = '0;
                command.id = bus.awid;
                command.addr = bus.awaddr;
                command.beats = int'(bus.awlen) + 1;
                aw_count++;
                command.error = !injected && error_kind == 5;
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
                if (bus.araddr + (32'(bus.arlen) + 1) * 32 > 32'(memory_size))
                    $fatal(1, "FAIL AR memory extent expected_end=%0d actual_end=%0d time=%0t",
                        memory_size, bus.araddr + (32'(bus.arlen) + 1) * 32, $time);
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
                        // rnd 5.1: prior writes drain before the next descriptor starts.
                        // Reads and writes belonging to that next descriptor may overlap.
                        if (check_dependency && b_count != aw_count)
                            $fatal(1, "%s expected_B=%0d actual_B=%0d time=%0t",
                                $sformatf("FAIL dependency desc=%0d coord=(-1,-1)",
                                    (bus.araddr - 32'h1000) / 64), aw_count, b_count, $time);
                        max_desc_read = int'((bus.araddr - 32'h1000) / 64);
                    end
                end else begin
                    source_ar_count++;
                    if (bus.araddr >= 32'h10000 && bus.araddr < 32'h18000)
                        target_ar_count++;
                end
                if (bus.araddr >= 32'h48000 && bus.araddr < 32'h50000)
                    parameter_ar_count++;
                if (bus.araddr >= 32'h20000 && bus.araddr < 32'h48000)
                    image_ar_count++;
                // RN-15/28: one selected descriptor/source/target/palette read transaction.
                command.error = !injected && ((error_kind == 1 && descriptor)
                    || (error_kind == 2 && bus.araddr >= 32'h20000
                        && bus.araddr < 32'h40000)
                    || (error_kind == 3 && bus.araddr >= 32'h10000
                        && bus.araddr < 32'h18000)
                    || (error_kind == 4 && bus.araddr >= 32'h50000
                        && bus.araddr < 32'h50400)
                    || (error_kind == 6 && bus.araddr >= 32'h48000
                        && bus.araddr < 32'h50000));
                if (command.error) injected = 1;
                reads.push_back(command);
            end
            if (r_taken) begin
                read_beat++;
                r_beats++;
                if (reads[0].addr >= 32'h48000 && reads[0].addr < 32'h50000)
                    parameter_beats++;
                if (reads[0].addr >= 32'h20000 && reads[0].addr < 32'h48000)
                    image_beats++;
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
            bus.arready = int'(random_state[15:8]) % 100 >= random_percent;
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
                        && int'(random_state[31:24]) % 100 >= random_percent;
                    bus.rid = command.id;
                    bus.rlast = read_beat == command.beats - 1;
                    bus.rresp = command.error ? 2'b10 : 2'b00;
                    for (int lane = 0; lane < 32; lane++)
                        bus.rdata[lane*8+:8] = mem[command.addr + 32'(read_beat * 32 + lane)];
                end
            end
            bus.wready = writes.size() != 0
                && int'(random_state[23:16]) % 100 >= random_percent;
        end
    end
endmodule
