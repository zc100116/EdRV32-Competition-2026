// ============================================================================
// File        : edrv32_render_compose_engine.v
// Description : Independent two-pixel compositor with one AXI master.
// ============================================================================

module edrv32_render_compose_engine (
    input  wire         clk_i,
    input  wire         rst_n_i,
    input  wire         start_i,
    output wire         start_ready_o,
    input  wire [31:0]  base_addr_i,
    input  wire [31:0]  base_stride_i,
    input  wire [31:0]  front_addr_i,
    input  wire [31:0]  front_stride_i,
    input  wire [31:0]  target_addr_i,
    input  wire [31:0]  target_stride_i,
    input  wire [15:0]  width_i,
    input  wire [15:0]  height_i,
    output wire         busy_o,
    output wire         done_o,
    output wire         error_o,

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

    edrv32_render_compose_dma #(
        .EXTERNAL_BLEND(0)
    ) u_dma (
        .clk_i(clk_i), .rst_n_i(rst_n_i),
        .start_i(start_i), .start_ready_o(start_ready_o),
        .base_addr_i(base_addr_i), .base_stride_i(base_stride_i),
        .front_addr_i(front_addr_i), .front_stride_i(front_stride_i),
        .target_addr_i(target_addr_i),
        .target_stride_i(target_stride_i),
        .width_i(width_i), .height_i(height_i),
        .busy_o(busy_o), .done_o(done_o), .error_o(error_o),
        .read_beat_count_o(), .write_beat_count_o(),
        .blend_in_valid_o(), .blend_in_ready_i(1'b0),
        .blend_src_o(), .blend_dst_o(), .blend_opacity_o(),
        .blend_premul_o(), .blend_tag_o(),
        .blend_out_valid_i(1'b0), .blend_out_ready_o(),
        .blend_pixel_i(64'd0),
        .m_arid_o(m_arid_o), .m_araddr_o(m_araddr_o),
        .m_arlen_o(m_arlen_o), .m_arsize_o(m_arsize_o),
        .m_arburst_o(m_arburst_o), .m_arqos_o(m_arqos_o),
        .m_arvalid_o(m_arvalid_o), .m_arready_i(m_arready_i),
        .m_rid_i(m_rid_i), .m_rdata_i(m_rdata_i),
        .m_rresp_i(m_rresp_i), .m_rlast_i(m_rlast_i),
        .m_rvalid_i(m_rvalid_i), .m_rready_o(m_rready_o),
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
