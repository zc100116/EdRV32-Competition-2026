// File: edrv32_cpu_mul.v
// Spec: cpu-spec 2.3, 4.8
// Description: Extend RV32 operands for all four multiply forms using a signed APM core.
// Keep valid and result selection aligned with the three enabled product stages.
// Clock domain: clk_sys.
module edrv32_cpu_mul (
    // Clock and control; enable freezes both stages on backend stalls.
    input wire clk_i,
    input wire rst_n_i,
    input wire enable_i,
    input wire valid_i,
    // E-stage operands and M-extension funct3 low two bits.
    input wire [31:0] operand_a_i,
    input wire [31:0] operand_b_i,
    input wire [1:0] operation_i,
    // W2-stage result after three enabled edges.
    output wire valid_o,
    output wire [31:0] result_o
);
    wire [32:0] operand_a_w;
    wire [32:0] operand_b_w;
    wire [63:0] product_w;
    wire [1:0] unused_product_sign_w;
    reg [2:0] valid_r;
    reg [63:0] product_r;
    reg high_output_r;
    reg high_stage_r;
    reg high_r;
    assign operand_a_w = {operand_a_i[31] && operation_i != 2'b11, operand_a_i};
    assign operand_b_w = {operand_b_i[31] && operation_i == 2'b01, operand_b_i};
    edrv32_mul_s33x33 u_product (
        .clk_i(clk_i),
        .enable_i(enable_i),
        .operand_a_i(operand_a_w),
        .operand_b_i(operand_b_w),
        .product_o({unused_product_sign_w, product_w})
    );
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i)
            valid_r <= 3'b0;
        else if (enable_i)
            valid_r <= {valid_r[1:0], valid_i};
    end
    always @(posedge clk_i) begin
        if (enable_i) begin
            high_stage_r <= operation_i != 0;
            high_r <= high_stage_r;
            high_output_r <= high_r;
            product_r <= product_w;
        end
    end
    assign valid_o = valid_r[2];
    assign result_o = high_output_r ? product_r[63:32] : product_r[31:0];
endmodule
