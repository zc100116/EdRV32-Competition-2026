// ============================================================================
// File        : edrv32_render_a8_blit_dma.v
// Description : Color an A8 mask into an ARGB8888 foreground Surface.
// Notes       : Each mask row occupies one aligned 256-bit beat (1..32 pixels).
//               Up to five destination beats are blended per glyph row tile.
// ============================================================================

module edrv32_render_a8_blit_dma #(
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
    input  wire [31:0]  mask_row0_addr_i,
    input  wire [31:0]  mask_stride_i,
    input  wire [31:0]  color_i,
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
    localparam [3:0] ST_MASK_AR = 4'd1;
    localparam [3:0] ST_MASK_R  = 4'd2;
    localparam [3:0] ST_DST_AR  = 4'd3;
    localparam [3:0] ST_DST_R   = 4'd4;
    localparam [3:0] ST_PAIR    = 4'd5;
    localparam [3:0] ST_AW      = 4'd7;
    localparam [3:0] ST_W       = 4'd8;
    localparam [3:0] ST_B       = 4'd9;

    function [7:0] mul255;
        input [7:0] a;
        input [7:0] b;
        reg [15:0] product;
        reg [16:0] rounded;
        begin
            product = a * b;
            rounded = {1'b0, product} + 17'd128;
            rounded = rounded + (rounded >> 8);
            mul255 = rounded[15:8];
        end
    endfunction

    function [31:0] premul_alpha;
        input [31:0] color;
        input [7:0] alpha;
        begin
            premul_alpha = {alpha,
                            mul255(color[23:16], alpha),
                            mul255(color[15:8], alpha),
                            mul255(color[7:0], alpha)};
        end
    endfunction

    reg [3:0]   state_r;
    reg         done_r;
    reg         error_r;
    reg [31:0]  front_row_addr_r;
    reg [31:0]  front_stride_r;
    reg [31:0]  mask_row_addr_r;
    reg [31:0]  mask_stride_r;
    reg [31:0]  color_r;
    reg [15:0]  x_r;
    reg [15:0]  width_r;
    reg [15:0]  height_r;
    reg [15:0]  row_r;
    reg [15:0]  beat_r;
    reg [15:0]  first_beat_r;
    reg [15:0]  last_beat_r;
    reg [255:0] mask_word_r;
    reg [255:0] read_cache_r [0:4];
    reg [63:0]  write_cache0_r [0:4];
    reg [63:0]  write_cache1_r [0:4];
    reg [63:0]  write_cache2_r [0:4];
    reg [63:0]  write_cache3_r [0:4];
    reg [4:0]   burst_len_r;
    reg [4:0]   read_index_r;
    reg [4:0]   write_index_r;
    reg [6:0]   issue_pair_r;
    reg [6:0]   return_pair_r;
    reg [31:0]  beat_count_r;
    reg         valid0_r, valid1_r, valid2_r;
    reg [15:0]  mask0_r, alpha1_r;
    reg [63:0]  dst0_r, dst1_r, dst2_r;
    reg [6:0]   tag0_r, tag1_r, tag2_r;
    reg [63:0]  src2_r;

    wire [16:0] rect_end_w = {1'b0, x_i} + {1'b0, width_i};
    wire [16:0] last_pixel_w = rect_end_w - 17'd1;
    wire [31:0] row_bytes_w = {13'd0, rect_end_w, 2'b00};
    wire [31:0] beat_addr_w = front_row_addr_r +
                              {11'd0, beat_r, 5'd0};
    wire [15:0] remaining_beats_w = last_beat_r - beat_r + 16'd1;
    wire [7:0] boundary_beats_w = 8'd128 -
                                  {1'b0,beat_addr_w[11:5]};
    wire [4:0] next_burst_w = remaining_beats_w < 16'd16 ?
        (remaining_beats_w < {8'd0,boundary_beats_w} ?
         remaining_beats_w[4:0] : boundary_beats_w[4:0]) :
        (boundary_beats_w < 8'd16 ? boundary_beats_w[4:0] : 5'd16);
    wire [6:0] burst_pairs_w = {burst_len_r,2'b00};
    wire [15:0] pair_abs_x_w = {beat_r[12:0],3'b0} +
                               {8'd0,issue_pair_r,1'b0};
    wire [15:0] pixel1_x_w = pair_abs_x_w + 16'd1;
    wire [15:0] rel0_w = pair_abs_x_w - x_r;
    wire [15:0] rel1_w = pixel1_x_w - x_r;
    wire [7:0] mask0_w = (pair_abs_x_w >= x_r) &&
                         (rel0_w < width_r) ?
                         mask_word_r[rel0_w[4:0]*8 +: 8] : 8'd0;
    wire [7:0] mask1_w = (pixel1_x_w >= x_r) &&
                         (rel1_w < width_r) ?
                         mask_word_r[rel1_w[4:0]*8 +: 8] : 8'd0;
    wire pipe_stall_w = valid2_r && !blend_in_ready_i;
    wire pair_issue_w = (state_r == ST_PAIR) && !pipe_stall_w;
    wire result_fire_w = blend_out_valid_i && blend_out_ready_o;
    wire read_last_w = read_index_r == burst_len_r - 5'd1;
    wire write_last_w = write_index_r == burst_len_r - 5'd1;
    wire [6:0] write_pair_limit_w =
        {1'b0,write_index_r[2:0],2'b00} + 7'd4;
    wire start_fire_w = start_i && start_ready_o;
    wire read_fault_w = (m_rid_i != AXI_ID) ||
                        (m_rresp_i != 2'b00);
    wire write_fault_w = (m_bid_i != AXI_ID) ||
                         (m_bresp_i != 2'b00);

    assign start_ready_o = state_r == ST_IDLE;
    assign busy_o = state_r != ST_IDLE;
    assign done_o = done_r;
    assign error_o = error_r;
    assign beat_count_o = beat_count_r;

    assign blend_in_valid_o = valid2_r;
    assign blend_src_o = src2_r;
    assign blend_dst_o = dst2_r;
    assign blend_opacity_o = 16'hffff;
    assign blend_premul_o = 1'b1;
    assign blend_tag_o = {25'd0,tag2_r};
    assign blend_out_ready_o = (state_r == ST_PAIR) ||
                               (state_r == ST_AW) ||
                               (state_r == ST_W) ||
                               (state_r == ST_B);

    assign m_arid_o = AXI_ID;
    assign m_araddr_o = (state_r == ST_MASK_AR) ?
                        mask_row_addr_r : beat_addr_w;
    assign m_arlen_o = (state_r == ST_MASK_AR) ? 8'd0 :
                       ({3'd0,next_burst_w} - 8'd1);
    assign m_arsize_o = 3'd5;
    assign m_arburst_o = 2'b01;
    assign m_arqos_o = 4'd3;
    assign m_arvalid_o = (state_r == ST_MASK_AR) ||
                         (state_r == ST_DST_AR);
    assign m_rready_o = (state_r == ST_MASK_R) ||
                        (state_r == ST_DST_R);

    assign m_awid_o = AXI_ID;
    assign m_awaddr_o = beat_addr_w;
    assign m_awlen_o = {3'd0,burst_len_r} - 8'd1;
    assign m_awsize_o = 3'd5;
    assign m_awburst_o = 2'b01;
    assign m_awqos_o = 4'd3;
    assign m_awvalid_o = state_r == ST_AW;
    assign m_wdata_o = {write_cache3_r[write_index_r[2:0]],
                        write_cache2_r[write_index_r[2:0]],
                        write_cache1_r[write_index_r[2:0]],
                        write_cache0_r[write_index_r[2:0]]};
    assign m_wstrb_o = 32'hffff_ffff;
    assign m_wlast_o = write_last_w;
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
            mask_row_addr_r <= 32'd0;
            mask_stride_r <= 32'd0;
            color_r <= 32'd0;
            x_r <= 16'd0;
            width_r <= 16'd0;
            height_r <= 16'd0;
            row_r <= 16'd0;
            beat_r <= 16'd0;
            first_beat_r <= 16'd0;
            last_beat_r <= 16'd0;
            burst_len_r <= 5'd0;
            read_index_r <= 5'd0;
            write_index_r <= 5'd0;
            issue_pair_r <= 7'd0;
            return_pair_r <= 7'd0;
            beat_count_r <= 32'd0;
            valid0_r <= 1'b0;
            valid1_r <= 1'b0;
            valid2_r <= 1'b0;
        end else begin
            done_r <= 1'b0;
            if (!pipe_stall_w) begin
                valid0_r <= state_r == ST_PAIR;
                valid1_r <= valid0_r;
                valid2_r <= valid1_r;
                if (state_r == ST_PAIR) begin
                    mask0_r <= {mask1_w,mask0_w};
                    dst0_r <= read_cache_r[issue_pair_r[4:2]]
                              [issue_pair_r[1:0]*64 +: 64];
                    tag0_r <= issue_pair_r;
                end
                if (valid0_r) begin
                    alpha1_r[7:0] <=
                        mul255(color_r[31:24],mask0_r[7:0]);
                    alpha1_r[15:8] <=
                        mul255(color_r[31:24],mask0_r[15:8]);
                    dst1_r <= dst0_r;
                    tag1_r <= tag0_r;
                end
                if (valid1_r) begin
                    src2_r[31:0] <= premul_alpha(color_r,alpha1_r[7:0]);
                    src2_r[63:32] <= premul_alpha(color_r,alpha1_r[15:8]);
                    dst2_r <= dst1_r;
                    tag2_r <= tag1_r;
                end
            end
            if (start_fire_w) begin
                error_r <= (front_row0_addr_i[4:0] != 5'd0) ||
                           (front_stride_i[4:0] != 5'd0) ||
                           (mask_row0_addr_i[4:0] != 5'd0) ||
                           (mask_stride_i[4:0] != 5'd0) ||
                           (width_i > 16'd32) ||
                           (rect_end_w > 17'd65536) ||
                           (row_bytes_w > front_stride_i);
                beat_count_r <= 32'd0;
                if ((width_i == 16'd0) || (height_i == 16'd0) ||
                    (front_row0_addr_i[4:0] != 5'd0) ||
                    (front_stride_i[4:0] != 5'd0) ||
                    (mask_row0_addr_i[4:0] != 5'd0) ||
                    (mask_stride_i[4:0] != 5'd0) ||
                    (width_i > 16'd32) ||
                    (rect_end_w > 17'd65536) ||
                    (row_bytes_w > front_stride_i)) begin
                    done_r <= 1'b1;
                end else begin
                    front_row_addr_r <= front_row0_addr_i;
                    front_stride_r <= front_stride_i;
                    mask_row_addr_r <= mask_row0_addr_i;
                    mask_stride_r <= mask_stride_i;
                    color_r <= color_i;
                    x_r <= x_i;
                    width_r <= width_i;
                    height_r <= height_i;
                    row_r <= 16'd0;
                    beat_r <= x_i >> 3;
                    first_beat_r <= x_i >> 3;
                    last_beat_r <= {2'b00,last_pixel_w[16:3]};
                    state_r <= ST_MASK_AR;
                end
            end else begin
                if (result_fire_w)
                    return_pair_r <= return_pair_r + 7'd1;
                case (state_r)
                    ST_MASK_AR: begin
                        if (m_arready_i)
                            state_r <= ST_MASK_R;
                    end
                    ST_MASK_R: begin
                        if (m_rvalid_i) begin
                            if (read_fault_w || !m_rlast_i) begin
                                error_r <= 1'b1;
                                done_r <= 1'b1;
                                state_r <= ST_IDLE;
                            end else begin
                                mask_word_r <= m_rdata_i;
                                state_r <= ST_DST_AR;
                            end
                        end
                    end
                    ST_DST_AR: begin
                        if (m_arready_i) begin
                            burst_len_r <= next_burst_w;
                            read_index_r <= 5'd0;
                            state_r <= ST_DST_R;
                        end
                    end
                    ST_DST_R: begin
                        if (m_rvalid_i) begin
                            if (read_fault_w ||
                                (m_rlast_i != read_last_w)) begin
                                error_r <= 1'b1;
                                done_r <= 1'b1;
                                state_r <= ST_IDLE;
                            end else begin
                                read_cache_r[read_index_r[2:0]] <= m_rdata_i;
                                if (read_last_w) begin
                                    issue_pair_r <= 7'd0;
                                    return_pair_r <= 7'd0;
                                    state_r <= ST_PAIR;
                                end else begin
                                    read_index_r <= read_index_r + 5'd1;
                                end
                            end
                        end
                    end
                    ST_PAIR: begin
                        if (pair_issue_w) begin
                            issue_pair_r <= issue_pair_r + 7'd1;
                            if (issue_pair_r == burst_pairs_w - 7'd1)
                                state_r <= ST_AW;
                        end
                    end
                    ST_AW: begin
                        if (m_awready_i) begin
                            write_index_r <= 5'd0;
                            state_r <= ST_W;
                        end
                    end
                    ST_W: begin
                        if (m_wvalid_o && m_wready_i) begin
                            if (write_last_w)
                                state_r <= ST_B;
                            else
                                write_index_r <= write_index_r + 5'd1;
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
                                                {27'd0,burst_len_r};
                                if (beat_r + {11'd0,burst_len_r} -
                                    16'd1 == last_beat_r) begin
                                    if (row_r == height_r - 16'd1) begin
                                        done_r <= 1'b1;
                                        state_r <= ST_IDLE;
                                    end else begin
                                        row_r <= row_r + 16'd1;
                                        front_row_addr_r <= front_row_addr_r +
                                                            front_stride_r;
                                        mask_row_addr_r <= mask_row_addr_r +
                                                           mask_stride_r;
                                        beat_r <= first_beat_r;
                                        state_r <= ST_MASK_AR;
                                    end
                                end else begin
                                    beat_r <= beat_r +
                                              {11'd0,burst_len_r};
                                    state_r <= ST_DST_AR;
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
