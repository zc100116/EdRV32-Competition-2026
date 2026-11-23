// File: edrv32_ram_gpu_target_tail.v
// Spec: gpu-spec 2.1; GPU microarchitecture 4.8; CLAUDE.md 8.
// Description: Fixed 512x72 DRM simple dual-port RAM for the GPU render target.
// Enabled reads have two-cycle latency (array read plus output register) and read old data on
// collision. Contents and output data are not initialized or reset.
// Clock: clk_gpu.
`include "edrv32_build_mode.vh"
module edrv32_ram_gpu_target_tail (
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
    ip_ram_gpu_target_tail u_ip (
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
    reg [71:0] rd_array_r;
    reg [71:0] rd_data_r;
    assign rd_data_o = rd_data_r;
    always @(posedge clk_i) begin
        if (wr_en_i) begin
            memory_r[wr_addr_i] <= wr_data_i;
        end
        if (rd_en_i) begin
            rd_array_r <= memory_r[rd_addr_i];
        end
    end
    // Output register is always enabled, so a held read stays held one edge later.
    always @(posedge clk_i) begin
        rd_data_r <= rd_array_r;
    end
`endif
endmodule
