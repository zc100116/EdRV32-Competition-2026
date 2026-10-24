// ============================================================================
// File        : edrv32_yolo_c2f.v
// Description : YOLOv8n C2f schedule with one or two bottlenecks.
// Notes       : One CONV engine and one residual DMA are reused. Hidden
//               channels are C16/C32/C64/C128; concat occupies consecutive
//               C16 planes in the workspace without a DDR copy.
// ============================================================================

module edrv32_yolo_c2f (
    input  wire         clk_i,
    input  wire         rst_n_i,

    input  wire         start_i,
    output wire         start_ready_o,
    input  wire [31:0]  input_base_i,
    input  wire [31:0]  workspace_base_i,
    input  wire [31:0]  temp_base_i,
    input  wire [31:0]  output_base_i,
    input  wire [31:0]  plane_stride_i,
    input  wire [15:0]  plane_beats_i,
    input  wire [31:0]  weight_split_i,
    input  wire [31:0]  weight_bottleneck0_i,
    input  wire [31:0]  weight_bottleneck1_i,
    input  wire [31:0]  weight_bottleneck2_i,
    input  wire [31:0]  weight_bottleneck3_i,
    input  wire [31:0]  weight_fuse_i,
    input  wire [10:0]  width_i,
    input  wire [15:0]  height_i,
    input  wire [9:0]   tile_pairs_i,
    input  wire [5:0]   input_blocks_i,
    input  wire [1:0]   hidden_blocks_log2_i,
    input  wire [4:0]   output_blocks_i,
    input  wire [9:0]   input_cache_row_stride_i,
    input  wire         two_bottlenecks_i,
    input  wire         shortcut_i,
    input  wire [7:0]   residual_zero_point_i,
    output wire         busy_o,
    output wire         done_o,
    output wire         error_o,
    output wire         mac_beat_o,

    output wire [2:0]   cfg_op_o,
    output wire [4:0]   cfg_block_o,
    output wire [4:0]   cfg_channel_o,
    input  wire         cfg_valid_i,
    output wire         cfg_ready_o,
    input  wire [31:0]  cfg_bias_i,
    input  wire [15:0]  cfg_multiplier_i,
    input  wire [5:0]   cfg_shift_i,
    input  wire [7:0]   cfg_zero_point_i,
    input  wire         cfg_lut_enable_i,
    input  wire         cfg_lut_valid_i,
    output wire         cfg_lut_ready_o,
    output wire [7:0]   cfg_lut_addr_o,
    input  wire [7:0]   cfg_lut_data_i,

    output wire [3:0]   m_arid_o,
    output wire [31:0]  m_araddr_o,
    output wire [7:0]   m_arlen_o,
    output wire [2:0]   m_arsize_o,
    output wire [1:0]   m_arburst_o,
    output wire         m_arvalid_o,
    input  wire         m_arready_i,
    input  wire [3:0]   m_rid_i,
    input  wire [255:0] m_rdata_i,
    input  wire [1:0]   m_rresp_i,
    input  wire         m_rlast_i,
    input  wire         m_rvalid_i,
    output wire         m_rready_o,

    output wire [3:0]   m_awid_o,
    output wire [31:0]  m_awaddr_o,
    output wire [7:0]   m_awlen_o,
    output wire [2:0]   m_awsize_o,
    output wire [1:0]   m_awburst_o,
    output wire         m_awvalid_o,
    input  wire         m_awready_i,
    output wire [255:0] m_wdata_o,
    output wire [31:0]  m_wstrb_o,
    output wire         m_wlast_o,
    output wire         m_wvalid_o,
    input  wire         m_wready_i,
    input  wire [3:0]   m_bid_i,
    input  wire [1:0]   m_bresp_i,
    input  wire         m_bvalid_i,
    output wire         m_bready_o
);

    localparam [3:0] S_IDLE       = 4'd0;
    localparam [3:0] S_SPLIT_START= 4'd1;
    localparam [3:0] S_SPLIT_WAIT = 4'd2;
    localparam [3:0] S_B0_START   = 4'd3;
    localparam [3:0] S_B0_WAIT    = 4'd4;
    localparam [3:0] S_B1_START   = 4'd5;
    localparam [3:0] S_B1_WAIT    = 4'd6;
    localparam [3:0] S_ADD_START  = 4'd7;
    localparam [3:0] S_ADD_WAIT   = 4'd8;
    localparam [3:0] S_FUSE_START = 4'd9;
    localparam [3:0] S_FUSE_WAIT  = 4'd10;

    reg [3:0] state_r;
    reg done_r;
    reg error_r;
    reg [31:0] input_base_r;
    reg [31:0] workspace_base_r;
    reg [31:0] temp_base_r;
    reg [31:0] output_base_r;
    reg [31:0] plane_stride_r;
    reg [15:0] plane_beats_r;
    reg [31:0] weight_split_r;
    reg [31:0] weight_bottleneck0_r;
    reg [31:0] weight_bottleneck1_r;
    reg [31:0] weight_bottleneck2_r;
    reg [31:0] weight_bottleneck3_r;
    reg [31:0] weight_fuse_r;
    reg [10:0] width_r;
    reg [15:0] height_r;
    reg [9:0] tile_pairs_r;
    reg [5:0] input_blocks_r;
    reg [1:0] hidden_blocks_log2_r;
    reg [4:0] output_blocks_r;
    reg [9:0] input_cache_row_stride_r;
    reg two_bottlenecks_r;
    reg shortcut_r;
    reg bottleneck_index_r;
    reg [7:0] residual_zero_point_r;

    wire split_op_w = state_r == S_SPLIT_START ||
                      state_r == S_SPLIT_WAIT;
    wire bottleneck0_op_w = state_r == S_B0_START ||
                            state_r == S_B0_WAIT;
    wire bottleneck1_op_w = state_r == S_B1_START ||
                            state_r == S_B1_WAIT;
    wire fuse_op_w = state_r == S_FUSE_START ||
                     state_r == S_FUSE_WAIT;
    wire conv_owner_w = split_op_w || bottleneck0_op_w ||
                        bottleneck1_op_w || fuse_op_w;
    wire add_owner_w = state_r == S_ADD_START ||
                       state_r == S_ADD_WAIT;
    wire [4:0] hidden_blocks_w = 5'd1 << hidden_blocks_log2_r;
    wire [31:0] group_stride_w = plane_stride_r <<
                                 hidden_blocks_log2_r;
    wire [31:0] workspace_group1_w = workspace_base_r +
                                      group_stride_w;
    wire [31:0] workspace_group2_w = workspace_group1_w +
                                      group_stride_w;
    wire [31:0] workspace_group3_w = workspace_group2_w +
                                      group_stride_w;
    wire [8:0] bank_stride_w = width_r[10:2];
    wire [9:0] hidden_row_stride_w = {1'b0, bank_stride_w} <<
                                      hidden_blocks_log2_r;
    wire [9:0] fuse_row_stride_w = two_bottlenecks_r ?
                                    (hidden_row_stride_w << 2) :
                                    (hidden_row_stride_w << 1) +
                                     hidden_row_stride_w;
    wire [5:0] fuse_cin_blocks_w = two_bottlenecks_r ?
                                     {1'b0, hidden_blocks_w} << 2 :
                                     ({1'b0, hidden_blocks_w} << 1) +
                                      {1'b0, hidden_blocks_w};
    wire [15:0] residual_beats_w = plane_beats_r <<
                                    hidden_blocks_log2_r;

    reg [31:0] conv_feature_base_w;
    reg [31:0] conv_weight_base_w;
    reg [31:0] conv_output_base_w;
    reg [5:0] conv_cin_blocks_w;
    reg [4:0] conv_output_blocks_w;
    reg [9:0] conv_cache_row_stride_w;
    reg conv_kernel3_w;
    reg conv_c16_only_w;
    wire [31:0] conv_weight_block_stride_w = conv_kernel3_w ?
        ({26'd0, conv_cin_blocks_w} << 12) +
        ({26'd0, conv_cin_blocks_w} << 9) :
        ({26'd0, conv_cin_blocks_w} << 9);
    always @(*) begin
        conv_feature_base_w = input_base_r;
        conv_weight_base_w = weight_split_r;
        conv_output_base_w = workspace_base_r;
        conv_cin_blocks_w = input_blocks_r;
        conv_output_blocks_w = hidden_blocks_w;
        conv_cache_row_stride_w = input_cache_row_stride_r;
        conv_kernel3_w = 1'b0;
        conv_c16_only_w = 1'b0;
        if (bottleneck0_op_w) begin
            conv_feature_base_w = bottleneck_index_r ?
                                  workspace_group2_w : workspace_group1_w;
            conv_weight_base_w = bottleneck_index_r ?
                                 weight_bottleneck2_r : weight_bottleneck0_r;
            conv_output_base_w = temp_base_r;
            conv_cin_blocks_w = {1'b0, hidden_blocks_w};
            conv_output_blocks_w = hidden_blocks_w[4:1] +
                                    {4'd0, hidden_blocks_w[0]};
            conv_cache_row_stride_w = hidden_row_stride_w;
            conv_kernel3_w = 1'b1;
            conv_c16_only_w = hidden_blocks_w == 5'd1;
        end else if (bottleneck1_op_w) begin
            conv_feature_base_w = temp_base_r;
            conv_weight_base_w = bottleneck_index_r ?
                                 weight_bottleneck3_r : weight_bottleneck1_r;
            conv_output_base_w = bottleneck_index_r ?
                                  workspace_group3_w : workspace_group2_w;
            conv_cin_blocks_w = {1'b0, hidden_blocks_w};
            conv_output_blocks_w = hidden_blocks_w[4:1] +
                                    {4'd0, hidden_blocks_w[0]};
            conv_cache_row_stride_w = hidden_row_stride_w;
            conv_kernel3_w = 1'b1;
            conv_c16_only_w = hidden_blocks_w == 5'd1;
        end else if (fuse_op_w) begin
            conv_feature_base_w = workspace_base_r;
            conv_weight_base_w = weight_fuse_r;
            conv_output_base_w = output_base_r;
            conv_cin_blocks_w = fuse_cin_blocks_w;
            conv_output_blocks_w = output_blocks_r;
            conv_cache_row_stride_w = fuse_row_stride_w;
        end
    end

    wire conv_start_ready_w, conv_done_w, conv_error_w;
    wire [4:0] conv_cfg_block_w, conv_cfg_channel_w;
    wire conv_cfg_ready_w;
    wire conv_lut_cfg_ready_w;
    wire add_start_ready_w, add_done_w, add_error_w;
    wire [3:0] conv_arid_w, conv_awid_w, add_arid_w, add_awid_w;
    wire [31:0] conv_araddr_w, conv_awaddr_w;
    wire [31:0] add_araddr_w, add_awaddr_w;
    wire [7:0] conv_arlen_w, conv_awlen_w;
    wire [7:0] add_arlen_w, add_awlen_w;
    wire [2:0] conv_arsize_w, conv_awsize_w;
    wire [2:0] add_arsize_w, add_awsize_w;
    wire [1:0] conv_arburst_w, conv_awburst_w;
    wire [1:0] add_arburst_w, add_awburst_w;
    wire conv_arvalid_w, conv_arready_w, conv_rready_w;
    wire conv_awvalid_w, conv_awready_w, conv_wvalid_w;
    wire conv_wready_w, conv_wlast_w, conv_bready_w;
    wire add_arvalid_w, add_arready_w, add_rready_w;
    wire add_awvalid_w, add_awready_w, add_wvalid_w;
    wire add_wready_w, add_wlast_w, add_bready_w;
    wire [255:0] conv_wdata_w, add_wdata_w;
    wire [31:0] conv_wstrb_w, add_wstrb_w;

    assign start_ready_o = state_r == S_IDLE && width_i != 11'd0 &&
                           width_i[1:0] == 2'd0 &&
                           height_i != 16'd0 && plane_beats_i != 16'd0 &&
                           input_blocks_i != 6'd0 &&
                           output_blocks_i != 5'd0 &&
                           input_cache_row_stride_i != 10'd0 &&
                           tile_pairs_i != 10'd0;
    assign busy_o = state_r != S_IDLE;
    assign done_o = done_r;
    assign error_o = error_r;
    assign cfg_op_o = split_op_w ? 3'd0 :
                      bottleneck0_op_w ? (bottleneck_index_r ? 3'd3 : 3'd1) :
                      bottleneck1_op_w ? (bottleneck_index_r ? 3'd4 : 3'd2) :
                      3'd5;
    assign cfg_block_o = conv_cfg_block_w;
    assign cfg_channel_o = conv_cfg_channel_w;
    assign cfg_ready_o = conv_owner_w && conv_cfg_ready_w;
    assign cfg_lut_ready_o = conv_owner_w && conv_lut_cfg_ready_w;

    edrv32_yolo_conv_group u_conv_group (
        .clk_i(clk_i), .rst_n_i(rst_n_i),
        .start_i(state_r == S_SPLIT_START ||
                 state_r == S_B0_START ||
                 state_r == S_B1_START ||
                 state_r == S_FUSE_START),
        .start_ready_o(conv_start_ready_w),
        .feature_base_i(conv_feature_base_w),
        .feature_plane_stride_i(plane_stride_r),
        .weight_base_i(conv_weight_base_w),
        .weight_block_stride_i(conv_weight_block_stride_w),
        .output_base_i(conv_output_base_w),
        .output_plane_stride_i(plane_stride_r),
        .output_blocks_i(conv_output_blocks_w),
        .last_block_c16_only_i(conv_c16_only_w),
        .input_width_i(width_r), .input_height_i(height_r),
        .output_width_pairs_i(width_r[10:1]),
        .output_height_i(height_r),
        .cin_blocks_i(conv_cin_blocks_w),
        .cache_bank_stride_i(bank_stride_w),
        .cache_row_stride_i(conv_cache_row_stride_w),
        .tile_pairs_i(tile_pairs_r),
        .kernel3_i(conv_kernel3_w), .stride2_i(1'b0),
        .busy_o(), .done_o(conv_done_w),
        .error_o(conv_error_w), .mac_beat_o(mac_beat_o),
        .cfg_block_o(conv_cfg_block_w),
        .cfg_channel_o(conv_cfg_channel_w),
        .cfg_valid_i(conv_owner_w && cfg_valid_i),
        .cfg_ready_o(conv_cfg_ready_w),
        .cfg_bias_i(cfg_bias_i),
        .cfg_multiplier_i(cfg_multiplier_i),
        .cfg_shift_i(cfg_shift_i),
        .cfg_zero_point_i(cfg_zero_point_i),
        .lut_enable_i(cfg_lut_enable_i),
        .lut_cfg_valid_i(conv_owner_w && cfg_lut_valid_i),
        .lut_cfg_ready_o(conv_lut_cfg_ready_w),
        .lut_cfg_addr_o(cfg_lut_addr_o),
        .lut_cfg_data_i(cfg_lut_data_i),
        .m_arid_o(conv_arid_w), .m_araddr_o(conv_araddr_w),
        .m_arlen_o(conv_arlen_w), .m_arsize_o(conv_arsize_w),
        .m_arburst_o(conv_arburst_w),
        .m_arvalid_o(conv_arvalid_w),
        .m_arready_i(conv_arready_w),
        .m_rid_i(m_rid_i), .m_rdata_i(m_rdata_i),
        .m_rresp_i(m_rresp_i), .m_rlast_i(m_rlast_i),
        .m_rvalid_i(conv_owner_w && m_rvalid_i),
        .m_rready_o(conv_rready_w),
        .m_awid_o(conv_awid_w), .m_awaddr_o(conv_awaddr_w),
        .m_awlen_o(conv_awlen_w), .m_awsize_o(conv_awsize_w),
        .m_awburst_o(conv_awburst_w),
        .m_awvalid_o(conv_awvalid_w),
        .m_awready_i(conv_awready_w),
        .m_wdata_o(conv_wdata_w), .m_wstrb_o(conv_wstrb_w),
        .m_wlast_o(conv_wlast_w), .m_wvalid_o(conv_wvalid_w),
        .m_wready_i(conv_wready_w),
        .m_bid_i(m_bid_i), .m_bresp_i(m_bresp_i),
        .m_bvalid_i(conv_owner_w && m_bvalid_i),
        .m_bready_o(conv_bready_w)
    );

    edrv32_yolo_c16_residual_dma u_residual (
        .clk_i(clk_i), .rst_n_i(rst_n_i),
        .start_i(state_r == S_ADD_START),
        .start_ready_o(add_start_ready_w),
        .a_base_i(bottleneck_index_r ? workspace_group2_w :
                  workspace_group1_w),
        .b_base_i(bottleneck_index_r ? workspace_group3_w :
                  workspace_group2_w),
        .output_base_i(bottleneck_index_r ? workspace_group3_w :
                       workspace_group2_w),
        .beat_count_i(residual_beats_w),
        .zero_point_i(residual_zero_point_r),
        .busy_o(), .done_o(add_done_w), .error_o(add_error_w),
        .m_arid_o(add_arid_w), .m_araddr_o(add_araddr_w),
        .m_arlen_o(add_arlen_w), .m_arsize_o(add_arsize_w),
        .m_arburst_o(add_arburst_w),
        .m_arvalid_o(add_arvalid_w),
        .m_arready_i(add_arready_w),
        .m_rid_i(m_rid_i), .m_rdata_i(m_rdata_i),
        .m_rresp_i(m_rresp_i), .m_rlast_i(m_rlast_i),
        .m_rvalid_i(add_owner_w && m_rvalid_i),
        .m_rready_o(add_rready_w),
        .m_awid_o(add_awid_w), .m_awaddr_o(add_awaddr_w),
        .m_awlen_o(add_awlen_w), .m_awsize_o(add_awsize_w),
        .m_awburst_o(add_awburst_w),
        .m_awvalid_o(add_awvalid_w),
        .m_awready_i(add_awready_w),
        .m_wdata_o(add_wdata_w), .m_wstrb_o(add_wstrb_w),
        .m_wlast_o(add_wlast_w), .m_wvalid_o(add_wvalid_w),
        .m_wready_i(add_wready_w),
        .m_bid_i(m_bid_i), .m_bresp_i(m_bresp_i),
        .m_bvalid_i(add_owner_w && m_bvalid_i),
        .m_bready_o(add_bready_w)
    );

    assign conv_arready_w = conv_owner_w && m_arready_i;
    assign conv_awready_w = conv_owner_w && m_awready_i;
    assign conv_wready_w = conv_owner_w && m_wready_i;
    assign add_arready_w = add_owner_w && m_arready_i;
    assign add_awready_w = add_owner_w && m_awready_i;
    assign add_wready_w = add_owner_w && m_wready_i;

    assign m_arid_o = conv_owner_w ? conv_arid_w : add_arid_w;
    assign m_araddr_o = conv_owner_w ? conv_araddr_w : add_araddr_w;
    assign m_arlen_o = conv_owner_w ? conv_arlen_w : add_arlen_w;
    assign m_arsize_o = conv_owner_w ? conv_arsize_w : add_arsize_w;
    assign m_arburst_o = conv_owner_w ? conv_arburst_w : add_arburst_w;
    assign m_arvalid_o = conv_owner_w ? conv_arvalid_w :
                         add_owner_w && add_arvalid_w;
    assign m_rready_o = conv_owner_w ? conv_rready_w :
                        add_owner_w && add_rready_w;
    assign m_awid_o = conv_owner_w ? conv_awid_w : add_awid_w;
    assign m_awaddr_o = conv_owner_w ? conv_awaddr_w : add_awaddr_w;
    assign m_awlen_o = conv_owner_w ? conv_awlen_w : add_awlen_w;
    assign m_awsize_o = conv_owner_w ? conv_awsize_w : add_awsize_w;
    assign m_awburst_o = conv_owner_w ? conv_awburst_w : add_awburst_w;
    assign m_awvalid_o = conv_owner_w ? conv_awvalid_w :
                         add_owner_w && add_awvalid_w;
    assign m_wdata_o = conv_owner_w ? conv_wdata_w : add_wdata_w;
    assign m_wstrb_o = conv_owner_w ? conv_wstrb_w : add_wstrb_w;
    assign m_wlast_o = conv_owner_w ? conv_wlast_w : add_wlast_w;
    assign m_wvalid_o = conv_owner_w ? conv_wvalid_w :
                        add_owner_w && add_wvalid_w;
    assign m_bready_o = conv_owner_w ? conv_bready_w :
                        add_owner_w && add_bready_w;

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            state_r <= S_IDLE;
            done_r <= 1'b0;
            error_r <= 1'b0;
            bottleneck_index_r <= 1'b0;
        end else begin
            done_r <= 1'b0;
            case (state_r)
                S_IDLE: if (start_i && start_ready_o) begin
                    input_base_r <= input_base_i;
                    workspace_base_r <= workspace_base_i;
                    temp_base_r <= temp_base_i;
                    output_base_r <= output_base_i;
                    plane_stride_r <= plane_stride_i;
                    plane_beats_r <= plane_beats_i;
                    weight_split_r <= weight_split_i;
                    weight_bottleneck0_r <= weight_bottleneck0_i;
                    weight_bottleneck1_r <= weight_bottleneck1_i;
                    weight_bottleneck2_r <= weight_bottleneck2_i;
                    weight_bottleneck3_r <= weight_bottleneck3_i;
                    weight_fuse_r <= weight_fuse_i;
                    width_r <= width_i;
                    height_r <= height_i;
                    tile_pairs_r <= tile_pairs_i;
                    input_blocks_r <= input_blocks_i;
                    hidden_blocks_log2_r <= hidden_blocks_log2_i;
                    output_blocks_r <= output_blocks_i;
                    input_cache_row_stride_r <= input_cache_row_stride_i;
                    two_bottlenecks_r <= two_bottlenecks_i;
                    shortcut_r <= shortcut_i;
                    bottleneck_index_r <= 1'b0;
                    residual_zero_point_r <= residual_zero_point_i;
                    error_r <= 1'b0;
                    state_r <= S_SPLIT_START;
                end
                S_SPLIT_START: if (conv_start_ready_w)
                    state_r <= S_SPLIT_WAIT;
                S_SPLIT_WAIT: if (conv_done_w) begin
                    if (conv_error_w) error_r <= 1'b1;
                    state_r <= S_B0_START;
                end
                S_B0_START: if (conv_start_ready_w)
                    state_r <= S_B0_WAIT;
                S_B0_WAIT: if (conv_done_w) begin
                    if (conv_error_w) error_r <= 1'b1;
                    state_r <= S_B1_START;
                end
                S_B1_START: if (conv_start_ready_w)
                    state_r <= S_B1_WAIT;
                S_B1_WAIT: if (conv_done_w) begin
                    if (conv_error_w) error_r <= 1'b1;
                    if (shortcut_r)
                        state_r <= S_ADD_START;
                    else if (two_bottlenecks_r && !bottleneck_index_r) begin
                        bottleneck_index_r <= 1'b1;
                        state_r <= S_B0_START;
                    end else
                        state_r <= S_FUSE_START;
                end
                S_ADD_START: if (add_start_ready_w)
                    state_r <= S_ADD_WAIT;
                S_ADD_WAIT: if (add_done_w) begin
                    if (add_error_w) error_r <= 1'b1;
                    if (two_bottlenecks_r && !bottleneck_index_r) begin
                        bottleneck_index_r <= 1'b1;
                        state_r <= S_B0_START;
                    end else
                        state_r <= S_FUSE_START;
                end
                S_FUSE_START: if (conv_start_ready_w)
                    state_r <= S_FUSE_WAIT;
                S_FUSE_WAIT: if (conv_done_w) begin
                    if (conv_error_w) error_r <= 1'b1;
                    done_r <= 1'b1;
                    state_r <= S_IDLE;
                end
                default: state_r <= S_IDLE;
            endcase
        end
    end
endmodule
