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
    reg [95:0] a_r;
    reg [95:0] b_r;
    reg [4:0] greater_r;
    reg [4:0] unused_equal_r;
    reg [95:0] result_r;
    wire choose_a_w;
    assign choose_a_w = greater_r[4] || (unused_equal_r[4] && greater_r[3]) ||
        (&unused_equal_r[4:3] && greater_r[2]) || (&unused_equal_r[4:2] && greater_r[1]) ||
        (&unused_equal_r[4:1] && greater_r[0]);
    assign value_o = result_r;
    always @(posedge clk_i) begin
        if (en_i) begin
            a_r <= a_i;
            b_r <= b_i;
            greater_r[0] <= a_i[0 +: 20] > b_i[0 +: 20];
            unused_equal_r[0] <= a_i[0 +: 20] == b_i[0 +: 20];
            greater_r[1] <= a_i[20 +: 20] > b_i[20 +: 20];
            unused_equal_r[1] <= a_i[20 +: 20] == b_i[20 +: 20];
            greater_r[2] <= a_i[40 +: 20] > b_i[40 +: 20];
            unused_equal_r[2] <= a_i[40 +: 20] == b_i[40 +: 20];
            greater_r[3] <= a_i[60 +: 20] > b_i[60 +: 20];
            unused_equal_r[3] <= a_i[60 +: 20] == b_i[60 +: 20];
            greater_r[4] <= a_i[80 +: 16] > b_i[80 +: 16];
            unused_equal_r[4] <= a_i[80 +: 16] == b_i[80 +: 16];
            result_r <= choose_a_w ? a_r : b_r;
        end
    end
endmodule
