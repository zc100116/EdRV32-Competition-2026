// File: edrv32_apm_gpu_s32xs16.v
// Spec: gpu-spec 2.4, 2.12, 2.13.1-6; design/2026-11-27-gpu-apm-cascade.
// Description: Exact fixed-width multiply; 2 APMs, 4 enabled clocks.
// Clock domain: clk_gpu.
module edrv32_apm_gpu_s32xs16 (
    // Clock and stall enable.
    input wire clk_i,
    input wire enable_i,

    // Full operands; signedness is fixed by this wrapper configuration.
    input wire [31:0] a_i,
    input wire [15:0] b_i,
    output wire [47:0] p_o
);
    wire [24:0] x0_w;
    assign x0_w = {{1{1'b0}}, a_i[0 +: 24]};
    wire [17:0] y0_w;
    assign y0_w = {{2{b_i[15]}}, b_i[0 +: 16]};
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
    reg [7:0] x1_d0_r;
    wire [24:0] x1_w;
    assign x1_w = {{17{x1_d0_r[7]}}, x1_d0_r};
    reg [15:0] y1_d0_r;
    wire [17:0] y1_w;
    assign y1_w = {{2{y1_d0_r[15]}}, y1_d0_r};
    wire [47:0] unused_c1_w;
    wire [47:0] unused_p1_w;
    // Term at bit 24; lower bits leave the sum through the residue delay below.
    edrv32_apm_gpu_shift24 u_cell1 (
        .clk_i(clk_i),
        .enable_i(enable_i),
        .x_i(x1_w),
        .y_i(y1_w),
        .cpi_i(unused_c0_w),
        .cpo_o(unused_c1_w),
        .p_o(unused_p1_w)
    );
    reg [23:0] low0_d0_r;
    assign p_o = {
        unused_p1_w[23:0],
        low0_d0_r
    };
    always @(posedge clk_i) begin
        if (enable_i) begin
            x1_d0_r <= a_i[24 +: 8];
            y1_d0_r <= b_i[0 +: 16];
            low0_d0_r <= unused_p0_w[23:0];
        end
    end
endmodule
