// File: edrv32_apm_gpu_s94xu16.v
// Spec: gpu-spec 2.4, 2.12, 2.13.1-6; design/2026-11-27-gpu-apm-cascade.
// Description: Exact fixed-width multiply; 4 APMs, 6 enabled clocks.
// Clock domain: clk_gpu.
module edrv32_apm_gpu_s94xu16 (
    // Clock and stall enable.
    input wire clk_i,
    input wire enable_i,

    // Full operands; signedness is fixed by this wrapper configuration.
    input wire [93:0] a_i,
    input wire [15:0] b_i,
    output wire [93:0] p_o
);
    wire [24:0] x0_w;
    assign x0_w = {{1{1'b0}}, a_i[0 +: 24]};
    wire [17:0] y0_w;
    assign y0_w = {{2{1'b0}}, b_i[0 +: 16]};
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
    reg [23:0] x1_d0_r;
    wire [24:0] x1_w;
    assign x1_w = {{1{1'b0}}, x1_d0_r};
    reg [15:0] y1_d0_r;
    wire [17:0] y1_w;
    assign y1_w = {{2{1'b0}}, y1_d0_r};
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
    reg [23:0] x2_d0_r;
    reg [23:0] x2_d1_r;
    wire [24:0] x2_w;
    assign x2_w = {{1{1'b0}}, x2_d1_r};
    reg [15:0] y2_d0_r;
    reg [15:0] y2_d1_r;
    wire [17:0] y2_w;
    assign y2_w = {{2{1'b0}}, y2_d1_r};
    wire [47:0] unused_c2_w;
    wire [47:0] unused_p2_w;
    // Term at bit 48; lower bits leave the sum through the residue delay below.
    edrv32_apm_gpu_shift24 u_cell2 (
        .clk_i(clk_i),
        .enable_i(enable_i),
        .x_i(x2_w),
        .y_i(y2_w),
        .cpi_i(unused_c1_w),
        .cpo_o(unused_c2_w),
        .p_o(unused_p2_w)
    );
    reg [21:0] x3_d0_r;
    reg [21:0] x3_d1_r;
    reg [21:0] x3_d2_r;
    wire [24:0] x3_w;
    assign x3_w = {{3{x3_d2_r[21]}}, x3_d2_r};
    reg [15:0] y3_d0_r;
    reg [15:0] y3_d1_r;
    reg [15:0] y3_d2_r;
    wire [17:0] y3_w;
    assign y3_w = {{2{1'b0}}, y3_d2_r};
    wire [47:0] unused_c3_w;
    wire [47:0] unused_p3_w;
    // Term at bit 72; lower bits leave the sum through the residue delay below.
    edrv32_apm_gpu_shift24 u_cell3 (
        .clk_i(clk_i),
        .enable_i(enable_i),
        .x_i(x3_w),
        .y_i(y3_w),
        .cpi_i(unused_c2_w),
        .cpo_o(unused_c3_w),
        .p_o(unused_p3_w)
    );
    reg [23:0] low0_d0_r;
    reg [23:0] low0_d1_r;
    reg [23:0] low0_d2_r;
    reg [23:0] low1_d0_r;
    reg [23:0] low1_d1_r;
    reg [23:0] low2_d0_r;
    assign p_o = {
        unused_p3_w[21:0],
        low2_d0_r,
        low1_d1_r,
        low0_d2_r
    };
    always @(posedge clk_i) begin
        if (enable_i) begin
            x1_d0_r <= a_i[24 +: 24];
            y1_d0_r <= b_i[0 +: 16];
            x2_d0_r <= a_i[48 +: 24];
            x2_d1_r <= x2_d0_r;
            y2_d0_r <= b_i[0 +: 16];
            y2_d1_r <= y2_d0_r;
            x3_d0_r <= a_i[72 +: 22];
            x3_d1_r <= x3_d0_r;
            x3_d2_r <= x3_d1_r;
            y3_d0_r <= b_i[0 +: 16];
            y3_d1_r <= y3_d0_r;
            y3_d2_r <= y3_d1_r;
            low0_d0_r <= unused_p0_w[23:0];
            low0_d1_r <= low0_d0_r;
            low0_d2_r <= low0_d1_r;
            low1_d0_r <= unused_p1_w[23:0];
            low1_d1_r <= low1_d0_r;
            low2_d0_r <= unused_p2_w[23:0];
        end
    end
endmodule
