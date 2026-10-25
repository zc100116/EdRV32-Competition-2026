// File: edrv32_ram_icache_tag.v
// Spec: cache-spec 2.2, 5.5.
// Description: Fixed synchronous RAM with old-data read/write collision behavior.
// Fixed simple dual-port RAM in clk_sys. Enabled reads update at the next edge;
// disabled reads hold their output. Same-edge same-address reads see old data.
// Contents and read data are not initialized or reset.
`include "edrv32_build_mode.vh"
module edrv32_ram_icache_tag (
    // Clock and RAM ports.
    input wire  clk_i,
    input wire  wr_en_i,
    input wire [6:0] wr_addr_i,
    input wire [19:0] wr_data_i,
    input wire  rd_en_i,
    input wire [6:0] rd_addr_i,
    output wire [19:0] rd_data_o
);
`ifdef EDRV32_FPGA_MEMORY_MODE
    ip_ram_icache_tag u_ip (
        .wr_clk(clk_i),
        .wr_en(wr_en_i),
        .wr_addr(wr_addr_i),
        .wr_data(wr_data_i),
        .rd_clk(clk_i),
        .rd_en(rd_en_i),
        .rd_addr(rd_addr_i),
        .rd_data(rd_data_o)
    );
`else
    reg [19:0] memory_r [0:127];
    reg [19:0] rd_data_r;
    assign rd_data_o = rd_data_r;
    always @(posedge clk_i) begin
        if (wr_en_i) begin
            memory_r[wr_addr_i] <= wr_data_i;
        end
        if (rd_en_i) begin
            rd_data_r <= memory_r[rd_addr_i];
        end
    end
`endif
endmodule
