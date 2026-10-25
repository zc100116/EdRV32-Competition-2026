// ============================================================================
// File        : edrv32_yolo_conv_group.v
// Description : Run one CONV surface through successive C32 output blocks.
// Notes       : One physical CONV engine is reused. The caller supplies the
//               fixed-model quantization values for each requested channel.
//               Output blocks occupy consecutive pairs of C16 DDR planes.
// ============================================================================

module edrv32_yolo_conv_group (
    input  wire         clk_i,
    input  wire         rst_n_i,

    input  wire         start_i,
    output wire         start_ready_o,
    input  wire [31:0]  feature_base_i,
    input  wire [31:0]  feature_plane_stride_i,
    input  wire [31:0]  weight_base_i,
    input  wire [31:0]  weight_block_stride_i,
    input  wire [31:0]  output_base_i,
    input  wire [31:0]  output_plane_stride_i,
    input  wire [4:0]   output_blocks_i,
    input  wire         last_block_c16_only_i,
    input  wire [10:0]  input_width_i,
    input  wire [15:0]  input_height_i,
    input  wire [9:0]   output_width_pairs_i,
    input  wire [15:0]  output_height_i,
    input  wire [5:0]   cin_blocks_i,
    input  wire [8:0]   cache_bank_stride_i,
    input  wire [9:0]   cache_row_stride_i,
    input  wire [9:0]   tile_pairs_i,
    input  wire         kernel3_i,
    input  wire         stride2_i,
    output wire         busy_o,
    output wire         done_o,
    output wire         error_o,
    output wire         mac_beat_o,

    output wire [4:0]   cfg_block_o,
    output wire [4:0]   cfg_channel_o,
    output wire         cfg_phase_o,
    input  wire         cfg_valid_i,
    output wire         cfg_ready_o,
    input  wire [31:0]  cfg_bias_i,
    input  wire [15:0]  cfg_multiplier_i,
    input  wire [5:0]   cfg_shift_i,
    input  wire [7:0]   cfg_zero_point_i,
    input  wire         lut_enable_i,
    input  wire         lut_cfg_valid_i,
    output wire         lut_cfg_ready_o,
    output wire [7:0]   lut_cfg_addr_o,
    input  wire [7:0]   lut_cfg_data_i,

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

    localparam [2:0] S_IDLE  = 3'd0;
    localparam [2:0] S_CFG   = 3'd1;
    localparam [2:0] S_LUT   = 3'd2;
    localparam [2:0] S_START = 3'd3;
    localparam [2:0] S_WAIT  = 3'd4;

    reg [2:0] state_r;
    reg done_r;
    reg error_r;
    reg [4:0] block_r;
    reg [4:0] block_count_r;
    reg last_block_c16_only_r;
    reg [4:0] cfg_channel_r;
    reg [7:0] lut_addr_r;
    reg lut_enable_r;
    reg [31:0] feature_base_r;
    reg [31:0] feature_plane_stride_r;
    reg [31:0] weight_addr_r;
    reg [31:0] weight_block_stride_r;
    reg [31:0] plane0_addr_r;
    reg [31:0] plane1_addr_r;
    reg [31:0] two_plane_stride_r;
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

    wire layer_start_ready_w;
    wire layer_done_w;
    wire layer_error_w;
    wire layer_cfg_ready_w;
    wire layer_lut_cfg_ready_w;
    wire cfg_fire_w = cfg_valid_i && cfg_ready_o;
    wire lut_fire_w = lut_cfg_valid_i && lut_cfg_ready_o;

    assign start_ready_o = state_r == S_IDLE && output_blocks_i != 5'd0;
    assign busy_o = state_r != S_IDLE;
    assign done_o = done_r;
    assign error_o = error_r;
    assign cfg_block_o = block_r;
    assign cfg_channel_o = cfg_channel_r;
    assign cfg_phase_o = state_r == S_CFG;
    assign cfg_ready_o = state_r == S_CFG && layer_cfg_ready_w;
    assign lut_cfg_ready_o = state_r == S_LUT && layer_lut_cfg_ready_w;
    assign lut_cfg_addr_o = lut_addr_r;

    edrv32_yolo_conv_layer u_layer (
        .clk_i(clk_i), .rst_n_i(rst_n_i),
        .start_i(state_r == S_START),
        .start_ready_o(layer_start_ready_w),
        .feature_base_i(feature_base_r),
        .feature_plane_stride_i(feature_plane_stride_r),
        .weight_base_i(weight_addr_r),
        .output_plane0_base_i(plane0_addr_r),
        .output_plane1_base_i(plane1_addr_r),
        .output_plane1_enable_i(!last_block_c16_only_r ||
                                block_r + 5'd1 != block_count_r),
        .input_width_i(input_width_r),
        .input_height_i(input_height_r),
        .output_width_pairs_i(output_width_pairs_r),
        .output_height_i(output_height_r),
        .cin_blocks_i(cin_blocks_r),
        .cache_bank_stride_i(cache_bank_stride_r),
        .cache_row_stride_i(cache_row_stride_r),
        .tile_pairs_i(tile_pairs_r),
        .kernel3_i(kernel3_r), .stride2_i(stride2_r),
        .busy_o(), .done_o(layer_done_w),
        .error_o(layer_error_w), .mac_beat_o(mac_beat_o),
        .weight_phase_o(), .feature_phase_o(), .run_phase_o(),
        .quant_cfg_valid_i(state_r == S_CFG && cfg_valid_i),
        .quant_cfg_ready_o(layer_cfg_ready_w),
        .quant_cfg_channel_i(cfg_channel_r),
        .quant_cfg_bias_i(cfg_bias_i),
        .quant_cfg_multiplier_i(cfg_multiplier_i),
        .quant_cfg_shift_i(cfg_shift_i),
        .quant_cfg_zero_point_i(cfg_zero_point_i),
        .lut_enable_i(lut_enable_r),
        .lut_cfg_valid_i(state_r == S_LUT && lut_cfg_valid_i),
        .lut_cfg_ready_o(layer_lut_cfg_ready_w),
        .lut_cfg_addr_i(lut_addr_r),
        .lut_cfg_data_i(lut_cfg_data_i),
        .m_arid_o(m_arid_o), .m_araddr_o(m_araddr_o),
        .m_arlen_o(m_arlen_o), .m_arsize_o(m_arsize_o),
        .m_arburst_o(m_arburst_o), .m_arvalid_o(m_arvalid_o),
        .m_arready_i(m_arready_i), .m_rid_i(m_rid_i),
        .m_rdata_i(m_rdata_i), .m_rresp_i(m_rresp_i),
        .m_rlast_i(m_rlast_i), .m_rvalid_i(m_rvalid_i),
        .m_rready_o(m_rready_o),
        .m_awid_o(m_awid_o), .m_awaddr_o(m_awaddr_o),
        .m_awlen_o(m_awlen_o), .m_awsize_o(m_awsize_o),
        .m_awburst_o(m_awburst_o), .m_awvalid_o(m_awvalid_o),
        .m_awready_i(m_awready_i), .m_wdata_o(m_wdata_o),
        .m_wstrb_o(m_wstrb_o), .m_wlast_o(m_wlast_o),
        .m_wvalid_o(m_wvalid_o), .m_wready_i(m_wready_i),
        .m_bid_i(m_bid_i), .m_bresp_i(m_bresp_i),
        .m_bvalid_i(m_bvalid_i), .m_bready_o(m_bready_o)
    );

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            state_r <= S_IDLE;
            done_r <= 1'b0;
            error_r <= 1'b0;
            block_r <= 5'd0;
            block_count_r <= 5'd0;
            last_block_c16_only_r <= 1'b0;
            cfg_channel_r <= 5'd0;
            lut_addr_r <= 8'd0;
            lut_enable_r <= 1'b0;
        end else begin
            done_r <= 1'b0;
            case (state_r)
                S_IDLE: if (start_i && start_ready_o) begin
                    feature_base_r <= feature_base_i;
                    feature_plane_stride_r <= feature_plane_stride_i;
                    weight_addr_r <= weight_base_i;
                    weight_block_stride_r <= weight_block_stride_i;
                    plane0_addr_r <= output_base_i;
                    plane1_addr_r <= output_base_i + output_plane_stride_i;
                    two_plane_stride_r <= output_plane_stride_i << 1;
                    input_width_r <= input_width_i;
                    input_height_r <= input_height_i;
                    output_width_pairs_r <= output_width_pairs_i;
                    output_height_r <= output_height_i;
                    cin_blocks_r <= cin_blocks_i;
                    cache_bank_stride_r <= cache_bank_stride_i;
                    cache_row_stride_r <= cache_row_stride_i;
                    tile_pairs_r <= tile_pairs_i;
                    kernel3_r <= kernel3_i;
                    stride2_r <= stride2_i;
                    block_r <= 5'd0;
                    block_count_r <= output_blocks_i;
                    last_block_c16_only_r <= last_block_c16_only_i;
                    cfg_channel_r <= 5'd0;
                    lut_addr_r <= 8'd0;
                    lut_enable_r <= lut_enable_i;
                    error_r <= 1'b0;
                    state_r <= S_CFG;
                end
                S_CFG: if (cfg_fire_w) begin
                    if (cfg_channel_r == 5'd31)
                        state_r <= lut_enable_r ? S_LUT : S_START;
                    else
                        cfg_channel_r <= cfg_channel_r + 5'd1;
                end
                S_LUT: if (lut_fire_w) begin
                    if (lut_addr_r == 8'd255)
                        state_r <= S_START;
                    else
                        lut_addr_r <= lut_addr_r + 8'd1;
                end
                S_START: if (layer_start_ready_w)
                    state_r <= S_WAIT;
                S_WAIT: if (layer_done_w) begin
                    if (layer_error_w)
                        error_r <= 1'b1;
                    if (block_r + 5'd1 == block_count_r) begin
                        done_r <= 1'b1;
                        state_r <= S_IDLE;
                    end else begin
                        block_r <= block_r + 5'd1;
                        cfg_channel_r <= 5'd0;
                        lut_addr_r <= 8'd0;
                        weight_addr_r <= weight_addr_r +
                                         weight_block_stride_r;
                        plane0_addr_r <= plane0_addr_r +
                                         two_plane_stride_r;
                        plane1_addr_r <= plane1_addr_r +
                                         two_plane_stride_r;
                        state_r <= S_CFG;
                    end
                end
                default: state_r <= S_IDLE;
            endcase
        end
    end
endmodule
