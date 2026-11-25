// File: edrv32_gpu_perspective_normal.v
// Spec: gpu-spec 2.13; microarch 4.13.
// Description: Fixed-width registered arithmetic; global enable preserves pipeline alignment.
// Clock domain: clk_gpu.
// Input widths are the spec 2.13 plane, product and aligned-difference widths.
module edrv32_gpu_perspective_normal #(
    parameter WIDTH = 66
) (
    // Clock and common pipeline enable.
    input wire clk_i,
    input wire en_i,

    // Arithmetic payload.
    input wire [WIDTH-1:0] magnitude_i,
    input wire sign_i,
    input wire [9:0] exponent_i,
    output wire [28:0] normal_o
);
    wire [65:0] magnitude_w;
    wire high_w;
    wire [63:0] count_value_w;
    wire [15:0] nibble_valid_w;
    wire [31:0] nibble_position_w;
    wire [3:0] block_valid_w;
    wire [15:0] block_position_w;
    reg [1:0] block_select_w;
    wire [3:0] block_position_selected_w;
    wire [6:0] leading_w;
    wire [6:0] exponent_delta_w;
    wire [4:0] window_position_w;
    wire [35:0] window_w;
    reg [35:0] value_r;
    reg [5:0] shift_r;
    reg [9:0] exponent_r;
    reg sign_r;
    reg [18:0] shifted_r;
    reg [9:0] shifted_exponent_r;
    reg shifted_sign_r;
    wire [35:0] shift_1_w;
    wire [35:0] shift_4_w;
    wire [18:0] shift_16_w;
    reg zero_r;
    reg shifted_zero_r;
    wire [18:0] rounded_w;
    reg [28:0] result_r;
    assign magnitude_w = {{(66-WIDTH){1'b0}}, magnitude_i};
    assign high_w = |magnitude_w[65:64];
    assign count_value_w = magnitude_w[63:0];
    assign leading_w = high_w ? {6'b100000, magnitude_w[65]} :
        {1'b0, block_select_w, block_position_selected_w};
    assign window_position_w = high_w ? {4'b1000, magnitude_w[65]} :
        {1'b0, block_position_selected_w};
    assign exponent_delta_w = leading_w - 7'd17;
    assign rounded_w = {1'b0, shifted_r[18:1]} + {18'b0, shifted_r[0]};
    assign normal_o = result_r;
    genvar nibble;
    genvar block_idx;
    generate
        // Sixteen parallel four-bit encoders; each output is one small LUT function.
        for (nibble = 0; nibble < 16; nibble = nibble + 1) begin : g_nibble
            wire [3:0] value_w;
            wire [1:0] position_w;
            assign value_w = count_value_w[nibble*4 +: 4];
            assign nibble_valid_w[nibble] = |value_w;
            assign position_w[1] = |value_w[3:2];
            assign position_w[0] = value_w[3] || (!value_w[2] && value_w[1]);
            assign nibble_position_w[nibble*2 +: 2] = position_w;
        end
        // Four 16-bit blocks: four-way priority plus four-way position selection.
        for (block_idx = 0; block_idx < 4; block_idx = block_idx + 1) begin : g_block
            reg [1:0] select_w;
            wire [1:0] position_w;
            assign block_valid_w[block_idx] = |nibble_valid_w[block_idx*4 +: 4]
                || (block_idx == 3 && high_w);
            assign block_position_w[block_idx*4 +: 4] = {select_w, position_w};
            always @(*) begin
                select_w = 0;
                casez (nibble_valid_w[block_idx*4 +: 4])
                    4'b1???: select_w = 3;
                    4'b01??: select_w = 2;
                    4'b001?: select_w = 1;
                    default: begin end
                endcase
            end
            assign position_w = select_w[1] ?
                (select_w[0] ? nibble_position_w[block_idx*8+6 +: 2] :
                nibble_position_w[block_idx*8+4 +: 2]) :
                (select_w[0] ? nibble_position_w[block_idx*8+2 +: 2] :
                nibble_position_w[block_idx*8 +: 2]);
        end
    endgenerate
    always @(*) begin
        block_select_w = 0;
        casez (block_valid_w)
            4'b1???: block_select_w = 3;
            4'b01??: block_select_w = 2;
            4'b001?: block_select_w = 1;
            default: begin end
        endcase
    end
    assign block_position_selected_w = block_select_w[1] ?
        (block_select_w[0] ? block_position_w[12 +: 4] : block_position_w[8 +: 4]) :
        (block_select_w[0] ? block_position_w[4 +: 4] : block_position_w[0 +: 4]);
    generate
        if (WIDTH > 36) begin : g_plane_window
            // Highest 16-bit block plus 18 lower bits preserve mantissa and guard.
            assign window_w = block_select_w[1] ?
                (block_select_w[0] ? magnitude_w[65:30] : {2'b0, magnitude_w[47:14]}) :
                (block_select_w[0] ? {2'b0, magnitude_w[31:0], 2'b0} :
                {2'b0, magnitude_w[15:0], 18'b0});
        end else begin : g_product_window
            // Products and aligned differences already fit in one 36-bit window.
            assign window_w = {{(36-WIDTH){1'b0}}, magnitude_i};
        end
    endgenerate
    // Each two-bit field selects one balanced four-input LUT6 stage.
    assign shift_1_w = shift_r[1] ?
        (shift_r[0] ? {value_r[32:0], 3'b0} : {value_r[33:0], 2'b0}) :
        (shift_r[0] ? {value_r[34:0], 1'b0} : value_r);
    assign shift_4_w = shift_r[3] ?
        (shift_r[2] ? {shift_1_w[23:0], 12'b0} : {shift_1_w[27:0], 8'b0}) :
        (shift_r[2] ? {shift_1_w[31:0], 4'b0} : shift_1_w);
    assign shift_16_w = shift_r[5] ?
        (shift_r[4] ? 19'b0 : {shift_4_w[3:0], 15'b0}) :
        (shift_r[4] ? shift_4_w[19:1] : shift_4_w[35:17]);
    always @(posedge clk_i) begin
        if (en_i) begin
            value_r <= window_w;
            zero_r <= !(|block_valid_w);
            shift_r <= WIDTH > 36 ? {1'b0, 5'd17 - window_position_w} :
                6'd35 - leading_w[5:0];
            exponent_r <= exponent_i + {{3{exponent_delta_w[6]}}, exponent_delta_w};
            sign_r <= sign_i;
            shifted_r <= shift_16_w;
            shifted_zero_r <= zero_r;
            shifted_exponent_r <= exponent_r;
            shifted_sign_r <= sign_r;
            result_r <= shifted_zero_r ? 29'b0 :
                {shifted_exponent_r + {9'b0, rounded_w[18]}, shifted_sign_r,
                rounded_w[18] ? rounded_w[18:1] : rounded_w[17:0]};
        end
    end
endmodule
