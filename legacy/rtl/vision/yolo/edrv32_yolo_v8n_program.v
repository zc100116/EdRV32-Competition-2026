// ============================================================================
// File        : edrv32_yolo_v8n_program.v
// Description : Generated fixed YOLOv8n 640x384 convolution program.
// Notes       : Regenerate with scripts/yolo_v8n_fixed_plan.py.
//               One command is issued only after the previous one completes.
// ============================================================================

module edrv32_yolo_v8n_program (
    input  wire        clk_i,
    input  wire        rst_n_i,
    input  wire        start_i,
    output wire        start_ready_o,
    output wire        busy_o,
    output wire        done_o,
    output wire        error_o,
    output wire [6:0]  step_o,
    output wire        cmd_valid_o,
    input  wire        cmd_ready_i,
    input  wire        cmd_done_i,
    input  wire        cmd_error_i,
    input  wire        abort_i,
    output wire   [1:0] cmd_op_o,
    output wire  [31:0] cmd_input_base_o,
    output wire  [31:0] cmd_aux_base_o,
    output wire  [31:0] cmd_output_base_o,
    output wire  [31:0] cmd_input_plane_stride_o,
    output wire  [31:0] cmd_output_plane_stride_o,
    output wire  [31:0] cmd_weight_base_o,
    output wire  [31:0] cmd_weight_block_stride_o,
    output wire  [10:0] cmd_input_width_o,
    output wire  [15:0] cmd_input_height_o,
    output wire   [9:0] cmd_output_width_pairs_o,
    output wire  [15:0] cmd_output_height_o,
    output wire   [5:0] cmd_cin_blocks_o,
    output wire   [4:0] cmd_output_blocks_o,
    output wire   [8:0] cmd_cache_bank_stride_o,
    output wire   [9:0] cmd_cache_row_stride_o,
    output wire   [9:0] cmd_tile_pairs_o,
    output wire         cmd_kernel3_o,
    output wire         cmd_stride2_o,
    output wire         cmd_last_c16_only_o,
    output wire  [15:0] cmd_beat_count_o,
    output wire   [7:0] cmd_residual_zero_point_o,
    output wire         cmd_lut_enable_o,
    output wire  [31:0] cfg_base_o,
    output wire   [4:0] layer_id_o
);

    localparam [1:0] S_IDLE = 2'd0;
    localparam [1:0] S_ISSUE = 2'd1;
    localparam [1:0] S_WAIT = 2'd2;
    reg [1:0] state_r;
    reg [6:0] step_r;
    reg done_r;
    reg error_r;
    reg [1:0] cmd_op_w;
    reg [31:0] cmd_input_base_w;
    reg [31:0] cmd_aux_base_w;
    reg [31:0] cmd_output_base_w;
    reg [31:0] cmd_input_plane_stride_w;
    reg [31:0] cmd_output_plane_stride_w;
    reg [31:0] cmd_weight_base_w;
    reg [31:0] cmd_weight_block_stride_w;
    reg [10:0] cmd_input_width_w;
    reg [15:0] cmd_input_height_w;
    reg [9:0] cmd_output_width_pairs_w;
    reg [15:0] cmd_output_height_w;
    reg [5:0] cmd_cin_blocks_w;
    reg [4:0] cmd_output_blocks_w;
    reg [8:0] cmd_cache_bank_stride_w;
    reg [9:0] cmd_cache_row_stride_w;
    reg [9:0] cmd_tile_pairs_w;
    reg cmd_kernel3_w;
    reg cmd_stride2_w;
    reg cmd_last_c16_only_w;
    reg [15:0] cmd_beat_count_w;
    reg [7:0] cmd_residual_zero_point_w;
    reg cmd_lut_enable_w;
    reg [31:0] cfg_base_w;
    reg [4:0] layer_id_w;

    assign start_ready_o = state_r == S_IDLE;
    assign busy_o = state_r != S_IDLE;
    assign done_o = done_r;
    assign error_o = error_r;
    assign step_o = step_r;
    assign cmd_valid_o = state_r == S_ISSUE;
    assign cmd_op_o = cmd_op_w;
    assign cmd_input_base_o = cmd_input_base_w;
    assign cmd_aux_base_o = cmd_aux_base_w;
    assign cmd_output_base_o = cmd_output_base_w;
    assign cmd_input_plane_stride_o = cmd_input_plane_stride_w;
    assign cmd_output_plane_stride_o = cmd_output_plane_stride_w;
    assign cmd_weight_base_o = cmd_weight_base_w;
    assign cmd_weight_block_stride_o = cmd_weight_block_stride_w;
    assign cmd_input_width_o = cmd_input_width_w;
    assign cmd_input_height_o = cmd_input_height_w;
    assign cmd_output_width_pairs_o = cmd_output_width_pairs_w;
    assign cmd_output_height_o = cmd_output_height_w;
    assign cmd_cin_blocks_o = cmd_cin_blocks_w;
    assign cmd_output_blocks_o = cmd_output_blocks_w;
    assign cmd_cache_bank_stride_o = cmd_cache_bank_stride_w;
    assign cmd_cache_row_stride_o = cmd_cache_row_stride_w;
    assign cmd_tile_pairs_o = cmd_tile_pairs_w;
    assign cmd_kernel3_o = cmd_kernel3_w;
    assign cmd_stride2_o = cmd_stride2_w;
    assign cmd_last_c16_only_o = cmd_last_c16_only_w;
    assign cmd_beat_count_o = cmd_beat_count_w;
    assign cmd_residual_zero_point_o = cmd_residual_zero_point_w;
    assign cmd_lut_enable_o = cmd_lut_enable_w;
    assign cfg_base_o = cfg_base_w;
    assign layer_id_o = layer_id_w;

    always @(*) begin
        cmd_op_w = 2'd0;
        cmd_input_base_w = 32'd0;
        cmd_aux_base_w = 32'd0;
        cmd_output_base_w = 32'd0;
        cmd_input_plane_stride_w = 32'd0;
        cmd_output_plane_stride_w = 32'd0;
        cmd_weight_base_w = 32'd0;
        cmd_weight_block_stride_w = 32'd0;
        cmd_input_width_w = 11'd0;
        cmd_input_height_w = 16'd0;
        cmd_output_width_pairs_w = 10'd0;
        cmd_output_height_w = 16'd0;
        cmd_cin_blocks_w = 6'd0;
        cmd_output_blocks_w = 5'd0;
        cmd_cache_bank_stride_w = 9'd0;
        cmd_cache_row_stride_w = 10'd0;
        cmd_tile_pairs_w = 10'd0;
        cmd_kernel3_w = 1'd0;
        cmd_stride2_w = 1'd0;
        cmd_last_c16_only_w = 1'd0;
        cmd_beat_count_w = 16'd0;
        cmd_residual_zero_point_w = 8'd0;
        cmd_lut_enable_w = 1'd0;
        cfg_base_w = 32'd0;
        layer_id_w = 5'd0;
        case (step_r)
            // L0: input -> L0
            7'd0: begin
                cmd_input_base_w = 32'h02152000;
                cmd_output_base_w = 32'h02512000;
                cmd_input_plane_stride_w = 32'h003c0000;
                cmd_output_plane_stride_w = 32'h000f0000;
                cmd_weight_base_w = 32'h00100000;
                cmd_weight_block_stride_w = 32'h00001200;
                cmd_input_width_w = 11'd640;
                cmd_input_height_w = 16'd384;
                cmd_output_width_pairs_w = 10'd160;
                cmd_output_height_w = 16'd192;
                cmd_cin_blocks_w = 6'd1;
                cmd_output_blocks_w = 5'd1;
                cmd_cache_bank_stride_w = 9'd160;
                cmd_cache_row_stride_w = 10'd160;
                cmd_tile_pairs_w = 10'd4;
                cmd_kernel3_w = 1'd1;
                cmd_stride2_w = 1'd1;
                cmd_last_c16_only_w = 1'd1;
                cmd_lut_enable_w = 1'd1;
                cfg_base_w = 32'h0041c000;
            end
            // L1: L0 -> L1
            7'd1: begin
                cmd_input_base_w = 32'h02512000;
                cmd_output_base_w = 32'h02602000;
                cmd_input_plane_stride_w = 32'h000f0000;
                cmd_output_plane_stride_w = 32'h0003c000;
                cmd_weight_base_w = 32'h00101200;
                cmd_weight_block_stride_w = 32'h00001200;
                cmd_input_width_w = 11'd320;
                cmd_input_height_w = 16'd192;
                cmd_output_width_pairs_w = 10'd80;
                cmd_output_height_w = 16'd96;
                cmd_cin_blocks_w = 6'd1;
                cmd_output_blocks_w = 5'd1;
                cmd_cache_bank_stride_w = 9'd80;
                cmd_cache_row_stride_w = 10'd80;
                cmd_tile_pairs_w = 10'd4;
                cmd_kernel3_w = 1'd1;
                cmd_stride2_w = 1'd1;
                cmd_lut_enable_w = 1'd1;
                cfg_base_w = 32'h0041c200;
                layer_id_w = 5'd1;
            end
            // L2.split: L1 -> L2.split
            7'd2: begin
                cmd_input_base_w = 32'h02602000;
                cmd_output_base_w = 32'h02885000;
                cmd_input_plane_stride_w = 32'h0003c000;
                cmd_output_plane_stride_w = 32'h0003c000;
                cmd_weight_base_w = 32'h00102400;
                cmd_weight_block_stride_w = 32'h00000400;
                cmd_input_width_w = 11'd160;
                cmd_input_height_w = 16'd96;
                cmd_output_width_pairs_w = 10'd80;
                cmd_output_height_w = 16'd96;
                cmd_cin_blocks_w = 6'd2;
                cmd_output_blocks_w = 5'd1;
                cmd_cache_bank_stride_w = 9'd40;
                cmd_cache_row_stride_w = 10'd80;
                cmd_tile_pairs_w = 10'd4;
                cmd_lut_enable_w = 1'd1;
                cfg_base_w = 32'h0041c400;
                layer_id_w = 5'd2;
            end
            // L2.b0.cv1: L2.g1 -> L2.temp
            7'd3: begin
                cmd_input_base_w = 32'h028c1000;
                cmd_output_base_w = 32'h02939000;
                cmd_input_plane_stride_w = 32'h0003c000;
                cmd_output_plane_stride_w = 32'h0003c000;
                cmd_weight_base_w = 32'h00102800;
                cmd_weight_block_stride_w = 32'h00001200;
                cmd_input_width_w = 11'd160;
                cmd_input_height_w = 16'd96;
                cmd_output_width_pairs_w = 10'd80;
                cmd_output_height_w = 16'd96;
                cmd_cin_blocks_w = 6'd1;
                cmd_output_blocks_w = 5'd1;
                cmd_cache_bank_stride_w = 9'd40;
                cmd_cache_row_stride_w = 10'd40;
                cmd_tile_pairs_w = 10'd4;
                cmd_kernel3_w = 1'd1;
                cmd_last_c16_only_w = 1'd1;
                cmd_lut_enable_w = 1'd1;
                cfg_base_w = 32'h0041c600;
                layer_id_w = 5'd2;
            end
            // L2.b0.cv2: L2.temp -> L2.g2
            7'd4: begin
                cmd_input_base_w = 32'h02939000;
                cmd_output_base_w = 32'h028fd000;
                cmd_input_plane_stride_w = 32'h0003c000;
                cmd_output_plane_stride_w = 32'h0003c000;
                cmd_weight_base_w = 32'h00103a00;
                cmd_weight_block_stride_w = 32'h00001200;
                cmd_input_width_w = 11'd160;
                cmd_input_height_w = 16'd96;
                cmd_output_width_pairs_w = 10'd80;
                cmd_output_height_w = 16'd96;
                cmd_cin_blocks_w = 6'd1;
                cmd_output_blocks_w = 5'd1;
                cmd_cache_bank_stride_w = 9'd40;
                cmd_cache_row_stride_w = 10'd40;
                cmd_tile_pairs_w = 10'd4;
                cmd_kernel3_w = 1'd1;
                cmd_last_c16_only_w = 1'd1;
                cmd_lut_enable_w = 1'd1;
                cfg_base_w = 32'h0041c800;
                layer_id_w = 5'd2;
            end
            // L2.b0.add: L2.g1 -> L2.g2
            7'd5: begin
                cmd_op_w = 2'd1;
                cmd_input_base_w = 32'h028c1000;
                cmd_aux_base_w = 32'h028fd000;
                cmd_output_base_w = 32'h028fd000;
                cmd_beat_count_w = 16'd7680;
                layer_id_w = 5'd2;
            end
            // L2.fuse: L2.workspace -> L2
            7'd6: begin
                cmd_input_base_w = 32'h02885000;
                cmd_output_base_w = 32'h0267a000;
                cmd_input_plane_stride_w = 32'h0003c000;
                cmd_output_plane_stride_w = 32'h0003c000;
                cmd_weight_base_w = 32'h00104c00;
                cmd_weight_block_stride_w = 32'h00000600;
                cmd_input_width_w = 11'd160;
                cmd_input_height_w = 16'd96;
                cmd_output_width_pairs_w = 10'd80;
                cmd_output_height_w = 16'd96;
                cmd_cin_blocks_w = 6'd3;
                cmd_output_blocks_w = 5'd1;
                cmd_cache_bank_stride_w = 9'd40;
                cmd_cache_row_stride_w = 10'd120;
                cmd_tile_pairs_w = 10'd4;
                cmd_lut_enable_w = 1'd1;
                cfg_base_w = 32'h0041ca00;
                layer_id_w = 5'd2;
            end
            // L3: L2 -> L3
            7'd7: begin
                cmd_input_base_w = 32'h0267a000;
                cmd_output_base_w = 32'h026f2000;
                cmd_input_plane_stride_w = 32'h0003c000;
                cmd_output_plane_stride_w = 32'h0000f000;
                cmd_weight_base_w = 32'h00105200;
                cmd_weight_block_stride_w = 32'h00002400;
                cmd_input_width_w = 11'd160;
                cmd_input_height_w = 16'd96;
                cmd_output_width_pairs_w = 10'd40;
                cmd_output_height_w = 16'd48;
                cmd_cin_blocks_w = 6'd2;
                cmd_output_blocks_w = 5'd2;
                cmd_cache_bank_stride_w = 9'd40;
                cmd_cache_row_stride_w = 10'd80;
                cmd_tile_pairs_w = 10'd4;
                cmd_kernel3_w = 1'd1;
                cmd_stride2_w = 1'd1;
                cmd_lut_enable_w = 1'd1;
                cfg_base_w = 32'h0041cc00;
                layer_id_w = 5'd3;
            end
            // L4.split: L3 -> L4.split
            7'd8: begin
                cmd_input_base_w = 32'h026f2000;
                cmd_output_base_w = 32'h02885000;
                cmd_input_plane_stride_w = 32'h0000f000;
                cmd_output_plane_stride_w = 32'h0000f000;
                cmd_weight_base_w = 32'h00109a00;
                cmd_weight_block_stride_w = 32'h00000800;
                cmd_input_width_w = 11'd80;
                cmd_input_height_w = 16'd48;
                cmd_output_width_pairs_w = 10'd40;
                cmd_output_height_w = 16'd48;
                cmd_cin_blocks_w = 6'd4;
                cmd_output_blocks_w = 5'd2;
                cmd_cache_bank_stride_w = 9'd20;
                cmd_cache_row_stride_w = 10'd80;
                cmd_tile_pairs_w = 10'd4;
                cmd_lut_enable_w = 1'd1;
                cfg_base_w = 32'h0041d000;
                layer_id_w = 5'd4;
            end
            // L4.b0.cv1: L4.g1 -> L4.temp
            7'd9: begin
                cmd_input_base_w = 32'h028a3000;
                cmd_output_base_w = 32'h02939000;
                cmd_input_plane_stride_w = 32'h0000f000;
                cmd_output_plane_stride_w = 32'h0000f000;
                cmd_weight_base_w = 32'h0010aa00;
                cmd_weight_block_stride_w = 32'h00002400;
                cmd_input_width_w = 11'd80;
                cmd_input_height_w = 16'd48;
                cmd_output_width_pairs_w = 10'd40;
                cmd_output_height_w = 16'd48;
                cmd_cin_blocks_w = 6'd2;
                cmd_output_blocks_w = 5'd1;
                cmd_cache_bank_stride_w = 9'd20;
                cmd_cache_row_stride_w = 10'd40;
                cmd_tile_pairs_w = 10'd4;
                cmd_kernel3_w = 1'd1;
                cmd_lut_enable_w = 1'd1;
                cfg_base_w = 32'h0041d400;
                layer_id_w = 5'd4;
            end
            // L4.b0.cv2: L4.temp -> L4.g2
            7'd10: begin
                cmd_input_base_w = 32'h02939000;
                cmd_output_base_w = 32'h028c1000;
                cmd_input_plane_stride_w = 32'h0000f000;
                cmd_output_plane_stride_w = 32'h0000f000;
                cmd_weight_base_w = 32'h0010ce00;
                cmd_weight_block_stride_w = 32'h00002400;
                cmd_input_width_w = 11'd80;
                cmd_input_height_w = 16'd48;
                cmd_output_width_pairs_w = 10'd40;
                cmd_output_height_w = 16'd48;
                cmd_cin_blocks_w = 6'd2;
                cmd_output_blocks_w = 5'd1;
                cmd_cache_bank_stride_w = 9'd20;
                cmd_cache_row_stride_w = 10'd40;
                cmd_tile_pairs_w = 10'd4;
                cmd_kernel3_w = 1'd1;
                cmd_lut_enable_w = 1'd1;
                cfg_base_w = 32'h0041d600;
                layer_id_w = 5'd4;
            end
            // L4.b0.add: L4.g1 -> L4.g2
            7'd11: begin
                cmd_op_w = 2'd1;
                cmd_input_base_w = 32'h028a3000;
                cmd_aux_base_w = 32'h028c1000;
                cmd_output_base_w = 32'h028c1000;
                cmd_beat_count_w = 16'd3840;
                layer_id_w = 5'd4;
            end
            // L4.b1.cv1: L4.g2 -> L4.temp
            7'd12: begin
                cmd_input_base_w = 32'h028c1000;
                cmd_output_base_w = 32'h02939000;
                cmd_input_plane_stride_w = 32'h0000f000;
                cmd_output_plane_stride_w = 32'h0000f000;
                cmd_weight_base_w = 32'h0010f200;
                cmd_weight_block_stride_w = 32'h00002400;
                cmd_input_width_w = 11'd80;
                cmd_input_height_w = 16'd48;
                cmd_output_width_pairs_w = 10'd40;
                cmd_output_height_w = 16'd48;
                cmd_cin_blocks_w = 6'd2;
                cmd_output_blocks_w = 5'd1;
                cmd_cache_bank_stride_w = 9'd20;
                cmd_cache_row_stride_w = 10'd40;
                cmd_tile_pairs_w = 10'd4;
                cmd_kernel3_w = 1'd1;
                cmd_lut_enable_w = 1'd1;
                cfg_base_w = 32'h0041d800;
                layer_id_w = 5'd4;
            end
            // L4.b1.cv2: L4.temp -> L4.g3
            7'd13: begin
                cmd_input_base_w = 32'h02939000;
                cmd_output_base_w = 32'h028df000;
                cmd_input_plane_stride_w = 32'h0000f000;
                cmd_output_plane_stride_w = 32'h0000f000;
                cmd_weight_base_w = 32'h00111600;
                cmd_weight_block_stride_w = 32'h00002400;
                cmd_input_width_w = 11'd80;
                cmd_input_height_w = 16'd48;
                cmd_output_width_pairs_w = 10'd40;
                cmd_output_height_w = 16'd48;
                cmd_cin_blocks_w = 6'd2;
                cmd_output_blocks_w = 5'd1;
                cmd_cache_bank_stride_w = 9'd20;
                cmd_cache_row_stride_w = 10'd40;
                cmd_tile_pairs_w = 10'd4;
                cmd_kernel3_w = 1'd1;
                cmd_lut_enable_w = 1'd1;
                cfg_base_w = 32'h0041da00;
                layer_id_w = 5'd4;
            end
            // L4.b1.add: L4.g2 -> L4.g3
            7'd14: begin
                cmd_op_w = 2'd1;
                cmd_input_base_w = 32'h028c1000;
                cmd_aux_base_w = 32'h028df000;
                cmd_output_base_w = 32'h028df000;
                cmd_beat_count_w = 16'd3840;
                layer_id_w = 5'd4;
            end
            // L4.fuse: L4.workspace -> L4
            7'd15: begin
                cmd_input_base_w = 32'h02885000;
                cmd_output_base_w = 32'h020d2000;
                cmd_input_plane_stride_w = 32'h0000f000;
                cmd_output_plane_stride_w = 32'h0000f000;
                cmd_weight_base_w = 32'h00113a00;
                cmd_weight_block_stride_w = 32'h00001000;
                cmd_input_width_w = 11'd80;
                cmd_input_height_w = 16'd48;
                cmd_output_width_pairs_w = 10'd40;
                cmd_output_height_w = 16'd48;
                cmd_cin_blocks_w = 6'd8;
                cmd_output_blocks_w = 5'd2;
                cmd_cache_bank_stride_w = 9'd20;
                cmd_cache_row_stride_w = 10'd160;
                cmd_tile_pairs_w = 10'd4;
                cmd_lut_enable_w = 1'd1;
                cfg_base_w = 32'h0041dc00;
                layer_id_w = 5'd4;
            end
            // L5: L4 -> L5
            7'd16: begin
                cmd_input_base_w = 32'h020d2000;
                cmd_output_base_w = 32'h0272e000;
                cmd_input_plane_stride_w = 32'h0000f000;
                cmd_output_plane_stride_w = 32'h00003c00;
                cmd_weight_base_w = 32'h00115a00;
                cmd_weight_block_stride_w = 32'h00004800;
                cmd_input_width_w = 11'd80;
                cmd_input_height_w = 16'd48;
                cmd_output_width_pairs_w = 10'd20;
                cmd_output_height_w = 16'd24;
                cmd_cin_blocks_w = 6'd4;
                cmd_output_blocks_w = 5'd4;
                cmd_cache_bank_stride_w = 9'd20;
                cmd_cache_row_stride_w = 10'd80;
                cmd_tile_pairs_w = 10'd4;
                cmd_kernel3_w = 1'd1;
                cmd_stride2_w = 1'd1;
                cmd_lut_enable_w = 1'd1;
                cfg_base_w = 32'h0041e000;
                layer_id_w = 5'd5;
            end
            // L6.split: L5 -> L6.split
            7'd17: begin
                cmd_input_base_w = 32'h0272e000;
                cmd_output_base_w = 32'h02885000;
                cmd_input_plane_stride_w = 32'h00003c00;
                cmd_output_plane_stride_w = 32'h00003c00;
                cmd_weight_base_w = 32'h00127a00;
                cmd_weight_block_stride_w = 32'h00001000;
                cmd_input_width_w = 11'd40;
                cmd_input_height_w = 16'd24;
                cmd_output_width_pairs_w = 10'd20;
                cmd_output_height_w = 16'd24;
                cmd_cin_blocks_w = 6'd8;
                cmd_output_blocks_w = 5'd4;
                cmd_cache_bank_stride_w = 9'd10;
                cmd_cache_row_stride_w = 10'd80;
                cmd_tile_pairs_w = 10'd4;
                cmd_lut_enable_w = 1'd1;
                cfg_base_w = 32'h0041e800;
                layer_id_w = 5'd6;
            end
            // L6.b0.cv1: L6.g1 -> L6.temp
            7'd18: begin
                cmd_input_base_w = 32'h02894000;
                cmd_output_base_w = 32'h02939000;
                cmd_input_plane_stride_w = 32'h00003c00;
                cmd_output_plane_stride_w = 32'h00003c00;
                cmd_weight_base_w = 32'h0012ba00;
                cmd_weight_block_stride_w = 32'h00004800;
                cmd_input_width_w = 11'd40;
                cmd_input_height_w = 16'd24;
                cmd_output_width_pairs_w = 10'd20;
                cmd_output_height_w = 16'd24;
                cmd_cin_blocks_w = 6'd4;
                cmd_output_blocks_w = 5'd2;
                cmd_cache_bank_stride_w = 9'd10;
                cmd_cache_row_stride_w = 10'd40;
                cmd_tile_pairs_w = 10'd4;
                cmd_kernel3_w = 1'd1;
                cmd_lut_enable_w = 1'd1;
                cfg_base_w = 32'h0041f000;
                layer_id_w = 5'd6;
            end
            // L6.b0.cv2: L6.temp -> L6.g2
            7'd19: begin
                cmd_input_base_w = 32'h02939000;
                cmd_output_base_w = 32'h028a3000;
                cmd_input_plane_stride_w = 32'h00003c00;
                cmd_output_plane_stride_w = 32'h00003c00;
                cmd_weight_base_w = 32'h00134a00;
                cmd_weight_block_stride_w = 32'h00004800;
                cmd_input_width_w = 11'd40;
                cmd_input_height_w = 16'd24;
                cmd_output_width_pairs_w = 10'd20;
                cmd_output_height_w = 16'd24;
                cmd_cin_blocks_w = 6'd4;
                cmd_output_blocks_w = 5'd2;
                cmd_cache_bank_stride_w = 9'd10;
                cmd_cache_row_stride_w = 10'd40;
                cmd_tile_pairs_w = 10'd4;
                cmd_kernel3_w = 1'd1;
                cmd_lut_enable_w = 1'd1;
                cfg_base_w = 32'h0041f400;
                layer_id_w = 5'd6;
            end
            // L6.b0.add: L6.g1 -> L6.g2
            7'd20: begin
                cmd_op_w = 2'd1;
                cmd_input_base_w = 32'h02894000;
                cmd_aux_base_w = 32'h028a3000;
                cmd_output_base_w = 32'h028a3000;
                cmd_beat_count_w = 16'd1920;
                layer_id_w = 5'd6;
            end
            // L6.b1.cv1: L6.g2 -> L6.temp
            7'd21: begin
                cmd_input_base_w = 32'h028a3000;
                cmd_output_base_w = 32'h02939000;
                cmd_input_plane_stride_w = 32'h00003c00;
                cmd_output_plane_stride_w = 32'h00003c00;
                cmd_weight_base_w = 32'h0013da00;
                cmd_weight_block_stride_w = 32'h00004800;
                cmd_input_width_w = 11'd40;
                cmd_input_height_w = 16'd24;
                cmd_output_width_pairs_w = 10'd20;
                cmd_output_height_w = 16'd24;
                cmd_cin_blocks_w = 6'd4;
                cmd_output_blocks_w = 5'd2;
                cmd_cache_bank_stride_w = 9'd10;
                cmd_cache_row_stride_w = 10'd40;
                cmd_tile_pairs_w = 10'd4;
                cmd_kernel3_w = 1'd1;
                cmd_lut_enable_w = 1'd1;
                cfg_base_w = 32'h0041f800;
                layer_id_w = 5'd6;
            end
            // L6.b1.cv2: L6.temp -> L6.g3
            7'd22: begin
                cmd_input_base_w = 32'h02939000;
                cmd_output_base_w = 32'h028b2000;
                cmd_input_plane_stride_w = 32'h00003c00;
                cmd_output_plane_stride_w = 32'h00003c00;
                cmd_weight_base_w = 32'h00146a00;
                cmd_weight_block_stride_w = 32'h00004800;
                cmd_input_width_w = 11'd40;
                cmd_input_height_w = 16'd24;
                cmd_output_width_pairs_w = 10'd20;
                cmd_output_height_w = 16'd24;
                cmd_cin_blocks_w = 6'd4;
                cmd_output_blocks_w = 5'd2;
                cmd_cache_bank_stride_w = 9'd10;
                cmd_cache_row_stride_w = 10'd40;
                cmd_tile_pairs_w = 10'd4;
                cmd_kernel3_w = 1'd1;
                cmd_lut_enable_w = 1'd1;
                cfg_base_w = 32'h0041fc00;
                layer_id_w = 5'd6;
            end
            // L6.b1.add: L6.g2 -> L6.g3
            7'd23: begin
                cmd_op_w = 2'd1;
                cmd_input_base_w = 32'h028a3000;
                cmd_aux_base_w = 32'h028b2000;
                cmd_output_base_w = 32'h028b2000;
                cmd_beat_count_w = 16'd1920;
                layer_id_w = 5'd6;
            end
            // L6.fuse: L6.workspace -> L6
            7'd24: begin
                cmd_input_base_w = 32'h02885000;
                cmd_output_base_w = 32'h0203c000;
                cmd_input_plane_stride_w = 32'h00003c00;
                cmd_output_plane_stride_w = 32'h00003c00;
                cmd_weight_base_w = 32'h0014fa00;
                cmd_weight_block_stride_w = 32'h00002000;
                cmd_input_width_w = 11'd40;
                cmd_input_height_w = 16'd24;
                cmd_output_width_pairs_w = 10'd20;
                cmd_output_height_w = 16'd24;
                cmd_cin_blocks_w = 6'd16;
                cmd_output_blocks_w = 5'd4;
                cmd_cache_bank_stride_w = 9'd10;
                cmd_cache_row_stride_w = 10'd160;
                cmd_tile_pairs_w = 10'd4;
                cmd_lut_enable_w = 1'd1;
                cfg_base_w = 32'h00420000;
                layer_id_w = 5'd6;
            end
            // L7: L6 -> L7
            7'd25: begin
                cmd_input_base_w = 32'h0203c000;
                cmd_output_base_w = 32'h0274c000;
                cmd_input_plane_stride_w = 32'h00003c00;
                cmd_output_plane_stride_w = 32'h00000f00;
                cmd_weight_base_w = 32'h00157a00;
                cmd_weight_block_stride_w = 32'h00009000;
                cmd_input_width_w = 11'd40;
                cmd_input_height_w = 16'd24;
                cmd_output_width_pairs_w = 10'd10;
                cmd_output_height_w = 16'd12;
                cmd_cin_blocks_w = 6'd8;
                cmd_output_blocks_w = 5'd8;
                cmd_cache_bank_stride_w = 9'd10;
                cmd_cache_row_stride_w = 10'd80;
                cmd_tile_pairs_w = 10'd4;
                cmd_kernel3_w = 1'd1;
                cmd_stride2_w = 1'd1;
                cmd_lut_enable_w = 1'd1;
                cfg_base_w = 32'h00420800;
                layer_id_w = 5'd7;
            end
            // L8.split: L7 -> L8.split
            7'd26: begin
                cmd_input_base_w = 32'h0274c000;
                cmd_output_base_w = 32'h02885000;
                cmd_input_plane_stride_w = 32'h00000f00;
                cmd_output_plane_stride_w = 32'h00000f00;
                cmd_weight_base_w = 32'h0019fa00;
                cmd_weight_block_stride_w = 32'h00002000;
                cmd_input_width_w = 11'd20;
                cmd_input_height_w = 16'd12;
                cmd_output_width_pairs_w = 10'd10;
                cmd_output_height_w = 16'd12;
                cmd_cin_blocks_w = 6'd16;
                cmd_output_blocks_w = 5'd8;
                cmd_cache_bank_stride_w = 9'd5;
                cmd_cache_row_stride_w = 10'd80;
                cmd_tile_pairs_w = 10'd4;
                cmd_lut_enable_w = 1'd1;
                cfg_base_w = 32'h00421800;
                layer_id_w = 5'd8;
            end
            // L8.b0.cv1: L8.g1 -> L8.temp
            7'd27: begin
                cmd_input_base_w = 32'h0288c800;
                cmd_output_base_w = 32'h02939000;
                cmd_input_plane_stride_w = 32'h00000f00;
                cmd_output_plane_stride_w = 32'h00000f00;
                cmd_weight_base_w = 32'h001afa00;
                cmd_weight_block_stride_w = 32'h00009000;
                cmd_input_width_w = 11'd20;
                cmd_input_height_w = 16'd12;
                cmd_output_width_pairs_w = 10'd10;
                cmd_output_height_w = 16'd12;
                cmd_cin_blocks_w = 6'd8;
                cmd_output_blocks_w = 5'd4;
                cmd_cache_bank_stride_w = 9'd5;
                cmd_cache_row_stride_w = 10'd40;
                cmd_tile_pairs_w = 10'd4;
                cmd_kernel3_w = 1'd1;
                cmd_lut_enable_w = 1'd1;
                cfg_base_w = 32'h00422800;
                layer_id_w = 5'd8;
            end
            // L8.b0.cv2: L8.temp -> L8.g2
            7'd28: begin
                cmd_input_base_w = 32'h02939000;
                cmd_output_base_w = 32'h02894000;
                cmd_input_plane_stride_w = 32'h00000f00;
                cmd_output_plane_stride_w = 32'h00000f00;
                cmd_weight_base_w = 32'h001d3a00;
                cmd_weight_block_stride_w = 32'h00009000;
                cmd_input_width_w = 11'd20;
                cmd_input_height_w = 16'd12;
                cmd_output_width_pairs_w = 10'd10;
                cmd_output_height_w = 16'd12;
                cmd_cin_blocks_w = 6'd8;
                cmd_output_blocks_w = 5'd4;
                cmd_cache_bank_stride_w = 9'd5;
                cmd_cache_row_stride_w = 10'd40;
                cmd_tile_pairs_w = 10'd4;
                cmd_kernel3_w = 1'd1;
                cmd_lut_enable_w = 1'd1;
                cfg_base_w = 32'h00423000;
                layer_id_w = 5'd8;
            end
            // L8.b0.add: L8.g1 -> L8.g2
            7'd29: begin
                cmd_op_w = 2'd1;
                cmd_input_base_w = 32'h0288c800;
                cmd_aux_base_w = 32'h02894000;
                cmd_output_base_w = 32'h02894000;
                cmd_beat_count_w = 16'd960;
                layer_id_w = 5'd8;
            end
            // L8.fuse: L8.workspace -> L8
            7'd30: begin
                cmd_input_base_w = 32'h02885000;
                cmd_output_base_w = 32'h0275b000;
                cmd_input_plane_stride_w = 32'h00000f00;
                cmd_output_plane_stride_w = 32'h00000f00;
                cmd_weight_base_w = 32'h001f7a00;
                cmd_weight_block_stride_w = 32'h00003000;
                cmd_input_width_w = 11'd20;
                cmd_input_height_w = 16'd12;
                cmd_output_width_pairs_w = 10'd10;
                cmd_output_height_w = 16'd12;
                cmd_cin_blocks_w = 6'd24;
                cmd_output_blocks_w = 5'd8;
                cmd_cache_bank_stride_w = 9'd5;
                cmd_cache_row_stride_w = 10'd120;
                cmd_tile_pairs_w = 10'd4;
                cmd_lut_enable_w = 1'd1;
                cfg_base_w = 32'h00423800;
                layer_id_w = 5'd8;
            end
            // L9.cv1: L8 -> L9.g0
            7'd31: begin
                cmd_input_base_w = 32'h0275b000;
                cmd_output_base_w = 32'h02885000;
                cmd_input_plane_stride_w = 32'h00000f00;
                cmd_output_plane_stride_w = 32'h00000f00;
                cmd_weight_base_w = 32'h0020fa00;
                cmd_weight_block_stride_w = 32'h00002000;
                cmd_input_width_w = 11'd20;
                cmd_input_height_w = 16'd12;
                cmd_output_width_pairs_w = 10'd10;
                cmd_output_height_w = 16'd12;
                cmd_cin_blocks_w = 6'd16;
                cmd_output_blocks_w = 5'd4;
                cmd_cache_bank_stride_w = 9'd5;
                cmd_cache_row_stride_w = 10'd80;
                cmd_tile_pairs_w = 10'd4;
                cmd_lut_enable_w = 1'd1;
                cfg_base_w = 32'h00424800;
                layer_id_w = 5'd9;
            end
            // L9.pool0: L9.g0 -> L9.g1
            7'd32: begin
                cmd_op_w = 2'd2;
                cmd_input_base_w = 32'h02885000;
                cmd_output_base_w = 32'h0288c800;
                cmd_input_plane_stride_w = 32'h00000f00;
                cmd_output_plane_stride_w = 32'h00000f00;
                cmd_input_width_w = 11'd20;
                cmd_input_height_w = 16'd12;
                cmd_cin_blocks_w = 6'd8;
                layer_id_w = 5'd9;
            end
            // L9.pool1: L9.g1 -> L9.g2
            7'd33: begin
                cmd_op_w = 2'd2;
                cmd_input_base_w = 32'h0288c800;
                cmd_output_base_w = 32'h02894000;
                cmd_input_plane_stride_w = 32'h00000f00;
                cmd_output_plane_stride_w = 32'h00000f00;
                cmd_input_width_w = 11'd20;
                cmd_input_height_w = 16'd12;
                cmd_cin_blocks_w = 6'd8;
                layer_id_w = 5'd9;
            end
            // L9.pool2: L9.g2 -> L9.g3
            7'd34: begin
                cmd_op_w = 2'd2;
                cmd_input_base_w = 32'h02894000;
                cmd_output_base_w = 32'h0289b800;
                cmd_input_plane_stride_w = 32'h00000f00;
                cmd_output_plane_stride_w = 32'h00000f00;
                cmd_input_width_w = 11'd20;
                cmd_input_height_w = 16'd12;
                cmd_cin_blocks_w = 6'd8;
                layer_id_w = 5'd9;
            end
            // L9.cv2: L9.workspace -> L9
            7'd35: begin
                cmd_input_base_w = 32'h02885000;
                cmd_output_base_w = 32'h02142800;
                cmd_input_plane_stride_w = 32'h00000f00;
                cmd_output_plane_stride_w = 32'h00000f00;
                cmd_weight_base_w = 32'h00217a00;
                cmd_weight_block_stride_w = 32'h00004000;
                cmd_input_width_w = 11'd20;
                cmd_input_height_w = 16'd12;
                cmd_output_width_pairs_w = 10'd10;
                cmd_output_height_w = 16'd12;
                cmd_cin_blocks_w = 6'd32;
                cmd_output_blocks_w = 5'd8;
                cmd_cache_bank_stride_w = 9'd5;
                cmd_cache_row_stride_w = 10'd160;
                cmd_tile_pairs_w = 10'd4;
                cmd_lut_enable_w = 1'd1;
                cfg_base_w = 32'h00425000;
                layer_id_w = 5'd9;
            end
            // L10: L9 -> L10
            7'd36: begin
                cmd_op_w = 2'd3;
                cmd_input_base_w = 32'h02142800;
                cmd_output_base_w = 32'h02000000;
                cmd_input_plane_stride_w = 32'h00000f00;
                cmd_output_plane_stride_w = 32'h00003c00;
                cmd_input_width_w = 11'd20;
                cmd_input_height_w = 16'd12;
                cmd_cin_blocks_w = 6'd16;
                layer_id_w = 5'd10;
            end
            // L12.split: L11 -> L12.split
            7'd37: begin
                cmd_input_base_w = 32'h02000000;
                cmd_output_base_w = 32'h02885000;
                cmd_input_plane_stride_w = 32'h00003c00;
                cmd_output_plane_stride_w = 32'h00003c00;
                cmd_weight_base_w = 32'h00237a00;
                cmd_weight_block_stride_w = 32'h00003000;
                cmd_input_width_w = 11'd40;
                cmd_input_height_w = 16'd24;
                cmd_output_width_pairs_w = 10'd20;
                cmd_output_height_w = 16'd24;
                cmd_cin_blocks_w = 6'd24;
                cmd_output_blocks_w = 5'd4;
                cmd_cache_bank_stride_w = 9'd10;
                cmd_cache_row_stride_w = 10'd240;
                cmd_tile_pairs_w = 10'd4;
                cmd_lut_enable_w = 1'd1;
                cfg_base_w = 32'h00426000;
                layer_id_w = 5'd12;
            end
            // L12.b0.cv1: L12.g1 -> L12.temp
            7'd38: begin
                cmd_input_base_w = 32'h02894000;
                cmd_output_base_w = 32'h02939000;
                cmd_input_plane_stride_w = 32'h00003c00;
                cmd_output_plane_stride_w = 32'h00003c00;
                cmd_weight_base_w = 32'h00243a00;
                cmd_weight_block_stride_w = 32'h00004800;
                cmd_input_width_w = 11'd40;
                cmd_input_height_w = 16'd24;
                cmd_output_width_pairs_w = 10'd20;
                cmd_output_height_w = 16'd24;
                cmd_cin_blocks_w = 6'd4;
                cmd_output_blocks_w = 5'd2;
                cmd_cache_bank_stride_w = 9'd10;
                cmd_cache_row_stride_w = 10'd40;
                cmd_tile_pairs_w = 10'd4;
                cmd_kernel3_w = 1'd1;
                cmd_lut_enable_w = 1'd1;
                cfg_base_w = 32'h00426800;
                layer_id_w = 5'd12;
            end
            // L12.b0.cv2: L12.temp -> L12.g2
            7'd39: begin
                cmd_input_base_w = 32'h02939000;
                cmd_output_base_w = 32'h028a3000;
                cmd_input_plane_stride_w = 32'h00003c00;
                cmd_output_plane_stride_w = 32'h00003c00;
                cmd_weight_base_w = 32'h0024ca00;
                cmd_weight_block_stride_w = 32'h00004800;
                cmd_input_width_w = 11'd40;
                cmd_input_height_w = 16'd24;
                cmd_output_width_pairs_w = 10'd20;
                cmd_output_height_w = 16'd24;
                cmd_cin_blocks_w = 6'd4;
                cmd_output_blocks_w = 5'd2;
                cmd_cache_bank_stride_w = 9'd10;
                cmd_cache_row_stride_w = 10'd40;
                cmd_tile_pairs_w = 10'd4;
                cmd_kernel3_w = 1'd1;
                cmd_lut_enable_w = 1'd1;
                cfg_base_w = 32'h00426c00;
                layer_id_w = 5'd12;
            end
            // L12.fuse: L12.workspace -> L12
            7'd40: begin
                cmd_input_base_w = 32'h02885000;
                cmd_output_base_w = 32'h0211d000;
                cmd_input_plane_stride_w = 32'h00003c00;
                cmd_output_plane_stride_w = 32'h00003c00;
                cmd_weight_base_w = 32'h00255a00;
                cmd_weight_block_stride_w = 32'h00001800;
                cmd_input_width_w = 11'd40;
                cmd_input_height_w = 16'd24;
                cmd_output_width_pairs_w = 10'd20;
                cmd_output_height_w = 16'd24;
                cmd_cin_blocks_w = 6'd12;
                cmd_output_blocks_w = 5'd4;
                cmd_cache_bank_stride_w = 9'd10;
                cmd_cache_row_stride_w = 10'd120;
                cmd_tile_pairs_w = 10'd4;
                cmd_lut_enable_w = 1'd1;
                cfg_base_w = 32'h00427000;
                layer_id_w = 5'd12;
            end
            // L13: L12 -> L13
            7'd41: begin
                cmd_op_w = 2'd3;
                cmd_input_base_w = 32'h0211d000;
                cmd_output_base_w = 32'h0205a000;
                cmd_input_plane_stride_w = 32'h00003c00;
                cmd_output_plane_stride_w = 32'h0000f000;
                cmd_input_width_w = 11'd40;
                cmd_input_height_w = 16'd24;
                cmd_cin_blocks_w = 6'd8;
                layer_id_w = 5'd13;
            end
            // L15.split: L14 -> L15.split
            7'd42: begin
                cmd_input_base_w = 32'h0205a000;
                cmd_output_base_w = 32'h02885000;
                cmd_input_plane_stride_w = 32'h0000f000;
                cmd_output_plane_stride_w = 32'h0000f000;
                cmd_weight_base_w = 32'h0025ba00;
                cmd_weight_block_stride_w = 32'h00001800;
                cmd_input_width_w = 11'd80;
                cmd_input_height_w = 16'd48;
                cmd_output_width_pairs_w = 10'd40;
                cmd_output_height_w = 16'd48;
                cmd_cin_blocks_w = 6'd12;
                cmd_output_blocks_w = 5'd2;
                cmd_cache_bank_stride_w = 9'd20;
                cmd_cache_row_stride_w = 10'd240;
                cmd_tile_pairs_w = 10'd4;
                cmd_lut_enable_w = 1'd1;
                cfg_base_w = 32'h00427800;
                layer_id_w = 5'd15;
            end
            // L15.b0.cv1: L15.g1 -> L15.temp
            7'd43: begin
                cmd_input_base_w = 32'h028a3000;
                cmd_output_base_w = 32'h02939000;
                cmd_input_plane_stride_w = 32'h0000f000;
                cmd_output_plane_stride_w = 32'h0000f000;
                cmd_weight_base_w = 32'h0025ea00;
                cmd_weight_block_stride_w = 32'h00002400;
                cmd_input_width_w = 11'd80;
                cmd_input_height_w = 16'd48;
                cmd_output_width_pairs_w = 10'd40;
                cmd_output_height_w = 16'd48;
                cmd_cin_blocks_w = 6'd2;
                cmd_output_blocks_w = 5'd1;
                cmd_cache_bank_stride_w = 9'd20;
                cmd_cache_row_stride_w = 10'd40;
                cmd_tile_pairs_w = 10'd4;
                cmd_kernel3_w = 1'd1;
                cmd_lut_enable_w = 1'd1;
                cfg_base_w = 32'h00427c00;
                layer_id_w = 5'd15;
            end
            // L15.b0.cv2: L15.temp -> L15.g2
            7'd44: begin
                cmd_input_base_w = 32'h02939000;
                cmd_output_base_w = 32'h028c1000;
                cmd_input_plane_stride_w = 32'h0000f000;
                cmd_output_plane_stride_w = 32'h0000f000;
                cmd_weight_base_w = 32'h00260e00;
                cmd_weight_block_stride_w = 32'h00002400;
                cmd_input_width_w = 11'd80;
                cmd_input_height_w = 16'd48;
                cmd_output_width_pairs_w = 10'd40;
                cmd_output_height_w = 16'd48;
                cmd_cin_blocks_w = 6'd2;
                cmd_output_blocks_w = 5'd1;
                cmd_cache_bank_stride_w = 9'd20;
                cmd_cache_row_stride_w = 10'd40;
                cmd_tile_pairs_w = 10'd4;
                cmd_kernel3_w = 1'd1;
                cmd_lut_enable_w = 1'd1;
                cfg_base_w = 32'h00427e00;
                layer_id_w = 5'd15;
            end
            // L15.fuse: L15.workspace -> L15
            7'd45: begin
                cmd_input_base_w = 32'h02885000;
                cmd_output_base_w = 32'h0276a000;
                cmd_input_plane_stride_w = 32'h0000f000;
                cmd_output_plane_stride_w = 32'h0000f000;
                cmd_weight_base_w = 32'h00263200;
                cmd_weight_block_stride_w = 32'h00000c00;
                cmd_input_width_w = 11'd80;
                cmd_input_height_w = 16'd48;
                cmd_output_width_pairs_w = 10'd40;
                cmd_output_height_w = 16'd48;
                cmd_cin_blocks_w = 6'd6;
                cmd_output_blocks_w = 5'd2;
                cmd_cache_bank_stride_w = 9'd20;
                cmd_cache_row_stride_w = 10'd120;
                cmd_tile_pairs_w = 10'd4;
                cmd_lut_enable_w = 1'd1;
                cfg_base_w = 32'h00428000;
                layer_id_w = 5'd15;
            end
            // L16: L15 -> L16
            7'd46: begin
                cmd_input_base_w = 32'h0276a000;
                cmd_output_base_w = 32'h0210e000;
                cmd_input_plane_stride_w = 32'h0000f000;
                cmd_output_plane_stride_w = 32'h00003c00;
                cmd_weight_base_w = 32'h00264a00;
                cmd_weight_block_stride_w = 32'h00004800;
                cmd_input_width_w = 11'd80;
                cmd_input_height_w = 16'd48;
                cmd_output_width_pairs_w = 10'd20;
                cmd_output_height_w = 16'd24;
                cmd_cin_blocks_w = 6'd4;
                cmd_output_blocks_w = 5'd2;
                cmd_cache_bank_stride_w = 9'd20;
                cmd_cache_row_stride_w = 10'd80;
                cmd_tile_pairs_w = 10'd4;
                cmd_kernel3_w = 1'd1;
                cmd_stride2_w = 1'd1;
                cmd_lut_enable_w = 1'd1;
                cfg_base_w = 32'h00428400;
                layer_id_w = 5'd16;
            end
            // L18.split: L17 -> L18.split
            7'd47: begin
                cmd_input_base_w = 32'h0210e000;
                cmd_output_base_w = 32'h02885000;
                cmd_input_plane_stride_w = 32'h00003c00;
                cmd_output_plane_stride_w = 32'h00003c00;
                cmd_weight_base_w = 32'h0026da00;
                cmd_weight_block_stride_w = 32'h00001800;
                cmd_input_width_w = 11'd40;
                cmd_input_height_w = 16'd24;
                cmd_output_width_pairs_w = 10'd20;
                cmd_output_height_w = 16'd24;
                cmd_cin_blocks_w = 6'd12;
                cmd_output_blocks_w = 5'd4;
                cmd_cache_bank_stride_w = 9'd10;
                cmd_cache_row_stride_w = 10'd120;
                cmd_tile_pairs_w = 10'd4;
                cmd_lut_enable_w = 1'd1;
                cfg_base_w = 32'h00428800;
                layer_id_w = 5'd18;
            end
            // L18.b0.cv1: L18.g1 -> L18.temp
            7'd48: begin
                cmd_input_base_w = 32'h02894000;
                cmd_output_base_w = 32'h02939000;
                cmd_input_plane_stride_w = 32'h00003c00;
                cmd_output_plane_stride_w = 32'h00003c00;
                cmd_weight_base_w = 32'h00273a00;
                cmd_weight_block_stride_w = 32'h00004800;
                cmd_input_width_w = 11'd40;
                cmd_input_height_w = 16'd24;
                cmd_output_width_pairs_w = 10'd20;
                cmd_output_height_w = 16'd24;
                cmd_cin_blocks_w = 6'd4;
                cmd_output_blocks_w = 5'd2;
                cmd_cache_bank_stride_w = 9'd10;
                cmd_cache_row_stride_w = 10'd40;
                cmd_tile_pairs_w = 10'd4;
                cmd_kernel3_w = 1'd1;
                cmd_lut_enable_w = 1'd1;
                cfg_base_w = 32'h00429000;
                layer_id_w = 5'd18;
            end
            // L18.b0.cv2: L18.temp -> L18.g2
            7'd49: begin
                cmd_input_base_w = 32'h02939000;
                cmd_output_base_w = 32'h028a3000;
                cmd_input_plane_stride_w = 32'h00003c00;
                cmd_output_plane_stride_w = 32'h00003c00;
                cmd_weight_base_w = 32'h0027ca00;
                cmd_weight_block_stride_w = 32'h00004800;
                cmd_input_width_w = 11'd40;
                cmd_input_height_w = 16'd24;
                cmd_output_width_pairs_w = 10'd20;
                cmd_output_height_w = 16'd24;
                cmd_cin_blocks_w = 6'd4;
                cmd_output_blocks_w = 5'd2;
                cmd_cache_bank_stride_w = 9'd10;
                cmd_cache_row_stride_w = 10'd40;
                cmd_tile_pairs_w = 10'd4;
                cmd_kernel3_w = 1'd1;
                cmd_lut_enable_w = 1'd1;
                cfg_base_w = 32'h00429400;
                layer_id_w = 5'd18;
            end
            // L18.fuse: L18.workspace -> L18
            7'd50: begin
                cmd_input_base_w = 32'h02885000;
                cmd_output_base_w = 32'h027a6000;
                cmd_input_plane_stride_w = 32'h00003c00;
                cmd_output_plane_stride_w = 32'h00003c00;
                cmd_weight_base_w = 32'h00285a00;
                cmd_weight_block_stride_w = 32'h00001800;
                cmd_input_width_w = 11'd40;
                cmd_input_height_w = 16'd24;
                cmd_output_width_pairs_w = 10'd20;
                cmd_output_height_w = 16'd24;
                cmd_cin_blocks_w = 6'd12;
                cmd_output_blocks_w = 5'd4;
                cmd_cache_bank_stride_w = 9'd10;
                cmd_cache_row_stride_w = 10'd120;
                cmd_tile_pairs_w = 10'd4;
                cmd_lut_enable_w = 1'd1;
                cfg_base_w = 32'h00429800;
                layer_id_w = 5'd18;
            end
            // L19: L18 -> L19
            7'd51: begin
                cmd_input_base_w = 32'h027a6000;
                cmd_output_base_w = 32'h0213b000;
                cmd_input_plane_stride_w = 32'h00003c00;
                cmd_output_plane_stride_w = 32'h00000f00;
                cmd_weight_base_w = 32'h0028ba00;
                cmd_weight_block_stride_w = 32'h00009000;
                cmd_input_width_w = 11'd40;
                cmd_input_height_w = 16'd24;
                cmd_output_width_pairs_w = 10'd10;
                cmd_output_height_w = 16'd12;
                cmd_cin_blocks_w = 6'd8;
                cmd_output_blocks_w = 5'd4;
                cmd_cache_bank_stride_w = 9'd10;
                cmd_cache_row_stride_w = 10'd80;
                cmd_tile_pairs_w = 10'd4;
                cmd_kernel3_w = 1'd1;
                cmd_stride2_w = 1'd1;
                cmd_lut_enable_w = 1'd1;
                cfg_base_w = 32'h0042a000;
                layer_id_w = 5'd19;
            end
            // L21.split: L20 -> L21.split
            7'd52: begin
                cmd_input_base_w = 32'h0213b000;
                cmd_output_base_w = 32'h02885000;
                cmd_input_plane_stride_w = 32'h00000f00;
                cmd_output_plane_stride_w = 32'h00000f00;
                cmd_weight_base_w = 32'h002afa00;
                cmd_weight_block_stride_w = 32'h00003000;
                cmd_input_width_w = 11'd20;
                cmd_input_height_w = 16'd12;
                cmd_output_width_pairs_w = 10'd10;
                cmd_output_height_w = 16'd12;
                cmd_cin_blocks_w = 6'd24;
                cmd_output_blocks_w = 5'd8;
                cmd_cache_bank_stride_w = 9'd5;
                cmd_cache_row_stride_w = 10'd120;
                cmd_tile_pairs_w = 10'd4;
                cmd_lut_enable_w = 1'd1;
                cfg_base_w = 32'h0042a800;
                layer_id_w = 5'd21;
            end
            // L21.b0.cv1: L21.g1 -> L21.temp
            7'd53: begin
                cmd_input_base_w = 32'h0288c800;
                cmd_output_base_w = 32'h02939000;
                cmd_input_plane_stride_w = 32'h00000f00;
                cmd_output_plane_stride_w = 32'h00000f00;
                cmd_weight_base_w = 32'h002c7a00;
                cmd_weight_block_stride_w = 32'h00009000;
                cmd_input_width_w = 11'd20;
                cmd_input_height_w = 16'd12;
                cmd_output_width_pairs_w = 10'd10;
                cmd_output_height_w = 16'd12;
                cmd_cin_blocks_w = 6'd8;
                cmd_output_blocks_w = 5'd4;
                cmd_cache_bank_stride_w = 9'd5;
                cmd_cache_row_stride_w = 10'd40;
                cmd_tile_pairs_w = 10'd4;
                cmd_kernel3_w = 1'd1;
                cmd_lut_enable_w = 1'd1;
                cfg_base_w = 32'h0042b800;
                layer_id_w = 5'd21;
            end
            // L21.b0.cv2: L21.temp -> L21.g2
            7'd54: begin
                cmd_input_base_w = 32'h02939000;
                cmd_output_base_w = 32'h02894000;
                cmd_input_plane_stride_w = 32'h00000f00;
                cmd_output_plane_stride_w = 32'h00000f00;
                cmd_weight_base_w = 32'h002eba00;
                cmd_weight_block_stride_w = 32'h00009000;
                cmd_input_width_w = 11'd20;
                cmd_input_height_w = 16'd12;
                cmd_output_width_pairs_w = 10'd10;
                cmd_output_height_w = 16'd12;
                cmd_cin_blocks_w = 6'd8;
                cmd_output_blocks_w = 5'd4;
                cmd_cache_bank_stride_w = 9'd5;
                cmd_cache_row_stride_w = 10'd40;
                cmd_tile_pairs_w = 10'd4;
                cmd_kernel3_w = 1'd1;
                cmd_lut_enable_w = 1'd1;
                cfg_base_w = 32'h0042c000;
                layer_id_w = 5'd21;
            end
            // L21.fuse: L21.workspace -> L21
            7'd55: begin
                cmd_input_base_w = 32'h02885000;
                cmd_output_base_w = 32'h027c4000;
                cmd_input_plane_stride_w = 32'h00000f00;
                cmd_output_plane_stride_w = 32'h00000f00;
                cmd_weight_base_w = 32'h0030fa00;
                cmd_weight_block_stride_w = 32'h00003000;
                cmd_input_width_w = 11'd20;
                cmd_input_height_w = 16'd12;
                cmd_output_width_pairs_w = 10'd10;
                cmd_output_height_w = 16'd12;
                cmd_cin_blocks_w = 6'd24;
                cmd_output_blocks_w = 5'd8;
                cmd_cache_bank_stride_w = 9'd5;
                cmd_cache_row_stride_w = 10'd120;
                cmd_tile_pairs_w = 10'd4;
                cmd_lut_enable_w = 1'd1;
                cfg_base_w = 32'h0042c800;
                layer_id_w = 5'd21;
            end
            // D0.box.cv0: L15 -> D0.box0
            7'd56: begin
                cmd_input_base_w = 32'h0276a000;
                cmd_output_base_w = 32'h02975000;
                cmd_input_plane_stride_w = 32'h0000f000;
                cmd_output_plane_stride_w = 32'h0000f000;
                cmd_weight_base_w = 32'h00327a00;
                cmd_weight_block_stride_w = 32'h00004800;
                cmd_input_width_w = 11'd80;
                cmd_input_height_w = 16'd48;
                cmd_output_width_pairs_w = 10'd40;
                cmd_output_height_w = 16'd48;
                cmd_cin_blocks_w = 6'd4;
                cmd_output_blocks_w = 5'd2;
                cmd_cache_bank_stride_w = 9'd20;
                cmd_cache_row_stride_w = 10'd80;
                cmd_tile_pairs_w = 10'd4;
                cmd_kernel3_w = 1'd1;
                cmd_lut_enable_w = 1'd1;
                cfg_base_w = 32'h0042d800;
                layer_id_w = 5'd22;
            end
            // D0.box.cv1: D0.box0 -> D0.box1
            7'd57: begin
                cmd_input_base_w = 32'h02975000;
                cmd_output_base_w = 32'h029c0000;
                cmd_input_plane_stride_w = 32'h0000f000;
                cmd_output_plane_stride_w = 32'h0000f000;
                cmd_weight_base_w = 32'h00330a00;
                cmd_weight_block_stride_w = 32'h00004800;
                cmd_input_width_w = 11'd80;
                cmd_input_height_w = 16'd48;
                cmd_output_width_pairs_w = 10'd40;
                cmd_output_height_w = 16'd48;
                cmd_cin_blocks_w = 6'd4;
                cmd_output_blocks_w = 5'd2;
                cmd_cache_bank_stride_w = 9'd20;
                cmd_cache_row_stride_w = 10'd80;
                cmd_tile_pairs_w = 10'd4;
                cmd_kernel3_w = 1'd1;
                cmd_lut_enable_w = 1'd1;
                cfg_base_w = 32'h0042dc00;
                layer_id_w = 5'd22;
            end
            // D0.box.out: D0.box1 -> D0.box
            7'd58: begin
                cmd_input_base_w = 32'h029c0000;
                cmd_output_base_w = 32'h027d3000;
                cmd_input_plane_stride_w = 32'h0000f000;
                cmd_output_plane_stride_w = 32'h0000f000;
                cmd_weight_base_w = 32'h00339a00;
                cmd_weight_block_stride_w = 32'h00000800;
                cmd_input_width_w = 11'd80;
                cmd_input_height_w = 16'd48;
                cmd_output_width_pairs_w = 10'd40;
                cmd_output_height_w = 16'd48;
                cmd_cin_blocks_w = 6'd4;
                cmd_output_blocks_w = 5'd2;
                cmd_cache_bank_stride_w = 9'd20;
                cmd_cache_row_stride_w = 10'd80;
                cmd_tile_pairs_w = 10'd4;
                cfg_base_w = 32'h0042e000;
                layer_id_w = 5'd22;
            end
            // D0.cls.cv0: L15 -> D0.cls0
            7'd59: begin
                cmd_input_base_w = 32'h0276a000;
                cmd_output_base_w = 32'h02975000;
                cmd_input_plane_stride_w = 32'h0000f000;
                cmd_output_plane_stride_w = 32'h0000f000;
                cmd_weight_base_w = 32'h0033aa00;
                cmd_weight_block_stride_w = 32'h00004800;
                cmd_input_width_w = 11'd80;
                cmd_input_height_w = 16'd48;
                cmd_output_width_pairs_w = 10'd40;
                cmd_output_height_w = 16'd48;
                cmd_cin_blocks_w = 6'd4;
                cmd_output_blocks_w = 5'd3;
                cmd_cache_bank_stride_w = 9'd20;
                cmd_cache_row_stride_w = 10'd80;
                cmd_tile_pairs_w = 10'd4;
                cmd_kernel3_w = 1'd1;
                cmd_last_c16_only_w = 1'd1;
                cmd_lut_enable_w = 1'd1;
                cfg_base_w = 32'h0042e400;
                layer_id_w = 5'd22;
            end
            // D0.cls.cv1: D0.cls0 -> D0.cls1
            7'd60: begin
                cmd_input_base_w = 32'h02975000;
                cmd_output_base_w = 32'h029c0000;
                cmd_input_plane_stride_w = 32'h0000f000;
                cmd_output_plane_stride_w = 32'h0000f000;
                cmd_weight_base_w = 32'h00348200;
                cmd_weight_block_stride_w = 32'h00005a00;
                cmd_input_width_w = 11'd80;
                cmd_input_height_w = 16'd48;
                cmd_output_width_pairs_w = 10'd40;
                cmd_output_height_w = 16'd48;
                cmd_cin_blocks_w = 6'd5;
                cmd_output_blocks_w = 5'd3;
                cmd_cache_bank_stride_w = 9'd20;
                cmd_cache_row_stride_w = 10'd100;
                cmd_tile_pairs_w = 10'd4;
                cmd_kernel3_w = 1'd1;
                cmd_last_c16_only_w = 1'd1;
                cmd_lut_enable_w = 1'd1;
                cfg_base_w = 32'h0042ea00;
                layer_id_w = 5'd22;
            end
            // D0.cls.out: D0.cls1 -> D0.cls
            7'd61: begin
                cmd_input_base_w = 32'h029c0000;
                cmd_output_base_w = 32'h0280f000;
                cmd_input_plane_stride_w = 32'h0000f000;
                cmd_output_plane_stride_w = 32'h0000f000;
                cmd_weight_base_w = 32'h00359000;
                cmd_weight_block_stride_w = 32'h00000a00;
                cmd_input_width_w = 11'd80;
                cmd_input_height_w = 16'd48;
                cmd_output_width_pairs_w = 10'd40;
                cmd_output_height_w = 16'd48;
                cmd_cin_blocks_w = 6'd5;
                cmd_output_blocks_w = 5'd3;
                cmd_cache_bank_stride_w = 9'd20;
                cmd_cache_row_stride_w = 10'd100;
                cmd_tile_pairs_w = 10'd4;
                cmd_last_c16_only_w = 1'd1;
                cfg_base_w = 32'h0042f000;
                layer_id_w = 5'd22;
            end
            // D1.box.cv0: L18 -> D1.box0
            7'd62: begin
                cmd_input_base_w = 32'h027a6000;
                cmd_output_base_w = 32'h02975000;
                cmd_input_plane_stride_w = 32'h00003c00;
                cmd_output_plane_stride_w = 32'h00003c00;
                cmd_weight_base_w = 32'h0035ae00;
                cmd_weight_block_stride_w = 32'h00009000;
                cmd_input_width_w = 11'd40;
                cmd_input_height_w = 16'd24;
                cmd_output_width_pairs_w = 10'd20;
                cmd_output_height_w = 16'd24;
                cmd_cin_blocks_w = 6'd8;
                cmd_output_blocks_w = 5'd2;
                cmd_cache_bank_stride_w = 9'd10;
                cmd_cache_row_stride_w = 10'd80;
                cmd_tile_pairs_w = 10'd4;
                cmd_kernel3_w = 1'd1;
                cmd_lut_enable_w = 1'd1;
                cfg_base_w = 32'h0042f600;
                layer_id_w = 5'd22;
            end
            // D1.box.cv1: D1.box0 -> D1.box1
            7'd63: begin
                cmd_input_base_w = 32'h02975000;
                cmd_output_base_w = 32'h029c0000;
                cmd_input_plane_stride_w = 32'h00003c00;
                cmd_output_plane_stride_w = 32'h00003c00;
                cmd_weight_base_w = 32'h0036ce00;
                cmd_weight_block_stride_w = 32'h00004800;
                cmd_input_width_w = 11'd40;
                cmd_input_height_w = 16'd24;
                cmd_output_width_pairs_w = 10'd20;
                cmd_output_height_w = 16'd24;
                cmd_cin_blocks_w = 6'd4;
                cmd_output_blocks_w = 5'd2;
                cmd_cache_bank_stride_w = 9'd10;
                cmd_cache_row_stride_w = 10'd40;
                cmd_tile_pairs_w = 10'd4;
                cmd_kernel3_w = 1'd1;
                cmd_lut_enable_w = 1'd1;
                cfg_base_w = 32'h0042fa00;
                layer_id_w = 5'd22;
            end
            // D1.box.out: D1.box1 -> D1.box
            7'd64: begin
                cmd_input_base_w = 32'h029c0000;
                cmd_output_base_w = 32'h0285a000;
                cmd_input_plane_stride_w = 32'h00003c00;
                cmd_output_plane_stride_w = 32'h00003c00;
                cmd_weight_base_w = 32'h00375e00;
                cmd_weight_block_stride_w = 32'h00000800;
                cmd_input_width_w = 11'd40;
                cmd_input_height_w = 16'd24;
                cmd_output_width_pairs_w = 10'd20;
                cmd_output_height_w = 16'd24;
                cmd_cin_blocks_w = 6'd4;
                cmd_output_blocks_w = 5'd2;
                cmd_cache_bank_stride_w = 9'd10;
                cmd_cache_row_stride_w = 10'd40;
                cmd_tile_pairs_w = 10'd4;
                cfg_base_w = 32'h0042fe00;
                layer_id_w = 5'd22;
            end
            // D1.cls.cv0: L18 -> D1.cls0
            7'd65: begin
                cmd_input_base_w = 32'h027a6000;
                cmd_output_base_w = 32'h02975000;
                cmd_input_plane_stride_w = 32'h00003c00;
                cmd_output_plane_stride_w = 32'h00003c00;
                cmd_weight_base_w = 32'h00376e00;
                cmd_weight_block_stride_w = 32'h00009000;
                cmd_input_width_w = 11'd40;
                cmd_input_height_w = 16'd24;
                cmd_output_width_pairs_w = 10'd20;
                cmd_output_height_w = 16'd24;
                cmd_cin_blocks_w = 6'd8;
                cmd_output_blocks_w = 5'd3;
                cmd_cache_bank_stride_w = 9'd10;
                cmd_cache_row_stride_w = 10'd80;
                cmd_tile_pairs_w = 10'd4;
                cmd_kernel3_w = 1'd1;
                cmd_last_c16_only_w = 1'd1;
                cmd_lut_enable_w = 1'd1;
                cfg_base_w = 32'h00430200;
                layer_id_w = 5'd22;
            end
            // D1.cls.cv1: D1.cls0 -> D1.cls1
            7'd66: begin
                cmd_input_base_w = 32'h02975000;
                cmd_output_base_w = 32'h029c0000;
                cmd_input_plane_stride_w = 32'h00003c00;
                cmd_output_plane_stride_w = 32'h00003c00;
                cmd_weight_base_w = 32'h00391e00;
                cmd_weight_block_stride_w = 32'h00005a00;
                cmd_input_width_w = 11'd40;
                cmd_input_height_w = 16'd24;
                cmd_output_width_pairs_w = 10'd20;
                cmd_output_height_w = 16'd24;
                cmd_cin_blocks_w = 6'd5;
                cmd_output_blocks_w = 5'd3;
                cmd_cache_bank_stride_w = 9'd10;
                cmd_cache_row_stride_w = 10'd50;
                cmd_tile_pairs_w = 10'd4;
                cmd_kernel3_w = 1'd1;
                cmd_last_c16_only_w = 1'd1;
                cmd_lut_enable_w = 1'd1;
                cfg_base_w = 32'h00430800;
                layer_id_w = 5'd22;
            end
            // D1.cls.out: D1.cls1 -> D1.cls
            7'd67: begin
                cmd_input_base_w = 32'h029c0000;
                cmd_output_base_w = 32'h02869000;
                cmd_input_plane_stride_w = 32'h00003c00;
                cmd_output_plane_stride_w = 32'h00003c00;
                cmd_weight_base_w = 32'h003a2c00;
                cmd_weight_block_stride_w = 32'h00000a00;
                cmd_input_width_w = 11'd40;
                cmd_input_height_w = 16'd24;
                cmd_output_width_pairs_w = 10'd20;
                cmd_output_height_w = 16'd24;
                cmd_cin_blocks_w = 6'd5;
                cmd_output_blocks_w = 5'd3;
                cmd_cache_bank_stride_w = 9'd10;
                cmd_cache_row_stride_w = 10'd50;
                cmd_tile_pairs_w = 10'd4;
                cmd_last_c16_only_w = 1'd1;
                cfg_base_w = 32'h00430e00;
                layer_id_w = 5'd22;
            end
            // D2.box.cv0: L21 -> D2.box0
            7'd68: begin
                cmd_input_base_w = 32'h027c4000;
                cmd_output_base_w = 32'h02975000;
                cmd_input_plane_stride_w = 32'h00000f00;
                cmd_output_plane_stride_w = 32'h00000f00;
                cmd_weight_base_w = 32'h003a4a00;
                cmd_weight_block_stride_w = 32'h00012000;
                cmd_input_width_w = 11'd20;
                cmd_input_height_w = 16'd12;
                cmd_output_width_pairs_w = 10'd10;
                cmd_output_height_w = 16'd12;
                cmd_cin_blocks_w = 6'd16;
                cmd_output_blocks_w = 5'd2;
                cmd_cache_bank_stride_w = 9'd5;
                cmd_cache_row_stride_w = 10'd80;
                cmd_tile_pairs_w = 10'd3;
                cmd_kernel3_w = 1'd1;
                cmd_lut_enable_w = 1'd1;
                cfg_base_w = 32'h00431400;
                layer_id_w = 5'd22;
            end
            // D2.box.cv1: D2.box0 -> D2.box1
            7'd69: begin
                cmd_input_base_w = 32'h02975000;
                cmd_output_base_w = 32'h029c0000;
                cmd_input_plane_stride_w = 32'h00000f00;
                cmd_output_plane_stride_w = 32'h00000f00;
                cmd_weight_base_w = 32'h003c8a00;
                cmd_weight_block_stride_w = 32'h00004800;
                cmd_input_width_w = 11'd20;
                cmd_input_height_w = 16'd12;
                cmd_output_width_pairs_w = 10'd10;
                cmd_output_height_w = 16'd12;
                cmd_cin_blocks_w = 6'd4;
                cmd_output_blocks_w = 5'd2;
                cmd_cache_bank_stride_w = 9'd5;
                cmd_cache_row_stride_w = 10'd20;
                cmd_tile_pairs_w = 10'd4;
                cmd_kernel3_w = 1'd1;
                cmd_lut_enable_w = 1'd1;
                cfg_base_w = 32'h00431800;
                layer_id_w = 5'd22;
            end
            // D2.box.out: D2.box1 -> D2.box
            7'd70: begin
                cmd_input_base_w = 32'h029c0000;
                cmd_output_base_w = 32'h0287c000;
                cmd_input_plane_stride_w = 32'h00000f00;
                cmd_output_plane_stride_w = 32'h00000f00;
                cmd_weight_base_w = 32'h003d1a00;
                cmd_weight_block_stride_w = 32'h00000800;
                cmd_input_width_w = 11'd20;
                cmd_input_height_w = 16'd12;
                cmd_output_width_pairs_w = 10'd10;
                cmd_output_height_w = 16'd12;
                cmd_cin_blocks_w = 6'd4;
                cmd_output_blocks_w = 5'd2;
                cmd_cache_bank_stride_w = 9'd5;
                cmd_cache_row_stride_w = 10'd20;
                cmd_tile_pairs_w = 10'd4;
                cfg_base_w = 32'h00431c00;
                layer_id_w = 5'd22;
            end
            // D2.cls.cv0: L21 -> D2.cls0
            7'd71: begin
                cmd_input_base_w = 32'h027c4000;
                cmd_output_base_w = 32'h02975000;
                cmd_input_plane_stride_w = 32'h00000f00;
                cmd_output_plane_stride_w = 32'h00000f00;
                cmd_weight_base_w = 32'h003d2a00;
                cmd_weight_block_stride_w = 32'h00012000;
                cmd_input_width_w = 11'd20;
                cmd_input_height_w = 16'd12;
                cmd_output_width_pairs_w = 10'd10;
                cmd_output_height_w = 16'd12;
                cmd_cin_blocks_w = 6'd16;
                cmd_output_blocks_w = 5'd3;
                cmd_cache_bank_stride_w = 9'd5;
                cmd_cache_row_stride_w = 10'd80;
                cmd_tile_pairs_w = 10'd3;
                cmd_kernel3_w = 1'd1;
                cmd_last_c16_only_w = 1'd1;
                cmd_lut_enable_w = 1'd1;
                cfg_base_w = 32'h00432000;
                layer_id_w = 5'd22;
            end
            // D2.cls.cv1: D2.cls0 -> D2.cls1
            7'd72: begin
                cmd_input_base_w = 32'h02975000;
                cmd_output_base_w = 32'h029c0000;
                cmd_input_plane_stride_w = 32'h00000f00;
                cmd_output_plane_stride_w = 32'h00000f00;
                cmd_weight_base_w = 32'h00408a00;
                cmd_weight_block_stride_w = 32'h00005a00;
                cmd_input_width_w = 11'd20;
                cmd_input_height_w = 16'd12;
                cmd_output_width_pairs_w = 10'd10;
                cmd_output_height_w = 16'd12;
                cmd_cin_blocks_w = 6'd5;
                cmd_output_blocks_w = 5'd3;
                cmd_cache_bank_stride_w = 9'd5;
                cmd_cache_row_stride_w = 10'd25;
                cmd_tile_pairs_w = 10'd4;
                cmd_kernel3_w = 1'd1;
                cmd_last_c16_only_w = 1'd1;
                cmd_lut_enable_w = 1'd1;
                cfg_base_w = 32'h00432600;
                layer_id_w = 5'd22;
            end
            // D2.cls.out: D2.cls1 -> D2.cls
            7'd73: begin
                cmd_input_base_w = 32'h029c0000;
                cmd_output_base_w = 32'h0287fc00;
                cmd_input_plane_stride_w = 32'h00000f00;
                cmd_output_plane_stride_w = 32'h00000f00;
                cmd_weight_base_w = 32'h00419800;
                cmd_weight_block_stride_w = 32'h00000a00;
                cmd_input_width_w = 11'd20;
                cmd_input_height_w = 16'd12;
                cmd_output_width_pairs_w = 10'd10;
                cmd_output_height_w = 16'd12;
                cmd_cin_blocks_w = 6'd5;
                cmd_output_blocks_w = 5'd3;
                cmd_cache_bank_stride_w = 9'd5;
                cmd_cache_row_stride_w = 10'd25;
                cmd_tile_pairs_w = 10'd4;
                cmd_last_c16_only_w = 1'd1;
                cfg_base_w = 32'h00432c00;
                layer_id_w = 5'd22;
            end
            default: begin end
        endcase
    end

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            state_r <= S_IDLE;
            step_r <= 7'd0;
            done_r <= 1'b0;
            error_r <= 1'b0;
        end else begin
            done_r <= 1'b0;
            if (abort_i && state_r != S_IDLE) begin
                error_r <= 1'b1;
                done_r <= 1'b1;
                state_r <= S_IDLE;
            end else case (state_r)
                S_IDLE: if (start_i) begin
                    step_r <= 7'd0;
                    error_r <= 1'b0;
                    state_r <= S_ISSUE;
                end
                S_ISSUE: if (cmd_ready_i)
                    state_r <= S_WAIT;
                S_WAIT: if (cmd_done_i) begin
                    if (cmd_error_i || step_r == 7'd73) begin
                        error_r <= cmd_error_i;
                        done_r <= 1'b1;
                        state_r <= S_IDLE;
                    end else begin
                        step_r <= step_r + 7'd1;
                        state_r <= S_ISSUE;
                    end
                end
                default: state_r <= S_IDLE;
            endcase
        end
    end
endmodule
