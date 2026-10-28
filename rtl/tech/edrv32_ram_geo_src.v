// File: edrv32_ram_geo_src.v
// Spec: geo-spec 5.2, 7, 9 #1-2; CLAUDE.md 8.
// Description: Fixed DRM simple dual-port RAM for one GEO source-buffer bank:
// 256x128 write port (8 RGB565 pixels), 2048x16 read port (1 pixel). Read
// address r selects bits [16*r[2:0] +: 16] of write entry r[10:3]. Enabled
// reads have one-cycle latency; same-cycle same-address read data is undefined.
// Clock: clk_mem.
`include "edrv32_build_mode.vh"
module edrv32_ram_geo_src (
    // Clock.
    input wire clk_i,

    // Write port.
    input wire wr_en_i,
    input wire [7:0] wr_addr_i,
    input wire [127:0] wr_data_i,

    // Read port.
    input wire rd_en_i,
    input wire [10:0] rd_addr_i,
    output wire [15:0] rd_data_o
);
`ifdef EDRV32_FPGA_MEMORY_MODE
    ip_ram_geo_src u_ip (
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
    reg [127:0] memory_r [0:255];
    reg [15:0] rd_array_r;
    assign rd_data_o = rd_array_r;
    always @(posedge clk_i) begin
        if (wr_en_i) begin
            memory_r[wr_addr_i] <= wr_data_i;
        end
        if (rd_en_i) begin
            rd_array_r <= memory_r[rd_addr_i[10:3]][{rd_addr_i[2:0], 4'b0} +: 16];
        end
    end
`endif
endmodule
