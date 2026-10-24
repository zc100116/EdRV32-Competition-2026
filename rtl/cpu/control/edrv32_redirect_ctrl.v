// ============================================================================
// File        : edrv32_redirect_ctrl.v
// Description : Registered redirect arbitration. COMMIT events are older than EX
//               events and therefore always win.
// Notes       : The output slot does not transparently refill when consumed.
//               Redirects are rare; the extra idle cycle removes an
//               out_ready-to-EX combinational path.
// ============================================================================
`include "edrv32_isa.vh"
`include "edrv32_uop.vh"

module edrv32_redirect_ctrl (
    input  wire                              clk_i,
    input  wire                              rst_n_i,

    input  wire                              commit_exception_valid_i,
    input  wire [31:0]                       commit_exception_target_i,
    input  wire                              commit_interrupt_valid_i,
    input  wire [31:0]                       commit_interrupt_target_i,
    input  wire                              commit_mret_valid_i,
    input  wire [31:0]                       commit_mret_target_i,
    input  wire                              commit_fencei_valid_i,
    input  wire [31:0]                       commit_fencei_target_i,
    output wire                              commit_event_ready_o,

    input  wire                              ex_redirect_valid_i,
    input  wire [31:0]                       ex_redirect_target_i,
    output wire                              ex_event_ready_o,

    output wire                              redirect_valid_o,
    input  wire                              redirect_accept_i,
    output wire [31:0]                       redirect_target_o,
    output wire [`EDRV32_REDIRECT_REASON_W-1:0] redirect_reason_o,
    output wire [`EDRV32_EPOCH_W-1:0]        redirect_epoch_o
);

    reg                                      valid_r;
    reg [31:0]                               target_r;
    reg [`EDRV32_REDIRECT_REASON_W-1:0]      reason_r;
    reg [`EDRV32_EPOCH_W-1:0]                epoch_r;
    reg [`EDRV32_EPOCH_W-1:0]                event_epoch_r;

    wire commit_any_w = commit_exception_valid_i || commit_interrupt_valid_i ||
                        commit_mret_valid_i || commit_fencei_valid_i;
    wire selected_valid_w = commit_any_w || ex_redirect_valid_i;
    // Resolve age priority separately from target data. The late EX branch
    // decision must select an already computed target, not become an input
    // to arithmetic shared with a COMMIT trap-vector or fallthrough target.
    wire select_exception_w = commit_exception_valid_i;
    wire select_interrupt_w = !commit_exception_valid_i &&
                              commit_interrupt_valid_i;
    wire select_mret_w = !commit_exception_valid_i &&
                         !commit_interrupt_valid_i && commit_mret_valid_i;
    wire select_fencei_w = !commit_exception_valid_i &&
                           !commit_interrupt_valid_i &&
                           !commit_mret_valid_i && commit_fencei_valid_i;
    wire select_ex_w = !commit_any_w;
    wire [31:0] selected_target_w =
        (commit_exception_target_i & {32{select_exception_w}}) |
        (commit_interrupt_target_i & {32{select_interrupt_w}}) |
        (commit_mret_target_i & {32{select_mret_w}}) |
        (commit_fencei_target_i & {32{select_fencei_w}}) |
        (ex_redirect_target_i & {32{select_ex_w}});
    wire [`EDRV32_REDIRECT_REASON_W-1:0] selected_reason_w =
        commit_exception_valid_i ? `EDRV32_REDIR_EXCEPTION :
        commit_interrupt_valid_i ? `EDRV32_REDIR_INTERRUPT :
        commit_mret_valid_i      ? `EDRV32_REDIR_MRET :
        commit_fencei_valid_i    ? `EDRV32_REDIR_FENCEI :
                                   `EDRV32_REDIR_EX_BRANCH;

    assign commit_event_ready_o = ~valid_r;
    assign ex_event_ready_o     = ~valid_r && ~commit_any_w;

    assign redirect_valid_o  = valid_r;
    assign redirect_target_o = target_r;
    assign redirect_reason_o = reason_r;
    assign redirect_epoch_o  = event_epoch_r;

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            valid_r       <= 1'b0;
            epoch_r       <= {`EDRV32_EPOCH_W{1'b0}};
        end else begin
            if (redirect_accept_i && valid_r) begin
                valid_r <= 1'b0;
            end

            if (!valid_r) begin
                // Payload registers are written whenever the local slot is
                // empty.  Their write enable therefore depends only on the
                // registered slot state, not on the long EX mispredict cone.
                // The payload is architecturally observable only with valid_r.
                target_r <= selected_target_w;
                reason_r <= selected_reason_w;

                if (selected_valid_w) begin
                    valid_r       <= 1'b1;
                    epoch_r       <= epoch_r + {{(`EDRV32_EPOCH_W-1){1'b0}}, 1'b1};
                    event_epoch_r <= epoch_r + {{(`EDRV32_EPOCH_W-1){1'b0}}, 1'b1};
                end
            end
        end
    end

endmodule
