// File: edrv32_ram_cpu_btb.v
// Spec: cpu-spec 4.4; CLAUDE.md 8.
// Description: Fixed distributed RAM, synchronous write and asynchronous read.
// Clock domain: clk_sys. Read data follows address and post-edge memory contents.
`include "edrv32_build_mode.vh"
module edrv32_ram_cpu_btb (
    // Clock and write port (no reset).
    input wire clk_i,
    input wire wr_en_i,
    input wire [6:0] wr_addr_i,
    input wire [57:0] wr_data_i,
    // Asynchronous read ports; update reads the write address.
    input wire [6:0] rd_addr_i,
    output wire [57:0] rd_data_o
);
`ifdef EDRV32_FPGA_MEMORY_MODE
    ip_ram_cpu_btb u_ip (
        .clk(clk_i),
        .wr_en(wr_en_i),
        .wr_addr(wr_addr_i),
        .wr_data(wr_data_i),
        .rd_addr(rd_addr_i),
        .rd_data(rd_data_o)
    );
`else
    reg [57:0] memory_r [0:127];
    assign rd_data_o = memory_r[rd_addr_i];
    always @(posedge clk_i) begin
        if (wr_en_i)
            memory_r[wr_addr_i] <= wr_data_i;
    end
`endif
endmodule
