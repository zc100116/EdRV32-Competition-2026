// ============================================================================
// File        : edrv32_render_system.v
// Description : APB frame control, command executor and one 256-bit AXI port.
// Notes       : Display tokens encode target(1)/bypass base(0) in bit 2.
// ============================================================================

module edrv32_render_system #(
    parameter [31:0] FRONT_BASE   = 32'h0300_0000,
    parameter [31:0] TARGET_BASE0 = 32'h0200_0000,
    parameter [31:0] TARGET_BASE1 = 32'h0220_0000,
    parameter [31:0] TARGET_BASE2 = 32'h0240_0000,
    parameter [31:0] TARGET_SLOT_BYTES = 32'h0020_0000
) (
    input  wire         clk_i,
    input  wire         rst_n_i,

    input  wire [31:0]  paddr_i,
    input  wire         psel_i,
    input  wire         penable_i,
    input  wire         pwrite_i,
    input  wire [31:0]  pwdata_i,
    input  wire [3:0]   pstrb_i,
    output wire         pready_o,
    output wire [31:0]  prdata_o,
    output wire         pslverr_o,
    output wire         irq_o,
    output wire         draw_start_o,
    output wire         draw_done_o,
    output wire [15:0]  draw_completed_count_o,
    output wire         compose_start_o,
    output wire         compose_done_o,

    input  wire         base_valid_i,
    input  wire [1:0]   base_buffer_i,
    input  wire [31:0]  base_addr_i,
    input  wire [31:0]  base_stride_i,
    output wire         base_release_valid_o,
    output wire [1:0]   base_release_buffer_o,

    output wire         display_valid_o,
    input  wire         display_ready_i,
    output wire [2:0]   display_token_o,
    output wire [31:0]  display_base_o,
    input  wire         display_retire_valid_i,
    input  wire [2:0]   display_retire_token_i,

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

    wire draw_start_w, draw_ready_w, draw_done_w, draw_error_w;
    wire [31:0] draw_list_base_w;
    wire [15:0] draw_list_count_w;
    wire compose_start_w, compose_ready_w;
    wire compose_done_w, compose_error_w;
    wire [31:0] compose_base_w, compose_base_stride_w;
    wire [31:0] compose_front_w, compose_front_stride_w;
    wire [31:0] compose_target_w, compose_target_stride_w;
    wire [15:0] compose_width_w, compose_height_w;
    wire [15:0] draw_completed_count_w;
    wire draw_active_w;
    wire compose_direct_active_w;
    wire [31:0] compose_direct_target_base_w;
    wire [3:0] engine_awid_w, engine_awqos_w, engine_bid_w;
    wire [31:0] engine_awaddr_w;
    wire [7:0] engine_awlen_w;
    wire [2:0] engine_awsize_w;
    wire [1:0] engine_awburst_w, engine_bresp_w;
    wire engine_awvalid_w, engine_awready_w;
    wire [255:0] engine_wdata_w;
    wire [31:0] engine_wstrb_w;
    wire engine_wlast_w, engine_wvalid_w, engine_wready_w;
    wire engine_bvalid_w, engine_bready_w;

    assign draw_start_o = draw_start_w;
    assign draw_done_o = draw_done_w;
    assign draw_completed_count_o = draw_completed_count_w;
    assign compose_start_o = compose_start_w;
    assign compose_done_o = compose_done_w;

    edrv32_render_frame_ctrl #(
        .FRONT_BASE(FRONT_BASE),
        .TARGET_BASE0(TARGET_BASE0),
        .TARGET_BASE1(TARGET_BASE1),
        .TARGET_BASE2(TARGET_BASE2)
    ) u_frame_ctrl (
        .clk_i(clk_i), .rst_n_i(rst_n_i),
        .paddr_i(paddr_i), .psel_i(psel_i),
        .penable_i(penable_i), .pwrite_i(pwrite_i),
        .pwdata_i(pwdata_i), .pstrb_i(pstrb_i),
        .pready_o(pready_o), .prdata_o(prdata_o),
        .pslverr_o(pslverr_o), .irq_o(irq_o),
        .base_valid_i(base_valid_i),
        .base_buffer_i(base_buffer_i),
        .base_addr_i(base_addr_i),
        .base_stride_i(base_stride_i),
        .base_release_valid_o(base_release_valid_o),
        .base_release_buffer_o(base_release_buffer_o),
        .display_valid_o(display_valid_o),
        .display_ready_i(display_ready_i),
        .display_token_o(display_token_o),
        .display_base_o(display_base_o),
        .display_retire_valid_i(display_retire_valid_i),
        .display_retire_token_i(display_retire_token_i),
        .draw_start_o(draw_start_w),
        .draw_ready_i(draw_ready_w),
        .draw_list_base_o(draw_list_base_w),
        .draw_list_count_o(draw_list_count_w),
        .draw_done_i(draw_done_w),
        .draw_error_i(draw_error_w),
        .compose_start_o(compose_start_w),
        .compose_ready_i(compose_ready_w),
        .compose_base_o(compose_base_w),
        .compose_base_stride_o(compose_base_stride_w),
        .compose_front_o(compose_front_w),
        .compose_front_stride_o(compose_front_stride_w),
        .compose_target_o(compose_target_w),
        .compose_target_stride_o(compose_target_stride_w),
        .compose_width_o(compose_width_w),
        .compose_height_o(compose_height_w),
        .compose_done_i(compose_done_w),
        .compose_error_i(compose_error_w)
    );

    edrv32_render_engine u_engine (
        .clk_i(clk_i), .rst_n_i(rst_n_i),
        .start_i(draw_start_w), .start_ready_o(draw_ready_w),
        .list_base_i(draw_list_base_w),
        .list_count_i(draw_list_count_w),
        .busy_o(), .draw_active_o(draw_active_w),
        .compose_direct_active_o(compose_direct_active_w),
        .compose_direct_target_base_o(compose_direct_target_base_w),
        .done_o(draw_done_w),
        .error_o(draw_error_w),
        .completed_count_o(draw_completed_count_w),
        .compose_direct_start_i(compose_start_w),
        .compose_direct_ready_o(compose_ready_w),
        .compose_direct_base_i(compose_base_w),
        .compose_direct_base_stride_i(compose_base_stride_w),
        .compose_direct_front_i(compose_front_w),
        .compose_direct_front_stride_i(compose_front_stride_w),
        .compose_direct_target_i(compose_target_w),
        .compose_direct_target_stride_i(compose_target_stride_w),
        .compose_direct_width_i(compose_width_w),
        .compose_direct_height_i(compose_height_w),
        .compose_direct_done_o(compose_done_w),
        .compose_direct_error_o(compose_error_w),
        .m_arid_o(m_arid_o), .m_araddr_o(m_araddr_o),
        .m_arlen_o(m_arlen_o), .m_arsize_o(m_arsize_o),
        .m_arburst_o(m_arburst_o), .m_arqos_o(m_arqos_o),
        .m_arvalid_o(m_arvalid_o), .m_arready_i(m_arready_i),
        .m_rid_i(m_rid_i), .m_rdata_i(m_rdata_i),
        .m_rresp_i(m_rresp_i), .m_rlast_i(m_rlast_i),
        .m_rvalid_i(m_rvalid_i), .m_rready_o(m_rready_o),
        .m_awid_o(engine_awid_w), .m_awaddr_o(engine_awaddr_w),
        .m_awlen_o(engine_awlen_w), .m_awsize_o(engine_awsize_w),
        .m_awburst_o(engine_awburst_w), .m_awqos_o(engine_awqos_w),
        .m_awvalid_o(engine_awvalid_w),
        .m_awready_i(engine_awready_w),
        .m_wdata_o(engine_wdata_w), .m_wstrb_o(engine_wstrb_w),
        .m_wlast_o(engine_wlast_w), .m_wvalid_o(engine_wvalid_w),
        .m_wready_i(engine_wready_w),
        .m_bid_i(engine_bid_w), .m_bresp_i(engine_bresp_w),
        .m_bvalid_i(engine_bvalid_w), .m_bready_o(engine_bready_w)
    );

    edrv32_render_write_guard #(
        .TARGET_BASE0(TARGET_BASE0),
        .TARGET_BASE1(TARGET_BASE1),
        .TARGET_BASE2(TARGET_BASE2),
        .TARGET_SLOT_BYTES(TARGET_SLOT_BYTES)
    ) u_write_guard (
        .clk_i(clk_i), .rst_n_i(rst_n_i),
        .draw_active_i(draw_active_w),
        .compose_direct_active_i(compose_direct_active_w),
        .compose_direct_target_base_i(compose_direct_target_base_w),
        .s_awid_i(engine_awid_w), .s_awaddr_i(engine_awaddr_w),
        .s_awlen_i(engine_awlen_w), .s_awsize_i(engine_awsize_w),
        .s_awburst_i(engine_awburst_w), .s_awqos_i(engine_awqos_w),
        .s_awvalid_i(engine_awvalid_w),
        .s_awready_o(engine_awready_w),
        .s_wdata_i(engine_wdata_w), .s_wstrb_i(engine_wstrb_w),
        .s_wlast_i(engine_wlast_w), .s_wvalid_i(engine_wvalid_w),
        .s_wready_o(engine_wready_w),
        .s_bid_o(engine_bid_w), .s_bresp_o(engine_bresp_w),
        .s_bvalid_o(engine_bvalid_w), .s_bready_i(engine_bready_w),
        .m_awid_o(m_awid_o), .m_awaddr_o(m_awaddr_o),
        .m_awlen_o(m_awlen_o), .m_awsize_o(m_awsize_o),
        .m_awburst_o(m_awburst_o), .m_awqos_o(m_awqos_o),
        .m_awvalid_o(m_awvalid_o), .m_awready_i(m_awready_i),
        .m_wdata_o(m_wdata_o), .m_wstrb_o(m_wstrb_o),
        .m_wlast_o(m_wlast_o), .m_wvalid_o(m_wvalid_o),
        .m_wready_i(m_wready_i),
        .m_bid_i(m_bid_i), .m_bresp_i(m_bresp_i),
        .m_bvalid_i(m_bvalid_i), .m_bready_o(m_bready_o)
    );

endmodule
