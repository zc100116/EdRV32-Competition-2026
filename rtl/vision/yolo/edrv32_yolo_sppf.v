// ============================================================================
// File        : edrv32_yolo_sppf.v
// Description : Fixed YOLOv8n SPPF schedule on one CONV engine and pool DMA.
// Notes       : C256 -> 1x1 C128 -> three successive 5x5 maxpools ->
//               no-copy C512 concat -> 1x1 C256. The four C128 groups are
//               consecutive C16 planes in DDR workspace.
// ============================================================================

module edrv32_yolo_sppf (
    input  wire         clk_i,
    input  wire         rst_n_i,

    input  wire         start_i,
    output wire         start_ready_o,
    input  wire [31:0]  input_base_i,
    input  wire [31:0]  workspace_base_i,
    input  wire [31:0]  output_base_i,
    input  wire [31:0]  plane_stride_i,
    input  wire [31:0]  weight_cv1_i,
    input  wire [31:0]  weight_cv2_i,
    input  wire [10:0]  width_i,
    input  wire [15:0]  height_i,
    input  wire [9:0]   tile_pairs_i,
    output wire         busy_o,
    output wire         done_o,
    output wire         error_o,
    output wire         mac_beat_o,

    output wire         cfg_op_o,
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
    output wire [1:0]   m_awburst_o,
    output wire [2:0]   m_awsize_o,
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

    localparam [2:0] S_IDLE = 3'd0;
    localparam [2:0] S_CV1_START = 3'd1;
    localparam [2:0] S_CV1_WAIT = 3'd2;
    localparam [2:0] S_POOL_START = 3'd3;
    localparam [2:0] S_POOL_WAIT = 3'd4;
    localparam [2:0] S_CV2_START = 3'd5;
    localparam [2:0] S_CV2_WAIT = 3'd6;

    reg [2:0] state_r;
    reg done_r;
    reg error_r;
    reg [31:0] input_base_r;
    reg [31:0] workspace_base_r;
    reg [31:0] output_base_r;
    reg [31:0] plane_stride_r;
    reg [31:0] weight_cv1_r;
    reg [31:0] weight_cv2_r;
    reg [10:0] width_r;
    reg [15:0] height_r;
    reg [9:0] tile_pairs_r;
    reg [1:0] pool_pass_r;
    reg [31:0] pool_input_addr_r;

    wire cv1_owner_w = state_r == S_CV1_START ||
                       state_r == S_CV1_WAIT;
    wire cv2_owner_w = state_r == S_CV2_START ||
                       state_r == S_CV2_WAIT;
    wire conv_owner_w = cv1_owner_w || cv2_owner_w;
    wire pool_owner_w = state_r == S_POOL_START ||
                        state_r == S_POOL_WAIT;
    wire [31:0] group_stride_w = plane_stride_r << 3;
    wire [8:0] bank_stride_w = width_r[10:2];
    wire conv_start_ready_w, conv_done_w, conv_error_w;
    wire pool_start_ready_w, pool_done_w, pool_error_w;
    wire conv_cfg_ready_w, conv_lut_cfg_ready_w;
    wire [3:0] conv_arid_w, pool_arid_w;
    wire [31:0] conv_araddr_w, pool_araddr_w;
    wire [7:0] conv_arlen_w, pool_arlen_w;
    wire [2:0] conv_arsize_w, pool_arsize_w;
    wire [1:0] conv_arburst_w, pool_arburst_w;
    wire conv_arvalid_w, conv_arready_w, conv_rready_w;
    wire pool_arvalid_w, pool_arready_w, pool_rready_w;
    wire [3:0] conv_awid_w, pool_awid_w;
    wire [31:0] conv_awaddr_w, pool_awaddr_w;
    wire [7:0] conv_awlen_w, pool_awlen_w;
    wire [2:0] conv_awsize_w, pool_awsize_w;
    wire [1:0] conv_awburst_w, pool_awburst_w;
    wire conv_awvalid_w, conv_awready_w, conv_wvalid_w;
    wire conv_wready_w, conv_wlast_w, conv_bready_w;
    wire pool_awvalid_w, pool_awready_w, pool_wvalid_w;
    wire pool_wready_w, pool_wlast_w, pool_bready_w;
    wire [255:0] conv_wdata_w, pool_wdata_w;
    wire [31:0] conv_wstrb_w, pool_wstrb_w;

    assign start_ready_o = state_r == S_IDLE &&
        width_i != 11'd0 && width_i <= 11'd20 &&
        width_i[1:0] == 2'd0 &&
        height_i != 16'd0 && height_i <= 16'd12 &&
        tile_pairs_i != 10'd0;
    assign busy_o = state_r != S_IDLE;
    assign done_o = done_r;
    assign error_o = error_r;
    assign cfg_op_o = cv2_owner_w;
    assign cfg_ready_o = conv_owner_w && conv_cfg_ready_w;
    assign cfg_lut_ready_o = conv_owner_w && conv_lut_cfg_ready_w;

    edrv32_yolo_conv_group u_conv_group (
        .clk_i(clk_i), .rst_n_i(rst_n_i),
        .start_i(state_r == S_CV1_START || state_r == S_CV2_START),
        .start_ready_o(conv_start_ready_w),
        .feature_base_i(cv1_owner_w ? input_base_r :
                         workspace_base_r),
        .feature_plane_stride_i(plane_stride_r),
        .weight_base_i(cv1_owner_w ? weight_cv1_r : weight_cv2_r),
        .weight_block_stride_i(cv1_owner_w ? 32'd8192 : 32'd16384),
        .output_base_i(cv1_owner_w ? workspace_base_r : output_base_r),
        .output_plane_stride_i(plane_stride_r),
        .output_blocks_i(cv1_owner_w ? 5'd4 : 5'd8),
        .last_block_c16_only_i(1'b0),
        .input_width_i(width_r), .input_height_i(height_r),
        .output_width_pairs_i(width_r[10:1]),
        .output_height_i(height_r),
        .cin_blocks_i(cv1_owner_w ? 6'd16 : 6'd32),
        .cache_bank_stride_i(bank_stride_w),
        .cache_row_stride_i(cv1_owner_w ?
                            ({1'b0, bank_stride_w} << 4) :
                            ({1'b0, bank_stride_w} << 5)),
        .tile_pairs_i(tile_pairs_r),
        .kernel3_i(1'b0), .stride2_i(1'b0),
        .busy_o(), .done_o(conv_done_w),
        .error_o(conv_error_w), .mac_beat_o(mac_beat_o),
        .cfg_block_o(cfg_block_o),
        .cfg_channel_o(cfg_channel_o),
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
        .m_arburst_o(conv_arburst_w), .m_arvalid_o(conv_arvalid_w),
        .m_arready_i(conv_arready_w),
        .m_rid_i(m_rid_i), .m_rdata_i(m_rdata_i),
        .m_rresp_i(m_rresp_i), .m_rlast_i(m_rlast_i),
        .m_rvalid_i(conv_owner_w && m_rvalid_i),
        .m_rready_o(conv_rready_w),
        .m_awid_o(conv_awid_w), .m_awaddr_o(conv_awaddr_w),
        .m_awlen_o(conv_awlen_w), .m_awsize_o(conv_awsize_w),
        .m_awburst_o(conv_awburst_w), .m_awvalid_o(conv_awvalid_w),
        .m_awready_i(conv_awready_w),
        .m_wdata_o(conv_wdata_w), .m_wstrb_o(conv_wstrb_w),
        .m_wlast_o(conv_wlast_w), .m_wvalid_o(conv_wvalid_w),
        .m_wready_i(conv_wready_w),
        .m_bid_i(m_bid_i), .m_bresp_i(m_bresp_i),
        .m_bvalid_i(conv_owner_w && m_bvalid_i),
        .m_bready_o(conv_bready_w)
    );

    edrv32_yolo_maxpool5_dma u_pool (
        .clk_i(clk_i), .rst_n_i(rst_n_i),
        .start_i(state_r == S_POOL_START),
        .start_ready_o(pool_start_ready_w),
        .input_base_i(pool_input_addr_r),
        .input_plane_stride_i(plane_stride_r),
        .output_base_i(pool_input_addr_r + group_stride_w),
        .output_plane_stride_i(plane_stride_r),
        .plane_count_i(4'd8),
        .width_pairs_i(width_r[4:1]),
        .height_i(height_r[3:0]),
        .busy_o(), .done_o(pool_done_w), .error_o(pool_error_w),
        .m_arid_o(pool_arid_w), .m_araddr_o(pool_araddr_w),
        .m_arlen_o(pool_arlen_w), .m_arsize_o(pool_arsize_w),
        .m_arburst_o(pool_arburst_w), .m_arvalid_o(pool_arvalid_w),
        .m_arready_i(pool_arready_w),
        .m_rid_i(m_rid_i), .m_rdata_i(m_rdata_i),
        .m_rresp_i(m_rresp_i), .m_rlast_i(m_rlast_i),
        .m_rvalid_i(pool_owner_w && m_rvalid_i),
        .m_rready_o(pool_rready_w),
        .m_awid_o(pool_awid_w), .m_awaddr_o(pool_awaddr_w),
        .m_awlen_o(pool_awlen_w), .m_awsize_o(pool_awsize_w),
        .m_awburst_o(pool_awburst_w), .m_awvalid_o(pool_awvalid_w),
        .m_awready_i(pool_awready_w),
        .m_wdata_o(pool_wdata_w), .m_wstrb_o(pool_wstrb_w),
        .m_wlast_o(pool_wlast_w), .m_wvalid_o(pool_wvalid_w),
        .m_wready_i(pool_wready_w),
        .m_bid_i(m_bid_i), .m_bresp_i(m_bresp_i),
        .m_bvalid_i(pool_owner_w && m_bvalid_i),
        .m_bready_o(pool_bready_w)
    );

    assign conv_arready_w = conv_owner_w && m_arready_i;
    assign conv_awready_w = conv_owner_w && m_awready_i;
    assign conv_wready_w = conv_owner_w && m_wready_i;
    assign pool_arready_w = pool_owner_w && m_arready_i;
    assign pool_awready_w = pool_owner_w && m_awready_i;
    assign pool_wready_w = pool_owner_w && m_wready_i;

    assign m_arid_o = conv_owner_w ? conv_arid_w : pool_arid_w;
    assign m_araddr_o = conv_owner_w ? conv_araddr_w : pool_araddr_w;
    assign m_arlen_o = conv_owner_w ? conv_arlen_w : pool_arlen_w;
    assign m_arsize_o = conv_owner_w ? conv_arsize_w : pool_arsize_w;
    assign m_arburst_o = conv_owner_w ? conv_arburst_w : pool_arburst_w;
    assign m_arvalid_o = conv_owner_w ? conv_arvalid_w :
                         pool_owner_w && pool_arvalid_w;
    assign m_rready_o = conv_owner_w ? conv_rready_w :
                        pool_owner_w && pool_rready_w;
    assign m_awid_o = conv_owner_w ? conv_awid_w : pool_awid_w;
    assign m_awaddr_o = conv_owner_w ? conv_awaddr_w : pool_awaddr_w;
    assign m_awlen_o = conv_owner_w ? conv_awlen_w : pool_awlen_w;
    assign m_awsize_o = conv_owner_w ? conv_awsize_w : pool_awsize_w;
    assign m_awburst_o = conv_owner_w ? conv_awburst_w : pool_awburst_w;
    assign m_awvalid_o = conv_owner_w ? conv_awvalid_w :
                         pool_owner_w && pool_awvalid_w;
    assign m_wdata_o = conv_owner_w ? conv_wdata_w : pool_wdata_w;
    assign m_wstrb_o = conv_owner_w ? conv_wstrb_w : pool_wstrb_w;
    assign m_wlast_o = conv_owner_w ? conv_wlast_w : pool_wlast_w;
    assign m_wvalid_o = conv_owner_w ? conv_wvalid_w :
                        pool_owner_w && pool_wvalid_w;
    assign m_bready_o = conv_owner_w ? conv_bready_w :
                        pool_owner_w && pool_bready_w;

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            state_r <= S_IDLE;
            done_r <= 1'b0;
            error_r <= 1'b0;
            pool_pass_r <= 2'd0;
            pool_input_addr_r <= 32'd0;
        end else begin
            done_r <= 1'b0;
            case (state_r)
                S_IDLE: if (start_i && start_ready_o) begin
                    input_base_r <= input_base_i;
                    workspace_base_r <= workspace_base_i;
                    output_base_r <= output_base_i;
                    plane_stride_r <= plane_stride_i;
                    weight_cv1_r <= weight_cv1_i;
                    weight_cv2_r <= weight_cv2_i;
                    width_r <= width_i;
                    height_r <= height_i;
                    tile_pairs_r <= tile_pairs_i;
                    pool_pass_r <= 2'd0;
                    pool_input_addr_r <= workspace_base_i;
                    error_r <= 1'b0;
                    state_r <= S_CV1_START;
                end
                S_CV1_START: if (conv_start_ready_w)
                    state_r <= S_CV1_WAIT;
                S_CV1_WAIT: if (conv_done_w) begin
                    if (conv_error_w) error_r <= 1'b1;
                    state_r <= S_POOL_START;
                end
                S_POOL_START: if (pool_start_ready_w)
                    state_r <= S_POOL_WAIT;
                S_POOL_WAIT: if (pool_done_w) begin
                    if (pool_error_w) error_r <= 1'b1;
                    if (pool_pass_r == 2'd2)
                        state_r <= S_CV2_START;
                    else begin
                        pool_pass_r <= pool_pass_r + 2'd1;
                        pool_input_addr_r <= pool_input_addr_r +
                                             group_stride_w;
                        state_r <= S_POOL_START;
                    end
                end
                S_CV2_START: if (conv_start_ready_w)
                    state_r <= S_CV2_WAIT;
                S_CV2_WAIT: if (conv_done_w) begin
                    if (conv_error_w) error_r <= 1'b1;
                    done_r <= 1'b1;
                    state_r <= S_IDLE;
                end
                default: state_r <= S_IDLE;
            endcase
        end
    end
endmodule
