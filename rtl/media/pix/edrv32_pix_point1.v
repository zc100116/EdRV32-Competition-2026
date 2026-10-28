// File: edrv32_pix_point1.v
// Spec: pix-spec 2.1-2.3, 2.6.
// Description: Expand RGB565, apply signed brightness/contrast and shared Gamma.
// Six asynchronous table read ports provide both RGB888 pixels each cycle.
// Clock: clk_mem.
module edrv32_pix_point1 (
    // Clock and reset.
    input wire clk_i,
    input wire rst_n_i,

    // Input stream.
    input wire valid_i,
    input wire [31:0] data_i,
    input wire sof_i,
    input wire eol_i,
    input wire eof_i,

    // Output stream.
    output reg valid_o,
    output reg [47:0] data_o,
    output reg sof_o,
    output reg eol_o,
    output reg eof_o,

    // Pipeline and frame configuration.
    input wire advance_i,
    input wire clear_i,
    input wire bc_en_i,
    input wire gamma_en_i,
    input wire gamma_bank_i,
    input wire [8:0] contrast_i,
    input wire [8:0] brightness_i,
    input wire gamma_wr_i,
    input wire [8:0] gamma_addr_i,
    input wire [7:0] gamma_data_i
);
    reg [7:0] gamma_r [0:511];
    wire [47:0] expanded_w;
    wire [47:0] corrected_w;
    wire [47:0] mapped_w;
    genvar lane;
    genvar channel;

    function [7:0] correct;
        input [7:0] value_i;
        input [8:0] arg_contrast_i;
        input [8:0] arg_brightness_i;
        reg signed [18:0] centered;
        reg signed [18:0] product;
        reg signed [18:0] adjusted;
        begin
            centered = $signed({11'd0, value_i}) - 19'sd128;
            product = centered * $signed({10'd0, arg_contrast_i});
            adjusted = (product >>> 8) + 19'sd128
                + $signed({{10{arg_brightness_i[8]}}, arg_brightness_i});
            if (adjusted < 0) begin
                correct = 8'd0;
            end else if (adjusted > 255) begin
                correct = 8'd255;
            end else begin
                correct = adjusted[7:0];
            end
        end
    endfunction

    generate
        for (lane = 0; lane < 2; lane = lane + 1) begin : g_expand
            assign expanded_w[lane*24 +: 24] = {
                data_i[lane*16+11 +: 5], data_i[lane*16+13 +: 3],
                data_i[lane*16+5 +: 6], data_i[lane*16+9 +: 2],
                data_i[lane*16 +: 5], data_i[lane*16+2 +: 3]};
        end
        for (channel = 0; channel < 6; channel = channel + 1) begin : g_channel
            assign corrected_w[channel*8 +: 8] = bc_en_i
                ? correct(expanded_w[channel*8 +: 8], contrast_i, brightness_i)
                : expanded_w[channel*8 +: 8];
            assign mapped_w[channel*8 +: 8] = gamma_en_i
                ? gamma_r[{gamma_bank_i, corrected_w[channel*8 +: 8]}]
                : corrected_w[channel*8 +: 8];
        end
    endgenerate

    // spec pix 2.3: table writes are immediate and independent of stream stalls/reset.
    always @(posedge clk_i) begin
        if (gamma_wr_i) begin
            gamma_r[gamma_addr_i] <= gamma_data_i;
        end
        if (advance_i) begin
            data_o <= mapped_w;
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
