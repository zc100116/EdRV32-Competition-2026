// File: edrv32_apm_gpu2_setup_s49xs33.v
// Spec: gpu-v2-spec 2.6; M-8 10.4.
// Description: Six APMs in three short cascades, full signed82 product in six clocks.
//              Each cascade retains its low16 residue before the two-stage sum tree.
// Clock domain: clk_gpu.
module edrv32_apm_gpu2_setup_s49xs33 (
    // Clock; free-running II1 datapath, no high-fanout stall enable.
    input wire clk_i,

    // Signed full operands and full product.
    input wire [48:0] a_i,
    input wire [32:0] b_i,
    output wire [81:0] product_o
);
    wire [191:0] chain_w;
    reg [24:0] x0_r;
    reg [16:0] high0_r;
    wire [47:0] low0_w;
    wire [47:0] cascade0_w;
    wire [47:0] high0_w;
    wire [47:0] unused_cascade0_w;
    reg [15:0] residue0_r;
    always @(posedge clk_i) begin
        x0_r <= {1'b0, a_i[23:0]};
        high0_r <= b_i[32:16];
        residue0_r <= low0_w[15:0];
    end
    edrv32_apm_gpu2_setup_head u_low0 (
        .clk_i(clk_i),
        .enable_i(1'b1),
        .x_i({1'b0, a_i[23:0]}),
        .y_i({2'b0, b_i[15:0]}),
        .unused_cpi_i(48'b0),
        .cpo_o(cascade0_w),
        .p_o(low0_w)
    );
    edrv32_apm_gpu2_setup_shift16 u_high0 (
        .clk_i(clk_i),
        .enable_i(1'b1),
        .x_i(x0_r),
        .y_i({high0_r[16], high0_r}),
        .cpi_i(cascade0_w),
        .cpo_o(unused_cascade0_w),
        .p_o(high0_w)
    );
    assign chain_w[0 +: 64] = {high0_w, residue0_r};
    reg [24:0] x1_r;
    reg [16:0] high1_r;
    wire [47:0] low1_w;
    wire [47:0] cascade1_w;
    wire [47:0] high1_w;
    wire [47:0] unused_cascade1_w;
    reg [15:0] residue1_r;
    always @(posedge clk_i) begin
        x1_r <= {1'b0, a_i[47:24]};
        high1_r <= b_i[32:16];
        residue1_r <= low1_w[15:0];
    end
    edrv32_apm_gpu2_setup_head u_low1 (
        .clk_i(clk_i),
        .enable_i(1'b1),
        .x_i({1'b0, a_i[47:24]}),
        .y_i({2'b0, b_i[15:0]}),
        .unused_cpi_i(48'b0),
        .cpo_o(cascade1_w),
        .p_o(low1_w)
    );
    edrv32_apm_gpu2_setup_shift16 u_high1 (
        .clk_i(clk_i),
        .enable_i(1'b1),
        .x_i(x1_r),
        .y_i({high1_r[16], high1_r}),
        .cpi_i(cascade1_w),
        .cpo_o(unused_cascade1_w),
        .p_o(high1_w)
    );
    assign chain_w[64 +: 64] = {high1_w, residue1_r};
    reg [24:0] x2_r;
    reg [16:0] high2_r;
    wire [47:0] low2_w;
    wire [47:0] cascade2_w;
    wire [47:0] high2_w;
    wire [47:0] unused_cascade2_w;
    reg [15:0] residue2_r;
    always @(posedge clk_i) begin
        x2_r <= {25{a_i[48]}};
        high2_r <= b_i[32:16];
        residue2_r <= low2_w[15:0];
    end
    edrv32_apm_gpu2_setup_head u_low2 (
        .clk_i(clk_i),
        .enable_i(1'b1),
        .x_i({25{a_i[48]}}),
        .y_i({2'b0, b_i[15:0]}),
        .unused_cpi_i(48'b0),
        .cpo_o(cascade2_w),
        .p_o(low2_w)
    );
    edrv32_apm_gpu2_setup_shift16 u_high2 (
        .clk_i(clk_i),
        .enable_i(1'b1),
        .x_i(x2_r),
        .y_i({high2_r[16], high2_r}),
        .cpi_i(cascade2_w),
        .cpo_o(unused_cascade2_w),
        .p_o(high2_w)
    );
    assign chain_w[128 +: 64] = {high2_w, residue2_r};
    wire [81:0] term0_w;
    wire [81:0] term1_w;
    wire [81:0] term2_w;
    reg [81:0] sum01_r;
    reg [81:0] term2_r;
    reg [81:0] product_r;
    assign term0_w = {{18{chain_w[63]}}, chain_w[63:0]};
    assign term1_w = {chain_w[121:64], 24'b0};
    assign term2_w = {chain_w[161:128], 48'b0};
    always @(posedge clk_i) begin
        sum01_r <= term0_w + term1_w;
        term2_r <= term2_w;
        product_r <= sum01_r + term2_r;
    end
    assign product_o = product_r;
    wire unused_w;
    assign unused_w = ^{low0_w[47:16], low1_w[47:16], low2_w[47:16],
        unused_cascade0_w, unused_cascade1_w, unused_cascade2_w,
        chain_w[127:122], chain_w[191:162]};
endmodule
