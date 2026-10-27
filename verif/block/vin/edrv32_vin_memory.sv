// File: edrv32_vin_memory.sv
// Spec: SoC 4.2; vin-testplan 2, VI-07,09,11,14.
// Description: Byte-addressed AXI256 RAM with ordered queues, stalls and SLVERR injection.
// Clock domain: clk_mem. Test controls change on falling edges.
`timescale 1ns/1ps
module edrv32_vin_memory (
    input logic clk_i,
    input logic rst_n_i,
    edrv32_axi256_if bus
);
    typedef struct packed {
        bit [31:0] addr;
        int beats;
        int number;
    } command_t;
    byte unsigned mem[bit [31:0]];
    command_t writes[$];
    command_t reads[$];
    int responses[$];
    bit [31:0] ar_log[$];
    int ar_beats[$];
    bit [31:0] aw_addresses[$];
    int aw_lengths[$];
    int aw_count = 0;
    int b_count = 0;
    int ar_count = 0;
    int r_count = 0;
    int write_beat = 0;
    int read_beat = 0;
    int b_error_transaction = -1;
    int r_error_transaction = -1;
    int random_percent = 0;
    bit stop_write = 0;
    bit stop_read = 0;
    bit hold_b = 0;
    bit check_read_ready = 0;
    bit check_continuous_w = 0;
    bit in_write_burst = 0;
    bit b_taken = 0;
    bit r_taken = 0;
    bit [31:0] random_state = 32'hadc01234;

    function automatic bit [31:0] random_next(input bit [31:0] state_i);
        bit [31:0] value;
        value = state_i ^ (state_i << 13);
        value = value ^ (value >> 17);
        return value ^ (value << 5);
    endfunction

    function automatic byte unsigned peek(input bit [31:0] address_i);
        if (mem.exists(address_i) != 0) return mem[address_i];
        return 8'ha5;
    endfunction

    task automatic poke16(input bit [31:0] address_i,
        input logic [15:0] value_i);
        mem[address_i] = value_i[7:0];
        mem[address_i+1] = value_i[15:8];
    endtask

    always @(posedge clk_i) begin : capture
        command_t command;
        int response_number;
        b_taken = bus.bvalid && bus.bready;
        r_taken = bus.rvalid && bus.rready;
        if (!rst_n_i) begin
            mem.delete();
            writes.delete();
            reads.delete();
            responses.delete();
            ar_log.delete();
            ar_beats.delete();
            aw_addresses.delete();
            aw_lengths.delete();
            aw_count = 0;
            b_count = 0;
            ar_count = 0;
            r_count = 0;
            write_beat = 0;
            read_beat = 0;
            in_write_burst = 0;
        end else begin
            if (check_read_ready && !bus.rready)
                $fatal(1, "FAIL memory source RREADY expected=1 actual=0 time=%0t", $time);
            if (bus.awvalid && bus.awready) begin
                command.addr = bus.awaddr;
                command.beats = int'(bus.awlen)+1;
                command.number = aw_count++;
                writes.push_back(command);
                aw_addresses.push_back(bus.awaddr);
                aw_lengths.push_back(int'(bus.awlen)+1);
                if (bus.awid != 0)
                    $fatal(1, "FAIL local AWID expected=0 actual=%b time=%0t",
                        bus.awid, $time);
            end
            if (check_continuous_w && in_write_burst && !bus.wvalid)
                $fatal(1, "FAIL complete burst grant expected=WVALID actual=0 time=%0t",
                    $time);
            if (bus.wvalid && bus.wready) begin
                command = writes[0];
                for (int lane = 0; lane < 32; lane++) begin
                    if (bus.wstrb[lane])
                        mem[command.addr+32'(write_beat*32+lane)] = bus.wdata[lane*8+:8];
                end
                write_beat++;
                in_write_burst = !bus.wlast;
                if (bus.wlast) begin
                    responses.push_back(command.number);
                    command = writes.pop_front();
                    write_beat = 0;
                end
            end
            if (bus.bvalid && bus.bready) begin
                response_number = responses.pop_front();
                if (response_number != b_count)
                    $fatal(1, "FAIL B order expected=%0d actual=%0d time=%0t",
                        b_count, response_number, $time);
                b_count++;
            end
            if (bus.arvalid && bus.arready) begin
                command.addr = bus.araddr;
                command.beats = int'(bus.arlen)+1;
                command.number = ar_count++;
                reads.push_back(command);
                ar_log.push_back(bus.araddr);
                ar_beats.push_back(int'(bus.arlen)+1);
                if (bus.arid != 0)
                    $fatal(1, "FAIL local ARID expected=0 actual=%b time=%0t",
                        bus.arid, $time);
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
            bus.awready = !stop_write && int'(random_state[7:0])%100 >= random_percent;
            bus.wready = !stop_write && writes.size() != 0
                && int'(random_state[15:8])%100 >= random_percent;
            if (!bus.bvalid || b_taken) begin
                bus.bvalid = !hold_b && responses.size() != 0
                    && int'(random_state[23:16])%100 >= random_percent;
                bus.bid = 0;
                bus.bresp = (responses.size() != 0
                    && responses[0] == b_error_transaction) ? 2'b10 : 2'b00;
            end
            bus.arready = !stop_read && int'(random_state[31:24])%100 >= random_percent;
            if (!bus.rvalid || r_taken) begin
                bus.rvalid = !stop_read && reads.size() != 0
                    && int'(random_state[7:0])%100 >= random_percent;
                bus.rid = 0;
                bus.rdata = 0;
                bus.rlast = 0;
                bus.rresp = 0;
                if (reads.size() != 0) begin
                    command = reads[0];
                    bus.rlast = read_beat == command.beats-1;
                    bus.rresp = command.number == r_error_transaction ? 2'b10 : 2'b00;
                    for (int lane = 0; lane < 32; lane++)
                        bus.rdata[lane*8+:8] = peek(command.addr+32'(read_beat*32+lane));
                end
            end
        end
    end
endmodule
