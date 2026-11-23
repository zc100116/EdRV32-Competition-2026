// File: edrv32_gpu_memory.sv
// Spec: gpu-testplan 2; SoC 4.2.
// Description: Byte-addressed AXI256 DDR with seeded random request stalls and delays.
//              Writes become visible before B; error injection selects one byte address.
// Clock domain: clk_gpu.
`timescale 1ns/1ps
module edrv32_gpu_memory (
    input logic clk_i,
    input logic rst_n_i,
    edrv32_axi256_if bus
);
    byte unsigned memory[bit [31:0]];
    bit [31:0] random_r;
    int latency = 3;
    int jitter = 5;
    int read_wait;
    int write_wait;
    bit reading;
    bit writing;
    bit write_complete;
    bit read_id;
    bit write_id;
    bit [31:0] read_addr;
    bit [31:0] write_addr;
    int read_left;
    int write_left;
    bit read_error_enable;
    bit write_error_enable;
    bit [31:0] read_error_address;
    bit [31:0] write_error_address;
    bit [1:0] write_response;
    bit [1:0] read_response;
    bit [31:0] read_error_last;
    bit [31:0] write_error_last;
    int read_error_nth = 0;
    int write_error_nth = 0;
    int read_transactions;
    int write_transactions;

    initial begin
        random_r = 1;
        void'($value$plusargs("SEED=%d", random_r));
        void'($value$plusargs("MEM_LAT=%d", latency));
        void'($value$plusargs("MEM_JITTER=%d", jitter));
        read_error_enable = $value$plusargs("MEM_RERR=%h", read_error_address);
        write_error_enable = $value$plusargs("MEM_WERR=%h", write_error_address);
        read_error_last = read_error_address;
        write_error_last = write_error_address;
        void'($value$plusargs("MEM_RERR_LAST=%h", read_error_last));
        void'($value$plusargs("MEM_WERR_LAST=%h", write_error_last));
        void'($value$plusargs("MEM_RERR_NTH=%d", read_error_nth));
        void'($value$plusargs("MEM_WERR_NTH=%d", write_error_nth));
    end

    function automatic byte unsigned peek(input bit [31:0] address);
        return memory[address];
    endfunction

    task automatic load(input string path, input bit [31:0] base, input int words);
        int fd;
        bit [31:0] word_data;
        fd = $fopen(path, "r");
        if (fd == 0) $fatal(1, "FAIL cannot open %s", path);
        for (int n = 0; n < words; n++) begin
            if ($fscanf(fd, "%h", word_data) != 1)
                $fatal(1, "FAIL truncated DDR image word=%0d", n);
            for (int b = 0; b < 4; b++) memory[base+32'(n*4+b)] = word_data[b*8 +: 8];
        end
        $fclose(fd);
    endtask

    task automatic dump(input string path, input bit [31:0] base, input int words);
        int fd;
        bit [31:0] word_data;
        fd = $fopen(path, "w");
        if (fd == 0) $fatal(1, "FAIL cannot open %s", path);
        for (int n = 0; n < words; n++) begin
            for (int b = 0; b < 4; b++) word_data[b*8 +: 8] = peek(base+32'(n*4+b));
            $fdisplay(fd, "%08x", word_data);
        end
        $fclose(fd);
    endtask

    assign bus.arready = rst_n_i && !reading && random_r[0];
    assign bus.awready = rst_n_i && !writing && random_r[1];
    assign bus.wready = rst_n_i && writing && !write_complete && random_r[2];

    always @(posedge clk_i) begin : service
        bit [255:0] data;
        if (!rst_n_i) begin
            reading = 0;
            writing = 0;
            write_complete = 0;
            read_wait = 0;
            write_wait = 0;
            read_left = 0;
            write_left = 0;
            read_addr = 0;
            write_addr = 0;
            read_id = 0;
            write_id = 0;
            write_response = 0;
            read_response = 0;
            read_transactions = 0;
            write_transactions = 0;
            bus.rvalid <= 0;
            bus.rdata <= 0;
            bus.rid <= 0;
            bus.rresp <= 0;
            bus.rlast <= 0;
            bus.bvalid <= 0;
            bus.bid <= 0;
            bus.bresp <= 0;
        end else begin
            random_r <= {random_r[30:0],
                            random_r[31] ^ random_r[21] ^ random_r[1] ^ random_r[0]};
            if (bus.rvalid && bus.rready) begin
                bus.rvalid <= 0;
                read_addr = read_addr+32;
                read_left--;
                read_wait = latency + int'(random_r[7:4]) % (jitter+1);
                if (read_left == 0) reading = 0;
            end
            if (bus.bvalid && bus.bready) begin
                bus.bvalid <= 0;
                writing = 0;
                write_complete = 0;
            end
            if (bus.arvalid && bus.arready) begin
                read_transactions++;
                read_response = ((read_error_enable && bus.araddr <= read_error_last &&
                    read_error_address < bus.araddr+32'(32*(int'(bus.arlen)+1))) ||
                    (read_error_nth != 0 && read_transactions == read_error_nth)) ? 2 : 0;
                reading = 1;
                read_addr = bus.araddr;
                read_left = int'(bus.arlen)+1;
                read_id = bus.arid;
                read_wait = latency + int'(random_r[11:8]) % (jitter+1);
            end
            if (bus.awvalid && bus.awready) begin
                writing = 1;
                write_addr = bus.awaddr;
                write_left = int'(bus.awlen)+1;
                write_id = bus.awid;
                write_transactions++;
                write_response = ((write_error_enable && bus.awaddr <= write_error_last &&
                    write_error_address < bus.awaddr+32'(32*(int'(bus.awlen)+1))) ||
                    (write_error_nth != 0 && write_transactions == write_error_nth)) ? 2 : 0;
            end
            if (bus.wvalid && bus.wready) begin
                for (int b = 0; b < 32; b++)
                    if (bus.wstrb[b]) memory[write_addr+32'(b)] = bus.wdata[b*8 +: 8];
                write_addr = write_addr+32;
                write_left--;
                if (write_left == 0) begin
                    write_complete = 1;
                    write_wait = latency + int'(random_r[15:12]) % (jitter+1);
                end
            end
            if (reading && !bus.rvalid) begin
                if (read_wait != 0) read_wait--;
                else begin
                    for (int b = 0; b < 32; b++) data[b*8 +: 8] = peek(read_addr+32'(b));
                    bus.rdata <= data;
                    bus.rid <= read_id;
                    bus.rlast <= read_left == 1;
                    bus.rresp <= read_response;
                    bus.rvalid <= 1;
                end
            end
            if (write_complete && !bus.bvalid) begin
                if (write_wait != 0) write_wait--;
                else begin
                    bus.bid <= write_id;
                    bus.bresp <= write_response;
                    bus.bvalid <= 1;
                end
            end
        end
    end
endmodule
