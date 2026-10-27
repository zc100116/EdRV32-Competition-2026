// File: edrv32_ram_disp_scan.v
// Spec: disp-spec 2.6, 9 #1; SoC 5.2 X5; CLAUDE.md 8.
// Description: Fixed 512x256 DRM simple dual-port RAM with independent clocks for
// the DISP scan FIFO. Enabled reads have one-cycle latency in the read clock.
// Contents and output data are not initialized or reset.
// Clock: write clk_mem, read clk_pix.
`include "edrv32_build_mode.vh"
module edrv32_ram_disp_scan (
    // Write port (clk_mem).
    input wire wr_clk_i,
    input wire wr_en_i,
    input wire [8:0] wr_addr_i,
    input wire [255:0] wr_data_i,

    // Read port (clk_pix).
    input wire rd_clk_i,
    input wire rd_en_i,
    input wire [8:0] rd_addr_i,
    output wire [255:0] rd_data_o
);
`ifdef EDRV32_FPGA_MEMORY_MODE
    ip_ram_disp_scan u_ip (
        .wr_clk(wr_clk_i),
        .wr_rst(1'b0),
        .wr_en(wr_en_i),
        .wr_addr(wr_addr_i),
        .wr_data(wr_data_i),
        .rd_clk(rd_clk_i),
        .rd_rst(1'b0),
        .rd_clk_en(rd_en_i),
        .rd_addr(rd_addr_i),
        .rd_data(rd_data_o)
    );
`else
    reg [255:0] memory_r [0:511];
    reg [255:0] rd_array_r;
    assign rd_data_o = rd_array_r;
    always @(posedge wr_clk_i) begin
        if (wr_en_i) begin
            memory_r[wr_addr_i] <= wr_data_i;
        end
    end
    always @(posedge rd_clk_i) begin
        if (rd_en_i) begin
            rd_array_r <= memory_r[rd_addr_i];
        end
    end
`endif
endmodule
