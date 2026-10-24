// ============================================================================
// File        : edrv32_axi_m2s_read.v
// Description : Generic multi-master, single-slave AXI4 read fabric. It
//               provides one-entry AR ingress buffers,
//               burst scheduling, finite downstream-ID remapping, per-master
//               response buffers, credit throttling and inline DECERR replies.
// Notes       : Byte addresses and aligned full-width INCR bursts are
//               supported. Target-specific limits belong in slave adapters.
// ============================================================================

module edrv32_axi_m2s_read #(
    parameter integer NUM_M = 4,
    parameter integer ADDR_W = 32,
    parameter integer DATA_W = 256,
    parameter integer ID_W = 4,
    parameter integer S_ID_W = 4,
    parameter integer LEN_W = 8,
    parameter integer STARVE_CYCLES = 64,
    parameter integer INGRESS_READY_BYPASS = 1,
    parameter integer MI_W = (NUM_M <= 1) ? 1 : $clog2(NUM_M),
    parameter integer COUNT_W = S_ID_W + 1
) (
    input  wire                         clk_i,
    input  wire                         rst_n_i,
    input  wire                         accept_i,

    input  wire [NUM_M*ID_W-1:0]        m_arid_i,
    input  wire [NUM_M*ADDR_W-1:0]      m_araddr_i,
    input  wire [NUM_M*LEN_W-1:0]       m_arlen_i,
    input  wire [NUM_M*3-1:0]           m_arsize_i,
    input  wire [NUM_M*2-1:0]           m_arburst_i,
    input  wire [NUM_M*4-1:0]           m_arqos_i,
    input  wire [NUM_M-1:0]             m_arvalid_i,
    output wire [NUM_M-1:0]             m_arready_o,

    output wire [NUM_M*ID_W-1:0]        m_rid_o,
    output wire [NUM_M*DATA_W-1:0]      m_rdata_o,
    output wire [NUM_M*2-1:0]           m_rresp_o,
    output wire [NUM_M-1:0]             m_rlast_o,
    output wire [NUM_M-1:0]             m_rvalid_o,
    input  wire [NUM_M-1:0]             m_rready_i,

    input  wire [NUM_M-1:0]             m_read_urgent_i,
    input  wire [NUM_M*4-1:0]           m_read_weight_i,
    input  wire [NUM_M*5-1:0]           m_read_credit_i,
    output wire [S_ID_W-1:0]            s_arid_o,
    output wire [ADDR_W-1:0]            s_araddr_o,
    output wire [LEN_W-1:0]             s_arlen_o,
    output wire [2:0]                   s_arsize_o,
    output wire [1:0]                   s_arburst_o,
    output wire [3:0]                   s_arqos_o,
    output wire                         s_arvalid_o,
    input  wire                         s_arready_i,

    input  wire [S_ID_W-1:0]            s_rid_i,
    input  wire [DATA_W-1:0]            s_rdata_i,
    input  wire [1:0]                   s_rresp_i,
    input  wire                         s_rlast_i,
    input  wire                         s_rvalid_i,
    output wire                         s_rready_o,

    output wire [NUM_M*COUNT_W-1:0]     outstanding_o,
    output wire                         protocol_error_o
);

    localparam integer STRB_W = DATA_W / 8;
    localparam integer SIZE_CODE = $clog2(STRB_W);
    localparam integer SLOT_COUNT = (1 << S_ID_W);
    localparam integer LOCAL_ID_COUNT = (1 << ID_W);
    localparam [1:0] RESP_DECERR = 2'b11;
    localparam [S_ID_W:0] FREE_COUNT_LIMIT = SLOT_COUNT[S_ID_W:0];

    // One registered address slot per master. Pop+push in one cycle sustains
    // one accepted AR per cycle without a transparent master-to-slave path.
    reg [NUM_M-1:0] arbuf_valid_r;
    reg [ID_W-1:0] arbuf_id_r [0:NUM_M-1];
    reg [ADDR_W-1:0] arbuf_addr_r [0:NUM_M-1];
    reg [LEN_W-1:0] arbuf_len_r [0:NUM_M-1];
    reg [2:0] arbuf_size_r [0:NUM_M-1];
    reg [1:0] arbuf_burst_r [0:NUM_M-1];
    reg [3:0] arbuf_qos_r [0:NUM_M-1];
    reg [NUM_M-1:0] arbuf_legal_r;

    reg [COUNT_W-1:0] outstanding_r [0:NUM_M-1];
    reg [LOCAL_ID_COUNT-1:0] local_id_busy_r [0:NUM_M-1];

    // The DDR-side ID is a finite route-table index, not a concatenation of
    // master and local ID. This preserves all four local ID bits for every
    // master while matching the controller's four-bit ID port.
    reg [SLOT_COUNT-1:0] route_valid_r;
    reg [MI_W-1:0] route_master_r [0:SLOT_COUNT-1];
    reg [ID_W-1:0] route_local_id_r [0:SLOT_COUNT-1];
    reg [LEN_W-1:0] route_left_r [0:SLOT_COUNT-1];

    wire route_release_w = s_rvalid_i && s_rready_o && s_rlast_i;

    // A registered free-ID queue keeps response retirement out of the AR
    // scheduling path. One ID can be returned and another allocated each
    // cycle, so steady-state command throughput remains one request/cycle.
    reg [S_ID_W-1:0] free_id_r [0:SLOT_COUNT-1];
    reg [S_ID_W-1:0] free_head_r;
    reg [S_ID_W-1:0] free_tail_r;
    reg [S_ID_W:0] free_count_r;

    wire free_valid_w = free_count_r != 0;
    wire [S_ID_W-1:0] free_index_w = free_id_r[free_head_r];

    // Invalid requests are converted into correctly sized DECERR bursts.
    reg [NUM_M-1:0] err_valid_r;
    reg [ID_W-1:0] err_id_r [0:NUM_M-1];
    reg [LEN_W-1:0] err_left_r [0:NUM_M-1];

    reg [NUM_M-1:0] sched_req_w;
    reg [NUM_M*4-1:0] sched_qos_w;
    integer req_i;
    always @(*) begin
        sched_req_w = {NUM_M{1'b0}};
        sched_qos_w = {NUM_M*4{1'b0}};
        for (req_i = 0; req_i < NUM_M; req_i = req_i + 1) begin
            sched_req_w[req_i] = arbuf_valid_r[req_i] &&
                (arbuf_legal_r[req_i] ? free_valid_w : !err_valid_r[req_i]);
            sched_qos_w[req_i*4 +: 4] = arbuf_qos_r[req_i];
        end
    end

    wire [NUM_M-1:0] sched_grant_w;
    wire sched_valid_w;
    wire [MI_W-1:0] sched_index_w;
    wire selected_legal_w = sched_valid_w && arbuf_legal_r[sched_index_w];
    wire selected_error_w = sched_valid_w && !arbuf_legal_r[sched_index_w];
    wire sched_fire_w = sched_valid_w &&
        (selected_error_w || (selected_legal_w && s_arready_i));
    wire route_alloc_w = sched_fire_w && selected_legal_w;

    edrv32_axi_m2s_arbiter #(
        .NUM_M(NUM_M),
        .STARVE_CYCLES(STARVE_CYCLES),
        .MI_W(MI_W)
    ) u_read_arbiter (
        .clk_i(clk_i),
        .rst_n_i(rst_n_i),
        .req_i(sched_req_w),
        .qos_i(sched_qos_w),
        .weight_i(m_read_weight_i),
        .urgent_i(m_read_urgent_i),
        .grant_o(sched_grant_w),
        .grant_valid_o(sched_valid_w),
        .grant_index_o(sched_index_w),
        .fire_i(sched_fire_w)
    );

    assign s_arid_o = free_index_w;
    assign s_araddr_o = sched_valid_w ? arbuf_addr_r[sched_index_w] : {ADDR_W{1'b0}};
    assign s_arlen_o = sched_valid_w ? arbuf_len_r[sched_index_w] : {LEN_W{1'b0}};
    assign s_arsize_o = sched_valid_w ? arbuf_size_r[sched_index_w] : 3'b000;
    assign s_arburst_o = sched_valid_w ? arbuf_burst_r[sched_index_w] : 2'b00;
    assign s_arqos_o = sched_valid_w ? arbuf_qos_r[sched_index_w] : 4'b0000;
    assign s_arvalid_o = selected_legal_w;

    wire [NUM_M-1:0] arbuf_pop_w = sched_grant_w & {NUM_M{sched_fire_w}};

    // Per-master one-beat response buffers form the timing boundary promised
    // by the DDR fabric architecture while retaining one beat/cycle throughput.
    reg [NUM_M-1:0] rbuf_valid_r;
    reg [ID_W-1:0] rbuf_id_r [0:NUM_M-1];
    reg [DATA_W-1:0] rbuf_data_r [0:NUM_M-1];
    reg [1:0] rbuf_resp_r [0:NUM_M-1];
    reg [NUM_M-1:0] rbuf_last_r;

    wire response_route_valid_w = route_valid_r[s_rid_i];
    wire [MI_W-1:0] response_master_w = route_master_r[s_rid_i];
    wire [ID_W-1:0] response_local_id_w = route_local_id_r[s_rid_i];

    reg [NUM_M-1:0] rbuf_ready_w;
    reg [NUM_M-1:0] slave_push_w;
    reg [NUM_M-1:0] error_push_w;
    integer rsp_i;
    always @(*) begin
        rbuf_ready_w = {NUM_M{1'b0}};
        slave_push_w = {NUM_M{1'b0}};
        error_push_w = {NUM_M{1'b0}};
        for (rsp_i = 0; rsp_i < NUM_M; rsp_i = rsp_i + 1) begin
            rbuf_ready_w[rsp_i] = !rbuf_valid_r[rsp_i] ||
                (m_rready_i[rsp_i] && rbuf_valid_r[rsp_i]);
            if (s_rvalid_i && response_route_valid_w &&
                (response_master_w == rsp_i[MI_W-1:0]) &&
                rbuf_ready_w[rsp_i])
                slave_push_w[rsp_i] = 1'b1;
            if (err_valid_r[rsp_i] && rbuf_ready_w[rsp_i] &&
                !slave_push_w[rsp_i])
                error_push_w[rsp_i] = 1'b1;
        end
    end

    assign s_rready_o = response_route_valid_w &&
        rbuf_ready_w[response_master_w];

    genvar out_g;
    generate
        for (out_g = 0; out_g < NUM_M; out_g = out_g + 1) begin : gen_read_outputs
            assign m_rid_o[out_g*ID_W +: ID_W] = rbuf_id_r[out_g];
            assign m_rdata_o[out_g*DATA_W +: DATA_W] = rbuf_data_r[out_g];
            assign m_rresp_o[out_g*2 +: 2] = rbuf_resp_r[out_g];
            assign m_rlast_o[out_g] = rbuf_last_r[out_g];
            assign m_rvalid_o[out_g] = rbuf_valid_r[out_g];
            assign outstanding_o[out_g*COUNT_W +: COUNT_W] = outstanding_r[out_g];
        end
    endgenerate

    wire [NUM_M-1:0] master_r_fire_w = rbuf_valid_r & m_rready_i;
    wire [NUM_M-1:0] master_r_last_fire_w = master_r_fire_w & rbuf_last_r;

    reg [NUM_M-1:0] arready_w;
    reg [NUM_M-1:0] master_ar_fire_w;
    reg [NUM_M-1:0] incoming_legal_w;
    reg [4:0] credit_limit_w;
    reg [12:0] byte_span_w;
    reg id_released_w;
    integer adm_i;
    always @(*) begin
        arready_w = {NUM_M{1'b0}};
        incoming_legal_w = {NUM_M{1'b0}};
        for (adm_i = 0; adm_i < NUM_M; adm_i = adm_i + 1) begin
            credit_limit_w = m_read_credit_i[adm_i*5 +: 5];
            if (credit_limit_w == 0)
                credit_limit_w = 5'd1;
            byte_span_w = ({5'b0, m_arlen_i[adm_i*LEN_W +: LEN_W]} + 1'b1)
                << SIZE_CODE;
            id_released_w = master_r_last_fire_w[adm_i] &&
                (rbuf_id_r[adm_i] == m_arid_i[adm_i*ID_W +: ID_W]);

            incoming_legal_w[adm_i] =
                (m_arsize_i[adm_i*3 +: 3] == SIZE_CODE[2:0]) &&
                (m_arburst_i[adm_i*2 +: 2] == 2'b01) &&
                (m_araddr_i[adm_i*ADDR_W +: ADDR_W] & (STRB_W-1)) == 0 &&
                ({1'b0, m_araddr_i[adm_i*ADDR_W +: 12]} + byte_span_w <= 13'd4096);

            arready_w[adm_i] = accept_i &&
                (!arbuf_valid_r[adm_i] ||
                 (INGRESS_READY_BYPASS && arbuf_pop_w[adm_i])) &&
                ((outstanding_r[adm_i] < credit_limit_w) ||
                 master_r_last_fire_w[adm_i]) &&
                (!local_id_busy_r[adm_i][m_arid_i[adm_i*ID_W +: ID_W]] ||
                 id_released_w);
        end
        master_ar_fire_w = m_arvalid_i & arready_w;
    end
    assign m_arready_o = arready_w;

    reg protocol_error_r;
    assign protocol_error_o = protocol_error_r;

    integer seq_m_i;
    integer seq_s_i;
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            arbuf_valid_r <= {NUM_M{1'b0}};
            arbuf_legal_r <= {NUM_M{1'b0}};
            err_valid_r <= {NUM_M{1'b0}};
            rbuf_valid_r <= {NUM_M{1'b0}};
            rbuf_last_r <= {NUM_M{1'b0}};
            route_valid_r <= {SLOT_COUNT{1'b0}};
            free_head_r <= {S_ID_W{1'b0}};
            free_tail_r <= {S_ID_W{1'b0}};
            free_count_r <= FREE_COUNT_LIMIT;
            protocol_error_r <= 1'b0;
            for (seq_m_i = 0; seq_m_i < NUM_M; seq_m_i = seq_m_i + 1) begin
                outstanding_r[seq_m_i] <= {COUNT_W{1'b0}};
                local_id_busy_r[seq_m_i] <= {LOCAL_ID_COUNT{1'b0}};
                err_id_r[seq_m_i] <= {ID_W{1'b0}};
                err_left_r[seq_m_i] <= {LEN_W{1'b0}};
                rbuf_id_r[seq_m_i] <= {ID_W{1'b0}};
                rbuf_data_r[seq_m_i] <= {DATA_W{1'b0}};
                rbuf_resp_r[seq_m_i] <= 2'b00;
            end
            for (seq_s_i = 0; seq_s_i < SLOT_COUNT; seq_s_i = seq_s_i + 1) begin
                free_id_r[seq_s_i] <= seq_s_i[S_ID_W-1:0];
                route_master_r[seq_s_i] <= {MI_W{1'b0}};
                route_local_id_r[seq_s_i] <= {ID_W{1'b0}};
                route_left_r[seq_s_i] <= {LEN_W{1'b0}};
            end
        end else begin
            if (route_alloc_w)
                free_head_r <= free_head_r + 1'b1;
            if (route_release_w) begin
                free_id_r[free_tail_r] <= s_rid_i;
                free_tail_r <= free_tail_r + 1'b1;
            end

            case ({route_alloc_w, route_release_w})
                2'b10: free_count_r <= free_count_r - 1'b1;
                2'b01: free_count_r <= free_count_r + 1'b1;
                default: free_count_r <= free_count_r;
            endcase

            for (seq_m_i = 0; seq_m_i < NUM_M; seq_m_i = seq_m_i + 1) begin
                if (master_ar_fire_w[seq_m_i]) begin
                    arbuf_valid_r[seq_m_i] <= 1'b1;
                    arbuf_id_r[seq_m_i] <= m_arid_i[seq_m_i*ID_W +: ID_W];
                    arbuf_addr_r[seq_m_i] <= m_araddr_i[seq_m_i*ADDR_W +: ADDR_W];
                    arbuf_len_r[seq_m_i] <= m_arlen_i[seq_m_i*LEN_W +: LEN_W];
                    arbuf_size_r[seq_m_i] <= m_arsize_i[seq_m_i*3 +: 3];
                    arbuf_burst_r[seq_m_i] <= m_arburst_i[seq_m_i*2 +: 2];
                    arbuf_qos_r[seq_m_i] <= m_arqos_i[seq_m_i*4 +: 4];
                    arbuf_legal_r[seq_m_i] <= incoming_legal_w[seq_m_i];
                end else if (arbuf_pop_w[seq_m_i]) begin
                    arbuf_valid_r[seq_m_i] <= 1'b0;
                end

                outstanding_r[seq_m_i] <= outstanding_r[seq_m_i]
                    + {{(COUNT_W-1){1'b0}}, master_ar_fire_w[seq_m_i]}
                    - {{(COUNT_W-1){1'b0}}, master_r_last_fire_w[seq_m_i]};

                if (master_r_last_fire_w[seq_m_i])
                    local_id_busy_r[seq_m_i][rbuf_id_r[seq_m_i]] <= 1'b0;
                if (master_ar_fire_w[seq_m_i])
                    local_id_busy_r[seq_m_i]
                        [m_arid_i[seq_m_i*ID_W +: ID_W]] <= 1'b1;

                if (sched_fire_w && selected_error_w &&
                    sched_grant_w[seq_m_i]) begin
                    err_valid_r[seq_m_i] <= 1'b1;
                    err_id_r[seq_m_i] <= arbuf_id_r[seq_m_i];
                    err_left_r[seq_m_i] <= arbuf_len_r[seq_m_i];
                end else if (error_push_w[seq_m_i]) begin
                    if (err_left_r[seq_m_i] == 0)
                        err_valid_r[seq_m_i] <= 1'b0;
                    else
                        err_left_r[seq_m_i] <= err_left_r[seq_m_i] - 1'b1;
                end

                if (slave_push_w[seq_m_i]) begin
                    rbuf_valid_r[seq_m_i] <= 1'b1;
                    rbuf_id_r[seq_m_i] <= response_local_id_w;
                    rbuf_data_r[seq_m_i] <= s_rdata_i;
                    rbuf_resp_r[seq_m_i] <= s_rresp_i;
                    rbuf_last_r[seq_m_i] <= s_rlast_i;
                end else if (error_push_w[seq_m_i]) begin
                    rbuf_valid_r[seq_m_i] <= 1'b1;
                    rbuf_id_r[seq_m_i] <= err_id_r[seq_m_i];
                    rbuf_data_r[seq_m_i] <= {DATA_W{1'b0}};
                    rbuf_resp_r[seq_m_i] <= RESP_DECERR;
                    rbuf_last_r[seq_m_i] <= (err_left_r[seq_m_i] == 0);
                end else if (master_r_fire_w[seq_m_i]) begin
                    rbuf_valid_r[seq_m_i] <= 1'b0;
                end
            end

            if (route_alloc_w) begin
                route_valid_r[free_index_w] <= 1'b1;
                route_master_r[free_index_w] <= sched_index_w;
                route_local_id_r[free_index_w] <= arbuf_id_r[sched_index_w];
                route_left_r[free_index_w] <= arbuf_len_r[sched_index_w];
            end

            if (s_rvalid_i && s_rready_o) begin
                if (s_rlast_i != (route_left_r[s_rid_i] == 0))
                    protocol_error_r <= 1'b1;
                if (s_rlast_i) begin
                    route_valid_r[s_rid_i] <= 1'b0;
                end else if (route_left_r[s_rid_i] != 0) begin
                    route_left_r[s_rid_i] <= route_left_r[s_rid_i] - 1'b1;
                end
            end else if (s_rvalid_i && !response_route_valid_w) begin
                protocol_error_r <= 1'b1;
            end
        end
    end

endmodule
