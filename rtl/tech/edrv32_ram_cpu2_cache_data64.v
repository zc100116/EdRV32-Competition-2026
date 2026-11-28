// File: edrv32_ram_cpu2_cache_data64.v
// Spec: cpu-v2-spec 5.5; interface freeze 2026-11-28 technology wrappers.
// Description: Fixed 2048x64 1R1W memory, 8-bit write mask; one-cycle
// old-data read; disabled reads hold their output. D$每路数据、单发射I$每路数据
// Clock domain: clk_sys.
`include "edrv32_build_mode.vh"
module edrv32_ram_cpu2_cache_data64 (
    // Clock and write port.
    input wire clk_i,
    input wire wr_en_i,
    input wire [10:0] wr_addr_i,
    input wire [63:0] wr_data_i,
    input wire [7:0] wr_mask_i,
    // Read port.
    input wire rd_en_i,
    input wire [10:0] rd_addr_i,
    output wire [63:0] rd_data_o
);
`ifdef EDRV32_FPGA_MEMORY_MODE
    ip_ram_cpu2_cache_data64 u_ip (
        .wr_clk(clk_i),
        .wr_en(wr_en_i),
        .wr_addr(wr_addr_i),
        .wr_data(wr_data_i),
        .wr_byte_en(wr_mask_i),
        .rd_clk(clk_i),
        .wr_rst(1'b0),
        .rd_rst(1'b0),
        .rd_clk_en(rd_en_i),
        .rd_addr(rd_addr_i),
        .rd_data(rd_data_o)
    );
`else
    reg [63:0] memory_r [0:2047];
    reg [63:0] rd_data_r;
    integer byte_idx_r;
    assign rd_data_o = rd_data_r;
    always @(posedge clk_i) begin
        if (wr_en_i) begin
            for (byte_idx_r = 0; byte_idx_r < 8; byte_idx_r = byte_idx_r + 1) begin
                if (wr_mask_i[byte_idx_r])
                    memory_r[wr_addr_i][byte_idx_r*8 +: 8] <= wr_data_i[byte_idx_r*8 +: 8];
            end
        end
        if (rd_en_i)
            rd_data_r <= memory_r[rd_addr_i];
    end
`endif
endmodule
