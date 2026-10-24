// ============================================================================
// File        : edrv32_hdmi_axi_reader_pageflip.v
// Description : Continuous HDMI framebuffer reader with frame-boundary flip.
// Notes       : Completed buffers are queued in the DDR clock domain. The old
//               front buffer is released only after the final read beat.
// ============================================================================

module edrv32_hdmi_axi_reader_pageflip #(
    parameter integer H_ACTIVE = 1280,
    parameter integer V_ACTIVE = 720,
    parameter integer BURST_BEATS = 16,
    parameter integer PREFILL_BEATS = 160,
    parameter integer TOKEN_WIDTH = 2,
    parameter integer DISPLAY_HANDSHAKE = 0,
    parameter [3:0] AXI_ID = 4'h1
) (
    input  wire         clk_i,
    input  wire         rst_n_i,
    input  wire         display_valid_i,
    output wire         display_ready_o,
    input  wire [TOKEN_WIDTH-1:0] display_buffer_i,
    input  wire [31:0]  display_base_i,

    output wire         release_valid_o,
    output wire [TOKEN_WIDTH-1:0] release_buffer_o,
    output wire         active_o,
    output wire [TOKEN_WIDTH-1:0] active_buffer_o,
    output wire         prefill_done_o,
    output wire [31:0]  frame_count_o,
    output wire         error_o,

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

    output wire [255:0] fifo_data_o,
    output wire         fifo_valid_o,
    input  wire         fifo_ready_i
);

    localparam integer FRAME_BEATS = (H_ACTIVE * V_ACTIVE) / 16;
    localparam integer BURST_BYTES = BURST_BEATS * 32;
    localparam [7:0] BURST_LAST = BURST_BEATS[7:0] - 8'd1;

    localparam [1:0] STATE_IDLE = 2'd0;
    localparam [1:0] STATE_AR   = 2'd1;
    localparam [1:0] STATE_R    = 2'd2;

    reg [1:0] state_r;
    reg [TOKEN_WIDTH-1:0] active_buffer_r;
    reg [31:0] active_base_r;
    reg [1:0] pending_count_r;
    reg [TOKEN_WIDTH-1:0] pending_buffer0_r;
    reg [TOKEN_WIDTH-1:0] pending_buffer1_r;
    reg [31:0] pending_base0_r;
    reg [31:0] pending_base1_r;
    reg release_valid_r;
    reg [TOKEN_WIDTH-1:0] release_buffer_r;
    reg [31:0] burst_addr_r;
    reg [7:0] beat_index_r;
    reg [31:0] frame_beat_r;
    reg [31:0] prefill_count_r;
    reg prefill_done_r;
    reg [31:0] frame_count_r;
    reg error_r;

    wire ar_fire_w = m_arvalid_o && m_arready_i;
    wire r_fire_w = m_rvalid_i && m_rready_o;
    wire expected_last_w = beat_index_r == BURST_LAST;
    wire frame_last_w = frame_beat_r == FRAME_BEATS - 1;
    wire dequeue_w = r_fire_w && m_rlast_i && frame_last_w &&
        (pending_count_r != 0);
    wire queue_room_w = (pending_count_r < 2'd2) || dequeue_w;
    wire accept_display_w = display_valid_i &&
        ((DISPLAY_HANDSHAKE == 0) || display_ready_o);
    wire enqueue_w = accept_display_w && (state_r != STATE_IDLE);

    assign display_ready_o = (state_r == STATE_IDLE) || queue_room_w;
    assign release_valid_o = release_valid_r;
    assign release_buffer_o = release_buffer_r;
    assign active_o = state_r != STATE_IDLE;
    assign active_buffer_o = active_buffer_r;
    assign prefill_done_o = prefill_done_r;
    assign frame_count_o = frame_count_r;
    assign error_o = error_r;

    assign m_arid_o = AXI_ID;
    assign m_araddr_o = burst_addr_r;
    assign m_arlen_o = BURST_LAST;
    assign m_arsize_o = 3'd5;
    assign m_arburst_o = 2'b01;
    assign m_arqos_o = 4'd12;
    assign m_arvalid_o = state_r == STATE_AR;
    assign fifo_data_o = m_rdata_i;
    assign fifo_valid_o = (state_r == STATE_R) && m_rvalid_i;
    assign m_rready_o = (state_r == STATE_R) && fifo_ready_i;

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            state_r <= STATE_IDLE;
            active_buffer_r <= {TOKEN_WIDTH{1'b0}};
            active_base_r <= 32'b0;
            pending_count_r <= 2'd0;
            pending_buffer0_r <= {TOKEN_WIDTH{1'b0}};
            pending_buffer1_r <= {TOKEN_WIDTH{1'b0}};
            pending_base0_r <= 32'b0;
            pending_base1_r <= 32'b0;
            release_valid_r <= 1'b0;
            release_buffer_r <= {TOKEN_WIDTH{1'b0}};
            burst_addr_r <= 32'b0;
            beat_index_r <= 8'b0;
            frame_beat_r <= 32'b0;
            prefill_count_r <= 32'b0;
            prefill_done_r <= 1'b0;
            frame_count_r <= 32'b0;
            error_r <= 1'b0;
        end else begin
            release_valid_r <= 1'b0;

            case ({enqueue_w, dequeue_w})
                2'b10: begin
                    if (pending_count_r == 0) begin
                        pending_buffer0_r <= display_buffer_i;
                        pending_base0_r <= display_base_i;
                        pending_count_r <= 2'd1;
                    end else if (pending_count_r == 1) begin
                        pending_buffer1_r <= display_buffer_i;
                        pending_base1_r <= display_base_i;
                        pending_count_r <= 2'd2;
                    end else begin
                        error_r <= 1'b1;
                    end
                end
                2'b01: begin
                    if (pending_count_r == 2) begin
                        pending_buffer0_r <= pending_buffer1_r;
                        pending_base0_r <= pending_base1_r;
                    end
                    pending_count_r <= pending_count_r - 1'b1;
                end
                2'b11: begin
                    if (pending_count_r == 1) begin
                        pending_buffer0_r <= display_buffer_i;
                        pending_base0_r <= display_base_i;
                    end else if (pending_count_r == 2) begin
                        pending_buffer0_r <= pending_buffer1_r;
                        pending_base0_r <= pending_base1_r;
                        pending_buffer1_r <= display_buffer_i;
                        pending_base1_r <= display_base_i;
                    end else begin
                        error_r <= 1'b1;
                    end
                end
                default: begin
                end
            endcase

            case (state_r)
                STATE_IDLE: begin
                    if (accept_display_w) begin
                        active_buffer_r <= display_buffer_i;
                        active_base_r <= display_base_i;
                        burst_addr_r <= display_base_i;
                        beat_index_r <= 8'b0;
                        frame_beat_r <= 32'b0;
                        prefill_count_r <= 32'b0;
                        prefill_done_r <= 1'b0;
                        state_r <= STATE_AR;
                    end
                end

                STATE_AR: begin
                    if (ar_fire_w) begin
                        beat_index_r <= 8'b0;
                        state_r <= STATE_R;
                    end
                end

                STATE_R: begin
                    if (r_fire_w) begin
                        if ((m_rid_i != AXI_ID) || (m_rresp_i != 2'b00) ||
                            (m_rlast_i != expected_last_w))
                            error_r <= 1'b1;

                        if (!prefill_done_r) begin
                            if (prefill_count_r == PREFILL_BEATS - 1)
                                prefill_done_r <= 1'b1;
                            else
                                prefill_count_r <= prefill_count_r + 1'b1;
                        end

                        if (frame_last_w) begin
                            frame_beat_r <= 32'b0;
                            frame_count_r <= frame_count_r + 1'b1;
                        end else begin
                            frame_beat_r <= frame_beat_r + 1'b1;
                        end

                        if (m_rlast_i) begin
                            beat_index_r <= 8'b0;
                            state_r <= STATE_AR;
                            if (frame_last_w) begin
                                if (pending_count_r != 0) begin
                                    release_valid_r <= 1'b1;
                                    release_buffer_r <= active_buffer_r;
                                    active_buffer_r <= pending_buffer0_r;
                                    active_base_r <= pending_base0_r;
                                    burst_addr_r <= pending_base0_r;
                                end else begin
                                    burst_addr_r <= active_base_r;
                                end
                            end else begin
                                burst_addr_r <= burst_addr_r + BURST_BYTES;
                            end
                        end else begin
                            beat_index_r <= beat_index_r + 1'b1;
                        end
                    end
                end

                default: begin
                    state_r <= STATE_IDLE;
                    error_r <= 1'b1;
                end
            endcase
        end
    end

    generate
        if (((H_ACTIVE * V_ACTIVE) % 16) != 0 ||
            (FRAME_BEATS % BURST_BEATS) != 0 ||
            PREFILL_BEATS < 1 || BURST_BEATS < 1 ||
            BURST_BEATS > 16) begin : gen_bad_geometry
            edrv32_hdmi_pageflip_geometry_must_use_full_bursts
                u_static_assert ();
        end
    endgenerate

endmodule
