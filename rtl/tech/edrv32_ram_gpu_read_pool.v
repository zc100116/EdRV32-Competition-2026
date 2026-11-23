// File: edrv32_ram_gpu_read_pool.v
// Spec: gpu-spec 2.10, 7; gpu-microarch 4.8, 4.9; CLAUDE.md 8.
// Description: Fixed 64x256 distributed RAM with enabled one-cycle read.
// Contents and read data are not reset; same-address accesses are not used.
// Clock: clk_gpu.
`include "edrv32_build_mode.vh"
module edrv32_ram_gpu_read_pool (
    // Clock.
    input wire clk_i,

    // Write port.
    input wire wr_en_i,
    input wire [5:0] wr_addr_i,
    input wire [255:0] wr_data_i,

    // Read port.
    input wire rd_en_i,
    input wire [5:0] rd_addr_i,
    output wire [255:0] rd_data_o
);
    wire [255:0] memory_data_w;
    reg [255:0] rd_data_r;
    assign rd_data_o = rd_data_r;
`ifdef EDRV32_FPGA_MEMORY_MODE
    ip_lutram_gpu_read_pool u_ip (
        .wr_clk(clk_i),
        .wr_en(wr_en_i),
        .wr_addr(wr_addr_i),
        .wr_data(wr_data_i),
        .rd_clk(clk_i),
        .rst(1'b0),
        .rd_addr(rd_addr_i),
        .rd_data(memory_data_w)
    );
`else
    reg [255:0] memory_r [0:63];
    assign memory_data_w = memory_r[rd_addr_i];
    always @(posedge clk_i) begin
        if (wr_en_i) memory_r[wr_addr_i] <= wr_data_i;
    end
`endif
    // Sample the pre-write combinational value, matching the IP wrapper.
    always @(posedge clk_i) begin
        if (rd_en_i) rd_data_r <= memory_data_w;
    end
endmodule
