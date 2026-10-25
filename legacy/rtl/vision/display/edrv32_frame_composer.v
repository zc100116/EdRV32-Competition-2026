// ============================================================================
// File        : edrv32_frame_composer.v
// Description : Copies the selected camera frame into a display back buffer.
// Notes       : Selection is sampled only when a new source frame is accepted.
//               The first version performs a 1:1 RGB565 frame copy; scaling,
//               rotation and overlays attach at this ownership boundary.
// ============================================================================

module edrv32_frame_composer #(
    parameter integer H_ACTIVE = 1280,
    parameter integer V_ACTIVE = 720,
    parameter integer BURST_BEATS = 16,
    parameter [31:0] DISPLAY_BASE0 = 32'h0180_0000,
    parameter [31:0] DISPLAY_BASE1 = 32'h01a0_0000,
    parameter [3:0] AXI_ID = 4'h2
) (
    input  wire         clk_i,
    input  wire         rst_n_i,
    input  wire         select_i,
    input  wire         cam0_valid_i,
    input  wire [31:0]  cam0_base_i,
    input  wire [31:0]  cam0_frame_count_i,
    input  wire         cam1_valid_i,
    input  wire [31:0]  cam1_base_i,
    input  wire [31:0]  cam1_frame_count_i,

    output wire         display_valid_o,
    output wire         display_buffer_o,
    output wire [31:0]  display_base_o,
    output wire [31:0]  display_frame_count_o,
    output wire         active_camera_o,
    output wire         busy_o,
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
    output wire         m_bready_o,

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
    output wire         m_rready_o
);

    localparam integer FRAME_BEATS = (H_ACTIVE * V_ACTIVE) / 16;
    localparam integer BURST_BYTES = BURST_BEATS * 32;

    localparam [3:0] STATE_IDLE = 4'd0;
    localparam [3:0] STATE_AR   = 4'd1;
    localparam [3:0] STATE_R    = 4'd2;
    localparam [3:0] STATE_AW   = 4'd3;
    localparam [3:0] STATE_W    = 4'd4;
    localparam [3:0] STATE_B    = 4'd5;

    reg [3:0] state_r;
    reg active_camera_r;
    reg display_buffer_r;
    reg display_valid_r;
    reg completed_buffer_r;
    reg [31:0] completed_base_r;
    reg [31:0] display_frame_count_r;
    reg [31:0] source_frame_count_r;
    reg [31:0] last_cam0_count_r;
    reg [31:0] last_cam1_count_r;
    reg [31:0] read_addr_r;
    reg [31:0] write_addr_r;
    reg [31:0] display_target_base_r;
    reg [31:0] frame_beat_r;
    reg [7:0] read_beat_r;
    reg [7:0] write_beat_r;
    reg error_r;

    wire selected_valid_w = select_i ? cam1_valid_i : cam0_valid_i;
    wire [31:0] selected_base_w = select_i ? cam1_base_i : cam0_base_i;
    wire [31:0] selected_count_w = select_i ?
        cam1_frame_count_i : cam0_frame_count_i;
    wire [31:0] selected_last_count_w = select_i ?
        last_cam1_count_r : last_cam0_count_r;
    wire selected_new_w = selected_valid_w &&
        (selected_count_w != selected_last_count_w);
    wire [31:0] next_display_base_w = display_buffer_r ?
        DISPLAY_BASE0 : DISPLAY_BASE1;

    wire [255:0] fifo_rdata_w;
    wire fifo_full_w;
    wire fifo_empty_w;
    wire [5:0] unused_fifo_count_w;
    wire fifo_push_w = (state_r == STATE_R) && m_rvalid_i && m_rready_o;
    wire fifo_pop_w = (state_r == STATE_W) && m_wvalid_o && m_wready_i;

    sync_fifo #(
        .WIDTH (256),
        .DEPTH (32)
    ) u_copy_fifo (
        .clk     (clk_i),
        .rst_n   (rst_n_i),
        .flush_i (state_r == STATE_IDLE),
        .push_i  (fifo_push_w),
        .wdata_i (m_rdata_i),
        .pop_i   (fifo_pop_w),
        .rdata_o (fifo_rdata_w),
        .full_o  (fifo_full_w),
        .empty_o (fifo_empty_w),
        .count_o (unused_fifo_count_w)
    );

    assign display_valid_o = display_valid_r;
    assign display_buffer_o = completed_buffer_r;
    assign display_base_o = completed_base_r;
    assign display_frame_count_o = display_frame_count_r;
    assign active_camera_o = active_camera_r;
    assign busy_o = state_r != STATE_IDLE;
    assign error_o = error_r;

    assign m_arid_o = AXI_ID;
    assign m_araddr_o = read_addr_r;
    assign m_arlen_o = BURST_BEATS - 1;
    assign m_arsize_o = 3'd5;
    assign m_arburst_o = 2'b01;
    assign m_arqos_o = 4'd6;
    assign m_arvalid_o = state_r == STATE_AR;
    assign m_rready_o = (state_r == STATE_R) && !fifo_full_w;

    assign m_awid_o = AXI_ID;
    assign m_awaddr_o = write_addr_r;
    assign m_awlen_o = BURST_BEATS - 1;
    assign m_awsize_o = 3'd5;
    assign m_awburst_o = 2'b01;
    assign m_awqos_o = 4'd6;
    assign m_awvalid_o = state_r == STATE_AW;
    assign m_wdata_o = fifo_rdata_w;
    assign m_wstrb_o = 32'hffff_ffff;
    assign m_wlast_o = write_beat_r == BURST_BEATS - 1;
    assign m_wvalid_o = (state_r == STATE_W) && !fifo_empty_w;
    assign m_bready_o = state_r == STATE_B;

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            state_r <= STATE_IDLE;
            active_camera_r <= 1'b0;
            display_buffer_r <= 1'b1;
            display_valid_r <= 1'b0;
            completed_buffer_r <= 1'b0;
            completed_base_r <= DISPLAY_BASE0;
            display_frame_count_r <= 32'b0;
            source_frame_count_r <= 32'b0;
            last_cam0_count_r <= 32'b0;
            last_cam1_count_r <= 32'b0;
            read_addr_r <= 32'b0;
            write_addr_r <= DISPLAY_BASE0;
            display_target_base_r <= DISPLAY_BASE0;
            frame_beat_r <= 32'b0;
            read_beat_r <= 8'b0;
            write_beat_r <= 8'b0;
            error_r <= 1'b0;
        end else begin
            case (state_r)
                STATE_IDLE: begin
                    frame_beat_r <= 32'b0;
                    if (selected_new_w) begin
                        active_camera_r <= select_i;
                        source_frame_count_r <= selected_count_w;
                        read_addr_r <= selected_base_w;
                        write_addr_r <= next_display_base_w;
                        display_target_base_r <= next_display_base_w;
                        state_r <= STATE_AR;
                    end
                end

                STATE_AR: begin
                    if (m_arvalid_o && m_arready_i) begin
                        read_beat_r <= 8'b0;
                        state_r <= STATE_R;
                    end
                end

                STATE_R: begin
                    if (fifo_push_w) begin
                        if ((m_rid_i != AXI_ID) || (m_rresp_i != 2'b00) ||
                            (m_rlast_i != (read_beat_r == BURST_BEATS - 1)))
                            error_r <= 1'b1;
                        if (read_beat_r == BURST_BEATS - 1) begin
                            write_beat_r <= 8'b0;
                            state_r <= STATE_AW;
                        end else begin
                            read_beat_r <= read_beat_r + 1'b1;
                        end
                    end
                end

                STATE_AW: begin
                    if (m_awvalid_o && m_awready_i)
                        state_r <= STATE_W;
                end

                STATE_W: begin
                    if (fifo_pop_w) begin
                        if (write_beat_r == BURST_BEATS - 1)
                            state_r <= STATE_B;
                        else
                            write_beat_r <= write_beat_r + 1'b1;
                    end
                end

                STATE_B: begin
                    if (m_bvalid_i && m_bready_o) begin
                        if ((m_bid_i != AXI_ID) || (m_bresp_i != 2'b00))
                            error_r <= 1'b1;

                        if (frame_beat_r == FRAME_BEATS - BURST_BEATS) begin
                            completed_buffer_r <= ~display_buffer_r;
                            completed_base_r <= display_target_base_r;
                            display_buffer_r <= ~display_buffer_r;
                            display_valid_r <= 1'b1;
                            display_frame_count_r <=
                                display_frame_count_r + 1'b1;
                            if (active_camera_r)
                                last_cam1_count_r <= source_frame_count_r;
                            else
                                last_cam0_count_r <= source_frame_count_r;
                            state_r <= STATE_IDLE;
                        end else begin
                            frame_beat_r <= frame_beat_r + BURST_BEATS;
                            read_addr_r <= read_addr_r + BURST_BYTES;
                            write_addr_r <= write_addr_r + BURST_BYTES;
                            state_r <= STATE_AR;
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
            BURST_BEATS < 1 || BURST_BEATS > 16) begin : gen_bad_geometry
            edrv32_frame_composer_geometry_must_use_full_bursts
                u_static_assert ();
        end
    endgenerate

endmodule
