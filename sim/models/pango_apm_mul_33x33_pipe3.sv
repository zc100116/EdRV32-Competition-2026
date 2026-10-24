`timescale 1ns/1ps

// Latency-accurate functional model for the generated Pango 33x33 signed
// multiplier. Synthesis filelists use the vendor-generated wrapper/IPML RTL.
module pango_apm_mul_33x33_pipe3 (
    input  wire               ce,
    input  wire               rst,
    input  wire               clk,
    input  wire signed [32:0] a,
    input  wire signed [32:0] b,
    output wire signed [65:0] p
);
    reg signed [65:0] product_stage1_r;
    reg signed [65:0] product_stage2_r;
    reg signed [65:0] product_stage3_r;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            product_stage1_r <= 66'sd0;
            product_stage2_r <= 66'sd0;
            product_stage3_r <= 66'sd0;
        end else if (ce) begin
            product_stage1_r <= a * b;
            product_stage2_r <= product_stage1_r;
            product_stage3_r <= product_stage2_r;
        end
    end

    assign p = product_stage3_r;
endmodule

// Match the current generated IP wrapper name while retaining the standalone
// arithmetic model used by the multiplier equivalence tests.
module mul (
    input  wire               ce,
    input  wire               rst,
    input  wire               clk,
    input  wire signed [32:0] a,
    input  wire signed [32:0] b,
    output wire signed [65:0] p
);
    pango_apm_mul_33x33_pipe3 u_model (
        .ce(ce), .rst(rst), .clk(clk), .a(a), .b(b), .p(p)
    );
endmodule
