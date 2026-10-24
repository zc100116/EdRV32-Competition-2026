// ============================================================================
// File        : axi_rd_fabric.v
// Author      : Edward ZC
// Description : Parameterised NUM_M x NUM_S AXI4 read crossbar (design §6.3).
//               AR admission is per-slave round-robin granted at the address
//               handshake; R beats are routed by the global ID the fabric
//               assigned ({master_index, local_id}) and the prefix is stripped
//               on return, so a slave may complete IDs in any order and the
//               fabric never holds an address owner until response completion
//               in the general multi-outstanding configuration.  A
//               single-outstanding specialization records the accepted AR
//               target and routes only that slave until RLAST; this removes a
//               physically expensive all-slave RID scan without changing the
//               externally visible AXI contract.
// Notes       : Verilog-2001. Decode miss / overlap / disconnected targets are
//               served by an inline DECERR responder that returns a full
//               ARLEN+1 beat burst; error reads are single-burst-per-master
//               (admission gated) and still count against the master
//               outstanding limit. Zero-latency same-cycle R responses are
//               supported by combinational RID routing.
// ============================================================================
`include "edrv32_axi4.vh"

module axi_rd_fabric #(
    parameter NUM_M   = 2,
    parameter NUM_S   = 5,
    parameter ADDR_W  = 32,
    parameter DATA_W  = 32,
    parameter ID_W    = 4,          // master-local ID width
    parameter LEN_W   = 8,
    parameter SIZE_W  = 3,
    parameter BURST_W = 2,
    parameter RESP_W  = 2,
    parameter GID_W   = ID_W + ((NUM_M <= 1) ? 1 : $clog2(NUM_M)),
    parameter M_MAX_OUTSTANDING = 4,
    parameter RD_TIMEOUT_CYCLES = 0,   // 0 = disabled (fail-stop watchdog)
    parameter AXI_MON_ENABLE = 0       // per-master observability counters
)(
    // --- Clock and reset ---
    input  wire                         clk,
    input  wire                         rst_n,

    // --- Master-side read address channels (ID is local) ---
    input  wire [NUM_M*ID_W-1:0]        m_arid_i,
    input  wire [NUM_M*ADDR_W-1:0]      m_araddr_i,
    input  wire [NUM_M*LEN_W-1:0]       m_arlen_i,
    input  wire [NUM_M*SIZE_W-1:0]      m_arsize_i,
    input  wire [NUM_M*BURST_W-1:0]     m_arburst_i,
    input  wire [NUM_M-1:0]             m_arvalid_i,
    output reg  [NUM_M-1:0]             m_arready_o,

    // --- Master-side read data channels (ID is local) ---
    output reg  [NUM_M*ID_W-1:0]        m_rid_o,
    output reg  [NUM_M*DATA_W-1:0]      m_rdata_o,
    output reg  [NUM_M*RESP_W-1:0]      m_rresp_o,
    output reg  [NUM_M-1:0]             m_rlast_o,
    output reg  [NUM_M-1:0]             m_rvalid_o,
    input  wire [NUM_M-1:0]             m_rready_i,

    // --- Address map and master/slave connectivity ---
    input  wire [NUM_S*ADDR_W-1:0]      s_base_i,
    input  wire [NUM_S*ADDR_W-1:0]      s_limit_i,
    input  wire [NUM_M*NUM_S-1:0]       m_read_connect_i,

    // --- Slave-side read address channels (ID is global) ---
    output reg  [NUM_S*GID_W-1:0]       s_arid_o,
    output reg  [NUM_S*ADDR_W-1:0]      s_araddr_o,
    output reg  [NUM_S*LEN_W-1:0]       s_arlen_o,
    output reg  [NUM_S*SIZE_W-1:0]      s_arsize_o,
    output reg  [NUM_S*BURST_W-1:0]     s_arburst_o,
    output reg  [NUM_S-1:0]             s_arvalid_o,
    input  wire [NUM_S-1:0]             s_arready_i,

    // --- Slave-side read data channels (ID is global) ---
    input  wire [NUM_S*GID_W-1:0]       s_rid_i,
    input  wire [NUM_S*DATA_W-1:0]      s_rdata_i,
    input  wire [NUM_S*RESP_W-1:0]      s_rresp_i,
    input  wire [NUM_S-1:0]             s_rlast_i,
    input  wire [NUM_S-1:0]             s_rvalid_i,
    output reg  [NUM_S-1:0]             s_rready_o,

    // --- Fail-stop timeout status (sticky until reset; no fake responses) ---
    output wire [NUM_M-1:0]             fs_rd_fail_o,
    output wire [NUM_M*ADDR_W-1:0]      fs_rd_addr_o,
    output wire [NUM_M*ID_W-1:0]        fs_rd_id_o,

    // --- AXI monitor (all-zero when AXI_MON_ENABLE=0) ---
    output wire [NUM_M*32-1:0]          mon_rd_beats_o,
    output wire [NUM_M*32-1:0]          mon_rd_bursts_o,
    output wire [NUM_M*32-1:0]          mon_rd_err_o,
    output wire [NUM_M*32-1:0]          mon_rd_maxwait_o
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
    localparam SRC_W = clog2(NUM_S + 1);                 // R source select
    localparam [SRC_W-1:0] SRC_ERROR = NUM_S;
    localparam [CNT_W-1:0] M_MAX_L = M_MAX_OUTSTANDING;
    localparam [MI_W-1:0]  M_LAST_IDX =
        NUM_M[MI_W-1:0] - {{(MI_W-1){1'b0}}, 1'b1};

    // Forward declaration: AR combinational admission observes fail-stop.
    reg [NUM_M-1:0] fs_rd_r;

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
                // A base below limit describes the usual [base, limit)
                // interval.  A base above limit describes an interval that
                // wraps through address zero; this is required for a region
                // ending exactly at 4 GiB (for example C000_0000..FFFF_FFFF
                // with an exclusive limit of 0000_0000).  Equal endpoints
                // intentionally describe an empty region, never all memory.
                if (m_read_connect_i[dec_m_i*NUM_S + dec_s_i] &&
                    (((s_base_i[dec_s_i*ADDR_W +: ADDR_W] <
                       s_limit_i[dec_s_i*ADDR_W +: ADDR_W]) &&
                      (m_araddr_i[dec_m_i*ADDR_W +: ADDR_W] >=
                       s_base_i[dec_s_i*ADDR_W +: ADDR_W]) &&
                      (m_araddr_i[dec_m_i*ADDR_W +: ADDR_W] <
                       s_limit_i[dec_s_i*ADDR_W +: ADDR_W])) ||
                     ((s_base_i[dec_s_i*ADDR_W +: ADDR_W] >
                       s_limit_i[dec_s_i*ADDR_W +: ADDR_W]) &&
                      ((m_araddr_i[dec_m_i*ADDR_W +: ADDR_W] >=
                        s_base_i[dec_s_i*ADDR_W +: ADDR_W]) ||
                       (m_araddr_i[dec_m_i*ADDR_W +: ADDR_W] <
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
    // Per-master outstanding read counter (admission limit).
    // ========================================================================
    reg [CNT_W-1:0] rd_cnt_r [0:NUM_M-1];

    // With one outstanding transaction per master, the accepted AR target is
    // a complete response-route token.  This is the same information a
    // general AXI demux keeps in its per-ID route table, reduced to one entry.
    // The local ID is retained so a slave returning a mismatched RID remains
    // fail-stop rather than being delivered to the wrong transaction.
    reg [NUM_S-1:0] single_owner_oh_r [0:NUM_M-1];
    reg [ID_W-1:0]  single_owner_id_r [0:NUM_M-1];

    wire [NUM_M-1:0] ar_fire_w     = m_arvalid_i & m_arready_o;
    wire [NUM_M-1:0] r_accept_w    = m_rvalid_o  & m_rready_i;
    wire [NUM_M-1:0] r_last_fire_w = r_accept_w  & m_rlast_o;

    // ========================================================================
    // Per-slave round-robin AR admission (grant ends at address handshake).
    // ========================================================================
    reg [MI_W-1:0]  rr_ptr_r   [0:NUM_S-1];
    reg [NUM_M-1:0] ar_req_r   [0:NUM_S-1];
    reg [NUM_M-1:0] grant_oh_r [0:NUM_S-1];
    reg             grant_hit_r [0:NUM_S-1];
    reg [MI_W-1:0]  grant_idx_r [0:NUM_S-1];
    integer adm_s_i;
    integer adm_m_i;
    integer adm_off_i;
    integer adm_idx_i;

    always @* begin
        for (adm_s_i = 0; adm_s_i < NUM_S; adm_s_i = adm_s_i + 1) begin
            for (adm_m_i = 0; adm_m_i < NUM_M; adm_m_i = adm_m_i + 1) begin
                ar_req_r[adm_s_i][adm_m_i] = m_arvalid_i[adm_m_i] &&
                    (hit_tgt_r[adm_m_i] == adm_s_i[TGT_W-1:0]) &&
                    (rd_cnt_r[adm_m_i] < M_MAX_L);
            end
            grant_oh_r[adm_s_i]  = {NUM_M{1'b0}};
            grant_hit_r[adm_s_i] = 1'b0;
            grant_idx_r[adm_s_i] = {MI_W{1'b0}};
            if (|ar_req_r[adm_s_i]) begin
                for (adm_off_i = 0; adm_off_i < NUM_M;
                     adm_off_i = adm_off_i + 1) begin
                    adm_idx_i = {{(32-MI_W){1'b0}}, rr_ptr_r[adm_s_i]};
                    adm_idx_i = adm_idx_i + adm_off_i;
                    if (adm_idx_i >= NUM_M)
                        adm_idx_i = adm_idx_i - NUM_M;
                    if (!grant_hit_r[adm_s_i] && ar_req_r[adm_s_i][adm_idx_i]) begin
                        grant_oh_r[adm_s_i][adm_idx_i] = 1'b1;
                        grant_idx_r[adm_s_i]           = adm_idx_i[MI_W-1:0];
                        grant_hit_r[adm_s_i]           = 1'b1;
                    end
                end
            end
        end
    end

    // ========================================================================
    // Per-master inline DECERR read responder (one burst in flight).
    // ========================================================================
    reg                err_busy_r [0:NUM_M-1];
    reg [ID_W-1:0]     err_id_r   [0:NUM_M-1];
    reg [LEN_W-1:0]    err_left_r [0:NUM_M-1];

    // ========================================================================
    // R beat candidates: slave s currently presents a beat for master m
    // (matched by the master-index field of the global RID).
    // ========================================================================
    wire [NUM_S*MI_W-1:0] s_rid_m_w;
    genvar rid_g;
    generate
        for (rid_g = 0; rid_g < NUM_S; rid_g = rid_g + 1) begin : gen_ridm
            assign s_rid_m_w[rid_g*MI_W +: MI_W] =
                s_rid_i[rid_g*GID_W + GID_W-1 -: MI_W];
        end
    endgenerate

    reg [NUM_S-1:0] r_cand_r [0:NUM_M-1];
    integer rt_m_i;
    integer rt_s_i;
    always @* begin
        for (rt_m_i = 0; rt_m_i < NUM_M; rt_m_i = rt_m_i + 1) begin
            r_cand_r[rt_m_i] = {NUM_S{1'b0}};
            for (rt_s_i = 0; rt_s_i < NUM_S; rt_s_i = rt_s_i + 1) begin
                if (m_read_connect_i[rt_m_i*NUM_S + rt_s_i] &&
                    s_rvalid_i[rt_s_i] &&
                    (s_rid_m_w[rt_s_i*MI_W +: MI_W] ==
                     m_idx_enc_w[rt_m_i*MI_W +: MI_W]))
                    r_cand_r[rt_m_i][rt_s_i] = 1'b1;
            end
        end
    end

    // ========================================================================
    // Per-master R source selection with burst hold.  Sources 0..NUM_S-1 are
    // slaves; source NUM_S is the inline DECERR responder.  A held source
    // keeps the master channel until its RLAST beat is accepted.
    // ========================================================================
    reg [NUM_S:0]   hold_oh_r [0:NUM_M-1];
    reg             hold_v_r  [0:NUM_M-1];
    reg [SRC_W-1:0] src_ptr_r [0:NUM_M-1];

    reg [NUM_S:0]   pick_oh_r    [0:NUM_M-1];
    reg             pick_err_r   [0:NUM_M-1];
    reg             pick_valid_r [0:NUM_M-1];
    reg [SRC_W-1:0] pick_idx_r   [0:NUM_M-1];
    integer sel_m_i;
    integer sel_s_i;
    integer sel_off_i;
    integer sel_idx_i;
    integer rrdy_m_i;
    integer rrdy_s_i;

    always @* begin
        // Defaults.
        for (sel_m_i = 0; sel_m_i < NUM_M; sel_m_i = sel_m_i + 1) begin
            m_arready_o[sel_m_i] = 1'b0;
            m_rid_o[sel_m_i*ID_W +: ID_W]       = {ID_W{1'b0}};
            m_rdata_o[sel_m_i*DATA_W +: DATA_W] = {DATA_W{1'b0}};
            m_rresp_o[sel_m_i*RESP_W +: RESP_W] = {RESP_W{1'b0}};
            m_rlast_o[sel_m_i]                  = 1'b0;
            m_rvalid_o[sel_m_i]                 = 1'b0;
            pick_oh_r[sel_m_i]                  = {(NUM_S+1){1'b0}};
            pick_err_r[sel_m_i]                 = 1'b0;
            pick_valid_r[sel_m_i]               = 1'b0;
            pick_idx_r[sel_m_i]                 = {SRC_W{1'b0}};
        end
        for (sel_s_i = 0; sel_s_i < NUM_S; sel_s_i = sel_s_i + 1) begin
            s_arvalid_o[sel_s_i]                = 1'b0;
            s_arid_o[sel_s_i*GID_W +: GID_W]    = {GID_W{1'b0}};
            s_araddr_o[sel_s_i*ADDR_W +: ADDR_W] = {ADDR_W{1'b0}};
            s_arlen_o[sel_s_i*LEN_W +: LEN_W]   = {LEN_W{1'b0}};
            s_arsize_o[sel_s_i*SIZE_W +: SIZE_W] = {SIZE_W{1'b0}};
            s_arburst_o[sel_s_i*BURST_W +: BURST_W] = {BURST_W{1'b0}};
        end

        // Source pick: held source wins; otherwise round-robin over
        // candidates (slaves with a matching beat, plus the error responder).
        for (sel_m_i = 0; sel_m_i < NUM_M; sel_m_i = sel_m_i + 1) begin
            if (M_MAX_OUTSTANDING == 1) begin
                // The route captured with AR acceptance is authoritative.
                // Only the recorded slave participates, so unrelated slave
                // VALID/ID activity cannot enter this master's response or
                // READY cones.  Inline DECERR uses its existing local state.
                if (err_busy_r[sel_m_i]) begin
                    pick_oh_r[sel_m_i][NUM_S] = 1'b1;
                    pick_valid_r[sel_m_i] = 1'b1;
                    pick_err_r[sel_m_i] = 1'b1;
                    pick_idx_r[sel_m_i] = SRC_ERROR;
                end else begin
                    for (sel_s_i = 0; sel_s_i < NUM_S;
                         sel_s_i = sel_s_i + 1) begin
                        if (single_owner_oh_r[sel_m_i][sel_s_i] &&
                            s_rvalid_i[sel_s_i] &&
                            (s_rid_i[sel_s_i*GID_W +: GID_W] ==
                             {m_idx_enc_w[sel_m_i*MI_W +: MI_W],
                              single_owner_id_r[sel_m_i]})) begin
                            pick_oh_r[sel_m_i][sel_s_i] = 1'b1;
                            pick_valid_r[sel_m_i] = 1'b1;
                            pick_idx_r[sel_m_i] = sel_s_i[SRC_W-1:0];
                        end
                    end
                end
            end else if (hold_v_r[sel_m_i]) begin
                pick_oh_r[sel_m_i]  = hold_oh_r[sel_m_i];
                pick_valid_r[sel_m_i] = 1'b1;
                pick_err_r[sel_m_i] = hold_oh_r[sel_m_i][NUM_S];
                pick_idx_r[sel_m_i] = SRC_ERROR;
                for (sel_s_i = 0; sel_s_i < NUM_S; sel_s_i = sel_s_i + 1)
                    if (hold_oh_r[sel_m_i][sel_s_i])
                        pick_idx_r[sel_m_i] = sel_s_i[SRC_W-1:0];
            end else begin
                for (sel_off_i = 0; sel_off_i <= NUM_S;
                     sel_off_i = sel_off_i + 1) begin
                    sel_idx_i = {{(32-SRC_W){1'b0}}, src_ptr_r[sel_m_i]};
                    sel_idx_i = sel_idx_i + sel_off_i;
                    if (sel_idx_i > NUM_S)
                        sel_idx_i = sel_idx_i - (NUM_S + 1);
                    if (((sel_idx_i == NUM_S) ? err_busy_r[sel_m_i]
                                              : r_cand_r[sel_m_i][sel_idx_i]) &&
                        !pick_valid_r[sel_m_i]) begin
                        pick_oh_r[sel_m_i][sel_idx_i] = 1'b1;
                        pick_valid_r[sel_m_i]         = 1'b1;
                        pick_idx_r[sel_m_i]           = sel_idx_i[SRC_W-1:0];
                    end
                end
                pick_err_r[sel_m_i] = pick_oh_r[sel_m_i][NUM_S];
            end

            if (pick_valid_r[sel_m_i]) begin
                if (pick_err_r[sel_m_i]) begin
                    m_rid_o[sel_m_i*ID_W +: ID_W]       = err_id_r[sel_m_i];
                    m_rdata_o[sel_m_i*DATA_W +: DATA_W] = {DATA_W{1'b0}};
                    m_rresp_o[sel_m_i*RESP_W +: RESP_W] = `AXI_RESP_DECERR;
                    m_rlast_o[sel_m_i]  = (err_left_r[sel_m_i] == 0);
                    m_rvalid_o[sel_m_i] = 1'b1;
                end else begin
                    for (sel_s_i = 0; sel_s_i < NUM_S; sel_s_i = sel_s_i + 1) begin
                        if (pick_oh_r[sel_m_i][sel_s_i] &&
                            s_rvalid_i[sel_s_i]) begin
                            m_rid_o[sel_m_i*ID_W +: ID_W] =
                                s_rid_i[sel_s_i*GID_W +: ID_W];
                            m_rdata_o[sel_m_i*DATA_W +: DATA_W] =
                                s_rdata_i[sel_s_i*DATA_W +: DATA_W];
                            m_rresp_o[sel_m_i*RESP_W +: RESP_W] =
                                s_rresp_i[sel_s_i*RESP_W +: RESP_W];
                            m_rlast_o[sel_m_i]  = s_rlast_i[sel_s_i];
                            m_rvalid_o[sel_m_i] = 1'b1;
                        end
                    end
                end
            end
        end

        // AR forwarding and master readiness.
        for (sel_m_i = 0; sel_m_i < NUM_M; sel_m_i = sel_m_i + 1) begin
            // Fail-stop masters may not issue new requests; in-flight
            // transactions continue to drain (or wait for reset).
            if (fs_rd_r[sel_m_i])
                m_arready_o[sel_m_i] = 1'b0;
            // Inline DECERR acceptance (gated: one error burst per master).
            else if (m_arvalid_i[sel_m_i] && (hit_tgt_r[sel_m_i] == TGT_ERROR) &&
                (rd_cnt_r[sel_m_i] < M_MAX_L) && !err_busy_r[sel_m_i])
                m_arready_o[sel_m_i] = 1'b1;
        end
        for (sel_s_i = 0; sel_s_i < NUM_S; sel_s_i = sel_s_i + 1) begin
            s_arvalid_o[sel_s_i] = grant_hit_r[sel_s_i];
            if (grant_hit_r[sel_s_i]) begin
                s_arid_o[sel_s_i*GID_W +: GID_W] =
                    {m_idx_enc_w[grant_idx_r[sel_s_i]*MI_W +: MI_W],
                     m_arid_i[grant_idx_r[sel_s_i]*ID_W +: ID_W]};
                s_araddr_o[sel_s_i*ADDR_W +: ADDR_W] =
                    m_araddr_i[grant_idx_r[sel_s_i]*ADDR_W +: ADDR_W];
                s_arlen_o[sel_s_i*LEN_W +: LEN_W] =
                    m_arlen_i[grant_idx_r[sel_s_i]*LEN_W +: LEN_W];
                s_arsize_o[sel_s_i*SIZE_W +: SIZE_W] =
                    m_arsize_i[grant_idx_r[sel_s_i]*SIZE_W +: SIZE_W];
                s_arburst_o[sel_s_i*BURST_W +: BURST_W] =
                    m_arburst_i[grant_idx_r[sel_s_i]*BURST_W +: BURST_W];
            end
            for (sel_m_i = 0; sel_m_i < NUM_M; sel_m_i = sel_m_i + 1) begin
                if (grant_oh_r[sel_s_i][sel_m_i] && s_arready_i[sel_s_i])
                    m_arready_o[sel_m_i] = 1'b1;
            end
        end
    end

    // RREADY routing is deliberately isolated from R payload selection.  This
    // prevents a false payload->READY->payload combinational dependency when
    // two parameterised fabrics are composed hierarchically.
    always @* begin
        for (rrdy_s_i = 0; rrdy_s_i < NUM_S; rrdy_s_i = rrdy_s_i + 1) begin
            s_rready_o[rrdy_s_i] = 1'b0;
            for (rrdy_m_i = 0; rrdy_m_i < NUM_M;
                 rrdy_m_i = rrdy_m_i + 1) begin
                if (pick_oh_r[rrdy_m_i][rrdy_s_i] &&
                    m_rready_i[rrdy_m_i])
                    s_rready_o[rrdy_s_i] = 1'b1;
            end
        end
    end

    // ========================================================================
    // Fail-stop timeout (design §6.3): countdown runs while the master has
    // outstanding transactions; any accepted R beat is progress and reloads
    // it.  Expiry latches a sticky fail-stop that only blocks NEW ARs from
    // that master (accepted transactions drain or wait for reset) — the
    // fabric never fabricates R responses.  With single-outstanding masters
    // the latched id/addr identify the hung transaction exactly.
    // ========================================================================
    localparam TMO_W = (RD_TIMEOUT_CYCLES <= 1) ? 1 : clog2(RD_TIMEOUT_CYCLES + 1);
    localparam [TMO_W-1:0] TMO_MAX = RD_TIMEOUT_CYCLES[TMO_W-1:0];

    reg [TMO_W-1:0]   rd_tmo_cnt_r [0:NUM_M-1];
    reg [ID_W-1:0]    fs_rd_id_r   [0:NUM_M-1];
    reg [ADDR_W-1:0]  fs_rd_addr_r [0:NUM_M-1];

    // Keep monitor state at module scope.  Some Verilog-2001 synthesis tools
    // cannot resolve an unpacked array through a named generate hierarchy.
    reg [31:0] mon_rd_beats_r   [0:NUM_M-1];
    reg [31:0] mon_rd_bursts_r  [0:NUM_M-1];
    reg [31:0] mon_rd_err_r     [0:NUM_M-1];
    reg [31:0] mon_rd_wait_r    [0:NUM_M-1];
    reg [31:0] mon_rd_maxwait_r [0:NUM_M-1];
    // ========================================================================
    // AXI monitor (§4.3/§6.3): per-master beats, bursts, error beats and
    // maximum AR-fire-to-RLAST wait.  Physically removed when disabled.
    // ========================================================================
    generate
        if (AXI_MON_ENABLE != 0) begin : gen_rd_mon
            integer mi;
            always @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    for (mi = 0; mi < NUM_M; mi = mi + 1) begin
                        mon_rd_beats_r[mi]   <= 32'h0;
                        mon_rd_bursts_r[mi]  <= 32'h0;
                        mon_rd_err_r[mi]     <= 32'h0;
                        mon_rd_wait_r[mi]    <= 32'h0;
                        mon_rd_maxwait_r[mi] <= 32'h0;
                    end
                end else begin
                    for (mi = 0; mi < NUM_M; mi = mi + 1) begin
                        if (ar_fire_w[mi]) begin
                            mon_rd_bursts_r[mi] <= mon_rd_bursts_r[mi] + 1'b1;
                            mon_rd_wait_r[mi]   <= 32'h0;
                        end
                        if (r_accept_w[mi]) begin
                            mon_rd_beats_r[mi] <= mon_rd_beats_r[mi] + 1'b1;
                            if (m_rresp_o[mi*RESP_W +: RESP_W] != `AXI_RESP_OKAY)
                                mon_rd_err_r[mi] <= mon_rd_err_r[mi] + 1'b1;
                            mon_rd_wait_r[mi] <= mon_rd_wait_r[mi] + 1'b1;
                            if (m_rlast_o[mi] &&
                                (mon_rd_wait_r[mi] + 1'b1 > mon_rd_maxwait_r[mi]))
                                mon_rd_maxwait_r[mi] <= mon_rd_wait_r[mi] + 1'b1;
                        end
                    end
                end
            end
        end
    endgenerate

    genvar mon_g;
    generate
        for (mon_g = 0; mon_g < NUM_M; mon_g = mon_g + 1) begin : gen_rd_mon_w
            if (AXI_MON_ENABLE != 0) begin : gen_wires_on
                assign mon_rd_beats_o[mon_g*32 +: 32]   = mon_rd_beats_r[mon_g];
                assign mon_rd_bursts_o[mon_g*32 +: 32]  = mon_rd_bursts_r[mon_g];
                assign mon_rd_err_o[mon_g*32 +: 32]     = mon_rd_err_r[mon_g];
                assign mon_rd_maxwait_o[mon_g*32 +: 32] = mon_rd_maxwait_r[mon_g];
            end
        end
    endgenerate

    generate
        if (AXI_MON_ENABLE == 0) begin : gen_rd_mon_off
            assign mon_rd_beats_o   = {NUM_M*32{1'b0}};
            assign mon_rd_bursts_o  = {NUM_M*32{1'b0}};
            assign mon_rd_err_o     = {NUM_M*32{1'b0}};
            assign mon_rd_maxwait_o = {NUM_M*32{1'b0}};
        end
    endgenerate

    assign fs_rd_fail_o = fs_rd_r;
    genvar fs_rd_g;
    generate
        for (fs_rd_g = 0; fs_rd_g < NUM_M; fs_rd_g = fs_rd_g + 1) begin : gen_fs_rd_out
            assign fs_rd_addr_o[fs_rd_g*ADDR_W +: ADDR_W] = fs_rd_addr_r[fs_rd_g];
            assign fs_rd_id_o[fs_rd_g*ID_W +: ID_W]       = fs_rd_id_r[fs_rd_g];
        end
    endgenerate

    wire [NUM_S-1:0] ar_fire_s_w = s_arvalid_o & s_arready_i;

    // ========================================================================
    // Sequential state: RR pointers, burst holds, error responder, counters.
    // ========================================================================
    integer seq_m_i;
    integer seq_s_i;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (seq_m_i = 0; seq_m_i < NUM_M; seq_m_i = seq_m_i + 1) begin
                rd_cnt_r[seq_m_i]   <= {CNT_W{1'b0}};
                hold_oh_r[seq_m_i]  <= {(NUM_S+1){1'b0}};
                hold_v_r[seq_m_i]   <= 1'b0;
                src_ptr_r[seq_m_i]  <= {SRC_W{1'b0}};
                err_busy_r[seq_m_i] <= 1'b0;
                err_id_r[seq_m_i]   <= {ID_W{1'b0}};
                err_left_r[seq_m_i] <= {LEN_W{1'b0}};
                single_owner_oh_r[seq_m_i] <= {NUM_S{1'b0}};
                single_owner_id_r[seq_m_i] <= {ID_W{1'b0}};
            end
            for (seq_s_i = 0; seq_s_i < NUM_S; seq_s_i = seq_s_i + 1)
                rr_ptr_r[seq_s_i] <= {MI_W{1'b0}};
            for (seq_m_i = 0; seq_m_i < NUM_M; seq_m_i = seq_m_i + 1) begin
                fs_rd_r[seq_m_i]      <= 1'b0;
                rd_tmo_cnt_r[seq_m_i] <= {TMO_W{1'b0}};
                fs_rd_id_r[seq_m_i]   <= {ID_W{1'b0}};
                fs_rd_addr_r[seq_m_i] <= {ADDR_W{1'b0}};
            end
        end else begin
            for (seq_m_i = 0; seq_m_i < NUM_M; seq_m_i = seq_m_i + 1) begin
                // Single-entry form of an AXI demux route table.  Connectivity
                // participates in capture as well as admission, allowing
                // constant masks in a fixed SoC map to prune impossible route
                // bits during synthesis.
                if (M_MAX_OUTSTANDING == 1) begin
                    if (ar_fire_w[seq_m_i]) begin
                        single_owner_oh_r[seq_m_i] <= {NUM_S{1'b0}};
                        single_owner_id_r[seq_m_i] <=
                            m_arid_i[seq_m_i*ID_W +: ID_W];
                        for (seq_s_i = 0; seq_s_i < NUM_S;
                             seq_s_i = seq_s_i + 1) begin
                            if (m_read_connect_i[seq_m_i*NUM_S + seq_s_i] &&
                                (hit_tgt_r[seq_m_i] ==
                                 seq_s_i[TGT_W-1:0]))
                                single_owner_oh_r[seq_m_i][seq_s_i] <= 1'b1;
                        end
                    end else if (r_last_fire_w[seq_m_i]) begin
                        single_owner_oh_r[seq_m_i] <= {NUM_S{1'b0}};
                    end
                end

                // Outstanding count: +1 per accepted AR, -1 per accepted RLAST.
                rd_cnt_r[seq_m_i] <= rd_cnt_r[seq_m_i]
                    + (ar_fire_w[seq_m_i] ? {{(CNT_W-1){1'b0}}, 1'b1} : {CNT_W{1'b0}})
                    - (r_last_fire_w[seq_m_i] ? {{(CNT_W-1){1'b0}}, 1'b1} : {CNT_W{1'b0}});

                // Error read responder lifecycle.
                if (ar_fire_w[seq_m_i] && (hit_tgt_r[seq_m_i] == TGT_ERROR)) begin
                    err_busy_r[seq_m_i] <= 1'b1;
                    err_id_r[seq_m_i]   <= m_arid_i[seq_m_i*ID_W +: ID_W];
                    err_left_r[seq_m_i] <= m_arlen_i[seq_m_i*LEN_W +: LEN_W];
                end else if (pick_err_r[seq_m_i] && r_accept_w[seq_m_i]) begin
                    if (err_left_r[seq_m_i] == 0)
                        err_busy_r[seq_m_i] <= 1'b0;
                    else
                        err_left_r[seq_m_i] <= err_left_r[seq_m_i] - 1'b1;
                end

                // Fail-stop timeout: reload on any accepted beat, count down
                // while transactions are outstanding, latch sticky fail-stop
                // (and the frozen first-error context) on expiry.
                if (RD_TIMEOUT_CYCLES != 0) begin
                    if (ar_fire_w[seq_m_i]) begin
                        rd_tmo_cnt_r[seq_m_i] <= TMO_MAX;
                        fs_rd_id_r[seq_m_i]   <= m_arid_i[seq_m_i*ID_W +: ID_W];
                        fs_rd_addr_r[seq_m_i] <= m_araddr_i[seq_m_i*ADDR_W +: ADDR_W];
                    end else if (!fs_rd_r[seq_m_i] && (rd_cnt_r[seq_m_i] != 0)) begin
                        if (r_accept_w[seq_m_i])
                            rd_tmo_cnt_r[seq_m_i] <= TMO_MAX;
                        else if (rd_tmo_cnt_r[seq_m_i] == 0)
                            fs_rd_r[seq_m_i] <= 1'b1;
                        else
                            rd_tmo_cnt_r[seq_m_i] <= rd_tmo_cnt_r[seq_m_i] - 1'b1;
                    end
                end

                // R source hold: release on burst completion (advancing the
                // source RR pointer), otherwise lock the current pick so
                // mid-burst candidates cannot steal the channel.
                if (r_last_fire_w[seq_m_i]) begin
                    hold_v_r[seq_m_i]  <= 1'b0;
                    src_ptr_r[seq_m_i] <= pick_err_r[seq_m_i]
                        ? SRC_ERROR
                        : pick_idx_r[seq_m_i] + 1'b1;
                end else if (!hold_v_r[seq_m_i] && pick_valid_r[seq_m_i]) begin
                    hold_v_r[seq_m_i]  <= 1'b1;
                    hold_oh_r[seq_m_i] <= pick_oh_r[seq_m_i];
                end
            end

            // Per-slave AR round-robin pointer.
            for (seq_s_i = 0; seq_s_i < NUM_S; seq_s_i = seq_s_i + 1) begin
                if (ar_fire_s_w[seq_s_i]) begin
                    if (grant_idx_r[seq_s_i] == M_LAST_IDX)
                        rr_ptr_r[seq_s_i] <= {MI_W{1'b0}};
                    else
                        rr_ptr_r[seq_s_i] <= grant_idx_r[seq_s_i] + 1'b1;
                end
            end
        end
    end

endmodule
