// File: edrv32_apm_gpu_u24xu8.v
// Spec: gpu-spec 2.4, 2.12, 2.13.1-6; design/2026-11-27-gpu-apm-cascade.
// Description: Exact fixed-width multiply; 1 APMs, 3 enabled clocks.
// Clock domain: clk_gpu.
module edrv32_apm_gpu_u24xu8 (
    // Clock and stall enable.
    input wire clk_i,
    input wire enable_i,

    // Full operands; signedness is fixed by this wrapper configuration.
    input wire [23:0] a_i,
    input wire [7:0] b_i,
    output wire [31:0] p_o
);
    wire [24:0] x0_w;
    assign x0_w = {{1{1'b0}}, a_i[0 +: 24]};
    wire [17:0] y0_w;
    assign y0_w = {{10{1'b0}}, b_i[0 +: 8]};
    wire [47:0] unused_c0_w;
    wire [47:0] unused_p0_w;
    // Term at bit 0; lower bits leave the sum through the residue delay below.
    edrv32_apm_gpu_head u_cell0 (
        .clk_i(clk_i),
        .enable_i(enable_i),
        .x_i(x0_w),
        .y_i(y0_w),
        .unused_cpi_i(48'b0),
        .cpo_o(unused_c0_w),
        .p_o(unused_p0_w)
    );
    assign p_o = {
        unused_p0_w[31:0]
    };
endmodule
