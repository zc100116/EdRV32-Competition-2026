// File: edrv32_gpu_perspective_maximum.v
// Spec: gpu-spec 2.13; microarch 4.6, 4.10.
// Description: Fixed-width registered arithmetic; global enable preserves pipeline alignment.
// Clock domain: clk_gpu.
module edrv32_gpu_perspective_maximum (
    // Clock and common pipeline enable.
    input wire clk_i,
    input wire en_i,

    // Arithmetic payload.
    input wire [95:0] a_i,
    input wire [95:0] b_i,
    output wire [95:0] value_o
);
    // Five parallel 32-bit carry comparisons, then a five-input priority select
    // and the data selector: two LUT levels after a carry chain of at most 32 bits.
    wire [2:0] greater_w;
    wire [2:1] greater_equal_w;
    wire choose_a_w;
    reg [95:0] result_r;
    assign greater_w[0] = a_i[31:0] > b_i[31:0];
    assign greater_w[1] = a_i[63:32] > b_i[63:32];
    assign greater_w[2] = a_i[95:64] > b_i[95:64];
    assign greater_equal_w[1] = a_i[63:32] >= b_i[63:32];
    assign greater_equal_w[2] = a_i[95:64] >= b_i[95:64];
    assign choose_a_w = greater_w[2] || (greater_equal_w[2] &&
        (greater_w[1] || (greater_equal_w[1] && greater_w[0])));
    assign value_o = result_r;
    always @(posedge clk_i) begin
        if (en_i) result_r <= choose_a_w ? a_i : b_i;
    end
endmodule
