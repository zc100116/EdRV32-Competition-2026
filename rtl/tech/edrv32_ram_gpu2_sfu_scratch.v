// File: edrv32_ram_gpu2_sfu_scratch.v
// Spec: gpu-v2-spec 2.4; M-7 synchronous scratch, GP-A2.
// Description: One DRM per 32x32 bank, one-cycle read with same-edge write forwarding.
// Clock domain: clk_gpu. Forwarding overlaps dependent reads with the ten-edge arithmetic core.
`include "edrv32_build_mode.vh"
module edrv32_ram_gpu2_sfu_scratch (
    input wire clk_i,
    input wire wr_en_i,
    input wire [4:0] wr_addr_i,
    input wire [31:0] wr_data_i,
    input wire [4:0] rd_addr_i,
    output wire [31:0] rd_data_o
);
    wire [31:0] memory_data_w;
`ifdef EDRV32_FPGA_MEMORY_MODE
    ip_ram_gpu2_sfu_scratch u_ip (
        .wr_clk(clk_i),
        .wr_rst(1'b0),
        .wr_en(wr_en_i),
        .wr_addr({5'b0, wr_addr_i}),
        .wr_data(wr_data_i),
        .rd_clk(clk_i),
        .rd_rst(1'b0),
        .rd_clk_en(1'b1),
        .rd_addr({5'b0, rd_addr_i}),
        .rd_data(memory_data_w)
    );
`else
    reg [31:0] memory_r [0:31];
    reg [31:0] memory_data_r;
    always @(posedge clk_i) begin
        if (wr_en_i) memory_r[wr_addr_i] <= wr_data_i;
        memory_data_r <= memory_r[rd_addr_i];
    end
    assign memory_data_w = memory_data_r;
`endif
    // Each select leaf drives sixteen data bits. Data capture has no enable/reset fanout.
    (* keep = "true", syn_preserve = 1 *) reg [1:0] forward_r;
    reg [31:0] forward_data_r;
    always @(posedge clk_i) begin
        forward_r <= {2{wr_en_i && wr_addr_i == rd_addr_i}};
        forward_data_r <= wr_data_i;
    end
    assign rd_data_o[15:0] = forward_r[0] ? forward_data_r[15:0] : memory_data_w[15:0];
    assign rd_data_o[31:16] = forward_r[1] ? forward_data_r[31:16] : memory_data_w[31:16];
endmodule
