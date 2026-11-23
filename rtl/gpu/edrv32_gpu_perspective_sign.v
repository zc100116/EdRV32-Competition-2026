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
    reg [31:0] unused_value_r;
    reg sign_r;
    reg [19:0] low_r;
    reg carry_r;
    reg [31:0] result_r;
    wire [20:0] low_w;
    wire [12:0] unused_high_w;
    assign low_w = {1'b0, (magnitude_i[19:0] ^ {20{sign_i}})} + {20'b0, sign_i};
    assign unused_high_w = {1'b0, (unused_value_r[31:20] ^ {12{sign_r}})} + {12'b0, carry_r};
    assign value_o = result_r;
    always @(posedge clk_i) begin
        if (en_i) begin
            unused_value_r <= magnitude_i;
            sign_r <= sign_i;
            low_r <= low_w[19:0];
            carry_r <= low_w[20];
            result_r <= {unused_high_w[11:0], low_r};
        end
    end
endmodule
