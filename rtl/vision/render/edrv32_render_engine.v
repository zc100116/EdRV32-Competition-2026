// ============================================================================
// File        : edrv32_render_engine.v
// Description : DDR command-list executor for fill, round and composition.
// Notes       : One AXI master; each accepted command completes before the
//               next command is issued. Later draw operations share this port.
// ============================================================================

module edrv32_render_engine #(
    parameter ENABLE_CMD_COMPOSE = 1
) (
    input  wire         clk_i,
    input  wire         rst_n_i,

    input  wire         start_i,
    output wire         start_ready_o,
    input  wire [31:0]  list_base_i,
    input  wire [15:0]  list_count_i,
    output wire         busy_o,
    output wire         draw_active_o,
    output wire         compose_direct_active_o,
    output wire [31:0]  compose_direct_target_base_o,
    output wire         done_o,
    output wire         error_o,
    output wire [15:0]  completed_count_o,

    input  wire         compose_direct_start_i,
    output wire         compose_direct_ready_o,
    input  wire [31:0]  compose_direct_base_i,
    input  wire [31:0]  compose_direct_base_stride_i,
    input  wire [31:0]  compose_direct_front_i,
    input  wire [31:0]  compose_direct_front_stride_i,
    input  wire [31:0]  compose_direct_target_i,
    input  wire [31:0]  compose_direct_target_stride_i,
    input  wire [15:0]  compose_direct_width_i,
    input  wire [15:0]  compose_direct_height_i,
    output wire         compose_direct_done_o,
    output wire         compose_direct_error_o,

    output wire [3:0]   m_arid_o,
    output wire [31:0]  m_araddr_o,
    output wire [7:0]   m_arlen_o,
    output wire [2:0]   m_arsize_o,
    output wire [1:0]   m_arburst_o,
    output wire [3:0]   m_arqos_o,
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
    output wire [3:0]   m_awqos_o,
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

    localparam [3:0] ST_IDLE    = 4'd0;
    localparam [3:0] ST_FETCH   = 4'd1;
    localparam [3:0] ST_FILL    = 4'd2;
    localparam [3:0] ST_COMPOSE = 4'd3;
    localparam [3:0] ST_ROUND   = 4'd4;
    localparam [3:0] ST_A8      = 4'd5;
    localparam [3:0] ST_BITMAP  = 4'd6;
    localparam [3:0] ST_COPY    = 4'd7;
    localparam [3:0] ST_BLUR    = 4'd8;
    localparam [3:0] ST_MASK    = 4'd9;
    localparam [7:0] OP_FILL565 = 8'h01;
    localparam [7:0] OP_FILL8888 = 8'h02;
    localparam [7:0] OP_COMPOSE = 8'h03;
    localparam [7:0] OP_ROUND   = 8'h04;
    localparam [7:0] OP_A8      = 8'h05;
    localparam [7:0] OP_BITMAP  = 8'h06;
    localparam [7:0] OP_COPY    = 8'h07;
    localparam [7:0] OP_GRADIENT = 8'h08;
    localparam [7:0] OP_A8_BLUR = 8'h09;
    localparam [7:0] OP_BOX_SHADOW = 8'h0a;

    reg [3:0]  state_r;
    reg        done_r;
    reg        error_r;
    reg        direct_active_r;
    reg        direct_done_r;
    reg        direct_error_r;
    reg        fill_start_r;
    reg        compose_start_r;
    reg        round_start_r;
    reg        a8_start_r;
    reg        bitmap_start_r;
    reg        copy_start_r;
    reg        blur_start_r;
    reg        mask_start_r;
    reg        shadow_active_r;
    reg        cancel_fetch_r;
    reg        last_cmd_r;
    reg [15:0] command_count_r;
    reg [15:0] completed_count_r;
    reg [31:0] fill_base_r;
    reg [31:0] fill_stride_r;
    reg [15:0] fill_x_r;
    reg [15:0] fill_width_r;
    reg [15:0] fill_height_r;
    reg        fill_argb_r;
    reg [31:0] fill_color_r;
    reg        fill_gradient_r;
    reg        fill_vertical_r;
    reg [31:0] fill_step_a_r;
    reg [31:0] fill_step_r_r;
    reg [31:0] fill_step_g_r;
    reg [31:0] fill_step_b_r;
    reg [31:0] compose_base_r;
    reg [31:0] compose_base_stride_r;
    reg [31:0] compose_front_r;
    reg [31:0] compose_front_stride_r;
    reg [31:0] compose_target_r;
    reg [31:0] compose_target_stride_r;
    reg [15:0] compose_width_r;
    reg [15:0] compose_height_r;
    reg [31:0] round_base_r;
    reg [31:0] round_stride_r;
    reg [15:0] round_x_r;
    reg [15:0] round_width_r;
    reg [15:0] round_height_r;
    reg [9:0]  round_radius_r;
    reg [9:0]  round_border_r;
    reg [31:0] round_fill_color_r;
    reg [31:0] round_border_color_r;
    reg [31:0] a8_front_r;
    reg [31:0] a8_front_stride_r;
    reg [15:0] a8_x_r;
    reg [15:0] a8_width_r;
    reg [15:0] a8_height_r;
    reg [31:0] a8_mask_r;
    reg [31:0] a8_mask_stride_r;
    reg [31:0] a8_color_r;
    reg [31:0] bitmap_front_r;
    reg [31:0] bitmap_front_stride_r;
    reg [15:0] bitmap_x_r;
    reg [15:0] bitmap_width_r;
    reg [15:0] bitmap_height_r;
    reg [31:0] bitmap_source_r;
    reg [31:0] bitmap_source_stride_r;
    reg [15:0] bitmap_source_x_r;
    reg        bitmap_argb_r;
    reg        bitmap_premul_r;
    reg [7:0]  bitmap_opacity_r;
    reg        bitmap_flip_x_r;
    reg        bitmap_flip_y_r;
    reg        bitmap_color_key_enable_r;
    reg [31:0] bitmap_color_key_r;
    reg        bitmap_scale_enable_r;
    reg [31:0] bitmap_scale_step_x_r;
    reg [31:0] bitmap_scale_step_y_r;
    reg [31:0] copy_source_r;
    reg [31:0] copy_source_stride_r;
    reg [15:0] copy_source_x_r;
    reg [31:0] copy_target_r;
    reg [31:0] copy_target_stride_r;
    reg [15:0] copy_target_x_r;
    reg [15:0] copy_width_r;
    reg [15:0] copy_height_r;
    reg        copy_argb_r;
    reg        copy_separate_r;
    reg [31:0] blur_source_r;
    reg [31:0] blur_source_stride_r;
    reg [31:0] blur_scratch_r;
    reg [31:0] blur_scratch_stride_r;
    reg [31:0] blur_output_r;
    reg [31:0] blur_output_stride_r;
    reg [15:0] blur_width_r;
    reg [15:0] blur_height_r;
    reg [4:0]  blur_radius_r;
    reg [31:0] shadow_front_r;
    reg [31:0] shadow_front_stride_r;
    reg [15:0] shadow_x_r;
    reg [15:0] shadow_width_r;
    reg [15:0] shadow_height_r;
    reg [7:0]  shadow_corner_r;
    reg [4:0]  shadow_blur_radius_r;
    reg [31:0] shadow_mask_r;
    reg [31:0] shadow_scratch_r;
    reg [31:0] shadow_blurred_r;
    reg [31:0] shadow_mask_stride_r;
    reg [31:0] shadow_color_r;
    reg [15:0] shadow_chunk_r;

    wire fetch_start_ready_w;
    wire fetch_cmd_valid_w;
    wire [511:0] fetch_cmd_data_w;
    wire [15:0] fetch_cmd_index_w;
    wire fetch_done_w, fetch_error_w;
    wire fetch_arvalid_w, fetch_rready_w;
    wire [3:0] fetch_arid_w;
    wire [31:0] fetch_araddr_w;
    wire [7:0] fetch_arlen_w;
    wire [2:0] fetch_arsize_w;
    wire [1:0] fetch_arburst_w;
    wire fill_start_ready_w, fill_done_w, fill_error_w;
    wire [3:0] fill_awid_w;
    wire [31:0] fill_awaddr_w;
    wire [7:0] fill_awlen_w;
    wire [2:0] fill_awsize_w;
    wire [1:0] fill_awburst_w;
    wire [3:0] fill_awqos_w;
    wire fill_awvalid_w, fill_wvalid_w, fill_wlast_w, fill_bready_w;
    wire [255:0] fill_wdata_w;
    wire [31:0] fill_wstrb_w;
    wire compose_start_ready_w, compose_done_w, compose_error_w;
    wire [3:0] compose_arid_w, compose_awid_w;
    wire [31:0] compose_araddr_w, compose_awaddr_w;
    wire [7:0] compose_arlen_w, compose_awlen_w;
    wire [2:0] compose_arsize_w, compose_awsize_w;
    wire [1:0] compose_arburst_w, compose_awburst_w;
    wire [3:0] compose_arqos_w, compose_awqos_w;
    wire compose_arvalid_w, compose_rready_w;
    wire compose_awvalid_w, compose_wvalid_w, compose_wlast_w;
    wire compose_bready_w;
    wire [255:0] compose_wdata_w;
    wire [31:0] compose_wstrb_w;
    wire round_start_ready_w, round_done_w, round_error_w;
    wire [3:0] round_arid_w, round_awid_w;
    wire [31:0] round_araddr_w, round_awaddr_w;
    wire [7:0] round_arlen_w, round_awlen_w;
    wire [3:0] round_arqos_w, round_awqos_w;
    wire round_arvalid_w, round_rready_w;
    wire round_awvalid_w, round_wvalid_w, round_wlast_w;
    wire round_bready_w;
    wire [255:0] round_wdata_w;
    wire [31:0] round_wstrb_w;
    wire a8_start_ready_w, a8_done_w, a8_error_w;
    wire [3:0] a8_arid_w, a8_awid_w;
    wire [31:0] a8_araddr_w, a8_awaddr_w;
    wire [7:0] a8_arlen_w, a8_awlen_w;
    wire [3:0] a8_arqos_w, a8_awqos_w;
    wire a8_arvalid_w, a8_rready_w;
    wire a8_awvalid_w, a8_wvalid_w, a8_wlast_w;
    wire a8_bready_w;
    wire [255:0] a8_wdata_w;
    wire [31:0] a8_wstrb_w;
    wire bitmap_start_ready_w, bitmap_done_w, bitmap_error_w;
    wire [3:0] bitmap_arid_w, bitmap_awid_w;
    wire [31:0] bitmap_araddr_w, bitmap_awaddr_w;
    wire [7:0] bitmap_arlen_w, bitmap_awlen_w;
    wire [3:0] bitmap_arqos_w, bitmap_awqos_w;
    wire bitmap_arvalid_w, bitmap_rready_w;
    wire bitmap_awvalid_w, bitmap_wvalid_w, bitmap_wlast_w;
    wire bitmap_bready_w;
    wire [255:0] bitmap_wdata_w;
    wire [31:0] bitmap_wstrb_w;
    wire copy_start_ready_w, copy_done_w, copy_error_w;
    wire [3:0] copy_arid_w, copy_awid_w;
    wire [31:0] copy_araddr_w, copy_awaddr_w;
    wire [7:0] copy_arlen_w, copy_awlen_w;
    wire [3:0] copy_arqos_w, copy_awqos_w;
    wire copy_arvalid_w, copy_rready_w;
    wire copy_awvalid_w, copy_wvalid_w, copy_wlast_w;
    wire copy_bready_w;
    wire [255:0] copy_wdata_w;
    wire [31:0] copy_wstrb_w;
    wire blur_start_ready_w, blur_done_w, blur_error_w;
    wire [3:0] blur_arid_w, blur_awid_w;
    wire [31:0] blur_araddr_w, blur_awaddr_w;
    wire [7:0] blur_arlen_w, blur_awlen_w;
    wire [3:0] blur_arqos_w, blur_awqos_w;
    wire blur_arvalid_w, blur_rready_w;
    wire blur_awvalid_w, blur_wvalid_w, blur_wlast_w;
    wire blur_bready_w;
    wire [255:0] blur_wdata_w;
    wire [31:0] blur_wstrb_w;
    wire mask_start_ready_w, mask_done_w, mask_error_w;
    wire [3:0] mask_awid_w;
    wire [31:0] mask_awaddr_w;
    wire [7:0] mask_awlen_w;
    wire [3:0] mask_awqos_w;
    wire mask_awvalid_w, mask_wvalid_w, mask_wlast_w;
    wire mask_bready_w;
    wire [255:0] mask_wdata_w;
    wire [31:0] mask_wstrb_w;

    wire compose_blend_valid_w, compose_blend_ready_w;
    wire round_blend_valid_w, round_blend_ready_w;
    wire a8_blend_valid_w, a8_blend_ready_w;
    wire bitmap_blend_valid_w, bitmap_blend_ready_w;
    wire [63:0] compose_blend_src_w, compose_blend_dst_w;
    wire [63:0] round_blend_src_w, round_blend_dst_w;
    wire [63:0] a8_blend_src_w, a8_blend_dst_w;
    wire [63:0] bitmap_blend_src_w, bitmap_blend_dst_w;
    wire [15:0] compose_blend_opacity_w, round_blend_opacity_w;
    wire [15:0] a8_blend_opacity_w;
    wire [15:0] bitmap_blend_opacity_w;
    wire compose_blend_premul_w, round_blend_premul_w;
    wire a8_blend_premul_w;
    wire bitmap_blend_premul_w;
    wire [31:0] compose_blend_tag_w, round_blend_tag_w;
    wire [31:0] a8_blend_tag_w;
    wire [31:0] bitmap_blend_tag_w;
    wire compose_blend_out_ready_w, round_blend_out_ready_w;
    wire a8_blend_out_ready_w;
    wire bitmap_blend_out_ready_w;
    wire shared_blend_ready_w;
    wire blend_result_valid_w;
    wire [63:0] blend_result_pixel_w;
    wire [31:0] blend_result_tag_w;

    wire fetch_fire_w = (state_r == ST_FETCH) && fetch_cmd_valid_w;
    wire [7:0] opcode_w = fetch_cmd_data_w[7:0];
    wire opcode_gradient_w = opcode_w == OP_GRADIENT;
    wire opcode_fill_w = (opcode_w == OP_FILL565) ||
                          (opcode_w == OP_FILL8888) ||
                          opcode_gradient_w;
    wire opcode_compose_w = ENABLE_CMD_COMPOSE &&
                            opcode_w == OP_COMPOSE;
    wire opcode_round_w = opcode_w == OP_ROUND;
    wire opcode_a8_w = opcode_w == OP_A8;
    wire opcode_bitmap_w = opcode_w == OP_BITMAP;
    wire opcode_copy_w = opcode_w == OP_COPY;
    wire opcode_blur_w = opcode_w == OP_A8_BLUR;
    wire opcode_shadow_w = opcode_w == OP_BOX_SHADOW;
    wire [16:0] shadow_next_chunk_w =
        {1'b0,shadow_chunk_r} + 17'd32;
    wire [16:0] shadow_remaining_w =
        {1'b0,shadow_width_r} - shadow_next_chunk_w;
    wire start_fire_w = start_i && start_ready_o;
    wire direct_fire_w = compose_direct_start_i &&
                         compose_direct_ready_o;
    assign draw_active_o = (state_r != ST_IDLE) && !direct_active_r;
    assign compose_direct_active_o =
        (state_r != ST_IDLE) && direct_active_r;
    assign compose_direct_target_base_o = compose_target_r;

    edrv32_render_cmd_fetch u_fetch (
        .clk_i(clk_i), .rst_n_i(rst_n_i),
        .start_i(start_fire_w && (list_count_i != 16'd0)),
        .cancel_i(cancel_fetch_r),
        .start_ready_o(fetch_start_ready_w),
        .list_base_i(list_base_i), .list_count_i(list_count_i),
        .cmd_valid_o(fetch_cmd_valid_w),
        .cmd_ready_i(state_r == ST_FETCH),
        .cmd_data_o(fetch_cmd_data_w),
        .cmd_index_o(fetch_cmd_index_w),
        .busy_o(), .done_o(fetch_done_w),
        .error_o(fetch_error_w),
        .m_arid_o(fetch_arid_w), .m_araddr_o(fetch_araddr_w),
        .m_arlen_o(fetch_arlen_w), .m_arsize_o(fetch_arsize_w),
        .m_arburst_o(fetch_arburst_w),
        .m_arvalid_o(fetch_arvalid_w),
        .m_arready_i((state_r == ST_FETCH) && m_arready_i),
        .m_rid_i(m_rid_i), .m_rdata_i(m_rdata_i),
        .m_rresp_i(m_rresp_i), .m_rlast_i(m_rlast_i),
        .m_rvalid_i((state_r == ST_FETCH) && m_rvalid_i),
        .m_rready_o(fetch_rready_w)
    );

    edrv32_render_fill_dma u_fill (
        .clk_i(clk_i), .rst_n_i(rst_n_i),
        .start_i(fill_start_r), .start_ready_o(fill_start_ready_w),
        .row0_base_i(fill_base_r), .stride_i(fill_stride_r),
        .x_i(fill_x_r), .width_i(fill_width_r),
        .height_i(fill_height_r), .argb_i(fill_argb_r),
        .color_i(fill_color_r),
        .gradient_i(fill_gradient_r),
        .gradient_vertical_i(fill_vertical_r),
        .gradient_step_a_i(fill_step_a_r),
        .gradient_step_r_i(fill_step_r_r),
        .gradient_step_g_i(fill_step_g_r),
        .gradient_step_b_i(fill_step_b_r),
        .busy_o(), .done_o(fill_done_w), .error_o(fill_error_w),
        .beat_count_o(), .burst_count_o(),
        .m_awid_o(fill_awid_w), .m_awaddr_o(fill_awaddr_w),
        .m_awlen_o(fill_awlen_w), .m_awsize_o(fill_awsize_w),
        .m_awburst_o(fill_awburst_w), .m_awqos_o(fill_awqos_w),
        .m_awvalid_o(fill_awvalid_w),
        .m_awready_i((state_r == ST_FILL) && m_awready_i),
        .m_wdata_o(fill_wdata_w), .m_wstrb_o(fill_wstrb_w),
        .m_wlast_o(fill_wlast_w), .m_wvalid_o(fill_wvalid_w),
        .m_wready_i((state_r == ST_FILL) && m_wready_i),
        .m_bid_i(m_bid_i), .m_bresp_i(m_bresp_i),
        .m_bvalid_i((state_r == ST_FILL) && m_bvalid_i),
        .m_bready_o(fill_bready_w)
    );

    edrv32_render_compose_dma #(.EXTERNAL_BLEND(1)) u_compose (
        .clk_i(clk_i), .rst_n_i(rst_n_i),
        .start_i(compose_start_r),
        .start_ready_o(compose_start_ready_w),
        .base_addr_i(compose_base_r),
        .base_stride_i(compose_base_stride_r),
        .front_addr_i(compose_front_r),
        .front_stride_i(compose_front_stride_r),
        .target_addr_i(compose_target_r),
        .target_stride_i(compose_target_stride_r),
        .width_i(compose_width_r), .height_i(compose_height_r),
        .busy_o(), .done_o(compose_done_w),
        .error_o(compose_error_w),
        .read_beat_count_o(), .write_beat_count_o(),
        .blend_in_valid_o(compose_blend_valid_w),
        .blend_in_ready_i(compose_blend_ready_w),
        .blend_src_o(compose_blend_src_w),
        .blend_dst_o(compose_blend_dst_w),
        .blend_opacity_o(compose_blend_opacity_w),
        .blend_premul_o(compose_blend_premul_w),
        .blend_tag_o(compose_blend_tag_w),
        .blend_out_valid_i((state_r == ST_COMPOSE) &&
                           blend_result_valid_w),
        .blend_out_ready_o(compose_blend_out_ready_w),
        .blend_pixel_i(blend_result_pixel_w),
        .m_arid_o(compose_arid_w),
        .m_araddr_o(compose_araddr_w),
        .m_arlen_o(compose_arlen_w),
        .m_arsize_o(compose_arsize_w),
        .m_arburst_o(compose_arburst_w),
        .m_arqos_o(compose_arqos_w),
        .m_arvalid_o(compose_arvalid_w),
        .m_arready_i((state_r == ST_COMPOSE) && m_arready_i),
        .m_rid_i(m_rid_i), .m_rdata_i(m_rdata_i),
        .m_rresp_i(m_rresp_i), .m_rlast_i(m_rlast_i),
        .m_rvalid_i((state_r == ST_COMPOSE) && m_rvalid_i),
        .m_rready_o(compose_rready_w),
        .m_awid_o(compose_awid_w),
        .m_awaddr_o(compose_awaddr_w),
        .m_awlen_o(compose_awlen_w),
        .m_awsize_o(compose_awsize_w),
        .m_awburst_o(compose_awburst_w),
        .m_awqos_o(compose_awqos_w),
        .m_awvalid_o(compose_awvalid_w),
        .m_awready_i((state_r == ST_COMPOSE) && m_awready_i),
        .m_wdata_o(compose_wdata_w),
        .m_wstrb_o(compose_wstrb_w),
        .m_wlast_o(compose_wlast_w),
        .m_wvalid_o(compose_wvalid_w),
        .m_wready_i((state_r == ST_COMPOSE) && m_wready_i),
        .m_bid_i(m_bid_i), .m_bresp_i(m_bresp_i),
        .m_bvalid_i((state_r == ST_COMPOSE) && m_bvalid_i),
        .m_bready_o(compose_bready_w)
    );

    edrv32_render_round_dma u_round (
        .clk_i(clk_i), .rst_n_i(rst_n_i),
        .start_i(round_start_r), .start_ready_o(round_start_ready_w),
        .row0_base_i(round_base_r), .stride_i(round_stride_r),
        .x_i(round_x_r), .width_i(round_width_r),
        .height_i(round_height_r), .radius_i(round_radius_r),
        .border_i(round_border_r),
        .fill_color_i(round_fill_color_r),
        .border_color_i(round_border_color_r),
        .busy_o(), .done_o(round_done_w), .error_o(round_error_w),
        .beat_count_o(),
        .blend_in_valid_o(round_blend_valid_w),
        .blend_in_ready_i(round_blend_ready_w),
        .blend_src_o(round_blend_src_w),
        .blend_dst_o(round_blend_dst_w),
        .blend_opacity_o(round_blend_opacity_w),
        .blend_premul_o(round_blend_premul_w),
        .blend_tag_o(round_blend_tag_w),
        .blend_out_valid_i((state_r == ST_ROUND) &&
                           blend_result_valid_w),
        .blend_out_ready_o(round_blend_out_ready_w),
        .blend_pixel_i(blend_result_pixel_w),
        .blend_out_tag_i(blend_result_tag_w),
        .m_arid_o(round_arid_w), .m_araddr_o(round_araddr_w),
        .m_arlen_o(round_arlen_w), .m_arsize_o(),
        .m_arburst_o(), .m_arqos_o(round_arqos_w),
        .m_arvalid_o(round_arvalid_w),
        .m_arready_i((state_r == ST_ROUND) && m_arready_i),
        .m_rid_i(m_rid_i), .m_rdata_i(m_rdata_i),
        .m_rresp_i(m_rresp_i), .m_rlast_i(m_rlast_i),
        .m_rvalid_i((state_r == ST_ROUND) && m_rvalid_i),
        .m_rready_o(round_rready_w),
        .m_awid_o(round_awid_w), .m_awaddr_o(round_awaddr_w),
        .m_awlen_o(round_awlen_w), .m_awsize_o(),
        .m_awburst_o(), .m_awqos_o(round_awqos_w),
        .m_awvalid_o(round_awvalid_w),
        .m_awready_i((state_r == ST_ROUND) && m_awready_i),
        .m_wdata_o(round_wdata_w), .m_wstrb_o(round_wstrb_w),
        .m_wlast_o(round_wlast_w), .m_wvalid_o(round_wvalid_w),
        .m_wready_i((state_r == ST_ROUND) && m_wready_i),
        .m_bid_i(m_bid_i), .m_bresp_i(m_bresp_i),
        .m_bvalid_i((state_r == ST_ROUND) && m_bvalid_i),
        .m_bready_o(round_bready_w)
    );

    edrv32_render_a8_blit_dma u_a8 (
        .clk_i(clk_i), .rst_n_i(rst_n_i),
        .start_i(a8_start_r), .start_ready_o(a8_start_ready_w),
        .front_row0_addr_i(a8_front_r),
        .front_stride_i(a8_front_stride_r),
        .x_i(a8_x_r), .width_i(a8_width_r),
        .height_i(a8_height_r),
        .mask_row0_addr_i(a8_mask_r),
        .mask_stride_i(a8_mask_stride_r),
        .color_i(a8_color_r),
        .busy_o(), .done_o(a8_done_w), .error_o(a8_error_w),
        .beat_count_o(),
        .blend_in_valid_o(a8_blend_valid_w),
        .blend_in_ready_i(a8_blend_ready_w),
        .blend_src_o(a8_blend_src_w),
        .blend_dst_o(a8_blend_dst_w),
        .blend_opacity_o(a8_blend_opacity_w),
        .blend_premul_o(a8_blend_premul_w),
        .blend_tag_o(a8_blend_tag_w),
        .blend_out_valid_i((state_r == ST_A8) &&
                           blend_result_valid_w),
        .blend_out_ready_o(a8_blend_out_ready_w),
        .blend_pixel_i(blend_result_pixel_w),
        .blend_out_tag_i(blend_result_tag_w),
        .m_arid_o(a8_arid_w), .m_araddr_o(a8_araddr_w),
        .m_arlen_o(a8_arlen_w), .m_arsize_o(),
        .m_arburst_o(), .m_arqos_o(a8_arqos_w),
        .m_arvalid_o(a8_arvalid_w),
        .m_arready_i((state_r == ST_A8) && m_arready_i),
        .m_rid_i(m_rid_i), .m_rdata_i(m_rdata_i),
        .m_rresp_i(m_rresp_i), .m_rlast_i(m_rlast_i),
        .m_rvalid_i((state_r == ST_A8) && m_rvalid_i),
        .m_rready_o(a8_rready_w),
        .m_awid_o(a8_awid_w), .m_awaddr_o(a8_awaddr_w),
        .m_awlen_o(a8_awlen_w), .m_awsize_o(),
        .m_awburst_o(), .m_awqos_o(a8_awqos_w),
        .m_awvalid_o(a8_awvalid_w),
        .m_awready_i((state_r == ST_A8) && m_awready_i),
        .m_wdata_o(a8_wdata_w), .m_wstrb_o(a8_wstrb_w),
        .m_wlast_o(a8_wlast_w), .m_wvalid_o(a8_wvalid_w),
        .m_wready_i((state_r == ST_A8) && m_wready_i),
        .m_bid_i(m_bid_i), .m_bresp_i(m_bresp_i),
        .m_bvalid_i((state_r == ST_A8) && m_bvalid_i),
        .m_bready_o(a8_bready_w)
    );

    edrv32_render_bitmap_blit_dma u_bitmap (
        .clk_i(clk_i), .rst_n_i(rst_n_i),
        .start_i(bitmap_start_r),
        .start_ready_o(bitmap_start_ready_w),
        .front_row0_addr_i(bitmap_front_r),
        .front_stride_i(bitmap_front_stride_r),
        .x_i(bitmap_x_r), .width_i(bitmap_width_r),
        .height_i(bitmap_height_r),
        .source_row0_addr_i(bitmap_source_r),
        .source_stride_i(bitmap_source_stride_r),
        .source_x_i(bitmap_source_x_r),
        .source_argb_i(bitmap_argb_r),
        .source_premul_i(bitmap_premul_r),
        .opacity_i(bitmap_opacity_r),
        .flip_x_i(bitmap_flip_x_r),
        .flip_y_i(bitmap_flip_y_r),
        .color_key_enable_i(bitmap_color_key_enable_r),
        .color_key_i(bitmap_color_key_r),
        .scale_enable_i(bitmap_scale_enable_r),
        .scale_step_x_i(bitmap_scale_step_x_r),
        .scale_step_y_i(bitmap_scale_step_y_r),
        .busy_o(), .done_o(bitmap_done_w),
        .error_o(bitmap_error_w), .beat_count_o(),
        .blend_in_valid_o(bitmap_blend_valid_w),
        .blend_in_ready_i(bitmap_blend_ready_w),
        .blend_src_o(bitmap_blend_src_w),
        .blend_dst_o(bitmap_blend_dst_w),
        .blend_opacity_o(bitmap_blend_opacity_w),
        .blend_premul_o(bitmap_blend_premul_w),
        .blend_tag_o(bitmap_blend_tag_w),
        .blend_out_valid_i((state_r == ST_BITMAP) &&
                           blend_result_valid_w),
        .blend_out_ready_o(bitmap_blend_out_ready_w),
        .blend_pixel_i(blend_result_pixel_w),
        .blend_out_tag_i(blend_result_tag_w),
        .m_arid_o(bitmap_arid_w), .m_araddr_o(bitmap_araddr_w),
        .m_arlen_o(bitmap_arlen_w), .m_arsize_o(),
        .m_arburst_o(), .m_arqos_o(bitmap_arqos_w),
        .m_arvalid_o(bitmap_arvalid_w),
        .m_arready_i((state_r == ST_BITMAP) && m_arready_i),
        .m_rid_i(m_rid_i), .m_rdata_i(m_rdata_i),
        .m_rresp_i(m_rresp_i), .m_rlast_i(m_rlast_i),
        .m_rvalid_i((state_r == ST_BITMAP) && m_rvalid_i),
        .m_rready_o(bitmap_rready_w),
        .m_awid_o(bitmap_awid_w), .m_awaddr_o(bitmap_awaddr_w),
        .m_awlen_o(bitmap_awlen_w), .m_awsize_o(),
        .m_awburst_o(), .m_awqos_o(bitmap_awqos_w),
        .m_awvalid_o(bitmap_awvalid_w),
        .m_awready_i((state_r == ST_BITMAP) && m_awready_i),
        .m_wdata_o(bitmap_wdata_w),
        .m_wstrb_o(bitmap_wstrb_w),
        .m_wlast_o(bitmap_wlast_w),
        .m_wvalid_o(bitmap_wvalid_w),
        .m_wready_i((state_r == ST_BITMAP) && m_wready_i),
        .m_bid_i(m_bid_i), .m_bresp_i(m_bresp_i),
        .m_bvalid_i((state_r == ST_BITMAP) && m_bvalid_i),
        .m_bready_o(bitmap_bready_w)
    );

    edrv32_render_copy_dma u_copy (
        .clk_i(clk_i), .rst_n_i(rst_n_i),
        .start_i(copy_start_r),
        .start_ready_o(copy_start_ready_w),
        .source_row0_addr_i(copy_source_r),
        .source_stride_i(copy_source_stride_r),
        .source_x_i(copy_source_x_r),
        .target_row0_addr_i(copy_target_r),
        .target_stride_i(copy_target_stride_r),
        .target_x_i(copy_target_x_r),
        .width_i(copy_width_r), .height_i(copy_height_r),
        .argb_i(copy_argb_r),
        .separate_surfaces_i(copy_separate_r),
        .busy_o(), .done_o(copy_done_w),
        .error_o(copy_error_w), .beat_count_o(),
        .m_arid_o(copy_arid_w), .m_araddr_o(copy_araddr_w),
        .m_arlen_o(copy_arlen_w), .m_arsize_o(),
        .m_arburst_o(), .m_arqos_o(copy_arqos_w),
        .m_arvalid_o(copy_arvalid_w),
        .m_arready_i((state_r == ST_COPY) && m_arready_i),
        .m_rid_i(m_rid_i), .m_rdata_i(m_rdata_i),
        .m_rresp_i(m_rresp_i), .m_rlast_i(m_rlast_i),
        .m_rvalid_i((state_r == ST_COPY) && m_rvalid_i),
        .m_rready_o(copy_rready_w),
        .m_awid_o(copy_awid_w), .m_awaddr_o(copy_awaddr_w),
        .m_awlen_o(copy_awlen_w), .m_awsize_o(),
        .m_awburst_o(), .m_awqos_o(copy_awqos_w),
        .m_awvalid_o(copy_awvalid_w),
        .m_awready_i((state_r == ST_COPY) && m_awready_i),
        .m_wdata_o(copy_wdata_w),
        .m_wstrb_o(copy_wstrb_w),
        .m_wlast_o(copy_wlast_w),
        .m_wvalid_o(copy_wvalid_w),
        .m_wready_i((state_r == ST_COPY) && m_wready_i),
        .m_bid_i(m_bid_i), .m_bresp_i(m_bresp_i),
        .m_bvalid_i((state_r == ST_COPY) && m_bvalid_i),
        .m_bready_o(copy_bready_w)
    );

    edrv32_render_a8_blur_dma u_blur (
        .clk_i(clk_i), .rst_n_i(rst_n_i),
        .start_i(blur_start_r),
        .start_ready_o(blur_start_ready_w),
        .source_base_i(blur_source_r),
        .source_stride_i(blur_source_stride_r),
        .scratch_base_i(blur_scratch_r),
        .scratch_stride_i(blur_scratch_stride_r),
        .output_base_i(blur_output_r),
        .output_stride_i(blur_output_stride_r),
        .width_i(blur_width_r), .height_i(blur_height_r),
        .radius_i(blur_radius_r),
        .busy_o(), .done_o(blur_done_w),
        .error_o(blur_error_w), .write_beat_count_o(),
        .m_arid_o(blur_arid_w), .m_araddr_o(blur_araddr_w),
        .m_arlen_o(blur_arlen_w), .m_arsize_o(),
        .m_arburst_o(), .m_arqos_o(blur_arqos_w),
        .m_arvalid_o(blur_arvalid_w),
        .m_arready_i((state_r == ST_BLUR) && m_arready_i),
        .m_rid_i(m_rid_i), .m_rdata_i(m_rdata_i),
        .m_rresp_i(m_rresp_i), .m_rlast_i(m_rlast_i),
        .m_rvalid_i((state_r == ST_BLUR) && m_rvalid_i),
        .m_rready_o(blur_rready_w),
        .m_awid_o(blur_awid_w), .m_awaddr_o(blur_awaddr_w),
        .m_awlen_o(blur_awlen_w), .m_awsize_o(),
        .m_awburst_o(), .m_awqos_o(blur_awqos_w),
        .m_awvalid_o(blur_awvalid_w),
        .m_awready_i((state_r == ST_BLUR) && m_awready_i),
        .m_wdata_o(blur_wdata_w), .m_wstrb_o(blur_wstrb_w),
        .m_wlast_o(blur_wlast_w), .m_wvalid_o(blur_wvalid_w),
        .m_wready_i((state_r == ST_BLUR) && m_wready_i),
        .m_bid_i(m_bid_i), .m_bresp_i(m_bresp_i),
        .m_bvalid_i((state_r == ST_BLUR) && m_bvalid_i),
        .m_bready_o(blur_bready_w)
    );

    edrv32_render_shadow_mask_dma u_mask (
        .clk_i(clk_i), .rst_n_i(rst_n_i),
        .start_i(mask_start_r),
        .start_ready_o(mask_start_ready_w),
        .mask_base_i(shadow_mask_r),
        .mask_stride_i(shadow_mask_stride_r),
        .width_i(shadow_width_r),
        .height_i(shadow_height_r),
        .corner_radius_i(shadow_corner_r),
        .blur_radius_i(shadow_blur_radius_r),
        .busy_o(), .done_o(mask_done_w),
        .error_o(mask_error_w), .beat_count_o(),
        .m_awid_o(mask_awid_w),
        .m_awaddr_o(mask_awaddr_w),
        .m_awlen_o(mask_awlen_w), .m_awsize_o(),
        .m_awburst_o(), .m_awqos_o(mask_awqos_w),
        .m_awvalid_o(mask_awvalid_w),
        .m_awready_i((state_r == ST_MASK) && m_awready_i),
        .m_wdata_o(mask_wdata_w),
        .m_wstrb_o(mask_wstrb_w),
        .m_wlast_o(mask_wlast_w),
        .m_wvalid_o(mask_wvalid_w),
        .m_wready_i((state_r == ST_MASK) && m_wready_i),
        .m_bid_i(m_bid_i), .m_bresp_i(m_bresp_i),
        .m_bvalid_i((state_r == ST_MASK) && m_bvalid_i),
        .m_bready_o(mask_bready_w)
    );

    edrv32_render_alpha_pipe u_shared_alpha (
        .clk_i(clk_i), .rst_n_i(rst_n_i),
        .in_valid_i(state_r == ST_COMPOSE ? compose_blend_valid_w :
                    state_r == ST_ROUND ? round_blend_valid_w :
                    state_r == ST_A8 ? a8_blend_valid_w :
                    state_r == ST_BITMAP && bitmap_blend_valid_w),
        .in_ready_o(shared_blend_ready_w),
        .in_src_i(state_r == ST_COMPOSE ? compose_blend_src_w :
                  state_r == ST_ROUND ? round_blend_src_w :
                  state_r == ST_A8 ? a8_blend_src_w :
                  bitmap_blend_src_w),
        .in_dst_i(state_r == ST_COMPOSE ? compose_blend_dst_w :
                  state_r == ST_ROUND ? round_blend_dst_w :
                  state_r == ST_A8 ? a8_blend_dst_w :
                  bitmap_blend_dst_w),
        .in_opacity_i(state_r == ST_COMPOSE ?
                      compose_blend_opacity_w :
                      state_r == ST_ROUND ? round_blend_opacity_w :
                      state_r == ST_A8 ? a8_blend_opacity_w :
                      bitmap_blend_opacity_w),
        .in_src_premul_i(state_r == ST_COMPOSE ?
                         compose_blend_premul_w :
                         state_r == ST_ROUND ? round_blend_premul_w :
                         state_r == ST_A8 ? a8_blend_premul_w :
                         bitmap_blend_premul_w),
        .in_tag_i(state_r == ST_COMPOSE ? compose_blend_tag_w :
                  state_r == ST_ROUND ? round_blend_tag_w :
                  state_r == ST_A8 ? a8_blend_tag_w :
                  bitmap_blend_tag_w),
        .out_valid_o(blend_result_valid_w),
        .out_ready_i(state_r == ST_COMPOSE ?
                     compose_blend_out_ready_w :
                     state_r == ST_ROUND ? round_blend_out_ready_w :
                     state_r == ST_A8 ? a8_blend_out_ready_w :
                     state_r == ST_BITMAP && bitmap_blend_out_ready_w),
        .out_pixel_o(blend_result_pixel_w),
        .out_tag_o(blend_result_tag_w)
    );
    assign compose_blend_ready_w =
        (state_r == ST_COMPOSE) && shared_blend_ready_w;
    assign round_blend_ready_w =
        (state_r == ST_ROUND) && shared_blend_ready_w;
    assign a8_blend_ready_w =
        (state_r == ST_A8) && shared_blend_ready_w;
    assign bitmap_blend_ready_w =
        (state_r == ST_BITMAP) && shared_blend_ready_w;

    assign start_ready_o = (state_r == ST_IDLE) &&
                           !cancel_fetch_r &&
                           fetch_start_ready_w &&
                           fill_start_ready_w &&
                           compose_start_ready_w &&
                           round_start_ready_w &&
                           a8_start_ready_w &&
                           bitmap_start_ready_w &&
                           copy_start_ready_w &&
                           blur_start_ready_w &&
                           mask_start_ready_w;
    assign busy_o = state_r != ST_IDLE;
    assign done_o = done_r;
    assign error_o = error_r;
    assign completed_count_o = completed_count_r;
    assign compose_direct_ready_o = start_ready_o && !start_i;
    assign compose_direct_done_o = direct_done_r;
    assign compose_direct_error_o = direct_error_r;

    assign m_arid_o = state_r == ST_FETCH ? fetch_arid_w :
                      state_r == ST_ROUND ? round_arid_w :
                      state_r == ST_A8 ? a8_arid_w :
                      state_r == ST_BITMAP ? bitmap_arid_w :
                      state_r == ST_COPY ? copy_arid_w :
                      state_r == ST_BLUR ? blur_arid_w : compose_arid_w;
    assign m_araddr_o = state_r == ST_FETCH ? fetch_araddr_w :
                       state_r == ST_ROUND ? round_araddr_w :
                       state_r == ST_A8 ? a8_araddr_w :
                       state_r == ST_BITMAP ? bitmap_araddr_w :
                       state_r == ST_COPY ? copy_araddr_w :
                       state_r == ST_BLUR ? blur_araddr_w :
                       compose_araddr_w;
    assign m_arlen_o = state_r == ST_FETCH ? fetch_arlen_w :
                       state_r == ST_ROUND ? round_arlen_w :
                       state_r == ST_A8 ? a8_arlen_w :
                       state_r == ST_BITMAP ? bitmap_arlen_w :
                       state_r == ST_COPY ? copy_arlen_w :
                       state_r == ST_BLUR ? blur_arlen_w : compose_arlen_w;
    assign m_arsize_o = 3'd5;
    assign m_arburst_o = 2'b01;
    assign m_arqos_o = state_r == ST_FETCH ? 4'd2 :
                       state_r == ST_ROUND ? round_arqos_w :
                       state_r == ST_A8 ? a8_arqos_w :
                       state_r == ST_BITMAP ? bitmap_arqos_w :
                       state_r == ST_COPY ? copy_arqos_w :
                       state_r == ST_BLUR ? blur_arqos_w : compose_arqos_w;
    assign m_arvalid_o = state_r == ST_FETCH ? fetch_arvalid_w :
                         ((state_r == ST_COMPOSE && compose_arvalid_w) ||
                          (state_r == ST_ROUND && round_arvalid_w) ||
                          (state_r == ST_A8 && a8_arvalid_w) ||
                          (state_r == ST_BITMAP && bitmap_arvalid_w) ||
                          (state_r == ST_COPY && copy_arvalid_w) ||
                          (state_r == ST_BLUR && blur_arvalid_w));
    assign m_rready_o = state_r == ST_FETCH ? fetch_rready_w :
                        ((state_r == ST_COMPOSE && compose_rready_w) ||
                         (state_r == ST_ROUND && round_rready_w) ||
                         (state_r == ST_A8 && a8_rready_w) ||
                         (state_r == ST_BITMAP && bitmap_rready_w) ||
                         (state_r == ST_COPY && copy_rready_w) ||
                         (state_r == ST_BLUR && blur_rready_w));

    assign m_awid_o = state_r == ST_FILL ? fill_awid_w :
                      state_r == ST_ROUND ? round_awid_w :
                      state_r == ST_A8 ? a8_awid_w :
                      state_r == ST_BITMAP ? bitmap_awid_w :
                      state_r == ST_COPY ? copy_awid_w :
                      state_r == ST_MASK ? mask_awid_w :
                      state_r == ST_BLUR ? blur_awid_w : compose_awid_w;
    assign m_awaddr_o = state_r == ST_FILL ? fill_awaddr_w :
                       state_r == ST_ROUND ? round_awaddr_w :
                       state_r == ST_A8 ? a8_awaddr_w :
                       state_r == ST_BITMAP ? bitmap_awaddr_w :
                       state_r == ST_COPY ? copy_awaddr_w :
                       state_r == ST_MASK ? mask_awaddr_w :
                       state_r == ST_BLUR ? blur_awaddr_w :
                       compose_awaddr_w;
    assign m_awlen_o = state_r == ST_FILL ? fill_awlen_w :
                       state_r == ST_ROUND ? round_awlen_w :
                       state_r == ST_A8 ? a8_awlen_w :
                       state_r == ST_BITMAP ? bitmap_awlen_w :
                       state_r == ST_COPY ? copy_awlen_w :
                       state_r == ST_MASK ? mask_awlen_w :
                       state_r == ST_BLUR ? blur_awlen_w : compose_awlen_w;
    assign m_awsize_o = 3'd5;
    assign m_awburst_o = 2'b01;
    assign m_awqos_o = state_r == ST_FILL ? fill_awqos_w :
                       state_r == ST_ROUND ? round_awqos_w :
                       state_r == ST_A8 ? a8_awqos_w :
                       state_r == ST_BITMAP ? bitmap_awqos_w :
                       state_r == ST_COPY ? copy_awqos_w :
                       state_r == ST_MASK ? mask_awqos_w :
                       state_r == ST_BLUR ? blur_awqos_w : compose_awqos_w;
    assign m_awvalid_o = state_r == ST_FILL ? fill_awvalid_w :
                         ((state_r == ST_COMPOSE && compose_awvalid_w) ||
                          (state_r == ST_ROUND && round_awvalid_w) ||
                          (state_r == ST_A8 && a8_awvalid_w) ||
                          (state_r == ST_BITMAP && bitmap_awvalid_w) ||
                          (state_r == ST_COPY && copy_awvalid_w) ||
                          (state_r == ST_MASK && mask_awvalid_w) ||
                          (state_r == ST_BLUR && blur_awvalid_w));
    assign m_wdata_o = state_r == ST_FILL ? fill_wdata_w :
                       state_r == ST_ROUND ? round_wdata_w :
                       state_r == ST_A8 ? a8_wdata_w :
                       state_r == ST_BITMAP ? bitmap_wdata_w :
                       state_r == ST_COPY ? copy_wdata_w :
                       state_r == ST_MASK ? mask_wdata_w :
                       state_r == ST_BLUR ? blur_wdata_w : compose_wdata_w;
    assign m_wstrb_o = state_r == ST_FILL ? fill_wstrb_w :
                       state_r == ST_ROUND ? round_wstrb_w :
                       state_r == ST_A8 ? a8_wstrb_w :
                       state_r == ST_BITMAP ? bitmap_wstrb_w :
                       state_r == ST_COPY ? copy_wstrb_w :
                       state_r == ST_MASK ? mask_wstrb_w :
                       state_r == ST_BLUR ? blur_wstrb_w : compose_wstrb_w;
    assign m_wlast_o = state_r == ST_FILL ? fill_wlast_w :
                       state_r == ST_ROUND ? round_wlast_w :
                       state_r == ST_A8 ? a8_wlast_w :
                       state_r == ST_BITMAP ? bitmap_wlast_w :
                       state_r == ST_COPY ? copy_wlast_w :
                       state_r == ST_MASK ? mask_wlast_w :
                       state_r == ST_BLUR ? blur_wlast_w : compose_wlast_w;
    assign m_wvalid_o = state_r == ST_FILL ? fill_wvalid_w :
                        ((state_r == ST_COMPOSE && compose_wvalid_w) ||
                         (state_r == ST_ROUND && round_wvalid_w) ||
                         (state_r == ST_A8 && a8_wvalid_w) ||
                         (state_r == ST_BITMAP && bitmap_wvalid_w) ||
                         (state_r == ST_COPY && copy_wvalid_w) ||
                         (state_r == ST_MASK && mask_wvalid_w) ||
                         (state_r == ST_BLUR && blur_wvalid_w));
    assign m_bready_o = state_r == ST_FILL ? fill_bready_w :
                        ((state_r == ST_COMPOSE && compose_bready_w) ||
                         (state_r == ST_ROUND && round_bready_w) ||
                         (state_r == ST_A8 && a8_bready_w) ||
                         (state_r == ST_BITMAP && bitmap_bready_w) ||
                         (state_r == ST_COPY && copy_bready_w) ||
                         (state_r == ST_MASK && mask_bready_w) ||
                         (state_r == ST_BLUR && blur_bready_w));

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            state_r <= ST_IDLE;
            done_r <= 1'b0;
            error_r <= 1'b0;
            direct_active_r <= 1'b0;
            direct_done_r <= 1'b0;
            direct_error_r <= 1'b0;
            fill_start_r <= 1'b0;
            compose_start_r <= 1'b0;
            round_start_r <= 1'b0;
            a8_start_r <= 1'b0;
            bitmap_start_r <= 1'b0;
            copy_start_r <= 1'b0;
            blur_start_r <= 1'b0;
            mask_start_r <= 1'b0;
            shadow_active_r <= 1'b0;
            shadow_chunk_r <= 16'd0;
            cancel_fetch_r <= 1'b0;
            last_cmd_r <= 1'b0;
            command_count_r <= 16'b0;
            completed_count_r <= 16'b0;
        end else begin
            done_r <= 1'b0;
            direct_done_r <= 1'b0;
            fill_start_r <= 1'b0;
            compose_start_r <= 1'b0;
            round_start_r <= 1'b0;
            a8_start_r <= 1'b0;
            bitmap_start_r <= 1'b0;
            copy_start_r <= 1'b0;
            blur_start_r <= 1'b0;
            mask_start_r <= 1'b0;
            cancel_fetch_r <= 1'b0;
            case (state_r)
                ST_IDLE: begin
                    if (start_fire_w) begin
                        direct_active_r <= 1'b0;
                        shadow_active_r <= 1'b0;
                        error_r <= 1'b0;
                        completed_count_r <= 16'b0;
                        command_count_r <= list_count_i;
                        if (list_count_i == 16'd0) begin
                            done_r <= 1'b1;
                        end else begin
                            state_r <= ST_FETCH;
                        end
                    end else if (direct_fire_w) begin
                        direct_active_r <= 1'b1;
                        direct_error_r <= 1'b0;
                        compose_base_r <= compose_direct_base_i;
                        compose_base_stride_r <=
                            compose_direct_base_stride_i;
                        compose_front_r <= compose_direct_front_i;
                        compose_front_stride_r <=
                            compose_direct_front_stride_i;
                        compose_target_r <= compose_direct_target_i;
                        compose_target_stride_r <=
                            compose_direct_target_stride_i;
                        compose_width_r <= compose_direct_width_i;
                        compose_height_r <= compose_direct_height_i;
                        compose_start_r <= 1'b1;
                        state_r <= ST_COMPOSE;
                    end
                end
                ST_FETCH: begin
                    if (fetch_fire_w) begin
                        last_cmd_r <= fetch_cmd_index_w ==
                                      command_count_r - 16'd1;
                        if (opcode_fill_w) begin
                            fill_base_r <= fetch_cmd_data_w[63:32];
                            fill_stride_r <= fetch_cmd_data_w[95:64];
                            fill_x_r <= fetch_cmd_data_w[111:96];
                            fill_width_r <= fetch_cmd_data_w[127:112];
                            fill_height_r <= fetch_cmd_data_w[143:128];
                            fill_color_r <= fetch_cmd_data_w[191:160];
                            fill_argb_r <=
                                (opcode_w == OP_FILL8888) ||
                                (opcode_gradient_w &&
                                 fetch_cmd_data_w[8]);
                            fill_gradient_r <= opcode_gradient_w;
                            fill_vertical_r <= fetch_cmd_data_w[9];
                            fill_step_a_r <= fetch_cmd_data_w[223:192];
                            fill_step_r_r <= fetch_cmd_data_w[255:224];
                            fill_step_g_r <= fetch_cmd_data_w[287:256];
                            fill_step_b_r <= fetch_cmd_data_w[319:288];
                            fill_start_r <= 1'b1;
                            state_r <= ST_FILL;
                        end else if (opcode_compose_w) begin
                            compose_base_r <= fetch_cmd_data_w[63:32];
                            compose_base_stride_r <= fetch_cmd_data_w[95:64];
                            compose_front_r <= fetch_cmd_data_w[127:96];
                            compose_front_stride_r <=
                                fetch_cmd_data_w[159:128];
                            compose_target_r <= fetch_cmd_data_w[191:160];
                            compose_target_stride_r <=
                                fetch_cmd_data_w[223:192];
                            compose_width_r <= fetch_cmd_data_w[239:224];
                            compose_height_r <= fetch_cmd_data_w[255:240];
                            compose_start_r <= 1'b1;
                            state_r <= ST_COMPOSE;
                        end else if (opcode_round_w &&
                                     (fetch_cmd_data_w[159:154] != 6'd0 ||
                                      fetch_cmd_data_w[175:170] != 6'd0)) begin
                            error_r <= 1'b1;
                            done_r <= 1'b1;
                            cancel_fetch_r <= 1'b1;
                            state_r <= ST_IDLE;
                        end else if (opcode_round_w) begin
                            round_base_r <= fetch_cmd_data_w[63:32];
                            round_stride_r <= fetch_cmd_data_w[95:64];
                            round_x_r <= fetch_cmd_data_w[111:96];
                            round_width_r <= fetch_cmd_data_w[127:112];
                            round_height_r <= fetch_cmd_data_w[143:128];
                            round_radius_r <= fetch_cmd_data_w[153:144];
                            round_border_r <= fetch_cmd_data_w[169:160];
                            round_fill_color_r <= fetch_cmd_data_w[223:192];
                            round_border_color_r <= fetch_cmd_data_w[255:224];
                            round_start_r <= 1'b1;
                            state_r <= ST_ROUND;
                        end else if (opcode_a8_w) begin
                            a8_front_r <= fetch_cmd_data_w[63:32];
                            a8_front_stride_r <= fetch_cmd_data_w[95:64];
                            a8_x_r <= fetch_cmd_data_w[111:96];
                            a8_width_r <= fetch_cmd_data_w[127:112];
                            a8_height_r <= fetch_cmd_data_w[143:128];
                            a8_mask_r <= fetch_cmd_data_w[191:160];
                            a8_mask_stride_r <= fetch_cmd_data_w[223:192];
                            a8_color_r <= fetch_cmd_data_w[255:224];
                            a8_start_r <= 1'b1;
                            state_r <= ST_A8;
                        end else if (opcode_bitmap_w) begin
                            bitmap_front_r <= fetch_cmd_data_w[63:32];
                            bitmap_front_stride_r <=
                                fetch_cmd_data_w[95:64];
                            bitmap_x_r <= fetch_cmd_data_w[111:96];
                            bitmap_width_r <= fetch_cmd_data_w[127:112];
                            bitmap_height_r <= fetch_cmd_data_w[143:128];
                            bitmap_source_x_r <= fetch_cmd_data_w[159:144];
                            bitmap_source_r <= fetch_cmd_data_w[191:160];
                            bitmap_source_stride_r <=
                                fetch_cmd_data_w[223:192];
                            bitmap_argb_r <= fetch_cmd_data_w[8];
                            bitmap_premul_r <= fetch_cmd_data_w[9];
                            bitmap_opacity_r <= fetch_cmd_data_w[23:16];
                            bitmap_flip_x_r <= fetch_cmd_data_w[10];
                            bitmap_flip_y_r <= fetch_cmd_data_w[11];
                            bitmap_color_key_enable_r <=
                                fetch_cmd_data_w[12];
                            bitmap_color_key_r <=
                                fetch_cmd_data_w[255:224];
                            bitmap_scale_enable_r <=
                                fetch_cmd_data_w[13];
                            bitmap_scale_step_x_r <=
                                fetch_cmd_data_w[287:256];
                            bitmap_scale_step_y_r <=
                                fetch_cmd_data_w[319:288];
                            bitmap_start_r <= 1'b1;
                            state_r <= ST_BITMAP;
                        end else if (opcode_copy_w) begin
                            copy_source_r <= fetch_cmd_data_w[63:32];
                            copy_source_stride_r <= fetch_cmd_data_w[95:64];
                            copy_source_x_r <= fetch_cmd_data_w[111:96];
                            copy_width_r <= fetch_cmd_data_w[127:112];
                            copy_target_r <= fetch_cmd_data_w[159:128];
                            copy_target_stride_r <=
                                fetch_cmd_data_w[191:160];
                            copy_target_x_r <= fetch_cmd_data_w[207:192];
                            copy_height_r <= fetch_cmd_data_w[223:208];
                            copy_argb_r <= fetch_cmd_data_w[8];
                            copy_separate_r <= fetch_cmd_data_w[9];
                            copy_start_r <= 1'b1;
                            state_r <= ST_COPY;
                        end else if (opcode_blur_w) begin
                            blur_source_r <= fetch_cmd_data_w[63:32];
                            blur_source_stride_r <=
                                fetch_cmd_data_w[95:64];
                            blur_scratch_r <= fetch_cmd_data_w[127:96];
                            blur_scratch_stride_r <=
                                fetch_cmd_data_w[159:128];
                            blur_output_r <= fetch_cmd_data_w[191:160];
                            blur_output_stride_r <=
                                fetch_cmd_data_w[223:192];
                            blur_width_r <= fetch_cmd_data_w[239:224];
                            blur_height_r <= fetch_cmd_data_w[255:240];
                            blur_radius_r <= fetch_cmd_data_w[260:256];
                            blur_start_r <= 1'b1;
                            state_r <= ST_BLUR;
                        end else if (opcode_shadow_w &&
                                     fetch_cmd_data_w[159:152] != 8'd0) begin
                            error_r <= 1'b1;
                            done_r <= 1'b1;
                            cancel_fetch_r <= 1'b1;
                            state_r <= ST_IDLE;
                        end else if (opcode_shadow_w) begin
                            shadow_front_r <= fetch_cmd_data_w[63:32];
                            shadow_front_stride_r <=
                                fetch_cmd_data_w[95:64];
                            shadow_x_r <= fetch_cmd_data_w[111:96];
                            shadow_width_r <= fetch_cmd_data_w[127:112];
                            shadow_height_r <= fetch_cmd_data_w[143:128];
                            shadow_corner_r <= fetch_cmd_data_w[151:144];
                            shadow_mask_r <= fetch_cmd_data_w[191:160];
                            shadow_scratch_r <=
                                fetch_cmd_data_w[223:192];
                            shadow_blurred_r <=
                                fetch_cmd_data_w[255:224];
                            shadow_mask_stride_r <=
                                fetch_cmd_data_w[287:256];
                            shadow_color_r <= fetch_cmd_data_w[319:288];
                            shadow_blur_radius_r <=
                                fetch_cmd_data_w[324:320];
                            shadow_chunk_r <= 16'd0;
                            shadow_active_r <= 1'b1;
                            mask_start_r <= 1'b1;
                            state_r <= ST_MASK;
                        end else begin
                            error_r <= 1'b1;
                            done_r <= 1'b1;
                            cancel_fetch_r <= 1'b1;
                            state_r <= ST_IDLE;
                        end
                    end else if (fetch_done_w && fetch_error_w) begin
                        error_r <= 1'b1;
                        done_r <= 1'b1;
                        state_r <= ST_IDLE;
                    end
                end
                ST_FILL: begin
                    if (fill_done_w) begin
                        completed_count_r <= completed_count_r + 16'd1;
                        if (fill_error_w || last_cmd_r) begin
                            error_r <= fill_error_w;
                            done_r <= 1'b1;
                            if (fill_error_w)
                                cancel_fetch_r <= 1'b1;
                            state_r <= ST_IDLE;
                        end else begin
                            state_r <= ST_FETCH;
                        end
                    end
                end
                ST_COMPOSE: begin
                    if (compose_done_w) begin
                        if (direct_active_r) begin
                            direct_done_r <= 1'b1;
                            direct_error_r <= compose_error_w;
                            direct_active_r <= 1'b0;
                            state_r <= ST_IDLE;
                        end else begin
                            completed_count_r <= completed_count_r +
                                                 16'd1;
                            if (compose_error_w || last_cmd_r) begin
                                error_r <= compose_error_w;
                                done_r <= 1'b1;
                                if (compose_error_w)
                                    cancel_fetch_r <= 1'b1;
                                state_r <= ST_IDLE;
                            end else begin
                                state_r <= ST_FETCH;
                            end
                        end
                    end
                end
                ST_ROUND: begin
                    if (round_done_w) begin
                        completed_count_r <= completed_count_r + 16'd1;
                        if (round_error_w || last_cmd_r) begin
                            error_r <= round_error_w;
                            done_r <= 1'b1;
                            if (round_error_w)
                                cancel_fetch_r <= 1'b1;
                            state_r <= ST_IDLE;
                        end else begin
                            state_r <= ST_FETCH;
                        end
                    end
                end
                ST_A8: begin
                    if (a8_done_w) begin
                        if (shadow_active_r && !a8_error_w &&
                            shadow_next_chunk_w <
                            {1'b0,shadow_width_r}) begin
                            shadow_chunk_r <= shadow_next_chunk_w[15:0];
                            a8_x_r <= shadow_x_r +
                                      shadow_next_chunk_w[15:0];
                            a8_width_r <= shadow_remaining_w > 17'd32 ?
                                          16'd32 :
                                          shadow_remaining_w[15:0];
                            a8_mask_r <= shadow_blurred_r +
                                         {16'd0,shadow_next_chunk_w[15:0]};
                            a8_start_r <= 1'b1;
                        end else begin
                            completed_count_r <= completed_count_r + 16'd1;
                            if (shadow_active_r)
                                shadow_active_r <= 1'b0;
                            if (a8_error_w || last_cmd_r) begin
                                error_r <= a8_error_w;
                                done_r <= 1'b1;
                                if (a8_error_w)
                                    cancel_fetch_r <= 1'b1;
                                state_r <= ST_IDLE;
                            end else begin
                                state_r <= ST_FETCH;
                            end
                        end
                    end
                end
                ST_BITMAP: begin
                    if (bitmap_done_w) begin
                        completed_count_r <= completed_count_r + 16'd1;
                        if (bitmap_error_w || last_cmd_r) begin
                            error_r <= bitmap_error_w;
                            done_r <= 1'b1;
                            if (bitmap_error_w)
                                cancel_fetch_r <= 1'b1;
                            state_r <= ST_IDLE;
                        end else begin
                            state_r <= ST_FETCH;
                        end
                    end
                end
                ST_COPY: begin
                    if (copy_done_w) begin
                        completed_count_r <= completed_count_r + 16'd1;
                        if (copy_error_w || last_cmd_r) begin
                            error_r <= copy_error_w;
                            done_r <= 1'b1;
                            if (copy_error_w)
                                cancel_fetch_r <= 1'b1;
                            state_r <= ST_IDLE;
                        end else begin
                            state_r <= ST_FETCH;
                        end
                    end
                end
                ST_MASK: begin
                    if (mask_done_w) begin
                        if (mask_error_w) begin
                            shadow_active_r <= 1'b0;
                            completed_count_r <= completed_count_r +
                                                 16'd1;
                            error_r <= 1'b1;
                            done_r <= 1'b1;
                            cancel_fetch_r <= 1'b1;
                            state_r <= ST_IDLE;
                        end else begin
                            blur_source_r <= shadow_mask_r;
                            blur_source_stride_r <=
                                shadow_mask_stride_r;
                            blur_scratch_r <= shadow_scratch_r;
                            blur_scratch_stride_r <=
                                shadow_mask_stride_r;
                            blur_output_r <= shadow_blurred_r;
                            blur_output_stride_r <=
                                shadow_mask_stride_r;
                            blur_width_r <= shadow_width_r;
                            blur_height_r <= shadow_height_r;
                            blur_radius_r <= shadow_blur_radius_r;
                            blur_start_r <= 1'b1;
                            state_r <= ST_BLUR;
                        end
                    end
                end
                ST_BLUR: begin
                    if (blur_done_w) begin
                        if (shadow_active_r && !blur_error_w) begin
                            a8_front_r <= shadow_front_r;
                            a8_front_stride_r <=
                                shadow_front_stride_r;
                            a8_x_r <= shadow_x_r;
                            a8_width_r <= shadow_width_r > 16'd32 ?
                                          16'd32 : shadow_width_r;
                            a8_height_r <= shadow_height_r;
                            a8_mask_r <= shadow_blurred_r;
                            a8_mask_stride_r <=
                                shadow_mask_stride_r;
                            a8_color_r <= shadow_color_r;
                            a8_start_r <= 1'b1;
                            state_r <= ST_A8;
                        end else begin
                            completed_count_r <= completed_count_r + 16'd1;
                            if (shadow_active_r)
                                shadow_active_r <= 1'b0;
                            if (blur_error_w || last_cmd_r) begin
                                error_r <= blur_error_w;
                                done_r <= 1'b1;
                                if (blur_error_w)
                                    cancel_fetch_r <= 1'b1;
                                state_r <= ST_IDLE;
                            end else begin
                                state_r <= ST_FETCH;
                            end
                        end
                    end
                end
                default: state_r <= ST_IDLE;
            endcase
        end
    end

endmodule
