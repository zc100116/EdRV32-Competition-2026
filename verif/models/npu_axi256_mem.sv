// File: npu_axi256_mem.sv
// Spec: npu-testplan 2.3; SoC 4.2.
// Description: Ordered sparse AXI256 memory with write visibility at B assertion.
//              Timing, response errors and image segments are selected by plusargs.
// Clock domain: clk_mem.
`timescale 1ns/1ps
module npu_axi256_mem (
    input logic clk_i,
    input logic rst_n_i,
    edrv32_axi256_if bus
);
    typedef struct packed {
        bit id;
        bit [31:0] addr;
        int beats;
        int due;
        int received;
        bit error;
        bit [15:0][255:0] data;
        bit [15:0][31:0] strb;
    } command_t;
    command_t reads[$];
    command_t writes[$];
    byte unsigned memory[bit [31:0]];
    string mode = "zero";
    int latency = 94;
    int b_delay = 1;
    int max_outstanding = 8;
    int bandwidth_mbps = 1400;
    int mem_mhz = 125;
    int cycle;
    int read_beat;
    int tokens;
    int read_outstanding;
    int write_outstanding;
    int peak_reads;
    int peak_writes;
    longint unsigned read_beats;
    longint unsigned write_beats;
    int first_request;
    int last_response;
    bit started;
    bit read_error_enable = 0;
    bit write_error_enable = 0;
    bit [31:0] read_error_first;
    bit [31:0] read_error_last;
    bit [31:0] write_error_first;
    bit [31:0] write_error_last;

    function automatic byte unsigned peek(input bit [31:0] addr);
        if (memory.exists(addr) != 0) return memory[addr];
        return 0;
    endfunction

    task automatic poke(input bit [31:0] addr, input byte unsigned value);
        memory[addr] = value;
    endtask

    // File addresses are beat indices; byte zero is the least significant byte.
    task automatic load_hex(input string path);
        int fd;
        int status;
        string word;
        bit [31:0] beat_addr;
        bit [255:0] data;
        fd = $fopen(path, "r");
        if (fd == 0) $fatal(1, "FAIL cannot open image %s time=%0t", path, $time);
        beat_addr = 0;
        while ($fscanf(fd, "%s", word) == 1) begin
            if (word.substr(0, 0) == "@") begin
                status = $sscanf(word.substr(1, word.len()-1), "%h", beat_addr);
            end else begin
                status = $sscanf(word, "%h", data);
                for (int b = 0; b < 32; b++) poke(beat_addr*32+32'(b), data[b*8 +: 8]);
                beat_addr++;
            end
            if (status != 1) $fatal(1, "FAIL image %s token=%s time=%0t", path, word, $time);
        end
        $fclose(fd);
    endtask

    function automatic int elapsed_cycles();
        return started ? last_response-first_request+1 : 0;
    endfunction

    initial begin : configure
        string path;
        void'($value$plusargs("MEM_MODE=%s", mode));
        void'($value$plusargs("MEM_LAT=%d", latency));
        void'($value$plusargs("MEM_B_DELAY=%d", b_delay));
        void'($value$plusargs("MEM_OUTST=%d", max_outstanding));
        void'($value$plusargs("MEM_BW_MBPS=%d", bandwidth_mbps));
        void'($value$plusargs("MEM_MHZ=%d", mem_mhz));
        read_error_enable = $value$plusargs("MEM_RERR_FIRST=%h", read_error_first);
        if (read_error_enable && !$value$plusargs("MEM_RERR_LAST=%h", read_error_last))
            $fatal(1, "FAIL MEM_RERR_LAST missing time=%0t", $time);
        write_error_enable = $value$plusargs("MEM_WERR_FIRST=%h", write_error_first);
        if (write_error_enable && !$value$plusargs("MEM_WERR_LAST=%h", write_error_last))
            $fatal(1, "FAIL MEM_WERR_LAST missing time=%0t", $time);
        case (mode)
            "zero": latency = 1;
            "latency", "bw": begin end
            default: $fatal(1, "FAIL unknown MEM_MODE=%s time=%0t", mode, $time);
        endcase
        if ($value$plusargs("MEM_MODEL_HEX=%s", path)) load_hex(path);
        if ($value$plusargs("MEM_DESC_HEX=%s", path)) load_hex(path);
        if ($value$plusargs("MEM_INPUT_HEX=%s", path)) load_hex(path);
        if ($value$plusargs("MEM_WORK_HEX=%s", path)) load_hex(path);
        if ($value$plusargs("MEM_OUTPUT_HEX=%s", path)) load_hex(path);
        if ($value$plusargs("MEM_STATE_HEX=%s", path)) load_hex(path);
    end

    always_comb begin
        bus.arready = rst_n_i && read_outstanding < max_outstanding;
        bus.awready = rst_n_i && write_outstanding < max_outstanding;
        bus.wready = 0;
        for (int n = 0; n < writes.size(); n++) begin
            if (writes[n].received < writes[n].beats) bus.wready = rst_n_i &&
                (mode != "bw" || tokens >= 32*mem_mhz);
        end
    end

    // Responses remain stable under master backpressure. Queue slots retire at handshake.
    always @(posedge clk_i) begin : service
        command_t cmd;
        int slot;
        bit [255:0] data;
        if (!rst_n_i) begin
            reads.delete();
            writes.delete();
            cycle = 0;
            read_beat = 0;
            tokens = 0;
            read_outstanding = 0;
            write_outstanding = 0;
            peak_reads = 0;
            peak_writes = 0;
            read_beats = 0;
            write_beats = 0;
            first_request = 0;
            last_response = 0;
            started = 0;
            bus.rvalid <= 0;
            bus.rid <= 0;
            bus.rdata <= 0;
            bus.rresp <= 0;
            bus.rlast <= 0;
            bus.bvalid <= 0;
            bus.bid <= 0;
            bus.bresp <= 0;
        end else begin
            cycle++;
            if (bus.rvalid && bus.rready) begin
                read_beats++;
                last_response = cycle;
                if (bus.rlast) begin
                    cmd = reads.pop_front();
                    read_outstanding--;
                    read_beat = 0;
                end else read_beat++;
                bus.rvalid <= 0;
            end
            if (bus.bvalid && bus.bready) begin
                cmd = writes.pop_front();
                write_outstanding--;
                last_response = cycle;
                bus.bvalid <= 0;
            end
            if (bus.wvalid && bus.wready) begin
                slot = 0;
                while (writes[slot].received == writes[slot].beats) slot++;
                cmd = writes[slot];
                cmd.data[cmd.received] = bus.wdata;
                cmd.strb[cmd.received] = bus.wstrb;
                cmd.received++;
                if (cmd.received == cmd.beats) cmd.due = cycle+b_delay;
                writes[slot] = cmd;
                write_beats++;
                if (mode == "bw") tokens -= 32*mem_mhz;
            end
            if (mode == "bw") begin
                tokens += bandwidth_mbps;
                if (tokens > 64*mem_mhz) tokens = 64*mem_mhz;
            end
            if ((!bus.bvalid || bus.bready) && writes.size() != 0 &&
                writes[0].received == writes[0].beats && cycle >= writes[0].due) begin
                cmd = writes[0];
                for (int n = 0; n < cmd.beats; n++) begin
                    for (int b = 0; b < 32; b++) begin
                        if (cmd.strb[n][b]) poke(cmd.addr+32'(n*32+b), cmd.data[n][b*8 +: 8]);
                    end
                end
                bus.bid <= cmd.id;
                bus.bresp <= cmd.error ? 2'b10 : 2'b00;
                bus.bvalid <= 1;
            end
            if (bus.arvalid && bus.arready) begin
                cmd = '0;
                cmd.id = bus.arid;
                cmd.addr = bus.araddr;
                cmd.beats = int'(bus.arlen)+1;
                cmd.due = cycle+latency-1;
                cmd.error = read_error_enable && cmd.addr <= read_error_last &&
                    cmd.addr+32'(cmd.beats*32-1) >= read_error_first;
                reads.push_back(cmd);
                read_outstanding++;
            end
            if ((!bus.rvalid || bus.rready) && reads.size() != 0 &&
                cycle >= reads[0].due && (mode != "bw" || tokens >= 32*mem_mhz)) begin
                cmd = reads[0];
                for (int b = 0; b < 32; b++)
                    data[b*8 +: 8] = peek(cmd.addr+32'(read_beat*32+b));
                bus.rid <= cmd.id;
                bus.rdata <= data;
                bus.rresp <= cmd.error ? 2'b10 : 2'b00;
                bus.rlast <= read_beat == cmd.beats-1;
                bus.rvalid <= 1;
                if (mode == "bw") tokens -= 32*mem_mhz;
            end
            if (bus.awvalid && bus.awready) begin
                cmd = '0;
                cmd.id = bus.awid;
                cmd.addr = bus.awaddr;
                cmd.beats = int'(bus.awlen)+1;
                cmd.error = write_error_enable && cmd.addr <= write_error_last &&
                    cmd.addr+32'(cmd.beats*32-1) >= write_error_first;
                writes.push_back(cmd);
                write_outstanding++;
            end
            if (read_outstanding > peak_reads) peak_reads = read_outstanding;
            if (write_outstanding > peak_writes) peak_writes = write_outstanding;
            if (!started && ((bus.arvalid && bus.arready) ||
                (bus.awvalid && bus.awready))) begin
                first_request = cycle;
                started = 1;
            end
        end
    end
endmodule
