// ============================================================================
// File        : edrv32_axi_m2s_arbiter.v
// Description : Burst-granular AXI shared-slave scheduler. Urgent or starved
//               requests
//               take precedence; normal requests select the highest AXI QoS
//               class and use weighted round-robin within that class.
// Notes       : A grant is held only by the caller's request/payload buffer.
//               State advances on fire_i, never merely on combinational grant.
// ============================================================================

module edrv32_axi_m2s_arbiter #(
    parameter integer NUM_M = 4,
    parameter integer STARVE_CYCLES = 64,
    parameter integer MI_W = (NUM_M <= 1) ? 1 : $clog2(NUM_M),
    parameter integer AGE_W = (STARVE_CYCLES <= 1) ? 1 : $clog2(STARVE_CYCLES + 1)
) (
    input  wire                     clk_i,
    input  wire                     rst_n_i,

    input  wire [NUM_M-1:0]         req_i,
    input  wire [NUM_M*4-1:0]       qos_i,
    input  wire [NUM_M*4-1:0]       weight_i,
    input  wire [NUM_M-1:0]         urgent_i,

    output wire [NUM_M-1:0]         grant_o,
    output wire                     grant_valid_o,
    output wire [MI_W-1:0]          grant_index_o,
    input  wire                     fire_i
);

    localparam [AGE_W-1:0] STARVE_LIMIT = STARVE_CYCLES[AGE_W-1:0];
    localparam [MI_W-1:0] LAST_MASTER = NUM_M[MI_W-1:0] - 1'b1;

    reg [AGE_W-1:0] age_r [0:NUM_M-1];
    reg [MI_W-1:0] rr_ptr_r;
    reg [3:0] quota_r;
    reg hold_valid_r;
    reg [MI_W-1:0] hold_index_r;
    reg hold_forced_r;
    reg [3:0] hold_weight_r;

    reg [NUM_M-1:0] grant_w;
    reg grant_valid_w;
    reg [MI_W-1:0] grant_index_w;
    reg [NUM_M-1:0] forced_w;
    reg [NUM_M-1:0] eligible_w;
    reg [3:0] max_qos_w;
    reg any_forced_w;
    integer arb_m_i;
    integer arb_off_i;
    integer arb_idx_i;

    assign grant_o = grant_w;
    assign grant_valid_o = grant_valid_w;
    assign grant_index_o = grant_index_w;

    always @(*) begin
        forced_w = {NUM_M{1'b0}};
        any_forced_w = 1'b0;
        max_qos_w = 4'd0;
        for (arb_m_i = 0; arb_m_i < NUM_M; arb_m_i = arb_m_i + 1) begin
            forced_w[arb_m_i] = req_i[arb_m_i] &&
                (urgent_i[arb_m_i] || (age_r[arb_m_i] == STARVE_LIMIT));
            any_forced_w = any_forced_w || forced_w[arb_m_i];
            if (req_i[arb_m_i] &&
                (qos_i[arb_m_i*4 +: 4] > max_qos_w))
                max_qos_w = qos_i[arb_m_i*4 +: 4];
        end

        eligible_w = {NUM_M{1'b0}};
        for (arb_m_i = 0; arb_m_i < NUM_M; arb_m_i = arb_m_i + 1) begin
            if (any_forced_w)
                eligible_w[arb_m_i] = forced_w[arb_m_i];
            else
                eligible_w[arb_m_i] = req_i[arb_m_i] &&
                    (qos_i[arb_m_i*4 +: 4] == max_qos_w);
        end

        grant_w = {NUM_M{1'b0}};
        grant_valid_w = 1'b0;
        grant_index_w = {MI_W{1'b0}};

        // Once a legal request is presented and stalls, its selection remains
        // fixed until fire_i. This is required by AXI payload stability.
        if (hold_valid_r) begin
            grant_w[hold_index_r] = 1'b1;
            grant_valid_w = 1'b1;
            grant_index_w = hold_index_r;
        end else if (!any_forced_w && (quota_r != 0) && eligible_w[rr_ptr_r]) begin
            grant_w[rr_ptr_r] = 1'b1;
            grant_valid_w = 1'b1;
            grant_index_w = rr_ptr_r;
        end else begin
            for (arb_off_i = 0; arb_off_i < NUM_M; arb_off_i = arb_off_i + 1) begin
                arb_idx_i = 0;
                arb_idx_i[MI_W-1:0] = rr_ptr_r;
                arb_idx_i = arb_idx_i + arb_off_i;
                if (arb_idx_i >= NUM_M)
                    arb_idx_i = arb_idx_i - NUM_M;
                if (!grant_valid_w && eligible_w[arb_idx_i]) begin
                    grant_w[arb_idx_i] = 1'b1;
                    grant_valid_w = 1'b1;
                    grant_index_w = arb_idx_i[MI_W-1:0];
                end
            end
        end
    end

    integer seq_m_i;
    reg [3:0] selected_weight_w;
    reg selected_forced_w;
    always @(*) begin
        selected_weight_w = hold_valid_r ? hold_weight_r : 4'd1;
        selected_forced_w = hold_valid_r ? hold_forced_r : any_forced_w;
        if (!hold_valid_r && grant_valid_w &&
            (weight_i[grant_index_w*4 +: 4] != 0))
            selected_weight_w = weight_i[grant_index_w*4 +: 4];
    end

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            rr_ptr_r <= {MI_W{1'b0}};
            quota_r <= 4'd0;
            hold_valid_r <= 1'b0;
            hold_index_r <= {MI_W{1'b0}};
            hold_forced_r <= 1'b0;
            hold_weight_r <= 4'd1;
            for (seq_m_i = 0; seq_m_i < NUM_M; seq_m_i = seq_m_i + 1)
                age_r[seq_m_i] <= {AGE_W{1'b0}};
        end else begin
            if (hold_valid_r) begin
                if (fire_i)
                    hold_valid_r <= 1'b0;
            end else if (grant_valid_w && !fire_i) begin
                hold_valid_r <= 1'b1;
                hold_index_r <= grant_index_w;
                hold_forced_r <= any_forced_w;
                hold_weight_r <= selected_weight_w;
            end

            for (seq_m_i = 0; seq_m_i < NUM_M; seq_m_i = seq_m_i + 1) begin
                if (!req_i[seq_m_i] ||
                    (fire_i && grant_w[seq_m_i]))
                    age_r[seq_m_i] <= {AGE_W{1'b0}};
                else if (age_r[seq_m_i] != STARVE_LIMIT)
                    age_r[seq_m_i] <= age_r[seq_m_i] + 1'b1;
            end

            if (fire_i && grant_valid_w) begin
                if (selected_forced_w) begin
                    rr_ptr_r <= (grant_index_w == LAST_MASTER)
                        ? {MI_W{1'b0}} : grant_index_w + 1'b1;
                    quota_r <= 4'd0;
                end else if ((grant_index_w == rr_ptr_r) && (quota_r != 0)) begin
                    if (quota_r == 4'd1) begin
                        rr_ptr_r <= (grant_index_w == LAST_MASTER)
                            ? {MI_W{1'b0}} : grant_index_w + 1'b1;
                        quota_r <= 4'd0;
                    end else begin
                        quota_r <= quota_r - 1'b1;
                    end
                end else if (selected_weight_w > 4'd1) begin
                    rr_ptr_r <= grant_index_w;
                    quota_r <= selected_weight_w - 1'b1;
                end else begin
                    rr_ptr_r <= (grant_index_w == LAST_MASTER)
                        ? {MI_W{1'b0}} : grant_index_w + 1'b1;
                    quota_r <= 4'd0;
                end
            end
        end
    end

endmodule
