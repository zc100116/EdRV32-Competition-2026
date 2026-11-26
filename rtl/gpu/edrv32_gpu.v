// File: edrv32_gpu.v
// Spec: gpu-spec 3, 5; gpu-microarch 4.2-4.5, 4.12.
// Description: Connect the command, DMA and ordered rendering pipelines.
//              Public buses stay in the GPU domain; SoC owns the CDC bridges.
// Clock domain: clk_gpu_i.
module edrv32_gpu (
    // Clock and reset.
    input wire clk_gpu_i,
    input wire rst_gpu_n_i,

    // APB control interface.
    input wire [11:0] s_apb_paddr_i,
    input wire s_apb_psel_i,
    input wire s_apb_penable_i,
    input wire s_apb_pwrite_i,
    input wire [31:0] s_apb_pwdata_i,
    input wire [3:0] s_apb_pstrb_i,
    output wire s_apb_pready_o,
    output wire [31:0] s_apb_prdata_o,
    output wire s_apb_pslverr_o,

    // AXI256 DDR interface.
    output wire m_axi_awid_o,
    output wire [31:0] m_axi_awaddr_o,
    output wire [3:0] m_axi_awlen_o,
    output wire m_axi_awvalid_o,
    input wire m_axi_awready_i,
    output wire [255:0] m_axi_wdata_o,
    output wire [31:0] m_axi_wstrb_o,
    output wire m_axi_wlast_o,
    output wire m_axi_wvalid_o,
    input wire m_axi_wready_i,
    input wire m_axi_bid_i,
    input wire [1:0] m_axi_bresp_i,
    input wire m_axi_bvalid_i,
    output wire m_axi_bready_o,
    output wire m_axi_arid_o,
    output wire [31:0] m_axi_araddr_o,
    output wire [3:0] m_axi_arlen_o,
    output wire m_axi_arvalid_o,
    input wire m_axi_arready_i,
    input wire m_axi_rid_i,
    input wire [255:0] m_axi_rdata_i,
    input wire [1:0] m_axi_rresp_i,
    input wire m_axi_rlast_i,
    input wire m_axi_rvalid_i,
    output wire m_axi_rready_o,

    // Completion and error interrupt.
    output wire irq_o
);

    // Local inter-unit streams and command lifetime levels.
    wire abort_w;
    wire busy_w;
    wire [255:0] clear_command_w;
    wire clear_ready_w;
    wire [255:0] clear_target_w;
    wire clear_valid_w;
    wire clear_wide_w;
    wire [255:0] command_read_data_data_w;
    wire [31:0] command_read_data_keep_w;
    wire command_read_data_last_w;
    wire command_read_data_ready_w;
    wire command_read_data_valid_w;
    wire [31:0] command_read_req_addr_w;
    wire [31:0] command_read_req_bytes_w;
    wire command_read_req_ready_w;
    wire command_read_req_valid_w;
    wire [159:0] current_read_data_w;
    wire current_read_en_w;
    wire [63:0] current_read_idx_w;
    wire [31:0] desc_base_w;
    wire [15:0] desc_count_w;
    wire dma_start_w;
    wire done_w;
    wire enable_w;
    wire [31:0] err_code_w;
    wire error_w;
    wire [255:0] free_write_data_data_w;
    wire [31:0] free_write_data_keep_w;
    wire free_write_data_last_w;
    wire free_write_data_ready_w;
    wire free_write_data_valid_w;
    wire free_write_done_w;
    wire [31:0] free_write_req_addr_w;
    wire [31:0] free_write_req_bytes_w;
    wire free_write_req_ready_w;
    wire free_write_req_valid_w;
    wire [79:0] full_read_data_w;
    wire full_read_en_w;
    wire [47:0] full_read_idx_w;
    wire [95:0] geometry_cfg_light_w;
    wire [511:0] geometry_cfg_matrix_w;
    wire [255:0] geometry_cfg_pixel_w;
    wire geometry_cfg_ready_w;
    wire [255:0] geometry_cfg_target_w;
    wire geometry_cfg_valid_w;
    wire geometry_cfg_wide_w;
    wire [255:0] geometry_draw_command_w;
    wire geometry_draw_ready_w;
    wire geometry_draw_valid_w;
    wire geometry_finish_w;
    wire geometry_unit_done_w;
    wire [255:0] hit_write_data_data_w;
    wire [31:0] hit_write_data_keep_w;
    wire hit_write_data_last_w;
    wire hit_write_data_ready_w;
    wire hit_write_data_valid_w;
    wire hit_write_done_w;
    wire [31:0] hit_write_req_addr_w;
    wire [31:0] hit_write_req_bytes_w;
    wire hit_write_req_ready_w;
    wire hit_write_req_valid_w;
    wire [511:0] matrix_data_w;
    wire [255:0] matrix_read_data_data_w;
    wire [31:0] matrix_read_data_keep_w;
    wire matrix_read_data_last_w;
    wire matrix_read_data_ready_w;
    wire matrix_read_data_valid_w;
    wire [31:0] matrix_read_req_addr_w;
    wire [31:0] matrix_read_req_bytes_w;
    wire matrix_read_req_ready_w;
    wire matrix_read_req_valid_w;
    wire matrix_ready_w;
    wire matrix_valid_w;
    wire [31:0] object_cfg_free_base_w;
    wire [23:0] object_cfg_free_max_w;
    wire [31:0] object_cfg_hit_base_w;
    wire [23:0] object_cfg_hit_max_w;
    wire [63:0] object_cfg_live_w;
    wire object_cfg_ready_w;
    wire object_cfg_request_w;
    wire [511:0] object_cfg_targets_w;
    wire object_cfg_valid_w;
    wire object_configured_w;
    wire [255:0] object_draw_command_w;
    wire object_draw_ready_w;
    wire object_draw_valid_w;
    wire object_event_free_w;
    wire [7:0] object_event_hit_w;
    wire [23:0] object_event_idx_w;
    wire object_event_ready_w;
    wire object_event_valid_w;
    wire object_finish_w;
    wire object_publish_w;
    wire object_published_w;
    wire [127:0] object_quad_data_w;
    wire object_quad_ready_w;
    wire object_quad_valid_w;
    wire [16:0] object_quad_x_w;
    wire [16:0] object_quad_y_w;
    wire [255:0] object_read_data_data_w;
    wire object_read_data_ready_w;
    wire object_read_data_valid_w;
    wire object_read_done_w;
    wire [31:0] object_read_req_addr_w;
    wire [31:0] object_read_req_bytes_w;
    wire object_read_req_ready_w;
    wire object_read_req_valid_w;
    wire [255:0] object_record_data_w;
    wire [23:0] object_record_idx_w;
    wire object_record_ready_w;
    wire object_record_valid_w;
    wire [23:0] object_result_alive_count_w;
    wire [23:0] object_result_free_count_w;
    wire [23:0] object_result_hit_count_w;
    wire [1:0] object_result_overflow_w;
    wire object_result_ready_w;
    wire object_result_valid_w;
    wire object_unit_done_w;
    wire [255:0] object_update_data_w;
    wire [23:0] object_update_idx_w;
    wire object_update_ready_w;
    wire object_update_valid_w;
    wire [255:0] object_write_data_data_w;
    wire [31:0] object_write_data_keep_w;
    wire object_write_data_last_w;
    wire object_write_data_ready_w;
    wire object_write_data_valid_w;
    wire object_write_done_w;
    wire [31:0] object_write_req_addr_w;
    wire [31:0] object_write_req_bytes_w;
    wire object_write_req_ready_w;
    wire object_write_req_valid_w;
    wire [255:0] pack_command_w;
    wire pack_done_w;
    wire pack_ready_w;
    wire pack_valid_w;
    wire palette_done_w;
    wire [19:0] palette_load_data_w;
    wire [11:0] palette_load_idx_w;
    wire palette_load_ready_w;
    wire palette_load_valid_w;
    wire [3:0] palette_prepare_group_w;
    wire palette_prepare_ready_w;
    wire palette_prepare_valid_w;
    wire palette_prepared_ready_w;
    wire palette_prepared_valid_w;
    wire [255:0] palette_read_data_data_w;
    wire [31:0] palette_read_data_keep_w;
    wire palette_read_data_last_w;
    wire palette_read_data_ready_w;
    wire palette_read_data_valid_w;
    wire [31:0] palette_read_req_addr_w;
    wire [31:0] palette_read_req_bytes_w;
    wire palette_read_req_ready_w;
    wire palette_read_req_valid_w;
    wire perf_object_busy_w;
    wire [2:0] perf_pixel_count_w;
    wire perf_quad_w;
    wire perf_read_wait_w;
    wire perf_resolve_busy_w;
    wire perf_texture_stall_w;
    wire perf_triangle_w;
    wire perf_vertex_w;
    wire perspective_finish_w;
    wire perspective_unit_done_w;
    wire pixel_finish_w;
    wire [255:0] pixel_render_state_pixel_w;
    wire pixel_render_state_ready_w;
    wire [255:0] pixel_render_state_target_w;
    wire [255:0] pixel_render_state_tex_w;
    wire pixel_render_state_valid_w;
    wire pixel_render_state_wide_w;
    wire pixel_unit_done_w;
    wire [255:0] quad_draw_command_w;
    wire quad_draw_ready_w;
    wire quad_draw_valid_w;
    wire quad_finish_w;
    wire [7:0] quad_sample_alpha_w;
    wire [95:0] quad_sample_color_w;
    wire [63:0] quad_sample_depth_w;
    wire [3:0] quad_sample_mask_w;
    wire [3:0] quad_sample_palette_w;
    wire quad_sample_quad_w;
    wire [383:0] quad_sample_span_w;
    wire [127:0] quad_sample_u_w;
    wire [127:0] quad_sample_v_w;
    wire [15:0] quad_sample_x_w;
    wire [15:0] quad_sample_y_w;
    wire quad_sample_ready_w;
    wire quad_sample_valid_w;
    wire [7:0] perspective_sample_alpha_w;
    wire [95:0] perspective_sample_color_w;
    wire [63:0] perspective_sample_depth_w;
    wire [3:0] perspective_sample_mask_w;
    wire [3:0] perspective_sample_palette_w;
    wire perspective_sample_quad_w;
    wire [383:0] perspective_sample_span_w;
    wire [127:0] perspective_sample_u_w;
    wire [127:0] perspective_sample_v_w;
    wire [15:0] perspective_sample_x_w;
    wire [15:0] perspective_sample_y_w;
    wire perspective_sample_ready_w;
    wire perspective_sample_valid_w;
    wire [255:0] quad_read_data_data_w;
    wire [31:0] quad_read_data_keep_w;
    wire quad_read_data_last_w;
    wire quad_read_data_ready_w;
    wire quad_read_data_valid_w;
    wire [31:0] quad_read_req_addr_w;
    wire [31:0] quad_read_req_bytes_w;
    wire quad_read_req_ready_w;
    wire quad_read_req_valid_w;
    wire [127:0] quad_record_data_w;
    wire quad_record_ready_w;
    wire quad_record_valid_w;
    wire [255:0] quad_render_state_pixel_w;
    wire quad_render_state_ready_w;
    wire [255:0] quad_render_state_target_w;
    wire [255:0] quad_render_state_tex_w;
    wire quad_render_state_valid_w;
    wire quad_render_state_wide_w;
    wire quad_unit_done_w;
    wire [255:0] raster_draw_command_w;
    wire raster_draw_ready_w;
    wire raster_draw_valid_w;
    wire raster_finish_w;
    wire [7:0] raster_fragment_alpha_w;
    wire [69:0] raster_fragment_h_w;
    wire [1:0] raster_fragment_mask_w;
    wire [3:0] raster_fragment_palette_w;
    wire [867:0] raster_fragment_plane_w;
    wire raster_fragment_ready_w;
    wire raster_fragment_valid_w;
    wire [15:0] raster_fragment_x_w;
    wire [15:0] raster_fragment_y_w;
    wire [255:0] raster_render_state_pixel_w;
    wire raster_render_state_ready_w;
    wire [255:0] raster_render_state_target_w;
    wire [255:0] raster_render_state_tex_w;
    wire raster_render_state_valid_w;
    wire raster_render_state_wide_w;
    wire raster_unit_done_w;
    wire read_dma_error_w;
    wire read_dma_idle_w;
    wire [63:0] resolve_color_data_w;
    wire resolve_color_ready_w;
    wire resolve_color_valid_w;
    wire [255:0] resolve_command_w;
    wire resolve_finish_w;
    wire [15:0] resolve_read_addr_w;
    wire resolve_read_ready_w;
    wire resolve_read_valid_w;
    wire resolve_ready_w;
    wire [255:0] resolve_target_w;
    wire resolve_unit_done_w;
    wire resolve_valid_w;
    wire resolve_wide_w;
    wire [255:0] resolve_write_data_data_w;
    wire [31:0] resolve_write_data_keep_w;
    wire resolve_write_data_last_w;
    wire resolve_write_data_ready_w;
    wire resolve_write_data_valid_w;
    wire resolve_write_done_w;
    wire [31:0] resolve_write_req_addr_w;
    wire [31:0] resolve_write_req_bytes_w;
    wire resolve_write_req_ready_w;
    wire resolve_write_req_valid_w;
    wire [7:0] sample_alpha_w;
    wire [95:0] sample_color_w;
    wire [63:0] sample_depth_w;
    wire [3:0] sample_mask_w;
    wire [3:0] sample_palette_w;
    wire sample_quad_w;
    wire sample_ready_w;
    wire [383:0] sample_span_w;
    wire [127:0] sample_u_w;
    wire [127:0] sample_v_w;
    wire sample_valid_w;
    wire [15:0] sample_x_w;
    wire [15:0] sample_y_w;
    wire [215:0] screen_triangle_color_w;
    wire [47:0] screen_triangle_depth_w;
    wire [104:0] screen_triangle_q_w;
    wire screen_triangle_ready_w;
    wire [152:0] screen_triangle_uq_w;
    wire screen_triangle_valid_w;
    wire [152:0] screen_triangle_vq_w;
    wire [50:0] screen_triangle_x_w;
    wire [50:0] screen_triangle_y_w;
    wire setup_finish_w;
    wire setup_unit_done_w;
    wire [31:0] shaded_alpha_w;
    wire [95:0] shaded_color_w;
    wire [63:0] shaded_depth_w;
    wire [3:0] shaded_mask_w;
    wire shaded_ready_w;
    wire shaded_valid_w;
    wire [15:0] shaded_x_w;
    wire [15:0] shaded_y_w;
    wire soft_rst_w;
    wire start_w;
    wire unused_stop_w;
    wire [15:0] stop_region_w;
    wire target_finish_w;
    wire [159:0] target_old_data_w;
    wire target_old_ready_w;
    wire target_old_valid_w;
    wire [15:0] target_read_addr_w;
    wire target_read_ready_w;
    wire target_read_valid_w;
    wire target_unit_done_w;
    wire [15:0] target_write_addr_w;
    wire [159:0] target_write_data_w;
    wire target_write_ready_w;
    wire target_write_valid_w;
    wire texture_finish_w;
    wire [17:0] texture_load_addr_w;
    wire [255:0] texture_load_data_w;
    wire [31:0] texture_load_keep_w;
    wire texture_load_ready_w;
    wire texture_load_valid_w;
    wire texture_pipeline_done_w;
    wire texture_ram_done_w;
    wire [119:0] texture_read_addr_w;
    wire [255:0] texture_read_data_data_w;
    wire [31:0] texture_read_data_keep_w;
    wire texture_read_data_last_w;
    wire texture_read_data_ready_w;
    wire texture_read_data_valid_w;
    wire [127:0] texture_read_data_w;
    wire [7:0] texture_read_en_w;
    wire [31:0] texture_read_req_addr_w;
    wire [31:0] texture_read_req_bytes_w;
    wire texture_read_req_ready_w;
    wire texture_read_req_valid_w;
    wire [255:0] texture_render_state_pixel_w;
    wire texture_render_state_ready_w;
    wire [255:0] texture_render_state_target_w;
    wire [255:0] texture_render_state_tex_w;
    wire texture_render_state_valid_w;
    wire texture_render_state_wide_w;
    wire texture_unit_done_w;
    wire [63:0] triangle_setup_bounds_w;
    wire [479:0] triangle_setup_edge_w;
    wire [671:0] triangle_setup_gradient_w;
    wire [69:0] triangle_setup_h_w;
    wire [31:0] triangle_setup_origin_w;
    wire triangle_setup_ready_w;
    wire [433:0] triangle_setup_start_w;
    wire triangle_setup_valid_w;
    wire [255:0] unpack_command_w;
    wire unpack_done_w;
    wire unpack_ready_w;
    wire unpack_valid_w;
    wire unused_command_read_done_w;
    wire unused_matrix_read_done_w;
    wire [31:0] unused_object_read_data_keep_w;
    wire unused_object_read_data_last_w;
    wire unused_palette_read_done_w;
    wire unused_quad_read_done_w;
    wire unused_texture_read_done_w;
    wire unused_vertex_read_done_w;
    wire [127:0] vertex_data_w;
    wire [255:0] vertex_read_data_data_w;
    wire [31:0] vertex_read_data_keep_w;
    wire vertex_read_data_last_w;
    wire vertex_read_data_ready_w;
    wire vertex_read_data_valid_w;
    wire [31:0] vertex_read_req_addr_w;
    wire [31:0] vertex_read_req_bytes_w;
    wire vertex_read_req_ready_w;
    wire vertex_read_req_valid_w;
    wire vertex_ready_w;
    wire vertex_valid_w;
    wire wide_w;
    wire write_dma_error_w;
    wire write_dma_idle_w;
    reg [23:0] object_record_idx_r;
    reg sample_quad_select_r;

    // One regional reset copy per independently placed unit.
    wire regs_rst_n_w;
    edrv32_reset_copy u_reset_regs (
        .clk_i(clk_gpu_i),
        .rst_n_i(rst_gpu_n_i),
        .rst_n_o(regs_rst_n_w)
    );

    wire command_rst_n_w;
    edrv32_reset_copy u_reset_command (
        .clk_i(clk_gpu_i),
        .rst_n_i(rst_gpu_n_i),
        .rst_n_o(command_rst_n_w)
    );

    wire read_dma_rst_n_w;
    edrv32_reset_copy u_reset_read_dma (
        .clk_i(clk_gpu_i),
        .rst_n_i(rst_gpu_n_i),
        .rst_n_o(read_dma_rst_n_w)
    );

    wire write_dma_rst_n_w;
    edrv32_reset_copy u_reset_write_dma (
        .clk_i(clk_gpu_i),
        .rst_n_i(rst_gpu_n_i),
        .rst_n_o(write_dma_rst_n_w)
    );

    wire unpack_rst_n_w;
    edrv32_reset_copy u_reset_unpack (
        .clk_i(clk_gpu_i),
        .rst_n_i(rst_gpu_n_i),
        .rst_n_o(unpack_rst_n_w)
    );

    wire list_pack_rst_n_w;
    edrv32_reset_copy u_reset_list_pack (
        .clk_i(clk_gpu_i),
        .rst_n_i(rst_gpu_n_i),
        .rst_n_o(list_pack_rst_n_w)
    );

    wire object_rst_n_w;
    edrv32_reset_copy u_reset_object (
        .clk_i(clk_gpu_i),
        .rst_n_i(rst_gpu_n_i),
        .rst_n_o(object_rst_n_w)
    );

    wire resolve_rst_n_w;
    edrv32_reset_copy u_reset_resolve (
        .clk_i(clk_gpu_i),
        .rst_n_i(rst_gpu_n_i),
        .rst_n_o(resolve_rst_n_w)
    );

    wire pixel_rst_n_w;
    edrv32_reset_copy u_reset_pixel (
        .clk_i(clk_gpu_i),
        .rst_n_i(rst_gpu_n_i),
        .rst_n_o(pixel_rst_n_w)
    );

    wire target_rst_n_w;
    edrv32_reset_copy u_reset_target (
        .clk_i(clk_gpu_i),
        .rst_n_i(rst_gpu_n_i),
        .rst_n_o(target_rst_n_w)
    );

    wire texture_ram_rst_n_w;
    edrv32_reset_copy u_reset_texture_ram (
        .clk_i(clk_gpu_i),
        .rst_n_i(rst_gpu_n_i),
        .rst_n_o(texture_ram_rst_n_w)
    );

    wire palette_rst_n_w;
    edrv32_reset_copy u_reset_palette (
        .clk_i(clk_gpu_i),
        .rst_n_i(rst_gpu_n_i),
        .rst_n_o(palette_rst_n_w)
    );

    wire geometry_rst_n_w;
    edrv32_reset_copy u_reset_geometry (
        .clk_i(clk_gpu_i),
        .rst_n_i(rst_gpu_n_i),
        .rst_n_o(geometry_rst_n_w)
    );

    wire setup_rst_n_w;
    edrv32_reset_copy u_reset_setup (
        .clk_i(clk_gpu_i),
        .rst_n_i(rst_gpu_n_i),
        .rst_n_o(setup_rst_n_w)
    );

    wire raster_rst_n_w;
    edrv32_reset_copy u_reset_raster (
        .clk_i(clk_gpu_i),
        .rst_n_i(rst_gpu_n_i),
        .rst_n_o(raster_rst_n_w)
    );

    wire quad_rst_n_w;
    edrv32_reset_copy u_reset_quad (
        .clk_i(clk_gpu_i),
        .rst_n_i(rst_gpu_n_i),
        .rst_n_o(quad_rst_n_w)
    );

    wire perspective_rst_n_w;
    edrv32_reset_copy u_reset_perspective (
        .clk_i(clk_gpu_i),
        .rst_n_i(rst_gpu_n_i),
        .rst_n_o(perspective_rst_n_w)
    );

    wire texture_rst_n_w;
    edrv32_reset_copy u_reset_texture (
        .clk_i(clk_gpu_i),
        .rst_n_i(rst_gpu_n_i),
        .rst_n_o(texture_rst_n_w)
    );

    // The object client returns one complete 32-byte record per transfer.
    assign object_record_valid_w = object_read_data_valid_w;
    assign object_read_data_ready_w = object_record_ready_w;
    assign object_record_data_w = object_read_data_data_w;
    assign object_record_idx_w = object_record_idx_r;
    assign object_configured_w = object_cfg_valid_w && object_cfg_ready_w;
    assign object_published_w = object_result_valid_w && object_result_ready_w;

    always @(posedge clk_gpu_i or negedge object_rst_n_w) begin
        if (!object_rst_n_w) begin
            object_record_idx_r <= 24'd0;
        end else if (object_read_req_valid_w && object_read_req_ready_w) begin
            object_record_idx_r <= 24'd0;
        end else if (object_record_valid_w && object_record_ready_w) begin
            object_record_idx_r <= object_record_idx_r + 24'd1;
        end
    end

    // TEX_LOAD completion includes every physical RAM write (microarch 4.12).
    assign texture_unit_done_w = texture_pipeline_done_w && texture_ram_done_w && palette_done_w;

    // The command remains the sole owner of the scan-source selection (4.12).
    always @(posedge clk_gpu_i or negedge command_rst_n_w) begin
        if (!command_rst_n_w) begin
            sample_quad_select_r <= 1'b0;
        end else if (raster_draw_valid_w && raster_draw_ready_w) begin
            sample_quad_select_r <= 1'b0;
        end else if (quad_draw_valid_w && quad_draw_ready_w) begin
            sample_quad_select_r <= 1'b1;
        end
    end

    assign perspective_sample_ready_w = !sample_quad_select_r && sample_ready_w;
    assign quad_sample_ready_w = sample_quad_select_r && sample_ready_w;
    assign sample_alpha_w = sample_quad_select_r
        ? quad_sample_alpha_w : perspective_sample_alpha_w;
    assign sample_color_w = sample_quad_select_r
        ? quad_sample_color_w : perspective_sample_color_w;
    assign sample_depth_w = sample_quad_select_r
        ? quad_sample_depth_w : perspective_sample_depth_w;
    assign sample_mask_w = sample_quad_select_r
        ? quad_sample_mask_w : perspective_sample_mask_w;
    assign sample_palette_w = sample_quad_select_r
        ? quad_sample_palette_w : perspective_sample_palette_w;
    assign sample_quad_w = sample_quad_select_r
        ? quad_sample_quad_w : perspective_sample_quad_w;
    assign sample_span_w = sample_quad_select_r
        ? quad_sample_span_w : perspective_sample_span_w;
    assign sample_u_w = sample_quad_select_r
        ? quad_sample_u_w : perspective_sample_u_w;
    assign sample_v_w = sample_quad_select_r
        ? quad_sample_v_w : perspective_sample_v_w;
    assign sample_x_w = sample_quad_select_r
        ? quad_sample_x_w : perspective_sample_x_w;
    assign sample_y_w = sample_quad_select_r
        ? quad_sample_y_w : perspective_sample_y_w;
    assign sample_valid_w = sample_quad_select_r
        ? quad_sample_valid_w : perspective_sample_valid_w;

    // regs interface.
    edrv32_gpu_regs u_regs (
        // Clock and reset.
        .clk_i(clk_gpu_i),
        .rst_n_i(regs_rst_n_w),

        // APB control interface.
        .s_apb_paddr_i(s_apb_paddr_i),
        .s_apb_psel_i(s_apb_psel_i),
        .s_apb_penable_i(s_apb_penable_i),
        .s_apb_pwrite_i(s_apb_pwrite_i),
        .s_apb_pwdata_i(s_apb_pwdata_i),
        .s_apb_pstrb_i(s_apb_pstrb_i),
        .s_apb_pready_o(s_apb_pready_o),
        .s_apb_prdata_o(s_apb_prdata_o),
        .s_apb_pslverr_o(s_apb_pslverr_o),

        // Command control and completion.
        .enable_o(enable_w),
        .start_o(start_w),
        .abort_o(abort_w),
        .soft_rst_o(soft_rst_w),
        .desc_base_o(desc_base_w),
        .desc_count_o(desc_count_w),
        .wide_o(wide_w),
        .busy_i(busy_w),
        .done_i(done_w),
        .error_i(error_w),
        .err_code_i(err_code_w),

        // Object configuration snapshot and result publication.
        .object_cfg_request_i(object_cfg_request_w),
        .object_cfg_valid_o(object_cfg_valid_w),
        .object_cfg_ready_i(object_cfg_ready_w),
        .object_cfg_live_o(object_cfg_live_w),
        .object_cfg_targets_o(object_cfg_targets_w),
        .object_cfg_hit_base_o(object_cfg_hit_base_w),
        .object_cfg_hit_max_o(object_cfg_hit_max_w),
        .object_cfg_free_base_o(object_cfg_free_base_w),
        .object_cfg_free_max_o(object_cfg_free_max_w),
        .object_result_valid_i(object_result_valid_w),
        .object_result_ready_o(object_result_ready_w),
        .object_result_hit_count_i(object_result_hit_count_w),
        .object_result_free_count_i(object_result_free_count_w),
        .object_result_alive_count_i(object_result_alive_count_w),
        .object_result_overflow_i(object_result_overflow_w),

        // Performance events and interrupt.
        .perf_vertex_i(perf_vertex_w),
        .perf_triangle_i(perf_triangle_w),
        .perf_quad_i(perf_quad_w),
        .perf_pixel_count_i(perf_pixel_count_w),
        .perf_texture_stall_i(perf_texture_stall_w),
        .perf_read_wait_i(perf_read_wait_w),
        .perf_resolve_busy_i(perf_resolve_busy_w),
        .perf_object_busy_i(perf_object_busy_w),
        .irq_o(irq_o)
    );

    // command interface.
    edrv32_gpu_command u_command (
        // Clock and reset.
        .clk_i(clk_gpu_i),
        .rst_n_i(command_rst_n_w),

        // Register control and completion.
        .start_i(start_w),
        .abort_i(abort_w),
        .soft_rst_i(soft_rst_w),
        .enable_i(enable_w),
        .desc_base_i(desc_base_w),
        .desc_count_i(desc_count_w),
        .wide_i(wide_w),
        .busy_o(busy_w),
        .done_o(done_w),
        .error_o(error_w),
        .err_code_o(err_code_w),

        // DMA client requests and command returns.
        .command_read_req_valid_o(command_read_req_valid_w),
        .command_read_req_ready_i(command_read_req_ready_w),
        .command_read_req_addr_o(command_read_req_addr_w),
        .command_read_req_bytes_o(command_read_req_bytes_w),
        .matrix_read_req_valid_o(matrix_read_req_valid_w),
        .matrix_read_req_ready_i(matrix_read_req_ready_w),
        .matrix_read_req_addr_o(matrix_read_req_addr_w),
        .matrix_read_req_bytes_o(matrix_read_req_bytes_w),
        .vertex_read_req_valid_o(vertex_read_req_valid_w),
        .vertex_read_req_ready_i(vertex_read_req_ready_w),
        .vertex_read_req_addr_o(vertex_read_req_addr_w),
        .vertex_read_req_bytes_o(vertex_read_req_bytes_w),
        .quad_read_req_valid_o(quad_read_req_valid_w),
        .quad_read_req_ready_i(quad_read_req_ready_w),
        .quad_read_req_addr_o(quad_read_req_addr_w),
        .quad_read_req_bytes_o(quad_read_req_bytes_w),
        .object_read_req_valid_o(object_read_req_valid_w),
        .object_read_req_ready_i(object_read_req_ready_w),
        .object_read_req_addr_o(object_read_req_addr_w),
        .object_read_req_bytes_o(object_read_req_bytes_w),
        .texture_read_req_valid_o(texture_read_req_valid_w),
        .texture_read_req_ready_i(texture_read_req_ready_w),
        .texture_read_req_addr_o(texture_read_req_addr_w),
        .texture_read_req_bytes_o(texture_read_req_bytes_w),
        .palette_read_req_valid_o(palette_read_req_valid_w),
        .palette_read_req_ready_i(palette_read_req_ready_w),
        .palette_read_req_addr_o(palette_read_req_addr_w),
        .palette_read_req_bytes_o(palette_read_req_bytes_w),
        .command_read_data_valid_i(command_read_data_valid_w),
        .command_read_data_ready_o(command_read_data_ready_w),
        .command_read_data_data_i(command_read_data_data_w),
        .command_read_data_keep_i(command_read_data_keep_w),
        .command_read_data_last_i(command_read_data_last_w),
        .object_read_done_i(object_read_done_w),
        .read_dma_idle_i(read_dma_idle_w),
        .write_dma_idle_i(write_dma_idle_w),
        .read_dma_error_i(read_dma_error_w),
        .write_dma_error_i(write_dma_error_w),
        .dma_start_o(dma_start_w),

        // DMA unpack configuration and assembled matrix.
        .unpack_valid_o(unpack_valid_w),
        .unpack_ready_i(unpack_ready_w),
        .unpack_command_o(unpack_command_w),
        .unpack_done_i(unpack_done_w),
        .matrix_valid_i(matrix_valid_w),
        .matrix_ready_o(matrix_ready_w),
        .matrix_data_i(matrix_data_w),

        // Geometry snapshot.
        .geometry_cfg_valid_o(geometry_cfg_valid_w),
        .geometry_cfg_ready_i(geometry_cfg_ready_w),
        .geometry_cfg_matrix_o(geometry_cfg_matrix_w),
        .geometry_cfg_light_o(geometry_cfg_light_w),
        .geometry_cfg_target_o(geometry_cfg_target_w),
        .geometry_cfg_pixel_o(geometry_cfg_pixel_w),
        .geometry_cfg_wide_o(geometry_cfg_wide_w),
        .raster_render_state_valid_o(raster_render_state_valid_w),
        .raster_render_state_ready_i(raster_render_state_ready_w),
        .raster_render_state_tex_o(raster_render_state_tex_w),
        .raster_render_state_pixel_o(raster_render_state_pixel_w),
        .raster_render_state_target_o(raster_render_state_target_w),
        .raster_render_state_wide_o(raster_render_state_wide_w),
        .quad_render_state_valid_o(quad_render_state_valid_w),
        .quad_render_state_ready_i(quad_render_state_ready_w),
        .quad_render_state_tex_o(quad_render_state_tex_w),
        .quad_render_state_pixel_o(quad_render_state_pixel_w),
        .quad_render_state_target_o(quad_render_state_target_w),
        .quad_render_state_wide_o(quad_render_state_wide_w),
        .texture_render_state_valid_o(texture_render_state_valid_w),
        .texture_render_state_ready_i(texture_render_state_ready_w),
        .texture_render_state_tex_o(texture_render_state_tex_w),
        .texture_render_state_pixel_o(texture_render_state_pixel_w),
        .texture_render_state_target_o(texture_render_state_target_w),
        .texture_render_state_wide_o(texture_render_state_wide_w),
        .pixel_render_state_valid_o(pixel_render_state_valid_w),
        .pixel_render_state_ready_i(pixel_render_state_ready_w),
        .pixel_render_state_tex_o(pixel_render_state_tex_w),
        .pixel_render_state_pixel_o(pixel_render_state_pixel_w),
        .pixel_render_state_target_o(pixel_render_state_target_w),
        .pixel_render_state_wide_o(pixel_render_state_wide_w),
        .geometry_draw_valid_o(geometry_draw_valid_w),
        .geometry_draw_ready_i(geometry_draw_ready_w),
        .geometry_draw_command_o(geometry_draw_command_w),
        .raster_draw_valid_o(raster_draw_valid_w),
        .raster_draw_ready_i(raster_draw_ready_w),
        .raster_draw_command_o(raster_draw_command_w),
        .quad_draw_valid_o(quad_draw_valid_w),
        .quad_draw_ready_i(quad_draw_ready_w),
        .quad_draw_command_o(quad_draw_command_w),
        .object_draw_valid_o(object_draw_valid_w),
        .object_draw_ready_i(object_draw_ready_w),
        .object_draw_command_o(object_draw_command_w),

        // Special command clients.
        .clear_valid_o(clear_valid_w),
        .clear_ready_i(clear_ready_w),
        .clear_command_o(clear_command_w),
        .clear_target_o(clear_target_w),
        .clear_wide_o(clear_wide_w),
        .resolve_valid_o(resolve_valid_w),
        .resolve_ready_i(resolve_ready_w),
        .resolve_command_o(resolve_command_w),
        .resolve_target_o(resolve_target_w),
        .resolve_wide_o(resolve_wide_w),
        .palette_prepare_valid_o(palette_prepare_valid_w),
        .palette_prepare_ready_i(palette_prepare_ready_w),
        .palette_prepare_group_o(palette_prepare_group_w),
        .palette_prepared_valid_i(palette_prepared_valid_w),
        .palette_prepared_ready_o(palette_prepared_ready_w),
        .object_cfg_request_o(object_cfg_request_w),
        .object_cfg_done_i(object_configured_w),
        .pack_valid_o(pack_valid_w),
        .pack_ready_i(pack_ready_w),
        .pack_command_o(pack_command_w),
        .pack_done_i(pack_done_w),
        .object_publish_o(object_publish_w),
        .object_published_i(object_published_w),

        // Per-unit finish levels and completion.
        .geometry_finish_o(geometry_finish_w),
        .geometry_unit_done_i(geometry_unit_done_w),
        .setup_finish_o(setup_finish_w),
        .setup_unit_done_i(setup_unit_done_w),
        .raster_finish_o(raster_finish_w),
        .raster_unit_done_i(raster_unit_done_w),
        .quad_finish_o(quad_finish_w),
        .quad_unit_done_i(quad_unit_done_w),
        .perspective_finish_o(perspective_finish_w),
        .perspective_unit_done_i(perspective_unit_done_w),
        .object_finish_o(object_finish_w),
        .object_unit_done_i(object_unit_done_w),
        .texture_finish_o(texture_finish_w),
        .texture_unit_done_i(texture_unit_done_w),
        .pixel_finish_o(pixel_finish_w),
        .pixel_unit_done_i(pixel_unit_done_w),
        .target_finish_o(target_finish_w),
        .target_unit_done_i(target_unit_done_w),
        .resolve_finish_o(resolve_finish_w),
        .resolve_unit_done_i(resolve_unit_done_w),
        .stop_region_o(stop_region_w),
        .stop_o(unused_stop_w)
    );

    // read dma interface.
    edrv32_gpu_read_dma u_read_dma (
        // Clock and reset.
        .clk_i(clk_gpu_i),
        .rst_n_i(read_dma_rst_n_w),

        // Independent logical read clients.
        .command_read_req_valid_i(command_read_req_valid_w),
        .command_read_req_ready_o(command_read_req_ready_w),
        .command_read_req_addr_i(command_read_req_addr_w),
        .command_read_req_bytes_i(command_read_req_bytes_w),
        .command_read_data_valid_o(command_read_data_valid_w),
        .command_read_data_ready_i(command_read_data_ready_w),
        .command_read_data_data_o(command_read_data_data_w),
        .command_read_data_keep_o(command_read_data_keep_w),
        .command_read_data_last_o(command_read_data_last_w),
        .command_read_done_o(unused_command_read_done_w),
        .matrix_read_req_valid_i(matrix_read_req_valid_w),
        .matrix_read_req_ready_o(matrix_read_req_ready_w),
        .matrix_read_req_addr_i(matrix_read_req_addr_w),
        .matrix_read_req_bytes_i(matrix_read_req_bytes_w),
        .matrix_read_data_valid_o(matrix_read_data_valid_w),
        .matrix_read_data_ready_i(matrix_read_data_ready_w),
        .matrix_read_data_data_o(matrix_read_data_data_w),
        .matrix_read_data_keep_o(matrix_read_data_keep_w),
        .matrix_read_data_last_o(matrix_read_data_last_w),
        .matrix_read_done_o(unused_matrix_read_done_w),
        .vertex_read_req_valid_i(vertex_read_req_valid_w),
        .vertex_read_req_ready_o(vertex_read_req_ready_w),
        .vertex_read_req_addr_i(vertex_read_req_addr_w),
        .vertex_read_req_bytes_i(vertex_read_req_bytes_w),
        .vertex_read_data_valid_o(vertex_read_data_valid_w),
        .vertex_read_data_ready_i(vertex_read_data_ready_w),
        .vertex_read_data_data_o(vertex_read_data_data_w),
        .vertex_read_data_keep_o(vertex_read_data_keep_w),
        .vertex_read_data_last_o(vertex_read_data_last_w),
        .vertex_read_done_o(unused_vertex_read_done_w),
        .quad_read_req_valid_i(quad_read_req_valid_w),
        .quad_read_req_ready_o(quad_read_req_ready_w),
        .quad_read_req_addr_i(quad_read_req_addr_w),
        .quad_read_req_bytes_i(quad_read_req_bytes_w),
        .quad_read_data_valid_o(quad_read_data_valid_w),
        .quad_read_data_ready_i(quad_read_data_ready_w),
        .quad_read_data_data_o(quad_read_data_data_w),
        .quad_read_data_keep_o(quad_read_data_keep_w),
        .quad_read_data_last_o(quad_read_data_last_w),
        .quad_read_done_o(unused_quad_read_done_w),
        .object_read_req_valid_i(object_read_req_valid_w),
        .object_read_req_ready_o(object_read_req_ready_w),
        .object_read_req_addr_i(object_read_req_addr_w),
        .object_read_req_bytes_i(object_read_req_bytes_w),
        .object_read_data_valid_o(object_read_data_valid_w),
        .object_read_data_ready_i(object_read_data_ready_w),
        .object_read_data_data_o(object_read_data_data_w),
        .object_read_data_keep_o(unused_object_read_data_keep_w),
        .object_read_data_last_o(unused_object_read_data_last_w),
        .object_read_done_o(object_read_done_w),
        .texture_read_req_valid_i(texture_read_req_valid_w),
        .texture_read_req_ready_o(texture_read_req_ready_w),
        .texture_read_req_addr_i(texture_read_req_addr_w),
        .texture_read_req_bytes_i(texture_read_req_bytes_w),
        .texture_read_data_valid_o(texture_read_data_valid_w),
        .texture_read_data_ready_i(texture_read_data_ready_w),
        .texture_read_data_data_o(texture_read_data_data_w),
        .texture_read_data_keep_o(texture_read_data_keep_w),
        .texture_read_data_last_o(texture_read_data_last_w),
        .texture_read_done_o(unused_texture_read_done_w),
        .palette_read_req_valid_i(palette_read_req_valid_w),
        .palette_read_req_ready_o(palette_read_req_ready_w),
        .palette_read_req_addr_i(palette_read_req_addr_w),
        .palette_read_req_bytes_i(palette_read_req_bytes_w),
        .palette_read_data_valid_o(palette_read_data_valid_w),
        .palette_read_data_ready_i(palette_read_data_ready_w),
        .palette_read_data_data_o(palette_read_data_data_w),
        .palette_read_data_keep_o(palette_read_data_keep_w),
        .palette_read_data_last_o(palette_read_data_last_w),
        .palette_read_done_o(unused_palette_read_done_w),

        // AXI256 read master; all transactions use local ID zero.
        .m_axi_arid_o(m_axi_arid_o),
        .m_axi_araddr_o(m_axi_araddr_o),
        .m_axi_arlen_o(m_axi_arlen_o),
        .m_axi_arvalid_o(m_axi_arvalid_o),
        .m_axi_arready_i(m_axi_arready_i),
        .m_axi_rid_i(m_axi_rid_i),
        .m_axi_rdata_i(m_axi_rdata_i),
        .m_axi_rresp_i(m_axi_rresp_i),
        .m_axi_rlast_i(m_axi_rlast_i),
        .m_axi_rvalid_i(m_axi_rvalid_i),
        .m_axi_rready_o(m_axi_rready_o),

        // Run lifecycle and statistics.
        .start_i(dma_start_w),
        .stop_i(stop_region_w[0]),
        .dma_idle_o(read_dma_idle_w),
        .dma_error_o(read_dma_error_w),
        .perf_read_wait_o(perf_read_wait_w)
    );

    // write dma interface.
    edrv32_gpu_write_dma u_write_dma (
        // Clock and reset.
        .clk_i(clk_gpu_i),
        .rst_n_i(write_dma_rst_n_w),

        // Independent logical write clients.
        .object_write_req_valid_i(object_write_req_valid_w),
        .object_write_req_ready_o(object_write_req_ready_w),
        .object_write_req_addr_i(object_write_req_addr_w),
        .object_write_req_bytes_i(object_write_req_bytes_w),
        .object_write_data_valid_i(object_write_data_valid_w),
        .object_write_data_ready_o(object_write_data_ready_w),
        .object_write_data_data_i(object_write_data_data_w),
        .object_write_data_keep_i(object_write_data_keep_w),
        .object_write_data_last_i(object_write_data_last_w),
        .object_write_done_o(object_write_done_w),
        .hit_write_req_valid_i(hit_write_req_valid_w),
        .hit_write_req_ready_o(hit_write_req_ready_w),
        .hit_write_req_addr_i(hit_write_req_addr_w),
        .hit_write_req_bytes_i(hit_write_req_bytes_w),
        .hit_write_data_valid_i(hit_write_data_valid_w),
        .hit_write_data_ready_o(hit_write_data_ready_w),
        .hit_write_data_data_i(hit_write_data_data_w),
        .hit_write_data_keep_i(hit_write_data_keep_w),
        .hit_write_data_last_i(hit_write_data_last_w),
        .hit_write_done_o(hit_write_done_w),
        .free_write_req_valid_i(free_write_req_valid_w),
        .free_write_req_ready_o(free_write_req_ready_w),
        .free_write_req_addr_i(free_write_req_addr_w),
        .free_write_req_bytes_i(free_write_req_bytes_w),
        .free_write_data_valid_i(free_write_data_valid_w),
        .free_write_data_ready_o(free_write_data_ready_w),
        .free_write_data_data_i(free_write_data_data_w),
        .free_write_data_keep_i(free_write_data_keep_w),
        .free_write_data_last_i(free_write_data_last_w),
        .free_write_done_o(free_write_done_w),
        .resolve_write_req_valid_i(resolve_write_req_valid_w),
        .resolve_write_req_ready_o(resolve_write_req_ready_w),
        .resolve_write_req_addr_i(resolve_write_req_addr_w),
        .resolve_write_req_bytes_i(resolve_write_req_bytes_w),
        .resolve_write_data_valid_i(resolve_write_data_valid_w),
        .resolve_write_data_ready_o(resolve_write_data_ready_w),
        .resolve_write_data_data_i(resolve_write_data_data_w),
        .resolve_write_data_keep_i(resolve_write_data_keep_w),
        .resolve_write_data_last_i(resolve_write_data_last_w),
        .resolve_write_done_o(resolve_write_done_w),

        // AXI256 write master.
        .m_axi_awid_o(m_axi_awid_o),
        .m_axi_awaddr_o(m_axi_awaddr_o),
        .m_axi_awlen_o(m_axi_awlen_o),
        .m_axi_awvalid_o(m_axi_awvalid_o),
        .m_axi_awready_i(m_axi_awready_i),
        .m_axi_wdata_o(m_axi_wdata_o),
        .m_axi_wstrb_o(m_axi_wstrb_o),
        .m_axi_wlast_o(m_axi_wlast_o),
        .m_axi_wvalid_o(m_axi_wvalid_o),
        .m_axi_wready_i(m_axi_wready_i),
        .m_axi_bid_i(m_axi_bid_i),
        .m_axi_bresp_i(m_axi_bresp_i),
        .m_axi_bvalid_i(m_axi_bvalid_i),
        .m_axi_bready_o(m_axi_bready_o),

        // Run lifecycle.
        .start_i(dma_start_w),
        .stop_i(stop_region_w[1]),
        .dma_idle_o(write_dma_idle_w),
        .dma_error_o(write_dma_error_w)
    );

    // unpack interface.
    edrv32_gpu_unpack u_unpack (
        // Clock and reset.
        .clk_i(clk_gpu_i),
        .rst_n_i(unpack_rst_n_w),

        // Current serial command.
        .unpack_valid_i(unpack_valid_w),
        .unpack_ready_o(unpack_ready_w),
        .unpack_command_i(unpack_command_w),
        .matrix_read_data_valid_i(matrix_read_data_valid_w),
        .matrix_read_data_ready_o(matrix_read_data_ready_w),
        .matrix_read_data_data_i(matrix_read_data_data_w),
        .matrix_read_data_keep_i(matrix_read_data_keep_w),
        .matrix_read_data_last_i(matrix_read_data_last_w),
        .vertex_read_data_valid_i(vertex_read_data_valid_w),
        .vertex_read_data_ready_o(vertex_read_data_ready_w),
        .vertex_read_data_data_i(vertex_read_data_data_w),
        .vertex_read_data_keep_i(vertex_read_data_keep_w),
        .vertex_read_data_last_i(vertex_read_data_last_w),
        .quad_read_data_valid_i(quad_read_data_valid_w),
        .quad_read_data_ready_o(quad_read_data_ready_w),
        .quad_read_data_data_i(quad_read_data_data_w),
        .quad_read_data_keep_i(quad_read_data_keep_w),
        .quad_read_data_last_i(quad_read_data_last_w),
        .texture_read_data_valid_i(texture_read_data_valid_w),
        .texture_read_data_ready_o(texture_read_data_ready_w),
        .texture_read_data_data_i(texture_read_data_data_w),
        .texture_read_data_keep_i(texture_read_data_keep_w),
        .texture_read_data_last_i(texture_read_data_last_w),
        .palette_read_data_valid_i(palette_read_data_valid_w),
        .palette_read_data_ready_o(palette_read_data_ready_w),
        .palette_read_data_data_i(palette_read_data_data_w),
        .palette_read_data_keep_i(palette_read_data_keep_w),
        .palette_read_data_last_i(palette_read_data_last_w),

        // Unpacked consumers.
        .matrix_valid_o(matrix_valid_w),
        .matrix_ready_i(matrix_ready_w),
        .matrix_data_o(matrix_data_w),
        .vertex_valid_o(vertex_valid_w),
        .vertex_ready_i(vertex_ready_w),
        .vertex_data_o(vertex_data_w),
        .quad_record_valid_o(quad_record_valid_w),
        .quad_record_ready_i(quad_record_ready_w),
        .quad_record_data_o(quad_record_data_w),
        .texture_load_valid_o(texture_load_valid_w),
        .texture_load_ready_i(texture_load_ready_w),
        .texture_load_addr_o(texture_load_addr_w),
        .texture_load_data_o(texture_load_data_w),
        .texture_load_keep_o(texture_load_keep_w),
        .palette_load_valid_o(palette_load_valid_w),
        .palette_load_ready_i(palette_load_ready_w),
        .palette_load_idx_o(palette_load_idx_w),
        .palette_load_data_o(palette_load_data_w),

        // Lifecycle.
        .stop_i(stop_region_w[2]),
        .unit_done_o(unpack_done_w)
    );

    // list pack interface.
    edrv32_gpu_list_pack u_list_pack (
        // Clock and reset.
        .clk_i(clk_gpu_i),
        .rst_n_i(list_pack_rst_n_w),

        // Command and previously captured register configuration.
        .pack_valid_i(pack_valid_w),
        .pack_ready_o(pack_ready_w),
        .pack_command_i(pack_command_w),
        .object_cfg_hit_base_i(object_cfg_hit_base_w),
        .object_cfg_hit_max_i(object_cfg_hit_max_w),
        .object_cfg_free_base_i(object_cfg_free_base_w),
        .object_cfg_free_max_i(object_cfg_free_max_w),

        // Ordered object updates and events.
        .object_update_valid_i(object_update_valid_w),
        .object_update_ready_o(object_update_ready_w),
        .object_update_idx_i(object_update_idx_w),
        .object_update_data_i(object_update_data_w),
        .object_event_valid_i(object_event_valid_w),
        .object_event_ready_o(object_event_ready_w),
        .object_event_idx_i(object_event_idx_w),
        .object_event_hit_i(object_event_hit_w),
        .object_event_free_i(object_event_free_w),

        // Independent write clients.
        .object_write_req_valid_o(object_write_req_valid_w),
        .object_write_req_ready_i(object_write_req_ready_w),
        .object_write_req_addr_o(object_write_req_addr_w),
        .object_write_req_bytes_o(object_write_req_bytes_w),
        .object_write_data_valid_o(object_write_data_valid_w),
        .object_write_data_ready_i(object_write_data_ready_w),
        .object_write_data_data_o(object_write_data_data_w),
        .object_write_data_keep_o(object_write_data_keep_w),
        .object_write_data_last_o(object_write_data_last_w),
        .object_write_done_i(object_write_done_w),
        .hit_write_req_valid_o(hit_write_req_valid_w),
        .hit_write_req_ready_i(hit_write_req_ready_w),
        .hit_write_req_addr_o(hit_write_req_addr_w),
        .hit_write_req_bytes_o(hit_write_req_bytes_w),
        .hit_write_data_valid_o(hit_write_data_valid_w),
        .hit_write_data_ready_i(hit_write_data_ready_w),
        .hit_write_data_data_o(hit_write_data_data_w),
        .hit_write_data_keep_o(hit_write_data_keep_w),
        .hit_write_data_last_o(hit_write_data_last_w),
        .hit_write_done_i(hit_write_done_w),
        .free_write_req_valid_o(free_write_req_valid_w),
        .free_write_req_ready_i(free_write_req_ready_w),
        .free_write_req_addr_o(free_write_req_addr_w),
        .free_write_req_bytes_o(free_write_req_bytes_w),
        .free_write_data_valid_o(free_write_data_valid_w),
        .free_write_data_ready_i(free_write_data_ready_w),
        .free_write_data_data_o(free_write_data_data_w),
        .free_write_data_keep_o(free_write_data_keep_w),
        .free_write_data_last_o(free_write_data_last_w),
        .free_write_done_i(free_write_done_w),

        // Finish follows object unit_done; stop retains data for accepted DMA requests.
        .finish_i(object_unit_done_w),
        .stop_i(stop_region_w[3]),
        .unit_done_o(pack_done_w)
    );

    // object interface.
    edrv32_gpu_object u_object (
        // Clock and reset.
        .clk_i(clk_gpu_i),
        .rst_n_i(object_rst_n_w),

        // Command and immutable configuration snapshots.
        .object_cfg_valid_i(object_cfg_valid_w),
        .object_cfg_ready_o(object_cfg_ready_w),
        .object_cfg_live_i(object_cfg_live_w),
        .object_cfg_targets_i(object_cfg_targets_w),
        .object_cfg_hit_base_i(object_cfg_hit_base_w),
        .object_cfg_hit_max_i(object_cfg_hit_max_w),
        .object_cfg_free_base_i(object_cfg_free_base_w),
        .object_cfg_free_max_i(object_cfg_free_max_w),
        .draw_valid_i(object_draw_valid_w),
        .draw_ready_o(object_draw_ready_w),
        .draw_command_i(object_draw_command_w),
        .object_record_valid_i(object_record_valid_w),
        .object_record_ready_o(object_record_ready_w),
        .object_record_data_i(object_record_data_w),
        .object_record_idx_i(object_record_idx_w),

        // Independently backpressured ordered output streams.
        .object_update_valid_o(object_update_valid_w),
        .object_update_ready_i(object_update_ready_w),
        .object_update_idx_o(object_update_idx_w),
        .object_update_data_o(object_update_data_w),
        .object_event_valid_o(object_event_valid_w),
        .object_event_ready_i(object_event_ready_w),
        .object_event_idx_o(object_event_idx_w),
        .object_event_hit_o(object_event_hit_w),
        .object_event_free_o(object_event_free_w),
        .object_quad_valid_o(object_quad_valid_w),
        .object_quad_ready_i(object_quad_ready_w),
        .object_quad_data_o(object_quad_data_w),
        .object_quad_x_o(object_quad_x_w),
        .object_quad_y_o(object_quad_y_w),

        // Drain and deferred atomic result publication.
        .finish_i(object_finish_w),
        .stop_i(stop_region_w[4]),
        .unit_done_o(object_unit_done_w),
        .object_publish_i(object_publish_w),
        .object_result_valid_o(object_result_valid_w),
        .object_result_ready_i(object_result_ready_w),
        .object_result_hit_count_o(object_result_hit_count_w),
        .object_result_free_count_o(object_result_free_count_w),
        .object_result_alive_count_o(object_result_alive_count_w),
        .object_result_overflow_o(object_result_overflow_w),
        .perf_object_busy_o(perf_object_busy_w)
    );

    // resolve interface.
    edrv32_gpu_resolve u_resolve (
        // Clock and reset.
        .clk_i(clk_gpu_i),
        .rst_n_i(resolve_rst_n_w),

        // Command snapshot.
        .resolve_valid_i(resolve_valid_w),
        .resolve_ready_o(resolve_ready_w),
        .resolve_command_i(resolve_command_w),
        .resolve_target_i(resolve_target_w),
        .resolve_wide_i(resolve_wide_w),

        // Target color access.
        .resolve_read_valid_o(resolve_read_valid_w),
        .resolve_read_ready_i(resolve_read_ready_w),
        .resolve_read_addr_o(resolve_read_addr_w),
        .resolve_color_valid_i(resolve_color_valid_w),
        .resolve_color_ready_o(resolve_color_ready_w),
        .resolve_color_data_i(resolve_color_data_w),

        // Surface row write client.
        .write_req_valid_o(resolve_write_req_valid_w),
        .write_req_ready_i(resolve_write_req_ready_w),
        .write_req_addr_o(resolve_write_req_addr_w),
        .write_req_bytes_o(resolve_write_req_bytes_w),
        .write_data_valid_o(resolve_write_data_valid_w),
        .write_data_ready_i(resolve_write_data_ready_w),
        .write_data_data_o(resolve_write_data_data_w),
        .write_data_keep_o(resolve_write_data_keep_w),
        .write_data_last_o(resolve_write_data_last_w),
        .write_done_i(resolve_write_done_w),

        // Command lifecycle.
        .finish_i(resolve_finish_w),
        .stop_i(stop_region_w[5]),
        .unit_done_o(resolve_unit_done_w),
        .perf_resolve_busy_o(perf_resolve_busy_w)
    );

    // pixel interface.
    edrv32_gpu_pixel u_pixel (
        // Clock and reset.
        .clk_i(clk_gpu_i),
        .rst_n_i(pixel_rst_n_w),

        // Draw snapshot.
        .render_state_valid_i(pixel_render_state_valid_w),
        .render_state_ready_o(pixel_render_state_ready_w),
        .render_state_tex_i(pixel_render_state_tex_w),
        .render_state_pixel_i(pixel_render_state_pixel_w),
        .render_state_target_i(pixel_render_state_target_w),
        .render_state_wide_i(pixel_render_state_wide_w),

        // Four adjacent shaded pixels; transparent texels have their mask cleared.
        .shaded_valid_i(shaded_valid_w),
        .shaded_ready_o(shaded_ready_w),
        .shaded_x_i(shaded_x_w),
        .shaded_y_i(shaded_y_w),
        .shaded_mask_i(shaded_mask_w),
        .shaded_depth_i(shaded_depth_w),
        .shaded_color_i(shaded_color_w),
        .shaded_alpha_i(shaded_alpha_w),

        // Target read and ordered old-word return.
        .target_read_valid_o(target_read_valid_w),
        .target_read_ready_i(target_read_ready_w),
        .target_read_addr_o(target_read_addr_w),
        .target_old_valid_i(target_old_valid_w),
        .target_old_ready_o(target_old_ready_w),
        .target_old_data_i(target_old_data_w),

        // Full merged target word.
        .target_write_valid_o(target_write_valid_w),
        .target_write_ready_i(target_write_ready_w),
        .target_write_addr_o(target_write_addr_w),
        .target_write_data_o(target_write_data_w),

        // Completion and pixel event.
        .finish_i(pixel_finish_w),
        .stop_i(stop_region_w[6]),
        .unit_done_o(pixel_unit_done_w),
        .perf_pixel_count_o(perf_pixel_count_w)
    );

    // target interface.
    edrv32_gpu_target u_target (
        // Clock and reset.
        .clk_i(clk_gpu_i),
        .rst_n_i(target_rst_n_w),

        // CLEAR command and target snapshot.
        .clear_valid_i(clear_valid_w),
        .clear_ready_o(clear_ready_w),
        .clear_command_i(clear_command_w),
        .clear_target_i(clear_target_w),
        .clear_wide_i(clear_wide_w),

        // Pixel access.
        .target_read_valid_i(target_read_valid_w),
        .target_read_ready_o(target_read_ready_w),
        .target_read_addr_i(target_read_addr_w),
        .target_old_valid_o(target_old_valid_w),
        .target_old_ready_i(target_old_ready_w),
        .target_old_data_o(target_old_data_w),
        .target_write_valid_i(target_write_valid_w),
        .target_write_ready_o(target_write_ready_w),
        .target_write_addr_i(target_write_addr_w),
        .target_write_data_i(target_write_data_w),

        // RESOLVE color access.
        .resolve_read_valid_i(resolve_read_valid_w),
        .resolve_read_ready_o(resolve_read_ready_w),
        .resolve_read_addr_i(resolve_read_addr_w),
        .resolve_color_valid_o(resolve_color_valid_w),
        .resolve_color_ready_i(resolve_color_ready_w),
        .resolve_color_data_o(resolve_color_data_w),

        // Command drain.
        .finish_i(target_finish_w),
        .stop_i(stop_region_w[7]),
        .unit_done_o(target_unit_done_w)
    );

    // texture ram interface.
    edrv32_gpu_texture_ram u_texture_ram (
        // Clock and command lifetime.
        .clk_i(clk_gpu_i),
        .rst_n_i(texture_ram_rst_n_w),
        .finish_i(texture_finish_w),
        .stop_i(stop_region_w[8]),
        .unit_done_o(texture_ram_done_w),

        // Linear, offline-interleaved byte stream.
        .texture_load_valid_i(texture_load_valid_w),
        .texture_load_ready_o(texture_load_ready_w),
        .texture_load_addr_i(texture_load_addr_w),
        .texture_load_data_i(texture_load_data_w),
        .texture_load_keep_i(texture_load_keep_w),

        // Internal sampling: two independent row addresses per bank, fixed five cycles.
        .read_en_i(texture_read_en_w),
        .read_addr_i(texture_read_addr_w),
        .read_data_o(texture_read_data_w)
    );

    // palette interface.
    edrv32_gpu_palette u_palette (
        // Clock and command lifetime.
        .clk_i(clk_gpu_i),
        .rst_n_i(palette_rst_n_w),
        .finish_i(texture_finish_w),
        .stop_i(stop_region_w[9]),
        .unit_done_o(palette_done_w),

        // Palette loading and triangle preload control.
        .palette_load_valid_i(palette_load_valid_w),
        .palette_load_ready_o(palette_load_ready_w),
        .palette_load_idx_i(palette_load_idx_w),
        .palette_load_data_i(palette_load_data_w),
        .palette_prepare_valid_i(palette_prepare_valid_w),
        .palette_prepare_ready_o(palette_prepare_ready_w),
        .palette_prepare_group_i(palette_prepare_group_w),
        .palette_prepared_valid_o(palette_prepared_valid_w),
        .palette_prepared_ready_i(palette_prepared_ready_w),

        // Internal fixed-latency sampling ports, four cycles.
        .full_read_en_i(full_read_en_w),
        .full_read_idx_i(full_read_idx_w),
        .full_read_data_o(full_read_data_w),
        .current_read_en_i(current_read_en_w),
        .current_read_idx_i(current_read_idx_w),
        .current_read_data_o(current_read_data_w)
    );

    // geometry interface.
    edrv32_gpu_geometry u_geometry (
        // Clock and reset.
        .clk_i(clk_gpu_i),
        .rst_n_i(geometry_rst_n_w),

        // Configuration snapshot, followed by one draw command.
        .geometry_cfg_valid_i(geometry_cfg_valid_w),
        .geometry_cfg_ready_o(geometry_cfg_ready_w),
        .geometry_cfg_matrix_i(geometry_cfg_matrix_w),
        .geometry_cfg_light_i(geometry_cfg_light_w),
        .geometry_cfg_target_i(geometry_cfg_target_w),
        .geometry_cfg_pixel_i(geometry_cfg_pixel_w),
        .geometry_cfg_wide_i(geometry_cfg_wide_w),
        .draw_valid_i(geometry_draw_valid_w),
        .draw_ready_o(geometry_draw_ready_w),
        .draw_command_i(geometry_draw_command_w),

        // Packed vertex stream.
        .vertex_valid_i(vertex_valid_w),
        .vertex_ready_o(vertex_ready_w),
        .vertex_data_i(vertex_data_w),

        // Screen triangle replacement boundary.
        .screen_triangle_valid_o(screen_triangle_valid_w),
        .screen_triangle_ready_i(screen_triangle_ready_w),
        .screen_triangle_x_o(screen_triangle_x_w),
        .screen_triangle_y_o(screen_triangle_y_w),
        .screen_triangle_depth_o(screen_triangle_depth_w),
        .screen_triangle_q_o(screen_triangle_q_w),
        .screen_triangle_uq_o(screen_triangle_uq_w),
        .screen_triangle_vq_o(screen_triangle_vq_w),
        .screen_triangle_color_o(screen_triangle_color_w),

        // Command lifetime and performance event.
        .finish_i(geometry_finish_w),
        .stop_i(stop_region_w[10]),
        .unit_done_o(geometry_unit_done_w),
        .perf_vertex_o(perf_vertex_w)
    );

    // setup interface.
    edrv32_gpu_setup u_setup (
        // Clock and reset.
        .clk_i(clk_gpu_i),
        .rst_n_i(setup_rst_n_w),

        // Screen triangle stream.
        .screen_triangle_valid_i(screen_triangle_valid_w),
        .screen_triangle_ready_o(screen_triangle_ready_w),
        .screen_triangle_x_i(screen_triangle_x_w),
        .screen_triangle_y_i(screen_triangle_y_w),
        .screen_triangle_depth_i(screen_triangle_depth_w),
        .screen_triangle_q_i(screen_triangle_q_w),
        .screen_triangle_uq_i(screen_triangle_uq_w),
        .screen_triangle_vq_i(screen_triangle_vq_w),
        .screen_triangle_color_i(screen_triangle_color_w),

        // Established triangle stream.
        .triangle_setup_valid_o(triangle_setup_valid_w),
        .triangle_setup_ready_i(triangle_setup_ready_w),
        .triangle_setup_bounds_o(triangle_setup_bounds_w),
        .triangle_setup_edge_o(triangle_setup_edge_w),
        .triangle_setup_origin_o(triangle_setup_origin_w),
        .triangle_setup_start_o(triangle_setup_start_w),
        .triangle_setup_gradient_o(triangle_setup_gradient_w),
        .triangle_setup_h_o(triangle_setup_h_w),

        // Command lifetime and performance event.
        .finish_i(setup_finish_w),
        .stop_i(stop_region_w[11]),
        .unit_done_o(setup_unit_done_w),
        .perf_triangle_o(perf_triangle_w)
    );

    // raster interface.
    edrv32_gpu_raster u_raster (
        // Clock and reset.
        .clk_i(clk_gpu_i),
        .rst_n_i(raster_rst_n_w),

        // State and command snapshots.
        .render_state_valid_i(raster_render_state_valid_w),
        .render_state_ready_o(raster_render_state_ready_w),
        .render_state_tex_i(raster_render_state_tex_w),
        .render_state_pixel_i(raster_render_state_pixel_w),
        .render_state_target_i(raster_render_state_target_w),
        .render_state_wide_i(raster_render_state_wide_w),
        .draw_valid_i(raster_draw_valid_w),
        .draw_ready_o(raster_draw_ready_w),
        .draw_command_i(raster_draw_command_w),

        // triangle_setup stream.
        .triangle_setup_valid_i(triangle_setup_valid_w),
        .triangle_setup_ready_o(triangle_setup_ready_w),
        .triangle_setup_bounds_i(triangle_setup_bounds_w),
        .triangle_setup_edge_i(triangle_setup_edge_w),
        .triangle_setup_origin_i(triangle_setup_origin_w),
        .triangle_setup_start_i(triangle_setup_start_w),
        .triangle_setup_gradient_i(triangle_setup_gradient_w),
        .triangle_setup_h_i(triangle_setup_h_w),

        // Ordered fragment stream.
        .fragment_valid_o(raster_fragment_valid_w),
        .fragment_ready_i(raster_fragment_ready_w),
        .fragment_x_o(raster_fragment_x_w),
        .fragment_y_o(raster_fragment_y_w),
        .fragment_mask_o(raster_fragment_mask_w),
        .fragment_plane_o(raster_fragment_plane_w),
        .fragment_h_o(raster_fragment_h_w),
        .fragment_palette_o(raster_fragment_palette_w),
        .fragment_alpha_o(raster_fragment_alpha_w),

        // Command lifecycle.
        .finish_i(raster_finish_w),
        .stop_i(stop_region_w[12]),
        .unit_done_o(raster_unit_done_w)
    );

    // quad interface.
    edrv32_gpu_quad u_quad (
        // Clock and reset.
        .clk_i(clk_gpu_i),
        .rst_n_i(quad_rst_n_w),

        // State and command snapshots.
        .render_state_valid_i(quad_render_state_valid_w),
        .render_state_ready_o(quad_render_state_ready_w),
        .render_state_tex_i(quad_render_state_tex_w),
        .render_state_pixel_i(quad_render_state_pixel_w),
        .render_state_target_i(quad_render_state_target_w),
        .render_state_wide_i(quad_render_state_wide_w),
        .draw_valid_i(quad_draw_valid_w),
        .draw_ready_o(quad_draw_ready_w),
        .draw_command_i(quad_draw_command_w),

        // object_quad stream.
        .object_quad_valid_i(object_quad_valid_w),
        .object_quad_ready_o(object_quad_ready_w),
        .object_quad_data_i(object_quad_data_w),
        .object_quad_x_i(object_quad_x_w),
        .object_quad_y_i(object_quad_y_w),
        .quad_record_valid_i(quad_record_valid_w),
        .quad_record_ready_o(quad_record_ready_w),
        .quad_record_data_i(quad_record_data_w),

        // Ordered fragment stream.
        .sample_valid_o(quad_sample_valid_w),
        .sample_ready_i(quad_sample_ready_w),
        .sample_x_o(quad_sample_x_w),
        .sample_y_o(quad_sample_y_w),
        .sample_mask_o(quad_sample_mask_w),
        .sample_quad_o(quad_sample_quad_w),
        .sample_u_o(quad_sample_u_w),
        .sample_v_o(quad_sample_v_w),
        .sample_span_o(quad_sample_span_w),
        .sample_depth_o(quad_sample_depth_w),
        .sample_color_o(quad_sample_color_w),
        .sample_palette_o(quad_sample_palette_w),
        .sample_alpha_o(quad_sample_alpha_w),

        // Command lifecycle.
        .finish_i(quad_finish_w),
        .stop_i(stop_region_w[13]),
        .unit_done_o(quad_unit_done_w),
        .perf_quad_o(perf_quad_w)
    );

    // perspective interface.
    edrv32_gpu_perspective u_perspective (
        // Clock and reset.
        .clk_i(clk_gpu_i),
        .rst_n_i(perspective_rst_n_w),

        // Input fragment stream.
        .fragment_valid_i(raster_fragment_valid_w),
        .fragment_ready_o(raster_fragment_ready_w),
        .fragment_x_i(raster_fragment_x_w),
        .fragment_y_i(raster_fragment_y_w),
        .fragment_mask_i(raster_fragment_mask_w),
        .fragment_plane_i(raster_fragment_plane_w),
        .fragment_h_i(raster_fragment_h_w),
        .fragment_palette_i(raster_fragment_palette_w),
        .fragment_alpha_i(raster_fragment_alpha_w),

        // Output sample stream.
        .sample_valid_o(perspective_sample_valid_w),
        .sample_ready_i(perspective_sample_ready_w),
        .sample_x_o(perspective_sample_x_w),
        .sample_y_o(perspective_sample_y_w),
        .sample_mask_o(perspective_sample_mask_w),
        .sample_quad_o(perspective_sample_quad_w),
        .sample_u_o(perspective_sample_u_w),
        .sample_v_o(perspective_sample_v_w),
        .sample_span_o(perspective_sample_span_w),
        .sample_depth_o(perspective_sample_depth_w),
        .sample_color_o(perspective_sample_color_w),
        .sample_palette_o(perspective_sample_palette_w),
        .sample_alpha_o(perspective_sample_alpha_w),

        // Command lifecycle.
        .finish_i(perspective_finish_w),
        .stop_i(stop_region_w[14]),
        .unit_done_o(perspective_unit_done_w)
    );

    // texture interface.
    edrv32_gpu_texture u_texture (
        // Clock and command lifetime.
        .clk_i(clk_gpu_i),
        .rst_n_i(texture_rst_n_w),
        .finish_i(texture_finish_w),
        .stop_i(stop_region_w[15]),
        .unit_done_o(texture_pipeline_done_w),

        // Frozen render state snapshot.
        .render_state_valid_i(texture_render_state_valid_w),
        .render_state_ready_o(texture_render_state_ready_w),
        .render_state_tex_i(texture_render_state_tex_w),
        .render_state_pixel_i(texture_render_state_pixel_w),
        .render_state_target_i(texture_render_state_target_w),
        .render_state_wide_i(texture_render_state_wide_w),

        // Four ordered pixels from perspective.
        .sample_valid_i(sample_valid_w),
        .sample_ready_o(sample_ready_w),
        .sample_x_i(sample_x_w),
        .sample_y_i(sample_y_w),
        .sample_mask_i(sample_mask_w),
        .sample_quad_i(sample_quad_w),
        .sample_u_i(sample_u_w),
        .sample_v_i(sample_v_w),
        .sample_span_i(sample_span_w),
        .sample_depth_i(sample_depth_w),
        .sample_color_i(sample_color_w),
        .sample_palette_i(sample_palette_w),
        .sample_alpha_i(sample_alpha_w),

        // Ordered group after filtering and shading.
        .shaded_valid_o(shaded_valid_w),
        .shaded_ready_i(shaded_ready_w),
        .shaded_x_o(shaded_x_w),
        .shaded_y_o(shaded_y_w),
        .shaded_mask_o(shaded_mask_w),
        .shaded_depth_o(shaded_depth_w),
        .shaded_color_o(shaded_color_w),
        .shaded_alpha_o(shaded_alpha_w),

        // Internal RAM ports: bank-major, two ports per bank, five-cycle reads.
        .texture_read_en_o(texture_read_en_w),
        .texture_read_addr_o(texture_read_addr_w),
        .texture_read_data_i(texture_read_data_w),

        // Internal full/current palette ports, four-cycle reads.
        .full_read_en_o(full_read_en_w),
        .full_read_idx_o(full_read_idx_w),
        .full_read_data_i(full_read_data_w),
        .current_read_en_o(current_read_en_w),
        .current_read_idx_o(current_read_idx_w),
        .current_read_data_i(current_read_data_w),
        .perf_texture_stall_o(perf_texture_stall_w)
    );

endmodule
