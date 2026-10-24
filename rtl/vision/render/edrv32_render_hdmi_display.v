// ============================================================================
// File        : edrv32_render_hdmi_display.v
// Description : Renderer display-token sink and DDR-to-HDMI scanout chain.
// Notes       : Renderer and reader use the DDR clock. Tokens are retired
//               after the reader finishes its last DDR beat for that frame.
// ============================================================================

module edrv32_render_hdmi_display #(
    parameter integer H_ACTIVE = 1280,
    parameter integer H_FP = 110,
    parameter integer H_SYNC = 40,
    parameter integer H_BP = 220,
    parameter integer V_ACTIVE = 720,
    parameter integer V_FP = 5,
    parameter integer V_SYNC = 5,
    parameter integer V_BP = 20,
    parameter integer BURST_BEATS = 16,
    parameter integer PREFILL_BEATS = 160
) (
    input  wire         ddr_clk_i,
    input  wire         ddr_rst_n_i,
    input  wire         pixel_clk_i,
    input  wire         pixel_rst_n_i,
    input  wire         serial_clk_i,
    input  wire         serial_rst_n_i,
    input  wire         display_enable_i,

    input  wire         display_valid_i,
    output wire         display_ready_o,
    input  wire [2:0]   display_token_i,
    input  wire [31:0]  display_base_i,
    output wire         display_retire_valid_o,
    output wire [2:0]   display_retire_token_o,
    output wire [2:0]   active_token_o,
    output wire [31:0]  reader_frame_count_o,
    output wire [31:0]  scanout_frame_count_o,
    output wire [31:0]  underflow_count_o,
    output wire         reader_error_o,
    output wire         read_urgent_o,

    output wire [23:0]  rgb_o,
    output wire         hs_o,
    output wire         vs_o,
    output wire         de_o,
    output wire         tmds_clk_p_o,
    output wire         tmds_clk_n_o,
    output wire [2:0]   tmds_data_p_o,
    output wire [2:0]   tmds_data_n_o,

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
    output wire         m_rready_o
);

    wire [255:0] fifo_write_data_w;
    wire fifo_write_valid_w;
    wire fifo_write_ready_w;
    wire [255:0] fifo_read_data_w;
    wire fifo_read_valid_w;
    wire fifo_read_ready_w;
    wire reader_prefill_done_w;
    wire unused_reader_active_w;
    wire fifo_almost_empty_w;
    wire [1:0] unused_fifo_local_count_w;
    wire [15:0] unused_scanout_x_w;
    wire [15:0] unused_scanout_y_w;
    reg prefill_meta_r;
    reg prefill_sync_r;
    reg enable_meta_r;
    reg enable_sync_r;
    reg almost_empty_meta_r;
    reg almost_empty_sync_r;

    edrv32_hdmi_axi_reader_pageflip #(
        .H_ACTIVE(H_ACTIVE), .V_ACTIVE(V_ACTIVE),
        .BURST_BEATS(BURST_BEATS),
        .PREFILL_BEATS(PREFILL_BEATS),
        .TOKEN_WIDTH(3), .DISPLAY_HANDSHAKE(1)
    ) u_reader (
        .clk_i(ddr_clk_i), .rst_n_i(ddr_rst_n_i),
        .display_valid_i(display_valid_i),
        .display_ready_o(display_ready_o),
        .display_buffer_i(display_token_i),
        .display_base_i(display_base_i),
        .release_valid_o(display_retire_valid_o),
        .release_buffer_o(display_retire_token_o),
        .active_o(unused_reader_active_w),
        .active_buffer_o(active_token_o),
        .prefill_done_o(reader_prefill_done_w),
        .frame_count_o(reader_frame_count_o),
        .error_o(reader_error_o),
        .m_arid_o(m_arid_o), .m_araddr_o(m_araddr_o),
        .m_arlen_o(m_arlen_o), .m_arsize_o(m_arsize_o),
        .m_arburst_o(m_arburst_o), .m_arqos_o(m_arqos_o),
        .m_arvalid_o(m_arvalid_o), .m_arready_i(m_arready_i),
        .m_rid_i(m_rid_i), .m_rdata_i(m_rdata_i),
        .m_rresp_i(m_rresp_i), .m_rlast_i(m_rlast_i),
        .m_rvalid_i(m_rvalid_i), .m_rready_o(m_rready_o),
        .fifo_data_o(fifo_write_data_w),
        .fifo_valid_o(fifo_write_valid_w),
        .fifo_ready_i(fifo_write_ready_w)
    );

    edrv32_hdmi_fifo u_fifo (
        .wr_clk_i(ddr_clk_i), .wr_rst_n_i(ddr_rst_n_i),
        .wr_data_i(fifo_write_data_w),
        .wr_valid_i(fifo_write_valid_w),
        .wr_ready_o(fifo_write_ready_w),
        .rd_clk_i(pixel_clk_i), .rd_rst_n_i(pixel_rst_n_i),
        .rd_data_o(fifo_read_data_w),
        .rd_valid_o(fifo_read_valid_w),
        .rd_ready_i(fifo_read_ready_w),
        .almost_empty_o(fifo_almost_empty_w),
        .local_count_o(unused_fifo_local_count_w)
    );

    always @(posedge ddr_clk_i or negedge ddr_rst_n_i) begin
        if (!ddr_rst_n_i) begin
            almost_empty_meta_r <= 1'b1;
            almost_empty_sync_r <= 1'b1;
        end else begin
            almost_empty_meta_r <= fifo_almost_empty_w;
            almost_empty_sync_r <= almost_empty_meta_r;
        end
    end

    assign read_urgent_o = almost_empty_sync_r;

    always @(posedge pixel_clk_i or negedge pixel_rst_n_i) begin
        if (!pixel_rst_n_i) begin
            prefill_meta_r <= 1'b0;
            prefill_sync_r <= 1'b0;
            enable_meta_r <= 1'b0;
            enable_sync_r <= 1'b0;
        end else begin
            prefill_meta_r <= reader_prefill_done_w;
            prefill_sync_r <= prefill_meta_r;
            enable_meta_r <= display_enable_i;
            enable_sync_r <= enable_meta_r;
        end
    end

    edrv32_hdmi_scanout #(
        .H_ACTIVE(H_ACTIVE), .H_FP(H_FP),
        .H_SYNC(H_SYNC), .H_BP(H_BP),
        .V_ACTIVE(V_ACTIVE), .V_FP(V_FP),
        .V_SYNC(V_SYNC), .V_BP(V_BP)
    ) u_scanout (
        .clk_i(pixel_clk_i), .rst_n_i(pixel_rst_n_i),
        .enable_i(prefill_sync_r),
        .output_enable_i(enable_sync_r),
        .fifo_data_i(fifo_read_data_w),
        .fifo_valid_i(fifo_read_valid_w),
        .fifo_ready_o(fifo_read_ready_w),
        .rgb_o(rgb_o), .hs_o(hs_o),
        .vs_o(vs_o), .de_o(de_o),
        .active_x_o(unused_scanout_x_w),
        .active_y_o(unused_scanout_y_w),
        .frame_count_o(scanout_frame_count_o),
        .underflow_count_o(underflow_count_o)
    );

    edrv32_tmds_tx u_tmds_tx (
        .pixel_clk_i(pixel_clk_i),
        .serial_clk_i(serial_clk_i),
        .pixel_rst_n_i(pixel_rst_n_i),
        .serial_rst_n_i(serial_rst_n_i),
        .rgb_i(rgb_o), .hs_i(hs_o),
        .vs_i(vs_o), .de_i(de_o),
        .tmds_clk_p_o(tmds_clk_p_o),
        .tmds_clk_n_o(tmds_clk_n_o),
        .tmds_data_p_o(tmds_data_p_o),
        .tmds_data_n_o(tmds_data_n_o)
    );

endmodule
