// ============================================================================
// File        : edrv32_render_round_dma.v
// Description : Rounded rectangle read/modify/write on an ARGB8888 Surface.
// Notes       : One 4 KiB-safe, up-to-16-beat tile is owned until its write
//               response. The two-pixel blend pipe is supplied by the engine.
// ============================================================================

module edrv32_render_round_dma #(
    parameter [3:0] AXI_ID = 4'h7
) (
    input  wire         clk_i,
    input  wire         rst_n_i,

    input  wire         start_i,
    output wire         start_ready_o,
    input  wire [31:0]  row0_base_i,
    input  wire [31:0]  stride_i,
    input  wire [15:0]  x_i,
    input  wire [15:0]  width_i,
    input  wire [15:0]  height_i,
    input  wire [9:0]   radius_i,
    input  wire [9:0]   border_i,
    input  wire [31:0]  fill_color_i,
    input  wire [31:0]  border_color_i,
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

    localparam [3:0] ST_IDLE     = 4'd0;
    localparam [3:0] ST_ROW_REQ  = 4'd1;
    localparam [3:0] ST_ROW_WAIT = 4'd2;
    localparam [3:0] ST_AR       = 4'd3;
    localparam [3:0] ST_R        = 4'd4;
    localparam [3:0] ST_PAIR     = 4'd5;
    localparam [3:0] ST_AW       = 4'd7;
    localparam [3:0] ST_W        = 4'd8;
    localparam [3:0] ST_B        = 4'd9;

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

    function [31:0] finish_pixel;
        input [7:0] fill_a;
        input [7:0] border_visible;
        input [23:0] fill_rgb;
        input [31:0] border_color;
        reg [8:0] alpha_sum;
        reg [8:0] red_sum, green_sum, blue_sum;
        begin
            alpha_sum = {1'b0, fill_a} + {1'b0, border_visible};
            red_sum = {1'b0, fill_rgb[23:16]} +
                      {1'b0, mul255(border_color[23:16], border_visible)};
            green_sum = {1'b0, fill_rgb[15:8]} +
                        {1'b0, mul255(border_color[15:8], border_visible)};
            blue_sum = {1'b0, fill_rgb[7:0]} +
                       {1'b0, mul255(border_color[7:0], border_visible)};
            finish_pixel = {alpha_sum[8] ? 8'hff : alpha_sum[7:0],
                            red_sum[8] ? 8'hff : red_sum[7:0],
                            green_sum[8] ? 8'hff : green_sum[7:0],
                            blue_sum[8] ? 8'hff : blue_sum[7:0]};
        end
    endfunction

    reg [3:0]   state_r;
    reg         done_r;
    reg         error_r;
    reg [31:0]  row_addr_r;
    reg [31:0]  stride_r;
    reg [15:0]  x_r;
    reg [15:0]  width_r;
    reg [15:0]  height_r;
    reg [9:0]   radius_r;
    reg [9:0]   border_r;
    reg [31:0]  fill_color_r;
    reg [31:0]  border_color_r;
    reg [15:0]  row_r;
    reg [15:0]  beat_r;
    reg [15:0]  first_beat_r;
    reg [15:0]  last_beat_r;
    reg [15:0]  outer_edge_r;
    reg [15:0]  inner_edge_r;
    reg         inner_active_r;
    reg [255:0] read_cache_r [0:15];
    // Four banks permit a full 256-bit AXI read and one 64-bit pair write.
    // Whole-word writes let synthesis map the banks to distributed RAM.
    reg [63:0]  write_cache0_r [0:15];
    reg [63:0]  write_cache1_r [0:15];
    reg [63:0]  write_cache2_r [0:15];
    reg [63:0]  write_cache3_r [0:15];
    reg [4:0]   burst_len_r;
    reg [4:0]   read_index_r;
    reg [4:0]   write_index_r;
    reg [6:0]   issue_pair_r;
    reg [6:0]   return_pair_r;
    reg [31:0]  beat_count_r;

    reg         valid0_r, valid1_r, valid2_r, valid3_r;
    reg [15:0]  outer0_r, inner0_r;
    reg [63:0]  dst0_r, dst1_r, dst2_r, dst3_r;
    reg [6:0]   tag0_r, tag1_r, tag2_r, tag3_r;
    reg [15:0]  fill_a1_r, border_a1_r;
    reg [15:0]  fill_a2_r, border_visible2_r;
    reg [47:0]  fill_rgb2_r;
    reg [63:0]  src3_r;

    wire [16:0] rect_end_w = {1'b0, x_i} + {1'b0, width_i};
    wire [31:0] row_bytes_w = {13'd0, rect_end_w, 2'b00};
    wire [16:0] last_pixel_w = rect_end_w - 17'd1;
    wire [31:0] beat_addr_w = row_addr_r +
                              {11'd0, beat_r, 5'd0};
    wire [15:0] remaining_beats_w = last_beat_r - beat_r + 16'd1;
    wire [7:0] boundary_beats_w = 8'd128 -
                                  {1'b0, beat_addr_w[11:5]};
    wire [4:0] next_burst_w = remaining_beats_w < 16'd16 ?
                              (remaining_beats_w < {8'd0,boundary_beats_w} ?
                               remaining_beats_w[4:0] :
                               boundary_beats_w[4:0]) :
                              (boundary_beats_w < 8'd16 ?
                               boundary_beats_w[4:0] : 5'd16);
    wire [6:0] burst_pairs_w = {burst_len_r,2'b00};
    wire row_ready_w, edge_valid_w, edge_inner_active_w;
    wire [15:0] edge_outer_w, edge_inner_w;
    wire [15:0] pair_abs_x_w = {beat_r[12:0], 3'b0} +
                               {8'd0, issue_pair_r, 1'b0};
    wire [15:0] pair_rel_x_w = pair_abs_x_w - x_r;
    wire [15:0] outer_cov_w, inner_cov_w;
    wire pipe_stall_w = valid3_r && !blend_in_ready_i;
    wire pair_issue_w = (state_r == ST_PAIR) && !pipe_stall_w;
    wire result_fire_w = blend_out_valid_i && blend_out_ready_o;
    wire read_last_w = read_index_r == burst_len_r - 5'd1;
    wire write_last_w = write_index_r == burst_len_r - 5'd1;
    wire [6:0] write_pair_limit_w =
        {1'b0,write_index_r[3:0],2'b00} + 7'd4;
    wire start_fire_w = start_i && start_ready_o;
    wire read_fault_w = (m_rid_i != AXI_ID) ||
                        (m_rresp_i != 2'b00);
    wire write_fault_w = (m_bid_i != AXI_ID) ||
                         (m_bresp_i != 2'b00);

    edrv32_render_round_row u_row (
        .clk_i(clk_i), .rst_n_i(rst_n_i),
        .row_valid_i(state_r == ST_ROW_REQ),
        .row_ready_o(row_ready_w),
        .width_i(width_r), .height_i(height_r),
        .row_y_i(row_r), .radius_i(radius_r), .border_i(border_r),
        .edge_valid_o(edge_valid_w),
        .edge_ready_i(state_r == ST_ROW_WAIT),
        .outer_edge_q4_o(edge_outer_w),
        .inner_edge_q4_o(edge_inner_w),
        .inner_active_o(edge_inner_active_w)
    );
    edrv32_render_round_coverage u_coverage (
        .x_i(pair_rel_x_w), .width_i(width_r),
        .outer_edge_q4_i(outer_edge_r),
        .inner_edge_q4_i(inner_edge_r),
        .inner_active_i(inner_active_r),
        .outer_coverage_o(outer_cov_w),
        .inner_coverage_o(inner_cov_w)
    );

    assign start_ready_o = state_r == ST_IDLE;
    assign busy_o = state_r != ST_IDLE;
    assign done_o = done_r;
    assign error_o = error_r;
    assign beat_count_o = beat_count_r;

    assign blend_in_valid_o = valid3_r;
    assign blend_src_o = src3_r;
    assign blend_dst_o = dst3_r;
    assign blend_opacity_o = 16'hffff;
    assign blend_premul_o = 1'b1;
    assign blend_tag_o = {25'd0, tag3_r};
    assign blend_out_ready_o = (state_r == ST_PAIR) ||
                               (state_r == ST_AW) ||
                               (state_r == ST_W) ||
                               (state_r == ST_B);

    assign m_arid_o = AXI_ID;
    assign m_araddr_o = beat_addr_w;
    assign m_arlen_o = {3'd0, next_burst_w} - 8'd1;
    assign m_arsize_o = 3'd5;
    assign m_arburst_o = 2'b01;
    assign m_arqos_o = 4'd3;
    assign m_arvalid_o = state_r == ST_AR;
    assign m_rready_o = state_r == ST_R;

    assign m_awid_o = AXI_ID;
    assign m_awaddr_o = beat_addr_w;
    assign m_awlen_o = {3'd0, burst_len_r} - 8'd1;
    assign m_awsize_o = 3'd5;
    assign m_awburst_o = 2'b01;
    assign m_awqos_o = 4'd3;
    assign m_awvalid_o = state_r == ST_AW;
    assign m_wdata_o = {write_cache3_r[write_index_r[3:0]],
                        write_cache2_r[write_index_r[3:0]],
                        write_cache1_r[write_index_r[3:0]],
                        write_cache0_r[write_index_r[3:0]]};
    assign m_wstrb_o = 32'hffff_ffff;
    assign m_wlast_o = write_last_w;
    // AXI writes may follow the compute pipe, but a beat is visible only
    // after all four Alpha results for that beat have filled its RAM banks.
    assign m_wvalid_o = (state_r == ST_W) &&
                        (return_pair_r >= write_pair_limit_w);
    assign m_bready_o = state_r == ST_B;

    always @(posedge clk_i) begin
        if (result_fire_w) begin
            case (blend_out_tag_i[1:0])
                2'd0: write_cache0_r[blend_out_tag_i[5:2]] <= blend_pixel_i;
                2'd1: write_cache1_r[blend_out_tag_i[5:2]] <= blend_pixel_i;
                2'd2: write_cache2_r[blend_out_tag_i[5:2]] <= blend_pixel_i;
                default: write_cache3_r[blend_out_tag_i[5:2]] <= blend_pixel_i;
            endcase
        end
    end

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            state_r <= ST_IDLE;
            done_r <= 1'b0;
            error_r <= 1'b0;
            row_addr_r <= 32'b0;
            stride_r <= 32'b0;
            x_r <= 16'b0;
            width_r <= 16'b0;
            height_r <= 16'b0;
            radius_r <= 10'b0;
            border_r <= 10'b0;
            fill_color_r <= 32'b0;
            border_color_r <= 32'b0;
            row_r <= 16'b0;
            beat_r <= 16'b0;
            first_beat_r <= 16'b0;
            last_beat_r <= 16'b0;
            outer_edge_r <= 16'b0;
            inner_edge_r <= 16'b0;
            inner_active_r <= 1'b0;
            burst_len_r <= 5'b0;
            read_index_r <= 5'b0;
            write_index_r <= 5'b0;
            issue_pair_r <= 7'b0;
            return_pair_r <= 7'b0;
            beat_count_r <= 32'b0;
            valid0_r <= 1'b0;
            valid1_r <= 1'b0;
            valid2_r <= 1'b0;
            valid3_r <= 1'b0;
        end else begin
            done_r <= 1'b0;
            // The local pipeline advances one pair each clock. A blocked
            // shared Alpha input freezes the pair and every upstream stage.
            if (!pipe_stall_w) begin
                valid0_r <= state_r == ST_PAIR;
                valid1_r <= valid0_r;
                valid2_r <= valid1_r;
                valid3_r <= valid2_r;
                if (state_r == ST_PAIR) begin
                    outer0_r <= outer_cov_w;
                    inner0_r <= inner_cov_w;
                    dst0_r <= read_cache_r[issue_pair_r[5:2]]
                              [issue_pair_r[1:0]*64 +: 64];
                    tag0_r <= issue_pair_r;
                end
                if (valid0_r) begin
                    fill_a1_r[7:0] <= mul255(fill_color_r[31:24],
                                             inner0_r[7:0]);
                    fill_a1_r[15:8] <= mul255(fill_color_r[31:24],
                                              inner0_r[15:8]);
                    border_a1_r[7:0] <= mul255(border_color_r[31:24],
                         outer0_r[7:0] - inner0_r[7:0]);
                    border_a1_r[15:8] <= mul255(border_color_r[31:24],
                         outer0_r[15:8] - inner0_r[15:8]);
                    dst1_r <= dst0_r;
                    tag1_r <= tag0_r;
                end
                if (valid1_r) begin
                    fill_a2_r <= fill_a1_r;
                    border_visible2_r[7:0] <=
                        mul255(border_a1_r[7:0], 8'hff - fill_a1_r[7:0]);
                    border_visible2_r[15:8] <=
                        mul255(border_a1_r[15:8], 8'hff - fill_a1_r[15:8]);
                    fill_rgb2_r[7:0] <=
                        mul255(fill_color_r[7:0], fill_a1_r[7:0]);
                    fill_rgb2_r[15:8] <=
                        mul255(fill_color_r[15:8], fill_a1_r[7:0]);
                    fill_rgb2_r[23:16] <=
                        mul255(fill_color_r[23:16], fill_a1_r[7:0]);
                    fill_rgb2_r[31:24] <=
                        mul255(fill_color_r[7:0], fill_a1_r[15:8]);
                    fill_rgb2_r[39:32] <=
                        mul255(fill_color_r[15:8], fill_a1_r[15:8]);
                    fill_rgb2_r[47:40] <=
                        mul255(fill_color_r[23:16], fill_a1_r[15:8]);
                    dst2_r <= dst1_r;
                    tag2_r <= tag1_r;
                end
                if (valid2_r) begin
                    src3_r[31:0] <= finish_pixel(fill_a2_r[7:0],
                        border_visible2_r[7:0], fill_rgb2_r[23:0],
                        border_color_r);
                    src3_r[63:32] <= finish_pixel(fill_a2_r[15:8],
                        border_visible2_r[15:8], fill_rgb2_r[47:24],
                        border_color_r);
                    dst3_r <= dst2_r;
                    tag3_r <= tag2_r;
                end
            end
            if (start_fire_w) begin
                error_r <= (row0_base_i[4:0] != 5'd0) ||
                           (stride_i[4:0] != 5'd0) ||
                           (rect_end_w > 17'd65536) ||
                           (row_bytes_w > stride_i);
                beat_count_r <= 32'd0;
                if ((width_i == 16'd0) || (height_i == 16'd0)) begin
                    done_r <= 1'b1;
                end else if ((row0_base_i[4:0] != 5'd0) ||
                             (stride_i[4:0] != 5'd0) ||
                             (rect_end_w > 17'd65536) ||
                             (row_bytes_w > stride_i)) begin
                    done_r <= 1'b1;
                end else begin
                    row_addr_r <= row0_base_i;
                    stride_r <= stride_i;
                    x_r <= x_i;
                    width_r <= width_i;
                    height_r <= height_i;
                    radius_r <= radius_i;
                    border_r <= border_i;
                    fill_color_r <= fill_color_i;
                    border_color_r <= border_color_i;
                    row_r <= 16'd0;
                    beat_r <= x_i >> 3;
                    first_beat_r <= x_i >> 3;
                    last_beat_r <= {2'b00, last_pixel_w[16:3]};
                    state_r <= ST_ROW_REQ;
                end
            end else begin
                if (result_fire_w)
                    return_pair_r <= return_pair_r + 7'd1;
                case (state_r)
                    ST_ROW_REQ: begin
                        if (row_ready_w)
                            state_r <= ST_ROW_WAIT;
                    end
                    ST_ROW_WAIT: begin
                        if (edge_valid_w) begin
                            outer_edge_r <= edge_outer_w;
                            inner_edge_r <= edge_inner_w;
                            inner_active_r <= edge_inner_active_w;
                            state_r <= ST_AR;
                        end
                    end
                    ST_AR: begin
                        if (m_arready_i) begin
                            burst_len_r <= next_burst_w;
                            read_index_r <= 5'd0;
                            state_r <= ST_R;
                        end
                    end
                    ST_R: begin
                        if (m_rvalid_i) begin
                            if (read_fault_w ||
                                (m_rlast_i != read_last_w)) begin
                                error_r <= 1'b1;
                                done_r <= 1'b1;
                                state_r <= ST_IDLE;
                            end else begin
                                read_cache_r[read_index_r[3:0]] <= m_rdata_i;
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
                            end else if (beat_r + {11'd0,burst_len_r} -
                                         16'd1 == last_beat_r) begin
                                beat_count_r <= beat_count_r +
                                                {27'd0,burst_len_r};
                                if (row_r == height_r - 16'd1) begin
                                    done_r <= 1'b1;
                                    state_r <= ST_IDLE;
                                end else begin
                                    row_r <= row_r + 16'd1;
                                    row_addr_r <= row_addr_r + stride_r;
                                    beat_r <= first_beat_r;
                                    state_r <= ST_ROW_REQ;
                                end
                            end else begin
                                beat_count_r <= beat_count_r +
                                                {27'd0,burst_len_r};
                                beat_r <= beat_r + {11'd0,burst_len_r};
                                state_r <= ST_AR;
                            end
                        end
                    end
                    default: state_r <= ST_IDLE;
                endcase
            end
        end
    end

endmodule
