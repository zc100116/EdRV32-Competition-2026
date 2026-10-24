// ============================================================================
// File        : edrv32_yolo_v8n_core.v
// Description : Fixed YOLOv8n backbone/neck program on one shared executor.
// Notes       : Command addresses are generated from the pinned 640x384 plan.
//               A local DMA fetches one 512-byte quantization record for
//               each CONV output block through the same AXI read master.
// ============================================================================

module edrv32_yolo_v8n_core (
    input  wire         clk_i,
    input  wire         rst_n_i,

    input  wire         start_i,
    output wire         start_ready_o,
    output wire         busy_o,
    output wire         done_o,
    output wire         error_o,
    output wire [6:0]   step_o,
    output wire [4:0]   layer_id_o,
    output wire         mac_beat_o,

    output wire [31:0]  cfg_record_addr_o,
    output wire [4:0]   cfg_block_o,
    output wire [4:0]   cfg_channel_o,
    output wire         cfg_ready_o,
    output wire [31:0]  cfg_lut_addr_o,
    output wire         cfg_lut_ready_o,
    output wire         cfg_dma_error_o,

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

    wire program_cmd_valid_w;
    wire program_start_ready_w;
    wire program_busy_w;
    wire program_error_w;
    wire exec_cmd_ready_w;
    wire exec_done_w;
    wire exec_error_w;
    wire [1:0] cmd_op_w;
    wire [31:0] cmd_input_base_w, cmd_aux_base_w, cmd_output_base_w;
    wire [31:0] cmd_input_plane_stride_w, cmd_output_plane_stride_w;
    wire [31:0] cmd_weight_base_w, cmd_weight_block_stride_w;
    wire [10:0] cmd_input_width_w;
    wire [15:0] cmd_input_height_w, cmd_output_height_w;
    wire [9:0] cmd_output_width_pairs_w;
    wire [5:0] cmd_cin_blocks_w;
    wire [4:0] cmd_output_blocks_w;
    wire [8:0] cmd_cache_bank_stride_w;
    wire [9:0] cmd_cache_row_stride_w, cmd_tile_pairs_w;
    wire cmd_kernel3_w, cmd_stride2_w, cmd_last_c16_only_w;
    wire [15:0] cmd_beat_count_w;
    wire [7:0] cmd_residual_zero_point_w;
    wire cmd_lut_enable_w;
    wire [31:0] cfg_base_w;
    wire [7:0] cfg_lut_index_w;
    wire cfg_valid_w, cfg_lut_valid_w, cfg_dma_error_w;
    wire exec_cfg_phase_w;
    wire [31:0] cfg_bias_w;
    wire [15:0] cfg_multiplier_w;
    wire [5:0] cfg_shift_w;
    wire [7:0] cfg_zero_point_w, cfg_lut_data_w;
    wire cfg_axi_owner_w;
    wire [3:0] exec_arid_w, cfg_arid_w;
    wire [31:0] exec_araddr_w, cfg_araddr_w;
    wire [7:0] exec_arlen_w, cfg_arlen_w;
    wire [2:0] exec_arsize_w, cfg_arsize_w;
    wire [1:0] exec_arburst_w, cfg_arburst_w;
    wire exec_arvalid_w, exec_rready_w;
    wire cfg_arvalid_w, cfg_rready_w;
    wire [31:0] cfg_block_offset_w = {18'd0, cfg_block_o, 9'd0};
    wire [31:0] cfg_channel_offset_w = {24'd0, cfg_channel_o, 3'd0};

    assign cfg_record_addr_o = cfg_base_w + cfg_block_offset_w +
                               cfg_channel_offset_w;
    assign cfg_lut_addr_o = cfg_base_w + cfg_block_offset_w +
                            32'd256 + {24'd0, cfg_lut_index_w};
    assign start_ready_o = program_start_ready_w && !cfg_dma_error_w;
    assign busy_o = program_busy_w;
    assign error_o = program_error_w || cfg_dma_error_w;
    assign cfg_dma_error_o = cfg_dma_error_w;
    assign m_arid_o = cfg_axi_owner_w ? cfg_arid_w : exec_arid_w;
    assign m_araddr_o = cfg_axi_owner_w ? cfg_araddr_w : exec_araddr_w;
    assign m_arlen_o = cfg_axi_owner_w ? cfg_arlen_w : exec_arlen_w;
    assign m_arsize_o = cfg_axi_owner_w ? cfg_arsize_w : exec_arsize_w;
    assign m_arburst_o = cfg_axi_owner_w ? cfg_arburst_w : exec_arburst_w;
    assign m_arvalid_o = cfg_axi_owner_w ? cfg_arvalid_w : exec_arvalid_w;
    assign m_rready_o = cfg_axi_owner_w ? cfg_rready_w : exec_rready_w;

    edrv32_yolo_v8n_program u_program (
        .clk_i(clk_i), .rst_n_i(rst_n_i),
        .start_i(start_i && !cfg_dma_error_w),
        .start_ready_o(program_start_ready_w),
        .busy_o(program_busy_w), .done_o(done_o),
        .error_o(program_error_w),
        .step_o(step_o),
        .cmd_valid_o(program_cmd_valid_w),
        .cmd_ready_i(exec_cmd_ready_w),
        .cmd_done_i(exec_done_w), .cmd_error_i(exec_error_w),
        .abort_i(cfg_dma_error_w),
        .cmd_op_o(cmd_op_w),
        .cmd_input_base_o(cmd_input_base_w),
        .cmd_aux_base_o(cmd_aux_base_w),
        .cmd_output_base_o(cmd_output_base_w),
        .cmd_input_plane_stride_o(cmd_input_plane_stride_w),
        .cmd_output_plane_stride_o(cmd_output_plane_stride_w),
        .cmd_weight_base_o(cmd_weight_base_w),
        .cmd_weight_block_stride_o(cmd_weight_block_stride_w),
        .cmd_input_width_o(cmd_input_width_w),
        .cmd_input_height_o(cmd_input_height_w),
        .cmd_output_width_pairs_o(cmd_output_width_pairs_w),
        .cmd_output_height_o(cmd_output_height_w),
        .cmd_cin_blocks_o(cmd_cin_blocks_w),
        .cmd_output_blocks_o(cmd_output_blocks_w),
        .cmd_cache_bank_stride_o(cmd_cache_bank_stride_w),
        .cmd_cache_row_stride_o(cmd_cache_row_stride_w),
        .cmd_tile_pairs_o(cmd_tile_pairs_w),
        .cmd_kernel3_o(cmd_kernel3_w),
        .cmd_stride2_o(cmd_stride2_w),
        .cmd_last_c16_only_o(cmd_last_c16_only_w),
        .cmd_beat_count_o(cmd_beat_count_w),
        .cmd_residual_zero_point_o(cmd_residual_zero_point_w),
        .cmd_lut_enable_o(cmd_lut_enable_w),
        .cfg_base_o(cfg_base_w), .layer_id_o(layer_id_o)
    );

    edrv32_yolo_quant_cfg_dma u_cfg_dma (
        .clk_i(clk_i), .rst_n_i(rst_n_i),
        .enable_i(program_busy_w && cmd_op_w == 2'd0),
        .cfg_base_i(cfg_base_w),
        .cfg_block_i(cfg_block_o),
        .cfg_phase_i(exec_cfg_phase_w),
        .lut_enable_i(cmd_lut_enable_w),
        .cfg_channel_i(cfg_channel_o),
        .cfg_ready_i(cfg_ready_o),
        .cfg_valid_o(cfg_valid_w),
        .cfg_bias_o(cfg_bias_w),
        .cfg_multiplier_o(cfg_multiplier_w),
        .cfg_shift_o(cfg_shift_w),
        .cfg_zero_point_o(cfg_zero_point_w),
        .lut_index_i(cfg_lut_index_w),
        .lut_ready_i(cfg_lut_ready_o),
        .lut_valid_o(cfg_lut_valid_w),
        .lut_data_o(cfg_lut_data_w),
        .axi_owner_o(cfg_axi_owner_w),
        .error_o(cfg_dma_error_w),
        .m_arid_o(cfg_arid_w), .m_araddr_o(cfg_araddr_w),
        .m_arlen_o(cfg_arlen_w), .m_arsize_o(cfg_arsize_w),
        .m_arburst_o(cfg_arburst_w),
        .m_arvalid_o(cfg_arvalid_w),
        .m_arready_i(cfg_axi_owner_w && m_arready_i),
        .m_rid_i(m_rid_i), .m_rdata_i(m_rdata_i),
        .m_rresp_i(m_rresp_i), .m_rlast_i(m_rlast_i),
        .m_rvalid_i(cfg_axi_owner_w && m_rvalid_i),
        .m_rready_o(cfg_rready_w)
    );

    edrv32_yolo_v8n_exec u_exec (
        .clk_i(clk_i), .rst_n_i(rst_n_i && !cfg_dma_error_w),
        .cmd_valid_i(program_cmd_valid_w),
        .cmd_ready_o(exec_cmd_ready_w),
        .cmd_op_i(cmd_op_w),
        .cmd_input_base_i(cmd_input_base_w),
        .cmd_aux_base_i(cmd_aux_base_w),
        .cmd_output_base_i(cmd_output_base_w),
        .cmd_input_plane_stride_i(cmd_input_plane_stride_w),
        .cmd_output_plane_stride_i(cmd_output_plane_stride_w),
        .cmd_weight_base_i(cmd_weight_base_w),
        .cmd_weight_block_stride_i(cmd_weight_block_stride_w),
        .cmd_input_width_i(cmd_input_width_w),
        .cmd_input_height_i(cmd_input_height_w),
        .cmd_output_width_pairs_i(cmd_output_width_pairs_w),
        .cmd_output_height_i(cmd_output_height_w),
        .cmd_cin_blocks_i(cmd_cin_blocks_w),
        .cmd_output_blocks_i(cmd_output_blocks_w),
        .cmd_cache_bank_stride_i(cmd_cache_bank_stride_w),
        .cmd_cache_row_stride_i(cmd_cache_row_stride_w),
        .cmd_tile_pairs_i(cmd_tile_pairs_w),
        .cmd_kernel3_i(cmd_kernel3_w),
        .cmd_stride2_i(cmd_stride2_w),
        .cmd_last_c16_only_i(cmd_last_c16_only_w),
        .cmd_beat_count_i(cmd_beat_count_w),
        .cmd_residual_zero_point_i(cmd_residual_zero_point_w),
        .cmd_lut_enable_i(cmd_lut_enable_w),
        .busy_o(), .done_o(exec_done_w),
        .error_o(exec_error_w), .mac_beat_o(mac_beat_o),
        .cfg_block_o(cfg_block_o),
        .cfg_channel_o(cfg_channel_o),
        .cfg_phase_o(exec_cfg_phase_w),
        .cfg_valid_i(cfg_valid_w), .cfg_ready_o(cfg_ready_o),
        .cfg_bias_i(cfg_bias_w),
        .cfg_multiplier_i(cfg_multiplier_w),
        .cfg_shift_i(cfg_shift_w),
        .cfg_zero_point_i(cfg_zero_point_w),
        .cfg_lut_valid_i(cfg_lut_valid_w),
        .cfg_lut_ready_o(cfg_lut_ready_o),
        .cfg_lut_addr_o(cfg_lut_index_w),
        .cfg_lut_data_i(cfg_lut_data_w),
        .m_arid_o(exec_arid_w), .m_araddr_o(exec_araddr_w),
        .m_arlen_o(exec_arlen_w), .m_arsize_o(exec_arsize_w),
        .m_arburst_o(exec_arburst_w), .m_arvalid_o(exec_arvalid_w),
        .m_arready_i(!cfg_axi_owner_w && m_arready_i),
        .m_rid_i(m_rid_i), .m_rdata_i(m_rdata_i),
        .m_rresp_i(m_rresp_i), .m_rlast_i(m_rlast_i),
        .m_rvalid_i(!cfg_axi_owner_w && m_rvalid_i),
        .m_rready_o(exec_rready_w),
        .m_awid_o(m_awid_o), .m_awaddr_o(m_awaddr_o),
        .m_awlen_o(m_awlen_o), .m_awsize_o(m_awsize_o),
        .m_awburst_o(m_awburst_o), .m_awvalid_o(m_awvalid_o),
        .m_awready_i(m_awready_i),
        .m_wdata_o(m_wdata_o), .m_wstrb_o(m_wstrb_o),
        .m_wlast_o(m_wlast_o), .m_wvalid_o(m_wvalid_o),
        .m_wready_i(m_wready_i),
        .m_bid_i(m_bid_i), .m_bresp_i(m_bresp_i),
        .m_bvalid_i(m_bvalid_i), .m_bready_o(m_bready_o)
    );
endmodule
