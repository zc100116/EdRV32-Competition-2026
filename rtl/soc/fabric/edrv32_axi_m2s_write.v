// ============================================================================
// File        : edrv32_axi_m2s_write.v
// Description : Generic multi-master, single-slave AXI4 write fabric. AW
//               commands are buffered and scheduled by
//               burst; an explicit order FIFO owns W until the expected last
//               beat, and downstream B IDs are mapped back to each master.
// Notes       : Invalid AW requests still consume their W burst in order and
//               complete locally with DECERR without touching the slave.
// ============================================================================

module edrv32_axi_m2s_write #(
    parameter integer NUM_M = 4,
    parameter integer ADDR_W = 32,
    parameter integer DATA_W = 256,
    parameter integer ID_W = 4,
    parameter integer S_ID_W = 4,
    parameter integer LEN_W = 8,
    parameter integer ORDER_DEPTH = 8,
    parameter integer STARVE_CYCLES = 64,
    parameter integer INGRESS_READY_BYPASS = 1,
    parameter integer MI_W = (NUM_M <= 1) ? 1 : $clog2(NUM_M),
    parameter integer COUNT_W = S_ID_W + 1,
    parameter integer ORDER_PTR_W = (ORDER_DEPTH <= 1) ? 1 : $clog2(ORDER_DEPTH),
    parameter integer ORDER_CNT_W = $clog2(ORDER_DEPTH + 1)
) (
    input  wire                         clk_i,
    input  wire                         rst_n_i,
    input  wire                         accept_i,

    input  wire [NUM_M*ID_W-1:0]        m_awid_i,
    input  wire [NUM_M*ADDR_W-1:0]      m_awaddr_i,
    input  wire [NUM_M*LEN_W-1:0]       m_awlen_i,
    input  wire [NUM_M*3-1:0]           m_awsize_i,
    input  wire [NUM_M*2-1:0]           m_awburst_i,
    input  wire [NUM_M*4-1:0]           m_awqos_i,
    input  wire [NUM_M-1:0]             m_awvalid_i,
    output wire [NUM_M-1:0]             m_awready_o,

    input  wire [NUM_M*DATA_W-1:0]      m_wdata_i,
    input  wire [NUM_M*(DATA_W/8)-1:0]  m_wstrb_i,
    input  wire [NUM_M-1:0]             m_wlast_i,
    input  wire [NUM_M-1:0]             m_wvalid_i,
    output wire [NUM_M-1:0]             m_wready_o,

    output wire [NUM_M*ID_W-1:0]        m_bid_o,
    output wire [NUM_M*2-1:0]           m_bresp_o,
    output wire [NUM_M-1:0]             m_bvalid_o,
    input  wire [NUM_M-1:0]             m_bready_i,

    input  wire [NUM_M-1:0]             m_write_urgent_i,
    input  wire [NUM_M*4-1:0]           m_write_weight_i,
    input  wire [NUM_M*5-1:0]           m_write_credit_i,
    output wire [S_ID_W-1:0]            s_awid_o,
    output wire [ADDR_W-1:0]            s_awaddr_o,
    output wire [LEN_W-1:0]             s_awlen_o,
    output wire [2:0]                   s_awsize_o,
    output wire [1:0]                   s_awburst_o,
    output wire [3:0]                   s_awqos_o,
    output wire                         s_awvalid_o,
    input  wire                         s_awready_i,

    output wire [DATA_W-1:0]            s_wdata_o,
    output wire [DATA_W/8-1:0]          s_wstrb_o,
    output wire                         s_wlast_o,
    output wire                         s_wvalid_o,
    input  wire                         s_wready_i,

    input  wire [S_ID_W-1:0]            s_bid_i,
    input  wire [1:0]                   s_bresp_i,
    input  wire                         s_bvalid_i,
    output wire                         s_bready_o,

    output wire [NUM_M*COUNT_W-1:0]     outstanding_o,
    output wire                         protocol_error_o,
    output wire                         w_owner_valid_o,
    output wire [MI_W-1:0]              w_owner_o
);

    localparam integer STRB_W = DATA_W / 8;
    localparam integer SIZE_CODE = $clog2(STRB_W);
    localparam integer SLOT_COUNT = (1 << S_ID_W);
    localparam integer LOCAL_ID_COUNT = (1 << ID_W);
    localparam [1:0] RESP_DECERR = 2'b11;
    localparam [S_ID_W:0] FREE_COUNT_LIMIT = SLOT_COUNT[S_ID_W:0];
    localparam [ORDER_PTR_W-1:0] ORDER_LAST = ORDER_DEPTH[ORDER_PTR_W-1:0] - 1'b1;
    localparam [ORDER_CNT_W-1:0] ORDER_COUNT_LIMIT =
        ORDER_DEPTH[ORDER_CNT_W-1:0];

    reg [NUM_M-1:0] awbuf_valid_r;
    reg [ID_W-1:0] awbuf_id_r [0:NUM_M-1];
    reg [ADDR_W-1:0] awbuf_addr_r [0:NUM_M-1];
    reg [LEN_W-1:0] awbuf_len_r [0:NUM_M-1];
    reg [2:0] awbuf_size_r [0:NUM_M-1];
    reg [1:0] awbuf_burst_r [0:NUM_M-1];
    reg [3:0] awbuf_qos_r [0:NUM_M-1];
    reg [NUM_M-1:0] awbuf_legal_r;

    reg [COUNT_W-1:0] outstanding_r [0:NUM_M-1];
    reg [LOCAL_ID_COUNT-1:0] local_id_busy_r [0:NUM_M-1];

    reg [SLOT_COUNT-1:0] route_valid_r;
    reg [MI_W-1:0] route_master_r [0:SLOT_COUNT-1];
    reg [ID_W-1:0] route_local_id_r [0:SLOT_COUNT-1];

    wire route_release_w = s_bvalid_i && s_bready_o;

    // Registered allocation removes the B-to-AW combinational feedback while
    // allowing one route ID to be returned and one to be consumed per cycle.
    reg [S_ID_W-1:0] free_id_r [0:SLOT_COUNT-1];
    reg [S_ID_W-1:0] free_head_r;
    reg [S_ID_W-1:0] free_tail_r;
    reg [S_ID_W:0] free_count_r;

    wire free_valid_w = free_count_r != 0;
    wire [S_ID_W-1:0] free_index_w = free_id_r[free_head_r];

    // AW issue order is also W ownership order because AXI4 has no WID.
    reg [MI_W-1:0] order_master_r [0:ORDER_DEPTH-1];
    reg [ID_W-1:0] order_local_id_r [0:ORDER_DEPTH-1];
    reg [LEN_W-1:0] order_len_r [0:ORDER_DEPTH-1];
    reg [ORDER_DEPTH-1:0] order_error_r;
    reg [ORDER_PTR_W-1:0] order_head_r;
    reg [ORDER_PTR_W-1:0] order_tail_r;
    reg [ORDER_CNT_W-1:0] order_count_r;
    reg [LEN_W-1:0] w_beat_r;

    wire order_valid_w = (order_count_r != 0);
    wire [MI_W-1:0] order_master_w = order_master_r[order_head_r];
    assign w_owner_valid_o = order_valid_w;
    assign w_owner_o = order_master_w;
    wire [ID_W-1:0] order_local_id_w = order_local_id_r[order_head_r];
    wire [LEN_W-1:0] order_len_w = order_len_r[order_head_r];
    wire order_error_w = order_error_r[order_head_r];
    wire expected_last_w = order_valid_w && (w_beat_r == order_len_w);

    // Per-master B buffers isolate response backpressure and permit a B pop and
    // replacement in the same cycle.
    reg [NUM_M-1:0] bbuf_valid_r;
    reg [ID_W-1:0] bbuf_id_r [0:NUM_M-1];
    reg [1:0] bbuf_resp_r [0:NUM_M-1];
    reg [NUM_M-1:0] bbuf_ready_w;
    reg [NUM_M-1:0] slave_b_push_w;
    integer br_i;

    wire response_route_valid_w = route_valid_r[s_bid_i];
    wire [MI_W-1:0] response_master_w = route_master_r[s_bid_i];
    wire [ID_W-1:0] response_local_id_w = route_local_id_r[s_bid_i];

    always @(*) begin
        bbuf_ready_w = {NUM_M{1'b0}};
        slave_b_push_w = {NUM_M{1'b0}};
        for (br_i = 0; br_i < NUM_M; br_i = br_i + 1) begin
            bbuf_ready_w[br_i] = !bbuf_valid_r[br_i] ||
                (m_bready_i[br_i] && bbuf_valid_r[br_i]);
            if (s_bvalid_i && response_route_valid_w &&
                (response_master_w == br_i[MI_W-1:0]) &&
                bbuf_ready_w[br_i])
                slave_b_push_w[br_i] = 1'b1;
        end
    end
    assign s_bready_o = response_route_valid_w &&
        bbuf_ready_w[response_master_w];

    reg [NUM_M-1:0] wready_w;
    reg [NUM_M-1:0] error_b_push_w;
    reg [DATA_W-1:0] wdata_w;
    reg [STRB_W-1:0] wstrb_w;
    reg wlast_w;
    reg wvalid_w;
    always @(*) begin
        wready_w = {NUM_M{1'b0}};
        error_b_push_w = {NUM_M{1'b0}};
        wdata_w = {DATA_W{1'b0}};
        wstrb_w = {STRB_W{1'b0}};
        wlast_w = 1'b0;
        wvalid_w = 1'b0;
        if (order_valid_w) begin
            if (order_error_w) begin
                wready_w[order_master_w] = !expected_last_w ||
                    (bbuf_ready_w[order_master_w] &&
                     !slave_b_push_w[order_master_w]);
                if (m_wvalid_i[order_master_w] &&
                    wready_w[order_master_w] && expected_last_w)
                    error_b_push_w[order_master_w] = 1'b1;
            end else begin
                wdata_w = m_wdata_i[order_master_w*DATA_W +: DATA_W];
                wstrb_w = m_wstrb_i[order_master_w*STRB_W +: STRB_W];
                wlast_w = expected_last_w;
                wvalid_w = m_wvalid_i[order_master_w];
                wready_w[order_master_w] = s_wready_i;
            end
        end
    end

    assign m_wready_o = wready_w;
    assign s_wdata_o = wdata_w;
    assign s_wstrb_o = wstrb_w;
    assign s_wlast_o = wlast_w;
    assign s_wvalid_o = wvalid_w;

    wire selected_w_fire_w = order_valid_w &&
        m_wvalid_i[order_master_w] && wready_w[order_master_w];
    wire order_pop_w = selected_w_fire_w && expected_last_w;
    wire order_space_w = (order_count_r < ORDER_COUNT_LIMIT) || order_pop_w;

    reg [NUM_M-1:0] sched_req_w;
    reg [NUM_M*4-1:0] sched_qos_w;
    integer req_i;
    always @(*) begin
        sched_req_w = {NUM_M{1'b0}};
        sched_qos_w = {NUM_M*4{1'b0}};
        for (req_i = 0; req_i < NUM_M; req_i = req_i + 1) begin
            sched_req_w[req_i] = awbuf_valid_r[req_i] && order_space_w &&
                (awbuf_legal_r[req_i] ? free_valid_w : 1'b1);
            sched_qos_w[req_i*4 +: 4] = awbuf_qos_r[req_i];
        end
    end

    wire [NUM_M-1:0] sched_grant_w;
    wire sched_valid_w;
    wire [MI_W-1:0] sched_index_w;
    wire selected_legal_w = sched_valid_w && awbuf_legal_r[sched_index_w];
    wire selected_error_w = sched_valid_w && !awbuf_legal_r[sched_index_w];
    wire sched_fire_w = sched_valid_w &&
        (selected_error_w || (selected_legal_w && s_awready_i));
    wire route_alloc_w = sched_fire_w && selected_legal_w;

    edrv32_axi_m2s_arbiter #(
        .NUM_M(NUM_M),
        .STARVE_CYCLES(STARVE_CYCLES),
        .MI_W(MI_W)
    ) u_write_arbiter (
        .clk_i(clk_i),
        .rst_n_i(rst_n_i),
        .req_i(sched_req_w),
        .qos_i(sched_qos_w),
        .weight_i(m_write_weight_i),
        .urgent_i(m_write_urgent_i),
        .grant_o(sched_grant_w),
        .grant_valid_o(sched_valid_w),
        .grant_index_o(sched_index_w),
        .fire_i(sched_fire_w)
    );

    assign s_awid_o = free_index_w;
    assign s_awaddr_o = sched_valid_w ? awbuf_addr_r[sched_index_w] : {ADDR_W{1'b0}};
    assign s_awlen_o = sched_valid_w ? awbuf_len_r[sched_index_w] : {LEN_W{1'b0}};
    assign s_awsize_o = sched_valid_w ? awbuf_size_r[sched_index_w] : 3'b000;
    assign s_awburst_o = sched_valid_w ? awbuf_burst_r[sched_index_w] : 2'b00;
    assign s_awqos_o = sched_valid_w ? awbuf_qos_r[sched_index_w] : 4'b0000;
    assign s_awvalid_o = selected_legal_w;

    wire [NUM_M-1:0] awbuf_pop_w = sched_grant_w & {NUM_M{sched_fire_w}};

    genvar out_g;
    generate
        for (out_g = 0; out_g < NUM_M; out_g = out_g + 1) begin : gen_write_outputs
            assign m_bid_o[out_g*ID_W +: ID_W] = bbuf_id_r[out_g];
            assign m_bresp_o[out_g*2 +: 2] = bbuf_resp_r[out_g];
            assign m_bvalid_o[out_g] = bbuf_valid_r[out_g];
            assign outstanding_o[out_g*COUNT_W +: COUNT_W] = outstanding_r[out_g];
        end
    endgenerate

    wire [NUM_M-1:0] master_b_fire_w = bbuf_valid_r & m_bready_i;

    reg [NUM_M-1:0] awready_w;
    reg [NUM_M-1:0] master_aw_fire_w;
    reg [NUM_M-1:0] incoming_legal_w;
    reg [4:0] credit_limit_w;
    reg [12:0] byte_span_w;
    reg id_released_w;
    integer adm_i;
    always @(*) begin
        awready_w = {NUM_M{1'b0}};
        incoming_legal_w = {NUM_M{1'b0}};
        for (adm_i = 0; adm_i < NUM_M; adm_i = adm_i + 1) begin
            credit_limit_w = m_write_credit_i[adm_i*5 +: 5];
            if (credit_limit_w == 0)
                credit_limit_w = 5'd1;
            byte_span_w = ({5'b0, m_awlen_i[adm_i*LEN_W +: LEN_W]} + 1'b1)
                << SIZE_CODE;
            id_released_w = master_b_fire_w[adm_i] &&
                (bbuf_id_r[adm_i] == m_awid_i[adm_i*ID_W +: ID_W]);

            incoming_legal_w[adm_i] =
                (m_awsize_i[adm_i*3 +: 3] == SIZE_CODE[2:0]) &&
                (m_awburst_i[adm_i*2 +: 2] == 2'b01) &&
                (m_awaddr_i[adm_i*ADDR_W +: ADDR_W] & (STRB_W-1)) == 0 &&
                ({1'b0, m_awaddr_i[adm_i*ADDR_W +: 12]} + byte_span_w <= 13'd4096);

            awready_w[adm_i] = accept_i &&
                (!awbuf_valid_r[adm_i] ||
                 (INGRESS_READY_BYPASS && awbuf_pop_w[adm_i])) &&
                ((outstanding_r[adm_i] < credit_limit_w) || master_b_fire_w[adm_i]) &&
                (!local_id_busy_r[adm_i][m_awid_i[adm_i*ID_W +: ID_W]] ||
                 id_released_w);
        end
        master_aw_fire_w = m_awvalid_i & awready_w;
    end
    assign m_awready_o = awready_w;

    reg protocol_error_r;
    assign protocol_error_o = protocol_error_r;

    integer seq_m_i;
    integer seq_s_i;
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            awbuf_valid_r <= {NUM_M{1'b0}};
            awbuf_legal_r <= {NUM_M{1'b0}};
            route_valid_r <= {SLOT_COUNT{1'b0}};
            free_head_r <= {S_ID_W{1'b0}};
            free_tail_r <= {S_ID_W{1'b0}};
            free_count_r <= FREE_COUNT_LIMIT;
            order_error_r <= {ORDER_DEPTH{1'b0}};
            order_head_r <= {ORDER_PTR_W{1'b0}};
            order_tail_r <= {ORDER_PTR_W{1'b0}};
            order_count_r <= {ORDER_CNT_W{1'b0}};
            w_beat_r <= {LEN_W{1'b0}};
            bbuf_valid_r <= {NUM_M{1'b0}};
            protocol_error_r <= 1'b0;
            for (seq_m_i = 0; seq_m_i < NUM_M; seq_m_i = seq_m_i + 1) begin
                outstanding_r[seq_m_i] <= {COUNT_W{1'b0}};
                local_id_busy_r[seq_m_i] <= {LOCAL_ID_COUNT{1'b0}};
                bbuf_id_r[seq_m_i] <= {ID_W{1'b0}};
                bbuf_resp_r[seq_m_i] <= 2'b00;
            end
            for (seq_s_i = 0; seq_s_i < SLOT_COUNT; seq_s_i = seq_s_i + 1) begin
                free_id_r[seq_s_i] <= seq_s_i[S_ID_W-1:0];
                route_master_r[seq_s_i] <= {MI_W{1'b0}};
                route_local_id_r[seq_s_i] <= {ID_W{1'b0}};
            end
            for (seq_s_i = 0; seq_s_i < ORDER_DEPTH; seq_s_i = seq_s_i + 1) begin
                order_master_r[seq_s_i] <= {MI_W{1'b0}};
                order_local_id_r[seq_s_i] <= {ID_W{1'b0}};
                order_len_r[seq_s_i] <= {LEN_W{1'b0}};
            end
        end else begin
            if (route_alloc_w)
                free_head_r <= free_head_r + 1'b1;
            if (route_release_w) begin
                free_id_r[free_tail_r] <= s_bid_i;
                free_tail_r <= free_tail_r + 1'b1;
            end

            case ({route_alloc_w, route_release_w})
                2'b10: free_count_r <= free_count_r - 1'b1;
                2'b01: free_count_r <= free_count_r + 1'b1;
                default: free_count_r <= free_count_r;
            endcase

            for (seq_m_i = 0; seq_m_i < NUM_M; seq_m_i = seq_m_i + 1) begin
                if (master_aw_fire_w[seq_m_i]) begin
                    awbuf_valid_r[seq_m_i] <= 1'b1;
                    awbuf_id_r[seq_m_i] <= m_awid_i[seq_m_i*ID_W +: ID_W];
                    awbuf_addr_r[seq_m_i] <= m_awaddr_i[seq_m_i*ADDR_W +: ADDR_W];
                    awbuf_len_r[seq_m_i] <= m_awlen_i[seq_m_i*LEN_W +: LEN_W];
                    awbuf_size_r[seq_m_i] <= m_awsize_i[seq_m_i*3 +: 3];
                    awbuf_burst_r[seq_m_i] <= m_awburst_i[seq_m_i*2 +: 2];
                    awbuf_qos_r[seq_m_i] <= m_awqos_i[seq_m_i*4 +: 4];
                    awbuf_legal_r[seq_m_i] <= incoming_legal_w[seq_m_i];
                end else if (awbuf_pop_w[seq_m_i]) begin
                    awbuf_valid_r[seq_m_i] <= 1'b0;
                end

                outstanding_r[seq_m_i] <= outstanding_r[seq_m_i]
                    + {{(COUNT_W-1){1'b0}}, master_aw_fire_w[seq_m_i]}
                    - {{(COUNT_W-1){1'b0}}, master_b_fire_w[seq_m_i]};

                if (master_b_fire_w[seq_m_i])
                    local_id_busy_r[seq_m_i][bbuf_id_r[seq_m_i]] <= 1'b0;
                if (master_aw_fire_w[seq_m_i])
                    local_id_busy_r[seq_m_i]
                        [m_awid_i[seq_m_i*ID_W +: ID_W]] <= 1'b1;

                if (slave_b_push_w[seq_m_i]) begin
                    bbuf_valid_r[seq_m_i] <= 1'b1;
                    bbuf_id_r[seq_m_i] <= response_local_id_w;
                    bbuf_resp_r[seq_m_i] <= s_bresp_i;
                end else if (error_b_push_w[seq_m_i]) begin
                    bbuf_valid_r[seq_m_i] <= 1'b1;
                    bbuf_id_r[seq_m_i] <= order_local_id_w;
                    bbuf_resp_r[seq_m_i] <= RESP_DECERR;
                end else if (master_b_fire_w[seq_m_i]) begin
                    bbuf_valid_r[seq_m_i] <= 1'b0;
                end
            end

            // Route allocation follows a real downstream AW handshake.
            if (route_alloc_w) begin
                route_valid_r[free_index_w] <= 1'b1;
                route_master_r[free_index_w] <= sched_index_w;
                route_local_id_r[free_index_w] <= awbuf_id_r[sched_index_w];
            end
            if (s_bvalid_i && s_bready_o) begin
                route_valid_r[s_bid_i] <= 1'b0;
            end
            else if (s_bvalid_i && !response_route_valid_w)
                protocol_error_r <= 1'b1;

            // Push and pop may coincide; the count expression preserves full
            // throughput and avoids the double-nonblocking-assignment bug.
            order_count_r <= order_count_r
                + {{(ORDER_CNT_W-1){1'b0}}, sched_fire_w}
                - {{(ORDER_CNT_W-1){1'b0}}, order_pop_w};
            if (sched_fire_w) begin
                order_master_r[order_tail_r] <= sched_index_w;
                order_local_id_r[order_tail_r] <= awbuf_id_r[sched_index_w];
                order_len_r[order_tail_r] <= awbuf_len_r[sched_index_w];
                order_error_r[order_tail_r] <= selected_error_w;
                order_tail_r <= (order_tail_r == ORDER_LAST)
                    ? {ORDER_PTR_W{1'b0}} : order_tail_r + 1'b1;
            end
            if (order_pop_w) begin
                order_head_r <= (order_head_r == ORDER_LAST)
                    ? {ORDER_PTR_W{1'b0}} : order_head_r + 1'b1;
                w_beat_r <= {LEN_W{1'b0}};
            end else if (selected_w_fire_w) begin
                w_beat_r <= w_beat_r + 1'b1;
            end

            if (selected_w_fire_w &&
                (m_wlast_i[order_master_w] != expected_last_w))
                protocol_error_r <= 1'b1;
        end
    end

endmodule
