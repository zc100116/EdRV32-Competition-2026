// File: edrv32_ram_mem_xbar_w.v
// Spec: mem-subsys-spec 2.2, 7; CLAUDE.md 8.
// Description: Fixed DRM simple dual-port storage for the mem_xbar buffers.
// Enabled synchronous reads have one-cycle latency and read old data on collision.
// Contents and output data are not initialized or reset.
// Clock: clk_mem.
`include "edrv32_build_mode.vh"
module edrv32_ram_mem_xbar_w (
    // Clock.
    input wire clk_i,

    // Write port.
    input wire wr_en_i,
    input wire [3:0] wr_addr_i,
    input wire [287:0] wr_data_i,

    // Read port.
    input wire rd_en_i,
    input wire [3:0] rd_addr_i,
    output wire [287:0] rd_data_o
);
`ifdef EDRV32_FPGA_MEMORY_MODE
    ip_ram_mem_xbar_w u_ip (
        .wr_clk(clk_i),
        .wr_en(wr_en_i),
        .wr_addr(wr_addr_i),
        .wr_data(wr_data_i),
        .rd_clk(clk_i),
        .rd_en(rd_en_i),
        .rd_addr(rd_addr_i),
        .rd_data(rd_data_o)
    );
`else
    reg [287:0] memory_r [0:15];
    reg [287:0] rd_data_r;
    assign rd_data_o = rd_data_r;
    always @(posedge clk_i) begin
        if (wr_en_i) begin
            memory_r[wr_addr_i] <= wr_data_i;
        end
        if (rd_en_i) begin
            rd_data_r <= memory_r[rd_addr_i];
        end
    end
`endif
endmodule
