// File: edrv32_gpu_perspective_absolute.v
// Spec: gpu-spec 2.13; microarch 4.6, 4.10.
// Description: Fixed-width registered arithmetic; global enable preserves pipeline alignment.
// Clock domain: clk_gpu.
module edrv32_gpu_perspective_absolute (
    // Clock and common pipeline enable.
    input wire clk_i,
    input wire en_i,

    // Arithmetic payload.
    input wire signed [65:0] value_i,
    input wire [9:0] exponent_i,
    output wire [65:0] magnitude_o,
    output wire sign_o,
    output wire [9:0] exponent_o
);
    reg [30:0] high_r;
    reg [34:0] low_r;
    reg carry_r;
    reg sign_r;
    reg [9:0] exponent_r;
    reg [65:0] magnitude_r;
    reg output_sign_r;
    reg [9:0] output_exponent_r;
    wire [35:0] low_w;
    wire [30:0] high_w;
    assign low_w = {1'b0, (value_i[34:0] ^ {35{value_i[65]}})}
        + {35'b0, value_i[65]};
    assign high_w = high_r + {30'b0, carry_r};
    assign magnitude_o = magnitude_r;
    assign sign_o = output_sign_r;
    assign exponent_o = output_exponent_r;
    always @(posedge clk_i) begin
        if (en_i) begin
            high_r <= value_i[65:35] ^ {31{value_i[65]}};
            low_r <= low_w[34:0];
            carry_r <= low_w[35];
            sign_r <= value_i[65];
            exponent_r <= exponent_i;
            magnitude_r <= {high_w, low_r};
            output_sign_r <= sign_r;
            output_exponent_r <= exponent_r;
        end
    end
endmodule
