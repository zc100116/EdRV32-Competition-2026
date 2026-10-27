// File: edrv32_npu_line_cache.v
// Spec: npu-spec 5.2; datapath design 4.2.4, 4.4, 4.5.
// Description: Two independently read 1024x256 banks shared across output blocks.
//              Legal S1/S2 windows require at most one read per bank each cycle.
// Clock: clk_npu.
module edrv32_npu_line_cache (
    // Clock; RAM contents and read data have no reset.
    input wire clk_i,

    // Normalized input writes.
    input wire cache_wr_valid_i,
    input wire cache_wr_bank_i,
    input wire [9:0] cache_wr_addr_i,
    input wire [255:0] cache_wr_data_i,

    // Independent two-stage synchronous read ports.
    input wire [1:0] cache_rd_en_i,
    input wire [9:0] cache_rd_addr0_i,
    input wire [9:0] cache_rd_addr1_i,
    output wire [255:0] cache_rd_data0_o,
    output wire [255:0] cache_rd_data1_o
);
    edrv32_ram_npu_line u_bank0 (
        .clk_i(clk_i),
        .wr_en_i(cache_wr_valid_i && !cache_wr_bank_i),
        .wr_addr_i(cache_wr_addr_i),
        .wr_data_i(cache_wr_data_i),
        .rd_en_i(cache_rd_en_i[0]),
        .rd_addr_i(cache_rd_addr0_i),
        .rd_data_o(cache_rd_data0_o)
    );

    edrv32_ram_npu_line u_bank1 (
        .clk_i(clk_i),
        .wr_en_i(cache_wr_valid_i && cache_wr_bank_i),
        .wr_addr_i(cache_wr_addr_i),
        .wr_data_i(cache_wr_data_i),
        .rd_en_i(cache_rd_en_i[1]),
        .rd_addr_i(cache_rd_addr1_i),
        .rd_data_o(cache_rd_data1_o)
    );
endmodule
