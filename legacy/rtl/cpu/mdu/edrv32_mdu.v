// ============================================================================
// File        : edrv32_mdu.v
// Description : One-slot decoupled RV32M execution unit.  This module owns only
//               operation dispatch, COMMIT authorization and the common result
//               slot.  Arithmetic is implemented by the adapted legacy-derived
//               multiplier and non-restoring divider modules.
// Registering : Slot lifecycle, authorization, completion, request identity and
//               result payload are intentionally stored in separate blocks.
// ============================================================================
`include "edrv32_uop.vh"

module edrv32_mdu #(
    parameter integer MUL_USE_PANGO_APM = 0,
    parameter integer MUL_FAST_LOW = 1,
    parameter integer MUL_LOW_PIPE_STAGES = 2
)(
    input  wire                         clk_i,
    input  wire                         rst_n_i,

    input  wire                         req_valid_i,
    output wire                         req_ready_o,
    input  wire [`EDRV32_MDU_OP_W-1:0] req_op_i,
    input  wire [31:0]                  req_lhs_i,
    input  wire [31:0]                  req_rhs_i,
    input  wire [31:0]                  req_mul_lhs_i,
    input  wire [31:0]                  req_mul_rhs_i,
    input  wire [31:0]                  req_div_lhs_i,
    input  wire [31:0]                  req_div_rhs_i,
    input  wire [4:0]                   req_rd_i,

    input  wire                         authorize_i,
    input  wire                         cancel_i,

    output wire                         result_valid_o,
    input  wire                         result_ready_i,
    output wire [4:0]                   result_rd_o,
    output wire [31:0]                  result_data_o,

    output wire                         slot_valid_o,
    output wire                         result_complete_o,
    output wire                         authorized_o
);

    reg slot_valid_r;
    reg authorized_r;
    reg result_complete_r;
    reg [4:0] request_rd_r;
    reg [31:0] result_data_r;

    wire request_is_division_w = req_op_i[2];
    wire request_fire_w = req_valid_i && req_ready_o;
    wire result_fire_w = result_valid_o && result_ready_i;

    wire multiply_result_valid_w;
    wire [31:0] multiply_result_data_w;
    wire low_multiply_request_w = (MUL_FAST_LOW != 0) &&
        (req_op_i == `EDRV32_MDU_MUL);
    wire legacy_multiply_start_w = request_fire_w && !request_is_division_w &&
        !low_multiply_request_w;
    wire legacy_multiply_valid_w;
    wire [31:0] legacy_multiply_data_w;
    wire low_multiply_valid_w;
    wire [31:0] low_multiply_data_w;
    generate
        if ((MUL_FAST_LOW != 0) &&
            (MUL_LOW_PIPE_STAGES == 1)) begin : gen_short_low_multiplier
            edrv32_mul_low32_pipe1 u_low_multiplier (
                .clk_i(clk_i),
                .rst_n_i(rst_n_i),
                .flush_i(cancel_i),
                .start_i(request_fire_w && low_multiply_request_w),
                .lhs_i(req_mul_lhs_i),
                .rhs_i(req_mul_rhs_i),
                .result_valid_o(low_multiply_valid_w),
                .result_o(low_multiply_data_w)
            );
        end else if (MUL_FAST_LOW != 0) begin : gen_fast_low_multiplier
            edrv32_mul_low32_pipe2 u_low_multiplier (
                .clk_i(clk_i),
                .rst_n_i(rst_n_i),
                .flush_i(cancel_i),
                .start_i(request_fire_w && low_multiply_request_w),
                .lhs_i(req_lhs_i),
                .rhs_i(req_rhs_i),
                .result_valid_o(low_multiply_valid_w),
                .result_o(low_multiply_data_w)
            );
        end else begin : gen_legacy_low_multiplier
            assign low_multiply_valid_w = 1'b0;
            assign low_multiply_data_w = 32'd0;
        end
    endgenerate
    assign multiply_result_valid_w = legacy_multiply_valid_w || low_multiply_valid_w;
    assign multiply_result_data_w = low_multiply_valid_w
        ? low_multiply_data_w : legacy_multiply_data_w;
    generate
        if (MUL_USE_PANGO_APM != 0) begin : gen_pango_multiplier
            edrv32_mul_pango_apm u_multiplier (
                .clk_i          (clk_i),
                .rst_n_i        (rst_n_i),

                // Operation launch and cancellation.
                .flush_i        (cancel_i),
                .start_i        (legacy_multiply_start_w),
                .operation_i    (req_op_i),
                .lhs_i          (req_lhs_i),
                .rhs_i          (req_rhs_i),

                // Completed multiply result.
                .result_valid_o (legacy_multiply_valid_w),
                .result_o       (legacy_multiply_data_w)
            );
        end else begin : gen_portable_multiplier
            edrv32_mul_booth4_wallace u_multiplier (
                .clk_i          (clk_i),
                .rst_n_i        (rst_n_i),

                // Operation launch and cancellation.
                .flush_i        (cancel_i),
                .start_i        (legacy_multiply_start_w),
                .operation_i    (req_op_i),
                .lhs_i          (req_lhs_i),
                .rhs_i          (req_rhs_i),

                // Completed multiply result.
                .result_valid_o (legacy_multiply_valid_w),
                .result_o       (legacy_multiply_data_w)
            );
        end
    endgenerate

    wire divider_request_ready_w;
    wire divider_result_valid_w;
    wire divider_result_ready_w;
    wire [31:0] divider_result_data_w;
    wire unused_divider_busy_w;
    edrv32_div_nonrestoring u_divider (
        .clk_i          (clk_i),
        .rst_n_i        (rst_n_i),

        // Iterative divide request and cancellation.
        .req_valid_i    (request_fire_w && request_is_division_w),
        .req_ready_o    (divider_request_ready_w),
        .req_op_i       (req_op_i),
        .req_lhs_i      (req_div_lhs_i),
        .req_rhs_i      (req_div_rhs_i),
        .cancel_i       (cancel_i),

        // Completed divide result.
        .result_valid_o (divider_result_valid_w),
        .result_ready_i (divider_result_ready_w),
        .result_data_o  (divider_result_data_w),
        .busy_o         (unused_divider_busy_w)
    );

    // The common MDU slot is the architectural capacity limit.  Whenever it is
    // empty the divider is necessarily idle as well; the explicit ready term is
    // retained as a local invariant check in the request path.
    assign req_ready_o = ~slot_valid_r &&
                         (!request_is_division_w || divider_request_ready_w);
    assign divider_result_ready_w = slot_valid_r && !result_complete_r;

    wire multiply_complete_w = multiply_result_valid_w && slot_valid_r &&
                               !result_complete_r;
    wire divide_complete_w = divider_result_valid_w && divider_result_ready_w;

    // Both arithmetic backends present registered completion data.  Expose
    // that last backend stage immediately instead of adding an otherwise
    // redundant common-slot cycle.  If COMMIT cannot consume it in this
    // cycle, the payload is captured below and held by result_complete_r.
    wire arithmetic_complete_w = multiply_complete_w || divide_complete_w;
    wire [31:0] arithmetic_result_data_w = divide_complete_w
        ? divider_result_data_w : multiply_result_data_w;
    wire completion_visible_w = result_complete_r || arithmetic_complete_w;

    // A completed operation may write back on the same edge that COMMIT
    // retires its token.  An unfinished operation still retains authorization
    // and completes later.  Request capacity remains registered: releasing
    // this slot never creates a COMMIT-to-EX transparent allocation path.
    assign result_valid_o = slot_valid_r && completion_visible_w &&
                            (authorized_r || authorize_i);
    assign result_rd_o = request_rd_r;
    assign result_data_o = result_complete_r
        ? result_data_r : arithmetic_result_data_w;
    assign slot_valid_o = slot_valid_r;
    assign result_complete_o = completion_visible_w;
    assign authorized_o = authorized_r;

    // Common-slot handshake lifecycle only.
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i)
            slot_valid_r <= 1'b0;
        else if (cancel_i)
            slot_valid_r <= 1'b0;
        else if (result_fire_w)
            slot_valid_r <= 1'b0;
        else if (request_fire_w)
            slot_valid_r <= 1'b1;
    end

    // COMMIT authorization lifecycle only.
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i)
            authorized_r <= 1'b0;
        else if (cancel_i || result_fire_w || request_fire_w)
            authorized_r <= 1'b0;
        else if (authorize_i && slot_valid_r)
            authorized_r <= 1'b1;
    end

    // Arithmetic-completion state only.
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i)
            result_complete_r <= 1'b0;
        else if (cancel_i || result_fire_w || request_fire_w)
            result_complete_r <= 1'b0;
        else if (arithmetic_complete_w)
            result_complete_r <= 1'b1;
    end

    // Request identity payload only.
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i)
            request_rd_r <= 5'd0;
        else if (request_fire_w)
            request_rd_r <= req_rd_i;
    end

    // Completed arithmetic payload only.
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i)
            result_data_r <= 32'd0;
        else if (arithmetic_complete_w)
            result_data_r <= arithmetic_result_data_w;
    end

endmodule
