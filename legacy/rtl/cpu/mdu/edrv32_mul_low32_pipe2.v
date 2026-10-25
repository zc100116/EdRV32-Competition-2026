// ============================================================================
// File        : edrv32_mul_low32_pipe2.v
// Description : Two-stage low-32-bit integer multiply using three 16x16 products.
// Notes       : Low multiplication is identical for signed and unsigned operands.
//               The high-high product contributes only above bit 31 and is omitted.
// ============================================================================
module edrv32_mul_low32_pipe2 (
    input  wire        clk_i,
    input  wire        rst_n_i,
    input  wire        flush_i,
    input  wire        start_i,
    input  wire [31:0] lhs_i,
    input  wire [31:0] rhs_i,
    output wire        result_valid_o,
    output wire [31:0] result_o
);
    reg [1:0]  valid_pipe_r;
    reg [31:0] lhs_r;
    reg [31:0] rhs_r;
    reg [31:0] result_r;

    // Capture operands before multiplication so a live Load bypass ends at
    // these registers rather than traversing the multiplier and output adder.
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i)
            valid_pipe_r <= 2'b00;
        else if (flush_i)
            valid_pipe_r <= 2'b00;
        else
            valid_pipe_r <= {valid_pipe_r[0], start_i};
    end

    always @(posedge clk_i) begin
        if (start_i) begin
            lhs_r <= lhs_i;
            rhs_r <= rhs_i;
        end
    end

    wire [31:0] low_product_w = lhs_r[15:0] * rhs_r[15:0];
    wire [31:0] cross_lhs_product_w = lhs_r[31:16] * rhs_r[15:0];
    wire [31:0] cross_rhs_product_w = lhs_r[15:0] * rhs_r[31:16];
    wire [15:0] high_a_w = low_product_w[31:16];
    wire [15:0] high_b_w = cross_lhs_product_w[15:0];
    wire [15:0] high_c_w = cross_rhs_product_w[15:0];

    // Reduce the three high-half addends before one carry-propagating add.
    // Discard the high carry explicitly: the instruction returns modulo 2^32.
    wire [15:0] high_sum_bits_w = high_a_w ^ high_b_w ^ high_c_w;
    wire [15:0] high_carry_bits_w = (high_a_w & high_b_w) |
        (high_a_w & high_c_w) | (high_b_w & high_c_w);
    wire [16:0] high_sum_w = {1'b0, high_sum_bits_w} + {high_carry_bits_w, 1'b0};

    always @(posedge clk_i) begin
        if (valid_pipe_r[0])
            result_r <= {high_sum_w[15:0], low_product_w[15:0]};
    end

    assign result_valid_o = valid_pipe_r[1];
    assign result_o       = result_r;
endmodule
