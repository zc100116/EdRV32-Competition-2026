// ============================================================================
// File        : edrv32_pango_ddr_axi_adapter.v
// Description : Restricted AXI4 slave to Pango DDR3 native-AXI UI adapter.
// Notes       : The DDR-facing AXI profile is 256-bit, aligned INCR bursts of
//               at most 16 beats. One AXI request maps to one DDR UI request.
//               The UI read channel has no RREADY, so every issued read owns
//               a complete-burst slot before the command reaches the UI.
// ============================================================================

module edrv32_pango_ddr_axi_adapter #(
    parameter integer ADDR_W = 32,
    parameter integer DATA_W = 256,
    parameter integer ID_W = 4,
    parameter integer LEN_W = 8,
    parameter integer UI_ADDR_W = 28,
    parameter integer UI_ID_W = 4,
    parameter integer RD_SLOT_COUNT = 4,
    parameter integer WR_SLOT_COUNT = 3,
    parameter integer RD_SLOT_W = (RD_SLOT_COUNT <= 1) ? 1 : $clog2(RD_SLOT_COUNT),
    parameter integer WR_SLOT_W = (WR_SLOT_COUNT <= 1) ? 1 : $clog2(WR_SLOT_COUNT)
) (
    input  wire                     clk_i,
    input  wire                     rst_n_i,
    input  wire                     init_done_i,

    input  wire [ID_W-1:0]          s_awid_i,
    input  wire [ADDR_W-1:0]        s_awaddr_i,
    input  wire [LEN_W-1:0]         s_awlen_i,
    input  wire [2:0]               s_awsize_i,
    input  wire [1:0]               s_awburst_i,
    input  wire                     s_awvalid_i,
    output wire                     s_awready_o,
    input  wire [DATA_W-1:0]        s_wdata_i,
    input  wire [DATA_W/8-1:0]      s_wstrb_i,
    input  wire                     s_wlast_i,
    input  wire                     s_wvalid_i,
    output wire                     s_wready_o,
    output wire [ID_W-1:0]          s_bid_o,
    output wire [1:0]               s_bresp_o,
    output wire                     s_bvalid_o,
    input  wire                     s_bready_i,

    input  wire [ID_W-1:0]          s_arid_i,
    input  wire [ADDR_W-1:0]        s_araddr_i,
    input  wire [LEN_W-1:0]         s_arlen_i,
    input  wire [2:0]               s_arsize_i,
    input  wire [1:0]               s_arburst_i,
    input  wire                     s_arvalid_i,
    output wire                     s_arready_o,
    output wire [ID_W-1:0]          s_rid_o,
    output wire [DATA_W-1:0]        s_rdata_o,
    output wire [1:0]               s_rresp_o,
    output wire                     s_rlast_o,
    output wire                     s_rvalid_o,
    input  wire                     s_rready_i,

    output wire [UI_ADDR_W-1:0]     ui_awaddr_o,
    output wire [UI_ID_W-1:0]       ui_awid_o,
    output wire [3:0]               ui_awlen_o,
    output wire                     ui_awvalid_o,
    input  wire                     ui_awready_i,
    output wire [DATA_W-1:0]        ui_wdata_o,
    output wire [DATA_W/8-1:0]      ui_wstrb_o,
    input  wire                     ui_wready_i,
    input  wire [UI_ID_W-1:0]       ui_wusero_id_i,
    input  wire                     ui_wusero_last_i,

    output wire [UI_ADDR_W-1:0]     ui_araddr_o,
    output wire [UI_ID_W-1:0]       ui_arid_o,
    output wire [3:0]               ui_arlen_o,
    output wire                     ui_arvalid_o,
    input  wire                     ui_arready_i,
    input  wire [DATA_W-1:0]        ui_rdata_i,
    input  wire [UI_ID_W-1:0]       ui_rid_i,
    input  wire                     ui_rlast_i,
    input  wire                     ui_rvalid_i,

    output wire                     protocol_error_o
);

    localparam integer STRB_W = DATA_W / 8;
    localparam integer SIZE_CODE = $clog2(STRB_W);
    localparam integer PAGE_BEAT_W = 12 - SIZE_CODE;
    localparam integer RD_COUNT_W = $clog2(RD_SLOT_COUNT + 1);
    localparam integer WR_COUNT_W = $clog2(WR_SLOT_COUNT + 1);
    localparam [UI_ID_W-1:0] RD_SLOT_LIMIT = RD_SLOT_COUNT[UI_ID_W-1:0];
    localparam [UI_ID_W-1:0] WR_SLOT_LIMIT = WR_SLOT_COUNT[UI_ID_W-1:0];
    localparam [1:0] RESP_OKAY = 2'b00;
    localparam [1:0] RESP_DECERR = 2'b11;
    localparam [LEN_W:0] PAGE_BEAT_LIMIT = 1 << PAGE_BEAT_W;

    function request_legal;
        input [11:0] addr_low_i;
        input [ADDR_W-UI_ADDR_W-3:0] addr_high_i;
        input [LEN_W-1:0] len_i;
        input [2:0] size_i;
        input [1:0] burst_i;
        reg [LEN_W:0] page_last_beat;
        begin
            page_last_beat = {
                {(LEN_W + 1 - PAGE_BEAT_W){1'b0}},
                addr_low_i[11:SIZE_CODE]
            } + {1'b0, len_i};
            request_legal = (len_i <= {{(LEN_W-4){1'b0}}, 4'd15}) &&
                            (size_i == SIZE_CODE[2:0]) &&
                            (burst_i == 2'b01) &&
                            (addr_low_i[SIZE_CODE-1:0] ==
                             {SIZE_CODE{1'b0}}) &&
                            (addr_high_i ==
                             {(ADDR_W-UI_ADDR_W-2){1'b0}}) &&
                            (page_last_beat < PAGE_BEAT_LIMIT);
        end
    endfunction

    // Read slots and UI command scheduler.
    reg [RD_SLOT_COUNT-1:0] rd_slot_active_r;
    reg [ID_W-1:0] rd_slot_id_r [0:RD_SLOT_COUNT-1];
    reg [ADDR_W-1:0] rd_slot_addr_r [0:RD_SLOT_COUNT-1];
    reg [LEN_W:0] rd_slot_beats_r [0:RD_SLOT_COUNT-1];
    reg [LEN_W:0] rd_slot_recv_r [0:RD_SLOT_COUNT-1];
    reg [LEN_W:0] rd_slot_send_r [0:RD_SLOT_COUNT-1];
    reg [1:0] rd_slot_resp_r [0:RD_SLOT_COUNT-1];
    reg [15:0] rd_slot_data_valid_r [0:RD_SLOT_COUNT-1];
    reg [DATA_W-1:0] rd_slot_data_r [0:RD_SLOT_COUNT-1][0:15];
    reg [RD_SLOT_W-1:0] rd_order_slot_r [0:RD_SLOT_COUNT-1];
    reg [RD_COUNT_W-1:0] rd_order_count_r;
    reg [RD_SLOT_W-1:0] rd_cmd_order_r [0:RD_SLOT_COUNT-1];
    reg [RD_COUNT_W-1:0] rd_cmd_order_count_r;

    reg rd_free_valid_w;
    reg [RD_SLOT_W-1:0] rd_free_slot_w;
    integer rd_free_i;
    always @(*) begin
        rd_free_valid_w = 1'b0;
        rd_free_slot_w = {RD_SLOT_W{1'b0}};
        for (rd_free_i = 0; rd_free_i < RD_SLOT_COUNT;
             rd_free_i = rd_free_i + 1) begin
            if (!rd_free_valid_w && !rd_slot_active_r[rd_free_i]) begin
                rd_free_valid_w = 1'b1;
                rd_free_slot_w = rd_free_i[RD_SLOT_W-1:0];
            end
        end
    end

    wire rd_request_legal_w = request_legal(
        s_araddr_i[11:0], s_araddr_i[ADDR_W-1:UI_ADDR_W+2],
        s_arlen_i, s_arsize_i, s_arburst_i);
    wire rd_request_fire_w = s_arvalid_i && s_arready_o;
    wire rd_cmd_push_w = rd_request_fire_w && rd_request_legal_w;
    wire rd_cmd_valid_w = rd_cmd_order_count_r != 0;
    wire [RD_SLOT_W-1:0] rd_cmd_slot_w = rd_cmd_order_r[0];
    wire rd_cmd_fire_w = ui_arvalid_o && ui_arready_i;

    assign s_arready_o = init_done_i && rd_free_valid_w &&
        (rd_order_count_r < RD_SLOT_COUNT);
    assign ui_araddr_o = rd_slot_addr_r[rd_cmd_slot_w][UI_ADDR_W+1:2];
    assign ui_arid_o = {{(UI_ID_W-RD_SLOT_W){1'b0}}, rd_cmd_slot_w};
    assign ui_arlen_o = rd_slot_beats_r[rd_cmd_slot_w][3:0] - 4'd1;
    assign ui_arvalid_o = init_done_i && rd_cmd_valid_w;

    wire [RD_SLOT_W-1:0] ui_read_slot_w = ui_rid_i[RD_SLOT_W-1:0];
    wire ui_read_id_valid_w = ui_rid_i < RD_SLOT_LIMIT;

    // Ordered read response scheduler and two-entry elastic output buffer.
    wire rd_head_valid_w = rd_order_count_r != 0;
    wire [RD_SLOT_W-1:0] rd_head_slot_w = rd_order_slot_r[0];
    wire [LEN_W:0] rd_head_index_w = rd_slot_send_r[rd_head_slot_w];
    wire rd_head_error_w = rd_slot_resp_r[rd_head_slot_w] != RESP_OKAY;
    wire rd_head_payload_valid_w = rd_head_error_w ||
        rd_slot_data_valid_r[rd_head_slot_w][rd_head_index_w[3:0]];
    wire rd_head_last_w = (rd_head_index_w + 1'b1) ==
        rd_slot_beats_r[rd_head_slot_w];

    reg r_fifo0_valid_r;
    reg [ID_W-1:0] r_fifo0_id_r;
    reg [DATA_W-1:0] r_fifo0_data_r;
    reg [1:0] r_fifo0_resp_r;
    reg r_fifo0_last_r;
    reg r_fifo1_valid_r;
    reg [ID_W-1:0] r_fifo1_id_r;
    reg [DATA_W-1:0] r_fifo1_data_r;
    reg [1:0] r_fifo1_resp_r;
    reg r_fifo1_last_r;

    wire r_fifo_pop_w = r_fifo0_valid_r && s_rready_i;
    wire r_fifo_push_ready_w = !r_fifo1_valid_r || r_fifo_pop_w;
    wire rd_emit_valid_w = rd_head_valid_w && rd_head_payload_valid_w;
    wire rd_emit_fire_w = rd_emit_valid_w && r_fifo_push_ready_w;
    wire rd_order_pop_w = rd_emit_fire_w && rd_head_last_w;
    wire [DATA_W-1:0] rd_emit_data_w = rd_head_error_w ?
        {DATA_W{1'b0}} :
        rd_slot_data_r[rd_head_slot_w][rd_head_index_w[3:0]];

    assign s_rid_o = r_fifo0_id_r;
    assign s_rdata_o = r_fifo0_data_r;
    assign s_rresp_o = r_fifo0_resp_r;
    assign s_rlast_o = r_fifo0_last_r;
    assign s_rvalid_o = r_fifo0_valid_r;

    // Write slots, W ordering and UI command scheduler.
    reg [WR_SLOT_COUNT-1:0] wr_slot_active_r;
    reg [WR_SLOT_COUNT-1:0] wr_slot_legal_r;
    reg [WR_SLOT_COUNT-1:0] wr_slot_issued_r;
    reg [WR_SLOT_COUNT-1:0] wr_slot_done_r;
    reg [ID_W-1:0] wr_slot_id_r [0:WR_SLOT_COUNT-1];
    reg [ADDR_W-1:0] wr_slot_addr_r [0:WR_SLOT_COUNT-1];
    reg [LEN_W:0] wr_slot_beats_r [0:WR_SLOT_COUNT-1];
    reg [LEN_W:0] wr_slot_fill_r [0:WR_SLOT_COUNT-1];
    reg [4:0] wr_slot_send_r [0:WR_SLOT_COUNT-1];
    reg [1:0] wr_slot_resp_r [0:WR_SLOT_COUNT-1];
    reg [DATA_W-1:0] wr_slot_data_r [0:WR_SLOT_COUNT-1][0:15];
    reg [STRB_W-1:0] wr_slot_strb_r [0:WR_SLOT_COUNT-1][0:15];
    reg [WR_SLOT_W-1:0] wr_data_order_r [0:WR_SLOT_COUNT-1];
    reg [WR_COUNT_W-1:0] wr_data_order_count_r;
    reg [WR_SLOT_W-1:0] wr_resp_order_r [0:WR_SLOT_COUNT-1];
    reg [WR_COUNT_W-1:0] wr_resp_order_count_r;
    reg [WR_SLOT_W-1:0] wr_cmd_order_r [0:WR_SLOT_COUNT-1];
    reg [WR_COUNT_W-1:0] wr_cmd_order_count_r;

    reg wr_free_valid_w;
    reg [WR_SLOT_W-1:0] wr_free_slot_w;
    integer wr_free_i;
    always @(*) begin
        wr_free_valid_w = 1'b0;
        wr_free_slot_w = {WR_SLOT_W{1'b0}};
        for (wr_free_i = 0; wr_free_i < WR_SLOT_COUNT;
             wr_free_i = wr_free_i + 1) begin
            if (!wr_free_valid_w && !wr_slot_active_r[wr_free_i]) begin
                wr_free_valid_w = 1'b1;
                wr_free_slot_w = wr_free_i[WR_SLOT_W-1:0];
            end
        end
    end

    wire wr_request_legal_w = request_legal(
        s_awaddr_i[11:0], s_awaddr_i[ADDR_W-1:UI_ADDR_W+2],
        s_awlen_i, s_awsize_i, s_awburst_i);
    wire wr_request_fire_w = s_awvalid_i && s_awready_o;
    wire wr_data_head_valid_w = wr_data_order_count_r != 0;
    wire [WR_SLOT_W-1:0] wr_data_slot_w = wr_data_order_r[0];
    wire wr_data_last_w = (wr_slot_fill_r[wr_data_slot_w] + 1'b1) ==
        wr_slot_beats_r[wr_data_slot_w];
    wire wr_data_fire_w = s_wvalid_i && s_wready_o;
    wire wr_data_order_pop_w = wr_data_fire_w && wr_data_last_w;

    assign s_awready_o = init_done_i && wr_free_valid_w &&
        (wr_data_order_count_r < WR_SLOT_COUNT) &&
        (wr_resp_order_count_r < WR_SLOT_COUNT);
    assign s_wready_o = init_done_i && wr_data_head_valid_w;

    wire wr_cmd_push_w = wr_data_order_pop_w &&
        wr_slot_legal_r[wr_data_slot_w];
    wire wr_cmd_valid_w = wr_cmd_order_count_r != 0;
    wire [WR_SLOT_W-1:0] wr_cmd_slot_w = wr_cmd_order_r[0];
    wire wr_cmd_fire_w = ui_awvalid_o && ui_awready_i;

    assign ui_awaddr_o = wr_slot_addr_r[wr_cmd_slot_w][UI_ADDR_W+1:2];
    assign ui_awid_o = {{(UI_ID_W-WR_SLOT_W){1'b0}}, wr_cmd_slot_w};
    assign ui_awlen_o = wr_slot_beats_r[wr_cmd_slot_w][3:0] - 4'd1;
    assign ui_awvalid_o = init_done_i && wr_cmd_valid_w;

    wire [WR_SLOT_W-1:0] ui_write_slot_w =
        ui_wusero_id_i[WR_SLOT_W-1:0];
    wire ui_write_id_valid_w = ui_wusero_id_i < WR_SLOT_LIMIT;
    wire [4:0] ui_write_index_w = wr_slot_send_r[ui_write_slot_w];
    wire ui_write_last_w = (ui_write_index_w + 5'd1) ==
        wr_slot_beats_r[ui_write_slot_w][4:0];
    wire ui_write_fire_w = init_done_i && ui_wready_i;
    // The Pango UI may request the first data beat in the same cycle that it
    // accepts the corresponding write command.  The registered issued bit is
    // still low in that cycle, so include the matching command handshake in
    // the ownership check instead of discarding the first beat.
    wire ui_write_slot_issued_w = wr_slot_issued_r[ui_write_slot_w] ||
        (wr_cmd_fire_w && (wr_cmd_slot_w == ui_write_slot_w));

    assign ui_wdata_o = wr_slot_data_r[ui_write_slot_w]
        [ui_write_index_w[3:0]];
    assign ui_wstrb_o = wr_slot_strb_r[ui_write_slot_w]
        [ui_write_index_w[3:0]];

    // Ordered B response scheduler and two-entry elastic output buffer.
    wire wr_resp_head_valid_w = wr_resp_order_count_r != 0;
    wire [WR_SLOT_W-1:0] wr_resp_slot_w = wr_resp_order_r[0];
    reg b_fifo0_valid_r;
    reg [ID_W-1:0] b_fifo0_id_r;
    reg [1:0] b_fifo0_resp_r;
    reg b_fifo1_valid_r;
    reg [ID_W-1:0] b_fifo1_id_r;
    reg [1:0] b_fifo1_resp_r;

    wire b_fifo_pop_w = b_fifo0_valid_r && s_bready_i;
    wire b_fifo_push_ready_w = !b_fifo1_valid_r || b_fifo_pop_w;
    wire wr_resp_emit_valid_w = wr_resp_head_valid_w &&
        wr_slot_done_r[wr_resp_slot_w];
    wire wr_resp_emit_fire_w = wr_resp_emit_valid_w &&
        b_fifo_push_ready_w;

    assign s_bid_o = b_fifo0_id_r;
    assign s_bresp_o = b_fifo0_resp_r;
    assign s_bvalid_o = b_fifo0_valid_r;

    reg protocol_error_r;
    integer reset_i;
    integer order_i;

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            rd_slot_active_r <= {RD_SLOT_COUNT{1'b0}};
            rd_order_count_r <= {RD_COUNT_W{1'b0}};
            rd_cmd_order_count_r <= {RD_COUNT_W{1'b0}};
            r_fifo0_valid_r <= 1'b0;
            r_fifo1_valid_r <= 1'b0;
            wr_slot_active_r <= {WR_SLOT_COUNT{1'b0}};
            wr_slot_legal_r <= {WR_SLOT_COUNT{1'b0}};
            wr_slot_issued_r <= {WR_SLOT_COUNT{1'b0}};
            wr_slot_done_r <= {WR_SLOT_COUNT{1'b0}};
            wr_data_order_count_r <= {WR_COUNT_W{1'b0}};
            wr_resp_order_count_r <= {WR_COUNT_W{1'b0}};
            wr_cmd_order_count_r <= {WR_COUNT_W{1'b0}};
            b_fifo0_valid_r <= 1'b0;
            b_fifo1_valid_r <= 1'b0;
            protocol_error_r <= 1'b0;
            for (reset_i = 0; reset_i < RD_SLOT_COUNT;
                 reset_i = reset_i + 1) begin
                rd_slot_recv_r[reset_i] <= {(LEN_W+1){1'b0}};
                rd_slot_send_r[reset_i] <= {(LEN_W+1){1'b0}};
                rd_slot_data_valid_r[reset_i] <= 16'b0;
            end
            for (reset_i = 0; reset_i < WR_SLOT_COUNT;
                 reset_i = reset_i + 1) begin
                wr_slot_fill_r[reset_i] <= {(LEN_W+1){1'b0}};
                wr_slot_send_r[reset_i] <= 5'b0;
            end
        end else begin
            if ((rd_request_fire_w && !rd_request_legal_w) ||
                (wr_request_fire_w && !wr_request_legal_w))
                protocol_error_r <= 1'b1;

            if (rd_request_fire_w) begin
                rd_slot_active_r[rd_free_slot_w] <= 1'b1;
                rd_slot_id_r[rd_free_slot_w] <= s_arid_i;
                rd_slot_addr_r[rd_free_slot_w] <= s_araddr_i;
                rd_slot_beats_r[rd_free_slot_w] <=
                    {1'b0, s_arlen_i} + 1'b1;
                rd_slot_recv_r[rd_free_slot_w] <= {(LEN_W+1){1'b0}};
                rd_slot_send_r[rd_free_slot_w] <= {(LEN_W+1){1'b0}};
                rd_slot_resp_r[rd_free_slot_w] <=
                    rd_request_legal_w ? RESP_OKAY : RESP_DECERR;
                rd_slot_data_valid_r[rd_free_slot_w] <= 16'b0;
            end

            case ({rd_cmd_push_w, rd_cmd_fire_w})
                2'b10: begin
                    rd_cmd_order_r[rd_cmd_order_count_r] <= rd_free_slot_w;
                    rd_cmd_order_count_r <= rd_cmd_order_count_r + 1'b1;
                end
                2'b01: begin
                    for (order_i = 0; order_i < RD_SLOT_COUNT-1;
                         order_i = order_i + 1)
                        rd_cmd_order_r[order_i] <= rd_cmd_order_r[order_i+1];
                    rd_cmd_order_count_r <= rd_cmd_order_count_r - 1'b1;
                end
                2'b11: begin
                    for (order_i = 0; order_i < RD_SLOT_COUNT-1;
                         order_i = order_i + 1)
                        rd_cmd_order_r[order_i] <= rd_cmd_order_r[order_i+1];
                    rd_cmd_order_r[rd_cmd_order_count_r-1'b1] <= rd_free_slot_w;
                    rd_cmd_order_count_r <= rd_cmd_order_count_r;
                end
                default: rd_cmd_order_count_r <= rd_cmd_order_count_r;
            endcase

            if (ui_rvalid_i) begin
                if (!ui_read_id_valid_w ||
                    !rd_slot_active_r[ui_read_slot_w] ||
                    (rd_slot_resp_r[ui_read_slot_w] != RESP_OKAY)) begin
                    protocol_error_r <= 1'b1;
                end else begin
                    rd_slot_data_r[ui_read_slot_w]
                        [rd_slot_recv_r[ui_read_slot_w][3:0]] <= ui_rdata_i;
                    rd_slot_data_valid_r[ui_read_slot_w]
                        [rd_slot_recv_r[ui_read_slot_w][3:0]] <= 1'b1;
                    if (ui_rlast_i !=
                        ((rd_slot_recv_r[ui_read_slot_w] + 1'b1) ==
                         rd_slot_beats_r[ui_read_slot_w]))
                        protocol_error_r <= 1'b1;
                    rd_slot_recv_r[ui_read_slot_w] <=
                        rd_slot_recv_r[ui_read_slot_w] + 1'b1;
                end
            end

            if (rd_emit_fire_w) begin
                if (!rd_head_error_w)
                    rd_slot_data_valid_r[rd_head_slot_w]
                        [rd_head_index_w[3:0]] <= 1'b0;
                if (rd_head_last_w) begin
                    rd_slot_active_r[rd_head_slot_w] <= 1'b0;
                    rd_slot_send_r[rd_head_slot_w] <= {(LEN_W+1){1'b0}};
                end else begin
                    rd_slot_send_r[rd_head_slot_w] <=
                        rd_slot_send_r[rd_head_slot_w] + 1'b1;
                end
            end

            case ({rd_request_fire_w, rd_order_pop_w})
                2'b10: begin
                    rd_order_slot_r[rd_order_count_r] <= rd_free_slot_w;
                    rd_order_count_r <= rd_order_count_r + 1'b1;
                end
                2'b01: begin
                    for (order_i = 0; order_i < RD_SLOT_COUNT-1;
                         order_i = order_i + 1)
                        rd_order_slot_r[order_i] <= rd_order_slot_r[order_i+1];
                    rd_order_count_r <= rd_order_count_r - 1'b1;
                end
                2'b11: begin
                    for (order_i = 0; order_i < RD_SLOT_COUNT-1;
                         order_i = order_i + 1)
                        rd_order_slot_r[order_i] <= rd_order_slot_r[order_i+1];
                    rd_order_slot_r[rd_order_count_r-1'b1] <= rd_free_slot_w;
                    rd_order_count_r <= rd_order_count_r;
                end
                default: rd_order_count_r <= rd_order_count_r;
            endcase

            case ({rd_emit_fire_w, r_fifo_pop_w})
                2'b10: begin
                    if (!r_fifo0_valid_r) begin
                        r_fifo0_valid_r <= 1'b1;
                        r_fifo0_id_r <= rd_slot_id_r[rd_head_slot_w];
                        r_fifo0_data_r <= rd_emit_data_w;
                        r_fifo0_resp_r <= rd_slot_resp_r[rd_head_slot_w];
                        r_fifo0_last_r <= rd_head_last_w;
                    end else begin
                        r_fifo1_valid_r <= 1'b1;
                        r_fifo1_id_r <= rd_slot_id_r[rd_head_slot_w];
                        r_fifo1_data_r <= rd_emit_data_w;
                        r_fifo1_resp_r <= rd_slot_resp_r[rd_head_slot_w];
                        r_fifo1_last_r <= rd_head_last_w;
                    end
                end
                2'b01: begin
                    r_fifo0_valid_r <= r_fifo1_valid_r;
                    if (r_fifo1_valid_r) begin
                        r_fifo0_id_r <= r_fifo1_id_r;
                        r_fifo0_data_r <= r_fifo1_data_r;
                        r_fifo0_resp_r <= r_fifo1_resp_r;
                        r_fifo0_last_r <= r_fifo1_last_r;
                    end
                    r_fifo1_valid_r <= 1'b0;
                end
                2'b11: begin
                    if (r_fifo1_valid_r) begin
                        r_fifo0_valid_r <= 1'b1;
                        r_fifo0_id_r <= r_fifo1_id_r;
                        r_fifo0_data_r <= r_fifo1_data_r;
                        r_fifo0_resp_r <= r_fifo1_resp_r;
                        r_fifo0_last_r <= r_fifo1_last_r;
                        r_fifo1_valid_r <= 1'b1;
                        r_fifo1_id_r <= rd_slot_id_r[rd_head_slot_w];
                        r_fifo1_data_r <= rd_emit_data_w;
                        r_fifo1_resp_r <= rd_slot_resp_r[rd_head_slot_w];
                        r_fifo1_last_r <= rd_head_last_w;
                    end else begin
                        r_fifo0_valid_r <= 1'b1;
                        r_fifo0_id_r <= rd_slot_id_r[rd_head_slot_w];
                        r_fifo0_data_r <= rd_emit_data_w;
                        r_fifo0_resp_r <= rd_slot_resp_r[rd_head_slot_w];
                        r_fifo0_last_r <= rd_head_last_w;
                        r_fifo1_valid_r <= 1'b0;
                    end
                end
                default: ;
            endcase

            if (wr_request_fire_w) begin
                wr_slot_active_r[wr_free_slot_w] <= 1'b1;
                wr_slot_legal_r[wr_free_slot_w] <= wr_request_legal_w;
                wr_slot_issued_r[wr_free_slot_w] <= 1'b0;
                wr_slot_done_r[wr_free_slot_w] <= 1'b0;
                wr_slot_id_r[wr_free_slot_w] <= s_awid_i;
                wr_slot_addr_r[wr_free_slot_w] <= s_awaddr_i;
                wr_slot_beats_r[wr_free_slot_w] <=
                    {1'b0, s_awlen_i} + 1'b1;
                wr_slot_fill_r[wr_free_slot_w] <= {(LEN_W+1){1'b0}};
                wr_slot_send_r[wr_free_slot_w] <= 5'b0;
                wr_slot_resp_r[wr_free_slot_w] <=
                    wr_request_legal_w ? RESP_OKAY : RESP_DECERR;
            end

            if (wr_data_fire_w) begin
                if (s_wlast_i != wr_data_last_w)
                    protocol_error_r <= 1'b1;
                if (wr_slot_legal_r[wr_data_slot_w]) begin
                    wr_slot_data_r[wr_data_slot_w]
                        [wr_slot_fill_r[wr_data_slot_w][3:0]] <= s_wdata_i;
                    wr_slot_strb_r[wr_data_slot_w]
                        [wr_slot_fill_r[wr_data_slot_w][3:0]] <= s_wstrb_i;
                end
                if (wr_data_last_w) begin
                    wr_slot_fill_r[wr_data_slot_w] <= {(LEN_W+1){1'b0}};
                    if (!wr_slot_legal_r[wr_data_slot_w])
                        wr_slot_done_r[wr_data_slot_w] <= 1'b1;
                end else begin
                    wr_slot_fill_r[wr_data_slot_w] <=
                        wr_slot_fill_r[wr_data_slot_w] + 1'b1;
                end
            end

            case ({wr_request_fire_w, wr_data_order_pop_w})
                2'b10: begin
                    wr_data_order_r[wr_data_order_count_r] <= wr_free_slot_w;
                    wr_data_order_count_r <= wr_data_order_count_r + 1'b1;
                end
                2'b01: begin
                    for (order_i = 0; order_i < WR_SLOT_COUNT-1;
                         order_i = order_i + 1)
                        wr_data_order_r[order_i] <= wr_data_order_r[order_i+1];
                    wr_data_order_count_r <= wr_data_order_count_r - 1'b1;
                end
                2'b11: begin
                    for (order_i = 0; order_i < WR_SLOT_COUNT-1;
                         order_i = order_i + 1)
                        wr_data_order_r[order_i] <= wr_data_order_r[order_i+1];
                    wr_data_order_r[wr_data_order_count_r-1'b1] <= wr_free_slot_w;
                    wr_data_order_count_r <= wr_data_order_count_r;
                end
                default: wr_data_order_count_r <= wr_data_order_count_r;
            endcase

            case ({wr_cmd_push_w, wr_cmd_fire_w})
                2'b10: begin
                    wr_cmd_order_r[wr_cmd_order_count_r] <= wr_data_slot_w;
                    wr_cmd_order_count_r <= wr_cmd_order_count_r + 1'b1;
                end
                2'b01: begin
                    for (order_i = 0; order_i < WR_SLOT_COUNT-1;
                         order_i = order_i + 1)
                        wr_cmd_order_r[order_i] <= wr_cmd_order_r[order_i+1];
                    wr_cmd_order_count_r <= wr_cmd_order_count_r - 1'b1;
                end
                2'b11: begin
                    for (order_i = 0; order_i < WR_SLOT_COUNT-1;
                         order_i = order_i + 1)
                        wr_cmd_order_r[order_i] <= wr_cmd_order_r[order_i+1];
                    wr_cmd_order_r[wr_cmd_order_count_r-1'b1] <= wr_data_slot_w;
                    wr_cmd_order_count_r <= wr_cmd_order_count_r;
                end
                default: wr_cmd_order_count_r <= wr_cmd_order_count_r;
            endcase
            if (wr_cmd_fire_w) begin
                wr_slot_issued_r[wr_cmd_slot_w] <= 1'b1;
            end

            if (ui_write_fire_w) begin
                if (!ui_write_id_valid_w ||
                    !wr_slot_active_r[ui_write_slot_w] ||
                    !wr_slot_legal_r[ui_write_slot_w] ||
                    !ui_write_slot_issued_w) begin
                    protocol_error_r <= 1'b1;
                end else begin
                    if (ui_wusero_last_i != ui_write_last_w)
                        protocol_error_r <= 1'b1;
                    if (ui_write_last_w) begin
                        wr_slot_send_r[ui_write_slot_w] <= 5'b0;
                        wr_slot_issued_r[ui_write_slot_w] <= 1'b0;
                        wr_slot_done_r[ui_write_slot_w] <= 1'b1;
                    end else begin
                        wr_slot_send_r[ui_write_slot_w] <=
                            wr_slot_send_r[ui_write_slot_w] + 1'b1;
                    end
                end
            end

            if (wr_resp_emit_fire_w) begin
                wr_slot_active_r[wr_resp_slot_w] <= 1'b0;
                wr_slot_done_r[wr_resp_slot_w] <= 1'b0;
            end
            case ({wr_request_fire_w, wr_resp_emit_fire_w})
                2'b10: begin
                    wr_resp_order_r[wr_resp_order_count_r] <= wr_free_slot_w;
                    wr_resp_order_count_r <= wr_resp_order_count_r + 1'b1;
                end
                2'b01: begin
                    for (order_i = 0; order_i < WR_SLOT_COUNT-1;
                         order_i = order_i + 1)
                        wr_resp_order_r[order_i] <= wr_resp_order_r[order_i+1];
                    wr_resp_order_count_r <= wr_resp_order_count_r - 1'b1;
                end
                2'b11: begin
                    for (order_i = 0; order_i < WR_SLOT_COUNT-1;
                         order_i = order_i + 1)
                        wr_resp_order_r[order_i] <= wr_resp_order_r[order_i+1];
                    wr_resp_order_r[wr_resp_order_count_r-1'b1] <= wr_free_slot_w;
                    wr_resp_order_count_r <= wr_resp_order_count_r;
                end
                default: wr_resp_order_count_r <= wr_resp_order_count_r;
            endcase

            case ({wr_resp_emit_fire_w, b_fifo_pop_w})
                2'b10: begin
                    if (!b_fifo0_valid_r) begin
                        b_fifo0_valid_r <= 1'b1;
                        b_fifo0_id_r <= wr_slot_id_r[wr_resp_slot_w];
                        b_fifo0_resp_r <= wr_slot_resp_r[wr_resp_slot_w];
                    end else begin
                        b_fifo1_valid_r <= 1'b1;
                        b_fifo1_id_r <= wr_slot_id_r[wr_resp_slot_w];
                        b_fifo1_resp_r <= wr_slot_resp_r[wr_resp_slot_w];
                    end
                end
                2'b01: begin
                    b_fifo0_valid_r <= b_fifo1_valid_r;
                    if (b_fifo1_valid_r) begin
                        b_fifo0_id_r <= b_fifo1_id_r;
                        b_fifo0_resp_r <= b_fifo1_resp_r;
                    end
                    b_fifo1_valid_r <= 1'b0;
                end
                2'b11: begin
                    if (b_fifo1_valid_r) begin
                        b_fifo0_valid_r <= 1'b1;
                        b_fifo0_id_r <= b_fifo1_id_r;
                        b_fifo0_resp_r <= b_fifo1_resp_r;
                        b_fifo1_valid_r <= 1'b1;
                        b_fifo1_id_r <= wr_slot_id_r[wr_resp_slot_w];
                        b_fifo1_resp_r <= wr_slot_resp_r[wr_resp_slot_w];
                    end else begin
                        b_fifo0_valid_r <= 1'b1;
                        b_fifo0_id_r <= wr_slot_id_r[wr_resp_slot_w];
                        b_fifo0_resp_r <= wr_slot_resp_r[wr_resp_slot_w];
                        b_fifo1_valid_r <= 1'b0;
                    end
                end
                default: ;
            endcase
        end
    end

    assign protocol_error_o = protocol_error_r;

endmodule
