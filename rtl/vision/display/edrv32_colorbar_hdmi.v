// ============================================================================
// File        : edrv32_colorbar_hdmi.v
// Description : Color-bar framebuffer writer and fixed 720p HDMI scanout loop.
// Notes       : This is the P2 bring-up source. Camera capture replaces the
//               writer in later checkpoints while the read/scanout path stays.
// ============================================================================

module edrv32_colorbar_hdmi #(
    parameter [31:0] FRAME_BASE = 32'h0100_0000
) (
    input  wire         ddr_clk_i,
    input  wire         ddr_rst_n_i,
    input  wire         pixel_clk_i,
    input  wire         pixel_rst_n_i,
    input  wire         serial_clk_i,
    input  wire         serial_rst_n_i,
    input  wire         start_i,

    output wire         writer_done_o,
    output wire         reader_active_o,
    output wire         read_urgent_o,
    output wire         error_o,
    output wire [31:0]  underflow_count_o,

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

    output wire         tmds_clk_p_o,
    output wire         tmds_clk_n_o,
    output wire [2:0]   tmds_data_p_o,
    output wire [2:0]   tmds_data_n_o
);

    wire writer_busy_w;
    wire writer_done_w;
    wire writer_error_w;

    edrv32_colorbar_axi_writer #(
        .H_ACTIVE    (1280),
        .V_ACTIVE    (720),
        .BURST_BEATS (16),
        .FRAME_BASE  (FRAME_BASE),
        .AXI_ID      (4'h0)
    ) u_writer (
        .clk_i       (ddr_clk_i),
        .rst_n_i     (ddr_rst_n_i),
        .start_i     (start_i),
        .busy_o      (writer_busy_w),
        .done_o      (writer_done_w),
        .error_o     (writer_error_w),
        .m_awid_o    (m_awid_o),
        .m_awaddr_o  (m_awaddr_o),
        .m_awlen_o   (m_awlen_o),
        .m_awsize_o  (m_awsize_o),
        .m_awburst_o (m_awburst_o),
        .m_awqos_o   (m_awqos_o),
        .m_awvalid_o (m_awvalid_o),
        .m_awready_i (m_awready_i),
        .m_wdata_o   (m_wdata_o),
        .m_wstrb_o   (m_wstrb_o),
        .m_wlast_o   (m_wlast_o),
        .m_wvalid_o  (m_wvalid_o),
        .m_wready_i  (m_wready_i),
        .m_bid_i     (m_bid_i),
        .m_bresp_i   (m_bresp_i),
        .m_bvalid_i  (m_bvalid_i),
        .m_bready_o  (m_bready_o)
    );

    wire reader_prefill_done_w;
    wire [31:0] unused_reader_frame_count_w;
    wire reader_error_w;
    wire [255:0] fifo_write_data_w;
    wire fifo_write_valid_w;
    wire fifo_write_ready_w;

    edrv32_hdmi_axi_reader #(
        .H_ACTIVE     (1280),
        .V_ACTIVE     (720),
        .BURST_BEATS  (16),
        .PREFILL_BEATS(160),
        .FRAME_BASE   (FRAME_BASE),
        .AXI_ID       (4'h0)
    ) u_reader (
        .clk_i          (ddr_clk_i),
        .rst_n_i        (ddr_rst_n_i),
        .start_i        (writer_done_w && !writer_error_w),
        .active_o       (reader_active_o),
        .prefill_done_o (reader_prefill_done_w),
        .frame_count_o  (unused_reader_frame_count_w),
        .error_o        (reader_error_w),
        .m_arid_o       (m_arid_o),
        .m_araddr_o     (m_araddr_o),
        .m_arlen_o      (m_arlen_o),
        .m_arsize_o     (m_arsize_o),
        .m_arburst_o    (m_arburst_o),
        .m_arqos_o      (m_arqos_o),
        .m_arvalid_o    (m_arvalid_o),
        .m_arready_i    (m_arready_i),
        .m_rid_i        (m_rid_i),
        .m_rdata_i      (m_rdata_i),
        .m_rresp_i      (m_rresp_i),
        .m_rlast_i      (m_rlast_i),
        .m_rvalid_i     (m_rvalid_i),
        .m_rready_o     (m_rready_o),
        .fifo_data_o    (fifo_write_data_w),
        .fifo_valid_o   (fifo_write_valid_w),
        .fifo_ready_i   (fifo_write_ready_w)
    );

    wire [255:0] fifo_read_data_w;
    wire fifo_read_valid_w;
    wire fifo_read_ready_w;
    wire fifo_almost_empty_w;
    wire [1:0] unused_fifo_local_count_w;

    edrv32_hdmi_fifo u_fifo (
        .wr_clk_i       (ddr_clk_i),
        .wr_rst_n_i     (ddr_rst_n_i),
        .wr_data_i      (fifo_write_data_w),
        .wr_valid_i     (fifo_write_valid_w),
        .wr_ready_o     (fifo_write_ready_w),
        .rd_clk_i       (pixel_clk_i),
        .rd_rst_n_i     (pixel_rst_n_i),
        .rd_data_o      (fifo_read_data_w),
        .rd_valid_o     (fifo_read_valid_w),
        .rd_ready_i     (fifo_read_ready_w),
        .almost_empty_o (fifo_almost_empty_w),
        .local_count_o  (unused_fifo_local_count_w)
    );

    reg prefill_meta_r;
    reg prefill_sync_r;
    always @(posedge pixel_clk_i or negedge pixel_rst_n_i) begin
        if (!pixel_rst_n_i) begin
            prefill_meta_r <= 1'b0;
            prefill_sync_r <= 1'b0;
        end else begin
            prefill_meta_r <= reader_prefill_done_w;
            prefill_sync_r <= prefill_meta_r;
        end
    end

    reg almost_empty_meta_r;
    reg almost_empty_sync_r;
    always @(posedge ddr_clk_i or negedge ddr_rst_n_i) begin
        if (!ddr_rst_n_i) begin
            almost_empty_meta_r <= 1'b1;
            almost_empty_sync_r <= 1'b1;
        end else begin
            almost_empty_meta_r <= fifo_almost_empty_w;
            almost_empty_sync_r <= almost_empty_meta_r;
        end
    end

    wire [23:0] scanout_rgb_w;
    wire scanout_hs_w;
    wire scanout_vs_w;
    wire scanout_de_w;
    wire [15:0] unused_active_x_w;
    wire [15:0] unused_active_y_w;
    wire [31:0] unused_scanout_frame_count_w;
    wire [31:0] scanout_underflow_count_w;

    edrv32_hdmi_scanout u_scanout (
        .clk_i             (pixel_clk_i),
        .rst_n_i           (pixel_rst_n_i),
        .enable_i          (prefill_sync_r),
        .output_enable_i   (1'b1),
        .fifo_data_i       (fifo_read_data_w),
        .fifo_valid_i      (fifo_read_valid_w),
        .fifo_ready_o      (fifo_read_ready_w),
        .rgb_o             (scanout_rgb_w),
        .hs_o              (scanout_hs_w),
        .vs_o              (scanout_vs_w),
        .de_o              (scanout_de_w),
        .active_x_o        (unused_active_x_w),
        .active_y_o        (unused_active_y_w),
        .frame_count_o     (unused_scanout_frame_count_w),
        .underflow_count_o (scanout_underflow_count_w)
    );

    reg underflow_meta_r;
    reg underflow_sync_r;
    always @(posedge ddr_clk_i or negedge ddr_rst_n_i) begin
        if (!ddr_rst_n_i) begin
            underflow_meta_r <= 1'b0;
            underflow_sync_r <= 1'b0;
        end else begin
            underflow_meta_r <= |scanout_underflow_count_w;
            underflow_sync_r <= underflow_meta_r;
        end
    end

    edrv32_tmds_tx u_tmds_tx (
        .pixel_clk_i   (pixel_clk_i),
        .serial_clk_i  (serial_clk_i),
        .pixel_rst_n_i (pixel_rst_n_i),
        .serial_rst_n_i(serial_rst_n_i),
        .rgb_i         (scanout_rgb_w),
        .hs_i          (scanout_hs_w),
        .vs_i          (scanout_vs_w),
        .de_i          (scanout_de_w),
        .tmds_clk_p_o  (tmds_clk_p_o),
        .tmds_clk_n_o  (tmds_clk_n_o),
        .tmds_data_p_o (tmds_data_p_o),
        .tmds_data_n_o (tmds_data_n_o)
    );

    assign writer_done_o = writer_done_w;
    assign read_urgent_o = almost_empty_sync_r;
    assign error_o = writer_error_w || reader_error_w || underflow_sync_r;
    assign underflow_count_o = scanout_underflow_count_w;
    wire unused_writer_busy_w = writer_busy_w;

endmodule
