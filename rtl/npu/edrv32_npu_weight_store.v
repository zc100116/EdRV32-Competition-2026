// File: edrv32_npu_weight_store.v
// Spec: npu-spec 4.2-4.3, 5.2; datapath design 4.2.4, 4.3.2, 4.5.
// Description: Eight resident weight banks, each split into three 512-row RAMs.
// Writes enter one local register; RAM reads return through two stages.
// Clock: clk_npu (clk_i).
module edrv32_npu_weight_store (
    // Clock and local control; only the pending write enable is cleared.
    input wire clk_i,
    input wire rst_n_i,
    input wire cancel_i,

    // Sequential DMA beats: low three address bits select the bank.
    input wire weight_wr_valid_i,
    input wire [13:0] weight_wr_addr_i,
    input wire [255:0] weight_wr_data_i,

    // Parallel K-row read, bank zero in the least significant 256 bits.
    input wire weight_rd_en_i,
    input wire [10:0] weight_rd_addr_i,
    output wire [2047:0] weight_rd_data_o
);
    genvar bank;
    genvar segment;
    generate
        for (bank = 0; bank < 8; bank = bank + 1) begin : g_bank
            reg wr_valid_r;
            reg [10:0] wr_addr_r;
            reg [255:0] wr_data_r;
            reg [1:0] rd_segment_array_r;
            reg [1:0] rd_segment_output_r;
            wire [767:0] rd_segment_data_w;

            always @(posedge clk_i or negedge rst_n_i) begin
                if (!rst_n_i) begin
                    wr_valid_r <= 1'b0;
                end else if (cancel_i) begin
                    wr_valid_r <= 1'b0;
                end else begin
                    wr_valid_r <= weight_wr_valid_i && weight_wr_addr_i[2:0] == bank;
                end
            end

            always @(posedge clk_i) begin
                if (weight_wr_valid_i && weight_wr_addr_i[2:0] == bank) begin
                    wr_addr_r <= weight_wr_addr_i[13:3];
                    wr_data_r <= weight_wr_data_i;
                end
                // Mirror the wrapper's enabled array and always-enabled output register.
                if (weight_rd_en_i) begin
                    rd_segment_array_r <= weight_rd_addr_i[10:9];
                end
                rd_segment_output_r <= rd_segment_array_r;
            end

            for (segment = 0; segment < 3; segment = segment + 1) begin : g_segment
                edrv32_ram_npu_weight u_ram (
                    .clk_i(clk_i),
                    .wr_en_i(wr_valid_r && wr_addr_r[10:9] == segment),
                    .wr_addr_i(wr_addr_r[8:0]),
                    .wr_data_i(wr_data_r),
                    .rd_en_i(weight_rd_en_i),
                    .rd_addr_i(weight_rd_addr_i[8:0]),
                    .rd_data_o(rd_segment_data_w[256*segment +: 256])
                );
            end

            // Selection is combinational after the RAM output boundary: no third read stage.
            assign weight_rd_data_o[256*bank +: 256] = rd_segment_output_r == 2'd0 ?
                rd_segment_data_w[0 +: 256] : rd_segment_output_r == 2'd1 ?
                rd_segment_data_w[256 +: 256] : rd_segment_data_w[512 +: 256];
        end
    endgenerate
endmodule
