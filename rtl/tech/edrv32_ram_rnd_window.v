// File: edrv32_ram_rnd_window.v
// Spec: rnd-spec v0.3 5.2; CLAUDE.md 8.
// Description: One parity bank of the affine source window, 256 x 64 bits;
//              synchronous enabled read, undefined same-address read/write collision.
// Clock domain: clk_mem (clk_i).
`include "edrv32_build_mode.vh"
module edrv32_ram_rnd_window (
    // Clock.
    input wire clk_i,

    // Decoded source-pair write.
    input wire wr_en_i,
    input wire [7:0] wr_addr_i,
    input wire [63:0] wr_data_i,

    // One-cycle source-pair read.
    input wire rd_en_i,
    input wire [7:0] rd_addr_i,
    output wire [63:0] rd_data_o
);
`ifdef EDRV32_FPGA_MEMORY_MODE
    ip_ram_rnd_window u_ip (
        .wr_clk(clk_i),
        .wr_en(wr_en_i),
        .wr_addr({1'b0, wr_addr_i}),
        .wr_data(wr_data_i),
        .wr_rst(1'b0),
        .rd_clk(clk_i),
        .rd_clk_en(rd_en_i),
        .rd_rst(1'b0),
        .rd_addr({1'b0, rd_addr_i}),
        .rd_data(rd_data_o)
    );
`else
    reg [63:0] memory_r [0:255];
    reg [63:0] data_r;
    assign rd_data_o = data_r;
    always @(posedge clk_i) begin
        if (wr_en_i)
            memory_r[wr_addr_i] <= wr_data_i;
        if (rd_en_i)
            data_r <= memory_r[rd_addr_i];
    end
`endif
endmodule
