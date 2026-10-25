// edrv32_axi64_memory.sv
// SoC 4.1; one transaction per direction, randomized independent channel delays.
// Clock domain: clk_sys.
module edrv32_axi64_memory (
    // Clock and reset
    input logic clk_i,
    input logic rst_n_i,

    // AXI memory interface
    edrv32_axi64_if bus
);
    import edrv32_axi64_memory_pkg::*;
    bit reading;
    bit writing;
    bit [31:0] read_addr;
    bit [31:0] write_addr;
    int unsigned read_count;
    int unsigned write_count;
    int unsigned read_len;
    int unsigned write_len;
    int unsigned read_size;
    int unsigned write_size;
    int unsigned read_delay;
    int unsigned write_delay;
    bit read_error;
    bit write_error;
    int unsigned reads;
    int unsigned writes;

    always @(posedge clk_i) begin
        if (!rst_n_i) begin
            reading <= 0;
            writing <= 0;
            bus.arready <= 0;
            bus.awready <= 0;
            bus.wready <= 0;
            bus.rvalid <= 0;
            bus.bvalid <= 0;
            bus.rid <= 0;
            bus.bid <= 0;
            bus.rdata <= 0;
            bus.rresp <= 0;
            bus.bresp <= 0;
            bus.rlast <= 0;
            reads <= 0;
            writes <= 0;
            read_delay <= 0;
            write_delay <= 0;
        end else begin
            bus.arready <= !reading && (!random_stalls || $urandom_range(0, 1) != 0);
            bus.awready <= !writing && !bus.bvalid &&
                           (!random_stalls || $urandom_range(0, 1) != 0);
            bus.wready <= writing && (!random_stalls || $urandom_range(0, 1) != 0);
            if (bus.arvalid && bus.arready) begin
                reading <= 1;
                bus.arready <= 0;
                read_addr <= bus.araddr;
                read_len <= int'(bus.arlen);
                read_size <= int'(bus.arsize);
                read_count <= 0;
                read_delay <= $urandom_range(0, delay_max);
                read_error <= {bus.araddr[31:5], 5'b0} == error_read_addr;
                reads <= reads + 1;
            end
            if (reading && !bus.rvalid) begin
                if (read_delay != 0) read_delay <= read_delay - 1;
                else if (!random_stalls || $urandom_range(0, 1) != 0) begin
                    bus.rvalid <= 1;
                    bus.rdata <= read_data({read_addr[31:3], 3'b0}, 8);
                    bus.rresp <= read_error ? 2 : 0;
                    bus.rlast <= read_count == read_len;
                end
            end
            if (bus.rvalid && bus.rready) begin
                bus.rvalid <= 0;
                if (bus.rlast) reading <= 0;
                else begin
                    read_count <= read_count + 1;
                    read_addr <= read_addr + (32'b1 << read_size);
                    read_delay <= $urandom_range(0, delay_max);
                    // No bubbles in SRAM performance mode.
                    if (!random_stalls && delay_max == 0) begin
                        bus.rvalid <= 1;
                        bus.rdata <= read_data({read_addr[31:3], 3'b0} +
                                              (32'b1 << read_size), 8);
                        bus.rlast <= read_count + 1 == read_len;
                    end
                end
            end
            if (bus.awvalid && bus.awready) begin
                writing <= 1;
                bus.awready <= 0;
                write_addr <= bus.awaddr;
                write_len <= int'(bus.awlen);
                write_size <= int'(bus.awsize);
                write_count <= 0;
                write_error <= {bus.awaddr[31:5], 5'b0} == error_write_addr;
                writes <= writes + 1;
            end
            if (bus.wvalid && bus.wready) begin
                for (int i = 0; i < 8; i++) begin
                    if (bus.wstrb[i] && !write_error)
                        bus_store({write_addr[31:3], 3'b0} + 32'(i), bus.wdata[i*8 +: 8]);
                end
                if (write_count == write_len) begin
                    writing <= 0;
                    bus.wready <= 0;
                    write_delay <= $urandom_range(0, delay_max) + 1;
                end else begin
                    write_count <= write_count + 1;
                    write_addr <= write_addr + (32'b1 << write_size);
                end
            end
            if (write_delay != 0) begin
                write_delay <= write_delay - 1;
                if (write_delay == 1) begin
                    bus.bvalid <= 1;
                    bus.bresp <= write_error ? 2 : 0;
                end
            end
            if (bus.bvalid && bus.bready) bus.bvalid <= 0;
        end
    end
endmodule
