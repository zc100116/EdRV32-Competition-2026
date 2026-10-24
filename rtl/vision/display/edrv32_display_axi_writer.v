// ============================================================================
// File        : edrv32_display_axi_writer.v
// Description : Packed video stream to triple-buffered DDR display surfaces.
// Notes       : A buffer is reused only after the HDMI reader releases it.
//               Complete 1..16-beat bursts are staged before AW, so a slow
//               camera stream never owns the shared AXI W channel mid-burst.
// ============================================================================

module edrv32_display_axi_writer #(
    parameter integer H_ACTIVE = 1280,
    parameter integer V_ACTIVE = 720,
    parameter integer BURST_BEATS = 16,
    parameter [31:0] FRAME_BASE0 = 32'h0180_0000,
    parameter [31:0] FRAME_BASE1 = 32'h01a0_0000,
    parameter [31:0] FRAME_BASE2 = 32'h01c0_0000,
    parameter [3:0] AXI_ID = 4'h0
) (
    input  wire         clk_i,
    input  wire         rst_n_i,

    input  wire [257:0] stream_data_i,
    input  wire         stream_valid_i,
    output wire         stream_ready_o,

    input  wire         release_valid_i,
    input  wire [1:0]   release_buffer_i,
    output wire         completed_valid_o,
    output wire [1:0]   completed_buffer_o,
    output wire [31:0]  completed_base_o,
    output wire [31:0]  frame_count_o,
    output wire [31:0]  dropped_frame_count_o,
    output wire         active_o,
    output wire         error_o,

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

    localparam integer FRAME_BEATS = (H_ACTIVE * V_ACTIVE) / 16;
    localparam integer BURST_BYTES = BURST_BEATS * 32;

    localparam [2:0] STATE_SYNC = 3'd0;
    localparam [2:0] STATE_FILL = 3'd1;
    localparam [2:0] STATE_AW   = 3'd2;
    localparam [2:0] STATE_W    = 3'd3;
    localparam [2:0] STATE_B    = 3'd4;

    reg [2:0] state_r;
    reg [2:0] free_buffers_r;
    reg [1:0] next_buffer_r;
    reg [1:0] write_buffer_r;
    reg completed_valid_r;
    reg [1:0] completed_buffer_r;
    reg [31:0] completed_base_r;
    reg [31:0] frame_count_r;
    reg [31:0] dropped_frame_count_r;
    reg [31:0] frame_beat_r;
    reg [7:0] burst_beat_r;
    reg [7:0] send_index_r;
    reg [255:0] burst_data_r [0:BURST_BEATS-1];
    reg [255:0] send_data_r;
    reg [31:0] burst_addr_r;
    reg frame_end_pending_r;
    reg frame_bad_r;
    reg error_r;

    reg [1:0] selected_buffer_w;
    always @(*) begin
        selected_buffer_w = 2'd0;
        case (next_buffer_r)
            2'd0: begin
                if (free_buffers_r[0])
                    selected_buffer_w = 2'd0;
                else if (free_buffers_r[1])
                    selected_buffer_w = 2'd1;
                else
                    selected_buffer_w = 2'd2;
            end
            2'd1: begin
                if (free_buffers_r[1])
                    selected_buffer_w = 2'd1;
                else if (free_buffers_r[2])
                    selected_buffer_w = 2'd2;
                else
                    selected_buffer_w = 2'd0;
            end
            default: begin
                if (free_buffers_r[2])
                    selected_buffer_w = 2'd2;
                else if (free_buffers_r[0])
                    selected_buffer_w = 2'd0;
                else
                    selected_buffer_w = 2'd1;
            end
        endcase
    end

    wire any_free_w = |free_buffers_r;
    wire stream_sof_w = stream_data_i[257];
    wire stream_eof_w = stream_data_i[256];
    wire expected_sof_w = frame_beat_r == 0;
    wire expected_eof_w = frame_beat_r == FRAME_BEATS - 1;
    wire stream_fire_w = stream_valid_i && stream_ready_o;
    wire aw_fire_w = m_awvalid_o && m_awready_i;
    wire w_fire_w = m_wvalid_o && m_wready_i;
    wire b_fire_w = m_bvalid_i && m_bready_o;
    wire burst_last_w = burst_beat_r == BURST_BEATS - 1;
    wire send_last_w = send_index_r == BURST_BEATS - 1;
    wire [31:0] selected_base_w = selected_buffer_w == 2'd0 ?
        FRAME_BASE0 : (selected_buffer_w == 2'd1 ? FRAME_BASE1 : FRAME_BASE2);
    wire [31:0] write_base_w = write_buffer_r == 2'd0 ?
        FRAME_BASE0 : (write_buffer_r == 2'd1 ? FRAME_BASE1 : FRAME_BASE2);

    assign stream_ready_o = ((state_r == STATE_SYNC) &&
        ((!any_free_w) || !stream_sof_w)) ||
        (state_r == STATE_FILL);
    assign completed_valid_o = completed_valid_r;
    assign completed_buffer_o = completed_buffer_r;
    assign completed_base_o = completed_base_r;
    assign frame_count_o = frame_count_r;
    assign dropped_frame_count_o = dropped_frame_count_r;
    assign active_o = state_r != STATE_SYNC;
    assign error_o = error_r;

    assign m_awid_o = AXI_ID;
    assign m_awaddr_o = burst_addr_r;
    assign m_awlen_o = BURST_BEATS - 1;
    assign m_awsize_o = 3'd5;
    assign m_awburst_o = 2'b01;
    assign m_awqos_o = 4'd8;
    assign m_awvalid_o = state_r == STATE_AW;
    assign m_wdata_o = send_data_r;
    assign m_wstrb_o = 32'hffff_ffff;
    assign m_wlast_o = send_last_w;
    assign m_wvalid_o = state_r == STATE_W;
    assign m_bready_o = state_r == STATE_B;

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            state_r <= STATE_SYNC;
            free_buffers_r <= 3'b111;
            next_buffer_r <= 2'd0;
            write_buffer_r <= 2'd0;
            completed_valid_r <= 1'b0;
            completed_buffer_r <= 2'd0;
            completed_base_r <= FRAME_BASE0;
            frame_count_r <= 32'b0;
            dropped_frame_count_r <= 32'b0;
            frame_beat_r <= 32'b0;
            burst_beat_r <= 8'b0;
            send_index_r <= 8'b0;
            burst_addr_r <= FRAME_BASE0;
            frame_end_pending_r <= 1'b0;
            frame_bad_r <= 1'b0;
            error_r <= 1'b0;
        end else begin
            completed_valid_r <= 1'b0;

            if (release_valid_i) begin
                if (release_buffer_i < 3)
                    free_buffers_r[release_buffer_i] <= 1'b1;
                else
                    error_r <= 1'b1;
            end

            case (state_r)
                STATE_SYNC: begin
                    frame_beat_r <= 32'b0;
                    burst_beat_r <= 8'b0;
                    frame_end_pending_r <= 1'b0;
                    frame_bad_r <= 1'b0;
                    if (stream_valid_i && stream_sof_w) begin
                        if (any_free_w) begin
                            write_buffer_r <= selected_buffer_w;
                            free_buffers_r[selected_buffer_w] <= 1'b0;
                            burst_addr_r <= selected_base_w;
                            if (selected_buffer_w == 2'd2)
                                next_buffer_r <= 2'd0;
                            else
                                next_buffer_r <= selected_buffer_w + 1'b1;
                            state_r <= STATE_FILL;
                        end else if (stream_fire_w) begin
                            dropped_frame_count_r <=
                                dropped_frame_count_r + 1'b1;
                        end
                    end
                end

                STATE_FILL: begin
                    if (stream_fire_w) begin
                        burst_data_r[burst_beat_r] <= stream_data_i[255:0];
                        if ((stream_sof_w != expected_sof_w) ||
                            (stream_eof_w != expected_eof_w)) begin
                            frame_bad_r <= 1'b1;
                            error_r <= 1'b1;
                        end

                        if (expected_eof_w)
                            frame_beat_r <= 32'b0;
                        else
                            frame_beat_r <= frame_beat_r + 1'b1;

                        if (burst_last_w) begin
                            frame_end_pending_r <= expected_eof_w;
                            send_index_r <= 8'b0;
                            state_r <= STATE_AW;
                        end else begin
                            burst_beat_r <= burst_beat_r + 1'b1;
                        end
                    end
                end

                STATE_AW: begin
                    if (aw_fire_w) begin
                        send_index_r <= 8'b0;
                        send_data_r <= burst_data_r[0];
                        state_r <= STATE_W;
                    end
                end

                STATE_W: begin
                    if (w_fire_w) begin
                        if (send_last_w) begin
                            state_r <= STATE_B;
                        end else begin
                            send_index_r <= send_index_r + 1'b1;
                            send_data_r <= burst_data_r[send_index_r + 1'b1];
                        end
                    end
                end

                STATE_B: begin
                    if (b_fire_w) begin
                        if ((m_bid_i != AXI_ID) || (m_bresp_i != 2'b00)) begin
                            error_r <= 1'b1;
                            free_buffers_r[write_buffer_r] <= 1'b1;
                            state_r <= STATE_SYNC;
                        end else if (frame_end_pending_r) begin
                            if (frame_bad_r) begin
                                free_buffers_r[write_buffer_r] <= 1'b1;
                                dropped_frame_count_r <=
                                    dropped_frame_count_r + 1'b1;
                            end else begin
                                completed_valid_r <= 1'b1;
                                completed_buffer_r <= write_buffer_r;
                                completed_base_r <= write_base_w;
                                frame_count_r <= frame_count_r + 1'b1;
                            end
                            state_r <= STATE_SYNC;
                        end else begin
                            burst_addr_r <= burst_addr_r + BURST_BYTES;
                            burst_beat_r <= 8'b0;
                            state_r <= STATE_FILL;
                        end
                    end
                end

                default: begin
                    state_r <= STATE_SYNC;
                    error_r <= 1'b1;
                end
            endcase
        end
    end

    generate
        if (((H_ACTIVE * V_ACTIVE) % 16) != 0 ||
            (FRAME_BEATS % BURST_BEATS) != 0 ||
            BURST_BEATS < 1 || BURST_BEATS > 16) begin : gen_bad_geometry
            edrv32_display_writer_geometry_must_use_full_bursts
                u_static_assert ();
        end
    endgenerate

endmodule
