// ============================================================================
// File        : edrv32_yolo_upsample2x_dma.v
// Description : Nearest-neighbor 2x DDR feature-map expansion for YOLOv8n.
// Notes       : One C16 row is read once, then emitted twice. Each source
//               pixel is duplicated horizontally in a 256-bit output beat.
//               Bursts have at most 16 beats and never cross 4 KiB.
// ============================================================================

module edrv32_yolo_upsample2x_dma (
    input  wire         clk_i,
    input  wire         rst_n_i,

    input  wire         start_i,
    output wire         start_ready_o,
    input  wire [31:0]  input_base_i,
    input  wire [31:0]  input_plane_stride_i,
    input  wire [31:0]  output_base_i,
    input  wire [31:0]  output_plane_stride_i,
    input  wire [4:0]   plane_count_i,
    input  wire [4:0]   input_width_pairs_i,
    input  wire [7:0]   input_height_i,
    output wire         busy_o,
    output wire         done_o,
    output wire         error_o,

    output wire [3:0]   m_arid_o,
    output wire [31:0]  m_araddr_o,
    output wire [7:0]   m_arlen_o,
    output wire [2:0]   m_arsize_o,
    output wire [1:0]   m_arburst_o,
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

    localparam [2:0] S_IDLE = 3'd0;
    localparam [2:0] S_READ_REQ = 3'd1;
    localparam [2:0] S_READ_WAIT = 3'd2;
    localparam [2:0] S_WRITE_AW = 3'd3;
    localparam [2:0] S_WRITE_W = 3'd4;
    localparam [2:0] S_WRITE_B = 3'd5;

    reg [2:0] state_r;
    reg done_r;
    reg error_r;
    reg [31:0] input_plane_base_r;
    reg [31:0] output_plane_base_r;
    reg [31:0] input_addr_r;
    reg [31:0] output_addr_r;
    reg [31:0] input_plane_stride_r;
    reg [31:0] output_plane_stride_r;
    reg [4:0] plane_count_r;
    reg [4:0] plane_r;
    reg [4:0] width_pairs_r;
    reg [7:0] height_r;
    reg [7:0] row_r;
    reg [6:0] write_index_r;
    reg [4:0] burst_beats_r;
    reg [4:0] burst_index_r;
    reg [255:0] row_buffer_r [0:19];

    wire reader_req_ready_w;
    wire reader_beat_valid_w;
    wire [15:0] reader_beat_index_w;
    wire [255:0] reader_beat_data_w;
    wire reader_done_w, reader_error_w;
    wire [6:0] row_output_beats_w = {width_pairs_r, 2'd0};
    wire [6:0] output_row_beats_w = {width_pairs_r, 1'b0};
    wire [6:0] remaining_w = row_output_beats_w - write_index_r;
    wire [31:0] after_burst_addr_w = output_addr_r +
                                      {22'd0, burst_beats_r, 5'd0};
    wire [7:0] first_boundary_w = 8'd128 -
                                   {1'b0, output_addr_r[11:5]};
    wire [7:0] next_boundary_w = 8'd128 -
                                  {1'b0, after_burst_addr_w[11:5]};
    wire [7:0] capped_w = remaining_w < 7'd16 ?
                           {1'b0, remaining_w} : 8'd16;
    wire [7:0] first_capped_w = row_output_beats_w < 7'd16 ?
                                 {1'b0, row_output_beats_w} : 8'd16;
    wire [7:0] first_burst_w = first_capped_w < first_boundary_w ?
                                first_capped_w : first_boundary_w;
    wire [7:0] next_burst_w = capped_w < next_boundary_w ?
                               capped_w : next_boundary_w;
    wire [6:0] row_beat_w = write_index_r >= output_row_beats_w ?
                            write_index_r - output_row_beats_w :
                            write_index_r;
    wire [4:0] source_pair_w = row_beat_w[5:1];
    wire [255:0] source_beat_w = row_buffer_r[source_pair_w];
    wire [127:0] source_pixel_w = row_beat_w[0] ?
                                   source_beat_w[255:128] :
                                   source_beat_w[127:0];
    wire aw_fire_w = m_awvalid_o && m_awready_i;
    wire w_fire_w = m_wvalid_o && m_wready_i;
    wire b_fire_w = m_bvalid_i && m_bready_o;

    assign start_ready_o = state_r == S_IDLE &&
                           plane_count_i != 5'd0 &&
                           input_width_pairs_i != 5'd0 &&
                           input_width_pairs_i <= 5'd20 &&
                           input_height_i != 8'd0 &&
                           input_base_i[4:0] == 5'd0 &&
                           output_base_i[4:0] == 5'd0;
    assign busy_o = state_r != S_IDLE;
    assign done_o = done_r;
    assign error_o = error_r;

    edrv32_yolo_axi_reader u_reader (
        .clk_i(clk_i), .rst_n_i(rst_n_i),
        .req_valid_i(state_r == S_READ_REQ),
        .req_ready_o(reader_req_ready_w),
        .req_addr_i(input_addr_r),
        .req_beats_i({11'd0, width_pairs_r}),
        .beat_valid_o(reader_beat_valid_w),
        .beat_index_o(reader_beat_index_w),
        .beat_data_o(reader_beat_data_w),
        .busy_o(), .done_o(reader_done_w),
        .error_o(reader_error_w),
        .m_arid_o(m_arid_o), .m_araddr_o(m_araddr_o),
        .m_arlen_o(m_arlen_o[3:0]),
        .m_arsize_o(m_arsize_o),
        .m_arburst_o(m_arburst_o),
        .m_arvalid_o(m_arvalid_o),
        .m_arready_i(m_arready_i),
        .m_rid_i(m_rid_i), .m_rdata_i(m_rdata_i),
        .m_rresp_i(m_rresp_i), .m_rlast_i(m_rlast_i),
        .m_rvalid_i(m_rvalid_i), .m_rready_o(m_rready_o)
    );
    assign m_arlen_o[7:4] = 4'd0;

    assign m_awid_o = 4'h9;
    assign m_awaddr_o = output_addr_r;
    assign m_awlen_o = {3'd0, burst_beats_r} - 8'd1;
    assign m_awsize_o = 3'd5;
    assign m_awburst_o = 2'b01;
    assign m_awvalid_o = state_r == S_WRITE_AW;
    assign m_wdata_o = {source_pixel_w, source_pixel_w};
    assign m_wstrb_o = 32'hffff_ffff;
    assign m_wlast_o = burst_index_r + 5'd1 == burst_beats_r;
    assign m_wvalid_o = state_r == S_WRITE_W;
    assign m_bready_o = state_r == S_WRITE_B;

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            state_r <= S_IDLE;
            done_r <= 1'b0;
            error_r <= 1'b0;
            input_plane_base_r <= 32'd0;
            output_plane_base_r <= 32'd0;
            input_addr_r <= 32'd0;
            output_addr_r <= 32'd0;
            input_plane_stride_r <= 32'd0;
            output_plane_stride_r <= 32'd0;
            plane_count_r <= 5'd0;
            plane_r <= 5'd0;
            width_pairs_r <= 5'd0;
            height_r <= 8'd0;
            row_r <= 8'd0;
            write_index_r <= 7'd0;
            burst_beats_r <= 5'd0;
            burst_index_r <= 5'd0;
        end else begin
            done_r <= 1'b0;
            if (state_r == S_READ_WAIT && reader_beat_valid_w)
                row_buffer_r[reader_beat_index_w[4:0]] <=
                    reader_beat_data_w;
            case (state_r)
                S_IDLE: if (start_i && start_ready_o) begin
                    input_plane_base_r <= input_base_i;
                    output_plane_base_r <= output_base_i;
                    input_addr_r <= input_base_i;
                    output_addr_r <= output_base_i;
                    input_plane_stride_r <= input_plane_stride_i;
                    output_plane_stride_r <= output_plane_stride_i;
                    plane_count_r <= plane_count_i;
                    plane_r <= 5'd0;
                    width_pairs_r <= input_width_pairs_i;
                    height_r <= input_height_i;
                    row_r <= 8'd0;
                    error_r <= 1'b0;
                    state_r <= S_READ_REQ;
                end
                S_READ_REQ: if (reader_req_ready_w)
                    state_r <= S_READ_WAIT;
                S_READ_WAIT: if (reader_done_w) begin
                    if (reader_error_w) error_r <= 1'b1;
                    write_index_r <= 7'd0;
                    burst_beats_r <= first_burst_w[4:0];
                    burst_index_r <= 5'd0;
                    state_r <= S_WRITE_AW;
                end
                S_WRITE_AW: if (aw_fire_w) begin
                    burst_index_r <= 5'd0;
                    state_r <= S_WRITE_W;
                end
                S_WRITE_W: if (w_fire_w) begin
                    write_index_r <= write_index_r + 7'd1;
                    burst_index_r <= burst_index_r + 5'd1;
                    if (m_wlast_o)
                        state_r <= S_WRITE_B;
                end
                S_WRITE_B: if (b_fire_w) begin
                    if (m_bid_i != 4'h9 || m_bresp_i != 2'b00)
                        error_r <= 1'b1;
                    output_addr_r <= after_burst_addr_w;
                    if (write_index_r == row_output_beats_w) begin
                        if (row_r + 8'd1 == height_r) begin
                            if (plane_r + 5'd1 == plane_count_r) begin
                                done_r <= 1'b1;
                                state_r <= S_IDLE;
                            end else begin
                                plane_r <= plane_r + 5'd1;
                                row_r <= 8'd0;
                                input_plane_base_r <= input_plane_base_r +
                                                      input_plane_stride_r;
                                output_plane_base_r <= output_plane_base_r +
                                                       output_plane_stride_r;
                                input_addr_r <= input_plane_base_r +
                                                input_plane_stride_r;
                                output_addr_r <= output_plane_base_r +
                                                 output_plane_stride_r;
                                state_r <= S_READ_REQ;
                            end
                        end else begin
                            row_r <= row_r + 8'd1;
                            input_addr_r <= input_addr_r +
                                {22'd0, width_pairs_r, 5'd0};
                            state_r <= S_READ_REQ;
                        end
                    end else begin
                        burst_beats_r <= next_burst_w[4:0];
                        state_r <= S_WRITE_AW;
                    end
                end
                default: state_r <= S_IDLE;
            endcase
        end
    end
endmodule
