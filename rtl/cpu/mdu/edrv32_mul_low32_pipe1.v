// ============================================================================
// File        : edrv32_mul_low32_pipe1.v
// Description : One-stage low-32-bit multiplication of registered operands.
// Notes       : The caller supplies an EX-stored operand view. Live Cache
//               responses must be captured before reaching these inputs.
// ============================================================================
module edrv32_mul_low32_pipe1 (
    input  wire        clk_i,
    input  wire        rst_n_i,
    input  wire        flush_i,
    input  wire        start_i,
    input  wire [31:0] lhs_i,
    input  wire [31:0] rhs_i,
    output wire        result_valid_o,
    output wire [31:0] result_o
);
    reg        valid_r;
    reg [31:0] result_r;

    wire [31:0] low_product_w = lhs_i[15:0] * rhs_i[15:0];
    wire [31:0] cross_lhs_product_w = lhs_i[31:16] * rhs_i[15:0];
    wire [31:0] cross_rhs_product_w = lhs_i[15:0] * rhs_i[31:16];
    wire [15:0] high_a_w = low_product_w[31:16];
    wire [15:0] high_b_w = cross_lhs_product_w[15:0];
    wire [15:0] high_c_w = cross_rhs_product_w[15:0];
    wire [15:0] high_sum_bits_w = high_a_w ^ high_b_w ^ high_c_w;
    wire [15:0] high_carry_bits_w = (high_a_w & high_b_w) |
        (high_a_w & high_c_w) | (high_b_w & high_c_w);
    wire [16:0] high_sum_w = {1'b0, high_sum_bits_w} + {high_carry_bits_w, 1'b0};

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i)
            valid_r <= 1'b0;
        else if (flush_i)
            valid_r <= 1'b0;
        else
            valid_r <= start_i;
    end

    always @(posedge clk_i) begin
        if (start_i)
            result_r <= {high_sum_w[15:0], low_product_w[15:0]};
    end

    assign result_valid_o = valid_r;
    assign result_o       = result_r;
endmodule
