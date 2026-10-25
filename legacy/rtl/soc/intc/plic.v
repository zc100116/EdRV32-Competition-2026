// ============================================================================
// File        : plic.v
// Author      : Edward ZC
// Description : Single M-context 32-source platform-level interrupt
//               controller (competition design §6.5.1).  The M-context drives
//               MEIP (irq_ext_o); the S-context is physically removed.
// Notes       : Source 0 is reserved. Priority and threshold are 3 bit. The
//               system target uses the Native valid/ready request/response
//               protocol and level-sensitive gateways with inflight tracking.
//               Enable, threshold and claim/complete are M-context only
//               (single-context PLIC).  Register offsets keep the SiFive
//               single-context layout (design §6.5.1).
// ============================================================================
`include "edrv32_bus.vh"

// ============================================================================
// plic - machine external interrupt controller (single context)
// ============================================================================
module plic #(
    parameter integer NUM_SOURCES = 32,
    parameter integer PRIO_W      = 3
)(
    // --- Clock and reset ---
    input  wire                     clk,
    input  wire                     rst_n,

    // --- Native request channel ---
    input  wire                     req_valid_i,
    output wire                     req_ready_o,
    input  wire [`XLEN-1:0]         req_addr_i,
    input  wire                     req_we_i,
    input  wire [3:0]               req_wstrb_i,
    input  wire [31:0]              req_wdata_i,

    // --- Native response channel ---
    input  wire                     resp_ready_i,
    output wire                     resp_valid_o,
    output wire [31:0]              resp_rdata_o,
    output wire                     resp_error_o,

    // --- Interrupt gateway and context outputs ---
    input  wire [NUM_SOURCES-1:0]   src_i,
    output wire                     irq_ext_o
);

    localparam [23:0] OFF_PRIORITY_LAST = 24'h00_007C;
    localparam [23:0] OFF_PENDING       = 24'h00_1000;
    localparam [23:0] OFF_ENABLE        = 24'h00_2000;
    localparam [23:0] OFF_THRESHOLD     = 24'h20_0000;
    localparam [23:0] OFF_CLAIM         = 24'h20_0004;

    localparam STATE_IDLE = 1'b0;
    localparam STATE_RESP = 1'b1;

    wire [23:0] off_w = req_addr_i[23:0];
    wire aligned_w = req_addr_i[1:0] == 2'b00;
    wire priority_access_w =
        aligned_w && off_w <= OFF_PRIORITY_LAST;
    wire pending_access_w = aligned_w && off_w == OFF_PENDING;
    wire enable_access_w = aligned_w && off_w == OFF_ENABLE;
    wire threshold_access_w = aligned_w && off_w == OFF_THRESHOLD;
    wire claim_access_w = aligned_w && off_w == OFF_CLAIM;
    wire valid_access_w =
        priority_access_w || pending_access_w ||
        enable_access_w || threshold_access_w || claim_access_w;
    wire [4:0] priority_index_w = off_w[6:2];

    wire [7:0] unused_req_addr_upper_w = req_addr_i[31:24];
    wire unused_src_zero_w = src_i[0];

    reg [PRIO_W-1:0] priority_r [0:NUM_SOURCES-1];
    reg [NUM_SOURCES-1:0] pending_r;
    reg [NUM_SOURCES-1:0] inflight_r;
    reg [NUM_SOURCES-1:0] enable_r;
    reg [PRIO_W-1:0] threshold_r;

    // ------------------------------------------------------------------------
    // Linear highest-priority selection. Ascending traversal and strict
    // priority replacement preserve the lowest source ID on ties.  The single
    // M-context gates on its own enable bitmap and threshold.
    // ------------------------------------------------------------------------
    reg [4:0] best_id_w;
    reg [PRIO_W-1:0] best_priority_w;
    integer arbitration_source;
    always @* begin
        best_id_w = 5'd0;
        best_priority_w = {PRIO_W{1'b0}};
        for (arbitration_source = 1;
             arbitration_source < NUM_SOURCES;
             arbitration_source = arbitration_source + 1) begin
            if (pending_r[arbitration_source] &&
                enable_r[arbitration_source] &&
                priority_r[arbitration_source] > threshold_r &&
                priority_r[arbitration_source] > best_priority_w) begin
                best_id_w = arbitration_source[4:0];
                best_priority_w = priority_r[arbitration_source];
            end
        end
    end

    // Register the context notification at the PLIC boundary.  The pending,
    // priority and claim/complete state remains authoritative inside this
    // block; only the asynchronous architectural notification is delayed by
    // one cycle.  Besides giving the PLIC a clean registered output, this
    // prevents the priority encoder from extending through the core's trap
    // and redirect logic in the same timing path.
    reg irq_ext_r;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            irq_ext_r <= 1'b0;
        else
            irq_ext_r <= best_id_w != 5'd0;
    end

    assign irq_ext_o = irq_ext_r;

    // ------------------------------------------------------------------------
    // Two-phase Native target. One request is outstanding at a time and the
    // response payload is retained until the upstream accepts it.
    // ------------------------------------------------------------------------
    reg state_r;
    reg [31:0] response_data_r;
    reg response_error_r;

    assign req_ready_o = state_r == STATE_IDLE;
    assign resp_valid_o = state_r == STATE_RESP;
    assign resp_rdata_o = response_data_r;
    assign resp_error_o = response_error_r;

    wire accept_w = req_valid_i && req_ready_o;
    wire claim_read_w =
        accept_w && !req_we_i && claim_access_w;
    wire complete_write_w =
        accept_w && req_we_i && claim_access_w && req_wstrb_i[0];
    wire [4:0] complete_id_w = req_wdata_i[4:0];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state_r <= STATE_IDLE;
        end else begin
            case (state_r)
                STATE_IDLE: begin
                    if (req_valid_i)
                        state_r <= STATE_RESP;
                end
                STATE_RESP: begin
                    if (resp_ready_i)
                        state_r <= STATE_IDLE;
                end
                default: state_r <= STATE_IDLE;
            endcase
        end
    end

    reg [31:0] read_data_w;
    always @* begin
        read_data_w = 32'b0;
        if (priority_access_w) begin
            if (priority_index_w != 5'd0)
                read_data_w =
                    {{(32-PRIO_W){1'b0}}, priority_r[priority_index_w]};
        end else if (pending_access_w) begin
            read_data_w = pending_r;
        end else if (enable_access_w) begin
            read_data_w = enable_r;
        end else if (threshold_access_w) begin
            read_data_w = {{(32-PRIO_W){1'b0}}, threshold_r};
        end else if (claim_access_w) begin
            read_data_w = {27'b0, best_id_w};
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            response_data_r <= 32'b0;
            response_error_r <= 1'b0;
        end else if (accept_w) begin
            response_data_r <= req_we_i ? 32'b0 : read_data_w;
            response_error_r <= !valid_access_w;
        end
    end

    // ------------------------------------------------------------------------
    // Priority configuration. Per-source processes avoid multi-driven arrays
    // and make source 0's read-only-zero behavior explicit.
    // ------------------------------------------------------------------------
    genvar priority_source;
    generate
        for (priority_source = 0;
             priority_source < NUM_SOURCES;
             priority_source = priority_source + 1) begin : gen_priority
            always @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    priority_r[priority_source] <= {PRIO_W{1'b0}};
                end else if (priority_source != 0 &&
                             accept_w && req_we_i &&
                             priority_access_w &&
                             priority_index_w == priority_source[4:0] &&
                             req_wstrb_i[0]) begin
                    priority_r[priority_source] <=
                        req_wdata_i[PRIO_W-1:0];
                end
            end
        end
    endgenerate

    // ------------------------------------------------------------------------
    // M-context enable bitmap. Source 0 is pinned to disabled.
    // ------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            enable_r <= {NUM_SOURCES{1'b0}};
        end else if (accept_w && req_we_i && enable_access_w) begin
            enable_r[0] <= 1'b0;
            if (req_wstrb_i[0])
                enable_r[7:1] <= req_wdata_i[7:1];
            if (req_wstrb_i[1])
                enable_r[15:8] <= req_wdata_i[15:8];
            if (req_wstrb_i[2])
                enable_r[23:16] <= req_wdata_i[23:16];
            if (req_wstrb_i[3])
                enable_r[31:24] <= req_wdata_i[31:24];
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            threshold_r <= {PRIO_W{1'b0}};
        end else if (accept_w && req_we_i &&
                     threshold_access_w && req_wstrb_i[0]) begin
            threshold_r <= req_wdata_i[PRIO_W-1:0];
        end
    end

    // ------------------------------------------------------------------------
    // Level gateways. A claimed source remains inflight until its matching
    // completion. Hardware level observation and completion re-pend are
    // resolved in one next-state function. The single M-context claim/completion
    // clears / releases the shared pending and inflight bits.
    // ------------------------------------------------------------------------
    reg [NUM_SOURCES-1:0] pending_next_w;
    reg [NUM_SOURCES-1:0] inflight_next_w;
    integer gateway_source;
    always @* begin
        pending_next_w = pending_r;
        inflight_next_w = inflight_r;
        pending_next_w[0] = 1'b0;
        inflight_next_w[0] = 1'b0;

        for (gateway_source = 1;
             gateway_source < NUM_SOURCES;
             gateway_source = gateway_source + 1) begin
            if (!inflight_r[gateway_source] && src_i[gateway_source])
                pending_next_w[gateway_source] = 1'b1;
        end

        if (claim_read_w && best_id_w != 5'd0) begin
            pending_next_w[best_id_w] = 1'b0;
            inflight_next_w[best_id_w] = 1'b1;
        end

        if (complete_write_w &&
            complete_id_w != 5'd0 &&
            inflight_r[complete_id_w]) begin
            inflight_next_w[complete_id_w] = 1'b0;
            if (src_i[complete_id_w])
                pending_next_w[complete_id_w] = 1'b1;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pending_r <= {NUM_SOURCES{1'b0}};
            inflight_r <= {NUM_SOURCES{1'b0}};
        end else begin
            pending_r <= pending_next_w;
            inflight_r <= inflight_next_w;
        end
    end

endmodule
