// ============================================================================
// File        : edrv32_render_system_parallel.v
// Description : Separate draw and compose engines behind one 256-bit AXI port.
// Notes       : Display tokens encode target(1)/bypass base(0) in bit 2.
// ============================================================================

module edrv32_render_system_parallel #(
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
    wire compose_busy_w;
    reg [31:0] compose_target_r;
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
    wire [3:0] compose_awid_w, compose_awqos_w, compose_bid_w;
    wire [31:0] compose_awaddr_w;
    wire [7:0] compose_awlen_w;
    wire [2:0] compose_awsize_w;
    wire [1:0] compose_awburst_w, compose_bresp_w;
    wire compose_awvalid_w, compose_awready_w;
    wire [255:0] compose_wdata_w;
    wire [31:0] compose_wstrb_w;
    wire compose_wlast_w, compose_wvalid_w, compose_wready_w;
    wire compose_bvalid_w, compose_bready_w;
    wire [7:0] awid_w, arid_w, bid_w, rid_w;
    wire [63:0] awaddr_w, araddr_w;
    wire [15:0] awlen_w, arlen_w;
    wire [5:0] awsize_w, arsize_w;
    wire [3:0] awburst_w, arburst_w;
    wire [7:0] awqos_w, arqos_w;
    wire [1:0] awvalid_w, awready_w;
    wire [1:0] wlast_w, wvalid_w, wready_w;
    wire [1:0] bvalid_w, bready_w;
    wire [1:0] arvalid_w, arready_w;
    wire [1:0] rlast_w, rvalid_w, rready_w;
    wire [511:0] wdata_w, rdata_w;
    wire [63:0] wstrb_w;
    wire [3:0] bresp_w, rresp_w;
    wire [9:0] unused_read_outstanding_w;
    wire [9:0] unused_write_outstanding_w;
    wire unused_read_protocol_error_w;
    wire unused_write_protocol_error_w;
    wire unused_write_owner_valid_w;
    wire unused_write_owner_w;

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i)
            compose_target_r <= 32'd0;
        else if (compose_start_w && compose_ready_w)
            compose_target_r <= compose_target_w;
    end

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

    edrv32_render_engine #(.ENABLE_CMD_COMPOSE(0)) u_engine (
        .clk_i(clk_i), .rst_n_i(rst_n_i),
        .start_i(draw_start_w), .start_ready_o(draw_ready_w),
        .list_base_i(draw_list_base_w),
        .list_count_i(draw_list_count_w),
        .busy_o(), .draw_active_o(draw_active_w),
        .compose_direct_active_o(),
        .compose_direct_target_base_o(),
        .done_o(draw_done_w),
        .error_o(draw_error_w),
        .completed_count_o(draw_completed_count_w),
        .compose_direct_start_i(1'b0),
        .compose_direct_ready_o(),
        .compose_direct_base_i(32'd0),
        .compose_direct_base_stride_i(32'd0),
        .compose_direct_front_i(32'd0),
        .compose_direct_front_stride_i(32'd0),
        .compose_direct_target_i(32'd0),
        .compose_direct_target_stride_i(32'd0),
        .compose_direct_width_i(16'd0),
        .compose_direct_height_i(16'd0),
        .compose_direct_done_o(),
        .compose_direct_error_o(),
        .m_arid_o(arid_w[3:0]), .m_araddr_o(araddr_w[31:0]),
        .m_arlen_o(arlen_w[7:0]), .m_arsize_o(arsize_w[2:0]),
        .m_arburst_o(arburst_w[1:0]), .m_arqos_o(arqos_w[3:0]),
        .m_arvalid_o(arvalid_w[0]), .m_arready_i(arready_w[0]),
        .m_rid_i(rid_w[3:0]), .m_rdata_i(rdata_w[255:0]),
        .m_rresp_i(rresp_w[1:0]), .m_rlast_i(rlast_w[0]),
        .m_rvalid_i(rvalid_w[0]), .m_rready_o(rready_w[0]),
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

    edrv32_render_compose_engine u_compose (
        .clk_i(clk_i), .rst_n_i(rst_n_i),
        .start_i(compose_start_w), .start_ready_o(compose_ready_w),
        .base_addr_i(compose_base_w),
        .base_stride_i(compose_base_stride_w),
        .front_addr_i(compose_front_w),
        .front_stride_i(compose_front_stride_w),
        .target_addr_i(compose_target_w),
        .target_stride_i(compose_target_stride_w),
        .width_i(compose_width_w), .height_i(compose_height_w),
        .busy_o(compose_busy_w), .done_o(compose_done_w),
        .error_o(compose_error_w),
        .m_arid_o(arid_w[7:4]), .m_araddr_o(araddr_w[63:32]),
        .m_arlen_o(arlen_w[15:8]), .m_arsize_o(arsize_w[5:3]),
        .m_arburst_o(arburst_w[3:2]), .m_arqos_o(arqos_w[7:4]),
        .m_arvalid_o(arvalid_w[1]), .m_arready_i(arready_w[1]),
        .m_rid_i(rid_w[7:4]), .m_rdata_i(rdata_w[511:256]),
        .m_rresp_i(rresp_w[3:2]), .m_rlast_i(rlast_w[1]),
        .m_rvalid_i(rvalid_w[1]), .m_rready_o(rready_w[1]),
        .m_awid_o(compose_awid_w), .m_awaddr_o(compose_awaddr_w),
        .m_awlen_o(compose_awlen_w), .m_awsize_o(compose_awsize_w),
        .m_awburst_o(compose_awburst_w),
        .m_awqos_o(compose_awqos_w),
        .m_awvalid_o(compose_awvalid_w),
        .m_awready_i(compose_awready_w),
        .m_wdata_o(compose_wdata_w), .m_wstrb_o(compose_wstrb_w),
        .m_wlast_o(compose_wlast_w), .m_wvalid_o(compose_wvalid_w),
        .m_wready_i(compose_wready_w),
        .m_bid_i(compose_bid_w), .m_bresp_i(compose_bresp_w),
        .m_bvalid_i(compose_bvalid_w),
        .m_bready_o(compose_bready_w)
    );

    edrv32_render_write_guard #(
        .TARGET_BASE0(TARGET_BASE0),
        .TARGET_BASE1(TARGET_BASE1),
        .TARGET_BASE2(TARGET_BASE2),
        .TARGET_SLOT_BYTES(TARGET_SLOT_BYTES)
    ) u_draw_write_guard (
        .clk_i(clk_i), .rst_n_i(rst_n_i),
        .draw_active_i(draw_active_w),
        .compose_direct_active_i(1'b0),
        .compose_direct_target_base_i(32'd0),
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
        .m_awid_o(awid_w[3:0]), .m_awaddr_o(awaddr_w[31:0]),
        .m_awlen_o(awlen_w[7:0]), .m_awsize_o(awsize_w[2:0]),
        .m_awburst_o(awburst_w[1:0]), .m_awqos_o(awqos_w[3:0]),
        .m_awvalid_o(awvalid_w[0]), .m_awready_i(awready_w[0]),
        .m_wdata_o(wdata_w[255:0]), .m_wstrb_o(wstrb_w[31:0]),
        .m_wlast_o(wlast_w[0]), .m_wvalid_o(wvalid_w[0]),
        .m_wready_i(wready_w[0]),
        .m_bid_i(bid_w[3:0]), .m_bresp_i(bresp_w[1:0]),
        .m_bvalid_i(bvalid_w[0]), .m_bready_o(bready_w[0])
    );

    edrv32_render_write_guard #(
        .TARGET_BASE0(TARGET_BASE0),
        .TARGET_BASE1(TARGET_BASE1),
        .TARGET_BASE2(TARGET_BASE2),
        .TARGET_SLOT_BYTES(TARGET_SLOT_BYTES)
    ) u_compose_write_guard (
        .clk_i(clk_i), .rst_n_i(rst_n_i),
        .draw_active_i(1'b0),
        .compose_direct_active_i(compose_busy_w),
        .compose_direct_target_base_i(compose_target_r),
        .s_awid_i(compose_awid_w), .s_awaddr_i(compose_awaddr_w),
        .s_awlen_i(compose_awlen_w),
        .s_awsize_i(compose_awsize_w),
        .s_awburst_i(compose_awburst_w),
        .s_awqos_i(compose_awqos_w),
        .s_awvalid_i(compose_awvalid_w),
        .s_awready_o(compose_awready_w),
        .s_wdata_i(compose_wdata_w),
        .s_wstrb_i(compose_wstrb_w),
        .s_wlast_i(compose_wlast_w),
        .s_wvalid_i(compose_wvalid_w),
        .s_wready_o(compose_wready_w),
        .s_bid_o(compose_bid_w), .s_bresp_o(compose_bresp_w),
        .s_bvalid_o(compose_bvalid_w),
        .s_bready_i(compose_bready_w),
        .m_awid_o(awid_w[7:4]), .m_awaddr_o(awaddr_w[63:32]),
        .m_awlen_o(awlen_w[15:8]), .m_awsize_o(awsize_w[5:3]),
        .m_awburst_o(awburst_w[3:2]), .m_awqos_o(awqos_w[7:4]),
        .m_awvalid_o(awvalid_w[1]), .m_awready_i(awready_w[1]),
        .m_wdata_o(wdata_w[511:256]),
        .m_wstrb_o(wstrb_w[63:32]),
        .m_wlast_o(wlast_w[1]), .m_wvalid_o(wvalid_w[1]),
        .m_wready_i(wready_w[1]),
        .m_bid_i(bid_w[7:4]), .m_bresp_i(bresp_w[3:2]),
        .m_bvalid_i(bvalid_w[1]), .m_bready_o(bready_w[1])
    );

    // Both ingress address channels are registered by this fabric. Read and
    // write arbitration are independent, with finite per-client credit.
    edrv32_axi_m2s_interconnect #(
        .NUM_M(2), .WR_ORDER_DEPTH(8), .STARVE_CYCLES(64),
        .INGRESS_READY_BYPASS(0)
    ) u_memory_scheduler (
        .clk_i(clk_i), .rst_n_i(rst_n_i), .accept_i(1'b1),
        .m_awid_i(awid_w), .m_awaddr_i(awaddr_w),
        .m_awlen_i(awlen_w), .m_awsize_i(awsize_w),
        .m_awburst_i(awburst_w), .m_awqos_i(awqos_w),
        .m_awvalid_i(awvalid_w), .m_awready_o(awready_w),
        .m_wdata_i(wdata_w), .m_wstrb_i(wstrb_w),
        .m_wlast_i(wlast_w), .m_wvalid_i(wvalid_w),
        .m_wready_o(wready_w),
        .m_bid_o(bid_w), .m_bresp_o(bresp_w),
        .m_bvalid_o(bvalid_w), .m_bready_i(bready_w),
        .m_arid_i(arid_w), .m_araddr_i(araddr_w),
        .m_arlen_i(arlen_w), .m_arsize_i(arsize_w),
        .m_arburst_i(arburst_w), .m_arqos_i(arqos_w),
        .m_arvalid_i(arvalid_w), .m_arready_o(arready_w),
        .m_rid_o(rid_w), .m_rdata_o(rdata_w),
        .m_rresp_o(rresp_w), .m_rlast_o(rlast_w),
        .m_rvalid_o(rvalid_w), .m_rready_i(rready_w),
        .m_read_urgent_i(2'b00),
        .m_write_urgent_i(2'b00),
        .m_read_weight_i({4'd8, 4'd4}),
        .m_write_weight_i({4'd8, 4'd4}),
        .m_read_credit_i({5'd4, 5'd4}),
        .m_write_credit_i({5'd4, 5'd4}),
        .s_awid_o(m_awid_o), .s_awaddr_o(m_awaddr_o),
        .s_awlen_o(m_awlen_o), .s_awsize_o(m_awsize_o),
        .s_awburst_o(m_awburst_o), .s_awqos_o(m_awqos_o),
        .s_awvalid_o(m_awvalid_o), .s_awready_i(m_awready_i),
        .s_wdata_o(m_wdata_o), .s_wstrb_o(m_wstrb_o),
        .s_wlast_o(m_wlast_o), .s_wvalid_o(m_wvalid_o),
        .s_wready_i(m_wready_i),
        .s_bid_i(m_bid_i), .s_bresp_i(m_bresp_i),
        .s_bvalid_i(m_bvalid_i), .s_bready_o(m_bready_o),
        .s_arid_o(m_arid_o), .s_araddr_o(m_araddr_o),
        .s_arlen_o(m_arlen_o), .s_arsize_o(m_arsize_o),
        .s_arburst_o(m_arburst_o), .s_arqos_o(m_arqos_o),
        .s_arvalid_o(m_arvalid_o), .s_arready_i(m_arready_i),
        .s_rid_i(m_rid_i), .s_rdata_i(m_rdata_i),
        .s_rresp_i(m_rresp_i), .s_rlast_i(m_rlast_i),
        .s_rvalid_i(m_rvalid_i), .s_rready_o(m_rready_o),
        .read_outstanding_o(unused_read_outstanding_w),
        .write_outstanding_o(unused_write_outstanding_w),
        .read_protocol_error_o(unused_read_protocol_error_w),
        .write_protocol_error_o(unused_write_protocol_error_w),
        .write_owner_valid_o(unused_write_owner_valid_w),
        .write_owner_o(unused_write_owner_w)
    );

endmodule
