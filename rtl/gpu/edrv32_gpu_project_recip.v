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
    output wire [5:0] exponent_o,

    // Shared ten-enabled-cycle exponent delay RAM.
    output wire [5:0] delay_exponent_wr_data_o,
    input wire [5:0] delay_exponent_rd_data_i
);
    reg [9:0] valid_r;
    reg [5:0] exponent_w;
    wire [4:0] leading_group_w;
    wire [2:0] leading_position_w [0:4];
    reg [39:0] unused_normalized_w;
    wire [30:0] mantissa_w [0:1];
    wire [29:0] seed_w;
    wire [29:0] seed_wide_w [2:5];
    wire [60:0] product_w [2:4];
    wire [61:0] unused_rounded_product_w;
    reg [31:0] correction_r;
    wire [61:0] result_w [6:8];
    wire [62:0] unused_rounded_result_w;
    reg [30:0] reciprocal_r;
    // Newton stages 2 and 6 each contain one multiplier (31x30 and 30x32).
    genvar stage_g;

    assign value_valid_o = valid_r[9];
    assign reciprocal_o = reciprocal_r;
    assign exponent_o = delay_exponent_rd_data_i;
    assign delay_exponent_wr_data_o = exponent_w;
    assign unused_rounded_product_w = {1'b0, product_w[4]} + 62'd536870912;
    assign unused_rounded_result_w = {1'b0, result_w[8]} + 63'd536870912;

    always @(*) begin
        exponent_w = 6'd0;
        unused_normalized_w = 40'd0;
        // Two-level priority encoder: five groups of eight, then one five-way selector.
        casez (leading_group_w)
            5'b1????: exponent_w = {3'd4, leading_position_w[4]};
            5'b01???: exponent_w = {3'd3, leading_position_w[3]};
            5'b001??: exponent_w = {3'd2, leading_position_w[2]};
            5'b0001?: exponent_w = {3'd1, leading_position_w[1]};
            5'b00001: exponent_w = {3'd0, leading_position_w[0]};
            default: begin end
        endcase
        unused_normalized_w = exponent_w >= 6'd30
            ? value_i >> (exponent_w - 6'd30) : value_i << (6'd30 - exponent_w);
    end

    // Normalization stage: five parallel 8-bit encoders; no serial 40-entry scan.
    genvar group_g;
    generate
        for (group_g = 0; group_g < 5; group_g = group_g + 1) begin : g_leading
            reg [2:0] position_w;
            assign leading_group_w[group_g] = |value_i[group_g * 8 +: 8];
            assign leading_position_w[group_g] = position_w;
            always @(*) begin
                position_w = 3'd0;
                casez (value_i[group_g * 8 +: 8])
                    8'b1???????: position_w = 3'd7;
                    8'b01??????: position_w = 3'd6;
                    8'b001?????: position_w = 3'd5;
                    8'b0001????: position_w = 3'd4;
                    8'b00001???: position_w = 3'd3;
                    8'b000001??: position_w = 3'd2;
                    8'b0000001?: position_w = 3'd1;
                    8'b00000001: position_w = 3'd0;
                    default: begin end
                endcase
            end
        end
        for (stage_g = 0; stage_g <= 1; stage_g = stage_g + 1) begin : g_mantissa
            reg [30:0] data_r;
            wire [30:0] next_w;
            if (stage_g == 0) begin : g_first
                assign next_w = unused_normalized_w[30:0];
            end else begin : g_delay
                assign next_w = mantissa_w[stage_g - 1];
            end
            assign mantissa_w[stage_g] = data_r;
            always @(posedge clk_i) begin
                if (enable_i) data_r <= next_w;
            end
        end
        for (stage_g = 2; stage_g <= 5; stage_g = stage_g + 1) begin : g_seed
            reg [29:0] data_r;
            wire [29:0] next_w;
            if (stage_g == 2) begin : g_first
                assign next_w = seed_w;
            end else begin : g_delay
                assign next_w = seed_wide_w[stage_g - 1];
            end
            assign seed_wide_w[stage_g] = data_r;
            always @(posedge clk_i) begin
                if (enable_i) data_r <= next_w;
            end
        end
        for (stage_g = 2; stage_g <= 4; stage_g = stage_g + 1) begin : g_product
            reg [60:0] data_r;
            wire [60:0] next_w;
            if (stage_g == 2) begin : g_first
                assign next_w = mantissa_w[1] * seed_w;
            end else begin : g_delay
                assign next_w = product_w[stage_g - 1];
            end
            assign product_w[stage_g] = data_r;
            always @(posedge clk_i) begin
                if (enable_i) data_r <= next_w;
            end
        end
        for (stage_g = 6; stage_g <= 8; stage_g = stage_g + 1) begin : g_result
            reg [61:0] data_r;
            wire [61:0] next_w;
            if (stage_g == 6) begin : g_first
                assign next_w = seed_wide_w[5] * correction_r;
            end else begin : g_delay
                assign next_w = result_w[stage_g - 1];
            end
            assign result_w[stage_g] = data_r;
            always @(posedge clk_i) begin
                if (enable_i) data_r <= next_w;
            end
        end
    endgenerate

    edrv32_rom_gpu_recip_q30 u_seed (
        .clk_i(clk_i),
        .en_i(enable_i),
        .addr_i(mantissa_w[0][29:20]),
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
            correction_r <= 32'd2147483648 - unused_rounded_product_w[61:30];
            reciprocal_r <= unused_rounded_result_w[60:30];
        end
    end
endmodule
