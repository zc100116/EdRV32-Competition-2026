// File: edrv32_pix_point2.v
// Spec: pix-spec 2.1, 2.5.
// Description: Ordered grayscale, threshold and per-channel inversion.
// Quantize the resulting RGB888 pair to the external RGB565 stream.
// Clock: clk_mem.
module edrv32_pix_point2 (
    // Clock and reset.
    input wire clk_i,
    input wire rst_n_i,

    // Input stream.
    input wire valid_i,
    input wire [47:0] data_i,
    input wire sof_i,
    input wire eol_i,
    input wire eof_i,

    // Output stream.
    output reg valid_o,
    output reg [31:0] data_o,
    output reg sof_o,
    output reg eol_o,
    output reg eof_o,

    // Pipeline and frame configuration.
    input wire advance_i,
    input wire clear_i,
    input wire gray_en_i,
    input wire bin_en_i,
    input wire inv_en_i,
    input wire [7:0] thresh_i
);
    wire [31:0] result_w;
    genvar lane;

    function [15:0] transform;
        input [23:0] rgb_i;
        input arg_gray_en_i;
        input arg_bin_en_i;
        input arg_inv_en_i;
        input [7:0] arg_thresh_i;
        reg [15:0] unused_sum;
        reg [7:0] y;
        reg [23:0] unused_value;
        begin
            unused_sum = 16'd77 * {8'd0, rgb_i[23:16]} + 16'd150 * {8'd0, rgb_i[15:8]}
                + 16'd29 * {8'd0, rgb_i[7:0]} + 16'd128;
            y = unused_sum[15:8];
            unused_value = arg_gray_en_i ? {y, y, y} : rgb_i;
            // Grayscale has Y unchanged, since the coefficients sum to 256.
            if (arg_bin_en_i) begin
                unused_value = y >= arg_thresh_i ? 24'hffffff : 24'd0;
            end
            if (arg_inv_en_i) begin
                unused_value = ~unused_value;
            end
            transform = {unused_value[23:19], unused_value[15:10], unused_value[7:3]};
        end
    endfunction

    generate
        for (lane = 0; lane < 2; lane = lane + 1) begin : g_lane
            assign result_w[lane*16 +: 16] = transform(data_i[lane*24 +: 24],
                gray_en_i, bin_en_i, inv_en_i, thresh_i);
        end
    endgenerate

    always @(posedge clk_i) begin
        if (advance_i) begin
            data_o <= result_w;
            sof_o <= sof_i;
            eol_o <= eol_i;
            eof_o <= eof_i;
        end
    end

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            valid_o <= 1'b0;
        end else if (clear_i) begin
            valid_o <= 1'b0;
        end else if (advance_i) begin
            valid_o <= valid_i;
        end
    end
endmodule
