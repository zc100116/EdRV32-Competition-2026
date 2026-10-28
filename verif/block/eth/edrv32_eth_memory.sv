// File: edrv32_eth_memory.sv
// Spec: SoC 4.2; eth-testplan 2, ET-05,10,11,14,15.
// Description: Ordered byte RAM, independent random stalls, fixed latency and response errors.
// Clock domain: clk_mem; test controls change away from rising edges.
`timescale 1ns/1ps
module edrv32_eth_memory (
    input logic clk_i,
    input logic rst_n_i,
    edrv32_axi256_if bus
);
    typedef struct packed {
        bit [31:0] addr;
        int beats;
        int number;
        int due;
    } command_t;
    typedef struct packed {
        int number;
        int due;
    } response_t;
    byte unsigned mem[bit [31:0]];
    command_t writes[$];
    command_t reads[$];
    response_t responses[$];
    int aw_count = 0;
    int b_count = 0;
    int ar_count = 0;
    int r_count = 0;
    int write_beat = 0;
    int read_beat = 0;
    int cycle = 0;
    int b_error_transaction = -1;
    int r_error_transaction = -1;
    bit [31:0] r_error_address = 32'hffffffff;
    int random_percent = 0;
    int read_latency = 0;
    int write_latency = 0;
    bit stop_write = 0;
    bit stop_read = 0;
    bit hold_b = 0;
    bit hold_r = 0;
    bit b_taken = 0;
    bit r_taken = 0;
    bit [31:0] random_state = 32'hadc01234;

    function automatic bit [31:0] random_next(input bit [31:0] state_i);
        bit [31:0] value;
        value = state_i ^ (state_i << 13);
        value = value ^ (value >> 17);
        return value ^ (value << 5);
    endfunction

    // Unwritten locations are explicitly initialized to the test sentinel 0xa5.
    function automatic byte unsigned peek(input bit [31:0] address_i);
        if (mem.exists(address_i) != 0) return mem[address_i];
        return 8'ha5;
    endfunction

    always @(posedge clk_i) begin : capture
        command_t command;
        response_t response;
        b_taken = bus.bvalid && bus.bready;
        r_taken = bus.rvalid && bus.rready;
        if (!rst_n_i) begin
            mem.delete();
            writes.delete();
            reads.delete();
            responses.delete();
            aw_count = 0;
            b_count = 0;
            ar_count = 0;
            r_count = 0;
            write_beat = 0;
            read_beat = 0;
            cycle = 0;
        end else begin
            cycle++;
            if (bus.awvalid && bus.awready) begin
                command.addr = bus.awaddr;
                command.beats = int'(bus.awlen)+1;
                command.number = aw_count++;
                command.due = cycle;
                writes.push_back(command);
                if (bus.awid != 0)
                    $fatal(1, "FAIL AWID expected=0 actual=%b time=%0t", bus.awid, $time);
            end
            if (bus.wvalid && bus.wready) begin
                command = writes[0];
                for (int lane = 0; lane < 32; lane++) begin
                    if (bus.wstrb[lane])
                        mem[command.addr+32'(write_beat*32+lane)] = bus.wdata[lane*8+:8];
                end
                write_beat++;
                if (bus.wlast) begin
                    response.number = command.number;
                    response.due = cycle + write_latency;
                    responses.push_back(response);
                    command = writes.pop_front();
                    write_beat = 0;
                end
            end
            if (bus.bvalid && bus.bready) begin
                void'(responses.pop_front());
                b_count++;
            end
            if (bus.arvalid && bus.arready) begin
                command.addr = bus.araddr;
                command.beats = int'(bus.arlen)+1;
                command.number = ar_count++;
                command.due = cycle + read_latency;
                reads.push_back(command);
                if (bus.arid != 0)
                    $fatal(1, "FAIL ARID expected=0 actual=%b time=%0t", bus.arid, $time);
            end
            if (bus.rvalid && bus.rready) begin
                read_beat++;
                if (bus.rlast) begin
                    command = reads.pop_front();
                    read_beat = 0;
                    r_count++;
                end
            end
        end
    end

    always @(negedge clk_i) begin : drive
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
            bus.awready = !stop_write && int'(random_state[7:0])%100 >= random_percent;
            bus.wready = !stop_write && writes.size() != 0
                && int'(random_state[15:8])%100 >= random_percent;
            if (!bus.bvalid || b_taken) begin
                bus.bvalid = !hold_b && responses.size() != 0
                    && responses[0].due <= cycle
                    && int'(random_state[23:16])%100 >= random_percent;
                bus.bid = 0;
                bus.bresp = (responses.size() != 0
                    && responses[0].number == b_error_transaction) ? 2'b10 : 2'b00;
            end
            bus.arready = !stop_read && int'(random_state[31:24])%100 >= random_percent;
            if (!bus.rvalid || r_taken) begin
                bus.rvalid = !hold_r && reads.size() != 0 && reads[0].due <= cycle
                    && int'(random_state[7:0])%100 >= random_percent;
                bus.rid = 0;
                bus.rdata = 0;
                bus.rlast = 0;
                bus.rresp = 0;
                if (reads.size() != 0) begin
                    bus.rlast = read_beat == reads[0].beats-1;
                    bus.rresp = (reads[0].number == r_error_transaction
                        || reads[0].addr == r_error_address) ? 2'b10 : 2'b00;
                    for (int lane = 0; lane < 32; lane++)
                        bus.rdata[lane*8+:8] = peek(reads[0].addr+32'(read_beat*32+lane));
                end
            end
        end
    end
endmodule
