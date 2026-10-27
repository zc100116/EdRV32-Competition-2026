// File: edrv32_npu_datapath.v
// Spec: npu-spec 5.1, 5.4, 5.5; datapath design 4.2.2 and 4.3.
// Description: Connect the CONV pipeline with pair reservations and DMA-owned chunks.
// Layer fields are captured once; command contexts and all tags stay in the window.
// Clock: clk_npu.
module edrv32_npu_datapath (
    // Clock and local cancellation.
    input wire clk_i,
    input wire rst_n_i,
    input wire cancel_i,

    // Layer configuration, accepted after local work has drained.
    input wire cfg_k3_i,
    input wire cfg_s2_i,
    input wire cfg_in_c4_i,
    input wire cfg_half_tail_i,
    input wire cfg_lut_en_i,
    input wire cfg_res_en_i,
    input wire [7:0] cfg_out_zp_i,
    input wire [11:0] cfg_in_w_i,
    input wire [11:0] cfg_out_w_i,
    input wire [5:0] cfg_cin_blocks_i,
    input wire [3:0] cfg_cout_blocks_i,
    input wire [10:0] cfg_k_count_i,
    input wire cfg_valid_i,
    output wire cfg_ready_o,

    // Input DMA and local row completion.
    input wire line_wr_valid_i,
    output wire line_wr_ready_o,
    input wire line_wr_bank_i,
    input wire [9:0] line_wr_addr_i,
    input wire [255:0] line_wr_data_i,
    input wire line_wr_row_last_i,
    output wire line_wr_row_done_o,
    output wire line_wr_idle_o,

    // Resident weights, quantization parameters and activation tables.
    input wire weight_wr_valid_i,
    input wire [13:0] weight_wr_addr_i,
    input wire [255:0] weight_wr_data_i,
    input wire quant_wr_valid_i,
    input wire [2:0] quant_wr_block_i,
    input wire [4:0] quant_wr_channel_i,
    input wire [31:0] quant_wr_bias_i,
    input wire [15:0] quant_wr_mult_i,
    input wire [5:0] quant_wr_shift_i,
    input wire lut_wr_valid_i,
    input wire [2:0] lut_wr_block_i,
    input wire [7:0] lut_wr_addr_i,
    input wire [7:0] lut_wr_data_i,

    // Ordered command queue and pair issue control.
    input wire cmd_valid_i,
    input wire [11:0] cmd_row_i,
    input wire [2:0] cmd_block_i,
    input wire [10:0] cmd_weight_base_i,
    input wire [9:0] cmd_row_base0_i,
    input wire [9:0] cmd_row_base1_i,
    input wire [9:0] cmd_row_base2_i,
    input wire [2:0] cmd_row_valid_i,
    output wire cmd_ready_o,
    input wire issue_enable_i,

    // Residual DMA batches in pair consumption order.
    input wire residual_begin_valid_i,
    output wire residual_begin_ready_o,
    input wire residual_begin_bank_i,
    input wire [4:0] residual_begin_pairs_i,
    input wire residual_begin_half_i,
    input wire residual_wr_valid_i,
    input wire residual_wr_bank_i,
    input wire [3:0] residual_wr_index_i,
    input wire [255:0] residual_wr_data_i,
    input wire residual_commit_i,

    // Completed result chunks and DMA RAM reads.
    output wire [5:0] result_credit_o,
    output wire result_chunk_valid_o,
    input wire result_chunk_ready_i,
    output wire [4:0] result_chunk_base_o,
    output wire [4:0] result_chunk_pairs_o,
    output wire [11:0] result_chunk_row_o,
    output wire [2:0] result_chunk_block_o,
    output wire [10:0] result_chunk_pair_o,
    output wire result_chunk_half_o,
    output wire result_chunk_last_o,
    input wire result_release_i,
    input wire result_rd_en_i,
    input wire [4:0] result_rd_index_i,
    input wire result_rd_plane_i,
    output wire result_rd_valid_o,
    output wire [255:0] result_rd_data_o,

    // Command lifetime and pipeline activity.
    output wire cmd_issued_o,
    output wire [11:0] cmd_issued_row_o,
    output wire [2:0] cmd_issued_block_o,
    output wire cmd_read_done_o,
    output wire [11:0] cmd_read_done_row_o,
    output wire [2:0] cmd_read_done_block_o,
    output wire cmd_done_o,
    output wire [11:0] cmd_done_row_o,
    output wire [2:0] cmd_done_block_o,
    output wire idle_o,
    output wire mac_beat_o
);
    reg cfg_k3_r;
    reg cfg_s2_r;
    reg cfg_in_c4_r;
    reg cfg_half_tail_r;
    reg cfg_lut_en_r;
    reg cfg_res_en_r;
    reg [7:0] cfg_out_zp_r;
    reg [11:0] cfg_in_w_r;
    reg [11:0] cfg_out_w_r;
    reg [5:0] cfg_cin_blocks_r;
    reg [3:0] cfg_cout_blocks_r;
    reg [10:0] cfg_k_count_r;
    wire cache_wr_valid_w;
    wire cache_wr_bank_w;
    wire [9:0] cache_wr_addr_w;
    wire [255:0] cache_wr_data_w;
    wire [1:0] cache_rd_en_w;
    wire [9:0] cache_rd_addr0_w;
    wire [9:0] cache_rd_addr1_w;
    wire [255:0] cache_rd_data0_w;
    wire [255:0] cache_rd_data1_w;
    wire pair_ready_w;
    wire [4:0] pair_result_slot_w;
    wire [4:0] pair_residual_addr_w;
    wire pair_fire_w;
    wire pair_half_w;
    wire weight_rd_en_w;
    wire [10:0] weight_rd_addr_w;
    wire [2047:0] weight_rd_data_w;
    wire term_valid_w;
    wire term_first_w;
    wire term_last_w;
    wire [48:0] term_tag_w;
    wire [1023:0] term_activation_w;
    wire [2047:0] term_weight_w;
    wire window_idle_w;
    wire param_rd_en_w;
    wire [2:0] param_rd_block_w;
    wire [1:0] param_rd_phase_w;
    wire [511:0] param_rd_data_w;
    wire sum_valid_w;
    wire sum_first_w;
    wire sum_last_w;
    wire [48:0] sum_tag_w;
    wire [1215:0] sum_data_w;
    wire mac_array_idle_w;
    wire quant_prepare_valid_w;
    wire [48:0] quant_prepare_tag_w;
    wire accum_valid_w;
    wire [48:0] accum_tag_w;
    wire [2047:0] accum_data_w;
    wire accum_idle_w;
    wire lut_rd_en_w;
    wire [2:0] lut_rd_block_w;
    wire [127:0] lut_rd_addr_w;
    wire [127:0] lut_rd_data_w;
    wire residual_rd_en_w;
    wire [4:0] residual_rd_addr_w;
    wire quant_valid_w;
    wire [48:0] quant_tag_w;
    wire [511:0] quant_data_w;
    wire result_quant_idle_w;
    wire residual_reserve_w;
    wire pair_residual_ready_w;
    wire residual_rd_valid_w;
    wire [255:0] residual_rd_data_w;
    wire residual_buffer_idle_w;
    wire writeback_valid_w;
    wire [48:0] writeback_tag_w;
    wire [511:0] writeback_data_w;
    wire residual_add_idle_w;
    wire writeback_idle_w;

    // Configuration is replaced only after every internal owner has released its data.
    assign cfg_ready_o = idle_o && !cancel_i;
    assign idle_o = window_idle_w &&
        mac_array_idle_w &&
        accum_idle_w &&
        result_quant_idle_w &&
        residual_buffer_idle_w &&
        residual_add_idle_w &&
        writeback_idle_w && line_wr_idle_o;
    assign pair_ready_w = (result_credit_o != 6'd0)
        && (!cfg_res_en_r || pair_residual_ready_w);
    assign residual_reserve_w = pair_fire_w && cfg_res_en_r;

    always @(posedge clk_i) begin
        if (cfg_valid_i && cfg_ready_o) begin
            cfg_k3_r <= cfg_k3_i;
            cfg_s2_r <= cfg_s2_i;
            cfg_in_c4_r <= cfg_in_c4_i;
            cfg_half_tail_r <= cfg_half_tail_i;
            cfg_lut_en_r <= cfg_lut_en_i;
            cfg_res_en_r <= cfg_res_en_i;
            cfg_out_zp_r <= cfg_out_zp_i;
            cfg_in_w_r <= cfg_in_w_i;
            cfg_out_w_r <= cfg_out_w_i;
            cfg_cin_blocks_r <= cfg_cin_blocks_i;
            cfg_cout_blocks_r <= cfg_cout_blocks_i;
            cfg_k_count_r <= cfg_k_count_i;
        end
    end

    // Normalize input DMA writes before the shared cache.
    edrv32_npu_input_unpack u_input_unpack (
        // Clock and cancellation.
        .clk_i(clk_i),
        .rst_n_i(rst_n_i),
        .cancel_i(cancel_i),

        // Input DMA and layer format.
        .cfg_in_c4_i(cfg_in_c4_r),
        .line_wr_valid_i(line_wr_valid_i),
        .line_wr_ready_o(line_wr_ready_o),
        .line_wr_bank_i(line_wr_bank_i),
        .line_wr_addr_i(line_wr_addr_i),
        .line_wr_data_i(line_wr_data_i),
        .line_wr_row_last_i(line_wr_row_last_i),
        .line_wr_row_done_o(line_wr_row_done_o),
        .line_wr_idle_o(line_wr_idle_o),

        // Normalized cache writes.
        .cache_wr_valid_o(cache_wr_valid_w),
        .cache_wr_bank_o(cache_wr_bank_w),
        .cache_wr_addr_o(cache_wr_addr_w),
        .cache_wr_data_o(cache_wr_data_w)
    );

    // A2/A3 reads run in parallel with the resident weight pool.
    edrv32_npu_line_cache u_line_cache (
        // Clock; RAM contents and read data have no reset.
        .clk_i(clk_i),

        // Normalized input writes.
        .cache_wr_valid_i(cache_wr_valid_w),
        .cache_wr_bank_i(cache_wr_bank_w),
        .cache_wr_addr_i(cache_wr_addr_w),
        .cache_wr_data_i(cache_wr_data_w),

        // Independent two-stage synchronous read ports.
        .cache_rd_en_i(cache_rd_en_w),
        .cache_rd_addr0_i(cache_rd_addr0_w),
        .cache_rd_addr1_i(cache_rd_addr1_w),
        .cache_rd_data0_o(cache_rd_data0_w),
        .cache_rd_data1_o(cache_rd_data1_w)
    );

    // Window owns both contexts and all A1-A5 address/data alignment.
    edrv32_npu_window u_window (
        // Clock and cancellation.
        .clk_i(clk_i),
        .rst_n_i(rst_n_i),
        .cancel_i(cancel_i),

        // Layer shadow fields.
        .cfg_k3_i(cfg_k3_r),
        .cfg_s2_i(cfg_s2_r),
        .cfg_in_c4_i(cfg_in_c4_r),
        .cfg_half_tail_i(cfg_half_tail_r),
        .cfg_lut_en_i(cfg_lut_en_r),
        .cfg_res_en_i(cfg_res_en_r),
        .cfg_out_zp_i(cfg_out_zp_r),
        .cfg_in_w_i(cfg_in_w_r),
        .cfg_out_w_i(cfg_out_w_r),
        .cfg_cin_blocks_i(cfg_cin_blocks_r),
        .cfg_cout_blocks_i(cfg_cout_blocks_r),
        .cfg_k_count_i(cfg_k_count_r),

        // Ordered row/block commands.
        .cmd_valid_i(cmd_valid_i),
        .cmd_ready_o(cmd_ready_o),
        .cmd_row_i(cmd_row_i),
        .cmd_block_i(cmd_block_i),
        .cmd_weight_base_i(cmd_weight_base_i),
        .cmd_row_base0_i(cmd_row_base0_i),
        .cmd_row_base1_i(cmd_row_base1_i),
        .cmd_row_base2_i(cmd_row_base2_i),
        .cmd_row_valid_i(cmd_row_valid_i),

        // Pair entry credit and execution control.
        .issue_enable_i(issue_enable_i),
        .pair_ready_i(pair_ready_w),
        .pair_result_slot_i(pair_result_slot_w),
        .pair_residual_addr_i(pair_residual_addr_w),
        .pair_fire_o(pair_fire_w),
        .pair_half_o(pair_half_w),

        // Registered A1 cache requests and A3 return.
        .cache_rd_en_o(cache_rd_en_w),
        .cache_rd_addr0_o(cache_rd_addr0_w),
        .cache_rd_addr1_o(cache_rd_addr1_w),
        .cache_rd_data0_i(cache_rd_data0_w),
        .cache_rd_data1_i(cache_rd_data1_w),

        // Parallel weight reads.
        .weight_rd_en_o(weight_rd_en_w),
        .weight_rd_addr_o(weight_rd_addr_w),
        .weight_rd_data_i(weight_rd_data_w),

        // Unstalled A5 terms.
        .term_valid_o(term_valid_w),
        .term_first_o(term_first_w),
        .term_last_o(term_last_w),
        .term_tag_o(term_tag_w),
        .term_activation_o(term_activation_w),
        .term_weight_o(term_weight_w),

        // Command lifetime notifications.
        .cmd_issued_o(cmd_issued_o),
        .cmd_issued_row_o(cmd_issued_row_o),
        .cmd_issued_block_o(cmd_issued_block_o),
        .cmd_read_done_o(cmd_read_done_o),
        .cmd_read_done_row_o(cmd_read_done_row_o),
        .cmd_read_done_block_o(cmd_read_done_block_o),

        // Local state.
        .idle_o(window_idle_w)
    );

    // Weights return at A3 and are carried through A4/A5 by window.
    edrv32_npu_weight_store u_weight_store (
        // Clock and local control; only the pending write enable is cleared.
        .clk_i(clk_i),
        .rst_n_i(rst_n_i),
        .cancel_i(cancel_i),

        // Sequential DMA beats: low three address bits select the bank.
        .weight_wr_valid_i(weight_wr_valid_i),
        .weight_wr_addr_i(weight_wr_addr_i),
        .weight_wr_data_i(weight_wr_data_i),

        // Parallel K-row read, bank zero in the least significant 256 bits.
        .weight_rd_en_i(weight_rd_en_w),
        .weight_rd_addr_i(weight_rd_addr_w),
        .weight_rd_data_o(weight_rd_data_w)
    );

    // R3 last prepares phase0 at the R4 sampling edge.
    edrv32_npu_quant_param_store u_quant_param_store (
        // Clock and local control; only the pending write enable is cleared.
        .clk_i(clk_i),
        .rst_n_i(rst_n_i),
        .cancel_i(cancel_i),

        // One channel from a decoded 512-byte quantization record.
        .quant_wr_valid_i(quant_wr_valid_i),
        .quant_wr_block_i(quant_wr_block_i),
        .quant_wr_channel_i(quant_wr_channel_i),
        .quant_wr_bias_i(quant_wr_bias_i),
        .quant_wr_mult_i(quant_wr_mult_i),
        .quant_wr_shift_i(quant_wr_shift_i),

        // Eight channels shared by the two quantization pixels.
        .param_rd_en_i(param_rd_en_w),
        .param_rd_block_i(param_rd_block_w),
        .param_rd_phase_i(param_rd_phase_w),
        .param_rd_data_o(param_rd_data_w)
    );

    // A5 directly feeds M1; there is no extra top-level register.
    edrv32_npu_mac_array u_mac_array (
        // Clock and control reset; payload registers are not reset.
        .clk_i(clk_i),
        .rst_n_i(rst_n_i),
        .cancel_i(cancel_i),

        // A5 terms, with four activation copies serving eight channels each.
        .term_valid_i(term_valid_w),
        .term_first_i(term_first_w),
        .term_last_i(term_last_w),
        .term_tag_i(term_tag_w),
        .term_activation_i(term_activation_w),
        .term_weight_i(term_weight_w),

        // R3 sums: [pixel][physical output channel], each signed 19 bits.
        .sum_valid_o(sum_valid_w),
        .sum_first_o(sum_first_w),
        .sum_last_o(sum_last_w),
        .sum_tag_o(sum_tag_w),
        .sum_data_o(sum_data_w),

        // Activity and pipeline occupancy.
        .mac_beat_o(mac_beat_o),
        .idle_o(mac_array_idle_w)
    );

    // Per-term tags select D2 folding before final accumulation.
    edrv32_npu_accum u_accum (
        // Clock and control reset; accumulated data is replaced by each first term.
        .clk_i(clk_i),
        .rst_n_i(rst_n_i),
        .cancel_i(cancel_i),

        // Signed R3 sums, one unstallable term per clock.
        .sum_valid_i(sum_valid_w),
        .sum_first_i(sum_first_w),
        .sum_last_i(sum_last_w),
        .sum_tag_i(sum_tag_w),
        .sum_data_i(sum_data_w),

        // Combinational R4 preparation and registered final ACC vector.
        .quant_prepare_valid_o(quant_prepare_valid_w),
        .quant_prepare_tag_o(quant_prepare_tag_w),
        .accum_valid_o(accum_valid_w),
        .accum_tag_o(accum_tag_w),
        .accum_data_o(accum_data_w),

        // Occupancy of the R4/ACC valid chain.
        .idle_o(accum_idle_w)
    );

    // The quantizer schedules parameter/LUT reads and Q10 residual prefetch.
    edrv32_npu_result_quant u_result_quant (
        // Clock and local control.
        .clk_i(clk_i),
        .rst_n_i(rst_n_i),
        .cancel_i(cancel_i),

        // R4 preparation and ACC final vector.
        .quant_prepare_valid_i(quant_prepare_valid_w),
        .quant_prepare_tag_i(quant_prepare_tag_w),
        .accum_valid_i(accum_valid_w),
        .accum_tag_i(accum_tag_w),
        .accum_data_i(accum_data_w),

        // Two-edge parameter and activation reads.
        .param_rd_en_o(param_rd_en_w),
        .param_rd_block_o(param_rd_block_w),
        .param_rd_phase_o(param_rd_phase_w),
        .param_rd_data_i(param_rd_data_w),
        .lut_rd_en_o(lut_rd_en_w),
        .lut_rd_block_o(lut_rd_block_w),
        .lut_rd_addr_o(lut_rd_addr_w),
        .lut_rd_data_i(lut_rd_data_w),

        // Q10 residual prefetch and Q12 complete pair.
        .residual_rd_en_o(residual_rd_en_w),
        .residual_rd_addr_o(residual_rd_addr_w),
        .quant_valid_o(quant_valid_w),
        .quant_tag_o(quant_tag_w),
        .quant_data_o(quant_data_w),

        // Local pipeline occupancy.
        .idle_o(result_quant_idle_w)
    );

    // Independent synchronous lane reads align with Q11.
    edrv32_npu_activation_lut u_activation_lut (
        // Clock and local control; only the pending write enable is cleared.
        .clk_i(clk_i),
        .rst_n_i(rst_n_i),
        .cancel_i(cancel_i),

        // Broadcast table load, locally registered beside each RAM replica.
        .lut_wr_valid_i(lut_wr_valid_i),
        .lut_wr_block_i(lut_wr_block_i),
        .lut_wr_addr_i(lut_wr_addr_i),
        .lut_wr_data_i(lut_wr_data_i),

        // Each lane supplies its own eight-bit index within the selected block.
        .lut_rd_en_i(lut_rd_en_w),
        .lut_rd_block_i(lut_rd_block_w),
        .lut_rd_addr_i(lut_rd_addr_w),
        .lut_rd_data_o(lut_rd_data_w)
    );

    // Only a pair first consumes one committed residual reservation.
    edrv32_npu_residual_buffer u_residual_buffer (
        // Clock and control.
        .clk_i(clk_i),
        .rst_n_i(rst_n_i),
        .cancel_i(cancel_i),

        // Residual DMA loader.
        .residual_begin_valid_i(residual_begin_valid_i),
        .residual_begin_ready_o(residual_begin_ready_o),
        .residual_begin_bank_i(residual_begin_bank_i),
        .residual_begin_pairs_i(residual_begin_pairs_i),
        .residual_begin_half_i(residual_begin_half_i),
        .residual_wr_valid_i(residual_wr_valid_i),
        .residual_wr_bank_i(residual_wr_bank_i),
        .residual_wr_index_i(residual_wr_index_i),
        .residual_wr_data_i(residual_wr_data_i),
        .residual_commit_i(residual_commit_i),

        // Pair reservation and quantization read port.
        .pair_half_i(pair_half_w),
        .pair_reserve_i(residual_reserve_w),
        .pair_residual_ready_o(pair_residual_ready_w),
        .pair_residual_addr_o(pair_residual_addr_w),
        .residual_rd_en_i(residual_rd_en_w),
        .residual_rd_addr_i(residual_rd_addr_w),
        .residual_rd_valid_o(residual_rd_valid_w),
        .residual_rd_data_o(residual_rd_data_w),

        // Local status.
        .idle_o(residual_buffer_idle_w)
    );

    // Q12 enters WB1; saturation is combinational ahead of the WB2 RAM edge.
    edrv32_npu_residual_add u_residual_add (
        // Clock and control.
        .clk_i(clk_i),
        .rst_n_i(rst_n_i),
        .cancel_i(cancel_i),

        // Q12 pair and the unstallable residual RAM return.
        .quant_valid_i(quant_valid_w),
        .quant_tag_i(quant_tag_w),
        .quant_data_i(quant_data_w),
        .residual_rd_valid_i(residual_rd_valid_w),
        .residual_rd_data_i(residual_rd_data_w),

        // WB2 combinational RAM write inputs.
        .writeback_valid_o(writeback_valid_w),
        .writeback_tag_o(writeback_tag_w),
        .writeback_data_o(writeback_data_w),

        // Local status.
        .idle_o(residual_add_idle_w)
    );

    // WB2 is the result RAM write boundary, and release alone returns credit.
    edrv32_npu_writeback u_writeback (
        // Clock and control.
        .clk_i(clk_i),
        .rst_n_i(rst_n_i),
        .cancel_i(cancel_i),

        // Pair reservation and WB2 completion.
        .writeback_valid_i(writeback_valid_w),
        .writeback_tag_i(writeback_tag_w),
        .writeback_data_i(writeback_data_w),
        .pair_reserve_i(pair_fire_w),
        .pair_result_slot_o(pair_result_slot_w),
        .result_credit_o(result_credit_o),

        // Ordered chunk grant and return of ownership.
        .result_chunk_valid_o(result_chunk_valid_o),
        .result_chunk_ready_i(result_chunk_ready_i),
        .result_chunk_base_o(result_chunk_base_o),
        .result_chunk_pairs_o(result_chunk_pairs_o),
        .result_chunk_row_o(result_chunk_row_o),
        .result_chunk_block_o(result_chunk_block_o),
        .result_chunk_pair_o(result_chunk_pair_o),
        .result_chunk_half_o(result_chunk_half_o),
        .result_chunk_last_o(result_chunk_last_o),
        .result_release_i(result_release_i),

        // DMA read port; index is the absolute ring slot.
        .result_rd_en_i(result_rd_en_i),
        .result_rd_index_i(result_rd_index_i),
        .result_rd_plane_i(result_rd_plane_i),
        .result_rd_valid_o(result_rd_valid_o),
        .result_rd_data_o(result_rd_data_o),

        // Command completion and local status.
        .cmd_done_o(cmd_done_o),
        .cmd_done_row_o(cmd_done_row_o),
        .cmd_done_block_o(cmd_done_block_o),
        .idle_o(writeback_idle_w)
    );
endmodule
