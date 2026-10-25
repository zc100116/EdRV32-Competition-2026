// ============================================================================
// File        : edrv32_if2_stage.v
// Description : Receives instruction-cache blocks in request order, discards
//               responses from an obsolete fetch epoch, and presents the
//               oldest instruction-alignment window from a six-halfword FIFO.
// ============================================================================
`include "edrv32_uop.vh"

// The stage directly owns its execution logic and outgoing registered boundary.
module edrv32_if2_stage #(
    parameter [31:0] RESET_PC = 32'h8000_0000,
    parameter integer DUAL_WINDOW = 0,
    parameter integer FETCH_WIDE = 0
)(
    input  wire                         clk_i,
    input  wire                         rst_n_i,

    input wire [31:0] block_upper_i,
    input wire [1:0] block_words_i,
    output wire hpm_second_append_hw2_o,
    input wire block_predicted_taken2_i,
    input wire [31:0] block_predicted_target2_i,
    input wire [1:0] block_predictor_meta2_i,
    input wire block_predicted_taken3_i,
    input wire [31:0] block_predicted_target3_i,
    input wire [1:0] block_predictor_meta3_i,

    // Returned fetch block from IF1.
    input  wire                         block_valid_i,
    output wire                         block_ready_o,
    input  wire [31:0]                  block_addr_i,
    input  wire [31:0]                  block_data_i,
    input  wire                         block_error_i,
    input  wire [`EDRV32_EPOCH_W-1:0]   block_epoch_i,
    input  wire                         block_predicted_taken0_i,
    input  wire [31:0]                  block_predicted_target0_i,
    input  wire [1:0]                   block_predictor_meta0_i,
    input  wire                         block_predicted_taken1_i,
    input  wire [31:0]                  block_predicted_target1_i,
    input  wire [1:0]                   block_predictor_meta1_i,
    input  wire                         preview_valid_i,
    input  wire [31:0]                  preview_addr_i,
    input  wire [`EDRV32_EPOCH_W-1:0]   preview_epoch_i,
    input  wire [31:0]                  preview_target0_i,
    input  wire [31:0]                  preview_target1_i,

    // Registered halfword window presented to ALIGN.
    output wire                         window_valid_o,
    input  wire                         window_ready_i,
    output wire [15:0]                  halfword0_o,
    output wire [15:0]                  halfword1_o,
    output wire                         halfword1_valid_o,
    output wire [31:0]                  window_pc_o,
    output wire                         halfword0_error_o,
    output wire                         halfword1_error_o,
    output wire [`EDRV32_EPOCH_W-1:0]   window_epoch_o,
    output wire                         window_predicted_taken_o,
    output wire [31:0]                  window_predicted_target_o,
    output wire [1:0]                   window_predictor_meta_o,

    // Optional second complete instruction window, always younger.
    output wire                             second_window_valid_o,
    input  wire                             second_window_accept_i,
    output wire [15:0]                      second_halfword0_o,
    output wire [15:0]                      second_halfword1_o,
    output wire                             second_halfword1_valid_o,
    output wire [31:0]                      second_window_pc_o,
    output wire                             second_halfword0_error_o,
    output wire                             second_halfword1_error_o,
    output wire [`EDRV32_EPOCH_W-1:0]       second_window_epoch_o,
    output wire                             second_window_predicted_taken_o,
    output wire [31:0]                      second_window_predicted_target_o,
    output wire [1:0]                       second_window_predictor_meta_o,
    output wire [2:0]                   hpm_consume_halfwords_o,

    // Early redirect request formed by the same IF2-window capture event.
    output wire                         prediction_redirect_valid_o,
    output wire [31:0]                  prediction_redirect_target_o,
    output wire                         prediction_redirect_fast_o,
    output wire                         prediction_redirect_fast_slot1_o,
    input  wire                         prediction_redirect_fire_i,
    input  wire [`EDRV32_EPOCH_W-1:0]   prediction_redirect_epoch_i,

    // HPM observation: halfword append/consume accounting and discarded
    // (epoch-mismatched or redirect-superseded) returned blocks.
    output wire                         hpm_append_hw1_o,
    output wire                         hpm_append_hw2_o,
    output wire                         hpm_consume_hw1_o,
    output wire                         hpm_consume_hw2_o,
    output wire                             hpm_second_consume_hw1_o,
    output wire                             hpm_second_consume_hw2_o,
    output wire                         hpm_discard_block_o,
    output wire                         hpm_pred_append_slot0_o,
    output wire                         hpm_pred_append_slot1_o,
    output wire                         hpm_pred_append_cross_o,
    output wire                         hpm_pred_candidate_o,
    output wire                         hpm_discard_stale_o,
    output wire                         hpm_discard_arch_redirect_o,
    output wire                         hpm_discard_pred_redirect_o,

    // Architectural stream recovery and boundary squash.
    input  wire                         redirect_fire_i,
    input  wire [31:0]                  redirect_target_i,
    input  wire [`EDRV32_EPOCH_W-1:0]   redirect_epoch_i,
    input  wire                         kill_i
);

    localparam integer FIFO_HALFWORDS = (FETCH_WIDE != 0) ? 12 : 6;
    localparam integer PTR_W = (FETCH_WIDE != 0) ? 4 : 3;
    localparam [PTR_W-1:0] LAST_FIFO_PTR = FIFO_HALFWORDS - 1;
    wire block_wide_w = (FETCH_WIDE != 0) && (block_words_i == 2'd2);
    wire [2:0] block_halfwords_w = block_wide_w ? 3'd4 : 3'd2;
    wire [31:0] block_stride_w = block_wide_w ? 32'd8 : 32'd4;
    reg [15:0] incoming_halfword_w [0:3];
    reg incoming_taken_w [0:3];
    reg [31:0] incoming_target_w [0:3];
    reg [1:0] incoming_meta_w [0:3];
    wire [1:0] ingress_skip_w = first_block_upper_only_w ? 2'd1 : 2'd0;

    wire                       candidate_valid_w;
    wire [15:0]                candidate_halfword0_w;
    wire [15:0]                candidate_halfword1_w;
    wire                       candidate_halfword1_valid_w;
    wire [31:0]                candidate_pc_w;
    wire                       candidate_halfword0_error_w;
    wire                       candidate_halfword1_error_w;
    wire [`EDRV32_EPOCH_W-1:0] candidate_epoch_w;
    wire                       candidate_predicted_taken_w;
    wire [31:0]                candidate_predicted_target_w;
    wire [1:0]                 candidate_predictor_meta_w;
    wire                       candidate_accept_w;
    wire [1:0]                 candidate_halfwords_w;
    wire                       candidate_compressed_w;
    wire                       candidate_formable_w;
    wire                       candidate_ready_w;
    reg  [2:0]                 window_count_r;
    wire                       window_full_w;
    wire                       window_empty_w;
    wire                       window_capture_w;
    wire                       window_transfer_w;
    wire                       window_head_we_w;
    wire                       window_head_from_tail_w;
    wire                       window_tail_we_w;

    // Stage-local execution logic is written directly in this module.


    reg [15:0] halfword_r [0:FIFO_HALFWORDS-1];
    reg        error_r [0:FIFO_HALFWORDS-1];
    reg        predicted_taken_r [0:FIFO_HALFWORDS-1];
    reg [31:0] predicted_target_r [0:FIFO_HALFWORDS-1];
    reg [1:0]  predictor_meta_r [0:FIFO_HALFWORDS-1];
    reg        prediction_redirected_r [0:FIFO_HALFWORDS-1];
    reg [PTR_W-1:0]  count_r;
    reg [PTR_W-1:0]  head_r;
    reg [PTR_W-1:0]  tail_r;
    reg [31:0] consume_pc_r;
    reg [31:0] expected_block_addr_r;
    reg [`EDRV32_EPOCH_W-1:0] active_epoch_r;
    reg first_block_r;
    reg first_block_skip_lower_r;
    reg next_block_lower_start_r;
    reg cross_block_prediction_r;
    reg [31:0] cross_block_prediction_target_r;
    function [PTR_W-1:0] increment_ptr;
        input [PTR_W-1:0] ptr_i;
        begin
            increment_ptr = (ptr_i == LAST_FIFO_PTR) ? 3'd0 : ptr_i + 3'd1;
        end
    endfunction

    function [PTR_W-1:0] decrement_ptr;
        input [PTR_W-1:0] ptr_i;
        begin
            decrement_ptr = (ptr_i == 3'd0) ? LAST_FIFO_PTR : ptr_i - 3'd1;
        end
    endfunction

    function [PTR_W-1:0] advance_ptr;
        input [PTR_W-1:0] ptr_i;
        input [PTR_W-1:0] amount_i;
        reg [PTR_W:0] sum_v;
        begin
            sum_v = {1'b0, ptr_i} + {1'b0, amount_i};
            advance_ptr = (sum_v >= FIFO_HALFWORDS)
                ? sum_v - FIFO_HALFWORDS : sum_v[PTR_W-1:0];
        end
    endfunction

    // Decode only direct control transfers. The first halfword of a 32-bit
    // instruction already contains its opcode and branch funct3.
    function [1:0] direct_kind;
        input [31:0] instr_i;
        begin
            direct_kind = 2'd0;
            if (instr_i[1:0] == 2'b11) begin
                if (instr_i[6:0] == 7'b1101111)
                    direct_kind = 2'd2;
                else if (instr_i[6:0] == 7'b1100011 &&
                         instr_i[14:12] != 3'b010 &&
                         instr_i[14:12] != 3'b011)
                    direct_kind = 2'd1;
            end else if (instr_i[1:0] == 2'b01) begin
                case (instr_i[15:13])
                    3'b001, 3'b101: direct_kind = 2'd2;
                    3'b110, 3'b111: direct_kind = 2'd1;
                    default: begin end
                endcase
            end
        end
    endfunction

    function [31:0] direct_target;
        input [31:0] instr_i;
        input [31:0] pc_i;
        reg [31:0] offset_v;
        begin
            offset_v = 32'd0;
            if (instr_i[1:0] == 2'b11) begin
                if (instr_i[6:0] == 7'b1101111)
                    offset_v = {{11{instr_i[31]}}, instr_i[31],
                        instr_i[19:12], instr_i[20], instr_i[30:21], 1'b0};
                else
                    offset_v = {{19{instr_i[31]}}, instr_i[31],
                        instr_i[7], instr_i[30:25], instr_i[11:8], 1'b0};
            end else if (instr_i[15:13] == 3'b001 ||
                         instr_i[15:13] == 3'b101) begin
                offset_v = {{20{instr_i[12]}}, instr_i[12], instr_i[8],
                    instr_i[10:9], instr_i[6], instr_i[7], instr_i[2],
                    instr_i[11], instr_i[5:3], 1'b0};
            end else begin
                offset_v = {{23{instr_i[12]}}, instr_i[12],
                    instr_i[6:5], instr_i[2], instr_i[11:10],
                    instr_i[4:3], 1'b0};
            end
            direct_target = pc_i + offset_v;
        end
    endfunction

    // First decide whether the returning block belongs to the active stream.
    wire [2:0] consume_count_w = (candidate_accept_w && !direct_candidate_w)
                                 ? captured_halfwords_w : 3'd0;
    wire [PTR_W-1:0] remaining_count_w = count_r - consume_count_w;
    wire first_block_upper_only_w = first_block_r &&
                                    first_block_skip_lower_r;
    wire [2:0] nominal_append_count_w = first_block_upper_only_w
        ? block_halfwords_w - 3'd1 : block_halfwords_w;
    wire block_matches_w = (block_epoch_i == active_epoch_r) &&
                           (block_addr_i == expected_block_addr_r);

    // Predecode only instruction-length boundaries at the append edge.  A
    // predicted upper-halfword 32-bit instruction is deliberately deferred:
    // its low continuation halfword has not returned yet, so redirecting here
    // would discard part of the branch instruction itself.
    wire append_slot0_compressed_w = block_data_i[1:0] != 2'b11;
    wire append_slot1_compressed_w = block_data_i[17:16] != 2'b11;
    wire [PTR_W-1:0] previous_tail_w = decrement_ptr(tail_r);
    wire [31:0] cross_instr_w =
        {block_data_i[15:0], halfword_r[previous_tail_w]};
    wire [1:0] append_slot0_kind_w = direct_kind(block_data_i);
    wire [1:0] append_slot1_kind_w =
        direct_kind({16'd0, block_data_i[31:16]});
    wire [1:0] append_cross_kind_w = direct_kind(cross_instr_w);
    wire append_slot0_taken_w = (append_slot0_kind_w == 2'd2) ||
        ((append_slot0_kind_w == 2'd1) && block_predictor_meta0_i[1]) ||
        ((append_slot0_kind_w == 2'd0) && block_predicted_taken0_i);
    wire append_slot1_taken_w = (append_slot1_kind_w == 2'd2) ||
        ((append_slot1_kind_w == 2'd1) && block_predictor_meta1_i[1]) ||
        ((append_slot1_kind_w == 2'd0) && block_predicted_taken1_i);
    wire preview_match_w = preview_valid_i && block_valid_i &&
        (preview_addr_i == block_addr_i) &&
        (preview_epoch_i == block_epoch_i);
    wire [31:0] append_slot0_target_w = (append_slot0_kind_w != 2'd0)
        ? (preview_match_w ? preview_target0_i
                           : direct_target(block_data_i, block_addr_i))
        : block_predicted_target0_i;
    wire [31:0] append_slot1_target_w = (append_slot1_kind_w != 2'd0)
        ? (preview_match_w ? preview_target1_i
                           : direct_target(slot1_instr_w,
                                           block_addr_i + 32'd2))
        : block_predicted_target1_i;
    wire [31:0] append_cross_target_w = (append_cross_kind_w != 2'd0)
        ? direct_target(cross_instr_w, block_addr_i - 32'd2)
        : cross_block_prediction_target_r;
    wire append_slot0_start_w = !first_block_upper_only_w &&
        (first_block_r || next_block_lower_start_r);
    wire append_slot1_start_w = first_block_upper_only_w ||
        (!first_block_upper_only_w &&
         (!append_slot0_start_w || append_slot0_compressed_w));
    wire [31:0] slot1_instr_w = block_wide_w
        ? {block_upper_i[15:0], block_data_i[31:16]}
        : {16'd0, block_data_i[31:16]};
    wire [1:0] append_slot2_kind_w = direct_kind(block_upper_i);
    wire [1:0] append_slot3_kind_w = direct_kind({16'd0, block_upper_i[31:16]});
    wire append_slot2_compressed_w = block_upper_i[1:0] != 2'b11;
    wire append_slot3_compressed_w = block_upper_i[17:16] != 2'b11;
    wire append_slot2_start_w = block_wide_w &&
        (!append_slot1_start_w || append_slot1_compressed_w);
    wire append_slot3_start_w = block_wide_w &&
        (!append_slot2_start_w || append_slot2_compressed_w);
    wire append_slot2_taken_w = (append_slot2_kind_w == 2'd2) ||
        ((append_slot2_kind_w == 2'd1) && block_predictor_meta2_i[1]) ||
        ((append_slot2_kind_w == 2'd0) && block_predicted_taken2_i);
    wire append_slot3_taken_w = (append_slot3_kind_w == 2'd2) ||
        ((append_slot3_kind_w == 2'd1) && block_predictor_meta3_i[1]) ||
        ((append_slot3_kind_w == 2'd0) && block_predicted_taken3_i);
    wire [31:0] append_slot2_target_w = (append_slot2_kind_w != 2'd0)
        ? direct_target(block_upper_i, block_addr_i + 32'd4) : block_predicted_target2_i;
    wire [31:0] append_slot3_target_w = (append_slot3_kind_w != 2'd0)
        ? direct_target({16'd0, block_upper_i[31:16]}, block_addr_i + 32'd6)
        : block_predicted_target3_i;
    wire append_cross_block_prediction_w = cross_block_prediction_r && !block_error_i;
    wire append_slot0_prediction_w = !append_cross_block_prediction_w &&
        append_slot0_start_w && append_slot0_taken_w && !block_error_i;
    wire append_slot1_prediction_w = !append_cross_block_prediction_w &&
        !append_slot0_prediction_w && append_slot1_start_w &&
        (append_slot1_compressed_w || block_wide_w) && append_slot1_taken_w && !block_error_i;
    wire append_slot2_prediction_w = !append_cross_block_prediction_w &&
        !append_slot0_prediction_w && !append_slot1_prediction_w &&
        append_slot2_start_w && append_slot2_taken_w && !block_error_i;
    wire append_slot3_prediction_w = !append_cross_block_prediction_w &&
        !append_slot0_prediction_w && !append_slot1_prediction_w && !append_slot2_prediction_w &&
        append_slot3_start_w && append_slot3_compressed_w && append_slot3_taken_w && !block_error_i;
    wire append_prediction_candidate_w = append_cross_block_prediction_w ||
                                         append_slot0_prediction_w ||
                                         append_slot1_prediction_w ||
                                         append_slot2_prediction_w || append_slot3_prediction_w;
    wire [31:0] append_prediction_target_w =
        append_cross_block_prediction_w ? append_cross_target_w :
        append_slot0_prediction_w ? append_slot0_target_w :
        append_slot1_prediction_w ? append_slot1_target_w :
        append_slot2_prediction_w ? append_slot2_target_w : append_slot3_target_w;
    wire [2:0] prediction_end_w = append_slot0_prediction_w
        ? (append_slot0_compressed_w ? 3'd1 : 3'd2) :
        append_slot1_prediction_w ? (append_slot1_compressed_w ? 3'd2 : 3'd3) :
        append_slot2_prediction_w ? (append_slot2_compressed_w ? 3'd3 : 3'd4) : 3'd4;
    wire [2:0] prediction_append_count_w = append_cross_block_prediction_w
        ? 3'd1 : prediction_end_w - {1'b0, ingress_skip_w};
    wire [2:0] capacity_append_count_w = append_prediction_candidate_w
        ? prediction_append_count_w : nominal_append_count_w;

    always @(*) begin
        incoming_halfword_w[0] = block_data_i[15:0];
        incoming_halfword_w[1] = block_data_i[31:16];
        incoming_halfword_w[2] = block_upper_i[15:0];
        incoming_halfword_w[3] = block_upper_i[31:16];
        incoming_taken_w[0] = append_slot0_taken_w;
        incoming_taken_w[1] = append_slot1_taken_w;
        incoming_taken_w[2] = append_slot2_taken_w;
        incoming_taken_w[3] = append_slot3_taken_w;
        incoming_target_w[0] = append_slot0_target_w;
        incoming_target_w[1] = append_slot1_target_w;
        incoming_target_w[2] = append_slot2_target_w;
        incoming_target_w[3] = append_slot3_target_w;
        incoming_meta_w[0] = block_predictor_meta0_i;
        incoming_meta_w[1] = block_predictor_meta1_i;
        incoming_meta_w[2] = block_predictor_meta2_i;
        incoming_meta_w[3] = block_predictor_meta3_i;
    end
    wire last_slot_start_w = block_wide_w ? append_slot3_start_w : append_slot1_start_w;
    wire last_slot_compressed_w = block_wide_w
        ? append_slot3_compressed_w : append_slot1_compressed_w;
    wire last_slot_taken_w = block_wide_w ? append_slot3_taken_w : append_slot1_taken_w;
    wire [31:0] last_slot_target_w = block_wide_w ? block_predicted_target3_i
        : block_predicted_target1_i;

    // Capacity deliberately depends only on registered occupancy and the
    // returned block itself.  It never depends on ALIGN/DECODE ready, so the
    // cache response CE cone remains locally bounded.
    wire [PTR_W:0] occupancy_after_append_w = {1'b0, count_r} +
                                          {1'b0, capacity_append_count_w};
    wire has_capacity_w = occupancy_after_append_w <= FIFO_HALFWORDS;

    // Empty-FIFO ingress: when no older halfword is buffered, form the
    // first complete instruction from the returned block at the capture edge.
    // The second compressed halfword remains in the local FIFO. Predicted
    // control transfers use the established append/redirect path unchanged.
    wire [15:0] direct_first_halfword_w = first_block_upper_only_w
        ? block_data_i[31:16] : block_data_i[15:0];
    wire direct_first_compressed_w = direct_first_halfword_w[1:0] != 2'b11;
    wire direct_formable_w = direct_first_compressed_w ||
                             (nominal_append_count_w >= 3'd2);
    wire direct_candidate_w = block_valid_i && block_matches_w &&
        !kill_i && !redirect_fire_i && (count_r == 3'd0) &&
        !window_full_w && !append_prediction_candidate_w &&
        direct_formable_w;
    wire [1:0] direct_halfwords_w = direct_first_compressed_w
        ? 2'd1 : 2'd2;
    assign candidate_valid_w = (count_r != 3'd0) || direct_candidate_w;
    wire [PTR_W-1:0] second_head_w = increment_ptr(head_r);
    wire [PTR_W-1:0] second_tail_w = increment_ptr(tail_r);

    assign candidate_halfword0_w = direct_candidate_w
        ? direct_first_halfword_w : halfword_r[head_r];
    assign candidate_halfword1_w = direct_candidate_w
        ? incoming_halfword_w[ingress_skip_w + 2'd1] : halfword_r[second_head_w];
    assign candidate_halfword1_valid_w = direct_candidate_w
        ? (nominal_append_count_w >= 3'd2) : (count_r >= 3'd2);
    assign candidate_pc_w            = consume_pc_r;
    assign candidate_halfword0_error_w = direct_candidate_w
        ? block_error_i : error_r[head_r];
    assign candidate_halfword1_error_w = direct_candidate_w
        ? block_error_i : error_r[second_head_w];
    assign candidate_epoch_w         = active_epoch_r;
    assign candidate_predicted_taken_w = direct_candidate_w
        ? (first_block_upper_only_w ? append_slot1_taken_w
                                     : append_slot0_taken_w)
        : predicted_taken_r[head_r];
    assign candidate_predicted_target_w = direct_candidate_w
        ? (first_block_upper_only_w ? append_slot1_target_w
                                     : append_slot0_target_w)
        : predicted_target_r[head_r];
    assign candidate_predictor_meta_w = direct_candidate_w
        ? (first_block_upper_only_w ? block_predictor_meta1_i
                                     : block_predictor_meta0_i)
        : predictor_meta_r[head_r];
    wire candidate_prediction_redirected_w = direct_candidate_w
        ? 1'b0 : prediction_redirected_r[head_r];

    // IF2 owns instruction formability and registered window capacity.
    // u_pipe below is only the payload register bank.
    assign candidate_compressed_w = candidate_halfword0_w[1:0] != 2'b11;
    assign candidate_formable_w = candidate_valid_w &&
                                  (candidate_compressed_w ||
                                   candidate_halfword1_valid_w);
    // The second capture is limited by registered window capacity and
    // complete sequential instructions. Taken predictions keep the established
    // single-window redirect path, including cross-block continuation handling.
    wire [PTR_W-1:0] second_candidate_head_w =
        advance_ptr(head_r, {1'b0, candidate_halfwords_w});
    wire [PTR_W-1:0] second_candidate_next_w = increment_ptr(second_candidate_head_w);
    wire [15:0] second_candidate_halfword0_w = direct_candidate_w
        ? incoming_halfword_w[ingress_skip_w + candidate_halfwords_w]
        : halfword_r[second_candidate_head_w];
    wire [15:0] second_candidate_halfword1_w = direct_candidate_w
        ? incoming_halfword_w[ingress_skip_w + candidate_halfwords_w + 3'd1]
        : halfword_r[second_candidate_next_w];
    wire second_candidate_compressed_w = second_candidate_halfword0_w[1:0] != 2'b11;
    wire [2:0] second_required_halfwords_w = {1'b0, candidate_halfwords_w} +
        (second_candidate_compressed_w ? 3'd1 : 3'd2);
    // Check B's registered occupancy before reading its unobservable length.
    wire second_candidate_formable_w = direct_candidate_w
        ? ((nominal_append_count_w > {1'b0, candidate_halfwords_w}) &&
           (nominal_append_count_w >= second_required_halfwords_w))
        : ((count_r > {1'b0, candidate_halfwords_w}) &&
           (count_r >= second_required_halfwords_w));
    wire second_candidate_predicted_taken_w = direct_candidate_w
        ? incoming_taken_w[ingress_skip_w + candidate_halfwords_w]
        : predicted_taken_r[second_candidate_head_w];
    wire second_candidate_halfword0_error_w = direct_candidate_w
        ? block_error_i : error_r[second_candidate_head_w];
    wire second_candidate_halfword1_error_w = direct_candidate_w
        ? block_error_i : error_r[second_candidate_next_w];
    wire second_candidate_halfword1_valid_w = direct_candidate_w
        ? (nominal_append_count_w >= ({1'b0, candidate_halfwords_w} + 3'd2))
        : (count_r >= ({1'b0, candidate_halfwords_w} + 3'd2));
    wire [31:0] second_candidate_pc_w = candidate_pc_w +
        (candidate_compressed_w ? 32'd2 : 32'd4);
    wire [31:0] second_candidate_predicted_target_w = direct_candidate_w
        ? incoming_target_w[ingress_skip_w + candidate_halfwords_w]
        : predicted_target_r[second_candidate_head_w];
    wire [1:0] second_candidate_predictor_meta_w = direct_candidate_w
        ? incoming_meta_w[ingress_skip_w + candidate_halfwords_w]
        : predictor_meta_r[second_candidate_head_w];
    wire second_capture_w = (DUAL_WINDOW != 0) && (window_count_r <= 3'd2) &&
        candidate_accept_w && second_candidate_formable_w &&
        !candidate_predicted_taken_w && !second_candidate_predicted_taken_w &&
        !candidate_halfword0_error_w &&
        (candidate_compressed_w || !candidate_halfword1_error_w);
    wire [2:0] captured_halfwords_w = {1'b0, candidate_halfwords_w} +
        (second_capture_w ? (second_candidate_compressed_w ? 3'd1 : 3'd2) : 3'd0);
    wire [31:0] captured_bytes_w = {28'd0, captured_halfwords_w, 1'b0};
    wire window_pop_two_w = (DUAL_WINDOW != 0) && window_transfer_w &&
        (window_count_r >= 3'd2) && second_window_accept_i;
    wire [2:0] window_pop_count_w = window_pop_two_w ? 3'd2
        : window_transfer_w ? 3'd1 : 3'd0;
    wire [2:0] window_capture_count_w = second_capture_w ? 3'd2
        : window_capture_w ? 3'd1 : 3'd0;
    assign second_window_valid_o = (DUAL_WINDOW != 0) && (window_count_r >= 3'd2);

    assign window_full_w        = (DUAL_WINDOW != 0)
        ? (window_count_r == 3'd4) : (window_count_r == 3'd2);
    assign window_empty_w       = (window_count_r == 2'd0);
    assign candidate_ready_w    = !kill_i && !window_full_w;
    assign candidate_accept_w   = candidate_formable_w &&
                                  candidate_ready_w;
    assign candidate_halfwords_w = candidate_compressed_w ? 2'd1 : 2'd2;
    assign window_valid_o       = !window_empty_w;
    assign window_capture_w     = candidate_accept_w;
    assign window_transfer_w    = window_valid_o && window_ready_i;

    // An older, already-buffered prediction wins over a prediction discovered
    // in the block returning on the same cycle.  The append path is otherwise
    // independent of downstream ready and may trim only younger halfwords in
    // its own returned block.
    wire candidate_prediction_valid_w = candidate_accept_w &&
        candidate_predicted_taken_w && !candidate_prediction_redirected_w &&
        !kill_i;
    wire append_prediction_valid_w = block_valid_i && block_matches_w &&
        has_capacity_w && append_prediction_candidate_w &&
        !candidate_prediction_valid_w && !redirect_fire_i;
    wire candidate_prediction_fire_w = prediction_redirect_fire_i &&
                                       candidate_prediction_valid_w;
    wire append_prediction_fire_w = prediction_redirect_fire_i &&
                                    append_prediction_valid_w;
    wire append_block_w = block_valid_i && block_ready_o && block_matches_w &&
                          !redirect_fire_i && !candidate_prediction_fire_w;
    wire [2:0] direct_consumed_count_w = direct_candidate_w
        ? captured_halfwords_w : 3'd0;
    wire [2:0] append_count_w = append_prediction_fire_w
        ? prediction_append_count_w
        : nominal_append_count_w - direct_consumed_count_w;
    // Wide ingress stores a fixed block layout. Bypassed instructions are
    // consumed by advancing the head, rather than rotating every payload
    // write through the late prediction/length/dual-capture decision cone.
    wire [2:0] physical_append_count_w = (FETCH_WIDE != 0)
        ? (append_prediction_fire_w ? prediction_append_count_w
                                    : nominal_append_count_w)
        : append_count_w;

    assign block_ready_o = redirect_fire_i || candidate_prediction_fire_w ||
                           !block_matches_w || has_capacity_w;

    assign window_head_we_w = !kill_i &&
        ((window_capture_w && window_transfer_w) ||
         (window_capture_w && !window_transfer_w && window_empty_w) ||
         (!window_capture_w && window_transfer_w && window_full_w && !window_pop_two_w));
    assign window_head_from_tail_w = !kill_i && !window_capture_w &&
                                     window_transfer_w && window_full_w && !window_pop_two_w;
    assign window_tail_we_w = !kill_i && window_capture_w &&
                              !window_transfer_w &&
                              ((window_count_r == 2'd1) || second_capture_w);

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            window_count_r <= 3'd0;
        end else if (kill_i) begin
            window_count_r <= 3'd0;
        end else begin
            window_count_r <= window_count_r + window_capture_count_w - window_pop_count_w;
        end
    end

    // count_r is the validity state for the six payload entries.  Clearing the
    // count on redirect makes old payload bits unobservable without resetting
    // the data array itself.
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            count_r <= 3'd0;
            head_r  <= 3'd0;
            tail_r  <= 3'd0;
        end else if (redirect_fire_i) begin
            count_r <= 3'd0;
            head_r  <= 3'd0;
            tail_r  <= 3'd0;
        end else if (candidate_prediction_fire_w) begin
            count_r <= 3'd0;
            head_r  <= 3'd0;
            tail_r  <= 3'd0;
        end else begin
            if (candidate_accept_w &&
                (!direct_candidate_w || (FETCH_WIDE != 0)))
                head_r <= advance_ptr(head_r, captured_halfwords_w);
            if (append_block_w)
                tail_r <= advance_ptr(tail_r, physical_append_count_w);

            case ({append_block_w, candidate_accept_w})
                2'b10: count_r <= count_r + append_count_w;
                2'b01: count_r <= remaining_count_w;
                2'b11: count_r <= remaining_count_w + append_count_w;
                default: begin end
            endcase
        end
    end

    // The stream position advances only with real consume and append events.
    // Keeping it separate from FIFO occupancy makes PC/epoch ownership clear.
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            consume_pc_r          <= RESET_PC;
            expected_block_addr_r <= {RESET_PC[31:2], 2'b00};
            active_epoch_r        <= {`EDRV32_EPOCH_W{1'b0}};
            first_block_r         <= 1'b1;
            first_block_skip_lower_r <= RESET_PC[1];
            next_block_lower_start_r <= 1'b1;
            cross_block_prediction_r <= 1'b0;
            cross_block_prediction_target_r <= 32'd0;
        end else if (redirect_fire_i) begin
            consume_pc_r          <= redirect_target_i;
            expected_block_addr_r <= {redirect_target_i[31:2], 2'b00};
            active_epoch_r        <= redirect_epoch_i;
            first_block_r         <= 1'b1;
            first_block_skip_lower_r <= redirect_target_i[1];
            next_block_lower_start_r <= 1'b1;
            cross_block_prediction_r <= 1'b0;
        end else if (candidate_prediction_fire_w) begin
            consume_pc_r <= candidate_predicted_target_w;
            expected_block_addr_r <=
                {candidate_predicted_target_w[31:2], 2'b00};
            active_epoch_r <= prediction_redirect_epoch_i;
            first_block_r <= 1'b1;
            first_block_skip_lower_r <= candidate_predicted_target_w[1];
            next_block_lower_start_r <= 1'b1;
            cross_block_prediction_r <= 1'b0;
        end else if (append_prediction_fire_w) begin
            if (candidate_accept_w) begin
                consume_pc_r <= candidate_prediction_redirected_w
                    ? candidate_predicted_target_w
                    : consume_pc_r + captured_bytes_w;
            end
            expected_block_addr_r <=
                {append_prediction_target_w[31:2], 2'b00};
            active_epoch_r <= prediction_redirect_epoch_i;
            first_block_r <= 1'b1;
            first_block_skip_lower_r <= append_prediction_target_w[1];
            next_block_lower_start_r <= 1'b1;
            cross_block_prediction_r <= 1'b0;
        end else begin
            if (candidate_accept_w) begin
                consume_pc_r <= candidate_prediction_redirected_w
                    ? candidate_predicted_target_w
                    : consume_pc_r + captured_bytes_w;
            end

            if (append_block_w) begin
                expected_block_addr_r <= expected_block_addr_r + block_stride_w;
                first_block_r <= 1'b0;
                first_block_skip_lower_r <= 1'b0;
                next_block_lower_start_r <= !last_slot_start_w || last_slot_compressed_w;
                cross_block_prediction_r <= last_slot_start_w &&
                    !last_slot_compressed_w &&
                    last_slot_taken_w && !block_error_i;
                if (last_slot_start_w && !last_slot_compressed_w &&
                    last_slot_taken_w && !block_error_i) begin
                    cross_block_prediction_target_r <=
                        last_slot_target_w;
                end
            end
        end
    end

    // Payload never moves when the consumer advances.  Only the registered
    // head pointer changes, so downstream decode cannot drive hundreds of
    // payload clock-enables.  New data is written at the registered tail.
    integer append_lane;
    wire [PTR_W-1:0] append_ptr_w [0:3];
    wire [2:0] source_lane_w [0:3];
    wire payload_lane_write_w [0:3];
    wire payload_append_w = (FETCH_WIDE != 0)
        ? (block_valid_i && block_matches_w)
        : (!redirect_fire_i && append_block_w && (append_count_w != 3'd0));
    genvar ingress_lane;
    generate
        for (ingress_lane = 0; ingress_lane < 4; ingress_lane = ingress_lane + 1)
                begin : gen_ingress_address
            assign append_ptr_w[ingress_lane] = advance_ptr(tail_r, ingress_lane);
            assign source_lane_w[ingress_lane] =
                ingress_skip_w + ingress_lane +
                ((FETCH_WIDE != 0) ? 3'd0 : direct_consumed_count_w);
            // Unaccepted/prediction-trimmed payload may be written only into
            // registered free slots. It becomes observable solely when the
            // accepted prefix advances count/tail. Never overwrite an older
            // valid halfword, even when only a short predicted prefix fits.
            assign payload_lane_write_w[ingress_lane] = (FETCH_WIDE != 0)
                ? ((ingress_lane < nominal_append_count_w) &&
                   (count_r <= (FIFO_HALFWORDS - ingress_lane - 1)))
                : (ingress_lane < append_count_w);
        end
    endgenerate
    always @(posedge clk_i) begin
        // A cross-block prediction patches an older valid halfword and must
        // therefore wait for the real accepted redirect event.
        if (!redirect_fire_i && append_block_w && (append_count_w != 3'd0) &&
            append_prediction_fire_w && append_cross_block_prediction_w) begin
            prediction_redirected_r[previous_tail_w] <= 1'b1;
            predicted_target_r[previous_tail_w] <= append_cross_target_w;
        end
        if (payload_append_w) begin
            for (append_lane = 0; append_lane < 4; append_lane = append_lane + 1) begin
                if (payload_lane_write_w[append_lane]) begin
                    halfword_r[append_ptr_w[append_lane]] <=
                        incoming_halfword_w[source_lane_w[append_lane]];
                    error_r[append_ptr_w[append_lane]] <= block_error_i;
                    predicted_taken_r[append_ptr_w[append_lane]] <=
                        incoming_taken_w[source_lane_w[append_lane]];
                    predicted_target_r[append_ptr_w[append_lane]] <=
                        incoming_target_w[source_lane_w[append_lane]];
                    predictor_meta_r[append_ptr_w[append_lane]] <=
                        incoming_meta_w[source_lane_w[append_lane]];
                    prediction_redirected_r[append_ptr_w[append_lane]] <=
                        append_prediction_fire_w &&
                        ((source_lane_w[append_lane] == 3'd0 && append_slot0_prediction_w) ||
                         (source_lane_w[append_lane] == 3'd1 && append_slot1_prediction_w) ||
                         (source_lane_w[append_lane] == 3'd2 && append_slot2_prediction_w) ||
                         (source_lane_w[append_lane] == 3'd3 && append_slot3_prediction_w));
                end
            end
        end
    end

    assign prediction_redirect_valid_o = candidate_prediction_valid_w ||
                                         append_prediction_valid_w;
    assign prediction_redirect_target_o = candidate_prediction_valid_w
        ? candidate_predicted_target_w : append_prediction_target_w;
    // The cross-block target still needs the continuation halfword in this
    // cycle. A direct single-block target may request immediately only when
    // the I-cache hit preview registered the matching address one edge ago.
    wire fast_slot0_w = append_slot0_prediction_w &&
                        (append_slot0_kind_w != 2'd0);
    wire fast_slot1_w = append_slot1_prediction_w &&
                        (append_slot1_kind_w != 2'd0);
    assign prediction_redirect_fast_o = append_prediction_valid_w &&
                                        preview_match_w &&
                                        (fast_slot0_w || fast_slot1_w);
    assign prediction_redirect_fast_slot1_o =
        prediction_redirect_fast_o && fast_slot1_w;

    // Halfword-level fetch accounting for the useful/discarded-fetch events.
    wire [2:0] accepted_halfwords_w = append_count_w +
                                       direct_consumed_count_w;
    assign hpm_append_hw1_o = append_block_w &&
                               ((accepted_halfwords_w == 3'd1) || (accepted_halfwords_w == 3'd3));
    assign hpm_append_hw2_o = append_block_w &&
                               (accepted_halfwords_w >= 3'd2);
    assign hpm_second_append_hw2_o = append_block_w && (accepted_halfwords_w == 3'd4);
    assign hpm_consume_hw1_o = candidate_accept_w &&
                               (candidate_halfwords_w == 2'd1);
    assign hpm_consume_hw2_o = candidate_accept_w &&
                               (candidate_halfwords_w == 2'd2);
    assign hpm_second_consume_hw1_o = second_capture_w && second_candidate_compressed_w;
    assign hpm_second_consume_hw2_o = second_capture_w && !second_candidate_compressed_w;
    assign hpm_consume_halfwords_o = candidate_accept_w ? captured_halfwords_w : 3'd0;
    // A returned block that this stage consumed without appending is either
    // from an obsolete epoch/stream or superseded by a same-edge redirect.
    assign hpm_discard_block_o = block_valid_i && block_ready_o &&
                                 !append_block_w;
    assign hpm_pred_append_slot0_o = append_prediction_fire_w &&
                                     append_slot0_prediction_w;
    assign hpm_pred_append_slot1_o = append_prediction_fire_w &&
                                     append_slot1_prediction_w;
    assign hpm_pred_append_cross_o = append_prediction_fire_w &&
                                     append_cross_block_prediction_w;
    assign hpm_pred_candidate_o = candidate_prediction_fire_w;
    assign hpm_discard_arch_redirect_o = hpm_discard_block_o &&
                                          redirect_fire_i;
    assign hpm_discard_pred_redirect_o = hpm_discard_block_o &&
                                          !redirect_fire_i &&
                                          candidate_prediction_fire_w;
    assign hpm_discard_stale_o = hpm_discard_block_o &&
                                 !redirect_fire_i &&
                                 !candidate_prediction_fire_w;



    generate
        if (DUAL_WINDOW != 0) begin : gen_pair_windows
            localparam integer WINDOW_W = 102 + `EDRV32_EPOCH_W;
            wire [WINDOW_W-1:0] payload0_w;
            wire [WINDOW_W-1:0] payload1_w;
            wire [WINDOW_W-1:0] payload2_w;
            wire [WINDOW_W-1:0] payload3_w;
            reg [WINDOW_W-1:0] next_payload0_w;
            reg [WINDOW_W-1:0] next_payload1_w;
            reg [WINDOW_W-1:0] next_payload2_w;
            reg [WINDOW_W-1:0] next_payload3_w;
            wire [2:0] remaining_windows_w = window_count_r - window_pop_count_w;
            wire [WINDOW_W-1:0] candidate_w = {candidate_halfword0_w,
                candidate_halfword1_w, candidate_halfword1_valid_w, candidate_pc_w,
                candidate_halfword0_error_w, candidate_halfword1_error_w, candidate_epoch_w,
                candidate_predicted_taken_w, candidate_predicted_target_w,
                candidate_predictor_meta_w};
            wire [WINDOW_W-1:0] second_candidate_w = {second_candidate_halfword0_w,
                second_candidate_halfword1_w, second_candidate_halfword1_valid_w,
                second_candidate_pc_w, second_candidate_halfword0_error_w,
                second_candidate_halfword1_error_w, candidate_epoch_w,
                second_candidate_predicted_taken_w, second_candidate_predicted_target_w,
                second_candidate_predictor_meta_w};
            assign {halfword0_o, halfword1_o, halfword1_valid_o, window_pc_o,
                halfword0_error_o, halfword1_error_o, window_epoch_o,
                window_predicted_taken_o, window_predicted_target_o,
                window_predictor_meta_o} = payload0_w;
            assign {second_halfword0_o, second_halfword1_o, second_halfword1_valid_o,
                second_window_pc_o, second_halfword0_error_o, second_halfword1_error_o,
                second_window_epoch_o, second_window_predicted_taken_o,
                second_window_predicted_target_o, second_window_predictor_meta_o} = payload1_w;

            always @(*) begin
                next_payload0_w = payload0_w;
                next_payload1_w = payload1_w;
                next_payload2_w = payload2_w;
                next_payload3_w = payload3_w;
                if (window_pop_count_w == 3'd1) begin
                    next_payload0_w = payload1_w;
                    next_payload1_w = payload2_w;
                    next_payload2_w = payload3_w;
                end else if (window_pop_count_w == 3'd2) begin
                    next_payload0_w = payload2_w;
                    next_payload1_w = payload3_w;
                end
                if (window_capture_w) begin
                    case (remaining_windows_w)
                        3'd0: next_payload0_w = candidate_w;
                        3'd1: next_payload1_w = candidate_w;
                        3'd2: next_payload2_w = candidate_w;
                        3'd3: next_payload3_w = candidate_w;
                        default: begin end
                    endcase
                end
                if (second_capture_w) begin
                    case (remaining_windows_w)
                        3'd0: next_payload1_w = second_candidate_w;
                        3'd1: next_payload2_w = second_candidate_w;
                        3'd2: next_payload3_w = second_candidate_w;
                        default: begin end
                    endcase
                end
            end

            edrv32_pipe_if2_to_align_pair #(.PAYLOAD_W(WINDOW_W)) u_pipe (
                .clk_i(clk_i),
                .payload_we_i(!kill_i && (window_capture_w || window_transfer_w)),
                .payload0_i(next_payload0_w),
                .payload1_i(next_payload1_w),
                .payload2_i(next_payload2_w),
                .payload3_i(next_payload3_w),
                .payload0_o(payload0_w),
                .payload1_o(payload1_w),
                .payload2_o(payload2_w),
                .payload3_o(payload3_w)
            );
        end else begin : gen_scalar_windows
            edrv32_pipe_if2_to_align u_pipe (
            .clk_i(clk_i),
            .head_we_i(window_head_we_w),
            .head_from_tail_i(window_head_from_tail_w),
            .tail_we_i(window_tail_we_w),
            .halfword0_i(candidate_halfword0_w),
            .halfword1_i(candidate_halfword1_w),
            .halfword1_valid_i(candidate_halfword1_valid_w),
            .pc_i(candidate_pc_w),
            .halfword0_error_i(candidate_halfword0_error_w),
            .halfword1_error_i(candidate_halfword1_error_w),
            .epoch_i(candidate_epoch_w),
            .predicted_taken_i(candidate_predicted_taken_w),
            .predicted_target_i(candidate_predicted_target_w),
            .predictor_meta_i(candidate_predictor_meta_w),
            .halfword0_o(halfword0_o),
            .halfword1_o(halfword1_o),
            .halfword1_valid_o(halfword1_valid_o),
            .pc_o(window_pc_o),
            .halfword0_error_o(halfword0_error_o),
            .halfword1_error_o(halfword1_error_o),
            .epoch_o(window_epoch_o),
            .predicted_taken_o(window_predicted_taken_o),
            .predicted_target_o(window_predicted_target_o),
            .predictor_meta_o(window_predictor_meta_o)
            );
            assign second_halfword0_o = 16'd0;
            assign second_halfword1_o = 16'd0;
            assign second_halfword1_valid_o = 1'b0;
            assign second_window_pc_o = 32'd0;
            assign second_halfword0_error_o = 1'b0;
            assign second_halfword1_error_o = 1'b0;
            assign second_window_epoch_o = {`EDRV32_EPOCH_W{1'b0}};
            assign second_window_predicted_taken_o = 1'b0;
            assign second_window_predicted_target_o = 32'd0;
            assign second_window_predictor_meta_o = 2'd0;
        end
    endgenerate

endmodule
