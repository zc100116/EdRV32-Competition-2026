// ============================================================================
// File        : edrv32_mul_pango_apm.v
// Description : Three-stage Pango APM backend for the current scalar MDU.
// Reuse       : Direct adaptation of the validated pre-rewrite mul_pango_apm.v.
// Notes       : One statically signed 33x33 IP implements all four RV32M
//               multiply forms through explicit operand sign/zero extension.
// ============================================================================
`include "edrv32_uop.vh"

module edrv32_mul_pango_apm (
    input  wire                         clk_i,
    input  wire                         rst_n_i,
    input  wire                         flush_i,
    input  wire                         start_i,
    input  wire [`EDRV32_MDU_OP_W-1:0] operation_i,
    input  wire [31:0]                  lhs_i,
    input  wire [31:0]                  rhs_i,
    output wire                         result_valid_o,
    output wire [31:0]                  result_o
);

    localparam integer APM_PIPE_STAGES = 3;

    wire lhs_signed_w = (operation_i == `EDRV32_MDU_MULH) ||
                        (operation_i == `EDRV32_MDU_MULHSU);
    wire rhs_signed_w = (operation_i == `EDRV32_MDU_MULH);
    wire [32:0] apm_lhs_w = {lhs_signed_w && lhs_i[31], lhs_i};
    wire [32:0] apm_rhs_w = {rhs_signed_w && rhs_i[31], rhs_i};
    wire [65:0] apm_product_w;

    reg [APM_PIPE_STAGES-1:0] valid_pipe_r;
    reg [`EDRV32_MDU_OP_W-1:0] operation_r;

    wire pipeline_enable_w = start_i || (|valid_pipe_r);

    // Pipeline occupancy is independent from arithmetic payload and operation.
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i)
            valid_pipe_r <= {APM_PIPE_STAGES{1'b0}};
        else if (flush_i)
            valid_pipe_r <= {APM_PIPE_STAGES{1'b0}};
        else if (pipeline_enable_w)
            valid_pipe_r <= {valid_pipe_r[APM_PIPE_STAGES-2:0], start_i};
    end

    // Operation metadata belongs to the sole accepted multiply request.
    always @(posedge clk_i) begin
        if (start_i)
            operation_r <= operation_i;
    end

    mul u_mul (
        .ce  (pipeline_enable_w),
        .rst (~rst_n_i || flush_i),
        .clk (clk_i),
        .a   (apm_lhs_w),
        .b   (apm_rhs_w),
        .p   (apm_product_w)
    );

    assign result_valid_o = valid_pipe_r[APM_PIPE_STAGES-1];
    assign result_o = (operation_r == `EDRV32_MDU_MUL)
        ? apm_product_w[31:0] : apm_product_w[63:32];

endmodule
