// File: edrv32_gpu2_sfu_arithmetic.v
// Spec: gpu-v2-spec 2.4; architecture M-6 independent ten-edge scalar cores.
// Description: II1 scalar MUL/FMA arithmetic for the SFU modulo reservation engines.
// Clock domain: clk_gpu. Scheduler owns validity; no data reset or unused product tap.
module edrv32_gpu2_sfu_arithmetic (
    input wire clk_i,
    input wire mul_i,
    input wire [31:0] a_i,
    input wire [31:0] b_i,
    input wire [31:0] c_i,
    output wire [31:0] result_o
);
    wire [31:0] unused_product_w;
    edrv32_gpu2_fp32_scalar u_arithmetic (
        .clk_i(clk_i),
        .mul_i(mul_i),
        .a_i(a_i),
        .b_i(b_i),
        .c_i(c_i),
        .product_o(unused_product_w),
        .result_o(result_o)
    );
endmodule
