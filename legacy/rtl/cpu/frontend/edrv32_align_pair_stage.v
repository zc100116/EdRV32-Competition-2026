// ============================================================================
// File        : edrv32_align_pair_stage.v
// Description : Decompresses up to two registered IF2 instruction windows and
//               owns a four-entry ordered ALIGN-to-DECODE boundary.
// Notes       : Ingress capacity uses registered occupancy only. A younger
//               window is accepted only with its older window; output slot B
//               advances only with slot A. No downstream ready reaches IF2 CE.
// ============================================================================
`include "edrv32_uop.vh"

module edrv32_align_pair_stage (
    input  wire                         clk_i,
    input  wire                         rst_n_i,

    input  wire                         window_valid_i,
    output wire                         window_accept_o,
    input  wire [15:0]                  halfword0_i,
    input  wire [15:0]                  halfword1_i,
    input  wire                         halfword1_valid_i,
    input  wire [31:0]                  pc_i,
    input  wire                         halfword0_error_i,
    input  wire                         halfword1_error_i,
    input  wire [`EDRV32_EPOCH_W-1:0]   epoch_i,
    input  wire                         predicted_taken_i,
    input  wire [31:0]                  predicted_target_i,
    input  wire [1:0]                   predictor_meta_i,

    input  wire                         second_window_valid_i,
    output wire                         second_window_accept_o,
    input  wire [15:0]                  second_halfword0_i,
    input  wire [15:0]                  second_halfword1_i,
    input  wire                         second_halfword1_valid_i,
    input  wire [31:0]                  second_pc_i,
    input  wire                         second_halfword0_error_i,
    input  wire                         second_halfword1_error_i,
    input  wire [`EDRV32_EPOCH_W-1:0]   second_epoch_i,
    input  wire                         second_predicted_taken_i,
    input  wire [31:0]                  second_predicted_target_i,
    input  wire [1:0]                   second_predictor_meta_i,

    output wire                         valid_o,
    input  wire                         ready_i,
    output wire [31:0]                  pc_o,
    output wire [31:0]                  instr_o,
    output wire [31:0]                  raw_instr_o,
    output wire                         is_compressed_o,
    output wire                         fetch_fault_o,
    output wire                         compressed_illegal_o,
    output wire [`EDRV32_EPOCH_W-1:0]   epoch_o,
    output wire                         predicted_taken_o,
    output wire [31:0]                  predicted_target_o,
    output wire [1:0]                   predictor_meta_o,

    output wire                         second_valid_o,
    input  wire                         second_ready_i,
    output wire [31:0]                  second_pc_o,
    output wire [31:0]                  second_instr_o,
    output wire [31:0]                  second_raw_instr_o,
    output wire                         second_is_compressed_o,
    output wire                         second_fetch_fault_o,
    output wire                         second_compressed_illegal_o,
    output wire [`EDRV32_EPOCH_W-1:0]   second_epoch_o,
    output wire                         second_predicted_taken_o,
    output wire [31:0]                  second_predicted_target_o,
    output wire [1:0]                   second_predictor_meta_o,

    input  wire                         kill_i
);

    localparam integer PAYLOAD_W = 134 + `EDRV32_EPOCH_W;
    wire [3:0] valid_w;
    wire [PAYLOAD_W-1:0] payload0_w;
    wire [PAYLOAD_W-1:0] payload1_w;
    wire [PAYLOAD_W-1:0] payload2_w;
    wire [PAYLOAD_W-1:0] payload3_w;
    reg [2:0] count_r;
    reg [1:0] head_r;
    reg [1:0] tail_r;
    wire [2:0] count_w = count_r;
    wire [1:0] second_head_w = head_r + 2'd1;
    wire [1:0] second_tail_w = tail_r + 2'd1;
    wire [PAYLOAD_W-1:0] head_payload_w = (head_r == 2'd0) ? payload0_w :
        (head_r == 2'd1) ? payload1_w : (head_r == 2'd2) ? payload2_w : payload3_w;
    wire [PAYLOAD_W-1:0] second_payload_w = (second_head_w == 2'd0) ? payload0_w :
        (second_head_w == 2'd1) ? payload1_w :
        (second_head_w == 2'd2) ? payload2_w : payload3_w;

    wire compressed_w = halfword0_i[1:0] != 2'b11;
    wire second_compressed_w = second_halfword0_i[1:0] != 2'b11;
    wire formable_w = window_valid_i && (compressed_w || halfword1_valid_i);
    wire second_formable_w = second_window_valid_i &&
        (second_compressed_w || second_halfword1_valid_i);
    wire [31:0] decompressed_w;
    wire decompressed_illegal_w;
    wire [31:0] second_decompressed_w;
    wire second_decompressed_illegal_w;

    edrv32_rvc_decompress u_decompress (
        .c_instr_i(halfword0_i),
        .instr_o(decompressed_w),
        .illegal_o(decompressed_illegal_w)
    );
    edrv32_rvc_decompress u_second_decompress (
        .c_instr_i(second_halfword0_i),
        .instr_o(second_decompressed_w),
        .illegal_o(second_decompressed_illegal_w)
    );

    wire fetch_fault_w = halfword0_error_i ||
        (!compressed_w && halfword1_error_i);
    wire compressed_illegal_w = compressed_w && decompressed_illegal_w;
    wire second_fetch_fault_w = second_halfword0_error_i ||
        (!second_compressed_w && second_halfword1_error_i);
    wire [31:0] sequential_pc_w = pc_i + (compressed_w ? 32'd2 : 32'd4);
    wire second_sequential_w = (second_epoch_i == epoch_i) &&
        (second_pc_i == sequential_pc_w) && !predicted_taken_i;

    assign window_accept_o = !kill_i && formable_w && (count_w < 3'd4);
    assign second_window_accept_o = window_accept_o &&
        second_formable_w && second_sequential_w && !fetch_fault_w &&
        !compressed_illegal_w && (count_w <= 3'd2);

    wire [31:0] canonical_w = compressed_w ? decompressed_w
        : {halfword1_i, halfword0_i};
    wire [31:0] raw_w = compressed_w ? {16'd0, halfword0_i}
        : {halfword1_i, halfword0_i};
    wire [31:0] second_canonical_w = second_compressed_w ? second_decompressed_w
        : {second_halfword1_i, second_halfword0_i};
    wire [31:0] second_raw_w = second_compressed_w ? {16'd0, second_halfword0_i}
        : {second_halfword1_i, second_halfword0_i};
    wire [PAYLOAD_W-1:0] candidate_w = {pc_i, canonical_w, raw_w, compressed_w,
        fetch_fault_w, compressed_illegal_w, epoch_i, predicted_taken_i,
        predicted_target_i, predictor_meta_i};
    wire [PAYLOAD_W-1:0] second_candidate_w = {second_pc_i, second_canonical_w,
        second_raw_w, second_compressed_w, second_fetch_fault_w,
        (second_compressed_w && second_decompressed_illegal_w), second_epoch_i,
        second_predicted_taken_i, second_predicted_target_i, second_predictor_meta_i};

    assign valid_o = (count_r != 3'd0);
    assign second_valid_o = (count_r >= 3'd2);
    assign {pc_o, instr_o, raw_instr_o, is_compressed_o, fetch_fault_o,
        compressed_illegal_o, epoch_o, predicted_taken_o,
        predicted_target_o, predictor_meta_o} = head_payload_w;
    assign {second_pc_o, second_instr_o, second_raw_instr_o,
        second_is_compressed_o, second_fetch_fault_o, second_compressed_illegal_o,
        second_epoch_o, second_predicted_taken_o,
        second_predicted_target_o, second_predictor_meta_o} = second_payload_w;

    wire pop_first_w = !kill_i && valid_o && ready_i;
    wire pop_second_w = pop_first_w && second_valid_o && second_ready_i;
    wire [2:0] pop_count_w = pop_second_w ? 3'd2 : pop_first_w ? 3'd1 : 3'd0;
    wire [2:0] capture_count_w = second_window_accept_o ? 3'd2
        : window_accept_o ? 3'd1 : 3'd0;
    wire [2:0] remaining_count_w = count_w - pop_count_w;
    wire [2:0] next_count_w = remaining_count_w + capture_count_w;
    wire movement_w = (pop_count_w != 3'd0) || (capture_count_w != 3'd0);
    // Payload stays in fixed physical slots. DECODE ready updates only the
    // small occupancy/head state; it never moves or clocks the payload bank.
    wire [3:0] first_capture_mask_w = window_accept_o
        ? (4'b0001 << tail_r) : 4'b0000;
    wire [3:0] second_capture_mask_w = second_window_accept_o
        ? (4'b0001 << second_tail_w) : 4'b0000;
    wire [3:0] capture_mask_w = first_capture_mask_w | second_capture_mask_w;
    wire [3:0] first_pop_mask_w = pop_first_w
        ? (4'b0001 << head_r) : 4'b0000;
    wire [3:0] second_pop_mask_w = pop_second_w
        ? (4'b0001 << second_head_w) : 4'b0000;
    wire [3:0] next_valid_w = kill_i ? 4'b0000 :
        ((valid_w & ~(first_pop_mask_w | second_pop_mask_w)) | capture_mask_w);
    wire [PAYLOAD_W-1:0] next_payload0_w = (tail_r == 2'd0)
        ? candidate_w : second_candidate_w;
    wire [PAYLOAD_W-1:0] next_payload1_w = (tail_r == 2'd1)
        ? candidate_w : second_candidate_w;
    wire [PAYLOAD_W-1:0] next_payload2_w = (tail_r == 2'd2)
        ? candidate_w : second_candidate_w;
    wire [PAYLOAD_W-1:0] next_payload3_w = (tail_r == 2'd3)
        ? candidate_w : second_candidate_w;

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            count_r <= 3'd0;
            head_r  <= 2'd0;
            tail_r  <= 2'd0;
        end else if (kill_i) begin
            count_r <= 3'd0;
            head_r  <= 2'd0;
            tail_r  <= 2'd0;
        end else begin
            count_r <= next_count_w;
            head_r  <= head_r + pop_count_w[1:0];
            tail_r  <= tail_r + capture_count_w[1:0];
        end
    end

    edrv32_pipe_align_to_decode_pair #(.PAYLOAD_W(PAYLOAD_W)) u_pipe (
        .clk_i(clk_i),
        .rst_n_i(rst_n_i),
        .valid_we_i(kill_i || movement_w),
        .valid_i(next_valid_w),
        .payload_we_i(capture_mask_w),
        .payload0_i(next_payload0_w),
        .payload1_i(next_payload1_w),
        .payload2_i(next_payload2_w),
        .payload3_i(next_payload3_w),
        .valid_o(valid_w),
        .payload0_o(payload0_w),
        .payload1_o(payload1_w),
        .payload2_o(payload2_w),
        .payload3_o(payload3_w)
    );

endmodule
