// File: edrv32_gpu_texture.v
// Spec: gpu-spec 2.6, 2.12; GPU microarchitecture 4.2, 4.4, 4.6, 4.8.
// Description: Per-lane LOD, ordered bank scheduling, palette expansion, filtering
// and vertex modulation. Reserved contexts retain all in-flight RAM results.
// Clock: clk_gpu.
module edrv32_gpu_texture (
    // Clock and command lifetime.
    input wire clk_i,
    input wire rst_n_i,
    input wire finish_i,
    input wire stop_i,
    output reg unit_done_o,

    // Frozen render state snapshot.
    input wire render_state_valid_i,
    output wire render_state_ready_o,
    input wire [255:0] render_state_tex_i,
    input wire [255:0] render_state_pixel_i,
    input wire [255:0] render_state_target_i,
    input wire render_state_wide_i,

    // Four ordered pixels from perspective.
    input wire sample_valid_i,
    output wire sample_ready_o,
    input wire [15:0] sample_x_i,
    input wire [15:0] sample_y_i,
    input wire [3:0] sample_mask_i,
    input wire sample_quad_i,
    input wire [127:0] sample_u_i,
    input wire [127:0] sample_v_i,
    input wire [383:0] sample_span_i,
    input wire [63:0] sample_depth_i,
    input wire [95:0] sample_color_i,
    input wire [3:0] sample_palette_i,
    input wire [7:0] sample_alpha_i,

    // Ordered group after filtering and shading.
    output wire shaded_valid_o,
    input wire shaded_ready_i,
    output wire [15:0] shaded_x_o,
    output wire [15:0] shaded_y_o,
    output wire [3:0] shaded_mask_o,
    output wire [63:0] shaded_depth_o,
    output wire [95:0] shaded_color_o,
    output wire [31:0] shaded_alpha_o,

    // Internal RAM ports: bank-major, two ports per bank, five-cycle reads.
    output wire [7:0] texture_read_en_o,
    output reg [119:0] texture_read_addr_o,
    input wire [127:0] texture_read_data_i,

    // Internal full/current palette ports, four-cycle reads.
    output wire full_read_en_o,
    output reg [47:0] full_read_idx_o,
    input wire [79:0] full_read_data_i,
    output wire current_read_en_o,
    output reg [63:0] current_read_idx_o,
    input wire [159:0] current_read_data_i,
    output wire perf_texture_stall_o
);
    // The snapshot fields used by this unit are SET_TEX bits [91:64], [49:37].
    // The other frozen fields belong to raster/pixel and are deliberately unused.
    wire unused_state_w;
    assign unused_state_w = ^{render_state_pixel_i, render_state_target_i,
                                render_state_wide_i, render_state_tex_i[255:92],
                                render_state_tex_i[63:50], render_state_tex_i[36:0]};
    reg [3:0] log2_w_r;
    reg [3:0] log2_h_r;
    reg [1:0] format_r;
    reg [3:0] levels_r;
    reg [3:0] group_r;
    reg [1:0] mode_r;
    reg signed [7:0] bias_r;
    reg [17:0] offset_r;
    reg [5:0] allocate_r;
    reg [5:0] schedule_r;
    reg [5:0] retire_r;
    wire [5:0] occupancy_w;
    wire accept_w;
    wire retire_w;
    wire schedule_valid_w;
    wire [4:0] schedule_slot_w;
    reg [3:0] lod_ready_r [0:31];
    reg [3:0] completed_r [0:31];
    reg [15:0] x_r [0:31];
    reg [15:0] y_r [0:31];
    reg [3:0] mask_r [0:31];
    reg [63:0] depth_r [0:31];
    reg [95:0] color_r [0:31];
    reg [7:0] alpha_r [0:31];
    reg quad_r [0:31];
    reg [3:0] palette_r [0:31];
    reg [127:0] u_r [0:31];
    reg [127:0] v_r [0:31];
    reg [47:0] lod_r [0:31];
    reg [95:0] result_color_r [0:31];
    reg [31:0] result_alpha_r [0:31];
    reg [3:0] result_mask_r [0:31];
    reg [1:0] batch_r;
    reg [3:0] nearest_pending_r;
    assign occupancy_w = allocate_r - retire_r;
    assign sample_ready_o = occupancy_w < 6'd32 && !stop_i;
    assign accept_w = sample_valid_i && sample_ready_o;
    assign render_state_ready_o = occupancy_w == 0;
    assign shaded_valid_o = occupancy_w != 0 && completed_r[retire_r[4:0]] == 4'hf
                            && !stop_i;
    assign retire_w = shaded_valid_o && shaded_ready_i;
    assign shaded_x_o = x_r[retire_r[4:0]];
    assign shaded_y_o = y_r[retire_r[4:0]];
    assign shaded_mask_o = result_mask_r[retire_r[4:0]];
    assign shaded_depth_o = depth_r[retire_r[4:0]];
    assign shaded_color_o = result_color_r[retire_r[4:0]];
    assign shaded_alpha_o = result_alpha_r[retire_r[4:0]];
    assign schedule_slot_w = schedule_r[4:0];
    assign schedule_valid_w = schedule_r != allocate_r
                                && lod_ready_r[schedule_slot_w] == 4'hf && !stop_i;

    function [8:0] log_fraction;
        input [7:0] index_i;
        begin
            case (index_i)
                8'd0: log_fraction = 9'd0;
                8'd1: log_fraction = 9'd1;
                8'd2: log_fraction = 9'd3;
                8'd3: log_fraction = 9'd4;
                8'd4: log_fraction = 9'd6;
                8'd5: log_fraction = 9'd7;
                8'd6: log_fraction = 9'd9;
                8'd7: log_fraction = 9'd10;
                8'd8: log_fraction = 9'd11;
                8'd9: log_fraction = 9'd13;
                8'd10: log_fraction = 9'd14;
                8'd11: log_fraction = 9'd16;
                8'd12: log_fraction = 9'd17;
                8'd13: log_fraction = 9'd18;
                8'd14: log_fraction = 9'd20;
                8'd15: log_fraction = 9'd21;
                8'd16: log_fraction = 9'd22;
                8'd17: log_fraction = 9'd24;
                8'd18: log_fraction = 9'd25;
                8'd19: log_fraction = 9'd26;
                8'd20: log_fraction = 9'd28;
                8'd21: log_fraction = 9'd29;
                8'd22: log_fraction = 9'd30;
                8'd23: log_fraction = 9'd32;
                8'd24: log_fraction = 9'd33;
                8'd25: log_fraction = 9'd34;
                8'd26: log_fraction = 9'd36;
                8'd27: log_fraction = 9'd37;
                8'd28: log_fraction = 9'd38;
                8'd29: log_fraction = 9'd40;
                8'd30: log_fraction = 9'd41;
                8'd31: log_fraction = 9'd42;
                8'd32: log_fraction = 9'd44;
                8'd33: log_fraction = 9'd45;
                8'd34: log_fraction = 9'd46;
                8'd35: log_fraction = 9'd47;
                8'd36: log_fraction = 9'd49;
                8'd37: log_fraction = 9'd50;
                8'd38: log_fraction = 9'd51;
                8'd39: log_fraction = 9'd52;
                8'd40: log_fraction = 9'd54;
                8'd41: log_fraction = 9'd55;
                8'd42: log_fraction = 9'd56;
                8'd43: log_fraction = 9'd57;
                8'd44: log_fraction = 9'd59;
                8'd45: log_fraction = 9'd60;
                8'd46: log_fraction = 9'd61;
                8'd47: log_fraction = 9'd62;
                8'd48: log_fraction = 9'd63;
                8'd49: log_fraction = 9'd65;
                8'd50: log_fraction = 9'd66;
                8'd51: log_fraction = 9'd67;
                8'd52: log_fraction = 9'd68;
                8'd53: log_fraction = 9'd69;
                8'd54: log_fraction = 9'd71;
                8'd55: log_fraction = 9'd72;
                8'd56: log_fraction = 9'd73;
                8'd57: log_fraction = 9'd74;
                8'd58: log_fraction = 9'd75;
                8'd59: log_fraction = 9'd77;
                8'd60: log_fraction = 9'd78;
                8'd61: log_fraction = 9'd79;
                8'd62: log_fraction = 9'd80;
                8'd63: log_fraction = 9'd81;
                8'd64: log_fraction = 9'd82;
                8'd65: log_fraction = 9'd84;
                8'd66: log_fraction = 9'd85;
                8'd67: log_fraction = 9'd86;
                8'd68: log_fraction = 9'd87;
                8'd69: log_fraction = 9'd88;
                8'd70: log_fraction = 9'd89;
                8'd71: log_fraction = 9'd90;
                8'd72: log_fraction = 9'd92;
                8'd73: log_fraction = 9'd93;
                8'd74: log_fraction = 9'd94;
                8'd75: log_fraction = 9'd95;
                8'd76: log_fraction = 9'd96;
                8'd77: log_fraction = 9'd97;
                8'd78: log_fraction = 9'd98;
                8'd79: log_fraction = 9'd99;
                8'd80: log_fraction = 9'd100;
                8'd81: log_fraction = 9'd102;
                8'd82: log_fraction = 9'd103;
                8'd83: log_fraction = 9'd104;
                8'd84: log_fraction = 9'd105;
                8'd85: log_fraction = 9'd106;
                8'd86: log_fraction = 9'd107;
                8'd87: log_fraction = 9'd108;
                8'd88: log_fraction = 9'd109;
                8'd89: log_fraction = 9'd110;
                8'd90: log_fraction = 9'd111;
                8'd91: log_fraction = 9'd112;
                8'd92: log_fraction = 9'd113;
                8'd93: log_fraction = 9'd114;
                8'd94: log_fraction = 9'd116;
                8'd95: log_fraction = 9'd117;
                8'd96: log_fraction = 9'd118;
                8'd97: log_fraction = 9'd119;
                8'd98: log_fraction = 9'd120;
                8'd99: log_fraction = 9'd121;
                8'd100: log_fraction = 9'd122;
                8'd101: log_fraction = 9'd123;
                8'd102: log_fraction = 9'd124;
                8'd103: log_fraction = 9'd125;
                8'd104: log_fraction = 9'd126;
                8'd105: log_fraction = 9'd127;
                8'd106: log_fraction = 9'd128;
                8'd107: log_fraction = 9'd129;
                8'd108: log_fraction = 9'd130;
                8'd109: log_fraction = 9'd131;
                8'd110: log_fraction = 9'd132;
                8'd111: log_fraction = 9'd133;
                8'd112: log_fraction = 9'd134;
                8'd113: log_fraction = 9'd135;
                8'd114: log_fraction = 9'd136;
                8'd115: log_fraction = 9'd137;
                8'd116: log_fraction = 9'd138;
                8'd117: log_fraction = 9'd139;
                8'd118: log_fraction = 9'd140;
                8'd119: log_fraction = 9'd141;
                8'd120: log_fraction = 9'd142;
                8'd121: log_fraction = 9'd143;
                8'd122: log_fraction = 9'd144;
                8'd123: log_fraction = 9'd145;
                8'd124: log_fraction = 9'd146;
                8'd125: log_fraction = 9'd147;
                8'd126: log_fraction = 9'd148;
                8'd127: log_fraction = 9'd149;
                8'd128: log_fraction = 9'd150;
                8'd129: log_fraction = 9'd151;
                8'd130: log_fraction = 9'd152;
                8'd131: log_fraction = 9'd153;
                8'd132: log_fraction = 9'd154;
                8'd133: log_fraction = 9'd155;
                8'd134: log_fraction = 9'd155;
                8'd135: log_fraction = 9'd156;
                8'd136: log_fraction = 9'd157;
                8'd137: log_fraction = 9'd158;
                8'd138: log_fraction = 9'd159;
                8'd139: log_fraction = 9'd160;
                8'd140: log_fraction = 9'd161;
                8'd141: log_fraction = 9'd162;
                8'd142: log_fraction = 9'd163;
                8'd143: log_fraction = 9'd164;
                8'd144: log_fraction = 9'd165;
                8'd145: log_fraction = 9'd166;
                8'd146: log_fraction = 9'd167;
                8'd147: log_fraction = 9'd168;
                8'd148: log_fraction = 9'd169;
                8'd149: log_fraction = 9'd169;
                8'd150: log_fraction = 9'd170;
                8'd151: log_fraction = 9'd171;
                8'd152: log_fraction = 9'd172;
                8'd153: log_fraction = 9'd173;
                8'd154: log_fraction = 9'd174;
                8'd155: log_fraction = 9'd175;
                8'd156: log_fraction = 9'd176;
                8'd157: log_fraction = 9'd177;
                8'd158: log_fraction = 9'd178;
                8'd159: log_fraction = 9'd178;
                8'd160: log_fraction = 9'd179;
                8'd161: log_fraction = 9'd180;
                8'd162: log_fraction = 9'd181;
                8'd163: log_fraction = 9'd182;
                8'd164: log_fraction = 9'd183;
                8'd165: log_fraction = 9'd184;
                8'd166: log_fraction = 9'd185;
                8'd167: log_fraction = 9'd185;
                8'd168: log_fraction = 9'd186;
                8'd169: log_fraction = 9'd187;
                8'd170: log_fraction = 9'd188;
                8'd171: log_fraction = 9'd189;
                8'd172: log_fraction = 9'd190;
                8'd173: log_fraction = 9'd191;
                8'd174: log_fraction = 9'd192;
                8'd175: log_fraction = 9'd192;
                8'd176: log_fraction = 9'd193;
                8'd177: log_fraction = 9'd194;
                8'd178: log_fraction = 9'd195;
                8'd179: log_fraction = 9'd196;
                8'd180: log_fraction = 9'd197;
                8'd181: log_fraction = 9'd198;
                8'd182: log_fraction = 9'd198;
                8'd183: log_fraction = 9'd199;
                8'd184: log_fraction = 9'd200;
                8'd185: log_fraction = 9'd201;
                8'd186: log_fraction = 9'd202;
                8'd187: log_fraction = 9'd203;
                8'd188: log_fraction = 9'd203;
                8'd189: log_fraction = 9'd204;
                8'd190: log_fraction = 9'd205;
                8'd191: log_fraction = 9'd206;
                8'd192: log_fraction = 9'd207;
                8'd193: log_fraction = 9'd208;
                8'd194: log_fraction = 9'd208;
                8'd195: log_fraction = 9'd209;
                8'd196: log_fraction = 9'd210;
                8'd197: log_fraction = 9'd211;
                8'd198: log_fraction = 9'd212;
                8'd199: log_fraction = 9'd212;
                8'd200: log_fraction = 9'd213;
                8'd201: log_fraction = 9'd214;
                8'd202: log_fraction = 9'd215;
                8'd203: log_fraction = 9'd216;
                8'd204: log_fraction = 9'd216;
                8'd205: log_fraction = 9'd217;
                8'd206: log_fraction = 9'd218;
                8'd207: log_fraction = 9'd219;
                8'd208: log_fraction = 9'd220;
                8'd209: log_fraction = 9'd220;
                8'd210: log_fraction = 9'd221;
                8'd211: log_fraction = 9'd222;
                8'd212: log_fraction = 9'd223;
                8'd213: log_fraction = 9'd224;
                8'd214: log_fraction = 9'd224;
                8'd215: log_fraction = 9'd225;
                8'd216: log_fraction = 9'd226;
                8'd217: log_fraction = 9'd227;
                8'd218: log_fraction = 9'd228;
                8'd219: log_fraction = 9'd228;
                8'd220: log_fraction = 9'd229;
                8'd221: log_fraction = 9'd230;
                8'd222: log_fraction = 9'd231;
                8'd223: log_fraction = 9'd231;
                8'd224: log_fraction = 9'd232;
                8'd225: log_fraction = 9'd233;
                8'd226: log_fraction = 9'd234;
                8'd227: log_fraction = 9'd234;
                8'd228: log_fraction = 9'd235;
                8'd229: log_fraction = 9'd236;
                8'd230: log_fraction = 9'd237;
                8'd231: log_fraction = 9'd238;
                8'd232: log_fraction = 9'd238;
                8'd233: log_fraction = 9'd239;
                8'd234: log_fraction = 9'd240;
                8'd235: log_fraction = 9'd241;
                8'd236: log_fraction = 9'd241;
                8'd237: log_fraction = 9'd242;
                8'd238: log_fraction = 9'd243;
                8'd239: log_fraction = 9'd244;
                8'd240: log_fraction = 9'd244;
                8'd241: log_fraction = 9'd245;
                8'd242: log_fraction = 9'd246;
                8'd243: log_fraction = 9'd247;
                8'd244: log_fraction = 9'd247;
                8'd245: log_fraction = 9'd248;
                8'd246: log_fraction = 9'd249;
                8'd247: log_fraction = 9'd249;
                8'd248: log_fraction = 9'd250;
                8'd249: log_fraction = 9'd251;
                8'd250: log_fraction = 9'd252;
                8'd251: log_fraction = 9'd252;
                8'd252: log_fraction = 9'd253;
                8'd253: log_fraction = 9'd254;
                8'd254: log_fraction = 9'd255;
                8'd255: log_fraction = 9'd255;
                default: log_fraction = 9'd0;
            endcase
        end
    endfunction
    function [7:0] divide_255;
        input [15:0] product_i;
        reg [16:0] temp;
        reg [17:0] total;
        reg unused_total;
        begin
            temp = {1'b0, product_i} + 17'd128;
            total = {1'b0, temp} + {9'b0, temp[16:8]};
            divide_255 = total[15:8];
            unused_total = ^{total[17:16], total[7:0]};
        end
    endfunction
    function [31:0] expand_rgba;
        input [15:0] rgb_i;
        input [7:0] alpha_i;
        begin
            expand_rgba = {alpha_i, rgb_i[4:0], rgb_i[4:2], rgb_i[10:5], rgb_i[10:9],
                            rgb_i[15:11], rgb_i[15:13]};
        end
    endfunction
    // h[1:0] selects the bank; h>>2 selects the row. Small levels keep padding.
    function [20:0] texel_address;
        input signed [31:0] x_i;
        input signed [31:0] y_i;
        input [3:0] level_i;
        reg [31:0] width_value;
        reg [31:0] height_value;
        reg [31:0] blocks_x;
        reg [31:0] blocks_y;
        reg [31:0] block_x;
        reg [31:0] block_y;
        reg [31:0] wrapped_x;
        reg [31:0] wrapped_y;
        reg [31:0] halfword;
        reg [3:0] subword;
        integer k;
        begin
            halfword = {15'b0, offset_r[17:1]};
            width_value = 32'd1 << log2_w_r;
            height_value = 32'd1 << log2_h_r;
            blocks_x = 0;
            blocks_y = 0;
            block_x = 0;
            block_y = 0;
            wrapped_x = 0;
            wrapped_y = 0;
            subword = 0;
            for (k = 0; k < 9; k = k + 1) begin
                blocks_x = format_r == 2 ? width_value : (width_value + 1) >> 1;
                blocks_y = format_r == 0 ? (height_value + 1) >> 1 : height_value;
                if (k < {28'b0, level_i}) begin
                    halfword = halfword + 4 * ((blocks_x + 1) >> 1)
                                                * ((blocks_y + 1) >> 1);
                    if (width_value > 1) begin
                        width_value = width_value >> 1;
                    end
                    if (height_value > 1) begin
                        height_value = height_value >> 1;
                    end
                end
            end
            blocks_x = format_r == 2 ? width_value : (width_value + 1) >> 1;
            wrapped_x = $unsigned(x_i) & (width_value - 1);
            wrapped_y = $unsigned(y_i) & (height_value - 1);
            block_x = format_r == 2 ? wrapped_x : wrapped_x >> 1;
            block_y = format_r == 0 ? wrapped_y >> 1 : wrapped_y;
            halfword = halfword + 4 * ((block_y >> 1) * ((blocks_x + 1) >> 1)
                                        + (block_x >> 1))
                        + (block_x & 1) + 2 * (block_y & 1);
            if (format_r == 0) begin
                subword = {wrapped_y[0], wrapped_x[0], 2'b0};
            end else if (format_r == 1) begin
                subword = {wrapped_x[0], 3'b0};
            end
            texel_address = {subword, halfword[16:0]};
        end
    endfunction

    // Nine-stage LOD path: seven leading-one normalization decisions, ROM, clamp.
    reg [8:0] lod_valid_r;
    reg [4:0] lod_slot_r [0:8];
    genvar lane;
    generate
        for (lane = 0; lane < 4; lane = lane + 1) begin : g_lod
            reg [95:0] normalized_r [0:6];
            reg [6:0] shift_r [0:6];
            reg zero_r [0:6];
            reg signed [15:0] logarithm_r;
            wire signed [15:0] biased_w;
            wire signed [15:0] maximum_w;
            wire [11:0] clamped_w;
            assign biased_w = logarithm_r + ($signed({{8{bias_r[7]}}, bias_r}) <<< 4);
            assign maximum_w = $signed({4'b0, levels_r - 4'd1, 8'b0});
            assign clamped_w = biased_w < 0 ? 12'd0 :
                                biased_w > maximum_w ? maximum_w[11:0] : biased_w[11:0];
            always @(posedge clk_i) begin
                normalized_r[0] <= sample_span_i[lane*96+48 +: 48] == 0
                                    ? sample_span_i[lane*96 +: 96] << 48
                                    : sample_span_i[lane*96 +: 96];
                shift_r[0] <= sample_span_i[lane*96+48 +: 48] == 0 ? 7'd48 : 7'd0;
                zero_r[0] <= sample_span_i[lane*96 +: 96] == 0;
                logarithm_r <= zero_r[6] ? 16'sd0 :
                    (16'sd79 - $signed({9'b0, shift_r[6]})) * 16'sd256
                    + $signed({7'b0, log_fraction(normalized_r[6][94:87])});
                if (lod_valid_r[7]) begin
                    lod_r[lod_slot_r[7]][lane*12 +: 12] <= clamped_w;
                end
            end
            always @(posedge clk_i) begin
                normalized_r[1] <= normalized_r[0][95:72] == 0
                                        ? normalized_r[0] << 24 : normalized_r[0];
                shift_r[1] <= shift_r[0]
                                + (normalized_r[0][95:72] == 0 ? 7'd24 : 7'd0);
                zero_r[1] <= zero_r[0];
            end
            always @(posedge clk_i) begin
                normalized_r[2] <= normalized_r[1][95:84] == 0
                                        ? normalized_r[1] << 12 : normalized_r[1];
                shift_r[2] <= shift_r[1]
                                + (normalized_r[1][95:84] == 0 ? 7'd12 : 7'd0);
                zero_r[2] <= zero_r[1];
            end
            always @(posedge clk_i) begin
                normalized_r[3] <= normalized_r[2][95:90] == 0
                                        ? normalized_r[2] << 6 : normalized_r[2];
                shift_r[3] <= shift_r[2]
                                + (normalized_r[2][95:90] == 0 ? 7'd6 : 7'd0);
                zero_r[3] <= zero_r[2];
            end
            always @(posedge clk_i) begin
                normalized_r[4] <= normalized_r[3][95:93] == 0
                                        ? normalized_r[3] << 3 : normalized_r[3];
                shift_r[4] <= shift_r[3]
                                + (normalized_r[3][95:93] == 0 ? 7'd3 : 7'd0);
                zero_r[4] <= zero_r[3];
            end
            always @(posedge clk_i) begin
                normalized_r[5] <= normalized_r[4][95:94] == 0
                                        ? normalized_r[4] << 2 : normalized_r[4];
                shift_r[5] <= shift_r[4]
                                + (normalized_r[4][95:94] == 0 ? 7'd2 : 7'd0);
                zero_r[5] <= zero_r[4];
            end
            always @(posedge clk_i) begin
                normalized_r[6] <= normalized_r[5][95:95] == 0
                                        ? normalized_r[5] << 1 : normalized_r[5];
                shift_r[6] <= shift_r[5]
                                + (normalized_r[5][95:95] == 0 ? 7'd1 : 7'd0);
                zero_r[6] <= zero_r[5];
            end
        end
    endgenerate

    // One launch holds up to eight taps. Equal words in each bank share a read.
    reg [7:0] port_en_w;
    reg [119:0] port_row_w;
    reg [23:0] tap_port_w;
    reg [31:0] tap_subword_w;
    reg [135:0] tap_weight_w;
    reg [3:0] lane_done_w;
    reg [3:0] pending_w;
    reg [1:0] launch_mode_w;
    reg [1:0] launch_lane_w;
    reg [7:0] launch_fraction_w;
    reg group_issued_w;
    reg [20:0] tap_address_w [0:7];
    integer tap;
    integer bank_idx;
    integer port_idx;
    integer match_idx;
    integer pixel_idx;
    integer tap_level;
    integer tap_x;
    integer tap_y;
    integer fraction_x;
    integer fraction_y;
    integer weight;
    integer lod_value;
    reg signed [31:0] scaled_u_w;
    reg signed [31:0] scaled_v_w;
    reg [11:0] lane_lod_w;
    always @(*) begin
        port_en_w = 0;
        port_row_w = 0;
        tap_port_w = 0;
        tap_subword_w = 0;
        tap_weight_w = 0;
        lane_done_w = 0;
        pending_w = nearest_pending_r;
        launch_mode_w = quad_r[schedule_slot_w] ? 2'b0 : mode_r;
        launch_lane_w = launch_mode_w == 1 ? {batch_r[0], 1'b0} : batch_r;
        launch_fraction_w = 0;
        group_issued_w = 0;
        bank_idx = 0;
        port_idx = 0;
        match_idx = 0;
        pixel_idx = 0;
        tap_level = 0;
        tap_x = 0;
        tap_y = 0;
        fraction_x = 0;
        fraction_y = 0;
        weight = 0;
        lod_value = 0;
        scaled_u_w = 0;
        scaled_v_w = 0;
        lane_lod_w = 0;
        for (tap = 0; tap < 8; tap = tap + 1) begin
            tap_address_w[tap] = 0;
            if (launch_mode_w == 0) begin
                pixel_idx = tap % 4;
            end else if (launch_mode_w == 1) begin
                pixel_idx = {30'b0, launch_lane_w} + tap / 4;
            end else begin
                pixel_idx = {30'b0, launch_lane_w};
            end
            lane_lod_w = quad_r[schedule_slot_w] ? 12'b0
                            : lod_r[schedule_slot_w][pixel_idx*12 +: 12];
            lod_value = {20'b0, lane_lod_w};
            tap_level = lod_value >> 8;
            if (launch_mode_w == 2 && tap >= 4 && tap_level < {28'b0, levels_r}-1) begin
                tap_level = tap_level + 1;
            end
            scaled_u_w = $signed(u_r[schedule_slot_w][pixel_idx*32 +: 32]) >>> tap_level;
            scaled_v_w = $signed(v_r[schedule_slot_w][pixel_idx*32 +: 32]) >>> tap_level;
            if (launch_mode_w != 0) begin
                scaled_u_w = scaled_u_w - 32'sd128;
                scaled_v_w = scaled_v_w - 32'sd128;
            end
            fraction_x = {24'b0, scaled_u_w[7:0]};
            fraction_y = {24'b0, scaled_v_w[7:0]};
            tap_x = scaled_u_w >>> 8;
            tap_y = scaled_v_w >>> 8;
            weight = 65536;
            if (launch_mode_w != 0) begin
                tap_x = tap_x + tap % 2;
                tap_y = tap_y + (tap / 2) % 2;
                weight = ((tap % 2) == 0 ? 256-fraction_x : fraction_x)
                            * (((tap/2) % 2) == 0 ? 256-fraction_y : fraction_y);
            end
            tap_address_w[tap] = texel_address(tap_x, tap_y, tap_level[3:0]);
            tap_subword_w[tap*4 +: 4] = tap_address_w[tap][20:17];
            tap_weight_w[tap*17 +: 17] = weight[16:0];
            if (schedule_valid_w && (launch_mode_w != 0
                                    || (tap < 4 && nearest_pending_r[tap%4]))) begin
                bank_idx = {30'b0, tap_address_w[tap][1:0]};
                match_idx = -1;
                for (port_idx = 0; port_idx < 2; port_idx = port_idx + 1) begin
                    if (port_en_w[bank_idx*2+port_idx]
                        && port_row_w[(bank_idx*2+port_idx)*15 +: 15]
                            == tap_address_w[tap][16:2]) begin
                        match_idx = bank_idx*2+port_idx;
                    end
                end
                if (match_idx == -1) begin
                    if (!port_en_w[bank_idx*2]) begin
                        match_idx = bank_idx*2;
                    end else if (!port_en_w[bank_idx*2+1]) begin
                        match_idx = bank_idx*2+1;
                    end
                end
                if (match_idx != -1) begin
                    port_en_w[match_idx] = 1'b1;
                    port_row_w[match_idx*15 +: 15] = tap_address_w[tap][16:2];
                    tap_port_w[tap*3 +: 3] = match_idx[2:0];
                    if (launch_mode_w == 0) begin
                        pending_w[tap%4] = 1'b0;
                        lane_done_w[tap%4] = 1'b1;
                    end
                end
            end
        end
        if (launch_mode_w == 0) begin
            group_issued_w = pending_w == 0;
        end else if (launch_mode_w == 1) begin
            lane_done_w = 4'b0011 << launch_lane_w;
            group_issued_w = batch_r[0];
        end else begin
            lane_done_w = 4'b0001 << launch_lane_w;
            group_issued_w = batch_r == 3;
        end
        launch_fraction_w = lod_r[schedule_slot_w][launch_lane_w*12 +: 8];
        texture_read_addr_o = port_row_w;
    end
    assign texture_read_en_o = port_en_w;
    assign perf_texture_stall_o = schedule_valid_w && launch_mode_w == 0 && pending_w != 0;

    // Tap metadata accompanies the five-cycle RAM and four-cycle palette paths.
    reg [8:0] return_valid_r;
    reg [4:0] return_slot_r [0:8];
    reg [1:0] return_mode_r [0:8];
    reg [1:0] return_lane_r [0:8];
    reg [3:0] return_done_r [0:8];
    reg [23:0] return_port_r [0:4];
    reg [31:0] return_subword_r [0:4];
    reg [135:0] return_weight_r [0:8];
    reg [7:0] return_fraction_r [0:8];
    reg [127:0] direct_r [0:3];
    reg [127:0] direct_w;
    reg [15:0] word_w;
    reg [15:0] shifted_w;
    reg [7:0] index_w;
    integer lookup;
    always @(*) begin
        full_read_idx_o = 0;
        current_read_idx_o = 0;
        direct_w = 0;
        word_w = 0;
        shifted_w = 0;
        index_w = 0;
        for (lookup = 0; lookup < 8; lookup = lookup + 1) begin
            word_w = texture_read_data_i[return_port_r[4][lookup*3 +: 3]*16 +: 16];
            shifted_w = word_w >> return_subword_r[4][lookup*4 +: 4];
            index_w = format_r == 0 ? {4'b0, shifted_w[3:0]} : shifted_w[7:0];
            current_read_idx_o[lookup*8 +: 8] = index_w;
            if (lookup < 4) begin
                full_read_idx_o[lookup*12 +: 12] =
                    {palette_r[return_slot_r[4]], index_w};
            end
            direct_w[lookup*16 +: 16] = word_w;
        end
    end
    assign full_read_en_o = return_valid_r[4] && return_mode_r[4] == 0 && !stop_i;
    assign current_read_en_o = return_valid_r[4] && return_mode_r[4] != 0 && !stop_i;

    // Palette expansion, tap products, pair sums, 2-D rounding, LOD products,
    // LOD rounding and shading are distinct stages. Horizontal sums never round.
    reg [31:0] expanded_w [0:7];
    reg [19:0] entry_w;
    reg [6:0] filter_valid_r;
    reg [4:0] filter_slot_r [0:6];
    reg [1:0] filter_mode_r [0:6];
    reg [1:0] filter_lane_r [0:6];
    reg [3:0] filter_done_r [0:6];
    reg [7:0] filter_fraction_r [0:3];
    reg [135:0] filter_weight_r;
    reg [255:0] expanded_r;
    reg [799:0] products_r;
    reg [415:0] pairs_r;
    reg [127:0] nearest_r [0:2];
    reg [127:0] bilinear_r;
    reg [127:0] bypass_r;
    reg [135:0] lod_products_r;
    reg [127:0] filtered_r;
    reg [191:0] shade_products_r;
    reg [63:0] alpha_products_r;
    reg [3:0] shade_mask_r;
    reg [31:0] unmodulated_alpha_r;
    reg shade_quad_r;
    integer expand_tap;
    always @(*) begin
        entry_w = 0;
        for (expand_tap = 0; expand_tap < 8; expand_tap = expand_tap + 1) begin
            entry_w = return_mode_r[8] == 0
                        ? full_read_data_i[(expand_tap%4)*20 +: 20]
                        : current_read_data_i[expand_tap*20 +: 20];
            expanded_w[expand_tap] = format_r == 2
                ? expand_rgba(direct_r[3][expand_tap*16 +: 16], 8'd255)
                : expand_rgba(entry_w[15:0], {entry_w[19:16], entry_w[19:16]});
        end
    end
    reg [26:0] rounded_sum_w;
    reg [17:0] rounded_lod_w;
    reg [127:0] bilinear_w;
    reg [127:0] filtered_w;
    reg [191:0] shade_products_w;
    reg [63:0] alpha_products_w;
    reg [3:0] shade_mask_w;
    reg [31:0] unmodulated_alpha_w;
    integer filter_pixel;
    integer channel;
    integer result_lane;
    wire unused_arithmetic_w;
    assign unused_arithmetic_w = ^{offset_r[0], weight[31:17], shifted_w[15:8],
                                    rounded_sum_w[26:24], rounded_sum_w[15:0],
                                    rounded_lod_w[17:16], rounded_lod_w[7:0]};
    always @(*) begin
        rounded_sum_w = 0;
        rounded_lod_w = 0;
        bilinear_w = nearest_r[2];
        filtered_w = bypass_r;
        shade_products_w = 0;
        alpha_products_w = 0;
        shade_mask_w = 0;
        unmodulated_alpha_w = 0;
        result_lane = 0;
        for (filter_pixel = 0; filter_pixel < 4; filter_pixel = filter_pixel + 1) begin
            for (channel = 0; channel < 4; channel = channel + 1) begin
                rounded_sum_w = {1'b0, pairs_r[((filter_pixel%2)*8+channel*2)*26 +: 26]}
                    + {1'b0, pairs_r[((filter_pixel%2)*8+channel*2+1)*26 +: 26]}
                    + 27'd32768;
                if (filter_mode_r[2] != 0) begin
                    bilinear_w[filter_pixel*32+channel*8 +: 8] = rounded_sum_w[23:16];
                end
            end
        end
        for (channel = 0; channel < 4; channel = channel + 1) begin
            rounded_lod_w = {1'b0, lod_products_r[channel*34 +: 17]}
                + {1'b0, lod_products_r[channel*34+17 +: 17]} + 18'd128;
            if (filter_mode_r[4] == 2) begin
                filtered_w[channel*8 +: 8] = rounded_lod_w[15:8];
            end
        end
        for (filter_pixel = 0; filter_pixel < 4; filter_pixel = filter_pixel + 1) begin
            result_lane = filter_mode_r[5] == 0 ? filter_pixel
                : {30'b0, filter_lane_r[5]} + filter_pixel;
            if (result_lane < 4) begin
                for (channel = 0; channel < 3; channel = channel + 1) begin
                    shade_products_w[result_lane*48+channel*16 +: 16] =
                        filtered_r[filter_pixel*32+channel*8 +: 8]
                        * color_r[filter_slot_r[5]][result_lane*24+channel*8 +: 8];
                end
                alpha_products_w[result_lane*16 +: 16] =
                    filtered_r[filter_pixel*32+24 +: 8] * alpha_r[filter_slot_r[5]];
                unmodulated_alpha_w[result_lane*8 +: 8] = filtered_r[filter_pixel*32+24 +: 8];
                shade_mask_w[result_lane] = mask_r[filter_slot_r[5]][result_lane]
                    && filtered_r[filter_pixel*32+24 +: 8] != 0;
            end
        end
    end
    wire [95:0] modulated_color_w;
    wire [31:0] modulated_alpha_w;
    genvar shade_lane;
    genvar shade_channel;
    generate
        for (shade_lane = 0; shade_lane < 4; shade_lane = shade_lane + 1) begin : g_shade
            assign modulated_alpha_w[shade_lane*8 +: 8] = shade_quad_r
                ? divide_255(alpha_products_r[shade_lane*16 +: 16])
                : unmodulated_alpha_r[shade_lane*8 +: 8];
            for (shade_channel = 0; shade_channel < 3;
                    shade_channel = shade_channel + 1) begin : g_channel
                assign modulated_color_w[shade_lane*24+shade_channel*8 +: 8] =
                    divide_255(shade_products_r[shade_lane*48+shade_channel*16 +: 16]);
            end
        end
    endgenerate
    integer filter_idx;
    integer filter_channel;
    integer filter_tap;
    always @(posedge clk_i) begin
        filter_slot_r[0] <= return_slot_r[8];
        filter_mode_r[0] <= return_mode_r[8];
        filter_lane_r[0] <= return_lane_r[8];
        filter_done_r[0] <= return_done_r[8];
        filter_fraction_r[0] <= return_fraction_r[8];
        filter_weight_r <= return_weight_r[8];
        for (filter_idx = 1; filter_idx < 7; filter_idx = filter_idx + 1) begin
            filter_slot_r[filter_idx] <= filter_slot_r[filter_idx-1];
            filter_mode_r[filter_idx] <= filter_mode_r[filter_idx-1];
            filter_lane_r[filter_idx] <= filter_lane_r[filter_idx-1];
            filter_done_r[filter_idx] <= filter_done_r[filter_idx-1];
        end
        for (filter_idx = 1; filter_idx < 4; filter_idx = filter_idx + 1) begin
            filter_fraction_r[filter_idx] <= filter_fraction_r[filter_idx-1];
        end
        for (filter_idx = 0; filter_idx < 8; filter_idx = filter_idx + 1) begin
            expanded_r[filter_idx*32 +: 32] <= expanded_w[filter_idx];
            for (filter_channel = 0; filter_channel < 4; filter_channel = filter_channel + 1) begin
                products_r[(filter_idx*4+filter_channel)*25 +: 25] <=
                    expanded_r[filter_idx*32+filter_channel*8 +: 8]
                    * filter_weight_r[filter_idx*17 +: 17];
            end
        end
        for (filter_idx = 0; filter_idx < 4; filter_idx = filter_idx + 1) begin
            nearest_r[0][filter_idx*32 +: 32] <= expanded_w[filter_idx];
        end
        nearest_r[1] <= nearest_r[0];
        nearest_r[2] <= nearest_r[1];
        for (filter_idx = 0; filter_idx < 2; filter_idx = filter_idx + 1) begin
            for (filter_channel = 0; filter_channel < 4; filter_channel = filter_channel + 1) begin
                for (filter_tap = 0; filter_tap < 2; filter_tap = filter_tap + 1) begin
                    pairs_r[(filter_idx*8+filter_channel*2+filter_tap)*26 +: 26] <=
                        {1'b0, products_r[((filter_idx*4+filter_tap*2)*4
                                            +filter_channel)*25 +: 25]}
                        + {1'b0, products_r[((filter_idx*4+filter_tap*2+1)*4
                                            +filter_channel)*25 +: 25]};
                end
            end
        end
        bilinear_r <= bilinear_w;
        bypass_r <= bilinear_r;
        for (filter_channel = 0; filter_channel < 4; filter_channel = filter_channel + 1) begin
            lod_products_r[filter_channel*34 +: 17] <=
                bilinear_r[filter_channel*8 +: 8] * (17'd256 - {9'b0, filter_fraction_r[3]});
            lod_products_r[filter_channel*34+17 +: 17] <=
                bilinear_r[32+filter_channel*8 +: 8] * filter_fraction_r[3];
        end
        filtered_r <= filtered_w;
        shade_products_r <= shade_products_w;
        alpha_products_r <= alpha_products_w;
        unmodulated_alpha_r <= unmodulated_alpha_w;
        shade_mask_r <= shade_mask_w;
        shade_quad_r <= quad_r[filter_slot_r[5]];
    end
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            allocate_r <= 0;
            schedule_r <= 0;
            retire_r <= 0;
            batch_r <= 0;
            nearest_pending_r <= 4'hf;
            lod_valid_r <= 0;
            return_valid_r <= 0;
            filter_valid_r <= 0;
            unit_done_o <= 1'b0;
        end else begin
            lod_valid_r <= {lod_valid_r[7:0], accept_w};
            return_valid_r <= {return_valid_r[7:0], schedule_valid_w};
            filter_valid_r <= {filter_valid_r[5:0], return_valid_r[8]};
            if (accept_w) begin
                allocate_r <= allocate_r + 1'b1;
            end
            if (retire_w) begin
                retire_r <= retire_r + 1'b1;
            end
            if (schedule_valid_w) begin
                if (group_issued_w) begin
                    schedule_r <= schedule_r + 1'b1;
                    batch_r <= 0;
                    nearest_pending_r <= 4'hf;
                end else if (launch_mode_w == 0) begin
                    nearest_pending_r <= pending_w;
                end else begin
                    batch_r <= batch_r + 1'b1;
                end
            end
            if (accept_w) begin
                completed_r[allocate_r[4:0]] <= 0;
                lod_ready_r[allocate_r[4:0]] <= 0;
            end
            if (lod_valid_r[8]) begin
                lod_ready_r[lod_slot_r[8]] <= 4'hf;
            end
            if (filter_valid_r[6]) begin
                completed_r[filter_slot_r[6]] <= completed_r[filter_slot_r[6]]
                                                | filter_done_r[6];
            end
            if (stop_i) begin
                allocate_r <= 0;
                schedule_r <= 0;
                retire_r <= 0;
                batch_r <= 0;
                nearest_pending_r <= 4'hf;
                lod_valid_r <= 0;
                return_valid_r <= 0;
                filter_valid_r <= 0;
            end
            if (!finish_i) begin
                unit_done_o <= 1'b0;
            end else if (occupancy_w == 0 && lod_valid_r == 0 && return_valid_r == 0
                            && filter_valid_r == 0) begin
                unit_done_o <= 1'b1;
            end
        end
    end
    integer data_idx;
    integer write_lane;
    always @(posedge clk_i) begin
        if (render_state_valid_i && render_state_ready_o) begin
            log2_w_r <= render_state_tex_i[67:64];
            log2_h_r <= render_state_tex_i[71:68];
            format_r <= render_state_tex_i[73:72];
            levels_r <= render_state_tex_i[77:74];
            group_r <= render_state_tex_i[81:78];
            mode_r <= render_state_tex_i[83:82];
            bias_r <= render_state_tex_i[91:84];
            offset_r <= {render_state_tex_i[49:37], 5'b0};
        end
        if (accept_w) begin
            x_r[allocate_r[4:0]] <= sample_x_i;
            y_r[allocate_r[4:0]] <= sample_y_i;
            mask_r[allocate_r[4:0]] <= sample_mask_i;
            depth_r[allocate_r[4:0]] <= sample_depth_i;
            color_r[allocate_r[4:0]] <= sample_color_i;
            alpha_r[allocate_r[4:0]] <= sample_alpha_i;
            quad_r[allocate_r[4:0]] <= sample_quad_i;
            palette_r[allocate_r[4:0]] <= sample_quad_i ? sample_palette_i : group_r;
            u_r[allocate_r[4:0]] <= sample_u_i;
            v_r[allocate_r[4:0]] <= sample_v_i;
        end
        lod_slot_r[0] <= allocate_r[4:0];
        for (data_idx = 1; data_idx < 9; data_idx = data_idx + 1) begin
            lod_slot_r[data_idx] <= lod_slot_r[data_idx-1];
        end
        return_slot_r[0] <= schedule_slot_w;
        return_mode_r[0] <= launch_mode_w;
        return_lane_r[0] <= launch_lane_w;
        return_done_r[0] <= lane_done_w;
        return_port_r[0] <= tap_port_w;
        return_subword_r[0] <= tap_subword_w;
        return_weight_r[0] <= tap_weight_w;
        return_fraction_r[0] <= launch_fraction_w;
        for (data_idx = 1; data_idx < 9; data_idx = data_idx + 1) begin
            return_slot_r[data_idx] <= return_slot_r[data_idx-1];
            return_mode_r[data_idx] <= return_mode_r[data_idx-1];
            return_lane_r[data_idx] <= return_lane_r[data_idx-1];
            return_done_r[data_idx] <= return_done_r[data_idx-1];
            return_weight_r[data_idx] <= return_weight_r[data_idx-1];
            return_fraction_r[data_idx] <= return_fraction_r[data_idx-1];
        end
        for (data_idx = 1; data_idx < 5; data_idx = data_idx + 1) begin
            return_port_r[data_idx] <= return_port_r[data_idx-1];
            return_subword_r[data_idx] <= return_subword_r[data_idx-1];
        end
        direct_r[0] <= direct_w;
        for (data_idx = 1; data_idx < 4; data_idx = data_idx + 1) begin
            direct_r[data_idx] <= direct_r[data_idx-1];
        end
        if (filter_valid_r[6]) begin
            for (write_lane = 0; write_lane < 4; write_lane = write_lane + 1) begin
                if (filter_done_r[6][write_lane]) begin
                    result_color_r[filter_slot_r[6]][write_lane*24 +: 24] <=
                        modulated_color_w[write_lane*24 +: 24];
                    result_alpha_r[filter_slot_r[6]][write_lane*8 +: 8] <=
                        modulated_alpha_w[write_lane*8 +: 8];
                    result_mask_r[filter_slot_r[6]][write_lane] <= shade_mask_r[write_lane];
                end
            end
        end
    end
endmodule
