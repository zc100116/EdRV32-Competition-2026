// File: edrv32_npu_activation_lut.v
// Spec: npu-spec 4.2-4.3, 5.2; datapath design 4.2.4, 4.3.2, 4.5.
// Description: Sixteen independent read ports use replicated eight-block activation tables.
// Writes enter one local register; RAM reads return through two stages.
// Clock: clk_npu (clk_i).
module edrv32_npu_activation_lut (
    // Clock and local control; only the pending write enable is cleared.
    input wire clk_i,
    input wire rst_n_i,
    input wire cancel_i,

    // Broadcast table load, locally registered beside each RAM replica.
    input wire lut_wr_valid_i,
    input wire [2:0] lut_wr_block_i,
    input wire [7:0] lut_wr_addr_i,
    input wire [7:0] lut_wr_data_i,

    // Each lane supplies its own eight-bit index within the selected block.
    input wire lut_rd_en_i,
    input wire [2:0] lut_rd_block_i,
    input wire [127:0] lut_rd_addr_i,
    output wire [127:0] lut_rd_data_o
);
    genvar lane;
    generate
        for (lane = 0; lane < 16; lane = lane + 1) begin : g_lane
            reg wr_valid_r;
            reg [10:0] wr_addr_r;
            reg [7:0] wr_data_r;

            always @(posedge clk_i or negedge rst_n_i) begin
                if (!rst_n_i) begin
                    wr_valid_r <= 1'b0;
                end else if (cancel_i) begin
                    wr_valid_r <= 1'b0;
                end else begin
                    wr_valid_r <= lut_wr_valid_i;
                end
            end

            always @(posedge clk_i) begin
                if (lut_wr_valid_i) begin
                    wr_addr_r <= {lut_wr_block_i, lut_wr_addr_i};
                    wr_data_r <= lut_wr_data_i;
                end
            end

            edrv32_ram_npu_lut u_ram (
                .clk_i(clk_i),
                .wr_en_i(wr_valid_r),
                .wr_addr_i({1'b0, wr_addr_r}),
                .wr_data_i(wr_data_r),
                .rd_en_i(lut_rd_en_i),
                .rd_addr_i({1'b0, lut_rd_block_i, lut_rd_addr_i[8*lane +: 8]}),
                .rd_data_o(lut_rd_data_o[8*lane +: 8])
            );
        end
    endgenerate
endmodule
