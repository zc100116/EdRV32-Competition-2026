// File: edrv32_eth_fifo.v
// Spec: eth 3, 5.1-5.2; SoC 5.2 X7.
// Description: Fixed 512-entry ten-bit stream FIFO using the shared CDC controller.
//              Storage is the technology-owned dual-clock RAM wrapper.
// Clock domain: independent write/read clocks.
module edrv32_eth_fifo (
    // Clocks and resets.
    input wire clk_write_i,
    input wire rst_write_n_i,
    input wire clk_read_i,
    input wire rst_read_n_i,

    // Producer stream.
    input wire valid_i,
    output wire ready_o,
    input wire [9:0] data_i,

    // Consumer stream.
    output wire valid_o,
    input wire ready_i,
    output wire [9:0] data_o
);
    wire wr_en_w;
    wire [8:0] wr_addr_w;
    wire [9:0] wr_data_w;
    wire rd_en_w;
    wire [8:0] rd_addr_w;
    wire [9:0] rd_data_w;
    edrv32_async_fifo_ram #(
        .WIDTH(10),
        .DEPTH(512)
    ) u_fifo (
        .clk_write_i(clk_write_i),
        .rst_write_n_i(rst_write_n_i),
        .clk_read_i(clk_read_i),
        .rst_read_n_i(rst_read_n_i),
        .valid_i(valid_i),
        .ready_o(ready_o),
        .data_i(data_i),
        .valid_o(valid_o),
        .ready_i(ready_i),
        .data_o(data_o),
        .wr_en_o(wr_en_w),
        .wr_addr_o(wr_addr_w),
        .wr_data_o(wr_data_w),
        .rd_en_o(rd_en_w),
        .rd_addr_o(rd_addr_w),
        .rd_data_i(rd_data_w)
    );
    edrv32_ram_eth_fifo u_memory (
        .wr_clk_i(clk_write_i),
        .wr_en_i(wr_en_w),
        .wr_addr_i(wr_addr_w),
        .wr_data_i(wr_data_w),
        .rd_clk_i(clk_read_i),
        .rd_en_i(rd_en_w),
        .rd_addr_i(rd_addr_w),
        .rd_data_o(rd_data_w)
    );
endmodule
