// File: edrv32_gpu2_setup_probe.v
// Spec: gpu-v2-spec 2.6; G-P03.
// Description: Independent reusable N48, six-APM full product and exact relocation paths.
//              Latencies are respectively 4, 6 and 4 clocks; all accept each clock.
// Clock domain: clk_gpu.
module edrv32_gpu2_setup_probe (
    // Clock and valid, independently observed paths use the same issue clock.
    input wire clk_i,
    input wire rst_n_i,
    input wire valid_i,

    // N48 path.
    input wire [81:0] mantissa_i,
    input wire [9:0] exponent_i,
    output wire norm_valid_o,
    output wire [47:0] mantissa_o,
    output wire [9:0] exponent_o,

    // Full product path, low bits are observable.
    input wire [48:0] a_i,
    input wire [32:0] b_i,
    output wire product_valid_o,
    output wire [81:0] product_o,

    // Integer tile relocation path.
    input wire [47:0] start_i,
    input wire [47:0] gx_i,
    input wire [47:0] gy_i,
    input wire [4:0] tile_x_i,
    input wire [3:0] tile_y_i,
    output wire relocate_valid_o,
    output wire [59:0] start_o
);
    edrv32_gpu2_setup_normalize u_normalize (
        .clk_i(clk_i),
        .rst_n_i(rst_n_i),
        .valid_i(valid_i),
        .mantissa_i(mantissa_i),
        .exponent_i(exponent_i),
        .valid_o(norm_valid_o),
        .mantissa_o(mantissa_o),
        .exponent_o(exponent_o)
    );
    edrv32_apm_gpu2_setup_s49xs33 u_multiply (
        .clk_i(clk_i),
        .a_i(a_i),
        .b_i(b_i),
        .product_o(product_o)
    );
    reg [5:0] product_valid_r;
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) product_valid_r <= 6'b0;
        else product_valid_r <= {product_valid_r[4:0], valid_i};
    end
    assign product_valid_o = product_valid_r[5];
    edrv32_gpu2_setup_relocate u_relocate (
        .clk_i(clk_i),
        .rst_n_i(rst_n_i),
        .valid_i(valid_i),
        .start_i(start_i),
        .gx_i(gx_i),
        .gy_i(gy_i),
        .tile_x_i(tile_x_i),
        .tile_y_i(tile_y_i),
        .valid_o(relocate_valid_o),
        .start_o(start_o)
    );
endmodule
