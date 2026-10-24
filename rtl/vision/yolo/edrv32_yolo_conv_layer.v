// ============================================================================
// File        : edrv32_yolo_conv_layer.v
// Description : One DDR-to-DDR, 32-output-channel INT8 convolution layer.
// Notes       : C16 feature surfaces use [block][row][pixel pair] layout.
//               Weights stay resident across all output rows. Five source
//               rows are tagged in the cache. Two activation RAM halves
//               alternate between patch generation and convolution.
//               Configuration requires even output width, input width a
//               multiple of four and tile_pairs * K <= 1024. Three-by-three
//               uses five row slots; one-by-one reuses slot zero each row.
// ============================================================================

module edrv32_yolo_conv_layer (
    input  wire          clk_i,
    input  wire          rst_n_i,

    input  wire          start_i,
    output wire          start_ready_o,
    input  wire [31:0]   feature_base_i,
    input  wire [31:0]   feature_plane_stride_i,
    input  wire [31:0]   weight_base_i,
    input  wire [31:0]   output_plane0_base_i,
    input  wire [31:0]   output_plane1_base_i,
    input  wire          output_plane1_enable_i,
    input  wire [10:0]   input_width_i,
    input  wire [15:0]   input_height_i,
    input  wire [9:0]    output_width_pairs_i,
    input  wire [15:0]   output_height_i,
    input  wire [5:0]    cin_blocks_i,
    input  wire [8:0]    cache_bank_stride_i,
    input  wire [9:0]    cache_row_stride_i,
    input  wire [9:0]    tile_pairs_i,
    input  wire          kernel3_i,
    input  wire          stride2_i,
    output wire          busy_o,
    output wire          done_o,
    output wire          error_o,
    output wire          mac_beat_o,
    output wire          weight_phase_o,
    output wire          feature_phase_o,
    output wire          run_phase_o,

    input  wire          quant_cfg_valid_i,
    output wire          quant_cfg_ready_o,
    input  wire [4:0]    quant_cfg_channel_i,
    input  wire [31:0]   quant_cfg_bias_i,
    input  wire [15:0]   quant_cfg_multiplier_i,
    input  wire [5:0]    quant_cfg_shift_i,
    input  wire [7:0]    quant_cfg_zero_point_i,
    input  wire          lut_enable_i,
    input  wire          lut_cfg_valid_i,
    output wire          lut_cfg_ready_o,
    input  wire [7:0]    lut_cfg_addr_i,
    input  wire [7:0]    lut_cfg_data_i,

    output wire [3:0]    m_arid_o,
    output wire [31:0]   m_araddr_o,
    output wire [7:0]    m_arlen_o,
    output wire [2:0]    m_arsize_o,
    output wire [1:0]    m_arburst_o,
    output wire          m_arvalid_o,
    input  wire          m_arready_i,
    input  wire [3:0]    m_rid_i,
    input  wire [255:0]  m_rdata_i,
    input  wire [1:0]    m_rresp_i,
    input  wire          m_rlast_i,
    input  wire          m_rvalid_i,
    output wire          m_rready_o,

    output wire [3:0]    m_awid_o,
    output wire [31:0]   m_awaddr_o,
    output wire [7:0]    m_awlen_o,
    output wire [2:0]    m_awsize_o,
    output wire [1:0]    m_awburst_o,
    output wire          m_awvalid_o,
    input  wire          m_awready_i,
    output wire [255:0]  m_wdata_o,
    output wire [31:0]   m_wstrb_o,
    output wire          m_wlast_o,
    output wire          m_wvalid_o,
    input  wire          m_wready_i,
    input  wire [3:0]    m_bid_i,
    input  wire [1:0]    m_bresp_i,
    input  wire          m_bvalid_i,
    output wire          m_bready_o
);

    localparam [2:0] S_IDLE         = 3'd0;
    localparam [2:0] S_WEIGHT_START = 3'd1;
    localparam [2:0] S_WEIGHT_WAIT  = 3'd2;
    localparam [2:0] S_ROW_PREP     = 3'd3;
    localparam [2:0] S_FEATURE_WAIT = 3'd4;
    localparam [2:0] S_ROW_START    = 3'd5;
    localparam [2:0] S_ROW_RUN      = 3'd6;

    reg [2:0] state_r;
    reg done_r;
    reg error_r;
    reg [31:0] feature_plane_stride_r;
    reg [31:0] input_row_bytes_r;
    reg [31:0] source_base_ddr_r;
    reg [31:0] weight_base_r;
    reg [31:0] output_plane0_r;
    reg [31:0] output_plane1_r;
    reg output_plane1_enable_r;
    reg [10:0] input_width_r;
    reg [15:0] input_height_r;
    reg [9:0] output_width_pairs_r;
    reg [15:0] output_height_r;
    reg [5:0] cin_blocks_r;
    reg [8:0] cache_bank_stride_r;
    reg [9:0] cache_row_stride_r;
    reg [9:0] tile_pairs_r;
    reg kernel3_r;
    reg stride2_r;
    reg lut_enable_r;
    reg [9:0] k_count_r;
    reg [15:0] output_y_r;
    reg signed [16:0] source_base_r;
    reg [2:0] first_slot_r;
    reg [1:0] prep_ky_r;
    reg [2:0] loading_slot_r;
    reg [15:0] loading_row_r;
    reg [2:0] row_valid_r;
    reg [9:0] row_base_r [0:2];
    reg [4:0] cache_valid_r;
    reg [15:0] cache_tag_r [0:4];

    reg [9:0] next_pair_r;
    reg fill_half_r;
    reg run_half_r;
    reg patch_filling_r;
    reg patch_half_r;
    reg compute_running_r;
    reg compute_half_r;
    reg [1:0] half_ready_r;
    reg [1:0] half_busy_r;
    reg [9:0] half_pairs_r [0:1];

    wire [9:0] k_count_w = kernel3_i ?
        ({4'd0, cin_blocks_i} << 4) +
        ({4'd0, cin_blocks_i} << 1) :
        {3'd0, cin_blocks_i, 1'b0};
    wire signed [16:0] source_y_w =
        source_base_r + $signed({15'd0, prep_ky_r});
    wire [31:0] config_row_bytes_w = {17'd0, input_width_i, 4'd0};
    wire [31:0] prep_row_addr_w = source_base_ddr_r +
        (prep_ky_r == 2'd0 ? 32'd0 :
         prep_ky_r == 2'd1 ? input_row_bytes_r :
                              (input_row_bytes_r << 1));
    wire source_valid_w = source_y_w >= 17'sd0 &&
                          source_y_w < $signed({1'b0, input_height_r});
    wire [3:0] slot_sum_w = {1'b0, first_slot_r} +
                            {2'd0, prep_ky_r};
    wire [3:0] next_first_slot_sum_w = {1'b0, first_slot_r} +
                                       (stride2_r ? 4'd2 : 4'd1);
    wire [2:0] next_first_slot_w = !kernel3_r ? 3'd0 :
        next_first_slot_sum_w >= 4'd5 ?
        next_first_slot_sum_w[2:0] - 3'd5 : next_first_slot_sum_w[2:0];
    wire [2:0] prep_slot_w = !kernel3_r ? 3'd0 :
        slot_sum_w >= 4'd5 ? slot_sum_w[2:0] - 3'd5 : slot_sum_w[2:0];
    wire [9:0] slot_base0_w = cache_row_stride_r;
    wire [9:0] slot_base1_w = cache_row_stride_r << 1;
    wire [9:0] slot_base2_w = slot_base1_w + cache_row_stride_r;
    wire [9:0] slot_base3_w = slot_base2_w + cache_row_stride_r;
    wire [9:0] slot_base4_w = slot_base3_w + cache_row_stride_r;
    reg [9:0] prep_row_base_w;
    always @(*) begin
        prep_row_base_w = 10'd0;
        case (prep_slot_w)
            3'd0: prep_row_base_w = 10'd0;
            3'd1: prep_row_base_w = slot_base0_w;
            3'd2: prep_row_base_w = slot_base1_w;
            3'd3: prep_row_base_w = slot_base2_w;
            3'd4: prep_row_base_w = slot_base3_w;
            default: prep_row_base_w = slot_base4_w;
        endcase
    end
    wire cache_hit_w = cache_valid_r[prep_slot_w] &&
                       cache_tag_r[prep_slot_w] == source_y_w[15:0];
    wire [9:0] remaining_pairs_w = output_width_pairs_r - next_pair_r;
    wire [9:0] next_chunk_pairs_w = remaining_pairs_w < tile_pairs_r ?
                                     remaining_pairs_w : tile_pairs_r;
    wire patch_start_w;
    wire conv_start_w;
    wire feature_start_w;
    wire weight_start_w;
    wire writer_start_w = state_r == S_ROW_START;

    wire reader_req_ready_w;
    wire reader_beat_valid_w;
    wire [15:0] reader_beat_index_w;
    wire [255:0] reader_beat_data_w;
    wire reader_done_w;
    wire reader_error_w;
    wire reader_busy_w;
    wire weight_req_valid_w;
    wire [31:0] weight_req_addr_w;
    wire [15:0] weight_req_beats_w;
    wire feature_req_valid_w;
    wire [31:0] feature_req_addr_w;
    wire [15:0] feature_req_beats_w;
    wire weight_ready_w;
    wire weight_done_w;
    wire weight_error_w;
    wire weight_busy_w;
    wire feature_ready_w;
    wire feature_done_w;
    wire feature_error_w;
    wire feature_busy_w;
    wire weight_data_valid_w;
    wire [11:0] weight_data_addr_w;
    wire [255:0] weight_data_w;
    wire cache_wr_valid_w;
    wire cache_wr_bank_w;
    wire [9:0] cache_wr_addr_w;
    wire [255:0] cache_wr_data_w;
    wire cache_rd_valid_w;
    wire cache_rd_ready_w;
    wire cache_rd_bank0_w;
    wire cache_rd_bank1_w;
    wire [9:0] cache_rd_addr0_w;
    wire [9:0] cache_rd_addr1_w;
    wire cache_result_valid_w;
    wire [255:0] cache_rd_data0_w;
    wire [255:0] cache_rd_data1_w;
    wire patch_ready_w;
    wire patch_done_w;
    wire patch_busy_w;
    wire activation_valid_w;
    wire [10:0] activation_addr_w;
    wire [127:0] activation_data_w;
    wire conv_ready_w;
    wire conv_done_w;
    wire conv_busy_w;
    wire conv_weight_ready_w;
    wire conv_activation_ready_w;
    wire conv_result_valid_w;
    wire conv_result_ready_w;
    wire conv_result_last_w;
    wire [11:0] conv_result_pair_w;
    wire [2047:0] conv_result_accum_w;
    wire quant_valid_w;
    wire quant_ready_w;
    wire [511:0] quant_data_w;
    wire writer_ready_w;
    wire writer_done_w;
    wire writer_error_w;
    wire writer_busy_w;

    assign start_ready_o = state_r == S_IDLE && cin_blocks_i != 6'd0 &&
                           k_count_w <= 10'd512 &&
                           input_width_i != 11'd0 &&
                           input_height_i != 16'd0 &&
                           output_width_pairs_i != 10'd0 &&
                           output_height_i != 16'd0 &&
                           tile_pairs_i != 10'd0;
    assign busy_o = state_r != S_IDLE;
    assign weight_phase_o = state_r == S_WEIGHT_START ||
                            state_r == S_WEIGHT_WAIT;
    assign feature_phase_o = state_r == S_FEATURE_WAIT;
    assign run_phase_o = state_r == S_ROW_RUN;
    assign done_o = done_r;
    assign error_o = error_r;
    assign weight_start_w = state_r == S_WEIGHT_START;
    assign feature_start_w = state_r == S_ROW_PREP && source_valid_w &&
                             !cache_hit_w && feature_ready_w;
    assign patch_start_w = state_r == S_ROW_RUN &&
                           next_pair_r < output_width_pairs_r &&
                           !patch_filling_r && !half_ready_r[fill_half_r] &&
                           !half_busy_r[fill_half_r] && patch_ready_w;
    assign conv_start_w = state_r == S_ROW_RUN &&
                          !compute_running_r &&
                          half_ready_r[run_half_r] && conv_ready_w;

    edrv32_yolo_axi_reader u_reader (
        .clk_i(clk_i), .rst_n_i(rst_n_i),
        .req_valid_i(weight_busy_w ? weight_req_valid_w :
                     feature_req_valid_w),
        .req_ready_o(reader_req_ready_w),
        .req_addr_i(weight_busy_w ? weight_req_addr_w :
                    feature_req_addr_w),
        .req_beats_i(weight_busy_w ? weight_req_beats_w :
                     feature_req_beats_w),
        .beat_valid_o(reader_beat_valid_w),
        .beat_index_o(reader_beat_index_w),
        .beat_data_o(reader_beat_data_w),
        .busy_o(reader_busy_w), .done_o(reader_done_w),
        .error_o(reader_error_w),
        .m_arid_o(m_arid_o), .m_araddr_o(m_araddr_o),
        .m_arlen_o(m_arlen_o[3:0]), .m_arsize_o(m_arsize_o),
        .m_arburst_o(m_arburst_o), .m_arvalid_o(m_arvalid_o),
        .m_arready_i(m_arready_i), .m_rid_i(m_rid_i),
        .m_rdata_i(m_rdata_i), .m_rresp_i(m_rresp_i),
        .m_rlast_i(m_rlast_i), .m_rvalid_i(m_rvalid_i),
        .m_rready_o(m_rready_o)
    );
    assign m_arlen_o[7:4] = 4'd0;

    edrv32_yolo_weight_loader u_weight_loader (
        .clk_i(clk_i), .rst_n_i(rst_n_i),
        .start_i(weight_start_w), .start_ready_o(weight_ready_w),
        .weight_addr_i(weight_base_r), .k_count_i(k_count_r),
        .rd_req_valid_o(weight_req_valid_w),
        .rd_req_ready_i(reader_req_ready_w && weight_busy_w),
        .rd_req_addr_o(weight_req_addr_w),
        .rd_req_beats_o(weight_req_beats_w),
        .rd_beat_valid_i(reader_beat_valid_w && weight_busy_w),
        .rd_beat_index_i(reader_beat_index_w),
        .rd_beat_data_i(reader_beat_data_w),
        .rd_done_i(reader_done_w && weight_busy_w),
        .rd_error_i(reader_error_w),
        .weight_valid_o(weight_data_valid_w),
        .weight_ready_i(conv_weight_ready_w),
        .weight_addr_o(weight_data_addr_w),
        .weight_data_o(weight_data_w),
        .busy_o(weight_busy_w), .done_o(weight_done_w),
        .error_o(weight_error_w)
    );

    edrv32_yolo_feature_loader u_feature_loader (
        .clk_i(clk_i), .rst_n_i(rst_n_i),
        .start_i(feature_start_w), .start_ready_o(feature_ready_w),
        .row_addr_i(prep_row_addr_w),
        .plane_stride_i(feature_plane_stride_r),
        .cache_row_base_i(prep_row_base_w),
        .bank_stride_i(cache_bank_stride_r),
        .width_pairs_i(input_width_r[10:1]),
        .channel_blocks_i(cin_blocks_r),
        .rd_req_valid_o(feature_req_valid_w),
        .rd_req_ready_i(reader_req_ready_w && !weight_busy_w),
        .rd_req_addr_o(feature_req_addr_w),
        .rd_req_beats_o(feature_req_beats_w),
        .rd_beat_valid_i(reader_beat_valid_w && !weight_busy_w),
        .rd_beat_index_i(reader_beat_index_w),
        .rd_beat_data_i(reader_beat_data_w),
        .rd_done_i(reader_done_w && !weight_busy_w),
        .rd_error_i(reader_error_w),
        .cache_wr_valid_o(cache_wr_valid_w),
        .cache_wr_bank_o(cache_wr_bank_w),
        .cache_wr_addr_o(cache_wr_addr_w),
        .cache_wr_data_o(cache_wr_data_w),
        .busy_o(feature_busy_w), .done_o(feature_done_w),
        .error_o(feature_error_w)
    );

    edrv32_yolo_line_cache u_line_cache (
        .clk_i(clk_i), .rst_n_i(rst_n_i),
        .wr_valid_i(cache_wr_valid_w), .wr_bank_i(cache_wr_bank_w),
        .wr_addr_i(cache_wr_addr_w), .wr_data_i(cache_wr_data_w),
        .rd_valid_i(cache_rd_valid_w), .rd_ready_o(cache_rd_ready_w),
        .rd_bank0_i(cache_rd_bank0_w), .rd_addr0_i(cache_rd_addr0_w),
        .rd_bank1_i(cache_rd_bank1_w), .rd_addr1_i(cache_rd_addr1_w),
        .rd_valid_o(cache_result_valid_w),
        .rd_data0_o(cache_rd_data0_w),
        .rd_data1_o(cache_rd_data1_w)
    );

    edrv32_yolo_patch_gen u_patch_gen (
        .clk_i(clk_i), .rst_n_i(rst_n_i),
        .start_i(patch_start_w), .start_ready_o(patch_ready_w),
        .kernel3_i(kernel3_r), .stride2_i(stride2_r),
        .input_width_i(input_width_r),
        .cin_blocks_i(cin_blocks_r),
        .block_bank_stride_i(cache_bank_stride_r),
        .pair_x_base_i(next_pair_r),
        .pair_count_i(next_chunk_pairs_w),
        .activation_base_i(fill_half_r ? 11'd1024 : 11'd0),
        .row_base0_i(row_base_r[0]),
        .row_base1_i(row_base_r[1]),
        .row_base2_i(row_base_r[2]),
        .row_valid_i(row_valid_r),
        .cache_rd_valid_o(cache_rd_valid_w),
        .cache_rd_ready_i(cache_rd_ready_w),
        .cache_rd_bank0_o(cache_rd_bank0_w),
        .cache_rd_addr0_o(cache_rd_addr0_w),
        .cache_rd_bank1_o(cache_rd_bank1_w),
        .cache_rd_addr1_o(cache_rd_addr1_w),
        .cache_rd_data0_i(cache_rd_data0_w),
        .cache_rd_data1_i(cache_rd_data1_w),
        .activation_valid_o(activation_valid_w),
        .activation_addr_o(activation_addr_w),
        .activation_data_o(activation_data_w),
        .busy_o(patch_busy_w), .done_o(patch_done_w)
    );

    edrv32_yolo_conv_tile u_conv (
        .clk_i(clk_i), .rst_n_i(rst_n_i),
        .weight_valid_i(weight_data_valid_w),
        .weight_ready_o(conv_weight_ready_w),
        .weight_addr_i(weight_data_addr_w),
        .weight_data_i(weight_data_w),
        .activation_valid_i(activation_valid_w),
        .activation_ready_o(conv_activation_ready_w),
        .activation_addr_i(activation_addr_w),
        .activation_data_i(activation_data_w),
        .start_i(conv_start_w), .start_ready_o(conv_ready_w),
        .activation_base_i(run_half_r ? 11'd1024 : 11'd0),
        .k_count_i(k_count_r),
        .pair_count_i({2'd0, half_pairs_r[run_half_r]}),
        .busy_o(conv_busy_w), .done_o(conv_done_w),
        .mac_beat_o(mac_beat_o),
        .result_valid_o(conv_result_valid_w),
        .result_ready_i(conv_result_ready_w),
        .result_last_o(conv_result_last_w),
        .result_pair_o(conv_result_pair_w),
        .result_accum_o(conv_result_accum_w)
    );

    edrv32_yolo_result_quant u_quant (
        .clk_i(clk_i), .rst_n_i(rst_n_i),
        .in_valid_i(conv_result_valid_w),
        .in_ready_o(conv_result_ready_w),
        .in_last_i(conv_result_last_w),
        .in_pair_i(conv_result_pair_w),
        .in_accum_i(conv_result_accum_w),
        .out_valid_o(quant_valid_w),
        .out_ready_i(quant_ready_w),
        .out_last_o(), .out_pair_o(),
        .out_data_o(quant_data_w),
        .cfg_valid_i(quant_cfg_valid_i),
        .cfg_ready_o(quant_cfg_ready_o),
        .cfg_channel_i(quant_cfg_channel_i),
        .cfg_bias_i(quant_cfg_bias_i),
        .cfg_multiplier_i(quant_cfg_multiplier_i),
        .cfg_shift_i(quant_cfg_shift_i),
        .cfg_zero_point_i(quant_cfg_zero_point_i),
        .lut_enable_i(lut_enable_r),
        .lut_cfg_valid_i(lut_cfg_valid_i),
        .lut_cfg_ready_o(lut_cfg_ready_o),
        .lut_cfg_addr_i(lut_cfg_addr_i),
        .lut_cfg_data_i(lut_cfg_data_i)
    );

    edrv32_yolo_axi_writer u_writer (
        .clk_i(clk_i), .rst_n_i(rst_n_i),
        .start_i(writer_start_w), .start_ready_o(writer_ready_w),
        .plane0_addr_i(output_plane0_r),
        .plane1_addr_i(output_plane1_r),
        .emit_plane1_i(output_plane1_enable_r),
        .pair_count_i(output_width_pairs_r),
        .in_valid_i(quant_valid_w), .in_ready_o(quant_ready_w),
        .in_data_i(quant_data_w),
        .busy_o(writer_busy_w), .done_o(writer_done_w),
        .error_o(writer_error_w),
        .m_awid_o(m_awid_o), .m_awaddr_o(m_awaddr_o),
        .m_awlen_o(m_awlen_o), .m_awsize_o(m_awsize_o),
        .m_awburst_o(m_awburst_o), .m_awvalid_o(m_awvalid_o),
        .m_awready_i(m_awready_i), .m_wdata_o(m_wdata_o),
        .m_wstrb_o(m_wstrb_o), .m_wlast_o(m_wlast_o),
        .m_wvalid_o(m_wvalid_o), .m_wready_i(m_wready_i),
        .m_bid_i(m_bid_i), .m_bresp_i(m_bresp_i),
        .m_bvalid_i(m_bvalid_i), .m_bready_o(m_bready_o)
    );

    integer slot;
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            state_r                <= S_IDLE;
            done_r                 <= 1'b0;
            error_r                <= 1'b0;
            feature_plane_stride_r <= 32'd0;
            input_row_bytes_r      <= 32'd0;
            source_base_ddr_r      <= 32'd0;
            weight_base_r          <= 32'd0;
            output_plane0_r        <= 32'd0;
            output_plane1_r        <= 32'd0;
            output_plane1_enable_r <= 1'b0;
            input_width_r          <= 11'd0;
            input_height_r         <= 16'd0;
            output_width_pairs_r   <= 10'd0;
            output_height_r        <= 16'd0;
            cin_blocks_r           <= 6'd0;
            cache_bank_stride_r    <= 9'd0;
            cache_row_stride_r     <= 10'd0;
            tile_pairs_r           <= 10'd0;
            kernel3_r              <= 1'b0;
            stride2_r              <= 1'b0;
            lut_enable_r           <= 1'b0;
            k_count_r              <= 10'd0;
            output_y_r             <= 16'd0;
            source_base_r          <= 17'sd0;
            first_slot_r           <= 3'd0;
            prep_ky_r              <= 2'd0;
            loading_slot_r         <= 3'd0;
            loading_row_r          <= 16'd0;
            row_valid_r            <= 3'd0;
            cache_valid_r          <= 5'd0;
            next_pair_r            <= 10'd0;
            fill_half_r            <= 1'b0;
            run_half_r             <= 1'b0;
            patch_filling_r        <= 1'b0;
            patch_half_r           <= 1'b0;
            compute_running_r      <= 1'b0;
            compute_half_r         <= 1'b0;
            half_ready_r           <= 2'b00;
            half_busy_r            <= 2'b00;
            for (slot = 0; slot < 5; slot = slot + 1)
                cache_tag_r[slot] <= 16'd0;
        end else begin
            done_r <= 1'b0;
            if (start_i && start_ready_o) begin
                feature_plane_stride_r <= feature_plane_stride_i;
                input_row_bytes_r      <= config_row_bytes_w;
                source_base_ddr_r      <= feature_base_i -
                    (kernel3_i ? config_row_bytes_w : 32'd0);
                weight_base_r          <= weight_base_i;
                output_plane0_r        <= output_plane0_base_i;
                output_plane1_r        <= output_plane1_base_i;
                output_plane1_enable_r <= output_plane1_enable_i;
                input_width_r          <= input_width_i;
                input_height_r         <= input_height_i;
                output_width_pairs_r   <= output_width_pairs_i;
                output_height_r        <= output_height_i;
                cin_blocks_r           <= cin_blocks_i;
                cache_bank_stride_r    <= cache_bank_stride_i;
                cache_row_stride_r     <= cache_row_stride_i;
                tile_pairs_r           <= tile_pairs_i;
                kernel3_r              <= kernel3_i;
                stride2_r              <= stride2_i;
                lut_enable_r           <= lut_enable_i;
                k_count_r              <= k_count_w;
                output_y_r             <= 16'd0;
                source_base_r          <= kernel3_i ? -17'sd1 : 17'sd0;
                first_slot_r           <= 3'd0;
                prep_ky_r              <= 2'd0;
                cache_valid_r          <= 5'd0;
                row_valid_r            <= 3'd0;
                error_r                <= 1'b0;
                state_r                <= S_WEIGHT_START;
            end else begin
                case (state_r)
                    S_WEIGHT_START: if (weight_ready_w)
                        state_r <= S_WEIGHT_WAIT;
                    S_WEIGHT_WAIT: if (weight_done_w) begin
                        if (weight_error_w)
                            error_r <= 1'b1;
                        prep_ky_r <= 2'd0;
                        row_valid_r <= 3'd0;
                        state_r <= S_ROW_PREP;
                    end
                    S_ROW_PREP: begin
                        row_base_r[prep_ky_r] <= prep_row_base_w;
                        row_valid_r[prep_ky_r] <= source_valid_w;
                        if (!source_valid_w || cache_hit_w) begin
                            if (prep_ky_r == (kernel3_r ? 2'd2 : 2'd0))
                                state_r <= S_ROW_START;
                            else
                                prep_ky_r <= prep_ky_r + 2'd1;
                        end else if (feature_start_w) begin
                            loading_slot_r <= prep_slot_w;
                            loading_row_r <= source_y_w[15:0];
                            state_r <= S_FEATURE_WAIT;
                        end
                    end
                    S_FEATURE_WAIT: if (feature_done_w) begin
                        if (feature_error_w)
                            error_r <= 1'b1;
                        cache_valid_r[loading_slot_r] <= 1'b1;
                        cache_tag_r[loading_slot_r] <= loading_row_r;
                        if (prep_ky_r == (kernel3_r ? 2'd2 : 2'd0))
                            state_r <= S_ROW_START;
                        else begin
                            prep_ky_r <= prep_ky_r + 2'd1;
                            state_r <= S_ROW_PREP;
                        end
                    end
                    S_ROW_START: if (writer_ready_w) begin
                        next_pair_r       <= 10'd0;
                        fill_half_r       <= 1'b0;
                        run_half_r        <= 1'b0;
                        patch_filling_r   <= 1'b0;
                        compute_running_r <= 1'b0;
                        half_ready_r      <= 2'b00;
                        half_busy_r       <= 2'b00;
                        state_r           <= S_ROW_RUN;
                    end
                    S_ROW_RUN: begin
                        if (patch_start_w) begin
                            patch_filling_r <= 1'b1;
                            patch_half_r <= fill_half_r;
                            half_pairs_r[fill_half_r] <= next_chunk_pairs_w;
                            next_pair_r <= next_pair_r + next_chunk_pairs_w;
                            fill_half_r <= !fill_half_r;
                        end
                        if (patch_done_w) begin
                            patch_filling_r <= 1'b0;
                            half_ready_r[patch_half_r] <= 1'b1;
                        end
                        if (conv_start_w) begin
                            compute_running_r <= 1'b1;
                            compute_half_r <= run_half_r;
                            half_ready_r[run_half_r] <= 1'b0;
                            half_busy_r[run_half_r] <= 1'b1;
                            run_half_r <= !run_half_r;
                        end
                        if (conv_done_w) begin
                            compute_running_r <= 1'b0;
                            half_busy_r[compute_half_r] <= 1'b0;
                        end
                        if (writer_done_w) begin
                            if (writer_error_w)
                                error_r <= 1'b1;
                            if (output_y_r == output_height_r - 16'd1) begin
                                done_r <= 1'b1;
                                state_r <= S_IDLE;
                            end else begin
                                output_y_r <= output_y_r + 16'd1;
                                output_plane0_r <= output_plane0_r +
                                    {17'd0, output_width_pairs_r, 5'd0};
                                output_plane1_r <= output_plane1_r +
                                    {17'd0, output_width_pairs_r, 5'd0};
                                source_base_r <= source_base_r +
                                    (stride2_r ? 17'sd2 : 17'sd1);
                                source_base_ddr_r <= source_base_ddr_r +
                                    (stride2_r ? (input_row_bytes_r << 1) :
                                                 input_row_bytes_r);
                                first_slot_r <= next_first_slot_w;
                                prep_ky_r <= 2'd0;
                                row_valid_r <= 3'd0;
                                state_r <= S_ROW_PREP;
                            end
                        end
                    end
                    default: state_r <= S_IDLE;
                endcase
            end
        end
    end
endmodule
