// ============================================================================
// File        : edrv32_geometry_surface_pipeline.v
// Description : Complete DDR Surface-to-Surface geometry datapath.
// Notes       : The read engine and S2MM writer are separate AXI masters so
//               the DDR interconnect can schedule tile fills and write bursts.
// ============================================================================

module edrv32_geometry_surface_pipeline (
    input  wire         clk_i,
    input  wire         rst_n_i,

    input  wire         cfg_start_i,
    output wire         cfg_ready_o,
    input  wire [31:0]  cfg_src_base_i,
    input  wire [31:0]  cfg_src_stride_i,
    input  wire [15:0]  cfg_src_width_i,
    input  wire [15:0]  cfg_src_height_i,
    input  wire [15:0]  cfg_crop_x_i,
    input  wire [15:0]  cfg_crop_y_i,
    input  wire [15:0]  cfg_crop_width_i,
    input  wire [15:0]  cfg_crop_height_i,
    input  wire [31:0]  cfg_dst_base_i,
    input  wire [31:0]  cfg_dst_stride_i,
    input  wire [15:0]  cfg_dst_width_i,
    input  wire [15:0]  cfg_dst_height_i,
    input  wire [15:0]  cfg_image_width_i,
    input  wire [15:0]  cfg_image_height_i,
    input  wire [8:0]   cfg_angle_i,
    input  wire         cfg_flip_x_i,
    input  wire         cfg_flip_y_i,
    input  wire [15:0]  cfg_fill_pixel_i,

    output wire [3:0]   rd_arid_o,
    output wire [31:0]  rd_araddr_o,
    output wire [7:0]   rd_arlen_o,
    output wire [2:0]   rd_arsize_o,
    output wire [1:0]   rd_arburst_o,
    output wire [3:0]   rd_arqos_o,
    output wire         rd_arvalid_o,
    input  wire         rd_arready_i,
    input  wire [3:0]   rd_rid_i,
    input  wire [255:0] rd_rdata_i,
    input  wire [1:0]   rd_rresp_i,
    input  wire         rd_rlast_i,
    input  wire         rd_rvalid_i,
    output wire         rd_rready_o,

    output wire [3:0]   wr_awid_o,
    output wire [31:0]  wr_awaddr_o,
    output wire [7:0]   wr_awlen_o,
    output wire [2:0]   wr_awsize_o,
    output wire [1:0]   wr_awburst_o,
    output wire [3:0]   wr_awqos_o,
    output wire         wr_awvalid_o,
    input  wire         wr_awready_i,
    output wire [255:0] wr_wdata_o,
    output wire [31:0]  wr_wstrb_o,
    output wire         wr_wlast_o,
    output wire         wr_wvalid_o,
    input  wire         wr_wready_i,
    input  wire [3:0]   wr_bid_i,
    input  wire [1:0]   wr_bresp_i,
    input  wire         wr_bvalid_i,
    output wire         wr_bready_o,

    output wire         busy_o,
    output wire         done_o,
    output wire         error_o,
    output wire [2:0]   profile_phase_o
);

    reg active_r;
    reg done_r;
    reg error_r;

    wire [16:0] crop_x_end_w = {1'b0, cfg_crop_x_i} +
        {1'b0, cfg_crop_width_i};
    wire [16:0] crop_y_end_w = {1'b0, cfg_crop_y_i} +
        {1'b0, cfg_crop_height_i};
    wire [16:0] min_image_width_w =
        ({1'b0, cfg_crop_width_i} + 17'd1) >> 1;
    wire [16:0] min_image_height_w =
        ({1'b0, cfg_crop_height_i} + 17'd1) >> 1;
    wire [16:0] src_width_bytes_w = {1'b0, cfg_src_width_i} << 1;
    wire [16:0] dst_width_bytes_w = {1'b0, cfg_dst_width_i} << 1;
    wire cfg_legal_w =
        (cfg_src_width_i != 0) && (cfg_src_height_i != 0) &&
        (cfg_src_width_i <= 16'd32768) &&
        (cfg_src_height_i <= 16'd32768) &&
        (cfg_crop_width_i != 0) && (cfg_crop_height_i != 0) &&
        (cfg_dst_width_i != 0) && (cfg_dst_height_i != 0) &&
        (cfg_image_width_i != 0) && (cfg_image_height_i != 0) &&
        ({1'b0, cfg_image_width_i} >= min_image_width_w) &&
        ({1'b0, cfg_image_height_i} >= min_image_height_w) &&
        // One 16-row band occupies ceil(width/16)*16 words in the
        // 2048x256 reorder RAM.  Wider Surfaces require a larger generated IP.
        (cfg_dst_width_i <= 16'd2048) &&
        (cfg_angle_i <= 9'd359) &&
        (crop_x_end_w <= {1'b0, cfg_src_width_i}) &&
        (crop_y_end_w <= {1'b0, cfg_src_height_i}) &&
        (cfg_src_base_i[4:0] == 0) && (cfg_dst_base_i[4:0] == 0) &&
        (cfg_src_stride_i[4:0] == 0) && (cfg_dst_stride_i[4:0] == 0) &&
        ({1'b0, cfg_src_stride_i} >= {{16{1'b0}}, src_width_bytes_w}) &&
        ({1'b0, cfg_dst_stride_i} >= {{16{1'b0}}, dst_width_bytes_w});

    wire engine_cfg_ready_w;
    wire writer_cfg_ready_w;
    wire launch_w = cfg_start_i && cfg_ready_o && cfg_legal_w;
    wire reject_w = cfg_start_i && cfg_ready_o && !cfg_legal_w;

    wire pixel_valid_w;
    wire pixel_ready_w;
    wire [15:0] pixel_data_w;
    wire [15:0] pixel_dst_x_w;
    wire [15:0] pixel_dst_y_w;
    wire pixel_sof_w;
    wire pixel_eol_w;
    wire pixel_eof_w;
    wire engine_busy_w;
    wire engine_done_w;
    wire engine_error_w;
    wire [2:0] engine_phase_w;
    wire writer_busy_w;
    wire writer_done_w;
    wire writer_error_w;

    edrv32_geometry_block_engine u_engine (
        .clk_i(clk_i), .rst_n_i(rst_n_i),
        .cfg_start_i(launch_w), .cfg_ready_o(engine_cfg_ready_w),
        .cfg_surface_base_i(cfg_src_base_i),
        .cfg_surface_stride_i(cfg_src_stride_i),
        .cfg_src_width_i(cfg_src_width_i),
        .cfg_src_height_i(cfg_src_height_i),
        .cfg_crop_x_i(cfg_crop_x_i), .cfg_crop_y_i(cfg_crop_y_i),
        .cfg_crop_width_i(cfg_crop_width_i),
        .cfg_crop_height_i(cfg_crop_height_i),
        .cfg_dst_width_i(cfg_dst_width_i),
        .cfg_dst_height_i(cfg_dst_height_i),
        .cfg_image_width_i(cfg_image_width_i),
        .cfg_image_height_i(cfg_image_height_i),
        .cfg_angle_i(cfg_angle_i), .cfg_flip_x_i(cfg_flip_x_i),
        .cfg_flip_y_i(cfg_flip_y_i), .cfg_fill_pixel_i(cfg_fill_pixel_i),
        .pixel_valid_o(pixel_valid_w), .pixel_ready_i(pixel_ready_w),
        .pixel_data_o(pixel_data_w),
        .pixel_dst_x_o(pixel_dst_x_w), .pixel_dst_y_o(pixel_dst_y_w),
        .pixel_sof_o(pixel_sof_w), .pixel_eol_o(pixel_eol_w),
        .pixel_eof_o(pixel_eof_w),
        .m_arid_o(rd_arid_o), .m_araddr_o(rd_araddr_o),
        .m_arlen_o(rd_arlen_o), .m_arsize_o(rd_arsize_o),
        .m_arburst_o(rd_arburst_o), .m_arqos_o(rd_arqos_o),
        .m_arvalid_o(rd_arvalid_o), .m_arready_i(rd_arready_i),
        .m_rid_i(rd_rid_i), .m_rdata_i(rd_rdata_i),
        .m_rresp_i(rd_rresp_i), .m_rlast_i(rd_rlast_i),
        .m_rvalid_i(rd_rvalid_i), .m_rready_o(rd_rready_o),
        .busy_o(engine_busy_w), .done_o(engine_done_w),
        .error_o(engine_error_w),
        .profile_phase_o(engine_phase_w)
    );

    edrv32_geometry_axi_writer u_writer (
        .clk_i(clk_i), .rst_n_i(rst_n_i),
        .cfg_start_i(launch_w), .cfg_ready_o(writer_cfg_ready_w),
        .abort_i(engine_done_w && engine_error_w),
        .cfg_dst_base_i(cfg_dst_base_i),
        .cfg_dst_stride_i(cfg_dst_stride_i),
        .cfg_dst_width_i(cfg_dst_width_i),
        .cfg_dst_height_i(cfg_dst_height_i),
        .pixel_valid_i(pixel_valid_w), .pixel_ready_o(pixel_ready_w),
        .pixel_data_i(pixel_data_w),
        .pixel_dst_x_i(pixel_dst_x_w), .pixel_dst_y_i(pixel_dst_y_w),
        .pixel_sof_i(pixel_sof_w), .pixel_eol_i(pixel_eol_w),
        .pixel_eof_i(pixel_eof_w),
        .m_awid_o(wr_awid_o), .m_awaddr_o(wr_awaddr_o),
        .m_awlen_o(wr_awlen_o), .m_awsize_o(wr_awsize_o),
        .m_awburst_o(wr_awburst_o), .m_awqos_o(wr_awqos_o),
        .m_awvalid_o(wr_awvalid_o), .m_awready_i(wr_awready_i),
        .m_wdata_o(wr_wdata_o), .m_wstrb_o(wr_wstrb_o),
        .m_wlast_o(wr_wlast_o), .m_wvalid_o(wr_wvalid_o),
        .m_wready_i(wr_wready_i), .m_bid_i(wr_bid_i),
        .m_bresp_i(wr_bresp_i), .m_bvalid_i(wr_bvalid_i),
        .m_bready_o(wr_bready_o),
        .busy_o(writer_busy_w), .done_o(writer_done_w),
        .error_o(writer_error_w)
    );

    assign cfg_ready_o = !active_r && engine_cfg_ready_w && writer_cfg_ready_w;
    assign busy_o = active_r;
    assign done_o = done_r;
    assign error_o = error_r | engine_error_w | writer_error_w;
    assign profile_phase_o = engine_busy_w ? engine_phase_w :
        (active_r ? 3'd6 : 3'd0);

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            active_r <= 1'b0;
            done_r <= 1'b0;
            error_r <= 1'b0;
        end else begin
            done_r <= 1'b0;
            if (launch_w) begin
                active_r <= 1'b1;
                error_r <= 1'b0;
            end
            if (reject_w) begin
                active_r <= 1'b0;
                done_r <= 1'b1;
                error_r <= 1'b1;
            end
            if (active_r && (engine_error_w || writer_error_w))
                error_r <= 1'b1;
            if (active_r && writer_done_w) begin
                active_r <= 1'b0;
                done_r <= 1'b1;
            end
        end
    end

endmodule
