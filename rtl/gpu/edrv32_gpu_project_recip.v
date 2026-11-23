// File: edrv32_gpu_project_recip.v
// Spec: gpu-spec 2.12; GPU microarchitecture 4.3, 4.10.
// Description: Q30 normalized reciprocal, midpoint seed and one Newton iteration.
//              Ten enabled pipeline stages; preserve the normalization exponent.
// Clock domain: clk_gpu.
module edrv32_gpu_project_recip (
    // Clock and reset.
    input wire clk_i,
    input wire rst_n_i,

    // Positive unsigned input and pipeline clock enable.
    input wire enable_i,
    input wire stop_i,
    input wire value_valid_i,
    input wire [39:0] value_i,

    // Normalized reciprocal and original leading-one exponent.
    output wire value_valid_o,
    output wire [30:0] reciprocal_o,
    output wire [5:0] exponent_o
);
    reg [9:0] valid_r;
    reg [5:0] exponent_r [0:9];
    reg [5:0] exponent_w;
    reg [39:0] unused_normalized_w;
    reg [30:0] mantissa_r [0:1];
    wire [29:0] seed_w;
    reg [29:0] seed_r [2:5];
    reg [60:0] product_r [2:4];
    wire [61:0] unused_rounded_product_w;
    reg [31:0] correction_r;
    reg [61:0] result_r [6:8];
    wire [62:0] unused_rounded_result_w;
    reg [30:0] reciprocal_r;
    integer leading_w;
    integer stage_r;

    assign value_valid_o = valid_r[9];
    assign reciprocal_o = reciprocal_r;
    assign exponent_o = exponent_r[9];
    assign unused_rounded_product_w = {1'b0, product_r[4]} + 62'd536870912;
    assign unused_rounded_result_w = {1'b0, result_r[8]} + 63'd536870912;

    always @(*) begin
        exponent_w = 6'd0;
        unused_normalized_w = 40'd0;
        for (leading_w = 0; leading_w < 40; leading_w = leading_w + 1) begin
            if (value_i[leading_w]) begin
                exponent_w = leading_w[5:0];
            end
        end
        if (exponent_w >= 6'd30) begin
            unused_normalized_w = value_i >> (exponent_w - 6'd30);
        end else begin
            unused_normalized_w = value_i << (6'd30 - exponent_w);
        end
    end

    edrv32_rom_gpu_recip_q30 u_seed (
        .clk_i(clk_i),
        .en_i(enable_i),
        .addr_i(mantissa_r[0][29:20]),
        .rd_data_o(seed_w)
    );

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            valid_r <= 10'd0;
        end else if (stop_i) begin
            valid_r <= 10'd0;
        end else if (enable_i) begin
            valid_r <= {valid_r[8:0], value_valid_i};
        end
    end

    always @(posedge clk_i) begin
        if (enable_i) begin
            exponent_r[0] <= exponent_w;
            for (stage_r = 1; stage_r < 10; stage_r = stage_r + 1) begin
                exponent_r[stage_r] <= exponent_r[stage_r - 1];
            end
            mantissa_r[0] <= unused_normalized_w[30:0];
            mantissa_r[1] <= mantissa_r[0];
            seed_r[2] <= seed_w;
            product_r[2] <= mantissa_r[1] * seed_w;
            for (stage_r = 3; stage_r < 5; stage_r = stage_r + 1) begin
                seed_r[stage_r] <= seed_r[stage_r - 1];
                product_r[stage_r] <= product_r[stage_r - 1];
            end
            seed_r[5] <= seed_r[4];
            correction_r <= 32'd2147483648 - unused_rounded_product_w[61:30];
            result_r[6] <= seed_r[5] * correction_r;
            result_r[7] <= result_r[6];
            result_r[8] <= result_r[7];
            reciprocal_r <= unused_rounded_result_w[60:30];
        end
    end
endmodule
