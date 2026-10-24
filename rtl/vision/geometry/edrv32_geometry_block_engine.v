// ============================================================================
// File        : edrv32_geometry_block_engine.v
// Description : Deterministic block/strip DDR geometry processing engine.
// Notes       : A 32x16 destination block loads one bounded source patch with
//               row bursts, samples it from local RAM, and writes a 16-row
//               target band.  The band is then emitted in raster order.
// ============================================================================

module edrv32_geometry_block_engine (
    input  wire         clk_i,
    input  wire         rst_n_i,

    input  wire         cfg_start_i,
    output wire         cfg_ready_o,
    input  wire [31:0]  cfg_surface_base_i,
    input  wire [31:0]  cfg_surface_stride_i,
    input  wire [15:0]  cfg_src_width_i,
    input  wire [15:0]  cfg_src_height_i,
    input  wire [15:0]  cfg_crop_x_i,
    input  wire [15:0]  cfg_crop_y_i,
    input  wire [15:0]  cfg_crop_width_i,
    input  wire [15:0]  cfg_crop_height_i,
    input  wire [15:0]  cfg_dst_width_i,
    input  wire [15:0]  cfg_dst_height_i,
    input  wire [15:0]  cfg_image_width_i,
    input  wire [15:0]  cfg_image_height_i,
    input  wire [8:0]   cfg_angle_i,
    input  wire         cfg_flip_x_i,
    input  wire         cfg_flip_y_i,
    input  wire [15:0]  cfg_fill_pixel_i,

    output wire         pixel_valid_o,
    input  wire         pixel_ready_i,
    output wire [15:0]  pixel_data_o,
    output wire [15:0]  pixel_dst_x_o,
    output wire [15:0]  pixel_dst_y_o,
    output wire         pixel_sof_o,
    output wire         pixel_eol_o,
    output wire         pixel_eof_o,

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

    output wire         busy_o,
    output wire         done_o,
    output wire         error_o,
    output wire [2:0]   profile_phase_o
);

    localparam [3:0] STATE_IDLE        = 4'd0;
    localparam [3:0] STATE_CONFIG      = 4'd1;
    localparam [3:0] STATE_BLOCK_PREP  = 4'd2;
    localparam [3:0] STATE_PATCH_REQ   = 4'd3;
    localparam [3:0] STATE_PATCH_WAIT  = 4'd4;
    localparam [3:0] STATE_PROC_START  = 4'd5;
    localparam [3:0] STATE_PROC_ISSUE  = 4'd6;
    localparam [3:0] STATE_PROC_SEND   = 4'd7;
    localparam [3:0] STATE_PROC_WAIT   = 4'd8;
    localparam [3:0] STATE_DRAIN_REQ   = 4'd9;
    localparam [3:0] STATE_DRAIN_SEND  = 4'd10;
    localparam [3:0] STATE_BBOX_CORNERS = 4'd11;
    localparam [3:0] STATE_BBOX_EXTREMA = 4'd12;
    localparam [3:0] STATE_BBOX_CLIP    = 4'd13;
    localparam [3:0] STATE_BBOX_CHECK   = 4'd14;

    localparam [15:0] BLOCK_WIDTH  = 16'd32;
    localparam [15:0] BLOCK_HEIGHT = 16'd16;

    function [15:0] select_pixel;
        input [255:0] word_i;
        input [3:0] lane_i;
        begin
            case (lane_i)
                4'd0: select_pixel = word_i[15:0];
                4'd1: select_pixel = word_i[31:16];
                4'd2: select_pixel = word_i[47:32];
                4'd3: select_pixel = word_i[63:48];
                4'd4: select_pixel = word_i[79:64];
                4'd5: select_pixel = word_i[95:80];
                4'd6: select_pixel = word_i[111:96];
                4'd7: select_pixel = word_i[127:112];
                4'd8: select_pixel = word_i[143:128];
                4'd9: select_pixel = word_i[159:144];
                4'd10: select_pixel = word_i[175:160];
                4'd11: select_pixel = word_i[191:176];
                4'd12: select_pixel = word_i[207:192];
                4'd13: select_pixel = word_i[223:208];
                4'd14: select_pixel = word_i[239:224];
                default: select_pixel = word_i[255:240];
            endcase
        end
    endfunction

    function [255:0] select_column_row0;
        input [1:0] column_i;
        input [255:0] col0_i;
        input [255:0] col1_i;
        input [255:0] col2_i;
        input [255:0] col3_i;
        begin
            case (column_i)
                2'd0: select_column_row0 = col0_i;
                2'd1: select_column_row0 = col1_i;
                2'd2: select_column_row0 = col2_i;
                default: select_column_row0 = col3_i;
            endcase
        end
    endfunction

    reg [3:0] state_r;
    reg done_r;
    reg error_r;
    reg [31:0] surface_base_r;
    reg [31:0] surface_stride_r;
    reg [15:0] crop_x_r;
    reg [15:0] crop_y_r;
    reg [15:0] crop_width_r;
    reg [15:0] crop_height_r;
    reg [15:0] dst_width_r;
    reg [15:0] dst_height_r;
    reg [15:0] block_width_limit_r;
    reg [15:0] fill_pixel_r;

    reg signed [31:0] origin_x_r;
    reg signed [31:0] origin_y_r;
    reg signed [31:0] pixel_step_x_r;
    reg signed [31:0] pixel_step_y_r;
    reg signed [31:0] row_step_x_r;
    reg signed [31:0] row_step_y_r;
    reg signed [31:0] band_origin_x_r;
    reg signed [31:0] band_origin_y_r;
    reg signed [31:0] block_origin_x_r;
    reg signed [31:0] block_origin_y_r;

    reg [15:0] band_y_r;
    reg [15:0] block_x_r;
    reg [15:0] block_width_r;
    reg [15:0] block_height_r;
    reg [15:0] patch_x_base_r;
    reg [15:0] patch_y_base_r;
    reg [2:0] patch_width_beats_r;
    reg [6:0] patch_height_r;

    reg [15:0] proc_x_r;
    reg [15:0] proc_y_r;
    reg signed [31:0] proc_row_x_r;
    reg signed [31:0] proc_row_y_r;
    reg signed [31:0] proc_sample_x_r;
    reg signed [31:0] proc_sample_y_r;
    reg [15:0] block_output_count_r;

    reg sample_in_bounds_r;
    reg [15:0] sample_frac_x_r;
    reg [15:0] sample_frac_y_r;
    reg [15:0] sample_dst_x_r;
    reg [15:0] sample_dst_y_r;
    reg sample_sof_r;
    reg sample_eol_r;
    reg sample_eof_r;
    reg [1:0] sample_col0_r;
    reg [1:0] sample_col1_r;
    reg [3:0] sample_lane0_r;
    reg [3:0] sample_lane1_r;

    reg [255:0] band_pack_r;
    reg [15:0] drain_row_r;
    reg [15:0] drain_beat_r;
    reg [3:0] drain_lane_r;

    wire config_start_w = cfg_start_i && cfg_ready_o;
    wire config_walker_start_w;
    wire [15:0] config_dst_width_w;
    wire [15:0] config_dst_height_w;
    wire [15:0] unused_config_src_width_w;
    wire [15:0] unused_config_src_height_w;
    wire signed [31:0] config_origin_x_w;
    wire signed [31:0] config_origin_y_w;
    wire signed [31:0] config_pixel_step_x_w;
    wire signed [31:0] config_pixel_step_y_w;
    wire signed [31:0] config_row_step_x_w;
    wire signed [31:0] config_row_step_y_w;
    wire config_busy_w;
    wire config_done_w;
    wire config_error_w;

    edrv32_geometry_config u_config (
        .clk_i(clk_i), .rst_n_i(rst_n_i),
        .cfg_start_i(config_start_w),
        .cfg_src_width_i(cfg_src_width_i),
        .cfg_src_height_i(cfg_src_height_i),
        .cfg_crop_x_i(cfg_crop_x_i), .cfg_crop_y_i(cfg_crop_y_i),
        .cfg_crop_width_i(cfg_crop_width_i),
        .cfg_crop_height_i(cfg_crop_height_i),
        .cfg_dst_width_i(cfg_dst_width_i),
        .cfg_dst_height_i(cfg_dst_height_i),
        .cfg_image_width_i(cfg_image_width_i),
        .cfg_image_height_i(cfg_image_height_i),
        .cfg_angle_i(cfg_angle_i),
        .cfg_flip_x_i(cfg_flip_x_i), .cfg_flip_y_i(cfg_flip_y_i),
        .walker_start_o(config_walker_start_w),
        .walker_dst_width_o(config_dst_width_w),
        .walker_dst_height_o(config_dst_height_w),
        .walker_src_width_o(unused_config_src_width_w),
        .walker_src_height_o(unused_config_src_height_w),
        .walker_origin_x_o(config_origin_x_w),
        .walker_origin_y_o(config_origin_y_w),
        .walker_pixel_step_x_o(config_pixel_step_x_w),
        .walker_pixel_step_y_o(config_pixel_step_y_w),
        .walker_row_step_x_o(config_row_step_x_w),
        .walker_row_step_y_o(config_row_step_y_w),
        .busy_o(config_busy_w), .done_o(config_done_w),
        .error_o(config_error_w)
    );

    wire [16:0] crop_right_full_w = {1'b0, crop_x_r} +
        {1'b0, crop_width_r} - 1'b1;
    wire [16:0] crop_bottom_full_w = {1'b0, crop_y_r} +
        {1'b0, crop_height_r} - 1'b1;
    wire [15:0] crop_right_w = crop_right_full_w[15:0];
    wire [15:0] crop_bottom_w = crop_bottom_full_w[15:0];
    wire [17:0] image_x_quarters_w = {2'b0, cfg_image_width_i} << 2;
    wire [17:0] image_y_quarters_w = {2'b0, cfg_image_height_i} << 2;
    wire [17:0] crop_x_three_w =
        ({2'b0, cfg_crop_width_i} << 1) + {2'b0, cfg_crop_width_i};
    wire [17:0] crop_y_three_w =
        ({2'b0, cfg_crop_height_i} << 1) + {2'b0, cfg_crop_height_i};

    wire [15:0] block_width_w =
        (dst_width_r - block_x_r) >= block_width_limit_r ?
        block_width_limit_r : dst_width_r - block_x_r;
    wire [15:0] block_height_w =
        (dst_height_r - band_y_r) >= BLOCK_HEIGHT ?
        BLOCK_HEIGHT : dst_height_r - band_y_r;
    // Width/height are captured before this arithmetic.  The old path ran
    // width selection -> multipliers -> four-corner extrema -> clipping ->
    // error FSM in one DDR clock and missed timing by more than 8 ns.
    wire signed [6:0] block_x_span_w =
        $signed({1'b0, block_width_r[5:0]}) - 7'sd1;
    wire signed [5:0] block_y_span_w =
        $signed({1'b0, block_height_r[4:0]}) - 6'sd1;
    wire signed [39:0] corner10_x_w =
        $signed({{8{block_origin_x_r[31]}}, block_origin_x_r}) +
        $signed(pixel_step_x_r) * block_x_span_w;
    wire signed [39:0] corner10_y_w =
        $signed({{8{block_origin_y_r[31]}}, block_origin_y_r}) +
        $signed(pixel_step_y_r) * block_x_span_w;
    wire signed [39:0] corner01_x_w =
        $signed({{8{block_origin_x_r[31]}}, block_origin_x_r}) +
        $signed(row_step_x_r) * block_y_span_w;
    wire signed [39:0] corner01_y_w =
        $signed({{8{block_origin_y_r[31]}}, block_origin_y_r}) +
        $signed(row_step_y_r) * block_y_span_w;
    wire signed [39:0] corner11_x_w = corner10_x_w +
        ($signed(row_step_x_r) * block_y_span_w);
    wire signed [39:0] corner11_y_w = corner10_y_w +
        ($signed(row_step_y_r) * block_y_span_w);
    reg signed [32:0] corner00_x_r;
    reg signed [32:0] corner00_y_r;
    reg signed [32:0] corner10_x_r;
    reg signed [32:0] corner10_y_r;
    reg signed [32:0] corner01_x_r;
    reg signed [32:0] corner01_y_r;
    reg signed [32:0] corner11_x_r;
    reg signed [32:0] corner11_y_r;

    reg signed [32:0] bbox_min_x_w;
    reg signed [32:0] bbox_max_x_w;
    reg signed [32:0] bbox_min_y_w;
    reg signed [32:0] bbox_max_y_w;
    reg signed [32:0] bbox_min_x_r;
    reg signed [32:0] bbox_max_x_r;
    reg signed [32:0] bbox_min_y_r;
    reg signed [32:0] bbox_max_y_r;
    reg fetch_valid_r;
    reg [15:0] fetch_x_base_r;
    reg [15:0] fetch_x_end_r;
    reg [15:0] fetch_y_base_r;
    reg [15:0] fetch_y_end_r;

    wire [16:0] fetch_width_beats_full_w =
        ({1'b0, fetch_x_end_r} - {1'b0, fetch_x_base_r} + 17'd16)
        >> 4;
    wire [16:0] fetch_height_full_w =
        {1'b0, fetch_y_end_r} - {1'b0, fetch_y_base_r} + 17'd1;
    wire fetch_size_legal_w = !fetch_valid_r ||
        ((fetch_width_beats_full_w >= 17'd1) &&
         (fetch_width_beats_full_w <= 17'd4) &&
         (fetch_height_full_w >= 17'd1) &&
         (fetch_height_full_w <= 17'd64));

    always @(*) begin
        bbox_min_x_w = corner00_x_r;
        bbox_max_x_w = corner00_x_r;
        bbox_min_y_w = corner00_y_r;
        bbox_max_y_w = corner00_y_r;
        if (corner10_x_r < bbox_min_x_w)
            bbox_min_x_w = corner10_x_r;
        if (corner10_x_r > bbox_max_x_w)
            bbox_max_x_w = corner10_x_r;
        if (corner01_x_r < bbox_min_x_w)
            bbox_min_x_w = corner01_x_r;
        if (corner01_x_r > bbox_max_x_w)
            bbox_max_x_w = corner01_x_r;
        if (corner11_x_r < bbox_min_x_w)
            bbox_min_x_w = corner11_x_r;
        if (corner11_x_r > bbox_max_x_w)
            bbox_max_x_w = corner11_x_r;

        if (corner10_y_r < bbox_min_y_w)
            bbox_min_y_w = corner10_y_r;
        if (corner10_y_r > bbox_max_y_w)
            bbox_max_y_w = corner10_y_r;
        if (corner01_y_r < bbox_min_y_w)
            bbox_min_y_w = corner01_y_r;
        if (corner01_y_r > bbox_max_y_w)
            bbox_max_y_w = corner01_y_r;
        if (corner11_y_r < bbox_min_y_w)
            bbox_min_y_w = corner11_y_r;
        if (corner11_y_r > bbox_max_y_w)
            bbox_max_y_w = corner11_y_r;
    end

    wire patch_req_valid_w = state_r == STATE_PATCH_REQ;
    wire patch_req_ready_w;
    wire patch_wr_en_w;
    wire [1:0] patch_wr_column_w;
    wire [5:0] patch_wr_row_w;
    wire [255:0] patch_wr_data_w;
    wire patch_done_w;
    wire patch_error_w;

    edrv32_geometry_axi_patch_reader u_patch_reader (
        .clk_i(clk_i), .rst_n_i(rst_n_i),
        .req_valid_i(patch_req_valid_w),
        .req_ready_o(patch_req_ready_w),
        .req_surface_base_i(surface_base_r),
        .req_stride_i(surface_stride_r),
        .req_x_base_i(patch_x_base_r),
        .req_y_base_i(patch_y_base_r),
        .req_width_beats_i(patch_width_beats_r),
        .req_height_i(patch_height_r),
        .patch_wr_en_o(patch_wr_en_w),
        .patch_wr_column_o(patch_wr_column_w),
        .patch_wr_row_o(patch_wr_row_w),
        .patch_wr_data_o(patch_wr_data_w),
        .done_o(patch_done_w), .error_o(patch_error_w),
        .m_arid_o(m_arid_o), .m_araddr_o(m_araddr_o),
        .m_arlen_o(m_arlen_o), .m_arsize_o(m_arsize_o),
        .m_arburst_o(m_arburst_o), .m_arqos_o(m_arqos_o),
        .m_arvalid_o(m_arvalid_o), .m_arready_i(m_arready_i),
        .m_rid_i(m_rid_i), .m_rdata_i(m_rdata_i),
        .m_rresp_i(m_rresp_i), .m_rlast_i(m_rlast_i),
        .m_rvalid_i(m_rvalid_i), .m_rready_o(m_rready_o)
    );

    wire signed [15:0] proc_src_x_w = proc_sample_x_r[31:16];
    wire signed [15:0] proc_src_y_w = proc_sample_y_r[31:16];
    // The source crop itself is the transformed image boundary.  An
    // unrotated destination rectangle would clip valid rotated corners.
    wire proc_inside_w = !proc_src_x_w[15] && !proc_src_y_w[15] &&
        ($unsigned(proc_src_x_w) >= crop_x_r) &&
        ($unsigned(proc_src_x_w) <= crop_right_w) &&
        ($unsigned(proc_src_y_w) >= crop_y_r) &&
        ($unsigned(proc_src_y_w) <= crop_bottom_w);
    wire [15:0] proc_src_x1_w =
        $unsigned(proc_src_x_w) == crop_right_w ?
        $unsigned(proc_src_x_w) : $unsigned(proc_src_x_w) + 1'b1;
    wire [15:0] proc_src_y1_w =
        $unsigned(proc_src_y_w) == crop_bottom_w ?
        $unsigned(proc_src_y_w) : $unsigned(proc_src_y_w) + 1'b1;
    wire [15:0] proc_local_x0_w =
        $unsigned(proc_src_x_w) - patch_x_base_r;
    wire [15:0] proc_local_x1_w = proc_src_x1_w - patch_x_base_r;
    wire [15:0] proc_local_y0_w =
        $unsigned(proc_src_y_w) - patch_y_base_r;
    wire [15:0] proc_local_y1_w = proc_src_y1_w - patch_y_base_r;
    wire patch_rd_en_w = (state_r == STATE_PROC_ISSUE) && proc_inside_w;
    wire [5:0] patch_rd_row0_w = proc_local_y0_w[5:0];
    wire [5:0] patch_rd_row1_w = proc_local_y1_w[5:0];
    wire [255:0] patch_col0_row0_w;
    wire [255:0] patch_col0_row1_w;
    wire [255:0] patch_col1_row0_w;
    wire [255:0] patch_col1_row1_w;
    wire [255:0] patch_col2_row0_w;
    wire [255:0] patch_col2_row1_w;
    wire [255:0] patch_col3_row0_w;
    wire [255:0] patch_col3_row1_w;

    edrv32_geometry_patch_ram u_patch_ram (
        .clk_i(clk_i), .rst_n_i(rst_n_i),
        .wr_en_i(patch_wr_en_w), .wr_column_i(patch_wr_column_w),
        .wr_row_i(patch_wr_row_w), .wr_data_i(patch_wr_data_w),
        .rd_en_i(patch_rd_en_w),
        .rd_row0_i(patch_rd_row0_w), .rd_row1_i(patch_rd_row1_w),
        .rd_col0_row0_o(patch_col0_row0_w),
        .rd_col0_row1_o(patch_col0_row1_w),
        .rd_col1_row0_o(patch_col1_row0_w),
        .rd_col1_row1_o(patch_col1_row1_w),
        .rd_col2_row0_o(patch_col2_row0_w),
        .rd_col2_row1_o(patch_col2_row1_w),
        .rd_col3_row0_o(patch_col3_row0_w),
        .rd_col3_row1_o(patch_col3_row1_w)
    );

    wire [255:0] sample_word00_w = select_column_row0(
        sample_col0_r, patch_col0_row0_w, patch_col1_row0_w,
        patch_col2_row0_w, patch_col3_row0_w);
    wire [255:0] sample_word10_w = select_column_row0(
        sample_col1_r, patch_col0_row0_w, patch_col1_row0_w,
        patch_col2_row0_w, patch_col3_row0_w);
    wire [255:0] sample_word01_w = select_column_row0(
        sample_col0_r, patch_col0_row1_w, patch_col1_row1_w,
        patch_col2_row1_w, patch_col3_row1_w);
    wire [255:0] sample_word11_w = select_column_row0(
        sample_col1_r, patch_col0_row1_w, patch_col1_row1_w,
        patch_col2_row1_w, patch_col3_row1_w);

    wire bilinear_sample_valid_w = state_r == STATE_PROC_SEND;
    wire bilinear_sample_ready_w;
    wire bilinear_pixel_valid_w;
    wire [15:0] bilinear_pixel_data_w;
    wire [15:0] bilinear_pixel_x_w;
    wire [15:0] bilinear_pixel_y_w;
    wire bilinear_pixel_sof_w;
    wire bilinear_pixel_eol_w;
    wire bilinear_pixel_eof_w;

    edrv32_geometry_bilinear u_bilinear (
        .clk_i(clk_i), .rst_n_i(rst_n_i),
        .sample_valid_i(bilinear_sample_valid_w),
        .sample_ready_o(bilinear_sample_ready_w),
        .sample_p00_i(select_pixel(sample_word00_w, sample_lane0_r)),
        .sample_p10_i(select_pixel(sample_word10_w, sample_lane1_r)),
        .sample_p01_i(select_pixel(sample_word01_w, sample_lane0_r)),
        .sample_p11_i(select_pixel(sample_word11_w, sample_lane1_r)),
        .sample_frac_x_i(sample_frac_x_r),
        .sample_frac_y_i(sample_frac_y_r),
        .sample_in_bounds_i(sample_in_bounds_r),
        .sample_fill_pixel_i(fill_pixel_r),
        .sample_dst_x_i(sample_dst_x_r),
        .sample_dst_y_i(sample_dst_y_r),
        .sample_sof_i(sample_sof_r),
        .sample_eol_i(sample_eol_r),
        .sample_eof_i(sample_eof_r),
        .pixel_valid_o(bilinear_pixel_valid_w),
        .pixel_ready_i(1'b1),
        .pixel_data_o(bilinear_pixel_data_w),
        .pixel_dst_x_o(bilinear_pixel_x_w),
        .pixel_dst_y_o(bilinear_pixel_y_w),
        .pixel_sof_o(bilinear_pixel_sof_w),
        .pixel_eol_o(bilinear_pixel_eol_w),
        .pixel_eof_o(bilinear_pixel_eof_w)
    );

    wire [15:0] beats_per_row_w = (dst_width_r + 16'd15) >> 4;
    wire [15:0] band_local_y_w = bilinear_pixel_y_w - band_y_r;
    wire [26:0] band_write_addr_full_w =
        band_local_y_w * beats_per_row_w +
        {11'b0, bilinear_pixel_x_w[15:4]};
    wire [255:0] band_next_pack_w = band_pack_r |
        ({{240{1'b0}}, bilinear_pixel_data_w} <<
         {bilinear_pixel_x_w[3:0], 4'b0});
    wire band_beat_complete_w = bilinear_pixel_valid_w &&
        ((bilinear_pixel_x_w[3:0] == 4'd15) ||
         (bilinear_pixel_x_w == dst_width_r - 1'b1));
    wire band_wr_en_w = band_beat_complete_w;
    wire [10:0] band_wr_addr_w = band_write_addr_full_w[10:0];

    wire [26:0] band_read_addr_full_w =
        drain_row_r * beats_per_row_w + drain_beat_r;
    wire band_rd_en_w = state_r == STATE_DRAIN_REQ;
    wire [255:0] band_rd_data_w;

    edrv32_geometry_band_ram u_band_ram (
        .clk_i(clk_i), .rst_n_i(rst_n_i),
        .wr_en_i(band_wr_en_w), .wr_addr_i(band_wr_addr_w),
        .wr_data_i(band_next_pack_w),
        .rd_en_i(band_rd_en_w),
        .rd_addr_i(band_read_addr_full_w[10:0]),
        .rd_data_o(band_rd_data_w)
    );

    wire [15:0] drain_x_w = {drain_beat_r[11:0], 4'b0} + drain_lane_r;
    wire [15:0] drain_y_w = band_y_r + drain_row_r;
    wire drain_fire_w = pixel_valid_o && pixel_ready_i;
    wire drain_beat_last_w = (drain_lane_r == 4'd15) ||
        (drain_x_w == dst_width_r - 1'b1);
    wire drain_row_last_w = drain_beat_r == beats_per_row_w - 1'b1;
    wire drain_band_last_w = drain_row_r == block_height_r - 1'b1;
    wire drain_frame_last_w = drain_band_last_w &&
        ((band_y_r + block_height_r) == dst_height_r);

    assign cfg_ready_o = (state_r == STATE_IDLE) && !config_busy_w;
    assign pixel_valid_o = state_r == STATE_DRAIN_SEND;
    assign pixel_data_o = select_pixel(band_rd_data_w, drain_lane_r);
    assign pixel_dst_x_o = drain_x_w;
    assign pixel_dst_y_o = drain_y_w;
    assign pixel_sof_o = pixel_valid_o && (drain_x_w == 0) &&
        (drain_y_w == 0);
    assign pixel_eol_o = pixel_valid_o &&
        (drain_x_w == dst_width_r - 1'b1);
    assign pixel_eof_o = pixel_eol_o &&
        (drain_y_w == dst_height_r - 1'b1);
    assign busy_o = state_r != STATE_IDLE;
    assign done_o = done_r;
    // The reader keeps its last error until the next Patch request.  Only
    // report the engine's frame-local latched error across frame boundaries.
    assign error_o = error_r;
    assign profile_phase_o =
        ((state_r == STATE_BLOCK_PREP) ||
         (state_r == STATE_BBOX_CORNERS) ||
         (state_r == STATE_BBOX_EXTREMA) ||
         (state_r == STATE_BBOX_CLIP) ||
         (state_r == STATE_BBOX_CHECK)) ? 3'd1 :
        ((state_r == STATE_PATCH_REQ) ||
         (state_r == STATE_PATCH_WAIT)) ? 3'd2 :
        ((state_r == STATE_PROC_START) ||
         (state_r == STATE_PROC_ISSUE) ||
         (state_r == STATE_PROC_SEND) ||
         (state_r == STATE_PROC_WAIT)) ? 3'd3 :
        ((state_r == STATE_DRAIN_REQ) ||
         (state_r == STATE_DRAIN_SEND)) ? 3'd4 :
        (state_r == STATE_CONFIG) ? 3'd5 : 3'd0;

    wire bilinear_sample_fire_w = bilinear_sample_valid_w &&
        bilinear_sample_ready_w;
    wire proc_issue_last_w = (proc_x_r == block_width_r - 1'b1) &&
        (proc_y_r == block_height_r - 1'b1);
    wire [31:0] block_pixel_count_w = block_width_r * block_height_r;
    wire block_output_last_w = bilinear_pixel_valid_w &&
        (block_output_count_r == block_pixel_count_w - 1'b1);
    wire block_is_last_w =
        (block_x_r + block_width_r) == dst_width_r;

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            state_r <= STATE_IDLE;
            done_r <= 1'b0;
            error_r <= 1'b0;
            surface_base_r <= 32'b0;
            surface_stride_r <= 32'b0;
            crop_x_r <= 16'b0;
            crop_y_r <= 16'b0;
            crop_width_r <= 16'b0;
            crop_height_r <= 16'b0;
            dst_width_r <= 16'b0;
            dst_height_r <= 16'b0;
            block_width_limit_r <= BLOCK_WIDTH;
            fill_pixel_r <= 16'b0;
            origin_x_r <= 32'sb0;
            origin_y_r <= 32'sb0;
            pixel_step_x_r <= 32'sb0;
            pixel_step_y_r <= 32'sb0;
            row_step_x_r <= 32'sb0;
            row_step_y_r <= 32'sb0;
            band_origin_x_r <= 32'sb0;
            band_origin_y_r <= 32'sb0;
            block_origin_x_r <= 32'sb0;
            block_origin_y_r <= 32'sb0;
            band_y_r <= 16'b0;
            block_x_r <= 16'b0;
            block_width_r <= 16'b0;
            block_height_r <= 16'b0;
            corner00_x_r <= 33'sb0;
            corner00_y_r <= 33'sb0;
            corner10_x_r <= 33'sb0;
            corner10_y_r <= 33'sb0;
            corner01_x_r <= 33'sb0;
            corner01_y_r <= 33'sb0;
            corner11_x_r <= 33'sb0;
            corner11_y_r <= 33'sb0;
            bbox_min_x_r <= 33'sb0;
            bbox_max_x_r <= 33'sb0;
            bbox_min_y_r <= 33'sb0;
            bbox_max_y_r <= 33'sb0;
            fetch_valid_r <= 1'b0;
            fetch_x_base_r <= 16'b0;
            fetch_x_end_r <= 16'b0;
            fetch_y_base_r <= 16'b0;
            fetch_y_end_r <= 16'b0;
            patch_x_base_r <= 16'b0;
            patch_y_base_r <= 16'b0;
            patch_width_beats_r <= 3'b0;
            patch_height_r <= 7'b0;
            proc_x_r <= 16'b0;
            proc_y_r <= 16'b0;
            proc_row_x_r <= 32'sb0;
            proc_row_y_r <= 32'sb0;
            proc_sample_x_r <= 32'sb0;
            proc_sample_y_r <= 32'sb0;
            block_output_count_r <= 16'b0;
            sample_in_bounds_r <= 1'b0;
            sample_frac_x_r <= 16'b0;
            sample_frac_y_r <= 16'b0;
            sample_dst_x_r <= 16'b0;
            sample_dst_y_r <= 16'b0;
            sample_sof_r <= 1'b0;
            sample_eol_r <= 1'b0;
            sample_eof_r <= 1'b0;
            sample_col0_r <= 2'b0;
            sample_col1_r <= 2'b0;
            sample_lane0_r <= 4'b0;
            sample_lane1_r <= 4'b0;
            band_pack_r <= 256'b0;
            drain_row_r <= 16'b0;
            drain_beat_r <= 16'b0;
            drain_lane_r <= 4'b0;
        end else begin
            done_r <= 1'b0;

            if (config_start_w) begin
                surface_base_r <= cfg_surface_base_i;
                surface_stride_r <= cfg_surface_stride_i;
                crop_x_r <= cfg_crop_x_i;
                crop_y_r <= cfg_crop_y_i;
                crop_width_r <= cfg_crop_width_i;
                crop_height_r <= cfg_crop_height_i;
                dst_width_r <= cfg_dst_width_i;
                dst_height_r <= cfg_dst_height_i;
                // At 75% or larger, a 32x16 destination block still fits
                // the 64x64 source patch at any angle.  Stronger shrink
                // uses 16x16 blocks to bound the source footprint.
                block_width_limit_r <=
                    (image_x_quarters_w < crop_x_three_w) ||
                    (image_y_quarters_w < crop_y_three_w) ?
                    16'd16 : BLOCK_WIDTH;
                fill_pixel_r <= cfg_fill_pixel_i;
                error_r <= 1'b0;
                state_r <= STATE_CONFIG;
            end

            if (cfg_start_i && !cfg_ready_o)
                error_r <= 1'b1;

            if ((state_r == STATE_CONFIG) && config_walker_start_w) begin
                origin_x_r <= config_origin_x_w;
                origin_y_r <= config_origin_y_w;
                pixel_step_x_r <= config_pixel_step_x_w;
                pixel_step_y_r <= config_pixel_step_y_w;
                row_step_x_r <= config_row_step_x_w;
                row_step_y_r <= config_row_step_y_w;
                band_origin_x_r <= config_origin_x_w;
                band_origin_y_r <= config_origin_y_w;
                block_origin_x_r <= config_origin_x_w;
                block_origin_y_r <= config_origin_y_w;
                band_y_r <= 16'b0;
                block_x_r <= 16'b0;
                state_r <= STATE_BLOCK_PREP;
            end

            if ((state_r == STATE_CONFIG) && config_done_w &&
                config_error_w) begin
                error_r <= 1'b1;
                done_r <= 1'b1;
                state_r <= STATE_IDLE;
            end

            if (state_r == STATE_BLOCK_PREP) begin
                block_width_r <= block_width_w;
                block_height_r <= block_height_w;
                block_output_count_r <= 16'b0;
                band_pack_r <= 256'b0;
                state_r <= STATE_BBOX_CORNERS;
            end

            if (state_r == STATE_BBOX_CORNERS) begin
                corner00_x_r <= $signed(block_origin_x_r) >>> 16;
                corner00_y_r <= $signed(block_origin_y_r) >>> 16;
                corner10_x_r <= corner10_x_w >>> 16;
                corner10_y_r <= corner10_y_w >>> 16;
                corner01_x_r <= corner01_x_w >>> 16;
                corner01_y_r <= corner01_y_w >>> 16;
                corner11_x_r <= corner11_x_w >>> 16;
                corner11_y_r <= corner11_y_w >>> 16;
                state_r <= STATE_BBOX_EXTREMA;
            end

            if (state_r == STATE_BBOX_EXTREMA) begin
                bbox_min_x_r <= bbox_min_x_w;
                bbox_max_x_r <= bbox_max_x_w;
                bbox_min_y_r <= bbox_min_y_w;
                bbox_max_y_r <= bbox_max_y_w;
                state_r <= STATE_BBOX_CLIP;
            end

            if (state_r == STATE_BBOX_CLIP) begin
                fetch_valid_r <=
                    (bbox_max_x_r >= $signed({1'b0, crop_x_r})) &&
                    (bbox_min_x_r <= $signed({1'b0, crop_right_w})) &&
                    (bbox_max_y_r >= $signed({1'b0, crop_y_r})) &&
                    (bbox_min_y_r <= $signed({1'b0, crop_bottom_w}));
                fetch_x_base_r <=
                    (bbox_min_x_r < $signed({1'b0, crop_x_r})) ?
                    {crop_x_r[15:4], 4'b0} :
                    {bbox_min_x_r[15:4], 4'b0};
                fetch_x_end_r <=
                    ((bbox_max_x_r + 33'sd1) >
                     $signed({1'b0, crop_right_w})) ?
                    crop_right_w : bbox_max_x_r[15:0] + 1'b1;
                fetch_y_base_r <=
                    (bbox_min_y_r < $signed({1'b0, crop_y_r})) ?
                    crop_y_r : bbox_min_y_r[15:0];
                fetch_y_end_r <=
                    ((bbox_max_y_r + 33'sd1) >
                     $signed({1'b0, crop_bottom_w})) ?
                    crop_bottom_w : bbox_max_y_r[15:0] + 1'b1;
                state_r <= STATE_BBOX_CHECK;
            end

            if (state_r == STATE_BBOX_CHECK) begin
                patch_x_base_r <= fetch_x_base_r;
                patch_y_base_r <= fetch_y_base_r;
                patch_width_beats_r <= fetch_width_beats_full_w[2:0];
                patch_height_r <= fetch_height_full_w[6:0];
                if (!fetch_size_legal_w) begin
                    error_r <= 1'b1;
                    done_r <= 1'b1;
                    state_r <= STATE_IDLE;
                end else if (fetch_valid_r) begin
                    state_r <= STATE_PATCH_REQ;
                end else begin
                    state_r <= STATE_PROC_START;
                end
            end

            if ((state_r == STATE_PATCH_REQ) && patch_req_ready_w)
                state_r <= STATE_PATCH_WAIT;

            if ((state_r == STATE_PATCH_WAIT) && patch_done_w) begin
                if (patch_error_w) begin
                    error_r <= 1'b1;
                    done_r <= 1'b1;
                    state_r <= STATE_IDLE;
                end else begin
                    state_r <= STATE_PROC_START;
                end
            end

            if (state_r == STATE_PROC_START) begin
                proc_x_r <= 16'b0;
                proc_y_r <= 16'b0;
                proc_row_x_r <= block_origin_x_r;
                proc_row_y_r <= block_origin_y_r;
                proc_sample_x_r <= block_origin_x_r;
                proc_sample_y_r <= block_origin_y_r;
                block_output_count_r <= 16'b0;
                state_r <= STATE_PROC_ISSUE;
            end

            if (state_r == STATE_PROC_ISSUE) begin
                sample_in_bounds_r <= proc_inside_w;
                sample_frac_x_r <= proc_sample_x_r[15:0];
                sample_frac_y_r <= proc_sample_y_r[15:0];
                sample_dst_x_r <= block_x_r + proc_x_r;
                sample_dst_y_r <= band_y_r + proc_y_r;
                sample_sof_r <= (block_x_r == 0) && (band_y_r == 0) &&
                    (proc_x_r == 0) && (proc_y_r == 0);
                sample_eol_r <=
                    (block_x_r + proc_x_r) == dst_width_r - 1'b1;
                sample_eof_r <=
                    ((block_x_r + proc_x_r) == dst_width_r - 1'b1) &&
                    ((band_y_r + proc_y_r) == dst_height_r - 1'b1);
                sample_col0_r <= proc_local_x0_w[5:4];
                sample_col1_r <= proc_local_x1_w[5:4];
                sample_lane0_r <= proc_local_x0_w[3:0];
                sample_lane1_r <= proc_local_x1_w[3:0];
                state_r <= STATE_PROC_SEND;
            end

            if (bilinear_sample_fire_w) begin
                if (proc_issue_last_w) begin
                    state_r <= STATE_PROC_WAIT;
                end else if (proc_x_r == block_width_r - 1'b1) begin
                    proc_x_r <= 16'b0;
                    proc_y_r <= proc_y_r + 1'b1;
                    proc_row_x_r <= proc_row_x_r + row_step_x_r;
                    proc_row_y_r <= proc_row_y_r + row_step_y_r;
                    proc_sample_x_r <= proc_row_x_r + row_step_x_r;
                    proc_sample_y_r <= proc_row_y_r + row_step_y_r;
                    state_r <= STATE_PROC_ISSUE;
                end else begin
                    proc_x_r <= proc_x_r + 1'b1;
                    proc_sample_x_r <= proc_sample_x_r + pixel_step_x_r;
                    proc_sample_y_r <= proc_sample_y_r + pixel_step_y_r;
                    state_r <= STATE_PROC_ISSUE;
                end
            end

            if (bilinear_pixel_valid_w) begin
                if (band_beat_complete_w)
                    band_pack_r <= 256'b0;
                else
                    band_pack_r <= band_next_pack_w;

                if (block_output_last_w) begin
                    block_output_count_r <= 16'b0;
                    if (block_is_last_w) begin
                        drain_row_r <= 16'b0;
                        drain_beat_r <= 16'b0;
                        drain_lane_r <= 4'b0;
                        state_r <= STATE_DRAIN_REQ;
                    end else begin
                        block_x_r <= block_x_r + block_width_r;
                        block_origin_x_r <= block_origin_x_r +
                            pixel_step_x_r * $signed({1'b0, block_width_r});
                        block_origin_y_r <= block_origin_y_r +
                            pixel_step_y_r * $signed({1'b0, block_width_r});
                        state_r <= STATE_BLOCK_PREP;
                    end
                end else begin
                    block_output_count_r <= block_output_count_r + 1'b1;
                end
            end

            if (state_r == STATE_DRAIN_REQ)
                state_r <= STATE_DRAIN_SEND;

            if (drain_fire_w) begin
                if (drain_beat_last_w) begin
                    drain_lane_r <= 4'b0;
                    if (drain_row_last_w && drain_band_last_w) begin
                        if (drain_frame_last_w) begin
                            state_r <= STATE_IDLE;
                            done_r <= 1'b1;
                        end else begin
                            band_y_r <= band_y_r + block_height_r;
                            band_origin_x_r <= band_origin_x_r +
                                row_step_x_r *
                                $signed({1'b0, block_height_r});
                            band_origin_y_r <= band_origin_y_r +
                                row_step_y_r *
                                $signed({1'b0, block_height_r});
                            block_origin_x_r <= band_origin_x_r +
                                row_step_x_r *
                                $signed({1'b0, block_height_r});
                            block_origin_y_r <= band_origin_y_r +
                                row_step_y_r *
                                $signed({1'b0, block_height_r});
                            block_x_r <= 16'b0;
                            drain_row_r <= 16'b0;
                            drain_beat_r <= 16'b0;
                            state_r <= STATE_BLOCK_PREP;
                        end
                    end else if (drain_row_last_w) begin
                        drain_row_r <= drain_row_r + 1'b1;
                        drain_beat_r <= 16'b0;
                        state_r <= STATE_DRAIN_REQ;
                    end else begin
                        drain_beat_r <= drain_beat_r + 1'b1;
                        state_r <= STATE_DRAIN_REQ;
                    end
                end else begin
                    drain_lane_r <= drain_lane_r + 1'b1;
                end
            end
        end
    end

endmodule
