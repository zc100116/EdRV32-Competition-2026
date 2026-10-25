// edrv32_cpu_mul.v
// cpu-spec 2, 4: mul datapath.
// Clock domain: clk_sys (combinational where no clock port).
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
    // W-stage result after two enabled edges.
    output wire valid_o,
    output wire [31:0] result_o
);
    wire [32:0] operand_a_w;
    wire [32:0] operand_b_w;
    wire [65:0] unused_product_w;
    reg [1:0] valid_r;
    reg high_stage_r;
    reg high_r;
    assign operand_a_w = {operand_a_i[31] && operation_i != 2'b11, operand_a_i};
    assign operand_b_w = {operand_b_i[31] && operation_i == 2'b01, operand_b_i};
    edrv32_mul_s33x33 u_product (
        .clk_i(clk_i),
        .enable_i(enable_i),
        .operand_a_i(operand_a_w),
        .operand_b_i(operand_b_w),
        .product_o(unused_product_w)
    );
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i)
            valid_r <= 2'b0;
        else if (enable_i)
            valid_r <= {valid_r[0], valid_i};
    end
    always @(posedge clk_i) begin
        if (enable_i) begin
            high_stage_r <= operation_i != 0;
            high_r <= high_stage_r;
        end
    end
    assign valid_o = valid_r[1];
    assign result_o = high_r ? unused_product_w[63:32] : unused_product_w[31:0];
endmodule
