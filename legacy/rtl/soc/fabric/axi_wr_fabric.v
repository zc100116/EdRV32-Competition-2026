// ============================================================================
// File        : axi_wr_fabric.v
// Author      : Edward ZC
// Description : Parameterised NUM_M x NUM_S AXI4 write crossbar (design §6.3).
//               AXI4 has no WID, so each slave consumes W beats strictly in
//               its AW-acceptance order: every slave keeps an AW order queue
//               and every master keeps a FIFO of unfinished AW targets; W is
//               forwarded only when both heads name the same master/slave
//               pair. B responses are routed by the global BID independently
//               and may complete in any order across IDs.  When each master
//               permits only one outstanding write, the accepted AW target is
//               retained as a one-entry response route table so unrelated
//               slave B channels do not enter the response arbitration cone.
// Notes       : Verilog-2001. Decode miss / overlap / disconnected targets go
//               to an inline responder that accepts AW, drains the W burst to
//               WLAST and returns one DECERR B; error writes are one per
//               master (admission gated) and still occupy the master's W
//               order FIFO, so master W streams stay correctly ordered.
// ============================================================================
`include "edrv32_axi4.vh"

module axi_wr_fabric #(
    parameter NUM_M   = 2,
    parameter NUM_S   = 5,
    parameter ADDR_W  = 32,
    parameter DATA_W  = 32,
    parameter STRB_W  = 4,
    parameter ID_W    = 4,          // master-local ID width
    parameter LEN_W   = 8,
    parameter SIZE_W  = 3,
    parameter BURST_W = 2,
    parameter RESP_W  = 2,
    parameter GID_W   = ID_W + ((NUM_M <= 1) ? 1 : $clog2(NUM_M)),
    parameter M_MAX_OUTSTANDING = 4,
    parameter S_MAX_WR = 8,
    parameter WR_TIMEOUT_CYCLES = 0,   // 0 = disabled (fail-stop watchdog)
    parameter AXI_MON_ENABLE = 0
)(
    // --- Clock and reset ---
    input  wire                         clk,
    input  wire                         rst_n,

    // --- Master-side write address channels (ID is local) ---
    input  wire [NUM_M*ID_W-1:0]        m_awid_i,
    input  wire [NUM_M*ADDR_W-1:0]      m_awaddr_i,
    input  wire [NUM_M*LEN_W-1:0]       m_awlen_i,
    input  wire [NUM_M*SIZE_W-1:0]      m_awsize_i,
    input  wire [NUM_M*BURST_W-1:0]     m_awburst_i,
    input  wire [NUM_M-1:0]             m_awvalid_i,
    output reg  [NUM_M-1:0]             m_awready_o,

    // --- Master-side write data channels ---
    input  wire [NUM_M*DATA_W-1:0]      m_wdata_i,
    input  wire [NUM_M*STRB_W-1:0]      m_wstrb_i,
    input  wire [NUM_M-1:0]             m_wlast_i,
    input  wire [NUM_M-1:0]             m_wvalid_i,
    output reg  [NUM_M-1:0]             m_wready_o,

    // --- Master-side write response channels (ID is local) ---
    output reg  [NUM_M*ID_W-1:0]        m_bid_o,
    output reg  [NUM_M*RESP_W-1:0]      m_bresp_o,
    output reg  [NUM_M-1:0]             m_bvalid_o,
    input  wire [NUM_M-1:0]             m_bready_i,

    // --- Address map and master/slave connectivity ---
    input  wire [NUM_S*ADDR_W-1:0]      s_base_i,
    input  wire [NUM_S*ADDR_W-1:0]      s_limit_i,
    input  wire [NUM_M*NUM_S-1:0]       m_write_connect_i,

    // --- Slave-side write address channels (ID is global) ---
    output reg  [NUM_S*GID_W-1:0]       s_awid_o,
    output reg  [NUM_S*ADDR_W-1:0]      s_awaddr_o,
    output reg  [NUM_S*LEN_W-1:0]       s_awlen_o,
    output reg  [NUM_S*SIZE_W-1:0]      s_awsize_o,
    output reg  [NUM_S*BURST_W-1:0]     s_awburst_o,
    output reg  [NUM_S-1:0]             s_awvalid_o,
    input  wire [NUM_S-1:0]             s_awready_i,

    // --- Slave-side write data channels ---
    output reg  [NUM_S*DATA_W-1:0]      s_wdata_o,
    output reg  [NUM_S*STRB_W-1:0]      s_wstrb_o,
    output reg  [NUM_S-1:0]             s_wlast_o,
    output reg  [NUM_S-1:0]             s_wvalid_o,
    input  wire [NUM_S-1:0]             s_wready_i,

    // --- Slave-side write response channels (ID is global) ---
    input  wire [NUM_S*GID_W-1:0]       s_bid_i,
    input  wire [NUM_S*RESP_W-1:0]      s_bresp_i,
    input  wire [NUM_S-1:0]             s_bvalid_i,
    output reg  [NUM_S-1:0]             s_bready_o,

    // --- Fail-stop timeout status (sticky until reset; no fake responses) ---
    output wire [NUM_M-1:0]             fs_wr_fail_o,
    output wire [NUM_M*ADDR_W-1:0]      fs_wr_addr_o,
    output wire [NUM_M*ID_W-1:0]        fs_wr_id_o,

    // --- AXI monitor (all-zero when AXI_MON_ENABLE=0) ---
    output wire [NUM_M*32-1:0]          mon_wr_beats_o,
    output wire [NUM_M*32-1:0]          mon_wr_bursts_o,
    output wire [NUM_M*32-1:0]          mon_wr_err_o,
    output wire [NUM_M*32-1:0]          mon_wr_maxwait_o
);

    function integer clog2;
        input integer value;
        integer value_i;
        begin
            value_i = value - 1;
            for (clog2 = 0; value_i > 0; clog2 = clog2 + 1)
                value_i = value_i >> 1;
        end
    endfunction

    localparam MI_W  = (NUM_M <= 1) ? 1 : clog2(NUM_M);
    localparam TGT_W = clog2(NUM_S + 1);                 // slave idx or ERROR
    localparam [TGT_W-1:0] TGT_ERROR = NUM_S;
    localparam CNT_W = clog2(M_MAX_OUTSTANDING + 1);
    localparam MP_W  = (M_MAX_OUTSTANDING <= 1) ? 1 : clog2(M_MAX_OUTSTANDING);
    localparam SP_W  = (S_MAX_WR <= 1) ? 1 : clog2(S_MAX_WR);
    localparam SC_W  = clog2(S_MAX_WR + 1);
    localparam SRC_W = clog2(NUM_S + 1);                 // B source select
    localparam [SRC_W-1:0] SRC_ERROR = NUM_S;
    localparam [CNT_W-1:0] M_MAX_L = M_MAX_OUTSTANDING;
    localparam [SC_W-1:0]  S_MAX_L = S_MAX_WR;
    localparam [MP_W-1:0]  M_LAST_PTR =
        M_MAX_OUTSTANDING[MP_W-1:0] - {{(MP_W-1){1'b0}}, 1'b1};
    localparam [SP_W-1:0]  S_LAST_PTR =
        S_MAX_WR[SP_W-1:0] - {{(SP_W-1){1'b0}}, 1'b1};
    localparam [MI_W-1:0]  M_LAST_IDX =
        NUM_M[MI_W-1:0] - {{(MI_W-1){1'b0}}, 1'b1};

    // Encoded master index per master (global ID high bits).
    wire [NUM_M*MI_W-1:0] m_idx_enc_w;
    genvar midx_g;
    generate
        for (midx_g = 0; midx_g < NUM_M; midx_g = midx_g + 1) begin : gen_midx
            assign m_idx_enc_w[midx_g*MI_W +: MI_W] = midx_g;
        end
    endgenerate

    // ========================================================================
    // Address decode: exactly one connected hit, else inline DECERR target.
    // ========================================================================
    reg [NUM_S-1:0]   hit_oh_r    [0:NUM_M-1];
    reg [NUM_M-1:0]   hit_unique_r;
    reg [TGT_W-1:0]   hit_tgt_r   [0:NUM_M-1];
    integer dec_m_i;
    integer dec_s_i;

    always @* begin
        for (dec_m_i = 0; dec_m_i < NUM_M; dec_m_i = dec_m_i + 1) begin
            hit_oh_r[dec_m_i] = {NUM_S{1'b0}};
            for (dec_s_i = 0; dec_s_i < NUM_S; dec_s_i = dec_s_i + 1) begin
                // See axi_rd_fabric: base > limit is a wrap-through-zero
                // interval, while base == limit is deliberately empty.
                if (m_write_connect_i[dec_m_i*NUM_S + dec_s_i] &&
                    (((s_base_i[dec_s_i*ADDR_W +: ADDR_W] <
                       s_limit_i[dec_s_i*ADDR_W +: ADDR_W]) &&
                      (m_awaddr_i[dec_m_i*ADDR_W +: ADDR_W] >=
                       s_base_i[dec_s_i*ADDR_W +: ADDR_W]) &&
                      (m_awaddr_i[dec_m_i*ADDR_W +: ADDR_W] <
                       s_limit_i[dec_s_i*ADDR_W +: ADDR_W])) ||
                     ((s_base_i[dec_s_i*ADDR_W +: ADDR_W] >
                       s_limit_i[dec_s_i*ADDR_W +: ADDR_W]) &&
                      ((m_awaddr_i[dec_m_i*ADDR_W +: ADDR_W] >=
                        s_base_i[dec_s_i*ADDR_W +: ADDR_W]) ||
                       (m_awaddr_i[dec_m_i*ADDR_W +: ADDR_W] <
                        s_limit_i[dec_s_i*ADDR_W +: ADDR_W])))))
                    hit_oh_r[dec_m_i][dec_s_i] = 1'b1;
            end
            hit_unique_r[dec_m_i] = (|hit_oh_r[dec_m_i]) &&
                ((hit_oh_r[dec_m_i] & (hit_oh_r[dec_m_i] - 1'b1)) == {NUM_S{1'b0}});
            hit_tgt_r[dec_m_i] = TGT_ERROR;
            if (hit_unique_r[dec_m_i]) begin
                for (dec_s_i = 0; dec_s_i < NUM_S; dec_s_i = dec_s_i + 1)
                    if (hit_oh_r[dec_m_i][dec_s_i])
                        hit_tgt_r[dec_m_i] = dec_s_i[TGT_W-1:0];
            end
        end
    end

    // ========================================================================
    // Per-master state: outstanding count and W-order FIFO of unfinished AWs.
    // ========================================================================
    reg [CNT_W-1:0] wr_cnt_r [0:NUM_M-1];

    // One-entry B route table used by the single-outstanding specialization.
    // It remains live after WLAST until the corresponding B is accepted.
    reg [NUM_S-1:0] single_b_owner_oh_r [0:NUM_M-1];
    reg [ID_W-1:0]  single_b_owner_id_r [0:NUM_M-1];

    reg [M_MAX_OUTSTANDING*TGT_W-1:0] mq_tgt_r [0:NUM_M-1];
    reg [M_MAX_OUTSTANDING*ID_W-1:0]  mq_id_r  [0:NUM_M-1];
    reg [MP_W-1:0]  mq_head_r [0:NUM_M-1];
    reg [MP_W-1:0]  mq_tail_r [0:NUM_M-1];
    reg [CNT_W-1:0] mq_cnt_r  [0:NUM_M-1];

    // ========================================================================
    // Per-slave state: AW order queue of master indices (W owner = head).
    // ========================================================================
    reg [S_MAX_WR*MI_W-1:0] sq_m_r [0:NUM_S-1];
    reg [SP_W-1:0]  sq_head_r [0:NUM_S-1];
    reg [SP_W-1:0]  sq_tail_r [0:NUM_S-1];
    reg [SC_W-1:0]  sq_cnt_r  [0:NUM_S-1];

    // Per-master inline DECERR write responder state.
    reg               errw_active_r  [0:NUM_M-1];  // AW accepted .. B accepted
    reg               errb_pending_r [0:NUM_M-1];  // W drained, B to present
    reg [ID_W-1:0]    errb_id_r      [0:NUM_M-1];

    // Combinational head reads.
    reg [TGT_W-1:0] mq_head_tgt_w [0:NUM_M-1];
    reg [ID_W-1:0]  mq_head_id_w  [0:NUM_M-1];
    reg [MI_W-1:0]  sq_head_m_w   [0:NUM_S-1];
    integer hd_m_i;
    always @* begin
        for (hd_m_i = 0; hd_m_i < NUM_M; hd_m_i = hd_m_i + 1) begin
            if (mq_cnt_r[hd_m_i] != 0) begin
                mq_head_tgt_w[hd_m_i] =
                    mq_tgt_r[hd_m_i][mq_head_r[hd_m_i]*TGT_W +: TGT_W];
                mq_head_id_w[hd_m_i] =
                    mq_id_r[hd_m_i][mq_head_r[hd_m_i]*ID_W +: ID_W];
            end else begin
                mq_head_tgt_w[hd_m_i] = TGT_ERROR;
                mq_head_id_w[hd_m_i]  = {ID_W{1'b0}};
            end
        end
    end
    integer hd_s_i;
    always @* begin
        for (hd_s_i = 0; hd_s_i < NUM_S; hd_s_i = hd_s_i + 1) begin
            if (sq_cnt_r[hd_s_i] != 0)
                sq_head_m_w[hd_s_i] =
                    sq_m_r[hd_s_i][sq_head_r[hd_s_i]*MI_W +: MI_W];
            else
                sq_head_m_w[hd_s_i] = {MI_W{1'b0}};
        end
    end

    // ========================================================================
    // AW admission: per-slave round-robin granted at the address handshake.
    // ========================================================================
    reg [MI_W-1:0]  aw_ptr_r   [0:NUM_S-1];
    reg [NUM_M-1:0] aw_req_r   [0:NUM_S-1];
    reg [NUM_M-1:0] aw_grant_r [0:NUM_S-1];
    reg             aw_gfit_r  [0:NUM_S-1];
    reg [MI_W-1:0]  aw_gidx_r  [0:NUM_S-1];
    integer aw_s_i;
    integer aw_m_i;
    integer aw_off_i;
    integer aw_idx_i;

    always @* begin
        for (aw_s_i = 0; aw_s_i < NUM_S; aw_s_i = aw_s_i + 1) begin
            for (aw_m_i = 0; aw_m_i < NUM_M; aw_m_i = aw_m_i + 1) begin
                aw_req_r[aw_s_i][aw_m_i] = m_awvalid_i[aw_m_i] &&
                    (hit_tgt_r[aw_m_i] == aw_s_i[TGT_W-1:0]) &&
                    (wr_cnt_r[aw_m_i] < M_MAX_L) &&
                    (sq_cnt_r[aw_s_i] < S_MAX_L);
            end
            aw_grant_r[aw_s_i] = {NUM_M{1'b0}};
            aw_gfit_r[aw_s_i]  = 1'b0;
            aw_gidx_r[aw_s_i]  = {MI_W{1'b0}};
            if (|aw_req_r[aw_s_i]) begin
                for (aw_off_i = 0; aw_off_i < NUM_M;
                     aw_off_i = aw_off_i + 1) begin
                    aw_idx_i = {{(32-MI_W){1'b0}}, aw_ptr_r[aw_s_i]};
                    aw_idx_i = aw_idx_i + aw_off_i;
                    if (aw_idx_i >= NUM_M)
                        aw_idx_i = aw_idx_i - NUM_M;
                    if (!aw_gfit_r[aw_s_i] && aw_req_r[aw_s_i][aw_idx_i]) begin
                        aw_grant_r[aw_s_i][aw_idx_i] = 1'b1;
                        aw_gidx_r[aw_s_i]            = aw_idx_i[MI_W-1:0];
                        aw_gfit_r[aw_s_i]            = 1'b1;
                    end
                end
            end
        end
    end

    // ========================================================================
    // Combinational outputs.
    // ========================================================================
    // B beat candidates: slave s presents a B for master m (global BID).
    wire [NUM_S*MI_W-1:0] s_bid_m_w;
    genvar bid_g;
    generate
        for (bid_g = 0; bid_g < NUM_S; bid_g = bid_g + 1) begin : gen_bidm
            assign s_bid_m_w[bid_g*MI_W +: MI_W] =
                s_bid_i[bid_g*GID_W + GID_W-1 -: MI_W];
        end
    endgenerate

    reg [NUM_S-1:0] b_cand_r [0:NUM_M-1];
    integer bt_m_i;
    integer bt_s_i;
    always @* begin
        for (bt_m_i = 0; bt_m_i < NUM_M; bt_m_i = bt_m_i + 1) begin
            b_cand_r[bt_m_i] = {NUM_S{1'b0}};
            for (bt_s_i = 0; bt_s_i < NUM_S; bt_s_i = bt_s_i + 1) begin
                if (m_write_connect_i[bt_m_i*NUM_S + bt_s_i] &&
                    s_bvalid_i[bt_s_i] &&
                    (s_bid_m_w[bt_s_i*MI_W +: MI_W] ==
                     m_idx_enc_w[bt_m_i*MI_W +: MI_W]))
                    b_cand_r[bt_m_i][bt_s_i] = 1'b1;
            end
        end
    end

    // Per-master B source pick (single beat, no hold): round-robin over
    // slave candidates plus the inline DECERR responder (source NUM_S).
    reg [SRC_W-1:0] b_ptr_r  [0:NUM_M-1];
    reg [NUM_S:0]   b_pick_r [0:NUM_M-1];
    reg             b_pick_err_r [0:NUM_M-1];
    reg             b_pick_v_r   [0:NUM_M-1];
    reg [SRC_W-1:0] b_pick_idx_r [0:NUM_M-1];
    integer bp_m_i;
    integer bp_off_i;
    integer bp_idx_i;
    integer bp_s_i;

    // W routing intermediates.
    reg             w_to_s_gate_r [0:NUM_S-1];   // slave s may take owner W
    reg [MI_W-1:0]  w_owner_r     [0:NUM_S-1];
    reg             w_own_valid_r [0:NUM_S-1];
    reg             m_head_err_w  [0:NUM_M-1];
    reg [NUM_S-1:0] m_head_tgt_oh [0:NUM_M-1];
    integer wr_m_i;
    integer wr_s_i;
    integer own_m_i;
    integer own_s_i;
    integer wf_s_i;
    integer wrdy_m_i;
    integer wrdy_s_i;
    integer brdy_m_i;
    integer brdy_s_i;

    always @* begin
        // Defaults.
        for (wr_m_i = 0; wr_m_i < NUM_M; wr_m_i = wr_m_i + 1) begin
            m_awready_o[wr_m_i] = 1'b0;
            m_bid_o[wr_m_i*ID_W +: ID_W]    = {ID_W{1'b0}};
            m_bresp_o[wr_m_i*RESP_W +: RESP_W] = {RESP_W{1'b0}};
            m_bvalid_o[wr_m_i]  = 1'b0;
            b_pick_r[wr_m_i]     = {(NUM_S+1){1'b0}};
            b_pick_err_r[wr_m_i] = 1'b0;
            b_pick_v_r[wr_m_i]   = 1'b0;
            b_pick_idx_r[wr_m_i] = {SRC_W{1'b0}};
        end
        for (wr_s_i = 0; wr_s_i < NUM_S; wr_s_i = wr_s_i + 1) begin
            s_awvalid_o[wr_s_i] = 1'b0;
            s_awid_o[wr_s_i*GID_W +: GID_W]    = {GID_W{1'b0}};
            s_awaddr_o[wr_s_i*ADDR_W +: ADDR_W] = {ADDR_W{1'b0}};
            s_awlen_o[wr_s_i*LEN_W +: LEN_W]   = {LEN_W{1'b0}};
            s_awsize_o[wr_s_i*SIZE_W +: SIZE_W] = {SIZE_W{1'b0}};
            s_awburst_o[wr_s_i*BURST_W +: BURST_W] = {BURST_W{1'b0}};
        end

        // B source pick and routing.
        for (bp_m_i = 0; bp_m_i < NUM_M; bp_m_i = bp_m_i + 1) begin
            if (M_MAX_OUTSTANDING == 1) begin
                if (errb_pending_r[bp_m_i]) begin
                    b_pick_r[bp_m_i][NUM_S] = 1'b1;
                    b_pick_v_r[bp_m_i] = 1'b1;
                    b_pick_idx_r[bp_m_i] = SRC_ERROR;
                end else begin
                    for (bp_s_i = 0; bp_s_i < NUM_S;
                         bp_s_i = bp_s_i + 1) begin
                        if (single_b_owner_oh_r[bp_m_i][bp_s_i] &&
                            s_bvalid_i[bp_s_i] &&
                            (s_bid_i[bp_s_i*GID_W +: GID_W] ==
                             {m_idx_enc_w[bp_m_i*MI_W +: MI_W],
                              single_b_owner_id_r[bp_m_i]})) begin
                            b_pick_r[bp_m_i][bp_s_i] = 1'b1;
                            b_pick_v_r[bp_m_i] = 1'b1;
                            b_pick_idx_r[bp_m_i] = bp_s_i[SRC_W-1:0];
                        end
                    end
                end
            end else begin
                for (bp_off_i = 0; bp_off_i <= NUM_S;
                     bp_off_i = bp_off_i + 1) begin
                    bp_idx_i = {{(32-SRC_W){1'b0}}, b_ptr_r[bp_m_i]};
                    bp_idx_i = bp_idx_i + bp_off_i;
                    if (bp_idx_i > NUM_S)
                        bp_idx_i = bp_idx_i - (NUM_S + 1);
                    if (((bp_idx_i == NUM_S) ? errb_pending_r[bp_m_i]
                                             : b_cand_r[bp_m_i][bp_idx_i]) &&
                        !b_pick_v_r[bp_m_i]) begin
                        b_pick_r[bp_m_i][bp_idx_i] = 1'b1;
                        b_pick_v_r[bp_m_i] = 1'b1;
                        b_pick_idx_r[bp_m_i] = bp_idx_i[SRC_W-1:0];
                    end
                end
            end
            b_pick_err_r[bp_m_i] = b_pick_r[bp_m_i][NUM_S];
            if (b_pick_v_r[bp_m_i]) begin
                if (b_pick_err_r[bp_m_i]) begin
                    m_bid_o[bp_m_i*ID_W +: ID_W]   = errb_id_r[bp_m_i];
                    m_bresp_o[bp_m_i*RESP_W +: RESP_W] = `AXI_RESP_DECERR;
                    m_bvalid_o[bp_m_i] = 1'b1;
                end else begin
                    for (bp_s_i = 0; bp_s_i < NUM_S; bp_s_i = bp_s_i + 1) begin
                        if (b_pick_r[bp_m_i][bp_s_i] && s_bvalid_i[bp_s_i]) begin
                            m_bid_o[bp_m_i*ID_W +: ID_W] =
                                s_bid_i[bp_s_i*GID_W +: ID_W];
                            m_bresp_o[bp_m_i*RESP_W +: RESP_W] =
                                s_bresp_i[bp_s_i*RESP_W +: RESP_W];
                            m_bvalid_o[bp_m_i] = 1'b1;
                        end
                    end
                end
            end
        end

        // AW forwarding and master readiness.
        for (wr_m_i = 0; wr_m_i < NUM_M; wr_m_i = wr_m_i + 1) begin
            if (m_awvalid_i[wr_m_i] && (hit_tgt_r[wr_m_i] == TGT_ERROR) &&
                (wr_cnt_r[wr_m_i] < M_MAX_L) && !errw_active_r[wr_m_i])
                m_awready_o[wr_m_i] = 1'b1;
        end
        for (wr_s_i = 0; wr_s_i < NUM_S; wr_s_i = wr_s_i + 1) begin
            s_awvalid_o[wr_s_i] = aw_gfit_r[wr_s_i];
            if (aw_gfit_r[wr_s_i]) begin
                s_awid_o[wr_s_i*GID_W +: GID_W] =
                    {m_idx_enc_w[aw_gidx_r[wr_s_i]*MI_W +: MI_W],
                     m_awid_i[aw_gidx_r[wr_s_i]*ID_W +: ID_W]};
                s_awaddr_o[wr_s_i*ADDR_W +: ADDR_W] =
                    m_awaddr_i[aw_gidx_r[wr_s_i]*ADDR_W +: ADDR_W];
                s_awlen_o[wr_s_i*LEN_W +: LEN_W] =
                    m_awlen_i[aw_gidx_r[wr_s_i]*LEN_W +: LEN_W];
                s_awsize_o[wr_s_i*SIZE_W +: SIZE_W] =
                    m_awsize_i[aw_gidx_r[wr_s_i]*SIZE_W +: SIZE_W];
                s_awburst_o[wr_s_i*BURST_W +: BURST_W] =
                    m_awburst_i[aw_gidx_r[wr_s_i]*BURST_W +: BURST_W];
            end
            for (wr_m_i = 0; wr_m_i < NUM_M; wr_m_i = wr_m_i + 1) begin
                if (aw_grant_r[wr_s_i][wr_m_i] && s_awready_i[wr_s_i])
                    m_awready_o[wr_m_i] = 1'b1;
            end
        end
    end

    // BREADY routing is independent from BID/BRESP/BVALID payload selection,
    // avoiding a false response-payload feedback path in nested fabrics.
    always @* begin
        for (brdy_s_i = 0; brdy_s_i < NUM_S; brdy_s_i = brdy_s_i + 1) begin
            s_bready_o[brdy_s_i] = 1'b0;
            for (brdy_m_i = 0; brdy_m_i < NUM_M;
                 brdy_m_i = brdy_m_i + 1) begin
                if (b_pick_r[brdy_m_i][brdy_s_i] &&
                    m_bready_i[brdy_m_i])
                    s_bready_o[brdy_s_i] = 1'b1;
            end
        end
    end

    // Decode W ownership only from registered queue state.  Keeping this
    // independent of payload and READY prevents false cross-instance
    // combinational dependencies when fabrics are composed hierarchically.
    always @* begin
        for (own_m_i = 0; own_m_i < NUM_M; own_m_i = own_m_i + 1) begin
            m_head_err_w[own_m_i] = 1'b0;
            m_head_tgt_oh[own_m_i] = {NUM_S{1'b0}};
            if (mq_cnt_r[own_m_i] != 0) begin
                if (mq_head_tgt_w[own_m_i] == TGT_ERROR)
                    m_head_err_w[own_m_i] = 1'b1;
                else
                    m_head_tgt_oh[own_m_i][mq_head_tgt_w[own_m_i]] = 1'b1;
            end
        end
        for (own_s_i = 0; own_s_i < NUM_S; own_s_i = own_s_i + 1) begin
            w_to_s_gate_r[own_s_i] = 1'b0;
            w_own_valid_r[own_s_i] = 1'b0;
            w_owner_r[own_s_i] = {MI_W{1'b0}};
            if (sq_cnt_r[own_s_i] != 0) begin
                w_own_valid_r[own_s_i] = 1'b1;
                w_owner_r[own_s_i] = sq_head_m_w[own_s_i];
                w_to_s_gate_r[own_s_i] =
                    m_head_tgt_oh[sq_head_m_w[own_s_i]][own_s_i];
            end
        end
    end

    // Slave-side W payload does not depend on slave READY.
    always @* begin
        for (wf_s_i = 0; wf_s_i < NUM_S; wf_s_i = wf_s_i + 1) begin
            s_wvalid_o[wf_s_i] = 1'b0;
            s_wdata_o[wf_s_i*DATA_W +: DATA_W] = {DATA_W{1'b0}};
            s_wstrb_o[wf_s_i*STRB_W +: STRB_W] = {STRB_W{1'b0}};
            s_wlast_o[wf_s_i] = 1'b0;
            if (w_own_valid_r[wf_s_i] && w_to_s_gate_r[wf_s_i]) begin
                s_wvalid_o[wf_s_i] = m_wvalid_i[w_owner_r[wf_s_i]];
                s_wdata_o[wf_s_i*DATA_W +: DATA_W] =
                    m_wdata_i[w_owner_r[wf_s_i]*DATA_W +: DATA_W];
                s_wstrb_o[wf_s_i*STRB_W +: STRB_W] =
                    m_wstrb_i[w_owner_r[wf_s_i]*STRB_W +: STRB_W];
                s_wlast_o[wf_s_i] = m_wlast_i[w_owner_r[wf_s_i]];
            end
        end
    end

    // Master-side WREADY depends on ownership and the selected slave READY,
    // but never on W payload or WLAST.
    always @* begin
        for (wrdy_m_i = 0; wrdy_m_i < NUM_M; wrdy_m_i = wrdy_m_i + 1) begin
            m_wready_o[wrdy_m_i] = 1'b0;
            if (mq_cnt_r[wrdy_m_i] != 0) begin
                if (m_head_err_w[wrdy_m_i]) begin
                    m_wready_o[wrdy_m_i] = 1'b1;
                end else begin
                    for (wrdy_s_i = 0; wrdy_s_i < NUM_S;
                         wrdy_s_i = wrdy_s_i + 1) begin
                        if (m_head_tgt_oh[wrdy_m_i][wrdy_s_i] &&
                            w_own_valid_r[wrdy_s_i] &&
                            (w_owner_r[wrdy_s_i] == wrdy_m_i[MI_W-1:0]))
                            m_wready_o[wrdy_m_i] = s_wready_i[wrdy_s_i];
                    end
                end
            end
        end
    end

    wire [NUM_S-1:0] aw_fire_s_w = s_awvalid_o & s_awready_i;
    wire [NUM_M-1:0] aw_fire_m_w = m_awvalid_i & m_awready_o;
    wire [NUM_M-1:0] w_fire_m_w  = m_wvalid_i & m_wready_o;
    wire [NUM_M-1:0] mq_pop_w    = w_fire_m_w & m_wlast_i;
    wire [NUM_S-1:0] sq_pop_w    = s_wvalid_o & s_wready_i & s_wlast_o;
    wire [NUM_M-1:0] b_accept_w  = m_bvalid_o & m_bready_i;

    // Keep monitor state at module scope.  Some Verilog-2001 synthesis tools
    // cannot resolve an unpacked array through a named generate hierarchy.
    reg [31:0] mon_wr_beats_r   [0:NUM_M-1];
    reg [31:0] mon_wr_bursts_r  [0:NUM_M-1];
    reg [31:0] mon_wr_err_r     [0:NUM_M-1];
    reg [31:0] mon_wr_wait_r    [0:NUM_M-1];
    reg [31:0] mon_wr_maxwait_r [0:NUM_M-1];

    // AXI monitor (write side): W beats, AW bursts, B errors, max AW->B wait.
    generate
        if (AXI_MON_ENABLE != 0) begin : gen_wr_mon
            integer mi;
            always @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    for (mi = 0; mi < NUM_M; mi = mi + 1) begin
                        mon_wr_beats_r[mi]   <= 32'h0;
                        mon_wr_bursts_r[mi]  <= 32'h0;
                        mon_wr_err_r[mi]     <= 32'h0;
                        mon_wr_wait_r[mi]    <= 32'h0;
                        mon_wr_maxwait_r[mi] <= 32'h0;
                    end
                end else begin
                    for (mi = 0; mi < NUM_M; mi = mi + 1) begin
                        if (aw_fire_m_w[mi]) begin
                            mon_wr_bursts_r[mi] <= mon_wr_bursts_r[mi] + 1'b1;
                            mon_wr_wait_r[mi]   <= 32'h0;
                        end
                        if (w_fire_m_w[mi]) begin
                            mon_wr_beats_r[mi] <= mon_wr_beats_r[mi] + 1'b1;
                            mon_wr_wait_r[mi]  <= mon_wr_wait_r[mi] + 1'b1;
                        end
                        if (b_accept_w[mi]) begin
                            if (m_bresp_o[mi*RESP_W +: RESP_W] != `AXI_RESP_OKAY)
                                mon_wr_err_r[mi] <= mon_wr_err_r[mi] + 1'b1;
                            mon_wr_wait_r[mi] <= mon_wr_wait_r[mi] + 1'b1;
                            if (mon_wr_wait_r[mi] + 1'b1 > mon_wr_maxwait_r[mi])
                                mon_wr_maxwait_r[mi] <= mon_wr_wait_r[mi] + 1'b1;
                        end
                    end
                end
            end
        end
    endgenerate

    genvar wmon_g;
    generate
        for (wmon_g = 0; wmon_g < NUM_M; wmon_g = wmon_g + 1) begin : gen_wr_mon_w
            if (AXI_MON_ENABLE != 0) begin : gen_wires_on
                assign mon_wr_beats_o[wmon_g*32 +: 32]   = mon_wr_beats_r[wmon_g];
                assign mon_wr_bursts_o[wmon_g*32 +: 32]  = mon_wr_bursts_r[wmon_g];
                assign mon_wr_err_o[wmon_g*32 +: 32]     = mon_wr_err_r[wmon_g];
                assign mon_wr_maxwait_o[wmon_g*32 +: 32] = mon_wr_maxwait_r[wmon_g];
            end
        end
    endgenerate

    generate
        if (AXI_MON_ENABLE == 0) begin : gen_wr_mon_off
            assign mon_wr_beats_o   = {NUM_M*32{1'b0}};
            assign mon_wr_bursts_o  = {NUM_M*32{1'b0}};
            assign mon_wr_err_o     = {NUM_M*32{1'b0}};
            assign mon_wr_maxwait_o = {NUM_M*32{1'b0}};
        end
    endgenerate

    // Fail-stop timeout: progress = any accepted W beat or B response.
    localparam WTMO_W = (WR_TIMEOUT_CYCLES <= 1) ? 1 : clog2(WR_TIMEOUT_CYCLES + 1);
    localparam [WTMO_W-1:0] WTMO_MAX = WR_TIMEOUT_CYCLES[WTMO_W-1:0];

    reg [NUM_M-1:0]   fs_wr_r;
    reg [WTMO_W-1:0]  wr_tmo_cnt_r [0:NUM_M-1];
    reg [ID_W-1:0]    fs_wr_id_r   [0:NUM_M-1];
    reg [ADDR_W-1:0]  fs_wr_addr_r [0:NUM_M-1];

    assign fs_wr_fail_o = fs_wr_r;
    genvar fs_wr_g;
    generate
        for (fs_wr_g = 0; fs_wr_g < NUM_M; fs_wr_g = fs_wr_g + 1) begin : gen_fs_wr_out
            assign fs_wr_addr_o[fs_wr_g*ADDR_W +: ADDR_W] = fs_wr_addr_r[fs_wr_g];
            assign fs_wr_id_o[fs_wr_g*ID_W +: ID_W]       = fs_wr_id_r[fs_wr_g];
        end
    endgenerate

    // ========================================================================
    // Sequential state.
    // ========================================================================
    integer seq_m_i;
    integer seq_s_i;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (seq_m_i = 0; seq_m_i < NUM_M; seq_m_i = seq_m_i + 1) begin
                wr_cnt_r[seq_m_i]   <= {CNT_W{1'b0}};
                mq_head_r[seq_m_i]  <= {MP_W{1'b0}};
                mq_tail_r[seq_m_i]  <= {MP_W{1'b0}};
                mq_cnt_r[seq_m_i]   <= {CNT_W{1'b0}};
                errw_active_r[seq_m_i]  <= 1'b0;
                errb_pending_r[seq_m_i] <= 1'b0;
                errb_id_r[seq_m_i]      <= {ID_W{1'b0}};
                single_b_owner_oh_r[seq_m_i] <= {NUM_S{1'b0}};
                single_b_owner_id_r[seq_m_i] <= {ID_W{1'b0}};
                b_ptr_r[seq_m_i]        <= {SRC_W{1'b0}};
                fs_wr_r[seq_m_i]        <= 1'b0;
                wr_tmo_cnt_r[seq_m_i]   <= {WTMO_W{1'b0}};
                fs_wr_id_r[seq_m_i]     <= {ID_W{1'b0}};
                fs_wr_addr_r[seq_m_i]   <= {ADDR_W{1'b0}};
            end
            for (seq_s_i = 0; seq_s_i < NUM_S; seq_s_i = seq_s_i + 1) begin
                sq_head_r[seq_s_i] <= {SP_W{1'b0}};
                sq_tail_r[seq_s_i] <= {SP_W{1'b0}};
                sq_cnt_r[seq_s_i]  <= {SC_W{1'b0}};
                aw_ptr_r[seq_s_i]  <= {MI_W{1'b0}};
            end
        end else begin
            for (seq_m_i = 0; seq_m_i < NUM_M; seq_m_i = seq_m_i + 1) begin
                // Single-entry form of the per-ID B route table.  The route
                // is captured with AW and held across the complete W burst.
                if (M_MAX_OUTSTANDING == 1) begin
                    if (aw_fire_m_w[seq_m_i]) begin
                        single_b_owner_oh_r[seq_m_i] <= {NUM_S{1'b0}};
                        single_b_owner_id_r[seq_m_i] <=
                            m_awid_i[seq_m_i*ID_W +: ID_W];
                        for (seq_s_i = 0; seq_s_i < NUM_S;
                             seq_s_i = seq_s_i + 1) begin
                            if (m_write_connect_i[seq_m_i*NUM_S + seq_s_i] &&
                                (hit_tgt_r[seq_m_i] ==
                                 seq_s_i[TGT_W-1:0]))
                                single_b_owner_oh_r[seq_m_i][seq_s_i] <= 1'b1;
                        end
                    end else if (b_accept_w[seq_m_i]) begin
                        single_b_owner_oh_r[seq_m_i] <= {NUM_S{1'b0}};
                    end
                end

                // Outstanding count: +1 per accepted AW, -1 per accepted B.
                wr_cnt_r[seq_m_i] <= wr_cnt_r[seq_m_i]
                    + (aw_fire_m_w[seq_m_i] ? {{(CNT_W-1){1'b0}}, 1'b1} : {CNT_W{1'b0}})
                    - (b_accept_w[seq_m_i] ? {{(CNT_W-1){1'b0}}, 1'b1} : {CNT_W{1'b0}});

                // W-order FIFO push (any accepted AW).
                if (aw_fire_m_w[seq_m_i]) begin
                    mq_tgt_r[seq_m_i][mq_tail_r[seq_m_i]*TGT_W +: TGT_W] <=
                        hit_tgt_r[seq_m_i];
                    mq_id_r[seq_m_i][mq_tail_r[seq_m_i]*ID_W +: ID_W] <=
                        m_awid_i[seq_m_i*ID_W +: ID_W];
                    if (mq_tail_r[seq_m_i] == M_LAST_PTR)
                        mq_tail_r[seq_m_i] <= {MP_W{1'b0}};
                    else
                        mq_tail_r[seq_m_i] <= mq_tail_r[seq_m_i] + 1'b1;
                    mq_cnt_r[seq_m_i] <= mq_cnt_r[seq_m_i] + 1'b1;
                end

                // W-order FIFO pop (WLAST forwarded for the head entry).
                if (mq_pop_w[seq_m_i]) begin
                    if (mq_head_r[seq_m_i] == M_LAST_PTR)
                        mq_head_r[seq_m_i] <= {MP_W{1'b0}};
                    else
                        mq_head_r[seq_m_i] <= mq_head_r[seq_m_i] + 1'b1;
                    mq_cnt_r[seq_m_i] <= mq_cnt_r[seq_m_i] - 1'b1;
                    // Error burst drained: present its DECERR B next.
                    if (mq_head_tgt_w[seq_m_i] == TGT_ERROR) begin
                        errb_pending_r[seq_m_i] <= 1'b1;
                        errb_id_r[seq_m_i]      <= mq_head_id_w[seq_m_i];
                    end
                end

                // Inline DECERR responder lifecycle.
                if (aw_fire_m_w[seq_m_i] && (hit_tgt_r[seq_m_i] == TGT_ERROR))
                    errw_active_r[seq_m_i] <= 1'b1;
                if (b_accept_w[seq_m_i] && b_pick_err_r[seq_m_i]) begin
                    errb_pending_r[seq_m_i] <= 1'b0;
                    errw_active_r[seq_m_i]  <= 1'b0;
                end

                // B source round-robin pointer.
                if (b_accept_w[seq_m_i]) begin
                    if (b_pick_idx_r[seq_m_i] == NUM_S)
                        b_ptr_r[seq_m_i] <= {SRC_W{1'b0}};
                    else
                        b_ptr_r[seq_m_i] <= b_pick_idx_r[seq_m_i] + 1'b1;
                end

                // Fail-stop timeout: progress = accepted W beat or B response.
                if (WR_TIMEOUT_CYCLES != 0) begin
                    if (aw_fire_m_w[seq_m_i]) begin
                        wr_tmo_cnt_r[seq_m_i] <= WTMO_MAX;
                        fs_wr_id_r[seq_m_i]   <= m_awid_i[seq_m_i*ID_W +: ID_W];
                        fs_wr_addr_r[seq_m_i] <= m_awaddr_i[seq_m_i*ADDR_W +: ADDR_W];
                    end else if (!fs_wr_r[seq_m_i] && (wr_cnt_r[seq_m_i] != 0)) begin
                        if (w_fire_m_w[seq_m_i] || b_accept_w[seq_m_i])
                            wr_tmo_cnt_r[seq_m_i] <= WTMO_MAX;
                        else if (wr_tmo_cnt_r[seq_m_i] == 0)
                            fs_wr_r[seq_m_i] <= 1'b1;
                        else
                            wr_tmo_cnt_r[seq_m_i] <= wr_tmo_cnt_r[seq_m_i] - 1'b1;
                    end
                end
            end

            for (seq_s_i = 0; seq_s_i < NUM_S; seq_s_i = seq_s_i + 1) begin
                // AW order queue push (accepted AW at this slave).
                if (aw_fire_s_w[seq_s_i]) begin
                    sq_m_r[seq_s_i][sq_tail_r[seq_s_i]*MI_W +: MI_W] <=
                        aw_gidx_r[seq_s_i];
                    if (sq_tail_r[seq_s_i] == S_LAST_PTR)
                        sq_tail_r[seq_s_i] <= {SP_W{1'b0}};
                    else
                        sq_tail_r[seq_s_i] <= sq_tail_r[seq_s_i] + 1'b1;
                    sq_cnt_r[seq_s_i] <= sq_cnt_r[seq_s_i] + 1'b1;
                end
                // AW order queue pop (WLAST forwarded to this slave).
                if (sq_pop_w[seq_s_i]) begin
                    if (sq_head_r[seq_s_i] == S_LAST_PTR)
                        sq_head_r[seq_s_i] <= {SP_W{1'b0}};
                    else
                        sq_head_r[seq_s_i] <= sq_head_r[seq_s_i] + 1'b1;
                    sq_cnt_r[seq_s_i] <= sq_cnt_r[seq_s_i] - 1'b1;
                end
                // AW round-robin pointer.
                if (aw_fire_s_w[seq_s_i]) begin
                    if (aw_gidx_r[seq_s_i] == M_LAST_IDX)
                        aw_ptr_r[seq_s_i] <= {MI_W{1'b0}};
                    else
                        aw_ptr_r[seq_s_i] <= aw_gidx_r[seq_s_i] + 1'b1;
                end
            end
        end
    end

endmodule
