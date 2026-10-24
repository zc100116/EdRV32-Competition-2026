// ============================================================================
// File        : edrv32_yolo_maxpool5_dma.v
// Description : Same-size signed INT8 5x5 maxpool over C16 DDR planes.
// Notes       : A P5 plane is cached once (at most 20x12x16 bytes). One
//               neighbor pixel is compared per clock pair, preserving one
//               RAM read port. Padding contributes the INT8 minimum.
// ============================================================================

module edrv32_yolo_maxpool5_dma (
    input  wire         clk_i,
    input  wire         rst_n_i,

    input  wire         start_i,
    output wire         start_ready_o,
    input  wire [31:0]  input_base_i,
    input  wire [31:0]  input_plane_stride_i,
    input  wire [31:0]  output_base_i,
    input  wire [31:0]  output_plane_stride_i,
    input  wire [3:0]   plane_count_i,
    input  wire [3:0]   width_pairs_i,
    input  wire [3:0]   height_i,
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

    localparam [3:0] S_IDLE        = 4'd0;
    localparam [3:0] S_READ_REQ    = 4'd1;
    localparam [3:0] S_READ_WAIT   = 4'd2;
    localparam [3:0] S_SAMPLE_REQ  = 4'd3;
    localparam [3:0] S_SAMPLE_USE  = 4'd4;
    localparam [3:0] S_WRITE_AW    = 4'd5;
    localparam [3:0] S_WRITE_W     = 4'd6;
    localparam [3:0] S_WRITE_B     = 4'd7;
    localparam [3:0] S_SAMPLE_ADDR = 4'd8;

    reg [3:0] state_r;
    reg done_r;
    reg error_r;
    reg [31:0] input_plane_base_r;
    reg [31:0] output_plane_base_r;
    reg [31:0] output_row_addr_r;
    reg [31:0] write_addr_r;
    reg [31:0] input_plane_stride_r;
    reg [31:0] output_plane_stride_r;
    reg [3:0] plane_count_r;
    reg [3:0] plane_r;
    reg [3:0] width_pairs_r;
    reg [3:0] height_r;
    reg [3:0] row_r;
    reg [3:0] pair_r;
    reg pixel_r;
    reg [2:0] dx_r;
    reg [2:0] dy_r;
    reg [127:0] max_r;
    reg [127:0] pixel0_r;
    reg [255:0] plane_read_data_r;
    reg neighbor_valid_r;
    reg neighbor_odd_r;
    reg [6:0] neighbor_addr_r;
    reg [3:0] write_index_r;
    reg [3:0] burst_beats_r;
    reg [3:0] burst_index_r;
    reg [255:0] plane_buffer_r [0:119];
    reg [255:0] row_buffer_r [0:9];

    wire reader_req_ready_w;
    wire reader_beat_valid_w;
    wire [15:0] reader_beat_index_w;
    wire [255:0] reader_beat_data_w;
    wire reader_done_w, reader_error_w;
    wire [7:0] plane_beats_w = width_pairs_r * height_r;
    wire [31:0] row_bytes_w = {23'd0, width_pairs_r, 5'd0};
    wire signed [11:0] center_x_w =
        $signed({7'd0, pair_r, 1'b0}) +
        $signed({11'd0, pixel_r});
    wire signed [11:0] neighbor_x_w = center_x_w +
        $signed({9'd0, dx_r}) - 12'sd2;
    wire signed [11:0] neighbor_y_w =
        $signed({8'd0, row_r}) +
        $signed({9'd0, dy_r}) - 12'sd2;
    wire neighbor_valid_w = neighbor_x_w >= 12'sd0 &&
        neighbor_x_w < $signed({7'd0, width_pairs_r, 1'b0}) &&
        neighbor_y_w >= 12'sd0 &&
        neighbor_y_w < $signed({8'd0, height_r});
    wire signed [11:0] neighbor_index_w =
        neighbor_y_w * $signed({8'd0, width_pairs_r}) +
        (neighbor_x_w >>> 1);
    wire [127:0] neighbor_pixel_w = neighbor_odd_r ?
        plane_read_data_r[255:128] : plane_read_data_r[127:0];
    wire [127:0] max_next_w;
    genvar lane;
    generate
        for (lane = 0; lane < 16; lane = lane + 1) begin : g_max_lane
            wire signed [7:0] candidate_w = neighbor_valid_r ?
                neighbor_pixel_w[lane*8 +: 8] : 8'h80;
            wire signed [7:0] prior_w = max_r[lane*8 +: 8];
            assign max_next_w[lane*8 +: 8] =
                candidate_w > prior_w ? candidate_w : prior_w;
        end
    endgenerate

    wire [31:0] after_burst_addr_w = write_addr_r +
                                      {23'd0, burst_beats_r, 5'd0};
    wire [4:0] remaining_w = {1'b0, width_pairs_r} -
                              {1'b0, write_index_r};
    wire [7:0] first_boundary_w = 8'd128 -
                                   {1'b0, output_row_addr_r[11:5]};
    wire [7:0] next_boundary_w = 8'd128 -
                                  {1'b0, after_burst_addr_w[11:5]};
    wire [7:0] first_burst_w = {4'd0, width_pairs_r} <
                                first_boundary_w ?
                                {4'd0, width_pairs_r} :
                                first_boundary_w;
    wire [7:0] next_burst_w = {3'd0, remaining_w} < next_boundary_w ?
                               {3'd0, remaining_w} : next_boundary_w;
    wire aw_fire_w = m_awvalid_o && m_awready_i;
    wire w_fire_w = m_wvalid_o && m_wready_i;
    wire b_fire_w = m_bvalid_i && m_bready_o;

    assign start_ready_o = state_r == S_IDLE &&
        plane_count_i != 4'd0 && plane_count_i <= 4'd8 &&
        width_pairs_i != 4'd0 && width_pairs_i <= 4'd10 &&
        height_i != 4'd0 && height_i <= 4'd12 &&
        input_base_i[4:0] == 5'd0 && output_base_i[4:0] == 5'd0;
    assign busy_o = state_r != S_IDLE;
    assign done_o = done_r;
    assign error_o = error_r;

    edrv32_yolo_axi_reader u_reader (
        .clk_i(clk_i), .rst_n_i(rst_n_i),
        .req_valid_i(state_r == S_READ_REQ),
        .req_ready_o(reader_req_ready_w),
        .req_addr_i(input_plane_base_r),
        .req_beats_i({8'd0, plane_beats_w}),
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
    assign m_awaddr_o = write_addr_r;
    assign m_awlen_o = {4'd0, burst_beats_r} - 8'd1;
    assign m_awsize_o = 3'd5;
    assign m_awburst_o = 2'b01;
    assign m_awvalid_o = state_r == S_WRITE_AW;
    assign m_wdata_o = row_buffer_r[write_index_r];
    assign m_wstrb_o = 32'hffff_ffff;
    assign m_wlast_o = burst_index_r + 4'd1 == burst_beats_r;
    assign m_wvalid_o = state_r == S_WRITE_W;
    assign m_bready_o = state_r == S_WRITE_B;

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            state_r <= S_IDLE;
            done_r <= 1'b0;
            error_r <= 1'b0;
            input_plane_base_r <= 32'd0;
            output_plane_base_r <= 32'd0;
            output_row_addr_r <= 32'd0;
            write_addr_r <= 32'd0;
            input_plane_stride_r <= 32'd0;
            output_plane_stride_r <= 32'd0;
            plane_count_r <= 4'd0;
            plane_r <= 4'd0;
            width_pairs_r <= 4'd0;
            height_r <= 4'd0;
            row_r <= 4'd0;
            pair_r <= 4'd0;
            pixel_r <= 1'b0;
            dx_r <= 3'd0;
            dy_r <= 3'd0;
            max_r <= {16{8'h80}};
            pixel0_r <= 128'd0;
            neighbor_valid_r <= 1'b0;
            neighbor_odd_r <= 1'b0;
            neighbor_addr_r <= 7'd0;
            write_index_r <= 4'd0;
            burst_beats_r <= 4'd0;
            burst_index_r <= 4'd0;
        end else begin
            done_r <= 1'b0;
            if (state_r == S_READ_WAIT && reader_beat_valid_w)
                plane_buffer_r[reader_beat_index_w[6:0]] <=
                    reader_beat_data_w;
            case (state_r)
                S_IDLE: if (start_i && start_ready_o) begin
                    input_plane_base_r <= input_base_i;
                    output_plane_base_r <= output_base_i;
                    output_row_addr_r <= output_base_i;
                    write_addr_r <= output_base_i;
                    input_plane_stride_r <= input_plane_stride_i;
                    output_plane_stride_r <= output_plane_stride_i;
                    plane_count_r <= plane_count_i;
                    plane_r <= 4'd0;
                    width_pairs_r <= width_pairs_i;
                    height_r <= height_i;
                    row_r <= 4'd0;
                    error_r <= 1'b0;
                    state_r <= S_READ_REQ;
                end
                S_READ_REQ: if (reader_req_ready_w)
                    state_r <= S_READ_WAIT;
                S_READ_WAIT: if (reader_done_w) begin
                    if (reader_error_w) error_r <= 1'b1;
                    pair_r <= 4'd0;
                    pixel_r <= 1'b0;
                    dx_r <= 3'd0;
                    dy_r <= 3'd0;
                    max_r <= {16{8'h80}};
                    state_r <= S_SAMPLE_ADDR;
                end
                S_SAMPLE_ADDR: begin
                    neighbor_valid_r <= neighbor_valid_w;
                    neighbor_odd_r <= neighbor_x_w[0];
                    neighbor_addr_r <= neighbor_valid_w ?
                                       neighbor_index_w[6:0] : 7'd0;
                    state_r <= S_SAMPLE_REQ;
                end
                S_SAMPLE_REQ: begin
                    plane_read_data_r <= plane_buffer_r[neighbor_addr_r];
                    state_r <= S_SAMPLE_USE;
                end
                S_SAMPLE_USE: begin
                    state_r <= S_SAMPLE_ADDR;
                    max_r <= max_next_w;
                    if (dx_r == 3'd4) begin
                        dx_r <= 3'd0;
                        if (dy_r == 3'd4) begin
                            dy_r <= 3'd0;
                            max_r <= {16{8'h80}};
                            if (!pixel_r) begin
                                pixel0_r <= max_next_w;
                                pixel_r <= 1'b1;
                            end else begin
                                row_buffer_r[pair_r] <=
                                    {max_next_w, pixel0_r};
                                pixel_r <= 1'b0;
                                if (pair_r + 4'd1 == width_pairs_r) begin
                                    write_index_r <= 4'd0;
                                    burst_beats_r <= first_burst_w[3:0];
                                    burst_index_r <= 4'd0;
                                    state_r <= S_WRITE_AW;
                                end else
                                    pair_r <= pair_r + 4'd1;
                            end
                        end else
                            dy_r <= dy_r + 3'd1;
                    end else
                        dx_r <= dx_r + 3'd1;
                end
                S_WRITE_AW: if (aw_fire_w) begin
                    burst_index_r <= 4'd0;
                    state_r <= S_WRITE_W;
                end
                S_WRITE_W: if (w_fire_w) begin
                    write_index_r <= write_index_r + 4'd1;
                    burst_index_r <= burst_index_r + 4'd1;
                    if (m_wlast_o)
                        state_r <= S_WRITE_B;
                end
                S_WRITE_B: if (b_fire_w) begin
                    if (m_bid_i != 4'h9 || m_bresp_i != 2'b00)
                        error_r <= 1'b1;
                    write_addr_r <= after_burst_addr_w;
                    if (write_index_r == width_pairs_r) begin
                        if (row_r + 4'd1 == height_r) begin
                            if (plane_r + 4'd1 == plane_count_r) begin
                                done_r <= 1'b1;
                                state_r <= S_IDLE;
                            end else begin
                                plane_r <= plane_r + 4'd1;
                                row_r <= 4'd0;
                                input_plane_base_r <= input_plane_base_r +
                                                      input_plane_stride_r;
                                output_plane_base_r <= output_plane_base_r +
                                                       output_plane_stride_r;
                                output_row_addr_r <= output_plane_base_r +
                                                     output_plane_stride_r;
                                write_addr_r <= output_plane_base_r +
                                                output_plane_stride_r;
                                state_r <= S_READ_REQ;
                            end
                        end else begin
                            row_r <= row_r + 4'd1;
                            output_row_addr_r <= output_row_addr_r +
                                                 row_bytes_w;
                            write_addr_r <= output_row_addr_r + row_bytes_w;
                            pair_r <= 4'd0;
                            pixel_r <= 1'b0;
                            dx_r <= 3'd0;
                            dy_r <= 3'd0;
                            max_r <= {16{8'h80}};
                            state_r <= S_SAMPLE_ADDR;
                        end
                    end else begin
                        burst_beats_r <= next_burst_w[3:0];
                        state_r <= S_WRITE_AW;
                    end
                end
                default: state_r <= S_IDLE;
            endcase
        end
    end
endmodule
