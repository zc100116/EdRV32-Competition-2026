// File: edrv32_gpu_perspective_sign.v
// Spec: gpu-spec 2.13; microarch 4.6, 4.10.
// Description: Fixed-width registered arithmetic; global enable preserves pipeline alignment.
// Clock domain: clk_gpu.
module edrv32_gpu_perspective_sign (
    // Clock and common pipeline enable.
    input wire clk_i,
    input wire en_i,

    // Arithmetic payload.
    input wire [31:0] magnitude_i,
    input wire sign_i,
    output wire [31:0] value_o
);
    reg [31:0] result_r;
    assign value_o = result_r;
    always @(posedge clk_i) begin
        if (en_i) result_r <= (magnitude_i ^ {32{sign_i}}) + {31'b0, sign_i};
    end
endmodule
