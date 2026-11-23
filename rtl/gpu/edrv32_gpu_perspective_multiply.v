// File: edrv32_gpu_perspective_multiply.v
// Spec: gpu-spec 2.13; microarch 4.6, 4.10.
// Description: Fixed-width registered arithmetic; global enable preserves pipeline alignment.
// Clock domain: clk_gpu.
module edrv32_gpu_perspective_multiply (
    // Clock and common pipeline enable.
    input wire clk_i,
    input wire en_i,

    // Arithmetic payload.
    input wire [17:0] a_i,
    input wire [17:0] b_i,
    input wire sign_i,
    input wire [9:0] exponent_i,
    output wire [35:0] magnitude_o,
    output wire sign_o,
    output wire [9:0] exponent_o
);
    reg [17:0] a_r;
    reg [17:0] b_r;
    reg [35:0] product_r;
    reg [35:0] output_r;
    reg [1:0] sign_r;
    reg [9:0] exponent_r [0:1];
    reg output_sign_r;
    reg [9:0] output_exponent_r;
    assign magnitude_o = output_r;
    assign sign_o = output_sign_r;
    assign exponent_o = output_exponent_r;
    always @(posedge clk_i) begin
        if (en_i) begin
            a_r <= a_i;
            b_r <= b_i;
            sign_r[0] <= sign_i;
            exponent_r[0] <= exponent_i;
            product_r <= a_r * b_r;
            sign_r[1] <= sign_r[0];
            exponent_r[1] <= exponent_r[0];
            output_r <= product_r;
            output_sign_r <= sign_r[1];
            output_exponent_r <= exponent_r[1];
        end
    end
endmodule
