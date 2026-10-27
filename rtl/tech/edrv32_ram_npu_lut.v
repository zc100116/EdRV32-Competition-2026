// File: edrv32_ram_npu_lut.v
// Spec: npu-spec 5.2; docs/design/2026-10-27-npu-datapath.md 4.5, 4.9; CLAUDE.md 8.
// Description: Fixed 4096x8 DRM simple dual-port RAM for the NPU (lut).
// Enabled reads have two-cycle latency (array read plus output register) and read old data on
// collision. Contents and output data are not initialized or reset.
// Clock: clk_npu.
`include "edrv32_build_mode.vh"
module edrv32_ram_npu_lut (
    // Clock.
    input wire clk_i,

    // Write port.
    input wire wr_en_i,
    input wire [11:0] wr_addr_i,
    input wire [7:0] wr_data_i,

    // Read port.
    input wire rd_en_i,
    input wire [11:0] rd_addr_i,
    output wire [7:0] rd_data_o
);
`ifdef EDRV32_FPGA_MEMORY_MODE
    ip_ram_npu_lut u_ip (
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
    reg [7:0] memory_r [0:4095];
    reg [7:0] rd_array_r;
    reg [7:0] rd_data_r;
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
