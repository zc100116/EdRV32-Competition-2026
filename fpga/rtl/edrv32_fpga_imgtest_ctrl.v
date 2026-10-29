// File: edrv32_fpga_imgtest_ctrl.v
// Spec: Task B3-9; SoC 7.3 R1-R5; VIN 4.3; PIX 2.6; GEO 2.6; DISP 5.3.
// Description: CPU-free APB configuration, Surface ownership and GEO descriptors.
//              Keep one pending DISP submission; skip new frames while it is pending.
// Clock domain: clk_mem (125 MHz); gateway clk_sys is also tied to clk_mem.
module edrv32_fpga_imgtest_ctrl (
    // Clock and domain reset.
    input wire clk_i,
    input wire rst_n_i,

    // Startup readiness and debounced key press pulses.
    input wire ready_i,
    input wire [2:0] key_press_i,

    // Media APB master (SoC slot numbering).
    output wire [11:0] apb_paddr_o,
    output wire [15:0] apb_psel_o,
    output wire apb_penable_o,
    output reg apb_pwrite_o,
    output reg [31:0] apb_pwdata_o,
    output wire [3:0] apb_pstrb_o,
    input wire [15:0] apb_pready_i,
    input wire [511:0] apb_prdata_i,

    // Gateway AXI64 write master; the unused read direction is tied off in the top.
    output wire [31:0] gw_awaddr_o,
    output wire gw_awvalid_o,
    input wire gw_awready_i,
    output wire [63:0] gw_wdata_o,
    output wire [7:0] gw_wstrb_o,
    output wire gw_wvalid_o,
    input wire gw_wready_i,
    input wire gw_bvalid_i,
    output wire gw_bready_o,

    // Board indicators.
    output reg frame_o,
    output reg error_o
);
    /* verilator lint_off UNUSEDPARAM */
    `include "edrv32_soc_map.vh"
    `include "regs/edrv32_vin_regs.vh"
    `include "regs/edrv32_pix_regs.vh"
    `include "regs/edrv32_geo_regs.vh"
    `include "regs/edrv32_disp_regs.vh"
    /* verilator lint_on UNUSEDPARAM */

    // Physical DDR allocations from design b2-software 3.3; only gateway uses an alias.
    localparam [31:0] IMAGE_BASE = 32'h06000000;
    localparam [31:0] GEO_BASE = 32'h07000000;
    localparam [31:0] IMAGE_SPACING = 32'h00200000;
    localparam [31:0] DESC_BASE = 32'h00090000;
    localparam [31:0] STRIDE = 32'd2560;
    localparam [31:0] SIZE = (32'd720 << EDRV32_VIN_CAM0_SIZE_HEIGHT_POS) | 32'd1280;

    localparam [5:0] S_WAIT = 6'd0;
    localparam [5:0] S_INIT = 6'd1;
    localparam [5:0] S_GAMMA = 6'd2;
    localparam [5:0] S_DISP_STAT = 6'd3;
    localparam [5:0] S_DISP_CLEAR = 6'd4;
    localparam [5:0] S_DISP_REL = 6'd5;
    localparam [5:0] S_DISP_BUSY = 6'd6;
    localparam [5:0] S_DISP_CUR = 6'd7;
    localparam [5:0] S_VIN_STAT = 6'd8;
    localparam [5:0] S_VIN_CLEAR = 6'd9;
    localparam [5:0] S_VIN_INFO = 6'd10;
    localparam [5:0] S_VIN_LOCK = 6'd11;
    localparam [5:0] S_VIN_ROUTE = 6'd12;
    localparam [5:0] S_SUBMIT = 6'd13;
    localparam [5:0] S_DISPLAY_ENABLE = 6'd14;
    localparam [5:0] S_GEO_STAT = 6'd15;
    localparam [5:0] S_GEO_CLEAR = 6'd16;
    localparam [5:0] S_GEO_RELEASE = 6'd17;
    localparam [5:0] S_GEO_BUSY = 6'd18;
    localparam [5:0] S_PIX_STAT = 6'd19;
    localparam [5:0] S_CONFIG_CHECK = 6'd20;
    localparam [5:0] S_CONFIG_STOP = 6'd21;
    localparam [5:0] S_CONFIG_IDLE = 6'd22;
    localparam [5:0] S_CONFIG_BC = 6'd23;
    localparam [5:0] S_CONFIG_THRESH = 6'd24;
    localparam [5:0] S_CONFIG_PIX = 6'd25;
    localparam [5:0] S_CONFIG_CAM = 6'd26;
    localparam [5:0] S_CONFIG_START = 6'd27;
    localparam [5:0] S_DESC_AW = 6'd28;
    localparam [5:0] S_DESC_W = 6'd29;
    localparam [5:0] S_DESC_B = 6'd30;
    localparam [5:0] S_GEO_START = 6'd31;
    reg [5:0] state_r;
    reg [4:0] init_idx_r;
    reg [7:0] gamma_idx_r;
    reg [3:0] desc_idx_r;
    reg apb_enable_r;
    reg [2:0] pix_mode_r;
    reg [1:0] geo_mode_r;
    reg camera_r;
    reg [2:0] applied_pix_r;
    reg applied_camera_r;
    reg [2:0] cfg_pix_r;
    reg cfg_camera_r;
    reg cfg_active_r;
    reg [1:0] job_geo_r;
    reg [3:0] vin_busy_r;
    reg [1:0] geo_busy_r;
    reg [1:0] source_r;
    reg target_r;
    reg geo_active_r;
    reg pending_r;
    reg display_enabled_r;
    reg [31:0] submitted_r;
    reg [31:0] disp_stat_r;
    reg [31:0] addr_w;
    wire [15:0] unused_addr_high_w = addr_w[31:16];
    reg command_w;
    reg [31:0] desc_data_w;
    wire [31:0] read_w = apb_prdata_i[32 * addr_w[15:12] +: 32];
    wire complete_w = command_w && apb_enable_r && apb_pready_i[addr_w[15:12]];
    wire [31:0] source_addr_w = IMAGE_BASE + {30'b0, source_r} * IMAGE_SPACING;
    wire [31:0] target_addr_w = GEO_BASE + {31'b0, target_r} * IMAGE_SPACING;
    wire [31:0] matrix_w = job_geo_r == 2'd1 ? 32'hffff0000 :
        (job_geo_r == 2'd2 ? 32'h00020000 : 32'h00008000);
    wire [31:0] tx_w = job_geo_r == 2'd1 ? 32'h04ff0000 :
        (job_geo_r == 2'd2 ? 32'hfd800000 : 32'h01400000);
    wire [31:0] ty_w = job_geo_r == 2'd1 ? 32'h02cf0000 :
        (job_geo_r == 2'd2 ? 32'hfe980000 : 32'h00b40000);

    function [31:0] pix_cfg;
        input [2:0] mode_i;
        begin
            pix_cfg = EDRV32_PIX_CFG_GAMMA_BANK_MASK;
            case (mode_i)
                3'd1: pix_cfg = pix_cfg | EDRV32_PIX_CFG_BC_EN_MASK;
                3'd2: pix_cfg = pix_cfg | EDRV32_PIX_CFG_GAMMA_EN_MASK;
                3'd3: pix_cfg = pix_cfg | (32'd2 << EDRV32_PIX_CFG_S1_OP_POS);
                3'd4: pix_cfg = pix_cfg | (32'd4 << EDRV32_PIX_CFG_S1_OP_POS) |
                    EDRV32_PIX_CFG_GRAY_EN_MASK;
                default: pix_cfg = pix_cfg;
            endcase
        end
    endfunction

    function [7:0] gamma_value;
        input [7:0] index_i;
        begin
            gamma_value = 8'd0;
            case (index_i)
                8'd0: gamma_value = 8'd0;
                8'd1: gamma_value = 8'd2;
                8'd2: gamma_value = 8'd4;
                8'd3: gamma_value = 8'd6;
                8'd4: gamma_value = 8'd8;
                8'd5: gamma_value = 8'd10;
                8'd6: gamma_value = 8'd12;
                8'd7: gamma_value = 8'd14;
                8'd8: gamma_value = 8'd16;
                8'd9: gamma_value = 8'd18;
                8'd10: gamma_value = 8'd20;
                8'd11: gamma_value = 8'd22;
                8'd12: gamma_value = 8'd24;
                8'd13: gamma_value = 8'd26;
                8'd14: gamma_value = 8'd28;
                8'd15: gamma_value = 8'd30;
                8'd16: gamma_value = 8'd31;
                8'd17: gamma_value = 8'd33;
                8'd18: gamma_value = 8'd35;
                8'd19: gamma_value = 8'd37;
                8'd20: gamma_value = 8'd39;
                8'd21: gamma_value = 8'd41;
                8'd22: gamma_value = 8'd43;
                8'd23: gamma_value = 8'd44;
                8'd24: gamma_value = 8'd46;
                8'd25: gamma_value = 8'd48;
                8'd26: gamma_value = 8'd50;
                8'd27: gamma_value = 8'd52;
                8'd28: gamma_value = 8'd53;
                8'd29: gamma_value = 8'd55;
                8'd30: gamma_value = 8'd57;
                8'd31: gamma_value = 8'd59;
                8'd32: gamma_value = 8'd60;
                8'd33: gamma_value = 8'd62;
                8'd34: gamma_value = 8'd64;
                8'd35: gamma_value = 8'd66;
                8'd36: gamma_value = 8'd67;
                8'd37: gamma_value = 8'd69;
                8'd38: gamma_value = 8'd71;
                8'd39: gamma_value = 8'd73;
                8'd40: gamma_value = 8'd74;
                8'd41: gamma_value = 8'd76;
                8'd42: gamma_value = 8'd78;
                8'd43: gamma_value = 8'd79;
                8'd44: gamma_value = 8'd81;
                8'd45: gamma_value = 8'd83;
                8'd46: gamma_value = 8'd84;
                8'd47: gamma_value = 8'd86;
                8'd48: gamma_value = 8'd87;
                8'd49: gamma_value = 8'd89;
                8'd50: gamma_value = 8'd91;
                8'd51: gamma_value = 8'd92;
                8'd52: gamma_value = 8'd94;
                8'd53: gamma_value = 8'd95;
                8'd54: gamma_value = 8'd97;
                8'd55: gamma_value = 8'd99;
                8'd56: gamma_value = 8'd100;
                8'd57: gamma_value = 8'd102;
                8'd58: gamma_value = 8'd103;
                8'd59: gamma_value = 8'd105;
                8'd60: gamma_value = 8'd106;
                8'd61: gamma_value = 8'd108;
                8'd62: gamma_value = 8'd109;
                8'd63: gamma_value = 8'd111;
                8'd64: gamma_value = 8'd112;
                8'd65: gamma_value = 8'd114;
                8'd66: gamma_value = 8'd115;
                8'd67: gamma_value = 8'd117;
                8'd68: gamma_value = 8'd118;
                8'd69: gamma_value = 8'd120;
                8'd70: gamma_value = 8'd121;
                8'd71: gamma_value = 8'd123;
                8'd72: gamma_value = 8'd124;
                8'd73: gamma_value = 8'd126;
                8'd74: gamma_value = 8'd127;
                8'd75: gamma_value = 8'd128;
                8'd76: gamma_value = 8'd130;
                8'd77: gamma_value = 8'd131;
                8'd78: gamma_value = 8'd133;
                8'd79: gamma_value = 8'd134;
                8'd80: gamma_value = 8'd135;
                8'd81: gamma_value = 8'd137;
                8'd82: gamma_value = 8'd138;
                8'd83: gamma_value = 8'd139;
                8'd84: gamma_value = 8'd141;
                8'd85: gamma_value = 8'd142;
                8'd86: gamma_value = 8'd143;
                8'd87: gamma_value = 8'd145;
                8'd88: gamma_value = 8'd146;
                8'd89: gamma_value = 8'd147;
                8'd90: gamma_value = 8'd149;
                8'd91: gamma_value = 8'd150;
                8'd92: gamma_value = 8'd151;
                8'd93: gamma_value = 8'd153;
                8'd94: gamma_value = 8'd154;
                8'd95: gamma_value = 8'd155;
                8'd96: gamma_value = 8'd156;
                8'd97: gamma_value = 8'd158;
                8'd98: gamma_value = 8'd159;
                8'd99: gamma_value = 8'd160;
                8'd100: gamma_value = 8'd161;
                8'd101: gamma_value = 8'd162;
                8'd102: gamma_value = 8'd164;
                8'd103: gamma_value = 8'd165;
                8'd104: gamma_value = 8'd166;
                8'd105: gamma_value = 8'd167;
                8'd106: gamma_value = 8'd168;
                8'd107: gamma_value = 8'd170;
                8'd108: gamma_value = 8'd171;
                8'd109: gamma_value = 8'd172;
                8'd110: gamma_value = 8'd173;
                8'd111: gamma_value = 8'd174;
                8'd112: gamma_value = 8'd175;
                8'd113: gamma_value = 8'd176;
                8'd114: gamma_value = 8'd178;
                8'd115: gamma_value = 8'd179;
                8'd116: gamma_value = 8'd180;
                8'd117: gamma_value = 8'd181;
                8'd118: gamma_value = 8'd182;
                8'd119: gamma_value = 8'd183;
                8'd120: gamma_value = 8'd184;
                8'd121: gamma_value = 8'd185;
                8'd122: gamma_value = 8'd186;
                8'd123: gamma_value = 8'd187;
                8'd124: gamma_value = 8'd188;
                8'd125: gamma_value = 8'd189;
                8'd126: gamma_value = 8'd190;
                8'd127: gamma_value = 8'd191;
                8'd128: gamma_value = 8'd192;
                8'd129: gamma_value = 8'd193;
                8'd130: gamma_value = 8'd194;
                8'd131: gamma_value = 8'd195;
                8'd132: gamma_value = 8'd196;
                8'd133: gamma_value = 8'd197;
                8'd134: gamma_value = 8'd198;
                8'd135: gamma_value = 8'd199;
                8'd136: gamma_value = 8'd200;
                8'd137: gamma_value = 8'd201;
                8'd138: gamma_value = 8'd202;
                8'd139: gamma_value = 8'd203;
                8'd140: gamma_value = 8'd204;
                8'd141: gamma_value = 8'd205;
                8'd142: gamma_value = 8'd205;
                8'd143: gamma_value = 8'd206;
                8'd144: gamma_value = 8'd207;
                8'd145: gamma_value = 8'd208;
                8'd146: gamma_value = 8'd209;
                8'd147: gamma_value = 8'd210;
                8'd148: gamma_value = 8'd211;
                8'd149: gamma_value = 8'd211;
                8'd150: gamma_value = 8'd212;
                8'd151: gamma_value = 8'd213;
                8'd152: gamma_value = 8'd214;
                8'd153: gamma_value = 8'd215;
                8'd154: gamma_value = 8'd215;
                8'd155: gamma_value = 8'd216;
                8'd156: gamma_value = 8'd217;
                8'd157: gamma_value = 8'd218;
                8'd158: gamma_value = 8'd219;
                8'd159: gamma_value = 8'd219;
                8'd160: gamma_value = 8'd220;
                8'd161: gamma_value = 8'd221;
                8'd162: gamma_value = 8'd222;
                8'd163: gamma_value = 8'd222;
                8'd164: gamma_value = 8'd223;
                8'd165: gamma_value = 8'd224;
                8'd166: gamma_value = 8'd224;
                8'd167: gamma_value = 8'd225;
                8'd168: gamma_value = 8'd226;
                8'd169: gamma_value = 8'd226;
                8'd170: gamma_value = 8'd227;
                8'd171: gamma_value = 8'd228;
                8'd172: gamma_value = 8'd228;
                8'd173: gamma_value = 8'd229;
                8'd174: gamma_value = 8'd230;
                8'd175: gamma_value = 8'd230;
                8'd176: gamma_value = 8'd231;
                8'd177: gamma_value = 8'd232;
                8'd178: gamma_value = 8'd232;
                8'd179: gamma_value = 8'd233;
                8'd180: gamma_value = 8'd233;
                8'd181: gamma_value = 8'd234;
                8'd182: gamma_value = 8'd235;
                8'd183: gamma_value = 8'd235;
                8'd184: gamma_value = 8'd236;
                8'd185: gamma_value = 8'd236;
                8'd186: gamma_value = 8'd237;
                8'd187: gamma_value = 8'd237;
                8'd188: gamma_value = 8'd238;
                8'd189: gamma_value = 8'd238;
                8'd190: gamma_value = 8'd239;
                8'd191: gamma_value = 8'd239;
                8'd192: gamma_value = 8'd240;
                8'd193: gamma_value = 8'd240;
                8'd194: gamma_value = 8'd241;
                8'd195: gamma_value = 8'd241;
                8'd196: gamma_value = 8'd242;
                8'd197: gamma_value = 8'd242;
                8'd198: gamma_value = 8'd243;
                8'd199: gamma_value = 8'd243;
                8'd200: gamma_value = 8'd244;
                8'd201: gamma_value = 8'd244;
                8'd202: gamma_value = 8'd244;
                8'd203: gamma_value = 8'd245;
                8'd204: gamma_value = 8'd245;
                8'd205: gamma_value = 8'd246;
                8'd206: gamma_value = 8'd246;
                8'd207: gamma_value = 8'd246;
                8'd208: gamma_value = 8'd247;
                8'd209: gamma_value = 8'd247;
                8'd210: gamma_value = 8'd248;
                8'd211: gamma_value = 8'd248;
                8'd212: gamma_value = 8'd248;
                8'd213: gamma_value = 8'd249;
                8'd214: gamma_value = 8'd249;
                8'd215: gamma_value = 8'd249;
                8'd216: gamma_value = 8'd250;
                8'd217: gamma_value = 8'd250;
                8'd218: gamma_value = 8'd250;
                8'd219: gamma_value = 8'd250;
                8'd220: gamma_value = 8'd251;
                8'd221: gamma_value = 8'd251;
                8'd222: gamma_value = 8'd251;
                8'd223: gamma_value = 8'd251;
                8'd224: gamma_value = 8'd252;
                8'd225: gamma_value = 8'd252;
                8'd226: gamma_value = 8'd252;
                8'd227: gamma_value = 8'd252;
                8'd228: gamma_value = 8'd253;
                8'd229: gamma_value = 8'd253;
                8'd230: gamma_value = 8'd253;
                8'd231: gamma_value = 8'd253;
                8'd232: gamma_value = 8'd253;
                8'd233: gamma_value = 8'd254;
                8'd234: gamma_value = 8'd254;
                8'd235: gamma_value = 8'd254;
                8'd236: gamma_value = 8'd254;
                8'd237: gamma_value = 8'd254;
                8'd238: gamma_value = 8'd254;
                8'd239: gamma_value = 8'd254;
                8'd240: gamma_value = 8'd255;
                8'd241: gamma_value = 8'd255;
                8'd242: gamma_value = 8'd255;
                8'd243: gamma_value = 8'd255;
                8'd244: gamma_value = 8'd255;
                8'd245: gamma_value = 8'd255;
                8'd246: gamma_value = 8'd255;
                8'd247: gamma_value = 8'd255;
                8'd248: gamma_value = 8'd255;
                8'd249: gamma_value = 8'd255;
                8'd250: gamma_value = 8'd255;
                8'd251: gamma_value = 8'd255;
                8'd252: gamma_value = 8'd255;
                8'd253: gamma_value = 8'd255;
                8'd254: gamma_value = 8'd255;
                8'd255: gamma_value = 8'd255;
                default: gamma_value = 8'd0;
            endcase
        end
    endfunction

    assign apb_paddr_o = addr_w[11:0];
    assign apb_psel_o = command_w ? (16'b1 << addr_w[15:12]) : 16'b0;
    assign apb_penable_o = apb_enable_r;
    assign apb_pstrb_o = 4'hf;
    assign gw_awaddr_o = EDRV32_DDR_UNCACHED_BASE + DESC_BASE + {26'b0, desc_idx_r, 2'b0};
    assign gw_awvalid_o = state_r == S_DESC_AW;
    assign gw_wdata_o = desc_idx_r[0] ? {desc_data_w, 32'b0} : {32'b0, desc_data_w};
    assign gw_wstrb_o = desc_idx_r[0] ? 8'hf0 : 8'h0f;
    assign gw_wvalid_o = state_r == S_DESC_W;
    assign gw_bready_o = state_r == S_DESC_B;

    // GEO 2.6: every word, including reserved words, is written before DOORBELL.
    always @(*) begin
        desc_data_w = 32'b0;
        case ({26'b0, desc_idx_r, 2'b0})
            EDRV32_GEO_DESC_SRC_BASE_OFFSET: desc_data_w = source_addr_w;
            EDRV32_GEO_DESC_SRC_STRIDE_OFFSET: desc_data_w = STRIDE;
            EDRV32_GEO_DESC_SRC_W_OFFSET: desc_data_w = SIZE;
            EDRV32_GEO_DESC_DST_BASE_OFFSET: desc_data_w = target_addr_w;
            EDRV32_GEO_DESC_DST_STRIDE_OFFSET: desc_data_w = STRIDE;
            EDRV32_GEO_DESC_RECT_W_OFFSET: desc_data_w = SIZE;
            EDRV32_GEO_DESC_A_OFFSET: desc_data_w = matrix_w;
            EDRV32_GEO_DESC_TX_OFFSET: desc_data_w = tx_w;
            EDRV32_GEO_DESC_D_OFFSET: desc_data_w = matrix_w;
            EDRV32_GEO_DESC_TY_OFFSET: desc_data_w = ty_w;
            default: desc_data_w = 32'b0;
        endcase
    end

    always @(*) begin
        command_w = 1'b1;
        addr_w = 32'b0;
        apb_pwrite_o = 1'b1;
        apb_pwdata_o = 32'b0;
        case (state_r)
            S_INIT: begin
                case (init_idx_r)
                    5'd0: begin
                        addr_w = EDRV32_PIX_BASE +
                            EDRV32_PIX_CTRL_OFFSET;
                        apb_pwdata_o = EDRV32_PIX_CTRL_ENABLE_MASK;
                    end
                    5'd1: begin
                        addr_w = EDRV32_PIX_BASE +
                            EDRV32_PIX_BC_OFFSET;
                        apb_pwdata_o = 32'd256;
                    end
                    5'd2: begin
                        addr_w = EDRV32_PIX_BASE +
                            EDRV32_PIX_THRESH_OFFSET;
                        apb_pwdata_o = 32'd128;
                    end
                    5'd3: begin
                        addr_w = EDRV32_PIX_BASE +
                            EDRV32_PIX_CFG_OFFSET;
                        apb_pwdata_o = EDRV32_PIX_CFG_GAMMA_BANK_MASK;
                    end
                    5'd4: begin
                        addr_w = EDRV32_VIN_BASE +
                            EDRV32_VIN_CAM0_SIZE_OFFSET;
                        apb_pwdata_o = SIZE;
                    end
                    5'd5: begin
                        addr_w = EDRV32_VIN_BASE +
                            EDRV32_VIN_CAM1_SIZE_OFFSET;
                        apb_pwdata_o = SIZE;
                    end
                    5'd6: begin
                        addr_w = EDRV32_VIN_BASE +
                            EDRV32_VIN_CH_SURF_BASE_OFFSET +
                            32'd0 * EDRV32_VIN_CH_SURF_BASE_S_STRIDE;
                        apb_pwdata_o = IMAGE_BASE + 32'd0 * IMAGE_SPACING;
                    end
                    5'd7: begin
                        addr_w = EDRV32_VIN_BASE +
                            EDRV32_VIN_CH_SURF_BASE_OFFSET +
                            32'd1 * EDRV32_VIN_CH_SURF_BASE_S_STRIDE;
                        apb_pwdata_o = IMAGE_BASE + 32'd1 * IMAGE_SPACING;
                    end
                    5'd8: begin
                        addr_w = EDRV32_VIN_BASE +
                            EDRV32_VIN_CH_SURF_BASE_OFFSET +
                            32'd2 * EDRV32_VIN_CH_SURF_BASE_S_STRIDE;
                        apb_pwdata_o = IMAGE_BASE + 32'd2 * IMAGE_SPACING;
                    end
                    5'd9: begin
                        addr_w = EDRV32_VIN_BASE +
                            EDRV32_VIN_CH_SURF_BASE_OFFSET +
                            32'd3 * EDRV32_VIN_CH_SURF_BASE_S_STRIDE;
                        apb_pwdata_o = IMAGE_BASE + 32'd3 * IMAGE_SPACING;
                    end
                    5'd10: begin
                        addr_w = EDRV32_VIN_BASE +
                            EDRV32_VIN_CH_STRIDE_OFFSET;
                        apb_pwdata_o = STRIDE;
                    end
                    5'd11: begin
                        addr_w = EDRV32_VIN_BASE +
                            EDRV32_VIN_CH_SLOT_BUSY_OFFSET;
                        apb_pwdata_o = 32'b0;
                    end
                    5'd12: begin
                        addr_w = EDRV32_VIN_BASE +
                            EDRV32_VIN_CH_CTRL_OFFSET;
                        apb_pwdata_o =
                            EDRV32_VIN_CH_CTRL_EN_MASK | (32'd4 << EDRV32_VIN_CH_CTRL_RING_N_POS);
                    end
                    5'd13: begin
                        addr_w = EDRV32_DISP_BASE +
                            EDRV32_DISP_LAYER_CTRL_OFFSET;
                        apb_pwdata_o = EDRV32_DISP_LAYER_CTRL_L0_EN_MASK;
                    end
                    5'd14: begin
                        addr_w = EDRV32_DISP_BASE +
                            EDRV32_DISP_L0_SCROLL_OFFSET;
                        apb_pwdata_o = 32'b0;
                    end
                    5'd15: begin
                        addr_w = EDRV32_DISP_BASE +
                            EDRV32_DISP_STRIDE_OFFSET;
                        apb_pwdata_o = STRIDE;
                    end
                    5'd16: begin
                        addr_w = EDRV32_GEO_BASE +
                            EDRV32_GEO_CTRL_OFFSET;
                        apb_pwdata_o = EDRV32_GEO_CTRL_ENABLE_MASK;
                    end
                    5'd17: begin
                        addr_w = EDRV32_GEO_BASE +
                            EDRV32_GEO_DESC_BASE_OFFSET;
                        apb_pwdata_o = DESC_BASE;
                    end
                    5'd18: begin
                        addr_w = EDRV32_GEO_BASE +
                            EDRV32_GEO_DESC_COUNT_OFFSET;
                        apb_pwdata_o = 32'd1;
                    end
                    5'd19: begin
                        addr_w = EDRV32_VIN_BASE +
                            EDRV32_VIN_CTRL_OFFSET;
                        apb_pwdata_o = EDRV32_VIN_CTRL_ENABLE_MASK;
                    end
                    default: command_w = 1'b0;
                endcase
            end
            S_GAMMA: begin
                addr_w = EDRV32_PIX_BASE + EDRV32_PIX_GAMMA_WR_OFFSET;
                apb_pwdata_o = EDRV32_PIX_GAMMA_WR_BANK_MASK | {24'b0, gamma_idx_r} |
                    ({24'b0, gamma_value(gamma_idx_r)} << EDRV32_PIX_GAMMA_WR_VALUE_POS);
            end
            S_DISP_STAT: begin
                addr_w = EDRV32_DISP_BASE + EDRV32_DISP_IRQ_STAT_OFFSET;
                apb_pwrite_o = 1'b0;
            end
            S_DISP_CLEAR: begin
                addr_w = EDRV32_DISP_BASE + EDRV32_DISP_IRQ_STAT_OFFSET;
                apb_pwdata_o = disp_stat_r & (EDRV32_DISP_IRQ_STAT_FRAME_MASK |
                    EDRV32_DISP_IRQ_STAT_SWITCH_MASK);
            end
            S_DISP_REL: begin
                addr_w = EDRV32_DISP_BASE + EDRV32_DISP_REL_BASE_OFFSET;
                apb_pwrite_o = 1'b0;
            end
            S_DISP_BUSY, S_VIN_LOCK, S_GEO_BUSY: begin
                addr_w = EDRV32_VIN_BASE + EDRV32_VIN_CH_SLOT_BUSY_OFFSET;
                apb_pwdata_o = {28'b0, vin_busy_r};
            end
            S_DISP_CUR: begin
                addr_w = EDRV32_DISP_BASE + EDRV32_DISP_CUR_BASE_OFFSET;
                apb_pwrite_o = 1'b0;
            end
            S_VIN_STAT: begin
                addr_w = EDRV32_VIN_BASE + EDRV32_VIN_IRQ_STAT_OFFSET;
                apb_pwrite_o = 1'b0;
            end
            S_VIN_CLEAR: begin
                addr_w = EDRV32_VIN_BASE + EDRV32_VIN_IRQ_STAT_OFFSET;
                apb_pwdata_o = EDRV32_VIN_IRQ_STAT_FRAME_MASK;
            end
            S_VIN_INFO: begin
                addr_w = EDRV32_VIN_BASE + EDRV32_VIN_CH_DONE_INFO_OFFSET;
                apb_pwrite_o = 1'b0;
            end
            S_SUBMIT: begin
                addr_w = EDRV32_DISP_BASE + EDRV32_DISP_NEXT_BASE_OFFSET;
                apb_pwdata_o = submitted_r;
            end
            S_DISPLAY_ENABLE: begin
                addr_w = EDRV32_DISP_BASE + EDRV32_DISP_CTRL_OFFSET;
                apb_pwdata_o = EDRV32_DISP_CTRL_ENABLE_MASK;
            end
            S_GEO_STAT: begin
                addr_w = EDRV32_GEO_BASE + EDRV32_GEO_IRQ_STAT_OFFSET;
                apb_pwrite_o = 1'b0;
            end
            S_GEO_CLEAR: begin
                addr_w = EDRV32_GEO_BASE + EDRV32_GEO_IRQ_STAT_OFFSET;
                apb_pwdata_o = EDRV32_GEO_IRQ_STAT_DONE_MASK;
            end
            S_PIX_STAT: begin
                addr_w = EDRV32_PIX_BASE + EDRV32_PIX_IRQ_STAT_OFFSET;
                apb_pwrite_o = 1'b0;
            end
            S_CONFIG_STOP: addr_w = EDRV32_VIN_BASE + EDRV32_VIN_CTRL_OFFSET;
            S_CONFIG_IDLE: begin
                addr_w = EDRV32_VIN_BASE + EDRV32_VIN_STATUS_OFFSET;
                apb_pwrite_o = 1'b0;
            end
            S_CONFIG_BC: begin
                addr_w = EDRV32_PIX_BASE + EDRV32_PIX_BC_OFFSET;
                apb_pwdata_o = cfg_pix_r == 3'd1 ?
                    ((32'd24 << EDRV32_PIX_BC_BRIGHTNESS_POS) | 32'd320) : 32'd256;
            end
            S_CONFIG_THRESH: begin
                addr_w = EDRV32_PIX_BASE + EDRV32_PIX_THRESH_OFFSET;
                apb_pwdata_o = 32'd128;
            end
            S_CONFIG_PIX: begin
                addr_w = EDRV32_PIX_BASE + EDRV32_PIX_CFG_OFFSET;
                apb_pwdata_o = pix_cfg(cfg_pix_r);
            end
            S_CONFIG_CAM: begin
                addr_w = EDRV32_VIN_BASE + EDRV32_VIN_CH_CTRL_OFFSET;
                apb_pwdata_o = EDRV32_VIN_CH_CTRL_EN_MASK |
                    (32'd4 << EDRV32_VIN_CH_CTRL_RING_N_POS) |
                    ({31'b0, cfg_camera_r} << EDRV32_VIN_CH_CTRL_SRC_POS);
            end
            S_CONFIG_START: begin
                addr_w = EDRV32_VIN_BASE + EDRV32_VIN_CTRL_OFFSET;
                apb_pwdata_o = EDRV32_VIN_CTRL_ENABLE_MASK;
            end
            S_GEO_START: begin
                addr_w = EDRV32_GEO_BASE + EDRV32_GEO_DOORBELL_OFFSET;
                apb_pwdata_o = 32'd1;
            end
            default: command_w = 1'b0;
        endcase
    end

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            apb_enable_r <= 1'b0;
        end else if (!command_w || complete_w) begin
            apb_enable_r <= 1'b0;
        end else begin
            apb_enable_r <= 1'b1;
        end
    end

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            pix_mode_r <= 3'd0;
            geo_mode_r <= 2'd0;
            camera_r <= 1'b0;
        end else begin
            if (key_press_i[0]) pix_mode_r <= pix_mode_r == 3'd4 ? 3'd0 : pix_mode_r + 1'b1;
            if (key_press_i[1]) geo_mode_r <= geo_mode_r + 1'b1;
            if (key_press_i[2]) camera_r <= !camera_r;
        end
    end

    // IRQ_STAT.ERROR stays set; only completion flags are W1C, without recovery.
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            error_o <= 1'b0;
            frame_o <= 1'b0;
        end else if (complete_w) begin
            if (state_r == S_VIN_STAT)
                error_o <= error_o || |(read_w & EDRV32_VIN_IRQ_STAT_ERROR_MASK);
            if (state_r == S_PIX_STAT)
                error_o <= error_o || |(read_w & EDRV32_PIX_IRQ_STAT_ERROR_MASK);
            if (state_r == S_GEO_STAT)
                error_o <= error_o || |(read_w & EDRV32_GEO_IRQ_STAT_ERROR_MASK);
            if (state_r == S_DISP_STAT) begin
                error_o <= error_o || |(read_w & EDRV32_DISP_IRQ_STAT_ERROR_MASK);
                if (|(read_w & EDRV32_DISP_IRQ_STAT_FRAME_MASK)) frame_o <= !frame_o;
            end
        end
    end

    // Data payload is captured only when its associated command/job becomes live.
    always @(posedge clk_i) begin
        if (state_r == S_DISP_STAT && complete_w) disp_stat_r <= read_w;
        if (state_r == S_CONFIG_CHECK && !cfg_active_r) begin
            cfg_pix_r <= pix_mode_r;
            cfg_camera_r <= camera_r;
        end
        if (state_r == S_VIN_INFO && complete_w && !pending_r && !geo_active_r &&
            (geo_mode_r == 2'd0 || geo_busy_r != 2'b11)) begin
            source_r <= read_w[1:0];
            job_geo_r <= geo_mode_r;
            target_r <= geo_busy_r[0];
            submitted_r <= IMAGE_BASE + (read_w & EDRV32_VIN_CH_DONE_INFO_SLOT_MASK) *
                IMAGE_SPACING;
        end
        if (state_r == S_GEO_RELEASE) submitted_r <= target_addr_w;
    end

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            state_r <= S_WAIT;
            init_idx_r <= 5'd0;
            gamma_idx_r <= 8'd0;
            desc_idx_r <= 4'd0;
            applied_pix_r <= 3'd0;
            applied_camera_r <= 1'b0;
            cfg_active_r <= 1'b0;
            vin_busy_r <= 4'b0;
            geo_busy_r <= 2'b0;
            geo_active_r <= 1'b0;
            pending_r <= 1'b0;
            display_enabled_r <= 1'b0;
        end else begin
            case (state_r)
                S_WAIT: if (ready_i) state_r <= S_GAMMA;
                S_GAMMA: begin
                    if (complete_w) begin
                        gamma_idx_r <= gamma_idx_r + 1'b1;
                        if (gamma_idx_r == 8'd255) state_r <= S_INIT;
                    end
                end
                S_INIT: begin
                    if (complete_w) begin
                        if (init_idx_r == 5'd19) begin
                            state_r <= S_DISP_STAT;
                        end else begin
                            init_idx_r <= init_idx_r + 1'b1;
                        end
                    end
                end
                S_DISP_STAT: begin
                    if (complete_w) begin
                        if (|(read_w & EDRV32_DISP_IRQ_STAT_FRAME_MASK)) begin
                            state_r <= S_DISP_CLEAR;
                        end else begin
                            state_r <= S_VIN_STAT;
                        end
                    end
                end
                S_DISP_CLEAR: begin
                    if (complete_w) begin
                        if (|(disp_stat_r & EDRV32_DISP_IRQ_STAT_SWITCH_MASK)) begin
                            state_r <= S_DISP_REL;
                        end else begin
                            state_r <= S_DISP_CUR;
                        end
                    end
                end
                S_DISP_REL: begin
                    if (complete_w) begin
                        // R3: only REL_BASE releases the display consumer's reference.
                        if (read_w >= IMAGE_BASE && read_w < IMAGE_BASE + 4 * IMAGE_SPACING)
                            vin_busy_r[read_w[22:21]] <= 1'b0;
                        if (read_w >= GEO_BASE && read_w < GEO_BASE + 2 * IMAGE_SPACING)
                            geo_busy_r[read_w[21]] <= 1'b0;
                        state_r <= S_DISP_BUSY;
                    end
                end
                S_DISP_BUSY: if (complete_w) state_r <= S_DISP_CUR;
                S_DISP_CUR: begin
                    if (complete_w) begin
                        if (pending_r && read_w == submitted_r) pending_r <= 1'b0;
                        state_r <= S_VIN_STAT;
                    end
                end
                S_VIN_STAT: begin
                    if (complete_w) begin
                        state_r <= |(read_w & EDRV32_VIN_IRQ_STAT_FRAME_MASK) ?
                            S_VIN_CLEAR : S_GEO_STAT;
                    end
                end
                S_VIN_CLEAR: if (complete_w) state_r <= S_VIN_INFO;
                S_VIN_INFO: begin
                    if (complete_w) begin
                        // No ready queue: a busy consumer causes this completed frame to be skipped.
                        if (!pending_r && !geo_active_r &&
                            (geo_mode_r == 2'd0 || geo_busy_r != 2'b11)) begin
                            vin_busy_r[read_w[1:0]] <= 1'b1;
                            state_r <= S_VIN_LOCK;
                        end else begin
                            state_r <= S_GEO_STAT;
                        end
                    end
                end
                S_VIN_LOCK: if (complete_w) state_r <= S_VIN_ROUTE;
                S_VIN_ROUTE: begin
                    if (job_geo_r == 2'd0) begin
                        pending_r <= 1'b1;
                        state_r <= S_SUBMIT;
                    end else begin
                        geo_busy_r[target_r] <= 1'b1;
                        geo_active_r <= 1'b1;
                        desc_idx_r <= 4'd0;
                        state_r <= S_DESC_AW;
                    end
                end
                S_SUBMIT: begin
                    if (complete_w) begin
                        state_r <= display_enabled_r ? S_GEO_STAT : S_DISPLAY_ENABLE;
                    end
                end
                S_DISPLAY_ENABLE: begin
                    if (complete_w) begin
                        display_enabled_r <= 1'b1;
                        state_r <= S_GEO_STAT;
                    end
                end
                S_DESC_AW: if (gw_awready_i) state_r <= S_DESC_W;
                S_DESC_W: if (gw_wready_i) state_r <= S_DESC_B;
                S_DESC_B: begin
                    if (gw_bvalid_i) begin
                        if (desc_idx_r == 4'd15) begin
                            state_r <= S_GEO_START;
                        end else begin
                            desc_idx_r <= desc_idx_r + 1'b1;
                            state_r <= S_DESC_AW;
                        end
                    end
                end
                S_GEO_START: if (complete_w) state_r <= S_GEO_STAT;
                S_GEO_STAT: begin
                    if (complete_w) begin
                        state_r <= |(read_w & EDRV32_GEO_IRQ_STAT_DONE_MASK) ?
                            S_GEO_CLEAR : S_PIX_STAT;
                    end
                end
                S_GEO_CLEAR: if (complete_w) state_r <= S_GEO_RELEASE;
                S_GEO_RELEASE: begin
                    vin_busy_r[source_r] <= 1'b0;
                    geo_active_r <= 1'b0;
                    pending_r <= 1'b1;
                    state_r <= S_GEO_BUSY;
                end
                S_GEO_BUSY: if (complete_w) state_r <= S_SUBMIT;
                S_PIX_STAT: if (complete_w) state_r <= S_CONFIG_CHECK;
                S_CONFIG_CHECK: begin
                    // Stop at the producer boundary so the multi-register PIX group is atomic.
                    if (cfg_active_r) begin
                        state_r <= S_CONFIG_IDLE;
                    end else if (pix_mode_r != applied_pix_r || camera_r != applied_camera_r) begin
                        cfg_active_r <= 1'b1;
                        state_r <= S_CONFIG_STOP;
                    end else begin
                        state_r <= S_DISP_STAT;
                    end
                end
                S_CONFIG_STOP: if (complete_w) state_r <= S_CONFIG_IDLE;
                S_CONFIG_IDLE: begin
                    if (complete_w) begin
                        // Service DISP/engine events while the current camera frame drains.
                        state_r <= |(read_w & EDRV32_VIN_STATUS_IDLE_MASK) ?
                            S_CONFIG_BC : S_DISP_STAT;
                    end
                end
                S_CONFIG_BC: if (complete_w) state_r <= S_CONFIG_THRESH;
                S_CONFIG_THRESH: if (complete_w) state_r <= S_CONFIG_PIX;
                S_CONFIG_PIX: if (complete_w) state_r <= S_CONFIG_CAM;
                S_CONFIG_CAM: if (complete_w) state_r <= S_CONFIG_START;
                S_CONFIG_START: begin
                    if (complete_w) begin
                        applied_pix_r <= cfg_pix_r;
                        applied_camera_r <= cfg_camera_r;
                        cfg_active_r <= 1'b0;
                        state_r <= S_DISP_STAT;
                    end
                end
                default: state_r <= S_WAIT;
            endcase
        end
    end
endmodule
