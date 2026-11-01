// File: edrv32_ram_mem_xbar_w.v
// Spec: mem-subsys-spec 2.2, 7; CLAUDE.md 8.
// Description: Fixed 16x288 distributed RAM simple dual-port storage (2 x 16x144 IP).
// Each 144-bit half has an independent read address and enable, with one-cycle latency.
// A disabled half holds its output; the two halves use the existing IP instances.
// The wrapper samples the combinational read before the write edge updates memory,
// so same-address reads return old data. Contents and output data are not initialized or reset.
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
    input wire rd_en_lo_i,
    input wire rd_en_hi_i,
    input wire [3:0] rd_addr_lo_i,
    input wire [3:0] rd_addr_hi_i,
    output wire [287:0] rd_data_o
);
    wire [287:0] memory_data_w;
    reg [287:0] rd_data_r;
    assign rd_data_o = rd_data_r;

`ifdef EDRV32_FPGA_MEMORY_MODE
    // The distributed RAM IP is at most 256 bits wide; two side-by-side
    // 144-bit instances share only the write address and enable.
    ip_lutram_mem_xbar_w u_ip_lo (
        // Synchronous write port.
        .wr_clk(clk_i),
        .wr_en(wr_en_i),
        .wr_addr(wr_addr_i),
        .wr_data(wr_data_i[143:0]),

        // Unregistered combinational read port.
        .rd_clk(clk_i),
        .rst(1'b0),
        .rd_addr(rd_addr_lo_i),
        .rd_data(memory_data_w[143:0])
    );
    ip_lutram_mem_xbar_w u_ip_hi (
        // Synchronous write port.
        .wr_clk(clk_i),
        .wr_en(wr_en_i),
        .wr_addr(wr_addr_i),
        .wr_data(wr_data_i[287:144]),

        // Unregistered combinational read port.
        .rd_clk(clk_i),
        .rst(1'b0),
        .rd_addr(rd_addr_hi_i),
        .rd_data(memory_data_w[287:144])
    );
`else
    reg [287:0] memory_r [0:15];
    assign memory_data_w[143:0] = memory_r[rd_addr_lo_i][143:0];
    assign memory_data_w[287:144] = memory_r[rd_addr_hi_i][287:144];
    always @(posedge clk_i) begin
        if (wr_en_i) begin
            memory_r[wr_addr_i] <= wr_data_i;
        end
    end
`endif
    // Capture the pre-write value; a disabled read holds this register.
    always @(posedge clk_i) begin
        if (rd_en_lo_i) begin
            rd_data_r[143:0] <= memory_data_w[143:0];
        end
        if (rd_en_hi_i) begin
            rd_data_r[287:144] <= memory_data_w[287:144];
        end
    end
endmodule
