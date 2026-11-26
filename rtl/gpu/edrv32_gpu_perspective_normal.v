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
    reg [1:0] unused_block_select_w;
    wire [6:0] leading_w;
    reg [6:0] leading_r;
    wire [5:0] shift_w;
    wire [15:0] nibble_select_w;
    wire [95:0] nibble_shift_w;
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
        // Independent block-valid reductions select the 36-bit data window.
        for (block_idx = 0; block_idx < 4; block_idx = block_idx + 1) begin : g_block
            assign block_valid_w[block_idx] = |count_value_w[block_idx*16 +: 16]
                || (block_idx == 3 && high_w);
        end
    endgenerate
    always @(*) begin
        unused_block_select_w = 0;
        casez (block_valid_w)
            4'b1???: unused_block_select_w = 3;
            4'b01??: unused_block_select_w = 2;
            4'b001?: unused_block_select_w = 1;
            default: begin end
        endcase
    end
    generate
        if (WIDTH > 36) begin : g_plane_window
            // Highest 16-bit block plus 18 lower bits preserve mantissa and guard.
            assign window_w = unused_block_select_w[1] ?
                (unused_block_select_w[0] ? magnitude_w[65:30] : {2'b0, magnitude_w[47:14]}) :
                (unused_block_select_w[0] ? {2'b0, magnitude_w[31:0], 2'b0} :
                {2'b0, magnitude_w[15:0], 18'b0});
        end else begin : g_product_window
            // Products and aligned differences already fit in one 36-bit window.
            assign window_w = {{(36-WIDTH){1'b0}}, magnitude_i};
        end
    endgenerate
    // Sixteen parallel priority terms; encode shift directly before the first register.
    assign nibble_select_w[0] = nibble_valid_w[0] &&
        !(|magnitude_w[65:4]);
    assign nibble_shift_w[0 +: 6] = WIDTH > 36 ?
        (nibble_position_w[1] ? (nibble_position_w[0] ? 6'd14 : 6'd15) :
        (nibble_position_w[0] ? 6'd16 : 6'd17)) :
        (nibble_position_w[1] ? (nibble_position_w[0] ? 6'd32 : 6'd33) :
        (nibble_position_w[0] ? 6'd34 : 6'd35));
    assign nibble_select_w[1] = nibble_valid_w[1] &&
        !(|magnitude_w[65:8]);
    assign nibble_shift_w[6 +: 6] = WIDTH > 36 ?
        (nibble_position_w[3] ? (nibble_position_w[2] ? 6'd10 : 6'd11) :
        (nibble_position_w[2] ? 6'd12 : 6'd13)) :
        (nibble_position_w[3] ? (nibble_position_w[2] ? 6'd28 : 6'd29) :
        (nibble_position_w[2] ? 6'd30 : 6'd31));
    assign nibble_select_w[2] = nibble_valid_w[2] &&
        !(|magnitude_w[65:12]);
    assign nibble_shift_w[12 +: 6] = WIDTH > 36 ?
        (nibble_position_w[5] ? (nibble_position_w[4] ? 6'd6 : 6'd7) :
        (nibble_position_w[4] ? 6'd8 : 6'd9)) :
        (nibble_position_w[5] ? (nibble_position_w[4] ? 6'd24 : 6'd25) :
        (nibble_position_w[4] ? 6'd26 : 6'd27));
    assign nibble_select_w[3] = nibble_valid_w[3] &&
        !(|magnitude_w[65:16]);
    assign nibble_shift_w[18 +: 6] = WIDTH > 36 ?
        (nibble_position_w[7] ? (nibble_position_w[6] ? 6'd2 : 6'd3) :
        (nibble_position_w[6] ? 6'd4 : 6'd5)) :
        (nibble_position_w[7] ? (nibble_position_w[6] ? 6'd20 : 6'd21) :
        (nibble_position_w[6] ? 6'd22 : 6'd23));
    assign nibble_select_w[4] = nibble_valid_w[4] &&
        !(|magnitude_w[65:20]);
    assign nibble_shift_w[24 +: 6] = WIDTH > 36 ?
        (nibble_position_w[9] ? (nibble_position_w[8] ? 6'd14 : 6'd15) :
        (nibble_position_w[8] ? 6'd16 : 6'd17)) :
        (nibble_position_w[9] ? (nibble_position_w[8] ? 6'd16 : 6'd17) :
        (nibble_position_w[8] ? 6'd18 : 6'd19));
    assign nibble_select_w[5] = nibble_valid_w[5] &&
        !(|magnitude_w[65:24]);
    assign nibble_shift_w[30 +: 6] = WIDTH > 36 ?
        (nibble_position_w[11] ? (nibble_position_w[10] ? 6'd10 : 6'd11) :
        (nibble_position_w[10] ? 6'd12 : 6'd13)) :
        (nibble_position_w[11] ? (nibble_position_w[10] ? 6'd12 : 6'd13) :
        (nibble_position_w[10] ? 6'd14 : 6'd15));
    assign nibble_select_w[6] = nibble_valid_w[6] &&
        !(|magnitude_w[65:28]);
    assign nibble_shift_w[36 +: 6] = WIDTH > 36 ?
        (nibble_position_w[13] ? (nibble_position_w[12] ? 6'd6 : 6'd7) :
        (nibble_position_w[12] ? 6'd8 : 6'd9)) :
        (nibble_position_w[13] ? (nibble_position_w[12] ? 6'd8 : 6'd9) :
        (nibble_position_w[12] ? 6'd10 : 6'd11));
    assign nibble_select_w[7] = nibble_valid_w[7] &&
        !(|magnitude_w[65:32]);
    assign nibble_shift_w[42 +: 6] = WIDTH > 36 ?
        (nibble_position_w[15] ? (nibble_position_w[14] ? 6'd2 : 6'd3) :
        (nibble_position_w[14] ? 6'd4 : 6'd5)) :
        (nibble_position_w[15] ? (nibble_position_w[14] ? 6'd4 : 6'd5) :
        (nibble_position_w[14] ? 6'd6 : 6'd7));
    assign nibble_select_w[8] = nibble_valid_w[8] &&
        !(|magnitude_w[65:36]);
    assign nibble_shift_w[48 +: 6] = WIDTH > 36 ?
        (nibble_position_w[17] ? (nibble_position_w[16] ? 6'd14 : 6'd15) :
        (nibble_position_w[16] ? 6'd16 : 6'd17)) :
        (nibble_position_w[17] ? (nibble_position_w[16] ? 6'd0 : 6'd1) :
        (nibble_position_w[16] ? 6'd2 : 6'd3));
    assign nibble_select_w[9] = nibble_valid_w[9] &&
        !(|magnitude_w[65:40]);
    assign nibble_shift_w[54 +: 6] = WIDTH > 36 ?
        (nibble_position_w[19] ? (nibble_position_w[18] ? 6'd10 : 6'd11) :
        (nibble_position_w[18] ? 6'd12 : 6'd13)) :
        (nibble_position_w[19] ? (nibble_position_w[18] ? 6'd60 : 6'd61) :
        (nibble_position_w[18] ? 6'd62 : 6'd63));
    assign nibble_select_w[10] = nibble_valid_w[10] &&
        !(|magnitude_w[65:44]);
    assign nibble_shift_w[60 +: 6] = WIDTH > 36 ?
        (nibble_position_w[21] ? (nibble_position_w[20] ? 6'd6 : 6'd7) :
        (nibble_position_w[20] ? 6'd8 : 6'd9)) :
        (nibble_position_w[21] ? (nibble_position_w[20] ? 6'd56 : 6'd57) :
        (nibble_position_w[20] ? 6'd58 : 6'd59));
    assign nibble_select_w[11] = nibble_valid_w[11] &&
        !(|magnitude_w[65:48]);
    assign nibble_shift_w[66 +: 6] = WIDTH > 36 ?
        (nibble_position_w[23] ? (nibble_position_w[22] ? 6'd2 : 6'd3) :
        (nibble_position_w[22] ? 6'd4 : 6'd5)) :
        (nibble_position_w[23] ? (nibble_position_w[22] ? 6'd52 : 6'd53) :
        (nibble_position_w[22] ? 6'd54 : 6'd55));
    assign nibble_select_w[12] = nibble_valid_w[12] &&
        !(|magnitude_w[65:52]);
    assign nibble_shift_w[72 +: 6] = WIDTH > 36 ?
        (nibble_position_w[25] ? (nibble_position_w[24] ? 6'd14 : 6'd15) :
        (nibble_position_w[24] ? 6'd16 : 6'd17)) :
        (nibble_position_w[25] ? (nibble_position_w[24] ? 6'd48 : 6'd49) :
        (nibble_position_w[24] ? 6'd50 : 6'd51));
    assign nibble_select_w[13] = nibble_valid_w[13] &&
        !(|magnitude_w[65:56]);
    assign nibble_shift_w[78 +: 6] = WIDTH > 36 ?
        (nibble_position_w[27] ? (nibble_position_w[26] ? 6'd10 : 6'd11) :
        (nibble_position_w[26] ? 6'd12 : 6'd13)) :
        (nibble_position_w[27] ? (nibble_position_w[26] ? 6'd44 : 6'd45) :
        (nibble_position_w[26] ? 6'd46 : 6'd47));
    assign nibble_select_w[14] = nibble_valid_w[14] &&
        !(|magnitude_w[65:60]);
    assign nibble_shift_w[84 +: 6] = WIDTH > 36 ?
        (nibble_position_w[29] ? (nibble_position_w[28] ? 6'd6 : 6'd7) :
        (nibble_position_w[28] ? 6'd8 : 6'd9)) :
        (nibble_position_w[29] ? (nibble_position_w[28] ? 6'd40 : 6'd41) :
        (nibble_position_w[28] ? 6'd42 : 6'd43));
    assign nibble_select_w[15] = nibble_valid_w[15] &&
        !(|magnitude_w[65:64]);
    assign nibble_shift_w[90 +: 6] = WIDTH > 36 ?
        (nibble_position_w[31] ? (nibble_position_w[30] ? 6'd2 : 6'd3) :
        (nibble_position_w[30] ? 6'd4 : 6'd5)) :
        (nibble_position_w[31] ? (nibble_position_w[30] ? 6'd36 : 6'd37) :
        (nibble_position_w[30] ? 6'd38 : 6'd39));
    (* keep = "true" *) wire [5:0] leading_bit0_tree0_w;
    assign leading_bit0_tree0_w[0] = magnitude_w[65] |
        (nibble_select_w[0] && nibble_position_w[0]) |
        (nibble_select_w[1] && nibble_position_w[2]);
    assign leading_bit0_tree0_w[1] = (nibble_select_w[2] && nibble_position_w[4]) |
        (nibble_select_w[3] && nibble_position_w[6]) |
        (nibble_select_w[4] && nibble_position_w[8]);
    assign leading_bit0_tree0_w[2] = (nibble_select_w[5] && nibble_position_w[10]) |
        (nibble_select_w[6] && nibble_position_w[12]) |
        (nibble_select_w[7] && nibble_position_w[14]);
    assign leading_bit0_tree0_w[3] = (nibble_select_w[8] && nibble_position_w[16]) |
        (nibble_select_w[9] && nibble_position_w[18]) |
        (nibble_select_w[10] && nibble_position_w[20]);
    assign leading_bit0_tree0_w[4] = (nibble_select_w[11] && nibble_position_w[22]) |
        (nibble_select_w[12] && nibble_position_w[24]) |
        (nibble_select_w[13] && nibble_position_w[26]);
    assign leading_bit0_tree0_w[5] = (nibble_select_w[14] && nibble_position_w[28]) |
        (nibble_select_w[15] && nibble_position_w[30]);
    (* keep = "true" *) wire [1:0] leading_bit0_tree1_w;
    assign leading_bit0_tree1_w[0] = leading_bit0_tree0_w[0] |
        leading_bit0_tree0_w[1] |
        leading_bit0_tree0_w[2];
    assign leading_bit0_tree1_w[1] = leading_bit0_tree0_w[3] |
        leading_bit0_tree0_w[4] |
        leading_bit0_tree0_w[5];
    (* keep = "true" *) wire [0:0] leading_bit0_tree2_w;
    assign leading_bit0_tree2_w[0] = leading_bit0_tree1_w[0] |
        leading_bit0_tree1_w[1];
    assign leading_w[0] = leading_bit0_tree2_w[0];
    (* keep = "true" *) wire [5:0] leading_bit1_tree0_w;
    assign leading_bit1_tree0_w[0] = (nibble_select_w[0] && nibble_position_w[1]) |
        (nibble_select_w[1] && nibble_position_w[3]) |
        (nibble_select_w[2] && nibble_position_w[5]);
    assign leading_bit1_tree0_w[1] = (nibble_select_w[3] && nibble_position_w[7]) |
        (nibble_select_w[4] && nibble_position_w[9]) |
        (nibble_select_w[5] && nibble_position_w[11]);
    assign leading_bit1_tree0_w[2] = (nibble_select_w[6] && nibble_position_w[13]) |
        (nibble_select_w[7] && nibble_position_w[15]) |
        (nibble_select_w[8] && nibble_position_w[17]);
    assign leading_bit1_tree0_w[3] = (nibble_select_w[9] && nibble_position_w[19]) |
        (nibble_select_w[10] && nibble_position_w[21]) |
        (nibble_select_w[11] && nibble_position_w[23]);
    assign leading_bit1_tree0_w[4] = (nibble_select_w[12] && nibble_position_w[25]) |
        (nibble_select_w[13] && nibble_position_w[27]) |
        (nibble_select_w[14] && nibble_position_w[29]);
    assign leading_bit1_tree0_w[5] = (nibble_select_w[15] && nibble_position_w[31]);
    (* keep = "true" *) wire [1:0] leading_bit1_tree1_w;
    assign leading_bit1_tree1_w[0] = leading_bit1_tree0_w[0] |
        leading_bit1_tree0_w[1] |
        leading_bit1_tree0_w[2];
    assign leading_bit1_tree1_w[1] = leading_bit1_tree0_w[3] |
        leading_bit1_tree0_w[4] |
        leading_bit1_tree0_w[5];
    (* keep = "true" *) wire [0:0] leading_bit1_tree2_w;
    assign leading_bit1_tree2_w[0] = leading_bit1_tree1_w[0] |
        leading_bit1_tree1_w[1];
    assign leading_w[1] = leading_bit1_tree2_w[0];
    (* keep = "true" *) wire [2:0] leading_bit2_tree0_w;
    assign leading_bit2_tree0_w[0] = nibble_select_w[1] |
        nibble_select_w[3] |
        nibble_select_w[5];
    assign leading_bit2_tree0_w[1] = nibble_select_w[7] |
        nibble_select_w[9] |
        nibble_select_w[11];
    assign leading_bit2_tree0_w[2] = nibble_select_w[13] |
        nibble_select_w[15];
    (* keep = "true" *) wire [0:0] leading_bit2_tree1_w;
    assign leading_bit2_tree1_w[0] = leading_bit2_tree0_w[0] |
        leading_bit2_tree0_w[1] |
        leading_bit2_tree0_w[2];
    assign leading_w[2] = leading_bit2_tree1_w[0];
    (* keep = "true" *) wire [2:0] leading_bit3_tree0_w;
    assign leading_bit3_tree0_w[0] = nibble_select_w[2] |
        nibble_select_w[3] |
        nibble_select_w[6];
    assign leading_bit3_tree0_w[1] = nibble_select_w[7] |
        nibble_select_w[10] |
        nibble_select_w[11];
    assign leading_bit3_tree0_w[2] = nibble_select_w[14] |
        nibble_select_w[15];
    (* keep = "true" *) wire [0:0] leading_bit3_tree1_w;
    assign leading_bit3_tree1_w[0] = leading_bit3_tree0_w[0] |
        leading_bit3_tree0_w[1] |
        leading_bit3_tree0_w[2];
    assign leading_w[3] = leading_bit3_tree1_w[0];
    (* keep = "true" *) wire [2:0] leading_bit4_tree0_w;
    assign leading_bit4_tree0_w[0] = nibble_select_w[4] |
        nibble_select_w[5] |
        nibble_select_w[6];
    assign leading_bit4_tree0_w[1] = nibble_select_w[7] |
        nibble_select_w[12] |
        nibble_select_w[13];
    assign leading_bit4_tree0_w[2] = nibble_select_w[14] |
        nibble_select_w[15];
    (* keep = "true" *) wire [0:0] leading_bit4_tree1_w;
    assign leading_bit4_tree1_w[0] = leading_bit4_tree0_w[0] |
        leading_bit4_tree0_w[1] |
        leading_bit4_tree0_w[2];
    assign leading_w[4] = leading_bit4_tree1_w[0];
    (* keep = "true" *) wire [2:0] leading_bit5_tree0_w;
    assign leading_bit5_tree0_w[0] = nibble_select_w[8] |
        nibble_select_w[9] |
        nibble_select_w[10];
    assign leading_bit5_tree0_w[1] = nibble_select_w[11] |
        nibble_select_w[12] |
        nibble_select_w[13];
    assign leading_bit5_tree0_w[2] = nibble_select_w[14] |
        nibble_select_w[15];
    (* keep = "true" *) wire [0:0] leading_bit5_tree1_w;
    assign leading_bit5_tree1_w[0] = leading_bit5_tree0_w[0] |
        leading_bit5_tree0_w[1] |
        leading_bit5_tree0_w[2];
    assign leading_w[5] = leading_bit5_tree1_w[0];
    assign leading_w[6] = high_w;
    (* keep = "true" *) wire [5:0] shift_bit0_tree0_w;
    assign shift_bit0_tree0_w[0] = (nibble_select_w[0] && nibble_shift_w[0]) |
        (nibble_select_w[1] && nibble_shift_w[6]) |
        (nibble_select_w[2] && nibble_shift_w[12]);
    assign shift_bit0_tree0_w[1] = (nibble_select_w[3] && nibble_shift_w[18]) |
        (nibble_select_w[4] && nibble_shift_w[24]) |
        (nibble_select_w[5] && nibble_shift_w[30]);
    assign shift_bit0_tree0_w[2] = (nibble_select_w[6] && nibble_shift_w[36]) |
        (nibble_select_w[7] && nibble_shift_w[42]) |
        (nibble_select_w[8] && nibble_shift_w[48]);
    assign shift_bit0_tree0_w[3] = (nibble_select_w[9] && nibble_shift_w[54]) |
        (nibble_select_w[10] && nibble_shift_w[60]) |
        (nibble_select_w[11] && nibble_shift_w[66]);
    assign shift_bit0_tree0_w[4] = (nibble_select_w[12] && nibble_shift_w[72]) |
        (nibble_select_w[13] && nibble_shift_w[78]) |
        (nibble_select_w[14] && nibble_shift_w[84]);
    assign shift_bit0_tree0_w[5] = (nibble_select_w[15] && nibble_shift_w[90]) |
        (high_w && !magnitude_w[65]);
    (* keep = "true" *) wire [1:0] shift_bit0_tree1_w;
    assign shift_bit0_tree1_w[0] = shift_bit0_tree0_w[0] |
        shift_bit0_tree0_w[1] |
        shift_bit0_tree0_w[2];
    assign shift_bit0_tree1_w[1] = shift_bit0_tree0_w[3] |
        shift_bit0_tree0_w[4] |
        shift_bit0_tree0_w[5];
    (* keep = "true" *) wire [0:0] shift_bit0_tree2_w;
    assign shift_bit0_tree2_w[0] = shift_bit0_tree1_w[0] |
        shift_bit0_tree1_w[1];
    assign shift_w[0] = shift_bit0_tree2_w[0];
    (* keep = "true" *) wire [5:0] shift_bit1_tree0_w;
    assign shift_bit1_tree0_w[0] = (nibble_select_w[0] && nibble_shift_w[1]) |
        (nibble_select_w[1] && nibble_shift_w[7]) |
        (nibble_select_w[2] && nibble_shift_w[13]);
    assign shift_bit1_tree0_w[1] = (nibble_select_w[3] && nibble_shift_w[19]) |
        (nibble_select_w[4] && nibble_shift_w[25]) |
        (nibble_select_w[5] && nibble_shift_w[31]);
    assign shift_bit1_tree0_w[2] = (nibble_select_w[6] && nibble_shift_w[37]) |
        (nibble_select_w[7] && nibble_shift_w[43]) |
        (nibble_select_w[8] && nibble_shift_w[49]);
    assign shift_bit1_tree0_w[3] = (nibble_select_w[9] && nibble_shift_w[55]) |
        (nibble_select_w[10] && nibble_shift_w[61]) |
        (nibble_select_w[11] && nibble_shift_w[67]);
    assign shift_bit1_tree0_w[4] = (nibble_select_w[12] && nibble_shift_w[73]) |
        (nibble_select_w[13] && nibble_shift_w[79]) |
        (nibble_select_w[14] && nibble_shift_w[85]);
    assign shift_bit1_tree0_w[5] = (nibble_select_w[15] && nibble_shift_w[91]);
    (* keep = "true" *) wire [1:0] shift_bit1_tree1_w;
    assign shift_bit1_tree1_w[0] = shift_bit1_tree0_w[0] |
        shift_bit1_tree0_w[1] |
        shift_bit1_tree0_w[2];
    assign shift_bit1_tree1_w[1] = shift_bit1_tree0_w[3] |
        shift_bit1_tree0_w[4] |
        shift_bit1_tree0_w[5];
    (* keep = "true" *) wire [0:0] shift_bit1_tree2_w;
    assign shift_bit1_tree2_w[0] = shift_bit1_tree1_w[0] |
        shift_bit1_tree1_w[1];
    assign shift_w[1] = shift_bit1_tree2_w[0];
    (* keep = "true" *) wire [5:0] shift_bit2_tree0_w;
    assign shift_bit2_tree0_w[0] = (nibble_select_w[0] && nibble_shift_w[2]) |
        (nibble_select_w[1] && nibble_shift_w[8]) |
        (nibble_select_w[2] && nibble_shift_w[14]);
    assign shift_bit2_tree0_w[1] = (nibble_select_w[3] && nibble_shift_w[20]) |
        (nibble_select_w[4] && nibble_shift_w[26]) |
        (nibble_select_w[5] && nibble_shift_w[32]);
    assign shift_bit2_tree0_w[2] = (nibble_select_w[6] && nibble_shift_w[38]) |
        (nibble_select_w[7] && nibble_shift_w[44]) |
        (nibble_select_w[8] && nibble_shift_w[50]);
    assign shift_bit2_tree0_w[3] = (nibble_select_w[9] && nibble_shift_w[56]) |
        (nibble_select_w[10] && nibble_shift_w[62]) |
        (nibble_select_w[11] && nibble_shift_w[68]);
    assign shift_bit2_tree0_w[4] = (nibble_select_w[12] && nibble_shift_w[74]) |
        (nibble_select_w[13] && nibble_shift_w[80]) |
        (nibble_select_w[14] && nibble_shift_w[86]);
    assign shift_bit2_tree0_w[5] = (nibble_select_w[15] && nibble_shift_w[92]);
    (* keep = "true" *) wire [1:0] shift_bit2_tree1_w;
    assign shift_bit2_tree1_w[0] = shift_bit2_tree0_w[0] |
        shift_bit2_tree0_w[1] |
        shift_bit2_tree0_w[2];
    assign shift_bit2_tree1_w[1] = shift_bit2_tree0_w[3] |
        shift_bit2_tree0_w[4] |
        shift_bit2_tree0_w[5];
    (* keep = "true" *) wire [0:0] shift_bit2_tree2_w;
    assign shift_bit2_tree2_w[0] = shift_bit2_tree1_w[0] |
        shift_bit2_tree1_w[1];
    assign shift_w[2] = shift_bit2_tree2_w[0];
    (* keep = "true" *) wire [5:0] shift_bit3_tree0_w;
    assign shift_bit3_tree0_w[0] = (nibble_select_w[0] && nibble_shift_w[3]) |
        (nibble_select_w[1] && nibble_shift_w[9]) |
        (nibble_select_w[2] && nibble_shift_w[15]);
    assign shift_bit3_tree0_w[1] = (nibble_select_w[3] && nibble_shift_w[21]) |
        (nibble_select_w[4] && nibble_shift_w[27]) |
        (nibble_select_w[5] && nibble_shift_w[33]);
    assign shift_bit3_tree0_w[2] = (nibble_select_w[6] && nibble_shift_w[39]) |
        (nibble_select_w[7] && nibble_shift_w[45]) |
        (nibble_select_w[8] && nibble_shift_w[51]);
    assign shift_bit3_tree0_w[3] = (nibble_select_w[9] && nibble_shift_w[57]) |
        (nibble_select_w[10] && nibble_shift_w[63]) |
        (nibble_select_w[11] && nibble_shift_w[69]);
    assign shift_bit3_tree0_w[4] = (nibble_select_w[12] && nibble_shift_w[75]) |
        (nibble_select_w[13] && nibble_shift_w[81]) |
        (nibble_select_w[14] && nibble_shift_w[87]);
    assign shift_bit3_tree0_w[5] = (nibble_select_w[15] && nibble_shift_w[93]);
    (* keep = "true" *) wire [1:0] shift_bit3_tree1_w;
    assign shift_bit3_tree1_w[0] = shift_bit3_tree0_w[0] |
        shift_bit3_tree0_w[1] |
        shift_bit3_tree0_w[2];
    assign shift_bit3_tree1_w[1] = shift_bit3_tree0_w[3] |
        shift_bit3_tree0_w[4] |
        shift_bit3_tree0_w[5];
    (* keep = "true" *) wire [0:0] shift_bit3_tree2_w;
    assign shift_bit3_tree2_w[0] = shift_bit3_tree1_w[0] |
        shift_bit3_tree1_w[1];
    assign shift_w[3] = shift_bit3_tree2_w[0];
    (* keep = "true" *) wire [5:0] shift_bit4_tree0_w;
    assign shift_bit4_tree0_w[0] = (nibble_select_w[0] && nibble_shift_w[4]) |
        (nibble_select_w[1] && nibble_shift_w[10]) |
        (nibble_select_w[2] && nibble_shift_w[16]);
    assign shift_bit4_tree0_w[1] = (nibble_select_w[3] && nibble_shift_w[22]) |
        (nibble_select_w[4] && nibble_shift_w[28]) |
        (nibble_select_w[5] && nibble_shift_w[34]);
    assign shift_bit4_tree0_w[2] = (nibble_select_w[6] && nibble_shift_w[40]) |
        (nibble_select_w[7] && nibble_shift_w[46]) |
        (nibble_select_w[8] && nibble_shift_w[52]);
    assign shift_bit4_tree0_w[3] = (nibble_select_w[9] && nibble_shift_w[58]) |
        (nibble_select_w[10] && nibble_shift_w[64]) |
        (nibble_select_w[11] && nibble_shift_w[70]);
    assign shift_bit4_tree0_w[4] = (nibble_select_w[12] && nibble_shift_w[76]) |
        (nibble_select_w[13] && nibble_shift_w[82]) |
        (nibble_select_w[14] && nibble_shift_w[88]);
    assign shift_bit4_tree0_w[5] = (nibble_select_w[15] && nibble_shift_w[94]);
    (* keep = "true" *) wire [1:0] shift_bit4_tree1_w;
    assign shift_bit4_tree1_w[0] = shift_bit4_tree0_w[0] |
        shift_bit4_tree0_w[1] |
        shift_bit4_tree0_w[2];
    assign shift_bit4_tree1_w[1] = shift_bit4_tree0_w[3] |
        shift_bit4_tree0_w[4] |
        shift_bit4_tree0_w[5];
    (* keep = "true" *) wire [0:0] shift_bit4_tree2_w;
    assign shift_bit4_tree2_w[0] = shift_bit4_tree1_w[0] |
        shift_bit4_tree1_w[1];
    assign shift_w[4] = shift_bit4_tree2_w[0];
    (* keep = "true" *) wire [5:0] shift_bit5_tree0_w;
    assign shift_bit5_tree0_w[0] = (nibble_select_w[0] && nibble_shift_w[5]) |
        (nibble_select_w[1] && nibble_shift_w[11]) |
        (nibble_select_w[2] && nibble_shift_w[17]);
    assign shift_bit5_tree0_w[1] = (nibble_select_w[3] && nibble_shift_w[23]) |
        (nibble_select_w[4] && nibble_shift_w[29]) |
        (nibble_select_w[5] && nibble_shift_w[35]);
    assign shift_bit5_tree0_w[2] = (nibble_select_w[6] && nibble_shift_w[41]) |
        (nibble_select_w[7] && nibble_shift_w[47]) |
        (nibble_select_w[8] && nibble_shift_w[53]);
    assign shift_bit5_tree0_w[3] = (nibble_select_w[9] && nibble_shift_w[59]) |
        (nibble_select_w[10] && nibble_shift_w[65]) |
        (nibble_select_w[11] && nibble_shift_w[71]);
    assign shift_bit5_tree0_w[4] = (nibble_select_w[12] && nibble_shift_w[77]) |
        (nibble_select_w[13] && nibble_shift_w[83]) |
        (nibble_select_w[14] && nibble_shift_w[89]);
    assign shift_bit5_tree0_w[5] = (nibble_select_w[15] && nibble_shift_w[95]);
    (* keep = "true" *) wire [1:0] shift_bit5_tree1_w;
    assign shift_bit5_tree1_w[0] = shift_bit5_tree0_w[0] |
        shift_bit5_tree0_w[1] |
        shift_bit5_tree0_w[2];
    assign shift_bit5_tree1_w[1] = shift_bit5_tree0_w[3] |
        shift_bit5_tree0_w[4] |
        shift_bit5_tree0_w[5];
    (* keep = "true" *) wire [0:0] shift_bit5_tree2_w;
    assign shift_bit5_tree2_w[0] = shift_bit5_tree1_w[0] |
        shift_bit5_tree1_w[1];
    assign shift_w[5] = shift_bit5_tree2_w[0];
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
            shift_r <= shift_w;
            exponent_r <= exponent_i - 10'd17;
            leading_r <= leading_w;
            sign_r <= sign_i;
            shifted_r <= shift_16_w;
            shifted_zero_r <= zero_r;
            shifted_exponent_r <= exponent_r + {3'b0, leading_r};
            shifted_sign_r <= sign_r;
            result_r <= shifted_zero_r ? 29'b0 :
                {shifted_exponent_r + {9'b0, rounded_w[18]}, shifted_sign_r,
                rounded_w[18] ? rounded_w[18:1] : rounded_w[17:0]};
        end
    end
endmodule
