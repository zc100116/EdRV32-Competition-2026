// File: edrv32_aud_fifo.v
// Spec: aud-spec 2.4; gpu-soc-spec 5.2 X11.
// Description: 512-sample dual-clock FIFO using the existing RAM controller and IP.
//              A Gray read count gives conservative occupancy in the write domain.
// Clock domain: clk_mem write side and clk_aud read side.
module edrv32_aud_fifo (
    // Clock and reset.
    input wire clk_mem_i,
    input wire rst_mem_n_i,
    input wire clk_aud_i,
    input wire rst_aud_n_i,

    // Producer and write-domain occupancy.
    input wire sample_valid_i,
    output wire sample_ready_o,
    input wire [31:0] sample_data_i,
    output wire [9:0] level_o,

    // Consumer.
    output wire sample_valid_o,
    input wire sample_ready_i,
    output wire [31:0] sample_data_o
);
    reg [9:0] write_cnt_r;
    reg [9:0] read_cnt_r;
    wire [9:0] read_cnt_w;
    wire wr_en_w;
    wire [8:0] wr_addr_w;
    wire [31:0] wr_data_w;
    wire rd_en_w;
    wire [8:0] rd_addr_w;
    wire [31:0] rd_data_w;

    assign level_o = write_cnt_r - read_cnt_w;
    always @(posedge clk_mem_i or negedge rst_mem_n_i) begin
        if (!rst_mem_n_i) begin
            write_cnt_r <= 10'd0;
        end else if (sample_valid_i && sample_ready_o) begin
            write_cnt_r <= write_cnt_r + 1'b1;
        end
    end
    always @(posedge clk_aud_i or negedge rst_aud_n_i) begin
        if (!rst_aud_n_i) begin
            read_cnt_r <= 10'd0;
        end else if (sample_valid_o && sample_ready_i) begin
            read_cnt_r <= read_cnt_r + 1'b1;
        end
    end
    edrv32_cdc_gray_cnt #(.WIDTH(10)) u_read_count (
        .clk_src_i(clk_aud_i),
        .rst_src_n_i(rst_aud_n_i),
        .clk_dst_i(clk_mem_i),
        .rst_dst_n_i(rst_mem_n_i),
        .count_i(read_cnt_r),
        .count_o(read_cnt_w)
    );
    edrv32_async_fifo_ram #(
        .WIDTH(32),
        .DEPTH(512)
    ) u_samples (
        .clk_write_i(clk_mem_i),
        .rst_write_n_i(rst_mem_n_i),
        .clk_read_i(clk_aud_i),
        .rst_read_n_i(rst_aud_n_i),
        .valid_i(sample_valid_i),
        .ready_o(sample_ready_o),
        .data_i(sample_data_i),
        .valid_o(sample_valid_o),
        .ready_i(sample_ready_i),
        .data_o(sample_data_o),
        .wr_en_o(wr_en_w),
        .wr_addr_o(wr_addr_w),
        .wr_data_o(wr_data_w),
        .rd_en_o(rd_en_w),
        .rd_addr_o(rd_addr_w),
        .rd_data_i(rd_data_w)
    );
    edrv32_ram_aud_fifo u_ram (
        .wr_clk_i(clk_mem_i),
        .wr_en_i(wr_en_w),
        .wr_addr_i(wr_addr_w),
        .wr_data_i(wr_data_w),
        .rd_clk_i(clk_aud_i),
        .rd_en_i(rd_en_w),
        .rd_addr_i(rd_addr_w),
        .rd_data_o(rd_data_w)
    );
endmodule
