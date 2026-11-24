// File: edrv32_ram_gpu_delay.v
// Spec: gpu-spec 2.5, 2.13; S-2 delay storage; CLAUDE.md 8.
// Description: Fixed 512x72 DRM with enabled one-cycle read.
// Contents and read data are not reset; same-address accesses are not used.
// Clock: clk_gpu.
`include "edrv32_build_mode.vh"
module edrv32_ram_gpu_delay (
    // Clock.
    input wire clk_i,

    // Write port.
    input wire wr_en_i,
    input wire [8:0] wr_addr_i,
    input wire [71:0] wr_data_i,

    // Read port.
    input wire rd_en_i,
    input wire [8:0] rd_addr_i,
    output wire [71:0] rd_data_o
);
`ifdef EDRV32_FPGA_MEMORY_MODE
    ip_ram_gpu_delay u_ip (
        .wr_clk(clk_i),
        .wr_rst(1'b0),
        .wr_en(wr_en_i),
        .wr_addr(wr_addr_i),
        .wr_data(wr_data_i),
        .rd_clk(clk_i),
        .rd_rst(1'b0),
        .rd_clk_en(rd_en_i),
        .rd_addr(rd_addr_i),
        .rd_data(rd_data_o)
    );
`else
    reg [71:0] memory_r [0:511];
    reg [71:0] rd_data_r;
    assign rd_data_o = rd_data_r;
    always @(posedge clk_i) begin
        if (wr_en_i) memory_r[wr_addr_i] <= wr_data_i;
    end
    always @(posedge clk_i) begin
        if (rd_en_i) rd_data_r <= memory_r[rd_addr_i];
    end
`endif
endmodule
