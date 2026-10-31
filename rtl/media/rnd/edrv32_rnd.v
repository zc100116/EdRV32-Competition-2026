// File: edrv32_rnd.v
// Spec: rnd-spec v0.3 3-6; SoC 4.2, 4.3, 7.1, 7.2, 8.11.
// Description: Ordered 64-byte command execution, APB control and shared P4 DMA arbitration.
//              Commands start only after the preceding command's final write response.
// Clock domain: clk_mem.
module edrv32_rnd (
    // Clock and reset.
    input wire clk_mem_i,
    input wire rst_mem_n_i,

    // Media APB slave, slot 4.
    input wire [11:0] apb_paddr_i,
    input wire apb_psel_i,
    input wire apb_penable_i,
    input wire apb_pwrite_i,
    input wire [31:0] apb_pwdata_i,
    input wire [3:0] apb_pstrb_i,
    output wire apb_pready_o,
    output wire [31:0] apb_prdata_o,
    output wire apb_pslverr_o,

    // P4 AXI256 read channels.
    output wire p4_arid_o,
    output wire [31:0] p4_araddr_o,
    output wire [3:0] p4_arlen_o,
    output wire p4_arvalid_o,
    input wire p4_arready_i,
    input wire p4_rid_i,
    input wire [255:0] p4_rdata_i,
    input wire [1:0] p4_rresp_i,
    input wire p4_rlast_i,
    input wire p4_rvalid_i,
    output wire p4_rready_o,

    // P4 AXI256 write channels.
    output wire p4_awid_o,
    output wire [31:0] p4_awaddr_o,
    output wire [3:0] p4_awlen_o,
    output wire p4_awvalid_o,
    input wire p4_awready_i,
    output wire [255:0] p4_wdata_o,
    output wire [31:0] p4_wstrb_o,
    output wire p4_wlast_o,
    output wire p4_wvalid_o,
    input wire p4_wready_i,
    input wire p4_bid_i,
    input wire [1:0] p4_bresp_i,
    input wire p4_bvalid_i,
    output wire p4_bready_o,

    // PLIC source 11.
    output wire irq_o
);
    localparam [4:0] S_IDLE = 5'd0;
    localparam [4:0] S_FETCH = 5'd1;
    localparam [4:0] S_FETCH_WAIT = 5'd2;
    localparam [4:0] S_CHECK = 5'd3;
    localparam [4:0] S_BEGIN = 5'd4;
    localparam [4:0] S_DRAW = 5'd5;
    localparam [4:0] S_FILL = 5'd6;
    localparam [4:0] S_COPY = 5'd7;
    localparam [4:0] S_BLUR = 5'd8;
    localparam [4:0] S_SHADOW = 5'd9;
    localparam [4:0] S_COMPLETE = 5'd10;
    localparam [4:0] S_FINISH = 5'd11;
    localparam [4:0] S_DRAIN = 5'd12;
    localparam [4:0] S_BLIT = 5'd13;
    localparam [4:0] S_CLIP = 5'd14;
    localparam [4:0] S_PARAM = 5'd15;
    localparam [4:0] S_PARAM_WAIT = 5'd16;
    reg [4:0] state_r;
    reg [63:0] round_area_r;
    reg [1023:0] parameters_r;
    reg [1:0] parameter_beat_r;
    wire geometry_w;
    assign geometry_w = op_w >= 8'h09 && op_w <= 8'h0b;
    reg signed [17:0] rect_left_r;
    reg signed [17:0] rect_top_r;
    reg signed [17:0] rect_right_r;
    reg signed [17:0] rect_bottom_r;
    reg signed [17:0] clip_left_r;
    reg signed [17:0] clip_top_r;
    reg signed [17:0] clip_right_r;
    reg signed [17:0] clip_bottom_r;
    reg inverted_r;
    wire signed [17:0] expansion_w;
    wire unused_empty_w;
    reg fetch_half_r;
    reg [511:0] command_r;
    reg [31:0] list_base_r;
    reg [15:0] list_count_r;
    reg [31:0] source_stride_r;
    reg simple_valid_r;
    reg [255:0] simple_data_r;
    reg [31:0] simple_strb_r;
    wire start_w;
    wire abort_w;
    wire soft_reset_w;
    wire busy_w;
    wire cancel_w;
    wire [31:0] desc_base_w;
    wire [15:0] desc_count_w;
    wire [31:0] cur_desc_w;
    wire read_fault_w;
    wire write_fault_w;
    wire illegal_w;
    wire empty_w;
    wire fast_fill_w;
    wire [1:0] error_w;
    wire [4:0] pixels_w;
    wire [7:0] op_w;
    wire unused_argb_w;
    wire [3:0] unused_format_w;
    wire [15:0] unused_flags_w;
    wire signed [17:0] unused_left_w;
    wire signed [17:0] unused_top_w;
    wire signed [17:0] unused_right_w;
    wire signed [17:0] unused_bottom_w;
    wire [16:0] unused_width_w;
    wire [16:0] unused_height_w;
    wire rd_desc_valid_w;
    wire rd_desc_ready_w;
    wire [31:0] rd_addr_w;
    wire [15:0] rd_bytes_w;
    wire rd_data_valid_w;
    wire [255:0] rd_data_w;
    wire rd_done_w;
    wire rd_idle_w;
    wire unused_rd_error_w;
    wire unused_sol_w;
    wire unused_eol_w;
    wire unused_eof_w;
    wire wr_desc_valid_w;
    wire wr_desc_ready_w;
    wire [31:0] wr_addr_w;
    wire [15:0] wr_bytes_w;
    wire wr_data_valid_w;
    wire wr_data_ready_w;
    wire [255:0] wr_data_w;
    wire [31:0] wr_strb_w;
    wire wr_done_w;
    wire wr_idle_w;
    wire unused_wr_error_w;
    wire scalar_write_w;
    wire draw_rd_valid_w;
    wire [31:0] draw_rd_addr_w;
    wire [15:0] draw_rd_bytes_w;
    wire [15:0] draw_wr_bytes_w;
    wire draw_data_valid_w;
    wire [31:0] draw_blend_tag_w;
    wire draw_wr_valid_w;
    wire [31:0] draw_wr_addr_w;
    wire [255:0] draw_wr_data_w;
    wire [31:0] draw_wr_strb_w;
    wire draw_done_w;
    wire unused_draw_idle_w;
    wire [4:0] draw_pixels_w;
    wire draw_read_wait_w;
    wire draw_write_wait_w;
    wire copy_rd_valid_w;
    wire [31:0] copy_rd_addr_w;
    wire [15:0] copy_rd_bytes_w;
    wire copy_wr_valid_w;
    wire [31:0] copy_wr_addr_w;
    wire [15:0] copy_wr_bytes_w;
    wire copy_data_valid_w;
    wire [255:0] copy_data_w;
    wire [31:0] copy_strb_w;
    wire copy_done_w;
    wire [4:0] copy_pixels_w;
    wire fill_wr_valid_w;
    wire [31:0] fill_wr_addr_w;
    wire [15:0] fill_wr_bytes_w;
    wire fill_data_valid_w;
    wire [255:0] fill_data_w;
    wire [31:0] fill_strb_w;
    wire fill_done_w;
    wire [4:0] fill_pixels_w;
    wire blur_rd_valid_w;
    wire [31:0] blur_rd_addr_w;
    wire blur_wr_valid_w;
    wire [31:0] blur_wr_addr_w;
    wire [255:0] blur_wr_data_w;
    wire [31:0] blur_wr_strb_w;
    wire blur_done_w;
    wire [4:0] blur_pixels_w;
    wire [511:0] shadow_command_w;
    wire [31:0] shadow_stride_w;

    wire blit_eligible_w;
    wire [17:0] row_pixels_w;
    wire [2:0] source_offset_w;
    wire [4:0] source_low_w;
    wire [4:0] target_low_w;
    wire blit_rd_valid_w;
    wire [31:0] blit_rd_addr_w;
    wire [15:0] blit_rd_bytes_w;
    wire blit_wr_valid_w;
    wire [31:0] blit_wr_addr_w;
    wire [15:0] blit_wr_bytes_w;
    wire blit_data_valid_w;
    wire [255:0] blit_data_w;
    wire [31:0] blit_strb_w;
    wire blit_done_w;
    wire [4:0] blit_pixels_w;
    wire blit_read_wait_w;
    wire blit_write_wait_w;
    wire draw_blend_valid_w;
    wire [63:0] draw_blend_src_w;
    wire [63:0] draw_blend_dst_w;
    wire blit_blend_valid_w;
    wire [63:0] blit_blend_src_w;
    wire [63:0] blit_blend_dst_w;
    wire [31:0] blit_blend_tag_w;
    wire blend_ready_w;
    wire blend_valid_w;
    wire [63:0] blend_pixel_w;
    wire [31:0] blend_tag_w;
    wire unused_geometry_w;

    assign row_pixels_w = clip_right_r - clip_left_r + 18'd1;
    assign source_offset_w = command_r[322:320] + clip_left_r[2:0] - command_r[162:160];
    assign source_low_w = command_r[260:256] + {source_offset_w, 2'd0};
    assign target_low_w = command_r[36:32] + {clip_left_r[2:0], 2'd0};
    assign blit_eligible_w = op_w == 8'h04 && command_r[8] && command_r[15:12] == 4'd1 &&
        command_r[23:16] == 0 && command_r[383:352] == 32'h0001_0000 &&
        command_r[415:384] == 32'h0001_0000 && command_r[68:64] == 0 &&
        command_r[292:288] == 0 && row_pixels_w[2:0] == 0 &&
        target_low_w == 0 && source_low_w == 0;
    assign unused_geometry_w = ^row_pixels_w[17:3];
    assign expansion_w = op_w == 8'h06 ? $signed({13'd0, command_r[292:288]}) : 18'sd0;
    assign empty_w = inverted_r || clip_right_r < clip_left_r || clip_bottom_r < clip_top_r;
    assign busy_w = state_r != S_IDLE || !rd_idle_w || !wr_idle_w;
    assign read_fault_w = p4_rvalid_i && p4_rready_o && p4_rresp_i != 0;
    assign write_fault_w = p4_bvalid_i && p4_bready_o && p4_bresp_i != 0;
    assign cancel_w = abort_w || soft_reset_w || read_fault_w || write_fault_w;
    assign error_w = write_fault_w ? 2'd2 : read_fault_w ? 2'd1 :
        state_r == S_CHECK && illegal_w && !abort_w ? 2'd3 : 2'd0;
    assign pixels_w = state_r == S_DRAW ? draw_pixels_w : state_r == S_COPY ?
        copy_pixels_w : state_r == S_FILL ? fill_pixels_w :
        state_r == S_BLUR ? blur_pixels_w : state_r == S_BLIT ? blit_pixels_w : 5'd0;
    edrv32_rnd_regs u_regs (
        .clk_i(clk_mem_i),
        .rst_n_i(rst_mem_n_i),
        .apb_paddr_i(apb_paddr_i),
        .apb_psel_i(apb_psel_i),
        .apb_penable_i(apb_penable_i),
        .apb_pwrite_i(apb_pwrite_i),
        .apb_pwdata_i(apb_pwdata_i),
        .apb_pstrb_i(apb_pstrb_i),
        .apb_pready_o(apb_pready_o),
        .apb_prdata_o(apb_prdata_o),
        .apb_pslverr_o(apb_pslverr_o),
        .busy_i(busy_w),
        .command_done_i(state_r == S_COMPLETE),
        .list_done_i(state_r == S_FINISH || (start_w && desc_count_w == 0)),
        .error_i(error_w),
        .pixel_count_i(pixels_w),
        .read_beat_i(p4_rvalid_i && p4_rready_o),
        .write_beat_i(p4_wvalid_o && p4_wready_i),
        .read_wait_i((state_r == S_DRAW && draw_read_wait_w) ||
            (state_r == S_BLIT && blit_read_wait_w)),
        .write_wait_i((state_r == S_DRAW && draw_write_wait_w) ||
            (state_r == S_BLIT && blit_write_wait_w)),
        .start_o(start_w),
        .abort_o(abort_w),
        .soft_reset_o(soft_reset_w),
        .desc_base_o(desc_base_w),
        .desc_count_o(desc_count_w),
        .cur_desc_o(cur_desc_w),
        .irq_o(irq_o)
    );
    edrv32_rnd_decode u_decode (
        .command_i(command_r),
        .illegal_o(illegal_w),
        .empty_o(unused_empty_w),
        .op_o(op_w),
        .argb_o(unused_argb_w),
        .src_fmt_o(unused_format_w),
        .flags_o(unused_flags_w),
        .left_o(unused_left_w),
        .top_o(unused_top_w),
        .right_o(unused_right_w),
        .bottom_o(unused_bottom_w),
        .width_o(unused_width_w),
        .height_o(unused_height_w),
        .fast_fill_o(fast_fill_w)
    );
    edrv32_rnd_draw u_draw (
        .clk_i(clk_mem_i),
        .rst_n_i(rst_mem_n_i),
        .start_i(state_r == S_SHADOW || (state_r == S_BEGIN &&
            !fast_fill_w && !blit_eligible_w && op_w != 8'h05 && op_w != 8'h06 && op_w != 8'h07)),
        .command_i(command_r),
        .source_stride_i(source_stride_r),
        .round_area_i(round_area_r),
        .parameters_i(parameters_r),
        .cancel_i(cancel_w),
        .idle_o(unused_draw_idle_w),
        .done_o(draw_done_w),
        .pixel_count_o(draw_pixels_w),
        .read_wait_o(draw_read_wait_w),
        .write_wait_o(draw_write_wait_w),
        .rd_valid_o(draw_rd_valid_w),
        .rd_ready_i(rd_desc_ready_w && state_r == S_DRAW),
        .rd_addr_o(draw_rd_addr_w),
        .rd_bytes_o(draw_rd_bytes_w),
        .rd_done_i(rd_done_w && state_r == S_DRAW),
        .rd_data_valid_i(rd_data_valid_w && state_r == S_DRAW),
        .rd_data_i(rd_data_w),
        .wr_valid_o(draw_wr_valid_w),
        .wr_ready_i(wr_desc_ready_w && state_r == S_DRAW),
        .wr_addr_o(draw_wr_addr_w),
        .wr_bytes_o(draw_wr_bytes_w),
        .wr_data_valid_o(draw_data_valid_w),
        .wr_data_ready_i(wr_data_ready_w && state_r == S_DRAW),
        .wr_data_o(draw_wr_data_w),
        .wr_strb_o(draw_wr_strb_w),
        .wr_done_i(wr_done_w && state_r == S_DRAW),
        .blend_valid_o(draw_blend_valid_w),
        .blend_ready_i(blend_ready_w && state_r == S_DRAW),
        .blend_src_o(draw_blend_src_w),
        .blend_dst_o(draw_blend_dst_w),
        .blend_tag_o(draw_blend_tag_w),
        .blend_tag_i(blend_tag_w),
        .blend_valid_i(blend_valid_w && state_r == S_DRAW),
        .blend_pixel_i(blend_pixel_w)
    );
    edrv32_rnd_copy u_copy (
        .clk_i(clk_mem_i),
        .rst_n_i(rst_mem_n_i),
        .start_i(state_r == S_BEGIN && op_w == 8'h05),
        .cancel_i(cancel_w),
        .command_i(command_r),
        .done_o(copy_done_w),
        .pixel_count_o(copy_pixels_w),
        .rd_valid_o(copy_rd_valid_w),
        .rd_ready_i(rd_desc_ready_w && state_r == S_COPY),
        .rd_addr_o(copy_rd_addr_w),
        .rd_bytes_o(copy_rd_bytes_w),
        .rd_data_valid_i(rd_data_valid_w && state_r == S_COPY),
        .rd_data_i(rd_data_w),
        .rd_done_i(rd_done_w && state_r == S_COPY),
        .wr_valid_o(copy_wr_valid_w),
        .wr_ready_i(wr_desc_ready_w && state_r == S_COPY),
        .wr_addr_o(copy_wr_addr_w),
        .wr_bytes_o(copy_wr_bytes_w),
        .wr_data_valid_o(copy_data_valid_w),
        .wr_data_ready_i(wr_data_ready_w && state_r == S_COPY),
        .wr_data_o(copy_data_w),
        .wr_strb_o(copy_strb_w),
        .wr_done_i(wr_done_w && state_r == S_COPY)
    );
    edrv32_rnd_fill u_fill (
        .clk_i(clk_mem_i),
        .rst_n_i(rst_mem_n_i),
        .start_i(state_r == S_BEGIN && fast_fill_w),
        .cancel_i(cancel_w),
        .command_i(command_r),
        .done_o(fill_done_w),
        .pixel_count_o(fill_pixels_w),
        .wr_valid_o(fill_wr_valid_w),
        .wr_ready_i(wr_desc_ready_w && state_r == S_FILL),
        .wr_addr_o(fill_wr_addr_w),
        .wr_bytes_o(fill_wr_bytes_w),
        .wr_data_valid_o(fill_data_valid_w),
        .wr_data_ready_i(wr_data_ready_w && state_r == S_FILL),
        .wr_data_o(fill_data_w),
        .wr_strb_o(fill_strb_w),
        .wr_done_i(wr_done_w && state_r == S_FILL)
    );
    edrv32_rnd_blur u_blur (
        .clk_i(clk_mem_i),
        .rst_n_i(rst_mem_n_i),
        .start_i(state_r == S_BEGIN && (op_w == 8'h06 || op_w == 8'h07)),
        .cancel_i(cancel_w),
        .command_i(command_r),
        .done_o(blur_done_w),
        .pixel_count_o(blur_pixels_w),
        .shadow_draw_o(shadow_command_w),
        .shadow_stride_o(shadow_stride_w),
        .rd_valid_o(blur_rd_valid_w),
        .rd_ready_i(rd_desc_ready_w && state_r == S_BLUR),
        .rd_addr_o(blur_rd_addr_w),
        .rd_data_valid_i(rd_data_valid_w && state_r == S_BLUR),
        .rd_data_i(rd_data_w),
        .wr_valid_o(blur_wr_valid_w),
        .wr_ready_i(wr_desc_ready_w && state_r == S_BLUR),
        .wr_addr_o(blur_wr_addr_w),
        .wr_data_o(blur_wr_data_w),
        .wr_strb_o(blur_wr_strb_w),
        .wr_done_i(wr_done_w && state_r == S_BLUR)
    );

    edrv32_rnd_blit u_blit (
        .clk_i(clk_mem_i),
        .rst_n_i(rst_mem_n_i),
        .start_i(state_r == S_BEGIN && blit_eligible_w),
        .cancel_i(cancel_w),
        .command_i(command_r),
        .done_o(blit_done_w),
        .pixel_count_o(blit_pixels_w),
        .read_wait_o(blit_read_wait_w),
        .write_wait_o(blit_write_wait_w),
        .rd_valid_o(blit_rd_valid_w),
        .rd_ready_i(rd_desc_ready_w && state_r == S_BLIT),
        .rd_addr_o(blit_rd_addr_w),
        .rd_bytes_o(blit_rd_bytes_w),
        .rd_data_valid_i(rd_data_valid_w && state_r == S_BLIT),
        .rd_data_i(rd_data_w),
        .rd_done_i(rd_done_w && state_r == S_BLIT),
        .wr_valid_o(blit_wr_valid_w),
        .wr_ready_i(wr_desc_ready_w && state_r == S_BLIT),
        .wr_addr_o(blit_wr_addr_w),
        .wr_bytes_o(blit_wr_bytes_w),
        .wr_data_valid_o(blit_data_valid_w),
        .wr_data_ready_i(wr_data_ready_w && state_r == S_BLIT),
        .wr_data_o(blit_data_w),
        .wr_strb_o(blit_strb_w),
        .wr_done_i(wr_done_w && state_r == S_BLIT),
        .blend_valid_o(blit_blend_valid_w),
        .blend_ready_i(blend_ready_w && state_r == S_BLIT),
        .blend_src_o(blit_blend_src_w),
        .blend_dst_o(blit_blend_dst_w),
        .blend_tag_o(blit_blend_tag_w),
        .blend_valid_i(blend_valid_w && state_r == S_BLIT),
        .blend_pixel_i(blend_pixel_w),
        .blend_tag_i(blend_tag_w)
    );
    edrv32_rnd_alpha_pipe u_alpha (
        .clk_i(clk_mem_i),
        .rst_n_i(rst_mem_n_i),
        .in_valid_i((state_r == S_DRAW && draw_blend_valid_w) ||
            (state_r == S_BLIT && blit_blend_valid_w)),
        .in_ready_o(blend_ready_w),
        .in_src_i(state_r == S_BLIT ? blit_blend_src_w : draw_blend_src_w),
        .in_dst_i(state_r == S_BLIT ? blit_blend_dst_w : draw_blend_dst_w),
        .in_argb_i(command_r[8]),
        .in_mode_i(op_w == 8'h04 ? command_r[21:20] : 2'd0),
        .in_tag_i(state_r == S_BLIT ? blit_blend_tag_w : draw_blend_tag_w),
        .out_valid_o(blend_valid_w),
        .out_ready_i(1'b1),
        .out_pixel_o(blend_pixel_w),
        .out_tag_o(blend_tag_w),
        .clear_i(cancel_w)
    );

    // The command scheduler grants one client for a descriptor; R remains ordered on ID 0.
    assign rd_desc_valid_w = !cancel_w && (state_r == S_FETCH || state_r == S_PARAM ||
        (state_r == S_DRAW && draw_rd_valid_w) ||
        (state_r == S_COPY && copy_rd_valid_w) ||
        (state_r == S_BLUR && blur_rd_valid_w) ||
        (state_r == S_BLIT && blit_rd_valid_w));
    assign rd_addr_w = state_r == S_FETCH ? list_base_r + (cur_desc_w << 6) :
        state_r == S_PARAM ? (geometry_w ? command_r[287:256] : command_r[447:416]) :
        state_r == S_DRAW ? draw_rd_addr_w : state_r == S_COPY ? copy_rd_addr_w :
        state_r == S_BLIT ? blit_rd_addr_w : blur_rd_addr_w;
    assign rd_bytes_w = state_r == S_PARAM && geometry_w ? 16'd128 :
        state_r == S_FETCH || state_r == S_PARAM ? 16'd64 :
        state_r == S_DRAW ? draw_rd_bytes_w : state_r == S_COPY ? copy_rd_bytes_w :
        state_r == S_BLIT ? blit_rd_bytes_w : 16'd32;
    edrv32_dma2d_rd #(
        .OUTSTANDING(8)
    ) u_read (
        .clk_i(clk_mem_i),
        .rst_n_i(rst_mem_n_i),
        .desc_valid_i(rd_desc_valid_w),
        .desc_ready_o(rd_desc_ready_w),
        .desc_base_i(rd_addr_w),
        .desc_stride_i(32'd0),
        .desc_width_bytes_i(rd_bytes_w),
        .desc_height_i(12'd1),
        .data_valid_o(rd_data_valid_w),
        .data_ready_i(1'b1),
        .data_o(rd_data_w),
        .data_sol_o(unused_sol_w),
        .data_eol_o(unused_eol_w),
        .data_eof_o(unused_eof_w),
        .axi_arid_o(p4_arid_o),
        .axi_araddr_o(p4_araddr_o),
        .axi_arlen_o(p4_arlen_o),
        .axi_arvalid_o(p4_arvalid_o),
        .axi_arready_i(p4_arready_i),
        .axi_rid_i(p4_rid_i),
        .axi_rdata_i(p4_rdata_i),
        .axi_rresp_i(p4_rresp_i),
        .axi_rlast_i(p4_rlast_i),
        .axi_rvalid_i(p4_rvalid_i),
        .axi_rready_o(p4_rready_o),
        .abort_i(cancel_w),
        .idle_o(rd_idle_w),
        .done_o(rd_done_w),
        .err_o(unused_rd_error_w)
    );
    assign scalar_write_w = state_r == S_BLUR;
    assign wr_desc_valid_w = !cancel_w && ((state_r == S_DRAW && draw_wr_valid_w) ||
        (state_r == S_COPY && copy_wr_valid_w) || (state_r == S_FILL && fill_wr_valid_w) ||
        (state_r == S_BLUR && blur_wr_valid_w) ||
        (state_r == S_BLIT && blit_wr_valid_w));
    assign wr_addr_w = state_r == S_DRAW ? draw_wr_addr_w : state_r == S_COPY ?
        copy_wr_addr_w : state_r == S_FILL ? fill_wr_addr_w :
        state_r == S_BLIT ? blit_wr_addr_w : blur_wr_addr_w;
    assign wr_bytes_w = state_r == S_DRAW ? draw_wr_bytes_w : state_r == S_COPY ? copy_wr_bytes_w :
        state_r == S_FILL ? fill_wr_bytes_w : state_r == S_BLIT ? blit_wr_bytes_w : 16'd32;
    assign wr_data_valid_w = |{scalar_write_w && simple_valid_r,
        state_r == S_DRAW && draw_data_valid_w, state_r == S_COPY && copy_data_valid_w,
        state_r == S_BLIT && blit_data_valid_w, state_r == S_FILL && fill_data_valid_w};
    assign wr_data_w = scalar_write_w ? simple_data_r :
        state_r == S_DRAW ? draw_wr_data_w :
        state_r == S_COPY ? copy_data_w : state_r == S_BLIT ? blit_data_w : fill_data_w;
    assign wr_strb_w = scalar_write_w ? simple_strb_r :
        state_r == S_DRAW ? draw_wr_strb_w :
        state_r == S_COPY ? copy_strb_w : state_r == S_BLIT ? blit_strb_w : fill_strb_w;
    edrv32_dma2d_wr #(
        .OUTSTANDING(8)
    ) u_write (
        .clk_i(clk_mem_i),
        .rst_n_i(rst_mem_n_i),
        .desc_valid_i(wr_desc_valid_w),
        .desc_ready_o(wr_desc_ready_w),
        .desc_base_i(wr_addr_w),
        .desc_stride_i(32'd0),
        .desc_width_bytes_i(wr_bytes_w),
        .desc_height_i(12'd1),
        .data_valid_i(wr_data_valid_w),
        .data_ready_o(wr_data_ready_w),
        .data_i(wr_data_w),
        .data_strb_i(wr_strb_w),
        .axi_awid_o(p4_awid_o),
        .axi_awaddr_o(p4_awaddr_o),
        .axi_awlen_o(p4_awlen_o),
        .axi_awvalid_o(p4_awvalid_o),
        .axi_awready_i(p4_awready_i),
        .axi_wdata_o(p4_wdata_o),
        .axi_wstrb_o(p4_wstrb_o),
        .axi_wlast_o(p4_wlast_o),
        .axi_wvalid_o(p4_wvalid_o),
        .axi_wready_i(p4_wready_i),
        .axi_bid_i(p4_bid_i),
        .axi_bresp_i(p4_bresp_i),
        .axi_bvalid_i(p4_bvalid_i),
        .axi_bready_o(p4_bready_o),
        .abort_i(cancel_w),
        .idle_o(wr_idle_w),
        .done_o(wr_done_w),
        .err_o(unused_wr_error_w)
    );
    always @(posedge clk_mem_i or negedge rst_mem_n_i) begin
        if (!rst_mem_n_i) begin
            state_r <= S_IDLE;
            fetch_half_r <= 1'b0;
            parameter_beat_r <= 2'd0;
            simple_valid_r <= 1'b0;
        end else if (cancel_w) begin
            state_r <= busy_w ? S_DRAIN : S_IDLE;
            fetch_half_r <= 1'b0;
            parameter_beat_r <= 2'd0;
            simple_valid_r <= 1'b0;
        end else begin
            if (scalar_write_w && wr_desc_valid_w && wr_desc_ready_w)
                simple_valid_r <= 1'b1;
            else if (wr_data_valid_w && wr_data_ready_w)
                simple_valid_r <= 1'b0;
            case (state_r)
                S_IDLE: if (start_w && desc_count_w != 0)
                    state_r <= S_FETCH;
                S_FETCH: if (rd_desc_ready_w) begin
                    fetch_half_r <= 1'b0;
                    state_r <= S_FETCH_WAIT;
                end
                S_FETCH_WAIT: begin
                    if (rd_data_valid_w)
                        fetch_half_r <= 1'b1;
                    if (rd_done_w)
                        state_r <= S_CLIP;
                end
                S_CLIP: state_r <= S_CHECK;
                S_CHECK: begin
                    if (illegal_w)
                        state_r <= S_DRAIN;
                    else if (empty_w)
                        state_r <= S_COMPLETE;
                    else
                        state_r <= geometry_w || (op_w == 8'h04 && command_r[23]) ?
                            S_PARAM : S_BEGIN;
                end
                S_PARAM: if (rd_desc_ready_w) begin
                    parameter_beat_r <= 2'd0;
                    fetch_half_r <= 1'b0;
                    state_r <= S_PARAM_WAIT;
                end
                S_PARAM_WAIT: begin
                    if (rd_data_valid_w) begin
                        fetch_half_r <= 1'b1;
                        parameter_beat_r <= parameter_beat_r + 2'd1;
                    end
                    if (rd_done_w)
                        state_r <= S_BEGIN;
                end
                S_BEGIN: begin
                    if (fast_fill_w)
                        state_r <= S_FILL;
                    else if (blit_eligible_w)
                        state_r <= S_BLIT;
                    else if (op_w == 8'h05)
                        state_r <= S_COPY;
                    else if (op_w == 8'h06 || op_w == 8'h07)
                        state_r <= S_BLUR;
                    else
                        state_r <= S_DRAW;
                end
                S_BLIT: if (blit_done_w)
                    state_r <= S_COMPLETE;
                S_DRAW: if (draw_done_w)
                    state_r <= S_COMPLETE;
                S_COPY: if (copy_done_w)
                    state_r <= S_COMPLETE;
                S_FILL: if (fill_done_w)
                    state_r <= S_COMPLETE;
                S_BLUR: if (blur_done_w)
                    state_r <= op_w == 8'h06 ? S_SHADOW : S_COMPLETE;
                S_SHADOW: state_r <= S_DRAW;
                S_COMPLETE: state_r <= cur_desc_w + 32'd1 == {16'd0, list_count_r} ?
                    S_FINISH : S_FETCH;
                S_FINISH: state_r <= S_IDLE;
                S_DRAIN: if (rd_idle_w && wr_idle_w)
                    state_r <= S_IDLE;
                default: state_r <= state_r;
            endcase
        end
    end
    always @(posedge clk_mem_i) begin
        if (start_w) begin
            list_base_r <= desc_base_w;
            list_count_r <= desc_count_w;
        end
        if (state_r == S_FETCH_WAIT && rd_data_valid_w)
            command_r[fetch_half_r*256 +: 256] <= rd_data_w;
        if (state_r == S_PARAM_WAIT && rd_data_valid_w) begin
            if (geometry_w)
                parameters_r[parameter_beat_r*256 +: 256] <= rd_data_w;
            else if (!fetch_half_r) begin
                command_r[447:416] <= rd_data_w[31:0];
                round_area_r <= rd_data_w[95:32];
            end
        end
        if (state_r == S_PARAM_WAIT && rd_done_w && op_w == 8'h09) begin
            command_r[319:288] <= parameters_r[319:288];
            command_r[447:320] <= parameters_r[447:320];
        end
        // The final DMA beat is already in command_r when rd_done_w rises.
        if (state_r == S_FETCH_WAIT && rd_done_w) begin
            rect_left_r <= $signed({{2{command_r[175]}}, command_r[175:160]}) - expansion_w;
            rect_top_r <= $signed({{2{command_r[191]}}, command_r[191:176]}) - expansion_w;
            rect_right_r <= $signed({{2{command_r[207]}}, command_r[207:192]}) + expansion_w;
            rect_bottom_r <= $signed({{2{command_r[223]}}, command_r[223:208]}) + expansion_w;
            inverted_r <= $signed(command_r[207:192]) < $signed(command_r[175:160]) ||
                $signed(command_r[223:208]) < $signed(command_r[191:176]);
        end
        if (state_r == S_CLIP) begin
            clip_left_r <= rect_left_r > $signed({6'd0, command_r[107:96]}) ?
                rect_left_r : $signed({6'd0, command_r[107:96]});
            clip_top_r <= rect_top_r > $signed({6'd0, command_r[123:112]}) ?
                rect_top_r : $signed({6'd0, command_r[123:112]});
            clip_right_r <= rect_right_r < $signed({6'd0, command_r[139:128]}) ?
                rect_right_r : $signed({6'd0, command_r[139:128]});
            clip_bottom_r <= rect_bottom_r < $signed({6'd0, command_r[155:144]}) ?
                rect_bottom_r : $signed({6'd0, command_r[155:144]});
        end
        if (state_r == S_BEGIN)
            source_stride_r <= {16'd0, command_r[303:288]};
        if (state_r == S_BLUR && blur_done_w && op_w == 8'h06) begin
            command_r <= shadow_command_w;
            source_stride_r <= shadow_stride_w;
        end
        if (scalar_write_w && wr_desc_valid_w && wr_desc_ready_w) begin
            simple_data_r <= blur_wr_data_w;
            simple_strb_r <= blur_wr_strb_w;
        end
    end
endmodule
