// File: edrv32_cpu2_frontend.v
// Spec: cpu-v2-spec 3.3, 3.8, 5.1, 5.4, 5.5, 6.2/6.3.
// Description: Two ordered request contexts connect F1 prediction to F2 cache return.
// Registered corrections cancel younger contexts and restore the retained RAS prefix.
// Clock domain: clk_sys.
module edrv32_cpu2_frontend #(
    parameter ISSUE_WIDTH = 2,
    parameter [31:0] FPU_FORMAT = "NONE"
) (
    clk_i,
    rst_n_i,
    frontend_flush_i,
    redirect_valid_i,
    redirect_pc_i,
    branch_redirect_valid_i,
    branch_redirect_tag_i,
    branch_redirect_pc_i,
    commit_redirect_valid_i,
    commit_redirect_pc_i,
    fetch_stop_i,
    branch_redirect_ras_data_i,
    branch_redirect_ras_ptr_i,
    branch_redirect_ras_count_i,
    branch_redirect_ras_pop_i,
    branch_redirect_ras_push_i,
    branch_redirect_link_i,
    ib_remove_count_i,
    ib_credit_o,
    lvt_i,
    wb0_valid_i,
    wb0_rd_i,
    wb1_valid_i,
    wb1_rd_i,
    wb0_valid_copy_i,
    wb0_rd_copy_i,
    wb1_valid_copy_i,
    wb1_rd_copy_i,
    ib_head0_valid_o,
    ib_head1_valid_o,
    ib_head0_pc_o,
    ib_head0_instr_o,
    ib_head0_error_o,
    ib_head0_candidates_o,
    ib_head0_predict_taken_o,
    ib_head0_predict_target_o,
    ib_head0_predict_token_o,
    ib_head0_predict_provider_o,
    ib_head0_predict_alternate_o,
    ib_head0_predict_index0_o,
    ib_head0_predict_index1_o,
    ib_head0_predict_index2_o,
    ib_head0_predict_index3_o,
    ib_head0_predict_tag0_o,
    ib_head0_predict_tag1_o,
    ib_head0_predict_tag2_o,
    ib_head0_predict_tag3_o,
    ib_head0_predict_base_index_o,
    ib_head0_predict_fast_index_o,
    ib_head0_ras_data_o,
    ib_head0_ras_ptr_o,
    ib_head0_ras_count_o,
    ib_head1_pc_o,
    ib_head1_instr_o,
    ib_head1_error_o,
    ib_head1_candidates_o,
    ib_head1_predict_taken_o,
    ib_head1_predict_target_o,
    ib_head1_predict_token_o,
    ib_head1_predict_provider_o,
    ib_head1_predict_alternate_o,
    ib_head1_predict_index0_o,
    ib_head1_predict_index1_o,
    ib_head1_predict_index2_o,
    ib_head1_predict_index3_o,
    ib_head1_predict_tag0_o,
    ib_head1_predict_tag1_o,
    ib_head1_predict_tag2_o,
    ib_head1_predict_tag3_o,
    ib_head1_predict_base_index_o,
    ib_head1_predict_fast_index_o,
    ib_head1_ras_data_o,
    ib_head1_ras_ptr_o,
    ib_head1_ras_count_o,
    ic_req_valid_o,
    ic_req_ready_i,
    ic_req_addr_o,
    ic_resp_valid_i,
    ic_resp_ready_o,
    ic_cancel_o,
    f2_redirect_valid_o,
    f2_redirect_pc_o,
    f2_redirect_target_o,
    f2_redirect_cause_o,
    ic_resp_bank0_way0_instr_i,
    ic_resp_bank0_way1_instr_i,
    ic_resp_bank1_way0_instr_i,
    ic_resp_bank1_way1_instr_i,
    ic_resp_bank0_way_hit_i,
    ic_resp_bank0_error_i,
    ic_resp_bank1_way_hit_i,
    ic_resp_bank1_error_i,
    predict_read0_valid_i,
    predict_read0_tag_i,
    predict_read0_index0_i,
    predict_read0_index1_i,
    predict_read0_index2_i,
    predict_read0_index3_i,
    predict_read0_tag0_i,
    predict_read0_tag1_i,
    predict_read0_tag2_i,
    predict_read0_tag3_i,
    predict_read0_base_index_i,
    predict_read1_valid_i,
    predict_read1_tag_i,
    predict_read1_index0_i,
    predict_read1_index1_i,
    predict_read1_index2_i,
    predict_read1_index3_i,
    predict_read1_tag0_i,
    predict_read1_tag1_i,
    predict_read1_tag2_i,
    predict_read1_tag3_i,
    predict_read1_base_index_i,
    ex_predict_train_valid_i,
    ex_predict_train_tag_i,
    ex_predict_train_pc_i,
    ex_predict_train_taken_i,
    ex_predict_train_target_i,
    ex_predict_train_type_i,
    ex_predict_train_fast_index_i,
    ex_predict_train_token_i,
    ex_predict_train_provider_i,
    ex_predict_train_prediction_i,
    ex_predict_train_alternate_i,
    ex_predict_train_index0_i,
    ex_predict_train_index1_i,
    ex_predict_train_index2_i,
    ex_predict_train_index3_i,
    ex_predict_train_tag0_i,
    ex_predict_train_tag1_i,
    ex_predict_train_tag2_i,
    ex_predict_train_tag3_i,
    ex_predict_train_base_index_i,
    mem_predict_train_valid_i,
    mem_predict_train_tag_i,
    mem_predict_train_pc_i,
    mem_predict_train_taken_i,
    mem_predict_train_target_i,
    mem_predict_train_type_i,
    mem_predict_train_fast_index_i,
    mem_predict_train_token_i,
    mem_predict_train_provider_i,
    mem_predict_train_prediction_i,
    mem_predict_train_alternate_i,
    mem_predict_train_index0_i,
    mem_predict_train_index1_i,
    mem_predict_train_index2_i,
    mem_predict_train_index3_i,
    mem_predict_train_tag0_i,
    mem_predict_train_tag1_i,
    mem_predict_train_tag2_i,
    mem_predict_train_tag3_i,
    mem_predict_train_base_index_i,
    age_head_i,
    cancel_valid_i,
    cancel_tag_i,
    ib_count_o,
    frontend_active_o
);
    localparam TAG_BITS = (ISSUE_WIDTH == 2 || FPU_FORMAT == "FD") ? 4 : 3;
    localparam RAS_BITS = (ISSUE_WIDTH == 2) ? 256 : 128;
    localparam RAS_PTR_BITS = (ISSUE_WIDTH == 2) ? 3 : 2;
    localparam RAS_COUNT_BITS = RAS_PTR_BITS+1;

    // Clock and domain reset.
    output wire [$clog2((ISSUE_WIDTH == 2 ? 8 : 4)+5)-1:0] ib_count_o;
    output wire [1:0] frontend_active_o;
    assign frontend_active_o = {predict_slot_valid_r, ic_req_valid_o};
    input wire clk_i;
    input wire rst_n_i;

    // Registered backend recovery; commit wins over the younger branch.
    input wire frontend_flush_i;
    input wire redirect_valid_i;
    input wire [32-1:0] redirect_pc_i;
    input wire branch_redirect_valid_i;
    input wire [TAG_BITS-1:0] branch_redirect_tag_i;
    input wire [32-1:0] branch_redirect_pc_i;
    input wire commit_redirect_valid_i;
    input wire [32-1:0] commit_redirect_pc_i;
    input wire fetch_stop_i;
    input wire [RAS_BITS-1:0] branch_redirect_ras_data_i;
    input wire [RAS_PTR_BITS-1:0] branch_redirect_ras_ptr_i;
    input wire [RAS_COUNT_BITS-1:0] branch_redirect_ras_count_i;
    input wire branch_redirect_ras_pop_i;
    input wire branch_redirect_ras_push_i;
    input wire [32-1:0] branch_redirect_link_i;

    // Issue heads and same-edge registered WB snoops (two physical regions).
    input wire [2-1:0] ib_remove_count_i;
    output wire [4-1:0] ib_credit_o;
    input wire [31:1] lvt_i;
    input wire wb0_valid_i;
    input wire [5-1:0] wb0_rd_i;
    input wire wb1_valid_i;
    input wire [5-1:0] wb1_rd_i;
    input wire wb0_valid_copy_i;
    input wire [4:0] wb0_rd_copy_i;
    input wire wb1_valid_copy_i;
    input wire [4:0] wb1_rd_copy_i;
    output wire ib_head0_valid_o;
    output wire ib_head1_valid_o;
    output wire [32-1:0] ib_head0_pc_o;
    output wire [32-1:0] ib_head0_instr_o;
    output wire ib_head0_error_o;
    output wire [5-1:0] ib_head0_candidates_o;
    output wire ib_head0_predict_taken_o;
    output wire [32-1:0] ib_head0_predict_target_o;
    output wire ib_head0_predict_token_o;
    output wire [3-1:0] ib_head0_predict_provider_o;
    output wire ib_head0_predict_alternate_o;
    output wire [9-1:0] ib_head0_predict_index0_o;
    output wire [9-1:0] ib_head0_predict_index1_o;
    output wire [9-1:0] ib_head0_predict_index2_o;
    output wire [9-1:0] ib_head0_predict_index3_o;
    output wire [10-1:0] ib_head0_predict_tag0_o;
    output wire [10-1:0] ib_head0_predict_tag1_o;
    output wire [10-1:0] ib_head0_predict_tag2_o;
    output wire [10-1:0] ib_head0_predict_tag3_o;
    output wire [12-1:0] ib_head0_predict_base_index_o;
    output wire [12-1:0] ib_head0_predict_fast_index_o;
    output wire [RAS_BITS-1:0] ib_head0_ras_data_o;
    output wire [RAS_PTR_BITS-1:0] ib_head0_ras_ptr_o;
    output wire [RAS_COUNT_BITS-1:0] ib_head0_ras_count_o;
    output wire [32-1:0] ib_head1_pc_o;
    output wire [32-1:0] ib_head1_instr_o;
    output wire ib_head1_error_o;
    output wire [5-1:0] ib_head1_candidates_o;
    output wire ib_head1_predict_taken_o;
    output wire [32-1:0] ib_head1_predict_target_o;
    output wire ib_head1_predict_token_o;
    output wire [3-1:0] ib_head1_predict_provider_o;
    output wire ib_head1_predict_alternate_o;
    output wire [9-1:0] ib_head1_predict_index0_o;
    output wire [9-1:0] ib_head1_predict_index1_o;
    output wire [9-1:0] ib_head1_predict_index2_o;
    output wire [9-1:0] ib_head1_predict_index3_o;
    output wire [10-1:0] ib_head1_predict_tag0_o;
    output wire [10-1:0] ib_head1_predict_tag1_o;
    output wire [10-1:0] ib_head1_predict_tag2_o;
    output wire [10-1:0] ib_head1_predict_tag3_o;
    output wire [12-1:0] ib_head1_predict_base_index_o;
    output wire [12-1:0] ib_head1_predict_fast_index_o;
    output wire [RAS_BITS-1:0] ib_head1_ras_data_o;
    output wire [RAS_PTR_BITS-1:0] ib_head1_ras_ptr_o;
    output wire [RAS_COUNT_BITS-1:0] ib_head1_ras_count_o;

    // Ordered I$ groups: bank0 even, bank1 odd, before instruction parity selection.
    output wire ic_req_valid_o;
    input wire ic_req_ready_i;
    output wire [32-1:0] ic_req_addr_o;
    input wire ic_resp_valid_i;
    output wire ic_resp_ready_o;
    output wire ic_cancel_o;
    // Registered correction event for top-level trace (stage=1, unallocated tag=0).
    output wire f2_redirect_valid_o;
    output wire [31:0] f2_redirect_pc_o;
    output wire [31:0] f2_redirect_target_o;
    output wire [1:0] f2_redirect_cause_o;
    input wire [32-1:0] ic_resp_bank0_way0_instr_i;
    input wire [32-1:0] ic_resp_bank0_way1_instr_i;
    input wire [32-1:0] ic_resp_bank1_way0_instr_i;
    input wire [32-1:0] ic_resp_bank1_way1_instr_i;
    input wire [2-1:0] ic_resp_bank0_way_hit_i;
    input wire ic_resp_bank0_error_i;
    input wire [2-1:0] ic_resp_bank1_way_hit_i;
    input wire ic_resp_bank1_error_i;

    // Actual conditional issue with an F1 token; D pre-read is associated by completion tag.
    input wire predict_read0_valid_i;
    input wire [TAG_BITS-1:0] predict_read0_tag_i;
    input wire [9-1:0] predict_read0_index0_i;
    input wire [9-1:0] predict_read0_index1_i;
    input wire [9-1:0] predict_read0_index2_i;
    input wire [9-1:0] predict_read0_index3_i;
    input wire [10-1:0] predict_read0_tag0_i;
    input wire [10-1:0] predict_read0_tag1_i;
    input wire [10-1:0] predict_read0_tag2_i;
    input wire [10-1:0] predict_read0_tag3_i;
    input wire [12-1:0] predict_read0_base_index_i;
    input wire predict_read1_valid_i;
    input wire [TAG_BITS-1:0] predict_read1_tag_i;
    input wire [9-1:0] predict_read1_index0_i;
    input wire [9-1:0] predict_read1_index1_i;
    input wire [9-1:0] predict_read1_index2_i;
    input wire [9-1:0] predict_read1_index3_i;
    input wire [10-1:0] predict_read1_tag0_i;
    input wire [10-1:0] predict_read1_tag1_i;
    input wire [10-1:0] predict_read1_tag2_i;
    input wire [10-1:0] predict_read1_tag3_i;
    input wire [12-1:0] predict_read1_base_index_i;

    // Registered clean EX/MEM resolutions; the original prediction snapshots remain unchanged.
    input wire ex_predict_train_valid_i;
    input wire [TAG_BITS-1:0] ex_predict_train_tag_i;
    input wire [32-1:0] ex_predict_train_pc_i;
    input wire ex_predict_train_taken_i;
    input wire [32-1:0] ex_predict_train_target_i;
    input wire [3-1:0] ex_predict_train_type_i;
    input wire [12-1:0] ex_predict_train_fast_index_i;
    input wire ex_predict_train_token_i;
    input wire [3-1:0] ex_predict_train_provider_i;
    input wire ex_predict_train_prediction_i;
    input wire ex_predict_train_alternate_i;
    input wire [9-1:0] ex_predict_train_index0_i;
    input wire [9-1:0] ex_predict_train_index1_i;
    input wire [9-1:0] ex_predict_train_index2_i;
    input wire [9-1:0] ex_predict_train_index3_i;
    input wire [10-1:0] ex_predict_train_tag0_i;
    input wire [10-1:0] ex_predict_train_tag1_i;
    input wire [10-1:0] ex_predict_train_tag2_i;
    input wire [10-1:0] ex_predict_train_tag3_i;
    input wire [12-1:0] ex_predict_train_base_index_i;
    input wire mem_predict_train_valid_i;
    input wire [TAG_BITS-1:0] mem_predict_train_tag_i;
    input wire [32-1:0] mem_predict_train_pc_i;
    input wire mem_predict_train_taken_i;
    input wire [32-1:0] mem_predict_train_target_i;
    input wire [3-1:0] mem_predict_train_type_i;
    input wire [12-1:0] mem_predict_train_fast_index_i;
    input wire mem_predict_train_token_i;
    input wire [3-1:0] mem_predict_train_provider_i;
    input wire mem_predict_train_prediction_i;
    input wire mem_predict_train_alternate_i;
    input wire [9-1:0] mem_predict_train_index0_i;
    input wire [9-1:0] mem_predict_train_index1_i;
    input wire [9-1:0] mem_predict_train_index2_i;
    input wire [9-1:0] mem_predict_train_index3_i;
    input wire [10-1:0] mem_predict_train_tag0_i;
    input wire [10-1:0] mem_predict_train_tag1_i;
    input wire [10-1:0] mem_predict_train_tag2_i;
    input wire [10-1:0] mem_predict_train_tag3_i;
    input wire [12-1:0] mem_predict_train_base_index_i;

    // Shared modulo-tag age and inclusive same-edge cancellation.
    input wire [TAG_BITS-1:0] age_head_i;
    input wire cancel_valid_i;
    input wire [TAG_BITS-1:0] cancel_tag_i;

    reg [31:0] pc_r;
    reg head_r;
    reg tail_r;
    reg [1:0] contexts_r;
    reg predict_slot_r;
    reg predict_slot_valid_r;
    reg correction_r;
    reg [1:0] correction_cause_r;
    wire [31:0] correction_source_pc_r;
    wire correction_needed_w;
    reg clear0_valid_r;
    reg clear1_valid_r;
    wire [31:0] clear0_pc_r;
    wire [31:0] clear1_pc_r;
    wire word0_control_w;
    wire word1_control_w;
    wire context0_raw_taken_w;
    wire context1_raw_taken_w;
    wire [31:0] correction_pc_r;
    wire [RAS_BITS-1:0] correction_ras_data_r;
    reg [RAS_PTR_BITS-1:0] correction_ras_ptr_r;
    reg [RAS_COUNT_BITS-1:0] correction_ras_count_r;
    reg correction_pop_r;
    reg correction_push_r;
    wire [31:0] correction_link_r;
    wire flush_w;
    wire request_w;
    wire response_w;
    wire [31:0] query_pc_w;
    wire [31:0] sequential_pc_w;
    wire [31:0] fast_next_pc_w;
    wire [31:0] final_next_pc_w;
    wire [3:0] credit_w;
    wire push_valid_w;
    wire push_ready_w;
    wire [1:0] push_count_w;
    wire fetch_ready_w;
    wire fetch_response_w;
    wire query_skip_w;
    wire ras_restore_valid_w;
    wire [RAS_BITS-1:0] ras_restore_data_w;
    wire [RAS_PTR_BITS-1:0] ras_restore_ptr_w;
    wire [RAS_COUNT_BITS-1:0] ras_restore_count_w;
    wire ras_restore_pop_w;
    wire ras_restore_push_w;
    wire [31:0] ras_restore_link_w;
    wire [1-1:0] fast0_hit_w;
    wire [1-1:0] fast0_taken_w;
    wire [32-1:0] fast0_target_w;
    wire [3-1:0] fast0_type_w;
    wire [12-1:0] fast0_fast_index_w;
    wire [RAS_BITS-1:0] fast0_ras_data_w;
    wire [RAS_PTR_BITS-1:0] fast0_ras_ptr_w;
    wire [RAS_COUNT_BITS-1:0] fast0_ras_count_w;
    wire [1-1:0] fast1_hit_w;
    wire [1-1:0] fast1_taken_w;
    wire [32-1:0] fast1_target_w;
    wire [3-1:0] fast1_type_w;
    wire [12-1:0] fast1_fast_index_w;
    wire [RAS_BITS-1:0] fast1_ras_data_w;
    wire [RAS_PTR_BITS-1:0] fast1_ras_ptr_w;
    wire [RAS_COUNT_BITS-1:0] fast1_ras_count_w;
    wire tage_valid_w;
    wire [1:0] tage_prediction_w;
    wire [1:0] tage_alternate_w;
    wire [5:0] tage_provider_w;
    wire [71:0] tage_indices_w;
    wire [79:0] tage_tags_w;
    wire [23:0] tage_base_w;
    wire [2*32-1:0] saved_base_pc_w;
    wire [32-1:0] context_base_pc_w;
    wire [2*1-1:0] saved_skip_w;
    wire [1-1:0] context_skip_w;
    wire [2*32-1:0] saved_fast_next_w;
    wire [32-1:0] context_fast_next_w;
    wire [2*1-1:0] saved_0_hit_w;
    wire [1-1:0] context_0_hit_w;
    wire [2*1-1:0] saved_0_taken_w;
    wire [1-1:0] context_0_taken_w;
    wire [2*32-1:0] saved_0_target_w;
    wire [32-1:0] context_0_target_w;
    wire [2*3-1:0] saved_0_type_w;
    wire [3-1:0] context_0_type_w;
    wire [2*12-1:0] saved_0_fast_index_w;
    wire [12-1:0] context_0_fast_index_w;
    wire [2*RAS_BITS-1:0] saved_0_ras_data_w;
    wire [RAS_BITS-1:0] context_0_ras_data_w;
    wire [2*RAS_PTR_BITS-1:0] saved_0_ras_ptr_w;
    wire [RAS_PTR_BITS-1:0] context_0_ras_ptr_w;
    wire [2*RAS_COUNT_BITS-1:0] saved_0_ras_count_w;
    wire [RAS_COUNT_BITS-1:0] context_0_ras_count_w;
    wire [2*1-1:0] saved_0_tage_prediction_w;
    wire [1-1:0] context_0_tage_prediction_w;
    wire [2*1-1:0] saved_0_tage_alternate_w;
    wire [1-1:0] context_0_tage_alternate_w;
    wire [2*3-1:0] saved_0_tage_provider_w;
    wire [3-1:0] context_0_tage_provider_w;
    wire [2*36-1:0] saved_0_tage_indices_w;
    wire [36-1:0] context_0_tage_indices_w;
    wire [2*40-1:0] saved_0_tage_tags_w;
    wire [40-1:0] context_0_tage_tags_w;
    wire [2*12-1:0] saved_0_tage_base_w;
    wire [12-1:0] context_0_tage_base_w;
    wire [2*1-1:0] saved_1_hit_w;
    wire [1-1:0] context_1_hit_w;
    wire [2*1-1:0] saved_1_taken_w;
    wire [1-1:0] context_1_taken_w;
    wire [2*32-1:0] saved_1_target_w;
    wire [32-1:0] context_1_target_w;
    wire [2*3-1:0] saved_1_type_w;
    wire [3-1:0] context_1_type_w;
    wire [2*12-1:0] saved_1_fast_index_w;
    wire [12-1:0] context_1_fast_index_w;
    wire [2*1-1:0] saved_1_tage_prediction_w;
    wire [1-1:0] context_1_tage_prediction_w;
    wire [2*1-1:0] saved_1_tage_alternate_w;
    wire [1-1:0] context_1_tage_alternate_w;
    wire [2*3-1:0] saved_1_tage_provider_w;
    wire [3-1:0] context_1_tage_provider_w;
    wire [2*36-1:0] saved_1_tage_indices_w;
    wire [36-1:0] context_1_tage_indices_w;
    wire [2*40-1:0] saved_1_tage_tags_w;
    wire [40-1:0] context_1_tage_tags_w;
    wire [2*12-1:0] saved_1_tage_base_w;
    wire [12-1:0] context_1_tage_base_w;
    genvar slot;
    wire [32-1:0] context0_pc_w;
    wire [1-1:0] context0_predict_taken_w;
    wire [32-1:0] context0_predict_target_w;
    wire [1-1:0] context0_predict_token_w;
    wire [3-1:0] context0_predict_provider_w;
    wire [1-1:0] context0_predict_alternate_w;
    wire [9-1:0] context0_predict_index0_w;
    wire [9-1:0] context0_predict_index1_w;
    wire [9-1:0] context0_predict_index2_w;
    wire [9-1:0] context0_predict_index3_w;
    wire [10-1:0] context0_predict_tag0_w;
    wire [10-1:0] context0_predict_tag1_w;
    wire [10-1:0] context0_predict_tag2_w;
    wire [10-1:0] context0_predict_tag3_w;
    wire [12-1:0] context0_predict_base_index_w;
    wire [12-1:0] context0_predict_fast_index_w;
    wire [RAS_BITS-1:0] context0_ras_data_w;
    wire [RAS_PTR_BITS-1:0] context0_ras_ptr_w;
    wire [RAS_COUNT_BITS-1:0] context0_ras_count_w;
    wire [1-1:0] current0_prediction_w;
    wire [1-1:0] current0_alternate_w;
    wire [3-1:0] current0_provider_w;
    wire [36-1:0] current0_indices_w;
    wire [40-1:0] current0_tags_w;
    wire [12-1:0] current0_base_w;
    wire [32-1:0] context1_pc_w;
    wire [1-1:0] context1_predict_taken_w;
    wire [32-1:0] context1_predict_target_w;
    wire [1-1:0] context1_predict_token_w;
    wire [3-1:0] context1_predict_provider_w;
    wire [1-1:0] context1_predict_alternate_w;
    wire [9-1:0] context1_predict_index0_w;
    wire [9-1:0] context1_predict_index1_w;
    wire [9-1:0] context1_predict_index2_w;
    wire [9-1:0] context1_predict_index3_w;
    wire [10-1:0] context1_predict_tag0_w;
    wire [10-1:0] context1_predict_tag1_w;
    wire [10-1:0] context1_predict_tag2_w;
    wire [10-1:0] context1_predict_tag3_w;
    wire [12-1:0] context1_predict_base_index_w;
    wire [12-1:0] context1_predict_fast_index_w;
    wire [RAS_BITS-1:0] context1_ras_data_w;
    wire [RAS_PTR_BITS-1:0] context1_ras_ptr_w;
    wire [RAS_COUNT_BITS-1:0] context1_ras_count_w;
    wire [1-1:0] current1_prediction_w;
    wire [1-1:0] current1_alternate_w;
    wire [3-1:0] current1_provider_w;
    wire [36-1:0] current1_indices_w;
    wire [40-1:0] current1_tags_w;
    wire [12-1:0] current1_base_w;
    wire [31:0] context_ras_top_w;
    wire [31:0] fast0_ras_top_w;
    wire [63:0] saved_ras_top_w;
    wire oldest_taken_w;
    wire youngest_taken_w;
    wire [1:0] context_count_w;
    wire final_taken_w;
    wire [2:0] final_type_w;
    wire [31:0] final_pc_w;
    wire final_pop_w;
    wire final_push_w;
    wire [31:0] final_link_w;
    wire [32-1:0] push0_pc_w;
    wire [32-1:0] push0_instr_w;
    wire [1-1:0] push0_error_w;
    wire [5-1:0] push0_candidates_w;
    wire [1-1:0] push0_predict_taken_w;
    wire [32-1:0] push0_predict_target_w;
    wire [1-1:0] push0_predict_token_w;
    wire [3-1:0] push0_predict_provider_w;
    wire [1-1:0] push0_predict_alternate_w;
    wire [9-1:0] push0_predict_index0_w;
    wire [9-1:0] push0_predict_index1_w;
    wire [9-1:0] push0_predict_index2_w;
    wire [9-1:0] push0_predict_index3_w;
    wire [10-1:0] push0_predict_tag0_w;
    wire [10-1:0] push0_predict_tag1_w;
    wire [10-1:0] push0_predict_tag2_w;
    wire [10-1:0] push0_predict_tag3_w;
    wire [12-1:0] push0_predict_base_index_w;
    wire [12-1:0] push0_predict_fast_index_w;
    wire [RAS_BITS-1:0] push0_ras_data_w;
    wire [RAS_PTR_BITS-1:0] push0_ras_ptr_w;
    wire [RAS_COUNT_BITS-1:0] push0_ras_count_w;
    wire [32-1:0] push1_pc_w;
    wire [32-1:0] push1_instr_w;
    wire [1-1:0] push1_error_w;
    wire [5-1:0] push1_candidates_w;
    wire [1-1:0] push1_predict_taken_w;
    wire [32-1:0] push1_predict_target_w;
    wire [1-1:0] push1_predict_token_w;
    wire [3-1:0] push1_predict_provider_w;
    wire [1-1:0] push1_predict_alternate_w;
    wire [9-1:0] push1_predict_index0_w;
    wire [9-1:0] push1_predict_index1_w;
    wire [9-1:0] push1_predict_index2_w;
    wire [9-1:0] push1_predict_index3_w;
    wire [10-1:0] push1_predict_tag0_w;
    wire [10-1:0] push1_predict_tag1_w;
    wire [10-1:0] push1_predict_tag2_w;
    wire [10-1:0] push1_predict_tag3_w;
    wire [12-1:0] push1_predict_base_index_w;
    wire [12-1:0] push1_predict_fast_index_w;
    wire [RAS_BITS-1:0] push1_ras_data_w;
    wire [RAS_PTR_BITS-1:0] push1_ras_ptr_w;
    wire [RAS_COUNT_BITS-1:0] push1_ras_count_w;
    wire unused_w;
    wire [32-1:0] correction_source_pc_capture_w;
    genvar correction_source_pc_part;
    wire [32-1:0] clear0_pc_capture_w;
    genvar clear0_pc_part;
    wire [32-1:0] clear1_pc_capture_w;
    genvar clear1_pc_part;
    wire [32-1:0] correction_pc_capture_w;
    genvar correction_pc_part;
    wire [RAS_BITS-1:0] correction_ras_data_capture_w;
    genvar correction_ras_data_part;
    wire [32-1:0] correction_link_capture_w;
    genvar correction_link_part;





    assign flush_w = frontend_flush_i || redirect_valid_i ||
        commit_redirect_valid_i || branch_redirect_valid_i;
    // Registered recovery targets can start F1 while old contexts are canceled.
    wire recovery_valid_w = commit_redirect_valid_i || redirect_valid_i ||
        branch_redirect_valid_i || (!frontend_flush_i && correction_r);
    wire recovery_w = flush_w || correction_r;
    wire [31:0] recovery_pc_w = commit_redirect_valid_i ? commit_redirect_pc_i :
        redirect_valid_i ? redirect_pc_i : branch_redirect_valid_i ?
        branch_redirect_pc_i : correction_r ? correction_pc_r : pc_r;
    wire [31:0] request_pc_w = recovery_valid_w ? recovery_pc_w : pc_r;
    wire request_slot_w = recovery_w ? 1'b0 : tail_r;
    wire redirect_request_w = commit_redirect_valid_i || redirect_valid_i ||
        branch_redirect_valid_i;
    wire correction_request_w = !flush_w && correction_r &&
        (credit_w >= 4'd2 || contexts_r != 0);
    assign query_pc_w = (ISSUE_WIDTH == 2) ? request_pc_w : {request_pc_w[31:3], 3'd0};
    assign query_skip_w = (ISSUE_WIDTH == 1) && request_pc_w[2];
    assign sequential_pc_w = query_pc_w + 32'd8;
    assign ic_req_valid_o = !fetch_stop_i && (redirect_request_w || correction_request_w ||
        (!recovery_w && contexts_r < 2'd2 && credit_w >= 4'd2));
    assign ic_req_addr_o = query_pc_w;
    assign request_w = ic_req_valid_o && ic_req_ready_i;
    assign ic_cancel_o = flush_w || correction_r;
    assign f2_redirect_valid_o = correction_r && !flush_w;
    assign f2_redirect_pc_o = correction_source_pc_r;
    assign f2_redirect_target_o = correction_pc_r;
    assign f2_redirect_cause_o = correction_cause_r;
    // Prefix changes need a correction even when the selected target addresses are equal.
    assign correction_needed_w = (!context_skip_w &&
        context0_predict_taken_w != context_0_taken_w) ||
        (youngest_taken_w != (context_1_taken_w && !context_0_taken_w)) ||
        final_next_pc_w != context_fast_next_w;
    assign ib_credit_o = credit_w;
    assign response_w = ic_resp_valid_i && ic_resp_ready_o;
    assign fetch_response_w = ic_resp_valid_i && !flush_w && !correction_r;
    assign ic_resp_ready_o = fetch_ready_w && !flush_w && !correction_r;
    always @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            pc_r <= 32'd0;
            head_r <= 1'b0;
            tail_r <= 1'b0;
            contexts_r <= 2'd0;
            predict_slot_valid_r <= 1'b0;
            correction_r <= 1'b0;
            clear0_valid_r <= 1'b0;
            clear1_valid_r <= 1'b0;
        end else begin
            correction_r <= response_w && correction_needed_w;
            clear0_valid_r <= response_w && !context_skip_w && context_0_hit_w &&
                !word0_control_w && context0_raw_taken_w;
            clear1_valid_r <= response_w && !oldest_taken_w && context_1_hit_w &&
                !word1_control_w && context1_raw_taken_w;
            predict_slot_valid_r <= request_w;
            // Direct next-pointer equations avoid a recovery-dependent FF enable chain.
            head_r <= !recovery_w && (head_r ^ response_w);
            tail_r <= request_w ^ (tail_r && !recovery_w);
            if (recovery_w) begin
                contexts_r <= {1'b0, request_w};
                predict_slot_valid_r <= request_w;
                correction_r <= 1'b0;
                pc_r <= request_w ? fast_next_pc_w : recovery_pc_w;
            end else begin
                if (request_w) begin
                    pc_r <= fast_next_pc_w;
                end
                // Precompute count +/- 1 from registered state, keeping recovery off the carry.
                case({request_w, response_w})
                    2'b10: contexts_r <= contexts_r + 2'd1;
                    2'b01: contexts_r <= contexts_r - 2'd1;
                    default: contexts_r <= contexts_r;
                endcase
            end
        end
    end
    always @(posedge clk_i) begin
        predict_slot_r <= request_slot_w;
        if (response_w) begin
            correction_cause_r <= (context0_raw_taken_w && !word0_control_w && !context_skip_w) ||
                (context1_raw_taken_w && !word1_control_w && !oldest_taken_w) ? 2'd3 : 2'd1;
            correction_ras_ptr_r <= context0_ras_ptr_w;
            correction_ras_count_r <= context0_ras_count_w;
            correction_pop_r <= final_pop_w;
            correction_push_r <= final_push_w;
        end
    end
    // Each retained correction payload slice has at most sixteen data-enable leaves.
    assign correction_source_pc_capture_w = !context_skip_w &&
                context0_predict_taken_w != context_0_taken_w ? context0_pc_w : context1_pc_w;
    generate
        for (correction_source_pc_part = 0; correction_source_pc_part < (32+15)/16;
            correction_source_pc_part = correction_source_pc_part + 1) begin :
                g_correction_source_pc_slice
            localparam WIDTH = (32-16*correction_source_pc_part < 16) ?
                32-16*correction_source_pc_part : 16;
            reg [WIDTH-1:0] data_r;
            always @(posedge clk_i) begin
                if (response_w)
                    data_r <= correction_source_pc_capture_w[16*correction_source_pc_part +: WIDTH];
            end
            assign correction_source_pc_r[16*correction_source_pc_part +: WIDTH] = data_r;
        end
    endgenerate
    assign clear0_pc_capture_w = context0_pc_w;
    generate
        for (clear0_pc_part = 0; clear0_pc_part < (32+15)/16;
            clear0_pc_part = clear0_pc_part + 1) begin : g_clear0_pc_slice
            localparam WIDTH = (32-16*clear0_pc_part < 16) ?
                32-16*clear0_pc_part : 16;
            reg [WIDTH-1:0] data_r;
            always @(posedge clk_i) begin
                if (response_w)
                    data_r <= clear0_pc_capture_w[16*clear0_pc_part +: WIDTH];
            end
            assign clear0_pc_r[16*clear0_pc_part +: WIDTH] = data_r;
        end
    endgenerate
    assign clear1_pc_capture_w = context1_pc_w;
    generate
        for (clear1_pc_part = 0; clear1_pc_part < (32+15)/16;
            clear1_pc_part = clear1_pc_part + 1) begin : g_clear1_pc_slice
            localparam WIDTH = (32-16*clear1_pc_part < 16) ?
                32-16*clear1_pc_part : 16;
            reg [WIDTH-1:0] data_r;
            always @(posedge clk_i) begin
                if (response_w)
                    data_r <= clear1_pc_capture_w[16*clear1_pc_part +: WIDTH];
            end
            assign clear1_pc_r[16*clear1_pc_part +: WIDTH] = data_r;
        end
    endgenerate
    assign correction_pc_capture_w = final_next_pc_w;
    generate
        for (correction_pc_part = 0; correction_pc_part < (32+15)/16;
            correction_pc_part = correction_pc_part + 1) begin : g_correction_pc_slice
            localparam WIDTH = (32-16*correction_pc_part < 16) ?
                32-16*correction_pc_part : 16;
            reg [WIDTH-1:0] data_r;
            always @(posedge clk_i) begin
                if (response_w)
                    data_r <= correction_pc_capture_w[16*correction_pc_part +: WIDTH];
            end
            assign correction_pc_r[16*correction_pc_part +: WIDTH] = data_r;
        end
    endgenerate
    assign correction_ras_data_capture_w = context0_ras_data_w;
    generate
        for (correction_ras_data_part = 0; correction_ras_data_part < (RAS_BITS+15)/16;
            correction_ras_data_part = correction_ras_data_part + 1) begin :
                g_correction_ras_data_slice
            localparam WIDTH = (RAS_BITS-16*correction_ras_data_part < 16) ?
                RAS_BITS-16*correction_ras_data_part : 16;
            reg [WIDTH-1:0] data_r;
            always @(posedge clk_i) begin
                if (response_w)
                    data_r <= correction_ras_data_capture_w[16*correction_ras_data_part +: WIDTH];
            end
            assign correction_ras_data_r[16*correction_ras_data_part +: WIDTH] = data_r;
        end
    endgenerate
    assign correction_link_capture_w = final_link_w;
    generate
        for (correction_link_part = 0; correction_link_part < (32+15)/16;
            correction_link_part = correction_link_part + 1) begin : g_correction_link_slice
            localparam WIDTH = (32-16*correction_link_part < 16) ?
                32-16*correction_link_part : 16;
            reg [WIDTH-1:0] data_r;
            always @(posedge clk_i) begin
                if (response_w)
                    data_r <= correction_link_capture_w[16*correction_link_part +: WIDTH];
            end
            assign correction_link_r[16*correction_link_part +: WIDTH] = data_r;
        end
    endgenerate
    assign ras_restore_valid_w = branch_redirect_valid_i && !commit_redirect_valid_i ||
        correction_r && !flush_w;
    assign ras_restore_data_w = branch_redirect_valid_i ?
        branch_redirect_ras_data_i : correction_ras_data_r;
    assign ras_restore_ptr_w = branch_redirect_valid_i ?
        branch_redirect_ras_ptr_i : correction_ras_ptr_r;
    assign ras_restore_count_w = branch_redirect_valid_i ?
        branch_redirect_ras_count_i : correction_ras_count_r;
    assign ras_restore_pop_w = branch_redirect_valid_i ?
        branch_redirect_ras_pop_i : correction_pop_r;
    assign ras_restore_push_w = branch_redirect_valid_i ?
        branch_redirect_ras_push_i : correction_push_r;
    assign ras_restore_link_w = branch_redirect_valid_i ? branch_redirect_link_i :
        correction_link_r;
    edrv32_cpu2_predictor #(
        .ISSUE_WIDTH(ISSUE_WIDTH),
        .FPU_FORMAT(FPU_FORMAT)
    ) u_predictor (
        .clk_i(clk_i),
        .rst_n_i(rst_n_i),
        .predict_req_valid_i(request_w),
        .predict_req_pc_i(query_pc_w),
        .query_skip0_i(query_skip_w),
        .clear0_valid_i(clear0_valid_r),
        .clear0_pc_i(clear0_pc_r),
        .clear1_valid_i(clear1_valid_r),
        .clear1_pc_i(clear1_pc_r),
        .fast0_hit_o(fast0_hit_w),
        .fast0_taken_o(fast0_taken_w),
        .fast0_target_o(fast0_target_w),
        .fast0_type_o(fast0_type_w),
        .fast0_fast_index_o(fast0_fast_index_w),
        .fast0_ras_data_o(fast0_ras_data_w),
        .fast0_ras_ptr_o(fast0_ras_ptr_w),
        .fast0_ras_count_o(fast0_ras_count_w),
        .fast0_ras_top_o(fast0_ras_top_w),
        .fast1_hit_o(fast1_hit_w),
        .fast1_taken_o(fast1_taken_w),
        .fast1_target_o(fast1_target_w),
        .fast1_type_o(fast1_type_w),
        .fast1_fast_index_o(fast1_fast_index_w),
        .fast1_ras_data_o(fast1_ras_data_w),
        .fast1_ras_ptr_o(fast1_ras_ptr_w),
        .fast1_ras_count_o(fast1_ras_count_w),
        .ras_restore_valid_i(ras_restore_valid_w),
        .ras_restore_data_i(ras_restore_data_w),
        .ras_restore_ptr_i(ras_restore_ptr_w),
        .ras_restore_count_i(ras_restore_count_w),
        .ras_restore_pop_i(ras_restore_pop_w),
        .ras_restore_push_i(ras_restore_push_w),
        .ras_restore_link_i(ras_restore_link_w),
        .ex_predict_train_valid_i(ex_predict_train_valid_i),
        .ex_predict_train_tag_i(ex_predict_train_tag_i),
        .ex_predict_train_pc_i(ex_predict_train_pc_i),
        .ex_predict_train_taken_i(ex_predict_train_taken_i),
        .ex_predict_train_target_i(ex_predict_train_target_i),
        .ex_predict_train_type_i(ex_predict_train_type_i),
        .ex_predict_train_fast_index_i(ex_predict_train_fast_index_i),
        .mem_predict_train_valid_i(mem_predict_train_valid_i),
        .mem_predict_train_tag_i(mem_predict_train_tag_i),
        .mem_predict_train_pc_i(mem_predict_train_pc_i),
        .mem_predict_train_taken_i(mem_predict_train_taken_i),
        .mem_predict_train_target_i(mem_predict_train_target_i),
        .mem_predict_train_type_i(mem_predict_train_type_i),
        .mem_predict_train_fast_index_i(mem_predict_train_fast_index_i),
        .age_head_i(age_head_i),
        .cancel_valid_i(cancel_valid_i),
        .cancel_tag_i(cancel_tag_i)
    );
    assign fast_next_pc_w = fast0_taken_w ? fast0_target_w :
        fast1_taken_w ? fast1_target_w : sequential_pc_w;
    generate
        if (ISSUE_WIDTH == 2) begin : g_tage
            edrv32_cpu2_tage #(
                .ISSUE_WIDTH(ISSUE_WIDTH),
                .FPU_FORMAT(FPU_FORMAT)
            ) u_tage (
                .clk_i(clk_i),
                .rst_n_i(rst_n_i),
                .f1_valid_i(request_w),
                .f1_pc_i(query_pc_w),
                .f2_valid_o(tage_valid_w),
                .f2_prediction_o(tage_prediction_w),
                .f2_alternate_o(tage_alternate_w),
                .f2_provider_o(tage_provider_w),
                .f2_indices_o(tage_indices_w),
                .f2_tags_o(tage_tags_w),
                .f2_base_indices_o(tage_base_w),
                .predict_read0_valid_i(predict_read0_valid_i),
                .predict_read0_tag_i(predict_read0_tag_i),
                .predict_read0_index0_i(predict_read0_index0_i),
                .predict_read0_index1_i(predict_read0_index1_i),
                .predict_read0_index2_i(predict_read0_index2_i),
                .predict_read0_index3_i(predict_read0_index3_i),
                .predict_read0_tag0_i(predict_read0_tag0_i),
                .predict_read0_tag1_i(predict_read0_tag1_i),
                .predict_read0_tag2_i(predict_read0_tag2_i),
                .predict_read0_tag3_i(predict_read0_tag3_i),
                .predict_read0_base_index_i(predict_read0_base_index_i),
                .predict_read1_valid_i(predict_read1_valid_i),
                .predict_read1_tag_i(predict_read1_tag_i),
                .predict_read1_index0_i(predict_read1_index0_i),
                .predict_read1_index1_i(predict_read1_index1_i),
                .predict_read1_index2_i(predict_read1_index2_i),
                .predict_read1_index3_i(predict_read1_index3_i),
                .predict_read1_tag0_i(predict_read1_tag0_i),
                .predict_read1_tag1_i(predict_read1_tag1_i),
                .predict_read1_tag2_i(predict_read1_tag2_i),
                .predict_read1_tag3_i(predict_read1_tag3_i),
                .predict_read1_base_index_i(predict_read1_base_index_i),
                .ex_predict_train_valid_i(ex_predict_train_valid_i &&
                    ex_predict_train_type_i == 3'd0),
                .ex_predict_train_tag_i(ex_predict_train_tag_i),
                .ex_predict_train_taken_i(ex_predict_train_taken_i),
                .ex_predict_train_token_i(ex_predict_train_token_i),
                .ex_predict_train_provider_i(ex_predict_train_provider_i),
                .ex_predict_train_prediction_i(ex_predict_train_prediction_i),
                .ex_predict_train_alternate_i(ex_predict_train_alternate_i),
                .ex_predict_train_index0_i(ex_predict_train_index0_i),
                .ex_predict_train_index1_i(ex_predict_train_index1_i),
                .ex_predict_train_index2_i(ex_predict_train_index2_i),
                .ex_predict_train_index3_i(ex_predict_train_index3_i),
                .ex_predict_train_tag0_i(ex_predict_train_tag0_i),
                .ex_predict_train_tag1_i(ex_predict_train_tag1_i),
                .ex_predict_train_tag2_i(ex_predict_train_tag2_i),
                .ex_predict_train_tag3_i(ex_predict_train_tag3_i),
                .ex_predict_train_base_index_i(ex_predict_train_base_index_i),
                .mem_predict_train_valid_i(mem_predict_train_valid_i &&
                    mem_predict_train_type_i == 3'd0),
                .mem_predict_train_tag_i(mem_predict_train_tag_i),
                .mem_predict_train_taken_i(mem_predict_train_taken_i),
                .mem_predict_train_token_i(mem_predict_train_token_i),
                .mem_predict_train_provider_i(mem_predict_train_provider_i),
                .mem_predict_train_prediction_i(mem_predict_train_prediction_i),
                .mem_predict_train_alternate_i(mem_predict_train_alternate_i),
                .mem_predict_train_index0_i(mem_predict_train_index0_i),
                .mem_predict_train_index1_i(mem_predict_train_index1_i),
                .mem_predict_train_index2_i(mem_predict_train_index2_i),
                .mem_predict_train_index3_i(mem_predict_train_index3_i),
                .mem_predict_train_tag0_i(mem_predict_train_tag0_i),
                .mem_predict_train_tag1_i(mem_predict_train_tag1_i),
                .mem_predict_train_tag2_i(mem_predict_train_tag2_i),
                .mem_predict_train_tag3_i(mem_predict_train_tag3_i),
                .mem_predict_train_base_index_i(mem_predict_train_base_index_i),
                .age_head_i(age_head_i),
                .cancel_valid_i(cancel_valid_i),
                .cancel_tag_i(cancel_tag_i)
            );
        end else begin : g_no_tage
            assign tage_valid_w = 1'b0;
            assign tage_prediction_w = 2'd0;
            assign tage_alternate_w = 2'd0;
            assign tage_provider_w = 6'd0;
            assign tage_indices_w = 72'd0;
            assign tage_tags_w = 80'd0;
            assign tage_base_w = 24'd0;
        end
    endgenerate
    assign context_base_pc_w = head_r ? saved_base_pc_w[32 +: 32] : saved_base_pc_w[0 +: 32];
    assign context_skip_w = head_r ? saved_skip_w[1 +: 1] : saved_skip_w[0 +: 1];
    assign context_fast_next_w = head_r ? saved_fast_next_w[32 +: 32] : saved_fast_next_w[0 +: 32];
    assign context_0_hit_w = head_r ? saved_0_hit_w[1 +: 1] : saved_0_hit_w[0 +: 1];
    assign context_0_taken_w = head_r ? saved_0_taken_w[1 +: 1] : saved_0_taken_w[0 +: 1];
    assign context_0_target_w = head_r ? saved_0_target_w[32 +: 32] : saved_0_target_w[0 +: 32];
    assign context_0_type_w = head_r ? saved_0_type_w[3 +: 3] : saved_0_type_w[0 +: 3];
    assign context_0_fast_index_w = head_r ? saved_0_fast_index_w[12 +: 12] :
        saved_0_fast_index_w[0 +: 12];
    assign context_0_ras_data_w = head_r ? saved_0_ras_data_w[RAS_BITS +: RAS_BITS] :
        saved_0_ras_data_w[0 +: RAS_BITS];
    assign context_0_ras_ptr_w = head_r ? saved_0_ras_ptr_w[RAS_PTR_BITS +: RAS_PTR_BITS] :
        saved_0_ras_ptr_w[0 +: RAS_PTR_BITS];
    assign context_0_ras_count_w = head_r ? saved_0_ras_count_w[RAS_COUNT_BITS +:
        RAS_COUNT_BITS] : saved_0_ras_count_w[0 +: RAS_COUNT_BITS];
    assign context_0_tage_prediction_w = head_r ? saved_0_tage_prediction_w[1 +: 1] :
        saved_0_tage_prediction_w[0 +: 1];
    assign context_0_tage_alternate_w = head_r ? saved_0_tage_alternate_w[1 +: 1] :
        saved_0_tage_alternate_w[0 +: 1];
    assign context_0_tage_provider_w = head_r ? saved_0_tage_provider_w[3 +: 3] :
        saved_0_tage_provider_w[0 +: 3];
    assign context_0_tage_indices_w = head_r ? saved_0_tage_indices_w[36 +: 36] :
        saved_0_tage_indices_w[0 +: 36];
    assign context_0_tage_tags_w = head_r ? saved_0_tage_tags_w[40 +: 40] :
        saved_0_tage_tags_w[0 +: 40];
    assign context_0_tage_base_w = head_r ? saved_0_tage_base_w[12 +: 12] :
        saved_0_tage_base_w[0 +: 12];
    assign context_1_hit_w = head_r ? saved_1_hit_w[1 +: 1] : saved_1_hit_w[0 +: 1];
    assign context_1_taken_w = head_r ? saved_1_taken_w[1 +: 1] : saved_1_taken_w[0 +: 1];
    assign context_1_target_w = head_r ? saved_1_target_w[32 +: 32] : saved_1_target_w[0 +: 32];
    assign context_1_type_w = head_r ? saved_1_type_w[3 +: 3] : saved_1_type_w[0 +: 3];
    assign context_1_fast_index_w = head_r ? saved_1_fast_index_w[12 +: 12] :
        saved_1_fast_index_w[0 +: 12];
    assign context_1_tage_prediction_w = head_r ? saved_1_tage_prediction_w[1 +: 1] :
        saved_1_tage_prediction_w[0 +: 1];
    assign context_1_tage_alternate_w = head_r ? saved_1_tage_alternate_w[1 +: 1] :
        saved_1_tage_alternate_w[0 +: 1];
    assign context_1_tage_provider_w = head_r ? saved_1_tage_provider_w[3 +: 3] :
        saved_1_tage_provider_w[0 +: 3];
    assign context_1_tage_indices_w = head_r ? saved_1_tage_indices_w[36 +: 36] :
        saved_1_tage_indices_w[0 +: 36];
    assign context_1_tage_tags_w = head_r ? saved_1_tage_tags_w[40 +: 40] :
        saved_1_tage_tags_w[0 +: 40];
    assign context_1_tage_base_w = head_r ? saved_1_tage_base_w[12 +: 12] :
        saved_1_tage_base_w[0 +: 12];
    generate
        for (slot = 0; slot < 2; slot = slot + 1) begin : g_context
            localparam SLOT = (slot != 0);
            genvar top_half;
            for (top_half = 0; top_half < 2; top_half = top_half + 1) begin : g_ras_top
                reg [15:0] data_r;
                always @(posedge clk_i) begin
                    if (request_w && request_slot_w == SLOT)
                        data_r <= fast0_ras_top_w[16*top_half +: 16];
                end
                assign saved_ras_top_w[32*slot+16*top_half +: 16] = data_r;
            end

            wire [32-1:0] base_pc_r;
            wire [32-1:0] base_pc_capture_w;
            assign base_pc_capture_w = query_pc_w;
            genvar base_pc_part;
            for (base_pc_part = 0; base_pc_part < (32+15)/16;
                base_pc_part = base_pc_part + 1) begin : g_base_pc_slice
                localparam WIDTH = (32-16*base_pc_part < 16) ?
                    32-16*base_pc_part : 16;
                reg [WIDTH-1:0] data_r;
                always @(posedge clk_i) begin
                    if (request_w && request_slot_w == SLOT)
                        data_r <= base_pc_capture_w[16*base_pc_part +: WIDTH];
                end
                assign base_pc_r[16*base_pc_part +: WIDTH] = data_r;
            end
            assign saved_base_pc_w[32*slot +: 32] = base_pc_r;
            reg [1-1:0] skip_r;
            always @(posedge clk_i) begin
                if (request_w && request_slot_w == SLOT)
                    skip_r <= query_skip_w;
            end
            assign saved_skip_w[1*slot +: 1] = skip_r;
            wire [32-1:0] fast_next_r;
            wire [32-1:0] fast_next_capture_w;
            assign fast_next_capture_w = fast_next_pc_w;
            genvar fast_next_part;
            for (fast_next_part = 0; fast_next_part < (32+15)/16;
                fast_next_part = fast_next_part + 1) begin : g_fast_next_slice
                localparam WIDTH = (32-16*fast_next_part < 16) ?
                    32-16*fast_next_part : 16;
                reg [WIDTH-1:0] data_r;
                always @(posedge clk_i) begin
                    if (request_w && request_slot_w == SLOT)
                        data_r <= fast_next_capture_w[16*fast_next_part +: WIDTH];
                end
                assign fast_next_r[16*fast_next_part +: WIDTH] = data_r;
            end
            assign saved_fast_next_w[32*slot +: 32] = fast_next_r;
            reg [1-1:0] word0_hit_r;
            always @(posedge clk_i) begin
                if (request_w && request_slot_w == SLOT)
                    word0_hit_r <= fast0_hit_w;
            end
            assign saved_0_hit_w[1*slot +: 1] = word0_hit_r;
            reg [1-1:0] word0_taken_r;
            always @(posedge clk_i) begin
                if (request_w && request_slot_w == SLOT)
                    word0_taken_r <= fast0_taken_w;
            end
            assign saved_0_taken_w[1*slot +: 1] = word0_taken_r;
            wire [32-1:0] word0_target_r;
            wire [32-1:0] word0_target_capture_w;
            assign word0_target_capture_w = fast0_target_w;
            genvar word0_target_part;
            for (word0_target_part = 0; word0_target_part < (32+15)/16;
                word0_target_part = word0_target_part + 1) begin : g_word0_target_slice
                localparam WIDTH = (32-16*word0_target_part < 16) ?
                    32-16*word0_target_part : 16;
                reg [WIDTH-1:0] data_r;
                always @(posedge clk_i) begin
                    if (request_w && request_slot_w == SLOT)
                        data_r <= word0_target_capture_w[16*word0_target_part +: WIDTH];
                end
                assign word0_target_r[16*word0_target_part +: WIDTH] = data_r;
            end
            assign saved_0_target_w[32*slot +: 32] = word0_target_r;
            reg [3-1:0] word0_type_r;
            always @(posedge clk_i) begin
                if (request_w && request_slot_w == SLOT)
                    word0_type_r <= fast0_type_w;
            end
            assign saved_0_type_w[3*slot +: 3] = word0_type_r;
            reg [12-1:0] word0_fast_index_r;
            always @(posedge clk_i) begin
                if (request_w && request_slot_w == SLOT)
                    word0_fast_index_r <= fast0_fast_index_w;
            end
            assign saved_0_fast_index_w[12*slot +: 12] = word0_fast_index_r;
            wire [RAS_BITS-1:0] word0_ras_data_r;
            wire [RAS_BITS-1:0] word0_ras_data_capture_w;
            assign word0_ras_data_capture_w = fast0_ras_data_w;
            genvar word0_ras_data_part;
            for (word0_ras_data_part = 0; word0_ras_data_part < (RAS_BITS+15)/16;
                word0_ras_data_part = word0_ras_data_part + 1) begin : g_word0_ras_data_slice
                localparam WIDTH = (RAS_BITS-16*word0_ras_data_part < 16) ?
                    RAS_BITS-16*word0_ras_data_part : 16;
                reg [WIDTH-1:0] data_r;
                always @(posedge clk_i) begin
                    if (request_w && request_slot_w == SLOT)
                        data_r <= word0_ras_data_capture_w[16*word0_ras_data_part +: WIDTH];
                end
                assign word0_ras_data_r[16*word0_ras_data_part +: WIDTH] = data_r;
            end
            assign saved_0_ras_data_w[RAS_BITS*slot +: RAS_BITS] = word0_ras_data_r;
            wire [RAS_PTR_BITS-1:0] word0_ras_ptr_r;
            wire [RAS_PTR_BITS-1:0] word0_ras_ptr_capture_w;
            assign word0_ras_ptr_capture_w = fast0_ras_ptr_w;
            genvar word0_ras_ptr_part;
            for (word0_ras_ptr_part = 0; word0_ras_ptr_part < (RAS_PTR_BITS+15)/16;
                word0_ras_ptr_part = word0_ras_ptr_part + 1) begin : g_word0_ras_ptr_slice
                localparam WIDTH = (RAS_PTR_BITS-16*word0_ras_ptr_part < 16) ?
                    RAS_PTR_BITS-16*word0_ras_ptr_part : 16;
                reg [WIDTH-1:0] data_r;
                always @(posedge clk_i) begin
                    if (request_w && request_slot_w == SLOT)
                        data_r <= word0_ras_ptr_capture_w[16*word0_ras_ptr_part +: WIDTH];
                end
                assign word0_ras_ptr_r[16*word0_ras_ptr_part +: WIDTH] = data_r;
            end
            assign saved_0_ras_ptr_w[RAS_PTR_BITS*slot +: RAS_PTR_BITS] = word0_ras_ptr_r;
            wire [RAS_COUNT_BITS-1:0] word0_ras_count_r;
            wire [RAS_COUNT_BITS-1:0] word0_ras_count_capture_w;
            assign word0_ras_count_capture_w = fast0_ras_count_w;
            genvar word0_ras_count_part;
            for (word0_ras_count_part = 0; word0_ras_count_part < (RAS_COUNT_BITS+15)/16;
                word0_ras_count_part = word0_ras_count_part + 1) begin : g_word0_ras_count_slice
                localparam WIDTH = (RAS_COUNT_BITS-16*word0_ras_count_part < 16) ?
                    RAS_COUNT_BITS-16*word0_ras_count_part : 16;
                reg [WIDTH-1:0] data_r;
                always @(posedge clk_i) begin
                    if (request_w && request_slot_w == SLOT)
                        data_r <= word0_ras_count_capture_w[16*word0_ras_count_part +: WIDTH];
                end
                assign word0_ras_count_r[16*word0_ras_count_part +: WIDTH] = data_r;
            end
            assign saved_0_ras_count_w[RAS_COUNT_BITS*slot +: RAS_COUNT_BITS] = word0_ras_count_r;
            reg [1-1:0] word0_tage_prediction_r;
            always @(posedge clk_i) begin
                if (predict_slot_valid_r && predict_slot_r == SLOT)
                    word0_tage_prediction_r <= tage_prediction_w[1*0 +: 1];
            end
            assign saved_0_tage_prediction_w[1*slot +: 1] = word0_tage_prediction_r;
            reg [1-1:0] word0_tage_alternate_r;
            always @(posedge clk_i) begin
                if (predict_slot_valid_r && predict_slot_r == SLOT)
                    word0_tage_alternate_r <= tage_alternate_w[1*0 +: 1];
            end
            assign saved_0_tage_alternate_w[1*slot +: 1] = word0_tage_alternate_r;
            reg [3-1:0] word0_tage_provider_r;
            always @(posedge clk_i) begin
                if (predict_slot_valid_r && predict_slot_r == SLOT)
                    word0_tage_provider_r <= tage_provider_w[3*0 +: 3];
            end
            assign saved_0_tage_provider_w[3*slot +: 3] = word0_tage_provider_r;
            wire [36-1:0] word0_tage_indices_r;
            wire [36-1:0] word0_tage_indices_capture_w;
            assign word0_tage_indices_capture_w = tage_indices_w[36*0 +: 36];
            genvar word0_tage_indices_part;
            for (word0_tage_indices_part = 0; word0_tage_indices_part < (36+15)/16;
                word0_tage_indices_part = word0_tage_indices_part + 1) begin :
                    g_word0_tage_indices_slice
                localparam WIDTH = (36-16*word0_tage_indices_part < 16) ?
                    36-16*word0_tage_indices_part : 16;
                reg [WIDTH-1:0] data_r;
                always @(posedge clk_i) begin
                    if (predict_slot_valid_r && predict_slot_r == SLOT)
                        data_r <= word0_tage_indices_capture_w[16*word0_tage_indices_part +: WIDTH];
                end
                assign word0_tage_indices_r[16*word0_tage_indices_part +: WIDTH] = data_r;
            end
            assign saved_0_tage_indices_w[36*slot +: 36] = word0_tage_indices_r;
            wire [40-1:0] word0_tage_tags_r;
            wire [40-1:0] word0_tage_tags_capture_w;
            assign word0_tage_tags_capture_w = tage_tags_w[40*0 +: 40];
            genvar word0_tage_tags_part;
            for (word0_tage_tags_part = 0; word0_tage_tags_part < (40+15)/16;
                word0_tage_tags_part = word0_tage_tags_part + 1) begin : g_word0_tage_tags_slice
                localparam WIDTH = (40-16*word0_tage_tags_part < 16) ?
                    40-16*word0_tage_tags_part : 16;
                reg [WIDTH-1:0] data_r;
                always @(posedge clk_i) begin
                    if (predict_slot_valid_r && predict_slot_r == SLOT)
                        data_r <= word0_tage_tags_capture_w[16*word0_tage_tags_part +: WIDTH];
                end
                assign word0_tage_tags_r[16*word0_tage_tags_part +: WIDTH] = data_r;
            end
            assign saved_0_tage_tags_w[40*slot +: 40] = word0_tage_tags_r;
            reg [12-1:0] word0_tage_base_r;
            always @(posedge clk_i) begin
                if (predict_slot_valid_r && predict_slot_r == SLOT)
                    word0_tage_base_r <= tage_base_w[12*0 +: 12];
            end
            assign saved_0_tage_base_w[12*slot +: 12] = word0_tage_base_r;
            reg [1-1:0] word1_hit_r;
            always @(posedge clk_i) begin
                if (request_w && request_slot_w == SLOT)
                    word1_hit_r <= fast1_hit_w;
            end
            assign saved_1_hit_w[1*slot +: 1] = word1_hit_r;
            reg [1-1:0] word1_taken_r;
            always @(posedge clk_i) begin
                if (request_w && request_slot_w == SLOT)
                    word1_taken_r <= fast1_taken_w;
            end
            assign saved_1_taken_w[1*slot +: 1] = word1_taken_r;
            wire [32-1:0] word1_target_r;
            wire [32-1:0] word1_target_capture_w;
            assign word1_target_capture_w = fast1_target_w;
            genvar word1_target_part;
            for (word1_target_part = 0; word1_target_part < (32+15)/16;
                word1_target_part = word1_target_part + 1) begin : g_word1_target_slice
                localparam WIDTH = (32-16*word1_target_part < 16) ?
                    32-16*word1_target_part : 16;
                reg [WIDTH-1:0] data_r;
                always @(posedge clk_i) begin
                    if (request_w && request_slot_w == SLOT)
                        data_r <= word1_target_capture_w[16*word1_target_part +: WIDTH];
                end
                assign word1_target_r[16*word1_target_part +: WIDTH] = data_r;
            end
            assign saved_1_target_w[32*slot +: 32] = word1_target_r;
            reg [3-1:0] word1_type_r;
            always @(posedge clk_i) begin
                if (request_w && request_slot_w == SLOT)
                    word1_type_r <= fast1_type_w;
            end
            assign saved_1_type_w[3*slot +: 3] = word1_type_r;
            reg [12-1:0] word1_fast_index_r;
            always @(posedge clk_i) begin
                if (request_w && request_slot_w == SLOT)
                    word1_fast_index_r <= fast1_fast_index_w;
            end
            assign saved_1_fast_index_w[12*slot +: 12] = word1_fast_index_r;
            reg [1-1:0] word1_tage_prediction_r;
            always @(posedge clk_i) begin
                if (predict_slot_valid_r && predict_slot_r == SLOT)
                    word1_tage_prediction_r <= tage_prediction_w[1*1 +: 1];
            end
            assign saved_1_tage_prediction_w[1*slot +: 1] = word1_tage_prediction_r;
            reg [1-1:0] word1_tage_alternate_r;
            always @(posedge clk_i) begin
                if (predict_slot_valid_r && predict_slot_r == SLOT)
                    word1_tage_alternate_r <= tage_alternate_w[1*1 +: 1];
            end
            assign saved_1_tage_alternate_w[1*slot +: 1] = word1_tage_alternate_r;
            reg [3-1:0] word1_tage_provider_r;
            always @(posedge clk_i) begin
                if (predict_slot_valid_r && predict_slot_r == SLOT)
                    word1_tage_provider_r <= tage_provider_w[3*1 +: 3];
            end
            assign saved_1_tage_provider_w[3*slot +: 3] = word1_tage_provider_r;
            wire [36-1:0] word1_tage_indices_r;
            wire [36-1:0] word1_tage_indices_capture_w;
            assign word1_tage_indices_capture_w = tage_indices_w[36*1 +: 36];
            genvar word1_tage_indices_part;
            for (word1_tage_indices_part = 0; word1_tage_indices_part < (36+15)/16;
                word1_tage_indices_part = word1_tage_indices_part + 1) begin :
                    g_word1_tage_indices_slice
                localparam WIDTH = (36-16*word1_tage_indices_part < 16) ?
                    36-16*word1_tage_indices_part : 16;
                reg [WIDTH-1:0] data_r;
                always @(posedge clk_i) begin
                    if (predict_slot_valid_r && predict_slot_r == SLOT)
                        data_r <= word1_tage_indices_capture_w[16*word1_tage_indices_part +: WIDTH];
                end
                assign word1_tage_indices_r[16*word1_tage_indices_part +: WIDTH] = data_r;
            end
            assign saved_1_tage_indices_w[36*slot +: 36] = word1_tage_indices_r;
            wire [40-1:0] word1_tage_tags_r;
            wire [40-1:0] word1_tage_tags_capture_w;
            assign word1_tage_tags_capture_w = tage_tags_w[40*1 +: 40];
            genvar word1_tage_tags_part;
            for (word1_tage_tags_part = 0; word1_tage_tags_part < (40+15)/16;
                word1_tage_tags_part = word1_tage_tags_part + 1) begin : g_word1_tage_tags_slice
                localparam WIDTH = (40-16*word1_tage_tags_part < 16) ?
                    40-16*word1_tage_tags_part : 16;
                reg [WIDTH-1:0] data_r;
                always @(posedge clk_i) begin
                    if (predict_slot_valid_r && predict_slot_r == SLOT)
                        data_r <= word1_tage_tags_capture_w[16*word1_tage_tags_part +: WIDTH];
                end
                assign word1_tage_tags_r[16*word1_tage_tags_part +: WIDTH] = data_r;
            end
            assign saved_1_tage_tags_w[40*slot +: 40] = word1_tage_tags_r;
            reg [12-1:0] word1_tage_base_r;
            always @(posedge clk_i) begin
                if (predict_slot_valid_r && predict_slot_r == SLOT)
                    word1_tage_base_r <= tage_base_w[12*1 +: 12];
            end
            assign saved_1_tage_base_w[12*slot +: 12] = word1_tage_base_r;
        end
    endgenerate
    // Decode a direct JAL before ID captures the F2 result (model d_penalty=1).
    wire [31:0] physical0_instr_w = ic_resp_bank0_way_hit_i[1] ?
        ic_resp_bank0_way1_instr_i : ic_resp_bank0_way0_instr_i;
    wire [31:0] physical1_instr_w = ic_resp_bank1_way_hit_i[1] ?
        ic_resp_bank1_way1_instr_i : ic_resp_bank1_way0_instr_i;
    wire [63:0] decoded_instr_w = context_base_pc_w[2] ?
        {physical0_instr_w, physical1_instr_w} : {physical1_instr_w, physical0_instr_w};
    wire [1:0] direct_jal_w;
    wire [1:0] direct_hit_w = {context_1_hit_w, context_0_hit_w};
    wire [63:0] direct_target_w;
    wire [5:0] decoded_type_w;
    genvar decode_word;
    generate
        for (decode_word = 0; decode_word < 2; decode_word = decode_word+1) begin : g_direct
            wire [31:0] instr_w;
            wire [31:0] pc_w;
            wire link_w;
            assign instr_w = decoded_instr_w[32*decode_word +: 32];
            assign pc_w = context_base_pc_w + 4*decode_word;
            assign direct_jal_w[decode_word] = !direct_hit_w[decode_word] &&
                instr_w[6:0] == 7'b1101111;
            assign link_w = instr_w[11:7] == 5'd1 || instr_w[11:7] == 5'd5;
            assign decoded_type_w[3*decode_word +: 3] = link_w ? 3'd3 : 3'd1;
            assign direct_target_w[32*decode_word +: 32] = pc_w +
                {{11{instr_w[31]}}, instr_w[31], instr_w[19:12], instr_w[20],
                instr_w[30:21], 1'b0};
        end
    endgenerate
    assign context0_pc_w = context_base_pc_w;
    assign context0_predict_taken_w = (context0_raw_taken_w || direct_jal_w[0]) && word0_control_w;
    assign context0_raw_taken_w = (context_0_hit_w && context_0_type_w == 3'd0 &&
        ISSUE_WIDTH == 2) ?
        current0_prediction_w : context_0_taken_w;
    assign context0_predict_target_w = direct_jal_w[0] ?
        direct_target_w[0 +: 32] : context_0_target_w;
    assign context0_predict_token_w = (ISSUE_WIDTH == 2) && context_0_hit_w && context_0_type_w
        == 3'd0;
    assign context0_predict_provider_w = current0_provider_w;
    assign context0_predict_alternate_w = current0_alternate_w;
    assign context0_predict_index0_w = current0_indices_w[0 +: 9];
    assign context0_predict_index1_w = current0_indices_w[9 +: 9];
    assign context0_predict_index2_w = current0_indices_w[18 +: 9];
    assign context0_predict_index3_w = current0_indices_w[27 +: 9];
    assign context0_predict_tag0_w = current0_tags_w[0 +: 10];
    assign context0_predict_tag1_w = current0_tags_w[10 +: 10];
    assign context0_predict_tag2_w = current0_tags_w[20 +: 10];
    assign context0_predict_tag3_w = current0_tags_w[30 +: 10];
    assign context0_predict_base_index_w = current0_base_w;
    assign context0_predict_fast_index_w = context_0_fast_index_w;
    assign context0_ras_data_w = context_0_ras_data_w;
    assign context0_ras_ptr_w = context_0_ras_ptr_w;
    assign context0_ras_count_w = context_0_ras_count_w;
    assign current0_prediction_w = predict_slot_valid_r && predict_slot_r == head_r ?
        tage_prediction_w[1*0 +: 1] : context_0_tage_prediction_w;
    assign current0_alternate_w = predict_slot_valid_r && predict_slot_r == head_r ?
        tage_alternate_w[1*0 +: 1] : context_0_tage_alternate_w;
    assign current0_provider_w = predict_slot_valid_r && predict_slot_r == head_r ?
        tage_provider_w[3*0 +: 3] : context_0_tage_provider_w;
    assign current0_indices_w = predict_slot_valid_r && predict_slot_r == head_r ?
        tage_indices_w[36*0 +: 36] : context_0_tage_indices_w;
    assign current0_tags_w = predict_slot_valid_r && predict_slot_r == head_r ?
        tage_tags_w[40*0 +: 40] : context_0_tage_tags_w;
    assign current0_base_w = predict_slot_valid_r && predict_slot_r == head_r ?
        tage_base_w[12*0 +: 12] : context_0_tage_base_w;
    assign context1_pc_w = context_base_pc_w + 32'd4;
    assign context1_predict_taken_w = (context1_raw_taken_w || direct_jal_w[1]) && word1_control_w;
    assign context1_raw_taken_w = (context_1_hit_w && context_1_type_w == 3'd0 &&
        ISSUE_WIDTH == 2) ?
        current1_prediction_w : context_1_taken_w;
    assign context1_predict_target_w = direct_jal_w[1] ? direct_target_w[32 +: 32] :
        (context_1_type_w == 3'd4 || context_1_type_w == 3'd5) && context_0_ras_count_w != 0 ?
        context_ras_top_w : context_1_target_w;
    assign context1_predict_token_w = (ISSUE_WIDTH == 2) && context_1_hit_w && context_1_type_w
        == 3'd0;
    assign context1_predict_provider_w = current1_provider_w;
    assign context1_predict_alternate_w = current1_alternate_w;
    assign context1_predict_index0_w = current1_indices_w[0 +: 9];
    assign context1_predict_index1_w = current1_indices_w[9 +: 9];
    assign context1_predict_index2_w = current1_indices_w[18 +: 9];
    assign context1_predict_index3_w = current1_indices_w[27 +: 9];
    assign context1_predict_tag0_w = current1_tags_w[0 +: 10];
    assign context1_predict_tag1_w = current1_tags_w[10 +: 10];
    assign context1_predict_tag2_w = current1_tags_w[20 +: 10];
    assign context1_predict_tag3_w = current1_tags_w[30 +: 10];
    assign context1_predict_base_index_w = current1_base_w;
    assign context1_predict_fast_index_w = context_1_fast_index_w;
    assign context1_ras_data_w = context_0_ras_data_w;
    assign context1_ras_ptr_w = context_0_ras_ptr_w;
    assign context1_ras_count_w = context_0_ras_count_w;
    assign current1_prediction_w = predict_slot_valid_r && predict_slot_r == head_r ?
        tage_prediction_w[1*1 +: 1] : context_1_tage_prediction_w;
    assign current1_alternate_w = predict_slot_valid_r && predict_slot_r == head_r ?
        tage_alternate_w[1*1 +: 1] : context_1_tage_alternate_w;
    assign current1_provider_w = predict_slot_valid_r && predict_slot_r == head_r ?
        tage_provider_w[3*1 +: 3] : context_1_tage_provider_w;
    assign current1_indices_w = predict_slot_valid_r && predict_slot_r == head_r ?
        tage_indices_w[36*1 +: 36] : context_1_tage_indices_w;
    assign current1_tags_w = predict_slot_valid_r && predict_slot_r == head_r ?
        tage_tags_w[40*1 +: 40] : context_1_tage_tags_w;
    assign current1_base_w = predict_slot_valid_r && predict_slot_r == head_r ?
        tage_base_w[12*1 +: 12] : context_1_tage_base_w;
    // Reuse the F1 RAS read at F2; no late pointer-to-eight-word mux is added.
    assign context_ras_top_w = head_r ? saved_ras_top_w[63:32] : saved_ras_top_w[31:0];
    assign oldest_taken_w = !context_skip_w && context0_predict_taken_w;
    assign youngest_taken_w = !oldest_taken_w && context1_predict_taken_w;
    assign context_count_w = context_skip_w || oldest_taken_w ? 2'd1 : 2'd2;
    assign final_next_pc_w = oldest_taken_w ? context0_predict_target_w :
        youngest_taken_w ? context1_predict_target_w : context_base_pc_w + 32'd8;
    assign final_taken_w = oldest_taken_w || youngest_taken_w;
    assign final_type_w = oldest_taken_w ?
        (direct_jal_w[0] ? decoded_type_w[0 +: 3] : context_0_type_w) :
        (direct_jal_w[1] ? decoded_type_w[3 +: 3] : context_1_type_w);
    assign final_pc_w = oldest_taken_w ? context0_pc_w : context1_pc_w;
    assign final_pop_w = final_taken_w && (final_type_w == 3'd4 || final_type_w == 3'd5);
    assign final_push_w = final_taken_w && (final_type_w == 3'd3 || final_type_w == 3'd5);
    assign final_link_w = final_pc_w + 32'd4;
    edrv32_cpu2_fetch #(
        .ISSUE_WIDTH(ISSUE_WIDTH)
    ) u_fetch (
        .clk_i(clk_i),
        .rst_n_i(rst_n_i),
        .ic_resp_valid_i(fetch_response_w),
        .ic_resp_ready_o(fetch_ready_w),
        .word0_control_o(word0_control_w),
        .word1_control_o(word1_control_w),
        .ic_resp_bank0_way0_instr_i(ic_resp_bank0_way0_instr_i),
        .ic_resp_bank0_way1_instr_i(ic_resp_bank0_way1_instr_i),
        .ic_resp_bank1_way0_instr_i(ic_resp_bank1_way0_instr_i),
        .ic_resp_bank1_way1_instr_i(ic_resp_bank1_way1_instr_i),
        .ic_resp_bank0_way_hit_i(ic_resp_bank0_way_hit_i),
        .ic_resp_bank0_error_i(ic_resp_bank0_error_i),
        .ic_resp_bank1_way_hit_i(ic_resp_bank1_way_hit_i),
        .ic_resp_bank1_error_i(ic_resp_bank1_error_i),
        .context_valid_i(contexts_r != 2'd0),
        .context_count_i(context_count_w),
        .context_skip0_i(context_skip_w),
        .context_parity_i(context_base_pc_w[2]),
        .context0_pc_i(context0_pc_w),
        .context0_predict_taken_i(context0_predict_taken_w),
        .context0_predict_target_i(context0_predict_target_w),
        .context0_predict_token_i(context0_predict_token_w),
        .context0_predict_provider_i(context0_predict_provider_w),
        .context0_predict_alternate_i(context0_predict_alternate_w),
        .context0_predict_index0_i(context0_predict_index0_w),
        .context0_predict_index1_i(context0_predict_index1_w),
        .context0_predict_index2_i(context0_predict_index2_w),
        .context0_predict_index3_i(context0_predict_index3_w),
        .context0_predict_tag0_i(context0_predict_tag0_w),
        .context0_predict_tag1_i(context0_predict_tag1_w),
        .context0_predict_tag2_i(context0_predict_tag2_w),
        .context0_predict_tag3_i(context0_predict_tag3_w),
        .context0_predict_base_index_i(context0_predict_base_index_w),
        .context0_predict_fast_index_i(context0_predict_fast_index_w),
        .context0_ras_data_i(context0_ras_data_w),
        .context0_ras_ptr_i(context0_ras_ptr_w),
        .context0_ras_count_i(context0_ras_count_w),
        .context1_pc_i(context1_pc_w),
        .context1_predict_taken_i(context1_predict_taken_w),
        .context1_predict_target_i(context1_predict_target_w),
        .context1_predict_token_i(context1_predict_token_w),
        .context1_predict_provider_i(context1_predict_provider_w),
        .context1_predict_alternate_i(context1_predict_alternate_w),
        .context1_predict_index0_i(context1_predict_index0_w),
        .context1_predict_index1_i(context1_predict_index1_w),
        .context1_predict_index2_i(context1_predict_index2_w),
        .context1_predict_index3_i(context1_predict_index3_w),
        .context1_predict_tag0_i(context1_predict_tag0_w),
        .context1_predict_tag1_i(context1_predict_tag1_w),
        .context1_predict_tag2_i(context1_predict_tag2_w),
        .context1_predict_tag3_i(context1_predict_tag3_w),
        .context1_predict_base_index_i(context1_predict_base_index_w),
        .context1_predict_fast_index_i(context1_predict_fast_index_w),
        .context1_ras_data_i(context1_ras_data_w),
        .context1_ras_ptr_i(context1_ras_ptr_w),
        .context1_ras_count_i(context1_ras_count_w),
        .lvt_i(lvt_i),
        .wb0_valid_i(wb0_valid_i),
        .wb0_rd_i(wb0_rd_i),
        .wb1_valid_i(wb1_valid_i),
        .wb1_rd_i(wb1_rd_i),
        .wb0_valid_copy_i(wb0_valid_copy_i),
        .wb0_rd_copy_i(wb0_rd_copy_i),
        .wb1_valid_copy_i(wb1_valid_copy_i),
        .wb1_rd_copy_i(wb1_rd_copy_i),
        .fetch_push_valid_o(push_valid_w),
        .fetch_push_ready_i(push_ready_w),
        .fetch_push_count_o(push_count_w),
        .fetch_push0_pc_o(push0_pc_w),
        .fetch_push0_instr_o(push0_instr_w),
        .fetch_push0_error_o(push0_error_w),
        .fetch_push0_candidates_o(push0_candidates_w),
        .fetch_push0_predict_taken_o(push0_predict_taken_w),
        .fetch_push0_predict_target_o(push0_predict_target_w),
        .fetch_push0_predict_token_o(push0_predict_token_w),
        .fetch_push0_predict_provider_o(push0_predict_provider_w),
        .fetch_push0_predict_alternate_o(push0_predict_alternate_w),
        .fetch_push0_predict_index0_o(push0_predict_index0_w),
        .fetch_push0_predict_index1_o(push0_predict_index1_w),
        .fetch_push0_predict_index2_o(push0_predict_index2_w),
        .fetch_push0_predict_index3_o(push0_predict_index3_w),
        .fetch_push0_predict_tag0_o(push0_predict_tag0_w),
        .fetch_push0_predict_tag1_o(push0_predict_tag1_w),
        .fetch_push0_predict_tag2_o(push0_predict_tag2_w),
        .fetch_push0_predict_tag3_o(push0_predict_tag3_w),
        .fetch_push0_predict_base_index_o(push0_predict_base_index_w),
        .fetch_push0_predict_fast_index_o(push0_predict_fast_index_w),
        .fetch_push0_ras_data_o(push0_ras_data_w),
        .fetch_push0_ras_ptr_o(push0_ras_ptr_w),
        .fetch_push0_ras_count_o(push0_ras_count_w),
        .fetch_push1_pc_o(push1_pc_w),
        .fetch_push1_instr_o(push1_instr_w),
        .fetch_push1_error_o(push1_error_w),
        .fetch_push1_candidates_o(push1_candidates_w),
        .fetch_push1_predict_taken_o(push1_predict_taken_w),
        .fetch_push1_predict_target_o(push1_predict_target_w),
        .fetch_push1_predict_token_o(push1_predict_token_w),
        .fetch_push1_predict_provider_o(push1_predict_provider_w),
        .fetch_push1_predict_alternate_o(push1_predict_alternate_w),
        .fetch_push1_predict_index0_o(push1_predict_index0_w),
        .fetch_push1_predict_index1_o(push1_predict_index1_w),
        .fetch_push1_predict_index2_o(push1_predict_index2_w),
        .fetch_push1_predict_index3_o(push1_predict_index3_w),
        .fetch_push1_predict_tag0_o(push1_predict_tag0_w),
        .fetch_push1_predict_tag1_o(push1_predict_tag1_w),
        .fetch_push1_predict_tag2_o(push1_predict_tag2_w),
        .fetch_push1_predict_tag3_o(push1_predict_tag3_w),
        .fetch_push1_predict_base_index_o(push1_predict_base_index_w),
        .fetch_push1_predict_fast_index_o(push1_predict_fast_index_w),
        .fetch_push1_ras_data_o(push1_ras_data_w),
        .fetch_push1_ras_ptr_o(push1_ras_ptr_w),
        .fetch_push1_ras_count_o(push1_ras_count_w)
    );
    edrv32_cpu2_ib #(
        .ISSUE_WIDTH(ISSUE_WIDTH)
    ) u_ib (
        .clk_i(clk_i),
        .rst_n_i(rst_n_i),
        .fetch_push_valid_i(push_valid_w),
        .fetch_push_ready_o(push_ready_w),
        .fetch_push_count_i(push_count_w),
        .fetch_push0_pc_i(push0_pc_w),
        .fetch_push0_instr_i(push0_instr_w),
        .fetch_push0_error_i(push0_error_w),
        .fetch_push0_candidates_i(push0_candidates_w),
        .fetch_push0_predict_taken_i(push0_predict_taken_w),
        .fetch_push0_predict_target_i(push0_predict_target_w),
        .fetch_push0_predict_token_i(push0_predict_token_w),
        .fetch_push0_predict_provider_i(push0_predict_provider_w),
        .fetch_push0_predict_alternate_i(push0_predict_alternate_w),
        .fetch_push0_predict_index0_i(push0_predict_index0_w),
        .fetch_push0_predict_index1_i(push0_predict_index1_w),
        .fetch_push0_predict_index2_i(push0_predict_index2_w),
        .fetch_push0_predict_index3_i(push0_predict_index3_w),
        .fetch_push0_predict_tag0_i(push0_predict_tag0_w),
        .fetch_push0_predict_tag1_i(push0_predict_tag1_w),
        .fetch_push0_predict_tag2_i(push0_predict_tag2_w),
        .fetch_push0_predict_tag3_i(push0_predict_tag3_w),
        .fetch_push0_predict_base_index_i(push0_predict_base_index_w),
        .fetch_push0_predict_fast_index_i(push0_predict_fast_index_w),
        .fetch_push0_ras_data_i(push0_ras_data_w),
        .fetch_push0_ras_ptr_i(push0_ras_ptr_w),
        .fetch_push0_ras_count_i(push0_ras_count_w),
        .fetch_push1_pc_i(push1_pc_w),
        .fetch_push1_instr_i(push1_instr_w),
        .fetch_push1_error_i(push1_error_w),
        .fetch_push1_candidates_i(push1_candidates_w),
        .fetch_push1_predict_taken_i(push1_predict_taken_w),
        .fetch_push1_predict_target_i(push1_predict_target_w),
        .fetch_push1_predict_token_i(push1_predict_token_w),
        .fetch_push1_predict_provider_i(push1_predict_provider_w),
        .fetch_push1_predict_alternate_i(push1_predict_alternate_w),
        .fetch_push1_predict_index0_i(push1_predict_index0_w),
        .fetch_push1_predict_index1_i(push1_predict_index1_w),
        .fetch_push1_predict_index2_i(push1_predict_index2_w),
        .fetch_push1_predict_index3_i(push1_predict_index3_w),
        .fetch_push1_predict_tag0_i(push1_predict_tag0_w),
        .fetch_push1_predict_tag1_i(push1_predict_tag1_w),
        .fetch_push1_predict_tag2_i(push1_predict_tag2_w),
        .fetch_push1_predict_tag3_i(push1_predict_tag3_w),
        .fetch_push1_predict_base_index_i(push1_predict_base_index_w),
        .fetch_push1_predict_fast_index_i(push1_predict_fast_index_w),
        .fetch_push1_ras_data_i(push1_ras_data_w),
        .fetch_push1_ras_ptr_i(push1_ras_ptr_w),
        .fetch_push1_ras_count_i(push1_ras_count_w),
        .ib_remove_count_i(ib_remove_count_i),
        .ib_credit_o(credit_w),
        .frontend_flush_i(flush_w),
        .reserve_valid_i(request_w),
        .reserve_cancel_count_i(correction_r ? contexts_r : 2'd0),
        .wb0_valid_i(wb0_valid_i),
        .wb0_rd_i(wb0_rd_i),
        .wb1_valid_i(wb1_valid_i),
        .wb1_rd_i(wb1_rd_i),
        .wb0_valid_copy_i(wb0_valid_copy_i),
        .wb0_rd_copy_i(wb0_rd_copy_i),
        .wb1_valid_copy_i(wb1_valid_copy_i),
        .wb1_rd_copy_i(wb1_rd_copy_i),
        .ib_head0_valid_o(ib_head0_valid_o),
        .ib_head1_valid_o(ib_head1_valid_o),
        .ib_head0_pc_o(ib_head0_pc_o),
        .ib_head0_instr_o(ib_head0_instr_o),
        .ib_head0_error_o(ib_head0_error_o),
        .ib_head0_candidates_o(ib_head0_candidates_o),
        .ib_head0_predict_taken_o(ib_head0_predict_taken_o),
        .ib_head0_predict_target_o(ib_head0_predict_target_o),
        .ib_head0_predict_token_o(ib_head0_predict_token_o),
        .ib_head0_predict_provider_o(ib_head0_predict_provider_o),
        .ib_head0_predict_alternate_o(ib_head0_predict_alternate_o),
        .ib_head0_predict_index0_o(ib_head0_predict_index0_o),
        .ib_head0_predict_index1_o(ib_head0_predict_index1_o),
        .ib_head0_predict_index2_o(ib_head0_predict_index2_o),
        .ib_head0_predict_index3_o(ib_head0_predict_index3_o),
        .ib_head0_predict_tag0_o(ib_head0_predict_tag0_o),
        .ib_head0_predict_tag1_o(ib_head0_predict_tag1_o),
        .ib_head0_predict_tag2_o(ib_head0_predict_tag2_o),
        .ib_head0_predict_tag3_o(ib_head0_predict_tag3_o),
        .ib_head0_predict_base_index_o(ib_head0_predict_base_index_o),
        .ib_head0_predict_fast_index_o(ib_head0_predict_fast_index_o),
        .ib_head0_ras_data_o(ib_head0_ras_data_o),
        .ib_head0_ras_ptr_o(ib_head0_ras_ptr_o),
        .ib_head0_ras_count_o(ib_head0_ras_count_o),
        .ib_head1_pc_o(ib_head1_pc_o),
        .ib_head1_instr_o(ib_head1_instr_o),
        .ib_head1_error_o(ib_head1_error_o),
        .ib_head1_candidates_o(ib_head1_candidates_o),
        .ib_head1_predict_taken_o(ib_head1_predict_taken_o),
        .ib_head1_predict_target_o(ib_head1_predict_target_o),
        .ib_head1_predict_token_o(ib_head1_predict_token_o),
        .ib_head1_predict_provider_o(ib_head1_predict_provider_o),
        .ib_head1_predict_alternate_o(ib_head1_predict_alternate_o),
        .ib_head1_predict_index0_o(ib_head1_predict_index0_o),
        .ib_head1_predict_index1_o(ib_head1_predict_index1_o),
        .ib_head1_predict_index2_o(ib_head1_predict_index2_o),
        .ib_head1_predict_index3_o(ib_head1_predict_index3_o),
        .ib_head1_predict_tag0_o(ib_head1_predict_tag0_o),
        .ib_head1_predict_tag1_o(ib_head1_predict_tag1_o),
        .ib_head1_predict_tag2_o(ib_head1_predict_tag2_o),
        .ib_head1_predict_tag3_o(ib_head1_predict_tag3_o),
        .ib_head1_predict_base_index_o(ib_head1_predict_base_index_o),
        .ib_head1_predict_fast_index_o(ib_head1_predict_fast_index_o),
        .ib_head1_ras_data_o(ib_head1_ras_data_o),
        .ib_head1_ras_ptr_o(ib_head1_ras_ptr_o),
        .ib_head1_ras_count_o(ib_head1_ras_count_o),
        .ib_count_o(ib_count_o)
    );
    assign unused_w = ^{branch_redirect_tag_i, tage_valid_w, correction_cause_r,
        fast1_ras_data_w, fast1_ras_ptr_w, fast1_ras_count_w,
        predict_read0_valid_i, predict_read0_tag_i, predict_read0_index0_i,
            predict_read0_index1_i, predict_read0_index2_i, predict_read0_index3_i,
            predict_read0_tag0_i, predict_read0_tag1_i, predict_read0_tag2_i,
            predict_read0_tag3_i, predict_read0_base_index_i, predict_read1_valid_i,
            predict_read1_tag_i, predict_read1_index0_i, predict_read1_index1_i,
            predict_read1_index2_i, predict_read1_index3_i, predict_read1_tag0_i,
            predict_read1_tag1_i, predict_read1_tag2_i, predict_read1_tag3_i,
            predict_read1_base_index_i, ex_predict_train_token_i, ex_predict_train_provider_i,
            ex_predict_train_prediction_i, ex_predict_train_alternate_i,
            ex_predict_train_index0_i, ex_predict_train_index1_i, ex_predict_train_index2_i,
            ex_predict_train_index3_i, ex_predict_train_tag0_i, ex_predict_train_tag1_i,
            ex_predict_train_tag2_i, ex_predict_train_tag3_i, ex_predict_train_base_index_i,
            mem_predict_train_token_i, mem_predict_train_provider_i,
            mem_predict_train_prediction_i, mem_predict_train_alternate_i,
            mem_predict_train_index0_i, mem_predict_train_index1_i, mem_predict_train_index2_i,
            mem_predict_train_index3_i, mem_predict_train_tag0_i, mem_predict_train_tag1_i,
            mem_predict_train_tag2_i, mem_predict_train_tag3_i, mem_predict_train_base_index_i};
endmodule
