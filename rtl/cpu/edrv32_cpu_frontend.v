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
    // Fixed four-byte instructions: a response contributes one or two whole words.
    localparam REC_BITS = 179;
    localparam STREAM_BITS = 160;
    reg [31:0] f1_pc_r /* synthesis syn_maxfan=16 */;
    reg [31:3] f1_icache_pc_r /* synthesis syn_preserve=1 */;
    reg f2_pending_r;
    reg [31:0] f2_pc_r;
    wire [1:0] f2_count_w;
    reg f2_checked_r;
    reg f2_conditional_r;
    reg [19:0] f2_local_history_r;
    reg [1:0] f2_global_r;
    reg [1:0] f2_local_r;
    wire [1:0] f2_local_w;
    wire [1:0] f2_saved_local_w;
    wire f2_use_local_w;
    wire f2_final_taken_w;
    wire f2_taken_w;
    wire f2_correct_w;
    wire [31:0] f2_correct_pc_w;
    wire [19:0] predict_local_history_w;
    wire [1:0] predict_global_w;
    wire predict_conditional_w;
    reg f2_hit_r;
    reg f2_taken_r;
    reg [1:0] f2_position_r;
    reg [31:0] f2_target_r;
    reg [11:0] f2_history_r;
    reg [36:0] f2_ras_r;
    reg [STREAM_BITS-1:0] words_r [0:3];
    reg [1:0] read_ptr_r;
    reg [1:0] write_ptr_r;
    reg [2:0] count_r;
    wire redirect_w;
    wire [31:0] redirect_pc_w;
    wire predict_hit_w;
    wire predict_taken_w;
    wire [31:0] predict_target_w;
    wire [1:0] predict_position_w;
    wire [11:0] predict_history_w;
    wire [36:0] predict_ras_w;
    wire request_accept_w;
    wire response_accept_w;
    wire [1:0] append_count_w;
    wire [2:0] remaining_w;
    wire [2:0] response_available_w;
    wire push_one_w;
    wire push_two_w;
    wire [2:0] buffered_remaining_w;
    wire [2:0] response_remaining_w;
    wire request_space_w;
    wire [31:0] sequential_pc_w;
    (* keep = 1 *) wire [31:0] default_pc_w /* synthesis syn_keep=1 */;
    wire ib_one_free_w;
    wire ib_two_free_w;
    wire buffered_space_w;
    wire response_space_w;
    wire [STREAM_BITS-1:0] stream_w [0:1];
    wire [1:0] push_count_w;
    wire [357:0] push_data_w;
    wire [5:0] push_index_hi_w;
    wire [23:0] push_tournament_w;
    wire [2:0] unused_update_align_w;
    assign unused_update_align_w = {update_pc_i[0], f2_pc_r[1:0]};
    assign redirect_w = redirect_valid_i || d_redirect_valid_i;
    assign redirect_pc_w = redirect_valid_i ? redirect_pc_i : d_redirect_pc_i;
    // cpu-spec 4.4: evaluate once, even when the I$ response is delayed.
    // The correction rejects this cycle's F1 request and preserves the older F2 response.
    assign f2_saved_local_w = f2_checked_r ? f2_local_r : f2_local_w;
    assign f2_final_taken_w = f2_use_local_w ?
        f2_local_w[f2_position_r[1]] : f2_global_r[f2_position_r[1]];
    assign f2_taken_w = !f2_checked_r && f2_hit_r && f2_conditional_r ?
        f2_final_taken_w : f2_taken_r;
    assign f2_correct_w = f2_pending_r && !f2_checked_r && f2_hit_r &&
        f2_conditional_r && f2_final_taken_w != f2_taken_r && !redirect_w;
    assign f2_correct_pc_w = f2_final_taken_w ? f2_target_r :
        {f2_pc_r[31:3] + 29'd1, 3'b0};
    assign f2_count_w = {!f2_pc_r[2] && (!f2_taken_w || f2_position_r[1]),
        f2_pc_r[2] ^ (f2_taken_w && !f2_position_r[1])};
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
    assign buffered_space_w = count_r <= 2 ||
        (count_r == 3 && ib_one_free_w) || (count_r == 4 && ib_two_free_w);
    assign response_space_w = response_available_w <= 2 ||
        (response_available_w == 3 && ib_one_free_w) ||
        (response_available_w == 4 && ib_two_free_w);
    // Encode only at the interface; buffered records never wait for an I$ hit.
    assign push_one_w = !redirect_w && ib_one_free_w &&
        (count_r != 0 || (f2_pending_r && ic_resp_valid_i && f2_count_w != 0));
    assign push_two_w = !redirect_w && ib_two_free_w &&
        (count_r >= 2 || (f2_pending_r && ic_resp_valid_i &&
        (f2_count_w == 2 || (count_r == 1 && f2_count_w != 0))));
    assign push_count_w = {push_two_w, push_one_w && !push_two_w};
    assign remaining_w = response_accept_w ? response_remaining_w : buffered_remaining_w;
    // Reserve response storage using only IB slots free at cycle start (spec 4.1).
    assign request_space_w = (!f2_pending_r && buffered_space_w) ||
        (ic_resp_valid_i && response_space_w);
    assign ic_req_valid_o = rst_n_i && !halt_i && !redirect_w && !f2_correct_w && request_space_w;
    assign sequential_pc_w = {f1_icache_pc_r + 29'd1, 3'b0};
    // Compute redirect/hold/sequential selection independently of the prediction.
    // The late BTB/direction decision then crosses a single data mux.
    assign default_pc_w = redirect_w ? redirect_pc_w :
        f2_correct_w ? f2_correct_pc_w :
        request_accept_w ? sequential_pc_w : f1_pc_r;
    assign ic_req_addr_o = {f1_icache_pc_r, 3'b0};
    assign request_accept_w = ic_req_valid_o && ic_req_ready_i;
    assign ic_kill_o = redirect_w && f2_pending_r;
    assign ic_inv_o = invalidate_i;
    assign invalidate_done_o = ic_inv_done_i;
    assign f1_valid_o = ic_req_valid_o;
    assign f2_valid_o = f2_pending_r || count_r != 0;
    assign fetch_wait_o = f2_pending_r && !ic_resp_valid_i;
    edrv32_cpu_predictor u_predictor (
        .clk_i(clk_i),
        .rst_n_i(rst_n_i),
        .query_pc_i(f1_pc_r[31:1]),
        .query_accept_i(request_accept_w),
        .predict_hit_o(predict_hit_w),
        .predict_taken_o(predict_taken_w),
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
        .f2_local_history_i(f2_local_history_r),
        .f2_index_i({f2_pc_r[13:3], f2_position_r[1]} ^ f2_history_r),
        .f2_local_o(f2_local_w),
        .f2_use_local_o(f2_use_local_w),
        .clear_valid_i(update_clear_i),
        .clear_index_i(update_clear_index_i),
        .restore_valid_i(redirect_w),
        .restore_ras_i(redirect_valid_i ? redirect_ras_i : d_redirect_ras_i),
        .restore_push_i(redirect_valid_i ? redirect_push_i : d_redirect_push_i),
        .restore_pop_i(redirect_valid_i ? redirect_pop_i : d_redirect_pop_i),
        .restore_return_pc_i(redirect_valid_i ? redirect_return_pc_i : d_redirect_return_pc_i)
    );
    edrv32_cpu_ib u_ib (
        .clk_i(clk_i),
        .rst_n_i(rst_n_i),
        .push_count_i(push_count_w),
        .push_data_i(push_data_w),
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
    generate
        for (slot = 0; slot < 2; slot = slot + 1) begin : g_read
            wire offset_w;
            wire position_w;
            wire [31:0] pc_w;
            wire [STREAM_BITS-1:0] response_w;
            assign offset_w = slot[0] ^ count_r[0];
            assign position_w = f2_pc_r[2] ^ offset_w;
            assign pc_w = {f2_pc_r[31:3], position_w, 2'b0};
            // {RAS, history, target, taken, hit, error, PC, instruction}.
            assign response_w = {f2_global_r[position_w], f2_saved_local_w[position_w],
                f2_local_history_r[position_w*10 +: 10], f2_ras_r, f2_history_r, f2_target_r,
                f2_taken_w && {position_w, 1'b0} == f2_position_r,
                f2_hit_r && {position_w, 1'b0} == f2_position_r,
                ic_resp_err_i, pc_w, ic_resp_data_i[position_w*32 +: 32]};
            // Each eight-bit slice owns its queue-select registers. This bounds
            // the fanout of the selects feeding the IB record write mux.
            for (slice = 0; slice < 20; slice = slice + 1) begin : g_slice
                localparam WIDTH = 8;
                reg [1:0] read_ptr_copy_r /* synthesis syn_preserve=1 */;
                reg [2:0] count_copy_r /* synthesis syn_preserve=1 */;
                wire [1:0] read_w;
                assign read_w = read_ptr_copy_r + slot[1:0];
                assign stream_w[slot][slice*8 +: WIDTH] = count_copy_r > slot ?
                    words_r[read_w][slice*8 +: WIDTH] : response_w[slice*8 +: WIDTH];
                always @(posedge clk_i or negedge rst_n_i) begin
                    if (!rst_n_i) begin
                        read_ptr_copy_r <= 0;
                        count_copy_r <= 0;
                    end else if (redirect_w) begin
                        read_ptr_copy_r <= 0;
                        count_copy_r <= 0;
                    end else begin
                        read_ptr_copy_r <= read_ptr_r + push_count_w;
                        count_copy_r <= remaining_w;
                    end
                end
            end
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
            assign offset_w = entry[1:0] - write_ptr_r;
            assign position_w = f2_pc_r[2] ^ offset_w[0];
            always @(posedge clk_i) begin
                if (f2_pending_r && ic_resp_valid_i && offset_w < f2_count_w)
                    words_r[entry] <= {f2_global_r[position_w], f2_saved_local_w[position_w],
                        f2_local_history_r[position_w*10 +: 10], f2_ras_r,
                        f2_history_r, f2_target_r,
                        f2_taken_w && {position_w, 1'b0} == f2_position_r,
                        f2_hit_r && {position_w, 1'b0} == f2_position_r,
                        ic_resp_err_i, f2_pc_r[31:3], position_w, 2'b0,
                        ic_resp_data_i[position_w*32 +: 32]};
            end
        end
    endgenerate
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            f1_pc_r <= 0;
            f1_icache_pc_r <= 0;
        end else begin
            f1_pc_r <= request_accept_w && predict_taken_w ? predict_target_w : default_pc_w;
            f1_icache_pc_r <= request_accept_w && predict_taken_w ? predict_target_w[31:3] :
                default_pc_w[31:3];
        end
    end
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            f2_pending_r <= 0;
            f2_checked_r <= 0;
            read_ptr_r <= 0;
            write_ptr_r <= 0;
            count_r <= 0;
        end else if (redirect_w) begin
            f2_pending_r <= 0;
            f2_checked_r <= 0;
            read_ptr_r <= 0;
            write_ptr_r <= 0;
            count_r <= 0;
        end else begin
            count_r <= remaining_w;
            read_ptr_r <= read_ptr_r + push_count_w;
            write_ptr_r <= write_ptr_r + append_count_w;
            if (f2_pending_r)
                f2_checked_r <= 1;
            if (response_accept_w)
                f2_pending_r <= 0;
            if (request_accept_w) begin
                f2_pending_r <= 1;
                f2_checked_r <= 0;
            end
        end
    end
    always @(posedge clk_i) begin
        if (f2_pending_r && !f2_checked_r) begin
            f2_taken_r <= f2_taken_w;
            f2_local_r <= f2_local_w;
        end
        if (!f2_pending_r || ic_resp_valid_i) begin
            f2_pc_r <= f1_pc_r;
            f2_hit_r <= predict_hit_w;
            f2_taken_r <= predict_taken_w;
            f2_conditional_r <= predict_conditional_w;
            f2_local_history_r <= predict_local_history_w;
            f2_global_r <= predict_global_w;
            f2_position_r <= predict_position_w;
            f2_target_r <= predict_target_w;
            f2_history_r <= predict_history_w;
            f2_ras_r <= predict_ras_w;
        end
    end
endmodule
