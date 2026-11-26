// File: edrv32_ram_gpu_table.v
// Spec: gpu-microarch 4.15; CLAUDE.md 8.
// Description: Fixed 64x72 distributed RAM, synchronous write, combinational read.
// Users needing a registered read add their own output register; one instance per read port.
// Contents are not reset; same-address accesses are not used. Clock: clk_gpu.
`include "edrv32_build_mode.vh"
module edrv32_ram_gpu_table (
    // Clock.
    input wire clk_i,

    // Write port.
    input wire wr_en_i,
    input wire [5:0] wr_addr_i,
    input wire [71:0] wr_data_i,

    // Combinational read port.
    input wire [5:0] rd_addr_i,
    output wire [71:0] rd_data_o
);
`ifdef EDRV32_FPGA_MEMORY_MODE
    ip_lutram_gpu_table u_ip (
        .wr_clk(clk_i),
        .wr_en(wr_en_i),
        .wr_addr(wr_addr_i),
        .wr_data(wr_data_i),
        .rd_clk(clk_i),
        .rst(1'b0),
        .rd_addr(rd_addr_i),
        .rd_data(rd_data_o)
    );
`else
    reg [71:0] memory_r [0:63];
    assign rd_data_o = memory_r[rd_addr_i];
    always @(posedge clk_i) begin
        if (wr_en_i) memory_r[wr_addr_i] <= wr_data_i;
    end
`endif
endmodule
