// File: edrv32_ram_dcache_data.v
// Spec: cache-spec 2.2, 5.5.
// Description: Fixed synchronous RAM with old-data read/write collision behavior.
// Fixed simple dual-port RAM in clk_sys. Enabled reads update at the next edge;
// disabled reads hold their output. Same-edge same-address reads see old data.
// Contents and read data are not initialized or reset.
`include "edrv32_build_mode.vh"
module edrv32_ram_dcache_data (
    // Clock and RAM ports.
    input wire  clk_i,
    input wire  wr_en_i,
    input wire [8:0] wr_addr_i,
    input wire [63:0] wr_data_i,
    input wire [7:0] wr_byte_en_i,
    input wire  rd_en_i,
    input wire [8:0] rd_addr_i,
    output wire [63:0] rd_data_o
);
`ifdef EDRV32_FPGA_MEMORY_MODE
    ip_ram_dcache_data u_ip (
        .wr_clk(clk_i),
        .wr_en(wr_en_i),
        .wr_addr(wr_addr_i),
        .wr_data(wr_data_i),
        .wr_byte_en(wr_byte_en_i),
        .rd_clk(clk_i),
        .rd_en(rd_en_i),
        .rd_addr(rd_addr_i),
        .rd_data(rd_data_o)
    );
`else
    reg [63:0] memory_r [0:511];
    reg [63:0] rd_data_r;
    integer byte_idx_r;
    assign rd_data_o = rd_data_r;
    always @(posedge clk_i) begin
        if (wr_en_i) begin
            for (byte_idx_r = 0; byte_idx_r < 8; byte_idx_r = byte_idx_r + 1) begin
                if (wr_byte_en_i[byte_idx_r]) begin
                    memory_r[wr_addr_i][byte_idx_r*8 +: 8] <=
                        wr_data_i[byte_idx_r*8 +: 8];
                end
            end
        end
        if (rd_en_i) begin
            rd_data_r <= memory_r[rd_addr_i];
        end
    end
`endif
endmodule
