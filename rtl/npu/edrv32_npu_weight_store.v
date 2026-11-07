// File: edrv32_npu_weight_store.v
// Spec: npu-spec 4.2-4.3, 5.2, 5.4; design/2026-10-30-npu-apm-cascade 4-6.
// Description: Eight resident weight banks, each split into three 512-row RAMs.
// DMA rows transpose into item banks; bank k reads k edges after bank zero.
// Clock: clk_npu (clk_i).
module edrv32_npu_weight_store (
    // Clock and local control; only the pending write enable is cleared.
    input wire clk_i,
    input wire rst_n_i,
    input wire cancel_i,

    // Sequential DMA beats: eight beats supply one complete 32-channel K row.
    input wire weight_wr_valid_i,
    input wire [13:0] weight_wr_addr_i,
    input wire [255:0] weight_wr_data_i,

    // Item-skewed K-row read, retaining [channel][item] output byte order.
    input wire weight_rd_en_i,
    input wire [10:0] weight_rd_addr_i,
    output wire [2047:0] weight_rd_data_o
);
    genvar bank;
    genvar segment;
    genvar channel;
    genvar beat;
    genvar group_idx;
    generate
        for (bank = 0; bank < 8; bank = bank + 1) begin : g_bank
            // One bank-local DMA boundary; each byte now drives eight slices only.
            (* keep = "true", syn_preserve = 1 *) reg [31:0] wr_bank_data_r;
            wire [255:0] wr_data_w;
            reg [1:0] rd_segment_array_r;

            wire [767:0] rd_segment_data_w;
            wire [255:0] rd_bank_data_w;
            wire rd_en_w;
            wire [10:0] rd_addr_w;

            if (bank == 0) begin : g_direct
                assign rd_en_w = weight_rd_en_i;
                assign rd_addr_w = weight_rd_addr_i;
            end else begin : g_skew
                reg [bank-1:0] rd_en_r;
                reg [11*bank-1:0] rd_addr_r;
                // Reads remain live across reset/cancel, as in the RAM wrappers.
                always @(posedge clk_i) begin
                    rd_en_r <= (rd_en_r << 1) | {{(bank-1){1'b0}}, weight_rd_en_i};
                    rd_addr_r <= (rd_addr_r << 11) |
                        {{(11*bank-11){1'b0}}, weight_rd_addr_i};
                end
                assign rd_en_w = rd_en_r[bank-1];
                assign rd_addr_w = rd_addr_r[11*(bank-1) +: 11];
            end

            always @(posedge clk_i) begin
                wr_bank_data_r <= {weight_wr_data_i[8*(24+bank) +: 8],
                    weight_wr_data_i[8*(16+bank) +: 8],
                    weight_wr_data_i[8*(8+bank) +: 8],
                    weight_wr_data_i[8*bank +: 8]};
                if (rd_en_w) begin
                    rd_segment_array_r <= rd_addr_w[10:9];
                end
            end

            // Fixed slices expose a word enable instead of a 256-bit feedback mux.
            for (beat = 0; beat < 8; beat = beat + 1) begin : g_write_beat
                (* keep = "true", syn_preserve = 1 *) reg wr_beat_valid_r;
                reg [31:0] wr_slice_r;
                assign wr_data_w[32*beat +: 32] = wr_slice_r;
                always @(posedge clk_i or negedge rst_n_i) begin
                    if (!rst_n_i) begin
                        wr_beat_valid_r <= 1'b0;
                    end else begin
                        wr_beat_valid_r <= !cancel_i && weight_wr_valid_i
                            && weight_wr_addr_i[2:0] == beat;
                    end
                end
                always @(posedge clk_i) begin
                    if (wr_beat_valid_r) begin
                        wr_slice_r <= wr_bank_data_r;
                    end
                end
            end

            for (segment = 0; segment < 3; segment = segment + 1) begin : g_segment
                // A 256-bit wrapper is four DRM slices: address/enable fanout is four.
                (* keep = "true", syn_preserve = 1 *) reg [10:0] wr_bank_addr_r;
                (* keep = "true", syn_preserve = 1 *) reg [8:0] wr_addr_r;
                (* keep = "true", syn_preserve = 1 *) reg wr_valid_r;

                wire rd_en_local_w;
                if (bank == 0) begin : g_read_direct
                    assign rd_en_local_w = weight_rd_en_i;
                end else begin : g_read_skew
                    (* keep = "true", syn_preserve = 1 *) reg rd_en_r;
                    if (bank == 1) begin : g_first
                        always @(posedge clk_i) begin
                            rd_en_r <= weight_rd_en_i;
                        end
                    end else begin : g_later
                        always @(posedge clk_i) begin
                            rd_en_r <= g_skew.rd_en_r[bank-2];
                        end
                    end
                    assign rd_en_local_w = rd_en_r;
                end
                always @(posedge clk_i) begin
                    wr_bank_addr_r <= weight_wr_addr_i[13:3];
                    wr_addr_r <= wr_bank_addr_r[8:0];
                end
                always @(posedge clk_i or negedge rst_n_i) begin
                    if (!rst_n_i) begin
                        wr_valid_r <= 1'b0;
                    end else begin
                        // Already accepted beat seven drains even when cancel arrives.
                        wr_valid_r <= g_write_beat[7].wr_beat_valid_r
                            && wr_bank_addr_r[10:9] == segment;
                    end
                end
                edrv32_ram_npu_weight u_ram (
                    .clk_i(clk_i),
                    .wr_en_i(wr_valid_r),
                    .wr_addr_i(wr_addr_r),
                    .wr_data_i(wr_data_w),
                    .rd_en_i(rd_en_local_w),
                    .rd_addr_i(rd_addr_w[8:0]),
                    .rd_data_o(rd_segment_data_w[256*segment +: 256])
                );
            end

            // Eight destination groups each select only four channels (32 mux bits).
            // The RAM read boundary and item skew retain their original latency.
            for (group_idx = 0; group_idx < 8; group_idx = group_idx + 1) begin : g_read_group
                (* keep = "true", syn_preserve = 1 *) reg [1:0] rd_segment_output_r;
                always @(posedge clk_i) begin
                    rd_segment_output_r <= rd_segment_array_r;
                end
                assign rd_bank_data_w[32*group_idx +: 32] = rd_segment_output_r == 2'd0 ?
                    rd_segment_data_w[32*group_idx +: 32] : rd_segment_output_r == 2'd1 ?
                    rd_segment_data_w[256+32*group_idx +: 32] :
                    rd_segment_data_w[512+32*group_idx +: 32];
            end
            for (channel = 0; channel < 32; channel = channel + 1) begin : g_channel
                assign weight_rd_data_o[8*(8*channel+bank) +: 8] =
                    rd_bank_data_w[8*channel +: 8];
            end
        end
    endgenerate
endmodule
