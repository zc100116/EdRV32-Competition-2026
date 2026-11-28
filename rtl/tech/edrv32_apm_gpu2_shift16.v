// File: edrv32_apm_gpu2_shift16.v
// Spec: gpu-v2-spec 2.4; fpga/ip/apm_gpu_cascade.md.
// Description: Signed 25x18 multiply with a registered 48-bit cascade sum (three clocks).
// Clock domain: clk_gpu.
`include "edrv32_build_mode.vh"
module edrv32_apm_gpu2_shift16 (
    // Clock and stall enable; all three internal boundaries advance together.
    input wire clk_i,
    input wire enable_i,

    // Signed native operands and dedicated cascade connection.
    input wire [24:0] x_i,
    input wire [17:0] y_i,
    input wire [47:0] cpi_i,
    output wire [47:0] cpo_o,
    output wire [47:0] p_o
);
`ifdef EDRV32_FPGA_MEMORY_MODE
    GTP_APM_E2 #(
        .GRS_EN("FALSE"),
        .USE_POSTADD(1'b1),
        .USE_PREADD(1'b0),
        .X_REG(1),
        .Y_REG(1),
        .MULT_REG(1),
        .P_REG(1),
        .CPO_REG(1),
        .USE_SIMD(0),
        .ASYNC_RST(0)
    ) u_apm (
        .P(p_o),
        .CPO(cpo_o),
        .COUT(),
        .CXO(),
        .CXBO(),
        .X({5'b0, x_i}),
        .CXI(30'b0),
        .CXBI(25'b0),
        .XB(25'b0),
        .Y(y_i),
        .Z(48'b0),
        .CPI(cpi_i),
        .CIN(1'b0),
        .MODEY(3'b001),
        .MODEZ(4'd6),
        .MODEIN(5'b00010),
        .CLK(clk_i),
        .CEX1(enable_i),
        .CEX2(enable_i),
        .CEX3(enable_i),
        .CEXB(enable_i),
        .CEY1(enable_i),
        .CEY2(enable_i),
        .CEZ(enable_i),
        .CEPRE(enable_i),
        .CEM(enable_i),
        .CEP(enable_i),
        .CEMODEY(enable_i),
        .CEMODEZ(enable_i),
        .CEMODEIN(enable_i),
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
    wire [47:0] cascade_w;
    reg signed [24:0] x_r;
    reg signed [17:0] y_r;
    reg signed [42:0] product_r;
    reg [47:0] sum_r;
    assign cascade_w = $signed(cpi_i) >>> 16;
    always @(posedge clk_i) begin
        if (enable_i) begin
            x_r <= x_i;
            y_r <= y_i;
            product_r <= x_r * y_r;
            sum_r <= {{5{product_r[42]}}, product_r} + cascade_w;
        end
    end
    assign cpo_o = sum_r;
    assign p_o = sum_r;
`endif
endmodule
