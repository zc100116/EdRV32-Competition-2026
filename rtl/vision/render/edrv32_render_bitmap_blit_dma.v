// ============================================================================
// File        : edrv32_render_bitmap_blit_dma.v
// Description : RGB565 / ARGB8888 bitmap source-over into ARGB8888 Surface.
// Notes       : Supports arbitrary source/destination pixel X and row width.
//               One or two source beats feed each destination beat; up to
//               eight blended destination beats share one write burst.
//               For vertical flip, source_row0_addr_i names the first row
//               visited (the bottom source row); subsequent rows step down.
// ============================================================================

module edrv32_render_bitmap_blit_dma #(
    parameter [3:0] AXI_ID = 4'h7
) (
    input  wire         clk_i,
    input  wire         rst_n_i,

    input  wire         start_i,
    output wire         start_ready_o,
    input  wire [31:0]  front_row0_addr_i,
    input  wire [31:0]  front_stride_i,
    input  wire [15:0]  x_i,
    input  wire [15:0]  width_i,
    input  wire [15:0]  height_i,
    input  wire [31:0]  source_row0_addr_i,
    input  wire [31:0]  source_stride_i,
    input  wire [15:0]  source_x_i,
    input  wire         source_argb_i,
    input  wire         source_premul_i,
    input  wire [7:0]   opacity_i,
    input  wire         flip_x_i,
    input  wire         flip_y_i,
    input  wire         color_key_enable_i,
    input  wire [31:0]  color_key_i,
    input  wire         scale_enable_i,
    input  wire [31:0]  scale_step_x_i,
    input  wire [31:0]  scale_step_y_i,
    output wire         busy_o,
    output wire         done_o,
    output wire         error_o,
    output wire [31:0]  beat_count_o,

    output wire         blend_in_valid_o,
    input  wire         blend_in_ready_i,
    output wire [63:0]  blend_src_o,
    output wire [63:0]  blend_dst_o,
    output wire [15:0]  blend_opacity_o,
    output wire         blend_premul_o,
    output wire [31:0]  blend_tag_o,
    input  wire         blend_out_valid_i,
    output wire         blend_out_ready_o,
    input  wire [63:0]  blend_pixel_i,
    input  wire [31:0]  blend_out_tag_i,

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
    output wire         m_bready_o
);

    localparam [3:0] ST_IDLE    = 4'd0;
    localparam [3:0] ST_SRC_AR0 = 4'd1;
    localparam [3:0] ST_SRC_R0  = 4'd2;
    localparam [3:0] ST_SRC_AR1 = 4'd3;
    localparam [3:0] ST_SRC_R1  = 4'd4;
    localparam [3:0] ST_DST_AR  = 4'd5;
    localparam [3:0] ST_DST_R   = 4'd6;
    localparam [3:0] ST_PAIR    = 4'd7;
    localparam [3:0] ST_AW      = 4'd9;
    localparam [3:0] ST_W       = 4'd10;
    localparam [3:0] ST_B       = 4'd11;
    localparam [3:0] ST_TILE    = 4'd12;
    localparam [3:0] ST_SCALE_PIXEL = 4'd13;
    localparam [3:0] ST_SCALE_ROW   = 4'd14;

    function [31:0] select_pixel;
        input [15:0] index;
        input        argb;
        input [15:0] first_word;
        input [255:0] word0;
        input [255:0] word1;
        reg [255:0] data;
        reg [15:0] rgb565;
        begin
            if (argb) begin
                data = (index >> 3) == first_word ? word0 : word1;
                select_pixel = data[index[2:0]*32 +: 32];
            end else begin
                data = (index >> 4) == first_word ? word0 : word1;
                rgb565 = data[index[3:0]*16 +: 16];
                select_pixel = {8'hff,
                                rgb565[15:11],rgb565[15:13],
                                rgb565[10:5],rgb565[10:9],
                                rgb565[4:0],rgb565[4:2]};
            end
        end
    endfunction

    reg [3:0]   state_r;
    reg         done_r;
    reg         error_r;
    reg [31:0]  front_row_addr_r;
    reg [31:0]  front_stride_r;
    reg [31:0]  source_row_addr_r;
    reg [31:0]  source_stride_r;
    reg [15:0]  x_r;
    reg [15:0]  source_x_r;
    reg [15:0]  width_r;
    reg [15:0]  height_r;
    reg [15:0]  row_r;
    reg [15:0]  beat_r;
    reg [15:0]  first_beat_r;
    reg [15:0]  last_beat_r;
    reg [15:0]  last_pixel_r;
    reg         source_argb_r;
    reg         source_premul_r;
    reg [7:0]   opacity_r;
    reg         flip_x_r;
    reg         flip_y_r;
    reg         color_key_enable_r;
    reg [31:0]  color_key_r;
    reg         scale_enable_r;
    reg [31:0]  scale_step_x_r;
    reg [31:0]  scale_step_y_r;
    reg [31:0]  scale_x_q16_r;
    reg [31:0]  scale_y_q16_r;
    reg signed [15:0] scale_row_index_r;
    reg signed [15:0] scale_row_target_r;
    reg [2:0]   scale_pixel_r;
    reg [31:0]  scaled_source_r [0:7];
    reg         scale_cache_valid_r;
    reg [31:0]  scale_cache_addr_r;
    reg [255:0] scale_cache_data_r;
    reg [255:0] source_word0_r;
    reg [255:0] source_word1_r;
    reg [255:0] read_word_r;
    reg [63:0]  write_cache0_r [0:7];
    reg [63:0]  write_cache1_r [0:7];
    reg [63:0]  write_cache2_r [0:7];
    reg [63:0]  write_cache3_r [0:7];
    reg [15:0]  tile_first_beat_r;
    reg [3:0]   tile_len_r;
    reg [3:0]   tile_processed_r;
    reg [3:0]   write_index_r;
    reg [2:0]   issue_pair_r;
    reg [5:0]   return_pair_r;
    reg [31:0]  beat_count_r;
    reg         valid0_r, valid1_r;
    reg [63:0]  src0_r, src1_r;
    reg [63:0]  dst0_r, dst1_r;
    reg [1:0]   pixel_valid0_r;
    reg [4:0]   tag0_r, tag1_r;

    wire [16:0] rect_end_w = {1'b0,x_i} + {1'b0,width_i};
    wire [16:0] source_end_w = {1'b0,source_x_i} +
                               {1'b0,width_i};
    wire [16:0] last_pixel_w = rect_end_w - 17'd1;
    wire [31:0] front_bytes_w = {13'd0,rect_end_w,2'b00};
    wire [31:0] source_bytes_w = source_argb_i ?
        {13'd0,source_end_w,2'b00} :
        {14'd0,source_end_w,1'b0};
    wire [31:0] beat_addr_w = front_row_addr_r +
                              {11'd0,beat_r,5'd0};
    wire [31:0] tile_addr_w = front_row_addr_r +
                              {11'd0,tile_first_beat_r,5'd0};
    wire [15:0] remaining_beats_w = last_beat_r - beat_r + 16'd1;
    wire [7:0] boundary_beats_w = 8'd128 -
                                  {1'b0,beat_addr_w[11:5]};
    wire [3:0] next_tile_len_w = remaining_beats_w < 16'd8 ?
        (remaining_beats_w < {8'd0,boundary_beats_w} ?
         remaining_beats_w[3:0] : boundary_beats_w[3:0]) :
        (boundary_beats_w < 8'd8 ? boundary_beats_w[3:0] : 4'd8);
    wire [15:0] beat_left_x_w = {beat_r[12:0],3'b0};
    wire [15:0] beat_right_x_w = beat_left_x_w + 16'd7;
    wire [15:0] first_valid_x_w = beat_left_x_w < x_r ?
                                  x_r : beat_left_x_w;
    wire [15:0] last_valid_x_w = beat_right_x_w > last_pixel_r ?
                                 last_pixel_r : beat_right_x_w;
    wire [15:0] first_source_index_w = flip_x_r ?
        source_x_r + width_r - 16'd1 - (first_valid_x_w - x_r) :
        source_x_r + first_valid_x_w - x_r;
    wire [15:0] last_source_index_w = flip_x_r ?
        source_x_r + width_r - 16'd1 - (last_valid_x_w - x_r) :
        source_x_r + last_valid_x_w - x_r;
    wire [15:0] first_source_word_w = source_argb_r ?
        first_source_index_w >> 3 : first_source_index_w >> 4;
    wire [15:0] last_source_word_w = source_argb_r ?
        last_source_index_w >> 3 : last_source_index_w >> 4;
    wire [31:0] source_addr0_w = source_row_addr_r +
        {11'd0,first_source_word_w,5'd0};
    wire [31:0] source_addr1_w = source_row_addr_r +
        {11'd0,last_source_word_w,5'd0};
    wire [15:0] scale_dest_x_w = beat_left_x_w +
        {13'd0,scale_pixel_r};
    wire scale_pixel_valid_w = (scale_dest_x_w >= x_r) &&
                               (scale_dest_x_w <= last_pixel_r);
    wire [15:0] scale_sample_x_w = scale_x_q16_r[31:16];
    wire [31:0] scale_sample_byte_w = source_argb_r ?
        {14'd0,scale_sample_x_w,2'b00} :
        {15'd0,scale_sample_x_w,1'b0};
    wire [31:0] scale_sample_addr_w = source_row_addr_r +
                                     scale_sample_byte_w;
    wire [31:0] scale_word_addr_w =
        {scale_sample_addr_w[31:5],5'd0};
    wire scale_cache_hit_w = scale_cache_valid_r &&
        (scale_cache_addr_r == scale_word_addr_w);
    wire scale_sample_in_stride_w =
        (scale_sample_byte_w + (source_argb_r ? 32'd4 : 32'd2)) <=
        source_stride_r;
    wire [15:0] scale_word_index_w = source_argb_r ?
        (scale_sample_x_w >> 3) : (scale_sample_x_w >> 4);
    wire [31:0] scale_selected_pixel_w = select_pixel(
        scale_sample_x_w,source_argb_r,scale_word_index_w,
        scale_cache_data_r,256'd0);
    wire [31:0] next_scale_y_q16_w = flip_y_r ?
        scale_y_q16_r - scale_step_y_r :
        scale_y_q16_r + scale_step_y_r;

    wire [15:0] pair_x0_w = beat_left_x_w +
                            {13'd0,issue_pair_r[1:0],1'b0};
    wire [15:0] pair_x1_w = pair_x0_w + 16'd1;
    wire pixel0_valid_w = (pair_x0_w >= x_r) &&
                          (pair_x0_w <= last_pixel_r);
    wire pixel1_valid_w = (pair_x1_w >= x_r) &&
                          (pair_x1_w <= last_pixel_r);
    wire [15:0] source_index0_w = flip_x_r ?
        source_x_r + width_r - 16'd1 - (pair_x0_w - x_r) :
        source_x_r + pair_x0_w - x_r;
    wire [15:0] source_index1_w = flip_x_r ?
        source_x_r + width_r - 16'd1 - (pair_x1_w - x_r) :
        source_x_r + pair_x1_w - x_r;
    wire [31:0] key_argb_w = source_argb_r ? color_key_r :
        {8'hff,color_key_r[15:11],color_key_r[15:13],
         color_key_r[10:5],color_key_r[10:9],
         color_key_r[4:0],color_key_r[4:2]};
    wire [31:0] source_pixel0_w = scale_enable_r ?
        scaled_source_r[{issue_pair_r[1:0],1'b0}] :
        (pixel0_valid_w ?
         select_pixel(source_index0_w,source_argb_r,
                      first_source_word_w,source_word0_r,
                      source_word1_r) : 32'd0);
    wire [31:0] source_pixel1_w = scale_enable_r ?
        scaled_source_r[{issue_pair_r[1:0],1'b1}] :
        (pixel1_valid_w ?
         select_pixel(source_index1_w,source_argb_r,
                      first_source_word_w,source_word0_r,
                      source_word1_r) : 32'd0);
    wire pipe_stall_w = valid1_r && !blend_in_ready_i;
    wire pair_issue_w = (state_r == ST_PAIR) && !pipe_stall_w;
    wire result_fire_w = blend_out_valid_i && blend_out_ready_o;
    wire [5:0] write_pair_limit_w =
        {1'b0,write_index_r[2:0],2'b00} + 6'd4;
    wire start_fire_w = start_i && start_ready_o;
    wire read_fault_w = (m_rid_i != AXI_ID) ||
                        (m_rresp_i != 2'b00) || !m_rlast_i;
    wire write_fault_w = (m_bid_i != AXI_ID) ||
                         (m_bresp_i != 2'b00);

    assign start_ready_o = state_r == ST_IDLE;
    assign busy_o = state_r != ST_IDLE;
    assign done_o = done_r;
    assign error_o = error_r;
    assign beat_count_o = beat_count_r;

    assign blend_in_valid_o = valid1_r;
    assign blend_src_o = src1_r;
    assign blend_dst_o = dst1_r;
    assign blend_opacity_o = {opacity_r,opacity_r};
    assign blend_premul_o = !source_argb_r || source_premul_r;
    assign blend_tag_o = {27'd0,tag1_r};
    assign blend_out_ready_o = state_r != ST_IDLE;

    assign m_arid_o = AXI_ID;
    assign m_araddr_o = state_r == ST_SRC_AR0 ?
                        (scale_enable_r ? scale_word_addr_w :
                         source_addr0_w) :
                        state_r == ST_SRC_AR1 ? source_addr1_w :
                        beat_addr_w;
    assign m_arlen_o = 8'd0;
    assign m_arsize_o = 3'd5;
    assign m_arburst_o = 2'b01;
    assign m_arqos_o = 4'd3;
    assign m_arvalid_o = (state_r == ST_SRC_AR0) ||
                         (state_r == ST_SRC_AR1) ||
                         (state_r == ST_DST_AR);
    assign m_rready_o = (state_r == ST_SRC_R0) ||
                        (state_r == ST_SRC_R1) ||
                        (state_r == ST_DST_R);

    assign m_awid_o = AXI_ID;
    assign m_awaddr_o = tile_addr_w;
    assign m_awlen_o = {4'd0,tile_len_r} - 8'd1;
    assign m_awsize_o = 3'd5;
    assign m_awburst_o = 2'b01;
    assign m_awqos_o = 4'd3;
    assign m_awvalid_o = state_r == ST_AW;
    assign m_wdata_o = {write_cache3_r[write_index_r[2:0]],
                        write_cache2_r[write_index_r[2:0]],
                        write_cache1_r[write_index_r[2:0]],
                        write_cache0_r[write_index_r[2:0]]};
    assign m_wstrb_o = 32'hffff_ffff;
    assign m_wlast_o = write_index_r == tile_len_r - 4'd1;
    assign m_wvalid_o = (state_r == ST_W) &&
                        (return_pair_r >= write_pair_limit_w);
    assign m_bready_o = state_r == ST_B;

    always @(posedge clk_i) begin
        if (result_fire_w) begin
            case (blend_out_tag_i[1:0])
                2'd0: write_cache0_r[blend_out_tag_i[4:2]] <= blend_pixel_i;
                2'd1: write_cache1_r[blend_out_tag_i[4:2]] <= blend_pixel_i;
                2'd2: write_cache2_r[blend_out_tag_i[4:2]] <= blend_pixel_i;
                default: write_cache3_r[blend_out_tag_i[4:2]] <= blend_pixel_i;
            endcase
        end
    end

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            state_r <= ST_IDLE;
            done_r <= 1'b0;
            error_r <= 1'b0;
            front_row_addr_r <= 32'd0;
            front_stride_r <= 32'd0;
            source_row_addr_r <= 32'd0;
            source_stride_r <= 32'd0;
            x_r <= 16'd0;
            source_x_r <= 16'd0;
            width_r <= 16'd0;
            height_r <= 16'd0;
            row_r <= 16'd0;
            beat_r <= 16'd0;
            first_beat_r <= 16'd0;
            last_beat_r <= 16'd0;
            last_pixel_r <= 16'd0;
            source_argb_r <= 1'b0;
            source_premul_r <= 1'b0;
            opacity_r <= 8'd0;
            flip_x_r <= 1'b0;
            flip_y_r <= 1'b0;
            color_key_enable_r <= 1'b0;
            color_key_r <= 32'd0;
            scale_enable_r <= 1'b0;
            scale_step_x_r <= 32'd0;
            scale_step_y_r <= 32'd0;
            scale_x_q16_r <= 32'd0;
            scale_y_q16_r <= 32'd0;
            scale_row_index_r <= 16'sd0;
            scale_row_target_r <= 16'sd0;
            scale_pixel_r <= 3'd0;
            scale_cache_valid_r <= 1'b0;
            scale_cache_addr_r <= 32'd0;
            issue_pair_r <= 3'd0;
            return_pair_r <= 6'd0;
            tile_first_beat_r <= 16'd0;
            tile_len_r <= 4'd0;
            tile_processed_r <= 4'd0;
            write_index_r <= 4'd0;
            beat_count_r <= 32'd0;
            valid0_r <= 1'b0;
            valid1_r <= 1'b0;
        end else begin
            done_r <= 1'b0;
            if (!pipe_stall_w) begin
                valid0_r <= state_r == ST_PAIR;
                valid1_r <= valid0_r;
                if (state_r == ST_PAIR) begin
                    src0_r <= {source_pixel1_w,source_pixel0_w};
                    pixel_valid0_r <= {pixel1_valid_w,pixel0_valid_w};
                    dst0_r <= read_word_r[issue_pair_r[1:0]*64 +: 64];
                    tag0_r <= {tile_processed_r[2:0],issue_pair_r[1:0]};
                end
                if (valid0_r) begin
                    src1_r[31:0] <=
                        color_key_enable_r && pixel_valid0_r[0] &&
                        (src0_r[31:0] == key_argb_w) ?
                        32'd0 : src0_r[31:0];
                    src1_r[63:32] <=
                        color_key_enable_r && pixel_valid0_r[1] &&
                        (src0_r[63:32] == key_argb_w) ?
                        32'd0 : src0_r[63:32];
                    dst1_r <= dst0_r;
                    tag1_r <= tag0_r;
                end
            end
            if (start_fire_w) begin
                error_r <= (front_row0_addr_i[4:0] != 5'd0) ||
                           (front_stride_i[4:0] != 5'd0) ||
                           (source_row0_addr_i[4:0] != 5'd0) ||
                           (source_stride_i[4:0] != 5'd0) ||
                           (rect_end_w > 17'd65536) ||
                           (!scale_enable_i &&
                            (source_end_w > 17'd65536)) ||
                           (front_bytes_w > front_stride_i) ||
                           (!scale_enable_i &&
                            (source_bytes_w > source_stride_i));
                beat_count_r <= 32'd0;
                if ((width_i == 16'd0) || (height_i == 16'd0)) begin
                    done_r <= 1'b1;
                end else if ((front_row0_addr_i[4:0] != 5'd0) ||
                             (front_stride_i[4:0] != 5'd0) ||
                             (source_row0_addr_i[4:0] != 5'd0) ||
                             (source_stride_i[4:0] != 5'd0) ||
                             (rect_end_w > 17'd65536) ||
                             (!scale_enable_i &&
                              (source_end_w > 17'd65536)) ||
                             (front_bytes_w > front_stride_i) ||
                             (!scale_enable_i &&
                              (source_bytes_w > source_stride_i))) begin
                    done_r <= 1'b1;
                end else begin
                    front_row_addr_r <= front_row0_addr_i;
                    front_stride_r <= front_stride_i;
                    source_row_addr_r <= source_row0_addr_i;
                    source_stride_r <= source_stride_i;
                    x_r <= x_i;
                    source_x_r <= source_x_i;
                    width_r <= width_i;
                    height_r <= height_i;
                    source_argb_r <= source_argb_i;
                    source_premul_r <= source_premul_i;
                    opacity_r <= opacity_i;
                    flip_x_r <= flip_x_i;
                    flip_y_r <= flip_y_i;
                    color_key_enable_r <= color_key_enable_i;
                    color_key_r <= color_key_i;
                    scale_enable_r <= scale_enable_i;
                    scale_step_x_r <= scale_step_x_i;
                    scale_step_y_r <= scale_step_y_i;
                    scale_x_q16_r <= {source_x_i,
                        flip_x_i ? 16'hffff : 16'd0};
                    scale_y_q16_r <= flip_y_i ?
                        32'h0000_ffff : 32'd0;
                    scale_row_index_r <= 16'sd0;
                    scale_row_target_r <= 16'sd0;
                    scale_cache_valid_r <= 1'b0;
                    row_r <= 16'd0;
                    beat_r <= x_i >> 3;
                    first_beat_r <= x_i >> 3;
                    last_beat_r <= {2'b00,last_pixel_w[16:3]};
                    last_pixel_r <= last_pixel_w[15:0];
                    state_r <= ST_TILE;
                end
            end else begin
                if (result_fire_w)
                    return_pair_r <= return_pair_r + 6'd1;
                case (state_r)
                    ST_TILE: begin
                        tile_first_beat_r <= beat_r;
                        tile_len_r <= next_tile_len_w;
                        tile_processed_r <= 4'd0;
                        scale_pixel_r <= 3'd0;
                        return_pair_r <= 6'd0;
                        state_r <= scale_enable_r ?
                                   ST_SCALE_PIXEL : ST_SRC_AR0;
                    end
                    ST_SCALE_PIXEL: begin
                        if (scale_pixel_valid_w &&
                            !scale_sample_in_stride_w) begin
                            error_r <= 1'b1;
                            done_r <= 1'b1;
                            state_r <= ST_IDLE;
                        end else if (!scale_pixel_valid_w ||
                                     scale_cache_hit_w) begin
                            scaled_source_r[scale_pixel_r] <=
                                scale_pixel_valid_w ?
                                scale_selected_pixel_w : 32'd0;
                            if (scale_pixel_valid_w)
                                scale_x_q16_r <= flip_x_r ?
                                    scale_x_q16_r - scale_step_x_r :
                                    scale_x_q16_r + scale_step_x_r;
                            if (scale_pixel_r == 3'd7)
                                state_r <= ST_DST_AR;
                            else
                                scale_pixel_r <= scale_pixel_r + 3'd1;
                        end else begin
                            state_r <= ST_SRC_AR0;
                        end
                    end
                    ST_SCALE_ROW: begin
                        if (scale_row_index_r == scale_row_target_r)
                            state_r <= ST_TILE;
                        else if (scale_row_index_r <
                                 scale_row_target_r) begin
                            source_row_addr_r <= source_row_addr_r +
                                                 source_stride_r;
                            scale_row_index_r <= scale_row_index_r +
                                                 16'sd1;
                        end else begin
                            source_row_addr_r <= source_row_addr_r -
                                                 source_stride_r;
                            scale_row_index_r <= scale_row_index_r -
                                                 16'sd1;
                        end
                    end
                    ST_SRC_AR0: begin
                        if (m_arready_i)
                            state_r <= ST_SRC_R0;
                    end
                    ST_SRC_R0: begin
                        if (m_rvalid_i) begin
                            if (read_fault_w) begin
                                error_r <= 1'b1;
                                done_r <= 1'b1;
                                state_r <= ST_IDLE;
                            end else begin
                                if (scale_enable_r) begin
                                    scale_cache_valid_r <= 1'b1;
                                    scale_cache_addr_r <=
                                        scale_word_addr_w;
                                    scale_cache_data_r <= m_rdata_i;
                                    state_r <= ST_SCALE_PIXEL;
                                end else begin
                                    source_word0_r <= m_rdata_i;
                                    state_r <= first_source_word_w ==
                                               last_source_word_w ?
                                               ST_DST_AR : ST_SRC_AR1;
                                end
                            end
                        end
                    end
                    ST_SRC_AR1: begin
                        if (m_arready_i)
                            state_r <= ST_SRC_R1;
                    end
                    ST_SRC_R1: begin
                        if (m_rvalid_i) begin
                            if (read_fault_w) begin
                                error_r <= 1'b1;
                                done_r <= 1'b1;
                                state_r <= ST_IDLE;
                            end else begin
                                source_word1_r <= m_rdata_i;
                                state_r <= ST_DST_AR;
                            end
                        end
                    end
                    ST_DST_AR: begin
                        if (m_arready_i)
                            state_r <= ST_DST_R;
                    end
                    ST_DST_R: begin
                        if (m_rvalid_i) begin
                            if (read_fault_w) begin
                                error_r <= 1'b1;
                                done_r <= 1'b1;
                                state_r <= ST_IDLE;
                            end else begin
                                read_word_r <= m_rdata_i;
                                issue_pair_r <= 3'd0;
                                state_r <= ST_PAIR;
                            end
                        end
                    end
                    ST_PAIR: begin
                        if (pair_issue_w) begin
                            issue_pair_r <= issue_pair_r + 3'd1;
                            if (issue_pair_r == 3'd3) begin
                                if (tile_processed_r == tile_len_r - 4'd1)
                                    state_r <= ST_AW;
                                else begin
                                    tile_processed_r <=
                                        tile_processed_r + 4'd1;
                                    beat_r <= beat_r + 16'd1;
                                    scale_pixel_r <= 3'd0;
                                    state_r <= scale_enable_r ?
                                               ST_SCALE_PIXEL : ST_SRC_AR0;
                                end
                            end
                        end
                    end
                    ST_AW: begin
                        if (m_awready_i) begin
                            write_index_r <= 4'd0;
                            state_r <= ST_W;
                        end
                    end
                    ST_W: begin
                        if (m_wvalid_o && m_wready_i) begin
                            if (m_wlast_o)
                                state_r <= ST_B;
                            else
                                write_index_r <= write_index_r + 4'd1;
                        end
                    end
                    ST_B: begin
                        if (m_bvalid_i) begin
                            if (write_fault_w) begin
                                error_r <= 1'b1;
                                done_r <= 1'b1;
                                state_r <= ST_IDLE;
                            end else begin
                                beat_count_r <= beat_count_r +
                                                {28'd0,tile_len_r};
                                if (beat_r == last_beat_r) begin
                                    if (row_r == height_r - 16'd1) begin
                                        done_r <= 1'b1;
                                        state_r <= ST_IDLE;
                                    end else begin
                                        row_r <= row_r + 16'd1;
                                        front_row_addr_r <= front_row_addr_r +
                                                            front_stride_r;
                                        if (scale_enable_r) begin
                                            scale_y_q16_r <=
                                                next_scale_y_q16_w;
                                            scale_row_target_r <=
                                                next_scale_y_q16_w[31:16];
                                            scale_x_q16_r <= {source_x_r,
                                                flip_x_r ?
                                                16'hffff : 16'd0};
                                        end else begin
                                            source_row_addr_r <= flip_y_r ?
                                                source_row_addr_r -
                                                source_stride_r :
                                                source_row_addr_r +
                                                source_stride_r;
                                        end
                                        beat_r <= first_beat_r;
                                        state_r <= scale_enable_r ?
                                                   ST_SCALE_ROW : ST_TILE;
                                    end
                                end else begin
                                    beat_r <= beat_r + 16'd1;
                                    state_r <= ST_TILE;
                                end
                            end
                        end
                    end
                    default: state_r <= ST_IDLE;
                endcase
            end
        end
    end

endmodule
