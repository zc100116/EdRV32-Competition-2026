// File: edrv32_ram_gpu2_setup_lut92.v
// Spec: gpu-v2-spec 2.6; M-7 scratch x16x92, M-8 72 banks.
// Description: Fixed 16x92 distributed SDP RAM, async read captured on enabled edge.
//              Same registered read and old-data collision as the DRM alternative.
// Clock domain: clk_gpu.
`include "edrv32_build_mode.vh"
module edrv32_ram_gpu2_setup_lut92 (
    // Clock.
    input wire clk_i,

    // Whole-word write.
    input wire wr_en_i,
    input wire [3:0] wr_addr_i,
    input wire [91:0] wr_data_i,

    // One-clock enabled read capture.
    input wire rd_en_i,
    input wire [3:0] rd_addr_i,
    output wire [91:0] rd_data_o
);
    wire [91:0] array_w;
`ifdef EDRV32_FPGA_MEMORY_MODE
    ip_lutram_gpu2_setup92 u_ip (
        .wr_clk(clk_i),
        .rd_clk(clk_i),
        .rst(1'b0),
        .wr_en(wr_en_i),
        .wr_addr(wr_addr_i),
        .wr_data(wr_data_i),
        .rd_addr(rd_addr_i),
        .rd_data(array_w)
    );
`else
    reg [91:0] memory_r [0:15];
    always @(posedge clk_i) begin
        if (wr_en_i) memory_r[wr_addr_i] <= wr_data_i;
    end
    assign array_w = memory_r[rd_addr_i];
`endif
    reg [91:0] rd_data_r;
    always @(posedge clk_i) begin
        if (rd_en_i) rd_data_r <= array_w;
    end
    assign rd_data_o = rd_data_r;
endmodule
