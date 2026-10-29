// File: edrv32_ram_rnd_palette.v
// Spec: rnd-spec 2.1 (palette), 5.2; CLAUDE.md 8.
// Description: Fixed DRM simple dual-port RAM for the RND palette: 256 x 32
// (generated 512 deep, upper address bit tied 0). Enabled reads have one-cycle
// latency; disabled reads hold. Same-cycle same-address data is undefined.
// Clock: clk_mem.
`include "edrv32_build_mode.vh"
module edrv32_ram_rnd_palette (
    // Clock.
    input wire clk_i,

    // Write port.
    input wire wr_en_i,
    input wire [7:0] wr_addr_i,
    input wire [31:0] wr_data_i,

    // Read port.
    input wire rd_en_i,
    input wire [7:0] rd_addr_i,
    output wire [31:0] rd_data_o
);
`ifdef EDRV32_FPGA_MEMORY_MODE
    ip_ram_rnd_palette u_ip (
        .wr_clk(clk_i),
        .wr_en(wr_en_i),
        .wr_addr({1'b0, wr_addr_i}),
        .wr_data(wr_data_i),
        // Generated IP resets are active-high; storage stays unreset.
        .wr_rst(1'b0),
        .rd_clk(clk_i),
        .rd_clk_en(rd_en_i),
        .rd_rst(1'b0),
        .rd_addr({1'b0, rd_addr_i}),
        .rd_data(rd_data_o)
    );
`else
    reg [31:0] memory_r [0:255];
    reg [31:0] rd_data_r;
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
