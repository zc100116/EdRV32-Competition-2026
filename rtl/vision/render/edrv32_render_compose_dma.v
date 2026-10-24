// ============================================================================
// File        : edrv32_render_compose_dma.v
// Description : Streaming RGB565 base + premultiplied ARGB foreground composer.
// Notes       : Full aligned rows. Read FIFOs, blend pipe and burst writer run
//               concurrently; source and destination may be the same Surface.
// ============================================================================

module edrv32_render_compose_dma #(
    parameter [3:0] AXI_ID = 4'h7,
    parameter EXTERNAL_BLEND = 0
) (
    input  wire         clk_i,
    input  wire         rst_n_i,

    input  wire         start_i,
    output wire         start_ready_o,
    input  wire [31:0]  base_addr_i,
    input  wire [31:0]  base_stride_i,
    input  wire [31:0]  front_addr_i,
    input  wire [31:0]  front_stride_i,
    input  wire [31:0]  target_addr_i,
    input  wire [31:0]  target_stride_i,
    input  wire [15:0]  width_i,
    input  wire [15:0]  height_i,
    output wire         busy_o,
    output wire         done_o,
    output wire         error_o,
    output wire [31:0]  read_beat_count_o,
    output wire [31:0]  write_beat_count_o,

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

    localparam [1:0] RD_SELECT = 2'd0;
    localparam [1:0] RD_AR     = 2'd1;
    localparam [1:0] RD_R      = 2'd2;
    localparam [1:0] WR_SELECT = 2'd0;
    localparam [1:0] WR_AW     = 2'd1;
    localparam [1:0] WR_W      = 2'd2;
    localparam [1:0] WR_B      = 2'd3;

    function [4:0] choose_burst;
        input [15:0] remaining;
        input [31:0] address;
        reg [7:0] boundary;
        reg [7:0] limited;
        begin
            boundary = 8'd128 - {1'b0, address[11:5]};
            limited = remaining < 16'd16 ?
                {1'b0, remaining[6:0]} : 8'd16;
            choose_burst = limited < boundary ?
                limited[4:0] : boundary[4:0];
        end
    endfunction

    reg         active_r;
    reg         done_r;
    reg         error_r;
    reg [15:0]  width_r;
    reg [15:0]  height_r;
    reg [31:0]  base_stride_r;
    reg [31:0]  front_stride_r;
    reg [31:0]  target_stride_r;
    reg [15:0]  base_row_r;
    reg [15:0]  front_row_r;
    reg [15:0]  target_row_r;
    reg [15:0]  base_index_r;
    reg [15:0]  front_index_r;
    reg [15:0]  target_index_r;
    reg [31:0]  base_row_addr_r;
    reg [31:0]  front_row_addr_r;
    reg [31:0]  target_row_addr_r;
    reg [1:0]   rd_state_r;
    reg         rd_front_r;
    reg [31:0]  araddr_r;
    reg [4:0]   rd_burst_len_r;
    reg [4:0]   rd_beat_index_r;
    reg [1:0]   wr_state_r;
    reg [31:0]  awaddr_r;
    reg [4:0]   wr_burst_len_r;
    reg [4:0]   wr_beat_index_r;
    reg [2:0]   base_pair_index_r;
    reg [1:0]   front_pair_index_r;
    reg [31:0]  pair_issued_r;
    reg [2:0]   pack_index_r;
    reg [255:0] pack_r;
    reg [31:0]  read_beat_count_r;
    reg [31:0]  write_beat_count_r;

    wire start_fire_w = start_i && start_ready_o;
    wire [15:0] base_row_beats_w = width_r >> 4;
    wire [15:0] front_row_beats_w = width_r >> 3;
    wire [31:0] total_pairs_w = ({16'd0, width_r} *
                                 {16'd0, height_r}) >> 1;
    wire [31:0] base_issue_addr_w = base_row_addr_r +
                                    {11'd0, base_index_r, 5'd0};
    wire [31:0] front_issue_addr_w = front_row_addr_r +
                                     {11'd0, front_index_r, 5'd0};
    wire [31:0] target_issue_addr_w = target_row_addr_r +
                                      {11'd0, target_index_r, 5'd0};
    wire [4:0] base_burst_w = choose_burst(
        base_row_beats_w - base_index_r, base_issue_addr_w);
    wire [4:0] front_burst_w = choose_burst(
        front_row_beats_w - front_index_r, front_issue_addr_w);
    wire [4:0] target_burst_w = choose_burst(
        base_row_beats_w - target_index_r, target_issue_addr_w);

    wire [255:0] base_fifo_data_w;
    wire [255:0] front_fifo_data_w;
    wire [255:0] output_fifo_data_w;
    wire base_fifo_full_w, base_fifo_empty_w;
    wire front_fifo_full_w, front_fifo_empty_w;
    wire output_fifo_full_w, output_fifo_empty_w;
    wire [5:0] base_fifo_count_w;
    wire [6:0] front_fifo_count_w;
    wire [5:0] output_fifo_count_w;
    wire base_can_read_w = (base_row_r < height_r) &&
        ((7'd32 - {1'b0, base_fifo_count_w}) >= {2'd0, base_burst_w});
    wire front_can_read_w = (front_row_r < height_r) &&
        ((8'd64 - {1'b0, front_fifo_count_w}) >= {3'd0, front_burst_w});
    wire choose_base_w = base_can_read_w &&
        (!front_can_read_w ||
         ({1'b0, base_fifo_count_w, 1'b0} <=
          {1'b0, front_fifo_count_w}));
    wire ar_fire_w = m_arvalid_o && m_arready_i;
    wire r_fire_w = m_rvalid_i && m_rready_o;
    wire aw_fire_w = m_awvalid_o && m_awready_i;
    wire w_fire_w = m_wvalid_o && m_wready_i;
    wire b_fire_w = m_bvalid_i && m_bready_o;
    wire base_fifo_push_w = r_fire_w && !rd_front_r;
    wire front_fifo_push_w = r_fire_w && rd_front_r;
    wire output_fifo_pop_w = w_fire_w;

    wire [31:0] base_pair_w =
        base_fifo_data_w[base_pair_index_r*32 +: 32];
    wire [63:0] front_pair_w =
        front_fifo_data_w[front_pair_index_r*64 +: 64];
    wire [63:0] base_argb_w;
    wire [63:0] blended_argb_w;
    wire [31:0] output_pair_w;
    wire [31:0] unused_tag_w;
    wire alpha_valid_w;
    wire alpha_ready_w;
    wire pair_valid_w = active_r && (pair_issued_r < total_pairs_w) &&
                        !base_fifo_empty_w && !front_fifo_empty_w;
    wire pair_fire_w = pair_valid_w && alpha_ready_w;
    wire base_fifo_pop_w = pair_fire_w && (base_pair_index_r == 3'd7);
    wire front_fifo_pop_w = pair_fire_w && (front_pair_index_r == 2'd3);
    wire output_ready_w = (pack_index_r != 3'd7) ||
                          !output_fifo_full_w;
    wire output_fire_w = alpha_valid_w && output_ready_w;
    wire output_fifo_push_w = output_fire_w &&
                              (pack_index_r == 3'd7);
    reg [255:0] packed_word_w;
    always @(*) begin
        packed_word_w = pack_r;
        packed_word_w[pack_index_r*32 +: 32] = output_pair_w;
    end

    edrv32_render_fifo #(.DEPTH(32)) u_base_fifo (
        .clk_i(clk_i), .rst_n_i(rst_n_i), .flush_i(start_fire_w),
        .push_i(base_fifo_push_w), .write_data_i(m_rdata_i),
        .pop_i(base_fifo_pop_w), .read_data_o(base_fifo_data_w),
        .full_o(base_fifo_full_w), .empty_o(base_fifo_empty_w),
        .count_o(base_fifo_count_w)
    );
    edrv32_render_fifo #(.DEPTH(64)) u_front_fifo (
        .clk_i(clk_i), .rst_n_i(rst_n_i), .flush_i(start_fire_w),
        .push_i(front_fifo_push_w), .write_data_i(m_rdata_i),
        .pop_i(front_fifo_pop_w), .read_data_o(front_fifo_data_w),
        .full_o(front_fifo_full_w), .empty_o(front_fifo_empty_w),
        .count_o(front_fifo_count_w)
    );
    edrv32_render_fifo #(.DEPTH(32)) u_output_fifo (
        .clk_i(clk_i), .rst_n_i(rst_n_i), .flush_i(start_fire_w),
        .push_i(output_fifo_push_w), .write_data_i(packed_word_w),
        .pop_i(output_fifo_pop_w), .read_data_o(output_fifo_data_w),
        .full_o(output_fifo_full_w), .empty_o(output_fifo_empty_w),
        .count_o(output_fifo_count_w)
    );

    edrv32_render_compose_format u_format (
        .base565_i(base_pair_w), .base_argb_o(base_argb_w),
        .blended_argb_i(blended_argb_w),
        .display565_o(output_pair_w)
    );
    assign blend_in_valid_o = pair_valid_w;
    assign blend_src_o = front_pair_w;
    assign blend_dst_o = base_argb_w;
    assign blend_opacity_o = 16'hffff;
    assign blend_premul_o = 1'b1;
    assign blend_tag_o = pair_issued_r;
    assign blend_out_ready_o = output_ready_w;

    generate if (EXTERNAL_BLEND) begin : g_external_blend
        assign alpha_ready_w = blend_in_ready_i;
        assign alpha_valid_w = blend_out_valid_i;
        assign blended_argb_w = blend_pixel_i;
        assign unused_tag_w = 32'b0;
    end else begin : g_local_blend
        edrv32_render_alpha_pipe u_alpha (
            .clk_i(clk_i), .rst_n_i(rst_n_i),
            .in_valid_i(pair_valid_w), .in_ready_o(alpha_ready_w),
            .in_src_i(front_pair_w), .in_dst_i(base_argb_w),
            .in_opacity_i(16'hffff), .in_src_premul_i(1'b1),
            .in_tag_i(pair_issued_r),
            .out_valid_o(alpha_valid_w), .out_ready_i(output_ready_w),
            .out_pixel_o(blended_argb_w), .out_tag_o(unused_tag_w)
        );
    end endgenerate

    assign start_ready_o = !active_r;
    assign busy_o = active_r;
    assign done_o = done_r;
    assign error_o = error_r;
    assign read_beat_count_o = read_beat_count_r;
    assign write_beat_count_o = write_beat_count_r;

    assign m_arid_o = AXI_ID;
    assign m_araddr_o = araddr_r;
    assign m_arlen_o = {3'b0, rd_burst_len_r} - 8'd1;
    assign m_arsize_o = 3'd5;
    assign m_arburst_o = 2'b01;
    assign m_arqos_o = 4'd4;
    assign m_arvalid_o = active_r && (rd_state_r == RD_AR);
    assign m_rready_o = active_r && (rd_state_r == RD_R) &&
                        (rd_front_r ? !front_fifo_full_w :
                                      !base_fifo_full_w);

    assign m_awid_o = AXI_ID;
    assign m_awaddr_o = awaddr_r;
    assign m_awlen_o = {3'b0, wr_burst_len_r} - 8'd1;
    assign m_awsize_o = 3'd5;
    assign m_awburst_o = 2'b01;
    assign m_awqos_o = 4'd4;
    assign m_awvalid_o = active_r && (wr_state_r == WR_AW);
    assign m_wdata_o = output_fifo_data_w;
    assign m_wstrb_o = 32'hffff_ffff;
    assign m_wlast_o = wr_beat_index_r == wr_burst_len_r - 5'd1;
    assign m_wvalid_o = active_r && (wr_state_r == WR_W) &&
                        !output_fifo_empty_w;
    assign m_bready_o = active_r && (wr_state_r == WR_B);

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            active_r <= 1'b0;
            done_r <= 1'b0;
            error_r <= 1'b0;
            width_r <= 16'b0;
            height_r <= 16'b0;
            base_stride_r <= 32'b0;
            front_stride_r <= 32'b0;
            target_stride_r <= 32'b0;
            base_row_r <= 16'b0;
            front_row_r <= 16'b0;
            target_row_r <= 16'b0;
            base_index_r <= 16'b0;
            front_index_r <= 16'b0;
            target_index_r <= 16'b0;
            base_row_addr_r <= 32'b0;
            front_row_addr_r <= 32'b0;
            target_row_addr_r <= 32'b0;
            rd_state_r <= RD_SELECT;
            rd_front_r <= 1'b0;
            araddr_r <= 32'b0;
            rd_burst_len_r <= 5'b0;
            rd_beat_index_r <= 5'b0;
            wr_state_r <= WR_SELECT;
            awaddr_r <= 32'b0;
            wr_burst_len_r <= 5'b0;
            wr_beat_index_r <= 5'b0;
            base_pair_index_r <= 3'b0;
            front_pair_index_r <= 2'b0;
            pair_issued_r <= 32'b0;
            pack_index_r <= 3'b0;
            read_beat_count_r <= 32'b0;
            write_beat_count_r <= 32'b0;
        end else begin
            done_r <= 1'b0;
            if (start_fire_w) begin
                error_r <= (base_addr_i[4:0] != 5'd0) ||
                           (front_addr_i[4:0] != 5'd0) ||
                           (target_addr_i[4:0] != 5'd0) ||
                           (base_stride_i[4:0] != 5'd0) ||
                           (front_stride_i[4:0] != 5'd0) ||
                           (target_stride_i[4:0] != 5'd0) ||
                           (width_i[3:0] != 4'd0);
                active_r <= (width_i != 16'd0) && (height_i != 16'd0) &&
                            (width_i[3:0] == 4'd0) &&
                            (base_addr_i[4:0] == 5'd0) &&
                            (front_addr_i[4:0] == 5'd0) &&
                            (target_addr_i[4:0] == 5'd0) &&
                            (base_stride_i[4:0] == 5'd0) &&
                            (front_stride_i[4:0] == 5'd0) &&
                            (target_stride_i[4:0] == 5'd0);
                if ((width_i == 16'd0) || (height_i == 16'd0) ||
                    (width_i[3:0] != 4'd0) ||
                    (base_addr_i[4:0] != 5'd0) ||
                    (front_addr_i[4:0] != 5'd0) ||
                    (target_addr_i[4:0] != 5'd0) ||
                    (base_stride_i[4:0] != 5'd0) ||
                    (front_stride_i[4:0] != 5'd0) ||
                    (target_stride_i[4:0] != 5'd0))
                    done_r <= 1'b1;
                width_r <= width_i;
                height_r <= height_i;
                base_stride_r <= base_stride_i;
                front_stride_r <= front_stride_i;
                target_stride_r <= target_stride_i;
                base_row_r <= 16'b0;
                front_row_r <= 16'b0;
                target_row_r <= 16'b0;
                base_index_r <= 16'b0;
                front_index_r <= 16'b0;
                target_index_r <= 16'b0;
                base_row_addr_r <= base_addr_i;
                front_row_addr_r <= front_addr_i;
                target_row_addr_r <= target_addr_i;
                rd_state_r <= RD_SELECT;
                wr_state_r <= WR_SELECT;
                base_pair_index_r <= 3'b0;
                front_pair_index_r <= 2'b0;
                pair_issued_r <= 32'b0;
                pack_index_r <= 3'b0;
                read_beat_count_r <= 32'b0;
                write_beat_count_r <= 32'b0;
            end else if (active_r) begin
                if (rd_state_r == RD_SELECT) begin
                    if (choose_base_w) begin
                        rd_front_r <= 1'b0;
                        araddr_r <= base_issue_addr_w;
                        rd_burst_len_r <= base_burst_w;
                        rd_state_r <= RD_AR;
                    end else if (front_can_read_w) begin
                        rd_front_r <= 1'b1;
                        araddr_r <= front_issue_addr_w;
                        rd_burst_len_r <= front_burst_w;
                        rd_state_r <= RD_AR;
                    end
                end else if (rd_state_r == RD_AR) begin
                    if (ar_fire_w) begin
                        rd_beat_index_r <= 5'd0;
                        rd_state_r <= RD_R;
                    end
                end else if (r_fire_w) begin
                    read_beat_count_r <= read_beat_count_r + 32'd1;
                    if ((m_rid_i != AXI_ID) ||
                        (m_rresp_i != 2'b00) ||
                        (m_rlast_i !=
                         (rd_beat_index_r == rd_burst_len_r - 5'd1)))
                        error_r <= 1'b1;
                    if (rd_beat_index_r == rd_burst_len_r - 5'd1) begin
                        rd_state_r <= RD_SELECT;
                        if (rd_front_r) begin
                            if (front_index_r +
                                {11'd0, rd_burst_len_r} ==
                                front_row_beats_w) begin
                                front_row_r <= front_row_r + 16'd1;
                                front_index_r <= 16'd0;
                                front_row_addr_r <= front_row_addr_r +
                                                    front_stride_r;
                            end else begin
                                front_index_r <= front_index_r +
                                                 {11'd0, rd_burst_len_r};
                            end
                        end else begin
                            if (base_index_r +
                                {11'd0, rd_burst_len_r} ==
                                base_row_beats_w) begin
                                base_row_r <= base_row_r + 16'd1;
                                base_index_r <= 16'd0;
                                base_row_addr_r <= base_row_addr_r +
                                                   base_stride_r;
                            end else begin
                                base_index_r <= base_index_r +
                                                {11'd0, rd_burst_len_r};
                            end
                        end
                    end else begin
                        rd_beat_index_r <= rd_beat_index_r + 5'd1;
                    end
                end

                if (pair_fire_w) begin
                    pair_issued_r <= pair_issued_r + 32'd1;
                    base_pair_index_r <= base_pair_index_r + 3'd1;
                    front_pair_index_r <= front_pair_index_r + 2'd1;
                end
                if (output_fire_w) begin
                    pack_r <= packed_word_w;
                    pack_index_r <= pack_index_r + 3'd1;
                end

                case (wr_state_r)
                    WR_SELECT: begin
                        if ((target_row_r < height_r) &&
                            ({1'b0, output_fifo_count_w} >=
                             {2'd0, target_burst_w})) begin
                            awaddr_r <= target_issue_addr_w;
                            wr_burst_len_r <= target_burst_w;
                            wr_state_r <= WR_AW;
                        end
                    end
                    WR_AW: begin
                        if (aw_fire_w) begin
                            wr_beat_index_r <= 5'd0;
                            wr_state_r <= WR_W;
                        end
                    end
                    WR_W: begin
                        if (w_fire_w) begin
                            write_beat_count_r <= write_beat_count_r + 32'd1;
                            if (m_wlast_o)
                                wr_state_r <= WR_B;
                            else
                                wr_beat_index_r <= wr_beat_index_r + 5'd1;
                        end
                    end
                    WR_B: begin
                        if (b_fire_w) begin
                            if ((m_bid_i != AXI_ID) ||
                                (m_bresp_i != 2'b00))
                                error_r <= 1'b1;
                            if (target_index_r +
                                {11'd0, wr_burst_len_r} ==
                                base_row_beats_w) begin
                                if (target_row_r == height_r - 16'd1) begin
                                    active_r <= 1'b0;
                                    done_r <= 1'b1;
                                end else begin
                                    target_row_r <= target_row_r + 16'd1;
                                    target_index_r <= 16'd0;
                                    target_row_addr_r <= target_row_addr_r +
                                                         target_stride_r;
                                end
                            end else begin
                                target_index_r <= target_index_r +
                                                  {11'd0, wr_burst_len_r};
                            end
                            wr_state_r <= WR_SELECT;
                        end
                    end
                    default: wr_state_r <= WR_SELECT;
                endcase
            end
        end
    end

endmodule
