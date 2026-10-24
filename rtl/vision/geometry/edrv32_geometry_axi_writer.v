// ============================================================================
// File        : edrv32_geometry_axi_writer.v
// Description : RGB565 raster stream to a strided 256-bit AXI Surface.
// Notes       : Pixels are packed 16 per beat. Bursts contain at most 16 beats
//               and never cross rows; partial row tails use WSTRB.
// ============================================================================

module edrv32_geometry_axi_writer (
    input  wire         clk_i,
    input  wire         rst_n_i,

    input  wire         cfg_start_i,
    output wire         cfg_ready_o,
    input  wire         abort_i,
    input  wire [31:0]  cfg_dst_base_i,
    input  wire [31:0]  cfg_dst_stride_i,
    input  wire [15:0]  cfg_dst_width_i,
    input  wire [15:0]  cfg_dst_height_i,

    input  wire         pixel_valid_i,
    output wire         pixel_ready_o,
    input  wire [15:0]  pixel_data_i,
    input  wire [15:0]  pixel_dst_x_i,
    input  wire [15:0]  pixel_dst_y_i,
    input  wire         pixel_sof_i,
    input  wire         pixel_eol_i,
    input  wire         pixel_eof_i,

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
    output wire         m_bready_o,

    output wire         busy_o,
    output wire         done_o,
    output wire         error_o
);

    localparam [2:0] STATE_IDLE    = 3'd0;
    localparam [2:0] STATE_COLLECT = 3'd1;
    localparam [2:0] STATE_AW      = 3'd2;
    localparam [2:0] STATE_W       = 3'd3;
    localparam [2:0] STATE_B       = 3'd4;
    localparam [1:0] RESP_OKAY = 2'b00;

    reg [2:0] state_r;
    reg done_r;
    reg error_r;
    reg [31:0] stride_r;
    reg [15:0] width_r;
    reg [15:0] height_r;
    reg [15:0] expected_x_r;
    reg [15:0] expected_y_r;
    reg [31:0] row_base_r;
    reg [31:0] burst_addr_r;
    reg [31:0] advance_addr_r;
    reg [255:0] beat_data_r;
    reg [31:0] beat_strb_r;
    reg [3:0] lane_r;
    reg [4:0] burst_count_r;
    reg [4:0] burst_beats_r;
    reg [4:0] send_index_r;
    reg frame_end_pending_r;
    reg row_end_pending_r;
    reg abort_pending_r;
    reg [255:0] burst_data_r [0:15];
    reg [31:0] burst_strb_r [0:15];

    wire cfg_legal_w = (cfg_dst_width_i != 0) &&
        (cfg_dst_height_i != 0) &&
        (cfg_dst_base_i[4:0] == 5'b0) &&
        (cfg_dst_stride_i[4:0] == 5'b0) &&
        ({1'b0, cfg_dst_stride_i} >=
         ({17'b0, cfg_dst_width_i} << 1));
    wire cfg_fire_w = cfg_start_i && cfg_ready_o;
    wire pixel_fire_w = pixel_valid_i && pixel_ready_o;
    wire expected_sof_w = (expected_x_r == 0) && (expected_y_r == 0);
    wire expected_eol_w = expected_x_r == width_r - 1'b1;
    wire expected_eof_w = expected_eol_w &&
        (expected_y_r == height_r - 1'b1);
    wire beat_last_pixel_w = lane_r == 4'd15;
    wire complete_beat_w = beat_last_pixel_w || expected_eol_w;
    wire [4:0] completed_burst_beats_w = burst_count_r + 1'b1;
    wire [7:0] boundary_beats_w =
        8'd128 - {1'b0, burst_addr_r[11:5]};
    wire complete_burst_w = complete_beat_w &&
        ((burst_count_r == 5'd15) || expected_eol_w ||
         (completed_burst_beats_w == boundary_beats_w));
    wire [255:0] next_beat_data_w = beat_data_r |
        ({{240{1'b0}}, pixel_data_i} << ({lane_r, 4'b0}));
    wire [31:0] next_beat_strb_w = beat_strb_r |
        (32'b11 << {lane_r, 1'b0});

    wire aw_fire_w = m_awvalid_o && m_awready_i;
    wire w_fire_w = m_wvalid_o && m_wready_i;
    wire b_fire_w = m_bvalid_i && m_bready_o;

    assign cfg_ready_o = state_r == STATE_IDLE;
    assign pixel_ready_o = state_r == STATE_COLLECT;
    assign m_awid_o = 4'hc;
    assign m_awaddr_o = burst_addr_r;
    assign m_awlen_o = {3'b0, burst_beats_r} - 1'b1;
    assign m_awsize_o = 3'd5;
    assign m_awburst_o = 2'b01;
    assign m_awqos_o = 4'h9;
    assign m_awvalid_o = state_r == STATE_AW;
    assign m_wdata_o = burst_data_r[send_index_r[3:0]];
    assign m_wstrb_o = burst_strb_r[send_index_r[3:0]];
    assign m_wlast_o = (send_index_r + 1'b1) == burst_beats_r;
    assign m_wvalid_o = state_r == STATE_W;
    assign m_bready_o = state_r == STATE_B;
    assign busy_o = state_r != STATE_IDLE;
    assign done_o = done_r;
    assign error_o = error_r;

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            state_r <= STATE_IDLE;
            done_r <= 1'b0;
            error_r <= 1'b0;
            stride_r <= 32'b0;
            width_r <= 16'b0;
            height_r <= 16'b0;
            expected_x_r <= 16'b0;
            expected_y_r <= 16'b0;
            row_base_r <= 32'b0;
            burst_addr_r <= 32'b0;
            advance_addr_r <= 32'b0;
            beat_data_r <= 256'b0;
            beat_strb_r <= 32'b0;
            lane_r <= 4'b0;
            burst_count_r <= 5'b0;
            burst_beats_r <= 5'b0;
            send_index_r <= 5'b0;
            frame_end_pending_r <= 1'b0;
            row_end_pending_r <= 1'b0;
            abort_pending_r <= 1'b0;
        end else begin
            done_r <= 1'b0;

            if (cfg_fire_w) begin
                error_r <= !cfg_legal_w;
                stride_r <= cfg_dst_stride_i;
                width_r <= cfg_dst_width_i;
                height_r <= cfg_dst_height_i;
                expected_x_r <= 16'b0;
                expected_y_r <= 16'b0;
                row_base_r <= cfg_dst_base_i;
                burst_addr_r <= cfg_dst_base_i;
                beat_data_r <= 256'b0;
                beat_strb_r <= 32'b0;
                lane_r <= 4'b0;
                burst_count_r <= 5'b0;
                frame_end_pending_r <= 1'b0;
                row_end_pending_r <= 1'b0;
                abort_pending_r <= 1'b0;
                if (cfg_legal_w) begin
                    state_r <= STATE_COLLECT;
                end else begin
                    state_r <= STATE_IDLE;
                    done_r <= 1'b1;
                end
            end

            if (pixel_fire_w) begin
                if ((pixel_dst_x_i != expected_x_r) ||
                    (pixel_dst_y_i != expected_y_r) ||
                    (pixel_sof_i != expected_sof_w) ||
                    (pixel_eol_i != expected_eol_w) ||
                    (pixel_eof_i != expected_eof_w))
                    error_r <= 1'b1;

                if (complete_beat_w) begin
                    burst_data_r[burst_count_r[3:0]] <= next_beat_data_w;
                    burst_strb_r[burst_count_r[3:0]] <= next_beat_strb_w;
                    beat_data_r <= 256'b0;
                    beat_strb_r <= 32'b0;
                    lane_r <= 4'b0;
                    if (complete_burst_w) begin
                        burst_beats_r <= completed_burst_beats_w;
                        burst_count_r <= 5'b0;
                        send_index_r <= 5'b0;
                        frame_end_pending_r <= expected_eof_w;
                        row_end_pending_r <= expected_eol_w;
                        advance_addr_r <= expected_eol_w ?
                            row_base_r + stride_r :
                            burst_addr_r +
                            {completed_burst_beats_w, 5'b0};
                        state_r <= STATE_AW;
                    end else begin
                        burst_count_r <= burst_count_r + 1'b1;
                    end
                end else begin
                    beat_data_r <= next_beat_data_w;
                    beat_strb_r <= next_beat_strb_w;
                    lane_r <= lane_r + 1'b1;
                end

                if (expected_eol_w) begin
                    expected_x_r <= 16'b0;
                    if (!expected_eof_w)
                        expected_y_r <= expected_y_r + 1'b1;
                end else begin
                    expected_x_r <= expected_x_r + 1'b1;
                end
            end

            if (aw_fire_w)
                state_r <= STATE_W;

            if (w_fire_w) begin
                if (m_wlast_o) begin
                    send_index_r <= 5'b0;
                    state_r <= STATE_B;
                end else begin
                    send_index_r <= send_index_r + 1'b1;
                end
            end

            if (b_fire_w) begin
                if ((m_bid_i != 4'hc) || (m_bresp_i != RESP_OKAY))
                    error_r <= 1'b1;
                burst_addr_r <= advance_addr_r;
                if (row_end_pending_r)
                    row_base_r <= advance_addr_r;
                if (frame_end_pending_r || abort_pending_r || abort_i) begin
                    state_r <= STATE_IDLE;
                    done_r <= 1'b1;
                end else begin
                    state_r <= STATE_COLLECT;
                end
                frame_end_pending_r <= 1'b0;
                row_end_pending_r <= 1'b0;
                abort_pending_r <= 1'b0;
            end

            if (abort_i && (state_r != STATE_IDLE)) begin
                error_r <= 1'b1;
                // Once AW handshakes, AXI ownership lasts through all W
                // beats and the B response.  Cancelling mid-burst can leave
                // the DDR interconnect waiting forever after a geometry
                // error (notably one triggered by a timing violation).
                if ((state_r == STATE_COLLECT) ||
                    ((state_r == STATE_AW) && !aw_fire_w)) begin
                    state_r <= STATE_IDLE;
                    done_r <= 1'b1;
                    frame_end_pending_r <= 1'b0;
                    row_end_pending_r <= 1'b0;
                    abort_pending_r <= 1'b0;
                end else if (!((state_r == STATE_B) && b_fire_w)) begin
                    abort_pending_r <= 1'b1;
                end
            end
        end
    end

endmodule
