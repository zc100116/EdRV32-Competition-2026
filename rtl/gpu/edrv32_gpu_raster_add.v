// File: edrv32_gpu_raster_add.v
// Spec: gpu-spec 2.13.7; microarch 4.6, 4.10.
// Description: Lossless 70-bit arithmetic with two registered 35-bit carry slices.
// Clock domain: clk_gpu.
module edrv32_gpu_raster_add (
    // Clock and shared pipeline enable.
    input wire clk_i,
    input wire en_i,

    // Arithmetic payload.
    input wire [69:0] a_i,
    input wire [69:0] b_i,
    output wire [69:0] sum_o
);
    // Only the unconsumed high halves cross the first register boundary.
    reg [34:0] high_a_r;
    reg [34:0] high_b_r;
    reg [34:0] low_r;
    reg carry_r;
    reg [69:0] result_r;
    wire [35:0] low_w;
    wire [34:0] high_w;
    assign low_w = {1'b0, a_i[34:0]} + {1'b0, b_i[34:0]};
    assign high_w = high_a_r + high_b_r + {34'b0, carry_r};
    assign sum_o = result_r;
    always @(posedge clk_i) begin
        if (en_i) begin
            high_a_r <= a_i[69:35];
            high_b_r <= b_i[69:35];
            low_r <= low_w[34:0];
            carry_r <= low_w[35];
            result_r <= {high_w, low_r};
        end
    end
endmodule
