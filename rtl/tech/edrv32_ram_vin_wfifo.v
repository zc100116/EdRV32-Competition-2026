// File: edrv32_ram_vin_wfifo.v
// Spec: vin-spec 2.3, 2.6, 9 #1; CLAUDE.md 8.
// Description: Fixed 512x288 DRM simple dual-port RAM for VIN FIFO storage.
// Enabled reads have one-cycle latency; same-cycle same-address read data is
// undefined. Contents and output data are not initialized or reset.
// Clock: clk_mem.
`include "edrv32_build_mode.vh"
module edrv32_ram_vin_wfifo (
    // Clock.
    input wire clk_i,

    // Write port.
    input wire wr_en_i,
    input wire [8:0] wr_addr_i,
    input wire [287:0] wr_data_i,

    // Read port.
    input wire rd_en_i,
    input wire [8:0] rd_addr_i,
    output wire [287:0] rd_data_o
);
`ifdef EDRV32_FPGA_MEMORY_MODE
    ip_ram_vin_wfifo u_ip (
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
    reg [287:0] memory_r [0:511];
    reg [287:0] rd_array_r;
    assign rd_data_o = rd_array_r;
    always @(posedge clk_i) begin
        if (wr_en_i) begin
            memory_r[wr_addr_i] <= wr_data_i;
        end
        if (rd_en_i) begin
            rd_array_r <= memory_r[rd_addr_i];
        end
    end
`endif
endmodule
