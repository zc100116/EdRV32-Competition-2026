// File: edrv32_mul_npu_quant_high.v
// Spec: npu-spec 2.3, 5.4; docs/design/2026-10-27-npu-datapath.md 4.6.2, 4.9; CLAUDE.md 8.
// Description: Fixed signed 16x16 APM multiplier for the signed high 16 bits of acc+bias times mult.
// Product appears two edges after the operands; no enable or data reset.
// Clock: clk_npu.
`include "edrv32_build_mode.vh"
module edrv32_mul_npu_quant_high (
    // Clock; the pipeline always advances.
    input wire clk_i,

    // Signed operands.
    input wire [15:0] operand_a_i,
    input wire [15:0] operand_b_i,

    // Signed product after two rising edges.
    output wire [31:0] product_o
);
`ifdef EDRV32_FPGA_MEMORY_MODE
    ip_mul_npu_quant_high u_ip (
        .clk(clk_i),
        .ce(1'b1),
        // The generated pipeline reset is active-high; data stays unreset.
        .rst(1'b0),
        .a(operand_a_i),
        .b(operand_b_i),
        .p(product_o)
    );
`else
    reg signed [31:0] product_stage_r;
    reg signed [31:0] product_r;
    always @(posedge clk_i) begin
        product_stage_r <= $signed(operand_a_i) * $signed(operand_b_i);
        product_r <= product_stage_r;
    end
    assign product_o = product_r;
`endif
endmodule
