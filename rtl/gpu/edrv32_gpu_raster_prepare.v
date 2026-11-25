// File: edrv32_gpu_raster_prepare.v
// Spec: gpu-spec 2.13.7; microarch 4.6, 4.10.
// Description: One CSA stage followed by two registered carry stages.
// Clock domain: clk_gpu.
module edrv32_gpu_raster_prepare (
    // Clock and shared pipeline enable.
    input wire clk_i,
    input wire en_i,

    // Arithmetic payload.
    input wire [69:0] a_i,
    input wire [69:0] b_i,
    input wire [69:0] c_i,
    output wire [69:0] sum_o
);
    reg [69:0] sum_r;
    reg [69:0] carry_r;
    always @(posedge clk_i) begin
        if (en_i) begin
            sum_r <= a_i ^ b_i ^ c_i;
            carry_r <= ((a_i & b_i) | (a_i & c_i) | (b_i & c_i)) << 1;
        end
    end
    edrv32_gpu_raster_add u_add (
        .clk_i(clk_i),
        .en_i(en_i),
        .a_i(sum_r),
        .b_i(carry_r),
        .sum_o(sum_o)
    );
endmodule
