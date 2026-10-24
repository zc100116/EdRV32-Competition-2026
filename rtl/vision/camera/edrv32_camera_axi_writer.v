// ============================================================================
// File        : edrv32_camera_axi_writer.v
// Description : Streams one camera into alternating DDR capture buffers.
// Notes       : Input words contain {sof,eof,RGB565 pixels}. A completed buffer
//               is published only after the final AXI write response.
// ============================================================================

module edrv32_camera_axi_writer #(
    parameter integer H_ACTIVE = 1280,
    parameter integer V_ACTIVE = 720,
    parameter integer BURST_BEATS = 16,
    parameter [31:0] FRAME_BASE0 = 32'h0100_0000,
    parameter [31:0] FRAME_BASE1 = 32'h0120_0000,
    parameter [3:0] AXI_ID = 4'h0
) (
    input  wire         clk_i,
    input  wire         rst_n_i,

    input  wire [257:0] stream_data_i,
    input  wire         stream_valid_i,
    output wire         stream_ready_o,

    output wire         completed_valid_o,
    output wire         completed_buffer_o,
    output wire [31:0]  completed_base_o,
    output wire [31:0]  frame_count_o,
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
    localparam [2:0] STATE_AW   = 3'd1;
    localparam [2:0] STATE_W    = 3'd2;
    localparam [2:0] STATE_B    = 3'd3;

    reg [2:0] state_r;
    reg write_buffer_r;
    reg completed_valid_r;
    reg completed_buffer_r;
    reg [31:0] completed_base_r;
    reg [31:0] frame_count_r;
    reg [31:0] frame_beat_r;
    reg [7:0] burst_beat_r;
    reg [31:0] burst_addr_r;
    reg frame_end_pending_r;
    reg error_r;

    wire stream_sof_w = stream_data_i[257];
    wire stream_eof_w = stream_data_i[256];
    wire expected_sof_w = frame_beat_r == 0;
    wire expected_eof_w = frame_beat_r == FRAME_BEATS - 1;
    wire stream_fire_w = stream_valid_i && stream_ready_o;
    wire aw_fire_w = m_awvalid_o && m_awready_i;
    wire b_fire_w = m_bvalid_i && m_bready_o;
    wire burst_last_w = burst_beat_r == BURST_BEATS - 1;
    wire [31:0] selected_base_w = write_buffer_r ?
        FRAME_BASE1 : FRAME_BASE0;

    // Discard stale words while searching, but retain the SOF word until its
    // AW command has been accepted and the W channel owns the burst.
    assign stream_ready_o = ((state_r == STATE_SYNC) && stream_valid_i &&
        !stream_sof_w) || ((state_r == STATE_W) && m_wready_i);
    assign completed_valid_o = completed_valid_r;
    assign completed_buffer_o = completed_buffer_r;
    assign completed_base_o = completed_base_r;
    assign frame_count_o = frame_count_r;
    assign active_o = state_r != STATE_SYNC;
    assign error_o = error_r;

    assign m_awid_o = AXI_ID;
    assign m_awaddr_o = burst_addr_r;
    assign m_awlen_o = BURST_BEATS - 1;
    assign m_awsize_o = 3'd5;
    assign m_awburst_o = 2'b01;
    assign m_awqos_o = 4'd5;
    assign m_awvalid_o = state_r == STATE_AW;
    assign m_wdata_o = stream_data_i[255:0];
    assign m_wstrb_o = 32'hffff_ffff;
    assign m_wlast_o = burst_last_w;
    assign m_wvalid_o = (state_r == STATE_W) && stream_valid_i;
    assign m_bready_o = state_r == STATE_B;

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            state_r <= STATE_SYNC;
            write_buffer_r <= 1'b0;
            completed_valid_r <= 1'b0;
            completed_buffer_r <= 1'b0;
            completed_base_r <= FRAME_BASE0;
            frame_count_r <= 32'b0;
            frame_beat_r <= 32'b0;
            burst_beat_r <= 8'b0;
            burst_addr_r <= FRAME_BASE0;
            frame_end_pending_r <= 1'b0;
            error_r <= 1'b0;
        end else begin
            case (state_r)
                STATE_SYNC: begin
                    frame_beat_r <= 32'b0;
                    burst_beat_r <= 8'b0;
                    frame_end_pending_r <= 1'b0;
                    if (stream_valid_i && stream_sof_w) begin
                        burst_addr_r <= selected_base_w;
                        state_r <= STATE_AW;
                    end
                end

                STATE_AW: begin
                    if (aw_fire_w) begin
                        burst_beat_r <= 8'b0;
                        state_r <= STATE_W;
                    end
                end

                STATE_W: begin
                    if (stream_fire_w) begin
                        if ((stream_sof_w != expected_sof_w) ||
                            (stream_eof_w != expected_eof_w))
                            error_r <= 1'b1;

                        if (expected_eof_w)
                            frame_beat_r <= 32'b0;
                        else
                            frame_beat_r <= frame_beat_r + 1'b1;

                        if (burst_last_w) begin
                            frame_end_pending_r <= expected_eof_w;
                            state_r <= STATE_B;
                        end else begin
                            burst_beat_r <= burst_beat_r + 1'b1;
                        end
                    end
                end

                STATE_B: begin
                    if (b_fire_w) begin
                        if ((m_bid_i != AXI_ID) || (m_bresp_i != 2'b00)) begin
                            error_r <= 1'b1;
                            state_r <= STATE_SYNC;
                        end else if (frame_end_pending_r) begin
                            completed_valid_r <= 1'b1;
                            completed_buffer_r <= write_buffer_r;
                            completed_base_r <= selected_base_w;
                            frame_count_r <= frame_count_r + 1'b1;
                            write_buffer_r <= ~write_buffer_r;
                            state_r <= STATE_SYNC;
                        end else begin
                            burst_addr_r <= burst_addr_r + BURST_BYTES;
                            state_r <= STATE_AW;
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
            edrv32_camera_writer_geometry_must_use_full_bursts
                u_static_assert ();
        end
    endgenerate

endmodule
