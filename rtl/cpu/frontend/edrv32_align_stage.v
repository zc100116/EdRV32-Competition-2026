// ============================================================================
// File        : edrv32_align_stage.v
// Description : Forms one architectural instruction from the oldest IF2
//               halfword window.  Compressed instructions are decompressed;
//               32-bit instructions are assembled from two halfwords.
// ============================================================================
`include "edrv32_isa.vh"
`include "edrv32_uop.vh"

// The stage directly owns its execution logic and outgoing registered boundary.
module edrv32_align_stage (
    input  wire                         clk_i,
    input  wire                         rst_n_i,

    // Registered IF2 halfword window.
    input  wire                         window_valid_i,
    output wire                         window_ready_o,
    output wire                         window_accept_o,
    output wire [1:0]                   window_halfwords_o,
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

    // Registered canonical instruction presented to DECODE.
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

    input  wire                         kill_i
);

    wire                       candidate_valid_w;
    wire                       candidate_ready_w;
    wire [31:0]                candidate_pc_w;
    wire [31:0]                candidate_instr_w;
    wire [31:0]                candidate_raw_instr_w;
    wire                       candidate_is_compressed_w;
    wire                       candidate_fetch_fault_w;
    wire                       candidate_compressed_illegal_w;
    wire [`EDRV32_EPOCH_W-1:0] candidate_epoch_w;
    wire                       candidate_predicted_taken_w;
    wire [31:0]                candidate_predicted_target_w;
    wire [1:0]                 candidate_predictor_meta_w;
    wire                       pipe_capture_w;
    wire                       pipe_transfer_w;
    wire                       pipe_valid_we_w;
    wire                       pipe_valid_d_w;


    // Stage-local execution logic is written directly in this module.


    // The low two bits determine whether the FIFO head is a complete 16-bit
    // instruction or the first half of a 32-bit instruction.
    wire compressed_w = halfword0_i[1:0] != 2'b11;
    wire formable_w = window_valid_i &&
                      (compressed_w || halfword1_valid_i);

    wire [31:0] decompressed_w;
    wire        decompressed_illegal_w;

    edrv32_rvc_decompress u_decompress (
        .c_instr_i(halfword0_i),
        .instr_o(decompressed_w),
        .illegal_o(decompressed_illegal_w)
    );

    // Consuming the window and filling the next pipeline register are one
    // event.  The IF2 FIFO isolates this local ready path from the I-cache.
    assign window_ready_o     = ~kill_i && candidate_ready_w;
    assign window_accept_o    = window_ready_o && formable_w;
    assign window_halfwords_o = compressed_w ? 2'd1 : 2'd2;

    assign candidate_valid_w              = ~kill_i && formable_w;
    assign candidate_pc_w                 = pc_i;
    assign candidate_instr_w              = compressed_w ? decompressed_w :
                                              {halfword1_i, halfword0_i};
    assign candidate_raw_instr_w          = compressed_w ?
                                              {16'd0, halfword0_i} :
                                              {halfword1_i, halfword0_i};
    assign candidate_is_compressed_w      = compressed_w;
    assign candidate_fetch_fault_w        = halfword0_error_i ||
                                              (!compressed_w && halfword1_error_i);
    assign candidate_compressed_illegal_w = compressed_w && decompressed_illegal_w;
    assign candidate_epoch_w              = epoch_i;
    assign candidate_predicted_taken_w    = predicted_taken_i;
    assign candidate_predicted_target_w   = predicted_target_i;
    assign candidate_predictor_meta_w     = predictor_meta_i;

    // ALIGN owns the elastic-boundary policy.  u_pipe only stores the state
    // selected by these controls.
    assign candidate_ready_w = ~kill_i && (~valid_o || ready_i);
    assign pipe_capture_w     = candidate_valid_w && candidate_ready_w;
    assign pipe_transfer_w    = valid_o && ready_i;
    assign pipe_valid_we_w    = kill_i || pipe_capture_w || pipe_transfer_w;
    assign pipe_valid_d_w     = ~kill_i && pipe_capture_w;


    edrv32_pipe_align_to_decode u_pipe (
        .clk_i(clk_i),
        .rst_n_i(rst_n_i),
        .valid_we_i(pipe_valid_we_w),
        .valid_d_i(pipe_valid_d_w),
        .payload_we_i(pipe_capture_w),
        .pc_i(candidate_pc_w),
        .instr_i(candidate_instr_w),
        .raw_instr_i(candidate_raw_instr_w),
        .is_compressed_i(candidate_is_compressed_w),
        .fetch_fault_i(candidate_fetch_fault_w),
        .compressed_illegal_i(candidate_compressed_illegal_w),
        .epoch_i(candidate_epoch_w),
        .predicted_taken_i(candidate_predicted_taken_w),
        .predicted_target_i(candidate_predicted_target_w),
        .predictor_meta_i(candidate_predictor_meta_w),
        .valid_o(valid_o),
        .pc_o(pc_o),
        .instr_o(instr_o),
        .raw_instr_o(raw_instr_o),
        .is_compressed_o(is_compressed_o),
        .fetch_fault_o(fetch_fault_o),
        .compressed_illegal_o(compressed_illegal_o),
        .epoch_o(epoch_o),
        .predicted_taken_o(predicted_taken_o),
        .predicted_target_o(predicted_target_o),
        .predictor_meta_o(predictor_meta_o)
    );

endmodule
