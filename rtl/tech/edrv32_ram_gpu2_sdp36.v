// File: edrv32_ram_gpu2_sdp36.v
// Spec: gpu-v2-spec 2.4/2.6; CLAUDE.md 8.
// Description: Fixed 1024x36 SDP DRM, one registered read, old-data collision.
//              No output register, reset, initialization or byte write enable.
// Clock domain: clk_gpu.
`include "edrv32_build_mode.vh"
module edrv32_ram_gpu2_sdp36 (
    // Clock.
    input wire clk_i,

    // One whole-word synchronous write point.
    input wire wr_en_i,
    input wire [9:0] wr_addr_i,
    input wire [35:0] wr_data_i,

    // Enabled synchronous read; output holds when disabled.
    input wire rd_en_i,
    input wire [9:0] rd_addr_i,
    output wire [35:0] rd_data_o
);
`ifdef EDRV32_FPGA_MEMORY_MODE
    ip_ram_gpu2_sdp36 u_ip (
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
    reg [35:0] memory_r [0:1023];
    reg [35:0] rd_data_r;
    always @(posedge clk_i) begin
        if (wr_en_i) memory_r[wr_addr_i] <= wr_data_i;
        if (rd_en_i) rd_data_r <= memory_r[rd_addr_i];
    end
    assign rd_data_o = rd_data_r;
`endif
endmodule
