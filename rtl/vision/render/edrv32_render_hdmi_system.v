// ============================================================================
// File        : edrv32_render_hdmi_system.v
// Description : Renderer, HDMI scanout and shared 256-bit AXI DDR fabric.
// Notes       : APB and incoming base-frame handshake use the DDR clock.
//               Display read urgency comes from the HDMI FIFO watermark.
// ============================================================================

module edrv32_render_hdmi_system #(
    parameter integer H_ACTIVE = 1280,
    parameter integer H_FP = 110,
    parameter integer H_SYNC = 40,
    parameter integer H_BP = 220,
    parameter integer V_ACTIVE = 720,
    parameter integer V_FP = 5,
    parameter integer V_SYNC = 5,
    parameter integer V_BP = 20,
    parameter integer BURST_BEATS = 16,
    parameter integer PREFILL_BEATS = 160,
    parameter integer SPLIT_AXI = 0,
    parameter [31:0] FRONT_BASE = 32'h0300_0000,
    parameter [31:0] TARGET_BASE0 = 32'h0200_0000,
    parameter [31:0] TARGET_BASE1 = 32'h0220_0000,
    parameter [31:0] TARGET_BASE2 = 32'h0240_0000,
    parameter [31:0] TARGET_SLOT_BYTES = 32'h0020_0000
) (
    input  wire         ddr_clk_i,
    input  wire         ddr_rst_n_i,
    input  wire         ddr_ready_i,
    input  wire         pixel_clk_i,
    input  wire         pixel_rst_n_i,
    input  wire         serial_clk_i,
    input  wire         serial_rst_n_i,
    input  wire         display_enable_i,

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
    output wire [31:0]  render_read_beats_o,
    output wire [31:0]  render_write_beats_o,
    output wire [31:0]  display_read_beats_o,
    output wire [31:0]  render_ar_wait_o,
    output wire [31:0]  render_aw_wait_o,
    output wire [31:0]  display_ar_wait_o,

    input  wire         base_valid_i,
    input  wire [1:0]   base_buffer_i,
    input  wire [31:0]  base_addr_i,
    input  wire [31:0]  base_stride_i,
    output wire         base_release_valid_o,
    output wire [1:0]   base_release_buffer_o,

    output wire [23:0]  rgb_o,
    output wire         hs_o,
    output wire         vs_o,
    output wire         de_o,
    output wire         tmds_clk_p_o,
    output wire         tmds_clk_n_o,
    output wire [2:0]   tmds_data_p_o,
    output wire [2:0]   tmds_data_n_o,
    output wire [31:0]  reader_frame_count_o,
    output wire [31:0]  scanout_frame_count_o,
    output wire [31:0]  underflow_count_o,
    output wire         reader_error_o,
    output wire         fabric_error_o,

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
    output wire         m_bready_o,

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

    output wire         display_read_urgent_o,
    output wire [3:0]   display_arid_o,
    output wire [31:0]  display_araddr_o,
    output wire [7:0]   display_arlen_o,
    output wire [2:0]   display_arsize_o,
    output wire [1:0]   display_arburst_o,
    output wire [3:0]   display_arqos_o,
    output wire         display_arvalid_o,
    input  wire         display_arready_i,
    input  wire [3:0]   display_rid_i,
    input  wire [255:0] display_rdata_i,
    input  wire [1:0]   display_rresp_i,
    input  wire         display_rlast_i,
    input  wire         display_rvalid_i,
    output wire         display_rready_o
);

    wire [7:0]   awid_w, arid_w, bid_w, rid_w;
    wire [63:0]  awaddr_w, araddr_w;
    wire [15:0]  awlen_w, arlen_w;
    wire [5:0]   awsize_w, arsize_w;
    wire [3:0]   awburst_w, arburst_w;
    wire [7:0]   awqos_w, arqos_w;
    wire [1:0]   awvalid_w, awready_w;
    wire [1:0]   wlast_w, wvalid_w, wready_w;
    wire [1:0]   bvalid_w, bready_w;
    wire [1:0]   arvalid_w, arready_w;
    wire [1:0]   rlast_w, rvalid_w, rready_w;
    wire [511:0] wdata_w, rdata_w;
    wire [63:0]  wstrb_w;
    wire [3:0]   bresp_w, rresp_w;
    wire [2:0]   display_token_w, retire_token_w;
    wire [31:0]  display_base_w;
    wire display_valid_w, display_ready_w, retire_valid_w;
    wire read_urgent_w;
    wire read_protocol_error_w, write_protocol_error_w;
    wire [9:0] unused_read_outstanding_w;
    wire [9:0] unused_write_outstanding_w;
    wire unused_write_owner_valid_w;
    wire unused_write_owner_w;
    wire [2:0] unused_active_token_w;
    reg [31:0] render_read_beats_r;
    reg [31:0] render_write_beats_r;
    reg [31:0] display_read_beats_r;
    reg [31:0] render_ar_wait_r;
    reg [31:0] render_aw_wait_r;
    reg [31:0] display_ar_wait_r;

    assign render_read_beats_o = render_read_beats_r;
    assign render_write_beats_o = render_write_beats_r;
    assign display_read_beats_o = display_read_beats_r;
    assign render_ar_wait_o = render_ar_wait_r;
    assign render_aw_wait_o = render_aw_wait_r;
    assign display_ar_wait_o = display_ar_wait_r;
    assign display_read_urgent_o = read_urgent_w;
    assign display_arid_o = arid_w[7:4];
    assign display_araddr_o = araddr_w[63:32];
    assign display_arlen_o = arlen_w[15:8];
    assign display_arsize_o = arsize_w[5:3];
    assign display_arburst_o = arburst_w[3:2];
    assign display_arqos_o = arqos_w[7:4];
    assign display_arvalid_o = arvalid_w[1];
    assign display_rready_o = rready_w[1];

    always @(posedge ddr_clk_i or negedge ddr_rst_n_i) begin
        if (!ddr_rst_n_i) begin
            render_read_beats_r <= 32'd0;
            render_write_beats_r <= 32'd0;
            display_read_beats_r <= 32'd0;
            render_ar_wait_r <= 32'd0;
            render_aw_wait_r <= 32'd0;
            display_ar_wait_r <= 32'd0;
        end else begin
            if (rvalid_w[0] && rready_w[0])
                render_read_beats_r <= render_read_beats_r + 32'd1;
            if (wvalid_w[0] && wready_w[0])
                render_write_beats_r <= render_write_beats_r + 32'd1;
            if (rvalid_w[1] && rready_w[1])
                display_read_beats_r <= display_read_beats_r + 32'd1;
            if (arvalid_w[0] && !arready_w[0])
                render_ar_wait_r <= render_ar_wait_r + 32'd1;
            if (awvalid_w[0] && !awready_w[0])
                render_aw_wait_r <= render_aw_wait_r + 32'd1;
            if (arvalid_w[1] && !arready_w[1])
                display_ar_wait_r <= display_ar_wait_r + 32'd1;
        end
    end

    edrv32_render_system_parallel #(
        .FRONT_BASE(FRONT_BASE),
        .TARGET_BASE0(TARGET_BASE0),
        .TARGET_BASE1(TARGET_BASE1),
        .TARGET_BASE2(TARGET_BASE2),
        .TARGET_SLOT_BYTES(TARGET_SLOT_BYTES)
    ) u_render (
        .clk_i(ddr_clk_i), .rst_n_i(ddr_rst_n_i),
        .paddr_i(paddr_i), .psel_i(psel_i),
        .penable_i(penable_i), .pwrite_i(pwrite_i),
        .pwdata_i(pwdata_i), .pstrb_i(pstrb_i),
        .pready_o(pready_o), .prdata_o(prdata_o),
        .pslverr_o(pslverr_o), .irq_o(irq_o),
        .draw_start_o(draw_start_o),
        .draw_done_o(draw_done_o),
        .draw_completed_count_o(draw_completed_count_o),
        .compose_start_o(compose_start_o),
        .compose_done_o(compose_done_o),
        .base_valid_i(base_valid_i),
        .base_buffer_i(base_buffer_i),
        .base_addr_i(base_addr_i),
        .base_stride_i(base_stride_i),
        .base_release_valid_o(base_release_valid_o),
        .base_release_buffer_o(base_release_buffer_o),
        .display_valid_o(display_valid_w),
        .display_ready_i(display_ready_w),
        .display_token_o(display_token_w),
        .display_base_o(display_base_w),
        .display_retire_valid_i(retire_valid_w),
        .display_retire_token_i(retire_token_w),
        .m_arid_o(arid_w[3:0]),
        .m_araddr_o(araddr_w[31:0]),
        .m_arlen_o(arlen_w[7:0]),
        .m_arsize_o(arsize_w[2:0]),
        .m_arburst_o(arburst_w[1:0]),
        .m_arqos_o(arqos_w[3:0]),
        .m_arvalid_o(arvalid_w[0]),
        .m_arready_i(arready_w[0]),
        .m_rid_i(rid_w[3:0]),
        .m_rdata_i(rdata_w[255:0]),
        .m_rresp_i(rresp_w[1:0]),
        .m_rlast_i(rlast_w[0]),
        .m_rvalid_i(rvalid_w[0]),
        .m_rready_o(rready_w[0]),
        .m_awid_o(awid_w[3:0]),
        .m_awaddr_o(awaddr_w[31:0]),
        .m_awlen_o(awlen_w[7:0]),
        .m_awsize_o(awsize_w[2:0]),
        .m_awburst_o(awburst_w[1:0]),
        .m_awqos_o(awqos_w[3:0]),
        .m_awvalid_o(awvalid_w[0]),
        .m_awready_i(awready_w[0]),
        .m_wdata_o(wdata_w[255:0]),
        .m_wstrb_o(wstrb_w[31:0]),
        .m_wlast_o(wlast_w[0]),
        .m_wvalid_o(wvalid_w[0]),
        .m_wready_i(wready_w[0]),
        .m_bid_i(bid_w[3:0]),
        .m_bresp_i(bresp_w[1:0]),
        .m_bvalid_i(bvalid_w[0]),
        .m_bready_o(bready_w[0])
    );

    edrv32_render_hdmi_display #(
        .H_ACTIVE(H_ACTIVE), .H_FP(H_FP),
        .H_SYNC(H_SYNC), .H_BP(H_BP),
        .V_ACTIVE(V_ACTIVE), .V_FP(V_FP),
        .V_SYNC(V_SYNC), .V_BP(V_BP),
        .BURST_BEATS(BURST_BEATS),
        .PREFILL_BEATS(PREFILL_BEATS)
    ) u_display (
        .ddr_clk_i(ddr_clk_i), .ddr_rst_n_i(ddr_rst_n_i),
        .pixel_clk_i(pixel_clk_i),
        .pixel_rst_n_i(pixel_rst_n_i),
        .serial_clk_i(serial_clk_i),
        .serial_rst_n_i(serial_rst_n_i),
        .display_enable_i(display_enable_i),
        .display_valid_i(display_valid_w),
        .display_ready_o(display_ready_w),
        .display_token_i(display_token_w),
        .display_base_i(display_base_w),
        .display_retire_valid_o(retire_valid_w),
        .display_retire_token_o(retire_token_w),
        .active_token_o(unused_active_token_w),
        .reader_frame_count_o(reader_frame_count_o),
        .scanout_frame_count_o(scanout_frame_count_o),
        .underflow_count_o(underflow_count_o),
        .reader_error_o(reader_error_o),
        .read_urgent_o(read_urgent_w),
        .rgb_o(rgb_o), .hs_o(hs_o),
        .vs_o(vs_o), .de_o(de_o),
        .tmds_clk_p_o(tmds_clk_p_o),
        .tmds_clk_n_o(tmds_clk_n_o),
        .tmds_data_p_o(tmds_data_p_o),
        .tmds_data_n_o(tmds_data_n_o),
        .m_arid_o(arid_w[7:4]),
        .m_araddr_o(araddr_w[63:32]),
        .m_arlen_o(arlen_w[15:8]),
        .m_arsize_o(arsize_w[5:3]),
        .m_arburst_o(arburst_w[3:2]),
        .m_arqos_o(arqos_w[7:4]),
        .m_arvalid_o(arvalid_w[1]),
        .m_arready_i(arready_w[1]),
        .m_rid_i(rid_w[7:4]),
        .m_rdata_i(rdata_w[511:256]),
        .m_rresp_i(rresp_w[3:2]),
        .m_rlast_i(rlast_w[1]),
        .m_rvalid_i(rvalid_w[1]),
        .m_rready_o(rready_w[1])
    );

    assign awid_w[7:4] = 4'd0;
    assign awaddr_w[63:32] = 32'd0;
    assign awlen_w[15:8] = 8'd0;
    assign awsize_w[5:3] = 3'd5;
    assign awburst_w[3:2] = 2'b01;
    assign awqos_w[7:4] = 4'd0;
    assign awvalid_w[1] = 1'b0;
    assign wdata_w[511:256] = 256'd0;
    assign wstrb_w[63:32] = 32'd0;
    assign wlast_w[1] = 1'b0;
    assign wvalid_w[1] = 1'b0;
    assign bready_w[1] = 1'b1;

    generate if (SPLIT_AXI) begin : gen_split_axi
        assign m_awid_o = awid_w[3:0];
        assign m_awaddr_o = awaddr_w[31:0];
        assign m_awlen_o = awlen_w[7:0];
        assign m_awsize_o = awsize_w[2:0];
        assign m_awburst_o = awburst_w[1:0];
        assign m_awqos_o = awqos_w[3:0];
        assign m_awvalid_o = awvalid_w[0];
        assign awready_w[0] = m_awready_i;
        assign m_wdata_o = wdata_w[255:0];
        assign m_wstrb_o = wstrb_w[31:0];
        assign m_wlast_o = wlast_w[0];
        assign m_wvalid_o = wvalid_w[0];
        assign wready_w[0] = m_wready_i;
        assign bid_w[3:0] = m_bid_i;
        assign bresp_w[1:0] = m_bresp_i;
        assign bvalid_w[0] = m_bvalid_i;
        assign m_bready_o = bready_w[0];
        assign m_arid_o = arid_w[3:0];
        assign m_araddr_o = araddr_w[31:0];
        assign m_arlen_o = arlen_w[7:0];
        assign m_arsize_o = arsize_w[2:0];
        assign m_arburst_o = arburst_w[1:0];
        assign m_arqos_o = arqos_w[3:0];
        assign m_arvalid_o = arvalid_w[0];
        assign arready_w[0] = m_arready_i;
        assign rid_w[3:0] = m_rid_i;
        assign rdata_w[255:0] = m_rdata_i;
        assign rresp_w[1:0] = m_rresp_i;
        assign rlast_w[0] = m_rlast_i;
        assign rvalid_w[0] = m_rvalid_i;
        assign m_rready_o = rready_w[0];

        assign arready_w[1] = display_arready_i;
        assign rid_w[7:4] = display_rid_i;
        assign rdata_w[511:256] = display_rdata_i;
        assign rresp_w[3:2] = display_rresp_i;
        assign rlast_w[1] = display_rlast_i;
        assign rvalid_w[1] = display_rvalid_i;
        assign awready_w[1] = 1'b0;
        assign wready_w[1] = 1'b0;
        assign bid_w[7:4] = 4'd0;
        assign bresp_w[3:2] = 2'd0;
        assign bvalid_w[1] = 1'b0;
        assign fabric_error_o = 1'b0;
    end else begin : gen_shared_axi
    edrv32_axi_m2s_interconnect #(
        .NUM_M(2), .WR_ORDER_DEPTH(8),
        .STARVE_CYCLES(64)
    ) u_fabric (
        .clk_i(ddr_clk_i), .rst_n_i(ddr_rst_n_i),
        .accept_i(ddr_ready_i),
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
        .m_read_urgent_i({read_urgent_w,1'b0}),
        .m_write_urgent_i(2'b00),
        .m_read_weight_i({4'd12,4'd3}),
        .m_write_weight_i({4'd1,4'd8}),
        .m_read_credit_i({5'd16,5'd4}),
        .m_write_credit_i({5'd1,5'd8}),
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
        .read_protocol_error_o(read_protocol_error_w),
        .write_protocol_error_o(write_protocol_error_w),
        .write_owner_valid_o(unused_write_owner_valid_w),
        .write_owner_o(unused_write_owner_w)
    );

    assign fabric_error_o = read_protocol_error_w ||
                            write_protocol_error_w;
    end endgenerate

endmodule
