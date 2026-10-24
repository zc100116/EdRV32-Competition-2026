// ============================================================================
// File        : edrv32_yolo_v8n_exec.v
// Description : Shared YOLOv8n DDR operator execution unit.
// Notes       : One 512-MAC CONV group is shared by every network layer.
//               Residual add, 5x5 SPPF pool and 2x nearest upsample reuse
//               the same AXI master slot under exclusive ownership.
//               Commands are limited to the four operators used by YOLOv8n.
// ============================================================================

module edrv32_yolo_v8n_exec (
    input  wire         clk_i,
    input  wire         rst_n_i,

    input  wire         cmd_valid_i,
    output wire         cmd_ready_o,
    input  wire [1:0]   cmd_op_i,
    input  wire [31:0]  cmd_input_base_i,
    input  wire [31:0]  cmd_aux_base_i,
    input  wire [31:0]  cmd_output_base_i,
    input  wire [31:0]  cmd_input_plane_stride_i,
    input  wire [31:0]  cmd_output_plane_stride_i,
    input  wire [31:0]  cmd_weight_base_i,
    input  wire [31:0]  cmd_weight_block_stride_i,
    input  wire [10:0]  cmd_input_width_i,
    input  wire [15:0]  cmd_input_height_i,
    input  wire [9:0]   cmd_output_width_pairs_i,
    input  wire [15:0]  cmd_output_height_i,
    input  wire [5:0]   cmd_cin_blocks_i,
    input  wire [4:0]   cmd_output_blocks_i,
    input  wire [8:0]   cmd_cache_bank_stride_i,
    input  wire [9:0]   cmd_cache_row_stride_i,
    input  wire [9:0]   cmd_tile_pairs_i,
    input  wire         cmd_kernel3_i,
    input  wire         cmd_stride2_i,
    input  wire         cmd_last_c16_only_i,
    input  wire [15:0]  cmd_beat_count_i,
    input  wire [7:0]   cmd_residual_zero_point_i,
    input  wire         cmd_lut_enable_i,
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

    localparam [1:0] OP_CONV = 2'd0;
    localparam [1:0] OP_ADD  = 2'd1;
    localparam [1:0] OP_POOL = 2'd2;
    localparam [1:0] OP_UP   = 2'd3;
    localparam [1:0] S_IDLE = 2'd0;
    localparam [1:0] S_START = 2'd1;
    localparam [1:0] S_WAIT = 2'd2;

    reg [1:0] state_r;
    reg [1:0] op_r;
    reg done_r;
    reg error_r;
    reg [31:0] input_base_r, aux_base_r, output_base_r;
    reg [31:0] input_plane_stride_r, output_plane_stride_r;
    reg [31:0] weight_base_r, weight_block_stride_r;
    reg [10:0] input_width_r;
    reg [15:0] input_height_r;
    reg [9:0] output_width_pairs_r;
    reg [15:0] output_height_r;
    reg [5:0] cin_blocks_r;
    reg [4:0] output_blocks_r;
    reg [8:0] cache_bank_stride_r;
    reg [9:0] cache_row_stride_r, tile_pairs_r;
    reg kernel3_r, stride2_r, last_c16_only_r;
    reg [15:0] beat_count_r;
    reg [7:0] residual_zero_point_r;
    reg lut_enable_r;

    wire [3:0] start_ready_w, op_done_w, op_error_w;
    wire [3:0] arid_w [0:3];
    wire [31:0] araddr_w [0:3];
    wire [7:0] arlen_w [0:3];
    wire [2:0] arsize_w [0:3];
    wire [1:0] arburst_w [0:3];
    wire [3:0] arvalid_w, rready_w;
    wire [3:0] awid_w [0:3];
    wire [31:0] awaddr_w [0:3];
    wire [7:0] awlen_w [0:3];
    wire [2:0] awsize_w [0:3];
    wire [1:0] awburst_w [0:3];
    wire [3:0] awvalid_w, wlast_w, wvalid_w, bready_w;
    wire [255:0] wdata_w [0:3];
    wire [31:0] wstrb_w [0:3];
    wire [3:0] arready_w, rvalid_w, awready_w, wready_w, bvalid_w;
    genvar owner;
    generate
        for (owner = 0; owner < 4; owner = owner + 1) begin : g_owner
            assign arready_w[owner] = state_r != S_IDLE &&
                                       op_r == owner && m_arready_i;
            assign rvalid_w[owner] = state_r != S_IDLE &&
                                      op_r == owner && m_rvalid_i;
            assign awready_w[owner] = state_r != S_IDLE &&
                                       op_r == owner && m_awready_i;
            assign wready_w[owner] = state_r != S_IDLE &&
                                      op_r == owner && m_wready_i;
            assign bvalid_w[owner] = state_r != S_IDLE &&
                                      op_r == owner && m_bvalid_i;
        end
    endgenerate

    assign cmd_ready_o = state_r == S_IDLE;
    assign busy_o = state_r != S_IDLE;
    assign done_o = done_r;
    assign error_o = error_r;
    assign m_arid_o = arid_w[op_r];
    assign m_araddr_o = araddr_w[op_r];
    assign m_arlen_o = arlen_w[op_r];
    assign m_arsize_o = arsize_w[op_r];
    assign m_arburst_o = arburst_w[op_r];
    assign m_arvalid_o = state_r != S_IDLE && arvalid_w[op_r];
    assign m_rready_o = state_r != S_IDLE && rready_w[op_r];
    assign m_awid_o = awid_w[op_r];
    assign m_awaddr_o = awaddr_w[op_r];
    assign m_awlen_o = awlen_w[op_r];
    assign m_awsize_o = awsize_w[op_r];
    assign m_awburst_o = awburst_w[op_r];
    assign m_awvalid_o = state_r != S_IDLE && awvalid_w[op_r];
    assign m_wdata_o = wdata_w[op_r];
    assign m_wstrb_o = wstrb_w[op_r];
    assign m_wlast_o = wlast_w[op_r];
    assign m_wvalid_o = state_r != S_IDLE && wvalid_w[op_r];
    assign m_bready_o = state_r != S_IDLE && bready_w[op_r];

    edrv32_yolo_conv_group u_conv (
        .clk_i(clk_i), .rst_n_i(rst_n_i),
        .start_i(state_r == S_START && op_r == OP_CONV),
        .start_ready_o(start_ready_w[0]),
        .feature_base_i(input_base_r),
        .feature_plane_stride_i(input_plane_stride_r),
        .weight_base_i(weight_base_r),
        .weight_block_stride_i(weight_block_stride_r),
        .output_base_i(output_base_r),
        .output_plane_stride_i(output_plane_stride_r),
        .output_blocks_i(output_blocks_r),
        .last_block_c16_only_i(last_c16_only_r),
        .input_width_i(input_width_r),
        .input_height_i(input_height_r),
        .output_width_pairs_i(output_width_pairs_r),
        .output_height_i(output_height_r),
        .cin_blocks_i(cin_blocks_r),
        .cache_bank_stride_i(cache_bank_stride_r),
        .cache_row_stride_i(cache_row_stride_r),
        .tile_pairs_i(tile_pairs_r),
        .kernel3_i(kernel3_r), .stride2_i(stride2_r),
        .busy_o(), .done_o(op_done_w[0]),
        .error_o(op_error_w[0]), .mac_beat_o(mac_beat_o),
        .cfg_block_o(cfg_block_o), .cfg_channel_o(cfg_channel_o),
        .cfg_phase_o(cfg_phase_o),
        .cfg_valid_i(op_r == OP_CONV && cfg_valid_i),
        .cfg_ready_o(cfg_ready_o),
        .cfg_bias_i(cfg_bias_i),
        .cfg_multiplier_i(cfg_multiplier_i),
        .cfg_shift_i(cfg_shift_i),
        .cfg_zero_point_i(cfg_zero_point_i),
        .lut_enable_i(lut_enable_r),
        .lut_cfg_valid_i(op_r == OP_CONV && cfg_lut_valid_i),
        .lut_cfg_ready_o(cfg_lut_ready_o),
        .lut_cfg_addr_o(cfg_lut_addr_o),
        .lut_cfg_data_i(cfg_lut_data_i),
        .m_arid_o(arid_w[0]), .m_araddr_o(araddr_w[0]),
        .m_arlen_o(arlen_w[0]), .m_arsize_o(arsize_w[0]),
        .m_arburst_o(arburst_w[0]), .m_arvalid_o(arvalid_w[0]),
        .m_arready_i(arready_w[0]),
        .m_rid_i(m_rid_i), .m_rdata_i(m_rdata_i),
        .m_rresp_i(m_rresp_i), .m_rlast_i(m_rlast_i),
        .m_rvalid_i(rvalid_w[0]), .m_rready_o(rready_w[0]),
        .m_awid_o(awid_w[0]), .m_awaddr_o(awaddr_w[0]),
        .m_awlen_o(awlen_w[0]), .m_awsize_o(awsize_w[0]),
        .m_awburst_o(awburst_w[0]), .m_awvalid_o(awvalid_w[0]),
        .m_awready_i(awready_w[0]),
        .m_wdata_o(wdata_w[0]), .m_wstrb_o(wstrb_w[0]),
        .m_wlast_o(wlast_w[0]), .m_wvalid_o(wvalid_w[0]),
        .m_wready_i(wready_w[0]),
        .m_bid_i(m_bid_i), .m_bresp_i(m_bresp_i),
        .m_bvalid_i(bvalid_w[0]), .m_bready_o(bready_w[0])
    );

    edrv32_yolo_c16_residual_dma u_add (
        .clk_i(clk_i), .rst_n_i(rst_n_i),
        .start_i(state_r == S_START && op_r == OP_ADD),
        .start_ready_o(start_ready_w[1]),
        .a_base_i(input_base_r), .b_base_i(aux_base_r),
        .output_base_i(output_base_r),
        .beat_count_i(beat_count_r),
        .zero_point_i(residual_zero_point_r),
        .busy_o(), .done_o(op_done_w[1]), .error_o(op_error_w[1]),
        .m_arid_o(arid_w[1]), .m_araddr_o(araddr_w[1]),
        .m_arlen_o(arlen_w[1]), .m_arsize_o(arsize_w[1]),
        .m_arburst_o(arburst_w[1]), .m_arvalid_o(arvalid_w[1]),
        .m_arready_i(arready_w[1]),
        .m_rid_i(m_rid_i), .m_rdata_i(m_rdata_i),
        .m_rresp_i(m_rresp_i), .m_rlast_i(m_rlast_i),
        .m_rvalid_i(rvalid_w[1]), .m_rready_o(rready_w[1]),
        .m_awid_o(awid_w[1]), .m_awaddr_o(awaddr_w[1]),
        .m_awlen_o(awlen_w[1]), .m_awsize_o(awsize_w[1]),
        .m_awburst_o(awburst_w[1]), .m_awvalid_o(awvalid_w[1]),
        .m_awready_i(awready_w[1]),
        .m_wdata_o(wdata_w[1]), .m_wstrb_o(wstrb_w[1]),
        .m_wlast_o(wlast_w[1]), .m_wvalid_o(wvalid_w[1]),
        .m_wready_i(wready_w[1]),
        .m_bid_i(m_bid_i), .m_bresp_i(m_bresp_i),
        .m_bvalid_i(bvalid_w[1]), .m_bready_o(bready_w[1])
    );

    edrv32_yolo_maxpool5_dma u_pool (
        .clk_i(clk_i), .rst_n_i(rst_n_i),
        .start_i(state_r == S_START && op_r == OP_POOL),
        .start_ready_o(start_ready_w[2]),
        .input_base_i(input_base_r),
        .input_plane_stride_i(input_plane_stride_r),
        .output_base_i(output_base_r),
        .output_plane_stride_i(output_plane_stride_r),
        .plane_count_i(cin_blocks_r[3:0]),
        .width_pairs_i(input_width_r[4:1]),
        .height_i(input_height_r[3:0]),
        .busy_o(), .done_o(op_done_w[2]), .error_o(op_error_w[2]),
        .m_arid_o(arid_w[2]), .m_araddr_o(araddr_w[2]),
        .m_arlen_o(arlen_w[2]), .m_arsize_o(arsize_w[2]),
        .m_arburst_o(arburst_w[2]), .m_arvalid_o(arvalid_w[2]),
        .m_arready_i(arready_w[2]),
        .m_rid_i(m_rid_i), .m_rdata_i(m_rdata_i),
        .m_rresp_i(m_rresp_i), .m_rlast_i(m_rlast_i),
        .m_rvalid_i(rvalid_w[2]), .m_rready_o(rready_w[2]),
        .m_awid_o(awid_w[2]), .m_awaddr_o(awaddr_w[2]),
        .m_awlen_o(awlen_w[2]), .m_awsize_o(awsize_w[2]),
        .m_awburst_o(awburst_w[2]), .m_awvalid_o(awvalid_w[2]),
        .m_awready_i(awready_w[2]),
        .m_wdata_o(wdata_w[2]), .m_wstrb_o(wstrb_w[2]),
        .m_wlast_o(wlast_w[2]), .m_wvalid_o(wvalid_w[2]),
        .m_wready_i(wready_w[2]),
        .m_bid_i(m_bid_i), .m_bresp_i(m_bresp_i),
        .m_bvalid_i(bvalid_w[2]), .m_bready_o(bready_w[2])
    );

    edrv32_yolo_upsample2x_dma u_up (
        .clk_i(clk_i), .rst_n_i(rst_n_i),
        .start_i(state_r == S_START && op_r == OP_UP),
        .start_ready_o(start_ready_w[3]),
        .input_base_i(input_base_r),
        .input_plane_stride_i(input_plane_stride_r),
        .output_base_i(output_base_r),
        .output_plane_stride_i(output_plane_stride_r),
        .plane_count_i(cin_blocks_r[4:0]),
        .input_width_pairs_i(input_width_r[5:1]),
        .input_height_i(input_height_r[7:0]),
        .busy_o(), .done_o(op_done_w[3]), .error_o(op_error_w[3]),
        .m_arid_o(arid_w[3]), .m_araddr_o(araddr_w[3]),
        .m_arlen_o(arlen_w[3]), .m_arsize_o(arsize_w[3]),
        .m_arburst_o(arburst_w[3]), .m_arvalid_o(arvalid_w[3]),
        .m_arready_i(arready_w[3]),
        .m_rid_i(m_rid_i), .m_rdata_i(m_rdata_i),
        .m_rresp_i(m_rresp_i), .m_rlast_i(m_rlast_i),
        .m_rvalid_i(rvalid_w[3]), .m_rready_o(rready_w[3]),
        .m_awid_o(awid_w[3]), .m_awaddr_o(awaddr_w[3]),
        .m_awlen_o(awlen_w[3]), .m_awsize_o(awsize_w[3]),
        .m_awburst_o(awburst_w[3]), .m_awvalid_o(awvalid_w[3]),
        .m_awready_i(awready_w[3]),
        .m_wdata_o(wdata_w[3]), .m_wstrb_o(wstrb_w[3]),
        .m_wlast_o(wlast_w[3]), .m_wvalid_o(wvalid_w[3]),
        .m_wready_i(wready_w[3]),
        .m_bid_i(m_bid_i), .m_bresp_i(m_bresp_i),
        .m_bvalid_i(bvalid_w[3]), .m_bready_o(bready_w[3])
    );

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            state_r <= S_IDLE;
            op_r <= OP_CONV;
            done_r <= 1'b0;
            error_r <= 1'b0;
        end else begin
            done_r <= 1'b0;
            case (state_r)
                S_IDLE: if (cmd_valid_i && cmd_ready_o) begin
                    op_r <= cmd_op_i;
                    input_base_r <= cmd_input_base_i;
                    aux_base_r <= cmd_aux_base_i;
                    output_base_r <= cmd_output_base_i;
                    input_plane_stride_r <= cmd_input_plane_stride_i;
                    output_plane_stride_r <= cmd_output_plane_stride_i;
                    weight_base_r <= cmd_weight_base_i;
                    weight_block_stride_r <= cmd_weight_block_stride_i;
                    input_width_r <= cmd_input_width_i;
                    input_height_r <= cmd_input_height_i;
                    output_width_pairs_r <= cmd_output_width_pairs_i;
                    output_height_r <= cmd_output_height_i;
                    cin_blocks_r <= cmd_cin_blocks_i;
                    output_blocks_r <= cmd_output_blocks_i;
                    cache_bank_stride_r <= cmd_cache_bank_stride_i;
                    cache_row_stride_r <= cmd_cache_row_stride_i;
                    tile_pairs_r <= cmd_tile_pairs_i;
                    kernel3_r <= cmd_kernel3_i;
                    stride2_r <= cmd_stride2_i;
                    last_c16_only_r <= cmd_last_c16_only_i;
                    beat_count_r <= cmd_beat_count_i;
                    residual_zero_point_r <= cmd_residual_zero_point_i;
                    lut_enable_r <= cmd_lut_enable_i;
                    error_r <= 1'b0;
                    state_r <= S_START;
                end
                S_START: if (start_ready_w[op_r])
                    state_r <= S_WAIT;
                S_WAIT: if (op_done_w[op_r]) begin
                    error_r <= op_error_w[op_r];
                    done_r <= 1'b1;
                    state_r <= S_IDLE;
                end
                default: state_r <= S_IDLE;
            endcase
        end
    end
endmodule
