// ============================================================================
// File        : reset_ctrl.v
// Author      : Edward ZC
// Description : Reset controller — ext_rst_n_i async assert, sync release.
//               WDT reset request pulse stretches to STRETCH_CYCLES min.
//               Debug 1.0 (2026-08): ndmreset/hartreset from the Debug Module
//               are level requests folded into the synchronizer so release is
//               always glitch-free.  Three domains:
//                 rst_n_o      SoC domain  = ext + WDT + ndmreset
//                 hart_rst_n_o hart domain = ext + WDT + ndmreset + hartreset
//                 dm_rst_n_o   DM domain   = ext + WDT (never ndmreset;
//                              the Debug Module must survive ndmreset)
// ============================================================================
module reset_ctrl #(
    parameter STRETCH_CYCLES = 4
)(
    input  wire         clk,
    input  wire         ext_rst_n_i,
    input  wire         wdt_reset_req_i,
    input  wire         ndmreset_req_i,
    input  wire         hartreset_req_i,
    output wire         rst_n_o,
    output wire         hart_rst_n_o,
    output wire         dm_rst_n_o,
    output wire         wdt_req_latched_o
);

    reg [1:0] sync_r;
    reg [2:0] cnt_r;
    reg       rst_r;
    reg       hart_rst_r;
    reg       dm_rst_r;
    reg       wdt_seen_r;

    // External reset asserts all reset state asynchronously. The synchronizer
    // controls only external-reset release.
    always @(posedge clk or negedge ext_rst_n_i) begin
        if (!ext_rst_n_i) begin
            sync_r <= 2'b00;
        end else begin
            sync_r <= {sync_r[0], 1'b1};
        end
    end

    // A WDT request loads the stretch counter once. It then decreases
    // monotonically; the cause latch must not reload it every cycle.
    always @(posedge clk or negedge ext_rst_n_i) begin
        if (!ext_rst_n_i) begin
            cnt_r <= 3'b0;
        end else if (!sync_r[1]) begin
            cnt_r <= 3'b0;
        end else if (wdt_reset_req_i) begin
            cnt_r <= STRETCH_CYCLES[2:0];
        end else if (cnt_r > 0) begin
            cnt_r <= cnt_r - 1'b1;
        end
    end

    // SoC domain: ext + WDT + ndmreset (level).
    always @(posedge clk or negedge ext_rst_n_i) begin
        if (!ext_rst_n_i) begin
            rst_r <= 1'b0;
        end else if (!sync_r[1] || wdt_reset_req_i || ndmreset_req_i ||
                     (cnt_r > 1)) begin
            rst_r <= 1'b0;
        end else begin
            rst_r <= 1'b1;
        end
    end

    // Hart domain: additionally gated by hartreset (level).
    always @(posedge clk or negedge ext_rst_n_i) begin
        if (!ext_rst_n_i) begin
            hart_rst_r <= 1'b0;
        end else if (!sync_r[1] || wdt_reset_req_i || ndmreset_req_i ||
                     hartreset_req_i || (cnt_r > 1)) begin
            hart_rst_r <= 1'b0;
        end else begin
            hart_rst_r <= 1'b1;
        end
    end

    // DM domain: never ndmreset/hartreset — the Debug Module survives both.
    always @(posedge clk or negedge ext_rst_n_i) begin
        if (!ext_rst_n_i) begin
            dm_rst_r <= 1'b0;
        end else if (!sync_r[1] || wdt_reset_req_i || (cnt_r > 1)) begin
            dm_rst_r <= 1'b0;
        end else begin
            dm_rst_r <= 1'b1;
        end
    end

    // Request capture has priority over idle-state clear. The latch remains
    // visible through the reset interval so SYSCTRL can record a sticky cause.
    always @(posedge clk or negedge ext_rst_n_i) begin
        if (!ext_rst_n_i) begin
            wdt_seen_r <= 1'b0;
        end else if (wdt_reset_req_i) begin
            wdt_seen_r <= 1'b1;
        end else if (rst_r && (cnt_r == 0)) begin
            wdt_seen_r <= 1'b0;
        end
    end

    assign rst_n_o           = rst_r;
    assign hart_rst_n_o      = hart_rst_r;
    assign dm_rst_n_o        = dm_rst_r;
    assign wdt_req_latched_o = wdt_seen_r;

endmodule
