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
    wire [3:0] lod_ready_w [0:31];
    wire [3:0] completed_w [0:31];
    reg [15:0] x_r [0:31];
    reg [15:0] y_r [0:31];
    reg [3:0] mask_r [0:31];
    reg [63:0] depth_r [0:31];
    reg [95:0] color_r [0:31];
    reg [7:0] alpha_r [0:31];
    reg quad_r [0:31];
    reg [3:0] palette_r [0:31];
    reg [4:0] cfg_wait_r;
    reg [1:0] batch_r;
    reg [3:0] nearest_pending_r;
    assign occupancy_w = allocate_r - retire_r;
    assign sample_ready_o = occupancy_w < 6'd32 && cfg_wait_r == 0 && !stop_i;
    assign accept_w = sample_valid_i && sample_ready_o;
    assign render_state_ready_o = occupancy_w == 0 && cfg_wait_r == 0;
    assign shaded_valid_o = occupancy_w != 0 && completed_w[retire_r[4:0]] == 4'hf
                            && !stop_i;
    assign retire_w = shaded_valid_o && shaded_ready_i;
    assign shaded_x_o = x_r[retire_r[4:0]];
    assign shaded_y_o = y_r[retire_r[4:0]];
    assign shaded_depth_o = depth_r[retire_r[4:0]];
    assign schedule_slot_w = schedule_r[4:0];
    assign schedule_valid_w = schedule_r != allocate_r
                                && lod_ready_w[schedule_slot_w] == 4'hf && !stop_i;

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
    // Four lanes: leading-one count, grouped shift, logarithm ROM and clamp.
    // Four-stage LOD path; only the eight fraction bits cross the shift boundary.
    reg [3:0] lod_valid_r;
    wire [4:0] lod_slot_r [0:3];
    reg [6:0] filter_valid_r;
    wire [4:0] filter_slot_r [0:6];
    wire [3:0] filter_done_r [0:6];
    wire [95:0] modulated_color_w;
    wire [31:0] modulated_alpha_w;
    reg [3:0] shade_mask_r;
    wire [31:0] lane_u_w [0:3];
    wire [31:0] lane_v_w [0:3];
    wire [11:0] lane_lod_w [0:3];
    genvar lane;
    generate
        for (lane = 0; lane < 4; lane = lane + 1) begin : g_lod
            reg [31:0] u_r [0:31];
            reg [31:0] v_r [0:31];
            reg [11:0] lod_r [0:31];
            reg [23:0] result_color_r [0:31];
            reg [7:0] result_alpha_r [0:31];
            reg result_mask_r [0:31];
            assign lane_u_w[lane] = u_r[schedule_slot_w];
            assign lane_v_w[lane] = v_r[schedule_slot_w];
            assign lane_lod_w[lane] = lod_r[schedule_slot_w];
            assign shaded_color_o[lane*24 +: 24] = result_color_r[retire_r[4:0]];
            assign shaded_alpha_o[lane*8 +: 8] = result_alpha_r[retire_r[4:0]];
            assign shaded_mask_o[lane] = result_mask_r[retire_r[4:0]];
            always @(posedge clk_i) begin
                if (accept_w) begin
                    u_r[allocate_r[4:0]] <= sample_u_i[lane*32 +: 32];
                    v_r[allocate_r[4:0]] <= sample_v_i[lane*32 +: 32];
                end
                if (filter_valid_r[6] && filter_done_r[6][lane]) begin
                    result_color_r[filter_slot_r[6]] <= modulated_color_w[lane*24 +: 24];
                    result_alpha_r[filter_slot_r[6]] <= modulated_alpha_w[lane*8 +: 8];
                    result_mask_r[filter_slot_r[6]] <= shade_mask_r[lane];
                end
            end
            wire high_w;
            wire [63:0] count_value_w;
            wire [7:0] group_w;
            wire [23:0] position_w;
            reg [5:0] leading_w;
            reg [63:0] count_value_r;
            reg [5:0] amount_r;
            reg [6:0] shift_r;
            reg [6:0] shift_last_r;
            reg zero_r;
            reg zero_last_r;
            wire [63:0] unused_shifted_w;
            reg [7:0] fraction_r;
            assign high_w = |sample_span_i[lane*96+64 +: 32];
            assign count_value_w = high_w ? sample_span_i[lane*96+32 +: 64]
                : sample_span_i[lane*96 +: 64];
            assign unused_shifted_w = count_value_r << amount_r;
            genvar group_idx;
                // Eight parallel 8-bit encoders and an eight-way group encoder.
                for (group_idx = 0; group_idx < 8; group_idx = group_idx + 1) begin : g_count
                    reg [2:0] position_select_w;
                    assign group_w[group_idx] = |count_value_w[group_idx*8 +: 8];
                    assign position_w[group_idx*3 +: 3] = position_select_w;
                    always @(*) begin
                        position_select_w = 0;
                        casez (count_value_w[group_idx*8 +: 8])
                            8'b1???????: position_select_w = 7;
                            8'b01??????: position_select_w = 6;
                            8'b001?????: position_select_w = 5;
                            8'b0001????: position_select_w = 4;
                            8'b00001???: position_select_w = 3;
                            8'b000001??: position_select_w = 2;
                            8'b0000001?: position_select_w = 1;
                            default: begin end
                        endcase
                    end
                end
            always @(*) begin
                leading_w = 0;
                casez (group_w)
                    8'b1???????: leading_w = {3'd7, position_w[21 +: 3]};
                    8'b01??????: leading_w = {3'd6, position_w[18 +: 3]};
                    8'b001?????: leading_w = {3'd5, position_w[15 +: 3]};
                    8'b0001????: leading_w = {3'd4, position_w[12 +: 3]};
                    8'b00001???: leading_w = {3'd3, position_w[9 +: 3]};
                    8'b000001??: leading_w = {3'd2, position_w[6 +: 3]};
                    8'b0000001?: leading_w = {3'd1, position_w[3 +: 3]};
                    8'b00000001: leading_w = {3'd0, position_w[0 +: 3]};
                    default: begin end
                endcase
            end
            reg signed [15:0] logarithm_r;
            wire signed [15:0] biased_w;
            wire signed [15:0] maximum_w;
            wire [11:0] clamped_w;
            assign biased_w = logarithm_r + ($signed({{8{bias_r[7]}}, bias_r}) <<< 4);
            assign maximum_w = $signed({4'b0, levels_r - 4'd1, 8'b0});
            assign clamped_w = biased_w < 0 ? 12'd0 :
                                biased_w > maximum_w ? maximum_w[11:0] : biased_w[11:0];
            always @(posedge clk_i) begin
                count_value_r <= count_value_w;
                amount_r <= 6'd63 - leading_w;
                shift_r <= (high_w ? 7'd0 : 7'd32) + 7'd63 - {1'b0, leading_w};
                zero_r <= sample_span_i[lane*96 +: 96] == 0;
                fraction_r <= unused_shifted_w[62:55];
                shift_last_r <= shift_r;
                zero_last_r <= zero_r;
                logarithm_r <= zero_last_r ? 16'sd0 :
                    (16'sd79 - $signed({9'b0, shift_last_r})) * 16'sd256
                    + $signed({7'b0, log_fraction(fraction_r)});
                if (lod_valid_r[2]) lod_r[lod_slot_r[2]] <= clamped_w;
            end
        end
    endgenerate

    // SET_TEX constants settle before sampling: dimensions take one stage per level,
    // sizes and prefix offsets take two. No mip prefix arithmetic lies on a tap path.
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) cfg_wait_r <= 0;
        else if (render_state_valid_i && render_state_ready_o) cfg_wait_r <= 20;
        else if (cfg_wait_r != 0) cfg_wait_r <= cfg_wait_r - 1'b1;
    end
    wire [16:0] offset_base_w;
    assign offset_base_w = offset_r[17:1];
    wire [8:0] mip_mask_x_w [0:9];
    wire [8:0] mip_mask_y_w [0:9];
    wire [3:0] mip_row_shift_w [0:9];
    wire [16:0] mip_offset_w [0:9];
    wire [80:0] mip_width_chain_w;
    wire [80:0] mip_height_chain_w;
    wire [80:0] mip_groups_x_chain_w;
    wire [80:0] mip_groups_y_chain_w;
    wire [152:0] mip_offset_chain_w;
    genvar mip;
    generate
        for (mip = 0; mip < 10; mip = mip + 1) begin : g_mip
            localparam [3:0] RGB_ROW_LEVEL = mip + 1;
            localparam [3:0] INDEX_ROW_LEVEL = mip + 2;
            reg [8:0] mask_x_r;
            reg [8:0] mask_y_r;
            reg [3:0] row_shift_r;
            reg [8:0] unused_width_r;
            reg [8:0] unused_height_r;
            reg [8:0] unused_groups_x_r;
            reg [8:0] unused_groups_y_r;
            reg [16:0] level_offset_r;
            wire [8:0] width_w;
            wire [8:0] height_w;
            wire [8:0] groups_x_w;
            wire [8:0] groups_y_w;
            assign mip_mask_x_w[mip] = mask_x_r;
            assign mip_mask_y_w[mip] = mask_y_r;
            assign mip_row_shift_w[mip] = row_shift_r;
            assign mip_offset_w[mip] = level_offset_r;
            if (mip < 9) begin : g_chain
                assign mip_width_chain_w[mip*9 +: 9] = unused_width_r;
                assign mip_height_chain_w[mip*9 +: 9] = unused_height_r;
                assign mip_groups_x_chain_w[mip*9 +: 9] = unused_groups_x_r;
                assign mip_groups_y_chain_w[mip*9 +: 9] = unused_groups_y_r;
                assign mip_offset_chain_w[mip*17 +: 17] = level_offset_r;
            end
            // All dimensions are powers of two, including padded one-block levels.
            assign groups_x_w = format_r == 2 ?
                (width_w > 1 ? width_w >> 1 : 9'd1) :
                (width_w > 2 ? width_w >> 2 : 9'd1);
            assign groups_y_w = format_r == 0 ?
                (height_w > 2 ? height_w >> 2 : 9'd1) :
                (height_w > 1 ? height_w >> 1 : 9'd1);
            always @(posedge clk_i) begin
                mask_x_r <= width_w - 9'd1;
                mask_y_r <= height_w - 9'd1;
                row_shift_r <= format_r == 2 ?
                    (log2_w_r > RGB_ROW_LEVEL ? log2_w_r - RGB_ROW_LEVEL : 4'd0) :
                    (log2_w_r > INDEX_ROW_LEVEL ? log2_w_r - INDEX_ROW_LEVEL : 4'd0);
                unused_width_r <= width_w;
                unused_height_r <= height_w;
                unused_groups_x_r <= groups_x_w;
                unused_groups_y_r <= groups_y_w;
            end
            if (mip == 0) begin : g_first
                assign width_w = 9'd1 << log2_w_r;
                assign height_w = 9'd1 << log2_h_r;
                always @(posedge clk_i) begin
                    level_offset_r <= offset_base_w;
                end
            end else begin : g_next
                reg [16:0] size_r;
                reg [16:0] base_r;
                assign width_w = mip_width_chain_w[(mip-1)*9 +: 9] > 1 ?
                    mip_width_chain_w[(mip-1)*9 +: 9] >> 1 : 9'd1;
                assign height_w = mip_height_chain_w[(mip-1)*9 +: 9] > 1 ?
                    mip_height_chain_w[(mip-1)*9 +: 9] >> 1 : 9'd1;
                always @(posedge clk_i) begin
                    size_r <= (mip_groups_x_chain_w[(mip-1)*9 +: 9] *
                        mip_groups_y_chain_w[(mip-1)*9 +: 9]) << 2;
                    base_r <= mip_offset_chain_w[(mip-1)*17 +: 17];
                    level_offset_r <= base_r + size_r;
                end
            end
        end
    endgenerate
    wire [7:0] port_en_w;
    wire [119:0] port_row_w;
    wire [23:0] tap_port_w;
    wire [31:0] tap_subword_w;
    wire [135:0] tap_weight_w;
    wire [20:0] tap_address_w [0:7];
    wire [2:0] bank_port_w [0:31];
    wire [7:0] unused_tap_accepted_w;
    wire [7:0] bank_accepted_w [0:3];
    wire [3:0] lane_done_w;
    wire [3:0] pending_w;
    wire [1:0] launch_mode_w;
    wire [1:0] launch_lane_w;
    wire [7:0] launch_fraction_w;
    wire group_issued_w;
    assign launch_mode_w = quad_r[schedule_slot_w] ? 2'b0 : mode_r;
    assign launch_lane_w = launch_mode_w == 1 ? {batch_r[0], 1'b0} : batch_r;
    assign launch_fraction_w = lane_lod_w[launch_lane_w][7:0];
    assign lane_done_w = launch_mode_w == 0 ? unused_tap_accepted_w[3:0] :
        launch_mode_w == 1 ? 4'b0011 << launch_lane_w : 4'b0001 << launch_lane_w;
    assign pending_w = nearest_pending_r & ~lane_done_w;
    assign group_issued_w = launch_mode_w == 0 ? pending_w == 0 :
        launch_mode_w == 1 ? batch_r[0] : batch_r == 3;
    always @(*) begin
        texture_read_addr_o = port_row_w;
    end
    assign texture_read_en_o = port_en_w;
    assign perf_texture_stall_o = schedule_valid_w && launch_mode_w == 0 && pending_w != 0;
    genvar tap;
    genvar bank;
    generate
        for (tap = 0; tap < 8; tap = tap + 1) begin : g_tap
            localparam [1:0] NEAREST_PIXEL = tap[1:0];
            localparam [1:0] PAIR_PIXEL = {1'b0, tap[2]};
            wire [1:0] pixel_w;
            wire [11:0] unused_lod_w;
            wire [3:0] level_w;
            wire signed [31:0] scaled_u_w;
            wire signed [31:0] scaled_v_w;
            wire signed [31:0] centered_u_w;
            wire signed [31:0] centered_v_w;
            wire [8:0] x_w;
            wire [8:0] y_w;
            wire [8:0] wrapped_x_w;
            wire [8:0] wrapped_y_w;
            wire [8:0] block_x_w;
            wire [8:0] block_y_w;
            wire [16:0] unused_row_product_w;
            wire [16:0] halfword_w;
            wire [8:0] weight_x_w;
            wire [8:0] weight_y_w;
            wire [17:0] weight_w;
            wire unused_weight_w;
            assign pixel_w = launch_mode_w == 0 ? NEAREST_PIXEL :
                launch_mode_w == 1 ? launch_lane_w + PAIR_PIXEL : launch_lane_w;
            assign unused_lod_w = quad_r[schedule_slot_w] ? 12'd0 : lane_lod_w[pixel_w];
            assign level_w = unused_lod_w[11:8] +
                ((launch_mode_w == 2 && tap >= 4 && unused_lod_w[11:8] < levels_r - 4'd1)
                    ? 4'd1 : 4'd0);
            assign scaled_u_w = $signed(lane_u_w[pixel_w]) >>> level_w;
            assign scaled_v_w = $signed(lane_v_w[pixel_w]) >>> level_w;
            assign centered_u_w = scaled_u_w - (launch_mode_w != 0 ? 32'sd128 : 32'sd0);
            assign centered_v_w = scaled_v_w - (launch_mode_w != 0 ? 32'sd128 : 32'sd0);
            assign x_w = centered_u_w[16:8] +
                ((launch_mode_w != 0 && (tap % 2) != 0) ? 9'd1 : 9'd0);
            assign y_w = centered_v_w[16:8] +
                ((launch_mode_w != 0 && ((tap/2) % 2) != 0) ? 9'd1 : 9'd0);
            assign wrapped_x_w = x_w & mip_mask_x_w[level_w];
            assign wrapped_y_w = y_w & mip_mask_y_w[level_w];
            assign block_x_w = format_r == 2 ? wrapped_x_w : wrapped_x_w >> 1;
            assign block_y_w = format_r == 0 ? wrapped_y_w >> 1 : wrapped_y_w;
            // Power-of-two rows make multiplication a shift. The column occupies
            // only the zero low bits of the row; the bank bits never carry into it.
            assign unused_row_product_w = {9'b0, block_y_w[8:1]} << mip_row_shift_w[level_w];
            assign halfword_w = {mip_offset_w[level_w][16:2] +
                (unused_row_product_w[14:0] | {7'b0, block_x_w[8:1]}),
                block_y_w[0], block_x_w[0]};
            assign tap_address_w[tap] = {format_r == 0 ?
                {wrapped_y_w[0], wrapped_x_w[0], 2'b0} : format_r == 1 ?
                {wrapped_x_w[0], 3'b0} : 4'd0, halfword_w};
            assign tap_subword_w[tap*4 +: 4] = tap_address_w[tap][20:17];
            assign weight_x_w = (tap % 2) == 0 ?
                9'd256 - {1'b0, centered_u_w[7:0]} : {1'b0, centered_u_w[7:0]};
            assign weight_y_w = ((tap/2) % 2) == 0 ?
                9'd256 - {1'b0, centered_v_w[7:0]} : {1'b0, centered_v_w[7:0]};
            assign weight_w = weight_x_w * weight_y_w;
            assign unused_weight_w = ^{weight_w[17], centered_u_w[31:17], centered_v_w[31:17]};
            assign tap_weight_w[tap*17 +: 17] = launch_mode_w == 0 ?
                17'd65536 : weight_w[16:0];
            assign tap_port_w[tap*3 +: 3] = bank_port_w[tap*4] |
                bank_port_w[tap*4+1] | bank_port_w[tap*4+2] | bank_port_w[tap*4+3];
        end
        // Four banks, each an eight-step ordered two-port allocator; no dynamic bus writes.
        for (bank = 0; bank < 4; bank = bank + 1) begin : g_bank
            wire [17:0] en_chain_w /* verilator split_var */;
            wire [134:0] row_a_chain_w /* verilator split_var */;
            wire [134:0] row_b_chain_w /* verilator split_var */;
            assign en_chain_w[0 +: 2] = 0;
            assign row_a_chain_w[0 +: 15] = 0;
            assign row_b_chain_w[0 +: 15] = 0;
            assign port_en_w[bank*2 +: 2] = en_chain_w[16 +: 2];
            assign port_row_w[bank*30 +: 30] = {row_b_chain_w[120 +: 15],
                row_a_chain_w[120 +: 15]};
            for (tap = 0; tap < 8; tap = tap + 1) begin : g_allocate
                wire [1:0] previous_en_w;
                wire [14:0] previous_a_w;
                wire [14:0] previous_b_w;
                wire [1:0] en_w;
                wire [14:0] row_a_w;
                wire [14:0] row_b_w;
                assign previous_en_w = en_chain_w[tap*2 +: 2];
                assign previous_a_w = row_a_chain_w[tap*15 +: 15];
                assign previous_b_w = row_b_chain_w[tap*15 +: 15];
                assign en_chain_w[(tap+1)*2 +: 2] = en_w;
                assign row_a_chain_w[(tap+1)*15 +: 15] = row_a_w;
                assign row_b_chain_w[(tap+1)*15 +: 15] = row_b_w;
                wire request_w;
                wire match_a_w;
                wire match_b_w;
                wire select_b_w;
                wire accepted_tap_w;
                assign request_w = schedule_valid_w && tap_address_w[tap][1:0] == bank &&
                    (launch_mode_w != 0 || (tap < 4 && nearest_pending_r[tap%4]));
                assign match_a_w = previous_en_w[0] && previous_a_w == tap_address_w[tap][16:2];
                assign match_b_w = previous_en_w[1] && previous_b_w == tap_address_w[tap][16:2];
                assign select_b_w = match_b_w || (!match_a_w && previous_en_w[0]);
                assign accepted_tap_w = request_w &&
                    (match_a_w || match_b_w || previous_en_w != 2'b11);
                assign bank_accepted_w[bank][tap] = accepted_tap_w;
                assign en_w = previous_en_w |
                    (accepted_tap_w ? (select_b_w ? 2'b10 : 2'b01) : 2'b00);
                assign row_a_w = accepted_tap_w && !select_b_w ?
                    tap_address_w[tap][16:2] : previous_a_w;
                assign row_b_w = accepted_tap_w && select_b_w ?
                    tap_address_w[tap][16:2] : previous_b_w;
                assign bank_port_w[tap*4+bank] = accepted_tap_w ?
                    {bank[1:0], select_b_w} : 3'd0;
            end
        end
        for (tap = 0; tap < 8; tap = tap + 1) begin : g_accepted
            assign unused_tap_accepted_w[tap] = bank_accepted_w[0][tap] |
                bank_accepted_w[1][tap] | bank_accepted_w[2][tap] |
                bank_accepted_w[3][tap];
        end
    endgenerate

    // Tap metadata accompanies the five-cycle RAM and four-cycle palette paths.
    reg [8:0] return_valid_r;
    wire [4:0] return_slot_r [0:8];
    wire [1:0] return_mode_r [0:8];
    wire [1:0] return_lane_r [0:8];
    wire [3:0] return_done_r [0:8];
    wire [23:0] return_port_r [0:4];
    wire [31:0] return_subword_r [0:4];
    wire [135:0] return_weight_w;
    wire [7:0] return_fraction_w;
    // Nine-cycle filter metadata: one 144-bit circular RAM, split into two DRM banks.
    reg [8:0] metadata_write_r;
    wire [8:0] metadata_read_w;
    wire [143:0] metadata_input_w;
    wire [143:0] metadata_data_w;
    assign metadata_read_w = metadata_write_r - 9'd8;
    assign metadata_input_w = {launch_fraction_w, tap_weight_w};
    assign return_weight_w = metadata_data_w[135:0];
    assign return_fraction_w = metadata_data_w[143:136];
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) metadata_write_r <= 0;
        else metadata_write_r <= metadata_write_r + 1'b1;
    end
    genvar metadata_bank;
    generate
        for (metadata_bank = 0; metadata_bank < 2;
            metadata_bank = metadata_bank + 1) begin : g_delay
            edrv32_ram_gpu_delay u_metadata (
                .clk_i(clk_i),
                .wr_en_i(1'b1),
                .wr_addr_i(metadata_write_r),
                .wr_data_i(metadata_input_w[metadata_bank*72 +: 72]),
                .rd_en_i(1'b1),
                .rd_addr_i(metadata_read_w),
                .rd_data_o(metadata_data_w[metadata_bank*72 +: 72])
            );
        end
    endgenerate
    wire [127:0] direct_r [0:3];
    wire [127:0] direct_w;
    generate
        for (tap = 0; tap < 8; tap = tap + 1) begin : g_lookup
            reg [15:0] word_w;
            wire [15:0] shifted_w;
            wire [7:0] index_w;
            wire unused_shifted_w;
            always @(*) begin
                word_w = 0;
                case (return_port_r[4][tap*3 +: 3])
                    3'd0: word_w = texture_read_data_i[0 +: 16];
                    3'd1: word_w = texture_read_data_i[16 +: 16];
                    3'd2: word_w = texture_read_data_i[32 +: 16];
                    3'd3: word_w = texture_read_data_i[48 +: 16];
                    3'd4: word_w = texture_read_data_i[64 +: 16];
                    3'd5: word_w = texture_read_data_i[80 +: 16];
                    3'd6: word_w = texture_read_data_i[96 +: 16];
                    3'd7: word_w = texture_read_data_i[112 +: 16];
                    default: word_w = 0;
                endcase
            end
            assign shifted_w = word_w >> return_subword_r[4][tap*4 +: 4];
            assign unused_shifted_w = ^shifted_w[15:8];
            assign index_w = format_r == 0 ? {4'b0, shifted_w[3:0]} : shifted_w[7:0];
            always @(*) begin
                current_read_idx_o[tap*8 +: 8] = index_w;
            end
            if (tap < 4) begin : g_full
                always @(*) begin
                    full_read_idx_o[tap*12 +: 12] = {palette_r[return_slot_r[4]], index_w};
                end
            end
            assign direct_w[tap*16 +: 16] = word_w;
        end
    endgenerate
    assign full_read_en_o = return_valid_r[4] && return_mode_r[4] == 0 && !stop_i;
    assign current_read_en_o = return_valid_r[4] && return_mode_r[4] != 0 && !stop_i;

    // Palette expansion, tap products, pair sums, 2-D rounding, LOD products,
    // LOD rounding and shading are distinct stages. Horizontal sums never round.
    wire [31:0] expanded_w [0:7];
    wire [1:0] filter_mode_r [0:6];
    wire [1:0] filter_lane_r [0:6];
    wire [7:0] filter_fraction_r [0:3];
    reg [135:0] filter_weight_r;
    reg [255:0] expanded_r;
    wire [24:0] product_w [0:31];
    wire [25:0] pair_w [0:15];
    wire [127:0] nearest_r [0:2];
    reg [127:0] bilinear_r;
    reg [127:0] bypass_r;
    reg [135:0] lod_products_r;
    reg [127:0] filtered_r;
    reg [191:0] shade_products_r;
    reg [63:0] alpha_products_r;
    reg [31:0] unmodulated_alpha_r;
    reg shade_quad_r;
    wire [127:0] bilinear_w;
    wire [127:0] filtered_w;
    wire [191:0] shade_products_w;
    wire [63:0] alpha_products_w;
    wire [3:0] shade_mask_w;
    wire [31:0] unmodulated_alpha_w;
    wire unused_offset_w;
    assign unused_offset_w = offset_r[0];
    genvar filter_pixel;
    genvar channel;
    genvar pair;
    generate
        // Expansion stage: eight RGB565 wiring networks and alpha selectors, no arithmetic.
        for (tap = 0; tap < 8; tap = tap + 1) begin : g_expand
            wire [19:0] entry_w;
            wire [15:0] rgb_w;
            wire [7:0] alpha_w;
            wire unused_entry_w;
            assign entry_w = return_mode_r[8] == 0 ?
                full_read_data_i[(tap%4)*20 +: 20] : current_read_data_i[tap*20 +: 20];
            assign rgb_w = format_r == 2 ? direct_r[3][tap*16 +: 16] : entry_w[15:0];
            assign alpha_w = format_r == 2 ? 8'd255 : {entry_w[19:16], entry_w[19:16]};
            assign unused_entry_w = ^entry_w;
            assign expanded_w[tap] = {alpha_w, rgb_w[4:0], rgb_w[4:2],
                rgb_w[10:5], rgb_w[10:9], rgb_w[15:11], rgb_w[15:13]};
            // Product stage: 8 taps x 4 channels = 32 independent 8x17 multipliers.
            for (channel = 0; channel < 4; channel = channel + 1) begin : g_product
                reg [24:0] product_r;
                assign product_w[tap*4+channel] = product_r;
                always @(posedge clk_i) begin
                    product_r <= expanded_r[tap*32+channel*8 +: 8] *
                        filter_weight_r[tap*17 +: 17];
                end
            end
        end
        // Pair stage: 2 footprints x 4 channels x 2 rows = sixteen 26-bit sums.
        for (filter_pixel = 0; filter_pixel < 2; filter_pixel = filter_pixel + 1) begin : g_pair
            localparam PIXEL_BASE = filter_pixel*8;
            for (channel = 0; channel < 4; channel = channel + 1) begin : g_channel
                localparam CHANNEL_BASE = channel*2;
                for (pair = 0; pair < 2; pair = pair + 1) begin : g_row
                    reg [25:0] pair_r;
                    assign pair_w[PIXEL_BASE+CHANNEL_BASE+pair] = pair_r;
                    always @(posedge clk_i) begin
                        pair_r <= {1'b0, product_w[(filter_pixel*4+pair*2)*4+channel]} +
                            {1'b0, product_w[(filter_pixel*4+pair*2+1)*4+channel]};
                    end
                end
            end
        end
        // Bilinear rounding stage: eight 27-bit vertical sums shared by duplicate outputs.
        for (filter_pixel = 0; filter_pixel < 2;
                filter_pixel = filter_pixel + 1) begin : g_bilinear
            localparam PIXEL_BASE = filter_pixel*8;
            for (channel = 0; channel < 4; channel = channel + 1) begin : g_channel
                wire [26:0] rounded_w;
                wire unused_rounded_w;
                assign rounded_w = {1'b0, pair_w[PIXEL_BASE+channel*2]} +
                    {1'b0, pair_w[PIXEL_BASE+channel*2+1]} + 27'd32768;
                assign unused_rounded_w = ^{rounded_w[26:24], rounded_w[15:0]};
                assign bilinear_w[filter_pixel*32+channel*8 +: 8] = filter_mode_r[2] != 0 ?
                    rounded_w[23:16] : nearest_r[2][filter_pixel*32+channel*8 +: 8];
                assign bilinear_w[(filter_pixel+2)*32+channel*8 +: 8] = filter_mode_r[2] != 0 ?
                    rounded_w[23:16] : nearest_r[2][(filter_pixel+2)*32+channel*8 +: 8];
            end
        end
        // LOD stages: eight 8x9 products, then four 18-bit rounding sums.
        for (channel = 0; channel < 4; channel = channel + 1) begin : g_lod_filter
            wire [8:0] inverse_fraction_w;
            wire [17:0] rounded_w;
            wire unused_rounded_w;
            assign inverse_fraction_w = 9'd256 - {1'b0, filter_fraction_r[3]};
            assign rounded_w = {1'b0, lod_products_r[channel*34 +: 17]} +
                {1'b0, lod_products_r[channel*34+17 +: 17]} + 18'd128;
            assign unused_rounded_w = ^{rounded_w[17:16], rounded_w[7:0]};
            assign filtered_w[channel*8 +: 8] = filter_mode_r[4] == 2 ?
                rounded_w[15:8] : bypass_r[channel*8 +: 8];
            always @(posedge clk_i) begin
                lod_products_r[channel*34 +: 17] <= bilinear_r[channel*8 +: 8] *
                    inverse_fraction_w;
                lod_products_r[channel*34+17 +: 17] <=
                    bilinear_r[32+channel*8 +: 8] * filter_fraction_r[3];
            end
        end
    endgenerate
    assign filtered_w[127:32] = bypass_r[127:32];
    generate
        // Shade product stage: four fixed output lanes, each with 3 RGB and 1 alpha product.
        // Registered filter lane selects a source word before the sixteen 8x8 multipliers.
        for (filter_pixel = 0; filter_pixel < 4; filter_pixel = filter_pixel + 1) begin : g_shade
            reg [31:0] source_w;
            wire enabled_w;
            wire [31:0] selected_w;
            wire [7:0] alpha_w;
            wire [16:0] alpha_temp_w;
            wire [17:0] alpha_total_w;
            wire unused_alpha_w;
            if (filter_pixel == 3) begin : g_all_sources
                assign enabled_w = 1'b1;
            end else begin : g_source_range
                assign enabled_w = filter_mode_r[5] == 0 || filter_lane_r[5] <= filter_pixel;
            end
            always @(*) begin
                source_w = 0;
                case (filter_lane_r[5])
                    2'd0: source_w = filtered_r[(filter_pixel-0)*32 +: 32];
                    2'd1: source_w = filter_pixel >= 1 ?
                        filtered_r[((filter_pixel+4-1)%4)*32 +: 32] : 32'd0;
                    2'd2: source_w = filter_pixel >= 2 ?
                        filtered_r[((filter_pixel+4-2)%4)*32 +: 32] : 32'd0;
                    2'd3: source_w = filter_pixel >= 3 ?
                        filtered_r[((filter_pixel+4-3)%4)*32 +: 32] : 32'd0;
                    default: source_w = 0;
                endcase
            end
            assign selected_w = filter_mode_r[5] == 0 ?
                filtered_r[filter_pixel*32 +: 32] : source_w;
            assign alpha_w = selected_w[31:24];
            assign alpha_products_w[filter_pixel*16 +: 16] = enabled_w ?
                alpha_w * alpha_r[filter_slot_r[5]] : 16'd0;
            assign unmodulated_alpha_w[filter_pixel*8 +: 8] = enabled_w ? alpha_w : 8'd0;
            assign shade_mask_w[filter_pixel] = enabled_w &&
                mask_r[filter_slot_r[5]][filter_pixel] && alpha_w != 0;
            // Shade rounding stage: sixteen explicit 17/18-bit divide-by-255 networks.
            assign alpha_temp_w = {1'b0, alpha_products_r[filter_pixel*16 +: 16]} + 17'd128;
            assign alpha_total_w = {1'b0, alpha_temp_w} + {9'b0, alpha_temp_w[16:8]};
            assign unused_alpha_w = ^{alpha_total_w[17:16], alpha_total_w[7:0]};
            assign modulated_alpha_w[filter_pixel*8 +: 8] = shade_quad_r ?
                alpha_total_w[15:8] : unmodulated_alpha_r[filter_pixel*8 +: 8];
            for (channel = 0; channel < 3; channel = channel + 1) begin : g_channel
                wire [16:0] temp_w;
                wire [17:0] total_w;
                wire unused_total_w;
                assign shade_products_w[filter_pixel*48+channel*16 +: 16] = enabled_w ?
                    selected_w[channel*8 +: 8] *
                    color_r[filter_slot_r[5]][filter_pixel*24+channel*8 +: 8] : 16'd0;
                assign temp_w =
                    {1'b0, shade_products_r[filter_pixel*48+channel*16 +: 16]} + 17'd128;
                assign total_w = {1'b0, temp_w} + {9'b0, temp_w[16:8]};
                assign unused_total_w = ^{total_w[17:16], total_w[7:0]};
                assign modulated_color_w[filter_pixel*24+channel*8 +: 8] = total_w[15:8];
            end
        end
    endgenerate
    always @(posedge clk_i) begin
        filter_weight_r <= return_weight_w;
        expanded_r <= {expanded_w[7], expanded_w[6], expanded_w[5], expanded_w[4],
            expanded_w[3], expanded_w[2], expanded_w[1], expanded_w[0]};
        bilinear_r <= bilinear_w;
        bypass_r <= bilinear_r;
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
            lod_valid_r <= {lod_valid_r[2:0], accept_w};
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
        end
    end
    // Thirty-two context completion registers: one whole-element update per clock.
    genvar context_idx;
    generate
        for (context_idx = 0; context_idx < 32; context_idx = context_idx + 1) begin : g_context
            reg [3:0] completed_r;
            reg [3:0] lod_ready_r;
            wire [3:0] completed_next_w;
            assign completed_next_w =
                filter_valid_r[6] && filter_slot_r[6] == context_idx ?
                    completed_r | filter_done_r[6] : 4'd0;
            // Reset holds the uninitialized context data, matching the command-control process.
            always @(posedge clk_i or negedge rst_n_i) begin
                if (!rst_n_i) begin
                end else begin
                    if ((accept_w && allocate_r[4:0] == context_idx) ||
                            (filter_valid_r[6] && filter_slot_r[6] == context_idx))
                        completed_r <= completed_next_w;
                    if ((accept_w && allocate_r[4:0] == context_idx) ||
                            (lod_valid_r[3] && lod_slot_r[3] == context_idx))
                        lod_ready_r <= lod_valid_r[3] && lod_slot_r[3] == context_idx ?
                            4'hf : 4'd0;
                end
            end
            assign completed_w[context_idx] = completed_r;
            assign lod_ready_w[context_idx] = lod_ready_r;
        end
    endgenerate
    // Metadata stages: independent local registers, one assignment per register.
    genvar pipe_stage;
    generate
        for (pipe_stage = 0; pipe_stage < 4; pipe_stage = pipe_stage + 1) begin : g_lod_slot
            reg [4:0] data_r;
            wire [4:0] data_w;
            assign lod_slot_r[pipe_stage] = data_r;
            if (pipe_stage == 0) begin : g_first
                assign data_w = allocate_r[4:0];
            end else begin : g_previous
                assign data_w = lod_slot_r[pipe_stage-1];
            end
            always @(posedge clk_i) begin
                data_r <= data_w;
            end
        end
        for (pipe_stage = 0; pipe_stage < 9; pipe_stage = pipe_stage + 1) begin : g_return_slot
            reg [4:0] data_r;
            wire [4:0] data_w;
            assign return_slot_r[pipe_stage] = data_r;
            if (pipe_stage == 0) begin : g_first
                assign data_w = schedule_slot_w;
            end else begin : g_previous
                assign data_w = return_slot_r[pipe_stage-1];
            end
            always @(posedge clk_i) begin
                data_r <= data_w;
            end
        end
        for (pipe_stage = 0; pipe_stage < 9; pipe_stage = pipe_stage + 1) begin : g_return_mode
            reg [1:0] data_r;
            wire [1:0] data_w;
            assign return_mode_r[pipe_stage] = data_r;
            if (pipe_stage == 0) begin : g_first
                assign data_w = launch_mode_w;
            end else begin : g_previous
                assign data_w = return_mode_r[pipe_stage-1];
            end
            always @(posedge clk_i) begin
                data_r <= data_w;
            end
        end
        for (pipe_stage = 0; pipe_stage < 9; pipe_stage = pipe_stage + 1) begin : g_return_lane
            reg [1:0] data_r;
            wire [1:0] data_w;
            assign return_lane_r[pipe_stage] = data_r;
            if (pipe_stage == 0) begin : g_first
                assign data_w = launch_lane_w;
            end else begin : g_previous
                assign data_w = return_lane_r[pipe_stage-1];
            end
            always @(posedge clk_i) begin
                data_r <= data_w;
            end
        end
        for (pipe_stage = 0; pipe_stage < 9; pipe_stage = pipe_stage + 1) begin : g_return_done
            reg [3:0] data_r;
            wire [3:0] data_w;
            assign return_done_r[pipe_stage] = data_r;
            if (pipe_stage == 0) begin : g_first
                assign data_w = lane_done_w;
            end else begin : g_previous
                assign data_w = return_done_r[pipe_stage-1];
            end
            always @(posedge clk_i) begin
                data_r <= data_w;
            end
        end
        for (pipe_stage = 0; pipe_stage < 5; pipe_stage = pipe_stage + 1) begin : g_return_port
            reg [23:0] data_r;
            wire [23:0] data_w;
            assign return_port_r[pipe_stage] = data_r;
            if (pipe_stage == 0) begin : g_first
                assign data_w = tap_port_w;
            end else begin : g_previous
                assign data_w = return_port_r[pipe_stage-1];
            end
            always @(posedge clk_i) begin
                data_r <= data_w;
            end
        end
        for (pipe_stage = 0; pipe_stage < 5; pipe_stage = pipe_stage + 1) begin : g_return_subword
            reg [31:0] data_r;
            wire [31:0] data_w;
            assign return_subword_r[pipe_stage] = data_r;
            if (pipe_stage == 0) begin : g_first
                assign data_w = tap_subword_w;
            end else begin : g_previous
                assign data_w = return_subword_r[pipe_stage-1];
            end
            always @(posedge clk_i) begin
                data_r <= data_w;
            end
        end
        for (pipe_stage = 0; pipe_stage < 4; pipe_stage = pipe_stage + 1) begin : g_direct
            reg [127:0] data_r;
            wire [127:0] data_w;
            assign direct_r[pipe_stage] = data_r;
            if (pipe_stage == 0) begin : g_first
                assign data_w = direct_w;
            end else begin : g_previous
                assign data_w = direct_r[pipe_stage-1];
            end
            always @(posedge clk_i) begin
                data_r <= data_w;
            end
        end
        for (pipe_stage = 0; pipe_stage < 7; pipe_stage = pipe_stage + 1) begin : g_filter_slot
            reg [4:0] data_r;
            wire [4:0] data_w;
            assign filter_slot_r[pipe_stage] = data_r;
            if (pipe_stage == 0) begin : g_first
                assign data_w = return_slot_r[8];
            end else begin : g_previous
                assign data_w = filter_slot_r[pipe_stage-1];
            end
            always @(posedge clk_i) begin
                data_r <= data_w;
            end
        end
        for (pipe_stage = 0; pipe_stage < 7; pipe_stage = pipe_stage + 1) begin : g_filter_mode
            reg [1:0] data_r;
            wire [1:0] data_w;
            assign filter_mode_r[pipe_stage] = data_r;
            if (pipe_stage == 0) begin : g_first
                assign data_w = return_mode_r[8];
            end else begin : g_previous
                assign data_w = filter_mode_r[pipe_stage-1];
            end
            always @(posedge clk_i) begin
                data_r <= data_w;
            end
        end
        for (pipe_stage = 0; pipe_stage < 7; pipe_stage = pipe_stage + 1) begin : g_filter_lane
            reg [1:0] data_r;
            wire [1:0] data_w;
            assign filter_lane_r[pipe_stage] = data_r;
            if (pipe_stage == 0) begin : g_first
                assign data_w = return_lane_r[8];
            end else begin : g_previous
                assign data_w = filter_lane_r[pipe_stage-1];
            end
            always @(posedge clk_i) begin
                data_r <= data_w;
            end
        end
        for (pipe_stage = 0; pipe_stage < 7; pipe_stage = pipe_stage + 1) begin : g_filter_done
            reg [3:0] data_r;
            wire [3:0] data_w;
            assign filter_done_r[pipe_stage] = data_r;
            if (pipe_stage == 0) begin : g_first
                assign data_w = return_done_r[8];
            end else begin : g_previous
                assign data_w = filter_done_r[pipe_stage-1];
            end
            always @(posedge clk_i) begin
                data_r <= data_w;
            end
        end
        for (pipe_stage = 0; pipe_stage < 4; pipe_stage = pipe_stage + 1) begin : g_filter_fraction
            reg [7:0] data_r;
            wire [7:0] data_w;
            assign filter_fraction_r[pipe_stage] = data_r;
            if (pipe_stage == 0) begin : g_first
                assign data_w = return_fraction_w;
            end else begin : g_previous
                assign data_w = filter_fraction_r[pipe_stage-1];
            end
            always @(posedge clk_i) begin
                data_r <= data_w;
            end
        end
        for (pipe_stage = 0; pipe_stage < 3; pipe_stage = pipe_stage + 1) begin : g_nearest
            reg [127:0] data_r;
            wire [127:0] data_w;
            assign nearest_r[pipe_stage] = data_r;
            if (pipe_stage == 0) begin : g_first
                assign data_w = {expanded_w[3], expanded_w[2], expanded_w[1], expanded_w[0]};
            end else begin : g_previous
                assign data_w = nearest_r[pipe_stage-1];
            end
            always @(posedge clk_i) begin
                data_r <= data_w;
            end
        end
    endgenerate
endmodule
