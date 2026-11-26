// File: edrv32_gpu_command.v
// Spec: gpu-spec 2.2, 2.3, 5, 6; gpu-microarch 4.2, 4.5, 4.7.
// Description: Ordered command prefetch, state snapshots and per-command pipeline fences.
// Only specified opcode/texture errors are detected; abort drains accepted DMA intervals.
// Clock: clk_gpu.
module edrv32_gpu_command (
    // Clock and reset.
    input wire clk_i,
    input wire rst_n_i,

    // Register control and completion.
    input wire start_i,
    input wire abort_i,
    input wire soft_rst_i,
    input wire enable_i,
    input wire [31:0] desc_base_i,
    input wire [15:0] desc_count_i,
    input wire wide_i,
    output wire busy_o,
    output reg done_o,
    output reg error_o,
    output reg [31:0] err_code_o,

    // DMA client requests and command returns.
    output wire command_read_req_valid_o,
    input wire command_read_req_ready_i,
    output wire [31:0] command_read_req_addr_o,
    output wire [31:0] command_read_req_bytes_o,
    output wire matrix_read_req_valid_o,
    input wire matrix_read_req_ready_i,
    output wire [31:0] matrix_read_req_addr_o,
    output wire [31:0] matrix_read_req_bytes_o,
    output wire vertex_read_req_valid_o,
    input wire vertex_read_req_ready_i,
    output wire [31:0] vertex_read_req_addr_o,
    output wire [31:0] vertex_read_req_bytes_o,
    output wire quad_read_req_valid_o,
    input wire quad_read_req_ready_i,
    output wire [31:0] quad_read_req_addr_o,
    output wire [31:0] quad_read_req_bytes_o,
    output wire object_read_req_valid_o,
    input wire object_read_req_ready_i,
    output wire [31:0] object_read_req_addr_o,
    output wire [31:0] object_read_req_bytes_o,
    output wire texture_read_req_valid_o,
    input wire texture_read_req_ready_i,
    output wire [31:0] texture_read_req_addr_o,
    output wire [31:0] texture_read_req_bytes_o,
    output wire palette_read_req_valid_o,
    input wire palette_read_req_ready_i,
    output wire [31:0] palette_read_req_addr_o,
    output wire [31:0] palette_read_req_bytes_o,
    input wire command_read_data_valid_i,
    output wire command_read_data_ready_o,
    input wire [255:0] command_read_data_data_i,
    input wire [31:0] command_read_data_keep_i,
    input wire command_read_data_last_i,
    input wire object_read_done_i,
    input wire read_dma_idle_i,
    input wire write_dma_idle_i,
    input wire read_dma_error_i,
    input wire write_dma_error_i,
    output reg dma_start_o,

    // DMA unpack configuration and assembled matrix.
    output wire unpack_valid_o,
    input wire unpack_ready_i,
    output wire [255:0] unpack_command_o,
    input wire unpack_done_i,
    input wire matrix_valid_i,
    output wire matrix_ready_o,
    input wire [511:0] matrix_data_i,

    // Geometry snapshot.
    output wire geometry_cfg_valid_o,
    input wire geometry_cfg_ready_i,
    output wire [511:0] geometry_cfg_matrix_o,
    output wire [95:0] geometry_cfg_light_o,
    output wire [255:0] geometry_cfg_target_o,
    output wire [255:0] geometry_cfg_pixel_o,
    output wire geometry_cfg_wide_o,
    output wire raster_render_state_valid_o,
    input wire raster_render_state_ready_i,
    output wire [255:0] raster_render_state_tex_o,
    output wire [255:0] raster_render_state_pixel_o,
    output wire [255:0] raster_render_state_target_o,
    output wire raster_render_state_wide_o,
    output wire quad_render_state_valid_o,
    input wire quad_render_state_ready_i,
    output wire [255:0] quad_render_state_tex_o,
    output wire [255:0] quad_render_state_pixel_o,
    output wire [255:0] quad_render_state_target_o,
    output wire quad_render_state_wide_o,
    output wire texture_render_state_valid_o,
    input wire texture_render_state_ready_i,
    output wire [255:0] texture_render_state_tex_o,
    output wire [255:0] texture_render_state_pixel_o,
    output wire [255:0] texture_render_state_target_o,
    output wire texture_render_state_wide_o,
    output wire pixel_render_state_valid_o,
    input wire pixel_render_state_ready_i,
    output wire [255:0] pixel_render_state_tex_o,
    output wire [255:0] pixel_render_state_pixel_o,
    output wire [255:0] pixel_render_state_target_o,
    output wire pixel_render_state_wide_o,
    output wire geometry_draw_valid_o,
    input wire geometry_draw_ready_i,
    output wire [255:0] geometry_draw_command_o,
    output wire raster_draw_valid_o,
    input wire raster_draw_ready_i,
    output wire [255:0] raster_draw_command_o,
    output wire quad_draw_valid_o,
    input wire quad_draw_ready_i,
    output wire [255:0] quad_draw_command_o,
    output wire object_draw_valid_o,
    input wire object_draw_ready_i,
    output wire [255:0] object_draw_command_o,
    // Special command clients.
    output wire clear_valid_o,
    input wire clear_ready_i,
    output wire [255:0] clear_command_o,
    output wire [255:0] clear_target_o,
    output wire clear_wide_o,
    output wire resolve_valid_o,
    input wire resolve_ready_i,
    output wire [255:0] resolve_command_o,
    output wire [255:0] resolve_target_o,
    output wire resolve_wide_o,
    output wire palette_prepare_valid_o,
    input wire palette_prepare_ready_i,
    output wire [3:0] palette_prepare_group_o,
    input wire palette_prepared_valid_i,
    output wire palette_prepared_ready_o,
    output reg object_cfg_request_o,
    input wire object_cfg_done_i,
    output wire pack_valid_o,
    input wire pack_ready_i,
    output wire [255:0] pack_command_o,
    input wire pack_done_i,
    output wire object_publish_o,
    input wire object_published_i,

    // Per-unit finish levels and completion.
    output reg geometry_finish_o,
    input wire geometry_unit_done_i,
    output reg setup_finish_o,
    input wire setup_unit_done_i,
    output reg raster_finish_o,
    input wire raster_unit_done_i,
    output reg quad_finish_o,
    input wire quad_unit_done_i,
    output reg perspective_finish_o,
    input wire perspective_unit_done_i,
    output reg object_finish_o,
    input wire object_unit_done_i,
    output reg texture_finish_o,
    input wire texture_unit_done_i,
    output reg pixel_finish_o,
    input wire pixel_unit_done_i,
    output reg target_finish_o,
    input wire target_unit_done_i,
    output reg resolve_finish_o,
    input wire resolve_unit_done_i,
    output wire stop_o
);
    localparam [13:0] S_IDLE = 14'd1;
    localparam [13:0] S_LIST = 14'd2;
    localparam [13:0] S_NEXT = 14'd4;
    localparam [13:0] S_DECODE = 14'd8;
    localparam [13:0] S_CONFIG = 14'd16;
    localparam [13:0] S_PREP = 14'd32;
    localparam [13:0] S_DRAW = 14'd64;
    localparam [13:0] S_REQUEST = 14'd128;
    localparam [13:0] S_EXEC = 14'd256;
    localparam [13:0] S_RETIRE = 14'd512;
    localparam [13:0] S_COMPLETE = 14'd1024;
    localparam [13:0] S_DRAIN = 14'd2048;
    localparam [13:0] S_LATCH = 14'd4096;
    localparam [13:0] S_TEX_CHECK = 14'd8192;
    reg [13:0] state_r;
    reg wide_r;
    reg [15:0] remaining_r;
    reg [15:0] fetch_remaining_r;
    reg [31:0] fetch_addr_r;
    reg prefetch_busy_r;
    wire [4:0] fetch_batch_w;
    wire fetch_fire_w;
    reg [255:0] command_r;
    reg [511:0] matrix_r;
    reg [95:0] light_r;
    reg [255:0] tex_r;
    reg [255:0] pixel_r;
    reg [255:0] target_r;
    wire [255:0] fifo_data_w;
    reg [4:0] head_r;
    reg [4:0] tail_r;
    reg [5:0] count_r;
    wire push_w;
    wire pop_w;
    reg stop_r;
    reg error_pending_r;
    reg [31:0] error_code_r;
    reg [6:0] config_r;
    reg [5:0] draw_r;
    reg palette_needed_r;
    reg object_configured_r;
    reg palette_sent_r;
    reg [2:0] read_client_r;
    reg [31:0] read_addr_r;
    reg [31:0] read_bytes_r;
    reg read_done_r;
    wire request_ready_w;
    wire [6:0] request_ready_bus_w;
    reg [11:0] opcode_r;
    reg is_tri_r;
    reg is_quad_r;
    reg is_object_r;
    wire is_tri_w;
    wire is_quad_w;
    wire is_object_w;
    wire is_draw_w;
    wire draw_complete_w;
    wire all_done_w;
    reg [31:0] texture_size_r;
    reg [2:0] texture_phase_r;
    reg [3:0] texture_block_x_r;
    reg [3:0] texture_block_y_r;
    reg [31:0] texture_level_bytes_r;
    reg [31:0] texture_accumulated_r;
    reg [31:0] texture_total_r;
    reg [3:0] texture_mip_r;
    reg [3:0] texture_log_width_r;
    reg [3:0] texture_log_height_r;
    wire [3:0] texture_x_shift_w;
    wire [3:0] texture_y_shift_w;
    wire [3:0] texture_block_x_w;
    wire [3:0] texture_block_y_w;
    wire [4:0] texture_exponent_w;
    wire [31:0] texture_level_bytes_w;
    wire [31:0] texture_total_w;
    wire texture_last_w;
    wire texture_error_w;
    wire unused_command_w;
    assign unused_command_w = ^command_read_data_keep_i;
    assign is_tri_w = is_tri_r;
    assign is_quad_w = is_quad_r;
    assign is_object_w = is_object_r;
    assign is_draw_w = is_tri_w || is_quad_w || is_object_w;
    assign busy_o = !state_r[0];
    assign stop_o = stop_r;
    assign push_w = command_read_data_valid_i && command_read_data_ready_o && !stop_r;
    assign pop_w = state_r[2] && count_r != 0;
    assign command_read_data_ready_o = stop_r || count_r < 6'd32;
    // Reserve room for the entire prefetch interval. Command backpressure must
    // never occupy all DMA pool regions while the current draw needs operand reads.
    assign fetch_batch_w = fetch_remaining_r > 16'd16 ? 5'd16 : fetch_remaining_r[4:0];
    assign command_read_req_valid_o = busy_o && !state_r[11] && !stop_r
        && !prefetch_busy_r && fetch_remaining_r != 0 && count_r <= 6'd16;
    assign command_read_req_addr_o = fetch_addr_r;
    assign command_read_req_bytes_o = {22'b0, fetch_batch_w, 5'b0};
    assign fetch_fire_w = command_read_req_valid_o && command_read_req_ready_i;
    assign request_ready_bus_w[0] = command_read_req_ready_i;
    assign request_ready_bus_w[1] = matrix_read_req_ready_i;
    assign matrix_read_req_valid_o = state_r[7] && read_client_r == 3'd1;
    assign matrix_read_req_addr_o = read_addr_r;
    assign matrix_read_req_bytes_o = read_bytes_r;
    assign request_ready_bus_w[2] = vertex_read_req_ready_i;
    assign vertex_read_req_valid_o = state_r[7] && read_client_r == 3'd2;
    assign vertex_read_req_addr_o = read_addr_r;
    assign vertex_read_req_bytes_o = read_bytes_r;
    assign request_ready_bus_w[3] = quad_read_req_ready_i;
    assign quad_read_req_valid_o = state_r[7] && read_client_r == 3'd3;
    assign quad_read_req_addr_o = read_addr_r;
    assign quad_read_req_bytes_o = read_bytes_r;
    assign request_ready_bus_w[4] = object_read_req_ready_i;
    assign object_read_req_valid_o = state_r[7] && read_client_r == 3'd4;
    assign object_read_req_addr_o = read_addr_r;
    assign object_read_req_bytes_o = read_bytes_r;
    assign request_ready_bus_w[5] = texture_read_req_ready_i;
    assign texture_read_req_valid_o = state_r[7] && read_client_r == 3'd5;
    assign texture_read_req_addr_o = read_addr_r;
    assign texture_read_req_bytes_o = read_bytes_r;
    assign request_ready_bus_w[6] = palette_read_req_ready_i;
    assign palette_read_req_valid_o = state_r[7] && read_client_r == 3'd6;
    assign palette_read_req_addr_o = read_addr_r;
    assign palette_read_req_bytes_o = read_bytes_r;
    assign request_ready_w = request_ready_bus_w[read_client_r];
    assign unpack_valid_o = state_r[4] && config_r[0];
    assign unpack_command_o = command_r;
    assign matrix_ready_o = state_r[8] && opcode_r[0];
    assign geometry_cfg_valid_o = state_r[4] && config_r[1];
    assign geometry_cfg_matrix_o = matrix_r;
    assign geometry_cfg_light_o = light_r;
    assign geometry_cfg_target_o = target_r;
    assign geometry_cfg_pixel_o = pixel_r;
    assign geometry_cfg_wide_o = wide_r;
    assign raster_render_state_valid_o = state_r[4] && config_r[2];
    assign raster_render_state_tex_o = tex_r;
    assign raster_render_state_pixel_o = pixel_r;
    assign raster_render_state_target_o = target_r;
    assign raster_render_state_wide_o = wide_r;
    // microarch 4.12: only the active scan source receives the render snapshot.
    assign quad_render_state_valid_o = state_r[4] && config_r[6];
    assign quad_render_state_tex_o = tex_r;
    assign quad_render_state_pixel_o = pixel_r;
    assign quad_render_state_target_o = target_r;
    assign quad_render_state_wide_o = wide_r;
    assign texture_render_state_valid_o = state_r[4] && config_r[3];
    assign texture_render_state_tex_o = tex_r;
    assign texture_render_state_pixel_o = pixel_r;
    assign texture_render_state_target_o = target_r;
    assign texture_render_state_wide_o = wide_r;
    assign pixel_render_state_valid_o = state_r[4] && config_r[4];
    assign pixel_render_state_tex_o = tex_r;
    assign pixel_render_state_pixel_o = pixel_r;
    assign pixel_render_state_target_o = target_r;
    assign pixel_render_state_wide_o = wide_r;
    assign geometry_draw_valid_o = state_r[6] && draw_r[0];
    assign geometry_draw_command_o = command_r;
    assign raster_draw_valid_o = state_r[6] && draw_r[1];
    assign raster_draw_command_o = command_r;
    assign quad_draw_valid_o = state_r[6] && draw_r[2];
    assign quad_draw_command_o = command_r;
    assign object_draw_valid_o = state_r[6] && draw_r[3];
    assign object_draw_command_o = command_r;
    assign clear_valid_o = state_r[6] && draw_r[4];
    assign clear_command_o = command_r;
    assign clear_target_o = target_r;
    assign clear_wide_o = wide_r;
    assign resolve_valid_o = state_r[6] && draw_r[5];
    assign resolve_command_o = command_r;
    assign resolve_target_o = target_r;
    assign resolve_wide_o = wide_r;
    assign palette_prepare_valid_o = state_r[5] && palette_needed_r
        && !palette_sent_r;
    assign palette_prepare_group_o = tex_r[81:78];
    assign palette_prepared_ready_o = state_r[5] && palette_sent_r;
    assign pack_valid_o = state_r[4] && config_r[5] && object_configured_r;
    assign pack_command_o = command_r;
    assign draw_complete_w = target_unit_done_i
        && (!is_object_w || (object_unit_done_i && pack_done_i && write_dma_idle_i));
    assign object_publish_o = state_r[8] && is_object_w && draw_complete_w;
    assign all_done_w = geometry_unit_done_i && setup_unit_done_i && raster_unit_done_i
        && quad_unit_done_i && perspective_unit_done_i && object_unit_done_i
        && texture_unit_done_i && pixel_unit_done_i && target_unit_done_i
        && resolve_unit_done_i;

    // The command FIFO uses another instance of the fixed 32x256 distributed RAM.
    edrv32_ram_gpu_write_pool u_command_fifo (
        .clk_i(clk_i),
        .wr_en_i(push_w),
        .wr_addr_i(tail_r),
        .wr_data_i(command_read_data_data_i),
        .rd_en_i(pop_w),
        .rd_addr_i(head_r),
        .rd_data_o(fifo_data_w)
    );

    // Power-of-two mip dimensions reduce padded block footprints to shifts.
    // One level per cycle keeps the nine-level bound check out of the decode path.
    assign texture_x_shift_w = command_r[73:72] == 2'd2 ? 4'd1 : 4'd2;
    assign texture_y_shift_w = command_r[73:72] == 2'd0 ? 4'd2 : 4'd1;
    assign texture_block_x_w = texture_log_width_r > texture_x_shift_w
        ? texture_log_width_r - texture_x_shift_w : 4'b0;
    assign texture_block_y_w = texture_log_height_r > texture_y_shift_w
        ? texture_log_height_r - texture_y_shift_w : 4'b0;
    assign texture_exponent_w = {1'b0, texture_block_x_r} + {1'b0, texture_block_y_r};
    assign texture_level_bytes_w = 32'd8 << texture_exponent_w;
    assign texture_total_w = texture_total_r;
    assign texture_last_w = texture_mip_r + 4'd1 == command_r[77:74];
    assign texture_error_w = texture_total_w > 32'd196608;

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) texture_phase_r <= 0;
        else if (!state_r[13] || texture_phase_r == 4) texture_phase_r <= 0;
        else texture_phase_r <= texture_phase_r + 1'b1;
    end
    always @(posedge clk_i) begin
        if (state_r[13]) begin
            if (texture_phase_r == 0) begin
                texture_block_x_r <= texture_block_x_w;
                texture_block_y_r <= texture_block_y_w;
            end
            if (texture_phase_r == 1) texture_level_bytes_r <= texture_level_bytes_w;
            if (texture_phase_r == 2)
                texture_accumulated_r <= texture_size_r + texture_level_bytes_r;
            if (texture_phase_r == 3)
                texture_total_r <= {14'b0, command_r[49:37], 5'b0} + texture_accumulated_r;
        end
    end
    always @(posedge clk_i) begin
        if (state_r[12]) begin
            command_r <= fifo_data_w;
            opcode_r <= {fifo_data_w[7:0] == 8'h40,
                fifo_data_w[7:0] == 8'h31,
                fifo_data_w[7:0] == 8'h30,
                fifo_data_w[7:0] == 8'h22,
                fifo_data_w[7:0] == 8'h21,
                fifo_data_w[7:0] == 8'h20,
                fifo_data_w[7:0] == 8'h10,
                fifo_data_w[7:0] == 8'h05,
                fifo_data_w[7:0] == 8'h04,
                fifo_data_w[7:0] == 8'h03,
                fifo_data_w[7:0] == 8'h02,
                fifo_data_w[7:0] == 8'h01};
            is_tri_r <= fifo_data_w[7:0] == 8'h20;
            is_quad_r <= fifo_data_w[7:0] == 8'h21;
            is_object_r <= fifo_data_w[7:0] == 8'h22;
        end
        if (matrix_valid_i && matrix_ready_o) matrix_r <= matrix_data_i;
        if (state_r[13] && texture_phase_r == 4 &&
            texture_last_w && !texture_error_w)
            tex_r <= command_r;
        if (state_r[3]) begin
            case (opcode_r)
                12'd2: light_r <= {command_r[151:128], command_r[119:96], command_r[79:32]};
                12'd8: pixel_r <= command_r;
                12'd16: target_r <= command_r;
                default: begin end
            endcase
        end
    end

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            state_r <= S_IDLE;
            wide_r <= 1'b0;
            remaining_r <= 16'b0;
            fetch_remaining_r <= 16'b0;
            fetch_addr_r <= 32'b0;
            prefetch_busy_r <= 1'b0;
            head_r <= 5'b0;
            tail_r <= 5'b0;
            count_r <= 6'b0;
            stop_r <= 1'b0;
            done_o <= 1'b0;
            error_o <= 1'b0;
            err_code_o <= 32'b0;
            error_pending_r <= 1'b0;
            error_code_r <= 32'b0;
            dma_start_o <= 1'b0;
            config_r <= 7'b0;
            draw_r <= 6'b0;
            palette_needed_r <= 1'b0;
            palette_sent_r <= 1'b0;
            object_cfg_request_o <= 1'b0;
            object_configured_r <= 1'b0;
            read_client_r <= 3'b0;
            read_addr_r <= 32'b0;
            read_bytes_r <= 32'b0;
            read_done_r <= 1'b0;
            texture_size_r <= 32'b0;
            texture_mip_r <= 4'b0;
            texture_log_width_r <= 4'b0;
            texture_log_height_r <= 4'b0;
            geometry_finish_o <= 1'b1;
            setup_finish_o <= 1'b1;
            raster_finish_o <= 1'b1;
            quad_finish_o <= 1'b1;
            perspective_finish_o <= 1'b1;
            object_finish_o <= 1'b1;
            texture_finish_o <= 1'b1;
            pixel_finish_o <= 1'b1;
            target_finish_o <= 1'b1;
            resolve_finish_o <= 1'b1;
        end else begin
            done_o <= 1'b0;
            error_o <= 1'b0;
            dma_start_o <= 1'b0;
            object_cfg_request_o <= 1'b0;
            if (fetch_fire_w) begin
                prefetch_busy_r <= 1'b1;
                fetch_addr_r <= fetch_addr_r + {22'b0, fetch_batch_w, 5'b0};
                fetch_remaining_r <= fetch_remaining_r - {11'b0, fetch_batch_w};
            end
            if (command_read_data_valid_i && command_read_data_ready_o
                && command_read_data_last_i) prefetch_busy_r <= 1'b0;
            if (push_w) tail_r <= tail_r + 5'd1;
            if (pop_w) head_r <= head_r + 5'd1;
            begin
                case ({push_w, pop_w})
                    2'b10: count_r <= count_r + 6'd1;
                    2'b01: count_r <= count_r - 6'd1;
                    default: begin end
                endcase
            end
            if (object_cfg_done_i) object_configured_r <= 1'b1;
            if (object_read_done_i && is_object_w) read_done_r <= 1'b1;
            if (unpack_done_i && !is_object_w && state_r[8]) read_done_r <= 1'b1;
            (* parallel_case *) case (1'b1)
                state_r[0]: begin
                    stop_r <= 1'b0;
                    if (start_i && enable_i) begin
                        wide_r <= wide_i;
                        remaining_r <= desc_count_i;
                        fetch_remaining_r <= desc_count_i;
                        fetch_addr_r <= desc_base_i;
                        prefetch_busy_r <= 1'b0;
                        error_pending_r <= 1'b0;
                        dma_start_o <= 1'b1;
                        head_r <= 5'b0;
                        tail_r <= 5'b0;
                        count_r <= 6'b0;
                        state_r <= desc_count_i == 0 ? S_COMPLETE : S_LIST;
                    end
                end
                state_r[1]: if (fetch_fire_w) state_r <= S_NEXT;
                state_r[2]: if (count_r != 0) state_r <= S_LATCH;
                state_r[12]: state_r <= S_DECODE;
                state_r[3]: begin
                    geometry_finish_o <= 1'b0;
                    setup_finish_o <= 1'b0;
                    raster_finish_o <= 1'b0;
                    quad_finish_o <= 1'b0;
                    perspective_finish_o <= 1'b0;
                    object_finish_o <= 1'b0;
                    texture_finish_o <= 1'b0;
                    pixel_finish_o <= 1'b0;
                    target_finish_o <= 1'b0;
                    resolve_finish_o <= 1'b0;
                    config_r <= 7'b0;
                    draw_r <= 6'b0;
                    palette_needed_r <= 1'b0;
                    palette_sent_r <= 1'b0;
                    object_configured_r <= 1'b0;
                    read_done_r <= 1'b0;
                    read_addr_r <= {command_r[95:69], 5'b0};
                    read_bytes_r <= 32'b0;
                    read_client_r <= 3'b0;
                    state_r <= S_CONFIG;
                    case (opcode_r)
                        12'd1: begin
                            read_client_r <= 3'd1;
                            read_bytes_r <= 32'd64;
                            config_r[0] <= 1'b1;
                        end
                        12'd2, 12'd8, 12'd16: state_r <= S_RETIRE;
                        12'd4: begin
                            texture_size_r <= 32'b0;
                            texture_mip_r <= 4'b0;
                            texture_log_width_r <= command_r[67:64];
                            texture_log_height_r <= command_r[71:68];
                            state_r <= S_TEX_CHECK;
                        end
                        12'd32: draw_r[4] <= 1'b1;
                        12'd64: begin
                            config_r[4:1] <= 4'b1111;
                            config_r[0] <= command_r[119:96] != 0;
                            draw_r[1:0] <= 2'b11;
                            read_client_r <= 3'd2;
                            read_bytes_r <= ({8'b0, command_r[119:96]} << 5)
                                + ({8'b0, command_r[119:96]} << 4);
                            palette_needed_r <= tex_r[73:72] != 2'd2 && tex_r[83:82] != 0;
                        end
                        12'd128: begin
                            config_r[4:3] <= 2'b11;
                            config_r[6] <= 1'b1;
                            config_r[0] <= command_r[119:96] != 0;
                            draw_r[2] <= 1'b1;
                            read_client_r <= 3'd3;
                            read_bytes_r <= {4'b0, command_r[119:96], 4'b0};
                        end
                        12'd256: begin
                            config_r[4:3] <= 2'b11;
                            config_r[6] <= 1'b1;
                            config_r[5] <= 1'b1;
                            draw_r[3:2] <= 2'b11;
                            object_cfg_request_o <= 1'b1;
                            read_client_r <= 3'd4;
                            read_bytes_r <= {3'b0, command_r[119:96], 5'b0};
                        end
                        12'd512: begin
                            read_client_r <= 3'd5;
                            read_bytes_r <= {13'b0, command_r[146:133], 5'b0};
                            config_r[0] <= command_r[146:133] != 0;
                        end
                        12'd1024: begin
                            read_client_r <= 3'd6;
                            read_bytes_r <= {21'b0, command_r[104:96], 2'b0};
                            config_r[0] <= 1'b1;
                        end
                        12'd2048: draw_r[5] <= 1'b1;
                        default: begin
                            error_pending_r <= 1'b1;
                            error_code_r <= 32'd1;
                            stop_r <= 1'b1;
                            state_r <= S_DRAIN;
                        end
                    endcase
                    begin
                        if (opcode_r[9] && {14'b0, command_r[113:101], 5'b0}
                            + {13'b0, command_r[146:133], 5'b0} > 32'd196608) begin
                            error_pending_r <= 1'b1;
                            error_code_r <= 32'd4;
                            stop_r <= 1'b1;
                            state_r <= S_DRAIN;
                        end
                    end
                end
                state_r[13]: if (texture_phase_r == 4) begin
                    texture_size_r <= texture_accumulated_r;
                    texture_mip_r <= texture_mip_r + 4'd1;
                    if (texture_log_width_r != 0)
                        texture_log_width_r <= texture_log_width_r - 4'd1;
                    if (texture_log_height_r != 0)
                        texture_log_height_r <= texture_log_height_r - 4'd1;
                    if (texture_last_w) begin
                        if (texture_error_w) begin
                            error_pending_r <= 1'b1;
                            error_code_r <= 32'd3;
                            stop_r <= 1'b1;
                            state_r <= S_DRAIN;
                        end else state_r <= S_RETIRE;
                    end
                end
                state_r[4]: begin
                    if (unpack_valid_o && unpack_ready_i) config_r[0] <= 1'b0;
                    if (geometry_cfg_valid_o && geometry_cfg_ready_i) config_r[1] <= 1'b0;
                    if (raster_render_state_valid_o && raster_render_state_ready_i)
                        config_r[2] <= 1'b0;
                    if (texture_render_state_valid_o && texture_render_state_ready_i)
                        config_r[3] <= 1'b0;
                    if (pixel_render_state_valid_o && pixel_render_state_ready_i)
                        config_r[4] <= 1'b0;
                    if (pack_valid_o && pack_ready_i) config_r[5] <= 1'b0;
                    if (quad_render_state_valid_o && quad_render_state_ready_i)
                        config_r[6] <= 1'b0;
                    if (config_r == 0) state_r <= S_PREP;
                end
                state_r[5]: begin
                    if (palette_prepare_valid_o && palette_prepare_ready_i)
                        palette_sent_r <= 1'b1;
                    if (!palette_needed_r || (palette_prepared_valid_i && palette_prepared_ready_o))
                        state_r <= S_DRAW;
                end
                state_r[6]: begin
                    if (geometry_draw_valid_o && geometry_draw_ready_i) draw_r[0] <= 1'b0;
                    if (raster_draw_valid_o && raster_draw_ready_i) draw_r[1] <= 1'b0;
                    if (quad_draw_valid_o && quad_draw_ready_i) draw_r[2] <= 1'b0;
                    if (object_draw_valid_o && object_draw_ready_i) draw_r[3] <= 1'b0;
                    if (clear_valid_o && clear_ready_i) draw_r[4] <= 1'b0;
                    if (resolve_valid_o && resolve_ready_i) draw_r[5] <= 1'b0;
                    if (draw_r == 0) begin
                        state_r <= read_bytes_r == 0 ? S_EXEC : S_REQUEST;
                        if (read_bytes_r == 0) read_done_r <= 1'b1;
                    end
                end
                state_r[7]: if (request_ready_w) state_r <= S_EXEC;
                state_r[8]: begin
                    geometry_finish_o <= !is_tri_w || read_done_r;
                    setup_finish_o <= !is_tri_w || geometry_unit_done_i;
                    raster_finish_o <= !is_tri_w || setup_unit_done_i;
                    object_finish_o <= !is_object_w || read_done_r;
                    quad_finish_o <= !(is_quad_w || is_object_w)
                        || (is_object_w ? object_unit_done_i : read_done_r);
                    perspective_finish_o <= !is_draw_w
                        || (is_tri_w ? raster_unit_done_i : quad_unit_done_i);
                    // read_done_r follows unpack's final consumer handshake for both loads.
                    texture_finish_o <= (opcode_r[9] || opcode_r[10]) ? read_done_r
                        : (!is_draw_w || perspective_unit_done_i);
                    pixel_finish_o <= !is_draw_w || texture_unit_done_i;
                    target_finish_o <= opcode_r[11] ? resolve_unit_done_i
                        : (!is_draw_w || pixel_unit_done_i);
                    resolve_finish_o <= 1'b1;
                    case (opcode_r)
                        12'd1: if (matrix_valid_i) state_r <= S_RETIRE;
                        12'd32: if (target_unit_done_i) state_r <= S_RETIRE;
                        12'd64, 12'd128: if (draw_complete_w) state_r <= S_RETIRE;
                        12'd256: if (object_publish_o && object_published_i) state_r <= S_RETIRE;
                        12'd512: if (read_done_r && texture_unit_done_i) state_r <= S_RETIRE;
                        12'd1024: if (read_done_r) state_r <= S_RETIRE;
                        12'd2048: if (resolve_unit_done_i && target_unit_done_i && write_dma_idle_i)
                            state_r <= S_RETIRE;
                        default: begin end
                    endcase
                end
                state_r[9]: begin
                    geometry_finish_o <= 1'b1;
                    setup_finish_o <= 1'b1;
                    raster_finish_o <= 1'b1;
                    quad_finish_o <= 1'b1;
                    perspective_finish_o <= 1'b1;
                    object_finish_o <= 1'b1;
                    texture_finish_o <= 1'b1;
                    pixel_finish_o <= 1'b1;
                    target_finish_o <= 1'b1;
                    resolve_finish_o <= 1'b1;
                    remaining_r <= remaining_r - 16'd1;
                    state_r <= remaining_r == 16'd1 ? S_COMPLETE : S_NEXT;
                end
                state_r[10]: begin
                    if (read_dma_idle_i && write_dma_idle_i) begin
                        done_o <= 1'b1;
                        state_r <= S_IDLE;
                    end
                end
                state_r[11]: begin
                    count_r <= 6'b0;
                    geometry_finish_o <= 1'b1;
                    setup_finish_o <= 1'b1;
                    raster_finish_o <= 1'b1;
                    quad_finish_o <= 1'b1;
                    perspective_finish_o <= 1'b1;
                    object_finish_o <= 1'b1;
                    texture_finish_o <= 1'b1;
                    pixel_finish_o <= 1'b1;
                    target_finish_o <= 1'b1;
                    resolve_finish_o <= 1'b1;
                    if (read_dma_idle_i && write_dma_idle_i && all_done_w) begin
                        state_r <= S_IDLE;
                        if (error_pending_r) begin
                            error_o <= 1'b1;
                            err_code_o <= error_code_r;
                        end
                    end
                end
                default: begin end
            endcase
            begin
                if (busy_o && !dma_start_o && !state_r[11]
                    && (abort_i || soft_rst_i || read_dma_error_i || write_dma_error_i)) begin
                    stop_r <= 1'b1;
                    state_r <= S_DRAIN;
                    if (read_dma_error_i || write_dma_error_i) begin
                        error_pending_r <= 1'b1;
                        error_code_r <= 32'd2;
                    end
                end
            end
        end
    end
endmodule
