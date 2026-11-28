// File: edrv32_ram_gpu2_queue.v
// Spec: gpu-v2-spec 2.4; CLAUDE.md 8.
// Description: Fixed sixteen-word FP32 response queue, synchronous write/asynchronous read.
// Clock domain: clk_gpu. Data are not reset; caller owns occupancy.
`include "edrv32_build_mode.vh"
module edrv32_ram_gpu2_queue (
    // Clock and write port.
    input wire clk_i,
    input wire wr_en_i,
    input wire [3:0] wr_addr_i,
    input wire [31:0] wr_data_i,

    // Independent asynchronous read port.
    input wire [3:0] rd_addr_i,
    output wire [31:0] rd_data_o
);
`ifdef EDRV32_FPGA_MEMORY_MODE
    ip_ram_gpu2_queue u_ip (
        .clk(clk_i),
        .wr_en(wr_en_i),
        .wr_addr(wr_addr_i),
        .wr_data(wr_data_i),
        .rd_addr(rd_addr_i),
        .rd_data(rd_data_o)
    );
`else
    reg [31:0] memory_r [0:15];
    always @(posedge clk_i) begin
        if (wr_en_i) memory_r[wr_addr_i] <= wr_data_i;
    end
    assign rd_data_o = memory_r[rd_addr_i];
`endif
endmodule
