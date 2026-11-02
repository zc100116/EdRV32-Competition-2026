// File: edrv32_ram_cpu_direction.v
// Spec: cpu-spec 4.4; CLAUDE.md 8.
// Description: Paired gshare counters, synchronous word write and asynchronous reads.
// Clock domain: clk_sys. Read data follows address and post-edge memory contents.
`include "edrv32_build_mode.vh"
module edrv32_ram_cpu_direction (
    // Clock and write port (no reset).
    input wire clk_i,
    input wire wr_en_i,
    input wire [10:0] wr_addr_i,
    input wire [3:0] wr_data_i,
    // Asynchronous read ports; update reads the write address.
    output wire [3:0] update_data_o,
    input wire [10:0] rd_addr_i,
    output wire [3:0] rd_data_o
);
`ifdef EDRV32_FPGA_MEMORY_MODE
    // fpga/ip/ip_lutram_cpu_direction.md: two simple dual-port copies share every write;
    // one reads the query address, the other the update (write) address.
    ip_lutram_cpu_direction u_ip_query (
        .wr_clk(clk_i),
        .rd_clk(clk_i),
        .rst(1'b0),
        .wr_en(wr_en_i),
        .wr_addr(wr_addr_i),
        .wr_data(wr_data_i),
        .rd_addr(rd_addr_i),
        .rd_data(rd_data_o)
    );
    ip_lutram_cpu_direction u_ip_update (
        .wr_clk(clk_i),
        .rd_clk(clk_i),
        .rst(1'b0),
        .wr_en(wr_en_i),
        .wr_addr(wr_addr_i),
        .wr_data(wr_data_i),
        .rd_addr(wr_addr_i),
        .rd_data(update_data_o)
    );
`else
    reg [3:0] memory_r [0:2047];
    integer entry;
    initial begin
        for (entry = 0; entry < 2048; entry = entry + 1)
            memory_r[entry] = 4'b0101;
    end
    assign update_data_o = memory_r[wr_addr_i];
    assign rd_data_o = memory_r[rd_addr_i];
    always @(posedge clk_i) begin
        if (wr_en_i)
            memory_r[wr_addr_i] <= wr_data_i;
    end
`endif
endmodule
