// File: edrv32_cpu_frontend.v
// Spec: cpu-spec 3.2, 4.1, 4.4
// Description: Fetch aligned groups, join boundary-spanning instructions and feed the four-entry IB.
// Reserve response storage before issuing requests and recover speculative fetch on redirect.
// Clock domain: clk_sys.
module edrv32_cpu_frontend (
    // Clock and reset to the SoC reset vector 0.
    input wire clk_i,
    input wire rst_n_i,

    // Backend: older M/E redirect wins over a D-stage JAL redirect.
    input wire redirect_valid_i,
    // Same-cycle M/E/D restoration replicas: 16 RAS bytes and one pointer/count bank.
    input wire [16:0] redirect_valid_copy_i,
    input wire [31:0] redirect_pc_i,
    input wire [36:0] redirect_ras_i,
    input wire redirect_push_i,
    input wire redirect_pop_i,
    input wire [31:0] redirect_return_pc_i,
    input wire d_redirect_valid_i,
    input wire d_redirect_slot_i,
    input wire [31:0] d_redirect_pc_i,
    input wire [36:0] d_redirect_ras_i,
    input wire d_redirect_push_i,
    input wire d_redirect_pop_i,
    input wire [31:0] d_redirect_return_pc_i,
    input wire halt_i,
    // Surviving E-stage branch training.
    input wire update_valid_i,
    input wire update_clear_i,
    input wire [6:0] update_clear_index_i,
    input wire [31:0] update_pc_i,
    input wire [31:0] update_target_i,
    input wire [2:0] update_type_i,
    input wire update_taken_i,
    input wire [11:0] update_index_i,
    input wire [11:0] update_tournament_i,
    // Decode consumes 0, 1 or 2 records; low record is oldest.
    input wire [1:0] decode_pop_count_i,
    output wire [357:0] decode_data_o,
    output wire [139:0] decode_predecode_o,
    output wire [5:0] decode_index_hi_o,
    output wire [23:0] decode_tournament_o,
    output wire [79:0] decode_operand_addr_o,
    output wire [1:0] decode_valid_count_o,
    output wire [2:0] ib_count_o,
    // I-cache request/response contract, cpu-spec 3.2.
    output wire ic_req_valid_o,
    output wire [31:0] ic_req_addr_o,
    input wire ic_req_ready_i,
    input wire ic_resp_valid_i,
    input wire [7:0] ic_resp_valid_copy_i,
    input wire [63:0] ic_resp_data_i,
    input wire [43:0] ic_resp_predecode_i,
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
    // Fixed four-byte instructions: a response contributes one or two whole words.
    localparam REC_BITS = 179;
    localparam STREAM_BITS = 182;
    reg [31:0] f1_pc_r;
    (* keep = "true", syn_preserve = 1 *) reg [31:1] f1_pc_copy1_r;
    (* keep = "true", syn_preserve = 1 *) reg [31:3] f1_pc_copy2_r;
    (* keep = "true", syn_preserve = 1 *) reg [31:3] f1_pc_copy3_r;
    wire [31:0] query_valid_index_w;
    reg f2_pending_r;
    reg miss_wait_r;
    reg replay_valid_r;
    (* keep = "true", syn_preserve = 1 *) reg replay_valid_copy1_r;
    reg [138:0] replay_payload_r;
    reg replay_taken_r;
    reg [31:0] replay_resume_pc_r;
    reg [3:0] credit_r;
    wire [31:0] replay_pc_w;
    wire [31:0] owner_sequential_pc_w;
    wire [138:0] owner_query_w;
    wire owner_taken_w;
    wire owner_accept_w;
    wire new_request_w;
    wire miss_notice_w;
    wire [31:0] f2_pc_r;
    wire [1:0] f2_count_w;
    reg [1:0] f2_taken_count_r;
    reg [1:0] f2_sequential_count_r;
    reg f2_checked_r;
    wire f2_conditional_r;
    wire [19:0] f2_local_history_r;
    wire [1:0] f2_global_r;
    reg [1:0] f2_local_r;
    wire [1:0] f2_local_w;
    wire [1:0] f2_branch_local_w;
    reg [19:0] f2_direction_history_r;
    wire [1:0] f2_saved_local_w;
    wire f2_use_local_w;
    wire f2_final_taken_w;
    wire f2_taken_w;
    wire f2_correct_w;
    reg [31:0] f2_correct_addr_r;
    wire [31:0] f2_correct_pc_w;
    reg f2_correct_eligible_r;
    reg [11:0] f2_index_r;
    wire [19:0] predict_local_history_w;
    wire [1:0] predict_global_w;
    wire predict_conditional_w;
    wire f2_hit_r;
    reg f2_taken_r;
    wire [1:0] f2_position_r;
    wire [31:0] f2_target_r;
    wire [11:0] f2_history_r;
    wire [36:0] f2_ras_r;
    reg [STREAM_BITS-1:0] words_r [0:3];
    reg [138:0] f2_payload_r;
    wire [138:0] f2_query_w;
    wire [8:0] f2_pending_copy_w;
    wire [1:0] read_ptr_r;
    reg [1:0] buffered_read_ptr_r;
    reg [1:0] response_read_ptr_r;
    reg buffered_response_r;
    reg [2:0] buffered_count_r;
    reg [2:0] response_count_r;
    assign read_ptr_r = buffered_response_r ? response_read_ptr_r : buffered_read_ptr_r;
    assign count_r = buffered_response_r ? response_count_r : buffered_count_r;
    reg [1:0] write_ptr_r;
    wire [2:0] count_r;
    wire redirect_w;
    wire [31:0] redirect_pc_w;
    wire predict_hit_w;
    wire predict_taken_w;
    wire [7:0] predict_taken_copy_w;
    wire [7:0] query_bank_copy_w;
    wire [31:0] predict_target_w;
    wire [1:0] predict_position_w;
    wire [11:0] predict_history_w;
    wire [36:0] predict_ras_w;
    wire request_accept_w;
    wire response_accept_w;
    wire [1:0] append_count_w;
    wire [2:0] response_available_w;
    wire push_one_w;
    wire push_two_w;
    wire [7:0] push_one_copy_w;
    wire [7:0] push_two_copy_w;
    wire [1:0] buffered_push_count_w;
    wire [1:0] response_push_count_w;
    wire [1:0] buffered_read_next_w;
    wire [1:0] response_read_next_w;
    assign buffered_push_count_w = ib_two_free_w && count_r >= 2 ? 2'd2 :
        ib_one_free_w && count_r != 0 ? 2'd1 : 2'd0;
    assign response_push_count_w = ib_two_free_w && response_available_w >= 2 ? 2'd2 :
        ib_one_free_w && response_available_w != 0 ? 2'd1 : 2'd0;
    assign buffered_read_next_w = read_ptr_r + buffered_push_count_w;
    assign response_read_next_w = f2_pending_r ?
        read_ptr_r + response_push_count_w : buffered_read_next_w;
    wire [2:0] buffered_remaining_w;
    wire [2:0] response_remaining_w;
    wire [31:0] sequential_pc_w;
    wire [31:0] next_pc_w;
    wire pc_advance_w;
    (* keep = "true" *) wire [31:0] unpredicted_pc_w;
    (* keep = "true" *) wire [31:0] predicted_pc_w;
    wire ib_one_free_w;
    wire ib_two_free_w;
    wire [STREAM_BITS-1:0] stream_w [0:1];
    wire [1:0] push_count_w;
    wire [357:0] push_data_w;
    wire [43:0] push_predecode_w;
    wire [5:0] push_index_hi_w;
    wire [23:0] push_tournament_w;
    wire [2:0] unused_update_align_w;
    assign unused_update_align_w = {update_pc_i[0], f2_pc_r[1:0]};
    assign redirect_w = redirect_valid_i || d_redirect_valid_i;
    assign redirect_pc_w = redirect_valid_i ? redirect_pc_i : d_redirect_pc_i;
    assign f2_query_w = {f1_pc_r, predict_hit_w, predict_conditional_w,
        predict_local_history_w, predict_global_w, predict_position_w, predict_target_w,
        predict_history_w, predict_ras_w};
    assign replay_pc_w = replay_payload_r[138:107];
    assign owner_query_w = replay_valid_r ? replay_payload_r : f2_query_w;
    assign owner_sequential_pc_w = {owner_query_w[138:110] + 29'd1, 3'b0};
    assign owner_taken_w = replay_valid_r ? replay_taken_r : predict_taken_w;
    assign {f2_pc_r, f2_hit_r, f2_conditional_r, f2_local_history_r, f2_global_r,
        f2_position_r, f2_target_r, f2_history_r, f2_ras_r} = f2_payload_r;
    // cpu-spec 4.4: evaluate once, even when the I$ response is delayed.
    // The correction rejects this cycle's F1 request and preserves the older F2 response.
    assign f2_local_w = f2_position_r[1] ?
        {f2_branch_local_w[0], f2_branch_local_w[1]} : f2_branch_local_w;
    assign f2_saved_local_w = f2_checked_r ? f2_local_r : f2_local_w;
    assign f2_final_taken_w = f2_use_local_w ?
        f2_branch_local_w[0] : f2_global_r[f2_position_r[1]];
    assign f2_taken_w = !f2_checked_r && f2_hit_r && f2_conditional_r ?
        f2_final_taken_w : f2_taken_r;
    assign f2_correct_w = f2_pending_r && !f2_checked_r && f2_correct_eligible_r &&
        f2_use_local_w && (f2_branch_local_w[0] != f2_taken_r) && !redirect_w;
    assign f2_count_w = f2_taken_w ? f2_taken_count_r : f2_sequential_count_r;
    assign response_accept_w = f2_pending_r && ic_resp_valid_i && !redirect_w;
    assign append_count_w = response_accept_w ? f2_count_w : 2'd0;
    // cpu-spec 4.9: compute both queue outcomes before the I$ response arrives.
    // The late hit must select a result, never feed the add/push/subtract chain.
    assign response_available_w = count_r + {1'b0, f2_count_w};
    // Read occupancy directly: avoid subtracting it from four and comparing the result.
    assign ib_one_free_w = ib_count_o < 4;
    assign ib_two_free_w = ib_count_o <= 2;
    // Constant decrements are parallel candidates, selected by the early IB occupancy.
    assign buffered_remaining_w = ib_two_free_w ? (count_r >= 2 ? count_r - 3'd2 : 3'd0) :
        ib_one_free_w ? (count_r != 0 ? count_r - 3'd1 : 3'd0) : count_r;
    assign response_remaining_w = ib_two_free_w ?
        (response_available_w >= 2 ? response_available_w - 3'd2 : 3'd0) :
        ib_one_free_w ? (response_available_w != 0 ? response_available_w - 3'd1 : 3'd0) :
        response_available_w;
    // Encode only at the interface; buffered records never wait for an I$ hit.
    assign push_one_w = !redirect_w && ib_one_free_w &&
        (count_r != 0 || (f2_pending_r && ic_resp_valid_i && f2_count_w != 0));
    assign push_two_w = !redirect_w && ib_two_free_w &&
        (count_r >= 2 || (f2_pending_r && ic_resp_valid_i &&
        (f2_count_w == 2 || (count_r == 1 && f2_count_w != 0))));
    assign push_count_w = {push_two_w, push_one_w && !push_two_w};
    // cpu-spec v0.19 4.1: credit covers IB4 + stream4, with two slots reserved
    // for every issued request. This cycle's D pop/response only affects next credit.
    assign ic_req_valid_o = rst_n_i && !halt_i && !redirect_w && !f2_correct_w &&
        (replay_valid_r || (!miss_wait_r && credit_r >= 2));
    assign new_request_w = request_accept_w && !replay_valid_r;
    assign owner_accept_w = request_accept_w && (!f2_pending_r || ic_resp_valid_i);
    assign miss_notice_w = f2_pending_r && !miss_wait_r && !ic_resp_valid_i && !redirect_w;
    assign sequential_pc_w = {f1_pc_copy3_r + 29'd1, 3'b0};
    // cpu-spec 4.4/4.9: all addresses are parallel candidates. The late cache
    // handshake only selects a candidate; it never enters a PC incrementer.
    assign pc_advance_w = rst_n_i && !halt_i && !miss_wait_r &&
        credit_r >= 2 && ic_req_ready_i;
    // Both outcomes include replay/hold before the final prediction decision.
    // A late BTB valid result selects complete candidates at the register boundary.
    assign unpredicted_pc_w = replay_valid_r ?
        (rst_n_i && !halt_i && ic_req_ready_i ? replay_resume_pc_r : replay_pc_w) :
        pc_advance_w ? sequential_pc_w : f1_pc_r;
    assign predicted_pc_w = replay_valid_r ?
        (rst_n_i && !halt_i && ic_req_ready_i ? replay_resume_pc_r : replay_pc_w) :
        pc_advance_w ? predict_target_w : f1_pc_r;
    assign ic_req_addr_o = replay_valid_r ? {replay_pc_w[31:3], 3'b0} :
        {f1_pc_copy2_r, 3'b0};
    assign request_accept_w = ic_req_valid_o && ic_req_ready_i;
    assign ic_kill_o = redirect_w && f2_pending_r;
    assign ic_inv_o = invalidate_i;
    assign invalidate_done_o = ic_inv_done_i;
    assign f1_valid_o = ic_req_valid_o;
    assign f2_valid_o = f2_pending_r || replay_valid_r || count_r != 0;
    assign fetch_wait_o = miss_wait_r;
    edrv32_cpu_predictor u_predictor (
        .clk_i(clk_i),
        .rst_n_i(rst_n_i),
        .query_pc_i(f1_pc_copy1_r[31:1]),
        .query_valid_index_i(query_valid_index_w),
        .query_bank_copy_i(query_bank_copy_w),
        .query_accept_i(new_request_w),
        .predict_hit_o(predict_hit_w),
        .predict_taken_o(predict_taken_w),
        .predict_taken_copy_o(predict_taken_copy_w),
        .predict_target_o(predict_target_w),
        .predict_position_o(predict_position_w),
        .predict_history_o(predict_history_w),
        .predict_ras_o(predict_ras_w),
        .update_valid_i(update_valid_i),
        .update_pc_i(update_pc_i[31:1]),
        .update_target_i(update_target_i),
        .update_type_i(update_type_i),
        .update_taken_i(update_taken_i),
        .update_index_i(update_index_i),
        .update_tournament_i(update_tournament_i),
        .predict_conditional_o(predict_conditional_w),
        .predict_local_history_o(predict_local_history_w),
        .predict_global_o(predict_global_w),
        .f2_local_history_i(f2_direction_history_r),
        .f2_index_i(f2_index_r),
        .f2_local_o(f2_branch_local_w),
        .f2_use_local_o(f2_use_local_w),
        .clear_valid_i(update_clear_i),
        .clear_index_i(update_clear_index_i),
        .restore_valid_i(redirect_valid_copy_i[16]),
        .restore_valid_copy_i(redirect_valid_copy_i[15:0]),
        .restore_ras_i(redirect_valid_i ? redirect_ras_i : d_redirect_ras_i),
        .restore_push_i(redirect_valid_i ? redirect_push_i : d_redirect_push_i),
        .restore_pop_i(redirect_valid_i ? redirect_pop_i : d_redirect_pop_i),
        .restore_return_pc_i(redirect_valid_i ? redirect_return_pc_i : d_redirect_return_pc_i)
    );
    edrv32_cpu_ib u_ib (
        .clk_i(clk_i),
        .rst_n_i(rst_n_i),
        .push_count_i(push_count_w),
        .push_one_i(push_one_w),
        .push_two_i(push_two_w),
        .push_one_copy_i(push_one_copy_w),
        .push_two_copy_i(push_two_copy_w),
        .push_data_i(push_data_w),
        .push_predecode_i(push_predecode_w),
        .push_index_hi_i(push_index_hi_w),
        .push_tournament_i(push_tournament_w),
        .tournament_o(decode_tournament_o),
        .index_hi_o(decode_index_hi_o),
        .pop_count_i(decode_pop_count_i),
        .data_o(decode_data_o),
        .predecode_o(decode_predecode_o),
        .operand_addr_o(decode_operand_addr_o),
        .valid_count_o(decode_valid_count_o),
        .flush_i(redirect_w),
        .keep_head_i(d_redirect_valid_i && !redirect_valid_i && decode_pop_count_i == 0),
        .keep_pair_i(d_redirect_slot_i),
        .count_o(ib_count_o)
    );
    genvar slot;
    genvar entry;
    genvar slice;
    genvar f2_group;
    genvar pc_group;
    genvar bank_copy;
    generate
        for (bank_copy = 0; bank_copy < 8; bank_copy = bank_copy + 1) begin : g_query_bank
            assign push_one_copy_w[bank_copy] = !redirect_w && ib_one_free_w &&
                (count_r != 0 || (f2_pending_r &&
                ic_resp_valid_copy_i[bank_copy] && f2_count_w != 0));
            assign push_two_copy_w[bank_copy] = !redirect_w && ib_two_free_w &&
                (count_r >= 2 || (f2_pending_r && ic_resp_valid_copy_i[bank_copy] &&
                (f2_count_w == 2 || (count_r == 1 && f2_count_w != 0))));
            (* keep = "true", syn_preserve = 1 *) reg query_bank_copy1_r;
            assign query_bank_copy_w[bank_copy] = query_bank_copy1_r;
            always @(posedge clk_i or negedge rst_n_i) begin
                if (!rst_n_i)
                    query_bank_copy1_r <= 0;
                else
                    query_bank_copy1_r <= next_pc_w[9];
            end
        end
        for (pc_group = 0; pc_group < 8; pc_group = pc_group + 1) begin : g_pc
            (* keep = "true", syn_preserve = 1 *) reg f2_taken_copy1_r;
            wire owner_target_select_w;
            (* keep = "true", syn_preserve = 1 *) reg correct_active_copy1_r;
            wire correct_w;
            (* keep = "true" *) wire [3:0] unpredicted_w;
            (* keep = "true" *) wire [3:0] predicted_w;
            assign correct_w = correct_active_copy1_r && f2_use_local_w &&
                (f2_branch_local_w[0] != f2_taken_copy1_r);
            always @(posedge clk_i or negedge rst_n_i) begin
                if (!rst_n_i)
                    correct_active_copy1_r <= 0;
                else
                    correct_active_copy1_r <= owner_accept_w &&
                        owner_query_w[106] && owner_query_w[105];
            end
            assign unpredicted_w = redirect_w ? redirect_pc_w[pc_group*4 +: 4] :
                correct_w ? f2_correct_pc_w[pc_group*4 +: 4] :
                unpredicted_pc_w[pc_group*4 +: 4];
            assign predicted_w = redirect_w ? redirect_pc_w[pc_group*4 +: 4] :
                correct_w ? f2_correct_pc_w[pc_group*4 +: 4] :
                predicted_pc_w[pc_group*4 +: 4];
            assign next_pc_w[pc_group*4 +: 4] = predict_taken_copy_w[pc_group] ?
                predicted_w : unpredicted_w;
            always @(posedge clk_i) begin
                if (!replay_valid_copy1_r)
                    replay_resume_pc_r[pc_group*4 +: 4] <= predict_taken_copy_w[pc_group] ?
                        predict_target_w[pc_group*4 +: 4] : sequential_pc_w[pc_group*4 +: 4];
            end
            // Distinct initial-direction FFs prevent synthesis from expanding
            // the late RAM comparison into every correction address bit.
            assign owner_target_select_w = replay_valid_r ? replay_taken_r :
                predict_taken_copy_w[pc_group];
            assign f2_correct_pc_w[pc_group*4 +: 4] =
                f2_correct_addr_r[pc_group*4 +: 4];
            always @(posedge clk_i) begin
                f2_taken_copy1_r <= owner_taken_w;
                f2_correct_addr_r[pc_group*4 +: 4] <= owner_target_select_w ?
                    owner_sequential_pc_w[pc_group*4 +: 4] :
                    owner_query_w[49+pc_group*4 +: 4];
            end
        end
        for (f2_group = 0; f2_group < 8; f2_group = f2_group + 1) begin : g_query_index
            (* keep = "true", syn_preserve = 1 *) reg [3:0] query_valid_index_copy1_r;
            assign query_valid_index_w[f2_group*4 +: 4] = query_valid_index_copy1_r;
            always @(posedge clk_i or negedge rst_n_i) begin
                if (!rst_n_i)
                    query_valid_index_copy1_r <= 0;
                else
                    query_valid_index_copy1_r <= next_pc_w[6:3];
            end
        end
        // Each capture group retains one owner bit and no more than sixteen data bits.
        // Owner copies use their own registered state when computing the next request.
        for (f2_group = 0; f2_group < 9; f2_group = f2_group + 1) begin : g_f2_capture
            localparam WIDTH = f2_group == 8 ? 11 : 16;
            (* keep = "true", syn_preserve = 1 *) reg f2_pending_copy1_r;
            wire response_valid_w;
            wire capture_accept_w;
            assign f2_pending_copy_w[f2_group] = f2_pending_copy1_r;
            assign response_valid_w = ic_resp_valid_copy_i[f2_group % 8];
            assign capture_accept_w = request_accept_w &&
                (!f2_pending_copy1_r || response_valid_w);
            always @(posedge clk_i or negedge rst_n_i) begin
                if (!rst_n_i)
                    f2_pending_copy1_r <= 0;
                else if (redirect_w)
                    f2_pending_copy1_r <= 0;
                else begin
                    if (response_valid_w)
                        f2_pending_copy1_r <= 0;
                    if (capture_accept_w)
                        f2_pending_copy1_r <= 1;
                end
            end
            always @(posedge clk_i) begin
                if (!f2_pending_copy1_r || response_valid_w)
                    f2_payload_r[f2_group*16 +: WIDTH] <= owner_query_w[f2_group*16 +: WIDTH];
            end
        end
        for (slot = 0; slot < 2; slot = slot + 1) begin : g_read
            wire offset_w;
            wire position_w;
            wire [31:0] pc_w;
            wire [STREAM_BITS-1:0] response_w;
            assign offset_w = slot[0] ^ count_r[0];
            assign position_w = f2_pc_r[2] ^ offset_w;
            assign pc_w = {f2_pc_r[31:3], position_w, 2'b0};
            // {RAS, history, target, taken, hit, error, PC, instruction}.
            assign response_w = {ic_resp_predecode_i[position_w*22 +: 22],
                f2_global_r[position_w], f2_saved_local_w[position_w],
                f2_local_history_r[position_w*10 +: 10], f2_ras_r, f2_history_r, f2_target_r,
                f2_taken_w && {position_w, 1'b0} == f2_position_r,
                f2_hit_r && {position_w, 1'b0} == f2_position_r,
                ic_resp_err_i, pc_w, ic_resp_data_i[position_w*32 +: 32]};
            // Each eight-bit slice owns its queue-select registers. This bounds
            // the fanout of the selects feeding the IB record write mux.
            for (slice = 0; slice < 23; slice = slice + 1) begin : g_slice
                localparam WIDTH = slice == 22 ? 6 : 8;
                reg [1:0] buffered_read_ptr_copy_r /* synthesis syn_preserve=1 */;
                reg [1:0] response_read_ptr_copy_r /* synthesis syn_preserve=1 */;
                reg [2:0] buffered_count_copy_r /* synthesis syn_preserve=1 */;
                reg [2:0] response_count_copy_r /* synthesis syn_preserve=1 */;
                reg response_select_copy_r /* synthesis syn_preserve=1 */;
                wire [1:0] read_ptr_copy_w;
                wire [2:0] count_copy_w;
                wire [1:0] read_w;
                assign read_ptr_copy_w = response_select_copy_r ?
                    response_read_ptr_copy_r : buffered_read_ptr_copy_r;
                assign count_copy_w = response_select_copy_r ?
                    response_count_copy_r : buffered_count_copy_r;
                assign read_w = read_ptr_copy_w + slot[1:0];
                assign stream_w[slot][slice*8 +: WIDTH] = count_copy_w > slot ?
                    words_r[read_w][slice*8 +: WIDTH] : response_w[slice*8 +: WIDTH];
                // Retiming the late hit select preserves the cycle's queue state.
                // Both next-state candidates are captured from registers alone.
                always @(posedge clk_i or negedge rst_n_i) begin
                    if (!rst_n_i) begin
                        response_select_copy_r <= 0;
                        buffered_read_ptr_copy_r <= 0;
                        response_read_ptr_copy_r <= 0;
                        buffered_count_copy_r <= 0;
                        response_count_copy_r <= 0;
                    end else begin
                        response_select_copy_r <= ic_resp_valid_copy_i[(slot*23+slice)%8];
                        buffered_read_ptr_copy_r <= redirect_w ? 2'd0 : buffered_read_next_w;
                        response_read_ptr_copy_r <= redirect_w ? 2'd0 : response_read_next_w;
                        buffered_count_copy_r <= redirect_w ? 3'd0 : buffered_remaining_w;
                        response_count_copy_r <= redirect_w ? 3'd0 :
                            f2_pending_r ? response_remaining_w : buffered_remaining_w;
                    end
                end
            end
            assign push_predecode_w[slot*22 +: 22] = stream_w[slot][181:160];
            assign push_tournament_w[slot*12 +: 12] = stream_w[slot][159:148];
            assign push_index_hi_w[slot*3 +: 3] =
                stream_w[slot][110:108] ^ stream_w[slot][45:43];
            assign push_data_w[slot*REC_BITS +: REC_BITS] = {
                stream_w[slot][147:111],
                stream_w[slot][107:99] ^ stream_w[slot][42:34],
                stream_w[slot][98:64], 2'b0,
                stream_w[slot][31:0], stream_w[slot][31:0], stream_w[slot][63:32]};
        end
        for (entry = 0; entry < 4; entry = entry + 1) begin : g_write
            wire [1:0] offset_w;
            wire position_w;
            wire [STREAM_BITS-1:0] response_w;
            assign offset_w = entry[1:0] - write_ptr_r;
            assign position_w = f2_pc_r[2] ^ offset_w[0];
            assign response_w = {ic_resp_predecode_i[position_w*22 +: 22],
                f2_global_r[position_w], f2_saved_local_w[position_w],
                f2_local_history_r[position_w*10 +: 10], f2_ras_r,
                f2_history_r, f2_target_r,
                f2_taken_w && {position_w, 1'b0} == f2_position_r,
                f2_hit_r && {position_w, 1'b0} == f2_position_r,
                ic_resp_err_i, f2_pc_r[31:3], position_w, 2'b0,
                ic_resp_data_i[position_w*32 +: 32]};
            // Every request reserves two stream slots. Capture speculatively
            // while it owns F2; append_count_w alone grants record ownership.
            // A delayed response overwrites unowned data on its returning edge.
            for (slice = 0; slice < 23; slice = slice + 1) begin : g_slice
                localparam GROUP = entry*23 + slice;
                localparam WIDTH = slice == 22 ? 6 : 8;
                always @(posedge clk_i) begin
                    if (f2_pending_copy_w[GROUP % 9] && !offset_w[1])
                        words_r[entry][slice*8 +: WIDTH] <= response_w[slice*8 +: WIDTH];
                end
            end
        end
    endgenerate
    // The discarded successor keeps its original prediction/RAS checkpoint.
    // Reissuing that token consumes no second credit or speculative RAS action.
    // Snapshot until replay owns it; the dedicated hold copy isolates the wide CE load.
    always @(posedge clk_i) begin
        if (!replay_valid_copy1_r) begin
            replay_payload_r <= f2_query_w;
            replay_taken_r <= predict_taken_w;
        end
    end
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            miss_wait_r <= 0;
            replay_valid_r <= 0;
            replay_valid_copy1_r <= 0;
            credit_r <= 8;
        end else if (redirect_w) begin
            miss_wait_r <= 0;
            replay_valid_r <= 0;
            replay_valid_copy1_r <= 0;
            credit_r <= d_redirect_valid_i && !redirect_valid_i && decode_pop_count_i == 0 ?
                (d_redirect_slot_i ? 4'd6 : 4'd7) : 4'd8;
        end else begin
            if (miss_notice_w) begin
                miss_wait_r <= 1;
                replay_valid_r <= new_request_w;
                replay_valid_copy1_r <= new_request_w;
            end
            if (response_accept_w)
                miss_wait_r <= 0;
            if (request_accept_w && replay_valid_r) begin
                replay_valid_r <= 0;
                replay_valid_copy1_r <= 0;
            end
            credit_r <= credit_r + {2'b0, decode_pop_count_i} -
                (new_request_w ? 4'd2 : 4'd0) +
                (response_accept_w ? 4'd2 - {2'b0, f2_count_w} : 4'd0);
        end
    end
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            f1_pc_r <= 0;
            f1_pc_copy1_r <= 0;
            f1_pc_copy2_r <= 0;
            f1_pc_copy3_r <= 0;
        end else begin
            f1_pc_r <= next_pc_w;
            f1_pc_copy1_r <= next_pc_w[31:1];
            f1_pc_copy2_r <= next_pc_w[31:3];
            f1_pc_copy3_r <= next_pc_w[31:3];
        end
    end
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            f2_pending_r <= 0;
            f2_checked_r <= 0;
            buffered_read_ptr_r <= 0;
            response_read_ptr_r <= 0;
            buffered_response_r <= 0;
            buffered_count_r <= 0;
            response_count_r <= 0;
            write_ptr_r <= 0;
        end else if (redirect_w) begin
            f2_pending_r <= 0;
            f2_checked_r <= 0;
            buffered_read_ptr_r <= 0;
            response_read_ptr_r <= 0;
            buffered_response_r <= 0;
            buffered_count_r <= 0;
            response_count_r <= 0;
            write_ptr_r <= 0;
        end else begin
            buffered_response_r <= ic_resp_valid_i;
            buffered_read_ptr_r <= buffered_read_next_w;
            response_read_ptr_r <= response_read_next_w;
            buffered_count_r <= buffered_remaining_w;
            response_count_r <= f2_pending_r ? response_remaining_w : buffered_remaining_w;
            write_ptr_r <= write_ptr_r + append_count_w;
            if (f2_pending_r)
                f2_checked_r <= 1;
            if (response_accept_w)
                f2_pending_r <= 0;
            if (owner_accept_w) begin
                f2_pending_r <= 1;
                f2_checked_r <= 0;
            end
        end
    end
    // Both correction addresses and the chooser index are ready in F2 before
    // the LUTRAM decision. Initial direction selects the opposite stored address.
    always @(posedge clk_i) begin
        // The response may arrive after F1/replay has changed owners. Retain
        // the pending F2 owner's instruction counts for its eventual response.
        if (!f2_pending_r || ic_resp_valid_i) begin
            f2_taken_count_r <= {!owner_query_w[109] && owner_query_w[82],
                owner_query_w[109] ^ !owner_query_w[82]};
            f2_sequential_count_r <= {!owner_query_w[109], owner_query_w[109]};
        end
        f2_correct_eligible_r <= owner_query_w[106] && owner_query_w[105];
        f2_direction_history_r <= owner_query_w[82] ?
            {owner_query_w[94:85], owner_query_w[104:95]} : owner_query_w[104:85];
        f2_index_r <= {owner_query_w[120:110], owner_query_w[82]} ^ owner_query_w[48:37];
        if (f2_pending_r && !f2_checked_r) begin
            f2_taken_r <= f2_taken_w;
            f2_local_r <= f2_local_w;
        end
        if (!f2_pending_r || ic_resp_valid_i)
            f2_taken_r <= owner_taken_w;
    end
endmodule
