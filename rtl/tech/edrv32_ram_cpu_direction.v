// File: edrv32_ram_cpu_direction.v
// Spec: cpu-spec 4.4; CLAUDE.md 8.
// Description: Fixed distributed RAM, synchronous write and asynchronous read.
// Clock domain: clk_sys. Read data follows address and post-edge memory contents.
`include "edrv32_build_mode.vh"
module edrv32_ram_cpu_direction (
    // Clock and write port (no reset).
    input wire clk_i,
    input wire wr_en_i,
    input wire [11:0] wr_addr_i,
    input wire [1:0] wr_data_i,
    // Asynchronous read ports; update reads the write address.
    output wire [1:0] update_data_o,
    input wire [11:0] rd_addr_i,
    output wire [1:0] rd_data_o
);
`ifdef EDRV32_FPGA_MEMORY_MODE
    ip_ram_cpu_direction u_ip (
        .clk(clk_i),
        .wr_en(wr_en_i),
        .wr_addr(wr_addr_i),
        .wr_data(wr_data_i),
        .update_data(update_data_o),
        .rd_addr(rd_addr_i),
        .rd_data(rd_data_o)
    );
`else
    reg [1:0] memory_r [0:4095];
    integer entry;
    initial begin
        for (entry = 0; entry < 4096; entry = entry + 1)
            memory_r[entry] = 2'b01;
    end
    assign update_data_o = memory_r[wr_addr_i];
    assign rd_data_o = memory_r[rd_addr_i];
    always @(posedge clk_i) begin
        if (wr_en_i)
            memory_r[wr_addr_i] <= wr_data_i;
    end
`endif
endmodule
