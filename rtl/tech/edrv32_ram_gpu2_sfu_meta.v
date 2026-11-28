// File: edrv32_ram_gpu2_sfu_meta.v
// Spec: gpu-v2-spec 2.4; GP-A2 metadata/retirement storage.
// Description: Fixed 32x21 logical word split into native <=16-bit enable regions.
// Clock domain: clk_gpu. Regional enables are same-edge registered copies, not pipeline stages.
module edrv32_ram_gpu2_sfu_meta (
    input wire clk_i,
    input wire [1:0] wr_en_i,
    input wire [4:0] wr_addr_i,
    input wire [20:0] wr_data_i,
    input wire [4:0] rd_addr_i,
    output wire [20:0] rd_data_o
);
    edrv32_ram_gpu2_sfu_word16 u_region0 (
        .clk_i(clk_i),
        .wr_en_i(wr_en_i[0]),
        .wr_addr_i(wr_addr_i),
        .wr_data_i(wr_data_i[0 +: 16]),
        .rd_addr_i(rd_addr_i),
        .rd_data_o(rd_data_o[0 +: 16])
    );
    edrv32_ram_gpu2_sfu_word5 u_region1 (
        .clk_i(clk_i),
        .wr_en_i(wr_en_i[1]),
        .wr_addr_i(wr_addr_i),
        .wr_data_i(wr_data_i[16 +: 5]),
        .rd_addr_i(rd_addr_i),
        .rd_data_o(rd_data_o[16 +: 5])
    );
endmodule
