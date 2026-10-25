// ============================================================================
// File        : edrv32_yolo_apm_mul2.v
// Description : Two signed INT8 products in one Logos2 APM SIMD primitive.
// Notes       : Two clock edges from accepted operands to products. The
//               behavioral branch has the same latency for portable tests.
// ============================================================================

module edrv32_yolo_apm_mul2 (
    input  wire              clk_i,
    input  wire              rst_n_i,
    input  wire              ce_i,
    input  wire signed [7:0] a0_i,
    input  wire signed [7:0] b0_i,
    input  wire signed [7:0] a1_i,
    input  wire signed [7:0] b1_i,
    output wire signed [15:0] p0_o,
    output wire signed [15:0] p1_o
);

`ifdef FPGA_MODE
    wire [47:0] product_w;
    wire [29:0] packed_a_w = {6'b0, {4{a1_i[7]}}, a1_i,
                              {4{a0_i[7]}}, a0_i};
    wire [17:0] packed_b_w = {{1{b1_i[7]}}, b1_i,
                              {1{b0_i[7]}}, b0_i};

    GTP_APM_E2 #(
        .GRS_EN      ("FALSE"),
        .USE_POSTADD (1'b0),
        .USE_PREADD  (1'b0),
        .X_REG       (1),
        .Y_REG       (1),
        .MULT_REG    (1),
        .P_REG       (0),
        .USE_SIMD    (1),
        .ASYNC_RST   (0)
    ) u_apm (
        .P          (product_w),
        .CPO        (), .COUT (), .CXO (), .CXBO (),
        .X          (packed_a_w),
        .CXI        (30'b0), .CXBI (25'b0), .XB (25'b0),
        .Y          (packed_b_w),
        .Z          (48'b0), .CPI (48'b0), .CIN (1'b0),
        .MODEY      (3'b001), .MODEZ (4'b0000), .MODEIN (5'b00010),
        .CLK        (clk_i),
        .CEX1       (ce_i), .CEX2 (ce_i), .CEX3 (ce_i), .CEXB (ce_i),
        .CEY1       (ce_i), .CEY2 (ce_i), .CEZ (ce_i),
        .CEPRE      (ce_i), .CEM (ce_i), .CEP (ce_i),
        .CEMODEY    (ce_i), .CEMODEZ (ce_i), .CEMODEIN (ce_i),
        .RSTX       (~rst_n_i), .RSTXB (~rst_n_i),
        .RSTY       (~rst_n_i), .RSTZ (~rst_n_i),
        .RSTPRE     (~rst_n_i), .RSTM (~rst_n_i), .RSTP (~rst_n_i),
        .RSTMODEY   (~rst_n_i), .RSTMODEZ (~rst_n_i),
        .RSTMODEIN  (~rst_n_i)
    );

    assign p0_o = product_w[15:0];
    assign p1_o = product_w[39:24];
`else
    reg signed [15:0] product0_r;
    reg signed [15:0] product1_r;
    reg signed [15:0] result0_r;
    reg signed [15:0] result1_r;

    always @(posedge clk_i) begin
        if (ce_i) begin
            product0_r <= a0_i * b0_i;
            product1_r <= a1_i * b1_i;
            result0_r  <= product0_r;
            result1_r  <= product1_r;
        end
    end

    assign p0_o = result0_r;
    assign p1_o = result1_r;
`endif

endmodule
