// File: edrv32_npu_quant_param_store.v
// Spec: npu-spec 4.2-4.3, 5.2; datapath design 4.2.4, 4.3.2, 4.5.
// Description: Eight channel banks hold all eight blocks of quantization parameters.
// Writes enter one local register; RAM reads return through two stages.
// Clock: clk_npu (clk_i).
module edrv32_npu_quant_param_store (
    // Clock and local control; only the pending write enable is cleared.
    input wire clk_i,
    input wire rst_n_i,
    input wire cancel_i,

    // One channel from a decoded 512-byte quantization record.
    input wire quant_wr_valid_i,
    input wire [2:0] quant_wr_block_i,
    input wire [4:0] quant_wr_channel_i,
    input wire [31:0] quant_wr_bias_i,
    input wire [15:0] quant_wr_mult_i,
    input wire [5:0] quant_wr_shift_i,

    // Eight channels shared by the two quantization pixels.
    input wire param_rd_en_i,
    input wire [2:0] param_rd_block_i,
    input wire [1:0] param_rd_phase_i,
    output wire [511:0] param_rd_data_o
);
    genvar bank;
    generate
        for (bank = 0; bank < 8; bank = bank + 1) begin : g_bank
            reg wr_valid_r;
            reg [4:0] wr_addr_r;
            reg [63:0] wr_data_r;

            always @(posedge clk_i or negedge rst_n_i) begin
                if (!rst_n_i) begin
                    wr_valid_r <= 1'b0;
                end else if (cancel_i) begin
                    wr_valid_r <= 1'b0;
                end else begin
                    wr_valid_r <= quant_wr_valid_i && quant_wr_channel_i[2:0] == bank;
                end
            end

            always @(posedge clk_i) begin
                if (quant_wr_valid_i && quant_wr_channel_i[2:0] == bank) begin
                    wr_addr_r <= {quant_wr_block_i, quant_wr_channel_i[4:3]};
                    // spec npu 4.2: reserved bits, including the old per-channel zp, are zero.
                    wr_data_r <= {10'b0, quant_wr_shift_i, quant_wr_mult_i, quant_wr_bias_i};
                end
            end

            edrv32_ram_npu_quant u_ram (
                .clk_i(clk_i),
                .wr_en_i(wr_valid_r),
                .wr_addr_i(wr_addr_r),
                .wr_data_i(wr_data_r),
                .rd_en_i(param_rd_en_i),
                .rd_addr_i({param_rd_block_i, param_rd_phase_i}),
                .rd_data_o(param_rd_data_o[64*bank +: 64])
            );
        end
    endgenerate
endmodule
