// ============================================================================
// File        : edrv32_stereo_hdmi.v
// Description : Dual OV5640 stream selection, DDR display DMA and HDMI output.
// Notes       : Camera selection occurs before the display writer. HDMI scans
//               only completed triple-buffered display surfaces.
// ============================================================================

module edrv32_stereo_hdmi #(
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
    parameter integer CAMERA_FIFO_ADDR_W = 10,
    parameter integer CAMERA_DISCARD_FRAMES = 2,
    parameter integer TELEMETRY_ENABLE = 0,
    parameter integer TELEMETRY_CLK_HZ = 125000000,
    parameter integer BUTTON_DEBOUNCE_CYCLES = 540000,
    parameter integer INIT_RESET_CYCLES = 65536,
    parameter integer INIT_SETTLE_CYCLES = 1048576,
    parameter integer INIT_REG_COUNT = 248,
    parameter INIT_ROM_FILE = "rtl/vision/camera/ov5640_720p.hex",
    parameter [31:0] DISPLAY_BASE0 = 32'h0180_0000,
    parameter [31:0] DISPLAY_BASE1 = 32'h01a0_0000,
    parameter [31:0] DISPLAY_BASE2 = 32'h01c0_0000,
    parameter [31:0] GEOMETRY_BASE0 = 32'h0200_0000,
    parameter [31:0] GEOMETRY_BASE1 = 32'h0220_0000,
    parameter [31:0] GEOMETRY_BASE2 = 32'h0240_0000
) (
    input  wire         ctrl_clk_i,
    input  wire         ctrl_rst_n_i,
    input  wire         ddr_clk_i,
    input  wire         ddr_rst_n_i,
    input  wire         pixel_clk_i,
    input  wire         pixel_rst_n_i,
    input  wire         serial_clk_i,
    input  wire         serial_rst_n_i,
    input  wire         enable_i,
    input  wire         select_button_n_i,
    input  wire         cam0_enable_i,
    input  wire         cam1_enable_i,
    input  wire         display_enable_i,
    input  wire         cfg_req_toggle_i,
    input  wire         cfg_camera_i,
    input  wire         cfg_read_i,
    input  wire [15:0]  cfg_reg_addr_i,
    input  wire [7:0]   cfg_write_data_i,
    output wire         cfg_ack_toggle_o,
    output wire         cfg_error_o,
    output wire [7:0]   cfg_read_data_o,

    input  wire         pixel_cfg_req_toggle_i,
    input  wire         pixel_cfg_enable_i,
    input  wire         pixel_cfg_grayscale_i,
    input  wire         pixel_cfg_threshold_enable_i,
    input  wire         pixel_cfg_invert_i,
    input  wire signed [8:0] pixel_cfg_brightness_i,
    input  wire [8:0]   pixel_cfg_contrast_i,
    input  wire [7:0]   pixel_cfg_threshold_i,
    input  wire         pixel_cfg_spatial_enable_i,
    input  wire [2:0]   pixel_cfg_spatial_mode_i,
    input  wire [7:0]   pixel_cfg_spatial_threshold_i,
    output wire         pixel_cfg_ack_toggle_o,
    input  wire [4:0]   geometry_mode_i,
    input  wire         geometry_cfg_req_toggle_i,
    input  wire         geometry_image_override_i,
    input  wire [15:0]  geometry_image_width_i,
    input  wire [15:0]  geometry_image_height_i,
    input  wire         geometry_angle_override_i,
    input  wire [8:0]   geometry_angle_i,

    input  wire         cam0_pclk_i,
    input  wire [7:0]   cam0_data_i,
    input  wire         cam0_href_i,
    input  wire         cam0_vsync_i,
    output wire         cam0_scl_o,
    inout  wire         cam0_sda_io,
    output wire         cam0_rst_n_o,

    input  wire         cam1_pclk_i,
    input  wire [7:0]   cam1_data_i,
    input  wire         cam1_href_i,
    input  wire         cam1_vsync_i,
    output wire         cam1_scl_o,
    inout  wire         cam1_sda_io,
    output wire         cam1_rst_n_o,

    output wire         selected_camera_o,
    output wire         cam0_init_done_o,
    output wire         cam1_init_done_o,
    output wire [1:0]   display_active_buffer_o,
    output wire [31:0]  cam0_frame_count_o,
    output wire [31:0]  cam1_frame_count_o,
    output wire [31:0]  display_frame_count_o,
    output wire [31:0]  pixel_frame_count_o,
    output wire [31:0]  underflow_count_o,
    output wire         reader_prefill_done_o,
    output wire         hdmi_fifo_read_valid_o,
    output wire [1:0]   hdmi_fifo_local_count_o,
    output wire [31:0]  scanout_frame_count_o,
    output wire         read_urgent_o,
    output wire         write_urgent_o,
    output wire         camera_error_o,
    output wire         display_error_o,
    output wire         error_o,
    output wire         telemetry_tx_o,

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

    localparam integer NUM_M = 4;
    localparam integer SURFACE_STRIDE = H_ACTIVE * 2;
    localparam [15:0] H_ACTIVE_16 = H_ACTIVE;
    localparam [15:0] V_ACTIVE_16 = V_ACTIVE;

    wire cam0_init_done_w;
    wire cam1_init_done_w;
    wire init_error_w;
    wire cam0_sda_drive_low_w;
    wire cam1_sda_drive_low_w;

    assign cam0_sda_io = cam0_sda_drive_low_w ? 1'b0 : 1'bz;
    assign cam1_sda_io = cam1_sda_drive_low_w ? 1'b0 : 1'bz;

    edrv32_ov5640_stereo_init #(
        .RESET_CYCLES (INIT_RESET_CYCLES),
        .SETTLE_CYCLES(INIT_SETTLE_CYCLES),
        .REG_COUNT     (INIT_REG_COUNT),
        .ROM_INIT_FILE (INIT_ROM_FILE)
    ) u_camera_init (
        .clk_i            (ctrl_clk_i),
        .rst_n_i          (ctrl_rst_n_i),
        .cfg_req_toggle_i (cfg_req_toggle_i),
        .cfg_camera_i     (cfg_camera_i),
        .cfg_read_i       (cfg_read_i),
        .cfg_reg_addr_i   (cfg_reg_addr_i),
        .cfg_write_data_i (cfg_write_data_i),
        .cfg_ack_toggle_o (cfg_ack_toggle_o),
        .cfg_error_o      (cfg_error_o),
        .cfg_read_data_o  (cfg_read_data_o),
        .cam0_scl_o       (cam0_scl_o),
        .cam0_sda_i       (cam0_sda_io),
        .cam0_sda_drive_low_o(cam0_sda_drive_low_w),
        .cam0_rst_n_o     (cam0_rst_n_o),
        .cam0_init_done_o (cam0_init_done_w),
        .cam1_scl_o       (cam1_scl_o),
        .cam1_sda_i       (cam1_sda_io),
        .cam1_sda_drive_low_o(cam1_sda_drive_low_w),
        .cam1_rst_n_o     (cam1_rst_n_o),
        .cam1_init_done_o (cam1_init_done_w),
        .error_o          (init_error_w)
    );

    wire selected_ctrl_w;
    edrv32_camera_select #(
        .DEBOUNCE_CYCLES (BUTTON_DEBOUNCE_CYCLES)
    ) u_camera_select (
        .clk_i      (ctrl_clk_i),
        .rst_n_i    (ctrl_rst_n_i),
        .button_n_i (select_button_n_i),
        .select_o   (selected_ctrl_w)
    );

    reg selected_meta_r;
    reg selected_ddr_r;
    always @(posedge ddr_clk_i or negedge ddr_rst_n_i) begin
        if (!ddr_rst_n_i) begin
            selected_meta_r <= 1'b0;
            selected_ddr_r <= 1'b0;
        end else begin
            selected_meta_r <= selected_ctrl_w;
            selected_ddr_r <= selected_meta_r;
        end
    end

    wire cam0_capture_rst_n_w;
    wire cam1_capture_rst_n_w;
    reset_sync #(.STAGES(2)) u_cam0_reset_sync (
        .clk(cam0_pclk_i), .arst_n_i(ctrl_rst_n_i),
        .rst_n_o(cam0_capture_rst_n_w)
    );
    reset_sync #(.STAGES(2)) u_cam1_reset_sync (
        .clk(cam1_pclk_i), .arst_n_i(ctrl_rst_n_i),
        .rst_n_o(cam1_capture_rst_n_w)
    );

    wire [257:0] cam0_capture_data_w;
    wire cam0_capture_valid_w;
    wire cam0_capture_ready_w;
    wire cam0_capture_overflow_w;
    wire [31:0] cam0_capture_frames_w;
    wire unused_cam0_active_w;
    wire [257:0] cam1_capture_data_w;
    wire cam1_capture_valid_w;
    wire cam1_capture_ready_w;
    wire cam1_capture_overflow_w;
    wire [31:0] cam1_capture_frames_w;
    wire unused_cam1_active_w;

    edrv32_ov5640_capture #(
        .H_ACTIVE(H_ACTIVE), .V_ACTIVE(V_ACTIVE),
        .DISCARD_FRAMES(CAMERA_DISCARD_FRAMES)
    ) u_cam0_capture (
        .clk_i(cam0_pclk_i), .rst_n_i(cam0_capture_rst_n_w),
        .enable_i(enable_i && cam0_enable_i), .init_done_i(cam0_init_done_w),
        .data_i(cam0_data_i), .href_i(cam0_href_i),
        .vsync_i(cam0_vsync_i), .stream_data_o(cam0_capture_data_w),
        .stream_valid_o(cam0_capture_valid_w),
        .stream_ready_i(cam0_capture_ready_w),
        .frame_active_o(unused_cam0_active_w),
        .frame_count_o(cam0_capture_frames_w),
        .overflow_o(cam0_capture_overflow_w)
    );

    edrv32_ov5640_capture #(
        .H_ACTIVE(H_ACTIVE), .V_ACTIVE(V_ACTIVE),
        .DISCARD_FRAMES(CAMERA_DISCARD_FRAMES)
    ) u_cam1_capture (
        .clk_i(cam1_pclk_i), .rst_n_i(cam1_capture_rst_n_w),
        .enable_i(enable_i && cam1_enable_i), .init_done_i(cam1_init_done_w),
        .data_i(cam1_data_i), .href_i(cam1_href_i),
        .vsync_i(cam1_vsync_i), .stream_data_o(cam1_capture_data_w),
        .stream_valid_o(cam1_capture_valid_w),
        .stream_ready_i(cam1_capture_ready_w),
        .frame_active_o(unused_cam1_active_w),
        .frame_count_o(cam1_capture_frames_w),
        .overflow_o(cam1_capture_overflow_w)
    );

    wire [257:0] cam0_fifo_data_w;
    wire cam0_fifo_valid_w;
    wire cam0_fifo_ready_w;
    wire cam0_almost_full_w;
    wire [257:0] cam1_fifo_data_w;
    wire cam1_fifo_valid_w;
    wire cam1_fifo_ready_w;
    wire cam1_almost_full_w;

    edrv32_camera_fifo #(.ADDR_W(CAMERA_FIFO_ADDR_W)) u_cam0_fifo (
        .wr_clk_i(cam0_pclk_i), .wr_rst_n_i(cam0_capture_rst_n_w),
        .wr_data_i(cam0_capture_data_w), .wr_valid_i(cam0_capture_valid_w),
        .wr_ready_o(cam0_capture_ready_w), .almost_full_o(cam0_almost_full_w),
        .rd_clk_i(ddr_clk_i), .rd_rst_n_i(ddr_rst_n_i),
        .rd_data_o(cam0_fifo_data_w), .rd_valid_o(cam0_fifo_valid_w),
        .rd_ready_i(cam0_fifo_ready_w)
    );

    edrv32_camera_fifo #(.ADDR_W(CAMERA_FIFO_ADDR_W)) u_cam1_fifo (
        .wr_clk_i(cam1_pclk_i), .wr_rst_n_i(cam1_capture_rst_n_w),
        .wr_data_i(cam1_capture_data_w), .wr_valid_i(cam1_capture_valid_w),
        .wr_ready_o(cam1_capture_ready_w), .almost_full_o(cam1_almost_full_w),
        .rd_clk_i(ddr_clk_i), .rd_rst_n_i(ddr_rst_n_i),
        .rd_data_o(cam1_fifo_data_w), .rd_valid_o(cam1_fifo_valid_w),
        .rd_ready_i(cam1_fifo_ready_w)
    );

    wire [257:0] selected_stream_data_w;
    wire selected_stream_valid_w;
    wire selected_stream_ready_w;
    wire active_camera_w;
    wire stream_mux_error_w;

    edrv32_camera_stream_mux u_camera_stream_mux (
        .clk_i(ddr_clk_i), .rst_n_i(ddr_rst_n_i),
        .select_i(selected_ddr_r),
        .cam0_data_i(cam0_fifo_data_w), .cam0_valid_i(cam0_fifo_valid_w),
        .cam0_ready_o(cam0_fifo_ready_w),
        .cam1_data_i(cam1_fifo_data_w), .cam1_valid_i(cam1_fifo_valid_w),
        .cam1_ready_o(cam1_fifo_ready_w),
        .stream_data_o(selected_stream_data_w),
        .stream_valid_o(selected_stream_valid_w),
        .stream_ready_i(selected_stream_ready_w),
        .active_camera_o(active_camera_w), .error_o(stream_mux_error_w)
    );

    // The APB shadow payload remains stable until this DDR-domain handshake
    // acknowledges that it has been applied at a frame boundary.
    reg pixel_cfg_req_meta_r;
    reg pixel_cfg_req_sync_r;
    reg pixel_cfg_ack_r;
    reg [1:0] pixel_cfg_state_r;
    reg pixel_cfg_commit_r;
    reg pixel_cfg_enable_r;
    reg pixel_cfg_grayscale_r;
    reg pixel_cfg_threshold_enable_r;
    reg pixel_cfg_invert_r;
    reg signed [8:0] pixel_cfg_brightness_r;
    reg [8:0] pixel_cfg_contrast_r;
    reg [7:0] pixel_cfg_threshold_r;
    reg pixel_cfg_spatial_enable_r;
    reg [2:0] pixel_cfg_spatial_mode_r;
    reg [7:0] pixel_cfg_spatial_threshold_r;

    wire pixel_cfg_pending_w;
    always @(posedge ddr_clk_i or negedge ddr_rst_n_i) begin
        if (!ddr_rst_n_i) begin
            pixel_cfg_req_meta_r <= 1'b0;
            pixel_cfg_req_sync_r <= 1'b0;
            pixel_cfg_ack_r <= 1'b0;
            pixel_cfg_state_r <= 2'b0;
            pixel_cfg_commit_r <= 1'b0;
            pixel_cfg_enable_r <= 1'b0;
            pixel_cfg_grayscale_r <= 1'b0;
            pixel_cfg_threshold_enable_r <= 1'b0;
            pixel_cfg_invert_r <= 1'b0;
            pixel_cfg_brightness_r <= 9'sd0;
            pixel_cfg_contrast_r <= 9'd256;
            pixel_cfg_threshold_r <= 8'd128;
            pixel_cfg_spatial_enable_r <= 1'b0;
            pixel_cfg_spatial_mode_r <= 3'b0;
            pixel_cfg_spatial_threshold_r <= 8'd128;
        end else begin
            pixel_cfg_req_meta_r <= pixel_cfg_req_toggle_i;
            pixel_cfg_req_sync_r <= pixel_cfg_req_meta_r;
            pixel_cfg_commit_r <= 1'b0;
            case (pixel_cfg_state_r)
                2'd0: begin
                    if (pixel_cfg_req_sync_r != pixel_cfg_ack_r) begin
                        pixel_cfg_enable_r <= pixel_cfg_enable_i;
                        pixel_cfg_grayscale_r <= pixel_cfg_grayscale_i;
                        pixel_cfg_threshold_enable_r <=
                            pixel_cfg_threshold_enable_i;
                        pixel_cfg_invert_r <= pixel_cfg_invert_i;
                        pixel_cfg_brightness_r <= pixel_cfg_brightness_i;
                        pixel_cfg_contrast_r <= pixel_cfg_contrast_i;
                        pixel_cfg_threshold_r <= pixel_cfg_threshold_i;
                        pixel_cfg_spatial_enable_r <=
                            pixel_cfg_spatial_enable_i;
                        pixel_cfg_spatial_mode_r <=
                            pixel_cfg_spatial_mode_i;
                        pixel_cfg_spatial_threshold_r <=
                            pixel_cfg_spatial_threshold_i;
                        pixel_cfg_commit_r <= 1'b1;
                        pixel_cfg_state_r <= 2'd1;
                    end
                end
                2'd1: pixel_cfg_state_r <= 2'd2;
                default: begin
                    if (!pixel_cfg_pending_w) begin
                        pixel_cfg_ack_r <= pixel_cfg_req_sync_r;
                        pixel_cfg_state_r <= 2'd0;
                    end
                end
            endcase
        end
    end

    wire [257:0] display_stream_data_w;
    wire display_stream_valid_w;
    wire display_stream_ready_w;
    wire [31:0] pixel_frames_w;
    wire [31:0] pixel_unpack_frames_w;
    wire [31:0] pixel_point_frames_w;
    wire [31:0] pixel_spatial_frames_w;
    wire mux_eof_fire_w = selected_stream_valid_w &&
        selected_stream_ready_w && selected_stream_data_w[256];

    edrv32_pixel_pipeline #(
        .H_ACTIVE(H_ACTIVE)
    ) u_pixel_pipeline (
        .clk_i(ddr_clk_i), .rst_n_i(ddr_rst_n_i),
        .stream_data_i(selected_stream_data_w),
        .stream_valid_i(selected_stream_valid_w),
        .stream_ready_o(selected_stream_ready_w),
        .stream_data_o(display_stream_data_w),
        .stream_valid_o(display_stream_valid_w),
        .stream_ready_i(display_stream_ready_w),
        .cfg_commit_i(pixel_cfg_commit_r),
        .cfg_enable_i(pixel_cfg_enable_r),
        .cfg_grayscale_i(pixel_cfg_grayscale_r),
        .cfg_threshold_enable_i(pixel_cfg_threshold_enable_r),
        .cfg_invert_i(pixel_cfg_invert_r),
        .cfg_brightness_i(pixel_cfg_brightness_r),
        .cfg_contrast_i(pixel_cfg_contrast_r),
        .cfg_threshold_i(pixel_cfg_threshold_r),
        .cfg_spatial_enable_i(pixel_cfg_spatial_enable_r),
        .cfg_spatial_mode_i(pixel_cfg_spatial_mode_r),
        .cfg_spatial_threshold_i(pixel_cfg_spatial_threshold_r),
        .cfg_pending_o(pixel_cfg_pending_w),
        .frame_count_o(pixel_frames_w),
        .unpack_frame_count_o(pixel_unpack_frames_w),
        .point_frame_count_o(pixel_point_frames_w),
        .spatial_frame_count_o(pixel_spatial_frames_w)
    );

    wire [NUM_M*4-1:0] m_awid_w;
    wire [NUM_M*32-1:0] m_awaddr_w;
    wire [NUM_M*8-1:0] m_awlen_w;
    wire [NUM_M*3-1:0] m_awsize_w;
    wire [NUM_M*2-1:0] m_awburst_w;
    wire [NUM_M*4-1:0] m_awqos_w;
    wire [NUM_M-1:0] m_awvalid_w;
    wire [NUM_M-1:0] m_awready_w;
    wire [NUM_M*256-1:0] m_wdata_w;
    wire [NUM_M*32-1:0] m_wstrb_w;
    wire [NUM_M-1:0] m_wlast_w;
    wire [NUM_M-1:0] m_wvalid_w;
    wire [NUM_M-1:0] m_wready_w;
    wire [NUM_M*4-1:0] m_bid_w;
    wire [NUM_M*2-1:0] m_bresp_w;
    wire [NUM_M-1:0] m_bvalid_w;
    wire [NUM_M-1:0] m_bready_w;
    wire [NUM_M*4-1:0] m_arid_w;
    wire [NUM_M*32-1:0] m_araddr_w;
    wire [NUM_M*8-1:0] m_arlen_w;
    wire [NUM_M*3-1:0] m_arsize_w;
    wire [NUM_M*2-1:0] m_arburst_w;
    wire [NUM_M*4-1:0] m_arqos_w;
    wire [NUM_M-1:0] m_arvalid_w;
    wire [NUM_M-1:0] m_arready_w;
    wire [NUM_M*4-1:0] m_rid_w;
    wire [NUM_M*256-1:0] m_rdata_w;
    wire [NUM_M*2-1:0] m_rresp_w;
    wire [NUM_M-1:0] m_rlast_w;
    wire [NUM_M-1:0] m_rvalid_w;
    wire [NUM_M-1:0] m_rready_w;

    wire display_valid_w;
    wire [1:0] display_buffer_w;
    wire [31:0] display_base_w;
    wire release_valid_w;
    wire [1:0] release_buffer_w;
    wire [31:0] display_frames_w;
    wire [31:0] unused_dropped_frames_w;
    wire unused_writer_active_w;
    wire display_writer_error_w;
    wire geometry_source_release_valid_w;
    wire [1:0] geometry_source_release_buffer_w;
    wire geometry_display_valid_w;
    wire [1:0] geometry_display_buffer_w;
    wire [31:0] geometry_display_base_w;
    wire geometry_start_w;
    wire [31:0] geometry_source_base_w;
    wire [31:0] geometry_target_base_w;
    wire [4:0] geometry_active_mode_w;
    wire geometry_cfg_ready_w;
    wire geometry_busy_w;
    wire geometry_done_w;
    wire geometry_error_w;
    wire [2:0] geometry_phase_w;
    wire geometry_queue_error_w;
    wire [31:0] geometry_replaced_frames_w;
    reg [4:0] geometry_mode_meta_r;
    reg [4:0] geometry_mode_sync_r;
    reg geometry_cfg_req_meta_r;
    reg geometry_cfg_req_sync_r;
    reg geometry_cfg_req_seen_r;
    reg geometry_image_override_sync_r;
    reg [15:0] geometry_image_width_sync_r;
    reg [15:0] geometry_image_height_sync_r;
    reg geometry_angle_override_sync_r;
    reg [8:0] geometry_angle_sync_r;

    always @(posedge ddr_clk_i or negedge ddr_rst_n_i) begin
        if (!ddr_rst_n_i) begin
            geometry_mode_meta_r <= 5'b0;
            geometry_mode_sync_r <= 5'b0;
            geometry_cfg_req_meta_r <= 1'b0;
            geometry_cfg_req_sync_r <= 1'b0;
            geometry_cfg_req_seen_r <= 1'b0;
            geometry_image_override_sync_r <= 1'b0;
            geometry_image_width_sync_r <= H_ACTIVE_16;
            geometry_image_height_sync_r <= V_ACTIVE_16;
            geometry_angle_override_sync_r <= 1'b0;
            geometry_angle_sync_r <= 9'b0;
        end else begin
            geometry_mode_meta_r <= geometry_mode_i;
            geometry_mode_sync_r <= geometry_mode_meta_r;
            geometry_cfg_req_meta_r <= geometry_cfg_req_toggle_i;
            geometry_cfg_req_sync_r <= geometry_cfg_req_meta_r;
            if (geometry_cfg_req_sync_r != geometry_cfg_req_seen_r) begin
                // The UART-side payload is held well beyond the two-clock
                // toggle synchronization window before this bundled capture.
                geometry_cfg_req_seen_r <= geometry_cfg_req_sync_r;
                geometry_image_override_sync_r <=
                    geometry_image_override_i;
                geometry_image_width_sync_r <= geometry_image_width_i;
                geometry_image_height_sync_r <= geometry_image_height_i;
                geometry_angle_override_sync_r <=
                    geometry_angle_override_i;
                geometry_angle_sync_r <= geometry_angle_i;
            end
        end
    end

    edrv32_display_axi_writer #(
        .H_ACTIVE(H_ACTIVE), .V_ACTIVE(V_ACTIVE),
        .BURST_BEATS(BURST_BEATS), .FRAME_BASE0(DISPLAY_BASE0),
        .FRAME_BASE1(DISPLAY_BASE1), .FRAME_BASE2(DISPLAY_BASE2),
        .AXI_ID(4'h0)
    ) u_display_writer (
        .clk_i(ddr_clk_i), .rst_n_i(ddr_rst_n_i),
        .stream_data_i(display_stream_data_w),
        .stream_valid_i(display_stream_valid_w),
        .stream_ready_o(display_stream_ready_w),
        .release_valid_i(geometry_source_release_valid_w),
        .release_buffer_i(geometry_source_release_buffer_w),
        .completed_valid_o(display_valid_w),
        .completed_buffer_o(display_buffer_w),
        .completed_base_o(display_base_w),
        .frame_count_o(display_frames_w),
        .dropped_frame_count_o(unused_dropped_frames_w),
        .active_o(unused_writer_active_w), .error_o(display_writer_error_w),
        .m_awid_o(m_awid_w[3:0]), .m_awaddr_o(m_awaddr_w[31:0]),
        .m_awlen_o(m_awlen_w[7:0]), .m_awsize_o(m_awsize_w[2:0]),
        .m_awburst_o(m_awburst_w[1:0]), .m_awqos_o(m_awqos_w[3:0]),
        .m_awvalid_o(m_awvalid_w[0]), .m_awready_i(m_awready_w[0]),
        .m_wdata_o(m_wdata_w[255:0]), .m_wstrb_o(m_wstrb_w[31:0]),
        .m_wlast_o(m_wlast_w[0]), .m_wvalid_o(m_wvalid_w[0]),
        .m_wready_i(m_wready_w[0]), .m_bid_i(m_bid_w[3:0]),
        .m_bresp_i(m_bresp_w[1:0]), .m_bvalid_i(m_bvalid_w[0]),
        .m_bready_o(m_bready_w[0])
    );

    edrv32_geometry_frame_scheduler #(
        .TARGET_BASE0(GEOMETRY_BASE0), .TARGET_BASE1(GEOMETRY_BASE1),
        .TARGET_BASE2(GEOMETRY_BASE2)
    ) u_geometry_scheduler (
        .clk_i(ddr_clk_i), .rst_n_i(ddr_rst_n_i),
        .mode_i(geometry_mode_sync_r),
        .source_valid_i(display_valid_w),
        .source_buffer_i(display_buffer_w), .source_base_i(display_base_w),
        .source_release_valid_o(geometry_source_release_valid_w),
        .source_release_buffer_o(geometry_source_release_buffer_w),
        .target_release_valid_i(release_valid_w),
        .target_release_buffer_i(release_buffer_w),
        .display_valid_o(geometry_display_valid_w),
        .display_buffer_o(geometry_display_buffer_w),
        .display_base_o(geometry_display_base_w),
        .geometry_ready_i(geometry_cfg_ready_w),
        .geometry_start_o(geometry_start_w),
        .geometry_source_base_o(geometry_source_base_w),
        .geometry_target_base_o(geometry_target_base_w),
        .geometry_mode_o(geometry_active_mode_w),
        .geometry_done_i(geometry_done_w), .geometry_error_i(geometry_error_w),
        .overflow_error_o(geometry_queue_error_w),
        .replaced_frame_count_o(geometry_replaced_frames_w)
    );

    wire [8:0] geometry_preset_angle_w =
        geometry_active_mode_w == 5'd7  ? 9'd15  :
        geometry_active_mode_w == 5'd8  ? 9'd30  :
        geometry_active_mode_w == 5'd9  ? 9'd45  :
        geometry_active_mode_w == 5'd10 ? 9'd60  :
        geometry_active_mode_w == 5'd11 ? 9'd90  :
        geometry_active_mode_w == 5'd12 ? 9'd120 :
        geometry_active_mode_w == 5'd13 ? 9'd135 :
        geometry_active_mode_w == 5'd14 ? 9'd150 :
        geometry_active_mode_w == 5'd15 ? 9'd180 :
        geometry_active_mode_w == 5'd16 ? 9'd210 :
        geometry_active_mode_w == 5'd17 ? 9'd225 :
        geometry_active_mode_w == 5'd18 ? 9'd240 :
        geometry_active_mode_w == 5'd19 ? 9'd270 :
        geometry_active_mode_w == 5'd20 ? 9'd300 :
        geometry_active_mode_w == 5'd21 ? 9'd315 :
        geometry_active_mode_w == 5'd22 ? 9'd330 :
        geometry_active_mode_w == 5'd30 ? 9'd90  :
        geometry_active_mode_w == 5'd31 ? 9'd45  : 9'd0;
    wire [8:0] geometry_angle_w = geometry_angle_override_sync_r ?
        geometry_angle_sync_r : geometry_preset_angle_w;
    wire geometry_flip_x_w = geometry_active_mode_w == 5'd23;
    wire geometry_flip_y_w = geometry_active_mode_w == 5'd24;
    // The source crop stays full-size.  Modes 25..31 now select the size of
    // the centered image on the fixed HDMI canvas, including unequal axes.
    wire [15:0] geometry_preset_image_width_w =
        geometry_active_mode_w == 5'd25 ? 16'd1024 :
        geometry_active_mode_w == 5'd27 ? 16'd960  :
        geometry_active_mode_w == 5'd28 ? 16'd640  :
        geometry_active_mode_w == 5'd30 ? 16'd960  :
        geometry_active_mode_w == 5'd31 ? 16'd960  : H_ACTIVE_16;
    wire [15:0] geometry_preset_image_height_w =
        geometry_active_mode_w == 5'd26 ? 16'd576 :
        geometry_active_mode_w == 5'd27 ? 16'd540 :
        geometry_active_mode_w == 5'd29 ? 16'd360 :
        geometry_active_mode_w == 5'd31 ? 16'd540 : V_ACTIVE_16;
    wire [15:0] geometry_image_width_w = geometry_image_override_sync_r ?
        geometry_image_width_sync_r : geometry_preset_image_width_w;
    wire [15:0] geometry_image_height_w = geometry_image_override_sync_r ?
        geometry_image_height_sync_r : geometry_preset_image_height_w;

    edrv32_geometry_surface_pipeline u_geometry (
        .clk_i(ddr_clk_i), .rst_n_i(ddr_rst_n_i),
        .cfg_start_i(geometry_start_w), .cfg_ready_o(geometry_cfg_ready_w),
        .cfg_src_base_i(geometry_source_base_w),
        .cfg_src_stride_i(SURFACE_STRIDE),
        .cfg_src_width_i(H_ACTIVE_16), .cfg_src_height_i(V_ACTIVE_16),
        .cfg_crop_x_i(16'd0), .cfg_crop_y_i(16'd0),
        .cfg_crop_width_i(H_ACTIVE_16),
        .cfg_crop_height_i(V_ACTIVE_16),
        .cfg_dst_base_i(geometry_target_base_w),
        .cfg_dst_stride_i(SURFACE_STRIDE),
        .cfg_dst_width_i(H_ACTIVE_16), .cfg_dst_height_i(V_ACTIVE_16),
        .cfg_image_width_i(geometry_image_width_w),
        .cfg_image_height_i(geometry_image_height_w),
        .cfg_angle_i(geometry_angle_w), .cfg_flip_x_i(geometry_flip_x_w),
        .cfg_flip_y_i(geometry_flip_y_w), .cfg_fill_pixel_i(16'h0000),
        .rd_arid_o(m_arid_w[11:8]), .rd_araddr_o(m_araddr_w[95:64]),
        .rd_arlen_o(m_arlen_w[23:16]), .rd_arsize_o(m_arsize_w[8:6]),
        .rd_arburst_o(m_arburst_w[5:4]), .rd_arqos_o(m_arqos_w[11:8]),
        .rd_arvalid_o(m_arvalid_w[2]), .rd_arready_i(m_arready_w[2]),
        .rd_rid_i(m_rid_w[11:8]), .rd_rdata_i(m_rdata_w[767:512]),
        .rd_rresp_i(m_rresp_w[5:4]), .rd_rlast_i(m_rlast_w[2]),
        .rd_rvalid_i(m_rvalid_w[2]), .rd_rready_o(m_rready_w[2]),
        .wr_awid_o(m_awid_w[15:12]), .wr_awaddr_o(m_awaddr_w[127:96]),
        .wr_awlen_o(m_awlen_w[31:24]), .wr_awsize_o(m_awsize_w[11:9]),
        .wr_awburst_o(m_awburst_w[7:6]), .wr_awqos_o(m_awqos_w[15:12]),
        .wr_awvalid_o(m_awvalid_w[3]), .wr_awready_i(m_awready_w[3]),
        .wr_wdata_o(m_wdata_w[1023:768]), .wr_wstrb_o(m_wstrb_w[127:96]),
        .wr_wlast_o(m_wlast_w[3]), .wr_wvalid_o(m_wvalid_w[3]),
        .wr_wready_i(m_wready_w[3]), .wr_bid_i(m_bid_w[15:12]),
        .wr_bresp_i(m_bresp_w[7:6]), .wr_bvalid_i(m_bvalid_w[3]),
        .wr_bready_o(m_bready_w[3]), .busy_o(geometry_busy_w),
        .done_o(geometry_done_w), .error_o(geometry_error_w),
        .profile_phase_o(geometry_phase_w)
    );

    wire [31:0] unused_reader_frames_w;
    wire [31:0] scanout_underflow_w;
    wire write_owner_valid_w;
    wire [1:0] write_owner_w;

    generate
        if (TELEMETRY_ENABLE) begin : gen_vision_telemetry
            wire [31:0] underflow_ddr_w;
            wire [31:0] cam0_frames_ddr_w;
            wire [31:0] cam1_frames_ddr_w;

            edrv32_counter_cdc u_cam0_frame_cdc (
                .src_clk_i(cam0_pclk_i),
                .src_rst_n_i(cam0_capture_rst_n_w),
                .src_count_i(cam0_capture_frames_w),
                .dst_clk_i(ddr_clk_i),
                .dst_rst_n_i(ddr_rst_n_i),
                .dst_count_o(cam0_frames_ddr_w)
            );

            edrv32_counter_cdc u_cam1_frame_cdc (
                .src_clk_i(cam1_pclk_i),
                .src_rst_n_i(cam1_capture_rst_n_w),
                .src_count_i(cam1_capture_frames_w),
                .dst_clk_i(ddr_clk_i),
                .dst_rst_n_i(ddr_rst_n_i),
                .dst_count_o(cam1_frames_ddr_w)
            );

            edrv32_counter_cdc u_underflow_cdc (
                .src_clk_i(pixel_clk_i),
                .src_rst_n_i(pixel_rst_n_i),
                .src_count_i(scanout_underflow_w),
                .dst_clk_i(ddr_clk_i),
                .dst_rst_n_i(ddr_rst_n_i),
                .dst_count_o(underflow_ddr_w)
            );

            edrv32_vision_telemetry #(
                .CLK_HZ(TELEMETRY_CLK_HZ)
            ) u_telemetry (
                .clk_i(ddr_clk_i), .rst_n_i(ddr_rst_n_i),
                .mode_i(geometry_mode_sync_r),
                .source_frame_i(display_valid_w),
                .source_drop_count_i(unused_dropped_frames_w),
                .geometry_start_i(geometry_start_w),
                .geometry_done_i(geometry_done_w),
                .geometry_error_i(geometry_error_w),
                .geometry_phase_i(geometry_phase_w),
                .display_flip_i(release_valid_w),
                .reader_frame_count_i(unused_reader_frames_w),
                .underflow_count_i(underflow_ddr_w),
                .cam0_frame_count_i(cam0_frames_ddr_w),
                .cam1_frame_count_i(cam1_frames_ddr_w),
                .pixel_frame_count_i(pixel_frames_w),
                .replaced_frame_count_i(geometry_replaced_frames_w),
                .input_stream_stall_i(selected_stream_valid_w &&
                    !selected_stream_ready_w),
                .output_stream_stall_i(display_stream_valid_w &&
                    !display_stream_ready_w),
                .camera_w_stall_i(m_wvalid_w[0] && !m_wready_w[0]),
                .write_owner_valid_i(write_owner_valid_w),
                .write_owner_geometry_i(write_owner_w == 2'd3),
                .mux_eof_i(mux_eof_fire_w),
                .unpack_frame_count_i(pixel_unpack_frames_w),
                .point_frame_count_i(pixel_point_frames_w),
                .spatial_frame_count_i(pixel_spatial_frames_w),
                .mux_error_i(stream_mux_error_w),
                .pixel_cfg_pending_i(pixel_cfg_pending_w),
                .writer_active_i(unused_writer_active_w),
                .mux_valid_i(selected_stream_valid_w),
                .pixel_valid_i(display_stream_valid_w),
                .cam0_overflow_i(cam0_capture_overflow_w),
                .cam1_overflow_i(cam1_capture_overflow_w),
                .writer_error_i(display_writer_error_w),
                .active_camera_i(active_camera_w),
                .rd_arvalid_i(m_arvalid_w[2]),
                .rd_arready_i(m_arready_w[2]),
                .rd_arlen_i(m_arlen_w[23:16]),
                .rd_rvalid_i(m_rvalid_w[2]),
                .rd_rready_i(m_rready_w[2]),
                .wr_awvalid_i(m_awvalid_w[3]),
                .wr_awready_i(m_awready_w[3]),
                .wr_wvalid_i(m_wvalid_w[3]),
                .wr_wready_i(m_wready_w[3]),
                .wr_bvalid_i(m_bvalid_w[3]),
                .wr_bready_i(m_bready_w[3]),
                .uart_tx_o(telemetry_tx_o)
            );
        end else begin : gen_no_vision_telemetry
            assign telemetry_tx_o = 1'b1;
        end
    endgenerate

    wire reader_prefill_done_w;
    wire reader_error_w;
    wire [255:0] hdmi_fifo_write_data_w;
    wire hdmi_fifo_write_valid_w;
    wire hdmi_fifo_write_ready_w;
    wire unused_reader_active_w;
    wire [1:0] reader_active_buffer_w;

    edrv32_hdmi_axi_reader_pageflip #(
        .H_ACTIVE(H_ACTIVE), .V_ACTIVE(V_ACTIVE),
        .BURST_BEATS(BURST_BEATS), .PREFILL_BEATS(PREFILL_BEATS),
        .AXI_ID(4'h1)
    ) u_reader (
        .clk_i(ddr_clk_i), .rst_n_i(ddr_rst_n_i),
        .display_valid_i(geometry_display_valid_w),
        .display_buffer_i(geometry_display_buffer_w),
        .display_base_i(geometry_display_base_w),
        .release_valid_o(release_valid_w),
        .release_buffer_o(release_buffer_w),
        .active_o(unused_reader_active_w),
        .active_buffer_o(reader_active_buffer_w),
        .prefill_done_o(reader_prefill_done_w),
        .frame_count_o(unused_reader_frames_w), .error_o(reader_error_w),
        .m_arid_o(m_arid_w[7:4]), .m_araddr_o(m_araddr_w[63:32]),
        .m_arlen_o(m_arlen_w[15:8]), .m_arsize_o(m_arsize_w[5:3]),
        .m_arburst_o(m_arburst_w[3:2]), .m_arqos_o(m_arqos_w[7:4]),
        .m_arvalid_o(m_arvalid_w[1]), .m_arready_i(m_arready_w[1]),
        .m_rid_i(m_rid_w[7:4]), .m_rdata_i(m_rdata_w[511:256]),
        .m_rresp_i(m_rresp_w[3:2]), .m_rlast_i(m_rlast_w[1]),
        .m_rvalid_i(m_rvalid_w[1]), .m_rready_o(m_rready_w[1]),
        .fifo_data_o(hdmi_fifo_write_data_w),
        .fifo_valid_o(hdmi_fifo_write_valid_w),
        .fifo_ready_i(hdmi_fifo_write_ready_w)
    );

    assign m_awid_w[7:4] = 4'b0;
    assign m_awaddr_w[63:32] = 32'b0;
    assign m_awlen_w[15:8] = 8'b0;
    assign m_awsize_w[5:3] = 3'd5;
    assign m_awburst_w[3:2] = 2'b01;
    assign m_awqos_w[7:4] = 4'b0;
    assign m_awvalid_w[1] = 1'b0;
    assign m_wdata_w[511:256] = 256'b0;
    assign m_wstrb_w[63:32] = 32'b0;
    assign m_wlast_w[1] = 1'b0;
    assign m_wvalid_w[1] = 1'b0;
    assign m_bready_w[1] = 1'b1;
    assign m_awid_w[11:8] = 4'b0;
    assign m_awaddr_w[95:64] = 32'b0;
    assign m_awlen_w[23:16] = 8'b0;
    assign m_awsize_w[8:6] = 3'd5;
    assign m_awburst_w[5:4] = 2'b01;
    assign m_awqos_w[11:8] = 4'b0;
    assign m_awvalid_w[2] = 1'b0;
    assign m_wdata_w[767:512] = 256'b0;
    assign m_wstrb_w[95:64] = 32'b0;
    assign m_wlast_w[2] = 1'b0;
    assign m_wvalid_w[2] = 1'b0;
    assign m_bready_w[2] = 1'b1;

    assign m_arid_w[3:0] = 4'b0;
    assign m_araddr_w[31:0] = 32'b0;
    assign m_arlen_w[7:0] = 8'b0;
    assign m_arsize_w[2:0] = 3'd5;
    assign m_arburst_w[1:0] = 2'b01;
    assign m_arqos_w[3:0] = 4'b0;
    assign m_arvalid_w[0] = 1'b0;
    assign m_rready_w[0] = 1'b1;
    assign m_arid_w[15:12] = 4'b0;
    assign m_araddr_w[127:96] = 32'b0;
    assign m_arlen_w[31:24] = 8'b0;
    assign m_arsize_w[11:9] = 3'd5;
    assign m_arburst_w[7:6] = 2'b01;
    assign m_arqos_w[15:12] = 4'b0;
    assign m_arvalid_w[3] = 1'b0;
    assign m_rready_w[3] = 1'b1;

    wire [255:0] hdmi_fifo_read_data_w;
    wire hdmi_fifo_read_valid_w;
    wire hdmi_fifo_read_ready_w;
    wire hdmi_fifo_almost_empty_w;
    wire [1:0] hdmi_fifo_local_count_w;

    edrv32_hdmi_fifo u_hdmi_fifo (
        .wr_clk_i(ddr_clk_i), .wr_rst_n_i(ddr_rst_n_i),
        .wr_data_i(hdmi_fifo_write_data_w),
        .wr_valid_i(hdmi_fifo_write_valid_w),
        .wr_ready_o(hdmi_fifo_write_ready_w),
        .rd_clk_i(pixel_clk_i), .rd_rst_n_i(pixel_rst_n_i),
        .rd_data_o(hdmi_fifo_read_data_w),
        .rd_valid_o(hdmi_fifo_read_valid_w),
        .rd_ready_i(hdmi_fifo_read_ready_w),
        .almost_empty_o(hdmi_fifo_almost_empty_w),
        .local_count_o(hdmi_fifo_local_count_w)
    );

    reg prefill_meta_r;
    reg prefill_sync_r;
    reg display_enable_meta_r;
    reg display_enable_sync_r;
    always @(posedge pixel_clk_i or negedge pixel_rst_n_i) begin
        if (!pixel_rst_n_i) begin
            prefill_meta_r <= 1'b0;
            prefill_sync_r <= 1'b0;
            display_enable_meta_r <= 1'b0;
            display_enable_sync_r <= 1'b0;
        end else begin
            prefill_meta_r <= reader_prefill_done_w;
            prefill_sync_r <= prefill_meta_r;
            display_enable_meta_r <= display_enable_i;
            display_enable_sync_r <= display_enable_meta_r;
        end
    end

    reg almost_empty_meta_r;
    reg almost_empty_sync_r;
    reg selected_full_meta_r;
    reg selected_full_sync_r;
    wire selected_full_w = selected_ddr_r ?
        cam1_almost_full_w : cam0_almost_full_w;

    always @(posedge ddr_clk_i or negedge ddr_rst_n_i) begin
        if (!ddr_rst_n_i) begin
            almost_empty_meta_r <= 1'b1;
            almost_empty_sync_r <= 1'b1;
            selected_full_meta_r <= 1'b0;
            selected_full_sync_r <= 1'b0;
        end else begin
            almost_empty_meta_r <= hdmi_fifo_almost_empty_w;
            almost_empty_sync_r <= almost_empty_meta_r;
            selected_full_meta_r <= selected_full_w;
            selected_full_sync_r <= selected_full_meta_r;
        end
    end

    wire [23:0] scanout_rgb_w;
    wire scanout_hs_w;
    wire scanout_vs_w;
    wire scanout_de_w;
    wire [15:0] unused_scanout_x_w;
    wire [15:0] unused_scanout_y_w;
    wire [31:0] scanout_frames_w;

    edrv32_hdmi_scanout #(
        .H_ACTIVE(H_ACTIVE), .H_FP(H_FP), .H_SYNC(H_SYNC), .H_BP(H_BP),
        .V_ACTIVE(V_ACTIVE), .V_FP(V_FP), .V_SYNC(V_SYNC), .V_BP(V_BP)
    ) u_scanout (
        .clk_i(pixel_clk_i), .rst_n_i(pixel_rst_n_i),
        .enable_i(prefill_sync_r),
        .output_enable_i(display_enable_sync_r),
        .fifo_data_i(hdmi_fifo_read_data_w),
        .fifo_valid_i(hdmi_fifo_read_valid_w),
        .fifo_ready_o(hdmi_fifo_read_ready_w), .rgb_o(scanout_rgb_w),
        .hs_o(scanout_hs_w), .vs_o(scanout_vs_w), .de_o(scanout_de_w),
        .active_x_o(unused_scanout_x_w), .active_y_o(unused_scanout_y_w),
        .frame_count_o(scanout_frames_w),
        .underflow_count_o(scanout_underflow_w)
    );

    edrv32_tmds_tx u_tmds_tx (
        .pixel_clk_i(pixel_clk_i), .serial_clk_i(serial_clk_i),
        .pixel_rst_n_i(pixel_rst_n_i),
        .serial_rst_n_i(serial_rst_n_i), .rgb_i(scanout_rgb_w),
        .hs_i(scanout_hs_w), .vs_i(scanout_vs_w), .de_i(scanout_de_w),
        .tmds_clk_p_o(tmds_clk_p_o), .tmds_clk_n_o(tmds_clk_n_o),
        .tmds_data_p_o(tmds_data_p_o), .tmds_data_n_o(tmds_data_n_o)
    );

    wire [NUM_M*5-1:0] unused_read_outstanding_w;
    wire [NUM_M*5-1:0] unused_write_outstanding_w;
    wire fabric_read_error_w;
    wire fabric_write_error_w;

    edrv32_axi_m2s_interconnect #(
        .NUM_M(NUM_M), .WR_ORDER_DEPTH(8), .STARVE_CYCLES(64)
    ) u_video_fabric (
        .clk_i(ddr_clk_i), .rst_n_i(ddr_rst_n_i), .accept_i(enable_i),
        .m_awid_i(m_awid_w), .m_awaddr_i(m_awaddr_w), .m_awlen_i(m_awlen_w),
        .m_awsize_i(m_awsize_w), .m_awburst_i(m_awburst_w),
        .m_awqos_i(m_awqos_w), .m_awvalid_i(m_awvalid_w),
        .m_awready_o(m_awready_w), .m_wdata_i(m_wdata_w),
        .m_wstrb_i(m_wstrb_w), .m_wlast_i(m_wlast_w),
        .m_wvalid_i(m_wvalid_w), .m_wready_o(m_wready_w),
        .m_bid_o(m_bid_w), .m_bresp_o(m_bresp_w), .m_bvalid_o(m_bvalid_w),
        .m_bready_i(m_bready_w), .m_arid_i(m_arid_w),
        .m_araddr_i(m_araddr_w), .m_arlen_i(m_arlen_w),
        .m_arsize_i(m_arsize_w), .m_arburst_i(m_arburst_w),
        .m_arqos_i(m_arqos_w), .m_arvalid_i(m_arvalid_w),
        .m_arready_o(m_arready_w), .m_rid_o(m_rid_w),
        .m_rdata_o(m_rdata_w), .m_rresp_o(m_rresp_w),
        .m_rlast_o(m_rlast_w), .m_rvalid_o(m_rvalid_w),
        .m_rready_i(m_rready_w),
        .m_read_urgent_i({2'b00, almost_empty_sync_r, 1'b0}),
        .m_write_urgent_i({3'b000, selected_full_sync_r}),
        .m_read_weight_i({4'd1, 4'd5, 4'd12, 4'd1}),
        .m_write_weight_i({4'd6, 4'd1, 4'd1, 4'd8}),
        .m_read_credit_i({5'd1, 5'd8, 5'd16, 5'd1}),
        .m_write_credit_i({5'd8, 5'd1, 5'd1, 5'd8}),
        .s_awid_o(m_awid_o), .s_awaddr_o(m_awaddr_o),
        .s_awlen_o(m_awlen_o), .s_awsize_o(m_awsize_o),
        .s_awburst_o(m_awburst_o), .s_awqos_o(m_awqos_o),
        .s_awvalid_o(m_awvalid_o), .s_awready_i(m_awready_i),
        .s_wdata_o(m_wdata_o), .s_wstrb_o(m_wstrb_o),
        .s_wlast_o(m_wlast_o), .s_wvalid_o(m_wvalid_o),
        .s_wready_i(m_wready_i), .s_bid_i(m_bid_i),
        .s_bresp_i(m_bresp_i), .s_bvalid_i(m_bvalid_i),
        .s_bready_o(m_bready_o), .s_arid_o(m_arid_o),
        .s_araddr_o(m_araddr_o), .s_arlen_o(m_arlen_o),
        .s_arsize_o(m_arsize_o), .s_arburst_o(m_arburst_o),
        .s_arqos_o(m_arqos_o), .s_arvalid_o(m_arvalid_o),
        .s_arready_i(m_arready_i), .s_rid_i(m_rid_i),
        .s_rdata_i(m_rdata_i), .s_rresp_i(m_rresp_i),
        .s_rlast_i(m_rlast_i), .s_rvalid_i(m_rvalid_i),
        .s_rready_o(m_rready_o),
        .read_outstanding_o(unused_read_outstanding_w),
        .write_outstanding_o(unused_write_outstanding_w),
        .write_owner_valid_o(write_owner_valid_w),
        .write_owner_o(write_owner_w),
        .read_protocol_error_o(fabric_read_error_w),
        .write_protocol_error_o(fabric_write_error_w)
    );

    assign selected_camera_o = active_camera_w;
    assign cam0_init_done_o = cam0_init_done_w;
    assign cam1_init_done_o = cam1_init_done_w;
    assign display_active_buffer_o = reader_active_buffer_w;
    assign cam0_frame_count_o = cam0_capture_frames_w;
    assign cam1_frame_count_o = cam1_capture_frames_w;
    assign display_frame_count_o = display_frames_w;
    assign pixel_frame_count_o = pixel_frames_w;
    assign underflow_count_o = scanout_underflow_w;
    assign reader_prefill_done_o = prefill_sync_r;
    assign hdmi_fifo_read_valid_o = hdmi_fifo_read_valid_w;
    assign hdmi_fifo_local_count_o = hdmi_fifo_local_count_w;
    assign scanout_frame_count_o = scanout_frames_w;
    assign pixel_cfg_ack_toggle_o = pixel_cfg_ack_r;
    assign read_urgent_o = almost_empty_sync_r;
    assign write_urgent_o = selected_full_sync_r;
    assign camera_error_o = init_error_w | cam0_capture_overflow_w |
        cam1_capture_overflow_w | stream_mux_error_w;
    assign display_error_o = display_writer_error_w | reader_error_w |
        fabric_read_error_w | fabric_write_error_w |
        geometry_error_w | geometry_queue_error_w |
        (|scanout_underflow_w);
    assign error_o = camera_error_o | display_error_o;

endmodule
