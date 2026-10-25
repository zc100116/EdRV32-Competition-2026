// ============================================================================
// File        : edrv32_geometry_engine.v
// Description : DDR Surface to RGB565 geometry processing engine.
// Notes       : Configuration, coordinate walking, tile fill/cache and fixed
//               bilinear sampling operate without CPU participation per frame.
// ============================================================================

module edrv32_geometry_engine (
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
    output wire         error_o
);

    reg engine_busy_r;
    reg engine_done_r;
    reg engine_error_r;
    reg [31:0] surface_base_r;
    reg [31:0] surface_stride_r;
    reg [15:0] src_width_r;
    reg [15:0] src_height_r;
    reg [15:0] crop_x_r;
    reg [15:0] crop_y_r;
    reg [15:0] crop_width_r;
    reg [15:0] crop_height_r;
    reg [15:0] fill_pixel_r;

    wire config_start_w = cfg_start_i && cfg_ready_o;
    wire config_walker_start_w;
    wire [15:0] walker_dst_width_w;
    wire [15:0] walker_dst_height_w;
    wire [15:0] walker_src_width_w;
    wire [15:0] walker_src_height_w;
    wire signed [31:0] walker_origin_x_w;
    wire signed [31:0] walker_origin_y_w;
    wire signed [31:0] walker_pixel_step_x_w;
    wire signed [31:0] walker_pixel_step_y_w;
    wire signed [31:0] walker_row_step_x_w;
    wire signed [31:0] walker_row_step_y_w;
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
        .cfg_image_width_i(cfg_dst_width_i),
        .cfg_image_height_i(cfg_dst_height_i),
        .cfg_angle_i(cfg_angle_i),
        .cfg_flip_x_i(cfg_flip_x_i), .cfg_flip_y_i(cfg_flip_y_i),
        .walker_start_o(config_walker_start_w),
        .walker_dst_width_o(walker_dst_width_w),
        .walker_dst_height_o(walker_dst_height_w),
        .walker_src_width_o(walker_src_width_w),
        .walker_src_height_o(walker_src_height_w),
        .walker_origin_x_o(walker_origin_x_w),
        .walker_origin_y_o(walker_origin_y_w),
        .walker_pixel_step_x_o(walker_pixel_step_x_w),
        .walker_pixel_step_y_o(walker_pixel_step_y_w),
        .walker_row_step_x_o(walker_row_step_x_w),
        .walker_row_step_y_o(walker_row_step_y_w),
        .busy_o(config_busy_w), .done_o(config_done_w),
        .error_o(config_error_w)
    );

    wire coord_valid_w;
    wire coord_ready_w;
    wire [15:0] coord_dst_x_w;
    wire [15:0] coord_dst_y_w;
    wire signed [15:0] coord_src_x_w;
    wire signed [15:0] coord_src_y_w;
    wire [15:0] coord_frac_x_w;
    wire [15:0] coord_frac_y_w;
    wire coord_in_bounds_w;
    wire coord_sof_w;
    wire coord_eol_w;
    wire coord_eof_w;
    wire unused_walker_busy_w;
    wire unused_walker_done_w;
    wire walker_error_w;

    edrv32_geometry_coord_walker u_walker (
        .clk_i(clk_i), .rst_n_i(rst_n_i),
        .cfg_start_i(config_walker_start_w),
        .cfg_dst_width_i(walker_dst_width_w),
        .cfg_dst_height_i(walker_dst_height_w),
        .cfg_src_width_i(walker_src_width_w),
        .cfg_src_height_i(walker_src_height_w),
        .cfg_origin_x_i(walker_origin_x_w),
        .cfg_origin_y_i(walker_origin_y_w),
        .cfg_pixel_step_x_i(walker_pixel_step_x_w),
        .cfg_pixel_step_y_i(walker_pixel_step_y_w),
        .cfg_row_step_x_i(walker_row_step_x_w),
        .cfg_row_step_y_i(walker_row_step_y_w),
        .coord_valid_o(coord_valid_w), .coord_ready_i(coord_ready_w),
        .dst_x_o(coord_dst_x_w), .dst_y_o(coord_dst_y_w),
        .src_x_o(coord_src_x_w), .src_y_o(coord_src_y_w),
        .src_x_frac_o(coord_frac_x_w), .src_y_frac_o(coord_frac_y_w),
        .src_in_bounds_o(coord_in_bounds_w),
        .sof_o(coord_sof_w), .eol_o(coord_eol_w), .eof_o(coord_eof_w),
        .busy_o(unused_walker_busy_w), .done_o(unused_walker_done_w),
        .error_o(walker_error_w)
    );

    wire cache_sample_valid_w;
    wire cache_sample_ready_w;
    wire [15:0] cache_p00_w;
    wire [15:0] cache_p10_w;
    wire [15:0] cache_p01_w;
    wire [15:0] cache_p11_w;
    wire [15:0] cache_frac_x_w;
    wire [15:0] cache_frac_y_w;
    wire cache_in_bounds_w;
    wire [15:0] cache_fill_pixel_w;
    wire [15:0] cache_dst_x_w;
    wire [15:0] cache_dst_y_w;
    wire cache_sof_w;
    wire cache_eol_w;
    wire cache_eof_w;
    wire fill_req_valid_w;
    wire fill_req_ready_w;
    wire [11:0] fill_tile_x_w;
    wire [11:0] fill_tile_y_w;
    wire fill_row_valid_w;
    wire fill_row_ready_w;
    wire [3:0] fill_row_index_w;
    wire [255:0] fill_row_data_w;
    wire fill_done_w;
    wire fill_error_w;
    wire unused_cache_busy_w;
    wire cache_error_w;

    edrv32_geometry_tile_cache u_tile_cache (
        .clk_i(clk_i), .rst_n_i(rst_n_i),
        .flush_i(config_walker_start_w),
        .crop_x_i(crop_x_r), .crop_y_i(crop_y_r),
        .crop_width_i(crop_width_r), .crop_height_i(crop_height_r),
        .fill_pixel_i(fill_pixel_r),
        .coord_valid_i(coord_valid_w), .coord_ready_o(coord_ready_w),
        .coord_src_x_i(coord_src_x_w), .coord_src_y_i(coord_src_y_w),
        .coord_frac_x_i(coord_frac_x_w), .coord_frac_y_i(coord_frac_y_w),
        .coord_in_bounds_i(coord_in_bounds_w),
        .coord_dst_x_i(coord_dst_x_w), .coord_dst_y_i(coord_dst_y_w),
        .coord_sof_i(coord_sof_w), .coord_eol_i(coord_eol_w),
        .coord_eof_i(coord_eof_w),
        .sample_valid_o(cache_sample_valid_w),
        .sample_ready_i(cache_sample_ready_w),
        .sample_p00_o(cache_p00_w), .sample_p10_o(cache_p10_w),
        .sample_p01_o(cache_p01_w), .sample_p11_o(cache_p11_w),
        .sample_frac_x_o(cache_frac_x_w),
        .sample_frac_y_o(cache_frac_y_w),
        .sample_in_bounds_o(cache_in_bounds_w),
        .sample_fill_pixel_o(cache_fill_pixel_w),
        .sample_dst_x_o(cache_dst_x_w), .sample_dst_y_o(cache_dst_y_w),
        .sample_sof_o(cache_sof_w), .sample_eol_o(cache_eol_w),
        .sample_eof_o(cache_eof_w),
        .fill_req_valid_o(fill_req_valid_w),
        .fill_req_ready_i(fill_req_ready_w),
        .fill_req_tile_x_o(fill_tile_x_w),
        .fill_req_tile_y_o(fill_tile_y_w),
        .fill_row_valid_i(fill_row_valid_w),
        .fill_row_ready_o(fill_row_ready_w),
        .fill_row_index_i(fill_row_index_w),
        .fill_row_data_i(fill_row_data_w),
        .fill_done_i(fill_done_w), .fill_error_i(fill_error_w),
        .busy_o(unused_cache_busy_w), .error_o(cache_error_w)
    );

    edrv32_geometry_axi_tile_reader u_tile_reader (
        .clk_i(clk_i), .rst_n_i(rst_n_i),
        .req_valid_i(fill_req_valid_w), .req_ready_o(fill_req_ready_w),
        .req_surface_base_i(surface_base_r),
        .req_stride_i(surface_stride_r),
        .req_src_width_i(src_width_r), .req_src_height_i(src_height_r),
        .req_tile_x_i(fill_tile_x_w), .req_tile_y_i(fill_tile_y_w),
        .row_valid_o(fill_row_valid_w), .row_ready_i(fill_row_ready_w),
        .row_index_o(fill_row_index_w), .row_data_o(fill_row_data_w),
        .done_o(fill_done_w), .error_o(fill_error_w),
        .m_arid_o(m_arid_o), .m_araddr_o(m_araddr_o),
        .m_arlen_o(m_arlen_o), .m_arsize_o(m_arsize_o),
        .m_arburst_o(m_arburst_o), .m_arqos_o(m_arqos_o),
        .m_arvalid_o(m_arvalid_o), .m_arready_i(m_arready_i),
        .m_rid_i(m_rid_i), .m_rdata_i(m_rdata_i),
        .m_rresp_i(m_rresp_i), .m_rlast_i(m_rlast_i),
        .m_rvalid_i(m_rvalid_i), .m_rready_o(m_rready_o)
    );

    edrv32_geometry_bilinear u_bilinear (
        .clk_i(clk_i), .rst_n_i(rst_n_i),
        .sample_valid_i(cache_sample_valid_w),
        .sample_ready_o(cache_sample_ready_w),
        .sample_p00_i(cache_p00_w), .sample_p10_i(cache_p10_w),
        .sample_p01_i(cache_p01_w), .sample_p11_i(cache_p11_w),
        .sample_frac_x_i(cache_frac_x_w),
        .sample_frac_y_i(cache_frac_y_w),
        .sample_in_bounds_i(cache_in_bounds_w),
        .sample_fill_pixel_i(cache_fill_pixel_w),
        .sample_dst_x_i(cache_dst_x_w), .sample_dst_y_i(cache_dst_y_w),
        .sample_sof_i(cache_sof_w), .sample_eol_i(cache_eol_w),
        .sample_eof_i(cache_eof_w),
        .pixel_valid_o(pixel_valid_o), .pixel_ready_i(pixel_ready_i),
        .pixel_data_o(pixel_data_o),
        .pixel_dst_x_o(pixel_dst_x_o), .pixel_dst_y_o(pixel_dst_y_o),
        .pixel_sof_o(pixel_sof_o), .pixel_eol_o(pixel_eol_o),
        .pixel_eof_o(pixel_eof_o)
    );

    wire pixel_fire_w = pixel_valid_o && pixel_ready_i;

    assign cfg_ready_o = !engine_busy_r && !config_busy_w;
    assign busy_o = engine_busy_r;
    assign done_o = engine_done_r;
    assign error_o = engine_error_r;

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            engine_busy_r <= 1'b0;
            engine_done_r <= 1'b0;
            engine_error_r <= 1'b0;
            surface_base_r <= 32'b0;
            surface_stride_r <= 32'b0;
            src_width_r <= 16'b0;
            src_height_r <= 16'b0;
            crop_x_r <= 16'b0;
            crop_y_r <= 16'b0;
            crop_width_r <= 16'b0;
            crop_height_r <= 16'b0;
            fill_pixel_r <= 16'b0;
        end else begin
            engine_done_r <= 1'b0;

            if (config_start_w) begin
                engine_busy_r <= 1'b1;
                engine_error_r <= 1'b0;
                surface_base_r <= cfg_surface_base_i;
                surface_stride_r <= cfg_surface_stride_i;
                src_width_r <= cfg_src_width_i;
                src_height_r <= cfg_src_height_i;
                crop_x_r <= cfg_crop_x_i;
                crop_y_r <= cfg_crop_y_i;
                crop_width_r <= cfg_crop_width_i;
                crop_height_r <= cfg_crop_height_i;
                fill_pixel_r <= cfg_fill_pixel_i;
            end

            if (cfg_start_i && !cfg_ready_o)
                engine_error_r <= 1'b1;

            if (config_done_w && config_error_w) begin
                engine_busy_r <= 1'b0;
                engine_done_r <= 1'b1;
                engine_error_r <= 1'b1;
            end

            if (walker_error_w || cache_error_w || fill_error_w)
                engine_error_r <= 1'b1;

            if (pixel_fire_w && pixel_eof_o) begin
                engine_busy_r <= 1'b0;
                engine_done_r <= 1'b1;
            end
        end
    end

endmodule
