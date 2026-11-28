// File: edrv32_ram_gpu2_sfu_word5.v
// Spec: gpu-v2-spec 2.4; GP-A2 regional LUTRAM write enables.
// Description: Fixed 32x5 distributed SDP RAM; one enable leaf has at most sixteen sinks.
// Clock domain: clk_gpu. Synchronous whole-word write and asynchronous read, no data reset.
`include "edrv32_build_mode.vh"
module edrv32_ram_gpu2_sfu_word5 (
    input wire clk_i,
    input wire wr_en_i,
    input wire [4:0] wr_addr_i,
    input wire [4:0] wr_data_i,
    input wire [4:0] rd_addr_i,
    output wire [4:0] rd_data_o
);
`ifdef EDRV32_FPGA_MEMORY_MODE
    ip_lutram_gpu2_sfu_word5 u_ip (
        .wr_clk(clk_i),
        .rd_clk(clk_i),
        .rst(1'b0),
        .wr_en(wr_en_i),
        .wr_addr(wr_addr_i),
        .wr_data(wr_data_i),
        .rd_addr(rd_addr_i),
        .rd_data(rd_data_o)
    );
`else
    reg [4:0] memory_r [0:31];
    always @(posedge clk_i) begin
        if (wr_en_i) memory_r[wr_addr_i] <= wr_data_i;
    end
    assign rd_data_o = memory_r[rd_addr_i];
`endif
endmodule
