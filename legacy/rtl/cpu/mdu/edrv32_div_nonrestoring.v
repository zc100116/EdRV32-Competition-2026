// ============================================================================
// File        : edrv32_div_nonrestoring.v
// Description : Single-outstanding RV32M non-restoring divider.
// Provenance  : Datapath and corner-case behavior are adapted from the verified
//               pre-rewrite cpu/exec/div/div_nonrestoring.v implementation.
//               Only the clean-core interface and register ownership have been
//               rewritten.  Control state, iteration payload, request metadata
//               and degenerate-result payload use separate sequential blocks.
// Algorithm   : 32 radix-2 non-restoring iterations followed, when required,
//               by one final remainder-correction cycle.  Runtime arithmetic is
//               structural; counter increment is control-only arithmetic.
// ============================================================================
`include "edrv32_uop.vh"

module edrv32_div_nonrestoring (
    input  wire                         clk_i,
    input  wire                         rst_n_i,

    input  wire                         req_valid_i,
    output wire                         req_ready_o,
    input  wire [`EDRV32_MDU_OP_W-1:0] req_op_i,
    input  wire [31:0]                  req_lhs_i,
    input  wire [31:0]                  req_rhs_i,

    input  wire                         cancel_i,

    output wire                         result_valid_o,
    input  wire                         result_ready_i,
    output wire [31:0]                  result_data_o,
    output wire                         busy_o
);

    localparam [1:0] STATE_IDLE    = 2'd0;
    localparam [1:0] STATE_COMPUTE = 2'd1;
    localparam [1:0] STATE_CORRECT = 2'd2;
    localparam [1:0] STATE_DONE    = 2'd3;

    reg [1:0] state_r;
    reg [5:0] iteration_count_r;

    reg [32:0] remainder_r;
    reg [31:0] quotient_r;
    reg [31:0] divisor_r;

    reg result_is_remainder_r;
    reg quotient_negative_r;
    reg remainder_negative_r;
    reg degenerate_result_r;
    reg [31:0] degenerate_result_data_r;

    wire request_fire_w = req_valid_i && req_ready_o;
    wire result_fire_w = result_valid_o && result_ready_i;

    wire request_is_signed_w = (req_op_i == `EDRV32_MDU_DIV) ||
                               (req_op_i == `EDRV32_MDU_REM);
    wire request_is_remainder_w = (req_op_i == `EDRV32_MDU_REM) ||
                                  (req_op_i == `EDRV32_MDU_REMU);
    wire request_lhs_negative_w = request_is_signed_w && req_lhs_i[31];
    wire request_rhs_negative_w = request_is_signed_w && req_rhs_i[31];

    wire [31:0] request_lhs_negated_w;
    wire [31:0] request_rhs_negated_w;
    wire unused_lhs_negate_carry_w;
    wire unused_rhs_negate_carry_w;
    edrv32_adder32 u_request_lhs_negate (
        .lhs_i   (~req_lhs_i),
        .rhs_i   (32'd0),
        .carry_i (1'b1),
        .sum_o   (request_lhs_negated_w),
        .carry_o (unused_lhs_negate_carry_w)
    );
    edrv32_adder32 u_request_rhs_negate (
        .lhs_i   (~req_rhs_i),
        .rhs_i   (32'd0),
        .carry_i (1'b1),
        .sum_o   (request_rhs_negated_w),
        .carry_o (unused_rhs_negate_carry_w)
    );

    wire [31:0] request_lhs_magnitude_w = request_lhs_negative_w
        ? request_lhs_negated_w : req_lhs_i;
    wire [31:0] request_rhs_magnitude_w = request_rhs_negative_w
        ? request_rhs_negated_w : req_rhs_i;

    wire request_divide_by_zero_w = (req_rhs_i == 32'd0);
    wire request_zero_dividend_w = (request_lhs_magnitude_w == 32'd0);
    wire request_unit_divisor_w = !request_divide_by_zero_w &&
                                  (request_rhs_magnitude_w == 32'd1);
    wire request_signed_overflow_w = request_is_signed_w &&
                                     (req_lhs_i == 32'h8000_0000) &&
                                     (req_rhs_i == 32'hffff_ffff);
    wire request_degenerate_w = request_divide_by_zero_w ||
                                request_zero_dividend_w ||
                                request_unit_divisor_w ||
                                request_signed_overflow_w;

    reg [31:0] request_degenerate_result_w;
    always @* begin
        if (request_divide_by_zero_w)
            request_degenerate_result_w = request_is_remainder_w
                ? req_lhs_i : 32'hffff_ffff;
        else if (request_zero_dividend_w)
            request_degenerate_result_w = 32'd0;
        else if (request_signed_overflow_w)
            request_degenerate_result_w = request_is_remainder_w
                ? 32'd0 : 32'h8000_0000;
        else if (request_is_remainder_w)
            request_degenerate_result_w = 32'd0;
        else
            request_degenerate_result_w = request_rhs_negative_w
                ? request_lhs_negated_w : req_lhs_i;
    end

    // The old accumulator sign selects add versus subtract.  Unlike restoring
    // division, a negative intermediate remainder is retained and repaired by
    // adding the divisor on the next iteration.
    wire [32:0] shifted_remainder_w =
        {remainder_r[31:0], quotient_r[31]};
    wire subtract_divisor_w = ~remainder_r[32];
    wire [32:0] extended_divisor_w = {1'b0, divisor_r};
    wire [32:0] addend_w = subtract_divisor_w
        ? ~extended_divisor_w : extended_divisor_w;

    wire [31:0] iteration_sum_low_w;
    wire iteration_sum_low_carry_w;
    wire iteration_sum_high_w;
    wire unused_iteration_sum_carry_w;
    edrv32_adder32 u_iteration_add_low (
        .lhs_i   (shifted_remainder_w[31:0]),
        .rhs_i   (addend_w[31:0]),
        .carry_i (subtract_divisor_w),
        .sum_o   (iteration_sum_low_w),
        .carry_o (iteration_sum_low_carry_w)
    );
    edrv32_full_adder u_iteration_add_high (
        .a_i    (shifted_remainder_w[32]),
        .b_i    (addend_w[32]),
        .cin_i  (iteration_sum_low_carry_w),
        .sum_o  (iteration_sum_high_w),
        .cout_o (unused_iteration_sum_carry_w)
    );

    wire [32:0] iteration_remainder_w =
        {iteration_sum_high_w, iteration_sum_low_w};
    wire [31:0] iteration_quotient_w =
        {quotient_r[30:0], ~iteration_remainder_w[32]};

    // A negative final non-restoring remainder needs one correction add.
    wire [31:0] corrected_remainder_low_w;
    wire corrected_remainder_low_carry_w;
    wire corrected_remainder_high_w;
    wire unused_corrected_remainder_carry_w;
    edrv32_adder32 u_remainder_correction_low (
        .lhs_i   (remainder_r[31:0]),
        .rhs_i   (divisor_r),
        .carry_i (1'b0),
        .sum_o   (corrected_remainder_low_w),
        .carry_o (corrected_remainder_low_carry_w)
    );
    edrv32_full_adder u_remainder_correction_high (
        .a_i    (remainder_r[32]),
        .b_i    (1'b0),
        .cin_i  (corrected_remainder_low_carry_w),
        .sum_o  (corrected_remainder_high_w),
        .cout_o (unused_corrected_remainder_carry_w)
    );
    wire [32:0] corrected_remainder_w =
        {corrected_remainder_high_w, corrected_remainder_low_w};

    wire [31:0] quotient_negated_w;
    wire [31:0] remainder_negated_w;
    wire unused_quotient_negate_carry_w;
    wire unused_remainder_negate_carry_w;
    edrv32_adder32 u_quotient_result_negate (
        .lhs_i   (~quotient_r),
        .rhs_i   (32'd0),
        .carry_i (1'b1),
        .sum_o   (quotient_negated_w),
        .carry_o (unused_quotient_negate_carry_w)
    );
    edrv32_adder32 u_remainder_result_negate (
        .lhs_i   (~remainder_r[31:0]),
        .rhs_i   (32'd0),
        .carry_i (1'b1),
        .sum_o   (remainder_negated_w),
        .carry_o (unused_remainder_negate_carry_w)
    );

    wire [31:0] signed_quotient_w = quotient_negative_r
        ? quotient_negated_w : quotient_r;
    wire [31:0] signed_remainder_w = remainder_negative_r
        ? remainder_negated_w : remainder_r[31:0];
    wire [31:0] normal_result_w = result_is_remainder_r
        ? signed_remainder_w : signed_quotient_w;

    assign req_ready_o = (state_r == STATE_IDLE);
    assign result_valid_o = (state_r == STATE_DONE);
    assign result_data_o = degenerate_result_r
        ? degenerate_result_data_r : normal_result_w;
    assign busy_o = (state_r != STATE_IDLE);

    // Transaction lifecycle/FSM only.
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i)
            state_r <= STATE_IDLE;
        else if (cancel_i)
            state_r <= STATE_IDLE;
        else begin
            case (state_r)
                STATE_IDLE: begin
                    if (request_fire_w)
                        state_r <= request_degenerate_w
                            ? STATE_DONE : STATE_COMPUTE;
                end
                STATE_COMPUTE: begin
                    if (iteration_count_r == 6'd31)
                        state_r <= iteration_remainder_w[32]
                            ? STATE_CORRECT : STATE_DONE;
                end
                STATE_CORRECT:
                    state_r <= STATE_DONE;
                STATE_DONE: begin
                    if (result_fire_w)
                        state_r <= STATE_IDLE;
                end
                default:
                    state_r <= STATE_IDLE;
            endcase
        end
    end

    // Iteration-progress control only.
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i)
            iteration_count_r <= 6'd0;
        else if (cancel_i)
            iteration_count_r <= 6'd0;
        else if (request_fire_w && !request_degenerate_w)
            iteration_count_r <= 6'd0;
        else if ((state_r == STATE_COMPUTE) &&
                 (iteration_count_r != 6'd31))
            iteration_count_r <= iteration_count_r + 6'd1;
    end

    // Iterative arithmetic payload only.
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            remainder_r <= 33'd0;
            quotient_r  <= 32'd0;
            divisor_r   <= 32'd0;
        end else if (request_fire_w && !request_degenerate_w) begin
            remainder_r <= 33'd0;
            quotient_r  <= request_lhs_magnitude_w;
            divisor_r   <= request_rhs_magnitude_w;
        end else if (state_r == STATE_COMPUTE) begin
            remainder_r <= iteration_remainder_w;
            quotient_r  <= iteration_quotient_w;
        end else if (state_r == STATE_CORRECT) begin
            remainder_r <= corrected_remainder_w;
        end
    end

    // Captured result-format metadata only.
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            result_is_remainder_r <= 1'b0;
            quotient_negative_r   <= 1'b0;
            remainder_negative_r  <= 1'b0;
            degenerate_result_r   <= 1'b0;
        end else if (request_fire_w) begin
            result_is_remainder_r <= request_is_remainder_w;
            quotient_negative_r   <= request_lhs_negative_w ^
                                     request_rhs_negative_w;
            remainder_negative_r  <= request_lhs_negative_w;
            degenerate_result_r   <= request_degenerate_w;
        end
    end

    // Degenerate-result payload only; normal results stay in the datapath regs.
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i)
            degenerate_result_data_r <= 32'd0;
        else if (request_fire_w && request_degenerate_w)
            degenerate_result_data_r <= request_degenerate_result_w;
    end

endmodule
