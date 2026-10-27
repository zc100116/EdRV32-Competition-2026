// ============================================================================
// File        : edrv32_fpga_npu_dp_top.v
// Spec        : npu-spec 5.4 item 4; npu-plan N-W1
// Description : Synthesis-measurement top for the NPU datapath alone. Every
//               datapath input is driven by one flop of a serial stimulus
//               shift register, every output is captured in a flop and folded
//               by a registered 6-input XOR tree onto one pin, so place-and-
//               route keeps the whole datapath and reports its own paths.
// Clock       : clk_i only (constrained to the clk_npu target in the .fdc)
// ============================================================================
module edrv32_fpga_npu_dp_top (
    // Board clock and active-low reset key.
    input wire clk_i,
    input wire rst_n_i,

    // Serial stimulus in and folded observation out.
    input wire stim_i,
    output wire obs_o
);

    // Input and output vector widths: sums of the datapath port widths below.
    localparam STIM_BITS = 1025;
    localparam OBS_BITS = 358;
    // Registered XOR tree, 6 inputs per LUT: 358 -> 60 -> 10 -> 2 -> 1.
    localparam L1_BITS = 60;
    localparam L2_BITS = 10;
    localparam L3_BITS = 2;

    wire rst_dp_n_w;

    // Stimulus shift register; each flop drives one datapath input bit.
    reg [STIM_BITS-1:0] stim_r;
    wire [STIM_BITS-1:0] stim_w;

    // Captured datapath outputs and XOR tree levels.
    wire [OBS_BITS-1:0] obs_w;
    reg [OBS_BITS-1:0] obs_r;
    wire [L1_BITS*6-1:0] obs_pad_w;
    reg [L1_BITS-1:0] l1_r;
    wire [L2_BITS*6-1:0] l1_pad_w;
    reg [L2_BITS-1:0] l2_r;
    wire [L3_BITS*6-1:0] l2_pad_w;
    reg [L3_BITS-1:0] l3_r;
    reg obs_bit_r;

    // Datapath outputs.
    wire cfg_ready_w;
    wire line_wr_ready_w;
    wire line_wr_row_done_w;
    wire line_wr_idle_w;
    wire cmd_ready_w;
    wire residual_begin_ready_w;
    wire [5:0] result_credit_w;
    wire result_chunk_valid_w;
    wire [4:0] result_chunk_base_w;
    wire [4:0] result_chunk_pairs_w;
    wire [11:0] result_chunk_row_w;
    wire [2:0] result_chunk_block_w;
    wire [10:0] result_chunk_pair_w;
    wire result_chunk_half_w;
    wire result_chunk_last_w;
    wire result_rd_valid_w;
    wire [255:0] result_rd_data_w;
    wire cmd_issued_w;
    wire [11:0] cmd_issued_row_w;
    wire [2:0] cmd_issued_block_w;
    wire cmd_read_done_w;
    wire [11:0] cmd_read_done_row_w;
    wire [2:0] cmd_read_done_block_w;
    wire cmd_done_w;
    wire [11:0] cmd_done_row_w;
    wire [2:0] cmd_done_block_w;
    wire idle_w;
    wire mac_beat_w;

    edrv32_reset_sync u_reset_sync (
        .clk_i(clk_i),
        .rst_n_i(rst_n_i),
        .rst_n_o(rst_dp_n_w)
    );

    // Stimulus is data, so the shift register is not reset.
    always @(posedge clk_i) begin
        stim_r <= {stim_r[STIM_BITS-2:0], stim_i};
    end
    assign stim_w = stim_r;

    edrv32_npu_datapath u_datapath (
        // Clock and local cancellation.
        .clk_i(clk_i),
        .rst_n_i(rst_dp_n_w),
        .cancel_i(stim_w[0]),

        // Layer configuration.
        .cfg_k3_i(stim_w[1]),
        .cfg_s2_i(stim_w[2]),
        .cfg_in_c4_i(stim_w[3]),
        .cfg_half_tail_i(stim_w[4]),
        .cfg_lut_en_i(stim_w[5]),
        .cfg_res_en_i(stim_w[6]),
        .cfg_out_zp_i(stim_w[14:7]),
        .cfg_in_w_i(stim_w[26:15]),
        .cfg_out_w_i(stim_w[38:27]),
        .cfg_cin_blocks_i(stim_w[44:39]),
        .cfg_cout_blocks_i(stim_w[48:45]),
        .cfg_k_count_i(stim_w[59:49]),
        .cfg_valid_i(stim_w[60]),
        .cfg_ready_o(cfg_ready_w),

        // Input DMA and local row completion.
        .line_wr_valid_i(stim_w[61]),
        .line_wr_ready_o(line_wr_ready_w),
        .line_wr_bank_i(stim_w[62]),
        .line_wr_addr_i(stim_w[72:63]),
        .line_wr_data_i(stim_w[328:73]),
        .line_wr_row_last_i(stim_w[329]),
        .line_wr_row_done_o(line_wr_row_done_w),
        .line_wr_idle_o(line_wr_idle_w),

        // Resident weights, quantization parameters and activation tables.
        .weight_wr_valid_i(stim_w[330]),
        .weight_wr_addr_i(stim_w[344:331]),
        .weight_wr_data_i(stim_w[600:345]),
        .quant_wr_valid_i(stim_w[601]),
        .quant_wr_block_i(stim_w[604:602]),
        .quant_wr_channel_i(stim_w[609:605]),
        .quant_wr_bias_i(stim_w[641:610]),
        .quant_wr_mult_i(stim_w[657:642]),
        .quant_wr_shift_i(stim_w[663:658]),
        .lut_wr_valid_i(stim_w[664]),
        .lut_wr_block_i(stim_w[667:665]),
        .lut_wr_addr_i(stim_w[675:668]),
        .lut_wr_data_i(stim_w[683:676]),

        // Commands.
        .cmd_valid_i(stim_w[684]),
        .cmd_row_i(stim_w[696:685]),
        .cmd_block_i(stim_w[699:697]),
        .cmd_weight_base_i(stim_w[710:700]),
        .cmd_row_base0_i(stim_w[720:711]),
        .cmd_row_base1_i(stim_w[730:721]),
        .cmd_row_base2_i(stim_w[740:731]),
        .cmd_row_valid_i(stim_w[743:741]),
        .cmd_ready_o(cmd_ready_w),
        .issue_enable_i(stim_w[744]),

        // Residual prefetch.
        .residual_begin_valid_i(stim_w[745]),
        .residual_begin_ready_o(residual_begin_ready_w),
        .residual_begin_bank_i(stim_w[746]),
        .residual_begin_pairs_i(stim_w[751:747]),
        .residual_begin_half_i(stim_w[752]),
        .residual_wr_valid_i(stim_w[753]),
        .residual_wr_bank_i(stim_w[754]),
        .residual_wr_index_i(stim_w[758:755]),
        .residual_wr_data_i(stim_w[1014:759]),
        .residual_commit_i(stim_w[1015]),

        // Result ring to the write DMA.
        .result_credit_o(result_credit_w),
        .result_chunk_valid_o(result_chunk_valid_w),
        .result_chunk_ready_i(stim_w[1016]),
        .result_chunk_base_o(result_chunk_base_w),
        .result_chunk_pairs_o(result_chunk_pairs_w),
        .result_chunk_row_o(result_chunk_row_w),
        .result_chunk_block_o(result_chunk_block_w),
        .result_chunk_pair_o(result_chunk_pair_w),
        .result_chunk_half_o(result_chunk_half_w),
        .result_chunk_last_o(result_chunk_last_w),
        .result_release_i(stim_w[1017]),
        .result_rd_en_i(stim_w[1018]),
        .result_rd_index_i(stim_w[1023:1019]),
        .result_rd_plane_i(stim_w[1024]),
        .result_rd_valid_o(result_rd_valid_w),
        .result_rd_data_o(result_rd_data_w),

        // Command progress and status.
        .cmd_issued_o(cmd_issued_w),
        .cmd_issued_row_o(cmd_issued_row_w),
        .cmd_issued_block_o(cmd_issued_block_w),
        .cmd_read_done_o(cmd_read_done_w),
        .cmd_read_done_row_o(cmd_read_done_row_w),
        .cmd_read_done_block_o(cmd_read_done_block_w),
        .cmd_done_o(cmd_done_w),
        .cmd_done_row_o(cmd_done_row_w),
        .cmd_done_block_o(cmd_done_block_w),
        .idle_o(idle_w),
        .mac_beat_o(mac_beat_w)
    );

    assign obs_w = {
        cfg_ready_w,
        line_wr_ready_w,
        line_wr_row_done_w,
        line_wr_idle_w,
        cmd_ready_w,
        residual_begin_ready_w,
        result_credit_w,
        result_chunk_valid_w,
        result_chunk_base_w,
        result_chunk_pairs_w,
        result_chunk_row_w,
        result_chunk_block_w,
        result_chunk_pair_w,
        result_chunk_half_w,
        result_chunk_last_w,
        result_rd_valid_w,
        result_rd_data_w,
        cmd_issued_w,
        cmd_issued_row_w,
        cmd_issued_block_w,
        cmd_read_done_w,
        cmd_read_done_row_w,
        cmd_read_done_block_w,
        cmd_done_w,
        cmd_done_row_w,
        cmd_done_block_w,
        idle_w,
        mac_beat_w
    };

    assign obs_pad_w = {{(L1_BITS*6-OBS_BITS){1'b0}}, obs_r};
    assign l1_pad_w = {{(L2_BITS*6-L1_BITS){1'b0}}, l1_r};
    assign l2_pad_w = {{(L3_BITS*6-L2_BITS){1'b0}}, l2_r};

    // Observation flops and the XOR tree carry data only, so they are not reset.
    always @(posedge clk_i) begin
        obs_r <= obs_w;
    end

    genvar g_i;
    generate
        for (g_i = 0; g_i < L1_BITS; g_i = g_i + 1) begin : g_l1
            always @(posedge clk_i) begin
                l1_r[g_i] <= ^obs_pad_w[g_i*6 +: 6];
            end
        end
        for (g_i = 0; g_i < L2_BITS; g_i = g_i + 1) begin : g_l2
            always @(posedge clk_i) begin
                l2_r[g_i] <= ^l1_pad_w[g_i*6 +: 6];
            end
        end
        for (g_i = 0; g_i < L3_BITS; g_i = g_i + 1) begin : g_l3
            always @(posedge clk_i) begin
                l3_r[g_i] <= ^l2_pad_w[g_i*6 +: 6];
            end
        end
    endgenerate

    always @(posedge clk_i) begin
        obs_bit_r <= ^l3_r;
    end
    assign obs_o = obs_bit_r;

endmodule
