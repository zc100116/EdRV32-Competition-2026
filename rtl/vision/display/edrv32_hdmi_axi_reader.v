// ============================================================================
// File        : edrv32_hdmi_axi_reader.v
// Description : Continuous RGB565 framebuffer reader for a 256-bit AXI port.
// Notes       : One burst is outstanding at a time.  The downstream video FIFO
//               supplies AXI backpressure without dropping read data.
// ============================================================================

module edrv32_hdmi_axi_reader #(
    parameter integer H_ACTIVE = 1280,
    parameter integer V_ACTIVE = 720,
    parameter integer BURST_BEATS = 16,
    parameter integer PREFILL_BEATS = 160,
    parameter [31:0] FRAME_BASE = 32'h0100_0000,
    parameter [3:0] AXI_ID = 4'h0
) (
    input  wire         clk_i,
    input  wire         rst_n_i,

    input  wire         start_i,
    output wire         active_o,
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

    localparam integer PIXELS_PER_BEAT = 16;
    localparam integer FRAME_BEATS =
        (H_ACTIVE * V_ACTIVE) / PIXELS_PER_BEAT;
    localparam integer BURST_BYTES = BURST_BEATS * 32;

    localparam [1:0] STATE_IDLE = 2'd0;
    localparam [1:0] STATE_AR   = 2'd1;
    localparam [1:0] STATE_R    = 2'd2;

    reg [1:0] state_r;
    reg [31:0] burst_addr_r;
    reg [7:0] beat_index_r;
    reg [31:0] frame_beat_r;
    reg [31:0] prefill_count_r;
    reg prefill_done_r;
    reg [31:0] frame_count_r;
    reg error_r;

    wire ar_fire_w = m_arvalid_o && m_arready_i;
    wire r_fire_w = m_rvalid_i && m_rready_o;
    wire expected_last_w = beat_index_r == (BURST_BEATS - 1);
    wire frame_last_w = frame_beat_r == (FRAME_BEATS - 1);

    assign active_o = state_r != STATE_IDLE;
    assign prefill_done_o = prefill_done_r;
    assign frame_count_o = frame_count_r;
    assign error_o = error_r;

    assign m_arid_o = AXI_ID;
    assign m_araddr_o = burst_addr_r;
    assign m_arlen_o = BURST_BEATS - 1;
    assign m_arsize_o = 3'd5;
    assign m_arburst_o = 2'b01;
    assign m_arqos_o = 4'd8;
    assign m_arvalid_o = state_r == STATE_AR;

    assign fifo_data_o = m_rdata_i;
    assign fifo_valid_o = (state_r == STATE_R) && m_rvalid_i;
    assign m_rready_o = (state_r == STATE_R) && fifo_ready_i;

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            state_r <= STATE_IDLE;
            burst_addr_r <= FRAME_BASE;
            beat_index_r <= 8'b0;
            frame_beat_r <= 32'b0;
            prefill_count_r <= 32'b0;
            prefill_done_r <= 1'b0;
            frame_count_r <= 32'b0;
            error_r <= 1'b0;
        end else begin
            case (state_r)
                STATE_IDLE: begin
                    if (start_i) begin
                        state_r <= STATE_AR;
                        burst_addr_r <= FRAME_BASE;
                        beat_index_r <= 8'b0;
                        frame_beat_r <= 32'b0;
                        prefill_count_r <= 32'b0;
                        prefill_done_r <= 1'b0;
                        frame_count_r <= 32'b0;
                        error_r <= 1'b0;
                    end
                end

                STATE_AR: begin
                    if (ar_fire_w) begin
                        state_r <= STATE_R;
                        beat_index_r <= 8'b0;
                    end
                end

                STATE_R: begin
                    if (r_fire_w) begin
                        if ((m_rid_i != AXI_ID) || (m_rresp_i != 2'b00) ||
                            (m_rlast_i != expected_last_w))
                            error_r <= 1'b1;

                        if (!prefill_done_r) begin
                            if (prefill_count_r == (PREFILL_BEATS - 1))
                                prefill_done_r <= 1'b1;
                            else
                                prefill_count_r <= prefill_count_r + 1'b1;
                        end

                        if (frame_last_w)
                            frame_beat_r <= 32'b0;
                        else
                            frame_beat_r <= frame_beat_r + 1'b1;

                        if (m_rlast_i) begin
                            state_r <= STATE_AR;
                            beat_index_r <= 8'b0;
                            if (frame_last_w) begin
                                burst_addr_r <= FRAME_BASE;
                                frame_count_r <= frame_count_r + 1'b1;
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
                end
            endcase
        end
    end

    generate
        if (((H_ACTIVE * V_ACTIVE) % PIXELS_PER_BEAT) != 0 ||
            (FRAME_BEATS % BURST_BEATS) != 0 ||
            PREFILL_BEATS < 1 || BURST_BEATS < 1 ||
            BURST_BEATS > 16) begin : gen_bad_geometry
            edrv32_hdmi_reader_geometry_must_use_full_256bit_bursts
                u_static_assert ();
        end
    endgenerate

endmodule
