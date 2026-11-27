// File: edrv32_gpu_raster_add.v
// Spec: gpu-spec 2.13.7; microarch 4.6, 4.10.
// Description: Lossless fixed-width addition with two result clocks; 32-bit uses one carry.
// Clock domain: clk_gpu.
// Fixed widths: 32/42 attributes, 40 edges, 52/72 setup (gpu-spec v0.6 2.13).
module edrv32_gpu_raster_add #(
    parameter WIDTH = 42
) (
    // Clock and shared pipeline enable.
    input wire clk_i,
    input wire en_i,

    // Arithmetic payload.
    input wire [WIDTH-1:0] a_i,
    input wire [WIDTH-1:0] b_i,
    output wire [WIDTH-1:0] sum_o
);
    generate
        if (WIDTH <= 36) begin : g_single_carry
            // One carry chain; the second register preserves the shared issue schedule.
            reg [WIDTH-1:0] sum_r;
            reg [WIDTH-1:0] result_r;
            assign sum_o = result_r;
            always @(posedge clk_i) begin
                if (en_i) begin
                    sum_r <= a_i + b_i;
                    result_r <= sum_r;
                end
            end
        end else begin : g_split_carry
            localparam LOW = WIDTH > 70 ? 36 : 35;
            // Each carry chain is at most 36 bits, including the P-A setup sum.
            reg [WIDTH-LOW-1:0] high_a_r;
            reg [WIDTH-LOW-1:0] high_b_r;
            reg [LOW-1:0] low_r;
            reg carry_r;
            reg [WIDTH-1:0] result_r;
            wire [LOW:0] low_w;
            wire [WIDTH-LOW-1:0] high_w;
            assign low_w = {1'b0, a_i[LOW-1:0]} + {1'b0, b_i[LOW-1:0]};
            assign high_w = high_a_r + high_b_r + {{(WIDTH-LOW-1){1'b0}}, carry_r};
            assign sum_o = result_r;
            always @(posedge clk_i) begin
                if (en_i) begin
                    high_a_r <= a_i[WIDTH-1:LOW];
                    high_b_r <= b_i[WIDTH-1:LOW];
                    low_r <= low_w[LOW-1:0];
                    carry_r <= low_w[LOW];
                    result_r <= {high_w, low_r};
                end
            end
        end
    endgenerate
endmodule
