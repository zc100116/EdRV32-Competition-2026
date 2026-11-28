// File: edrv32_apm_cpu2_u24xu24.v
// Spec: fpu-spec 5.2.
// Description: Full unsigned 24x24 product, two APMs and four sampling edges.
// Clock domain: clk_sys.
module edrv32_apm_cpu2_u24xu24 (
    // Clock; the FMA advances on every clock.
    input wire clk_i,

    // Normalized significands; X/Y registers are the first pipeline boundary.
    input wire [23:0] a_i,
    input wire [23:0] b_i,
    output wire [47:0] product_o
);
    wire [47:0] head_cpo_w;
    wire [47:0] unused_head_p_w;
    wire [47:0] unused_tail_cpo_w;
    wire [47:0] unused_tail_p_w;
    reg [23:0] tail_a_r;
    reg [7:0] tail_b_r;
    reg [15:0] residue_r;

    edrv32_apm_cpu2_head u_head (
        .clk_i(clk_i),
        .enable_i(1'b1),
        .x_i({1'b0, a_i}),
        .y_i({2'b0, b_i[15:0]}),
        .unused_cpi_i(48'b0),
        .cpo_o(head_cpo_w),
        .p_o(unused_head_p_w)
    );
    edrv32_apm_cpu2_shift16 u_tail (
        .clk_i(clk_i),
        .enable_i(1'b1),
        .x_i({1'b0, tail_a_r}),
        .y_i({10'b0, tail_b_r}),
        .cpi_i(head_cpo_w),
        .cpo_o(unused_tail_cpo_w),
        .p_o(unused_tail_p_w)
    );
    always @(posedge clk_i) begin
        tail_a_r <= a_i;
        tail_b_r <= b_i[23:16];
        residue_r <= unused_head_p_w[15:0];
    end
    assign product_o = {unused_tail_p_w[31:0], residue_r};
endmodule
