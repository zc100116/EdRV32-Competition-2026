// File: edrv32_mul_s33x33.v
// Spec: cpu-spec 4.8
// Description: Wrap the fixed signed 33-by-33 APM multiplier with two enabled stages.
// Match the behavioral product latency to the FPGA IP without data reset.
// Clock domain: clk_sys.
`include "edrv32_build_mode.vh"
module edrv32_mul_s33x33 (
    // Clock and pipeline enable.
    input wire clk_i,
    input wire enable_i,
    // Signed operands.
    input wire [32:0] operand_a_i,
    input wire [32:0] operand_b_i,
    // Product after two enabled rising edges.
    output wire [65:0] product_o
);
`ifdef EDRV32_FPGA_MEMORY_MODE
    ip_mul_s33x33 u_ip (
        .clk(clk_i),
        .ce(enable_i),
        .a(operand_a_i),
        .b(operand_b_i),
        .p(product_o)
    );
`else
    reg signed [65:0] product_stage_r;
    reg signed [65:0] product_r;
    always @(posedge clk_i) begin
        if (enable_i) begin
            product_stage_r <= $signed(operand_a_i) * $signed(operand_b_i);
            product_r <= product_stage_r;
        end
    end
    assign product_o = product_r;
`endif
endmodule
