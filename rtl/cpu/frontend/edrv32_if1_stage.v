// ============================================================================
// File        : edrv32_if1_stage.v
// Description : Owns the fetch-stream PC and epoch and offers the next block
//               request to the IF1->IF2 boundary.
// ============================================================================
`include "edrv32_uop.vh"

// The stage directly owns its execution logic and outgoing registered boundary.
module edrv32_if1_stage #(
    parameter integer FETCH_WIDE = 0,
    parameter [31:0] RESET_PC = 32'h8000_0000
)(
    input  wire                         clk_i,
    input  wire                         rst_n_i,

    input wire [1:0] lookup_req_words_i,
    input wire [31:0] lookup_resp_upper_i,
    input wire [31:0] lookup_preview_upper_i,
    output wire [31:0] block_upper_o,
    output wire [1:0] block_words_o,
    output wire [31:0] predictor_query_pc2_o,
    input wire predicted_taken2_i,
    input wire [31:0] predicted_target2_i,
    input wire [1:0] predictor_meta2_i,
    output wire block_predicted_taken2_o,
    output wire [31:0] block_predicted_target2_o,
    output wire [1:0] block_predictor_meta2_o,
    output wire [31:0] predictor_query_pc3_o,
    input wire predicted_taken3_i,
    input wire [31:0] predicted_target3_i,
    input wire [1:0] predictor_meta3_i,
    output wire block_predicted_taken3_o,
    output wire [31:0] block_predicted_target3_o,
    output wire [1:0] block_predictor_meta3_o,

    // Predictor lookup for the two possible instruction starts in this block.
    output wire [31:0]                  predictor_query_pc0_o,
    output wire [31:0]                  predictor_query_pc1_o,
    input  wire                         predicted_taken0_i,
    input  wire [31:0]                  predicted_target0_i,
    input  wire [1:0]                   predictor_meta0_i,
    input  wire                         predicted_taken1_i,
    input  wire [31:0]                  predicted_target1_i,
    input  wire [1:0]                   predictor_meta1_i,

    // Architectural and early-prediction redirects.
    input  wire                         redirect_valid_i,
    output wire                         redirect_accept_o,
    output wire                         redirect_fire_o,
    input  wire [31:0]                  redirect_target_i,
    input  wire [`EDRV32_EPOCH_W-1:0]   redirect_epoch_i,
    input  wire                         prediction_redirect_valid_i,
    input  wire [31:0]                  prediction_redirect_target_i,
    input  wire                         prediction_redirect_fast_i,
    input  wire                         prediction_redirect_fast_slot1_i,
    output wire                         prediction_redirect_fire_o,
    output wire [`EDRV32_EPOCH_W-1:0]   applied_redirect_epoch_o,

    // Instruction-memory lookup transaction.
    output wire                         lookup_req_valid_o,
    input  wire                         lookup_req_ready_i,
    output wire [31:0]                  lookup_req_addr_o,
    input  wire                         lookup_resp_valid_i,
    output wire                         lookup_resp_ready_o,
    input  wire [31:0]                  lookup_resp_data_i,
    input  wire                         lookup_resp_error_i,
    input  wire                         lookup_preview_valid_i,
    input  wire [31:0]                  lookup_preview_addr_i,
    input  wire [31:0]                  lookup_preview_data_i,

    // Returned block, paired with its saved IF1 identity, for IF2.
    output wire                         block_valid_o,
    input  wire                         block_ready_i,
    output wire [31:0]                  block_addr_o,
    output wire [31:0]                  block_data_o,
    output wire                         block_error_o,
    output wire [`EDRV32_EPOCH_W-1:0]   block_epoch_o,
    output wire                         block_predicted_taken0_o,
    output wire [31:0]                  block_predicted_target0_o,
    output wire [1:0]                   block_predictor_meta0_o,
    output wire                         block_predicted_taken1_o,
    output wire [31:0]                  block_predicted_target1_o,
    output wire [1:0]                   block_predictor_meta1_o,
    output wire                         preview_valid_o,
    output wire [31:0]                  preview_addr_o,
    output wire [`EDRV32_EPOCH_W-1:0]   preview_epoch_o,
    output wire [31:0]                  preview_target0_o,
    output wire [31:0]                  preview_target1_o,

    // HPM observation: a fetch block is outstanding in the tag queue.
    output wire                         hpm_tag_nonempty_o
);

    wire [1:0] request_words_w = (FETCH_WIDE != 0) ? lookup_req_words_i : 2'd1;
    wire [31:0] request_stride_w = (request_words_w == 2'd2) ? 32'd8 : 32'd4;
    wire [71:0] request_wide_meta_w = {request_words_w,
        predicted_taken2_i, predicted_target2_i, predictor_meta2_i,
        predicted_taken3_i, predicted_target3_i, predictor_meta3_i};
    wire [71:0] returned_wide_meta_w;
    assign {block_words_o, block_predicted_taken2_o, block_predicted_target2_o,
        block_predictor_meta2_o, block_predicted_taken3_o, block_predicted_target3_o,
        block_predictor_meta3_o} = returned_wide_meta_w;
    assign block_upper_o = lookup_resp_upper_i;
    assign predictor_query_pc2_o = candidate_addr_w + 32'd4;
    assign predictor_query_pc3_o = candidate_addr_w + 32'd6;

    wire                       candidate_valid_w;
    wire                       candidate_ready_w;
    wire [31:0]                candidate_addr_w;
    wire [`EDRV32_EPOCH_W-1:0] candidate_epoch_w;
    reg  [1:0]                 tag_count_r;
    wire                       tag_full_w;
    wire                       tag_empty_w;
    wire                       tag_capture_w;
    wire                       tag_transfer_w;
    wire                       tag_capacity_w;
    wire [1:0]                 tag_write_index_w;

    // Stage-local execution logic is written directly in this module.


    // These two registers are the complete state of the current fetch stream.
    reg [31:0] fetch_addr_r;
    reg [`EDRV32_EPOCH_W-1:0] issue_epoch_r;
    reg [31:0] pending_addr_r;
    reg [`EDRV32_EPOCH_W-1:0] pending_epoch_r;

    function [31:0] preview_direct_target;
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
            preview_direct_target = pc_i + offset_v;
        end
    endfunction

    wire candidate_fire_w;
    wire [31:0] local_fast_target_w = prediction_redirect_fast_slot1_i
        ? preview_target1_o : preview_target0_o;
    wire [31:0] selected_prediction_target_w =
        prediction_redirect_fast_i ? local_fast_target_w
                                   : prediction_redirect_target_i;

    // The cache's synchronous hit word is visible one edge before its ordered
    // response.  Only the direct targets are computed here; IF2 still decides
    // instruction boundaries, prediction direction, and redirect priority.
    wire preview_capture_w = lookup_preview_valid_i &&
        (lookup_preview_addr_i == pending_addr_r) &&
        !redirect_fire_o && !prediction_redirect_fire_o;
    wire preview_valid_we_w = redirect_fire_o ||
        prediction_redirect_fire_o || preview_capture_w || tag_transfer_w;
    wire [31:0] preview_target0_w = preview_direct_target(
        lookup_preview_data_i, pending_addr_r);
    wire [31:0] preview_target1_w = preview_direct_target(
        {(FETCH_WIDE != 0) ? lookup_preview_upper_i[15:0] : 16'd0,
         lookup_preview_data_i[31:16]},
        {pending_addr_r[31:2], 2'b10});

    always @(posedge clk_i) begin
        if (tag_capture_w) begin
            pending_addr_r <= candidate_addr_w;
            pending_epoch_r <= candidate_epoch_w;
        end
    end

    // A redirect is accepted whenever reset is released.  An architectural
    // redirect suppresses prediction and request issue on the same cycle.
    assign redirect_accept_o = rst_n_i;
    assign redirect_fire_o   = redirect_valid_i && redirect_accept_o;
    assign prediction_redirect_fire_o = prediction_redirect_valid_i &&
        rst_n_i && !redirect_valid_i;
    assign applied_redirect_epoch_o = issue_epoch_r +
        {{(`EDRV32_EPOCH_W-1){1'b0}}, 1'b1};

    // The architectural redirect controller already presents a registered
    // command.  Use that stable payload as the current lookup candidate so a
    // target request can launch while the old stream is being invalidated.
    // A matching hit preview supplies an already-registered direct target on
    // the later response cycle. Other predictions keep the PC register cut.
    assign candidate_valid_w = rst_n_i &&
        (!prediction_redirect_valid_i || redirect_valid_i ||
         prediction_redirect_fast_i);
    assign candidate_addr_w  = redirect_valid_i
        ? {redirect_target_i[31:2], 2'b00} :
        (prediction_redirect_valid_i && prediction_redirect_fast_i)
            ? {local_fast_target_w[31:2], 2'b00} : fetch_addr_r;
    assign candidate_epoch_w = redirect_valid_i ||
                               (prediction_redirect_valid_i &&
                                prediction_redirect_fast_i)
        ? applied_redirect_epoch_o : issue_epoch_r;

    // IF1 owns the instruction-cache protocol and request-tag queue policy.
    // The pipe below is only the two-entry metadata register bank.
    assign tag_full_w          = (tag_count_r == 2'd2);
    assign tag_empty_w         = (tag_count_r == 2'd0);
    assign hpm_tag_nonempty_o  = (tag_count_r != 2'd0);
    assign tag_capacity_w      = !tag_full_w || tag_transfer_w;
    assign lookup_req_valid_o  = candidate_valid_w && tag_capacity_w;
    assign lookup_req_addr_o   = candidate_addr_w;
    assign candidate_ready_w   = tag_capacity_w && lookup_req_ready_i;
    assign tag_capture_w       = lookup_req_valid_o && lookup_req_ready_i;
    assign block_valid_o       = lookup_resp_valid_i && !tag_empty_w;
    assign lookup_resp_ready_o = !tag_empty_w && block_ready_i;
    assign tag_transfer_w      = lookup_resp_valid_i &&
                                 lookup_resp_ready_o;
    assign block_data_o        = lookup_resp_data_i;
    assign block_error_o       = lookup_resp_error_i;
    assign candidate_fire_w    = tag_capture_w;

    // After an optional head removal, a new entry is written at the current
    // occupancy. Two metadata registers cover the lookup and response stages;
    // full-queue pop+push keeps one-request-per-cycle steady-state throughput.
    assign tag_write_index_w = tag_count_r[1:0] -
                               (tag_transfer_w ? 2'd1 : 2'd0);

    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            tag_count_r <= 2'd0;
        end else begin
            case ({tag_capture_w, tag_transfer_w})
                2'b10: tag_count_r <= tag_count_r + 2'd1;
                2'b01: tag_count_r <= tag_count_r - 2'd1;
                default: begin end
            endcase
        end
    end

    // Only an accepted request advances sequentially.  Redirects instead start
    // a new stream and bump the epoch used to reject old returning requests.
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            fetch_addr_r  <= {RESET_PC[31:2], 2'b00};
            issue_epoch_r <= {`EDRV32_EPOCH_W{1'b0}};
        end else if (redirect_fire_o) begin
            // If the target lookup was accepted in the redirect cycle, the
            // resident sequential PC starts at the following fetch block.
            // Otherwise it retains the target itself for a normal retry.
            fetch_addr_r  <= {redirect_target_i[31:2], 2'b00} +
                             (candidate_fire_w ? request_stride_w : 32'd0);
            issue_epoch_r <= applied_redirect_epoch_o;
        end else if (prediction_redirect_fire_o) begin
            fetch_addr_r <= {selected_prediction_target_w[31:2], 2'b00} +
                            (candidate_fire_w ? request_stride_w : 32'd0);
            issue_epoch_r <= applied_redirect_epoch_o;
        end else if (candidate_fire_w) begin
            // The fetch-block stride is fixed, so no shared arithmetic unit is
            // needed for this local +4 operation.
            fetch_addr_r <= fetch_addr_r + request_stride_w;
        end
    end

    wire unused_redirect_epoch_w = ^redirect_epoch_i;

    assign predictor_query_pc0_o = candidate_addr_w;
    assign predictor_query_pc1_o = candidate_addr_w + 32'd2;



    edrv32_pipe_if1_to_if2 u_pipe (
        .wide_meta_i(request_wide_meta_w),
        .wide_meta_o(returned_wide_meta_w),
        .clk_i(clk_i),
        .rst_n_i(rst_n_i),
        .shift_i(tag_transfer_w),
        .write_i(tag_capture_w),
        .write_index_i(tag_write_index_w),
        .preview_valid_we_i(preview_valid_we_w),
        .preview_valid_d_i(preview_capture_w),
        .preview_payload_we_i(preview_capture_w),
        .preview_addr_i(pending_addr_r),
        .preview_epoch_i(pending_epoch_r),
        .preview_target0_i(preview_target0_w),
        .preview_target1_i(preview_target1_w),
        .addr_i(candidate_addr_w),
        .epoch_i(candidate_epoch_w),
        .predicted_taken0_i(predicted_taken0_i),
        .predicted_target0_i(predicted_target0_i),
        .predictor_meta0_i(predictor_meta0_i),
        .predicted_taken1_i(predicted_taken1_i),
        .predicted_target1_i(predicted_target1_i),
        .predictor_meta1_i(predictor_meta1_i),
        .addr_o(block_addr_o),
        .epoch_o(block_epoch_o),
        .predicted_taken0_o(block_predicted_taken0_o),
        .predicted_target0_o(block_predicted_target0_o),
        .predictor_meta0_o(block_predictor_meta0_o),
        .predicted_taken1_o(block_predicted_taken1_o),
        .predicted_target1_o(block_predicted_target1_o),
        .predictor_meta1_o(block_predictor_meta1_o),
        .preview_valid_o(preview_valid_o),
        .preview_addr_o(preview_addr_o),
        .preview_epoch_o(preview_epoch_o),
        .preview_target0_o(preview_target0_o),
        .preview_target1_o(preview_target1_o)
    );

endmodule
