// File: edrv32_mac_npu_int8_chain.v
// Spec: npu-spec 5.4 C1-C8; design/2026-10-30-npu-apm-cascade 3-6; CLAUDE.md 8.
// Description: Fixed SIMD INT8 multiply and two independent 24-bit cascade additions.
// X/Y, MULT and P register boundaries always advance; CPI is sampled at the P edge.
// Clock: clk_npu.
`include "edrv32_build_mode.vh"
module edrv32_mac_npu_int8_chain (
    // Clock; the pipeline always advances.
    input wire clk_i,

    // Signed operand pairs.
    input wire [7:0] a0_i,
    input wire [7:0] b0_i,
    input wire [7:0] a1_i,
    input wire [7:0] b1_i,

    // SIMD cascade: low/high 24-bit lanes wrap independently.
    input wire [47:0] cpi_i,
    output wire [47:0] cpo_o
);
`ifdef EDRV32_FPGA_MEMORY_MODE
    // SIMD lanes: 12-bit X and 9-bit Y sub-words, each sign-extended from INT8.
    wire [29:0] packed_a_w;
    wire [17:0] packed_b_w;
    assign packed_a_w = {6'b0, {4{a1_i[7]}}, a1_i, {4{a0_i[7]}}, a0_i};
    assign packed_b_w = {b1_i[7], b1_i, b0_i[7], b0_i};
    GTP_APM_E2 #(
        .GRS_EN("FALSE"),
        .USE_POSTADD(1'b1),
        .USE_PREADD(1'b0),
        .X_REG(1),
        .Y_REG(1),
        .MULT_REG(1),
        .P_REG(1),
        .CPO_REG(1),
        .USE_SIMD(1),
        .ASYNC_RST(0)
    ) u_apm (
        .P(),
        .CPO(cpo_o),
        .COUT(),
        .CXO(),
        .CXBO(),
        .X(packed_a_w),
        .CXI(30'b0),
        .CXBI(25'b0),
        .XB(25'b0),
        .Y(packed_b_w),
        .Z(48'b0),
        .CPI(cpi_i),
        .CIN(1'b0),
        .MODEY(3'b001),
        .MODEZ(4'b0011),
        .MODEIN(5'b00010),
        .CLK(clk_i),
        .CEX1(1'b1),
        .CEX2(1'b1),
        .CEX3(1'b1),
        .CEXB(1'b1),
        .CEY1(1'b1),
        .CEY2(1'b1),
        .CEZ(1'b1),
        .CEPRE(1'b1),
        .CEM(1'b1),
        .CEP(1'b1),
        .CEMODEY(1'b1),
        .CEMODEZ(1'b1),
        .CEMODEIN(1'b1),
        // Data registers are not reset (CLAUDE.md 5.2).
        .RSTX(1'b0),
        .RSTXB(1'b0),
        .RSTY(1'b0),
        .RSTZ(1'b0),
        .RSTPRE(1'b0),
        .RSTM(1'b0),
        .RSTP(1'b0),
        .RSTMODEY(1'b0),
        .RSTMODEZ(1'b0),
        .RSTMODEIN(1'b0)
    );
`else
    reg signed [15:0] product0_stage_r;
    reg signed [15:0] product1_stage_r;
    reg signed [15:0] product0_r;
    reg signed [15:0] product1_r;
    reg [23:0] sum0_r;
    reg [23:0] sum1_r;
    always @(posedge clk_i) begin
        product0_stage_r <= $signed(a0_i) * $signed(b0_i);
        product1_stage_r <= $signed(a1_i) * $signed(b1_i);
        product0_r <= product0_stage_r;
        product1_r <= product1_stage_r;
        sum0_r <= {{8{product0_r[15]}}, product0_r} + cpi_i[23:0];
        sum1_r <= {{8{product1_r[15]}}, product1_r} + cpi_i[47:24];
    end
    assign cpo_o = {sum1_r, sum0_r};
`endif
endmodule
