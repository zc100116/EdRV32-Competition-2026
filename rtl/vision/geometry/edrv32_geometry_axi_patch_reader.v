// ============================================================================
// File        : edrv32_geometry_axi_patch_reader.v
// Description : Load a bounded RGB565 patch with up to four AXI reads in flight.
// Notes       : Each source row is a 1..4 beat burst. Four local IDs allow the
//               next rows to be issued before earlier R bursts finish; RID
//               selects each row's patch-RAM destination independently.
// ============================================================================

module edrv32_geometry_axi_patch_reader (
    input  wire         clk_i,
    input  wire         rst_n_i,

    input  wire         req_valid_i,
    output wire         req_ready_o,
    input  wire [31:0]  req_surface_base_i,
    input  wire [31:0]  req_stride_i,
    input  wire [15:0]  req_x_base_i,
    input  wire [15:0]  req_y_base_i,
    input  wire [2:0]   req_width_beats_i,
    input  wire [6:0]   req_height_i,

    output wire         patch_wr_en_o,
    output wire [1:0]   patch_wr_column_o,
    output wire [5:0]   patch_wr_row_o,
    output wire [255:0] patch_wr_data_o,
    output wire         done_o,
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
    output wire         m_rready_o
);

    localparam [1:0] STATE_IDLE = 2'd0;
    localparam [1:0] STATE_BUSY = 2'd1;
    localparam [1:0] RESP_OKAY  = 2'b00;

    reg [1:0] state_r;
    reg done_r;
    reg error_r;
    reg [31:0] issue_base_r;
    reg [31:0] stride_r;
    reg [2:0] width_beats_r;
    reg [6:0] height_r;
    reg [6:0] issue_row_r;
    reg [2:0] issue_column_r;

    reg [3:0] slot_active_r;
    reg [5:0] slot_row_r [0:3];
    reg [2:0] slot_column_r [0:3];
    reg [2:0] slot_beats_r [0:3];
    reg [2:0] slot_beat_r [0:3];
    integer slot_i;

    reg free_valid_w;
    reg [1:0] free_index_w;
    integer free_i;
    always @(*) begin
        free_valid_w = 1'b0;
        free_index_w = 2'b0;
        for (free_i = 0; free_i < 4; free_i = free_i + 1) begin
            if (!free_valid_w && !slot_active_r[free_i]) begin
                free_valid_w = 1'b1;
                free_index_w = free_i[1:0];
            end
        end
    end

    wire req_legal_w = (req_surface_base_i[4:0] == 5'b0) &&
        (req_stride_i[4:0] == 5'b0) &&
        (req_x_base_i[3:0] == 4'b0) &&
        (req_width_beats_i >= 3'd1) &&
        (req_width_beats_i <= 3'd4) &&
        (req_height_i >= 7'd1) && (req_height_i <= 7'd64);
    wire [32:0] row_offset_w = req_y_base_i * req_stride_i;
    wire [32:0] request_addr_w = {1'b0, req_surface_base_i} +
        row_offset_w + {16'b0, req_x_base_i, 1'b0};
    wire req_fire_w = req_valid_i && req_ready_o;

    wire [3:0] remaining_beats_w =
        {1'b0, width_beats_r} - {1'b0, issue_column_r};
    wire [7:0] boundary_beats_w =
        8'd128 - {1'b0, m_araddr_o[11:5]};
    wire [2:0] next_segment_beats_w =
        boundary_beats_w < remaining_beats_w ?
        boundary_beats_w[2:0] : remaining_beats_w[2:0];
    wire ar_fire_w = m_arvalid_o && m_arready_i;
    wire r_fire_w = m_rvalid_i && m_rready_o;
    wire [1:0] response_slot_w = m_rid_i[1:0];
    wire response_valid_w = (m_rid_i[3:2] == 2'b0) &&
        slot_active_r[response_slot_w];
    wire response_last_w = response_valid_w &&
        (slot_beat_r[response_slot_w] ==
         slot_beats_r[response_slot_w] - 1'b1);
    wire issue_last_segment_w =
        ({1'b0, issue_column_r} + {1'b0, next_segment_beats_w}) ==
        {1'b0, width_beats_r};

    assign req_ready_o = state_r == STATE_IDLE;
    assign done_o = done_r;
    assign error_o = error_r;
    assign patch_wr_en_o = r_fire_w && response_valid_w &&
        (m_rresp_i == RESP_OKAY);
    assign patch_wr_column_o =
        slot_column_r[response_slot_w][1:0] +
        slot_beat_r[response_slot_w][1:0];
    assign patch_wr_row_o = slot_row_r[response_slot_w];
    assign patch_wr_data_o = m_rdata_i;

    assign m_arid_o = {2'b0, free_index_w};
    assign m_araddr_o = issue_base_r + {issue_column_r, 5'b0};
    assign m_arlen_o = {5'b0, next_segment_beats_w} - 1'b1;
    assign m_arsize_o = 3'd5;
    assign m_arburst_o = 2'b01;
    assign m_arqos_o = 4'h8;
    assign m_arvalid_o = (state_r == STATE_BUSY) &&
        (issue_row_r < height_r) && free_valid_w;
    assign m_rready_o = (state_r == STATE_BUSY) && (|slot_active_r);

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            state_r <= STATE_IDLE;
            done_r <= 1'b0;
            error_r <= 1'b0;
            issue_base_r <= 32'b0;
            stride_r <= 32'b0;
            width_beats_r <= 3'b0;
            height_r <= 7'b0;
            issue_row_r <= 7'b0;
            issue_column_r <= 3'b0;
            slot_active_r <= 4'b0;
            for (slot_i = 0; slot_i < 4; slot_i = slot_i + 1) begin
                slot_row_r[slot_i] <= 6'b0;
                slot_column_r[slot_i] <= 3'b0;
                slot_beats_r[slot_i] <= 3'b0;
                slot_beat_r[slot_i] <= 3'b0;
            end
        end else begin
            done_r <= 1'b0;

            if (req_fire_w) begin
                error_r <= !req_legal_w || request_addr_w[32];
                issue_base_r <= request_addr_w[31:0];
                stride_r <= req_stride_i;
                width_beats_r <= req_width_beats_i;
                height_r <= req_height_i;
                issue_row_r <= 7'b0;
                issue_column_r <= 3'b0;
                slot_active_r <= 4'b0;
                if (req_legal_w && !request_addr_w[32]) begin
                    state_r <= STATE_BUSY;
                end else begin
                    done_r <= 1'b1;
                end
            end

            if (ar_fire_w) begin
                slot_active_r[free_index_w] <= 1'b1;
                slot_row_r[free_index_w] <= issue_row_r[5:0];
                slot_column_r[free_index_w] <= issue_column_r;
                slot_beats_r[free_index_w] <= next_segment_beats_w;
                slot_beat_r[free_index_w] <= 3'b0;
                if (issue_last_segment_w) begin
                    issue_row_r <= issue_row_r + 1'b1;
                    issue_column_r <= 3'b0;
                    issue_base_r <= issue_base_r + stride_r;
                end else begin
                    issue_column_r <= issue_column_r +
                        next_segment_beats_w;
                end
            end

            if (r_fire_w) begin
                if (!response_valid_w ||
                    (m_rresp_i != RESP_OKAY) ||
                    (m_rlast_i != response_last_w))
                    error_r <= 1'b1;
                if (response_valid_w) begin
                    if (response_last_w) begin
                        slot_active_r[response_slot_w] <= 1'b0;
                    end else begin
                        slot_beat_r[response_slot_w] <=
                            slot_beat_r[response_slot_w] + 1'b1;
                    end
                end
            end

            if ((state_r == STATE_BUSY) &&
                (issue_row_r == height_r) && !(|slot_active_r)) begin
                done_r <= 1'b1;
                state_r <= STATE_IDLE;
            end
        end
    end

endmodule
