// ============================================================================
// File        : edrv32_colorbar_axi_writer.v
// Description : One-shot RGB565 color-bar writer for a 256-bit AXI framebuffer.
// Notes       : The configured geometry must contain an integer number of
//               full 256-bit beats and fixed-size bursts.
// ============================================================================

module edrv32_colorbar_axi_writer #(
    parameter integer H_ACTIVE = 1280,
    parameter integer V_ACTIVE = 720,
    parameter integer BURST_BEATS = 16,
    parameter [31:0] FRAME_BASE = 32'h0100_0000,
    parameter [3:0] AXI_ID = 4'h0
) (
    input  wire         clk_i,
    input  wire         rst_n_i,

    input  wire         start_i,
    output wire         busy_o,
    output wire         done_o,
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

    localparam integer PIXELS_PER_BEAT = 16;
    localparam integer BEATS_PER_FRAME =
        (H_ACTIVE * V_ACTIVE) / PIXELS_PER_BEAT;
    localparam integer BURST_BYTES = BURST_BEATS * 32;

    localparam [2:0] STATE_IDLE = 3'd0;
    localparam [2:0] STATE_AW   = 3'd1;
    localparam [2:0] STATE_W    = 3'd2;
    localparam [2:0] STATE_B    = 3'd3;
    localparam [2:0] STATE_DONE = 3'd4;

    reg [2:0] state_r;
    reg [31:0] burst_addr_r;
    reg [7:0] beat_index_r;
    reg [15:0] pixel_x_r;
    reg [15:0] pixel_y_r;
    reg frame_last_pending_r;
    reg done_r;
    reg error_r;

    function [15:0] colorbar_pixel;
        input [15:0] x;
        begin
            if (x < (H_ACTIVE / 8))
                colorbar_pixel = 16'hffff;
            else if (x < ((H_ACTIVE * 2) / 8))
                colorbar_pixel = 16'hffe0;
            else if (x < ((H_ACTIVE * 3) / 8))
                colorbar_pixel = 16'h07ff;
            else if (x < ((H_ACTIVE * 4) / 8))
                colorbar_pixel = 16'h07e0;
            else if (x < ((H_ACTIVE * 5) / 8))
                colorbar_pixel = 16'hf81f;
            else if (x < ((H_ACTIVE * 6) / 8))
                colorbar_pixel = 16'hf800;
            else if (x < ((H_ACTIVE * 7) / 8))
                colorbar_pixel = 16'h001f;
            else
                colorbar_pixel = 16'h0000;
        end
    endfunction

    reg [255:0] write_data_w;
    integer lane_i;
    always @(*) begin
        write_data_w = 256'b0;
        for (lane_i = 0; lane_i < PIXELS_PER_BEAT;
             lane_i = lane_i + 1) begin
            write_data_w[lane_i*16 +: 16] =
                colorbar_pixel(pixel_x_r + lane_i[15:0]);
        end
    end

    wire aw_fire_w = m_awvalid_o && m_awready_i;
    wire w_fire_w = m_wvalid_o && m_wready_i;
    wire b_fire_w = m_bvalid_i && m_bready_o;
    wire beat_is_last_w = beat_index_r == (BURST_BEATS - 1);
    wire line_is_last_beat_w =
        pixel_x_r == (H_ACTIVE - PIXELS_PER_BEAT);
    wire frame_is_last_beat_w = line_is_last_beat_w &&
        (pixel_y_r == (V_ACTIVE - 1));

    assign busy_o = (state_r != STATE_IDLE) && (state_r != STATE_DONE);
    assign done_o = done_r;
    assign error_o = error_r;

    assign m_awid_o = AXI_ID;
    assign m_awaddr_o = burst_addr_r;
    assign m_awlen_o = BURST_BEATS - 1;
    assign m_awsize_o = 3'd5;
    assign m_awburst_o = 2'b01;
    assign m_awqos_o = 4'd2;
    assign m_awvalid_o = state_r == STATE_AW;

    assign m_wdata_o = write_data_w;
    assign m_wstrb_o = 32'hffff_ffff;
    assign m_wlast_o = beat_is_last_w;
    assign m_wvalid_o = state_r == STATE_W;

    assign m_bready_o = state_r == STATE_B;

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            state_r <= STATE_IDLE;
            burst_addr_r <= FRAME_BASE;
            beat_index_r <= 8'b0;
            pixel_x_r <= 16'b0;
            pixel_y_r <= 16'b0;
            frame_last_pending_r <= 1'b0;
            done_r <= 1'b0;
            error_r <= 1'b0;
        end else begin
            case (state_r)
                STATE_IDLE: begin
                    if (start_i) begin
                        state_r <= STATE_AW;
                        burst_addr_r <= FRAME_BASE;
                        beat_index_r <= 8'b0;
                        pixel_x_r <= 16'b0;
                        pixel_y_r <= 16'b0;
                        frame_last_pending_r <= 1'b0;
                        done_r <= 1'b0;
                        error_r <= 1'b0;
                    end
                end

                STATE_AW: begin
                    if (aw_fire_w) begin
                        state_r <= STATE_W;
                        beat_index_r <= 8'b0;
                    end
                end

                STATE_W: begin
                    if (w_fire_w) begin
                        if (line_is_last_beat_w) begin
                            pixel_x_r <= 16'b0;
                            if (pixel_y_r == (V_ACTIVE - 1))
                                pixel_y_r <= 16'b0;
                            else
                                pixel_y_r <= pixel_y_r + 1'b1;
                        end else begin
                            pixel_x_r <= pixel_x_r + PIXELS_PER_BEAT;
                        end

                        if (beat_is_last_w) begin
                            state_r <= STATE_B;
                            frame_last_pending_r <= frame_is_last_beat_w;
                        end else begin
                            beat_index_r <= beat_index_r + 1'b1;
                        end
                    end
                end

                STATE_B: begin
                    if (b_fire_w) begin
                        if ((m_bid_i != AXI_ID) || (m_bresp_i != 2'b00)) begin
                            state_r <= STATE_DONE;
                            done_r <= 1'b1;
                            error_r <= 1'b1;
                        end else if (frame_last_pending_r) begin
                            state_r <= STATE_DONE;
                            done_r <= 1'b1;
                        end else begin
                            state_r <= STATE_AW;
                            burst_addr_r <= burst_addr_r + BURST_BYTES;
                            frame_last_pending_r <= 1'b0;
                        end
                    end
                end

                default: begin
                    state_r <= STATE_DONE;
                end
            endcase
        end
    end

    generate
        if (((H_ACTIVE * V_ACTIVE) % PIXELS_PER_BEAT) != 0 ||
            (BEATS_PER_FRAME % BURST_BEATS) != 0 ||
            BURST_BEATS < 1 || BURST_BEATS > 16) begin : gen_bad_geometry
            edrv32_colorbar_geometry_must_use_full_256bit_bursts
                u_static_assert ();
        end
    endgenerate

endmodule
