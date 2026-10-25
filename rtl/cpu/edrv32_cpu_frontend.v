// File: edrv32_cpu_frontend.v
// Spec: cpu-spec 3.2, 4.1, 4.4
// Description: Fetch aligned groups, join boundary-spanning instructions and feed the four-entry IB.
// Reserve response storage before issuing requests and recover speculative fetch on redirect.
// Clock domain: clk_sys.
module edrv32_cpu_frontend #(
    parameter RVC_EN = 1
) (
    // Clock and reset to the SoC reset vector 0.
    input wire clk_i,
    input wire rst_n_i,
    // Backend: older M/E redirect wins over a D-stage JAL redirect.
    input wire redirect_valid_i,
    input wire [31:0] redirect_pc_i,
    input wire [36:0] redirect_ras_i,
    input wire redirect_push_i,
    input wire redirect_pop_i,
    input wire [31:0] redirect_return_pc_i,
    input wire d_redirect_valid_i,
    input wire [31:0] d_redirect_pc_i,
    input wire [36:0] d_redirect_ras_i,
    input wire d_redirect_push_i,
    input wire d_redirect_pop_i,
    input wire [31:0] d_redirect_return_pc_i,
    input wire halt_i,
    // Surviving E-stage branch training.
    input wire update_valid_i,
    input wire update_clear_i,
    input wire [4:0] update_clear_index_i,
    input wire [31:0] update_pc_i,
    input wire [31:0] update_target_i,
    input wire [2:0] update_type_i,
    input wire update_taken_i,
    input wire update_compressed_i,
    input wire [8:0] update_index_i,
    // Decode consumes 0, 1 or 2 records; low record is oldest.
    input wire [1:0] decode_pop_count_i,
    output wire [357:0] decode_data_o,
    output wire [1:0] decode_valid_count_o,
    output wire [2:0] ib_count_o,
    // I-cache request/response contract, cpu-spec 3.2.
    output wire ic_req_valid_o,
    output wire [31:0] ic_req_addr_o,
    input wire ic_req_ready_i,
    input wire ic_resp_valid_i,
    input wire [63:0] ic_resp_data_i,
    input wire ic_resp_err_i,
    output wire ic_kill_o,
    // FENCE.I sequencing belongs to the backend.
    input wire invalidate_i,
    output wire invalidate_done_o,
    output wire ic_inv_o,
    input wire ic_inv_done_i,
    // Pipeline activity for core debug and HPM.
    output wire f1_valid_o,
    output wire f2_valid_o,
    output wire fetch_wait_o
);
    localparam HALFWORD_BITS = 130;
    localparam HALFWORD_CAPACITY = 8;
    reg [31:0] f1_pc_r;
    reg f1_cross_r;
    reg [31:0] f1_cross_target_r;
    reg f2_pending_r;
    reg [31:0] f2_pc_r;
    reg [2:0] f2_end_r;
    reg f2_hit_r;
    reg f2_taken_r;
    reg f2_compressed_r;
    reg [1:0] f2_position_r;
    reg [31:0] f2_target_r;
    reg [8:0] f2_history_r;
    reg [36:0] f2_ras_r;
    reg [HALFWORD_CAPACITY*HALFWORD_BITS-1:0] halfwords_r;
    reg [3:0] halfword_count_r;
    wire redirect_w;
    wire [31:0] redirect_pc_w;
    wire [36:0] restore_ras_w;
    wire restore_push_w;
    wire restore_pop_w;
    wire [31:0] restore_return_pc_w;
    wire predict_hit_w;
    wire predict_taken_w;
    wire [31:0] predict_target_w;
    wire [1:0] predict_position_w;
    wire predict_compressed_w;
    wire [8:0] predict_history_w;
    wire [36:0] predict_ras_w;
    wire request_accept_w;
    wire [2:0] request_end_w;
    wire [2:0] branch_end_w;
    wire response_accept_w;
    wire [2:0] append_count_w;
    wire [2:0] ib_free_count_w;
    reg [HALFWORD_CAPACITY*HALFWORD_BITS-1:0] merged_w;
    reg [3:0] available_w;
    reg [3:0] remaining_w;
    reg [2:0] consume_w;
    reg [1:0] push_count_w;
    reg [357:0] push_data_w;
    reg [HALFWORD_BITS-1:0] first_w;
    reg [16:0] first_tail_w;
    reg [HALFWORD_BITS-1:0] second_w;
    reg [16:0] second_tail_w;
    wire [31:0] first_expanded_w;
    wire first_illegal_w;
    wire [31:0] second_expanded_w;
    wire second_illegal_w;
    reg first_compressed_w;
    reg second_compressed_w;
    reg [2:0] first_length_w;
    reg [2:0] second_length_w;
    reg [31:0] first_raw_w;
    reg [31:0] second_raw_w;
    reg first_error_w;
    reg second_error_w;
    reg [31:0] append_pc_w;
    wire first_recover_w;
    wire second_recover_w;
    wire recover_w;
    wire [31:0] recover_pc_w;
    wire [36:0] recover_ras_w;
    wire [4:0] recover_btb_index_w;
    wire [1:0] unused_alignment_w;
    assign unused_alignment_w = {update_pc_i[0], f2_pc_r[0]};
    integer append_idx;
    integer append_slot;
    assign redirect_w = redirect_valid_i || d_redirect_valid_i;
    assign redirect_pc_w = redirect_valid_i ? redirect_pc_i : d_redirect_pc_i;
    assign restore_ras_w = redirect_valid_i ? redirect_ras_i :
        d_redirect_valid_i ? d_redirect_ras_i : recover_ras_w;
    assign restore_push_w = redirect_valid_i ? redirect_push_i :
        d_redirect_valid_i && d_redirect_push_i;
    assign restore_pop_w = redirect_valid_i ? redirect_pop_i :
        d_redirect_valid_i && d_redirect_pop_i;
    assign restore_return_pc_w = redirect_valid_i ?
        redirect_return_pc_i : d_redirect_return_pc_i;
    assign branch_end_w = {1'b0, predict_position_w} +
        (RVC_EN && predict_compressed_w ? 3'd1 : 3'd2);
    assign request_end_w = f1_cross_r ? 3'd1 : predict_taken_w ? branch_end_w : 3'd4;
    assign response_accept_w = f2_pending_r && ic_resp_valid_i && !redirect_w;
    assign append_count_w = response_accept_w ?
        f2_end_r - {1'b0, f2_pc_r[2:1]} : 3'd0;
    // Include the arriving response and this cycle's drain when reserving the next group.
    assign ic_req_valid_o = rst_n_i && !halt_i && !redirect_w && !recover_w &&
        (!f2_pending_r || ic_resp_valid_i) && remaining_w <= 4;
    assign ic_req_addr_o = {f1_pc_r[31:3], 3'b0};
    assign request_accept_w = ic_req_valid_o && ic_req_ready_i;
    assign ic_kill_o = (redirect_w || recover_w) && f2_pending_r;
    assign ic_inv_o = invalidate_i;
    assign invalidate_done_o = ic_inv_done_i;
    assign f1_valid_o = ic_req_valid_o;
    assign f2_valid_o = f2_pending_r || halfword_count_r != 0;
    assign fetch_wait_o = f2_pending_r && !ic_resp_valid_i;
    edrv32_cpu_predictor u_predictor (
        .clk_i(clk_i),
        .rst_n_i(rst_n_i),
        .query_pc_i(f1_pc_r[31:1]),
        .query_accept_i(request_accept_w && !f1_cross_r),
        .predict_hit_o(predict_hit_w),
        .predict_taken_o(predict_taken_w),
        .predict_target_o(predict_target_w),
        .predict_position_o(predict_position_w),
        .predict_compressed_o(predict_compressed_w),
        .predict_history_o(predict_history_w),
        .predict_ras_o(predict_ras_w),
        .update_valid_i(update_valid_i),
        .update_pc_i(update_pc_i[31:1]),
        .update_target_i(update_target_i),
        .update_type_i(update_type_i),
        .update_taken_i(update_taken_i),
        .update_compressed_i(update_compressed_i),
        .update_index_i(update_index_i),
        .clear_valid_i(update_clear_i || recover_w),
        .clear_index_i(update_clear_i ? update_clear_index_i : recover_btb_index_w),
        .restore_valid_i(redirect_w || recover_w),
        .restore_ras_i(restore_ras_w),
        .restore_push_i(restore_push_w),
        .restore_pop_i(restore_pop_w),
        .restore_return_pc_i(restore_return_pc_w)
    );
    edrv32_cpu_ib u_ib (
        .clk_i(clk_i),
        .rst_n_i(rst_n_i),
        .push_count_i(push_count_w),
        .push_data_i(push_data_w),
        .free_count_o(ib_free_count_w),
        .pop_count_i(decode_pop_count_i),
        .data_o(decode_data_o),
        .valid_count_o(decode_valid_count_o),
        .flush_i(redirect_w),
        .count_o(ib_count_o)
    );
    edrv32_cpu_rvc u_expand_first (
        .instr_i(first_w[15:0]),
        .instr_o(first_expanded_w),
        .illegal_o(first_illegal_w)
    );
    edrv32_cpu_rvc u_expand_second (
        .instr_i(second_w[15:0]),
        .instr_o(second_expanded_w),
        .illegal_o(second_illegal_w)
    );
    // Each halfword carries its PC so predicted targets may share the same stream buffer.
    // Layout: {predicted_compressed, RAS[36:0], GHR[8:0], target[31:0],
    //          taken, hit, error, PC[31:0], data[15:0]}.
    always @(*) begin
        merged_w = halfwords_r;
        available_w = halfword_count_r + {1'b0, append_count_w};
        append_pc_w = 0;
        append_slot = 0;
        for (append_idx = 0; append_idx < 4; append_idx = append_idx + 1) begin
            if (response_accept_w && append_idx >= {30'b0, f2_pc_r[2:1]} &&
                append_idx < {29'b0, f2_end_r}) begin
                append_pc_w = {f2_pc_r[31:3], 3'b0} + (append_idx << 1);
                append_slot = {28'b0, halfword_count_r} + append_idx -
                    {30'b0, f2_pc_r[2:1]};
                merged_w[append_slot * HALFWORD_BITS +: HALFWORD_BITS] =
                    {f2_compressed_r, f2_ras_r, f2_history_r, f2_target_r,
                    f2_taken_r && append_idx[1:0] == f2_position_r,
                    f2_hit_r && append_idx[1:0] == f2_position_r,
                    ic_resp_err_i, append_pc_w, ic_resp_data_i[append_idx * 16 +: 16]};
            end
        end
    end
    always @(*) begin
        first_w = merged_w[0 +: HALFWORD_BITS];
        first_tail_w = {merged_w[HALFWORD_BITS + 48],
            merged_w[HALFWORD_BITS +: 16]};
        first_compressed_w = RVC_EN && first_w[1:0] != 3;
        first_length_w = first_compressed_w ? 3'd1 : 3'd2;
        first_raw_w = first_compressed_w ? {16'b0, first_w[15:0]} :
            {first_tail_w[15:0], first_w[15:0]};
        first_error_w = first_w[48] || (!first_compressed_w && first_tail_w[16]);
        second_w = merged_w[first_length_w * HALFWORD_BITS +: HALFWORD_BITS];
        second_tail_w = {merged_w[({29'b0, first_length_w} + 1) * HALFWORD_BITS + 48],
            merged_w[({29'b0, first_length_w} + 1) * HALFWORD_BITS +: 16]};
        second_compressed_w = RVC_EN && second_w[1:0] != 3;
        second_length_w = second_compressed_w ? 3'd1 : 3'd2;
        second_raw_w = second_compressed_w ? {16'b0, second_w[15:0]} :
            {second_tail_w[15:0], second_w[15:0]};
        second_error_w = second_w[48] || (!second_compressed_w && second_tail_w[16]);
    end
    // cpu-spec v0.3 4.4: only compressed fetch requires prediction boundary recovery.
    generate
        if (RVC_EN) begin : g_rvc_recover
            wire [42:0] first_upper_prediction_w;
            wire [42:0] second_upper_prediction_w;
            wire first_length_mismatch_w;
            wire second_length_mismatch_w;
            assign first_upper_prediction_w = {merged_w[HALFWORD_BITS + 92 +: 37],
                merged_w[HALFWORD_BITS + 49], merged_w[HALFWORD_BITS + 19 +: 5]};
            assign second_upper_prediction_w =
                {merged_w[({29'b0, first_length_w} + 1) * HALFWORD_BITS + 92 +: 37],
                merged_w[({29'b0, first_length_w} + 1) * HALFWORD_BITS + 49],
                merged_w[({29'b0, first_length_w} + 1) * HALFWORD_BITS + 19 +: 5]};
            assign first_length_mismatch_w = first_w[49] &&
                first_w[129] != first_compressed_w;
            assign second_length_mismatch_w = second_w[49] &&
                second_w[129] != second_compressed_w;
            assign first_recover_w = (available_w >= 1 && first_length_mismatch_w) ||
                (available_w >= 2 && first_length_w == 2 && first_upper_prediction_w[5]);
            assign second_recover_w =
                (available_w >= {1'b0, first_length_w} + 1 && second_length_mismatch_w) ||
                (available_w >= {1'b0, first_length_w} + 2 && second_length_w == 2 &&
                second_upper_prediction_w[5]);
            // A valid older first instruction may still enter IB while the second is retried.
            assign recover_w = !redirect_w && (first_recover_w ||
                (available_w >= {1'b0, first_length_w} && ib_free_count_w != 0 &&
                second_recover_w));
            assign recover_pc_w = first_recover_w ? first_w[47:16] : second_w[47:16];
            assign recover_ras_w = first_recover_w ?
                (first_length_mismatch_w ? first_w[128:92] : first_upper_prediction_w[42:6]) :
                (second_length_mismatch_w ? second_w[128:92] : second_upper_prediction_w[42:6]);
            assign recover_btb_index_w = first_recover_w ?
                (first_length_mismatch_w ? first_w[23:19] : first_upper_prediction_w[4:0]) :
                (second_length_mismatch_w ? second_w[23:19] : second_upper_prediction_w[4:0]);
        end else begin : g_fixed_length
            wire [1:0] unused_prediction_length_w;
            assign unused_prediction_length_w = {first_w[129], second_w[129]};
            assign first_recover_w = 1'b0;
            assign second_recover_w = 1'b0;
            assign recover_w = 1'b0;
            assign recover_pc_w = 0;
            assign recover_ras_w = 0;
            assign recover_btb_index_w = 0;
        end
    endgenerate
    always @(*) begin
        push_count_w = 0;
        push_data_w = 0;
        consume_w = 0;
        if (!redirect_w && !first_recover_w &&
            available_w >= {1'b0, first_length_w} && ib_free_count_w != 0) begin
            push_count_w = 1;
            consume_w = first_length_w;
            push_data_w[178:0] = {first_w[128:92], 9'b0,
                first_w[82:51], first_w[50], first_w[49], first_error_w,
                first_compressed_w && first_illegal_w, first_compressed_w,
                first_raw_w, first_compressed_w ? first_expanded_w : first_raw_w,
                first_w[47:16]};
            // History is sampled at F1, but each instruction uses its own PC in gshare.
            push_data_w[141:133] = first_w[91:83] ^ first_w[25:17];
            if (available_w >= {1'b0, first_length_w} + {1'b0, second_length_w} &&
                ib_free_count_w >= 2 && !second_recover_w) begin
                push_count_w = 2;
                consume_w = first_length_w + second_length_w;
                push_data_w[357:179] = {second_w[128:92], 9'b0,
                    second_w[82:51], second_w[50], second_w[49], second_error_w,
                    second_compressed_w && second_illegal_w, second_compressed_w,
                    second_raw_w, second_compressed_w ? second_expanded_w : second_raw_w,
                    second_w[47:16]};
                push_data_w[320:312] = second_w[91:83] ^ second_w[25:17];
            end
        end
        remaining_w = available_w - {1'b0, consume_w};
    end
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            f1_pc_r <= 0;
            f1_cross_r <= 0;
            f2_pending_r <= 0;
            halfword_count_r <= 0;
        end else if (redirect_w) begin
            f1_pc_r <= redirect_pc_w;
            f1_cross_r <= 0;
            f2_pending_r <= 0;
            halfword_count_r <= 0;
        end else if (recover_w) begin
            f1_pc_r <= recover_pc_w;
            f1_cross_r <= 0;
            f2_pending_r <= 0;
            halfword_count_r <= 0;
        end else begin
            halfword_count_r <= remaining_w;
            if (response_accept_w)
                f2_pending_r <= 0;
            if (request_accept_w) begin
                f2_pending_r <= 1;
                if (f1_cross_r) begin
                    f1_pc_r <= f1_cross_target_r;
                    f1_cross_r <= 0;
                end else if (predict_taken_w) begin
                    if (branch_end_w > 4) begin
                        f1_pc_r <= {f1_pc_r[31:3], 3'b0} + 8;
                        f1_cross_r <= 1;
                    end else begin
                        f1_pc_r <= predict_target_w;
                    end
                end else begin
                    f1_pc_r <= {f1_pc_r[31:3], 3'b0} + 8;
                end
            end
        end
    end
    always @(posedge clk_i) begin
        if (!redirect_w && !recover_w)
            halfwords_r <= merged_w >> (consume_w * HALFWORD_BITS);
        if (request_accept_w) begin
            f2_pc_r <= f1_pc_r;
            f2_end_r <= request_end_w > 4 ? 3'd4 : request_end_w;
            f2_hit_r <= predict_hit_w && !f1_cross_r;
            f2_taken_r <= predict_taken_w && !f1_cross_r;
            f2_compressed_r <= predict_compressed_w;
            f2_position_r <= predict_position_w;
            f2_target_r <= predict_target_w;
            f2_history_r <= predict_history_w;
            f2_ras_r <= predict_ras_w;
            if (!f1_cross_r && predict_taken_w && branch_end_w > 4)
                f1_cross_target_r <= predict_target_w;
        end
    end
endmodule
