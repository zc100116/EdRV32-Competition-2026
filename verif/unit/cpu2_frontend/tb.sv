// Independent CV07/CV08 public-interface state model.
module tb #(
    parameter ISSUE_WIDTH = 2,
    parameter [31:0] FPU_FORMAT = "NONE"
);
    localparam TAG_BITS = FPU_FORMAT == "FD" ? 4 : FPU_FORMAT == "F" ? 3 : 2;
    localparam RAS_BITS = ISSUE_WIDTH == 2 ? 256 : 128;
    localparam RAS_PTR_BITS = ISSUE_WIDTH == 2 ? 3 : 2;
    localparam RAS_COUNT_BITS = RAS_PTR_BITS+1;
    reg clk_i;
    reg rst_n_i;
    reg frontend_flush_i;
    reg redirect_valid_i;
    reg [32-1:0] redirect_pc_i;
    reg branch_redirect_valid_i;
    reg [TAG_BITS-1:0] branch_redirect_tag_i;
    reg [32-1:0] branch_redirect_pc_i;
    reg commit_redirect_valid_i;
    reg [32-1:0] commit_redirect_pc_i;
    reg fetch_stop_i;
    reg [RAS_BITS-1:0] branch_redirect_ras_data_i;
    reg [RAS_PTR_BITS-1:0] branch_redirect_ras_ptr_i;
    reg [RAS_COUNT_BITS-1:0] branch_redirect_ras_count_i;
    reg branch_redirect_ras_pop_i;
    reg branch_redirect_ras_push_i;
    reg [32-1:0] branch_redirect_link_i;
    reg [2-1:0] ib_remove_count_i;
    wire [4-1:0] ib_credit_o;
    reg [31:1] lvt_i;
    reg wb0_valid_i;
    reg [5-1:0] wb0_rd_i;
    reg wb1_valid_i;
    reg [5-1:0] wb1_rd_i;
    wire ib_head0_valid_o;
    wire ib_head1_valid_o;
    wire [32-1:0] ib_head0_pc_o;
    wire [32-1:0] ib_head0_instr_o;
    wire ib_head0_error_o;
    wire [5-1:0] ib_head0_candidates_o;
    wire ib_head0_predict_taken_o;
    wire [32-1:0] ib_head0_predict_target_o;
    wire ib_head0_predict_token_o;
    wire [3-1:0] ib_head0_predict_provider_o;
    wire ib_head0_predict_alternate_o;
    wire [9-1:0] ib_head0_predict_index0_o;
    wire [9-1:0] ib_head0_predict_index1_o;
    wire [9-1:0] ib_head0_predict_index2_o;
    wire [9-1:0] ib_head0_predict_index3_o;
    wire [10-1:0] ib_head0_predict_tag0_o;
    wire [10-1:0] ib_head0_predict_tag1_o;
    wire [10-1:0] ib_head0_predict_tag2_o;
    wire [10-1:0] ib_head0_predict_tag3_o;
    wire [12-1:0] ib_head0_predict_base_index_o;
    wire [12-1:0] ib_head0_predict_fast_index_o;
    wire [RAS_BITS-1:0] ib_head0_ras_data_o;
    wire [RAS_PTR_BITS-1:0] ib_head0_ras_ptr_o;
    wire [RAS_COUNT_BITS-1:0] ib_head0_ras_count_o;
    wire [32-1:0] ib_head1_pc_o;
    wire [32-1:0] ib_head1_instr_o;
    wire ib_head1_error_o;
    wire [5-1:0] ib_head1_candidates_o;
    wire ib_head1_predict_taken_o;
    wire [32-1:0] ib_head1_predict_target_o;
    wire ib_head1_predict_token_o;
    wire [3-1:0] ib_head1_predict_provider_o;
    wire ib_head1_predict_alternate_o;
    wire [9-1:0] ib_head1_predict_index0_o;
    wire [9-1:0] ib_head1_predict_index1_o;
    wire [9-1:0] ib_head1_predict_index2_o;
    wire [9-1:0] ib_head1_predict_index3_o;
    wire [10-1:0] ib_head1_predict_tag0_o;
    wire [10-1:0] ib_head1_predict_tag1_o;
    wire [10-1:0] ib_head1_predict_tag2_o;
    wire [10-1:0] ib_head1_predict_tag3_o;
    wire [12-1:0] ib_head1_predict_base_index_o;
    wire [12-1:0] ib_head1_predict_fast_index_o;
    wire [RAS_BITS-1:0] ib_head1_ras_data_o;
    wire [RAS_PTR_BITS-1:0] ib_head1_ras_ptr_o;
    wire [RAS_COUNT_BITS-1:0] ib_head1_ras_count_o;
    wire ic_req_valid_o;
    reg ic_req_ready_i;
    wire [32-1:0] ic_req_addr_o;
    reg ic_resp_valid_i;
    wire ic_resp_ready_o;
    wire ic_cancel_o;
    reg [32-1:0] ic_resp_bank0_way0_instr_i;
    reg [32-1:0] ic_resp_bank0_way1_instr_i;
    reg [32-1:0] ic_resp_bank1_way0_instr_i;
    reg [32-1:0] ic_resp_bank1_way1_instr_i;
    reg [2-1:0] ic_resp_bank0_way_hit_i;
    reg ic_resp_bank0_error_i;
    reg [2-1:0] ic_resp_bank1_way_hit_i;
    reg ic_resp_bank1_error_i;
    reg predict_read0_valid_i;
    reg [TAG_BITS-1:0] predict_read0_tag_i;
    reg [9-1:0] predict_read0_index0_i;
    reg [9-1:0] predict_read0_index1_i;
    reg [9-1:0] predict_read0_index2_i;
    reg [9-1:0] predict_read0_index3_i;
    reg [10-1:0] predict_read0_tag0_i;
    reg [10-1:0] predict_read0_tag1_i;
    reg [10-1:0] predict_read0_tag2_i;
    reg [10-1:0] predict_read0_tag3_i;
    reg [12-1:0] predict_read0_base_index_i;
    reg predict_read1_valid_i;
    reg [TAG_BITS-1:0] predict_read1_tag_i;
    reg [9-1:0] predict_read1_index0_i;
    reg [9-1:0] predict_read1_index1_i;
    reg [9-1:0] predict_read1_index2_i;
    reg [9-1:0] predict_read1_index3_i;
    reg [10-1:0] predict_read1_tag0_i;
    reg [10-1:0] predict_read1_tag1_i;
    reg [10-1:0] predict_read1_tag2_i;
    reg [10-1:0] predict_read1_tag3_i;
    reg [12-1:0] predict_read1_base_index_i;
    reg ex_predict_train_valid_i;
    reg [TAG_BITS-1:0] ex_predict_train_tag_i;
    reg [32-1:0] ex_predict_train_pc_i;
    reg ex_predict_train_taken_i;
    reg [32-1:0] ex_predict_train_target_i;
    reg [3-1:0] ex_predict_train_type_i;
    reg [12-1:0] ex_predict_train_fast_index_i;
    reg ex_predict_train_token_i;
    reg [3-1:0] ex_predict_train_provider_i;
    reg ex_predict_train_prediction_i;
    reg ex_predict_train_alternate_i;
    reg [9-1:0] ex_predict_train_index0_i;
    reg [9-1:0] ex_predict_train_index1_i;
    reg [9-1:0] ex_predict_train_index2_i;
    reg [9-1:0] ex_predict_train_index3_i;
    reg [10-1:0] ex_predict_train_tag0_i;
    reg [10-1:0] ex_predict_train_tag1_i;
    reg [10-1:0] ex_predict_train_tag2_i;
    reg [10-1:0] ex_predict_train_tag3_i;
    reg [12-1:0] ex_predict_train_base_index_i;
    reg mem_predict_train_valid_i;
    reg [TAG_BITS-1:0] mem_predict_train_tag_i;
    reg [32-1:0] mem_predict_train_pc_i;
    reg mem_predict_train_taken_i;
    reg [32-1:0] mem_predict_train_target_i;
    reg [3-1:0] mem_predict_train_type_i;
    reg [12-1:0] mem_predict_train_fast_index_i;
    reg mem_predict_train_token_i;
    reg [3-1:0] mem_predict_train_provider_i;
    reg mem_predict_train_prediction_i;
    reg mem_predict_train_alternate_i;
    reg [9-1:0] mem_predict_train_index0_i;
    reg [9-1:0] mem_predict_train_index1_i;
    reg [9-1:0] mem_predict_train_index2_i;
    reg [9-1:0] mem_predict_train_index3_i;
    reg [10-1:0] mem_predict_train_tag0_i;
    reg [10-1:0] mem_predict_train_tag1_i;
    reg [10-1:0] mem_predict_train_tag2_i;
    reg [10-1:0] mem_predict_train_tag3_i;
    reg [12-1:0] mem_predict_train_base_index_i;
    reg [TAG_BITS-1:0] age_head_i;
    reg cancel_valid_i;
    reg [TAG_BITS-1:0] cancel_tag_i;
    wire wb0_valid_copy_i = wb0_valid_i;
    wire [4:0] wb0_rd_copy_i = wb0_rd_i;
    wire wb1_valid_copy_i = wb1_valid_i;
    wire [4:0] wb1_rd_copy_i = wb1_rd_i;
    wire f2_redirect_valid_o;
    wire [31:0] f2_redirect_pc_o;
    wire [31:0] f2_redirect_target_o;
    wire [1:0] f2_redirect_cause_o;
    edrv32_cpu2_frontend #(
        .ISSUE_WIDTH(ISSUE_WIDTH),
        .FPU_FORMAT(FPU_FORMAT)
    ) dut (
        .clk_i(clk_i),
        .rst_n_i(rst_n_i),
        .frontend_flush_i(frontend_flush_i),
        .redirect_valid_i(redirect_valid_i),
        .redirect_pc_i(redirect_pc_i),
        .branch_redirect_valid_i(branch_redirect_valid_i),
        .branch_redirect_tag_i(branch_redirect_tag_i),
        .branch_redirect_pc_i(branch_redirect_pc_i),
        .commit_redirect_valid_i(commit_redirect_valid_i),
        .commit_redirect_pc_i(commit_redirect_pc_i),
        .fetch_stop_i(fetch_stop_i),
        .branch_redirect_ras_data_i(branch_redirect_ras_data_i),
        .branch_redirect_ras_ptr_i(branch_redirect_ras_ptr_i),
        .branch_redirect_ras_count_i(branch_redirect_ras_count_i),
        .branch_redirect_ras_pop_i(branch_redirect_ras_pop_i),
        .branch_redirect_ras_push_i(branch_redirect_ras_push_i),
        .branch_redirect_link_i(branch_redirect_link_i),
        .ib_remove_count_i(ib_remove_count_i),
        .ib_credit_o(ib_credit_o),
        .lvt_i(lvt_i),
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
        .ic_req_valid_o(ic_req_valid_o),
        .ic_req_ready_i(ic_req_ready_i),
        .ic_req_addr_o(ic_req_addr_o),
        .ic_resp_valid_i(ic_resp_valid_i),
        .ic_resp_ready_o(ic_resp_ready_o),
        .ic_cancel_o(ic_cancel_o),
        .f2_redirect_valid_o(f2_redirect_valid_o),
        .f2_redirect_pc_o(f2_redirect_pc_o),
        .f2_redirect_target_o(f2_redirect_target_o),
        .f2_redirect_cause_o(f2_redirect_cause_o),
        .ic_resp_bank0_way0_instr_i(ic_resp_bank0_way0_instr_i),
        .ic_resp_bank0_way1_instr_i(ic_resp_bank0_way1_instr_i),
        .ic_resp_bank1_way0_instr_i(ic_resp_bank1_way0_instr_i),
        .ic_resp_bank1_way1_instr_i(ic_resp_bank1_way1_instr_i),
        .ic_resp_bank0_way_hit_i(ic_resp_bank0_way_hit_i),
        .ic_resp_bank0_error_i(ic_resp_bank0_error_i),
        .ic_resp_bank1_way_hit_i(ic_resp_bank1_way_hit_i),
        .ic_resp_bank1_error_i(ic_resp_bank1_error_i),
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
        .ex_predict_train_valid_i(ex_predict_train_valid_i),
        .ex_predict_train_tag_i(ex_predict_train_tag_i),
        .ex_predict_train_pc_i(ex_predict_train_pc_i),
        .ex_predict_train_taken_i(ex_predict_train_taken_i),
        .ex_predict_train_target_i(ex_predict_train_target_i),
        .ex_predict_train_type_i(ex_predict_train_type_i),
        .ex_predict_train_fast_index_i(ex_predict_train_fast_index_i),
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
        .mem_predict_train_valid_i(mem_predict_train_valid_i),
        .mem_predict_train_tag_i(mem_predict_train_tag_i),
        .mem_predict_train_pc_i(mem_predict_train_pc_i),
        .mem_predict_train_taken_i(mem_predict_train_taken_i),
        .mem_predict_train_target_i(mem_predict_train_target_i),
        .mem_predict_train_type_i(mem_predict_train_type_i),
        .mem_predict_train_fast_index_i(mem_predict_train_fast_index_i),
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
        .cancel_tag_i(cancel_tag_i),
        // I06 observation-only outputs.
        .ib_count_o(),
        .frontend_active_o()
    );
    always #5 clk_i = ~clk_i;
    task tick; begin @(posedge clk_i); #1; end endtask
    task initialize; begin
        clk_i = '0;
        rst_n_i = '0;
        frontend_flush_i = '0;
        redirect_valid_i = '0;
        redirect_pc_i = '0;
        branch_redirect_valid_i = '0;
        branch_redirect_tag_i = '0;
        branch_redirect_pc_i = '0;
        commit_redirect_valid_i = '0;
        commit_redirect_pc_i = '0;
        fetch_stop_i = '0;
        branch_redirect_ras_data_i = '0;
        branch_redirect_ras_ptr_i = '0;
        branch_redirect_ras_count_i = '0;
        branch_redirect_ras_pop_i = '0;
        branch_redirect_ras_push_i = '0;
        branch_redirect_link_i = '0;
        ib_remove_count_i = '0;
        lvt_i = '0;
        wb0_valid_i = '0;
        wb0_rd_i = '0;
        wb1_valid_i = '0;
        wb1_rd_i = '0;
        ic_req_ready_i = '0;
        ic_resp_valid_i = '0;
        ic_resp_bank0_way0_instr_i = '0;
        ic_resp_bank0_way1_instr_i = '0;
        ic_resp_bank1_way0_instr_i = '0;
        ic_resp_bank1_way1_instr_i = '0;
        ic_resp_bank0_way_hit_i = '0;
        ic_resp_bank0_error_i = '0;
        ic_resp_bank1_way_hit_i = '0;
        ic_resp_bank1_error_i = '0;
        predict_read0_valid_i = '0;
        predict_read0_tag_i = '0;
        predict_read0_index0_i = '0;
        predict_read0_index1_i = '0;
        predict_read0_index2_i = '0;
        predict_read0_index3_i = '0;
        predict_read0_tag0_i = '0;
        predict_read0_tag1_i = '0;
        predict_read0_tag2_i = '0;
        predict_read0_tag3_i = '0;
        predict_read0_base_index_i = '0;
        predict_read1_valid_i = '0;
        predict_read1_tag_i = '0;
        predict_read1_index0_i = '0;
        predict_read1_index1_i = '0;
        predict_read1_index2_i = '0;
        predict_read1_index3_i = '0;
        predict_read1_tag0_i = '0;
        predict_read1_tag1_i = '0;
        predict_read1_tag2_i = '0;
        predict_read1_tag3_i = '0;
        predict_read1_base_index_i = '0;
        ex_predict_train_valid_i = '0;
        ex_predict_train_tag_i = '0;
        ex_predict_train_pc_i = '0;
        ex_predict_train_taken_i = '0;
        ex_predict_train_target_i = '0;
        ex_predict_train_type_i = '0;
        ex_predict_train_fast_index_i = '0;
        ex_predict_train_token_i = '0;
        ex_predict_train_provider_i = '0;
        ex_predict_train_prediction_i = '0;
        ex_predict_train_alternate_i = '0;
        ex_predict_train_index0_i = '0;
        ex_predict_train_index1_i = '0;
        ex_predict_train_index2_i = '0;
        ex_predict_train_index3_i = '0;
        ex_predict_train_tag0_i = '0;
        ex_predict_train_tag1_i = '0;
        ex_predict_train_tag2_i = '0;
        ex_predict_train_tag3_i = '0;
        ex_predict_train_base_index_i = '0;
        mem_predict_train_valid_i = '0;
        mem_predict_train_tag_i = '0;
        mem_predict_train_pc_i = '0;
        mem_predict_train_taken_i = '0;
        mem_predict_train_target_i = '0;
        mem_predict_train_type_i = '0;
        mem_predict_train_fast_index_i = '0;
        mem_predict_train_token_i = '0;
        mem_predict_train_provider_i = '0;
        mem_predict_train_prediction_i = '0;
        mem_predict_train_alternate_i = '0;
        mem_predict_train_index0_i = '0;
        mem_predict_train_index1_i = '0;
        mem_predict_train_index2_i = '0;
        mem_predict_train_index3_i = '0;
        mem_predict_train_tag0_i = '0;
        mem_predict_train_tag1_i = '0;
        mem_predict_train_tag2_i = '0;
        mem_predict_train_tag3_i = '0;
        mem_predict_train_base_index_i = '0;
        age_head_i = '0;
        cancel_valid_i = '0;
        cancel_tag_i = '0;
        tick(); rst_n_i = 1; tick();
    end endtask
    localparam CAPACITY = ISSUE_WIDTH == 2 ? 12 : 8;
    integer seed = 708;
    function automatic integer random_next;
        seed = seed * 1664525 + 1013904223;
        return (seed >> 1) & 'h7fffffff;
    endfunction
    function automatic reg [31:0] instruction(input integer address);
        return (32'((address >> 2)&31) << 15) | 32'h00000013;
    endfunction
    function automatic bit error_value(input integer address);
        return (address & 127) == 28;
    endfunction
    integer resident_pc [0:31];
    integer resident_instr [0:31];
    bit resident_error [0:31];
    integer residents;
    integer pending_pc [0:3];
    integer pending_start [0:3];
    integer pending_delay [0:3];
    integer pending;
    integer next_stream;
    integer sequence_number;
    integer cycles;
    integer cross_lines;
    bit [31:1] owner_model;
    task check_head;
        integer owner_bits;
        integer source_register;
        begin
            if (ib_credit_o !== 4'(CAPACITY - residents - 2*pending))
                $fatal(1,"credit cycle=%0d expected=%0d actual=%0d resident=%0d pending=%0d",
                       cycles,CAPACITY-residents-2*pending,ib_credit_o,residents,pending);
            if (ib_head0_valid_o !== (residents != 0) ||
                ib_head1_valid_o !== (ISSUE_WIDTH == 2 && residents >= 2))
                $fatal(1,"head valid cycle=%0d residents=%0d actual=%b%b",cycles,residents,
                       ib_head1_valid_o,ib_head0_valid_o);
            if (residents > 0) begin
                if (ib_head0_pc_o !== 32'(resident_pc[0]) ||
                    ib_head0_instr_o !== 32'(resident_instr[0]) ||
                    ib_head0_error_o !== resident_error[0])
                    $fatal(1,"head0 cycle=%0d PC expected=%h actual=%h instr=%h/%h error=%b/%b",
                           cycles,resident_pc[0],ib_head0_pc_o,resident_instr[0],ib_head0_instr_o,
                           resident_error[0],ib_head0_error_o);
                if (ib_head0_predict_token_o !== 0 || ib_head0_predict_taken_o !== 0 ||
                    ib_head0_predict_fast_index_o !== 12'(resident_pc[0] >> 2))
                    $fatal(1,"cold prediction snapshot cycle=%0d",cycles);
                if (ib_head0_ras_count_o != 0 || ib_head0_ras_ptr_o != 0)
                    $fatal(1,"cold RAS snapshot cycle=%0d",cycles);
                if (ISSUE_WIDTH == 2) begin
                    if (ib_head0_predict_provider_o != 0 || ib_head0_predict_alternate_o != 0 ||
                        ib_head0_predict_base_index_o != 12'(resident_pc[0] >> 2))
                        $fatal(1,"cold TAGE metadata cycle=%0d",cycles);
                    if (ib_head0_predict_index0_o != 9'(resident_pc[0] >> 2) ||
                        ib_head0_predict_tag0_o != 10'(resident_pc[0] >> 11))
                        $fatal(1,"IB TAGE table0 snapshot cycle=%0d",cycles);
                    if (ib_head0_predict_index1_o != 9'(resident_pc[0] >> 2) ||
                        ib_head0_predict_tag1_o != 10'(resident_pc[0] >> 11))
                        $fatal(1,"IB TAGE table1 snapshot cycle=%0d",cycles);
                    if (ib_head0_predict_index2_o != 9'(resident_pc[0] >> 2) ||
                        ib_head0_predict_tag2_o != 10'(resident_pc[0] >> 11))
                        $fatal(1,"IB TAGE table2 snapshot cycle=%0d",cycles);
                    if (ib_head0_predict_index3_o != 9'(resident_pc[0] >> 2) ||
                        ib_head0_predict_tag3_o != 10'(resident_pc[0] >> 11))
                        $fatal(1,"IB TAGE table3 snapshot cycle=%0d",cycles);
                end
                if (ISSUE_WIDTH == 2) begin
                    if (ib_head0_candidates_o[4] !== 1'((resident_pc[0]>>2)&1))
                        $fatal(1,"physical bank candidate selection cycle=%0d",cycles);
                    owner_bits = (int'(ib_head0_candidates_o) >>
                                  (ib_head0_candidates_o[4] ? 2 : 0)) & 3;
                    source_register = (resident_instr[0] >> 15)&31;
                    if ((owner_bits&1) != int'(source_register != 0 && owner_model[source_register]))
                        $fatal(1,"head0 owner cycle=%0d register=%0d candidates=%b model=%b",cycles,
                               source_register,ib_head0_candidates_o,owner_model);
                end else if (ib_head0_candidates_o !== 0) $fatal(1,"single candidates");
            end
            if (ISSUE_WIDTH == 2 && residents >= 2) begin
                if (ib_head1_pc_o !== 32'(resident_pc[1]) ||
                    ib_head1_instr_o !== 32'(resident_instr[1]) ||
                    ib_head1_error_o !== resident_error[1])
                    $fatal(1,"head1 cycle=%0d PC=%h/%h",cycles,resident_pc[1],ib_head1_pc_o);
                source_register = (resident_instr[1] >> 15)&31;
                if (ib_head1_candidates_o[4] !== 1'((resident_pc[1]>>2)&1))
                    $fatal(1,"head1 physical bank selection cycle=%0d",cycles);
                owner_bits = (int'(ib_head1_candidates_o) >>
                              (ib_head1_candidates_o[4] ? 2 : 0)) & 3;
                if ((owner_bits&1) != int'(source_register != 0 && owner_model[source_register]))
                    $fatal(1,"head1 owner cycle=%0d register=%0d candidates=%b",cycles,
                           source_register,ib_head1_candidates_o);
            end
        end
    endtask
    task run_cycle(input bit redirect_now, input bit hold_consumer);
        integer remove;
        integer start_pc;
        integer base_pc;
        integer even_pc;
        integer odd_pc;
        bit accepted;
        bit returned;
        begin
            @(negedge clk_i);
            cycles++;
            redirect_valid_i = redirect_now;
            frontend_flush_i = redirect_now;
            redirect_pc_i = 32'((random_next()%512)*4);
            fetch_stop_i = (random_next()%11) == 0;
            ic_req_ready_i = (random_next()%5) != 0;
            remove = hold_consumer ? 0 : random_next()%(ISSUE_WIDTH+1);
            if (remove > residents) remove = residents;
            ib_remove_count_i = 2'(remove);
            wb0_valid_i = (random_next()%3) == 0;
            wb1_valid_i = ISSUE_WIDTH == 2 && (random_next()%3) == 0;
            wb0_rd_i = 5'(random_next()%32);
            wb1_rd_i = 5'(random_next()%32);
            if (cycles%20 == 0) begin
                wb0_valid_i=1;wb1_valid_i=(ISSUE_WIDTH==2);wb1_rd_i=wb0_rd_i;
            end
            lvt_i = owner_model;
            ic_resp_valid_i = pending > 0 && pending_delay[0] == 0;
            base_pc = pending > 0 ? pending_pc[0] : 0;
            even_pc = base_pc[2] ? base_pc+4 : base_pc;
            odd_pc = base_pc[2] ? base_pc : base_pc+4;
            ic_resp_bank0_way_hit_i = even_pc[3] ? 2'b10 : 2'b01;
            ic_resp_bank1_way_hit_i = odd_pc[4] ? 2'b10 : 2'b01;
            ic_resp_bank0_way0_instr_i = even_pc[3] ? 32'hfffaab13 : instruction(even_pc);
            ic_resp_bank0_way1_instr_i = even_pc[3] ? instruction(even_pc) : 32'hfffaab13;
            ic_resp_bank1_way0_instr_i = odd_pc[4] ? 32'hfffaab13 : instruction(odd_pc);
            ic_resp_bank1_way1_instr_i = odd_pc[4] ? instruction(odd_pc) : 32'hfffaab13;
            ic_resp_bank0_error_i = error_value(even_pc);
            ic_resp_bank1_error_i = error_value(odd_pc);
            #1;
            accepted = ic_req_valid_o && ic_req_ready_i;
            returned = ic_resp_valid_i && ic_resp_ready_o;
            if (redirect_now) begin
                residents = 0;
                pending = 0;
                next_stream = int'(redirect_pc_i);
                if (!ic_cancel_o || accepted || returned) $fatal(1,"redirect priority");
            end else begin
                for (integer j = 0; j < residents-remove; j++) begin
                    resident_pc[j] = resident_pc[j+remove];
                    resident_instr[j] = resident_instr[j+remove];
                    resident_error[j] = resident_error[j+remove];
                end
                residents -= remove;
                if (returned) begin
                    start_pc = pending_start[0];
                    for (integer j = 0; j < 2; j++) begin
                        if (base_pc + 4*j >= start_pc) begin
                            resident_pc[residents] = base_pc+4*j;
                            resident_instr[residents] = int'(instruction(base_pc+4*j));
                            resident_error[residents] = error_value(base_pc+4*j);
                            residents++;
                        end
                    end
                    for (integer j = 0; j < pending-1; j++) begin
                        pending_pc[j] = pending_pc[j+1];
                        pending_start[j] = pending_start[j+1];
                        pending_delay[j] = pending_delay[j+1];
                    end
                    pending--;
                end
                if (accepted) begin
                    base_pc = ISSUE_WIDTH == 2 ? next_stream : next_stream & -8;
                    if (ic_req_addr_o !== 32'(base_pc))
                        $fatal(1,"request cycle=%0d expected=%h actual=%h",cycles,base_pc,ic_req_addr_o);
                    pending_pc[pending] = base_pc;
                    pending_start[pending] = next_stream;
                    pending_delay[pending] = random_next()%8;
                    if ((base_pc & 31) == 28) begin
                        cross_lines++;
                        pending_delay[pending] += random_next()%12;
                    end
                    pending++;
                    next_stream = base_pc + 8;
                end
            end
            if (wb0_valid_i && wb0_rd_i != 0) owner_model[wb0_rd_i] = 0;
            if (wb1_valid_i && wb1_rd_i != 0) owner_model[wb1_rd_i] = 1;
            tick();
            for (integer j = 0; j < pending; j++)
                if (pending_delay[j] > 0) pending_delay[j]--;
            check_head();
        end
    endtask
    task train(input integer address,input integer kind,input integer target,
               input integer fast_index,input bit token_value);
        begin
            ex_predict_train_valid_i = 1;
            ex_predict_train_pc_i = 32'(address);
            ex_predict_train_type_i = 3'(kind);
            ex_predict_train_target_i = 32'(target);
            ex_predict_train_fast_index_i = 12'(fast_index);
            ex_predict_train_taken_i = 1;
            ex_predict_train_token_i = token_value;
            tick(); ex_predict_train_valid_i = 0; ex_predict_train_token_i = 0;
        end
    endtask
    task controlled_return(input integer address);
        begin
            ic_resp_bank0_way0_instr_i = address[2] ? 32'h000000ef : 32'h00000063;
            ic_resp_bank1_way0_instr_i = address[2] ? 32'h00000063 : 32'h000000ef;
            ic_resp_bank0_way_hit_i = 1;
            ic_resp_bank1_way_hit_i = 1;
            ic_resp_bank0_error_i = 0;
            ic_resp_bank1_error_i = 0;
            ic_resp_valid_i = 1;
            #1;
            if (!ic_resp_ready_o) $fatal(1,"missing F2 capacity address=%h",address);
            tick();ic_resp_valid_i = 0;
        end
    endtask
    initial begin
        initialize();
        residents = 0; pending = 0; next_stream = 0; cycles = 0; cross_lines = 0;
        owner_model = 0;
        // Full physical queue, then randomized removals, response delays and redirects.
        for (integer n = 0; n < 200; n++) run_cycle(0,1);
        if (residents != CAPACITY || pending != 0 || ib_credit_o != 0)
            $fatal(1,"IB full expected=%0d actual=%0d pending=%0d",CAPACITY,residents,pending);
        for (integer n = 0; n < 1600; n++) run_cycle(n%37 == 0,0);
        if (ISSUE_WIDTH == 2 && cross_lines == 0) $fatal(1,"cross-line coverage");
        // Cancel an F1-pushed younger call when the base predictor takes the older branch.
        if (ISSUE_WIDTH == 2) begin
            fetch_stop_i = 1; redirect_valid_i = 1; frontend_flush_i = 1;
            redirect_pc_i = 0; ic_resp_valid_i = 0; ib_remove_count_i = 0;tick();
            redirect_valid_i = 0; frontend_flush_i = 0;
            wb0_valid_i = 0; wb1_valid_i = 0;
            branch_redirect_valid_i = 1;
            branch_redirect_pc_i = 0;
            branch_redirect_ras_data_i = 0;
            branch_redirect_ras_ptr_i = 0;
            branch_redirect_ras_count_i = 0;
            tick();branch_redirect_valid_i = 0;
            train(4,3,512,0,0);
            predict_read0_valid_i = 1;
            predict_read0_tag_i = 0;
            tick();predict_read0_valid_i = 0;
            train(0,0,100,0,1);
            tick();
            ic_req_ready_i = 1;fetch_stop_i = 0;#1;
            if (!ic_req_valid_o || ic_req_addr_o != 0) $fatal(1,"directed request0");
            tick();
            controlled_return(0);fetch_stop_i = 1;
            if (!ic_cancel_o || !ib_head0_valid_o || ib_head1_valid_o ||
                !ib_head0_predict_taken_o || !ib_head0_predict_token_o)
                $fatal(1,"F2 older taken must cancel younger call");
            tick();
            if (ib_credit_o != CAPACITY-1) $fatal(1,"F2 cancel must return younger reservation");
            fetch_stop_i = 0;#1;
            if (ic_req_addr_o != 100) $fatal(1,"older corrected PC");
            tick();fetch_stop_i = 1;ib_remove_count_i = 1;
            controlled_return(100);ib_remove_count_i = 0;
            if (ib_head0_ras_count_o != 0) $fatal(1,"canceled call must not remain in RAS");
            // Expose the younger call when fast is taken and TAGE base is not taken.
            rst_n_i = 0;tick();rst_n_i = 1;
            redirect_valid_i = 1; redirect_pc_i = 8192;tick();redirect_valid_i = 0;
            branch_redirect_valid_i = 1; branch_redirect_pc_i = 8192;
            branch_redirect_ras_data_i = 0;branch_redirect_ras_ptr_i = 0;
            branch_redirect_ras_count_i = 0;tick();branch_redirect_valid_i = 0;
            train(8196,3,8712,0,0);
            train(8712,4,777,0,0);
            train(8192,0,8712,2049,0);
            tick();fetch_stop_i = 0;#1;
            if (ic_req_addr_o != 8192) $fatal(1,"directed request8192");
            tick();
            controlled_return(8192);fetch_stop_i = 1;
            if (ib_head0_predict_provider_o != 0 || ib_head0_predict_alternate_o != 0 ||
                ib_head0_predict_base_index_o != 2048 || ib_head0_predict_fast_index_o != 2049)
                $fatal(1,"live conditional prediction token metadata");
            if (ib_head0_predict_index0_o != 0 || ib_head0_predict_tag0_o != 4)
                $fatal(1,"live TAGE table0 snapshot");
            if (ib_head0_predict_index1_o != 0 || ib_head0_predict_tag1_o != 4)
                $fatal(1,"live TAGE table1 snapshot");
            if (ib_head0_predict_index2_o != 0 || ib_head0_predict_tag2_o != 4)
                $fatal(1,"live TAGE table2 snapshot");
            if (ib_head0_predict_index3_o != 0 || ib_head0_predict_tag3_o != 4)
                $fatal(1,"live TAGE table3 snapshot");

            if (!ic_cancel_o || !ib_head1_valid_o || ib_head0_predict_taken_o ||
                !ib_head1_predict_taken_o || ib_head1_predict_target_o != 8712)
                $fatal(1,"F2 not-taken must expose younger call");
            tick();
            if (ib_credit_o != CAPACITY-2) $fatal(1,"F2 expose must return younger reservation");
            fetch_stop_i = 0;#1;
            if (ic_req_addr_o != 8712) $fatal(1,"F2 corrected target expected=8712 actual=%h",ic_req_addr_o);
            tick();fetch_stop_i = 1;ib_remove_count_i = 2;
            controlled_return(8712);ib_remove_count_i = 0;
            if (!ib_head0_valid_o || ib_head0_predict_target_o != 8200 ||
                ib_head0_ras_count_o != 1)
                $fatal(1,"exposed call RAS restore count=%0d target=%h",ib_head0_ras_count_o,
                       ib_head0_predict_target_o);
        end
        // A stale call BTB entry now names an ordinary ALU after FENCE.I.
        // F2 removes the false taken prediction, restores the call-free prefix,
        // invalidates BTB and preserves both sequential words.
        fetch_stop_i=1;ic_resp_valid_i=0;ib_remove_count_i=0;
        rst_n_i=0;tick();rst_n_i=1;
        redirect_valid_i=1;redirect_pc_i='h3000;tick();redirect_valid_i=0;
        branch_redirect_valid_i=1;branch_redirect_pc_i='h3000;
        branch_redirect_ras_data_i=0;branch_redirect_ras_ptr_i=0;
        branch_redirect_ras_count_i=0;tick();branch_redirect_valid_i=0;
        train('h3000,3,'h3100,0,0);tick();fetch_stop_i=0;ic_req_ready_i=1;
        tick();
        ic_resp_bank0_way0_instr_i=instruction('h3000);
        ic_resp_bank1_way0_instr_i=instruction('h3004);
        ic_resp_bank0_way_hit_i=1;ic_resp_bank1_way_hit_i=1;
        ic_resp_bank0_error_i=0;ic_resp_bank1_error_i=0;
        ic_resp_valid_i=1;tick();ic_resp_valid_i=0;fetch_stop_i=1;
        if(!f2_redirect_valid_o || f2_redirect_cause_o!=3 ||
           f2_redirect_pc_o!='h3000 || f2_redirect_target_o!='h3008 ||
           !ib_head0_valid_o || ib_head0_predict_taken_o || ib_head0_predict_token_o)
            $fatal(1,"noncontrol F2 correction event cause=%0d target=%h",f2_redirect_cause_o,
                   f2_redirect_target_o);
        if(ISSUE_WIDTH==2 && (!ib_head1_valid_o || ib_head1_ras_count_o!=0))
            $fatal(1,"F2 corrected second-word RAS snapshot");
        tick();
        if(ib_credit_o!=CAPACITY-2) $fatal(1,"noncontrol cancellation credit");
        redirect_valid_i=1;redirect_pc_i='h3000;tick();redirect_valid_i=0;
        fetch_stop_i=0;tick();fetch_stop_i=1;
        ic_resp_valid_i=1;tick();ic_resp_valid_i=0;
        if(ib_head0_predict_taken_o || f2_redirect_valid_o || ib_head0_ras_count_o!=0)
            $fatal(1,"noncontrol BTB invalidation / RAS restore");
        // Commit recovery wins over a simultaneous younger branch restoration.
        fetch_stop_i=1;commit_redirect_valid_i=1;commit_redirect_pc_i='h7004;
        redirect_valid_i=1;redirect_pc_i='h8000;
        branch_redirect_valid_i=1;branch_redirect_pc_i='h9000;
        branch_redirect_ras_ptr_i=0;branch_redirect_ras_count_i=3;
        tick();commit_redirect_valid_i=0;redirect_valid_i=0;branch_redirect_valid_i=0;
        fetch_stop_i=0;#1;
        if(ic_req_addr_o !== (ISSUE_WIDTH==2 ? 32'h7004 : 32'h7000))
            $fatal(1,"commit redirect priority PC=%h",ic_req_addr_o);
        tick();fetch_stop_i=1;
        ic_resp_bank0_way0_instr_i=instruction(ISSUE_WIDTH==2 ? 'h7008 : 'h7000);
        ic_resp_bank1_way0_instr_i=instruction('h7004);
        ic_resp_valid_i=1;tick();ic_resp_valid_i=0;
        if(ib_head0_pc_o!='h7004 || ib_head0_ras_count_o!=0 || f2_redirect_valid_o)
            $fatal(1,"commit must not apply younger RAS restore");
        $display("PASS CV08 frontend ISSUE_WIDTH=%0d: credits, errors, cross-line delays, owner/WB, redirect and F2 RAS prefix",ISSUE_WIDTH);
        $finish;
    end
endmodule
