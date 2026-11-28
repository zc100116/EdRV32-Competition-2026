// File: edrv32_fpga_probe_gpu2_setup_top.v
// Spec: gpu-v2-spec 2.4/2.6; G-P03/G-P04.
// Description: Independent II1 arithmetic paths.
//              Local stimulus and observation registers preserve measured boundaries.
// Clock domain: clk_gpu, 220 MHz probe constraint.
module edrv32_fpga_probe_gpu2_setup_top (
    input wire clk_i,
    input wire rst_n_i,
    input wire stim_i,
    output wire obs_o
);
    (* keep = "true", syn_preserve = 1 *) reg [81:0] mantissa_r;
    always @(posedge clk_i) begin
        mantissa_r <=
            {mantissa_r[80:0], mantissa_r[81] ^ stim_i};
    end
    (* keep = "true", syn_preserve = 1 *) reg [9:0] exponent_r;
    always @(posedge clk_i) begin
        exponent_r <=
            {exponent_r[8:0], exponent_r[9] ^ stim_i};
    end
    wire [0:0] norm_valid_w;
    reg norm_valid_observed_r;
    always @(posedge clk_i) begin
        norm_valid_observed_r <= ^norm_valid_w;
    end
    wire [47:0] mantissa_w;
    reg mantissa_observed_r;
    always @(posedge clk_i) begin
        mantissa_observed_r <= ^mantissa_w;
    end
    wire [9:0] exponent_w;
    reg exponent_observed_r;
    always @(posedge clk_i) begin
        exponent_observed_r <= ^exponent_w;
    end
    (* keep = "true", syn_preserve = 1 *) reg [48:0] a_r;
    always @(posedge clk_i) begin
        a_r <=
            {a_r[47:0], a_r[48] ^ stim_i};
    end
    (* keep = "true", syn_preserve = 1 *) reg [32:0] b_r;
    always @(posedge clk_i) begin
        b_r <=
            {b_r[31:0], b_r[32] ^ stim_i};
    end
    wire [0:0] product_valid_w;
    reg product_valid_observed_r;
    always @(posedge clk_i) begin
        product_valid_observed_r <= ^product_valid_w;
    end
    wire [81:0] product_w;
    reg product_observed_r;
    always @(posedge clk_i) begin
        product_observed_r <= ^product_w;
    end
    (* keep = "true", syn_preserve = 1 *) reg [47:0] start_r;
    always @(posedge clk_i) begin
        start_r <=
            {start_r[46:0], start_r[47] ^ stim_i};
    end
    (* keep = "true", syn_preserve = 1 *) reg [47:0] gx_r;
    always @(posedge clk_i) begin
        gx_r <=
            {gx_r[46:0], gx_r[47] ^ stim_i};
    end
    (* keep = "true", syn_preserve = 1 *) reg [47:0] gy_r;
    always @(posedge clk_i) begin
        gy_r <=
            {gy_r[46:0], gy_r[47] ^ stim_i};
    end
    (* keep = "true", syn_preserve = 1 *) reg [4:0] tile_x_r;
    always @(posedge clk_i) begin
        tile_x_r <=
            {tile_x_r[3:0], tile_x_r[4] ^ stim_i};
    end
    (* keep = "true", syn_preserve = 1 *) reg [3:0] tile_y_r;
    always @(posedge clk_i) begin
        tile_y_r <=
            {tile_y_r[2:0], tile_y_r[3] ^ stim_i};
    end
    wire [0:0] relocate_valid_w;
    reg relocate_valid_observed_r;
    always @(posedge clk_i) begin
        relocate_valid_observed_r <= ^relocate_valid_w;
    end
    wire [59:0] start_w;
    reg start_observed_r;
    always @(posedge clk_i) begin
        start_observed_r <= ^start_w;
    end
    edrv32_gpu2_setup_probe u_probe (
        .clk_i(clk_i),
        .rst_n_i(rst_n_i),
        .valid_i(1'b1),
        .mantissa_i(mantissa_r),
        .exponent_i(exponent_r),
        .norm_valid_o(norm_valid_w),
        .mantissa_o(mantissa_w),
        .exponent_o(exponent_w),
        .a_i(a_r),
        .b_i(b_r),
        .product_valid_o(product_valid_w),
        .product_o(product_w),
        .start_i(start_r),
        .gx_i(gx_r),
        .gy_i(gy_r),
        .tile_x_i(tile_x_r),
        .tile_y_i(tile_y_r),
        .relocate_valid_o(relocate_valid_w),
        .start_o(start_w)
    );
    reg observation_r;
    always @(posedge clk_i) begin
        observation_r <= norm_valid_observed_r ^
            mantissa_observed_r ^
            exponent_observed_r ^
            product_valid_observed_r ^
            product_observed_r ^
            relocate_valid_observed_r ^
            start_observed_r;
    end
    assign obs_o = observation_r;
endmodule
